-- =============================================================================
-- 422_FlockReportsSkipDeletedAndPending.postgres.sql   (requires 421)
--
-- Purpose
-- -------
-- End of Flock showed more "Birds placed" than the Birds tracker.  The bird
-- reports listed EVERY flock row, including
--   * soft-deleted flocks (flock has a BEFORE DELETE soft-delete trigger, so a
--     deleted flock is still a row) -- on dev one company showed 54,840 birds
--     placed, all of them in deleted flocks;
--   * flocks whose birds have not arrived yet (hasarrived = false) -- counted as
--     placed before a single bird was there.
-- Both predate 421, but 421 made them visible: placed is now the originally
-- placed figure, so the gap grew.
--
-- What this does
-- --------------
-- End of Flock, Birds on Hand, Flock Production Summary and Farm Summary rows
-- skip deleted flocks and flocks whose birds have not arrived.  Inactive and
-- CLOSED flocks stay -- they are what End of Flock is for.  Bodies are 421's,
-- with only that filter added; signatures unchanged (CREATE OR REPLACE).
--
-- Not changed: P&L by Flock (money, not birds; it already skips deleted flocks
-- for the chick cost) and Mortality (its rows are production records).
--
-- Deploy order: this migration, then nothing -- no API or web change needed.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- ------------------------------------------------ End of Flock
CREATE OR REPLACE FUNCTION public.sppoultryreport_endofflock(p_farmid text, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeactiveflocks boolean DEFAULT true)
 RETURNS TABLE(flockid integer, flockname text, placementdate date, flockageweeks integer, birdsplaced integer, totaldeaths integer, finalbirdsremaining integer, totaleggsproduced bigint, brokenrejectedeggs bigint, peakproductionday bigint, productiondays integer, birddays bigint, totalfeedconsumedkg numeric, feedcost numeric, medicinevaccinecost numeric, laborcost numeric, othercost numeric, totalrevenue numeric, active boolean, historyknown boolean, openingmortality integer, openingsold integer, openingculled integer, openingtransferred integer, openingother integer, recordeddeaths integer, birdssold integer, birdsculled integer, birdstransferred integer, closeddate date)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_gid uuid;
BEGIN
    BEGIN
        v_gid := p_farmid::uuid;               -- TRY_CONVERT(UNIQUEIDENTIFIER, @FarmId)
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;

    RETURN QUERY
    WITH daily AS (
        SELECT r.flockid AS c_flockid, r.date AS c_date,
               SUM(r.totalproduction::bigint) AS c_dayeggs
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.date <= p_enddate
        GROUP  BY r.flockid, r.date
    ),
    pk AS (
        SELECT daily.c_flockid,
               MAX(daily.c_dayeggs)     AS c_peakdaily,
               COUNT(*)                 AS c_days,
               SUM(daily.c_dayeggs)     AS c_eggs
        FROM   daily
        GROUP  BY daily.c_flockid
    ),
    pr AS (
        SELECT r.flockid AS c_flockid,
               SUM((COALESCE(r.brokeneggs,0)+COALESCE(r.meatyeggs,0)+COALESCE(r.softeggs,0)+COALESCE(r.losteggs,0))::bigint) AS c_broken,
               SUM(r.feedkg::numeric(18,2))                                                                                  AS c_feed,
               SUM(r.mortality)                                                                                              AS c_deaths,
               SUM(r.noofbirdsleft::bigint)                                                                                  AS c_birddays
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.date <= p_enddate
        GROUP  BY r.flockid
    ),
    rev AS (
        SELECT s.flockid AS c_flockid, SUM(s.totalamount) AS c_revenue
        FROM   sale s
        WHERE  s.status = 'Posted' AND s.farmid = p_farmid AND s.saledate < (p_enddate + 1)
        GROUP  BY s.flockid
    ),
    cost AS (
        SELECT e.flockid AS c_flockid,
            SUM(CASE WHEN e.category ILIKE '%feed%' THEN e.amount ELSE 0 END)                       AS c_feedcost,
            SUM(CASE WHEN e.category ILIKE '%medic%' OR e.category ILIKE '%vaccin%'
                       OR e.category ILIKE '%drug%'  OR e.category ILIKE '%health%'
                     THEN e.amount ELSE 0 END)                                                      AS c_medcost,
            SUM(CASE WHEN e.category ILIKE '%labo%'   OR e.category ILIKE '%salary%'
                       OR e.category ILIKE '%wage%'   OR e.category ILIKE '%payroll%'
                     THEN e.amount ELSE 0 END)                                                      AS c_laborcost,
            SUM(CASE WHEN e.category ILIKE '%feed%'   OR e.category ILIKE '%medic%'
                       OR e.category ILIKE '%vaccin%' OR e.category ILIKE '%drug%'
                       OR e.category ILIKE '%health%' OR e.category ILIKE '%labo%'
                       OR e.category ILIKE '%salary%' OR e.category ILIKE '%wage%'
                       OR e.category ILIKE '%payroll%'
                     THEN 0 ELSE e.amount END)                                                      AS c_othercost
        FROM   expense e
        WHERE  e.farmid = v_gid AND e.expensedate < (p_enddate + 1)
        GROUP  BY e.flockid
    )
    SELECT
        f.flockid,
        f.name::text                                            AS flockname,
        f.startdate                                             AS placementdate,
        -- DATEDIFF(WEEK, ...): SQL Server counts Monday-aligned week boundaries since 1900-01-01
        (((p_enddate - DATE '1900-01-01') / 7) - ((f.startdate - DATE '1900-01-01') / 7)) AS flockageweeks,
        -- 421: placed / deaths / remaining from the flock's bird position as of
        -- the end date, so the opening historical reduction is counted.
        (CASE WHEN bp.historyknown THEN bp.originallyplaced ELSE bp.openinglivebirds END)::int AS birdsplaced,
        (CASE WHEN bp.historyknown THEN bp.openingmortality ELSE 0 END + bp.recordedmortality)::int AS totaldeaths,
        bp.currentlivebirds                                     AS finalbirdsremaining,
        COALESCE(pk.c_eggs, 0)::bigint                          AS totaleggsproduced,
        COALESCE(pr.c_broken, 0)::bigint                        AS brokenrejectedeggs,
        COALESCE(pk.c_peakdaily, 0)::bigint                     AS peakproductionday,
        COALESCE(pk.c_days, 0)::int                             AS productiondays,
        COALESCE(pr.c_birddays, 0)::bigint                      AS birddays,
        COALESCE(pr.c_feed, 0)                                  AS totalfeedconsumedkg,
        COALESCE(cost.c_feedcost, 0)                            AS feedcost,
        COALESCE(cost.c_medcost, 0)                             AS medicinevaccinecost,
        COALESCE(cost.c_laborcost, 0)                           AS laborcost,
        COALESCE(cost.c_othercost, 0)                           AS othercost,
        COALESCE(rev.c_revenue, 0)                              AS totalrevenue,
        COALESCE(f.active, TRUE)                                AS active,
        bp.historyknown, bp.openingmortality, bp.openingsold, bp.openingculled,
        bp.openingtransferred, bp.openingother, bp.recordedmortality,
        bp.birdssold, bp.birdsculled, bp.birdstransferred,
        f.closeddate::date                                      AS closeddate
    FROM   flock f
    CROSS JOIN LATERAL public.fnflock_birdpositionasof(p_farmid, f.flockid, p_enddate) bp
    LEFT JOIN pk   ON pk.c_flockid   = f.flockid
    LEFT JOIN pr   ON pr.c_flockid   = f.flockid
    LEFT JOIN rev  ON rev.c_flockid  = f.flockid
    LEFT JOIN cost ON cost.c_flockid = f.flockid
    WHERE  f.farmid = p_farmid
      AND  (p_flockid IS NULL OR f.flockid = p_flockid)
      AND  (p_includeactiveflocks OR NOT COALESCE(f.active, TRUE))
      AND  NOT COALESCE(f.isdeleted, FALSE)      -- 422: a deleted flock placed nothing
      AND  COALESCE(f.hasarrived, TRUE)          -- 422: nor did one whose birds have not arrived
    ORDER  BY f.name;
END
$function$;

-- ------------------------------------------------ Birds on Hand
CREATE OR REPLACE FUNCTION public.sppoultryreport_birdsonhand(p_farmid text, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeclosedflocks boolean DEFAULT false)
 RETURNS TABLE(flockid integer, flockname text, birdsplaced integer, deaths integer, currentrecordedbirds integer,
               historyknown boolean, openingmortality integer, birdssold integer, birdsculled integer,
               birdstransferred integer, otherreductions integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- 421: every figure from the flock's bird position as of the end date.
    --   birdsplaced  = birds the flock STARTED with (originally placed; the
    --                  opening live count when the history is unknown)
    --   deaths       = opening historical mortality (history known) + recorded
    --   birdssold / birdsculled / birdstransferred = opening + since tracking
    --   otherreductions = opening "other" (history known only)
    --   currentrecordedbirds = live: the last count less sales, culls and
    --                  transfers made after it
    -- so expected - current is exactly the count corrections nobody explained.
    RETURN QUERY
    SELECT
        f.flockid,
        f.name::text,
        (CASE WHEN bp.historyknown THEN bp.originallyplaced ELSE bp.openinglivebirds END)::int,
        (CASE WHEN bp.historyknown THEN bp.openingmortality ELSE 0 END + bp.recordedmortality)::int,
        bp.currentlivebirds,
        bp.historyknown,
        CASE WHEN bp.historyknown THEN bp.openingmortality ELSE 0 END,
        (CASE WHEN bp.historyknown THEN bp.openingsold ELSE 0 END + bp.birdssold)::int,
        (CASE WHEN bp.historyknown THEN bp.openingculled ELSE 0 END + bp.birdsculled)::int,
        (CASE WHEN bp.historyknown THEN bp.openingtransferred ELSE 0 END + bp.birdstransferred)::int,
        CASE WHEN bp.historyknown THEN bp.openingother ELSE 0 END
    FROM   flock f
    CROSS  JOIN LATERAL public.fnflock_birdpositionasof(p_farmid, f.flockid, p_enddate) bp
    WHERE  f.farmid = p_farmid
      AND  (p_flockid IS NULL OR f.flockid = p_flockid)
      AND  (p_includeclosedflocks OR COALESCE(f.active, TRUE))
      AND  NOT COALESCE(f.isdeleted, FALSE)      -- 422: a deleted flock placed nothing
      AND  COALESCE(f.hasarrived, TRUE)          -- 422: nor did one whose birds have not arrived
    ORDER  BY f.name;
END
$function$;

-- ------------------------------------------------ Flock Production Summary
CREATE OR REPLACE FUNCTION public.sppoultryreport_flockproductionsummary(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeclosedflocks boolean DEFAULT false)
 RETURNS TABLE(flockid integer, flockname text, flockageweeks integer, birdsplaced integer, currentbirds integer, totaleggs bigint, peakdailyeggs bigint, productiondays integer, birddays bigint, brokeneggs bigint, feedconsumedkg numeric, deaths integer, active boolean)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH daily AS (
        SELECT r.flockid AS c_flockid, r.date AS c_date,
               SUM(r.totalproduction::bigint) AS c_dayeggs,
               SUM(r.noofbirdsleft::bigint)   AS c_daybirds
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate
        GROUP  BY r.flockid, r.date
    ),
    agg AS (
        SELECT d.c_flockid          AS c_flockid,
               SUM(d.c_dayeggs)     AS c_eggs,
               MAX(d.c_dayeggs)     AS c_peakdaily,
               COUNT(*)             AS c_days,
               SUM(d.c_daybirds)    AS c_birddays
        FROM   daily d
        GROUP  BY d.c_flockid
    ),
    loss AS (
        SELECT r.flockid AS c_flockid,
               SUM((COALESCE(r.brokeneggs,0)+COALESCE(r.meatyeggs,0)+COALESCE(r.softeggs,0)+COALESCE(r.losteggs,0))::bigint) AS c_broken,
               SUM(r.feedkg::numeric(18,2)) AS c_feed,
               SUM(r.mortality)             AS c_deaths
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate
        GROUP  BY r.flockid
    )
    SELECT
        f.flockid,
        f.name::text                                                                            AS flockname,
        -- DATEDIFF(WEEK, ...): SQL Server counts Monday-aligned week boundaries since 1900-01-01
        (((p_enddate - DATE '1900-01-01') / 7) - ((f.startdate - DATE '1900-01-01') / 7))       AS flockageweeks,
        (CASE WHEN bp.historyknown THEN bp.originallyplaced ELSE bp.openinglivebirds END)::int AS birdsplaced,   -- 421
        bp.currentlivebirds                                                                     AS currentbirds,   -- 421
        COALESCE(agg.c_eggs, 0)::bigint                                                         AS totaleggs,
        COALESCE(agg.c_peakdaily, 0)::bigint                                                    AS peakdailyeggs,
        COALESCE(agg.c_days, 0)::int                                                            AS productiondays,
        COALESCE(agg.c_birddays, 0)::bigint                                                     AS birddays,
        COALESCE(loss.c_broken, 0)::bigint                                                      AS brokeneggs,
        COALESCE(loss.c_feed, 0)                                                                AS feedconsumedkg,
        COALESCE(loss.c_deaths, 0)::int                                                         AS deaths,
        COALESCE(f.active, TRUE)                                                                AS active
    FROM   flock f
    LEFT JOIN agg  ON agg.c_flockid  = f.flockid
    LEFT JOIN loss ON loss.c_flockid = f.flockid
    CROSS JOIN LATERAL public.fnflock_birdpositionasof(p_farmid, f.flockid, p_enddate) bp
    WHERE  f.farmid = p_farmid
      AND  (p_flockid IS NULL OR f.flockid = p_flockid)
      AND  (p_includeclosedflocks OR COALESCE(f.active, TRUE))
      AND  NOT COALESCE(f.isdeleted, FALSE)      -- 422: a deleted flock placed nothing
      AND  COALESCE(f.hasarrived, TRUE)          -- 422: nor did one whose birds have not arrived
    ORDER  BY f.name;
END
$function$;

-- ------------------------------------------------ Farm Summary rows
CREATE OR REPLACE FUNCTION public.sppoultryreport_farmsummary_rs1(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeclosedflocks boolean DEFAULT false)
 RETURNS TABLE(flockid integer, flockname text, startingbirds integer, currentbirds integer, eggsproduced bigint, brokenrejectedeggs bigint, birddays bigint, feedconsumedkg numeric, deaths integer, salesrevenue numeric, expensesallocated numeric, active boolean)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_gid uuid;
BEGIN
    BEGIN
        v_gid := p_farmid::uuid;               -- TRY_CONVERT(UNIQUEIDENTIFIER, @FarmId)
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;

    RETURN QUERY
    WITH pr AS (
        SELECT r.flockid AS c_flockid,
               SUM(r.totalproduction::bigint)                                                                                     AS c_eggs,
               SUM((COALESCE(r.brokeneggs,0)+COALESCE(r.meatyeggs,0)+COALESCE(r.softeggs,0)+COALESCE(r.losteggs,0))::bigint)      AS c_broken,
               SUM(r.feedkg::numeric(18,2))                                                                                       AS c_feed,
               SUM(r.mortality)                                                                                                   AS c_deaths,
               SUM(r.noofbirdsleft::bigint)                                                                                       AS c_birddays
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate
        GROUP  BY r.flockid
    ),
    sa AS (
        SELECT s.flockid AS c_flockid,
               SUM(s.totalamount)                                                        AS c_revenue,
               SUM(CASE WHEN COALESCE(s.paid, TRUE) THEN s.totalamount ELSE 0 END)       AS c_paid
        FROM   sale s
        WHERE  s.status = 'Posted' AND s.farmid = p_farmid AND s.saledate >= p_startdate AND s.saledate < (p_enddate + 1)
        GROUP  BY s.flockid
    ),
    ex AS (
        SELECT e.flockid AS c_flockid, SUM(e.amount) AS c_expenses
        FROM   expense e
        WHERE  e.farmid = v_gid
          AND  e.expensedate >= p_startdate AND e.expensedate < (p_enddate + 1)
        GROUP  BY e.flockid
    )
    SELECT
        f.flockid,
        f.name::text                                            AS flockname,
        (CASE WHEN bp.historyknown THEN bp.originallyplaced ELSE bp.openinglivebirds END)::int AS startingbirds,   -- 421
        bp.currentlivebirds                                     AS currentbirds,    -- 421
        COALESCE(pr.c_eggs, 0)::bigint                          AS eggsproduced,
        COALESCE(pr.c_broken, 0)::bigint                        AS brokenrejectedeggs,
        COALESCE(pr.c_birddays, 0)::bigint                      AS birddays,
        COALESCE(pr.c_feed, 0)                                  AS feedconsumedkg,
        COALESCE(pr.c_deaths, 0)::int                           AS deaths,
        COALESCE(sa.c_revenue, 0)                               AS salesrevenue,
        COALESCE(ex.c_expenses, 0)                              AS expensesallocated,
        COALESCE(f.active, TRUE)                                AS active
    FROM   flock f
    LEFT JOIN pr ON pr.c_flockid = f.flockid
    LEFT JOIN sa ON sa.c_flockid = f.flockid
    LEFT JOIN ex ON ex.c_flockid = f.flockid
    CROSS JOIN LATERAL public.fnflock_birdpositionasof(p_farmid, f.flockid, p_enddate) bp
    WHERE  f.farmid = p_farmid
      AND  (p_flockid IS NULL OR f.flockid = p_flockid)
      AND  (p_includeclosedflocks OR COALESCE(f.active, TRUE))
      AND  NOT COALESCE(f.isdeleted, FALSE)      -- 422: a deleted flock placed nothing
      AND  COALESCE(f.hasarrived, TRUE)          -- 422: nor did one whose birds have not arrived
    ORDER  BY f.name;
END
$function$;

-- ----------------------------------------------------------- self-test ------
DO $t$
DECLARE v_bad integer;
BEGIN
    SELECT COUNT(*) INTO v_bad
    FROM   flock f
    CROSS  JOIN LATERAL public.sppoultryreport_endofflock(f.farmid, DATE '2999-12-31', f.flockid, TRUE) r
    WHERE  COALESCE(f.isdeleted, FALSE) OR NOT COALESCE(f.hasarrived, TRUE);
    IF v_bad > 0 THEN RAISE EXCEPTION '422: End of Flock still lists % deleted / not-arrived flock(s)', v_bad; END IF;

    SELECT COUNT(*) INTO v_bad
    FROM   flock f
    CROSS  JOIN LATERAL public.sppoultryreport_birdsonhand(f.farmid, DATE '2999-12-31', f.flockid, TRUE) r
    WHERE  COALESCE(f.isdeleted, FALSE) OR NOT COALESCE(f.hasarrived, TRUE);
    IF v_bad > 0 THEN RAISE EXCEPTION '422: Birds on Hand still lists % deleted / not-arrived flock(s)', v_bad; END IF;

    -- an arrived, not-deleted flock is still listed
    SELECT COUNT(*) INTO v_bad
    FROM   flock f
    WHERE  NOT COALESCE(f.isdeleted, FALSE) AND COALESCE(f.hasarrived, TRUE)
      AND  NOT EXISTS (SELECT 1 FROM public.sppoultryreport_endofflock(f.farmid, DATE '2999-12-31', f.flockid, TRUE));
    IF v_bad > 0 THEN RAISE EXCEPTION '422: % arrived flock(s) dropped from End of Flock', v_bad; END IF;
END
$t$;

COMMIT;
