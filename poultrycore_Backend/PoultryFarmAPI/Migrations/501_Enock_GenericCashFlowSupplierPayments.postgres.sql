-- =============================================================================
-- 501_Enock_GenericCashFlowSupplierPayments: two Generic Cash Flow fixes.
-- (requires 500_Enock_GenericPurchaseReversal; rebuilt from the live body)
-- =============================================================================
--
-- 1. A PURCHASE PAID LATER WAS COUNTED TWICE.
--    The purchase row (474) used genericpurchases.amountpaid, but every Supplier
--    Payment applied to the purchase later also raises amountpaid
--    (fngenericpayable_addpaid) -- and the payment is already its own
--    'SupplierPayment' row. The purchase row now counts only what was paid when
--    the purchase was entered: amountpaid less the posted allocations on it
--    (equal to the purchase's own CashOut on every dev row, 2026-11-27).
--    Supplier credit applied to a purchase is an allocation too: no new cash,
--    so it leaves the purchase row as well.
--
-- 2. MANUAL SUPPLIER CREDITS WERE COUNTED AS MONEY OUT.
--    A credit note / opening credit / manual credit is a genericsupplierpayments
--    row with no cash (449, fngenericsupplier_iscreditkind). It is left out.
--
-- Read-only change to a report function: no business data changes.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spgenericcashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text, createdat timestamp without time zone)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);
    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);
BEGIN
    -- ---- 1. customer receipts ---------------------------------------------------
    RETURN QUERY
    SELECT 'Receipt'::text, FALSE,
           p.genericcustomerpaymentid, p.genericcashaccountid, NULL::text,
           p.paymentdate::timestamp, 'CashIn'::text, 'CustomerPayment'::text,
           p.genericcustomerpaymentid, FALSE,
           COALESCE(p.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(p.notes), ''), NULLIF(btrim(p.referenceno), ''),
                    'Customer payment #' || p.genericcustomerpaymentid::text)::text,
           'OperatingIn'::text, p.createdat::timestamp
    FROM   genericcustomerpayments p
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) > 0
      -- 483: a reversed payment WAS received on its day; its reversal is its own row (1b)
      AND  p.paymentdate::timestamp >= v_from
      AND  p.paymentdate::timestamp <= v_to;

    -- ---- 2. sale residuals (part paid at counter) -------------------------------
    RETURN QUERY
    SELECT 'SaleResidual'::text, FALSE,
           s.genericsaleid, s.genericcashaccountid, NULL::text,
           s.saledate::timestamp, 'CashIn'::text, 'Sale'::text,
           s.genericsaleid, FALSE, v.residual,
           ('Sale #' || s.genericsaleid::text ||
            COALESCE(' - ' || NULLIF(btrim(c.customername), ''), ''))::text,
           'OperatingIn'::text, s.createdat::timestamp
    FROM   genericsales s
    LEFT   JOIN genericcustomers c ON c.genericcustomerid = s.genericcustomerid
    CROSS  JOIN LATERAL (
        SELECT ROUND(
                   CASE WHEN COALESCE(s.paymentstatus, '') = 'Paid'
                        THEN COALESCE(s.totalamount, 0)
                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),
                                   COALESCE(s.totalamount, 0))
                   END
                 - COALESCE((SELECT SUM(ca.amountapplied)   -- 489: payments applied through allocations
                             FROM   customerpaymentallocation ca
                             WHERE  ca.module = 'generic' AND ca.saleid = s.genericsaleid
                               AND  lower(ca.farmid::text) = lower(p_farmid) AND ca.status = 'Posted'), 0)
                 - COALESCE((SELECT SUM(pp.amount)
                             FROM   genericcustomerpayments pp
                             WHERE  pp.linkedsaleid = s.genericsaleid
                               AND  lower(pp.farmid::text) = lower(p_farmid)
                               -- 483: reversed payments stay counted (receipt kept, reversal in 1b)
                               ), 0)
               , 2) AS residual
    ) v
    WHERE  lower(s.farmid::text) = lower(p_farmid)
      AND  COALESCE(s.isdeleted, FALSE) = FALSE
      -- 483: only money a sale actually took: approved, or approved then refunded / reversed (not drafts)
      AND  (s.status IN ('Approved', 'Refunded') OR s.salereversalid IS NOT NULL)
      AND  v.residual > 0
      AND  s.saledate::timestamp >= v_from
      AND  s.saledate::timestamp <= v_to;

    -- ---- 1b. reversed customer payments: money back out on the day of the reversal (483)
    RETURN QUERY
    SELECT 'ReceiptReversal'::text, FALSE,
           p.genericcustomerpaymentid::integer, p.genericcashaccountid::integer, NULL::text,
           p.reversedat::timestamp, 'CashOut'::text, 'CustomerPaymentReversal'::text,
           p.genericcustomerpaymentid, FALSE,
           -COALESCE(p.amount, 0)::numeric,
           ('Reversal of customer payment #' || p.genericcustomerpaymentid::text
            || COALESCE(': ' || NULLIF(btrim(p.reversalreason), ''), ''))::text,
           'OperatingOut'::text, p.reversedat::timestamp
    FROM   genericcustomerpayments p
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) > 0
      AND  p.status = 'Reversed' AND p.reversedat IS NOT NULL
      AND  p.genericcashaccountid IS NOT NULL
      AND  p.reversedat::timestamp >= v_from
      AND  p.reversedat::timestamp <= v_to;

    -- ---- 1c. sale refunds paid out of a cash account (old Refund, 483 SaleReversal) --
    RETURN QUERY
    SELECT 'SaleRefund'::text, FALSE,
           t.genericcashtransactionid::integer, t.genericcashaccountid::integer, NULL::text,
           t.transactiondate::timestamp, 'CashOut'::text, t.sourcetype::text,
           t.sourceid::integer, FALSE,
           -ABS(COALESCE(t.amount, 0))::numeric,
           COALESCE(NULLIF(btrim(t.description), ''), 'Sale refund')::text,
           'OperatingOut'::text, t.transactiondate::timestamp
    FROM   genericcashtransactions t
    WHERE  lower(t.farmid::text) = lower(p_farmid)
      AND  t.transactiontype = 'CashOut'
      AND  t.sourcetype IN ('Refund', 'SaleReversal')
      AND  COALESCE(t.amount, 0) <> 0
      AND  t.transactiondate::timestamp >= v_from
      AND  t.transactiondate::timestamp <= v_to;

    -- ---- 3. expenses (operational spending) ------------------------------------
    RETURN QUERY
    SELECT 'Expense'::text, FALSE,
           e.genericexpenseid, e.genericcashaccountid, NULL::text,
           e.expensedate::timestamp, 'CashOut'::text, 'Expense'::text,
           e.genericexpenseid, FALSE,
           -COALESCE(e.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(e.description), ''), 'Expense')::text,
           'OperatingOut'::text, e.createdat::timestamp
    FROM   genericexpenses e
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  COALESCE(e.amount, 0) > 0
      AND  COALESCE(e.isdeleted, FALSE) = FALSE
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'
      AND  e.expensedate::timestamp >= v_from
      AND  e.expensedate::timestamp <= v_to;

    -- ---- 4. payroll (only paid runs WITHOUT a linked expense) ------------------
    IF to_regclass('public.genericpayrollruns') IS NOT NULL THEN
        RETURN QUERY EXECUTE format($sql$
            SELECT 'Payroll'::text, FALSE,
                   pr.genericpayrollrunid, pr.genericcashaccountid, NULL::text,
                   COALESCE(pr.paidat, pr.createdat)::timestamp, 'CashOut'::text,
                   'Payroll'::text, pr.genericpayrollrunid, FALSE,
                   -COALESCE(pr.totalnetpay, 0)::numeric,
                   COALESCE(NULLIF(btrim(pr.notes), ''),
                            'Payroll ' || to_char(pr.periodstart, 'DD Mon') || ' - ' || to_char(pr.periodend, 'DD Mon YYYY'))::text,
                   'OperatingOut'::text, pr.createdat::timestamp
            FROM   genericpayrollruns pr
            WHERE  lower(pr.farmid::text) = lower($1)
              AND  pr.status = 'Paid'
              AND  COALESCE(pr.totalnetpay, 0) > 0
              AND  COALESCE(pr.isdeleted, FALSE) = FALSE
              AND  NOT EXISTS (
                       SELECT 1 FROM genericexpenses e
                       WHERE  e.sourcetype = 'Payroll'
                         AND  e.sourceid = pr.genericpayrollrunid
                         AND  lower(e.farmid::text) = lower($1)
                         AND  COALESCE(e.isdeleted, FALSE) = FALSE
                   )
              AND  COALESCE(pr.paidat, pr.createdat)::timestamp >= $2
              AND  COALESCE(pr.paidat, pr.createdat)::timestamp <= $3
        $sql$)
        USING p_farmid, v_from, v_to;
    END IF;

    -- ---- 5. owner contributions (financing in) --------------------------------
    RETURN QUERY
    SELECT 'OwnerContribution'::text, FALSE,
           oc.genericownerentryid, oc.genericcashaccountid, NULL::text,
           oc.entrydate::timestamp, 'CashIn'::text, 'OwnerInjection'::text,
           oc.genericownerentryid, FALSE,
           COALESCE(oc.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(oc.notes), ''),
                    'Owner contribution' || COALESCE(' - ' || NULLIF(btrim(oc.ownername), ''), ''))::text,
           'FinancingIn'::text, oc.createdat::timestamp
    FROM   genericownercontributiondraws oc
    WHERE  lower(oc.farmid::text) = lower(p_farmid)
      AND  oc.entrytype = 'Contribution' AND oc.status = 'Posted'
      AND  COALESCE(oc.amount, 0) > 0
      AND  oc.entrydate::timestamp >= v_from
      AND  oc.entrydate::timestamp <= v_to;

    -- ---- 6. owner draws (financing out) ----------------------------------------
    RETURN QUERY
    SELECT 'OwnerDraw'::text, FALSE,
           oc.genericownerentryid, oc.genericcashaccountid, NULL::text,
           oc.entrydate::timestamp, 'CashOut'::text, 'Withdrawal'::text,
           oc.genericownerentryid, FALSE,
           -COALESCE(oc.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(oc.notes), ''),
                    'Owner draw' || COALESCE(' - ' || NULLIF(btrim(oc.ownername), ''), ''))::text,
           'FinancingOut'::text, oc.createdat::timestamp
    FROM   genericownercontributiondraws oc
    WHERE  lower(oc.farmid::text) = lower(p_farmid)
      AND  oc.entrytype = 'Draw' AND oc.status = 'Posted'
      AND  COALESCE(oc.amount, 0) > 0
      AND  oc.entrydate::timestamp >= v_from
      AND  oc.entrydate::timestamp <= v_to;

    -- ---- 7. loans received (financing in) --------------------------------------
    IF to_regclass('public."GenericLoans"') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'LoanReceived'::text, FALSE,
               l."GenericLoanId", l."GenericCashAccountId", NULL::text,
               COALESCE(l."LoanDate", l."CreatedAt")::timestamp, 'CashIn'::text,
               'LoanReceived'::text, l."GenericLoanId", FALSE,
               COALESCE(l."AmountReceived", 0)::numeric,
               COALESCE(NULLIF(btrim(l."Notes"), ''),
                        'Loan from ' || COALESCE(NULLIF(btrim(l."LenderName"), ''), 'unknown lender'))::text,
               'FinancingIn'::text, l."CreatedAt"::timestamp
        FROM   "GenericLoans" l
        WHERE  l."FarmId" = p_farmid
          AND  l."Status" IN ('Active', 'Paid')
          AND  COALESCE(l."AmountReceived", 0) > 0
          AND  COALESCE(l."LoanDate", l."CreatedAt")::timestamp >= v_from
          AND  COALESCE(l."LoanDate", l."CreatedAt")::timestamp <= v_to;
    END IF;

    -- ---- 8. loan repayments (financing out) ------------------------------------
    IF to_regclass('public."GenericLoanPayments"') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'LoanRepayment'::text, FALSE,
               lp."GenericLoanPaymentId", lp."GenericCashAccountId", NULL::text,
               lp."PaymentDate"::timestamp, 'CashOut'::text,
               'LoanRepayment'::text, lp."GenericLoanPaymentId", FALSE,
               -COALESCE(lp."TotalPayment", 0)::numeric,
               COALESCE(NULLIF(btrim(lp."Notes"), ''),
                        'Loan repayment #' || lp."GenericLoanPaymentId"::text)::text,
               'FinancingOut'::text, lp."CreatedAt"::timestamp
        FROM   "GenericLoanPayments" lp
        WHERE  lp."FarmId" = p_farmid
          AND  COALESCE(lp."IsReversed", FALSE) = FALSE
          AND  COALESCE(lp."TotalPayment", 0) > 0
          AND  lp."PaymentDate"::timestamp >= v_from
          AND  lp."PaymentDate"::timestamp <= v_to;
    END IF;

    -- ---- 9. legacy cash adjustments --------------------------------------------
    IF to_regclass('public.cashadjustment') IS NOT NULL OR
       to_regclass('public.cashadjustments') IS NOT NULL THEN
        RETURN QUERY EXECUTE format($sql$
            SELECT 'Adjustment'::text, FALSE,
                   ca.adjustmentid, NULL::integer, NULL::text,
                   ca.adjustmentdate,
                   CASE WHEN ca.amount >= 0 THEN 'CashIn' ELSE 'CashOut' END::text,
                   COALESCE(NULLIF(btrim(ca.adjustmenttype), ''), 'Adjustment')::text,
                   ca.adjustmentid, FALSE,
                   ca.amount::numeric,
                   COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text,
                   CASE WHEN ca.amount >= 0 THEN 'FinancingIn' ELSE 'FinancingOut' END::text,
                   NULL::timestamp
            FROM   %s ca
            WHERE  lower(ca.farmid::text) = lower($1)
              AND  ca.amount <> 0
              AND  ca.adjustmentdate >= $2
              AND  ca.adjustmentdate <= $3
        $sql$, COALESCE(to_regclass('public.cashadjustment')::text,
                        to_regclass('public.cashadjustments')::text))
        USING p_farmid, v_from, v_to;
    END IF;

    -- ========================================================================
    -- NEW (474): Purchase cash-out — the AmountPaid portion of approved
    -- purchases. This is money that left the business to pay for goods.
    -- ========================================================================
    RETURN QUERY
    SELECT 'PurchasePayment'::text, FALSE,
           pu.genericpurchaseid,
           pu.genericcashaccountid,
           NULL::text,
           pu.purchasedate::timestamp,
           'CashOut'::text,
           'Purchase'::text,
           pu.genericpurchaseid,
           FALSE,
           -pe.atentry,   -- 501: paid at entry only; later payments are their own rows
           ('Purchase ' || COALESCE(NULLIF(btrim(pu.invoicenumber), ''), '#' || pu.genericpurchaseid::text)
            || COALESCE(' - ' || NULLIF(btrim(sp.suppliername), ''), ''))::text,
           'OperatingOut'::text,
           pu.createdat::timestamp
    FROM   genericpurchases pu
    LEFT   JOIN genericsuppliers sp ON sp.genericsupplierid = pu.genericsupplierid
    CROSS  JOIN LATERAL (
        -- 501: amountpaid also holds every Supplier Payment (and credit) applied
        -- to the purchase later; those are counted on the payment's own row.
        SELECT GREATEST(COALESCE(pu.amountpaid, 0) - COALESCE((
                   SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                   WHERE  sa.module = 'generic' AND sa.documenttype = 'Purchase'
                     AND  sa.documentid = pu.genericpurchaseid AND sa.status = 'Posted'
                     AND  lower(sa.farmid::text) = lower(p_farmid)), 0), 0)::numeric AS atentry
    ) pe
    WHERE  lower(pu.farmid::text) = lower(p_farmid)
      AND  (pu.status = 'Approved' OR pu.purchasereversalid IS NOT NULL)   -- 500: reversed keeps its day
      AND  COALESCE(pu.isdeleted, FALSE) = FALSE
      AND  pe.atentry > 0
      AND  pu.purchasedate::timestamp >= v_from
      AND  pu.purchasedate::timestamp <= v_to;

    -- ========================================================================
    -- NEW (474): Supplier payments — standalone payments against outstanding
    -- supplier balances (purchases or expenses on credit).
    -- ========================================================================
    RETURN QUERY
    SELECT 'SupplierPayment'::text, FALSE,
           sp.genericsupplierpaymentid,
           sp.genericcashaccountid,
           NULL::text,
           sp.paymentdate::timestamp,
           'CashOut'::text,
           'SupplierPayment'::text,
           sp.genericsupplierpaymentid,
           FALSE,
           -COALESCE(sp.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(sp.notes), ''),
                    'Supplier payment #' || sp.genericsupplierpaymentid::text
                    || COALESCE(' - ' || NULLIF(btrim(sv.suppliername), ''), ''))::text,
           'OperatingOut'::text,
           sp.createdat::timestamp
    FROM   genericsupplierpayments sp
    LEFT   JOIN genericsuppliers sv ON sv.genericsupplierid = sp.genericsupplierid
    WHERE  lower(sp.farmid::text) = lower(p_farmid)
      AND  sp.status = 'Approved'
      AND  COALESCE(sp.sourcetype, '') <> 'PurchaseReversalCredit'   -- 500: kept as credit, no cash
      AND  NOT public.fngenericsupplier_iscreditkind(sp.sourcetype)   -- 501: credit note / opening / manual credit, no cash
      AND  COALESCE(sp.amount, 0) > 0
      AND  sp.paymentdate::timestamp >= v_from
      AND  sp.paymentdate::timestamp <= v_to;
    -- ========================================================================
    -- 500: a reversed purchase the supplier refunded -- money back in on the
    -- day of the reversal (its payment at entry stays on its own day above).
    -- ========================================================================
    RETURN QUERY
    SELECT 'PurchaseRefund'::text, FALSE,
           t.genericcashtransactionid::integer, t.genericcashaccountid::integer, NULL::text,
           t.transactiondate::timestamp, 'CashIn'::text, 'PurchaseReversal'::text,
           t.sourceid::integer, FALSE,
           ABS(COALESCE(t.amount, 0))::numeric,
           COALESCE(NULLIF(btrim(t.description), ''), 'Purchase refund')::text,
           'OperatingIn'::text, t.transactiondate::timestamp
    FROM   genericcashtransactions t
    WHERE  lower(t.farmid::text) = lower(p_farmid)
      AND  t.transactiontype = 'CashIn'
      AND  t.sourcetype = 'PurchaseReversal'
      AND  COALESCE(t.amount, 0) <> 0
      AND  t.transactiondate::timestamp >= v_from
      AND  t.transactiondate::timestamp <= v_to;
END;
$function$;
