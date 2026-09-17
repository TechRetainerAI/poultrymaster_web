-- =============================================================================
-- 298_CompanyTimeZone.postgres.sql
--
-- Purpose
-- -------
-- Phase 2 + the database half of Phase 3 of the business-date programme: give a
-- company a real timezone, and give the rest of the system ONE place to ask
-- "what day is it for this company?".
--
-- Nothing in this file changes a number. It adds two columns, seeds them so that
-- today's behaviour is reproduced exactly, and adds four read-only functions
-- that nothing calls yet.
--
-- WHY THIS IS SAFE TO SHIP AHEAD OF THE BEHAVIOURAL WORK
-- ======================================================
-- Every company on this database is seeded to a UTC+0 zone (Africa/Accra) or,
-- for the one Nigerian company, Africa/Lagos. The database session timezone is
-- already UTC, so for 75 of 76 companies "the company's business date" and
-- "the UTC date" are the same string today. The functions below can therefore be
-- adopted call site by call site without any cutover moment.
--
-- WHAT THE AUDIT FOUND, AND WHY THE SEED IS WHAT IT IS
-- ====================================================
-- There is nothing to infer a timezone from:
--
--   farms.location        EXISTS but is BLANK for all 76 companies.
--   hotelprofiles.timezone / restaurantprofiles.timezone
--                         exist, are free text, and are BLANK in all 4 rows.
--                         They have never been read by a single line of UI.
--   AspNetUsers.BusinessOfficeCountry
--                         is the OWNER's country, not the company's. Using it
--                         would encode the exact New-York-owner/Ghana-farm
--                         mistake this programme exists to remove.
--
-- What does exist is currency, on every company: 75 GHS, 1 NGN. So the seed uses
-- currency as a HINT, not as truth:
--
--   GHS -> Africa/Accra   (UTC+0, no DST)
--   NGN -> Africa/Lagos   (UTC+1, no DST)
--   else-> Africa/Accra
--
-- The NGN case is the one that matters. Defaulting it to Accra would put its
-- business date an hour wrong every night between 23:00 and midnight local --
-- a small window, but a real one, and currency makes it free to get right.
--
-- EVERY SEEDED ROW IS MARKED UNCONFIRMED.
-- timezoneconfirmed = false says "a machine guessed this". Company Setup can
-- prompt for it, and spcompany_settimezone flips the flag. Nothing keys
-- behaviour off the flag -- it exists so the product can ask, and so a later
-- audit can tell a guess from a decision.
--
-- IANA IDS, VALIDATED AGAINST THE DATABASE ITSELF
-- ===============================================
-- p_timezoneid is checked against pg_timezone_names, which is the tz database
-- Postgres itself uses for AT TIME ZONE. That is stronger than a hard-coded
-- list: a zone that validates here is, by construction, a zone the conversion
-- functions below can actually use. It also rejects fixed offsets like 'UTC-4'
-- or '+00:00', which break under daylight saving.
--
-- It is enforced in the SETTER rather than as a CHECK constraint, because a
-- CHECK cannot contain a subquery and pg_timezone_names is a view.
--
-- WHAT THIS FILE DELIBERATELY DOES NOT DO
-- =======================================
-- It does not change a single existing function. The ~41 stored procedures that
-- use CURRENT_DATE, and the 488 that use now(), are untouched: converting them
-- is later phases, one reviewable slice at a time, each with its own before/after
-- measurement. Adding the vocabulary first means those slices can be small.
--
-- THE FINDING THAT CHANGES THE WIDER PLAN
-- =======================================
-- Recorded here because the next person planning this work needs it, and the
-- live schema is the only place it is visible:
--
--   Business-date columns on this database are NOT mostly DATE.
--     47 are `timestamp without time zone`  (expense.expensedate,
--        genericsales.saledate, watersales.saledate, every *.purchasedate,
--        every *.transactiondate, every *.paymentdate ...)
--     17 are `date`  (eggproduction.productiondate, sale.saledate, the five
--        *dailyclosings.closingdate, poultryloans.loandate ...)
--      1 is timestamptz (hotelpayments.paymentdate)
--
-- So the "BusinessDate is a DATE, add OccurredAtUtc beside it" target describes
-- a shape most of this schema does not have. For those 47, the pragmatic reading
-- is that the column ALREADY carries date+time and what is missing is only the
-- guarantee about which zone the date part belongs to -- which is what these
-- functions provide. Converting 47 columns to DATE + a new timestamp column
-- would be a large destructive migration for little gain, and is not assumed
-- here either way. It is a decision, and it has not been made.
--
-- And the legacy-timestamp question (section 50 of the brief) is SETTLED:
--   the database session timezone is UTC, so the 400 `now() at time zone 'utc'`
--   and the 488 bare `now()` calls produce identical values. Every legacy
--   timestamp on this database is UTC. No forensics needed.
--   (Not pinned by the application, though -- see the note on section 4 below.)
--
-- Order: after 297.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The company's timezone.
-- -----------------------------------------------------------------------------
ALTER TABLE farms ADD COLUMN IF NOT EXISTS timezoneid        text;
ALTER TABLE farms ADD COLUMN IF NOT EXISTS timezoneconfirmed boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN farms.timezoneid IS
    'IANA timezone id (Africa/Accra, America/New_York). The source of truth for '
    'this company''s business date. Never a fixed offset: those break under '
    'daylight saving. Validated against pg_timezone_names by '
    'spcompany_settimezone.';

COMMENT ON COLUMN farms.timezoneconfirmed IS
    'FALSE means 298 guessed this from the company currency and nobody has '
    'confirmed it. Nothing keys behaviour off this flag -- it exists so Company '
    'Setup can prompt, and so a later audit can tell a guess from a decision.';

-- -----------------------------------------------------------------------------
-- 2. Seed. Currency is a hint, never truth -- hence confirmed = false.
--
-- Only fills a NULL, so re-running cannot overwrite a zone somebody has since
-- chosen, and cannot un-confirm a confirmed one.
-- -----------------------------------------------------------------------------
UPDATE farms
SET    timezoneid = CASE upper(btrim(COALESCE(currencycode, '')))
                         WHEN 'NGN' THEN 'Africa/Lagos'   -- UTC+1
                         ELSE            'Africa/Accra'   -- UTC+0
                    END,
       timezoneconfirmed = false
WHERE  timezoneid IS NULL;

-- -----------------------------------------------------------------------------
-- 3. The company's zone, with a fallback that cannot change behaviour.
--
-- 'UTC' rather than 'Africa/Accra' for a company with no zone at all: the two
-- are the same instant today, but UTC is the honest answer to "we do not know",
-- and it reproduces exactly what every caller does before this migration.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fncompany_timezone(p_farmid text)
RETURNS text
LANGUAGE sql STABLE
AS $function$
    -- The COALESCE must wrap the SUBQUERY, not sit inside it. Inside, it only
    -- defends against a NULL column; an unknown farm id matches no row at all,
    -- the function returns zero rows, and the result is NULL -- which would
    -- then propagate into AT TIME ZONE and make fncompany_businessdate NULL.
    -- The dry run caught exactly this.
    SELECT COALESCE(
             (SELECT NULLIF(btrim(f.timezoneid), '')
              FROM   farms f
              WHERE  lower(f.farmid::text) = lower(p_farmid)
              LIMIT  1),
             'UTC');
$function$;

COMMENT ON FUNCTION public.fncompany_timezone(text) IS
    'This company''s IANA zone, or UTC when unset or the company is unknown. '
    'UTC is the pre-298 behaviour, so an unset company behaves exactly as it '
    'did before.';

-- -----------------------------------------------------------------------------
-- 4. What day is it, for this company?
--
-- THE function. Every "today" in the platform should end up here.
--
-- now() is used rather than (now() at time zone 'utc') on purpose: now() returns
-- timestamptz -- an absolute instant, independent of the session zone -- and
-- AT TIME ZONE converts that instant into the company's wall clock. Writing
-- (now() at time zone 'utc') first would strip the zone and make the result
-- depend on the session setting, which is the very bug this replaces.
--
-- NOTE: the session timezone on this database is currently UTC and nothing in
-- the application pins it. This function does not care -- that is the point --
-- but the ~41 CURRENT_DATE procedures still do, until they are converted.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fncompany_businessdate(p_farmid text)
RETURNS date
LANGUAGE sql STABLE
AS $function$
    SELECT (now() AT TIME ZONE public.fncompany_timezone(p_farmid))::date;
$function$;

COMMENT ON FUNCTION public.fncompany_businessdate(text) IS
    'Today, for this company. The one definition of "today" the platform should '
    'use -- not the browser''s, not the server''s, not UTC.';

-- -----------------------------------------------------------------------------
-- 5. A business day's UTC bounds, HALF-OPEN.
--
-- [start, end) deliberately. 23:59:59.999 loses whatever falls in the last
-- fraction of a second, and the size of that gap depends on the column's
-- precision -- which differs across this schema.
--
-- Returns timestamptz so a caller cannot accidentally reinterpret the bounds in
-- another zone. Against a `timestamp without time zone` column, compare as
-- `col >= (startutc AT TIME ZONE 'UTC') AND col < (endutc AT TIME ZONE 'UTC')`
-- -- every legacy timestamp on this database is UTC (see the header).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fncompany_businessdayrange(
    p_farmid text,
    p_date   date
) RETURNS TABLE(startutc timestamptz, endutc timestamptz)
LANGUAGE sql STABLE
AS $function$
    SELECT (p_date::timestamp     AT TIME ZONE public.fncompany_timezone(p_farmid)),
           ((p_date + 1)::timestamp AT TIME ZONE public.fncompany_timezone(p_farmid));
$function$;

COMMENT ON FUNCTION public.fncompany_businessdayrange(text, date) IS
    'The UTC instants bounding one of this company''s business days, HALF-OPEN: '
    'start inclusive, end exclusive. Never build a range with 23:59:59.';

-- -----------------------------------------------------------------------------
-- 6. The context the API hands the frontend (section 11 of the brief).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spcompany_timecontext(p_farmid text)
RETURNS TABLE(
    farmid              text,
    timezoneid          text,
    timezoneconfirmed   boolean,
    businessdate        date,
    companylocaldatetime timestamp,
    utcnow              timestamptz
)
LANGUAGE sql STABLE
AS $function$
    SELECT p_farmid,
           public.fncompany_timezone(p_farmid),
           COALESCE((SELECT f.timezoneconfirmed FROM farms f
                     WHERE lower(f.farmid::text) = lower(p_farmid) LIMIT 1), false),
           public.fncompany_businessdate(p_farmid),
           (now() AT TIME ZONE public.fncompany_timezone(p_farmid)),
           now();
$function$;

COMMENT ON FUNCTION public.spcompany_timecontext(text) IS
    'Everything the frontend needs to stop asking the browser what day it is. '
    'businessdate is what a date field should default to.';

-- -----------------------------------------------------------------------------
-- 7. Setting the zone -- the only writer, and where IANA is enforced.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spcompany_settimezone(
    p_farmid     text,
    p_timezoneid text,
    p_updatedby  text DEFAULT NULL
) RETURNS TABLE(timezoneid text, timezoneconfirmed boolean, businessdate date)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_tz text := btrim(COALESCE(p_timezoneid, ''));
BEGIN
    IF v_tz = '' THEN
        RAISE EXCEPTION 'A timezone is required.';
    END IF;

    -- pg_timezone_names is the tz database Postgres uses for AT TIME ZONE, so a
    -- zone that passes here is one the conversion functions can actually use.
    -- It also rejects 'GMT+1', 'UTC-4' and '+00:00', which have no daylight
    -- saving rules and silently go wrong twice a year for zones that do.
    IF NOT EXISTS (SELECT 1 FROM pg_timezone_names z WHERE z.name = v_tz) THEN
        RAISE EXCEPTION
          'Not a known IANA timezone: "%". Use a region id such as Africa/Accra '
          'or America/New_York, not a fixed offset.', v_tz;
    END IF;

    UPDATE farms f
    SET    timezoneid        = v_tz,
           timezoneconfirmed = true,
           updatedby         = COALESCE(p_updatedby, f.updatedby),
           updatedat         = (now() at time zone 'utc')
    WHERE  lower(f.farmid::text) = lower(p_farmid);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Company % not found.', p_farmid;
    END IF;

    RETURN QUERY
    SELECT v_tz, true, public.fncompany_businessdate(p_farmid);
END;
$function$;

COMMENT ON FUNCTION public.spcompany_settimezone(text, text, text) IS
    'Set a company''s business timezone. Validates against pg_timezone_names and '
    'marks it confirmed. Changing it does NOT rewrite historical business dates '
    '-- only how future defaults, "today", and report boundaries are decided.';

-- -----------------------------------------------------------------------------
-- 8. Grants.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.fncompany_timezone(text)                 TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.fncompany_businessdate(text)             TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.fncompany_businessdayrange(text, date)   TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spcompany_timecontext(text)              TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spcompany_settimezone(text, text, text)  TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'every company has a timezone' AS check,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'MISSING ON ' || COUNT(*) END AS result
FROM   farms WHERE COALESCE(isdeleted,false) = false AND timezoneid IS NULL

UNION ALL
SELECT 'every seeded zone is a real IANA id',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'INVALID: ' || string_agg(DISTINCT timezoneid, ', ') END
FROM   farms f
WHERE  f.timezoneid IS NOT NULL
  AND  NOT EXISTS (SELECT 1 FROM pg_timezone_names z WHERE z.name = f.timezoneid)

UNION ALL
SELECT 'every seeded zone is marked unconfirmed',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   farms WHERE timezoneconfirmed = true

UNION ALL
-- The claim that makes this safe: for a UTC+0 company the new definition of
-- today and the old one agree, so adopting the function changes nothing.
SELECT 'business date matches UTC date for every UTC+0 company',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'DIFFERS ON ' || COUNT(*) END
FROM   farms f
WHERE  COALESCE(f.isdeleted,false) = false
  AND  f.timezoneid = 'Africa/Accra'
  AND  public.fncompany_businessdate(f.farmid) <> (now() at time zone 'utc')::date;
