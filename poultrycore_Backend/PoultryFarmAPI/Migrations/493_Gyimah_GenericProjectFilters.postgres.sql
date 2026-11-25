-- 493: Projects & Contracts -- the Project / Contract filter on the rest of
-- Sales, Expenses & Money (Customer Payments, Supplier Payments, Customer
-- Balances, Supplier Balances, Financial Activity, Payroll, Loans, Assets).
--
-- Read-only. Every share comes from fngenericproject_keyshares (484), the same
-- engine the project P&L and cash flow use, so a page filtered to a project
-- agrees with that project's own figures. Nothing here writes.
--
-- 1. spgenericproject_labels -- CustomerPayment and SupplierPayment now return
--    the projects a payment really belongs to: the sales / purchases / expenses
--    it paid, plus any designated advance. Before, only the designated advance
--    counted, so a payment applied to a project's sale showed no project.
--    Every other source type returns exactly what it did before.
-- 2. spgenericproject_activityshares -- Financial Activity: for each event in
--    the period that belongs (partly) to a project, its projects and shares.
--    Events not listed are entirely General company activity.
-- 3. spgenericproject_openbalances -- Customer / Supplier Balances: every open
--    document (the same rows the balances pages list) with its party and its
--    project shares. The page multiplies each balance by the share, so the
--    projects + General always add back to the company figure.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Labels
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericproject_labels(
    p_farmid text, p_sourcetype text, p_ids integer[])
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH a AS (
        -- Stored tags (unchanged from 483) for every type except payments.
        SELECT a.sourceid, a.genericprojectid
        FROM genericprojectallocations a
        WHERE p_sourcetype NOT IN ('CustomerPayment', 'SupplierPayment')
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
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object('sourceId', x.sourceid, 'projects', x.projects)), '[]'::jsonb)
    FROM (SELECT a.sourceid,
                 jsonb_agg(DISTINCT jsonb_build_object('projectId', a.genericprojectid,
                                                       'label', p.projectnumber || ' — ' || p.name)) AS projects
          FROM a JOIN genericprojects p ON p.genericprojectid = a.genericprojectid
          GROUP BY a.sourceid) x;
$f$;

-- ---------------------------------------------------------------------------
-- 2. Financial Activity
-- ---------------------------------------------------------------------------
-- Which record each Financial Activity event comes from (fngenericfa_events /
-- spgenericcashflow_rows), as an engine key:
--   SaleRevenue, SaleResidual  sale id                       -> Sale
--   SaleRefund                 cash transaction id -> its sale -> Sale
--   Receipt, ReceiptReversal   customer payment id           -> CustomerPaymentCash
--   Expense                    expense id                    -> Expense
--   PurchasePayment            purchase id                   -> Purchase
--   SupplierPayment            supplier payment id           -> SupplierPaymentCash
--   Payroll                    payroll run id                -> PayrollRun
--   OwnerContribution/Draw     owner entry id                -> OwnerEntry
--   LoanReceived               loan id                       -> Loan
--   LoanRepayment              loan payment id -> its loan   -> Loan
--   Adjustment, CashTransfer   company-wide                  -> General
CREATE OR REPLACE FUNCTION public.spgenericproject_activityshares(
    p_farmid text, p_from date, p_to date)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH ev AS (
        SELECT e.eventkey,
               CASE
                 WHEN e.sourcetype IN ('SaleRevenue', 'SaleResidual', 'SaleRefund') THEN 'Sale'
                 WHEN e.sourcetype IN ('Receipt', 'ReceiptReversal') THEN 'CustomerPaymentCash'
                 WHEN e.sourcetype = 'Expense' THEN 'Expense'
                 WHEN e.sourcetype = 'PurchasePayment' THEN 'Purchase'
                 WHEN e.sourcetype = 'SupplierPayment' THEN 'SupplierPaymentCash'
                 WHEN e.sourcetype = 'Payroll' THEN 'PayrollRun'
                 WHEN e.sourcetype IN ('OwnerContribution', 'OwnerDraw') THEN 'OwnerEntry'
                 WHEN e.sourcetype IN ('LoanReceived', 'LoanRepayment') THEN 'Loan'
               END AS keytype,
               CASE
                 WHEN e.sourcetype = 'SaleRefund' THEN
                      (SELECT t.sourceid FROM genericcashtransactions t
                       WHERE t.genericcashtransactionid = e.sourceid AND t.farmid = p_farmid)
                 WHEN e.sourcetype = 'LoanRepayment' THEN
                      (SELECT lp."GenericLoanId" FROM "GenericLoanPayments" lp
                       WHERE lp."GenericLoanPaymentId" = e.sourceid AND lp."FarmId" = p_farmid)
                 ELSE e.sourceid
               END AS keyid
        FROM fngenericfa_events(p_farmid, p_from, p_to) e
    ), ks AS (
        SELECT keytype, keyid, projectid, sum(share) AS share
        FROM fngenericproject_keyshares(p_farmid)
        WHERE productid IS NULL AND share > 0
        GROUP BY 1, 2, 3
    ), x AS (
        SELECT ev.eventkey,
               jsonb_agg(jsonb_build_object('projectId', ks.projectid, 'share', round(ks.share, 6))
                         ORDER BY ks.projectid) AS projects
        FROM ev JOIN ks ON ks.keytype = ev.keytype AND ks.keyid = ev.keyid
        GROUP BY ev.eventkey
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object('eventKey', x.eventkey, 'projects', x.projects)), '[]'::jsonb)
    FROM x;
$f$;

-- ---------------------------------------------------------------------------
-- 3. Customer / Supplier Balances
-- ---------------------------------------------------------------------------
-- p_side 'customer': the rows spgenericcustomeropeninvoices lists (any customer).
-- p_side 'supplier': the rows spgenericsupplieropenbills lists (any supplier),
-- due date worked out the same way (the bill's own, else date + payment terms).
-- Subscription invoices are sales to the engine. Documents it cannot attribute
-- (customer debts from 488, supplier debts)
-- come back with no projects: they are General.
CREATE OR REPLACE FUNCTION public.spgenericproject_openbalances(p_farmid text, p_side text)
 RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH docs AS (
        SELECT d.genericcustomerid AS partyid, d.documenttype, d.documentid, d.documentdate AS docdate,
               d.amountpaid, d.balance, d.duedate
        FROM fngenericopeninvoices(p_farmid) d
        WHERE p_side = 'customer' AND d.balance > 0
        UNION ALL
        SELECT d.supplierid, d.documenttype, d.documentid, d.docdate, d.amountpaid, d.balance,
               COALESCE(d.duedate, d.docdate + COALESCE(s.paymenttermsdays, 0))
        FROM fngenericpayables(p_farmid) d
        JOIN genericsuppliers s ON s.genericsupplierid = d.supplierid AND s.farmid = p_farmid
        WHERE p_side = 'supplier' AND d.balance > 0
    ), ks AS (
        SELECT keytype, keyid, projectid, sum(share) AS share
        FROM fngenericproject_keyshares(p_farmid)
        WHERE productid IS NULL AND share > 0 AND keytype IN ('Sale', 'Purchase', 'Expense')
        GROUP BY 1, 2, 3
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'partyId', d.partyid, 'documentType', d.documenttype, 'documentId', d.documentid,
               'documentDate', d.docdate, 'amountPaid', d.amountpaid, 'balance', d.balance,
               'dueDate', d.duedate, 'isOverdue', COALESCE(d.duedate < CURRENT_DATE, false),
               'projects', COALESCE((
                   SELECT jsonb_agg(jsonb_build_object('projectId', ks.projectid, 'share', round(ks.share, 6))
                                    ORDER BY ks.projectid)
                   FROM ks WHERE ks.keytype = CASE d.documenttype WHEN 'Invoice' THEN 'Sale' ELSE d.documenttype END
                     AND ks.keyid = d.documentid), '[]'::jsonb))
             ORDER BY d.partyid, d.docdate, d.documentid), '[]'::jsonb)
    FROM docs d;
$f$;

COMMIT;
