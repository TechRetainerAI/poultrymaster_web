-- =============================================================================
-- 418_GenericCashFlowOnTransactions.postgres.sql
--
-- Purpose
-- -------
-- Build Cash Flow for the Generic module on business transactions, the same way
-- migration 235 did for Poultry, 236 for Water, and 316 for Hotel.
--
-- What it reads
-- -------------
--   genericcustomerpayments         money received from customers
--   genericsales                    the part paid at the counter (residuals)
--   genericexpenses                 operational spending (non-deleted, non-NonCash)
--   genericpayrollruns              staff wages (Paid only, when no linked expense)
--   genericownercontributiondraws   owner contributions and draws (Posted only)
--   "GenericLoans"                  loan principal received
--   "GenericLoanPayments"           loan repayments
--   cashadjustment                  legacy capital adjustments
--
-- What it does NOT read
-- ---------------------
--   genericcashtransactions         the cash-account ledger
--   genericcashaccounts             account balances
--   genericcashtransfers            movements between own accounts
--   genericcashreconciliations      verification records
--
-- Amount convention: SIGNED. Positive is money in, negative is money out.
--
-- DROP + CREATE. No table is created, altered or written to.
-- Order: after 417. Run before any migration that references these functions.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- Dependency order: detail and summary both call rows.
DROP FUNCTION IF EXISTS public.spgenericcashflow_detail(text, timestamp, timestamp);
DROP FUNCTION IF EXISTS public.spgenericcashflow_summary(text, timestamp, timestamp);
DROP FUNCTION IF EXISTS public.spgenericcashflow_rows(text, timestamp, timestamp);

-- -----------------------------------------------------------------------------
-- 1. The rows.
-- -----------------------------------------------------------------------------
-- amount is SIGNED: positive in, negative out.
--
-- Columns kept compatible with the poultry/water/hotel shape so
-- CashFlowService.cs can read all rails with the same reader.
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
           -COALESCE(e.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(e.description), ''), 'Expense')::text,
           'OperatingOut'::text,
           e.createdat::timestamp
    FROM   genericexpenses e
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  COALESCE(e.amount, 0) > 0
      AND  COALESCE(e.isdeleted, FALSE) = FALSE
      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'
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

-- -----------------------------------------------------------------------------
-- 2. The summary.
-- -----------------------------------------------------------------------------
-- Opening + in - out = closing, all from the same transaction set.
-- Return shape matches poultry/water/hotel so CashFlowService.cs reads all
-- rails identically.
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
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_in      numeric := 0;
    v_out     numeric := 0;
    v_n       bigint  := 0;
    v_open    numeric := 0;
BEGIN
    SELECT COALESCE(SUM(r.amount)  FILTER (WHERE r.amount > 0), 0),
           COALESCE(SUM(-r.amount) FILTER (WHERE r.amount < 0), 0),
           COUNT(*)
      INTO v_in, v_out, v_n
    FROM   public.spgenericcashflow_rows(p_farmid, p_fromdate, p_todate) r;

    -- Everything before the window opened.
    IF p_fromdate IS NOT NULL THEN
        SELECT COALESCE(SUM(r.amount), 0) INTO v_open
        FROM   public.spgenericcashflow_rows(
                   p_farmid, NULL, p_fromdate - interval '1 microsecond') r;
    END IF;

    RETURN QUERY SELECT
        ROUND(v_in, 2),
        ROUND(v_out, 2),
        ROUND(v_in - v_out, 2),
        0::numeric,                          -- ledgercash    (ledger not read)
        0::numeric,                          -- offledgernet  (concept retired)
        ROUND(v_open + v_in - v_out, 2),     -- cashathand = CLOSING cash
        ROUND(v_open, 2),
        0::numeric,                          -- transfervolume (excluded)
        0::numeric,                          -- offledgerin
        0::numeric,                          -- offledgerout
        v_n;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. The detail rows, with the category.
-- -----------------------------------------------------------------------------
-- Same pattern as hotel (316): rows plus what the money was FOR.
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
LANGUAGE sql
STABLE
AS $function$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid, r.accountname,
           r.transactiondate, r.transactiontype, r.sourcetype, r.sourceid,
           r.istransfer, r.amount, r.description, r.flowgroup,
           CASE
               WHEN r.rowsource = 'Expense'
                   THEN COALESCE(
                       NULLIF(btrim(ec.name), ''),
                       'Uncategorised'
                   )
               WHEN r.rowsource = 'Receipt'
                   THEN COALESCE(
                       'Sales revenue (' || NULLIF(btrim(gp.paymentmethod), '') || ')',
                       'Sales revenue'
                   )
               WHEN r.rowsource = 'SaleResidual'      THEN 'Sales'
               WHEN r.rowsource = 'Payroll'            THEN 'Staff wages'
               WHEN r.rowsource = 'OwnerContribution'  THEN 'Owner contribution'
               WHEN r.rowsource = 'OwnerDraw'          THEN 'Owner draw'
               WHEN r.rowsource = 'LoanReceived'       THEN 'Loan received'
               WHEN r.rowsource = 'LoanRepayment'      THEN 'Loan repayment'
               WHEN r.rowsource = 'Adjustment'
                   THEN COALESCE(NULLIF(btrim(r.sourcetype), ''), 'Adjustment')
               ELSE 'Other'
           END::text,
           r.createdat
    FROM   public.spgenericcashflow_rows(p_farmid, p_fromdate, p_todate) r
    -- Expense: join to get the category name
    LEFT   JOIN genericexpenses ge
           ON  r.rowsource = 'Expense'
           AND ge.genericexpenseid = r.sourcerowid
           AND lower(ge.farmid::text) = lower(p_farmid)
    LEFT   JOIN genericexpensecategories ec
           ON  ge.genericexpensecategoryid = ec.genericexpensecategoryid
    -- Customer payment: join to get the payment method for the category label
    LEFT   JOIN genericcustomerpayments gp
           ON  r.rowsource = 'Receipt'
           AND gp.genericcustomerpaymentid = r.sourcerowid
           AND lower(gp.farmid::text) = lower(p_farmid);
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 4. Verification.
-- -----------------------------------------------------------------------------
SELECT 'generic cash flow functions (3 expected)' AS check,
       CASE WHEN count(*) = 3 THEN 'OK' ELSE 'ONLY ' || count(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('spgenericcashflow_rows', 'spgenericcashflow_summary',
                     'spgenericcashflow_detail');
