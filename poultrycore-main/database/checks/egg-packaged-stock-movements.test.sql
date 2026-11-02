-- =============================================================================
-- egg-packaged-stock-movements.test.sql -- checks for migration 395 (stock
-- movements entered in Boxes, Crates and Pieces). Spec tests 24, 25 and the
-- refusals.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f).
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm   text;
    v_user   text;
    v_egg    integer;
    v_broken integer;
    v_today  date;
    v_res    jsonb;
    v_id     integer;
    v_m      record;
    v_on0    numeric;
    v_on1    numeric;
    v_failed boolean;
    v_n      bigint;

    c_onhand CONSTANT text := 'SELECT COALESCE(sum(t.quantity), 0) FROM poultrystocktransactions t WHERE t.farmid = $1 AND t.poultryproductid = $2';
BEGIN
    -- 0. A movement's packaging is only ever whole and matches its eggs.
    IF EXISTS (SELECT 1 FROM poultrymanualstockmovements
               WHERE (qtycrates IS NULL) <> (eggspercrate IS NULL)
                  OR (qtycrates IS NOT NULL AND quantity <> fnpoultry_eggpieces(qtyboxes, qtycrates, qtypieces, eggspercrate, cratesperbox))) THEN
        RAISE EXCEPTION 'FAIL 0: a movement has a partial or wrong packaging snapshot'; END IF;
    RAISE NOTICE 'ok 0 every movement packaging is whole and matches its eggs';

    SELECT pp.farmid, pp.poultryproductid INTO v_farm, v_egg
    FROM   poultryproducts pp
    WHERE  pp.israweggproduct = TRUE AND pp.poultryproductid = fnpoultry_unsortedeggproduct(pp.farmid)
    ORDER  BY pp.farmid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'egg packaged stock movements: all checks passed (no company with an egg product)';
        RETURN;
    END IF;
    SELECT fa.owneruserid INTO v_user FROM farms fa WHERE fa.id::text = v_farm OR fa.farmid::text = v_farm LIMIT 1;
    v_user  := COALESCE(v_user, 'check395');
    v_today := fncompany_businessdate(v_farm);
    INSERT INTO poultryeggsortingsettings (farmid, eggspercrate) VALUES (v_farm, 30)
    ON CONFLICT (farmid) DO UPDATE SET eggspercrate = 30;
    PERFORM sppoultryeggpackaging_save(v_farm, TRUE, 14, 'BoxesCratesPieces', 'Boxes', 'check395');
    -- Enough eggs that no step below runs into "not enough stock" (dev data
    -- can sit below zero).
    EXECUTE c_onhand INTO v_on0 USING v_farm, v_egg;
    PERFORM sppoultrymanualmovement_post(v_farm, v_egg, NULL, 'Increase', 10000 + GREATEST(-v_on0, 0), NULL, NULL, NULL,
        v_today, 'Opening Inventory', NULL, 'check395', 'check-395-open', v_user);

    -- 24. Increase 1 box + 2 crates + 5 pcs = +485 eggs, one movement.
    EXECUTE c_onhand INTO v_on0 USING v_farm, v_egg;
    SELECT count(*) INTO v_n FROM poultrymanualstockmovements WHERE farmid = v_farm;
    v_res := sppoultrymanualmovement_postpackaged(v_farm, v_egg, 'Increase', 1, 2, 5, NULL, NULL, NULL, v_today,
        'Opening Inventory', 'check395', 'check-395-a', v_user);
    EXECUTE c_onhand INTO v_on1 USING v_farm, v_egg;
    IF v_on1 - v_on0 <> 485 OR (v_res->>'eggs')::int <> 485 THEN RAISE EXCEPTION 'FAIL 24: +% (want 485)', v_on1 - v_on0; END IF;
    IF (SELECT count(*) FROM poultrymanualstockmovements WHERE farmid = v_farm) <> v_n + 1 THEN RAISE EXCEPTION 'FAIL 24: not one movement'; END IF;
    SELECT * INTO v_m FROM poultrymanualstockmovements WHERE farmid = v_farm AND requestkey = 'check-395-a';
    v_id := v_m.movementid;
    IF (v_m.qtyboxes, v_m.qtycrates, v_m.qtypieces, v_m.eggspercrate, v_m.cratesperbox) <> (1, 2, 5, 30, 14) OR v_m.quantity <> 485 THEN
        RAISE EXCEPTION 'FAIL 24: snapshot %', row_to_json(v_m); END IF;
    IF v_res->>'packaging' <> '1 box + 2 crates + 5 pcs' THEN RAISE EXCEPTION 'FAIL 24: text %', v_res->>'packaging'; END IF;
    RAISE NOTICE 'ok 24 1 box + 2 crates + 5 pcs = +485 eggs, one movement, entry kept';

    -- Same key again: the same movement, no second +485.
    v_res := sppoultrymanualmovement_postpackaged(v_farm, v_egg, 'Increase', 1, 2, 5, NULL, NULL, NULL, v_today,
        'Opening Inventory', 'check395', 'check-395-a', v_user);
    EXECUTE c_onhand INTO v_on0 USING v_farm, v_egg;
    IF v_on0 <> v_on1 OR NOT COALESCE((v_res->>'repeated')::boolean, FALSE) THEN RAISE EXCEPTION 'FAIL repeat: %', v_res; END IF;
    RAISE NOTICE 'ok double submit posts once';

    -- Decrease 2 boxes = -840.
    EXECUTE c_onhand INTO v_on0 USING v_farm, v_egg;
    PERFORM sppoultrymanualmovement_postpackaged(v_farm, v_egg, 'Decrease', 2, 0, 0, NULL, NULL, NULL, v_today,
        'Disposal', 'check395', 'check-395-b', v_user);
    EXECUTE c_onhand INTO v_on1 USING v_farm, v_egg;
    IF v_on0 - v_on1 <> 840 THEN RAISE EXCEPTION 'FAIL decrease: -% (want 840)', v_on0 - v_on1; END IF;
    RAISE NOTICE 'ok decrease 2 boxes = -840 eggs';

    -- 25. Box size changes, then the +485 is reversed: exactly 485 come off.
    PERFORM sppoultryeggpackaging_save(v_farm, TRUE, 10, 'BoxesCratesPieces', 'Boxes', 'check395');
    EXECUTE c_onhand INTO v_on0 USING v_farm, v_egg;
    PERFORM sppoultrymanualmovement_reverse(v_farm, v_id, 'check395', v_user);
    EXECUTE c_onhand INTO v_on1 USING v_farm, v_egg;
    IF v_on0 - v_on1 <> 485 THEN RAISE EXCEPTION 'FAIL 25: reversal took % (want 485)', v_on0 - v_on1; END IF;
    IF (SELECT cratesperbox FROM poultrymanualstockmovements WHERE movementid = v_id) <> 14 THEN
        RAISE EXCEPTION 'FAIL 25: the movement lost its conversion'; END IF;
    RAISE NOTICE 'ok 25 reversal after a box-size change removes exactly 485';

    -- Refusals: fractions, negatives, nothing, a non-egg item, boxes while off.
    v_failed := FALSE;
    BEGIN PERFORM sppoultrymanualmovement_postpackaged(v_farm, v_egg, 'Increase', 0, -1, 40, NULL, NULL, NULL, v_today, 'Opening Inventory', NULL, 'check-395-c', v_user);
    EXCEPTION WHEN OTHERS THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: negative crates accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrymanualmovement_postpackaged(v_farm, v_egg, 'Increase', 0, 0, 0, NULL, NULL, NULL, v_today, 'Opening Inventory', NULL, 'check-395-d', v_user);
    EXCEPTION WHEN OTHERS THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: an empty movement accepted'; END IF;
    PERFORM sppoultryproduct_ensurebyproducts(v_farm);
    v_broken := fnpoultry_byproduct(v_farm, 'BrokenEggs');
    IF v_broken IS NOT NULL THEN
        v_failed := FALSE;
        BEGIN PERFORM sppoultrymanualmovement_postpackaged(v_farm, v_broken, 'Increase', 0, 1, 0, NULL, NULL, NULL, v_today, 'Opening Inventory', NULL, 'check-395-e', v_user);
        EXCEPTION WHEN OTHERS THEN v_failed := TRUE; END;
        IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: Broken Eggs entered in crates'; END IF;
    END IF;
    PERFORM sppoultryeggpackaging_save(v_farm, FALSE, 10, 'CratesPieces', 'Crates', 'check395');
    v_failed := FALSE;
    BEGIN PERFORM sppoultrymanualmovement_postpackaged(v_farm, v_egg, 'Increase', 1, 0, 0, NULL, NULL, NULL, v_today, 'Opening Inventory', NULL, 'check-395-f', v_user);
    EXCEPTION WHEN OTHERS THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL: boxes accepted while off'; END IF;
    -- Crates still work with boxes off, and keep no box size.
    PERFORM sppoultrymanualmovement_postpackaged(v_farm, v_egg, 'Increase', 0, 3, 5, NULL, NULL, NULL, v_today, 'Opening Inventory', NULL, 'check-395-g', v_user);
    SELECT * INTO v_m FROM poultrymanualstockmovements WHERE farmid = v_farm AND requestkey = 'check-395-g';
    IF v_m.quantity <> 95 OR v_m.cratesperbox IS NOT NULL THEN RAISE EXCEPTION 'FAIL crates with boxes off: %', row_to_json(v_m); END IF;
    RAISE NOTICE 'ok refusals (negative, empty, Broken Eggs, boxes off); crates still post with boxes off';

    -- The list returns the packaging.
    IF NOT EXISTS (SELECT 1 FROM sppoultrymanualmovement_list(v_farm) l WHERE l.movementid = v_id AND l.qtyboxes = 1 AND l.cratesperbox = 14) THEN
        RAISE EXCEPTION 'FAIL list: packaging not returned'; END IF;
    RAISE NOTICE 'ok list carries the packaging';

    RAISE NOTICE 'egg packaged stock movements: all checks passed';
END;
$$;

ROLLBACK;
