-- =============================================================================
-- 523_James_GenericFaPurchaseAsExpense.postgres.sql
--
-- Financial Activity: show a Generic purchase as an EXPENSE with a negative
-- profit impact, to match the cash-basis P&L (521/522).
--
-- Today the Purchase payment row carries money-out only (expense 0, profit
-- impact 0): Enock's 519 deliberately keeps the purchase a single row and skips
-- its mirror expense, because the system was accrual (purchase = stock, cost at
-- sale via COGS). We keep that single-row design but, on cash-basis, give that
-- one row its expense: attach the purchase's full amount as an expense leg keyed
-- to the SAME event ('PurchasePayment:<id>'), so the row becomes
--   money out = paid at entry | expense = full amount | profit impact = -amount.
-- The mirror expense is still skipped in the expense arm (519), so nothing is
-- double-counted; later supplier payments stay cash-only (the purchase is
-- already expensed here). A fully-credit purchase (no cash at entry) shows as
-- one non-cash row: expense, no money out.
--
-- ONLY Financial Activity changes. Cash Flow and the Dashboard stay as they are.
-- Body is the LIVE fngenericfa_events (519) with only the marked "523" leg added.
-- Idempotent: CREATE OR REPLACE.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fngenericfa_events(p_farmid text, p_from date, p_to date)
 RETURNS TABLE(eventkey text, businessdate date, occurredat timestamp without time zone, createdat timestamp without time zone, activitytype text, type text, category text, description text, sourcetype text, sourceid integer, sourcenumber text, moneyin numeric, moneyout numeric, revenue numeric, expense numeric, profitimpact numeric, iscash boolean, isnoncash boolean, istransfer boolean, cashaccountid integer, partyname text, plline text, status text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH legs AS (
        -- ---- cash: exactly the rows Generic Cash Flow sums ----------------------
        SELECT d.rowsource || ':' || d.sourcerowid AS k, d.transactiondate::date AS dt, d.createdat AS ca,
               d.rowsource AS st, d.sourcerowid AS sid, d.category AS cat, d.description AS descr,
               GREATEST(d.amount, 0) AS mi, GREATEST(-d.amount, 0) AS mo, 0::numeric AS rev, 0::numeric AS exp,
               d.cashaccountid AS acc, FALSE AS trf, 1 AS pri, NULL::text AS pl, NULL::text AS party, 'Posted'::text AS stat
        FROM   public.spgenericcashflow_detail(p_farmid, p_from::timestamp, (p_to + 1)::timestamp - interval '1 microsecond') d
        UNION ALL
        -- ---- ACCRUAL REVENUE: recognized at sale approval (475) -----------------
        -- Full TotalAmount as revenue, regardless of how much cash was collected.
        SELECT 'SaleRevenue:' || s.genericsaleid, s.saledate::date, s.createdat::timestamp,
               'SaleRevenue', s.genericsaleid, 'Sales',
               'Sale #' || s.genericsaleid || COALESCE(' - ' || NULLIF(btrim(c.customername), ''), ''),
               0, 0, COALESCE(s.totalamount, 0), 0, NULL::int, FALSE, 2, 'Sales Revenue',
               c.customername, s.status
        FROM   genericsales s
        LEFT   JOIN genericcustomers c ON c.genericcustomerid = s.genericcustomerid
        WHERE  lower(s.farmid::text) = lower(p_farmid)
          AND  s.status = 'Approved'
          AND  COALESCE(s.isdeleted, FALSE) = FALSE
          AND  s.saledate::date BETWEEN p_from AND p_to
        UNION ALL
        -- ---- expense legs (approved, non-deleted, non-NonCash) -------------------
        SELECT 'Expense:' || e.genericexpenseid, e.expensedate::date, e.createdat::timestamp,
               'Expense', e.genericexpenseid,
               COALESCE(NULLIF(btrim(ec.name), ''), 'Uncategorised'),
               COALESCE(NULLIF(btrim(e.description), ''), 'Expense'),
               0, 0, 0, e.amount, NULL, FALSE, 2,
               COALESCE(NULLIF(btrim(ec.name), ''), 'Uncategorised'),
               COALESCE(sup.suppliername, NULL), e.status
        FROM   genericexpenses e
        LEFT   JOIN genericexpensecategories ec ON ec.genericexpensecategoryid = e.genericexpensecategoryid
        LEFT   JOIN genericsuppliers sup ON sup.genericsupplierid = e.genericsupplierid
        WHERE  lower(e.farmid::text) = lower(p_farmid) AND COALESCE(e.amount, 0) > 0
          AND  COALESCE(e.isdeleted, FALSE) = FALSE
          AND  COALESCE(e.paymentmethod, '') <> 'NonCash'
          AND  NOT public.fngenericpurchase_ismirrorexpense(e.genericexpenseid)   -- 519
          AND  e.expensedate::date BETWEEN p_from AND p_to
        UNION ALL
        -- ---- 523: purchase as a cash-basis expense, merged onto its own cash-out
        -- row. Same event key as the PurchasePayment cash leg, so it stays ONE
        -- row: money out (paid at entry) + expense (full amount) + profit impact.
        SELECT 'PurchasePayment:' || pu.genericpurchaseid, pu.purchasedate::date, pu.createdat::timestamp,
               'PurchasePayment', pu.genericpurchaseid, 'Purchases',
               ('Purchase ' || COALESCE(NULLIF(btrim(pu.invoicenumber), ''), '#' || pu.genericpurchaseid::text)
                || COALESCE(' - ' || NULLIF(btrim(sp.suppliername), ''), '')),
               0, 0, 0, e.amount, NULL, FALSE, 2, 'Inventory purchases',
               sp.suppliername, pu.status
        FROM   genericpurchases pu
        JOIN   genericexpenses e ON e.genericexpenseid = pu.genericexpenseid AND lower(e.farmid::text) = lower(p_farmid)
        LEFT   JOIN genericsuppliers sp ON sp.genericsupplierid = pu.genericsupplierid
        WHERE  lower(pu.farmid::text) = lower(p_farmid)
          AND  pu.status = 'Approved'
          AND  COALESCE(pu.isdeleted, FALSE) = FALSE
          AND  COALESCE(e.isdeleted, FALSE) = FALSE
          AND  e.status = 'Approved'
          AND  COALESCE(e.amount, 0) > 0
          AND  pu.purchasedate::date BETWEEN p_from AND p_to
        UNION ALL
        -- ---- loan interest and fees as expense ----------------------------------
        SELECT 'LoanRepayment:' || lp."GenericLoanPaymentId", lp."PaymentDate"::date, lp."CreatedAt"::timestamp,
               'LoanRepayment', lp."GenericLoanPaymentId", 'Loan repayments', 'Loan interest and fees',
               0, 0, 0, COALESCE(lp."InterestAmount", 0) + COALESCE(lp."FeeAmount", 0), NULL, FALSE, 2,
               'Loan Interest', NULL, CASE WHEN lp."IsReversed" THEN 'Reversed' ELSE 'Posted' END
        FROM   "GenericLoanPayments" lp
        WHERE  lp."FarmId" = p_farmid AND COALESCE(lp."IsReversed", FALSE) = FALSE
          AND  (COALESCE(lp."InterestAmount", 0) > 0 OR COALESCE(lp."FeeAmount", 0) > 0)
          AND  lp."PaymentDate"::date BETWEEN p_from AND p_to
        UNION ALL
        -- ---- internal transfers (no money enters or leaves) ---------------------
        SELECT 'CashTransfer:' || t.genericcashtransferid, t.transferdate::date, t.createdat::timestamp,
               'CashTransfer', t.genericcashtransferid, 'Transfers',
               'Transfer #' || t.genericcashtransferid,
               0, 0, 0, 0, t.fromgenericcashaccountid, TRUE, 3, NULL, NULL, t.status
        FROM   genericcashtransfers t
        WHERE  lower(t.farmid::text) = lower(p_farmid) AND t.status = 'Approved'
          AND  t.transferdate::date BETWEEN p_from AND p_to
    ), ev AS (
        SELECT l.k,
               MIN(l.dt) AS dt, MIN(l.ca) AS ca,
               (ARRAY_AGG(l.st ORDER BY l.pri))[1] AS st, (ARRAY_AGG(l.sid ORDER BY l.pri))[1] AS sid,
               (ARRAY_AGG(l.cat ORDER BY l.pri))[1] AS cat, (ARRAY_AGG(l.descr ORDER BY l.pri))[1] AS descr,
               SUM(l.mi) AS mi, SUM(l.mo) AS mo, SUM(l.rev) AS rev, SUM(l.exp) AS exp,
               MAX(l.acc) AS acc, BOOL_OR(l.trf) AS trf,
               (ARRAY_AGG(l.pl ORDER BY l.pl IS NULL, l.pri))[1] AS pl,
               (ARRAY_AGG(l.party ORDER BY l.party IS NULL, l.pri))[1] AS party,
               (ARRAY_AGG(l.stat ORDER BY l.pri DESC))[1] AS stat,
               BOOL_OR(l.pri = 1) AS hascash
        FROM   legs l GROUP BY l.k
    )
    SELECT e.k, e.dt, e.dt::timestamp, e.ca,
           CASE WHEN e.trf THEN 'Transfer'
                WHEN e.st LIKE 'OwnerContribution%' OR e.st LIKE 'OwnerDraw%' THEN 'Owner'
                WHEN e.st LIKE 'LoanReceived%' OR e.st LIKE 'LoanRepayment%' THEN 'Financing'
                WHEN e.st = 'Adjustment' THEN 'Financing'
                WHEN e.st = 'CashTransfer' THEN 'Transfer'
                ELSE 'Operating' END,
           CASE e.st
               WHEN 'Receipt' THEN 'Payment received'
               WHEN 'SaleResidual' THEN 'Sale payment'
               WHEN 'SaleRevenue' THEN 'Sale'
               WHEN 'Expense' THEN 'Expense'
               WHEN 'Payroll' THEN 'Payroll'
               WHEN 'OwnerContribution' THEN 'Owner contribution'
               WHEN 'OwnerDraw' THEN 'Owner draw'
               WHEN 'LoanReceived' THEN 'Loan received'
               WHEN 'LoanRepayment' THEN 'Loan repayment'
               WHEN 'CashTransfer' THEN 'Transfer'
               WHEN 'Adjustment' THEN 'Cash adjustment'
               WHEN 'PurchasePayment' THEN 'Purchase payment'
               WHEN 'SupplierPayment' THEN 'Supplier payment'
               ELSE COALESCE(e.st, 'Other') END,
           COALESCE(e.cat, 'Other'), e.descr, e.st, e.sid, e.st || ' #' || COALESCE(e.sid::text, ''),
           ROUND(e.mi, 2), ROUND(e.mo, 2), ROUND(e.rev, 2), ROUND(e.exp, 2), ROUND(e.rev - e.exp, 2),
           e.hascash AND (e.mi <> 0 OR e.mo <> 0),
           NOT (e.hascash AND (e.mi <> 0 OR e.mo <> 0)) AND NOT e.trf,
           e.trf, e.acc, e.party, e.pl, e.stat
    FROM   ev e;
$function$;

COMMIT;
