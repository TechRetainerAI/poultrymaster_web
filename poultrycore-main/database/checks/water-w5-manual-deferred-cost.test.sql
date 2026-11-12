-- =============================================================================
-- Checks for 428 (Water manual deferred cost, W5). SELF-ROLLING-BACK, fixtures
-- in a real Water company. Prints 'water W5: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $t$
DECLARE
    v_farm text; v_item integer; v_res jsonb; v_lot integer; v_use integer; v_n numeric; v_flag integer;
    v_base numeric; v_spend numeric;
    d1 date := DATE '2001-06-10';
BEGIN
    SELECT a.farmid INTO v_farm FROM watercashaccounts a ORDER BY a.watercashaccountid LIMIT 1;
    -- 100 kg of opening stock that no purchase covers
    v_item := spwaterrawmaterialitem_insert(v_farm, '__w5_item', 'PackagingRoll', 'kg', 0, 100, TRUE, NULL, 'kg', 'FIFO');
    UPDATE waterrawmaterialitems SET currentquantity = 100 WHERE waterrawmaterialitemid = v_item;
    IF fnwaterrawmaterial_uncoveredstock(v_farm, v_item) <> 100 THEN RAISE EXCEPTION 'FAIL 0: uncovered %', fnwaterrawmaterial_uncoveredstock(v_farm, v_item); END IF;

    -- 1. without a lot, usage cannot draw
    INSERT INTO waterrawmaterialusage (farmid, waterrawmaterialitemid, quantityused, useddate)
    VALUES (v_farm, v_item, 40, d1::timestamp) RETURNING waterrawmaterialusageid INTO v_use;
    v_flag := 0;
    BEGIN PERFORM spwaterrawmaterialitem_consumebatches(v_farm, v_item, v_use, 40); EXCEPTION WHEN OTHERS THEN v_flag := 1; END;
    IF v_flag <> 1 THEN RAISE EXCEPTION 'FAIL 1: drew from no lot'; END IF;
    RAISE NOTICE 'ok 1 uncovered stock cannot be drawn';

    -- 2. a manual cost may not exceed the uncovered stock
    v_flag := 0;
    BEGIN PERFORM spwatermanualdeferredcost_create(v_farm, v_item, 600, 120, d1, 'OpeningDeferredCost', 'too much', NULL, NULL, '__w5');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN v_flag := 1; END;
    IF v_flag <> 1 THEN RAISE EXCEPTION 'FAIL 2: covered more than uncovered'; END IF;

    -- 3. record it: no P&L, no closing spend, no payable; stock unchanged
    SELECT rawmaterialcost INTO v_base FROM spwaterreport_periodpnl(v_farm, d1, d1);
    SELECT rawmaterialspendtoday INTO v_spend FROM fnwaterdailyclosing_livetotals(v_farm, d1);
    v_res := spwatermanualdeferredcost_create(v_farm, v_item, 500, 100, d1, 'OpeningDeferredCost', 'opening stock', NULL, NULL, '__w5');
    v_lot := (v_res->>'lotId')::int;
    IF (SELECT rawmaterialcost FROM spwaterreport_periodpnl(v_farm, d1, d1)) <> v_base THEN RAISE EXCEPTION 'FAIL 3a: manual cost hit raw materials'; END IF;
    IF (SELECT rawmaterialspendtoday FROM fnwaterdailyclosing_livetotals(v_farm, d1)) <> v_spend THEN RAISE EXCEPTION 'FAIL 3b: closing spend'; END IF;
    IF EXISTS (SELECT 1 FROM fnwaterpayables(v_farm) d WHERE d.documenttype = 'RawMaterialPurchase' AND d.documentid = v_lot) THEN
        RAISE EXCEPTION 'FAIL 3c: manual cost is a payable';
    END IF;
    IF EXISTS (SELECT 1 FROM spwaterrawmaterialpurchase_getall(v_farm) g WHERE g.waterrawmaterialpurchaseid = v_lot) THEN
        RAISE EXCEPTION 'FAIL 3d: manual cost listed as a purchase';
    END IF;
    IF EXISTS (SELECT 1 FROM fnwaterbalanceaudit(v_farm) a WHERE a.documenttype = 'RawMaterialPurchase' AND a.documentid = v_lot) THEN
        RAISE EXCEPTION 'FAIL 3e: balance audit flags it';
    END IF;
    PERFORM spwaterrawmaterialitem_recalculatestock(v_farm, v_item);
    IF (SELECT currentquantity FROM waterrawmaterialitems WHERE waterrawmaterialitemid = v_item) > 100 THEN
        RAISE EXCEPTION 'FAIL 3f: recalculate counted the opening stock twice';
    END IF;
    UPDATE waterrawmaterialitems SET currentquantity = 100 WHERE waterrawmaterialitemid = v_item;
    IF fnwaterrawmaterial_uncoveredstock(v_farm, v_item) <> 0 THEN RAISE EXCEPTION 'FAIL 3g: still uncovered'; END IF;
    RAISE NOTICE 'ok 2-3 manual cost: capped, no P&L / spend / payable / purchase, stock unchanged';

    -- 4. usage now draws from it and carries its deferred cost
    PERFORM spwaterrawmaterialitem_consumebatches(v_farm, v_item, v_use, 40);
    SELECT deferredremainingcost INTO v_n FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot;
    IF v_n <> 300 THEN RAISE EXCEPTION 'FAIL 4a: deferred left %', v_n; END IF;
    IF (SELECT SUM(deferredcostdrawn) FROM waterrawmaterialusagebatch WHERE waterrawmaterialusageid = v_use) <> 200 THEN
        RAISE EXCEPTION 'FAIL 4b: deferred cost drawn';
    END IF;
    RAISE NOTICE 'ok 4 usage draws the manual lot and carries its cost';

    -- 5. it cannot be edited / deleted / paid as a purchase
    v_flag := 0;
    BEGIN PERFORM spwaterrawmaterialpurchase_delete(v_lot, v_farm); EXCEPTION WHEN SQLSTATE 'P0001' THEN v_flag := 1; END;
    IF v_flag <> 1 THEN RAISE EXCEPTION 'FAIL 5: manual lot deleted as a purchase'; END IF;

    -- 6. reversal takes back only the unrecognised part; the stock stays
    v_n := spwatermanualdeferredcost_reverse(v_farm, (v_res->>'entryId')::int, 'entered twice', '__w5');
    IF v_n <> 300 THEN RAISE EXCEPTION 'FAIL 6a: reversed %', v_n; END IF;
    IF (SELECT deferredtotalcost FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot) <> 200 THEN
        RAISE EXCEPTION 'FAIL 6b: recognised part touched';
    END IF;
    IF (SELECT remainingquantity FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot) <> 60 THEN
        RAISE EXCEPTION 'FAIL 6c: stock changed';
    END IF;
    IF (SELECT status FROM spwatermanualdeferredcost_list(v_farm) WHERE entryid = (v_res->>'entryId')::int) <> 'Reversed' THEN
        RAISE EXCEPTION 'FAIL 6d: list status';
    END IF;
    RAISE NOTICE 'ok 5-6 purchase actions refuse it; reversal keeps recognised cost and stock';

    RAISE NOTICE 'water W5: all checks passed';
END
$t$;

ROLLBACK;
