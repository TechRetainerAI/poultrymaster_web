-- 501: Projects & Contracts -- four more record types can belong to a project,
--      plus project labels for deferred-cost lots.
--
-- New allocation source types (genericprojectallocations.sourcetype):
--   InternalUsage      -- an internal use. Its cost reaches the project P&L
--                         through the non-cash expense the usage posts
--                         (sourcetype GenericInternalUsage), exactly as a payroll
--                         expense follows its run. No new P&L line: the company
--                         P&L is unchanged.
--   EmployeeLoan       -- an employee loan / advance taken FOR a project. Cash
--                         only: employee loans have no P&L line, so they never
--                         become project expenses. A personal loan stays untagged.
--   CustomerCredit     -- a credit added by hand. It moves no money; the tag is
--                         for filtering. Credits from a payment follow the payment.
--   RecurringTemplate  -- a recurring expense template. Each expense it creates
--                         gets its own Expense tag at creation (done in the API),
--                         so nothing is counted twice.
-- Cash (fngenericproject_cashrows): employee-loan disbursements, repayments and
-- reversals follow the loan; a supplier credit refund follows the refunded
-- payment's designated advance split (new key SupplierCreditRefund).
-- Labels (spgenericproject_labels): 'DeferredLot' -- a purchase lot follows its
-- purchase lines for that product.
--
-- Each function below is the live body, extended; nothing else in it changed.

BEGIN;

ALTER TABLE genericprojectallocations DROP CONSTRAINT IF EXISTS genericprojectallocations_sourcetype_check;
ALTER TABLE genericprojectallocations ADD CONSTRAINT genericprojectallocations_sourcetype_check CHECK (sourcetype IN (
    'SaleLine', 'PurchaseLine', 'Expense', 'OwnerEntry', 'Loan', 'PayrollRun',
    'CapitalAsset', 'CustomerPayment', 'SupplierPayment',
    'InternalUsage', 'EmployeeLoan', 'CustomerCredit', 'RecurringTemplate'));

CREATE OR REPLACE FUNCTION public.fngenericproject_sourcesize(p_farmid text, p_sourcetype text, p_sourceid integer, p_lineid integer, OUT amount numeric, OUT quantity numeric, OUT label text)
 RETURNS record
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    CASE p_sourcetype
    WHEN 'SaleLine' THEN
        SELECT i.linetotal, i.quantity,
               coalesce(nullif(s.receiptnumber, ''), 'Sale #' || s.genericsaleid) || ' — ' || coalesce(i.description, 'line')
          INTO amount, quantity, label
          FROM genericsaleitems i JOIN genericsales s ON s.genericsaleid = i.genericsaleid
         WHERE i.genericsaleitemid = p_lineid AND i.genericsaleid = p_sourceid AND s.farmid = p_farmid;
    WHEN 'PurchaseLine' THEN
        SELECT i.linetotal, i.quantity,
               coalesce(nullif(p.invoicenumber, ''), 'Purchase #' || p.genericpurchaseid) || ' — '
                 || coalesce(i.description, pr.productname, 'line')
          INTO amount, quantity, label
          FROM genericpurchaseitems i JOIN genericpurchases p ON p.genericpurchaseid = i.genericpurchaseid
          LEFT JOIN genericproducts pr ON pr.genericproductid = i.genericproductid
         WHERE i.genericpurchaseitemid = p_lineid AND i.genericpurchaseid = p_sourceid AND p.farmid = p_farmid;
    WHEN 'Expense' THEN
        SELECT e.amount, NULL, 'Expense #' || e.genericexpenseid || ' — ' || coalesce(e.description, e.paidto, '')
          INTO amount, quantity, label
          FROM genericexpenses e WHERE e.genericexpenseid = p_sourceid AND e.farmid = p_farmid;
    WHEN 'OwnerEntry' THEN
        SELECT o.amount, NULL, 'Owner ' || lower(o.entrytype) || ' ' || coalesce(o.referenceno, '#' || o.genericownerentryid)
          INTO amount, quantity, label
          FROM genericownercontributiondraws o WHERE o.genericownerentryid = p_sourceid AND o.farmid = p_farmid;
    WHEN 'Loan' THEN
        SELECT l."AmountReceived", NULL, 'Loan ' || coalesce(l."LoanNumber", '#' || l."GenericLoanId") || ' — ' || coalesce(l."LenderName", '')
          INTO amount, quantity, label
          FROM "GenericLoans" l WHERE l."GenericLoanId" = p_sourceid AND l."FarmId" = p_farmid;
    WHEN 'PayrollRun' THEN
        SELECT r.totalgrosspay, NULL, 'Payroll #' || r.genericpayrollrunid || ' (' || r.periodstart || ' to ' || r.periodend || ')'
          INTO amount, quantity, label
          FROM genericpayrollruns r WHERE r.genericpayrollrunid = p_sourceid AND r.farmid = p_farmid;
    WHEN 'CapitalAsset' THEN
        SELECT COALESCE((SELECT sum(c.amount) FROM genericcapitalassetcosts c
                         WHERE c.genericcapitalassetid = a.genericcapitalassetid AND c.status = 'Posted'), 0),
               NULL, 'Asset ' || a.assetnumber || ' — ' || a.assetname
          INTO amount, quantity, label
          FROM genericcapitalassets a WHERE a.genericcapitalassetid = p_sourceid AND a.farmid = p_farmid;
    WHEN 'CustomerPayment' THEN
        SELECT p.amount, NULL, 'Customer payment #' || p.genericcustomerpaymentid
          INTO amount, quantity, label
          FROM genericcustomerpayments p WHERE p.genericcustomerpaymentid = p_sourceid AND p.farmid = p_farmid;
    WHEN 'SupplierPayment' THEN
        SELECT p.amount, NULL, 'Supplier payment #' || p.genericsupplierpaymentid
          INTO amount, quantity, label
          FROM genericsupplierpayments p WHERE p.genericsupplierpaymentid = p_sourceid AND p.farmid = p_farmid;
    -- 501: four more record types.
    WHEN 'InternalUsage' THEN
        SELECT u.totalcostvalue, NULL, 'Internal use #' || u.genericinternalusageid
          INTO amount, quantity, label
          FROM genericinternalusage u WHERE u.genericinternalusageid = p_sourceid AND u.farmid = p_farmid;
    WHEN 'EmployeeLoan' THEN
        SELECT l.principalamount, NULL, 'Employee loan #' || l.genericemployeeloanid
          INTO amount, quantity, label
          FROM genericemployeeloans l WHERE l.genericemployeeloanid = p_sourceid AND l.farmid = p_farmid;
    WHEN 'CustomerCredit' THEN
        SELECT c."Amount", NULL, 'Customer credit #' || c."GenericCustomerCreditId"
          INTO amount, quantity, label
          FROM genericcustomercredits c WHERE c."GenericCustomerCreditId" = p_sourceid AND c."FarmId" = p_farmid;
    WHEN 'RecurringTemplate' THEN
        SELECT t.amount, NULL, 'Recurring expense #' || t.templateid
          INTO amount, quantity, label
          FROM recurringexpensetemplates t WHERE t.templateid = p_sourceid AND t.farmid = p_farmid AND t.module = 'generic';
    ELSE
        RAISE EXCEPTION 'Transactions of type "%" cannot be assigned to a project.', p_sourcetype USING ERRCODE = 'P0001';
    END CASE;
END
$function$;

CREATE OR REPLACE FUNCTION public.fngenericproject_keyshares(p_farmid text)
 RETURNS TABLE(keytype text, keyid integer, productid integer, projectid integer, share numeric, costclass text)
 LANGUAGE sql
 STABLE
AS $function$
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
                                      'CustomerPayment', 'SupplierPayment',
                                      -- 501: cash only (no P&L line exists for an employee loan).
                                      'EmployeeLoan')
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
        UNION ALL
        -- 501: the non-cash expense an internal use posts follows its usage.
        SELECT 'Expense', e.genericexpenseid, iu.genericprojectid, iu.share, iu.costclass
        FROM genericexpenses e
        JOIN a iu ON iu.sourcetype = 'InternalUsage' AND iu.sourceid = e.sourceid
        WHERE e.farmid = p_farmid AND e.sourcetype = 'GenericInternalUsage'
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
    UNION ALL SELECT 'SupplierPaymentCash', keyid, NULL, projectid, share, 'Direct' FROM supplier_payment
    -- 501: a refund of supplier credit returns unapplied money, so it follows the
    -- payment's designated advance split. Its own keytype name: the balances
    -- function reads 'SupplierPaymentAdvance' from the allocations directly.
    UNION ALL SELECT 'SupplierCreditRefund', keyid, NULL, projectid, share, costclass FROM direct
              WHERE keytype = 'SupplierPayment';
$function$;

CREATE OR REPLACE FUNCTION public.fngenericproject_cashrows(p_farmid text, p_start date, p_finish date)
 RETURNS TABLE(cashtransactionid bigint, day date, sourcetype text, sourceid integer, description text, amount numeric, activity text, category text, keytype text, keyid integer)
 LANGUAGE sql
 STABLE
AS $function$
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
             -- 501: employee loans for a project, and supplier credit refunds.
             WHEN t.sourcetype IN ('EmployeeLoan', 'EmployeeLoanReversal',
                                   'EmployeeLoanRepayment', 'EmployeeLoanRepaymentReversal') THEN 'EmployeeLoan'
             WHEN t.sourcetype = 'GenericSupplierRefund' THEN 'SupplierCreditRefund'
             ELSE 'General' END,
           CASE
             WHEN t.sourcetype = 'CapitalAssetCost' THEN
                  (SELECT c.genericcapitalassetid FROM genericcapitalassetcosts c WHERE c.genericcapitalassetcostid = t.sourceid)
             WHEN t.sourcetype IN ('LoanRepayment', 'LoanRepaymentReversal') THEN
                  (SELECT lp."GenericLoanId" FROM "GenericLoanPayments" lp WHERE lp."GenericLoanPaymentId" = t.sourceid)
             WHEN t.sourcetype IN ('EmployeeLoanRepayment', 'EmployeeLoanRepaymentReversal') THEN
                  (SELECT r.genericemployeeloanid FROM genericemployeeloanrepayments r
                   WHERE r.genericemployeeloanrepaymentid = t.sourceid)
             WHEN t.sourcetype = 'GenericSupplierRefund' THEN
                  (SELECT min(rl.genericsupplierpaymentid) FROM genericsupplierrefundlines rl WHERE rl.refundid = t.sourceid)
             ELSE t.sourceid END
    FROM genericcashtransactions t
    WHERE t.farmid = p_farmid
      AND t.transactiondate >= p_start AND t.transactiondate < p_finish + 1
      AND COALESCE(t.sourcetype, '') <> 'Transfer'
      AND COALESCE(t.transactiontype, '') NOT IN ('TransferIn', 'TransferOut')
      AND COALESCE(t.status, 'Approved') NOT IN ('Pending', 'Rejected', 'Draft', 'Cancelled', 'Void')
      -- 496: loan money comes from the loan tables below, as on the company
      -- Cash Flow (spgenericcashflow_rows 7 / 8). A cash-ledger row typed as a
      -- loan is not a loan record and the company Cash Flow does not count it.
      AND COALESCE(t.sourcetype, '') NOT IN ('LoanReceived', 'LoanRepayment', 'LoanRepaymentReversal', 'LoanCancelled')
    UNION ALL
    -- 496: loans received (Active / Paid), on the loan date. Not in the cash
    -- ledger, so they get their own negative row ids.
    SELECT -(l."GenericLoanId")::bigint, COALESCE(l."LoanDate", l."CreatedAt")::date, 'LoanReceived', l."GenericLoanId",
           COALESCE(NULLIF(btrim(l."Notes"), ''), 'Loan from ' || COALESCE(NULLIF(btrim(l."LenderName"), ''), 'unknown lender')),
           COALESCE(l."AmountReceived", 0)::numeric(14,2), 'Financing', 'Loans received', 'Loan', l."GenericLoanId"
    FROM "GenericLoans" l
    WHERE l."FarmId" = p_farmid AND l."Status" IN ('Active', 'Paid') AND COALESCE(l."AmountReceived", 0) > 0
      AND COALESCE(l."LoanDate", l."CreatedAt") >= p_start AND COALESCE(l."LoanDate", l."CreatedAt") < p_finish + 1
    UNION ALL
    -- 496: loan repayments (principal + interest + fees + other), not reversed.
    SELECT -(1000000000 + lp."GenericLoanPaymentId")::bigint, lp."PaymentDate"::date, 'LoanRepayment', lp."GenericLoanPaymentId",
           COALESCE(NULLIF(btrim(lp."Notes"), ''), 'Loan repayment #' || lp."GenericLoanPaymentId"),
           -COALESCE(lp."TotalPayment", 0)::numeric(14,2), 'Financing', 'Loan repayments', 'Loan', lp."GenericLoanId"
    FROM "GenericLoanPayments" lp
    WHERE lp."FarmId" = p_farmid AND NOT COALESCE(lp."IsReversed", FALSE) AND COALESCE(lp."TotalPayment", 0) > 0
      AND lp."PaymentDate" >= p_start AND lp."PaymentDate" < p_finish + 1;
$function$;

CREATE OR REPLACE FUNCTION public.spgenericproject_labels(p_farmid text, p_sourcetype text, p_ids integer[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    WITH a AS (
        -- Stored tags (unchanged from 483) for every type except payments.
        SELECT a.sourceid, a.genericprojectid
        FROM genericprojectallocations a
        WHERE p_sourcetype NOT IN ('CustomerPayment', 'SupplierPayment', 'DeferredLot')
          AND a.farmid = p_farmid AND a.status = 'Active'
          AND a.sourcetype = CASE p_sourcetype WHEN 'Sale' THEN 'SaleLine' WHEN 'Purchase' THEN 'PurchaseLine' ELSE p_sourcetype END
          AND (p_ids IS NULL OR a.sourceid = ANY (p_ids))
        UNION ALL
        -- Payments: what they paid follows the documents, the rest the advance.
        SELECT k.keyid, k.projectid
        FROM fngenericproject_keyshares(p_farmid) k
        WHERE p_sourcetype IN ('CustomerPayment', 'SupplierPayment')
          AND k.keytype = p_sourcetype || 'Cash'
          AND k.share > 0
          AND (p_ids IS NULL OR k.keyid = ANY (p_ids))
        UNION ALL
        -- 501: a deferred-cost lot is a stock-in movement; a purchase lot belongs
        -- to the projects of its purchase's lines for that product. Other lots
        -- (opening stock, adjustments, production) are General.
        SELECT m.genericstockmovementid, a.genericprojectid
        FROM genericstockmovements m
        JOIN genericpurchaseitems i ON i.genericpurchaseid = m.referenceid AND i.genericproductid = m.genericproductid
        JOIN genericprojectallocations a ON a.farmid = p_farmid AND a.status = 'Active' AND a.sourcetype = 'PurchaseLine'
             AND a.sourceid = i.genericpurchaseid AND a.sourcelineid = i.genericpurchaseitemid
        WHERE p_sourcetype = 'DeferredLot' AND m.farmid = p_farmid AND m.referencetype = 'Purchase'
          AND (p_ids IS NULL OR m.genericstockmovementid = ANY (p_ids))
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object('sourceId', x.sourceid, 'projects', x.projects)), '[]'::jsonb)
    FROM (SELECT a.sourceid,
                 jsonb_agg(DISTINCT jsonb_build_object('projectId', a.genericprojectid,
                                                       'label', p.projectnumber || ' — ' || p.name)) AS projects
          FROM a JOIN genericprojects p ON p.genericprojectid = a.genericprojectid
          GROUP BY a.sourceid) x;
$function$;

-- 501: the split a recurring template passes to each expense it creates, as the
-- {splits:[...]} the save hook takes. NULL when the template has none or the
-- company has switched Projects & Contracts off -- the expense is then simply
-- General, and posting never fails because of the module.
CREATE OR REPLACE FUNCTION public.spgenericproject_templatesplits(p_farmid text, p_templateid integer)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT CASE WHEN NOT fngenericproject_enabled(p_farmid) OR count(*) = 0 THEN NULL
                ELSE jsonb_build_object('splits', jsonb_agg(jsonb_build_object(
                         'projectId', a.genericprojectid, 'share', a.share, 'costClass', a.costclass)
                         ORDER BY a.genericprojectid)) END
    FROM genericprojectallocations a
    JOIN genericprojects p ON p.genericprojectid = a.genericprojectid AND p.status <> 'Archived'
    WHERE a.farmid = p_farmid AND a.status = 'Active' AND a.sourcetype = 'RecurringTemplate' AND a.sourceid = p_templateid;
$f$;

-- 501: for Cash & Accounts and Reconciliation -- which projects each cash-ledger
-- entry of one account (or every account) belongs to, and with what share. The
-- same rows and shares as the project cash flow (fngenericproject_cash), so a
-- filtered ledger agrees with the project's Cash Flow tab. Read only; account
-- balances are never split.
CREATE OR REPLACE FUNCTION public.spgenericproject_cashshares(
    p_farmid text, p_accountid integer, p_from date, p_to date)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(jsonb_agg(jsonb_build_object('cashTransactionId', x.id, 'projects', x.projects)), '[]'::jsonb)
    FROM (
        SELECT c.cashtransactionid AS id,
               jsonb_agg(jsonb_build_object('projectId', c.projectid, 'share', round(c.share, 6),
                                            'label', p.projectnumber || ' — ' || p.name)
                         ORDER BY c.projectid) AS projects
        FROM fngenericproject_cash(p_farmid, COALESCE(p_from, DATE '2000-01-01'), COALESCE(p_to, DATE '2100-01-01')) c
        JOIN genericcashtransactions t ON t.genericcashtransactionid = c.cashtransactionid AND t.farmid = p_farmid
        JOIN genericprojects p ON p.genericprojectid = c.projectid
        WHERE c.projectid IS NOT NULL AND c.share > 0
          AND (p_accountid IS NULL OR t.genericcashaccountid = p_accountid)
        GROUP BY c.cashtransactionid
    ) x;
$f$;

COMMIT;
