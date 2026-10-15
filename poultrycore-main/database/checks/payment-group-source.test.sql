-- =============================================================================
-- payment-group-source.test.sql -- checks for migration 368.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f).
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm  text;
    v_user  text;
    v_acct  integer;
    v_cust  integer;
    v_sale  integer;
    v_grp   uuid;
    v_adv   uuid;
    v_src   text;
BEGIN
    SELECT a.farmid, a.poultrycashaccountid INTO v_farm, v_acct
    FROM   poultrycashaccounts a
    JOIN   farms f ON (f.id::text = a.farmid OR f.farmid::text = a.farmid) AND f.type = 'Poultry'
    WHERE  a.isactive
    ORDER  BY a.poultrycashaccountid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'payment group source: all checks passed';
        RETURN;
    END IF;
    SELECT f.owneruserid INTO v_user FROM farms f WHERE f.id::text = v_farm OR f.farmid::text = v_farm LIMIT 1;
    INSERT INTO customer (farmid, userid, name) VALUES (v_farm, COALESCE(v_user, '0'), 'Source Check 368')
    RETURNING customerid INTO v_cust;
    SELECT (sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => now()::timestamp,
              p_customername => NULL, p_customerid => v_cust, p_paymentmethod => NULL,
              p_cashaccountid => v_acct, p_paid => false, p_description => 'source check 368', p_flockid => NULL,
              p_linesjson => '[{"product":"Manure","eggProductId":null,"quantity":1,"unitPrice":100,"totalAmount":100}]',
              p_requestkey => 'check-368-' || gen_random_uuid()::text)::jsonb->>'saleId')::integer INTO v_sale;

    -- 1. Paid a sale and kept the rest: reads as the payment it is.
    v_grp := sppoultrycustomerpayment_record(v_farm, v_cust, 150,
                 jsonb_build_array(jsonb_build_object('saleid', v_sale, 'amount', 100)),
                 'Cash', now()::timestamp, v_acct, NULL, NULL, 'PaymentsPage', v_user);
    SELECT h.sourcetype INTO v_src FROM sppoultrycustomerpayment_history(v_farm, v_cust) h WHERE h.paymentgroupid = v_grp;
    IF v_src IS DISTINCT FROM 'PaymentsPage' THEN RAISE EXCEPTION 'FAIL 1: mixed payment reads as %', v_src; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycustomerstatement(v_farm, v_cust) s
                   WHERE s.paymentgroupid = v_grp AND s.sourcetype = 'PaymentsPage' AND s.description LIKE 'Payment received%') THEN
        RAISE EXCEPTION 'FAIL 1b: statement line for the mixed payment'; END IF;
    RAISE NOTICE 'ok 1 a payment that also kept credit reads as a payment';

    -- 2. A payment with no sale keeps its own source and reads as an advance.
    v_adv := sppoultrycustomerpayment_record(v_farm, v_cust, 70, '[]'::jsonb, 'Cash', now()::timestamp, v_acct, NULL, NULL, 'PaymentsPage', v_user);
    SELECT h.sourcetype INTO v_src FROM sppoultrycustomerpayment_history(v_farm, v_cust) h WHERE h.paymentgroupid = v_adv;
    IF v_src IS DISTINCT FROM 'Deposit' THEN RAISE EXCEPTION 'FAIL 2: advance reads as %', v_src; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycustomerstatement(v_farm, v_cust) s
                   WHERE s.paymentgroupid = v_adv AND s.description LIKE 'Customer advance received%') THEN
        RAISE EXCEPTION 'FAIL 2b: statement does not say Customer advance received'; END IF;
    RAISE NOTICE 'ok 2 an advance reads as an advance';

    RAISE NOTICE 'payment group source: all checks passed';
END $$;

ROLLBACK;
