-- 505_Enock_GenericExpenseListReversed. Self-contained: BEGIN ... ROLLBACK.
BEGIN;
DO $$
DECLARE v_farm text; v_acct integer; v_x integer; v_rev integer;
BEGIN
    SELECT e.farmid INTO v_farm FROM genericexpenses e
    WHERE EXISTS (SELECT 1 FROM genericexpensecategories c WHERE c.farmid = e.farmid)
    GROUP BY e.farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT a.genericcashaccountid INTO v_acct FROM genericcashaccounts a WHERE a.farmid = v_farm ORDER BY 1 LIMIT 1;
    UPDATE genericcashaccounts SET currentbalance = currentbalance + 1000 WHERE genericcashaccountid = v_acct;
    v_x := spgenericexpense_insert(v_farm, (now() AT TIME ZONE 'utc')::timestamp,
        (SELECT c.genericexpensecategoryid FROM genericexpensecategories c WHERE c.farmid = v_farm ORDER BY 1 LIMIT 1),
        NULL, '505 check', 10, NULL, 'Cash', v_acct, NULL, NULL, NULL, NULL, '505-check', NULL, NULL);
    PERFORM spgenericexpense_approve(v_x, v_farm, '505-check');
    v_rev := spgenericexpense_reverse(v_farm, v_x, 'Wrong amount', NULL, '{}'::jsonb, NULL, NULL, '505-check');
    IF NOT EXISTS (SELECT 1 FROM spgenericexpense_getall(v_farm, NULL, NULL, NULL) g
                   WHERE g.genericexpenseid = v_x AND g.expensereversalid = v_rev AND g.reversalnumber LIKE 'GER-%') THEN
        RAISE EXCEPTION 'FAIL 505.1: the list does not show the reversal'; END IF;
    RAISE NOTICE 'ok 505.1 the Expenses list carries the reversal id and number';
    RAISE NOTICE 'generic 505: all checks passed';
END $$;
ROLLBACK;
