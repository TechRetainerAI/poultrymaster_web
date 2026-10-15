-- =============================================================================
-- manual-customer-credit.test.sql -- checks for migration 363.
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
    v_res     jsonb;
    v_open    uuid;
    v_dep     uuid;
    v_note    uuid;
    v_sale    integer;
    v_n       numeric;
    v_bal0    numeric;
    v_bal1    numeric;
    v_salecash integer;
    v_failed  boolean;
    v_txt     text;
BEGIN
    SELECT a.farmid, a.poultrycashaccountid INTO v_farm, v_acct
    FROM   poultrycashaccounts a
    JOIN   farms f ON (f.id::text = a.farmid OR f.farmid::text = a.farmid) AND f.type = 'Poultry'
    WHERE  a.isactive
    ORDER  BY a.poultrycashaccountid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'manual customer credit: no poultry company with a cash account -- skipped';
        RAISE NOTICE 'manual customer credit: all checks passed';
        RETURN;
    END IF;
    SELECT f.owneruserid INTO v_user FROM farms f WHERE f.id::text = v_farm OR f.farmid::text = v_farm LIMIT 1;

    INSERT INTO customer (farmid, userid, name) VALUES (v_farm, COALESCE(v_user, '0'), 'Credit Check 363')
    RETURNING customerid INTO v_cust;

    -- 1. opening credit: credit, no cash, not money received
    SELECT currentbalance INTO v_bal0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_res := sppoultrycustomercredit_create(v_farm, v_cust, 'OpeningCredit', 500, NULL, NULL, NULL, 'OB-1', 'Prepaid before go-live', v_user);
    v_open := (v_res->>'paymentGroupId')::uuid;
    IF fnpoultrycustomer_credit(v_farm, v_cust) <> 500 THEN RAISE EXCEPTION 'FAIL 1a: opening credit not counted (%)', fnpoultrycustomer_credit(v_farm, v_cust); END IF;
    IF EXISTS (SELECT 1 FROM poultrycashtransactions ct WHERE ct.paymentgroupid = v_open) THEN RAISE EXCEPTION 'FAIL 1b: opening credit moved cash'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycustomercredit_summary(v_farm) s WHERE s.customerid = v_cust AND s.availablecredit = 500) THEN
        RAISE EXCEPTION 'FAIL 1c: not on the credit summary'; END IF;
    RAISE NOTICE 'ok 1 opening credit is credit, and no cash';

    -- 2. an opening credit with a cash account is refused
    v_failed := false;
    BEGIN PERFORM sppoultrycustomercredit_create(v_farm, v_cust, 'OpeningCredit', 10, NULL, v_acct, NULL, NULL, 'x', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2: opening credit took a cash account'; END IF;
    v_failed := false;
    BEGIN PERFORM sppoultrycustomercredit_create(v_farm, v_cust, 'CreditNote', 10, NULL, NULL, NULL, NULL, '  ', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2b: credit without a reason accepted'; END IF;
    RAISE NOTICE 'ok 2 bad input refused';

    -- 3. credit pays a sale: sale paid, credit down, NO phantom sale cash
    SELECT (sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => now()::timestamp,
              p_customername => NULL, p_customerid => v_cust, p_paymentmethod => 'Customer Credit',
              p_cashaccountid => v_acct, p_paid => false, p_description => 'credit check', p_flockid => NULL,
              p_linesjson => '[{"product":"Manure","eggProductId":null,"quantity":1,"unitPrice":300,"totalAmount":300}]',
              p_requestkey => 'check-363-' || gen_random_uuid()::text)::jsonb->>'saleId')::integer INTO v_sale;
    PERFORM sppoultrycustomercredit_apply(v_farm, v_cust, v_sale, 300, v_user);
    IF (SELECT fnpoultrysalebalance(paid, totalamount, amountpaid) FROM sale WHERE saleid = v_sale) <> 0 THEN
        RAISE EXCEPTION 'FAIL 3a: sale not paid by credit'; END IF;
    IF fnpoultrycustomer_credit(v_farm, v_cust) <> 200 THEN RAISE EXCEPTION 'FAIL 3b: credit not reduced'; END IF;
    SELECT count(*) INTO v_salecash FROM poultrycashtransactions ct WHERE ct.sourcetype = 'Sale' AND ct.sourceid = v_sale AND ct.farmid = v_farm;
    IF v_salecash <> 0 THEN RAISE EXCEPTION 'FAIL 3c: phantom sale CashIn posted for a credit-paid sale'; END IF;
    RAISE NOTICE 'ok 3 credit pays a sale, no phantom cash';

    -- 4. a credit-paid sale cannot be discarded
    v_failed := false;
    BEGIN
        PERFORM set_config('poultry.sale_discard', 'on', true);
        PERFORM spsale_delete(v_farm, v_user, v_sale);
    EXCEPTION WHEN raise_exception THEN v_failed := true; END;
    PERFORM set_config('poultry.sale_discard', '', true);
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4: credit-paid sale discarded'; END IF;
    RAISE NOTICE 'ok 4 credit-paid sale cannot be discarded';

    -- 5. reversing the sale hands the credit back, never cash out
    SELECT jsonb_agg(m->'allowed') INTO v_res FROM jsonb_array_elements(fnpoultrysale_reversalstate(v_farm, v_sale)->'payments') m;
    IF v_res::text LIKE '%ReversePayment%' THEN RAISE EXCEPTION 'FAIL 5a: reversal offers to reverse an opening credit: %', v_res; END IF;
    PERFORM sppoultrysale_reverse(v_farm, v_sale, 'Other', 'credit check',
        (SELECT COALESCE(jsonb_object_agg(m->>'key', 'KeepAsCredit'), '{}'::jsonb)
         FROM jsonb_array_elements(fnpoultrysale_reversalstate(v_farm, v_sale)->'payments') m),
        NULL, NULL, v_user);
    IF fnpoultrycustomer_credit(v_farm, v_cust) <> 500 THEN RAISE EXCEPTION 'FAIL 5b: credit not handed back (%)', fnpoultrycustomer_credit(v_farm, v_cust); END IF;
    SELECT currentbalance INTO v_bal1 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    IF v_bal1 <> v_bal0 THEN RAISE EXCEPTION 'FAIL 5c: cash moved (% -> %)', v_bal0, v_bal1; END IF;
    RAISE NOTICE 'ok 5 sale reversal returns the credit, cash unchanged';

    -- 5b. a manual credit is not reversed as an ordinary payment
    v_failed := false;
    BEGIN PERFORM sppoultrycustomerpayment_reverse(v_farm, v_open, 'x', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5d: manual credit reversed as a payment'; END IF;
    RAISE NOTICE 'ok 5b manual credit only reversed from Customer Credits';

    -- 6. deposit: real cash in, Money In on Cash Flow; reversing it takes it back out
    v_res := sppoultrycustomercredit_create(v_farm, v_cust, 'Deposit', 250, NULL, v_acct, 'Cash', NULL, 'Paid in advance', v_user);
    v_dep := (v_res->>'paymentGroupId')::uuid;
    SELECT currentbalance INTO v_bal1 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    IF v_bal1 <> v_bal0 + 250 THEN RAISE EXCEPTION 'FAIL 6a: deposit cash not in (% -> %)', v_bal0, v_bal1; END IF;
    IF fnpoultrycustomer_credit(v_farm, v_cust) <> 750 THEN RAISE EXCEPTION 'FAIL 6b: deposit not credit'; END IF;
    SELECT count(*) INTO v_n FROM sppoultrycashflow_rows(v_farm, (now() - interval '2 days')::date, (now() + interval '2 days')::date) r
     WHERE r.amount = 250 AND r.description LIKE 'Customer advance%';   -- 367: shown as an advance
    IF v_n <> 1 THEN RAISE EXCEPTION 'FAIL 6c: deposit not Money In on Cash Flow (% rows)', v_n; END IF;
    PERFORM sppoultrycustomercredit_reverse(v_farm, v_dep, 'entered twice', v_user);
    SELECT currentbalance INTO v_bal1 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    IF v_bal1 <> v_bal0 THEN RAISE EXCEPTION 'FAIL 6d: reversed deposit left cash (% -> %)', v_bal0, v_bal1; END IF;
    IF fnpoultrycustomer_credit(v_farm, v_cust) <> 500 THEN RAISE EXCEPTION 'FAIL 6e: reversed deposit still credit'; END IF;
    RAISE NOTICE 'ok 6 deposit is cash in; reversing it takes it back out';

    -- 7. opening credit is not on Cash Flow
    SELECT count(*) INTO v_n FROM sppoultrycashflow_rows(v_farm, (now() - interval '2 days')::date, (now() + interval '2 days')::date) r
     WHERE r.amount = 500 AND r.description LIKE '%Credit Check 363%';   -- only this check's customer
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 7: opening credit on Cash Flow'; END IF;
    RAISE NOTICE 'ok 7 opening credit is not money received';

    -- 8. credit note: a negative P&L revenue line; total revenue falls by it
    SELECT COALESCE(SUM(amount) FILTER (WHERE section = 'Revenue'), 0) INTO v_bal0
    FROM sppoultryreport_pllines(v_farm, (now() - interval '2 days')::date, (now() + interval '2 days')::date);
    v_res := sppoultrycustomercredit_create(v_farm, v_cust, 'CreditNote', 40, NULL, NULL, NULL, NULL, 'Broken eggs', v_user);
    v_note := (v_res->>'paymentGroupId')::uuid;
    SELECT COALESCE(SUM(amount) FILTER (WHERE section = 'Revenue'), 0) INTO v_bal1
    FROM sppoultryreport_pllines(v_farm, (now() - interval '2 days')::date, (now() + interval '2 days')::date);
    IF v_bal1 <> v_bal0 - 40 THEN RAISE EXCEPTION 'FAIL 8a: revenue % -> %, expected -40', v_bal0, v_bal1; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultryreport_plrevenuedetail(v_farm, (now() - interval '2 days')::date, (now() + interval '2 days')::date, 'CreditNotes') d
                   WHERE d.totalamount = -40) THEN RAISE EXCEPTION 'FAIL 8b: credit note missing from the drilldown'; END IF;
    PERFORM sppoultrycustomercredit_reverse(v_farm, v_note, 'mistake', v_user);
    SELECT COALESCE(SUM(amount) FILTER (WHERE section = 'Revenue'), 0) INTO v_bal1
    FROM sppoultryreport_pllines(v_farm, (now() - interval '2 days')::date, (now() + interval '2 days')::date);
    IF v_bal1 <> v_bal0 THEN RAISE EXCEPTION 'FAIL 8c: reversed credit note still on P&L'; END IF;
    RAISE NOTICE 'ok 8 credit note is a cost on P&L until reversed';

    -- 9. statement names the kind and has no NULL description
    SELECT string_agg(s.description, ' | ') INTO v_txt FROM sppoultrycustomerstatement(v_farm, v_cust, NULL, NULL) s;
    IF v_txt IS NULL OR v_txt NOT LIKE '%Opening credit%' THEN RAISE EXCEPTION 'FAIL 9: statement: %', v_txt; END IF;
    RAISE NOTICE 'ok 9 statement says Opening credit';

    -- 10. the manual list shows all three, with what is left
    SELECT count(*) INTO v_n FROM sppoultrycustomercredit_manuallist(v_farm) m WHERE m.customerid = v_cust;
    IF v_n <> 3 THEN RAISE EXCEPTION 'FAIL 10a: manual list has % rows', v_n; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycustomercredit_manuallist(v_farm) m
                   WHERE m.paymentgroupid = v_open AND m.remaining = 500 AND m.status = 'Posted') THEN
        RAISE EXCEPTION 'FAIL 10b: opening credit row wrong'; END IF;
    v_failed := false;
    BEGIN PERFORM sppoultrycustomercredit_reverse(v_farm, v_open, 'x', v_user); PERFORM sppoultrycustomercredit_reverse(v_farm, v_open, 'x', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := true; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 10c: reversed twice'; END IF;
    RAISE NOTICE 'ok 10 manual list, and no double reversal';

    RAISE NOTICE 'manual customer credit: all checks passed';
END $$;

ROLLBACK;
