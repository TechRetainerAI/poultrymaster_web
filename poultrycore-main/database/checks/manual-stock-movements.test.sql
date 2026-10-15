-- =============================================================================
-- manual-stock-movements.test.sql -- checks for migration 373.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Uses the open,
-- batched flock with the most production records on dev.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm    text;
    v_flock   integer;
    v_batch   integer;
    v_other   integer;
    v_birds   integer;
    v_egg     integer;
    v_item    integer;
    v_res     jsonb;
    v_id      integer;
    v_id2     integer;
    v_live0   integer;
    v_farm0   integer;
    v_dead0   numeric;
    v_brk0    numeric;
    v_egg0    numeric;
    v_x       numeric;
    v_nrec    integer;
    v_mort    integer;
    v_failed  boolean;
    v_today   date;
BEGIN
    SELECT f.farmid, f.flockid, f.batchid INTO v_farm, v_flock, v_batch
    FROM   flock f JOIN productionrecords pr ON pr.flockid = f.flockid AND pr.farmid = f.farmid
    WHERE  f.active AND NOT f.isdeleted AND f.closeddate IS NULL AND f.batchid IS NOT NULL
    GROUP  BY f.farmid, f.flockid, f.batchid ORDER BY count(*) DESC LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'manual stock movements: all checks passed';
        RETURN;
    END IF;
    v_today := fncompany_businessdate(v_farm);
    PERFORM sppoultryproduct_ensurebyproducts(v_farm);
    SELECT p.poultryproductid INTO v_birds FROM poultryproducts p
    WHERE  p.farmid = v_farm AND (p.isbirdproduct OR p.name = 'Birds') AND p.systemrole IS NULL
    ORDER  BY p.isbirdproduct DESC, p.poultryproductid LIMIT 1;
    v_egg := fnpoultry_unsortedeggproduct(v_farm);
    SELECT b.batchid INTO v_other FROM mainflockbatch b WHERE b.farmid = v_farm AND b.batchid <> v_batch LIMIT 1;

    -- Room to take birds away.
    PERFORM sppoultrymanualmovement_post(v_farm, v_birds, NULL, 'Increase', 500, NULL, v_batch, v_flock, v_today,
        'Stock Count Correction', NULL, 'check373 room', NULL, 'check373');

    -- 1. Historical mortality, kept: live -180, Dead Birds +180, no production record touched for mortality.
    SELECT bp.currentlivebirds INTO v_live0 FROM fnflock_birdposition(v_farm, v_flock) bp;
    v_farm0 := fnpoultry_farmlivebirds(v_farm);
    v_dead0 := fnpoultry_byproductonhand(v_farm, 'DeadBirds');
    SELECT count(*), COALESCE(sum(mortality), 0) INTO v_nrec, v_mort FROM productionrecords WHERE farmid = v_farm AND flockid = v_flock;
    v_res := sppoultrymanualmovement_post(v_farm, v_birds, NULL, 'Decrease', 180, NULL, v_batch, v_flock, v_today - 15,
        'Historical Mortality', 'Keep', 'before onboarding', NULL, 'check373');
    v_id := (v_res->>'movementId')::int;
    IF (SELECT bp.currentlivebirds FROM fnflock_birdposition(v_farm, v_flock) bp) <> v_live0 - 180 THEN RAISE EXCEPTION 'FAIL 1a: flock live birds'; END IF;
    IF fnpoultry_farmlivebirds(v_farm) <> v_farm0 - 180 THEN RAISE EXCEPTION 'FAIL 1b: farm live birds'; END IF;
    IF fnpoultry_byproductonhand(v_farm, 'DeadBirds') <> v_dead0 + 180 THEN RAISE EXCEPTION 'FAIL 1c: dead birds'; END IF;
    IF (SELECT count(*) FROM productionrecords WHERE farmid = v_farm AND flockid = v_flock) <> v_nrec
       OR (SELECT sum(mortality) FROM productionrecords WHERE farmid = v_farm AND flockid = v_flock) <> v_mort THEN
        RAISE EXCEPTION 'FAIL 1d: a production record was created or its mortality changed'; END IF;
    IF NOT EXISTS (SELECT 1 FROM poultrybirdadjustments a WHERE a.manualmovementid = v_id AND a.reason = 'Historical Mortality'
                   AND a.adjustmentdate = v_today - 15 AND a.quantity = -180) THEN RAISE EXCEPTION 'FAIL 1e: adjustment not dated / reasoned'; END IF;
    IF NOT EXISTS (SELECT 1 FROM poultrystocktransactions t WHERE t.manualmovementid = v_id AND t.txntype = 'Bird Adjustment'
                   AND t.flockid = v_flock AND t.batchid = v_batch AND t.effectivedate = v_today - 15
                   AND t.createddate = (v_today - 15)::timestamp) THEN RAISE EXCEPTION 'FAIL 1f: ledger row provenance'; END IF;
    RAISE NOTICE 'ok 1 historical mortality: live -180, dead birds +180, no fake production, dated and attributed';

    -- 2. Already disposed: generated and disposed, dead bird stock unchanged.
    v_dead0 := fnpoultry_byproductonhand(v_farm, 'DeadBirds');
    v_res := sppoultrymanualmovement_post(v_farm, v_birds, NULL, 'Decrease', 20, NULL, v_batch, v_flock, v_today,
        'Historical Mortality', 'Disposed', NULL, NULL, 'check373');
    IF fnpoultry_byproductonhand(v_farm, 'DeadBirds') <> v_dead0 THEN RAISE EXCEPTION 'FAIL 2a: dead birds moved'; END IF;
    IF (SELECT count(*) FROM poultrystocktransactions t WHERE t.manualmovementid = (v_res->>'movementId')::int
        AND t.txntype IN ('Hist Mortality In', 'Hist Mortality Disp')) <> 2 THEN RAISE EXCEPTION 'FAIL 2b: generated + disposed rows'; END IF;
    RAISE NOTICE 'ok 2 already disposed = generated and disposed';

    -- 3. A count correction is not mortality: no dead birds.
    v_dead0 := fnpoultry_byproductonhand(v_farm, 'DeadBirds');
    SELECT bp.currentlivebirds INTO v_live0 FROM fnflock_birdposition(v_farm, v_flock) bp;
    PERFORM sppoultrymanualmovement_post(v_farm, v_birds, NULL, 'Increase', 120, NULL, NULL, v_flock, v_today,
        'Stock Count Correction', NULL, NULL, NULL, 'check373');   -- batch derived from the flock
    PERFORM sppoultrymanualmovement_post(v_farm, v_birds, NULL, 'Decrease', 10, NULL, v_batch, v_flock, v_today,
        'Cull', NULL, NULL, NULL, 'check373');
    IF (SELECT bp.currentlivebirds FROM fnflock_birdposition(v_farm, v_flock) bp) <> v_live0 + 110 THEN RAISE EXCEPTION 'FAIL 3a: live birds'; END IF;
    IF fnpoultry_byproductonhand(v_farm, 'DeadBirds') <> v_dead0 THEN RAISE EXCEPTION 'FAIL 3b: correction / cull made dead birds'; END IF;
    RAISE NOTICE 'ok 3 count correction +120 and cull -10 move live birds only';

    -- 4. Refusals.
    v_failed := FALSE;
    BEGIN PERFORM sppoultrymanualmovement_post(v_farm, v_birds, NULL, 'Decrease', 1, NULL, NULL, NULL, v_today, 'Cull', NULL, NULL, NULL, 'c');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4a: birds without a flock'; END IF;
    IF v_other IS NOT NULL THEN
        v_failed := FALSE;
        BEGIN PERFORM sppoultrymanualmovement_post(v_farm, v_egg, NULL, 'Increase', 1, NULL, v_other, v_flock, v_today, 'Opening Inventory', NULL, NULL, NULL, 'c');
        EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
        IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4b: flock of another batch accepted'; END IF;
    END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrymanualmovement_post(v_farm, v_egg, NULL, 'Increase', 1, NULL, NULL, NULL, v_today + 2, 'Opening Inventory', NULL, NULL, NULL, 'c');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4c: future date accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrymanualmovement_post(v_farm, v_egg, NULL, 'Increase', 1, NULL, NULL, NULL, v_today, '', NULL, NULL, NULL, 'c');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4d: no reason accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrymanualmovement_post(v_farm, v_egg, NULL, 'Increase', 1, NULL, NULL, NULL, v_today, 'Other', NULL, NULL, NULL, 'c');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4e: Other without a note accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrymanualmovement_post(v_farm, v_egg, NULL, 'Decrease', 1, NULL, NULL, NULL, v_today, 'Historical Mortality', NULL, NULL, NULL, 'c');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4f: eggs as mortality accepted'; END IF;
    RAISE NOTICE 'ok 4 flock required for birds; batch/flock, date, reason all validated';

    -- 5. Eggs: opening inventory with provenance, back-dated; no production / sale made.
    SELECT COALESCE(sum(quantity), 0) INTO v_egg0 FROM poultrystocktransactions WHERE farmid = v_farm AND poultryproductid = v_egg;
    SELECT count(*) INTO v_nrec FROM productionrecords WHERE farmid = v_farm;
    v_res := sppoultrymanualmovement_post(v_farm, v_egg, NULL, 'Increase', 300, 2.5, v_batch, v_flock, v_today - 3,
        'Opening Inventory', NULL, NULL, NULL, 'check373');
    IF NOT EXISTS (SELECT 1 FROM sppoultrystock_gettransactions(v_farm, v_egg) g
                   WHERE g.manualmovementid = (v_res->>'movementId')::int AND g.quantity = 300 AND g.flockid = v_flock
                     AND g.batchcode IS NOT NULL AND g.reason = 'Opening Inventory' AND g.effectivedate = v_today - 3) THEN
        RAISE EXCEPTION 'FAIL 5a: egg row provenance'; END IF;
    IF (v_res->>'itemAfter')::numeric <> v_egg0 + 300 THEN RAISE EXCEPTION 'FAIL 5b: after %', v_res->>'itemAfter'; END IF;
    IF (SELECT count(*) FROM productionrecords WHERE farmid = v_farm) <> v_nrec THEN RAISE EXCEPTION 'FAIL 5c: production created'; END IF;
    RAISE NOTICE 'ok 5 egg opening inventory +300 with batch / flock / date / reason';

    -- 6. Unrecorded breakage converts eggs into Broken Eggs.
    v_brk0 := fnpoultry_byproductonhand(v_farm, 'BrokenEggs');
    SELECT COALESCE(sum(quantity), 0) INTO v_egg0 FROM poultrystocktransactions WHERE farmid = v_farm AND poultryproductid = v_egg;
    v_res := sppoultrymanualmovement_post(v_farm, v_egg, NULL, 'Decrease', 20, NULL, NULL, NULL, v_today,
        'Unrecorded Breakage', NULL, NULL, NULL, 'check373');
    v_id2 := (v_res->>'movementId')::int;
    IF fnpoultry_byproductonhand(v_farm, 'BrokenEggs') <> v_brk0 + 20 THEN RAISE EXCEPTION 'FAIL 6a: broken eggs'; END IF;
    IF (SELECT sum(quantity) FROM poultrystocktransactions WHERE farmid = v_farm AND poultryproductid = v_egg) <> v_egg0 - 20 THEN
        RAISE EXCEPTION 'FAIL 6b: eggs'; END IF;
    RAISE NOTICE 'ok 6 unrecorded breakage: eggs -20, Broken Eggs +20';

    -- 7. Disposal of byproducts: never below zero; live birds untouched.
    SELECT bp.currentlivebirds INTO v_live0 FROM fnflock_birdposition(v_farm, v_flock) bp;
    v_dead0 := fnpoultry_byproductonhand(v_farm, 'DeadBirds');
    PERFORM sppoultrymanualmovement_post(v_farm, fnpoultry_byproduct(v_farm, 'DeadBirds'), NULL, 'Decrease', 5, NULL, v_batch, v_flock,
        v_today, 'Disposal', NULL, NULL, NULL, 'check373');
    IF fnpoultry_byproductonhand(v_farm, 'DeadBirds') <> v_dead0 - 5 THEN RAISE EXCEPTION 'FAIL 7a: disposal'; END IF;
    IF (SELECT bp.currentlivebirds FROM fnflock_birdposition(v_farm, v_flock) bp) <> v_live0 THEN RAISE EXCEPTION 'FAIL 7b: live birds moved'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrymanualmovement_post(v_farm, fnpoultry_byproduct(v_farm, 'BrokenEggs'), NULL, 'Decrease',
        fnpoultry_byproductonhand(v_farm, 'BrokenEggs') + 1, NULL, NULL, NULL, v_today, 'Disposal', NULL, NULL, NULL, 'c');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7c: broken eggs below zero'; END IF;
    RAISE NOTICE 'ok 7 dead bird disposal -5 leaves live birds alone; no byproduct below zero';

    -- 8. Reversal: append-only, restores both sides; refused twice; refused once used.
    v_brk0 := fnpoultry_byproductonhand(v_farm, 'BrokenEggs');
    PERFORM sppoultrymanualmovement_reverse(v_farm, v_id2, 'entered twice', 'check373');
    IF fnpoultry_byproductonhand(v_farm, 'BrokenEggs') <> v_brk0 - 20 THEN RAISE EXCEPTION 'FAIL 8a: broken eggs back'; END IF;
    IF (SELECT count(*) FROM poultrystocktransactions WHERE manualmovementid = v_id2) <> 4 THEN RAISE EXCEPTION 'FAIL 8b: originals kept + reversals'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrymanualmovement_reverse(v_farm, v_id2, 'again', 'c');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 8c: reversed twice'; END IF;

    SELECT bp.currentlivebirds INTO v_live0 FROM fnflock_birdposition(v_farm, v_flock) bp;
    v_dead0 := fnpoultry_byproductonhand(v_farm, 'DeadBirds');
    -- Use most of the dead birds, so the mortality cannot be reversed.
    PERFORM sppoultrymanualmovement_post(v_farm, fnpoultry_byproduct(v_farm, 'DeadBirds'), NULL, 'Decrease', v_dead0 - 10, NULL, NULL, NULL,
        v_today, 'Disposal', NULL, NULL, NULL, 'check373');
    v_failed := FALSE;
    BEGIN PERFORM sppoultrymanualmovement_reverse(v_farm, v_id, 'wrong', 'check373');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 8d: reversal of used dead birds accepted'; END IF;
    PERFORM sppoultrymanualmovement_post(v_farm, fnpoultry_byproduct(v_farm, 'DeadBirds'), NULL, 'Increase', 500, NULL, NULL, NULL,
        v_today, 'Stock Count Correction', NULL, NULL, NULL, 'check373');
    v_dead0 := fnpoultry_byproductonhand(v_farm, 'DeadBirds');
    PERFORM sppoultrymanualmovement_reverse(v_farm, v_id, 'wrong', 'check373');
    IF (SELECT bp.currentlivebirds FROM fnflock_birdposition(v_farm, v_flock) bp) <> v_live0 + 180 THEN RAISE EXCEPTION 'FAIL 8e: live birds back'; END IF;
    IF fnpoultry_byproductonhand(v_farm, 'DeadBirds') <> v_dead0 - 180 THEN RAISE EXCEPTION 'FAIL 8f: dead birds back'; END IF;
    IF (SELECT status FROM poultrymanualstockmovements WHERE movementid = v_id) <> 'Reversed' THEN RAISE EXCEPTION 'FAIL 8g: status'; END IF;
    RAISE NOTICE 'ok 8 reversal appends the opposite, both sides, once, and not over used stock';

    -- 9. A repeated request posts once.
    v_res := sppoultrymanualmovement_post(v_farm, v_egg, NULL, 'Increase', 7, NULL, NULL, NULL, v_today, 'Stock Count Correction', NULL, NULL, 'rk-373', 'check373');
    v_res := sppoultrymanualmovement_post(v_farm, v_egg, NULL, 'Increase', 7, NULL, NULL, NULL, v_today, 'Stock Count Correction', NULL, NULL, 'rk-373', 'check373');
    IF NOT (v_res->>'repeated')::boolean OR (SELECT count(*) FROM poultrymanualstockmovements WHERE farmid = v_farm AND requestkey = 'rk-373') <> 1 THEN
        RAISE EXCEPTION 'FAIL 9: posted twice'; END IF;
    RAISE NOTICE 'ok 9 a repeated request posts once';

    -- 10. Raw materials: dated adjustment with reason; reversal; no overdraw.
    INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, usagemethod)
    VALUES (v_farm, 'Check 373 Feed', 'Feed', 'kg', 0, 'FIFO') RETURNING poultryrawmaterialitemid INTO v_item;
    v_res := sppoultrymanualmovement_post(v_farm, NULL, v_item, 'Increase', 50, 3, v_batch, v_flock, v_today - 5,
        'Opening Inventory', NULL, NULL, NULL, 'check373');
    IF (SELECT currentquantity FROM poultryrawmaterialitems WHERE poultryrawmaterialitemid = v_item) <> 50 THEN RAISE EXCEPTION 'FAIL 10a: stock'; END IF;
    IF NOT EXISTS (SELECT 1 FROM poultryrawmaterialadjustments a WHERE a.poultryrawmaterialitemid = v_item
                   AND a.adjusteddate = (v_today - 5)::timestamp AND a.reason = 'Opening Inventory') THEN RAISE EXCEPTION 'FAIL 10b: date / reason'; END IF;
    IF (SELECT flockid FROM poultrymanualstockmovements WHERE movementid = (v_res->>'movementId')::int) IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL 10c: raw material attributed to a flock'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrymanualmovement_post(v_farm, NULL, v_item, 'Decrease', 60, NULL, NULL, NULL, v_today, 'Loss', NULL, NULL, NULL, 'c');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 10d: overdraw accepted'; END IF;
    PERFORM sppoultrymanualmovement_reverse(v_farm, (v_res->>'movementId')::int, 'wrong item', 'check373');
    IF (SELECT currentquantity FROM poultryrawmaterialitems WHERE poultryrawmaterialitemid = v_item) <> 0 THEN RAISE EXCEPTION 'FAIL 10e: reversal'; END IF;
    RAISE NOTICE 'ok 10 raw materials: dated, reasoned, no flock, reversible';

    -- 11. Preview and list.
    v_res := sppoultrymanualmovement_preview(v_farm, v_birds, NULL, v_batch, v_flock);
    IF NOT (v_res->>'isBirds')::boolean OR (v_res->>'flockLiveBirds')::int <> (SELECT bp.currentlivebirds FROM fnflock_birdposition(v_farm, v_flock) bp) THEN
        RAISE EXCEPTION 'FAIL 11a: preview %', v_res; END IF;
    v_res := sppoultrymanualmovement_preview(v_farm, NULL, v_item, NULL, NULL);
    IF (v_res->>'itemOnHand')::numeric <> 0 THEN RAISE EXCEPTION 'FAIL 11b: raw preview'; END IF;
    IF (SELECT count(*) FROM sppoultrymanualmovement_list(v_farm) l WHERE l.createdby = 'check373') < 10 THEN RAISE EXCEPTION 'FAIL 11c: list'; END IF;
    RAISE NOTICE 'ok 11 preview and list';

    RAISE NOTICE 'manual stock movements: all checks passed';
END $$;

ROLLBACK;
