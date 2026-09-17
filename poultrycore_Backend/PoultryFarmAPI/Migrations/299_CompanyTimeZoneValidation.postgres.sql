-- =============================================================================
-- 299_CompanyTimeZoneValidation.postgres.sql
--
-- Purpose
-- -------
-- Close a hole in 298. Its header says a company timezone must be a region id
-- and never a fixed offset, "because those break under daylight saving" -- but
-- its validation only checks membership of pg_timezone_names, and that catalogue
-- contains the fixed offsets too.
--
-- THE BUG
-- =======
-- spcompany_settimezone rejected 'UTC+1' and 'Mars/Olympus' in testing, which
-- made the validation look correct. It also accepts, today:
--
--     EST          -05:00, is_dst = f      <- the dangerous one
--     MST          -07:00, is_dst = f
--     HST          -10:00, is_dst = f
--     GMT, UCT     +00:00
--     EST5EDT      a legacy pseudo-zone
--     Etc/GMT+5    a fixed offset wearing a region-shaped name
--                  (and note its sign is INVERTED: Etc/GMT+5 is UTC-5)
--
-- 44 bare abbreviations and 35 Etc/ entries, out of 597 rows.
--
-- A company set to 'EST' is correct all winter and an hour wrong all summer,
-- every year, silently -- because EST is a fixed -05:00 with no daylight-saving
-- rules, whereas the place people mean by "EST" is America/New_York, which
-- moves to -04:00 in March. Business dates recorded between 23:00 and midnight
-- would land on the wrong day for half the year.
--
-- This was found by the 300 dry run, which planted 'EST' as an example of
-- free text that "obviously" is not a valid IANA id -- and watched the
-- reconciliation happily promote it.
--
-- THE FIX: ONE PREDICATE, SHARED
-- ==============================
-- fncompany_isvalidtimezone() below is now the single definition of "a zone a
-- company may use", and BOTH the setter and the picker are rebuilt on it.
--
-- That matters more than the predicate itself. 298 had a list-of-zones query in
-- C# (CompanyTimeService.GetZonesAsync) with a Region/City filter, and a
-- DIFFERENT, looser check in the SP. The picker refused to offer 'EST' while the
-- setter happily accepted it -- so the API contract depended on which door you
-- came through. Two places defining the same rule is how they drift; there is
-- now one, in SQL, and the C# calls it.
--
-- THE RULE
-- ========
--   'UTC' exactly                     allowed -- the documented fallback, and a
--                                     legitimate deliberate choice
--   Region/City (contains '/')        allowed
--   Etc/*, posix/*, SystemV/*         refused -- fixed offsets and legacy dupes
--   anything without '/'              refused -- abbreviations
--   not in pg_timezone_names          refused -- unknown to AT TIME ZONE
--
-- NO DATA CHANGES. On dev no company is on an invalid zone (298 seeded only
-- Africa/Accra and Africa/Lagos). The migration REPORTS any that are rather
-- than rewriting them: silently moving a company's business day is exactly the
-- class of change this programme refuses to make without a human.
--
-- Order: after 298, before 300.
--
-- Idempotent.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The one definition of a usable company timezone.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fncompany_isvalidtimezone(p_timezoneid text)
RETURNS boolean
LANGUAGE sql STABLE
AS $function$
    SELECT CASE
        WHEN btrim(COALESCE(p_timezoneid, '')) = '' THEN false
        -- UTC is the fallback fncompany_timezone returns for a company with no
        -- zone, so it must be settable too -- otherwise a company could be in a
        -- state the setter cannot reproduce.
        WHEN btrim(p_timezoneid) = 'UTC' THEN true
        -- Must be a Region/City id. Abbreviations (EST, MST, GMT) and the Etc/
        -- family are fixed offsets with no daylight-saving rules.
        WHEN btrim(p_timezoneid) NOT LIKE '%/%'        THEN false
        WHEN btrim(p_timezoneid) LIKE 'Etc/%'          THEN false
        WHEN btrim(p_timezoneid) LIKE 'posix/%'        THEN false
        WHEN btrim(p_timezoneid) LIKE 'SystemV/%'      THEN false
        -- And it must be a zone this server's tz database actually knows, since
        -- that is what AT TIME ZONE will consult.
        ELSE EXISTS (SELECT 1 FROM pg_timezone_names z WHERE z.name = btrim(p_timezoneid))
    END;
$function$;

COMMENT ON FUNCTION public.fncompany_isvalidtimezone(text) IS
    'The single definition of a timezone a company may be set to: UTC, or a '
    'Region/City IANA id this server knows. Refuses abbreviations (EST, MST) and '
    'the Etc/ fixed offsets -- they have no daylight-saving rules, so a company '
    'on one is silently an hour wrong for half of every year. Used by BOTH '
    'spcompany_settimezone and spcompany_timezones so the two cannot disagree.';

-- -----------------------------------------------------------------------------
-- 2. The picker, moved out of C# so it shares the predicate above.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spcompany_timezones(p_search text DEFAULT NULL)
RETURNS TABLE(timezoneid text, utcoffset interval, isdst boolean)
LANGUAGE sql STABLE
AS $function$
    SELECT z.name, z.utc_offset, z.is_dst
    FROM   pg_timezone_names z
    WHERE  public.fncompany_isvalidtimezone(z.name)
      AND  (COALESCE(btrim(p_search), '') = ''
            OR z.name ILIKE '%' || btrim(p_search) || '%')
    ORDER  BY z.name;
$function$;

COMMENT ON FUNCTION public.spcompany_timezones(text) IS
    'The zones a company may choose. Every row is guaranteed to pass '
    'spcompany_settimezone, because both are built on fncompany_isvalidtimezone.';

-- -----------------------------------------------------------------------------
-- 3. Rebuild the setter on the shared predicate.
--
-- Body is 298's, with only the validation branch changed. The error message now
-- names the specific problem, because "not a known IANA timezone" was actively
-- misleading for 'EST' -- which IS known, and is still wrong to use.
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

    IF NOT public.fncompany_isvalidtimezone(v_tz) THEN
        -- Distinguish the two failures. Telling someone that 'EST' is "not a
        -- known timezone" is false and unhelpful; the real objection is that it
        -- is a fixed offset.
        IF EXISTS (SELECT 1 FROM pg_timezone_names z WHERE z.name = v_tz) THEN
            RAISE EXCEPTION
              '"%" is a fixed-offset or abbreviated timezone, which has no '
              'daylight-saving rules -- a company using it would be an hour '
              'wrong for part of the year. Use the Region/City id for the place '
              'instead, such as America/New_York rather than EST.', v_tz;
        ELSE
            RAISE EXCEPTION
              'Not a known IANA timezone: "%". Use a region id such as '
              'Africa/Accra or America/New_York.', v_tz;
        END IF;
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
    'Set a company''s business timezone. Validates with '
    'fncompany_isvalidtimezone. Changing it does NOT rewrite historical business '
    'dates -- only how future defaults, "today", and report boundaries are decided.';

-- -----------------------------------------------------------------------------
-- 4. Grants.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.fncompany_isvalidtimezone(text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spcompany_timezones(text)       TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification, plus the report of anything already on a bad zone.
-- -----------------------------------------------------------------------------
SELECT 'EST is now refused (it was accepted before)' AS check,
       CASE WHEN public.fncompany_isvalidtimezone('EST') THEN 'STILL ACCEPTED' ELSE 'OK' END AS result

UNION ALL SELECT 'Etc/GMT+5 refused',
       CASE WHEN public.fncompany_isvalidtimezone('Etc/GMT+5') THEN 'STILL ACCEPTED' ELSE 'OK' END
UNION ALL SELECT 'America/New_York accepted',
       CASE WHEN public.fncompany_isvalidtimezone('America/New_York') THEN 'OK' ELSE 'WRONGLY REFUSED' END
UNION ALL SELECT 'UTC accepted (it is the fallback)',
       CASE WHEN public.fncompany_isvalidtimezone('UTC') THEN 'OK' ELSE 'WRONGLY REFUSED' END
UNION ALL SELECT 'Africa/Accra accepted',
       CASE WHEN public.fncompany_isvalidtimezone('Africa/Accra') THEN 'OK' ELSE 'WRONGLY REFUSED' END

UNION ALL
-- Picker and setter must agree by construction. If this is ever non-zero the
-- two have drifted apart again.
SELECT 'zones the picker offers that the setter would refuse',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'DRIFT: ' || COUNT(*)::text END
FROM   public.spcompany_timezones() p
WHERE  NOT public.fncompany_isvalidtimezone(p.timezoneid)

UNION ALL
-- Reported, NOT rewritten. Moving a company's business day is a human decision.
SELECT 'companies currently on a zone the new rule refuses',
       COALESCE(string_agg(DISTINCT f.name || ' (' || f.timezoneid || ')', ', '), 'none')
FROM   farms f
WHERE  COALESCE(f.isdeleted,false) = false
  AND  f.timezoneid IS NOT NULL
  AND  NOT public.fncompany_isvalidtimezone(f.timezoneid);
