-- =============================================================================
-- 474_GenericPurchaseReporting.postgres.sql
--
-- Fix: Generic purchase payments and supplier payments were invisible to Cash
-- Flow, Financial Activity, and the Supplier Payments page.
--
-- Root cause
-- ----------
-- spgenericcashflow_rows (418) reads business source tables but had no UNION
-- for genericpurchases.amountpaid or genericsupplierpayments. The purchase
-- approval correctly posts CashOut to genericcashtransactions, but the cash
-- flow function deliberately reads source tables (not the ledger), so the
-- rows were silently missing.
--
-- What this fixes
-- ---------------
-- 1. spgenericcashflow_rows      — adds purchase cash-out + supplier payment
-- 2. spgenericcashflow_detail    — adds category for the two new row sources
-- 3. fngenericfa_events          — inherits cash fix; no P&L change because
--                                   purchase is a balance-sheet event (inventory
--                                   up, cash down) — cost hits P&L when sold
-- 4. spgenericsupplierpayment_combined — NEW: unions GenericSupplierPayments
--                                   WITH the initial purchase payment, so the
--                                   Supplier Payments page shows both
--
-- P&L treatment
-- -------------
-- A tracked-inventory purchase is NOT an expense. It increases stock value
-- (deferred cost). The cost reaches P&L as COGS when the goods are sold
-- (GenericStockMovements.SaleOut × CostPrice). This matches standard
-- accounting and prevents double-charging.
--
-- A supplier payment for the remaining balance is a CASH event only — it
-- moves cash to the supplier and closes the payable. It is not P&L.
--
-- Double-charge prevention
-- ------------------------
-- The purchase approval creates exactly one CashOut for AmountPaid and one
-- SupplierLedger PurchaseCredit for Balance. A later supplier payment creates
-- its OWN CashOut and PaymentDebit. These are separate events on separate
-- dates with separate amounts. The cash flow function unions them from
-- different source tables and they never overlap.
--
-- Idempotent: DROP + CREATE throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- =============================================================================
-- 1. Rewrite spgenericcashflow_rows — add purchase payments + supplier payments
-- =============================================================================

DROP FUNCTION IF EXISTS public.spgenericcashflow_detail(text, timestamp, timestamp);
DROP FUNCTION IF EXISTS public.spgenericcashflow_summary(text, timestamp, timestamp);
DROP FUNCTION IF EXISTS public.spgenericcashflow_rows(text, timestamp, timestamp);

CREATE OR REPLACE FUNCTION public.spgenericcashflow_rows(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    rowsource       text,
    offledger       boolean,
    sourcerowid     integer,
    cashaccountid   integer,
    accountname     text,
    transactiondate timestamp,
    transactiontype text,
    sourcetype      text,
    sourceid        integer,
    istransfer      boolean,
    amount          numeric,
    description     text,
    flowgroup       text,
    createdat       timestamp)
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
      AND  COALESCE(p.status, 'Posted') <> 'Reversed'
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
           -COALESCE(pu.amountpaid, 0)::numeric,
           ('Purchase ' || COALESCE(NULLIF(btrim(pu.invoicenumber), ''), '#' || pu.genericpurchaseid::text)
            || COALESCE(' - ' || NULLIF(btrim(sp.suppliername), ''), ''))::text,
           'OperatingOut'::text,
           pu.createdat::timestamp
    FROM   genericpurchases pu
    LEFT   JOIN genericsuppliers sp ON sp.genericsupplierid = pu.genericsupplierid
    WHERE  lower(pu.farmid::text) = lower(p_farmid)
      AND  pu.status = 'Approved'
      AND  COALESCE(pu.isdeleted, FALSE) = FALSE
      AND  COALESCE(pu.amountpaid, 0) > 0
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
      AND  COALESCE(sp.amount, 0) > 0
      AND  sp.paymentdate::timestamp >= v_from
      AND  sp.paymentdate::timestamp <= v_to;
END;
$function$;

-- =============================================================================
-- 2. Rewrite spgenericcashflow_summary (unchanged logic, just re-create
--    because we dropped it above)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spgenericcashflow_summary(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    moneyin            numeric,
    moneyout           numeric,
    netcashflow        numeric,
    ledgercash         numeric,
    offledgernet       numeric,
    cashathand         numeric,
    openingbalance     numeric,
    transfervolume     numeric,
    offledgerin        numeric,
    offledgerout       numeric,
    rowcount           bigint)
LANGUAGE plpgsql STABLE
AS $function$
DECLARE
    v_in   numeric := 0;
    v_out  numeric := 0;
    v_n    bigint  := 0;
    v_open numeric := 0;
BEGIN
    SELECT COALESCE(SUM(r.amount)  FILTER (WHERE r.amount > 0), 0),
           COALESCE(SUM(-r.amount) FILTER (WHERE r.amount < 0), 0),
           COUNT(*)
      INTO v_in, v_out, v_n
    FROM   public.spgenericcashflow_rows(p_farmid, p_fromdate, p_todate) r;

    IF p_fromdate IS NOT NULL THEN
        SELECT COALESCE(SUM(r.amount), 0) INTO v_open
        FROM   public.spgenericcashflow_rows(
                   p_farmid, NULL, p_fromdate - interval '1 microsecond') r;
    END IF;

    RETURN QUERY SELECT
        ROUND(v_in, 2), ROUND(v_out, 2), ROUND(v_in - v_out, 2),
        0::numeric, 0::numeric, ROUND(v_open + v_in - v_out, 2),
        ROUND(v_open, 2), 0::numeric, 0::numeric, 0::numeric, v_n;
END;
$function$;

-- =============================================================================
-- 3. Rewrite spgenericcashflow_detail — add category for new row sources
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spgenericcashflow_detail(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    rowsource       text,
    offledger       boolean,
    sourcerowid     integer,
    cashaccountid   integer,
    accountname     text,
    transactiondate timestamp,
    transactiontype text,
    sourcetype      text,
    sourceid        integer,
    istransfer      boolean,
    amount          numeric,
    description     text,
    flowgroup       text,
    category        text,
    createdat       timestamp)
LANGUAGE sql STABLE
AS $function$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid, r.accountname,
           r.transactiondate, r.transactiontype, r.sourcetype, r.sourceid,
           r.istransfer, r.amount, r.description, r.flowgroup,
           CASE
               WHEN r.rowsource = 'Expense'
                   THEN COALESCE(NULLIF(btrim(ec.name), ''), 'Uncategorised')
               WHEN r.rowsource = 'Receipt'
                   THEN COALESCE('Sales revenue (' || NULLIF(btrim(gp.paymentmethod), '') || ')', 'Sales revenue')
               WHEN r.rowsource = 'SaleResidual'       THEN 'Sales'
               WHEN r.rowsource = 'Payroll'             THEN 'Staff wages'
               WHEN r.rowsource = 'OwnerContribution'   THEN 'Owner contribution'
               WHEN r.rowsource = 'OwnerDraw'           THEN 'Owner draw'
               WHEN r.rowsource = 'LoanReceived'        THEN 'Loan received'
               WHEN r.rowsource = 'LoanRepayment'       THEN 'Loan repayment'
               WHEN r.rowsource = 'PurchasePayment'     THEN 'Purchases'
               WHEN r.rowsource = 'SupplierPayment'     THEN 'Supplier payments'
               WHEN r.rowsource = 'Adjustment'
                   THEN COALESCE(NULLIF(btrim(r.sourcetype), ''), 'Adjustment')
               ELSE 'Other'
           END::text,
           r.createdat
    FROM   public.spgenericcashflow_rows(p_farmid, p_fromdate, p_todate) r
    LEFT   JOIN genericexpenses ge
           ON  r.rowsource = 'Expense'
           AND ge.genericexpenseid = r.sourcerowid
           AND lower(ge.farmid::text) = lower(p_farmid)
    LEFT   JOIN genericexpensecategories ec
           ON  ge.genericexpensecategoryid = ec.genericexpensecategoryid
    LEFT   JOIN genericcustomerpayments gp
           ON  r.rowsource = 'Receipt'
           AND gp.genericcustomerpaymentid = r.sourcerowid
           AND lower(gp.farmid::text) = lower(p_farmid);
$function$;

-- =============================================================================
-- 4. Rewrite fngenericfa_events — add type/activitytype for new sources
-- =============================================================================

DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('fngenericfa_events', 'fngenericfa_positions',
                            'spgenericfinancialactivity_get', 'spgenericfinancialactivity_summary')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

CREATE FUNCTION public.fngenericfa_events(p_farmid text, p_from date, p_to date)
RETURNS TABLE(eventkey text, businessdate date, occurredat timestamp, createdat timestamp, activitytype text, type text,
              category text, description text, sourcetype text, sourceid int, sourcenumber text, moneyin numeric,
              moneyout numeric, revenue numeric, expense numeric, profitimpact numeric, iscash boolean,
              isnoncash boolean, istransfer boolean, cashaccountid int, partyname text, plline text, status text)
LANGUAGE sql STABLE AS $function$
    WITH legs AS (
        -- ---- cash: exactly the rows Generic Cash Flow sums ----------------------
        SELECT d.rowsource || ':' || d.sourcerowid AS k, d.transactiondate::date AS dt, d.createdat AS ca,
               d.rowsource AS st, d.sourcerowid AS sid, d.category AS cat, d.description AS descr,
               GREATEST(d.amount, 0) AS mi, GREATEST(-d.amount, 0) AS mo, 0::numeric AS rev, 0::numeric AS exp,
               d.cashaccountid AS acc, FALSE AS trf, 1 AS pri, NULL::text AS pl, NULL::text AS party, 'Posted'::text AS stat
        FROM   public.spgenericcashflow_detail(p_farmid, p_from::timestamp, (p_to + 1)::timestamp - interval '1 microsecond') d
        UNION ALL
        -- ---- revenue: customer payments = cash-basis revenue --------------------
        SELECT 'Receipt:' || p.genericcustomerpaymentid, p.paymentdate::date, p.createdat::timestamp,
               'Receipt', p.genericcustomerpaymentid, 'Sales revenue',
               COALESCE(NULLIF(btrim(p.notes), ''), 'Customer payment #' || p.genericcustomerpaymentid),
               0, 0, p.amount, 0, NULL::int, FALSE, 2, 'Sales Revenue', NULL, COALESCE(p.status, 'Posted')
        FROM   genericcustomerpayments p
        WHERE  lower(p.farmid::text) = lower(p_farmid) AND COALESCE(p.amount, 0) > 0
          AND  COALESCE(p.status, 'Posted') <> 'Reversed'
          AND  p.paymentdate::date BETWEEN p_from AND p_to
        UNION ALL
        -- sale residuals as revenue
        SELECT 'SaleResidual:' || s.genericsaleid, s.saledate::date, s.createdat::timestamp,
               'SaleResidual', s.genericsaleid, 'Sales',
               'Sale #' || s.genericsaleid || COALESCE(' - ' || NULLIF(btrim(c.customername), ''), ''),
               0, 0,
               ROUND(CASE WHEN COALESCE(s.paymentstatus, '') = 'Paid' THEN COALESCE(s.totalamount, 0)
                     ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0), COALESCE(s.totalamount, 0)) END
                 - COALESCE((SELECT SUM(pp.amount) FROM genericcustomerpayments pp
                             WHERE pp.linkedsaleid = s.genericsaleid AND lower(pp.farmid::text) = lower(p_farmid)
                               AND COALESCE(pp.status, 'Posted') <> 'Reversed'), 0), 2),
               0, NULL, FALSE, 2, 'Sales Revenue', c.customername, s.status
        FROM   genericsales s
        LEFT   JOIN genericcustomers c ON c.genericcustomerid = s.genericcustomerid
        WHERE  lower(s.farmid::text) = lower(p_farmid) AND COALESCE(s.isdeleted, FALSE) = FALSE
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
          AND  e.expensedate::date BETWEEN p_from AND p_to
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
                WHEN e.st = 'PurchasePayment' THEN 'Operating'
                WHEN e.st = 'SupplierPayment' THEN 'Operating'
                ELSE 'Operating' END,
           CASE e.st
               WHEN 'Receipt' THEN 'Payment received'
               WHEN 'SaleResidual' THEN 'Sale'
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

-- Recreate dependent functions (unchanged logic, just re-create after drop)
CREATE FUNCTION public.spgenericfinancialactivity_get(p_farmid text, p_from date, p_to date)
RETURNS TABLE(eventkey text, businessdate date, occurredat timestamp, createdat timestamp, activitytype text, type text,
              category text, description text, sourcetype text, sourceid int, sourcenumber text, moneyin numeric,
              moneyout numeric, revenue numeric, expense numeric, profitimpact numeric, runningcash numeric,
              iscash boolean, isnoncash boolean, istransfer boolean, cashaccountid int, cashaccountname text,
              partyname text, plline text, status text)
LANGUAGE sql STABLE AS $function$
    WITH opening AS (
        SELECT COALESCE(s.openingbalance, 0) AS bal
        FROM   public.spgenericcashflow_summary(p_farmid, p_from::timestamp, (p_to + 1)::timestamp - interval '1 microsecond') s
    )
    SELECT e.eventkey, e.businessdate, e.occurredat, e.createdat, e.activitytype, e.type, e.category, e.description,
           e.sourcetype, e.sourceid, e.sourcenumber, e.moneyin, e.moneyout, e.revenue, e.expense, e.profitimpact,
           ROUND((SELECT bal FROM opening)
                 + SUM(e.moneyin - e.moneyout) OVER (ORDER BY e.businessdate, e.createdat NULLS FIRST, e.eventkey
                                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2),
           e.iscash, e.isnoncash, e.istransfer, e.cashaccountid, a.accountname::text, e.partyname, e.plline, e.status
    FROM   public.fngenericfa_events(p_farmid, p_from, p_to) e
    LEFT   JOIN genericcashaccounts a ON a.genericcashaccountid = e.cashaccountid
    ORDER  BY e.businessdate, e.createdat NULLS FIRST, e.eventkey;
$function$;

CREATE FUNCTION public.spgenericfinancialactivity_summary(p_farmid text, p_from date, p_to date)
RETURNS TABLE(moneyin numeric, moneyout numeric, netcashflow numeric, openingcash numeric, closingcash numeric,
              revenue numeric, expense numeric, netprofit numeric, eventcount int, cashevents int, noncashevents int)
LANGUAGE sql STABLE AS $function$
    WITH cf AS (
        SELECT * FROM public.spgenericcashflow_summary(p_farmid, p_from::timestamp, (p_to + 1)::timestamp - interval '1 microsecond')
    ), ev AS (
        SELECT COALESCE(SUM(e.revenue), 0) AS rev, COALESCE(SUM(e.expense), 0) AS exp, COUNT(*) AS n,
               COUNT(*) FILTER (WHERE e.iscash) AS ncash, COUNT(*) FILTER (WHERE e.isnoncash) AS nnon
        FROM   public.fngenericfa_events(p_farmid, p_from, p_to) e
    )
    SELECT ROUND(cf.moneyin, 2), ROUND(cf.moneyout, 2), ROUND(cf.netcashflow, 2), ROUND(cf.openingbalance, 2),
           ROUND(cf.cashathand, 2), ROUND(ev.rev, 2), ROUND(ev.exp, 2), ROUND(ev.rev - ev.exp, 2),
           ev.n::int, ev.ncash::int, ev.nnon::int
    FROM   cf CROSS JOIN ev;
$function$;

CREATE FUNCTION public.fngenericfa_positions(p_farmid text, p_from date, p_to date)
RETURNS TABLE(eventkey text, positiontype text, positionname text, increaseamount numeric, decreaseamount numeric,
              explanation text)
LANGUAGE sql STABLE AS $function$
    WITH e AS (SELECT * FROM public.spgenericfinancialactivity_get(p_farmid, p_from, p_to))
    -- cash
    SELECT e.eventkey, 'Cash', COALESCE(e.cashaccountname, 'Cash'), e.moneyin, e.moneyout,
           CASE WHEN e.moneyin > 0 THEN 'Money received into this account.' ELSE 'Money paid out of this account.' END
    FROM   e WHERE e.iscash
    UNION ALL
    -- transfers
    SELECT e.eventkey, 'Cash', a.accountname::text,
           CASE WHEN a.genericcashaccountid = t.togenericcashaccountid THEN t.amount ELSE 0 END,
           CASE WHEN a.genericcashaccountid = t.fromgenericcashaccountid THEN t.amount ELSE 0 END,
           'Moved between the business''s own accounts; no money entered or left.'
    FROM   e JOIN genericcashtransfers t ON e.sourcetype = 'CashTransfer' AND t.genericcashtransferid = e.sourceid
    JOIN   genericcashaccounts a ON a.genericcashaccountid IN (t.fromgenericcashaccountid, t.togenericcashaccountid)
    UNION ALL
    -- customer receivable
    SELECT e.eventkey, 'CustomerReceivable', COALESCE(e.partyname, 'Customers'), e.moneyout, e.moneyin,
           CASE WHEN e.moneyin > 0 THEN 'A customer paid what they owed.'
                ELSE 'A payment was reversed, so the amount is owed again.' END
    FROM   e WHERE e.sourcetype IN ('Receipt', 'SaleResidual') AND (e.moneyin <> 0 OR e.moneyout <> 0)
    UNION ALL
    -- supplier payable from expenses
    SELECT e.eventkey, 'SupplierPayable', COALESCE(e.partyname, 'Supplier'), e.expense, 0,
           'An approved expense owed to the supplier.'
    FROM   e JOIN genericexpenses x ON e.sourcetype = 'Expense' AND x.genericexpenseid = e.sourceid
    WHERE  x.genericsupplierid IS NOT NULL AND COALESCE(x.amountpaid, 0) < x.amount
    UNION ALL
    -- supplier payable from purchases (474)
    SELECT e.eventkey, 'SupplierPayable', COALESCE(e.partyname, 'Supplier'), 0, e.moneyout,
           'Purchase payment reduced what is owed to the supplier.'
    FROM   e WHERE e.sourcetype = 'Purchase' AND e.moneyout > 0
    UNION ALL
    -- supplier payable from supplier payments (474)
    SELECT e.eventkey, 'SupplierPayable', COALESCE(e.partyname, 'Supplier'), 0, e.moneyout,
           'Supplier payment reduced what is owed.'
    FROM   e WHERE e.sourcetype = 'SupplierPayment' AND e.moneyout > 0
    UNION ALL
    -- financing: loans
    SELECT e.eventkey, 'LoanLiability', 'Loans', e.moneyin, e.moneyout,
           'Borrowed money: owed back, so it is not income.'
    FROM   e WHERE e.sourcetype = 'LoanReceived'
    UNION ALL
    SELECT e.eventkey, 'LoanLiability', 'Loans', 0, GREATEST(e.moneyout - e.expense, 0),
           'The principal repaid lowers the debt; interest and fees are the cost.'
    FROM   e WHERE e.sourcetype = 'LoanRepayment'
    UNION ALL
    -- owner capital
    SELECT e.eventkey, 'OwnerCapital', 'Owner', e.moneyin, e.moneyout, 'Owner money is never income or expense.'
    FROM   e WHERE e.sourcetype IN ('OwnerContribution', 'OwnerDraw');
$function$;

-- =============================================================================
-- 5. Combined supplier payments reader — unions standalone supplier payments
--    WITH the initial purchase payment, for the Supplier Payments page.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spgenericsupplierpayment_combined(p_farmid text, p_status text DEFAULT NULL)
RETURNS TABLE(
    paymentid       integer,
    source          text,       -- 'SupplierPayment' or 'PurchasePayment'
    farmid          text,
    genericsupplierid integer,
    suppliername    text,
    paymentdate     timestamp,
    amount          numeric,
    paymentmethod   text,
    genericcashaccountid integer,
    linkedpurchaseid integer,
    linkedexpenseid  integer,
    invoicenumber   text,
    status          text,
    notes           text,
    createdby       text,
    approvedby      text,
    approvedat      timestamp,
    createdat       timestamp)
LANGUAGE sql STABLE
AS $function$
    -- Standalone supplier payments
    SELECT sp.genericsupplierpaymentid, 'SupplierPayment'::text,
           sp.farmid::text, sp.genericsupplierid, sv.suppliername::text,
           sp.paymentdate, sp.amount, sp.paymentmethod::text,
           sp.genericcashaccountid, sp.linkedpurchaseid, sp.linkedexpenseid,
           NULL::text,
           sp.status::text, sp.notes::text, sp.createdby::text,
           sp.approvedby::text, sp.approvedat, sp.createdat
    FROM   genericsupplierpayments sp
    INNER  JOIN genericsuppliers sv ON sv.genericsupplierid = sp.genericsupplierid
    WHERE  sp.farmid = p_farmid
      AND  (p_status IS NULL OR sp.status = p_status)
    UNION ALL
    -- Initial purchase payments (AmountPaid at approval)
    SELECT pu.genericpurchaseid, 'PurchasePayment'::text,
           pu.farmid::text, pu.genericsupplierid, sv.suppliername::text,
           pu.purchasedate, pu.amountpaid, pu.paymentmethod::text,
           pu.genericcashaccountid, pu.genericpurchaseid, NULL::integer,
           pu.invoicenumber::text,
           pu.status::text, pu.notes::text, pu.createdby::text,
           pu.approvedby::text, pu.approvedat, pu.createdat
    FROM   genericpurchases pu
    LEFT   JOIN genericsuppliers sv ON sv.genericsupplierid = pu.genericsupplierid
    WHERE  pu.farmid = p_farmid
      AND  pu.status = 'Approved'
      AND  COALESCE(pu.isdeleted, FALSE) = FALSE
      AND  COALESCE(pu.amountpaid, 0) > 0
      AND  (p_status IS NULL OR pu.status = p_status)
    ORDER  BY 6 DESC, 1 DESC;  -- paymentdate DESC, paymentid DESC
$function$;

COMMIT;

-- Verification
SELECT 'cash flow functions' AS check,
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'MISSING ' || (3 - count(*)) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('spgenericcashflow_rows', 'spgenericcashflow_summary', 'spgenericcashflow_detail');

SELECT 'financial activity functions' AS check,
       CASE WHEN count(*) = 4 THEN 'OK' ELSE 'MISSING ' || (4 - count(*)) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('fngenericfa_events', 'fngenericfa_positions',
                     'spgenericfinancialactivity_get', 'spgenericfinancialactivity_summary');

SELECT 'combined supplier payments' AS check,
       CASE WHEN count(*) = 1 THEN 'OK' ELSE 'MISSING' END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname = 'spgenericsupplierpayment_combined';
