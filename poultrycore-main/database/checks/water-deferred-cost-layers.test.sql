-- Behavioural checks for migration 277: the water deferred cost layers.
--
-- One DO block per theme, a NOTICE per check reading "expect X got Y". Run
-- inside a transaction you ROLL BACK; it writes items, purchases, usage rows and
-- allocations.
--
--   psql ... -X -c "BEGIN;" -f water-deferred-cost-layers.test.sql -c "ROLLBACK;"
--
-- To validate the migration AND its behaviour in one pass, concatenate 277
-- (BEGIN;/COMMIT; stripped, and its trailing SELECT verification dropped) ahead
-- of this body inside the same BEGIN; ROLLBACK;.
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **The engine's operational behaviour does not change.** 277 adds a second
-- number to a working FIFO/LIFO/HIFO engine, and the whole file is worthless if
-- the lot ordering, the purchase-to-production unit conversion or the returned
-- unit cost moved by so much as a rounding step. Section A pins those against
-- hand-computed values BEFORE any deferred cost exists anywhere.
--
-- WHY THE DEFERRED BALANCES ARE SEEDED BY HAND
-- --------------------------------------------
-- 278 is the migration that OPENS a lot's deferred balance at purchase, and it
-- is not written yet. So sections B onward set deferredtotalcost /
-- deferredremainingcost with a plain UPDATE, which is exactly the state 278 will
-- leave behind. That is the only way to exercise the draw arithmetic before 278
-- exists, and it is honest about it rather than pretending the purchase path
-- already does this.
--
-- The rest:
--   A. The engine is unchanged, and every draw reports a deferred share of zero
--      while no lot has any deferred cost. This is the state of every real
--      company today.
--   B. A partial draw takes a PRO RATA share of the lot's remaining deferred
--      cost, and the lot keeps the rest.
--   C. Emptying a lot takes its deferred balance to EXACTLY zero -- the property
--      that pro rata buys and that quantity x unit-cost would not.
--   D. A draw spanning a deferred lot and an already-expensed one charges only
--      the deferred one.
--   E. The allocation remembers its own share, which is what makes reversal
--      exact once 279 needs to give it back.
--   F. The unit-cost helper, including the exhausted lot it must not divide by.

DO $t$
DECLARE
    v_farm     text;
    v_item     integer;
    v_item2    integer;
    v_lot1     integer;
    v_lot2     integer;
    v_usage    integer;
    v_unitcost numeric;
    v_rem      numeric;
    v_def      numeric;
    v_drawn    numeric;
    v_before   numeric;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE EXCEPTION 'No water company to run these checks against.';
    END IF;
    RAISE NOTICE '   using water company %', v_farm;

    -- =====================================================================
    -- A. THE ENGINE IS UNCHANGED, AND EVERY DRAW IS ZERO-DEFERRED.
    --
    -- Two FIFO lots of the same item, different unit costs, with a
    -- purchase-to-production multiplier of 2 so the unit conversion is actually
    -- exercised rather than being an identity.
    --
    --   lot1  10 purchase units @ 100  -> 20 production units, cost 1000
    --   lot2  10 purchase units @ 200  -> 20 production units, cost 2000
    --
    -- Draw 30 production units: all 20 of lot1, then 10 of lot2.
    --   purchase cost drawn = 10 x 100  +  5 x 200 = 2000
    --   production units    = 30
    --   unit cost           = 2000 / 30 = 66.6667
    -- =====================================================================
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Film 277', 'SachetFilm', 'Sheet', 'Roll', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_item;

    INSERT INTO waterrawmaterialpurchases
        (farmid, waterrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
         paymentmethod, amountpaid, remainingquantity, productionunit,
         productionunitsperpurchaseunit, costrecognitionmethod, createdby)
    VALUES (v_farm, v_item, (now() at time zone 'utc') - interval '2 days', 10, 100, 1000,
            'Credit', 0, 10, 'Sheet', 2, 'EXPENSE_WHEN_PURCHASED', 'ZZ tester')
    RETURNING waterrawmaterialpurchaseid INTO v_lot1;

    INSERT INTO waterrawmaterialpurchases
        (farmid, waterrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
         paymentmethod, amountpaid, remainingquantity, productionunit,
         productionunitsperpurchaseunit, costrecognitionmethod, createdby)
    VALUES (v_farm, v_item, (now() at time zone 'utc') - interval '1 day', 10, 200, 2000,
            'Credit', 0, 10, 'Sheet', 2, 'EXPENSE_WHEN_PURCHASED', 'ZZ tester')
    RETURNING waterrawmaterialpurchaseid INTO v_lot2;

    RAISE NOTICE 'A1. new lots default to 0 deferred expect        t  got %',
        ((SELECT deferredtotalcost + deferredremainingcost FROM waterrawmaterialpurchases
          WHERE waterrawmaterialpurchaseid IN (v_lot1, v_lot2)
          ORDER BY waterrawmaterialpurchaseid LIMIT 1) = 0);

    INSERT INTO waterrawmaterialusage (farmid, waterrawmaterialitemid, useddate, quantityused, createdby)
    VALUES (v_farm, v_item, (now() at time zone 'utc'), 30, 'ZZ tester')
    RETURNING waterrawmaterialusageid INTO v_usage;

    v_unitcost := spwaterrawmaterialitem_consumebatches(v_farm, v_item, v_usage, 30);

    RAISE NOTICE 'A2. unit cost is unchanged   expect  66.6667  got %', v_unitcost;

    SELECT remainingquantity INTO v_rem FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot1;
    RAISE NOTICE 'A3. FIFO emptied lot1 first  expect   0.000   got %', v_rem;
    SELECT remainingquantity INTO v_rem FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot2;
    RAISE NOTICE 'A4. and took 5 from lot2     expect   5.000   got %', v_rem;

    RAISE NOTICE 'A5. two allocations written  expect        2  got %',
        (SELECT COUNT(*) FROM waterrawmaterialusagebatch WHERE waterrawmaterialusageid = v_usage);

    -- The point of section A.
    RAISE NOTICE 'A6. nothing was deferred     expect     0.00  got %',
        (SELECT COALESCE(SUM(deferredcostdrawn), 0) FROM waterrawmaterialusagebatch
         WHERE waterrawmaterialusageid = v_usage);

    -- =====================================================================
    -- B. A PARTIAL DRAW TAKES A PRO-RATA SHARE.
    --
    -- One lot, 10 purchase units @ 100, multiplier 1, fully deferred at 1000.
    -- Draw 4 of the 10 production units: 4/10 of 1000 = 400 recognised, 600 left.
    -- =====================================================================
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Film 277b', 'SachetFilm', 'Roll', 'Roll', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_item2;

    INSERT INTO waterrawmaterialpurchases
        (farmid, waterrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
         paymentmethod, amountpaid, remainingquantity, productionunit,
         productionunitsperpurchaseunit, costrecognitionmethod, createdby)
    VALUES (v_farm, v_item2, (now() at time zone 'utc'), 10, 100, 1000,
            'Credit', 0, 10, 'Roll', 1, 'EXPENSE_WHEN_CONSUMED', 'ZZ tester')
    RETURNING waterrawmaterialpurchaseid INTO v_lot1;

    -- The state 278 will leave behind. Set by hand because 278 is not written.
    UPDATE waterrawmaterialpurchases
    SET    deferredtotalcost = 1000, deferredremainingcost = 1000
    WHERE  waterrawmaterialpurchaseid = v_lot1;

    INSERT INTO waterrawmaterialusage (farmid, waterrawmaterialitemid, useddate, quantityused, createdby)
    VALUES (v_farm, v_item2, (now() at time zone 'utc'), 4, 'ZZ tester')
    RETURNING waterrawmaterialusageid INTO v_usage;

    PERFORM spwaterrawmaterialitem_consumebatches(v_farm, v_item2, v_usage, 4);

    SELECT deferredcostdrawn INTO v_drawn FROM waterrawmaterialusagebatch
    WHERE waterrawmaterialusageid = v_usage;
    RAISE NOTICE 'B1. pro-rata share drawn     expect   400.00  got %', v_drawn;

    SELECT deferredremainingcost, deferredtotalcost INTO v_def, v_rem
    FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot1;
    RAISE NOTICE 'B2. lot keeps the rest       expect   600.00  got %', v_def;
    RAISE NOTICE 'B3. and totalcost is a record, not a balance expect  1000.00  got %', v_rem;

    -- =====================================================================
    -- C. EMPTYING A LOT LANDS ON EXACTLY ZERO.
    --
    -- The property pro rata buys. A deferred balance that does not divide evenly
    -- by the quantity is the case that would strand a crumb under a
    -- quantity x unit-cost rule: 1000/3 per unit never sums back to 1000.
    -- =====================================================================
    UPDATE waterrawmaterialpurchases
    SET    quantity = 3, remainingquantity = 3, totalcost = 1000, unitcost = 333.33,
           deferredtotalcost = 1000, deferredremainingcost = 1000
    WHERE  waterrawmaterialpurchaseid = v_lot1;

    -- What this lot had already given up in section B, so C3 below measures
    -- section C's draws alone. The lot is deliberately reused -- re-deferring a
    -- partly-drawn lot is the realistic shape -- and summing its allocations
    -- without this baseline would count B's 400 twice.
    SELECT COALESCE(SUM(ub.deferredcostdrawn), 0) INTO v_before
    FROM   waterrawmaterialusagebatch ub
    WHERE  ub.waterrawmaterialpurchaseid = v_lot1;

    -- Draw one unit at a time, so each draw rounds independently.
    FOR i IN 1..3 LOOP
        INSERT INTO waterrawmaterialusage (farmid, waterrawmaterialitemid, useddate, quantityused, createdby)
        VALUES (v_farm, v_item2, (now() at time zone 'utc'), 1, 'ZZ tester')
        RETURNING waterrawmaterialusageid INTO v_usage;
        PERFORM spwaterrawmaterialitem_consumebatches(v_farm, v_item2, v_usage, 1);
    END LOOP;

    SELECT remainingquantity, deferredremainingcost INTO v_rem, v_def
    FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot1;
    RAISE NOTICE 'C1. lot is empty of stock    expect   0.000   got %', v_rem;
    RAISE NOTICE 'C2. and empty of deferred    expect     0.00  got %', v_def;

    -- Not one pesewa may have gone missing on the way out: what the lot held
    -- must equal what the allocations took.
    SELECT COALESCE(SUM(ub.deferredcostdrawn), 0) - v_before INTO v_drawn
    FROM   waterrawmaterialusagebatch ub
    WHERE  ub.waterrawmaterialpurchaseid = v_lot1;
    RAISE NOTICE 'C3. and it all went somewhere expect  1000.00  got %', v_drawn;

    -- =====================================================================
    -- D. A MIXED DRAW CHARGES ONLY THE DEFERRED LOT.
    --
    -- This is the case that protects a company from being charged twice. lot1 is
    -- already expensed (its cost reached the P&L when it was paid); lot2 is
    -- deferred. A draw crossing both may only recognise lot2's share.
    --
    --   lot1  5 units @ 100, expensed at purchase, deferred 0
    --   lot2  5 units @ 100, deferred 500
    --   draw 8 units: 5 from lot1 (0 deferred), 3 from lot2 (3/5 x 500 = 300)
    -- =====================================================================
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Film 277d', 'SachetFilm', 'Roll', 'Roll', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_item2;

    INSERT INTO waterrawmaterialpurchases
        (farmid, waterrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
         paymentmethod, amountpaid, remainingquantity, productionunit,
         productionunitsperpurchaseunit, costrecognitionmethod, createdby)
    VALUES (v_farm, v_item2, (now() at time zone 'utc') - interval '2 days', 5, 100, 500,
            'Cash', 500, 5, 'Roll', 1, 'EXPENSE_WHEN_PURCHASED', 'ZZ tester')
    RETURNING waterrawmaterialpurchaseid INTO v_lot1;

    INSERT INTO waterrawmaterialpurchases
        (farmid, waterrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
         paymentmethod, amountpaid, remainingquantity, productionunit,
         productionunitsperpurchaseunit, costrecognitionmethod, createdby)
    VALUES (v_farm, v_item2, (now() at time zone 'utc') - interval '1 day', 5, 100, 500,
            'Credit', 0, 5, 'Roll', 1, 'EXPENSE_WHEN_CONSUMED', 'ZZ tester')
    RETURNING waterrawmaterialpurchaseid INTO v_lot2;

    UPDATE waterrawmaterialpurchases
    SET    deferredtotalcost = 500, deferredremainingcost = 500
    WHERE  waterrawmaterialpurchaseid = v_lot2;

    INSERT INTO waterrawmaterialusage (farmid, waterrawmaterialitemid, useddate, quantityused, createdby)
    VALUES (v_farm, v_item2, (now() at time zone 'utc'), 8, 'ZZ tester')
    RETURNING waterrawmaterialusageid INTO v_usage;

    PERFORM spwaterrawmaterialitem_consumebatches(v_farm, v_item2, v_usage, 8);

    RAISE NOTICE 'D1. expensed lot charges nothing expect     0.00  got %',
        (SELECT deferredcostdrawn FROM waterrawmaterialusagebatch
         WHERE waterrawmaterialusageid = v_usage AND waterrawmaterialpurchaseid = v_lot1);
    RAISE NOTICE 'D2. deferred lot charges pro rata expect   300.00  got %',
        (SELECT deferredcostdrawn FROM waterrawmaterialusagebatch
         WHERE waterrawmaterialusageid = v_usage AND waterrawmaterialpurchaseid = v_lot2);
    RAISE NOTICE 'D3. usage total is the deferred part only expect   300.00  got %',
        (SELECT COALESCE(SUM(deferredcostdrawn), 0) FROM waterrawmaterialusagebatch
         WHERE waterrawmaterialusageid = v_usage);
    RAISE NOTICE 'D4. deferred lot keeps 200   expect   200.00  got %',
        (SELECT deferredremainingcost FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot2);

    -- The operational half is untouched by any of it: 8 units at 100 each.
    RAISE NOTICE 'D5. operational cost unchanged expect 100.0000  got %',
        (SELECT SUM(ub.quantitydrawn * ub.unitcostatdraw) / NULLIF(SUM(ub.quantitydrawn), 0)
         FROM waterrawmaterialusagebatch ub WHERE ub.waterrawmaterialusageid = v_usage)::numeric(14,4);

    -- =====================================================================
    -- E. THE ALLOCATION REMEMBERS ITS OWN SHARE.
    --
    -- Drawn again from the same lot AFTER the draw above. The first allocation's
    -- recorded share must not move -- 279's reversal gives back what was taken at
    -- the time, not what today's balance would imply.
    -- =====================================================================
    SELECT deferredcostdrawn INTO v_drawn FROM waterrawmaterialusagebatch
    WHERE waterrawmaterialusageid = v_usage AND waterrawmaterialpurchaseid = v_lot2;

    INSERT INTO waterrawmaterialusage (farmid, waterrawmaterialitemid, useddate, quantityused, createdby)
    VALUES (v_farm, v_item2, (now() at time zone 'utc'), 2, 'ZZ tester')
    RETURNING waterrawmaterialusageid INTO v_usage;
    PERFORM spwaterrawmaterialitem_consumebatches(v_farm, v_item2, v_usage, 2);

    RAISE NOTICE 'E1. the earlier draw is frozen expect   300.00  got %', v_drawn;
    RAISE NOTICE 'E2. the new draw empties it   expect   200.00  got %',
        (SELECT deferredcostdrawn FROM waterrawmaterialusagebatch
         WHERE waterrawmaterialusageid = v_usage AND waterrawmaterialpurchaseid = v_lot2);
    RAISE NOTICE 'E3. and the lot is at zero    expect     0.00  got %',
        (SELECT deferredremainingcost FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot2);

    -- =====================================================================
    -- F. THE UNIT-COST HELPER.
    -- =====================================================================
    RAISE NOTICE 'F1. 600 over 6 prod units     expect 100.0000  got %',
        fnwaterlot_deferredunitcost(600, 6, 1)::numeric(14,4);
    RAISE NOTICE 'F2. the multiplier is applied expect  50.0000  got %',
        fnwaterlot_deferredunitcost(600, 6, 2)::numeric(14,4);
    -- The guard that matters: an exhausted lot must return NULL, not raise.
    RAISE NOTICE 'F3. exhausted lot is NULL     expect        t  got %',
        (fnwaterlot_deferredunitcost(600, 0, 1) IS NULL);
    RAISE NOTICE 'F4. a null mult reads as 1    expect 100.0000  got %',
        fnwaterlot_deferredunitcost(600, 6, NULL)::numeric(14,4);

    RAISE NOTICE '--- 277 checks done. ROLL BACK this transaction. ---';
END
$t$;

-- =============================================================================
-- G. THE CONSTRAINT, tested outside the block above because each violation
--    aborts its own subtransaction.
-- =============================================================================
DO $ck$
DECLARE
    v_farm text;
    v_item integer;
    v_lot  integer;
BEGIN
    SELECT f.farmid INTO v_farm FROM farms f WHERE f.type = 'Water' ORDER BY f.farmid LIMIT 1;

    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, minimumstockalert, isactive, usagemethod)
    VALUES (v_farm, 'ZZ Film 277g', 'SachetFilm', 'Roll', 'Roll', 0, TRUE, 'FIFO')
    RETURNING waterrawmaterialitemid INTO v_item;

    INSERT INTO waterrawmaterialpurchases
        (farmid, waterrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
         paymentmethod, amountpaid, remainingquantity, productionunit,
         productionunitsperpurchaseunit, costrecognitionmethod, createdby)
    VALUES (v_farm, v_item, (now() at time zone 'utc'), 1, 100, 100,
            'Credit', 0, 1, 'Roll', 1, 'EXPENSE_WHEN_CONSUMED', 'ZZ tester')
    RETURNING waterrawmaterialpurchaseid INTO v_lot;

    BEGIN
        UPDATE waterrawmaterialpurchases SET deferredremainingcost = -1
        WHERE waterrawmaterialpurchaseid = v_lot;
        RAISE NOTICE 'G1. negative deferred blocked expect blocked  got ALLOWED -- WRONG';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'G1. negative deferred blocked expect blocked  got blocked';
    END;

    BEGIN
        UPDATE waterrawmaterialpurchases
        SET deferredtotalcost = 100, deferredremainingcost = 200
        WHERE waterrawmaterialpurchaseid = v_lot;
        RAISE NOTICE 'G2. remaining over total blocked expect blocked  got ALLOWED -- WRONG';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'G2. remaining over total blocked expect blocked  got blocked';
    END;

    RAISE NOTICE '--- 277 constraint checks done. ROLL BACK this transaction. ---';
END
$ck$;
