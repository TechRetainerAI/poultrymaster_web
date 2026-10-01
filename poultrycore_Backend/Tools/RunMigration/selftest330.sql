-- Self-test for migration 330 (Restaurant Internal Use). Run on its own after
-- 330; it always ends by raising so everything rolls back. "SELFTEST PASSED" in
-- the error is the success signal; anything else names the failing check.
--
-- The story: tomatoes are "expense when consumed" (10 kg bought for 100), soda
-- is "expense when purchased" (24 bottles for 48), rice is old stock with no
-- purchase behind it (10 kg). Jollof = 2 kg tomatoes + 1 kg rice (+10% prep
-- waste). Staff eat 3 kg of tomatoes, the owner takes 6 sodas, two plates of
-- jollof go out complimentary; one record is short of stock, one menu item has
-- no recipe; records are reversed, edited, posted again and deleted; a record
-- dated yesterday is posted, reversed today, and then yesterday is closed.
-- Checked: guards, stock, FIFO lots, movements, draws, the P&L line (charged
-- once: deferred stock only), the profit-vs-cash bridge (0), no cash, the
-- deferred history, the picker and the daily-closing lock.
DO $$
DECLARE
    f TEXT := '__probe330__';
    v_cash INT; v_tom INT; v_soda INT; v_rice INT; v_mi INT; v_bare INT; v_other INT;
    v_p1 INT; v_p2 INT; v_iu1 INT; v_iu2 INT; v_iu3 INT; v_iu4 INT; v_iu5 INT; v_iu6 INT;
    v_ledger INT; v_cogs0 NUMERIC; v_n NUMERIC; v_n2 NUMERIC; v_i INT; v_txt TEXT; v_st TEXT; v_failed BOOLEAN;
    v_checks INT := 0; v_y DATE := CURRENT_DATE - 1;
    j_tom3 TEXT; j_soda6 TEXT; j_jol2 TEXT;
BEGIN
    PERFORM * FROM sprestaurant_cashaccount_list(f);
    SELECT cashaccountid INTO v_cash FROM restaurantcashaccounts WHERE farmid = f AND defaultfor = 'Cash';
    PERFORM sprestaurant_costmode_set(f, 'Produce', 'EXPENSE_WHEN_CONSUMED', 'probe');
    INSERT INTO restaurantingredients (farmid, name, category, unit, costperunit, currentstock)
    VALUES (f, 'Tomatoes', 'Produce', 'kg', 0, 0) RETURNING ingredientid INTO v_tom;
    INSERT INTO restaurantingredients (farmid, name, category, unit, costperunit, currentstock)
    VALUES (f, 'Soda', 'Beverages', 'bottle', 0, 0) RETURNING ingredientid INTO v_soda;
    INSERT INTO restaurantingredients (farmid, name, category, unit, costperunit, currentstock)
    VALUES (f, 'Rice', 'Dry Goods', 'kg', 4, 10) RETURNING ingredientid INTO v_rice;
    INSERT INTO restaurantingredients (farmid, name, category, unit, costperunit, currentstock)
    VALUES ('__other330__', 'Their oil', 'Dry Goods', 'L', 1, 50) RETURNING ingredientid INTO v_other;
    INSERT INTO restaurantmenuitems (farmid, name, price) VALUES (f, 'Jollof', 100) RETURNING menuitemid INTO v_mi;
    INSERT INTO restaurantmenuitems (farmid, name, price) VALUES (f, 'Chef special', 80) RETURNING menuitemid INTO v_bare;
    INSERT INTO restaurantrecipes (farmid, menuitemid, ingredientid, quantity, unit, wastepercent) VALUES (f, v_mi, v_tom, 2, 'kg', 0);
    INSERT INTO restaurantrecipes (farmid, menuitemid, ingredientid, quantity, unit, wastepercent) VALUES (f, v_mi, v_rice, 1, 'kg', 10);

    v_p1 := sprestaurant_purchase_create(f, v_tom, 10, 100, CURRENT_DATE, NULL, NULL, 'Cash', NULL, v_cash, NULL, NULL, 'probe');
    v_p2 := sprestaurant_purchase_create(f, v_soda, 24, 48, CURRENT_DATE, NULL, NULL, 'Cash', NULL, v_cash, NULL, NULL, 'probe');
    SELECT COUNT(*) INTO v_ledger FROM restaurantcashtransactions WHERE farmid = f;
    SELECT cogs INTO v_cogs0 FROM sprestaurant_report_pnl_summary(f, CURRENT_DATE, CURRENT_DATE);
    IF v_cogs0 <> 48 THEN RAISE EXCEPTION 'SETUP: cost of sales % (want 48: the soda, expensed when purchased)', v_cogs0; END IF;

    j_tom3  := '[{"itemType":"Ingredient","ingredientId":' || v_tom || ',"entryQuantity":3,"entryUnitCost":0}]';
    j_soda6 := '[{"itemType":"Ingredient","ingredientId":' || v_soda || ',"entryQuantity":6}]';
    j_jol2  := '[{"itemType":"MenuItem","menuItemId":' || v_mi || ',"entryQuantity":2}]';

    -- 1. guards on saving
    v_failed := FALSE; BEGIN PERFORM sprestaurant_internalusage_insert(f, CURRENT_DATE, 'FarmUse', NULL, NULL, NULL, NULL, NULL, j_tom3, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM = 'Pick what the stock was used for.'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1: a Poultry-only reason accepted'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_internalusage_insert(f, CURRENT_DATE + 1, 'StaffWelfare', NULL, NULL, NULL, NULL, NULL, j_tom3, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM = 'The date cannot be in the future.'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1b: future date accepted'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_internalusage_insert(f, CURRENT_DATE, 'StaffWelfare', NULL, NULL, NULL, NULL, NULL,
        '[{"itemType":"Ingredient","ingredientId":' || v_other || ',"entryQuantity":1}]', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM = 'Pick a stock item or menu item of this restaurant.'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1c: another company''s stock accepted'; END IF;
    v_checks := v_checks + 3;

    -- 2. a draft moves nothing
    v_iu1 := sprestaurant_internalusage_insert(f, CURRENT_DATE, 'StaffWelfare', 'Friday lunch', 'Kitchen team', NULL, 6, NULL, j_tom3, 'probe');
    SELECT referenceno, totalcostvalue, status INTO v_txt, v_n, v_st FROM restaurantinternalusage WHERE internalusageid = v_iu1;
    IF v_txt NOT LIKE 'IU-' || to_char(CURRENT_DATE, 'YYYY') || '-%' OR v_n <> 0 OR v_st <> 'Draft' THEN
        RAISE EXCEPTION 'FAIL 2: draft % % %', v_txt, v_n, v_st; END IF;
    IF (SELECT currentstock FROM restaurantingredients WHERE ingredientid = v_tom) <> 10 THEN RAISE EXCEPTION 'FAIL 2b: draft moved stock'; END IF;
    v_checks := v_checks + 2;

    -- 3. post (expense when consumed): blank cost filled from stock history, lot drawn, P&L once, no cash
    PERFORM sprestaurant_internalusage_post(v_iu1, f, 'probe');
    PERFORM sprestaurant_internalusage_post(v_iu1, f, 'probe');   -- repeat is a no-op
    SELECT totalcostvalue, status INTO v_n, v_st FROM restaurantinternalusage WHERE internalusageid = v_iu1;
    IF v_n <> 30 OR v_st <> 'Posted' THEN RAISE EXCEPTION 'FAIL 3: posted % %', v_n, v_st; END IF;
    IF (SELECT currentstock FROM restaurantingredients WHERE ingredientid = v_tom) <> 7 THEN RAISE EXCEPTION 'FAIL 3b: stock'; END IF;
    SELECT remainingquantity, deferredremainingcost INTO v_n, v_n2 FROM restaurantpurchases WHERE purchaseid = v_p1;
    IF v_n <> 7 OR v_n2 <> 70 THEN RAISE EXCEPTION 'FAIL 3c: lot % %', v_n, v_n2; END IF;
    SELECT COUNT(*), SUM(quantity) INTO v_i, v_n FROM restaurantstockmovements WHERE farmid = f AND movementtype = 'InternalUse';
    IF v_i <> 1 OR v_n <> -3 THEN RAISE EXCEPTION 'FAIL 3d: movements % %', v_i, v_n; END IF;
    IF (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'stock_internal_use') <> -30 THEN
        RAISE EXCEPTION 'FAIL 3e: P&L internal use line'; END IF;
    IF (SELECT cogs FROM sprestaurant_report_pnl_summary(f, CURRENT_DATE, CURRENT_DATE)) <> v_cogs0 + 30 THEN RAISE EXCEPTION 'FAIL 3f: cogs'; END IF;
    IF (SELECT plcost FROM sprestaurant_internalusage_getbyid(v_iu1, f)) <> 30 THEN RAISE EXCEPTION 'FAIL 3g: plcost'; END IF;
    IF (SELECT amount FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'internal_use') <> 30
       OR (SELECT amount FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'check') <> 0 THEN
        RAISE EXCEPTION 'FAIL 3h: bridge'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_internalusage_update(v_iu1, f, CURRENT_DATE, 'StaffWelfare', NULL, NULL, NULL, NULL, NULL, j_tom3, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'Only a draft or a reversed record can be edited%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3i: posted record edited'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_internalusage_delete(v_iu1, f, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'A Posted record cannot be deleted%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3j: posted record deleted'; END IF;
    v_checks := v_checks + 10;

    -- 4. expense when purchased: stock moves, cost recorded, P&L NOT charged again
    v_iu2 := sprestaurant_internalusage_insert(f, CURRENT_DATE, 'OwnerUse', NULL, 'Owner', NULL, NULL, NULL, j_soda6, 'probe');
    PERFORM sprestaurant_internalusage_post(v_iu2, f, 'probe');
    IF (SELECT totalcostvalue FROM restaurantinternalusage WHERE internalusageid = v_iu2) <> 12 THEN RAISE EXCEPTION 'FAIL 4: soda cost'; END IF;
    IF (SELECT currentstock FROM restaurantingredients WHERE ingredientid = v_soda) <> 18
       OR (SELECT remainingquantity FROM restaurantpurchases WHERE purchaseid = v_p2) <> 18 THEN RAISE EXCEPTION 'FAIL 4b: soda stock/lot'; END IF;
    IF (SELECT cogs FROM sprestaurant_report_pnl_summary(f, CURRENT_DATE, CURRENT_DATE)) <> v_cogs0 + 30
       OR (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'stock_purchased') <> -48 THEN
        RAISE EXCEPTION 'FAIL 4c: soda charged twice'; END IF;
    IF (SELECT plcost FROM sprestaurant_internalusage_getbyid(v_iu2, f)) <> 0 THEN RAISE EXCEPTION 'FAIL 4d: plcost'; END IF;
    v_checks := v_checks + 4;

    -- 5. menu item through its recipe: 2 jollof = 4 kg tomatoes + 2.2 kg rice
    SELECT onhand, suggestedunitcost INTO v_n, v_n2 FROM sprestaurant_internalusage_items(f) WHERE itemtype = 'MenuItem' AND itemid = v_mi;
    IF v_n <> 3 OR v_n2 <> 24.4 THEN RAISE EXCEPTION 'FAIL 5: picker portions % cost % (want 3, 24.4)', v_n, v_n2; END IF;
    IF EXISTS (SELECT 1 FROM sprestaurant_internalusage_items(f) WHERE itemtype = 'MenuItem' AND itemid = v_bare) THEN
        RAISE EXCEPTION 'FAIL 5b: menu item without recipe offered'; END IF;
    v_iu3 := sprestaurant_internalusage_insert(f, CURRENT_DATE, 'Sample', NULL, 'Table 4', NULL, NULL, NULL, j_jol2, 'probe');
    PERFORM sprestaurant_internalusage_post(v_iu3, f, 'probe');
    IF (SELECT totalcostvalue FROM restaurantinternalusage WHERE internalusageid = v_iu3) <> 48.8 THEN RAISE EXCEPTION 'FAIL 5c: jollof cost'; END IF;
    IF (SELECT currentstock FROM restaurantingredients WHERE ingredientid = v_tom) <> 3
       OR (SELECT currentstock FROM restaurantingredients WHERE ingredientid = v_rice) <> 7.8 THEN RAISE EXCEPTION 'FAIL 5d: recipe stock'; END IF;
    IF (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'stock_internal_use') <> -70 THEN
        RAISE EXCEPTION 'FAIL 5e: P&L (want 30 + 40; rice has no purchase behind it)'; END IF;
    v_checks := v_checks + 5;

    -- 6. not enough stock / no recipe: refused, nothing moves
    v_iu4 := sprestaurant_internalusage_insert(f, CURRENT_DATE, 'StaffWelfare', NULL, NULL, NULL, NULL, NULL, j_jol2, 'probe');
    v_failed := FALSE; BEGIN PERFORM sprestaurant_internalusage_post(v_iu4, f, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM = 'Not enough Tomatoes: 3 in stock, 4 needed.'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6: short stock posted'; END IF;
    PERFORM sprestaurant_internalusage_update(v_iu4, f, CURRENT_DATE, 'StaffWelfare', NULL, NULL, NULL, NULL, NULL,
        '[{"itemType":"MenuItem","menuItemId":' || v_bare || ',"entryQuantity":1}]', 'probe');
    v_failed := FALSE; BEGIN PERFORM sprestaurant_internalusage_post(v_iu4, f, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'Chef special has no recipe%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6b: menu item without recipe posted'; END IF;
    IF (SELECT currentstock FROM restaurantingredients WHERE ingredientid = v_tom) <> 3 THEN RAISE EXCEPTION 'FAIL 6c: refused post moved stock'; END IF;
    PERFORM sprestaurant_internalusage_delete(v_iu4, f, 'probe');
    IF EXISTS (SELECT 1 FROM restaurantinternalusage WHERE internalusageid = v_iu4) THEN RAISE EXCEPTION 'FAIL 6d: draft not deleted'; END IF;
    v_checks := v_checks + 4;

    -- 7. reverse: reason required, stock and deferred cost back to the lot, P&L back today
    v_failed := FALSE; BEGIN PERFORM sprestaurant_internalusage_reverse(v_iu1, f, NULL, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'A reason is required%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7: reversal without reason'; END IF;
    PERFORM sprestaurant_internalusage_reverse(v_iu1, f, 'Wrong quantity', 'probe');
    PERFORM sprestaurant_internalusage_reverse(v_iu1, f, 'again', 'probe');   -- no-op
    IF (SELECT status FROM restaurantinternalusage WHERE internalusageid = v_iu1) <> 'Reversed' THEN RAISE EXCEPTION 'FAIL 7b: status'; END IF;
    IF (SELECT currentstock FROM restaurantingredients WHERE ingredientid = v_tom) <> 6 THEN RAISE EXCEPTION 'FAIL 7c: stock back'; END IF;
    SELECT remainingquantity, deferredremainingcost INTO v_n, v_n2 FROM restaurantpurchases WHERE purchaseid = v_p1;
    IF v_n <> 6 OR v_n2 <> 60 THEN RAISE EXCEPTION 'FAIL 7d: lot after reversal % %', v_n, v_n2; END IF;
    SELECT COUNT(*), SUM(quantity) INTO v_i, v_n FROM restaurantstockmovements WHERE farmid = f AND movementtype = 'InternalUseReversal';
    IF v_i <> 1 OR v_n <> 3 THEN RAISE EXCEPTION 'FAIL 7e: reversal movements % %', v_i, v_n; END IF;
    IF (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'stock_internal_use') <> -40 THEN
        RAISE EXCEPTION 'FAIL 7f: P&L after reversal'; END IF;
    IF (SELECT amount FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'check') <> 0 THEN
        RAISE EXCEPTION 'FAIL 7g: bridge after reversal'; END IF;
    SELECT COUNT(*) FILTER (WHERE isreversed), COALESCE(SUM(recognizedcost) FILTER (WHERE NOT isreversed), 0)
      INTO v_i, v_n FROM sprestaurant_deferredpurchase_history(f, v_p1);
    IF v_i <> 1 OR v_n <> 40 THEN RAISE EXCEPTION 'FAIL 7h: deferred history % reversed, % live', v_i, v_n; END IF;
    IF EXISTS (SELECT 1 FROM sprestaurant_deferredpurchase_getall(f, 'EXCEPTION')) THEN RAISE EXCEPTION 'FAIL 7i: lot exceptions'; END IF;
    v_checks := v_checks + 9;

    -- 8. reversed edits like a draft (stays Reversed), then Post again
    PERFORM sprestaurant_internalusage_update(v_iu1, f, CURRENT_DATE, 'StaffWelfare', 'Friday lunch', 'Kitchen team', NULL, NULL, NULL,
        '[{"itemType":"Ingredient","ingredientId":' || v_tom || ',"entryQuantity":2,"entryUnitCost":10}]', 'probe');
    SELECT status, totalcostvalue INTO v_st, v_n FROM restaurantinternalusage WHERE internalusageid = v_iu1;
    IF v_st <> 'Reversed' OR v_n <> 20 THEN RAISE EXCEPTION 'FAIL 8: edited reversed % %', v_st, v_n; END IF;
    PERFORM sprestaurant_internalusage_post(v_iu1, f, 'probe');
    SELECT status, reversalreason INTO v_st, v_txt FROM restaurantinternalusage WHERE internalusageid = v_iu1;
    IF v_st <> 'Posted' OR v_txt IS NOT NULL THEN RAISE EXCEPTION 'FAIL 8b: re-post % %', v_st, v_txt; END IF;
    IF (SELECT currentstock FROM restaurantingredients WHERE ingredientid = v_tom) <> 4 THEN RAISE EXCEPTION 'FAIL 8c: stock'; END IF;
    IF (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'stock_internal_use') <> -60 THEN
        RAISE EXCEPTION 'FAIL 8d: P&L after re-post'; END IF;
    v_checks := v_checks + 4;

    -- 9. delete a reversed record; the stock history stays. Net-zero assertion.
    PERFORM sprestaurant_internalusage_reverse(v_iu3, f, 'Posted by mistake', 'probe');
    PERFORM sprestaurant_internalusage_delete(v_iu3, f, 'probe');
    IF EXISTS (SELECT 1 FROM restaurantinternalusage WHERE internalusageid = v_iu3) THEN RAISE EXCEPTION 'FAIL 9: not deleted'; END IF;
    IF (SELECT COUNT(*) FROM restaurantstockmovements WHERE farmid = f AND movementtype LIKE 'InternalUse%') <> 8 THEN
        RAISE EXCEPTION 'FAIL 9b: stock history lost'; END IF;
    UPDATE restaurantinternalusage SET status = 'Reversed' WHERE internalusageid = v_iu2;   -- hand-broken
    v_failed := FALSE; BEGIN PERFORM sprestaurant_internalusage_delete(v_iu2, f, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE '%still out of stock%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 9c: net-zero assertion'; END IF;
    UPDATE restaurantinternalusage SET status = 'Posted' WHERE internalusageid = v_iu2;
    v_checks := v_checks + 3;

    -- 10. dated yesterday, reversed today: each day carries its own side; then close yesterday
    v_iu5 := sprestaurant_internalusage_insert(f, v_y, 'Donation', NULL, 'Orphanage', NULL, NULL, NULL,
        '[{"itemType":"Ingredient","ingredientId":' || v_tom || ',"entryQuantity":1}]', 'probe');
    PERFORM sprestaurant_internalusage_post(v_iu5, f, 'probe');
    PERFORM sprestaurant_internalusage_reverse(v_iu5, f, 'Wrong date', 'probe');
    IF (SELECT amount FROM sprestaurant_report_pnl_lines(f, v_y, v_y) WHERE linekey = 'stock_internal_use') <> -10
       OR (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'stock_internal_use') <> -10 THEN
        RAISE EXCEPTION 'FAIL 10: period split'; END IF;
    IF (SELECT amount FROM sprestaurant_report_cash_profit_bridge(f, v_y, v_y) WHERE linekey = 'check') <> 0 THEN
        RAISE EXCEPTION 'FAIL 10b: bridge yesterday'; END IF;
    INSERT INTO restaurantdailyclosings (farmid, closingdate, status, closedby) VALUES (f, v_y, 'Closed', 'probe');
    v_failed := FALSE; BEGIN PERFORM sprestaurant_internalusage_insert(f, v_y, 'Donation', NULL, NULL, NULL, NULL, NULL, j_soda6, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'The books are closed%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 10c: closed day accepted'; END IF;
    v_failed := FALSE; BEGIN PERFORM sprestaurant_internalusage_post(v_iu5, f, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := SQLERRM LIKE 'The books are closed%'; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 10d: posted into a closed day'; END IF;
    v_iu6 := sprestaurant_internalusage_insert(f, CURRENT_DATE, 'QualityTest', NULL, NULL, NULL, NULL, NULL, j_soda6, 'probe');
    PERFORM sprestaurant_internalusage_post(v_iu6, f, 'probe');
    PERFORM sprestaurant_internalusage_reverse(v_iu6, f, 'Stock returned unused', 'probe');   -- reversal is dated today: allowed
    v_checks := v_checks + 5;

    -- 11. never cash; ledger = balances; stock = lots for purchased-only items
    IF (SELECT COUNT(*) FROM restaurantcashtransactions WHERE farmid = f) <> v_ledger THEN RAISE EXCEPTION 'FAIL 11: internal use moved cash'; END IF;
    IF EXISTS (SELECT 1 FROM restaurantcashaccounts a WHERE a.farmid = f
                 AND a.currentbalance <> COALESCE((SELECT SUM(t.amount) FROM restaurantcashtransactions t
                                                    WHERE t.cashaccountid = a.cashaccountid), 0)) THEN
        RAISE EXCEPTION 'FAIL 11b: an account balance disagrees with its ledger'; END IF;
    IF (SELECT currentstock FROM restaurantingredients WHERE ingredientid = v_tom)
       <> (SELECT remainingquantity FROM restaurantpurchases WHERE purchaseid = v_p1)
       OR (SELECT currentstock FROM restaurantingredients WHERE ingredientid = v_soda)
       <> (SELECT remainingquantity FROM restaurantpurchases WHERE purchaseid = v_p2) THEN
        RAISE EXCEPTION 'FAIL 11c: stock and lots disagree'; END IF;
    IF (SELECT amount FROM sprestaurant_report_cash_profit_bridge(f, v_y, CURRENT_DATE) WHERE linekey = 'check') <> 0 THEN
        RAISE EXCEPTION 'FAIL 11d: bridge over both days'; END IF;
    v_checks := v_checks + 4;

    RAISE EXCEPTION 'SELFTEST PASSED: % checks (rolled back)', v_checks;
END $$;
