-- 483_Enock_GenericSaleReversal -- Generic sale reversal (the Poultry/Water model).
-- Self-contained: BEGIN ... ROLLBACK. Builds its own sales in the Generic
-- company with the most sales, approves them with the live approval path, then
-- reverses them every way the dialog allows.
BEGIN;

CREATE FUNCTION pg_temp.mk_sale(p_farm text, p_cust integer, p_acct integer, p_prod integer,
                                p_qty numeric, p_price numeric, p_paid numeric, p_credit numeric DEFAULT 0)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_id integer;
BEGIN
    INSERT INTO genericsales (farmid, saledate, status, genericcustomerid, genericcashaccountid, subtotalamount,
                              totalamount, amountpaid, balance, paymentmethod, applycreditamount, createdby)
    VALUES (p_farm, now() AT TIME ZONE 'utc', 'Draft', p_cust, p_acct, p_qty * p_price, p_qty * p_price, p_paid,
            p_qty * p_price - p_paid - p_credit, 'Cash', p_credit, '483-check')
    RETURNING genericsaleid INTO v_id;
    INSERT INTO genericsaleitems (genericsaleid, farmid, itemtype, genericproductid, description, quantity, unitprice, unitfactor)
    VALUES (v_id, p_farm, 'Product', p_prod, '483 check item', p_qty, p_price, 1);
    PERFORM spgenericsale_approve(v_id, p_farm, '483-check');
    RETURN v_id;
END $$;

CREATE FUNCTION pg_temp.must_fail(p_sql text, p_like text, p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM ILIKE '%' || p_like || '%' THEN RETURN; END IF;
        RAISE EXCEPTION 'FAIL %: refused with the wrong message: %', p_label, SQLERRM;
    END;
    RAISE EXCEPTION 'FAIL %: was accepted', p_label;
END $$;

DO $$
DECLARE
    v_farm text; v_cust integer; v_acct integer; v_prod integer;
    v_stock0 numeric; v_stock numeric; v_cash0 numeric; v_cash numeric; v_bal0 numeric; v_bal numeric;
    v_sale integer; v_sale2 integer; v_pre jsonb; v_rev integer; v_rev2 integer; v_pay integer; v_n integer; v_fp text;
BEGIN
    SELECT s.farmid INTO v_farm FROM genericsales s GROUP BY s.farmid ORDER BY count(*) DESC LIMIT 1;
    SELECT c.genericcustomerid INTO v_cust FROM genericcustomers c WHERE c.farmid = v_farm ORDER BY c.genericcustomerid LIMIT 1;
    SELECT a.genericcashaccountid INTO v_acct FROM genericcashaccounts a WHERE a.farmid = v_farm ORDER BY a.genericcashaccountid LIMIT 1;
    SELECT p.genericproductid INTO v_prod FROM genericproducts p WHERE p.farmid = v_farm AND p.trackinventory ORDER BY p.genericproductid LIMIT 1;
    IF v_cust IS NULL OR v_acct IS NULL OR v_prod IS NULL THEN RAISE EXCEPTION 'FAIL 483.0: test company lacks a customer, account or product'; END IF;
    -- room to work in, inside this rolled-back transaction
    UPDATE genericproducts SET currentstock = currentstock + 1000 WHERE genericproductid = v_prod;
    UPDATE genericcashaccounts SET currentbalance = currentbalance + 100000 WHERE genericcashaccountid = v_acct;

    -- ---------------------------------------------------------------- 1
    -- walk-in sale paid in full -> money paid back
    SELECT currentstock INTO v_stock0 FROM genericproducts WHERE genericproductid = v_prod;
    SELECT currentbalance INTO v_cash0 FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    v_sale := pg_temp.mk_sale(v_farm, NULL, v_acct, v_prod, 3, 100, 300);
    v_pre := spgenericsale_reversalpreview(v_farm, v_sale);
    IF jsonb_array_length(v_pre->'blockers') <> 0 THEN RAISE EXCEPTION 'FAIL 483.1: blockers %', v_pre->'blockers'; END IF;
    IF jsonb_array_length(v_pre->'payments') <> 1 OR (v_pre->'payments'->0->'allowed') <> '["ReversePayment"]'::jsonb THEN
        RAISE EXCEPTION 'FAIL 483.1: a walk-in payment must be refund-only: %', v_pre->'payments'; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericsale_reverse(%L, %s, 'Customer returned goods', NULL, '{"%s":"KeepAsCredit"}'::jsonb, NULL, NULL, '483-check')$q$,
        v_farm, v_sale, v_pre->'payments'->0->>'key'), 'no customer to hold', '483.1 walk-in kept as credit');
    v_rev := spgenericsale_reverse(v_farm, v_sale, 'Customer returned goods', NULL, '{}'::jsonb, v_pre->>'fingerprint', '483-idem-1', '483-check');
    SELECT currentstock INTO v_stock FROM genericproducts WHERE genericproductid = v_prod;
    SELECT currentbalance INTO v_cash FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    IF v_stock <> v_stock0 THEN RAISE EXCEPTION 'FAIL 483.1: stock % (expected %)', v_stock, v_stock0; END IF;
    IF v_cash <> v_cash0 THEN RAISE EXCEPTION 'FAIL 483.1: cash % (expected %)', v_cash, v_cash0; END IF;
    IF (SELECT status || '/' || (salereversalid = v_rev)::text FROM genericsales WHERE genericsaleid = v_sale) <> 'Cancelled/true' THEN
        RAISE EXCEPTION 'FAIL 483.1: sale not marked reversed'; END IF;
    IF NOT EXISTS (SELECT 1 FROM genericcustomerpayments WHERE linkedsaleid = v_sale AND status = 'Reversed') THEN
        RAISE EXCEPTION 'FAIL 483.1: the sale''s payment was not reversed'; END IF;
    RAISE NOTICE 'ok 483.1 walk-in sale: refund only; stock and cash back exactly; payment reversed; sale Cancelled + reversal';

    -- the same click again returns the same reversal; a second reversal is refused; the sale is locked
    v_rev2 := spgenericsale_reverse(v_farm, v_sale, 'Customer returned goods', NULL, '{}'::jsonb, NULL, '483-idem-1', '483-check');
    IF v_rev2 <> v_rev THEN RAISE EXCEPTION 'FAIL 483.2: a repeated click made another reversal'; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericsale_reverse(%L, %s, 'Customer returned goods', NULL)$q$, v_farm, v_sale), 'already been reversed', '483.2 reverse twice');
    PERFORM pg_temp.must_fail(format($q$UPDATE genericsales SET notes = 'x' WHERE genericsaleid = %s$q$, v_sale), 'cannot be changed', '483.2 edit a reversed sale');
    RAISE NOTICE 'ok 483.2 a repeated click returns the same reversal; reversing twice and editing a reversed sale are refused';

    -- cash flow: the receipt stays on its day and the reversal is its own row
    SELECT count(*) INTO v_n FROM spgenericcashflow_rows(v_farm, NULL, NULL) r
    WHERE r.sourceid = (SELECT genericcustomerpaymentid FROM genericcustomerpayments WHERE linkedsaleid = v_sale)
      AND r.rowsource IN ('Receipt', 'ReceiptReversal');
    IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL 483.3: % cash flow rows for the reversed payment (expected receipt + reversal)', v_n; END IF;
    IF (SELECT COALESCE(SUM(r.amount), 0) FROM spgenericcashflow_rows(v_farm, NULL, NULL) r
        WHERE r.sourceid = (SELECT genericcustomerpaymentid FROM genericcustomerpayments WHERE linkedsaleid = v_sale)
          AND r.rowsource IN ('Receipt', 'ReceiptReversal')) <> 0 THEN
        RAISE EXCEPTION 'FAIL 483.3: receipt and reversal do not net to zero'; END IF;
    RAISE NOTICE 'ok 483.3 Cash Flow keeps the receipt and shows the reversal (net 0)';

    -- ---------------------------------------------------------------- 4
    -- customer sale part paid, with credit applied -> money kept as credit
    -- leave the customer with exactly 50 of credit (credit = negative balance)
    SELECT currentbalance INTO v_bal FROM genericcustomers WHERE genericcustomerid = v_cust;
    PERFORM fngenericcustomer_postledger(v_farm, v_cust, 'Adjustment', NULL, NULL, 0, v_bal + 50, '483 check: leave 50 credit', '483-check');
    SELECT currentbalance INTO v_bal0 FROM genericcustomers WHERE genericcustomerid = v_cust;
    SELECT currentbalance INTO v_cash0 FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    v_sale := pg_temp.mk_sale(v_farm, v_cust, v_acct, v_prod, 3, 100, 100, 50);
    v_pre := spgenericsale_reversalpreview(v_farm, v_sale);
    IF (v_pre->>'creditApplied')::numeric <> 50 THEN RAISE EXCEPTION 'FAIL 483.4: creditApplied %', v_pre->>'creditApplied'; END IF;
    v_rev := spgenericsale_reverse(v_farm, v_sale, 'Wrong customer', NULL,
             jsonb_build_object(v_pre->'payments'->0->>'key', 'KeepAsCredit'), v_pre->>'fingerprint', NULL, '483-check');
    SELECT currentbalance INTO v_bal FROM genericcustomers WHERE genericcustomerid = v_cust;
    SELECT currentbalance INTO v_cash FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    IF v_bal <> v_bal0 - 100 THEN RAISE EXCEPTION 'FAIL 483.4: customer balance % (expected % = before less the 100 kept)', v_bal, v_bal0 - 100; END IF;
    IF v_cash <> v_cash0 + 100 THEN RAISE EXCEPTION 'FAIL 483.4: cash % (expected the 100 to stay in)', v_cash; END IF;
    IF (SELECT creditcreated FROM genericsalereversals WHERE salereversalid = v_rev) <> 100 THEN RAISE EXCEPTION 'FAIL 483.4: creditcreated'; END IF;
    RAISE NOTICE 'ok 483.4 kept as credit: the 50 applied credit is back, the 100 paid becomes credit, cash stays';

    -- ---------------------------------------------------------------- 5
    -- the same with money paid back: customer exactly where they started
    SELECT currentbalance INTO v_bal0 FROM genericcustomers WHERE genericcustomerid = v_cust;
    SELECT currentbalance INTO v_cash0 FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    v_sale := pg_temp.mk_sale(v_farm, v_cust, v_acct, v_prod, 2, 100, 150);
    v_pre := spgenericsale_reversalpreview(v_farm, v_sale);
    v_rev := spgenericsale_reverse(v_farm, v_sale, 'Other', 'Priced wrong',
             jsonb_build_object(v_pre->'payments'->0->>'key', 'ReversePayment'), v_pre->>'fingerprint', NULL, '483-check');
    SELECT currentbalance INTO v_bal FROM genericcustomers WHERE genericcustomerid = v_cust;
    SELECT currentbalance INTO v_cash FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    IF v_bal <> v_bal0 THEN RAISE EXCEPTION 'FAIL 483.5: customer balance % (expected %)', v_bal, v_bal0; END IF;
    IF v_cash <> v_cash0 THEN RAISE EXCEPTION 'FAIL 483.5: cash % (expected %)', v_cash, v_cash0; END IF;
    RAISE NOTICE 'ok 483.5 paid back: customer and cash exactly as before the sale';

    -- ---------------------------------------------------------------- 6
    -- a Customer Balances payment shared with another invoice: credit only
    v_sale  := pg_temp.mk_sale(v_farm, v_cust, v_acct, v_prod, 2, 100, 0);
    v_sale2 := pg_temp.mk_sale(v_farm, v_cust, v_acct, v_prod, 1, 100, 0);
    v_pay := spgenericcustomerpayment_record(v_farm, v_cust, 300,
             jsonb_build_array(jsonb_build_object('saleid', v_sale, 'amount', 200), jsonb_build_object('saleid', v_sale2, 'amount', 100)),
             'Cash', NULL, v_acct);
    SELECT currentbalance INTO v_bal0 FROM genericcustomers WHERE genericcustomerid = v_cust;
    v_pre := spgenericsale_reversalpreview(v_farm, v_sale);
    IF (v_pre->'payments'->0->>'source') <> 'CustomerBalances' OR (v_pre->'payments'->0->'allowed') <> '["KeepAsCredit"]'::jsonb THEN
        RAISE EXCEPTION 'FAIL 483.6: shared payment options %', v_pre->'payments'; END IF;
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericsale_reverse(%L, %s, 'Duplicate sale', NULL, '{"%s":"ReversePayment"}'::jsonb, NULL, NULL, '483-check')$q$,
        v_farm, v_sale, v_pre->'payments'->0->>'key'), 'also paid other invoices', '483.6 refund a shared payment');
    v_rev := spgenericsale_reverse(v_farm, v_sale, 'Duplicate sale', NULL, '{}'::jsonb, v_pre->>'fingerprint', NULL, '483-check');
    SELECT currentbalance INTO v_bal FROM genericcustomers WHERE genericcustomerid = v_cust;
    IF v_bal <> v_bal0 - 200 THEN RAISE EXCEPTION 'FAIL 483.6: balance % (expected % : the 200 becomes credit)', v_bal, v_bal0 - 200; END IF;
    IF EXISTS (SELECT 1 FROM customerpaymentallocation WHERE module = 'generic' AND saleid = v_sale AND status = 'Posted') THEN
        RAISE EXCEPTION 'FAIL 483.6: allocation to the reversed sale still Posted'; END IF;
    IF NOT EXISTS (SELECT 1 FROM customerpaymentallocation WHERE module = 'generic' AND saleid = v_sale2 AND status = 'Posted') THEN
        RAISE EXCEPTION 'FAIL 483.6: the other invoice lost its payment'; END IF;
    RAISE NOTICE 'ok 483.6 shared Customer Balances payment: credit only; its share is released; the other invoice stays paid';

    -- ---------------------------------------------------------------- 7
    -- reasons, stale preview, drafts, the old Refund
    v_sale := pg_temp.mk_sale(v_farm, v_cust, v_acct, v_prod, 1, 100, 100);
    v_pre := spgenericsale_reversalpreview(v_farm, v_sale);
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericsale_reverse(%L, %s, NULL, NULL)$q$, v_farm, v_sale), 'Give a reason', '483.7 no reason');
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericsale_reverse(%L, %s, 'Other', ' ')$q$, v_farm, v_sale), 'few words', '483.7 Other without a note');
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericsale_reverse(%L, %s, 'Wrong customer', NULL, '{}'::jsonb, 'stale', NULL, '483-check')$q$, v_farm, v_sale),
        'changed after the reversal preview', '483.7 stale preview');
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericsale_refund(%s, %L, '483-check', 'x')$q$, v_sale, v_farm), 'replaced by Reverse', '483.7 old refund');
    INSERT INTO genericsales (farmid, saledate, status, totalamount, amountpaid, balance, createdby)
    VALUES (v_farm, now() AT TIME ZONE 'utc', 'Draft', 10, 0, 10, '483-check') RETURNING genericsaleid INTO v_sale2;
    PERFORM pg_temp.must_fail(format($q$SELECT spgenericsale_reverse(%L, %s, 'Wrong customer', NULL)$q$, v_farm, v_sale2), 'still a draft', '483.7 reverse a draft');
    RAISE NOTICE 'ok 483.7 reason required ("Other" needs a note); stale preview, drafts and the old Refund are refused';

    -- ---------------------------------------------------------------- 8
    -- a reversed sale leaves the P&L and every Approved-only report
    IF EXISTS (SELECT 1 FROM genericsales WHERE salereversalid IS NOT NULL AND status = 'Approved') THEN
        RAISE EXCEPTION 'FAIL 483.8: a reversed sale is still Approved'; END IF;
    PERFORM 1 FROM spgenericcashflow_summary(v_farm, NULL, NULL);
    RAISE NOTICE 'ok 483.8 reversed sales are Cancelled (out of P&L and reports); Cash Flow summary runs';

    -- ---------------------------------------------------------------- 9
    -- a sale paid at the counter before 475 (no payment record): simulated by
    -- removing the payment the approval wrote, as the old approval never wrote one
    v_sale := pg_temp.mk_sale(v_farm, v_cust, v_acct, v_prod, 2, 100, 100);
    SELECT genericcustomerpaymentid INTO v_pay FROM genericcustomerpayments WHERE linkedsaleid = v_sale;
    PERFORM fngenericcustomer_postledger(v_farm, v_cust, 'Adjustment', NULL, NULL, 100, 0, '483 check: undo payment credit', '483-check');
    DELETE FROM genericcustomerledger WHERE paymentid = v_pay AND transactiontype = 'PaymentCredit';
    DELETE FROM genericcustomerpayments WHERE genericcustomerpaymentid = v_pay;
    SELECT currentbalance INTO v_bal0 FROM genericcustomers WHERE genericcustomerid = v_cust;   -- before + 200 owed
    v_pre := spgenericsale_reversalpreview(v_farm, v_sale);
    IF (v_pre->'payments'->0->>'key') <> 'AT-SALE' OR (v_pre->'payments'->0->>'allocated')::numeric <> 100 THEN
        RAISE EXCEPTION 'FAIL 483.9: counter money not offered: %', v_pre->'payments'; END IF;
    v_rev := spgenericsale_reverse(v_farm, v_sale, 'Customer returned goods', NULL, '{"AT-SALE":"KeepAsCredit"}'::jsonb, v_pre->>'fingerprint', NULL, '483-check');
    SELECT currentbalance INTO v_bal FROM genericcustomers WHERE genericcustomerid = v_cust;
    IF v_bal <> v_bal0 - 300 THEN RAISE EXCEPTION 'FAIL 483.9: balance % (expected % : sale 200 off, 100 credit)', v_bal, v_bal0 - 300; END IF;
    -- walk-in counter money paid back: a SaleReversal cash-out that Cash Flow shows
    v_sale := pg_temp.mk_sale(v_farm, NULL, v_acct, v_prod, 1, 100, 100);
    DELETE FROM genericcustomerpayments WHERE linkedsaleid = v_sale;
    SELECT currentbalance INTO v_cash0 FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    v_pre := spgenericsale_reversalpreview(v_farm, v_sale);
    v_rev := spgenericsale_reverse(v_farm, v_sale, 'Customer returned goods', NULL, '{}'::jsonb, v_pre->>'fingerprint', NULL, '483-check');
    SELECT currentbalance INTO v_cash FROM genericcashaccounts WHERE genericcashaccountid = v_acct;
    IF v_cash <> v_cash0 - 100 THEN RAISE EXCEPTION 'FAIL 483.9: cash % (expected %)', v_cash, v_cash0 - 100; END IF;
    IF NOT EXISTS (SELECT 1 FROM spgenericcashflow_rows(v_farm, NULL, NULL) r WHERE r.rowsource = 'SaleRefund' AND r.sourceid = v_sale AND r.amount = -100) THEN
        RAISE EXCEPTION 'FAIL 483.9: Cash Flow does not show the counter refund'; END IF;
    RAISE NOTICE 'ok 483.9 counter money (no payment record): kept as credit, or paid back as a cash-out Cash Flow shows';

    RAISE NOTICE 'generic 483: all checks passed';
END $$;
ROLLBACK;
