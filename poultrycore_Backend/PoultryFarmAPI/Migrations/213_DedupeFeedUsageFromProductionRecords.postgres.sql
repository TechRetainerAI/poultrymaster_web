-- =============================================================================
-- 213_DedupeFeedUsageFromProductionRecords.postgres.sql
--
-- Problem
-- -------
-- feedusage has TWO writers and they fight.
--
--   1. The database triggers on productionrecords —
--      trg_productionrecord_insertfeedusage / _update / _delete. These are
--      correct: one feedusage row per production record, keyed on
--      sourceproductionrecordid, kept in step when feedkg changes and removed
--      when the record is deleted.
--
--   2. app/production-records/new and /[id] ALSO wrote feedusage from the
--      browser after saving. That code looked for an existing row by
--      (flock, date) rather than by production record, and created rows through
--      spfeedusage_insert, which has no sourceproductionrecordid parameter.
--
-- So the second writer either overwrote a row belonging to a DIFFERENT
-- production record on the same day, or inserted a duplicate with no source
-- link. 66 such orphans exist, and 13 flock/date groups have more than one
-- production record, which is where the overwriting happened.
--
-- The frontend writer has been removed; the triggers are the only writer now.
-- This migration clears the duplicates it left behind.
--
-- Fix
-- ---
-- An orphan is only removed when a trigger-owned row exists for the same farm,
-- flock, date AND quantity — i.e. it is provably the same feeding recorded
-- twice. Anything else is left alone and reported, because a row with no source
-- link is not automatically junk: /feed-usage lets people record feed directly,
-- and those entries are legitimate.
--
-- Before deleting, the orphan's feed type is copied onto the trigger-owned row
-- where that row still carries the trigger's hardcoded 'General Feed'. The
-- orphans hold the type the user actually picked ('Grower Feed', 'Starter Feed'
-- ...), so this keeps the better label rather than discarding it.
--
-- Read-only on everything except feedusage. Idempotent: once the duplicates are
-- gone the statements match nothing.
--
-- Known limitation, unchanged by this migration: feed type is not stored on
-- productionrecords, so the trigger has nothing to read and writes the constant
-- 'General Feed'. 226 of 300 rows already carried that value before today. It
-- is a description label in the feed ledger only — no total or grouping depends
-- on it. Storing the real type would need a new column on productionrecords and
-- a change to the trigger.
-- =============================================================================

\set ON_ERROR_STOP on

-- -----------------------------------------------------------------------------
-- 1. Carry the more specific feed type over to the row that is being kept.
-- -----------------------------------------------------------------------------
UPDATE feedusage t
SET    feedtype = o.feedtype,
       dateupdated = (now() at time zone 'utc')
FROM   feedusage o
WHERE  t.sourceproductionrecordid IS NOT NULL
  AND  o.sourceproductionrecordid IS NULL
  AND  o.farmid     = t.farmid
  AND  o.flockid    = t.flockid
  AND  o.usagedate  = t.usagedate
  AND  o.quantitykg = t.quantitykg
  AND  COALESCE(t.feedtype, '') IN ('', 'General Feed')
  AND  COALESCE(o.feedtype, '') NOT IN ('', 'General Feed');

-- -----------------------------------------------------------------------------
-- 2. Delete the duplicates.
-- -----------------------------------------------------------------------------
DELETE FROM feedusage o
WHERE  o.sourceproductionrecordid IS NULL
  AND  EXISTS (
         SELECT 1 FROM feedusage t
         WHERE t.sourceproductionrecordid IS NOT NULL
           AND t.farmid     = o.farmid
           AND t.flockid    = o.flockid
           AND t.usagedate  = o.usagedate
           AND t.quantitykg = o.quantitykg);

-- -----------------------------------------------------------------------------
-- 3. Report anything left unlinked, rather than assuming it is safe to remove.
-- -----------------------------------------------------------------------------
DO $report$
DECLARE
    r record;
    n int := 0;
BEGIN
    FOR r IN
        SELECT fu.feedusageid, fu.farmid, fu.flockid, fu.usagedate, fu.feedtype, fu.quantitykg
        FROM   feedusage fu
        WHERE  fu.sourceproductionrecordid IS NULL
        ORDER  BY fu.feedusageid
    LOOP
        RAISE NOTICE '213: feedusage % (flock %, %, % kg, %) has no source production record — left in place, check by hand.',
                     r.feedusageid, r.flockid, r.usagedate, r.quantitykg, COALESCE(r.feedtype, '-');
        n := n + 1;
    END LOOP;

    IF n = 0 THEN
        RAISE NOTICE '213: every feedusage row is now owned by a production record.';
    ELSE
        RAISE NOTICE '213: % unlinked feedusage row(s) remain (either genuine /feed-usage entries or a quantity that did not match).', n;
    END IF;
END
$report$;

-- 213_DedupeFeedUsageFromProductionRecords.postgres.sql complete.
