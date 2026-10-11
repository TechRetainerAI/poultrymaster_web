-- =============================================================================
-- 347  Flock Lifecycle Assistant (poultry)
-- =============================================================================
--
-- WHAT THIS IS
-- ------------
-- A REMINDER system the farm configures itself. VisibilityCore ships NO
-- milestones: no week numbers, no treatments, no "layers should move at week
-- 16". A farm writes its own lifecycle templates ("Layer plan", "Broiler
-- plan" ...), each a list of milestones at an age it chooses, assigns a
-- template to a batch (its flocks inherit it) or to one flock, and the system
-- works out WHEN each milestone falls for each flock and reminds people.
--
-- Nothing here executes an operational transaction. A milestone may carry an
-- action LINK (flock details, house transfer, treatment records, production,
-- closeout); following it opens the ordinary page where a person does the
-- work, or decides not to.
--
-- THE MODEL
-- ---------
--   poultrylifecycletemplates    name, optional breed, description, active
--   poultrylifecyclemilestones   age (value + Day|Week), title, description,
--                                category, lead time, optional action type
--   poultrylifecycleassignments  template -> BATCH (flocks inherit) or FLOCK
--                                (overrides the batch's), plus the birds' age
--                                on the flock's start date
--   poultrylifecycletasks        ONE row per (flock, milestone), created the
--                                first time someone acts on it -- the schedule
--                                itself is derived, never stored
--   poultrylifecycletaskevents   append-only status history (trigger-enforced)
--
-- THE SCHEDULING CALCULATION (fnpoultrylifecycle_schedule)
-- --------------------------------------------------------
--   milestone age (days)  = agevalue            for unit Day
--                         = agevalue * 7        for unit Week
--   age at start (days)   = assignment.ageatstartdays (0 = arrived day-old)
--   due date              = flock.startdate + (milestone age - age at start)
--   due window end        = due date            for a Day milestone
--                         = due date + 6        for a Week milestone (the
--                           whole week the birds are that many weeks old)
--   visible from          = due date - leadtimedays
--   flock age today       = today - startdate + age at start
--   today                 = fncompany_businessdate(farm) -- the COMPANY's
--                           date in its own time zone, never the server's
--
--   status   Completed / Skipped   if a person said so (stored)
--            Scheduled             today <  visible from (not yet shown as a task)
--            Upcoming              visible from <= today < due date
--            Due                   due date <= today <= due window end
--            Overdue               today > due window end
--
-- A milestone younger than the birds were on arrival (milestone age < age at
-- start) is not a task for that flock: it happened before the farm had them.
--
-- ESTIMATED DATES
-- ---------------
-- When Initial Farm Setup derived a flock's start date from an age someone
-- typed (poultryopeningflockposition.startdateestimated), every date computed
-- from it is an estimate, and every row says so (isestimated).
--
-- WHICH FLOCKS
-- ------------
-- Open flocks only: not deleted, not closed (338), arrived, with a start
-- date. A closed flock's acted-on tasks stay in the tables and in the history;
-- its unfinished reminders simply stop.
--
-- PERMISSIONS: poultry.lifecycle.{view,create,edit,delete}, seeded from the
-- poultry.flocks grants (view->view, create->create, edit->edit,
-- delete->delete). Completing or skipping a task is `edit` (PUT).
--
-- Idempotent. PostgreSQL.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------- 1. tables --
CREATE TABLE IF NOT EXISTS public.poultrylifecycletemplates (
    templateid    serial PRIMARY KEY,
    farmid        text      NOT NULL,
    name          text      NOT NULL,
    breed         text      NULL,      -- optional: which breed it is written for
    description   text      NULL,
    isactive      boolean   NOT NULL DEFAULT TRUE,
    createdby     text      NULL,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby     text      NULL,
    updatedat     timestamp NULL,
    CONSTRAINT ck_poultrylifecycletemplates_name CHECK (btrim(name) <> '')
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrylifecycletemplates_name
    ON public.poultrylifecycletemplates (farmid, lower(btrim(name)));

CREATE TABLE IF NOT EXISTS public.poultrylifecyclemilestones (
    milestoneid   serial PRIMARY KEY,
    templateid    integer   NOT NULL REFERENCES public.poultrylifecycletemplates (templateid) ON DELETE CASCADE,
    farmid        text      NOT NULL,
    ageunit       text      NOT NULL DEFAULT 'Week',
    agevalue      integer   NOT NULL,
    agedays       integer   GENERATED ALWAYS AS (agevalue * CASE WHEN ageunit = 'Week' THEN 7 ELSE 1 END) STORED,
    title         text      NOT NULL,
    description   text      NULL,
    category      text      NULL,
    leadtimedays  integer   NOT NULL DEFAULT 3,
    actiontype    text      NULL,
    sortorder     integer   NOT NULL DEFAULT 0,
    isactive      boolean   NOT NULL DEFAULT TRUE,
    createdat     timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedat     timestamp NULL,
    CONSTRAINT ck_poultrylifecyclemilestones_unit   CHECK (ageunit IN ('Day', 'Week')),
    CONSTRAINT ck_poultrylifecyclemilestones_age    CHECK (agevalue >= 0 AND agevalue <= 5000),
    CONSTRAINT ck_poultrylifecyclemilestones_lead   CHECK (leadtimedays >= 0 AND leadtimedays <= 365),
    CONSTRAINT ck_poultrylifecyclemilestones_title  CHECK (btrim(title) <> ''),
    CONSTRAINT ck_poultrylifecyclemilestones_action CHECK (actiontype IS NULL OR actiontype IN
        ('FlockDetails', 'FlockTransfer', 'MedicationCampaign', 'Production', 'Closeout'))
);
CREATE INDEX IF NOT EXISTS ix_poultrylifecyclemilestones_template
    ON public.poultrylifecyclemilestones (templateid);

CREATE TABLE IF NOT EXISTS public.poultrylifecycleassignments (
    assignmentid    serial PRIMARY KEY,
    farmid          text      NOT NULL,
    templateid      integer   NOT NULL REFERENCES public.poultrylifecycletemplates (templateid),
    batchid         integer   NULL,
    flockid         integer   NULL,
    -- The birds' age, in days, on the flock's start date. 0 = arrived day-old;
    -- point-of-lay pullets bought at 16 weeks would be 112.
    ageatstartdays  integer   NOT NULL DEFAULT 0,
    isactive        boolean   NOT NULL DEFAULT TRUE,
    assignedby      text      NULL,
    assignedat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    endedby         text      NULL,
    endedat         timestamp NULL,
    CONSTRAINT ck_poultrylifecycleassignments_target CHECK ((batchid IS NULL) <> (flockid IS NULL)),
    CONSTRAINT ck_poultrylifecycleassignments_age    CHECK (ageatstartdays >= 0 AND ageatstartdays <= 5000)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrylifecycleassignments_batch
    ON public.poultrylifecycleassignments (farmid, batchid) WHERE isactive AND batchid IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrylifecycleassignments_flock
    ON public.poultrylifecycleassignments (farmid, flockid) WHERE isactive AND flockid IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.poultrylifecycletasks (
    taskid        serial PRIMARY KEY,
    farmid        text      NOT NULL,
    flockid       integer   NOT NULL,
    milestoneid   integer   NOT NULL REFERENCES public.poultrylifecyclemilestones (milestoneid),
    status        text      NOT NULL,
    -- What the task WAS when someone acted on it, so a later edit to the
    -- milestone cannot rewrite what was completed.
    title         text      NOT NULL,
    duedate       date      NOT NULL,
    isestimated   boolean   NOT NULL DEFAULT FALSE,
    note          text      NULL,
    actedby       text      NULL,
    actedat       timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    CONSTRAINT ck_poultrylifecycletasks_status CHECK (status IN ('Open', 'Completed', 'Skipped')),
    CONSTRAINT ux_poultrylifecycletasks_flockmilestone UNIQUE (flockid, milestoneid)
);
CREATE INDEX IF NOT EXISTS ix_poultrylifecycletasks_farm ON public.poultrylifecycletasks (farmid);

CREATE TABLE IF NOT EXISTS public.poultrylifecycletaskevents (
    eventid       bigserial PRIMARY KEY,
    farmid        text        NOT NULL,
    taskid        integer     NOT NULL REFERENCES public.poultrylifecycletasks (taskid),
    flockid       integer     NOT NULL,
    milestoneid   integer     NOT NULL,
    fromstatus    text        NOT NULL,   -- the DERIVED status at the time (Upcoming/Due/Overdue/...)
    tostatus      text        NOT NULL,
    note          text        NULL,
    actor         text        NULL,
    atutc         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_poultrylifecycletaskevents_task ON public.poultrylifecycletaskevents (taskid);

CREATE OR REPLACE FUNCTION public.trg_poultrylifecycletaskevents_appendonly_fn()
RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
    RAISE EXCEPTION 'Lifecycle task history is append-only.';
END $f$;
DROP TRIGGER IF EXISTS trg_poultrylifecycletaskevents_appendonly ON public.poultrylifecycletaskevents;
CREATE TRIGGER trg_poultrylifecycletaskevents_appendonly
    BEFORE UPDATE OR DELETE ON public.poultrylifecycletaskevents
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultrylifecycletaskevents_appendonly_fn();

-- --------------------------------------------- 2. drop old overloads by name --
DO $d$ DECLARE r record; BEGIN
    FOR r IN SELECT p.oid::regprocedure::text AS sig FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public'
               AND p.proname IN ('fnpoultrylifecycle_schedule', 'sppoultrylifecycle_tasks',
                                 'sppoultrylifecycle_summary', 'sppoultrylifecycletemplate_save',
                                 'sppoultrylifecycletemplate_getall', 'sppoultrylifecyclemilestone_getall',
                                 'sppoultrylifecycletemplate_delete', 'sppoultrylifecycle_assign',
                                 'sppoultrylifecycle_unassign', 'sppoultrylifecycleassignment_getall',
                                 'sppoultrylifecycle_settaskstatus', 'sppoultrylifecycle_taskhistory')
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
              taskid integer, status text, note text, actedby text, actedat timestamp, today date)
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
    s AS (
        SELECT fl.flockid, fl.name::text AS flockname, fl.batchid, b.batchcode::text AS batchcode,
               fl.houseid, COALESCE(NULLIF(btrim(fl.breed), ''), b.breed)::text AS breed,
               fl.startdate, COALESCE(fl.active, TRUE) AS flockactive,
               COALESCE(op.startdateestimated, FALSE) AS isestimated,
               fl.a_id, fl.a_via, tp.templateid, tp.name AS templatename, tp.breed AS templatebreed,
               fl.a_age,
               ((SELECT today FROM t) - fl.startdate + fl.a_age)::integer AS currentagedays,
               m.milestoneid, m.title, m.description, m.category, m.ageunit, m.agevalue, m.agedays,
               m.leadtimedays, m.actiontype, m.sortorder,
               (fl.startdate + (m.agedays - fl.a_age))::date AS duedate,
               (fl.startdate + (m.agedays - fl.a_age)
                  + CASE WHEN m.ageunit = 'Week' THEN 6 ELSE 0 END)::date AS duewindowend,
               (fl.startdate + (m.agedays - fl.a_age) - m.leadtimedays)::date AS visiblefrom,
               tk.taskid, tk.status AS storedstatus, tk.note, tk.actedby, tk.actedat
        FROM   fl
        JOIN   poultrylifecycletemplates tp ON tp.templateid = fl.a_template AND tp.farmid = p_farmid
        JOIN   poultrylifecyclemilestones m ON m.templateid = tp.templateid AND m.isactive
        LEFT   JOIN mainflockbatch b ON b.batchid = fl.batchid AND b.farmid = fl.farmid
        LEFT   JOIN LATERAL (
                   SELECT bool_or(o.startdateestimated) AS startdateestimated
                   FROM   poultryopeningflockposition o
                   WHERE  o.flockid = fl.flockid AND o.farmid = p_farmid) op ON TRUE
        LEFT   JOIN poultrylifecycletasks tk ON tk.flockid = fl.flockid AND tk.milestoneid = m.milestoneid
        WHERE  fl.a_template IS NOT NULL
          AND  m.agedays >= fl.a_age          -- before the birds arrived: not this farm's task
    )
    SELECT s.flockid, s.flockname, s.batchid, s.batchcode, s.houseid, s.breed, s.startdate,
           s.flockactive, s.isestimated, s.a_id, s.a_via, s.templateid, s.templatename::text,
           s.templatebreed::text, s.a_age, s.currentagedays,
           s.milestoneid, s.title::text, s.description::text, s.category::text, s.ageunit::text,
           s.agevalue, s.agedays, s.leadtimedays, s.actiontype::text,
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
           (SELECT today FROM t)
    FROM   s
    ORDER  BY s.duedate, s.flockname, s.sortorder, s.milestoneid;
$f$;

-- ------------------------------------------------------------ 4. task reads ----
-- p_view: 'Open'      Upcoming + Due + Overdue (what needs attention)
--         'Upcoming' | 'Due' | 'Overdue' | 'Completed' | 'Skipped' | 'Scheduled'
--         'All'       everything for the open flocks
CREATE FUNCTION public.sppoultrylifecycle_tasks(p_farmid text, p_view text DEFAULT 'Open', p_flockid integer DEFAULT NULL)
RETURNS TABLE(flockid integer, flockname text, batchid integer, batchcode text, houseid integer,
              breed text, flockstartdate date, flockactive boolean, isestimated boolean,
              assignmentid integer, assignedvia text, templateid integer, templatename text,
              templatebreed text, ageatstartdays integer, currentagedays integer,
              milestoneid integer, title text, description text, category text,
              ageunit text, agevalue integer, agedays integer, leadtimedays integer, actiontype text,
              duedate date, duewindowend date, visiblefrom date, daysuntildue integer,
              taskid integer, status text, note text, actedby text, actedat timestamp, today date)
LANGUAGE sql STABLE AS $f$
    SELECT s.*
    FROM   fnpoultrylifecycle_schedule(p_farmid) s
    WHERE  (p_flockid IS NULL OR s.flockid = p_flockid)
      AND  (COALESCE(p_view, 'Open') = 'All'
            OR (p_view = 'Open' AND s.status IN ('Upcoming', 'Due', 'Overdue'))
            OR s.status = p_view)
    ORDER  BY CASE s.status WHEN 'Overdue' THEN 0 WHEN 'Due' THEN 1 WHEN 'Upcoming' THEN 2
                            WHEN 'Scheduled' THEN 3 ELSE 4 END,
              s.duedate, s.flockname, s.milestoneid;
$f$;

-- What Business Office shows on a company card / My Tasks header.
CREATE FUNCTION public.sppoultrylifecycle_summary(p_farmid text)
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
-- Saves the template AND its milestone list in one call. Milestones carry
-- their id when they already exist; a milestone left out of the list is
-- deleted, or -- if a task was already acted on for it -- deactivated, so the
-- history keeps pointing at something real.
CREATE FUNCTION public.sppoultrylifecycletemplate_save(
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
               NULLIF(btrim(e.v ->> 'actiontype'), '') AS actiontype
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
               updatedat = (now() at time zone 'utc')
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
               NULLIF(btrim(e.v ->> 'actiontype'), '') AS actiontype
        FROM   jsonb_array_elements(p_milestones) WITH ORDINALITY AS e(v, n)
    LOOP
        IF m.milestoneid IS NULL THEN
            INSERT INTO poultrylifecyclemilestones
                (templateid, farmid, ageunit, agevalue, title, description, category, leadtimedays, actiontype, sortorder)
            VALUES (v_id, p_farmid, m.ageunit, m.agevalue, m.title, m.description, m.category,
                    m.leadtimedays, m.actiontype, m.n)
            RETURNING milestoneid INTO v_mid;
        ELSE
            UPDATE poultrylifecyclemilestones x
            SET    ageunit = m.ageunit, agevalue = m.agevalue, title = m.title, description = m.description,
                   category = m.category, leadtimedays = m.leadtimedays, actiontype = m.actiontype,
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
              createdby text, createdat timestamp, updatedby text, updatedat timestamp)
LANGUAGE sql STABLE AS $f$
    SELECT t.templateid, t.name, t.breed, t.description, t.isactive,
           (SELECT COUNT(*) FROM poultrylifecyclemilestones m WHERE m.templateid = t.templateid AND m.isactive)::int,
           (SELECT COUNT(*) FROM poultrylifecycleassignments a WHERE a.templateid = t.templateid AND a.isactive AND a.batchid IS NOT NULL)::int,
           (SELECT COUNT(*) FROM poultrylifecycleassignments a WHERE a.templateid = t.templateid AND a.isactive AND a.flockid IS NOT NULL)::int,
           t.createdby, t.createdat, t.updatedby, t.updatedat
    FROM   poultrylifecycletemplates t
    WHERE  t.farmid = p_farmid
    ORDER  BY t.isactive DESC, lower(t.name);
$f$;

CREATE FUNCTION public.sppoultrylifecyclemilestone_getall(p_farmid text, p_templateid integer)
RETURNS TABLE(milestoneid integer, templateid integer, ageunit text, agevalue integer, agedays integer,
              title text, description text, category text, leadtimedays integer, actiontype text,
              sortorder integer)
LANGUAGE sql STABLE AS $f$
    SELECT m.milestoneid, m.templateid, m.ageunit, m.agevalue, m.agedays, m.title, m.description,
           m.category, m.leadtimedays, m.actiontype, m.sortorder
    FROM   poultrylifecyclemilestones m
    WHERE  m.farmid = p_farmid AND m.templateid = p_templateid AND m.isactive
    ORDER  BY m.agedays, m.sortorder, m.milestoneid;
$f$;

-- Deleting a plan that is in use is refused; one with history is retired
-- (isactive = false) rather than deleted. Returns 'Deleted' or 'Retired'.
CREATE FUNCTION public.sppoultrylifecycletemplate_delete(p_farmid text, p_templateid integer, p_actor text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql AS $f$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM poultrylifecycletemplates t WHERE t.templateid = p_templateid AND t.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Lifecycle plan not found for this company.';
    END IF;
    IF EXISTS (SELECT 1 FROM poultrylifecycleassignments a WHERE a.templateid = p_templateid AND a.isactive) THEN
        RAISE EXCEPTION 'This plan is still assigned to a batch or flock. Remove those assignments first.';
    END IF;
    IF EXISTS (SELECT 1 FROM poultrylifecycleassignments a WHERE a.templateid = p_templateid)
       OR EXISTS (SELECT 1 FROM poultrylifecycletasks k
                  JOIN poultrylifecyclemilestones m ON m.milestoneid = k.milestoneid
                  WHERE m.templateid = p_templateid) THEN
        UPDATE poultrylifecycletemplates t SET isactive = FALSE, updatedby = p_actor,
               updatedat = (now() at time zone 'utc')
        WHERE  t.templateid = p_templateid;
        RETURN 'Retired';
    END IF;
    DELETE FROM poultrylifecycletemplates t WHERE t.templateid = p_templateid AND t.farmid = p_farmid;
    RETURN 'Deleted';
END $f$;

-- --------------------------------------------------------- 6. assignment ------
-- Exactly one of batch / flock. Re-assigning a target replaces its current
-- plan (the old assignment is ended, kept for history).
CREATE FUNCTION public.sppoultrylifecycle_assign(
    p_farmid         text,
    p_templateid     integer,
    p_batchid        integer,
    p_flockid        integer,
    p_ageatstartdays integer DEFAULT 0,
    p_actor          text    DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql AS $f$
DECLARE
    v_id    integer;
    v_type  text;
BEGIN
    IF (p_batchid IS NULL) = (p_flockid IS NULL) THEN
        RAISE EXCEPTION 'Assign the plan to either a batch or a flock.';
    END IF;
    v_type := spfarm_gettype(p_farmid);
    IF v_type IS NOT NULL AND btrim(v_type) <> '' AND lower(v_type) <> 'poultry' THEN
        RAISE EXCEPTION 'Lifecycle plans are only available for Poultry companies (this company is %).', v_type;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM poultrylifecycletemplates t
                   WHERE t.templateid = p_templateid AND t.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Lifecycle plan not found for this company.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM poultrylifecycletemplates t
                   WHERE t.templateid = p_templateid AND t.farmid = p_farmid AND t.isactive) THEN
        RAISE EXCEPTION 'This lifecycle plan is inactive. Reactivate it before assigning it.';
    END IF;
    IF COALESCE(p_ageatstartdays, 0) < 0 OR COALESCE(p_ageatstartdays, 0) > 5000 THEN
        RAISE EXCEPTION 'Age at start must be between 0 and 5000 days.';
    END IF;
    IF p_batchid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM mainflockbatch b WHERE b.batchid = p_batchid AND b.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Batch not found for this company.';
    END IF;
    IF p_flockid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM flock f WHERE f.flockid = p_flockid AND f.farmid = p_farmid
                                                                     AND NOT COALESCE(f.isdeleted, FALSE)) THEN
        RAISE EXCEPTION 'Flock not found for this company.';
    END IF;

    UPDATE poultrylifecycleassignments a
    SET    isactive = FALSE, endedby = p_actor, endedat = (now() at time zone 'utc')
    WHERE  a.farmid = p_farmid AND a.isactive
      AND  ((p_batchid IS NOT NULL AND a.batchid = p_batchid) OR (p_flockid IS NOT NULL AND a.flockid = p_flockid));

    INSERT INTO poultrylifecycleassignments (farmid, templateid, batchid, flockid, ageatstartdays, assignedby)
    VALUES (p_farmid, p_templateid, p_batchid, p_flockid, COALESCE(p_ageatstartdays, 0), p_actor)
    RETURNING assignmentid INTO v_id;
    RETURN v_id;
END $f$;

CREATE FUNCTION public.sppoultrylifecycle_unassign(p_farmid text, p_assignmentid integer, p_actor text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql AS $f$
BEGIN
    UPDATE poultrylifecycleassignments a
    SET    isactive = FALSE, endedby = p_actor, endedat = (now() at time zone 'utc')
    WHERE  a.assignmentid = p_assignmentid AND a.farmid = p_farmid AND a.isactive;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active assignment not found for this company.'; END IF;
END $f$;

CREATE FUNCTION public.sppoultrylifecycleassignment_getall(p_farmid text)
RETURNS TABLE(assignmentid integer, templateid integer, templatename text, templatebreed text,
              batchid integer, batchcode text, batchname text, flockid integer, flockname text,
              targetbreed text, ageatstartdays integer, flockcount integer, breedmismatch boolean,
              assignedby text, assignedat timestamp)
LANGUAGE sql STABLE AS $f$
    SELECT a.assignmentid, a.templateid, t.name, t.breed,
           a.batchid, b.batchcode::text, b.batchname::text, a.flockid, f.name::text,
           COALESCE(NULLIF(btrim(f.breed), ''), b.breed)::text,
           a.ageatstartdays,
           (CASE WHEN a.flockid IS NOT NULL THEN 1
                 ELSE (SELECT COUNT(*) FROM flock x WHERE x.batchid = a.batchid AND x.farmid = a.farmid
                         AND NOT COALESCE(x.isdeleted, FALSE) AND x.closeddate IS NULL) END)::int,
           (t.breed IS NOT NULL AND COALESCE(NULLIF(btrim(f.breed), ''), b.breed) IS NOT NULL
            AND lower(btrim(t.breed)) <> lower(btrim(COALESCE(NULLIF(btrim(f.breed), ''), b.breed)))),
           a.assignedby, a.assignedat
    FROM   poultrylifecycleassignments a
    JOIN   poultrylifecycletemplates t ON t.templateid = a.templateid
    LEFT   JOIN mainflockbatch b ON b.batchid = a.batchid AND b.farmid = a.farmid
    LEFT   JOIN flock f          ON f.flockid = a.flockid AND f.farmid = a.farmid
    WHERE  a.farmid = p_farmid AND a.isactive
    ORDER  BY COALESCE(b.batchcode, f.name);
$f$;

-- ------------------------------------------------------- 7. task status ------
-- 'Completed' | 'Skipped' (a reason is required) | 'Open' (undo either).
CREATE FUNCTION public.sppoultrylifecycle_settaskstatus(
    p_farmid      text,
    p_flockid     integer,
    p_milestoneid integer,
    p_status      text,
    p_note        text DEFAULT NULL,
    p_actor       text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql AS $f$
DECLARE
    s       record;
    v_task  integer;
    v_note  text := NULLIF(btrim(p_note), '');
BEGIN
    IF p_status NOT IN ('Completed', 'Skipped', 'Open') THEN
        RAISE EXCEPTION 'Status must be Completed, Skipped or Open.';
    END IF;

    SELECT * INTO s FROM fnpoultrylifecycle_schedule(p_farmid) x
    WHERE  x.flockid = p_flockid AND x.milestoneid = p_milestoneid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That task is not on this company''s lifecycle schedule (the flock may be closed or the plan unassigned).';
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

    INSERT INTO poultrylifecycletasks (farmid, flockid, milestoneid, status, title, duedate, isestimated, note, actedby)
    VALUES (p_farmid, p_flockid, p_milestoneid, p_status, s.title, s.duedate, s.isestimated, v_note, p_actor)
    ON CONFLICT (flockid, milestoneid) DO UPDATE
       SET status = EXCLUDED.status, title = EXCLUDED.title, duedate = EXCLUDED.duedate,
           isestimated = EXCLUDED.isestimated, note = EXCLUDED.note, actedby = EXCLUDED.actedby,
           actedat = (now() at time zone 'utc')
    RETURNING taskid INTO v_task;

    INSERT INTO poultrylifecycletaskevents (farmid, taskid, flockid, milestoneid, fromstatus, tostatus, note, actor)
    VALUES (p_farmid, v_task, p_flockid, p_milestoneid, s.status, p_status, v_note, p_actor);

    RETURN v_task;
END $f$;

CREATE FUNCTION public.sppoultrylifecycle_taskhistory(p_farmid text, p_flockid integer, p_milestoneid integer DEFAULT NULL)
RETURNS TABLE(eventid bigint, flockid integer, milestoneid integer, title text,
              fromstatus text, tostatus text, note text, actor text, atutc timestamptz)
LANGUAGE sql STABLE AS $f$
    SELECT e.eventid, e.flockid, e.milestoneid, k.title, e.fromstatus, e.tostatus, e.note, e.actor, e.atutc
    FROM   poultrylifecycletaskevents e
    JOIN   poultrylifecycletasks k ON k.taskid = e.taskid
    WHERE  e.farmid = p_farmid AND e.flockid = p_flockid
      AND  (p_milestoneid IS NULL OR e.milestoneid = p_milestoneid)
    ORDER  BY e.atutc DESC, e.eventid DESC;
$f$;

-- ---------------------------------------------------------- 8. permissions ----
DO $iam$
DECLARE
    v_keys integer := 0; v_roles integer := 0; v_users integer := 0;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '347: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    INSERT INTO iampermissions (permissionkey, module, resource, action, permissiongroup, resourcelabel,
                                description, companytype, isdangerous, sortorder)
    SELECT 'poultry.lifecycle.' || a.action, 'poultry', 'lifecycle', a.action, 'Flock & Birds', 'Flock Lifecycle',
           'Farm-defined lifecycle plans and the reminders they raise for each flock. Edit covers '
           || 'completing or skipping a reminder; create covers writing plans and assigning them.',
           'Poultry', a.action = 'delete', 13
    FROM (VALUES ('view'), ('create'), ('edit'), ('delete')) AS a(action)
    ON CONFLICT (permissionkey) DO NOTHING;
    GET DIAGNOSTICS v_keys = ROW_COUNT;

    IF to_regclass('public.iamrolepermissions') IS NOT NULL THEN
        INSERT INTO iamrolepermissions (roleid, permissionkey)
        SELECT rp.roleid, m.new_key
        FROM   iamrolepermissions rp
        JOIN   (VALUES ('poultry.flocks.view',   'poultry.lifecycle.view'),
                       ('poultry.flocks.create', 'poultry.lifecycle.create'),
                       ('poultry.flocks.edit',   'poultry.lifecycle.edit'),
                       ('poultry.flocks.delete', 'poultry.lifecycle.delete')) AS m(old_key, new_key)
               ON m.old_key = rp.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
        ON CONFLICT (roleid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_roles = ROW_COUNT;
    END IF;

    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        INSERT INTO iamuserpermissions (userid, farmid, permissionkey, effect, reason, grantedby, grantedat)
        SELECT up.userid, up.farmid, m.new_key, up.effect,
               'Carried over from ' || up.permissionkey || ' by migration 347', up.grantedby, (now() at time zone 'utc')
        FROM   iamuserpermissions up
        JOIN   (VALUES ('poultry.flocks.view',   'poultry.lifecycle.view'),
                       ('poultry.flocks.create', 'poultry.lifecycle.create'),
                       ('poultry.flocks.edit',   'poultry.lifecycle.edit'),
                       ('poultry.flocks.delete', 'poultry.lifecycle.delete')) AS m(old_key, new_key)
               ON m.old_key = up.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
          AND  (up.expiresat IS NULL OR up.expiresat > (now() at time zone 'utc'))
        ON CONFLICT (userid, farmid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_users = ROW_COUNT;
    END IF;

    RAISE NOTICE '347: % catalog key(s), % role grant(s), % user grant(s) added.', v_keys, v_roles, v_users;
END
$iam$;

COMMIT;
