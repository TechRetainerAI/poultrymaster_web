-- =============================================================================
-- 236_WaterCashFlowOnTransactions.postgres.sql
--
-- Purpose
-- -------
-- The Water rail's Cash Flow, built on business transactions. Mirrors 235.
--
-- NEW FUNCTIONS, not rewrites: Water had no cash-flow SPs at all. Its page did
-- the arithmetic in the browser over watercashtransactions -- the ledger -- which
-- is exactly the dependency this removes.
--
-- What it reads
-- -------------
--   waterpayments    money received from customers, dated when it arrived
--   watersales       the part paid at the point of sale
--   waterexpenses    money paid out
--   cashadjustment   capital in and out   (see the note below -- expect empty)
--
-- Same consolidation as Poultry: waterexpenses is written by internal usage
-- (212, 213) and supplier payments (227), so reading it covers those without
-- reading their tables again and doubling them.
--
-- WATER-SPECIFIC RULES
-- --------------------
-- 1. STATUS GATES THE EXPENSE. 047's own header states the rule: "On Approve: if
--    PaymentMethod <> Credit, debit the linked CashAccount." So Approved AND
--    not-Credit is exactly when money moved. A Draft has not been approved and a
--    Credit has not been paid; neither is cash out. Poultry has no equivalent
--    lifecycle, which is why 235 has no status filter.
-- 2. SOFT DELETES ARE REAL HERE. waterexpenses.isdeleted exists and must be
--    honoured; the poultry expense table has no such column.
-- 3. CANCELLED SALES ARE NOT INCOME. watersales.status can be 'Cancelled'.
--
-- KNOWN GAP -- WATER CAPITAL
-- --------------------------
-- Water records owner injections and similar through adjustWaterCashAccount,
-- which writes to the cash LEDGER. This report does not read the ledger, so
-- those movements will NOT appear in Water's financing section.
--
-- cashadjustment is read here because it is keyed by farmid rather than by
-- module, so a Water farm CAN have rows in it -- but nothing in the Water UI
-- writes there today, so in practice the financing section will be empty.
--
-- That is deliberate: an empty section is honest, whereas pulling adjustment
-- rows out of the ledger would reintroduce the dependency this file exists to
-- remove. Giving Water its own capital record is a separate decision.
--
-- No table is created, altered or written to.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The rows.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwatercashflow_rows(
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
    flowgroup       text)
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
                               AND  lower(wp.farmid::text) = lower(p_farmid)), 0)
               , 2) AS residual
    ) v
    WHERE  lower(s.farmid::text) = lower(p_farmid)
      -- A cancelled sale is not income, whatever it once recorded as paid.
      AND  COALESCE(s.status, '') <> 'Cancelled'
      AND  v.residual > 0
      AND  s.saledate >= v_from
      AND  s.saledate <= v_to;

    -- ---- 3. money paid out -------------------------------------------------
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
           -COALESCE(e.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(e.description), ''),
                    NULLIF(btrim(e.paidto), ''),
                    'Expense #' || e.waterexpenseid::text)::text,
           'OperatingOut'::text
    FROM   waterexpenses e
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  COALESCE(e.isdeleted, false) = false
      AND  COALESCE(e.amount, 0) > 0
      -- 047's rule, verbatim: approved and not on credit is when cash moved.
      AND  COALESCE(e.status, '') = 'Approved'
      AND  COALESCE(e.paymentmethod, '') <> 'Credit'
      AND  e.expensedate >= v_from
      AND  e.expensedate <= v_to;

    -- ---- 4. capital in and out ---------------------------------------------
    -- Expected to return nothing on Water today -- see the header note.
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
-- 2. The summary. Same shape as the poultry one so the frontend can share code.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwatercashflow_summary(
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
    v_in   numeric := 0;
    v_out  numeric := 0;
    v_n    bigint  := 0;
    v_open numeric := 0;
BEGIN
    SELECT COALESCE(SUM(r.amount)  FILTER (WHERE r.amount > 0), 0),
           COALESCE(SUM(-r.amount) FILTER (WHERE r.amount < 0), 0),
           COUNT(*)
      INTO v_in, v_out, v_n
    FROM   public.spwatercashflow_rows(p_farmid, p_fromdate, p_todate) r;

    IF p_fromdate IS NOT NULL THEN
        SELECT COALESCE(SUM(r.amount), 0) INTO v_open
        FROM   public.spwatercashflow_rows(
                   p_farmid, NULL, p_fromdate - interval '1 microsecond') r;
    END IF;

    RETURN QUERY SELECT
        ROUND(v_in, 2),
        ROUND(v_out, 2),
        ROUND(v_in - v_out, 2),
        0::numeric,                          -- ledgercash    (ledger not read)
        0::numeric,                          -- offledgernet
        ROUND(v_open + v_in - v_out, 2),     -- cashathand = CLOSING cash
        ROUND(v_open, 2),
        0::numeric,                          -- transfervolume
        0::numeric,
        0::numeric,
        v_n;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. The detail rows, with the expense category.
-- -----------------------------------------------------------------------------
-- Water stores the category as a foreign key rather than free text, so this
-- joins two tables where poultry joins one.
CREATE OR REPLACE FUNCTION public.spwatercashflow_detail(
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
                   THEN COALESCE(NULLIF(btrim(c.name), ''), 'Uncategorised')
               WHEN r.rowsource IN ('Receipt', 'SaleResidual') THEN 'Sales'
               ELSE COALESCE(NULLIF(btrim(r.sourcetype), ''), 'Other')
           END::text
    FROM   public.spwatercashflow_rows(p_farmid, p_fromdate, p_todate) r
    LEFT   JOIN waterexpenses e
           ON  r.rowsource = 'Expense'
           AND e.waterexpenseid = r.sourceid
           AND lower(e.farmid::text) = lower(p_farmid)
    LEFT   JOIN waterexpensecategories c
           ON  c.waterexpensecategoryid = e.waterexpensecategoryid;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 4. Verification.
-- -----------------------------------------------------------------------------
SELECT 'functions (3 expected)' AS check,
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'ONLY ' || count(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('spwatercashflow_rows', 'spwatercashflow_summary',
                     'spwatercashflow_detail');

-- 4a. The identity, per farm. Must be 0.00.
SELECT f.farmid,
       s.openingbalance, s.moneyin, s.moneyout, s.cashathand,
       ROUND(s.openingbalance + s.moneyin - s.moneyout - s.cashathand, 2) AS should_be_zero
FROM   (SELECT DISTINCT farmid FROM watercashaccounts) f
CROSS  JOIN LATERAL public.spwatercashflow_summary(
                        f.farmid, '2000-01-01'::timestamp, '2999-12-31'::timestamp) s
ORDER  BY f.farmid;

-- 4b. No double counting: outflow must equal the eligible waterexpenses total.
SELECT f.farmid,
       ROUND(s.moneyout, 2) AS reported_outflow,
       ROUND(COALESCE((SELECT SUM(e.amount) FROM waterexpenses e
                       WHERE lower(e.farmid::text) = lower(f.farmid)
                         AND COALESCE(e.isdeleted,false) = false
                         AND COALESCE(e.amount,0) > 0
                         AND COALESCE(e.status,'') = 'Approved'
                         AND COALESCE(e.paymentmethod,'') <> 'Credit'), 0), 2) AS expense_total
FROM   (SELECT DISTINCT farmid FROM watercashaccounts) f
CROSS  JOIN LATERAL public.spwatercashflow_summary(f.farmid, NULL, NULL) s
ORDER  BY f.farmid;

-- 4c. Receipt consistency. Any row here is a pre-existing data problem.
SELECT s.watersaleid, s.saledate, s.totalamount, s.status, s.amountpaid,
       COALESCE(SUM(p.amount), 0) AS payment_rows
FROM   watersales s
LEFT   JOIN waterpayments p
       ON  p.watersaleid = s.watersaleid
       AND lower(p.farmid::text) = lower(s.farmid::text)
WHERE  COALESCE(s.status,'') <> 'Cancelled'
GROUP  BY s.watersaleid, s.saledate, s.totalamount, s.status, s.amountpaid
HAVING ROUND(CASE WHEN COALESCE(s.status,'') = 'Paid' THEN COALESCE(s.totalamount,0)
                  ELSE LEAST(GREATEST(COALESCE(s.amountpaid,0),0), COALESCE(s.totalamount,0)) END
             - COALESCE(SUM(p.amount), 0), 2) < 0
ORDER  BY s.saledate DESC
LIMIT  50;

-- 4d. Flow groups. FinancingIn/FinancingOut are EXPECTED to be absent on Water
--     until it has its own capital record -- see the header note.
SELECT r.flowgroup, count(*) AS movements, ROUND(SUM(ABS(r.amount)), 2) AS total
FROM   (SELECT DISTINCT farmid FROM watercashaccounts) f
CROSS  JOIN LATERAL public.spwatercashflow_rows(f.farmid, NULL, NULL) r
GROUP  BY r.flowgroup
ORDER  BY r.flowgroup;
