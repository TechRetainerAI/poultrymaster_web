-- =============================================================================
-- 324  Restaurant money reports: the reads that let the cash ledger (323) flow
--      through the reporting system the way Poultry's and Water's do.
-- =============================================================================
--
-- Poultry and Water surface their money through a Cash Account Report (where the
-- money sits: opening / in / out / closing per account + ledger + transfers), a
-- Money Movement report (transfers, owner money, loans, repayments), a Closing
-- Report and the Cash Flow pages. This file adds the restaurant equivalents'
-- data, all read-only and all from the ONE ledger 323 built, so every report
-- agrees with Cash Flow and with the account balances by construction:
--
--   sprestaurant_cashledger_period      per-account opening/in/out/transfers/closing
--   sprestaurant_cashledger_rows        the ledger across accounts, with names and
--                                       per-account running balance
--   sprestaurant_loan_payments          now: NULL loan = every repayment (with lender)
--   sprestaurant_dailyclosing_list      now: optional date range
--   sprestaurant_report_takings_by_account  money received per account and method,
--                                       including gift-card payments (no cash)
--   sprestaurant_report_cash_profit_bridge  why cash moved differently from profit:
--                                       net profit -> each difference -> net cash flow
--
-- Transfers, till floats and drops move money between accounts. They show on
-- the account reports (they change a drawer's balance) but never as money in or
-- out of the business -- the same rule Cash Flow follows.
-- Re-runnable: every function here is dropped by name first.
-- =============================================================================

DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN ('fnrestaurant_is_internal_move', 'sprestaurant_cashledger_period',
                            'sprestaurant_cashledger_rows', 'sprestaurant_loan_payments',
                            'sprestaurant_dailyclosing_list', 'sprestaurant_report_takings_by_account',
                            'sprestaurant_report_cash_profit_bridge')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

-- The movements between the restaurant's own accounts. One definition, used by
-- every report here, so "internal" can never mean two things.
CREATE FUNCTION fnrestaurant_is_internal_move(p_sourcetype TEXT)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE AS $$
    SELECT p_sourcetype IN ('TransferOut', 'TransferIn', 'TransferReversalOut', 'TransferReversalIn',
                            'ShiftFloatOut', 'ShiftFloatIn', 'ShiftDropOut', 'ShiftDropIn');
$$;

-- Where the money sits, per account, for a period. Opening includes the opening
-- balances of accounts created inside the period (money that was already there),
-- matching sprestaurantcashflow_summary. opening + moneyin - moneyout +
-- transfersin - transfersout = closing, exactly.
CREATE FUNCTION sprestaurant_cashledger_period(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(cashaccountid INT, name TEXT, accounttype TEXT, isactive BOOLEAN,
              openingbalance NUMERIC, moneyin NUMERIC, moneyout NUMERIC,
              transfersin NUMERIC, transfersout NUMERIC, closingbalance NUMERIC,
              currentbalance NUMERIC, ledgerbalance NUMERIC, txncount BIGINT,
              lastcountedat TIMESTAMP, lastcountedbalance NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT a.cashaccountid, a.name, a.accounttype, a.isactive,
           COALESCE(SUM(t.amount) FILTER (WHERE t.txndate < p_from
                                           OR (t.sourcetype = 'OpeningBalance' AND t.txndate <= p_to)), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.txndate BETWEEN p_from AND p_to AND t.amount > 0
                                           AND t.sourcetype <> 'OpeningBalance'
                                           AND NOT fnrestaurant_is_internal_move(t.sourcetype)), 0),
           COALESCE(-SUM(t.amount) FILTER (WHERE t.txndate BETWEEN p_from AND p_to AND t.amount < 0
                                            AND t.sourcetype <> 'OpeningBalance'
                                            AND NOT fnrestaurant_is_internal_move(t.sourcetype)), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.txndate BETWEEN p_from AND p_to AND t.amount > 0
                                           AND fnrestaurant_is_internal_move(t.sourcetype)), 0),
           COALESCE(-SUM(t.amount) FILTER (WHERE t.txndate BETWEEN p_from AND p_to AND t.amount < 0
                                            AND fnrestaurant_is_internal_move(t.sourcetype)), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.txndate <= p_to), 0),
           a.currentbalance,
           COALESCE(SUM(t.amount), 0),
           COUNT(t.cashtxnid) FILTER (WHERE t.txndate BETWEEN p_from AND p_to),
           a.lastcountedat, a.lastcountedbalance
      FROM restaurantcashaccounts a
      LEFT JOIN restaurantcashtransactions t ON t.cashaccountid = a.cashaccountid
     WHERE a.farmid = p_farmid
     GROUP BY a.cashaccountid
     ORDER BY a.isactive DESC,
              CASE a.accounttype WHEN 'Till' THEN 0 WHEN 'CashBox' THEN 1 WHEN 'PettyCash' THEN 2
                                 WHEN 'MobileMoney' THEN 3 WHEN 'Bank' THEN 4 ELSE 5 END,
              a.name;
$$;

-- The ledger across every account (or one), oldest first, with the running
-- balance OF EACH ACCOUNT computed over all time before the period filter.
CREATE FUNCTION sprestaurant_cashledger_rows(p_farmid TEXT, p_from DATE, p_to DATE, p_accountid INT DEFAULT NULL)
RETURNS TABLE(cashtxnid INT, txndate DATE, cashaccountid INT, accountname TEXT, txntype TEXT,
              sourcetype TEXT, sourceid INT, amount NUMERIC, runningbalance NUMERIC,
              isinternal BOOLEAN, description TEXT, shiftid INT, createdby TEXT, createdat TIMESTAMP)
LANGUAGE sql STABLE AS $$
    SELECT x.cashtxnid, x.txndate, x.cashaccountid, x.accountname, x.txntype, x.sourcetype, x.sourceid,
           x.amount, x.running, fnrestaurant_is_internal_move(x.sourcetype), x.description, x.shiftid,
           x.createdby, x.createdat
    FROM (
        SELECT t.*, a.name AS accountname,
               SUM(t.amount) OVER (PARTITION BY t.cashaccountid ORDER BY t.txndate, t.cashtxnid) AS running
          FROM restaurantcashtransactions t
          JOIN restaurantcashaccounts a ON a.cashaccountid = t.cashaccountid
         WHERE t.farmid = p_farmid AND (p_accountid IS NULL OR t.cashaccountid = p_accountid)
    ) x
    WHERE x.txndate BETWEEN p_from AND p_to
    ORDER BY x.txndate, x.cashtxnid;
$$;

-- As 323, plus the loan's number and lender, and NULL loan = every repayment.
CREATE FUNCTION sprestaurant_loan_payments(p_farmid TEXT, p_loanid INT DEFAULT NULL)
RETURNS TABLE(loanpaymentid INT, loanid INT, loannumber TEXT, lendername TEXT, paymentdate DATE,
              cashaccountid INT, accountname TEXT, principalamount NUMERIC, interestamount NUMERIC,
              feeamount NUMERIC, totalamount NUMERIC, status TEXT, notes TEXT, createdby TEXT,
              createdat TIMESTAMP, reversalreason TEXT)
LANGUAGE sql STABLE AS $$
    SELECT p.loanpaymentid, p.loanid, l.loannumber, l.lendername, p.paymentdate, p.cashaccountid, a.name,
           p.principalamount, p.interestamount, p.feeamount,
           p.principalamount + p.interestamount + p.feeamount,
           p.status, p.notes, p.createdby, p.createdat, p.reversalreason
      FROM restaurantloanpayments p
      JOIN restaurantloans l ON l.loanid = p.loanid
      JOIN restaurantcashaccounts a ON a.cashaccountid = p.cashaccountid
     WHERE p.farmid = p_farmid AND (p_loanid IS NULL OR p.loanid = p_loanid)
     ORDER BY p.paymentdate DESC, p.loanpaymentid DESC;
$$;

CREATE FUNCTION sprestaurant_dailyclosing_list(p_farmid TEXT, p_limit INT DEFAULT 60,
                                               p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL)
RETURNS TABLE(closingid INT, closingdate DATE, status TEXT, ordercount INT, netsales NUMERIC,
              taxcollected NUMERIC, moneyin NUMERIC, moneyout NUMERIC, cashvariance NUMERIC, notes TEXT,
              closedby TEXT, closedat TIMESTAMP, reopenedby TEXT, reopenedat TIMESTAMP, reopenreason TEXT)
LANGUAGE sql STABLE AS $$
    SELECT d.closingid, d.closingdate, d.status, d.ordercount, d.netsales, d.taxcollected, d.moneyin,
           d.moneyout, d.cashvariance, d.notes, d.closedby, d.closedat, d.reopenedby, d.reopenedat, d.reopenreason
      FROM restaurantdailyclosings d
     WHERE d.farmid = p_farmid
       AND (p_from IS NULL OR d.closingdate >= p_from)
       AND (p_to IS NULL OR d.closingdate <= p_to)
     ORDER BY d.closingdate DESC
     LIMIT COALESCE(p_limit, 60);
$$;

-- Money received, per account and method. Payments that moved no cash (gift
-- card, voucher) have no ledger row, so they are listed under "No cash moved"
-- to keep the total equal to the Payment Methods report.
CREATE FUNCTION sprestaurant_report_takings_by_account(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(accountname TEXT, accounttype TEXT, paymentmethod TEXT, paymentcount BIGINT,
              takings NUMERIC, tips NUMERIC, refunds NUMERIC, nettotal NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(a.name, 'No cash moved'), COALESCE(a.accounttype, '—'), p.paymentmethod,
           COUNT(*) FILTER (WHERE p.amount > 0),
           COALESCE(SUM(p.amount) FILTER (WHERE p.amount > 0), 0),
           COALESCE(SUM(p.tipamount) FILTER (WHERE p.amount > 0), 0),
           COALESCE(-SUM(p.amount) FILTER (WHERE p.amount < 0), 0),
           COALESCE(SUM(p.amount + COALESCE(p.tipamount, 0)), 0)
      FROM restaurantorderpayments p
      LEFT JOIN restaurantcashtransactions t
             ON t.sourcetype IN ('OrderPayment', 'OrderRefund') AND t.sourceid = p.orderpaymentid
      LEFT JOIN restaurantcashaccounts a ON a.cashaccountid = t.cashaccountid
     WHERE p.farmid = p_farmid AND p.status = 'Completed'
       AND p.createdat::DATE BETWEEN p_from AND p_to
     GROUP BY COALESCE(a.name, 'No cash moved'), COALESCE(a.accounttype, '—'), p.paymentmethod
     ORDER BY 8 DESC;
$$;

-- Profit is not cash. Starting from the P&L's net profit, every line here is a
-- reason the cash moved by a different amount, ending at the Cash Flow net for
-- the same dates. The two "timing" lines are measured, not guessed: they are
-- the sales cash (or expense cash) the ledger actually recorded minus what the
-- P&L recognised for the same period, so the bridge always lands exactly on
-- the Cash Flow figure and the size of each difference is visible.
CREATE FUNCTION sprestaurant_report_cash_profit_bridge(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(sortorder INT, linekey TEXT, label TEXT, amount NUMERIC, kind TEXT, explanation TEXT)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    v_profit NUMERIC; v_rev NUMERIC; v_cogs NUMERIC; v_exp_pl NUMERIC;
    v_tax NUMERIC; v_tips NUMERIC; v_gift_paid NUMERIC; v_sales_cash NUMERIC;
    v_gift_sold NUMERIC; v_exp_cash NUMERIC; v_loan_int NUMERIC; v_loan_cash NUMERIC;
    v_loan_in NUMERIC; v_owner NUMERIC; v_var NUMERIC; v_net NUMERIC;
    v_sales_timing NUMERIC; v_exp_timing NUMERIC; v_principal NUMERIC;
BEGIN
    SELECT s.net_profit, s.revenue, s.cogs INTO v_profit, v_rev, v_cogs
      FROM sprestaurant_report_pnl_summary(p_farmid, p_from, p_to) s;

    SELECT COALESCE(-SUM(l.amount) FILTER (WHERE l.section = 'Expenses'), 0),
           COALESCE(-SUM(l.amount) FILTER (WHERE l.linekey IN ('loan_interest', 'loan_fees')), 0),
           COALESCE(SUM(l.amount) FILTER (WHERE l.linekey = 'cash_variance'), 0)
      INTO v_exp_pl, v_loan_int, v_var
      FROM sprestaurant_report_pnl_lines(p_farmid, p_from, p_to) l;

    -- Tax on the orders the P&L counted: the customer paid it, it is not revenue.
    SELECT COALESCE(SUM(o.taxamount), 0) INTO v_tax FROM restaurantorders o
     WHERE o.farmid = p_farmid AND o.status = 'Completed' AND o.createdat::DATE BETWEEN p_from AND p_to;

    -- Order money as the ledger recorded it (payments incl. tips, less refunds).
    SELECT COALESCE(SUM(t.amount), 0) INTO v_sales_cash FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.sourcetype IN ('OrderPayment', 'OrderRefund')
       AND t.txndate BETWEEN p_from AND p_to;
    SELECT COALESCE(SUM(p.tipamount), 0) INTO v_tips FROM restaurantorderpayments p
     WHERE p.farmid = p_farmid AND p.status = 'Completed' AND p.amount > 0
       AND p.createdat::DATE BETWEEN p_from AND p_to;
    SELECT COALESCE(SUM(p.amount), 0) INTO v_gift_paid FROM restaurantorderpayments p
     WHERE p.farmid = p_farmid AND p.status = 'Completed' AND p.amount > 0
       AND NOT fnrestaurant_is_cash_method(p.paymentmethod)
       AND p.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('GiftCardSale', 'GiftCardReload')), 0),
           COALESCE(-SUM(t.amount) FILTER (WHERE t.sourcetype IN ('Expense', 'ExpenseReversal')), 0),
           COALESCE(-SUM(t.amount) FILTER (WHERE t.sourcetype IN ('LoanRepayment', 'LoanRepaymentReversal')), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('LoanReceived', 'LoanReceivedReversal')), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype LIKE 'Owner%'), 0)
      INTO v_gift_sold, v_exp_cash, v_loan_cash, v_loan_in, v_owner
      FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.txndate BETWEEN p_from AND p_to;

    SELECT s.netcashflow INTO v_net
      FROM sprestaurantcashflow_summary(p_farmid, p_from::TIMESTAMP, (p_to + 1)::TIMESTAMP - INTERVAL '1 microsecond') s;

    -- Sales: what the P&L counted, plus the tax and tips customers paid on top,
    -- minus what they paid with gift cards (value that came in earlier as cash).
    v_sales_timing := v_sales_cash - (v_rev + v_tax + v_tips - v_gift_paid);
    v_exp_timing := v_exp_pl - v_exp_cash;          -- + when the P&L cost more than was paid out
    v_principal := v_loan_cash - v_loan_int;        -- principal leaves cash but is not a cost

    RETURN QUERY VALUES
        (10, 'net_profit', 'Net profit (from the P&L)', ROUND(v_profit, 2), 'start',
         'Revenue less cost of goods, expenses, loan costs and cash over/short.'),
        (20, 'cogs', 'Add back: recipe cost of food sold', ROUND(v_cogs, 2), 'adjust',
         'The P&L charges ingredient cost when food is sold; the cash left when stock was bought (recorded as expenses).'),
        (30, 'tax', 'Add: tax collected from customers', ROUND(v_tax, 2), 'adjust',
         'Customers paid it, but it is owed to the tax office, so it is not revenue.'),
        (40, 'tips', 'Add: tips received', ROUND(v_tips, 2), 'adjust',
         'Tips come into the till but belong to staff, so they are not revenue.'),
        (50, 'gift_paid', 'Less: sales paid with gift cards', ROUND(-v_gift_paid, 2), 'adjust',
         'Revenue with no cash today — the cash came in when the card was sold.'),
        (60, 'gift_sold', 'Add: gift cards sold and reloaded', ROUND(v_gift_sold, 2), 'adjust',
         'Cash received for food not yet served. It becomes revenue when the card is used.'),
        (70, 'sales_timing', 'Sales timing differences', ROUND(v_sales_timing, 2), 'adjust',
         'Payments taken this period for orders counted in another period (or the reverse), and full refunds.'),
        (80, 'expense_timing', 'Expense timing differences', ROUND(v_exp_timing, 2), 'adjust',
         'Expenses counted in the P&L but paid in another period, or paid without a cash movement.'),
        (90, 'loan_in', 'Add: loans received', ROUND(v_loan_in, 2), 'adjust',
         'Borrowed money is cash in but not income.'),
        (100, 'loan_principal', 'Less: loan principal repaid', ROUND(-v_principal, 2), 'adjust',
         'Paying back what was borrowed is cash out but not a cost. Interest and fees are already in the P&L.'),
        (110, 'owner', 'Add: owner money (contributions less drawings)', ROUND(v_owner, 2), 'adjust',
         'Owner money moves cash but is never income or expense.'),
        (200, 'net_cash', 'Net cash flow (from Cash Flow)', ROUND(v_net, 2), 'result',
         'Money in less money out across every account, transfers excluded.'),
        (210, 'check', 'Unexplained', ROUND(v_net - (v_profit + v_cogs + v_tax + v_tips - v_gift_paid + v_gift_sold
                                                   + v_sales_timing + v_exp_timing + v_loan_in - v_principal + v_owner), 2),
         'check', 'Should be zero. Anything else is a ledger row this bridge does not classify yet.');
END $$;
