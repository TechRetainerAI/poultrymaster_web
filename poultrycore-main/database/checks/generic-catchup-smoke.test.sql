-- Generic catch-up smoke test (apply-generic-catchup.ps1). Read-only calls,
-- wrapped in BEGIN/ROLLBACK: for every Generic company, the pages that failed on
-- production on 2026-11-23 must now run -- P&L (the exact query in
-- Business/GenericProfitLoss.cs), Expenses, Products, Supplier credits,
-- Payroll runs and Capital assets -- each called the way the API calls it.
BEGIN;
DO $chk$
DECLARE
    v_farm text;
    v_n    integer := 0;
    v_step text;
BEGIN
    FOR v_farm IN
        SELECT DISTINCT farmid FROM (
            SELECT farmid FROM genericsales UNION SELECT farmid FROM genericexpenses
            UNION SELECT farmid FROM genericpurchases) x
    LOOP
        v_step := 'P&L';
        EXECUTE $pl$ SELECT count(*) FROM ( 
            WITH sales AS (
                SELECT s.genericsaleid, s.saledate::date AS day, s.genericsubscriptionid,
                       coalesce(nullif(s.receiptnumber, ''), 'Sale #' || s.genericsaleid) AS ref,
                       coalesce(c.customername, s.notes, 'Walk-in sale') AS description,
                       s.totalamount - coalesce(s.taxamount, 0) AS revenue
                FROM genericsales s
                LEFT JOIN genericcustomers c ON c.farmid = s.farmid AND c.genericcustomerid = s.genericcustomerid
                WHERE s.farmid = $1 AND s.status = 'Approved' AND NOT coalesce(s.isdeleted, false)
                  AND s.saledate >= $2 AND s.saledate < $3 + 1
            ), movement_cost AS (
                SELECT m.referenceid, m.genericproductid, sum(abs(coalesce(m.totalcostvalue, m.unitcost * m.quantity))) AS cost
                FROM genericstockmovements m JOIN sales s ON s.genericsaleid = m.referenceid
                WHERE m.farmid = $1 AND m.referencetype = 'Sale' AND m.movementtype = 'SaleOut'
                GROUP BY m.referenceid, m.genericproductid
            ), item_cost AS (
                SELECT i.genericsaleid, i.genericproductid, sum(i.costamount * i.quantity) AS cost
                FROM genericsaleitems i JOIN sales s USING (genericsaleid)
                WHERE i.farmid = $1 AND i.itemtype = 'Product'
                GROUP BY i.genericsaleid, i.genericproductid
            ), costs AS (
                SELECT coalesce(m.referenceid, i.genericsaleid) AS id, sum(coalesce(m.cost, i.cost, 0)) AS cost
                FROM movement_cost m FULL JOIN item_cost i ON m.referenceid = i.genericsaleid AND m.genericproductid = i.genericproductid
                GROUP BY coalesce(m.referenceid, i.genericsaleid)
            ), loans AS (
                SELECT * FROM spgenericloan_list($1) WHERE "Status" NOT IN ('Cancelled', 'Reversed')
            ), entries(section, line, day, ref, description, amount) AS (
                SELECT 'revenue', CASE WHEN genericsubscriptionid IS NULL THEN 'Sales' ELSE 'Subscription income' END,
                       day, ref, description, revenue FROM sales
                UNION ALL
                SELECT 'direct', 'Cost of goods sold', s.day, s.ref, s.description, c.cost
                FROM costs c JOIN sales s ON s.genericsaleid = c.id
                UNION ALL
                SELECT 'direct', 'Stock losses', a.adjustmentdate::date, 'Adjustment #' || a.genericstockadjustmentid,
                       coalesce(a.reason, 'Stock decrease'), abs(coalesce(m.totalcostvalue, m.quantity * m.unitcost))
                FROM genericstockadjustments a JOIN genericstockmovements m ON m.farmid = a.farmid
                     AND m.referenceid = a.genericstockadjustmentid AND m.referencetype = 'Adjustment' AND m.movementtype = 'AdjustmentOut'
                WHERE a.farmid = $1 AND a.adjustmenttype = 'Decrease' AND a.status = 'Approved'
                  AND a.adjustmentdate >= $2 AND a.adjustmentdate < $3 + 1
                UNION ALL
                SELECT CASE WHEN e.sourcetype = 'AssetDepreciation' OR lower(c.name) = 'depreciation' THEN 'other' ELSE 'operating' END,
                       CASE WHEN e.sourcetype = 'AssetDepreciation' THEN 'Depreciation' ELSE coalesce(c.name, 'Uncategorised expenses') END,
                       e.expensedate::date, 'Expense #' || e.genericexpenseid, coalesce(e.description, e.paidto, 'Expense'), e.amount
                FROM genericexpenses e LEFT JOIN genericexpensecategories c ON c.farmid = e.farmid AND c.genericexpensecategoryid = e.genericexpensecategoryid
                WHERE e.farmid = $1 AND e.status = 'Approved' AND NOT coalesce(e.isdeleted, false)
                  AND coalesce(e.sourcetype, '') NOT IN ('GenericPurchase', 'GenericSupplierPayment', 'Purchase', 'SupplierPayment')
                  AND e.expensedate >= $2 AND e.expensedate < $3 + 1
                UNION ALL
                SELECT 'operating', 'Payroll', coalesce(p.paydate, p.paidat)::date, 'Payroll #' || p.genericpayrollrunid,
                       concat('Pay period ', p.periodstart::date, ' to ', p.periodend::date), p.totalgrosspay
                FROM genericpayrollruns p
                WHERE p.farmid = $1 AND p.status = 'Paid' AND NOT coalesce(p.isdeleted, false)
                  AND coalesce(p.paydate, p.paidat) >= $2 AND coalesce(p.paydate, p.paidat) < $3 + 1
                  AND NOT EXISTS (SELECT 1 FROM genericexpenses e WHERE e.farmid = p.farmid AND e.sourcetype = 'GenericPayrollRun'
                                  AND e.sourceid = p.genericpayrollrunid AND e.status = 'Approved' AND NOT coalesce(e.isdeleted, false))
                UNION ALL
                SELECT 'owner', CASE WHEN entrytype = 'Contribution' THEN 'Owner contributions' ELSE 'Owner draws' END,
                       entrydate::date, coalesce(referenceno, 'Owner entry #' || genericownerentryid), coalesce(ownername, notes, 'Owner'),
                       CASE WHEN entrytype = 'Contribution' THEN amount ELSE -amount END
                FROM genericownercontributiondraws
                WHERE farmid = $1 AND status = 'Posted' AND entrydate >= $2 AND entrydate < $3 + 1
                UNION ALL
                SELECT 'borrowing', 'Loan proceeds', "LoanDate"::date, 'Loan #' || "GenericLoanId", "LenderName", "AmountReceived"
                FROM loans WHERE "LoanDate" >= $2 AND "LoanDate" < $3 + 1
                UNION ALL
                SELECT v.section, v.line, p."PaymentDate"::date, 'Payment #' || p."GenericLoanPaymentId", l."LenderName", v.amount
                FROM loans l CROSS JOIN LATERAL spgenericloan_payments(l."GenericLoanId", $1) p
                CROSS JOIN LATERAL (VALUES ('borrowing', 'Principal repaid', -p."PrincipalAmount"),
                                           ('other', 'Loan interest', p."InterestAmount"),
                                           ('other', 'Loan fees', p."FeeAmount"),
                                           -- 455: the "Other" part of a repayment left the bank too and paid off no debt.
                                           ('other', 'Loan other charges', p."OtherAmount")) v(section, line, amount)
                WHERE NOT p."IsReversed" AND p."PaymentDate" >= $2 AND p."PaymentDate" < $3 + 1
                UNION ALL
                -- 453: every posted cost line of the capital asset register (acquisitions,
                -- added costs and signed corrections), dated when it was incurred.
                SELECT 'capital', 'Asset purchases', c.costdate, 'Asset ' || a.assetnumber, a.assetname, c.amount
                FROM genericcapitalassetcosts c JOIN genericcapitalassets a ON a.genericcapitalassetid = c.genericcapitalassetid
                WHERE c.farmid = $1 AND c.status = 'Posted' AND c.costdate >= $2 AND c.costdate < $3 + 1
            )
            SELECT section, line, day, ref, coalesce(description, ''), amount FROM entries
            WHERE amount <> 0 ORDER BY day DESC, ref, section, line
             ) q $pl$
            USING v_farm, (current_date - 30), current_date;
        v_step := 'Expenses';
        -- the API reads the column by name, case-insensitively (Npgsql GetOrdinal)
        IF EXISTS (SELECT 1 FROM spgenericexpense_getall(p_farmid => v_farm, p_status => NULL::text, p_fromdate => NULL::timestamp, p_todate => NULL::timestamp) e
                   WHERE NOT EXISTS (SELECT 1 FROM jsonb_object_keys(to_jsonb(e)) k WHERE lower(k) = 'amountpaid')) THEN
            RAISE EXCEPTION 'FAIL catch-up: Expenses list for % has no AmountPaid column', v_farm;
        END IF;
        v_step := 'Products';
        PERFORM 1 FROM spgenericproduct_getall(p_farmid => v_farm::text);
        v_step := 'Supplier credits';
        PERFORM 1 FROM spgenericsuppliercredit_list(v_farm::text);
        v_step := 'Payroll runs';
        PERFORM 1 FROM spgenericpayrollrun_getall(p_farmid => v_farm::text, p_status => NULL::text);
        v_step := 'Capital assets';
        PERFORM 1 FROM spgenericasset_list(v_farm::text);
        v_n := v_n + 1;
    END LOOP;
    RAISE NOTICE 'ok catch-up P&L, Expenses, Products, Supplier credits, Payroll runs and Capital assets run for all % Generic companies', v_n;
    RAISE NOTICE 'generic catch-up: all checks passed';
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'FAIL catch-up at % for company %: %', v_step, v_farm, SQLERRM;
END $chk$;
ROLLBACK;
