-- Behavioural checks for migration 268: the read surface for cost recognition.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates items, lots, consumption and a feed
-- production batch.
--
--   psql ... -X -c "BEGIN;" -f poultry-cost-recognition-reads.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 268
-- ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **A usage that recognises nothing is not a usage that cost nothing.** Section
-- C consumes 800 cedis of premix that was expensed at purchase: operational cost
-- 800, recognised cost 0. A screen showing only the second would tell an
-- expense-at-purchase farm -- the default, and today every farm on the system --
-- that all of its feed is free. Both numbers are returned, and a status string
-- says in words which case the row is in so no caller has to read meaning into a
-- zero.
--
-- The rest:
--   1. A lot reports its own snapshot, not today's farm setting.
--   2. Deferred cost per unit is per PRODUCTION unit, so it is comparable with
--      the production unit cost printed beside it.
--   3. A draw across two lots reports two cost layers and the sum of both.
--   4. Feed production shows what the batch COST and, separately and lower, what
--      it CARRIED FORWARD -- additional costs are in the first and not the
--      second.
--   5. Every column that existed before 268 still reads the same value.

DO $t$
DECLARE
    v_farm text;
    v_defItem integer; v_expItem integer; v_feedItem integer; v_pureItem integer;
    v_defLot integer;  v_expLot integer;  v_defLot2 integer; v_pureLot integer;
    v_p record;
    v_u record;
    v_b record;
    v_r integer;
BEGIN
    SELECT f.farmid INTO v_farm
    FROM   farms f
    WHERE  f.type = 'Poultry'
      AND  f.farmid ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ORDER  BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No uuid-shaped poultry company to test against.'; END IF;
    RAISE NOTICE '   using poultry farm %', v_farm;

    DELETE FROM poultryfinancialsettings WHERE farmid = v_farm;
    PERFORM sppoultryfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');

    -- Maize follows the farm default (defer). Premix overrides to expense at
    -- purchase, so the two live side by side in every read below.
    v_defItem := sppoultryrawmaterialitem_insert(v_farm, 'ZZ R Deferred Maize', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'kg');
    v_expItem := sppoultryrawmaterialitem_insert(v_farm, 'ZZ R Expensed Premix', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'kg',
                                                 'EXPENSE_WHEN_PURCHASED');

    v_defLot := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_defItem,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc') - interval '3 days',
        p_quantity => 1000, p_unitcost => 10, p_totalcost => 10000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 10000, p_createdby => 'ZZ tester');

    v_expLot := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_expItem,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc') - interval '3 days',
        p_quantity => 500, p_unitcost => 8, p_totalcost => 4000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 4000, p_createdby => 'ZZ tester');

    -- =====================================================================
    -- A. The purchase read carries the snapshot and the deferred balance.
    -- =====================================================================
    SELECT * INTO v_p FROM sppoultryrawmaterialpurchase_getall(v_farm) g
    WHERE  g.poultryrawmaterialpurchaseid = v_defLot;
    RAISE NOTICE 'A1. deferred lot method    expect EXPENSE_WHEN_CONSUMED  got %', v_p.costrecognitionmethod;
    RAISE NOTICE 'A2. whole cost deferred    expect 10000.00  got %', v_p.deferredtotalcost;
    RAISE NOTICE 'A3. none of it expensed    expect 10000.00  got %', v_p.deferredremainingcost;
    RAISE NOTICE 'A4. deferred per kg        expect 10.0000  got %', v_p.deferredunitcost;
    RAISE NOTICE 'A5. status in words        expect Deferred - not yet expensed  got %', v_p.costrecognitionstatus;

    SELECT * INTO v_p FROM sppoultryrawmaterialpurchase_getall(v_farm) g
    WHERE  g.poultryrawmaterialpurchaseid = v_expLot;
    RAISE NOTICE 'A6. override wins          expect EXPENSE_WHEN_PURCHASED  got %', v_p.costrecognitionmethod;
    RAISE NOTICE 'A7. nothing deferred       expect     0.00  got %', v_p.deferredtotalcost;
    -- Zero per kg, not NULL: there IS stock in this lot and it owes the P&L
    -- nothing per unit. NULL is reserved for a lot with no stock left at all
    -- (D6), where a rate would be a division by zero.
    RAISE NOTICE 'A8. deferred rate is zero  expect   0.0000  got %', COALESCE(v_p.deferredunitcost::text, '<NULL>');
    RAISE NOTICE 'A9. status in words        expect Expensed at purchase  got %', v_p.costrecognitionstatus;
    -- The columns that existed before 268 must not have moved.
    RAISE NOTICE 'A10. totalcost unchanged   expect  4000.00  got %', v_p.totalcost;
    RAISE NOTICE 'A11. balance unchanged     expect     0.00  got %', v_p.balance;
    RAISE NOTICE 'A12. prod unit cost kept   expect   8.0000  got %', v_p.productionunitcost;
    RAISE NOTICE 'A13. item name kept        expect ZZ R Expensed Premix  got %', v_p.itemname;

    -- =====================================================================
    -- B. A deferred consumption: cost drawn AND cost recognised.
    -- =====================================================================
    INSERT INTO productionrecords
        (farmid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
         noofbirdsleft, feedkg, production9am, production12pm, production4pm,
         totalproduction, sourcetype)
    VALUES (v_farm, 'ZZ tester', 20, 140, CURRENT_DATE, 100, 0, 100, 0, 0, 0, 0, 0,
            'ManualSingleFlock')
    RETURNING id INTO v_r;

    PERFORM sppoultryproductionrawmaterialsync(
        p_farmid => v_farm, p_productionid => v_r, p_createdby => 'ZZ tester',
        p_feedsjson => ('[{"itemId":' || v_defItem::text || ',"qty":200}]'));

    SELECT * INTO v_u FROM sppoultryrawmaterialusage_gethistory(v_farm, v_defItem) h
    WHERE  h.productionrecordid = v_r;
    RAISE NOTICE 'B1. stock drawn was worth  expect  2000.00  got %', v_u.operationalcost;
    RAISE NOTICE 'B2. and all of it expensed expect  2000.00  got %', v_u.recognizedcost;
    RAISE NOTICE 'B3. out of one cost layer  expect        1  got %', v_u.costlayercount;
    RAISE NOTICE 'B4. status in words        expect Expensed at consumption  got %', v_u.costrecognitionstatus;
    RAISE NOTICE 'B5. quantity column kept   expect  200.000  got %', v_u.quantityused;

    SELECT * INTO v_p FROM sppoultryrawmaterialpurchase_getall(v_farm) g
    WHERE  g.poultryrawmaterialpurchaseid = v_defLot;
    RAISE NOTICE 'B6. lot owes 8000 now      expect  8000.00  got %', v_p.deferredremainingcost;
    -- 8,000 over 800 kg. The rate is unchanged because the draw was pro rata.
    RAISE NOTICE 'B7. rate still 10 per kg   expect  10.0000  got %', v_p.deferredunitcost;

    -- =====================================================================
    -- C. An expense-at-purchase consumption. THE CLAIM.
    -- =====================================================================
    INSERT INTO productionrecords
        (farmid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
         noofbirdsleft, feedkg, production9am, production12pm, production4pm,
         totalproduction, sourcetype)
    VALUES (v_farm, 'ZZ tester', 20, 140, CURRENT_DATE, 100, 0, 100, 0, 0, 0, 0, 0,
            'ManualSingleFlock')
    RETURNING id INTO v_r;

    PERFORM sppoultryproductionrawmaterialsync(
        p_farmid => v_farm, p_productionid => v_r, p_createdby => 'ZZ tester',
        p_feedsjson => ('[{"itemId":' || v_expItem::text || ',"qty":100}]'));

    SELECT * INTO v_u FROM sppoultryrawmaterialusage_gethistory(v_farm, v_expItem) h
    WHERE  h.productionrecordid = v_r;
    -- The premix was NOT free. It cost 800 and the farm paid for it three days
    -- ago; that is what operational cost is for.
    RAISE NOTICE 'C1. the premix cost 800    expect   800.00  got %', v_u.operationalcost;
    RAISE NOTICE 'C2. but recognises nothing expect     0.00  got %', v_u.recognizedcost;
    RAISE NOTICE 'C3. and says why           expect Already expensed at purchase  got %', v_u.costrecognitionstatus;
    RAISE NOTICE 'C4. still one cost layer   expect        1  got %', v_u.costlayercount;

    -- =====================================================================
    -- D. A draw across two lots reports two layers.
    -- =====================================================================
    v_defLot2 := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_defItem,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc') - interval '1 day',
        p_quantity => 500, p_unitcost => 20, p_totalcost => 10000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 10000, p_createdby => 'ZZ tester');

    INSERT INTO productionrecords
        (farmid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
         noofbirdsleft, feedkg, production9am, production12pm, production4pm,
         totalproduction, sourcetype)
    VALUES (v_farm, 'ZZ tester', 20, 140, CURRENT_DATE, 100, 0, 100, 0, 0, 0, 0, 0,
            'ManualSingleFlock')
    RETURNING id INTO v_r;

    -- FIFO: 800 kg out of the old lot at 10, then 100 kg out of the new one at 20.
    PERFORM sppoultryproductionrawmaterialsync(
        p_farmid => v_farm, p_productionid => v_r, p_createdby => 'ZZ tester',
        p_feedsjson => ('[{"itemId":' || v_defItem::text || ',"qty":900}]'));

    SELECT * INTO v_u FROM sppoultryrawmaterialusage_gethistory(v_farm, v_defItem) h
    WHERE  h.productionrecordid = v_r;
    RAISE NOTICE 'D1. 8000 + 2000 drawn      expect 10000.00  got %', v_u.operationalcost;
    RAISE NOTICE 'D2. and all of it deferred expect 10000.00  got %', v_u.recognizedcost;
    RAISE NOTICE 'D3. across two cost layers expect        2  got %', v_u.costlayercount;

    SELECT * INTO v_p FROM sppoultryrawmaterialpurchase_getall(v_farm) g
    WHERE  g.poultryrawmaterialpurchaseid = v_defLot;
    RAISE NOTICE 'D4. old lot fully expensed expect     0.00  got %', v_p.deferredremainingcost;
    RAISE NOTICE 'D5. and says so            expect Deferred - fully expensed  got %', v_p.costrecognitionstatus;
    -- An emptied lot has no rate, and NULL is the honest answer rather than 0.
    RAISE NOTICE 'D6. no rate on empty lot   expect <NULL>  got %', COALESCE(v_p.deferredunitcost::text, '<NULL>');

    -- =====================================================================
    -- E. Feed production: what it COST and what it CARRIED FORWARD.
    -- =====================================================================
    -- Left standing: 400 kg of deferred maize (lot 2, 8,000 deferred) and 400 kg
    -- of expensed premix at 8.
    DECLARE
        v_batch integer;
    BEGIN
        v_feedItem := sppoultryrawmaterialitem_insert(v_farm, 'ZZ R Mixed Feed', 'FinishedFeed', 'kg', 0, NULL, 'FIFO', 'kg');

        INSERT INTO poultryfeedproductionbatches
            (farmid, batchnumber, productiondate, finishedfeeditemid, quantityproduced, outputunit, status, createdby)
        VALUES (v_farm, 'ZZ-R-1', (now() at time zone 'utc'), v_feedItem, 150, 'kg', 'Draft', 'ZZ tester')
        RETURNING poultryfeedproductionbatchid INTO v_batch;

        INSERT INTO poultryfeedproductionbatchlines
            (poultryfeedproductionbatchid, ingredientitemid, quantityused, inventoryquantityused, unitofmeasure, sortorder)
        VALUES (v_batch, v_defItem, 100, 100, 'kg', 1),
               (v_batch, v_expItem, 100, 100, 'kg', 2);

        -- Milling. Unpaid, so no cash account is needed and no cash moves.
        INSERT INTO poultryfeedproductionadditionalcosts
            (poultryfeedproductionbatchid, costtype, amount, paymentstatus, amountpaid, sortorder)
        VALUES (v_batch, 'Milling', 500, 'Unpaid', 0, 1);

        -- A draft batch has no lot yet, and must not pretend otherwise.
        SELECT * INTO v_b FROM sppoultryfeedproductionbatch_getbyid_rs1(v_farm, v_batch);
        RAISE NOTICE 'E1. draft carries nothing  expect     0.00  got %', v_b.deferredproductioncost;
        RAISE NOTICE 'E2. and says so            expect Not posted  got %', v_b.costrecognitionstatus;

        PERFORM sppoultryfeedproductionbatch_post(v_farm, v_batch, 'ZZ tester');

        SELECT * INTO v_b FROM sppoultryfeedproductionbatch_getbyid_rs1(v_farm, v_batch);
        -- 2,000 of maize + 800 of premix + 500 of milling.
        RAISE NOTICE 'E3. ingredients cost       expect  2800.00  got %', v_b.totalingredientcost;
        RAISE NOTICE 'E4. plus milling           expect   500.00  got %', v_b.totaladditionalcost;
        RAISE NOTICE 'E5. total production cost  expect  3300.00  got %', v_b.totalproductioncost;
        -- Only the maize was still waiting. The premix was expensed three days
        -- ago and the milling is an expense of its own; charging either again
        -- when this feed is eaten is the double charge Phase 2 exists to stop.
        RAISE NOTICE 'E6. carried forward        expect  2000.00  got %', v_b.deferredproductioncost;
        RAISE NOTICE 'E7. none of it eaten yet   expect  2000.00  got %', v_b.deferredremainingcost;
        RAISE NOTICE 'E8. cost per kg unchanged  expect  22.0000  got %', v_b.costperoutputunit;
        RAISE NOTICE 'E9. deferred per kg        expect  13.3333  got %', v_b.deferredunitcost;
        RAISE NOTICE 'E10. status in words       expect Part of the cost already expensed at purchase  got %', v_b.costrecognitionstatus;
        RAISE NOTICE 'E11. batch number kept     expect ZZ-R-1  got %', v_b.batchnumber;
        RAISE NOTICE 'E12. posted                expect Posted  got %', v_b.status;
    END;

    -- =====================================================================
    -- F. A batch mixed entirely from expensed stock carries nothing.
    -- =====================================================================
    DECLARE
        v_batch2 integer; v_feed2 integer;
    BEGIN
        v_feed2 := sppoultryrawmaterialitem_insert(v_farm, 'ZZ R Pure Feed', 'FinishedFeed', 'kg', 0, NULL, 'FIFO', 'kg');

        INSERT INTO poultryfeedproductionbatches
            (farmid, batchnumber, productiondate, finishedfeeditemid, quantityproduced, outputunit, status, createdby)
        VALUES (v_farm, 'ZZ-R-2', (now() at time zone 'utc'), v_feed2, 100, 'kg', 'Draft', 'ZZ tester')
        RETURNING poultryfeedproductionbatchid INTO v_batch2;

        INSERT INTO poultryfeedproductionbatchlines
            (poultryfeedproductionbatchid, ingredientitemid, quantityused, inventoryquantityused, unitofmeasure, sortorder)
        VALUES (v_batch2, v_expItem, 100, 100, 'kg', 1);

        PERFORM sppoultryfeedproductionbatch_post(v_farm, v_batch2, 'ZZ tester');

        SELECT * INTO v_b FROM sppoultryfeedproductionbatch_getbyid_rs1(v_farm, v_batch2);
        RAISE NOTICE 'F1. it cost 800            expect   800.00  got %', v_b.totalproductioncost;
        RAISE NOTICE 'F2. and carries nothing    expect     0.00  got %', v_b.deferredproductioncost;
        RAISE NOTICE 'F3. zero deferred per kg   expect   0.0000  got %', COALESCE(v_b.deferredunitcost::text, '<NULL>');
        RAISE NOTICE 'F4. status in words        expect Ingredients already expensed at purchase  got %', v_b.costrecognitionstatus;
        RAISE NOTICE 'F5. lot method follows it  expect EXPENSE_WHEN_PURCHASED  got %', v_b.costrecognitionmethod;
    END;

    -- =====================================================================
    -- G. A reversed usage still reads back, and says it was reversed.
    -- =====================================================================
    INSERT INTO productionrecords
        (farmid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
         noofbirdsleft, feedkg, production9am, production12pm, production4pm,
         totalproduction, sourcetype)
    VALUES (v_farm, 'ZZ tester', 20, 140, CURRENT_DATE, 100, 0, 100, 0, 0, 0, 0, 0,
            'ManualSingleFlock')
    RETURNING id INTO v_r;

    PERFORM sppoultryproductionrawmaterialsync(
        p_farmid => v_farm, p_productionid => v_r, p_createdby => 'ZZ tester',
        p_feedsjson => ('[{"itemId":' || v_defItem::text || ',"qty":50}]'));

    SELECT * INTO v_u FROM sppoultryrawmaterialusage_gethistory(v_farm, v_defItem) h
    WHERE  h.productionrecordid = v_r;
    RAISE NOTICE 'G1. 50 kg at 20 recognised expect  1000.00  got %', v_u.recognizedcost;

    -- Empty feed list = pure reversal. The usage row is kept and flagged.
    PERFORM sppoultryproductionrawmaterialsync(
        p_farmid => v_farm, p_productionid => v_r, p_createdby => 'ZZ tester',
        p_feedsjson => '[]');

    SELECT * INTO v_u FROM sppoultryrawmaterialusage_gethistory(v_farm, v_defItem) h
    WHERE  h.productionrecordid = v_r;
    RAISE NOTICE 'G2. the row survives       expect t  got %', (v_u.poultryrawmaterialusageid IS NOT NULL);
    RAISE NOTICE 'G3. flagged reversed       expect t  got %', v_u.isreversed;
    RAISE NOTICE 'G4. status in words        expect Reversed  got %', v_u.costrecognitionstatus;
    -- The allocations are kept too, so what it drew is still legible after the
    -- fact -- which is the whole point of an append-only ledger.
    RAISE NOTICE 'G5. what it drew is kept   expect  1000.00  got %', v_u.recognizedcost;

    -- =====================================================================
    -- H. The two wrappers return exactly what 267 returns.
    -- =====================================================================
    RAISE NOTICE 'H1. valuation wrapper rows expect %  got %',
        (SELECT COUNT(*) FROM fnpoultryinventoryvaluation(v_farm)),
        (SELECT COUNT(*) FROM sppoultryinventoryvaluation_getall(v_farm));
    RAISE NOTICE 'H2. audit wrapper rows     expect %  got %',
        (SELECT COUNT(*) FROM fnpoultrycostlayeraudit(v_farm)),
        (SELECT COUNT(*) FROM sppoultrycostlayeraudit_getall(v_farm));
    RAISE NOTICE 'H3. deferred maize value   expect %  got %',
        (SELECT v.deferredvalue FROM fnpoultryinventoryvaluation(v_farm) v
          WHERE v.poultryrawmaterialitemid = v_defItem),
        (SELECT w.deferredvalue FROM sppoultryinventoryvaluation_getall(v_farm) w
          WHERE w.poultryrawmaterialitemid = v_defItem);
    -- Premix is worth real money and owes the P&L nothing. Both numbers, always.
    -- 500 kg bought, 100 eaten in C, 100 into each of the two batches: 200 left
    -- at 8.
    RAISE NOTICE 'H4. premix operational     expect  1600.00  got %',
        (SELECT w.operationalvalue FROM sppoultryinventoryvaluation_getall(v_farm) w
          WHERE w.poultryrawmaterialitemid = v_expItem);
    RAISE NOTICE 'H5. premix deferred        expect     0.00  got %',
        (SELECT w.deferredvalue FROM sppoultryinventoryvaluation_getall(v_farm) w
          WHERE w.poultryrawmaterialitemid = v_expItem);

    -- =====================================================================
    -- I. Nothing above wrote a single cedi of cash.
    -- =====================================================================
    -- Consumption recognition is NonCash by construction (266); the read layer
    -- must not have introduced a cash movement of its own.
    RAISE NOTICE 'I1. no cash on recognition expect        0  got %',
        (SELECT COUNT(*) FROM poultrycashtransactions c
          WHERE c.farmid = v_farm
            AND c.sourcetype IN ('PoultryFeedConsumption', 'PoultryMedicationConsumption'));
END
$t$;
