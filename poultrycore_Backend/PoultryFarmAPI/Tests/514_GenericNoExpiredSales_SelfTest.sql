-- Self-test for migration 514 (no sale of expired stock). ROLLS BACK: ends with 'RESULT (rolled back): ...'.
--   cd poultrycore_Backend/Tools/RunMigration; dotnet run -- ../../PoultryFarmAPI/Tests/514_GenericNoExpiredSales_SelfTest.sql
-- Setup: 150 tablets = GOOD 100 (in date) + OLD 50 (expired yesterday).
-- Expected: sell 120 refused | sell 100 ok, GOOD=0 OLD=50 | sell 1 more refused | write-off OLD ok, stock=0.

DO $t$
DECLARE
    v_farm TEXT; v_sup INT; v_pid INT; v_pur INT; v_good INT; v_old INT; v_out TEXT := '';
BEGIN
    SELECT s.farmid, s.genericsupplierid INTO v_farm, v_sup FROM genericsuppliers s LIMIT 1;
    INSERT INTO genericproducts (farmid, productname, unitofmeasure, costprice, sellingprice, openingstock,
                                 currentstock, minimumstockalert, trackinventory, trackexpiry, isactive, isdeleted, createdat, updatedat)
    VALUES (v_farm, 'RXTEST514 Paracetamol', 'tablet', 0.2, 0.5, 0, 0, 0, TRUE, TRUE, TRUE, FALSE, now(), now())
    RETURNING genericproductid INTO v_pid;

    -- (Batches inserted directly, so the test does not depend on purchase approval.)
    UPDATE genericproducts SET currentstock = 150 WHERE genericproductid = v_pid;
    INSERT INTO genericproductbatches (farmid, genericproductid, batchnumber, expirydate, quantityreceived,
                                       quantityremaining, unitcost, receiveddate, sourcetype, notes, createdby)
    VALUES (v_farm, v_pid, 'GOOD', CURRENT_DATE + 200, 100, 100, 0.2, CURRENT_DATE, 'Manual', 'test', 'test')
    RETURNING genericproductbatchid INTO v_good;
    INSERT INTO genericproductbatches (farmid, genericproductid, batchnumber, expirydate, quantityreceived,
                                       quantityremaining, unitcost, receiveddate, sourcetype, notes, createdby)
    VALUES (v_farm, v_pid, 'OLD', CURRENT_DATE + 10, 50, 50, 0.2, CURRENT_DATE, 'Manual', 'test', 'test')
    RETURNING genericproductbatchid INTO v_old;
    UPDATE genericproductbatches SET expirydate = CURRENT_DATE - 1 WHERE genericproductbatchid = v_old;  -- now expired
    v_out := 'stock=' || (SELECT currentstock FROM genericproducts WHERE genericproductid = v_pid);

    BEGIN
        INSERT INTO genericstockmovements (farmid, genericproductid, movementdate, movementtype, quantity, referencetype, referenceid, reason, createdby)
        VALUES (v_farm, v_pid, now(), 'SaleOut', -120, 'Sale', -514, 'test', 'test');
        v_out := v_out || ' | sell 120 NOT refused';
    EXCEPTION WHEN OTHERS THEN v_out := v_out || ' | sell 120 refused: ' || SQLERRM;
    END;

    INSERT INTO genericstockmovements (farmid, genericproductid, movementdate, movementtype, quantity, referencetype, referenceid, reason, createdby)
    VALUES (v_farm, v_pid, now(), 'SaleOut', -100, 'Sale', -515, 'test', 'test');
    UPDATE genericproducts SET currentstock = currentstock - 100 WHERE genericproductid = v_pid;
    v_out := v_out || ' | sell 100 ok GOOD=' || (SELECT quantityremaining FROM genericproductbatches WHERE genericproductbatchid = v_good)
                   || ' OLD=' || (SELECT quantityremaining FROM genericproductbatches WHERE genericproductbatchid = v_old);

    BEGIN
        INSERT INTO genericstockmovements (farmid, genericproductid, movementdate, movementtype, quantity, referencetype, referenceid, reason, createdby)
        VALUES (v_farm, v_pid, now(), 'SaleOut', -1, 'Sale', -516, 'test', 'test');
        v_out := v_out || ' | sell 1 more NOT refused';
    EXCEPTION WHEN OTHERS THEN v_out := v_out || ' | sell 1 more refused';
    END;

    PERFORM spgenericproductbatch_writeoff(v_farm, v_old, 50, 'test expired', 'test');
    v_out := v_out || ' | write-off OLD ok, stock=' || (SELECT currentstock FROM genericproducts WHERE genericproductid = v_pid)
                   || ' OLD=' || (SELECT quantityremaining FROM genericproductbatches WHERE genericproductbatchid = v_old);

    RAISE EXCEPTION 'RESULT (rolled back): %', v_out;
END
$t$;
