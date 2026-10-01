-- Self-test for migration 333 (Restaurant pay-later orders, Customer Balances,
-- Payments). Always ends by raising so everything rolls back; "SELFTEST PASSED"
-- is the success signal.
--
-- Ama (a saved customer) eats twice on account: order 1 (100, 20 paid at the
-- till) and order 2 (50, yesterday, nothing paid). A walk-in cannot pay later.
-- Ama pays 90 against both orders in one payment, which is then reversed; the
-- till payment is reversed too. Checked: completion rule, payment status,
-- balances / summary / open orders, one ledger row per payment, allocations,
-- history, statement, P&L revenue on completion, cash flow, bridge = 0, audit.
DO $$
DECLARE
    f TEXT := '__probe333__';
    v_cash INT; v_c1 INT; v_c2 INT; o1 INT; o2 INT; o3 INT; o4 INT; v_op INT; v_op4 INT; v_cp INT;
    v_n NUMERIC; v_i INT; v_txt TEXT; v_failed BOOLEAN; v_checks INT := 0;
BEGIN
    PERFORM * FROM sprestaurant_cashaccount_list(f);
    SELECT cashaccountid INTO v_cash FROM restaurantcashaccounts WHERE farmid = f AND defaultfor = 'Cash';
    INSERT INTO restaurantcustomers (farmid, name, phone) VALUES (f, 'Ama Mensah', '0244111222') RETURNING customerid INTO v_c1;
    INSERT INTO restaurantcustomers (farmid, name, phone) VALUES (f, 'Kofi', '0244333444') RETURNING customerid INTO v_c2;
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, status, subtotal, totalamount, customerid, customername)
    VALUES (f, 'P333-1', 'DineIn', 'Served', 100, 100, v_c1, 'Ama Mensah') RETURNING orderid INTO o1;
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, status, subtotal, totalamount, customerid, customername, createdat)
    VALUES (f, 'P333-2', 'Takeaway', 'Served', 50, 50, v_c1, 'Ama Mensah', NOW() - INTERVAL '1 day') RETURNING orderid INTO o2;
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, status, subtotal, totalamount)
    VALUES (f, 'P333-3', 'Takeaway', 'Served', 30, 30) RETURNING orderid INTO o3;
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, status, subtotal, totalamount)
    VALUES (f, 'P333-4', 'Takeaway', 'Served', 10, 10) RETURNING orderid INTO o4;

    -- 1. walk-ins still pay in full
    v_failed := FALSE; BEGIN PERFORM sprestaurant_order_update_status(o3, f, 'Completed');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE '%still has 30.00 to pay%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1: walk-in completed unpaid'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_order_paylater(f, o3);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'Only a saved customer can pay later%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1b: walk-in marked pay later'; END IF;
    v_checks := v_checks + 2;

    -- 2. pay-later orders complete unpaid / part-paid
    v_op := sprestaurant_orderpayment_insert(f, o1, 'Cash', 20, 0, NULL, 'probe', v_cash);
    PERFORM sprestaurant_order_paylater(f, o1, NULL, NULL, NULL, 'probe');
    PERFORM sprestaurant_order_update_status(o1, f, 'Completed');
    PERFORM sprestaurant_order_paylater(f, o2, NULL, NULL, NULL, 'probe');
    PERFORM sprestaurant_order_update_status(o2, f, 'Completed');
    SELECT paymentstatus INTO v_txt FROM restaurantorders WHERE orderid = o1;
    IF v_txt <> 'Partial' THEN RAISE EXCEPTION 'FAIL 2: o1 status % (want Partial)', v_txt; END IF;
    IF (SELECT paymentstatus FROM restaurantorders WHERE orderid = o2) <> 'Unpaid' THEN RAISE EXCEPTION 'FAIL 2b: o2 status'; END IF;
    v_op4 := sprestaurant_orderpayment_insert(f, o4, 'Cash', 10, 0, NULL, 'probe', v_cash);
    PERFORM sprestaurant_order_update_status(o4, f, 'Completed');
    IF (SELECT paymentstatus FROM restaurantorders WHERE orderid = o4) <> 'Paid' THEN RAISE EXCEPTION 'FAIL 2c: walk-in paid'; END IF;
    v_checks := v_checks + 3;

    -- 3. revenue when completed, not when collected
    IF (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'food_sales') <> 110 THEN
        RAISE EXCEPTION 'FAIL 3: food sales today (want 100 + 10)'; END IF;
    IF (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE - 1, CURRENT_DATE - 1) WHERE linekey = 'food_sales') <> 50 THEN
        RAISE EXCEPTION 'FAIL 3b: yesterday''s unpaid order not revenue'; END IF;
    IF (SELECT amount FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE - 1, CURRENT_DATE) WHERE linekey = 'check') <> 0 THEN
        RAISE EXCEPTION 'FAIL 3c: bridge'; END IF;
    v_checks := v_checks + 3;

    -- 4. Customer Balances
    SELECT totalbalance, opendocumentcount, overdueamount INTO v_n, v_i, v_txt FROM sprestaurant_customerbalances(f) WHERE customerid = v_c1;
    IF v_n <> 130 OR v_i <> 2 OR v_txt::NUMERIC <> 50 THEN RAISE EXCEPTION 'FAIL 4: balance % docs % overdue %', v_n, v_i, v_txt; END IF;
    IF (SELECT COUNT(*) FROM sprestaurant_customerbalances(f)) <> 1 THEN RAISE EXCEPTION 'FAIL 4b: parties'; END IF;
    IF (SELECT totalbalance FROM sprestaurant_customerbalancesummary(f)) <> 130 THEN RAISE EXCEPTION 'FAIL 4c: summary'; END IF;
    IF (SELECT COUNT(*) FROM sprestaurant_customeropenorders(f, v_c1)) <> 2 THEN RAISE EXCEPTION 'FAIL 4d: open orders'; END IF;
    IF (SELECT COUNT(*) FROM sprestaurant_customerbalances(f, NULL, NULL, NULL, 'Overdue')) <> 1 THEN RAISE EXCEPTION 'FAIL 4e: overdue filter'; END IF;
    v_checks := v_checks + 5;

    -- 5. one payment across both orders
    v_failed := FALSE; BEGIN PERFORM sprestaurant_customerpayment_record(f, v_c1, 90, CURRENT_DATE, 'Cash', v_cash, NULL, NULL,
        'CustomerBalances', 'probe', jsonb_build_array(jsonb_build_object('documentId', o2, 'amount', 50)));
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'The amounts applied%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5: allocations not adding up accepted'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_customerpayment_record(f, v_c1, 60, CURRENT_DATE, 'Cash', v_cash, NULL, NULL,
        'CustomerBalances', 'probe', jsonb_build_array(jsonb_build_object('documentId', o2, 'amount', 60)));
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE '%only has 50.00 still owed%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5b: over-allocation accepted'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_customerpayment_record(f, v_c2, 10, CURRENT_DATE, 'Cash', v_cash, NULL, NULL,
        'CustomerBalances', 'probe', jsonb_build_array(jsonb_build_object('documentId', o2, 'amount', 10)));
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE '%not a pay-later order of this customer%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5c: another customer''s order accepted'; END IF;
    v_cp := sprestaurant_customerpayment_record(f, v_c1, 90, CURRENT_DATE, 'Cash', v_cash, 'R-1', NULL, 'CustomerBalances', 'probe',
        jsonb_build_array(jsonb_build_object('documentId', o2, 'amount', 50), jsonb_build_object('documentId', o1, 'amount', 40)));
    IF (SELECT COUNT(*) FROM restaurantcashtransactions WHERE farmid = f AND sourcetype = 'CustomerPayment') <> 1
       OR (SELECT amount FROM restaurantcashtransactions WHERE sourcetype = 'CustomerPayment' AND sourceid = v_cp) <> 90 THEN
        RAISE EXCEPTION 'FAIL 5d: not one ledger row of 90'; END IF;
    IF (SELECT paymentstatus FROM restaurantorders WHERE orderid = o2) <> 'Paid'
       OR (SELECT paidamount FROM restaurantorders WHERE orderid = o1) <> 60 THEN RAISE EXCEPTION 'FAIL 5e: orders after payment'; END IF;
    IF (SELECT totalbalance FROM sprestaurant_customerbalances(f) WHERE customerid = v_c1) <> 40 THEN RAISE EXCEPTION 'FAIL 5f: balance 40'; END IF;
    IF (SELECT COUNT(*) FROM customerpaymentallocation WHERE module = 'restaurant' AND farmid = f AND paymentid = v_cp) <> 2 THEN
        RAISE EXCEPTION 'FAIL 5g: allocations'; END IF;
    v_checks := v_checks + 7;

    -- 6. history, allocations, statement
    SELECT allocationcount, sourcetype INTO v_i, v_txt FROM sprestaurant_customerpayment_history(f) WHERE paymentid = 'CP-' || v_cp;
    IF v_i <> 2 OR v_txt <> 'CustomerBalances' THEN RAISE EXCEPTION 'FAIL 6: CP history row % %', v_i, v_txt; END IF;
    IF NOT EXISTS (SELECT 1 FROM sprestaurant_customerpayment_history(f) WHERE paymentid = 'OP-' || v_op AND sourcetype = 'SaleEntry' AND saleid = o1) THEN
        RAISE EXCEPTION 'FAIL 6b: till payment not listed'; END IF;
    IF (SELECT COUNT(*) FROM sprestaurant_customerpayment_history(f)) <> 3 THEN RAISE EXCEPTION 'FAIL 6c: history count (want CP + 2 OP)'; END IF;
    IF (SELECT COUNT(*) FROM sprestaurant_customerpayment_allocations(f, 'CP-' || v_cp)) <> 2 THEN RAISE EXCEPTION 'FAIL 6d'; END IF;
    SELECT runningbalance INTO v_n FROM sprestaurant_customerstatement(f, v_c1) ORDER BY entrydate DESC NULLS LAST, entrytype DESC LIMIT 1;
    IF (SELECT runningbalance FROM (SELECT runningbalance, ROW_NUMBER() OVER () rn FROM sprestaurant_customerstatement(f, v_c1)) s
         ORDER BY rn DESC LIMIT 1) <> 40 THEN RAISE EXCEPTION 'FAIL 6e: statement closing balance'; END IF;
    v_checks := v_checks + 5;

    -- 7. cash flow and bridge
    IF (SELECT COUNT(*) FROM sprestaurantcashflow_detail(f) WHERE category = 'Customer payments') <> 1 THEN RAISE EXCEPTION 'FAIL 7: cash flow'; END IF;
    IF (SELECT amount FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE - 1, CURRENT_DATE) WHERE linekey = 'check') <> 0 THEN
        RAISE EXCEPTION 'FAIL 7b: bridge after collection'; END IF;
    v_checks := v_checks + 2;

    -- 8. reverse the balance payment
    v_failed := FALSE; BEGIN PERFORM sprestaurant_customerpayment_reverse(f, 'CP-' || v_cp, '', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'A reason is required%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 8: reversal without reason'; END IF;
    IF sprestaurant_customerpayment_reverse(f, 'CP-' || v_cp, 'Cheque bounced', 'probe') <> 2 THEN RAISE EXCEPTION 'FAIL 8b: count'; END IF;
    IF (SELECT amount FROM restaurantcashtransactions WHERE sourcetype = 'CustomerPaymentReversal' AND sourceid = v_cp) <> -90 THEN
        RAISE EXCEPTION 'FAIL 8c: reversal ledger'; END IF;
    IF (SELECT totalbalance FROM sprestaurant_customerbalances(f) WHERE customerid = v_c1) <> 130 THEN RAISE EXCEPTION 'FAIL 8d: owed again'; END IF;
    IF (SELECT status FROM sprestaurant_customerpayment_history(f) WHERE paymentid = 'CP-' || v_cp) <> 'Reversed' THEN RAISE EXCEPTION 'FAIL 8e'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_customerpayment_reverse(f, 'CP-' || v_cp, 'again', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE '%already been reversed%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 8f: reversed twice'; END IF;
    v_checks := v_checks + 6;

    -- 9. till payments: reversible on a pay-later order, not on a paid walk-in
    PERFORM sprestaurant_customerpayment_reverse(f, 'OP-' || v_op, 'Wrong order', 'probe');
    IF (SELECT amount FROM restaurantcashtransactions WHERE sourcetype = 'OrderPaymentReversal' AND sourceid = v_op) <> -20 THEN
        RAISE EXCEPTION 'FAIL 9: till reversal ledger'; END IF;
    IF (SELECT totalbalance FROM sprestaurant_customerbalances(f) WHERE customerid = v_c1) <> 150 THEN RAISE EXCEPTION 'FAIL 9b: balance 150'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_customerpayment_reverse(f, 'OP-' || v_op4, 'x', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE '%Refund it on the order instead%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 9c: walk-in payment reversed'; END IF;
    v_checks := v_checks + 3;

    -- 10. books still agree
    IF (SELECT amount FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE - 1, CURRENT_DATE) WHERE linekey = 'check') <> 0 THEN
        RAISE EXCEPTION 'FAIL 10: bridge after reversals'; END IF;
    IF EXISTS (SELECT 1 FROM sprestaurant_customerbalance_audit(f)) THEN RAISE EXCEPTION 'FAIL 10b: audit'; END IF;
    IF EXISTS (SELECT 1 FROM restaurantcashaccounts a WHERE a.farmid = f
                 AND a.currentbalance <> COALESCE((SELECT SUM(t.amount) FROM restaurantcashtransactions t
                                                    WHERE t.cashaccountid = a.cashaccountid), 0)) THEN
        RAISE EXCEPTION 'FAIL 10c: ledger vs balance'; END IF;
    IF (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_cash) <> 10 THEN
        RAISE EXCEPTION 'FAIL 10d: cash (want 20 + 10 + 90 - 90 - 20 = 10)'; END IF;
    v_checks := v_checks + 4;

    RAISE EXCEPTION 'SELFTEST PASSED: % checks (rolled back)', v_checks;
END $$;
