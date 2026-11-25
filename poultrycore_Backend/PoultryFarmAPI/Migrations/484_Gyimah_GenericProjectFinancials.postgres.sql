-- 484: Projects & Contracts -- the one financial engine.
--
-- Every project number comes from here. No page computes its own formula.
--
-- 1. fngenericpnl_lines / fngenericpnl_entries
--    The Generic P&L used to be inline SQL in Business/GenericProfitLoss.cs.
--    It moves here UNCHANGED in meaning: fngenericpnl_entries returns exactly the
--    rows the old SQL returned (checked row-for-row on every Generic company
--    before the C# switched). fngenericpnl_lines is the same thing one level
--    finer: cost of goods sold per sale AND product, and each row carries the
--    key it is attributed by (keytype/keyid).
-- 2. fngenericproject_keyshares -- for every attributable key, which projects
--    own what share. Derived keys are worked out here, once:
--      Sale          revenue, by each line's amount x its share
--      SaleProduct   cost of goods sold, by each product line's quantity x share
--      Purchase      by each line's amount x its share
--      Expense       its own split; else depreciation follows its asset, a
--                    payroll expense follows its payroll run
--      CustomerPayment  what it paid follows the sales it was applied to; the
--                    unapplied rest follows a designated advance
--      SupplierPayment  follows the purchases / expenses / asset costs it paid;
--                    the unapplied rest follows a designated advance
--      OwnerEntry, Loan, PayrollRun, CapitalAsset -- their own split
-- 3. fngenericproject_pnl -- P&L rows per project. The part not given to any
--    project is a "General company activity" row (projectid NULL) worked out
--    as amount minus the project parts, so projects + General = company,
--    to the cent.
-- 4. fngenericproject_cash -- actual money in and out per project, read from
--    the cash ledger (genericcashtransactions). Transfers between the company's
--    own accounts are left out (they are not money in or out). Classified
--    Operating / Investing / Financing / Other.
-- 5. fngenericproject_balances -- receivables, payables and advances per
--    project as they stand now.
-- 6. spgenericproject_summary / _compare / _pnl / _cashflow / _transactions /
--    _reconcile -- what the pages call.
--
-- Read-only: nothing here writes.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. P&L lines (moved from GenericProfitLoss.cs)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fngenericpnl_lines(p_farmid text, p_start date, p_finish date)
RETURNS TABLE(section text, line text, day date, ref text, description text, amount numeric,
              keytype text, keyid integer, productid integer, rowid integer)
LANGUAGE sql STABLE AS $f$
    WITH sales AS (
        SELECT s.genericsaleid, s.saledate::date AS day, s.genericsubscriptionid,
               coalesce(nullif(s.receiptnumber, ''), 'Sale #' || s.genericsaleid) AS ref,
               coalesce(c.customername, s.notes, 'Walk-in sale') AS description,
               s.totalamount - coalesce(s.taxamount, 0) AS revenue
        FROM genericsales s
        LEFT JOIN genericcustomers c ON c.farmid = s.farmid AND c.genericcustomerid = s.genericcustomerid
        WHERE s.farmid = p_farmid AND s.status = 'Approved' AND NOT coalesce(s.isdeleted, false)
          AND s.saledate >= p_start AND s.saledate < p_finish + 1
    ), movement_cost AS (
        SELECT m.referenceid, m.genericproductid, sum(abs(coalesce(m.totalcostvalue, m.unitcost * m.quantity))) AS cost
        FROM genericstockmovements m JOIN sales s ON s.genericsaleid = m.referenceid
        WHERE m.farmid = p_farmid AND m.referencetype = 'Sale' AND m.movementtype = 'SaleOut'
        GROUP BY m.referenceid, m.genericproductid
    ), item_cost AS (
        SELECT i.genericsaleid, i.genericproductid, sum(i.costamount * i.quantity) AS cost
        FROM genericsaleitems i JOIN sales s USING (genericsaleid)
        WHERE i.farmid = p_farmid AND i.itemtype = 'Product'
        GROUP BY i.genericsaleid, i.genericproductid
    ), costs AS (
        SELECT coalesce(m.referenceid, i.genericsaleid) AS id,
               coalesce(m.genericproductid, i.genericproductid) AS productid,
               coalesce(m.cost, i.cost, 0) AS cost
        FROM movement_cost m FULL JOIN item_cost i ON m.referenceid = i.genericsaleid AND m.genericproductid = i.genericproductid
    ), loans AS (
        SELECT * FROM spgenericloan_list(p_farmid) WHERE "Status" NOT IN ('Cancelled', 'Reversed')
    )
    SELECT 'revenue', CASE WHEN genericsubscriptionid IS NULL THEN 'Sales' ELSE 'Subscription income' END,
           day, ref, description, revenue, 'Sale', genericsaleid, NULL::int, NULL::int FROM sales
    UNION ALL
    SELECT 'direct', 'Cost of goods sold', s.day, s.ref, s.description, c.cost, 'SaleProduct', s.genericsaleid, c.productid, NULL
    FROM costs c JOIN sales s ON s.genericsaleid = c.id
    UNION ALL
    SELECT 'direct', 'Stock losses', a.adjustmentdate::date, 'Adjustment #' || a.genericstockadjustmentid,
           coalesce(a.reason, 'Stock decrease'), abs(coalesce(m.totalcostvalue, m.quantity * m.unitcost)),
           'General', a.genericstockadjustmentid, m.genericproductid, m.genericstockmovementid
    FROM genericstockadjustments a JOIN genericstockmovements m ON m.farmid = a.farmid
         AND m.referenceid = a.genericstockadjustmentid AND m.referencetype = 'Adjustment' AND m.movementtype = 'AdjustmentOut'
    WHERE a.farmid = p_farmid AND a.adjustmenttype = 'Decrease' AND a.status = 'Approved'
      AND a.adjustmentdate >= p_start AND a.adjustmentdate < p_finish + 1
    UNION ALL
    SELECT CASE WHEN e.sourcetype = 'AssetDepreciation' OR lower(c.name) = 'depreciation' THEN 'other' ELSE 'operating' END,
           CASE WHEN e.sourcetype = 'AssetDepreciation' THEN 'Depreciation' ELSE coalesce(c.name, 'Uncategorised expenses') END,
           e.expensedate::date, 'Expense #' || e.genericexpenseid, coalesce(e.description, e.paidto, 'Expense'), e.amount,
           'Expense', e.genericexpenseid, NULL, e.genericexpenseid
    FROM genericexpenses e LEFT JOIN genericexpensecategories c ON c.farmid = e.farmid AND c.genericexpensecategoryid = e.genericexpensecategoryid
    WHERE e.farmid = p_farmid AND e.status = 'Approved' AND NOT coalesce(e.isdeleted, false)
      AND coalesce(e.sourcetype, '') NOT IN ('GenericPurchase', 'GenericSupplierPayment', 'Purchase', 'SupplierPayment')
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
$f$;

-- Exactly the rows GenericProfitLoss.cs returned before 484.
CREATE OR REPLACE FUNCTION public.fngenericpnl_entries(p_farmid text, p_start date, p_finish date)
RETURNS TABLE(section text, line text, day date, ref text, description text, amount numeric)
LANGUAGE sql STABLE AS $f$
    SELECT l.section, l.line, l.day, l.ref, coalesce(l.description, ''), sum(l.amount)
    FROM fngenericpnl_lines(p_farmid, p_start, p_finish) l
    -- COGS rows are per product here and were one row per sale before; every
    -- other row is already unique by its rowid.
    GROUP BY l.section, l.line, l.day, l.ref, l.description, l.keytype, l.keyid,
             CASE WHEN l.keytype = 'SaleProduct' THEN NULL ELSE l.rowid END,
             CASE WHEN l.keytype = 'General' THEN l.rowid END
    HAVING sum(l.amount) <> 0;
$f$;

-- ---------------------------------------------------------------------------
-- 2. Shares
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fngenericproject_keyshares(p_farmid text)
RETURNS TABLE(keytype text, keyid integer, productid integer, projectid integer, share numeric, costclass text)
LANGUAGE sql STABLE AS $f$
    WITH a AS (
        SELECT * FROM genericprojectallocations WHERE farmid = p_farmid AND status = 'Active'
    ), sale_lines AS (
        SELECT i.genericsaleid, i.genericsaleitemid, i.genericproductid, i.linetotal, i.quantity,
               sum(i.linetotal) OVER w AS saletotal, sum(i.quantity) OVER w AS saleqty,
               sum(i.quantity) OVER (PARTITION BY i.genericsaleid, i.genericproductid) AS prodqty
        FROM genericsaleitems i
        WHERE i.farmid = p_farmid AND i.genericsaleid IN (SELECT sourceid FROM a WHERE sourcetype = 'SaleLine')
        WINDOW w AS (PARTITION BY i.genericsaleid)
    ), sale_share AS (
        SELECT l.genericsaleid AS keyid, a.genericprojectid AS projectid,
               sum(a.share * CASE WHEN l.saletotal <> 0 THEN l.linetotal / l.saletotal
                                  WHEN l.saleqty <> 0 THEN l.quantity / l.saleqty ELSE 0 END) AS share
        FROM sale_lines l JOIN a ON a.sourcetype = 'SaleLine' AND a.sourceid = l.genericsaleid
                                AND a.sourcelineid = l.genericsaleitemid
        GROUP BY 1, 2
    ), saleprod_share AS (
        SELECT l.genericsaleid AS keyid, l.genericproductid AS productid, a.genericprojectid AS projectid,
               sum(a.share * CASE WHEN l.prodqty <> 0 THEN l.quantity / l.prodqty ELSE 0 END) AS share
        FROM sale_lines l JOIN a ON a.sourcetype = 'SaleLine' AND a.sourceid = l.genericsaleid
                                AND a.sourcelineid = l.genericsaleitemid
        WHERE l.genericproductid IS NOT NULL
        GROUP BY 1, 2, 3
    ), purchase_share AS (
        SELECT i.genericpurchaseid AS keyid, a.genericprojectid AS projectid,
               sum(a.share * CASE WHEN t.total <> 0 THEN i.linetotal / t.total
                                  WHEN t.qty <> 0 THEN i.quantity / t.qty ELSE 0 END) AS share
        FROM genericpurchaseitems i
        JOIN (SELECT genericpurchaseid, sum(linetotal) AS total, sum(quantity) AS qty
              FROM genericpurchaseitems WHERE farmid = p_farmid GROUP BY 1) t USING (genericpurchaseid)
        JOIN a ON a.sourcetype = 'PurchaseLine' AND a.sourceid = i.genericpurchaseid AND a.sourcelineid = i.genericpurchaseitemid
        GROUP BY 1, 2
    ), direct AS (
        SELECT a.sourcetype AS keytype, a.sourceid AS keyid, a.genericprojectid AS projectid, a.share, a.costclass
        FROM a WHERE a.sourcetype IN ('Expense', 'OwnerEntry', 'Loan', 'PayrollRun', 'CapitalAsset',
                                      'CustomerPayment', 'SupplierPayment')
    ), expense_derived AS (
        -- Depreciation follows its asset; a payroll expense follows its run --
        -- unless the expense was given its own split, which wins.
        SELECT 'Expense'::text AS keytype, e.genericexpenseid AS keyid, d.projectid, d.share, d.costclass
        FROM genericexpenses e
        JOIN genericassetdepreciation ad ON ad.farmid = e.farmid AND ad.genericexpenseid = e.genericexpenseid
        JOIN direct d ON d.keytype = 'CapitalAsset' AND d.keyid = ad.genericcapitalassetid
        WHERE e.farmid = p_farmid AND e.sourcetype = 'AssetDepreciation'
          AND NOT EXISTS (SELECT 1 FROM a WHERE a.sourcetype = 'Expense' AND a.sourceid = e.genericexpenseid)
        UNION ALL
        SELECT 'Expense', e.genericexpenseid, d.projectid, d.share, d.costclass
        FROM genericexpenses e
        JOIN direct d ON d.keytype = 'PayrollRun' AND d.keyid = e.sourceid
        WHERE e.farmid = p_farmid AND e.sourcetype = 'GenericPayrollRun'
          AND NOT EXISTS (SELECT 1 FROM a WHERE a.sourcetype = 'Expense' AND a.sourceid = e.genericexpenseid)
    ), customer_payment AS (
        -- What a payment paid follows the sales it paid; the rest follows its
        -- designated advance split (if any).
        SELECT p.genericcustomerpaymentid AS keyid, x.projectid,
               sum(x.amount) / greatest(p.amount, sum(sum(x.amount)) OVER (PARTITION BY p.genericcustomerpaymentid), 0.01) AS share
        FROM genericcustomerpayments p
        JOIN LATERAL (
            SELECT ss.projectid, ca.amountapplied * ss.share AS amount
            FROM customerpaymentallocation ca JOIN sale_share ss ON ss.keyid = ca.saleid
            WHERE ca.module = 'generic' AND ca.farmid = p_farmid AND ca.paymentid = p.genericcustomerpaymentid
              AND ca.status IN ('Posted', 'Reversed')
            UNION ALL
            SELECT d.projectid, d.share * greatest(p.amount - COALESCE((
                       SELECT sum(ca2.amountapplied) FROM customerpaymentallocation ca2
                       WHERE ca2.module = 'generic' AND ca2.farmid = p_farmid
                         AND ca2.paymentid = p.genericcustomerpaymentid AND ca2.status IN ('Posted', 'Reversed')), 0), 0)
            FROM direct d WHERE d.keytype = 'CustomerPayment' AND d.keyid = p.genericcustomerpaymentid
        ) x ON TRUE
        WHERE p.farmid = p_farmid AND p.amount <> 0
        GROUP BY p.genericcustomerpaymentid, p.amount, x.projectid
    ), supplier_payment AS (
        SELECT p.genericsupplierpaymentid AS keyid, x.projectid,
               sum(x.amount) / greatest(p.amount, sum(sum(x.amount)) OVER (PARTITION BY p.genericsupplierpaymentid), 0.01) AS share
        FROM genericsupplierpayments p
        JOIN LATERAL (
            SELECT ps.projectid, sa.amountapplied * ps.share AS amount
            FROM supplierpaymentallocation sa JOIN purchase_share ps ON ps.keyid = sa.documentid
            WHERE sa.module = 'generic' AND sa.farmid = p_farmid AND sa.paymentid = p.genericsupplierpaymentid
              AND sa.documenttype = 'Purchase' AND sa.status IN ('Posted', 'Reversed')
            UNION ALL
            SELECT es.projectid, sa.amountapplied * es.share
            FROM supplierpaymentallocation sa
            JOIN (SELECT keyid, projectid, share FROM direct WHERE keytype = 'Expense'
                  UNION ALL SELECT keyid, projectid, share FROM expense_derived) es ON es.keyid = sa.documentid
            WHERE sa.module = 'generic' AND sa.farmid = p_farmid AND sa.paymentid = p.genericsupplierpaymentid
              AND sa.documenttype = 'Expense' AND sa.status IN ('Posted', 'Reversed')
            UNION ALL
            SELECT d.projectid, sa.amountapplied * d.share
            FROM supplierpaymentallocation sa
            JOIN genericcapitalassetcosts cc ON cc.genericcapitalassetcostid = sa.documentid
            JOIN direct d ON d.keytype = 'CapitalAsset' AND d.keyid = cc.genericcapitalassetid
            WHERE sa.module = 'generic' AND sa.farmid = p_farmid AND sa.paymentid = p.genericsupplierpaymentid
              AND sa.documenttype = 'CapitalAsset' AND sa.status IN ('Posted', 'Reversed')
            UNION ALL
            SELECT d.projectid, d.share * greatest(p.amount - COALESCE((
                       SELECT sum(sa2.amountapplied) FROM supplierpaymentallocation sa2
                       WHERE sa2.module = 'generic' AND sa2.farmid = p_farmid
                         AND sa2.paymentid = p.genericsupplierpaymentid AND sa2.status IN ('Posted', 'Reversed')), 0), 0)
            FROM direct d WHERE d.keytype = 'SupplierPayment' AND d.keyid = p.genericsupplierpaymentid
        ) x ON TRUE
        WHERE p.farmid = p_farmid AND p.amount <> 0
        GROUP BY p.genericsupplierpaymentid, p.amount, x.projectid
    )
    SELECT 'Sale', keyid, NULL::int, projectid, share, 'Direct' FROM sale_share
    UNION ALL SELECT 'SaleProduct', keyid, productid, projectid, share, 'Direct' FROM saleprod_share
    UNION ALL SELECT 'Purchase', keyid, NULL, projectid, share, 'Direct' FROM purchase_share
    UNION ALL SELECT keytype, keyid, NULL, projectid, share, costclass FROM direct
              WHERE keytype NOT IN ('CustomerPayment', 'SupplierPayment')
    UNION ALL SELECT keytype, keyid, NULL, projectid, share, costclass FROM expense_derived
    UNION ALL SELECT 'CustomerPaymentCash', keyid, NULL, projectid, share, 'Direct' FROM customer_payment
    UNION ALL SELECT 'SupplierPaymentCash', keyid, NULL, projectid, share, 'Direct' FROM supplier_payment;
$f$;

-- Split any set of (amount, key) rows into project rows + one General row.
-- Project amounts are rounded to the cent; General takes the remainder, so the
-- parts always add back to the whole exactly.
-- (Implemented inline in each function below as the same three CTEs: rows ->
--  parts -> general, to keep each one a single plannable SQL statement.)

-- ---------------------------------------------------------------------------
-- 3. P&L per project
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fngenericproject_pnl(p_farmid text, p_start date, p_finish date)
RETURNS TABLE(projectid integer, section text, line text, day date, ref text, description text,
              amount numeric, keytype text, keyid integer, costclass text, share numeric)
LANGUAGE sql STABLE AS $f$
    WITH rows AS (
        SELECT row_number() OVER () AS rn, l.* FROM fngenericpnl_lines(p_farmid, p_start, p_finish) l
        WHERE l.amount <> 0
    ), ks AS (
        SELECT * FROM fngenericproject_keyshares(p_farmid)
    ), parts AS (
        SELECT r.rn, k.projectid, round(r.amount * k.share, 2) AS amount, k.costclass, k.share
        FROM rows r JOIN ks k ON k.keytype = r.keytype AND k.keyid = r.keyid
                              AND (r.keytype <> 'SaleProduct' OR k.productid IS NOT DISTINCT FROM r.productid)
        WHERE r.keytype <> 'General'
    )
    SELECT p.projectid, r.section, r.line, r.day, r.ref, coalesce(r.description, ''), p.amount,
           r.keytype, r.keyid, p.costclass, p.share
    FROM parts p JOIN rows r USING (rn)
    WHERE p.amount <> 0
    UNION ALL
    SELECT NULL, r.section, r.line, r.day, r.ref, coalesce(r.description, ''),
           r.amount - COALESCE((SELECT sum(p.amount) FROM parts p WHERE p.rn = r.rn), 0),
           r.keytype, r.keyid, NULL,
           1 - COALESCE((SELECT sum(p.share) FROM parts p WHERE p.rn = r.rn), 0)
    FROM rows r
    WHERE r.amount - COALESCE((SELECT sum(p.amount) FROM parts p WHERE p.rn = r.rn), 0) <> 0;
$f$;

-- ---------------------------------------------------------------------------
-- 4. Cash per project (actual money, from the cash ledger)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fngenericproject_cashrows(p_farmid text, p_start date, p_finish date)
RETURNS TABLE(cashtransactionid bigint, day date, sourcetype text, sourceid integer, description text,
              amount numeric, activity text, category text, keytype text, keyid integer)
LANGUAGE sql STABLE AS $f$
    SELECT t.genericcashtransactionid, t.transactiondate::date, t.sourcetype, t.sourceid, t.description, t.amount,
           CASE
             WHEN t.sourcetype IN ('GenericOwnerContribution', 'GenericOwnerDraw', 'OwnerContribution', 'OwnerWithdrawal',
                                   'LoanReceived', 'LoanRepayment', 'LoanRepaymentReversal', 'LoanCancelled') THEN 'Financing'
             WHEN t.sourcetype IN ('CapitalAsset', 'CapitalAssetCost', 'AssetDisposal') THEN 'Investing'
             WHEN t.sourcetype IN ('OpeningBalance', 'ReconciliationAdjustment') THEN 'Other'
             ELSE 'Operating' END,
           CASE
             WHEN t.sourcetype IN ('Sale', 'SaleReversal') THEN 'Sales paid at the counter'
             WHEN t.sourcetype IN ('CustomerPayment', 'CustomerRefund') THEN 'Customer payments'
             WHEN t.sourcetype = 'Purchase' THEN 'Purchases paid when bought'
             WHEN t.sourcetype IN ('SupplierPayment', 'SupplierRefund', 'GenericSupplierRefund') THEN 'Supplier payments'
             WHEN t.sourcetype IN ('Expense', 'ExpenseReversal') THEN 'Expenses paid'
             WHEN t.sourcetype IN ('Payroll', 'GenericStaffPayment') THEN 'Wages paid'
             WHEN t.sourcetype IN ('CapitalAsset', 'CapitalAssetCost') THEN 'Asset purchases'
             WHEN t.sourcetype = 'AssetDisposal' THEN 'Asset sales'
             WHEN t.sourcetype IN ('GenericOwnerContribution', 'OwnerContribution') THEN 'Owner contributions'
             WHEN t.sourcetype IN ('GenericOwnerDraw', 'OwnerWithdrawal') THEN 'Owner draws'
             WHEN t.sourcetype IN ('LoanReceived', 'LoanCancelled') THEN 'Loans received'
             WHEN t.sourcetype IN ('LoanRepayment', 'LoanRepaymentReversal') THEN 'Loan repayments'
             ELSE 'Other money in / out' END,
           CASE
             WHEN t.sourcetype IN ('Sale', 'SaleReversal') THEN 'Sale'
             WHEN t.sourcetype = 'CustomerPayment' THEN 'CustomerPaymentCash'
             WHEN t.sourcetype = 'Purchase' THEN 'Purchase'
             WHEN t.sourcetype = 'SupplierPayment' THEN 'SupplierPaymentCash'
             WHEN t.sourcetype IN ('Expense', 'ExpenseReversal') THEN 'Expense'
             WHEN t.sourcetype = 'Payroll' THEN 'PayrollRun'
             WHEN t.sourcetype IN ('CapitalAsset', 'CapitalAssetCost', 'AssetDisposal') THEN 'CapitalAsset'
             WHEN t.sourcetype IN ('GenericOwnerContribution', 'GenericOwnerDraw') THEN 'OwnerEntry'
             WHEN t.sourcetype IN ('LoanReceived', 'LoanCancelled', 'LoanRepayment', 'LoanRepaymentReversal') THEN 'Loan'
             ELSE 'General' END,
           CASE
             WHEN t.sourcetype = 'CapitalAssetCost' THEN
                  (SELECT c.genericcapitalassetid FROM genericcapitalassetcosts c WHERE c.genericcapitalassetcostid = t.sourceid)
             WHEN t.sourcetype IN ('LoanRepayment', 'LoanRepaymentReversal') THEN
                  (SELECT lp."GenericLoanId" FROM "GenericLoanPayments" lp WHERE lp."GenericLoanPaymentId" = t.sourceid)
             ELSE t.sourceid END
    FROM genericcashtransactions t
    WHERE t.farmid = p_farmid
      AND t.transactiondate >= p_start AND t.transactiondate < p_finish + 1
      AND COALESCE(t.sourcetype, '') <> 'Transfer'
      AND COALESCE(t.transactiontype, '') NOT IN ('TransferIn', 'TransferOut')
      AND COALESCE(t.status, 'Approved') NOT IN ('Pending', 'Rejected', 'Draft', 'Cancelled', 'Void');
$f$;

CREATE OR REPLACE FUNCTION public.fngenericproject_cash(p_farmid text, p_start date, p_finish date)
RETURNS TABLE(projectid integer, cashtransactionid bigint, day date, activity text, category text,
              sourcetype text, sourceid integer, description text, amount numeric, share numeric)
LANGUAGE sql STABLE AS $f$
    WITH rows AS (
        SELECT * FROM fngenericproject_cashrows(p_farmid, p_start, p_finish)
    ), ks AS (
        SELECT keytype, keyid, projectid, sum(share) AS share
        FROM fngenericproject_keyshares(p_farmid)
        WHERE productid IS NULL
        GROUP BY 1, 2, 3
    ), parts AS (
        SELECT r.cashtransactionid, k.projectid, round(r.amount * k.share, 2) AS amount, k.share
        FROM rows r JOIN ks k ON k.keytype = r.keytype AND k.keyid = r.keyid
    )
    SELECT p.projectid, r.cashtransactionid, r.day, r.activity, r.category, r.sourcetype, r.sourceid, r.description,
           p.amount, p.share
    FROM parts p JOIN rows r USING (cashtransactionid)
    WHERE p.amount <> 0
    UNION ALL
    SELECT NULL, r.cashtransactionid, r.day, r.activity, r.category, r.sourcetype, r.sourceid, r.description,
           r.amount - COALESCE((SELECT sum(p.amount) FROM parts p WHERE p.cashtransactionid = r.cashtransactionid), 0),
           1 - COALESCE((SELECT sum(p.share) FROM parts p WHERE p.cashtransactionid = r.cashtransactionid), 0)
    FROM rows r
    WHERE r.amount - COALESCE((SELECT sum(p.amount) FROM parts p WHERE p.cashtransactionid = r.cashtransactionid), 0) <> 0;
$f$;

-- ---------------------------------------------------------------------------
-- 5. Balances as they stand now, per project (NULL = General)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fngenericproject_balances(p_farmid text)
RETURNS TABLE(projectid integer, kind text, documenttype text, documentid integer, day date,
              ref text, party text, duedate date, amount numeric)
LANGUAGE sql STABLE AS $f$
    WITH ks AS (SELECT * FROM fngenericproject_keyshares(p_farmid) WHERE productid IS NULL),
    docs AS (
        -- Receivables: approved sales with money still owed.
        SELECT 'Receivable'::text AS kind, 'Sale'::text AS documenttype, s.genericsaleid AS documentid,
               s.saledate::date AS day, coalesce(nullif(s.receiptnumber, ''), 'Sale #' || s.genericsaleid) AS ref,
               c.customername AS party, s.duedate, s.balance AS amount, 'Sale'::text AS keytype
        FROM genericsales s LEFT JOIN genericcustomers c ON c.genericcustomerid = s.genericcustomerid AND c.farmid = s.farmid
        WHERE s.farmid = p_farmid AND s.status = 'Approved' AND NOT coalesce(s.isdeleted, false) AND s.balance > 0
        UNION ALL
        -- Payables: approved purchases and expenses not yet paid.
        SELECT 'Payable', 'Purchase', p.genericpurchaseid, p.purchasedate::date,
               coalesce(nullif(p.invoicenumber, ''), 'Purchase #' || p.genericpurchaseid), sp.suppliername, NULL::date,
               p.balance, 'Purchase'
        FROM genericpurchases p LEFT JOIN genericsuppliers sp ON sp.genericsupplierid = p.genericsupplierid
        WHERE p.farmid = p_farmid AND p.status = 'Approved' AND NOT coalesce(p.isdeleted, false) AND p.balance > 0
        UNION ALL
        SELECT 'Payable', 'Expense', e.genericexpenseid, e.expensedate::date, 'Expense #' || e.genericexpenseid,
               coalesce(sp.suppliername, e.paidto), e.duedate, e.amount - coalesce(e.amountpaid, e.amount), 'Expense'
        FROM genericexpenses e LEFT JOIN genericsuppliers sp ON sp.genericsupplierid = e.genericsupplierid
        WHERE e.farmid = p_farmid AND e.status = 'Approved' AND NOT coalesce(e.isdeleted, false)
          AND e.amount - coalesce(e.amountpaid, e.amount) > 0
        UNION ALL
        -- Customer advances: money received and not yet applied to any sale.
        SELECT 'CustomerAdvance', 'CustomerPayment', p.genericcustomerpaymentid, p.paymentdate::date,
               'Payment #' || p.genericcustomerpaymentid, c.customername, NULL,
               p.amount - COALESCE((SELECT sum(ca.amountapplied) FROM customerpaymentallocation ca
                                    WHERE ca.module = 'generic' AND ca.farmid = p_farmid
                                      AND ca.paymentid = p.genericcustomerpaymentid AND ca.status = 'Posted'), 0),
               'CustomerPaymentAdvance'
        FROM genericcustomerpayments p LEFT JOIN genericcustomers c ON c.genericcustomerid = p.genericcustomerid AND c.farmid = p.farmid
        WHERE p.farmid = p_farmid AND COALESCE(p.status, 'Approved') NOT IN ('Reversed', 'Cancelled', 'Rejected', 'Pending')
        UNION ALL
        -- Supplier advances: money paid and not yet applied to anything.
        SELECT 'SupplierAdvance', 'SupplierPayment', p.genericsupplierpaymentid, p.paymentdate::date,
               'Payment #' || p.genericsupplierpaymentid, sp.suppliername, NULL,
               p.amount - COALESCE((SELECT sum(sa.amountapplied) FROM supplierpaymentallocation sa
                                    WHERE sa.module = 'generic' AND sa.farmid = p_farmid
                                      AND sa.paymentid = p.genericsupplierpaymentid AND sa.status = 'Posted'), 0),
               'SupplierPaymentAdvance'
        FROM genericsupplierpayments p LEFT JOIN genericsuppliers sp ON sp.genericsupplierid = p.genericsupplierid
        WHERE p.farmid = p_farmid AND COALESCE(p.status, 'Approved') NOT IN ('Reversed', 'Cancelled', 'Rejected', 'Pending')
    ), d AS (
        SELECT row_number() OVER () AS rn, * FROM docs WHERE amount > 0
    ), dshare AS (
        -- An advance's project is its designated split (the CustomerPayment /
        -- SupplierPayment allocation), nothing else.
        SELECT d.rn, a.genericprojectid AS projectid, a.share
        FROM d JOIN genericprojectallocations a ON a.farmid = p_farmid AND a.status = 'Active'
             AND a.sourcetype = CASE d.keytype WHEN 'CustomerPaymentAdvance' THEN 'CustomerPayment' ELSE 'SupplierPayment' END
             AND a.sourceid = d.documentid
        WHERE d.keytype IN ('CustomerPaymentAdvance', 'SupplierPaymentAdvance')
        UNION ALL
        SELECT d.rn, k.projectid, k.share
        FROM d JOIN ks k ON k.keytype = d.keytype AND k.keyid = d.documentid
    ), parts AS (
        SELECT d.rn, s.projectid, round(d.amount * s.share, 2) AS amount FROM d JOIN dshare s USING (rn)
    )
    SELECT p.projectid, d.kind, d.documenttype, d.documentid, d.day, d.ref, d.party, d.duedate, p.amount
    FROM parts p JOIN d USING (rn) WHERE p.amount <> 0
    UNION ALL
    SELECT NULL, d.kind, d.documenttype, d.documentid, d.day, d.ref, d.party, d.duedate,
           d.amount - COALESCE((SELECT sum(p.amount) FROM parts p WHERE p.rn = d.rn), 0)
    FROM d WHERE d.amount - COALESCE((SELECT sum(p.amount) FROM parts p WHERE p.rn = d.rn), 0) <> 0;
$f$;

-- ---------------------------------------------------------------------------
-- 6. What the pages call
-- ---------------------------------------------------------------------------

-- p_projects: NULL = every project (and General), else the ids to include.
-- Purchases bought for each project (value, not cost): line amount x share.
CREATE OR REPLACE FUNCTION public.fngenericproject_purchases(p_farmid text, p_start date, p_finish date)
RETURNS TABLE(projectid integer, purchaseid integer, purchaseitemid integer, productid integer, day date,
              ref text, supplier text, quantity numeric, amount numeric, status text)
LANGUAGE sql STABLE AS $f$
    SELECT a.genericprojectid, p.genericpurchaseid, i.genericpurchaseitemid, i.genericproductid, p.purchasedate::date,
           coalesce(nullif(p.invoicenumber, ''), 'Purchase #' || p.genericpurchaseid), sp.suppliername,
           round(i.quantity * a.share * coalesce(nullif(i.unitfactor, 0), 1), 4),
           round(i.linetotal * a.share, 2), p.status
    FROM genericprojectallocations a
    JOIN genericpurchaseitems i ON i.genericpurchaseitemid = a.sourcelineid AND i.genericpurchaseid = a.sourceid
    JOIN genericpurchases p ON p.genericpurchaseid = i.genericpurchaseid AND p.farmid = p_farmid
    LEFT JOIN genericsuppliers sp ON sp.genericsupplierid = p.genericsupplierid
    WHERE a.farmid = p_farmid AND a.status = 'Active' AND a.sourcetype = 'PurchaseLine'
      AND p.status = 'Approved' AND NOT coalesce(p.isdeleted, false)
      AND (p_start IS NULL OR p.purchasedate >= p_start) AND (p_finish IS NULL OR p.purchasedate < p_finish + 1);
$f$;

CREATE OR REPLACE FUNCTION public.spgenericproject_summary(
    p_farmid text, p_projectids integer[], p_from date, p_to date)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE
    v_from date := COALESCE(p_from, DATE '1900-01-01');
    v_to   date := COALESCE(p_to, DATE '2999-12-31');
    v_out  jsonb;
BEGIN
    WITH pnl AS (
        SELECT projectid,
               sum(amount) FILTER (WHERE section = 'revenue') AS revenue,
               sum(amount) FILTER (WHERE section = 'direct') AS direct,
               sum(amount) FILTER (WHERE section = 'direct' AND line = 'Cost of goods sold') AS cogs,
               sum(amount) FILTER (WHERE section = 'operating' AND COALESCE(costclass, 'Direct') <> 'Overhead') AS operating,
               sum(amount) FILTER (WHERE section = 'operating' AND costclass = 'Overhead') AS overhead,
               sum(amount) FILTER (WHERE section = 'other' AND line = 'Depreciation') AS depreciation,
               sum(amount) FILTER (WHERE section = 'other' AND line <> 'Depreciation') AS financingcost,
               sum(amount) FILTER (WHERE section = 'owner' AND amount > 0) AS ownerin,
               -sum(amount) FILTER (WHERE section = 'owner' AND amount < 0) AS ownerout,
               sum(amount) FILTER (WHERE section = 'capital') AS capital
        FROM fngenericproject_pnl(p_farmid, v_from, v_to) GROUP BY projectid
    ), cash AS (
        SELECT projectid,
               sum(amount) FILTER (WHERE amount > 0) AS cashin,
               -sum(amount) FILTER (WHERE amount < 0) AS cashout,
               sum(amount) FILTER (WHERE category IN ('Customer payments', 'Sales paid at the counter')) AS customercash,
               -sum(amount) FILTER (WHERE category IN ('Supplier payments', 'Purchases paid when bought')) AS procurementcash,
               -sum(amount) FILTER (WHERE category IN ('Expenses paid', 'Wages paid')) AS expensecash,
               sum(amount) FILTER (WHERE activity = 'Operating') AS operating,
               sum(amount) FILTER (WHERE activity = 'Investing') AS investing,
               sum(amount) FILTER (WHERE activity = 'Financing') AS financing,
               sum(amount) AS net
        FROM fngenericproject_cash(p_farmid, v_from, v_to) GROUP BY projectid
    ), bal AS (
        SELECT projectid,
               sum(amount) FILTER (WHERE kind = 'Receivable') AS receivable,
               sum(amount) FILTER (WHERE kind = 'Receivable' AND duedate < (now() at time zone 'utc')::date) AS overdue,
               sum(amount) FILTER (WHERE kind = 'Payable') AS payable,
               sum(amount) FILTER (WHERE kind = 'CustomerAdvance') AS customeradvance,
               sum(amount) FILTER (WHERE kind = 'SupplierAdvance') AS supplieradvance
        FROM fngenericproject_balances(p_farmid) GROUP BY projectid
    ), pur AS (
        SELECT projectid, sum(amount) AS purchasevalue FROM fngenericproject_purchases(p_farmid, v_from, v_to) GROUP BY 1
    ), ids AS (
        SELECT genericprojectid AS projectid FROM genericprojects
        WHERE farmid = p_farmid AND (p_projectids IS NULL OR genericprojectid = ANY (p_projectids))
        UNION ALL SELECT NULL WHERE p_projectids IS NULL
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'projectId', i.projectid,
        'projectNumber', p.projectnumber, 'name', COALESCE(p.name, 'General company activity'),
        'kind', p.kind, 'status', p.status, 'customerName',
            (SELECT c.customername FROM genericcustomers c WHERE c.farmid = p.farmid AND c.genericcustomerid = p.genericcustomerid),
        'expectedEndDate', p.expectedenddate, 'actualEndDate', p.actualenddate,
        'awardValue', p.awardvalue, 'approvedBudget', p.approvedbudget,
        'revenue', COALESCE(pn.revenue, 0),
        'costOfGoodsSold', COALESCE(pn.cogs, 0),
        'directCosts', COALESCE(pn.direct, 0),
        'grossProfit', COALESCE(pn.revenue, 0) - COALESCE(pn.direct, 0),
        'operatingExpenses', COALESCE(pn.operating, 0),
        'allocatedOverhead', COALESCE(pn.overhead, 0),
        'operatingProfit', COALESCE(pn.revenue, 0) - COALESCE(pn.direct, 0) - COALESCE(pn.operating, 0) - COALESCE(pn.overhead, 0),
        'depreciation', COALESCE(pn.depreciation, 0),
        'financingCosts', COALESCE(pn.financingcost, 0),
        'netProfit', COALESCE(pn.revenue, 0) - COALESCE(pn.direct, 0) - COALESCE(pn.operating, 0)
                     - COALESCE(pn.overhead, 0) - COALESCE(pn.depreciation, 0) - COALESCE(pn.financingcost, 0),
        'profitMarginPercent', CASE WHEN COALESCE(pn.revenue, 0) = 0 THEN NULL ELSE round(
                     (COALESCE(pn.revenue, 0) - COALESCE(pn.direct, 0) - COALESCE(pn.operating, 0) - COALESCE(pn.overhead, 0)
                      - COALESCE(pn.depreciation, 0) - COALESCE(pn.financingcost, 0)) * 100 / pn.revenue, 1) END,
        'totalCosts', COALESCE(pn.direct, 0) + COALESCE(pn.operating, 0) + COALESCE(pn.overhead, 0)
                     + COALESCE(pn.depreciation, 0) + COALESCE(pn.financingcost, 0),
        'capitalSpend', COALESCE(pn.capital, 0),
        'ownerContributed', COALESCE(pn.ownerin, 0),
        'ownerDrawn', COALESCE(pn.ownerout, 0),
        'netOwnerFunding', COALESCE(pn.ownerin, 0) - COALESCE(pn.ownerout, 0),
        'purchaseValue', COALESCE(pu.purchasevalue, 0),
        'cashIn', COALESCE(ca.cashin, 0),
        'cashOut', COALESCE(ca.cashout, 0),
        'customerCashReceived', COALESCE(ca.customercash, 0),
        'procurementCashPaid', COALESCE(ca.procurementcash, 0),
        'expenseCashPaid', COALESCE(ca.expensecash, 0),
        'operatingCashFlow', COALESCE(ca.operating, 0),
        'investingCashFlow', COALESCE(ca.investing, 0),
        'financingCashFlow', COALESCE(ca.financing, 0),
        'netCashFlow', COALESCE(ca.net, 0),
        -- Money the project has used beyond what it brought in, before owner
        -- funding: how much working capital it is tying up.
        'workingCapitalExposure', GREATEST(-(COALESCE(ca.operating, 0) + COALESCE(ca.investing, 0)), 0),
        'receivable', COALESCE(b.receivable, 0),
        'overdueReceivable', COALESCE(b.overdue, 0),
        'payable', COALESCE(b.payable, 0),
        'customerAdvances', COALESCE(b.customeradvance, 0),
        'supplierAdvances', COALESCE(b.supplieradvance, 0),
        'remainingAwardValue', CASE WHEN p.awardvalue IS NULL THEN NULL
                                    ELSE p.awardvalue - COALESCE((SELECT sum(x.amount) FROM fngenericproject_pnl(p_farmid, DATE '1900-01-01', DATE '2999-12-31') x
                                                                   WHERE x.projectid = i.projectid AND x.section = 'revenue'), 0) END)
        ORDER BY i.projectid NULLS LAST), '[]'::jsonb)
      INTO v_out
      FROM ids i
      LEFT JOIN genericprojects p ON p.genericprojectid = i.projectid
      LEFT JOIN pnl pn ON pn.projectid IS NOT DISTINCT FROM i.projectid
      LEFT JOIN cash ca ON ca.projectid IS NOT DISTINCT FROM i.projectid
      LEFT JOIN bal b ON b.projectid IS NOT DISTINCT FROM i.projectid
      LEFT JOIN pur pu ON pu.projectid IS NOT DISTINCT FROM i.projectid;
    RETURN v_out;
END
$f$;

-- P&L entries in the exact shape the Generic P&L page reads. p_scope:
--   'all'      -> the whole company (same as before 484)
--   'general'  -> only what is not given to any project
--   'projects' -> the projects in p_projectids (one or many)
CREATE OR REPLACE FUNCTION public.spgenericproject_pnlentries(
    p_farmid text, p_scope text, p_projectids integer[], p_from date, p_to date)
RETURNS TABLE(section text, line text, day date, ref text, description text, amount numeric)
LANGUAGE sql STABLE AS $f$
    SELECT e.section, e.line, e.day, e.ref, e.description, e.amount
    FROM fngenericpnl_entries(p_farmid, p_from, p_to) e WHERE COALESCE(p_scope, 'all') = 'all'
    UNION ALL
    SELECT x.section, x.line, x.day, x.ref, x.description, sum(x.amount)
    FROM fngenericproject_pnl(p_farmid, p_from, p_to) x
    WHERE (p_scope = 'general' AND x.projectid IS NULL)
       OR (p_scope = 'projects' AND x.projectid = ANY (p_projectids))
    GROUP BY x.section, x.line, x.day, x.ref, x.description, x.keytype, x.keyid
    HAVING sum(x.amount) <> 0;
$f$;

-- Cash flow for a scope: rows + totals by activity and category.
CREATE OR REPLACE FUNCTION public.spgenericproject_cashflow(
    p_farmid text, p_scope text, p_projectids integer[], p_from date, p_to date)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH r AS (
        SELECT * FROM fngenericproject_cash(p_farmid, p_from, p_to) c
        WHERE COALESCE(p_scope, 'all') = 'all'
           OR (p_scope = 'general' AND c.projectid IS NULL)
           OR (p_scope = 'projects' AND c.projectid = ANY (p_projectids))
    )
    SELECT jsonb_build_object(
        'moneyIn', COALESCE((SELECT sum(amount) FROM r WHERE amount > 0), 0),
        'moneyOut', COALESCE((SELECT -sum(amount) FROM r WHERE amount < 0), 0),
        'net', COALESCE((SELECT sum(amount) FROM r), 0),
        'byActivity', COALESCE((SELECT jsonb_object_agg(activity, total) FROM
                        (SELECT activity, sum(amount) AS total FROM r GROUP BY 1) a), '{}'::jsonb),
        'byCategory', COALESCE((SELECT jsonb_agg(jsonb_build_object('activity', activity, 'category', category,
                        'moneyIn', moneyin, 'moneyOut', moneyout, 'net', net) ORDER BY activity, category) FROM
                        (SELECT activity, category, COALESCE(sum(amount) FILTER (WHERE amount > 0), 0) AS moneyin,
                                COALESCE(-sum(amount) FILTER (WHERE amount < 0), 0) AS moneyout, sum(amount) AS net
                         FROM r GROUP BY 1, 2) c), '[]'::jsonb),
        'rows', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                        'projectId', projectid, 'cashTransactionId', cashtransactionid, 'date', day,
                        'activity', activity, 'category', category, 'sourceType', sourcetype, 'sourceId', sourceid,
                        'description', description, 'amount', amount, 'share', round(share, 4))
                        ORDER BY day DESC, cashtransactionid DESC) FROM r), '[]'::jsonb));
$f$;

-- Every transaction behind a project's numbers, newest first.
CREATE OR REPLACE FUNCTION public.spgenericproject_transactions(
    p_farmid text, p_projectid integer, p_from date, p_to date)
 RETURNS jsonb LANGUAGE plpgsql STABLE AS $f$
DECLARE v_from date := COALESCE(p_from, DATE '1900-01-01'); v_to date := COALESCE(p_to, DATE '2999-12-31');
BEGIN
    PERFORM fngenericproject_require(p_farmid, p_projectid);
    RETURN jsonb_build_object(
        'pnl', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                    'section', section, 'line', line, 'date', day, 'ref', ref, 'description', description,
                    'amount', amount, 'sourceType', keytype, 'sourceId', keyid, 'costClass', costclass,
                    'share', round(share, 4)) ORDER BY day DESC, ref)
                 FROM fngenericproject_pnl(p_farmid, v_from, v_to) WHERE projectid = p_projectid), '[]'::jsonb),
        'purchases', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                    'purchaseId', purchaseid, 'lineId', purchaseitemid, 'productId', productid,
                    'productName', (SELECT productname FROM genericproducts g WHERE g.genericproductid = x.productid),
                    'date', day, 'ref', ref, 'supplier', supplier, 'quantity', quantity, 'amount', amount)
                    ORDER BY day DESC, purchaseid DESC)
                 FROM fngenericproject_purchases(p_farmid, v_from, v_to) x WHERE projectid = p_projectid), '[]'::jsonb),
        'balances', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                    'kind', kind, 'documentType', documenttype, 'documentId', documentid, 'date', day,
                    'ref', ref, 'party', party, 'dueDate', duedate, 'amount', amount) ORDER BY kind, day)
                 FROM fngenericproject_balances(p_farmid) WHERE projectid = p_projectid), '[]'::jsonb),
        'cash', spgenericproject_cashflow(p_farmid, 'projects', ARRAY[p_projectid], v_from, v_to));
END
$f$;

-- Proof that nothing is double counted: company total vs projects + General.
CREATE OR REPLACE FUNCTION public.spgenericproject_reconcile(p_farmid text, p_from date, p_to date)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH company AS (
        SELECT section, sum(amount) AS amount FROM fngenericpnl_entries(p_farmid, p_from, p_to) GROUP BY 1
    ), split AS (
        SELECT section, sum(amount) FILTER (WHERE projectid IS NOT NULL) AS projects,
               sum(amount) FILTER (WHERE projectid IS NULL) AS general
        FROM fngenericproject_pnl(p_farmid, p_from, p_to) GROUP BY 1
    ), cashco AS (
        SELECT COALESCE(sum(amount), 0) AS amount FROM fngenericproject_cashrows(p_farmid, p_from, p_to)
    ), cashsplit AS (
        SELECT COALESCE(sum(amount) FILTER (WHERE projectid IS NOT NULL), 0) AS projects,
               COALESCE(sum(amount) FILTER (WHERE projectid IS NULL), 0) AS general
        FROM fngenericproject_cash(p_farmid, p_from, p_to)
    )
    SELECT jsonb_build_object(
        'pnl', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                  'section', COALESCE(c.section, s.section),
                  'company', COALESCE(c.amount, 0),
                  'projects', COALESCE(s.projects, 0),
                  'general', COALESCE(s.general, 0),
                  'difference', COALESCE(c.amount, 0) - COALESCE(s.projects, 0) - COALESCE(s.general, 0)))
               FROM company c FULL JOIN split s ON s.section = c.section), '[]'::jsonb),
        'cash', (SELECT jsonb_build_object('company', cashco.amount, 'projects', cashsplit.projects,
                        'general', cashsplit.general,
                        'difference', cashco.amount - cashsplit.projects - cashsplit.general)
                 FROM cashco, cashsplit),
        'balanced', NOT EXISTS (
                SELECT 1 FROM company c FULL JOIN split s ON s.section = c.section
                WHERE COALESCE(c.amount, 0) <> COALESCE(s.projects, 0) + COALESCE(s.general, 0))
            AND (SELECT cashco.amount = cashsplit.projects + cashsplit.general FROM cashco, cashsplit));
$f$;

-- Index support for the engine's joins.
CREATE INDEX IF NOT EXISTS ix_customerpaymentallocation_generic_payment
    ON customerpaymentallocation (farmid, paymentid) WHERE module = 'generic';
CREATE INDEX IF NOT EXISTS ix_supplierpaymentallocation_generic_payment
    ON supplierpaymentallocation (farmid, paymentid) WHERE module = 'generic';

COMMIT;
