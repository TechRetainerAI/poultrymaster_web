-- =============================================================================
-- Checks for 462 (Water Receive Purchase). SELF-ROLLING-BACK, fixtures in a
-- real Water company, dated 2001. Prints 'water 462: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.w462_refused(p_sql text) RETURNS text LANGUAGE plpgsql AS $r$
BEGIN
    EXECUTE p_sql;
    RETURN NULL;
EXCEPTION WHEN OTHERS THEN
    RETURN SQLERRM;
END $r$;

DO $t$
DECLARE
    v_farm text; v_sup integer; v_acct integer; v_i1 integer; v_i2 integer;
    v_rc integer; v_rc2 integer; v_rc3 integer; v_lot1 integer; v_lot2 integer; v_pay integer;
    v_q1 numeric; v_q2 numeric; v_err text; v_n numeric; v_m numeric;
    v_req uuid := gen_random_uuid();
    d1 date := DATE '2001-07-10';
BEGIN
    SELECT a.farmid INTO v_farm FROM watercashaccounts a
    WHERE lower(COALESCE(spfarm_gettype(a.farmid), '')) = 'water' ORDER BY a.watercashaccountid LIMIT 1;
    INSERT INTO watersuppliers (farmid, suppliername, isactive, isdeleted) VALUES (v_farm, '__w462_supplier', TRUE, FALSE)
    RETURNING watersupplierid INTO v_sup;
    INSERT INTO watercashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, allownegativebalance, isactive)
    VALUES (v_farm, '__w462_account', 'Cash', 10000, 10000, FALSE, TRUE) RETURNING watercashaccountid INTO v_acct;
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive)
    VALUES (v_farm, '__w462_preform', 'Packaging', 'pcs', 0, TRUE) RETURNING waterrawmaterialitemid INTO v_i1;
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive)
    VALUES (v_farm, '__w462_cap', 'Packaging', 'pcs', 0, TRUE) RETURNING waterrawmaterialitemid INTO v_i2;

    SELECT netcashflow INTO v_m FROM spwatercashflow_summary(v_farm, NULL, NULL);

    -- 1. post: two lines, 15 of transport spread by value, 100 paid now
    v_rc := spwaterpurchasereceipt_post(v_farm, v_sup, d1::timestamp, 'INV-9', NULL, NULL,
              jsonb_build_array(jsonb_build_object('itemid', v_i1, 'quantity', 10, 'unitcost', 5),
                                jsonb_build_object('itemid', v_i2, 'quantity', 4, 'unitcost', 25)),
              15, 'transport', 100, 'Cash', v_acct, v_req, '__w462');
    SELECT waterrawmaterialpurchaseid INTO v_lot1 FROM waterpurchasereceiptlines WHERE waterpurchasereceiptid = v_rc AND lineno = 1;
    SELECT waterrawmaterialpurchaseid INTO v_lot2 FROM waterpurchasereceiptlines WHERE waterpurchasereceiptid = v_rc AND lineno = 2;
    IF (SELECT totalcost FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot1) <> 55
       OR (SELECT totalcost FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot2) <> 110 THEN
        RAISE EXCEPTION 'FAIL 1a: landed cost not spread (% / %)',
            (SELECT totalcost FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot1),
            (SELECT totalcost FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot2);
    END IF;
    SELECT watersupplierpaymentid INTO v_pay FROM waterpurchasereceipts WHERE waterpurchasereceiptid = v_rc;
    IF v_pay IS NULL OR (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 9900 THEN
        RAISE EXCEPTION 'FAIL 1b: payment / cash';
    END IF;
    IF (SELECT amountpaid FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot1) <> 55
       OR (SELECT amountpaid FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_lot2) <> 45 THEN
        RAISE EXCEPTION 'FAIL 1c: payment not allocated line by line';
    END IF;
    IF (SELECT SUM(balance) FROM fnwaterpayables(v_farm) WHERE documenttype = 'RawMaterialPurchase' AND documentid IN (v_lot1, v_lot2)) <> 65 THEN
        RAISE EXCEPTION 'FAIL 1d: payable';
    END IF;
    SELECT currentquantity INTO v_q1 FROM waterrawmaterialitems WHERE waterrawmaterialitemid = v_i1;
    SELECT currentquantity INTO v_q2 FROM waterrawmaterialitems WHERE waterrawmaterialitemid = v_i2;
    IF v_q1 <> 10 OR v_q2 <> 4 THEN RAISE EXCEPTION 'FAIL 1e: stock % / %', v_q1, v_q2; END IF;
    IF spwaterpurchasereceipt_post(v_farm, v_sup, d1::timestamp, 'INV-9', NULL, NULL,
              jsonb_build_array(jsonb_build_object('itemid', v_i1, 'quantity', 10, 'unitcost', 5)),
              0, NULL, 0, NULL, NULL, v_req, '__w462') <> v_rc THEN
        RAISE EXCEPTION 'FAIL 1f: a double Save received twice';
    END IF;
    v_err := pg_temp.w462_refused(format('SELECT spwaterpurchasereceipt_post(%L, %s, %L::timestamp, %L, NULL, NULL, %L::jsonb, 0, NULL, 0, NULL, NULL, NULL, %L)',
              v_farm, v_sup, d1, 'inv-9 ', jsonb_build_array(jsonb_build_object('itemid', v_i1, 'quantity', 1, 'unitcost', 1)), '__w462'));
    IF v_err IS NULL OR v_err NOT LIKE '%already received%' THEN RAISE EXCEPTION 'FAIL 1g: duplicate invoice: %', v_err; END IF;
    RAISE NOTICE 'ok 1 post: landed cost, one payment allocated by line, payable, stock, no duplicates';

    -- 2. a receipt's lot cannot be edited or deleted on its own
    v_err := pg_temp.w462_refused(format('UPDATE waterrawmaterialpurchases SET unitcost = 1 WHERE waterrawmaterialpurchaseid = %s', v_lot1));
    IF v_err IS NULL OR v_err NOT LIKE '%purchase receipt%' THEN RAISE EXCEPTION 'FAIL 2a: %', v_err; END IF;
    v_err := pg_temp.w462_refused(format('SELECT spwaterrawmaterialpurchase_delete(%s, %L)', v_lot1, v_farm));
    IF v_err IS NULL OR v_err NOT LIKE '%Reverse the receipt%' THEN RAISE EXCEPTION 'FAIL 2b: %', v_err; END IF;
    RAISE NOTICE 'ok 2 receipt lots are locked';

    -- 3. a drawn lot blocks the reversal
    UPDATE waterrawmaterialpurchases SET remainingquantity = remainingquantity - 1 WHERE waterrawmaterialpurchaseid = v_lot1;
    IF NOT EXISTS (SELECT 1 FROM spwaterpurchasereceipt_reversalblockers(v_farm, v_rc) WHERE code = 'Consumed') THEN
        RAISE EXCEPTION 'FAIL 3: consumed stock not blocking';
    END IF;
    UPDATE waterrawmaterialpurchases SET remainingquantity = remainingquantity + 1 WHERE waterrawmaterialpurchaseid = v_lot1;
    RAISE NOTICE 'ok 3 used stock blocks the reversal';

    -- 4. reverse: payment back, stock out, nothing owed, history kept
    PERFORM spwaterpurchasereceipt_reverse(v_farm, v_rc, 'wrong supplier', '__w462');
    IF (SELECT status FROM waterpurchasereceipts WHERE waterpurchasereceiptid = v_rc) <> 'Reversed' THEN RAISE EXCEPTION 'FAIL 4a'; END IF;
    IF (SELECT status FROM watersupplierpayments WHERE watersupplierpaymentid = v_pay) <> 'Reversed' THEN RAISE EXCEPTION 'FAIL 4b'; END IF;
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 10000 THEN RAISE EXCEPTION 'FAIL 4c: cash'; END IF;
    IF (SELECT currentquantity FROM waterrawmaterialitems WHERE waterrawmaterialitemid = v_i1) <> 0
       OR (SELECT currentquantity FROM waterrawmaterialitems WHERE waterrawmaterialitemid = v_i2) <> 0 THEN RAISE EXCEPTION 'FAIL 4d: stock'; END IF;
    IF EXISTS (SELECT 1 FROM fnwaterpayables(v_farm) WHERE documenttype = 'RawMaterialPurchase' AND documentid IN (v_lot1, v_lot2)) THEN
        RAISE EXCEPTION 'FAIL 4e: a reversed lot is still owed';
    END IF;
    IF (SELECT COUNT(*) FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid IN (v_lot1, v_lot2) AND reversedat IS NOT NULL) <> 2 THEN
        RAISE EXCEPTION 'FAIL 4f: lots not kept and stamped';
    END IF;
    IF NOT (SELECT bool_and(isreversed) FROM spwaterrawmaterialpurchase_getall(v_farm) WHERE waterrawmaterialpurchaseid IN (v_lot1, v_lot2)) THEN
        RAISE EXCEPTION 'FAIL 4g: purchase list does not say reversed';
    END IF;
    SELECT netcashflow INTO v_n FROM spwatercashflow_summary(v_farm, NULL, NULL);
    IF v_n <> v_m THEN RAISE EXCEPTION 'FAIL 4h: Cash Flow net % before the receipt, % after its reversal', v_m, v_n; END IF;
    v_err := pg_temp.w462_refused(format('SELECT spwaterpurchasereceipt_reverse(%L, %s, %L)', v_farm, v_rc, 'again'));
    IF v_err IS NULL OR v_err NOT LIKE '%already reversed%' THEN RAISE EXCEPTION 'FAIL 4i: %', v_err; END IF;
    RAISE NOTICE 'ok 4 reverse: cash back, stock out, nothing owed, rows kept';

    -- 5. the same invoice can be received again, correctly
    v_rc2 := spwaterpurchasereceipt_post(v_farm, v_sup, d1::timestamp, 'INV-9', NULL, NULL,
              jsonb_build_array(jsonb_build_object('itemid', v_i1, 'quantity', 10, 'unitcost', 5)),
              0, NULL, 0, NULL, NULL, NULL, '__w462');
    IF (SELECT status FROM waterpurchasereceipts WHERE waterpurchasereceiptid = v_rc2) <> 'Posted' THEN RAISE EXCEPTION 'FAIL 5'; END IF;
    RAISE NOTICE 'ok 5 a reversed invoice can be received again';

    -- 6. a later supplier payment applied to a receipt blocks its reversal
    SELECT waterrawmaterialpurchaseid INTO v_lot1 FROM waterpurchasereceiptlines WHERE waterpurchasereceiptid = v_rc2;
    PERFORM spwatersupplierpayment_record(v_farm, v_sup, 20,
              jsonb_build_array(jsonb_build_object('documenttype', 'RawMaterialPurchase', 'documentid', v_lot1, 'amount', 20)),
              'Cash', d1::timestamp, v_acct, NULL, NULL, 'SupplierBalances', '__w462');
    v_err := pg_temp.w462_refused(format('SELECT spwaterpurchasereceipt_reverse(%L, %s, %L)', v_farm, v_rc2, 'x'));
    IF v_err IS NULL OR v_err NOT LIKE '%Supplier Payments%' THEN RAISE EXCEPTION 'FAIL 6: %', v_err; END IF;
    RAISE NOTICE 'ok 6 another payment on the receipt blocks the reversal';

    -- 7. a plain stock adjustment works (it failed on every call before 462)
    SELECT currentquantity INTO v_n FROM waterrawmaterialitems WHERE waterrawmaterialitemid = v_i2;
    PERFORM spwaterrawmaterialitem_adjust(v_farm, v_i2, 3, 1, 'Correction', 'count', '__w462');
    IF (SELECT currentquantity FROM waterrawmaterialitems WHERE waterrawmaterialitemid = v_i2) <> v_n + 3 THEN RAISE EXCEPTION 'FAIL 7'; END IF;
    RAISE NOTICE 'ok 7 stock adjustment works';

    RAISE NOTICE 'water 462: all checks passed';
END
$t$;

ROLLBACK;
