-- =============================================================================
-- Checks for 458 (Water sale reversal).  SELF-ROLLING-BACK, fixtures in a real
-- Water company, dated 2001.  Prints 'water 458: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.w458_refused(p_sql text) RETURNS text LANGUAGE plpgsql AS $r$
BEGIN
    EXECUTE p_sql;
    RETURN NULL;
EXCEPTION WHEN OTHERS THEN
    RETURN SQLERRM;
END $r$;

DO $t$
DECLARE
    v_farm text; v_cust integer; v_prod integer; v_cust2 integer;
    v_s1 integer; v_s2 integer; v_s3 integer; v_s4 integer; v_s5 integer; v_s6 integer; v_s7 integer;
    v_dr integer; v_dsale integer; v_loading integer;
    v_rev integer; v_rev2 integer; v_pid integer; v_grp uuid; v_cgrp uuid;
    v_prev jsonb; v_err text; v_n numeric; v_m numeric; v_lt record; v_inc0 numeric; v_inc1 numeric;
    d1 date := DATE '2001-03-10';
    d2 date := DATE '2001-03-11';
BEGIN
    SELECT a.farmid INTO v_farm FROM watercashaccounts a ORDER BY a.watercashaccountid LIMIT 1;
    INSERT INTO watercustomers (farmid, name) VALUES (v_farm, '__w458_customer') RETURNING watercustomerid INTO v_cust;
    INSERT INTO watercustomers (farmid, name) VALUES (v_farm, '__w458_customer2') RETURNING watercustomerid INTO v_cust2;
    INSERT INTO waterproducts (farmid, name, unit) VALUES (v_farm, '__w458_bag', 'Bag') RETURNING waterproductid INTO v_prod;

    -- ---- sale 1: 10 bags @ 5, paid on the Sales page, the same day
    v_s1 := spwatersale_createv2(v_farm, v_cust, d1 + time '09:00', NULL, '__w458',
                jsonb_build_array(jsonb_build_object('WaterProductId', v_prod, 'Quantity', 10, 'UnitPrice', 5))::text);
    v_pid := spwaterpayment_record(v_farm, v_s1, 50, 'Cash', d1 + time '09:05', NULL, NULL, '__w458');
    SELECT paymentgroupid INTO v_grp FROM waterpayments WHERE waterpaymentid = v_pid;
    IF (SELECT SUM(quantity) FROM waterstocktransactions WHERE waterproductid = v_prod) <> -10 THEN RAISE EXCEPTION 'FAIL 0: stock'; END IF;
    SELECT totalincome INTO v_inc0 FROM spwaterreport_periodpnl(v_farm, d1, d1);
    -- from here on the fixture sales are no longer "fresh" in this transaction
    PERFORM set_config('water.sale_fresh', '', true);

    -- 1. delete / cancel / edit refused
    v_err := pg_temp.w458_refused(format('SELECT spwatersale_delete(%s, %L)', v_s1, v_farm));
    IF v_err IS NULL OR v_err NOT LIKE '%Reverse it instead%' THEN RAISE EXCEPTION 'FAIL 1a: delete %', v_err; END IF;
    v_err := pg_temp.w458_refused(format('SELECT spwatersale_cancel(%s, %L)', v_s1, v_farm));
    IF v_err IS NULL THEN RAISE EXCEPTION 'FAIL 1b: cancel ran'; END IF;
    v_err := pg_temp.w458_refused(format('UPDATE watersales SET totalamount = 1 WHERE watersaleid = %s', v_s1));
    IF v_err IS NULL THEN RAISE EXCEPTION 'FAIL 1c: total edited'; END IF;
    v_err := pg_temp.w458_refused(format('DELETE FROM watersales WHERE watersaleid = %s', v_s1));
    IF v_err IS NULL THEN RAISE EXCEPTION 'FAIL 1d: row deleted'; END IF;
    v_err := pg_temp.w458_refused(format('UPDATE watersaleitems SET quantity = 1 WHERE watersaleid = %s', v_s1));
    IF v_err IS NULL THEN RAISE EXCEPTION 'FAIL 1e: line edited'; END IF;
    v_err := pg_temp.w458_refused(format('UPDATE watersales SET notes = %L WHERE watersaleid = %s', 'note', v_s1));
    IF v_err IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1f: notes refused: %', v_err; END IF;
    RAISE NOTICE 'ok 1 a saved sale cannot be deleted, cancelled or edited';

    -- 2. preview
    v_prev := spwatersale_reversalpreview(v_farm, v_s1);
    IF jsonb_array_length(v_prev->'blockers') <> 0 THEN RAISE EXCEPTION 'FAIL 2a: %', v_prev->'blockers'; END IF;
    IF jsonb_array_length(v_prev->'payments') <> 1 OR NOT (v_prev->'payments'->0->'allowed') ? 'ReversePayment'
       OR NOT (v_prev->'payments'->0->'allowed') ? 'KeepAsCredit' THEN RAISE EXCEPTION 'FAIL 2b: %', v_prev->'payments'; END IF;
    IF (v_prev->'lines'->0->>'restoreQuantity')::numeric <> 10 THEN RAISE EXCEPTION 'FAIL 2c: %', v_prev->'lines'; END IF;
    RAISE NOTICE 'ok 2 preview';

    -- 3. stale preview refused
    v_err := pg_temp.w458_refused(format('SELECT spwatersale_reverse(%L, %s, %L, NULL, %L::jsonb, %L)',
                                         v_farm, v_s1, 'Wrong price', '{}', 'not-the-fingerprint'));
    IF v_err IS NULL OR v_err NOT LIKE '%changed after%' THEN RAISE EXCEPTION 'FAIL 3: %', v_err; END IF;
    RAISE NOTICE 'ok 3 stale preview refused';

    -- 4. reverse with ReversePayment
    v_rev := spwatersale_reverse(v_farm, v_s1, 'Wrong price', NULL,
                                 jsonb_build_object(v_grp::text, 'ReversePayment'), v_prev->>'fingerprint', '__w458-k1', '__w458');
    IF (SELECT status FROM watersales WHERE watersaleid = v_s1) <> 'Cancelled'
       OR (SELECT salereversalid FROM watersales WHERE watersaleid = v_s1) <> v_rev THEN RAISE EXCEPTION 'FAIL 4a: sale not marked'; END IF;
    IF (SELECT SUM(quantity) FROM waterstocktransactions WHERE waterproductid = v_prod) <> 0 THEN RAISE EXCEPTION 'FAIL 4b: stock not back'; END IF;
    IF (SELECT status FROM waterpayments WHERE waterpaymentid = v_pid) <> 'Reversed' THEN RAISE EXCEPTION 'FAIL 4c: payment'; END IF;
    IF EXISTS (SELECT 1 FROM customerpaymentallocation WHERE module = 'water' AND saleid = v_s1 AND status = 'Posted') THEN RAISE EXCEPTION 'FAIL 4d: allocation'; END IF;
    IF (SELECT reversalnumber FROM watersalereversals WHERE salereversalid = v_rev) NOT LIKE 'WSR-%' THEN RAISE EXCEPTION 'FAIL 4e'; END IF;
    IF spwatersale_reverse(v_farm, v_s1, 'Wrong price', NULL, '{}'::jsonb, NULL, '__w458-k1', '__w458') <> v_rev THEN RAISE EXCEPTION 'FAIL 4f: idempotency'; END IF;
    v_err := pg_temp.w458_refused(format('SELECT spwatersale_reverse(%L, %s, %L, NULL)', v_farm, v_s1, 'Wrong price'));
    IF v_err IS NULL OR v_err NOT LIKE '%already been reversed%' THEN RAISE EXCEPTION 'FAIL 4g: %', v_err; END IF;
    IF (SELECT SUM(quantity) FROM waterstocktransactions WHERE waterproductid = v_prod) <> 0 THEN RAISE EXCEPTION 'FAIL 4h: stock twice'; END IF;
    v_err := pg_temp.w458_refused(format('UPDATE watersales SET notes = %L WHERE watersaleid = %s', 'x', v_s1));
    IF v_err IS NULL THEN RAISE EXCEPTION 'FAIL 4i: reversed sale edited'; END IF;
    v_err := pg_temp.w458_refused(format('SELECT spwaterpayment_record(%L, %s, 5)', v_farm, v_s1));
    IF v_err IS NULL THEN RAISE EXCEPTION 'FAIL 4j: payment on a reversed sale'; END IF;
    SELECT totalincome INTO v_inc1 FROM spwaterreport_periodpnl(v_farm, d1, d1);
    IF v_inc1 <> v_inc0 - 50 THEN RAISE EXCEPTION 'FAIL 4k: P&L income % -> %', v_inc0, v_inc1; END IF;
    -- Cash Flow: the receipt stays on its day, the reversal takes it out
    SELECT COALESCE(SUM(r.amount), 0), COUNT(*) INTO v_n, v_m FROM spwatercashflow_rows(v_farm, NULL, NULL) r
    WHERE r.rowsource IN ('Receipt', 'ReceiptReversal') AND r.sourcerowid = v_pid;
    IF v_n <> 0 OR v_m <> 2 THEN RAISE EXCEPTION 'FAIL 4l: cash flow net % rows %', v_n, v_m; END IF;
    IF NOT EXISTS (SELECT 1 FROM spwatercashflow_rows(v_farm, d1::timestamp, d1 + time '23:59') r
                   WHERE r.rowsource = 'Receipt' AND r.sourcerowid = v_pid AND r.amount = 50) THEN RAISE EXCEPTION 'FAIL 4m: receipt left its day'; END IF;
    RAISE NOTICE 'ok 4 reverse: stock back once, payment reversed, P&L and Cash Flow';

    -- 5. KeepAsCredit
    v_s2 := spwatersale_createv2(v_farm, v_cust, d2 + time '09:00', NULL, '__w458',
                jsonb_build_array(jsonb_build_object('WaterProductId', v_prod, 'Quantity', 8, 'UnitPrice', 5))::text);
    v_pid := spwaterpayment_record(v_farm, v_s2, 40, 'Cash', d2 + time '09:05', NULL, NULL, '__w458');
    SELECT paymentgroupid INTO v_grp FROM waterpayments WHERE waterpaymentid = v_pid;
    PERFORM set_config('water.sale_fresh', '', true);
    SELECT * INTO v_lt FROM fnwaterdailyclosing_livetotals(v_farm, d2);
    v_n := v_lt.totalincome - v_lt.creditsales + v_lt.customercollections;     -- money in for the day
    v_rev := spwatersale_reverse(v_farm, v_s2, 'Wrong customer', NULL, jsonb_build_object(v_grp::text, 'KeepAsCredit'),
                                 NULL, NULL, '__w458');
    IF (SELECT status FROM waterpayments WHERE waterpaymentid = v_pid) <> 'Posted' THEN RAISE EXCEPTION 'FAIL 5a: payment touched'; END IF;
    IF fnwatercustomer_credit(v_farm, v_cust) <> 40 THEN RAISE EXCEPTION 'FAIL 5b: credit %', fnwatercustomer_credit(v_farm, v_cust); END IF;
    SELECT * INTO v_lt FROM fnwaterdailyclosing_livetotals(v_farm, d2);
    IF v_lt.totalincome - v_lt.creditsales + v_lt.customercollections <> v_n THEN
        RAISE EXCEPTION 'FAIL 5c: the day''s money moved % -> %', v_n, v_lt.totalincome - v_lt.creditsales + v_lt.customercollections;
    END IF;
    IF EXISTS (SELECT 1 FROM spwatercashflow_rows(v_farm, NULL, NULL) r JOIN waterpayments p ON p.waterpaymentid = r.sourcerowid
               WHERE r.rowsource = 'Receipt' AND p.sourcetype = 'SaleReversalCredit') THEN RAISE EXCEPTION 'FAIL 5d: credit is a receipt'; END IF;
    IF NOT EXISTS (SELECT 1 FROM spwatercashflow_rows(v_farm, NULL, NULL) r WHERE r.rowsource = 'Receipt' AND r.sourcerowid = v_pid) THEN
        RAISE EXCEPTION 'FAIL 5e: the money received left Cash Flow';
    END IF;
    SELECT p.paymentgroupid INTO v_cgrp FROM waterpayments p WHERE p.sourcetype = 'SaleReversalCredit' AND p.sourceid = v_s2;
    IF EXISTS (SELECT 1 FROM spwatercustomerpayment_history(v_farm, v_cust) h WHERE h.paymentgroupid = v_cgrp) THEN RAISE EXCEPTION 'FAIL 5f: credit in payment history'; END IF;
    v_err := pg_temp.w458_refused(format('SELECT spwatercustomerpayment_reverse(%L, %L::uuid)', v_farm, v_cgrp));
    IF v_err IS NULL OR v_err NOT LIKE '%refund%' THEN RAISE EXCEPTION 'FAIL 5g: %', v_err; END IF;
    IF (SELECT SUM(debit) - SUM(credit) FROM spwatercustomerstatement(v_farm, v_cust)) <> 0 THEN RAISE EXCEPTION 'FAIL 5h: statement'; END IF;
    IF (SELECT e.saleid FROM spwatercustomercredit_events(v_farm, v_cust) e WHERE e.paymentgroupid = v_cgrp) <> v_s2 THEN RAISE EXCEPTION 'FAIL 5i: events'; END IF;
    IF EXISTS (SELECT 1 FROM fnwaterbalanceaudit(v_farm) a WHERE a.documentid IN (v_s1, v_s2) AND a.documenttype = 'WaterSale') THEN RAISE EXCEPTION 'FAIL 5j: audit'; END IF;
    RAISE NOTICE 'ok 5 keep as credit: money stays received, credit appears, no double count';

    -- 6. Edit & repost: the corrected sale uses the credit and links back
    v_s3 := spwatersale_createv2(v_farm, v_cust2, d2 + time '10:00', NULL, '__w458',
                jsonb_build_array(jsonb_build_object('WaterProductId', v_prod, 'Quantity', 8, 'UnitPrice', 5))::text);
    PERFORM spwatersale_linkcorrection(v_farm, v_s3, v_s2, '__w458');
    IF (SELECT correctssaleid FROM watersales WHERE watersaleid = v_s3) <> v_s2
       OR (SELECT correctionsaleid FROM watersalereversals WHERE salereversalid = v_rev) <> v_s3 THEN RAISE EXCEPTION 'FAIL 6a'; END IF;
    v_s4 := spwatersale_createv2(v_farm, v_cust, d2 + time '11:00', NULL, '__w458',
                jsonb_build_array(jsonb_build_object('WaterProductId', v_prod, 'Quantity', 2, 'UnitPrice', 5))::text);
    v_err := pg_temp.w458_refused(format('SELECT spwatersale_linkcorrection(%L, %s, %s)', v_farm, v_s4, v_s2));
    IF v_err IS NULL OR v_err NOT LIKE '%already corrected%' THEN RAISE EXCEPTION 'FAIL 6b: %', v_err; END IF;
    PERFORM spwatercustomercredit_apply(v_farm, v_cust, v_s4, 10, '__w458');
    IF (SELECT amountpaid FROM watersales WHERE watersaleid = v_s4) <> 10 OR fnwatercustomer_credit(v_farm, v_cust) <> 30 THEN
        RAISE EXCEPTION 'FAIL 6c: credit apply';
    END IF;
    RAISE NOTICE 'ok 6 edit & repost link + kept credit pays a new sale';

    -- 7. reversing a sale paid by credit gives the credit back
    PERFORM set_config('water.sale_fresh', '', true);
    v_prev := spwatersale_reversalpreview(v_farm, v_s4);
    IF (v_prev->>'creditApplied')::numeric <> 10 OR jsonb_array_length(v_prev->'payments') <> 0 THEN RAISE EXCEPTION 'FAIL 7a: %', v_prev; END IF;
    PERFORM spwatersale_reverse(v_farm, v_s4, 'Entered by mistake', NULL, '{}'::jsonb, NULL, NULL, '__w458');
    IF fnwatercustomer_credit(v_farm, v_cust) <> 40 THEN RAISE EXCEPTION 'FAIL 7b: credit %', fnwatercustomer_credit(v_farm, v_cust); END IF;
    RAISE NOTICE 'ok 7 applied credit returns to the customer';

    -- 8. walk-in: money can only be reversed
    v_s5 := spwatersale_createv2(v_farm, NULL, d2 + time '12:00', NULL, '__w458',
                jsonb_build_array(jsonb_build_object('WaterProductId', v_prod, 'Quantity', 1, 'UnitPrice', 5))::text);
    v_pid := spwaterpayment_record(v_farm, v_s5, 5, 'Cash', d2 + time '12:00', NULL, NULL, '__w458');
    SELECT paymentgroupid INTO v_grp FROM waterpayments WHERE waterpaymentid = v_pid;
    PERFORM set_config('water.sale_fresh', '', true);
    v_prev := spwatersale_reversalpreview(v_farm, v_s5);
    IF (v_prev->'payments'->0->>'default') <> 'ReversePayment' OR (v_prev->'payments'->0->'allowed') ? 'KeepAsCredit' THEN RAISE EXCEPTION 'FAIL 8a'; END IF;
    v_err := pg_temp.w458_refused(format('SELECT spwatersale_reverse(%L, %s, %L, NULL, %L::jsonb)', v_farm, v_s5, 'Other',
                                         jsonb_build_object(v_grp::text, 'KeepAsCredit')::text));
    IF v_err IS NULL OR v_err NOT LIKE '%few words%' THEN RAISE EXCEPTION 'FAIL 8b: Other without a note: %', v_err; END IF;
    v_err := pg_temp.w458_refused(format('SELECT spwatersale_reverse(%L, %s, %L, NULL, %L::jsonb)', v_farm, v_s5, 'Wrong price',
                                         jsonb_build_object(v_grp::text, 'KeepAsCredit')::text));
    IF v_err IS NULL OR v_err NOT LIKE '%no customer%' THEN RAISE EXCEPTION 'FAIL 8c: %', v_err; END IF;
    PERFORM spwatersale_reverse(v_farm, v_s5, 'Wrong price', NULL, '{}'::jsonb, NULL, NULL, '__w458');
    IF (SELECT status FROM waterpayments WHERE waterpaymentid = v_pid) <> 'Reversed' THEN RAISE EXCEPTION 'FAIL 8d'; END IF;
    RAISE NOTICE 'ok 8 walk-in: reverse only';

    -- 9. a Customer Balances payment over two sales is never reversed by one of them
    v_s6 := spwatersale_createv2(v_farm, v_cust2, d2 + time '13:00', NULL, '__w458',
                jsonb_build_array(jsonb_build_object('WaterProductId', v_prod, 'Quantity', 2, 'UnitPrice', 5))::text);
    v_s7 := spwatersale_createv2(v_farm, v_cust2, d2 + time '13:30', NULL, '__w458',
                jsonb_build_array(jsonb_build_object('WaterProductId', v_prod, 'Quantity', 2, 'UnitPrice', 5))::text);
    PERFORM set_config('water.sale_fresh', '', true);
    v_grp := spwatercustomerpayment_record(v_farm, v_cust2, 20,
                 jsonb_build_array(jsonb_build_object('saleid', v_s6, 'amount', 10), jsonb_build_object('saleid', v_s7, 'amount', 10)),
                 'Cash', d2 + time '14:00', NULL, NULL, NULL, 'CustomerBalances', '__w458');
    v_prev := spwatersale_reversalpreview(v_farm, v_s6);
    IF (v_prev->'payments'->0->'allowed') ? 'ReversePayment' THEN RAISE EXCEPTION 'FAIL 9a: %', v_prev->'payments'; END IF;
    v_err := pg_temp.w458_refused(format('SELECT spwatersale_reverse(%L, %s, %L, NULL, %L::jsonb)', v_farm, v_s6, 'Wrong price',
                                         jsonb_build_object(v_grp::text, 'ReversePayment')::text));
    IF v_err IS NULL THEN RAISE EXCEPTION 'FAIL 9b: a shared payment was reversed'; END IF;
    PERFORM spwatersale_reverse(v_farm, v_s6, 'Wrong price', NULL, '{}'::jsonb, NULL, NULL, '__w458');
    IF (SELECT amountpaid FROM watersales WHERE watersaleid = v_s7) <> 10 THEN RAISE EXCEPTION 'FAIL 9c: other sale touched'; END IF;
    IF fnwatercustomer_credit(v_farm, v_cust2) <> 10 THEN RAISE EXCEPTION 'FAIL 9d: credit %', fnwatercustomer_credit(v_farm, v_cust2); END IF;
    RAISE NOTICE 'ok 9 shared payment: kept as credit, other sale untouched';

    -- 10. a delivery sale belongs to its driver return; reversing the return reverses its payments
    SELECT l.watervehicleloadingid INTO v_loading FROM watervehicleloadings l ORDER BY l.watervehicleloadingid LIMIT 1;
    INSERT INTO waterdriverreturns (farmid, watervehicleloadingid, bagssold, bagsreturned, status)
    VALUES (v_farm, COALESCE(v_loading, 0), 0, 0, 'Approved') RETURNING waterdriverreturnid INTO v_dr;
    INSERT INTO watersales (farmid, watercustomerid, saledate, totalamount, amountpaid, status, sourcetype, sourceid)
    VALUES (v_farm, v_cust, d2 + time '15:00', 30, 30, 'Paid', 'DeliveryRun', v_dr) RETURNING watersaleid INTO v_dsale;
    INSERT INTO waterpayments (farmid, watersaleid, amount, paymentmethod, paymentdate, reference, createdby,
                               watercustomerid, sourcetype, sourceid, paymentgroupid)
    VALUES (v_farm, v_dsale, 30, 'Cash', d2 + time '15:00', 'DR#' || v_dr, '__w458', v_cust, 'DeliveryRun', v_dr, gen_random_uuid())
    RETURNING waterpaymentid INTO v_pid;
    INSERT INTO customerpaymentallocation (farmid, module, paymentid, saleid, amountapplied, salebalancebefore, salebalanceafter, status, createdby, createdat)
    VALUES (v_farm, 'water', v_pid, v_dsale, 30, 30, 0, 'Posted', '__w458', d2 + time '15:00');
    PERFORM set_config('water.sale_fresh', '', true);
    v_prev := spwatersale_reversalpreview(v_farm, v_dsale);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_prev->'blockers') b WHERE b->>'code' = 'GeneratedSale') THEN RAISE EXCEPTION 'FAIL 10a'; END IF;
    PERFORM spwaterdriverreturn_reverse(v_dr, v_farm, '__w458', 'test');
    IF (SELECT status FROM waterpayments WHERE waterpaymentid = v_pid) <> 'Reversed' THEN RAISE EXCEPTION 'FAIL 10b: delivery payment still Posted'; END IF;
    IF EXISTS (SELECT 1 FROM customerpaymentallocation WHERE module = 'water' AND paymentid = v_pid AND status = 'Posted') THEN RAISE EXCEPTION 'FAIL 10c'; END IF;
    SELECT COALESCE(SUM(r.amount), 0) INTO v_n FROM spwatercashflow_rows(v_farm, NULL, NULL) r
    WHERE r.rowsource IN ('Receipt', 'ReceiptReversal') AND r.sourcerowid = v_pid;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 10d: delivery money still on Cash Flow (%)', v_n; END IF;
    RAISE NOTICE 'ok 10 delivery sale: blocked here, reversed with its driver return';

    RAISE NOTICE 'water 458: all checks passed';
END
$t$;

ROLLBACK;
