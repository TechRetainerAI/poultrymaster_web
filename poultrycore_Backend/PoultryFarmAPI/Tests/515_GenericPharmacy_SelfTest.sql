-- Self-test for migration 515 (Generic Pharmacy). Runs a full scenario on the dev DB and ROLLS BACK:
-- the last statement raises 'RESULT (rolled back): ...' with the figures. Run with
--   cd poultrycore_Backend/Tools/RunMigration; dotnet run -- ../../PoultryFarmAPI/Tests/511_GenericPharmacy_SelfTest.sql
-- Expected: packs=2 conv=2 | 300 A=200 B=100 | reverse C -> 300, C gone | manual add refused | out 50 -> B=50 |
-- write-off A 20 -> A=180 | over write-off refused | class=A | expiring=50 | rx=1 | settings saved.

DO $t$
DECLARE
    v_farm TEXT; v_sup INT; v_pid INT; v_pur INT; v_adj INT; v_bA INT; v_bB INT;
    v_out TEXT := ''; v_msg TEXT; v_j JSONB;
BEGIN
    SELECT s.farmid, s.genericsupplierid INTO v_farm, v_sup FROM genericsuppliers s LIMIT 1;

    INSERT INTO genericproducts (farmid, productname, unitofmeasure, costprice, sellingprice, openingstock,
                                 currentstock, minimumstockalert, trackinventory, isactive, isdeleted, createdat, updatedat)
    VALUES (v_farm, 'RXTEST Amoxicillin 500mg', 'tablet', 0.5, 1, 0, 0, 0, TRUE, TRUE, FALSE, now(), now())
    RETURNING genericproductid INTO v_pid;

    PERFORM spgenericmedicine_save(v_farm, v_pid, jsonb_build_object(
        'genericName', 'Amoxicillin', 'strength', '500mg', 'dosageForm', 'Capsule', 'medicineClass', 'A',
        'packs', jsonb_build_array(
            jsonb_build_object('packName', 'Strip', 'unitsPerPack', 10, 'sellingPrice', 8),
            jsonb_build_object('packName', 'Box', 'unitsPerPack', 100, 'sellingPrice', 70))), 'test');
    v_out := v_out || ' packs=' || (SELECT count(*) FROM genericproductpacks WHERE genericproductid = v_pid AND isactive)
                   || ' conv=' || (SELECT count(*) FROM genericuomconversions WHERE genericproductid = v_pid);

    v_pur := spgenericpurchase_insert(p_farmid => v_farm, p_genericsupplierid => v_sup, p_amountpaid => 0,
        p_items => jsonb_build_array(
            jsonb_build_object('genericproductid', v_pid, 'quantity', 2, 'unitcost', 40, 'discountamount', 0, 'purchaseunit', 'Box', 'unitfactor', 100),
            jsonb_build_object('genericproductid', v_pid, 'quantity', 1, 'unitcost', 40, 'discountamount', 0, 'purchaseunit', 'Box', 'unitfactor', 100)));
    PERFORM spgenericpurchase_setbatches(v_farm, v_pur, jsonb_build_array(
        jsonb_build_object('genericProductId', v_pid, 'batchNumber', 'A-LONG', 'expiryDate', (CURRENT_DATE + 400)::text),
        jsonb_build_object('genericProductId', v_pid, 'batchNumber', 'B-SOON', 'expiryDate', (CURRENT_DATE + 30)::text)));
    PERFORM spgenericpurchase_approve(v_pur, v_farm, 'test');

    SELECT genericproductbatchid INTO v_bA FROM genericproductbatches WHERE genericproductid = v_pid AND batchnumber = 'A-LONG';
    SELECT genericproductbatchid INTO v_bB FROM genericproductbatches WHERE genericproductid = v_pid AND batchnumber = 'B-SOON';
    v_out := v_out || ' | after purchase stock=' || (SELECT currentstock FROM genericproducts WHERE genericproductid = v_pid)
        || ' A=' || (SELECT quantityremaining FROM genericproductbatches WHERE genericproductbatchid = v_bA)
        || ' B=' || (SELECT quantityremaining FROM genericproductbatches WHERE genericproductbatchid = v_bB);

    -- reverse a second purchase: its batch must go, the first purchase's batches stay
    DECLARE v_pur2 INT; BEGIN
        v_pur2 := spgenericpurchase_insert(p_farmid => v_farm, p_genericsupplierid => v_sup, p_amountpaid => 0,
            p_items => jsonb_build_array(jsonb_build_object('genericproductid', v_pid, 'quantity', 1, 'unitcost', 40, 'discountamount', 0, 'purchaseunit', 'Box', 'unitfactor', 100)));
        PERFORM spgenericpurchase_setbatches(v_farm, v_pur2, jsonb_build_array(jsonb_build_object('genericProductId', v_pid, 'batchNumber', 'C-REV', 'expiryDate', (CURRENT_DATE + 5)::text)));
        PERFORM spgenericpurchase_approve(v_pur2, v_farm, 'test');
        v_out := v_out || ' | with C stock=' || (SELECT currentstock FROM genericproducts WHERE genericproductid = v_pid);
        PERFORM spgenericpurchase_reverse(v_farm, v_pur2, 'Other', 'test reversal', '{}'::jsonb, NULL, NULL, 'test');
        v_out := v_out || ' | after reverse C stock=' || (SELECT currentstock FROM genericproducts WHERE genericproductid = v_pid)
            || ' A=' || (SELECT quantityremaining FROM genericproductbatches WHERE genericproductbatchid = v_bA)
            || ' B=' || (SELECT quantityremaining FROM genericproductbatches WHERE genericproductbatchid = v_bB)
            || ' Clive=' || (SELECT count(*) FROM genericproductbatches WHERE batchnumber = 'C-REV' AND genericproductid = v_pid AND NOT isdeleted);
    END;
    BEGIN
        PERFORM spgenericproductbatch_add(v_farm, v_pid, 'X', CURRENT_DATE + 10, 10);
        v_out := v_out || ' | manual add NOT refused';
    EXCEPTION WHEN OTHERS THEN v_out := v_out || ' | manual add refused: ' || SQLERRM;
    END;

    -- stock out 50 (like a sale): earliest expiry first -> B
    v_adj := spgenericstockadjustment_insert(v_farm, v_pid, 'Decrease', 50, 'test out', NULL, NULL, 'test');
    PERFORM spgenericstockadjustment_submit(v_adj, v_farm);
    PERFORM spgenericstockadjustment_approve(v_adj, v_farm, 'test');
    v_out := v_out || ' | after out 50 stock=' || (SELECT currentstock FROM genericproducts WHERE genericproductid = v_pid)
        || ' A=' || (SELECT quantityremaining FROM genericproductbatches WHERE genericproductbatchid = v_bA)
        || ' B=' || (SELECT quantityremaining FROM genericproductbatches WHERE genericproductbatchid = v_bB);

    -- write off 20 of A (the long one, to prove it is taken from the named batch)
    PERFORM spgenericproductbatch_writeoff(v_farm, v_bA, 20, 'test damage', 'test');
    v_out := v_out || ' | after write-off A 20 stock=' || (SELECT currentstock FROM genericproducts WHERE genericproductid = v_pid)
        || ' A=' || (SELECT quantityremaining FROM genericproductbatches WHERE genericproductbatchid = v_bA)
        || ' B=' || (SELECT quantityremaining FROM genericproductbatches WHERE genericproductbatchid = v_bB);

    BEGIN
        PERFORM spgenericproductbatch_writeoff(v_farm, v_bB, 999);
        v_out := v_out || ' | over write-off NOT refused';
    EXCEPTION WHEN OTHERS THEN v_out := v_out || ' | over write-off refused: ' || SQLERRM;
    END;

    v_j := spgenericmedicine_list(v_farm);
    SELECT e INTO v_j FROM jsonb_array_elements(v_j) e WHERE (e->>'genericProductId')::int = v_pid;
    v_out := v_out || ' | list: class=' || (v_j->>'medicineClass') || ' unbatched=' || (v_j->>'unbatchedQty')
        || ' nearest=' || (v_j->>'nearestExpiry') || ' batches=' || (v_j->>'batchCount');

    v_j := spgenericpharmacy_report(v_farm, CURRENT_DATE - 30, CURRENT_DATE, 90);
    SELECT e INTO v_j FROM jsonb_array_elements(v_j) e WHERE (e->>'genericProductId')::int = v_pid;
    v_out := v_out || ' | report expiring=' || (v_j->>'expiringQty') || ' stockValue=' || (v_j->>'stockValue');

    PERFORM spgenericprescription_create(v_farm, jsonb_build_object('patientName', 'Ama', 'prescriberName', 'Dr Mensah',
        'items', jsonb_build_array(jsonb_build_object('genericProductId', v_pid, 'medicineName', 'Amoxicillin', 'quantity', 21, 'unit', 'tablet'))), 'test');
    v_out := v_out || ' | rx=' || jsonb_array_length(spgenericprescription_list(v_farm, CURRENT_DATE, CURRENT_DATE));

    PERFORM spgenericpharmacy_settings_save(v_farm, 'ChemicalShop', TRUE, 60, 'test');
    v_out := v_out || ' | settings=' || spgenericpharmacy_settings_get(v_farm)::text;

    RAISE EXCEPTION 'RESULT (rolled back): %', v_out;
END
$t$;
