-- =============================================================================
-- Checks for 479 (Poultry purchase reversal on the sale model). SELF-ROLLING-
-- BACK, fixtures in a real Poultry company. Prints
-- 'poultry 479: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.p479_refused(p_sql text) RETURNS text LANGUAGE plpgsql AS $r$
BEGIN
    EXECUTE p_sql;
    RETURN NULL;
EXCEPTION WHEN OTHERS THEN
    RETURN SQLERRM;
END $r$;

DO $t$
DECLARE
    v_farm text; v_acct integer; v_user text; v_sup integer; v_item integer;
    v_p1 integer; v_p2 integer; v_p3 integer; v_p4 integer; v_pay integer;
    v_st jsonb; v_r integer; v_r2 integer; v_err text; v_bal numeric; v_cred numeric; v_n integer;
    v_from timestamp := (CURRENT_DATE - 2)::timestamp;
    v_to   timestamp := (CURRENT_DATE + 2)::timestamp;
BEGIN
    SELECT a.farmid, a.poultrycashaccountid INTO v_farm, v_acct
    FROM   poultrycashaccounts a
    JOIN   farms f ON (f.id::text = a.farmid OR f.farmid::text = a.farmid) AND f.type = 'Poultry'
    WHERE  a.isactive AND a.farmid ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    ORDER  BY a.poultrycashaccountid LIMIT 1;
    IF v_farm IS NULL THEN RAISE NOTICE 'poultry 479: all checks passed (no poultry company)'; RETURN; END IF;
    UPDATE poultrycashaccounts SET allownegativebalance = TRUE WHERE poultrycashaccountid = v_acct;
    SELECT f.owneruserid INTO v_user FROM farms f WHERE f.id::text = v_farm OR f.farmid::text = v_farm LIMIT 1;
    v_user := COALESCE(v_user, 'check479');
    INSERT INTO supplier (farmid, userid, name) VALUES (v_farm, v_user, '__p479_supplier') RETURNING supplierid INTO v_sup;
    INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive)
    VALUES (v_farm, '__p479_maize', 'Feed', 'kg', 0, TRUE) RETURNING poultryrawmaterialitemid INTO v_item;

    -- 1. paid in full when recorded, refunded: payment reversed, cash back, row kept
    SELECT currentbalance INTO v_bal FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_p1 := sppoultryrawmaterialpurchase_record(v_farm, v_item, '__p479_supplier', v_sup, now()::timestamp, 10, 10, 100,
              NULL, 1, 'Cash', 100, NULL, NULL, v_user, v_acct);
    v_st := sppoultrypurchase_reversalpreview(v_farm, v_p1);
    IF jsonb_array_length(v_st->'blockers') <> 0 OR jsonb_array_length(v_st->'payments') <> 1
       OR NOT (v_st->'payments'->0->'allowed') ? 'Refund' THEN
        RAISE EXCEPTION 'FAIL 1a: preview %', v_st;
    END IF;
    v_r := sppoultrypurchase_reverse(v_farm, v_p1, 'Duplicate entry', NULL,
              jsonb_build_object(v_st->'payments'->0->>'key', 'Refund'), v_st->>'fingerprint', '__p479-k1', v_user);
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal THEN
        RAISE EXCEPTION 'FAIL 1b: cash not back (% vs %)', (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct), v_bal;
    END IF;
    IF (SELECT currentquantity FROM poultryrawmaterialitems WHERE poultryrawmaterialitemid = v_item) <> 0
       OR (SELECT purchasereversalid FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_p1) IS DISTINCT FROM v_r
       OR (SELECT reversalnumber FROM poultrypurchasereversals WHERE purchasereversalid = v_r) NOT LIKE 'PPR-%' THEN
        RAISE EXCEPTION 'FAIL 1c: stock / stamp';
    END IF;
    IF EXISTS (SELECT 1 FROM expense e WHERE e.sourcetype = 'PoultryRawMaterialPurchase' AND e.sourceid = v_p1) THEN
        RAISE EXCEPTION 'FAIL 1d: expense still counted';
    END IF;
    v_r2 := sppoultrypurchase_reverse(v_farm, v_p1, 'Duplicate entry', NULL, '{}'::jsonb, NULL, '__p479-k1', v_user);
    IF v_r2 <> v_r THEN RAISE EXCEPTION 'FAIL 1e: idempotency'; END IF;
    RAISE NOTICE 'ok 1 refunded: payment reversed, cash back, stock out, expense gone, idempotent';

    -- 2. kept as supplier credit: no cash moves, the payment's part becomes credit
    SELECT currentbalance INTO v_bal FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_p2 := sppoultryrawmaterialpurchase_record(v_farm, v_item, '__p479_supplier', v_sup, now()::timestamp, 6, 10, 60,
              NULL, 1, 'Cash', 60, NULL, NULL, v_user, v_acct);
    v_cred := fnpoultrysupplier_credit(v_farm, v_sup);
    v_st := sppoultrypurchase_reversalpreview(v_farm, v_p2);
    v_r := sppoultrypurchase_reverse(v_farm, v_p2, 'Returned to supplier', NULL,
              jsonb_build_object(v_st->'payments'->0->>'key', 'KeepAsCredit'), v_st->>'fingerprint', NULL, v_user);
    IF fnpoultrysupplier_credit(v_farm, v_sup) <> v_cred + 60 THEN
        RAISE EXCEPTION 'FAIL 2a: credit % expected %', fnpoultrysupplier_credit(v_farm, v_sup), v_cred + 60;
    END IF;
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal - 60 THEN
        RAISE EXCEPTION 'FAIL 2b: keeping credit moved cash';
    END IF;
    v_pay := (v_st->'payments'->0->>'paymentId')::int;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycashflow_rows(v_farm, v_from, v_to) r
                   WHERE r.rowsource = 'SupplierAdvance' AND r.sourceid = v_pay AND r.amount = -60) THEN
        RAISE EXCEPTION 'FAIL 2c: the payment vanished from Cash Flow';
    END IF;
    RAISE NOTICE 'ok 2 kept as supplier credit: no cash, Cash Flow keeps the payment as an advance';

    -- 3. a payment that also paid another purchase: keep as credit only (used to block)
    v_p3 := sppoultryrawmaterialpurchase_record(v_farm, v_item, '__p479_supplier', v_sup, now()::timestamp, 3, 10, 30,
              NULL, 1, 'Credit', 0, NULL, NULL, v_user, v_acct);
    v_p4 := sppoultryrawmaterialpurchase_record(v_farm, v_item, '__p479_supplier', v_sup, now()::timestamp, 2, 10, 20,
              NULL, 1, 'Credit', 0, NULL, NULL, v_user, v_acct);
    v_pay := sppoultrysupplierpayment_record(v_farm, v_sup, 50, jsonb_build_array(
              jsonb_build_object('documenttype', 'RawMaterialPurchase', 'documentid', v_p3, 'amount', 30),
              jsonb_build_object('documenttype', 'RawMaterialPurchase', 'documentid', v_p4, 'amount', 20)),
              'Cash', now()::timestamp, v_acct, NULL, NULL, 'SupplierPayments', v_user);
    v_st := sppoultrypurchase_reversalpreview(v_farm, v_p3);
    IF jsonb_array_length(v_st->'blockers') <> 0 OR (v_st->'payments'->0->'allowed') ? 'Refund' THEN
        RAISE EXCEPTION 'FAIL 3a: shared payment preview %', v_st;
    END IF;
    v_err := pg_temp.p479_refused(format('SELECT sppoultrypurchase_reverse(%L, %s, %L, NULL, %L::jsonb)',
              v_farm, v_p3, 'Wrong amount', jsonb_build_object(v_st->'payments'->0->>'key', 'Refund')::text));
    IF v_err IS NULL OR v_err NOT LIKE '%also paid other items%' THEN RAISE EXCEPTION 'FAIL 3b: %', COALESCE(v_err, 'shared payment refunded'); END IF;
    v_cred := fnpoultrysupplier_credit(v_farm, v_sup);
    PERFORM sppoultrypurchase_reverse(v_farm, v_p3, 'Wrong amount', NULL, '{}'::jsonb, NULL, NULL, v_user);
    IF fnpoultrysupplier_credit(v_farm, v_sup) <> v_cred + 30 THEN RAISE EXCEPTION 'FAIL 3c: shared part not credit'; END IF;
    IF (SELECT amountpaid FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_p4) <> 20 THEN
        RAISE EXCEPTION 'FAIL 3d: the other purchase was touched';
    END IF;
    RAISE NOTICE 'ok 3 shared payment: this purchase''s part kept as credit, the other purchase untouched';

    -- 4. reasons, stale preview, used stock
    v_err := pg_temp.p479_refused(format('SELECT sppoultrypurchase_reverse(%L, %s, NULL, NULL)', v_farm, v_p4));
    IF v_err IS NULL OR v_err NOT LIKE 'Give a reason%' THEN RAISE EXCEPTION 'FAIL 4a: %', v_err; END IF;
    v_err := pg_temp.p479_refused(format('SELECT sppoultrypurchase_reverse(%L, %s, %L, NULL)', v_farm, v_p4, 'Other'));
    IF v_err IS NULL OR v_err NOT LIKE '%"Other"%' THEN RAISE EXCEPTION 'FAIL 4b: %', v_err; END IF;
    v_err := pg_temp.p479_refused(format('SELECT sppoultrypurchase_reverse(%L, %s, %L, NULL, %L::jsonb, %L)',
              v_farm, v_p4, 'Wrong amount', '{}', 'stale'));
    IF v_err IS NULL OR v_err NOT LIKE '%changed after the reversal preview%' THEN RAISE EXCEPTION 'FAIL 4c: %', v_err; END IF;
    UPDATE poultryrawmaterialpurchases SET remainingquantity = 1 WHERE poultryrawmaterialpurchaseid = v_p4;
    v_st := sppoultrypurchase_reversalpreview(v_farm, v_p4);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_st->'blockers') b WHERE b->>'code' = 'Consumed') THEN
        RAISE EXCEPTION 'FAIL 4d: used lot not blocked %', v_st->'blockers';
    END IF;
    RAISE NOTICE 'ok 4 reason rules, stale preview, used lot blocked';

    -- 5. the old 4-argument entry point still works (refund where it can)
    UPDATE poultryrawmaterialpurchases SET remainingquantity = quantity WHERE poultryrawmaterialpurchaseid = v_p4;
    PERFORM sppoultryrawmaterialpurchase_reverse(v_farm, v_p4, 'old client', v_user);
    IF (SELECT purchasereversalid FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = v_p4) IS NULL THEN
        RAISE EXCEPTION 'FAIL 5: old entry point did not reverse';
    END IF;
    RAISE NOTICE 'ok 5 old entry point';

    RAISE NOTICE 'poultry 479: all checks passed';
END
$t$;

ROLLBACK;
