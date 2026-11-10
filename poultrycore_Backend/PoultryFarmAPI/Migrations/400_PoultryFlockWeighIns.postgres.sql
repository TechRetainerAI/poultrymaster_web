-- =============================================================================
-- 400: Broilers, phase 2 -- weigh-ins.
--
-- Nothing in the app recorded what a bird weighs, so a broiler farm could not
-- see growth, and phase 4 (FCR, kg produced, cost per kg) had nothing to stand
-- on. A weigh-in is a sample of birds from one flock on one day:
--
--   * individual weights (grams), from which the server derives the average,
--     min, max, uniformity and CV -- the browser's figures are never trusted;
--   * or, when the farm only wrote down the result, the sample size and the
--     average, with uniformity / CV / min / max optional.
--
-- Uniformity = % of the sampled birds within +/-10% of the sample average.
-- CV         = sample standard deviation / average x 100.
-- The same arithmetic is in lib/poultry/weigh-in-stats.ts; both carry the same
-- test cases.
--
-- Rules:
--   * one live weigh-in per flock per day (edit it rather than add a second);
--   * not before the flock started, not after the company's business date;
--   * a closed flock's weigh-ins are frozen, as its production records are;
--   * deleting is a soft delete with who / when / why.
--   * ageindays is stored: weigh date - flock start date + the age the birds
--     already had on the start date (the flock's lifecycle assignment, else its
--     batch's, else 0 = arrived day-old) -- the same age the lifecycle uses.
--
-- Any flock may be weighed (pullets are weighed too); the screens lead with
-- broiler flocks.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

CREATE TABLE IF NOT EXISTS public.poultryflockweighins (
    weighinid      serial PRIMARY KEY,
    farmid         text          NOT NULL,
    flockid        integer       NOT NULL,
    weighdate      date          NOT NULL,
    ageindays      integer       NOT NULL,
    samplesize     integer       NOT NULL,
    avgweightg     numeric(10,1) NOT NULL,
    minweightg     numeric(10,1) NULL,
    maxweightg     numeric(10,1) NULL,
    uniformitypct  numeric(5,1)  NULL,
    cvpct          numeric(6,2)  NULL,
    -- The birds as weighed, when they were entered one by one. NULL when only
    -- the summary was recorded.
    weightsg       numeric(10,1)[] NULL,
    notes          text          NULL,
    createdby      text          NULL,
    createdat      timestamp     NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updatedby      text          NULL,
    updatedat      timestamp     NULL,
    deletedby      text          NULL,
    deletedat      timestamp     NULL,
    deletereason   text          NULL,
    CONSTRAINT ck_weighin_sample     CHECK (samplesize BETWEEN 1 AND 100000),
    CONSTRAINT ck_weighin_avg        CHECK (avgweightg > 0 AND avgweightg <= 20000),
    CONSTRAINT ck_weighin_minmax     CHECK ((minweightg IS NULL OR minweightg > 0)
                                        AND (maxweightg IS NULL OR maxweightg <= 20000)
                                        AND (minweightg IS NULL OR maxweightg IS NULL OR minweightg <= maxweightg)),
    CONSTRAINT ck_weighin_uniformity CHECK (uniformitypct IS NULL OR uniformitypct BETWEEN 0 AND 100),
    CONSTRAINT ck_weighin_cv         CHECK (cvpct IS NULL OR cvpct BETWEEN 0 AND 1000),
    CONSTRAINT ck_weighin_age        CHECK (ageindays >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryflockweighins_day
    ON public.poultryflockweighins (farmid, flockid, weighdate) WHERE deletedat IS NULL;
CREATE INDEX IF NOT EXISTS ix_poultryflockweighins_flock
    ON public.poultryflockweighins (farmid, flockid, weighdate);

-- ---------------------------------------------------------------------------
-- The arithmetic, once.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryweighin_stats(p_weights numeric[])
RETURNS TABLE(samplesize integer, avgweightg numeric, minweightg numeric, maxweightg numeric,
              uniformitypct numeric, cvpct numeric)
LANGUAGE sql IMMUTABLE AS $function$
    WITH w AS (SELECT x::numeric AS g FROM unnest(p_weights) AS x WHERE x IS NOT NULL),
    a AS (SELECT count(*)::int AS n, avg(g) AS mean, min(g) AS lo, max(g) AS hi,
                 stddev_samp(g) AS sd FROM w)
    SELECT a.n,
           round(a.mean, 1),
           round(a.lo, 1),
           round(a.hi, 1),
           round(100.0 * (SELECT count(*) FROM w WHERE w.g BETWEEN a.mean * 0.9 AND a.mean * 1.1) / a.n, 1),
           CASE WHEN a.n < 2 THEN NULL ELSE round(100.0 * a.sd / a.mean, 2) END
    FROM a
    WHERE a.n > 0;
$function$;

-- The birds' age in days on a date (lifecycle assignment for the flock, else
-- its batch, else 0 = arrived day-old).
CREATE OR REPLACE FUNCTION public.fnflock_ageondate(p_farmid text, p_flockid integer, p_date date)
RETURNS integer LANGUAGE sql STABLE AS $function$
    SELECT (p_date - f.startdate)
         + COALESCE(
             (SELECT a.ageatstartdays FROM poultrylifecycleassignments a
               WHERE a.farmid = p_farmid AND a.flockid = f.flockid AND a.isactive LIMIT 1),
             (SELECT a.ageatstartdays FROM poultrylifecycleassignments a
               WHERE a.farmid = p_farmid AND a.batchid = f.batchid AND a.isactive LIMIT 1),
             0)
    FROM flock f
    WHERE f.farmid = p_farmid AND f.flockid = p_flockid;
$function$;

-- ---------------------------------------------------------------------------
-- Save (create when p_weighinid is NULL, else edit).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryweighin_save(
    p_farmid        text,
    p_flockid       integer,
    p_weighdate     date,
    p_samplesize    integer   DEFAULT NULL,
    p_avgweightg    numeric   DEFAULT NULL,
    p_weightsg      numeric[] DEFAULT NULL,
    p_uniformitypct numeric   DEFAULT NULL,
    p_cvpct         numeric   DEFAULT NULL,
    p_minweightg    numeric   DEFAULT NULL,
    p_maxweightg    numeric   DEFAULT NULL,
    p_notes         text      DEFAULT NULL,
    p_by            text      DEFAULT NULL,
    p_weighinid     integer   DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $function$
DECLARE
    v_flock   record;
    v_old     record;
    v_today   date := public.fncompany_businessdate(p_farmid);
    v_s       record;
    v_weights numeric[];
    v_id      integer;
BEGIN
    IF p_weighdate IS NULL THEN
        RAISE EXCEPTION 'Choose the date the birds were weighed.' USING ERRCODE = 'P0001';
    END IF;

    SELECT f.flockid, f.name, f.startdate, f.closeddate
      INTO v_flock
      FROM flock f
     WHERE f.farmid = p_farmid AND f.flockid = p_flockid AND NOT COALESCE(f.isdeleted, FALSE);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Flock not found.' USING ERRCODE = 'P0001';
    END IF;
    IF v_flock.closeddate IS NOT NULL THEN
        RAISE EXCEPTION 'Flock "%" is closed. Reopen it before changing its weigh-ins.', v_flock.name
            USING ERRCODE = 'P0001';
    END IF;
    IF v_flock.startdate IS NOT NULL AND p_weighdate < v_flock.startdate THEN
        RAISE EXCEPTION 'Flock "%" started on %; a weigh-in cannot be earlier.',
            v_flock.name, to_char(v_flock.startdate, 'DD Mon YYYY') USING ERRCODE = 'P0001';
    END IF;
    IF v_today IS NOT NULL AND p_weighdate > v_today THEN
        RAISE EXCEPTION 'A weigh-in cannot be dated after today (%).', to_char(v_today, 'DD Mon YYYY')
            USING ERRCODE = 'P0001';
    END IF;

    -- Individual weights win: every figure comes from them.
    v_weights := ARRAY(SELECT x FROM unnest(COALESCE(p_weightsg, ARRAY[]::numeric[])) x WHERE x IS NOT NULL);
    IF cardinality(v_weights) > 0 THEN
        IF EXISTS (SELECT 1 FROM unnest(v_weights) x WHERE x <= 0 OR x > 20000) THEN
            RAISE EXCEPTION 'Each bird''s weight must be between 1 g and 20,000 g.' USING ERRCODE = 'P0001';
        END IF;
        SELECT * INTO v_s FROM public.fnpoultryweighin_stats(v_weights);
    ELSE
        v_weights := NULL;
        IF p_samplesize IS NULL OR p_samplesize < 1 THEN
            RAISE EXCEPTION 'Enter how many birds were weighed.' USING ERRCODE = 'P0001';
        END IF;
        IF p_avgweightg IS NULL OR p_avgweightg <= 0 OR p_avgweightg > 20000 THEN
            RAISE EXCEPTION 'Enter the average weight in grams (1 to 20,000).' USING ERRCODE = 'P0001';
        END IF;
        IF p_minweightg IS NOT NULL AND p_maxweightg IS NOT NULL AND p_minweightg > p_maxweightg THEN
            RAISE EXCEPTION 'The lightest bird cannot weigh more than the heaviest.' USING ERRCODE = 'P0001';
        END IF;
        IF (p_minweightg IS NOT NULL AND p_minweightg > p_avgweightg)
           OR (p_maxweightg IS NOT NULL AND p_maxweightg < p_avgweightg) THEN
            RAISE EXCEPTION 'The average must lie between the lightest and heaviest bird.' USING ERRCODE = 'P0001';
        END IF;
        SELECT p_samplesize AS samplesize, round(p_avgweightg, 1) AS avgweightg,
               round(p_minweightg, 1) AS minweightg, round(p_maxweightg, 1) AS maxweightg,
               round(p_uniformitypct, 1) AS uniformitypct, round(p_cvpct, 2) AS cvpct
          INTO v_s;
    END IF;

    IF p_weighinid IS NOT NULL THEN
        SELECT w.weighinid, w.flockid INTO v_old
          FROM poultryflockweighins w
         WHERE w.weighinid = p_weighinid AND w.farmid = p_farmid AND w.deletedat IS NULL
         FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Weigh-in not found.' USING ERRCODE = 'P0001';
        END IF;
        IF v_old.flockid <> p_flockid
           AND EXISTS (SELECT 1 FROM flock f WHERE f.farmid = p_farmid AND f.flockid = v_old.flockid
                       AND f.closeddate IS NOT NULL) THEN
            RAISE EXCEPTION 'That weigh-in belongs to a closed flock and cannot be moved.' USING ERRCODE = 'P0001';
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM poultryflockweighins w
               WHERE w.farmid = p_farmid AND w.flockid = p_flockid AND w.weighdate = p_weighdate
                 AND w.deletedat IS NULL AND w.weighinid IS DISTINCT FROM p_weighinid) THEN
        RAISE EXCEPTION 'Flock "%" already has a weigh-in on %. Edit that one instead.',
            v_flock.name, to_char(p_weighdate, 'DD Mon YYYY') USING ERRCODE = 'P0001';
    END IF;

    IF p_weighinid IS NULL THEN
        INSERT INTO poultryflockweighins (farmid, flockid, weighdate, ageindays, samplesize, avgweightg,
            minweightg, maxweightg, uniformitypct, cvpct, weightsg, notes, createdby)
        VALUES (p_farmid, p_flockid, p_weighdate,
            GREATEST(COALESCE(public.fnflock_ageondate(p_farmid, p_flockid, p_weighdate), 0), 0),
            v_s.samplesize, v_s.avgweightg, v_s.minweightg, v_s.maxweightg, v_s.uniformitypct, v_s.cvpct,
            v_weights, NULLIF(btrim(p_notes), ''), p_by)
        RETURNING weighinid INTO v_id;
    ELSE
        UPDATE poultryflockweighins SET
            flockid = p_flockid,
            weighdate = p_weighdate,
            ageindays = GREATEST(COALESCE(public.fnflock_ageondate(p_farmid, p_flockid, p_weighdate), 0), 0),
            samplesize = v_s.samplesize, avgweightg = v_s.avgweightg,
            minweightg = v_s.minweightg, maxweightg = v_s.maxweightg,
            uniformitypct = v_s.uniformitypct, cvpct = v_s.cvpct,
            weightsg = v_weights, notes = NULLIF(btrim(p_notes), ''),
            updatedby = p_by, updatedat = now() AT TIME ZONE 'utc'
        WHERE weighinid = p_weighinid
        RETURNING weighinid INTO v_id;
    END IF;

    RETURN v_id;
END
$function$;

-- ---------------------------------------------------------------------------
-- Delete (soft).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryweighin_delete(
    p_weighinid integer, p_farmid text, p_by text DEFAULT NULL, p_reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
    v_w record;
BEGIN
    SELECT w.weighinid, f.name, f.closeddate
      INTO v_w
      FROM poultryflockweighins w
      JOIN flock f ON f.farmid = w.farmid AND f.flockid = w.flockid
     WHERE w.weighinid = p_weighinid AND w.farmid = p_farmid AND w.deletedat IS NULL
     FOR UPDATE OF w;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Weigh-in not found.' USING ERRCODE = 'P0001';
    END IF;
    IF v_w.closeddate IS NOT NULL THEN
        RAISE EXCEPTION 'Flock "%" is closed. Reopen it before changing its weigh-ins.', v_w.name
            USING ERRCODE = 'P0001';
    END IF;
    UPDATE poultryflockweighins
       SET deletedat = now() AT TIME ZONE 'utc', deletedby = p_by, deletereason = NULLIF(btrim(p_reason), '')
     WHERE weighinid = p_weighinid;
END
$function$;

-- ---------------------------------------------------------------------------
-- List, oldest first per flock, with the gain since the previous weigh-in.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryweighin_list(p_farmid text, p_flockid integer DEFAULT NULL)
RETURNS TABLE(weighinid integer, flockid integer, flockname text, flocktype text, breed text,
              flockclosed boolean, weighdate date, ageindays integer, samplesize integer,
              avgweightg numeric, minweightg numeric, maxweightg numeric, uniformitypct numeric,
              cvpct numeric, weightsg numeric[], notes text, createdby text, createdat timestamp,
              prevavgweightg numeric, dayssinceprev integer, dailygaing numeric)
LANGUAGE sql STABLE AS $function$
    SELECT w.weighinid, w.flockid, f.name::text, f.flocktype, f.breed::text,
           (f.closeddate IS NOT NULL),
           w.weighdate, w.ageindays, w.samplesize, w.avgweightg, w.minweightg, w.maxweightg,
           w.uniformitypct, w.cvpct, w.weightsg, w.notes, w.createdby, w.createdat,
           lag(w.avgweightg) OVER win,
           (w.weighdate - lag(w.weighdate) OVER win)::int,
           round((w.avgweightg - lag(w.avgweightg) OVER win)
                 / NULLIF(w.weighdate - lag(w.weighdate) OVER win, 0), 1)
    FROM poultryflockweighins w
    JOIN flock f ON f.farmid = w.farmid AND f.flockid = w.flockid
    WHERE w.farmid = p_farmid
      AND w.deletedat IS NULL
      AND (p_flockid IS NULL OR w.flockid = p_flockid)
    WINDOW win AS (PARTITION BY w.flockid ORDER BY w.weighdate)
    ORDER BY w.flockid, w.weighdate;
$function$;

COMMIT;
