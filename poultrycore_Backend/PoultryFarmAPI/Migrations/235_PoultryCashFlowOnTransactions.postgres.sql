-- =============================================================================
-- 235_PoultryCashFlowOnTransactions.postgres.sql
--
-- Purpose
-- -------
-- Rebuild Cash Flow on the business transactions that actually move money, and
-- cut its dependency on the cash-account ledger entirely.
--
-- What it stops reading
-- ---------------------
--   poultrycashtransactions   the cash-account ledger
--   poultrycashaccounts       balances and opening balances
--   poultrycashtransfers      movements between the company's own accounts
--   reconciliation / counts   verification records
--
-- None of those are cash flow. A transfer is the same money in a different box.
-- A reconciliation adjustment is a correction to a record, not an event in the
-- business. And reconciliation cannot both check the figures and be their source.
--
-- What it reads instead
-- ---------------------
--   poultrypayments   money received from customers, dated when it arrived
--   sale              the part paid at the counter that never became a payment row
--   expense           money paid out
--   cashadjustment    owner capital, loans, withdrawals   (optional table)
--
-- THE ONE THING TO UNDERSTAND HERE
-- --------------------------------
-- The expense table is ALREADY the consolidated record of money paid out.
-- Payroll (131:254), raw-material purchases (130:84), supplier payments
-- (224:414), deliveries, driver distribution and flock batches all INSERT INTO
-- expense with sourcetype/sourceid.
--
-- 224's insert carries the comment "a purchase's linked expense rows sum to its
-- amountpaid" -- so those rows are CASH PAID, not an accrual.
--
-- So this file reads expense and does NOT separately read payroll runs or
-- supplier payments. Reading both would double every wage and every supplier
-- settlement. If outflow ever exceeds the eligible expense total for a period,
-- that is the bug, and the verification block at the foot of this file catches it.
--
-- This also REVERSES one rule from 231. That function excluded the categories
-- 'Raw Materials / Inventory Purchase' and 'Flock / Bird Purchase', because in
-- the ledger world the supplier payment posted its own cash row and counting the
-- expense too would double it. Reading expense alone, those rows are exactly the
-- ones we want.
--
-- The Cash Movement report follows this change rather than being insulated from
-- it: 237 repoints that report at these same functions, so the two can never
-- give different answers to the same question. Run 235 before 237.
--
-- DROP + CREATE (the row shape gains a column). No table is created, altered or
-- written to.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- Dependency order: detail and summary both call rows.
DROP FUNCTION IF EXISTS public.sppoultrycashflow_detail(text, timestamp, timestamp);
DROP FUNCTION IF EXISTS public.sppoultrycashflow_summary(text, timestamp, timestamp);
DROP FUNCTION IF EXISTS public.sppoultrycashflow_rows(text, timestamp, timestamp);

-- -----------------------------------------------------------------------------
-- 1. The rows.
-- -----------------------------------------------------------------------------
-- amount stays SIGNED -- positive in, negative out -- because every caller
-- already relies on that.
--
-- The column list is unchanged from 231 apart from `flowgroup`, so the C# reader
-- and the frontend keep working. Three columns are now always constant and are
-- kept only so the shape is stable:
--
--   offledger    FALSE  -- every row here moved money; whether it touched an
--                          account is a Cash Accounts question, not a cash-flow one
--   istransfer   FALSE  -- transfers are not read at all any more
--   cashaccountid/accountname -- informational where known, never a filter
CREATE OR REPLACE FUNCTION public.sppoultrycashflow_rows(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    rowsource       text,        -- Receipt | SaleResidual | Expense | Adjustment
    offledger       boolean,
    sourcerowid     integer,
    cashaccountid   integer,
    accountname     text,
    transactiondate timestamp,
    transactiontype text,
    sourcetype      text,
    sourceid        integer,
    istransfer      boolean,
    amount          numeric,
    description     text,
    flowgroup       text)        -- OperatingIn | OperatingOut | FinancingIn | FinancingOut
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_tbl  text;
    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);
    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);
BEGIN
    -- ---- 1. customer receipts, dated when the money arrived -----------------
    -- This is the leg that makes it a CASH flow rather than a sales report. A
    -- January sale part-paid in August belongs in August, and poultrypayments is
    -- the only place that date exists (145_PoultryPayments.sql:36).
    RETURN QUERY
    SELECT 'Receipt'::text,
           FALSE,
           p.poultrypaymentid,
           NULL::integer,
           NULL::text,
           p.paymentdate,
           'CashIn'::text,
           'CustomerPayment'::text,
           p.saleid,
           FALSE,
           COALESCE(p.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(p.note), ''),
                    NULLIF(btrim(p.reference), ''),
                    'Payment for sale #' || p.saleid::text)::text,
           'OperatingIn'::text
    FROM   poultrypayments p
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) <> 0
      AND  p.paymentdate >= v_from
      AND  p.paymentdate <= v_to;

    -- ---- 2. the part paid at the counter -----------------------------------
    -- Not every receipt becomes a payment row: a sale entered as already paid
    -- sets amountpaid directly. Counting the difference here picks those up
    -- without double counting the ones that DID create a row.
    --
    -- `paid` is honoured ahead of amountpaid because older rows were marked paid
    -- without amountpaid ever being populated -- the same rule CashController
    -- applies. Without it, historic cash sales vanish from the report.
    RETURN QUERY
    SELECT 'SaleResidual'::text,
           FALSE,
           s.saleid,
           s.poultrycashaccountid,
           NULL::text,
           s.saledate,
           'CashIn'::text,
           'Sale'::text,
           s.saleid,
           FALSE,
           v.residual,
           ('Sale #' || s.saleid::text ||
            COALESCE(' - ' || NULLIF(btrim(s.customername), ''), ''))::text,
           'OperatingIn'::text
    FROM   sale s
    CROSS  JOIN LATERAL (
        SELECT ROUND(
                   CASE WHEN COALESCE(s.paid, false)
                        THEN COALESCE(s.totalamount, 0)
                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),
                                   COALESCE(s.totalamount, 0))
                   END
                 - COALESCE((SELECT SUM(pp.amount)
                             FROM   poultrypayments pp
                             WHERE  pp.saleid = s.saleid
                               AND  lower(pp.farmid::text) = lower(p_farmid)), 0)
               , 2) AS residual
    ) v
    WHERE  lower(s.farmid::text) = lower(p_farmid)
      -- Only a POSITIVE residual. A negative one means the payment rows already
      -- exceed what the sale records as paid, which is a data inconsistency; it
      -- is surfaced by this file's verification query rather than quietly
      -- subtracted from the day's income.
      AND  v.residual > 0
      AND  s.saledate >= v_from
      AND  s.saledate <= v_to;

    -- ---- 3. money paid out -------------------------------------------------
    -- Every kind of spending, because every module writes here. NonCash is the
    -- only exclusion: internal use posts it to record stock leaving without any
    -- money moving (migration 216).
    RETURN QUERY
    SELECT 'Expense'::text,
           FALSE,
           e.expenseid,
           e.poultrycashaccountid,
           NULL::text,
           e.expensedate,
           'CashOut'::text,
           'Expense'::text,
           e.expenseid,
           FALSE,
           -COALESCE(e.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(e.description), ''), e.category)::text,
           'OperatingOut'::text
    FROM   expense e
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  COALESCE(e.amount, 0) > 0
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'
      AND  e.expensedate >= v_from
      AND  e.expensedate <= v_to;

    -- ---- 4. capital in and out ---------------------------------------------
    -- Owner injections, loans received, withdrawals. Financing, not operating:
    -- money the business received or returned rather than earned or spent.
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);

    IF v_tbl IS NULL THEN
        RETURN;                     -- no capital records; the three legs stand
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
               ca.amount::numeric,     -- already signed
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
-- 2. The summary.
-- -----------------------------------------------------------------------------
-- Opening + in - out = closing, all from the same transaction set, so the
-- identity closes by construction rather than by agreeing with a balance.
--
-- Opening is no longer derived backwards from today's cash. It is measured:
-- everything eligible that happened BEFORE the period started. A business that
-- held cash before it began using the system records that as an OpeningBalance
-- adjustment, which is simply one more eligible transaction.
--
-- Four columns are retained at zero so the return shape does not change and no
-- caller breaks. They described the ledger, and the ledger is no longer read:
--   ledgercash, offledgernet, offledgerin, offledgerout, transfervolume
CREATE OR REPLACE FUNCTION public.sppoultrycashflow_summary(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    moneyin            numeric,
    moneyout           numeric,
    netcashflow        numeric,
    ledgercash         numeric,
    offledgernet       numeric,
    cashathand         numeric,
    openingbalance     numeric,
    transfervolume     numeric,
    offledgerin        numeric,
    offledgerout       numeric,
    rowcount           bigint)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_in      numeric := 0;
    v_out     numeric := 0;
    v_n       bigint  := 0;
    v_open    numeric := 0;
BEGIN
    SELECT COALESCE(SUM(r.amount)  FILTER (WHERE r.amount > 0), 0),
           COALESCE(SUM(-r.amount) FILTER (WHERE r.amount < 0), 0),
           COUNT(*)
      INTO v_in, v_out, v_n
    FROM   public.sppoultrycashflow_rows(p_farmid, p_fromdate, p_todate) r;

    -- Everything before the window opened. With no start date there is nothing
    -- before it, so opening is zero and closing becomes the all-time total.
    IF p_fromdate IS NOT NULL THEN
        SELECT COALESCE(SUM(r.amount), 0) INTO v_open
        FROM   public.sppoultrycashflow_rows(
                   p_farmid, NULL, p_fromdate - interval '1 microsecond') r;
    END IF;

    RETURN QUERY SELECT
        ROUND(v_in, 2),
        ROUND(v_out, 2),
        ROUND(v_in - v_out, 2),
        0::numeric,                          -- ledgercash    (ledger not read)
        0::numeric,                          -- offledgernet  (concept retired)
        ROUND(v_open + v_in - v_out, 2),     -- cashathand = CLOSING cash
        ROUND(v_open, 2),
        0::numeric,                          -- transfervolume (excluded entirely)
        0::numeric,                          -- offledgerin
        0::numeric,                          -- offledgerout
        v_n;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. The detail rows, with the expense category.
-- -----------------------------------------------------------------------------
-- Same as 233: the rows above plus what the money was FOR. The category lives on
-- the expense record, and sourceid is the expense id, so one join covers it.
CREATE OR REPLACE FUNCTION public.sppoultrycashflow_detail(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    rowsource       text,
    offledger       boolean,
    sourcerowid     integer,
    cashaccountid   integer,
    accountname     text,
    transactiondate timestamp,
    transactiontype text,
    sourcetype      text,
    sourceid        integer,
    istransfer      boolean,
    amount          numeric,
    description     text,
    flowgroup       text,
    category        text)
LANGUAGE sql
STABLE
AS $function$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid, r.accountname,
           r.transactiondate, r.transactiontype, r.sourcetype, r.sourceid,
           r.istransfer, r.amount, r.description, r.flowgroup,
           CASE
               WHEN r.rowsource = 'Expense'
                   THEN COALESCE(NULLIF(btrim(e.category), ''), 'Uncategorised')
               WHEN r.rowsource IN ('Receipt', 'SaleResidual') THEN 'Sales'
               -- Capital keeps its own type as the bucket, so an owner injection
               -- never merges into a generic "Adjustment" slice.
               ELSE COALESCE(NULLIF(btrim(r.sourcetype), ''), 'Other')
           END::text
    FROM   public.sppoultrycashflow_rows(p_farmid, p_fromdate, p_todate) r
    -- LEFT, so an expense deleted after the fact still appears in the totals as
    -- Uncategorised rather than dropping out of them.
    LEFT   JOIN expense e
           ON  r.rowsource = 'Expense'
           AND e.expenseid = r.sourceid
           AND lower(e.farmid::text) = lower(p_farmid);
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 4. Verification.
-- -----------------------------------------------------------------------------
SELECT 'functions (3 expected)' AS check,
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'ONLY ' || count(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('sppoultrycashflow_rows', 'sppoultrycashflow_summary',
                     'sppoultrycashflow_detail');

-- 4a. THE IDENTITY. opening + in - out must equal closing, for a bounded window
--     as well as all time. Must be 0.00 per farm.
SELECT f.farmid,
       s.openingbalance, s.moneyin, s.moneyout, s.cashathand,
       ROUND(s.openingbalance + s.moneyin - s.moneyout - s.cashathand, 2) AS should_be_zero
FROM   (SELECT DISTINCT farmid FROM poultrycashaccounts) f
CROSS  JOIN LATERAL public.sppoultrycashflow_summary(
                        f.farmid, '2000-01-01'::timestamp, '2999-12-31'::timestamp) s
ORDER  BY f.farmid;

-- 4b. NO DOUBLE COUNTING. Total outflow must equal the eligible expense total.
--     If outflow is larger, payroll or supplier payments are being counted both
--     through expense and through their own tables.
SELECT f.farmid,
       ROUND(s.moneyout, 2) AS reported_outflow,
       ROUND(COALESCE((SELECT SUM(e.amount) FROM expense e
                       WHERE lower(e.farmid::text) = lower(f.farmid)
                         AND COALESCE(e.amount,0) > 0
                         AND COALESCE(e.paymentmethod,'') <> 'NonCash'), 0), 2) AS expense_total,
       ROUND(s.moneyout
             - COALESCE((SELECT SUM(e.amount) FROM expense e
                         WHERE lower(e.farmid::text) = lower(f.farmid)
                           AND COALESCE(e.amount,0) > 0
                           AND COALESCE(e.paymentmethod,'') <> 'NonCash'), 0), 2)
         AS should_be_zero_or_capital_withdrawals
FROM   (SELECT DISTINCT farmid FROM poultrycashaccounts) f
CROSS  JOIN LATERAL public.sppoultrycashflow_summary(f.farmid, NULL, NULL) s
ORDER  BY f.farmid;
-- NOTE: the last column is expected to equal total capital WITHDRAWALS, not
-- necessarily zero -- those are outflow but are not expenses. Anything above
-- that is double counting.

-- 4c. RECEIPT CONSISTENCY. Payment rows must never exceed what the sale records
--     as paid. Any row returned here is a pre-existing data problem that this
--     report will now expose; investigate rather than clamp.
SELECT s.saleid, s.saledate, s.totalamount, s.paid, s.amountpaid,
       COALESCE(SUM(p.amount), 0) AS payment_rows,
       ROUND(CASE WHEN COALESCE(s.paid,false) THEN COALESCE(s.totalamount,0)
                  ELSE LEAST(GREATEST(COALESCE(s.amountpaid,0),0), COALESCE(s.totalamount,0)) END
             - COALESCE(SUM(p.amount), 0), 2) AS residual
FROM   sale s
LEFT   JOIN poultrypayments p
       ON  p.saleid = s.saleid
       AND lower(p.farmid::text) = lower(s.farmid::text)
GROUP  BY s.saleid, s.saledate, s.totalamount, s.paid, s.amountpaid
HAVING ROUND(CASE WHEN COALESCE(s.paid,false) THEN COALESCE(s.totalamount,0)
                  ELSE LEAST(GREATEST(COALESCE(s.amountpaid,0),0), COALESCE(s.totalamount,0)) END
             - COALESCE(SUM(p.amount), 0), 2) < 0
ORDER  BY s.saledate DESC
LIMIT  50;

-- 4d. What the four flow groups now hold, per farm. A sanity read before anyone
--     trusts the page.
SELECT r.flowgroup, count(*) AS movements, ROUND(SUM(ABS(r.amount)), 2) AS total
FROM   (SELECT DISTINCT farmid FROM poultrycashaccounts) f
CROSS  JOIN LATERAL public.sppoultrycashflow_rows(f.farmid, NULL, NULL) r
GROUP  BY r.flowgroup
ORDER  BY r.flowgroup;
