-- =============================================================================
-- Checks for 465 (Water Alerts). SELF-ROLLING-BACK; fixtures in a real Water
-- company. Prints 'water 465: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $t$
DECLARE
    v_f record; v_farm text; v_today date; v_acct integer; v_i integer; v_n integer;
BEGIN
    -- 1. it runs for every Water company, and severities / links are filled
    FOR v_f IN SELECT DISTINCT farmid FROM watersales UNION SELECT DISTINCT farmid FROM watercashaccounts LOOP
        IF EXISTS (SELECT 1 FROM spwateralerts_get(v_f.farmid) a
                   WHERE a.severity NOT IN ('Critical', 'Warning', 'Info') OR a.href IS NULL OR a.itemcount <= 0) THEN
            RAISE EXCEPTION 'FAIL 1 %: malformed alert', v_f.farmid;
        END IF;
    END LOOP;
    RAISE NOTICE 'ok 1 runs for every company';

    SELECT a.farmid INTO v_farm FROM watercashaccounts a
    WHERE lower(COALESCE(spfarm_gettype(a.farmid), '')) = 'water' ORDER BY a.watercashaccountid LIMIT 1;
    v_today := fncompany_businessdate(v_farm);

    -- 2. a cash account below zero is Critical, and goes away when fixed
    INSERT INTO watercashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, allownegativebalance, isactive)
    VALUES (v_farm, '__w465', 'Cash', 0, -50, TRUE, TRUE) RETURNING watercashaccountid INTO v_acct;
    IF NOT EXISTS (SELECT 1 FROM spwateralerts_get(v_farm) a WHERE a.code = 'NegativeCash' AND a.severity = 'Critical') THEN
        RAISE EXCEPTION 'FAIL 2a: negative cash not raised';
    END IF;
    UPDATE watercashaccounts SET currentbalance = 10 WHERE watercashaccountid = v_acct;
    SELECT COALESCE(SUM(a.itemcount), 0) INTO v_n FROM spwateralerts_get(v_farm) a WHERE a.code = 'NegativeCash';
    IF EXISTS (SELECT 1 FROM watercashaccounts WHERE farmid = v_farm AND isactive AND currentbalance < 0) THEN
        NULL;   -- the company has real negative accounts of its own; nothing to assert
    ELSIF v_n <> 0 THEN
        RAISE EXCEPTION 'FAIL 2b: alert stayed after the fix';
    END IF;
    RAISE NOTICE 'ok 2 derived, never stored';

    -- 3. a sale on a day without a closing raises MissingClosing
    IF NOT EXISTS (SELECT 1 FROM waterdailyclosings WHERE farmid = v_farm AND closingdate = v_today - 3 AND COALESCE(isactive, TRUE)) THEN
        SELECT COALESCE(MAX(a.itemcount), 0) INTO v_n FROM spwateralerts_get(v_farm) a WHERE a.code = 'MissingClosing';
        INSERT INTO watersales (farmid, saledate, totalamount, amountpaid, status) VALUES (v_farm, (v_today - 3)::timestamp, 10, 0, 'Pending');
        IF (SELECT COALESCE(MAX(a.itemcount), 0) FROM spwateralerts_get(v_farm) a WHERE a.code = 'MissingClosing') < GREATEST(v_n, 1) THEN
            RAISE EXCEPTION 'FAIL 3: a day with a sale and no closing was not flagged';
        END IF;
    END IF;
    RAISE NOTICE 'ok 3 missing closing';

    -- 4. a critical raw material shows under Stock with the item's name
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive)
    VALUES (v_farm, '__w465_item', 'Packaging', 'pcs', -1, TRUE) RETURNING waterrawmaterialitemid INTO v_i;
    INSERT INTO waterrawmaterialpurchases (farmid, waterrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
        productionunitsperpurchaseunit, remainingquantity, amountpaid, paymentmethod)
    VALUES (v_farm, v_i, (v_today - 30)::timestamp, 1, 1, 1, 1, 0, 1, 'Cash');
    IF NOT EXISTS (SELECT 1 FROM spwateralerts_get(v_farm) a WHERE a.code = 'StockNegative' AND a.detail LIKE '%__w465_item%') THEN
        RAISE EXCEPTION 'FAIL 4: negative stock not raised';
    END IF;
    RAISE NOTICE 'ok 4 stock from the restock forecast';

    RAISE NOTICE 'water 465: all checks passed';
END
$t$;

ROLLBACK;
