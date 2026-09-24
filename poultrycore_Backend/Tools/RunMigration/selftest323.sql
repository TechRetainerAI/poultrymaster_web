-- Self-test for migration 323 (restaurant finance).
--
-- Run it APPENDED to the migration, in one go:
--   cat ../../PoultryFarmAPI/Migrations/323_RestaurantFinance.postgres.sql selftest323.sql > t.sql
--   dotnet run -- t.sql
-- It always ends by raising, so RunMigration rolls the WHOLE file back: the
-- migration, the backfill and every probe row. "SELFTEST PASSED" in the error
-- is the success signal; anything else names the failing check.
DO $$
DECLARE
    f        text := '__probe323__';
    v_cat    int; v_mi int; v_ia int; v_ib int;
    v_o1     int; v_o2 int; v_o3 int;
    v_cash   int; v_bank int; v_momo int; v_till int;
    v_shift  int; v_exp int; v_trf int; v_own int; v_loan int; v_lp int; v_cnt int;
    v_gc     text; v_gc2 text;
    v_n      numeric; v_n2 numeric; v_txt text; v_txt2 text; v_i int;
    v_checks int := 0; v_backfill int;
BEGIN
    SELECT COUNT(*) INTO v_backfill FROM restaurantcashtransactions WHERE createdby = 'Migration 323';

    INSERT INTO restaurantprofiles (farmid, restaurantname, taxrate, servicechargerate)
    VALUES (f, 'Probe 323', 10, 5);
    INSERT INTO restaurantexpensecategories (farmid, name) VALUES (f, 'Utilities') RETURNING expensecategoryid INTO v_cat;
    INSERT INTO restaurantmenuitems (farmid, name, price) VALUES (f, 'Jollof', 100) RETURNING menuitemid INTO v_mi;
    INSERT INTO restaurantingredients (farmid, name, currentstock, costperunit) VALUES (f, 'Rice', 10, 4) RETURNING ingredientid INTO v_ia;
    INSERT INTO restaurantingredients (farmid, name, currentstock, costperunit) VALUES (f, 'Oil', 10, 2) RETURNING ingredientid INTO v_ib;
    INSERT INTO restaurantrecipes (farmid, menuitemid, ingredientid, quantity, unit, wastepercent) VALUES (f, v_mi, v_ia, 2, 'kg', 0);
    INSERT INTO restaurantrecipes (farmid, menuitemid, ingredientid, quantity, unit, wastepercent) VALUES (f, v_mi, v_ib, 3, 'l', 0);

    -- 1. recalc applies Setup rates; service charge is dine-in only
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, status) VALUES (f, 'P323-1', 'DineIn', 'Placed') RETURNING orderid INTO v_o1;
    INSERT INTO restaurantorderitems (farmid, orderid, menuitemid, itemname, quantity, unitprice, linetotal, status)
    VALUES (f, v_o1, v_mi, 'Jollof', 1, 100, 100, 'Pending');
    PERFORM sprestaurant_order_recalc(v_o1, f, NULL, NULL);
    SELECT totalamount INTO v_n FROM restaurantorders WHERE orderid = v_o1;
    IF v_n <> 115 THEN RAISE EXCEPTION 'FAIL 1: dine-in total % <> 115', v_n; END IF;
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, status) VALUES (f, 'P323-2', 'Takeaway', 'Placed') RETURNING orderid INTO v_o2;
    INSERT INTO restaurantorderitems (farmid, orderid, menuitemid, itemname, quantity, unitprice, linetotal, status)
    VALUES (f, v_o2, v_mi, 'Jollof', 1, 100, 100, 'Pending');
    PERFORM sprestaurant_order_recalc(v_o2, f);
    SELECT totalamount INTO v_n FROM restaurantorders WHERE orderid = v_o2;
    IF v_n <> 110 THEN RAISE EXCEPTION 'FAIL 1b: takeaway total % <> 110', v_n; END IF;
    v_checks := v_checks + 2;

    -- 2. overpayment refused
    BEGIN
        PERFORM sprestaurant_orderpayment_insert(f, v_o1, 'Cash', 200, 0, NULL, 'probe');
        RAISE EXCEPTION 'FAIL 2: overpayment accepted';
    EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
    v_checks := v_checks + 1;

    -- 3. completing an unpaid order refused
    BEGIN
        PERFORM sprestaurant_order_update_status(v_o1, f, 'Completed', NULL);
        RAISE EXCEPTION 'FAIL 3: unpaid order completed';
    EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
    v_checks := v_checks + 1;

    -- 4. defaults created on list; a till; a shift with a float from the cash box
    PERFORM * FROM sprestaurant_cashaccount_list(f);
    SELECT cashaccountid INTO v_cash FROM restaurantcashaccounts WHERE farmid = f AND defaultfor = 'Cash';
    SELECT cashaccountid INTO v_bank FROM restaurantcashaccounts WHERE farmid = f AND defaultfor = 'Bank';
    SELECT cashaccountid INTO v_momo FROM restaurantcashaccounts WHERE farmid = f AND defaultfor = 'MobileMoney';
    IF v_cash IS NULL OR v_bank IS NULL OR v_momo IS NULL THEN RAISE EXCEPTION 'FAIL 4: defaults missing'; END IF;
    v_till := sprestaurant_cashaccount_create(f, 'Front Till', 'Till', 0, FALSE, NULL, NULL, 'probe');
    v_shift := sprestaurant_cashshift_open(f, v_till, 50, v_cash, 'probe', NULL);
    SELECT currentbalance INTO v_n FROM restaurantcashaccounts WHERE cashaccountid = v_till;
    IF v_n <> 50 THEN RAISE EXCEPTION 'FAIL 4b: till after float %', v_n; END IF;
    BEGIN
        PERFORM sprestaurant_cashshift_open(f, v_till, 0, NULL, 'probe', NULL);
        RAISE EXCEPTION 'FAIL 4c: second open shift allowed';
    EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
    v_checks := v_checks + 3;

    -- 5. cash (with tip) lands in the open till, card in the bank; order settles
    PERFORM sprestaurant_orderpayment_insert(f, v_o1, 'Cash', 100, 5, NULL, 'probe');
    SELECT paymentstatus INTO v_txt FROM restaurantorders WHERE orderid = v_o1;
    IF v_txt <> 'Partial' THEN RAISE EXCEPTION 'FAIL 5: status % after part payment', v_txt; END IF;
    PERFORM sprestaurant_orderpayment_insert(f, v_o1, 'Card', 15, 0, 'visa', 'probe');
    SELECT paymentstatus, paidamount INTO v_txt, v_n FROM restaurantorders WHERE orderid = v_o1;
    IF v_txt <> 'Paid' OR v_n <> 115 THEN RAISE EXCEPTION 'FAIL 5b: % / %', v_txt, v_n; END IF;
    SELECT currentbalance INTO v_n FROM restaurantcashaccounts WHERE cashaccountid = v_till;
    IF v_n <> 155 THEN RAISE EXCEPTION 'FAIL 5c: till %', v_n; END IF;
    SELECT currentbalance INTO v_n FROM restaurantcashaccounts WHERE cashaccountid = v_bank;
    IF v_n <> 15 THEN RAISE EXCEPTION 'FAIL 5d: bank %', v_n; END IF;
    v_checks := v_checks + 4;

    -- 6. complete; recipe deduction is per ingredient and runs once
    PERFORM sprestaurant_order_update_status(v_o1, f, 'Completed', NULL);
    PERFORM sprestaurant_recipe_deduct_order(v_o1, f);
    PERFORM sprestaurant_recipe_deduct_order(v_o1, f);
    SELECT currentstock INTO v_n FROM restaurantingredients WHERE ingredientid = v_ia;
    SELECT currentstock INTO v_n2 FROM restaurantingredients WHERE ingredientid = v_ib;
    IF v_n <> 8 OR v_n2 <> 7 THEN RAISE EXCEPTION 'FAIL 6: stock rice % oil % (want 8, 7)', v_n, v_n2; END IF;
    v_checks := v_checks + 1;

    -- 7. partial cash refund leaves the till; order stays Completed / Paid
    PERFORM sprestaurant_orderpayment_refund(f, v_o1, 20, 'Cash', 'Cold food', 'probe');
    SELECT status, paymentstatus, paidamount INTO v_txt, v_txt2, v_n FROM restaurantorders WHERE orderid = v_o1;
    IF v_txt <> 'Completed' OR v_txt2 <> 'Paid' OR v_n <> 95 THEN
        RAISE EXCEPTION 'FAIL 7: after refund % / % / %', v_txt, v_txt2, v_n; END IF;
    SELECT currentbalance INTO v_n FROM restaurantcashaccounts WHERE cashaccountid = v_till;
    IF v_n <> 135 THEN RAISE EXCEPTION 'FAIL 7b: till after refund %', v_n; END IF;
    v_checks := v_checks + 2;

    -- 8. cancelling an order with money on it refused; full refund marks Refunded
    PERFORM sprestaurant_orderpayment_insert(f, v_o2, 'MobileMoney', 110, 0, NULL, 'probe');
    BEGIN
        PERFORM sprestaurant_order_update_status(v_o2, f, 'Cancelled', 'x');
        RAISE EXCEPTION 'FAIL 8: cancelled a paid order';
    EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
    PERFORM sprestaurant_orderpayment_refund(f, v_o2, 110, 'MobileMoney', 'Wrong order', 'probe');
    SELECT status, paymentstatus INTO v_txt, v_txt2 FROM restaurantorders WHERE orderid = v_o2;
    IF v_txt <> 'Refunded' OR v_txt2 <> 'Refunded' THEN RAISE EXCEPTION 'FAIL 8b: % / %', v_txt, v_txt2; END IF;
    SELECT currentbalance INTO v_n FROM restaurantcashaccounts WHERE cashaccountid = v_momo;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 8c: momo %', v_n; END IF;
    v_checks := v_checks + 3;

    -- 9. expense: category name filled from id, posts out; delete puts it back
    v_exp := sprestaurant_expense_record(f, CURRENT_DATE, v_cat, NULL, 'Power bill', 30, 'Cash', NULL, NULL, 'probe', NULL);
    SELECT categoryname INTO v_txt FROM restaurantexpenses WHERE expenseid = v_exp;
    IF v_txt IS DISTINCT FROM 'Utilities' THEN RAISE EXCEPTION 'FAIL 9: category %', v_txt; END IF;
    SELECT currentbalance INTO v_n FROM restaurantcashaccounts WHERE cashaccountid = v_cash;
    IF v_n <> -80 THEN RAISE EXCEPTION 'FAIL 9b: cash box % (want -50 float -30)', v_n; END IF;
    PERFORM sprestaurant_expense_delete(v_exp, f);
    SELECT currentbalance INTO v_n FROM restaurantcashaccounts WHERE cashaccountid = v_cash;
    IF v_n <> -50 THEN RAISE EXCEPTION 'FAIL 9c: cash box after delete %', v_n; END IF;
    v_exp := sprestaurant_expense_record(f, CURRENT_DATE, v_cat, NULL, 'Gas', 12, 'Card', NULL, NULL, 'probe', NULL);
    v_checks := v_checks + 3;

    -- 10. transfer + reversal; overdraft refused on a strict account
    v_trf := sprestaurant_cashtransfer_create(f, v_bank, v_cash, 3, CURRENT_DATE, NULL, NULL, 'probe');
    PERFORM sprestaurant_cashtransfer_reverse(f, v_trf, 'test', 'probe');
    SELECT currentbalance INTO v_n FROM restaurantcashaccounts WHERE cashaccountid = v_bank;
    IF v_n <> 3 THEN RAISE EXCEPTION 'FAIL 10: bank % (want 15-12)', v_n; END IF;
    BEGIN
        PERFORM sprestaurant_cashtransfer_create(f, v_till, v_cash, 1000, CURRENT_DATE, NULL, NULL, 'probe');
        RAISE EXCEPTION 'FAIL 10b: overdrew the till';
    EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
    v_checks := v_checks + 2;

    -- 11. owner money
    v_own := sprestaurant_ownermoney_record(f, 'Contribution', v_bank, 500, CURRENT_DATE, 'Owner', NULL, 'probe');
    v_own := sprestaurant_ownermoney_record(f, 'Draw', v_bank, 100, CURRENT_DATE, 'Owner', NULL, 'probe');
    PERFORM sprestaurant_ownermoney_reverse(f, v_own, 'test', 'probe');
    SELECT currentbalance INTO v_n FROM restaurantcashaccounts WHERE cashaccountid = v_bank;
    IF v_n <> 503 THEN RAISE EXCEPTION 'FAIL 11: bank %', v_n; END IF;
    v_checks := v_checks + 1;

    -- 12. loans: receive less than principal, repay, reverse, cancel
    v_loan := sprestaurant_loan_create(f, 'Bank X', 1000, 950, v_bank, CURRENT_DATE, 12, NULL, NULL, 'probe');
    v_lp := sprestaurant_loan_repay(f, v_loan, v_bank, 200, 20, 5, CURRENT_DATE, NULL, 'probe');
    SELECT outstandingprincipal INTO v_n FROM restaurantloans WHERE loanid = v_loan;
    IF v_n <> 800 THEN RAISE EXCEPTION 'FAIL 12: outstanding %', v_n; END IF;
    BEGIN
        PERFORM sprestaurant_loan_repay(f, v_loan, v_bank, 900, 0, 0, CURRENT_DATE, NULL, 'probe');
        RAISE EXCEPTION 'FAIL 12b: over-repaid principal';
    EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
    -- P&L sees the interest and fees before the reversal
    SELECT SUM(l.amount) INTO v_n FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) l
     WHERE l.linekey IN ('loan_interest', 'loan_fees');
    IF v_n <> -25 THEN RAISE EXCEPTION 'FAIL 12c: loan cost on P&L %', v_n; END IF;
    PERFORM sprestaurant_loan_payment_reverse(f, v_lp, 'test', 'probe');
    PERFORM sprestaurant_loan_cancel(f, v_loan, 'test', 'probe');
    SELECT currentbalance INTO v_n FROM restaurantcashaccounts WHERE cashaccountid = v_bank;
    IF v_n <> 503 THEN RAISE EXCEPTION 'FAIL 12d: bank after loan round trip %', v_n; END IF;
    v_checks := v_checks + 4;

    -- 13. gift card: sale is cash in; pays an order; redeem-against-order settles it
    SELECT g.cardnumber INTO v_gc FROM sprestaurant_giftcard_create(f, 'Digital', 60, 'A', NULL, NULL, NULL, NULL, NULL, 'Cash', NULL, 'probe') g;
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, status) VALUES (f, 'P323-3', 'Takeaway', 'Placed') RETURNING orderid INTO v_o3;
    INSERT INTO restaurantorderitems (farmid, orderid, menuitemid, itemname, quantity, unitprice, linetotal, status)
    VALUES (f, v_o3, v_mi, 'Jollof', 1, 50, 50, 'Pending');
    PERFORM sprestaurant_order_recalc(v_o3, f);   -- 55 with 10% tax
    PERFORM sprestaurant_orderpayment_insert(f, v_o3, 'GiftCard', 40, 0, lower(v_gc), 'probe');
    SELECT success INTO v_i FROM (SELECT (r.success)::int AS success FROM sprestaurant_giftcard_redeem(v_gc, f, 15, v_o3, 'probe') r) z;
    SELECT paymentstatus INTO v_txt FROM restaurantorders WHERE orderid = v_o3;
    IF v_i <> 1 OR v_txt <> 'Paid' THEN RAISE EXCEPTION 'FAIL 13: redeem-on-order % status %', v_i, v_txt; END IF;
    SELECT currentbalance INTO v_n FROM restaurantgiftcards WHERE cardnumber = v_gc;
    IF v_n <> 5 THEN RAISE EXCEPTION 'FAIL 13b: card balance %', v_n; END IF;
    UPDATE restaurantgiftcards SET expirydate = CURRENT_DATE - 1 WHERE cardnumber = v_gc;
    SELECT r.message INTO v_txt FROM sprestaurant_giftcard_redeem(v_gc, f, 1, NULL, 'probe') r;
    IF v_txt NOT LIKE 'Card expired%' THEN RAISE EXCEPTION 'FAIL 13c: expiry not enforced: %', v_txt; END IF;
    IF EXISTS (SELECT 1 FROM sprestaurant_giftcard_balance(v_gc, 'someone-else')) THEN
        RAISE EXCEPTION 'FAIL 13d: balance visible to another tenant'; END IF;
    v_checks := v_checks + 4;

    -- 14. close the shift: expected 135 + 60 (gift sale while the till was the only open one), count 190 -> -5
    SELECT currentbalance INTO v_n FROM restaurantcashaccounts WHERE cashaccountid = v_till;
    SELECT z.variance INTO v_n2 FROM sprestaurant_cashshift_close(f, v_shift, v_n - 5, 100, v_cash, 'probe', NULL) z;
    IF v_n2 <> -5 THEN RAISE EXCEPTION 'FAIL 14: variance %', v_n2; END IF;
    SELECT currentbalance INTO v_n2 FROM restaurantcashaccounts WHERE cashaccountid = v_till;
    IF v_n2 <> v_n - 105 THEN RAISE EXCEPTION 'FAIL 14b: till after drop % (want %)', v_n2, v_n - 105; END IF;
    PERFORM * FROM sprestaurant_cashshift_zreport(f, v_shift);
    PERFORM * FROM sprestaurant_cashshift_list(f, NULL, NULL, NULL);
    v_checks := v_checks + 2;

    -- 15. count on the bank: 1 over
    SELECT currentbalance INTO v_n FROM restaurantcashaccounts WHERE cashaccountid = v_bank;
    v_cnt := sprestaurant_cashcount_post(f, v_bank, v_n + 1, NULL, 'probe');
    SELECT difference INTO v_n2 FROM restaurantcashcounts WHERE countid = v_cnt;
    IF v_n2 <> 1 THEN RAISE EXCEPTION 'FAIL 15: count difference %', v_n2; END IF;
    v_checks := v_checks + 1;

    -- 16. every cached balance equals its ledger
    IF EXISTS (SELECT 1 FROM restaurantcashaccounts a
                WHERE a.farmid = f
                  AND a.currentbalance <> COALESCE((SELECT SUM(t.amount) FROM restaurantcashtransactions t
                                                     WHERE t.cashaccountid = a.cashaccountid), 0)) THEN
        RAISE EXCEPTION 'FAIL 16: a cached balance drifted from its ledger'; END IF;
    v_checks := v_checks + 1;

    -- 17. Cash Flow cash-at-hand equals the sum of account balances
    SELECT s.cashathand INTO v_n FROM sprestaurantcashflow_summary(f, NULL, NULL) s;
    SELECT SUM(a.currentbalance) INTO v_n2 FROM restaurantcashaccounts a WHERE a.farmid = f;
    IF v_n <> v_n2 THEN RAISE EXCEPTION 'FAIL 17: cash flow % vs accounts %', v_n, v_n2; END IF;
    SELECT s.cashathand INTO v_n FROM sprestaurantcashflow_summary(f, CURRENT_DATE::timestamp, (CURRENT_DATE + 1)::timestamp - interval '1 microsecond') s;
    IF v_n <> v_n2 THEN RAISE EXCEPTION 'FAIL 17b: dated cash flow % vs accounts %', v_n, v_n2; END IF;
    PERFORM * FROM sprestaurantcashflow_detail(f, NULL, NULL);
    v_checks := v_checks + 2;

    -- 18. P&L: revenue = (100 + 5 sc) + 50 - 20 refund; order 2 refunded drops out
    SELECT s.revenue INTO v_n FROM sprestaurant_report_pnl_summary(f, CURRENT_DATE, CURRENT_DATE) s;
    -- order 3 is not Completed yet, so only order 1: 100 + 5 - 20 = 85
    IF v_n <> 85 THEN RAISE EXCEPTION 'FAIL 18: revenue %', v_n; END IF;
    PERFORM * FROM sprestaurant_report_pnl_expenses(f, CURRENT_DATE, CURRENT_DATE);
    v_checks := v_checks + 1;

    -- 19. daily closing locks the day; reopen unlocks
    PERFORM sprestaurant_order_update_status(v_o3, f, 'Completed', NULL);
    PERFORM * FROM sprestaurant_dailyclosing_preview(f, CURRENT_DATE);
    PERFORM sprestaurant_dailyclosing_close(f, CURRENT_DATE, NULL, 'probe');
    BEGIN
        PERFORM sprestaurant_expense_record(f, CURRENT_DATE, NULL, NULL, 'Late', 1, 'Cash', NULL, NULL, 'probe', NULL);
        RAISE EXCEPTION 'FAIL 19: wrote into a closed day';
    EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
    PERFORM sprestaurant_dailyclosing_reopen(f, CURRENT_DATE, 'forgot one', 'probe');
    PERFORM sprestaurant_expense_record(f, CURRENT_DATE, NULL, NULL, 'Late', 1, 'Cash', NULL, NULL, 'probe', NULL);
    PERFORM * FROM sprestaurant_dailyclosing_list(f, 10);
    v_checks := v_checks + 2;

    -- 20. an open shift blocks closing the day
    v_shift := sprestaurant_cashshift_open(f, v_till, 0, NULL, 'probe', NULL);
    BEGIN
        PERFORM sprestaurant_dailyclosing_close(f, CURRENT_DATE, NULL, 'probe');
        RAISE EXCEPTION 'FAIL 20: closed the day with a shift open';
    EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
    v_checks := v_checks + 1;

    -- 21. the list functions all execute
    PERFORM * FROM sprestaurant_cashaccount_ledger(f, v_bank, NULL, NULL);
    PERFORM * FROM sprestaurant_cashtransfer_list(f, NULL, NULL);
    PERFORM * FROM sprestaurant_ownermoney_list(f, NULL, NULL);
    PERFORM * FROM sprestaurant_loan_list(f);
    PERFORM * FROM sprestaurant_loan_payments(f, v_loan);
    PERFORM * FROM sprestaurant_cashcount_list(f, NULL);
    PERFORM * FROM sprestaurant_giftcard_stats(f);
    v_checks := v_checks + 1;

    RAISE EXCEPTION 'SELFTEST PASSED: % checks; backfill posted % ledger rows (rolled back)', v_checks, v_backfill;
END $$;
