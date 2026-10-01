-- Self-test for migration 335 (Restaurant Financial Activity). Always ends by
-- raising so everything rolls back; "SELFTEST PASSED" is the success signal.
--
-- A day of restaurant business touching every leg: an owner puts money in, a
-- loan comes in and is part repaid with interest, money moves between two own
-- accounts, tomatoes are bought (expense when consumed) and soda (expense when
-- purchased) partly on credit, a walk-in order is paid at the till, a pay-later
-- order is completed and part-collected, jollof is sold (deferred stock drawn),
-- staff eat soda (internal use), an expense is paid. Checked: the page's totals
-- equal Cash Flow's and Profit & Loss's for the same period, the rows add up to
-- the totals, running cash ends at closing cash, legs of one event merge,
-- transfers move no money, and position changes are produced.
DO $$
DECLARE
    f TEXT := '__probe335__';
    v_cash INT; v_bank INT; v_cust INT; v_tom INT; v_soda INT; v_mi INT; o1 INT; o2 INT; v_loan INT; v_e INT; v_iu INT;
    s RECORD; c RECORD; p RECORD; v_n NUMERIC; v_n2 NUMERIC; v_i INT; v_checks INT := 0;
BEGIN
    PERFORM * FROM sprestaurant_cashaccount_list(f);
    SELECT cashaccountid INTO v_cash FROM restaurantcashaccounts WHERE farmid = f AND defaultfor = 'Cash';
    v_bank := sprestaurant_cashaccount_create(f, 'Probe Bank', 'Bank', 0, TRUE, NULL, NULL, 'probe');
    PERFORM sprestaurant_ownermoney_record(f, 'Contribution', v_cash, 1000, CURRENT_DATE, 'Owner', NULL, 'probe');
    v_loan := sprestaurant_loan_create(f, 'Probe Bank Ltd', 500, 500, v_bank, CURRENT_DATE, 10, NULL, NULL, 'probe');
    PERFORM sprestaurant_loan_repay(f, v_loan, v_bank, 100, 15, 5, CURRENT_DATE, NULL, 'probe');
    PERFORM sprestaurant_cashtransfer_create(f, v_bank, v_cash, 200, CURRENT_DATE, NULL, NULL, 'probe');

    PERFORM sprestaurant_costmode_set(f, 'Produce', 'EXPENSE_WHEN_CONSUMED', 'probe');
    INSERT INTO restaurantingredients (farmid, name, category, unit, costperunit, currentstock)
    VALUES (f, 'Tomatoes', 'Produce', 'kg', 0, 0) RETURNING ingredientid INTO v_tom;
    INSERT INTO restaurantingredients (farmid, name, category, unit, costperunit, currentstock)
    VALUES (f, 'Soda', 'Beverages', 'bottle', 0, 0) RETURNING ingredientid INTO v_soda;
    PERFORM sprestaurant_purchase_create(f, v_tom, 10, 100, CURRENT_DATE, NULL, NULL, 'Cash', NULL, v_cash, NULL, NULL, 'probe');
    INSERT INTO restaurantsuppliers (farmid, name) VALUES (f, 'Drinks Co');
    PERFORM sprestaurant_purchase_create(f, v_soda, 24, 48, CURRENT_DATE, NULL, 'Drinks Co', 'Cash', 20, v_cash, NULL, NULL, 'probe');

    INSERT INTO restaurantmenuitems (farmid, name, price) VALUES (f, 'Jollof', 50) RETURNING menuitemid INTO v_mi;
    INSERT INTO restaurantrecipes (farmid, menuitemid, ingredientid, quantity, unit, wastepercent) VALUES (f, v_mi, v_tom, 2, 'kg', 0);
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, status, subtotal, totalamount)
    VALUES (f, 'P335-1', 'Takeaway', 'Served', 100, 100) RETURNING orderid INTO o1;
    INSERT INTO restaurantorderitems (farmid, orderid, menuitemid, itemname, quantity, unitprice, linetotal, status)
    VALUES (f, o1, v_mi, 'Jollof', 2, 50, 100, 'Pending');
    PERFORM sprestaurant_orderpayment_insert(f, o1, 'Cash', 100, 0, NULL, 'probe', v_cash);
    PERFORM sprestaurant_order_update_status(o1, f, 'Completed');
    PERFORM sprestaurant_recipe_deduct_order(o1, f);

    INSERT INTO restaurantcustomers (farmid, name) VALUES (f, 'Ama') RETURNING customerid INTO v_cust;
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, status, subtotal, totalamount, customerid, customername)
    VALUES (f, 'P335-2', 'DineIn', 'Served', 80, 80, v_cust, 'Ama') RETURNING orderid INTO o2;
    PERFORM sprestaurant_order_paylater(f, o2, NULL, NULL, NULL, 'probe');
    PERFORM sprestaurant_order_update_status(o2, f, 'Completed');
    PERFORM sprestaurant_customerpayment_record(f, v_cust, 30, CURRENT_DATE, 'Cash', v_cash, NULL, NULL, 'CustomerBalances',
        'probe', jsonb_build_array(jsonb_build_object('documentId', o2, 'amount', 30)));

    v_iu := sprestaurant_internalusage_insert(f, CURRENT_DATE, 'StaffWelfare', NULL, NULL, NULL, NULL, NULL,
        '[{"itemType":"Ingredient","ingredientId":' || v_tom || ',"entryQuantity":1}]', 'probe');
    PERFORM sprestaurant_internalusage_post(v_iu, f, 'probe');
    v_e := sprestaurant_expense_record(f, CURRENT_DATE, NULL, 'Gas', 'Cooking gas', 40, 'Cash', NULL, NULL, 'probe', v_cash);

    SELECT * INTO s FROM sprestaurantfinancialactivity_summary(f, CURRENT_DATE, CURRENT_DATE);
    SELECT * INTO c FROM sprestaurantcashflow_summary(f, CURRENT_DATE::TIMESTAMP, (CURRENT_DATE + 1)::TIMESTAMP - INTERVAL '1 microsecond');
    SELECT * INTO p FROM sprestaurant_report_pnl_summary(f, CURRENT_DATE, CURRENT_DATE);

    -- 1. totals agree with Cash Flow
    IF s.moneyin <> c.moneyin OR s.moneyout <> c.moneyout OR s.closingcash <> c.cashathand THEN
        RAISE EXCEPTION 'FAIL 1: cash % / % / % vs Cash Flow % / % / %', s.moneyin, s.moneyout, s.closingcash,
            c.moneyin, c.moneyout, c.cashathand; END IF;
    -- 2. totals agree with Profit & Loss
    IF s.revenue <> p.revenue OR s.expense <> p.cogs + p.expenses_total OR s.netprofit <> p.net_profit THEN
        RAISE EXCEPTION 'FAIL 2: profit % / % / % vs P&L % / % / %', s.revenue, s.expense, s.netprofit,
            p.revenue, p.cogs + p.expenses_total, p.net_profit; END IF;
    IF p.revenue <> 180 OR p.net_profit = 0 THEN RAISE EXCEPTION 'FAIL 2b: scenario revenue % (want 100 + 80)', p.revenue; END IF;
    v_checks := v_checks + 3;

    -- 3. the rows add up to the totals; running cash ends at closing cash
    SELECT SUM(moneyin), SUM(moneyout) INTO v_n, v_n2 FROM sprestaurantfinancialactivity_get(f, CURRENT_DATE, CURRENT_DATE);
    IF v_n <> s.moneyin OR v_n2 <> s.moneyout THEN RAISE EXCEPTION 'FAIL 3: rows cash % / %', v_n, v_n2; END IF;
    SELECT SUM(revenue) - SUM(expense) INTO v_n FROM sprestaurantfinancialactivity_get(f, CURRENT_DATE, CURRENT_DATE);
    IF v_n <> s.netprofit THEN RAISE EXCEPTION 'FAIL 3b: rows profit %', v_n; END IF;
    SELECT runningcash INTO v_n FROM sprestaurantfinancialactivity_get(f, CURRENT_DATE, CURRENT_DATE)
     ORDER BY businessdate DESC, createdat DESC NULLS LAST, eventkey DESC LIMIT 1;
    IF v_n <> s.closingcash THEN RAISE EXCEPTION 'FAIL 3c: last running cash % vs closing %', v_n, s.closingcash; END IF;
    v_checks := v_checks + 3;

    -- 4. one event per business event: the expense's cash and cost are one row;
    --    the loan repayment carries interest + fees as its expense
    SELECT moneyout, expense INTO v_n, v_n2 FROM sprestaurantfinancialactivity_get(f, CURRENT_DATE, CURRENT_DATE)
     WHERE eventkey = 'Expense:' || v_e;
    IF v_n <> 40 OR v_n2 <> 40 THEN RAISE EXCEPTION 'FAIL 4: expense row % / %', v_n, v_n2; END IF;
    SELECT moneyout, expense INTO v_n, v_n2 FROM sprestaurantfinancialactivity_get(f, CURRENT_DATE, CURRENT_DATE)
     WHERE sourcetype = 'LoanRepayment';
    IF v_n <> 120 OR v_n2 <> 20 THEN RAISE EXCEPTION 'FAIL 4b: loan repayment % / %', v_n, v_n2; END IF;
    v_checks := v_checks + 2;

    -- 5. activity types and non-cash events
    IF (SELECT COUNT(*) FROM sprestaurantfinancialactivity_get(f, CURRENT_DATE, CURRENT_DATE)
         WHERE activitytype = 'Transfer' AND istransfer AND moneyin = 0 AND moneyout = 0) <> 1 THEN
        RAISE EXCEPTION 'FAIL 5: transfer row'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sprestaurantfinancialactivity_get(f, CURRENT_DATE, CURRENT_DATE)
                    WHERE activitytype = 'Owner' AND moneyin = 1000 AND profitimpact = 0) THEN RAISE EXCEPTION 'FAIL 5b: owner'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sprestaurantfinancialactivity_get(f, CURRENT_DATE, CURRENT_DATE)
                    WHERE activitytype = 'Financing' AND moneyin = 500 AND revenue = 0) THEN RAISE EXCEPTION 'FAIL 5c: loan'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sprestaurantfinancialactivity_get(f, CURRENT_DATE, CURRENT_DATE)
                    WHERE eventkey = 'Order:' || o2 AND revenue = 80 AND isnoncash) THEN RAISE EXCEPTION 'FAIL 5d: pay-later sale'; END IF;
    SELECT COUNT(*), SUM(expense) INTO v_i, v_n FROM sprestaurantfinancialactivity_get(f, CURRENT_DATE, CURRENT_DATE)
     WHERE activitytype = 'Inventory' AND sourcetype = 'StockUse';
    IF v_i <> 2 OR v_n <> 50 THEN RAISE EXCEPTION 'FAIL 5e: stock used % rows % (want sale 40 + internal use 10)', v_i, v_n; END IF;
    IF NOT EXISTS (SELECT 1 FROM sprestaurantfinancialactivity_get(f, CURRENT_DATE, CURRENT_DATE)
                    WHERE sourcetype = 'StockPurchase' AND moneyout = 20 AND expense = 48) THEN RAISE EXCEPTION 'FAIL 5f: soda purchase'; END IF;
    v_checks := v_checks + 6;

    -- 6. positions
    IF NOT EXISTS (SELECT 1 FROM fnrestaurantfa_positions(f, CURRENT_DATE, CURRENT_DATE)
                    WHERE positiontype = 'CustomerReceivable' AND increaseamount = 80) THEN RAISE EXCEPTION 'FAIL 6: receivable'; END IF;
    IF NOT EXISTS (SELECT 1 FROM fnrestaurantfa_positions(f, CURRENT_DATE, CURRENT_DATE)
                    WHERE positiontype = 'SupplierPayable' AND increaseamount = 28) THEN RAISE EXCEPTION 'FAIL 6b: payable'; END IF;
    IF NOT EXISTS (SELECT 1 FROM fnrestaurantfa_positions(f, CURRENT_DATE, CURRENT_DATE)
                    WHERE positiontype = 'LoanLiability' AND decreaseamount = 100) THEN RAISE EXCEPTION 'FAIL 6c: loan principal'; END IF;
    IF (SELECT COUNT(*) FROM fnrestaurantfa_positions(f, CURRENT_DATE, CURRENT_DATE) WHERE eventkey LIKE 'CashTransfer:%') <> 2 THEN
        RAISE EXCEPTION 'FAIL 6d: transfer legs'; END IF;
    v_checks := v_checks + 4;

    -- 7. the bridge still balances
    IF (SELECT amount FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'check') <> 0 THEN
        RAISE EXCEPTION 'FAIL 7: bridge'; END IF;
    v_checks := v_checks + 1;

    RAISE EXCEPTION 'SELFTEST PASSED: % checks (rolled back)', v_checks;
END $$;
