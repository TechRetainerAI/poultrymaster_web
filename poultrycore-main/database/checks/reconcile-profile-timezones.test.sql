-- Checks for 300_ReconcileProfileTimeZones.
--
-- Runs inside the dry-run transaction, AFTER the migration body and after
-- reconcile-profile-timezones.seed.sql has planted the three cases.
--
-- Every value is wrapped in COALESCE: a NULL would make the whole concatenation
-- NULL, the row would render blank, and the runner's "expect X got Y" scan
-- would find nothing to compare -- a silent pass on a real failure. That is how
-- 298's missing UTC fallback nearly got through.

\pset footer off

\echo
\echo === A. A valid profile zone is promoted, and lands CONFIRMED ===
-- Confirmed, because a human typed it in Setup. 298's currency guess was not a
-- decision; this is.
SELECT 'valid profile zone promoted  expect Africa/Nairobi got '
       || COALESCE((SELECT f.timezoneid FROM farms f
                    JOIN seed299 s ON s.scenario='valid'
                    WHERE lower(f.farmid::text) = lower(s.farmid)), '(null)') AS check;

SELECT 'promoted zone marked confirmed  expect true got '
       || COALESCE((SELECT f.timezoneconfirmed::text FROM farms f
                    JOIN seed299 s ON s.scenario='valid'
                    WHERE lower(f.farmid::text) = lower(s.farmid)), '(null)') AS check;

\echo
\echo === B. Free text that is not an IANA id is LEFT ALONE, not guessed ===
-- 'EST' IS in pg_timezone_names -- it is a fixed -05:00 with no daylight-saving
-- rules -- so the first draft of 300 promoted it. fncompany_isvalidtimezone (299)
-- now refuses it, and it must be left alone rather than mapped to
-- America/New_York: that would be a guess about a real company's business day,
-- which is the thing timezoneconfirmed exists to prevent.
SELECT 'company with invalid profile zone keeps 298 seed  expect Africa/Accra got '
       || COALESCE((SELECT f.timezoneid FROM farms f
                    JOIN seed299 s ON s.scenario='invalid'
                    WHERE lower(f.farmid::text) = lower(s.farmid)), '(null)') AS check;

SELECT 'and is still UNCONFIRMED so Setup will ask  expect false got '
       || COALESCE((SELECT f.timezoneconfirmed::text FROM farms f
                    JOIN seed299 s ON s.scenario='invalid'
                    WHERE lower(f.farmid::text) = lower(s.farmid)), '(null)') AS check;

SELECT 'the invalid value is still in the profile column  expect EST got '
       || COALESCE((SELECT h.timezone FROM hotelprofiles h
                    JOIN seed299 s ON s.scenario='invalid'
                    WHERE h.farmid = s.farmid), '(null)') AS check;

\echo
\echo === C. An already-CONFIRMED company is never overwritten ===
-- The restaurant profile says Asia/Dubai, the company says Europe/London and a
-- human confirmed it. The human wins.
--
-- This case is also the only thing that runs 300's restaurant promotion block
-- at all -- without it that half of the migration is never executed.
SELECT 'confirmed company keeps its zone  expect Europe/London got '
       || COALESCE((SELECT f.timezoneid FROM farms f
                    JOIN seed299 s ON s.scenario='already_confirmed'
                    WHERE lower(f.farmid::text) = lower(s.farmid)), '(null)') AS check;

\echo
\echo === D. Nothing lost a zone, and no zone became invalid ===
SELECT 'companies without a timezone  expect 0 got '
       || COUNT(*)::text AS check
FROM   farms WHERE COALESCE(isdeleted,false) = false AND timezoneid IS NULL;

-- Through the strict predicate, not a bare catalogue lookup -- the loose test
-- is what let 'EST' through in the first place.
SELECT 'companies on a zone the rules refuse  expect 0 got '
       || COUNT(*)::text AS check
FROM   farms f
WHERE  f.timezoneid IS NOT NULL
  AND  NOT public.fncompany_isvalidtimezone(f.timezoneid);

\echo
\echo === E. The business date still works for a promoted company ===
-- Nairobi is UTC+3, so its day starts 3 hours BEFORE the UTC day. If this reads
-- 0 the promotion changed the stored text without changing behaviour.
SELECT 'Nairobi day start vs UTC day start, hours  expect -3 got '
       || COALESCE(ROUND(EXTRACT(epoch FROM (
             (SELECT r.startutc FROM seed299 s,
                LATERAL public.fncompany_businessdayrange(s.farmid, DATE '2026-09-15') r
              WHERE s.scenario='valid')
           - (DATE '2026-09-15'::timestamp AT TIME ZONE 'UTC')
           )) / 3600)::text, '(null)') AS check;

\echo
\echo === F. Idempotency: running the promotion again changes nothing ===
-- The promoted rows are confirmed by now, so the WHERE clause must skip them.
-- If this reports any rows, a re-run would fight with human decisions.
SELECT 'rows a second run would still promote  expect 0 got '
       || COUNT(*)::text AS check
FROM   hotelprofiles h
JOIN   farms f ON lower(f.farmid::text) = lower(h.farmid::text)
WHERE  COALESCE(btrim(h.timezone),'') <> ''
  AND  public.fncompany_isvalidtimezone(btrim(h.timezone))
  AND  f.timezoneconfirmed = false;

\echo
\echo === G. The deprecation comments are actually on the columns ===
SELECT 'hotelprofiles.timezone marked deprecated  expect true got '
       || COALESCE((col_description('hotelprofiles'::regclass,
                      (SELECT ordinal_position FROM information_schema.columns
                       WHERE table_schema='public' AND table_name='hotelprofiles'
                         AND column_name='timezone')::int)
                    LIKE 'DEPRECATED%')::text, '(null)') AS check;

SELECT 'restaurantprofiles.timezone marked deprecated  expect true got '
       || COALESCE((col_description('restaurantprofiles'::regclass,
                      (SELECT ordinal_position FROM information_schema.columns
                       WHERE table_schema='public' AND table_name='restaurantprofiles'
                         AND column_name='timezone')::int)
                    LIKE 'DEPRECATED%')::text, '(null)') AS check;

\echo
\echo === H. What the reconciliation did ===
SELECT s.scenario, s.planted AS seeded_profile_value,
       f.timezoneid AS company_zone, f.timezoneconfirmed
FROM   seed299 s
JOIN   farms f ON lower(f.farmid::text) = lower(s.farmid)
ORDER  BY s.scenario;
