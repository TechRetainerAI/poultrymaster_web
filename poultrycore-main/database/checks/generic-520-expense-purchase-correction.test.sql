-- 520_Enock_GenericExpensePurchaseCorrection -- Edit & repost for reversed
-- Generic expenses and purchases (the 485 sale model).
-- Self-contained: BEGIN ... ROLLBACK.
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

CREATE OR REPLACE FUNCTION pg_temp.mk_exp(p_farm text, p_acct integer, p_amount numeric) RETURNS integer LANGUAGE sql AS $$
    SELECT spgenericexpense_insert(p_farm, (now() AT TIME ZONE 'utc')::timestamp,
        (SELECT c.genericexpensecategoryid FROM genericexpensecategories c WHERE c.farmid = p_farm ORDER BY 1 LIMIT 1),
        NULL, '520 check expense', p_amount, NULL, 'Cash', p_acct, NULL, NULL, NULL, NULL, '520-check', NULL, NULL);
$$;

DO $$
DECLARE
    v_farm text; v_acct integer; v_old integer; v_new integer; v_new2 integer; v_other integer; v_n integer;
    v_prod integer; v_pu integer; v_pnew integer;
BEGIN
    -- ------------------------------------------------------------ expenses
    SELECT e.farmid INTO v_farm FROM genericexpenses e
    WHERE EXISTS (SELECT 1 FROM genericexpensecategories c WHERE c.farmid = e.farmid)
    GROUP BY e.farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT a.genericcashaccountid INTO v_acct FROM genericcashaccounts a WHERE a.farmid = v_farm ORDER BY 1 LIMIT 1;
    UPDATE genericcashaccounts SET currentbalance = currentbalance + 100000 WHERE genericcashaccountid = v_acct;

    v_old := pg_temp.mk_exp(v_farm, v_acct, 40);
    PERFORM spgenericexpense_approve(v_old, v_farm, '520-check');
    v_new := pg_temp.mk_exp(v_farm, v_acct, 45);
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericexpense_linkcorrection(%L, %s, %s)$q$, v_farm, v_new, v_old),
        'not a reversed expense', '520.1 repost an expense that is not reversed');
    PERFORM spgenericexpense_reverse(v_farm, v_old, 'Wrong amount', NULL, '{}'::jsonb, NULL, NULL, '520-check');

    SELECT count(*) INTO v_n FROM spgenericexpense_getall(v_farm) g
    WHERE g.genericexpenseid = v_old AND g.expensereversalid IS NOT NULL AND g.correctedbyexpenseid IS NULL;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 520.1: reversed expense not listed as repostable'; END IF;
    RAISE NOTICE 'ok 520.1 only a reversed expense can be reposted; the list says it can be';

    PERFORM spgenericexpense_linkcorrection(v_farm, v_new, v_old, '520-check');
    PERFORM spgenericexpense_linkcorrection(v_farm, v_new, v_old, '520-check');   -- same link again: no-op
    SELECT count(*) INTO v_n FROM spgenericexpense_getbyid(v_old, v_farm) g WHERE g.correctedbyexpenseid = v_new;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 520.2: getbyid does not name the repost'; END IF;
    SELECT count(*) INTO v_n FROM spgenericexpense_getbyid(v_new, v_farm) g WHERE g.correctsexpenseid = v_old;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 520.2: the repost does not name the reversed expense'; END IF;
    v_other := pg_temp.mk_exp(v_farm, v_acct, 46);
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericexpense_linkcorrection(%L, %s, %s)$q$, v_farm, v_other, v_old),
        'already reposted', '520.2 a second repost');
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericexpense_linkcorrection(%L, %s, %s)$q$, v_farm, v_old, v_old),
        'cannot correct itself', '520.2 self');
    RAISE NOTICE 'ok 520.2 one live repost per reversed expense, both sides named';

    -- the repost draft is deleted -> the reversed expense can be reposted again
    PERFORM spgenericexpense_delete(v_new, v_farm, 'typo', '520-check');
    IF fngenericexpense_correctedby(v_farm, v_old) IS NOT NULL THEN RAISE EXCEPTION 'FAIL 520.3: a deleted repost still counts'; END IF;
    PERFORM spgenericexpense_linkcorrection(v_farm, v_other, v_old, '520-check');
    -- approve the repost: it is an ordinary expense
    PERFORM spgenericexpense_approve(v_other, v_farm, '520-check');
    IF NOT EXISTS (SELECT 1 FROM genericexpenses WHERE genericexpenseid = v_other AND status = 'Approved' AND correctsexpenseid = v_old) THEN
        RAISE EXCEPTION 'FAIL 520.3: approved repost lost its link'; END IF;
    RAISE NOTICE 'ok 520.3 a deleted repost frees the reversed expense; an approved repost keeps the link';

    -- ------------------------------------------------------------ purchases
    SELECT p.farmid INTO v_farm FROM genericpurchases p GROUP BY p.farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT a.genericcashaccountid INTO v_acct FROM genericcashaccounts a WHERE a.farmid = v_farm ORDER BY 1 LIMIT 1;
    UPDATE genericcashaccounts SET currentbalance = currentbalance + 100000 WHERE genericcashaccountid = v_acct;
    INSERT INTO genericproducts (farmid, productname, trackinventory, currentstock, isactive, costprice)
    VALUES (v_farm, '520 check product', true, 0, true, 10) RETURNING genericproductid INTO v_prod;

    v_pu := spgenericpurchase_insert(v_farm, (now() AT TIME ZONE 'utc')::timestamp, NULL, NULL, 0, 0, 100, 'Cash', v_acct,
                                     NULL, NULL, NULL, '520 check A', '520-check',
                                     jsonb_build_array(jsonb_build_object('genericproductid', v_prod, 'quantity', 10, 'unitcost', 10, 'unitfactor', 1)));
    PERFORM spgenericpurchase_approve(v_pu, v_farm, '520-check');
    v_pnew := spgenericpurchase_insert(v_farm, (now() AT TIME ZONE 'utc')::timestamp, NULL, NULL, 0, 0, 90, 'Cash', v_acct,
                                     NULL, NULL, NULL, '520 check B', '520-check',
                                     jsonb_build_array(jsonb_build_object('genericproductid', v_prod, 'quantity', 9, 'unitcost', 10, 'unitfactor', 1)));
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericpurchase_linkcorrection(%L, %s, %s)$q$, v_farm, v_pnew, v_pu),
        'not a reversed purchase', '520.4 repost a purchase that is not reversed');
    PERFORM spgenericpurchase_reverse(v_farm, v_pu, 'Wrong quantity', NULL, '{}'::jsonb, NULL, NULL, '520-check');
    PERFORM spgenericpurchase_linkcorrection(v_farm, v_pnew, v_pu, '520-check');
    SELECT count(*) INTO v_n FROM spgenericpurchase_getall(v_farm) g WHERE g.genericpurchaseid = v_pu AND g.correctedbypurchaseid = v_pnew;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 520.4: the list does not name the repost'; END IF;
    SELECT count(*) INTO v_n FROM spgenericpurchase_getall(v_farm) g WHERE g.genericpurchaseid = v_pnew AND g.correctspurchaseid = v_pu;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 520.4: the repost does not name the reversed purchase'; END IF;
    PERFORM spgenericpurchase_cancel(v_pnew, v_farm, '520-check', 'typo');
    IF fngenericpurchase_correctedby(v_farm, v_pu) IS NOT NULL THEN RAISE EXCEPTION 'FAIL 520.4: a cancelled repost still counts'; END IF;
    RAISE NOTICE 'ok 520.4 purchases: only a reversed one is reposted, both sides named, a cancelled repost frees it';

    RAISE NOTICE 'generic 520: all checks passed';
END $$;

ROLLBACK;
