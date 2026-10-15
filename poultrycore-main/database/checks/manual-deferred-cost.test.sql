-- =============================================================================
-- manual-deferred-cost.test.sql -- checks for migration 371.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Uses a throwaway
-- raw-material item in the first poultry company that has a cash account.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm    text;
    v_user    text;
    v_item    integer;
    v_res     jsonb;
    v_entry   integer;
    v_lot     integer;
    v_usage   integer;
    v_cost    numeric;
    v_n       integer;
    v_x       numeric;
    v_failed  boolean;
    v_cash0   numeric;
BEGIN
    SELECT a.farmid INTO v_farm
    FROM   poultrycashaccounts a
    JOIN   farms f ON (f.id::text = a.farmid OR f.farmid::text = a.farmid) AND f.type = 'Poultry'
    WHERE  a.isactive
    ORDER  BY a.poultrycashaccountid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'manual deferred cost: all checks passed';
        RETURN;
    END IF;
    SELECT f.owneruserid INTO v_user FROM farms f WHERE f.id::text = v_farm OR f.farmid::text = v_farm LIMIT 1;
    v_user := COALESCE(v_user, 'check371');

    -- A feed item holding 2,000 kg that no purchase covers (opening stock).
    INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, usagemethod)
    VALUES (v_farm, 'Check 371 Feed', 'Feed', 'kg', 2000, 'FIFO')
    RETURNING poultryrawmaterialitemid INTO v_item;
    -- The opening stock got there the usual way: a stock adjustment.
    INSERT INTO poultryrawmaterialadjustments (farmid, poultryrawmaterialitemid, adjusteddate, quantity, movementtype, note)
    VALUES (v_farm, v_item, now()::timestamp - interval '20 days', 2000, 'Opening', 'check 371 opening stock');
    SELECT COALESCE(sum(currentbalance), 0) INTO v_cash0 FROM poultrycashaccounts WHERE farmid = v_farm;

    -- 1. Only uncovered stock; a reason is required.
    IF fnpoultryrawmaterial_uncoveredstock(v_farm, v_item) <> 2000 THEN RAISE EXCEPTION 'FAIL 1a: uncovered %', fnpoultryrawmaterial_uncoveredstock(v_farm, v_item); END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrymanualdeferredcost_create(v_farm, v_item, 12000, 2500, CURRENT_DATE - 10, 'OpeningDeferredCost', 'opening', NULL, NULL, v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1b: more than the uncovered stock accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrymanualdeferredcost_create(v_farm, v_item, 12000, 2000, CURRENT_DATE - 10, 'OpeningDeferredCost', '  ', NULL, NULL, v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1c: no reason accepted'; END IF;
    RAISE NOTICE 'ok 1 only stock no purchase covers, with a reason';

    -- 2. Record 12,000 on 2,000 kg: deferred, no stock change, no payable, no cash.
    v_res := sppoultrymanualdeferredcost_create(v_farm, v_item, 12000, 2000, CURRENT_DATE - 10, 'OpeningDeferredCost',
                                                'Opening stock cost', 'Stock sheet 1', NULL, v_user);
    v_entry := (v_res->>'entryId')::integer;
    v_lot   := (v_res->>'lotId')::integer;
    IF (SELECT currentquantity FROM poultryrawmaterialitems WHERE poultryrawmaterialitemid = v_item) <> 2000 THEN
        RAISE EXCEPTION 'FAIL 2a: physical stock changed'; END IF;
    IF fnpoultryrawmaterial_uncoveredstock(v_farm, v_item) <> 0 THEN RAISE EXCEPTION 'FAIL 2b: still uncovered'; END IF;
    IF EXISTS (SELECT 1 FROM fnpoultrypayables(v_farm) d WHERE d.documenttype = 'RawMaterialPurchase' AND d.documentid = v_lot) THEN
        RAISE EXCEPTION 'FAIL 2c: the manual cost is a payable'; END IF;
    IF (SELECT COALESCE(sum(currentbalance), 0) FROM poultrycashaccounts WHERE farmid = v_farm) <> v_cash0 THEN
        RAISE EXCEPTION 'FAIL 2d: cash moved'; END IF;
    IF EXISTS (SELECT 1 FROM sppoultrycashflow_rows(v_farm, (CURRENT_DATE - 30)::timestamp, (CURRENT_DATE + 1)::timestamp) r
               WHERE r.sourceid = v_lot AND r.sourcetype = 'RawMaterialPurchase') THEN
        RAISE EXCEPTION 'FAIL 2e: the manual cost is on Cash Flow'; END IF;
    SELECT x.newquantity INTO v_x FROM sppoultryrawmaterialitem_recalculatestock(v_farm, v_item) x;
    IF v_x <> 2000 THEN RAISE EXCEPTION 'FAIL 2f: recalculating stock counts the manual cost as a purchase (%)', v_x; END IF;
    UPDATE poultryrawmaterialitems SET currentquantity = 2000 WHERE poultryrawmaterialitemid = v_item;   -- keep the test's stock
    IF NOT EXISTS (SELECT 1 FROM sppoultrymanualdeferredcost_list(v_farm) l WHERE l.entryid = v_entry AND l.remaining = 12000) THEN
        RAISE EXCEPTION 'FAIL 2g: not listed'; END IF;
    RAISE NOTICE 'ok 2 deferred, with no stock change, payable or cash';

    -- 3. Using 500 kg recognises a quarter (3,000) through the usual lot draw.
    INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, useddate, quantityused)
    VALUES (v_farm, v_item, now()::timestamp, 500) RETURNING poultryrawmaterialusageid INTO v_usage;
    v_cost := sppoultryrawmaterialitem_consumebatches(v_farm, v_item, v_usage, 500);
    IF (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lot) <> 9000 THEN
        RAISE EXCEPTION 'FAIL 3a: deferred left %', (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lot); END IF;
    IF (SELECT deferredcostdrawn FROM poultryrawmaterialusagebatch WHERE poultryrawmaterialusageid = v_usage) <> 3000 THEN
        RAISE EXCEPTION 'FAIL 3b: drawn cost'; END IF;
    IF round(v_cost, 2) <> 6 THEN RAISE EXCEPTION 'FAIL 3c: unit cost % (want 6)', v_cost; END IF;
    RAISE NOTICE 'ok 3 usage recognises it like any deferred lot';

    -- 4. The purchase functions refuse it.
    v_failed := FALSE;
    BEGIN PERFORM sppoultryrawmaterialpurchase_delete(v_lot, v_farm);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4a: deleted as a purchase'; END IF;
    RAISE NOTICE 'ok 4 not editable as a purchase';

    -- 5. Reverse: only the 9,000 not yet recognised comes off; recognised stays; stock stays.
    v_x := sppoultrymanualdeferredcost_reverse(v_farm, v_entry, 'cost was wrong', v_user);
    IF v_x <> 9000 THEN RAISE EXCEPTION 'FAIL 5a: reversed %', v_x; END IF;
    IF (SELECT deferredtotalcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lot) <> 3000
       OR (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lot) <> 0 THEN
        RAISE EXCEPTION 'FAIL 5b: lot after reversal'; END IF;
    IF (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_lot) <> 1500 THEN
        RAISE EXCEPTION 'FAIL 5c: stock on the lot changed'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrymanualdeferredcost_reverse(v_farm, v_entry, 'again', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5d: reversed twice'; END IF;
    RAISE NOTICE 'ok 5 reversal takes back only the unrecognised part';

    RAISE NOTICE 'manual deferred cost: all checks passed';
END $$;

ROLLBACK;
