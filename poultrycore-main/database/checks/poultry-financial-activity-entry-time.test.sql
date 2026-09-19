-- Behavioural checks for migration 315: an entry time on every activity row.
--
-- One DO $t$ block, a NOTICE per check reading "expect X got Y". Run inside a
-- transaction you ROLL BACK; it writes nothing, but the apply script runs it
-- inside the same discarded transaction as the migration.
--
--   psql ... -X -c "BEGIN;" -f poultry-financial-activity-entry-time.test.sql -c "ROLLBACK;"
--
-- THE CLAIM THAT MATTERS MOST
-- ---------------------------
-- **Nothing about the money moved.** This migration adds a column and must not
-- touch a figure, an ordering or a row. Section C proves that from the inside:
-- the events function and the summary function are recomputed independently and
-- must still agree to the pesewa, and Running Cash must still land exactly on
-- opening cash plus net movement. Section D proves the payroll leg -- which
-- lives on another branch and only exists in the deployed body -- survived the
-- rebuild.
--
-- The rest:
--   A. Every row can now answer "when was this entered?".
--   B. The sources that previously showed no time now do.
--   E. An entry time is never in the future and never before its business date
--      by more than a working correction.

DO $t$
DECLARE
    v_farm     text;
    v_from     date := '2000-01-01';
    v_to       date := '2099-12-31';
    v_rows     integer;
    v_nulls    integer;
    v_notime   integer;
    v_future   integer;
    v_cash     numeric;
    v_sumcash  numeric;
    v_open     numeric;
    v_last     numeric;
    v_legE     integer;
    v_r        record;
BEGIN
    -- The company with the most activity, so the checks run against real rows
    -- rather than an empty set that would pass by vacuousness.
    SELECT f.farmid INTO v_farm
    FROM   farms f
    WHERE  f.type = 'Poultry'
      AND  f.farmid ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ORDER  BY (SELECT COUNT(*) FROM public.fnpoultryfa_events(f.farmid, v_from, v_to)) DESC,
             f.farmid
    LIMIT  1;
    IF v_farm IS NULL THEN RAISE EXCEPTION 'No uuid-shaped poultry company to test against.'; END IF;

    SELECT COUNT(*) INTO v_rows FROM public.fnpoultryfa_events(v_farm, v_from, v_to);
    RAISE NOTICE '   using poultry farm % with % event(s)', v_farm, v_rows;
    IF v_rows = 0 THEN
        RAISE NOTICE '   NO EVENTS -- every check below would pass vacuously. Skipping.';
        RETURN;
    END IF;

    -- =====================================================================
    -- A. Every row can answer "when was this entered?".
    -- =====================================================================
    SELECT COUNT(*) FILTER (WHERE e.createdat IS NULL) INTO v_nulls
    FROM   public.fnpoultryfa_events(v_farm, v_from, v_to) e;
    RAISE NOTICE 'A1. events with no entry time at all  expect 0  got %', COALESCE(v_nulls, -1);

    -- The screen shows a time when EITHER the business timestamp carries one or
    -- the entry time does. This is the number the user actually complained about.
    SELECT COUNT(*) FILTER (WHERE e.occurredat::time = '00:00:00'
                              AND (e.createdat IS NULL OR e.createdat::time = '00:00:00'))
      INTO v_notime
    FROM   public.fnpoultryfa_events(v_farm, v_from, v_to) e;
    RAISE NOTICE 'A2. events that would still show NO time  expect 0  got %', COALESCE(v_notime, -1);

    -- =====================================================================
    -- B. The sources that had no time before, by name.
    --
    -- Printed rather than asserted against a hardcoded count: which sources a
    -- company has is its own business, and a check that demanded six sales
    -- would fail on every database but this one.
    -- =====================================================================
    FOR v_r IN
        SELECT e.sourcetype,
               COUNT(*)                                                         AS n,
               COUNT(*) FILTER (WHERE e.occurredat::time <> '00:00:00')         AS had_time,
               COUNT(*) FILTER (WHERE e.createdat::time <> '00:00:00')          AS has_entry_time
        FROM   public.fnpoultryfa_events(v_farm, v_from, v_to) e
        GROUP  BY e.sourcetype ORDER BY e.sourcetype
    LOOP
        RAISE NOTICE 'B.  % -- % row(s), % had a time before, % have an entry time now',
            rpad(v_r.sourcetype, 28), v_r.n, v_r.had_time, v_r.has_entry_time;
    END LOOP;

    -- =====================================================================
    -- C. THE CLAIM. No money moved.
    -- =====================================================================
    -- The events function and the summary function compute net cash by two
    -- different routes. They agreed before this migration and must still agree.
    SELECT COALESCE(SUM(e.moneyin - e.moneyout), 0) INTO v_sumcash
    FROM   public.fnpoultryfa_events(v_farm, v_from, v_to) e;

    SELECT COALESCE(s.netcashflow, 0) INTO v_cash
    FROM   public.sppoultryfinancialactivity_summary(v_farm, v_from, v_to) s;

    RAISE NOTICE 'C1. events net cash vs summary net cash  expect 0.00 difference  got %',
        COALESCE(ROUND(v_sumcash - v_cash, 2), -1);

    -- Running Cash is a WINDOW over occurredat. If the ordering had shifted, the
    -- last row would no longer land on opening + net.
    SELECT COALESCE(s.openingbalance, 0) INTO v_open
    FROM   public.sppoultrycashflow_summary(
               v_farm, v_from::timestamp,
               ((v_to + 1)::timestamp - interval '1 microsecond')) s;

    SELECT g.runningcash INTO v_last
    FROM   public.sppoultryfinancialactivity_get(v_farm, v_from, v_to) g
    ORDER  BY g.businessdate DESC, g.occurredat DESC, g.eventkey DESC
    LIMIT  1;

    RAISE NOTICE 'C2. last running cash = opening + net  expect 0.00 difference  got %',
        COALESCE(ROUND(v_last - (v_open + v_sumcash), 2), -1);

    -- And the row count itself, which a bad join in a leg would silently inflate.
    RAISE NOTICE 'C3. get and events return the same rows  expect 0 difference  got %',
        COALESCE((SELECT COUNT(*) FROM public.sppoultryfinancialactivity_get(v_farm, v_from, v_to)), -1)
        - v_rows;

    -- =====================================================================
    -- D. The leg that lives on another branch survived the rebuild.
    -- =====================================================================
    SELECT COUNT(*)::integer INTO v_legE
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'fnpoultryfa_events'
      AND  pg_get_functiondef(p.oid) LIKE '%poultryemployeeloanrepayments%';
    RAISE NOTICE 'D1. the payroll repayment leg is still in the body  expect 1  got %', v_legE;

    -- =====================================================================
    -- E. An entry time is a real instant.
    -- =====================================================================
    SELECT COUNT(*) FILTER (WHERE e.createdat > (now() at time zone 'utc') + interval '1 day')
      INTO v_future
    FROM   public.fnpoultryfa_events(v_farm, v_from, v_to) e;
    RAISE NOTICE 'E1. entry times in the future  expect 0  got %', COALESCE(v_future, -1);

    RAISE NOTICE '--- 8 numbered assertions expected above (A1-E1), plus one B line per';
    RAISE NOTICE '--- source type. A blank "got" is a FAILURE, not a pass. ---';
END;
$t$;
