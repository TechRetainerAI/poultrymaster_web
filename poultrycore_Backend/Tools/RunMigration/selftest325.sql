-- Self-test for migration 325 (Hotel employee loans + payroll). Append to the
-- migration and run, or run on its own after 325; it always ends by raising so
-- everything rolls back. "SELFTEST PASSED" in the error is the success signal.
--
-- The story: Ama earns 2,000 a month. She gets a 600 advance (+60 interest),
-- repaid 200 per payroll. We check every balance, the ledger, Cash Flow, the
-- P&L, and that each guard refuses what it should.
DO $$
DECLARE
    f        text := '__probe325__';
    v_ama    int;  v_kofi int;
    v_main   int;  v_pay int;
    v_loan   int;  v_loan2 int;
    v_run    int;  v_run2 int; v_run3 int;
    v_item   int;  v_item2 int;
    v_rep    int;
    v_n      numeric; v_n2 numeric; v_i int; v_t text;
    v_checks int := 0;
    v_failed boolean;
    r        record;
BEGIN
    INSERT INTO hotelstaff (farmid, firstname, lastname, role, department, salaryamount)
    VALUES (f, 'Ama', 'Mensah', 'Receptionist', 'Front Desk', 2000) RETURNING hotelstaffid INTO v_ama;
    INSERT INTO hotelstaff (farmid, firstname, lastname, role, department, salaryamount)
    VALUES (f, 'Kofi', 'Owusu', 'Porter', 'Front Desk', 1500) RETURNING hotelstaffid INTO v_kofi;
    INSERT INTO hotelcashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance)
    VALUES (f, 'Main Cash', 'Cash', 5000, 5000) RETURNING hotelcashaccountid INTO v_main;

    -- 1. Guards on create
    v_failed := FALSE;
    BEGIN PERFORM sphotelemployeeloan_create(f, v_ama, NULL, 'SalaryAdvance', 600, 60, 'PayrollDeduction', 0);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1a: payroll method with no deduction was accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelemployeeloan_create(f, 999999, NULL, 'SalaryAdvance', 600, 0, 'Cash', 0);
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 1b: unknown staff was accepted'; END IF;
    v_checks := v_checks + 2;

    -- 2. Create a Draft: numbered, nothing owed yet, no cash moved
    v_loan := sphotelemployeeloan_create(f, v_ama, NULL, 'SalaryAdvance', 600, 60, 'PayrollDeduction', 200);
    SELECT * INTO r FROM sphotelemployeeloan_getbyid(v_loan, f);
    IF r.status <> 'Draft' OR r.loannumber <> 'EL-0001' OR r.outstandingbalance <> 0 OR r.staffname <> 'Ama Mensah' THEN
        RAISE EXCEPTION 'FAIL 2: draft %', row_to_json(r); END IF;
    v_checks := v_checks + 1;

    -- 3. Disburse needs an account; then only the PRINCIPAL leaves it
    v_failed := FALSE;
    BEGIN PERFORM sphotelemployeeloan_disburse(v_loan, f, NULL, now(), NULL, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 3a: disbursed with no account'; END IF;
    PERFORM sphotelemployeeloan_disburse(v_loan, f, v_main, now(), 'ADV-1', 'probe');
    SELECT * INTO r FROM sphotelemployeeloan_getbyid(v_loan, f);
    IF r.status <> 'Active' OR r.outstandingbalance <> 660 OR r.cashaccountname <> 'Main Cash' THEN
        RAISE EXCEPTION 'FAIL 3b: after disburse %', row_to_json(r); END IF;
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 4400 THEN
        RAISE EXCEPTION 'FAIL 3c: main balance % (want 4400: principal only)',
            (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main); END IF;
    IF NOT EXISTS (SELECT 1 FROM hotelcashtransactions WHERE farmid = f AND sourcetype = 'EmployeeLoanDisbursement'
                   AND txntype = 'Debit' AND amount = 600 AND sourceid = v_loan) THEN
        RAISE EXCEPTION 'FAIL 3d: no disbursement ledger row'; END IF;
    v_checks := v_checks + 4;

    -- 4. Cash repayment of 60: interest first, money into Main
    v_rep := sphotelemployeeloanrepayment_record(v_loan, f, 60, 'Cash', v_main, now(), NULL, 'cash', 'probe');
    SELECT * INTO r FROM sphotelemployeeloan_getbyid(v_loan, f);
    IF r.outstandingbalance <> 600 OR r.totalinterestrepaid <> 60 OR r.totalprincipalrepaid <> 0 THEN
        RAISE EXCEPTION 'FAIL 4a: after cash repay %', row_to_json(r); END IF;
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 4460 THEN
        RAISE EXCEPTION 'FAIL 4b: main balance after repay'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelemployeeloanrepayment_record(v_loan, f, 10, 'Cash', NULL, now(), NULL, NULL, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4c: cash repayment without account accepted'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelemployeeloanrepayment_record(v_loan, f, 10, 'Payroll', NULL, now(), NULL, NULL, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 4d: manual payroll repayment accepted'; END IF;
    v_checks := v_checks + 4;

    -- 5. Payroll line with the suggested deduction
    SELECT * INTO r FROM sphotelemployeeloan_eligible(f, v_ama, NULL);
    IF r.suggesteddeduction <> 200 OR r.available <> 600 THEN RAISE EXCEPTION 'FAIL 5a: eligible %', row_to_json(r); END IF;
    INSERT INTO hotelpayrollruns (farmid, periodstart, periodend, paydate, status)
    VALUES (f, DATE '2026-09-01', DATE '2026-09-30', DATE '2026-09-30', 'Draft') RETURNING hotelpayrollrunid INTO v_run;
    v_item := sphotelpayrollitem_save(f, v_run, v_ama, NULL, NULL, 2000, 0, 0, 0, 50, 'Cash', NULL,
                                      jsonb_build_array(jsonb_build_object('loanId', v_loan, 'amount', 200)), 'probe');
    SELECT deductions, netpay INTO v_n, v_n2 FROM hotelpayrollitems WHERE hotelpayrollitemid = v_item;
    IF v_n <> 250 OR v_n2 <> 1750 THEN RAISE EXCEPTION 'FAIL 5b: line deductions % net %', v_n, v_n2; END IF;
    SELECT totalgrosspay, totalnetpay INTO v_n, v_n2 FROM hotelpayrollruns WHERE hotelpayrollrunid = v_run;
    IF v_n <> 2000 OR v_n2 <> 1750 THEN RAISE EXCEPTION 'FAIL 5c: run gross % net %', v_n, v_n2; END IF;
    -- saving the line again with NULL loans keeps the deduction and the same item id
    IF sphotelpayrollitem_save(f, v_run, v_ama, NULL, NULL, 2000, 0, 0, 100, 50, 'Cash', NULL, NULL, 'probe') <> v_item THEN
        RAISE EXCEPTION 'FAIL 5d: item id changed on re-save'; END IF;
    SELECT deductions, netpay INTO v_n, v_n2 FROM hotelpayrollitems WHERE hotelpayrollitemid = v_item;
    IF v_n <> 250 OR v_n2 <> 1850 THEN RAISE EXCEPTION 'FAIL 5e: after re-save deductions % net %', v_n, v_n2; END IF;
    v_checks := v_checks + 5;

    -- 6. Over-claiming is refused, here and across two draft runs
    v_failed := FALSE;
    BEGIN PERFORM sphotelpayrollitem_save(f, v_run, v_ama, NULL, NULL, 2000, 0, 0, 100, 50, 'Cash', NULL,
                                         jsonb_build_array(jsonb_build_object('loanId', v_loan, 'amount', 700)), 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6a: deduction above the balance accepted'; END IF;
    INSERT INTO hotelpayrollruns (farmid, periodstart, periodend, paydate, status)
    VALUES (f, DATE '2026-10-01', DATE '2026-10-31', DATE '2026-10-31', 'Draft') RETURNING hotelpayrollrunid INTO v_run2;
    v_failed := FALSE;
    BEGIN PERFORM sphotelpayrollitem_save(f, v_run2, v_ama, NULL, NULL, 2000, 0, 0, 0, 0, 'Cash', NULL,
                                         jsonb_build_array(jsonb_build_object('loanId', v_loan, 'amount', 450)), 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6b: 450 accepted while 200 of 600 is claimed elsewhere'; END IF;
    v_item2 := sphotelpayrollitem_save(f, v_run2, v_ama, NULL, NULL, 2000, 0, 0, 0, 0, 'Cash', NULL,
                                       jsonb_build_array(jsonb_build_object('loanId', v_loan, 'amount', 400)), 'probe');
    -- and the other staff member's loan cannot be deducted from Ama
    v_loan2 := sphotelemployeeloan_create(f, v_kofi, NULL, 'EmployeeLoan', 300, 0, 'Cash', 0, NULL, NULL, NULL, 'probe', TRUE, v_main, now());
    v_failed := FALSE;
    BEGIN PERFORM sphotelpayrollitem_save(f, v_run2, v_ama, NULL, NULL, 2000, 0, 0, 0, 0, 'Cash', NULL,
                                         jsonb_build_array(jsonb_build_object('loanId', v_loan2, 'amount', 10)), 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 6c: another staff member''s loan was deducted'; END IF;
    -- an empty list removes the deduction; deleting the line removes it too
    PERFORM sphotelpayrollitem_save(f, v_run2, v_ama, NULL, NULL, 2000, 0, 0, 0, 0, 'Cash', NULL, '[]'::jsonb, 'probe');
    IF EXISTS (SELECT 1 FROM hotelpayrollitemdeductions WHERE hotelpayrollrunid = v_run2) THEN
        RAISE EXCEPTION 'FAIL 6d: empty list did not remove the deduction'; END IF;
    PERFORM sphotelpayrollitem_delete(f, v_item2);
    IF (SELECT totalgrosspay FROM hotelpayrollruns WHERE hotelpayrollrunid = v_run2) <> 0 THEN
        RAISE EXCEPTION 'FAIL 6e: run 2 totals not recalculated after delete'; END IF;
    v_checks := v_checks + 5;

    -- 7. A loan with a draft payroll deduction cannot be reversed
    v_failed := FALSE;
    BEGIN PERFORM sphotelemployeeloan_reverse(v_loan, f, 'probe', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 7: reversed a loan with a draft payroll deduction'; END IF;
    v_checks := v_checks + 1;

    -- 8. Approve: the deduction becomes a Payroll repayment; no cash moves
    SELECT currentbalance INTO v_n FROM hotelcashaccounts WHERE hotelcashaccountid = v_main;
    IF sphotelpayrollrun_approve(f, v_run, 'probe') <> 1 THEN RAISE EXCEPTION 'FAIL 8a: approve posted wrong count'; END IF;
    SELECT * INTO r FROM sphotelemployeeloan_getbyid(v_loan, f);
    IF r.outstandingbalance <> 400 THEN RAISE EXCEPTION 'FAIL 8b: outstanding after approve %', r.outstandingbalance; END IF;
    IF (SELECT status FROM hotelpayrollitemdeductions WHERE hotelpayrollitemid = v_item) <> 'Posted' THEN
        RAISE EXCEPTION 'FAIL 8c: deduction not Posted'; END IF;
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> v_n THEN
        RAISE EXCEPTION 'FAIL 8d: approving moved cash'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelemployeeloanrepayment_reverse(
            (SELECT hotelemployeeloanrepaymentid FROM hotelemployeeloanrepayments WHERE hotelpayrollrunid = v_run AND status = 'Posted'),
            f, 'probe', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 8e: payroll repayment reversed outside payroll'; END IF;
    v_checks := v_checks + 5;

    -- 9. Reopen reverses it; approving again posts it again
    PERFORM sphotelpayrollrun_unapprove(f, v_run, 'fix bonus', 'probe');
    SELECT * INTO r FROM sphotelemployeeloan_getbyid(v_loan, f);
    IF r.outstandingbalance <> 600 OR (SELECT status FROM hotelpayrollruns WHERE hotelpayrollrunid = v_run) <> 'Draft'
       OR (SELECT status FROM hotelpayrollitemdeductions WHERE hotelpayrollitemid = v_item) <> 'Draft' THEN
        RAISE EXCEPTION 'FAIL 9a: after reopen %', row_to_json(r); END IF;
    PERFORM sphotelpayrollrun_approve(f, v_run, 'probe');
    SELECT * INTO r FROM sphotelemployeeloan_getbyid(v_loan, f);
    IF r.outstandingbalance <> 400 THEN RAISE EXCEPTION 'FAIL 9b: re-approve outstanding %', r.outstandingbalance; END IF;
    SELECT COUNT(*) INTO v_i FROM hotelemployeeloanrepayments WHERE hotelemployeeloanid = v_loan AND sourcetype = 'Payroll';
    IF v_i <> 2 THEN RAISE EXCEPTION 'FAIL 9c: payroll repayment rows % (want 1 reversed + 1 posted)', v_i; END IF;
    v_checks := v_checks + 3;

    -- 10. Mark paid: NET pay leaves the Payroll account (created on first use)
    PERFORM sphotelpayrollrun_markpaid(f, v_run, DATE '2026-09-30', 'probe');
    SELECT hotelcashaccountid INTO v_pay FROM hotelcashaccounts WHERE farmid = f AND purpose = 'Payroll';
    IF v_pay IS NULL THEN RAISE EXCEPTION 'FAIL 10a: no Payroll account'; END IF;
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_pay) <> -1850 THEN
        RAISE EXCEPTION 'FAIL 10b: payroll account %', (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_pay); END IF;
    IF (SELECT status FROM hotelpayrollruns WHERE hotelpayrollrunid = v_run) <> 'Paid'
       OR (SELECT cashtransactionid FROM hotelpayrollruns WHERE hotelpayrollrunid = v_run) IS NULL THEN
        RAISE EXCEPTION 'FAIL 10c: run not Paid with a ledger id'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelpayrollrun_cancel(f, v_run, 'late', 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 10d: a Paid run was cancelled'; END IF;
    v_checks := v_checks + 4;

    -- 11. Cash Flow: loan movements appear, net pay is the payroll figure
    SELECT COALESCE(SUM(amount), 0) INTO v_n FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource LIKE 'Loan%';
    IF v_n <> (-600 - 300 + 60) THEN RAISE EXCEPTION 'FAIL 11a: loan cash flow % (want -840)', v_n; END IF;
    SELECT amount INTO v_n FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource = 'Payroll';
    IF v_n <> -1850 THEN RAISE EXCEPTION 'FAIL 11b: payroll cash flow %', v_n; END IF;
    IF EXISTS (SELECT 1 FROM sphotelcashflow_detail(f, NULL, NULL) WHERE rowsource LIKE 'Loan%' AND category NOT LIKE 'Staff loan%') THEN
        RAISE EXCEPTION 'FAIL 11c: loan rows without a staff-loan category'; END IF;
    -- keys must be unique (the page keys rows by rowsource + id)
    SELECT COUNT(*) - COUNT(DISTINCT rowsource || ':' || sourcerowid) INTO v_i FROM sphotelcashflow_rows(f, NULL, NULL);
    IF v_i <> 0 THEN RAISE EXCEPTION 'FAIL 11d: duplicate cash-flow keys'; END IF;
    v_checks := v_checks + 4;

    -- 12. P&L: wages at GROSS (2,100 incl. bonus), interest 60 as revenue, totals agree
    SELECT amount INTO v_n FROM sphotelreport_pllines(f, DATE '2026-01-01', DATE '2026-12-31') WHERE linekey = 'StaffWages';
    IF v_n <> 2100 THEN RAISE EXCEPTION 'FAIL 12a: staff wages % (want gross 2100)', v_n; END IF;
    SELECT amount INTO v_n FROM sphotelreport_pllines(f, CURRENT_DATE - 1, CURRENT_DATE + 1) WHERE linekey = 'StaffLoanInterest';
    IF v_n <> 60 THEN RAISE EXCEPTION 'FAIL 12b: loan interest %', v_n; END IF;
    SELECT totalrevenue INTO v_n FROM sphotelreport_plsummary(f, CURRENT_DATE - 1, CURRENT_DATE + 1);
    SELECT SUM(amount) INTO v_n2 FROM sphotelreport_pllines(f, CURRENT_DATE - 1, CURRENT_DATE + 1) WHERE section = 'Revenue';
    IF v_n <> v_n2 THEN RAISE EXCEPTION 'FAIL 12c: summary revenue % <> lines %', v_n, v_n2; END IF;
    v_checks := v_checks + 3;

    -- 13. Reverse the cash repayment: money goes back out, interest un-repaid
    PERFORM sphotelemployeeloanrepayment_reverse(v_rep, f, 'counted twice', 'probe');
    SELECT * INTO r FROM sphotelemployeeloan_getbyid(v_loan, f);
    IF r.outstandingbalance <> 460 OR r.totalinterestrepaid <> 0 THEN RAISE EXCEPTION 'FAIL 13a: %', row_to_json(r); END IF;
    IF (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 4100 THEN
        RAISE EXCEPTION 'FAIL 13b: main % (want 5000 - 600 - 300)', (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main); END IF;
    IF NOT EXISTS (SELECT 1 FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource = 'LoanRepayReversed' AND amount = -60) THEN
        RAISE EXCEPTION 'FAIL 13c: repayment reversal missing from cash flow'; END IF;
    v_checks := v_checks + 3;

    -- 14. Kofi's loan reversed: principal returns, loan Reversed, cash flow shows it
    PERFORM sphotelemployeeloan_reverse(v_loan2, f, 'wrong person', 'probe');
    IF (SELECT status FROM hotelemployeeloans WHERE hotelemployeeloanid = v_loan2) <> 'Reversed'
       OR (SELECT currentbalance FROM hotelcashaccounts WHERE hotelcashaccountid = v_main) <> 4400 THEN
        RAISE EXCEPTION 'FAIL 14a: reversal'; END IF;
    IF NOT EXISTS (SELECT 1 FROM hotelcashtransactions WHERE farmid = f AND sourcetype = 'EmployeeLoanReversal' AND amount = 300) THEN
        RAISE EXCEPTION 'FAIL 14b: reversal ledger row'; END IF;
    v_checks := v_checks + 2;

    -- 15. Every account: balance = opening + credits - debits
    FOR r IN
        SELECT a.accountname, a.currentbalance,
               a.openingbalance + COALESCE(SUM(CASE WHEN t.txntype = 'Credit' THEN t.amount ELSE -t.amount END), 0) AS derived
        FROM   hotelcashaccounts a
        LEFT   JOIN hotelcashtransactions t ON t.hotelcashaccountid = a.hotelcashaccountid
        WHERE  a.farmid = f
        GROUP  BY a.hotelcashaccountid
    LOOP
        IF r.currentbalance <> r.derived THEN
            RAISE EXCEPTION 'FAIL 15: % balance % <> ledger %', r.accountname, r.currentbalance, r.derived; END IF;
    END LOOP;
    -- and the loan cash flow equals the loan ledger rows
    SELECT COALESCE(SUM(CASE WHEN txntype = 'Credit' THEN amount ELSE -amount END), 0) INTO v_n
    FROM   hotelcashtransactions WHERE farmid = f AND sourcetype LIKE 'EmployeeLoan%';
    SELECT COALESCE(SUM(amount), 0) INTO v_n2 FROM sphotelcashflow_rows(f, NULL, NULL) WHERE rowsource LIKE 'Loan%';
    IF v_n <> v_n2 THEN RAISE EXCEPTION 'FAIL 15b: loan ledger % <> loan cash flow %', v_n, v_n2; END IF;
    v_checks := v_checks + 2;

    -- 16. Cancelling an Approved run restores the loan
    INSERT INTO hotelpayrollruns (farmid, periodstart, periodend, paydate, status)
    VALUES (f, DATE '2026-11-01', DATE '2026-11-30', DATE '2026-11-30', 'Draft') RETURNING hotelpayrollrunid INTO v_run3;
    PERFORM sphotelpayrollitem_save(f, v_run3, v_ama, NULL, NULL, 2000, 0, 0, 0, 0, 'Cash', NULL,
                                    jsonb_build_array(jsonb_build_object('loanId', v_loan, 'amount', 200)), 'probe');
    PERFORM sphotelpayrollrun_approve(f, v_run3, 'probe');
    IF (SELECT outstandingbalance FROM hotelemployeeloans WHERE hotelemployeeloanid = v_loan) <> 260 THEN
        RAISE EXCEPTION 'FAIL 16a: before cancel'; END IF;
    PERFORM sphotelpayrollrun_cancel(f, v_run3, 'duplicate', 'probe');
    IF (SELECT outstandingbalance FROM hotelemployeeloans WHERE hotelemployeeloanid = v_loan) <> 460
       OR EXISTS (SELECT 1 FROM hotelpayrollitemdeductions WHERE hotelpayrollrunid = v_run3 AND status <> 'Reversed') THEN
        RAISE EXCEPTION 'FAIL 16b: after cancel'; END IF;
    v_checks := v_checks + 2;

    -- 17. Summary, staff report, and the staff delete guard
    SELECT * INTO r FROM sphotelemployeeloan_summary(f, NULL, NULL);
    IF r.totaloutstanding <> 460 OR r.activecount <> 1 OR r.staffwithloans <> 1 OR r.totaldisbursed <> 600 THEN
        RAISE EXCEPTION 'FAIL 17a: summary %', row_to_json(r); END IF;
    SELECT outstanding, repaidpayrollinperiod INTO v_n, v_n2 FROM sphotelemployeeloan_staffreport(f, NULL, NULL) WHERE hotelstaffid = v_ama;
    IF v_n <> 460 OR v_n2 <> 200 THEN RAISE EXCEPTION 'FAIL 17b: staff report % / %', v_n, v_n2; END IF;
    v_failed := FALSE;
    BEGIN DELETE FROM hotelstaff WHERE hotelstaffid = v_ama;
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 17c: deleted a staff member with an open loan'; END IF;
    DELETE FROM hotelstaff WHERE hotelstaffid = v_kofi;   -- Kofi's loan is Reversed: allowed
    v_checks := v_checks + 3;

    -- 18. Edit: plan fields change on an Active loan, amounts do not
    PERFORM sphotelemployeeloan_update(v_loan, f, 'SalaryAdvance', 600, 60, 'Mixed', 150, NULL, 'ADV-1', 'new plan', 'probe');
    IF (SELECT defaultpayrolldeduction FROM hotelemployeeloans WHERE hotelemployeeloanid = v_loan) <> 150 THEN
        RAISE EXCEPTION 'FAIL 18a: plan not updated'; END IF;
    v_failed := FALSE;
    BEGIN PERFORM sphotelemployeeloan_update(v_loan, f, 'SalaryAdvance', 900, 60, 'Mixed', 150, NULL, NULL, NULL, 'probe');
    EXCEPTION WHEN raise_exception THEN v_failed := TRUE; END;
    IF NOT v_failed THEN RAISE EXCEPTION 'FAIL 18b: principal changed on an Active loan'; END IF;
    v_checks := v_checks + 2;

    RAISE EXCEPTION 'SELFTEST PASSED: % checks (rolled back)', v_checks;
END $$;
