-- Checks for 298_CompanyTimeZone.
--
-- Run inside the dry-run transaction, after the migration body. Every assertion
-- prints "expect X got Y"; the runner fails the run if any pair disagrees.
--
-- The point of these checks is NOT that the new functions work in isolation --
-- it is that adopting them cannot move a number. So most of them compare the
-- new definition of "today" against the old one and demand they agree.

\pset footer off
\echo
\echo === A. Every company got a zone, and it is a real IANA id ===
SELECT 'companies without a timezone  expect 0 got '
       || COUNT(*)::text AS check
FROM   farms WHERE COALESCE(isdeleted,false) = false AND timezoneid IS NULL;

SELECT 'zones postgres does not know  expect 0 got '
       || COUNT(*)::text AS check
FROM   farms f
WHERE  f.timezoneid IS NOT NULL
  AND  NOT EXISTS (SELECT 1 FROM pg_timezone_names z WHERE z.name = f.timezoneid);

\echo
\echo === B. Nothing is silently marked as confirmed ===
-- A machine guessed these. If any row claims otherwise the seed is lying.
SELECT 'seeded rows claiming confirmed  expect 0 got '
       || COUNT(*)::text AS check
FROM   farms WHERE timezoneconfirmed = true;

\echo
\echo === C. The seed follows currency, and the NGN company is NOT Accra ===
SELECT 'GHS companies not on Africa/Accra  expect 0 got '
       || COUNT(*)::text AS check
FROM   farms
WHERE  upper(btrim(COALESCE(currencycode,''))) = 'GHS'
  AND  timezoneid <> 'Africa/Accra';

SELECT 'NGN companies not on Africa/Lagos  expect 0 got '
       || COUNT(*)::text AS check
FROM   farms
WHERE  upper(btrim(COALESCE(currencycode,''))) = 'NGN'
  AND  timezoneid <> 'Africa/Lagos';

\echo
\echo === D. THE SAFETY CLAIM: for a UTC+0 company, new today = old today ===
-- This is what makes the functions adoptable call site by call site with no
-- cutover. If this ever fails, adopting fncompany_businessdate somewhere would
-- change a report boundary.
SELECT 'UTC+0 companies where business date <> UTC date  expect 0 got '
       || COUNT(*)::text AS check
FROM   farms f
WHERE  COALESCE(f.isdeleted,false) = false
  AND  f.timezoneid = 'Africa/Accra'
  AND  public.fncompany_businessdate(f.farmid) <> (now() at time zone 'utc')::date;

\echo
\echo === E. An unknown company falls back to UTC, i.e. to today s behaviour ===
-- COALESCE on every value a check prints. Without it a NULL result makes the
-- whole concatenation NULL, the row renders blank, and the runner's
-- "expect X got Y" scan finds nothing to compare -- so a real failure passes
-- silently. That is how the missing UTC fallback nearly got through.
SELECT 'unknown farm id resolves to  expect UTC got '
       || COALESCE(public.fncompany_timezone('no-such-farm-00000000'), '(null)') AS check;

SELECT 'unknown farm business date = UTC date  expect true got '
       || COALESCE((public.fncompany_businessdate('no-such-farm-00000000')
                    = (now() at time zone 'utc')::date)::text, '(null)') AS check;

-- The same trap one level down: a NULL zone would silently disable the range.
SELECT 'unknown farm day range is 24h  expect 86400 got '
       || COALESCE(EXTRACT(epoch FROM (r.endutc - r.startutc))::bigint::text, '(null)') AS check
FROM   public.fncompany_businessdayrange('no-such-farm-00000000', DATE '2026-09-15') r;

\echo
\echo === F. The day range is half-open and exactly 24h for a no-DST zone ===
-- Africa/Accra and Africa/Lagos have no daylight saving, so every day is 24h.
-- A 23:59:59 range would show 86399 here, which is the bug this avoids.
SELECT 'Accra business day length in seconds  expect 86400 got '
       || EXTRACT(epoch FROM (r.endutc - r.startutc))::bigint::text AS check
FROM   public.fncompany_businessdayrange(
         (SELECT farmid FROM farms WHERE timezoneid='Africa/Accra' LIMIT 1),
         DATE '2026-09-15') r;

-- Consecutive days must abut exactly: day N end = day N+1 start. That is what
-- half-open buys, and it is why no transaction can fall between two days.
SELECT 'gap between consecutive business days  expect 00:00:00 got '
       || (b.startutc - a.endutc)::text AS check
FROM   public.fncompany_businessdayrange(
         (SELECT farmid FROM farms WHERE timezoneid='Africa/Accra' LIMIT 1),
         DATE '2026-09-15') a,
       public.fncompany_businessdayrange(
         (SELECT farmid FROM farms WHERE timezoneid='Africa/Accra' LIMIT 1),
         DATE '2026-09-16') b;

\echo
\echo === G. The NGN company really does differ -- the reason 298 bothers ===
-- Africa/Lagos is UTC+1, so its business day starts an hour BEFORE the UTC day.
-- If this shows 0 the Lagos seed is not doing anything and should be questioned.
SELECT 'Lagos day start vs UTC day start, hours  expect -1 got '
       || ROUND(EXTRACT(epoch FROM (
             (SELECT startutc FROM public.fncompany_businessdayrange(
                 (SELECT farmid FROM farms WHERE timezoneid='Africa/Lagos' LIMIT 1),
                 DATE '2026-09-15'))
           - (DATE '2026-09-15'::timestamp AT TIME ZONE 'UTC')
           )) / 3600)::text AS check;

\echo
\echo === H. The setter validates, and rejects fixed offsets ===
DO $$
DECLARE v_farm text; v_ok boolean;
BEGIN
    SELECT farmid INTO v_farm FROM farms WHERE COALESCE(isdeleted,false)=false LIMIT 1;

    -- a fixed offset must be refused: it has no DST rules
    BEGIN
        PERFORM public.spcompany_settimezone(v_farm, 'UTC+1');
        v_ok := false;
    EXCEPTION WHEN others THEN
        v_ok := true;
    END;
    RAISE NOTICE 'fixed offset UTC+1 rejected  expect t got %', v_ok;

    BEGIN
        PERFORM public.spcompany_settimezone(v_farm, 'Mars/Olympus');
        v_ok := false;
    EXCEPTION WHEN others THEN
        v_ok := true;
    END;
    RAISE NOTICE 'nonsense zone rejected  expect t got %', v_ok;

    BEGIN
        PERFORM public.spcompany_settimezone(v_farm, '   ');
        v_ok := false;
    EXCEPTION WHEN others THEN
        v_ok := true;
    END;
    RAISE NOTICE 'blank zone rejected  expect t got %', v_ok;

    -- a real zone must be accepted AND must flip the confirmed flag
    PERFORM public.spcompany_settimezone(v_farm, 'America/New_York', 'check');
    SELECT (timezoneid = 'America/New_York' AND timezoneconfirmed)
      INTO v_ok FROM farms WHERE farmid = v_farm;
    RAISE NOTICE 'real zone accepted and confirmed  expect t got %', v_ok;

    -- and the business date must now follow New York, not UTC. At 00:30 UTC
    -- New York is still on the previous day, which is the entire point.
    RAISE NOTICE 'New York business date  expect % got %',
        (now() AT TIME ZONE 'America/New_York')::date,
        public.fncompany_businessdate(v_farm);
END $$;

\echo
\echo === I. The time context an API would return ===
SELECT * FROM public.spcompany_timecontext(
    (SELECT farmid FROM farms WHERE timezoneid='Africa/Lagos' LIMIT 1));

\echo
\echo === J. Distribution of what was seeded ===
SELECT timezoneid, COUNT(*) AS companies,
       COUNT(*) FILTER (WHERE timezoneconfirmed) AS confirmed
FROM   farms GROUP BY timezoneid ORDER BY companies DESC;
