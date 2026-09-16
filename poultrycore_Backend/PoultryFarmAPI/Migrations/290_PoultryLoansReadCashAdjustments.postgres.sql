-- =============================================================================
-- 290_PoultryLoansReadCashAdjustments.postgres.sql
--
-- Purpose
-- -------
-- Make the Loans page show the borrowings that were recorded on the Cash and
-- Cash Flow pages.
--
-- The exact mirror of 287, which did this for Owner Money -- and which
-- deliberately left LoanReceived alone, saying "borrowed money, not owner money.
-- The Loans module (254) owns it." This is the file that makes that true.
--
-- THE GAP
-- =======
-- There are two ways to record the farm borrowing money, and they write to
-- different tables:
--
--   /cash and /cash-flow   POST /Cash/Adjustment -> cashadjustment,
--                          adjustmenttype 'LoanReceived'
--   /poultry-loans         sppoultryloan_create -> poultryloans
--
-- Cash Flow reads BOTH, so the borrowing shows up there. The Loans page reads
-- only poultryloans, so the same borrowing is missing from the page whose entire
-- job is to say what the farm owes. An owner who has always used the Cash page
-- sees an empty loan book and a Cash Flow full of financing.
--
-- WHAT THIS FILE DOES
-- ===================
-- Widens the two READS -- _getall and _summary -- to union in the matching
-- cashadjustment rows. It writes nothing, moves no money, and creates no table.
--
-- Cash Flow is NOT touched. Copying cashadjustment rows into poultryloans would
-- double-count immediately, because Cash Flow reads both tables. Reading across
-- at report time keeps one row, one place, one number.
--
-- THESE ROWS COUNT AS DEBT. A DECISION, NOT A DEFAULT.
-- ====================================================
-- A legacy row is included in outstandingprincipal, totalborrowed, totalreceived
-- and the active-loan count. That was asked for explicitly, and it is the
-- reading that makes the page's headline honest: money was borrowed and nothing
-- on record says it has been paid back, so it is owed.
--
-- THE CONSEQUENCE, STATED SO NOBODY IS SURPRISED BY IT
-- ----------------------------------------------------
-- A cash adjustment has no repayment mechanism. There is no
-- sppoultryloanpayment_record path that can reach it, so its outstanding balance
-- CANNOT BE REDUCED FROM THIS PAGE. It will sit at its full amount until either:
--
--   * the owner edits or deletes the adjustment on the Cash page, which owns it;
--     or
--   * the owner records the borrowing properly as a loan -- and then DELETES the
--     adjustment, because leaving both would state the same debt twice.
--
-- That second case is the one to watch. The page marks these rows as coming from
-- Cash Flow so the distinction is visible, but nothing in the database can stop
-- somebody entering the same borrowing in both places.
--
-- WHICH ADJUSTMENTS COUNT, AND WHY THE SIGN MATTERS
-- =================================================
-- Only 'LoanReceived'. Deliberately NOT:
--
--   OwnerInjection / Withdrawal   owner money, not borrowing. 287 owns those,
--                                 and counting them here would state the same
--                                 money twice across two pages.
--   OpeningBalance                the account's starting position.
--   Correction                    a bookkeeping fix, not a borrowing.
--
-- The amount is emitted SIGNED, not absolute -- and this is where loans differ
-- from 287. Owner money has a direction column (Contribution / Draw) to carry
-- the sign into; a loan has only an amount. So a negative 'LoanReceived', which
-- is how a correction to an over-stated borrowing is recorded on the Cash page,
-- comes through as a negative principal and NETS OFF in the totals. That is the
-- arithmetic an owner expects; showing it as a positive borrowing would double
-- the debt the correction was meant to remove.
--
-- THE ROWS ARE READ-ONLY HERE
-- ===========================
-- A cashadjustment row belongs to the Cash page, which edits and deletes it.
-- Loans are append-only with their own repayment and reversal flow. Those two
-- lifecycles do not mix, so legacy rows come back with source = 'CashAdjustment'
-- and the page hides Repayment, Reverse and Cancel on them. Trying to repay one
-- from here would either write against a loan id that does not exist or
-- silently do nothing.
--
-- poultryloanid is 0 on a legacy row. It is deliberately NOT reused to carry the
-- adjustment id: the two id spaces overlap, and a page keying rows on it would
-- collide and offer actions against the wrong record. The real key is
-- (source, sourceid).
--
-- EFFECT ON TODAY'S NUMBERS
-- =========================
-- The Loans page's totals WILL move, and that is the requested change:
-- borrowings that were always in Cash Flow now also appear in the loan book and
-- in what the farm owes. Nothing else moves -- Cash Flow, the P&L, cash balances
-- and the ledger are all untouched, because this file only reads.
--
-- Order: after 289.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Drop by NAME, not by signature.
--
-- _getall gains two return columns, and CREATE OR REPLACE cannot change a return
-- type. Leaving the old one in place would let Npgsql bind either. Same reason
-- 287 does this, and the same reason the gotcha is worth repeating.
-- -----------------------------------------------------------------------------
DO $drop$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM   pg_proc p
        JOIN   pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('sppoultryloan_getall',
                             'sppoultryloan_summary',
                             'fnpoultryloan_legacy')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- -----------------------------------------------------------------------------
-- 1. The legacy rows, in loan shape.
--
-- One place, so _getall and _summary cannot disagree about which adjustments
-- count or what they are worth.
--
-- The table is resolved at run time because it is `cashadjustment` on some
-- environments and `cashadjustments` on others -- 235, 236 and 287 all do the
-- same COALESCE. A company with neither gets an empty set rather than an error.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryloan_legacy(p_farmid text)
RETURNS TABLE(
    adjustmentid integer,
    loandate     date,
    amount       numeric,
    description  text,
    createdby    text,
    createdat    timestamp
)
LANGUAGE plpgsql STABLE
AS $function$
DECLARE
    v_tbl text;
BEGIN
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);
    IF v_tbl IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY EXECUTE format($sql$
        SELECT ca.adjustmentid,
               ca.adjustmentdate::date,
               ca.amount::numeric,
               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text,
               ca.userid::text,
               ca.createddate::timestamp
        FROM   %s ca
        WHERE  lower(ca.farmid::text) = lower($1)
          AND  ca.adjustmenttype = 'LoanReceived'
          AND  ca.amount <> 0
    $sql$, v_tbl)
    USING p_farmid;
END;
$function$;

COMMENT ON FUNCTION public.fnpoultryloan_legacy(text) IS
    'Borrowings recorded on the Cash / Cash Flow pages as LoanReceived '
    'adjustments, shaped for the loan book. Amount is SIGNED so a negative '
    'correction nets off. Read-only: the Cash page owns these rows.';

-- -----------------------------------------------------------------------------
-- 2. The list.
--
-- Reproduced from 254 with the legacy arm unioned on and two columns added:
--
--   source    'Loan' | 'CashAdjustment' -- what the page keys on, and what it
--             uses to decide whether Repayment / Reverse / Cancel are offered
--   sourceid  the id WITHIN that source
--
-- Every real-loan column is byte for byte what 254 returned.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryloan_getall(
    p_farmid text,
    p_status text DEFAULT NULL
) RETURNS TABLE(
    poultryloanid        integer,
    farmid               text,
    loannumber           text,
    lendername           text,
    lendertype           text,
    accountnumber        text,
    loandate             date,
    originalprincipal    numeric,
    amountreceived       numeric,
    interestrate         numeric,
    interesttype         text,
    termmonths           integer,
    paymentfrequency     text,
    startdate            date,
    enddate              date,
    nextpaymentdate      date,
    poultrycashaccountid integer,
    accountname          text,
    outstandingprincipal numeric,
    totalprincipalrepaid numeric,
    totalinterestpaid    numeric,
    totalfeespaid        numeric,
    status               text,
    isoverdue            boolean,
    paymentcount         integer,
    paidoffdate          date,
    notes                text,
    createdby            text,
    createdat            timestamp,
    reversalreason       text,
    source               text,
    sourceid             integer
)
LANGUAGE sql STABLE
AS $function$
    SELECT l.poultryloanid, l.farmid::text, l.loannumber::text,
           l.lendername::text, l.lendertype::text, l.accountnumber::text,
           l.loandate, l.originalprincipal, l.amountreceived,
           l.interestrate, l.interesttype::text, l.termmonths, l.paymentfrequency::text,
           l.startdate, l.enddate, l.nextpaymentdate,
           l.poultrycashaccountid, a.accountname::text,
           l.outstandingprincipal, l.totalprincipalrepaid,
           l.totalinterestpaid, l.totalfeespaid,
           l.status::text,
           (l.status = 'Active'
            AND l.nextpaymentdate IS NOT NULL
            AND l.nextpaymentdate < CURRENT_DATE
            AND l.outstandingprincipal > 0) AS isoverdue,
           (SELECT COUNT(*)::int FROM poultryloanpayments p
             WHERE p.poultryloanid = l.poultryloanid AND p.status = 'Posted'),
           l.paidoffdate, l.notes::text, l.createdby::text, l.createdat,
           l.reversalreason::text,
           'Loan'::text, l.poultryloanid
    FROM   poultryloans l
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = l.poultrycashaccountid
    WHERE  l.farmid = p_farmid
      AND  (p_status IS NULL OR p_status = 'All' OR l.status = p_status)

    UNION ALL

    -- 290. The legacy arm. Everything a loan record knows and an adjustment does
    -- not is NULL rather than invented: there is no lender, no rate, no term and
    -- no schedule behind a cash adjustment, and filling those with plausible
    -- defaults would be the page telling the owner something nobody entered.
    SELECT 0,                                   -- NOT the adjustment id. See the header.
           p_farmid,
           ('CASH-' || g.adjustmentid::text)::text,
           NULL::text,                          -- lendername: unknown, and not guessable
           NULL::text,                          -- lendertype
           NULL::text,                          -- accountnumber
           g.loandate,
           g.amount, g.amount,                  -- originalprincipal, amountreceived
           NULL::numeric,                       -- interestrate
           NULL::text,                          -- interesttype
           NULL::integer,                       -- termmonths
           NULL::text,                          -- paymentfrequency
           g.loandate,                          -- startdate, so the ORDER BY below works
           NULL::date,                          -- enddate
           NULL::date,                          -- nextpaymentdate
           NULL::integer,                       -- poultrycashaccountid
           NULL::text,                          -- accountname
           g.amount,                            -- outstandingprincipal: counts as debt
           0::numeric, 0::numeric, 0::numeric,  -- nothing repaid, and nothing can be
           'Active'::text,
           false,                               -- isoverdue: no due date to be late against
           0,                                   -- paymentcount
           NULL::date,                          -- paidoffdate
           g.description,
           g.createdby,
           g.createdat,
           NULL::text,                          -- reversalreason
           'CashAdjustment'::text, g.adjustmentid
    FROM   public.fnpoultryloan_legacy(p_farmid) g
    -- Legacy rows are always 'Active', so they answer to no filter, 'All' and
    -- 'Active', and correctly vanish under 'PaidOff' or 'Cancelled'.
    WHERE  (p_status IS NULL OR p_status IN ('All', 'Active'))

    ORDER  BY 14 DESC, 1 DESC;   -- startdate, then id: 254's order, kept
$function$;

COMMENT ON FUNCTION public.sppoultryloan_getall(text, text) IS
    'The loan book, including borrowings recorded as LoanReceived cash '
    'adjustments on the Cash / Cash Flow pages. Legacy rows carry '
    'source = ''CashAdjustment'', loan id 0, and no repayment path -- the page '
    'must not offer Repayment, Reverse or Cancel on them.';

-- -----------------------------------------------------------------------------
-- 3. Summary.
--
-- Reproduced from 254. The legacy rows are added to what was borrowed, what was
-- received, what is outstanding and the active count -- and to nothing else,
-- because an adjustment has no repayments, no interest, no fees and no due date.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryloan_summary(p_farmid text)
RETURNS TABLE(
    activeloans          integer,
    totalborrowed        numeric,
    totalreceived        numeric,
    outstandingprincipal numeric,
    totalprincipalrepaid numeric,
    totalinterestpaid    numeric,
    totalfeespaid        numeric,
    overdueloans         integer,
    nextpaymentdate      date
)
LANGUAGE sql STABLE
AS $function$
    WITH real AS (
        SELECT
            COUNT(*) FILTER (WHERE l.status IN ('Active', 'Overdue'))::int AS activeloans,
            COALESCE(SUM(l.originalprincipal) FILTER (WHERE l.status <> 'Cancelled'), 0)::numeric AS totalborrowed,
            COALESCE(SUM(l.amountreceived)    FILTER (WHERE l.status <> 'Cancelled'), 0)::numeric AS totalreceived,
            COALESCE(SUM(l.outstandingprincipal), 0)::numeric AS outstanding,
            COALESCE(SUM(l.totalprincipalrepaid), 0)::numeric AS repaid,
            COALESCE(SUM(l.totalinterestpaid), 0)::numeric    AS interest,
            COALESCE(SUM(l.totalfeespaid), 0)::numeric        AS fees,
            COUNT(*) FILTER (WHERE l.status = 'Active'
                               AND l.nextpaymentdate IS NOT NULL
                               AND l.nextpaymentdate < CURRENT_DATE
                               AND l.outstandingprincipal > 0)::int AS overdueloans,
            MIN(l.nextpaymentdate) FILTER (WHERE l.status = 'Active' AND l.outstandingprincipal > 0) AS nextdue
        FROM poultryloans l
        WHERE l.farmid = p_farmid
    ),
    legacy AS (
        -- 290. Counted into the debt, per the header. A negative correction nets
        -- off here exactly as it does in the list.
        SELECT COUNT(*)::int AS n, COALESCE(SUM(g.amount), 0)::numeric AS amt
        FROM   public.fnpoultryloan_legacy(p_farmid) g
    )
    SELECT (r.activeloans + l.n)::int,
           (r.totalborrowed + l.amt)::numeric(14,2),
           (r.totalreceived + l.amt)::numeric(14,2),
           (r.outstanding   + l.amt)::numeric(14,2),
           r.repaid::numeric(14,2),     -- an adjustment has no repayments,
           r.interest::numeric(14,2),   -- no interest
           r.fees::numeric(14,2),       -- and no fees
           r.overdueloans,              -- and no due date to be late against
           r.nextdue
    FROM   real r CROSS JOIN legacy l;
$function$;

COMMENT ON FUNCTION public.sppoultryloan_summary(text) IS
    'Loan book totals, including LoanReceived cash adjustments. Those count '
    'toward borrowed, received, outstanding and the active count -- but never '
    'toward repaid, interest, fees or overdue, because an adjustment has no '
    'repayment, no rate and no schedule.';

-- -----------------------------------------------------------------------------
-- 4. Grants.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.fnpoultryloan_legacy(text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryloan_getall(text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryloan_summary(text) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
DO $verify$
DECLARE
    v_farm text;
    v_list integer;
    v_sum  integer;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Poultry' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE '290: no poultry company to verify against.';
        RETURN;
    END IF;

    SELECT COUNT(*) INTO v_list FROM sppoultryloan_getall(v_farm, 'All');
    SELECT activeloans INTO v_sum FROM sppoultryloan_summary(v_farm);
    RAISE NOTICE '290: list returned % rows, summary counts % active.', v_list, v_sum;

    -- Exactly one source value per row, and legacy rows never carry a real id.
    IF EXISTS (SELECT 1 FROM sppoultryloan_getall(v_farm, 'All') r
               WHERE r.source NOT IN ('Loan', 'CashAdjustment')) THEN
        RAISE EXCEPTION '290: a row came back with an unknown source.';
    END IF;
    IF EXISTS (SELECT 1 FROM sppoultryloan_getall(v_farm, 'All') r
               WHERE r.source = 'CashAdjustment' AND r.poultryloanid <> 0) THEN
        RAISE EXCEPTION '290: a legacy row carried a real loan id. The page would offer actions against the wrong record.';
    END IF;
    RAISE NOTICE '290: every row is tagged, and no legacy row carries a loan id.';
END
$verify$;
