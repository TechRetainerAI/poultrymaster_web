-- =============================================================================
-- 239_PoultryCashFlowExpensePaid.postgres.sql
--
-- Purpose
-- -------
-- Teach the cash-flow report the difference between an expense that was PAID and
-- an expense that was merely RECORDED. Migration 238 makes an unpaid expense
-- possible for the first time; until this file lands, 235 would report it as
-- money that left the business on the day it was entered.
--
-- Why this cannot wait
-- --------------------
-- Since 235 the cash-flow and cash-movement reports do not read the cash ledger
-- at all. They read `expense` directly, and the Expense arm is:
--
--     -COALESCE(e.amount, 0)                                        (235:190)
--
-- i.e. the full billed amount, unconditionally. That was right when every
-- expense row meant money already spent. With 238 it is right for exactly the
-- rows that are fully paid and wrong for every other one.
--
-- The two arms
-- ------------
-- Money against an expense arrives at up to two different times, so it is
-- reported at up to two different times:
--
--   Expense         COALESCE(amountpaid, amount) MINUS posted allocations,
--                   dated expensedate -- what was paid when the bill was entered.
--   ExpensePayment  each posted allocation, dated the PAYMENT date -- what was
--                   paid later through Supplier Balances.
--
-- They sum to COALESCE(amountpaid, amount) and cannot overlap, which is the same
-- v_alloc subtraction 224 used to keep purchase cash and payment cash disjoint.
--
-- Supplier payments against a raw-material purchase or a flock batch are NOT
-- touched: those already book their own expense row dated the payment date
-- (224:414), so they arrive through the Expense arm exactly as before.
--
-- NO-OP AGAINST TODAY'S DATA
-- --------------------------
-- 238 leaves amountpaid NULL on every existing row, and no expense has an
-- allocation yet. So COALESCE(amountpaid, amount) - 0 = amount, and the new arm
-- returns nothing. Every total this report produces is unchanged to the penny --
-- run the verification at the foot of this file before and after and diff it.
--
-- Order: 238, then 239, then re-run 237 (cash movement reads these functions).
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The rows.
-- -----------------------------------------------------------------------------
-- Shape is unchanged from 235, so this is a plain replacement and _summary and
-- _detail keep working without being touched.
CREATE OR REPLACE FUNCTION public.sppoultrycashflow_rows(
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
      -- A REVERSED payment is money that came back. 222/227 added this column and
      -- flip it on reversal rather than deleting the row, so without this filter
      -- the report counts a refunded receipt as income for ever.
      AND  COALESCE(p.status, 'Posted') = 'Posted' 
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
           -- sale.saledate is DATE while this function returns TIMESTAMP, so the
           -- cast is load-bearing: without it Postgres refuses the whole
           -- function with "structure of query does not match function result
           -- type". The live 235 carries this; the copy of 235 in this repo does
           -- NOT, so anyone reproducing that file inherits the fault.
           s.saledate::timestamp,
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
                               AND  lower(pp.farmid::text) = lower(p_farmid)
                               -- Same reason: a reversed payment never covered
                               -- anything, so it must not reduce the residual.
                               AND  COALESCE(pp.status, 'Posted') = 'Posted'), 0)
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

    -- ---- 3. money paid out when the expense was recorded --------------------
    -- Every kind of spending, because every module writes here. NonCash is still
    -- the only category-level exclusion: internal use posts it to record stock
    -- leaving without any money moving (migration 216).
    --
    -- What changed from 235 is the AMOUNT. It was e.amount -- the full bill.
    -- It is now what was actually paid at entry: the expense's resolved
    -- amountpaid, less anything a supplier payment has since covered (which the
    -- next arm reports on its own, later, date).
    --
    -- amountpaid IS NULL means paid in full, so a legacy row resolves straight
    -- back to e.amount and this arm returns exactly what 235 returned.
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
           -v.paidatentry,
           COALESCE(NULLIF(btrim(e.description), ''), e.category)::text,
           'OperatingOut'::text
    FROM   expense e
    CROSS  JOIN LATERAL (
        SELECT GREATEST(
                   COALESCE(e.amountpaid, e.amount)
                 - COALESCE((SELECT SUM(sa.amountapplied)
                             FROM   supplierpaymentallocation sa
                             WHERE  sa.farmid = p_farmid
                               AND  sa.module = 'poultry'
                               AND  sa.status = 'Posted'
                               AND  sa.documenttype = 'Expense'
                               AND  sa.documentid = e.expenseid), 0)
               , 0)::numeric AS paidatentry
    ) v
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  v.paidatentry > 0
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'
      AND  e.expensedate >= v_from
      AND  e.expensedate <= v_to;

    -- ---- 3b. money paid out later, against a bill already recorded ----------
    -- A supplier payment settling an unpaid expense. It belongs to the day the
    -- money moved, not the day the bill was entered -- the same principle arm 1
    -- applies to customer receipts.
    --
    -- sourceid is the EXPENSE id so the row still drills through to the bill it
    -- paid (and so _detail's category join finds it); sourcerowid is the
    -- allocation id, which is what makes each row unique.
    --
    -- Only documenttype='Expense'. A payment against a raw-material purchase or
    -- a flock batch books its own expense row dated the payment date (224:414)
    -- and is already counted by arm 3; adding it here would double it.
    RETURN QUERY
    SELECT 'ExpensePayment'::text,
           FALSE,
           sa.allocationid,
           sp.poultrycashaccountid,
           NULL::text,
           sp.paymentdate,
           'CashOut'::text,
           'ExpensePayment'::text,
           sa.documentid,
           FALSE,
           -sa.amountapplied::numeric,
           ('Payment for expense #' || sa.documentid::text ||
            COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,
           'OperatingOut'::text
    FROM   supplierpaymentallocation sa
    JOIN   poultrysupplierpayments sp
           ON  sp.poultrysupplierpaymentid = sa.paymentid
           AND sp.farmid = sa.farmid
    LEFT   JOIN supplier s
           ON  s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sa.farmid = p_farmid
      AND  sa.module = 'poultry'
      AND  sa.status = 'Posted'
      AND  sa.documenttype = 'Expense'
      AND  sp.status = 'Posted'
      AND  sa.amountapplied <> 0
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;

    -- ---- 4. capital in and out ---------------------------------------------
    -- Owner injections, loans received, withdrawals. Financing, not operating:
    -- money the business received or returned rather than earned or spent.
    --
    -- MUST STAY LAST: it RETURNs early when the table is absent, and anything
    -- below it would be silently skipped on a farm without capital records.
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);

    IF v_tbl IS NULL THEN
        RETURN;                     -- no capital records; the four legs stand
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
-- 2. The detail rows.
-- -----------------------------------------------------------------------------
-- Unchanged from 235 except that ExpensePayment resolves its category the same
-- way Expense does. A bill paid two months late still belongs to the category it
-- was filed under, so the Money Out breakdown does not sprout a mystery slice.
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
               WHEN r.rowsource IN ('Expense', 'ExpensePayment')
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
           ON  r.rowsource IN ('Expense', 'ExpensePayment')
           AND e.expenseid = r.sourceid
           AND lower(e.farmid::text) = lower(p_farmid);
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 3. Verification.
-- -----------------------------------------------------------------------------
-- Run 3a and 3b BEFORE applying 238/239 and again after. Every number must be
-- identical: that is the whole claim this pair of migrations makes.
SELECT 'functions (3 expected)' AS check,
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'ONLY ' || count(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('sppoultrycashflow_rows', 'sppoultrycashflow_summary',
                     'sppoultrycashflow_detail');

-- 3a. THE IDENTITY. opening + in - out must equal closing. Must be 0.00 per farm.
SELECT f.farmid,
       s.openingbalance, s.moneyin, s.moneyout, s.cashathand,
       ROUND(s.openingbalance + s.moneyin - s.moneyout - s.cashathand, 2) AS should_be_zero
FROM   (SELECT DISTINCT farmid FROM poultrycashaccounts) f
CROSS  JOIN LATERAL public.sppoultrycashflow_summary(
                        f.farmid, '2000-01-01'::timestamp, '2999-12-31'::timestamp) s
ORDER  BY f.farmid;

-- 3b. NO DOUBLE COUNTING. Total outflow must equal the eligible PAID expense
--     total. 235 compared against SUM(e.amount); with unpaid expenses possible
--     that is no longer the right yardstick -- the money that left is what was
--     paid, whenever it was paid. The two arms of the report sum to exactly this.
SELECT f.farmid,
       ROUND(s.moneyout, 2) AS reported_outflow,
       ROUND(v.paid_total, 2) AS paid_expense_total,
       ROUND(s.moneyout - v.paid_total, 2)
         AS should_be_zero_or_capital_withdrawals
FROM   (SELECT DISTINCT farmid FROM poultrycashaccounts) f
CROSS  JOIN LATERAL public.sppoultrycashflow_summary(f.farmid, NULL, NULL) s
CROSS  JOIN LATERAL (
    SELECT COALESCE((SELECT SUM(COALESCE(e.amountpaid, e.amount)) FROM expense e
                     WHERE lower(e.farmid::text) = lower(f.farmid)
                       AND COALESCE(e.amount, 0) > 0
                       AND COALESCE(e.paymentmethod, '') <> 'NonCash'), 0) AS paid_total
) v
ORDER  BY f.farmid;
-- NOTE: the last column is expected to equal total capital WITHDRAWALS, not
-- necessarily zero -- those are outflow but are not expenses. Anything above
-- that is double counting.

-- 3c. THE TWO ARMS MUST NOT OVERLAP. For every expense, what arm 3 reports plus
--     what arm 3b reports must equal its resolved amountpaid. Expect no rows.
SELECT e.expenseid, e.amount, e.amountpaid, x.allocated, x.reported
FROM   expense e
CROSS  JOIN LATERAL (
    SELECT COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                     WHERE sa.farmid = lower(e.farmid::text) AND sa.module = 'poultry'
                       AND sa.status = 'Posted' AND sa.documenttype = 'Expense'
                       AND sa.documentid = e.expenseid), 0) AS allocated,
           COALESCE(e.amountpaid, e.amount) AS reported
) x
WHERE  COALESCE(e.paymentmethod, '') <> 'NonCash'
  AND  x.allocated > x.reported;
