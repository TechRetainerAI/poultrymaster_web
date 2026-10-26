-- =============================================================================
-- 387  Ghana national vaccination schedule on the Flock Lifecycle Assistant
-- =============================================================================
--
-- WHAT THIS ADDS
-- --------------
-- 1. REPEATING MILESTONES. A milestone may repeat every N days
--    (poultrylifecyclemilestones.repeateverydays) until the flock is closed.
--    Each repeat is an OCCURRENCE: 0 is the milestone's own age, 1 is one
--    interval later, and so on. A task row is now one per (flock, milestone,
--    occurrence), and the history records the occurrence too.
--
--      occurrence age (days)  = agedays + occurrence * repeateverydays
--      dates                  = exactly as 347, from the occurrence age
--
--    Which occurrences the schedule lists, per flock:
--      * every one from the milestone's age up to the NEXT one still to come
--        (its reminder appears within one interval + lead time of today) --
--        never an endless list;
--      * an occurrence nobody acted on is dropped once the next one is due:
--        a newer repeat replaces it, so a flock assigned late does not open
--        with a pile of overdue boosters. Completed / skipped ones stay.
--
-- 2. THE NATIONAL SCHEDULE AS TWO BUILT-IN PLANS, from the Veterinary
--    Services Directorate (Ghana) "National Vaccination Schedule" poster:
--      Ghana National Vaccination - Commercial Layers   10 milestones
--      Ghana National Vaccination - Breeders            11 milestones
--    Ages are the poster's days (Week 8 is day 53 on the poster, not 56).
--    The poster's footnotes are in the milestone descriptions, and its repeat
--    rules are repeating milestones:
--      commercial  "Repeat LaSota / I-2 / inactivated Newcastle every 3 months
--                   after 16 weeks"  -> a booster from week 29, every 13 weeks
--      breeder     "Repeat 3rd Newcastle + IBD every 3 months from week 42"
--                   -> the week-42 milestone repeats every 13 weeks
--    Each plan's description carries the locality note: confirm with your vet.
--
--    COPIED, not shared, ONCE per farm -- the same rules as the 385 feed
--    defaults: poultrylifecycledefaultsapplied remembers the farm was seeded,
--    so a deleted plan stays deleted; p_force ("Add the national schedule")
--    re-adds a missing one. A plan of the same name is left alone. Editing a
--    built-in plan makes it the farm's own (defaultkey cleared).
--    Plans are NOT assigned to anything: the farm assigns them, as before.
--
-- Changes
--   + poultrylifecyclemilestones.repeateverydays
--   + poultrylifecycletasks.occurrence      (unique now flock+milestone+occurrence)
--   + poultrylifecycletaskevents.occurrence
--   + poultrylifecycletemplates.defaultkey
--   + poultrylifecycledefaultsapplied
--   ~ fnpoultrylifecycle_schedule, sppoultrylifecycle_tasks   (+ occurrence, repeateverydays)
--   ~ sppoultrylifecycle_settaskstatus  (+ p_occurrence, last, default 0)
--   ~ sppoultrylifecycle_taskhistory    (+ p_occurrence, last; + occurrence column)
--   ~ sppoultrylifecycle_summary        (recreated, same shape)
--   ~ sppoultrylifecycletemplate_save   (repeateverydays; an edit clears defaultkey)
--   ~ sppoultrylifecycletemplate_getall (+ isdefault)
--   ~ sppoultrylifecyclemilestone_getall (+ repeateverydays)
--   + sppoultrylifecycle_ensuredefaults(p_farmid, p_actor, p_force)
--
-- Positional calls written for 347 keep working: new parameters come last and
-- default to the old behaviour. Idempotent. PostgreSQL. The behavioural checks
-- are in poultrycore-main/database/checks/poultry-vaccination-schedule.test.sql.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------- 1. columns --
ALTER TABLE public.poultrylifecyclemilestones ADD COLUMN IF NOT EXISTS repeateverydays integer NULL;
DO $c$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_poultrylifecyclemilestones_repeat') THEN
        ALTER TABLE public.poultrylifecyclemilestones
            ADD CONSTRAINT ck_poultrylifecyclemilestones_repeat
            CHECK (repeateverydays IS NULL OR (repeateverydays >= 1 AND repeateverydays <= 3650));
    END IF;
END $c$;

ALTER TABLE public.poultrylifecycletasks      ADD COLUMN IF NOT EXISTS occurrence integer NOT NULL DEFAULT 0;
ALTER TABLE public.poultrylifecycletaskevents ADD COLUMN IF NOT EXISTS occurrence integer NOT NULL DEFAULT 0;

ALTER TABLE public.poultrylifecycletasks DROP CONSTRAINT IF EXISTS ux_poultrylifecycletasks_flockmilestone;
DO $c$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ux_poultrylifecycletasks_flockmilestoneocc') THEN
        ALTER TABLE public.poultrylifecycletasks
            ADD CONSTRAINT ux_poultrylifecycletasks_flockmilestoneocc UNIQUE (flockid, milestoneid, occurrence);
    END IF;
END $c$;

ALTER TABLE public.poultrylifecycletemplates ADD COLUMN IF NOT EXISTS defaultkey varchar(40) NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrylifecycletemplates_defaultkey
    ON public.poultrylifecycletemplates (farmid, defaultkey) WHERE defaultkey IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.poultrylifecycledefaultsapplied (
    farmid     text      PRIMARY KEY,
    version    integer   NOT NULL,
    appliedat  timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    appliedby  text      NULL
);

-- --------------------------------------------- 2. drop changed signatures --
DO $d$ DECLARE r record; BEGIN
    FOR r IN SELECT p.oid::regprocedure::text AS sig FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public'
               AND p.proname IN ('fnpoultrylifecycle_schedule', 'sppoultrylifecycle_tasks',
                                 'sppoultrylifecycle_settaskstatus', 'sppoultrylifecycle_taskhistory',
                                 'sppoultrylifecycletemplate_getall', 'sppoultrylifecyclemilestone_getall',
                                 'sppoultrylifecycle_ensuredefaults')
    LOOP EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig; END LOOP;
END $d$;

-- ------------------------------------------------------- 3. the schedule ------
CREATE FUNCTION public.fnpoultrylifecycle_schedule(p_farmid text, p_asof date DEFAULT NULL)
RETURNS TABLE(flockid integer, flockname text, batchid integer, batchcode text, houseid integer,
              breed text, flockstartdate date, flockactive boolean, isestimated boolean,
              assignmentid integer, assignedvia text, templateid integer, templatename text,
              templatebreed text, ageatstartdays integer, currentagedays integer,
              milestoneid integer, title text, description text, category text,
              ageunit text, agevalue integer, agedays integer, leadtimedays integer, actiontype text,
              duedate date, duewindowend date, visiblefrom date, daysuntildue integer,
              taskid integer, status text, note text, actedby text, actedat timestamp, today date,
              occurrence integer, repeateverydays integer)
LANGUAGE sql STABLE AS $f$
    WITH t AS (SELECT COALESCE(p_asof, fncompany_businessdate(p_farmid)) AS today),
    fl AS (
        SELECT f.*,
               -- Flock-level assignment overrides the batch's.
               COALESCE(af.assignmentid, ab.assignmentid)     AS a_id,
               CASE WHEN af.assignmentid IS NOT NULL THEN 'Flock' ELSE 'Batch' END AS a_via,
               COALESCE(af.templateid, ab.templateid)         AS a_template,
               COALESCE(af.ageatstartdays, ab.ageatstartdays) AS a_age
        FROM   flock f
        LEFT   JOIN poultrylifecycleassignments af
               ON af.farmid = f.farmid AND af.flockid = f.flockid AND af.isactive
        LEFT   JOIN poultrylifecycleassignments ab
               ON ab.farmid = f.farmid AND ab.batchid = f.batchid AND ab.isactive
        WHERE  f.farmid = p_farmid
          AND  NOT COALESCE(f.isdeleted, FALSE)
          AND  f.closeddate IS NULL
          AND  COALESCE(f.hasarrived, TRUE)
          AND  f.startdate IS NOT NULL
    ),
    o AS (
        -- One row per (flock, milestone, occurrence). A milestone without a
        -- repeat has occurrence 0 only. A repeating one lists every occurrence
        -- up to the next one still to come.
        SELECT fl.*, tp.templateid AS tp_id, tp.name AS tp_name, tp.breed AS tp_breed,
               m.milestoneid AS m_id, m.title AS m_title, m.description AS m_description,
               m.category AS m_category, m.ageunit AS m_ageunit, m.agevalue AS m_agevalue,
               m.leadtimedays AS m_lead, m.actiontype AS m_action, m.sortorder AS m_sort,
               m.repeateverydays AS m_every, k.occ,
               m.agedays + k.occ * COALESCE(m.repeateverydays, 0) AS occdays,
               ((SELECT today FROM t) - fl.startdate + fl.a_age)::integer AS curage
        FROM   fl
        JOIN   poultrylifecycletemplates tp ON tp.templateid = fl.a_template AND tp.farmid = p_farmid
        JOIN   poultrylifecyclemilestones m ON m.templateid = tp.templateid AND m.isactive
        CROSS  JOIN LATERAL generate_series(0,
                   CASE WHEN m.repeateverydays IS NULL THEN 0
                        ELSE LEAST(500, GREATEST(0,
                               (((SELECT today FROM t) - fl.startdate + fl.a_age)
                                + m.repeateverydays + m.leadtimedays - m.agedays) / m.repeateverydays))
                   END) AS k(occ)
        WHERE  fl.a_template IS NOT NULL
    ),
    s AS (
        SELECT o.flockid, o.name::text AS flockname, o.batchid, b.batchcode::text AS batchcode,
               o.houseid, COALESCE(NULLIF(btrim(o.breed), ''), b.breed)::text AS breed,
               o.startdate, COALESCE(o.active, TRUE) AS flockactive,
               COALESCE(op.startdateestimated, FALSE) AS isestimated,
               o.a_id, o.a_via, o.tp_id, o.tp_name, o.tp_breed, o.a_age, o.curage,
               o.m_id, o.m_title, o.m_description, o.m_category, o.m_ageunit, o.m_agevalue, o.occdays,
               o.m_lead, o.m_action, o.m_sort, o.m_every, o.occ,
               (o.startdate + (o.occdays - o.a_age))::date AS duedate,
               (o.startdate + (o.occdays - o.a_age)
                  + CASE WHEN o.m_ageunit = 'Week' THEN 6 ELSE 0 END)::date AS duewindowend,
               (o.startdate + (o.occdays - o.a_age) - o.m_lead)::date AS visiblefrom,
               tk.taskid, tk.status AS storedstatus, tk.note, tk.actedby, tk.actedat
        FROM   o
        LEFT   JOIN mainflockbatch b ON b.batchid = o.batchid AND b.farmid = o.farmid
        LEFT   JOIN LATERAL (
                   SELECT bool_or(x.startdateestimated) AS startdateestimated
                   FROM   poultryopeningflockposition x
                   WHERE  x.flockid = o.flockid AND x.farmid = p_farmid) op ON TRUE
        LEFT   JOIN poultrylifecycletasks tk
               ON tk.flockid = o.flockid AND tk.milestoneid = o.m_id AND tk.occurrence = o.occ
        WHERE  o.occdays >= o.a_age            -- before the birds arrived: not this farm's task
    )
    SELECT s.flockid, s.flockname, s.batchid, s.batchcode, s.houseid, s.breed, s.startdate,
           s.flockactive, s.isestimated, s.a_id, s.a_via, s.tp_id, s.tp_name::text,
           s.tp_breed::text, s.a_age, s.curage,
           s.m_id, s.m_title::text, s.m_description::text, s.m_category::text, s.m_ageunit::text,
           s.m_agevalue, s.occdays, s.m_lead, s.m_action::text,
           s.duedate, s.duewindowend, s.visiblefrom,
           (s.duedate - (SELECT today FROM t))::integer,
           s.taskid,
           (CASE
                WHEN s.storedstatus IN ('Completed', 'Skipped') THEN s.storedstatus
                WHEN (SELECT today FROM t) <  s.visiblefrom  THEN 'Scheduled'
                WHEN (SELECT today FROM t) <  s.duedate      THEN 'Upcoming'
                WHEN (SELECT today FROM t) <= s.duewindowend THEN 'Due'
                ELSE 'Overdue'
            END)::text,
           s.note::text, s.actedby::text, s.actedat,
           (SELECT today FROM t),
           s.occ, s.m_every
    FROM   s
    -- An unacted repeat is replaced once the next one is due.
    WHERE  NOT (s.m_every IS NOT NULL
                AND COALESCE(s.storedstatus, 'Open') NOT IN ('Completed', 'Skipped')
                AND s.duedate + s.m_every <= (SELECT today FROM t))
    ORDER  BY s.duedate, s.flockname, s.m_sort, s.m_id, s.occ;
$f$;

-- ------------------------------------------------------------ 4. task reads ----
CREATE FUNCTION public.sppoultrylifecycle_tasks(p_farmid text, p_view text DEFAULT 'Open', p_flockid integer DEFAULT NULL)
RETURNS TABLE(flockid integer, flockname text, batchid integer, batchcode text, houseid integer,
              breed text, flockstartdate date, flockactive boolean, isestimated boolean,
              assignmentid integer, assignedvia text, templateid integer, templatename text,
              templatebreed text, ageatstartdays integer, currentagedays integer,
              milestoneid integer, title text, description text, category text,
              ageunit text, agevalue integer, agedays integer, leadtimedays integer, actiontype text,
              duedate date, duewindowend date, visiblefrom date, daysuntildue integer,
              taskid integer, status text, note text, actedby text, actedat timestamp, today date,
              occurrence integer, repeateverydays integer)
LANGUAGE sql STABLE AS $f$
    SELECT s.*
    FROM   fnpoultrylifecycle_schedule(p_farmid) s
    WHERE  (p_flockid IS NULL OR s.flockid = p_flockid)
      AND  (COALESCE(p_view, 'Open') = 'All'
            OR (p_view = 'Open' AND s.status IN ('Upcoming', 'Due', 'Overdue'))
            OR s.status = p_view)
    ORDER  BY CASE s.status WHEN 'Overdue' THEN 0 WHEN 'Due' THEN 1 WHEN 'Upcoming' THEN 2
                            WHEN 'Scheduled' THEN 3 ELSE 4 END,
              s.duedate, s.flockname, s.milestoneid, s.occurrence;
$f$;

CREATE OR REPLACE FUNCTION public.sppoultrylifecycle_summary(p_farmid text)
RETURNS TABLE(upcoming integer, due integer, overdue integer, completedlast30 integer,
              skippedlast30 integer, estimatedflocks integer, assignedflocks integer, today date)
LANGUAGE sql STABLE AS $f$
    SELECT COUNT(*) FILTER (WHERE s.status = 'Upcoming')::int,
           COUNT(*) FILTER (WHERE s.status = 'Due')::int,
           COUNT(*) FILTER (WHERE s.status = 'Overdue')::int,
           (SELECT COUNT(*) FROM poultrylifecycletasks k
            WHERE k.farmid = p_farmid AND k.status = 'Completed'
              AND k.actedat >= (now() at time zone 'utc') - interval '30 days')::int,
           (SELECT COUNT(*) FROM poultrylifecycletasks k
            WHERE k.farmid = p_farmid AND k.status = 'Skipped'
              AND k.actedat >= (now() at time zone 'utc') - interval '30 days')::int,
           COUNT(DISTINCT s.flockid) FILTER (WHERE s.isestimated)::int,
           COUNT(DISTINCT s.flockid)::int,
           fncompany_businessdate(p_farmid)
    FROM   fnpoultrylifecycle_schedule(p_farmid) s;
$f$;

-- ----------------------------------------------------------- 5. templates ------
-- 347's save, plus repeateverydays per milestone, and an edit of a built-in
-- plan makes it the farm's own (defaultkey cleared).
CREATE OR REPLACE FUNCTION public.sppoultrylifecycletemplate_save(
    p_farmid       text,
    p_templateid   integer,
    p_name         text,
    p_breed        text,
    p_description  text,
    p_isactive     boolean,
    p_milestones   jsonb,
    p_actor        text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql AS $f$
DECLARE
    v_id    integer := p_templateid;
    v_name  text := NULLIF(btrim(p_name), '');
    v_keep  integer[] := '{}';
    v_mid   integer;
    m       record;
    v_n     integer := 0;
BEGIN
    IF COALESCE(btrim(p_farmid), '') = '' THEN RAISE EXCEPTION 'Company is required.'; END IF;
    IF v_name IS NULL THEN RAISE EXCEPTION 'Give the lifecycle plan a name.'; END IF;
    IF EXISTS (SELECT 1 FROM poultrylifecycletemplates t
               WHERE t.farmid = p_farmid AND lower(btrim(t.name)) = lower(v_name)
                 AND t.templateid IS DISTINCT FROM v_id) THEN
        RAISE EXCEPTION 'A lifecycle plan called "%" already exists.', v_name;
    END IF;

    -- Validate every milestone before writing anything.
    FOR m IN
        SELECT e.n,
               NULLIF(e.v ->> 'milestoneid', '')::integer AS milestoneid,
               COALESCE(NULLIF(e.v ->> 'ageunit', ''), 'Week') AS ageunit,
               NULLIF(e.v ->> 'agevalue', '')::integer AS agevalue,
               NULLIF(btrim(e.v ->> 'title'), '') AS title,
               COALESCE(NULLIF(e.v ->> 'leadtimedays', '')::integer, 3) AS leadtimedays,
               NULLIF(btrim(e.v ->> 'actiontype'), '') AS actiontype,
               NULLIF(e.v ->> 'repeateverydays', '')::integer AS repeateverydays
        FROM   jsonb_array_elements(COALESCE(p_milestones, '[]'::jsonb)) WITH ORDINALITY AS e(v, n)
    LOOP
        v_n := v_n + 1;
        IF m.title IS NULL THEN RAISE EXCEPTION 'Milestone %: give it a title.', m.n; END IF;
        IF m.ageunit NOT IN ('Day', 'Week') THEN RAISE EXCEPTION 'Milestone %: age must be in days or weeks.', m.n; END IF;
        IF m.agevalue IS NULL OR m.agevalue < 0 OR m.agevalue > 5000 THEN
            RAISE EXCEPTION 'Milestone % (%): enter an age between 0 and 5000.', m.n, m.title;
        END IF;
        IF m.leadtimedays < 0 OR m.leadtimedays > 365 THEN
            RAISE EXCEPTION 'Milestone % (%): lead time must be between 0 and 365 days.', m.n, m.title;
        END IF;
        IF m.repeateverydays IS NOT NULL AND (m.repeateverydays < 1 OR m.repeateverydays > 3650) THEN
            RAISE EXCEPTION 'Milestone % (%): repeat every 1 to 3650 days, or not at all.', m.n, m.title;
        END IF;
        IF m.actiontype IS NOT NULL AND m.actiontype NOT IN ('FlockDetails', 'FlockTransfer', 'MedicationCampaign', 'Production', 'Closeout') THEN
            RAISE EXCEPTION 'Milestone % (%): unknown action link "%".', m.n, m.title, m.actiontype;
        END IF;
        IF m.milestoneid IS NOT NULL AND (v_id IS NULL OR NOT EXISTS (
               SELECT 1 FROM poultrylifecyclemilestones x
               WHERE x.milestoneid = m.milestoneid AND x.templateid = v_id AND x.farmid = p_farmid)) THEN
            RAISE EXCEPTION 'Milestone % does not belong to this plan.', m.n;
        END IF;
    END LOOP;
    IF v_n = 0 THEN RAISE EXCEPTION 'Add at least one milestone.'; END IF;
    IF v_n > 200 THEN RAISE EXCEPTION 'A plan can hold at most 200 milestones.'; END IF;

    IF v_id IS NULL THEN
        INSERT INTO poultrylifecycletemplates (farmid, name, breed, description, isactive, createdby)
        VALUES (p_farmid, v_name, NULLIF(btrim(p_breed), ''), NULLIF(btrim(p_description), ''),
                COALESCE(p_isactive, TRUE), p_actor)
        RETURNING templateid INTO v_id;
    ELSE
        UPDATE poultrylifecycletemplates t
        SET    name = v_name, breed = NULLIF(btrim(p_breed), ''), description = NULLIF(btrim(p_description), ''),
               isactive = COALESCE(p_isactive, t.isactive), updatedby = p_actor,
               updatedat = (now() at time zone 'utc'),
               defaultkey = NULL      -- 387: an edited built-in plan is the farm's own
        WHERE  t.templateid = v_id AND t.farmid = p_farmid;
        IF NOT FOUND THEN RAISE EXCEPTION 'Lifecycle plan not found for this company.'; END IF;
    END IF;

    FOR m IN
        SELECT e.n,
               NULLIF(e.v ->> 'milestoneid', '')::integer AS milestoneid,
               COALESCE(NULLIF(e.v ->> 'ageunit', ''), 'Week') AS ageunit,
               (e.v ->> 'agevalue')::integer AS agevalue,
               btrim(e.v ->> 'title') AS title,
               NULLIF(btrim(e.v ->> 'description'), '') AS description,
               NULLIF(btrim(e.v ->> 'category'), '') AS category,
               COALESCE(NULLIF(e.v ->> 'leadtimedays', '')::integer, 3) AS leadtimedays,
               NULLIF(btrim(e.v ->> 'actiontype'), '') AS actiontype,
               NULLIF(e.v ->> 'repeateverydays', '')::integer AS repeateverydays
        FROM   jsonb_array_elements(p_milestones) WITH ORDINALITY AS e(v, n)
    LOOP
        IF m.milestoneid IS NULL THEN
            INSERT INTO poultrylifecyclemilestones
                (templateid, farmid, ageunit, agevalue, title, description, category, leadtimedays, actiontype, sortorder, repeateverydays)
            VALUES (v_id, p_farmid, m.ageunit, m.agevalue, m.title, m.description, m.category,
                    m.leadtimedays, m.actiontype, m.n, m.repeateverydays)
            RETURNING milestoneid INTO v_mid;
        ELSE
            UPDATE poultrylifecyclemilestones x
            SET    ageunit = m.ageunit, agevalue = m.agevalue, title = m.title, description = m.description,
                   category = m.category, leadtimedays = m.leadtimedays, actiontype = m.actiontype,
                   repeateverydays = m.repeateverydays,
                   sortorder = m.n, isactive = TRUE, updatedat = (now() at time zone 'utc')
            WHERE  x.milestoneid = m.milestoneid;
            v_mid := m.milestoneid;
        END IF;
        v_keep := v_keep || v_mid;
    END LOOP;

    -- Milestones dropped from the list.
    UPDATE poultrylifecyclemilestones x SET isactive = FALSE, updatedat = (now() at time zone 'utc')
    WHERE  x.templateid = v_id AND NOT (x.milestoneid = ANY (v_keep))
      AND  EXISTS (SELECT 1 FROM poultrylifecycletasks k WHERE k.milestoneid = x.milestoneid);
    DELETE FROM poultrylifecyclemilestones x
    WHERE  x.templateid = v_id AND NOT (x.milestoneid = ANY (v_keep))
      AND  NOT EXISTS (SELECT 1 FROM poultrylifecycletasks k WHERE k.milestoneid = x.milestoneid);

    RETURN v_id;
END $f$;

CREATE FUNCTION public.sppoultrylifecycletemplate_getall(p_farmid text)
RETURNS TABLE(templateid integer, name text, breed text, description text, isactive boolean,
              milestonecount integer, assignedbatches integer, assignedflocks integer,
              createdby text, createdat timestamp, updatedby text, updatedat timestamp,
              isdefault boolean)
LANGUAGE sql STABLE AS $f$
    SELECT t.templateid, t.name, t.breed, t.description, t.isactive,
           (SELECT COUNT(*) FROM poultrylifecyclemilestones m WHERE m.templateid = t.templateid AND m.isactive)::int,
           (SELECT COUNT(*) FROM poultrylifecycleassignments a WHERE a.templateid = t.templateid AND a.isactive AND a.batchid IS NOT NULL)::int,
           (SELECT COUNT(*) FROM poultrylifecycleassignments a WHERE a.templateid = t.templateid AND a.isactive AND a.flockid IS NOT NULL)::int,
           t.createdby, t.createdat, t.updatedby, t.updatedat,
           (t.defaultkey IS NOT NULL)
    FROM   poultrylifecycletemplates t
    WHERE  t.farmid = p_farmid
    ORDER  BY t.isactive DESC, lower(t.name);
$f$;

CREATE FUNCTION public.sppoultrylifecyclemilestone_getall(p_farmid text, p_templateid integer)
RETURNS TABLE(milestoneid integer, templateid integer, ageunit text, agevalue integer, agedays integer,
              title text, description text, category text, leadtimedays integer, actiontype text,
              sortorder integer, repeateverydays integer)
LANGUAGE sql STABLE AS $f$
    SELECT m.milestoneid, m.templateid, m.ageunit, m.agevalue, m.agedays, m.title, m.description,
           m.category, m.leadtimedays, m.actiontype, m.sortorder, m.repeateverydays
    FROM   poultrylifecyclemilestones m
    WHERE  m.farmid = p_farmid AND m.templateid = p_templateid AND m.isactive
    ORDER  BY m.agedays, m.sortorder, m.milestoneid;
$f$;

-- ------------------------------------------------------- 6. task status ------
-- 347's rules, per occurrence. p_occurrence is last so 347's positional calls
-- (one-off milestones, occurrence 0) still work.
CREATE FUNCTION public.sppoultrylifecycle_settaskstatus(
    p_farmid      text,
    p_flockid     integer,
    p_milestoneid integer,
    p_status      text,
    p_note        text    DEFAULT NULL,
    p_actor       text    DEFAULT NULL,
    p_occurrence  integer DEFAULT 0)
RETURNS integer
LANGUAGE plpgsql AS $f$
DECLARE
    s       record;
    v_task  integer;
    v_note  text := NULLIF(btrim(p_note), '');
    v_occ   integer := COALESCE(p_occurrence, 0);
BEGIN
    IF p_status NOT IN ('Completed', 'Skipped', 'Open') THEN
        RAISE EXCEPTION 'Status must be Completed, Skipped or Open.';
    END IF;

    SELECT * INTO s FROM fnpoultrylifecycle_schedule(p_farmid) x
    WHERE  x.flockid = p_flockid AND x.milestoneid = p_milestoneid AND x.occurrence = v_occ;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That task is not on this company''s lifecycle schedule (the flock may be closed, the plan unassigned, or a newer repeat has replaced it).';
    END IF;
    IF s.status = 'Scheduled' AND p_status <> 'Open' THEN
        RAISE EXCEPTION '"%" for % is not due yet -- it becomes a task on %.', s.title, s.flockname, s.visiblefrom;
    END IF;
    IF p_status = 'Skipped' AND v_note IS NULL THEN
        RAISE EXCEPTION 'Say why this task is being skipped.';
    END IF;
    IF p_status = 'Open' AND s.status NOT IN ('Completed', 'Skipped') THEN
        RAISE EXCEPTION 'This task is already open.';
    END IF;
    IF p_status = s.status THEN
        RAISE EXCEPTION 'This task is already %.', lower(p_status);
    END IF;

    INSERT INTO poultrylifecycletasks (farmid, flockid, milestoneid, occurrence, status, title, duedate, isestimated, note, actedby)
    VALUES (p_farmid, p_flockid, p_milestoneid, v_occ, p_status, s.title, s.duedate, s.isestimated, v_note, p_actor)
    ON CONFLICT (flockid, milestoneid, occurrence) DO UPDATE
       SET status = EXCLUDED.status, title = EXCLUDED.title, duedate = EXCLUDED.duedate,
           isestimated = EXCLUDED.isestimated, note = EXCLUDED.note, actedby = EXCLUDED.actedby,
           actedat = (now() at time zone 'utc')
    RETURNING taskid INTO v_task;

    INSERT INTO poultrylifecycletaskevents (farmid, taskid, flockid, milestoneid, occurrence, fromstatus, tostatus, note, actor)
    VALUES (p_farmid, v_task, p_flockid, p_milestoneid, v_occ, s.status, p_status, v_note, p_actor);

    RETURN v_task;
END $f$;

CREATE FUNCTION public.sppoultrylifecycle_taskhistory(p_farmid text, p_flockid integer,
                                                      p_milestoneid integer DEFAULT NULL,
                                                      p_occurrence integer DEFAULT NULL)
RETURNS TABLE(eventid bigint, flockid integer, milestoneid integer, title text,
              fromstatus text, tostatus text, note text, actor text, atutc timestamptz,
              occurrence integer)
LANGUAGE sql STABLE AS $f$
    SELECT e.eventid, e.flockid, e.milestoneid, k.title, e.fromstatus, e.tostatus, e.note, e.actor, e.atutc,
           e.occurrence
    FROM   poultrylifecycletaskevents e
    JOIN   poultrylifecycletasks k ON k.taskid = e.taskid
    WHERE  e.farmid = p_farmid AND e.flockid = p_flockid
      AND  (p_milestoneid IS NULL OR e.milestoneid = p_milestoneid)
      AND  (p_occurrence IS NULL OR e.occurrence = p_occurrence)
    ORDER  BY e.atutc DESC, e.eventid DESC;
$f$;

-- ------------------------------------------- 7. the national schedule plans --
CREATE FUNCTION public.sppoultrylifecycle_ensuredefaults(
    p_farmid text,
    p_actor  text    DEFAULT NULL,
    p_force  boolean DEFAULT false)
RETURNS TABLE(planscreated integer, alreadyapplied boolean)
LANGUAGE plpgsql AS $f$
DECLARE
    c_version constant integer := 1;
    c_note    constant text :=
        'From the Veterinary Services Directorate (Ghana) national vaccination schedule. Ages are the birds'' age '
        || 'from hatch. Schedules differ by area, disease pressure and vaccine brand -- confirm with your vet '
        || 'before you follow it, and edit the plan to match what your vet prescribes.';
    v_plans   integer := 0;
    v_id      integer;
    r         record;
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN
        RAISE EXCEPTION 'Company ID is required.';
    END IF;

    -- Two tabs opening the page at once must not both seed.
    PERFORM pg_advisory_xact_lock(hashtext('poultrylifecycledefaults:' || p_farmid));

    IF NOT COALESCE(p_force, false)
       AND EXISTS (SELECT 1 FROM poultrylifecycledefaultsapplied a WHERE a.farmid = p_farmid) THEN
        RETURN QUERY SELECT 0, true;
        RETURN;
    END IF;

    FOR r IN
        SELECT * FROM (VALUES
          ('vacc.gh.commercial', 'Ghana National Vaccination - Commercial Layers',
           'Vaccinations for commercial layers, week 1 to week 16, then a Newcastle booster every 3 months. '),
          ('vacc.gh.breeder',    'Ghana National Vaccination - Breeders',
           'Vaccinations for breeders, day 1 to week 42, then Newcastle + IBD every 3 months. ')
        ) AS t(dkey, name, lead)
    LOOP
        IF EXISTS (SELECT 1 FROM poultrylifecycletemplates t
                   WHERE t.farmid = p_farmid
                     AND (t.defaultkey = r.dkey OR lower(btrim(t.name)) = lower(r.name))) THEN
            CONTINUE;
        END IF;

        INSERT INTO poultrylifecycletemplates (farmid, name, breed, description, isactive, createdby, defaultkey)
        VALUES (p_farmid, r.name, NULL, r.lead || c_note, TRUE, p_actor, r.dkey)
        RETURNING templateid INTO v_id;

        INSERT INTO poultrylifecyclemilestones
            (templateid, farmid, ageunit, agevalue, title, description, category, leadtimedays, actiontype, sortorder, repeateverydays)
        SELECT v_id, p_farmid, 'Day', x.d, x.title, x.descr, 'Vaccination', x.lead, 'MedicationCampaign', x.n, x.every
        FROM (VALUES
          -- commercial layers -----------------------------------------------------------------
          ('vacc.gh.commercial',  1,   7, 'Gumboro Intermediate',
           'Week 1. Skip it if the parent stock was given Gumboro Maternalin vaccine -- ask your chick supplier.', 3, NULL::integer),
          ('vacc.gh.commercial',  2,  14, 'HB1 (Newcastle)', 'Week 2.', 3, NULL),
          ('vacc.gh.commercial',  3,  21, 'Gumboro Intermediate Plus', 'Week 3.', 3, NULL),
          ('vacc.gh.commercial',  4,  28, 'LaSota (Newcastle)', 'Week 4.', 3, NULL),
          ('vacc.gh.commercial',  5,  35, 'Gumboro Intermediate / Plus',
           'Week 5. Use Intermediate Plus if Gumboro is common in your area.', 3, NULL),
          ('vacc.gh.commercial',  6,  53, '1st Fowl Pox', 'Week 8.', 3, NULL),
          ('vacc.gh.commercial',  7,  70, 'LaSota (Newcastle)', 'Week 10.', 3, NULL),
          ('vacc.gh.commercial',  8,  84, '2nd Fowl Pox', 'Week 12.', 3, NULL),
          ('vacc.gh.commercial',  9, 112, '3rd Newcastle Vaccine', 'Week 16.', 3, NULL),
          ('vacc.gh.commercial', 10, 203, 'Newcastle booster (LaSota / I-2 / inactivated)',
           'Every 3 months after week 16, for as long as the flock is kept. Use LaSota, I-2 or an inactivated Newcastle vaccine.', 7, 91),
          -- breeders -------------------------------------------------------------------------
          ('vacc.gh.breeder',  1,   1, 'Marek''s Vaccine',
           'Day 1. Usually given at the hatchery -- complete it if the chicks arrived vaccinated.', 0, NULL),
          ('vacc.gh.breeder',  2,   7, 'Gumboro Intermediate',
           'Week 1. Skip it if the parent stock was given Gumboro Maternalin vaccine -- ask your chick supplier.', 3, NULL),
          ('vacc.gh.breeder',  3,  14, 'HB1 (Newcastle)', 'Week 2.', 3, NULL),
          ('vacc.gh.breeder',  4,  21, 'Gumboro Intermediate Plus', 'Week 3.', 3, NULL),
          ('vacc.gh.breeder',  5,  28, 'LaSota (Newcastle)', 'Week 4.', 3, NULL),
          ('vacc.gh.breeder',  6,  35, 'Gumboro Intermediate / Plus',
           'Week 5. Use Intermediate Plus if Gumboro is common in your area.', 3, NULL),
          ('vacc.gh.breeder',  7,  53, '1st Fowl Pox', 'Week 8.', 3, NULL),
          ('vacc.gh.breeder',  8,  70, 'LaSota (Newcastle)', 'Week 10.', 3, NULL),
          ('vacc.gh.breeder',  9,  84, '2nd Fowl Pox', 'Week 12.', 3, NULL),
          ('vacc.gh.breeder', 10, 112, '3rd Newcastle Vaccine + IBD Maternal', 'Week 16.', 3, NULL),
          ('vacc.gh.breeder', 11, 294, 'Newcastle Vaccine + IBD Maternal',
           'Week 42, then every 3 months for as long as the flock is kept.', 7, 91)
        ) AS x(dkey, n, d, title, descr, lead, every)
        WHERE x.dkey = r.dkey;

        v_plans := v_plans + 1;
    END LOOP;

    INSERT INTO poultrylifecycledefaultsapplied (farmid, version, appliedat, appliedby)
    VALUES (p_farmid, c_version, (now() at time zone 'utc'), p_actor)
    ON CONFLICT (farmid) DO UPDATE
        SET version = EXCLUDED.version, appliedat = EXCLUDED.appliedat, appliedby = EXCLUDED.appliedby;

    RETURN QUERY SELECT v_plans, false;
END $f$;

-- ---------------------------------------------------------------- 8. self-test --
DO $selftest$
DECLARE
    f   constant text := '__selftest_387__';
    res record;
    n   integer;
BEGIN
    SELECT * INTO res FROM sppoultrylifecycle_ensuredefaults(f, 'selftest');
    IF res.planscreated <> 2 OR res.alreadyapplied THEN
        RAISE EXCEPTION '387 self-test: first run made % plans (want 2)', res.planscreated;
    END IF;
    SELECT count(*) INTO n FROM poultrylifecyclemilestones WHERE farmid = f;
    IF n <> 21 THEN RAISE EXCEPTION '387 self-test: % milestones (want 21)', n; END IF;
    SELECT count(*) INTO n FROM poultrylifecyclemilestones WHERE farmid = f AND repeateverydays = 91;
    IF n <> 2 THEN RAISE EXCEPTION '387 self-test: % repeating milestones (want 2)', n; END IF;
    SELECT count(*) INTO n FROM sppoultrylifecycletemplate_getall(f) g WHERE g.isdefault;
    IF n <> 2 THEN RAISE EXCEPTION '387 self-test: % plans flagged built-in (want 2)', n; END IF;

    SELECT * INTO res FROM sppoultrylifecycle_ensuredefaults(f, 'selftest');
    IF res.planscreated <> 0 OR NOT res.alreadyapplied THEN RAISE EXCEPTION '387 self-test: second run was not a no-op'; END IF;

    -- A deleted plan stays deleted until the farm asks for it back.
    DELETE FROM poultrylifecycletemplates WHERE farmid = f AND defaultkey = 'vacc.gh.breeder';
    SELECT * INTO res FROM sppoultrylifecycle_ensuredefaults(f, 'selftest');
    IF res.planscreated <> 0 THEN RAISE EXCEPTION '387 self-test: deleted plan came back without force'; END IF;
    SELECT * INTO res FROM sppoultrylifecycle_ensuredefaults(f, 'selftest', true);
    IF res.planscreated <> 1 THEN RAISE EXCEPTION '387 self-test: forced run made % plans (want 1)', res.planscreated; END IF;

    DELETE FROM poultrylifecycletemplates      WHERE farmid = f;   -- milestones cascade
    DELETE FROM poultrylifecycledefaultsapplied WHERE farmid = f;
    RAISE NOTICE '387 self-test passed';
END;
$selftest$;

COMMIT;
