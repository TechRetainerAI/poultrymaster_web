-- =============================================================================
-- 332_PoultryProductionCompleteness.postgres.sql
--
-- Purpose
-- -------
-- The first deterministic check of the Missing Activity Detector: "which flocks
-- that were expected to report production on this business date have not?"
--
-- DERIVED, NOT STORED
-- ===================
-- Nothing here writes a row. "20 eligible flocks, 17 recorded, 3 missing" is a
-- fact about data that already exists, so it is recomputed on every read. A
-- persisted task per missing flock would have to be created, de-duplicated and
-- closed again when the record arrives -- three ways to drift from the truth,
-- for no benefit. Persistence belongs only to things that need acknowledgement
-- or history (a future notification), and those can be built on top of this.
--
-- WHO IS EXPECTED TO REPORT (an "eligible" flock)
-- ===============================================
--   active = TRUE AND hasarrived = TRUE AND isdeleted = FALSE
-- which is the definition of a live flock used by the egg ledger (204), house
-- occupancy (327) and flock-eligibility.ts on the frontend. That excludes
-- closed / sold / culled / disposed flocks (all recorded as active = FALSE with
-- an inactivation reason -- there is no separate status column), flocks still
-- pending arrival, and deleted flocks.
--
-- A flock is expected from its EXPECTED-FROM date, the latest of:
--   * startdate                        -- a flock not yet started owes nothing
--   * the opening-position effective date (319), if the flock came through
--     Initial Farm Setup -- history before that date is summarised, not recorded
--   * the company-local day the flock was entered into the system -- a flock
--     created today with a start date last month is not "missing" 30 days of
--     records nobody could have entered
--
-- Eligibility is read from the flock's CURRENT state. There is no lifecycle
-- history table, so a flock closed today is not checked for yesterday either.
-- That errs toward silence, which is the right side to err on for an alert.
--
-- There is no per-flock "exclude from production" flag in this schema. The only
-- way to take a flock out of the expected set today is to make it inactive.
--
-- WHAT COUNTS AS DONE
-- ===================
-- Any productionrecords row for (farm, flock, date) -- regardless of sourcetype.
-- Individually entered records are 'ManualSingleFlock'; Batch Production Entry
-- writes the SAME table through spproductionrecord_insert when a batch is
-- posted ('BatchAllocation'). A batch that is saved but not yet posted has
-- produced no record, so its flocks are still outstanding -- they are reported
-- as AWAITING POSTING with the batch id, so the fix offered is "post that batch"
-- rather than "enter it again" (which spproductionbatchrecord_post would refuse
-- as a duplicate anyway).
--
-- productionrecords has NO unique constraint on (farm, flock, date) and real
-- duplicates exist. Every count below is per FLOCK, never per row, so a
-- duplicate cannot make 17 look like 18. recordcount is returned so the UI (or
-- a later "duplicate production" check) can surface them.
--
-- BUSINESS DATE
-- =============
-- The company's own day, from fncompany_timezone (298). p_asof exists so the
-- self-test can pin the clock; production callers leave it at now(). A date
-- after the company's today is refused: nothing can be missing from the future.
--
-- SEVERITY (deterministic)
-- ========================
-- Anchored on the farm's OWN egg-pick schedule (farmproductionsettings, 153 /
-- 248): the latest enabled pick time, defaulting to 16:00, the default 3rd pick.
--   * Critical     -- the business date is already over (a past date), or the
--                     flock has also missed an earlier day (daysmissing >= 2)
--   * Warning      -- today, and the last scheduled pick of the day has passed
--   * Information  -- today, and the farm is still inside its picking day
-- A complete flock has no severity. The summary takes the worst row.
--
-- PERFORMANCE
-- ===========
-- One statement per call. Eligible flocks come from ix_flock_farm_active; each
-- flock's record-on-date and last-record-date are index probes on the new
-- (farmid, flockid, date) index below -- the lateral joins run inside the one
-- query, not as N round trips from the API.
--
-- Idempotent. Safe to run more than once.
-- EFFECT ON TODAY'S NUMBERS: none. Read-only functions and one index.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE INDEX IF NOT EXISTS ix_productionrecords_farm_flock_date
    ON public.productionrecords (farmid, flockid, date);

-- -----------------------------------------------------------------------------
-- The latest pick time the farm has switched on. The first three picks are
-- always on; 4th-6th count only when enabled AND set to a real HH:mm. A blank
-- or malformed value is ignored rather than allowed to throw.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultry_lastpicktime(p_farmid text)
RETURNS time
LANGUAGE sql
STABLE
AS $function$
    SELECT COALESCE(
        (SELECT max(t::time)
         FROM   farmproductionsettings s,
                LATERAL (VALUES (s.firstpicktime,  TRUE),
                                (s.secondpicktime, TRUE),
                                (s.thirdpicktime,  TRUE),
                                (s.fourthpicktime, COALESCE(s.enablefourthpick, FALSE)),
                                (s.fifthpicktime,  COALESCE(s.enablefifthpick,  FALSE)),
                                (s.sixthpicktime,  COALESCE(s.enablesixthpick,  FALSE))) v(t, enabled)
         WHERE  s.farmid = p_farmid
           AND  v.enabled
           AND  btrim(COALESCE(v.t, '')) ~ '^([01]?[0-9]|2[0-3]):[0-5][0-9]$'),
        time '16:00');
$function$;

-- -----------------------------------------------------------------------------
-- One row per ELIGIBLE flock for the business date, complete or not.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryactivity_productioncompleteness(text, date, timestamptz);

CREATE FUNCTION public.sppoultryactivity_productioncompleteness(
    p_farmid       text,
    p_businessdate date        DEFAULT NULL,
    p_asof         timestamptz DEFAULT now())
RETURNS TABLE(
    businessdate         date,
    flockid              integer,
    flockname            text,
    batchid              integer,
    batchname            text,
    houseid              integer,
    housename            text,
    expectedfrom         date,
    hasproduction        boolean,
    recordcount          integer,
    lastproductiondate   date,
    daysmissing          integer,
    pendingbatchrecordid integer,
    pendingbatchstatus   text,
    severity             text)
LANGUAGE plpgsql
STABLE
AS $function$
#variable_conflict use_column
DECLARE
    v_tz       text      := public.fncompany_timezone(p_farmid);
    v_local    timestamp := p_asof AT TIME ZONE public.fncompany_timezone(p_farmid);
    v_today    date;
    v_date     date;
    v_lastpick time      := public.fnpoultry_lastpicktime(p_farmid);
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN
        RAISE EXCEPTION 'Company ID is required.';
    END IF;

    v_today := v_local::date;
    v_date  := COALESCE(p_businessdate, v_today);

    IF v_date > v_today THEN
        RAISE EXCEPTION 'Business date % is in the future for this company (today is %).',
            v_date, v_today;
    END IF;

    RETURN QUERY
    WITH eligible AS (
        SELECT f.flockid,
               f.name::text                 AS flockname,
               f.batchid,
               b.batchname::text            AS batchname,
               f.houseid,
               h.housename::text            AS housename,
               GREATEST(
                   f.startdate,
                   COALESCE(o.effectivebusinessdate, f.startdate),
                   -- createdat is written by DEFAULT now() in a UTC session.
                   ((f.createdat AT TIME ZONE 'UTC') AT TIME ZONE v_tz)::date
               )                             AS expectedfrom
        FROM   flock f
        LEFT JOIN mainflockbatch b ON b.batchid = f.batchid AND b.farmid = f.farmid
        LEFT JOIN houses h         ON h.houseid = f.houseid AND h.farmid = f.farmid
        LEFT JOIN LATERAL (
            SELECT max(op.effectivebusinessdate) AS effectivebusinessdate
            FROM   poultryopeningflockposition op
            WHERE  op.farmid = p_farmid AND op.flockid = f.flockid
        ) o ON TRUE
        WHERE  f.farmid = p_farmid
          AND  f.active
          AND  f.hasarrived
          AND  NOT COALESCE(f.isdeleted, FALSE)
    ),
    scored AS (
        SELECT e.*,
               COALESCE(onday.n, 0)::integer  AS recordcount,
               lastrec.d                      AS lastproductiondate,
               pend.id                        AS pendingbatchrecordid,
               pend.status::text              AS pendingbatchstatus
        FROM   eligible e
        LEFT JOIN LATERAL (
            SELECT count(*) AS n
            FROM   productionrecords pr
            WHERE  pr.farmid = p_farmid AND pr.flockid = e.flockid AND pr.date = v_date
        ) onday ON TRUE
        LEFT JOIN LATERAL (
            SELECT max(pr.date) AS d
            FROM   productionrecords pr
            WHERE  pr.farmid = p_farmid AND pr.flockid = e.flockid AND pr.date <= v_date
        ) lastrec ON TRUE
        LEFT JOIN LATERAL (
            -- An unposted Batch Production Entry for this day that includes the
            -- flock. Posted batches have already written productionrecords;
            -- Reversed / Cancelled ones never will.
            SELECT r.id, r.status
            FROM   productionbatchrecords r
            JOIN   productionbatchincludedflocks i ON i.productionbatchrecordid = r.id
            WHERE  r.farmid = p_farmid
              AND  r.productiondate = v_date
              AND  i.flockid = e.flockid
              AND  r.status IN ('Draft', 'PendingAllocation', 'Allocated')
            ORDER  BY r.id DESC
            LIMIT  1
        ) pend ON TRUE
        WHERE  e.expectedfrom <= v_date
    ),
    gaps AS (
        SELECT s.*,
               (s.recordcount > 0) AS done,
               CASE WHEN s.recordcount > 0 THEN 0
                    -- Consecutive unrecorded days ending on v_date, counted from
                    -- the day after the last record, or from expected-from if the
                    -- flock has never reported (or its last record predates it).
                    ELSE (v_date - GREATEST(COALESCE(s.lastproductiondate + 1, s.expectedfrom),
                                            s.expectedfrom) + 1)::integer
               END AS gap
        FROM   scored s
    )
    SELECT v_date,
           g.flockid,
           g.flockname,
           g.batchid,
           g.batchname,
           g.houseid,
           g.housename,
           g.expectedfrom,
           g.done,
           g.recordcount,
           g.lastproductiondate,
           g.gap,
           g.pendingbatchrecordid,
           g.pendingbatchstatus,
           CASE WHEN g.done                          THEN NULL
                WHEN v_date < v_today OR g.gap >= 2  THEN 'Critical'
                WHEN v_local::time >= v_lastpick     THEN 'Warning'
                ELSE                                      'Information'
           END
    FROM   gaps g
    ORDER  BY g.done, g.batchname NULLS LAST, g.housename NULLS LAST, g.flockname, g.flockid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- The headline: "17 of 20 flocks reported". Built FROM the detail function so
-- the count and the list can never disagree.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryactivity_productioncompletenesssummary(text, date, timestamptz);

CREATE FUNCTION public.sppoultryactivity_productioncompletenesssummary(
    p_farmid       text,
    p_businessdate date        DEFAULT NULL,
    p_asof         timestamptz DEFAULT now())
RETURNS TABLE(
    businessdate         date,
    companytoday         date,
    companylocaltime     timestamp,
    timezoneid           text,
    lastpicktime         text,
    expectedcount        integer,
    completedcount       integer,
    missingcount         integer,
    awaitingpostingcount integer,
    duplicateflockcount  integer,
    severity             text)
LANGUAGE sql
STABLE
AS $function$
    WITH d AS (
        SELECT * FROM public.sppoultryactivity_productioncompleteness(p_farmid, p_businessdate, p_asof)
    )
    SELECT COALESCE(p_businessdate, (p_asof AT TIME ZONE public.fncompany_timezone(p_farmid))::date),
           (p_asof AT TIME ZONE public.fncompany_timezone(p_farmid))::date,
           p_asof AT TIME ZONE public.fncompany_timezone(p_farmid),
           public.fncompany_timezone(p_farmid),
           to_char(public.fnpoultry_lastpicktime(p_farmid), 'HH24:MI'),
           count(*)::integer,
           count(*) FILTER (WHERE d.hasproduction)::integer,
           count(*) FILTER (WHERE NOT d.hasproduction)::integer,
           count(*) FILTER (WHERE NOT d.hasproduction AND d.pendingbatchrecordid IS NOT NULL)::integer,
           count(*) FILTER (WHERE d.recordcount > 1)::integer,
           CASE max(CASE d.severity WHEN 'Critical' THEN 3 WHEN 'Warning' THEN 2
                                    WHEN 'Information' THEN 1 END)
                WHEN 3 THEN 'Critical' WHEN 2 THEN 'Warning' WHEN 1 THEN 'Information'
           END
    FROM d;
$function$;

-- -----------------------------------------------------------------------------
-- Every missing date for ONE flock within a lookback window, newest first --
-- the dropdown under each row on Farm Completeness.
--
-- daysmissing above is the CURRENT run only (days since the last record). A
-- flock can also have older gaps -- missed the 10th, recorded the 11th to the
-- 27th, missed today -- and those are exactly what someone clearing a backlog
-- needs to see, so this lists every unrecorded day in the window.
--
-- Eligibility and expected-from are NOT re-derived here: the flock's row from
-- sppoultryactivity_productioncompleteness supplies both, so the list and the
-- count can never disagree about which days a flock owed. A flock that is not
-- eligible (closed, not arrived, another company's) returns no rows.
-- The window is clamped to 1..366 days.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryactivity_flockmissingdates(text, integer, date, integer, timestamptz);

CREATE FUNCTION public.sppoultryactivity_flockmissingdates(
    p_farmid       text,
    p_flockid      integer,
    p_businessdate date        DEFAULT NULL,
    p_days         integer     DEFAULT 30,
    p_asof         timestamptz DEFAULT now())
RETURNS TABLE(
    businessdate         date,
    missingdate          date,
    pendingbatchrecordid integer,
    pendingbatchstatus   text)
LANGUAGE plpgsql
STABLE
AS $function$
#variable_conflict use_column
DECLARE
    v_date date;
    v_from date;
    v_days integer := LEAST(GREATEST(COALESCE(p_days, 30), 1), 366);
BEGIN
    SELECT x.businessdate, x.expectedfrom INTO v_date, v_from
    FROM   public.sppoultryactivity_productioncompleteness(p_farmid, p_businessdate, p_asof) x
    WHERE  x.flockid = p_flockid;

    IF v_date IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT v_date, g.d::date, pend.id, pend.status::text
    FROM   generate_series(GREATEST(v_from, v_date - (v_days - 1)), v_date, interval '1 day') g(d)
    LEFT JOIN LATERAL (
        SELECT r.id, r.status
        FROM   productionbatchrecords r
        JOIN   productionbatchincludedflocks i ON i.productionbatchrecordid = r.id
        WHERE  r.farmid = p_farmid
          AND  r.productiondate = g.d::date
          AND  i.flockid = p_flockid
          AND  r.status IN ('Draft', 'PendingAllocation', 'Allocated')
        ORDER  BY r.id DESC
        LIMIT  1
    ) pend ON TRUE
    WHERE  NOT EXISTS (SELECT 1 FROM productionrecords pr
                       WHERE pr.farmid = p_farmid AND pr.flockid = p_flockid AND pr.date = g.d::date)
    ORDER  BY g.d DESC;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification. Runs after COMMIT so a failure here does not undo the migration.
--
-- Every fixture lives in an inner block that ends by raising a sentinel, which
-- rolls the block's subtransaction back -- so no selftest flock, record or farm
-- row survives (flock has a soft-delete trigger, so DELETE alone would leave
-- retired rows behind). Any OTHER exception is a real failure and propagates.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    a      text := '__332_selftest_a__';   -- company under test
    b      text := '__332_selftest_b__';   -- a second company, for isolation
    z      text := '__332_selftest_z__';   -- a company with no flocks
    -- Clock: 2026-03-10 10:00 UTC. Company A is in Pacific/Auckland (UTC+13 in
    -- March), so its local time is 2026-03-10 23:00 -- same day, but past its
    -- last pick. At 11:30 UTC it is 00:30 on the 11th: the timezone boundary.
    t_day  timestamptz := '2026-03-10 10:00:00+00';
    t_next timestamptz := '2026-03-10 11:30:00+00';
    t_morn timestamptz := '2026-03-09 20:00:00+00';   -- 09:00 local on the 10th
    d      date := date '2026-03-10';
    -- Entered into the system well before the test day (the pinned clock is in
    -- the past, so this cannot be relative to now()).
    v_created timestamp := timestamp '2026-01-01 08:00';
    v_house integer;
    f_rec  integer; f_batch integer; f_miss integer; f_miss2 integer;
    f_inactive integer; f_pending integer; f_future integer; f_deleted integer;
    f_pendbatch integer; f_b integer; f_dup integer; f_late integer;
    v_pbr  integer;
    s      record;
    r      record;
    v_n    integer;
BEGIN
    BEGIN
        INSERT INTO farms (id, farmid, name, email, type, timezoneid)
        VALUES (a, a, 'Selftest A', 'a@selftest.invalid', 'Poultry', 'Pacific/Auckland'),
               (b, b, 'Selftest B', 'b@selftest.invalid', 'Poultry', 'Pacific/Auckland'),
               (z, z, 'Selftest Z', 'z@selftest.invalid', 'Poultry', 'Pacific/Auckland');

        INSERT INTO houses (userid, farmid, housename, capacity)
        VALUES ('__332__', a, 'Pen 7', 100) RETURNING houseid INTO v_house;

        -- Every flock started well before the test day, and createdat is pinned
        -- before it too so the "entered into the system" floor does not hide them.
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, houseid, createdat)
        VALUES ('__332__', a, 'Recorded manually', d - 30, 'Brown', 100, TRUE, TRUE, -332, v_house, v_created)
        RETURNING flockid INTO f_rec;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES ('__332__', a, 'Recorded via batch', d - 30, 'Brown', 100, TRUE, TRUE, -332, v_created)
        RETURNING flockid INTO f_batch;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, houseid, createdat)
        VALUES ('__332__', a, 'Missing today', d - 30, 'Brown', 100, TRUE, TRUE, -332, v_house, v_created)
        RETURNING flockid INTO f_miss;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES ('__332__', a, 'Missing three days', d - 30, 'Brown', 100, TRUE, TRUE, -332, v_created)
        RETURNING flockid INTO f_miss2;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES ('__332__', a, 'Duplicate records', d - 30, 'Brown', 100, TRUE, TRUE, -332, v_created)
        RETURNING flockid INTO f_dup;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES ('__332__', a, 'In unposted batch', d - 30, 'Brown', 100, TRUE, TRUE, -332, v_created)
        RETURNING flockid INTO f_pendbatch;
        -- Not eligible:
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat, inactivationreason)
        VALUES ('__332__', a, 'Closed', d - 30, 'Brown', 100, FALSE, TRUE, -332, v_created, 'Sold')
        RETURNING flockid INTO f_inactive;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES ('__332__', a, 'Not arrived', d - 30, 'Brown', 100, TRUE, FALSE, -332, v_created)
        RETURNING flockid INTO f_pending;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES ('__332__', a, 'Starts tomorrow', d + 1, 'Brown', 100, TRUE, TRUE, -332, v_created)
        RETURNING flockid INTO f_future;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat, isdeleted)
        VALUES ('__332__', a, 'Deleted', d - 30, 'Brown', 100, TRUE, TRUE, -332, v_created, TRUE)
        RETURNING flockid INTO f_deleted;
        -- Started a month ago but only ENTERED into the system after the test
        -- day (e.g. a batch divided into flocks later): owes nothing for the 10th.
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES ('__332__', a, 'Entered later', d - 30, 'Brown', 100, TRUE, TRUE, -332, timestamp '2026-03-12 08:00')
        RETURNING flockid INTO f_late;
        -- Company B: a missing flock that must never show up in A's numbers,
        -- and a record for A's flock id under B that must not count for A.
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES ('__332__', b, 'Other company', d - 30, 'Brown', 100, TRUE, TRUE, -332, v_created)
        RETURNING flockid INTO f_b;

        -- Records. The column list is every NOT NULL column without a default.
        INSERT INTO productionrecords (farmid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
                                       noofbirdsleft, feedkg, production9am, production12pm, production4pm,
                                       totalproduction, flockid, sourcetype, createdat)
        VALUES (a, '__332__', 10, 70, d,     100, 0, 100, 0, 1, 1, 1, 3, f_rec,   'ManualSingleFlock', now()),
               (a, '__332__', 10, 70, d,     100, 0, 100, 0, 1, 1, 1, 3, f_batch, 'BatchAllocation',   now()),
               (a, '__332__', 10, 70, d - 1, 100, 0, 100, 0, 1, 1, 1, 3, f_miss,  'ManualSingleFlock', now()),
               (a, '__332__', 10, 70, d - 3, 100, 0, 100, 0, 1, 1, 1, 3, f_miss2, 'ManualSingleFlock', now()),
               (a, '__332__', 10, 70, d,     100, 0, 100, 0, 1, 1, 1, 3, f_dup,   'ManualSingleFlock', now()),
               (a, '__332__', 10, 70, d,     100, 0, 100, 0, 1, 1, 1, 3, f_dup,   'ManualSingleFlock', now()),
               (a, '__332__', 10, 70, d - 1, 100, 0, 100, 0, 1, 1, 1, 3, f_pendbatch, 'ManualSingleFlock', now()),
               -- Closed flock DID report; it must still not enter the expected set.
               (a, '__332__', 10, 70, d,     100, 0, 100, 0, 1, 1, 1, 3, f_inactive, 'ManualSingleFlock', now()),
               -- Wrong company for f_miss: must not count as A's record.
               (b, '__332__', 10, 70, d,     100, 0, 100, 0, 1, 1, 1, 3, f_miss, 'ManualSingleFlock', now());

        -- A saved-but-unposted Batch Production Entry covering f_pendbatch.
        INSERT INTO productionbatchrecords (farmid, batchselectiontype, productiondate, status)
        VALUES (a, 'CustomBatch', d, 'PendingAllocation') RETURNING id INTO v_pbr;
        INSERT INTO productionbatchincludedflocks (productionbatchrecordid, flockid, flockname)
        VALUES (v_pbr, f_pendbatch, 'In unposted batch');

        -- ---- Summary on the day, after the last pick (23:00 local) ----------
        SELECT * INTO s FROM public.sppoultryactivity_productioncompletenesssummary(a, NULL, t_day);
        IF s.businessdate <> d THEN
            RAISE EXCEPTION '332: business date %, expected %.', s.businessdate, d;
        END IF;
        IF s.expectedcount <> 6 THEN
            RAISE EXCEPTION '332: expected 6 eligible flocks (closed, not-arrived, future, deleted and other-company entered-later and other-company excluded), got %.', s.expectedcount;
        END IF;
        IF s.completedcount <> 3 THEN
            RAISE EXCEPTION '332: expected 3 complete (manual, batch-posted, duplicated), got %.', s.completedcount;
        END IF;
        IF s.missingcount <> 3 THEN
            RAISE EXCEPTION '332: expected 3 missing, got %.', s.missingcount;
        END IF;
        IF s.awaitingpostingcount <> 1 THEN
            RAISE EXCEPTION '332: expected 1 awaiting posting, got %.', s.awaitingpostingcount;
        END IF;
        IF s.duplicateflockcount <> 1 THEN
            RAISE EXCEPTION '332: expected 1 flock with duplicate records, got %.', s.duplicateflockcount;
        END IF;
        IF s.severity <> 'Critical' THEN
            RAISE EXCEPTION '332: a flock three days behind must make the day Critical, got %.', s.severity;
        END IF;

        -- ---- Per-flock detail ------------------------------------------------
        SELECT * INTO r FROM public.sppoultryactivity_productioncompleteness(a, NULL, t_day) x WHERE x.flockid = f_miss;
        IF r.hasproduction OR r.daysmissing <> 1 OR r.lastproductiondate <> d - 1
           OR r.housename <> 'Pen 7' OR r.severity <> 'Warning' THEN
            RAISE EXCEPTION '332: missing-today row wrong: %', r;
        END IF;
        SELECT * INTO r FROM public.sppoultryactivity_productioncompleteness(a, NULL, t_day) x WHERE x.flockid = f_miss2;
        IF r.daysmissing <> 3 OR r.severity <> 'Critical' THEN
            RAISE EXCEPTION '332: three-day gap row wrong: %', r;
        END IF;
        SELECT * INTO r FROM public.sppoultryactivity_productioncompleteness(a, NULL, t_day) x WHERE x.flockid = f_pendbatch;
        IF r.hasproduction OR r.pendingbatchrecordid IS DISTINCT FROM v_pbr OR r.pendingbatchstatus <> 'PendingAllocation' THEN
            RAISE EXCEPTION '332: unposted batch not reported: %', r;
        END IF;
        SELECT * INTO r FROM public.sppoultryactivity_productioncompleteness(a, NULL, t_day) x WHERE x.flockid = f_dup;
        IF NOT r.hasproduction OR r.recordcount <> 2 OR r.severity IS NOT NULL THEN
            RAISE EXCEPTION '332: duplicate records row wrong: %', r;
        END IF;
        IF EXISTS (SELECT 1 FROM public.sppoultryactivity_productioncompleteness(a, NULL, t_day) x
                   WHERE x.flockid IN (f_inactive, f_pending, f_future, f_deleted, f_b, f_late)) THEN
            RAISE EXCEPTION '332: an ineligible or other-company flock was listed.';
        END IF;

        -- ---- Missing dates per flock (the row dropdown) ---------------------
        -- f_miss2's only record is d-3: a 3-day window is exactly d-2, d-1, d.
        SELECT count(*) INTO v_n FROM public.sppoultryactivity_flockmissingdates(a, f_miss2, NULL, 3, t_day);
        IF v_n <> 3 THEN
            RAISE EXCEPTION '332: expected 3 missing dates for the 3-day gap, got %.', v_n;
        END IF;
        -- f_miss recorded d-1 only: a 3-day window shows d AND the older gap d-2.
        IF (SELECT array_agg(x.missingdate ORDER BY x.missingdate DESC)
            FROM public.sppoultryactivity_flockmissingdates(a, f_miss, NULL, 3, t_day) x) <> ARRAY[d, d - 2] THEN
            RAISE EXCEPTION '332: the gap before the last record must be listed too.';
        END IF;
        -- The window never reaches back past expected-from (start date d-30).
        SELECT count(*) INTO v_n FROM public.sppoultryactivity_flockmissingdates(a, f_miss2, NULL, 366, t_day);
        IF v_n <> 30 THEN
            RAISE EXCEPTION '332: d-30..d is 31 days less the one record = 30, got %.', v_n;
        END IF;
        -- An unposted batch is reported on its date.
        SELECT * INTO r FROM public.sppoultryactivity_flockmissingdates(a, f_pendbatch, NULL, 1, t_day) x;
        IF r.missingdate <> d OR r.pendingbatchrecordid IS DISTINCT FROM v_pbr THEN
            RAISE EXCEPTION '332: pending batch not reported on the missing date: %', r;
        END IF;
        -- Complete, ineligible and other-company flocks list nothing.
        IF EXISTS (SELECT 1 FROM public.sppoultryactivity_flockmissingdates(a, f_rec, NULL, 1, t_day))
           OR EXISTS (SELECT 1 FROM public.sppoultryactivity_flockmissingdates(a, f_inactive, NULL, 30, t_day))
           OR EXISTS (SELECT 1 FROM public.sppoultryactivity_flockmissingdates(b, f_miss, NULL, 30, t_day)) THEN
            RAISE EXCEPTION '332: listed dates for a complete, closed or other-company flock.';
        END IF;

        -- ---- Morning (09:00 local): still inside the picking day ------------
        SELECT * INTO r FROM public.sppoultryactivity_productioncompleteness(a, NULL, t_morn) x WHERE x.flockid = f_miss;
        IF r.severity <> 'Information' THEN
            RAISE EXCEPTION '332: a flock missing at 09:00 should be Information, got %.', r.severity;
        END IF;

        -- ---- Timezone boundary: 11:30 UTC is already the 11th in Auckland ---
        SELECT * INTO s FROM public.sppoultryactivity_productioncompletenesssummary(a, NULL, t_next);
        IF s.businessdate <> d + 1 THEN
            RAISE EXCEPTION '332: at 11:30 UTC Auckland is on %, got %.', d + 1, s.businessdate;
        END IF;
        IF s.completedcount <> 0 THEN
            RAISE EXCEPTION '332: the 10th''s records counted toward the 11th (% complete).', s.completedcount;
        END IF;
        -- ...and the future flock (starts on the 11th) is now expected.
        IF NOT EXISTS (SELECT 1 FROM public.sppoultryactivity_productioncompleteness(a, NULL, t_next) x WHERE x.flockid = f_future) THEN
            RAISE EXCEPTION '332: a flock starting today was not expected today.';
        END IF;

        -- ---- An explicit past date: the day is over, so everything is Critical
        SELECT * INTO s FROM public.sppoultryactivity_productioncompletenesssummary(a, d - 1, t_day);
        IF s.businessdate <> d - 1 OR s.severity <> 'Critical' THEN
            RAISE EXCEPTION '332: past-date summary wrong: %', s;
        END IF;

        -- ---- The future is refused -----------------------------------------
        BEGIN
            PERFORM * FROM public.sppoultryactivity_productioncompleteness(a, d + 5, t_day);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '332: a future business date was accepted.';
        EXCEPTION WHEN raise_exception THEN
            NULL;  -- expected (P0001)
        END;

        -- ---- Other company: sees only its own flock -------------------------
        SELECT * INTO s FROM public.sppoultryactivity_productioncompletenesssummary(b, NULL, t_day);
        IF s.expectedcount <> 1 OR s.missingcount <> 1 THEN
            RAISE EXCEPTION '332: company B should see exactly its one missing flock: %', s;
        END IF;

        -- ---- No active flocks: zero expected, no severity -------------------
        SELECT * INTO s FROM public.sppoultryactivity_productioncompletenesssummary(z, NULL, t_day);
        IF s.expectedcount <> 0 OR s.missingcount <> 0 OR s.severity IS NOT NULL THEN
            RAISE EXCEPTION '332: an empty company should be 0/0 with no severity: %', s;
        END IF;

        -- ---- All complete: record the three outstanding flocks --------------
        INSERT INTO productionrecords (farmid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
                                       noofbirdsleft, feedkg, production9am, production12pm, production4pm,
                                       totalproduction, flockid, sourcetype, createdat)
        SELECT a, '__332__', 10, 70, d, 100, 0, 100, 0, 1, 1, 1, 3, x, 'ManualSingleFlock', now()
        FROM unnest(ARRAY[f_miss, f_miss2, f_pendbatch]) x;
        SELECT * INTO s FROM public.sppoultryactivity_productioncompletenesssummary(a, NULL, t_day);
        IF s.expectedcount <> 6 OR s.completedcount <> 6 OR s.missingcount <> 0 OR s.severity IS NOT NULL THEN
            RAISE EXCEPTION '332: all-complete summary wrong: %', s;
        END IF;

        -- ---- Last pick time follows the farm's settings ---------------------
        INSERT INTO farmproductionsettings (farmid, firstpicktime, secondpicktime, thirdpicktime, fourthpicktime, enablefourthpick)
        VALUES (a, '08:00', '11:00', '14:00', '19:30', TRUE);
        IF public.fnpoultry_lastpicktime(a) <> time '19:30' THEN
            RAISE EXCEPTION '332: an enabled 4th pick should set the last pick to 19:30, got %.', public.fnpoultry_lastpicktime(a);
        END IF;
        UPDATE farmproductionsettings SET enablefourthpick = FALSE WHERE farmid = a;
        IF public.fnpoultry_lastpicktime(a) <> time '14:00' THEN
            RAISE EXCEPTION '332: a disabled 4th pick must be ignored, got %.', public.fnpoultry_lastpicktime(a);
        END IF;
        IF public.fnpoultry_lastpicktime(z) <> time '16:00' THEN
            RAISE EXCEPTION '332: a farm with no settings should default to 16:00.';
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '__332_ok__';
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
        NULL;  -- every fixture above is rolled back with the subtransaction
    END;

    RAISE NOTICE '332_PoultryProductionCompleteness: 4 functions + 1 index, verified (15 scenarios).';
END $$;
