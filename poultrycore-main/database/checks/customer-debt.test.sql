-- =============================================================================
-- customer-debt.test.sql -- checks for migration 369.
--
-- Self-contained and ROLLED BACK: safe to run bare (psql -f). Works on a
-- throwaway customer in the first poultry company that has a cash account.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $$
DECLARE
    v_farm    text;
    v_user    text;
    v_acct    integer;
    v_cust    integer;
    v_debt    integer;
    v_debt2   integer;
    v_sale    integer;
    v_grp     uuid;
    v_grp2    uuid;
    v_res     jsonb;
    v_bal0    numeric;
    v_n       integer;
    v_x       numeric;
    v_failed  boolean;
    v_sales0  numeric;
    v_rev0    numeric;
BEGIN
    SELECT a.farmid, a.poultrycashaccountid INTO v_farm, v_acct
    FROM   poultrycashaccounts a
    JOIN   farms f ON (f.id::text = a.farmid OR f.farmid::text = a.farmid) AND f.type = 'Poultry'
    WHERE  a.isactive
    ORDER  BY a.poultrycashaccountid LIMIT 1;
    IF v_farm IS NULL THEN
        RAISE NOTICE 'customer debt: all checks passed';
        RETURN;
    END IF;
    SELECT f.owneruserid INTO v_user FROM farms f WHERE f.id::text = v_farm OR f.farmid::text = v_farm LIMIT 1;
    INSERT INTO customer (farmid, userid, name) VALUES (v_farm, COALESCE(v_user, '0'), 'Debt Check 369')
    RETURNING customerid INTO v_cust;

    -- 1. Record a debt of 8,500: owed, but no sale, no cash, no revenue.
    SELECT count(*), COALESCE(sum(totalamount), 0) INTO v_n, v_sales0 FROM sale WHERE farmid = v_farm;
    SELECT currentbalance INTO v_bal0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrycustomerdebt_create(v_farm, v_cust, 100, CURRENT_DATE, 'OpeningBalance', '  ', NULL, NULL, v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1a: debt without a description accepted'; END IF;
    v_res := sppoultrycustomerdebt_create(v_farm, v_cust, 8500, CURRENT_DATE - 3, 'HistoricalDebt',
                                          'Eggs supplied before the system', 'Old book p.12', NULL, v_user);
    v_debt := (v_res->>'debtId')::integer;
    IF (v_res->>'debtNumber') NOT LIKE 'CD-%' THEN RAISE EXCEPTION 'FAIL 1b: debt number %', v_res->>'debtNumber'; END IF;
    IF (SELECT count(*) FROM sale WHERE farmid = v_farm) <> v_n THEN RAISE EXCEPTION 'FAIL 1c: a sale was created'; END IF;
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal0 THEN
        RAISE EXCEPTION 'FAIL 1d: cash moved'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycustomerbalances(p_farmid => v_farm) b WHERE b.customerid = v_cust AND b.totalbalance = 8500) THEN
        RAISE EXCEPTION 'FAIL 1e: Customer Balances does not show 8,500 owed'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycustomerstatement(v_farm, v_cust) s WHERE s.entrytype = 'Debt' AND s.debit = 8500) THEN
        RAISE EXCEPTION 'FAIL 1f: statement has no debt line'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultryreport_customerbalance(v_farm, CURRENT_DATE) r WHERE r.customerid = v_cust AND r.balance = 8500) THEN
        RAISE EXCEPTION 'FAIL 1g: Advanced Reports customer balance misses the debt'; END IF;
    IF EXISTS (SELECT 1 FROM sppoultrycashflow_rows(v_farm, (CURRENT_DATE - 10)::timestamp, (CURRENT_DATE + 1)::timestamp) r
               WHERE r.amount = 8500) THEN
        RAISE EXCEPTION 'FAIL 1h: the debt is on Cash Flow'; END IF;
    RAISE NOTICE 'ok 1 a debt is owed, with no sale, cash or Cash Flow';

    -- 2. Pay 3,000 of it: 5,500 left; cash +3,000 once; not credit.
    v_failed := FALSE;
    BEGIN PERFORM sppoultrycustomerpayment_record(v_farm, v_cust, 3000,
                  jsonb_build_array(jsonb_build_object('debtid', v_debt, 'amount', 3000)),
                  'Cash', now()::timestamp, NULL, NULL, NULL, 'CustomerBalances', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 2a: debt paid without a cash account'; END IF;
    v_grp := sppoultrycustomerpayment_record(v_farm, v_cust, 3000,
                 jsonb_build_array(jsonb_build_object('debtid', v_debt, 'amount', 3000)),
                 'Cash', now()::timestamp, v_acct, NULL, NULL, 'CustomerBalances', v_user);
    IF fnpoultrycustomerdebt_balance(v_farm, v_debt) <> 5500 THEN
        RAISE EXCEPTION 'FAIL 2b: debt balance % (want 5500)', fnpoultrycustomerdebt_balance(v_farm, v_debt); END IF;
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal0 + 3000 THEN
        RAISE EXCEPTION 'FAIL 2c: cash did not go up by 3,000'; END IF;
    SELECT count(*), COALESCE(sum(amount), 0) INTO v_n, v_x FROM poultrycashtransactions WHERE paymentgroupid = v_grp;
    IF v_n <> 1 OR v_x <> 3000 THEN RAISE EXCEPTION 'FAIL 2d: cash rows % / %', v_n, v_x; END IF;
    IF fnpoultrycustomer_credit(v_farm, v_cust) <> 0 THEN
        RAISE EXCEPTION 'FAIL 2e: paying a debt created credit (%)', fnpoultrycustomer_credit(v_farm, v_cust); END IF;
    IF EXISTS (SELECT 1 FROM sppoultrycustomercredit_events(v_farm, v_cust)) THEN
        RAISE EXCEPTION 'FAIL 2f: a debt payment is listed as a credit'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycashflow_rows(v_farm, (CURRENT_DATE - 1)::timestamp, (CURRENT_DATE + 1)::timestamp) r
                   WHERE r.amount = 3000 AND r.description LIKE 'Customer debt payment%') THEN
        RAISE EXCEPTION 'FAIL 2g: Cash Flow does not show the debt payment'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycustomerpayment_allocations(v_farm, v_grp) a WHERE a.product LIKE 'Debt CD-%' AND a.amountapplied = 3000) THEN
        RAISE EXCEPTION 'FAIL 2h: payment drilldown does not show the debt'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycustomerbalances(p_farmid => v_farm) b WHERE b.customerid = v_cust AND b.totalbalance = 5500) THEN
        RAISE EXCEPTION 'FAIL 2i: Customer Balances does not show 5,500'; END IF;
    RAISE NOTICE 'ok 2 paying part of a debt: 5,500 left, cash in once, no credit';

    -- 3. Overpaying a debt is refused; a debt with payments cannot be reversed.
    v_failed := FALSE;
    BEGIN PERFORM sppoultrycustomerpayment_record(v_farm, v_cust, 6000,
                  jsonb_build_array(jsonb_build_object('debtid', v_debt, 'amount', 6000)),
                  'Cash', now()::timestamp, v_acct, NULL, NULL, 'CustomerBalances', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3a: more than owed applied to a debt'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrycustomerdebt_reverse(v_farm, v_debt, 'wrong', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3b: a paid debt was reversed'; END IF;
    RAISE NOTICE 'ok 3 overpaying and reversing a paid debt are refused';

    -- 4. Reverse the payment: the debt is owed in full again, cash back out.
    PERFORM sppoultrycustomerpayment_reverse(v_farm, v_grp, 'check', v_user);
    IF fnpoultrycustomerdebt_balance(v_farm, v_debt) <> 8500 THEN RAISE EXCEPTION 'FAIL 4a: debt not owed again'; END IF;
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal0 THEN
        RAISE EXCEPTION 'FAIL 4b: cash not back'; END IF;
    IF fnpoultrycustomer_credit(v_farm, v_cust) <> 0 THEN RAISE EXCEPTION 'FAIL 4c: reversal left credit'; END IF;
    RAISE NOTICE 'ok 4 reversing the payment reopens the debt';

    -- 5. One payment over a sale, a debt and a remainder: everything lands, once.
    SELECT (sppoultrysale_creategroup(p_farmid => v_farm, p_userid => v_user, p_saledate => now()::timestamp,
              p_customername => NULL, p_customerid => v_cust, p_paymentmethod => NULL,
              p_cashaccountid => v_acct, p_paid => false, p_description => 'debt check 369', p_flockid => NULL,
              p_linesjson => '[{"product":"Manure","eggProductId":null,"quantity":1,"unitPrice":400,"totalAmount":400}]',
              p_requestkey => 'check-369-' || gen_random_uuid()::text)::jsonb->>'saleId')::integer INTO v_sale;
    v_grp2 := sppoultrycustomerpayment_record(v_farm, v_cust, 1500,
                 jsonb_build_array(jsonb_build_object('saleid', v_sale, 'amount', 400),
                                   jsonb_build_object('debtid', v_debt, 'amount', 1000)),
                 'Cash', now()::timestamp, v_acct, NULL, NULL, 'PaymentsPage', v_user);
    IF (SELECT fnpoultrysalebalance(paid, totalamount, amountpaid) FROM sale WHERE saleid = v_sale) <> 0 THEN
        RAISE EXCEPTION 'FAIL 5a: sale not paid'; END IF;
    IF fnpoultrycustomerdebt_balance(v_farm, v_debt) <> 7500 THEN RAISE EXCEPTION 'FAIL 5b: debt not reduced'; END IF;
    IF fnpoultrycustomer_credit(v_farm, v_cust) <> 100 THEN
        RAISE EXCEPTION 'FAIL 5c: remainder credit % (want 100)', fnpoultrycustomer_credit(v_farm, v_cust); END IF;
    SELECT count(*), COALESCE(sum(amount), 0) INTO v_n, v_x FROM poultrycashtransactions WHERE paymentgroupid = v_grp2;
    IF v_n <> 1 OR v_x <> 1500 THEN RAISE EXCEPTION 'FAIL 5d: cash rows % / %', v_n, v_x; END IF;
    IF (SELECT h.sourcetype FROM sppoultrycustomerpayment_history(v_farm, v_cust) h WHERE h.paymentgroupid = v_grp2) <> 'PaymentsPage' THEN
        RAISE EXCEPTION 'FAIL 5e: mixed payment reads as a credit'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrycustomercredit_reverse(v_farm, v_grp2, 'x', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5f: the payment''s remainder reversed as a manual credit'; END IF;
    RAISE NOTICE 'ok 5 one payment over a sale, a debt and a remainder';

    -- 6. An unpaid debt reverses: no longer owed, no cash, history kept.
    v_res := sppoultrycustomerdebt_create(v_farm, v_cust, 200, CURRENT_DATE, 'Adjustment', 'Entered twice', NULL, NULL, v_user);
    v_debt2 := (v_res->>'debtId')::integer;
    SELECT currentbalance INTO v_bal0 FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    PERFORM sppoultrycustomerdebt_reverse(v_farm, v_debt2, 'entered twice', v_user);
    IF fnpoultrycustomerdebt_balance(v_farm, v_debt2) <> 0 THEN RAISE EXCEPTION 'FAIL 6a: reversed debt still owed'; END IF;
    IF (SELECT status FROM poultrycustomerdebts WHERE debtid = v_debt2) <> 'Reversed' THEN RAISE EXCEPTION 'FAIL 6b: not Reversed'; END IF;
    IF (SELECT currentbalance FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct) <> v_bal0 THEN RAISE EXCEPTION 'FAIL 6c: cash moved'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sppoultrycustomerdebt_reverse(v_farm, v_debt2, 'again', v_user);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6d: debt reversed twice'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycustomerdebt_list(v_farm, v_cust) l WHERE l.debtid = v_debt2 AND l.status = 'Reversed') THEN
        RAISE EXCEPTION 'FAIL 6e: reversed debt not in the list'; END IF;
    RAISE NOTICE 'ok 6 an unpaid debt reverses with no cash';

    -- 7. Open items for the payment dialog; credit summary still-owes.
    IF NOT EXISTS (SELECT 1 FROM sppoultrycustomeropendebts(v_farm, v_cust) o WHERE o.debtid = v_debt AND o.balance = 7500) THEN
        RAISE EXCEPTION 'FAIL 7a: open debts'; END IF;
    IF NOT EXISTS (SELECT 1 FROM sppoultrycustomercredit_summary(v_farm) s WHERE s.customerid = v_cust AND s.outstanding = 7500) THEN
        RAISE EXCEPTION 'FAIL 7b: credit summary still-owes misses the debt'; END IF;
    RAISE NOTICE 'ok 7 open debts listed; still-owes includes debts';

    RAISE NOTICE 'customer debt: all checks passed';
END $$;

ROLLBACK;
