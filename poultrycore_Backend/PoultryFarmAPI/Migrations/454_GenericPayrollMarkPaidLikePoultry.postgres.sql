-- =============================================================================
-- 454_GenericPayrollMarkPaidLikePoultry.postgres.sql   (Report 40, Part 5)
--
-- As on Poultry: a run with no cash account, or with nothing left to hand over
-- (all of it kept as employee credit), can still be marked Paid -- it simply
-- moves no cash. Cash Flow's payroll arm then counts a paid run only when it
-- really took money out (it has a 'Payroll' cash row). Reopening already
-- returns only the cash a run actually moved (451). Idempotent.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spgenericpayrollrun_markpaid(p_genericpayrollrunid integer, p_farmid text, p_paidby text DEFAULT NULL::text, p_paydate date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_cashaccountid integer;
    v_netpay numeric;
    v_notes text;
    v_allowneg boolean;
    v_bal numeric;
    v_newbalance numeric;
BEGIN
    SELECT r.status, r.genericcashaccountid, r.totalnetpay, r.notes
    INTO   v_status, v_cashaccountid, v_netpay, v_notes
    FROM   genericpayrollruns r
    WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid
       AND r.isdeleted = FALSE
    LIMIT 1;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found.';
    END IF;
    IF v_status <> 'Approved' THEN
        RAISE EXCEPTION 'Payroll must be Approved before it can be marked Paid (current=%).', v_status;
    END IF;
    -- 454 (as on Poultry): no cash account, or nothing left to hand over
    -- (all kept as employee credit), marks the run paid with no cash movement.
    IF v_cashaccountid IS NULL OR COALESCE(v_netpay, 0) <= 0 THEN
        UPDATE genericpayrollruns r
        SET    status = 'Paid', paidby = p_paidby, paidat = (now() at time zone 'utc'),
               paydate = COALESCE(p_paydate, r.paydate), updatedat = (now() at time zone 'utc')
        WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid;
        RETURN;
    END IF;

    SELECT ca.allownegativebalance, ca.currentbalance
    INTO   v_allowneg, v_bal
    FROM   genericcashaccounts ca
    WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid
    LIMIT 1;

    IF v_bal IS NULL THEN
        RAISE EXCEPTION 'GenericCashAccountId not found on this farm.';
    END IF;

    v_newbalance := v_bal - v_netpay;
    IF (v_allowneg = FALSE AND v_newbalance < 0) THEN
        RAISE EXCEPTION 'Cash account would go negative; payroll pay rejected.';
    END IF;

    UPDATE genericpayrollruns r
    SET    status    = 'Paid',
           paidby    = p_paidby,
           paidat    = (now() at time zone 'utc'),
           paydate   = COALESCE(p_paydate, r.paydate),
           updatedat = (now() at time zone 'utc')
    WHERE  r.genericpayrollrunid = p_genericpayrollrunid AND r.farmid = p_farmid;

    INSERT INTO genericcashtransactions (
        farmid, genericcashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, balanceaftertransaction, description,
        createdby, approvedby, approvedat
    )
    VALUES (
        p_farmid, v_cashaccountid, (now() at time zone 'utc'), 'CashOut',
        'Payroll', p_genericpayrollrunid, -v_netpay, v_newbalance,
        COALESCE('Payroll: ' || left(COALESCE(v_notes, ''), 200), 'Payroll'),
        p_paidby, p_paidby, (now() at time zone 'utc')
    );

    UPDATE genericcashaccounts ca
    SET    currentbalance = v_newbalance, updatedat = (now() at time zone 'utc')
    WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid;

    -- Trailing T-SQL SELECT discarded: C# call site uses ExecuteNonQuery.
END
$function$;

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
    -- Money received from customers against sales/invoices.
    RETURN QUERY
    SELECT 'Receipt'::text,
           FALSE,
           p.genericcustomerpaymentid,
           p.genericcashaccountid,
           NULL::text,
           p.paymentdate::timestamp,
           'CashIn'::text,
           'CustomerPayment'::text,
           p.genericcustomerpaymentid,
           FALSE,
           COALESCE(p.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(p.notes), ''),
               NULLIF(btrim(p.referenceno), ''),
               'Customer payment #' || p.genericcustomerpaymentid::text
           )::text,
           'OperatingIn'::text,
           p.createdat::timestamp
    FROM   genericcustomerpayments p
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) > 0
      AND  COALESCE(p.status, 'Posted') <> 'Reversed'
      AND  p.paymentdate::timestamp >= v_from
      AND  p.paymentdate::timestamp <= v_to;

    -- ---- 2. sale residuals (part paid at counter) -------------------------------
    -- A sale entered as already paid or partially paid. The residual is the
    -- amount paid that did NOT create a genericcustomerpayments row.
    RETURN QUERY
    SELECT 'SaleResidual'::text,
           FALSE,
           s.genericsaleid,
           s.genericcashaccountid,
           NULL::text,
           s.saledate::timestamp,
           'CashIn'::text,
           'Sale'::text,
           s.genericsaleid,
           FALSE,
           v.residual,
           ('Sale #' || s.genericsaleid::text ||
            COALESCE(' - ' || NULLIF(btrim(c.customername), ''), ''))::text,
           'OperatingIn'::text,
           s.createdat::timestamp
    FROM   genericsales s
    LEFT   JOIN genericcustomers c ON c.genericcustomerid = s.genericcustomerid
    CROSS  JOIN LATERAL (
        SELECT ROUND(
                   CASE WHEN COALESCE(s.paymentstatus, '') = 'Paid'
                        THEN COALESCE(s.totalamount, 0)
                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),
                                   COALESCE(s.totalamount, 0))
                   END
                 - COALESCE((SELECT SUM(pp.amount)
                             FROM   genericcustomerpayments pp
                             WHERE  pp.linkedsaleid = s.genericsaleid
                               AND  lower(pp.farmid::text) = lower(p_farmid)
                               AND  COALESCE(pp.status, 'Posted') <> 'Reversed'), 0)
               , 2) AS residual
    ) v
    WHERE  lower(s.farmid::text) = lower(p_farmid)
      AND  COALESCE(s.isdeleted, FALSE) = FALSE
      AND  v.residual > 0
      AND  s.saledate::timestamp >= v_from
      AND  s.saledate::timestamp <= v_to;

    -- ---- 3. expenses (all operational spending) ---------------------------------
    -- Every kind of spending: supplier payments, staff payments, recurring,
    -- purchases, etc. all INSERT INTO genericexpenses. NonCash (internal use)
    -- is excluded — that records stock leaving without money moving.
    RETURN QUERY
    SELECT 'Expense'::text,
           FALSE,
           e.genericexpenseid,
           e.genericcashaccountid,
           NULL::text,
           e.expensedate::timestamp,
           'CashOut'::text,
           'Expense'::text,
           e.genericexpenseid,
           FALSE,
           -- 449: the part paid from supplier credit left with the advance
           -(COALESCE(e.amount, 0)
             - COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                         WHERE sa.module = 'generic' AND sa.documenttype = 'Expense'
                           AND sa.documentid = e.genericexpenseid AND sa.status = 'Posted'
                           AND sa.fromcredit), 0))::numeric,
           COALESCE(NULLIF(btrim(e.description), ''), 'Expense')::text,
           'OperatingOut'::text,
           e.createdat::timestamp
    FROM   genericexpenses e
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  COALESCE(e.amount, 0) > 0
      AND  COALESCE(e.isdeleted, FALSE) = FALSE
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'
      AND  COALESCE(e.status, 'Approved') = 'Approved'   -- 448
      AND  e.expensedate::timestamp >= v_from
      AND  e.expensedate::timestamp <= v_to;

    -- ---- 4. payroll (only paid runs WITHOUT a linked expense) --------------------
    -- If payroll creates a linked expense, the expense leg already counts it.
    -- Only add standalone paid payroll runs that have no genericexpenseid.
    IF to_regclass('public.genericpayrollruns') IS NOT NULL THEN
        RETURN QUERY EXECUTE format($sql$
            SELECT 'Payroll'::text,
                   FALSE,
                   pr.genericpayrollrunid,
                   pr.genericcashaccountid,
                   NULL::text,
                   COALESCE(pr.paidat, pr.createdat)::timestamp,
                   'CashOut'::text,
                   'Payroll'::text,
                   pr.genericpayrollrunid,
                   FALSE,
                   -COALESCE(pr.totalnetpay, 0)::numeric,
                   COALESCE(
                       NULLIF(btrim(pr.notes), ''),
                       'Payroll ' || to_char(pr.periodstart, 'DD Mon') || ' - ' || to_char(pr.periodend, 'DD Mon YYYY')
                   )::text,
                   'OperatingOut'::text,
                   pr.createdat::timestamp
            FROM   genericpayrollruns pr
            WHERE  lower(pr.farmid::text) = lower($1)
              AND  pr.status = 'Paid'
              AND  COALESCE(pr.totalnetpay, 0) > 0
              -- 454: a run paid with no cash account moved no money
              AND  EXISTS (SELECT 1 FROM genericcashtransactions ct
                           WHERE ct.farmid = pr.farmid AND ct.sourcetype = 'Payroll'
                             AND ct.sourceid = pr.genericpayrollrunid)
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

    -- ---- 5. owner contributions (financing in) ----------------------------------
    RETURN QUERY
    SELECT 'OwnerContribution'::text,
           FALSE,
           oc.genericownerentryid,
           oc.genericcashaccountid,
           NULL::text,
           oc.entrydate::timestamp,
           'CashIn'::text,
           'OwnerInjection'::text,
           oc.genericownerentryid,
           FALSE,
           COALESCE(oc.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(oc.notes), ''),
               'Owner contribution' || COALESCE(' - ' || NULLIF(btrim(oc.ownername), ''), '')
           )::text,
           'FinancingIn'::text,
           oc.createdat::timestamp
    FROM   genericownercontributiondraws oc
    WHERE  lower(oc.farmid::text) = lower(p_farmid)
      AND  oc.entrytype = 'Contribution'
      AND  oc.status = 'Posted'
      AND  COALESCE(oc.amount, 0) > 0
      AND  oc.entrydate::timestamp >= v_from
      AND  oc.entrydate::timestamp <= v_to;

    -- ---- 6. owner draws (financing out) -----------------------------------------
    RETURN QUERY
    SELECT 'OwnerDraw'::text,
           FALSE,
           oc.genericownerentryid,
           oc.genericcashaccountid,
           NULL::text,
           oc.entrydate::timestamp,
           'CashOut'::text,
           'Withdrawal'::text,
           oc.genericownerentryid,
           FALSE,
           -COALESCE(oc.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(oc.notes), ''),
               'Owner draw' || COALESCE(' - ' || NULLIF(btrim(oc.ownername), ''), '')
           )::text,
           'FinancingOut'::text,
           oc.createdat::timestamp
    FROM   genericownercontributiondraws oc
    WHERE  lower(oc.farmid::text) = lower(p_farmid)
      AND  oc.entrytype = 'Draw'
      AND  oc.status = 'Posted'
      AND  COALESCE(oc.amount, 0) > 0
      AND  oc.entrydate::timestamp >= v_from
      AND  oc.entrydate::timestamp <= v_to;

    -- ---- 7. loans received (financing in) ---------------------------------------
    IF to_regclass('public."GenericLoans"') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'LoanReceived'::text,
               FALSE,
               l."GenericLoanId",
               l."GenericCashAccountId",
               NULL::text,
               COALESCE(l."LoanDate", l."CreatedAt")::timestamp,
               'CashIn'::text,
               'LoanReceived'::text,
               l."GenericLoanId",
               FALSE,
               COALESCE(l."AmountReceived", 0)::numeric,
               COALESCE(
                   NULLIF(btrim(l."Notes"), ''),
                   'Loan from ' || COALESCE(NULLIF(btrim(l."LenderName"), ''), 'unknown lender')
               )::text,
               'FinancingIn'::text,
               l."CreatedAt"::timestamp
        FROM   "GenericLoans" l
        WHERE  l."FarmId" = p_farmid
          AND  l."Status" IN ('Active', 'Paid')
          AND  COALESCE(l."AmountReceived", 0) > 0
          AND  COALESCE(l."LoanDate", l."CreatedAt")::timestamp >= v_from
          AND  COALESCE(l."LoanDate", l."CreatedAt")::timestamp <= v_to;
    END IF;

    -- ---- 8. loan repayments (financing out) -------------------------------------
    IF to_regclass('public."GenericLoanPayments"') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'LoanRepayment'::text,
               FALSE,
               lp."GenericLoanPaymentId",
               lp."GenericCashAccountId",
               NULL::text,
               lp."PaymentDate"::timestamp,
               'CashOut'::text,
               'LoanRepayment'::text,
               lp."GenericLoanPaymentId",
               FALSE,
               -COALESCE(lp."TotalPayment", 0)::numeric,
               COALESCE(
                   NULLIF(btrim(lp."Notes"), ''),
                   'Loan repayment #' || lp."GenericLoanPaymentId"::text
               )::text,
               'FinancingOut'::text,
               lp."CreatedAt"::timestamp
        FROM   "GenericLoanPayments" lp
        WHERE  lp."FarmId" = p_farmid
          AND  COALESCE(lp."IsReversed", FALSE) = FALSE
          AND  COALESCE(lp."TotalPayment", 0) > 0
          AND  lp."PaymentDate"::timestamp >= v_from
          AND  lp."PaymentDate"::timestamp <= v_to;
    END IF;

    -- ---- 449a. supplier advances (the part of a payment not applied) -----------
    RETURN QUERY
    SELECT 'SupplierAdvance'::text,
           FALSE,
           sp.genericsupplierpaymentid,
           sp.genericcashaccountid,
           NULL::text,
           sp.paymentdate::timestamp,
           'CashOut'::text,
           'SupplierPayment'::text,
           sp.genericsupplierpaymentid,
           FALSE,
           -(sp.amount - COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                                   WHERE sa.farmid = sp.farmid AND sa.module = 'generic'
                                     AND sa.paymentid = sp.genericsupplierpaymentid
                                     AND sa.status = 'Posted' AND NOT sa.fromcredit), 0))::numeric,
           ('Supplier advance SP-' || lpad(sp.genericsupplierpaymentid::text, 5, '0'))::text,
           'OperatingOut'::text,
           sp.createdat::timestamp
    FROM   genericsupplierpayments sp
    WHERE  lower(sp.farmid::text) = lower(p_farmid)
      AND  public.fngenericsupplierpayment_isposted(sp.status, sp.sourcetype)
      AND  NOT public.fngenericsupplier_iscreditkind(sp.sourcetype)
      AND  sp.genericcashaccountid IS NOT NULL
      AND  sp.paymentdate::timestamp >= v_from
      AND  sp.paymentdate::timestamp <= v_to
      AND  sp.amount - COALESCE((SELECT SUM(sa.amountapplied) FROM supplierpaymentallocation sa
                                 WHERE sa.farmid = sp.farmid AND sa.module = 'generic'
                                   AND sa.paymentid = sp.genericsupplierpaymentid
                                   AND sa.status = 'Posted' AND NOT sa.fromcredit), 0) > 0;

    -- ---- 449b. supplier refunds (money back from a supplier) -------------------
    RETURN QUERY
    SELECT 'SupplierRefund'::text,
           FALSE,
           r.refundid,
           r.genericcashaccountid,
           NULL::text,
           r.refunddate::timestamp,
           'CashIn'::text,
           'GenericSupplierRefund'::text,
           r.refundid,
           FALSE,
           r.amount::numeric,
           ('Supplier refund ' || r.refundnumber)::text,
           'OperatingIn'::text,
           r.createdat::timestamp
    FROM   genericsupplierrefunds r
    WHERE  lower(r.farmid::text) = lower(p_farmid)
      AND  r.status = 'Posted'
      AND  r.refunddate::timestamp >= v_from
      AND  r.refunddate::timestamp <= v_to;

    -- ---- 450. employee credit: money handed in (in), paid out (out), and the
    -- reversal of either on the day it was reversed ---------------------------
    RETURN QUERY
    SELECT 'EmployeeCredit'::text, FALSE, c.genericemployeecreditid, c.genericcashaccountid, NULL::text,
           CASE WHEN c.entrydate = c.createdat::date THEN c.createdat ELSE c.entrydate::timestamp END,
           CASE WHEN c.entrytype = 'Deposit' THEN 'CashIn' ELSE 'CashOut' END::text,
           CASE WHEN c.entrytype = 'Deposit' THEN 'EmployeeCreditDeposit' ELSE 'EmployeeCreditPayout' END::text,
           c.genericemployeecreditid, FALSE,
           (CASE WHEN c.entrytype = 'Deposit' THEN c.amount ELSE -c.amount END)::numeric,
           (CASE WHEN c.entrytype = 'Deposit' THEN 'Employee credit: money from ' ELSE 'Employee credit paid to ' END
             || btrim(s.firstname || ' ' || s.lastname))::text,
           CASE WHEN c.entrytype = 'Deposit' THEN 'OperatingIn' ELSE 'OperatingOut' END::text,
           c.createdat
    FROM   genericemployeecredits c JOIN genericstaff s ON s.genericstaffid = c.genericstaffid
    WHERE  lower(c.farmid::text) = lower(p_farmid) AND c.entrytype IN ('Deposit', 'Payout')
      AND  CASE WHEN c.entrydate = c.createdat::date THEN c.createdat ELSE c.entrydate::timestamp END BETWEEN v_from AND v_to;

    RETURN QUERY
    SELECT 'EmployeeCreditReversal'::text, FALSE, c.genericemployeecreditid, c.genericcashaccountid, NULL::text,
           c.reversedat,
           CASE WHEN c.entrytype = 'Deposit' THEN 'CashOut' ELSE 'CashIn' END::text,
           'EmployeeCreditReversal'::text, c.genericemployeecreditid, FALSE,
           (CASE WHEN c.entrytype = 'Deposit' THEN -c.amount ELSE c.amount END)::numeric,
           ('Reversal: employee credit ' || lower(c.entrytype) || ' for ' || btrim(s.firstname || ' ' || s.lastname))::text,
           CASE WHEN c.entrytype = 'Deposit' THEN 'OperatingOut' ELSE 'OperatingIn' END::text,
           c.reversedat
    FROM   genericemployeecredits c JOIN genericstaff s ON s.genericstaffid = c.genericstaffid
    WHERE  lower(c.farmid::text) = lower(p_farmid) AND c.entrytype IN ('Deposit', 'Payout')
      AND  c.status = 'Reversed' AND c.reversedat IS NOT NULL AND c.reversedat BETWEEN v_from AND v_to;

    -- ---- 453a. capital assets: cash paid at purchase, refunds on a correction or
    -- reversal, and disposal proceeds -- read from the cash ledger itself, so each
    -- movement counts once and only when money really moved.
    RETURN QUERY
    SELECT 'CapitalAsset'::text, FALSE, t.genericcashtransactionid::integer, t.genericcashaccountid, NULL::text,
           t.transactiondate, CASE WHEN t.amount >= 0 THEN 'CashIn' ELSE 'CashOut' END::text,
           t.sourcetype::text, t.sourceid, FALSE, t.amount::numeric,
           COALESCE(NULLIF(btrim(t.description), ''), 'Capital asset')::text,
           CASE WHEN t.amount >= 0 THEN 'OperatingIn' ELSE 'OperatingOut' END::text,
           t.createdat
    FROM   genericcashtransactions t
    WHERE  lower(t.farmid::text) = lower(p_farmid)
      AND  t.sourcetype IN ('CapitalAsset', 'CapitalAssetCost', 'AssetDisposal')
      AND  COALESCE(t.status, 'Approved') <> 'Reversed'
      AND  t.amount <> 0
      AND  t.transactiondate >= v_from
      AND  t.transactiondate <= v_to;

    -- ---- 453b. supplier payments applied to capital asset bills. The advance
    -- arm (449a) leaves every applied amount to its document; an asset bill is
    -- not an expense row, so its applied cash is counted here.
    RETURN QUERY
    SELECT 'CapitalAssetPayment'::text, FALSE, sa.allocationid, sp.genericcashaccountid, NULL::text,
           sp.paymentdate::timestamp, 'CashOut'::text, 'SupplierPayment'::text, sp.genericsupplierpaymentid, FALSE,
           -sa.amountapplied::numeric,
           ('Supplier payment SP-' || lpad(sp.genericsupplierpaymentid::text, 5, '0') || ' - capital asset')::text,
           'OperatingOut'::text,
           sa.createdat::timestamp
    FROM   supplierpaymentallocation sa
    JOIN   genericsupplierpayments sp ON sp.genericsupplierpaymentid = sa.paymentid AND sp.farmid = sa.farmid
    WHERE  sa.module = 'generic' AND lower(sa.farmid) = lower(p_farmid)
      AND  sa.documenttype = 'CapitalAsset' AND sa.status = 'Posted' AND NOT sa.fromcredit
      AND  public.fngenericsupplierpayment_isposted(sp.status, sp.sourcetype)
      AND  NOT public.fngenericsupplier_iscreditkind(sp.sourcetype)
      AND  sp.genericcashaccountid IS NOT NULL
      AND  sp.paymentdate::timestamp >= v_from
      AND  sp.paymentdate::timestamp <= v_to;

    -- ---- 9. legacy cash adjustments (shared table) ------------------------------
    -- The cashadjustment table is used by all rails for capital events before
    -- dedicated owner-money and loan tables existed. Include any that belong
    -- to this farm.
    IF to_regclass('public.cashadjustment') IS NOT NULL OR
       to_regclass('public.cashadjustments') IS NOT NULL THEN

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
END;
$function$;
