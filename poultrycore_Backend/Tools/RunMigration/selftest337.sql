-- Self-test for migration 337 (edit a Restaurant expense). Always ends by
-- raising so everything rolls back; "SELFTEST PASSED" is the success signal.
--
-- Gas paid in cash is edited up, then its wording only, then down, then moved
-- to the bank; a supplier bill with a supplier payment applied cannot be cut
-- below what was paid or moved to another supplier; future and closed dates are
-- refused; an edited expense is deleted. Checked: the ledger (one reversal + one
-- new posting per money edit, nothing for a wording edit), balances, the
-- revision history, the cash-flow category, P&L and the bridge.
DO $$
DECLARE
    f TEXT := '__probe337__';
    v_cash INT; v_bank INT; v_sup INT; v_sup2 INT; v_e1 INT; v_e2 INT; v_e3 INT; v_pay INT;
    v_n NUMERIC; v_i INT; v_txt TEXT; v_failed BOOLEAN; v_checks INT := 0; v_y DATE := CURRENT_DATE - 1;
BEGIN
    PERFORM * FROM sprestaurant_cashaccount_list(f);
    SELECT cashaccountid INTO v_cash FROM restaurantcashaccounts WHERE farmid = f AND defaultfor = 'Cash';
    v_bank := sprestaurant_cashaccount_create(f, 'Probe Bank', 'Bank', 1000, TRUE, NULL, NULL, 'probe');
    v_sup := sprestaurant_supplier_insert(f, 'Gas Co', NULL, NULL, NULL, NULL, NULL, NULL);
    v_sup2 := sprestaurant_supplier_insert(f, 'Other Co', NULL, NULL, NULL, NULL, NULL, NULL);

    v_e1 := sprestaurant_expense_record(f, CURRENT_DATE, NULL, 'Gas', 'Cooking gas', 100, 'Cash', NULL, NULL, 'probe', v_cash);

    -- 1. money edit: 100 -> 120, one reversal and one new posting
    PERFORM sprestaurant_expense_update(v_e1, f, CURRENT_DATE, NULL, 'Gas', 'Cooking gas', 120, 'Cash', NULL, NULL, 'probe', v_cash);
    IF (SELECT amount FROM restaurantexpenses WHERE expenseid = v_e1) <> 120 THEN RAISE EXCEPTION 'FAIL 1: amount'; END IF;
    SELECT COUNT(*), SUM(amount) INTO v_i, v_n FROM restaurantcashtransactions WHERE farmid = f AND cashaccountid = v_cash;
    IF v_i <> 3 OR v_n <> -120 THEN RAISE EXCEPTION 'FAIL 1b: ledger % rows sum % (want 3, -120)', v_i, v_n; END IF;
    IF (SELECT sourcetype FROM fnrestaurant_expense_liveposting(f, v_e1) LIMIT 1) <> 'ExpenseEdit' THEN RAISE EXCEPTION 'FAIL 1c: live posting'; END IF;
    v_checks := v_checks + 3;

    -- 2. wording only: no cash moves, history still kept
    PERFORM sprestaurant_expense_update(v_e1, f, CURRENT_DATE, NULL, 'Utilities', 'Cooking gas refill', 120, 'Cash', NULL, NULL, 'probe', v_cash);
    IF (SELECT COUNT(*) FROM restaurantcashtransactions WHERE farmid = f AND cashaccountid = v_cash) <> 3 THEN RAISE EXCEPTION 'FAIL 2: wording edit moved cash'; END IF;
    IF (SELECT COUNT(*) FROM restaurantexpenserevisions WHERE expenseid = v_e1) <> 2
       OR (SELECT movedcash FROM restaurantexpenserevisions WHERE expenseid = v_e1 ORDER BY revisionid DESC LIMIT 1) THEN
        RAISE EXCEPTION 'FAIL 2b: revision history'; END IF;
    v_checks := v_checks + 2;

    -- 3. down to 80 and out of the bank instead
    PERFORM sprestaurant_expense_update(v_e1, f, CURRENT_DATE, NULL, 'Utilities', 'Cooking gas refill', 80, 'Bank Transfer', NULL, NULL, 'probe', v_bank);
    IF (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_cash) <> 0
       OR (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_bank) <> 920 THEN
        RAISE EXCEPTION 'FAIL 3: balances cash % bank %', (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_cash),
            (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_bank); END IF;
    SELECT category INTO v_txt FROM sprestaurantcashflow_detail(f) WHERE sourcetype = 'ExpenseEdit' AND amount = -80;
    IF v_txt <> 'Utilities' THEN RAISE EXCEPTION 'FAIL 3b: cash-flow category %', v_txt; END IF;
    IF (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'expense:Utilities') <> -80 THEN
        RAISE EXCEPTION 'FAIL 3c: P&L'; END IF;
    IF (SELECT amount FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'check') <> 0 THEN
        RAISE EXCEPTION 'FAIL 3d: bridge'; END IF;
    v_checks := v_checks + 4;

    -- 4. a supplier bill with a payment applied
    v_e2 := sprestaurant_expense_record(f, CURRENT_DATE, NULL, 'Gas', 'Gas on account', 200, 'Credit', NULL, NULL, 'probe',
                                        NULL, v_sup, 0, CURRENT_DATE + 30);
    v_pay := sprestaurant_supplierpayment_record(f, v_sup, 150,
        jsonb_build_array(jsonb_build_object('documenttype', 'Expense', 'documentid', v_e2, 'amount', 150)), 'Cash', NOW()::TIMESTAMP, v_bank);
    v_failed := FALSE; BEGIN PERFORM sprestaurant_expense_update(v_e2, f, CURRENT_DATE, NULL, 'Gas', 'Gas on account', 140, 'Credit', NULL, NULL,
        'probe', NULL, v_sup, 0, NULL);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'Supplier payments totalling 150.00 have been applied to this expense, so its total cannot be reduced to 140.00.'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4: cut below the supplier payment'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_expense_update(v_e2, f, CURRENT_DATE, NULL, 'Gas', 'Gas on account', 200, 'Credit', NULL, NULL,
        'probe', NULL, v_sup2, 0, NULL);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE '%so its supplier cannot change%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4b: supplier changed under a payment'; END IF;
    PERFORM sprestaurant_expense_update(v_e2, f, CURRENT_DATE, NULL, 'Gas', 'Gas on account', 250, 'Credit', NULL, NULL,
        'probe', NULL, v_sup, 0, CURRENT_DATE + 30);
    SELECT balance INTO v_n FROM sprestaurant_expense_payments(f) WHERE expenseid = v_e2;
    IF v_n <> 100 THEN RAISE EXCEPTION 'FAIL 4c: still owed % (want 250 - 150)', v_n; END IF;
    IF EXISTS (SELECT 1 FROM restaurantcashtransactions WHERE sourcetype LIKE 'ExpenseEdit%'
                AND sourceid IN (SELECT revisionid FROM restaurantexpenserevisions WHERE expenseid = v_e2)) THEN
        RAISE EXCEPTION 'FAIL 4d: an unpaid bill''s edit moved cash'; END IF;
    v_checks := v_checks + 4;

    -- 5. dates
    v_failed := FALSE; BEGIN PERFORM sprestaurant_expense_update(v_e1, f, CURRENT_DATE + 1, NULL, 'Utilities', 'x', 80, 'Cash', NULL, NULL, 'probe', v_cash);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE '%future%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5: future date'; END IF;
    v_e3 := sprestaurant_expense_record(f, v_y, NULL, 'Gas', 'Yesterday gas', 30, 'Cash', NULL, NULL, 'probe', v_cash);
    INSERT INTO restaurantdailyclosings (farmid, closingdate, status, closedby) VALUES (f, v_y, 'Closed', 'probe');
    v_failed := FALSE; BEGIN PERFORM sprestaurant_expense_update(v_e3, f, CURRENT_DATE, NULL, 'Gas', 'Moved', 30, 'Cash', NULL, NULL, 'probe', v_cash);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'The books are closed%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5b: edited a closed day''s expense'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_expense_update(v_e1, f, v_y, NULL, 'Utilities', 'x', 80, 'Cash', NULL, NULL, 'probe', v_cash);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'The books are closed%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5c: moved into a closed day'; END IF;
    v_checks := v_checks + 3;

    -- 6. delete an edited expense: its live (edited) posting comes back
    PERFORM sprestaurant_expense_delete(v_e1, f);
    IF (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_bank) <> 1000 - 150 THEN
        RAISE EXCEPTION 'FAIL 6: bank after delete %', (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_bank); END IF;
    IF (SELECT amount FROM restaurantcashtransactions WHERE sourcetype = 'ExpenseReversal' AND sourceid = v_e1) <> 80 THEN
        RAISE EXCEPTION 'FAIL 6b: delete reversal'; END IF;
    v_checks := v_checks + 2;

    -- 7. books agree
    IF (SELECT amount FROM sprestaurant_report_cash_profit_bridge(f, v_y, CURRENT_DATE) WHERE linekey = 'check') <> 0 THEN
        RAISE EXCEPTION 'FAIL 7: bridge'; END IF;
    IF EXISTS (SELECT 1 FROM restaurantcashaccounts a WHERE a.farmid = f
                 AND a.currentbalance <> COALESCE((SELECT SUM(t.amount) FROM restaurantcashtransactions t
                                                    WHERE t.cashaccountid = a.cashaccountid), 0)) THEN
        RAISE EXCEPTION 'FAIL 7b: a balance disagrees with its ledger'; END IF;
    v_checks := v_checks + 2;

    RAISE EXCEPTION 'SELFTEST PASSED: % checks (rolled back)', v_checks;
END $$;
