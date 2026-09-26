-- =============================================================================
-- 326_RestaurantPayrollStaffLoans.postgres.sql
--
-- Purpose
-- -------
-- Payroll and staff loans & advances for the standalone Restaurant module,
-- built the same way as the Hotel (325) and Water/Poultry (305-317) versions,
-- and posting through the restaurant money machinery from 323:
--   * every balance change goes through fnrestaurant_post (one ledger row, one
--     balance move, overdraft rule, unique (sourcetype, sourceid));
--   * every money date is checked by fnrestaurant_assert_day_open (closed days
--     are locked); money cannot be dated in the future; reversals are today;
--   * back-office cash defaults to the Main Cash Box, as expenses do.
-- RESTAURANT ONLY. The company-borrowing loans (restaurantloans, the "Loans"
-- page) are a different thing and are not touched. New ledger source types all
-- start with "EmployeeLoan" or are "Payroll" -- never "Loan..." -- because the
-- Cash Flow classifies sourcetype LIKE 'Loan%' as financing.
--
-- The money rules
-- ---------------
--   * An advance is NOT an expense and a repayment is NOT revenue. Paying it out
--     is cash out; getting it back is cash in. Interest repaid is income.
--   * A payroll deduction moves NO cash: the staff member receives less.
--     Approving the run turns each deduction into a repayment. Marking the run
--     Paid posts the NET pay. The P&L carries wages at GROSS pay.
--   * Corrections are new reversing entries; nothing posted is deleted.
--
-- Payroll lifecycle
-- -----------------
--   Draft -> Approved (loan deductions become repayments)
--         -> Paid     (net pay leaves the chosen account)
--   Approved -> Draft (Reopen: repayments reversed) ; Draft/Approved -> Cancelled
--
-- Order: after 324. Re-runnable: every function is dropped (all overloads) and
-- recreated; tables and columns are IF NOT EXISTS.
-- NOTE: this redefines sprestaurantcashflow_rows/_detail, the three P&L report
-- functions (from 323) and sprestaurant_report_cash_profit_bridge (from 324).
-- Re-running 323 or 324 on their own would undo those changes; re-run 326 after.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Drop every function this migration defines, all overloads.
-- -----------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
            'sprestaurant_staffloan_create', 'sprestaurant_staffloan_update', 'sprestaurant_staffloan_disburse',
            'sprestaurant_staffloan_cancel', 'sprestaurant_staffloan_reverse',
            'sprestaurant_staffloanrepayment_record', 'sprestaurant_staffloanrepayment_reverse',
            'sprestaurant_staffloan_list', 'sprestaurant_staffloan_repayments', 'sprestaurant_staffloan_summary',
            'sprestaurant_staffloan_eligible', 'sprestaurant_staffloan_staffreport',
            'fnrestaurant_payrollrun_recalc', 'fnrestaurant_payrollrun_reverserepayments',
            'fnrestaurant_payrollline_setloans',
            'sprestaurant_payrollrun_create', 'sprestaurant_payrollrun_update', 'sprestaurant_payrollrun_list',
            'sprestaurant_payrollrun_lines', 'sprestaurant_payrollrun_deductions',
            'sprestaurant_payrollline_save', 'sprestaurant_payrollline_delete', 'sprestaurant_payrollrun_addallstaff',
            'sprestaurant_payrollrun_approve', 'sprestaurant_payrollrun_unapprove', 'sprestaurant_payrollrun_cancel',
            'sprestaurant_payrollrun_markpaid', 'sprestaurant_payrollrun_delete', 'sprestaurant_payroll_report',
            'trgrestaurantstaff_openloanguard')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS restaurantstaffloans (
    staffloanid              SERIAL PRIMARY KEY,
    farmid                   TEXT          NOT NULL,
    restaurantstaffid        INT           NOT NULL,        -- no FK: staff are hard-deleted; the name is kept below
    staffname                TEXT,
    loannumber               TEXT          NOT NULL,
    loantype                 TEXT          NOT NULL DEFAULT 'SalaryAdvance'
                             CHECK (loantype IN ('SalaryAdvance', 'EmployeeLoan', 'OtherAdvance')),
    status                   TEXT          NOT NULL DEFAULT 'Draft'
                             CHECK (status IN ('Draft', 'Active', 'Paid', 'Cancelled', 'Reversed')),
    principalamount          NUMERIC(14,2) NOT NULL CHECK (principalamount > 0),
    interestamount           NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (interestamount >= 0),
    totalrepayable           NUMERIC(14,2) NOT NULL,
    totalprincipalrepaid     NUMERIC(14,2) NOT NULL DEFAULT 0,
    totalinterestrepaid      NUMERIC(14,2) NOT NULL DEFAULT 0,
    outstandingbalance       NUMERIC(14,2) NOT NULL DEFAULT 0,
    repaymentmethod          TEXT          NOT NULL DEFAULT 'PayrollDeduction'
                             CHECK (repaymentmethod IN ('PayrollDeduction', 'Mixed', 'Cash', 'MoMo', 'Bank', 'Other')),
    defaultpayrolldeduction  NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (defaultpayrolldeduction >= 0),
    disbursementdate         DATE,
    expectedenddate          DATE,
    cashaccountid            INT,
    cashtxnid                INT,
    reversalcashtxnid        INT,
    reference                TEXT,
    notes                    TEXT,
    createdby                TEXT,
    createdat                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updatedat                TIMESTAMPTZ,
    closedby                 TEXT,          -- who cancelled or reversed
    closedreason             TEXT,
    closedat                 TIMESTAMPTZ,
    CONSTRAINT ck_restaurantstaffloans_total CHECK (totalrepayable = principalamount + interestamount)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantstaffloans_number ON restaurantstaffloans (farmid, loannumber);
CREATE INDEX IF NOT EXISTS ix_restaurantstaffloans_staff ON restaurantstaffloans (farmid, restaurantstaffid, status);

CREATE TABLE IF NOT EXISTS restaurantpayrollruns (
    payrollrunid        SERIAL PRIMARY KEY,
    farmid              TEXT          NOT NULL,
    runnumber           TEXT          NOT NULL,
    periodstart         DATE          NOT NULL,
    periodend           DATE          NOT NULL,
    paydate             DATE          NOT NULL,
    status              TEXT          NOT NULL DEFAULT 'Draft'
                        CHECK (status IN ('Draft', 'Approved', 'Paid', 'Cancelled')),
    cashaccountid       INT,
    totalgross          NUMERIC(14,2) NOT NULL DEFAULT 0,
    totaldeductions     NUMERIC(14,2) NOT NULL DEFAULT 0,
    totalloandeductions NUMERIC(14,2) NOT NULL DEFAULT 0,
    totalnet            NUMERIC(14,2) NOT NULL DEFAULT 0,
    notes               TEXT,
    cashtxnid           INT,
    createdby           TEXT,
    createdat           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updatedat           TIMESTAMPTZ,
    approvedby          TEXT,
    approvedat          TIMESTAMPTZ,
    paidby              TEXT,
    paidat              TIMESTAMPTZ,
    cancelledby         TEXT,
    cancelledat         TIMESTAMPTZ,
    cancelreason        TEXT,
    reopenedby          TEXT,
    reopenedat          TIMESTAMPTZ,
    reopenreason        TEXT,
    CONSTRAINT ck_restaurantpayrollruns_period CHECK (periodend >= periodstart)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantpayrollruns_number ON restaurantpayrollruns (farmid, runnumber);
CREATE INDEX IF NOT EXISTS ix_restaurantpayrollruns_farm ON restaurantpayrollruns (farmid, status, paydate);

CREATE TABLE IF NOT EXISTS restaurantpayrolllines (
    payrolllineid       SERIAL PRIMARY KEY,
    payrollrunid        INT           NOT NULL REFERENCES restaurantpayrollruns(payrollrunid) ON DELETE CASCADE,
    farmid              TEXT          NOT NULL,
    restaurantstaffid   INT           NOT NULL,
    staffname           TEXT,
    staffrole           TEXT,
    salarytype          TEXT,
    basicpay            NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (basicpay >= 0),
    allowances          NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (allowances >= 0),
    overtime            NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (overtime >= 0),
    bonus               NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (bonus >= 0),
    otherdeductions     NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (otherdeductions >= 0),
    loandeductions      NUMERIC(14,2) NOT NULL DEFAULT 0,
    grosspay            NUMERIC(14,2) NOT NULL DEFAULT 0,
    netpay              NUMERIC(14,2) NOT NULL DEFAULT 0,
    paymentmethod       TEXT          NOT NULL DEFAULT 'Cash',
    notes               TEXT,
    createdat           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updatedat           TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantpayrolllines_run_staff ON restaurantpayrolllines (payrollrunid, restaurantstaffid);

CREATE TABLE IF NOT EXISTS restaurantpayrolldeductions (
    payrolldeductionid  SERIAL PRIMARY KEY,
    farmid              TEXT          NOT NULL,
    payrollrunid        INT           NOT NULL REFERENCES restaurantpayrollruns(payrollrunid) ON DELETE CASCADE,
    payrolllineid       INT           NOT NULL REFERENCES restaurantpayrolllines(payrolllineid) ON DELETE CASCADE,
    restaurantstaffid   INT           NOT NULL,
    staffloanid         INT           NOT NULL REFERENCES restaurantstaffloans(staffloanid),
    deductiontype       TEXT          NOT NULL CHECK (deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment')),
    amount              NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    status              TEXT          NOT NULL DEFAULT 'Draft' CHECK (status IN ('Draft', 'Posted', 'Reversed')),
    repaymentid         INT,
    createdby           TEXT,
    createdat           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updatedat           TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS ix_restaurantpayrolldeductions_run ON restaurantpayrolldeductions (payrollrunid);
CREATE INDEX IF NOT EXISTS ix_restaurantpayrolldeductions_loan ON restaurantpayrolldeductions (staffloanid, status);
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantpayrolldeductions_line_loan_live
    ON restaurantpayrolldeductions (payrolllineid, staffloanid) WHERE status IN ('Draft', 'Posted');

CREATE TABLE IF NOT EXISTS restaurantstaffloanrepayments (
    repaymentid         SERIAL PRIMARY KEY,
    farmid              TEXT          NOT NULL,
    staffloanid         INT           NOT NULL REFERENCES restaurantstaffloans(staffloanid),
    restaurantstaffid   INT           NOT NULL,
    amount              NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    principalamount     NUMERIC(14,2) NOT NULL DEFAULT 0,
    interestamount      NUMERIC(14,2) NOT NULL DEFAULT 0,
    sourcetype          TEXT          NOT NULL CHECK (sourcetype IN ('Cash', 'MoMo', 'Bank', 'Other', 'Payroll')),
    cashaccountid       INT,
    cashtxnid           INT,
    reversalcashtxnid   INT,
    payrollrunid        INT,
    payrolldeductionid  INT,
    balancebefore       NUMERIC(14,2) NOT NULL,
    balanceafter        NUMERIC(14,2) NOT NULL,
    repaymentdate       DATE          NOT NULL,
    reference           TEXT,
    notes               TEXT,
    status              TEXT          NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),
    createdby           TEXT,
    createdat           TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    reversedby          TEXT,
    reversedreason      TEXT,
    reversedat          TIMESTAMPTZ,
    CONSTRAINT ck_restaurantstaffloanrepay_split CHECK (amount = principalamount + interestamount),
    CONSTRAINT ck_restaurantstaffloanrepay_cash CHECK (
        (sourcetype = 'Payroll' AND cashaccountid IS NULL AND payrolldeductionid IS NOT NULL)
        OR (sourcetype <> 'Payroll' AND cashaccountid IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS ix_restaurantstaffloanrepay_loan ON restaurantstaffloanrepayments (staffloanid);
CREATE INDEX IF NOT EXISTS ix_restaurantstaffloanrepay_farm ON restaurantstaffloanrepayments (farmid, repaymentdate);
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantstaffloanrepay_deduction_posted
    ON restaurantstaffloanrepayments (payrolldeductionid) WHERE status = 'Posted' AND payrolldeductionid IS NOT NULL;

-- A staff member with an open loan cannot be deleted (sprestaurant_staff_delete
-- is a hard DELETE): the loan would point at nobody and payroll could never
-- collect it.
CREATE FUNCTION trgrestaurantstaff_openloanguard()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_n INT;
BEGIN
    SELECT COUNT(*) INTO v_n FROM restaurantstaffloans l
     WHERE l.farmid = OLD.farmid AND l.restaurantstaffid = OLD.restaurantstaffid AND l.status IN ('Draft', 'Active');
    IF v_n > 0 THEN
        RAISE EXCEPTION '% % has % open loan(s) or advance(s). Settle, cancel or reverse them first.',
            OLD.firstname, OLD.lastname, v_n;
    END IF;
    RETURN OLD;
END $$;
DROP TRIGGER IF EXISTS trgrestaurantstaff_openloanguard ON restaurantstaff;
CREATE TRIGGER trgrestaurantstaff_openloanguard
    BEFORE DELETE ON restaurantstaff
    FOR EACH ROW EXECUTE FUNCTION trgrestaurantstaff_openloanguard();

-- -----------------------------------------------------------------------------
-- 2. Staff loans
-- -----------------------------------------------------------------------------

CREATE FUNCTION sprestaurant_staffloan_create(
    p_farmid TEXT, p_staffid INT, p_loantype TEXT, p_principal NUMERIC, p_interest NUMERIC,
    p_repaymentmethod TEXT, p_defaultdeduction NUMERIC, p_expectedenddate DATE,
    p_reference TEXT, p_notes TEXT, p_createdby TEXT,
    p_disbursenow BOOLEAN DEFAULT FALSE, p_cashaccountid INT DEFAULT NULL, p_disbursementdate DATE DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_name TEXT; v_active BOOLEAN; v_total NUMERIC; v_next INT; v_id INT;
BEGIN
    SELECT btrim(s.firstname || ' ' || COALESCE(s.lastname, '')), s.isactive INTO v_name, v_active
      FROM restaurantstaff s WHERE s.restaurantstaffid = p_staffid AND s.farmid = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Choose a staff member of this restaurant.'; END IF;
    IF NOT v_active THEN RAISE EXCEPTION '% is marked inactive. Reactivate them before giving a loan or advance.', v_name; END IF;
    IF p_loantype NOT IN ('SalaryAdvance', 'EmployeeLoan', 'OtherAdvance') THEN RAISE EXCEPTION 'Unknown loan type %.', p_loantype; END IF;
    IF p_repaymentmethod NOT IN ('PayrollDeduction', 'Mixed', 'Cash', 'MoMo', 'Bank', 'Other') THEN
        RAISE EXCEPTION 'Unknown repayment method %.', p_repaymentmethod; END IF;
    IF COALESCE(p_principal, 0) <= 0 THEN RAISE EXCEPTION 'The amount given must be more than zero.'; END IF;
    IF COALESCE(p_interest, 0) < 0 THEN RAISE EXCEPTION 'Interest cannot be negative.'; END IF;
    v_total := ROUND(p_principal, 2) + ROUND(COALESCE(p_interest, 0), 2);
    IF COALESCE(p_defaultdeduction, 0) < 0 OR COALESCE(p_defaultdeduction, 0) > v_total THEN
        RAISE EXCEPTION 'The deduction per payroll must be between 0 and the total to repay (%).', v_total; END IF;
    IF p_repaymentmethod IN ('PayrollDeduction', 'Mixed') AND COALESCE(p_defaultdeduction, 0) = 0 THEN
        RAISE EXCEPTION 'Set how much to deduct from each payroll, or choose a different repayment method.'; END IF;

    PERFORM pg_advisory_xact_lock(hashtext('restaurantstaffloan:' || p_farmid));
    SELECT COALESCE(MAX(NULLIF(regexp_replace(l.loannumber, '\D', '', 'g'), '')::INT), 0) + 1 INTO v_next
      FROM restaurantstaffloans l WHERE l.farmid = p_farmid;

    INSERT INTO restaurantstaffloans (farmid, restaurantstaffid, staffname, loannumber, loantype, status,
        principalamount, interestamount, totalrepayable, outstandingbalance, repaymentmethod,
        defaultpayrolldeduction, expectedenddate, reference, notes, createdby)
    VALUES (p_farmid, p_staffid, v_name, 'SA-' || lpad(v_next::TEXT, 4, '0'), p_loantype, 'Draft',
        ROUND(p_principal, 2), ROUND(COALESCE(p_interest, 0), 2), v_total, 0, p_repaymentmethod,
        ROUND(COALESCE(p_defaultdeduction, 0), 2), p_expectedenddate,
        NULLIF(btrim(p_reference), ''), NULLIF(btrim(p_notes), ''), p_createdby)
    RETURNING staffloanid INTO v_id;

    IF p_disbursenow THEN
        PERFORM sprestaurant_staffloan_disburse(p_farmid, v_id, p_cashaccountid, p_disbursementdate, p_reference, p_createdby);
    END IF;
    RETURN v_id;
END $$;

-- A Draft can change anything; once paid out, only the plan and notes.
CREATE FUNCTION sprestaurant_staffloan_update(
    p_farmid TEXT, p_loanid INT, p_loantype TEXT, p_principal NUMERIC, p_interest NUMERIC,
    p_repaymentmethod TEXT, p_defaultdeduction NUMERIC, p_expectedenddate DATE,
    p_reference TEXT, p_notes TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v restaurantstaffloans%ROWTYPE; v_total NUMERIC;
BEGIN
    SELECT * INTO v FROM restaurantstaffloans WHERE staffloanid = p_loanid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found.'; END IF;
    IF v.status NOT IN ('Draft', 'Active', 'Paid') THEN RAISE EXCEPTION 'A % loan cannot be edited.', lower(v.status); END IF;
    IF p_loantype NOT IN ('SalaryAdvance', 'EmployeeLoan', 'OtherAdvance') THEN RAISE EXCEPTION 'Unknown loan type %.', p_loantype; END IF;
    IF p_repaymentmethod NOT IN ('PayrollDeduction', 'Mixed', 'Cash', 'MoMo', 'Bank', 'Other') THEN
        RAISE EXCEPTION 'Unknown repayment method %.', p_repaymentmethod; END IF;

    IF v.status = 'Draft' THEN
        IF COALESCE(p_principal, 0) <= 0 THEN RAISE EXCEPTION 'The amount given must be more than zero.'; END IF;
        IF COALESCE(p_interest, 0) < 0 THEN RAISE EXCEPTION 'Interest cannot be negative.'; END IF;
        v_total := ROUND(p_principal, 2) + ROUND(COALESCE(p_interest, 0), 2);
    ELSE
        IF ROUND(p_principal, 2) IS DISTINCT FROM v.principalamount
           OR ROUND(COALESCE(p_interest, 0), 2) IS DISTINCT FROM v.interestamount
           OR p_loantype IS DISTINCT FROM v.loantype THEN
            RAISE EXCEPTION 'The type and amounts can only change while the loan is a Draft. Reverse it and create a new one instead.';
        END IF;
        v_total := v.totalrepayable;
    END IF;
    IF COALESCE(p_defaultdeduction, 0) < 0 OR COALESCE(p_defaultdeduction, 0) > v_total THEN
        RAISE EXCEPTION 'The deduction per payroll must be between 0 and the total to repay (%).', v_total; END IF;
    IF p_repaymentmethod IN ('PayrollDeduction', 'Mixed') AND COALESCE(p_defaultdeduction, 0) = 0 THEN
        RAISE EXCEPTION 'Set how much to deduct from each payroll, or choose a different repayment method.'; END IF;

    UPDATE restaurantstaffloans SET
        loantype = p_loantype,
        principalamount = CASE WHEN v.status = 'Draft' THEN ROUND(p_principal, 2) ELSE principalamount END,
        interestamount  = CASE WHEN v.status = 'Draft' THEN ROUND(COALESCE(p_interest, 0), 2) ELSE interestamount END,
        totalrepayable  = v_total,
        repaymentmethod = p_repaymentmethod,
        defaultpayrolldeduction = ROUND(COALESCE(p_defaultdeduction, 0), 2),
        expectedenddate = p_expectedenddate,
        reference = NULLIF(btrim(p_reference), ''), notes = NULLIF(btrim(p_notes), ''),
        updatedat = NOW()
     WHERE staffloanid = p_loanid;
END $$;

-- Pay out: Draft -> Active. The PRINCIPAL leaves the account (default: Main Cash Box).
CREATE FUNCTION sprestaurant_staffloan_disburse(
    p_farmid TEXT, p_loanid INT, p_cashaccountid INT, p_date DATE, p_reference TEXT, p_by TEXT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v restaurantstaffloans%ROWTYPE; v_date DATE := COALESCE(p_date, CURRENT_DATE); v_acct INT; v_txn INT;
BEGIN
    SELECT * INTO v FROM restaurantstaffloans WHERE staffloanid = p_loanid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found.'; END IF;
    IF v.status <> 'Draft' THEN RAISE EXCEPTION 'Only a Draft loan can be paid out (this one is %).', v.status; END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'A payout cannot be dated in the future.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    v_acct := COALESCE(p_cashaccountid, fnrestaurant_default_account(p_farmid, 'Cash'));
    v_txn := fnrestaurant_post(p_farmid, v_acct, v_date, -v.principalamount, 'EmployeeLoanDisbursement', p_loanid,
        'Staff ' || CASE WHEN v.loantype = 'SalaryAdvance' THEN 'advance ' ELSE 'loan ' END || v.loannumber
            || ' to ' || COALESCE(v.staffname, 'staff'), p_by);

    UPDATE restaurantstaffloans SET status = 'Active', disbursementdate = v_date, cashaccountid = v_acct,
           cashtxnid = v_txn, outstandingbalance = totalrepayable,
           reference = COALESCE(NULLIF(btrim(p_reference), ''), reference), updatedat = NOW()
     WHERE staffloanid = p_loanid;
    RETURN v_txn;
END $$;

CREATE FUNCTION sprestaurant_staffloan_cancel(p_farmid TEXT, p_loanid INT, p_reason TEXT, p_by TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_status TEXT;
BEGIN
    SELECT status INTO v_status FROM restaurantstaffloans WHERE staffloanid = p_loanid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found.'; END IF;
    IF v_status <> 'Draft' THEN RAISE EXCEPTION 'Only a Draft loan can be cancelled. A paid-out loan is reversed instead.'; END IF;
    UPDATE restaurantstaffloans SET status = 'Cancelled', closedby = p_by, closedreason = NULLIF(btrim(p_reason), ''),
           closedat = NOW(), outstandingbalance = 0, updatedat = NOW()
     WHERE staffloanid = p_loanid;
END $$;

-- Reverse: the loan was a mistake. The principal goes back to the account it
-- came from, dated today.
CREATE FUNCTION sprestaurant_staffloan_reverse(p_farmid TEXT, p_loanid INT, p_reason TEXT, p_by TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v restaurantstaffloans%ROWTYPE; v_n INT; v_runs TEXT; v_txn INT;
BEGIN
    SELECT * INTO v FROM restaurantstaffloans WHERE staffloanid = p_loanid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found.'; END IF;
    IF v.status NOT IN ('Active', 'Paid') THEN RAISE EXCEPTION 'Only an Active or Paid loan can be reversed (this one is %).', v.status; END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN RAISE EXCEPTION 'Give a reason for reversing the loan.'; END IF;
    SELECT COUNT(*) INTO v_n FROM restaurantstaffloanrepayments r WHERE r.staffloanid = p_loanid AND r.status = 'Posted';
    IF v_n > 0 THEN
        RAISE EXCEPTION 'This loan has % posted repayment(s). Reverse them first (payroll repayments are reversed by reopening or cancelling the payroll run).', v_n;
    END IF;
    SELECT string_agg(DISTINCT pr.runnumber, ', ') INTO v_runs
      FROM restaurantpayrolldeductions d JOIN restaurantpayrollruns pr ON pr.payrollrunid = d.payrollrunid
     WHERE d.staffloanid = p_loanid AND d.status = 'Draft';
    IF v_runs IS NOT NULL THEN
        RAISE EXCEPTION 'A draft payroll (%) is set to deduct from this loan. Remove the deduction there first.', v_runs;
    END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    IF v.cashtxnid IS NOT NULL THEN
        v_txn := fnrestaurant_post(p_farmid, v.cashaccountid, CURRENT_DATE, v.principalamount, 'EmployeeLoanReversal', p_loanid,
            'Reversal of staff loan ' || v.loannumber || ' to ' || COALESCE(v.staffname, 'staff'), p_by);
    END IF;
    UPDATE restaurantstaffloans SET status = 'Reversed', closedby = p_by, closedreason = btrim(p_reason), closedat = NOW(),
           reversalcashtxnid = v_txn, outstandingbalance = 0, updatedat = NOW()
     WHERE staffloanid = p_loanid;
END $$;

-- The one path for every repayment. Cash/MoMo/Bank/Other: money INTO an account
-- (default: the account for that method). Payroll: no cash, only from payroll
-- approval with a deduction id. Interest is repaid first.
CREATE FUNCTION sprestaurant_staffloanrepayment_record(
    p_farmid TEXT, p_loanid INT, p_amount NUMERIC, p_sourcetype TEXT, p_cashaccountid INT,
    p_date DATE, p_reference TEXT, p_notes TEXT, p_by TEXT,
    p_deductionid INT DEFAULT NULL, p_payrollrunid INT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v restaurantstaffloans%ROWTYPE; v_amt NUMERIC := ROUND(COALESCE(p_amount, 0), 2);
        v_date DATE := COALESCE(p_date, CURRENT_DATE); v_int NUMERIC; v_after NUMERIC; v_acct INT; v_id INT; v_txn INT;
BEGIN
    SELECT * INTO v FROM restaurantstaffloans WHERE staffloanid = p_loanid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found.'; END IF;
    IF v.status <> 'Active' THEN
        RAISE EXCEPTION 'Loan % is % — only an Active loan takes repayments.', v.loannumber, v.status; END IF;
    IF p_sourcetype NOT IN ('Cash', 'MoMo', 'Bank', 'Other', 'Payroll') THEN
        RAISE EXCEPTION 'Unknown repayment source %.', p_sourcetype; END IF;
    IF v_amt <= 0 THEN RAISE EXCEPTION 'The repayment must be more than zero.'; END IF;
    IF v_amt > v.outstandingbalance THEN
        RAISE EXCEPTION 'The repayment (%) is more than % still owes on % (%).',
            v_amt, COALESCE(v.staffname, 'the staff member'), v.loannumber, v.outstandingbalance; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);

    IF p_sourcetype = 'Payroll' THEN
        IF p_deductionid IS NULL THEN RAISE EXCEPTION 'Payroll repayments are created by approving a payroll run.'; END IF;
        IF p_cashaccountid IS NOT NULL THEN RAISE EXCEPTION 'A payroll repayment moves no cash, so it takes no account.'; END IF;
    ELSE
        IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'A repayment cannot be dated in the future.'; END IF;
        v_acct := COALESCE(p_cashaccountid, fnrestaurant_method_account(p_farmid, p_sourcetype));
    END IF;

    v_int := LEAST(v_amt, GREATEST(v.interestamount - v.totalinterestrepaid, 0));
    v_after := v.outstandingbalance - v_amt;

    INSERT INTO restaurantstaffloanrepayments (farmid, staffloanid, restaurantstaffid, amount, principalamount, interestamount,
        sourcetype, cashaccountid, payrollrunid, payrolldeductionid, balancebefore, balanceafter, repaymentdate,
        reference, notes, createdby)
    VALUES (p_farmid, p_loanid, v.restaurantstaffid, v_amt, v_amt - v_int, v_int,
        p_sourcetype, v_acct, p_payrollrunid, p_deductionid, v.outstandingbalance, v_after, v_date,
        NULLIF(btrim(p_reference), ''), NULLIF(btrim(p_notes), ''), p_by)
    RETURNING repaymentid INTO v_id;

    IF p_sourcetype <> 'Payroll' THEN
        v_txn := fnrestaurant_post(p_farmid, v_acct, v_date, v_amt, 'EmployeeLoanRepayment', v_id,
            'Staff loan repayment ' || v.loannumber || ' from ' || COALESCE(v.staffname, 'staff'), p_by);
        UPDATE restaurantstaffloanrepayments SET cashtxnid = v_txn WHERE repaymentid = v_id;
    END IF;

    UPDATE restaurantstaffloans SET
        totalprincipalrepaid = totalprincipalrepaid + (v_amt - v_int),
        totalinterestrepaid  = totalinterestrepaid + v_int,
        outstandingbalance   = v_after,
        status = CASE WHEN v_after <= 0 THEN 'Paid' ELSE 'Active' END,
        updatedat = NOW()
     WHERE staffloanid = p_loanid;
    RETURN v_id;
END $$;

-- Reverse a repayment, dated today. Payroll repayments only via payroll.
CREATE FUNCTION sprestaurant_staffloanrepayment_reverse(
    p_farmid TEXT, p_repaymentid INT, p_reason TEXT, p_by TEXT, p_allowpayroll BOOLEAN DEFAULT FALSE)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE r restaurantstaffloanrepayments%ROWTYPE; v restaurantstaffloans%ROWTYPE; v_txn INT;
BEGIN
    SELECT * INTO r FROM restaurantstaffloanrepayments WHERE repaymentid = p_repaymentid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Repayment not found.'; END IF;
    IF r.status <> 'Posted' THEN RAISE EXCEPTION 'This repayment is already reversed.'; END IF;
    IF r.sourcetype = 'Payroll' AND NOT p_allowpayroll THEN
        RAISE EXCEPTION 'A payroll repayment is reversed by reopening or cancelling its payroll run.'; END IF;
    IF NOT p_allowpayroll AND NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for reversing the repayment.'; END IF;
    SELECT * INTO v FROM restaurantstaffloans WHERE staffloanid = r.staffloanid FOR UPDATE;
    IF v.status NOT IN ('Active', 'Paid') THEN
        RAISE EXCEPTION 'Loan % is %, so its repayments cannot be reversed.', v.loannumber, v.status; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, CURRENT_DATE);

    IF r.cashtxnid IS NOT NULL THEN
        v_txn := fnrestaurant_post(p_farmid, r.cashaccountid, CURRENT_DATE, -r.amount, 'EmployeeLoanRepaymentReversal', r.repaymentid,
            'Reversal of staff loan repayment ' || v.loannumber || ' from ' || COALESCE(v.staffname, 'staff'), p_by);
    END IF;
    UPDATE restaurantstaffloanrepayments SET status = 'Reversed', reversedby = p_by,
           reversedreason = NULLIF(btrim(p_reason), ''), reversedat = NOW(), reversalcashtxnid = v_txn
     WHERE repaymentid = p_repaymentid;
    UPDATE restaurantstaffloans SET
        totalprincipalrepaid = totalprincipalrepaid - r.principalamount,
        totalinterestrepaid  = totalinterestrepaid - r.interestamount,
        outstandingbalance   = LEAST(totalrepayable, outstandingbalance + r.amount),
        status = 'Active', updatedat = NOW()
     WHERE staffloanid = r.staffloanid;
END $$;

-- ── Reads ──────────────────────────────────────────────────────────────────

CREATE FUNCTION sprestaurant_staffloan_list(p_farmid TEXT, p_status TEXT DEFAULT NULL, p_staffid INT DEFAULT NULL)
RETURNS TABLE(staffloanid INT, restaurantstaffid INT, staffname TEXT, staffisactive BOOLEAN, loannumber TEXT,
              loantype TEXT, status TEXT, principalamount NUMERIC, interestamount NUMERIC, totalrepayable NUMERIC,
              totalprincipalrepaid NUMERIC, totalinterestrepaid NUMERIC, outstandingbalance NUMERIC,
              repaymentmethod TEXT, defaultpayrolldeduction NUMERIC, disbursementdate DATE, expectedenddate DATE,
              cashaccountid INT, cashaccountname TEXT, reference TEXT, notes TEXT, createdby TEXT, createdat TIMESTAMPTZ,
              closedby TEXT, closedreason TEXT, closedat TIMESTAMPTZ, repaymentcount INT, lastrepaymentdate DATE,
              draftpayrollclaims NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT l.staffloanid, l.restaurantstaffid,
           COALESCE(NULLIF(btrim(s.firstname || ' ' || COALESCE(s.lastname, '')), ''), l.staffname),
           COALESCE(s.isactive, FALSE), l.loannumber, l.loantype, l.status,
           l.principalamount, l.interestamount, l.totalrepayable, l.totalprincipalrepaid, l.totalinterestrepaid,
           l.outstandingbalance, l.repaymentmethod, l.defaultpayrolldeduction, l.disbursementdate, l.expectedenddate,
           l.cashaccountid, a.name, l.reference, l.notes, l.createdby, l.createdat, l.closedby, l.closedreason, l.closedat,
           (SELECT COUNT(*)::INT FROM restaurantstaffloanrepayments r WHERE r.staffloanid = l.staffloanid AND r.status = 'Posted'),
           (SELECT MAX(r.repaymentdate) FROM restaurantstaffloanrepayments r WHERE r.staffloanid = l.staffloanid AND r.status = 'Posted'),
           COALESCE((SELECT SUM(d.amount) FROM restaurantpayrolldeductions d WHERE d.staffloanid = l.staffloanid AND d.status = 'Draft'), 0)
      FROM restaurantstaffloans l
      LEFT JOIN restaurantstaff s ON s.restaurantstaffid = l.restaurantstaffid AND s.farmid = l.farmid
      LEFT JOIN restaurantcashaccounts a ON a.cashaccountid = l.cashaccountid
     WHERE l.farmid = p_farmid
       AND (p_status IS NULL OR l.status = p_status)
       AND (p_staffid IS NULL OR l.restaurantstaffid = p_staffid)
     ORDER BY l.createdat DESC, l.staffloanid DESC;
$$;

CREATE FUNCTION sprestaurant_staffloan_repayments(p_farmid TEXT, p_loanid INT DEFAULT NULL)
RETURNS TABLE(repaymentid INT, staffloanid INT, loannumber TEXT, restaurantstaffid INT, staffname TEXT,
              amount NUMERIC, principalamount NUMERIC, interestamount NUMERIC, sourcetype TEXT,
              cashaccountid INT, cashaccountname TEXT, payrollrunid INT, payrollrunnumber TEXT,
              balancebefore NUMERIC, balanceafter NUMERIC, repaymentdate DATE, reference TEXT, notes TEXT,
              status TEXT, createdby TEXT, createdat TIMESTAMPTZ, reversedby TEXT, reversedreason TEXT, reversedat TIMESTAMPTZ)
LANGUAGE sql STABLE AS $$
    SELECT r.repaymentid, r.staffloanid, l.loannumber, r.restaurantstaffid, l.staffname,
           r.amount, r.principalamount, r.interestamount, r.sourcetype, r.cashaccountid, a.name,
           r.payrollrunid, pr.runnumber, r.balancebefore, r.balanceafter, r.repaymentdate, r.reference, r.notes,
           r.status, r.createdby, r.createdat, r.reversedby, r.reversedreason, r.reversedat
      FROM restaurantstaffloanrepayments r
      JOIN restaurantstaffloans l ON l.staffloanid = r.staffloanid
      LEFT JOIN restaurantcashaccounts a ON a.cashaccountid = r.cashaccountid
      LEFT JOIN restaurantpayrollruns pr ON pr.payrollrunid = r.payrollrunid
     WHERE r.farmid = p_farmid AND (p_loanid IS NULL OR r.staffloanid = p_loanid)
     ORDER BY r.repaymentdate, r.repaymentid;
$$;

CREATE FUNCTION sprestaurant_staffloan_summary(p_farmid TEXT, p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL)
RETURNS TABLE(totaloutstanding NUMERIC, totaldisbursed NUMERIC, totalrepaid NUMERIC, activecount INT,
              staffwithloans INT, draftcount INT, paidcount INT, interestearned NUMERIC,
              repaidviapayroll NUMERIC, draftpayrollclaims NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT
        COALESCE((SELECT SUM(l.outstandingbalance) FROM restaurantstaffloans l WHERE l.farmid = p_farmid AND l.status = 'Active'), 0),
        COALESCE((SELECT SUM(l.principalamount) FROM restaurantstaffloans l WHERE l.farmid = p_farmid AND l.status IN ('Active', 'Paid')
                    AND (p_from IS NULL OR l.disbursementdate >= p_from) AND (p_to IS NULL OR l.disbursementdate <= p_to)), 0),
        COALESCE((SELECT SUM(r.amount) FROM restaurantstaffloanrepayments r WHERE r.farmid = p_farmid AND r.status = 'Posted'
                    AND (p_from IS NULL OR r.repaymentdate >= p_from) AND (p_to IS NULL OR r.repaymentdate <= p_to)), 0),
        (SELECT COUNT(*)::INT FROM restaurantstaffloans l WHERE l.farmid = p_farmid AND l.status = 'Active'),
        (SELECT COUNT(DISTINCT l.restaurantstaffid)::INT FROM restaurantstaffloans l WHERE l.farmid = p_farmid AND l.status = 'Active'),
        (SELECT COUNT(*)::INT FROM restaurantstaffloans l WHERE l.farmid = p_farmid AND l.status = 'Draft'),
        (SELECT COUNT(*)::INT FROM restaurantstaffloans l WHERE l.farmid = p_farmid AND l.status = 'Paid'),
        COALESCE((SELECT SUM(r.interestamount) FROM restaurantstaffloanrepayments r WHERE r.farmid = p_farmid AND r.status = 'Posted'
                    AND (p_from IS NULL OR r.repaymentdate >= p_from) AND (p_to IS NULL OR r.repaymentdate <= p_to)), 0),
        COALESCE((SELECT SUM(r.amount) FROM restaurantstaffloanrepayments r WHERE r.farmid = p_farmid AND r.status = 'Posted'
                    AND r.sourcetype = 'Payroll'
                    AND (p_from IS NULL OR r.repaymentdate >= p_from) AND (p_to IS NULL OR r.repaymentdate <= p_to)), 0),
        COALESCE((SELECT SUM(d.amount) FROM restaurantpayrolldeductions d WHERE d.farmid = p_farmid AND d.status = 'Draft'), 0);
$$;

-- A staff member's open loans for a payroll line: what they owe, what other
-- draft lines already claim, and the suggested deduction.
CREATE FUNCTION sprestaurant_staffloan_eligible(p_farmid TEXT, p_staffid INT, p_excludelineid INT DEFAULT NULL)
RETURNS TABLE(staffloanid INT, loannumber TEXT, loantype TEXT, repaymentmethod TEXT, outstandingbalance NUMERIC,
              defaultpayrolldeduction NUMERIC, claimedelsewhere NUMERIC, available NUMERIC,
              suggesteddeduction NUMERIC, currentdeduction NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH b AS (
        SELECT l.staffloanid, l.loannumber, l.loantype, l.repaymentmethod, l.outstandingbalance,
               l.defaultpayrolldeduction, l.disbursementdate,
               COALESCE((SELECT SUM(d.amount) FROM restaurantpayrolldeductions d
                          WHERE d.staffloanid = l.staffloanid AND d.status = 'Draft'
                            AND (p_excludelineid IS NULL OR d.payrolllineid <> p_excludelineid)), 0) AS other,
               COALESCE((SELECT SUM(d.amount) FROM restaurantpayrolldeductions d
                          WHERE d.staffloanid = l.staffloanid AND d.status = 'Draft'
                            AND d.payrolllineid = p_excludelineid), 0) AS cur
          FROM restaurantstaffloans l
         WHERE l.farmid = p_farmid AND l.restaurantstaffid = p_staffid AND l.status = 'Active' AND l.outstandingbalance > 0
    )
    SELECT b.staffloanid, b.loannumber, b.loantype, b.repaymentmethod, b.outstandingbalance, b.defaultpayrolldeduction,
           b.other, GREATEST(b.outstandingbalance - b.other, 0),
           CASE WHEN b.repaymentmethod IN ('PayrollDeduction', 'Mixed')
                THEN LEAST(b.defaultpayrolldeduction, GREATEST(b.outstandingbalance - b.other, 0)) ELSE 0 END,
           b.cur
      FROM b ORDER BY b.disbursementdate, b.staffloanid;
$$;

-- Per staff member: owed now and what moved in the period.
CREATE FUNCTION sprestaurant_staffloan_staffreport(p_farmid TEXT, p_from DATE DEFAULT NULL, p_to DATE DEFAULT NULL)
RETURNS TABLE(restaurantstaffid INT, staffname TEXT, role TEXT, staffisactive BOOLEAN, activeloans INT,
              outstanding NUMERIC, disbursedinperiod NUMERIC, repaidcashinperiod NUMERIC,
              repaidpayrollinperiod NUMERIC, interestinperiod NUMERIC, lastrepaymentdate DATE, totalever NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH ids AS (SELECT DISTINCT l.restaurantstaffid FROM restaurantstaffloans l
                  WHERE l.farmid = p_farmid AND l.status IN ('Active', 'Paid'))
    SELECT i.restaurantstaffid,
           COALESCE(NULLIF(btrim(s.firstname || ' ' || COALESCE(s.lastname, '')), ''),
                    (SELECT l.staffname FROM restaurantstaffloans l WHERE l.farmid = p_farmid
                        AND l.restaurantstaffid = i.restaurantstaffid ORDER BY l.staffloanid DESC LIMIT 1)),
           s.role::TEXT, COALESCE(s.isactive, FALSE),
           (SELECT COUNT(*)::INT FROM restaurantstaffloans l WHERE l.farmid = p_farmid AND l.restaurantstaffid = i.restaurantstaffid AND l.status = 'Active'),
           COALESCE((SELECT SUM(l.outstandingbalance) FROM restaurantstaffloans l WHERE l.farmid = p_farmid
                       AND l.restaurantstaffid = i.restaurantstaffid AND l.status = 'Active'), 0),
           COALESCE((SELECT SUM(l.principalamount) FROM restaurantstaffloans l WHERE l.farmid = p_farmid
                       AND l.restaurantstaffid = i.restaurantstaffid AND l.status IN ('Active', 'Paid')
                       AND (p_from IS NULL OR l.disbursementdate >= p_from) AND (p_to IS NULL OR l.disbursementdate <= p_to)), 0),
           COALESCE((SELECT SUM(r.amount) FROM restaurantstaffloanrepayments r WHERE r.farmid = p_farmid
                       AND r.restaurantstaffid = i.restaurantstaffid AND r.status = 'Posted' AND r.sourcetype <> 'Payroll'
                       AND (p_from IS NULL OR r.repaymentdate >= p_from) AND (p_to IS NULL OR r.repaymentdate <= p_to)), 0),
           COALESCE((SELECT SUM(r.amount) FROM restaurantstaffloanrepayments r WHERE r.farmid = p_farmid
                       AND r.restaurantstaffid = i.restaurantstaffid AND r.status = 'Posted' AND r.sourcetype = 'Payroll'
                       AND (p_from IS NULL OR r.repaymentdate >= p_from) AND (p_to IS NULL OR r.repaymentdate <= p_to)), 0),
           COALESCE((SELECT SUM(r.interestamount) FROM restaurantstaffloanrepayments r WHERE r.farmid = p_farmid
                       AND r.restaurantstaffid = i.restaurantstaffid AND r.status = 'Posted'
                       AND (p_from IS NULL OR r.repaymentdate >= p_from) AND (p_to IS NULL OR r.repaymentdate <= p_to)), 0),
           (SELECT MAX(r.repaymentdate) FROM restaurantstaffloanrepayments r WHERE r.farmid = p_farmid
               AND r.restaurantstaffid = i.restaurantstaffid AND r.status = 'Posted'),
           COALESCE((SELECT SUM(l.principalamount) FROM restaurantstaffloans l WHERE l.farmid = p_farmid
                       AND l.restaurantstaffid = i.restaurantstaffid AND l.status IN ('Active', 'Paid')), 0)
      FROM ids i
      LEFT JOIN restaurantstaff s ON s.restaurantstaffid = i.restaurantstaffid AND s.farmid = p_farmid
     ORDER BY 6 DESC, 2;
$$;

-- -----------------------------------------------------------------------------
-- 3. Payroll
-- -----------------------------------------------------------------------------

-- Recompute every line of a run and the run totals. gross = basic + allowances
-- + overtime + bonus; net = gross - other deductions - live loan deductions.
CREATE FUNCTION fnrestaurant_payrollrun_recalc(p_runid INT)
RETURNS VOID LANGUAGE sql AS $$
    WITH ld AS (
        SELECT pl.payrolllineid,
               COALESCE((SELECT SUM(d.amount) FROM restaurantpayrolldeductions d
                          WHERE d.payrolllineid = pl.payrolllineid AND d.status <> 'Reversed'), 0) AS amt
          FROM restaurantpayrolllines pl WHERE pl.payrollrunid = p_runid)
    UPDATE restaurantpayrolllines pl
       SET loandeductions = ld.amt,
           grosspay = pl.basicpay + pl.allowances + pl.overtime + pl.bonus,
           netpay   = pl.basicpay + pl.allowances + pl.overtime + pl.bonus - pl.otherdeductions - ld.amt
      FROM ld WHERE ld.payrolllineid = pl.payrolllineid;

    UPDATE restaurantpayrollruns r
       SET totalgross = COALESCE(t.g, 0), totaldeductions = COALESCE(t.d, 0),
           totalloandeductions = COALESCE(t.l, 0), totalnet = COALESCE(t.n, 0), updatedat = NOW()
      FROM (SELECT SUM(pl.grosspay) g, SUM(pl.otherdeductions + pl.loandeductions) d, SUM(pl.loandeductions) l,
                   SUM(pl.netpay) n
              FROM restaurantpayrolllines pl WHERE pl.payrollrunid = p_runid) t
     WHERE r.payrollrunid = p_runid;
$$;

CREATE FUNCTION sprestaurant_payrollrun_create(
    p_farmid TEXT, p_periodstart DATE, p_periodend DATE, p_paydate DATE, p_cashaccountid INT, p_notes TEXT, p_by TEXT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_next INT; v_id INT;
BEGIN
    IF p_periodstart IS NULL OR p_periodend IS NULL THEN RAISE EXCEPTION 'The pay period needs a start and an end date.'; END IF;
    IF p_periodend < p_periodstart THEN RAISE EXCEPTION 'The pay period ends before it starts.'; END IF;
    IF p_cashaccountid IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM restaurantcashaccounts a WHERE a.cashaccountid = p_cashaccountid AND a.farmid = p_farmid AND a.isactive) THEN
        RAISE EXCEPTION 'Choose an active cash account of this restaurant.'; END IF;
    PERFORM pg_advisory_xact_lock(hashtext('restaurantpayrollrun:' || p_farmid));
    SELECT COALESCE(MAX(NULLIF(regexp_replace(r.runnumber, '\D', '', 'g'), '')::INT), 0) + 1 INTO v_next
      FROM restaurantpayrollruns r WHERE r.farmid = p_farmid;
    INSERT INTO restaurantpayrollruns (farmid, runnumber, periodstart, periodend, paydate, cashaccountid, notes, createdby)
    VALUES (p_farmid, 'PR-' || lpad(v_next::TEXT, 4, '0'), p_periodstart, p_periodend,
            COALESCE(p_paydate, p_periodend), p_cashaccountid, NULLIF(btrim(p_notes), ''), p_by)
    RETURNING payrollrunid INTO v_id;
    RETURN v_id;
END $$;

CREATE FUNCTION sprestaurant_payrollrun_update(
    p_farmid TEXT, p_runid INT, p_periodstart DATE, p_periodend DATE, p_paydate DATE, p_cashaccountid INT, p_notes TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_status TEXT;
BEGIN
    SELECT status INTO v_status FROM restaurantpayrollruns WHERE payrollrunid = p_runid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payroll run not found.'; END IF;
    IF v_status NOT IN ('Draft', 'Approved') THEN RAISE EXCEPTION 'A % payroll run cannot be edited.', lower(v_status); END IF;
    IF v_status = 'Approved' AND EXISTS (SELECT 1 FROM restaurantpayrollruns r WHERE r.payrollrunid = p_runid
            AND (r.periodstart <> p_periodstart OR r.periodend <> p_periodend OR r.paydate <> COALESCE(p_paydate, r.paydate))) THEN
        RAISE EXCEPTION 'Reopen the payroll run before changing its dates.'; END IF;
    IF p_periodend < p_periodstart THEN RAISE EXCEPTION 'The pay period ends before it starts.'; END IF;
    IF p_cashaccountid IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM restaurantcashaccounts a WHERE a.cashaccountid = p_cashaccountid AND a.farmid = p_farmid AND a.isactive) THEN
        RAISE EXCEPTION 'Choose an active cash account of this restaurant.'; END IF;
    UPDATE restaurantpayrollruns SET periodstart = p_periodstart, periodend = p_periodend,
           paydate = COALESCE(p_paydate, paydate), cashaccountid = p_cashaccountid,
           notes = NULLIF(btrim(p_notes), ''), updatedat = NOW()
     WHERE payrollrunid = p_runid;
END $$;

CREATE FUNCTION sprestaurant_payrollrun_list(p_farmid TEXT, p_status TEXT DEFAULT NULL)
RETURNS TABLE(payrollrunid INT, runnumber TEXT, periodstart DATE, periodend DATE, paydate DATE, status TEXT,
              cashaccountid INT, cashaccountname TEXT, totalgross NUMERIC, totaldeductions NUMERIC,
              totalloandeductions NUMERIC, totalnet NUMERIC, linecount INT, notes TEXT, createdby TEXT,
              createdat TIMESTAMPTZ, approvedby TEXT, approvedat TIMESTAMPTZ, paidby TEXT, paidat TIMESTAMPTZ,
              cancelledby TEXT, cancelreason TEXT, reopenedby TEXT, reopenreason TEXT)
LANGUAGE sql STABLE AS $$
    SELECT r.payrollrunid, r.runnumber, r.periodstart, r.periodend, r.paydate, r.status, r.cashaccountid, a.name,
           r.totalgross, r.totaldeductions, r.totalloandeductions, r.totalnet,
           (SELECT COUNT(*)::INT FROM restaurantpayrolllines pl WHERE pl.payrollrunid = r.payrollrunid),
           r.notes, r.createdby, r.createdat, r.approvedby, r.approvedat, r.paidby, r.paidat,
           r.cancelledby, r.cancelreason, r.reopenedby, r.reopenreason
      FROM restaurantpayrollruns r
      LEFT JOIN restaurantcashaccounts a ON a.cashaccountid = r.cashaccountid
     WHERE r.farmid = p_farmid AND (p_status IS NULL OR r.status = p_status)
     ORDER BY r.periodstart DESC, r.payrollrunid DESC;
$$;

CREATE FUNCTION sprestaurant_payrollrun_lines(p_farmid TEXT, p_runid INT)
RETURNS TABLE(payrolllineid INT, payrollrunid INT, restaurantstaffid INT, staffname TEXT, staffrole TEXT,
              salarytype TEXT, basicpay NUMERIC, allowances NUMERIC, overtime NUMERIC, bonus NUMERIC,
              otherdeductions NUMERIC, loandeductions NUMERIC, grosspay NUMERIC, netpay NUMERIC,
              paymentmethod TEXT, notes TEXT)
LANGUAGE sql STABLE AS $$
    SELECT pl.payrolllineid, pl.payrollrunid, pl.restaurantstaffid, pl.staffname, pl.staffrole, pl.salarytype,
           pl.basicpay, pl.allowances, pl.overtime, pl.bonus, pl.otherdeductions, pl.loandeductions,
           pl.grosspay, pl.netpay, pl.paymentmethod, pl.notes
      FROM restaurantpayrolllines pl
      JOIN restaurantpayrollruns r ON r.payrollrunid = pl.payrollrunid
     WHERE r.farmid = p_farmid AND pl.payrollrunid = p_runid
     ORDER BY pl.staffname, pl.payrolllineid;
$$;

CREATE FUNCTION sprestaurant_payrollrun_deductions(p_farmid TEXT, p_runid INT)
RETURNS TABLE(payrolldeductionid INT, payrolllineid INT, restaurantstaffid INT, staffloanid INT, loannumber TEXT,
              loantype TEXT, deductiontype TEXT, amount NUMERIC, status TEXT, repaymentid INT, outstandingbalance NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT d.payrolldeductionid, d.payrolllineid, d.restaurantstaffid, d.staffloanid, l.loannumber, l.loantype,
           d.deductiontype, d.amount, d.status, d.repaymentid, l.outstandingbalance
      FROM restaurantpayrolldeductions d
      JOIN restaurantstaffloans l ON l.staffloanid = d.staffloanid
     WHERE d.farmid = p_farmid AND d.payrollrunid = p_runid
     ORDER BY d.payrolllineid, d.payrolldeductionid;
$$;

-- Replace a line's draft loan deductions (validated against what is still owed,
-- counting other draft runs). Internal: callers hold the run lock.
CREATE FUNCTION fnrestaurant_payrollline_setloans(
    p_farmid TEXT, p_runid INT, p_lineid INT, p_staffid INT, p_staffname TEXT, p_loans JSONB, p_by TEXT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE d record; l restaurantstaffloans%ROWTYPE; v_other NUMERIC;
BEGIN
    IF jsonb_typeof(p_loans) <> 'array' THEN RAISE EXCEPTION 'Loan deductions must be a list.'; END IF;
    FOR d IN
        SELECT (e->>'loanId')::INT AS loanid, SUM(ROUND(COALESCE((e->>'amount')::NUMERIC, 0), 2)) AS amount, COUNT(*) AS n
          FROM jsonb_array_elements(p_loans) e GROUP BY 1
    LOOP
        IF d.loanid IS NULL THEN RAISE EXCEPTION 'A loan deduction is missing its loan.'; END IF;
        IF d.n > 1 THEN RAISE EXCEPTION 'The same loan is listed twice on this payroll line.'; END IF;
        IF d.amount < 0 THEN RAISE EXCEPTION 'A loan deduction cannot be negative.'; END IF;
        CONTINUE WHEN d.amount = 0;
        SELECT * INTO l FROM restaurantstaffloans WHERE staffloanid = d.loanid AND farmid = p_farmid FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Loan #% does not belong to this restaurant.', d.loanid; END IF;
        IF l.restaurantstaffid <> p_staffid THEN
            RAISE EXCEPTION 'Loan % belongs to %, not to %.', l.loannumber, l.staffname, p_staffname; END IF;
        IF l.status <> 'Active' THEN RAISE EXCEPTION 'Loan % is %, so nothing can be deducted for it.', l.loannumber, l.status; END IF;
        SELECT COALESCE(SUM(x.amount), 0) INTO v_other FROM restaurantpayrolldeductions x
         WHERE x.staffloanid = d.loanid AND x.status = 'Draft' AND x.payrolllineid <> p_lineid;
        IF d.amount > l.outstandingbalance - v_other THEN
            RAISE EXCEPTION 'At most % can be deducted for loan % (% owes %, and % is already set aside on another draft payroll).',
                GREATEST(l.outstandingbalance - v_other, 0), l.loannumber, p_staffname, l.outstandingbalance, v_other;
        END IF;
    END LOOP;

    DELETE FROM restaurantpayrolldeductions x
     WHERE x.payrolllineid = p_lineid AND x.status = 'Draft'
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p_loans) e
                        WHERE (e->>'loanId')::INT = x.staffloanid AND COALESCE((e->>'amount')::NUMERIC, 0) > 0);

    FOR d IN SELECT (e->>'loanId')::INT AS loanid, ROUND((e->>'amount')::NUMERIC, 2) AS amount
               FROM jsonb_array_elements(p_loans) e WHERE COALESCE((e->>'amount')::NUMERIC, 0) > 0
    LOOP
        UPDATE restaurantpayrolldeductions x SET amount = d.amount, updatedat = NOW()
         WHERE x.payrolllineid = p_lineid AND x.staffloanid = d.loanid AND x.status = 'Draft';
        IF NOT FOUND THEN
            INSERT INTO restaurantpayrolldeductions (farmid, payrollrunid, payrolllineid, restaurantstaffid, staffloanid,
                   deductiontype, amount, createdby)
            SELECT p_farmid, p_runid, p_lineid, p_staffid, d.loanid,
                   CASE WHEN l2.loantype = 'SalaryAdvance' THEN 'SalaryAdvanceRepayment' ELSE 'EmployeeLoanRepayment' END,
                   d.amount, p_by
              FROM restaurantstaffloans l2 WHERE l2.staffloanid = d.loanid;
        END IF;
    END LOOP;
END $$;

-- Save one payroll line in place (so its loan deductions survive).
--   p_loans NULL  -> keep this line's loan deductions as they are
--   p_loans array -> replace them: [{"loanId": 3, "amount": 200}, ...]
CREATE FUNCTION sprestaurant_payrollline_save(
    p_farmid TEXT, p_runid INT, p_staffid INT, p_basicpay NUMERIC, p_allowances NUMERIC, p_overtime NUMERIC,
    p_bonus NUMERIC, p_otherdeductions NUMERIC, p_paymentmethod TEXT, p_notes TEXT, p_loans JSONB, p_by TEXT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_status TEXT; v_name TEXT; v_role TEXT; v_type TEXT; v_line INT; v_gross NUMERIC; v_ded NUMERIC;
BEGIN
    SELECT status INTO v_status FROM restaurantpayrollruns WHERE payrollrunid = p_runid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payroll run not found.'; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'This payroll run is %. Lines can only change while it is a Draft (reopen it first).', v_status; END IF;
    SELECT btrim(s.firstname || ' ' || COALESCE(s.lastname, '')), s.role, s.salarytype INTO v_name, v_role, v_type
      FROM restaurantstaff s WHERE s.restaurantstaffid = p_staffid AND s.farmid = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Choose a staff member of this restaurant.'; END IF;
    IF LEAST(COALESCE(p_basicpay, 0), COALESCE(p_allowances, 0), COALESCE(p_overtime, 0), COALESCE(p_bonus, 0),
             COALESCE(p_otherdeductions, 0)) < 0 THEN
        RAISE EXCEPTION 'Pay and deduction amounts cannot be negative.'; END IF;

    SELECT pl.payrolllineid INTO v_line FROM restaurantpayrolllines pl
     WHERE pl.payrollrunid = p_runid AND pl.restaurantstaffid = p_staffid;
    IF v_line IS NULL THEN
        INSERT INTO restaurantpayrolllines (payrollrunid, farmid, restaurantstaffid, staffname, staffrole, salarytype,
               basicpay, allowances, overtime, bonus, otherdeductions, paymentmethod, notes)
        VALUES (p_runid, p_farmid, p_staffid, v_name, v_role, v_type,
               ROUND(COALESCE(p_basicpay, 0), 2), ROUND(COALESCE(p_allowances, 0), 2), ROUND(COALESCE(p_overtime, 0), 2),
               ROUND(COALESCE(p_bonus, 0), 2), ROUND(COALESCE(p_otherdeductions, 0), 2),
               COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash'), NULLIF(btrim(p_notes), ''))
        RETURNING payrolllineid INTO v_line;
    ELSE
        UPDATE restaurantpayrolllines SET staffname = v_name, staffrole = v_role, salarytype = v_type,
               basicpay = ROUND(COALESCE(p_basicpay, 0), 2), allowances = ROUND(COALESCE(p_allowances, 0), 2),
               overtime = ROUND(COALESCE(p_overtime, 0), 2), bonus = ROUND(COALESCE(p_bonus, 0), 2),
               otherdeductions = ROUND(COALESCE(p_otherdeductions, 0), 2),
               paymentmethod = COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash'), notes = NULLIF(btrim(p_notes), ''),
               updatedat = NOW()
         WHERE payrolllineid = v_line;
    END IF;

    IF p_loans IS NOT NULL THEN
        PERFORM fnrestaurant_payrollline_setloans(p_farmid, p_runid, v_line, p_staffid, v_name, p_loans, p_by);
    END IF;

    SELECT pl.basicpay + pl.allowances + pl.overtime + pl.bonus, pl.otherdeductions INTO v_gross, v_ded
      FROM restaurantpayrolllines pl WHERE pl.payrolllineid = v_line;
    v_ded := v_ded + COALESCE((SELECT SUM(x.amount) FROM restaurantpayrolldeductions x
                                WHERE x.payrolllineid = v_line AND x.status <> 'Reversed'), 0);
    IF v_ded > v_gross THEN
        RAISE EXCEPTION 'Deductions for % (%) are more than their gross pay (%).', v_name, v_ded, v_gross; END IF;

    PERFORM fnrestaurant_payrollrun_recalc(p_runid);
    RETURN v_line;
END $$;

CREATE FUNCTION sprestaurant_payrollline_delete(p_farmid TEXT, p_lineid INT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_run INT; v_status TEXT;
BEGIN
    SELECT r.payrollrunid, r.status INTO v_run, v_status
      FROM restaurantpayrolllines pl JOIN restaurantpayrollruns r ON r.payrollrunid = pl.payrollrunid
     WHERE pl.payrolllineid = p_lineid AND r.farmid = p_farmid
       FOR UPDATE OF r;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payroll line not found.'; END IF;
    IF v_status <> 'Draft' THEN RAISE EXCEPTION 'This payroll run is %. Lines can only be removed while it is a Draft.', v_status; END IF;
    DELETE FROM restaurantpayrolllines WHERE payrolllineid = p_lineid;
    PERFORM fnrestaurant_payrollrun_recalc(v_run);
END $$;

-- Add every active staff member not yet on the run, at their base pay, with
-- their open loans' suggested deductions (capped so net pay stays >= 0).
CREATE FUNCTION sprestaurant_payrollrun_addallstaff(p_farmid TEXT, p_runid INT, p_by TEXT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE s record; e record; v_room NUMERIC; v_amt NUMERIC; v_loans JSONB; v_n INT := 0;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM restaurantpayrollruns WHERE payrollrunid = p_runid AND farmid = p_farmid AND status = 'Draft') THEN
        RAISE EXCEPTION 'Staff can only be added to a Draft payroll run.'; END IF;
    FOR s IN
        SELECT st.restaurantstaffid, st.basepay FROM restaurantstaff st
         WHERE st.farmid = p_farmid AND st.isactive
           AND NOT EXISTS (SELECT 1 FROM restaurantpayrolllines pl WHERE pl.payrollrunid = p_runid
                             AND pl.restaurantstaffid = st.restaurantstaffid)
         ORDER BY st.firstname, st.lastname
    LOOP
        v_room := COALESCE(s.basepay, 0);
        v_loans := '[]'::JSONB;
        FOR e IN SELECT * FROM sprestaurant_staffloan_eligible(p_farmid, s.restaurantstaffid, NULL) LOOP
            v_amt := LEAST(e.suggesteddeduction, GREATEST(v_room, 0));
            IF v_amt > 0 THEN
                v_loans := v_loans || jsonb_build_object('loanId', e.staffloanid, 'amount', v_amt);
                v_room := v_room - v_amt;
            END IF;
        END LOOP;
        PERFORM sprestaurant_payrollline_save(p_farmid, p_runid, s.restaurantstaffid, COALESCE(s.basepay, 0), 0, 0, 0, 0,
                                              'Cash', NULL, v_loans, p_by);
        v_n := v_n + 1;
    END LOOP;
    RETURN v_n;
END $$;

-- Approve: Draft -> Approved. Each draft loan deduction becomes a Payroll
-- repayment dated the pay date. All or nothing.
CREATE FUNCTION sprestaurant_payrollrun_approve(p_farmid TEXT, p_runid INT, p_by TEXT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v restaurantpayrollruns%ROWTYPE; d record; v_rep INT; v_n INT := 0; v_neg TEXT;
BEGIN
    SELECT * INTO v FROM restaurantpayrollruns WHERE payrollrunid = p_runid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payroll run not found.'; END IF;
    IF v.status <> 'Draft' THEN RAISE EXCEPTION 'Only a Draft payroll run can be approved (this one is %).', v.status; END IF;
    IF NOT EXISTS (SELECT 1 FROM restaurantpayrolllines pl WHERE pl.payrollrunid = p_runid) THEN
        RAISE EXCEPTION 'Add at least one staff member before approving.'; END IF;
    PERFORM fnrestaurant_payrollrun_recalc(p_runid);
    SELECT string_agg(pl.staffname, ', ') INTO v_neg FROM restaurantpayrolllines pl
     WHERE pl.payrollrunid = p_runid AND pl.netpay < 0;
    IF v_neg IS NOT NULL THEN RAISE EXCEPTION 'Net pay would be below zero for: %. Reduce their deductions first.', v_neg; END IF;

    FOR d IN
        SELECT x.*, l.loannumber, pl.staffname
          FROM restaurantpayrolldeductions x
          JOIN restaurantstaffloans l ON l.staffloanid = x.staffloanid
          JOIN restaurantpayrolllines pl ON pl.payrolllineid = x.payrolllineid
         WHERE x.payrollrunid = p_runid AND x.status = 'Draft'
         ORDER BY x.payrolldeductionid
    LOOP
        BEGIN
            v_rep := sprestaurant_staffloanrepayment_record(p_farmid, d.staffloanid, d.amount, 'Payroll', NULL,
                        v.paydate, v.runnumber, 'Payroll ' || v.runnumber, p_by, d.payrolldeductionid, p_runid);
        EXCEPTION WHEN raise_exception THEN
            RAISE EXCEPTION 'Could not deduct % from % for loan %: %', d.amount, d.staffname, d.loannumber, SQLERRM;
        END;
        UPDATE restaurantpayrolldeductions SET status = 'Posted', repaymentid = v_rep, updatedat = NOW()
         WHERE payrolldeductionid = d.payrolldeductionid;
        v_n := v_n + 1;
    END LOOP;

    UPDATE restaurantpayrollruns SET status = 'Approved', approvedby = p_by, approvedat = NOW(), updatedat = NOW()
     WHERE payrollrunid = p_runid;
    RETURN v_n;
END $$;

CREATE FUNCTION fnrestaurant_payrollrun_reverserepayments(p_farmid TEXT, p_runid INT, p_reason TEXT, p_by TEXT, p_newstatus TEXT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE d record; v_n INT := 0;
BEGIN
    FOR d IN SELECT * FROM restaurantpayrolldeductions x WHERE x.payrollrunid = p_runid AND x.status = 'Posted'
              ORDER BY x.payrolldeductionid
    LOOP
        IF d.repaymentid IS NOT NULL THEN
            PERFORM sprestaurant_staffloanrepayment_reverse(p_farmid, d.repaymentid, p_reason, p_by, TRUE);
        END IF;
        UPDATE restaurantpayrolldeductions SET status = p_newstatus,
               repaymentid = CASE WHEN p_newstatus = 'Draft' THEN NULL ELSE repaymentid END, updatedat = NOW()
         WHERE payrolldeductionid = d.payrolldeductionid;
        v_n := v_n + 1;
    END LOOP;
    RETURN v_n;
END $$;

-- Reopen: Approved -> Draft, to correct a run before it is paid.
CREATE FUNCTION sprestaurant_payrollrun_unapprove(p_farmid TEXT, p_runid INT, p_reason TEXT, p_by TEXT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_status TEXT; v_num TEXT; v_n INT;
BEGIN
    SELECT status, runnumber INTO v_status, v_num FROM restaurantpayrollruns WHERE payrollrunid = p_runid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payroll run not found.'; END IF;
    IF v_status <> 'Approved' THEN RAISE EXCEPTION 'Only an Approved payroll run can be reopened (this one is %).', v_status; END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN RAISE EXCEPTION 'Give a reason for reopening the payroll run.'; END IF;
    v_n := fnrestaurant_payrollrun_reverserepayments(p_farmid, p_runid, 'Payroll ' || v_num || ' reopened: ' || btrim(p_reason), p_by, 'Draft');
    UPDATE restaurantpayrollruns SET status = 'Draft', approvedby = NULL, approvedat = NULL,
           reopenedby = p_by, reopenedat = NOW(), reopenreason = btrim(p_reason), updatedat = NOW()
     WHERE payrollrunid = p_runid;
    PERFORM fnrestaurant_payrollrun_recalc(p_runid);
    RETURN v_n;
END $$;

CREATE FUNCTION sprestaurant_payrollrun_cancel(p_farmid TEXT, p_runid INT, p_reason TEXT, p_by TEXT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_status TEXT; v_num TEXT; v_n INT;
BEGIN
    SELECT status, runnumber INTO v_status, v_num FROM restaurantpayrollruns WHERE payrollrunid = p_runid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payroll run not found.'; END IF;
    IF v_status NOT IN ('Draft', 'Approved') THEN
        RAISE EXCEPTION 'Only a Draft or Approved payroll run can be cancelled (this one is %).', v_status; END IF;
    v_n := fnrestaurant_payrollrun_reverserepayments(p_farmid, p_runid,
              'Payroll ' || v_num || ' cancelled' || COALESCE(': ' || NULLIF(btrim(p_reason), ''), ''), p_by, 'Reversed');
    UPDATE restaurantpayrolldeductions SET status = 'Reversed', updatedat = NOW() WHERE payrollrunid = p_runid AND status = 'Draft';
    UPDATE restaurantpayrollruns SET status = 'Cancelled', cancelledby = p_by, cancelledat = NOW(),
           cancelreason = NULLIF(btrim(p_reason), ''), updatedat = NOW()
     WHERE payrollrunid = p_runid;
    RETURN v_n;
END $$;

-- Mark paid: Approved -> Paid. NET pay leaves the chosen account (the run's, or
-- the Main Cash Box). Posted once per run (ledger key Payroll/runid).
CREATE FUNCTION sprestaurant_payrollrun_markpaid(p_farmid TEXT, p_runid INT, p_paydate DATE, p_cashaccountid INT, p_by TEXT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v restaurantpayrollruns%ROWTYPE; v_date DATE; v_acct INT; v_txn INT;
BEGIN
    SELECT * INTO v FROM restaurantpayrollruns WHERE payrollrunid = p_runid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payroll run not found.'; END IF;
    IF v.status <> 'Approved' THEN RAISE EXCEPTION 'Only an Approved payroll run can be marked paid (this one is %).', v.status; END IF;
    v_date := COALESCE(p_paydate, LEAST(v.paydate, CURRENT_DATE));
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'Wages cannot be marked paid on a future date.'; END IF;
    PERFORM fnrestaurant_assert_day_open(p_farmid, v_date);
    v_acct := COALESCE(p_cashaccountid, v.cashaccountid, fnrestaurant_default_account(p_farmid, 'Cash'));
    IF v.totalnet > 0 THEN
        v_txn := fnrestaurant_post(p_farmid, v_acct, v_date, -v.totalnet, 'Payroll', p_runid,
            'Payroll ' || v.runnumber || ' (' || to_char(v.periodstart, 'DD Mon') || ' – ' || to_char(v.periodend, 'DD Mon YYYY') || ') net pay',
            p_by);
    END IF;
    UPDATE restaurantpayrollruns SET status = 'Paid', paidby = p_by, paidat = NOW(), paydate = v_date,
           cashaccountid = v_acct, cashtxnid = v_txn, updatedat = NOW()
     WHERE payrollrunid = p_runid;
    RETURN v_txn;
END $$;

-- Delete: only a Draft (nothing posted) or a Cancelled run (everything reversed).
CREATE FUNCTION sprestaurant_payrollrun_delete(p_farmid TEXT, p_runid INT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE v_status TEXT;
BEGIN
    SELECT status INTO v_status FROM restaurantpayrollruns WHERE payrollrunid = p_runid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payroll run not found.'; END IF;
    IF v_status NOT IN ('Draft', 'Cancelled') THEN RAISE EXCEPTION 'Only a Draft or Cancelled payroll run can be deleted.'; END IF;
    DELETE FROM restaurantpayrollruns WHERE payrollrunid = p_runid;   -- lines and deductions cascade
END $$;

-- Per staff member, runs PAID in the period (by pay date).
CREATE FUNCTION sprestaurant_payroll_report(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(restaurantstaffid INT, staffname TEXT, staffrole TEXT, runs INT, basicpay NUMERIC, extras NUMERIC,
              grosspay NUMERIC, otherdeductions NUMERIC, loandeductions NUMERIC, netpay NUMERIC)
LANGUAGE sql STABLE AS $$
    SELECT pl.restaurantstaffid, MAX(pl.staffname), MAX(pl.staffrole), COUNT(DISTINCT r.payrollrunid)::INT,
           SUM(pl.basicpay), SUM(pl.allowances + pl.overtime + pl.bonus), SUM(pl.grosspay),
           SUM(pl.otherdeductions), SUM(pl.loandeductions), SUM(pl.netpay)
      FROM restaurantpayrolllines pl
      JOIN restaurantpayrollruns r ON r.payrollrunid = pl.payrollrunid
     WHERE r.farmid = p_farmid AND r.status = 'Paid' AND r.paydate BETWEEN p_from AND p_to
     GROUP BY pl.restaurantstaffid
     ORDER BY SUM(pl.grosspay) DESC;
$$;

-- -----------------------------------------------------------------------------
-- 4. Cash Flow, P&L and the profit-vs-cash bridge, extended for payroll and
--    staff loans. Copied from 323 / 324 with only the marked additions; same
--    signatures and result columns, so CREATE OR REPLACE is enough.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sprestaurantcashflow_rows(p_farmid TEXT, p_fromdate TIMESTAMP DEFAULT NULL,
                                          p_todate TIMESTAMP DEFAULT NULL)
RETURNS TABLE(rowsource TEXT, offledger BOOLEAN, sourcerowid INT, cashaccountid INT, accountname TEXT,
              transactiondate TIMESTAMP, transactiontype TEXT, sourcetype TEXT, sourceid INT,
              istransfer BOOLEAN, amount NUMERIC, description TEXT, flowgroup TEXT, createdat TIMESTAMP)
LANGUAGE sql STABLE AS $$
    SELECT t.sourcetype, FALSE, t.cashtxnid, t.cashaccountid, a.name, t.txndate::TIMESTAMP, t.txntype,
           t.sourcetype, t.sourceid, FALSE, t.amount, t.description,
           CASE WHEN t.sourcetype LIKE 'EmployeeLoan%'
                THEN CASE WHEN t.amount > 0 THEN 'EmployeeLoanIn' ELSE 'EmployeeLoanOut' END
                WHEN t.sourcetype LIKE 'Owner%' OR t.sourcetype LIKE 'Loan%'
                THEN CASE WHEN t.amount > 0 THEN 'FinancingIn' ELSE 'FinancingOut' END
                ELSE CASE WHEN t.amount > 0 THEN 'OperatingIn' ELSE 'OperatingOut' END END,
           t.createdat
      FROM restaurantcashtransactions t
      JOIN restaurantcashaccounts a ON a.cashaccountid = t.cashaccountid
     WHERE t.farmid = p_farmid
       AND t.sourcetype NOT IN ('OpeningBalance', 'TransferOut', 'TransferIn', 'TransferReversalOut',
                                'TransferReversalIn', 'ShiftFloatOut', 'ShiftFloatIn', 'ShiftDropOut', 'ShiftDropIn')
       AND (p_fromdate IS NULL OR t.txndate::TIMESTAMP >= p_fromdate)
       AND (p_todate IS NULL OR t.txndate::TIMESTAMP <= p_todate);
$$;

CREATE OR REPLACE FUNCTION sprestaurantcashflow_detail(p_farmid TEXT, p_fromdate TIMESTAMP DEFAULT NULL,
                                            p_todate TIMESTAMP DEFAULT NULL)
RETURNS TABLE(rowsource TEXT, offledger BOOLEAN, sourcerowid INT, cashaccountid INT, accountname TEXT,
              transactiondate TIMESTAMP, transactiontype TEXT, sourcetype TEXT, sourceid INT,
              istransfer BOOLEAN, amount NUMERIC, description TEXT, flowgroup TEXT, category TEXT,
              createdat TIMESTAMP)
LANGUAGE sql STABLE AS $$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid, r.accountname, r.transactiondate,
           r.transactiontype, r.sourcetype, r.sourceid, r.istransfer, r.amount, r.description, r.flowgroup,
           CASE r.sourcetype
               WHEN 'OrderPayment' THEN 'Sales (' || COALESCE(NULLIF(btrim(p.paymentmethod), ''), 'Cash') || ')'
               WHEN 'OrderRefund' THEN 'Refunds to customers'
               WHEN 'Expense' THEN COALESCE(NULLIF(btrim(e.categoryname), ''), 'Uncategorised')
               WHEN 'ExpenseReversal' THEN 'Expense corrections'
               WHEN 'GiftCardSale' THEN 'Gift card sales'
               WHEN 'GiftCardReload' THEN 'Gift card sales'
               WHEN 'OwnerContribution' THEN 'Owner contributions'
               WHEN 'OwnerDraw' THEN 'Owner drawings'
               WHEN 'OwnerContributionReversal' THEN 'Owner money corrections'
               WHEN 'OwnerDrawReversal' THEN 'Owner money corrections'
               WHEN 'LoanReceived' THEN 'Loans received'
               WHEN 'LoanRepayment' THEN 'Loan repayments'
               WHEN 'LoanRepaymentReversal' THEN 'Loan corrections'
               WHEN 'LoanReceivedReversal' THEN 'Loan corrections'
               WHEN 'ShiftVariance' THEN 'Cash over / short'
               WHEN 'CountVariance' THEN 'Cash over / short'
               WHEN 'CountVarianceReversal' THEN 'Cash over / short'
               WHEN 'Payroll' THEN 'Staff wages (net pay)'
               WHEN 'EmployeeLoanDisbursement' THEN 'Staff advances paid out'
               WHEN 'EmployeeLoanReversal' THEN 'Staff advance corrections'
               WHEN 'EmployeeLoanRepayment' THEN 'Staff advances repaid'
               WHEN 'EmployeeLoanRepaymentReversal' THEN 'Staff advance corrections'
               ELSE 'Other' END::TEXT,
           r.createdat
      FROM sprestaurantcashflow_rows(p_farmid, p_fromdate, p_todate) r
      LEFT JOIN restaurantorderpayments p ON r.sourcetype = 'OrderPayment' AND p.orderpaymentid = r.sourceid
      LEFT JOIN restaurantexpenses e ON r.sourcetype = 'Expense' AND e.expenseid = r.sourceid;
$$;

CREATE OR REPLACE FUNCTION sprestaurant_report_pnl_lines(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(section TEXT, linekey TEXT, label TEXT, amount NUMERIC, sortorder INT)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE v_sales NUMERIC; v_disc NUMERIC; v_sc NUMERIC; v_fee NUMERIC; v_ref NUMERIC; v_cogs NUMERIC;
        v_int NUMERIC; v_fees NUMERIC; v_var NUMERIC; v_wages NUMERIC; v_slint NUMERIC;
BEGIN
    SELECT COALESCE(SUM(o.subtotal), 0), COALESCE(SUM(o.discountamount), 0),
           COALESCE(SUM(o.servicechargeamount), 0), COALESCE(SUM(o.deliveryfee), 0)
      INTO v_sales, v_disc, v_sc, v_fee
      FROM restaurantorders o
     WHERE o.farmid = p_farmid AND o.status = 'Completed'
       AND o.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(p.amount), 0) INTO v_ref
      FROM restaurantorderpayments p
      JOIN restaurantorders o ON o.orderid = p.orderid AND o.farmid = p.farmid
     WHERE p.farmid = p_farmid AND p.amount < 0 AND p.status = 'Completed' AND o.status = 'Completed'
       AND p.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(oi.quantity * COALESCE((
               SELECT SUM(r.quantity * (1 + COALESCE(r.wastepercent, 0) / 100) * i.costperunit)
                 FROM restaurantrecipes r
                 JOIN restaurantingredients i ON i.ingredientid = r.ingredientid AND i.farmid = r.farmid
                WHERE r.menuitemid = oi.menuitemid AND r.farmid = oi.farmid), 0)), 0)
      INTO v_cogs
      FROM restaurantorderitems oi
      JOIN restaurantorders o ON o.orderid = oi.orderid AND o.farmid = oi.farmid
     WHERE oi.farmid = p_farmid AND o.status = 'Completed' AND oi.status <> 'Cancelled'
       AND o.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(lp.interestamount), 0), COALESCE(SUM(lp.feeamount), 0)
      INTO v_int, v_fees
      FROM restaurantloanpayments lp
     WHERE lp.farmid = p_farmid AND lp.status = 'Posted' AND lp.paymentdate BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(t.amount), 0) INTO v_var
      FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.sourcetype IN ('ShiftVariance', 'CountVariance', 'CountVarianceReversal')
       AND t.txndate BETWEEN p_from AND p_to;

    -- Staff wages at GROSS pay for runs paid in the period (326). Loan deductions
    -- and other withholdings are still a wage cost.
    SELECT COALESCE(SUM(r.totalgross), 0) INTO v_wages
      FROM restaurantpayrollruns r
     WHERE r.farmid = p_farmid AND r.status = 'Paid' AND r.paydate BETWEEN p_from AND p_to;

    -- Interest repaid on staff loans (326): the one part of a staff loan that is income.
    SELECT COALESCE(SUM(sr.interestamount), 0) INTO v_slint
      FROM restaurantstaffloanrepayments sr
     WHERE sr.farmid = p_farmid AND sr.status = 'Posted' AND sr.repaymentdate BETWEEN p_from AND p_to;

    RETURN QUERY VALUES
        ('Revenue', 'food_sales', 'Food & beverage sales', ROUND(v_sales, 2), 10),
        ('Revenue', 'discounts', 'Less: discounts & promotions', ROUND(-v_disc, 2), 11),
        ('Revenue', 'refunds', 'Less: partial refunds', ROUND(v_ref, 2), 12),
        ('Revenue', 'service_charge', 'Service charge', ROUND(v_sc, 2), 13),
        ('Revenue', 'delivery_fees', 'Delivery fees', ROUND(v_fee, 2), 14),
        ('CostOfSales', 'recipe_cost', 'Ingredients (recipe cost)', ROUND(-v_cogs, 2), 20);

    IF v_wages <> 0 THEN
        RETURN QUERY VALUES ('Expenses', 'staff_wages', 'Staff wages (payroll)', ROUND(-v_wages, 2), 29);
    END IF;

    RETURN QUERY
    SELECT 'Expenses'::TEXT, 'expense:' || COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised'),
           COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised'), ROUND(-SUM(e.amount), 2), 30
      FROM restaurantexpenses e
     WHERE e.farmid = p_farmid AND e.expensedate BETWEEN p_from AND p_to
       AND COALESCE(e.status, 'Approved') NOT IN ('Rejected', 'Draft')
     GROUP BY COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised')
     ORDER BY SUM(e.amount) DESC;

    RETURN QUERY VALUES
        ('Other', 'loan_interest', 'Loan interest', ROUND(-v_int, 2), 40),
        ('Other', 'loan_fees', 'Loan fees', ROUND(-v_fees, 2), 41),
        ('Other', 'cash_variance', 'Cash over / short', ROUND(v_var, 2), 42);
    IF v_slint <> 0 THEN
        RETURN QUERY VALUES ('Other', 'staff_loan_interest', 'Interest on staff loans', ROUND(v_slint, 2), 43);
    END IF;
END $$;

CREATE OR REPLACE FUNCTION sprestaurant_report_pnl_expenses(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(expense_category TEXT, entry_count BIGINT, expense_total NUMERIC, share_pct NUMERIC)
LANGUAGE sql STABLE AS $$
    WITH x AS (
        SELECT COALESCE(NULLIF(e.categoryname, ''), 'Uncategorised') AS cat, COUNT(*) AS n, SUM(e.amount) AS tot
          FROM restaurantexpenses e
         WHERE e.farmid = p_farmid AND e.expensedate BETWEEN p_from AND p_to
           AND COALESCE(e.status, 'Approved') NOT IN ('Rejected', 'Draft')
         GROUP BY 1
        UNION ALL
        SELECT 'Loan interest & fees', COUNT(*), SUM(lp.interestamount + lp.feeamount)
          FROM restaurantloanpayments lp
         WHERE lp.farmid = p_farmid AND lp.status = 'Posted' AND lp.paymentdate BETWEEN p_from AND p_to
        HAVING SUM(lp.interestamount + lp.feeamount) > 0
        UNION ALL
        SELECT 'Staff wages (payroll)', COUNT(*), SUM(r.totalgross)
          FROM restaurantpayrollruns r
         WHERE r.farmid = p_farmid AND r.status = 'Paid' AND r.paydate BETWEEN p_from AND p_to
        HAVING COALESCE(SUM(r.totalgross), 0) <> 0
        UNION ALL
        SELECT 'Interest on staff loans (income)', COUNT(*), -SUM(sr.interestamount)
          FROM restaurantstaffloanrepayments sr
         WHERE sr.farmid = p_farmid AND sr.status = 'Posted' AND sr.repaymentdate BETWEEN p_from AND p_to
        HAVING COALESCE(SUM(sr.interestamount), 0) <> 0
        UNION ALL
        SELECT 'Cash over / short', COUNT(*), -SUM(t.amount)
          FROM restaurantcashtransactions t
         WHERE t.farmid = p_farmid AND t.sourcetype IN ('ShiftVariance', 'CountVariance', 'CountVarianceReversal')
           AND t.txndate BETWEEN p_from AND p_to
        HAVING COALESCE(SUM(t.amount), 0) <> 0
    ), tot AS (SELECT COALESCE(SUM(x.tot), 0) AS allv FROM x)
    SELECT x.cat, x.n, ROUND(x.tot, 2),
           CASE WHEN tot.allv <> 0 THEN ROUND(x.tot / tot.allv * 100, 2) ELSE 0 END
      FROM x, tot
     ORDER BY x.tot DESC;
$$;

CREATE OR REPLACE FUNCTION sprestaurant_report_cash_profit_bridge(p_farmid TEXT, p_from DATE, p_to DATE)
RETURNS TABLE(sortorder INT, linekey TEXT, label TEXT, amount NUMERIC, kind TEXT, explanation TEXT)
LANGUAGE plpgsql STABLE AS $$
#variable_conflict use_column
DECLARE
    v_profit NUMERIC; v_rev NUMERIC; v_cogs NUMERIC; v_exp_pl NUMERIC;
    v_tax NUMERIC; v_tips NUMERIC; v_gift_paid NUMERIC; v_sales_cash NUMERIC;
    v_gift_sold NUMERIC; v_exp_cash NUMERIC; v_loan_int NUMERIC; v_loan_cash NUMERIC;
    v_loan_in NUMERIC; v_owner NUMERIC; v_var NUMERIC; v_net NUMERIC;
    v_sales_timing NUMERIC; v_exp_timing NUMERIC; v_principal NUMERIC;
    v_wages_pl NUMERIC; v_wages_cash NUMERIC; v_slint NUMERIC; v_adv_out NUMERIC; v_adv_in NUMERIC;
BEGIN
    SELECT s.net_profit, s.revenue, s.cogs INTO v_profit, v_rev, v_cogs
      FROM sprestaurant_report_pnl_summary(p_farmid, p_from, p_to) s;

    -- Staff wages (326) are bridged on their own line, not as expense timing.
    SELECT COALESCE(-SUM(l.amount) FILTER (WHERE l.section = 'Expenses' AND l.linekey <> 'staff_wages'), 0),
           COALESCE(-SUM(l.amount) FILTER (WHERE l.linekey IN ('loan_interest', 'loan_fees')), 0),
           COALESCE(SUM(l.amount) FILTER (WHERE l.linekey = 'cash_variance'), 0)
      INTO v_exp_pl, v_loan_int, v_var
      FROM sprestaurant_report_pnl_lines(p_farmid, p_from, p_to) l;

    SELECT COALESCE(-SUM(l.amount) FILTER (WHERE l.linekey = 'staff_wages'), 0),
           COALESCE(SUM(l.amount) FILTER (WHERE l.linekey = 'staff_loan_interest'), 0)
      INTO v_wages_pl, v_slint
      FROM sprestaurant_report_pnl_lines(p_farmid, p_from, p_to) l;

    -- Net pay that actually left, advances paid out (less reversals) and
    -- advances repaid in cash (less reversals), as the ledger recorded them.
    SELECT COALESCE(-SUM(t.amount) FILTER (WHERE t.sourcetype = 'Payroll'), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('EmployeeLoanDisbursement', 'EmployeeLoanReversal')), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('EmployeeLoanRepayment', 'EmployeeLoanRepaymentReversal')), 0)
      INTO v_wages_cash, v_adv_out, v_adv_in
      FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.txndate BETWEEN p_from AND p_to;

    -- Tax on the orders the P&L counted: the customer paid it, it is not revenue.
    SELECT COALESCE(SUM(o.taxamount), 0) INTO v_tax FROM restaurantorders o
     WHERE o.farmid = p_farmid AND o.status = 'Completed' AND o.createdat::DATE BETWEEN p_from AND p_to;

    -- Order money as the ledger recorded it (payments incl. tips, less refunds).
    SELECT COALESCE(SUM(t.amount), 0) INTO v_sales_cash FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.sourcetype IN ('OrderPayment', 'OrderRefund')
       AND t.txndate BETWEEN p_from AND p_to;
    SELECT COALESCE(SUM(p.tipamount), 0) INTO v_tips FROM restaurantorderpayments p
     WHERE p.farmid = p_farmid AND p.status = 'Completed' AND p.amount > 0
       AND p.createdat::DATE BETWEEN p_from AND p_to;
    SELECT COALESCE(SUM(p.amount), 0) INTO v_gift_paid FROM restaurantorderpayments p
     WHERE p.farmid = p_farmid AND p.status = 'Completed' AND p.amount > 0
       AND NOT fnrestaurant_is_cash_method(p.paymentmethod)
       AND p.createdat::DATE BETWEEN p_from AND p_to;

    SELECT COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('GiftCardSale', 'GiftCardReload')), 0),
           COALESCE(-SUM(t.amount) FILTER (WHERE t.sourcetype IN ('Expense', 'ExpenseReversal')), 0),
           COALESCE(-SUM(t.amount) FILTER (WHERE t.sourcetype IN ('LoanRepayment', 'LoanRepaymentReversal')), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype IN ('LoanReceived', 'LoanReceivedReversal')), 0),
           COALESCE(SUM(t.amount) FILTER (WHERE t.sourcetype LIKE 'Owner%'), 0)
      INTO v_gift_sold, v_exp_cash, v_loan_cash, v_loan_in, v_owner
      FROM restaurantcashtransactions t
     WHERE t.farmid = p_farmid AND t.txndate BETWEEN p_from AND p_to;

    SELECT s.netcashflow INTO v_net
      FROM sprestaurantcashflow_summary(p_farmid, p_from::TIMESTAMP, (p_to + 1)::TIMESTAMP - INTERVAL '1 microsecond') s;

    -- Sales: what the P&L counted, plus the tax and tips customers paid on top,
    -- minus what they paid with gift cards (value that came in earlier as cash).
    v_sales_timing := v_sales_cash - (v_rev + v_tax + v_tips - v_gift_paid);
    v_exp_timing := v_exp_pl - v_exp_cash;          -- + when the P&L cost more than was paid out
    v_principal := v_loan_cash - v_loan_int;        -- principal leaves cash but is not a cost

    RETURN QUERY VALUES
        (10, 'net_profit', 'Net profit (from the P&L)', ROUND(v_profit, 2), 'start',
         'Revenue less cost of goods, expenses, loan costs and cash over/short.'),
        (20, 'cogs', 'Add back: recipe cost of food sold', ROUND(v_cogs, 2), 'adjust',
         'The P&L charges ingredient cost when food is sold; the cash left when stock was bought (recorded as expenses).'),
        (30, 'tax', 'Add: tax collected from customers', ROUND(v_tax, 2), 'adjust',
         'Customers paid it, but it is owed to the tax office, so it is not revenue.'),
        (40, 'tips', 'Add: tips received', ROUND(v_tips, 2), 'adjust',
         'Tips come into the till but belong to staff, so they are not revenue.'),
        (50, 'gift_paid', 'Less: sales paid with gift cards', ROUND(-v_gift_paid, 2), 'adjust',
         'Revenue with no cash today — the cash came in when the card was sold.'),
        (60, 'gift_sold', 'Add: gift cards sold and reloaded', ROUND(v_gift_sold, 2), 'adjust',
         'Cash received for food not yet served. It becomes revenue when the card is used.'),
        (70, 'sales_timing', 'Sales timing differences', ROUND(v_sales_timing, 2), 'adjust',
         'Payments taken this period for orders counted in another period (or the reverse), and full refunds.'),
        (80, 'expense_timing', 'Expense timing differences', ROUND(v_exp_timing, 2), 'adjust',
         'Expenses counted in the P&L but paid in another period, or paid without a cash movement.'),
        (90, 'loan_in', 'Add: loans received', ROUND(v_loan_in, 2), 'adjust',
         'Borrowed money is cash in but not income.'),
        (100, 'loan_principal', 'Less: loan principal repaid', ROUND(-v_principal, 2), 'adjust',
         'Paying back what was borrowed is cash out but not a cost. Interest and fees are already in the P&L.'),
        (110, 'owner', 'Add: owner money (contributions less drawings)', ROUND(v_owner, 2), 'adjust',
         'Owner money moves cash but is never income or expense.'),
        (120, 'wages_withheld', 'Add back: wages not paid out in cash', ROUND(v_wages_pl - v_wages_cash, 2), 'adjust',
         'The P&L charges gross wages; only net pay left the till. The rest repaid staff loans or was withheld.'),
        (130, 'staff_advances_out', 'Less: staff advances paid out', ROUND(v_adv_out, 2), 'adjust',
         'Money lent to staff is cash out but not a cost: they owe it back.'),
        (140, 'staff_advances_in', 'Add: staff advances repaid in cash', ROUND(v_adv_in, 2), 'adjust',
         'Staff paying back an advance is cash in but not income.'),
        (150, 'staff_loan_interest', 'Less: interest on staff loans (already in profit)', ROUND(-v_slint, 2), 'adjust',
         'Interest is counted in net profit; its cash is inside the repayment and wage lines above.'),
        (200, 'net_cash', 'Net cash flow (from Cash Flow)', ROUND(v_net, 2), 'result',
         'Money in less money out across every account, transfers excluded.'),
        (210, 'check', 'Unexplained', ROUND(v_net - (v_profit + v_cogs + v_tax + v_tips - v_gift_paid + v_gift_sold
                                                   + v_sales_timing + v_exp_timing + v_loan_in - v_principal + v_owner
                                                   + (v_wages_pl - v_wages_cash) + v_adv_out + v_adv_in - v_slint), 2),
         'check', 'Should be zero. Anything else is a ledger row this bridge does not classify yet.');
END $$;

-- -----------------------------------------------------------------------------
-- 5. Verification (read-only)
-- -----------------------------------------------------------------------------
DO $$
DECLARE v_missing TEXT;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
      FROM unnest(ARRAY[
            'sprestaurant_staffloan_create', 'sprestaurant_staffloan_update', 'sprestaurant_staffloan_disburse',
            'sprestaurant_staffloan_cancel', 'sprestaurant_staffloan_reverse',
            'sprestaurant_staffloanrepayment_record', 'sprestaurant_staffloanrepayment_reverse',
            'sprestaurant_staffloan_list', 'sprestaurant_staffloan_repayments', 'sprestaurant_staffloan_summary',
            'sprestaurant_staffloan_eligible', 'sprestaurant_staffloan_staffreport',
            'fnrestaurant_payrollrun_recalc', 'fnrestaurant_payrollrun_reverserepayments', 'fnrestaurant_payrollline_setloans',
            'sprestaurant_payrollrun_create', 'sprestaurant_payrollrun_update', 'sprestaurant_payrollrun_list',
            'sprestaurant_payrollrun_lines', 'sprestaurant_payrollrun_deductions', 'sprestaurant_payrollline_save',
            'sprestaurant_payrollline_delete', 'sprestaurant_payrollrun_addallstaff', 'sprestaurant_payrollrun_approve',
            'sprestaurant_payrollrun_unapprove', 'sprestaurant_payrollrun_cancel', 'sprestaurant_payrollrun_markpaid',
            'sprestaurant_payrollrun_delete', 'sprestaurant_payroll_report',
            'sprestaurantcashflow_rows', 'sprestaurantcashflow_detail', 'sprestaurant_report_pnl_lines',
            'sprestaurant_report_pnl_expenses', 'sprestaurant_report_cash_profit_bridge']) f
     WHERE NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = 'public' AND p.proname = f);
    IF v_missing IS NOT NULL THEN RAISE EXCEPTION '326 verification failed, missing: %', v_missing; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trgrestaurantstaff_openloanguard') THEN
        RAISE EXCEPTION '326 verification failed: staff delete guard trigger missing'; END IF;
END $$;
