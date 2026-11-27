-- 506_Enock_PoultryBatchDeleteFlocks. Self-contained: BEGIN ... ROLLBACK.
-- Builds batches in the poultry company with the most batches and deletes them
-- every way the screen allows.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.must_fail(p_sql text, p_like text, p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM ILIKE '%' || p_like || '%' THEN RETURN; END IF;
        RAISE EXCEPTION 'FAIL %: refused with the wrong message: %', p_label, SQLERRM;
    END;
    RAISE EXCEPTION 'FAIL %: was accepted', p_label;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.mk_flock(p_farm text, p_batch integer, p_name text) RETURNS integer LANGUAGE sql AS $$
    INSERT INTO flock (userid, name, startdate, breed, quantity, farmid, batchid, flocktype, active)
    VALUES ('506-check', p_name, now() AT TIME ZONE 'utc', 'Test', 100, p_farm, p_batch, 'Layer', true)
    RETURNING flockid;
$$;

DO $$
DECLARE
    v_farm text; v_sup integer; v_acct integer; v_b integer; v_f1 integer; v_f2 integer; v_pre jsonb;
    v_cash0 numeric;
BEGIN
    SELECT b.farmid INTO v_farm FROM mainflockbatch b JOIN supplier s ON s.farmid::text = b.farmid
    WHERE b.farmid ~ '^[0-9a-f-]{36}$' GROUP BY b.farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT s.supplierid INTO v_sup FROM supplier s WHERE s.farmid::text = v_farm ORDER BY 1 LIMIT 1;
    SELECT a.poultrycashaccountid INTO v_acct FROM poultrycashaccounts a WHERE a.farmid = v_farm ORDER BY 1 LIMIT 1;
    IF v_sup IS NULL OR v_acct IS NULL THEN RAISE EXCEPTION 'FAIL 506.0: test farm lacks a supplier or cash account'; END IF;
    UPDATE poultrycashaccounts SET currentbalance = currentbalance + 100000 WHERE poultrycashaccountid = v_acct;

    -- ---------------------------------------------------------------- 1
    -- paid batch, two empty flocks: refused without confirmation, then deleted
    -- with them; its expense and cash come off
    SELECT currentbalance INTO v_cash0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_b := spmainflockbatch_insert('506-check', v_farm, '506-A', '506 batch A', 'Test', 200, (now() AT TIME ZONE 'utc')::timestamp,
                                   'active', 5, 1000, NULL, v_sup, 1000, NULL, NULL, NULL, NULL, false, v_acct);
    v_f1 := pg_temp.mk_flock(v_farm, v_b, '506 flock 1');
    v_f2 := pg_temp.mk_flock(v_farm, v_b, '506 flock 2');
    v_pre := fnpoultrybatch_deletepreview(v_farm, v_b);
    IF jsonb_array_length(v_pre->'blockers') <> 0 OR (v_pre->>'flocksToDelete')::int <> 2 OR (v_pre->>'expenseRemoved')::numeric <> 1000 THEN
        RAISE EXCEPTION 'FAIL 506.1: preview %', v_pre; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT spmainflockbatch_delete(%s, '506-check', %L)$q$, v_b, v_farm), 'still has 2 flock', '506.1 unconfirmed');
    PERFORM spmainflockbatch_delete(v_b, '506-check', v_farm, true);
    IF EXISTS (SELECT 1 FROM mainflockbatch WHERE batchid = v_b) THEN RAISE EXCEPTION 'FAIL 506.1: batch still there'; END IF;
    IF EXISTS (SELECT 1 FROM flock WHERE flockid IN (v_f1, v_f2) AND NOT isdeleted) THEN RAISE EXCEPTION 'FAIL 506.1: flocks not deleted'; END IF;
    IF EXISTS (SELECT 1 FROM expense WHERE sourcetype = 'MainFlockBatch' AND sourceid = v_b) THEN RAISE EXCEPTION 'FAIL 506.1: batch expense left'; END IF;
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_cash0 THEN
        RAISE EXCEPTION 'FAIL 506.1: cash not back (% vs %)', (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct), v_cash0; END IF;
    RAISE NOTICE 'ok 506.1 unconfirmed refused; confirmed deletes the batch, its 2 flocks, its expense, and the cash comes back';

    -- ---------------------------------------------------------------- 2
    -- a flock with records blocks it: make it inactive instead
    v_b := spmainflockbatch_insert('506-check', v_farm, '506-B', '506 batch B', 'Test', 200, (now() AT TIME ZONE 'utc')::timestamp,
                                   'active', 5, 1000, NULL, v_sup, 1000, NULL, NULL, NULL, NULL, false, v_acct);
    v_f1 := pg_temp.mk_flock(v_farm, v_b, '506 flock busy');
    v_f2 := pg_temp.mk_flock(v_farm, v_b, '506 flock empty');
    INSERT INTO expense (expensedate, category, description, amount, paymentmethod, flockid, createddate, userid, farmid)
    VALUES (now() AT TIME ZONE 'utc', 'Feed', '506 check', 10, 'Cash', v_f1, now() AT TIME ZONE 'utc', '506-check', v_farm::uuid);
    v_pre := fnpoultrybatch_deletepreview(v_farm, v_b);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_pre->'blockers') x WHERE x->>'code' = 'FlockHasRecords:' || v_f1) THEN
        RAISE EXCEPTION 'FAIL 506.2: busy flock not blocking: %', v_pre->'blockers'; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT spmainflockbatch_delete(%s, '506-check', %L, true)$q$, v_b, v_farm), 'Make it inactive', '506.2 busy flock');
    IF EXISTS (SELECT 1 FROM flock WHERE flockid = v_f2 AND isdeleted) THEN RAISE EXCEPTION 'FAIL 506.2: the empty flock was deleted anyway'; END IF;
    RAISE NOTICE 'ok 506.2 a flock with records blocks the whole delete (make it inactive); nothing is deleted';

    -- ---------------------------------------------------------------- 3
    -- a Supplier Payment on the batch blocks it
    v_b := spmainflockbatch_insert('506-check', v_farm, '506-C', '506 batch C', 'Test', 200, (now() AT TIME ZONE 'utc')::timestamp,
                                   'active', 5, 1000, NULL, v_sup, 400, NULL, NULL, NULL, NULL, false, v_acct);
    PERFORM spmainflockbatch_paybalance(v_b, v_farm, 100, 'Cash', NULL, '506-check');
    v_pre := fnpoultrybatch_deletepreview(v_farm, v_b);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_pre->'blockers') x WHERE x->>'code' = 'SupplierPayments') THEN
        RAISE EXCEPTION 'FAIL 506.3: supplier payment not blocking: %', v_pre->'blockers'; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT spmainflockbatch_delete(%s, '506-check', %L, true)$q$, v_b, v_farm), 'Reverse it on Supplier Payments', '506.3 paid batch');
    RAISE NOTICE 'ok 506.3 a batch with a Supplier Payment applied cannot be deleted until it is reversed';

    -- ---------------------------------------------------------------- 4
    -- a batch with no flocks deletes as before (3-argument call)
    v_b := spmainflockbatch_insert('506-check', v_farm, '506-D', '506 batch D', 'Test', 50, (now() AT TIME ZONE 'utc')::timestamp,
                                   'active', 5, 250, NULL, v_sup, 250, NULL, NULL, NULL, NULL, false, v_acct);
    PERFORM spmainflockbatch_delete(v_b, '506-check', v_farm);
    IF EXISTS (SELECT 1 FROM mainflockbatch WHERE batchid = v_b) THEN RAISE EXCEPTION 'FAIL 506.4: empty batch not deleted'; END IF;
    RAISE NOTICE 'ok 506.4 a batch with no flocks deletes as before';

    RAISE NOTICE 'poultry 506: all checks passed';
END $$;

ROLLBACK;
