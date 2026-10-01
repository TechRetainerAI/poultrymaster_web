-- =============================================================================
-- 336_HotelFinancialActivity.postgres.sql
--
-- Financial Activity for the Hotel, copied from Poultry (290, 308, 315) through
-- the Restaurant's 335: one timeline, one row per business event, each carrying
-- Money In / Money Out AND Revenue / Expense / Profit Impact, plus Running Cash,
-- and the financial positions it moved. READ-ONLY: functions only, no table, no
-- data. HOTEL ONLY.
--
-- Built from the SAME sources the other two Hotel pages read, so the totals agree
-- by construction (selftest336 asserts it):
--   * the cash leg is sphotelcashflow_detail (as of 334) -- the rows Hotel Cash
--     Flow sums (transfers are not in it);
--   * the profit legs repeat sphotelreport_pllines' own selections (as of 334):
--     room revenue = posted guest payments (the Hotel P&L is cash-basis for room
--     revenue, see 332), paid restaurant orders, interest on staff loans; staff
--     wages at gross, approved expenses, supplies expensed when purchased,
--     supplies used (deferred cost drawn), depreciation, loan interest and fees.
--     Revenue is the Revenue section; Expense is every other line, so
--     Revenue - Expense = the P&L's net profit.
-- Legs of one event share a key (rowsource:rowid) and become one row -- an
-- expense paid at approval: its cash and its cost; a guest payment: its cash and
-- its revenue. Cash transfers are internal rows with no money in or out.
--
-- Activity types: Operating, Financing (loans), Owner, Capital (assets and
-- depreciation), Inventory (supplies bought and used), Transfer, EmployeeLoan.
-- =============================================================================

DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('fnhotelfa_events', 'fnhotelfa_positions',
                            'sphotelfinancialactivity_get', 'sphotelfinancialactivity_summary')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 1. Events
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.fnhotelfa_events(p_farmid text, p_from date, p_to date)
RETURNS TABLE(eventkey text, businessdate date, occurredat timestamp, createdat timestamp, activitytype text, type text,
              category text, description text, sourcetype text, sourceid int, sourcenumber text, moneyin numeric,
              moneyout numeric, revenue numeric, expense numeric, profitimpact numeric, iscash boolean,
              isnoncash boolean, istransfer boolean, cashaccountid int, partyname text, plline text, status text)
LANGUAGE sql STABLE AS $function$
    WITH legs AS (
        -- ---- cash: exactly the rows Hotel Cash Flow sums ---------------------------
        SELECT d.rowsource || ':' || d.sourcerowid AS k, d.transactiondate::date AS dt, d.createdat AS ca,
               d.rowsource AS st, d.sourcerowid AS sid, d.category AS cat, d.description AS descr,
               GREATEST(d.amount, 0) AS mi, GREATEST(-d.amount, 0) AS mo, 0::numeric AS rev, 0::numeric AS exp,
               d.cashaccountid AS acc, FALSE AS trf, 1 AS pri, NULL::text AS pl, NULL::text AS party, 'Posted'::text AS stat
        FROM   public.sphotelcashflow_detail(p_farmid, p_from::timestamp, (p_to + 1)::timestamp - interval '1 microsecond') d
        UNION ALL
        -- ---- revenue (the P&L's selections) ------------------------------------------
        SELECT 'GuestPayment:' || hp.hotelpaymentid, hp.paymentdate::date, hp.createdat::timestamp, 'GuestPayment', hp.hotelpaymentid,
               'Room revenue', COALESCE(NULLIF(btrim(hp.reference), ''), 'Guest payment #' || hp.hotelpaymentid),
               0, 0, hp.amount, 0, NULL::int, FALSE, 2, 'Room Revenue', NULL, hp.status
        FROM   public.hotelpayments hp
        WHERE  lower(hp.farmid) = lower(p_farmid) AND hp.status = 'Posted' AND COALESCE(hp.amount, 0) > 0
          AND  hp.paymentdate::date BETWEEN p_from AND p_to
        UNION ALL
        SELECT 'RestaurantOrder:' || ro.hotelrestaurantorderid, ro.ordertime::date, ro.createdat::timestamp, 'RestaurantOrder',
               ro.hotelrestaurantorderid, 'Restaurant / F&B', 'Restaurant order #' || ro.hotelrestaurantorderid,
               0, 0, ro.totalamount, 0, NULL, FALSE, 2, 'Restaurant / F&B', NULL, ro.status
        FROM   public.hotelrestaurantorders ro
        WHERE  lower(ro.farmid) = lower(p_farmid) AND ro.cashtransactionid IS NOT NULL
          AND  ro.reversalcashtransactionid IS NULL AND COALESCE(ro.totalamount, 0) > 0
          AND  ro.ordertime::date BETWEEN p_from AND p_to
        UNION ALL
        SELECT 'LoanRepaid:' || r.hotelemployeeloanrepaymentid, r.repaymentdate::date, r.createdat::timestamp, 'LoanRepaid',
               r.hotelemployeeloanrepaymentid, 'Staff loan repayments', 'Interest on staff loan',
               0, 0, r.interestamount, 0, NULL, FALSE, 2, 'Interest on staff loans', NULL, r.status
        FROM   public.hotelemployeeloanrepayments r
        WHERE  lower(r.farmid) = lower(p_farmid) AND r.status = 'Posted' AND r.interestamount > 0
          AND  r.repaymentdate::date BETWEEN p_from AND p_to
        UNION ALL
        -- ---- expenses ----------------------------------------------------------------
        SELECT 'Payroll:' || pr.hotelpayrollrunid, COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::date,
               pr.createdat::timestamp, 'Payroll', pr.hotelpayrollrunid, 'Staff wages',
               'Payroll ' || to_char(pr.periodstart, 'DD Mon') || ' - ' || to_char(pr.periodend, 'DD Mon YYYY'),
               0, 0, 0, pr.totalgrosspay, NULL, FALSE, 2, 'Staff Wages', NULL, pr.status
        FROM   public.hotelpayrollruns pr
        WHERE  lower(pr.farmid) = lower(p_farmid) AND pr.status = 'Paid' AND COALESCE(pr.totalgrosspay, 0) > 0
          AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::date BETWEEN p_from AND p_to
        UNION ALL
        SELECT 'Expense:' || he.hotelexpenseid, he.expensedate, he.createdat::timestamp, 'Expense', he.hotelexpenseid,
               COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised'),
               COALESCE(NULLIF(btrim(he.description), ''), he.category),
               0, 0, 0, he.amount, NULL, FALSE, 2,
               COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised'),
               COALESCE(s.suppliername, he.paidto, he.vendor), he.status
        FROM   public.hotelexpenses he
        LEFT   JOIN public.hotelexpensecategories ec ON ec.hotelexpensecategoryid = he.hotelexpensecategoryid
        LEFT   JOIN public.hotelsuppliers s ON s.hotelsupplierid = he.hotelsupplierid
        WHERE  lower(he.farmid) = lower(p_farmid) AND he.status IN ('Approved', 'Paid') AND COALESCE(he.amount, 0) > 0
          AND  he.expensedate BETWEEN p_from AND p_to
        UNION ALL
        -- every posted supply purchase is an event (it moves Inventory); only one
        -- expensed when purchased carries its cost, as the P&L does.
        SELECT 'SupplyPurchase:' || p.purchaseid, p.purchasedate, p.createdat, 'SupplyPurchase', p.purchaseid,
               'Supplies', 'Purchase PO-' || p.purchaseid || ': ' || i.name,
               0, 0, 0, CASE WHEN p.costmode = 'EXPENSE_WHEN_PURCHASED' THEN p.totalcost ELSE 0 END, NULL, FALSE, 2,
               CASE WHEN p.costmode = 'EXPENSE_WHEN_PURCHASED' THEN 'Supplies purchased' END,
               COALESCE(s.suppliername, p.suppliername), p.status
        FROM   public.hotelsupplypurchases p
        JOIN   public.hotelinventoryitems i ON i.hotelinventoryitemid = p.hotelinventoryitemid
        LEFT   JOIN public.hotelsuppliers s ON s.hotelsupplierid = p.hotelsupplierid
        WHERE  lower(p.farmid) = lower(p_farmid) AND p.status = 'Posted' AND p.purchasedate BETWEEN p_from AND p_to
        UNION ALL
        -- supplies used: one event per draw type, reference and day
        SELECT 'SupplyUse:' || d.drawtype || ':' || COALESCE(d.reference, '') || ':' || d.drawdate, d.drawdate, MIN(d.createdat),
               'SupplyUse', NULL::int, 'Internal Use', COALESCE(d.reference, d.drawtype),
               0, 0, 0, SUM(d.deferredcost), NULL, FALSE, 2, 'Supplies used', NULL, 'Posted'
        FROM   public.hotelsupplydraws d
        WHERE  lower(d.farmid) = lower(p_farmid) AND d.deferredcost <> 0 AND d.drawdate BETWEEN p_from AND p_to
        GROUP  BY d.drawtype, d.reference, d.drawdate
        UNION ALL
        SELECT 'Depreciation:' || d.hotelassetdepreciationid, d.periodstart, d.createdat::timestamp, 'Depreciation',
               d.hotelassetdepreciationid, 'Depreciation',
               'Depreciation ' || COALESCE(a.assetname, '') || ' - ' || to_char(d.periodstart, 'Mon YYYY'),
               0, 0, 0, d.amount, NULL, FALSE, 2, 'Depreciation', NULL, d.status
        FROM   public.hotelassetdepreciation d
        LEFT   JOIN public.hotelcapitalassets a ON a.hotelcapitalassetid = d.hotelcapitalassetid
        WHERE  lower(d.farmid) = lower(p_farmid) AND d.status = 'Posted' AND d.periodstart BETWEEN p_from AND p_to
        UNION ALL
        SELECT 'FinancingLoanPayment:' || lp.hotelloanpaymentid, lp.paymentdate::date, lp.createdat::timestamp,
               'FinancingLoanPayment', lp.hotelloanpaymentid, 'Loan repayments', 'Loan interest and fees',
               0, 0, 0, COALESCE(lp.interestamount, 0) + COALESCE(lp.feeamount, 0), NULL, FALSE, 2, 'Loan Interest', NULL, lp.status
        FROM   public.hotelloanpayments lp
        WHERE  lower(lp.farmid) = lower(p_farmid) AND lp.status = 'Posted'
          AND  (COALESCE(lp.interestamount, 0) > 0 OR COALESCE(lp.feeamount, 0) > 0)
          AND  lp.paymentdate::date BETWEEN p_from AND p_to
        UNION ALL
        -- ---- internal transfers (no money enters or leaves) --------------------------
        SELECT 'CashTransfer:' || t.hotelcashtransferid, t.transferdate::date, t.createdat::timestamp, 'CashTransfer',
               t.hotelcashtransferid, 'Transfers', 'Transfer ' || COALESCE(t.transfernumber, '#' || t.hotelcashtransferid),
               0, 0, 0, 0, t.fromhotelcashaccountid, TRUE, 3, NULL, NULL, t.status
        FROM   public.hotelcashtransfers t
        WHERE  lower(t.farmid) = lower(p_farmid) AND t.transferdate::date BETWEEN p_from AND p_to
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
                WHEN e.st LIKE 'OwnerMoney%' THEN 'Owner'
                WHEN e.st LIKE 'FinancingLoan%' THEN 'Financing'
                WHEN e.st IN ('LoanDisbursed', 'LoanReversed', 'LoanRepaid', 'LoanRepayReversed') THEN 'EmployeeLoan'
                WHEN e.st LIKE 'CapitalAsset%' OR e.st = 'Depreciation' THEN 'Capital'
                WHEN e.st LIKE 'SupplyPurchase%' OR e.st = 'SupplyUse' THEN 'Inventory'
                ELSE 'Operating' END,
           CASE e.st
               WHEN 'GuestPayment' THEN 'Payment received'
               WHEN 'GuestPaymentVoid' THEN 'Payment reversed'
               WHEN 'RestaurantOrder' THEN 'Sale'
               WHEN 'RestaurantOrderReversal' THEN 'Sale reversed'
               WHEN 'DepositIn' THEN 'Deposit held'
               WHEN 'DepositOut' THEN 'Deposit refunded'
               WHEN 'CustomerPayment' THEN 'Customer payment'
               WHEN 'CustomerPaymentReversal' THEN 'Customer payment reversed'
               WHEN 'Expense' THEN 'Expense'
               WHEN 'ExpenseReversal' THEN 'Expense correction'
               WHEN 'SupplyPurchase' THEN 'Supply purchase'
               WHEN 'SupplyPurchaseReversal' THEN 'Supply purchase reversed'
               WHEN 'SupplyUse' THEN 'Supplies used'
               WHEN 'SupplierPayment' THEN 'Supplier payment'
               WHEN 'SupplierPaymentReversal' THEN 'Supplier payment reversed'
               WHEN 'Payroll' THEN 'Payroll'
               WHEN 'Depreciation' THEN 'Depreciation'
               WHEN 'CapitalAsset' THEN 'Capital investment'
               WHEN 'CapitalAssetReversal' THEN 'Capital investment corrected'
               WHEN 'FinancingLoan' THEN 'Loan received'
               WHEN 'FinancingLoanCancelled' THEN 'Loan corrected'
               WHEN 'FinancingLoanPayment' THEN 'Loan repayment'
               WHEN 'FinancingLoanPaymentReversal' THEN 'Loan repayment reversed'
               WHEN 'OwnerMoney' THEN 'Owner money'
               WHEN 'OwnerMoneyReversal' THEN 'Owner money reversed'
               WHEN 'LoanDisbursed' THEN 'Staff advance'
               WHEN 'LoanReversed' THEN 'Staff advance reversed'
               WHEN 'LoanRepaid' THEN 'Staff advance repaid'
               WHEN 'LoanRepayReversed' THEN 'Staff repayment reversed'
               WHEN 'CashTransfer' THEN 'Transfer'
               WHEN 'ReconciliationAdjustment' THEN 'Cash over / short'
               WHEN 'ReconciliationReversal' THEN 'Cash over / short reversed'
               WHEN 'CashAdjustment' THEN 'Cash adjustment'
               WHEN 'CashAdjustmentReversal' THEN 'Cash adjustment reversed'
               ELSE COALESCE(e.st, 'Other') END,
           COALESCE(e.cat, 'Other'), e.descr, e.st, e.sid, e.st || ' #' || COALESCE(e.sid::text, ''),
           ROUND(e.mi, 2), ROUND(e.mo, 2), ROUND(e.rev, 2), ROUND(e.exp, 2), ROUND(e.rev - e.exp, 2),
           e.hascash AND (e.mi <> 0 OR e.mo <> 0),
           NOT (e.hascash AND (e.mi <> 0 OR e.mo <> 0)) AND NOT e.trf,
           e.trf, e.acc, e.party, e.pl, e.stat
    FROM   ev e;
$function$;

-- -----------------------------------------------------------------------------
-- 2. The page's rows, with running cash seeded from Cash Flow's opening balance
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.sphotelfinancialactivity_get(p_farmid text, p_from date, p_to date)
RETURNS TABLE(eventkey text, businessdate date, occurredat timestamp, createdat timestamp, activitytype text, type text,
              category text, description text, sourcetype text, sourceid int, sourcenumber text, moneyin numeric,
              moneyout numeric, revenue numeric, expense numeric, profitimpact numeric, runningcash numeric,
              iscash boolean, isnoncash boolean, istransfer boolean, cashaccountid int, cashaccountname text,
              partyname text, plline text, status text)
LANGUAGE sql STABLE AS $function$
    WITH opening AS (
        SELECT COALESCE(s.openingbalance, 0) AS bal
        FROM   public.sphotelcashflow_summary(p_farmid, p_from::timestamp, (p_to + 1)::timestamp - interval '1 microsecond') s
    )
    SELECT e.eventkey, e.businessdate, e.occurredat, e.createdat, e.activitytype, e.type, e.category, e.description,
           e.sourcetype, e.sourceid, e.sourcenumber, e.moneyin, e.moneyout, e.revenue, e.expense, e.profitimpact,
           ROUND((SELECT bal FROM opening)
                 + SUM(e.moneyin - e.moneyout) OVER (ORDER BY e.businessdate, e.createdat NULLS FIRST, e.eventkey
                                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2),
           e.iscash, e.isnoncash, e.istransfer, e.cashaccountid, a.accountname::text, e.partyname, e.plline, e.status
    FROM   public.fnhotelfa_events(p_farmid, p_from, p_to) e
    LEFT   JOIN public.hotelcashaccounts a ON a.hotelcashaccountid = e.cashaccountid
    ORDER  BY e.businessdate, e.createdat NULLS FIRST, e.eventkey;
$function$;

CREATE FUNCTION public.sphotelfinancialactivity_summary(p_farmid text, p_from date, p_to date)
RETURNS TABLE(moneyin numeric, moneyout numeric, netcashflow numeric, openingcash numeric, closingcash numeric,
              revenue numeric, expense numeric, netprofit numeric, eventcount int, cashevents int, noncashevents int)
LANGUAGE sql STABLE AS $function$
    WITH cf AS (
        SELECT * FROM public.sphotelcashflow_summary(p_farmid, p_from::timestamp, (p_to + 1)::timestamp - interval '1 microsecond')
    ), ev AS (
        SELECT COALESCE(SUM(e.revenue), 0) AS rev, COALESCE(SUM(e.expense), 0) AS exp, COUNT(*) AS n,
               COUNT(*) FILTER (WHERE e.iscash) AS ncash, COUNT(*) FILTER (WHERE e.isnoncash) AS nnon
        FROM   public.fnhotelfa_events(p_farmid, p_from, p_to) e
    )
    SELECT ROUND(cf.moneyin, 2), ROUND(cf.moneyout, 2), ROUND(cf.netcashflow, 2), ROUND(cf.openingbalance, 2),
           ROUND(cf.cashathand, 2), ROUND(ev.rev, 2), ROUND(ev.exp, 2), ROUND(ev.rev - ev.exp, 2),
           ev.n::int, ev.ncash::int, ev.nnon::int
    FROM   cf CROSS JOIN ev;
$function$;

-- -----------------------------------------------------------------------------
-- 3. What each event did to the hotel's financial position (only positions this
--    database tracks and an owner understands -- not a general ledger).
-- -----------------------------------------------------------------------------
CREATE FUNCTION public.fnhotelfa_positions(p_farmid text, p_from date, p_to date)
RETURNS TABLE(eventkey text, positiontype text, positionname text, increaseamount numeric, decreaseamount numeric,
              explanation text)
LANGUAGE sql STABLE AS $function$
    WITH e AS (SELECT * FROM public.sphotelfinancialactivity_get(p_farmid, p_from, p_to))
    -- cash
    SELECT e.eventkey, 'Cash', COALESCE(e.cashaccountname, 'Cash'), e.moneyin, e.moneyout,
           CASE WHEN e.moneyin > 0 THEN 'Money received into this account.' ELSE 'Money paid out of this account.' END
    FROM   e WHERE e.iscash
    UNION ALL
    -- transfers: both account legs
    SELECT e.eventkey, 'Cash', a.accountname::text,
           CASE WHEN a.hotelcashaccountid = t.tohotelcashaccountid THEN t.amount ELSE 0 END,
           CASE WHEN a.hotelcashaccountid = t.fromhotelcashaccountid THEN t.amount ELSE 0 END,
           'Moved between the hotel''s own accounts; no money entered or left the business.'
    FROM   e JOIN public.hotelcashtransfers t ON e.sourcetype = 'CashTransfer' AND t.hotelcashtransferid = e.sourceid
    JOIN   public.hotelcashaccounts a ON a.hotelcashaccountid IN (t.fromhotelcashaccountid, t.tohotelcashaccountid)
    UNION ALL
    -- what guests and corporate accounts owe on their stays
    SELECT e.eventkey, 'CustomerReceivable', COALESCE(e.partyname, 'Guests and accounts'), e.moneyout, e.moneyin,
           CASE WHEN e.moneyin > 0 THEN 'A guest or corporate account paid what they owed on a stay.'
                ELSE 'A payment was reversed, so the amount is owed again.' END
    FROM   e WHERE e.sourcetype IN ('GuestPayment', 'GuestPaymentVoid', 'CustomerPayment', 'CustomerPaymentReversal')
             AND (e.moneyin <> 0 OR e.moneyout <> 0)
    UNION ALL
    -- supplies bought and used
    SELECT e.eventkey, 'Inventory', i.name::text, p.totalcost, 0, 'Supplies received from the supplier.'
    FROM   e JOIN public.hotelsupplypurchases p ON e.sourcetype = 'SupplyPurchase' AND p.purchaseid = e.sourceid
    JOIN   public.hotelinventoryitems i ON i.hotelinventoryitemid = p.hotelinventoryitemid
    UNION ALL
    SELECT e.eventkey, 'SupplierPayable', COALESCE(e.partyname, 'Supplier'), p.totalcost - p.amountpaid, 0,
           'The part of the purchase not paid when it was recorded is owed to the supplier.'
    FROM   e JOIN public.hotelsupplypurchases p ON e.sourcetype = 'SupplyPurchase' AND p.purchaseid = e.sourceid
    WHERE  p.totalcost > p.amountpaid
    UNION ALL
    SELECT e.eventkey, 'SupplierPayable', COALESCE(e.partyname, 'Supplier'), e.expense, 0,
           'Approved on credit: the bill is owed to the supplier.'
    FROM   e JOIN public.hotelexpenses x ON e.sourcetype = 'Expense' AND x.hotelexpenseid = e.sourceid
    WHERE  x.paymentmethod = 'Credit' AND x.hotelsupplierid IS NOT NULL
    UNION ALL
    SELECT e.eventkey, 'Inventory', 'Supplies', GREATEST(-e.expense, 0), GREATEST(e.expense, 0),
           'Supplies held as inventory value (expense when consumed) were used, so their cost moved into Profit & Loss.'
    FROM   e WHERE e.sourcetype = 'SupplyUse'
    UNION ALL
    SELECT e.eventkey, 'SupplierPayable', 'Supplier', e.moneyin, e.moneyout,
           CASE WHEN e.moneyout > 0 THEN 'A supplier was paid what the hotel owed.' ELSE 'A supplier payment was reversed, so it is owed again.' END
    FROM   e WHERE e.sourcetype IN ('SupplierPayment', 'SupplierPaymentReversal')
    UNION ALL
    -- capital
    SELECT e.eventkey, 'CapitalAsset', 'Capital investments', e.moneyout, e.moneyin,
           'Equipment, furniture or other long-term investment; its cost reaches profit through depreciation.'
    FROM   e WHERE e.sourcetype IN ('CapitalAsset', 'CapitalAssetReversal')
    UNION ALL
    SELECT e.eventkey, 'AccumulatedDepreciation', 'Capital investments', GREATEST(e.expense, 0), GREATEST(-e.expense, 0),
           'The share of the investments'' cost charged to this period.'
    FROM   e WHERE e.sourcetype = 'Depreciation'
    UNION ALL
    -- financing, owner, staff advances
    SELECT e.eventkey, 'LoanLiability', 'Loans', e.moneyin, e.moneyout,
           'Borrowed money: owed back, so it is not income.'
    FROM   e WHERE e.sourcetype IN ('FinancingLoan', 'FinancingLoanCancelled')
    UNION ALL
    SELECT e.eventkey, 'LoanLiability', 'Loans', 0, GREATEST(e.moneyout - e.expense, 0),
           'The principal repaid lowers the debt; interest and fees are the cost.'
    FROM   e WHERE e.sourcetype = 'FinancingLoanPayment'
    UNION ALL
    SELECT e.eventkey, 'OwnerCapital', 'Owner', e.moneyin, e.moneyout, 'Owner money is never income or expense.'
    FROM   e WHERE e.sourcetype LIKE 'OwnerMoney%'
    UNION ALL
    SELECT e.eventkey, 'EmployeeLoanReceivable', 'Staff advances', e.moneyout, e.moneyin,
           'Money lent to staff is owed back, so it is not a cost.'
    FROM   e WHERE e.sourcetype IN ('LoanDisbursed', 'LoanReversed', 'LoanRepaid', 'LoanRepayReversed')
             AND (e.moneyin <> 0 OR e.moneyout <> 0);
$function$;

DO $$
BEGIN
    IF (SELECT COUNT(*) FROM pg_proc WHERE proname IN ('fnhotelfa_events', 'fnhotelfa_positions',
            'sphotelfinancialactivity_get', 'sphotelfinancialactivity_summary')) <> 4 THEN
        RAISE EXCEPTION '336 verification failed: functions missing';
    END IF;
END $$;
