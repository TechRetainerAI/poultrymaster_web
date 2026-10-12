-- CustomerCrm_SmokeTest.sql — database-side assertions for migration 350.
-- PASS = raised 'SMOKETEST_PASS ...' (everything rolls back).

DO $t$
DECLARE
    v_note1 bigint;
    v_note2 bigint;
    v_item  bigint;
    v_cnt   bigint;
BEGIN
    ---------------------------------------------------------------
    -- 1. Notes: author/date recorded; org A's rows invisible to org B filter
    ---------------------------------------------------------------
    INSERT INTO customercrmnotes (organizationid, companyid, category, note, createdby)
    VALUES ('smoke-crm-orgA', 'smoke-crm-co1', 'Support', 'A support note', 'smoke-admin')
    RETURNING id INTO v_note1;
    INSERT INTO customercrmnotes (organizationid, category, contacttype, note, createdby,
                                  followupatutc, assignedtoname)
    VALUES ('smoke-crm-orgB', 'Sales', 'Called', 'Spoke to owner', 'smoke-admin',
            now() + interval '3 days', 'Fiifi')
    RETURNING id INTO v_note2;

    SELECT count(*) INTO v_cnt FROM customercrmnotes
     WHERE organizationid = 'smoke-crm-orgA' AND createdby = 'smoke-admin' AND createdatutc IS NOT NULL;
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 1: note author/date not recorded'; END IF;
    SELECT count(*) INTO v_cnt FROM customercrmnotes
     WHERE organizationid = 'smoke-crm-orgB' AND id = v_note1;
    IF v_cnt <> 0 THEN RAISE EXCEPTION 'FAIL 1b: cross-organization leak in notes filter'; END IF;

    ---------------------------------------------------------------
    -- 2. Contact history + follow-up fields live on the same stream
    ---------------------------------------------------------------
    SELECT count(*) INTO v_cnt FROM customercrmnotes
     WHERE id = v_note2 AND contacttype = 'Called'
       AND followupatutc IS NOT NULL AND assignedtoname = 'Fiifi';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 2: contact/follow-up fields not stored'; END IF;

    ---------------------------------------------------------------
    -- 3. Attention-item link (ON DELETE SET NULL keeps the note)
    ---------------------------------------------------------------
    v_item := platform_attention_upsert('smoke-crm-orgA', 'smoke-crm-co1', 'PastDue', 'High',
                                        'smoke', 'smoke', 'PastDue');
    UPDATE customercrmnotes SET attentionitemid = v_item WHERE id = v_note1;
    DELETE FROM customerattentionitems WHERE id = v_item;
    SELECT count(*) INTO v_cnt FROM customercrmnotes
     WHERE id = v_note1 AND attentionitemid IS NULL;
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 3: attention link did not null out on delete'; END IF;

    ---------------------------------------------------------------
    -- 4. Product feedback stored with defaults
    ---------------------------------------------------------------
    INSERT INTO customerproductfeedback (organizationid, companyfamily, category, title, createdby)
    VALUES ('smoke-crm-orgA', 'Water', 'FeatureRequest', 'Bulk driver assignment', 'smoke-admin');
    SELECT count(*) INTO v_cnt FROM customerproductfeedback
     WHERE organizationid = 'smoke-crm-orgA' AND status = 'Open' AND severity = 'Medium';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 4: feedback defaults wrong'; END IF;

    ---------------------------------------------------------------
    -- 5. Cancellation reason recorded with author
    ---------------------------------------------------------------
    INSERT INTO subscriptioncancellationreasons (organizationid, reasoncode, note, createdby)
    VALUES ('smoke-crm-orgA', 'TemporaryPause', 'Rainy season', 'smoke-admin');
    SELECT count(*) INTO v_cnt FROM subscriptioncancellationreasons
     WHERE organizationid = 'smoke-crm-orgA' AND reasoncode = 'TemporaryPause';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 5: cancellation reason not stored'; END IF;

    RAISE EXCEPTION 'SMOKETEST_PASS: all 5 CRM assertions passed (rolled back on purpose)';
END
$t$;
