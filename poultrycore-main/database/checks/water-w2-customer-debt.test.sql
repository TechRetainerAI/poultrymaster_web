-- =============================================================================
-- Checks for 425 (Water customer debt, W2).  SELF-ROLLING-BACK, fixtures in a
-- real Water company, dated 2001 (debts and credits refuse future dates).
-- Prints 'water W2: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $t$
DECLARE
    v_farm text; v_cust integer; v_debt jsonb; v_did integer; v_grp uuid; v_grp2 uuid;
    v_n numeric; v_m numeric; v_base numeric; v_flag integer; v_lt record; v_od integer;
    d1 date := DATE '2001-03-10';
    d2 date := DATE '2001-03-11';
BEGIN
    SELECT a.farmid INTO v_farm FROM watercashaccounts a ORDER BY a.watercashaccountid LIMIT 1;
    INSERT INTO watercustomers (farmid, name) VALUES (v_farm, '__w2_customer') RETURNING watercustomerid INTO v_cust;
    SELECT totalincome INTO v_base FROM spwaterreport_periodpnl(v_farm, d2, d2);

    -- 1. a debt is owed, and moves nothing else
    v_debt := spwatercustomerdebt_create(v_farm, v_cust, 100, d1, 'OpeningBalance', 'owed before the system', NULL, NULL, '__w2');
    v_did := (v_debt->>'debtId')::int;
    IF (SELECT totalbalance FROM spwatercustomerbalances(v_farm) WHERE customerid = v_cust) <> 100 THEN RAISE EXCEPTION 'FAIL 1a: balance'; END IF;
    IF (SELECT SUM(debit) - SUM(credit) FROM spwatercustomerstatement(v_farm, v_cust)) <> 100 THEN RAISE EXCEPTION 'FAIL 1b: statement'; END IF;
    IF NOT EXISTS (SELECT 1 FROM spwatercustomeropendebts(v_farm, v_cust) WHERE debtid = v_did AND balance = 100) THEN RAISE EXCEPTION 'FAIL 1c: open debts'; END IF;
    RAISE NOTICE 'ok 1 a debt is owed (balances, statement, open items)';

    -- 2. paying it: the debt goes down, NO credit appears
    v_grp := spwatercustomerpayment_record(v_farm, v_cust, 60, jsonb_build_array(jsonb_build_object('debtid', v_did, 'amount', 60)),
                                           'Cash', d2 + time '09:00', NULL, NULL, NULL, 'CustomerBalances', '__w2');
    IF fnwatercustomerdebt_balance(v_farm, v_did) <> 40 THEN RAISE EXCEPTION 'FAIL 2a: debt balance'; END IF;
    IF fnwatercustomer_credit(v_farm, v_cust) <> 0 THEN RAISE EXCEPTION 'FAIL 2b: a debt payment became credit (%)', fnwatercustomer_credit(v_farm, v_cust); END IF;
    IF EXISTS (SELECT 1 FROM spwatercustomercredit_events(v_farm, v_cust)) THEN RAISE EXCEPTION 'FAIL 2c: debt payment listed as credit'; END IF;
    IF (SELECT SUM(debit) - SUM(credit) FROM spwatercustomerstatement(v_farm, v_cust)) <> 40 THEN RAISE EXCEPTION 'FAIL 2d: statement after payment'; END IF;
    IF NOT EXISTS (SELECT 1 FROM spwatercustomerpayment_allocations(v_farm, v_grp) WHERE documenttype = 'CustomerDebt' AND amountapplied = 60) THEN
        RAISE EXCEPTION 'FAIL 2e: allocation line';
    END IF;
    SELECT * INTO v_lt FROM fnwaterdailyclosing_livetotals(v_farm, d2);
    SELECT COALESCE(SUM(p.amount), 0) INTO v_n FROM waterpayments p
    WHERE p.farmid = v_farm AND p.createdby <> '__w2' AND COALESCE(p.status,'Posted') = 'Posted'
      AND COALESCE(p.sourcetype,'') <> 'DeliveryRun' AND NOT fnwater_ismanualcredit(p.sourcetype)
      AND p.paymentdate >= d2 AND p.paymentdate < d2 + 1
      AND NOT EXISTS (SELECT 1 FROM watersales s WHERE s.watersaleid = p.watersaleid AND s.saledate >= d2 AND s.saledate < d2 + 1
                      AND COALESCE(s.sourcetype,'') <> 'DeliveryRun');
    IF v_lt.customercollections <> 60 + v_n THEN RAISE EXCEPTION 'FAIL 2f: closing collections %', v_lt.customercollections; END IF;
    RAISE NOTICE 'ok 2 paying a debt reduces it, is collected, never becomes credit';

    -- 3. a debt payment is revenue; excluding it takes it off
    SELECT totalincome INTO v_n FROM spwaterreport_periodpnl(v_farm, d2, d2);
    IF v_n <> v_base + 60 THEN RAISE EXCEPTION 'FAIL 3a: P&L % expected %', v_n, v_base + 60; END IF;
    SELECT COALESCE(SUM(l.amount), 0) INTO v_m FROM spwaterreport_pllines(v_farm, d2, d2) l WHERE l.section = 'Revenue';
    IF v_m <> v_n THEN RAISE EXCEPTION 'FAIL 3b: P&L lines % <> periodpnl %', v_m, v_n; END IF;
    PERFORM spwaterpayment_setplexclusion(v_farm, v_grp, TRUE, '__w2');
    SELECT totalincome INTO v_n FROM spwaterreport_periodpnl(v_farm, d2, d2);
    IF v_n <> v_base THEN RAISE EXCEPTION 'FAIL 3c: excluded payment still on P&L'; END IF;
    PERFORM spwaterpayment_setplexclusion(v_farm, v_grp, FALSE, '__w2');
    RAISE NOTICE 'ok 3 debt collections on P&L, excludable';

    -- 4. a paid debt cannot be reversed
    v_flag := 0;
    BEGIN
        PERFORM spwatercustomerdebt_reverse(v_farm, v_did, 'x', '__w2');
    EXCEPTION WHEN SQLSTATE 'P0001' THEN v_flag := 1;
    END;
    IF v_flag <> 1 THEN RAISE EXCEPTION 'FAIL 4: paid debt reversed'; END IF;
    RAISE NOTICE 'ok 4 paid debt cannot be reversed';

    -- 5. old debt: a payment for a sale made before the system is revenue, not credit
    v_grp2 := spwatercustomerpayment_recordolddebt(v_farm, v_cust, 50, '[]'::jsonb, 'Cash', d2 + time '10:00',
                                                   NULL, NULL, NULL, 'PaymentsPage', '__w2', 'Water bags');
    SELECT d.debtid INTO v_od FROM watercustomerdebts d JOIN waterpayments p ON p.waterdebtid = d.debtid
    WHERE p.paymentgroupid = v_grp2 AND d.paidonentry AND d.saletype = 'Water bags';
    IF v_od IS NULL THEN RAISE EXCEPTION 'FAIL 5a: no paid-on-entry old debt'; END IF;
    IF fnwatercustomerdebt_balance(v_farm, v_od) <> 0 THEN RAISE EXCEPTION 'FAIL 5b: old debt not paid'; END IF;
    IF fnwatercustomer_credit(v_farm, v_cust) <> 0 THEN RAISE EXCEPTION 'FAIL 5c: old debt payment became credit'; END IF;
    SELECT totalincome INTO v_n FROM spwaterreport_periodpnl(v_farm, d2, d2);
    IF v_n <> v_base + 110 THEN RAISE EXCEPTION 'FAIL 5d: P&L %', v_n; END IF;
    IF NOT EXISTS (SELECT 1 FROM spwaterreport_plrevenuedetail(v_farm, d2, d2, 'DebtCollections') x
                   WHERE x.detail LIKE 'Old debt collected: Water bags%') THEN RAISE EXCEPTION 'FAIL 5e: revenue detail'; END IF;
    RAISE NOTICE 'ok 5 old-debt payment: paid-on-entry debt, revenue with its sale type';

    -- 6. reversing the old-debt payment reverses its debt (nobody owes it)
    PERFORM spwatercustomerpayment_reverse(v_farm, v_grp2, 'mistake', '__w2');
    IF (SELECT status FROM watercustomerdebts WHERE debtid = v_od) <> 'Reversed' THEN RAISE EXCEPTION 'FAIL 6a: old debt left owed'; END IF;
    SELECT totalincome INTO v_n FROM spwaterreport_periodpnl(v_farm, d2, d2);
    IF v_n <> v_base + 60 THEN RAISE EXCEPTION 'FAIL 6b: P&L after reversal %', v_n; END IF;
    RAISE NOTICE 'ok 6 reversing an old-debt payment reverses the debt';

    -- 7. reversing a debt payment: owed again; the debt can then be reversed
    PERFORM spwatercustomerpayment_reverse(v_farm, v_grp, 'test', '__w2');
    IF fnwatercustomerdebt_balance(v_farm, v_did) <> 100 THEN RAISE EXCEPTION 'FAIL 7a'; END IF;
    PERFORM spwatercustomerdebt_reverse(v_farm, v_did, 'entered by mistake', '__w2');
    IF EXISTS (SELECT 1 FROM spwatercustomerbalances(v_farm) WHERE customerid = v_cust) THEN RAISE EXCEPTION 'FAIL 7b: reversed debt still owed'; END IF;
    RAISE NOTICE 'ok 7 debt payment reversal and debt reversal';

    -- 8. W1 still works: a payment remainder is still credit
    PERFORM spwatercustomerpayment_record(v_farm, v_cust, 25, '[]'::jsonb, 'Cash', d2 + time '11:00', NULL, NULL, NULL, 'CustomerBalances', '__w2');
    IF fnwatercustomer_credit(v_farm, v_cust) <> 25 THEN RAISE EXCEPTION 'FAIL 8: credit %', fnwatercustomer_credit(v_farm, v_cust); END IF;
    RAISE NOTICE 'ok 8 payment remainder is still credit';

    RAISE NOTICE 'water W2: all checks passed';
END
$t$;

ROLLBACK;
