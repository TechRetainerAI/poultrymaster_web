-- =============================================================================
-- 295_WaterLoanReceivedIsALoan.postgres.sql
--
-- Purpose
-- -------
-- A "Loan received" IS a loan. Stop making the user say so twice.
--
-- WHAT WAS WRONG WITH 293
-- =======================
-- 291 surfaced Cash Flow borrowings on the Loans page and counted them as debt.
-- 293 gave them a repayment path -- behind a button labelled "Make it a loan".
--
-- That button was the mistake. Somebody who picks "Loan received" has ALREADY
-- said it is a loan; asking them to convert it afterwards is the system handing
-- its own bookkeeping back to the user. The fix is not a better button, it is to
-- stop producing the thing the button was cleaning up after.
--
-- So this file closes the gap at both ends:
--
--   the past      every existing LoanReceived adjustment becomes a loan here,
--                 once, with no one clicking anything (section 3).
--   the future    the Cash Flow page now calls the loan create directly when
--                 the type is "Loan received", so no new bare adjustment of
--                 that kind is ever written. That is the frontend half, and it
--                 is what makes this backfill a ONE-OFF rather than a job that
--                 has to keep running.
--
-- THE LENDER, AND WHY THE CONSTRAINT HAS TO GIVE
-- ==============================================
-- waterloans.lendername was NOT NULL, which is right for a loan somebody typed
-- into the loan form -- that form asks. But a historical adjustment never
-- captured one, and there is nothing to recover it from. The choices were:
--
--   invent one ('Unknown', 'Not recorded')   a fiction in the loan book that
--                                            reads exactly like a real lender.
--   refuse to backfill                       leaves the dead end 292 existed to
--                                            remove, which is the whole point.
--   let it be NULL                           honest: we do not know, the page
--                                            says "Lender not recorded", and
--                                            the owner can fill it in.
--
-- The third. A blank that admits it is blank beats a placeholder that lies. New
-- loans still get a lender because both writers that create one -- the loan form
-- and now the Cash Flow form -- require it; this only relaxes what the TABLE
-- insists on, for rows that genuinely predate the question being asked.
--
-- EFFECT ON TODAY'S NUMBERS
-- =========================
-- None, and this is the same argument 293 made. A backfilled loan carries NO
-- cash row: the adjustment it came from is still the cash event, 293's guard
-- keeps the cash-flow loans arm from counting it a second time, and 290's legacy
-- read already skips an adjustment once a loan points at it. So cash flow, the
-- cash accounts, the P&L and what the company owes are all identical afterwards.
--
-- What DOES change is that every one of those debts is now repayable, and the
-- Loans page stops showing rows that cannot be acted on.
--
-- WHAT IS DELIBERATELY LEFT ALONE
-- ===============================
-- NEGATIVE LoanReceived adjustments. A negative one is a CORRECTION to an
-- over-stated borrowing, not a borrowing -- waterloans has
-- CHECK (originalprincipal > 0) and would reject it anyway. Those stay as
-- adjustments, 291's legacy read keeps netting them off against the debt, and
-- the Cash Flow page keeps handling them the way it always has.
--
-- Order: after 294.
--
-- Idempotent throughout -- section 3 skips anything already converted, so
-- running it twice backfills nothing twice.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Refuse to run out of order.
-- -----------------------------------------------------------------------------
DO $guard$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public' AND p.proname = 'spwaterloan_fromadjustment'
    ) THEN
        RAISE EXCEPTION '295 requires 293 (spwaterloan_fromadjustment is missing).';
    END IF;
END
$guard$;

-- -----------------------------------------------------------------------------
-- 1. A loan may have no lender, when nobody was ever asked.
-- -----------------------------------------------------------------------------
ALTER TABLE waterloans ALTER COLUMN lendername DROP NOT NULL;

COMMENT ON COLUMN waterloans.lendername IS
    'Who lent the money. NULL only on a loan backfilled from a Cash Flow '
    '"Loan received" adjustment (294), which never captured one -- the page '
    'shows "Lender not recorded" and it can be edited in. Both writers that '
    'CREATE a loan require it.';

-- -----------------------------------------------------------------------------
-- 2. The conversion accepts a missing lender, for the backfill only.
--
-- Reproduced from 293 with one refusal relaxed. Everything else -- the
-- LoanReceived check, the positive-amount check, the already-converted check,
-- the no-cash-row rule and the audit trail in the notes -- is unchanged.
--
-- The interactive path still supplies a lender: the Cash Flow form now requires
-- one before it will save. This only stops the SP from rejecting a row that
-- predates that form.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterloan_fromadjustment(
    p_farmid          text,
    p_adjustmentid    integer,
    p_lendername      text,
    p_lendertype      text    DEFAULT 'Other',
    p_accountnumber   text    DEFAULT NULL,
    p_interestrate    numeric DEFAULT NULL,
    p_interesttype    text    DEFAULT NULL,
    p_termmonths      integer DEFAULT NULL,
    p_paymentfrequency text   DEFAULT NULL,
    p_enddate         date    DEFAULT NULL,
    p_nextpaymentdate date    DEFAULT NULL,
    p_notes           text    DEFAULT NULL,
    p_createdby       text    DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_tbl    text;
    v_date   date;
    v_amount numeric(14,2);
    v_desc   text;
    v_id     integer;
BEGIN
    -- 295. No longer refused. A blank lender is how a BACKFILLED row says "this
    -- predates anyone being asked"; the loan book shows it as not recorded
    -- rather than inventing a name. Every interactive caller still sends one.
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);
    IF v_tbl IS NULL THEN
        RAISE EXCEPTION 'There are no cash adjustments on this database to convert.';
    END IF;

    EXECUTE format($sql$
        SELECT ca.adjustmentdate::date, ca.amount::numeric(14,2),
               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text
        FROM   %s ca
        WHERE  ca.adjustmentid = $1
          AND  lower(ca.farmid::text) = lower($2)
          AND  ca.adjustmenttype = 'LoanReceived'
    $sql$, v_tbl)
    INTO v_date, v_amount, v_desc
    USING p_adjustmentid, p_farmid;

    IF v_date IS NULL THEN
        RAISE EXCEPTION 'Cash adjustment % is not a "Loan received" entry for this company.',
              p_adjustmentid;
    END IF;

    IF v_amount <= 0 THEN
        RAISE EXCEPTION
          'Cash adjustment % is for %, which is a correction rather than a borrowing. '
          'Corrections cannot become loans -- they reduce one.', p_adjustmentid, v_amount;
    END IF;

    IF EXISTS (SELECT 1 FROM waterloans l WHERE l.sourceadjustmentid = p_adjustmentid) THEN
        RAISE EXCEPTION 'Cash adjustment % has already been made into a loan.', p_adjustmentid;
    END IF;

    INSERT INTO waterloans (
        farmid, lendername, lendertype, accountnumber, loandate,
        originalprincipal, amountreceived,
        interestrate, interesttype, termmonths, paymentfrequency,
        startdate, enddate, nextpaymentdate,
        outstandingprincipal, status, notes, createdby, sourceadjustmentid)
    VALUES (
        p_farmid, NULLIF(btrim(COALESCE(p_lendername, '')), ''),   -- 294
        COALESCE(p_lendertype, 'Other'),
        NULLIF(btrim(p_accountnumber), ''), v_date,
        v_amount, v_amount,
        p_interestrate, p_interesttype, p_termmonths, p_paymentfrequency,
        v_date, p_enddate, p_nextpaymentdate,
        v_amount, 'Active',
        btrim(COALESCE(NULLIF(btrim(p_notes), '') || chr(10), '')
              || 'Converted from Cash Flow adjustment #' || p_adjustmentid::text
              || ' (' || v_amount::text || ') on '
              || to_char((now() at time zone 'utc'), 'YYYY-MM-DD')
              || COALESCE('. Original note: ' || NULLIF(v_desc, ''), '')),
        p_createdby, p_adjustmentid)
    RETURNING waterloanid INTO v_id;

    UPDATE waterloans
    SET    loannumber = 'LN-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  waterloanid = v_id;

    RETURN v_id;
END;
$function$;

COMMENT ON FUNCTION public.spwaterloan_fromadjustment(text, integer, text, text, text, numeric, text, integer, text, date, date, text, text) IS
    'Turn a Cash Flow "Loan received" adjustment into a real, repayable loan. '
    'Writes NO cash row and moves NO balance -- the adjustment remains the cash '
    'event. Since 294 the lender may be blank, which is how a backfilled row '
    'says nobody was ever asked. Refuses a non-LoanReceived row, a negative '
    'amount (that is a correction) and a second conversion.';

-- -----------------------------------------------------------------------------
-- 3. The backfill. Nobody clicks anything.
--
-- One loan per existing positive LoanReceived adjustment that does not already
-- have one. Re-running finds nothing left to do, because the loans written on
-- the first pass are exactly what the NOT EXISTS excludes on the second.
-- -----------------------------------------------------------------------------
DO $backfill$
DECLARE
    v_tbl  text;
    r      record;
    v_n    integer := 0;
BEGIN
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);
    IF v_tbl IS NULL THEN
        RAISE NOTICE '295: no cashadjustment table -- nothing to backfill.';
        RETURN;
    END IF;

    FOR r IN EXECUTE format($sql$
        SELECT ca.adjustmentid, ca.farmid::text AS farmid, ca.userid::text AS userid
        FROM   %s ca
        JOIN   farms f ON lower(f.farmid::text) = lower(ca.farmid::text)
        WHERE  ca.adjustmenttype = 'LoanReceived'
          AND  ca.amount > 0
          AND  f.type = 'Water'
          AND  NOT EXISTS (SELECT 1 FROM waterloans l
                           WHERE l.sourceadjustmentid = ca.adjustmentid)
        ORDER  BY ca.adjustmentid
    $sql$, v_tbl)
    LOOP
        PERFORM spwaterloan_fromadjustment(
            p_farmid       => r.farmid,
            p_adjustmentid => r.adjustmentid,
            p_lendername   => NULL,        -- 295. Not known, and not invented.
            p_createdby    => r.userid);
        v_n := v_n + 1;
    END LOOP;

    RAISE NOTICE '295: backfilled % Cash Flow borrowing(s) into loans.', v_n;
END
$backfill$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'a loan may now have no lender' AS check,
       CASE WHEN (SELECT is_nullable FROM information_schema.columns
                  WHERE table_name = 'waterloans' AND column_name = 'lendername') = 'YES'
            THEN 'OK' ELSE 'STILL NOT NULL' END AS result

UNION ALL
-- The point of the whole file: no positive borrowing is left unrepayable.
SELECT 'no unconverted borrowing is left',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   (SELECT ca.adjustmentid
        FROM   cashadjustment ca
        JOIN   farms f ON lower(f.farmid::text) = lower(ca.farmid::text)
        WHERE  ca.adjustmenttype = 'LoanReceived' AND ca.amount > 0
          AND  f.type = 'Water'
          AND  NOT EXISTS (SELECT 1 FROM waterloans l
                           WHERE l.sourceadjustmentid = ca.adjustmentid)) x

UNION ALL
-- And every backfilled loan is repayable: a real id, active, with debt on it.
SELECT 'every backfilled loan is repayable',
       CASE WHEN COUNT(*) FILTER (
                WHERE l.waterloanid <= 0 OR l.status <> 'Active'
                   OR l.outstandingprincipal <= 0) = 0
            THEN 'OK' ELSE 'SOME ARE NOT' END
FROM   waterloans l WHERE l.sourceadjustmentid IS NOT NULL

UNION ALL
-- No backfilled loan carries a cash row: the adjustment is still the cash event.
SELECT 'no backfilled loan moved cash',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   waterloans l
WHERE  l.sourceadjustmentid IS NOT NULL AND l.watercashtransactionid IS NOT NULL;
