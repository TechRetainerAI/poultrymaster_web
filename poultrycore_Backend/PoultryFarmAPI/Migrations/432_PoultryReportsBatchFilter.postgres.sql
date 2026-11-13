-- =============================================================================
-- 432_PoultryReportsBatchFilter.postgres.sql   (requires 422)
--
-- Purpose
-- -------
-- Every advanced poultry report that has a Flock filter gets a Batch filter
-- too.  A batch = the flocks whose flock.batchid is that batch.  Picking a
-- batch narrows the report to those flocks; picking a batch AND a flock needs
-- both to match.  Rows not traced to any flock (pooled byproducts, expenses
-- with no flock) drop out under a batch filter, as they do under a flock one.
--
-- What this does
-- --------------
-- The 20 report functions that take p_flockid get one more parameter,
-- p_batchid integer DEFAULT NULL, appended LAST.  Each existing
--     (p_flockid IS NULL OR x.flockid = p_flockid)
-- becomes
--     ((p_flockid IS NULL OR x.flockid = p_flockid)
--      AND (p_batchid IS NULL OR x.flockid IN (flocks of the batch)))
-- Nothing else in the bodies changes; they are the live definitions as of
-- 2026-11-12 (after 420-422).  With p_batchid NULL every result is identical.
--
-- Because the signature changes, each function is DROPped and re-created
-- (CREATE OR REPLACE would leave an ambiguous overload).  No other database
-- function calls these; positional/named callers without p_batchid still work.
--
-- Deploy order: this migration, then the API (it only sends p_batchid when a
-- batch is picked, so the API also runs fine before this is applied), then web.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- birdsonhand: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_birdsonhand(p_farmid text, p_enddate date, p_flockid integer, p_includeclosedflocks boolean);
CREATE FUNCTION public.sppoultryreport_birdsonhand(p_farmid text, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeclosedflocks boolean DEFAULT false, p_batchid integer DEFAULT NULL::integer)
 RETURNS TABLE(flockid integer, flockname text, birdsplaced integer, deaths integer, currentrecordedbirds integer, historyknown boolean, openingmortality integer, birdssold integer, birdsculled integer, birdstransferred integer, otherreductions integer)
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
      AND  ((p_flockid IS NULL OR f.flockid = p_flockid) AND (p_batchid IS NULL OR f.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))
      AND  (p_includeclosedflocks OR COALESCE(f.active, TRUE))
      AND  NOT COALESCE(f.isdeleted, FALSE)      -- 420: a deleted flock placed nothing
      AND  COALESCE(f.hasarrived, TRUE)          -- 420: nor did one whose birds have not arrived
    ORDER  BY f.name;
END
$function$;

-- byproducts: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_byproducts(p_farmid text, p_startdate date, p_enddate date, p_flockid integer, p_role text, p_byflock boolean);
CREATE FUNCTION public.sppoultryreport_byproducts(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_role text DEFAULT NULL::text, p_byflock boolean DEFAULT true, p_batchid integer DEFAULT NULL::integer)
 RETURNS TABLE(role text, productname text, flockid integer, flockname text, batchid integer, batchcode text, opening numeric, generated numeric, sold numeric, disposed numeric, internaluse numeric, manualin numeric, manualout numeric, reversals numeric, closing numeric, revenue numeric, unitsoldprice numeric)
 LANGUAGE sql
 STABLE
AS $function$

    WITH l AS (

        SELECT x.*, CASE WHEN p_byflock THEN x.flockid END AS gflock

        FROM   fnpoultry_byproductledger(p_farmid) x

        WHERE  x.bdate <= p_enddate

          AND  ((p_flockid IS NULL OR x.flockid = p_flockid) AND (p_batchid IS NULL OR x.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))

          AND  (p_role IS NULL OR x.role = p_role)

    ),

    roles AS (   -- both byproducts always appear for the company, even at zero

        SELECT p.systemrole AS role, p.name::text AS productname

        FROM   poultryproducts p

        WHERE  p.farmid = p_farmid AND p.systemrole IS NOT NULL AND (p_role IS NULL OR p.systemrole = p_role)

    ),

    g AS (

        SELECT l.role, l.gflock,

               SUM(l.quantity) FILTER (WHERE l.bdate < p_startdate)                                   AS opening,

               SUM(l.quantity) FILTER (WHERE l.bdate >= p_startdate AND l.category = 'Generated')    AS generated,

               -SUM(l.quantity) FILTER (WHERE l.bdate >= p_startdate AND l.category = 'Sold')        AS sold,

               -SUM(l.quantity) FILTER (WHERE l.bdate >= p_startdate AND l.category = 'Disposed')    AS disposed,

               -SUM(l.quantity) FILTER (WHERE l.bdate >= p_startdate AND l.category = 'InternalUse') AS internaluse,

               SUM(l.quantity) FILTER (WHERE l.bdate >= p_startdate AND l.category = 'ManualIn')     AS manualin,

               -SUM(l.quantity) FILTER (WHERE l.bdate >= p_startdate AND l.category = 'ManualOut')   AS manualout,

               SUM(l.quantity) FILTER (WHERE l.bdate >= p_startdate AND l.category = 'Reversal')     AS reversals,

               SUM(l.quantity)                                                                        AS closing,

               SUM(l.revenue) FILTER (WHERE l.bdate >= p_startdate)                                   AS revenue

        FROM   l

        GROUP  BY l.role, l.gflock

    )

    SELECT r.role, r.productname, g.gflock, f.name::text, f.batchid, b.batchcode::text,

           COALESCE(g.opening, 0), COALESCE(g.generated, 0), COALESCE(g.sold, 0), COALESCE(g.disposed, 0),

           COALESCE(g.internaluse, 0), COALESCE(g.manualin, 0), COALESCE(g.manualout, 0), COALESCE(g.reversals, 0),

           COALESCE(g.closing, 0), COALESCE(g.revenue, 0),

           CASE WHEN COALESCE(g.sold, 0) > 0 THEN round(COALESCE(g.revenue, 0) / g.sold, 2) END

    FROM   roles r

    LEFT   JOIN g ON g.role = r.role

    LEFT   JOIN flock f ON f.flockid = g.gflock

    LEFT   JOIN mainflockbatch b ON b.batchid = f.batchid

    -- A flock filter shows only that flock's rows; without one, a byproduct

    -- with no movement at all still shows once, at zero.

    WHERE  (g.role IS NOT NULL OR (p_flockid IS NULL AND p_batchid IS NULL))

    ORDER  BY r.role, f.name NULLS LAST;

$function$;

-- costperegg: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_costperegg(p_farmid text, p_startdate date, p_enddate date, p_flockid integer, p_includeclosedflocks boolean);
CREATE FUNCTION public.sppoultryreport_costperegg(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeclosedflocks boolean DEFAULT false, p_batchid integer DEFAULT NULL::integer)
 RETURNS TABLE(flockid integer, flockname text, eggsproduced bigint, feedcost numeric, medicinevaccinecost numeric, laborcost numeric, totalallocatedcost numeric, sellingpriceperunit numeric)
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

    WITH eggs AS (

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

            SUM(e.amount)                                                                           AS c_totalcost

        FROM   expense e

        WHERE  e.farmid = v_gid

          AND  e.expensedate >= p_startdate AND e.expensedate < (p_enddate + 1)

        GROUP  BY e.flockid

    ),

    avgprice AS (

        SELECT s.flockid AS c_flockid,

               CASE WHEN SUM(s.quantity) = 0 THEN NULL

                    ELSE SUM(s.totalamount) / NULLIF(SUM(s.quantity), 0) END                        AS c_avgunitprice

        FROM   sale s

        WHERE  s.status = 'Posted' AND s.farmid = p_farmid

          AND  s.saledate >= p_startdate AND s.saledate < (p_enddate + 1)

        GROUP  BY s.flockid

    )

    SELECT

        f.flockid,

        f.name::text                          AS flockname,

        COALESCE(eggs.c_eggs, 0)::bigint      AS eggsproduced,

        COALESCE(cost.c_feedcost, 0)          AS feedcost,

        COALESCE(cost.c_medcost, 0)           AS medicinevaccinecost,

        COALESCE(cost.c_laborcost, 0)         AS laborcost,

        COALESCE(cost.c_totalcost, 0)         AS totalallocatedcost,

        avgprice.c_avgunitprice               AS sellingpriceperunit

    FROM   flock f

    LEFT JOIN eggs     ON eggs.c_flockid     = f.flockid

    LEFT JOIN cost     ON cost.c_flockid     = f.flockid

    LEFT JOIN avgprice ON avgprice.c_flockid = f.flockid

    WHERE  f.farmid = p_farmid

      AND  ((p_flockid IS NULL OR f.flockid = p_flockid) AND (p_batchid IS NULL OR f.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))

      AND  (p_includeclosedflocks OR COALESCE(f.active, TRUE))

    ORDER  BY f.name;

END

$function$;

-- dailyeggproduction: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_dailyeggproduction(p_farmid text, p_startdate date, p_enddate date, p_flockid integer);
CREATE FUNCTION public.sppoultryreport_dailyeggproduction(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_batchid integer DEFAULT NULL::integer)
 RETURNS TABLE(date date, flockid integer, flockname text, ageinweeks integer, morningeggs integer, middayeggs integer, eveningeggs integer, fourthpickeggs integer, fifthpickeggs integer, sixthpickeggs integer, totaleggs bigint, brokeneggs bigint, birdcount bigint, notes text)
 LANGUAGE plpgsql
AS $function$

BEGIN

    RETURN QUERY

    SELECT

        pr.date                                                                                                                AS date,

        pr.flockid                                                                                                             AS flockid,

        COALESCE(f.name, 'Unassigned')::text                                                                                   AS flockname,

        MAX(pr.ageinweeks)                                                                                                     AS ageinweeks,

        SUM(pr.production9am)::int                                                                                             AS morningeggs,

        SUM(pr.production12pm)::int                                                                                            AS middayeggs,

        SUM(pr.production4pm)::int                                                                                             AS eveningeggs,

        SUM(COALESCE(pr.production4thpick, 0))::int                                                                            AS fourthpickeggs,

        SUM(COALESCE(pr.production5thpick, 0))::int                                                                            AS fifthpickeggs,

        SUM(COALESCE(pr.production6thpick, 0))::int                                                                            AS sixthpickeggs,

        SUM(pr.totalproduction::bigint)::bigint                                                                                AS totaleggs,

        SUM((COALESCE(pr.brokeneggs,0)+COALESCE(pr.meatyeggs,0)+COALESCE(pr.softeggs,0)+COALESCE(pr.losteggs,0))::bigint)::bigint AS brokeneggs,

        SUM(pr.noofbirdsleft::bigint)::bigint                                                                                  AS birdcount,

        MAX(pr.notes)::text                                                                                                    AS notes

    FROM   productionrecords pr

    LEFT JOIN flock f ON f.flockid = pr.flockid AND f.farmid = pr.farmid

    WHERE  pr.farmid = p_farmid AND pr.date >= p_startdate AND pr.date <= p_enddate AND pr.sourcetype <> 'FeedUsage'

      AND  ((p_flockid IS NULL OR pr.flockid = p_flockid) AND (p_batchid IS NULL OR pr.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))

    GROUP  BY pr.date, pr.flockid, f.name

    ORDER  BY pr.date DESC, f.name;

END

$function$;

-- eggsales_rs1: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_eggsales_rs1(p_farmid text, p_startdate date, p_enddate date, p_flockid integer, p_customername text);
CREATE FUNCTION public.sppoultryreport_eggsales_rs1(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_customername text DEFAULT NULL::text, p_batchid integer DEFAULT NULL::integer)
 RETURNS TABLE(date date, saleid integer, customer text, product text, size text, quantitysold numeric, unitprice numeric, totalamount numeric, paid boolean, amountpaid numeric, paymentmethod text, flockid integer, lineno integer, qtyboxes integer, qtycrates integer, qtypieces integer, eggspercrate integer, cratesperbox integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        s.saledate::date                AS date,
        s.saleid                        AS saleid,
        s.customername::text            AS customer,
        l.product::text                 AS product,
        l.size::text                    AS size,
        l.quantity                      AS quantitysold,
        l.unitprice                     AS unitprice,
        l.totalamount                   AS totalamount,
        COALESCE(s.paid, TRUE)          AS paid,
        CASE WHEN COALESCE(s.paid, TRUE) THEN l.totalamount
             WHEN s.totalamount > 0 THEN round(COALESCE(s.amountpaid, 0) * l.totalamount / s.totalamount, 2)
             ELSE 0 END                 AS amountpaid,
        s.paymentmethod::text           AS paymentmethod,
        s.flockid                       AS flockid,
        -- 396: the line and how it was entered (NULL before 394)
        l.lineno                        AS lineno,
        l.qtyboxes                      AS qtyboxes,
        l.qtycrates                     AS qtycrates,
        l.qtypieces                     AS qtypieces,
        l.eggspercrate                  AS eggspercrate,
        l.cratesperbox                  AS cratesperbox
    FROM   sale s
    JOIN   saleline l ON l.saleid = s.saleid
    WHERE  s.status = 'Posted' AND s.farmid = p_farmid
      AND  s.saledate >= p_startdate AND s.saledate < (p_enddate + 1)
      AND  ((p_flockid IS NULL OR s.flockid = p_flockid) AND (p_batchid IS NULL OR s.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))
      AND  (p_customername IS NULL OR s.customername = p_customername)
      AND  COALESCE(l.product, '') ILIKE '%egg%'
    ORDER  BY s.saledate DESC, s.saleid DESC, l.lineno;
END
$function$;

-- eggsales_rs2: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_eggsales_rs2(p_farmid text, p_startdate date, p_enddate date, p_flockid integer, p_customername text);
CREATE FUNCTION public.sppoultryreport_eggsales_rs2(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_customername text DEFAULT NULL::text, p_batchid integer DEFAULT NULL::integer)
 RETURNS TABLE(excludedcount integer, excludedamount numeric)
 LANGUAGE plpgsql
AS $function$

BEGIN

    RETURN QUERY

    SELECT

        COUNT(*)::int                       AS excludedcount,

        COALESCE(SUM(s.totalamount), 0)     AS excludedamount

    FROM   sale s

    WHERE  s.status = 'Posted' AND s.farmid = p_farmid

      AND  s.saledate >= p_startdate AND s.saledate < (p_enddate + 1)

      AND  ((p_flockid IS NULL OR s.flockid = p_flockid) AND (p_batchid IS NULL OR s.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))

      AND  (p_customername IS NULL OR s.customername = p_customername)

      AND  COALESCE(s.product, '') NOT ILIKE '%egg%';

END

$function$;

-- endofflock: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_endofflock(p_farmid text, p_enddate date, p_flockid integer, p_includeactiveflocks boolean);
CREATE FUNCTION public.sppoultryreport_endofflock(p_farmid text, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeactiveflocks boolean DEFAULT true, p_batchid integer DEFAULT NULL::integer)
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
      AND  ((p_flockid IS NULL OR f.flockid = p_flockid) AND (p_batchid IS NULL OR f.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))
      AND  (p_includeactiveflocks OR NOT COALESCE(f.active, TRUE))
      AND  NOT COALESCE(f.isdeleted, FALSE)      -- 420: a deleted flock placed nothing
      AND  COALESCE(f.hasarrived, TRUE)          -- 420: nor did one whose birds have not arrived
    ORDER  BY f.name;
END
$function$;

-- expensesummary: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_expensesummary(p_farmid text, p_startdate date, p_enddate date, p_flockid integer, p_supplier text, p_category text);
CREATE FUNCTION public.sppoultryreport_expensesummary(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_supplier text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_batchid integer DEFAULT NULL::integer)
 RETURNS TABLE(date date, expenseid integer, category text, description text, supplier text, amount numeric, paymentmethod text, sourcetype text, flockid integer, flockname text, createdby text)
 LANGUAGE plpgsql
AS $function$

DECLARE

    v_gid uuid;

BEGIN

    BEGIN

        v_gid := p_farmid::uuid;

    EXCEPTION WHEN OTHERS THEN

        v_gid := NULL;

    END;



    RETURN QUERY

    SELECT

        e.expensedate::date         AS date,

        e.expenseid                 AS expenseid,

        e.category::text            AS category,

        e.description::text         AS description,

        e.supplier::text            AS supplier,

        e.amount                    AS amount,

        e.paymentmethod::text       AS paymentmethod,

        e.sourcetype::text          AS sourcetype,

        e.flockid                   AS flockid,

        f.name::text                AS flockname,

        e.userid::text              AS createdby

    FROM   expense e

    LEFT JOIN flock f ON f.flockid = e.flockid AND f.farmid = p_farmid

    WHERE  e.farmid = v_gid

      AND  e.expensedate >= p_startdate AND e.expensedate < (p_enddate + 1)

      AND  ((p_flockid IS NULL OR e.flockid = p_flockid) AND (p_batchid IS NULL OR e.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))

      AND  (p_supplier IS NULL OR e.supplier = p_supplier)

      AND  (NULLIF(btrim(COALESCE(p_category, '')), '') IS NULL

            OR lower(btrim(e.category)) = lower(btrim(p_category)))

    ORDER  BY e.expensedate DESC, e.expenseid DESC;

END

$function$;

-- farmsummary_rs1: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_farmsummary_rs1(p_farmid text, p_startdate date, p_enddate date, p_flockid integer, p_includeclosedflocks boolean);
CREATE FUNCTION public.sppoultryreport_farmsummary_rs1(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeclosedflocks boolean DEFAULT false, p_batchid integer DEFAULT NULL::integer)
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
      AND  ((p_flockid IS NULL OR f.flockid = p_flockid) AND (p_batchid IS NULL OR f.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))
      AND  (p_includeclosedflocks OR COALESCE(f.active, TRUE))
      AND  NOT COALESCE(f.isdeleted, FALSE)      -- 420: a deleted flock placed nothing
      AND  COALESCE(f.hasarrived, TRUE)          -- 420: nor did one whose birds have not arrived
    ORDER  BY f.name;
END
$function$;

-- farmsummary_rs2: 9 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_farmsummary_rs2(p_farmid text, p_startdate date, p_enddate date, p_flockid integer, p_includeclosedflocks boolean);
CREATE FUNCTION public.sppoultryreport_farmsummary_rs2(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeclosedflocks boolean DEFAULT false, p_batchid integer DEFAULT NULL::integer)
 RETURNS TABLE(totaleggs bigint, brokenrejectedeggs bigint, deaths integer, feedconsumedkg numeric, salesrevenue numeric, cashcollected numeric, customerreceivables numeric, expenses numeric, activeflocks integer)
 LANGUAGE plpgsql
AS $function$

DECLARE

    v_gid uuid;

BEGIN

    BEGIN

        v_gid := p_farmid::uuid;

    EXCEPTION WHEN OTHERS THEN

        v_gid := NULL;

    END;



    RETURN QUERY

    SELECT

        COALESCE((SELECT SUM(r.totalproduction::bigint) FROM productionrecords r

                  WHERE r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate

                    AND ((p_flockid IS NULL OR r.flockid = p_flockid) AND (p_batchid IS NULL OR r.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))), 0)::bigint              AS totaleggs,

        COALESCE((SELECT SUM((COALESCE(r.brokeneggs,0)+COALESCE(r.meatyeggs,0)+COALESCE(r.softeggs,0)+COALESCE(r.losteggs,0))::bigint)

                  FROM productionrecords r

                  WHERE r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate

                    AND ((p_flockid IS NULL OR r.flockid = p_flockid) AND (p_batchid IS NULL OR r.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))), 0)::bigint              AS brokenrejectedeggs,

        COALESCE((SELECT SUM(r.mortality) FROM productionrecords r

                  WHERE r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate

                    AND ((p_flockid IS NULL OR r.flockid = p_flockid) AND (p_batchid IS NULL OR r.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))), 0)::int                  AS deaths,

        COALESCE((SELECT SUM(r.feedkg::numeric(18,2)) FROM productionrecords r

                  WHERE r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate

                    AND ((p_flockid IS NULL OR r.flockid = p_flockid) AND (p_batchid IS NULL OR r.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))), 0)                       AS feedconsumedkg,

        COALESCE((SELECT SUM(s.totalamount) FROM sale s

                  WHERE s.status = 'Posted' AND s.farmid = p_farmid AND s.saledate >= p_startdate AND s.saledate < (p_enddate + 1)

                    AND ((p_flockid IS NULL OR s.flockid = p_flockid) AND (p_batchid IS NULL OR s.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))), 0)                       AS salesrevenue,

        COALESCE((SELECT SUM(CASE WHEN COALESCE(s.paid, TRUE) THEN s.totalamount ELSE 0 END) FROM sale s

                  WHERE s.status = 'Posted' AND s.farmid = p_farmid AND s.saledate >= p_startdate AND s.saledate < (p_enddate + 1)

                    AND ((p_flockid IS NULL OR s.flockid = p_flockid) AND (p_batchid IS NULL OR s.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))), 0)                       AS cashcollected,

        COALESCE((SELECT SUM(CASE WHEN COALESCE(s.paid, TRUE) = FALSE THEN s.totalamount ELSE 0 END) FROM sale s

                  WHERE s.status = 'Posted' AND s.farmid = p_farmid AND s.saledate >= p_startdate AND s.saledate < (p_enddate + 1)

                    AND ((p_flockid IS NULL OR s.flockid = p_flockid) AND (p_batchid IS NULL OR s.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))), 0)                       AS customerreceivables,

        COALESCE((SELECT SUM(e.amount) FROM expense e

                  WHERE e.farmid = v_gid

                    AND e.expensedate >= p_startdate AND e.expensedate < (p_enddate + 1)

                    AND ((p_flockid IS NULL OR e.flockid = p_flockid) AND (p_batchid IS NULL OR e.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))), 0)                       AS expenses,

        (SELECT COUNT(*)::int FROM flock f

          WHERE f.farmid = p_farmid AND COALESCE(f.active, TRUE)

            AND ((p_flockid IS NULL OR f.flockid = p_flockid) AND (p_batchid IS NULL OR f.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid))))                                   AS activeflocks;

END

$function$;

-- feedcostperegg: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_feedcostperegg(p_farmid text, p_startdate date, p_enddate date, p_flockid integer, p_includeclosedflocks boolean);
CREATE FUNCTION public.sppoultryreport_feedcostperegg(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeclosedflocks boolean DEFAULT false, p_batchid integer DEFAULT NULL::integer)
 RETURNS TABLE(flockid integer, flockname text, feedconsumedkg numeric, eggsproduced bigint, birddays bigint, feedcost numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_gid uuid;
BEGIN
    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;

    RETURN QUERY
    WITH pr AS (
        SELECT r.flockid AS c_flockid,
               SUM(r.totalproduction::bigint) AS c_eggs,
               SUM(r.feedkg::numeric(18,2))   AS c_feed,
               SUM(r.noofbirdsleft::bigint)   AS c_birddays
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate
        GROUP  BY r.flockid
    ),
    fc AS (
        SELECT e.flockid AS c_flockid, SUM(e.amount) AS c_feedcost
        FROM   expense e
        WHERE  e.farmid = v_gid
          AND  e.expensedate >= p_startdate AND e.expensedate < (p_enddate + 1)
          AND  e.category ILIKE '%Feed%'
        GROUP  BY e.flockid
    )
    SELECT
        f.flockid,
        f.name::text                        AS flockname,
        COALESCE(pr.c_feed, 0)              AS feedconsumedkg,
        COALESCE(pr.c_eggs, 0)::bigint      AS eggsproduced,
        COALESCE(pr.c_birddays, 0)::bigint  AS birddays,
        fc.c_feedcost                       AS feedcost
    FROM   flock f
    LEFT JOIN pr ON pr.c_flockid = f.flockid
    LEFT JOIN fc ON fc.c_flockid = f.flockid
    WHERE  f.farmid = p_farmid
      AND  ((p_flockid IS NULL OR f.flockid = p_flockid) AND (p_batchid IS NULL OR f.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))
      AND  (p_includeclosedflocks OR COALESCE(f.active, TRUE))
    ORDER  BY f.name;
END
$function$;

-- feedusage: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_feedusage(p_farmid text, p_startdate date, p_enddate date, p_flockid integer);
CREATE FUNCTION public.sppoultryreport_feedusage(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_batchid integer DEFAULT NULL::integer)
 RETURNS TABLE(date date, flockid integer, flockname text, feedtype text, feedconsumedkg numeric, livebirds bigint, eggsproduced bigint)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        fu.usagedate                                AS date,
        fu.flockid                                  AS flockid,
        COALESCE(f.name, 'Unassigned')::text        AS flockname,
        fu.feedtype::text                           AS feedtype,
        SUM(fu.quantitykg::numeric(18,2))           AS feedconsumedkg,
        (SELECT SUM(pr.noofbirdsleft::bigint)::bigint FROM productionrecords pr
          WHERE pr.farmid = p_farmid AND pr.flockid = fu.flockid AND pr.date = fu.usagedate)   AS livebirds,
        (SELECT SUM(pr.totalproduction::bigint)::bigint FROM productionrecords pr
          WHERE pr.farmid = p_farmid AND pr.flockid = fu.flockid AND pr.date = fu.usagedate)   AS eggsproduced
    FROM   feedusage fu
    LEFT JOIN flock f ON f.flockid = fu.flockid AND f.farmid = fu.farmid
    WHERE  fu.farmid = p_farmid AND fu.usagedate >= p_startdate AND fu.usagedate <= p_enddate
      AND  ((p_flockid IS NULL OR fu.flockid = p_flockid) AND (p_batchid IS NULL OR fu.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))
    GROUP  BY fu.usagedate, fu.flockid, fu.feedtype, f.name
    ORDER  BY fu.usagedate DESC, f.name;
END
$function$;

-- flockproductionsummary: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_flockproductionsummary(p_farmid text, p_startdate date, p_enddate date, p_flockid integer, p_includeclosedflocks boolean);
CREATE FUNCTION public.sppoultryreport_flockproductionsummary(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeclosedflocks boolean DEFAULT false, p_batchid integer DEFAULT NULL::integer)
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
      AND  ((p_flockid IS NULL OR f.flockid = p_flockid) AND (p_batchid IS NULL OR f.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))
      AND  (p_includeclosedflocks OR COALESCE(f.active, TRUE))
      AND  NOT COALESCE(f.isdeleted, FALSE)      -- 420: a deleted flock placed nothing
      AND  COALESCE(f.hasarrived, TRUE)          -- 420: nor did one whose birds have not arrived
    ORDER  BY f.name;
END
$function$;

-- hendayproduction: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_hendayproduction(p_farmid text, p_startdate date, p_enddate date, p_flockid integer);
CREATE FUNCTION public.sppoultryreport_hendayproduction(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_batchid integer DEFAULT NULL::integer)
 RETURNS TABLE(date date, flockid integer, flockname text, livebirds bigint, eggsproduced bigint)
 LANGUAGE plpgsql
AS $function$

BEGIN

    RETURN QUERY

    SELECT

        pr.date                                     AS date,

        pr.flockid                                  AS flockid,

        COALESCE(f.name, 'Unassigned')::text        AS flockname,

        SUM(pr.noofbirdsleft::bigint)::bigint       AS livebirds,

        SUM(pr.totalproduction::bigint)::bigint     AS eggsproduced

    FROM   productionrecords pr

    LEFT JOIN flock f ON f.flockid = pr.flockid AND f.farmid = pr.farmid

    WHERE  pr.farmid = p_farmid AND pr.date >= p_startdate AND pr.date <= p_enddate AND pr.sourcetype <> 'FeedUsage'

      AND  ((p_flockid IS NULL OR pr.flockid = p_flockid) AND (p_batchid IS NULL OR pr.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))

    GROUP  BY pr.date, pr.flockid, f.name

    ORDER  BY pr.date DESC, f.name;

END

$function$;

-- medicineusage: 2 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_medicineusage(p_farmid text, p_startdate date, p_enddate date, p_flockid integer);
CREATE FUNCTION public.sppoultryreport_medicineusage(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_batchid integer DEFAULT NULL::integer)
 RETURNS TABLE(date date, flockid integer, flockname text, medicine text, notes text, createdby text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT x.c_date                                 AS date,
           x.c_flockid                              AS flockid,
           COALESCE(f.name, 'Unassigned')::text     AS flockname,
           x.c_medicine                             AS medicine,
           x.c_notes                                AS notes,
           x.c_createdby                            AS createdby
    FROM (
        SELECT h.recorddate::date       AS c_date,
               h.flockid                AS c_flockid,
               h.medication::text       AS c_medicine,
               h.notes::text            AS c_notes,
               h.userid::text           AS c_createdby
        FROM   healthrecord h
        WHERE  h.farmid = p_farmid
          AND  h.recorddate >= p_startdate AND h.recorddate < (p_enddate + 1)
          AND  h.medication IS NOT NULL AND btrim(h.medication) <> ''
          AND  ((p_flockid IS NULL OR h.flockid = p_flockid) AND (p_batchid IS NULL OR h.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))
        UNION ALL
        SELECT pr.date,
               pr.flockid,
               pr.medication::text,
               pr.notes::text,
               pr.userid::text
        FROM   productionrecords pr
        WHERE  pr.farmid = p_farmid
          AND  pr.date >= p_startdate AND pr.date <= p_enddate
          AND  pr.medication IS NOT NULL AND btrim(pr.medication) <> ''
          AND  ((p_flockid IS NULL OR pr.flockid = p_flockid) AND (p_batchid IS NULL OR pr.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))
    ) x
    LEFT JOIN flock f ON f.flockid = x.c_flockid AND f.farmid = p_farmid
    ORDER  BY x.c_date DESC, f.name;
END
$function$;

-- missingdailyrecords_rs1: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_missingdailyrecords_rs1(p_farmid text, p_startdate date, p_enddate date, p_flockid integer);
CREATE FUNCTION public.sppoultryreport_missingdailyrecords_rs1(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_batchid integer DEFAULT NULL::integer)
 RETURNS TABLE(date date, flockid integer, flockname text, hasproductionrecord boolean, hasfeedusage boolean, hasmortalityupdate boolean, hashealthnote boolean)
 LANGUAGE plpgsql
AS $function$

BEGIN

    RETURN QUERY

    WITH d AS (

        SELECT gs::date AS c_dt

        FROM   generate_series(p_startdate, p_enddate, INTERVAL '1 day') AS gs

    ),

    fl AS (

        SELECT f.flockid AS c_flockid, f.name AS c_name, f.startdate AS c_startdate,

               f.closeddate AS c_closeddate

        FROM   flock f

        WHERE  f.farmid = p_farmid

          AND  (f.closeddate IS NOT NULL OR COALESCE(f.active, TRUE))       -- 338

          AND  ((p_flockid IS NULL OR f.flockid = p_flockid) AND (p_batchid IS NULL OR f.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))

          AND  f.startdate <= p_enddate

          AND  (f.closeddate IS NULL OR f.closeddate >= p_startdate)        -- 338

    ),

    grid AS (

        SELECT d.c_dt                       AS c_date,

               fl.c_flockid                 AS c_flockid,

               fl.c_name                    AS c_flockname,

               EXISTS(SELECT 1 FROM productionrecords pr

                      WHERE pr.farmid = p_farmid AND pr.flockid = fl.c_flockid AND pr.date = d.c_dt AND pr.sourcetype <> 'FeedUsage')

                                            AS c_hasproductionrecord,

               (EXISTS(SELECT 1 FROM feedusage fu

                       WHERE fu.farmid = p_farmid AND fu.flockid = fl.c_flockid AND fu.usagedate = d.c_dt)

                OR EXISTS(SELECT 1 FROM productionrecords pr

                          WHERE pr.farmid = p_farmid AND pr.flockid = fl.c_flockid AND pr.date = d.c_dt AND pr.feedkg > 0))

                                            AS c_hasfeedusage,

               EXISTS(SELECT 1 FROM productionrecords pr

                      WHERE pr.farmid = p_farmid AND pr.flockid = fl.c_flockid AND pr.date = d.c_dt AND pr.sourcetype <> 'FeedUsage')

                                            AS c_hasmortalityupdate,

               EXISTS(SELECT 1 FROM healthrecord h

                      WHERE h.farmid = p_farmid AND h.flockid = fl.c_flockid AND h.recorddate::date = d.c_dt)

                                            AS c_hashealthnote

        FROM   d CROSS JOIN fl

        WHERE  d.c_dt >= fl.c_startdate

          AND  (fl.c_closeddate IS NULL OR d.c_dt <= fl.c_closeddate)       -- 338

    )

    SELECT g.c_date, g.c_flockid, g.c_flockname::text,

           g.c_hasproductionrecord, g.c_hasfeedusage, g.c_hasmortalityupdate, g.c_hashealthnote

    FROM   grid g

    WHERE  g.c_hasproductionrecord = FALSE OR g.c_hasfeedusage = FALSE

    ORDER  BY g.c_date DESC, g.c_flockname;

END

$function$;

-- missingdailyrecords_rs2: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_missingdailyrecords_rs2(p_farmid text, p_startdate date, p_enddate date, p_flockid integer);
CREATE FUNCTION public.sppoultryreport_missingdailyrecords_rs2(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_batchid integer DEFAULT NULL::integer)
 RETURNS TABLE(activeflocks integer, missingproductionrecords integer, missingfeedrecords integer, missinghealthrecords integer, completeflockdays integer)
 LANGUAGE plpgsql
AS $function$

BEGIN

    RETURN QUERY

    WITH d AS (

        SELECT gs::date AS c_dt

        FROM   generate_series(p_startdate, p_enddate, INTERVAL '1 day') AS gs

    ),

    fl AS (

        SELECT f.flockid AS c_flockid, f.startdate AS c_startdate, f.closeddate AS c_closeddate

        FROM   flock f

        WHERE  f.farmid = p_farmid

          AND  (f.closeddate IS NOT NULL OR COALESCE(f.active, TRUE))       -- 338

          AND  ((p_flockid IS NULL OR f.flockid = p_flockid) AND (p_batchid IS NULL OR f.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))

          AND  f.startdate <= p_enddate

          AND  (f.closeddate IS NULL OR f.closeddate >= p_startdate)        -- 338

    ),

    grid AS (

        SELECT EXISTS(SELECT 1 FROM productionrecords pr

                      WHERE pr.farmid = p_farmid AND pr.flockid = fl.c_flockid AND pr.date = d.c_dt AND pr.sourcetype <> 'FeedUsage')

                                            AS c_hasprod,

               (EXISTS(SELECT 1 FROM feedusage fu

                       WHERE fu.farmid = p_farmid AND fu.flockid = fl.c_flockid AND fu.usagedate = d.c_dt)

                OR EXISTS(SELECT 1 FROM productionrecords pr

                          WHERE pr.farmid = p_farmid AND pr.flockid = fl.c_flockid AND pr.date = d.c_dt AND pr.feedkg > 0))

                                            AS c_hasfeed,

               EXISTS(SELECT 1 FROM healthrecord h

                      WHERE h.farmid = p_farmid AND h.flockid = fl.c_flockid AND h.recorddate::date = d.c_dt)

                                            AS c_hashealth

        FROM   d CROSS JOIN fl

        WHERE  d.c_dt >= fl.c_startdate

          AND  (fl.c_closeddate IS NULL OR d.c_dt <= fl.c_closeddate)       -- 338

    )

    SELECT

        (SELECT COUNT(*)::int FROM fl)                                                   AS activeflocks,

        SUM(CASE WHEN g.c_hasprod   = FALSE THEN 1 ELSE 0 END)::int                      AS missingproductionrecords,

        SUM(CASE WHEN g.c_hasfeed   = FALSE THEN 1 ELSE 0 END)::int                      AS missingfeedrecords,

        SUM(CASE WHEN g.c_hashealth = FALSE THEN 1 ELSE 0 END)::int                      AS missinghealthrecords,

        SUM(CASE WHEN g.c_hasprod = TRUE AND g.c_hasfeed = TRUE THEN 1 ELSE 0 END)::int  AS completeflockdays

    FROM   grid g;

END

$function$;

-- mortality: 2 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_mortality(p_farmid text, p_startdate date, p_enddate date, p_flockid integer);
CREATE FUNCTION public.sppoultryreport_mortality(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_batchid integer DEFAULT NULL::integer)
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
        WHERE  f.farmid = p_farmid AND ((p_flockid IS NULL OR f.flockid = p_flockid) AND (p_batchid IS NULL OR f.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))
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
      AND  ((p_flockid IS NULL OR pr.flockid = p_flockid) AND (p_batchid IS NULL OR pr.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))
    GROUP  BY pr.date, pr.flockid, f.name, pos.c_started, pos.c_before
    ORDER  BY pr.flockid, pr.date;
END
$function$;

-- profitlossbyflock: 2 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_profitlossbyflock(p_farmid text, p_startdate date, p_enddate date, p_flockid integer, p_includeclosedflocks boolean);
CREATE FUNCTION public.sppoultryreport_profitlossbyflock(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_includeclosedflocks boolean DEFAULT false, p_batchid integer DEFAULT NULL::integer)
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
          AND  ((p_flockid IS NULL OR f.flockid = p_flockid) AND (p_batchid IS NULL OR f.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))
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
      AND  ((p_flockid IS NULL OR f.flockid = p_flockid) AND (p_batchid IS NULL OR f.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))
      AND  (p_includeclosedflocks OR COALESCE(f.active, TRUE))
    ORDER  BY f.name;
END
$function$;

-- vaccinationschedule: 1 flock filter(s) now also honour the batch
DROP FUNCTION IF EXISTS public.sppoultryreport_vaccinationschedule(p_farmid text, p_startdate date, p_enddate date, p_flockid integer);
CREATE FUNCTION public.sppoultryreport_vaccinationschedule(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer, p_batchid integer DEFAULT NULL::integer)
 RETURNS TABLE(flockid integer, flockname text, vaccine text, actualdate date, administeredby text, notes text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        h.flockid                                   AS flockid,
        COALESCE(f.name, 'Unassigned')::text        AS flockname,
        h.vaccination::text                         AS vaccine,
        h.recorddate::date                          AS actualdate,
        h.userid::text                              AS administeredby,
        h.notes::text                               AS notes
    FROM   healthrecord h
    LEFT JOIN flock f ON f.flockid = h.flockid AND f.farmid = p_farmid
    WHERE  h.farmid = p_farmid
      AND  h.recorddate >= p_startdate AND h.recorddate < (p_enddate + 1)
      AND  h.vaccination IS NOT NULL AND btrim(h.vaccination) <> ''
      AND  ((p_flockid IS NULL OR h.flockid = p_flockid) AND (p_batchid IS NULL OR h.flockid IN (SELECT bf.flockid FROM flock bf WHERE bf.farmid = p_farmid AND bf.batchid = p_batchid)))
    ORDER  BY h.recorddate DESC, f.name;
END
$function$;

-- Self-test: every function runs with and without a batch, and a batch never
-- returns more rows than the unfiltered report.
DO $$
DECLARE
    v_farm text; v_batch int; a bigint; b bigint;
    s date := current_date - 365; e date := current_date;
BEGIN
    SELECT f.farmid, f.batchid INTO v_farm, v_batch
    FROM flock f WHERE f.batchid IS NOT NULL AND f.batchid <> 0
    GROUP BY 1, 2 ORDER BY count(*) DESC LIMIT 1;
    IF v_farm IS NULL THEN RAISE NOTICE '432 self-test skipped: no batched flocks'; RETURN; END IF;

    SELECT count(*) INTO a FROM sppoultryreport_birdsonhand(p_farmid => v_farm, p_enddate => e, p_includeclosedflocks => true);
    SELECT count(*) INTO b FROM sppoultryreport_birdsonhand(p_farmid => v_farm, p_enddate => e, p_includeclosedflocks => true, p_batchid => v_batch);
    IF b > a OR b = 0 THEN RAISE EXCEPTION '432 birdsonhand: % of % rows', b, a; END IF;
    RAISE NOTICE '432 birdsonhand farm % batch %: % of % flocks', v_farm, v_batch, b, a;

    SELECT count(*) INTO a FROM sppoultryreport_endofflock(p_farmid => v_farm, p_enddate => e, p_includeactiveflocks => true);
    SELECT count(*) INTO b FROM sppoultryreport_endofflock(p_farmid => v_farm, p_enddate => e, p_includeactiveflocks => true, p_batchid => v_batch);
    IF b > a THEN RAISE EXCEPTION '432 endofflock: % of % rows', b, a; END IF;

    SELECT count(*) INTO a FROM sppoultryreport_mortality(p_farmid => v_farm, p_startdate => s, p_enddate => e);
    SELECT count(*) INTO b FROM sppoultryreport_mortality(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_batchid => v_batch);
    IF b > a THEN RAISE EXCEPTION '432 mortality: % of % rows', b, a; END IF;

    PERFORM * FROM sppoultryreport_farmsummary_rs1(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_farmsummary_rs2(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_dailyeggproduction(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_flockproductionsummary(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_hendayproduction(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_feedusage(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_feedcostperegg(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_byproducts(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_eggsales_rs1(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_customername => NULL, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_eggsales_rs2(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_customername => NULL, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_expensesummary(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_supplier => NULL, p_category => NULL, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_profitlossbyflock(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_costperegg(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_vaccinationschedule(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_medicineusage(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_missingdailyrecords_rs1(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_batchid => v_batch);
    PERFORM * FROM sppoultryreport_missingdailyrecords_rs2(p_farmid => v_farm, p_startdate => s, p_enddate => e, p_batchid => v_batch);
    RAISE NOTICE '432 self-test passed';
END $$;

COMMIT;
