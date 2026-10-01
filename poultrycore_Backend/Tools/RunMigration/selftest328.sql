-- Self-test for migration 328 (Restaurant Capital Investments/Assets). Run on
-- its own after 328; it always ends by raising so everything rolls back.
-- "SELFTEST PASSED" in the error is the success signal.
--
-- The story: a 12,000 combi oven bought two months ago, 9,000 paid from the Main
-- Cash Box and 3,000 owed to Kitchen Pro, depreciated over 12 months; a POS
-- terminal paid by bank, improved on credit, its original cost corrected twice,
-- then reversed; the oven sold for 5,000. Every guard, the ledger, balances,
-- Cash Flow, the P&L, the payables seam and the profit-vs-cash bridge are checked.
DO $$
DECLARE
    f TEXT := '__probe328__';
    v_cash INT; v_bank INT; v_strict INT; v_oven INT; v_pos INT; v_cat_k INT; v_cat_p INT;
    v_start DATE := (date_trunc('month', CURRENT_DATE) - INTERVAL '2 months')::DATE;
    v_end DATE := (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE;
    v_cost INT; v_corr INT; v_dep INT; v_n NUMERIC; v_n2 NUMERIC; v_i INT; v_i2 INT;
    v_failed BOOLEAN; v_checks INT := 0; r RECORD;
BEGIN
    v_cash := fnrestaurant_default_account(f, 'Cash');
    v_bank := fnrestaurant_default_account(f, 'Bank');
    INSERT INTO restaurantcashaccounts (farmid, name, accounttype, allownegative)
    VALUES (f, 'Strict safe', 'CashBox', FALSE) RETURNING cashaccountid INTO v_strict;

    -- 1. categories seeded per restaurant, restaurant vocabulary
    SELECT COUNT(*) INTO v_i FROM sprestaurant_assetcategory_list(f);
    SELECT assetcategoryid, defaultusefullifemonths INTO v_cat_k, v_i2 FROM sprestaurant_assetcategory_list(f)
     WHERE categoryname = 'Kitchen Equipment';
    SELECT assetcategoryid INTO v_cat_p FROM sprestaurant_assetcategory_list(f) WHERE categoryname = 'POS & Electronics';
    IF v_i <> 9 OR v_i2 <> 84 OR v_cat_p IS NULL THEN RAISE EXCEPTION 'FAIL 1a: categories % %', v_i, v_i2; END IF;
    PERFORM sprestaurant_assetcategory_list(f);
    IF (SELECT COUNT(*) FROM restaurantassetcategories WHERE farmid = f) <> 9 THEN RAISE EXCEPTION 'FAIL 1b: reseeded'; END IF;
    v_checks := v_checks + 2;

    -- 2. guards on create
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_create(f, '  ');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2a: blank name accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_create(f, 'Future', NULL, NULL, CURRENT_DATE + 1, NULL, 100);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2b: future acquisition accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_create(f, 'Early', NULL, NULL, CURRENT_DATE, CURRENT_DATE - 1, 100);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2c: in service before acquired accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_create(f, 'Credit paid', NULL, NULL, CURRENT_DATE, NULL, 100, 0, NULL,
                                                   'Someone', NULL, 'Credit', 50);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2d: credit purchase with money paid accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_create(f, 'Owed to nobody', NULL, NULL, CURRENT_DATE, NULL, 100, 0, NULL,
                                                   NULL, NULL, 'Cash', 40);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2e: unpaid balance with no supplier accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_create(f, 'Overdraft probe', NULL, NULL, CURRENT_DATE, NULL, 100, 0, NULL,
                                                   NULL, NULL, 'Cash', NULL, NULL, v_strict);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2f: overdraft of a strict account accepted'; END IF;
    IF EXISTS (SELECT 1 FROM restaurantcapitalassets WHERE farmid = f) THEN
        RAISE EXCEPTION 'FAIL 2g: a refused create left an asset behind'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_create(f, 'Residual', NULL, NULL, CURRENT_DATE, NULL, 100, 150);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2h: residual above cost accepted'; END IF;
    v_checks := v_checks + 8;

    -- 3. the oven: 12,000, 9,000 paid from the cash box, 3,000 owed to Kitchen Pro
    v_oven := sprestaurant_capitalasset_create(f, 'Combi oven', v_cat_k, '10-tray', v_start, v_start, 12000, 0, 12,
                                               'Kitchen Pro', NULL, 'Cash', 9000, v_end, NULL, 'Main kitchen', 'SN-1',
                                               NULL, 'probe');
    SELECT * INTO r FROM sprestaurant_capitalasset_list(f) WHERE capitalassetid = v_oven;
    IF r.assetnumber <> 'AST-0001' OR r.status <> 'Active' OR r.totalcapitalizedcost <> 12000
       OR r.acquisitioncost <> 12000 OR r.monthlydepreciation <> 1000 OR r.currentbookvalue <> 12000
       OR r.amountowed <> 3000 OR r.categoryname <> 'Kitchen Equipment' THEN
        RAISE EXCEPTION 'FAIL 3a: %', row_to_json(r); END IF;
    IF (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_cash) <> -9000 THEN
        RAISE EXCEPTION 'FAIL 3b: cash box not -9000'; END IF;
    SELECT COUNT(*), SUM(amount) INTO v_i, v_n FROM restaurantcashtransactions WHERE farmid = f;
    IF v_i <> 1 OR v_n <> -9000
       OR NOT EXISTS (SELECT 1 FROM restaurantcashtransactions t JOIN restaurantcapitalassetcosts c
                        ON t.sourcetype = 'AssetPurchase' AND t.sourceid = c.assetcostid AND c.capitalassetid = v_oven) THEN
        RAISE EXCEPTION 'FAIL 3c: ledger % %', v_i, v_n; END IF;
    SELECT * INTO r FROM sprestaurant_capitalasset_costs(f, v_oven);
    IF r.paymentstatus <> 'Partial' OR r.balance <> 3000 OR r.cashaccountname <> 'Main Cash Box' OR r.duedate <> v_end THEN
        RAISE EXCEPTION 'FAIL 3d: %', row_to_json(r); END IF;
    v_checks := v_checks + 4;

    -- 4. buying is NOT a cost: the P&L is untouched; Cash Flow shows an Operating out
    SELECT expenses_total, net_profit INTO v_n, v_n2 FROM sprestaurant_report_pnl_summary(f, v_start, v_end);
    IF v_n <> 0 OR v_n2 <> 0 THEN RAISE EXCEPTION 'FAIL 4a: purchase reached the P&L % %', v_n, v_n2; END IF;
    SELECT * INTO r FROM sprestaurantcashflow_detail(f, v_start::TIMESTAMP, v_end::TIMESTAMP) WHERE sourcetype = 'AssetPurchase';
    IF r.category <> 'Capital investments' OR r.flowgroup <> 'OperatingOut' OR r.amount <> -9000 THEN
        RAISE EXCEPTION 'FAIL 4b: %', row_to_json(r); END IF;
    v_checks := v_checks + 2;

    -- 5. the payables seam: 3,000 owed to Kitchen Pro
    SELECT COUNT(*), SUM(balance) INTO v_i, v_n FROM sprestaurant_capitalasset_payables(f);
    IF v_i <> 1 OR v_n <> 3000 OR (SELECT suppliername FROM sprestaurant_capitalasset_payables(f)) <> 'Kitchen Pro' THEN
        RAISE EXCEPTION 'FAIL 5: payables % %', v_i, v_n; END IF;
    v_checks := v_checks + 1;

    -- 6. depreciation: 3 months due, generate charges them once, moves no cash
    SELECT monthsdue, amountdue INTO v_i, v_n FROM sprestaurant_assetdepreciation_due(f) WHERE capitalassetid = v_oven;
    IF v_i <> 3 OR v_n <> 3000 THEN RAISE EXCEPTION 'FAIL 6a: due % %', v_i, v_n; END IF;
    SELECT * INTO r FROM sprestaurant_assetdepreciation_generate(f, NULL, NULL, 'probe');
    IF r.entriescreated <> 3 OR r.totalamount <> 3000 OR r.assetsprocessed <> 1 THEN RAISE EXCEPTION 'FAIL 6b: %', row_to_json(r); END IF;
    SELECT * INTO r FROM sprestaurant_assetdepreciation_generate(f, NULL, NULL, 'probe');
    IF r.entriescreated <> 0 THEN RAISE EXCEPTION 'FAIL 6c: second run charged %', r.entriescreated; END IF;
    IF (SELECT COUNT(*) FROM restaurantcashtransactions WHERE farmid = f) <> 1 THEN RAISE EXCEPTION 'FAIL 6d: depreciation moved cash'; END IF;
    IF EXISTS (SELECT 1 FROM sprestaurant_assetdepreciation_due(f)) THEN RAISE EXCEPTION 'FAIL 6e: still due'; END IF;
    SELECT accumulateddepreciation, currentbookvalue INTO v_n, v_n2 FROM sprestaurant_capitalasset_list(f) WHERE capitalassetid = v_oven;
    IF v_n <> 3000 OR v_n2 <> 9000 THEN RAISE EXCEPTION 'FAIL 6f: % %', v_n, v_n2; END IF;
    v_checks := v_checks + 6;

    -- 7. P&L: a Depreciation line in Depreciation & Financing ('Other'); breakdown adds up
    SELECT amount INTO v_n FROM sprestaurant_report_pnl_lines(f, v_start, v_end) WHERE linekey = 'depreciation';
    IF v_n IS DISTINCT FROM -3000 OR (SELECT section FROM sprestaurant_report_pnl_lines(f, v_start, v_end) WHERE linekey = 'depreciation') <> 'Other' THEN
        RAISE EXCEPTION 'FAIL 7a: depreciation line %', v_n; END IF;
    SELECT expenses_total, net_profit INTO v_n, v_n2 FROM sprestaurant_report_pnl_summary(f, v_start, v_end);
    IF v_n <> 3000 OR v_n2 <> -3000 THEN RAISE EXCEPTION 'FAIL 7b: % %', v_n, v_n2; END IF;
    IF (SELECT SUM(expense_total) FROM sprestaurant_report_pnl_expenses(f, v_start, v_end)) <> v_n
       OR (SELECT expense_total FROM sprestaurant_report_pnl_expenses(f, v_start, v_end) WHERE expense_category = 'Depreciation') <> 3000 THEN
        RAISE EXCEPTION 'FAIL 7c: breakdown'; END IF;
    v_checks := v_checks + 3;

    -- 8. the bridge: purchase = cash not profit, depreciation = profit not cash
    SELECT amount INTO v_n FROM sprestaurant_report_cash_profit_bridge(f, v_start, v_end) WHERE linekey = 'check';
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 8a: bridge unexplained %', v_n; END IF;
    IF (SELECT amount FROM sprestaurant_report_cash_profit_bridge(f, v_start, v_end) WHERE linekey = 'depreciation') <> 3000
       OR (SELECT amount FROM sprestaurant_report_cash_profit_bridge(f, v_start, v_end) WHERE linekey = 'capital_investments') <> -9000 THEN
        RAISE EXCEPTION 'FAIL 8b: bridge lines'; END IF;
    v_checks := v_checks + 2;

    -- 9. once depreciation is posted: cost, financials and reversal are locked
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_addcost(f, v_oven, CURRENT_DATE, 'Hood', 'Install', 500);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 9a: cost added under posted depreciation'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_update(f, v_oven, 'Combi oven', NULL, NULL, NULL, NULL, NULL, v_start, 24, 0, TRUE, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 9b: life changed under posted depreciation'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_reverse(f, v_oven, 'oops', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 9c: reversed with depreciation posted'; END IF;
    PERFORM sprestaurant_capitalasset_update(f, v_oven, 'Combi oven 10-tray', NULL, NULL, 'Kitchen line', NULL, 'moved', NULL, NULL, NULL, FALSE, 'probe');
    IF (SELECT assetname || '|' || location FROM restaurantcapitalassets WHERE capitalassetid = v_oven) <> 'Combi oven 10-tray|Kitchen line' THEN
        RAISE EXCEPTION 'FAIL 9d: details edit'; END IF;
    v_checks := v_checks + 4;

    -- 10. reverse one charge (append-only), not reopened to the generator; adjust re-posts it
    SELECT assetdepreciationid INTO v_dep FROM restaurantassetdepreciation
     WHERE capitalassetid = v_oven AND periodstart = date_trunc('month', CURRENT_DATE)::DATE;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_assetdepreciation_reverse(f, v_dep, ' ', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 10a: reversal without a reason'; END IF;
    PERFORM sprestaurant_assetdepreciation_reverse(f, v_dep, 'wrong month', 'probe');
    IF (SELECT status FROM restaurantassetdepreciation WHERE assetdepreciationid = v_dep) <> 'Reversed'
       OR (SELECT COUNT(*) FROM restaurantassetdepreciation WHERE reversalofid = v_dep AND amount = -1000 AND depreciationdate = CURRENT_DATE) <> 1 THEN
        RAISE EXCEPTION 'FAIL 10b: reversal rows'; END IF;
    IF (SELECT accumulateddepreciation FROM sprestaurant_capitalasset_list(f) WHERE capitalassetid = v_oven) <> 2000 THEN
        RAISE EXCEPTION 'FAIL 10c: accumulated after reversal'; END IF;
    SELECT entriescreated INTO v_i FROM sprestaurant_assetdepreciation_generate(f, NULL, NULL, 'probe');
    IF v_i <> 0 THEN RAISE EXCEPTION 'FAIL 10d: reversed month re-charged by the generator'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_assetdepreciation_reverse(f, (SELECT assetdepreciationid FROM restaurantassetdepreciation WHERE reversalofid = v_dep), 'x', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 10e: a reversal was reversed'; END IF;
    PERFORM sprestaurant_assetdepreciation_adjust(f, v_oven, CURRENT_DATE, 1000, 'right amount', 'probe');
    IF (SELECT accumulateddepreciation FROM sprestaurant_capitalasset_list(f) WHERE capitalassetid = v_oven) <> 3000
       OR (SELECT amount FROM sprestaurant_report_pnl_lines(f, v_start, v_end) WHERE linekey = 'depreciation') <> -3000 THEN
        RAISE EXCEPTION 'FAIL 10f: adjust'; END IF;
    v_checks := v_checks + 6;

    -- 11. the POS terminal: Draft, paid by bank; an added cost on credit
    v_pos := sprestaurant_capitalasset_create(f, 'POS terminal', v_cat_p, NULL, CURRENT_DATE, NULL, 2400, 0, NULL,
                                              'Tech Hub', NULL, 'Bank', NULL, NULL, NULL, NULL, NULL, NULL, 'probe');
    IF (SELECT status || assetnumber FROM restaurantcapitalassets WHERE capitalassetid = v_pos) <> 'DraftAST-0002'
       OR (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_bank) <> -2400 THEN
        RAISE EXCEPTION 'FAIL 11a: draft / bank'; END IF;
    v_cost := sprestaurant_capitalasset_addcost(f, v_pos, CURRENT_DATE, 'Card reader', 'Upgrade', 600, 'Tech Hub', NULL, 'Credit', NULL, v_end, NULL, 'probe');
    SELECT * INTO r FROM sprestaurant_capitalasset_list(f) WHERE capitalassetid = v_pos;
    IF r.acquisitioncost <> 2400 OR r.additionalcost <> 600 OR r.totalcapitalizedcost <> 3000 OR r.amountowed <> 600 THEN
        RAISE EXCEPTION 'FAIL 11b: %', row_to_json(r); END IF;
    IF (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_bank) <> -2400 THEN
        RAISE EXCEPTION 'FAIL 11c: credit cost moved cash'; END IF;
    v_checks := v_checks + 3;

    -- 12. correct the original cost down (refund) and up (owed); never an edit
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_correctoriginalcost(f, v_pos, 2000, NULL, '', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 12a: correction without reason'; END IF;
    v_corr := sprestaurant_capitalasset_correctoriginalcost(f, v_pos, 2000, NULL, 'invoice misread', 'probe');
    IF (SELECT amount || '|' || amountpaid FROM restaurantcapitalassetcosts WHERE assetcostid = v_corr) <> '-400.00|-400.00'
       OR (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_bank) <> -2000
       OR (SELECT amount FROM restaurantcashtransactions WHERE sourcetype = 'AssetPurchaseReversal' AND sourceid = v_corr) <> 400 THEN
        RAISE EXCEPTION 'FAIL 12b: downward correction'; END IF;
    PERFORM sprestaurant_capitalasset_correctoriginalcost(f, v_pos, 2500, NULL, 'delivery charge included', 'probe');
    SELECT * INTO r FROM sprestaurant_capitalasset_list(f) WHERE capitalassetid = v_pos;
    IF r.acquisitioncost <> 2500 OR r.totalcapitalizedcost <> 3100 OR r.amountowed <> 1100
       OR (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_bank) <> -2000 THEN
        RAISE EXCEPTION 'FAIL 12c: upward correction %', row_to_json(r); END IF;
    SELECT balance INTO v_n FROM sprestaurant_capitalasset_costs(f, v_pos) WHERE sourcetype = 'Acquisition';
    IF v_n <> 500 THEN RAISE EXCEPTION 'FAIL 12d: acquisition document balance %', v_n; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_cost_reverse(f, v_corr, 'no', 'probe', v_pos);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 12e: a correction was reversed'; END IF;
    v_checks := v_checks + 5;

    -- 13. reverse the added cost, then the whole terminal: every cedi comes back
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_cost_reverse(f, v_cost, 'wrong asset', 'probe', v_oven);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 13a: cost reversed through another asset'; END IF;
    PERFORM sprestaurant_capitalasset_cost_reverse(f, v_cost, 'returned the reader', 'probe', v_pos);
    IF (SELECT status FROM restaurantcapitalassetcosts WHERE assetcostid = v_cost) <> 'Reversed'
       OR (SELECT totalcapitalizedcost FROM sprestaurant_capitalasset_list(f) WHERE capitalassetid = v_pos) <> 2500 THEN
        RAISE EXCEPTION 'FAIL 13b: cost reversal'; END IF;
    PERFORM sprestaurant_capitalasset_reverse(f, v_pos, 'bought for the wrong branch', 'probe');
    IF (SELECT status FROM restaurantcapitalassets WHERE capitalassetid = v_pos) <> 'Reversed'
       OR EXISTS (SELECT 1 FROM restaurantcapitalassetcosts WHERE capitalassetid = v_pos AND status = 'Posted')
       OR (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_bank) <> 0 THEN
        RAISE EXCEPTION 'FAIL 13c: asset reversal'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_reverse(f, v_pos, 'again', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 13d: reversed twice'; END IF;
    v_checks := v_checks + 4;

    -- 14. dispose the oven: proceeds are cash in, not revenue; depreciation stops
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_dispose(f, v_oven, CURRENT_DATE, 5000, NULL, NULL, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 14a: proceeds with no account'; END IF;
    PERFORM sprestaurant_capitalasset_dispose(f, v_oven, CURRENT_DATE, 5000, v_cash, 'sold to a caterer', 'probe');
    IF (SELECT status FROM restaurantcapitalassets WHERE capitalassetid = v_oven) <> 'Disposed'
       OR (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_cash) <> -4000
       OR (SELECT amount FROM restaurantcashtransactions WHERE sourcetype = 'AssetDisposal' AND sourceid = v_oven) <> 5000 THEN
        RAISE EXCEPTION 'FAIL 14b: disposal'; END IF;
    IF (SELECT revenue FROM sprestaurant_report_pnl_summary(f, v_start, v_end)) <> 0 THEN RAISE EXCEPTION 'FAIL 14c: proceeds became revenue'; END IF;
    IF (SELECT category FROM sprestaurantcashflow_detail(f, v_start::TIMESTAMP, v_end::TIMESTAMP) WHERE sourcetype = 'AssetDisposal') <> 'Capital investments sold' THEN
        RAISE EXCEPTION 'FAIL 14d: cash flow category'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_dispose(f, v_oven, CURRENT_DATE, NULL, NULL, NULL, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 14e: disposed twice'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_reverse(f, v_oven, 'x', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 14f: disposed asset reversed'; END IF;
    v_checks := v_checks + 6;

    -- 15. summary cards (book value is a balance; reversed assets are out)
    SELECT * INTO r FROM sprestaurant_capitalasset_summary(f);
    IF r.totalassets <> 1 OR r.disposedassets <> 1 OR r.totalassetcost <> 12000 OR r.accumulateddepreciation <> 3000
       OR r.currentbookvalue <> 9000 OR r.amountowed <> 3000 THEN
        RAISE EXCEPTION 'FAIL 15: %', row_to_json(r); END IF;
    v_checks := v_checks + 1;

    -- 16. the bridge reconciles over the whole story and over today alone
    SELECT amount INTO v_n FROM sprestaurant_report_cash_profit_bridge(f, v_start, v_end) WHERE linekey = 'check';
    SELECT amount INTO v_n2 FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'check';
    IF v_n <> 0 OR v_n2 <> 0 THEN RAISE EXCEPTION 'FAIL 16a: bridge unexplained % / %', v_n, v_n2; END IF;
    IF (SELECT amount FROM sprestaurant_report_cash_profit_bridge(f, v_start, v_end) WHERE linekey = 'net_cash') <> -4000
       OR (SELECT amount FROM sprestaurant_report_cash_profit_bridge(f, v_start, v_end) WHERE linekey = 'asset_disposals') <> 5000 THEN
        RAISE EXCEPTION 'FAIL 16b: bridge lines'; END IF;
    v_checks := v_checks + 2;

    -- 17. every account: balance = its ledger; source ids never collided
    FOR r IN SELECT a.name, a.currentbalance, COALESCE(SUM(t.amount), 0) AS led
               FROM restaurantcashaccounts a LEFT JOIN restaurantcashtransactions t ON t.cashaccountid = a.cashaccountid
              WHERE a.farmid = f GROUP BY a.cashaccountid LOOP
        IF r.currentbalance <> r.led THEN RAISE EXCEPTION 'FAIL 17: % % vs ledger %', r.name, r.currentbalance, r.led; END IF;
    END LOOP;
    v_checks := v_checks + 1;

    -- 18. closed-day lock: close yesterday, then nothing can be bought dated yesterday
    PERFORM sprestaurant_dailyclosing_close(f, CURRENT_DATE - 1, NULL, 'probe');
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_capitalasset_create(f, 'Late entry', NULL, NULL, CURRENT_DATE - 1, NULL, 100);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 18: purchase into a closed day accepted'; END IF;
    v_checks := v_checks + 1;

    RAISE EXCEPTION 'SELFTEST PASSED: % checks (rolled back)', v_checks;
END $$;
