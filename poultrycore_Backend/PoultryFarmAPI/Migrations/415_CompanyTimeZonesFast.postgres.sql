-- 415: make the business timezone list fast.
--
-- spcompany_timezones (299) took ~9.4 s. It reads pg_timezone_names once
-- (~18 ms; Postgres rebuilds that view from the tz files on every read), then
-- calls fncompany_isvalidtimezone on each of ~600 names, and that function
-- ends with EXISTS (SELECT 1 FROM pg_timezone_names ...) -- re-reading the
-- whole view once per zone. Every name here already comes from that view, so
-- the existence check can never fail; only the name rules matter.
--
-- The list now applies the same rules inline and reads the view once.
-- fncompany_isvalidtimezone is unchanged: the setter still validates the one
-- zone it is given, which is a single read.
--
-- Idempotent (CREATE OR REPLACE); same signature and output as 299.

CREATE OR REPLACE FUNCTION public.spcompany_timezones(p_search text DEFAULT NULL::text)
 RETURNS TABLE(timezoneid text, utcoffset interval, isdst boolean)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT z.name, z.utc_offset, z.is_dst
    FROM   pg_timezone_names z
    -- Same rules as fncompany_isvalidtimezone, minus its existence check:
    -- UTC, or a Region/City id that is not a fixed-offset family.
    WHERE  (z.name = 'UTC'
            OR (z.name LIKE '%/%'
                AND z.name NOT LIKE 'Etc/%'
                AND z.name NOT LIKE 'posix/%'
                AND z.name NOT LIKE 'SystemV/%'))
      AND  (COALESCE(btrim(p_search), '') = ''
            OR z.name ILIKE '%' || btrim(p_search) || '%')
    ORDER  BY z.name;
$function$;
