-- Self-test for migration 324 (restaurant money reports). Append to the
-- migration and run; it always ends by raising so everything rolls back.
-- "SELFTEST PASSED" in the error is the success signal.
DO $$
DECLARE
    f text := '__probe324__';
    v_mi int; v_o1 int; v_o2 int; v_till int; v_cash int; v_bank int; v_shift int; v_loan int;
    v_gc text; v_n numeric; v_n2 numeric; v_i int; v_checks int := 0; r record;
BEGIN
    INSERT INTO restaurantprofiles (farmid, restaurantname, taxrate, servicechargerate) VALUES (f, 'Probe 324', 10, 0);
    INSERT INTO restaurantmenuitems (farmid, name, price) VALUES (f, 'Dish', 100) RETURNING menuitemid INTO v_mi;
    PERFORM * FROM sprestaurant_cashaccount_list(f);
    SELECT cashaccountid INTO v_cash FROM restaurantcashaccounts WHERE farmid = f AND defaultfor = 'Cash';
    SELECT cashaccountid INTO v_bank FROM restaurantcashaccounts WHERE farmid = f AND defaultfor = 'Bank';
    v_till := sprestaurant_cashaccount_create(f, 'Till 1', 'Till', 0, FALSE, NULL, NULL, 'probe');
    PERFORM sprestaurant_cashaccount_create(f, 'Safe', 'CashBox', 500, FALSE, NULL, NULL, 'probe');
    v_shift := sprestaurant_cashshift_open(f, v_till, 40, v_cash, 'probe', NULL);

    -- order 1: 110 incl. tax, paid 110 cash + 5 tip
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, status) VALUES (f, 'P324-1', 'Takeaway', 'Placed') RETURNING orderid INTO v_o1;
    INSERT INTO restaurantorderitems (farmid, orderid, menuitemid, itemname, quantity, unitprice, linetotal, status)
    VALUES (f, v_o1, v_mi, 'Dish', 1, 100, 100, 'Pending');
    PERFORM sprestaurant_order_recalc(v_o1, f);
    PERFORM sprestaurant_orderpayment_insert(f, v_o1, 'Cash', 110, 5, NULL, 'probe');
    PERFORM sprestaurant_order_update_status(v_o1, f, 'Completed', NULL);
    -- gift card sold by card, then order 2 (110) paid 60 gift card + 50 mobile money
    SELECT g.cardnumber INTO v_gc FROM sprestaurant_giftcard_create(f, 'Digital', 80, NULL, NULL, NULL, NULL, NULL, NULL, 'Card', NULL, 'probe') g;
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, status) VALUES (f, 'P324-2', 'Takeaway', 'Placed') RETURNING orderid INTO v_o2;
    INSERT INTO restaurantorderitems (farmid, orderid, menuitemid, itemname, quantity, unitprice, linetotal, status)
    VALUES (f, v_o2, v_mi, 'Dish', 1, 100, 100, 'Pending');
    PERFORM sprestaurant_order_recalc(v_o2, f);
    PERFORM sprestaurant_orderpayment_insert(f, v_o2, 'GiftCard', 60, 0, v_gc, 'probe');
    PERFORM sprestaurant_orderpayment_insert(f, v_o2, 'MobileMoney', 50, 0, NULL, 'probe');
    PERFORM sprestaurant_order_update_status(v_o2, f, 'Completed', NULL);
    PERFORM sprestaurant_orderpayment_refund(f, v_o2, 20, 'MobileMoney', 'probe', 'probe');

    PERFORM sprestaurant_expense_record(f, CURRENT_DATE, NULL, 'Gas', 'Gas', 30, 'Cash', NULL, NULL, 'probe', NULL);
    PERFORM sprestaurant_cashtransfer_create(f, v_cash, v_bank, 25, CURRENT_DATE, NULL, NULL, 'probe');
    PERFORM sprestaurant_ownermoney_record(f, 'Contribution', v_bank, 200, CURRENT_DATE, 'Owner', NULL, 'probe');
    PERFORM sprestaurant_ownermoney_record(f, 'Draw', v_bank, 50, CURRENT_DATE, 'Owner', NULL, 'probe');
    v_loan := sprestaurant_loan_create(f, 'Lender', 300, 300, v_bank, CURRENT_DATE, NULL, NULL, NULL, 'probe');
    PERFORM sprestaurant_loan_repay(f, v_loan, v_bank, 100, 12, 3, CURRENT_DATE, NULL, 'probe');
    PERFORM sprestaurant_cashshift_close(f, v_shift, 150, 100, v_cash, 'probe', NULL);  -- expected 155 -> short 5

    -- 1. every account: opening + in - out + tin - tout = closing = cached balance
    FOR r IN SELECT * FROM sprestaurant_cashledger_period(f, CURRENT_DATE, CURRENT_DATE) LOOP
        IF r.openingbalance + r.moneyin - r.moneyout + r.transfersin - r.transfersout <> r.closingbalance THEN
            RAISE EXCEPTION 'FAIL 1: % does not balance', r.name; END IF;
        IF r.closingbalance <> r.currentbalance THEN
            RAISE EXCEPTION 'FAIL 1b: % closing % <> balance %', r.name, r.closingbalance, r.currentbalance; END IF;
    END LOOP;
    SELECT openingbalance INTO v_n FROM sprestaurant_cashledger_period(f, CURRENT_DATE, CURRENT_DATE) WHERE name = 'Safe';
    IF v_n <> 500 THEN RAISE EXCEPTION 'FAIL 1c: safe opening %', v_n; END IF;
    v_checks := v_checks + 3;

    -- 2. account in/out across the business = Cash Flow; transfers net to zero
    SELECT SUM(moneyin - moneyout), SUM(transfersin - transfersout) INTO v_n, v_n2
      FROM sprestaurant_cashledger_period(f, CURRENT_DATE, CURRENT_DATE);
    IF v_n2 <> 0 THEN RAISE EXCEPTION 'FAIL 2: transfers net %', v_n2; END IF;
    IF v_n <> (SELECT s.netcashflow FROM sprestaurantcashflow_summary(f, CURRENT_DATE::timestamp, (CURRENT_DATE + 1)::timestamp - interval '1 microsecond') s) THEN
        RAISE EXCEPTION 'FAIL 2b: accounts net % <> cash flow', v_n; END IF;
    v_checks := v_checks + 2;

    -- 3. the bridge lands exactly on net cash flow
    SELECT amount INTO v_n FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'check';
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 3: bridge unexplained %', v_n; END IF;
    SELECT amount INTO v_n FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'gift_paid';
    IF v_n <> -60 THEN RAISE EXCEPTION 'FAIL 3b: gift paid %', v_n; END IF;
    SELECT amount INTO v_n FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'loan_principal';
    IF v_n <> -100 THEN RAISE EXCEPTION 'FAIL 3c: principal %', v_n; END IF;
    v_checks := v_checks + 3;

    -- 4. takings by account total = every payment incl. the gift-card one
    SELECT SUM(nettotal) INTO v_n FROM sprestaurant_report_takings_by_account(f, CURRENT_DATE, CURRENT_DATE);
    IF v_n <> 110 + 5 + 60 + 50 - 20 THEN RAISE EXCEPTION 'FAIL 4: takings %', v_n; END IF;
    IF NOT EXISTS (SELECT 1 FROM sprestaurant_report_takings_by_account(f, CURRENT_DATE, CURRENT_DATE)
                    WHERE accountname = 'No cash moved' AND paymentmethod = 'GiftCard') THEN
        RAISE EXCEPTION 'FAIL 4b: gift card takings row missing'; END IF;
    v_checks := v_checks + 2;

    -- 5. ledger rows: running balance per account ends at the balance
    SELECT r2.runningbalance INTO v_n FROM sprestaurant_cashledger_rows(f, CURRENT_DATE, CURRENT_DATE, v_till) r2
     ORDER BY r2.cashtxnid DESC LIMIT 1;
    IF v_n <> (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_till) THEN
        RAISE EXCEPTION 'FAIL 5: till running %', v_n; END IF;
    SELECT COUNT(*) INTO v_i FROM sprestaurant_cashledger_rows(f, CURRENT_DATE, CURRENT_DATE, NULL) WHERE isinternal;
    IF v_i <> 6 THEN RAISE EXCEPTION 'FAIL 5b: internal rows % (want 6: float x2, transfer x2, drop x2)', v_i; END IF;
    v_checks := v_checks + 2;

    -- 6. all repayments with lender; closing list with a range
    SELECT COUNT(*) INTO v_i FROM sprestaurant_loan_payments(f, NULL) WHERE lendername = 'Lender';
    IF v_i <> 1 THEN RAISE EXCEPTION 'FAIL 6: repayments %', v_i; END IF;
    PERFORM sprestaurant_dailyclosing_close(f, CURRENT_DATE, NULL, 'probe');
    SELECT COUNT(*) INTO v_i FROM sprestaurant_dailyclosing_list(f, 10, CURRENT_DATE, CURRENT_DATE);
    IF v_i <> 1 THEN RAISE EXCEPTION 'FAIL 6b: closings %', v_i; END IF;
    SELECT COUNT(*) INTO v_i FROM sprestaurant_dailyclosing_list(f, 10, CURRENT_DATE - 30, CURRENT_DATE - 1);
    IF v_i <> 0 THEN RAISE EXCEPTION 'FAIL 6c: range ignored'; END IF;
    v_checks := v_checks + 3;

    RAISE EXCEPTION 'SELFTEST PASSED: % checks (rolled back)', v_checks;
END $$;
