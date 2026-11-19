-- =============================================================================
-- poultry-employee-credit.test.sql  (migration 441)
--
-- SELF-CONTAINED AND SELF-ROLLING-BACK. Builds a throwaway company id that no
-- real company has, so nothing here can touch real data, and ends in ROLLBACK.
--
-- Proves the accounting the feature promises:
--   payroll keep 300 of 1,000 -> P&L payroll 1,000, cash out 700, credit 300
--   payout 300                -> cash out 300, NO new expense, credit 0
--   deposit / opening / wages owed behave as documented
--   over-payout, reversing paid-out credit and reopening paid-out payroll refused
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

DO $t$
DECLARE
    v_farm  text := gen_random_uuid()::text;
    v_staff integer;
    v_acct  integer;
    v_run   integer;
    v_item  integer;
    v_ded   integer;
    v_id    integer;
    v_dep   integer;
    v_n     numeric;
    v_ok    boolean;
    v_cash  numeric;
BEGIN
    INSERT INTO poultrystaff (farmid, firstname, lastname, salarytype, basepay, isactive, isdeleted, createdat)
    VALUES (v_farm, 'Test', 'Saver', 'Monthly', 1000, TRUE, FALSE, now())
    RETURNING poultrystaffid INTO v_staff;

    INSERT INTO poultrycashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance)
    VALUES (v_farm, 'Box', 'FarmCashBox', 5000, 5000)
    RETURNING poultrycashaccountid INTO v_acct;

    -- ---- payroll: 1,000 gross, keep 300 ------------------------------------
    INSERT INTO poultrypayrollruns (farmid, periodstart, periodend, paydate, poultrycashaccountid)
    VALUES (v_farm, '2026-10-01', '2026-10-31', '2026-10-31', v_acct)
    RETURNING poultrypayrollrunid INTO v_run;
    INSERT INTO poultrypayrollitems (poultrypayrollrunid, poultrystaffid, basicpay)
    VALUES (v_run, v_staff, 1000) RETURNING poultrypayrollitemid INTO v_item;

    v_ded := public.sppoultrypayrollitemdeduction_save(v_farm, v_item, 'EmployeeCredit', 300);
    UPDATE poultrypayrollruns r SET totalnetpay = (SELECT SUM(i.netpay) FROM poultrypayrollitems i WHERE i.poultrypayrollrunid = v_run)
    WHERE r.poultrypayrollrunid = v_run;

    SELECT netpay INTO v_n FROM poultrypayrollitems WHERE poultrypayrollitemid = v_item;
    IF v_n <> 700 THEN RAISE EXCEPTION 'net pay should be 700, got %', v_n; END IF;
    IF public.fnpoultryemployeecredit_balance(v_farm, v_staff) <> 0 THEN
        RAISE EXCEPTION 'a draft payroll must not move the credit';
    END IF;

    PERFORM public.sppoultrypayrollrun_approve(v_run, v_farm, 'test');
    IF public.fnpoultryemployeecredit_balance(v_farm, v_staff) <> 300 THEN
        RAISE EXCEPTION 'approve should credit 300';
    END IF;
    SELECT SUM(amount) INTO v_n FROM expense WHERE farmid = v_farm::uuid AND category = 'Payroll';
    IF v_n <> 1000 THEN RAISE EXCEPTION 'P&L payroll should be 1000 (gross), got %', v_n; END IF;
    SELECT SUM(amount) INTO v_n FROM public.fnpoultrypl_expenselines(v_farm, '2026-10-01', '2026-10-31');
    IF v_n <> 1000 THEN RAISE EXCEPTION 'P&L expense lines should be 1000, got %', v_n; END IF;

    PERFORM public.sppoultrypayrollrun_markpaid(v_run, v_farm, 'test');
    SELECT currentbalance INTO v_cash FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    IF v_cash <> 4300 THEN RAISE EXCEPTION 'cash should be 4300 after net pay, got %', v_cash; END IF;
    SELECT COALESCE(SUM(amount), 0) INTO v_n FROM public.sppoultrycashflow_rows(v_farm, NULL, NULL);
    IF v_n <> -700 THEN RAISE EXCEPTION 'cash flow after payroll should be -700, got %', v_n; END IF;

    -- ---- unapprove + re-approve round trip --------------------------------
    PERFORM public.sppoultrypayrollrun_unapprove(v_run, v_farm, 'test', 'check');
    IF public.fnpoultryemployeecredit_balance(v_farm, v_staff) <> 0 THEN
        RAISE EXCEPTION 'reopening should take the 300 back';
    END IF;
    IF EXISTS (SELECT 1 FROM expense WHERE farmid = v_farm::uuid AND sourcetype = 'PayrollEmployeeCredit') THEN
        RAISE EXCEPTION 'reopening should remove the top-up';
    END IF;
    IF (SELECT status FROM poultrypayrollitemdeductions WHERE poultrypayrollitemdeductionid = v_ded) <> 'Draft' THEN
        RAISE EXCEPTION 'deduction should be Draft again';
    END IF;
    PERFORM public.sppoultrypayrollrun_approve(v_run, v_farm, 'test');
    PERFORM public.sppoultrypayrollrun_markpaid(v_run, v_farm, 'test');
    IF public.fnpoultryemployeecredit_balance(v_farm, v_staff) <> 300 THEN
        RAISE EXCEPTION 're-approve should credit 300 again';
    END IF;

    -- ---- the other ways in -------------------------------------------------
    PERFORM public.sppoultryemployeecredit_add(v_farm, v_staff, 'OpeningBalance', 50, '2026-09-30');
    v_dep := public.sppoultryemployeecredit_add(v_farm, v_staff, 'Deposit', 100, '2026-11-01', v_acct);
    v_id  := public.sppoultryemployeecredit_add(v_farm, v_staff, 'WagesOwed', 25, '2026-11-02');
    IF public.fnpoultryemployeecredit_balance(v_farm, v_staff) <> 475 THEN
        RAISE EXCEPTION 'balance should be 475';
    END IF;
    SELECT currentbalance INTO v_cash FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    IF v_cash <> 4400 THEN RAISE EXCEPTION 'deposit should add 100 cash, got %', v_cash; END IF;
    SELECT SUM(amount) INTO v_n FROM expense WHERE farmid = v_farm::uuid AND category = 'Payroll';
    IF v_n <> 1025 THEN RAISE EXCEPTION 'wages owed should add 25 to payroll cost, got %', v_n; END IF;

    -- the wages-owed expense cannot be deleted from the Expenses page
    v_ok := FALSE;
    BEGIN
        DELETE FROM expense WHERE sourcetype = 'EmployeeCreditWages' AND sourceid = v_id;
    EXCEPTION WHEN OTHERS THEN v_ok := TRUE;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'wages-owed expense should be protected'; END IF;

    -- ---- payout ------------------------------------------------------------
    v_ok := FALSE;
    BEGIN
        PERFORM public.sppoultryemployeecredit_payout(v_farm, v_staff, 476, v_acct, '2026-11-05');
    EXCEPTION WHEN OTHERS THEN v_ok := TRUE;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION 'paying out more than held must be refused'; END IF;

    SELECT SUM(amount) INTO v_n FROM expense WHERE farmid = v_farm::uuid;
    PERFORM public.sppoultryemployeecredit_payout(v_farm, v_staff, 475, v_acct, '2026-11-05');
    IF (SELECT SUM(amount) FROM expense WHERE farmid = v_farm::uuid) <> v_n THEN
        RAISE EXCEPTION 'a payout must not create an expense';
    END IF;
    IF public.fnpoultryemployeecredit_balance(v_farm, v_staff) <> 0 THEN
        RAISE EXCEPTION 'balance should be 0 after full payout';
    END IF;
    SELECT currentbalance INTO v_cash FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    IF v_cash <> 3925 THEN RAISE EXCEPTION 'cash should be 3925, got %', v_cash; END IF;
    -- Cash Flow agrees with the account: 5000 - 3925 = 1075 net out
    SELECT COALESCE(SUM(amount), 0) INTO v_n FROM public.sppoultrycashflow_rows(v_farm, NULL, NULL);
    IF v_n <> -1075 THEN RAISE EXCEPTION 'cash flow net should be -1075, got %', v_n; END IF;

    -- ---- refusals once the money is gone ---------------------------------
    v_ok := FALSE;
    BEGIN PERFORM public.sppoultryemployeecredit_reverse(v_farm, v_dep, 'mistake');
    EXCEPTION WHEN OTHERS THEN v_ok := TRUE; END;
    IF NOT v_ok THEN RAISE EXCEPTION 'reversing paid-out credit must be refused'; END IF;

    v_ok := FALSE;
    BEGIN PERFORM public.sppoultrypayrollrun_unapprove(v_run, v_farm, 'test', 'x');
    EXCEPTION WHEN OTHERS THEN v_ok := TRUE; END;
    IF NOT v_ok THEN RAISE EXCEPTION 'reopening payroll whose savings were paid out must be refused'; END IF;

    -- ---- reverse the payout, then the wages owed --------------------------
    PERFORM public.sppoultryemployeecredit_reverse(v_farm,
        (SELECT poultryemployeecreditid FROM poultryemployeecredits
          WHERE farmid = v_farm AND entrytype = 'Payout'), 'paid wrong person');
    IF public.fnpoultryemployeecredit_balance(v_farm, v_staff) <> 475 THEN
        RAISE EXCEPTION 'payout reversal should restore 475';
    END IF;
    SELECT currentbalance INTO v_cash FROM poultrycashaccounts WHERE poultrycashaccountid = v_acct;
    IF v_cash <> 4400 THEN RAISE EXCEPTION 'payout reversal should restore cash, got %', v_cash; END IF;
    SELECT COALESCE(SUM(amount), 0) INTO v_n FROM public.sppoultrycashflow_rows(v_farm, NULL, NULL);
    IF v_n <> -600 THEN RAISE EXCEPTION 'cash flow net should be -600 after reversal, got %', v_n; END IF;

    PERFORM public.sppoultryemployeecredit_reverse(v_farm, v_id, 'typo');
    IF EXISTS (SELECT 1 FROM expense WHERE sourcetype = 'EmployeeCreditWages' AND sourceid = v_id) THEN
        RAISE EXCEPTION 'reversing wages owed should remove its expense';
    END IF;

    v_ok := FALSE;
    BEGIN PERFORM public.sppoultryemployeecredit_reverse(v_farm,
        (SELECT poultryemployeecreditid FROM poultryemployeecredits
          WHERE farmid = v_farm AND entrytype = 'PayrollSaving' AND status = 'Posted'), 'x');
    EXCEPTION WHEN OTHERS THEN v_ok := TRUE; END;
    IF NOT v_ok THEN RAISE EXCEPTION 'payroll savings must only be undone by reopening payroll'; END IF;

    -- ---- readers -----------------------------------------------------------
    IF (SELECT balance FROM public.sppoultryemployeecredit_balances(v_farm)) <> 450 THEN
        RAISE EXCEPTION 'balances reader disagrees';
    END IF;
    IF (SELECT totalheld FROM public.sppoultryemployeecredit_total(v_farm)) <> 450 THEN
        RAISE EXCEPTION 'total reader disagrees';
    END IF;
    IF (SELECT runningbalance FROM public.sppoultryemployeecredit_getall(v_farm, v_staff) LIMIT 1) <> 450 THEN
        RAISE EXCEPTION 'statement running balance disagrees';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.fnpoultryfa_positions(v_farm, '2026-01-01', '2026-12-31')
                    WHERE positiontype = 'EmployeeCreditLiability') THEN
        RAISE EXCEPTION 'Financial Activity has no Employee Credit position';
    END IF;
    PERFORM * FROM public.fnpoultryfa_events(v_farm, '2026-01-01', '2026-12-31');
    PERFORM * FROM public.sppoultrycashflow_detail(v_farm, NULL, NULL);

    RAISE NOTICE 'poultry-employee-credit: all checks passed';
END
$t$;

ROLLBACK;
