-- =============================================================================
-- 249  Production records can hold a 5th and a 6th pick
-- =============================================================================
-- 248 let a farm CONFIGURE six pick times; this is where the eggs from the last
-- two go. Until now productionrecords stopped at four picks, so the settings
-- page could name a 5th round that no form could record.
--
-- HOW THE 4TH PICK WAS DONE, AND WHY THIS COPIES IT. Migration 153 did not
-- widen spproductionrecord_insert / _update — both are 35-parameter procedures
-- and rewriting them to add one column is a large change with a large blast
-- radius. Instead it added spproductionrecord_setfourthpick, which the service
-- calls straight after the insert or update, inside the same transaction. This
-- file adds the matching spproductionrecord_setextrapicks for the 5th and 6th.
-- Same shape, same transaction, same guard in the API: the service probes for
-- the procedure and skips it when it is absent, so the API runs against a
-- database with or without this migration.
--
-- TOTALPRODUCTION. Both side procedures rewrite it, because it is the sum of
-- the picks and every downstream reader trusts it — the egg stock ledger posts
-- saleable eggs from it (136 / 204), and /egg-tracker's "Egg produced" totals
-- it. setfourthpick is REPLACED here rather than left alone: its old body
-- summed four picks, so on a record that had a 5th or 6th it would have written
-- a total that quietly dropped them. Both procedures now sum all six from the
-- row itself, which also means the order the service calls them in cannot
-- change the answer.
--
-- NULL, not 0. The two columns are nullable with no default: a record written
-- before this migration did not have a 5th pick of zero, it had no 5th pick at
-- all, and COALESCE at read time keeps the arithmetic right either way.
--
-- Idempotent. Columns are added only if absent; both functions are replaced.
--
-- HOW TO RUN
--   psql "<conn>" -f 249_ProductionRecordFifthSixthPick.postgres.sql
-- =============================================================================

BEGIN;

-- --- 1. Columns ---------------------------------------------------------------
ALTER TABLE productionrecords
    ADD COLUMN IF NOT EXISTS production5thpick INTEGER,
    ADD COLUMN IF NOT EXISTS production6thpick INTEGER;

-- --- 2. The 4th-pick writer, taught about the other two ------------------------
CREATE OR REPLACE FUNCTION public.spproductionrecord_setfourthpick(
    p_recordid integer,
    p_farmid text DEFAULT NULL::text,
    p_production4thpick integer DEFAULT 0)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE productionrecords pr
    SET production4thpick = p_production4thpick,
        totalproduction = COALESCE(pr.production9am, 0) + COALESCE(pr.production12pm, 0)
                        + COALESCE(pr.production4pm, 0) + COALESCE(p_production4thpick, 0)
                        + COALESCE(pr.production5thpick, 0) + COALESCE(pr.production6thpick, 0)
    WHERE pr.id = p_recordid
      AND (p_farmid IS NULL OR pr.farmid = p_farmid);
END;
$function$;

-- --- 3. The 5th / 6th writer ---------------------------------------------------
CREATE OR REPLACE FUNCTION public.spproductionrecord_setextrapicks(
    p_recordid integer,
    p_farmid text DEFAULT NULL::text,
    p_production5thpick integer DEFAULT NULL,
    p_production6thpick integer DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    UPDATE productionrecords pr
    SET production5thpick = p_production5thpick,
        production6thpick = p_production6thpick,
        totalproduction = COALESCE(pr.production9am, 0) + COALESCE(pr.production12pm, 0)
                        + COALESCE(pr.production4pm, 0) + COALESCE(pr.production4thpick, 0)
                        + COALESCE(p_production5thpick, 0) + COALESCE(p_production6thpick, 0)
    WHERE pr.id = p_recordid
      AND (p_farmid IS NULL OR pr.farmid = p_farmid);
END;
$function$;

-- --- 4. Prove it ---------------------------------------------------------------
-- Nothing to backfill: every existing record has NULL for both new picks, and
-- its total already equals the four picks it does have. This just shows the
-- columns landed and that no total moved.
SELECT 'AFTER' AS phase,
       COUNT(*) AS records,
       COUNT(production5thpick) AS with_fifth,
       COUNT(production6thpick) AS with_sixth,
       COUNT(*) FILTER (
         WHERE COALESCE(totalproduction, 0) <> COALESCE(production9am, 0) + COALESCE(production12pm, 0)
                                             + COALESCE(production4pm, 0) + COALESCE(production4thpick, 0)
                                             + COALESCE(production5thpick, 0) + COALESCE(production6thpick, 0)
       ) AS totals_disagreeing
FROM   productionrecords;

COMMIT;

-- =============================================================================
-- UNDO (paste separately if ever needed)
-- =============================================================================
-- BEGIN;
-- DROP FUNCTION IF EXISTS public.spproductionrecord_setextrapicks(integer, text, integer, integer);
-- ALTER TABLE productionrecords
--     DROP COLUMN IF EXISTS production5thpick,
--     DROP COLUMN IF EXISTS production6thpick;
-- -- then re-apply migration 153's spproductionrecord_setfourthpick, whose body
-- -- sums four picks rather than six.
-- COMMIT;
