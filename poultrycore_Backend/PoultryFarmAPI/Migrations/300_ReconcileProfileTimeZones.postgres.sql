-- =============================================================================
-- 300_ReconcileProfileTimeZones.postgres.sql
--
-- Purpose
-- -------
-- 298 made farms.timezoneid the single source of truth for a company's business
-- day. Two OTHER timezone columns already existed:
--
--     hotelprofiles.timezone        (migration 211)
--     restaurantprofiles.timezone   (migration 216)
--
-- Both are free text, both are writable through HotelSetupService /
-- RestaurantSetupService, and neither has ever been read to decide anything.
-- Leaving them writable next to farms.timezoneid is how a platform ends up with
-- two answers to "what day is it" that disagree.
--
-- This migration promotes anything a human actually typed into those columns,
-- then marks them deprecated.
--
-- ON DEV THIS IS A NO-OP. All 3 hotel rows and the 1 restaurant row are blank.
-- It is written to be correct anyway, because prod is a different database and
-- "it was empty when I looked" is not a migration strategy.
--
-- WHY PROMOTED VALUES ARE MARKED CONFIRMED
-- ========================================
-- 298 seeded from currency and marked everything timezoneconfirmed = false,
-- because a machine guessed. A value in hotelprofiles.timezone is different:
-- somebody opened Setup and typed it. That is a decision, so it lands as
-- confirmed = true and Setup will not prompt again.
--
-- It only overwrites an UNCONFIRMED row. If somebody has already confirmed a
-- zone on the company since 298, that is the more recent and more deliberate
-- statement and this migration must not undo it.
--
-- INVALID VALUES ARE LEFT ALONE, NOT GUESSED AT
-- =============================================
-- These columns are free text, so they may hold 'GMT+1', 'EST', 'West Africa
-- Standard Time', or a typo. Only values fncompany_isvalidtimezone() accepts are
-- promoted -- the same predicate spcompany_settimezone uses, so a promoted value
-- is by construction one the setter would have accepted.
--
-- The first draft of this migration tested membership of pg_timezone_names
-- directly, and its own dry run promoted 'EST' -- a fixed -05:00 with no
-- daylight-saving rules. That is what migration 299 exists to fix, and why the
-- test below goes through the shared function rather than repeating a filter.
--
-- Anything unrecognised is REPORTED at the end and left where it is. Mapping
-- 'EST' to America/New_York would be a guess about a real company's business
-- day, and the whole point of timezoneconfirmed is to stop guessing silently.
--
-- The columns are NOT dropped. Dropping them would break HotelSetupService and
-- RestaurantSetupService on a deployment that has not shipped the matching C#
-- yet. They are commented as deprecated; removing them is a later, separate
-- decision once nothing writes them.
--
-- Order: after 299 -- it depends on fncompany_isvalidtimezone.
--
-- Idempotent: re-running promotes nothing new, because the rows it promoted are
-- confirmed by then and the WHERE clause skips them.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Promote real, valid, human-entered zones onto the company.
-- -----------------------------------------------------------------------------
DO $reconcile$
DECLARE
    v_promoted int := 0;
    v_n        int;
BEGIN
    -- Hotel
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema='public' AND table_name='hotelprofiles'
                 AND column_name='timezone') THEN
        WITH candidate AS (
            SELECT h.farmid, btrim(h.timezone) AS tz
            FROM   hotelprofiles h
            WHERE  COALESCE(btrim(h.timezone), '') <> ''
              AND  public.fncompany_isvalidtimezone(btrim(h.timezone))
        )
        UPDATE farms f
        SET    timezoneid = c.tz, timezoneconfirmed = true
        FROM   candidate c
        WHERE  lower(f.farmid::text) = lower(c.farmid::text)
          -- never overwrite a zone someone has already confirmed
          AND  f.timezoneconfirmed = false;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_promoted := v_promoted + v_n;
        RAISE NOTICE 'hotel profiles promoted: %', v_n;
    END IF;

    -- Restaurant
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema='public' AND table_name='restaurantprofiles'
                 AND column_name='timezone') THEN
        WITH candidate AS (
            SELECT r.farmid, btrim(r.timezone) AS tz
            FROM   restaurantprofiles r
            WHERE  COALESCE(btrim(r.timezone), '') <> ''
              AND  public.fncompany_isvalidtimezone(btrim(r.timezone))
        )
        UPDATE farms f
        SET    timezoneid = c.tz, timezoneconfirmed = true
        FROM   candidate c
        WHERE  lower(f.farmid::text) = lower(c.farmid::text)
          AND  f.timezoneconfirmed = false;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_promoted := v_promoted + v_n;
        RAISE NOTICE 'restaurant profiles promoted: %', v_n;
    END IF;

    RAISE NOTICE 'total companies whose zone came from a profile: %', v_promoted;
END
$reconcile$;

-- -----------------------------------------------------------------------------
-- 2. Mark the old columns deprecated, in the database itself.
--
-- A comment is the only form of documentation that travels with the schema and
-- shows up in every client someone might inspect the table from.
-- -----------------------------------------------------------------------------
DO $comments$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema='public' AND table_name='hotelprofiles'
                 AND column_name='timezone') THEN
        COMMENT ON COLUMN hotelprofiles.timezone IS
            'DEPRECATED (migration 299). Free text, never read to decide anything. '
            'The company business timezone is farms.timezoneid -- set it via '
            'spcompany_settimezone, which validates against pg_timezone_names. '
            'Kept only so existing setup code does not break; do not add readers.';
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema='public' AND table_name='restaurantprofiles'
                 AND column_name='timezone') THEN
        COMMENT ON COLUMN restaurantprofiles.timezone IS
            'DEPRECATED (migration 299). Free text, never read to decide anything. '
            'The company business timezone is farms.timezoneid -- set it via '
            'spcompany_settimezone, which validates against pg_timezone_names. '
            'Kept only so existing setup code does not break; do not add readers.';
    END IF;
END
$comments$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification, and the report of anything that could NOT be promoted.
-- -----------------------------------------------------------------------------
SELECT 'companies with a CONFIRMED zone (promoted here, or set by a human)' AS check,
       COUNT(*)::text AS result
FROM   farms WHERE timezoneconfirmed = true

UNION ALL
SELECT 'profile zones that are NOT valid IANA ids (left alone, need a human)',
       COALESCE(string_agg(DISTINCT t.tz, ', '), 'none')
FROM (
    SELECT btrim(h.timezone) AS tz FROM hotelprofiles h
    WHERE COALESCE(btrim(h.timezone),'') <> ''
      AND NOT public.fncompany_isvalidtimezone(btrim(h.timezone))
    UNION ALL
    SELECT btrim(r.timezone) FROM restaurantprofiles r
    WHERE COALESCE(btrim(r.timezone),'') <> ''
      AND NOT public.fncompany_isvalidtimezone(btrim(r.timezone))
) t

UNION ALL
-- The reconciliation must not have invented an invalid zone anywhere.
SELECT 'companies now on a zone the rules refuse',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'INVALID: ' || string_agg(DISTINCT f.timezoneid, ', ') END
FROM   farms f
WHERE  f.timezoneid IS NOT NULL
  AND  NOT public.fncompany_isvalidtimezone(f.timezoneid);
