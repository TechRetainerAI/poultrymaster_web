-- 503: Projects & Contracts -- a reversed purchase's refund follows the purchase.
--
-- 500_Enock_GenericPurchaseReversal writes the money a supplier refunds as a
-- cash-ledger row with sourcetype 'PurchaseReversal' and sourceid = the
-- purchase. fngenericproject_cashrows did not know that type, so the refund
-- fell into General while the original payment counted for the purchase's
-- projects -- the project's cash flow showed money out with no money back.
-- It now maps to the Purchase key, exactly like the payment. ExpenseReversal
-- was already mapped to Expense.
--
-- The live body (after 501_Gyimah), with only those two lines extended. Company
-- totals are unchanged: only which project a refund is shown against moves.

BEGIN;

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
             WHEN t.sourcetype IN ('Purchase', 'PurchaseReversal') THEN 'Purchases paid when bought'
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
             -- 503: Enock's purchase reversal (500_Enock) refunds what was paid;
             -- sourceid is the purchase, so the refund follows its projects.
             WHEN t.sourcetype IN ('Purchase', 'PurchaseReversal') THEN 'Purchase'
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

COMMIT;
