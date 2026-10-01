-- Self-test for migration 334 (Hotel supply purchases, Internal Use, Deferred
-- inventory cost). Always ends by raising; "SELFTEST PASSED" is success.
--
-- Soap (Toiletries, expensed when consumed) has 10 old units; 100 are bought for
-- 200 (50 paid now, 150 owed). 20 towels (Linen, expensed when purchased) are
-- bought for 400 cash. Housekeeping uses 30 soap and 5 towels; the supplier is
-- paid 150; a credit purchase is reversed; the internal use is reversed. Every
-- step checks stock, lots, the ledger, Supplier Balances, P&L and Cash Flow.
DO $$
DECLARE
    f text := '__probe334__';
    v_main int; v_supp int; v_soap int; v_towel int;
    v_p1 int; v_p2 int; v_p3 int; v_iu int; v_sp int;
    v_n numeric; v_n2 numeric; v_failed boolean; v_checks int := 0; r record;
    v_today date := CURRENT_DATE;
BEGIN
    INSERT INTO hotelcashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance)
    VALUES (f, 'Main', 'Cash', 5000, 5000) RETURNING hotelcashaccountid INTO v_main;
    v_supp := sphotelsupplier_insert(f, 'Amenity Co', 'ProductSupplier', NULL, NULL, NULL, NULL, 14, 0, NULL, 'probe');
    INSERT INTO hotelinventoryitems (farmid, name, category, unit, stockonhand, reorderlevel, unitcost)
    VALUES (f, 'Soap', 'Toiletries', 'bar', 10, 5, 1) RETURNING hotelinventoryitemid INTO v_soap;
    INSERT INTO hotelinventoryitems (farmid, name, category, unit, stockonhand, reorderlevel, unitcost)
    VALUES (f, 'Towel', 'Linen', 'pc', 0, 5, 0) RETURNING hotelinventoryitemid INTO v_towel;
    PERFORM sphotelsupply_costmode_set(f, 'Toiletries', 'EXPENSE_WHEN_CONSUMED', 'probe');
    IF (SELECT costmode FROM sphotelsupply_costmode_list(f) WHERE category = 'Toiletries') <> 'EXPENSE_WHEN_CONSUMED'
       OR (SELECT costmode FROM sphotelsupply_costmode_list(f) WHERE category = 'Linen') <> 'EXPENSE_WHEN_PURCHASED' THEN
        RAISE EXCEPTION 'FAIL 1a: cost modes'; END IF;
    v_checks := v_checks + 1;

    -- ── 2. Purchases ───────────────────────────────────────────────────────
    v_p1 := sphotelsupplypurchase_create(f, v_soap, 100, 200, v_today - 2, v_supp, NULL, 'Cash', 50, v_main, v_today + 10, NULL, 'probe');
    v_p2 := sphotelsupplypurchase_create(f, v_towel, 20, 400, v_today - 2, NULL, NULL, 'Cash', NULL, v_main, NULL, NULL, 'probe');
    SELECT * INTO r FROM hotelsupplypurchases WHERE purchaseid = v_p1;
    IF r.costmode <> 'EXPENSE_WHEN_CONSUMED' OR r.deferredtotalcost <> 200 OR r.remainingquantity <> 100 OR r.cashtransactionid IS NULL THEN
        RAISE EXCEPTION 'FAIL 2a: soap lot %', row_to_json(r); END IF;
    IF (SELECT stockonhand FROM hotelinventoryitems WHERE hotelinventoryitemid = v_soap) <> 110
       OR (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 4550 THEN
        RAISE EXCEPTION 'FAIL 2b: stock or cash after purchases'; END IF;
    IF (SELECT totalbalance FROM sphotelsupplierbalances(f) WHERE partyid = v_supp) <> 150
       OR (SELECT currentbalance FROM hotelsuppliers WHERE hotelsupplierid = v_supp) <> 150
       OR (SELECT documenttype FROM sphotelsupplieropenpurchases(f, v_supp)) <> 'Purchase' THEN
        RAISE EXCEPTION 'FAIL 2c: payable'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelsupplypurchase_create(f, v_towel, 1, 10, v_today, NULL, NULL, 'Credit', NULL, NULL, NULL, NULL, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2d: credit purchase without a supplier accepted'; END IF;
    v_checks := v_checks + 4;

    -- ── 3. Internal use: posting draws through the lots ────────────────────
    v_iu := sphotelinternalusage_insert(f, v_today - 1, 'Housekeeping', 'Rooms 101-110', NULL, NULL, NULL,
              json_build_array(json_build_object('itemId', v_soap, 'entryQuantity', 30),
                               json_build_object('itemId', v_towel, 'entryQuantity', 5))::text, 'probe');
    v_failed := FALSE;
    BEGIN PERFORM sphotelinternalusage_insert(f, v_today, 'Party', NULL); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3a: unknown reason accepted'; END IF;
    PERFORM sphotelinternalusage_post(v_iu, f, 'probe');
    SELECT * INTO r FROM sphotelinternalusage_getbyid(v_iu, f);
    -- 10 old soap first (no cost), then 20 from the lot: 200 x 20/100 = 40. Towels were expensed when bought.
    IF r.status <> 'Posted' OR r.plcost <> 40 OR r.totalcostvalue <= 0 THEN RAISE EXCEPTION 'FAIL 3b: posted %', row_to_json(r); END IF;
    IF (SELECT stockonhand FROM hotelinventoryitems WHERE hotelinventoryitemid = v_soap) <> 80
       OR (SELECT remainingquantity FROM hotelsupplypurchases WHERE purchaseid = v_p1) <> 80
       OR (SELECT deferredremainingcost FROM hotelsupplypurchases WHERE purchaseid = v_p1) <> 160 THEN
        RAISE EXCEPTION 'FAIL 3c: stock / lot after posting'; END IF;
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 4550 THEN
        RAISE EXCEPTION 'FAIL 3d: internal use moved cash'; END IF;
    v_failed := FALSE;
    BEGIN
        PERFORM sphotelinternalusage_post(sphotelinternalusage_insert(f, v_today, 'Damaged', NULL, NULL, NULL, NULL,
                  json_build_array(json_build_object('itemId', v_towel, 'entryQuantity', 999))::text, 'probe'), f, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3e: more than in stock accepted'; END IF;
    SELECT * INTO r FROM sphotelreport_plsummary(f, v_today - 30, v_today);
    IF (SELECT amount FROM sphotelreport_pllines(f, v_today - 30, v_today) WHERE linekey = 'SuppliesUsed') <> 40
       OR (SELECT amount FROM sphotelreport_pllines(f, v_today - 30, v_today) WHERE linekey = 'SuppliesPurchased') <> 400
       OR EXISTS (SELECT 1 FROM sphotelreport_pllines(f, v_today - 30, v_today) WHERE linekey = 'SuppliesPurchased' AND amount = 600)
       OR r.totalexpenses <> 440 THEN
        RAISE EXCEPTION 'FAIL 3f: P&L supply lines %', row_to_json(r); END IF;
    IF (SELECT SUM(amount) FROM sphotelreport_plexpensedetail(f, v_today - 30, v_today, 'SuppliesUsed')) <> 40 THEN
        RAISE EXCEPTION 'FAIL 3g: supplies-used drilldown'; END IF;
    v_checks := v_checks + 7;

    -- ── 4. Deferred inventory cost page ────────────────────────────────────
    SELECT * INTO r FROM sphotelsupply_deferred_getall(f) WHERE purchaseid = v_p1;
    IF r.deferredremainingcost <> 160 OR r.recognizedcost <> 40 OR r.status <> 'Partly expensed' OR r.recognitiondrift <> 0 THEN
        RAISE EXCEPTION 'FAIL 4a: deferred row %', row_to_json(r); END IF;
    IF EXISTS (SELECT 1 FROM sphotelsupply_deferred_getall(f) WHERE purchaseid = v_p2) THEN
        RAISE EXCEPTION 'FAIL 4b: expensed-at-purchase lot listed as deferred'; END IF;
    IF (SELECT remainingdeferredcost FROM sphotelsupply_deferred_summary(f)) <> 160
       OR (SELECT count(*) FROM sphotelsupply_deferred_history(f, v_p1)) <> 1 THEN
        RAISE EXCEPTION 'FAIL 4c: summary / history'; END IF;
    v_checks := v_checks + 3;

    -- ── 5. Guards, supplier payment, purchase reversal ─────────────────────
    v_failed := FALSE;
    BEGIN PERFORM sphotelsupplypurchase_reverse(f, v_p1, 'wrong', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5a: used purchase reversed'; END IF;
    v_sp := sphotelsupplierpayment_record(f, v_supp, 150,
              jsonb_build_array(jsonb_build_object('documenttype', 'Purchase', 'documentid', v_p1, 'amount', 150)),
              'Cash', NULL, v_main, NULL, NULL, 'SupplierBalances', 'probe');
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 4400
       OR EXISTS (SELECT 1 FROM sphotelsupplierbalances(f) WHERE partyid = v_supp)
       OR (SELECT currentbalance FROM hotelsuppliers WHERE hotelsupplierid = v_supp) <> 0
       OR (SELECT paymentstatus FROM sphotelsupplypurchase_list(f) WHERE purchaseid = v_p1) <> 'Paid' THEN
        RAISE EXCEPTION 'FAIL 5b: after paying the purchase'; END IF;
    v_p3 := sphotelsupplypurchase_create(f, v_towel, 10, 100, v_today, v_supp, NULL, 'Credit', NULL, NULL, NULL, NULL, 'probe');
    IF (SELECT currentbalance FROM hotelsuppliers WHERE hotelsupplierid = v_supp) <> 100 THEN RAISE EXCEPTION 'FAIL 5c: credit purchase ledger'; END IF;
    PERFORM sphotelsupplypurchase_reverse(f, v_p3, 'duplicate delivery', 'probe');
    IF (SELECT currentbalance FROM hotelsuppliers WHERE hotelsupplierid = v_supp) <> 0
       OR (SELECT stockonhand FROM hotelinventoryitems WHERE hotelinventoryitemid = v_towel) <> 15
       OR EXISTS (SELECT 1 FROM sphotelsupplierbalances(f) WHERE partyid = v_supp) THEN
        RAISE EXCEPTION 'FAIL 5d: purchase reversal'; END IF;
    v_checks := v_checks + 4;

    -- ── 6. Reverse the internal use: lots and P&L come back ────────────────
    v_failed := FALSE;
    BEGIN PERFORM sphotelinternalusage_reverse(v_iu, f, ' ', 'probe'); EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6a: reversal without a reason'; END IF;
    PERFORM sphotelinternalusage_reverse(v_iu, f, 'entered twice', 'probe');
    IF (SELECT stockonhand FROM hotelinventoryitems WHERE hotelinventoryitemid = v_soap) <> 110
       OR (SELECT deferredremainingcost FROM hotelsupplypurchases WHERE purchaseid = v_p1) <> 200
       OR (SELECT remainingquantity FROM hotelsupplypurchases WHERE purchaseid = v_p1) <> 100
       OR (SELECT stockonhand FROM hotelinventoryitems WHERE hotelinventoryitemid = v_towel) <> 20 THEN
        RAISE EXCEPTION 'FAIL 6b: stock after reversal'; END IF;
    IF COALESCE((SELECT amount FROM sphotelreport_pllines(f, v_today - 30, v_today) WHERE linekey = 'SuppliesUsed'), 0) <> 0
       OR (SELECT plcost FROM sphotelinternalusage_getbyid(v_iu, f)) <> 0 THEN
        RAISE EXCEPTION 'FAIL 6c: P&L after reversal'; END IF;
    PERFORM sphotelinternalusage_post(v_iu, f, 'probe');   -- a reversed record may be posted again
    IF (SELECT plcost FROM sphotelinternalusage_getbyid(v_iu, f)) <> 40 THEN RAISE EXCEPTION 'FAIL 6d: re-post'; END IF;
    v_checks := v_checks + 4;

    -- ── 7. Cash Flow = ledger = account ────────────────────────────────────
    SELECT COALESCE(SUM(amount), 0) INTO v_n FROM sphotelcashflow_rows(f, NULL, NULL);
    SELECT COALESCE(SUM(CASE WHEN txntype = 'Credit' THEN amount ELSE -amount END), 0) INTO v_n2 FROM hotelcashtransactions WHERE farmid = f;
    IF v_n <> v_n2 OR v_n2 <> -600 OR (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 4400 THEN
        RAISE EXCEPTION 'FAIL 7a: cash flow % ledger %', v_n, v_n2; END IF;
    IF EXISTS (SELECT 1 FROM sphotelcashflow_detail(f, NULL, NULL) WHERE category = 'Other')
       OR (SELECT count(*) FROM sphotelcashflow_detail(f, NULL, NULL) WHERE category = 'Supplies') <> 2 THEN
        RAISE EXCEPTION 'FAIL 7b: cash flow categories'; END IF;
    IF EXISTS (SELECT 1 FROM sphotelbalanceaudit(f)) THEN RAISE EXCEPTION 'FAIL 7c: audit'; END IF;
    v_checks := v_checks + 3;

    RAISE EXCEPTION 'SELFTEST PASSED (% checks)', v_checks;
END $$;
