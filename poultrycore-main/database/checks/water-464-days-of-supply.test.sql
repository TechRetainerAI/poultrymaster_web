-- =============================================================================
-- Checks for 464 (Water days of supply). SELF-ROLLING-BACK, fixtures in a real
-- Water company, dated relative to its business date.
-- Prints 'water 464: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $t$
DECLARE
    v_farm text; v_today date; k integer; r record;
    i_norm integer; i_zero integer; i_new integer; i_neg integer; i_out integer; i_bag integer;
BEGIN
    SELECT a.farmid INTO v_farm FROM watercashaccounts a
    WHERE lower(COALESCE(spfarm_gettype(a.farmid), '')) = 'water' ORDER BY a.watercashaccountid LIMIT 1;
    v_today := (now() AT TIME ZONE fncompany_timezone(v_farm))::date;

    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, currentquantity, isactive, minimumstockalert)
    VALUES (v_farm, '__w464_preform', 'Packaging', 'pcs', 'Bag', 1800, TRUE, 2000) RETURNING waterrawmaterialitemid INTO i_norm;
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive)
    VALUES (v_farm, '__w464_idle', 'Packaging', 'pcs', 100, TRUE) RETURNING waterrawmaterialitemid INTO i_zero;
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive, createdat)
    VALUES (v_farm, '__w464_new', 'Packaging', 'pcs', 500, TRUE, now()) RETURNING waterrawmaterialitemid INTO i_new;
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive)
    VALUES (v_farm, '__w464_neg', 'Chemicals', 'litre', -5, TRUE) RETURNING waterrawmaterialitemid INTO i_neg;
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive)
    VALUES (v_farm, '__w464_out', 'Packaging', 'pcs', 0, TRUE) RETURNING waterrawmaterialitemid INTO i_out;
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, purchaseunitofmeasure, currentquantity, isactive)
    VALUES (v_farm, '__w464_roll', 'Packaging', 'kg', 'Roll', 500, TRUE) RETURNING waterrawmaterialitemid INTO i_bag;

    -- first stock 40 days ago for the "old" items; the new item is stocked yesterday
    INSERT INTO waterrawmaterialpurchases (farmid, waterrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
        productionunitsperpurchaseunit, remainingquantity, amountpaid, paymentmethod)
    SELECT v_farm, x, (v_today - 40)::timestamp, 1, 1, 1, 1, 0, 0, 'Credit'
    FROM unnest(ARRAY[i_norm, i_zero, i_neg, i_out]) x;
    INSERT INTO waterrawmaterialpurchases (farmid, waterrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
        productionunitsperpurchaseunit, remainingquantity, amountpaid, paymentmethod)
    VALUES (v_farm, i_bag, (v_today - 40)::timestamp, 10, 50, 500, 50, 10, 0, 'Credit'),
           (v_farm, i_new, (v_today - 1)::timestamp, 500, 1, 500, 1, 500, 0, 'Credit'),
           -- a purchase INSIDE the window is stock in, not usage
           (v_farm, i_norm, (v_today - 2)::timestamp, 999, 1, 999, 1, 999, 0, 'Credit');

    FOR k IN 0..7 LOOP   -- d-7 .. d-1 is the window; d (today) must not count yet
        INSERT INTO waterrawmaterialusage (farmid, waterrawmaterialitemid, useddate, quantityused, isreversed)
        VALUES (v_farm, i_norm, (v_today - k)::timestamp + time '10:00', 620, FALSE),
               (v_farm, i_norm, (v_today - k)::timestamp + time '11:00', 10000, TRUE);   -- reversed: ignored
        IF k >= 1 THEN
            INSERT INTO waterrawmaterialusage (farmid, waterrawmaterialitemid, useddate, quantityused, isreversed)
            VALUES (v_farm, i_bag, (v_today - k)::timestamp + time '10:00', 25, FALSE);
        END IF;
        IF k = 3 THEN
            INSERT INTO waterrawmaterialusage (farmid, waterrawmaterialitemid, useddate, quantityused, isreversed)
            VALUES (v_farm, i_out, (v_today - k)::timestamp, 70, FALSE), (v_farm, i_neg, (v_today - k)::timestamp, 2, FALSE);
        END IF;
    END LOOP;
    -- a write-off adjustment is not consumption
    INSERT INTO waterrawmaterialadjustments (farmid, waterrawmaterialitemid, adjusteddate, quantity, movementtype, note, createdby)
    VALUES (v_farm, i_norm, (v_today - 2)::timestamp, -300, 'Decrease', 'spoiled', '__w464');

    SELECT * INTO r FROM spwaterstocksupply(v_farm) x WHERE x.waterrawmaterialitemid = i_norm;
    IF r.consumedqty <> 4340 OR r.avgdailyusage <> 620 OR r.daysofsupply <> 2.9 OR r.status <> 'Critical'
       OR r.estimatedstockout <> v_today + 2 OR r.windowfrom <> v_today - 7 OR r.windowto <> v_today - 1
       OR r.usagedays <> 7 OR NOT r.belowreorder THEN
        RAISE EXCEPTION 'FAIL 1: normal usage wrong (reversals, purchases, write-offs and today excluded): %', r;
    END IF;
    RAISE NOTICE 'ok 1 620/day, 1800 left -> 2.9 days, Critical';

    SELECT * INTO r FROM spwaterstocksupply(v_farm) x WHERE x.waterrawmaterialitemid = i_zero;
    IF r.status <> 'NoRecentUsage' OR r.daysofsupply IS NOT NULL OR r.estimatedstockout IS NOT NULL THEN RAISE EXCEPTION 'FAIL 2: %', r; END IF;
    SELECT * INTO r FROM spwaterstocksupply(v_farm) x WHERE x.waterrawmaterialitemid = i_new;
    IF r.status <> 'InsufficientHistory' OR r.daysofsupply IS NOT NULL THEN RAISE EXCEPTION 'FAIL 3: %', r; END IF;
    SELECT * INTO r FROM spwaterstocksupply(v_farm) x WHERE x.waterrawmaterialitemid = i_neg;
    IF r.status <> 'Negative' OR r.daysofsupply IS NOT NULL THEN RAISE EXCEPTION 'FAIL 4: %', r; END IF;
    SELECT * INTO r FROM spwaterstocksupply(v_farm) x WHERE x.waterrawmaterialitemid = i_out;
    IF r.status <> 'OutOfStock' OR r.daysofsupply <> 0 OR r.estimatedstockout <> v_today THEN RAISE EXCEPTION 'FAIL 5: %', r; END IF;
    RAISE NOTICE 'ok 2-5 no usage / new item / negative / out of stock';

    SELECT * INTO r FROM spwaterstocksupply(v_farm) x WHERE x.waterrawmaterialitemid = i_bag;
    IF r.avgdailyusage <> 25 OR r.daysofsupply <> 20 OR r.status <> 'Healthy' OR r.unitsperpurchaseunit <> 50 OR r.purchaseunitofmeasure <> 'Roll' THEN
        RAISE EXCEPTION 'FAIL 6: units: %', r;
    END IF;
    SELECT * INTO r FROM spwaterstocksupply(v_farm, 14) x WHERE x.waterrawmaterialitemid = i_norm;
    IF r.avgdailyusage <> 310 OR r.daysofsupply <> 5.8 OR r.status <> 'Warning' THEN RAISE EXCEPTION 'FAIL 7: 14-day lookback: %', r; END IF;
    RAISE NOTICE 'ok 6-7 purchase units, lookback';

    PERFORM spwaterstocksupplysettings_set(v_farm, 7, 1, 2, 3, '__w464');
    SELECT * INTO r FROM spwaterstocksupply(v_farm) x WHERE x.waterrawmaterialitemid = i_norm;
    IF r.status <> 'Healthy' OR r.criticaldays <> 1 THEN RAISE EXCEPTION 'FAIL 8: thresholds: %', r; END IF;
    BEGIN
        PERFORM spwaterstocksupplysettings_set(v_farm, 7, 5, 5, 3, '__w464');
        RAISE EXCEPTION 'FAIL 9: accepted warning <= critical';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'ok 8-9 company thresholds';

    RAISE NOTICE 'water 464: all checks passed';
END
$t$;

ROLLBACK;
