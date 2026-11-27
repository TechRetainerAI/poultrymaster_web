-- 501_Enock_GenericCashFlowSupplierPayments: a purchase paid later is counted
-- once; manual supplier credits are not cash. Self-contained: BEGIN ... ROLLBACK.
BEGIN;

DO $$
DECLARE
    v_farm text; v_acct integer; v_sup integer; v_prod integer; v_pu integer; v_pay integer; v_cred integer;
    v_rows numeric; v_n integer;
BEGIN
    SELECT p.farmid INTO v_farm FROM genericpurchases p GROUP BY p.farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT a.genericcashaccountid INTO v_acct FROM genericcashaccounts a WHERE a.farmid = v_farm ORDER BY 1 LIMIT 1;
    UPDATE genericcashaccounts SET currentbalance = currentbalance + 100000 WHERE genericcashaccountid = v_acct;
    INSERT INTO genericsuppliers (farmid, suppliername, currentbalance) VALUES (v_farm, '501 check supplier', 0) RETURNING genericsupplierid INTO v_sup;
    INSERT INTO genericproducts (farmid, productname, trackinventory, currentstock, isactive, costprice)
    VALUES (v_farm, '501 check product', true, 0, true, 10) RETURNING genericproductid INTO v_prod;

    -- 100 purchase: 40 at entry, 60 by a Supplier Payment later
    v_pu := spgenericpurchase_insert(v_farm, (now() AT TIME ZONE 'utc')::timestamp, v_sup, NULL, 0, 0, 40, 'Cash', v_acct,
                                     NULL, NULL, NULL, '501 check', '501-check',
                                     jsonb_build_array(jsonb_build_object('genericproductid', v_prod, 'quantity', 10, 'unitcost', 10, 'unitfactor', 1)));
    PERFORM spgenericpurchase_approve(v_pu, v_farm, '501-check');
    v_pay := spgenericsupplierpayment_record(v_farm, v_sup, 60, jsonb_build_array(jsonb_build_object('documenttype', 'Purchase', 'documentid', v_pu, 'amount', 60)),
                                             'Cash', NULL, v_acct, NULL, '501 pay', 'SupplierBalances', '501-check');
    SELECT COALESCE(SUM(r.amount), 0) INTO v_rows FROM spgenericcashflow_rows(v_farm, NULL, NULL) r
    WHERE (r.rowsource = 'PurchasePayment' AND r.sourceid = v_pu) OR (r.rowsource = 'SupplierPayment' AND r.sourceid = v_pay);
    IF v_rows <> -100 THEN RAISE EXCEPTION 'FAIL 501.1: purchase + payment count % in Cash Flow (expected -100)', v_rows; END IF;
    IF (SELECT r.amount FROM spgenericcashflow_rows(v_farm, NULL, NULL) r WHERE r.rowsource = 'PurchasePayment' AND r.sourceid = v_pu) <> -40 THEN
        RAISE EXCEPTION 'FAIL 501.1: the purchase row is not the 40 paid at entry'; END IF;
    RAISE NOTICE 'ok 501.1 a purchase paid partly later counts 100 once: 40 on the purchase, 60 on the payment';

    -- a manual credit is not cash
    INSERT INTO genericsupplierpayments (farmid, genericsupplierid, paymentdate, amount, paymentmethod, genericcashaccountid,
                                         status, sourcetype, createdby, approvedby, approvedat, createdat)
    VALUES (v_farm, v_sup, now() AT TIME ZONE 'utc', 25, 'Credit', NULL, 'Approved', 'SupplierManualCredit', '501-check', '501-check',
            now() AT TIME ZONE 'utc', now() AT TIME ZONE 'utc')
    RETURNING genericsupplierpaymentid INTO v_cred;
    SELECT count(*) INTO v_n FROM spgenericcashflow_rows(v_farm, NULL, NULL) r WHERE r.rowsource = 'SupplierPayment' AND r.sourceid = v_cred;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 501.2: a manual credit shows as money out'; END IF;
    RAISE NOTICE 'ok 501.2 a manual supplier credit is not in Cash Flow';

    -- every purchase row on the database equals its own CashOut at entry
    SELECT count(*) INTO v_n
    FROM spgenericcashflow_rows(v_farm, NULL, NULL) r
    WHERE r.rowsource = 'PurchasePayment'
      AND -r.amount <> COALESCE((SELECT -SUM(t.amount) FROM genericcashtransactions t
                                 WHERE t.farmid = v_farm AND t.sourcetype = 'Purchase' AND t.sourceid = r.sourceid), 0);
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 501.3: % purchase rows differ from the cash that left at entry', v_n; END IF;
    RAISE NOTICE 'ok 501.3 every purchase row equals the purchase''s own cash out at entry';

    RAISE NOTICE 'generic 501: all checks passed';
END $$;

ROLLBACK;
