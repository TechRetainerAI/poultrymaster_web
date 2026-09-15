-- Behavioural checks for migration 264: deferred cost on the existing layers.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it creates items and purchase lots and consumes
-- them.
--
--   psql ... -X -c "BEGIN;" -f poultry-deferred-cost-layers.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 264
-- (BEGIN;/COMMIT; stripped) ahead of this body inside the same BEGIN; ROLLBACK;.
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **The engine's operational behaviour is unchanged.** 264 rewrites the
-- FIFO/LIFO/HIFO function every consumption path in the system depends on, so
-- section A drives it exactly as it is driven today -- ordering, unit
-- normalisation, the shortfall guard, remainingquantity depletion, the returned
-- unit cost and the allocation rows -- and asserts today's answers. The deferred
-- figures are a second, parallel set of numbers; if any of section A moved, the
-- rewrite broke something.
--
-- The rest:
--   1. FIFO, LIFO and HIFO pick the layers the brief's worked examples say.
--   2. Deferred cost is drawn PRO RATA and a fully drained lot lands on exactly
--      zero -- no rounding crumb left behind that could never be recognised.
--   3. **A lot expensed at purchase contributes NOTHING deferred**, which is
--      what stops the same cost being charged twice.
--   4. Mixed layers work: one draw crossing an expensed lot and a deferred one
--      consumes both physically and defers only the deferred part.
--   5. Purchase-unit lots normalise: a lot bought in bags and consumed in kg
--      defers per kg, not per bag.

DO $t$
DECLARE
    v_farm  text;
    v_item  integer;
    v_u1 integer; v_u2 integer; v_u3 integer;
    v_pA integer; v_pB integer; v_pC integer;
    v_cost numeric;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Poultry' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No poultry company to test against.'; END IF;
    RAISE NOTICE '   using poultry farm %', v_farm;

    -- =====================================================================
    -- A. The engine still behaves exactly as it does today.
    -- =====================================================================
    -- FIFO, two lots, the brief's own numbers: 100 @ 5 then 100 @ 8, draw 120.
    v_item := sppoultryrawmaterialitem_insert(v_farm, 'ZZ FIFO Maize', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'kg');

    INSERT INTO poultryrawmaterialpurchases
        (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
         productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod)
    VALUES (v_farm, v_item, now() - interval '2 days', 100, 5, 500, 1, 100, 'EXPENSE_WHEN_PURCHASED')
    RETURNING poultryrawmaterialpurchaseid INTO v_pA;
    INSERT INTO poultryrawmaterialpurchases
        (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
         productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod)
    VALUES (v_farm, v_item, now() - interval '1 day', 100, 8, 800, 1, 100, 'EXPENSE_WHEN_PURCHASED')
    RETURNING poultryrawmaterialpurchaseid INTO v_pB;

    INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, quantityused, createdby)
    VALUES (v_farm, v_item, 120, 'ZZ tester') RETURNING poultryrawmaterialusageid INTO v_u1;

    v_cost := sppoultryrawmaterialitem_consumebatches(v_farm, v_item, v_u1, 120);

    -- 100 x 5 + 20 x 8 = 660 over 120 units = 5.50/unit.
    RAISE NOTICE 'A1. FIFO unit cost         expect     5.50  got %', ROUND(v_cost, 2);
    RAISE NOTICE 'A2. FIFO total cost        expect   660.00  got %',
        ROUND((SELECT SUM(b.quantitydrawn * b.unitcostatdraw) FROM poultryrawmaterialusagebatch b
                WHERE b.poultryrawmaterialusageid = v_u1), 2);
    RAISE NOTICE 'A3. two allocations        expect        2  got %',
        (SELECT COUNT(*) FROM poultryrawmaterialusagebatch WHERE poultryrawmaterialusageid = v_u1);
    RAISE NOTICE 'A4. oldest lot emptied     expect     0.00  got %',
        (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_pA);
    RAISE NOTICE 'A5. newest lot part-drawn  expect    80.00  got %',
        (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_pB);

    -- LIFO, same numbers, the brief's other answer.
    v_item := sppoultryrawmaterialitem_insert(v_farm, 'ZZ LIFO Maize', 'FeedIngredient', 'kg', 0, NULL, 'LIFO', 'kg');
    INSERT INTO poultryrawmaterialpurchases
        (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
         productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod)
    VALUES (v_farm, v_item, now() - interval '2 days', 100, 5, 500, 1, 100, 'EXPENSE_WHEN_PURCHASED');
    INSERT INTO poultryrawmaterialpurchases
        (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
         productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod)
    VALUES (v_farm, v_item, now() - interval '1 day', 100, 8, 800, 1, 100, 'EXPENSE_WHEN_PURCHASED');
    INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, quantityused, createdby)
    VALUES (v_farm, v_item, 120, 'ZZ tester') RETURNING poultryrawmaterialusageid INTO v_u2;
    v_cost := sppoultryrawmaterialitem_consumebatches(v_farm, v_item, v_u2, 120);
    -- 100 x 8 + 20 x 5 = 900.
    RAISE NOTICE 'A6. LIFO total cost        expect   900.00  got %',
        ROUND((SELECT SUM(b.quantitydrawn * b.unitcostatdraw) FROM poultryrawmaterialusagebatch b
                WHERE b.poultryrawmaterialusageid = v_u2), 2);

    -- HIFO, three lots, draw 150: 100 from the 10 then 50 from the 7.
    v_item := sppoultryrawmaterialitem_insert(v_farm, 'ZZ HIFO Maize', 'FeedIngredient', 'kg', 0, NULL, 'HIFO', 'kg');
    INSERT INTO poultryrawmaterialpurchases
        (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
         productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod)
    VALUES (v_farm, v_item, now() - interval '3 days', 100, 5, 500, 1, 100, 'EXPENSE_WHEN_PURCHASED');
    INSERT INTO poultryrawmaterialpurchases
        (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
         productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod)
    VALUES (v_farm, v_item, now() - interval '2 days', 100, 10, 1000, 1, 100, 'EXPENSE_WHEN_PURCHASED');
    INSERT INTO poultryrawmaterialpurchases
        (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
         productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod)
    VALUES (v_farm, v_item, now() - interval '1 day', 100, 7, 700, 1, 100, 'EXPENSE_WHEN_PURCHASED');
    INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, quantityused, createdby)
    VALUES (v_farm, v_item, 150, 'ZZ tester') RETURNING poultryrawmaterialusageid INTO v_u3;
    v_cost := sppoultryrawmaterialitem_consumebatches(v_farm, v_item, v_u3, 150);
    -- 100 x 10 + 50 x 7 = 1,350.
    RAISE NOTICE 'A7. HIFO total cost        expect  1350.00  got %',
        ROUND((SELECT SUM(b.quantitydrawn * b.unitcostatdraw) FROM poultryrawmaterialusagebatch b
                WHERE b.poultryrawmaterialusageid = v_u3), 2);
    RAISE NOTICE 'A8. cheapest lot untouched expect   100.00  got %',
        (SELECT remainingquantity FROM poultryrawmaterialpurchases
          WHERE poultryrawmaterialitemid = v_item AND unitcost = 5);

    -- And the shortfall guard still fires.
    BEGIN
        PERFORM sppoultryrawmaterialitem_consumebatches(v_farm, v_item, v_u3, 999999);
        RAISE NOTICE 'A9. overdraw               <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'A9. overdraw               blocked: %', left(SQLERRM, 60);
    END;

    -- =====================================================================
    -- B. An expensed lot contributes nothing deferred.
    -- =====================================================================
    -- Every lot in section A is EXPENSE_WHEN_PURCHASED, so not one pesewa of
    -- deferred cost may have appeared anywhere. This is the double-expense
    -- guard, stated as a total.
    RAISE NOTICE 'B1. no deferred drawn      expect     0.00  got %',
        (SELECT COALESCE(SUM(b.deferredcostdrawn), 0) FROM poultryrawmaterialusagebatch b
          WHERE b.poultryrawmaterialusageid IN (v_u1, v_u2, v_u3));
    RAISE NOTICE 'B2. no deferred on the lots expect     0.00  got %',
        (SELECT COALESCE(SUM(p.deferredremainingcost), 0) FROM poultryrawmaterialpurchases p
          WHERE p.farmid = v_farm AND p.poultryrawmaterialitemid = v_item);

    -- =====================================================================
    -- C. A deferred lot draws its cost pro rata and lands on exactly zero.
    -- =====================================================================
    DECLARE
        v_ditem integer; v_dlot integer; v_du integer;
    BEGIN
        v_ditem := sppoultryrawmaterialitem_insert(v_farm, 'ZZ Deferred Maize', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'kg');
        -- A lot whose cost does not divide evenly, so rounding has somewhere to go.
        INSERT INTO poultryrawmaterialpurchases
            (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
             productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod,
             deferredtotalcost, deferredremainingcost)
        VALUES (v_farm, v_ditem, now() - interval '1 day', 3, 33.33, 100.00, 1, 3, 'EXPENSE_WHEN_CONSUMED', 100.00, 100.00)
        RETURNING poultryrawmaterialpurchaseid INTO v_dlot;

        -- Draw one third.
        INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, quantityused, createdby)
        VALUES (v_farm, v_ditem, 1, 'ZZ tester') RETURNING poultryrawmaterialusageid INTO v_du;
        PERFORM sppoultryrawmaterialitem_consumebatches(v_farm, v_ditem, v_du, 1);

        RAISE NOTICE 'C1. a third deferred drawn expect    33.33  got %',
            (SELECT deferredcostdrawn FROM poultryrawmaterialusagebatch WHERE poultryrawmaterialusageid = v_du);
        RAISE NOTICE 'C2. lot keeps the rest    expect    66.67  got %',
            (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_dlot);

        -- Drain the rest. The last draw must land the lot on exactly zero, not
        -- on a crumb that could never be recognised.
        INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, quantityused, createdby)
        VALUES (v_farm, v_ditem, 2, 'ZZ tester') RETURNING poultryrawmaterialusageid INTO v_du;
        PERFORM sppoultryrawmaterialitem_consumebatches(v_farm, v_ditem, v_du, 2);

        RAISE NOTICE 'C3. drained to exactly 0  expect     0.00  got %',
            (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_dlot);
        RAISE NOTICE 'C4. stock also 0          expect     0.00  got %',
            (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_dlot);
        -- Nothing was created or destroyed on the way: the draws add to the lot.
        RAISE NOTICE 'C5. draws sum to the lot  expect   100.00  got %',
            (SELECT COALESCE(SUM(b.deferredcostdrawn), 0) FROM poultryrawmaterialusagebatch b
              WHERE b.poultryrawmaterialpurchaseid = v_dlot);
    END;

    -- =====================================================================
    -- D. Mixed layers: one draw across an expensed lot and a deferred one.
    -- =====================================================================
    DECLARE
        v_mitem integer; v_mA integer; v_mB integer; v_mu integer;
    BEGIN
        v_mitem := sppoultryrawmaterialitem_insert(v_farm, 'ZZ Mixed Maize', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'kg');
        -- The brief's own example: 100 kg already expensed, then 100 kg deferred
        -- at 10/kg, FIFO draw of 150.
        INSERT INTO poultryrawmaterialpurchases
            (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
             productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod,
             deferredtotalcost, deferredremainingcost)
        VALUES (v_farm, v_mitem, now() - interval '2 days', 100, 10, 1000, 1, 100, 'EXPENSE_WHEN_PURCHASED', 0, 0)
        RETURNING poultryrawmaterialpurchaseid INTO v_mA;
        INSERT INTO poultryrawmaterialpurchases
            (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
             productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod,
             deferredtotalcost, deferredremainingcost)
        VALUES (v_farm, v_mitem, now() - interval '1 day', 100, 10, 1000, 1, 100, 'EXPENSE_WHEN_CONSUMED', 1000, 1000)
        RETURNING poultryrawmaterialpurchaseid INTO v_mB;

        INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, quantityused, createdby)
        VALUES (v_farm, v_mitem, 150, 'ZZ tester') RETURNING poultryrawmaterialusageid INTO v_mu;
        PERFORM sppoultryrawmaterialitem_consumebatches(v_farm, v_mitem, v_mu, 150);

        -- 150 kg physically consumed, from both lots...
        RAISE NOTICE 'D1. both lots drawn        expect        2  got %',
            (SELECT COUNT(*) FROM poultryrawmaterialusagebatch WHERE poultryrawmaterialusageid = v_mu);
        RAISE NOTICE 'D2. expensed lot emptied   expect     0.00  got %',
            (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_mA);
        RAISE NOTICE 'D3. deferred lot at 50     expect    50.00  got %',
            (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_mB);
        -- ...but only 500 of deferred cost, all of it from the second lot.
        RAISE NOTICE 'D4. deferred drawn is 500  expect   500.00  got %',
            (SELECT COALESCE(SUM(b.deferredcostdrawn), 0) FROM poultryrawmaterialusagebatch b
              WHERE b.poultryrawmaterialusageid = v_mu);
        RAISE NOTICE 'D5. none from the expensed expect     0.00  got %',
            (SELECT b.deferredcostdrawn FROM poultryrawmaterialusagebatch b
              WHERE b.poultryrawmaterialusageid = v_mu AND b.poultryrawmaterialpurchaseid = v_mA);
        RAISE NOTICE 'D6. and 500 still deferred expect   500.00  got %',
            (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_mB);
    END;

    -- =====================================================================
    -- E. Purchase units normalise into production units.
    -- =====================================================================
    DECLARE
        v_bitem integer; v_blot integer; v_bu integer;
    BEGIN
        -- Bought in bags, stocked and consumed in kg: 20 bags of 50 kg for
        -- 10,000 -- the brief's own worked example, 10/kg.
        v_bitem := sppoultryrawmaterialitem_insert(v_farm, 'ZZ Bagged Maize', 'FeedIngredient', 'kg', 0, NULL, 'FIFO', 'bag');
        INSERT INTO poultryrawmaterialpurchases
            (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
             productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod,
             deferredtotalcost, deferredremainingcost)
        VALUES (v_farm, v_bitem, now() - interval '1 day', 20, 500, 10000, 50, 20, 'EXPENSE_WHEN_CONSUMED', 10000, 10000)
        RETURNING poultryrawmaterialpurchaseid INTO v_blot;

        -- Consume 100 kg -- two bags' worth.
        INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, quantityused, createdby)
        VALUES (v_farm, v_bitem, 100, 'ZZ tester') RETURNING poultryrawmaterialusageid INTO v_bu;
        PERFORM sppoultryrawmaterialitem_consumebatches(v_farm, v_bitem, v_bu, 100);

        -- The draw is recorded in PURCHASE units, as it always has been.
        RAISE NOTICE 'E1. two bags drawn         expect     2.00  got %',
            (SELECT quantitydrawn FROM poultryrawmaterialusagebatch WHERE poultryrawmaterialusageid = v_bu);
        RAISE NOTICE 'E2. lot down to 18 bags    expect    18.00  got %',
            (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_blot);
        -- 100 kg at 10/kg. Deferring per BAG here would have charged 1,000.
        RAISE NOTICE 'E3. deferred drawn is 1000 expect  1000.00  got %',
            (SELECT deferredcostdrawn FROM poultryrawmaterialusagebatch WHERE poultryrawmaterialusageid = v_bu);
        RAISE NOTICE 'E4. 9000 still deferred    expect  9000.00  got %',
            (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_blot);
    END;

    -- =====================================================================
    -- F. The guard rails hold.
    -- =====================================================================
    BEGIN
        UPDATE poultryrawmaterialpurchases SET deferredremainingcost = -1
        WHERE  poultryrawmaterialpurchaseid = v_pA;
        RAISE NOTICE 'F1. negative deferred cost <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'F1. negative deferred cost blocked: %', left(SQLERRM, 60);
    END;

    BEGIN
        UPDATE poultryrawmaterialpurchases SET deferredremainingcost = deferredtotalcost + 10
        WHERE  poultryrawmaterialpurchaseid = v_pA;
        RAISE NOTICE 'F2. remaining over total   <-- BUG, allowed';
    EXCEPTION WHEN others THEN
        RAISE NOTICE 'F2. remaining over total   blocked: %', left(SQLERRM, 60);
    END;
END
$t$;
