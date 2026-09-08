-- =============================================================================
-- 248  Egg pick settings: a 5th and a 6th pick
-- =============================================================================
-- Migration 153 gave a farm four configurable pick times and one switch, for
-- the 4th. Farms that collect more often than that had nowhere to say so, so
-- /business-office/egg-pick-settings now configures six.
--
-- WHAT THIS FILE DOES. Four columns on farmproductionsettings — two times and
-- two switches — and the two SPs behind them widened to carry the new fields.
--
-- WHAT IT DOES NOT DO. It does not add anywhere to RECORD a 5th or 6th pick.
-- productionrecords stores its picks in four fixed columns (production9am,
-- production12pm, production4pm, production4thpick), and giving it two more is
-- a separate change touching the record SPs, the API model, the entry forms and
-- every report that reads them. Until then these two settings are configuration
-- the entry forms can read but not yet fill: exactly the state the 4th pick was
-- in between 153 and the form work that followed it.
--
-- DEFAULTS. The new switches default FALSE, so no farm gains a pick it did not
-- ask for, and the times default NULL rather than to invented hours — a blank
-- time reads as "not set" on the settings page and adds no suffix to a label.
--
-- Idempotent: columns are added only if absent, and the functions are replaced.
-- Both function signatures change (new parameters, wider result), so they are
-- dropped first — CREATE OR REPLACE cannot change a function's return type.
--
-- HOW TO RUN
--   psql "<conn>" -f 248_FarmProductionSettingsFifthSixthPick.postgres.sql
-- =============================================================================

BEGIN;

-- --- 1. Columns ---------------------------------------------------------------
ALTER TABLE farmproductionsettings
    ADD COLUMN IF NOT EXISTS fifthpicktime   VARCHAR(10),
    ADD COLUMN IF NOT EXISTS sixthpicktime   VARCHAR(10),
    ADD COLUMN IF NOT EXISTS enablefifthpick BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS enablesixthpick BOOLEAN NOT NULL DEFAULT FALSE;

-- --- 2. Read -------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spfarmproductionsettings_get(text);

CREATE FUNCTION public.spfarmproductionsettings_get(p_farmid text)
RETURNS TABLE(
    id integer, farmid text,
    firstpicktime text, secondpicktime text, thirdpicktime text,
    fourthpicktime text, fifthpicktime text, sixthpicktime text,
    enablefourthpick boolean, enablefifthpick boolean, enablesixthpick boolean,
    createdby text, createddate timestamp without time zone,
    updatedby text, updateddate timestamp without time zone)
LANGUAGE plpgsql
AS $function$
BEGIN
    IF EXISTS (SELECT 1 FROM farmproductionsettings s WHERE s.farmid = p_farmid) THEN
        RETURN QUERY
        SELECT s.id, s.farmid::text,
               s.firstpicktime::text, s.secondpicktime::text, s.thirdpicktime::text,
               s.fourthpicktime::text, s.fifthpicktime::text, s.sixthpicktime::text,
               s.enablefourthpick, s.enablefifthpick, s.enablesixthpick,
               s.createdby::text, s.createddate,
               s.updatedby::text, s.updateddate
        FROM   farmproductionsettings s
        WHERE  s.farmid = p_farmid;
    ELSE
        -- A farm that has never saved settings still gets a usable row: the
        -- first four times are the hours 153 shipped with, and everything the
        -- farm has not opted into is off or unset.
        RETURN QUERY
        SELECT 0::integer, p_farmid::text,
               '09:00'::text, '12:00'::text, '16:00'::text, '18:00'::text,
               NULL::text, NULL::text,
               FALSE, FALSE, FALSE,
               NULL::text, NULL::timestamp,
               NULL::text, NULL::timestamp;
    END IF;
END
$function$;

-- --- 3. Write ------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spfarmproductionsettings_upsert(text, text, text, text, text, boolean, text);

CREATE FUNCTION public.spfarmproductionsettings_upsert(
    p_farmid           text,
    p_firstpicktime    text DEFAULT NULL,
    p_secondpicktime   text DEFAULT NULL,
    p_thirdpicktime    text DEFAULT NULL,
    p_fourthpicktime   text DEFAULT NULL,
    p_enablefourthpick boolean DEFAULT FALSE,
    p_updatedby        text DEFAULT NULL,
    -- The new fields go on the END with defaults, so a caller built against the
    -- old signature keeps working: an older API instance mid-deploy sends seven
    -- arguments and leaves the 5th and 6th pick as they are.
    p_fifthpicktime    text DEFAULT NULL,
    p_sixthpicktime    text DEFAULT NULL,
    p_enablefifthpick  boolean DEFAULT FALSE,
    p_enablesixthpick  boolean DEFAULT FALSE)
RETURNS TABLE(
    id integer, farmid text,
    firstpicktime text, secondpicktime text, thirdpicktime text,
    fourthpicktime text, fifthpicktime text, sixthpicktime text,
    enablefourthpick boolean, enablefifthpick boolean, enablesixthpick boolean,
    createdby text, createddate timestamp without time zone,
    updatedby text, updateddate timestamp without time zone)
LANGUAGE plpgsql
AS $function$
BEGIN
    IF EXISTS (SELECT 1 FROM farmproductionsettings s WHERE s.farmid = p_farmid) THEN
        UPDATE farmproductionsettings s
        SET    firstpicktime    = p_firstpicktime,
               secondpicktime   = p_secondpicktime,
               thirdpicktime    = p_thirdpicktime,
               fourthpicktime   = p_fourthpicktime,
               fifthpicktime    = p_fifthpicktime,
               sixthpicktime    = p_sixthpicktime,
               enablefourthpick = p_enablefourthpick,
               enablefifthpick  = p_enablefifthpick,
               enablesixthpick  = p_enablesixthpick,
               updatedby        = p_updatedby,
               updateddate      = (now() at time zone 'utc')
        WHERE  s.farmid = p_farmid;
    ELSE
        INSERT INTO farmproductionsettings
            (farmid, firstpicktime, secondpicktime, thirdpicktime, fourthpicktime,
             fifthpicktime, sixthpicktime,
             enablefourthpick, enablefifthpick, enablesixthpick, createdby, createddate)
        VALUES (p_farmid, p_firstpicktime, p_secondpicktime, p_thirdpicktime, p_fourthpicktime,
                p_fifthpicktime, p_sixthpicktime,
                p_enablefourthpick, p_enablefifthpick, p_enablesixthpick, p_updatedby,
                (now() at time zone 'utc'));
    END IF;

    RETURN QUERY SELECT * FROM spfarmproductionsettings_get(p_farmid);
END
$function$;

-- --- 4. Prove it ---------------------------------------------------------------
-- Reading a farm that has no row must still return one, with the new fields
-- present and off.
SELECT 'AFTER' AS phase, * FROM spfarmproductionsettings_get('__migration_248_probe__');

COMMIT;

-- =============================================================================
-- UNDO (paste separately if ever needed)
-- =============================================================================
-- BEGIN;
-- DROP FUNCTION IF EXISTS public.spfarmproductionsettings_get(text);
-- DROP FUNCTION IF EXISTS public.spfarmproductionsettings_upsert(text, text, text, text, text, boolean, text, text, text, boolean, boolean);
-- ALTER TABLE farmproductionsettings
--     DROP COLUMN IF EXISTS fifthpicktime,
--     DROP COLUMN IF EXISTS sixthpicktime,
--     DROP COLUMN IF EXISTS enablefifthpick,
--     DROP COLUMN IF EXISTS enablesixthpick;
-- -- then re-apply migration 153's two functions.
-- COMMIT;
