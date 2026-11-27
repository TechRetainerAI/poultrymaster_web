-- 508_Enock_PoultryBatchReversalShowRows. Self-contained: BEGIN ... ROLLBACK.
BEGIN;
DO $$
DECLARE v_farm text; v_sup integer; v_acct integer; v_b integer; v_f integer; v_rev integer; v_row jsonb;
BEGIN
    SELECT b.farmid INTO v_farm FROM mainflockbatch b JOIN supplier s ON s.farmid::text = b.farmid
    WHERE b.farmid ~ '^[0-9a-f-]{36}$' GROUP BY b.farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT s.supplierid INTO v_sup FROM supplier s WHERE s.farmid::text = v_farm ORDER BY 1 LIMIT 1;
    SELECT a.poultrycashaccountid INTO v_acct FROM poultrycashaccounts a WHERE a.farmid = v_farm ORDER BY 1 LIMIT 1;
    UPDATE poultrycashaccounts SET currentbalance = currentbalance + 10000 WHERE poultrycashaccountid = v_acct;
    v_b := spmainflockbatch_insert('508-check', v_farm, '508-A', '508 batch', 'Test', 200, (now() AT TIME ZONE 'utc')::timestamp,
                                   'active', 5, 1000, NULL, v_sup, 1000, NULL, NULL, NULL, NULL, false, v_acct);
    INSERT INTO flock (userid, name, startdate, breed, quantity, farmid, batchid, flocktype, active)
    VALUES ('508-check', '508 flock', now() AT TIME ZONE 'utc', 'Test', 100, v_farm, v_b, 'Layer', true) RETURNING flockid INTO v_f;
    v_rev := sppoultrybatch_reverse(v_farm, v_b, 'Wrong quantity', NULL, '{}'::jsonb, true, NULL, NULL, '508-check');
    SELECT x INTO v_row FROM jsonb_array_elements(sppoultrybatchreversal_list(v_farm)) x WHERE (x->>'batchReversalId')::int = v_rev;
    IF v_row IS NULL THEN RAISE EXCEPTION 'FAIL 508.1: reversal not listed'; END IF;
    IF jsonb_array_length(v_row->'flocks') <> 1 OR (v_row->'flocks'->0->>'flockId')::int <> v_f OR v_row->'flocks'->0->>'breed' IS NULL THEN
        RAISE EXCEPTION 'FAIL 508.1: flocks %', v_row->'flocks'; END IF;
    IF jsonb_array_length(v_row->'expenses') <> 1 OR (v_row->'expenses'->0->>'amount')::numeric <> 1000 THEN
        RAISE EXCEPTION 'FAIL 508.1: expenses %', v_row->'expenses'; END IF;
    RAISE NOTICE 'ok 508.1 the list returns the reversed batch with its flocks and its expense lines';
    RAISE NOTICE 'poultry 508: all checks passed';
END $$;
ROLLBACK;
