-- =============================================================================
-- 378_PoultryProductionRecordDuplicateMessage.postgres.sql      (requires 341)
--
-- Purpose
-- -------
-- Clearer wording when a second production record is added for a flock-day.
-- Was:
--   "BVCH - New 3 already has a production record for 15 Oct 2026. Edit that
--    record instead of adding another one. To record egg sizes, use the Egg
--    Sorting Workspace -- sorting never needs a second production record."
-- Now:
--   "There is already a production record for BVCH - New 3 on 15 Oct 2026.
--    Choose a different date, or edit the existing record from the Production
--    Records list. To record egg sizes, use Egg Sorting instead."
--
-- Only the message changes: same rule, same SQLSTATE (P0010), so the API and
-- the web app show it as before (the web app now shows the sentence alone).
-- =============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.tr_productionrecords_oneperday_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_flock text;
BEGIN
    IF NEW.flockid IS NULL THEN
        RETURN NEW;
    END IF;
    -- An edit that leaves the flock and the date alone is always allowed, so a
    -- pre-existing duplicate can still be corrected in place.
    IF TG_OP = 'UPDATE'
       AND NEW.flockid IS NOT DISTINCT FROM OLD.flockid
       AND NEW.date    IS NOT DISTINCT FROM OLD.date
       AND NEW.farmid  IS NOT DISTINCT FROM OLD.farmid THEN
        RETURN NEW;
    END IF;

    -- Two saves for the same flock-day at the same moment: the second waits
    -- here and then sees the first.
    PERFORM pg_advisory_xact_lock(hashtext('poultry-prodrec:' || NEW.farmid || ':' || NEW.flockid::text || ':' || NEW.date::text));

    IF EXISTS (SELECT 1 FROM productionrecords pr
               WHERE pr.farmid = NEW.farmid AND pr.flockid = NEW.flockid AND pr.date = NEW.date
                 AND pr.id IS DISTINCT FROM NEW.id) THEN
        SELECT f.name INTO v_flock FROM flock f WHERE f.flockid = NEW.flockid;
        -- 378: say what to do next, in plain words.
        RAISE EXCEPTION 'There is already a production record for % on %. Choose a different date, or edit the existing record from the Production Records list. To record egg sizes, use Egg Sorting instead.',
            COALESCE(v_flock, 'this flock'), to_char(NEW.date, 'FMDD Mon YYYY')
            USING ERRCODE = 'P0010';
    END IF;
    RETURN NEW;
END;
$function$;

COMMIT;
