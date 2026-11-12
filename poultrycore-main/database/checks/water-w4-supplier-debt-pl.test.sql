-- =============================================================================
-- Checks for 427 (Water supplier debt payments on P&L + old debt, W4).
-- SELF-ROLLING-BACK, fixtures in a real Water company. Prints
-- 'water W4: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $t$
DECLARE
    v_farm text; v_acct integer; v_supp integer; v_did integer; v_did2 integer;
    v_pay integer; v_old integer; v_adv integer; v_cn integer; v_od integer;
    v_base numeric; v_n numeric; v_m numeric; v_today date := (now() AT TIME ZONE 'utc')::date;
    d1 date := DATE '2001-05-10';
BEGIN
    SELECT a.farmid INTO v_farm FROM watercashaccounts a ORDER BY a.watercashaccountid LIMIT 1;
    INSERT INTO watercashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, isactive)
    VALUES (v_farm, '__w4_account', 'Cash', 10000, 10000, TRUE) RETURNING watercashaccountid INTO v_acct;
    v_supp := spwatersupplier_insert(v_farm, '__w4_supplier', NULL, NULL, NULL, NULL, NULL, NULL, '__w4');
    v_did := (spwatersupplierdebt_create(v_farm, v_supp, 200, d1, 'OpeningBalance', 'old', NULL, NULL, '__w4')->>'debtId')::int;
    SELECT totalexpenses INTO v_base FROM spwaterreport_periodpnl(v_farm, d1, d1);

    -- 1. paying a supplier debt is an operating expense on the payment date
    v_pay := spwatersupplierpayment_record(v_farm, v_supp, 200,
               jsonb_build_array(jsonb_build_object('documenttype', 'SupplierDebt', 'documentid', v_did, 'amount', 200)),
               'Cash', d1 + time '09:00', v_acct, NULL, NULL, 'SupplierBalances', '__w4');
    SELECT totalexpenses INTO v_n FROM spwaterreport_periodpnl(v_farm, d1, d1);
    IF v_n <> v_base + 200 THEN RAISE EXCEPTION 'FAIL 1a: opex % expected %', v_n, v_base + 200; END IF;
    SELECT COALESCE(SUM(l.amount), 0) INTO v_m FROM spwaterreport_pllines(v_farm, d1, d1) l
    WHERE l.section = 'OperatingExpense' AND l.linekey = 'SupplierDebtPayments';
    IF v_m <> 200 THEN RAISE EXCEPTION 'FAIL 1b: P&L line %', v_m; END IF;
    IF NOT EXISTS (SELECT 1 FROM spwaterreport_plexpensedetail(v_farm, d1, d1, 'SupplierDebtPayments')) THEN RAISE EXCEPTION 'FAIL 1c: detail'; END IF;
    PERFORM spwatersupplierpayment_setplexclusion(v_farm, v_pay, TRUE, '__w4');
    SELECT totalexpenses INTO v_n FROM spwaterreport_periodpnl(v_farm, d1, d1);
    IF v_n <> v_base THEN RAISE EXCEPTION 'FAIL 1d: excluded payment still on P&L'; END IF;
    PERFORM spwatersupplierpayment_setplexclusion(v_farm, v_pay, FALSE, '__w4');
    RAISE NOTICE 'ok 1 supplier debt payment on P&L, excludable';

    -- 2. old debt: the leftover of Record supplier payment is an expense, not credit
    v_old := spwatersupplierpayment_recordolddebt(v_farm, v_supp, 150, '[]'::jsonb, 'Cash', d1 + time '10:00', v_acct,
                                                  NULL, NULL, 'SupplierPayments', '__w4');
    SELECT sa.documentid INTO v_od FROM supplierpaymentallocation sa
    WHERE sa.module = 'water' AND sa.paymentid = v_old AND sa.documenttype = 'SupplierDebt';
    IF NOT (SELECT paidonentry FROM watersupplierdebts WHERE debtid = v_od) THEN RAISE EXCEPTION 'FAIL 2a: not paid on entry'; END IF;
    IF fnwatersupplier_credit(v_farm, v_supp) <> 0 THEN RAISE EXCEPTION 'FAIL 2b: old debt became credit'; END IF;
    SELECT totalexpenses INTO v_n FROM spwaterreport_periodpnl(v_farm, d1, d1);
    IF v_n <> v_base + 350 THEN RAISE EXCEPTION 'FAIL 2c: opex %', v_n; END IF;
    PERFORM spwatersupplierpayment_reverse(v_farm, v_old, 'mistake', '__w4');
    IF (SELECT status FROM watersupplierdebts WHERE debtid = v_od) <> 'Reversed' THEN RAISE EXCEPTION 'FAIL 2d: old debt left owed'; END IF;
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 9800 THEN RAISE EXCEPTION 'FAIL 2e: cash'; END IF;
    RAISE NOTICE 'ok 2 old-debt supplier payment: expense, reversal removes its debt';

    -- 3. a cash advance applied to a debt counts on the day it is applied
    v_did2 := (spwatersupplierdebt_create(v_farm, v_supp, 80, d1, 'HistoricalDebt', 'second', NULL, NULL, '__w4')->>'debtId')::int;
    v_adv := spwatersupplierpayment_record(v_farm, v_supp, 80, '[]'::jsonb, 'Cash', d1 + time '11:00', v_acct, NULL, NULL, 'SupplierBalances', '__w4');
    SELECT totalexpenses INTO v_base FROM spwaterreport_periodpnl(v_farm, v_today, v_today);
    PERFORM spwatersuppliercredit_apply(v_farm, v_adv, 'SupplierDebt', v_did2, 80, '__w4');
    SELECT totalexpenses INTO v_n FROM spwaterreport_periodpnl(v_farm, v_today, v_today);
    IF v_n <> v_base + 80 THEN RAISE EXCEPTION 'FAIL 3a: applied advance on P&L %', v_n - v_base; END IF;
    SELECT totalexpenses INTO v_n FROM spwaterreport_periodpnl(v_farm, d1, d1);
    IF v_n <> (SELECT totalexpenses FROM spwaterreport_periodpnl(v_farm, d1, d1)) THEN RAISE EXCEPTION 'FAIL 3b'; END IF;
    RAISE NOTICE 'ok 3 advance applied to a debt counts when applied';

    -- 4. a credit note netted against a debt moves no money: never on P&L
    v_cn := spwatersuppliercredit_create(v_farm, v_supp, 'SupplierCreditNote', 50, d1 + time '12:00', NULL, 'allowance', '__w4');
    v_did2 := (spwatersupplierdebt_create(v_farm, v_supp, 50, d1, 'HistoricalDebt', 'third', NULL, NULL, '__w4')->>'debtId')::int;
    SELECT totalexpenses INTO v_base FROM spwaterreport_periodpnl(v_farm, v_today, v_today);
    PERFORM spwatersuppliercredit_apply(v_farm, v_cn, 'SupplierDebt', v_did2, 50, '__w4');
    SELECT totalexpenses INTO v_n FROM spwaterreport_periodpnl(v_farm, v_today, v_today);
    IF v_n <> v_base THEN RAISE EXCEPTION 'FAIL 4: credit note against a debt reached P&L'; END IF;
    RAISE NOTICE 'ok 4 credit note against a debt is never P&L';

    -- 5. the itemisation still sums to periodpnl
    SELECT COALESCE(SUM(l.amount), 0) INTO v_m FROM spwaterreport_pllines(v_farm, d1, d1) l
    WHERE l.section IN ('OperatingExpense', 'OtherExpense', 'NonOperatingExpense')
       OR (l.section NOT IN ('Revenue', 'DirectCost', 'Loss', 'Financing', 'CapitalInvestment'));
    SELECT totalexpenses INTO v_n FROM spwaterreport_periodpnl(v_farm, d1, d1);
    IF v_m <> v_n THEN RAISE EXCEPTION 'FAIL 5: expense lines % <> periodpnl %', v_m, v_n; END IF;
    RAISE NOTICE 'ok 5 P&L lines still reconcile';

    RAISE NOTICE 'water W4: all checks passed';
END
$t$;

ROLLBACK;
