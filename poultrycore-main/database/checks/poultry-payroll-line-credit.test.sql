-- =============================================================================
-- poultry-payroll-line-credit.test.sql  (migration 442)
--
-- SELF-CONTAINED AND SELF-ROLLING-BACK. Uses a throwaway company id no real
-- company has, and ends in ROLLBACK.
--
-- Proves:
--   * one upsert sets other deductions + keep-as-credit; net pay follows
--   * changing / removing the kept amount moves net pay back (the 306
--     reconcile used to swallow it into "Other deduction")
--   * deleting a structured deduction lowers the total (same bug)
--   * old-style callers (p_deductions = line total) still work
--   * negative net is refused; a Reopened run's line can be edited
--   * keep-as-credit from the line form posts on approval exactly like 441
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
    v_n     numeric;
    v_ok    boolean;
    i       record;
BEGIN
    INSERT INTO poultrystaff (farmid, firstname, lastname, salarytype, basepay, isactive, isdeleted, createdat)
    VALUES (v_farm, 'Test', 'Keeper', 'Monthly', 1000, TRUE, FALSE, now())
    RETURNING poultrystaffid INTO v_staff;
    INSERT INTO poultrycashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance)
    VALUES (v_farm, 'Box', 'FarmCashBox', 5000, 5000)
    RETURNING poultrycashaccountid INTO v_acct;
    INSERT INTO poultrypayrollruns (farmid, periodstart, periodend, paydate, poultrycashaccountid)
    VALUES (v_farm, '2026-10-01', '2026-10-31', '2026-10-31', v_acct)
    RETURNING poultrypayrollrunid INTO v_run;

    -- ---- 1. new line: other 100, keep 300 ---------------------------------
    SELECT * INTO i FROM public.sppoultrypayrollitem_upsert(v_run, v_farm, v_staff, 1000, 0, 0, 0,
        p_otherdeductions => 100, p_employeecredit => 300);
    v_item := i.poultrypayrollitemid;
    IF i.deductions <> 400 OR i.netpay <> 600 THEN
        RAISE EXCEPTION '1: expected deductions 400 / net 600, got % / %', i.deductions, i.netpay;
    END IF;
    IF (SELECT count(*) FROM poultrypayrollitemdeductions
        WHERE poultrypayrollitemid = v_item AND deductiontype = 'EmployeeCredit' AND amount = 300) <> 1 THEN
        RAISE EXCEPTION '1: one 300 employee-credit row expected';
    END IF;
    RAISE NOTICE 'ok 1 new line with keep-as-credit';

    -- ---- 2. lower keep to 200, then remove it -------------------------------
    SELECT * INTO i FROM public.sppoultrypayrollitem_upsert(v_run, v_farm, v_staff, 1000, 0, 0, 0,
        p_otherdeductions => 100, p_employeecredit => 200);
    IF i.netpay <> 700 THEN RAISE EXCEPTION '2a: net should be 700, got %', i.netpay; END IF;
    SELECT * INTO i FROM public.sppoultrypayrollitem_upsert(v_run, v_farm, v_staff, 1000, 0, 0, 0,
        p_otherdeductions => 100, p_employeecredit => 0);
    IF i.netpay <> 900 THEN RAISE EXCEPTION '2b: net should be 900 after removing the keep, got %', i.netpay; END IF;
    IF EXISTS (SELECT 1 FROM poultrypayrollitemdeductions WHERE poultrypayrollitemid = v_item AND deductiontype = 'EmployeeCredit') THEN
        RAISE EXCEPTION '2b: credit row should be gone';
    END IF;
    RAISE NOTICE 'ok 2 changing / removing the kept amount moves net pay';

    -- ---- 3. NULL credit leaves the dialog's rows alone; delete lowers total --
    v_ded := public.sppoultrypayrollitemdeduction_save(v_farm, v_item, 'OtherDeduction', 50);
    SELECT netpay INTO v_n FROM poultrypayrollitems WHERE poultrypayrollitemid = v_item;
    IF v_n <> 850 THEN RAISE EXCEPTION '3a: net should be 850, got %', v_n; END IF;
    v_ded := public.sppoultrypayrollitemdeduction_save(v_farm, v_item, 'EmployeeCredit', 250);
    SELECT * INTO i FROM public.sppoultrypayrollitem_upsert(v_run, v_farm, v_staff, 1000, 0, 0, 0,
        p_otherdeductions => 100);                         -- p_employeecredit NULL
    IF i.netpay <> 600 THEN RAISE EXCEPTION '3b: NULL keep must leave the 250 alone, net %', i.netpay; END IF;
    PERFORM public.sppoultrypayrollitemdeduction_delete(v_farm, v_ded);
    SELECT netpay INTO v_n FROM poultrypayrollitems WHERE poultrypayrollitemid = v_item;
    IF v_n <> 850 THEN RAISE EXCEPTION '3c: deleting a deduction must give the money back, net %', v_n; END IF;
    RAISE NOTICE 'ok 3 deleting a deduction lowers the total (306 reconcile bug)';

    -- ---- 4. old-style caller: p_deductions is the line total ----------------
    SELECT * INTO i FROM public.sppoultrypayrollitem_upsert(v_run, v_farm, v_staff, 1000, 0, 0, 0, 450, 'Cash', NULL);
    IF i.deductions <> 450 OR i.netpay <> 550 THEN
        RAISE EXCEPTION '4: old-style total 450 should stand, got % / %', i.deductions, i.netpay;
    END IF;
    IF (SELECT legacydeductions FROM poultrypayrollitems WHERE poultrypayrollitemid = v_item) <> 400 THEN
        RAISE EXCEPTION '4: legacy should be 450 - 50 structured = 400';
    END IF;
    RAISE NOTICE 'ok 4 old-style total still works';

    -- ---- 5. negative net refused -------------------------------------------
    v_ok := FALSE;
    BEGIN
        PERFORM public.sppoultrypayrollitem_upsert(v_run, v_farm, v_staff, 1000, 0, 0, 0,
            p_otherdeductions => 500, p_employeecredit => 600);
    EXCEPTION WHEN OTHERS THEN v_ok := TRUE;
    END;
    IF NOT v_ok THEN RAISE EXCEPTION '5: negative net pay must be refused'; END IF;
    RAISE NOTICE 'ok 5 negative net refused';

    -- ---- 6. approve posts the kept amount; reopen; edit the reopened line ----
    SELECT * INTO i FROM public.sppoultrypayrollitem_upsert(v_run, v_farm, v_staff, 1000, 0, 0, 0,
        p_otherdeductions => 0, p_employeecredit => 300);
    PERFORM public.sppoultrypayrollrun_approve(v_run, v_farm, 'test');
    IF public.fnpoultryemployeecredit_balance(v_farm, v_staff) <> 300 THEN
        RAISE EXCEPTION '6a: approve should credit 300, got %', public.fnpoultryemployeecredit_balance(v_farm, v_staff);
    END IF;
    PERFORM public.sppoultrypayrollrun_unapprove(v_run, v_farm, 'test reopen', 'test');
    IF public.fnpoultryemployeecredit_balance(v_farm, v_staff) <> 0 THEN
        RAISE EXCEPTION '6b: reopen should take the credit back';
    END IF;
    SELECT * INTO i FROM public.sppoultrypayrollitem_upsert(v_run, v_farm, v_staff, 1000, 0, 0, 0,
        p_otherdeductions => 0, p_employeecredit => 100);
    -- 1000 - 50 (the step-3 Other deduction still on the line) - 100 kept
    IF i.netpay <> 850 THEN RAISE EXCEPTION '6c: reopened line edit, net should be 850, got %', i.netpay; END IF;
    PERFORM public.sppoultrypayrollrun_approve(v_run, v_farm, 'test');
    IF public.fnpoultryemployeecredit_balance(v_farm, v_staff) <> 100 THEN
        RAISE EXCEPTION '6d: re-approve should credit 100';
    END IF;
    RAISE NOTICE 'ok 6 approve / reopen / edit / re-approve';

    RAISE NOTICE 'poultry-payroll-line-credit: all checks passed';
END
$t$;

ROLLBACK;
