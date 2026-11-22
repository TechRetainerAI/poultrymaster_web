-- =============================================================================
-- 460  Water Employee Credit + payroll "keep as credit"   (Water port of
--      poultry 441 / 442 / 392)                          (requires 458)
-- =============================================================================
--
-- Money the business is KEEPING FOR A MEMBER OF STAFF -- a worker asked not to
-- be paid every period and to collect the savings later. A liability, the
-- mirror of wateremployeeloans (staff owes us).
--
--                         payroll day           payout day
--   P&L payroll cost      gross                 nothing
--   cash out              net pay               the kept amount
--   employee credit       +kept                 -kept
--
--   PayrollSaving   +credit  P&L yes (NonCash 'PayrollEmployeeCredit')  cash no
--   WagesOwed       +credit  P&L yes (NonCash 'EmployeeCreditWages')    cash no
--   OpeningBalance  +credit  P&L no  (earned before the books)          cash no
--   Deposit         +credit  P&L no  (her own money)                    cash IN
--   Payout          -credit  P&L no                                     cash OUT
--
-- Water's payroll expense is TOTALNETPAY (316), and its loan top-up is a
-- NonCash 'PayrollEmployeeLoan' row; the kept wages get the same treatment so
-- the P&L shows the gross wage. NonCash rows are skipped by Cash Flow arm 3 and
-- by payables (sourcetype is set), and counted by the P&L.
--
-- Append-only: balance = SUM of Posted rows (Payout negative). A mistake is
-- reversed (status Reversed + a cash reversal for Deposit/Payout), never
-- deleted. Taking back credit that has already been paid out is refused.
-- Cash Flow (document-based on Water) gets its own arm: the original movement
-- on its date and a reversal on the day it was reversed.
--
-- PAYROLL (same changes poultry made):
--   * deduction type 'EmployeeCredit'; approve posts PayrollSaving credits and
--     the NonCash top-up; reopen reverses them (refused if already paid out)
--     and cancels the top-up;
--   * 442: the line form sends "other deductions" and "keep as credit"
--     separately (spwaterpayrollitem_upsert gains p_otherdeductions,
--     p_employeecredit, p_savedby; also accepts a Reopened run), and the
--     deductions recalc is a plain sum -- the old "reconcile" turned a REMOVED
--     deduction into an unexplained Other deduction. Backfilled first; no
--     line's total changes.
--   * 392: Mark paid dates the CashOut to the PAY DATE (not the click), locks
--     the account row while checking it, and marks a run with nothing left to
--     hand over (all kept as credit) Paid without moving cash.
--
-- DEPLOY ORDER: this migration, then the Farm API (the line upsert signature
-- changed), then the web. Idempotent.
-- Dry-run with database/apply-water-employee-credit.ps1.
-- =============================================================================

BEGIN;

-- ------------------------------------------------------------ 1. the ledger --
CREATE TABLE IF NOT EXISTS wateremployeecredits (
    wateremployeecreditid     serial PRIMARY KEY,
    farmid                    varchar(450) NOT NULL,
    waterstaffid              integer NOT NULL REFERENCES waterstaff (waterstaffid),
    entrytype   text NOT NULL
                CHECK (entrytype IN ('PayrollSaving', 'WagesOwed', 'OpeningBalance', 'Deposit', 'Payout')),
    amount      numeric(14,2) NOT NULL CHECK (amount > 0),
    entrydate   date NOT NULL,
    watercashaccountid        integer NULL REFERENCES watercashaccounts (watercashaccountid),
    paymentmethod             text NULL,
    watercashtransactionid    integer NULL,
    reversalcashtransactionid integer NULL,
    waterexpenseid            integer NULL,     -- WagesOwed: its NonCash payroll expense
    -- PayrollSaving: where it came from. No FK on purpose (a reopened run's
    -- REVERSED rows must keep naming it).
    waterpayrollrunid         integer NULL,
    waterpayrollitemid        integer NULL,
    waterpayrolldeductionid   integer NULL,
    reference   text NULL,
    description text NULL,
    status      text NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),
    createdby   text NULL,
    createdat   timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby  text NULL,
    reversedat  timestamp NULL,
    reversalreason text NULL,
    CONSTRAINT ck_wateremployeecredits_cash
        CHECK ((entrytype IN ('Deposit', 'Payout') AND watercashaccountid IS NOT NULL)
            OR (entrytype NOT IN ('Deposit', 'Payout') AND watercashaccountid IS NULL
                AND watercashtransactionid IS NULL)),
    CONSTRAINT ck_wateremployeecredits_payroll
        CHECK ((entrytype = 'PayrollSaving') = (waterpayrollrunid IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS ix_wateremployeecredits_staff ON wateremployeecredits (farmid, waterstaffid, status);
CREATE INDEX IF NOT EXISTS ix_wateremployeecredits_run ON wateremployeecredits (waterpayrollrunid) WHERE waterpayrollrunid IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS ux_wateremployeecredits_deduction
    ON wateremployeecredits (waterpayrolldeductionid)
    WHERE waterpayrolldeductionid IS NOT NULL AND status = 'Posted';

-- ----------------------------------------------------- 2. the deduction type --
ALTER TABLE waterpayrollitemdeductions ADD COLUMN IF NOT EXISTS wateremployeecreditid integer NULL;
ALTER TABLE waterpayrollitemdeductions DROP CONSTRAINT IF EXISTS waterpayrollitemdeductions_deductiontype_check;
ALTER TABLE waterpayrollitemdeductions ADD CONSTRAINT waterpayrollitemdeductions_deductiontype_check
    CHECK (deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment', 'OtherDeduction', 'EmployeeCredit'));
ALTER TABLE waterpayrollitemdeductions DROP CONSTRAINT IF EXISTS ck_waterpayrollitemdeductions_loan;
ALTER TABLE waterpayrollitemdeductions ADD CONSTRAINT ck_waterpayrollitemdeductions_loan
    CHECK ((deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment') AND wateremployeeloanid IS NOT NULL)
        OR (deductiontype IN ('OtherDeduction', 'EmployeeCredit') AND wateremployeeloanid IS NULL));

-- --------------------------------------------------------------- 3. balance --
CREATE OR REPLACE FUNCTION public.fnwateremployeecredit_balance(p_farmid text, p_waterstaffid integer)
RETURNS numeric LANGUAGE sql STABLE AS $function$
    SELECT COALESCE(SUM(CASE WHEN c.entrytype = 'Payout' THEN -c.amount ELSE c.amount END), 0)::numeric(14,2)
    FROM   wateremployeecredits c
    WHERE  c.farmid = p_farmid AND c.waterstaffid = p_waterstaffid AND c.status = 'Posted';
$function$;

-- Cash helper: one signed row to an account, refusing an overdraft.
CREATE OR REPLACE FUNCTION public.fnwateremployeecredit_cash(
    p_farmid text, p_accountid integer, p_date date, p_amount numeric,
    p_sourcetype text, p_sourceid integer, p_description text, p_by text)
RETURNS integer LANGUAGE plpgsql AS $function$
DECLARE
    v_allowneg boolean;
    v_bal      numeric;
    v_txid     integer;
BEGIN
    SELECT a.allownegativebalance, a.currentbalance INTO v_allowneg, v_bal
    FROM   watercashaccounts a
    WHERE  a.watercashaccountid = p_accountid AND a.farmid = p_farmid
    FOR UPDATE;
    IF v_allowneg IS NULL THEN
        RAISE EXCEPTION 'Cash account does not belong to this company.';
    END IF;
    IF p_amount < 0 AND NOT v_allowneg AND (v_bal + p_amount) < 0 THEN
        RAISE EXCEPTION 'This payment would overdraw the cash account (balance %, payment %).',
              v_bal, (-p_amount)::numeric(14,2);
    END IF;

    UPDATE watercashaccounts a
    SET    currentbalance = a.currentbalance + p_amount, updatedat = (now() at time zone 'utc')
    WHERE  a.watercashaccountid = p_accountid;

    INSERT INTO watercashtransactions
        (farmid, watercashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
         amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
    VALUES
        (p_farmid, p_accountid, p_date::timestamp,
         CASE WHEN p_amount >= 0 THEN 'CashIn' ELSE 'CashOut' END,
         p_sourcetype, p_sourceid, p_amount, v_bal + p_amount,
         left(p_description, 500), p_by, p_by, (now() at time zone 'utc'))
    RETURNING watercashtransactionid INTO v_txid;
    RETURN v_txid;
END;
$function$;

-- The company's payroll expense category (same choice as approve: Payroll,
-- Salaries, Wages; created when missing).
CREATE OR REPLACE FUNCTION public.fnwaterexpensecategory_payroll(p_farmid text)
RETURNS integer LANGUAGE plpgsql AS $function$
DECLARE v_id integer;
BEGIN
    SELECT c.waterexpensecategoryid INTO v_id
    FROM   waterexpensecategories c
    WHERE  c.farmid = p_farmid AND c.isactive = TRUE AND c.name IN ('Payroll', 'Salaries', 'Wages')
    ORDER  BY CASE c.name WHEN 'Payroll' THEN 1 WHEN 'Salaries' THEN 2 ELSE 3 END
    LIMIT  1;
    IF v_id IS NULL THEN
        INSERT INTO waterexpensecategories (farmid, name, isactive)
        VALUES (p_farmid, 'Payroll', TRUE)
        RETURNING waterexpensecategoryid INTO v_id;
    END IF;
    RETURN v_id;
END;
$function$;

-- ------------------------------------- 4. add by hand: Opening/Deposit/WagesOwed --
CREATE OR REPLACE FUNCTION public.spwateremployeecredit_add(
    p_farmid text, p_waterstaffid integer, p_entrytype text, p_amount numeric,
    p_entrydate date DEFAULT NULL, p_watercashaccountid integer DEFAULT NULL,
    p_paymentmethod text DEFAULT NULL, p_reference text DEFAULT NULL,
    p_description text DEFAULT NULL, p_createdby text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $function$
DECLARE
    v_type  text := NULLIF(btrim(p_entrytype), '');
    v_date  date := COALESCE(p_entrydate, fncompany_businessdate(p_farmid));
    v_staff text;
    v_id    integer;
    v_txid  integer;
    v_expid integer;
    v_desc  text;
BEGIN
    IF v_type IS NULL OR v_type NOT IN ('OpeningBalance', 'Deposit', 'WagesOwed') THEN
        RAISE EXCEPTION 'Credit can be added as an opening balance, money handed in, or wages owed. Payroll savings are added by approving payroll.';
    END IF;
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'The amount must be more than zero.';
    END IF;
    IF v_date > fncompany_businessdate(p_farmid) THEN
        RAISE EXCEPTION 'The date cannot be in the future.';
    END IF;

    SELECT btrim(s.firstname || ' ' || s.lastname) INTO v_staff
    FROM   waterstaff s
    WHERE  s.waterstaffid = p_waterstaffid AND s.farmid = p_farmid AND NOT COALESCE(s.isdeleted, FALSE);
    IF v_staff IS NULL THEN
        RAISE EXCEPTION 'Staff member not found on this company.';
    END IF;
    IF v_type = 'Deposit' AND p_watercashaccountid IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account the money went into.';
    END IF;

    v_desc := COALESCE(NULLIF(btrim(p_description), ''),
                       CASE v_type WHEN 'OpeningBalance' THEN 'Opening employee credit'
                                   WHEN 'Deposit'        THEN 'Money handed in to keep'
                                   ELSE 'Wages kept as employee credit' END);

    INSERT INTO wateremployeecredits
        (farmid, waterstaffid, entrytype, amount, entrydate,
         watercashaccountid, paymentmethod, reference, description, createdby)
    VALUES
        (p_farmid, p_waterstaffid, v_type, round(p_amount, 2), v_date,
         CASE WHEN v_type = 'Deposit' THEN p_watercashaccountid END,
         CASE WHEN v_type = 'Deposit' THEN NULLIF(btrim(p_paymentmethod), '') END,
         NULLIF(btrim(p_reference), ''), v_desc, p_createdby)
    RETURNING wateremployeecreditid INTO v_id;

    IF v_type = 'Deposit' THEN
        v_txid := public.fnwateremployeecredit_cash(
            p_farmid, p_watercashaccountid, v_date, round(p_amount, 2),
            'EmployeeCreditDeposit', v_id, 'Employee credit: money from ' || v_staff, p_createdby);
        UPDATE wateremployeecredits SET watercashtransactionid = v_txid WHERE wateremployeecreditid = v_id;
    ELSIF v_type = 'WagesOwed' THEN
        -- Earned today, not paid: a payroll cost with no cash (NonCash -- Cash
        -- Flow and payables skip it, the P&L counts it).
        INSERT INTO waterexpenses
            (farmid, expensedate, waterexpensecategoryid, description, amount,
             paymentmethod, watercashaccountid, status, sourcetype, sourceid,
             createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_date::timestamp, public.fnwaterexpensecategory_payroll(p_farmid),
             left(v_staff || ' - ' || v_desc, 500), round(p_amount, 2),
             'NonCash', NULL, 'Approved', 'EmployeeCreditWages', v_id,
             p_createdby, p_createdby, (now() at time zone 'utc'))
        RETURNING waterexpenseid INTO v_expid;
        UPDATE wateremployeecredits SET waterexpenseid = v_expid WHERE wateremployeecreditid = v_id;
    END IF;
    RETURN v_id;
END;
$function$;

-- -------------------------------------------------------------- 5. pay out --
CREATE OR REPLACE FUNCTION public.spwateremployeecredit_payout(
    p_farmid text, p_waterstaffid integer, p_amount numeric, p_watercashaccountid integer,
    p_entrydate date DEFAULT NULL, p_paymentmethod text DEFAULT NULL,
    p_reference text DEFAULT NULL, p_description text DEFAULT NULL, p_createdby text DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $function$
DECLARE
    v_date  date := COALESCE(p_entrydate, fncompany_businessdate(p_farmid));
    v_staff text;
    v_bal   numeric;
    v_id    integer;
    v_txid  integer;
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'The amount must be more than zero.';
    END IF;
    IF p_watercashaccountid IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account the money is paid from.';
    END IF;
    IF v_date > fncompany_businessdate(p_farmid) THEN
        RAISE EXCEPTION 'The date cannot be in the future.';
    END IF;

    -- Locked, so two payouts for one worker serialise.
    SELECT btrim(s.firstname || ' ' || s.lastname) INTO v_staff
    FROM   waterstaff s
    WHERE  s.waterstaffid = p_waterstaffid AND s.farmid = p_farmid
    FOR UPDATE;
    IF v_staff IS NULL THEN
        RAISE EXCEPTION 'Staff member not found on this company.';
    END IF;

    v_bal := public.fnwateremployeecredit_balance(p_farmid, p_waterstaffid);
    IF round(p_amount, 2) > v_bal THEN
        RAISE EXCEPTION 'The business is only holding % for %.', v_bal, v_staff;
    END IF;

    INSERT INTO wateremployeecredits
        (farmid, waterstaffid, entrytype, amount, entrydate,
         watercashaccountid, paymentmethod, reference, description, createdby)
    VALUES
        (p_farmid, p_waterstaffid, 'Payout', round(p_amount, 2), v_date,
         p_watercashaccountid, NULLIF(btrim(p_paymentmethod), ''), NULLIF(btrim(p_reference), ''),
         COALESCE(NULLIF(btrim(p_description), ''), 'Employee credit paid out'), p_createdby)
    RETURNING wateremployeecreditid INTO v_id;

    v_txid := public.fnwateremployeecredit_cash(
        p_farmid, p_watercashaccountid, v_date, -round(p_amount, 2),
        'EmployeeCreditPayout', v_id, 'Employee credit paid to ' || v_staff, p_createdby);
    UPDATE wateremployeecredits SET watercashtransactionid = v_txid WHERE wateremployeecreditid = v_id;
    RETURN v_id;
END;
$function$;

-- ------------------------------------------------------------ 6. reverse --
-- The shared core: the reverse SP and payroll reopen both use it.
CREATE OR REPLACE FUNCTION public.fnwateremployeecredit_reverserow(p_farmid text, p_id integer, p_reason text, p_by text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
    v_c     wateremployeecredits%ROWTYPE;
    v_staff text;
    v_bal   numeric;
    v_txid  integer;
BEGIN
    SELECT * INTO v_c FROM wateremployeecredits
    WHERE  wateremployeecreditid = p_id AND farmid = p_farmid
    FOR UPDATE;
    IF v_c.wateremployeecreditid IS NULL THEN
        RAISE EXCEPTION 'Employee credit entry not found on this company.';
    END IF;
    IF v_c.status <> 'Posted' THEN
        RAISE EXCEPTION 'This entry has already been reversed.';
    END IF;

    SELECT btrim(s.firstname || ' ' || s.lastname) INTO v_staff
    FROM   waterstaff s WHERE s.waterstaffid = v_c.waterstaffid
    FOR UPDATE;

    -- Taking back money that was ADDED must not leave the business owing less
    -- than nothing -- that would mean it has already been paid out.
    IF v_c.entrytype <> 'Payout' THEN
        v_bal := public.fnwateremployeecredit_balance(p_farmid, v_c.waterstaffid);
        IF v_bal - v_c.amount < 0 THEN
            RAISE EXCEPTION 'Only % of %''s credit is left -- the rest has been paid out. Reverse the payout first.',
                v_bal, v_staff;
        END IF;
    END IF;

    IF v_c.entrytype IN ('Deposit', 'Payout') THEN
        v_txid := public.fnwateremployeecredit_cash(
            p_farmid, v_c.watercashaccountid, fncompany_businessdate(p_farmid),
            CASE WHEN v_c.entrytype = 'Deposit' THEN -v_c.amount ELSE v_c.amount END,
            'EmployeeCreditReversal', v_c.wateremployeecreditid,
            'Reversal: employee credit ' || lower(v_c.entrytype) || ' for ' || v_staff, p_by);
    END IF;

    -- Water cancels its expenses rather than deleting them.
    IF v_c.entrytype = 'WagesOwed' AND v_c.waterexpenseid IS NOT NULL THEN
        PERFORM set_config('water.employeecredit_reverse', 'on', true);
        UPDATE waterexpenses e
        SET    status = 'Cancelled', isdeleted = TRUE, updatedat = (now() at time zone 'utc'),
               notes = left(COALESCE(e.notes, '') || chr(10) || 'Employee credit reversed'
                            || COALESCE(': ' || NULLIF(btrim(p_reason), ''), ''), 1000)
        WHERE  e.waterexpenseid = v_c.waterexpenseid;
        PERFORM set_config('water.employeecredit_reverse', 'off', true);
    END IF;

    UPDATE wateremployeecredits
    SET    status = 'Reversed', reversalcashtransactionid = v_txid,
           reversedby = p_by, reversedat = (now() at time zone 'utc'),
           reversalreason = NULLIF(btrim(p_reason), '')
    WHERE  wateremployeecreditid = p_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.spwateremployeecredit_reverse(
    p_farmid text, p_wateremployeecreditid integer, p_reason text, p_reversedby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE v_type text;
BEGIN
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for the reversal.';
    END IF;
    SELECT entrytype INTO v_type FROM wateremployeecredits
    WHERE  wateremployeecreditid = p_wateremployeecreditid AND farmid = p_farmid;
    IF v_type = 'PayrollSaving' THEN
        RAISE EXCEPTION 'This credit came from payroll. Reopen that payroll to take it back.';
    END IF;
    PERFORM public.fnwateremployeecredit_reverserow(p_farmid, p_wateremployeecreditid, p_reason, p_reversedby);
END;
$function$;

-- The kept-wages expenses belong to their credit / payroll: changed there,
-- never from the Expenses page.
CREATE OR REPLACE FUNCTION public.fnwateremployeecredit_expenseguard()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    IF COALESCE(current_setting('water.employeecredit_reverse', true), 'off') = 'on' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'These wages are held as employee credit. Reverse the entry on Employee Credit instead.';
    END IF;
    IF NEW.amount IS DISTINCT FROM OLD.amount
       OR NEW.paymentmethod IS DISTINCT FROM OLD.paymentmethod
       OR NEW.expensedate IS DISTINCT FROM OLD.expensedate
       OR NEW.status IS DISTINCT FROM OLD.status
       OR NEW.isdeleted IS DISTINCT FROM OLD.isdeleted THEN
        RAISE EXCEPTION 'These wages are held as employee credit. Reverse the entry on Employee Credit and add it again.';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trgwateremployeecredit_expenseguard ON waterexpenses;
CREATE TRIGGER trgwateremployeecredit_expenseguard
    BEFORE UPDATE OR DELETE ON waterexpenses
    FOR EACH ROW
    WHEN (OLD.sourcetype = 'EmployeeCreditWages')
    EXECUTE FUNCTION public.fnwateremployeecredit_expenseguard();

-- -------------------------------------------------------------- 7. readers --
CREATE OR REPLACE FUNCTION public.spwateremployeecredit_balances(p_farmid text)
RETURNS TABLE(waterstaffid integer, staffname text, staffrole text, isactive boolean,
              balance numeric, totalin numeric, totalpaidout numeric,
              lastentrydate date, entrycount integer)
LANGUAGE sql STABLE AS $function$
    SELECT s.waterstaffid,
           btrim(s.firstname || ' ' || s.lastname)::text,
           s.role::text,
           COALESCE(s.isactive, TRUE) AND NOT COALESCE(s.isdeleted, FALSE),
           COALESCE(SUM(CASE WHEN c.entrytype = 'Payout' THEN -c.amount ELSE c.amount END)
                    FILTER (WHERE c.status = 'Posted'), 0)::numeric(14,2),
           COALESCE(SUM(c.amount) FILTER (WHERE c.status = 'Posted' AND c.entrytype <> 'Payout'), 0)::numeric(14,2),
           COALESCE(SUM(c.amount) FILTER (WHERE c.status = 'Posted' AND c.entrytype = 'Payout'), 0)::numeric(14,2),
           MAX(c.entrydate),
           COUNT(c.wateremployeecreditid)::int
    FROM   waterstaff s
    JOIN   wateremployeecredits c ON c.waterstaffid = s.waterstaffid AND c.farmid = p_farmid
    WHERE  s.farmid = p_farmid
    GROUP  BY s.waterstaffid, s.firstname, s.lastname, s.role, s.isactive, s.isdeleted
    ORDER  BY 5 DESC, 2;
$function$;

CREATE OR REPLACE FUNCTION public.spwateremployeecredit_getall(p_farmid text, p_waterstaffid integer DEFAULT NULL)
RETURNS TABLE(wateremployeecreditid integer, waterstaffid integer, staffname text,
              entrytype text, amount numeric, signedamount numeric, runningbalance numeric,
              entrydate date, watercashaccountid integer, accountname text,
              paymentmethod text, reference text, description text,
              waterpayrollrunid integer, payrollperiod text, waterexpenseid integer,
              status text, createdby text, createdat timestamp,
              reversedby text, reversedat timestamp, reversalreason text)
LANGUAGE sql STABLE AS $function$
    SELECT c.wateremployeecreditid, c.waterstaffid,
           btrim(s.firstname || ' ' || s.lastname)::text,
           c.entrytype, c.amount,
           (CASE WHEN c.entrytype = 'Payout' THEN -c.amount ELSE c.amount END)::numeric(14,2),
           SUM(CASE WHEN c.status <> 'Posted' THEN 0
                    WHEN c.entrytype = 'Payout' THEN -c.amount ELSE c.amount END)
               OVER (PARTITION BY c.waterstaffid ORDER BY c.entrydate, c.createdat, c.wateremployeecreditid)::numeric(14,2),
           c.entrydate, c.watercashaccountid, a.accountname::text,
           c.paymentmethod, c.reference, c.description,
           c.waterpayrollrunid,
           CASE WHEN r.waterpayrollrunid IS NOT NULL
                THEN to_char(r.periodstart, 'YYYY-MM-DD') || ' to ' || to_char(r.periodend, 'YYYY-MM-DD') END,
           c.waterexpenseid,
           c.status, c.createdby, c.createdat, c.reversedby, c.reversedat, c.reversalreason
    FROM   wateremployeecredits c
    JOIN   waterstaff s ON s.waterstaffid = c.waterstaffid
    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = c.watercashaccountid
    LEFT   JOIN waterpayrollruns r ON r.waterpayrollrunid = c.waterpayrollrunid
    WHERE  c.farmid = p_farmid
      AND  (p_waterstaffid IS NULL OR c.waterstaffid = p_waterstaffid)
    ORDER  BY c.entrydate DESC, c.createdat DESC, c.wateremployeecreditid DESC;
$function$;

CREATE OR REPLACE FUNCTION public.spwateremployeecredit_total(p_farmid text)
RETURNS TABLE(totalheld numeric, staffcount integer)
LANGUAGE sql STABLE AS $function$
    SELECT COALESCE(SUM(b.balance), 0)::numeric(14,2),
           COUNT(*) FILTER (WHERE b.balance > 0)::int
    FROM   public.spwateremployeecredit_balances(p_farmid) b;
$function$;

-- ------------------------------------------------------- 8. Cash Flow rows --
-- Deposits in, payouts out; a reversed one keeps its row and gets its
-- reversal on the day it was reversed. Spliced into spwatercashflow_rows.
CREATE OR REPLACE FUNCTION public.spwateremployeecredit_cashflowrows(
    p_farmid text, p_fromdate timestamp DEFAULT NULL, p_todate timestamp DEFAULT NULL)
RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer,
              accountname text, transactiondate timestamp, transactiontype text,
              sourcetype text, sourceid integer, istransfer boolean, amount numeric,
              description text, flowgroup text, createdat timestamp)
LANGUAGE sql STABLE AS $function$
    SELECT 'EmployeeCredit'::text, FALSE, c.wateremployeecreditid, c.watercashaccountid, a.accountname::text,
           CASE WHEN c.entrydate = c.createdat::date THEN c.createdat ELSE c.entrydate::timestamp END,
           CASE WHEN c.entrytype = 'Deposit' THEN 'CashIn' ELSE 'CashOut' END::text,
           CASE WHEN c.entrytype = 'Deposit' THEN 'EmployeeCreditDeposit' ELSE 'EmployeeCreditPayout' END::text,
           c.wateremployeecreditid, FALSE,
           (CASE WHEN c.entrytype = 'Deposit' THEN c.amount ELSE -c.amount END)::numeric,
           (CASE WHEN c.entrytype = 'Deposit' THEN 'Employee credit: money from '
                 ELSE 'Employee credit paid to ' END || btrim(s.firstname || ' ' || s.lastname))::text,
           CASE WHEN c.entrytype = 'Deposit' THEN 'EmployeeCreditIn' ELSE 'EmployeeCreditOut' END::text,
           c.createdat
    FROM   wateremployeecredits c
    JOIN   waterstaff s ON s.waterstaffid = c.waterstaffid
    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = c.watercashaccountid
    WHERE  c.farmid = p_farmid
      AND  c.entrytype IN ('Deposit', 'Payout')
      AND  CASE WHEN c.entrydate = c.createdat::date THEN c.createdat ELSE c.entrydate::timestamp END
           BETWEEN COALESCE(p_fromdate, '-infinity'::timestamp) AND COALESCE(p_todate, 'infinity'::timestamp)
    UNION ALL
    SELECT 'EmployeeCreditReversal'::text, FALSE, c.wateremployeecreditid, c.watercashaccountid, a.accountname::text,
           c.reversedat,
           CASE WHEN c.entrytype = 'Deposit' THEN 'CashOut' ELSE 'CashIn' END::text,
           'EmployeeCreditReversal'::text, c.wateremployeecreditid, FALSE,
           (CASE WHEN c.entrytype = 'Deposit' THEN -c.amount ELSE c.amount END)::numeric,
           ('Reversal: employee credit ' || lower(c.entrytype) || ' for ' || btrim(s.firstname || ' ' || s.lastname))::text,
           CASE WHEN c.entrytype = 'Deposit' THEN 'EmployeeCreditOut' ELSE 'EmployeeCreditIn' END::text,
           c.reversedat
    FROM   wateremployeecredits c
    JOIN   waterstaff s ON s.waterstaffid = c.waterstaffid
    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = c.watercashaccountid
    WHERE  c.farmid = p_farmid
      AND  c.entrytype IN ('Deposit', 'Payout')
      AND  c.status = 'Reversed' AND c.reversedat IS NOT NULL
      AND  c.reversedat BETWEEN COALESCE(p_fromdate, '-infinity'::timestamp) AND COALESCE(p_todate, 'infinity'::timestamp);
$function$;

-- ----------------------------------------------- 9. payroll lines (442) --
-- An OLD client (before this web release) types the line's TOTAL, advance
-- repayment included, and then adds the advance as its own row; the old recalc
-- "reconciled" that by shrinking the typed part. The plain sum below would
-- count the advance twice, so a line saved the old way remembers it
-- (legacyfromtotal) and spwaterpayrollitemdeduction_save absorbs an advance
-- row added to it. New clients send p_otherdeductions and never set the flag.
ALTER TABLE waterpayrollitems ADD COLUMN IF NOT EXISTS legacyfromtotal boolean NOT NULL DEFAULT FALSE;

-- Backfill BEFORE the recalc stops reconciling: legacy = total - structured
-- where they disagree. No line's total or net pay changes.
UPDATE waterpayrollitems i
SET    legacydeductions = i.deductions - COALESCE(s.amt, 0)
FROM  (SELECT it.waterpayrollitemid,
              (SELECT COALESCE(SUM(d.amount), 0) FROM waterpayrollitemdeductions d
               WHERE  d.waterpayrollitemid = it.waterpayrollitemid AND d.status <> 'Reversed') AS amt
       FROM   waterpayrollitems it) s
WHERE  s.waterpayrollitemid = i.waterpayrollitemid
  AND  i.deductions <> COALESCE(i.legacydeductions, 0) + COALESCE(s.amt, 0)
  AND  i.deductions >= COALESCE(s.amt, 0);

CREATE OR REPLACE FUNCTION public.fnwaterpayrollitem_recalcdeductions(p_waterpayrollitemid integer)
RETURNS numeric LANGUAGE plpgsql AS $function$
DECLARE
    v_runid      integer;
    v_legacy     numeric;
    v_structured numeric;
    v_total      numeric;
BEGIN
    SELECT i.waterpayrollrunid, COALESCE(i.legacydeductions, 0)
    INTO   v_runid, v_legacy
    FROM   waterpayrollitems i
    WHERE  i.waterpayrollitemid = p_waterpayrollitemid
    FOR UPDATE;
    IF v_runid IS NULL THEN
        RAISE EXCEPTION 'Payroll item % not found.', p_waterpayrollitemid;
    END IF;

    SELECT COALESCE(SUM(d.amount), 0) INTO v_structured
    FROM   waterpayrollitemdeductions d
    WHERE  d.waterpayrollitemid = p_waterpayrollitemid AND d.status <> 'Reversed';

    -- 460 (poultry 442): no reconcile. A removed or lowered deduction lowers the total.
    v_total := v_legacy + v_structured;

    UPDATE waterpayrollitems SET deductions = v_total WHERE waterpayrollitemid = p_waterpayrollitemid;

    BEGIN
        UPDATE waterpayrollitems i
        SET    netpay = i.basicpay + i.dailywage + i.commission + i.bonus - i.deductions
        WHERE  i.waterpayrollitemid = p_waterpayrollitemid;
    EXCEPTION WHEN generated_always THEN NULL;
    END;

    UPDATE waterpayrollruns r
    SET    totalgrosspay = agg.gross, totaldeductions = agg.ded, totalnetpay = agg.net,
           updatedat = (now() at time zone 'utc')
    FROM (SELECT COALESCE(SUM(i.basicpay + i.dailywage + i.commission + i.bonus), 0) AS gross,
                 COALESCE(SUM(i.deductions), 0) AS ded,
                 COALESCE(SUM(i.netpay), 0)     AS net
          FROM   waterpayrollitems i WHERE i.waterpayrollrunid = v_runid) agg
    WHERE  r.waterpayrollrunid = v_runid;

    RETURN v_total;
END;
$function$;

-- Line upsert: other deductions + keep-as-credit in one call. Dropped BY NAME
-- (new parameters change the signature).
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT p.oid::regprocedure AS sig FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'spwaterpayrollitem_upsert'
    LOOP EXECUTE 'DROP FUNCTION ' || r.sig; END LOOP;
END $$;

CREATE FUNCTION public.spwaterpayrollitem_upsert(
    p_waterpayrollrunid integer, p_farmid text, p_waterstaffid integer DEFAULT NULL::integer,
    p_basicpay numeric DEFAULT 0, p_dailywage numeric DEFAULT 0, p_commission numeric DEFAULT 0,
    p_bonus numeric DEFAULT 0, p_deductions numeric DEFAULT 0,
    p_paymentmethod text DEFAULT NULL::text, p_notes text DEFAULT NULL::text,
    p_otherdeductions numeric DEFAULT NULL::numeric, p_employeecredit numeric DEFAULT NULL::numeric,
    p_savedby text DEFAULT NULL::text)
RETURNS TABLE(waterpayrollitemid integer, waterpayrollrunid integer, waterstaffid integer, basicpay numeric,
              dailywage numeric, commission numeric, bonus numeric, deductions numeric, netpay numeric,
              paymentmethod text, notes text, createdat timestamp without time zone)
LANGUAGE plpgsql AS $function$
DECLARE
    v_runstatus  text;
    v_itemid     integer;
    v_structured numeric;
    v_legacy     numeric;
    v_net        numeric;
BEGIN
    SELECT r.status INTO v_runstatus
    FROM   waterpayrollruns r
    WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE;
    IF v_runstatus IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found for this farm.';
    END IF;
    IF v_runstatus NOT IN ('Draft', 'Reopened') THEN
        RAISE EXCEPTION 'This payroll is %. Reopen it before changing its lines.', v_runstatus;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM waterstaff st WHERE st.waterstaffid = p_waterstaffid AND st.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Staff % not found on this farm.', p_waterstaffid;
    END IF;
    IF (COALESCE(p_basicpay, 0) < 0 OR COALESCE(p_dailywage, 0) < 0 OR COALESCE(p_commission, 0) < 0
        OR COALESCE(p_bonus, 0) < 0 OR COALESCE(p_deductions, 0) < 0
        OR COALESCE(p_otherdeductions, 0) < 0 OR COALESCE(p_employeecredit, 0) < 0) THEN
        RAISE EXCEPTION 'Pay and deductions cannot be negative.';
    END IF;

    SELECT i.waterpayrollitemid INTO v_itemid
    FROM   waterpayrollitems i
    WHERE  i.waterpayrollrunid = p_waterpayrollrunid AND i.waterstaffid = p_waterstaffid;

    IF v_itemid IS NULL THEN
        INSERT INTO waterpayrollitems (waterpayrollrunid, waterstaffid, basicpay, dailywage, commission, bonus,
                                       deductions, legacydeductions, paymentmethod, notes)
        VALUES (p_waterpayrollrunid, p_waterstaffid, COALESCE(p_basicpay, 0), COALESCE(p_dailywage, 0),
                COALESCE(p_commission, 0), COALESCE(p_bonus, 0), 0, 0, p_paymentmethod, p_notes)
        RETURNING waterpayrollitems.waterpayrollitemid INTO v_itemid;
    ELSE
        UPDATE waterpayrollitems i
        SET    basicpay = COALESCE(p_basicpay, 0), dailywage = COALESCE(p_dailywage, 0),
               commission = COALESCE(p_commission, 0), bonus = COALESCE(p_bonus, 0),
               paymentmethod = p_paymentmethod, notes = p_notes
        WHERE  i.waterpayrollitemid = v_itemid;
    END IF;

    -- Keep as employee credit: replace the line's DRAFT credit rows (a reopened
    -- run's rows went back to Draft when it was reopened).
    IF p_employeecredit IS NOT NULL THEN
        DELETE FROM waterpayrollitemdeductions d
        WHERE  d.waterpayrollitemid = v_itemid AND d.deductiontype = 'EmployeeCredit' AND d.status = 'Draft';
        IF p_employeecredit > 0 THEN
            INSERT INTO waterpayrollitemdeductions (farmid, waterpayrollrunid, waterpayrollitemid, waterstaffid,
                                                    deductiontype, amount, wateremployeeloanid, description, status, createdby)
            VALUES (p_farmid, p_waterpayrollrunid, v_itemid, p_waterstaffid,
                    'EmployeeCredit', p_employeecredit, NULL, 'Kept from wages', 'Draft', p_savedby);
        END IF;
    END IF;

    -- Other deductions: given exactly, or derived from an old-style total.
    IF p_otherdeductions IS NOT NULL THEN
        v_legacy := p_otherdeductions;
    ELSE
        SELECT COALESCE(SUM(d.amount), 0) INTO v_structured
        FROM   waterpayrollitemdeductions d
        WHERE  d.waterpayrollitemid = v_itemid AND d.status <> 'Reversed';
        v_legacy := GREATEST(COALESCE(p_deductions, 0) - v_structured, 0);
    END IF;

    UPDATE waterpayrollitems i
    SET    legacydeductions = v_legacy,
           legacyfromtotal  = (p_otherdeductions IS NULL)
    WHERE  i.waterpayrollitemid = v_itemid;
    PERFORM public.fnwaterpayrollitem_recalcdeductions(v_itemid);

    SELECT i.netpay INTO v_net FROM waterpayrollitems i WHERE i.waterpayrollitemid = v_itemid;
    IF v_net < 0 THEN
        RAISE EXCEPTION 'Deductions (%) are more than this line''s pay. Net pay cannot be negative.',
            (SELECT i.deductions FROM waterpayrollitems i WHERE i.waterpayrollitemid = v_itemid);
    END IF;

    RETURN QUERY
    SELECT i.waterpayrollitemid, i.waterpayrollrunid, i.waterstaffid,
           i.basicpay, i.dailywage, i.commission, i.bonus, i.deductions, i.netpay,
           i.paymentmethod::text, i.notes::text, i.createdat
    FROM   waterpayrollitems i
    WHERE  i.waterpayrollitemid = v_itemid;
END;
$function$;

-- -------------------------------------------- 10. payroll writers (live) --
-- Each is the live body (pg_get_functiondef, 2026-11-20) with only the marked
-- 460 change.

-- 460: an EmployeeCredit deduction carries no advance; an old client's advance is absorbed.
CREATE OR REPLACE FUNCTION public.spwaterpayrollitemdeduction_save(p_farmid text, p_waterpayrollitemid integer, p_deductiontype text, p_amount numeric, p_wateremployeeloanid integer DEFAULT NULL::integer, p_description text DEFAULT NULL::text, p_reference text DEFAULT NULL::text, p_waterpayrollitemdeductionid integer DEFAULT NULL::integer, p_savedby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id          integer := p_waterpayrollitemdeductionid;
    v_runid       integer;
    v_staffid     integer;
    v_runstatus   text;
    v_type        text := NULLIF(btrim(p_deductiontype), '');
    v_amount      numeric := COALESCE(p_amount, 0);
    v_loanstaff   integer;
    v_loanstatus  text;
    v_outstanding numeric;
    v_number      text;
    v_claimed     numeric;
BEGIN
    IF v_amount <= 0 THEN
        RAISE EXCEPTION 'A deduction must be more than zero.';
    END IF;
    IF v_type IS NULL THEN
        RAISE EXCEPTION 'Say what kind of deduction this is.';
    END IF;

    SELECT i.waterpayrollrunid, i.waterstaffid, r.status
    INTO   v_runid, v_staffid, v_runstatus
    FROM   waterpayrollitems i
    JOIN   waterpayrollruns r ON r.waterpayrollrunid = i.waterpayrollrunid
    WHERE  i.waterpayrollitemid = p_waterpayrollitemid
      AND  r.farmid = p_farmid;

    IF v_runid IS NULL THEN
        RAISE EXCEPTION 'Payroll line not found on this farm.';
    END IF;
    -- 'Reopened', not just 'Draft'. spwaterpayrollrun_unapprove sets a
    -- reopened run to 'Reopened' and _approve accepts both, so a deduction has
    -- to be editable in both states -- otherwise the reverse, change the
    -- deduction, re-approve cycle that spec section 44 requires is impossible:
    -- you could unapprove the payroll and then not be allowed to touch it.
    IF v_runstatus NOT IN ('Draft', 'Reopened') THEN
        RAISE EXCEPTION
            'This payroll is %. Reopen it before changing deductions.', v_runstatus;
    END IF;

    IF v_type IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment') THEN
        IF p_wateremployeeloanid IS NULL THEN
            RAISE EXCEPTION 'Choose which advance this repayment is against.';
        END IF;

        SELECT l.waterstaffid, l.status, l.outstandingbalance, l.loannumber
        INTO   v_loanstaff, v_loanstatus, v_outstanding, v_number
        FROM   wateremployeeloans l
        WHERE  l.wateremployeeloanid = p_wateremployeeloanid
          AND  l.farmid = p_farmid;

        IF v_loanstaff IS NULL THEN
            RAISE EXCEPTION 'Advance not found on this farm.';
        END IF;
        -- Section 33, enforced on the server. The dropdown is a convenience;
        -- this is the rule.
        IF v_loanstaff <> v_staffid THEN
            RAISE EXCEPTION 'That advance belongs to a different member of staff.';
        END IF;
        IF v_loanstatus <> 'Active' THEN
            RAISE EXCEPTION 'Advance % is %, so nothing can be deducted against it.',
                COALESCE(v_number, p_wateremployeeloanid::text), v_loanstatus;
        END IF;

        -- Section 34. What this run ALREADY plans to take off the same advance
        -- counts against the balance, or two 300 deductions could both pass
        -- against a 500 balance and only fail at approval -- which is the worst
        -- possible moment to find out.
        SELECT COALESCE(SUM(d.amount), 0)
        INTO   v_claimed
        FROM   waterpayrollitemdeductions d
        WHERE  d.wateremployeeloanid = p_wateremployeeloanid
          AND  d.status = 'Draft'
          AND  (v_id IS NULL OR d.waterpayrollitemdeductionid <> v_id);

        IF v_amount + v_claimed > v_outstanding THEN
            IF v_claimed > 0 THEN
                RAISE EXCEPTION
                    'Only % is left on advance %, and % of it is already planned in a draft payroll.',
                    v_outstanding, COALESCE(v_number, p_wateremployeeloanid::text), v_claimed;
            ELSE
                RAISE EXCEPTION 'Only % is left on advance %.',
                    v_outstanding, COALESCE(v_number, p_wateremployeeloanid::text);
            END IF;
        END IF;
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO waterpayrollitemdeductions (
            farmid, waterpayrollrunid, waterpayrollitemid, waterstaffid,
            deductiontype, amount, wateremployeeloanid,
            description, reference, status, createdby)
        VALUES (
            p_farmid, v_runid, p_waterpayrollitemid, v_staffid,
            v_type, v_amount,
            CASE WHEN v_type IN ('OtherDeduction', 'EmployeeCredit') THEN NULL /* 460 */ ELSE p_wateremployeeloanid END,
            NULLIF(btrim(p_description), ''), NULLIF(btrim(p_reference), ''),
            'Draft', p_savedby)
        RETURNING waterpayrollitemdeductionid INTO v_id;
    ELSE
        UPDATE waterpayrollitemdeductions d
        SET    deductiontype = v_type,
               amount = v_amount,
               wateremployeeloanid =
                   CASE WHEN v_type IN ('OtherDeduction', 'EmployeeCredit') THEN NULL /* 460 */
                        ELSE p_wateremployeeloanid END,
               description = NULLIF(btrim(p_description), ''),
               reference   = NULLIF(btrim(p_reference), ''),
               updatedby   = p_savedby,
               updatedat   = (now() at time zone 'utc')
        WHERE  d.waterpayrollitemdeductionid = v_id
          AND  d.farmid = p_farmid
          AND  d.status = 'Draft';

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'Deduction % cannot be edited -- it is not a draft on this farm.', v_id;
        END IF;
    END IF;

    -- 460: an old client typed this advance into the line's total already
    -- (legacyfromtotal); take it out of the typed part instead of counting it twice.
    IF p_waterpayrollitemdeductionid IS NULL
       AND v_type IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment') THEN
        UPDATE waterpayrollitems i
        SET    legacydeductions = i.legacydeductions - v_amount
        WHERE  i.waterpayrollitemid = p_waterpayrollitemid
          AND  i.legacyfromtotal AND i.legacydeductions >= v_amount;
    END IF;
    PERFORM public.fnwaterpayrollitem_recalcdeductions(p_waterpayrollitemid);
    RETURN v_id;
END;
$function$;

-- 460: approve posts kept wages as employee credit + their NonCash cost.
CREATE OR REPLACE FUNCTION public.spwaterpayrollrun_approve(p_waterpayrollrunid integer, p_farmid text, p_approvedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_priorstatus   text;
    -- 316.
    v_d          record;
    v_repayid    integer;
    v_loantotal  numeric := 0;
    v_ctxloan    text := NULL;
    v_ctxstaff   text := NULL;
    v_netpay        numeric(14,2);
    v_periodstart   date;
    v_periodend     date;
    v_paydate       date;
    v_cashaccountid integer;
    v_notes         text;
    v_catid         integer;
    v_expensedate   timestamp;
    v_description   text;
    -- 460.
    v_c           record;
    v_creditid    integer;
    v_credittotal numeric := 0;
    v_creditdate  date;
BEGIN
    SELECT r.status INTO v_priorstatus
    FROM   waterpayrollruns r
    WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE
    LIMIT  1;

    IF v_priorstatus IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found.';
    END IF;
    IF v_priorstatus NOT IN ('Draft', 'Reopened') THEN
        RAISE EXCEPTION 'Payroll cannot be approved (current=%).', v_priorstatus;
    END IF;

    -- ---- 316: turn planned loan deductions into real repayments -------------
    -- Before anything else is written, so a rejected repayment leaves a run
    -- that still looks exactly as it did. (Belt and braces -- the whole
    -- function is one transaction either way.)
    --
    -- Validation is NOT repeated here. spwateremployeeloanrepayment_record
    -- re-checks the farm, the worker, the advance's status and its outstanding
    -- balance at posting time, which is the only moment those answers are
    -- authoritative.
    BEGIN
        FOR v_d IN
            SELECT d.waterpayrollitemdeductionid AS dedid,
                   d.waterpayrollitemid          AS itemid,
                   d.wateremployeeloanid         AS loanid,
                   d.waterstaffid                AS staffid,
                   d.amount                      AS amount,
                   l.loannumber                  AS loannumber,
                   btrim(s.firstname || ' ' || s.lastname) AS staffname
            FROM   waterpayrollitemdeductions d
            JOIN   wateremployeeloans l ON l.wateremployeeloanid = d.wateremployeeloanid
            JOIN   waterstaff s ON s.waterstaffid = d.waterstaffid
            WHERE  d.waterpayrollrunid = p_waterpayrollrunid
              AND  d.farmid = p_farmid
              AND  d.status = 'Draft'
              AND  d.deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment')
            ORDER  BY d.waterpayrollitemdeductionid
        LOOP
            v_ctxloan  := COALESCE(v_d.loannumber, v_d.loanid::text);
            v_ctxstaff := v_d.staffname;

            v_repayid := public.spwateremployeeloanrepayment_record(
                p_farmid                    => p_farmid,
                p_wateremployeeloanid       => v_d.loanid,
                p_amount                    => v_d.amount,
                p_sourcetype                => 'Payroll',
                p_principalamount           => v_d.amount,
                p_interestamount            => 0,
                p_repaymentdate             => COALESCE(
                    (SELECT r.paydate::timestamp FROM waterpayrollruns r
                      WHERE r.waterpayrollrunid = p_waterpayrollrunid),
                    (now() at time zone 'utc')),
                -- No cash account, and 313's constraint would refuse one: the
                -- wage paid out is already net, so no money moved for this.
                p_watercashaccountid        => NULL,
                p_waterpayrollrunid         => p_waterpayrollrunid,
                p_waterpayrollitemid        => v_d.itemid,
                p_waterpayrolldeductionid   => v_d.dedid,
                p_waterstaffid              => v_d.staffid,
                p_createdby                 => p_approvedby);

            UPDATE waterpayrollitemdeductions
            SET    status = 'Posted',
                   wateremployeeloanrepaymentid = v_repayid,
                   updatedby = p_approvedby,
                   updatedat = (now() at time zone 'utc')
            WHERE  waterpayrollitemdeductionid = v_d.dedid;

            v_loantotal := v_loantotal + v_d.amount;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        IF v_ctxloan IS NULL THEN
            RAISE;
        END IF;
        RAISE EXCEPTION
            'Payroll was not approved. The deduction against advance % for % could not be posted: %',
            v_ctxloan, COALESCE(v_ctxstaff, 'this member of staff'), SQLERRM;
    END;

    -- ---- 460: wages kept as employee credit --------------------------------
    -- Still the worker's wage: it becomes money the business OWES her (a credit
    -- row) and, at the end, a NonCash payroll cost -- so the P&L shows gross.
    SELECT COALESCE(r.paydate, fncompany_businessdate(p_farmid)) INTO v_creditdate
    FROM   waterpayrollruns r WHERE r.waterpayrollrunid = p_waterpayrollrunid;
    FOR v_c IN
        SELECT d.waterpayrollitemdeductionid AS dedid, d.waterpayrollitemid AS itemid,
               d.waterstaffid AS staffid, d.amount AS amount
        FROM   waterpayrollitemdeductions d
        WHERE  d.waterpayrollrunid = p_waterpayrollrunid AND d.farmid = p_farmid
          AND  d.status = 'Draft' AND d.deductiontype = 'EmployeeCredit'
        ORDER  BY d.waterpayrollitemdeductionid
    LOOP
        INSERT INTO wateremployeecredits
            (farmid, waterstaffid, entrytype, amount, entrydate,
             waterpayrollrunid, waterpayrollitemid, waterpayrolldeductionid, description, createdby)
        VALUES
            (p_farmid, v_c.staffid, 'PayrollSaving', v_c.amount, v_creditdate,
             p_waterpayrollrunid, v_c.itemid, v_c.dedid,
             'Payroll run #' || p_waterpayrollrunid || ' - kept as employee credit', p_approvedby)
        RETURNING wateremployeecreditid INTO v_creditid;

        UPDATE waterpayrollitemdeductions
        SET    status = 'Posted', wateremployeecreditid = v_creditid,
               updatedby = p_approvedby, updatedat = (now() at time zone 'utc')
        WHERE  waterpayrollitemdeductionid = v_c.dedid;
        v_credittotal := v_credittotal + v_c.amount;
    END LOOP;

    -- Every remaining planned deduction is now in force. The loan ones flipped
    -- above; this catches Other deductions, which post nothing but should not
    -- stay 'Draft' on an approved run.
    UPDATE waterpayrollitemdeductions
    SET    status = 'Posted',
           updatedby = p_approvedby,
           updatedat = (now() at time zone 'utc')
    WHERE  waterpayrollrunid = p_waterpayrollrunid
      AND  farmid = p_farmid
      AND  status = 'Draft';

    IF v_priorstatus = 'Reopened' THEN
        -- Reapproval: preserve the original ApprovedBy/At; record Reapproved*.
        UPDATE waterpayrollruns r
        SET    status       = 'Approved',
               reapprovedby = p_approvedby,
               reapprovedat = (now() at time zone 'utc'),
               updatedat    = (now() at time zone 'utc')
        WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid;
    ELSE  -- Draft
        UPDATE waterpayrollruns r
        SET    status     = 'Approved',
               approvedby = p_approvedby,
               approvedat = (now() at time zone 'utc'),
               updatedat  = (now() at time zone 'utc')
        WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid;
    END IF;

    -- Linked-expense upsert.
    SELECT r.totalnetpay, r.periodstart, r.periodend, r.paydate, r.watercashaccountid, r.notes
    INTO   v_netpay, v_periodstart, v_periodend, v_paydate, v_cashaccountid, v_notes
    FROM   waterpayrollruns r
    WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid
    LIMIT  1;

    SELECT c.waterexpensecategoryid INTO v_catid
    FROM   waterexpensecategories c
    WHERE  c.farmid = p_farmid
      AND  c.name IN ('Payroll', 'Salaries', 'Wages')
      AND  c.isactive = TRUE
    ORDER  BY CASE c.name WHEN 'Payroll' THEN 1 WHEN 'Salaries' THEN 2 ELSE 3 END
    LIMIT  1;

    IF v_catid IS NULL THEN
        INSERT INTO waterexpensecategories (farmid, name, isactive)
        VALUES (p_farmid, 'Payroll', TRUE)
        RETURNING waterexpensecategoryid INTO v_catid;
    END IF;

    v_expensedate := COALESCE(v_paydate::timestamp, (now() at time zone 'utc'));
    v_description := left(concat(
        'Payroll for ',
        to_char(v_periodstart, 'YYYY-MM-DD'),
        ' to ',
        to_char(v_periodend, 'YYYY-MM-DD'),
        ' (run #', p_waterpayrollrunid, ')'
    ), 500);

    IF EXISTS (
        SELECT 1 FROM waterexpenses e
        WHERE e.farmid = p_farmid AND e.sourcetype = 'Payroll'
          AND e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE
    ) THEN
        UPDATE waterexpenses e
        SET    amount        = v_netpay,
               expensedate   = v_expensedate,
               description   = v_description,
               waterexpensecategoryid = v_catid,
               watercashaccountid = v_cashaccountid,
               status        = 'Approved',
               approvedby    = p_approvedby,
               approvedat    = (now() at time zone 'utc'),
               updatedat     = (now() at time zone 'utc')
        WHERE  e.farmid = p_farmid AND e.sourcetype = 'Payroll'
          AND  e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE;
    ELSE
        INSERT INTO waterexpenses (
            farmid, expensedate, waterexpensecategoryid, description, amount,
            paymentmethod, watercashaccountid, status,
            sourcetype, sourceid,
            createdby, approvedby, approvedat
        )
        VALUES (
            p_farmid, v_expensedate, v_catid, v_description, v_netpay,
            CASE WHEN v_cashaccountid IS NULL THEN 'Credit' ELSE 'Cash' END,
            v_cashaccountid, 'Approved',
            'Payroll', p_waterpayrollrunid,
            p_approvedby, p_approvedby, (now() at time zone 'utc')
        );
    END IF;

    -- ---- 316: put back the wage cost the deductions took out ----------------
    -- The linked expense above is totalNETpay, so every deduction reduces
    -- recorded payroll cost. Over the life of a 2,000 advance repaid through
    -- wages, 2,000 of labour cost would quietly leave the reports while the
    -- receivable also went to zero.
    --
    -- 'NonCash' is the existing marker for "a cost recorded without money
    -- moving for THIS row". spwatercashflow_rows arm 3 excludes it, so the
    -- top-up never becomes a second outflow; the expense reports do not filter
    -- it, so the cost still counts. Same trick water already uses for loan
    -- interest (259).
    --
    -- Its own sourcetype, so 317 can find and cancel it the way the run's own
    -- expense is cancelled. A run with no loan deductions writes nothing here.
    IF v_loantotal > 0 THEN
        IF EXISTS (
            SELECT 1 FROM waterexpenses e
            WHERE e.farmid = p_farmid AND e.sourcetype = 'PayrollEmployeeLoan'
              AND e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE
        ) THEN
            UPDATE waterexpenses e
            SET    amount      = v_loantotal,
                   expensedate = v_expensedate,
                   description = left(v_description || ' - advances repaid from wages', 500),
                   waterexpensecategoryid = v_catid,
                   status      = 'Approved',
                   approvedby  = p_approvedby,
                   approvedat  = (now() at time zone 'utc'),
                   updatedat   = (now() at time zone 'utc')
            WHERE  e.farmid = p_farmid AND e.sourcetype = 'PayrollEmployeeLoan'
              AND  e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE;
        ELSE
            INSERT INTO waterexpenses (
                farmid, expensedate, waterexpensecategoryid, description, amount,
                paymentmethod, watercashaccountid, status,
                sourcetype, sourceid,
                createdby, approvedby, approvedat
            )
            VALUES (
                p_farmid, v_expensedate, v_catid,
                left(v_description || ' - advances repaid from wages', 500), v_loantotal,
                'NonCash', NULL, 'Approved',
                'PayrollEmployeeLoan', p_waterpayrollrunid,
                p_approvedby, p_approvedby, (now() at time zone 'utc')
            );
        END IF;
    END IF;

    -- ---- 460: put the kept wages back into payroll cost ---------------------
    -- Same shape as the advance top-up above.
    IF v_credittotal > 0 THEN
        IF EXISTS (SELECT 1 FROM waterexpenses e
                   WHERE e.farmid = p_farmid AND e.sourcetype = 'PayrollEmployeeCredit'
                     AND e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE) THEN
            UPDATE waterexpenses e
            SET    amount = v_credittotal, expensedate = v_expensedate,
                   description = left(v_description || ' - wages kept as employee credit', 500),
                   waterexpensecategoryid = v_catid, status = 'Approved',
                   approvedby = p_approvedby, approvedat = (now() at time zone 'utc'),
                   updatedat = (now() at time zone 'utc')
            WHERE  e.farmid = p_farmid AND e.sourcetype = 'PayrollEmployeeCredit'
              AND  e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE;
        ELSE
            INSERT INTO waterexpenses (
                farmid, expensedate, waterexpensecategoryid, description, amount,
                paymentmethod, watercashaccountid, status, sourcetype, sourceid,
                createdby, approvedby, approvedat)
            VALUES (
                p_farmid, v_expensedate, v_catid,
                left(v_description || ' - wages kept as employee credit', 500), v_credittotal,
                'NonCash', NULL, 'Approved', 'PayrollEmployeeCredit', p_waterpayrollrunid,
                p_approvedby, p_approvedby, (now() at time zone 'utc'));
        END IF;
    END IF;
END;
$function$;

-- 460: reopen takes back kept wages (refused once paid out) and cancels their cost.
CREATE OR REPLACE FUNCTION public.spwaterpayrollrun_unapprove(p_waterpayrollrunid integer, p_farmid text, p_reopenedby text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status        text;
    -- 317.
    v_r        record;
    v_reason   text;
    v_ctxloan  text := NULL;
    v_ctxstaff text := NULL;
    v_cashaccountid integer;
    v_netpay        numeric(14,2);
    -- 460.
    v_c        record;
BEGIN
    SELECT r.status, r.watercashaccountid, r.totalnetpay
    INTO   v_status, v_cashaccountid, v_netpay
    FROM   waterpayrollruns r
    WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found.';
    END IF;
    IF v_status NOT IN ('Approved', 'Paid') THEN
        RAISE EXCEPTION 'Payroll can only be reopened from Approved or Paid (current=%).', v_status;
    END IF;

    -- ---- 317: give back every advance repayment this run took ---------------
    -- First, so that if an advance refuses the reversal nothing else has run.
    --
    -- Appends a reversal rather than deleting: the repayment stays, marked
    -- Reversed, and because 313 computes the balance from POSTED repayments
    -- only, the advance goes back up by exactly what this run had taken off.
    -- p_allowpayroll => TRUE is the one place in the water module that passes
    -- it, which is what makes a payroll-created repayment undoable only by the
    -- payroll that created it.
    v_reason := 'Payroll reopened' || COALESCE(': ' || NULLIF(btrim(p_reason), ''), '');

    -- ---- 460: take back the wages this run kept as employee credit ---------
    -- Refused (by the reverse core) if the money has already been paid out:
    -- the business cannot un-owe what it has already handed over.
    FOR v_c IN
        SELECT c.wateremployeecreditid AS creditid, c.waterpayrolldeductionid AS dedid,
               btrim(s.firstname || ' ' || s.lastname) AS staffname
        FROM   wateremployeecredits c
        JOIN   waterstaff s ON s.waterstaffid = c.waterstaffid
        WHERE  c.farmid = p_farmid AND c.waterpayrollrunid = p_waterpayrollrunid
          AND  c.entrytype = 'PayrollSaving' AND c.status = 'Posted'
        ORDER  BY c.wateremployeecreditid
    LOOP
        BEGIN
            PERFORM public.fnwateremployeecredit_reverserow(p_farmid, v_c.creditid, v_reason, p_reopenedby);
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Payroll was not reopened. The wages kept for % could not be taken back: %',
                v_c.staffname, SQLERRM;
        END;
        IF v_c.dedid IS NOT NULL THEN
            UPDATE waterpayrollitemdeductions
            SET    status = 'Draft', wateremployeecreditid = NULL,
                   updatedby = p_reopenedby, updatedat = (now() at time zone 'utc')
            WHERE  waterpayrollitemdeductionid = v_c.dedid AND farmid = p_farmid;
        END IF;
    END LOOP;

    BEGIN
        FOR v_r IN
            SELECT r.wateremployeeloanrepaymentid AS repayid,
                   r.waterpayrolldeductionid      AS dedid,
                   COALESCE(l.loannumber, l.wateremployeeloanid::text) AS loannumber,
                   btrim(s.firstname || ' ' || s.lastname) AS staffname
            FROM   wateremployeeloanrepayments r
            JOIN   wateremployeeloans l ON l.wateremployeeloanid = r.wateremployeeloanid
            JOIN   waterstaff s ON s.waterstaffid = r.waterstaffid
            WHERE  r.farmid = p_farmid
              AND  r.waterpayrollrunid = p_waterpayrollrunid
              AND  r.sourcetype = 'Payroll'
              AND  r.status = 'Posted'
            ORDER  BY r.wateremployeeloanrepaymentid
        LOOP
            v_ctxloan  := v_r.loannumber;
            v_ctxstaff := v_r.staffname;

            PERFORM public.spwateremployeeloanrepayment_reverse(
                p_farmid       => p_farmid,
                p_wateremployeeloanrepaymentid => v_r.repayid,
                p_reversedby   => p_reopenedby,
                p_reason       => v_reason,
                p_allowpayroll => TRUE);

            IF v_r.dedid IS NOT NULL THEN
                UPDATE waterpayrollitemdeductions
                SET    status = 'Draft',
                       wateremployeeloanrepaymentid = NULL,
                       updatedby = p_reopenedby,
                       updatedat = (now() at time zone 'utc')
                WHERE  waterpayrollitemdeductionid = v_r.dedid
                  AND  farmid = p_farmid;
            END IF;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        IF v_ctxloan IS NULL THEN
            RAISE;
        END IF;
        RAISE EXCEPTION
            'Payroll was not reopened. The repayment against advance % for % could not be reversed: %',
            v_ctxloan, COALESCE(v_ctxstaff, 'this member of staff'), SQLERRM;
    END;

    -- Other deductions posted nothing, but must become editable again with the
    -- rest of the run.
    UPDATE waterpayrollitemdeductions
    SET    status = 'Draft',
           updatedby = p_reopenedby,
           updatedat = (now() at time zone 'utc')
    WHERE  waterpayrollrunid = p_waterpayrollrunid
      AND  farmid = p_farmid
      AND  status = 'Posted'
      AND  wateremployeeloanrepaymentid IS NULL;

    -- If currently Paid, reverse the cash transaction + refund the cash account.
    IF v_status = 'Paid' AND v_cashaccountid IS NOT NULL AND v_netpay > 0 THEN
        INSERT INTO watercashtransactions (
            farmid, watercashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, description, createdby, approvedby, approvedat
        )
        VALUES (
            p_farmid, v_cashaccountid, (now() AT TIME ZONE 'utc'), 'Adjustment',
            'Payroll', p_waterpayrollrunid, v_netpay,
            concat('Payroll reopened � reversal',
                   CASE WHEN p_reason IS NULL THEN '' ELSE ': ' || p_reason END),
            p_reopenedby, p_reopenedby, (now() AT TIME ZONE 'utc')
        );

        UPDATE watercashaccounts a
        SET    currentbalance = a.currentbalance + v_netpay,
               updatedat      = (now() AT TIME ZONE 'utc')
        WHERE  a.watercashaccountid = v_cashaccountid;
    END IF;

    -- Flip the run to Reopened. Audit cols set; Paid* stays as historical
    -- record of the prior approval/payment cycle.
    UPDATE waterpayrollruns r
    SET    status       = 'Reopened',
           reopenedby   = p_reopenedby,
           reopenedat   = (now() AT TIME ZONE 'utc'),
           reopenreason = p_reason,
           updatedat    = (now() AT TIME ZONE 'utc')
    WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid;

    -- Reverse the linked expense - IsDeleted=TRUE so the filtered unique index
    -- frees up for a fresh active row when the run is reapproved later.
    UPDATE waterexpenses e
    SET    status    = 'Cancelled',
           isdeleted = TRUE,
           notes     = left(COALESCE(e.notes, '') || chr(10) || 'Payroll reopened'
                            || CASE WHEN p_reason IS NULL THEN '' ELSE ': ' || p_reason END, 1000),
           updatedat = (now() AT TIME ZONE 'utc')
    WHERE  e.farmid = p_farmid AND e.sourcetype = 'Payroll'
      AND  e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE;

    -- ---- 317: and the advance top-up 316 added ------------------------------
    -- Cancelled the same way and at the same moment as the payroll expense it
    -- belongs to, so the two cannot disagree about whether this run's cost
    -- exists. Soft-deleted, not removed: water cancels its expenses rather than
    -- deleting them, and this follows that rather than inventing a second rule.
    UPDATE waterexpenses e
    SET    status    = 'Cancelled',
           isdeleted = TRUE,
           updatedat = (now() at time zone 'utc')
    WHERE  e.farmid = p_farmid
      AND  e.sourcetype = 'PayrollEmployeeLoan'
      AND  e.sourceid = p_waterpayrollrunid
      AND  e.isdeleted = FALSE;

    -- 460: and the kept-wages top-up, the same way.
    UPDATE waterexpenses e
    SET    status = 'Cancelled', isdeleted = TRUE, updatedat = (now() at time zone 'utc')
    WHERE  e.farmid = p_farmid AND e.sourcetype = 'PayrollEmployeeCredit'
      AND  e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE;
END;
$function$;

-- 460: mark paid -- pay-date CashOut, locked account check, nothing-to-pay runs.
CREATE OR REPLACE FUNCTION public.spwaterpayrollrun_markpaid(p_waterpayrollrunid integer, p_farmid text, p_paidby text DEFAULT NULL::text, p_paydate date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status        text;
    v_cashaccountid integer;
    v_netpay        numeric(14,2);
    v_notes         text;
    v_periodstart   date;
    v_periodend     date;
    v_allowneg      boolean;
    v_bal           numeric(14,2);
    v_expensedate   timestamp;
    v_catid         integer;
BEGIN
    SELECT r.status, r.watercashaccountid, r.totalnetpay, r.notes, r.periodstart, r.periodend
    INTO   v_status, v_cashaccountid, v_netpay, v_notes, v_periodstart, v_periodend
    FROM   waterpayrollruns r
    WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE
    LIMIT  1;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found.';
    END IF;
    IF v_status <> 'Approved' THEN
        RAISE EXCEPTION 'Payroll must be Approved before it can be marked Paid (current=%).', v_status;
    END IF;
    -- 460 (poultry 441): nothing left to hand over -- all of it kept as
    -- employee credit -- marks the run Paid with no cash movement.
    IF COALESCE(v_netpay, 0) <= 0 THEN
        UPDATE waterpayrollruns r
        SET    status = 'Paid', paidby = p_paidby, paidat = (now() at time zone 'utc'),
               paydate = COALESCE(p_paydate, r.paydate), updatedat = (now() at time zone 'utc')
        WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid;
        UPDATE waterexpenses e
        SET    expensedate = COALESCE(p_paydate, e.expensedate::date)::timestamp,
               updatedat = (now() at time zone 'utc')
        WHERE  e.farmid = p_farmid AND e.sourcetype = 'Payroll'
          AND  e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE;
        RETURN;
    END IF;
    IF v_cashaccountid IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account this payroll is paid from before marking it paid.';
    END IF;

    -- 460 (poultry 392): locked, so two payouts cannot both pass the check,
    -- and the account must belong to this company.
    SELECT a.allownegativebalance, a.currentbalance
    INTO   v_allowneg, v_bal
    FROM   watercashaccounts a
    WHERE  a.watercashaccountid = v_cashaccountid AND a.farmid = p_farmid
    FOR UPDATE;
    IF v_allowneg IS NULL THEN
        RAISE EXCEPTION 'Cash account does not belong to this company.';
    END IF;

    IF (v_allowneg = FALSE AND (v_bal - v_netpay) < 0) THEN
        RAISE EXCEPTION 'This payment would overdraw the cash account (balance %, payment %).',
              v_bal, v_netpay;
    END IF;

    UPDATE waterpayrollruns r
    SET    status    = 'Paid',
           paidby    = p_paidby,
           paidat    = (now() at time zone 'utc'),
           paydate   = COALESCE(p_paydate, r.paydate),
           updatedat = (now() at time zone 'utc')
    WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid;

    -- Cash transaction.
    INSERT INTO watercashtransactions (
        farmid, watercashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, description, createdby, approvedby, approvedat
    )
    VALUES (
        -- 460 (poultry 392): dated to the pay date (midnight), not the click.
        p_farmid, v_cashaccountid,
        COALESCE(p_paydate, (SELECT r.paydate FROM waterpayrollruns r WHERE r.waterpayrollrunid = p_waterpayrollrunid),
                 fncompany_businessdate(p_farmid))::timestamp,
        'CashOut',
        'Payroll', p_waterpayrollrunid, -v_netpay,
        COALESCE('Payroll: ' || left(COALESCE(v_notes, ''), 200), 'Payroll'),
        p_paidby, p_paidby, (now() at time zone 'utc')
    );

    UPDATE watercashaccounts a
    SET    currentbalance = a.currentbalance - v_netpay,
           updatedat = (now() at time zone 'utc')
    WHERE  a.watercashaccountid = v_cashaccountid;

    -- Refine the linked expense — the Approve SP already inserted it; here we
    -- update PaymentMethod (now we know it's real cash out of the cash account)
    -- and ExpenseDate (now we have a real PayDate).
    v_expensedate := COALESCE(p_paydate, (now() at time zone 'utc')::date)::timestamp;

    IF EXISTS (
        SELECT 1 FROM waterexpenses e
        WHERE e.farmid = p_farmid AND e.sourcetype = 'Payroll'
          AND e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE
    ) THEN
        UPDATE waterexpenses e
        SET    paymentmethod      = 'Cash',
               watercashaccountid = v_cashaccountid,
               expensedate        = v_expensedate,
               status             = 'Approved',
               updatedat          = (now() at time zone 'utc')
        WHERE  e.farmid = p_farmid AND e.sourcetype = 'Payroll'
          AND  e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE;
    ELSE
        -- Defensive fallback: if for some reason there's no linked expense yet
        -- (e.g. legacy Approved run from before this migration), create one.
        SELECT c.waterexpensecategoryid INTO v_catid
        FROM   waterexpensecategories c
        WHERE  c.farmid = p_farmid AND c.isactive = TRUE
          AND  c.name IN ('Payroll', 'Salaries', 'Wages')
        ORDER  BY CASE c.name WHEN 'Payroll' THEN 1 WHEN 'Salaries' THEN 2 ELSE 3 END
        LIMIT  1;

        IF v_catid IS NULL THEN
            INSERT INTO waterexpensecategories (farmid, name, isactive)
            VALUES (p_farmid, 'Payroll', TRUE)
            RETURNING waterexpensecategoryid INTO v_catid;
        END IF;

        INSERT INTO waterexpenses (
            farmid, expensedate, waterexpensecategoryid, description, amount,
            paymentmethod, watercashaccountid, status,
            sourcetype, sourceid,
            createdby, approvedby, approvedat
        )
        VALUES (
            p_farmid, v_expensedate, v_catid,
            concat('Payroll for ', to_char(v_periodstart, 'YYYY-MM-DD'),
                   ' to ',         to_char(v_periodend, 'YYYY-MM-DD'),
                   ' (run #', p_waterpayrollrunid, ')'),
            v_netpay, 'Cash', v_cashaccountid, 'Approved',
            'Payroll', p_waterpayrollrunid,
            p_paidby, p_paidby, (now() at time zone 'utc')
        );
    END IF;
END;
$function$;

-- 460: Cash Flow gets the employee credit arm; both staff arms move above arm 7.
CREATE OR REPLACE FUNCTION public.spwatercashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text, createdat timestamp without time zone)
 LANGUAGE plpgsql
 STABLE
AS $function$

DECLARE

    v_tbl  text;
    v_createdcol text;               -- 302: 'ca.createddate' or NULL

    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);

    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);

BEGIN

    -- ---- 1. customer receipts, dated when the money arrived -----------------

    RETURN QUERY

    SELECT 'Receipt'::text,

           FALSE,

           p.waterpaymentid,

           NULL::integer,

           NULL::text,

           p.paymentdate,

           'CashIn'::text,

           'CustomerPayment'::text,

           p.watersaleid,

           FALSE,

           COALESCE(p.amount, 0)::numeric,

           COALESCE(NULLIF(btrim(p.note), ''),

                    NULLIF(btrim(p.reference), ''),

                    'Payment for sale #' || p.watersaleid::text)::text,

           'OperatingIn'::text

           , p.createddate   -- 302: the entry time
    FROM   waterpayments p

    WHERE  lower(p.farmid::text) = lower(p_farmid)

      AND  COALESCE(p.amount, 0) <> 0

      -- 458: a REVERSED payment keeps its receipt on the day the money came in;
      -- arm 1a below takes it back out on the day it was reversed. Before 458
      -- the receipt vanished, rewriting the period it was received in.
      AND  COALESCE(p.status, 'Posted') IN ('Posted', 'Reversed')

      -- 422: opening credit and credit notes are credit, not money received.
      AND  NOT public.fnwater_isnocashcredit(p.sourcetype)

      AND  p.paymentdate >= v_from

      AND  p.paymentdate <= v_to;



    -- ---- 1a. 458: a reversed customer payment, out on the reversal day ------
    RETURN QUERY
    SELECT 'ReceiptReversal'::text, FALSE, p.waterpaymentid, NULL::integer, NULL::text,
           p.reversedat, 'CashOut'::text, 'CustomerPaymentReversal'::text, p.watersaleid, FALSE,
           -COALESCE(p.amount, 0)::numeric,
           ('Reversal of payment ' || COALESCE(p.paymentnumber, '#' || p.waterpaymentid::text)
            || COALESCE(' - ' || NULLIF(btrim(p.reversalreason), ''), ''))::text,
           'OperatingOut'::text, p.reversedat
    FROM   waterpayments p
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) <> 0
      AND  p.status = 'Reversed' AND p.reversedat IS NOT NULL
      AND  NOT public.fnwater_isnocashcredit(p.sourcetype)
      AND  p.reversedat >= v_from
      AND  p.reversedat <= v_to;

    -- ---- 1b. 422: customer refunds -----------------------------------------
    -- Money out on the refund date, and it stays there when the refund is
    -- reversed (the money did leave); the reversal is money back in on its date.
    RETURN QUERY
    SELECT 'CustomerRefund'::text, FALSE, r.refundid, r.watercashaccountid, NULL::text,
           r.refunddate::timestamp, 'CashOut'::text, 'WaterCustomerRefund'::text, r.refundid, FALSE,
           -r.amount, ('Customer refund ' || r.refundnumber ||
                       COALESCE(' - ' || NULLIF(btrim(c.name), ''), ''))::text,
           'OperatingOut'::text, r.createdat
    FROM   watercustomerrefunds r
    LEFT   JOIN watercustomers c ON c.watercustomerid = r.watercustomerid AND c.farmid = r.farmid
    WHERE  r.farmid = p_farmid AND r.status IN ('Posted', 'Reversed')
      AND  r.refunddate::timestamp >= v_from AND r.refunddate::timestamp <= v_to;

    RETURN QUERY
    SELECT 'CustomerRefundReversal'::text, FALSE, r.refundid, r.watercashaccountid, NULL::text,
           r.reversedat, 'CashIn'::text, 'WaterCustomerRefund'::text, r.refundid, FALSE,
           r.amount, ('Reversal of customer refund ' || r.refundnumber)::text,
           'OperatingIn'::text, r.reversedat
    FROM   watercustomerrefunds r
    WHERE  r.farmid = p_farmid AND r.status = 'Reversed' AND r.reversedat IS NOT NULL
      AND  r.reversedat >= v_from AND r.reversedat <= v_to;

    -- ---- 2. the part paid at the point of sale -----------------------------

    -- Same reasoning as 235: a sale settled on the spot may never create a

    -- payment row, and the difference is what picks those up.

    RETURN QUERY

    SELECT 'SaleResidual'::text,

           FALSE,

           s.watersaleid,

           NULL::integer,

           NULL::text,

           s.saledate,

           'CashIn'::text,

           'Sale'::text,

           s.watersaleid,

           FALSE,

           v.residual,

           ('Sale #' || s.watersaleid::text)::text,

           'OperatingIn'::text

           , s.createddate   -- 302: the entry time
    FROM   watersales s

    CROSS  JOIN LATERAL (

        SELECT ROUND(

                   CASE WHEN COALESCE(s.status, '') = 'Paid'

                        THEN COALESCE(s.totalamount, 0)

                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),

                                   COALESCE(s.totalamount, 0))

                   END

                 - COALESCE((SELECT SUM(wp.amount)

                             FROM   waterpayments wp

                             WHERE  wp.watersaleid = s.watersaleid

                               AND  lower(wp.farmid::text) = lower(p_farmid)

                               -- Same reason: a reversed payment never covered

                               -- anything, so it must not reduce the residual.

                               AND  COALESCE(wp.status, 'Posted') = 'Posted'), 0)
                 -- 422: credit applied to the sale is not money taken at the till
                 - public.fnwatersale_creditapplied(p_farmid, s.watersaleid)

               , 2) AS residual

    ) v

    WHERE  lower(s.farmid::text) = lower(p_farmid)

      -- A cancelled sale is not income, whatever it once recorded as paid.

      AND  COALESCE(s.status, '') <> 'Cancelled'

      AND  v.residual > 0

      AND  s.saledate >= v_from

      AND  s.saledate <= v_to;



    -- ---- 3. money paid out when the bill was recorded -----------------------

    -- 236's gates are kept verbatim -- Approved, not deleted -- with two

    -- changes:

    --

    --   * the AMOUNT is what was actually paid at entry, not the whole bill:

    --     the resolved amountpaid, less anything a supplier payment has since

    --     covered (which the next arm reports on its own, later, date);

    --   * the `paymentmethod <> 'Credit'` filter is GONE, because the resolution

    --     subsumes it. A Credit bill resolves to 0 paid and drops out on

    --     `paidatentry > 0` instead -- same rows excluded, and a Credit bill

    --     that has since been part-paid is no longer wrongly invisible.

    RETURN QUERY

    SELECT 'Expense'::text,

           FALSE,

           e.waterexpenseid,

           e.watercashaccountid,

           NULL::text,

           e.expensedate,

           'CashOut'::text,

           'Expense'::text,

           e.waterexpenseid,

           FALSE,

           -v.paidatentry,

           COALESCE(NULLIF(btrim(e.description), ''),

                    NULLIF(btrim(e.paidto), ''),

                    'Expense #' || e.waterexpenseid::text)::text,

           'OperatingOut'::text

           , e.createdat   -- 302: the entry time
    FROM   waterexpenses e

    CROSS  JOIN LATERAL (

        SELECT GREATEST(

                   COALESCE(e.amountpaid,

                            CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'

                                 THEN 0 ELSE e.amount END)

                 - COALESCE((SELECT SUM(sa.amountapplied)

                             FROM   supplierpaymentallocation sa

                             WHERE  sa.farmid = p_farmid

                               AND  sa.module = 'water'

                               AND  sa.status = 'Posted'

                               AND  sa.documenttype = 'Expense'

                               AND  sa.documentid = e.waterexpenseid), 0)

               , 0)::numeric AS paidatentry

    ) v

    WHERE  lower(e.farmid::text) = lower(p_farmid)

      AND  COALESCE(e.isdeleted, false) = false

      AND  v.paidatentry > 0

      -- 047's rule: only an approved expense has been recognised at all.

      AND  COALESCE(e.status, '') = 'Approved'

      -- 259. 'NonCash' means "a cost recorded, but the money moved elsewhere".

      -- Loan interest and fees are written this way: the repayment's own arm

      -- below reports the FULL amount that left the account, so counting these

      -- rows here as well would take 12,500 out of the bank and 15,000 off the

      -- cash flow. Expense reports do not filter NonCash, so the cost still

      -- counts where it should.

      --

      -- No-op on today's data: there are zero water expenses with this marker.

      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'

      -- 421: a supplier payment's own aggregated expense row is not read here.
      -- It holds only the part expensed at purchase and is Cancelled on
      -- reversal; the payment's cash is reported from the payment below (3c).
      AND  COALESCE(e.sourcetype, '') <> 'WaterSupplierPayment'

      AND  e.expensedate >= v_from

      AND  e.expensedate <= v_to;



    -- ---- 3b. money paid out later, against a bill already recorded ----------

    -- A supplier payment settling a bill. It belongs to the day the money moved,

    -- not the day the bill was entered.

    --

    -- Only documenttype='Expense'. A payment against a raw-material purchase

    -- books its own aggregated expense row dated the payment date (240) and is

    -- already counted by arm 3; adding it here would double it.

    RETURN QUERY

    SELECT 'ExpensePayment'::text,

           FALSE,

           sa.allocationid,

           sp.watercashaccountid,

           NULL::text,

           sp.paymentdate,

           'CashOut'::text,

           'ExpensePayment'::text,

           sa.documentid,

           FALSE,

           -sa.amountapplied::numeric,

           ('Payment for expense #' || sa.documentid::text ||

            COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,

           'OperatingOut'::text

           , sa.createdat   -- 302: the entry time
    FROM   supplierpaymentallocation sa

    JOIN   watersupplierpayments sp

           ON  sp.watersupplierpaymentid = sa.paymentid

           AND sp.farmid = sa.farmid

    LEFT   JOIN watersuppliers s

           ON  s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid

    WHERE  sa.farmid = p_farmid

      AND  sa.module = 'water'

      -- 421: a reversed payment's money still LEFT on its date (376's rule);
      -- the reversal brings it back on its own date (3d). Allocations are only
      -- ever reversed together with their payment.
      AND  (sa.status = 'Posted' OR (sa.status = 'Reversed' AND sp.status = 'Reversed'))

      AND  NOT sa.fromcredit                                -- 424

      AND  sa.documenttype = 'Expense'

      AND  COALESCE(sp.status, 'Posted') IN ('Posted', 'Reversed')

      AND  sa.amountapplied <> 0

      AND  sp.paymentdate >= v_from

      AND  sp.paymentdate <= v_to;



    -- ---- 3c. 421: supplier payments for raw-material purchases ------------
    --
    -- The FULL purchase portion, on the payment date -- deferred lots included,
    -- because the supplier was paid for them whether or not their cost has
    -- reached the P&L (275). Reversed payments stay: the money did leave.
    RETURN QUERY
    SELECT 'SupplierPurchasePayment'::text,
           FALSE,
           sp.watersupplierpaymentid,
           sp.watercashaccountid,
           NULL::text,
           sp.paymentdate,
           'CashOut'::text,
           'WaterSupplierPayment'::text,
           sp.watersupplierpaymentid,
           FALSE,
           -x.amount,
           ('Supplier payment - raw material purchase' ||
            COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,
           'OperatingOut'::text,
           sp.createdat
    FROM   watersupplierpayments sp
    CROSS  JOIN LATERAL (
        SELECT COALESCE(SUM(sa.amountapplied), 0)::numeric AS amount
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = sp.farmid AND sa.module = 'water'
          AND  sa.paymentid = sp.watersupplierpaymentid
          AND  sa.documenttype NOT IN ('Expense', 'SupplierDebt')     -- 424
          AND  NOT sa.fromcredit                                     -- 424
          AND  (sa.status = 'Posted' OR (sa.status = 'Reversed' AND sp.status = 'Reversed'))
    ) x
    LEFT   JOIN watersuppliers s
           ON  s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  COALESCE(sp.status, 'Posted') IN ('Posted', 'Reversed')
      AND  x.amount <> 0
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;

    -- ---- 3d. 421: a reversed supplier payment's money coming back ---------
    --
    -- Everything the payment paid out (purchases and bills), back in on the
    -- day it was reversed.
    RETURN QUERY
    SELECT 'SupplierPaymentReversal'::text,
           FALSE,
           sp.watersupplierpaymentid,
           sp.watercashaccountid,
           NULL::text,
           sp.reversedat,
           'CashIn'::text,
           'WaterSupplierPayment'::text,
           sp.watersupplierpaymentid,
           FALSE,
           x.amount,
           ('Reversal of supplier payment #' || sp.watersupplierpaymentid::text ||
            COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,
           'OperatingIn'::text,
           sp.reversedat
    FROM   watersupplierpayments sp
    CROSS  JOIN LATERAL (
        -- 424: the whole payment (an advance has no allocations at all)
        SELECT sp.totalamount::numeric AS amount
    ) x
    LEFT   JOIN watersuppliers s
           ON  s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  sp.status = 'Reversed'
      AND  NOT public.fnwatersupplier_iscreditkind(sp.sourcetype)   -- 424
      AND  sp.reversedat IS NOT NULL
      AND  x.amount <> 0
      AND  sp.reversedat >= v_from
      AND  sp.reversedat <= v_to;

    -- ---- 3e. 424: supplier debts and advances --------------------------------
    -- The part of a payment no other row shows: what it paid on supplier debts
    -- and what it applied to nothing (an advance / overpayment), on the
    -- payment's own day. With 3b and 3c a payment always totals its amount.
    RETURN QUERY
    SELECT 'SupplierAdvanceOrDebt'::text, FALSE, sp.watersupplierpaymentid, sp.watercashaccountid, NULL::text,
           sp.paymentdate, 'CashOut'::text, 'WaterSupplierPayment'::text, sp.watersupplierpaymentid, FALSE,
           -x.amount,
           ('Supplier payment - debts / advance' || COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,
           'OperatingOut'::text, sp.createdat
    FROM   watersupplierpayments sp
    CROSS  JOIN LATERAL (
        SELECT sp.totalamount - COALESCE(SUM(sa.amountapplied), 0)::numeric AS amount
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = sp.farmid AND sa.module = 'water'
          AND  sa.paymentid = sp.watersupplierpaymentid
          AND  sa.documenttype IN ('RawMaterialPurchase', 'Expense')
          AND  NOT sa.fromcredit
          AND  (sa.status = 'Posted' OR (sa.status = 'Reversed' AND sp.status = 'Reversed'))
    ) x
    LEFT   JOIN watersuppliers s ON s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  COALESCE(sp.status, 'Posted') IN ('Posted', 'Reversed')
      AND  NOT public.fnwatersupplier_iscreditkind(sp.sourcetype)
      AND  x.amount > 0
      AND  sp.paymentdate >= v_from AND sp.paymentdate <= v_to;

    -- ---- 3g / 3h. 424: supplier refunds ---------------------------------------
    RETURN QUERY
    SELECT 'SupplierRefund'::text, FALSE, r.refundid, r.watercashaccountid, NULL::text,
           r.refunddate::timestamp, 'CashIn'::text, 'WaterSupplierRefund'::text, r.refundid, FALSE,
           r.amount, ('Supplier refund ' || r.refundnumber || COALESCE(' - ' || NULLIF(btrim(s.suppliername), ''), ''))::text,
           'OperatingIn'::text, r.createdat
    FROM   watersupplierrefunds r
    LEFT   JOIN watersuppliers s ON s.watersupplierid = r.supplierid AND s.farmid = r.farmid
    WHERE  r.farmid = p_farmid AND r.status IN ('Posted', 'Reversed')
      AND  r.refunddate::timestamp >= v_from AND r.refunddate::timestamp <= v_to;

    RETURN QUERY
    SELECT 'SupplierRefundReversal'::text, FALSE, r.refundid, r.watercashaccountid, NULL::text,
           r.reversedat, 'CashOut'::text, 'WaterSupplierRefund'::text, r.refundid, FALSE,
           -r.amount, ('Reversal of supplier refund ' || r.refundnumber)::text,
           'OperatingOut'::text, r.reversedat
    FROM   watersupplierrefunds r
    WHERE  r.farmid = p_farmid AND r.status = 'Reversed' AND r.reversedat IS NOT NULL
      AND  r.reversedat >= v_from AND r.reversedat <= v_to;

    -- ---- 4. owner money (258) ----------------------------------------------

    -- Contributions and draws recorded through the Owner Money module.

    -- FINANCING, not operating: the owner funded the business or took funding

    -- back. Never revenue, never expense.

    --

    -- Reversed records are dropped entirely rather than netted to zero with a

    -- second row -- a contribution that was put in and taken back out is not

    -- funding, and showing both legs would put money the business never kept

    -- into Money In and Money Out.

    --

    -- Placed ABOVE the legacy capital arm on purpose: that arm RETURNs early

    -- when cashadjustment is absent, so anything below it is skipped on a

    -- company with no capital records.

    RETURN QUERY

    SELECT 'OwnerMoney'::text,

           FALSE,

           o.waterownermoneyid,

           o.watercashaccountid,

           a.accountname::text,

           o.transactiondate,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'CashIn' ELSE 'CashOut' END::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END::text,

           o.waterownermoneyid,

           FALSE,

           -- Stored positive; the sign is applied here, once.

           (CASE WHEN o.transactiontype = 'Contribution' THEN o.amount ELSE -o.amount END)::numeric,

           COALESCE(NULLIF(btrim(o.notes), ''),

                    NULLIF(btrim(o.ownername), ''),

                    CASE WHEN o.transactiontype = 'Contribution'

                         THEN 'Owner contribution' ELSE 'Owner draw' END)::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'FinancingIn' ELSE 'FinancingOut' END::text

           , o.createdat   -- 302: the entry time
    FROM   waterownermoney o

    LEFT   JOIN watercashaccounts a

           ON a.watercashaccountid = o.watercashaccountid

    WHERE  o.farmid = p_farmid

      AND  o.status = 'Posted'
      -- 297. A record backfilled from a Cash Flow adjustment has NO cash
      -- row of its own: the ADJUSTMENT is still the cash event, and the
      -- legacy adjustment arm below already reports it. Without this the
      -- same money is counted twice -- the trap 292 hit for loans.
      AND  o.sourceadjustmentid IS NULL

      AND  o.transactiondate >= v_from

      AND  o.transactiondate <= v_to;



    -- ---- 5. loans received (259) -------------------------------------------

    -- Borrowed money arriving. FINANCING: the business received it, it did not

    -- earn it, so it is money in and never revenue.

    --

    -- The AMOUNT RECEIVED, not the principal. A lender that withholds a fee

    -- pays out less than it lends, and only what arrived is cash in.

    --

    -- The timestamp carries 256's rule, baked in from the start rather than

    -- patched afterwards as it had to be on poultry: loandate is a DATE, so a

    -- plain cast gives midnight and a loan recorded this afternoon sorts below

    -- everything else recorded today. A loan dated TODAY reports the moment it

    -- was recorded; a BACK-DATED one keeps midnight, because using createdat

    -- unconditionally would drag last Tuesday's loan into today, above rows

    -- that really did happen after it.

    RETURN QUERY

    SELECT 'Loan'::text,

           FALSE,

           l.waterloanid,

           l.watercashaccountid,

           a.accountname::text,

           CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                ELSE l.loandate::timestamp END,

           'CashIn'::text,

           'LoanReceived'::text,

           l.waterloanid,

           FALSE,

           l.amountreceived::numeric,

           ('Loan received from ' || l.lendername)::text,

           'FinancingIn'::text

           , l.createdat   -- 302: the entry time
    FROM   waterloans l

    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = l.watercashaccountid

    WHERE  l.farmid = p_farmid

      AND  l.amountreceived > 0

      -- 293. A loan converted from a Cash Flow adjustment has NO cash row of

      -- its own: the ADJUSTMENT is the cash event, and the legacy adjustment arm

      -- already reports it. Without this the same borrowing is money-in twice --

      -- which is precisely what 292's stage check caught on the poultry side.

      AND  l.sourceadjustmentid IS NULL

      AND  l.status NOT IN ('Cancelled', 'Reversed', 'Draft')

      AND  (CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                 ELSE l.loandate::timestamp END) >= v_from

      AND  (CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                 ELSE l.loandate::timestamp END) <= v_to;



    -- ---- 6. loan repayments (259) ------------------------------------------

    -- The FULL payment leaves the account, so the full payment is money out --

    -- principal, interest and fees together.

    --

    -- This does NOT double count the interest and fee expenses those payments

    -- create: they are written paymentmethod = 'NonCash', and arm 3 above now

    -- skips NonCash. Expense reports read the expense table directly and still

    -- count them, which is the whole point -- cash out is 12,500, cost is 2,500.

    RETURN QUERY

    SELECT 'LoanPayment'::text,

           FALSE,

           p.waterloanpaymentid,

           p.watercashaccountid,

           a.accountname::text,

           p.paymentdate,

           'CashOut'::text,

           'LoanRepayment'::text,

           p.waterloanid,

           FALSE,

           -p.totalamount::numeric,

           ('Loan repayment to ' || l.lendername)::text,

           'FinancingOut'::text

           , p.createdat   -- 302: the entry time
    FROM   waterloanpayments p

    JOIN   waterloans l ON l.waterloanid = p.waterloanid

    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = p.watercashaccountid

    WHERE  p.farmid = p_farmid

      AND  p.status = 'Posted'

      AND  p.paymentdate >= v_from

      AND  p.paymentdate <= v_to;



    -- ---- 8. employee advances (313/315) ------------------------------------
    -- 460: MOVED above arm 7, which RETURNs early on a database without a
    -- cashadjustment table -- this arm was silently skipped there.
    -- Disbursements out, manual repayments in, payroll deductions NOWHERE:
    -- a deduction moves no money, so it is not a cash event.
    RETURN QUERY
    SELECT * FROM public.spwateremployeeloan_cashflowrows(p_farmid, v_from, v_to);

    -- ---- 9. 460: employee credit -- money handed in to keep, payouts, reversals.
    RETURN QUERY
    SELECT * FROM public.spwateremployeecredit_cashflowrows(p_farmid, v_from, v_to);

    -- ---- 7. capital in and out (legacy cash adjustments) --------------------

    -- Expected to return nothing on Water today -- see 236's header note.

    --

    -- MUST STAY LAST: it RETURNs early when the table is absent, and anything

    -- below it would be silently skipped.

    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,

                      to_regclass('public.cashadjustments')::text);



    -- 302: only reference the creation column if the resolved table has one.
    SELECT CASE WHEN EXISTS (
               SELECT 1 FROM information_schema.columns c
               WHERE  c.table_schema = 'public'
                 AND  c.table_name = replace(v_tbl, 'public.', '')
                 AND  c.column_name = 'createddate')
           THEN 'ca.createddate' ELSE 'NULL::timestamp' END
      INTO v_createdcol;

    IF v_tbl IS NULL THEN

        RETURN;

    END IF;



    RETURN QUERY EXECUTE format($sql$

        SELECT 'Adjustment'::text,

               FALSE,

               ca.adjustmentid,

               NULL::integer,

               NULL::text,

               ca.adjustmentdate,

               CASE WHEN ca.amount >= 0 THEN 'CashIn' ELSE 'CashOut' END::text,

               COALESCE(NULLIF(btrim(ca.adjustmenttype), ''), 'Adjustment')::text,

               ca.adjustmentid,

               FALSE,

               ca.amount::numeric,

               COALESCE(NULLIF(btrim(ca.description), ''), ca.adjustmenttype)::text,

               CASE WHEN ca.amount >= 0 THEN 'FinancingIn' ELSE 'FinancingOut' END::text,
               %s                       -- 302: the entry time

        FROM   %s ca

        WHERE  lower(ca.farmid::text) = lower($1)

          AND  ca.amount <> 0

          AND  ca.adjustmentdate >= $2

          AND  ca.adjustmentdate <= $3

    $sql$, v_createdcol, v_tbl)

    USING p_farmid, v_from, v_to;


END;

$function$;

-- 460: the Expenses page explains the two new payroll-owned expense types.
CREATE OR REPLACE FUNCTION public.fnwaterexpense_sourceblock(p_waterexpenseid integer, p_farmid text, p_verb text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_type text; v_id integer; v_exists boolean := FALSE; v_what text; v_where text;
BEGIN
    SELECT e.sourcetype, e.sourceid INTO v_type, v_id
    FROM   waterexpenses e WHERE e.waterexpenseid = p_waterexpenseid AND e.farmid = p_farmid;
    IF v_type IS NULL OR v_id IS NULL THEN RETURN NULL; END IF;

    CASE v_type
    WHEN 'RawMaterialPurchase' THEN
        SELECT TRUE INTO v_exists FROM waterrawmaterialpurchases x
        WHERE x.waterrawmaterialpurchaseid = v_id AND x.farmid = p_farmid;
        v_what  := 'raw material purchase #' || v_id;
        v_where := 'Inventory & Supply Purchases (edit or delete the purchase there)';
    WHEN 'Payroll', 'PayrollEmployeeLoan', 'PayrollEmployeeCredit' THEN   -- 460
        SELECT TRUE INTO v_exists FROM waterpayrollruns x
        WHERE x.waterpayrollrunid = v_id AND x.farmid = p_farmid;
        v_what  := 'payroll run #' || v_id;
        v_where := 'Payroll (reverse the run there)';
    WHEN 'CapitalAsset' THEN
        SELECT TRUE INTO v_exists FROM watercapitalassets x
        WHERE x.watercapitalassetid = v_id AND x.farmid = p_farmid;
        v_what  := 'capital asset #' || v_id;
        v_where := 'Capital assets (correct or reverse the asset there)';
    WHEN 'WaterInternalUsage' THEN
        SELECT TRUE INTO v_exists FROM waterinternalusage x
        WHERE x.waterinternalusageid = v_id AND x.farmid = p_farmid;
        v_what  := 'internal use #' || v_id;
        v_where := 'Internal use (reverse it there)';
    WHEN 'EmployeeCreditWages' THEN   -- 460
        SELECT TRUE INTO v_exists FROM wateremployeecredits x
        WHERE x.wateremployeecreditid = v_id AND x.farmid = p_farmid;
        v_what  := 'employee credit entry #' || v_id;
        v_where := 'Employee Credit (reverse the entry there)';
    ELSE
        RETURN NULL;   -- unknown source: keep the old behaviour
    END CASE;

    IF NOT COALESCE(v_exists, FALSE) THEN RETURN NULL; END IF;   -- orphan: allow
    RETURN 'This expense was created automatically by ' || v_what || ' and cannot be '
           || p_verb || ' here. Undo it on ' || v_where || ', which updates this expense too.';
END
$function$
;

-- 460: a deduction that posted employee credit cannot be deleted.
CREATE OR REPLACE FUNCTION public.fnwaterpayrolldeduction_nodelete()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_loan  text;
    v_staff text;
    v_amount numeric;
BEGIN
    SELECT COALESCE(l.loannumber, l.wateremployeeloanid::text),
           btrim(s.firstname || ' ' || s.lastname),
           r.amount
    INTO   v_loan, v_staff, v_amount
    FROM   wateremployeeloanrepayments r
    JOIN   wateremployeeloans l ON l.wateremployeeloanid = r.wateremployeeloanid
    JOIN   waterstaff s ON s.waterstaffid = r.waterstaffid
    WHERE  r.waterpayrolldeductionid = OLD.waterpayrollitemdeductionid
      AND  r.status = 'Posted'
    LIMIT  1;

    IF v_loan IS NOT NULL THEN
        RAISE EXCEPTION
            'This payroll has already repaid % of %''s advance %. Reopen the payroll first -- that gives the money back; deleting it now would leave the advance short with no payslip to explain it.',
            to_char(v_amount, 'FM999999990.00'), v_staff, v_loan;
    END IF;

    -- 460: nor one that put wages into employee credit.
    IF EXISTS (SELECT 1 FROM wateremployeecredits c
               WHERE c.waterpayrolldeductionid = OLD.waterpayrollitemdeductionid AND c.status = 'Posted') THEN
        RAISE EXCEPTION 'This payroll has already kept % as employee credit. Reopen the payroll first -- that takes the credit back.',
            to_char(OLD.amount, 'FM999999990.00');
    END IF;

    RETURN OLD;
END;
$function$;

-- 460: cancel refuses a run whose postings would be left behind.
CREATE OR REPLACE FUNCTION public.spwaterpayrollrun_cancel(p_waterpayrollrunid integer, p_farmid text, p_cancelledby text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status        text;
    v_cashaccountid integer;
    v_netpay        numeric(14,2);
BEGIN
    SELECT r.status, r.watercashaccountid, r.totalnetpay
    INTO   v_status, v_cashaccountid, v_netpay
    FROM   waterpayrollruns r
    WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE
    LIMIT  1;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found.';
    END IF;
    IF v_status = 'Cancelled' THEN
        RETURN;
    END IF;
    -- 460: cancelling used to leave this run's advance repayments and (now)
    -- kept wages posted, with their cost still on the P&L. Reopen first: it
    -- gives them back properly.
    IF EXISTS (SELECT 1 FROM wateremployeeloanrepayments x
               WHERE x.farmid = p_farmid AND x.waterpayrollrunid = p_waterpayrollrunid
                 AND x.sourcetype = 'Payroll' AND x.status = 'Posted')
       OR EXISTS (SELECT 1 FROM wateremployeecredits c
                  WHERE c.farmid = p_farmid AND c.waterpayrollrunid = p_waterpayrollrunid AND c.status = 'Posted') THEN
        RAISE EXCEPTION 'This payroll repaid advances or kept wages as employee credit. Reopen it first (that gives them back), then cancel it.';
    END IF;

    IF v_status = 'Paid' THEN
        IF (v_cashaccountid IS NOT NULL AND v_netpay > 0) THEN
            INSERT INTO watercashtransactions (
                farmid, watercashaccountid, transactiondate, transactiontype,
                sourcetype, sourceid, amount, description, createdby, approvedby, approvedat
            )
            VALUES (
                p_farmid, v_cashaccountid, (now() at time zone 'utc'), 'Adjustment',
                'Payroll', p_waterpayrollrunid, v_netpay, 'Payroll cancelled — reversal',
                p_cancelledby, p_cancelledby, (now() at time zone 'utc')
            );

            UPDATE watercashaccounts a
            SET    currentbalance = a.currentbalance + v_netpay,
                   updatedat = (now() at time zone 'utc')
            WHERE  a.watercashaccountid = v_cashaccountid;
        END IF;
    END IF;

    UPDATE waterpayrollruns r
    SET    status    = 'Cancelled',
           notes     = CASE WHEN p_reason IS NULL THEN r.notes
                            ELSE left(COALESCE(r.notes,'') || chr(10) || 'Cancelled: ' || p_reason, 1000) END,
           updatedat = (now() at time zone 'utc')
    WHERE  r.waterpayrollrunid = p_waterpayrollrunid AND r.farmid = p_farmid;

    -- Cancel the linked Expense row (if any). Hard-cancel: IsDeleted=1 +
    -- Status='Cancelled' so it drops out of the active Expenses page AND the
    -- filtered unique index frees up for a future re-approval.
    UPDATE waterexpenses e
    SET    status    = 'Cancelled',
           isdeleted = TRUE,
           notes     = CASE WHEN p_reason IS NULL THEN e.notes
                            ELSE left(COALESCE(e.notes,'') || chr(10) || 'Payroll cancelled: ' || p_reason, 1000) END,
           updatedat = (now() at time zone 'utc')
    WHERE  e.farmid = p_farmid AND e.sourcetype = 'Payroll'
      AND  e.sourceid = p_waterpayrollrunid AND e.isdeleted = FALSE;
END;
$function$;

COMMIT;
