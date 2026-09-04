-- =============================================================================
-- 241_WaterCashFlowExpensePaid.postgres.sql
--
-- Purpose
-- -------
-- The water twin of 239: teach the cash-flow report the difference between a
-- bill that was PAID and a bill that was merely RECORDED, now that 240 lets one
-- be part-paid and settled later.
--
-- What changes, and what does not
-- -------------------------------
-- 236's Expense arm already gets the all-or-nothing case right: it takes only
-- Approved rows whose paymentmethod is not 'Credit', so an unpaid bill has never
-- counted as outflow. Two things it cannot express:
--
--   a. A PART payment. A bill for 1,000 with 300 paid at entry is neither Credit
--      nor fully paid, and 236 would report the whole 1,000 as money gone.
--   b. A bill settled LATER. 240 books no expense row for that (the bill already
--      exists), so without a second arm the money would never appear at all.
--
-- So, exactly as in 239, money against a bill arrives at up to two times and is
-- reported at up to two times:
--
--   Expense         resolved amountpaid MINUS posted allocations, at expensedate
--   ExpensePayment  each posted Expense allocation, at the PAYMENT date
--
-- They sum to what was paid and cannot overlap.
--
-- Purchase-side payments are untouched: 240 still books their aggregated expense
-- row dated the payment date, so they keep arriving through the Expense arm.
--
-- EFFECT ON TODAY'S NUMBERS: none. Every untouched row resolves to what 236
-- already reported -- a Credit bill to 0 (and it is still excluded by the Credit
-- filter), anything else to its full amount -- and no bill has an allocation yet.
-- Section 3 measures that; run it before and after and diff it.
--
-- Order: 240, then 241.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The rows.
-- -----------------------------------------------------------------------------
-- Shape unchanged from 236, so _summary keeps working untouched.
CREATE OR REPLACE FUNCTION public.spwatercashflow_rows(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    rowsource       text,        -- Receipt | SaleResidual | Expense | ExpensePayment | Adjustment
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

    -- ---- 4. capital in and out ---------------------------------------------
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
-- 2. The detail rows.
-- -----------------------------------------------------------------------------
-- Unchanged from 236 except that ExpensePayment resolves its category the same
-- way Expense does: a bill paid two months late still belongs to the category it
-- was filed under, so the Money Out breakdown does not sprout a mystery slice.
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
               WHEN r.rowsource IN ('Expense', 'ExpensePayment')
                   THEN COALESCE(NULLIF(btrim(c.name), ''), 'Uncategorised')
               WHEN r.rowsource IN ('Receipt', 'SaleResidual') THEN 'Sales'
               ELSE COALESCE(NULLIF(btrim(r.sourcetype), ''), 'Other')
           END::text
    FROM   public.spwatercashflow_rows(p_farmid, p_fromdate, p_todate) r
    LEFT   JOIN waterexpenses e
           ON  r.rowsource IN ('Expense', 'ExpensePayment')
           AND e.waterexpenseid = r.sourceid
           AND lower(e.farmid::text) = lower(p_farmid)
    LEFT   JOIN waterexpensecategories c
           ON  c.waterexpensecategoryid = e.waterexpensecategoryid;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 3. Verification.
-- -----------------------------------------------------------------------------
SELECT 'functions (3 expected)' AS check,
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'ONLY ' || count(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('spwatercashflow_rows', 'spwatercashflow_summary',
                     'spwatercashflow_detail');

-- 3a. THE IDENTITY. opening + in - out must equal closing. Must be 0.00 per farm.
SELECT f.farmid,
       s.openingbalance, s.moneyin, s.moneyout, s.cashathand,
       ROUND(s.openingbalance + s.moneyin - s.moneyout - s.cashathand, 2) AS should_be_zero
FROM   (SELECT DISTINCT farmid FROM watercashaccounts) f
CROSS  JOIN LATERAL public.spwatercashflow_summary(
                        f.farmid, '2000-01-01'::timestamp, '2999-12-31'::timestamp) s
ORDER  BY f.farmid;

-- 3b. NO DOUBLE COUNTING. Total outflow must equal the eligible PAID bill total.
SELECT f.farmid,
       ROUND(s.moneyout, 2)   AS reported_outflow,
       ROUND(v.paid_total, 2) AS paid_expense_total,
       ROUND(s.moneyout - v.paid_total, 2) AS should_be_zero_or_capital_withdrawals
FROM   (SELECT DISTINCT farmid FROM watercashaccounts) f
CROSS  JOIN LATERAL public.spwatercashflow_summary(f.farmid, NULL, NULL) s
CROSS  JOIN LATERAL (
    SELECT COALESCE((SELECT SUM(COALESCE(e.amountpaid,
                                  CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                                       THEN 0 ELSE e.amount END))
                     FROM waterexpenses e
                     WHERE lower(e.farmid::text) = lower(f.farmid)
                       AND COALESCE(e.isdeleted, false) = false
                       AND COALESCE(e.status, '') = 'Approved'), 0) AS paid_total
) v
ORDER  BY f.farmid;

-- 3c. THE TWO ARMS MUST NOT OVERLAP: allocations may never exceed what a bill
--     records as paid. Expect NO ROWS.
SELECT e.waterexpenseid, e.amount, e.amountpaid, x.allocated, x.paid
FROM   waterexpenses e
CROSS  JOIN LATERAL (
    SELECT COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                     WHERE sa.farmid = e.farmid AND sa.module = 'water'
                       AND sa.status = 'Posted' AND sa.documenttype = 'Expense'
                       AND sa.documentid = e.waterexpenseid), 0) AS allocated,
           COALESCE(e.amountpaid,
                    CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                         THEN 0 ELSE e.amount END) AS paid
) x
WHERE  x.allocated > x.paid;

-- 3d. Internal use must never reach cash flow. Expect NO ROWS.
SELECT r.*
FROM   (SELECT DISTINCT farmid FROM watercashaccounts) f
CROSS  JOIN LATERAL public.spwatercashflow_rows(f.farmid, NULL, NULL) r
JOIN   waterexpenses e ON e.waterexpenseid = r.sourceid
WHERE  r.rowsource = 'Expense' AND e.sourcetype = 'WaterInternalUsage';
