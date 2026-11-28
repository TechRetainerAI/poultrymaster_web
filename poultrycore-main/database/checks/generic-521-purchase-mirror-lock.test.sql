-- 521_Enock_GenericPurchaseMirrorLock: a purchase is reversed on Inventory &
-- Purchases only; its expense / supplier payment copies refuse every other
-- reversal path. Self-contained: BEGIN ... ROLLBACK.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.must_fail521(p_sql text, p_expect text, p_label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        IF position(lower(p_expect) IN lower(SQLERRM)) = 0 THEN
            RAISE EXCEPTION 'FAIL %: wrong error: %', p_label, SQLERRM;
        END IF;
        RETURN;
    END;
    RAISE EXCEPTION 'FAIL %: was allowed', p_label;
END $$;

DO $$
DECLARE
    v_farm text; v_acct integer; v_sup integer; v_prod integer;
    v_pu integer; v_exp integer; v_sp integer; v_pre jsonb; v_cash0 numeric; v_bal0 numeric;
BEGIN
    SELECT p.farmid INTO v_farm FROM genericpurchases p GROUP BY p.farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT a.genericcashaccountid INTO v_acct FROM genericcashaccounts a WHERE a.farmid = v_farm ORDER BY 1 LIMIT 1;
    UPDATE genericcashaccounts SET currentbalance = currentbalance + 100000 WHERE genericcashaccountid = v_acct;
    INSERT INTO genericsuppliers (farmid, suppliername, currentbalance) VALUES (v_farm, '521 check supplier', 0) RETURNING genericsupplierid INTO v_sup;
    INSERT INTO genericproducts (farmid, productname, trackinventory, currentstock, isactive, costprice)
    VALUES (v_farm, '521 check product', true, 0, true, 10) RETURNING genericproductid INTO v_prod;

    v_pu := spgenericpurchase_insert(v_farm, (now() AT TIME ZONE 'utc')::timestamp, v_sup, NULL, 0, 0, 100, 'Cash', v_acct,
                                     NULL, NULL, NULL, '521 check', '521-check',
                                     jsonb_build_array(jsonb_build_object('genericproductid', v_prod, 'quantity', 10, 'unitcost', 10, 'unitfactor', 1)));
    PERFORM spgenericpurchase_approve(v_pu, v_farm, '521-check');
    SELECT pu.genericexpenseid INTO v_exp FROM genericpurchases pu WHERE pu.genericpurchaseid = v_pu;
    SELECT sp.genericsupplierpaymentid INTO v_sp FROM genericsupplierpayments sp WHERE sp.linkedpurchaseid = v_pu AND sp.linkedexpenseid = v_exp;
    SELECT currentbalance INTO v_cash0 FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    SELECT currentbalance INTO v_bal0 FROM genericsuppliers WHERE genericsupplierid = v_sup;

    -- 1. the copy expense is tagged and not a bill
    IF (SELECT sourcetype || ':' || sourceid FROM genericexpenses WHERE genericexpenseid = v_exp) <> 'Purchase:' || v_pu THEN
        RAISE EXCEPTION 'FAIL 521.1: copy expense not tagged Purchase'; END IF;
    IF (SELECT sourcetype FROM genericsupplierpayments WHERE genericsupplierpaymentid = v_sp) IS NOT NULL THEN
        RAISE EXCEPTION 'FAIL 521.1: copy payment got a stored sourcetype (would read as credit)'; END IF;
    IF fngenericsupplierpayment_unapplied(v_farm, v_sp) <> 0 THEN
        RAISE EXCEPTION 'FAIL 521.1: copy payment shows as supplier credit'; END IF;
    IF EXISTS (SELECT 1 FROM fngenericpayables(v_farm) b WHERE b.documenttype = 'Expense' AND b.documentid = v_exp) THEN
        RAISE EXCEPTION 'FAIL 521.1: copy expense listed as a bill to pay'; END IF;
    IF (SELECT h.sourcetype FROM spgenericsupplierpayment_history(v_farm) h WHERE h.paymentid = v_sp) <> 'PurchaseEntry' THEN
        RAISE EXCEPTION 'FAIL 521.1: Supplier Payments does not report the copy as PurchaseEntry'; END IF;
    RAISE NOTICE 'ok 521.1 copy expense tagged Purchase, not a bill; copy payment not credit, listed as PurchaseEntry';

    -- 2. every other reversal path refuses
    v_pre := spgenericexpense_reversalpreview(v_farm, v_exp);
    IF jsonb_array_length(v_pre->'blockers') = 0 THEN RAISE EXCEPTION 'FAIL 521.2: expense reversal preview has no blocker'; END IF;
    PERFORM pg_temp.must_fail521(format($q$SELECT spgenericexpense_reverse(%L, %s, 'Posted by mistake', NULL)$q$, v_farm, v_exp), 'Purchase', '521.2 expense reverse');
    PERFORM pg_temp.must_fail521(format($q$SELECT spgenericexpense_delete(%s, %L)$q$, v_exp, v_farm), 'Purchase', '521.2 expense delete');
    PERFORM pg_temp.must_fail521(format($q$SELECT spgenericsupplierpayment_reverse(%L, %s, 'Posted by mistake', '521-check')$q$, v_farm, v_sp), 'Reverse the purchase there', '521.2 payment reverse');
    PERFORM pg_temp.must_fail521(format($q$SELECT spgenericsupplierpayment_cancel(%s, %L)$q$, v_sp, v_farm), 'cannot be cancelled', '521.2 payment cancel');   -- cancel already refuses an Approved payment
    PERFORM pg_temp.must_fail521(format($q$DELETE FROM genericsupplierpayments WHERE genericsupplierpaymentid = %s$q$, v_sp), 'Reverse the purchase there', '521.2 payment delete');
    IF (SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct) <> v_cash0
       OR (SELECT currentbalance FROM genericsuppliers WHERE genericsupplierid = v_sup) <> v_bal0 THEN
        RAISE EXCEPTION 'FAIL 521.2: a refused reversal still moved cash or the supplier balance'; END IF;
    RAISE NOTICE 'ok 521.2 expense reverse/delete and payment reverse/cancel/delete all refused; nothing moved';

    -- 3. the purchase page reverses it, copies go with it
    v_pre := spgenericpurchase_reversalpreview(v_farm, v_pu);
    IF jsonb_array_length(v_pre->'blockers') <> 0 THEN RAISE EXCEPTION 'FAIL 521.3: blockers %', v_pre->'blockers'; END IF;
    PERFORM spgenericpurchase_reverse(v_farm, v_pu, 'Wrong quantity', NULL, jsonb_build_object('entry', 'Refund'), v_pre->>'fingerprint', NULL, '521-check');
    IF (SELECT status FROM genericexpenses WHERE genericexpenseid = v_exp) <> 'Cancelled'
       OR (SELECT status FROM genericsupplierpayments WHERE genericsupplierpaymentid = v_sp) <> 'Cancelled' THEN
        RAISE EXCEPTION 'FAIL 521.3: copies not cancelled with the purchase'; END IF;
    IF (SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct) <> v_cash0 + 100 THEN
        RAISE EXCEPTION 'FAIL 521.3: refund not 100'; END IF;
    IF COALESCE(current_setting('generic.purchase_system', true), '') = 'on' THEN
        RAISE EXCEPTION 'FAIL 521.3: the lock bypass was left on'; END IF;
    RAISE NOTICE 'ok 521.3 Inventory & Purchases reverse works: copies Cancelled, 100 back, lock back on';

    RAISE NOTICE 'generic 521: all checks passed';
END $$;

ROLLBACK;
