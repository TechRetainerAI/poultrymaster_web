-- 507_Enock_PoultryBatchReversal. Self-contained: BEGIN ... ROLLBACK.
-- Builds batches in the poultry company with the most batches and reverses them
-- every way the dialog allows.
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
    VALUES ('507-check', p_name, now() AT TIME ZONE 'utc', 'Test', 100, p_farm, p_batch, 'Layer', true)
    RETURNING flockid;
$$;

CREATE OR REPLACE FUNCTION pg_temp.mk_batch(p_farm text, p_code text, p_sup integer, p_acct integer, p_total numeric, p_paid numeric)
RETURNS integer LANGUAGE sql AS $$
    SELECT spmainflockbatch_insert('507-check', p_farm, p_code, '507 ' || p_code, 'Test', 200, (now() AT TIME ZONE 'utc')::timestamp,
                                   'active', p_total / 200, p_total, NULL, p_sup, p_paid, NULL, NULL, NULL, NULL, false, p_acct);
$$;

DO $$
DECLARE
    v_farm text; v_sup integer; v_acct integer; v_b integer; v_f1 integer; v_f2 integer; v_pre jsonb; v_rev integer; v_rev2 integer;
    v_cash0 numeric; v_n integer; v_x numeric; v_pay integer;
BEGIN
    SELECT b.farmid INTO v_farm FROM mainflockbatch b JOIN supplier s ON s.farmid::text = b.farmid
    WHERE b.farmid ~ '^[0-9a-f-]{36}$' GROUP BY b.farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT s.supplierid INTO v_sup FROM supplier s WHERE s.farmid::text = v_farm ORDER BY 1 LIMIT 1;
    SELECT a.poultrycashaccountid INTO v_acct FROM poultrycashaccounts a WHERE a.farmid = v_farm ORDER BY 1 LIMIT 1;
    UPDATE poultrycashaccounts SET currentbalance = currentbalance + 100000 WHERE poultrycashaccountid = v_acct;

    -- ---------------------------------------------------------------- 1
    -- paid batch, two empty flocks, refunded
    SELECT currentbalance INTO v_cash0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_b := pg_temp.mk_batch(v_farm, '507-A', v_sup, v_acct, 1000, 1000);
    v_f1 := pg_temp.mk_flock(v_farm, v_b, '507 flock 1');
    v_f2 := pg_temp.mk_flock(v_farm, v_b, '507 flock 2');
    v_pre := sppoultrybatch_reversalpreview(v_farm, v_b);
    IF jsonb_array_length(v_pre->'blockers') <> 0 OR jsonb_array_length(v_pre->'flocks') <> 2
       OR jsonb_array_length(v_pre->'payments') <> 1 OR (v_pre->'payments'->0->>'allocated')::numeric <> 1000
       OR (v_pre->'payments'->0->'allowed') <> '["KeepAsCredit","Refund"]'::jsonb THEN
        RAISE EXCEPTION 'FAIL 507.1: preview %', v_pre; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT sppoultrybatch_reverse(%L, %s, 'Wrong quantity', NULL)$q$, v_farm, v_b), 'Confirm that they are deleted', '507.1 unconfirmed');
    v_rev := sppoultrybatch_reverse(v_farm, v_b, 'Wrong quantity', NULL, '{}'::jsonb, true, v_pre->>'fingerprint', '507-idem', '507-check');
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_cash0 THEN RAISE EXCEPTION 'FAIL 507.1: cash not back'; END IF;
    IF NOT EXISTS (SELECT 1 FROM poultrycashtransactions WHERE farmid = v_farm AND sourcetype = 'FlockBatchPurchase' AND sourceid = v_b AND amount = -1000) THEN
        RAISE EXCEPTION 'FAIL 507.1: the original cash-out was not kept'; END IF;
    IF NOT EXISTS (SELECT 1 FROM poultrycashtransactions WHERE farmid = v_farm AND sourcetype = 'FlockBatchReversal' AND sourceid = v_b AND amount = 1000) THEN
        RAISE EXCEPTION 'FAIL 507.1: no refund cash-in'; END IF;
    IF EXISTS (SELECT 1 FROM mainflockbatch WHERE batchid = v_b) OR EXISTS (SELECT 1 FROM expense WHERE sourcetype = 'MainFlockBatch' AND sourceid = v_b) THEN
        RAISE EXCEPTION 'FAIL 507.1: batch or its expense still there'; END IF;
    IF EXISTS (SELECT 1 FROM flock WHERE flockid IN (v_f1, v_f2) AND NOT isdeleted) THEN RAISE EXCEPTION 'FAIL 507.1: flocks not deleted'; END IF;
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(sppoultrybatchreversal_list(v_farm)) x
                   WHERE (x->>'batchReversalId')::int = v_rev AND jsonb_array_length(x->'flocksRemoved') = 2 AND (x->>'refunded')::numeric = 1000) THEN
        RAISE EXCEPTION 'FAIL 507.1: not in the reversed list'; END IF;
    SELECT COALESCE(SUM(r.amount), 0), count(*) INTO v_x, v_n FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r
    WHERE r.rowsource IN ('BatchPurchase', 'BatchRefund') AND r.sourceid = v_b;
    IF v_n <> 2 OR v_x <> 0 THEN RAISE EXCEPTION 'FAIL 507.1: Cash Flow shows % rows netting % (expected purchase + refund = 0)', v_n, v_x; END IF;
    RAISE NOTICE 'ok 507.1 refunded: cash back, original cash-out kept + refund cash-in, batch/expense/flocks gone, listed, Cash Flow nets 0';

    -- ---------------------------------------------------------------- 2
    v_rev2 := sppoultrybatch_reverse(v_farm, v_b, 'Wrong quantity', NULL, '{}'::jsonb, true, NULL, '507-idem', '507-check');
    IF v_rev2 <> v_rev THEN RAISE EXCEPTION 'FAIL 507.2: a repeated click made another reversal'; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT sppoultrybatch_reverse(%L, %s, 'Wrong quantity', NULL)$q$, v_farm, v_b), 'already been reversed', '507.2 twice');
    RAISE NOTICE 'ok 507.2 a repeated click returns the same reversal; reversing twice is refused';

    -- ---------------------------------------------------------------- 3
    -- paid, supplier keeps the money: a supplier credit, the cash-out stays on Cash Flow
    SELECT currentbalance INTO v_cash0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_b := pg_temp.mk_batch(v_farm, '507-B', v_sup, v_acct, 500, 500);
    v_rev := sppoultrybatch_reverse(v_farm, v_b, 'Duplicate entry', NULL, jsonb_build_object('entry:' || v_acct, 'KeepAsCredit'), false, NULL, NULL, '507-check');
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_cash0 - 500 THEN RAISE EXCEPTION 'FAIL 507.3: cash moved'; END IF;
    SELECT paymentid INTO v_pay FROM poultrybatchreversalpayments WHERE batchreversalid = v_rev;
    IF (SELECT sourcetype FROM poultrysupplierpayments WHERE poultrysupplierpaymentid = v_pay) <> 'SupplierManualCredit'
       OR fnpoultrysupplierpayment_unapplied(v_farm, v_pay) <> 500 THEN RAISE EXCEPTION 'FAIL 507.3: no 500 supplier credit'; END IF;
    IF (SELECT COALESCE(SUM(r.amount), 0) FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r WHERE r.rowsource IN ('BatchPurchase', 'BatchRefund') AND r.sourceid = v_b) <> -500 THEN
        RAISE EXCEPTION 'FAIL 507.3: Cash Flow should still show the 500 paid'; END IF;
    IF EXISTS (SELECT 1 FROM sppoultrycashflow_rows(v_farm, NULL, NULL) r WHERE r.sourcerowid = v_pay AND r.rowsource = 'SupplierAdvance') THEN
        RAISE EXCEPTION 'FAIL 507.3: the credit shows as cash'; END IF;
    RAISE NOTICE 'ok 507.3 kept as credit: supplier credit 500, no cash moves, the cash-out stays on Cash Flow';

    -- ---------------------------------------------------------------- 4
    -- part paid + "Pay balance" payment kept as credit
    v_b := pg_temp.mk_batch(v_farm, '507-C', v_sup, v_acct, 1000, 400);
    PERFORM spmainflockbatch_paybalance(v_b, v_farm, 100, 'Cash', NULL, '507-check');
    v_pre := sppoultrybatch_reversalpreview(v_farm, v_b);
    IF jsonb_array_length(v_pre->'blockers') <> 0 OR jsonb_array_length(v_pre->'payments') <> 2 THEN RAISE EXCEPTION 'FAIL 507.4: preview %', v_pre; END IF;
    SELECT (x->>'paymentId')::int INTO v_pay FROM jsonb_array_elements(v_pre->'payments') x WHERE x->>'source' = 'SupplierPayment';
    PERFORM sppoultrybatch_reverse(v_farm, v_b, 'Wrong amount', NULL, '{}'::jsonb, false, NULL, NULL, '507-check');
    IF fnpoultrysupplierpayment_unapplied(v_farm, v_pay) <> 100 THEN RAISE EXCEPTION 'FAIL 507.4: the pay-balance payment is not credit'; END IF;
    RAISE NOTICE 'ok 507.4 a Pay balance payment is released as supplier credit';

    -- ---------------------------------------------------------------- 5
    -- a flock with records blocks it
    v_b := pg_temp.mk_batch(v_farm, '507-D', v_sup, v_acct, 100, 100);
    v_f1 := pg_temp.mk_flock(v_farm, v_b, '507 busy');
    INSERT INTO expense (expensedate, category, description, amount, paymentmethod, flockid, createddate, userid, farmid)
    VALUES (now() AT TIME ZONE 'utc', 'Feed', '507 check', 10, 'Cash', v_f1, now() AT TIME ZONE 'utc', '507-check', v_farm::uuid);
    PERFORM pg_temp.must_fail(format($q$SELECT sppoultrybatch_reverse(%L, %s, 'Wrong amount', NULL, '{}'::jsonb, true)$q$, v_farm, v_b), 'Make it inactive', '507.5 busy flock');
    PERFORM pg_temp.must_fail(format($q$SELECT sppoultrybatch_reverse(%L, %s, 'Other', '')$q$, v_farm, v_b), 'what happened', '507.5 Other without note');
    RAISE NOTICE 'ok 507.5 a flock with records blocks the reversal; Other needs a note';

    RAISE NOTICE 'poultry 507: all checks passed';
END $$;

ROLLBACK;
