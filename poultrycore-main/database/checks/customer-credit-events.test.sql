-- =============================================================================
-- customer-credit-events.test.sql -- checks for migration 367.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f), and the apply
-- script also runs it inside its own rolled-back dry run. Works on a throwaway
-- customer in the first poultry company that has a cash account.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm    text;
    v_user    text;
    v_acct    integer;
    v_cust    integer;
    v_sale    integer;
    v_sale2   integer;
    v_grp     uuid;
    v_adv     uuid;
    v_pid     integer;
    v_refund  integer;
    v_bal0    numeric;
    v_bal     numeric;
    v_n       integer;
    v_failed  boolean;
    v_ev      record;
BEGIN
    SELECT a.farmid, a.poultrycashaccountid INTO v_farm, v_acct
    FROM   poultrycashaccounts a
    JOIN   farms f ON (f.id::text = a.farmid OR f.farmid::text = a.farmid) AND f.type = 'Poultry'
    WHERE  a.isactive
    ORDER  BY a.poultrycashaccountid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'customer credit events: no poultry company with a cash account -- skipped';
        RAISE NOTICE 'customer credit events: all checks passed';
        RETURN;
    END IF;
    SELECT f.owneruserid INTO v_user FROM farms f WHERE f.id::text = v_farm OR f.farmid::text = v_farm LIMIT 1;
    INSERT INTO customer (farmid, userid, name) VALUES (v_farm, COALESCE(v_user, '0'), 'Credit Check 367')
    RETURNING customerid INTO v_cust;

    -- An owed sale of 600.
    SELECT (sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => now()::timestamp,
              p_customername => NULL, p_customerid => v_cust, p_paymentmethod => NULL,
              p_cashaccountid => v_acct, p_paid => false, p_description => 'credit check 367', p_flockid => NULL,
              p_linesjson => '[{"product":"Manure","eggProductId":null,"quantity":1,"unitPrice":600,"totalAmount":600}]',
              p_requestkey => 'check-367-' || gen_random_uuid()::text)::jsonb->>'saleId')::integer INTO v_sale;

    -- 1. A payment of 1,000 applied 600: sale paid, 400 kept as credit, ONE CashIn of 1,000.
    SELECT currentbalance INTO v_bal0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_grp := sppoultrycustomerpayment_record(v_farm, v_cust, 1000,
                 jsonb_build_array(jsonb_build_object('saleid', v_sale, 'amount', 600)),
                 'Cash', now()::timestamp, v_acct, 'CHK-367', NULL, 'PaymentsPage', v_user);
    IF (SELECT fnpoultrysalebalance(paid, totalamount, amountpaid) FROM sale WHERE saleid = v_sale) <> 0 THEN
        RAISE EXCEPTION 'FAIL 1a: sale not paid'; END IF;
    IF fnpoultrycustomer_credit(v_farm, v_cust) <> 400 THEN
        RAISE EXCEPTION 'FAIL 1b: remainder not kept as credit (%)', fnpoultrycustomer_credit(v_farm, v_cust); END IF;
    SELECT count(*), COALESCE(sum(ct.amount), 0) INTO v_n, v_bal FROM poultrycashtransactions ct
    WHERE  ct.paymentgroupid = v_grp AND ct.transactiontype = 'CashIn';
    IF v_n <> 1 OR v_bal <> 1000 THEN RAISE EXCEPTION 'FAIL 1c: cash in % rows / % (want 1 / 1000)', v_n, v_bal; END IF;
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal0 + 1000 THEN
        RAISE EXCEPTION 'FAIL 1d: account did not go up by 1000'; END IF;
    RAISE NOTICE 'ok 1 payment above what is owed: rest is credit, cash in once';

    -- 2. A payment with no sale is an advance; with no account it is refused.
    v_failed := FALSE;
    BEGIN PERFORM sppoultrycustomerpayment_record(v_farm, v_cust, 50, '[]'::jsonb, 'Cash', now()::timestamp, NULL, NULL, NULL, 'PaymentsPage', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2a: an advance with no account was accepted'; END IF;
    v_adv := sppoultrycustomerpayment_record(v_farm, v_cust, 500, '[]'::jsonb, 'Cash', now()::timestamp, v_acct, NULL, 'advance', 'PaymentsPage', v_user);
    IF fnpoultrycustomer_credit(v_farm, v_cust) <> 900 THEN RAISE EXCEPTION 'FAIL 2b: advance not credit'; END IF;
    IF NOT EXISTS (SELECT 1 FROM poultrycashtransactions ct WHERE ct.paymentgroupid = v_adv
                   AND ct.amount = 500 AND ct.description LIKE 'Customer advance%') THEN
        RAISE EXCEPTION 'FAIL 2c: advance cash missing or not labelled Customer advance'; END IF;
    RAISE NOTICE 'ok 2 payment with no sale is an advance (cash in, credit)';

    -- 3. Credit events: two, with the right source and figures; totals agree.
    SELECT count(*) INTO v_n FROM sppoultrycustomercredit_events(v_farm, v_cust);
    IF v_n <> 2 THEN RAISE EXCEPTION 'FAIL 3a: % credit events (want 2)', v_n; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycustomercredit_events(v_farm, v_cust) e
                   WHERE e.source = 'Unapplied part of payment' AND e.originalamount = 400 AND e.available = 400 AND NOT e.ismanual)
       OR NOT EXISTS (SELECT 1 FROM sppoultrycustomercredit_events(v_farm, v_cust) e
                   WHERE e.source = 'Customer advance' AND e.originalamount = 500 AND e.ismanual) THEN
        RAISE EXCEPTION 'FAIL 3b: event sources / amounts wrong'; END IF;
    IF (SELECT sum(available) FROM sppoultrycustomercredit_events(v_farm, v_cust)) <> fnpoultrycustomer_credit(v_farm, v_cust) THEN
        RAISE EXCEPTION 'FAIL 3c: events do not add up to the credit held'; END IF;
    RAISE NOTICE 'ok 3 credit events listed one by one and add up';

    -- 4. Refund a CHOSEN credit, partly: only that event goes down; cash out.
    SELECT e.poultrypaymentid INTO v_pid FROM sppoultrycustomercredit_events(v_farm, v_cust) e WHERE e.source = 'Customer advance';
    SELECT currentbalance INTO v_bal0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrycustomerrefund_record(v_farm, v_cust, 600, v_acct, 'Cash', NULL, 'too much', v_user, v_pid);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4a: refund above the chosen credit accepted'; END IF;
    v_refund := sppoultrycustomerrefund_record(v_farm, v_cust, 200, v_acct, 'Cash', NULL, 'part back', v_user, v_pid);
    SELECT * INTO v_ev FROM sppoultrycustomercredit_events(v_farm, v_cust) e WHERE e.poultrypaymentid = v_pid;
    IF v_ev.refunded <> 200 OR v_ev.available <> 300 OR v_ev.status <> 'Partly used' THEN
        RAISE EXCEPTION 'FAIL 4b: chosen credit after refund: refunded % available % status %', v_ev.refunded, v_ev.available, v_ev.status; END IF;
    IF EXISTS (SELECT 1 FROM sppoultrycustomercredit_events(v_farm, v_cust) e
               WHERE e.source = 'Unapplied part of payment' AND e.available <> 400) THEN
        RAISE EXCEPTION 'FAIL 4c: the other credit was touched'; END IF;
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal0 - 200 THEN
        RAISE EXCEPTION 'FAIL 4d: account did not go down by 200'; END IF;
    RAISE NOTICE 'ok 4 refund out of one chosen credit, partly';

    -- 5. Reverse the refund: credit back, money back to the SAME account, Cash Flow both ways.
    v_failed := FALSE;
    BEGIN PERFORM sppoultrycustomerrefund_reverse(v_farm, v_refund, '  ', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5a: reversal without a reason accepted'; END IF;
    PERFORM sppoultrycustomerrefund_reverse(v_farm, v_refund, 'entered by mistake', v_user);
    IF (SELECT available FROM sppoultrycustomercredit_events(v_farm, v_cust) e WHERE e.poultrypaymentid = v_pid) <> 500 THEN
        RAISE EXCEPTION 'FAIL 5b: credit not restored'; END IF;
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal0 THEN
        RAISE EXCEPTION 'FAIL 5c: account not restored'; END IF;
    IF (SELECT status FROM poultrycustomerrefunds WHERE refundid = v_refund) <> 'Reversed' THEN
        RAISE EXCEPTION 'FAIL 5d: refund not marked Reversed'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycashflow_rows(v_farm, (CURRENT_DATE - 1)::timestamp, (CURRENT_DATE + 2)::timestamp) r
                   WHERE r.rowsource = 'CustomerRefund' AND r.sourceid = v_refund AND r.amount = -200)
       OR NOT EXISTS (SELECT 1 FROM sppoultrycashflow_rows(v_farm, (CURRENT_DATE - 1)::timestamp, (CURRENT_DATE + 2)::timestamp) r
                   WHERE r.rowsource = 'CustomerRefundReversal' AND r.sourceid = v_refund AND r.amount = 200) THEN
        RAISE EXCEPTION 'FAIL 5e: Cash Flow does not show the refund and its reversal'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycustomerstatement(v_farm, v_cust) s WHERE s.entrytype = 'RefundReversal' AND s.credit = 200) THEN
        RAISE EXCEPTION 'FAIL 5f: statement has no refund reversal line'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrycustomerrefund_reverse(v_farm, v_refund, 'again', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5g: a refund reversed twice'; END IF;
    RAISE NOTICE 'ok 5 refund reversal: credit and cash restored once, history kept';

    -- 6. The unapplied part of a payment is reversed with its payment, not as a manual credit.
    v_failed := FALSE;
    BEGIN PERFORM sppoultrycustomercredit_reverse(v_farm, v_grp, 'x', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6a: unapplied part reversed as a manual credit'; END IF;
    IF EXISTS (SELECT 1 FROM sppoultrycustomercredit_manuallist(v_farm) m WHERE m.paymentgroupid = v_grp) THEN
        RAISE EXCEPTION 'FAIL 6b: unapplied part listed as added by hand'; END IF;
    PERFORM sppoultrycustomerpayment_reverse(v_farm, v_grp, 'check', v_user);
    IF (SELECT fnpoultrysalebalance(paid, totalamount, amountpaid) FROM sale WHERE saleid = v_sale) <> 600 THEN
        RAISE EXCEPTION 'FAIL 6c: payment reversal did not reopen the sale'; END IF;
    IF fnpoultrycustomer_credit(v_farm, v_cust) <> 500 THEN
        RAISE EXCEPTION 'FAIL 6d: credit after payment reversal % (want 500)', fnpoultrycustomer_credit(v_farm, v_cust); END IF;
    SELECT COALESCE(sum(ct.amount), 0) INTO v_bal FROM poultrycashtransactions ct WHERE ct.paymentgroupid = v_grp;
    IF v_bal <> 0 THEN RAISE EXCEPTION 'FAIL 6e: reversed payment still nets % in cash', v_bal; END IF;
    RAISE NOTICE 'ok 6 a payment with a remainder reverses as one payment';

    -- 7. An ordinary fully-applied payment is unchanged: no credit event.
    SELECT (sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => now()::timestamp,
              p_customername => NULL, p_customerid => v_cust, p_paymentmethod => NULL,
              p_cashaccountid => v_acct, p_paid => false, p_description => 'credit check 367 b', p_flockid => NULL,
              p_linesjson => '[{"product":"Manure","eggProductId":null,"quantity":1,"unitPrice":100,"totalAmount":100}]',
              p_requestkey => 'check-367b-' || gen_random_uuid()::text)::jsonb->>'saleId')::integer INTO v_sale2;
    PERFORM sppoultrycustomerpayment_record(v_farm, v_cust, 100,
                jsonb_build_array(jsonb_build_object('saleid', v_sale2, 'amount', 100)),
                'Cash', now()::timestamp, v_acct, NULL, NULL, 'CustomerBalances', v_user);
    IF EXISTS (SELECT 1 FROM sppoultrycustomercredit_events(v_farm, v_cust) e WHERE e.saleid = v_sale2) THEN
        RAISE EXCEPTION 'FAIL 7: a fully applied payment shows as credit'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrycustomerpayment_record(v_farm, v_cust, 50,
                jsonb_build_array(jsonb_build_object('saleid', v_sale2, 'amount', 60)),
                'Cash', now()::timestamp, v_acct, NULL, NULL, 'CustomerBalances', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7b: allocation above the payment accepted'; END IF;
    RAISE NOTICE 'ok 7 ordinary payments unchanged';

    RAISE NOTICE 'customer credit events: all checks passed';
END $$;

ROLLBACK;
