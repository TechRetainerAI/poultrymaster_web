-- =============================================================================
-- 346_PoultryEggSortingReportsByFlock.postgres.sql    (requires 342 and 343)
--
-- Purpose
-- -------
-- The Size reports on the Egg Sorting Workspace added every flock together:
-- "12 Mar 2026 -- Large 40%" did not say whose eggs those were. These two
-- functions return the same figures split by flock, with the flock's name,
-- so each row of the report belongs to one flock.
--
--   sppoultryeggsorting_compositionbyflock -- sppoultryeggsorting_composition
--       plus flockid / flockname; every grouping is per flock as well (by
--       production date = one row per flock per day, by pick = per flock per
--       pick, ...). Grouping BY flock is unchanged.
--   sppoultryeggsorting_carryoverbyflock   -- sppoultryeggsorting_carryover
--       per production date AND flock.
--
-- NEW functions, not a change to the old ones: Daily Closing's sorting check
-- (343) sums sppoultryeggsorting_carryover, and changing a function's result
-- columns needs a DROP that would break it. The API uses the by-flock
-- functions when they exist and falls back to the old ones before this runs.
-- Same rules as 343: "by pick" counts ByPick sortings only, and a combined
-- sorting is shared across its source days by quantity.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.sppoultryeggsorting_compositionbyflock(
    p_farmid text, p_fromdate date, p_todate date, p_groupby text DEFAULT 'productiondate',
    p_flockid integer DEFAULT NULL)
RETURNS TABLE (groupkey text, grouplabel text, groupsort text, flockid integer, flockname text,
               linetype text, eggsizeid integer, sizename text, sizesort integer, quantity numeric,
               sessions integer, combinedsessions integer)
LANGUAGE sql
STABLE
AS $function$
    WITH ses AS (
        SELECT s.* FROM poultryeggsortingsessions s
        WHERE  s.farmid = p_farmid AND s.status = 'Posted'
          AND  (p_flockid IS NULL OR s.flockid = p_flockid)
          AND  (p_groupby <> 'pick' OR s.sortingmode = 'ByPick')
    ),
    share AS (
        SELECT ses.sessionid, ses.sortingmode, ses.sortingdate, src.productionrecordid, src.picknumber,
               src.flockid, src.productiondate,
               l.linetype, l.eggsizeid, l.quantity::numeric * src.quantity / NULLIF(ses.inputquantity, 0) AS qty
        FROM   ses
        JOIN   poultryeggsortingsources src ON src.sessionid = ses.sessionid
        JOIN   poultryeggsortinglines l     ON l.sessionid = ses.sessionid
    ),
    keyed AS (
        SELECT sh.*,
               COALESCE(f.name, 'Flock ' || sh.flockid) AS fname,
               CASE p_groupby
                    WHEN 'sortingdate' THEN sh.sortingdate::text
                    WHEN 'flock'       THEN sh.flockid::text
                    WHEN 'batch'       THEN COALESCE(f.batchid::text, 'none')
                    WHEN 'age'         THEN ((sh.productiondate - f.startdate) / 7)::text
                    WHEN 'pick'        THEN sh.picknumber::text
                    ELSE sh.productiondate::text END AS gkey,
               CASE p_groupby
                    WHEN 'sortingdate' THEN to_char(sh.sortingdate, 'FMDD Mon YYYY')
                    WHEN 'flock'       THEN COALESCE(f.name, 'Flock ' || sh.flockid)
                    WHEN 'batch'       THEN COALESCE(b.batchname, 'No batch')
                    WHEN 'age'         THEN 'Week ' || ((sh.productiondate - f.startdate) / 7)
                    WHEN 'pick'        THEN 'Pick ' || sh.picknumber
                    ELSE to_char(sh.productiondate, 'FMDD Mon YYYY') END AS glabel,
               CASE p_groupby
                    WHEN 'sortingdate' THEN to_char(sh.sortingdate, 'YYYY-MM-DD')
                    WHEN 'flock'       THEN COALESCE(f.name, '')
                    WHEN 'batch'       THEN COALESCE(b.batchname, '~')
                    WHEN 'age'         THEN lpad(((sh.productiondate - f.startdate) / 7)::text, 4, '0')
                    WHEN 'pick'        THEN sh.picknumber::text
                    ELSE to_char(sh.productiondate, 'YYYY-MM-DD') END AS gsort
        FROM   share sh
        LEFT   JOIN flock f ON f.flockid = sh.flockid
        LEFT   JOIN mainflockbatch b ON b.batchid = f.batchid AND b.farmid = f.farmid
        WHERE  CASE WHEN p_groupby = 'sortingdate' THEN sh.sortingdate ELSE sh.productiondate END
               BETWEEN p_fromdate AND p_todate
    )
    -- The group key carries the flock, so two flocks on the same day are two rows.
    SELECT k.flockid::text || '|' || k.gkey, MAX(k.glabel), MAX(k.gsort), k.flockid, MAX(k.fname),
           k.linetype, k.eggsizeid, MAX(z.name)::text,
           COALESCE(MAX(z.sortorder), 100000),
           ROUND(SUM(k.qty), 2),
           COUNT(DISTINCT k.sessionid)::int,
           COUNT(DISTINCT k.sessionid) FILTER (WHERE k.sortingmode = 'Combined')::int
    FROM   keyed k
    LEFT   JOIN poultryeggsizes z ON z.eggsizeid = k.eggsizeid
    GROUP  BY k.flockid, k.gkey, k.linetype, k.eggsizeid
    ORDER  BY 3, 5, 9, 6;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryeggsorting_carryoverbyflock(
    p_farmid text, p_fromdate date, p_todate date, p_flockid integer DEFAULT NULL)
RETURNS TABLE (productiondate date, flockid integer, flockname text, records integer, gross bigint,
               collectionloss bigint, saleable bigint, sorted bigint, leftunsorted bigint)
LANGUAGE sql
STABLE
AS $function$
    SELECT r.productiondate, r.flockid, MAX(r.flockname), COUNT(*)::int,
           SUM(r.recordgross)::bigint, SUM(r.recordcollectionloss)::bigint,
           SUM(r.recordsaleable)::bigint, SUM(r.recordsorted)::bigint, SUM(r.recordleft)::bigint
    FROM (
        SELECT DISTINCT ON (x.productionrecordid) x.*
        FROM   public.sppoultryeggsorting_picks(p_farmid, p_fromdate, p_todate, p_flockid, NULL) x
    ) r
    GROUP  BY r.productiondate, r.flockid
    ORDER  BY r.productiondate DESC, MAX(r.flockname);
$function$;

COMMIT;
