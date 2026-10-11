-- CustomerHealth_SmokeTest.sql — database-side assertions for migration 348.
-- Same convention as PlatformActivity_SmokeTest.sql: PASS = the forced error
-- 'SMOKETEST_PASS ...' (everything rolls back); any other error = real failure.

DO $t$
DECLARE
    v_id1  bigint;
    v_id2  bigint;
    v_id3  bigint;
    v_n    int;
    v_cnt  bigint;
BEGIN
    ---------------------------------------------------------------
    -- 1. Upsert opens one item
    ---------------------------------------------------------------
    v_id1 := platform_attention_upsert('smoke-org', 'smoke-co', 'PaymentFailed', 'High',
                                       'Smoke: payment failed', 'A payment failed.', 'PaymentFailed');
    IF v_id1 IS NULL THEN RAISE EXCEPTION 'FAIL 1: upsert returned NULL'; END IF;

    ---------------------------------------------------------------
    -- 2. Duplicate suppression: re-detection updates, never duplicates
    ---------------------------------------------------------------
    v_id2 := platform_attention_upsert('smoke-org', 'smoke-co', 'PaymentFailed', 'High',
                                       'Smoke: payment failed again', 'Second detection.', 'PaymentFailed');
    IF v_id2 <> v_id1 THEN RAISE EXCEPTION 'FAIL 2: duplicate live item created (% vs %)', v_id2, v_id1; END IF;
    SELECT count(*) INTO v_cnt FROM customerattentionitems
     WHERE organizationid = 'smoke-org' AND attentiontype = 'PaymentFailed';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 2b: expected 1 item, found %', v_cnt; END IF;
    SELECT count(*) INTO v_cnt FROM customerattentionitems
     WHERE id = v_id1 AND reason = 'Second detection.' AND lastdetectedatutc >= detectedatutc;
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 2c: re-detection did not refresh the item'; END IF;

    ---------------------------------------------------------------
    -- 3. Dedupe respects scope: org-level and company-level are distinct
    ---------------------------------------------------------------
    v_id3 := platform_attention_upsert('smoke-org', NULL, 'PaymentFailed', 'High',
                                       'Smoke: org-level', 'Org-level item.', 'PaymentFailed');
    IF v_id3 = v_id1 THEN RAISE EXCEPTION 'FAIL 3: org-level and company-level collapsed together'; END IF;

    ---------------------------------------------------------------
    -- 4. Auto-resolve closes the live item and preserves it as history
    ---------------------------------------------------------------
    v_n := platform_attention_autoresolve('smoke-org', 'smoke-co', ARRAY['PaymentFailed'],
                                          'Auto Resolved — Customer Reactivated');
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 4: expected 1 auto-resolved, got %', v_n; END IF;
    SELECT count(*) INTO v_cnt FROM customerattentionitems
     WHERE id = v_id1 AND status = 'Resolved' AND resolvedby = 'system'
       AND resolutionnote = 'Auto Resolved — Customer Reactivated';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 4b: auto-resolve did not mark the item correctly'; END IF;

    ---------------------------------------------------------------
    -- 5. Same condition can re-open as a NEW item after resolution
    ---------------------------------------------------------------
    v_id2 := platform_attention_upsert('smoke-org', 'smoke-co', 'PaymentFailed', 'High',
                                       'Smoke: failed again later', 'Third detection.', 'PaymentFailed');
    IF v_id2 = v_id1 THEN RAISE EXCEPTION 'FAIL 5: resolved item was reused instead of reopening fresh'; END IF;

    ---------------------------------------------------------------
    -- 6. Auto-resolve of a type with no live item is a harmless no-op
    ---------------------------------------------------------------
    v_n := platform_attention_autoresolve('smoke-org', 'smoke-co', ARRAY['RepeatedErrors'], 'noop');
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 6: no-op auto-resolve touched % rows', v_n; END IF;

    ---------------------------------------------------------------
    -- 7. Health history: one row per day, updated on change only
    ---------------------------------------------------------------
    PERFORM platform_health_record('Company', 'smoke-co', 'Healthy', 'all good');
    PERFORM platform_health_record('Company', 'smoke-co', 'Healthy', 'still good');  -- same level: ignored
    SELECT count(*) INTO v_cnt FROM customerhealthhistory WHERE scope = 'Company' AND subjectid = 'smoke-co';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 7: expected 1 history row, found %', v_cnt; END IF;
    SELECT count(*) INTO v_cnt FROM customerhealthhistory
     WHERE scope = 'Company' AND subjectid = 'smoke-co' AND reasons = 'all good';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 7b: same-level rewrite should keep first reasons'; END IF;
    PERFORM platform_health_record('Company', 'smoke-co', 'At Risk', 'went quiet');
    SELECT count(*) INTO v_cnt FROM customerhealthhistory
     WHERE scope = 'Company' AND subjectid = 'smoke-co' AND health = 'At Risk';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 7c: level change was not recorded'; END IF;

    ---------------------------------------------------------------
    -- 8. Notes cascade with their item
    ---------------------------------------------------------------
    INSERT INTO customerattentionnotes (itemid, note, createdby) VALUES (v_id2, 'test note', 'smoke');
    SELECT count(*) INTO v_cnt FROM customerattentionnotes WHERE itemid = v_id2;
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 8: note insert failed'; END IF;

    RAISE EXCEPTION 'SMOKETEST_PASS: all 8 customer-health assertions passed (rolled back on purpose)';
END
$t$;
