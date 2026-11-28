-- =============================================================================
-- 521_James_GenericPnlCashBasis.postgres.sql
--
-- Switch the Generic Profit & Loss to CASH-BASIS (owner's explicit choice).
--
-- Before (accrual): buying stock was not an expense; its cost reached profit as
-- Cost of Goods Sold when the stock was sold.
-- After  (cash-basis, mirroring the Poultry P&L): a purchase is an expense the
-- day it is approved, shown as a DIRECT production cost "Inventory purchases"
-- (Poultry treats Feed/FlockCost/ProductionSupplies the same way, with no COGS).
-- To avoid charging the same stock twice, the inventory-valuation arms are
-- removed:
--   * Cost of goods sold  -- the cost is now taken at purchase, not at sale.
--   * Stock losses        -- the lost stock was already expensed at purchase.
--   * Internal usage expenses -- consuming own stock was already expensed too.
-- The memo 'inventory' section from migration 520 is dropped (purchases are a
-- real expense now, not an excluded memo). Supplier payments stay excluded (the
-- purchase's full amount is already expensed at approval).
--
-- Net profit over time is unchanged vs accrual; only the TIMING moves (cost down
-- when you buy, up when you sell). Applies to every Generic company. This also
-- makes the P&L page agree with the dashboard's spgenericreport_periodpnl, which
-- is already cash-basis for expenses.
--
-- Idempotent: CREATE OR REPLACE.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fngenericpnl_lines(p_farmid text, p_start date, p_finish date)
 RETURNS TABLE(section text, line text, day date, ref text, description text, amount numeric, keytype text, keyid integer, productid integer, rowid integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH sales AS (
        SELECT s.genericsaleid, s.saledate::date AS day, s.genericsubscriptionid,
               coalesce(nullif(s.receiptnumber, ''), 'Sale #' || s.genericsaleid) AS ref,
               coalesce(c.customername, s.notes, 'Walk-in sale') AS description,
               s.totalamount - coalesce(s.taxamount, 0) AS revenue
        FROM genericsales s
        LEFT JOIN genericcustomers c ON c.farmid = s.farmid AND c.genericcustomerid = s.genericcustomerid
        WHERE s.farmid = p_farmid AND s.status = 'Approved' AND NOT coalesce(s.isdeleted, false)
          AND s.saledate >= p_start AND s.saledate < p_finish + 1
    ), loans AS (
        SELECT * FROM spgenericloan_list(p_farmid) WHERE "Status" NOT IN ('Cancelled', 'Reversed')
    )
    SELECT 'revenue', CASE WHEN genericsubscriptionid IS NULL THEN 'Sales' ELSE 'Subscription income' END,
           day, ref, description, revenue, 'Sale', genericsaleid, NULL::int, NULL::int FROM sales
    UNION ALL
    -- Cash-basis expense arm: every approved expense EXCEPT supplier payments
    -- (the purchase itself is expensed below) and internal stock usage (already
    -- expensed at purchase). Purchases are handled in their own arm so they land
    -- in Operating Expenses as "Inventory purchases".
    SELECT CASE WHEN e.sourcetype = 'AssetDepreciation' OR lower(c.name) = 'depreciation' THEN 'other' ELSE 'operating' END,
           CASE WHEN e.sourcetype = 'AssetDepreciation' THEN 'Depreciation' ELSE coalesce(c.name, 'Uncategorised expenses') END,
           e.expensedate::date, 'Expense #' || e.genericexpenseid, coalesce(e.description, e.paidto, 'Expense'), e.amount,
           'Expense', e.genericexpenseid, NULL, e.genericexpenseid
    FROM genericexpenses e LEFT JOIN genericexpensecategories c ON c.farmid = e.farmid AND c.genericexpensecategoryid = e.genericexpensecategoryid
    WHERE e.farmid = p_farmid AND e.status = 'Approved' AND NOT coalesce(e.isdeleted, false)
      AND coalesce(e.sourcetype, '') NOT IN ('GenericPurchase', 'GenericSupplierPayment', 'Purchase', 'SupplierPayment',
                                             'GenericInternalUsage', 'InternalUsage')
      AND e.expensedate >= p_start AND e.expensedate < p_finish + 1
    UNION ALL
    -- 521: cash-basis, mirroring Poultry. On the Poultry P&L a stock/input
    -- purchase (Feed, FlockCost, ProductionSupplies) is a DIRECT production cost
    -- and there is no Cost-of-Goods-Sold matching. Generic now does the same:
    -- inventory purchases are a Direct Production Cost charged on the day the
    -- purchase is approved (its full amount), so Gross Profit = Revenue −
    -- purchases, and the stock is never charged twice.
    SELECT 'direct', 'Inventory purchases', e.expensedate::date,
           'Expense #' || e.genericexpenseid, coalesce(e.description, e.paidto, 'Purchase'), e.amount,
           'Expense', e.genericexpenseid, NULL, e.genericexpenseid
    FROM genericexpenses e
    WHERE e.farmid = p_farmid AND e.status = 'Approved' AND NOT coalesce(e.isdeleted, false)
      AND coalesce(e.sourcetype, '') IN ('Purchase', 'GenericPurchase')
      AND e.expensedate >= p_start AND e.expensedate < p_finish + 1
    UNION ALL
    SELECT 'operating', 'Payroll', coalesce(p.paydate, p.paidat)::date, 'Payroll #' || p.genericpayrollrunid,
           concat('Pay period ', p.periodstart::date, ' to ', p.periodend::date), p.totalgrosspay,
           'PayrollRun', p.genericpayrollrunid, NULL, p.genericpayrollrunid
    FROM genericpayrollruns p
    WHERE p.farmid = p_farmid AND p.status = 'Paid' AND NOT coalesce(p.isdeleted, false)
      AND coalesce(p.paydate, p.paidat) >= p_start AND coalesce(p.paydate, p.paidat) < p_finish + 1
      AND NOT EXISTS (SELECT 1 FROM genericexpenses e WHERE e.farmid = p.farmid AND e.sourcetype = 'GenericPayrollRun'
                      AND e.sourceid = p.genericpayrollrunid AND e.status = 'Approved' AND NOT coalesce(e.isdeleted, false))
    UNION ALL
    SELECT 'owner', CASE WHEN entrytype = 'Contribution' THEN 'Owner contributions' ELSE 'Owner draws' END,
           entrydate::date, coalesce(referenceno, 'Owner entry #' || genericownerentryid), coalesce(ownername, notes, 'Owner'),
           CASE WHEN entrytype = 'Contribution' THEN amount ELSE -amount END,
           'OwnerEntry', genericownerentryid, NULL, genericownerentryid
    FROM genericownercontributiondraws
    WHERE farmid = p_farmid AND status = 'Posted' AND entrydate >= p_start AND entrydate < p_finish + 1
    UNION ALL
    SELECT 'borrowing', 'Loan proceeds', "LoanDate"::date, 'Loan #' || "GenericLoanId", "LenderName", "AmountReceived",
           'Loan', "GenericLoanId", NULL, "GenericLoanId"
    FROM loans WHERE "LoanDate" >= p_start AND "LoanDate" < p_finish + 1
    UNION ALL
    SELECT v.section, v.line, p."PaymentDate"::date, 'Payment #' || p."GenericLoanPaymentId", l."LenderName", v.amount,
           'Loan', l."GenericLoanId", NULL, p."GenericLoanPaymentId"
    FROM loans l CROSS JOIN LATERAL spgenericloan_payments(l."GenericLoanId", p_farmid) p
    CROSS JOIN LATERAL (VALUES ('borrowing', 'Principal repaid', -p."PrincipalAmount"),
                               ('other', 'Loan interest', p."InterestAmount"),
                               ('other', 'Loan fees', p."FeeAmount"),
                               ('other', 'Loan other charges', p."OtherAmount")) v(section, line, amount)
    WHERE NOT p."IsReversed" AND p."PaymentDate" >= p_start AND p."PaymentDate" < p_finish + 1
    UNION ALL
    SELECT 'capital', 'Asset purchases', c.costdate, 'Asset ' || a.assetnumber, a.assetname, c.amount,
           'CapitalAsset', a.genericcapitalassetid, NULL, c.genericcapitalassetcostid
    FROM genericcapitalassetcosts c JOIN genericcapitalassets a ON a.genericcapitalassetid = c.genericcapitalassetid
    WHERE c.farmid = p_farmid AND c.status = 'Posted' AND c.costdate >= p_start AND c.costdate < p_finish + 1;
$function$;

COMMIT;
