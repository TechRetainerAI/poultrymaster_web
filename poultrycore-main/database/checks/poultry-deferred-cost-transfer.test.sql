-- Behavioural checks for migration 265: opening and transferring deferred cost.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates items, purchases and a feed production
-- batch.
--
--   psql ... -X -c "BEGIN;" -f poultry-deferred-cost-transfer.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 265
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **Feed production is a transfer, not an expense, and it transfers only what
-- was actually deferred.** The brief's own mixed example is section C: maize
-- deferred, premix already expensed. The feed's operational cost must be the
-- full recipe, its deferred cost only the maize -- because charging the premix
-- again when the feed is eaten is exactly the double-expense this whole phase
-- exists to prevent.
--
-- The rest:
--   1. A deferred purchase opens with its whole COST deferred -- not its amount
--      paid. Paying later is a cash event, not a costing one.
--   2. An expensed purchase opens with nothing deferred.
--   3. Deferred cost is conserved through production: what the ingredients give
--      up is exactly what the finished feed receives.
--   4. A batch mixed entirely from expensed stock produces a lot that says it
--      has nothing left to expense, whatever the farm setting says.
--   5. Additional costs (labour, milling) are NOT deferred -- they are already
--      expenses in their own right.
--   6. Bought-during-production ingredients get a real snapshot.

DO $t$
DECLARE
    v_farm   text;
    v_maize  integer;
    v_premix integer;
    v_feed   integer;
    v_lotA   integer;
    v_lotP   integer;
    v_batch  integer;
    v_fedlot integer;
    v_exp0   numeric;
BEGIN
    SELECT f.farmid INTO v_farm
    FROM   farms f
    WHERE  f.type = 'Poultry'
      AND  f.farmid ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ORDER  BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No uuid-shaped poultry company to test against.'; END IF;
    RAISE NOTICE '   using poultry farm %', v_farm;

    DELETE FROM poultryfinancialsettings WHERE farmid = v_farm;
    -- Defer feed. Medication is left alone, so the two stay visibly independent.
    PERFORM sppoultryfinancialsettings_upsert(
        v_farm, 'EXPENSE_WHEN_CONSUMED', 'EXPENSE_WHEN_PURCHASED', NULL, 'ZZ tester');

    SELECT COALESCE(SUM(e.amount), 0) INTO v_exp0 FROM expense e WHERE e.farmid::text = v_farm;

    v_maize  := sppoultryrawmaterialitem_insert(v_farm, 'ZZ T Maize',  'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'kg');
    -- Premix opts OUT of the farm's deferral: its cost is expensed at purchase.
    v_premix := sppoultryrawmaterialitem_insert(v_farm, 'ZZ T Premix', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'kg',
                                                'EXPENSE_WHEN_PURCHASED');
    v_feed   := sppoultryrawmaterialitem_insert(v_farm, 'ZZ T Layer Feed', 'FinishedFeed', 'kg', 0, NULL, 'FIFO', 'kg');

    -- =====================================================================
    -- A. A deferred purchase opens with its whole cost deferred.
    -- =====================================================================
    -- Deliberately part-paid: what is deferred is the COST of the stock, not
    -- what has been handed over. Paying later is a cash event.
    v_lotA := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_maize,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 1000, p_unitcost => 10, p_totalcost => 10000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 4000, p_createdby => 'ZZ tester');

    RAISE NOTICE 'A1. snapshotted consumed   expect EXPENSE_WHEN_CONSUMED  got %',
        (SELECT costrecognitionmethod FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lotA);
    RAISE NOTICE 'A2. whole COST deferred    expect 10000.00  got %',
        (SELECT deferredtotalcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lotA);
    RAISE NOTICE 'A3. not the amount paid    expect 10000.00  got %',
        (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lotA);
    RAISE NOTICE 'A4. and no P&L yet         expect     0.00  got %',
        ((SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm) - v_exp0);

    -- =====================================================================
    -- B. An expensed purchase opens with nothing deferred.
    -- =====================================================================
    v_lotP := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_premix,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 100, p_unitcost => 20, p_totalcost => 2000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 2000, p_createdby => 'ZZ tester');

    RAISE NOTICE 'B1. snapshotted purchased  expect EXPENSE_WHEN_PURCHASED  got %',
        (SELECT costrecognitionmethod FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lotP);
    RAISE NOTICE 'B2. nothing deferred       expect     0.00  got %',
        (SELECT deferredtotalcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lotP);
    -- Its cost went to the P&L the ordinary way, as it was paid.
    RAISE NOTICE 'B3. but it WAS expensed    expect  2000.00  got %',
        ((SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm) - v_exp0);

    -- =====================================================================
    -- C. Feed production: the mixed case the brief calls out.
    -- =====================================================================
    -- 500 kg maize (deferred, 5,000) + 100 kg premix (expensed, 2,000)
    -- -> 600 kg of feed. Operational cost 7,000; deferred cost 5,000.
    INSERT INTO poultryfeedproductionbatches
        (farmid, batchnumber, productiondate, finishedfeeditemid, quantityproduced, outputunit, status, createdby)
    VALUES (v_farm, 'ZZ-FP-1', (now() at time zone 'utc'), v_feed, 600, 'kg', 'Draft', 'ZZ tester')
    RETURNING poultryfeedproductionbatchid INTO v_batch;

    INSERT INTO poultryfeedproductionbatchlines
        (poultryfeedproductionbatchid, ingredientitemid, quantityused, inventoryquantityused, unitofmeasure, sortorder)
    VALUES (v_batch, v_maize, 500, 500, 'kg', 1),
           (v_batch, v_premix, 100, 100, 'kg', 2);

    PERFORM sppoultryfeedproductionbatch_post(v_farm, v_batch, 'ZZ tester');

    SELECT poultryrawmaterialpurchaseid INTO v_fedlot
    FROM   poultryrawmaterialpurchases
    WHERE  sourcefeedproductionbatchid = v_batch AND poultryrawmaterialitemid = v_feed;

    -- The operational cost is the FULL recipe. Cost per kg, formula analysis and
    -- the production reports all read this and must not move.
    RAISE NOTICE 'C1. operational cost is all expect  7000.00  got %',
        (SELECT totalcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_fedlot);
    -- **THE** check. Only the maize may ever reach the P&L again.
    RAISE NOTICE 'C2. deferred is maize only expect  5000.00  got %',
        (SELECT deferredtotalcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_fedlot);
    RAISE NOTICE 'C3. lot says it defers     expect EXPENSE_WHEN_CONSUMED  got %',
        (SELECT costrecognitionmethod FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_fedlot);
    RAISE NOTICE 'C4. 600 kg of feed exists  expect   600.00  got %',
        (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_fedlot);

    -- Conservation: what the ingredients gave up is what the feed received.
    RAISE NOTICE 'C5. maize lot gave up 5000 expect  5000.00  got %',
        (10000 - (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lotA));
    RAISE NOTICE 'C6. premix gave up nothing expect     0.00  got %',
        (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lotP);
    -- Nothing was created or destroyed by mixing feed.
    RAISE NOTICE 'C7. deferred is conserved  expect     0.00  got %',
        ((SELECT COALESCE(SUM(p.deferredremainingcost), 0) FROM poultryrawmaterialpurchases p
           WHERE p.farmid = v_farm AND p.poultryrawmaterialitemid IN (v_maize, v_premix, v_feed))
         - 10000);

    -- Production is a TRANSFER. It must not have touched the P&L.
    RAISE NOTICE 'C8. production expensed 0  expect  2000.00  got %',
        ((SELECT COALESCE(SUM(e.amount), 0) FROM expense e WHERE e.farmid::text = v_farm) - v_exp0);

    -- =====================================================================
    -- D. A batch of purely expensed stock defers nothing.
    -- =====================================================================
    DECLARE
        v_feed2 integer; v_batch2 integer; v_fedlot2 integer;
    BEGIN
        v_feed2 := sppoultryrawmaterialitem_insert(v_farm, 'ZZ T Feed 2', 'FinishedFeed', 'kg', 0, NULL, 'FIFO', 'kg');
        -- Section C consumed the whole first premix lot, so buy more. Still
        -- expensed at purchase: the item overrides the farm's deferral.
        PERFORM sppoultryrawmaterialpurchase_insert(
            p_farmid => v_farm, p_poultryrawmaterialitemid => v_premix,
            p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
            p_quantity => 50, p_unitcost => 20, p_totalcost => 1000,
            p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
            p_paymentmethod => 'Cash', p_amountpaid => 1000, p_createdby => 'ZZ tester');

        INSERT INTO poultryfeedproductionbatches
            (farmid, batchnumber, productiondate, finishedfeeditemid, quantityproduced, outputunit, status, createdby)
        VALUES (v_farm, 'ZZ-FP-2', (now() at time zone 'utc'), v_feed2, 50, 'kg', 'Draft', 'ZZ tester')
        RETURNING poultryfeedproductionbatchid INTO v_batch2;
        INSERT INTO poultryfeedproductionbatchlines
            (poultryfeedproductionbatchid, ingredientitemid, quantityused, inventoryquantityused, unitofmeasure, sortorder)
        VALUES (v_batch2, v_premix, 50, 50, 'kg', 1);

        PERFORM sppoultryfeedproductionbatch_post(v_farm, v_batch2, 'ZZ tester');

        SELECT poultryrawmaterialpurchaseid INTO v_fedlot2
        FROM   poultryrawmaterialpurchases
        WHERE  sourcefeedproductionbatchid = v_batch2 AND poultryrawmaterialitemid = v_feed2;

        -- The farm defers feed, but this batch has nothing left to defer. The
        -- lot must say so rather than claim a deferral it cannot honour.
        RAISE NOTICE 'D1. nothing deferred       expect     0.00  got %',
            (SELECT deferredtotalcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_fedlot2);
        RAISE NOTICE 'D2. lot says so            expect EXPENSE_WHEN_PURCHASED  got %',
            (SELECT costrecognitionmethod FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_fedlot2);
        RAISE NOTICE 'D3. but it still cost 1000 expect  1000.00  got %',
            (SELECT totalcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_fedlot2);
    END;

    -- =====================================================================
    -- E. Additional costs are not deferred.
    -- =====================================================================
    DECLARE
        v_feed3 integer; v_batch3 integer; v_fedlot3 integer;
    BEGIN
        v_feed3 := sppoultryrawmaterialitem_insert(v_farm, 'ZZ T Feed 3', 'FinishedFeed', 'kg', 0, NULL, 'FIFO', 'kg');
        INSERT INTO poultryfeedproductionbatches
            (farmid, batchnumber, productiondate, finishedfeeditemid, quantityproduced, outputunit, status, createdby)
        VALUES (v_farm, 'ZZ-FP-3', (now() at time zone 'utc'), v_feed3, 100, 'kg', 'Draft', 'ZZ tester')
        RETURNING poultryfeedproductionbatchid INTO v_batch3;
        INSERT INTO poultryfeedproductionbatchlines
            (poultryfeedproductionbatchid, ingredientitemid, quantityused, inventoryquantityused, unitofmeasure, sortorder)
        VALUES (v_batch3, v_maize, 100, 100, 'kg', 1);
        -- Milling labour, entered as a production cost.
        INSERT INTO poultryfeedproductionadditionalcosts
            (poultryfeedproductionbatchid, costtype, amount, sortorder)
        VALUES (v_batch3, 'Milling', 300, 1);

        PERFORM sppoultryfeedproductionbatch_post(v_farm, v_batch3, 'ZZ tester');

        SELECT poultryrawmaterialpurchaseid INTO v_fedlot3
        FROM   poultryrawmaterialpurchases
        WHERE  sourcefeedproductionbatchid = v_batch3 AND poultryrawmaterialitemid = v_feed3;

        -- Operational cost carries the milling; deferred cost does not. The
        -- milling is its own expense wherever it was entered, and folding it in
        -- here would expense it again when the feed is eaten.
        RAISE NOTICE 'E1. operational includes it expect  1300.00  got %',
            (SELECT totalcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_fedlot3);
        RAISE NOTICE 'E2. deferred excludes it   expect  1000.00  got %',
            (SELECT deferredtotalcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_fedlot3);
    END;

    -- =====================================================================
    -- F. Bought during production gets a real snapshot.
    -- =====================================================================
    DECLARE
        v_feed4 integer; v_batch4 integer; v_fedlot4 integer; v_bought integer;
    BEGIN
        v_feed4 := sppoultryrawmaterialitem_insert(v_farm, 'ZZ T Feed 4', 'FinishedFeed', 'kg', 0, NULL, 'FIFO', 'kg');
        INSERT INTO poultryfeedproductionbatches
            (farmid, batchnumber, productiondate, finishedfeeditemid, quantityproduced, outputunit, status, createdby)
        VALUES (v_farm, 'ZZ-FP-4', (now() at time zone 'utc'), v_feed4, 200, 'kg', 'Draft', 'ZZ tester')
        RETURNING poultryfeedproductionbatchid INTO v_batch4;
        -- Maize bought during production: the farm defers feed, so it arrives
        -- deferred and passes straight through into the finished feed.
        INSERT INTO poultryfeedproductionbatchlines
            (poultryfeedproductionbatchid, ingredientitemid, quantityused, purchasedquantityused,
             purchasedunitcost, unitofmeasure, suppliername, sortorder)
        VALUES (v_batch4, v_maize, 200, 200, 12, 'kg', 'ZZ Supplier', 1);

        PERFORM sppoultryfeedproductionbatch_post(v_farm, v_batch4, 'ZZ tester');

        SELECT poultryrawmaterialpurchaseid INTO v_bought
        FROM   poultryrawmaterialpurchases
        WHERE  sourcefeedproductionbatchid = v_batch4 AND poultryrawmaterialitemid = v_maize;
        SELECT poultryrawmaterialpurchaseid INTO v_fedlot4
        FROM   poultryrawmaterialpurchases
        WHERE  sourcefeedproductionbatchid = v_batch4 AND poultryrawmaterialitemid = v_feed4;

        RAISE NOTICE 'F1. bought lot snapshotted expect EXPENSE_WHEN_CONSUMED  got %',
            (SELECT costrecognitionmethod FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_bought);
        RAISE NOTICE 'F2. it was fully drawn     expect     0.00  got %',
            (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_bought);
        -- 200 kg at 12 = 2,400, straight through.
        RAISE NOTICE 'F3. and passed through     expect  2400.00  got %',
            (SELECT deferredtotalcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_fedlot4);
    END;
END
$t$;
