-- =============================================================================
-- egg-packaging.test.sql -- checks for migration 393 (Boxes, Crates, Pieces).
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f).
-- The same cases as lib/poultry/egg-packaging.test.ts, so the database and the
-- web app cannot drift apart on the conversion.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_r       record;
    v_t       text;
    v_n       bigint;
    v_v1      integer;
    v_v2      integer;
    v_a       text := 'pkgtest-' || md5(random()::text);
    v_b       text := 'pkgtest-' || md5(random()::text);
    v_failed  boolean;
    v_stock0  numeric;
    v_sales0  numeric;
    v_audit0  bigint;
BEGIN
    -- 0. Existing farms: nothing switched on, display unchanged -- except a
    --    farm that has since changed its packaging itself (audited).
    SELECT count(*) INTO v_n FROM poultryeggsortingsettings s
    WHERE (s.enableboxes OR s.eggdisplay <> 'CratesPieces' OR s.saleentryunit <> 'Crates')
      AND NOT EXISTS (SELECT 1 FROM poultryeggsortingaudit a
                      WHERE a.farmid = s.farmid AND a.entity = 'Settings' AND a.details ? 'enableBoxes');
    IF v_n > 0 THEN RAISE EXCEPTION 'FAIL 0: % farm(s) have packaging nobody set', v_n; END IF;
    RAISE NOTICE 'ok 0 no farm has packaging it did not set';

    -- 1-2. Eggs per box.
    IF fnpoultry_eggpieces(1, 0, 0, 30, 14) <> 420 THEN RAISE EXCEPTION 'FAIL 1: 14 x 30'; END IF;
    IF fnpoultry_eggpieces(1, 0, 0, 30, 10) <> 300 THEN RAISE EXCEPTION 'FAIL 2: 10 x 30'; END IF;
    RAISE NOTICE 'ok 1-2 eggs per box';

    -- 3. Mixed entry.
    IF fnpoultry_eggpieces(2, 3, 10, 30, 14) <> 940 THEN RAISE EXCEPTION 'FAIL 3: 2b+3c+10p'; END IF;
    RAISE NOTICE 'ok 3 2 boxes + 3 crates + 10 pcs = 940';

    -- 4-7. Eggs -> packages.
    SELECT * INTO v_r FROM fnpoultry_eggbreakdown(10675, 30, 14);
    IF (v_r.boxes, v_r.crates, v_r.pieces) <> (25, 5, 25) THEN RAISE EXCEPTION 'FAIL 4: %', v_r; END IF;
    SELECT * INTO v_r FROM fnpoultry_eggbreakdown(840, 30, 14);
    IF (v_r.boxes, v_r.crates, v_r.pieces) <> (2, 0, 0) THEN RAISE EXCEPTION 'FAIL 5: %', v_r; END IF;
    SELECT * INTO v_r FROM fnpoultry_eggbreakdown(95, 30, 14);
    IF (v_r.boxes, v_r.crates, v_r.pieces) <> (0, 3, 5) THEN RAISE EXCEPTION 'FAIL 6: %', v_r; END IF;
    SELECT * INTO v_r FROM fnpoultry_eggbreakdown(0, 30, 14);
    IF (v_r.boxes, v_r.crates, v_r.pieces) <> (0, 0, 0) THEN RAISE EXCEPTION 'FAIL 7: %', v_r; END IF;
    -- No box size: no boxes, no division by zero.
    SELECT * INTO v_r FROM fnpoultry_eggbreakdown(1000, 30, NULL);
    IF (v_r.boxes, v_r.crates, v_r.pieces) <> (0, 33, 10) THEN RAISE EXCEPTION 'FAIL 7b: %', v_r; END IF;
    SELECT * INTO v_r FROM fnpoultry_eggbreakdown(-485, 30, 14);
    IF (v_r.boxes, v_r.crates, v_r.pieces) <> (-1, -2, -5) THEN RAISE EXCEPTION 'FAIL 7c: %', v_r; END IF;
    RAISE NOTICE 'ok 4-7 breakdown (incl. no box size and a decrease)';

    -- Refusals: negatives, boxes without a size.
    v_failed := FALSE;
    BEGIN PERFORM fnpoultry_eggpieces(0, -1, 0, 30, 14); EXCEPTION WHEN OTHERS THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7d: negative crates accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM fnpoultry_eggpieces(1, 0, 0, 30, NULL); EXCEPTION WHEN OTHERS THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7e: boxes without a box size accepted'; END IF;
    RAISE NOTICE 'ok 7d-e refusals';

    -- Text: same words as the web app.
    IF fnpoultry_eggqtytext(10675, 30, 14, 'BoxesCratesPieces') <> '25 boxes + 5 crates + 25 pcs' THEN
        RAISE EXCEPTION 'FAIL text 1: %', fnpoultry_eggqtytext(10675, 30, 14, 'BoxesCratesPieces'); END IF;
    IF fnpoultry_eggqtytext(10675, 30, 14, 'CratesPieces') <> '355 crates + 25 pcs' THEN RAISE EXCEPTION 'FAIL text 2'; END IF;
    IF fnpoultry_eggqtytext(10675, 30, 14, 'Pieces') <> '10,675 eggs' THEN RAISE EXCEPTION 'FAIL text 3'; END IF;
    IF fnpoultry_eggqtytext(10675, 30, NULL, 'BoxesCratesPieces') <> '355 crates + 25 pcs' THEN RAISE EXCEPTION 'FAIL text 4'; END IF;
    IF fnpoultry_eggqtytext(25, 30, 14, 'BoxesCratesPieces') <> '25 eggs' THEN RAISE EXCEPTION 'FAIL text 5'; END IF;
    IF fnpoultry_eggqtytext(420, 30, 14, 'BoxesCratesPieces') <> '1 box' THEN RAISE EXCEPTION 'FAIL text 6'; END IF;
    IF fnpoultry_eggqtytext(0, 30, 14, 'BoxesCratesPieces') <> '0 eggs' THEN RAISE EXCEPTION 'FAIL text 7'; END IF;
    RAISE NOTICE 'ok text matches the web app';

    -- 8. Bad configuration refused.
    v_failed := FALSE;
    BEGIN PERFORM sppoultryeggpackaging_save(v_a, TRUE, 0, 'BoxesCratesPieces', 'Boxes', 'pkgtest'); EXCEPTION WHEN OTHERS THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 8: crates per box 0 accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultryeggpackaging_save(v_a, TRUE, NULL, 'CratesPieces', 'Crates', 'pkgtest'); EXCEPTION WHEN OTHERS THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 8b: boxes on without a size accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultryeggpackaging_save(v_a, FALSE, 14, 'BoxesCratesPieces', 'Crates', 'pkgtest'); EXCEPTION WHEN OTHERS THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 8c: box display with boxes off accepted'; END IF;
    RAISE NOTICE 'ok 8 bad configuration refused';

    -- 35. Two companies, two box sizes, no leakage.
    PERFORM sppoultryeggpackaging_save(v_a, TRUE, 14, 'BoxesCratesPieces', 'Boxes', 'pkgtest');
    PERFORM sppoultryeggpackaging_save(v_b, TRUE, 10, 'BoxesCratesPieces', 'Crates', 'pkgtest');
    IF (SELECT eggsperbox FROM fnpoultry_eggpackaging(v_a)) <> 420 THEN RAISE EXCEPTION 'FAIL 35a'; END IF;
    IF (SELECT eggsperbox FROM fnpoultry_eggpackaging(v_b)) <> 300 THEN RAISE EXCEPTION 'FAIL 35b'; END IF;
    RAISE NOTICE 'ok 35 per-company box sizes';

    -- Unknown farm: defaults, boxes off.
    SELECT * INTO v_r FROM fnpoultry_eggpackaging('pkgtest-no-such-farm');
    IF v_r.enableboxes OR v_r.eggsperbox IS NOT NULL OR v_r.eggspercrate <> 30 OR v_r.eggdisplay <> 'CratesPieces' THEN
        RAISE EXCEPTION 'FAIL defaults: %', v_r; END IF;
    RAISE NOTICE 'ok defaults for a farm with no settings row';

    -- Versioning: the conversion changing bumps the version; display alone does not.
    SELECT packagingversion INTO v_v1 FROM fnpoultry_eggpackaging(v_a);
    PERFORM sppoultryeggpackaging_save(v_a, TRUE, 14, 'Pieces', 'Crates', 'pkgtest');
    IF (SELECT packagingversion FROM fnpoultry_eggpackaging(v_a)) <> v_v1 THEN RAISE EXCEPTION 'FAIL version: display bumped it'; END IF;
    PERFORM sppoultryeggpackaging_save(v_a, TRUE, 10, 'Pieces', 'Crates', 'pkgtest');
    SELECT packagingversion INTO v_v2 FROM fnpoultry_eggpackaging(v_a);
    IF v_v2 <> v_v1 + 1 THEN RAISE EXCEPTION 'FAIL version: box size change % -> %', v_v1, v_v2; END IF;
    UPDATE poultryeggsortingsettings SET eggspercrate = 24 WHERE farmid = v_a;
    IF (SELECT packagingversion FROM fnpoultry_eggpackaging(v_a)) <> v_v2 + 1 THEN RAISE EXCEPTION 'FAIL version: crate size change'; END IF;
    IF (SELECT eggsperbox FROM fnpoultry_eggpackaging(v_a)) <> 240 THEN RAISE EXCEPTION 'FAIL eggs per box follows crate size'; END IF;
    RAISE NOTICE 'ok versioning';

    -- Switching boxes off keeps the box size, and display falls back to crates.
    PERFORM sppoultryeggpackaging_save(v_b, FALSE, 10, 'CratesPieces', 'Crates', 'pkgtest');
    SELECT * INTO v_r FROM sppoultryeggpackaging_get(v_b);
    IF v_r.enableboxes OR v_r.eggsperbox IS NOT NULL OR v_r.storedcratesperbox <> 10 THEN RAISE EXCEPTION 'FAIL off: %', v_r; END IF;
    RAISE NOTICE 'ok boxes off keeps the size';

    -- Audit: every change is recorded with before/after.
    SELECT count(*) INTO v_n FROM poultryeggsortingaudit WHERE farmid = v_a AND entity = 'Settings';
    IF v_n < 4 THEN RAISE EXCEPTION 'FAIL audit: % rows', v_n; END IF;
    SELECT details->>'cratesPerBox' INTO v_t FROM poultryeggsortingaudit
    WHERE farmid = v_a AND entity = 'Settings' AND details->'before'->>'cratesPerBox' = '14' ORDER BY 1 LIMIT 1;
    IF v_t IS DISTINCT FROM '10' THEN RAISE EXCEPTION 'FAIL audit before/after: %', v_t; END IF;
    RAISE NOTICE 'ok audit';

    -- Rule 5/6: configuration never moves stock or money.
    SELECT COALESCE(sum(quantity), 0) INTO v_stock0 FROM poultrystocktransactions;
    SELECT COALESCE(sum(totalamount), 0) INTO v_sales0 FROM sale;
    PERFORM sppoultryeggpackaging_save(v_a, TRUE, 12, 'BoxesCratesPieces', 'Boxes', 'pkgtest');
    IF (SELECT COALESCE(sum(quantity), 0) FROM poultrystocktransactions) <> v_stock0
       OR (SELECT COALESCE(sum(totalamount), 0) FROM sale) <> v_sales0 THEN
        RAISE EXCEPTION 'FAIL: a packaging change moved stock or sales';
    END IF;
    RAISE NOTICE 'ok packaging changes move no stock and no money';

    RAISE NOTICE 'egg packaging: all checks passed';
END;
$$;

ROLLBACK;
