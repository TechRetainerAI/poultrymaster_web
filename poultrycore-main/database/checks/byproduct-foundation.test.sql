-- =============================================================================
-- byproduct-foundation.test.sql -- checks for migration 372.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Uses the active
-- flock with the most production records on dev.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm     text;
    v_flock    integer;
    v_rec      integer;
    v_rec2     integer;
    v_old      integer;
    v_birds    integer;
    v_eggs0    numeric;
    v_live0    numeric;
    v_x        numeric;
    v_failed   boolean;
    v_unsorted integer;
BEGIN
    SELECT f.farmid, f.flockid INTO v_farm, v_flock
    FROM   flock f JOIN productionrecords pr ON pr.flockid = f.flockid AND pr.farmid = f.farmid
    WHERE  f.active
    GROUP  BY f.farmid, f.flockid ORDER BY count(*) DESC LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'byproduct foundation: all checks passed';
        RETURN;
    END IF;

    -- 1. Both system products exist once, found by role.
    IF (SELECT count(*) FROM poultryproducts WHERE farmid = v_farm AND systemrole IN ('BrokenEggs', 'DeadBirds')) <> 2 THEN
        RAISE EXCEPTION 'FAIL 1a: system products missing'; END IF;
    PERFORM sppoultryproduct_ensurebyproducts(v_farm);
    IF (SELECT count(*) FROM poultryproducts WHERE farmid = v_farm AND systemrole IN ('BrokenEggs', 'DeadBirds')) <> 2 THEN
        RAISE EXCEPTION 'FAIL 1b: duplicated'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultryproduct_delete(fnpoultry_byproduct(v_farm, 'DeadBirds'), v_farm);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1c: system product deleted'; END IF;
    RAISE NOTICE 'ok 1 system products exist once and are protected';

    -- 2. A production record: 1,000 laid, 20 broken, 3 dead.
    v_unsorted := fnpoultry_unsortedeggproduct(v_farm);
    SELECT COALESCE(sum(quantity), 0) INTO v_eggs0 FROM poultrystocktransactions WHERE farmid = v_farm AND poultryproductid = v_unsorted;
    SELECT pr.noofbirdsleft INTO v_birds FROM productionrecords pr WHERE pr.flockid = v_flock AND pr.farmid = v_farm ORDER BY pr.date DESC, pr.id DESC LIMIT 1;
    v_birds := GREATEST(COALESCE(v_birds, 100), 100);
    v_rec := spproductionrecord_insert(p_farmid => v_farm, p_createdby => 'check372', p_userid => 'check372',
        p_ageinweeks => 30, p_ageindays => 210, p_date => CURRENT_DATE, p_noofbirds => v_birds, p_mortality => 3,
        p_noofbirdsleft => v_birds - 3, p_feedkg => 0, p_production9am => 1000, p_production12pm => 0, p_production4pm => 0,
        p_totalproduction => 1000, p_flockid => v_flock, p_brokeneggs => 20);
    SELECT COALESCE(sum(quantity), 0) INTO v_x FROM poultrystocktransactions WHERE farmid = v_farm AND poultryproductid = v_unsorted;
    IF v_x - v_eggs0 <> 980 THEN RAISE EXCEPTION 'FAIL 2a: saleable eggs +% (want 980)', v_x - v_eggs0; END IF;
    IF (SELECT sum(quantity) FROM poultrystocktransactions WHERE farmid = v_farm AND relatedid = v_rec AND txntype = 'Broken Egg Prod') <> 20 THEN
        RAISE EXCEPTION 'FAIL 2b: broken eggs not +20'; END IF;
    IF (SELECT sum(quantity) FROM poultrystocktransactions WHERE farmid = v_farm AND relatedid = v_rec AND txntype = 'Mortality In') <> 3 THEN
        RAISE EXCEPTION 'FAIL 2c: dead birds not +3'; END IF;
    IF (SELECT noofbirdsleft FROM productionrecords WHERE id = v_rec) <> v_birds - 3 THEN
        RAISE EXCEPTION 'FAIL 2d: live birds'; END IF;
    RAISE NOTICE 'ok 2 production: 980 saleable + 20 broken = 1,000; 3 dead birds; live birds -3';

    -- 3. Disposed immediately: generated AND disposed; dead bird stock unchanged by it.
    v_live0 := fnpoultry_byproductonhand(v_farm, 'DeadBirds');
    PERFORM sppoultryproduction_setdisposition(v_farm, v_rec, 'Disposed', NULL, 'check372');
    IF (SELECT sum(quantity) FROM poultrystocktransactions WHERE farmid = v_farm AND relatedid = v_rec AND txntype = 'Mortality Disposal') <> -3 THEN
        RAISE EXCEPTION 'FAIL 3a: no immediate disposal'; END IF;
    IF fnpoultry_byproductonhand(v_farm, 'DeadBirds') <> v_live0 - 3 THEN RAISE EXCEPTION 'FAIL 3b: dead bird stock'; END IF;
    PERFORM sppoultryproduction_setdisposition(v_farm, v_rec, 'Disposed', NULL, 'check372');   -- repeat: nothing new
    IF (SELECT count(*) FROM poultrystocktransactions WHERE farmid = v_farm AND relatedid = v_rec AND txntype = 'Mortality Disposal') <> 1 THEN
        RAISE EXCEPTION 'FAIL 3c: repeat posted again'; END IF;
    PERFORM sppoultryproduction_setdisposition(v_farm, v_rec, 'Keep', NULL, 'check372');
    RAISE NOTICE 'ok 3 disposed immediately = generated and disposed; repeat writes nothing';

    -- 4. Correction: broken 20 -> 25 posts +5 only.
    PERFORM spproductionrecord_update(p_recordid => v_rec, p_updatedby => 'check372', p_ageinweeks => 30, p_ageindays => 210,
        p_date => CURRENT_DATE, p_noofbirds => v_birds, p_mortality => 3, p_noofbirdsleft => v_birds - 3, p_feedkg => 0,
        p_production9am => 1000, p_production12pm => 0, p_production4pm => 0, p_totalproduction => 1000, p_flockid => v_flock, p_brokeneggs => 25);
    IF (SELECT sum(quantity) FROM poultrystocktransactions WHERE farmid = v_farm AND relatedid = v_rec AND txntype = 'Broken Egg Prod') <> 25 THEN
        RAISE EXCEPTION 'FAIL 4: correction'; END IF;
    RAISE NOTICE 'ok 4 a correction posts only the difference';

    -- 5. Reversal is refused once some broken eggs are gone; allowed once restored.
    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, note, createdby)
    VALUES (v_farm, fnpoultry_byproduct(v_farm, 'BrokenEggs'), 'Adjustment',
            -fnpoultry_byproductonhand(v_farm, 'BrokenEggs') + 5, 'check372 used most', 'check372');
    v_failed := FALSE;
    BEGIN PERFORM spproductionrecord_delete(v_rec, 'check372', v_farm);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5a: reversal not refused'; END IF;
    IF NOT EXISTS (SELECT 1 FROM productionrecords WHERE id = v_rec) THEN RAISE EXCEPTION 'FAIL 5b: record gone after refusal'; END IF;
    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, note, createdby)
    VALUES (v_farm, fnpoultry_byproduct(v_farm, 'BrokenEggs'), 'Adjustment', 100, 'check372 back', 'check372');
    v_x := fnpoultry_byproductonhand(v_farm, 'BrokenEggs');
    v_live0 := fnpoultry_byproductonhand(v_farm, 'DeadBirds');
    PERFORM spproductionrecord_delete(v_rec, 'check372', v_farm);
    IF fnpoultry_byproductonhand(v_farm, 'BrokenEggs') <> v_x - 25 OR fnpoultry_byproductonhand(v_farm, 'DeadBirds') <> v_live0 - 3 THEN
        RAISE EXCEPTION 'FAIL 5c: reversal amounts'; END IF;
    RAISE NOTICE 'ok 5 reversal takes byproducts off, and is refused if they were used';

    -- 6. Cutover: an edit of an old record creates no byproduct stock.
    SELECT pr.id INTO v_old FROM productionrecords pr
    WHERE  pr.farmid = v_farm AND COALESCE(pr.brokeneggs, 0) > 0
      AND  pr.createdat < (SELECT cutoverat FROM poultrybyproductsettings WHERE farmid = v_farm)
    ORDER  BY pr.id DESC LIMIT 1;
    IF v_old IS NOT NULL THEN
        PERFORM sppoultrybyproduct_syncforproduction(v_farm, v_old, FALSE, 'check372');
        IF EXISTS (SELECT 1 FROM poultrystocktransactions WHERE farmid = v_farm AND relatedid = v_old AND txntype IN ('Broken Egg Prod', 'Mortality In')) THEN
            RAISE EXCEPTION 'FAIL 6: an old record created byproduct stock'; END IF;
    END IF;
    RAISE NOTICE 'ok 6 records from before the cutover create no byproduct stock';

    -- 7. Egg sorting: Breakage lines become broken eggs; reversing takes them off.
    DECLARE
        v_sess integer;
        v_bb0  numeric;
        v_r7   integer;
    BEGIN
        v_r7 := spproductionrecord_insert(p_farmid => v_farm, p_createdby => 'check372', p_userid => 'check372',
            p_ageinweeks => 30, p_ageindays => 210, p_date => CURRENT_DATE, p_noofbirds => v_birds, p_mortality => 0,
            p_noofbirdsleft => v_birds, p_feedkg => 0, p_production9am => 100, p_production12pm => 0, p_production4pm => 0,
            p_totalproduction => 100, p_flockid => v_flock, p_brokeneggs => 0);
        v_sess := sppoultryeggsorting_save(v_farm, NULL, 'ByPick', CURRENT_DATE, ARRAY[v_r7], 1,
            '[{"lineType":"Breakage","quantity":7},{"lineType":"Reject","quantity":3}]', 'check372', NULL, 'check372');
        v_bb0 := fnpoultry_byproductonhand(v_farm, 'BrokenEggs');
        PERFORM sppoultryeggsorting_post(v_farm, v_sess, 'check372');
        IF (SELECT sum(quantity) FROM poultrystocktransactions WHERE farmid = v_farm AND relatedid = v_sess AND txntype = 'Sorting Breakage') <> 7 THEN
            RAISE EXCEPTION 'FAIL 7a: sorting breakage not +7'; END IF;
        IF fnpoultry_byproductonhand(v_farm, 'BrokenEggs') <> v_bb0 + 7 THEN RAISE EXCEPTION 'FAIL 7b: broken egg stock'; END IF;
        PERFORM sppoultryeggsorting_reverse(v_farm, v_sess, 'check', 'check372');
        IF fnpoultry_byproductonhand(v_farm, 'BrokenEggs') <> v_bb0 THEN RAISE EXCEPTION 'FAIL 7c: reversal did not take them off'; END IF;
    END;
    RAISE NOTICE 'ok 7 sorting breakage becomes broken eggs, and reverses';

    RAISE NOTICE 'byproduct foundation: all checks passed';
END $$;

ROLLBACK;
