-- 519_Enock_GenericPurchaseMirrorRows: one approved purchase is ONE row on Cash
-- Flow and Financial Activity, not three (purchase + mirror expense + mirror
-- supplier payment). Self-contained: BEGIN ... ROLLBACK.
BEGIN;

DO $$
DECLARE
    v_farm text; v_acct integer; v_sup integer; v_prod integer;
    v_pu integer; v_exp integer; v_sp integer; v_pu2 integer; v_exp2 integer; v_pay integer;
    v_n integer; v_amt numeric; v_today date := (now() AT TIME ZONE 'utc')::date;
BEGIN
    SELECT p.farmid INTO v_farm FROM genericpurchases p GROUP BY p.farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT a.genericcashaccountid INTO v_acct FROM genericcashaccounts a WHERE a.farmid = v_farm ORDER BY 1 LIMIT 1;
    UPDATE genericcashaccounts SET currentbalance = currentbalance + 100000 WHERE genericcashaccountid = v_acct;
    INSERT INTO genericsuppliers (farmid, suppliername, currentbalance) VALUES (v_farm, '519 check supplier', 0) RETURNING genericsupplierid INTO v_sup;
    INSERT INTO genericproducts (farmid, productname, trackinventory, currentstock, isactive, costprice)
    VALUES (v_farm, '519 check product', true, 0, true, 10) RETURNING genericproductid INTO v_prod;

    -- A: 100 purchase paid in full at entry, with a supplier (the reported case)
    v_pu := spgenericpurchase_insert(v_farm, (now() AT TIME ZONE 'utc')::timestamp, v_sup, NULL, 0, 0, 100, 'Cash', v_acct,
                                     NULL, NULL, NULL, '519 check A', '519-check',
                                     jsonb_build_array(jsonb_build_object('genericproductid', v_prod, 'quantity', 10, 'unitcost', 10, 'unitfactor', 1)));
    PERFORM spgenericpurchase_approve(v_pu, v_farm, '519-check');
    SELECT pu.genericexpenseid INTO v_exp FROM genericpurchases pu WHERE pu.genericpurchaseid = v_pu;
    SELECT sp.genericsupplierpaymentid INTO v_sp FROM genericsupplierpayments sp
    WHERE  sp.linkedpurchaseid = v_pu AND sp.linkedexpenseid = v_exp;
    IF v_exp IS NULL OR v_sp IS NULL THEN
        RAISE EXCEPTION 'FAIL 519.0: approve no longer creates the mirror expense/payment (exp %, sp %) -- re-check 519', v_exp, v_sp;
    END IF;

    SELECT count(*), COALESCE(sum(r.amount), 0) INTO v_n, v_amt FROM spgenericcashflow_rows(v_farm, NULL, NULL) r
    WHERE (r.rowsource = 'PurchasePayment' AND r.sourceid = v_pu)
       OR (r.rowsource = 'Expense'         AND r.sourcerowid = v_exp)
       OR (r.rowsource = 'SupplierPayment' AND r.sourcerowid = v_sp);
    IF v_n <> 1 OR v_amt <> -100 THEN
        RAISE EXCEPTION 'FAIL 519.1: Cash Flow has % row(s) totalling % for one 100 purchase (expected 1 row, -100)', v_n, v_amt;
    END IF;
    RAISE NOTICE 'ok 519.1 Cash Flow: a 100 purchase paid at entry is one row of -100';

    SELECT count(*), COALESCE(sum(e.moneyout), 0) INTO v_n, v_amt FROM fngenericfa_events(v_farm, v_today - 1, v_today + 1) e
    WHERE e.eventkey IN ('PurchasePayment:' || v_pu, 'Expense:' || v_exp, 'SupplierPayment:' || v_sp);
    IF v_n <> 1 OR v_amt <> 100 THEN
        RAISE EXCEPTION 'FAIL 519.2: Financial Activity has % event(s), money out % (expected 1, 100)', v_n, v_amt;
    END IF;
    IF EXISTS (SELECT 1 FROM fngenericfa_events(v_farm, v_today - 1, v_today + 1) e WHERE e.eventkey = 'PurchasePayment:' || v_pu AND e.expense <> 0) THEN
        RAISE EXCEPTION 'FAIL 519.2: the purchase shows as a P&L expense (Generic stock is costed at sale)';
    END IF;
    RAISE NOTICE 'ok 519.2 Financial Activity: one event, 100 out, no expense';

    -- B: 100 purchase on credit, then a supplier payment recorded by hand -> that payment IS cash
    v_pu2 := spgenericpurchase_insert(v_farm, (now() AT TIME ZONE 'utc')::timestamp, v_sup, NULL, 0, 0, 0, 'Credit', NULL,
                                      NULL, NULL, NULL, '519 check B', '519-check',
                                      jsonb_build_array(jsonb_build_object('genericproductid', v_prod, 'quantity', 10, 'unitcost', 10, 'unitfactor', 1)));
    PERFORM spgenericpurchase_approve(v_pu2, v_farm, '519-check');
    SELECT pu.genericexpenseid INTO v_exp2 FROM genericpurchases pu WHERE pu.genericpurchaseid = v_pu2;
    IF EXISTS (SELECT 1 FROM fngenericfa_events(v_farm, v_today - 1, v_today + 1) e WHERE e.eventkey = 'Expense:' || v_exp2) THEN
        RAISE EXCEPTION 'FAIL 519.3: the on-credit purchase''s mirror expense is on Financial Activity';
    END IF;
    v_pay := spgenericsupplierpayment_record(v_farm, v_sup, 100, jsonb_build_array(jsonb_build_object('documenttype', 'Purchase', 'documentid', v_pu2, 'amount', 100)),
                                             'Cash', NULL, v_acct, NULL, '519 pay', 'SupplierBalances', '519-check');
    SELECT COALESCE(sum(r.amount), 0) INTO v_amt FROM spgenericcashflow_rows(v_farm, NULL, NULL) r
    WHERE (r.rowsource = 'PurchasePayment' AND r.sourceid = v_pu2) OR (r.rowsource = 'SupplierPayment' AND r.sourcerowid = v_pay)
       OR (r.rowsource = 'Expense' AND r.sourcerowid = v_exp2);
    IF v_amt <> -100 THEN RAISE EXCEPTION 'FAIL 519.3: credit purchase + hand payment = % in Cash Flow (expected -100)', v_amt; END IF;
    RAISE NOTICE 'ok 519.3 a supplier payment recorded by hand still counts; the credit purchase adds nothing';

    -- D: every existing purchase in the database -- no mirror row left on Cash Flow
    SELECT count(*) INTO v_n
    FROM   (SELECT DISTINCT pu.farmid FROM genericpurchases pu WHERE pu.genericexpenseid IS NOT NULL) f
    CROSS  JOIN LATERAL spgenericcashflow_rows(f.farmid, NULL, NULL) r
    WHERE  (r.rowsource = 'Expense' AND public.fngenericpurchase_ismirrorexpense(r.sourcerowid))
        OR (r.rowsource = 'SupplierPayment' AND EXISTS (
               SELECT 1 FROM genericsupplierpayments sp WHERE sp.genericsupplierpaymentid = r.sourcerowid
                 AND public.fngenericpurchase_ismirrorpayment(sp.linkedpurchaseid, sp.linkedexpenseid)));
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 519.4: % mirror row(s) still on Cash Flow across companies', v_n; END IF;
    RAISE NOTICE 'ok 519.4 no purchase mirror row on any company''s Cash Flow';

    -- E: purchase A can be reversed, and its mirror expense + payment go with it
    DECLARE v_pre jsonb; v_rev integer; v_cash0 numeric; BEGIN
        SELECT currentbalance INTO v_cash0 FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
        v_pre := spgenericpurchase_reversalpreview(v_farm, v_pu);
        IF jsonb_array_length(v_pre->'blockers') <> 0 THEN RAISE EXCEPTION 'FAIL 519.5: reversal blocked %', v_pre->'blockers'; END IF;
        v_rev := spgenericpurchase_reverse(v_farm, v_pu, 'Wrong quantity', NULL, jsonb_build_object('entry', 'Refund'),
                                           v_pre->>'fingerprint', NULL, '519-check');
        IF (SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct) <> v_cash0 + 100 THEN
            RAISE EXCEPTION 'FAIL 519.5: refund did not bring 100 back'; END IF;
        IF (SELECT status FROM genericexpenses WHERE genericexpenseid = v_exp) <> 'Cancelled'
           OR (SELECT status FROM genericsupplierpayments WHERE genericsupplierpaymentid = v_sp) <> 'Cancelled' THEN
            RAISE EXCEPTION 'FAIL 519.5: mirror rows not cancelled with the purchase'; END IF;
        SELECT COALESCE(sum(r.amount), 0) INTO v_amt FROM spgenericcashflow_rows(v_farm, NULL, NULL) r
        WHERE (r.rowsource = 'PurchasePayment' AND r.sourceid = v_pu) OR (r.rowsource = 'PurchaseRefund' AND r.sourceid = v_pu);
        IF v_amt <> 0 THEN RAISE EXCEPTION 'FAIL 519.5: reversed purchase nets % on Cash Flow (expected 0)', v_amt; END IF;
    END;
    RAISE NOTICE 'ok 519.5 a paid purchase reverses (no LegacyPayment block); mirror expense + payment Cancelled; cash nets 0';

    RAISE NOTICE 'generic 519: all checks passed';
END $$;

ROLLBACK;
