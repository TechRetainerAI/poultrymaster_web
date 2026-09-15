-- =============================================================================
-- 252  Daily Egg Production report breaks out the 5th and 6th picks
-- =============================================================================
-- The last procedure in the database still reading four picks. Its TOTAL was
-- never wrong — it sums pr.totalproduction rather than adding the picks up
-- itself, so the two new picks were already inside it. What it could not do was
-- SHOW them: a farm collecting six times a day saw four pick columns and a
-- total that did not equal their sum.
--
-- Read from the live catalogue and edited in place, as 250 and 251 were. The
-- return type changes, so the old function is dropped first.
--
-- HOW TO RUN
--   psql "<conn>" -f 252_DailyEggProductionFifthSixthPick.postgres.sql
-- =============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.sppoultryreport_dailyeggproduction(p_farmid text, p_startdate date, p_enddate date, p_flockid integer);
CREATE FUNCTION public.sppoultryreport_dailyeggproduction(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer)
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
    WHERE  pr.farmid = p_farmid AND pr.date >= p_startdate AND pr.date <= p_enddate
      AND  (p_flockid IS NULL OR pr.flockid = p_flockid)
    GROUP  BY pr.date, pr.flockid, f.name
    ORDER  BY pr.date DESC, f.name;
END
$function$;

-- --- Prove it -----------------------------------------------------------------
-- The report's own total must still equal the six picks it now prints.
SELECT 'AFTER' AS phase,
       (SELECT COUNT(*) FROM pg_proc WHERE proname = 'sppoultryreport_dailyeggproduction'
          AND prosrc ILIKE '%production5thpick%') AS proc_updated,
       (SELECT COUNT(*) FROM productionrecords pr
        WHERE COALESCE(pr.totalproduction,0) <> COALESCE(pr.production9am,0) + COALESCE(pr.production12pm,0)
                                              + COALESCE(pr.production4pm,0) + COALESCE(pr.production4thpick,0)
                                              + COALESCE(pr.production5thpick,0) + COALESCE(pr.production6thpick,0)
       ) AS records_whose_total_disagrees;

COMMIT;

-- =============================================================================
-- UNDO: re-apply this function from the advanced-reports migration.
-- =============================================================================
