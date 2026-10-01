-- =============================================================================
-- 335_RestaurantFinancialActivity.postgres.sql
--
-- Financial Activity for the standalone Restaurant, copied from Poultry (290,
-- 308, 315): one timeline, one row per business event, each carrying Money In /
-- Money Out AND Revenue / Expense / Profit Impact, plus Running Cash, and the
-- financial positions it moved. READ-ONLY: functions only, no table, no data.
--
-- Built from the SAME sources the other two pages read, so the totals agree by
-- construction (selftest335 asserts it):
--   * the cash leg is sprestaurantcashflow_detail (as of 333) -- the rows Cash
--     Flow sums, transfers and till floats already excluded;
--   * the profit legs repeat sprestaurant_report_pnl_lines' own selections (as
--     of 330/333): completed orders (revenue on the order date, paid or not),
--     partial refunds, stock purchases expensed when purchased, deferred stock
--     drawn (sales, waste, adjustments, internal use), expenses, payroll at
--     gross, depreciation, loan interest and fees, cash over/short and interest
--     on staff loans. Sign rule: Revenue is the Revenue section; Expense is every
--     other line, so Revenue - Expense = the P&L's net profit.
-- Legs of the same event share a key and become one row (an expense paid at
-- entry: its cash and its cost; a purchase: its payment and its charge).
-- Cash transfers between the restaurant's own accounts are shown as internal
-- rows with no money in or out, as Poultry does.
--
-- Activity types: Operating, Financing (Loan*), Owner (Owner*), Capital
-- (Asset*, depreciation), Inventory (stock purchases and stock used), Transfer,
-- EmployeeLoan (staff advances).
-- The Profit vs Cash report (324/330/333) is unchanged.
-- =============================================================================

DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('fnrestaurantfa_events', 'fnrestaurantfa_positions',
                            'sprestaurantfinancialactivity_get', 'sprestaurantfinancialactivity_summary')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 1. Events
-- -----------------------------------------------------------------------------
CREATE FUNCTION fnrestaurantfa_events(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(eventkey TEXT, businessdate DATE, occurredat TIMESTAMP, createdat TIMESTAMP, activitytype TEXT, type TEXT,
              category TEXT, description TEXT, sourcetype TEXT, sourceid INT, sourcenumber TEXT, moneyin NUMERIC,
              moneyout NUMERIC, revenue NUMERIC, expense NUMERIC, profitimpact NUMERIC, iscash BOOLEAN,
              isnoncash BOOLEAN, istransfer BOOLEAN, cashaccountid INT, partyname TEXT, plline TEXT, status TEXT)
LANGUAGE sql STABLE AS $$
    WITH legs AS (
        -- ---- cash: exactly the rows Cash Flow sums --------------------------------
        SELECT d.sourcetype || ':' || d.sourceid AS k, d.transactiondate::DATE AS dt, d.createdat AS ca,
               d.sourcetype AS st, d.sourceid AS sid, d.category AS cat, d.description AS descr,
               GREATEST(d.amount, 0) AS mi, GREATEST(-d.amount, 0) AS mo,
               0::NUMERIC AS rev,
               -- cash over / short is itself the P&L line (profit-signed ledger amount)
               CASE WHEN d.sourcetype IN ('ShiftVariance', 'CountVariance', 'CountVarianceReversal') THEN -d.amount ELSE 0 END AS exp,
               d.cashaccountid AS acc, FALSE AS trf, 1 AS pri,
               CASE WHEN d.sourcetype IN ('ShiftVariance', 'CountVariance', 'CountVarianceReversal') THEN 'Cash over / short' END AS pl,
               NULL::TEXT AS party, 'Posted'::TEXT AS stat
          FROM sprestaurantcashflow_detail(p_farmid, p_from::TIMESTAMP, (p_to + 1)::TIMESTAMP - INTERVAL '1 microsecond') d
        UNION ALL
        -- ---- revenue: completed orders on their order date, paid or not --------------
        SELECT 'Order:' || o.orderid, o.createdat::DATE, o.createdat, 'Order', o.orderid, 'Sales',
               'Order ' || o.ordernumber || COALESCE(' — ' || NULLIF(btrim(o.customername), ''), ''),
               0, 0,
               COALESCE(o.subtotal, 0) - COALESCE(o.discountamount, 0) + COALESCE(o.servicechargeamount, 0)
                 + COALESCE(o.deliveryfee, 0),
               0, NULL::INT, FALSE, 2, 'Food & beverage sales', o.customername, o.status
          FROM restaurantorders o
         WHERE o.farmid = p_farmid AND o.status = 'Completed' AND o.createdat::DATE BETWEEN p_from AND p_to
        UNION ALL
        -- partial refunds on completed orders (same key as their cash leg)
        SELECT 'OrderRefund:' || p.orderpaymentid, p.createdat::DATE, p.createdat, 'OrderRefund', p.orderpaymentid,
               'Refunds to customers', COALESCE(p.reference, 'Refund'), 0, 0, p.amount, 0, NULL, FALSE, 2,
               'Less: partial refunds', NULL, 'Posted'
          FROM restaurantorderpayments p
          JOIN restaurantorders o ON o.orderid = p.orderid AND o.farmid = p.farmid
         WHERE p.farmid = p_farmid AND p.amount < 0 AND p.status = 'Completed' AND o.status = 'Completed'
           AND p.createdat::DATE BETWEEN p_from AND p_to
        UNION ALL
        -- ---- cost of sales ------------------------------------------------------------
        SELECT 'StockPurchase:' || p.purchaseid, p.purchasedate, p.createdat, 'StockPurchase', p.purchaseid,
               'Stock purchases', 'Purchase: ' || i.name, 0, 0, 0, p.totalcost, NULL, FALSE, 2,
               'Stock purchases (expense when purchased)', p.suppliername, p.status
          FROM restaurantpurchases p JOIN restaurantingredients i ON i.ingredientid = p.ingredientid
         WHERE p.farmid = p_farmid AND p.costmode = 'EXPENSE_WHEN_PURCHASED' AND p.purchasedate BETWEEN p_from AND p_to
        UNION ALL
        SELECT 'StockPurchaseReversal:' || p.purchaseid, p.reversedat::DATE, p.reversedat, 'StockPurchaseReversal', p.purchaseid,
               'Stock purchase corrections', 'Reversal of purchase: ' || i.name, 0, 0, 0, -p.totalcost, NULL, FALSE, 2,
               'Stock purchases (expense when purchased)', p.suppliername, 'Reversed'
          FROM restaurantpurchases p JOIN restaurantingredients i ON i.ingredientid = p.ingredientid
         WHERE p.farmid = p_farmid AND p.costmode = 'EXPENSE_WHEN_PURCHASED' AND p.status = 'Reversed'
           AND p.reversedat::DATE BETWEEN p_from AND p_to
        UNION ALL
        -- deferred stock drawn: one event per draw type, reference and day
        SELECT 'StockUse:' || d.drawtype || ':' || COALESCE(d.reference, '') || ':' || d.drawdate, d.drawdate, MIN(d.createdat),
               'StockUse', NULL::INT,
               CASE d.drawtype WHEN 'OrderDeduction' THEN 'Ingredients used' WHEN 'Waste' THEN 'Stock wasted'
                               WHEN 'InternalUse' THEN 'Internal Use' WHEN 'InternalUseReversal' THEN 'Internal Use'
                               ELSE 'Stock adjustments' END,
               COALESCE(d.reference, d.drawtype), 0, 0, 0, SUM(d.deferredcost), NULL, FALSE, 2,
               CASE d.drawtype WHEN 'OrderDeduction' THEN 'Ingredients used (expense when consumed)'
                               WHEN 'Waste' THEN 'Stock wasted (expense when consumed)'
                               WHEN 'InternalUse' THEN 'Internal Use (expense when consumed)'
                               WHEN 'InternalUseReversal' THEN 'Internal Use (expense when consumed)'
                               ELSE 'Stock adjustments (expense when consumed)' END,
               NULL, 'Posted'
          FROM restaurantstockdraws d
         WHERE d.farmid = p_farmid AND d.drawdate BETWEEN p_from AND p_to AND d.deferredcost <> 0
         GROUP BY d.drawtype, d.reference, d.drawdate
        UNION ALL
        -- ---- operating expenses -------------------------------------------------------
        SELECT 'Expense:' || e.expenseid, e.expensedate, e.createdat, 'Expense', e.expenseid,
               COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised'), COALESCE(e.description, e.categoryname),
               0, 0, 0, e.amount, NULL, FALSE, 2, COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised'),
               e.suppliername, COALESCE(e.status, 'Approved')
          FROM restaurantexpenses e
         WHERE e.farmid = p_farmid AND e.expensedate BETWEEN p_from AND p_to
           AND COALESCE(e.status, 'Approved') NOT IN ('Rejected', 'Draft')
        UNION ALL
        SELECT 'Payroll:' || r.payrollrunid, r.paydate, r.createdat, 'Payroll', r.payrollrunid, 'Staff wages (net pay)',
               'Payroll ' || r.runnumber, 0, 0, 0, r.totalgross, NULL, FALSE, 2, 'Staff wages (payroll)', NULL, r.status
          FROM restaurantpayrollruns r
         WHERE r.farmid = p_farmid AND r.status = 'Paid' AND r.paydate BETWEEN p_from AND p_to
        UNION ALL
        SELECT 'Depreciation:' || d.assetdepreciationid, d.depreciationdate, d.createdat, 'Depreciation', d.assetdepreciationid,
               'Depreciation', 'Depreciation', 0, 0, 0, d.amount, NULL, FALSE, 2, 'Depreciation', NULL, 'Posted'
          FROM restaurantassetdepreciation d
         WHERE d.farmid = p_farmid AND d.depreciationdate BETWEEN p_from AND p_to
        UNION ALL
        SELECT 'LoanRepayment:' || lp.loanpaymentid, lp.paymentdate, lp.createdat, 'LoanRepayment', lp.loanpaymentid,
               'Loan repayments', 'Loan interest and fees', 0, 0, 0,
               COALESCE(lp.interestamount, 0) + COALESCE(lp.feeamount, 0), NULL, FALSE, 2, 'Loan interest', NULL, lp.status
          FROM restaurantloanpayments lp
         WHERE lp.farmid = p_farmid AND lp.status = 'Posted' AND lp.paymentdate BETWEEN p_from AND p_to
        UNION ALL
        SELECT 'EmployeeLoanRepayment:' || sr.repaymentid, sr.repaymentdate, sr.createdat, 'EmployeeLoanRepayment', sr.repaymentid,
               'Staff advances repaid', 'Interest on staff loan', 0, 0, 0, -sr.interestamount, NULL, FALSE, 2,
               'Interest on staff loans', NULL, sr.status
          FROM restaurantstaffloanrepayments sr
         WHERE sr.farmid = p_farmid AND sr.status = 'Posted' AND sr.repaymentdate BETWEEN p_from AND p_to
           AND COALESCE(sr.interestamount, 0) <> 0
        UNION ALL
        -- ---- internal transfers (no money enters or leaves) --------------------------
        SELECT 'CashTransfer:' || t.transferid, t.transferdate, t.createdat, 'CashTransfer', t.transferid,
               'Transfers', 'Transfer ' || COALESCE(t.transfernumber, '#' || t.transferid), 0, 0, 0, 0, t.fromaccountid,
               TRUE, 3, NULL, NULL, t.status
          FROM restaurantcashtransfers t
         WHERE t.farmid = p_farmid AND t.transferdate BETWEEN p_from AND p_to
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
          FROM legs l GROUP BY l.k
    )
    SELECT e.k, e.dt, e.dt::TIMESTAMP, e.ca,
           CASE WHEN e.trf THEN 'Transfer'
                WHEN e.st LIKE 'Owner%' THEN 'Owner'
                WHEN e.st LIKE 'Loan%' THEN 'Financing'
                WHEN e.st LIKE 'EmployeeLoan%' THEN 'EmployeeLoan'
                WHEN e.st LIKE 'Asset%' OR e.st = 'Depreciation' THEN 'Capital'
                WHEN e.st LIKE 'StockPurchase%' OR e.st = 'StockUse' THEN 'Inventory'
                ELSE 'Operating' END,
           CASE e.st
               WHEN 'Order' THEN 'Sale'
               WHEN 'OrderPayment' THEN 'Payment received'
               WHEN 'CustomerPayment' THEN 'Customer payment'
               WHEN 'OrderRefund' THEN 'Refund'
               WHEN 'OrderPaymentReversal' THEN 'Payment reversed'
               WHEN 'CustomerPaymentReversal' THEN 'Customer payment reversed'
               WHEN 'Expense' THEN 'Expense'
               WHEN 'ExpenseReversal' THEN 'Expense correction'
               WHEN 'StockPurchase' THEN 'Stock purchase'
               WHEN 'StockPurchaseReversal' THEN 'Stock purchase reversed'
               WHEN 'StockUse' THEN 'Stock used'
               WHEN 'SupplierPayment' THEN 'Supplier payment'
               WHEN 'SupplierPaymentReversal' THEN 'Supplier payment reversed'
               WHEN 'Payroll' THEN 'Payroll'
               WHEN 'Depreciation' THEN 'Depreciation'
               WHEN 'AssetPurchase' THEN 'Capital investment'
               WHEN 'AssetPurchaseReversal' THEN 'Capital investment corrected'
               WHEN 'AssetDisposal' THEN 'Asset disposal'
               WHEN 'LoanReceived' THEN 'Loan received'
               WHEN 'LoanReceivedReversal' THEN 'Loan corrected'
               WHEN 'LoanRepayment' THEN 'Loan repayment'
               WHEN 'LoanRepaymentReversal' THEN 'Loan repayment reversed'
               WHEN 'OwnerContribution' THEN 'Owner contribution'
               WHEN 'OwnerDraw' THEN 'Owner drawing'
               WHEN 'EmployeeLoanDisbursement' THEN 'Staff advance'
               WHEN 'EmployeeLoanRepayment' THEN 'Staff advance repaid'
               WHEN 'CashTransfer' THEN 'Transfer'
               WHEN 'GiftCardSale' THEN 'Gift card sold'
               WHEN 'GiftCardReload' THEN 'Gift card reloaded'
               WHEN 'ShiftVariance' THEN 'Cash over / short'
               WHEN 'CountVariance' THEN 'Cash over / short'
               ELSE COALESCE(e.st, 'Other') END,
           COALESCE(e.cat, 'Other'), e.descr, e.st, e.sid, e.st || ' #' || e.sid,
           ROUND(e.mi, 2), ROUND(e.mo, 2), ROUND(e.rev, 2), ROUND(e.exp, 2), ROUND(e.rev - e.exp, 2),
           e.hascash AND (e.mi <> 0 OR e.mo <> 0),
           NOT (e.hascash AND (e.mi <> 0 OR e.mo <> 0)) AND NOT e.trf,
           e.trf, e.acc, e.party, e.pl, e.stat
      FROM ev e;
$$;

-- -----------------------------------------------------------------------------
-- 2. The page's rows, with running cash seeded from Cash Flow's opening balance
-- -----------------------------------------------------------------------------
CREATE FUNCTION sprestaurantfinancialactivity_get(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(eventkey TEXT, businessdate DATE, occurredat TIMESTAMP, createdat TIMESTAMP, activitytype TEXT, type TEXT,
              category TEXT, description TEXT, sourcetype TEXT, sourceid INT, sourcenumber TEXT, moneyin NUMERIC,
              moneyout NUMERIC, revenue NUMERIC, expense NUMERIC, profitimpact NUMERIC, runningcash NUMERIC,
              iscash BOOLEAN, isnoncash BOOLEAN, istransfer BOOLEAN, cashaccountid INT, cashaccountname TEXT,
              partyname TEXT, plline TEXT, status TEXT)
LANGUAGE sql STABLE AS $$
    WITH opening AS (
        SELECT COALESCE(s.openingbalance, 0) AS bal
          FROM sprestaurantcashflow_summary(p_farmid, p_from::TIMESTAMP, (p_to + 1)::TIMESTAMP - INTERVAL '1 microsecond') s
    )
    SELECT e.eventkey, e.businessdate, e.occurredat, e.createdat, e.activitytype, e.type, e.category, e.description,
           e.sourcetype, e.sourceid, e.sourcenumber, e.moneyin, e.moneyout, e.revenue, e.expense, e.profitimpact,
           ROUND((SELECT bal FROM opening)
                 + SUM(e.moneyin - e.moneyout) OVER (ORDER BY e.businessdate, e.createdat NULLS FIRST, e.eventkey
                                                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2),
           e.iscash, e.isnoncash, e.istransfer, e.cashaccountid, a.name::TEXT, e.partyname, e.plline, e.status
      FROM fnrestaurantfa_events(p_farmid, p_from, p_to) e
      LEFT JOIN restaurantcashaccounts a ON a.cashaccountid = e.cashaccountid
     ORDER BY e.businessdate, e.createdat NULLS FIRST, e.eventkey;
$$;

CREATE FUNCTION sprestaurantfinancialactivity_summary(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(moneyin NUMERIC, moneyout NUMERIC, netcashflow NUMERIC, openingcash NUMERIC, closingcash NUMERIC,
              revenue NUMERIC, expense NUMERIC, netprofit NUMERIC, eventcount INT, cashevents INT, noncashevents INT)
LANGUAGE sql STABLE AS $$
    WITH cf AS (
        SELECT * FROM sprestaurantcashflow_summary(p_farmid, p_from::TIMESTAMP, (p_to + 1)::TIMESTAMP - INTERVAL '1 microsecond')
    ), ev AS (
        SELECT COALESCE(SUM(e.revenue), 0) AS rev, COALESCE(SUM(e.expense), 0) AS exp, COUNT(*) AS n,
               COUNT(*) FILTER (WHERE e.iscash) AS ncash, COUNT(*) FILTER (WHERE e.isnoncash) AS nnon
          FROM fnrestaurantfa_events(p_farmid, p_from, p_to) e
    )
    SELECT ROUND(cf.moneyin, 2), ROUND(cf.moneyout, 2), ROUND(cf.netcashflow, 2), ROUND(cf.openingbalance, 2),
           ROUND(cf.cashathand, 2), ROUND(ev.rev, 2), ROUND(ev.exp, 2), ROUND(ev.rev - ev.exp, 2),
           ev.n::INT, ev.ncash::INT, ev.nnon::INT
      FROM cf CROSS JOIN ev;
$$;

-- -----------------------------------------------------------------------------
-- 3. What each event did to the restaurant's financial position (not a general
--    ledger -- only positions this database tracks and an owner understands).
-- -----------------------------------------------------------------------------
CREATE FUNCTION fnrestaurantfa_positions(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(eventkey TEXT, positiontype TEXT, positionname TEXT, increaseamount NUMERIC, decreaseamount NUMERIC,
              explanation TEXT)
LANGUAGE sql STABLE AS $$
    WITH e AS (SELECT * FROM sprestaurantfinancialactivity_get(p_farmid, p_from, p_to))
    -- cash
    SELECT e.eventkey, 'Cash', COALESCE(e.cashaccountname, 'Cash'), e.moneyin, e.moneyout,
           CASE WHEN e.moneyin > 0 THEN 'Money received into this account.' ELSE 'Money paid out of this account.' END
      FROM e WHERE e.iscash
    UNION ALL
    -- transfers: both account legs
    SELECT e.eventkey, 'Cash', a.name::TEXT,
           CASE WHEN a.cashaccountid = t.toaccountid THEN t.amount ELSE 0 END,
           CASE WHEN a.cashaccountid = t.fromaccountid THEN t.amount ELSE 0 END,
           'Moved between the restaurant''s own accounts; no money entered or left the business.'
      FROM e JOIN restaurantcashtransfers t ON e.sourcetype = 'CashTransfer' AND t.transferid = e.sourceid
      JOIN restaurantcashaccounts a ON a.cashaccountid IN (t.fromaccountid, t.toaccountid)
    UNION ALL
    -- pay-later orders raise what customers owe; collections lower it
    SELECT e.eventkey, 'CustomerReceivable', COALESCE(e.partyname, 'Customer'), o.totalamount, 0,
           'Completed on Pay later: the customer owes the bill until it is paid.'
      FROM e JOIN restaurantorderpaylater l ON e.sourcetype = 'Order' AND l.orderid = e.sourceid
      JOIN restaurantorders o ON o.orderid = l.orderid
    UNION ALL
    SELECT e.eventkey, 'CustomerReceivable', COALESCE(e.partyname, 'Customer'), 0, e.moneyin,
           'A customer paid what they owed on a pay-later order.'
      FROM e WHERE e.sourcetype = 'CustomerPayment'
    UNION ALL
    -- stock bought and used
    SELECT e.eventkey, 'Inventory', i.name::TEXT, p.totalcost, 0, 'Stock received from the supplier.'
      FROM e JOIN restaurantpurchases p ON e.sourcetype = 'StockPurchase' AND p.purchaseid = e.sourceid
      JOIN restaurantingredients i ON i.ingredientid = p.ingredientid
    UNION ALL
    SELECT e.eventkey, 'SupplierPayable', COALESCE(p.suppliername, 'Supplier'), p.totalcost - p.amountpaid, 0,
           'The part of the purchase not paid when it was recorded is owed to the supplier.'
      FROM e JOIN restaurantpurchases p ON e.sourcetype = 'StockPurchase' AND p.purchaseid = e.sourceid
     WHERE p.totalcost > p.amountpaid
    UNION ALL
    SELECT e.eventkey, 'Inventory', 'Stock', GREATEST(-e.expense, 0), GREATEST(e.expense, 0),
           'Stock held as inventory value (expense when consumed) was used, so its cost moved into Profit & Loss.'
      FROM e WHERE e.sourcetype = 'StockUse'
    UNION ALL
    SELECT e.eventkey, 'SupplierPayable', 'Supplier', 0, e.moneyout, 'A supplier was paid what the restaurant owed.'
      FROM e WHERE e.sourcetype = 'SupplierPayment'
    UNION ALL
    -- capital
    SELECT e.eventkey, 'CapitalAsset', 'Capital investments', e.moneyout, e.moneyin,
           'Equipment or other long-term investment; its cost reaches profit through depreciation.'
      FROM e WHERE e.sourcetype IN ('AssetPurchase', 'AssetPurchaseReversal')
    UNION ALL
    SELECT e.eventkey, 'AccumulatedDepreciation', 'Capital investments', GREATEST(e.expense, 0), GREATEST(-e.expense, 0),
           'The share of the investments'' cost charged to this period.'
      FROM e WHERE e.sourcetype = 'Depreciation'
    UNION ALL
    -- financing, owner, staff advances
    SELECT e.eventkey, 'LoanLiability', 'Loans', e.moneyin, 0, 'Borrowed money: owed back, so it is not income.'
      FROM e WHERE e.sourcetype = 'LoanReceived'
    UNION ALL
    SELECT e.eventkey, 'LoanLiability', 'Loans', 0, GREATEST(e.moneyout - e.expense, 0),
           'The principal repaid lowers the debt; interest and fees are the cost.'
      FROM e WHERE e.sourcetype = 'LoanRepayment'
    UNION ALL
    SELECT e.eventkey, 'OwnerCapital', 'Owner', e.moneyin, e.moneyout, 'Owner money is never income or expense.'
      FROM e WHERE e.sourcetype LIKE 'Owner%'
    UNION ALL
    SELECT e.eventkey, 'EmployeeLoanReceivable', 'Staff advances', e.moneyout, e.moneyin,
           'Money lent to staff is owed back, so it is not a cost.'
      FROM e WHERE e.sourcetype LIKE 'EmployeeLoan%' AND (e.moneyin <> 0 OR e.moneyout <> 0);
$$;

DO $$
BEGIN
    IF (SELECT COUNT(*) FROM pg_proc WHERE proname IN ('fnrestaurantfa_events', 'fnrestaurantfa_positions',
            'sprestaurantfinancialactivity_get', 'sprestaurantfinancialactivity_summary')) <> 4 THEN
        RAISE EXCEPTION '335 verification failed: functions missing';
    END IF;
END $$;
