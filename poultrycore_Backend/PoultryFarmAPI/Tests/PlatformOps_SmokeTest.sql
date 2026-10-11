-- PlatformOps_SmokeTest.sql — database-side assertions for migration 352.
-- PASS = raised 'SMOKETEST_PASS ...' (everything rolls back).

DO $t$
DECLARE
    v_id   bigint;
    v_id2  bigint;
    v_cnt  bigint;
    v_flag int;
BEGIN
    ---------------------------------------------------------------
    -- 1. Feature flag + scoped rules + audit rows
    ---------------------------------------------------------------
    INSERT INTO platformfeatureflags (flagkey, name, enabled, defaulton, createdby)
    VALUES ('smoke-flag', 'Smoke Flag', true, false, 'smoke') RETURNING id INTO v_flag;
    INSERT INTO platformfeatureflagrules (flagid, scopetype, scopevalue, enabled, createdby)
    VALUES (v_flag, 'Organization', 'smoke-org', true, 'smoke'),
           (v_flag, 'Company', 'smoke-farm', false, 'smoke');
    -- scope uniqueness: same scope twice must conflict (updated, not duplicated)
    INSERT INTO platformfeatureflagrules (flagid, scopetype, scopevalue, enabled, createdby)
    VALUES (v_flag, 'Organization', 'smoke-org', false, 'smoke2')
    ON CONFLICT (flagid, scopetype, scopevalue) DO UPDATE SET enabled = excluded.enabled;
    SELECT count(*) INTO v_cnt FROM platformfeatureflagrules
     WHERE flagid = v_flag AND scopetype = 'Organization';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 1: duplicate scope rule (%)', v_cnt; END IF;
    SELECT count(*) INTO v_cnt FROM platformfeatureflagrules
     WHERE flagid = v_flag AND scopetype = 'Organization' AND enabled = false;
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 1b: rule upsert did not update'; END IF;

    INSERT INTO platformfeatureflagaudit (flagkey, action, scopetype, scopevalue, newvalue, changedby, reason)
    VALUES ('smoke-flag', 'RuleSet', 'Organization', 'smoke-org', 'false', 'smoke', 'pilot rollback');
    SELECT count(*) INTO v_cnt FROM platformfeatureflagaudit WHERE flagkey = 'smoke-flag' AND reason = 'pilot rollback';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 1c: flag audit row missing'; END IF;

    ---------------------------------------------------------------
    -- 2. Security event dedupe: same condition same day bumps occurrences
    ---------------------------------------------------------------
    v_id := platform_security_event('RepeatedFailedLogins', 'Warning', NULL, NULL, 'smoke-user',
                                    'Repeated failed logins', '3 failures');
    v_id2 := platform_security_event('RepeatedFailedLogins', 'Critical', NULL, NULL, 'smoke-user',
                                     'Repeated failed logins', '6 failures');
    IF v_id2 <> v_id THEN RAISE EXCEPTION 'FAIL 2: security event duplicated (% vs %)', v_id2, v_id; END IF;
    SELECT count(*) INTO v_cnt FROM platformsecurityevents
     WHERE id = v_id AND occurrences = 2 AND severity = 'Critical' AND detail = '6 failures';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 2b: dedupe did not bump/refresh'; END IF;
    -- different subject = different event
    v_id2 := platform_security_event('RepeatedFailedLogins', 'Warning', NULL, NULL, 'other-user',
                                     'Repeated failed logins', '3 failures');
    IF v_id2 = v_id THEN RAISE EXCEPTION 'FAIL 2c: distinct subjects collapsed'; END IF;

    ---------------------------------------------------------------
    -- 3. Release registry is idempotent
    ---------------------------------------------------------------
    INSERT INTO platformreleases (service, version) VALUES ('farm-api', 'smoke-rev-1');
    INSERT INTO platformreleases (service, version) VALUES ('farm-api', 'smoke-rev-1')
    ON CONFLICT (service, version) DO NOTHING;
    SELECT count(*) INTO v_cnt FROM platformreleases WHERE service = 'farm-api' AND version = 'smoke-rev-1';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 3: release duplicated'; END IF;

    ---------------------------------------------------------------
    -- 4. Brief upsert: one row per type per day, regeneration replaces it
    ---------------------------------------------------------------
    INSERT INTO platformbriefs (brieftype, briefdate, generatedby, metricsjson)
    VALUES ('Daily', current_date, 'smoke', '{"v":1}')
    ON CONFLICT (brieftype, briefdate) DO UPDATE SET metricsjson = excluded.metricsjson;
    INSERT INTO platformbriefs (brieftype, briefdate, generatedby, metricsjson)
    VALUES ('Daily', current_date, 'smoke', '{"v":2}')
    ON CONFLICT (brieftype, briefdate) DO UPDATE SET metricsjson = excluded.metricsjson;
    SELECT count(*) INTO v_cnt FROM platformbriefs
     WHERE brieftype = 'Daily' AND briefdate = current_date AND metricsjson = '{"v":2}';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 4: brief upsert broken'; END IF;

    ---------------------------------------------------------------
    -- 5. Retention function runs and reports
    ---------------------------------------------------------------
    IF platform_ops_retention() IS NULL THEN RAISE EXCEPTION 'FAIL 5: retention returned NULL'; END IF;

    RAISE EXCEPTION 'SMOKETEST_PASS: all 5 platform-ops assertions passed (rolled back on purpose)';
END
$t$;
