-- =============================================================================
-- 419_FlockReportsOpeningPosition.postgres.sql   (requires 319, 338, 352, 389, 402, 406, 413, 418)
--
-- Purpose
-- -------
-- Flock- and batch-level reports read flock.quantity as "birds placed" and
-- SUM(productionrecords.mortality) as "deaths".  For a flock onboarded through
-- Initial Farm Setup (319) flock.quantity is the OPENING LIVE count, so every
-- such report silently dropped the opening historical reduction: the birds
-- that died, were sold, culled, transferred or otherwise lost before tracking
-- began.  A flock placed with 10,000 that had 7,500 left at onboarding showed
-- "Birds placed 7,500", 0 deaths and a 0% mortality.
--
-- fnflock_birdposition (413) already has the right answer.  This migration
-- makes every report read it.
--
-- The rule, everywhere
-- --------------------
--   Placed / started = originallyplaced; the opening LIVE count when the
--                      farm said the history is not known (its reduction is
--                      then an unknown adjustment, not mortality -- 319's rule,
--                      and the one 402's broiler KPIs already use).
--   Lifetime deaths  = opening historical mortality (history known) + recorded.
--   Sold / culled / transferred = opening + since tracking began.
--   Live             = currentlivebirds: the last count less sales, culls and
--                      transfers made after it.
--   A DATE-RANGE figure (deaths in this period, deaths per day) stays the
--   period's own: historical birds did not die on any of those dates.  The
--   cumulative mortality % is lifetime and includes them.
--
-- What changes
-- ------------
--  1. fnflock_birdpositionasof(farm, flock, asof)  -- fnflock_birdposition's
--     body with every movement limited to <= asof (NULL = no limit).  Reports
--     with an end date read the position as of that date.
--  2. fnflock_startedbirds(farm, flock) and sppoultryflock_positions(farm)
--     (every flock's position in one call, for the Flocks / Flock Purchases
--     pages).
--  3. sppoultryreport_endofflock      DROP + CREATE (new columns appended)
--  4. sppoultryreport_mortality       DROP + CREATE (deathsbefore appended)
--  5. sppoultryreport_birdsonhand     DROP + CREATE (new columns appended)
--  6. sppoultryreport_flockproductionsummary   same signature
--  7. sppoultryreport_farmsummary_rs1          same signature
--  8. sppoultryreport_profitlossbyflock        same signature (birdsplaced only)
--
-- Every body is the LIVE body (pg_get_functiondef, 2026-11-12) with only the
-- bird figures changed.  Three of them (mortality, flockproductionsummary,
-- birdsonhand) had no Postgres body in the repo at all.
--
-- For a flock with no opening position nothing changes except "live", which
-- now also subtracts sales / closeouts made after the last production record.
--
-- Deploy order: this migration, then the Farm API, then the web app.  The old
-- API reads columns by name, so it keeps working against the new functions.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- ------------------------------------------------ 1. position as of a date --
CREATE OR REPLACE FUNCTION public.fnflock_birdpositionasof(p_farmid text, p_flockid integer, p_asof date)
 RETURNS TABLE(flockid integer, hasopeningposition boolean, historyknown boolean, originallyplaced integer, openingmortality integer, openingsold integer, openingculled integer, openingtransferred integer, openingother integer, openinglivebirds integer, recordedmortality integer, productionrecordcount integer, lastcountedbirds integer, lastcountdate date, correction integer, birdssold integer, birdsculled integer, birdstransferred integer, currentlivebirds integer)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    -- fnflock_birdposition (413), movements limited to p_asof.  Keep the two
    -- in step: with p_asof NULL this returns exactly what that one does.
    RETURN QUERY
    WITH f AS (
        SELECT fl.flockid AS c_flockid, COALESCE(fl.quantity, 0) AS c_quantity,
               public.fnflock_quantityadjustments(p_farmid, p_flockid) AS c_qadj
        FROM   flock fl
        WHERE  fl.farmid = p_farmid AND fl.flockid = p_flockid
    ),
    o AS (
        SELECT op.*
        FROM   poultryopeningflockposition op
        WHERE  op.farmid = p_farmid AND op.flockid = p_flockid
        ORDER  BY op.openingpositionid DESC
        LIMIT  1
    ),
    pr AS (
        SELECT COALESCE(SUM(COALESCE(r.mortality, 0)), 0)::int AS c_mort,
               COUNT(*)::int                                    AS c_n
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.flockid = p_flockid
          AND  (p_asof IS NULL OR r.date <= p_asof)
    ),
    lr AS (
        SELECT r.noofbirdsleft AS c_left, r.date AS c_date, COALESCE(r.birdssoldreflected, 0) AS c_refl
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.flockid = p_flockid
          AND  (p_asof IS NULL OR r.date <= p_asof)
        ORDER  BY r.date DESC, r.id DESC
        LIMIT  1
    ),
    s AS (
        SELECT COALESCE(ROUND(SUM(sa.quantity)), 0)::int AS c_sold
        FROM   sale sa
        WHERE  sa.status = 'Posted' AND sa.farmid = p_farmid AND sa.flockid = p_flockid
          AND  fnpoultrysale_isbirdsale(sa.product)
          AND  (p_asof IS NULL OR sa.saledate < (p_asof + 1))
    ),
    d AS (
        SELECT COALESCE(SUM(x.quantity) FILTER (WHERE x.disposition = 'Cull'), 0)::int     AS c_culled,
               COALESCE(SUM(x.quantity) FILTER (WHERE x.disposition = 'Transfer'), 0)::int AS c_transferred
        FROM   flockcloseoutdispositions x
        JOIN   flockcloseouts c ON c.closeoutid = x.closeoutid
        WHERE  x.farmid = p_farmid AND x.flockid = p_flockid
          AND  x.reversedat IS NULL AND c.reopenedat IS NULL
          AND  (p_asof IS NULL OR c.closeddate <= p_asof)
    )
    SELECT
        f.c_flockid,
        (o.openingpositionid IS NOT NULL),
        COALESCE(o.historyknown, TRUE),
        COALESCE(o.originallyplaced, f.c_quantity - f.c_qadj),
        COALESCE(o.historicalmortality, 0),
        COALESCE(o.historicalsold, 0),
        COALESCE(o.historicalculled, 0),
        COALESCE(o.historicaltransferred, 0),
        COALESCE(o.otheradjustment, 0),
        f.c_quantity - f.c_qadj,
        pr.c_mort,
        pr.c_n,
        GREATEST(COALESCE(lr.c_left, f.c_quantity), 0),
        lr.c_date,
        CASE WHEN lr.c_date IS NULL THEN 0
             ELSE GREATEST(COALESCE(lr.c_left, f.c_quantity), 0) - (f.c_quantity - pr.c_mort)
        END,
        s.c_sold,
        d.c_culled,
        d.c_transferred,
        GREATEST(COALESCE(lr.c_left, f.c_quantity), 0) - (s.c_sold - COALESCE(lr.c_refl, 0)) - d.c_culled - d.c_transferred
    FROM   f
    CROSS  JOIN pr
    CROSS  JOIN s
    CROSS  JOIN d
    LEFT   JOIN o  ON TRUE
    LEFT   JOIN lr ON TRUE;
END
$function$;

-- ------------------------------------------------ 2. helpers ---------------
-- Birds the flock STARTED with: placed, or the opening live count when the
-- history is not known (its reduction is not mortality).
CREATE OR REPLACE FUNCTION public.fnflock_startedbirds(p_farmid text, p_flockid integer)
RETURNS integer LANGUAGE sql STABLE AS $f$
    SELECT (CASE WHEN bp.historyknown THEN bp.originallyplaced ELSE bp.openinglivebirds END)::int
    FROM   public.fnflock_birdposition(p_farmid, p_flockid) bp;
$f$;

-- Every flock's position in one call.
CREATE OR REPLACE FUNCTION public.sppoultryflock_positions(p_farmid text)
 RETURNS TABLE(flockid integer, batchid integer, isclosed boolean, isdeleted boolean,
               hasopeningposition boolean, historyknown boolean, originallyplaced integer,
               openingmortality integer, openingsold integer, openingculled integer,
               openingtransferred integer, openingother integer, openinglivebirds integer,
               recordedmortality integer, productionrecordcount integer, lastcountedbirds integer,
               lastcountdate date, correction integer, birdssold integer, birdsculled integer,
               birdstransferred integer, currentlivebirds integer, startedbirds integer)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT f.flockid, f.batchid, (f.closeddate IS NOT NULL), COALESCE(f.isdeleted, FALSE),
           bp.hasopeningposition, bp.historyknown, bp.originallyplaced,
           bp.openingmortality, bp.openingsold, bp.openingculled,
           bp.openingtransferred, bp.openingother, bp.openinglivebirds,
           bp.recordedmortality, bp.productionrecordcount, bp.lastcountedbirds,
           bp.lastcountdate, bp.correction, bp.birdssold, bp.birdsculled,
           bp.birdstransferred, bp.currentlivebirds,
           (CASE WHEN bp.historyknown THEN bp.originallyplaced ELSE bp.openinglivebirds END)::int
    FROM   flock f
    CROSS  JOIN LATERAL public.fnflock_birdposition(p_farmid, f.flockid) bp
    WHERE  f.farmid = p_farmid
    ORDER  BY f.flockid;
$function$;


-- ------------------------------------------------ 3. End of Flock ------
DROP FUNCTION IF EXISTS public.sppoultryreport_endofflock(text, date, integer, boolean);
CREATE FUNCTION public.sppoultryreport_endofflock(p_farmid text, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeactiveflocks boolean DEFAULT true)
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
        -- 419: placed / deaths / remaining from the flock's bird position as of
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
    ORDER  BY f.name;
END
$function$;

-- ------------------------------------------------ 4. Mortality ---------
DROP FUNCTION IF EXISTS public.sppoultryreport_mortality(text, date, date, integer);
CREATE FUNCTION public.sppoultryreport_mortality(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer)
 RETURNS TABLE(date date, flockid integer, flockname text, openingbirds integer, deaths integer, closingbirds integer, birdsplaced integer, notes text, deathsbefore integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    -- 419: one bird position per flock. birdsplaced is the birds the flock
    -- STARTED with (originally placed; opening live when the history is
    -- unknown) and deathsbefore is every death before the start date
    -- (opening historical mortality + recorded), so the cumulative % is
    -- lifetime and not just the selected days.
    WITH pos AS (
        SELECT f.flockid AS c_flockid,
               (CASE WHEN bp.historyknown THEN bp.originallyplaced ELSE bp.openinglivebirds END)::int AS c_started,
               (CASE WHEN bp.historyknown THEN bp.openingmortality ELSE 0 END
                + COALESCE((SELECT SUM(r.mortality) FROM productionrecords r
                            WHERE r.farmid = f.farmid AND r.flockid = f.flockid AND r.date < p_startdate), 0))::int AS c_before
        FROM   flock f CROSS JOIN LATERAL public.fnflock_birdposition(p_farmid, f.flockid) bp
        WHERE  f.farmid = p_farmid AND (p_flockid IS NULL OR f.flockid = p_flockid)
    )
    SELECT
        pr.date                                 AS date,
        pr.flockid                              AS flockid,
        COALESCE(f.name, 'Unassigned')::text    AS flockname,
        SUM(pr.noofbirds)::int                  AS openingbirds,
        SUM(pr.mortality)::int                  AS deaths,
        SUM(pr.noofbirdsleft)::int              AS closingbirds,
        COALESCE(pos.c_started, 0)              AS birdsplaced,
        MAX(pr.notes)::text                     AS notes,
        COALESCE(pos.c_before, 0)               AS deathsbefore
    FROM   productionrecords pr
    LEFT JOIN flock f ON f.flockid = pr.flockid AND f.farmid = pr.farmid
    LEFT JOIN pos     ON pos.c_flockid = pr.flockid
    WHERE  pr.farmid = p_farmid AND pr.date >= p_startdate AND pr.date <= p_enddate
      AND  (p_flockid IS NULL OR pr.flockid = p_flockid)
    GROUP  BY pr.date, pr.flockid, f.name, pos.c_started, pos.c_before
    ORDER  BY pr.flockid, pr.date;
END
$function$;

-- ------------------------------------------------ 5. Birds on Hand -----
DROP FUNCTION IF EXISTS public.sppoultryreport_birdsonhand(text, date, integer, boolean);
CREATE FUNCTION public.sppoultryreport_birdsonhand(p_farmid text, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeclosedflocks boolean DEFAULT false)
 RETURNS TABLE(flockid integer, flockname text, birdsplaced integer, deaths integer, currentrecordedbirds integer,
               historyknown boolean, openingmortality integer, birdssold integer, birdsculled integer,
               birdstransferred integer, otherreductions integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- 419: every figure from the flock's bird position as of the end date.
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
      AND  NOT COALESCE(f.isdeleted, FALSE)
    ORDER  BY f.name;
END
$function$;

-- ------------------------------------------------ 6. Flock Production Summary (same signature)
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
        (CASE WHEN bp.historyknown THEN bp.originallyplaced ELSE bp.openinglivebirds END)::int AS birdsplaced,   -- 419
        bp.currentlivebirds                                                                     AS currentbirds,   -- 419
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
    ORDER  BY f.name;
END
$function$;

-- ------------------------------------------------ 7. Farm Summary rows (same signature)
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
        (CASE WHEN bp.historyknown THEN bp.originallyplaced ELSE bp.openinglivebirds END)::int AS startingbirds,   -- 419
        bp.currentlivebirds                                     AS currentbirds,    -- 419
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
    ORDER  BY f.name;
END
$function$;

-- ------------------------------------------------ 8. P&L by Flock (same signature)
CREATE OR REPLACE FUNCTION public.sppoultryreport_profitlossbyflock(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeclosedflocks boolean DEFAULT false)
 RETURNS TABLE(flockid integer, flockname text, birdsplaced integer, eggrevenue numeric, birdsalesrevenue numeric, otherrevenue numeric, totalrevenue numeric, eggsproduced bigint, feedcost numeric, medicinevaccinecost numeric, laborcost numeric, otherexpenses numeric, active boolean, birdcost numeric)
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
    WITH rev AS (
        SELECT s.flockid AS c_flockid,
            -- 375: byproducts are neither eggs nor live birds (they count in total revenue)
            SUM(CASE WHEN s.product ILIKE '%egg%' AND fnpoultrysale_byproductrole(s.product) IS NULL THEN s.totalamount ELSE 0 END) AS c_eggrevenue,
            SUM(CASE WHEN s.product NOT ILIKE '%egg%' AND fnpoultrysale_byproductrole(s.product) IS NULL AND (
                     s.product ILIKE '%bird%'     OR s.product ILIKE '%layer%'  OR s.product ILIKE '%broiler%'
                  OR s.product ILIKE '%cockerel%' OR s.product ILIKE '%chick%'  OR s.product ILIKE '%cock%'
                  OR s.product ILIKE '%hen%'      OR s.product ILIKE '%spent%'  OR s.product ILIKE '%pullet%'
                  OR s.product ILIKE '%fowl%'     OR s.product ILIKE '%culled%')
                THEN s.totalamount ELSE 0 END)                                                      AS c_birdrevenue,
            SUM(s.totalamount)                                                                      AS c_revenue
        FROM   sale s
        WHERE  s.status = 'Posted' AND s.farmid = p_farmid
          AND  s.saledate >= p_startdate AND s.saledate < (p_enddate + 1)
        GROUP  BY s.flockid
    ),
    eggs AS (
        SELECT r.flockid AS c_flockid, SUM(r.totalproduction::bigint) AS c_eggs
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate
        GROUP  BY r.flockid
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
        WHERE  e.farmid = v_gid
          AND  e.expensedate >= p_startdate AND e.expensedate < (p_enddate + 1)
          AND  COALESCE(e.sourcetype, '') <> 'MainFlockBatch'     -- 400: the chick purchase is birdcost below
        GROUP  BY e.flockid
    ),
    -- 400: the chick purchase, shared by birds placed (as fnflock_lifetimesummary
    -- shares it), charged in the period the flock started.
    chicks AS (
        SELECT f.flockid AS c_flockid,
               ROUND(b.totalcost * p.originallyplaced / b.numberofbirds, 2) AS c_birdcost
        FROM   flock f
        JOIN   mainflockbatch b ON b.batchid = f.batchid AND b.farmid = f.farmid
        CROSS  JOIN LATERAL fnflock_birdposition(p_farmid, f.flockid) p
        WHERE  f.farmid = p_farmid
          AND  (p_flockid IS NULL OR f.flockid = p_flockid)
          AND  NOT COALESCE(f.isdeleted, FALSE)
          AND  f.startdate >= p_startdate AND f.startdate <= p_enddate
          AND  COALESCE(b.totalcost, 0) > 0 AND COALESCE(b.numberofbirds, 0) > 0
    )
    SELECT
        f.flockid,
        f.name::text                                                                                AS flockname,
        public.fnflock_startedbirds(p_farmid, f.flockid)                                            AS birdsplaced,   -- 419
        COALESCE(rev.c_eggrevenue, 0)                                                               AS eggrevenue,
        COALESCE(rev.c_birdrevenue, 0)                                                              AS birdsalesrevenue,
        COALESCE(rev.c_revenue, 0) - COALESCE(rev.c_eggrevenue, 0) - COALESCE(rev.c_birdrevenue, 0) AS otherrevenue,
        COALESCE(rev.c_revenue, 0)                                                                  AS totalrevenue,
        COALESCE(eggs.c_eggs, 0)::bigint                                                            AS eggsproduced,
        COALESCE(cost.c_feedcost, 0)                                                                AS feedcost,
        COALESCE(cost.c_medcost, 0)                                                                 AS medicinevaccinecost,
        COALESCE(cost.c_laborcost, 0)                                                               AS laborcost,
        COALESCE(cost.c_othercost, 0)                                                               AS otherexpenses,
        COALESCE(f.active, TRUE)                                                                    AS active,
        COALESCE(chicks.c_birdcost, 0)                                                              AS birdcost
    FROM   flock f
    LEFT JOIN rev    ON rev.c_flockid    = f.flockid
    LEFT JOIN eggs   ON eggs.c_flockid   = f.flockid
    LEFT JOIN cost   ON cost.c_flockid   = f.flockid
    LEFT JOIN chicks ON chicks.c_flockid = f.flockid
    WHERE  f.farmid = p_farmid
      AND  (p_flockid IS NULL OR f.flockid = p_flockid)
      AND  (p_includeclosedflocks OR COALESCE(f.active, TRUE))
    ORDER  BY f.name;
END
$function$;

-- ------------------------------------------------ 9. grants ----------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.fnflock_birdpositionasof(text, integer, date) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.fnflock_startedbirds(text, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryflock_positions(text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryreport_endofflock(text, date, integer, boolean) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryreport_mortality(text, date, date, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryreport_birdsonhand(text, date, integer, boolean) TO poultryapp;
    END IF;
END
$grants$;

-- ------------------------------------------------ 10. self-test ------------
DO $t$
DECLARE v_bad integer;
BEGIN
    -- (a) with no date limit the as-of position IS fnflock_birdposition
    SELECT COUNT(*) INTO v_bad
    FROM   flock f
    CROSS  JOIN LATERAL public.fnflock_birdposition(f.farmid, f.flockid) a
    CROSS  JOIN LATERAL public.fnflock_birdpositionasof(f.farmid, f.flockid, NULL) b
    WHERE  ROW(a.*) IS DISTINCT FROM ROW(b.*);
    IF v_bad > 0 THEN RAISE EXCEPTION '419: as-of position differs from fnflock_birdposition for % flock(s)', v_bad; END IF;

    -- (b) ... and as of a far-future date too
    SELECT COUNT(*) INTO v_bad
    FROM   flock f
    CROSS  JOIN LATERAL public.fnflock_birdposition(f.farmid, f.flockid) a
    CROSS  JOIN LATERAL public.fnflock_birdpositionasof(f.farmid, f.flockid, DATE '2999-12-31') b
    WHERE  ROW(a.*) IS DISTINCT FROM ROW(b.*);
    IF v_bad > 0 THEN RAISE EXCEPTION '419: as-of(2999) position differs for % flock(s)', v_bad; END IF;

    -- (c) a flock WITHOUT an opening position reports exactly what it did:
    --     placed = flock.quantity (less FlockQuantity adjustments)
    SELECT COUNT(*) INTO v_bad
    FROM   flock f
    CROSS  JOIN LATERAL public.sppoultryreport_birdsonhand(f.farmid, DATE '2999-12-31', f.flockid, TRUE) r
    WHERE  NOT EXISTS (SELECT 1 FROM poultryopeningflockposition o WHERE o.farmid = f.farmid AND o.flockid = f.flockid)
      AND  r.birdsplaced <> COALESCE(f.quantity, 0) - public.fnflock_quantityadjustments(f.farmid, f.flockid);
    IF v_bad > 0 THEN RAISE EXCEPTION '419: % flock(s) without an opening position changed their placed figure', v_bad; END IF;

    -- (d) a flock WITH a known opening position reports its originally placed
    SELECT COUNT(*) INTO v_bad
    FROM   poultryopeningflockposition o
    JOIN   flock f ON f.farmid = o.farmid AND f.flockid = o.flockid
    CROSS  JOIN LATERAL public.sppoultryreport_birdsonhand(f.farmid, DATE '2999-12-31', f.flockid, TRUE) r
    WHERE  o.historyknown
      AND  o.openingpositionid = (SELECT MAX(o2.openingpositionid) FROM poultryopeningflockposition o2
                                  WHERE o2.farmid = o.farmid AND o2.flockid = o.flockid)
      AND  NOT COALESCE(f.isdeleted, FALSE)
      AND  r.birdsplaced <> o.originallyplaced;
    IF v_bad > 0 THEN RAISE EXCEPTION '419: % opening flock(s) do not report their originally placed birds', v_bad; END IF;
END
$t$;

COMMIT;
