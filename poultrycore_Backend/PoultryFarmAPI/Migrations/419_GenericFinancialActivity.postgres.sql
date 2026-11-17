-- =============================================================================
-- 419_GenericFinancialActivity.postgres.sql
--
-- Financial Activity for Generic companies, following 336 (Hotel).
-- One timeline, one row per business event, each carrying Money In / Money Out
-- AND Revenue / Expense / Profit Impact, plus Running Cash, and what financial
-- positions it moved. READ-ONLY: functions only, no tables, no data.
--
-- Built from spgenericcashflow_detail (418) for the cash leg and the same
-- tables the Generic P&L reads for the profit legs.
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

-- -----------------------------------------------------------------------------
-- 1. Events — union of all business transactions with their cash and P&L legs
-- -----------------------------------------------------------------------------
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
               COALESCE(sp.suppliername, NULL), e.status
        FROM   genericexpenses e
        LEFT   JOIN genericexpensecategories ec ON ec.genericexpensecategoryid = e.genericexpensecategoryid
        LEFT   JOIN genericsuppliers sp ON sp.genericsupplierid = e.genericsupplierid
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
               ELSE COALESCE(e.st, 'Other') END,
           COALESCE(e.cat, 'Other'), e.descr, e.st, e.sid, e.st || ' #' || COALESCE(e.sid::text, ''),
           ROUND(e.mi, 2), ROUND(e.mo, 2), ROUND(e.rev, 2), ROUND(e.exp, 2), ROUND(e.rev - e.exp, 2),
           e.hascash AND (e.mi <> 0 OR e.mo <> 0),
           NOT (e.hascash AND (e.mi <> 0 OR e.mo <> 0)) AND NOT e.trf,
           e.trf, e.acc, e.party, e.pl, e.stat
    FROM   ev e;
$function$;

-- -----------------------------------------------------------------------------
-- 2. Rows with running cash, seeded from Cash Flow's opening balance
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- 3. Summary
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- 4. Position changes
-- -----------------------------------------------------------------------------
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
    -- transfers: both account legs
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
    -- supplier payable
    SELECT e.eventkey, 'SupplierPayable', COALESCE(e.partyname, 'Supplier'), e.expense, 0,
           'An approved expense owed to the supplier.'
    FROM   e JOIN genericexpenses x ON e.sourcetype = 'Expense' AND x.genericexpenseid = e.sourceid
    WHERE  x.genericsupplierid IS NOT NULL AND COALESCE(x.amountpaid, 0) < x.amount
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

-- Verification
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM pg_proc WHERE proname IN ('fngenericfa_events', 'fngenericfa_positions',
            'spgenericfinancialactivity_get', 'spgenericfinancialactivity_summary')) <> 4 THEN
        RAISE EXCEPTION '419 verification failed: functions missing';
    END IF;
END $$;
