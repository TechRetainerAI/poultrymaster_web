-- =============================================================================
-- 338_PoultryFlockAnomalyDetection.postgres.sql
--
-- Purpose
-- -------
-- Deterministic, explainable flock anomaly detection:
--
--   "B2-P4 -- Mortality spike (Critical)
--    Deaths today: 14 (7 per 1,000 of 2,000 birds)
--    Normal (average of the last 14 days): 3 deaths/day (1.5 per 1,000 birds), from 14 recorded days
--    Alert levels: Information 1.5 times normal or more, Warning 2.5 times normal or more, Critical 4 times normal or more
--    Compared with normal: today is 4.67 times normal"
--
-- WORDING: every line a user reads says "normal", "Alert levels" and "times
-- normal" -- never "baseline", "threshold" or "standard deviation". (Internal
-- names below still say baseline; only the user-facing text is plain.)
--
-- NO LLM IS INVOLVED IN DECIDING ANYTHING. Every alert is a plain comparison of
-- one flock's figure today against the same flock's own recent history, using
-- thresholds the farm can see and change. The structured evidence (jsonb) is
-- stored with every alert so a future assistant can EXPLAIN a signal from the
-- facts -- it never decides whether one occurred.
--
-- SIGNALS (poultryanomalysignals -- the registry)
-- ===============================================
--   MortalitySpike        deaths per 1,000 birds       up    ratio      14 d
--   EggProductionDecline  laying rate % (eggs / birds) down  % change   7 d
--   FeedConsumptionSpike  feed grams / bird / day      up    % change   7 d
--   FeedConsumptionDrop   feed grams / bird / day      down  % change   7 d
--
-- Every metric is PER BIRD, so a flock that halved (birds moved, sold, culled)
-- does not look like an egg collapse or a feed drop: 850 eggs from 1,000 birds
-- is the same 85% as 1,700 from 2,000.
--
-- Adding a signal on an existing metric = one registry row. A new metric = one
-- column in fnpoultryanomaly_flockdaymetrics + one arm in fnpoultryanomaly_pick
-- + one wording block in fnpoultryanomaly_explain. Nothing else changes.
--
-- BASELINE (configurable per farm per signal, poultryanomalysettings)
-- ==================================================================
-- The previous N days (N = baselinedays), NOT including the day judged, of the
-- same flock. Only usable days count: a day with no record, with more than one
-- record, or where the metric cannot be computed (no birds, 0 kg feed) is left
-- out. Fewer than minbaselinedays usable days -> InsufficientBaseline, no alert.
--
-- Three comparison methods, chosen per signal (never one hardcoded method):
--   ratio      up:   today / baseline mean              ("4.67x baseline")
--              down: baseline mean / today              ("baseline is 1.3x today")
--   pctchange  (today - mean) / mean x 100, in the signal's direction
--   zscore     (today - mean) / rolling sample std dev, in the signal's direction
-- baselinefloor is the smallest denominator allowed (mean for ratio/pctchange,
-- std dev for zscore), so a flock with zero deaths for two weeks does not turn
-- 3 deaths into "infinity x".
--
-- A guard stops trivial alerts:
--   MortalitySpike        at least guardminimum deaths today (default 3)
--   EggProductionDecline  baseline laying rate >= guardminimum % (default 20):
--                         a flock that is not in lay has no decline to report.
--
-- SEVERITY: observed (rounded to 2 dp) >= critical -> Critical, >= warning ->
-- Warning, >= information (optional band) -> Information, else Normal.
--
-- OPENING HISTORY NEVER COUNTS (regression-tested below)
-- =======================================================
--   * poultryopeningflockposition (historical mortality / sold / culled /
--     other reductions) is NEVER read. Daily figures come only from production
--     records, which since 319 hold only what happened on their own date.
--   * Records dated BEFORE a flock's opening effective date are ignored.
--   * A flock with NO opening position (onboarded before 319): its first ever
--     recorded day is where pre-tracking history used to be typed, so that day
--     is status OnboardingDay -- never judged and never part of a baseline.
--
-- ALERTS (persisted, never deleted)
-- =================================
-- One alert per flock per business date, however many signals fired -- a
-- flock with eggs down, feed up and deaths up is ONE alert with three signals,
-- not three notifications. sppoultryanomaly_scan is idempotent: running it
-- again updates the same rows. Each change is written to the append-only
-- poultryflockalertevents (Detected, SignalAdded, SeverityChanged,
-- EvidenceUpdated, SignalCleared, AutoCleared, Reactivated, Escalated,
-- Acknowledged, NoteAdded, Resolved).
--   Open -> Acknowledged -> Resolved (by a person, note required)
--   Open/Acknowledged -> Cleared      (the data no longer shows it, e.g. a typo
--                                      was corrected; history kept)
--   Cleared -> Open                   (it fires again: Reactivated)
--   Acknowledged -> Open              (severity rises above what was
--                                      acknowledged: Escalated)
--   Resolved stays Resolved; later changes are still logged as events.
-- Triggers block DELETE on all three tables and UPDATE on events.
--
-- TIME: the default date is TODAY in the company's timezone (298). Records are
-- dated by business date, so a day is judged as soon as its record exists; the
-- scan never evaluates a date after the company's today.
--
-- Depends on 298 (fncompany_timezone) and 319 (opening position). Idempotent.
-- EFFECT ON TODAY'S NUMBERS: none (new tables + functions only).
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Signal registry + per-farm settings
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultryanomalysignals (
    signalkey               text PRIMARY KEY,
    label                   text    NOT NULL,
    metrickey               text    NOT NULL,
    metriclabel             text    NOT NULL,
    metricunit              text    NOT NULL,
    direction               text    NOT NULL CHECK (direction IN ('up', 'down')),
    guardfield              text    CHECK (guardfield IN ('currentDeaths', 'baselineMean')),
    guardlabel              text,
    defaultmethod           text    NOT NULL CHECK (defaultmethod IN ('ratio', 'pctchange', 'zscore')),
    defaultbaselinedays     integer NOT NULL,
    defaultminbaselinedays  integer NOT NULL,
    defaultinformation      numeric(12,2),
    defaultwarning          numeric(12,2) NOT NULL,
    defaultcritical         numeric(12,2) NOT NULL,
    defaultguard            numeric(12,2),
    defaultfloor            numeric(12,4) NOT NULL,
    sortorder               integer NOT NULL DEFAULT 100
);

INSERT INTO public.poultryanomalysignals AS t
    (signalkey, label, metrickey, metriclabel, metricunit, direction, guardfield, guardlabel,
     defaultmethod, defaultbaselinedays, defaultminbaselinedays,
     defaultinformation, defaultwarning, defaultcritical, defaultguard, defaultfloor, sortorder)
VALUES
    ('MortalitySpike', 'Mortality spike', 'mortalityPer1000', 'Mortality rate', 'deaths per 1,000 birds',
     'up', 'currentDeaths', 'Minimum deaths in the day', 'ratio', 14, 7, 1.5, 2.5, 4, 3, 0.3, 10),
    ('EggProductionDecline', 'Egg production decline', 'layingRatePct', 'Laying rate', '% of birds',
     'down', 'baselineMean', 'Minimum normal laying rate (%)', 'pctchange', 7, 5, 5, 10, 20, 20, 1, 20),
    ('FeedConsumptionSpike', 'Feed consumption spike', 'feedGramsPerBird', 'Feed per bird', 'g/bird/day',
     'up', NULL, NULL, 'pctchange', 7, 5, 15, 25, 40, NULL, 1, 30),
    ('FeedConsumptionDrop', 'Feed consumption drop', 'feedGramsPerBird', 'Feed per bird', 'g/bird/day',
     'down', NULL, NULL, 'pctchange', 7, 5, 15, 25, 40, NULL, 1, 40)
ON CONFLICT (signalkey) DO UPDATE SET
    label = EXCLUDED.label, metrickey = EXCLUDED.metrickey, metriclabel = EXCLUDED.metriclabel,
    metricunit = EXCLUDED.metricunit, direction = EXCLUDED.direction, guardfield = EXCLUDED.guardfield,
    guardlabel = EXCLUDED.guardlabel, defaultmethod = EXCLUDED.defaultmethod,
    defaultbaselinedays = EXCLUDED.defaultbaselinedays, defaultminbaselinedays = EXCLUDED.defaultminbaselinedays,
    defaultinformation = EXCLUDED.defaultinformation, defaultwarning = EXCLUDED.defaultwarning,
    defaultcritical = EXCLUDED.defaultcritical, defaultguard = EXCLUDED.defaultguard,
    defaultfloor = EXCLUDED.defaultfloor, sortorder = EXCLUDED.sortorder;

-- A farm's override is a COMPLETE configuration for that signal (so "no
-- Information band" can be told apart from "use the default").
CREATE TABLE IF NOT EXISTS public.poultryanomalysettings (
    farmid                text    NOT NULL,
    signalkey             text    NOT NULL REFERENCES public.poultryanomalysignals(signalkey),
    enabled               boolean NOT NULL DEFAULT TRUE,
    method                text    NOT NULL CHECK (method IN ('ratio', 'pctchange', 'zscore')),
    baselinedays          integer NOT NULL,
    minbaselinedays       integer NOT NULL,
    informationthreshold  numeric(12,2),
    warningthreshold      numeric(12,2) NOT NULL,
    criticalthreshold     numeric(12,2) NOT NULL,
    guardminimum          numeric(12,2),
    baselinefloor         numeric(12,4) NOT NULL,
    updatedby             text,
    updatedatutc          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (farmid, signalkey),
    CONSTRAINT ck_poultryanomalysettings_numbers CHECK (
        baselinedays BETWEEN 3 AND 90
        AND minbaselinedays BETWEEN 1 AND baselinedays
        AND warningthreshold > 0 AND criticalthreshold > warningthreshold
        AND (informationthreshold IS NULL OR (informationthreshold > 0 AND informationthreshold < warningthreshold))
        AND (guardminimum IS NULL OR guardminimum >= 0)
        AND baselinefloor > 0
        AND (method <> 'zscore' OR minbaselinedays >= 3))
);

DROP FUNCTION IF EXISTS public.sppoultryanomalysettings_get(text);
CREATE FUNCTION public.sppoultryanomalysettings_get(p_farmid text)
RETURNS TABLE(signalkey text, label text, metrickey text, metriclabel text, metricunit text,
              direction text, guardfield text, guardlabel text, enabled boolean, method text,
              baselinedays integer, minbaselinedays integer, informationthreshold numeric,
              warningthreshold numeric, criticalthreshold numeric, guardminimum numeric,
              baselinefloor numeric, iscustomised boolean, updatedby text, updatedatutc timestamptz,
              sortorder integer)
LANGUAGE sql
STABLE
AS $function$
    SELECT g.signalkey, g.label, g.metrickey, g.metriclabel, g.metricunit, g.direction,
           g.guardfield, g.guardlabel,
           COALESCE(o.enabled, TRUE),
           CASE WHEN o.farmid IS NULL THEN g.defaultmethod          ELSE o.method END,
           CASE WHEN o.farmid IS NULL THEN g.defaultbaselinedays    ELSE o.baselinedays END,
           CASE WHEN o.farmid IS NULL THEN g.defaultminbaselinedays ELSE o.minbaselinedays END,
           CASE WHEN o.farmid IS NULL THEN g.defaultinformation     ELSE o.informationthreshold END,
           CASE WHEN o.farmid IS NULL THEN g.defaultwarning         ELSE o.warningthreshold END,
           CASE WHEN o.farmid IS NULL THEN g.defaultcritical        ELSE o.criticalthreshold END,
           CASE WHEN o.farmid IS NULL THEN g.defaultguard           ELSE o.guardminimum END,
           CASE WHEN o.farmid IS NULL THEN g.defaultfloor           ELSE o.baselinefloor END,
           o.farmid IS NOT NULL, o.updatedby, o.updatedatutc, g.sortorder
    FROM   public.poultryanomalysignals g
    LEFT   JOIN public.poultryanomalysettings o ON o.signalkey = g.signalkey AND o.farmid = p_farmid
    ORDER  BY g.sortorder;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryanomalysettings_set(
    p_farmid text, p_signalkey text, p_enabled boolean, p_method text, p_baselinedays integer,
    p_minbaselinedays integer, p_informationthreshold numeric, p_warningthreshold numeric,
    p_criticalthreshold numeric, p_guardminimum numeric, p_baselinefloor numeric, p_updatedby text)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN RAISE EXCEPTION 'Company ID is required.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM poultryanomalysignals WHERE signalkey = p_signalkey) THEN
        RAISE EXCEPTION 'Unknown signal "%".', p_signalkey;
    END IF;
    IF p_method NOT IN ('ratio', 'pctchange', 'zscore') THEN
        RAISE EXCEPTION 'Method must be ratio, pctchange or zscore.';
    END IF;
    IF p_baselinedays IS NULL OR p_baselinedays NOT BETWEEN 3 AND 90 THEN
        RAISE EXCEPTION 'The baseline must be 3 to 90 days.';
    END IF;
    IF p_minbaselinedays IS NULL OR p_minbaselinedays < 1 OR p_minbaselinedays > p_baselinedays THEN
        RAISE EXCEPTION 'Minimum history must be at least 1 day and no more than the baseline.';
    END IF;
    IF p_method = 'zscore' AND p_minbaselinedays < 3 THEN
        RAISE EXCEPTION 'A standard-deviation baseline needs at least 3 days of history.';
    END IF;
    IF p_warningthreshold IS NULL OR p_criticalthreshold IS NULL OR p_warningthreshold <= 0
       OR p_criticalthreshold <= p_warningthreshold THEN
        RAISE EXCEPTION 'Critical must be higher than Warning, and both above zero.';
    END IF;
    IF p_informationthreshold IS NOT NULL
       AND (p_informationthreshold <= 0 OR p_informationthreshold >= p_warningthreshold) THEN
        RAISE EXCEPTION 'Information must be above zero and lower than Warning (or left empty).';
    END IF;
    IF p_guardminimum IS NOT NULL AND p_guardminimum < 0 THEN
        RAISE EXCEPTION 'The minimum cannot be negative.';
    END IF;
    IF p_baselinefloor IS NULL OR p_baselinefloor <= 0 THEN
        RAISE EXCEPTION 'The baseline floor must be above zero.';
    END IF;

    INSERT INTO poultryanomalysettings AS t (farmid, signalkey, enabled, method, baselinedays, minbaselinedays,
        informationthreshold, warningthreshold, criticalthreshold, guardminimum, baselinefloor, updatedby, updatedatutc)
    VALUES (p_farmid, p_signalkey, COALESCE(p_enabled, TRUE), p_method, p_baselinedays, p_minbaselinedays,
        p_informationthreshold, p_warningthreshold, p_criticalthreshold, p_guardminimum, p_baselinefloor, p_updatedby, now())
    ON CONFLICT (farmid, signalkey) DO UPDATE SET
        enabled = EXCLUDED.enabled, method = EXCLUDED.method, baselinedays = EXCLUDED.baselinedays,
        minbaselinedays = EXCLUDED.minbaselinedays, informationthreshold = EXCLUDED.informationthreshold,
        warningthreshold = EXCLUDED.warningthreshold, criticalthreshold = EXCLUDED.criticalthreshold,
        guardminimum = EXCLUDED.guardminimum, baselinefloor = EXCLUDED.baselinefloor,
        updatedby = EXCLUDED.updatedby, updatedatutc = now();
END;
$function$;

-- Back to the registry defaults. Deletes a SETTING, never alert history.
CREATE OR REPLACE FUNCTION public.sppoultryanomalysettings_reset(p_farmid text, p_signalkey text)
RETURNS void
LANGUAGE sql
AS $function$
    DELETE FROM public.poultryanomalysettings WHERE farmid = p_farmid AND signalkey = p_signalkey;
$function$;

-- -----------------------------------------------------------------------------
-- 2. Per-flock, per-day figures -- the ONLY place detection reads farm data.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fnpoultryanomaly_flockdaymetrics(text, date, date);
CREATE FUNCTION public.fnpoultryanomaly_flockdaymetrics(p_farmid text, p_from date, p_to date)
RETURNS TABLE(flockid integer, businessdate date, recordcount integer, birds integer, deaths integer,
              eggs integer, feedkg numeric, mortalityper1000 numeric, layingratepct numeric,
              feedgramsperbird numeric, onboardingday boolean, openingeffectivedate date)
LANGUAGE sql
STABLE
AS $function$
    WITH d AS (
        SELECT pr.flockid,
               pr.date                                   AS businessdate,
               count(*)::int                             AS recordcount,
               -- Birds at the START of the day: the population the day's deaths,
               -- eggs and feed belong to.
               max(pr.noofbirds)::int                    AS birds,
               sum(COALESCE(pr.mortality, 0))::int       AS deaths,
               sum(COALESCE(pr.totalproduction, 0))::int AS eggs,
               -- feedkg is kept equal to the record's feed lines (155).
               sum(COALESCE(pr.feedkg, 0))               AS feedkg,
               op.effectivebusinessdate                  AS opendate,
               -- No opening position: the first recorded day is where
               -- pre-tracking history was typed before 319 existed.
               (op.flockid IS NULL AND pr.date = first.d) AS onboardingday
        FROM   productionrecords pr
        JOIN   flock f ON f.flockid = pr.flockid AND f.farmid = pr.farmid
        LEFT   JOIN poultryopeningflockposition op ON op.farmid = pr.farmid AND op.flockid = pr.flockid
        LEFT   JOIN LATERAL (
                   SELECT min(p2.date) AS d FROM productionrecords p2
                   WHERE  p2.farmid = pr.farmid AND p2.flockid = pr.flockid
               ) first ON TRUE
        WHERE  pr.farmid = p_farmid
          AND  pr.date BETWEEN p_from AND p_to
          AND  NOT COALESCE(f.isdeleted, FALSE)
          -- Before the opening position there was no tracking: ignore.
          AND  (op.effectivebusinessdate IS NULL OR pr.date >= op.effectivebusinessdate)
        GROUP  BY pr.flockid, pr.date, op.effectivebusinessdate, op.flockid, first.d
    )
    SELECT d.flockid, d.businessdate, d.recordcount, d.birds, d.deaths, d.eggs, d.feedkg,
           CASE WHEN d.birds > 0 THEN round(d.deaths * 1000.0 / d.birds, 4) END,
           CASE WHEN d.birds > 0 THEN round(d.eggs * 100.0 / d.birds, 4) END,
           -- 0 kg means "feed not recorded", not "the birds ate nothing".
           CASE WHEN d.birds > 0 AND d.feedkg > 0 THEN round(d.feedkg * 1000.0 / d.birds, 4) END,
           d.onboardingday, d.opendate
    FROM d;
$function$;

-- Which metric a signal reads.
CREATE OR REPLACE FUNCTION public.fnpoultryanomaly_pick(p_metrickey text, p_mortalityper1000 numeric,
    p_layingratepct numeric, p_feedgramsperbird numeric)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT CASE p_metrickey
               WHEN 'mortalityPer1000' THEN p_mortalityper1000
               WHEN 'layingRatePct'    THEN p_layingratepct
               WHEN 'feedGramsPerBird' THEN p_feedgramsperbird
           END;
$function$;

CREATE OR REPLACE FUNCTION public.fnpoultryanomaly_sevrank(p_severity text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT CASE p_severity WHEN 'Critical' THEN 3 WHEN 'Warning' THEN 2 WHEN 'Information' THEN 1 ELSE 0 END;
$function$;

-- 1234.5 -> '1,234.5'; trailing zeros dropped; NULL -> '-'.
CREATE OR REPLACE FUNCTION public.fnpoultryanomaly_fmt(p numeric, p_dp integer DEFAULT 1)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT CASE
               WHEN p IS NULL THEN '-'
               WHEN p_dp <= 0 THEN to_char(round(p), 'FM999,999,999,990')
               ELSE rtrim(rtrim(to_char(round(p, p_dp), 'FM999,999,999,990.' || repeat('0', p_dp)), '0'), '.')
           END;
$function$;

-- "2.5x baseline" / "10% below baseline" / "3 standard deviations above baseline"
CREATE OR REPLACE FUNCTION public.fnpoultryanomaly_band(p_method text, p_direction text, p_value numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT CASE p_method
               WHEN 'ratio' THEN
                   CASE p_direction WHEN 'up' THEN format('%s times normal or more', public.fnpoultryanomaly_fmt(p_value, 2))
                                    ELSE format('normal %s times today or more', public.fnpoultryanomaly_fmt(p_value, 2)) END
               WHEN 'pctchange' THEN
                   format('%s%% or more %s normal', public.fnpoultryanomaly_fmt(p_value, 2),
                          CASE p_direction WHEN 'up' THEN 'above' ELSE 'below' END)
               ELSE
                   format('unusual score %s or more, %s normal', public.fnpoultryanomaly_fmt(p_value, 2),
                          CASE p_direction WHEN 'up' THEN 'above' ELSE 'below' END)
           END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. The explanation, written ONLY from the structured evidence. Whatever an
--    alert says, the evidence it carries proves.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryanomaly_explain(e jsonb)
RETURNS text[]
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
    k      text    := e->'metric'->>'key';
    lbl    text    := e->'metric'->>'label';
    unit   text    := e->'metric'->>'unit';
    dir    text    := e->'metric'->>'direction';
    st     text    := e->>'status';
    c      jsonb   := e->'current';
    b      jsonb   := e->'baseline';
    t      jsonb   := e->'thresholds';
    g      jsonb   := e->'guard';
    meth   text    := b->>'method';
    cur    numeric := (c->>'value')::numeric;
    mean   numeric := (b->>'mean')::numeric;
    pts    integer := COALESCE((b->>'points')::int, 0);
    obs    numeric := (e->>'observed')::numeric;
    lines  text[]  := ARRAY[]::text[];
    bands  text;
BEGIN
    IF st = 'DuplicateRecords' THEN
        RETURN ARRAY[format('%s production records exist for this flock on this date, so the day is not judged until the duplicate is removed.',
                            c->>'recordCount')];
    END IF;
    IF st = 'OnboardingDay' THEN
        RETURN ARRAY['This is the flock''s first recorded day and it has no opening position, so the day may include history from before tracking began. It is not judged and is not used to work out what is normal. Record the history in Initial Farm Setup instead.'];
    END IF;

    -- Today.
    IF k = 'mortalityPer1000' THEN
        lines := lines || CASE WHEN cur IS NULL
            THEN 'No bird count on today''s record, so a mortality rate cannot be worked out.'
            ELSE format('Deaths today: %s (%s per 1,000 of %s birds)', public.fnpoultryanomaly_fmt((c->>'deaths')::numeric, 0),
                        public.fnpoultryanomaly_fmt(cur, 2), public.fnpoultryanomaly_fmt((c->>'birds')::numeric, 0)) END;
    ELSIF k = 'layingRatePct' THEN
        lines := lines || CASE WHEN cur IS NULL
            THEN 'No bird count on today''s record, so a laying rate cannot be worked out.'
            ELSE format('Laying rate today: %s%% (%s eggs from %s birds)', public.fnpoultryanomaly_fmt(cur, 1),
                        public.fnpoultryanomaly_fmt((c->>'eggs')::numeric, 0), public.fnpoultryanomaly_fmt((c->>'birds')::numeric, 0)) END;
    ELSIF k = 'feedGramsPerBird' THEN
        lines := lines || CASE WHEN cur IS NULL
            THEN 'No feed recorded on today''s record (0 kg is treated as not recorded), so feed is not judged.'
            ELSE format('Feed today: %s g/bird (%s kg for %s birds)', public.fnpoultryanomaly_fmt(cur, 1),
                        public.fnpoultryanomaly_fmt((c->>'feedKg')::numeric, 1), public.fnpoultryanomaly_fmt((c->>'birds')::numeric, 0)) END;
    ELSE
        lines := lines || format('%s today: %s %s', lbl, public.fnpoultryanomaly_fmt(cur, 2), unit);
    END IF;
    IF st = 'NoData' THEN RETURN lines; END IF;

    -- Normal (the baseline).
    IF pts = 0 THEN
        lines := lines || format('No usable days in the previous %s days.', b->>'days');
    ELSIF k = 'mortalityPer1000' THEN
        lines := lines || format('Normal (average of the last %s days): %s deaths/day (%s per 1,000 birds), from %s recorded day%s',
            b->>'days', public.fnpoultryanomaly_fmt((b->>'avgDeaths')::numeric, 1), public.fnpoultryanomaly_fmt(mean, 2),
            pts, CASE WHEN pts = 1 THEN '' ELSE 's' END);
    ELSIF k = 'layingRatePct' THEN
        lines := lines || format('Normal (average of the last %s days): %s%% laying (about %s eggs/day from %s birds), from %s recorded day%s',
            b->>'days', public.fnpoultryanomaly_fmt(mean, 1), public.fnpoultryanomaly_fmt((b->>'avgEggs')::numeric, 0),
            public.fnpoultryanomaly_fmt((b->>'avgBirds')::numeric, 0), pts, CASE WHEN pts = 1 THEN '' ELSE 's' END);
    ELSIF k = 'feedGramsPerBird' THEN
        lines := lines || format('Normal (average of the last %s days): %s g/bird/day (about %s kg/day), from %s recorded day%s',
            b->>'days', public.fnpoultryanomaly_fmt(mean, 1), public.fnpoultryanomaly_fmt((b->>'avgFeedKg')::numeric, 1),
            pts, CASE WHEN pts = 1 THEN '' ELSE 's' END);
    ELSE
        lines := lines || format('Normal (average of the last %s days): %s %s, from %s recorded days', b->>'days', public.fnpoultryanomaly_fmt(mean, 2), unit, pts);
    END IF;
    IF meth = 'zscore' AND pts > 0 THEN
        lines := lines || format('Usual day-to-day variation: %s %s', public.fnpoultryanomaly_fmt((b->>'stdDev')::numeric, 2), unit);
    END IF;

    IF st = 'InsufficientBaseline' THEN
        RETURN lines || format('Not enough history to judge: %s usable day%s in the last %s, %s needed. No alert until there are.',
            pts, CASE WHEN pts = 1 THEN '' ELSE 's' END, b->>'days', b->>'minDays');
    END IF;
    IF st = 'BelowMinimum' THEN
        RETURN lines || CASE g->>'field'
            WHEN 'currentDeaths' THEN format('Below the minimum: a mortality alert needs at least %s deaths in a day; there were %s.',
                public.fnpoultryanomaly_fmt((g->>'minimum')::numeric, 0), public.fnpoultryanomaly_fmt((c->>'deaths')::numeric, 0))
            WHEN 'baselineMean' THEN format('Not treated as in lay: the flock''s normal laying rate (%s%%) is below the %s%% minimum.',
                public.fnpoultryanomaly_fmt(mean, 1), public.fnpoultryanomaly_fmt((g->>'minimum')::numeric, 1))
            ELSE 'Below the minimum set in Alert settings.' END;
    END IF;

    -- Alert levels + how far today is from normal.
    bands := concat_ws(', ',
        CASE WHEN t->>'information' IS NOT NULL THEN 'Information ' || public.fnpoultryanomaly_band(meth, dir, (t->>'information')::numeric) END,
        'Warning '  || public.fnpoultryanomaly_band(meth, dir, (t->>'warning')::numeric),
        'Critical ' || public.fnpoultryanomaly_band(meth, dir, (t->>'critical')::numeric));
    lines := lines || ('Alert levels: ' || bands);
    lines := lines || CASE meth
        WHEN 'ratio' THEN
            CASE dir WHEN 'up' THEN format('Compared with normal: today is %s times normal', public.fnpoultryanomaly_fmt(obs, 2))
                     ELSE format('Compared with normal: normal is %s times today', public.fnpoultryanomaly_fmt(obs, 2)) END
        WHEN 'pctchange' THEN
            format('Compared with normal: today is %s%% %s normal', public.fnpoultryanomaly_fmt(abs(obs), 2),
                   CASE WHEN (dir = 'up') = (obs >= 0) THEN 'above' ELSE 'below' END)
        ELSE
            format('Compared with normal: unusual score %s, %s normal', public.fnpoultryanomaly_fmt(abs(obs), 2),
                   CASE WHEN (dir = 'up') = (obs >= 0) THEN 'above' ELSE 'below' END)
    END;
    lines := lines || CASE WHEN st = 'Fired' THEN format('Result: %s.', e->>'severity')
                       ELSE 'Result: within the normal range.' END;
    RETURN lines;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Evaluation: every enabled signal for every flock with a record on the
--    date, INCLUDING the ones that did not fire and why. Derived, read-only.
--    This is the structured evidence a future assistant reads.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryanomaly_evaluate(text, date, timestamptz);
CREATE FUNCTION public.sppoultryanomaly_evaluate(
    p_farmid text,
    p_date   date        DEFAULT NULL,
    p_asof   timestamptz DEFAULT now())
RETURNS TABLE(
    flockid integer, flockname text, housename text, businessdate date,
    signalkey text, signallabel text, metrickey text, metriclabel text, metricunit text, direction text,
    status text, severity text, severityrank integer,
    currentvalue numeric, baselinemean numeric, baselinestddev numeric, baselinepoints integer,
    baselinefrom date, baselineto date, method text, observed numeric, changepct numeric,
    informationthreshold numeric, warningthreshold numeric, criticalthreshold numeric,
    evidence jsonb, explanation text[])
LANGUAGE plpgsql
STABLE
AS $function$
#variable_conflict use_column
DECLARE
    v_date date;
    v_max  integer;
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN RAISE EXCEPTION 'Company ID is required.'; END IF;
    v_date := COALESCE(p_date, (p_asof AT TIME ZONE public.fncompany_timezone(p_farmid))::date);
    SELECT max(s.baselinedays) INTO v_max FROM public.sppoultryanomalysettings_get(p_farmid) s WHERE s.enabled;
    IF v_max IS NULL THEN RETURN; END IF;

    RETURN QUERY
    WITH sig AS (
        SELECT * FROM public.sppoultryanomalysettings_get(p_farmid) s WHERE s.enabled
    ),
    m AS (
        SELECT * FROM public.fnpoultryanomaly_flockdaymetrics(p_farmid, v_date - v_max, v_date)
    ),
    cur AS (
        SELECT m.flockid AS fid, m.recordcount AS c_n, m.birds AS c_birds, m.deaths AS c_deaths,
               m.eggs AS c_eggs, m.feedkg AS c_feed, m.mortalityper1000 AS c_mort,
               m.layingratepct AS c_lay, m.feedgramsperbird AS c_feedg,
               m.onboardingday AS c_onb, m.openingeffectivedate AS c_open
        FROM m WHERE m.businessdate = v_date
    ),
    pairs AS (
        SELECT c.*, s.signalkey AS skey, s.label AS slabel, s.metrickey AS mkey, s.metriclabel AS mlabel,
               s.metricunit AS munit, s.direction AS dir, s.guardfield AS gfield, s.method AS meth,
               s.baselinedays AS bdays, s.minbaselinedays AS bmin, s.informationthreshold AS t_info,
               s.warningthreshold AS t_warn, s.criticalthreshold AS t_crit, s.guardminimum AS gmin,
               s.baselinefloor AS bfloor, s.sortorder AS sord,
               public.fnpoultryanomaly_pick(s.metrickey, c.c_mort, c.c_lay, c.c_feedg) AS curval
        FROM cur c CROSS JOIN sig s
    ),
    base AS (
        -- Usable baseline days: one record, not an onboarding day, metric known.
        SELECT p.fid, p.skey,
               count(*)::int AS n, avg(x.v) AS mean, stddev_samp(x.v) AS sd,
               avg(m.deaths) AS a_deaths, avg(m.eggs) AS a_eggs, avg(m.feedkg) AS a_feed, avg(m.birds) AS a_birds
        FROM pairs p
        JOIN m ON m.flockid = p.fid AND m.businessdate BETWEEN v_date - p.bdays AND v_date - 1
              AND m.recordcount = 1 AND NOT m.onboardingday
        CROSS JOIN LATERAL (SELECT public.fnpoultryanomaly_pick(p.mkey, m.mortalityper1000, m.layingratepct, m.feedgramsperbird) AS v) x
        WHERE x.v IS NOT NULL
        GROUP BY p.fid, p.skey
    ),
    skipped AS (
        SELECT p.fid, p.skey,
               count(*) FILTER (WHERE m.recordcount > 1)::int AS dupdays,
               count(*) FILTER (WHERE m.onboardingday)::int   AS onbdays
        FROM pairs p
        JOIN m ON m.flockid = p.fid AND m.businessdate BETWEEN v_date - p.bdays AND v_date - 1
        GROUP BY p.fid, p.skey
    ),
    calc AS (
        SELECT p.*, COALESCE(b.n, 0) AS n, b.mean, b.sd, b.a_deaths, b.a_eggs, b.a_feed, b.a_birds,
               COALESCE(k.dupdays, 0) AS dupdays, COALESCE(k.onbdays, 0) AS onbdays,
               CASE
                   WHEN p.c_n > 1                    THEN 'DuplicateRecords'
                   WHEN p.c_onb                      THEN 'OnboardingDay'
                   WHEN p.curval IS NULL             THEN 'NoData'
                   WHEN COALESCE(b.n, 0) < p.bmin    THEN 'InsufficientBaseline'
                   WHEN p.gmin IS NOT NULL AND p.gfield = 'currentDeaths' AND p.c_deaths < p.gmin THEN 'BelowMinimum'
                   WHEN p.gmin IS NOT NULL AND p.gfield = 'baselineMean'  AND b.mean < p.gmin     THEN 'BelowMinimum'
               END AS pre
        FROM pairs p
        LEFT JOIN base b    ON b.fid = p.fid AND b.skey = p.skey
        LEFT JOIN skipped k ON k.fid = p.fid AND k.skey = p.skey
    ),
    obs AS (
        SELECT c.*,
               CASE WHEN c.pre IS NULL THEN round(
                   CASE c.meth
                       WHEN 'ratio' THEN
                           CASE c.dir WHEN 'up' THEN c.curval / GREATEST(c.mean, c.bfloor)
                                      ELSE c.mean / GREATEST(c.curval, c.bfloor) END
                       WHEN 'pctchange' THEN
                           (CASE c.dir WHEN 'up' THEN c.curval - c.mean ELSE c.mean - c.curval END)
                           / GREATEST(c.mean, c.bfloor) * 100
                       ELSE
                           (CASE c.dir WHEN 'up' THEN c.curval - c.mean ELSE c.mean - c.curval END)
                           / GREATEST(COALESCE(c.sd, 0), c.bfloor)
                   END, 2) END AS o,
               CASE WHEN c.mean IS NOT NULL AND c.curval IS NOT NULL
                    THEN round((c.curval - c.mean) / GREATEST(c.mean, c.bfloor) * 100, 1) END AS chg
        FROM calc c
    ),
    sev AS (
        SELECT o.*,
               CASE WHEN o.o IS NULL                                  THEN NULL
                    WHEN o.o >= o.t_crit                              THEN 'Critical'
                    WHEN o.o >= o.t_warn                              THEN 'Warning'
                    WHEN o.t_info IS NOT NULL AND o.o >= o.t_info     THEN 'Information'
               END AS sv
        FROM obs o
    ),
    ev AS (
        SELECT s.*,
               COALESCE(s.pre, CASE WHEN s.sv IS NULL THEN 'Normal' ELSE 'Fired' END) AS st,
               jsonb_build_object(
                   'schema', 'poultry.flock-anomaly.v1',
                   'flockId', s.fid,
                   'businessDate', v_date,
                   'signalKey', s.skey,
                   'signalLabel', s.slabel,
                   'status', COALESCE(s.pre, CASE WHEN s.sv IS NULL THEN 'Normal' ELSE 'Fired' END),
                   'severity', s.sv,
                   'metric', jsonb_build_object('key', s.mkey, 'label', s.mlabel, 'unit', s.munit, 'direction', s.dir),
                   'current', jsonb_build_object(
                       'value', round(s.curval, 2), 'birds', s.c_birds, 'deaths', s.c_deaths,
                       'eggs', s.c_eggs, 'feedKg', s.c_feed, 'recordCount', s.c_n),
                   'baseline', jsonb_build_object(
                       'method', s.meth, 'days', s.bdays, 'minDays', s.bmin, 'points', s.n,
                       'from', v_date - s.bdays, 'to', v_date - 1,
                       'mean', round(s.mean, 4), 'stdDev', round(s.sd, 4), 'floor', s.bfloor,
                       'avgDeaths', round(s.a_deaths, 2), 'avgEggs', round(s.a_eggs, 1),
                       'avgFeedKg', round(s.a_feed, 2), 'avgBirds', round(s.a_birds, 0)),
                   'observed', s.o,
                   'changePct', s.chg,
                   'thresholds', jsonb_build_object('information', s.t_info, 'warning', s.t_warn, 'critical', s.t_crit),
                   'guard', CASE WHEN s.gfield IS NULL OR s.gmin IS NULL THEN NULL
                                 ELSE jsonb_build_object('field', s.gfield, 'minimum', s.gmin) END,
                   'exclusions', jsonb_build_object(
                       'openingHistoryRead', FALSE,
                       'openingEffectiveDate', s.c_open,
                       'duplicateDaysSkipped', s.dupdays,
                       'onboardingDaysSkipped', s.onbdays)
               ) AS evid
        FROM sev s
    )
    SELECT e.fid, f.name::text, h.housename::text, v_date,
           e.skey, e.slabel, e.mkey, e.mlabel, e.munit, e.dir,
           e.st, e.sv, public.fnpoultryanomaly_sevrank(e.sv),
           round(e.curval, 2), round(e.mean, 2), round(e.sd, 2), e.n,
           v_date - e.bdays, v_date - 1, e.meth, e.o, e.chg,
           e.t_info, e.t_warn, e.t_crit,
           e.evid, public.fnpoultryanomaly_explain(e.evid)
    FROM ev e
    JOIN flock f ON f.flockid = e.fid AND f.farmid = p_farmid
    LEFT JOIN houses h ON h.houseid = f.houseid AND h.farmid = f.farmid
    ORDER BY public.fnpoultryanomaly_sevrank(e.sv) DESC, f.name, e.sord;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Persisted alerts (one per flock per business date) + append-only events
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultryflockalerts (
    alertid               serial PRIMARY KEY,
    farmid                text        NOT NULL,
    flockid               integer     NOT NULL,
    businessdate          date        NOT NULL,
    status                text        NOT NULL DEFAULT 'Open'
                          CHECK (status IN ('Open', 'Acknowledged', 'Resolved', 'Cleared')),
    severity              text        NOT NULL CHECK (severity IN ('Information', 'Warning', 'Critical')),
    peakseverity          text        NOT NULL CHECK (peakseverity IN ('Information', 'Warning', 'Critical')),
    activesignalcount     integer     NOT NULL DEFAULT 0,
    firstdetectedatutc    timestamptz NOT NULL DEFAULT now(),
    lastevaluatedatutc    timestamptz NOT NULL DEFAULT now(),
    acknowledgedby        text,
    acknowledgedatutc     timestamptz,
    acknowledgedseverity  text,
    resolvedby            text,
    resolvedatutc         timestamptz,
    resolutionnote        text
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryflockalerts_flockday
    ON public.poultryflockalerts (farmid, flockid, businessdate);
CREATE INDEX IF NOT EXISTS ix_poultryflockalerts_farm_status
    ON public.poultryflockalerts (farmid, status, businessdate DESC);

CREATE TABLE IF NOT EXISTS public.poultryflockalertsignals (
    alertsignalid       serial PRIMARY KEY,
    alertid             integer     NOT NULL REFERENCES public.poultryflockalerts(alertid),
    farmid              text        NOT NULL,
    signalkey           text        NOT NULL,
    isactive            boolean     NOT NULL DEFAULT TRUE,
    severity            text        NOT NULL CHECK (severity IN ('Information', 'Warning', 'Critical')),
    observed            numeric,
    evidence            jsonb       NOT NULL,
    explanation         text[]      NOT NULL,
    firstdetectedatutc  timestamptz NOT NULL DEFAULT now(),
    lastevaluatedatutc  timestamptz NOT NULL DEFAULT now(),
    clearedatutc        timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryflockalertsignals_alert_signal
    ON public.poultryflockalertsignals (alertid, signalkey);

CREATE TABLE IF NOT EXISTS public.poultryflockalertevents (
    eventid     bigserial PRIMARY KEY,
    alertid     integer     NOT NULL REFERENCES public.poultryflockalerts(alertid),
    farmid      text        NOT NULL,
    eventtype   text        NOT NULL CHECK (eventtype IN (
                    'Detected', 'SignalAdded', 'SignalReactivated', 'SeverityChanged', 'EvidenceUpdated',
                    'SignalCleared', 'AutoCleared', 'Reactivated', 'Escalated',
                    'Acknowledged', 'NoteAdded', 'Resolved')),
    signalkey   text,
    note        text,
    actor       text,
    details     jsonb,
    atutc       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_poultryflockalertevents_alert ON public.poultryflockalertevents (alertid, eventid);

-- History is never deleted; events are never rewritten; an alert never moves
-- to another flock, company or date.
CREATE OR REPLACE FUNCTION public.trg_poultryflockalert_guard_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Flock alert history cannot be deleted.' USING ERRCODE = 'P0001';
    END IF;
    IF TG_TABLE_NAME = 'poultryflockalertevents' THEN
        RAISE EXCEPTION 'Flock alert events cannot be changed.' USING ERRCODE = 'P0001';
    END IF;
    IF TG_TABLE_NAME = 'poultryflockalerts'
       AND (NEW.farmid IS DISTINCT FROM OLD.farmid OR NEW.flockid IS DISTINCT FROM OLD.flockid
            OR NEW.businessdate IS DISTINCT FROM OLD.businessdate) THEN
        RAISE EXCEPTION 'A flock alert cannot be moved to another company, flock or date.' USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_poultryflockalerts_guard ON public.poultryflockalerts;
CREATE TRIGGER trg_poultryflockalerts_guard BEFORE UPDATE OR DELETE ON public.poultryflockalerts
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryflockalert_guard_fn();
DROP TRIGGER IF EXISTS trg_poultryflockalertsignals_guard ON public.poultryflockalertsignals;
CREATE TRIGGER trg_poultryflockalertsignals_guard BEFORE DELETE ON public.poultryflockalertsignals
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryflockalert_guard_fn();
DROP TRIGGER IF EXISTS trg_poultryflockalertevents_guard ON public.poultryflockalertevents;
CREATE TRIGGER trg_poultryflockalertevents_guard BEFORE UPDATE OR DELETE ON public.poultryflockalertevents
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryflockalert_guard_fn();

-- -----------------------------------------------------------------------------
-- 6. Scan: evaluate a date range and bring the persisted alerts in line.
--    Idempotent -- the same data scanned twice changes nothing.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryanomaly_scan(text, date, date, text, timestamptz);
CREATE FUNCTION public.sppoultryanomaly_scan(
    p_farmid text,
    p_from   date        DEFAULT NULL,
    p_to     date        DEFAULT NULL,
    p_actor  text        DEFAULT NULL,
    p_asof   timestamptz DEFAULT now())
RETURNS TABLE(scandate date, flocksevaluated integer, alertsopened integer, alertsupdated integer,
              alertscleared integer, alertsescalated integer)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_today   date;
    v_from    date;
    v_to      date;
    d         date;
    v_actor   text := COALESCE(NULLIF(btrim(p_actor), ''), 'system');
    v_all     jsonb;
    v_fired   integer[];
    fl        record;
    sg        record;
    ex        record;
    a         record;
    v_sev     text;
    v_n       integer;
    v_changed boolean;
    v_status  text;
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN RAISE EXCEPTION 'Company ID is required.'; END IF;
    v_today := (p_asof AT TIME ZONE public.fncompany_timezone(p_farmid))::date;
    v_to    := LEAST(COALESCE(p_to, v_today), v_today);     -- never judge the future
    v_from  := COALESCE(p_from, v_to - 1);                  -- default: yesterday + today
    IF v_from > v_to THEN RAISE EXCEPTION 'The start date is after the end date.'; END IF;
    IF v_to - v_from > 92 THEN RAISE EXCEPTION 'Scan at most 93 days at a time.'; END IF;

    -- One scan per company at a time; the unique index is the second line of defence.
    PERFORM pg_advisory_xact_lock(hashtext('poultryflockalertscan'), hashtext(p_farmid));

    d := v_from;
    WHILE d <= v_to LOOP
        scandate := d; flocksevaluated := 0; alertsopened := 0; alertsupdated := 0;
        alertscleared := 0; alertsescalated := 0;

        SELECT COALESCE(jsonb_agg(to_jsonb(e)), '[]'::jsonb) INTO v_all
        FROM public.sppoultryanomaly_evaluate(p_farmid, d, p_asof) e;
        SELECT count(DISTINCT (x->>'flockid')) INTO flocksevaluated FROM jsonb_array_elements(v_all) x;
        SELECT COALESCE(array_agg(DISTINCT (x->>'flockid')::int), '{}') INTO v_fired
        FROM jsonb_array_elements(v_all) x WHERE x->>'status' = 'Fired';

        -- Flocks with something firing today.
        FOR fl IN
            SELECT (x->>'flockid')::int AS fid,
                   max((x->>'severityrank')::int) AS rk,
                   count(*)::int AS n,
                   jsonb_agg(x ORDER BY (x->>'severityrank')::int DESC) AS sigs
            FROM jsonb_array_elements(v_all) x
            WHERE x->>'status' = 'Fired'
            GROUP BY 1
        LOOP
            v_sev := CASE fl.rk WHEN 3 THEN 'Critical' WHEN 2 THEN 'Warning' ELSE 'Information' END;
            SELECT * INTO a FROM poultryflockalerts
            WHERE farmid = p_farmid AND flockid = fl.fid AND businessdate = d FOR UPDATE;

            IF NOT FOUND THEN
                INSERT INTO poultryflockalerts (farmid, flockid, businessdate, status, severity, peakseverity, activesignalcount)
                VALUES (p_farmid, fl.fid, d, 'Open', v_sev, v_sev, fl.n)
                RETURNING * INTO a;
                INSERT INTO poultryflockalertsignals (alertid, farmid, signalkey, severity, observed, evidence, explanation)
                SELECT a.alertid, p_farmid, x->>'signalkey', x->>'severity', (x->>'observed')::numeric, x->'evidence',
                       ARRAY(SELECT jsonb_array_elements_text(x->'explanation'))
                FROM jsonb_array_elements(fl.sigs) x;
                INSERT INTO poultryflockalertevents (alertid, farmid, eventtype, actor, details)
                VALUES (a.alertid, p_farmid, 'Detected', v_actor, jsonb_build_object(
                    'severity', v_sev,
                    'signals', (SELECT jsonb_agg(jsonb_build_object('signalKey', x->>'signalkey', 'severity', x->>'severity',
                                                                    'observed', x->'observed'))
                                FROM jsonb_array_elements(fl.sigs) x)));
                alertsopened := alertsopened + 1;
                CONTINUE;
            END IF;

            v_changed := FALSE;
            FOR sg IN
                SELECT x->>'signalkey' AS k, x->>'severity' AS sv, (x->>'observed')::numeric AS o,
                       x->'evidence' AS ev, ARRAY(SELECT jsonb_array_elements_text(x->'explanation')) AS expl
                FROM jsonb_array_elements(fl.sigs) x
            LOOP
                SELECT * INTO ex FROM poultryflockalertsignals WHERE alertid = a.alertid AND signalkey = sg.k;
                IF NOT FOUND THEN
                    INSERT INTO poultryflockalertsignals (alertid, farmid, signalkey, severity, observed, evidence, explanation)
                    VALUES (a.alertid, p_farmid, sg.k, sg.sv, sg.o, sg.ev, sg.expl);
                    INSERT INTO poultryflockalertevents (alertid, farmid, eventtype, signalkey, actor, details)
                    VALUES (a.alertid, p_farmid, 'SignalAdded', sg.k, v_actor,
                            jsonb_build_object('severity', sg.sv, 'observed', sg.o));
                    v_changed := TRUE;
                ELSIF NOT ex.isactive OR ex.severity <> sg.sv OR ex.evidence <> sg.ev THEN
                    UPDATE poultryflockalertsignals
                    SET isactive = TRUE, severity = sg.sv, observed = sg.o, evidence = sg.ev, explanation = sg.expl,
                        lastevaluatedatutc = now(), clearedatutc = NULL
                    WHERE alertsignalid = ex.alertsignalid;
                    INSERT INTO poultryflockalertevents (alertid, farmid, eventtype, signalkey, actor, details)
                    VALUES (a.alertid, p_farmid,
                            CASE WHEN NOT ex.isactive THEN 'SignalReactivated'
                                 WHEN ex.severity <> sg.sv THEN 'SeverityChanged'
                                 ELSE 'EvidenceUpdated' END,
                            sg.k, v_actor,
                            jsonb_build_object('fromSeverity', ex.severity, 'toSeverity', sg.sv,
                                               'fromObserved', ex.observed, 'toObserved', sg.o,
                                               'previousEvidence', ex.evidence));
                    v_changed := TRUE;
                ELSE
                    UPDATE poultryflockalertsignals SET lastevaluatedatutc = now()
                    WHERE alertsignalid = ex.alertsignalid;
                END IF;
            END LOOP;

            -- Signals on this alert that no longer fire.
            FOR ex IN
                SELECT s.* FROM poultryflockalertsignals s
                WHERE s.alertid = a.alertid AND s.isactive
                  AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(fl.sigs) x WHERE x->>'signalkey' = s.signalkey)
            LOOP
                UPDATE poultryflockalertsignals SET isactive = FALSE, clearedatutc = now(), lastevaluatedatutc = now()
                WHERE alertsignalid = ex.alertsignalid;
                INSERT INTO poultryflockalertevents (alertid, farmid, eventtype, signalkey, actor, details)
                VALUES (a.alertid, p_farmid, 'SignalCleared', ex.signalkey, v_actor, jsonb_build_object(
                    'nowStatus', (SELECT x->>'status' FROM jsonb_array_elements(v_all) x
                                  WHERE (x->>'flockid')::int = fl.fid AND x->>'signalkey' = ex.signalkey),
                    'previousEvidence', ex.evidence));
                v_changed := TRUE;
            END LOOP;

            v_status := a.status;
            IF a.status = 'Cleared' THEN
                v_status := 'Open';
                INSERT INTO poultryflockalertevents (alertid, farmid, eventtype, actor, details)
                VALUES (a.alertid, p_farmid, 'Reactivated', v_actor, jsonb_build_object('severity', v_sev));
                v_changed := TRUE;
            ELSIF a.status = 'Acknowledged'
                  AND public.fnpoultryanomaly_sevrank(v_sev) > public.fnpoultryanomaly_sevrank(a.acknowledgedseverity) THEN
                v_status := 'Open';
                INSERT INTO poultryflockalertevents (alertid, farmid, eventtype, actor, details)
                VALUES (a.alertid, p_farmid, 'Escalated', v_actor,
                        jsonb_build_object('acknowledgedSeverity', a.acknowledgedseverity, 'severity', v_sev));
                alertsescalated := alertsescalated + 1;
                v_changed := TRUE;
            END IF;

            UPDATE poultryflockalerts
            SET status = v_status, severity = v_sev,
                peakseverity = CASE WHEN public.fnpoultryanomaly_sevrank(v_sev) > public.fnpoultryanomaly_sevrank(a.peakseverity)
                                    THEN v_sev ELSE a.peakseverity END,
                activesignalcount = fl.n, lastevaluatedatutc = now()
            WHERE alertid = a.alertid;
            IF v_changed THEN alertsupdated := alertsupdated + 1; END IF;
        END LOOP;

        -- Alerts on this date whose flock no longer fires anything (a record was
        -- corrected or deleted): clear the signals, keep every row.
        FOR a IN
            SELECT * FROM poultryflockalerts
            WHERE farmid = p_farmid AND businessdate = d AND activesignalcount > 0
              AND NOT (flockid = ANY (v_fired))
            FOR UPDATE
        LOOP
            FOR ex IN SELECT s.* FROM poultryflockalertsignals s WHERE s.alertid = a.alertid AND s.isactive LOOP
                UPDATE poultryflockalertsignals SET isactive = FALSE, clearedatutc = now(), lastevaluatedatutc = now()
                WHERE alertsignalid = ex.alertsignalid;
                INSERT INTO poultryflockalertevents (alertid, farmid, eventtype, signalkey, actor, details)
                VALUES (a.alertid, p_farmid, 'SignalCleared', ex.signalkey, v_actor, jsonb_build_object(
                    'nowStatus', COALESCE((SELECT x->>'status' FROM jsonb_array_elements(v_all) x
                                           WHERE (x->>'flockid')::int = a.flockid AND x->>'signalkey' = ex.signalkey),
                                          'NoRecord'),
                    'previousEvidence', ex.evidence));
            END LOOP;
            UPDATE poultryflockalerts
            SET activesignalcount = 0, lastevaluatedatutc = now(),
                status = CASE WHEN status IN ('Open', 'Acknowledged') THEN 'Cleared' ELSE status END
            WHERE alertid = a.alertid;
            IF a.status IN ('Open', 'Acknowledged') THEN
                INSERT INTO poultryflockalertevents (alertid, farmid, eventtype, actor, note)
                VALUES (a.alertid, p_farmid, 'AutoCleared', v_actor,
                        'The recorded figures for this day no longer show an anomaly.');
            END IF;
            alertscleared := alertscleared + 1;
        END LOOP;

        RETURN NEXT;
        d := d + 1;
    END LOOP;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 7. Reading alerts
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryflockalert_list(text, text, date, date, integer, integer, integer);
CREATE FUNCTION public.sppoultryflockalert_list(
    p_farmid  text,
    p_status  text    DEFAULT 'active',   -- active (Open + Acknowledged) | all | Open | Acknowledged | Resolved | Cleared
    p_from    date    DEFAULT NULL,
    p_to      date    DEFAULT NULL,
    p_flockid integer DEFAULT NULL,
    p_alertid integer DEFAULT NULL,
    p_limit   integer DEFAULT 200)
RETURNS TABLE(
    alertid integer, flockid integer, flockname text, housename text, businessdate date,
    status text, severity text, severityrank integer, peakseverity text, activesignalcount integer,
    consecutivedays integer, firstdetectedatutc timestamptz, lastevaluatedatutc timestamptz,
    acknowledgedby text, acknowledgedatutc timestamptz, resolvedby text, resolvedatutc timestamptz,
    resolutionnote text, notecount integer, signals jsonb)
LANGUAGE sql
STABLE
AS $function$
    WITH streak AS (
        -- Gaps-and-islands: how many days in a row this flock has had an alert,
        -- ending on this alert's date.
        SELECT x.alertid,
               row_number() OVER (PARTITION BY x.flockid, x.grp ORDER BY x.businessdate)::int AS n
        FROM (
            SELECT a.alertid, a.flockid, a.businessdate,
                   a.businessdate - (row_number() OVER (PARTITION BY a.flockid ORDER BY a.businessdate))::int AS grp
            FROM poultryflockalerts a WHERE a.farmid = p_farmid
        ) x
    )
    SELECT a.alertid, a.flockid, f.name::text, h.housename::text, a.businessdate,
           a.status, a.severity, public.fnpoultryanomaly_sevrank(a.severity), a.peakseverity, a.activesignalcount,
           COALESCE(s.n, 1), a.firstdetectedatutc, a.lastevaluatedatutc,
           a.acknowledgedby, a.acknowledgedatutc, a.resolvedby, a.resolvedatutc, a.resolutionnote,
           (SELECT count(*)::int FROM poultryflockalertevents e
            WHERE e.alertid = a.alertid AND e.note IS NOT NULL AND e.eventtype IN ('Acknowledged', 'NoteAdded', 'Resolved')),
           (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                        'signalKey', sg.signalkey, 'label', g.label, 'isActive', sg.isactive,
                        'severity', sg.severity, 'observed', sg.observed,
                        'explanation', to_jsonb(sg.explanation), 'evidence', sg.evidence,
                        'firstDetectedAtUtc', sg.firstdetectedatutc, 'clearedAtUtc', sg.clearedatutc)
                    ORDER BY sg.isactive DESC, public.fnpoultryanomaly_sevrank(sg.severity) DESC, g.sortorder), '[]'::jsonb)
            FROM poultryflockalertsignals sg
            LEFT JOIN poultryanomalysignals g ON g.signalkey = sg.signalkey
            WHERE sg.alertid = a.alertid)
    FROM poultryflockalerts a
    JOIN flock f ON f.flockid = a.flockid AND f.farmid = a.farmid
    LEFT JOIN houses h ON h.houseid = f.houseid AND h.farmid = f.farmid
    LEFT JOIN streak s ON s.alertid = a.alertid
    WHERE a.farmid = p_farmid
      AND (p_alertid IS NULL OR a.alertid = p_alertid)
      AND (p_flockid IS NULL OR a.flockid = p_flockid)
      AND (p_from IS NULL OR a.businessdate >= p_from)
      AND (p_to   IS NULL OR a.businessdate <= p_to)
      AND (p_alertid IS NOT NULL
           OR COALESCE(p_status, 'active') = 'all'
           OR (COALESCE(p_status, 'active') = 'active' AND a.status IN ('Open', 'Acknowledged'))
           OR a.status = p_status)
    ORDER BY CASE a.status WHEN 'Open' THEN 0 WHEN 'Acknowledged' THEN 1 WHEN 'Cleared' THEN 2 ELSE 3 END,
             public.fnpoultryanomaly_sevrank(a.severity) DESC, a.businessdate DESC, f.name
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 200), 1), 1000);
$function$;

DROP FUNCTION IF EXISTS public.sppoultryflockalert_events(text, integer);
CREATE FUNCTION public.sppoultryflockalert_events(p_farmid text, p_alertid integer)
RETURNS TABLE(eventid bigint, alertid integer, eventtype text, signalkey text, note text, actor text,
              details jsonb, atutc timestamptz)
LANGUAGE sql
STABLE
AS $function$
    SELECT e.eventid, e.alertid, e.eventtype, e.signalkey, e.note, e.actor, e.details, e.atutc
    FROM poultryflockalertevents e
    WHERE e.farmid = p_farmid AND e.alertid = p_alertid
    ORDER BY e.eventid;
$function$;

-- -----------------------------------------------------------------------------
-- 8. People acting on alerts. Company-scoped: an alert id from another company
--    is "not found", never touched.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryflockalert_lock(p_farmid text, p_alertid integer)
RETURNS public.poultryflockalerts
LANGUAGE plpgsql
AS $function$
DECLARE a public.poultryflockalerts;
BEGIN
    SELECT * INTO a FROM public.poultryflockalerts WHERE alertid = p_alertid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Alert not found.' USING ERRCODE = 'P0002'; END IF;
    RETURN a;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryflockalert_acknowledge(p_farmid text, p_alertid integer, p_note text, p_actor text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE a public.poultryflockalerts;
BEGIN
    a := public.fnpoultryflockalert_lock(p_farmid, p_alertid);
    IF a.status = 'Resolved' THEN RAISE EXCEPTION 'This alert is already resolved.'; END IF;
    IF a.status = 'Acknowledged' THEN RAISE EXCEPTION 'This alert is already acknowledged.'; END IF;
    UPDATE poultryflockalerts
    SET status = CASE WHEN status = 'Cleared' THEN 'Cleared' ELSE 'Acknowledged' END,
        acknowledgedby = p_actor, acknowledgedatutc = now(), acknowledgedseverity = severity
    WHERE alertid = a.alertid;
    INSERT INTO poultryflockalertevents (alertid, farmid, eventtype, note, actor, details)
    VALUES (a.alertid, p_farmid, 'Acknowledged', NULLIF(btrim(p_note), ''), p_actor,
            jsonb_build_object('severity', a.severity, 'status', a.status));
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryflockalert_addnote(p_farmid text, p_alertid integer, p_note text, p_actor text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE a public.poultryflockalerts;
BEGIN
    IF p_note IS NULL OR btrim(p_note) = '' THEN RAISE EXCEPTION 'Write a note first.'; END IF;
    a := public.fnpoultryflockalert_lock(p_farmid, p_alertid);
    INSERT INTO poultryflockalertevents (alertid, farmid, eventtype, note, actor)
    VALUES (a.alertid, p_farmid, 'NoteAdded', btrim(p_note), p_actor);
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryflockalert_resolve(p_farmid text, p_alertid integer, p_note text, p_actor text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE a public.poultryflockalerts;
BEGIN
    IF p_note IS NULL OR btrim(p_note) = '' THEN
        RAISE EXCEPTION 'Say what was found or done before resolving.';
    END IF;
    a := public.fnpoultryflockalert_lock(p_farmid, p_alertid);
    IF a.status = 'Resolved' THEN RAISE EXCEPTION 'This alert is already resolved.'; END IF;
    UPDATE poultryflockalerts
    SET status = 'Resolved', resolvedby = p_actor, resolvedatutc = now(), resolutionnote = btrim(p_note)
    WHERE alertid = a.alertid;
    INSERT INTO poultryflockalertevents (alertid, farmid, eventtype, note, actor, details)
    VALUES (a.alertid, p_farmid, 'Resolved', btrim(p_note), p_actor,
            jsonb_build_object('severity', a.severity, 'fromStatus', a.status));
END;
$function$;


-- Re-run safety: alerts stored by an earlier run of this file get the current
-- wording. The explanation is a pure function of the stored evidence, so only
-- the words can change, never the facts.
UPDATE public.poultryflockalertsignals
SET explanation = public.fnpoultryanomaly_explain(evidence)
WHERE explanation IS DISTINCT FROM public.fnpoultryanomaly_explain(evidence);

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification (rolled back by the sentinel). The Prompt 6 test list, in order.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.pfa338_rec(p_farm text, p_flock integer, p_date date, p_birds integer,
    p_deaths integer, p_eggs integer, p_feedkg numeric)
RETURNS integer
LANGUAGE sql
AS $$
    INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
        noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
    VALUES (p_farm, '__338__', '__338__', 30, 210, p_date, p_birds, p_deaths, p_birds - p_deaths, p_feedkg,
            p_eggs, 0, 0, p_eggs, p_flock, 'ManualSingleFlock', now())
    RETURNING id;
$$;

CREATE OR REPLACE FUNCTION pg_temp.pfa338_flock(p_farm text, p_name text, p_qty integer)
RETURNS integer
LANGUAGE sql
AS $$
    INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
    VALUES ('__338__', p_farm, p_name, date '2025-10-01', 'Brown', p_qty, TRUE, TRUE, -338, timestamp '2025-10-01')
    RETURNING flockid;
$$;

DO $$
DECLARE
    a text := '__338_selftest_a__';
    b text := '__338_selftest_b__';
    c text := '__338_selftest_c__';
    -- Company A is in Pacific/Auckland (UTC+13 in March). 10:00 UTC on the
    -- 20th is 23:00 on the 20th there; 11:30 UTC is already the 21st.
    t_day  timestamptz := '2026-03-20 10:00:00+00';
    t_next timestamptz := '2026-03-20 11:30:00+00';
    d date := date '2026-03-20';
    who text := '__338__';
    f_stable int; f_mort int; f_egg int; f_pop int; f_fup int; f_fdn int; f_new int; f_multi int;
    f_dup int; f_open int; f_legacy int; f_b int; f_c int;
    rec int;
    k int;
    r record;
    v_alert int;
    v_n int;
    v_events int;
BEGIN
    BEGIN
        INSERT INTO farms (id, farmid, name, email, type, timezoneid)
        VALUES (a, a, 'Selftest A', 'a@selftest.invalid', 'Poultry', 'Pacific/Auckland'),
               (b, b, 'Selftest B', 'b@selftest.invalid', 'Poultry', 'Pacific/Auckland'),
               (c, c, 'Selftest C', 'c@selftest.invalid', 'Poultry', 'UTC');

        f_stable := pg_temp.pfa338_flock(a, 'Stable', 2000);
        f_mort   := pg_temp.pfa338_flock(a, 'B2-P4', 2000);
        f_egg    := pg_temp.pfa338_flock(a, 'EggDrop', 2000);
        f_pop    := pg_temp.pfa338_flock(a, 'Halved', 2000);
        f_fup    := pg_temp.pfa338_flock(a, 'FeedUp', 2000);
        f_fdn    := pg_temp.pfa338_flock(a, 'FeedDown', 2000);
        f_new    := pg_temp.pfa338_flock(a, 'NewFlock', 2000);
        f_multi  := pg_temp.pfa338_flock(a, 'Multi', 2000);
        f_dup    := pg_temp.pfa338_flock(a, 'Dup', 2000);
        f_b      := pg_temp.pfa338_flock(b, 'B2-P4', 2000);

        -- 15 days of steady history (d-15 .. d-1): 2,000 birds, 85% lay (1,700
        -- eggs), 220 kg feed (110 g/bird). Stable alternates 3/2 deaths; the
        -- others lose 3 a day. d-15 is each flock's first recorded day (no
        -- opening position -> OnboardingDay), so the 14-day window is full.
        FOR k IN 1..15 LOOP
            PERFORM pg_temp.pfa338_rec(a, f_stable, d - k, 2000, CASE WHEN k % 2 = 0 THEN 3 ELSE 2 END, 1700, 220);
            PERFORM pg_temp.pfa338_rec(a, f_mort,   d - k, 2000, 3, 1700, 220);
            PERFORM pg_temp.pfa338_rec(a, f_egg,    d - k, 2000, 3, 1700, 220);
            PERFORM pg_temp.pfa338_rec(a, f_pop,    d - k, 2000, 3, 1700, 220);
            PERFORM pg_temp.pfa338_rec(a, f_fup,    d - k, 2000, 3, 1700, 220);
            PERFORM pg_temp.pfa338_rec(a, f_fdn,    d - k, 2000, 3, 1700, 220);
            PERFORM pg_temp.pfa338_rec(a, f_multi,  d - k, 2000, 3, 1700, 220);
            PERFORM pg_temp.pfa338_rec(a, f_dup,    d - k, 2000, 3, 1700, 220);
            PERFORM pg_temp.pfa338_rec(b, f_b,      d - k, 2000, 3, 1700, 220);
        END LOOP;
        FOR k IN 1..3 LOOP
            PERFORM pg_temp.pfa338_rec(a, f_new, d - k, 2000, 1, 1700, 220);
        END LOOP;

        -- Today.
        PERFORM pg_temp.pfa338_rec(a, f_stable, d, 2000, 3, 1690, 222);   -- nothing unusual
        PERFORM pg_temp.pfa338_rec(a, f_mort,   d, 2000, 14, 1700, 220);  -- 14 deaths vs 3/day
        PERFORM pg_temp.pfa338_rec(a, f_egg,    d, 2000, 3, 1400, 220);   -- 70% vs 85%
        PERFORM pg_temp.pfa338_rec(a, f_pop,    d, 1000, 1, 850, 110);    -- half the birds moved out
        PERFORM pg_temp.pfa338_rec(a, f_fup,    d, 2000, 3, 1700, 300);   -- 150 g vs 110 g
        PERFORM pg_temp.pfa338_rec(a, f_fdn,    d, 2000, 3, 1700, 150);   -- 75 g vs 110 g
        PERFORM pg_temp.pfa338_rec(a, f_new,    d, 2000, 50, 100, 500);   -- huge, but only 3 days known
        PERFORM pg_temp.pfa338_rec(a, f_multi,  d, 2000, 12, 1300, 290);  -- deaths up, eggs down, feed up
        PERFORM pg_temp.pfa338_rec(a, f_dup,    d, 2000, 30, 1700, 220);
        PERFORM pg_temp.pfa338_rec(a, f_dup,    d, 2000, 30, 1700, 220);  -- entered twice
        PERFORM pg_temp.pfa338_rec(b, f_b,      d, 2000, 14, 1700, 220);

        -- ---- 1. Stable flock ------------------------------------------------
        IF EXISTS (SELECT 1 FROM public.sppoultryanomaly_evaluate(a, d, t_day) e
                   WHERE e.flockid = f_stable AND e.status <> 'Normal') THEN
            RAISE EXCEPTION '338: stable flock should be Normal on every signal: %',
                (SELECT jsonb_agg(jsonb_build_object('s', e.signalkey, 'st', e.status, 'o', e.observed))
                 FROM public.sppoultryanomaly_evaluate(a, d, t_day) e WHERE e.flockid = f_stable);
        END IF;

        -- ---- 2. Mortality spike (explained exactly) ---------------------------
        SELECT * INTO r FROM public.sppoultryanomaly_evaluate(a, d, t_day) e
        WHERE e.flockid = f_mort AND e.signalkey = 'MortalitySpike';
        IF r.status <> 'Fired' OR r.severity <> 'Critical' OR r.observed <> 4.67 OR r.baselinepoints <> 14
           OR r.currentvalue <> 7 OR r.baselinemean <> 1.5 OR (r.evidence->'baseline'->>'avgDeaths')::numeric <> 3 THEN
            RAISE EXCEPTION '338: mortality spike wrong (14 deaths vs 3/day on 2,000 birds = 4.67x): %', r;
        END IF;
        IF r.explanation[1] <> 'Deaths today: 14 (7 per 1,000 of 2,000 birds)'
           OR r.explanation[2] <> 'Normal (average of the last 14 days): 3 deaths/day (1.5 per 1,000 birds), from 14 recorded days'
           OR r.explanation[3] <> 'Alert levels: Information 1.5 times normal or more, Warning 2.5 times normal or more, Critical 4 times normal or more'
           OR r.explanation[4] <> 'Compared with normal: today is 4.67 times normal'
           OR r.explanation[5] <> 'Result: Critical.' THEN
            RAISE EXCEPTION '338: mortality explanation wrong: %', r.explanation;
        END IF;

        -- ---- 3. Egg decline (laying rate, not raw count) ----------------------
        SELECT * INTO r FROM public.sppoultryanomaly_evaluate(a, d, t_day) e
        WHERE e.flockid = f_egg AND e.signalkey = 'EggProductionDecline';
        IF r.status <> 'Fired' OR r.severity <> 'Warning' OR r.observed <> 17.65 OR r.currentvalue <> 70 OR r.baselinemean <> 85 THEN
            RAISE EXCEPTION '338: egg decline wrong (85%% -> 70%% = 17.65%% drop, Warning): %', r;
        END IF;
        IF r.explanation[1] <> 'Laying rate today: 70% (1,400 eggs from 2,000 birds)' THEN
            RAISE EXCEPTION '338: egg explanation wrong: %', r.explanation;
        END IF;

        -- ---- 4. Changing flock population ------------------------------------
        IF EXISTS (SELECT 1 FROM public.sppoultryanomaly_evaluate(a, d, t_day) e
                   WHERE e.flockid = f_pop AND e.signalkey IN ('EggProductionDecline', 'FeedConsumptionDrop')
                     AND (e.status <> 'Normal' OR e.changepct <> 0)) THEN
            RAISE EXCEPTION '338: halving the flock (eggs and feed halved too) must not read as a decline.';
        END IF;

        -- ---- 5. Feed spike / drop (g/bird/day) --------------------------------
        SELECT * INTO r FROM public.sppoultryanomaly_evaluate(a, d, t_day) e
        WHERE e.flockid = f_fup AND e.signalkey = 'FeedConsumptionSpike';
        IF r.status <> 'Fired' OR r.severity <> 'Warning' OR r.currentvalue <> 150 OR r.observed <> 36.36 THEN
            RAISE EXCEPTION '338: feed spike wrong (150 vs 110 g = +36.36%%): %', r;
        END IF;
        IF (SELECT e.status FROM public.sppoultryanomaly_evaluate(a, d, t_day) e
            WHERE e.flockid = f_fup AND e.signalkey = 'FeedConsumptionDrop') <> 'Normal' THEN
            RAISE EXCEPTION '338: a feed spike is not also a feed drop.';
        END IF;
        SELECT * INTO r FROM public.sppoultryanomaly_evaluate(a, d, t_day) e
        WHERE e.flockid = f_fdn AND e.signalkey = 'FeedConsumptionDrop';
        IF r.status <> 'Fired' OR r.severity <> 'Warning' OR r.observed <> 31.82 OR r.changepct <> -31.8 THEN
            RAISE EXCEPTION '338: feed drop wrong (75 vs 110 g = -31.82%%): %', r;
        END IF;

        -- ---- 6. Insufficient baseline ----------------------------------------
        IF EXISTS (SELECT 1 FROM public.sppoultryanomaly_evaluate(a, d, t_day) e
                   WHERE e.flockid = f_new AND e.status <> 'InsufficientBaseline') THEN
            RAISE EXCEPTION '338: 3 days of history must be InsufficientBaseline on every signal.';
        END IF;
        -- Duplicate records on the day: not judged.
        IF EXISTS (SELECT 1 FROM public.sppoultryanomaly_evaluate(a, d, t_day) e
                   WHERE e.flockid = f_dup AND e.status <> 'DuplicateRecords') THEN
            RAISE EXCEPTION '338: a day with two records must be DuplicateRecords.';
        END IF;

        -- ---- 7. Opening historical mortality (REQUIRED REGRESSION) -----------
        -- Company C (UTC), min history lowered to 1 day so the onboarding window
        -- is actually judged. Flock O: placed 1,050, 960 live on d-3, 90 died
        -- before tracking. A stray record dated BEFORE the opening says 90 deaths.
        PERFORM public.sppoultryanomalysettings_set(c, 'MortalitySpike', TRUE, 'ratio', 14, 1, 1.5, 2.5, 4, 3, 0.3, who);
        f_open := pg_temp.pfa338_flock(c, 'Opened', 960);
        INSERT INTO poultryopeningflockposition (farmid, flockid, effectivebusinessdate, originallyplaced,
            openinglivebirds, historicalmortality, historyknown, createdby)
        VALUES (c, f_open, d - 3, 1050, 960, 90, TRUE, who);
        -- Before the opening: a steady week, then the 90 typed in on one day.
        -- Were pre-opening records read, d-5 would be a 30x Critical spike.
        FOR k IN 6..12 LOOP
            PERFORM pg_temp.pfa338_rec(c, f_open, d - k, 1050, 3, 0, 0);
        END LOOP;
        PERFORM pg_temp.pfa338_rec(c, f_open, d - 5, 1050, 90, 0, 0);
        PERFORM pg_temp.pfa338_rec(c, f_open, d - 3, 960, 3, 800, 110);
        PERFORM pg_temp.pfa338_rec(c, f_open, d - 2, 957, 3, 800, 110);
        PERFORM pg_temp.pfa338_rec(c, f_open, d - 1, 954, 3, 800, 110);
        PERFORM pg_temp.pfa338_rec(c, f_open, d,     951, 3, 800, 110);
        -- Legacy flock L (no opening position): 90 deaths of history were typed
        -- into its first record on d-8.
        f_legacy := pg_temp.pfa338_flock(c, 'Legacy', 1050);
        PERFORM pg_temp.pfa338_rec(c, f_legacy, d - 8, 1050, 90, 800, 110);
        FOR k IN 0..7 LOOP
            PERFORM pg_temp.pfa338_rec(c, f_legacy, d - k, 960, 3, 800, 110);
        END LOOP;

        IF EXISTS (SELECT 1 FROM public.fnpoultryanomaly_flockdaymetrics(c, d - 12, d) m
                   WHERE m.flockid = f_open AND m.businessdate < d - 3) THEN
            RAISE EXCEPTION '338: a record before the opening effective date was read.';
        END IF;
        IF (SELECT m.deaths FROM public.fnpoultryanomaly_flockdaymetrics(c, d - 3, d - 3) m WHERE m.flockid = f_open) <> 3 THEN
            RAISE EXCEPTION '338: onboarding-day deaths must be the 3 recorded that day, not include the 90 historical.';
        END IF;
        IF (SELECT e.status FROM public.sppoultryanomaly_evaluate(c, d - 8, t_day) e
            WHERE e.flockid = f_legacy AND e.signalkey = 'MortalitySpike') <> 'OnboardingDay' THEN
            RAISE EXCEPTION '338: a legacy flock''s first recorded day must be OnboardingDay, not a 90-death spike.';
        END IF;
        SELECT * INTO r FROM public.sppoultryanomaly_evaluate(c, d, t_day) e
        WHERE e.flockid = f_legacy AND e.signalkey = 'MortalitySpike';
        IF r.baselinepoints <> 7 OR (r.evidence->'baseline'->>'avgDeaths')::numeric <> 3
           OR (r.evidence->'exclusions'->>'onboardingDaysSkipped')::int <> 1 THEN
            RAISE EXCEPTION '338: the legacy onboarding day leaked into the baseline: %', r.evidence;
        END IF;
        PERFORM public.sppoultryanomaly_scan(c, d - 12, d, who, t_day);
        IF EXISTS (SELECT 1 FROM poultryflockalerts WHERE farmid = c) THEN
            RAISE EXCEPTION '338: opening history produced an alert: %',
                (SELECT jsonb_agg(to_jsonb(x)) FROM public.sppoultryflockalert_list(c, 'all') x);
        END IF;

        -- ---- 8. Multiple simultaneous signals -> ONE alert --------------------
        PERFORM public.sppoultryanomaly_scan(a, d, d, who, t_day);
        SELECT count(*) INTO v_n FROM poultryflockalerts WHERE farmid = a AND flockid = f_multi;
        SELECT * INTO r FROM public.sppoultryflockalert_list(a, 'active') x WHERE x.flockid = f_multi;
        IF v_n <> 1 OR r.activesignalcount <> 3 OR r.severity <> 'Critical' OR jsonb_array_length(r.signals) <> 3
           OR r.signals->0->>'severity' <> 'Critical' THEN
            RAISE EXCEPTION '338: multi-signal flock should be one Critical alert with 3 signals: % / %', v_n, r;
        END IF;
        -- Alerts exactly where expected, nowhere else.
        IF (SELECT array_agg(f.name::text ORDER BY f.name) FROM poultryflockalerts x JOIN flock f ON f.flockid = x.flockid
            WHERE x.farmid = a) <> ARRAY['B2-P4', 'EggDrop', 'FeedDown', 'FeedUp', 'Multi'] THEN
            RAISE EXCEPTION '338: unexpected set of alerts: %',
                (SELECT array_agg(f.name::text) FROM poultryflockalerts x JOIN flock f ON f.flockid = x.flockid WHERE x.farmid = a);
        END IF;
        -- Idempotent: a second scan creates nothing and writes no events.
        SELECT count(*) INTO v_events FROM poultryflockalertevents WHERE farmid = a;
        SELECT * INTO r FROM public.sppoultryanomaly_scan(a, d, d, who, t_day);
        IF r.alertsopened <> 0 OR r.alertsupdated <> 0
           OR (SELECT count(*) FROM poultryflockalertevents WHERE farmid = a) <> v_events THEN
            RAISE EXCEPTION '338: rescanning unchanged data changed something: %', r;
        END IF;

        -- ---- 9. Acknowledge / note / resolve; history kept -------------------
        SELECT alertid INTO v_alert FROM poultryflockalerts WHERE farmid = a AND flockid = f_mort;
        PERFORM public.sppoultryflockalert_acknowledge(a, v_alert, 'Vet called', 'manager1');
        BEGIN
            PERFORM public.sppoultryflockalert_acknowledge(a, v_alert, NULL, 'manager1');
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '338: acknowledged twice.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        PERFORM public.sppoultryflockalert_addnote(a, v_alert, 'Suspected heat stress', 'manager1');
        BEGIN
            PERFORM public.sppoultryflockalert_resolve(a, v_alert, '  ', 'manager1');
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '338: resolved without a note.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        PERFORM public.sppoultryflockalert_resolve(a, v_alert, 'Fans repaired', 'manager1');
        SELECT * INTO r FROM public.sppoultryflockalert_list(a, 'all', NULL, NULL, NULL, v_alert) x;
        IF r.status <> 'Resolved' OR r.acknowledgedby <> 'manager1' OR r.resolutionnote <> 'Fans repaired' OR r.notecount <> 3 THEN
            RAISE EXCEPTION '338: acknowledge/note/resolve not recorded: %', r;
        END IF;
        IF (SELECT array_agg(e.eventtype ORDER BY e.eventid) FROM public.sppoultryflockalert_events(a, v_alert) e)
           <> ARRAY['Detected', 'Acknowledged', 'NoteAdded', 'Resolved'] THEN
            RAISE EXCEPTION '338: event history wrong: %',
                (SELECT array_agg(e.eventtype ORDER BY e.eventid) FROM public.sppoultryflockalert_events(a, v_alert) e);
        END IF;
        PERFORM public.sppoultryanomaly_scan(a, d, d, who, t_day);
        IF (SELECT status FROM poultryflockalerts WHERE alertid = v_alert) <> 'Resolved' THEN
            RAISE EXCEPTION '338: a rescan reopened a resolved alert.';
        END IF;
        BEGIN
            DELETE FROM poultryflockalerts WHERE alertid = v_alert;
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '338: an alert was deleted.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        BEGIN
            UPDATE poultryflockalertevents SET note = 'rewritten' WHERE alertid = v_alert;
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '338: an event was rewritten.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        -- Escalation: EggDrop acknowledged at Warning, then eggs fall further.
        SELECT alertid INTO v_alert FROM poultryflockalerts WHERE farmid = a AND flockid = f_egg;
        PERFORM public.sppoultryflockalert_acknowledge(a, v_alert, NULL, 'manager1');
        UPDATE productionrecords SET totalproduction = 1200, production9am = 1200 WHERE farmid = a AND flockid = f_egg AND date = d;
        SELECT * INTO r FROM public.sppoultryanomaly_scan(a, d, d, who, t_day);
        IF r.alertsescalated <> 1 OR (SELECT status || '/' || severity FROM poultryflockalerts WHERE alertid = v_alert) <> 'Open/Critical'
           OR NOT EXISTS (SELECT 1 FROM poultryflockalertevents WHERE alertid = v_alert AND eventtype = 'Escalated') THEN
            RAISE EXCEPTION '338: a Warning acknowledged, now Critical, should reopen as Escalated: %', r;
        END IF;
        -- Data corrected: FeedUp's 300 kg was a typo for 222.
        SELECT alertid INTO v_alert FROM poultryflockalerts WHERE farmid = a AND flockid = f_fup;
        UPDATE productionrecords SET feedkg = 222 WHERE farmid = a AND flockid = f_fup AND date = d;
        SELECT * INTO r FROM public.sppoultryanomaly_scan(a, d, d, who, t_day);
        IF r.alertscleared <> 1 OR (SELECT status FROM poultryflockalerts WHERE alertid = v_alert) <> 'Cleared'
           OR (SELECT count(*) FROM poultryflockalertsignals WHERE alertid = v_alert) <> 1 THEN
            RAISE EXCEPTION '338: a corrected record should clear the alert and keep its signal row: %', r;
        END IF;
        -- ... and the typo comes back: Reactivated.
        UPDATE productionrecords SET feedkg = 300 WHERE farmid = a AND flockid = f_fup AND date = d;
        PERFORM public.sppoultryanomaly_scan(a, d, d, who, t_day);
        IF (SELECT status FROM poultryflockalerts WHERE alertid = v_alert) <> 'Open'
           OR NOT EXISTS (SELECT 1 FROM poultryflockalertevents WHERE alertid = v_alert AND eventtype = 'Reactivated') THEN
            RAISE EXCEPTION '338: a cleared alert that fires again should reopen as Reactivated.';
        END IF;

        -- ---- 10. Threshold configuration -------------------------------------
        PERFORM public.sppoultryanomalysettings_set(a, 'MortalitySpike', TRUE, 'ratio', 14, 7, 1.5, 2.5, 5, 3, 0.3, who);
        IF (SELECT e.severity FROM public.sppoultryanomaly_evaluate(a, d, t_day) e
            WHERE e.flockid = f_mort AND e.signalkey = 'MortalitySpike') <> 'Warning' THEN
            RAISE EXCEPTION '338: Critical raised to 5x should make 4.67x a Warning.';
        END IF;
        PERFORM public.sppoultryanomalysettings_set(a, 'MortalitySpike', FALSE, 'ratio', 14, 7, 1.5, 2.5, 5, 3, 0.3, who);
        IF EXISTS (SELECT 1 FROM public.sppoultryanomaly_evaluate(a, d, t_day) e WHERE e.signalkey = 'MortalitySpike') THEN
            RAISE EXCEPTION '338: a disabled signal was evaluated.';
        END IF;
        PERFORM public.sppoultryanomalysettings_reset(a, 'MortalitySpike');
        -- z-score: 14 days alternating 3/2 deaths -> sd 0.2594 per 1,000; 3 deaths is +0.96 sd.
        PERFORM public.sppoultryanomalysettings_set(a, 'MortalitySpike', TRUE, 'zscore', 14, 7, NULL, 2, 3, 0, 0.01, who);
        SELECT * INTO r FROM public.sppoultryanomaly_evaluate(a, d, t_day) e
        WHERE e.flockid = f_stable AND e.signalkey = 'MortalitySpike';
        IF r.method <> 'zscore' OR r.status <> 'Normal' OR r.observed <> 0.96 OR r.baselinestddev <> 0.26 THEN
            RAISE EXCEPTION '338: z-score baseline wrong: %', r;
        END IF;
        PERFORM public.sppoultryanomalysettings_reset(a, 'MortalitySpike');
        BEGIN
            PERFORM public.sppoultryanomalysettings_set(a, 'MortalitySpike', TRUE, 'ratio', 14, 7, 1.5, 4, 4, 3, 0.3, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '338: accepted critical = warning.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        BEGIN
            PERFORM public.sppoultryanomalysettings_set(a, 'MortalitySpike', TRUE, 'zscore', 14, 2, NULL, 2, 3, 3, 0.3, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '338: accepted a 2-day std-dev baseline.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- ---- 11. Timezone -----------------------------------------------------
        IF (SELECT DISTINCT e.businessdate FROM public.sppoultryanomaly_evaluate(a, NULL, t_day) e) <> d THEN
            RAISE EXCEPTION '338: at 23:00 Auckland the business date should be the 20th.';
        END IF;
        IF EXISTS (SELECT 1 FROM public.sppoultryanomaly_evaluate(a, NULL, t_next) e) THEN
            RAISE EXCEPTION '338: at 00:30 on the 21st in Auckland nothing is recorded yet -- nothing to judge.';
        END IF;
        IF (SELECT max(s.scandate) FROM public.sppoultryanomaly_scan(a, d, d + 5, who, t_day) s) <> d THEN
            RAISE EXCEPTION '338: the scan judged a date after the company''s today.';
        END IF;
        IF (SELECT array_agg(s.scandate ORDER BY s.scandate) FROM public.sppoultryanomaly_scan(a, NULL, NULL, who, t_next) s)
           <> ARRAY[d, d + 1] THEN
            RAISE EXCEPTION '338: the default scan window should be yesterday + today on the company''s calendar.';
        END IF;

        -- ---- 12. Company isolation --------------------------------------------
        PERFORM public.sppoultryanomaly_scan(b, d, d, who, t_day);
        IF (SELECT count(*) FROM public.sppoultryflockalert_list(b, 'all')) <> 1
           OR EXISTS (SELECT 1 FROM public.sppoultryflockalert_list(b, 'all') x WHERE x.flockid <> f_b)
           OR EXISTS (SELECT 1 FROM public.sppoultryflockalert_list(a, 'all') x WHERE x.flockid = f_b) THEN
            RAISE EXCEPTION '338: alerts crossed companies.';
        END IF;
        SELECT alertid INTO v_alert FROM poultryflockalerts WHERE farmid = a AND flockid = f_multi;
        BEGIN
            PERFORM public.sppoultryflockalert_acknowledge(b, v_alert, NULL, 'intruder');
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '338: company B acknowledged company A''s alert.';
        EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;
        END;
        IF EXISTS (SELECT 1 FROM public.sppoultryflockalert_events(b, v_alert)) THEN
            RAISE EXCEPTION '338: company B can read company A''s alert history.';
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '__338_ok__';
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
        NULL;
    END;
    RAISE NOTICE '338_PoultryFlockAnomalyDetection: verified (stable, mortality spike + explanation, egg decline, changing population, feed spike/drop, insufficient baseline, duplicates, opening + legacy history, multi-signal grouping, idempotent scan, acknowledge/note/resolve, append-only, escalation, auto-clear/reactivate, thresholds, z-score, timezone, isolation).';
END $$;

-- Stored alerts all carry the current plain wording (matters on a re-run).
DO $$
DECLARE n integer;
BEGIN
    SELECT count(*) INTO n FROM public.poultryflockalertsignals
    WHERE explanation IS DISTINCT FROM public.fnpoultryanomaly_explain(evidence)
       OR array_to_string(explanation, ' ') ~* 'baseline|threshold|standard deviation';
    IF n > 0 THEN
        RAISE EXCEPTION '338: % stored alert signal(s) still use the old wording.', n;
    END IF;
END $$;
