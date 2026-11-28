-- =============================================================================
-- 525_James_GenericPnlCogsInDirectTotal.postgres.sql
--
-- Per owner's instruction: show Cost of Goods Sold as a counted line inside
-- Direct Production Costs (under Inventory purchases), INCLUDED in the Direct
-- total -- not the excluded 'cogsmemo' reference line from 522.
--
-- Effect: Total Direct Production Costs = Inventory purchases + Cost of goods
-- sold, so the stock's cost is counted both when bought (purchases) and when
-- sold (COGS). This lowers Gross and Net profit by the COGS amount. This is the
-- owner's explicit choice for the Generic P&L.
--
-- Only the COGS arm's section changes ('cogsmemo' -> 'direct'); everything else
-- is unchanged from 524. Idempotent: CREATE OR REPLACE.
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
    -- 525: Cost of Goods Sold is a COUNTED Direct line (owner's choice), summed
    -- into Total Direct Production Costs alongside Inventory purchases.
    SELECT 'direct', 'Cost of goods sold', s.day, s.ref, s.description, c.cost, 'SaleProduct', s.genericsaleid, c.productid, NULL
    FROM costs c JOIN sales s ON s.genericsaleid = c.id
    UNION ALL
    -- Inventory purchases: the APPROVED purchase joined to its auto-created
    -- expense (same shape as Financial Activity 523).
    SELECT 'direct', 'Inventory purchases', e.expensedate::date,
           'Expense #' || e.genericexpenseid, coalesce(e.description, e.paidto, 'Purchase'), e.amount,
           'Expense', e.genericexpenseid, NULL, e.genericexpenseid
    FROM genericpurchases pu
    JOIN genericexpenses e ON e.genericexpenseid = pu.genericexpenseid AND e.farmid = pu.farmid
    WHERE pu.farmid = p_farmid AND pu.status = 'Approved' AND NOT coalesce(pu.isdeleted, false)
      AND e.status = 'Approved' AND NOT coalesce(e.isdeleted, false)
      AND e.expensedate >= p_start AND e.expensedate < p_finish + 1
    UNION ALL
    -- Operating expenses: every approved expense EXCEPT purchase mirrors (Direct,
    -- above), supplier payments and internal stock usage.
    SELECT CASE WHEN e.sourcetype = 'AssetDepreciation' OR lower(c.name) = 'depreciation' THEN 'other' ELSE 'operating' END,
           CASE WHEN e.sourcetype = 'AssetDepreciation' THEN 'Depreciation' ELSE coalesce(c.name, 'Uncategorised expenses') END,
           e.expensedate::date, 'Expense #' || e.genericexpenseid, coalesce(e.description, e.paidto, 'Expense'), e.amount,
           'Expense', e.genericexpenseid, NULL, e.genericexpenseid
    FROM genericexpenses e LEFT JOIN genericexpensecategories c ON c.farmid = e.farmid AND c.genericexpensecategoryid = e.genericexpensecategoryid
    WHERE e.farmid = p_farmid AND e.status = 'Approved' AND NOT coalesce(e.isdeleted, false)
      AND NOT public.fngenericpurchase_ismirrorexpense(e.genericexpenseid)
      AND coalesce(e.sourcetype, '') NOT IN ('GenericSupplierPayment', 'SupplierPayment',
                                             'GenericInternalUsage', 'InternalUsage')
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
