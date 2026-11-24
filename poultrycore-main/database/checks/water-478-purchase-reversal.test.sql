-- =============================================================================
-- Checks for 478 (Water purchase reversal). SELF-ROLLING-BACK, fixtures in a
-- real Water company, purchases dated 2001. Prints 'water 478: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.w478_refused(p_sql text) RETURNS text LANGUAGE plpgsql AS $r$
BEGIN
    EXECUTE p_sql;
    RETURN NULL;
EXCEPTION WHEN OTHERS THEN
    RETURN SQLERRM;
END $r$;

DO $t$
DECLARE
    v_farm text; v_sup integer; v_acct integer; v_item integer;
    v_p1 integer; v_p2 integer; v_p3 integer; v_p4 integer; v_p5 integer; v_p6 integer;
    v_st jsonb; v_r integer; v_r2 integer; v_err text; v_n numeric; v_bal numeric; v_cred numeric;
    v_pay integer; v_credpid integer; v_exp integer;
    d1 timestamp := TIMESTAMP '2001-07-10 09:00';
BEGIN
    SELECT a.farmid INTO v_farm FROM watercashaccounts a
    WHERE lower(COALESCE(spfarm_gettype(a.farmid), '')) = 'water' ORDER BY a.watercashaccountid LIMIT 1;
    INSERT INTO watersuppliers (farmid, suppliername, isactive, isdeleted) VALUES (v_farm, '__w478_supplier', TRUE, FALSE)
    RETURNING watersupplierid INTO v_sup;
    INSERT INTO watercashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, allownegativebalance, isactive)
    VALUES (v_farm, '__w478_account', 'Cash', 10000, 10000, FALSE, TRUE) RETURNING watercashaccountid INTO v_acct;
    INSERT INTO waterrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive)
    VALUES (v_farm, '__w478_film', 'Packaging', 'roll', 0, TRUE) RETURNING waterrawmaterialitemid INTO v_item;

    -- 1. paid at entry (cash), refunded: stock out, cash back, P&L clear, Cash Flow refund
    v_p1 := spwaterrawmaterialpurchase_insert(p_farmid => v_farm, p_waterrawmaterialitemid => v_item,
              p_suppliername => '__w478_supplier', p_purchasedate => d1, p_quantity => 10, p_unitcost => 10,
              p_paymentmethod => 'Cash', p_amountpaid => 100, p_receipturl => NULL, p_receivedbystaffid => NULL,
              p_notes => NULL, p_createdby => '__w478', p_supplierid => v_sup, p_totalcost => 100,
              p_watercashaccountid => v_acct, p_productionunit => NULL, p_productionunitsperpurchaseunit => 1);
    SELECT linkedwaterexpenseid INTO v_exp FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_p1;
    v_st := spwaterpurchase_reversalpreview(v_farm, v_p1);
    IF jsonb_array_length(v_st->'blockers') <> 0 OR jsonb_array_length(v_st->'payments') <> 1
       OR v_st->'payments'->0->>'key' <> 'entry' OR (v_st->'payments'->0->>'allocated')::numeric <> 100 THEN
        RAISE EXCEPTION 'FAIL 1a: preview %', v_st;
    END IF;
    IF v_exp IS NOT NULL AND (v_st->'payments'->0->>'cashAccountId')::int IS DISTINCT FROM v_acct THEN
        RAISE EXCEPTION 'FAIL 1b: refund account %', v_st->'payments'->0->>'cashAccountId';
    END IF;
    SELECT currentbalance INTO v_bal FROM watercashaccounts WHERE watercashaccountid = v_acct;
    v_r := spwaterpurchase_reverse(v_farm, v_p1, 'Wrong amount', NULL, '{"entry":"Refund"}'::jsonb,
                                   v_st->>'fingerprint', '__w478-k1', '__w478');
    IF (SELECT currentquantity FROM waterrawmaterialitems WHERE waterrawmaterialitemid = v_item) <> 0 THEN
        RAISE EXCEPTION 'FAIL 1c: stock not taken back out';
    END IF;
    IF v_exp IS NOT NULL AND (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> v_bal + 100 THEN
        RAISE EXCEPTION 'FAIL 1d: refund not in the account';
    END IF;
    IF (SELECT purchasereversalid FROM waterrawmaterialpurchases WHERE waterrawmaterialpurchaseid = v_p1) IS DISTINCT FROM v_r
       OR (SELECT reversalnumber FROM waterpurchasereversals WHERE purchasereversalid = v_r) NOT LIKE 'WPR-%' THEN
        RAISE EXCEPTION 'FAIL 1e: purchase not stamped';
    END IF;
    IF EXISTS (SELECT 1 FROM fnwaterpl_rawmaterialrows(v_farm, TIMESTAMP '2001-01-01', TIMESTAMP '2002-01-01')
               WHERE reference = 'Purchase #' || v_p1) THEN
        RAISE EXCEPTION 'FAIL 1f: reversed purchase still on the P&L';
    END IF;
    IF v_exp IS NOT NULL AND NOT EXISTS (SELECT 1 FROM spwatercashflow_rows(v_farm, NULL, NULL)
               WHERE rowsource = 'PurchaseReversalRefund' AND sourceid = v_r AND amount = 100) THEN
        RAISE EXCEPTION 'FAIL 1g: refund missing from Cash Flow';
    END IF;
    IF v_exp IS NOT NULL AND NOT EXISTS (SELECT 1 FROM spwatercashflow_rows(v_farm, NULL, NULL)
               WHERE rowsource = 'Expense' AND sourceid = v_exp AND amount = -100) THEN
        RAISE EXCEPTION 'FAIL 1h: the original payment vanished from Cash Flow';
    END IF;
    RAISE NOTICE 'ok 1 paid-at-entry purchase refunded: stock out, cash back in, P&L clear, Cash Flow keeps both';

    -- 2. idempotent: the same key returns the same reversal
    v_r2 := spwaterpurchase_reverse(v_farm, v_p1, 'Wrong amount', NULL, '{}'::jsonb, NULL, '__w478-k1', '__w478');
    IF v_r2 <> v_r THEN RAISE EXCEPTION 'FAIL 2: double click reversed twice'; END IF;
    RAISE NOTICE 'ok 2 idempotency key';

    -- 3. a reversed purchase is history
    v_err := pg_temp.w478_refused(format('UPDATE waterrawmaterialpurchases SET notes = %L WHERE waterrawmaterialpurchaseid = %s', 'x', v_p1));
    IF v_err IS NULL OR v_err NOT LIKE '%was reversed%' THEN RAISE EXCEPTION 'FAIL 3a: %', COALESCE(v_err, 'edit allowed'); END IF;
    v_err := pg_temp.w478_refused(format('SELECT spwaterrawmaterialpurchase_delete(%s, %L)', v_p1, v_farm));
    IF v_err IS NULL OR v_err NOT LIKE '%no longer be deleted%' THEN RAISE EXCEPTION 'FAIL 3b: %', COALESCE(v_err, 'delete allowed'); END IF;
    RAISE NOTICE 'ok 3 reversed purchase cannot be edited; delete refuses';

    -- 4. on credit, paid later by a supplier payment, kept as supplier credit
    v_p2 := spwaterrawmaterialpurchase_insert(p_farmid => v_farm, p_waterrawmaterialitemid => v_item,
              p_suppliername => '__w478_supplier', p_purchasedate => d1, p_quantity => 6, p_unitcost => 10,
              p_paymentmethod => 'Credit', p_amountpaid => 0, p_receipturl => NULL, p_receivedbystaffid => NULL,
              p_notes => NULL, p_createdby => '__w478', p_supplierid => v_sup, p_totalcost => 60,
              p_watercashaccountid => v_acct, p_productionunit => NULL, p_productionunitsperpurchaseunit => 1);
    v_pay := spwatersupplierpayment_record(p_farmid => v_farm, p_supplierid => v_sup, p_amount => 60,
              p_allocations => jsonb_build_array(jsonb_build_object('documenttype', 'RawMaterialPurchase', 'documentid', v_p2, 'amount', 60)),
              p_paymentmethod => 'Cash', p_paymentdate => d1, p_cashaccountid => v_acct, p_reference => NULL,
              p_note => NULL, p_sourcetype => 'PurchaseEntry', p_createdby => '__w478');
    v_cred := fnwatersupplier_credit(v_farm, v_sup);
    v_st := spwaterpurchase_reversalpreview(v_farm, v_p2);
    IF jsonb_array_length(v_st->'payments') <> 1 OR v_st->'payments'->0->>'source' <> 'SupplierPayment'
       OR v_st->'payments'->0->>'default' <> 'KeepAsCredit' THEN
        RAISE EXCEPTION 'FAIL 4a: preview %', v_st->'payments';
    END IF;
    v_r := spwaterpurchase_reverse(v_farm, v_p2, 'Posted by mistake', NULL, '{}'::jsonb, v_st->>'fingerprint', NULL, '__w478');
    IF fnwatersupplier_credit(v_farm, v_sup) <> v_cred + 60 THEN
        RAISE EXCEPTION 'FAIL 4b: credit % expected %', fnwatersupplier_credit(v_farm, v_sup), v_cred + 60;
    END IF;
    SELECT creditpaymentid INTO v_credpid FROM waterpurchasereversalpayments WHERE purchasereversalid = v_r;
    IF EXISTS (SELECT 1 FROM watercashtransactions WHERE sourcetype = 'WaterSupplierPayment' AND sourceid = v_credpid) THEN
        RAISE EXCEPTION 'FAIL 4c: keeping credit moved cash';
    END IF;
    IF EXISTS (SELECT 1 FROM fnwaterpl_rawmaterialrows(v_farm, TIMESTAMP '2001-01-01', TIMESTAMP '2002-01-01')
               WHERE reference = 'Purchase #' || v_p2) THEN
        RAISE EXCEPTION 'FAIL 4d: reversed purchase still on the P&L';
    END IF;
    RAISE NOTICE 'ok 4 supplier payment kept as supplier credit, no cash, off the P&L';

    -- 5. that payment and that credit cannot be undone behind the reversal's back
    v_err := pg_temp.w478_refused(format('SELECT spwatersupplierpayment_reverse(%L, %s, %L, %L)', v_farm, v_pay, 'x', 'x'));
    IF v_err IS NULL OR v_err NOT LIKE '%already settled%' THEN RAISE EXCEPTION 'FAIL 5a: %', COALESCE(v_err, 'payment reversed'); END IF;
    v_err := pg_temp.w478_refused(format('SELECT spwatersuppliercredit_reverse(%L, %s, %L, %L)', v_farm, v_credpid, 'x', 'x'));
    IF v_err IS NULL OR v_err NOT LIKE '%reversed purchase%' THEN RAISE EXCEPTION 'FAIL 5b: %', COALESCE(v_err, 'credit erased'); END IF;
    RAISE NOTICE 'ok 5 settled payment and kept credit are protected';

    -- 6. the kept credit, spent on a new purchase, IS a raw material cost
    v_p3 := spwaterrawmaterialpurchase_insert(p_farmid => v_farm, p_waterrawmaterialitemid => v_item,
              p_suppliername => '__w478_supplier', p_purchasedate => d1, p_quantity => 4, p_unitcost => 10,
              p_paymentmethod => 'Credit', p_amountpaid => 0, p_receipturl => NULL, p_receivedbystaffid => NULL,
              p_notes => NULL, p_createdby => '__w478', p_supplierid => v_sup, p_totalcost => 40,
              p_watercashaccountid => v_acct, p_productionunit => NULL, p_productionunitsperpurchaseunit => 1);
    PERFORM spwatersuppliercredit_apply(v_farm, v_credpid, 'RawMaterialPurchase', v_p3, 40, '__w478');
    IF COALESCE((SELECT SUM(amount) FROM fnwaterpl_rawmaterialrows(v_farm, TIMESTAMP '2000-01-01', now()::timestamp + interval '1 day')
                 WHERE reference = 'Purchase #' || v_p3 AND kind = 'CreditApplied'), 0) <> 40 THEN
        RAISE EXCEPTION 'FAIL 6: spent reversal credit not on the P&L';
    END IF;
    RAISE NOTICE 'ok 6 reversal credit spent later reaches the P&L';

    -- 6b. what is left of the kept credit can be refunded later (Supplier Credits)
    SELECT currentbalance INTO v_bal FROM watercashaccounts WHERE watercashaccountid = v_acct;
    PERFORM spwatersupplierrefund_record(v_farm, v_credpid, 20, v_acct, 'Cash', current_date, 'supplier paid back', '__w478');
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> v_bal + 20
       OR fnwatersupplierpayment_unapplied(v_farm, v_credpid) <> 0 THEN
        RAISE EXCEPTION 'FAIL 6b: refund of the kept credit';
    END IF;
    RAISE NOTICE 'ok 6b the rest of the kept credit refunded later';

    -- 7. reversing a purchase paid with credit gives the credit back
    v_cred := fnwatersupplier_credit(v_farm, v_sup);
    v_st := spwaterpurchase_reversalpreview(v_farm, v_p3);
    IF (v_st->>'creditApplied')::numeric <> 40 OR jsonb_array_length(v_st->'payments') <> 0 THEN
        RAISE EXCEPTION 'FAIL 7a: preview %', v_st;
    END IF;
    PERFORM spwaterpurchase_reverse(v_farm, v_p3, 'Duplicate entry', NULL, '{}'::jsonb, NULL, NULL, '__w478');
    IF fnwatersupplier_credit(v_farm, v_sup) <> v_cred + 40 THEN RAISE EXCEPTION 'FAIL 7b: credit not given back'; END IF;
    RAISE NOTICE 'ok 7 applied supplier credit goes back to the supplier';

    -- 8. no supplier: money can only be refunded
    v_p4 := spwaterrawmaterialpurchase_insert(p_farmid => v_farm, p_waterrawmaterialitemid => v_item,
              p_suppliername => 'market', p_purchasedate => d1, p_quantity => 2, p_unitcost => 10,
              p_paymentmethod => 'Cash', p_amountpaid => 20, p_receipturl => NULL, p_receivedbystaffid => NULL,
              p_notes => NULL, p_createdby => '__w478', p_supplierid => NULL, p_totalcost => 20,
              p_watercashaccountid => v_acct, p_productionunit => NULL, p_productionunitsperpurchaseunit => 1);
    v_err := pg_temp.w478_refused(format('SELECT spwaterpurchase_reverse(%L, %s, %L, NULL, %L::jsonb)',
                                         v_farm, v_p4, 'Wrong amount', '{"entry":"KeepAsCredit"}'));
    IF v_err IS NULL OR v_err NOT LIKE '%no supplier%' THEN RAISE EXCEPTION 'FAIL 8: %', COALESCE(v_err, 'credit kept without a supplier'); END IF;
    RAISE NOTICE 'ok 8 supplier-less purchase cannot keep credit';

    -- 9. reason rules and a stale preview
    v_err := pg_temp.w478_refused(format('SELECT spwaterpurchase_reverse(%L, %s, NULL, NULL)', v_farm, v_p4));
    IF v_err IS NULL OR v_err NOT LIKE 'Give a reason%' THEN RAISE EXCEPTION 'FAIL 9a: %', v_err; END IF;
    v_err := pg_temp.w478_refused(format('SELECT spwaterpurchase_reverse(%L, %s, %L, NULL)', v_farm, v_p4, 'Other'));
    IF v_err IS NULL OR v_err NOT LIKE '%"Other"%' THEN RAISE EXCEPTION 'FAIL 9b: %', v_err; END IF;
    v_err := pg_temp.w478_refused(format('SELECT spwaterpurchase_reverse(%L, %s, %L, NULL, %L::jsonb, %L)',
                                         v_farm, v_p4, 'Wrong amount', '{}', 'stale'));
    IF v_err IS NULL OR v_err NOT LIKE '%changed after the reversal preview%' THEN RAISE EXCEPTION 'FAIL 9c: %', v_err; END IF;
    RAISE NOTICE 'ok 9 reason rules and stale preview';

    -- 10. blocked while any of the lot has been used
    v_p5 := spwaterrawmaterialpurchase_insert(p_farmid => v_farm, p_waterrawmaterialitemid => v_item,
              p_suppliername => '__w478_supplier', p_purchasedate => d1, p_quantity => 5, p_unitcost => 10,
              p_paymentmethod => 'Credit', p_amountpaid => 0, p_receipturl => NULL, p_receivedbystaffid => NULL,
              p_notes => NULL, p_createdby => '__w478', p_supplierid => v_sup, p_totalcost => 50,
              p_watercashaccountid => v_acct, p_productionunit => NULL, p_productionunitsperpurchaseunit => 1);
    UPDATE waterrawmaterialpurchases SET remainingquantity = 3 WHERE waterrawmaterialpurchaseid = v_p5;
    v_st := spwaterpurchase_reversalpreview(v_farm, v_p5);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_st->'blockers') b WHERE b->>'code' = 'Consumed') THEN
        RAISE EXCEPTION 'FAIL 10a: no Consumed blocker %', v_st->'blockers';
    END IF;
    v_err := pg_temp.w478_refused(format('SELECT spwaterpurchase_reverse(%L, %s, %L, NULL)', v_farm, v_p5, 'Wrong amount'));
    IF v_err IS NULL OR v_err NOT LIKE '%already been used%' THEN RAISE EXCEPTION 'FAIL 10b: %', COALESCE(v_err, 'used lot reversed'); END IF;
    RAISE NOTICE 'ok 10 a used lot cannot be reversed';

    RAISE NOTICE 'water 478: all checks passed';
END
$t$;

ROLLBACK;
