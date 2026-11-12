-- =============================================================================
-- Checks for 422 (Water customer credit, W1).  SELF-ROLLING-BACK, fixtures in a
-- real Water company, dated 2001 (credit refuses future dates).  Prints 'water W1: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $t$
DECLARE
    v_farm text; v_cust integer; v_acct integer;
    v_s1 integer; v_s2 integer; v_s3 integer;
    v_grp uuid; v_dep jsonb; v_on jsonb; v_cn jsonb;
    v_ref integer; v_n numeric; v_m numeric; v_bal0 numeric; v_lt record; v_pl record;
    d1 date := DATE '2001-02-10';
    d2 date := DATE '2001-02-11';
BEGIN
    SELECT a.farmid INTO v_farm FROM watercashaccounts a ORDER BY a.watercashaccountid LIMIT 1;
    INSERT INTO watercustomers (farmid, name) VALUES (v_farm, '__w1_customer') RETURNING watercustomerid INTO v_cust;
    INSERT INTO watercashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, isactive)
    VALUES (v_farm, '__w1_account', 'Cash', 1000, 1000, TRUE) RETURNING watercashaccountid INTO v_acct;
    INSERT INTO watersales (farmid, watercustomerid, saledate, totalamount, amountpaid, status)
    VALUES (v_farm, v_cust, d1 + time '09:00', 100, 0, 'Pending') RETURNING watersaleid INTO v_s1;
    INSERT INTO watersales (farmid, watercustomerid, saledate, totalamount, amountpaid, status)
    VALUES (v_farm, v_cust, d1 + time '10:00', 80, 0, 'Pending') RETURNING watersaleid INTO v_s2;

    -- 1. a payment bigger than its sale leaves credit
    v_grp := spwatercustomerpayment_record(v_farm, v_cust, 130,
                 jsonb_build_array(jsonb_build_object('saleid', v_s1, 'amount', 100)),
                 'Cash', d2 + time '09:00', NULL, NULL, NULL, 'CustomerBalances', '__w1');
    IF (SELECT amountpaid FROM watersales WHERE watersaleid = v_s1) <> 100 THEN RAISE EXCEPTION 'FAIL 1a'; END IF;
    IF fnwatercustomer_credit(v_farm, v_cust) <> 30 THEN RAISE EXCEPTION 'FAIL 1b: credit %', fnwatercustomer_credit(v_farm, v_cust); END IF;
    RAISE NOTICE 'ok 1 payment remainder becomes credit';

    -- 2. advance = money into the account now, not a closing collection
    v_dep := spwatercustomercredit_create(v_farm, v_cust, 'Deposit', 50, d2 + time '10:00', v_acct, 'Cash', NULL, 'advance', '__w1');
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 1050 THEN RAISE EXCEPTION 'FAIL 2a'; END IF;
    SELECT * INTO v_lt FROM fnwaterdailyclosing_livetotals(v_farm, d2);
    -- collections on d2 = the 130 payment only (sale s1 was made on d1), never the advance
    SELECT COALESCE(SUM(p.amount), 0) INTO v_n FROM waterpayments p
    WHERE p.farmid = v_farm AND p.createdby <> '__w1' AND COALESCE(p.status,'Posted') = 'Posted'
      AND COALESCE(p.sourcetype,'') <> 'DeliveryRun' AND p.paymentdate >= d2 AND p.paymentdate < d2 + 1;
    IF v_lt.customercollections <> 130 + v_n THEN RAISE EXCEPTION 'FAIL 2b: collections %', v_lt.customercollections; END IF;
    RAISE NOTICE 'ok 2 advance posts cash and is not a closing collection';

    -- 3. opening credit and a credit note: no money; credit note is negative revenue
    v_on := spwatercustomercredit_create(v_farm, v_cust, 'OpeningCredit', 20, d2 + time '11:00', NULL, NULL, NULL, 'opening', '__w1');
    SELECT totalincome INTO v_bal0 FROM spwaterreport_periodpnl(v_farm, d2, d2);
    v_cn := spwatercustomercredit_create(v_farm, v_cust, 'CreditNote', 10, d2 + time '12:00', NULL, NULL, NULL, 'damaged bags', '__w1');
    SELECT totalincome INTO v_n FROM spwaterreport_periodpnl(v_farm, d2, d2);
    IF v_n <> v_bal0 - 10 THEN RAISE EXCEPTION 'FAIL 3a: credit note not negative revenue (% -> %)', v_bal0, v_n; END IF;
    SELECT COALESCE(SUM(l.amount), 0) INTO v_m FROM spwaterreport_pllines(v_farm, d2, d2) l WHERE l.section = 'Revenue';
    IF v_m <> v_n THEN RAISE EXCEPTION 'FAIL 3b: P&L lines revenue % <> periodpnl %', v_m, v_n; END IF;
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 1050 THEN RAISE EXCEPTION 'FAIL 3c'; END IF;
    IF EXISTS (SELECT 1 FROM spwatercashflow_rows(v_farm, NULL, NULL) r
               WHERE r.rowsource = 'Receipt' AND r.sourcerowid IN ((v_on->>'waterPaymentId')::int, (v_cn->>'waterPaymentId')::int)) THEN
        RAISE EXCEPTION 'FAIL 3d: no-cash credit is a Cash Flow receipt';
    END IF;
    IF fnwatercustomer_credit(v_farm, v_cust) <> 110 THEN RAISE EXCEPTION 'FAIL 3e: credit %', fnwatercustomer_credit(v_farm, v_cust); END IF;
    RAISE NOTICE 'ok 3 opening credit / credit note: no cash, credit note on the P&L';

    -- 4. apply credit to sale 2: paid, but no till money in Cash Flow
    PERFORM spwatercustomercredit_apply(v_farm, v_cust, v_s2, 80, '__w1');
    IF (SELECT amountpaid FROM watersales WHERE watersaleid = v_s2) <> 80 THEN RAISE EXCEPTION 'FAIL 4a'; END IF;
    IF fnwatercustomer_credit(v_farm, v_cust) <> 30 THEN RAISE EXCEPTION 'FAIL 4b'; END IF;
    IF EXISTS (SELECT 1 FROM spwatercashflow_rows(v_farm, NULL, NULL) r WHERE r.rowsource = 'SaleResidual' AND r.sourceid = v_s2) THEN
        RAISE EXCEPTION 'FAIL 4c: applied credit read as money at the till';
    END IF;
    -- statement still ends at 0 owed: 180 of sales, 100 paid, 80 credit applied
    SELECT runningbalance INTO v_n FROM spwatercustomerstatement(v_farm, v_cust) ORDER BY sortkey DESC, entrydate DESC NULLS LAST LIMIT 1;
    IF (SELECT SUM(debit) - SUM(credit) FROM spwatercustomerstatement(v_farm, v_cust)) <> 0 THEN
        RAISE EXCEPTION 'FAIL 4e: statement does not net to 0';
    END IF;
    RAISE NOTICE 'ok 4 applied credit pays the sale, never cash';

    -- 5. refund a CHOSEN credit (the opening credit; the advance is all used)
    --    - money out; reversal puts it back
    v_ref := spwatercustomerrefund_record(v_farm, v_cust, 20, v_acct, 'Cash', d2, 'customer asked', '__w1',
                                          (v_on->>'waterPaymentId')::int);
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 1030 THEN RAISE EXCEPTION 'FAIL 5a'; END IF;
    IF fnwatercustomer_credit(v_farm, v_cust) <> 10 THEN RAISE EXCEPTION 'FAIL 5b'; END IF;
    v_n := 0;
    BEGIN
        PERFORM spwatercustomercredit_reverse(v_farm, (v_on->>'paymentGroupId')::uuid, 'test', '__w1');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN v_n := 1;
    END;
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 5c: refunded credit was reversed'; END IF;
    PERFORM spwatercustomerrefund_reverse(v_farm, v_ref, 'mistake', '__w1');
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 1050 THEN RAISE EXCEPTION 'FAIL 5d'; END IF;
    IF fnwatercustomer_credit(v_farm, v_cust) <> 30 THEN RAISE EXCEPTION 'FAIL 5e'; END IF;
    SELECT COALESCE(SUM(r.amount), 0) INTO v_n FROM spwatercashflow_rows(v_farm, NULL, NULL) r
    WHERE r.rowsource IN ('CustomerRefund', 'CustomerRefundReversal') AND r.sourceid = v_ref;
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 5f: refund + reversal in Cash Flow net %', v_n; END IF;
    RAISE NOTICE 'ok 5 refund chosen credit; reversal restores cash and credit';

    -- 6. reversing the advance releases what it paid; the sale is owed again
    -- (the 80 on sale 2 came from the oldest credits first: overpayment 30, advance 50)
    PERFORM spwatercustomercredit_reverse(v_farm, (v_dep->>'paymentGroupId')::uuid, 'test', '__w1');
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 1000 THEN RAISE EXCEPTION 'FAIL 6a'; END IF;
    SELECT amountpaid INTO v_n FROM watersales WHERE watersaleid = v_s2;
    IF v_n <> 30 THEN RAISE EXCEPTION 'FAIL 6b: sale 2 paid % after the advance was reversed', v_n; END IF;
    RAISE NOTICE 'ok 6 reversing an advance gives its cash back and re-opens what it paid';

    -- 7. cancelling a sale gives its applied credit back
    PERFORM spwatersale_cancel(v_s2, v_farm);
    IF fnwatercustomer_credit(v_farm, v_cust) <> 60 THEN RAISE EXCEPTION 'FAIL 7: credit % after cancel', fnwatercustomer_credit(v_farm, v_cust); END IF;
    RAISE NOTICE 'ok 7 cancelled sale releases credit';

    -- 8. history lists the payment once at its full amount; hand-made credit stays off it
    INSERT INTO watersales (farmid, watercustomerid, saledate, totalamount, amountpaid, status)
    VALUES (v_farm, v_cust, d1 + time '11:00', 25, 0, 'Pending') RETURNING watersaleid INTO v_s3;
    PERFORM spwatercustomercredit_apply(v_farm, v_cust, v_s3, 25, '__w1');
    IF (SELECT totalamount FROM spwatercustomerpayment_history(v_farm, v_cust) h WHERE h.paymentgroupid = v_grp) <> 130 THEN
        RAISE EXCEPTION 'FAIL 8a: history multiplied the payment';
    END IF;
    IF EXISTS (SELECT 1 FROM spwatercustomerpayment_history(v_farm, v_cust) h
               WHERE h.paymentgroupid IN ((v_on->>'paymentGroupId')::uuid, (v_cn->>'paymentGroupId')::uuid)) THEN
        RAISE EXCEPTION 'FAIL 8b: hand-made credit in payment history';
    END IF;
    RAISE NOTICE 'ok 8 payment history';

    -- 9. a payment whose left-over credit was refunded cannot be reversed
    v_ref := spwatercustomerrefund_record(v_farm, v_cust, 5, v_acct, 'Cash', d2, 'r', '__w1', NULL);
    BEGIN
        PERFORM spwatercustomerpayment_reverse(v_farm, v_grp, 'x', '__w1');
        IF EXISTS (SELECT 1 FROM watercustomerrefundlines rl JOIN waterpayments p ON p.waterpaymentid = rl.waterpaymentid
                   WHERE rl.refundid = v_ref AND p.paymentgroupid = v_grp) THEN
            RAISE EXCEPTION 'FAIL 9: refunded payment was reversed';
        END IF;
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
    END;
    RAISE NOTICE 'ok 9 refunded payment cannot be reversed';

    RAISE NOTICE 'water W1: all checks passed';
END
$t$;

ROLLBACK;
