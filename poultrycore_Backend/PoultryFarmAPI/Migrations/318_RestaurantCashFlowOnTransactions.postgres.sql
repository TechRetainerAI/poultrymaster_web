-- =============================================================================
-- 318_RestaurantCashFlowOnTransactions.postgres.sql
--
-- Purpose
-- -------
-- Cash Flow for the Restaurant module, same pattern as 235 (Poultry), 236
-- (Water) and 316 (Hotel).
--
-- What it reads
-- -------------
--   restaurantorderpayments   money received from customers (completed orders)
--   restaurantexpenses        operational spending (not rejected)
--
-- The restaurant has no cash accounts, payroll runs, owner-money or loan
-- tables. Tips are included in order payments (amount + tipamount).
--
-- Revenue is the PAYMENT amount, not the order subtotal: this is a cash flow
-- report, not P&L. Tax and service charge collected are cash that moved.
--
-- Amount: SIGNED. Positive in, negative out.
-- Order: after 317.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

DROP FUNCTION IF EXISTS public.sprestaurantcashflow_detail(text, timestamp, timestamp);
DROP FUNCTION IF EXISTS public.sprestaurantcashflow_summary(text, timestamp, timestamp);
DROP FUNCTION IF EXISTS public.sprestaurantcashflow_rows(text, timestamp, timestamp);

-- -----------------------------------------------------------------------------
-- 1. The rows.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sprestaurantcashflow_rows(
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
    createdat       timestamp)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);
    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);
BEGIN
    -- ---- 1. order payments (money received from customers) -------------------
    -- amount + tipamount = total cash received. Tips are cash flow even though
    -- they are not revenue on the P&L.
    RETURN QUERY
    SELECT 'OrderPayment'::text,
           FALSE,
           p.orderpaymentid,
           NULL::integer,
           NULL::text,
           o.createdat::timestamp,
           'CashIn'::text,
           COALESCE(NULLIF(btrim(p.paymentmethod), ''), 'Cash')::text,
           o.orderid,
           FALSE,
           ROUND(COALESCE(p.amount, 0) + COALESCE(p.tipamount, 0), 2)::numeric,
           ('Order #' || COALESCE(o.ordernumber, o.orderid::text)
            || CASE WHEN COALESCE(p.tipamount, 0) > 0
                    THEN ' (incl. tip ' || ROUND(p.tipamount, 2)::text || ')'
                    ELSE '' END)::text,
           'OperatingIn'::text,
           p.createdat::timestamp
    FROM   restaurantorderpayments p
    JOIN   restaurantorders o
           ON  o.orderid = p.orderid
           AND o.farmid = p.farmid
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  o.status = 'Completed'
      AND  p.status = 'Completed'
      AND  COALESCE(p.amount, 0) + COALESCE(p.tipamount, 0) > 0
      AND  o.createdat::timestamp >= v_from
      AND  o.createdat::timestamp <= v_to;

    -- ---- 2. expenses (money paid out) ----------------------------------------
    -- Not-rejected expenses. Draft is included because restaurant expenses do
    -- not have the same approval workflow as hotel — most are recorded as spent.
    RETURN QUERY
    SELECT 'Expense'::text,
           FALSE,
           e.expenseid,
           NULL::integer,
           NULL::text,
           e.expensedate::timestamp,
           'CashOut'::text,
           'Expense'::text,
           e.expenseid,
           FALSE,
           -COALESCE(e.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(e.description), ''),
               COALESCE(NULLIF(btrim(e.categoryname), ''), 'Expense')
           )::text,
           'OperatingOut'::text,
           e.createdat::timestamp
    FROM   restaurantexpenses e
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  COALESCE(e.amount, 0) > 0
      AND  COALESCE(e.status, 'Approved') <> 'Rejected'
      AND  e.expensedate::timestamp >= v_from
      AND  e.expensedate::timestamp <= v_to;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. The summary.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sprestaurantcashflow_summary(
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
    FROM   public.sprestaurantcashflow_rows(p_farmid, p_fromdate, p_todate) r;

    IF p_fromdate IS NOT NULL THEN
        SELECT COALESCE(SUM(r.amount), 0) INTO v_open
        FROM   public.sprestaurantcashflow_rows(
                   p_farmid, NULL, p_fromdate - interval '1 microsecond') r;
    END IF;

    RETURN QUERY SELECT
        ROUND(v_in, 2),  ROUND(v_out, 2),  ROUND(v_in - v_out, 2),
        0::numeric, 0::numeric, ROUND(v_open + v_in - v_out, 2),
        ROUND(v_open, 2), 0::numeric, 0::numeric, 0::numeric, v_n;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. The detail rows, with category.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sprestaurantcashflow_detail(
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
    category        text,
    createdat       timestamp)
LANGUAGE sql
STABLE
AS $function$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid, r.accountname,
           r.transactiondate, r.transactiontype, r.sourcetype, r.sourceid,
           r.istransfer, r.amount, r.description, r.flowgroup,
           CASE
               WHEN r.rowsource = 'Expense'
                   THEN COALESCE(NULLIF(btrim(e.categoryname), ''), 'Uncategorised')
               WHEN r.rowsource = 'OrderPayment'
                   THEN 'Sales (' || COALESCE(NULLIF(btrim(r.sourcetype), ''), 'Cash') || ')'
               ELSE 'Other'
           END::text,
           r.createdat
    FROM   public.sprestaurantcashflow_rows(p_farmid, p_fromdate, p_todate) r
    LEFT   JOIN restaurantexpenses e
           ON  r.rowsource = 'Expense'
           AND e.expenseid = r.sourcerowid
           AND lower(e.farmid::text) = lower(p_farmid);
$function$;

COMMIT;

-- Verification
SELECT 'restaurant cash flow functions (3 expected)' AS check,
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'ONLY ' || count(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('sprestaurantcashflow_rows', 'sprestaurantcashflow_summary',
                     'sprestaurantcashflow_detail');

-- Identity check
SELECT f.farmid,
       s.openingbalance, s.moneyin, s.moneyout, s.cashathand,
       ROUND(s.openingbalance + s.moneyin - s.moneyout - s.cashathand, 2) AS should_be_zero
FROM   (SELECT DISTINCT farmid FROM restaurantorders) f
CROSS  JOIN LATERAL public.sprestaurantcashflow_summary(
                        f.farmid, '2000-01-01'::timestamp, '2999-12-31'::timestamp) s
ORDER  BY f.farmid;
