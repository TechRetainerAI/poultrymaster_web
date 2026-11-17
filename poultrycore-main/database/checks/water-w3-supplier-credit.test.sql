-- =============================================================================
-- Checks for 426 (Water supplier credit / refunds / debt, W3). SELF-ROLLING-
-- BACK, fixtures in a real Water company, dated 2001 (credit refuses future
-- dates). Prints 'water W3: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $t$
DECLARE
    v_farm text; v_acct integer; v_supp integer; v_item integer; v_p integer;
    v_adv integer; v_dpay integer; v_app integer; v_ref integer; v_cn integer; v_app2 integer;
    v_debt jsonb; v_did integer; v_n numeric; v_m numeric; v_flag integer;
    d1 date := DATE '2001-04-10';
BEGIN
    SELECT a.farmid INTO v_farm FROM watercashaccounts a ORDER BY a.watercashaccountid LIMIT 1;
    INSERT INTO watercashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, isactive)
    VALUES (v_farm, '__w3_account', 'Cash', 10000, 10000, TRUE) RETURNING watercashaccountid INTO v_acct;
    v_supp := spwatersupplier_insert(v_farm, '__w3_supplier', NULL, NULL, NULL, NULL, NULL, NULL, '__w3');
    v_item := spwaterrawmaterialitem_insert(v_farm, '__w3_item', 'PackagingRoll', 'kg', 0, 0, TRUE, NULL, 'kg', 'FIFO');
    v_p := spwaterrawmaterialpurchase_insert(v_farm, v_item, '__w3_supplier', d1::timestamp, 10, 30, 'Credit', 0,
                                             NULL, NULL, NULL, '__w3', v_supp, 300, NULL, 'kg', 1);
    v_debt := spwatersupplierdebt_create(v_farm, v_supp, 200, d1, 'OpeningBalance', 'owed before the system', NULL, NULL, '__w3');
    v_did := (v_debt->>'debtId')::int;
    IF NOT EXISTS (SELECT 1 FROM fnwaterpayables(v_farm) d WHERE d.documenttype = 'SupplierDebt' AND d.documentid = v_did AND d.balance = 200) THEN
        RAISE EXCEPTION 'FAIL 0: supplier debt not a payable';
    END IF;
    IF (SELECT totalbalance FROM spwatersupplierbalances(v_farm) WHERE supplierid = v_supp) <> 500 THEN
        RAISE EXCEPTION 'FAIL 0b: supplier owed %', (SELECT totalbalance FROM spwatersupplierbalances(v_farm) WHERE supplierid = v_supp);
    END IF;

    -- 1. an advance: money out, credit held, on Cash Flow on its day
    v_adv := spwatersupplierpayment_record(v_farm, v_supp, 500, '[]'::jsonb, 'Cash', d1 + time '10:00', v_acct, NULL, NULL, 'SupplierBalances', '__w3');
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 9500 THEN RAISE EXCEPTION 'FAIL 1a: cash'; END IF;
    IF fnwatersupplier_credit(v_farm, v_supp) <> 500 THEN RAISE EXCEPTION 'FAIL 1b: credit'; END IF;
    SELECT COALESCE(SUM(r.amount), 0) INTO v_n FROM spwatercashflow_rows(v_farm, NULL, NULL) r WHERE r.sourceid = v_adv AND r.sourcetype = 'WaterSupplierPayment';
    IF v_n <> -500 THEN RAISE EXCEPTION 'FAIL 1c: Cash Flow shows % for a 500 advance', v_n; END IF;
    RAISE NOTICE 'ok 1 advance: cash out, credit held, on Cash Flow';

    -- 2. apply 300 of it to the purchase: paid, no cash
    v_app := spwatersuppliercredit_apply(v_farm, v_adv, 'RawMaterialPurchase', v_p, 300, '__w3');
    IF (SELECT amountpaid FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_p) <> 300 THEN RAISE EXCEPTION 'FAIL 2a'; END IF;
    IF fnwatersupplier_credit(v_farm, v_supp) <> 200 THEN RAISE EXCEPTION 'FAIL 2b'; END IF;
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 9500 THEN RAISE EXCEPTION 'FAIL 2c: applying credit moved cash'; END IF;
    SELECT COALESCE(SUM(r.amount), 0) INTO v_n FROM spwatercashflow_rows(v_farm, NULL, NULL) r WHERE r.sourceid = v_adv AND r.sourcetype = 'WaterSupplierPayment';
    IF v_n <> -500 THEN RAISE EXCEPTION 'FAIL 2d: applying credit changed Cash Flow (%)', v_n; END IF;
    RAISE NOTICE 'ok 2 applying credit pays the purchase, no cash';

    -- 3. pay the debt: debt paid, cash out, on Cash Flow
    v_dpay := spwatersupplierpayment_record(v_farm, v_supp, 200,
                 jsonb_build_array(jsonb_build_object('documenttype', 'SupplierDebt', 'documentid', v_did, 'amount', 200)),
                 'Cash', d1 + time '11:00', v_acct, NULL, NULL, 'SupplierBalances', '__w3');
    IF (SELECT amountpaid FROM watersupplierdebts WHERE debtid = v_did) <> 200 THEN RAISE EXCEPTION 'FAIL 3a'; END IF;
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 9300 THEN RAISE EXCEPTION 'FAIL 3b'; END IF;
    IF fnwatersupplier_credit(v_farm, v_supp) <> 200 THEN RAISE EXCEPTION 'FAIL 3c: a debt payment became credit'; END IF;
    SELECT COALESCE(SUM(r.amount), 0) INTO v_n FROM spwatercashflow_rows(v_farm, NULL, NULL) r WHERE r.sourceid = v_dpay AND r.sourcetype = 'WaterSupplierPayment';
    IF v_n <> -200 THEN RAISE EXCEPTION 'FAIL 3d: debt payment Cash Flow %', v_n; END IF;
    v_flag := 0;
    BEGIN PERFORM spwatersupplierdebt_reverse(v_farm, v_did, 'x', '__w3'); EXCEPTION WHEN SQLSTATE 'P0001' THEN v_flag := 1; END;
    IF v_flag <> 1 THEN RAISE EXCEPTION 'FAIL 3e: paid debt reversed'; END IF;
    RAISE NOTICE 'ok 3 paying a supplier debt';

    -- 4. the supplier refunds 50 of the advance: money in, credit down
    v_ref := spwatersupplierrefund_record(v_farm, v_adv, 50, v_acct, 'Cash', d1, 'returned', '__w3');
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 9350 THEN RAISE EXCEPTION 'FAIL 4a'; END IF;
    IF fnwatersupplier_credit(v_farm, v_supp) <> 150 THEN RAISE EXCEPTION 'FAIL 4b'; END IF;
    -- 5. a credit with applications / refunds cannot be reversed
    v_flag := 0;
    BEGIN PERFORM spwatersupplierpayment_reverse(v_farm, v_adv, 'x', '__w3'); EXCEPTION WHEN raise_exception THEN v_flag := 1; END;
    IF v_flag <> 1 THEN RAISE EXCEPTION 'FAIL 5: advance reversed while applied / refunded'; END IF;
    -- 6. refund reversal: money back out, credit back
    PERFORM spwatersupplierrefund_reverse(v_farm, v_ref, 'mistake', '__w3');
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 9300 THEN RAISE EXCEPTION 'FAIL 6a'; END IF;
    IF fnwatersupplier_credit(v_farm, v_supp) <> 200 THEN RAISE EXCEPTION 'FAIL 6b'; END IF;
    SELECT COALESCE(SUM(r.amount), 0) INTO v_n FROM spwatercashflow_rows(v_farm, NULL, NULL) r WHERE r.sourceid = v_ref AND r.sourcetype = 'WaterSupplierRefund';
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 6c: refund + reversal net %', v_n; END IF;
    RAISE NOTICE 'ok 4-6 refund, guard, refund reversal';

    -- 7. undo the application, then reverse the advance: all its cash comes back
    PERFORM spwatersuppliercredit_unapply(v_farm, v_app, 'wrong purchase', '__w3');
    IF (SELECT amountpaid FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_p) <> 0 THEN RAISE EXCEPTION 'FAIL 7a'; END IF;
    PERFORM spwatersupplierpayment_reverse(v_farm, v_adv, 'test', '__w3');
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 9800 THEN
        RAISE EXCEPTION 'FAIL 7b: cash after reversing the advance %', (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct);
    END IF;
    SELECT COALESCE(SUM(r.amount) FILTER (WHERE r.amount < 0), 0), COALESCE(SUM(r.amount) FILTER (WHERE r.amount > 0), 0)
    INTO   v_n, v_m FROM spwatercashflow_rows(v_farm, NULL, NULL) r WHERE r.sourceid = v_adv AND r.sourcetype = 'WaterSupplierPayment';
    IF v_n <> -500 OR v_m <> 500 THEN RAISE EXCEPTION 'FAIL 7c: reversed advance Cash Flow out % in %', v_n, v_m; END IF;
    RAISE NOTICE 'ok 7 unapply; reversing an advance gives all its cash back';

    -- 8. a credit note: no cash; applied, it pays; it cannot go while applied
    v_cn := spwatersuppliercredit_create(v_farm, v_supp, 'SupplierCreditNote', 100, d1 + time '12:00', NULL, 'damaged rolls', '__w3');
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 9800 THEN RAISE EXCEPTION 'FAIL 8a: credit note moved cash'; END IF;
    IF EXISTS (SELECT 1 FROM spwatercashflow_rows(v_farm, NULL, NULL) r WHERE r.sourceid = v_cn AND r.sourcetype = 'WaterSupplierPayment') THEN
        RAISE EXCEPTION 'FAIL 8b: credit note on Cash Flow';
    END IF;
    v_app2 := spwatersuppliercredit_apply(v_farm, v_cn, 'RawMaterialPurchase', v_p, 100, '__w3');
    v_flag := 0;
    BEGIN PERFORM spwatersuppliercredit_reverse(v_farm, v_cn, 'x', '__w3'); EXCEPTION WHEN SQLSTATE 'P0001' THEN v_flag := 1; END;
    IF v_flag <> 1 THEN RAISE EXCEPTION 'FAIL 8c: applied credit note reversed'; END IF;
    PERFORM spwatersuppliercredit_unapply(v_farm, v_app2, 'x', '__w3');
    PERFORM spwatersuppliercredit_reverse(v_farm, v_cn, 'entered twice', '__w3');
    IF fnwatersupplier_credit(v_farm, v_supp) <> 0 THEN RAISE EXCEPTION 'FAIL 8d: credit %', fnwatersupplier_credit(v_farm, v_supp); END IF;
    IF EXISTS (SELECT 1 FROM spwatersupplierpayment_history(v_farm, v_supp) h WHERE h.paymentid = v_cn) THEN
        RAISE EXCEPTION 'FAIL 8e: credit note in payment history';
    END IF;
    RAISE NOTICE 'ok 8 credit note: no cash, applies, guarded';

    -- 9. reversing the debt payment makes it owed again; then the debt can go
    PERFORM spwatersupplierpayment_reverse(v_farm, v_dpay, 'test', '__w3');
    IF (SELECT amountpaid FROM watersupplierdebts WHERE debtid = v_did) <> 0 THEN RAISE EXCEPTION 'FAIL 9a'; END IF;
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 10000 THEN RAISE EXCEPTION 'FAIL 9b'; END IF;
    PERFORM spwatersupplierdebt_reverse(v_farm, v_did, 'entered by mistake', '__w3');
    IF EXISTS (SELECT 1 FROM fnwaterpayables(v_farm) d WHERE d.documenttype = 'SupplierDebt' AND d.documentid = v_did) THEN
        RAISE EXCEPTION 'FAIL 9c: reversed debt still a payable';
    END IF;
    RAISE NOTICE 'ok 9 debt payment reversal and debt reversal';

    -- 10. an ordinary purchase payment still works exactly as before
    PERFORM spwatersupplierpayment_record(v_farm, v_supp, 300,
                 jsonb_build_array(jsonb_build_object('documenttype', 'RawMaterialPurchase', 'documentid', v_p, 'amount', 300)),
                 'Cash', d1 + time '13:00', v_acct, NULL, NULL, 'SupplierBalances', '__w3');
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 9700 THEN RAISE EXCEPTION 'FAIL 10a'; END IF;
    IF fnwatersupplier_credit(v_farm, v_supp) <> 0 THEN RAISE EXCEPTION 'FAIL 10b'; END IF;
    RAISE NOTICE 'ok 10 an ordinary payment is unchanged';

    RAISE NOTICE 'water W3: all checks passed';
END
$t$;

ROLLBACK;
