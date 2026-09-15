-- Behavioural checks for migration 267: valuation and the cost-layer audit.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates items, lots and deliberate corruption.
--
--   psql ... -X -c "BEGIN;" -f poultry-cost-layer-guards.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 267
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **The audit is silent when healthy and specific when not.** A diagnostic that
-- cries wolf gets switched off, and one that stays quiet through real corruption
-- is worse than none. Section A builds a clean item and asserts silence;
-- sections C to E break one thing at a time and assert that exactly that thing
-- is named.
--
-- The rest:
--   1. Operational value and deferred value are DIFFERENT numbers, and an
--      expensed item reports a real operational value with zero deferred.
--   2. Consuming stock moves both down together.
--   3. Stock that leaves without drawing a lot is reported as Stranded on a
--      deferring item and as mere Drift where nothing is deferred -- the
--      distinction Phase 3 needs to prioritise the clean-up.
--   4. The two unsafe-reversal guards, which predate this work, still refuse.

DO $t$
DECLARE
    v_farm text;
    v_defItem integer; v_expItem integer;
    v_defLot integer;  v_expLot integer;
    v_v record;
    v_rec integer;
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

    v_defItem := sppoultryrawmaterialitem_insert(v_farm, 'ZZ G Deferred Maize', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'kg');
    v_expItem := sppoultryrawmaterialitem_insert(v_farm, 'ZZ G Expensed Maize', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'kg',
                                                 'EXPENSE_WHEN_PURCHASED');

    v_defLot := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_defItem,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 1000, p_unitcost => 10, p_totalcost => 10000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 10000, p_createdby => 'ZZ tester');

    v_expLot := sppoultryrawmaterialpurchase_insert(
        p_farmid => v_farm, p_poultryrawmaterialitemid => v_expItem,
        p_suppliername => 'ZZ Supplier', p_purchasedate => (now() at time zone 'utc'),
        p_quantity => 500, p_unitcost => 8, p_totalcost => 4000,
        p_productionunit => 'kg', p_productionunitsperpurchaseunit => 1,
        p_paymentmethod => 'Cash', p_amountpaid => 4000, p_createdby => 'ZZ tester');

    -- =====================================================================
    -- A. Two values, and they are not the same number.
    -- =====================================================================
    SELECT * INTO v_v FROM fnpoultryinventoryvaluation(v_farm)
    WHERE  poultryrawmaterialitemid = v_defItem;
    RAISE NOTICE 'A1. deferred: operational  expect 10000.00  got %', v_v.operationalvalue;
    RAISE NOTICE 'A2. deferred: deferred     expect 10000.00  got %', v_v.deferredvalue;
    RAISE NOTICE 'A3. and no drift           expect     0.000  got %', v_v.quantitydrift;

    SELECT * INTO v_v FROM fnpoultryinventoryvaluation(v_farm)
    WHERE  poultryrawmaterialitemid = v_expItem;
    -- The distinction the whole file exists for: this stock is WORTH 4,000 and
    -- has NOTHING left to expense. Reading only the second would call it
    -- worthless.
    RAISE NOTICE 'A4. expensed: operational  expect  4000.00  got %', v_v.operationalvalue;
    RAISE NOTICE 'A5. expensed: deferred 0   expect     0.00  got %', v_v.deferredvalue;
    RAISE NOTICE 'A6. one open lot           expect        1  got %', v_v.openlots;
    RAISE NOTICE 'A7. and no deferred lot    expect        0  got %', v_v.deferredlots;

    -- A clean farm is a silent audit.
    RAISE NOTICE 'A8. audit is silent        expect        0  got %',
        (SELECT COUNT(*) FROM fnpoultrycostlayeraudit(v_farm) a
          WHERE a.itemid IN (v_defItem, v_expItem));

    -- =====================================================================
    -- B. Consuming moves both values down together.
    -- =====================================================================
    DECLARE
        v_r integer;
    BEGIN
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

        SELECT * INTO v_v FROM fnpoultryinventoryvaluation(v_farm)
        WHERE  poultryrawmaterialitemid = v_defItem;
        RAISE NOTICE 'B1. operational down to 8000 expect  8000.00  got %', v_v.operationalvalue;
        RAISE NOTICE 'B2. deferred down to 8000  expect  8000.00  got %', v_v.deferredvalue;
        RAISE NOTICE 'B3. stock down to 800      expect   800.000  got %', v_v.physicalquantity;
        RAISE NOTICE 'B4. and still no drift     expect     0.000  got %', v_v.quantitydrift;
        RAISE NOTICE 'B5. audit still silent     expect        0  got %',
            (SELECT COUNT(*) FROM fnpoultrycostlayeraudit(v_farm) a WHERE a.itemid = v_defItem);
    END;

    -- =====================================================================
    -- C. Stock leaving without drawing a lot. (the real Phase 2 gap)
    -- =====================================================================
    -- This is what internal use and stock adjustments do today: reduce the
    -- item's quantity and never touch the lots.
    UPDATE poultryrawmaterialitems SET currentquantity = currentquantity - 100
    WHERE  poultryrawmaterialitemid = v_defItem;

    SELECT * INTO v_v FROM fnpoultryinventoryvaluation(v_farm)
    WHERE  poultryrawmaterialitemid = v_defItem;
    RAISE NOTICE 'C1. drift is -100          expect  -100.000  got %', v_v.quantitydrift;
    -- The lots still claim the cost, so 1,000 of it can no longer be recognised.
    RAISE NOTICE 'C2. deferred still claims it expect  8000.00  got %', v_v.deferredvalue;

    RAISE NOTICE 'C3. audit names it         expect StockLeftWithoutDrawingLots  got %',
        (SELECT a.finding FROM fnpoultrycostlayeraudit(v_farm) a WHERE a.itemid = v_defItem LIMIT 1);
    -- On a DEFERRING item this is money, not bookkeeping. The severity says so.
    RAISE NOTICE 'C4. and calls it Stranded  expect Stranded  got %',
        (SELECT a.severity FROM fnpoultrycostlayeraudit(v_farm) a WHERE a.itemid = v_defItem LIMIT 1);

    -- The same drift on an item with nothing deferred is only Drift.
    UPDATE poultryrawmaterialitems SET currentquantity = currentquantity - 100
    WHERE  poultryrawmaterialitemid = v_expItem;
    RAISE NOTICE 'C5. same drift, but Drift  expect    Drift  got %',
        (SELECT a.severity FROM fnpoultrycostlayeraudit(v_farm) a WHERE a.itemid = v_expItem LIMIT 1);

    -- =====================================================================
    -- D. Corruption is named as corruption.
    -- =====================================================================
    -- An empty lot still holding deferred cost: nothing can draw it now.
    DECLARE
        v_orphan integer;
    BEGIN
        INSERT INTO poultryrawmaterialpurchases
            (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
             productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod,
             deferredtotalcost, deferredremainingcost)
        VALUES (v_farm, v_defItem, now(), 10, 10, 100, 1, 0, 'EXPENSE_WHEN_CONSUMED', 100, 100)
        RETURNING poultryrawmaterialpurchaseid INTO v_orphan;

        RAISE NOTICE 'D1. empty lot flagged      expect DeferredOnEmptyLot  got %',
            (SELECT a.finding FROM fnpoultrycostlayeraudit(v_farm) a WHERE a.purchaseid = v_orphan);
        RAISE NOTICE 'D2. as Stranded            expect Stranded  got %',
            (SELECT a.severity FROM fnpoultrycostlayeraudit(v_farm) a WHERE a.purchaseid = v_orphan);
        RAISE NOTICE 'D3. with the amount        expect   100.00  got %',
            (SELECT a.amount FROM fnpoultrycostlayeraudit(v_farm) a WHERE a.purchaseid = v_orphan);
    END;

    -- An expensed lot carrying deferred cost would double-expense on use.
    DECLARE
        v_bad integer;
    BEGIN
        INSERT INTO poultryrawmaterialpurchases
            (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
             productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod,
             deferredtotalcost, deferredremainingcost)
        VALUES (v_farm, v_expItem, now(), 10, 10, 100, 1, 10, 'EXPENSE_WHEN_PURCHASED', 100, 100)
        RETURNING poultryrawmaterialpurchaseid INTO v_bad;

        RAISE NOTICE 'D4. double-expense risk    expect ExpensedLotCarriesDeferred  got %',
            (SELECT a.finding FROM fnpoultrycostlayeraudit(v_farm) a WHERE a.purchaseid = v_bad);
        RAISE NOTICE 'D5. and it is Corrupt      expect  Corrupt  got %',
            (SELECT a.severity FROM fnpoultrycostlayeraudit(v_farm) a WHERE a.purchaseid = v_bad);
    END;

    -- =====================================================================
    -- E. The farm summary keeps the two apart.
    -- =====================================================================
    DECLARE
        v_s record;
    BEGIN
        SELECT * INTO v_s FROM sppoultryinventoryvaluation_summary(v_farm);
        -- It deliberately does NOT add up to one "inventory value".
        RAISE NOTICE 'E1. operational > deferred expect        t  got %',
            (v_s.operationalvalue > v_s.deferredvalue);
        RAISE NOTICE 'E2. drift is surfaced      expect        t  got %', (v_s.itemswithdrift > 0);
        RAISE NOTICE 'E3. findings are counted   expect        t  got %', (v_s.auditfindings > 0);
    END;

    -- =====================================================================
    -- F. The pre-existing unsafe-reversal guards still refuse.
    -- =====================================================================
    -- Section 29: a lot that has been drawn from cannot be deleted.
    BEGIN
        PERFORM sppoultryrawmaterialpurchase_delete(v_defLot, v_farm);
        RAISE NOTICE 'F1. deleting a drawn lot   <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'F1. deleting a drawn lot   blocked: %', left(SQLERRM, 60);
    END;

    -- Section 30/72: a production batch whose feed has been eaten cannot be
    -- reversed. Built here end to end so the guard is exercised, not assumed.
    DECLARE
        v_feed integer; v_batch integer; v_r2 integer;
    BEGIN
        v_feed := sppoultryrawmaterialitem_insert(v_farm, 'ZZ G Feed', 'FinishedFeed', 'kg', 0, NULL, 'FIFO', 'kg');
        INSERT INTO poultryfeedproductionbatches
            (farmid, batchnumber, productiondate, finishedfeeditemid, quantityproduced, outputunit, status, createdby)
        VALUES (v_farm, 'ZZ-G-1', (now() at time zone 'utc'), v_feed, 100, 'kg', 'Draft', 'ZZ tester')
        RETURNING poultryfeedproductionbatchid INTO v_batch;
        INSERT INTO poultryfeedproductionbatchlines
            (poultryfeedproductionbatchid, ingredientitemid, quantityused, inventoryquantityused, unitofmeasure, sortorder)
        VALUES (v_batch, v_defItem, 100, 100, 'kg', 1);

        PERFORM sppoultryfeedproductionbatch_post(v_farm, v_batch, 'ZZ tester');

        -- Eat some of what it made.
        INSERT INTO productionrecords
            (farmid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
             noofbirdsleft, feedkg, production9am, production12pm, production4pm,
             totalproduction, sourcetype)
        VALUES (v_farm, 'ZZ tester', 20, 140, CURRENT_DATE, 100, 0, 100, 0, 0, 0, 0, 0,
                'ManualSingleFlock')
        RETURNING id INTO v_r2;
        PERFORM sppoultryproductionrawmaterialsync(
            p_farmid => v_farm, p_productionid => v_r2, p_createdby => 'ZZ tester',
            p_feedsjson => ('[{"itemId":' || v_feed::text || ',"qty":30}]'));

        BEGIN
            PERFORM sppoultryfeedproductionbatch_reverse(v_farm, v_batch, 'ZZ tester', 'should be blocked');
            RAISE NOTICE 'F2. reversing eaten feed   <-- BUG, allowed';
        EXCEPTION WHEN others THEN
            RAISE NOTICE 'F2. reversing eaten feed   blocked: %', left(SQLERRM, 60);
        END;
    END;
END
$t$;
