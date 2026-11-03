-- Behavioural checks for migration 387: repeating lifecycle milestones and the
-- Ghana national vaccination schedule plans.
--
-- SELF-CONTAINED: opens its own transaction and ROLLS IT BACK.
--
--   psql ... -X -f poultry-vaccination-schedule.test.sql
--
-- Every check prints "ok" or "FAIL"; the block RAISES at the end if any failed.
-- "Today" is moved with fnpoultrylifecycle_schedule's p_asof, so the file
-- passes on any day.
--
--   A  The national plans: seeded once, ages as on the poster, built-in flag
--   B  A day-old flock: one-off vaccinations and their statuses
--   C  Repeats: only up to the next one; an unacted repeat replaced by the next
--   D  Completing a repeat (by occurrence); 347's positional call still works
--   E  Birds bought older: earlier vaccinations are not this farm's tasks
--   F  Editing a built-in plan makes it the farm's own; repeat validation

BEGIN;

CREATE FUNCTION pg_temp.chk(p_label text, p_expect text, p_got text)
RETURNS integer LANGUAGE plpgsql AS $c$
BEGIN
    IF p_expect IS NOT DISTINCT FROM p_got THEN
        RAISE NOTICE 'ok    %  (%)', p_label, p_got;
        RETURN 0;
    END IF;
    RAISE NOTICE 'FAIL  %  expect % got %', p_label, COALESCE(p_expect, 'NULL'), COALESCE(p_got, 'NULL');
    RETURN 1;
END $c$;

-- "occurrence:status" of every row for one (flock, title), in order.
CREATE FUNCTION pg_temp.occ(p_farm text, p_flock integer, p_title text, p_asof date)
RETURNS text LANGUAGE sql AS $c$
    SELECT string_agg(s.occurrence || ':' || s.status, ',' ORDER BY s.occurrence)
    FROM   fnpoultrylifecycle_schedule(p_farm, p_asof) s
    WHERE  s.flockid = p_flock AND s.title = p_title;
$c$;

DO $t$
DECLARE
    v_farm   text := gen_random_uuid()::text;
    v_today  date;
    v_batch  integer;
    f_chick  integer;   -- day-old, 30 days ago
    f_old    integer;   -- day-old, 250 days ago
    f_pol    integer;   -- bought at 16 weeks, 10 days ago
    t_com    integer;
    t_brd    integer;
    v_mid    integer;
    v_txt    text;
    f        integer := 0;
BEGIN
    v_today := fncompany_businessdate(v_farm);

    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate, costperchick, totalcost)
    VALUES ('vac-test', v_farm, 'V1', 'Vaccination test', 'Isa Brown', 1000, v_today - 30, 2, 2000) RETURNING batchid INTO v_batch;
    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, hasarrived)
    VALUES ('vac-test', v_farm, 'Chicks', 'Isa Brown', v_today - 30, 500, TRUE, v_batch, TRUE) RETURNING flockid INTO f_chick;
    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, hasarrived)
    VALUES ('vac-test', v_farm, 'Layers', 'Isa Brown', v_today - 250, 500, TRUE, v_batch, TRUE) RETURNING flockid INTO f_old;
    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, hasarrived)
    VALUES ('vac-test', v_farm, 'Pullets', 'Isa Brown', v_today - 10, 300, TRUE, v_batch, TRUE) RETURNING flockid INTO f_pol;

    -- ============================================================ A. the plans
    f := f + pg_temp.chk('A1. two national plans created', '2',
            (SELECT planscreated::text FROM sppoultrylifecycle_ensuredefaults(v_farm, 'tester')));
    f := f + pg_temp.chk('A2. second call does nothing', 'true',
            (SELECT alreadyapplied::text FROM sppoultrylifecycle_ensuredefaults(v_farm, 'tester')));
    SELECT templateid INTO t_com FROM poultrylifecycletemplates WHERE farmid = v_farm AND defaultkey = 'vacc.gh.commercial';
    SELECT templateid INTO t_brd FROM poultrylifecycletemplates WHERE farmid = v_farm AND defaultkey = 'vacc.gh.breeder';
    f := f + pg_temp.chk('A3. commercial ages are the poster''s days', '7,14,21,28,35,53,70,84,112,203',
            (SELECT string_agg(agedays::text, ',' ORDER BY agedays) FROM sppoultrylifecyclemilestone_getall(v_farm, t_com)));
    f := f + pg_temp.chk('A4. breeder ages are the poster''s days', '1,7,14,21,28,35,53,70,84,112,294',
            (SELECT string_agg(agedays::text, ',' ORDER BY agedays) FROM sppoultrylifecyclemilestone_getall(v_farm, t_brd)));
    f := f + pg_temp.chk('A5. one repeat per plan, every 91 days', '203:91,294:91',
            (SELECT string_agg(m.agedays || ':' || m.repeateverydays, ',' ORDER BY m.agedays)
             FROM poultrylifecyclemilestones m WHERE m.farmid = v_farm AND m.repeateverydays IS NOT NULL));
    f := f + pg_temp.chk('A6. both flagged built-in', '2',
            (SELECT count(*)::text FROM sppoultrylifecycletemplate_getall(v_farm) WHERE isdefault));
    f := f + pg_temp.chk('A7. the plans tell the farm to confirm with its vet', '2',
            (SELECT count(*)::text FROM poultrylifecycletemplates WHERE farmid = v_farm AND description ILIKE '%confirm with your vet%'));
    f := f + pg_temp.chk('A8. nothing is assigned by seeding', '0',
            (SELECT count(*)::text FROM poultrylifecycleassignments WHERE farmid = v_farm));

    PERFORM sppoultrylifecycle_assign(v_farm, t_com, NULL, f_chick, 0, 'tester');
    PERFORM sppoultrylifecycle_assign(v_farm, t_com, NULL, f_old, 0, 'tester');
    PERFORM sppoultrylifecycle_assign(v_farm, t_com, NULL, f_pol, 112, 'tester');

    -- ======================================================= B. day-old flock
    -- Age 30 today: LaSota (day 28) passed, Gumboro Int/Plus (day 35) in 5 days.
    f := f + pg_temp.chk('B1. day-28 LaSota is overdue at age 30', '0:Overdue',
            (SELECT string_agg(s.occurrence || ':' || s.status, ',') FROM fnpoultrylifecycle_schedule(v_farm) s
             WHERE s.flockid = f_chick AND s.agedays = 28));
    f := f + pg_temp.chk('B2. day-35 Gumboro is still later (lead 3 days)', 'Scheduled',
            (SELECT s.status FROM fnpoultrylifecycle_schedule(v_farm) s WHERE s.flockid = f_chick AND s.agedays = 35));
    f := f + pg_temp.chk('B3. ... and upcoming 2 days later', 'Upcoming',
            (SELECT s.status FROM fnpoultrylifecycle_schedule(v_farm, v_today + 2) s WHERE s.flockid = f_chick AND s.agedays = 35));
    f := f + pg_temp.chk('B4. ... and due on day 35', 'Due',
            (SELECT s.status FROM fnpoultrylifecycle_schedule(v_farm, v_today + 5) s WHERE s.flockid = f_chick AND s.agedays = 35));
    f := f + pg_temp.chk('B5. the booster shows once, as later', '0:Scheduled',
            pg_temp.occ(v_farm, f_chick, 'Newcastle booster (LaSota / I-2 / inactivated)', v_today));

    -- ================================================================ C. repeats
    -- Age 250: booster 0 (day 203) overdue, booster 1 (day 294) later.
    f := f + pg_temp.chk('C1. age 250: first booster overdue, next one listed', '0:Overdue,1:Scheduled',
            pg_temp.occ(v_farm, f_old, 'Newcastle booster (LaSota / I-2 / inactivated)', v_today));
    -- Age 400: boosters at 203 and 294 were never done and newer ones are due,
    -- so only the latest past one (385) and the next (476) are listed.
    f := f + pg_temp.chk('C2. age 400: unacted older boosters are replaced', '2:Overdue,3:Scheduled',
            pg_temp.occ(v_farm, f_old, 'Newcastle booster (LaSota / I-2 / inactivated)', v_today + 150));
    f := f + pg_temp.chk('C3. a repeat''s age is its own (day 385)', '385',
            (SELECT s.agedays::text FROM fnpoultrylifecycle_schedule(v_farm, v_today + 150) s
             WHERE s.flockid = f_old AND s.occurrence = 2));
    f := f + pg_temp.chk('C4. ... and its due date follows from it', (v_today - 250 + 385)::text,
            (SELECT s.duedate::text FROM fnpoultrylifecycle_schedule(v_farm, v_today + 150) s
             WHERE s.flockid = f_old AND s.occurrence = 2));

    -- ========================================================= D. completing
    SELECT milestoneid INTO v_mid FROM poultrylifecyclemilestones WHERE templateid = t_com AND repeateverydays IS NOT NULL;
    PERFORM sppoultrylifecycle_settaskstatus(v_farm, f_old, v_mid, 'Completed', 'Done with LaSota', 'tester', 0);
    f := f + pg_temp.chk('D1. booster 0 completed, booster 1 untouched', '0:Completed,1:Scheduled',
            pg_temp.occ(v_farm, f_old, 'Newcastle booster (LaSota / I-2 / inactivated)', v_today));
    f := f + pg_temp.chk('D2. a completed repeat stays listed later on', '0:Completed,2:Overdue,3:Scheduled',
            pg_temp.occ(v_farm, f_old, 'Newcastle booster (LaSota / I-2 / inactivated)', v_today + 150));
    f := f + pg_temp.chk('D3. history records the occurrence', '0|Overdue|Completed',
            (SELECT occurrence || '|' || fromstatus || '|' || tostatus FROM sppoultrylifecycle_taskhistory(v_farm, f_old, v_mid, 0)));
    f := f + pg_temp.chk('D4. no history for an untouched occurrence', '0',
            (SELECT count(*)::text FROM sppoultrylifecycle_taskhistory(v_farm, f_old, v_mid, 1)));
    BEGIN
        PERFORM sppoultrylifecycle_settaskstatus(v_farm, f_old, v_mid, 'Completed', NULL, 'tester', 1);
        f := f + pg_temp.chk('D5. a repeat not yet due cannot be completed', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.chk('D5. a repeat not yet due cannot be completed', 'refused',
                CASE WHEN SQLERRM ILIKE '%not due yet%' THEN 'refused' ELSE SQLERRM END);
    END;
    -- 347's six-argument call: a one-off milestone, occurrence 0.
    SELECT milestoneid INTO v_mid FROM poultrylifecyclemilestones WHERE templateid = t_com AND agevalue = 28;
    PERFORM sppoultrylifecycle_settaskstatus(v_farm, f_chick, v_mid, 'Completed', NULL, 'tester');
    f := f + pg_temp.chk('D6. 347 positional call completes a one-off milestone', 'Completed',
            (SELECT s.status FROM fnpoultrylifecycle_schedule(v_farm) s WHERE s.flockid = f_chick AND s.milestoneid = v_mid));

    -- ===================================================== E. bought older
    f := f + pg_temp.chk('E1. POL pullets: nothing before week 16', '112',
            (SELECT min(s.agedays)::text FROM fnpoultrylifecycle_schedule(v_farm) s WHERE s.flockid = f_pol));

    -- ==================================================== F. editing a plan
    PERFORM sppoultrylifecycletemplate_save(v_farm, t_brd, 'Our breeder plan', NULL, NULL, TRUE,
        jsonb_build_array(jsonb_build_object('ageunit', 'Week', 'agevalue', 42, 'title', 'ND + IBD',
                                             'leadtimedays', 7, 'repeateverydays', 84)), 'tester');
    f := f + pg_temp.chk('F1. an edited built-in plan is the farm''s own', 'false',
            (SELECT isdefault::text FROM sppoultrylifecycletemplate_getall(v_farm) WHERE templateid = t_brd));
    f := f + pg_temp.chk('F2. the repeat is saved', '84',
            (SELECT repeateverydays::text FROM sppoultrylifecyclemilestone_getall(v_farm, t_brd)));
    BEGIN
        PERFORM sppoultrylifecycletemplate_save(v_farm, NULL, 'Bad repeat', NULL, NULL, TRUE,
            jsonb_build_array(jsonb_build_object('ageunit', 'Day', 'agevalue', 1, 'title', 'x', 'repeateverydays', 0)), 'tester');
        f := f + pg_temp.chk('F3. a repeat of 0 days is refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN
        f := f + pg_temp.chk('F3. a repeat of 0 days is refused', 'refused',
                CASE WHEN SQLERRM ILIKE '%repeat every%' THEN 'refused' ELSE SQLERRM END);
    END;

    IF f > 0 THEN RAISE EXCEPTION '% vaccination schedule check(s) failed', f; END IF;
    RAISE NOTICE 'all vaccination schedule checks passed';
END
$t$;

ROLLBACK;
