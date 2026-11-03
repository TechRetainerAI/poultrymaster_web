-- =============================================================================
-- flock-weigh-ins.test.sql -- checks for migration 400 (weigh-ins).
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Fixtures live on
-- random farm ids. The stats cases are the ones in
-- lib/poultry/weigh-in-stats.test.ts, so the two cannot drift apart.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_a      text := 'wtest-' || md5(random()::text);
    v_b      text := 'wtest-' || md5(random()::text);
    v_today  date;
    v_batch  integer;
    v_f      integer;
    v_f2     integer;
    v_w1     integer;
    v_w2     integer;
    v_r      record;
    v_n      bigint;
    v_failed boolean;
BEGIN
    v_today := fncompany_businessdate(v_a);

    -- 1. Stats.
    SELECT * INTO v_r FROM fnpoultryweighin_stats(ARRAY[1800, 1900, 2000, 2100, 2200]::numeric[]);
    IF v_r.samplesize <> 5 OR v_r.avgweightg <> 2000 OR v_r.uniformitypct <> 100 OR v_r.cvpct <> 7.91
       OR v_r.minweightg <> 1800 OR v_r.maxweightg <> 2200 THEN
        RAISE EXCEPTION 'FAIL 1a: %', v_r;
    END IF;
    SELECT * INTO v_r FROM fnpoultryweighin_stats(ARRAY[1000, 2000, 2000, 2000, 3000]::numeric[]);
    IF v_r.uniformitypct <> 60 OR v_r.cvpct <> 35.36 THEN RAISE EXCEPTION 'FAIL 1b: %', v_r; END IF;
    SELECT * INTO v_r FROM fnpoultryweighin_stats(ARRAY[1500]::numeric[]);
    IF v_r.uniformitypct <> 100 OR v_r.cvpct IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1c: %', v_r; END IF;
    SELECT * INTO v_r FROM fnpoultryweighin_stats(ARRAY[2000, 1800, 2200]::numeric[]);   -- 1800/2200 exactly at +/-10%
    IF v_r.uniformitypct <> 100 THEN RAISE EXCEPTION 'FAIL 1d: edges are inside: %', v_r; END IF;
    RAISE NOTICE 'ok 1 stats';

    -- Fixtures: a broiler flock that started 20 days ago.
    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate)
    VALUES ('u', v_a, 'W-1', 'Batch', 'Cobb 500', 1000, v_today - 20) RETURNING batchid INTO v_batch;
    INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, batchid)
    VALUES ('u', v_a, 'Broilers A', v_today - 20, 'Cobb 500', 500, v_batch) RETURNING flockid INTO v_f;
    INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, batchid)
    VALUES ('u', v_a, 'Broilers B', v_today - 20, 'Cobb 500', 500, v_batch) RETURNING flockid INTO v_f2;

    -- 2. Summary entry, age from the start date.
    v_w1 := sppoultryweighin_save(v_a, v_f, v_today - 13, p_samplesize => 50, p_avgweightg => 180, p_by => 'u');
    SELECT * INTO v_r FROM poultryflockweighins WHERE weighinid = v_w1;
    IF v_r.ageindays <> 7 OR v_r.samplesize <> 50 OR v_r.avgweightg <> 180 OR v_r.weightsg IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL 2: %', v_r;
    END IF;
    RAISE NOTICE 'ok 2 summary weigh-in, age 7';

    -- 3. Individual weights: the server derives everything, ignoring summary inputs.
    v_w2 := sppoultryweighin_save(v_a, v_f, v_today - 6, p_samplesize => 999, p_avgweightg => 1,
                                  p_weightsg => ARRAY[400, 450, 500]::numeric[], p_by => 'u');
    SELECT * INTO v_r FROM poultryflockweighins WHERE weighinid = v_w2;
    IF v_r.samplesize <> 3 OR v_r.avgweightg <> 450 OR v_r.ageindays <> 14 THEN RAISE EXCEPTION 'FAIL 3: %', v_r; END IF;
    RAISE NOTICE 'ok 3 individual weights win';

    -- 4. List: daily gain since the previous weigh-in.
    SELECT * INTO v_r FROM sppoultryweighin_list(v_a, v_f) l WHERE l.weighinid = v_w2;
    IF v_r.prevavgweightg <> 180 OR v_r.dayssinceprev <> 7 OR v_r.dailygaing <> 38.6 OR v_r.flocktype <> 'Broiler' THEN
        RAISE EXCEPTION 'FAIL 4: %', v_r;
    END IF;
    SELECT count(*) INTO v_n FROM sppoultryweighin_list(v_a);
    IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL 4b: % rows', v_n; END IF;
    RAISE NOTICE 'ok 4 list + daily gain';

    -- 5. Refusals.
    v_failed := false;
    BEGIN PERFORM sppoultryweighin_save(v_a, v_f, v_today - 13, p_samplesize => 10, p_avgweightg => 190);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5a: second weigh-in on a day'; END IF;

    v_failed := false;
    BEGIN PERFORM sppoultryweighin_save(v_a, v_f, v_today - 25, p_samplesize => 10, p_avgweightg => 50);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5b: before the flock started'; END IF;

    v_failed := false;
    BEGIN PERFORM sppoultryweighin_save(v_a, v_f, v_today + 1, p_samplesize => 10, p_avgweightg => 50);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5c: future date'; END IF;

    v_failed := false;
    BEGIN PERFORM sppoultryweighin_save(v_a, v_f, v_today, p_samplesize => 10);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5d: no average'; END IF;

    v_failed := false;
    BEGIN PERFORM sppoultryweighin_save(v_a, v_f, v_today, p_weightsg => ARRAY[500, -3]::numeric[]);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5e: negative bird'; END IF;

    v_failed := false;
    BEGIN PERFORM sppoultryweighin_save(v_a, v_f, v_today, p_samplesize => 10, p_avgweightg => 500,
                                        p_minweightg => 600, p_maxweightg => 700);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5f: average outside min/max'; END IF;

    v_failed := false;
    BEGIN PERFORM sppoultryweighin_save(v_b, v_f, v_today, p_samplesize => 10, p_avgweightg => 500);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5g: another company weighed the flock'; END IF;

    v_failed := false;
    BEGIN PERFORM sppoultryweighin_delete(v_w1, v_b);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5h: another company deleted it'; END IF;
    RAISE NOTICE 'ok 5 refusals';

    -- 6. Edit: move the date, recompute age; colliding date refused.
    PERFORM sppoultryweighin_save(v_a, v_f, v_today - 12, p_samplesize => 50, p_avgweightg => 200,
                                  p_by => 'u2', p_weighinid => v_w1);
    SELECT * INTO v_r FROM poultryflockweighins WHERE weighinid = v_w1;
    IF v_r.ageindays <> 8 OR v_r.avgweightg <> 200 OR v_r.updatedby <> 'u2' THEN RAISE EXCEPTION 'FAIL 6a: %', v_r; END IF;
    v_failed := false;
    BEGIN PERFORM sppoultryweighin_save(v_a, v_f, v_today - 6, p_samplesize => 5, p_avgweightg => 300, p_weighinid => v_w1);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6b: edit onto an occupied day'; END IF;
    RAISE NOTICE 'ok 6 edit';

    -- 7. Delete frees the day; the row stays with who/why.
    PERFORM sppoultryweighin_delete(v_w1, v_a, 'u3', 'Wrong flock');
    SELECT * INTO v_r FROM poultryflockweighins WHERE weighinid = v_w1;
    IF v_r.deletedat IS NULL OR v_r.deletedby <> 'u3' OR v_r.deletereason <> 'Wrong flock' THEN RAISE EXCEPTION 'FAIL 7a'; END IF;
    PERFORM sppoultryweighin_save(v_a, v_f, v_today - 12, p_samplesize => 40, p_avgweightg => 210);
    SELECT count(*) INTO v_n FROM sppoultryweighin_list(v_a, v_f);
    IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL 7b: % rows', v_n; END IF;
    RAISE NOTICE 'ok 7 soft delete';

    -- 8. A closed flock is frozen.
    PERFORM set_config('app.flock_closeout', 'on', true);
    UPDATE flock SET closeddate = v_today, active = false WHERE flockid = v_f;
    PERFORM set_config('app.flock_closeout', 'off', true);
    v_failed := false;
    BEGIN PERFORM sppoultryweighin_save(v_a, v_f, v_today, p_samplesize => 10, p_avgweightg => 2000);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 8a: weighed a closed flock'; END IF;
    v_failed := false;
    BEGIN PERFORM sppoultryweighin_delete(v_w2, v_a);
    EXCEPTION WHEN OTHERS THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 8b: deleted from a closed flock'; END IF;
    RAISE NOTICE 'ok 8 closed flock frozen';

    RAISE NOTICE 'flock weigh-ins: all checks passed';
END
$$;

ROLLBACK;
