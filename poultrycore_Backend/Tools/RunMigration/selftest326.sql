-- Self-test for migration 326 (Restaurant payroll + staff loans). Append to the
-- migration and run, or run on its own after 326; it always ends by raising so
-- everything rolls back. "SELFTEST PASSED" in the error is the success signal.
--
-- The story: Ama (basic 2,000) gets a 600 advance (+60 interest), repaid 200 per
-- payroll; Kofi (1,500) is paid too and gets a loan that is reversed. Every
-- balance, the ledger, Cash Flow, the P&L, the profit-vs-cash bridge, the
-- closed-day lock and every guard are checked.
DO $$
DECLARE
    f TEXT := '__probe326__';
    v_ama INT; v_kofi INT; v_cash INT; v_momo INT;
    v_loan INT; v_loan2 INT; v_run INT; v_run2 INT; v_run3 INT; v_line INT; v_line2 INT; v_rep INT;
    v_n NUMERIC; v_n2 NUMERIC; v_i INT; v_failed BOOLEAN; v_checks INT := 0; r RECORD;
BEGIN
    INSERT INTO restaurantstaff (farmid, firstname, lastname, role, salarytype, basepay)
    VALUES (f, 'Ama', 'Mensah', 'Waiter', 'Monthly', 2000) RETURNING restaurantstaffid INTO v_ama;
    INSERT INTO restaurantstaff (farmid, firstname, lastname, role, salarytype, basepay)
    VALUES (f, 'Kofi', 'Owusu', 'Chef', 'Monthly', 1500) RETURNING restaurantstaffid INTO v_kofi;
    v_cash := fnrestaurant_default_account(f, 'Cash');
    v_momo := fnrestaurant_default_account(f, 'MobileMoney');

    -- 1. guards on create
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_staffloan_create(f, v_ama, 'SalaryAdvance', 600, 60, 'PayrollDeduction', 0, NULL, NULL, NULL, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1a: payroll method without a deduction accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_staffloan_create(f, 999999, 'SalaryAdvance', 600, 0, 'Cash', 0, NULL, NULL, NULL, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1b: unknown staff accepted'; END IF;
    v_checks := v_checks + 2;

    -- 2. draft: numbered, owes nothing yet
    v_loan := sprestaurant_staffloan_create(f, v_ama, 'SalaryAdvance', 600, 60, 'PayrollDeduction', 200, NULL, NULL, NULL, 'probe');
    SELECT * INTO r FROM sprestaurant_staffloan_list(f) WHERE staffloanid = v_loan;
    IF r.status <> 'Draft' OR r.loannumber <> 'SA-0001' OR r.outstandingbalance <> 0 OR r.staffname <> 'Ama Mensah' THEN
        RAISE EXCEPTION 'FAIL 2: %', row_to_json(r); END IF;
    v_checks := v_checks + 1;

    -- 3. pay out: no future date; principal only leaves the Main Cash Box
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_staffloan_disburse(f, v_loan, NULL, CURRENT_DATE + 1, NULL, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3a: future payout accepted'; END IF;
    PERFORM sprestaurant_staffloan_disburse(f, v_loan, NULL, CURRENT_DATE, 'ADV-1', 'probe');
    SELECT * INTO r FROM sprestaurant_staffloan_list(f) WHERE staffloanid = v_loan;
    IF r.status <> 'Active' OR r.outstandingbalance <> 660 OR r.cashaccountid <> v_cash THEN RAISE EXCEPTION 'FAIL 3b: %', row_to_json(r); END IF;
    IF (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_cash) <> -600 THEN RAISE EXCEPTION 'FAIL 3c: cash box'; END IF;
    v_checks := v_checks + 3;

    -- 4. MoMo repayment with no account lands in the MoMo wallet; interest first
    v_rep := sprestaurant_staffloanrepayment_record(f, v_loan, 60, 'MoMo', NULL, CURRENT_DATE, NULL, NULL, 'probe');
    IF (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_momo) <> 60 THEN RAISE EXCEPTION 'FAIL 4a: momo'; END IF;
    SELECT * INTO r FROM sprestaurant_staffloan_list(f) WHERE staffloanid = v_loan;
    IF r.outstandingbalance <> 600 OR r.totalinterestrepaid <> 60 THEN RAISE EXCEPTION 'FAIL 4b: %', row_to_json(r); END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_staffloanrepayment_record(f, v_loan, 10, 'Payroll', NULL, CURRENT_DATE, NULL, NULL, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4c: manual payroll repayment accepted'; END IF;
    v_checks := v_checks + 3;

    -- 5. payroll line with the suggested deduction; add-all adds Kofi
    SELECT * INTO r FROM sprestaurant_staffloan_eligible(f, v_ama, NULL);
    IF r.suggesteddeduction <> 200 OR r.available <> 600 THEN RAISE EXCEPTION 'FAIL 5a: %', row_to_json(r); END IF;
    v_run := sprestaurant_payrollrun_create(f, date_trunc('month', CURRENT_DATE)::DATE, CURRENT_DATE, CURRENT_DATE, NULL, NULL, 'probe');
    v_line := sprestaurant_payrollline_save(f, v_run, v_ama, 2000, 100, 0, 0, 50, 'Cash', NULL,
                jsonb_build_array(jsonb_build_object('loanId', v_loan, 'amount', 200)), 'probe');
    SELECT grosspay, netpay INTO v_n, v_n2 FROM restaurantpayrolllines WHERE payrolllineid = v_line;
    IF v_n <> 2100 OR v_n2 <> 1850 THEN RAISE EXCEPTION 'FAIL 5b: gross % net %', v_n, v_n2; END IF;
    IF sprestaurant_payrollline_save(f, v_run, v_ama, 2000, 100, 0, 0, 50, 'Cash', NULL, NULL, 'probe') <> v_line
       OR (SELECT loandeductions FROM restaurantpayrolllines WHERE payrolllineid = v_line) <> 200 THEN
        RAISE EXCEPTION 'FAIL 5c: re-save lost the loan deduction'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_payrollline_save(f, v_run, v_ama, 2000, 100, 0, 0, 50, 'Cash', NULL,
                jsonb_build_array(jsonb_build_object('loanId', v_loan, 'amount', 700)), 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 5d: over-deduction accepted'; END IF;
    IF sprestaurant_payrollrun_addallstaff(f, v_run, 'probe') <> 1 THEN RAISE EXCEPTION 'FAIL 5e: add-all'; END IF;
    SELECT totalgross, totalnet INTO v_n, v_n2 FROM restaurantpayrollruns WHERE payrollrunid = v_run;
    IF v_n <> 3600 OR v_n2 <> 3350 THEN RAISE EXCEPTION 'FAIL 5f: run gross % net %', v_n, v_n2; END IF;
    v_checks := v_checks + 6;

    -- 6. claims across draft runs; another staff member's loan; remove + delete
    v_run2 := sprestaurant_payrollrun_create(f, CURRENT_DATE, CURRENT_DATE, CURRENT_DATE, NULL, NULL, 'probe');
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_payrollline_save(f, v_run2, v_ama, 2000, 0, 0, 0, 0, 'Cash', NULL,
                jsonb_build_array(jsonb_build_object('loanId', v_loan, 'amount', 450)), 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6a: 450 accepted with 200 claimed elsewhere'; END IF;
    v_line2 := sprestaurant_payrollline_save(f, v_run2, v_ama, 2000, 0, 0, 0, 0, 'Cash', NULL,
                jsonb_build_array(jsonb_build_object('loanId', v_loan, 'amount', 400)), 'probe');
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_payrollline_save(f, v_run2, v_kofi, 1500, 0, 0, 0, 0, 'Cash', NULL,
                jsonb_build_array(jsonb_build_object('loanId', v_loan, 'amount', 10)), 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6b: deducted another staff member''s loan'; END IF;
    PERFORM sprestaurant_payrollline_save(f, v_run2, v_ama, 2000, 0, 0, 0, 0, 'Cash', NULL, '[]'::JSONB, 'probe');
    IF EXISTS (SELECT 1 FROM restaurantpayrolldeductions WHERE payrollrunid = v_run2) THEN RAISE EXCEPTION 'FAIL 6c: [] kept deduction'; END IF;
    PERFORM sprestaurant_payrollline_delete(f, v_line2);
    PERFORM sprestaurant_payrollrun_delete(f, v_run2);
    v_checks := v_checks + 3;

    -- 7. a loan on a draft payroll cannot be reversed
    PERFORM sprestaurant_staffloanrepayment_reverse(f, v_rep, 'test', 'probe');   -- clear the cash repayment first
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_staffloan_reverse(f, v_loan, 'probe', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7: reversed a loan with a draft payroll deduction'; END IF;
    IF (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_momo) <> 0 THEN RAISE EXCEPTION 'FAIL 7b: momo after reversal'; END IF;
    v_checks := v_checks + 2;
    -- re-take the cash repayment so the rest of the story has it
    v_rep := sprestaurant_staffloanrepayment_record(f, v_loan, 60, 'MoMo', NULL, CURRENT_DATE, NULL, NULL, 'probe');

    -- 8. approve: repayment, no cash
    SELECT currentbalance INTO v_n FROM restaurantcashaccounts WHERE cashaccountid = v_cash;
    IF sprestaurant_payrollrun_approve(f, v_run, 'probe') <> 1 THEN RAISE EXCEPTION 'FAIL 8a'; END IF;
    IF (SELECT outstandingbalance FROM restaurantstaffloans WHERE staffloanid = v_loan) <> 400 THEN RAISE EXCEPTION 'FAIL 8b'; END IF;
    IF (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_cash) <> v_n THEN RAISE EXCEPTION 'FAIL 8c: approve moved cash'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_staffloanrepayment_reverse(f,
            (SELECT repaymentid FROM restaurantstaffloanrepayments WHERE payrollrunid = v_run AND status = 'Posted'), 'x', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 8d: payroll repayment reversed outside payroll'; END IF;
    v_checks := v_checks + 4;

    -- 9. reopen and approve again
    PERFORM sprestaurant_payrollrun_unapprove(f, v_run, 'fix', 'probe');
    IF (SELECT outstandingbalance FROM restaurantstaffloans WHERE staffloanid = v_loan) <> 600 THEN RAISE EXCEPTION 'FAIL 9a'; END IF;
    PERFORM sprestaurant_payrollrun_approve(f, v_run, 'probe');
    IF (SELECT outstandingbalance FROM restaurantstaffloans WHERE staffloanid = v_loan) <> 400 THEN RAISE EXCEPTION 'FAIL 9b'; END IF;
    v_checks := v_checks + 2;

    -- 10. mark paid: net 3,350 leaves the Main Cash Box; a paid run cannot be cancelled
    PERFORM sprestaurant_payrollrun_markpaid(f, v_run, CURRENT_DATE, NULL, 'probe');
    IF (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_cash) <> -600 - 3350 THEN
        RAISE EXCEPTION 'FAIL 10a: cash box %', (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_cash); END IF;
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_payrollrun_cancel(f, v_run, 'late', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 10b: paid run cancelled'; END IF;
    v_checks := v_checks + 2;

    -- 11. cash flow groups
    SELECT COALESCE(SUM(amount), 0) INTO v_n FROM sprestaurantcashflow_rows(f) WHERE flowgroup LIKE 'EmployeeLoan%';
    IF v_n <> -600 + 60 - 60 + 60 THEN RAISE EXCEPTION 'FAIL 11a: staff loan flow %', v_n; END IF;
    IF NOT EXISTS (SELECT 1 FROM sprestaurantcashflow_detail(f) WHERE sourcetype = 'Payroll' AND flowgroup = 'OperatingOut'
                    AND amount = -3350 AND category = 'Staff wages (net pay)') THEN RAISE EXCEPTION 'FAIL 11b: payroll row'; END IF;
    v_checks := v_checks + 2;

    -- 12. P&L: gross wages, interest income, breakdown adds up
    IF (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'staff_wages') <> -3600 THEN
        RAISE EXCEPTION 'FAIL 12a: wages'; END IF;
    IF (SELECT amount FROM sprestaurant_report_pnl_lines(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'staff_loan_interest') <> 60 THEN
        RAISE EXCEPTION 'FAIL 12b: interest'; END IF;
    SELECT expenses_total INTO v_n FROM sprestaurant_report_pnl_summary(f, CURRENT_DATE, CURRENT_DATE);
    SELECT COALESCE(SUM(expense_total), 0) INTO v_n2 FROM sprestaurant_report_pnl_expenses(f, CURRENT_DATE, CURRENT_DATE);
    IF v_n <> v_n2 OR v_n <> 3540 THEN RAISE EXCEPTION 'FAIL 12c: expenses_total % vs breakdown %', v_n, v_n2; END IF;
    v_checks := v_checks + 3;

    -- 13. the bridge reconciles
    SELECT amount INTO v_n FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'check';
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 13: bridge unexplained %', v_n; END IF;
    v_checks := v_checks + 1;

    -- 14. Kofi's loan paid out and reversed; bridge still zero
    v_loan2 := sprestaurant_staffloan_create(f, v_kofi, 'EmployeeLoan', 300, 0, 'Cash', 0, NULL, NULL, NULL, 'probe', TRUE, NULL, CURRENT_DATE);
    PERFORM sprestaurant_staffloan_reverse(f, v_loan2, 'wrong person', 'probe');
    IF (SELECT status FROM restaurantstaffloans WHERE staffloanid = v_loan2) <> 'Reversed'
       OR (SELECT currentbalance FROM restaurantcashaccounts WHERE cashaccountid = v_cash) <> -3950 THEN RAISE EXCEPTION 'FAIL 14a'; END IF;
    SELECT amount INTO v_n FROM sprestaurant_report_cash_profit_bridge(f, CURRENT_DATE, CURRENT_DATE) WHERE linekey = 'check';
    IF v_n <> 0 THEN RAISE EXCEPTION 'FAIL 14b: bridge %', v_n; END IF;
    v_checks := v_checks + 2;

    -- 15. every account: balance = its ledger
    FOR r IN SELECT a.name, a.currentbalance, COALESCE(SUM(t.amount), 0) AS led
               FROM restaurantcashaccounts a LEFT JOIN restaurantcashtransactions t ON t.cashaccountid = a.cashaccountid
              WHERE a.farmid = f GROUP BY a.cashaccountid LOOP
        IF r.currentbalance <> r.led THEN RAISE EXCEPTION 'FAIL 15: % % vs ledger %', r.name, r.currentbalance, r.led; END IF;
    END LOOP;
    v_checks := v_checks + 1;

    -- 16. cancelling an approved run restores the loan
    v_run3 := sprestaurant_payrollrun_create(f, CURRENT_DATE, CURRENT_DATE, CURRENT_DATE, NULL, NULL, 'probe');
    PERFORM sprestaurant_payrollline_save(f, v_run3, v_ama, 2000, 0, 0, 0, 0, 'Cash', NULL,
            jsonb_build_array(jsonb_build_object('loanId', v_loan, 'amount', 200)), 'probe');
    PERFORM sprestaurant_payrollrun_approve(f, v_run3, 'probe');
    PERFORM sprestaurant_payrollrun_cancel(f, v_run3, 'duplicate', 'probe');
    IF (SELECT outstandingbalance FROM restaurantstaffloans WHERE staffloanid = v_loan) <> 400 THEN RAISE EXCEPTION 'FAIL 16'; END IF;
    v_checks := v_checks + 1;

    -- 17. reports and summary
    SELECT * INTO r FROM sprestaurant_staffloan_summary(f);
    IF r.totaloutstanding <> 400 OR r.staffwithloans <> 1 OR r.totaldisbursed <> 600 OR r.interestearned <> 60 THEN
        RAISE EXCEPTION 'FAIL 17a: %', row_to_json(r); END IF;
    SELECT outstanding, repaidpayrollinperiod INTO v_n, v_n2 FROM sprestaurant_staffloan_staffreport(f) WHERE restaurantstaffid = v_ama;
    IF v_n <> 400 OR v_n2 <> 200 THEN RAISE EXCEPTION 'FAIL 17b: % %', v_n, v_n2; END IF;
    SELECT COUNT(*), SUM(netpay) INTO v_i, v_n FROM sprestaurant_payroll_report(f, CURRENT_DATE, CURRENT_DATE);
    IF v_i <> 2 OR v_n <> 3350 THEN RAISE EXCEPTION 'FAIL 17c: payroll report % %', v_i, v_n; END IF;
    v_checks := v_checks + 3;

    -- 18. staff delete guard
    v_failed := FALSE;
    BEGIN DELETE FROM restaurantstaff WHERE restaurantstaffid = v_ama;
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 18: deleted staff with an open loan'; END IF;
    v_checks := v_checks + 1;

    -- 19. closed-day lock: close yesterday, then nothing can be dated yesterday
    PERFORM sprestaurant_dailyclosing_close(f, CURRENT_DATE - 1, NULL, 'probe');
    v_failed := FALSE;
    BEGIN PERFORM sprestaurant_staffloanrepayment_record(f, v_loan, 10, 'Cash', NULL, CURRENT_DATE - 1, NULL, NULL, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 19: repayment into a closed day accepted'; END IF;
    v_checks := v_checks + 1;

    RAISE EXCEPTION 'SELFTEST PASSED: % checks (rolled back)', v_checks;
END $$;
