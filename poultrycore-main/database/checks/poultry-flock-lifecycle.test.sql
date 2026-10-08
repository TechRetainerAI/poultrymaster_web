-- Behavioural checks for migration 347: the Flock Lifecycle Assistant.
--
-- SELF-CONTAINED: opens its own transaction and ROLLS IT BACK.
--
--   psql ... -X -f poultry-flock-lifecycle.test.sql
--
-- Every check prints "ok" or "FAIL"; the block RAISES at the end if any failed.
-- Dates are written relative to the company's business date, so the file
-- passes on any day and in any time zone.
--
--   A  Template creation + validation
--   B  Assignment: batch inheritance, flock override, replacement, breed flag
--   C  Age calculation (day-old and older-on-arrival flocks)
--   D  Due-date statuses: Scheduled / Upcoming / Due / Overdue
--   E  Completion, re-opening, history
--   F  Skipping (reason required)
--   G  Estimated start dates
--   H  History is append-only
--   I  Closed and pending flocks
--   J  Template / milestone retirement
--   K  Company isolation and company type
--   L  Time zone: "today" is the company's date
--   M  Permissions

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

CREATE FUNCTION pg_temp.chk_like(p_label text, p_pattern text, p_got text)
RETURNS integer LANGUAGE plpgsql AS $c$
BEGIN
    IF p_got ILIKE p_pattern THEN
        RAISE NOTICE 'ok    %  (%)', p_label, p_got;
        RETURN 0;
    END IF;
    RAISE NOTICE 'FAIL  %  expect like "%" got %', p_label, p_pattern, COALESCE(p_got, 'NULL');
    RETURN 1;
END $c$;

CREATE FUNCTION pg_temp.ms(p_unit text, p_age integer, p_title text, p_lead integer DEFAULT 3,
                           p_action text DEFAULT NULL, p_id integer DEFAULT NULL)
RETURNS jsonb LANGUAGE sql AS $c$
    SELECT jsonb_strip_nulls(jsonb_build_object('milestoneid', p_id, 'ageunit', p_unit, 'agevalue', p_age,
           'title', p_title, 'leadtimedays', p_lead, 'actiontype', p_action, 'category', 'Review'));
$c$;

-- The status of one (flock, milestone title) as the schedule reports it.
CREATE FUNCTION pg_temp.st(p_farm text, p_flock integer, p_title text)
RETURNS text LANGUAGE sql AS $c$
    SELECT s.status FROM fnpoultrylifecycle_schedule(p_farm) s WHERE s.flockid = p_flock AND s.title = p_title;
$c$;

DO $t$
DECLARE
    v_farm   text := gen_random_uuid()::text;
    v_other  text := gen_random_uuid()::text;
    v_today  date;
    v_batch  integer;
    v_batch2 integer;
    v_obatch integer;
    v_batch5 integer;
    f_b1     integer;   -- in batch, inherits
    f_b2     integer;   -- in batch, overridden by flock assignment
    f_solo   integer;   -- no batch, flock assignment, arrived at 16 weeks
    f_est    integer;   -- estimated start date
    f_pend   integer;   -- not arrived
    f_oth    integer;
    t_layer  integer;
    t_alt    integer;
    t_tmp    integer;
    a1       integer;
    a2       integer;
    v_mid    integer;
    v_n      integer;
    v_txt    text;
    f        integer := 0;
BEGIN
    v_today := fncompany_businessdate(v_farm);

    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate, costperchick, totalcost)
    VALUES ('lc-test', v_farm, 'B3', 'Batch three', 'Isa Brown', 1000, v_today - 107, 2, 2000) RETURNING batchid INTO v_batch;
    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate, costperchick, totalcost)
    VALUES ('lc-test', v_farm, 'B4', 'Batch four', 'Cobb 500', 500, v_today - 10, 2, 1000) RETURNING batchid INTO v_batch2;
    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate, costperchick, totalcost)
    VALUES ('lc-test', v_other, 'X1', 'Not yours', 'Isa Brown', 100, v_today - 107, 2, 200) RETURNING batchid INTO v_obatch;
    INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate, costperchick, totalcost)
    VALUES ('lc-test', v_farm, 'B5', 'Pullets bought at POL', 'Isa Brown', 300, v_today - 10, 2, 600) RETURNING batchid INTO v_batch5;

    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, hasarrived)
    VALUES ('lc-test', v_farm, 'B3-House A', 'Isa Brown', v_today - 107, 500, TRUE, v_batch, TRUE) RETURNING flockid INTO f_b1;
    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, hasarrived)
    VALUES ('lc-test', v_farm, 'B3-House B', 'Isa Brown', v_today - 107, 500, TRUE, v_batch, TRUE) RETURNING flockid INTO f_b2;
    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, hasarrived)
    VALUES ('lc-test', v_farm, 'Pullets', 'Isa Brown', v_today - 10, 300, TRUE, v_batch5, TRUE) RETURNING flockid INTO f_solo;
    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, hasarrived)
    VALUES ('lc-test', v_farm, 'Inherited', 'Cobb 500', v_today - 10, 500, TRUE, v_batch2, TRUE) RETURNING flockid INTO f_est;
    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, hasarrived)
    VALUES ('lc-test', v_farm, 'On order', 'Cobb 500', v_today + 5, 500, TRUE, v_batch2, FALSE) RETURNING flockid INTO f_pend;
    INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, hasarrived)
    VALUES ('lc-test', v_other, 'Their flock', 'Isa Brown', v_today - 107, 100, TRUE, v_obatch, TRUE) RETURNING flockid INTO f_oth;

    -- ============================================================== A. templates
    -- Farm-defined: the system ships none.
    f := f + pg_temp.chk('A0. no templates exist until the farm writes one', '0',
            (SELECT COUNT(*)::text FROM sppoultrylifecycletemplate_getall(v_farm)));

    t_layer := sppoultrylifecycletemplate_save(v_farm, NULL, 'Layer plan', 'Isa Brown', 'Our own reminders', TRUE,
        jsonb_build_array(
            pg_temp.ms('Week', 16, 'Prepare layer housing', 7, 'FlockTransfer'),   -- day 112: in 5 days
            pg_temp.ms('Week', 15, 'Week-15 review', 3),                          -- day 105: window 105..111 -> Due
            pg_temp.ms('Day', 107, 'Day-107 check', 0),                           -- today -> Due
            pg_temp.ms('Day', 106, 'Day-106 check', 0),                           -- yesterday -> Overdue
            pg_temp.ms('Week', 30, 'Production-stage review', 7, 'Production'),   -- far future -> Scheduled
            pg_temp.ms('Week', 1, 'Week-1 check', 2)),                            -- long past -> Overdue
        'tester');
    f := f + pg_temp.chk('A1. plan saved with its milestones', '6',
            (SELECT milestonecount::text FROM sppoultrylifecycletemplate_getall(v_farm) WHERE templateid = t_layer));
    f := f + pg_temp.chk('A2. week milestones stored in days', '112',
            (SELECT agedays::text FROM sppoultrylifecyclemilestone_getall(v_farm, t_layer) WHERE title = 'Prepare layer housing'));
    BEGIN
        PERFORM sppoultrylifecycletemplate_save(v_farm, NULL, '  layer PLAN ', NULL, NULL, TRUE,
            jsonb_build_array(pg_temp.ms('Day', 1, 'x')), 'tester');
        f := f + pg_temp.chk('A3. duplicate name refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('A3. duplicate name refused', '%already exists%', SQLERRM); END;
    BEGIN
        PERFORM sppoultrylifecycletemplate_save(v_farm, NULL, 'Empty', NULL, NULL, TRUE, '[]'::jsonb, 'tester');
        f := f + pg_temp.chk('A4. plan with no milestones refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('A4. plan with no milestones refused', '%at least one milestone%', SQLERRM); END;
    BEGIN
        PERFORM sppoultrylifecycletemplate_save(v_farm, NULL, 'Bad', NULL, NULL, TRUE,
            jsonb_build_array(pg_temp.ms('Month', 1, 'x')), 'tester');
        f := f + pg_temp.chk('A5. unknown age unit refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('A5. unknown age unit refused', '%days or weeks%', SQLERRM); END;
    BEGIN
        PERFORM sppoultrylifecycletemplate_save(v_farm, NULL, 'Bad2', NULL, NULL, TRUE,
            jsonb_build_array(pg_temp.ms('Day', 1, '   ')), 'tester');
        f := f + pg_temp.chk('A6. untitled milestone refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('A6. untitled milestone refused', '%title%', SQLERRM); END;
    BEGIN
        PERFORM sppoultrylifecycletemplate_save(v_farm, NULL, 'Bad3', NULL, NULL, TRUE,
            jsonb_build_array(pg_temp.ms('Day', 1, 'x', 3, 'GiveVaccine')), 'tester');
        f := f + pg_temp.chk('A7. unknown action link refused (links only, no actions)', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('A7. unknown action link refused (links only, no actions)', '%unknown action link%', SQLERRM); END;

    t_alt := sppoultrylifecycletemplate_save(v_farm, NULL, 'Broiler plan', 'Cobb 500', NULL, TRUE,
        jsonb_build_array(pg_temp.ms('Day', 14, 'Day-14 review', 2), pg_temp.ms('Day', 3, 'Day-3 check', 0)), 'tester');

    -- ============================================================== B. assignment
    a1 := sppoultrylifecycle_assign(v_farm, t_layer, v_batch, NULL, 0, 'tester');
    f := f + pg_temp.chk('B1. both batch flocks inherit the batch plan', '2',
            (SELECT COUNT(DISTINCT flockid)::text FROM fnpoultrylifecycle_schedule(v_farm) WHERE templateid = t_layer));
    f := f + pg_temp.chk('B2. ... reported as inherited from the batch', 'Batch',
            (SELECT DISTINCT assignedvia FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_b1));
    a2 := sppoultrylifecycle_assign(v_farm, t_alt, NULL, f_b2, 0, 'tester');
    f := f + pg_temp.chk('B3. a flock assignment overrides the batch''s', 'Flock|Broiler plan',
            (SELECT DISTINCT assignedvia || '|' || templatename FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_b2));
    f := f + pg_temp.chk('B4. the sibling keeps the batch plan', 'Layer plan',
            (SELECT DISTINCT templatename FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_b1));
    f := f + pg_temp.chk('B5. breed mismatch flagged (Broiler plan on an Isa Brown flock)', 'true',
            (SELECT breedmismatch::text FROM sppoultrylifecycleassignment_getall(v_farm) WHERE assignmentid = a2));
    PERFORM sppoultrylifecycle_assign(v_farm, t_layer, NULL, f_b2, 0, 'tester');
    f := f + pg_temp.chk('B6. reassigning a target replaces its plan', '1|Layer plan',
            (SELECT COUNT(*)::text || '|' || MAX(templatename) FROM sppoultrylifecycleassignment_getall(v_farm) WHERE flockid = f_b2));
    f := f + pg_temp.chk('B7. ... and keeps the old assignment for history', 'false',
            (SELECT isactive::text FROM poultrylifecycleassignments WHERE assignmentid = a2));
    PERFORM sppoultrylifecycle_assign(v_farm, t_alt, v_batch2, NULL, 0, 'tester');
    BEGIN
        PERFORM sppoultrylifecycle_assign(v_farm, t_layer, v_batch, f_b1, 0, 'tester');
        f := f + pg_temp.chk('B8. batch AND flock at once refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('B8. batch AND flock at once refused', '%either a batch or a flock%', SQLERRM); END;

    -- ============================================================== C. age
    f := f + pg_temp.chk('C1. day-old flock started 107 days ago is 107 days old', '107',
            (SELECT DISTINCT currentagedays::text FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_b1));
    -- Pullets bought at 16 weeks (112 days), started 10 days ago: 122 days old.
    PERFORM sppoultrylifecycle_assign(v_farm, t_layer, NULL, f_solo, 112, 'tester');
    f := f + pg_temp.chk('C2. age at start is added (112 + 10)', '122',
            (SELECT DISTINCT currentagedays::text FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_solo));
    f := f + pg_temp.chk('C3. milestones before arrival are not tasks for that flock', '2',
            (SELECT COUNT(*)::text FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_solo));   -- week 16 + week 30
    f := f + pg_temp.chk('C4. due date = start + (milestone age - age at start)', (v_today - 10)::text,
            (SELECT duedate::text FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_solo AND title = 'Prepare layer housing'));

    -- ============================================================== D. statuses
    f := f + pg_temp.chk('D1. "B3 reaches week 16 in 5 days" -> Upcoming', 'Upcoming|5',
            (SELECT status || '|' || daysuntildue FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_b1 AND title = 'Prepare layer housing'));
    f := f + pg_temp.chk('D2. day milestone falling today -> Due', 'Due', pg_temp.st(v_farm, f_b1, 'Day-107 check'));
    f := f + pg_temp.chk('D3. inside a week milestone''s week -> Due', 'Due', pg_temp.st(v_farm, f_b1, 'Week-15 review'));
    f := f + pg_temp.chk('D4. day milestone that fell yesterday -> Overdue', 'Overdue', pg_temp.st(v_farm, f_b1, 'Day-106 check'));
    f := f + pg_temp.chk('D5. week milestone whose week has ended -> Overdue', 'Overdue', pg_temp.st(v_farm, f_b1, 'Week-1 check'));
    f := f + pg_temp.chk('D6. outside its lead time -> Scheduled', 'Scheduled', pg_temp.st(v_farm, f_b1, 'Production-stage review'));
    f := f + pg_temp.chk('D7. lead time: visible 7 days before the due date', (v_today - 2)::text,
            (SELECT visiblefrom::text FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_b1 AND title = 'Prepare layer housing'));
    f := f + pg_temp.chk('D8. Open view = Upcoming + Due + Overdue only', '0',
            (SELECT COUNT(*)::text FROM sppoultrylifecycle_tasks(v_farm, 'Open', f_b1) WHERE status NOT IN ('Upcoming', 'Due', 'Overdue')));
    f := f + pg_temp.chk('D9. Open view lists overdue first', 'Overdue',
            (SELECT status FROM sppoultrylifecycle_tasks(v_farm, 'Open', f_b1) LIMIT 1));
    f := f + pg_temp.chk('D10. action link carried to the task', 'FlockTransfer',
            (SELECT actiontype FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_b1 AND title = 'Prepare layer housing'));
    -- B3-House A and B: 1 upcoming, 2 due, 2 overdue each. Pullets: week 16 fell
    -- 10 days ago and its week ended 4 days ago -> 1 overdue. Inherited (Broiler
    -- plan): day 3 fell 7 days ago -> 1 overdue; day 14 is outside its lead time.
    f := f + pg_temp.chk('D11. summary counts (upcoming|due|overdue)', '2|4|6',
            (SELECT upcoming || '|' || due || '|' || overdue FROM sppoultrylifecycle_summary(v_farm)));

    -- ============================================================== E. complete
    SELECT milestoneid INTO v_mid FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_b1 AND title = 'Prepare layer housing';
    PERFORM sppoultrylifecycle_settaskstatus(v_farm, f_b1, v_mid, 'Completed', 'Moved to house C', 'tester');
    f := f + pg_temp.chk('E1. completed', 'Completed', pg_temp.st(v_farm, f_b1, 'Prepare layer housing'));
    f := f + pg_temp.chk('E2. the sibling flock''s copy is untouched', 'Upcoming', pg_temp.st(v_farm, f_b2, 'Prepare layer housing'));
    f := f + pg_temp.chk('E3. history: Upcoming -> Completed by tester', 'Upcoming|Completed|tester|Moved to house C',
            (SELECT fromstatus || '|' || tostatus || '|' || actor || '|' || note FROM sppoultrylifecycle_taskhistory(v_farm, f_b1, v_mid)));
    BEGIN
        PERFORM sppoultrylifecycle_settaskstatus(v_farm, f_b1, v_mid, 'Completed', NULL, 'tester');
        f := f + pg_temp.chk('E4. completing twice refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('E4. completing twice refused', '%already completed%', SQLERRM); END;
    PERFORM sppoultrylifecycle_settaskstatus(v_farm, f_b1, v_mid, 'Open', 'Ticked by mistake', 'tester2');
    f := f + pg_temp.chk('E5. reopened task goes back to its derived status', 'Upcoming', pg_temp.st(v_farm, f_b1, 'Prepare layer housing'));
    f := f + pg_temp.chk('E6. both events kept, newest first', '2|Completed->Open',
            (SELECT COUNT(*)::text || '|' || (array_agg(fromstatus || '->' || tostatus ORDER BY atutc DESC, eventid DESC))[1]
             FROM sppoultrylifecycle_taskhistory(v_farm, f_b1, v_mid)));
    SELECT milestoneid INTO v_mid FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_b1 AND title = 'Production-stage review';
    BEGIN
        PERFORM sppoultrylifecycle_settaskstatus(v_farm, f_b1, v_mid, 'Completed', NULL, 'tester');
        f := f + pg_temp.chk('E7. a Scheduled task cannot be completed yet', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('E7. a Scheduled task cannot be completed yet', '%not due yet%', SQLERRM); END;
    SELECT milestoneid INTO v_mid FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_b1 AND title = 'Day-106 check';
    PERFORM sppoultrylifecycle_settaskstatus(v_farm, f_b1, v_mid, 'Completed', NULL, 'tester');
    f := f + pg_temp.chk('E8. an Overdue task can be completed late', 'Completed', pg_temp.st(v_farm, f_b1, 'Day-106 check'));
    f := f + pg_temp.chk('E9. task keeps a snapshot of its due date', (v_today - 1)::text,
            (SELECT duedate::text FROM poultrylifecycletasks WHERE flockid = f_b1 AND milestoneid = v_mid));

    -- ============================================================== F. skip
    SELECT milestoneid INTO v_mid FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_b1 AND title = 'Week-1 check';
    BEGIN
        PERFORM sppoultrylifecycle_settaskstatus(v_farm, f_b1, v_mid, 'Skipped', '  ', 'tester');
        f := f + pg_temp.chk('F1. skipping without a reason refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('F1. skipping without a reason refused', '%why%', SQLERRM); END;
    PERFORM sppoultrylifecycle_settaskstatus(v_farm, f_b1, v_mid, 'Skipped', 'Flock bought after week 1', 'tester');
    f := f + pg_temp.chk('F2. skipped with its reason', 'Skipped|Flock bought after week 1',
            (SELECT status || '|' || note FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_b1 AND milestoneid = v_mid));
    f := f + pg_temp.chk('F3. skipped tasks leave the Open view', '0',
            (SELECT COUNT(*)::text FROM sppoultrylifecycle_tasks(v_farm, 'Open', f_b1) WHERE milestoneid = v_mid));
    f := f + pg_temp.chk('F4. ... and appear in the Skipped view', '1',
            (SELECT COUNT(*)::text FROM sppoultrylifecycle_tasks(v_farm, 'Skipped', f_b1)));

    -- ============================================================== G. estimated
    f := f + pg_temp.chk('G1. a known start date is not an estimate', 'false',
            (SELECT DISTINCT isestimated::text FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_est));
    INSERT INTO poultryopeningflockposition (farmid, flockid, effectivebusinessdate, originallyplaced, openinglivebirds, startdateestimated)
    VALUES (v_farm, f_est, v_today, 500, 500, TRUE);
    f := f + pg_temp.chk('G2. a start date derived during onboarding marks every date estimated', 'true',
            (SELECT bool_and(isestimated)::text FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_est));
    f := f + pg_temp.chk('G3. the batch plan reached the onboarded flock', 'Broiler plan',
            (SELECT DISTINCT templatename FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_est));

    -- ============================================================== H. append-only
    BEGIN
        UPDATE poultrylifecycletaskevents SET note = 'edited' WHERE farmid = v_farm;
        f := f + pg_temp.chk('H1. history cannot be edited', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('H1. history cannot be edited', '%append-only%', SQLERRM); END;
    BEGIN
        DELETE FROM poultrylifecycletaskevents WHERE farmid = v_farm;
        f := f + pg_temp.chk('H2. history cannot be deleted', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('H2. history cannot be deleted', '%append-only%', SQLERRM); END;

    -- ============================================================== I. closed / pending
    f := f + pg_temp.chk('I1. a flock that has not arrived has no tasks yet', '0',
            (SELECT COUNT(*)::text FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_pend));
    PERFORM set_config('app.flock_closeout', 'on', true);
    UPDATE flock SET closeddate = v_today, active = FALSE WHERE flockid = f_b1;
    PERFORM set_config('app.flock_closeout', 'off', true);
    f := f + pg_temp.chk('I2. a closed flock''s reminders stop', '0',
            (SELECT COUNT(*)::text FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_b1));
    f := f + pg_temp.chk('I3. ... but what was done is kept', '3',
            (SELECT COUNT(*)::text FROM poultrylifecycletasks WHERE flockid = f_b1));
    BEGIN
        PERFORM sppoultrylifecycle_settaskstatus(v_farm, f_b1, v_mid, 'Open', NULL, 'tester');
        f := f + pg_temp.chk('I4. cannot act on a closed flock''s task', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('I4. cannot act on a closed flock''s task', '%not on this company''s lifecycle schedule%', SQLERRM); END;

    -- ============================================================== J. retirement
    BEGIN
        PERFORM sppoultrylifecycletemplate_delete(v_farm, t_layer, 'tester');
        f := f + pg_temp.chk('J1. deleting a plan in use refused', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('J1. deleting a plan in use refused', '%still assigned%', SQLERRM); END;
    t_tmp := sppoultrylifecycletemplate_save(v_farm, NULL, 'Scratch', NULL, NULL, TRUE,
        jsonb_build_array(pg_temp.ms('Day', 1, 'x')), 'tester');
    f := f + pg_temp.chk('J2. an unused plan is deleted outright', 'Deleted',
            sppoultrylifecycletemplate_delete(v_farm, t_tmp, 'tester'));
    -- Drop "Day-106 check" (has history on f_b1) and "Week-15 review" (none) from the layer plan.
    PERFORM sppoultrylifecycletemplate_save(v_farm, t_layer, 'Layer plan', 'Isa Brown', NULL, TRUE,
        (SELECT jsonb_agg(pg_temp.ms(m.ageunit, m.agevalue, m.title, m.leadtimedays, m.actiontype, m.milestoneid) ORDER BY m.agedays)
         FROM sppoultrylifecyclemilestone_getall(v_farm, t_layer) m
         WHERE m.title NOT IN ('Day-106 check', 'Week-15 review')), 'tester');
    f := f + pg_temp.chk('J3. a dropped milestone with history is retired, not deleted', 'false',
            (SELECT isactive::text FROM poultrylifecyclemilestones WHERE templateid = t_layer AND title = 'Day-106 check'));
    f := f + pg_temp.chk('J4. a dropped milestone without history is deleted', '0',
            (SELECT COUNT(*)::text FROM poultrylifecyclemilestones WHERE templateid = t_layer AND title = 'Week-15 review'));
    f := f + pg_temp.chk('J5. retired milestones leave the schedule', '0',
            (SELECT COUNT(*)::text FROM fnpoultrylifecycle_schedule(v_farm) WHERE title IN ('Day-106 check', 'Week-15 review')));
    UPDATE poultrylifecycletemplates SET isactive = FALSE WHERE templateid = t_alt;
    BEGIN
        PERFORM sppoultrylifecycle_assign(v_farm, t_alt, NULL, f_solo, 0, 'tester');
        f := f + pg_temp.chk('J6. an inactive plan cannot be assigned', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('J6. an inactive plan cannot be assigned', '%inactive%', SQLERRM); END;

    -- ============================================================== K. isolation
    f := f + pg_temp.chk('K1. another company sees no plans', '0', (SELECT COUNT(*)::text FROM sppoultrylifecycletemplate_getall(v_other)));
    f := f + pg_temp.chk('K2. ... and no tasks', '0', (SELECT COUNT(*)::text FROM fnpoultrylifecycle_schedule(v_other)));
    BEGIN
        PERFORM sppoultrylifecycle_assign(v_farm, t_layer, NULL, f_oth, 0, 'tester');
        f := f + pg_temp.chk('K3. cannot assign to another company''s flock', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('K3. cannot assign to another company''s flock', '%not found for this company%', SQLERRM); END;
    BEGIN
        PERFORM sppoultrylifecycle_assign(v_farm, t_layer, v_obatch, NULL, 0, 'tester');
        f := f + pg_temp.chk('K4. cannot assign to another company''s batch', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('K4. cannot assign to another company''s batch', '%not found for this company%', SQLERRM); END;
    BEGIN
        PERFORM sppoultrylifecycle_assign(v_other, t_layer, v_obatch, NULL, 0, 'tester');
        f := f + pg_temp.chk('K5. cannot use another company''s plan', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('K5. cannot use another company''s plan', '%not found for this company%', SQLERRM); END;
    SELECT milestoneid INTO v_mid FROM fnpoultrylifecycle_schedule(v_farm) WHERE flockid = f_b2 AND title = 'Prepare layer housing';
    BEGIN
        PERFORM sppoultrylifecycle_settaskstatus(v_other, f_b2, v_mid, 'Completed', NULL, 'tester');
        f := f + pg_temp.chk('K6. cannot complete another company''s task', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('K6. cannot complete another company''s task', '%not on this company''s lifecycle schedule%', SQLERRM); END;
    BEGIN
        PERFORM sppoultrylifecycletemplate_delete(v_other, t_layer, 'tester');
        f := f + pg_temp.chk('K7. cannot delete another company''s plan', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('K7. cannot delete another company''s plan', '%not found%', SQLERRM); END;
    INSERT INTO farms (id, farmid, name, email, type) VALUES (gen_random_uuid()::text, v_other, 'ZZ Water', 'zz@example.com', 'Water');
    t_tmp := sppoultrylifecycletemplate_save(v_other, NULL, 'Theirs', NULL, NULL, TRUE, jsonb_build_array(pg_temp.ms('Day', 1, 'x')), 'tester');
    BEGIN
        PERFORM sppoultrylifecycle_assign(v_other, t_tmp, v_obatch, NULL, 0, 'tester');
        f := f + pg_temp.chk('K8. a Water company cannot assign plans', 'BLOCK', 'ALLOWED');
    EXCEPTION WHEN OTHERS THEN f := f + pg_temp.chk_like('K8. a Water company cannot assign plans', '%only available for Poultry%', SQLERRM); END;

    -- ============================================================== L. time zone
    -- Two companies on opposite sides of the date line: at any instant their
    -- business dates differ, and each one's schedule must follow its own.
    DECLARE
        z_east text := gen_random_uuid()::text;   -- UTC+14
        z_west text := gen_random_uuid()::text;   -- UTC-11
        d_east date; d_west date; t_e integer; t_w integer; fe integer; fw integer; be integer; bw integer;
    BEGIN
        INSERT INTO farms (id, farmid, name, email, type, timezoneid) VALUES
            (gen_random_uuid()::text, z_east, 'ZZ East', 'e@example.com', 'Poultry', 'Pacific/Kiritimati'),
            (gen_random_uuid()::text, z_west, 'ZZ West', 'w@example.com', 'Poultry', 'Pacific/Pago_Pago');
        d_east := fncompany_businessdate(z_east);
        d_west := fncompany_businessdate(z_west);
        f := f + pg_temp.chk('L1. the two companies are on different dates right now', 'true', (d_east <> d_west)::text);

        -- Both flocks started on the EAST company's date minus 7; a day-7 milestone.
        INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate, costperchick, totalcost)
        VALUES ('lc-test', z_east, 'E1', 'East', 'Isa Brown', 10, d_east - 7, 1, 10) RETURNING batchid INTO be;
        INSERT INTO mainflockbatch (userid, farmid, batchcode, batchname, breed, numberofbirds, startdate, costperchick, totalcost)
        VALUES ('lc-test', z_west, 'W1', 'West', 'Isa Brown', 10, d_east - 7, 1, 10) RETURNING batchid INTO bw;
        INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, hasarrived)
        VALUES ('lc-test', z_east, 'East', 'Isa Brown', d_east - 7, 10, TRUE, be, TRUE) RETURNING flockid INTO fe;
        INSERT INTO flock (userid, farmid, name, breed, startdate, quantity, active, batchid, hasarrived)
        VALUES ('lc-test', z_west, 'West', 'Isa Brown', d_east - 7, 10, TRUE, bw, TRUE) RETURNING flockid INTO fw;
        t_e := sppoultrylifecycletemplate_save(z_east, NULL, 'P', NULL, NULL, TRUE, jsonb_build_array(pg_temp.ms('Day', 7, 'D7', 3)), 'tester');
        t_w := sppoultrylifecycletemplate_save(z_west, NULL, 'P', NULL, NULL, TRUE, jsonb_build_array(pg_temp.ms('Day', 7, 'D7', 3)), 'tester');
        PERFORM sppoultrylifecycle_assign(z_east, t_e, NULL, fe, 0, 'tester');
        PERFORM sppoultrylifecycle_assign(z_west, t_w, NULL, fw, 0, 'tester');
        f := f + pg_temp.chk('L2. east: due on its own today', 'Due', pg_temp.st(z_east, fe, 'D7'));
        f := f + pg_temp.chk('L3. west: the same date is still tomorrow there', 'Upcoming|1',
                (SELECT status || '|' || daysuntildue FROM fnpoultrylifecycle_schedule(z_west) WHERE flockid = fw));
        f := f + pg_temp.chk('L4. "today" is the company date, not the server''s', d_west::text,
                (SELECT DISTINCT today::text FROM fnpoultrylifecycle_schedule(z_west)));
    END;

    -- ============================================================== M. permissions
    IF to_regclass('public.iampermissions') IS NOT NULL THEN
        f := f + pg_temp.chk('M1. four catalog keys', '4',
                (SELECT COUNT(*)::text FROM iampermissions WHERE permissionkey LIKE 'poultry.lifecycle.%'));
        f := f + pg_temp.chk('M2. every role that edits flocks can work lifecycle tasks', 'true',
                (NOT EXISTS (SELECT 1 FROM iamrolepermissions rp WHERE rp.permissionkey = 'poultry.flocks.edit'
                              AND NOT EXISTS (SELECT 1 FROM iamrolepermissions r2 WHERE r2.roleid = rp.roleid
                                              AND r2.permissionkey = 'poultry.lifecycle.edit')))::text);
        f := f + pg_temp.chk('M3. delete flagged dangerous', 'true',
                (SELECT isdangerous::text FROM iampermissions WHERE permissionkey = 'poultry.lifecycle.delete'));
    END IF;

    IF f > 0 THEN
        RAISE EXCEPTION 'poultry-flock-lifecycle: % check(s) FAILED', f;
    END IF;
    RAISE NOTICE 'poultry-flock-lifecycle: all checks passed';
END $t$;

ROLLBACK;
