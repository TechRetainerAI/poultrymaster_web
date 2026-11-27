-- 502_Enock_GenericStockMovementsWholeDay. Self-contained: BEGIN ... ROLLBACK.
BEGIN;
DO $$
DECLARE v_farm text; v_prod integer; v_day date := current_date; v_n integer;
BEGIN
    SELECT p.farmid, p.genericproductid INTO v_farm, v_prod FROM genericproducts p ORDER BY p.genericproductid LIMIT 1;
    INSERT INTO genericstockmovements (farmid, genericproductid, movementdate, movementtype, quantity, referencetype, referenceid, reason, createdby)
    VALUES (v_farm, v_prod, v_day + time '00:00', 'AdjustmentIn', 1, 'Adjustment', -502, '502 midnight', '502-check'),
           (v_farm, v_prod, v_day + time '15:30', 'AdjustmentOut', -1, 'Adjustment', -502, '502 afternoon', '502-check'),
           (v_farm, v_prod, v_day + 1 + time '00:00', 'AdjustmentIn', 1, 'Adjustment', -502, '502 next day', '502-check');
    SELECT count(*) INTO v_n FROM spgenericstockmovement_getbyfarm(v_farm, v_day, v_day) WHERE referenceid = -502;
    IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL 502.1: % rows for the day (expected midnight + afternoon, not the next day)', v_n; END IF;
    SELECT count(*) INTO v_n FROM spgenericstockmovement_getbyfarm(v_farm, v_day, v_day + time '12:00') WHERE referenceid = -502;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 502.2: a "To" with a time must be used as given (got %)', v_n; END IF;
    RAISE NOTICE 'ok 502.1 a To date covers the whole day; a To with a time is exact';
    RAISE NOTICE 'generic 502: all checks passed';
END $$;
ROLLBACK;
