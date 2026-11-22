-- =============================================================================
-- Checks for 460 (Water Employee Credit + payroll keep-as-credit + mark paid).
-- SELF-ROLLING-BACK, fixtures in a real Water company, dated 2001.
-- Prints 'water 460: all checks passed'.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.w460_refused(p_sql text) RETURNS text LANGUAGE plpgsql AS $r$
BEGIN
    EXECUTE p_sql;
    RETURN NULL;
EXCEPTION WHEN OTHERS THEN
    RETURN SQLERRM;
END $r$;

DO $t$
DECLARE
    v_farm text; v_staff integer; v_acct integer; v_run integer; v_run2 integer; v_item integer; v_item2 integer;
    v_ded integer; v_id integer; v_id2 integer; v_err text; v_n numeric; v_m numeric; v_exp0 numeric; v_exp1 numeric;
    d1 date := DATE '2001-04-30';
    d2 date := DATE '2001-05-02';
BEGIN
    SELECT a.farmid INTO v_farm FROM watercashaccounts a ORDER BY a.watercashaccountid LIMIT 1;
    INSERT INTO waterstaff (farmid, firstname, lastname, role, salarytype, basepay, isactive, isdeleted)
    VALUES (v_farm, '__w460', 'Worker', 'Driver', 'Monthly', 1000, TRUE, FALSE) RETURNING waterstaffid INTO v_staff;
    INSERT INTO watercashaccounts (farmid, accountname, accounttype, openingbalance, currentbalance, allownegativebalance, isactive)
    VALUES (v_farm, '__w460_account', 'Cash', 1000, 1000, FALSE, TRUE) RETURNING watercashaccountid INTO v_acct;
    INSERT INTO waterpayrollruns (farmid, periodstart, periodend, paydate, totalgrosspay, totaldeductions, totalnetpay,
                                  status, watercashaccountid, isdeleted, createdby)
    VALUES (v_farm, DATE '2001-04-01', d1, d1, 0, 0, 0, 'Draft', v_acct, FALSE, '__w460') RETURNING waterpayrollrunid INTO v_run;
    SELECT totalexpenses INTO v_exp0 FROM spwaterreport_periodpnl(v_farm, d1, d1);

    -- 1. a line: 1,000 gross, 100 other deductions, 300 kept as credit
    SELECT waterpayrollitemid INTO v_item FROM spwaterpayrollitem_upsert(
        p_waterpayrollrunid => v_run, p_farmid => v_farm, p_waterstaffid => v_staff, p_basicpay => 1000,
        p_otherdeductions => 100, p_employeecredit => 300, p_savedby => '__w460');
    IF (SELECT deductions FROM waterpayrollitems WHERE waterpayrollitemid = v_item) <> 400
       OR (SELECT totalnetpay FROM waterpayrollruns WHERE waterpayrollrunid = v_run) <> 600 THEN RAISE EXCEPTION 'FAIL 1a'; END IF;
    -- removing the credit lowers the deductions (the 442 bug), putting it back restores them
    PERFORM spwaterpayrollitem_upsert(p_waterpayrollrunid => v_run, p_farmid => v_farm, p_waterstaffid => v_staff,
        p_basicpay => 1000, p_otherdeductions => 100, p_employeecredit => 0);
    IF (SELECT deductions FROM waterpayrollitems WHERE waterpayrollitemid = v_item) <> 100 THEN RAISE EXCEPTION 'FAIL 1b: removed credit still deducted'; END IF;
    PERFORM spwaterpayrollitem_upsert(p_waterpayrollrunid => v_run, p_farmid => v_farm, p_waterstaffid => v_staff,
        p_basicpay => 1000, p_otherdeductions => 100, p_employeecredit => 300);
    -- an old client sending only the total still works
    PERFORM spwaterpayrollitem_upsert(p_waterpayrollrunid => v_run, p_farmid => v_farm, p_waterstaffid => v_staff,
        p_basicpay => 1000, p_deductions => 400);
    IF (SELECT deductions FROM waterpayrollitems WHERE waterpayrollitemid = v_item) <> 400
       OR (SELECT legacydeductions FROM waterpayrollitems WHERE waterpayrollitemid = v_item) <> 100 THEN RAISE EXCEPTION 'FAIL 1c: old-style total'; END IF;
    RAISE NOTICE 'ok 1 line: other deductions + keep as credit';

    -- 2. approve: credit posted, P&L = 1,000 - 100 other
    PERFORM spwaterpayrollrun_approve(v_run, v_farm, '__w460');
    IF fnwateremployeecredit_balance(v_farm, v_staff) <> 300 THEN RAISE EXCEPTION 'FAIL 2a: balance %', fnwateremployeecredit_balance(v_farm, v_staff); END IF;
    SELECT totalexpenses INTO v_exp1 FROM spwaterreport_periodpnl(v_farm, d1, d1);
    IF v_exp1 - v_exp0 <> 900 THEN RAISE EXCEPTION 'FAIL 2b: payroll cost % (expected 900)', v_exp1 - v_exp0; END IF;
    IF EXISTS (SELECT 1 FROM spwatercashflow_rows(v_farm, NULL, NULL) r
               JOIN waterexpenses e ON e.waterexpenseid = r.sourcerowid AND r.rowsource = 'Expense'
               WHERE e.sourcetype = 'PayrollEmployeeCredit' AND e.sourceid = v_run) THEN RAISE EXCEPTION 'FAIL 2c: kept wages are cash'; END IF;
    SELECT d.waterpayrollitemdeductionid INTO v_ded FROM waterpayrollitemdeductions d
    WHERE d.waterpayrollitemid = v_item AND d.deductiontype = 'EmployeeCredit';
    v_err := pg_temp.w460_refused(format('DELETE FROM waterpayrollitemdeductions WHERE waterpayrollitemdeductionid = %s', v_ded));
    IF v_err IS NULL THEN RAISE EXCEPTION 'FAIL 2d: posted credit deduction deleted'; END IF;
    v_err := pg_temp.w460_refused(format('SELECT spwaterpayrollrun_cancel(%s, %L)', v_run, v_farm));
    IF v_err IS NULL OR v_err NOT LIKE '%Reopen it first%' THEN RAISE EXCEPTION 'FAIL 2e: cancel %', v_err; END IF;
    RAISE NOTICE 'ok 2 approve keeps the wages as credit, P&L shows the wage';

    -- 3. mark paid: cash out of the account, on the pay date
    PERFORM spwaterpayrollrun_markpaid(v_run, v_farm, '__w460', d1);
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 400 THEN RAISE EXCEPTION 'FAIL 3a'; END IF;
    IF NOT EXISTS (SELECT 1 FROM watercashtransactions t WHERE t.watercashaccountid = v_acct AND t.sourcetype = 'Payroll'
                   AND t.sourceid = v_run AND t.amount = -600 AND t.transactiondate = d1::timestamp) THEN
        RAISE EXCEPTION 'FAIL 3b: CashOut not dated to the pay date';
    END IF;
    RAISE NOTICE 'ok 3 mark paid on the pay date';

    -- 4. reopen gives the credit back; approve + pay again
    PERFORM spwaterpayrollrun_unapprove(v_run, v_farm, '__w460', 'test');
    IF fnwateremployeecredit_balance(v_farm, v_staff) <> 0 THEN RAISE EXCEPTION 'FAIL 4a'; END IF;
    IF EXISTS (SELECT 1 FROM waterexpenses WHERE farmid = v_farm AND sourcetype = 'PayrollEmployeeCredit' AND sourceid = v_run AND NOT isdeleted) THEN
        RAISE EXCEPTION 'FAIL 4b: top-up survived the reopen';
    END IF;
    IF (SELECT status FROM waterpayrollitemdeductions WHERE waterpayrollitemdeductionid = v_ded) <> 'Draft' THEN RAISE EXCEPTION 'FAIL 4c'; END IF;
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 1000 THEN RAISE EXCEPTION 'FAIL 4d'; END IF;
    PERFORM spwaterpayrollrun_approve(v_run, v_farm, '__w460');
    PERFORM spwaterpayrollrun_markpaid(v_run, v_farm, '__w460', d1);
    IF fnwateremployeecredit_balance(v_farm, v_staff) <> 300 THEN RAISE EXCEPTION 'FAIL 4e'; END IF;
    RAISE NOTICE 'ok 4 reopen takes the credit back; re-approve posts it again';

    -- 5. pay out: cash out, liability down, no P&L; then reopen is refused
    v_err := pg_temp.w460_refused(format('SELECT spwateremployeecredit_payout(%L, %s, 301, %s, %L)', v_farm, v_staff, v_acct, d2));
    IF v_err IS NULL THEN RAISE EXCEPTION 'FAIL 5a: paid out more than held'; END IF;
    SELECT totalexpenses INTO v_exp0 FROM spwaterreport_periodpnl(v_farm, d2, d2);
    v_id := spwateremployeecredit_payout(v_farm, v_staff, 300, v_acct, d2, 'Cash', NULL, NULL, '__w460');
    IF fnwateremployeecredit_balance(v_farm, v_staff) <> 0 THEN RAISE EXCEPTION 'FAIL 5b'; END IF;
    IF (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> 100 THEN RAISE EXCEPTION 'FAIL 5c'; END IF;
    SELECT totalexpenses INTO v_exp1 FROM spwaterreport_periodpnl(v_farm, d2, d2);
    IF v_exp1 <> v_exp0 THEN RAISE EXCEPTION 'FAIL 5d: payout on the P&L'; END IF;
    IF NOT EXISTS (SELECT 1 FROM spwatercashflow_rows(v_farm, NULL, NULL) r
                   WHERE r.rowsource = 'EmployeeCredit' AND r.sourcerowid = v_id AND r.amount = -300) THEN RAISE EXCEPTION 'FAIL 5e: payout not on Cash Flow'; END IF;
    v_err := pg_temp.w460_refused(format('SELECT spwaterpayrollrun_unapprove(%s, %L, NULL, %L)', v_run, v_farm, 'x'));
    IF v_err IS NULL OR v_err NOT LIKE '%paid out%' THEN RAISE EXCEPTION 'FAIL 5f: reopen after payout: %', v_err; END IF;
    v_err := pg_temp.w460_refused(format('SELECT spwateremployeecredit_add(%L, %s, %L, 200, %L, %s)', v_farm, v_staff, 'Deposit', d2, v_acct));
    IF v_err IS NOT NULL THEN RAISE EXCEPTION 'FAIL 5g: deposit refused: %', v_err; END IF;
    RAISE NOTICE 'ok 5 payout: cash only, never P&L; reopen refused once paid out';

    -- 6. an overdraft is refused
    v_err := pg_temp.w460_refused(format('SELECT spwateremployeecredit_payout(%L, %s, 200, %s, %L)', v_farm, v_staff, v_acct, d2));
    IF v_err IS NOT NULL THEN RAISE EXCEPTION 'FAIL 6a: %', v_err; END IF;   -- 300 in the account after the deposit
    PERFORM spwateremployeecredit_add(v_farm, v_staff, 'Deposit', 500, d2, v_acct, NULL, NULL, NULL, '__w460');
    UPDATE watercashaccounts SET currentbalance = 10 WHERE watercashaccountid = v_acct;
    v_err := pg_temp.w460_refused(format('SELECT spwateremployeecredit_payout(%L, %s, 400, %s, %L)', v_farm, v_staff, v_acct, d2));
    IF v_err IS NULL OR v_err NOT LIKE '%overdraw%' THEN RAISE EXCEPTION 'FAIL 6b: %', v_err; END IF;
    UPDATE watercashaccounts SET currentbalance = 1000 WHERE watercashaccountid = v_acct;
    RAISE NOTICE 'ok 6 overdraft refused';

    -- 7. deposit + its reversal net to zero on Cash Flow
    v_id := spwateremployeecredit_add(v_farm, v_staff, 'Deposit', 50, d2, v_acct, 'Cash', NULL, NULL, '__w460');
    PERFORM spwateremployeecredit_reverse(v_farm, v_id, 'mistake', '__w460');
    SELECT COALESCE(SUM(r.amount), 0), COUNT(*) INTO v_n, v_m FROM spwatercashflow_rows(v_farm, NULL, NULL) r
    WHERE r.rowsource IN ('EmployeeCredit', 'EmployeeCreditReversal') AND r.sourcerowid = v_id;
    IF v_n <> 0 OR v_m <> 2 THEN RAISE EXCEPTION 'FAIL 7: net % rows %', v_n, v_m; END IF;
    RAISE NOTICE 'ok 7 reversed deposit: both legs on Cash Flow';

    -- 8. wages owed: NonCash cost, guarded, reversed with the entry
    SELECT totalexpenses INTO v_exp0 FROM spwaterreport_periodpnl(v_farm, d2, d2);
    v_id2 := spwateremployeecredit_add(v_farm, v_staff, 'WagesOwed', 70, d2, NULL, NULL, NULL, NULL, '__w460');
    SELECT totalexpenses INTO v_exp1 FROM spwaterreport_periodpnl(v_farm, d2, d2);
    IF v_exp1 - v_exp0 <> 70 THEN RAISE EXCEPTION 'FAIL 8a: wages owed not a cost (%)', v_exp1 - v_exp0; END IF;
    v_err := pg_temp.w460_refused(format('UPDATE waterexpenses SET amount = 1 WHERE farmid = %L AND sourcetype = %L AND sourceid = %s',
                                         v_farm, 'EmployeeCreditWages', v_id2));
    IF v_err IS NULL THEN RAISE EXCEPTION 'FAIL 8b: expense edited directly'; END IF;
    IF fnwaterexpense_sourceblock((SELECT waterexpenseid FROM waterexpenses WHERE farmid = v_farm AND sourcetype = 'EmployeeCreditWages' AND sourceid = v_id2), v_farm, 'cancelled') IS NULL THEN
        RAISE EXCEPTION 'FAIL 8c: Expenses page would allow it';
    END IF;
    PERFORM spwateremployeecredit_reverse(v_farm, v_id2, 'mistake', '__w460');
    SELECT totalexpenses INTO v_exp1 FROM spwaterreport_periodpnl(v_farm, d2, d2);
    IF v_exp1 <> v_exp0 THEN RAISE EXCEPTION 'FAIL 8d: reversed wages still a cost'; END IF;
    v_err := pg_temp.w460_refused(format('SELECT spwateremployeecredit_reverse(%L, %s, %L)',
        v_farm, (SELECT wateremployeecreditid FROM wateremployeecredits WHERE waterpayrollrunid = v_run AND status = 'Posted'), 'x'));
    IF v_err IS NULL OR v_err NOT LIKE '%Reopen that payroll%' THEN RAISE EXCEPTION 'FAIL 8e: %', v_err; END IF;
    RAISE NOTICE 'ok 8 wages owed: a cost with no cash, reversed with its entry';

    -- 9. a run that keeps everything is marked Paid without cash
    INSERT INTO waterpayrollruns (farmid, periodstart, periodend, paydate, totalgrosspay, totaldeductions, totalnetpay,
                                  status, watercashaccountid, isdeleted, createdby)
    VALUES (v_farm, DATE '2001-05-01', DATE '2001-05-31', DATE '2001-05-31', 0, 0, 0, 'Draft', v_acct, FALSE, '__w460')
    RETURNING waterpayrollrunid INTO v_run2;
    PERFORM spwaterpayrollitem_upsert(p_waterpayrollrunid => v_run2, p_farmid => v_farm, p_waterstaffid => v_staff,
        p_basicpay => 200, p_otherdeductions => 0, p_employeecredit => 200);
    PERFORM spwaterpayrollrun_approve(v_run2, v_farm, '__w460');
    SELECT currentbalance INTO v_n FROM watercashaccounts WHERE watercashaccountid = v_acct;
    PERFORM spwaterpayrollrun_markpaid(v_run2, v_farm, '__w460', DATE '2001-05-31');
    IF (SELECT status FROM waterpayrollruns WHERE waterpayrollrunid = v_run2) <> 'Paid'
       OR (SELECT currentbalance FROM watercashaccounts WHERE watercashaccountid = v_acct) <> v_n THEN RAISE EXCEPTION 'FAIL 9'; END IF;
    RAISE NOTICE 'ok 9 nothing to hand over: Paid, no cash';

    -- 10. an OLD client (total typed, advance added afterwards) is not double-deducted
    INSERT INTO wateremployeeloans (farmid, waterstaffid, loannumber, loantype, principalamount, interestenabled,
                                    interestamount, totalrepayable, disbursementdate, repaymentmethod,
                                    defaultpayrolldeduction, status, outstandingbalance, totalprincipalrepaid,
                                    totalinterestrepaid, watercashaccountid, createdby)
    VALUES (v_farm, v_staff, '__W460-L1', 'SalaryAdvance', 500, FALSE, 0, 500, DATE '2001-05-01', 'PayrollDeduction',
            50, 'Active', 500, 0, 0, v_acct, '__w460')
    RETURNING wateremployeeloanid INTO v_id;
    INSERT INTO waterpayrollruns (farmid, periodstart, periodend, paydate, totalgrosspay, totaldeductions, totalnetpay,
                                  status, watercashaccountid, isdeleted, createdby)
    VALUES (v_farm, DATE '2001-06-01', DATE '2001-06-30', DATE '2001-06-30', 0, 0, 0, 'Draft', v_acct, FALSE, '__w460')
    RETURNING waterpayrollrunid INTO v_run2;
    SELECT waterpayrollitemid INTO v_item2 FROM spwaterpayrollitem_upsert(
        p_waterpayrollrunid => v_run2, p_farmid => v_farm, p_waterstaffid => v_staff, p_basicpay => 500, p_deductions => 150);
    PERFORM spwaterpayrollitemdeduction_save(v_farm, v_item2, 'SalaryAdvanceRepayment', 50, v_id, NULL, NULL, NULL, '__w460');
    IF (SELECT deductions FROM waterpayrollitems WHERE waterpayrollitemid = v_item2) <> 150 THEN
        RAISE EXCEPTION 'FAIL 10a: old client double-deducted (% instead of 150)', (SELECT deductions FROM waterpayrollitems WHERE waterpayrollitemid = v_item2);
    END IF;
    -- a NEW client typing other deductions only, then the advance: other + advance
    PERFORM spwaterpayrollitem_upsert(p_waterpayrollrunid => v_run2, p_farmid => v_farm, p_waterstaffid => v_staff,
        p_basicpay => 500, p_otherdeductions => 100, p_employeecredit => 0);
    IF (SELECT deductions FROM waterpayrollitems WHERE waterpayrollitemid = v_item2) <> 150 THEN RAISE EXCEPTION 'FAIL 10b'; END IF;
    RAISE NOTICE 'ok 10 old and new payroll clients both deduct an advance once';

    RAISE NOTICE 'water 460: all checks passed';
END
$t$;

ROLLBACK;
