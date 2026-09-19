-- =============================================================================
-- 297_WaterOwnerInjectionIsOwnerMoney.postgres.sql
--
-- Purpose
-- -------
-- An "Owner injection" IS owner money. A "Withdrawal" IS a draw. Stop making the
-- user say so twice.
--
-- The same correction 294/295 made for "Loan received", applied to the other two
-- capital types on the Cash Flow form, and for the same reason: somebody who
-- picks "Owner injection" has already said what it is. Writing a bare
-- cashadjustment row instead leaves the Owner Money page to go looking for it.
--
-- WHERE EACH MODULE STARTED
-- =========================
--   poultry   287 taught the Owner Money page to READ ACROSS into cashadjustment,
--             so the injection at least showed up. This file makes the record
--             real, and teaches that read-across to skip anything it has
--             converted.
--   water     had no equivalent at all -- there is no fnwaterownermoney_legacy.
--             An owner injection typed on /water-cash-flow has NEVER appeared on
--             /water-owner-money. Backfilling is not a tidy-up here; it is the
--             first time that money shows up where it belongs.
--
-- THE SAME CASH TRAP AS THE LOANS, AND THE SAME ANSWER
-- ====================================================
-- spwaterownermoney_record writes its own cash row AND moves a cash account
-- balance. The adjustment it would be built from is ALREADY a cash event that
-- Cash Flow reads. So a naive backfill counts the money twice.
--
-- So a BACKFILLED record is written with NO cash row and NO account movement --
-- the adjustment stays the cash event, the record is the capital record beside
-- it -- and three readers are taught to respect that:
--
--   spwatercashflow_rows   its owner-money arm skips a backfilled record
--                (section 3). This is exactly the guard 292's stage check
--                caught the hard way for loans.
--   the legacy read      skips an adjustment once a record points at it
--   the unique index     one record per adjustment, so two runs cannot both win
--
-- Net effect on every number: NOTHING MOVES. Cash flow, the cash accounts, the
-- P&L and the owner's capital are identical afterwards. What changes is that the
-- money is finally ON the Owner Money page as a first-class record.
--
-- WHY THE ACCOUNT CONSTRAINT HAS TO GIVE
-- ======================================
-- waterownermoney.watercashaccountid was NOT NULL, which is right for a record somebody
-- typed into the Owner Money form -- that form asks which account the money
-- went into. A historical adjustment has no account at all: the legacy
-- cashadjustment table predates cash accounts and Cash Flow reports those rows
-- with cashaccountid NULL.
--
-- Inventing an account would be worse than leaving it blank: it would attribute
-- money to a till that never received it, and the next person to reconcile that
-- till would find a number they cannot explain. So the column becomes nullable
-- for backfilled rows only. Both writers that CREATE owner money still require
-- an account -- the Owner Money form always did, and the Cash Flow form now
-- does too.
--
-- NEW ENTRIES DO NOT COME THROUGH HERE AT ALL
-- ===========================================
-- The Cash Flow form now calls spwaterownermoney_record directly for these two
-- types, which writes a real record with a real cash row against a real account.
-- That is what makes this backfill a ONE-OFF rather than a job that has to keep
-- running.
--
-- Order: after 296.
--
-- Idempotent throughout -- the backfill skips anything already converted.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The link, and the relaxed account.
-- -----------------------------------------------------------------------------
ALTER TABLE waterownermoney
    ADD COLUMN IF NOT EXISTS sourceadjustmentid integer NULL;

ALTER TABLE waterownermoney ALTER COLUMN watercashaccountid DROP NOT NULL;

COMMENT ON COLUMN waterownermoney.sourceadjustmentid IS
    'The cashadjustment this record was backfilled from (297). When set, the cash '
    'for it is the ADJUSTMENT, not an owner-money cash row -- which is why such a '
    'record has no watercashtransactionid and may have no cash account. Every reader '
    'that could double-count it is taught to skip it.';

COMMENT ON COLUMN waterownermoney.watercashaccountid IS
    'Which account the money moved through. NULL only on a record backfilled '
    'from a Cash Flow adjustment (297), which never had one -- the legacy '
    'cashadjustment table predates cash accounts. Both writers that CREATE owner '
    'money require it.';

CREATE UNIQUE INDEX IF NOT EXISTS ux_waterownermoney_sourceadjustment
    ON waterownermoney (sourceadjustmentid)
    WHERE sourceadjustmentid IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 2. The backfill writer.
--
-- Deliberately NOT a call to spwaterownermoney_record: that one writes a cash
-- row and moves a balance, and neither may happen here. The money already
-- arrived, as the adjustment.
--
-- The TYPE selects which adjustments count; the SIGN decides direction, exactly
-- as 287 reads the same table and as spwatercashflow_rows already does
-- (`CASE WHEN ca.amount >= 0 THEN 'CashIn'`). That stays right even when
-- somebody records a correction to an injection as a negative 'OwnerInjection',
-- which classifying by type alone would report as money going IN.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterownermoney_fromadjustment(
    p_farmid       text,
    p_adjustmentid integer,
    p_ownername    text DEFAULT NULL,
    p_createdby    text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_tbl    text;
    v_date   timestamp;
    v_amount numeric(14,2);
    v_desc   text;
    v_type   text;
    v_id     integer;
BEGIN
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);
    IF v_tbl IS NULL THEN
        RAISE EXCEPTION 'There are no cash adjustments on this database to convert.';
    END IF;

    EXECUTE format($sql$
        SELECT ca.adjustmentdate::timestamp, ca.amount::numeric(14,2),
               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text
        FROM   %s ca
        WHERE  ca.adjustmentid = $1
          AND  lower(ca.farmid::text) = lower($2)
          AND  ca.adjustmenttype IN ('OwnerInjection', 'Withdrawal')
    $sql$, v_tbl)
    INTO v_date, v_amount, v_desc
    USING p_adjustmentid, p_farmid;

    IF v_date IS NULL THEN
        RAISE EXCEPTION
          'Cash adjustment % is not an owner injection or withdrawal for this company.',
          p_adjustmentid;
    END IF;
    IF v_amount = 0 THEN
        RAISE EXCEPTION 'Cash adjustment % is for zero and is not a capital event.',
          p_adjustmentid;
    END IF;

    IF EXISTS (SELECT 1 FROM waterownermoney o WHERE o.sourceadjustmentid = p_adjustmentid) THEN
        RAISE EXCEPTION 'Cash adjustment % is already recorded as owner money.',
          p_adjustmentid;
    END IF;

    -- The sign decides, not the type. The record stores a POSITIVE amount with
    -- the direction in transactiontype -- 253's rule -- so a negative
    -- 'OwnerInjection' (a correction) becomes a Draw rather than a negative
    -- contribution, which the table's CHECK (amount > 0) would reject anyway.
    v_type := CASE WHEN v_amount >= 0 THEN 'Contribution' ELSE 'Draw' END;

    -- No cash row, no balance change, no account. See the header.
    INSERT INTO waterownermoney (
        farmid, transactiondate, transactiontype, amount, watercashaccountid,
        ownername, notes, status, createdby, sourceadjustmentid)
    VALUES (
        p_farmid, v_date, v_type, abs(v_amount), NULL,
        NULLIF(btrim(COALESCE(p_ownername, '')), ''),
        btrim('Backfilled from Cash Flow adjustment #' || p_adjustmentid::text
              || ' (' || v_amount::text || ') on '
              || to_char((now() at time zone 'utc'), 'YYYY-MM-DD')
              || COALESCE('. Original note: ' || NULLIF(v_desc, ''), '')),
        'Posted', p_createdby, p_adjustmentid)
    RETURNING waterownermoneyid INTO v_id;

    UPDATE waterownermoney
    SET    transactionnumber =
               CASE WHEN v_type = 'Contribution' THEN 'OWN-' ELSE 'OWD-' END
               || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  waterownermoneyid = v_id;

    RETURN v_id;
END;
$function$;

COMMENT ON FUNCTION public.spwaterownermoney_fromadjustment(text, integer, text, text) IS
    'Record a Cash Flow owner injection or withdrawal as real owner money. '
    'Writes NO cash row, moves NO balance and takes NO account -- the adjustment '
    'remains the cash event. Type selects, sign decides direction, amount is '
    'stored positive.';

-- -----------------------------------------------------------------------------
-- 3. Cash Flow must not count the same money twice.
--
-- Reproduced from the LIVE definition with ONE predicate added, marked 297.
-- Every other arm -- receipts, counter sales, expenses, transfers, loans,
-- repayments, the legacy adjustments -- is byte for byte what it was.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwatercashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text)
 LANGUAGE plpgsql
 STABLE
AS $function$

DECLARE

    v_tbl  text;

    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);

    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);

BEGIN

    -- ---- 1. customer receipts, dated when the money arrived -----------------

    RETURN QUERY

    SELECT 'Receipt'::text,

           FALSE,

           p.waterpaymentid,

           NULL::integer,

           NULL::text,

           p.paymentdate,

           'CashIn'::text,

           'CustomerPayment'::text,

           p.watersaleid,

           FALSE,

           COALESCE(p.amount, 0)::numeric,

           COALESCE(NULLIF(btrim(p.note), ''),

                    NULLIF(btrim(p.reference), ''),

                    'Payment for sale #' || p.watersaleid::text)::text,

           'OperatingIn'::text

    FROM   waterpayments p

    WHERE  lower(p.farmid::text) = lower(p_farmid)

      AND  COALESCE(p.amount, 0) <> 0

      -- A REVERSED payment is money that came back. 227 added this column and

      -- flips it on reversal rather than deleting the row, so without this filter

      -- the report counts a refunded receipt as income for ever.

      AND  COALESCE(p.status, 'Posted') = 'Posted'

      AND  p.paymentdate >= v_from

      AND  p.paymentdate <= v_to;



    -- ---- 2. the part paid at the point of sale -----------------------------

    -- Same reasoning as 235: a sale settled on the spot may never create a

    -- payment row, and the difference is what picks those up.

    RETURN QUERY

    SELECT 'SaleResidual'::text,

           FALSE,

           s.watersaleid,

           NULL::integer,

           NULL::text,

           s.saledate,

           'CashIn'::text,

           'Sale'::text,

           s.watersaleid,

           FALSE,

           v.residual,

           ('Sale #' || s.watersaleid::text)::text,

           'OperatingIn'::text

    FROM   watersales s

    CROSS  JOIN LATERAL (

        SELECT ROUND(

                   CASE WHEN COALESCE(s.status, '') = 'Paid'

                        THEN COALESCE(s.totalamount, 0)

                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),

                                   COALESCE(s.totalamount, 0))

                   END

                 - COALESCE((SELECT SUM(wp.amount)

                             FROM   waterpayments wp

                             WHERE  wp.watersaleid = s.watersaleid

                               AND  lower(wp.farmid::text) = lower(p_farmid)

                               -- Same reason: a reversed payment never covered

                               -- anything, so it must not reduce the residual.

                               AND  COALESCE(wp.status, 'Posted') = 'Posted'), 0)

               , 2) AS residual

    ) v

    WHERE  lower(s.farmid::text) = lower(p_farmid)

      -- A cancelled sale is not income, whatever it once recorded as paid.

      AND  COALESCE(s.status, '') <> 'Cancelled'

      AND  v.residual > 0

      AND  s.saledate >= v_from

      AND  s.saledate <= v_to;



    -- ---- 3. money paid out when the bill was recorded -----------------------

    -- 236's gates are kept verbatim -- Approved, not deleted -- with two

    -- changes:

    --

    --   * the AMOUNT is what was actually paid at entry, not the whole bill:

    --     the resolved amountpaid, less anything a supplier payment has since

    --     covered (which the next arm reports on its own, later, date);

    --   * the `paymentmethod <> 'Credit'` filter is GONE, because the resolution

    --     subsumes it. A Credit bill resolves to 0 paid and drops out on

    --     `paidatentry > 0` instead -- same rows excluded, and a Credit bill

    --     that has since been part-paid is no longer wrongly invisible.

    RETURN QUERY

    SELECT 'Expense'::text,

           FALSE,

           e.waterexpenseid,

           e.watercashaccountid,

           NULL::text,

           e.expensedate,

           'CashOut'::text,

           'Expense'::text,

           e.waterexpenseid,

           FALSE,

           -v.paidatentry,

           COALESCE(NULLIF(btrim(e.description), ''),

                    NULLIF(btrim(e.paidto), ''),

                    'Expense #' || e.waterexpenseid::text)::text,

           'OperatingOut'::text

    FROM   waterexpenses e

    CROSS  JOIN LATERAL (

        SELECT GREATEST(

                   COALESCE(e.amountpaid,

                            CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'

                                 THEN 0 ELSE e.amount END)

                 - COALESCE((SELECT SUM(sa.amountapplied)

                             FROM   supplierpaymentallocation sa

                             WHERE  sa.farmid = p_farmid

                               AND  sa.module = 'water'

                               AND  sa.status = 'Posted'

                               AND  sa.documenttype = 'Expense'

                               AND  sa.documentid = e.waterexpenseid), 0)

               , 0)::numeric AS paidatentry

    ) v

    WHERE  lower(e.farmid::text) = lower(p_farmid)

      AND  COALESCE(e.isdeleted, false) = false

      AND  v.paidatentry > 0

      -- 047's rule: only an approved expense has been recognised at all.

      AND  COALESCE(e.status, '') = 'Approved'

      -- 259. 'NonCash' means "a cost recorded, but the money moved elsewhere".

      -- Loan interest and fees are written this way: the repayment's own arm

      -- below reports the FULL amount that left the account, so counting these

      -- rows here as well would take 12,500 out of the bank and 15,000 off the

      -- cash flow. Expense reports do not filter NonCash, so the cost still

      -- counts where it should.

      --

      -- No-op on today's data: there are zero water expenses with this marker.

      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'

      AND  e.expensedate >= v_from

      AND  e.expensedate <= v_to;



    -- ---- 3b. money paid out later, against a bill already recorded ----------

    -- A supplier payment settling a bill. It belongs to the day the money moved,

    -- not the day the bill was entered.

    --

    -- Only documenttype='Expense'. A payment against a raw-material purchase

    -- books its own aggregated expense row dated the payment date (240) and is

    -- already counted by arm 3; adding it here would double it.

    RETURN QUERY

    SELECT 'ExpensePayment'::text,

           FALSE,

           sa.allocationid,

           sp.watercashaccountid,

           NULL::text,

           sp.paymentdate,

           'CashOut'::text,

           'ExpensePayment'::text,

           sa.documentid,

           FALSE,

           -sa.amountapplied::numeric,

           ('Payment for expense #' || sa.documentid::text ||

            COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,

           'OperatingOut'::text

    FROM   supplierpaymentallocation sa

    JOIN   watersupplierpayments sp

           ON  sp.watersupplierpaymentid = sa.paymentid

           AND sp.farmid = sa.farmid

    LEFT   JOIN watersuppliers s

           ON  s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid

    WHERE  sa.farmid = p_farmid

      AND  sa.module = 'water'

      AND  sa.status = 'Posted'

      AND  sa.documenttype = 'Expense'

      AND  COALESCE(sp.status, 'Posted') = 'Posted'

      AND  sa.amountapplied <> 0

      AND  sp.paymentdate >= v_from

      AND  sp.paymentdate <= v_to;



    -- ---- 4. owner money (258) ----------------------------------------------

    -- Contributions and draws recorded through the Owner Money module.

    -- FINANCING, not operating: the owner funded the business or took funding

    -- back. Never revenue, never expense.

    --

    -- Reversed records are dropped entirely rather than netted to zero with a

    -- second row -- a contribution that was put in and taken back out is not

    -- funding, and showing both legs would put money the business never kept

    -- into Money In and Money Out.

    --

    -- Placed ABOVE the legacy capital arm on purpose: that arm RETURNs early

    -- when cashadjustment is absent, so anything below it is skipped on a

    -- company with no capital records.

    RETURN QUERY

    SELECT 'OwnerMoney'::text,

           FALSE,

           o.waterownermoneyid,

           o.watercashaccountid,

           a.accountname::text,

           o.transactiondate,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'CashIn' ELSE 'CashOut' END::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END::text,

           o.waterownermoneyid,

           FALSE,

           -- Stored positive; the sign is applied here, once.

           (CASE WHEN o.transactiontype = 'Contribution' THEN o.amount ELSE -o.amount END)::numeric,

           COALESCE(NULLIF(btrim(o.notes), ''),

                    NULLIF(btrim(o.ownername), ''),

                    CASE WHEN o.transactiontype = 'Contribution'

                         THEN 'Owner contribution' ELSE 'Owner draw' END)::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'FinancingIn' ELSE 'FinancingOut' END::text

    FROM   waterownermoney o

    LEFT   JOIN watercashaccounts a

           ON a.watercashaccountid = o.watercashaccountid

    WHERE  o.farmid = p_farmid

      AND  o.status = 'Posted'
      -- 297. A record backfilled from a Cash Flow adjustment has NO cash
      -- row of its own: the ADJUSTMENT is still the cash event, and the
      -- legacy adjustment arm below already reports it. Without this the
      -- same money is counted twice -- the trap 292 hit for loans.
      AND  o.sourceadjustmentid IS NULL

      AND  o.transactiondate >= v_from

      AND  o.transactiondate <= v_to;



    -- ---- 5. loans received (259) -------------------------------------------

    -- Borrowed money arriving. FINANCING: the business received it, it did not

    -- earn it, so it is money in and never revenue.

    --

    -- The AMOUNT RECEIVED, not the principal. A lender that withholds a fee

    -- pays out less than it lends, and only what arrived is cash in.

    --

    -- The timestamp carries 256's rule, baked in from the start rather than

    -- patched afterwards as it had to be on poultry: loandate is a DATE, so a

    -- plain cast gives midnight and a loan recorded this afternoon sorts below

    -- everything else recorded today. A loan dated TODAY reports the moment it

    -- was recorded; a BACK-DATED one keeps midnight, because using createdat

    -- unconditionally would drag last Tuesday's loan into today, above rows

    -- that really did happen after it.

    RETURN QUERY

    SELECT 'Loan'::text,

           FALSE,

           l.waterloanid,

           l.watercashaccountid,

           a.accountname::text,

           CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                ELSE l.loandate::timestamp END,

           'CashIn'::text,

           'LoanReceived'::text,

           l.waterloanid,

           FALSE,

           l.amountreceived::numeric,

           ('Loan received from ' || l.lendername)::text,

           'FinancingIn'::text

    FROM   waterloans l

    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = l.watercashaccountid

    WHERE  l.farmid = p_farmid

      AND  l.amountreceived > 0

      -- 293. A loan converted from a Cash Flow adjustment has NO cash row of

      -- its own: the ADJUSTMENT is the cash event, and the legacy adjustment arm

      -- already reports it. Without this the same borrowing is money-in twice --

      -- which is precisely what 292's stage check caught on the poultry side.

      AND  l.sourceadjustmentid IS NULL

      AND  l.status NOT IN ('Cancelled', 'Reversed', 'Draft')

      AND  (CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                 ELSE l.loandate::timestamp END) >= v_from

      AND  (CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                 ELSE l.loandate::timestamp END) <= v_to;



    -- ---- 6. loan repayments (259) ------------------------------------------

    -- The FULL payment leaves the account, so the full payment is money out --

    -- principal, interest and fees together.

    --

    -- This does NOT double count the interest and fee expenses those payments

    -- create: they are written paymentmethod = 'NonCash', and arm 3 above now

    -- skips NonCash. Expense reports read the expense table directly and still

    -- count them, which is the whole point -- cash out is 12,500, cost is 2,500.

    RETURN QUERY

    SELECT 'LoanPayment'::text,

           FALSE,

           p.waterloanpaymentid,

           p.watercashaccountid,

           a.accountname::text,

           p.paymentdate,

           'CashOut'::text,

           'LoanRepayment'::text,

           p.waterloanid,

           FALSE,

           -p.totalamount::numeric,

           ('Loan repayment to ' || l.lendername)::text,

           'FinancingOut'::text

    FROM   waterloanpayments p

    JOIN   waterloans l ON l.waterloanid = p.waterloanid

    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = p.watercashaccountid

    WHERE  p.farmid = p_farmid

      AND  p.status = 'Posted'

      AND  p.paymentdate >= v_from

      AND  p.paymentdate <= v_to;



    -- ---- 7. capital in and out (legacy cash adjustments) --------------------

    -- Expected to return nothing on Water today -- see 236's header note.

    --

    -- MUST STAY LAST: it RETURNs early when the table is absent, and anything

    -- below it would be silently skipped.

    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,

                      to_regclass('public.cashadjustments')::text);



    IF v_tbl IS NULL THEN

        RETURN;

    END IF;



    RETURN QUERY EXECUTE format($sql$

        SELECT 'Adjustment'::text,

               FALSE,

               ca.adjustmentid,

               NULL::integer,

               NULL::text,

               ca.adjustmentdate,

               CASE WHEN ca.amount >= 0 THEN 'CashIn' ELSE 'CashOut' END::text,

               COALESCE(NULLIF(btrim(ca.adjustmenttype), ''), 'Adjustment')::text,

               ca.adjustmentid,

               FALSE,

               ca.amount::numeric,

               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text,

               CASE WHEN ca.amount >= 0 THEN 'FinancingIn' ELSE 'FinancingOut' END::text

        FROM   %s ca

        WHERE  lower(ca.farmid::text) = lower($1)

          AND  ca.amount <> 0

          AND  ca.adjustmentdate >= $2

          AND  ca.adjustmentdate <= $3

    $sql$, v_tbl)

    USING p_farmid, v_from, v_to;

END;

$function$;

-- -----------------------------------------------------------------------------
-- 5. The backfill. Nobody clicks anything.
-- -----------------------------------------------------------------------------
DO $backfill$
DECLARE
    v_tbl text;
    r     record;
    v_n   integer := 0;
BEGIN
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);
    IF v_tbl IS NULL THEN
        RAISE NOTICE '297: no cashadjustment table -- nothing to backfill.';
        RETURN;
    END IF;

    FOR r IN EXECUTE format($sql$
        SELECT ca.adjustmentid, ca.farmid::text AS farmid, ca.userid::text AS userid
        FROM   %s ca
        JOIN   farms f ON lower(f.farmid::text) = lower(ca.farmid::text)
        WHERE  ca.adjustmenttype IN ('OwnerInjection', 'Withdrawal')
          AND  ca.amount <> 0
          AND  f.type = 'Water'
          AND  NOT EXISTS (SELECT 1 FROM waterownermoney o
                           WHERE o.sourceadjustmentid = ca.adjustmentid)
        ORDER  BY ca.adjustmentid
    $sql$, v_tbl)
    LOOP
        PERFORM spwaterownermoney_fromadjustment(
            p_farmid       => r.farmid,
            p_adjustmentid => r.adjustmentid,
            p_ownername    => NULL,
            p_createdby    => r.userid);
        v_n := v_n + 1;
    END LOOP;

    RAISE NOTICE '297: backfilled % Cash Flow capital entr(ies) into owner money.', v_n;
END
$backfill$;

-- -----------------------------------------------------------------------------
-- 6. Grants.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.spwaterownermoney_fromadjustment(
            text, integer, text, text) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'the link column exists' AS check,
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                         WHERE table_name = 'waterownermoney' AND column_name = 'sourceadjustmentid')
            THEN 'OK' ELSE 'MISSING' END AS result

UNION ALL
SELECT 'one record per adjustment is enforced',
       CASE WHEN EXISTS (SELECT 1 FROM pg_indexes
                         WHERE indexname = 'ux_waterownermoney_sourceadjustment')
            THEN 'OK' ELSE 'MISSING' END

UNION ALL
SELECT 'cash flow skips backfilled records',
       CASE WHEN position('sourceadjustmentid' in pg_get_functiondef(p.oid)) > 0
            THEN 'OK' ELSE 'NOT WIRED -- the money would be counted twice' END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname = 'spwatercashflow_rows'

UNION ALL
SELECT 'nothing is left unrecorded',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   (SELECT ca.adjustmentid
        FROM   cashadjustment ca
        JOIN   farms f ON lower(f.farmid::text) = lower(ca.farmid::text)
        WHERE  ca.adjustmenttype IN ('OwnerInjection', 'Withdrawal')
          AND  ca.amount <> 0 AND f.type = 'Water'
          AND  NOT EXISTS (SELECT 1 FROM waterownermoney o
                           WHERE o.sourceadjustmentid = ca.adjustmentid)) x

UNION ALL
SELECT 'no backfilled record moved cash',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   waterownermoney o
WHERE  o.sourceadjustmentid IS NOT NULL AND o.watercashtransactionid IS NOT NULL;
