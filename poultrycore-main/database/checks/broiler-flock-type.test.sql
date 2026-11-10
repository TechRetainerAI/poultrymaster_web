-- =============================================================================
-- broiler-flock-type.test.sql -- checks for migration 399 (Layer / Broiler flocks).
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Fixtures live on
-- random farm ids, never on a real company.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_a      text := 'brtest-' || md5(random()::text);
    v_b      text := 'brtest-' || md5(random()::text);
    v_batch  integer;
    v_f1     integer;
    v_f2     integer;
    v_f3     integer;
    v_f4     integer;
    v_t      text;
    v_n      bigint;
    v_failed boolean;
BEGIN
    -- 0. Every flock has a type, and only the two allowed ones.
    SELECT count(*) INTO v_n FROM flock WHERE flocktype IS NULL OR flocktype NOT IN ('Layer', 'Broiler');
    IF v_n > 0 THEN RAISE EXCEPTION 'FAIL 0: % flock(s) without a valid type', v_n; END IF;
    RAISE NOTICE 'ok 0 every flock is a Layer or a Broiler flock';

    -- 1. Default rule.
    IF fnpoultry_defaultflocktype(v_a, 'Isa Brown') <> 'Layer'     THEN RAISE EXCEPTION 'FAIL 1a'; END IF;
    IF fnpoultry_defaultflocktype(v_a, 'Cobb 500') <> 'Broiler'    THEN RAISE EXCEPTION 'FAIL 1b'; END IF;
    IF fnpoultry_defaultflocktype(v_a, 'ROSS 308') <> 'Broiler'    THEN RAISE EXCEPTION 'FAIL 1c'; END IF;
    IF fnpoultry_defaultflocktype(v_a, 'Broiller') <> 'Broiler'    THEN RAISE EXCEPTION 'FAIL 1d: misspelt broiler'; END IF;
    IF fnpoultry_defaultflocktype(v_a, NULL) <> 'Layer'            THEN RAISE EXCEPTION 'FAIL 1e'; END IF;
    INSERT INTO poultrycompanyprofiles (farmid, businesstype) VALUES (v_b, 'Broilers');
    IF fnpoultry_defaultflocktype(v_b, 'Local / Indigenous') <> 'Broiler' THEN RAISE EXCEPTION 'FAIL 1f: broiler company'; END IF;
    RAISE NOTICE 'ok 1 default: broiler breed, else broiler company, else layer';

    -- 2. Insert fills the type when the writer sends none; a sent type wins.
    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate)
    VALUES ('u', v_a, 'BR-1', 'Batch', 'Mixed', 1000, current_date)
    RETURNING batchid INTO v_batch;

    INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, batchid)
    VALUES ('u', v_a, 'L1', current_date, 'Isa Brown', 100, v_batch) RETURNING flockid INTO v_f1;
    INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, batchid)
    VALUES ('u', v_a, 'B1', current_date, 'Cobb 500', 100, v_batch) RETURNING flockid INTO v_f2;
    INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, batchid, flocktype)
    VALUES ('u', v_a, 'L2', current_date, 'Cobb 500', 100, v_batch, 'Layer') RETURNING flockid INTO v_f3;
    INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, batchid)
    VALUES ('u', v_b, 'B2', current_date, 'Local', 100, v_batch) RETURNING flockid INTO v_f4;

    IF (SELECT flocktype FROM flock WHERE flockid = v_f1) <> 'Layer'   THEN RAISE EXCEPTION 'FAIL 2a'; END IF;
    IF (SELECT flocktype FROM flock WHERE flockid = v_f2) <> 'Broiler' THEN RAISE EXCEPTION 'FAIL 2b'; END IF;
    IF (SELECT flocktype FROM flock WHERE flockid = v_f3) <> 'Layer'   THEN RAISE EXCEPTION 'FAIL 2c: sent type overridden'; END IF;
    IF (SELECT flocktype FROM flock WHERE flockid = v_f4) <> 'Broiler' THEN RAISE EXCEPTION 'FAIL 2d'; END IF;
    RAISE NOTICE 'ok 2 insert default + explicit type';

    -- 3. Readers return it.
    SELECT g.flocktype INTO v_t FROM spflock_getbyid(v_f2, v_a) g;
    IF v_t IS DISTINCT FROM 'Broiler' THEN RAISE EXCEPTION 'FAIL 3a: getbyid %', v_t; END IF;
    SELECT count(*) INTO v_n FROM spflock_getall(v_a) g WHERE g.flocktype = 'Layer';
    IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL 3b: getall layers %', v_n; END IF;
    RAISE NOTICE 'ok 3 readers return flocktype';

    -- 4. spflock_settype.
    PERFORM spflock_settype(v_f1, v_a, 'Broiler', 'u');
    IF (SELECT flocktype FROM flock WHERE flockid = v_f1) <> 'Broiler' THEN RAISE EXCEPTION 'FAIL 4a'; END IF;

    v_failed := false;
    BEGIN PERFORM spflock_settype(v_f1, v_a, 'Duck', 'u'); EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4b: bad type accepted'; END IF;

    v_failed := false;
    BEGIN PERFORM spflock_settype(v_f1, v_b, 'Layer', 'u'); EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4c: another company changed the flock'; END IF;

    v_failed := false;
    BEGIN UPDATE flock SET flocktype = 'Turkey' WHERE flockid = v_f1; EXCEPTION WHEN check_violation THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4d: check constraint missing'; END IF;
    RAISE NOTICE 'ok 4 settype changes, validates, stays in its company';

    -- 5. A closed flock keeps its type.
    PERFORM set_config('app.flock_closeout', 'on', true);
    UPDATE flock SET closeddate = current_date, active = false WHERE flockid = v_f2;
    PERFORM set_config('app.flock_closeout', 'off', true);
    v_failed := false;
    BEGIN PERFORM spflock_settype(v_f2, v_a, 'Layer', 'u'); EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5: closed flock retyped'; END IF;
    PERFORM spflock_settype(v_f2, v_a, 'Broiler', 'u');   -- same type: a no-op, not an error
    RAISE NOTICE 'ok 5 closed flock refused';

    -- 6. Bird sale rule.
    IF NOT fnpoultrysale_isbirdsale('Broilers')          THEN RAISE EXCEPTION 'FAIL 6a'; END IF;
    IF NOT fnpoultrysale_isbirdsale('Live broilers')     THEN RAISE EXCEPTION 'FAIL 6b'; END IF;
    IF NOT fnpoultrysale_isbirdsale('Birds')             THEN RAISE EXCEPTION 'FAIL 6c'; END IF;
    IF NOT fnpoultrysale_isbirdsale('Chicken')           THEN RAISE EXCEPTION 'FAIL 6d'; END IF;
    IF fnpoultrysale_isbirdsale('Broiler feed')          THEN RAISE EXCEPTION 'FAIL 6e'; END IF;
    IF fnpoultrysale_isbirdsale('Broiler starter mash')  THEN RAISE EXCEPTION 'FAIL 6f'; END IF;
    IF fnpoultrysale_isbirdsale('Dead Birds')            THEN RAISE EXCEPTION 'FAIL 6g'; END IF;
    IF fnpoultrysale_isbirdsale('Fresh Eggs')            THEN RAISE EXCEPTION 'FAIL 6h'; END IF;
    RAISE NOTICE 'ok 6 bird sale rule';

    RAISE NOTICE 'broiler flock type: all checks passed';
END
$$;

ROLLBACK;
