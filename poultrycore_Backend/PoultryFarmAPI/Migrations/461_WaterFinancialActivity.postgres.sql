-- =============================================================================
-- 461  Water: Financial Activity                (Water port of 290 / 419)
-- =============================================================================
--
-- One timeline, one row per business event, each with Money In / Money Out
-- AND Revenue / Expense / Profit Impact, plus Running Cash, and the financial
-- positions it moved. READ-ONLY: functions only, no tables, no data.
--
-- Same output as Generic's (419) so the page and API are shared in shape.
-- Unlike 419, which rebuilds the profit side from tables, Water reads both
-- sides from its own authorities, so the timeline always agrees with them:
--
--   cash legs    spwatercashflow_detail   -- exactly the rows Cash Flow sums
--   profit legs  spwaterreport_pllines + the 316 per-document detail
--                (plrevenuedetail / pldirectcostdetail / plexpensedetail /
--                pllossdetail)         -- exactly what the P&L sums
--
-- So: summary Money In/Out = Cash Flow for the period, and summary Revenue -
-- Expense = the P&L net profit for the period (checked by
-- water-461-financial-activity.test.sql on every Water company).
--
-- A document that has both legs becomes ONE event when they share a key:
-- "Expense #N" (P&L) and Cash Flow's Expense row N. A sale's revenue and the
-- payment for it stay separate events (as on Generic): they are different
-- moments. A driver return's collections and its shortage share "Return #N".
--
-- Idempotent. PostgreSQL.
-- =============================================================================

BEGIN;

DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('fnwaterfa_events', 'fnwaterfa_positions',
                            'spwaterfinancialactivity_get', 'spwaterfinancialactivity_summary')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 1. Events
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.fnwaterfa_events(p_farmid text, p_from date, p_to date)
RETURNS TABLE(eventkey text, businessdate date, occurredat timestamp, createdat timestamp, activitytype text, type text,
              category text, description text, sourcetype text, sourceid int, sourcenumber text, moneyin numeric,
              moneyout numeric, revenue numeric, expense numeric, profitimpact numeric, iscash boolean,
              isnoncash boolean, istransfer boolean, cashaccountid int, partyname text, plline text, status text)
LANGUAGE sql STABLE AS $function$
    WITH lines AS (
        SELECT l.section, l.linekey, l.linelabel
        FROM   public.spwaterreport_pllines(p_farmid, p_from, p_to) l
        WHERE  NOT l.isinformational
          -- 'Excluded' is listed because spwaterreport_periodpnl (the P&L's
          -- headline net profit) still deducts it -- e.g. a capital asset bought
          -- as an approved expense -- although pllines labels it "Excluded
          -- from profit". The timeline follows the headline figure; see the
          -- note raised 2026-11-20.
          AND  l.section IN ('Revenue', 'DirectCost', 'OperatingExpense', 'OtherCost', 'Loss', 'Excluded')
    ), pl AS (
        SELECT ln.section, ln.linekey, ln.linelabel, d.*
        FROM   lines ln
        CROSS  JOIN LATERAL (
            SELECT * FROM public.spwaterreport_plrevenuedetail(p_farmid, p_from, p_to, ln.linekey) WHERE ln.section = 'Revenue'
            UNION ALL
            SELECT * FROM public.spwaterreport_pldirectcostdetail(p_farmid, p_from, p_to, ln.linekey) WHERE ln.section = 'DirectCost'
            UNION ALL
            SELECT * FROM public.spwaterreport_pllossdetail(p_farmid, p_from, p_to, ln.linekey) WHERE ln.section = 'Loss'
            UNION ALL
            -- Expense-based lines are itemised here even when the P&L files them
            -- under Direct Costs (e.g. Production Supplies); the direct-cost
            -- detail only knows raw materials and production cost. Each function
            -- returns nothing for the other's keys.
            SELECT * FROM public.spwaterreport_plexpensedetail(p_farmid, p_from, p_to, ln.linekey)
            WHERE ln.section IN ('OperatingExpense', 'OtherCost', 'DirectCost', 'Excluded')
        ) d
    ), legs AS (
        -- ---- cash: exactly the rows Water Cash Flow sums --------------------------
        SELECT d.rowsource || ':' || d.sourcerowid AS k, d.transactiondate::date AS dt, d.createdat AS ca,
               d.rowsource AS st, d.sourcerowid AS sid, d.category AS cat, d.description AS descr,
               GREATEST(d.amount, 0) AS mi, GREATEST(-d.amount, 0) AS mo, 0::numeric AS rev, 0::numeric AS exp,
               d.cashaccountid AS acc, COALESCE(d.istransfer, FALSE) AS trf, 1 AS pri,
               NULL::text AS pl, NULL::text AS party
        FROM   public.spwatercashflow_detail(p_farmid, p_from::timestamp, (p_to + 1)::timestamp - interval '1 microsecond') d
        UNION ALL
        -- ---- profit: exactly what the P&L sums, one row per document -------------
        SELECT CASE WHEN p.reference ~ '^Expense #[0-9]+$' THEN 'Expense:' || substring(p.reference FROM '[0-9]+')
                    WHEN p.reference ~ '^Sale #[0-9]+$'    THEN 'Sale:'    || substring(p.reference FROM '[0-9]+')
                    WHEN p.reference ~ '^Return #[0-9]+$'  THEN 'Return:'  || substring(p.reference FROM '[0-9]+')
                    ELSE 'PL:' || p.linekey || ':' || COALESCE(p.reference, '') || ':' || p.entrydate::text END,
               p.entrydate::date, p.entrydate,
               CASE p.section WHEN 'Revenue' THEN
                        CASE WHEN p.reference LIKE 'Return #%' THEN 'DeliveryReturn' ELSE 'Sale' END
                    WHEN 'DirectCost' THEN 'DirectCost'
                    WHEN 'Loss' THEN 'Loss'
                    ELSE 'Expense' END,
               NULLIF(substring(COALESCE(p.reference, '') FROM '[0-9]+'), '')::int,
               p.linelabel,
               COALESCE(NULLIF(btrim(p.detail), ''), p.reference, p.linelabel),
               0, 0,
               CASE WHEN p.section = 'Revenue' THEN p.amount ELSE 0 END,
               CASE WHEN p.section = 'Revenue' THEN 0 ELSE p.amount END,
               NULL::int, FALSE, 2, p.linelabel,
               NULLIF(NULLIF(btrim(p.party), ''), 'Not recorded')
        FROM   pl p
        WHERE  COALESCE(p.amount, 0) <> 0
    ), ev AS (
        SELECT l.k,
               MIN(l.dt) AS dt, MIN(l.ca) AS ca,
               (ARRAY_AGG(l.st ORDER BY l.pri))[1] AS st, (ARRAY_AGG(l.sid ORDER BY l.pri))[1] AS sid,
               (ARRAY_AGG(l.cat ORDER BY l.pri))[1] AS cat, (ARRAY_AGG(l.descr ORDER BY l.pri))[1] AS descr,
               SUM(l.mi) AS mi, SUM(l.mo) AS mo, SUM(l.rev) AS rev, SUM(l.exp) AS exp,
               MAX(l.acc) AS acc, BOOL_OR(l.trf) AS trf,
               (ARRAY_AGG(l.pl ORDER BY l.pl IS NULL, l.pri))[1] AS pl,
               (ARRAY_AGG(l.party ORDER BY l.party IS NULL, l.pri))[1] AS party,
               BOOL_OR(l.pri = 1) AS hascash
        FROM   legs l GROUP BY l.k
    )
    SELECT e.k, e.dt, e.dt::timestamp, e.ca,
           CASE WHEN e.trf THEN 'Transfer'
                WHEN e.st = 'OwnerMoney' THEN 'Owner'
                WHEN e.st IN ('Loan', 'LoanPayment', 'Adjustment') THEN 'Financing'
                WHEN e.st IN ('EmployeeLoan', 'EmployeeLoanRepayment', 'EmployeeCredit', 'EmployeeCreditReversal') THEN 'Staff'
                ELSE 'Operating' END,
           CASE e.st
               WHEN 'Receipt'                 THEN 'Payment received'
               WHEN 'ReceiptReversal'         THEN 'Payment reversed'
               WHEN 'SaleResidual'            THEN 'Paid at the sale'
               WHEN 'CustomerRefund'          THEN 'Customer refund'
               WHEN 'CustomerRefundReversal'  THEN 'Customer refund reversed'
               WHEN 'Sale'                    THEN 'Sale'
               WHEN 'DeliveryReturn'          THEN 'Delivery collections'
               WHEN 'Expense'                 THEN 'Expense'
               WHEN 'ExpensePayment'          THEN 'Supplier payment'
               WHEN 'SupplierPurchasePayment' THEN 'Supplier payment'
               WHEN 'SupplierAdvanceOrDebt'   THEN 'Supplier payment'
               WHEN 'SupplierPaymentReversal' THEN 'Supplier payment reversed'
               WHEN 'SupplierRefund'          THEN 'Supplier refund'
               WHEN 'SupplierRefundReversal'  THEN 'Supplier refund reversed'
               WHEN 'DirectCost'              THEN 'Direct cost'
               WHEN 'Loss'                    THEN 'Loss'
               WHEN 'OwnerMoney'              THEN 'Owner money'
               WHEN 'Loan'                    THEN 'Loan received'
               WHEN 'LoanPayment'             THEN 'Loan repayment'
               WHEN 'Adjustment'              THEN 'Cash adjustment'
               WHEN 'EmployeeLoan'            THEN 'Staff advance'
               WHEN 'EmployeeLoanRepayment'   THEN 'Advance repaid'
               WHEN 'EmployeeCredit'          THEN 'Employee credit'
               WHEN 'EmployeeCreditReversal'  THEN 'Employee credit reversed'
               ELSE COALESCE(e.st, 'Other') END,
           COALESCE(e.cat, 'Other'), e.descr, e.st, e.sid,
           CASE WHEN e.sid IS NULL THEN e.st ELSE e.st || ' #' || e.sid END,
           ROUND(e.mi, 2), ROUND(e.mo, 2), ROUND(e.rev, 2), ROUND(e.exp, 2), ROUND(e.rev - e.exp, 2),
           e.hascash AND (e.mi <> 0 OR e.mo <> 0),
           NOT (e.hascash AND (e.mi <> 0 OR e.mo <> 0)) AND NOT e.trf,
           e.trf, e.acc, e.party, e.pl, 'Posted'::text
    FROM   ev e;
$function$;

-- -----------------------------------------------------------------------------
-- 2. Rows with running cash, seeded from Cash Flow's opening balance
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.spwaterfinancialactivity_get(p_farmid text, p_from date, p_to date)
RETURNS TABLE(eventkey text, businessdate date, occurredat timestamp, createdat timestamp, activitytype text, type text,
              category text, description text, sourcetype text, sourceid int, sourcenumber text, moneyin numeric,
              moneyout numeric, revenue numeric, expense numeric, profitimpact numeric, runningcash numeric,
              iscash boolean, isnoncash boolean, istransfer boolean, cashaccountid int, cashaccountname text,
              partyname text, plline text, status text)
LANGUAGE sql STABLE AS $function$
    WITH opening AS (
        SELECT COALESCE(s.openingbalance, 0) AS bal
        FROM   public.spwatercashflow_summary(p_farmid, p_from::timestamp, (p_to + 1)::timestamp - interval '1 microsecond') s
    )
    SELECT e.eventkey, e.businessdate, e.occurredat, e.createdat, e.activitytype, e.type, e.category, e.description,
           e.sourcetype, e.sourceid, e.sourcenumber, e.moneyin, e.moneyout, e.revenue, e.expense, e.profitimpact,
           ROUND((SELECT bal FROM opening)
                 + SUM(e.moneyin - e.moneyout) OVER (ORDER BY e.businessdate, e.createdat NULLS FIRST, e.eventkey
                                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2),
           e.iscash, e.isnoncash, e.istransfer, e.cashaccountid, a.accountname::text, e.partyname, e.plline, e.status
    FROM   public.fnwaterfa_events(p_farmid, p_from, p_to) e
    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = e.cashaccountid
    ORDER  BY e.businessdate, e.createdat NULLS FIRST, e.eventkey;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Summary: cash from Cash Flow, profit from the same events (= the P&L)
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.spwaterfinancialactivity_summary(p_farmid text, p_from date, p_to date)
RETURNS TABLE(moneyin numeric, moneyout numeric, netcashflow numeric, openingcash numeric, closingcash numeric,
              revenue numeric, expense numeric, netprofit numeric, eventcount int, cashevents int, noncashevents int)
LANGUAGE sql STABLE AS $function$
    WITH cf AS (
        SELECT * FROM public.spwatercashflow_summary(p_farmid, p_from::timestamp, (p_to + 1)::timestamp - interval '1 microsecond')
    ), ev AS (
        SELECT COALESCE(SUM(e.revenue), 0) AS rev, COALESCE(SUM(e.expense), 0) AS exp, COUNT(*) AS n,
               COUNT(*) FILTER (WHERE e.iscash) AS ncash, COUNT(*) FILTER (WHERE e.isnoncash) AS nnon
        FROM   public.fnwaterfa_events(p_farmid, p_from, p_to) e
    )
    SELECT ROUND(cf.moneyin, 2), ROUND(cf.moneyout, 2), ROUND(cf.netcashflow, 2), ROUND(cf.openingbalance, 2),
           ROUND(cf.cashathand, 2), ROUND(ev.rev, 2), ROUND(ev.exp, 2), ROUND(ev.rev - ev.exp, 2),
           ev.n::int, ev.ncash::int, ev.nnon::int
    FROM   cf CROSS JOIN ev;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Position changes
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.fnwaterfa_positions(p_farmid text, p_from date, p_to date)
RETURNS TABLE(eventkey text, positiontype text, positionname text, increaseamount numeric, decreaseamount numeric,
              explanation text)
LANGUAGE sql STABLE AS $function$
    WITH e AS (SELECT * FROM public.spwaterfinancialactivity_get(p_farmid, p_from, p_to))
    SELECT e.eventkey, 'Cash', COALESCE(e.cashaccountname, 'Cash'), e.moneyin, e.moneyout,
           CASE WHEN e.moneyin > 0 THEN 'Money received into this account.' ELSE 'Money paid out of this account.' END
    FROM   e WHERE e.iscash
    UNION ALL
    SELECT e.eventkey, 'CustomerReceivable', COALESCE(e.partyname, 'Customers'), e.moneyout, e.moneyin,
           CASE WHEN e.moneyin > 0 THEN 'A customer paid what they owed.'
                ELSE 'A payment was reversed, so the amount is owed again.' END
    FROM   e WHERE e.sourcetype IN ('Receipt', 'ReceiptReversal') AND (e.moneyin <> 0 OR e.moneyout <> 0)
    UNION ALL
    SELECT e.eventkey, 'CustomerReceivable', COALESCE(e.partyname, 'Customers'),
           GREATEST(e.revenue - e.moneyin, 0), 0, 'A sale on credit: the customer owes it until they pay.'
    FROM   e WHERE e.sourcetype = 'Sale' AND e.revenue > e.moneyin
    UNION ALL
    SELECT e.eventkey, 'SupplierPayable', COALESCE(e.partyname, 'Suppliers'), 0, e.moneyout,
           'A supplier was paid what the business owed.'
    FROM   e WHERE e.sourcetype IN ('ExpensePayment', 'SupplierPurchasePayment', 'SupplierAdvanceOrDebt') AND e.moneyout > 0
    UNION ALL
    SELECT e.eventkey, 'LoanLiability', 'Loans', e.moneyin, e.moneyout,
           CASE WHEN e.moneyin > 0 THEN 'Borrowed money: owed back, so it is not income.'
                ELSE 'Repaying the loan lowers the debt; interest is shown as its own expense.' END
    FROM   e WHERE e.sourcetype IN ('Loan', 'LoanPayment')
    UNION ALL
    SELECT e.eventkey, 'OwnerCapital', 'Owner', e.moneyin, e.moneyout, 'Owner money is never income or expense.'
    FROM   e WHERE e.sourcetype = 'OwnerMoney'
    UNION ALL
    SELECT e.eventkey, 'EmployeeAdvance', 'Staff advances', e.moneyout, e.moneyin,
           CASE WHEN e.moneyout > 0 THEN 'Money advanced to staff: they owe it back.'
                ELSE 'Staff repaid part of an advance.' END
    FROM   e WHERE e.sourcetype IN ('EmployeeLoan', 'EmployeeLoanRepayment')
    UNION ALL
    SELECT e.eventkey, 'EmployeeCreditLiability', 'Held for staff', e.moneyin, e.moneyout,
           CASE WHEN e.moneyin > 0 THEN 'Money kept for a member of staff: it is theirs, not income.'
                ELSE 'Kept money handed back to staff: not an expense.' END
    FROM   e WHERE e.sourcetype IN ('EmployeeCredit', 'EmployeeCreditReversal');
$function$;

COMMIT;
