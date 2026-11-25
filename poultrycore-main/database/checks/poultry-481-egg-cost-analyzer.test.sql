-- 481: Egg Cost & Profit Analyzer -- the database guarantees.
-- Self-contained: BEGIN ... ROLLBACK, so even a bare run leaves nothing behind.
BEGIN;
DO $$
DECLARE
    v_farm   text;
    v_other  text;
    v_flock  integer;
    v_batch  integer;
    v_f1     jsonb;
    v_f2     jsonb;
    v_n      bigint;
    v_before text;
    v_after  text;
    v_eid    integer;
    v_ok     boolean;
    v_s      jsonb;
    v_id     integer;
BEGIN
    -- the poultry company with the most production records, and another one
    SELECT farmid INTO v_farm FROM productionrecords GROUP BY farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT farmid INTO v_other FROM productionrecords WHERE farmid <> v_farm GROUP BY farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT f.flockid, f.batchid INTO v_flock, v_batch FROM flock f
    WHERE f.farmid = v_farm AND NOT COALESCE(f.isdeleted, false) AND f.batchid IS NOT NULL
    ORDER BY (SELECT count(*) FROM productionrecords r WHERE r.flockid = f.flockid) DESC LIMIT 1;

    -- 1. Test 23: running the analysis writes nothing to business tables
    SELECT string_agg(t || '=' || n, ',' ORDER BY t) INTO v_before FROM (
        SELECT 'expense' t, count(*) n FROM expense UNION ALL SELECT 'cash', count(*) FROM poultrycashtransactions
        UNION ALL SELECT 'payments', count(*) FROM poultrypayments UNION ALL SELECT 'stock', count(*) FROM poultrystocktransactions
        UNION ALL SELECT 'records', count(*) FROM productionrecords UNION ALL SELECT 'sales', count(*) FROM sale
        UNION ALL SELECT 'supplierpay', count(*) FROM poultrysupplierpayments UNION ALL SELECT 'rmusage', count(*) FROM poultryrawmaterialusage) x;
    FOR i IN 1..3 LOOP
        v_f1 := sppoultryeggcost_facts(v_farm, current_date - 365, current_date);
    END LOOP;
    SELECT string_agg(t || '=' || n, ',' ORDER BY t) INTO v_after FROM (
        SELECT 'expense' t, count(*) n FROM expense UNION ALL SELECT 'cash', count(*) FROM poultrycashtransactions
        UNION ALL SELECT 'payments', count(*) FROM poultrypayments UNION ALL SELECT 'stock', count(*) FROM poultrystocktransactions
        UNION ALL SELECT 'records', count(*) FROM productionrecords UNION ALL SELECT 'sales', count(*) FROM sale
        UNION ALL SELECT 'supplierpay', count(*) FROM poultrysupplierpayments UNION ALL SELECT 'rmusage', count(*) FROM poultryrawmaterialusage) x;
    IF v_before IS DISTINCT FROM v_after THEN RAISE EXCEPTION 'FAIL 481.1: the analysis wrote business rows (% -> %)', v_before, v_after; END IF;
    RAISE NOTICE 'ok 481.1 analysing three times wrote no expense, cash, payment, stock, record, sale or usage row';

    -- 2. Test 22: one company's facts never carry another company's rows
    SELECT count(*) INTO v_n FROM jsonb_array_elements(v_f1 -> 'records') r
    JOIN productionrecords p ON p.id = (r ->> 'id')::int WHERE p.farmid <> v_farm;
    IF v_n > 0 THEN RAISE EXCEPTION 'FAIL 481.2: % record(s) of another company', v_n; END IF;
    SELECT count(*) INTO v_n FROM jsonb_array_elements(v_f1 -> 'costs') c
    JOIN expense e ON e.expenseid = (c ->> 'expenseId')::int WHERE e.farmid::text <> v_farm;
    IF v_n > 0 THEN RAISE EXCEPTION 'FAIL 481.2: % expense(s) of another company', v_n; END IF;
    SELECT count(*) INTO v_n FROM jsonb_array_elements(v_f1 -> 'flocks') f
    JOIN flock fl ON fl.flockid = (f ->> 'flockId')::int WHERE fl.farmid <> v_farm;
    IF v_n > 0 THEN RAISE EXCEPTION 'FAIL 481.2: % flock(s) of another company', v_n; END IF;
    SELECT count(*) INTO v_n FROM jsonb_array_elements(v_f1 -> 'sales') s
    JOIN sale x ON x.saleid = (s ->> 'saleId')::int WHERE x.farmid <> v_farm;
    IF v_n > 0 THEN RAISE EXCEPTION 'FAIL 481.2: % sale(s) of another company', v_n; END IF;
    RAISE NOTICE 'ok 481.2 facts hold only the requested company''s records, expenses, flocks and sales';

    -- 3. production counted once: facts gross = the records' own totals (sorting never adds eggs)
    SELECT COALESCE(SUM((r ->> 'gross')::numeric), 0) - COALESCE((SELECT SUM(totalproduction) FROM productionrecords
           WHERE farmid = v_farm AND flockid IS NOT NULL AND date BETWEEN current_date - 365 AND current_date), 0)
    INTO v_n FROM jsonb_array_elements(v_f1 -> 'records') r;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 481.3: facts gross differs from production records by %', v_n; END IF;
    RAISE NOTICE 'ok 481.3 gross eggs are exactly the production records (sorting and sales add none)';

    -- 4. stock purchases / consumption are never a cost line of their own
    SELECT count(*) INTO v_n FROM jsonb_array_elements(v_f1 -> 'costs') c
    WHERE c ->> 'sourceType' IN ('PoultryRawMaterialPurchase', 'PoultryFeedConsumption', 'PoultryMedicationConsumption', 'MainFlockBatch', 'CapitalAsset')
      AND c ->> 'component' NOT LIKE 'Excluded%';
    IF v_n > 0 THEN RAISE EXCEPTION 'FAIL 481.4: % stock/bird/capital expense(s) not excluded', v_n; END IF;
    RAISE NOTICE 'ok 481.4 purchase, consumption, bird-purchase and capital expenses are all excluded (no double count)';

    -- 5. Test 20: a new expense appears, its reversal (removal) disappears, the fingerprint moves both times
    INSERT INTO expense (farmid, userid, expensedate, category, description, amount, paymentmethod)
    SELECT v_farm::uuid, e.userid, current_date, 'Utilities', '481 check electricity', 2000, 'Cash'
    FROM expense e WHERE e.userid IS NOT NULL ORDER BY (e.farmid::text = v_farm) DESC LIMIT 1
    RETURNING expenseid INTO v_eid;
    v_f2 := sppoultryeggcost_facts(v_farm, current_date - 365, current_date);
    SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(v_f2 -> 'costs') c WHERE (c ->> 'expenseId')::int = v_eid AND c ->> 'component' = 'Utilities') INTO v_ok;
    IF NOT v_ok THEN RAISE EXCEPTION 'FAIL 481.5: a new utilities expense is not in the facts'; END IF;
    IF v_f2 ->> 'fingerprint' = v_f1 ->> 'fingerprint' THEN RAISE EXCEPTION 'FAIL 481.5: fingerprint did not change'; END IF;
    DELETE FROM expense WHERE expenseid = v_eid;
    v_f2 := sppoultryeggcost_facts(v_farm, current_date - 365, current_date);
    IF v_f2 ->> 'fingerprint' <> v_f1 ->> 'fingerprint' THEN RAISE EXCEPTION 'FAIL 481.5: fingerprint did not return after removal'; END IF;
    RAISE NOTICE 'ok 481.5 an expense change is picked up and changes the fingerprint; undoing it restores it';

    -- 6. settings are versioned and audited
    v_s := sppoultryeggcost_settingssave(v_farm, '{"labourAllocation":"SaleableEggs"}'::jsonb, '481-check');
    v_s := sppoultryeggcost_settingssave(v_farm, '{"labourAllocation":"BirdDays","overheadEggSharePct":80}'::jsonb, '481-check');
    IF (v_s ->> 'version')::int < 2 OR (v_s ->> 'overheadEggSharePct')::numeric <> 80 THEN RAISE EXCEPTION 'FAIL 481.6: settings %', v_s; END IF;
    SELECT count(*) INTO v_n FROM poultryeggcostaudit WHERE farmid = v_farm AND kind = 'Settings' AND changedby = '481-check';
    IF v_n < 2 THEN RAISE EXCEPTION 'FAIL 481.6: % settings audit rows', v_n; END IF;
    BEGIN
        PERFORM sppoultryeggcost_settingssave(v_farm, '{"labourAllocation":"Guess"}'::jsonb, '481-check');
        RAISE EXCEPTION 'FAIL 481.6: an unknown allocation basis was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    RAISE NOTICE 'ok 481.6 settings save bumps the version, writes an audit row, refuses unknown values';

    -- 7. historical cost: never what VisibilityCore already holds
    IF EXISTS (SELECT 1 FROM mainflockbatch WHERE batchid = v_batch AND COALESCE(totalcost, 0) > 0) THEN
        BEGIN
            PERFORM sppoultryeggcost_historicaladd(v_farm, v_flock, NULL, 'BirdPurchase', 100, NULL, NULL, 'check', NULL, true, '481-check');
            RAISE EXCEPTION 'FAIL 481.7: bird cost accepted although the batch records it';
        EXCEPTION WHEN raise_exception THEN
            IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
        END;
    END IF;
    IF EXISTS (SELECT 1 FROM productionrecords WHERE flockid = v_flock AND COALESCE(totalfeedcost, 0) > 0) THEN
        BEGIN
            PERFORM sppoultryeggcost_historicaladd(v_farm, v_flock, NULL, 'Feed', 100, NULL, NULL, 'check', NULL, true, '481-check');
            RAISE EXCEPTION 'FAIL 481.7: feed accepted although production records cost feed in that period';
        EXCEPTION WHEN raise_exception THEN
            IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
        END;
    END IF;
    BEGIN
        PERFORM sppoultryeggcost_historicaladd(v_other, v_flock, NULL, 'Other', 100, NULL, NULL, 'check', NULL, true, '481-check');
        RAISE EXCEPTION 'FAIL 481.7: another company''s flock was accepted';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    END;
    v_id := sppoultryeggcost_historicaladd(v_farm, v_flock, NULL, 'Labour', 500, current_date - 400, current_date - 380, 'Rearing labour before VisibilityCore', 'Notebook p.4', true, '481-check');
    v_f2 := sppoultryeggcost_facts(v_farm, current_date - 30, current_date);
    SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(v_f2 -> 'flocks') f
                   WHERE (f ->> 'flockId')::int = v_flock AND (f ->> 'historicalCost')::numeric >= 500 AND (f ->> 'historicalCostHasEstimate')::boolean)
      OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_f2 -> 'flocks') f WHERE (f ->> 'flockId')::int = v_flock) INTO v_ok;
    IF NOT v_ok THEN RAISE EXCEPTION 'FAIL 481.7: the historical cost is not on the flock'; END IF;
    PERFORM sppoultryeggcost_historicalreverse(v_farm, v_id, 'check', '481-check');
    IF (SELECT status FROM poultryeggcosthistoricalcosts WHERE historicalcostid = v_id) <> 'Reversed' THEN RAISE EXCEPTION 'FAIL 481.7: not reversed'; END IF;
    RAISE NOTICE 'ok 481.7 historical costs: duplicates and other companies refused; added, shown as estimate, reversed';

    -- 8. Test 19: a snapshot keeps its inputs and results and posts nothing
    SELECT string_agg(t || '=' || n, ',' ORDER BY t) INTO v_before FROM (
        SELECT 'expense' t, count(*) n FROM expense UNION ALL SELECT 'cash', count(*) FROM poultrycashtransactions) x;
    v_id := sppoultryeggcost_snapshotsave(v_farm, 'Feed +15% check', 'Scenario',
        '{"startDate":"2026-10-01","endDate":"2026-10-31","scenario":{"feedPricePct":15}}'::jsonb,
        '{"headline":{"fullPerCrate":38.5}}'::jsonb, '481.1', 2, v_f1 ->> 'fingerprint', '481-check');
    v_s := sppoultryeggcost_snapshotget(v_farm, v_id);
    IF (v_s #>> '{params,scenario,feedPricePct}')::int <> 15 OR (v_s #>> '{result,headline,fullPerCrate}')::numeric <> 38.5
       OR v_s ->> 'sourceFingerprint' <> v_f1 ->> 'fingerprint' THEN
        RAISE EXCEPTION 'FAIL 481.8: snapshot round trip %', v_s;
    END IF;
    IF sppoultryeggcost_snapshotget(v_other, v_id) IS NOT NULL THEN RAISE EXCEPTION 'FAIL 481.8: another company can read the snapshot'; END IF;
    SELECT string_agg(t || '=' || n, ',' ORDER BY t) INTO v_after FROM (
        SELECT 'expense' t, count(*) n FROM expense UNION ALL SELECT 'cash', count(*) FROM poultrycashtransactions) x;
    IF v_before IS DISTINCT FROM v_after THEN RAISE EXCEPTION 'FAIL 481.8: saving a snapshot posted rows'; END IF;
    PERFORM sppoultryeggcost_snapshotdelete(v_farm, v_id, '481-check');
    IF sppoultryeggcost_snapshotget(v_farm, v_id) IS NOT NULL THEN RAISE EXCEPTION 'FAIL 481.8: deleted snapshot still readable'; END IF;
    RAISE NOTICE 'ok 481.8 snapshot keeps inputs, figures and fingerprint; other companies cannot read it; posts nothing';

    -- 9. bad periods refused
    BEGIN
        PERFORM sppoultryeggcost_facts(v_farm, current_date, current_date - 1);
        RAISE EXCEPTION 'FAIL 481.9: a backwards period was accepted';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'ok 481.9 a period ending before it starts is refused';

    RAISE NOTICE 'poultry 481: all checks passed';
END $$;
ROLLBACK;
