-- 500_Enock_GenericPurchaseReversal -- Generic purchase reversal (the Water/Poultry model).
-- Self-contained: BEGIN ... ROLLBACK. Builds its own supplier, products and
-- purchases in the Generic company with the most purchases, approves them with
-- the live approval path, then reverses them every way the dialog allows.
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.mk_purchase(p_farm text, p_sup integer, p_acct integer, p_prod integer,
                                    p_qty numeric, p_cost numeric, p_paid numeric)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_id integer;
BEGIN
    v_id := spgenericpurchase_insert(p_farm, (now() AT TIME ZONE 'utc')::timestamp, p_sup, NULL, 0, 0, p_paid,
                                     CASE WHEN p_paid > 0 THEN 'Cash' ELSE 'Credit' END,
                                     CASE WHEN p_paid > 0 THEN p_acct END, NULL, NULL, NULL, '500 check', '500-check',
                                     jsonb_build_array(jsonb_build_object('genericproductid', p_prod, 'description', '500 item',
                                                                          'quantity', p_qty, 'unitcost', p_cost, 'unitfactor', 1)));
    PERFORM spgenericpurchase_approve(v_id, p_farm, '500-check');
    RETURN v_id;
END $$;

-- a sale/use of stock: what would make a purchase's stock "used"
CREATE OR REPLACE FUNCTION pg_temp.use_stock(p_farm text, p_prod integer, p_qty numeric) RETURNS void LANGUAGE sql AS $$
    INSERT INTO genericstockmovements (farmid, genericproductid, movementdate, movementtype, quantity, unitcost, totalcostvalue,
                                       referencetype, referenceid, reason, createdby)
    VALUES (p_farm, p_prod, now() AT TIME ZONE 'utc', 'InternalUseOut', -p_qty, 0, 0, 'GenericInternalUsage', -1, '500 check use', '500-check');
    UPDATE genericproducts SET currentstock = currentstock - p_qty WHERE genericproductid = p_prod;
$$;

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

CREATE OR REPLACE FUNCTION pg_temp.has_blocker(p_pre jsonb, p_code text) RETURNS boolean LANGUAGE sql AS $$
    SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(p_pre->'blockers') b WHERE b->>'code' LIKE p_code || '%')
$$;

DO $$
DECLARE
    v_farm text; v_acct integer; v_sup integer; v_sup2 integer; v_p integer; v_q integer;
    v_a integer; v_b integer; v_c integer; v_d integer; v_e integer; v_w integer; v_pay integer; v_pay2 integer;
    v_pre jsonb; v_rev integer; v_rev2 integer; v_n integer; v_x numeric;
    v_cash0 numeric; v_cash numeric; v_supbal0 numeric; v_supbal numeric;
BEGIN
    SELECT p.farmid INTO v_farm FROM genericpurchases p GROUP BY p.farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT a.genericcashaccountid INTO v_acct FROM genericcashaccounts a WHERE a.farmid = v_farm ORDER BY a.genericcashaccountid LIMIT 1;
    IF v_acct IS NULL THEN RAISE EXCEPTION 'FAIL 500.0: test company has no cash account'; END IF;
    UPDATE genericcashaccounts SET currentbalance = currentbalance + 100000 WHERE genericcashaccountid = v_acct;
    INSERT INTO genericsuppliers (farmid, suppliername, currentbalance) VALUES (v_farm, '500 check supplier', 0) RETURNING genericsupplierid INTO v_sup;
    INSERT INTO genericsuppliers (farmid, suppliername, currentbalance) VALUES (v_farm, '500 check supplier 2', 0) RETURNING genericsupplierid INTO v_sup2;
    INSERT INTO genericproducts (farmid, productname, trackinventory, currentstock, isactive, costprice)
    VALUES (v_farm, '500 check product P', true, 0, true, 5) RETURNING genericproductid INTO v_p;
    INSERT INTO genericproducts (farmid, productname, trackinventory, currentstock, isactive, costprice)
    VALUES (v_farm, '500 check product Q', true, 0, true, 5) RETURNING genericproductid INTO v_q;

    -- ---------------------------------------------------------------- 1
    -- 10 x 5 = 50: 20 paid at entry, 30 paid later by a Supplier Payment.
    -- Reverse: entry refunded, the payment kept as credit.
    SELECT currentbalance INTO v_cash0 FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    v_a := pg_temp.mk_purchase(v_farm, v_sup, v_acct, v_p, 10, 5, 20);
    IF (SELECT currentbalance FROM genericsuppliers WHERE genericsupplierid = v_sup) <> 30 THEN
        RAISE EXCEPTION 'FAIL 500.1: approval did not put 30 on the supplier'; END IF;
    v_pay := spgenericsupplierpayment_record(v_farm, v_sup, 30, jsonb_build_array(jsonb_build_object('documenttype', 'Purchase', 'documentid', v_a, 'amount', 30)),
                                             'Cash', NULL, v_acct, NULL, '500 pay', 'SupplierBalances', '500-check');
    v_pre := spgenericpurchase_reversalpreview(v_farm, v_a);
    IF jsonb_array_length(v_pre->'blockers') <> 0 THEN RAISE EXCEPTION 'FAIL 500.1: blockers %', v_pre->'blockers'; END IF;
    IF jsonb_array_length(v_pre->'payments') <> 2 THEN RAISE EXCEPTION 'FAIL 500.1: payments %', v_pre->'payments'; END IF;
    IF (v_pre->'payments'->0->>'key') <> 'entry' OR (v_pre->'payments'->0->>'allocated')::numeric <> 20
       OR (v_pre->'payments'->0->'allowed') <> '["KeepAsCredit","Refund"]'::jsonb THEN
        RAISE EXCEPTION 'FAIL 500.1: entry line wrong %', v_pre->'payments'->0; END IF;
    IF (v_pre->'payments'->1->>'key') <> 'sp:' || v_pay OR (v_pre->'payments'->1->>'allocated')::numeric <> 30
       OR (v_pre->'payments'->1->'allowed') <> '["KeepAsCredit","Refund"]'::jsonb THEN
        RAISE EXCEPTION 'FAIL 500.1: payment line wrong %', v_pre->'payments'->1; END IF;
    IF (v_pre->>'stockToRemove')::numeric <> 10 OR (v_pre->>'outstanding')::numeric <> 0 THEN
        RAISE EXCEPTION 'FAIL 500.1: stock/outstanding wrong %', v_pre; END IF;

    v_rev := spgenericpurchase_reverse(v_farm, v_a, 'Wrong quantity', NULL,
                                       jsonb_build_object('entry', 'Refund', 'sp:' || v_pay, 'KeepAsCredit'),
                                       v_pre->>'fingerprint', '500-idem-1', '500-check');
    SELECT currentbalance INTO v_cash FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    IF v_cash <> v_cash0 - 30 THEN RAISE EXCEPTION 'FAIL 500.1: cash % (expected %: the 30 payment stays out, the 20 came back)', v_cash, v_cash0 - 30; END IF;
    IF (SELECT currentstock FROM genericproducts WHERE genericproductid = v_p) <> 0 THEN RAISE EXCEPTION 'FAIL 500.1: stock not taken back out'; END IF;
    IF (SELECT currentbalance FROM genericsuppliers WHERE genericsupplierid = v_sup) <> 0 THEN
        RAISE EXCEPTION 'FAIL 500.1: supplier balance % (expected 0)', (SELECT currentbalance FROM genericsuppliers WHERE genericsupplierid = v_sup); END IF;
    IF fngenericsupplierpayment_unapplied(v_farm, v_pay) <> 30 THEN RAISE EXCEPTION 'FAIL 500.1: the payment is not 30 of credit'; END IF;
    IF NOT EXISTS (SELECT 1 FROM genericpurchases WHERE genericpurchaseid = v_a AND status = 'Cancelled'
                   AND purchasereversalid = v_rev AND balance = 0 AND amountpaid = 20) THEN
        RAISE EXCEPTION 'FAIL 500.1: purchase not marked reversed: %', (SELECT status || '/' || balance || '/' || amountpaid FROM genericpurchases WHERE genericpurchaseid = v_a); END IF;
    IF (SELECT refunded || '/' || creditcreated || '/' || paymenthandling FROM genericpurchasereversals WHERE purchasereversalid = v_rev) <> '20.00/30.00/Mixed' THEN
        RAISE EXCEPTION 'FAIL 500.1: record totals wrong'; END IF;
    RAISE NOTICE 'ok 500.1 entry refunded + payment kept as credit: stock, cash, supplier balance and credit exact; purchase Cancelled + reversal';

    -- ---------------------------------------------------------------- 2
    v_rev2 := spgenericpurchase_reverse(v_farm, v_a, 'Wrong quantity', NULL, '{}'::jsonb, NULL, '500-idem-1', '500-check');
    IF v_rev2 <> v_rev THEN RAISE EXCEPTION 'FAIL 500.2: a repeated click made another reversal'; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericpurchase_reverse(%L, %s, 'Wrong quantity', NULL)$q$, v_farm, v_a), 'already been reversed', '500.2 reverse twice');
    PERFORM pg_temp.must_fail(format($q$UPDATE genericpurchases SET notes = 'x' WHERE genericpurchaseid = %s$q$, v_a), 'cannot be changed', '500.2 edit a reversed purchase');
    IF (SELECT reversalnumber FROM spgenericpurchase_getall(v_farm, NULL) WHERE genericpurchaseid = v_a) IS NULL THEN
        RAISE EXCEPTION 'FAIL 500.2: the list does not show the reversal number'; END IF;
    IF (spgenericpurchase_reversalget(v_farm, v_a)->>'purchaseReversalId')::int <> v_rev THEN RAISE EXCEPTION 'FAIL 500.2: reversalget'; END IF;
    RAISE NOTICE 'ok 500.2 a repeated click returns the same reversal; twice and edits are refused; list + record read it';

    -- ---------------------------------------------------------------- 3
    -- Cash Flow: the entry payment stays on its day, the refund is its own row,
    -- the lot of the reversed purchase is gone from deferred costing.
    SELECT COALESCE(SUM(r.amount), 0), count(*) INTO v_x, v_n FROM spgenericcashflow_rows(v_farm, NULL, NULL) r
    WHERE r.sourceid = v_a AND r.rowsource IN ('PurchasePayment', 'PurchaseRefund');
    IF v_n <> 2 OR v_x <> 0 THEN RAISE EXCEPTION 'FAIL 500.3: % purchase cash flow rows netting % (expected 2 netting 0)', v_n, v_x; END IF;
    IF NOT EXISTS (SELECT 1 FROM spgenericcashflow_detail(v_farm, NULL, NULL) r WHERE r.rowsource = 'PurchaseRefund' AND r.category = 'Purchase refunds') THEN
        RAISE EXCEPTION 'FAIL 500.3: refund category'; END IF;
    IF EXISTS (SELECT 1 FROM fngenericdeferred_lots(v_farm) l WHERE l.referencetype = 'Purchase' AND l.referenceid = v_a)
       OR EXISTS (SELECT 1 FROM fngenericdeferred_draws(v_farm) d WHERE d.genericproductid = v_p) THEN
        RAISE EXCEPTION 'FAIL 500.3: the reversed lot or its reversal still in deferred costing'; END IF;
    RAISE NOTICE 'ok 500.3 Cash Flow keeps the entry payment and shows the refund (net 0); deferred lots/draws leave the reversal out';

    -- ---------------------------------------------------------------- 4
    -- stock used: B 4 units, 1 used -> blocked. C 5 units after it -> reversible
    -- (oldest first: the use came out of B). C's entry money kept as credit.
    v_b := pg_temp.mk_purchase(v_farm, v_sup, v_acct, v_p, 4, 10, 40);
    PERFORM pg_temp.use_stock(v_farm, v_p, 1);
    v_c := pg_temp.mk_purchase(v_farm, v_sup, v_acct, v_p, 5, 10, 50);
    v_pre := spgenericpurchase_reversalpreview(v_farm, v_b);
    IF NOT pg_temp.has_blocker(v_pre, 'StockUsed') THEN RAISE EXCEPTION 'FAIL 500.4: B used but not blocked: %', v_pre->'blockers'; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericpurchase_reverse(%L, %s, 'Wrong quantity', NULL)$q$, v_farm, v_b), 'sold or used', '500.4 reverse a used purchase');
    v_pre := spgenericpurchase_reversalpreview(v_farm, v_c);
    IF jsonb_array_length(v_pre->'blockers') <> 0 THEN RAISE EXCEPTION 'FAIL 500.4: C blocked: %', v_pre->'blockers'; END IF;
    SELECT currentbalance INTO v_cash0 FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    v_rev := spgenericpurchase_reverse(v_farm, v_c, 'Duplicate entry', NULL, '{}'::jsonb, v_pre->>'fingerprint', NULL, '500-check');
    IF (SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct) <> v_cash0 THEN RAISE EXCEPTION 'FAIL 500.4: keeping as credit moved cash'; END IF;
    IF (SELECT currentstock FROM genericproducts WHERE genericproductid = v_p) <> 3 THEN RAISE EXCEPTION 'FAIL 500.4: stock not 3'; END IF;
    SELECT genericsupplierpaymentid INTO v_pay2 FROM genericsupplierpayments
    WHERE farmid = v_farm AND sourcetype = 'PurchaseReversalCredit' AND genericsupplierid = v_sup AND amount = 50;
    IF v_pay2 IS NULL OR fngenericsupplierpayment_unapplied(v_farm, v_pay2) <> 50 THEN RAISE EXCEPTION 'FAIL 500.4: no 50 credit row'; END IF;
    IF EXISTS (SELECT 1 FROM spgenericcashflow_rows(v_farm, NULL, NULL) r WHERE r.rowsource = 'SupplierPayment' AND r.sourceid = v_pay2) THEN
        RAISE EXCEPTION 'FAIL 500.4: the credit row shows as cash in Cash Flow'; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericsupplierpayment_reverse(%L, %s, 'x', '500-check')$q$, v_farm, v_pay2), 'kept from a reversed purchase', '500.4 reverse the kept credit');
    RAISE NOTICE 'ok 500.4 used stock blocks; a later lot is reversible; entry money kept = no-cash credit row, not in Cash Flow, cannot be reversed away';

    -- ---------------------------------------------------------------- 5
    -- FIFO only: E 5 units, 3 used, then +10 adjusted in -> stock 12 but E's lot was drawn.
    v_e := pg_temp.mk_purchase(v_farm, v_sup, v_acct, v_q, 5, 2, 0);
    PERFORM pg_temp.use_stock(v_farm, v_q, 3);
    INSERT INTO genericstockmovements (farmid, genericproductid, movementdate, movementtype, quantity, unitcost, totalcostvalue, referencetype, referenceid, reason, createdby)
    VALUES (v_farm, v_q, now() AT TIME ZONE 'utc', 'AdjustmentIn', 10, 2, 20, 'Adjustment', -1, '500 check', '500-check');
    UPDATE genericproducts SET currentstock = currentstock + 10 WHERE genericproductid = v_q;
    v_pre := spgenericpurchase_reversalpreview(v_farm, v_e);
    IF NOT pg_temp.has_blocker(v_pre, 'StockUsed') THEN RAISE EXCEPTION 'FAIL 500.5: FIFO-used lot not blocked: %', v_pre->'blockers'; END IF;
    RAISE NOTICE 'ok 500.5 a lot already drawn (oldest first) blocks even when the shelf holds enough';

    -- ---------------------------------------------------------------- 6
    -- a payment that paid two purchases: its share can only be kept as credit.
    v_d := pg_temp.mk_purchase(v_farm, v_sup2, v_acct, v_p, 2, 10, 0);
    v_w := pg_temp.mk_purchase(v_farm, v_sup2, v_acct, v_p, 3, 10, 0);
    v_pay := spgenericsupplierpayment_record(v_farm, v_sup2, 50, jsonb_build_array(
                 jsonb_build_object('documenttype', 'Purchase', 'documentid', v_d, 'amount', 20),
                 jsonb_build_object('documenttype', 'Purchase', 'documentid', v_w, 'amount', 30)),
             'Cash', NULL, v_acct, NULL, '500 pay two', 'SupplierBalances', '500-check');
    v_pre := spgenericpurchase_reversalpreview(v_farm, v_d);
    IF (v_pre->'payments'->0->'allowed') <> '["KeepAsCredit"]'::jsonb OR v_pre->'payments'->0->>'refundUnavailableReason' IS NULL THEN
        RAISE EXCEPTION 'FAIL 500.6: a shared payment offered a refund: %', v_pre->'payments'; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericpurchase_reverse(%L, %s, 'Wrong item', NULL, '{"sp:%s":"Refund"}'::jsonb)$q$, v_farm, v_d, v_pay),
        'also paid other bills', '500.6 refund a shared payment');
    v_rev := spgenericpurchase_reverse(v_farm, v_d, 'Wrong item', NULL, '{}'::jsonb, NULL, NULL, '500-check');
    IF fngenericsupplierpayment_unapplied(v_farm, v_pay) <> 20 THEN RAISE EXCEPTION 'FAIL 500.6: the released share is not credit'; END IF;
    IF (SELECT currentbalance FROM genericsuppliers WHERE genericsupplierid = v_sup2) <> 0 THEN RAISE EXCEPTION 'FAIL 500.6: supplier 2 balance not 0'; END IF;
    RAISE NOTICE 'ok 500.6 a payment that paid two bills is credit-only; its share here becomes credit; the other bill keeps its payment';

    -- ---------------------------------------------------------------- 7
    -- a payment that paid only this purchase, refunded: the payment is reversed, cash back.
    v_d := pg_temp.mk_purchase(v_farm, v_sup2, v_acct, v_p, 1, 10, 0);
    v_pay := spgenericsupplierpayment_record(v_farm, v_sup2, 10, jsonb_build_array(jsonb_build_object('documenttype', 'Purchase', 'documentid', v_d, 'amount', 10)),
                                             'Cash', NULL, v_acct, NULL, '500 pay one', 'SupplierBalances', '500-check');
    SELECT currentbalance INTO v_cash0 FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    v_rev := spgenericpurchase_reverse(v_farm, v_d, 'Returned to supplier', NULL, jsonb_build_object('sp:' || v_pay, 'Refund'), NULL, NULL, '500-check');
    IF (SELECT status FROM genericsupplierpayments WHERE genericsupplierpaymentid = v_pay) <> 'Reversed' THEN RAISE EXCEPTION 'FAIL 500.7: payment not reversed'; END IF;
    IF (SELECT currentbalance FROM genericcashaccounts WHERE genericcashaccountid = v_acct) <> v_cash0 + 10 THEN RAISE EXCEPTION 'FAIL 500.7: cash not back'; END IF;
    IF (SELECT currentbalance FROM genericsuppliers WHERE genericsupplierid = v_sup2) <> 0 THEN RAISE EXCEPTION 'FAIL 500.7: supplier 2 balance not 0'; END IF;
    RAISE NOTICE 'ok 500.7 a payment for only this purchase can be refunded: payment reversed, cash back, supplier square';

    -- ---------------------------------------------------------------- 8
    -- no supplier: refund only; owed-only purchase: nothing to choose; draft; stale.
    v_w := pg_temp.mk_purchase(v_farm, NULL, v_acct, v_p, 1, 7, 7);
    v_pre := spgenericpurchase_reversalpreview(v_farm, v_w);
    IF (v_pre->'payments'->0->'allowed') <> '["Refund"]'::jsonb THEN RAISE EXCEPTION 'FAIL 500.8: no-supplier entry not refund-only'; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericpurchase_reverse(%L, %s, 'Wrong item', NULL, '{"entry":"KeepAsCredit"}'::jsonb)$q$, v_farm, v_w),
        'no supplier', '500.8 keep credit without a supplier');
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericpurchase_reverse(%L, %s, 'Wrong item', NULL, '{}'::jsonb, 'stale')$q$, v_farm, v_w),
        'changed after', '500.8 stale fingerprint');
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericpurchase_reverse(%L, %s, 'Other', '')$q$, v_farm, v_w), 'what happened', '500.8 Other without a note');
    v_d := pg_temp.mk_purchase(v_farm, v_sup2, v_acct, v_p, 2, 10, 0);
    v_pre := spgenericpurchase_reversalpreview(v_farm, v_d);
    IF jsonb_array_length(v_pre->'payments') <> 0 OR (v_pre->>'outstanding')::numeric <> 20 THEN RAISE EXCEPTION 'FAIL 500.8: owed-only preview %', v_pre; END IF;
    PERFORM spgenericpurchase_reverse(v_farm, v_d, 'Posted by mistake', NULL, '{}'::jsonb, NULL, NULL, '500-check');
    IF (SELECT currentbalance FROM genericsuppliers WHERE genericsupplierid = v_sup2) <> 0 THEN RAISE EXCEPTION 'FAIL 500.8: owed-only did not clear the supplier'; END IF;
    v_d := spgenericpurchase_insert(v_farm, (now() AT TIME ZONE 'utc')::timestamp, v_sup2, NULL, 0, 0, 0, 'Credit', NULL, NULL, NULL, NULL, NULL, '500-check',
                                    jsonb_build_array(jsonb_build_object('genericproductid', v_p, 'quantity', 1, 'unitcost', 1, 'unitfactor', 1)));
    IF NOT pg_temp.has_blocker(spgenericpurchase_reversalpreview(v_farm, v_d), 'Draft') THEN RAISE EXCEPTION 'FAIL 500.8: draft not blocked'; END IF;
    RAISE NOTICE 'ok 500.8 no supplier = refund only; stale preview, Other without a note and drafts refused; owed-only clears the supplier';

    RAISE NOTICE 'generic 500: all checks passed';
END $$;

ROLLBACK;
