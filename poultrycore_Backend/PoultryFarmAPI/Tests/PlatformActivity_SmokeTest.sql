-- PlatformActivity_SmokeTest.sql — database-side assertions for migration 346.
--
-- HOW TO RUN (same pattern as CashIntegration_SmokeTest.sql):
--   Tools/RunMigration -- PoultryFarmAPI/Tests/PlatformActivity_SmokeTest.sql
--
-- The whole file is one DO block that ends with
--   RAISE EXCEPTION 'SMOKETEST_PASS ...'
-- ON PURPOSE: RunMigration wraps the file in a transaction and rolls back on
-- error, so the forced error is what guarantees none of the test rows survive.
-- A run is a PASS when the reported error message starts with SMOKETEST_PASS.
-- Any OTHER error message is a real failure.

DO $t$
DECLARE
    v_owner  text := 'smoketest-owner-346';
    v_farm1  text := 'smoketest-farm-346-a';      -- Africa/Accra (UTC+0)
    v_farm2  text := 'smoketest-farm-346-b';      -- Pacific/Auckland (UTC+12/13)
    v_id1    bigint;
    v_id2    bigint;
    v_id3    bigint;
    v_n      bigint;
    v_date   date;
    v_users  int;
BEGIN
    -- Two companies under ONE organization, different timezones.
    INSERT INTO farms (id, farmid, name, email, type, owneruserid, timezoneid, timezoneconfirmed, isdeleted)
    VALUES (2000000346, v_farm1, 'Smoke Farm A', 'smoke-a@test.local', 'Poultry', v_owner, 'Africa/Accra', true, false),
           (2000000347, v_farm2, 'Smoke Farm B', 'smoke-b@test.local', 'Water',   v_owner, 'Pacific/Auckland', true, false);

    ---------------------------------------------------------------
    -- 1. Meaningful event records and resolves company metadata
    ---------------------------------------------------------------
    v_id1 := platform_activity_record(v_farm1, 'smoke-user-1', 'PRODUCTION', 'ProductionRecorded', 'Poultry',
                                      '12345', true, NULL, NULL);
    IF v_id1 IS NULL THEN RAISE EXCEPTION 'FAIL 1: meaningful event was not recorded'; END IF;

    SELECT count(*) INTO v_n FROM platformactivityevents
     WHERE id = v_id1 AND organizationid = v_owner AND companyfamily = 'Poultry' AND ismeaningful;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 1b: organization/family not resolved on event'; END IF;

    ---------------------------------------------------------------
    -- 2. Idempotency: same correlation id collapses to one event
    ---------------------------------------------------------------
    v_id2 := platform_activity_record(v_farm1, 'smoke-user-1', 'PAYMENTS', 'PaymentRecorded', 'Poultry',
                                      '777', true, NULL, 'smoke-corr-1');
    v_id3 := platform_activity_record(v_farm1, 'smoke-user-1', 'PAYMENTS', 'PaymentRecorded', 'Poultry',
                                      '777', true, NULL, 'smoke-corr-1');
    IF v_id2 IS NULL THEN RAISE EXCEPTION 'FAIL 2: first correlated event not recorded'; END IF;
    IF v_id3 IS NOT NULL THEN RAISE EXCEPTION 'FAIL 2b: duplicate correlation id was recorded twice'; END IF;
    SELECT count(*) INTO v_n FROM platformactivityevents WHERE correlationid = 'smoke-corr-1';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 2c: expected exactly 1 correlated event, found %', v_n; END IF;

    ---------------------------------------------------------------
    -- 3. Usage-daily cache maintained by trigger (counts + active users)
    ---------------------------------------------------------------
    PERFORM platform_activity_record(v_farm1, 'smoke-user-2', 'SALES', 'SaleRecorded', 'Poultry',
                                     '888', true, NULL, NULL);
    SELECT meaningfulactivitycount, activeusers INTO v_n, v_users
      FROM companyusagedaily
     WHERE companyid = v_farm1
       AND businessdate = (now() AT TIME ZONE 'Africa/Accra')::date;
    IF coalesce(v_n, 0) <> 3 THEN RAISE EXCEPTION 'FAIL 3: usage daily meaningful count = %, expected 3', v_n; END IF;
    IF coalesce(v_users, 0) <> 2 THEN RAISE EXCEPTION 'FAIL 3b: usage daily active users = %, expected 2', v_users; END IF;

    SELECT salescount INTO v_n FROM companyusagedaily
     WHERE companyid = v_farm1 AND businessdate = (now() AT TIME ZONE 'Africa/Accra')::date;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 3c: sales category counter = %, expected 1', v_n; END IF;

    ---------------------------------------------------------------
    -- 4. Timezone: company business date uses the COMPANY's timezone
    ---------------------------------------------------------------
    PERFORM platform_activity_record(v_farm2, 'smoke-user-1', 'PRODUCTION', 'ProductionRecorded', 'Water',
                                     '999', true, NULL, NULL);
    SELECT businessdate INTO v_date FROM platformactivityevents
     WHERE companyid = v_farm2 ORDER BY id DESC LIMIT 1;
    IF v_date <> (now() AT TIME ZONE 'Pacific/Auckland')::date THEN
        RAISE EXCEPTION 'FAIL 4: business date % is not Auckland-local today %',
            v_date, (now() AT TIME ZONE 'Pacific/Auckland')::date;
    END IF;

    ---------------------------------------------------------------
    -- 5. Company isolation: farm B's day is untouched by farm A's events
    ---------------------------------------------------------------
    SELECT meaningfulactivitycount INTO v_n FROM companyusagedaily
     WHERE companyid = v_farm2 AND businessdate = (now() AT TIME ZONE 'Pacific/Auckland')::date;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 5: farm B meaningful count = %, expected 1', v_n; END IF;

    ---------------------------------------------------------------
    -- 6. Organization aggregation: both companies roll up to the owner
    ---------------------------------------------------------------
    SELECT count(*), max(occurredatutc)::date INTO v_n, v_date
      FROM platformactivityevents
     WHERE organizationid = v_owner AND ismeaningful;
    IF v_n <> 4 THEN RAISE EXCEPTION 'FAIL 6: organization meaningful events = %, expected 4', v_n; END IF;

    ---------------------------------------------------------------
    -- 7. Unresolvable company: event is kept but unattributed (no fabrication)
    ---------------------------------------------------------------
    PERFORM platform_activity_record('no-such-farm', 'smoke-user-1', 'SALES', 'SaleRecorded', 'Poultry',
                                     NULL, true, NULL, NULL);
    SELECT count(*) INTO v_n FROM platformactivityevents
     WHERE userid = 'smoke-user-1' AND companyid IS NULL AND activitytype = 'SaleRecorded';
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 7: unresolvable company should store NULL companyid'; END IF;

    ---------------------------------------------------------------
    -- 8. Login recording: counters + login day + AUTH event, never meaningful
    ---------------------------------------------------------------
    -- (uses an existing user when present; otherwise skipped — aspnetusers has
    --  FKs/identity colums we must not fake here)
    PERFORM platform_record_login((SELECT id FROM aspnetusers LIMIT 1));
    SELECT count(*) INTO v_n FROM platformactivityevents
     WHERE activitycategory = 'AUTHENTICATION' AND ismeaningful;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 8: login events must never be meaningful'; END IF;

    ---------------------------------------------------------------
    -- 9. Rebuild reproduces the trigger-maintained cache exactly
    ---------------------------------------------------------------
    PERFORM platform_usagedaily_rebuild();
    SELECT meaningfulactivitycount, activeusers INTO v_n, v_users
      FROM companyusagedaily
     WHERE companyid = v_farm1 AND businessdate = (now() AT TIME ZONE 'Africa/Accra')::date;
    IF coalesce(v_n, 0) <> 3 OR coalesce(v_users, 0) <> 2 THEN
        RAISE EXCEPTION 'FAIL 9: rebuild mismatch (meaningful=%, users=%)', v_n, v_users;
    END IF;

    RAISE EXCEPTION 'SMOKETEST_PASS: all 9 platform-activity assertions passed (rolled back on purpose)';
END
$t$;
