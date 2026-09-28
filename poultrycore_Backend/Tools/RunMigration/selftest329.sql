-- Self-test for migration 329 (Restaurant suppliers, purchases, payables,
-- supplier payments, deferred inventory cost). Run on its own after 329; it
-- always ends by raising so everything rolls back. "SELFTEST PASSED" in the
-- error is the success signal; anything else names the failing check.
--
-- The story: tomatoes are "expense when consumed", takeaway boxes "expense when
-- purchased". Two tomato deliveries from Fresh Farms (one part-paid, one on
-- credit), a box delivery paid in full, three plates of jollof sold, tomatoes
-- wasted and adjusted out, two expenses owed to Fresh Farms, a chiller bought
-- from Pack It with 300 still owed. Fresh Farms is paid 100 across three
-- documents (then the payment is reversed), Pack It is paid for the chiller.
-- Every guard, the ledger, balances, FIFO lots, the P&L lines, cash flow, the
-- supplier balances / statement contract, the deferred page and the
-- profit-vs-cash bridge are checked.
DO $$
DECLARE
    f TEXT := '__probe329__';
    v_cash INT; v_fresh INT; v_pack INT; v_tom INT; v_box INT; v_rice INT; v_mi INT; v_o INT;
    v_p1 INT; v_p2 INT; v_p3 INT; v_e1 INT; v_e2 INT; v_asset INT; v_acost INT; v_pay INT; v_pay2 INT;
    v_n NUMERIC; v_n2 NUMERIC; v_i INT; v_txt TEXT; v_failed BOOLEAN; v_checks INT := 0; r RECORD;
BEGIN
    PERFORM * FROM sprestaurant_cashaccount_list(f);
    SELECT cashaccountid INTO v_cash FROM restaurantcashaccounts WHERE farmid = f AND defaultfor = 'Cash';
    v_fresh := sprestaurant_supplier_insert(f, 'Fresh Farms', NULL, '0244000000', 'fresh@x.test', 'Market St', 'Vegetables', NULL);
    v_pack  := sprestaurant_supplier_insert(f, 'Pack It', NULL, '0244000001', NULL, 'Ring Rd', 'Packaging', NULL);
    INSERT INTO restaurantingredients (farmid, name, category, unit, costperunit, currentstock)
    VALUES (f, 'Tomatoes', 'Produce', 'kg', 0, 0) RETURNING ingredientid INTO v_tom;
    INSERT INTO restaurantingredients (farmid, name, category, unit, costperunit, currentstock)
    VALUES (f, 'Takeaway boxes', 'Packaging', 'pcs', 0, 0) RETURNING ingredientid INTO v_box;
    INSERT INTO restaurantingredients (farmid, name, category, unit, costperunit, currentstock)
    VALUES (f, 'Rice', 'Dry Goods', 'kg', 4, 10) RETURNING ingredientid INTO v_rice;
    INSERT INTO restaurantmenuitems (farmid, name, price) VALUES (f, 'Jollof', 100) RETURNING menuitemid INTO v_mi;
    INSERT INTO restaurantrecipes (farmid, menuitemid, ingredientid, quantity, unit, wastepercent) VALUES (f, v_mi, v_tom, 2, 'kg', 0);
    INSERT INTO restaurantrecipes (farmid, menuitemid, ingredientid, quantity, unit, wastepercent) VALUES (f, v_mi, v_rice, 1, 'kg', 0);

    -- 1. cost recognition per category; default is expense when purchased
    PERFORM sprestaurant_costmode_set(f, 'produce', 'EXPENSE_WHEN_CONSUMED', 'probe');
    IF fnrestaurant_costmode(f, 'Produce') <> 'EXPENSE_WHEN_CONSUMED' THEN RAISE EXCEPTION 'FAIL 1: produce mode'; END IF;
    IF fnrestaurant_costmode(f, 'Packaging') <> 'EXPENSE_WHEN_PURCHASED' THEN RAISE EXCEPTION 'FAIL 1b: default mode'; END IF;
    SELECT COUNT(*) INTO v_i FROM sprestaurant_costmode_list(f);
    IF v_i <> 3 THEN RAISE EXCEPTION 'FAIL 1c: % categories listed (want 3)', v_i; END IF;
    v_checks := v_checks + 3;

    -- 2. purchase guards
    v_failed := FALSE; BEGIN PERFORM sprestaurant_purchase_create(f, v_tom, 5, 50, CURRENT_DATE, NULL, NULL, 'Cash', 10);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'Choose the supplier%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2: unpaid purchase with no supplier accepted'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_purchase_create(f, v_tom, 5, 50, CURRENT_DATE + 1, v_fresh);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE '%future%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2b: future purchase accepted'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_purchase_create(f, v_tom, 5, 50, CURRENT_DATE, v_fresh, NULL, 'Cash', 60);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'Amount paid now%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2c: overpaid purchase accepted'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_purchase_create('__other329__', v_tom, 5, 50, CURRENT_DATE);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2d: another company''s ingredient accepted'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_ingredient_adjust_stock(v_tom, f, 5, 'PurchaseIn', 'x', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'Record a delivery%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2e: Adjust Stock still accepts a purchase'; END IF;
    v_checks := v_checks + 5;

    -- 3. tomatoes: 10 kg for 100, 40 paid now; then 10 kg for 150 on credit
    v_p1 := sprestaurant_purchase_create(f, v_tom, 10, 100, CURRENT_DATE, v_fresh, NULL, 'Cash', 40, v_cash, CURRENT_DATE + 7, NULL, 'probe');
    SELECT currentstock, costperunit INTO v_n, v_n2 FROM restaurantingredients WHERE ingredientid = v_tom;
    IF v_n <> 10 OR v_n2 <> 10 THEN RAISE EXCEPTION 'FAIL 3: stock % cost % (want 10, 10)', v_n, v_n2; END IF;
    SELECT costmode, deferredtotalcost, deferredremainingcost INTO v_txt, v_n, v_n2
      FROM restaurantpurchases WHERE purchaseid = v_p1;
    IF v_txt <> 'EXPENSE_WHEN_CONSUMED' OR v_n <> 100 OR v_n2 <> 100 THEN RAISE EXCEPTION 'FAIL 3b: lot % % %', v_txt, v_n, v_n2; END IF;
    SELECT amount INTO v_n FROM restaurantcashtransactions WHERE sourcetype = 'StockPurchase' AND sourceid = v_p1;
    IF v_n <> -40 THEN RAISE EXCEPTION 'FAIL 3c: ledger % (want -40)', v_n; END IF;
    v_p2 := sprestaurant_purchase_create(f, v_tom, 10, 150, CURRENT_DATE, NULL, 'fresh farms', 'Credit', NULL, NULL, NULL, NULL, 'probe');
    SELECT supplierid, amountpaid INTO v_i, v_n FROM restaurantpurchases WHERE purchaseid = v_p2;
    IF v_i IS DISTINCT FROM v_fresh OR v_n <> 0 THEN RAISE EXCEPTION 'FAIL 3d: typed supplier % paid %', v_i, v_n; END IF;
    IF EXISTS (SELECT 1 FROM restaurantcashtransactions WHERE sourcetype = 'StockPurchase' AND sourceid = v_p2) THEN
        RAISE EXCEPTION 'FAIL 3e: credit purchase moved cash'; END IF;
    SELECT costperunit INTO v_n FROM restaurantingredients WHERE ingredientid = v_tom;
    IF v_n <> 12.5 THEN RAISE EXCEPTION 'FAIL 3f: blended cost % (want 12.5)', v_n; END IF;
    v_checks := v_checks + 6;

    -- 4. boxes: expense when purchased, paid in full
    v_p3 := sprestaurant_purchase_create(f, v_box, 100, 50, CURRENT_DATE, v_pack, NULL, 'Cash', NULL, v_cash, NULL, NULL, 'probe');
    SELECT deferredtotalcost, amountpaid INTO v_n, v_n2 FROM restaurantpurchases WHERE purchaseid = v_p3;
    IF v_n <> 0 OR v_n2 <> 50 THEN RAISE EXCEPTION 'FAIL 4: boxes deferred % paid %', v_n, v_n2; END IF;
    IF (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'stock_purchased') <> -50 THEN
        RAISE EXCEPTION 'FAIL 4b: stock_purchased line'; END IF;
    v_checks := v_checks + 2;

    -- 5. three jollof: 6 kg tomatoes FIFO from lot 1 (60 of deferred cost), rice
    --    is legacy stock (no purchase) and moves no cost
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, status) VALUES (f, 'P329-1', 'Takeaway', 'Placed') RETURNING orderid INTO v_o;
    INSERT INTO restaurantorderitems (farmid, orderid, menuitemid, itemname, quantity, unitprice, linetotal, status)
    VALUES (f, v_o, v_mi, 'Jollof', 3, 100, 300, 'Pending');
    PERFORM sprestaurant_recipe_deduct_order(v_o, f);
    PERFORM sprestaurant_recipe_deduct_order(v_o, f);
    SELECT remainingquantity, deferredremainingcost INTO v_n, v_n2 FROM restaurantpurchases WHERE purchaseid = v_p1;
    IF v_n <> 4 OR v_n2 <> 40 THEN RAISE EXCEPTION 'FAIL 5: lot 1 after sale % / %', v_n, v_n2; END IF;
    SELECT currentstock INTO v_n FROM restaurantingredients WHERE ingredientid = v_rice;
    IF v_n <> 7 THEN RAISE EXCEPTION 'FAIL 5b: rice % (want 7)', v_n; END IF;
    IF (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'recipe_cost') <> -60 THEN
        RAISE EXCEPTION 'FAIL 5c: recipe cost line (want -60: tomatoes only, rice has no purchase behind it)'; END IF;
    v_checks := v_checks + 3;

    -- 6. waste 5 kg: 4 from lot 1 (40) + 1 from lot 2 (15)
    PERFORM sprestaurant_wastelog_insert(f, v_tom, NULL, 'Tomatoes', 5, 'kg', 0, 'Spoilage', NULL, 'probe');
    SELECT remainingquantity, deferredremainingcost INTO v_n, v_n2 FROM restaurantpurchases WHERE purchaseid = v_p1;
    IF v_n <> 0 OR v_n2 <> 0 THEN RAISE EXCEPTION 'FAIL 6: lot 1 after waste % / %', v_n, v_n2; END IF;
    IF (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'stock_waste') <> -55 THEN
        RAISE EXCEPTION 'FAIL 6b: stock_waste line'; END IF;
    v_checks := v_checks + 2;

    -- 7. adjustment out typed as +1 now LOWERS stock and draws 15
    PERFORM sprestaurant_ingredient_adjust_stock(v_tom, f, 1, 'AdjustmentOut', 'Dropped crate', 'probe');
    SELECT currentstock INTO v_n FROM restaurantingredients WHERE ingredientid = v_tom;
    IF v_n <> 8 THEN RAISE EXCEPTION 'FAIL 7: tomatoes % (want 20-6-5-1 = 8)', v_n; END IF;
    IF (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'stock_adjustments') <> -15 THEN
        RAISE EXCEPTION 'FAIL 7b: stock_adjustments line'; END IF;
    -- stock and lots agree: 8 kg on hand, 8 kg in lot 2
    IF (SELECT remainingquantity FROM restaurantpurchases WHERE purchaseid = v_p2) <> 8 THEN RAISE EXCEPTION 'FAIL 7c: lot 2 qty'; END IF;
    v_checks := v_checks + 3;

    -- 8. expenses owed to Fresh Farms: gas 30 unpaid, charcoal 20 with 5 paid
    v_e1 := sprestaurant_expense_record(f, CURRENT_DATE, NULL, 'Utilities', 'Gas refill', 30, 'Cash', NULL, NULL, 'probe', NULL, v_fresh, 0, CURRENT_DATE + 3);
    v_e2 := sprestaurant_expense_record(f, CURRENT_DATE, NULL, 'Utilities', 'Charcoal', 20, 'Cash', NULL, NULL, 'probe', v_cash, v_fresh, 5, NULL);
    IF EXISTS (SELECT 1 FROM restaurantcashtransactions WHERE sourcetype = 'Expense' AND sourceid = v_e1) THEN
        RAISE EXCEPTION 'FAIL 8: unpaid expense moved cash'; END IF;
    IF (SELECT amount FROM restaurantcashtransactions WHERE sourcetype = 'Expense' AND sourceid = v_e2) <> -5 THEN
        RAISE EXCEPTION 'FAIL 8b: part-paid expense ledger'; END IF;
    IF (SELECT suppliername FROM restaurantexpenses WHERE expenseid = v_e1) IS DISTINCT FROM 'Fresh Farms' THEN
        RAISE EXCEPTION 'FAIL 8c: supplier name not filled from the id'; END IF;
    SELECT paymentstatus, balance INTO v_txt, v_n FROM sprestaurant_expense_payments(f) WHERE expenseid = v_e2;
    IF v_txt <> 'PartiallyPaid' OR v_n <> 15 THEN RAISE EXCEPTION 'FAIL 8d: % %', v_txt, v_n; END IF;
    -- the old 11-argument call still works and means paid in full
    PERFORM sprestaurant_expense_record(f, CURRENT_DATE, NULL, 'Utilities', 'Water', 7, 'Cash', NULL, NULL, 'probe', NULL);
    v_checks := v_checks + 5;

    -- 9. a chiller from Pack It: 500, 200 paid, 300 owed (the 328 seam)
    v_asset := sprestaurant_capitalasset_create(p_farmid => f, p_assetname => 'Walk-in chiller', p_amount => 500,
                   p_supplierid => v_pack, p_paymentmethod => 'Cash', p_amountpaid => 200, p_cashaccountid => v_cash,
                   p_createdby => 'probe');
    SELECT assetcostid INTO v_acost FROM restaurantcapitalassetcosts WHERE capitalassetid = v_asset;
    v_checks := v_checks + 1;

    -- 10. balances: Fresh Farms 60 + 150 + 30 + 15 = 255; Pack It 300
    SELECT totalbalance, openpurchasecount INTO v_n, v_i FROM sprestaurant_supplierbalances(f) WHERE supplierid = v_fresh;
    IF v_n <> 255 OR v_i <> 4 THEN RAISE EXCEPTION 'FAIL 10: Fresh Farms % over % docs', v_n, v_i; END IF;
    SELECT totalbalance INTO v_n FROM sprestaurant_supplierbalances(f) WHERE supplierid = v_pack;
    IF v_n <> 300 THEN RAISE EXCEPTION 'FAIL 10b: Pack It %', v_n; END IF;
    SELECT totalbalance, suppliersowed, largestbalancesupplier INTO v_n, v_i, v_txt FROM sprestaurant_supplierbalancesummary(f);
    IF v_n <> 555 OR v_i <> 2 OR v_txt <> 'Pack It' THEN RAISE EXCEPTION 'FAIL 10c: summary % % %', v_n, v_i, v_txt; END IF;
    SELECT COUNT(*) INTO v_i FROM sprestaurant_supplieropenpurchases(f, v_fresh);
    IF v_i <> 4 THEN RAISE EXCEPTION 'FAIL 10d: % open documents', v_i; END IF;
    SELECT COUNT(*) INTO v_i FROM sprestaurant_supplierbalances(f, p_status => 'Unpaid');
    IF v_i <> 1 THEN RAISE EXCEPTION 'FAIL 10e: % suppliers with an unpaid document', v_i; END IF;
    v_checks := v_checks + 5;

    -- 11. payment guards
    v_failed := FALSE; BEGIN PERFORM sprestaurant_supplierpayment_record(f, v_fresh, 100,
        jsonb_build_array(jsonb_build_object('documenttype', 'Purchase', 'documentid', v_p1, 'amount', 60)), 'Cash', NOW()::TIMESTAMP, v_cash);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'Allocated total%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 11: allocations short of the payment accepted'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_supplierpayment_record(f, v_fresh, 70,
        jsonb_build_array(jsonb_build_object('documenttype', 'Purchase', 'documentid', v_p1, 'amount', 70)), 'Cash', NOW()::TIMESTAMP, v_cash);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'Cannot apply%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 11b: over-applied a document'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_supplierpayment_record(f, v_fresh, 50,
        jsonb_build_array(jsonb_build_object('documenttype', 'AssetCost', 'documentid', v_acost, 'amount', 50)), 'Cash', NOW()::TIMESTAMP, v_cash);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE '%do not belong to this supplier%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 11c: paid another supplier''s document'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_supplierpayment_record(f, v_fresh, 20,
        jsonb_build_array(jsonb_build_object('documenttype', 'Expense', 'documentid', v_e1, 'amount', 10),
                          jsonb_build_object('documenttype', 'Expense', 'documentid', v_e1, 'amount', 10)), 'Cash', NOW()::TIMESTAMP, v_cash);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'The same item%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 11d: duplicate allocation accepted'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_supplierpayment_record(f, v_fresh, 10,
        jsonb_build_array(jsonb_build_object('documenttype', 'Expense', 'documentid', v_e1, 'amount', 10)), 'Cash', NOW()::TIMESTAMP, NULL);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'Choose the cash account%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 11e: payment without an account accepted'; END IF;
    v_checks := v_checks + 5;

    -- 12. Fresh Farms paid 100: lot 1 60, gas 30, charcoal 10 -> ONE cash-out
    SELECT currentbalance INTO v_n2 FROM restaurantcashaccounts WHERE cashaccountid = v_cash;
    v_pay := sprestaurant_supplierpayment_record(f, v_fresh, 100,
        jsonb_build_array(jsonb_build_object('documenttype', 'Purchase', 'documentid', v_p1, 'amount', 60),
                          jsonb_build_object('documenttype', 'Expense', 'documentid', v_e1, 'amount', 30),
                          jsonb_build_object('documenttype', 'Expense', 'documentid', v_e2, 'amount', 10)),
        'Cash', NOW()::TIMESTAMP, v_cash, 'RCPT-9', NULL, 'SupplierBalances', 'probe');
    SELECT COUNT(*), SUM(amount) INTO v_i, v_n FROM restaurantcashtransactions WHERE sourcetype = 'SupplierPayment' AND sourceid = v_pay;
    IF v_i <> 1 OR v_n <> -100 THEN RAISE EXCEPTION 'FAIL 12: ledger % rows %', v_i, v_n; END IF;
    SELECT currentbalance INTO v_n FROM restaurantcashaccounts WHERE cashaccountid = v_cash;
    IF v_n <> v_n2 - 100 THEN RAISE EXCEPTION 'FAIL 12b: cash box moved %', v_n - v_n2; END IF;
    SELECT COUNT(*), SUM(amountapplied) INTO v_i, v_n FROM supplierpaymentallocation
     WHERE farmid = f AND module = 'restaurant' AND paymentid = v_pay AND status = 'Posted';
    IF v_i <> 3 OR v_n <> 100 THEN RAISE EXCEPTION 'FAIL 12c: allocations % / %', v_i, v_n; END IF;
    SELECT totalbalance INTO v_n FROM sprestaurant_supplierbalances(f) WHERE supplierid = v_fresh;
    IF v_n <> 155 THEN RAISE EXCEPTION 'FAIL 12d: Fresh Farms after payment % (want 155)', v_n; END IF;
    -- the documents' own paid-at-entry is untouched (no cash counted twice)
    IF (SELECT amountpaid FROM restaurantpurchases WHERE purchaseid = v_p1) <> 40 THEN RAISE EXCEPTION 'FAIL 12e: purchase amountpaid rewritten'; END IF;
    SELECT paymentstatus, balance INTO v_txt, v_n FROM sprestaurant_purchase_list(f, p_purchaseid => v_p1);
    IF v_txt <> 'Paid' OR v_n <> 0 THEN RAISE EXCEPTION 'FAIL 12f: purchase list % %', v_txt, v_n; END IF;
    SELECT allocationcount, totalamount INTO v_i, v_n FROM sprestaurant_supplierpayment_history(f, v_fresh);
    IF v_i <> 3 OR v_n <> 100 THEN RAISE EXCEPTION 'FAIL 12g: history % %', v_i, v_n; END IF;
    SELECT COUNT(*) INTO v_i FROM sprestaurant_supplierpayment_history(f, NULL, 'Expense', v_e1);
    IF v_i <> 1 THEN RAISE EXCEPTION 'FAIL 12h: history by document'; END IF;
    SELECT COUNT(*) INTO v_i FROM sprestaurant_supplierpayment_allocations(f, v_pay) WHERE reference IS NOT NULL;
    IF v_i <> 3 THEN RAISE EXCEPTION 'FAIL 12i: allocation rows %', v_i; END IF;
    v_checks := v_checks + 9;

    -- 13. statement: billed 100+150+30+20 = 300; paid 40 + 5 at entry + 100 -> 155
    SELECT SUM(credit) - SUM(debit) INTO v_n2 FROM sprestaurant_supplierstatement(f, v_fresh);
    IF v_n2 <> 155 THEN RAISE EXCEPTION 'FAIL 13: statement nets to % (want 155)', v_n2; END IF;
    v_checks := v_checks + 1;

    -- 14. guards on documents with a payment against them
    v_failed := FALSE; BEGIN PERFORM sprestaurant_expense_delete(v_e1, f);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'A supplier payment has been recorded%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 14: deleted a paid expense'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_purchase_reverse(f, v_p1, 'oops', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'A supplier payment has been recorded%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 14b: reversed a paid purchase'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_purchase_reverse(f, v_p2, 'oops', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'Stock from this purchase%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 14c: reversed a purchase whose stock was used'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_supplier_delete(v_fresh, f);
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'This supplier is still owed%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 14d: deleted a supplier still owed money'; END IF;
    v_checks := v_checks + 4;

    -- 15. Pack It paid for the chiller; the asset seam follows, the asset is locked
    v_pay2 := sprestaurant_supplierpayment_record(f, v_pack, 300,
        jsonb_build_array(jsonb_build_object('documenttype', 'AssetCost', 'documentid', v_acost, 'amount', 300)),
        'Bank Transfer', NOW()::TIMESTAMP, v_cash, NULL, NULL, 'SupplierBalances', 'probe');
    IF EXISTS (SELECT 1 FROM sprestaurant_capitalasset_payables(f)) THEN RAISE EXCEPTION 'FAIL 15: chiller still payable'; END IF;
    IF (SELECT amountowed FROM sprestaurant_capitalasset_list(f, p_assetid => v_asset)) <> 0 THEN RAISE EXCEPTION 'FAIL 15b: amountowed'; END IF;
    IF (SELECT amountowed FROM sprestaurant_capitalasset_summary(f)) <> 0 THEN RAISE EXCEPTION 'FAIL 15c: summary amountowed'; END IF;
    IF (SELECT paymentstatus FROM sprestaurant_capitalasset_costs(f, v_asset) WHERE assetcostid = v_acost) <> 'Paid' THEN
        RAISE EXCEPTION 'FAIL 15d: cost row status'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_capitalasset_reverse(f, v_asset, 'wrong', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'A supplier payment has been recorded%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 15e: reversed a paid asset'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_capitalasset_correctoriginalcost(f, v_asset, 250, CURRENT_DATE, 'cheaper', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'Supplier payments of %'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 15f: corrected below what suppliers were paid'; END IF;
    v_checks := v_checks + 6;

    -- 16. P&L and the bridge
    IF (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'recipe_cost') <> -60
       OR (SELECT cogs FROM sprestaurant_report_pnl_summary(f, CURRENT_DATE, CURRENT_DATE)) <> 180 THEN
        RAISE EXCEPTION 'FAIL 16: cost of sales (want 60 + 55 + 15 + 50 = 180)'; END IF;
    SELECT amount INTO v_n FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'check';
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 16b: bridge unexplained %', v_n; END IF;
    SELECT amount INTO v_n FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'stock_paid';
    IF v_n <> -150 THEN RAISE EXCEPTION 'FAIL 16c: stock paid % (want 40 + 50 + 60)', v_n; END IF;
    SELECT amount INTO v_n FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'capital_investments';
    IF v_n <> -500 THEN RAISE EXCEPTION 'FAIL 16d: capital investments % (want 200 + 300)', v_n; END IF;
    SELECT COUNT(*) INTO v_i FROM sprestaurantcashflow_detail(f) WHERE category IN ('Stock purchases', 'Supplier payments');
    IF v_i <> 4 THEN RAISE EXCEPTION 'FAIL 16e: % categorised cash-flow rows (want 4)', v_i; END IF;
    IF EXISTS (SELECT 1 FROM sprestaurantcashflow_detail(f) WHERE flowgroup LIKE 'Financing%') THEN
        RAISE EXCEPTION 'FAIL 16f: supplier money classified as financing'; END IF;
    v_checks := v_checks + 6;

    -- 17. reverse the Fresh Farms payment: reason required, cash back, owed again
    v_failed := FALSE; BEGIN PERFORM sprestaurant_supplierpayment_reverse(f, v_pay, NULL, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'A reason is required%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 17: reversal without a reason'; END IF;
    IF sprestaurant_supplierpayment_reverse(f, v_pay, 'Wrong supplier', 'probe') <> 3 THEN RAISE EXCEPTION 'FAIL 17b: count'; END IF;
    IF (SELECT amount FROM restaurantcashtransactions WHERE sourcetype = 'SupplierPaymentReversal' AND sourceid = v_pay) <> 100 THEN
        RAISE EXCEPTION 'FAIL 17c: reversal ledger'; END IF;
    SELECT totalbalance INTO v_n FROM sprestaurant_supplierbalances(f) WHERE supplierid = v_fresh;
    IF v_n <> 255 THEN RAISE EXCEPTION 'FAIL 17d: Fresh Farms after reversal %', v_n; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_supplierpayment_reverse(f, v_pay, 'again', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE '%already been reversed%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 17e: reversed twice'; END IF;
    SELECT amount INTO v_n FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'check';
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 17f: bridge after reversal %', v_n; END IF;
    v_checks := v_checks + 6;

    -- 18. the unused box delivery reverses: cash back, stock out, P&L nets to 0
    PERFORM sprestaurant_purchase_reverse(f, v_p3, 'Delivered to the wrong branch', 'probe');
    IF (SELECT currentstock FROM restaurantingredients WHERE ingredientid = v_box) <> 0 THEN RAISE EXCEPTION 'FAIL 18: box stock'; END IF;
    IF (SELECT amount FROM restaurantcashtransactions WHERE sourcetype = 'StockPurchaseReversal' AND sourceid = v_p3) <> 50 THEN
        RAISE EXCEPTION 'FAIL 18b: refund'; END IF;
    IF EXISTS (SELECT 1 FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'stock_purchased') THEN
        RAISE EXCEPTION 'FAIL 18c: reversed purchase still charged'; END IF;
    SELECT amount INTO v_n FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'check';
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 18d: bridge after purchase reversal %', v_n; END IF;
    v_checks := v_checks + 4;

    -- 19. deferred inventory cost page: lot 2 holds 150 - 15 - 15 = 120
    SELECT remainingdeferredcost, deferredpurchases, recognizedcost INTO v_n, v_i, v_n2 FROM sprestaurant_deferredpurchase_summary(f);
    IF v_n <> 120 OR v_i <> 1 OR v_n2 <> 30 THEN RAISE EXCEPTION 'FAIL 19: deferred summary % % %', v_n, v_i, v_n2; END IF;
    SELECT status INTO v_txt FROM sprestaurant_deferredpurchase_getall(f, 'ALL') WHERE purchaseid = v_p1;
    IF v_txt <> 'Fully expensed' THEN RAISE EXCEPTION 'FAIL 19b: lot 1 status %', v_txt; END IF;
    SELECT COUNT(*), SUM(recognizedcost) INTO v_i, v_n FROM sprestaurant_deferredpurchase_history(f, v_p1);
    IF v_i <> 2 OR v_n <> 100 THEN RAISE EXCEPTION 'FAIL 19c: lot 1 history % rows %', v_i, v_n; END IF;
    IF EXISTS (SELECT 1 FROM sprestaurant_deferredpurchase_getall(f, 'EXCEPTION')) THEN RAISE EXCEPTION 'FAIL 19d: exceptions'; END IF;
    v_checks := v_checks + 4;

    -- 20. ledger = balances for every account of this restaurant
    IF EXISTS (SELECT 1 FROM restaurantcashaccounts a WHERE a.farmid = f
                 AND a.currentbalance <> COALESCE((SELECT SUM(t.amount) FROM restaurantcashtransactions t
                                                    WHERE t.cashaccountid = a.cashaccountid), 0)) THEN
        RAISE EXCEPTION 'FAIL 20: an account balance disagrees with its ledger'; END IF;
    v_checks := v_checks + 1;

    RAISE EXCEPTION 'SELFTEST PASSED: % checks (rolled back)', v_checks;
END $$;
