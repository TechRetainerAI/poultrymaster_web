-- =============================================================================
-- 441_PoultryEmployeeCredit.postgres.sql
--
-- Purpose
-- -------
-- Money the farm is KEEPING FOR A MEMBER OF STAFF. A worker asked not to be
-- paid every period and to collect the savings in one go later. The farm holds
-- the money; it is still hers.
--
-- THIS IS THE MIRROR OF poultryemployeeloans (305)
-- ================================================
--   employee loan    staff owes the farm   RECEIVABLE (asset)
--   employee credit  the farm owes staff   LIABILITY
--
-- THE ACCOUNTING, IN ONE TABLE
-- ============================
-- Gross wage 1,000, worker asks to keep 300:
--
--                         payroll day           payout day
--   P&L payroll cost      1,000                 nothing
--   cash out              700 (net pay)         300
--   employee credit       +300                  -300
--
-- The wage is EARNED on payroll day whether or not it is handed over, so the
-- expense is recognised then, in full. Handing it over later only settles a
-- debt: cash goes down, the liability goes down, profit does not move. That is
-- exactly the user's own rule ("it was not ours to begin with").
--
-- HOW EACH ENTRY TYPE MOVES THINGS
-- --------------------------------
--   PayrollSaving   +credit  P&L yes (NonCash payroll top-up)  cash no
--   WagesOwed       +credit  P&L yes (NonCash payroll expense) cash no
--   OpeningBalance  +credit  P&L no  (earned before the books)  cash no
--   Deposit         +credit  P&L no  (her own money)            cash IN
--   Payout          -credit  P&L no                             cash OUT
--
-- PayrollSaving is a payroll DEDUCTION ('EmployeeCredit'). It lowers net pay,
-- so Mark paid pays out less. Approval posts the credit and writes a NonCash
-- 'Payroll' expense for the kept amount, exactly the way 309 restores the cost
-- of loan repayments -- so the P&L shows the full gross wage. Unapproval
-- reverses both. A draft payroll changes no balance.
--
-- APPEND-ONLY
-- -----------
-- The balance is DERIVED: SUM of Posted rows, signed by entry type. There is no
-- balance column to drift. A mistake is corrected by reversing the row
-- (status -> Reversed, plus a cash reversal for Deposit/Payout), never by
-- deleting it. A reversal that would leave the worker owed less than zero --
-- because the money it added has already been paid out -- is refused.
--
-- Cash Flow shows a reversed Deposit/Payout twice -- the original on its own
-- date and the reversal on the day it was reversed -- so a day that has already
-- been closed keeps its figures (the 376 rule for supplier payments).
--
-- Idempotent. Safe to run more than once.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The ledger.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poultryemployeecredits (
    poultryemployeecreditid serial PRIMARY KEY,
    farmid                  varchar(450) NOT NULL,
    poultrystaffid          integer NOT NULL REFERENCES poultrystaff (poultrystaffid),

    entrytype   text NOT NULL
                CHECK (entrytype IN ('PayrollSaving', 'WagesOwed', 'OpeningBalance',
                                     'Deposit', 'Payout')),
    amount      numeric(14,2) NOT NULL CHECK (amount > 0),
    entrydate   date NOT NULL,

    -- Cash: only Deposit and Payout move money (ck_..._cash below).
    poultrycashaccountid      integer NULL REFERENCES poultrycashaccounts (poultrycashaccountid),
    paymentmethod             text NULL,
    poultrycashtransactionid  integer NULL,
    reversalcashtransactionid integer NULL,

    -- WagesOwed: the NonCash payroll expense it wrote.
    expenseid   integer NULL,

    -- PayrollSaving: where it came from. No FK on purpose: a reopened run can
    -- be deleted, and its REVERSED credit rows must keep saying which run they
    -- were. A POSTED one cannot outlive its run -- only Draft/Reopened runs can
    -- be deleted, and reopening reverses every credit the run posted.
    poultrypayrollrunid       integer NULL,
    poultrypayrollitemid      integer NULL,
    poultrypayrolldeductionid integer NULL,

    reference   text NULL,
    description text NULL,

    status      text NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),
    createdby   text NULL,
    createdat   timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby  text NULL,
    reversedat  timestamp NULL,
    reversalreason text NULL,

    CONSTRAINT ck_poultryemployeecredits_cash
        CHECK ((entrytype IN ('Deposit', 'Payout') AND poultrycashaccountid IS NOT NULL)
            OR (entrytype NOT IN ('Deposit', 'Payout') AND poultrycashaccountid IS NULL
                AND poultrycashtransactionid IS NULL)),
    CONSTRAINT ck_poultryemployeecredits_payroll
        CHECK ((entrytype = 'PayrollSaving') = (poultrypayrollrunid IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS ix_poultryemployeecredits_staff
    ON poultryemployeecredits (farmid, poultrystaffid, status);
CREATE INDEX IF NOT EXISTS ix_poultryemployeecredits_run
    ON poultryemployeecredits (poultrypayrollrunid) WHERE poultrypayrollrunid IS NOT NULL;
-- One live credit per payroll deduction, so approving twice cannot double it.
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryemployeecredits_deduction
    ON poultryemployeecredits (poultrypayrolldeductionid)
    WHERE poultrypayrolldeductionid IS NOT NULL AND status = 'Posted';

COMMENT ON TABLE poultryemployeecredits IS
    'Money the farm holds for a member of staff (a liability). Append-only; the '
    'balance is SUM of Posted rows, Payout negative. See migration 441.';

-- -----------------------------------------------------------------------------
-- 2. The deduction type.
-- -----------------------------------------------------------------------------
ALTER TABLE poultrypayrollitemdeductions
    ADD COLUMN IF NOT EXISTS poultryemployeecreditid integer NULL;

ALTER TABLE poultrypayrollitemdeductions
    DROP CONSTRAINT IF EXISTS poultrypayrollitemdeductions_deductiontype_check;
ALTER TABLE poultrypayrollitemdeductions
    ADD CONSTRAINT poultrypayrollitemdeductions_deductiontype_check
    CHECK (deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment',
                             'OtherDeduction', 'EmployeeCredit'));

ALTER TABLE poultrypayrollitemdeductions
    DROP CONSTRAINT IF EXISTS ck_poultrypayrollitemdeductions_loan;
ALTER TABLE poultrypayrollitemdeductions
    ADD CONSTRAINT ck_poultrypayrollitemdeductions_loan
    CHECK ((deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment')
            AND poultryemployeeloanid IS NOT NULL)
        OR (deductiontype IN ('OtherDeduction', 'EmployeeCredit')
            AND poultryemployeeloanid IS NULL));

-- -----------------------------------------------------------------------------
-- 3. Balance.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryemployeecredit_balance(
    p_farmid text, p_poultrystaffid integer)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
    SELECT COALESCE(SUM(CASE WHEN c.entrytype = 'Payout' THEN -c.amount ELSE c.amount END), 0)::numeric(14,2)
    FROM   poultryemployeecredits c
    WHERE  c.farmid = p_farmid
      AND  c.poultrystaffid = p_poultrystaffid
      AND  c.status = 'Posted';
$function$;

-- Cash helper: post one signed row to an account, refusing an overdraft.
CREATE OR REPLACE FUNCTION public.fnpoultryemployeecredit_cash(
    p_farmid text, p_accountid integer, p_date date, p_amount numeric,
    p_sourcetype text, p_sourceid integer, p_description text, p_by text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_allowneg boolean;
    v_bal      numeric;
    v_txid     integer;
BEGIN
    SELECT a.allownegativebalance, a.currentbalance INTO v_allowneg, v_bal
    FROM   poultrycashaccounts a
    WHERE  a.poultrycashaccountid = p_accountid AND a.farmid = p_farmid
    FOR UPDATE;
    IF v_allowneg IS NULL THEN
        RAISE EXCEPTION 'Cash account does not belong to this company.';
    END IF;
    IF p_amount < 0 AND NOT v_allowneg AND (v_bal + p_amount) < 0 THEN
        RAISE EXCEPTION 'This payment would overdraw the cash account (balance %, payment %).',
              v_bal, (-p_amount)::numeric(14,2);
    END IF;

    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance + p_amount,
           updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycashaccountid = p_accountid;

    INSERT INTO poultrycashtransactions
        (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
         amount, balanceaftertransaction, description, createdby, approvedby, approvedat)
    VALUES
        (p_farmid, p_accountid, p_date::timestamp,
         CASE WHEN p_amount >= 0 THEN 'CashIn' ELSE 'CashOut' END,
         p_sourcetype, p_sourceid, p_amount, v_bal + p_amount,
         left(p_description, 500), p_by, p_by, (now() at time zone 'utc'))
    RETURNING poultrycashtransactionid INTO v_txid;
    RETURN v_txid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Add credit by hand: OpeningBalance, Deposit, WagesOwed.
--    (PayrollSaving is posted by approving payroll, and by nothing else.)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryemployeecredit_add(
    p_farmid text,
    p_poultrystaffid integer,
    p_entrytype text,
    p_amount numeric,
    p_entrydate date DEFAULT NULL,
    p_poultrycashaccountid integer DEFAULT NULL,
    p_paymentmethod text DEFAULT NULL,
    p_reference text DEFAULT NULL,
    p_description text DEFAULT NULL,
    p_createdby text DEFAULT NULL)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_type   text := NULLIF(btrim(p_entrytype), '');
    v_date   date := COALESCE(p_entrydate, ((now() at time zone 'utc'))::date);
    v_staff  text;
    v_id     integer;
    v_txid   integer;
    v_expid  integer;
    v_farmguid uuid;
    v_desc   text;
BEGIN
    IF v_type NOT IN ('OpeningBalance', 'Deposit', 'WagesOwed') THEN
        RAISE EXCEPTION 'Credit can be added as an opening balance, money handed in, or wages owed. Payroll savings are added by approving payroll.';
    END IF;
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'The amount must be more than zero.';
    END IF;

    SELECT btrim(s.firstname || ' ' || s.lastname) INTO v_staff
    FROM   poultrystaff s
    WHERE  s.poultrystaffid = p_poultrystaffid AND s.farmid = p_farmid
      AND  NOT COALESCE(s.isdeleted, FALSE);
    IF v_staff IS NULL THEN
        RAISE EXCEPTION 'Staff member not found on this company.';
    END IF;

    IF v_type = 'Deposit' AND p_poultrycashaccountid IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account the money went into.';
    END IF;

    v_desc := COALESCE(NULLIF(btrim(p_description), ''),
                       CASE v_type
                           WHEN 'OpeningBalance' THEN 'Opening employee credit'
                           WHEN 'Deposit'        THEN 'Money handed in to keep'
                           ELSE 'Wages kept as employee credit' END);

    INSERT INTO poultryemployeecredits
        (farmid, poultrystaffid, entrytype, amount, entrydate,
         poultrycashaccountid, paymentmethod, reference, description, createdby)
    VALUES
        (p_farmid, p_poultrystaffid, v_type, round(p_amount, 2), v_date,
         CASE WHEN v_type = 'Deposit' THEN p_poultrycashaccountid END,
         CASE WHEN v_type = 'Deposit' THEN NULLIF(btrim(p_paymentmethod), '') END,
         NULLIF(btrim(p_reference), ''), v_desc, p_createdby)
    RETURNING poultryemployeecreditid INTO v_id;

    IF v_type = 'Deposit' THEN
        v_txid := public.fnpoultryemployeecredit_cash(
            p_farmid, p_poultrycashaccountid, v_date, round(p_amount, 2),
            'EmployeeCreditDeposit', v_id,
            'Employee credit: money from ' || v_staff, p_createdby);
        UPDATE poultryemployeecredits SET poultrycashtransactionid = v_txid
        WHERE  poultryemployeecreditid = v_id;
    ELSIF v_type = 'WagesOwed' THEN
        -- The wage is earned today and not paid: a payroll cost with no cash,
        -- NonCash so Cash Flow and Supplier Balances skip it while the P&L
        -- (which sums every expense row) counts it.
        BEGIN
            v_farmguid := p_farmid::uuid;
        EXCEPTION WHEN OTHERS THEN
            v_farmguid := NULL;
        END;
        INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                             flockid, userid, farmid, sourcetype, sourceid)
        VALUES (v_date, 'Payroll', v_staff || ' - ' || v_desc, round(p_amount, 2), 'NonCash',
                NULL, COALESCE(p_createdby, ''), v_farmguid, 'EmployeeCreditWages', v_id)
        RETURNING expenseid INTO v_expid;
        UPDATE poultryemployeecredits SET expenseid = v_expid
        WHERE  poultryemployeecreditid = v_id;
    END IF;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Pay out. Cash out, liability down, no P&L.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryemployeecredit_payout(
    p_farmid text,
    p_poultrystaffid integer,
    p_amount numeric,
    p_poultrycashaccountid integer,
    p_entrydate date DEFAULT NULL,
    p_paymentmethod text DEFAULT NULL,
    p_reference text DEFAULT NULL,
    p_description text DEFAULT NULL,
    p_createdby text DEFAULT NULL)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_date  date := COALESCE(p_entrydate, ((now() at time zone 'utc'))::date);
    v_staff text;
    v_bal   numeric;
    v_id    integer;
    v_txid  integer;
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'The amount must be more than zero.';
    END IF;
    IF p_poultrycashaccountid IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account the money is paid from.';
    END IF;

    -- Locked, so two payouts for the same worker serialise and the second one
    -- re-reads the balance the first one left.
    SELECT btrim(s.firstname || ' ' || s.lastname) INTO v_staff
    FROM   poultrystaff s
    WHERE  s.poultrystaffid = p_poultrystaffid AND s.farmid = p_farmid
    FOR UPDATE;
    IF v_staff IS NULL THEN
        RAISE EXCEPTION 'Staff member not found on this company.';
    END IF;

    v_bal := public.fnpoultryemployeecredit_balance(p_farmid, p_poultrystaffid);
    IF round(p_amount, 2) > v_bal THEN
        RAISE EXCEPTION 'The farm is only holding % for %.', v_bal, v_staff;
    END IF;

    INSERT INTO poultryemployeecredits
        (farmid, poultrystaffid, entrytype, amount, entrydate,
         poultrycashaccountid, paymentmethod, reference, description, createdby)
    VALUES
        (p_farmid, p_poultrystaffid, 'Payout', round(p_amount, 2), v_date,
         p_poultrycashaccountid, NULLIF(btrim(p_paymentmethod), ''),
         NULLIF(btrim(p_reference), ''),
         COALESCE(NULLIF(btrim(p_description), ''), 'Employee credit paid out'), p_createdby)
    RETURNING poultryemployeecreditid INTO v_id;

    v_txid := public.fnpoultryemployeecredit_cash(
        p_farmid, p_poultrycashaccountid, v_date, -round(p_amount, 2),
        'EmployeeCreditPayout', v_id,
        'Employee credit paid to ' || v_staff, p_createdby);
    UPDATE poultryemployeecredits SET poultrycashtransactionid = v_txid
    WHERE  poultryemployeecreditid = v_id;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Reverse one entry. Not for payroll savings: reopen the payroll instead.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryemployeecredit_reverserow(
    p_farmid text, p_id integer, p_reason text, p_by text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
-- The shared core: used by the reverse SP and by payroll unapproval.
DECLARE
    v_c     poultryemployeecredits%ROWTYPE;
    v_staff text;
    v_bal   numeric;
    v_txid  integer;
BEGIN
    SELECT * INTO v_c FROM poultryemployeecredits
    WHERE  poultryemployeecreditid = p_id AND farmid = p_farmid
    FOR UPDATE;
    IF v_c.poultryemployeecreditid IS NULL THEN
        RAISE EXCEPTION 'Employee credit entry not found on this company.';
    END IF;
    IF v_c.status <> 'Posted' THEN
        RAISE EXCEPTION 'This entry has already been reversed.';
    END IF;

    SELECT btrim(s.firstname || ' ' || s.lastname) INTO v_staff
    FROM   poultrystaff s WHERE s.poultrystaffid = v_c.poultrystaffid
    FOR UPDATE;

    -- Taking back money that was ADDED must not leave the farm owing less than
    -- nothing -- that would mean it has already been paid out.
    IF v_c.entrytype <> 'Payout' THEN
        v_bal := public.fnpoultryemployeecredit_balance(p_farmid, v_c.poultrystaffid);
        IF v_bal - v_c.amount < 0 THEN
            RAISE EXCEPTION
                'Only % of %''s credit is left -- the rest has been paid out. Reverse the payout first.',
                v_bal, v_staff;
        END IF;
    END IF;

    IF v_c.entrytype IN ('Deposit', 'Payout') THEN
        v_txid := public.fnpoultryemployeecredit_cash(
            p_farmid, v_c.poultrycashaccountid, ((now() at time zone 'utc'))::date,
            CASE WHEN v_c.entrytype = 'Deposit' THEN -v_c.amount ELSE v_c.amount END,
            'EmployeeCreditReversal', v_c.poultryemployeecreditid,
            'Reversal: employee credit ' || lower(v_c.entrytype) || ' for ' || v_staff, p_by);
    END IF;

    IF v_c.entrytype = 'WagesOwed' AND v_c.expenseid IS NOT NULL THEN
        PERFORM set_config('poultry.employeecredit_reverse', 'on', true);
        DELETE FROM expense WHERE expenseid = v_c.expenseid;
        PERFORM set_config('poultry.employeecredit_reverse', 'off', true);
    END IF;

    UPDATE poultryemployeecredits
    SET    status = 'Reversed',
           reversalcashtransactionid = v_txid,
           reversedby = p_by,
           reversedat = (now() at time zone 'utc'),
           reversalreason = NULLIF(btrim(p_reason), '')
    WHERE  poultryemployeecreditid = p_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryemployeecredit_reverse(
    p_farmid text, p_poultryemployeecreditid integer, p_reason text, p_reversedby text DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_type text;
BEGIN
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for the reversal.';
    END IF;
    SELECT entrytype INTO v_type FROM poultryemployeecredits
    WHERE  poultryemployeecreditid = p_poultryemployeecreditid AND farmid = p_farmid;
    IF v_type = 'PayrollSaving' THEN
        RAISE EXCEPTION 'This credit came from payroll. Reopen that payroll to take it back.';
    END IF;
    PERFORM public.fnpoultryemployeecredit_reverserow(
        p_farmid, p_poultryemployeecreditid, p_reason, p_reversedby);
END;
$function$;

-- The WagesOwed expense belongs to its credit row: it is changed by reversing
-- the credit, not from the Expenses page.
CREATE OR REPLACE FUNCTION public.fnpoultryemployeecredit_expenseguard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF COALESCE(current_setting('poultry.employeecredit_reverse', true), 'off') = 'on' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'These wages are held as employee credit. Reverse the entry on Employee Credit instead.';
    END IF;
    IF NEW.amount IS DISTINCT FROM OLD.amount
       OR NEW.paymentmethod IS DISTINCT FROM OLD.paymentmethod
       OR NEW.expensedate IS DISTINCT FROM OLD.expensedate THEN
        RAISE EXCEPTION 'These wages are held as employee credit. Reverse the entry on Employee Credit and add it again.';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trgpoultryemployeecredit_expenseguard ON expense;
CREATE TRIGGER trgpoultryemployeecredit_expenseguard
    BEFORE UPDATE OR DELETE ON expense
    FOR EACH ROW
    WHEN (OLD.sourcetype = 'EmployeeCreditWages')
    EXECUTE FUNCTION public.fnpoultryemployeecredit_expenseguard();

-- -----------------------------------------------------------------------------
-- 7. Readers.
-- -----------------------------------------------------------------------------
-- One row per member of staff who has, or had, credit.
CREATE OR REPLACE FUNCTION public.sppoultryemployeecredit_balances(p_farmid text)
 RETURNS TABLE(poultrystaffid integer, staffname text, staffrole text, isactive boolean,
               balance numeric, totalin numeric, totalpaidout numeric,
               lastentrydate date, entrycount integer)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT s.poultrystaffid,
           btrim(s.firstname || ' ' || s.lastname)::text,
           s.role::text,
           COALESCE(s.isactive, TRUE) AND NOT COALESCE(s.isdeleted, FALSE),
           COALESCE(SUM(CASE WHEN c.entrytype = 'Payout' THEN -c.amount ELSE c.amount END)
                    FILTER (WHERE c.status = 'Posted'), 0)::numeric(14,2),
           COALESCE(SUM(c.amount) FILTER (WHERE c.status = 'Posted' AND c.entrytype <> 'Payout'), 0)::numeric(14,2),
           COALESCE(SUM(c.amount) FILTER (WHERE c.status = 'Posted' AND c.entrytype = 'Payout'), 0)::numeric(14,2),
           MAX(c.entrydate),
           COUNT(c.poultryemployeecreditid)::int
    FROM   poultrystaff s
    JOIN   poultryemployeecredits c
           ON c.poultrystaffid = s.poultrystaffid AND c.farmid = p_farmid
    WHERE  s.farmid = p_farmid
    GROUP  BY s.poultrystaffid, s.firstname, s.lastname, s.role, s.isactive, s.isdeleted
    ORDER  BY 5 DESC, 2;
$function$;

-- The statement: every entry, oldest first, with a running balance over
-- Posted rows only.
CREATE OR REPLACE FUNCTION public.sppoultryemployeecredit_getall(
    p_farmid text, p_poultrystaffid integer DEFAULT NULL)
 RETURNS TABLE(poultryemployeecreditid integer, poultrystaffid integer, staffname text,
               entrytype text, amount numeric, signedamount numeric, runningbalance numeric,
               entrydate date, poultrycashaccountid integer, accountname text,
               paymentmethod text, reference text, description text,
               poultrypayrollrunid integer, payrollperiod text, expenseid integer,
               status text, createdby text, createdat timestamp,
               reversedby text, reversedat timestamp, reversalreason text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT c.poultryemployeecreditid, c.poultrystaffid,
           btrim(s.firstname || ' ' || s.lastname)::text,
           c.entrytype, c.amount,
           (CASE WHEN c.entrytype = 'Payout' THEN -c.amount ELSE c.amount END)::numeric(14,2),
           SUM(CASE WHEN c.status <> 'Posted' THEN 0
                    WHEN c.entrytype = 'Payout' THEN -c.amount ELSE c.amount END)
               OVER (PARTITION BY c.poultrystaffid
                     ORDER BY c.entrydate, c.createdat, c.poultryemployeecreditid)::numeric(14,2),
           c.entrydate, c.poultrycashaccountid, a.accountname::text,
           c.paymentmethod, c.reference, c.description,
           c.poultrypayrollrunid,
           CASE WHEN r.poultrypayrollrunid IS NOT NULL
                THEN to_char(r.periodstart, 'YYYY-MM-DD') || ' to ' || to_char(r.periodend, 'YYYY-MM-DD') END,
           c.expenseid,
           c.status, c.createdby, c.createdat, c.reversedby, c.reversedat, c.reversalreason
    FROM   poultryemployeecredits c
    JOIN   poultrystaff s ON s.poultrystaffid = c.poultrystaffid
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = c.poultrycashaccountid
    LEFT   JOIN poultrypayrollruns r ON r.poultrypayrollrunid = c.poultrypayrollrunid
    WHERE  c.farmid = p_farmid
      AND  (p_poultrystaffid IS NULL OR c.poultrystaffid = p_poultrystaffid)
    ORDER  BY c.entrydate DESC, c.createdat DESC, c.poultryemployeecreditid DESC;
$function$;

-- The single number for cash screens: what the farm is holding for staff.
CREATE OR REPLACE FUNCTION public.sppoultryemployeecredit_total(p_farmid text)
 RETURNS TABLE(totalheld numeric, staffcount integer)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT COALESCE(SUM(b.balance), 0)::numeric(14,2),
           COUNT(*) FILTER (WHERE b.balance > 0)::int
    FROM   public.sppoultryemployeecredit_balances(p_farmid) b;
$function$;

-- -----------------------------------------------------------------------------
-- 8. Cash Flow rows: deposits in, payouts out, and the reversal of either on
--    the day it was reversed. Spliced into sppoultrycashflow_rows below.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryemployeecredit_cashflowrows(
    p_farmid text, p_fromdate timestamp DEFAULT NULL, p_todate timestamp DEFAULT NULL)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer,
               accountname text, transactiondate timestamp, transactiontype text,
               sourcetype text, sourceid integer, istransfer boolean, amount numeric,
               description text, flowgroup text, createdat timestamp)
 LANGUAGE sql
 STABLE
AS $function$
    -- The original movement, on its own business date (entry time if today).
    SELECT 'EmployeeCredit'::text,
           FALSE,
           c.poultryemployeecreditid,
           c.poultrycashaccountid,
           a.accountname::text,
           CASE WHEN c.entrydate = c.createdat::date THEN c.createdat ELSE c.entrydate::timestamp END,
           CASE WHEN c.entrytype = 'Deposit' THEN 'CashIn' ELSE 'CashOut' END::text,
           CASE WHEN c.entrytype = 'Deposit' THEN 'EmployeeCreditDeposit'
                ELSE 'EmployeeCreditPayout' END::text,
           c.poultryemployeecreditid,
           FALSE,
           (CASE WHEN c.entrytype = 'Deposit' THEN c.amount ELSE -c.amount END)::numeric,
           (CASE WHEN c.entrytype = 'Deposit' THEN 'Employee credit: money from '
                 ELSE 'Employee credit paid to ' END || btrim(s.firstname || ' ' || s.lastname))::text,
           CASE WHEN c.entrytype = 'Deposit' THEN 'EmployeeCreditIn' ELSE 'EmployeeCreditOut' END::text,
           c.createdat
    FROM   poultryemployeecredits c
    JOIN   poultrystaff s ON s.poultrystaffid = c.poultrystaffid
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = c.poultrycashaccountid
    WHERE  c.farmid = p_farmid
      AND  c.entrytype IN ('Deposit', 'Payout')
      AND  CASE WHEN c.entrydate = c.createdat::date THEN c.createdat ELSE c.entrydate::timestamp END
           BETWEEN COALESCE(p_fromdate, '-infinity'::timestamp) AND COALESCE(p_todate, 'infinity'::timestamp)

    UNION ALL
    -- Its reversal, on the day it happened.
    SELECT 'EmployeeCreditReversal'::text,
           FALSE,
           c.poultryemployeecreditid,
           c.poultrycashaccountid,
           a.accountname::text,
           c.reversedat,
           CASE WHEN c.entrytype = 'Deposit' THEN 'CashOut' ELSE 'CashIn' END::text,
           'EmployeeCreditReversal'::text,
           c.poultryemployeecreditid,
           FALSE,
           (CASE WHEN c.entrytype = 'Deposit' THEN -c.amount ELSE c.amount END)::numeric,
           ('Reversal: employee credit ' || lower(c.entrytype) || ' for ' ||
            btrim(s.firstname || ' ' || s.lastname))::text,
           CASE WHEN c.entrytype = 'Deposit' THEN 'EmployeeCreditOut' ELSE 'EmployeeCreditIn' END::text,
           c.reversedat
    FROM   poultryemployeecredits c
    JOIN   poultrystaff s ON s.poultrystaffid = c.poultrystaffid
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = c.poultrycashaccountid
    WHERE  c.farmid = p_farmid
      AND  c.entrytype IN ('Deposit', 'Payout')
      AND  c.status = 'Reversed'
      AND  c.reversedat IS NOT NULL
      AND  c.reversedat BETWEEN COALESCE(p_fromdate, '-infinity'::timestamp) AND COALESCE(p_todate, 'infinity'::timestamp);
$function$;


-- -----------------------------------------------------------------------------
-- 9a. Deduction save: an EmployeeCredit row carries no advance.
-- (live body via pg_get_functiondef 2026-11-16; only the 441 lines added)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrypayrollitemdeduction_save(p_farmid text, p_poultrypayrollitemid integer, p_deductiontype text, p_amount numeric, p_poultryemployeeloanid integer DEFAULT NULL::integer, p_description text DEFAULT NULL::text, p_reference text DEFAULT NULL::text, p_poultrypayrollitemdeductionid integer DEFAULT NULL::integer, p_savedby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id          integer := p_poultrypayrollitemdeductionid;
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

    SELECT i.poultrypayrollrunid, i.poultrystaffid, r.status
    INTO   v_runid, v_staffid, v_runstatus
    FROM   poultrypayrollitems i
    JOIN   poultrypayrollruns r ON r.poultrypayrollrunid = i.poultrypayrollrunid
    WHERE  i.poultrypayrollitemid = p_poultrypayrollitemid
      AND  r.farmid = p_farmid;

    IF v_runid IS NULL THEN
        RAISE EXCEPTION 'Payroll line not found on this farm.';
    END IF;
    -- 'Reopened', not just 'Draft'. sppoultrypayrollrun_unapprove sets a
    -- reopened run to 'Reopened' and _approve accepts both, so a deduction has
    -- to be editable in both states -- otherwise the reverse, change the
    -- deduction, re-approve cycle that spec section 44 requires is impossible:
    -- you could unapprove the payroll and then not be allowed to touch it.
    IF v_runstatus NOT IN ('Draft', 'Reopened') THEN
        RAISE EXCEPTION
            'This payroll is %. Reopen it before changing deductions.', v_runstatus;
    END IF;

    IF v_type IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment') THEN
        IF p_poultryemployeeloanid IS NULL THEN
            RAISE EXCEPTION 'Choose which advance this repayment is against.';
        END IF;

        SELECT l.poultrystaffid, l.status, l.outstandingbalance, l.loannumber
        INTO   v_loanstaff, v_loanstatus, v_outstanding, v_number
        FROM   poultryemployeeloans l
        WHERE  l.poultryemployeeloanid = p_poultryemployeeloanid
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
                COALESCE(v_number, p_poultryemployeeloanid::text), v_loanstatus;
        END IF;

        -- Section 34. What this run ALREADY plans to take off the same advance
        -- counts against the balance, or two 300 deductions could both pass
        -- against a 500 balance and only fail at approval -- which is the worst
        -- possible moment to find out.
        SELECT COALESCE(SUM(d.amount), 0)
        INTO   v_claimed
        FROM   poultrypayrollitemdeductions d
        WHERE  d.poultryemployeeloanid = p_poultryemployeeloanid
          AND  d.status = 'Draft'
          AND  (v_id IS NULL OR d.poultrypayrollitemdeductionid <> v_id);

        IF v_amount + v_claimed > v_outstanding THEN
            IF v_claimed > 0 THEN
                RAISE EXCEPTION
                    'Only % is left on advance %, and % of it is already planned in a draft payroll.',
                    v_outstanding, COALESCE(v_number, p_poultryemployeeloanid::text), v_claimed;
            ELSE
                RAISE EXCEPTION 'Only % is left on advance %.',
                    v_outstanding, COALESCE(v_number, p_poultryemployeeloanid::text);
            END IF;
        END IF;
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO poultrypayrollitemdeductions (
            farmid, poultrypayrollrunid, poultrypayrollitemid, poultrystaffid,
            deductiontype, amount, poultryemployeeloanid,
            description, reference, status, createdby)
        VALUES (
            p_farmid, v_runid, p_poultrypayrollitemid, v_staffid,
            v_type, v_amount,
            CASE WHEN v_type IN ('OtherDeduction', 'EmployeeCredit') THEN NULL /* 441 */ ELSE p_poultryemployeeloanid END,
            NULLIF(btrim(p_description), ''), NULLIF(btrim(p_reference), ''),
            'Draft', p_savedby)
        RETURNING poultrypayrollitemdeductionid INTO v_id;
    ELSE
        UPDATE poultrypayrollitemdeductions d
        SET    deductiontype = v_type,
               amount = v_amount,
               poultryemployeeloanid =
                   CASE WHEN v_type IN ('OtherDeduction', 'EmployeeCredit') THEN NULL /* 441 */
                        ELSE p_poultryemployeeloanid END,
               description = NULLIF(btrim(p_description), ''),
               reference   = NULLIF(btrim(p_reference), ''),
               updatedby   = p_savedby,
               updatedat   = (now() at time zone 'utc')
        WHERE  d.poultrypayrollitemdeductionid = v_id
          AND  d.farmid = p_farmid
          AND  d.status = 'Draft';

        IF NOT FOUND THEN
            RAISE EXCEPTION
                'Deduction % cannot be edited -- it is not a draft on this farm.', v_id;
        END IF;
    END IF;

    PERFORM public.fnpoultrypayrollitem_recalcdeductions(p_poultrypayrollitemid);
    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 9b. Approve: post kept wages as employee credit + NonCash payroll top-up.
-- (live body via pg_get_functiondef 2026-11-16; only the 441 lines added)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrypayrollrun_approve(p_poultrypayrollrunid integer, p_farmid text, p_approvedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_periodstart date;
    v_periodend date;
    v_paydate date;
    v_net numeric;
    v_farmguid uuid;
    v_expdate date;
    v_desc text;
    -- 309.
    v_d          record;
    v_repayid    integer;
    v_loantotal  numeric := 0;
    v_ctxloan    text := NULL;
    v_ctxstaff   text := NULL;
    -- 441.
    v_c          record;
    v_creditid   integer;
    v_credittotal numeric := 0;
BEGIN
    SELECT r.status, r.periodstart, r.periodend, r.paydate, r.totalnetpay
    INTO   v_status, v_periodstart, v_periodend, v_paydate, v_net
    FROM   poultrypayrollruns r
    WHERE  r.poultrypayrollrunid = p_poultrypayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found for this farm.';
    END IF;
    IF v_status NOT IN ('Draft', 'Reopened') THEN
        RAISE EXCEPTION 'Payroll run is %; only Draft or Reopened can be approved.', v_status;
    END IF;
    BEGIN
        v_farmguid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_farmguid := NULL;
    END;
    v_expdate := COALESCE(v_paydate, ((now() at time zone 'utc'))::date);
    v_desc := concat('Payroll ', to_char(v_periodstart, 'YYYY-MM-DD'), ' to ', to_char(v_periodend, 'YYYY-MM-DD'));

    -- ---- 309: turn planned loan deductions into real repayments -------------
    -- BEFORE the status flips and before the expense is written, so that a
    -- rejected repayment leaves a run that still looks exactly as it did.
    -- (Belt and braces -- the whole function is one transaction either way.)
    --
    -- The validation is NOT repeated here. sppoultryemployeeloanrepayment_record
    -- re-checks the farm, the worker, the advance's status and its outstanding
    -- balance at posting time, which is the only moment those answers are
    -- authoritative. 306 checks the same things when the deduction is entered,
    -- so the user normally finds out early; this is what guarantees it.
    BEGIN
        FOR v_d IN
            SELECT d.poultrypayrollitemdeductionid AS dedid,
                   d.poultrypayrollitemid          AS itemid,
                   d.poultryemployeeloanid         AS loanid,
                   d.poultrystaffid                AS staffid,
                   d.amount                        AS amount,
                   l.loannumber                    AS loannumber,
                   btrim(s.firstname || ' ' || s.lastname) AS staffname
            FROM   poultrypayrollitemdeductions d
            JOIN   poultryemployeeloans l ON l.poultryemployeeloanid = d.poultryemployeeloanid
            JOIN   poultrystaff s ON s.poultrystaffid = d.poultrystaffid
            WHERE  d.poultrypayrollrunid = p_poultrypayrollrunid
              AND  d.farmid = p_farmid
              AND  d.status = 'Draft'
              AND  d.deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment')
            ORDER  BY d.poultrypayrollitemdeductionid
        LOOP
            v_ctxloan  := COALESCE(v_d.loannumber, v_d.loanid::text);
            v_ctxstaff := v_d.staffname;

            v_repayid := public.sppoultryemployeeloanrepayment_record(
                p_farmid                    => p_farmid,
                p_poultryemployeeloanid     => v_d.loanid,
                p_amount                    => v_d.amount,
                p_sourcetype                => 'Payroll',
                -- All principal. Interest on a staff advance is not charged per
                -- payroll period, and splitting it here would be inventing an
                -- amortisation rule the farm never asked for.
                p_principalamount           => v_d.amount,
                p_interestamount            => 0,
                p_repaymentdate             => v_expdate::timestamp,
                -- No cash account, and 305's constraint would refuse one: the
                -- wage paid out is already net, so no money moved for this.
                p_poultrycashaccountid      => NULL,
                p_description               => v_desc,
                p_poultrypayrollrunid       => p_poultrypayrollrunid,
                p_poultrypayrollitemid      => v_d.itemid,
                p_poultrypayrolldeductionid => v_d.dedid,
                p_poultrystaffid            => v_d.staffid,
                p_createdby                 => p_approvedby);

            UPDATE poultrypayrollitemdeductions
            SET    status = 'Posted',
                   poultryemployeeloanrepaymentid = v_repayid,
                   updatedby = p_approvedby,
                   updatedat = (now() at time zone 'utc')
            WHERE  poultrypayrollitemdeductionid = v_d.dedid;

            v_loantotal := v_loantotal + v_d.amount;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        -- Section 40: say which advance stopped the approval. Without this the
        -- user sees a balance error with no idea whose wage it came from.
        IF v_ctxloan IS NULL THEN
            RAISE;
        END IF;
        RAISE EXCEPTION
            'Payroll was not approved. The deduction against advance % for % could not be posted: %',
            v_ctxloan, COALESCE(v_ctxstaff, 'this member of staff'), SQLERRM;
    END;

    -- ---- 441: wages kept as employee credit --------------------------------
    -- The kept amount is still the worker's wage: it becomes money the farm
    -- OWES her (a credit row) and, below, a NonCash payroll cost.
    FOR v_c IN
        SELECT d.poultrypayrollitemdeductionid AS dedid,
               d.poultrypayrollitemid          AS itemid,
               d.poultrystaffid                AS staffid,
               d.amount                        AS amount
        FROM   poultrypayrollitemdeductions d
        WHERE  d.poultrypayrollrunid = p_poultrypayrollrunid
          AND  d.farmid = p_farmid
          AND  d.status = 'Draft'
          AND  d.deductiontype = 'EmployeeCredit'
        ORDER  BY d.poultrypayrollitemdeductionid
    LOOP
        INSERT INTO poultryemployeecredits
            (farmid, poultrystaffid, entrytype, amount, entrydate,
             poultrypayrollrunid, poultrypayrollitemid, poultrypayrolldeductionid,
             description, createdby)
        VALUES
            (p_farmid, v_c.staffid, 'PayrollSaving', v_c.amount, v_expdate,
             p_poultrypayrollrunid, v_c.itemid, v_c.dedid,
             v_desc || ' - kept as employee credit', p_approvedby)
        RETURNING poultryemployeecreditid INTO v_creditid;

        UPDATE poultrypayrollitemdeductions
        SET    status = 'Posted',
               poultryemployeecreditid = v_creditid,
               updatedby = p_approvedby,
               updatedat = (now() at time zone 'utc')
        WHERE  poultrypayrollitemdeductionid = v_c.dedid;

        v_credittotal := v_credittotal + v_c.amount;
    END LOOP;

    -- Every remaining planned deduction on the run is now in force. The loan
    -- ones already flipped above; this catches Other deductions, which post
    -- nothing but should not stay 'Draft' on an approved run.
    UPDATE poultrypayrollitemdeductions
    SET    status = 'Posted',
           updatedby = p_approvedby,
           updatedat = (now() at time zone 'utc')
    WHERE  poultrypayrollrunid = p_poultrypayrollrunid
      AND  farmid = p_farmid
      AND  status = 'Draft';

    IF v_status = 'Reopened' THEN
        UPDATE poultrypayrollruns r
        SET    status = 'Approved', reapprovedby = p_approvedby, reapprovedat = (now() at time zone 'utc'),
               updatedat = (now() at time zone 'utc')
        WHERE  r.poultrypayrollrunid = p_poultrypayrollrunid AND r.farmid = p_farmid;
    ELSE
        UPDATE poultrypayrollruns r
        SET    status = 'Approved', approvedby = p_approvedby, approvedat = (now() at time zone 'utc'),
               updatedat = (now() at time zone 'utc')
        WHERE  r.poultrypayrollrunid = p_poultrypayrollrunid AND r.farmid = p_farmid;
    END IF;
    -- Upsert the linked expense (matched by SourceType/SourceId).
    IF EXISTS (SELECT 1 FROM expense e WHERE e.sourcetype = 'Payroll' AND e.sourceid = p_poultrypayrollrunid) THEN
        UPDATE expense e
        SET    amount = v_net, expensedate = v_expdate, description = v_desc, category = 'Payroll'
        WHERE  e.sourcetype = 'Payroll' AND e.sourceid = p_poultrypayrollrunid AND e.farmid = v_farmguid;
    ELSE
        INSERT INTO expense (expensedate, category, description, amount, paymentmethod, flockid, userid, farmid, sourcetype, sourceid)
        VALUES (v_expdate, 'Payroll', v_desc, v_net, 'Cash', NULL, COALESCE(p_approvedby, ''), v_farmguid, 'Payroll', p_poultrypayrollrunid);
    END IF;

    -- ---- 309: put back the wage cost the deductions took out ----------------
    -- Only for LOAN deductions, and only when there are any. See the header for
    -- why 'NonCash' is the right marker and what it does in each report.
    --
    -- Its own sourcetype, so 310 can find and remove it on unapproval exactly
    -- the way the run's own expense is removed.
    IF v_loantotal > 0 THEN
        IF EXISTS (SELECT 1 FROM expense e
                    WHERE e.sourcetype = 'PayrollEmployeeLoan'
                      AND e.sourceid = p_poultrypayrollrunid) THEN
            UPDATE expense e
            SET    amount = v_loantotal, expensedate = v_expdate,
                   description = v_desc || ' - advances repaid from wages',
                   category = 'Payroll'
            WHERE  e.sourcetype = 'PayrollEmployeeLoan'
              AND  e.sourceid = p_poultrypayrollrunid
              AND  e.farmid = v_farmguid;
        ELSE
            INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                                 flockid, userid, farmid, sourcetype, sourceid)
            VALUES (v_expdate, 'Payroll', v_desc || ' - advances repaid from wages',
                    v_loantotal, 'NonCash', NULL, COALESCE(p_approvedby, ''), v_farmguid,
                    'PayrollEmployeeLoan', p_poultrypayrollrunid);
        END IF;
    END IF;

    -- ---- 441: put the kept wages back into payroll cost ---------------------
    -- Same shape as the advance top-up: NonCash, so Cash Flow and Supplier
    -- Balances skip it and the P&L counts it. Gross wage = P&L payroll cost.
    IF v_credittotal > 0 THEN
        IF EXISTS (SELECT 1 FROM expense e
                    WHERE e.sourcetype = 'PayrollEmployeeCredit'
                      AND e.sourceid = p_poultrypayrollrunid) THEN
            UPDATE expense e
            SET    amount = v_credittotal, expensedate = v_expdate,
                   description = v_desc || ' - wages kept as employee credit',
                   category = 'Payroll'
            WHERE  e.sourcetype = 'PayrollEmployeeCredit'
              AND  e.sourceid = p_poultrypayrollrunid
              AND  e.farmid = v_farmguid;
        ELSE
            INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                                 flockid, userid, farmid, sourcetype, sourceid)
            VALUES (v_expdate, 'Payroll', v_desc || ' - wages kept as employee credit',
                    v_credittotal, 'NonCash', NULL, COALESCE(p_approvedby, ''), v_farmguid,
                    'PayrollEmployeeCredit', p_poultrypayrollrunid);
        END IF;
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 9c. Unapprove: reverse the run's employee credit and its top-up.
-- (live body via pg_get_functiondef 2026-11-16; only the 441 lines added)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrypayrollrun_unapprove(p_poultrypayrollrunid integer, p_farmid text, p_reopenedby text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_farmguid uuid;
    -- 310.
    v_r        record;
    v_reason   text;
    v_ctxloan  text := NULL;
    v_ctxstaff text := NULL;
    -- 441.
    v_c        record;
BEGIN
    SELECT r.status INTO v_status
    FROM   poultrypayrollruns r
    WHERE  r.poultrypayrollrunid = p_poultrypayrollrunid AND r.farmid = p_farmid AND r.isdeleted = FALSE;
    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Payroll run not found for this farm.';
    END IF;
    IF v_status NOT IN ('Approved', 'Paid') THEN
        RAISE EXCEPTION 'Payroll run is %; only Approved or Paid can be reopened.', v_status;
    END IF;
    BEGIN
        v_farmguid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_farmguid := NULL;
    END;

    -- ---- 310: give back every advance repayment this run took ---------------
    -- First, so that if an advance refuses the reversal nothing destructive has
    -- run yet. (One transaction either way, but a function that fails before it
    -- deletes is easier to reason about than one that fails after.)
    v_reason := 'Payroll reopened' ||
                COALESCE(': ' || NULLIF(btrim(p_reason), ''), '');

    BEGIN
        FOR v_r IN
            SELECT r.poultryemployeeloanrepaymentid AS repayid,
                   r.poultrypayrolldeductionid      AS dedid,
                   COALESCE(l.loannumber, l.poultryemployeeloanid::text) AS loannumber,
                   btrim(s.firstname || ' ' || s.lastname) AS staffname
            FROM   poultryemployeeloanrepayments r
            JOIN   poultryemployeeloans l ON l.poultryemployeeloanid = r.poultryemployeeloanid
            JOIN   poultrystaff s ON s.poultrystaffid = r.poultrystaffid
            WHERE  r.farmid = p_farmid
              AND  r.poultrypayrollrunid = p_poultrypayrollrunid
              AND  r.sourcetype = 'Payroll'
              -- Already-reversed ones are left alone: reversing a reversal
              -- would put the deduction back on the advance.
              AND  r.status = 'Posted'
            ORDER  BY r.poultryemployeeloanrepaymentid
        LOOP
            v_ctxloan  := v_r.loannumber;
            v_ctxstaff := v_r.staffname;

            -- Appends a reversal; does not delete. TRUE is what unlocks a
            -- payroll-created repayment, and this is the only caller that
            -- passes it.
            PERFORM public.sppoultryemployeeloanrepayment_reverse(
                p_farmid       => p_farmid,
                p_poultryemployeeloanrepaymentid => v_r.repayid,
                p_reversedby   => p_reopenedby,
                p_reason       => v_reason,
                p_allowpayroll => TRUE);

            -- Editable again, and no longer claiming a repayment it does not
            -- have. The reverse link survives on the repayment row.
            IF v_r.dedid IS NOT NULL THEN
                UPDATE poultrypayrollitemdeductions
                SET    status = 'Draft',
                       poultryemployeeloanrepaymentid = NULL,
                       updatedby = p_reopenedby,
                       updatedat = (now() at time zone 'utc')
                WHERE  poultrypayrollitemdeductionid = v_r.dedid
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

    -- ---- 441: take back the wages this run kept as employee credit ---------
    -- Refused (by the reverse core) if the money has already been paid out:
    -- the farm cannot un-owe what it has already handed over.
    FOR v_c IN
        SELECT c.poultryemployeecreditid AS creditid,
               c.poultrypayrolldeductionid AS dedid,
               btrim(s.firstname || ' ' || s.lastname) AS staffname
        FROM   poultryemployeecredits c
        JOIN   poultrystaff s ON s.poultrystaffid = c.poultrystaffid
        WHERE  c.farmid = p_farmid
          AND  c.poultrypayrollrunid = p_poultrypayrollrunid
          AND  c.entrytype = 'PayrollSaving'
          AND  c.status = 'Posted'
        ORDER  BY c.poultryemployeecreditid
    LOOP
        BEGIN
            PERFORM public.fnpoultryemployeecredit_reverserow(
                p_farmid, v_c.creditid, v_reason, p_reopenedby);
        EXCEPTION WHEN OTHERS THEN
            RAISE EXCEPTION 'Payroll was not reopened. The wages kept for % could not be taken back: %',
                v_c.staffname, SQLERRM;
        END;
        IF v_c.dedid IS NOT NULL THEN
            UPDATE poultrypayrollitemdeductions
            SET    status = 'Draft',
                   poultryemployeecreditid = NULL,
                   updatedby = p_reopenedby,
                   updatedat = (now() at time zone 'utc')
            WHERE  poultrypayrollitemdeductionid = v_c.dedid
              AND  farmid = p_farmid;
        END IF;
    END LOOP;

    -- Other deductions posted nothing, so there is nothing to reverse -- but
    -- they must become editable again along with the rest of the run.
    UPDATE poultrypayrollitemdeductions
    SET    status = 'Draft',
           updatedby = p_reopenedby,
           updatedat = (now() at time zone 'utc')
    WHERE  poultrypayrollrunid = p_poultrypayrollrunid
      AND  farmid = p_farmid
      AND  status = 'Posted'
      AND  poultryemployeeloanrepaymentid IS NULL;

    -- Reverse any payroll cash transactions for this run (restore balances).
    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - t.net,
           updatedat = (now() at time zone 'utc')
    FROM (
        SELECT ct.poultrycashaccountid, SUM(ct.amount) AS net
        FROM   poultrycashtransactions ct
        WHERE  ct.sourcetype = 'Payroll' AND ct.sourceid = p_poultrypayrollrunid AND ct.farmid = p_farmid
        GROUP  BY ct.poultrycashaccountid
    ) t
    WHERE t.poultrycashaccountid = a.poultrycashaccountid
      AND a.farmid = p_farmid;
    DELETE FROM poultrycashtransactions ct
    WHERE ct.sourcetype = 'Payroll' AND ct.sourceid = p_poultrypayrollrunid AND ct.farmid = p_farmid;
    -- Remove the linked expense.
    DELETE FROM expense e
    WHERE e.sourcetype = 'Payroll' AND e.sourceid = p_poultrypayrollrunid AND e.farmid = v_farmguid;

    -- ---- 310: and the advance top-up 309 added ------------------------------
    -- Deleted rather than compensated, deliberately: it is removed the same way
    -- and at the same moment as the payroll expense it belongs to, so the two
    -- cannot end up disagreeing about whether this run's cost exists. It also
    -- moved no cash, so there is no balance to put back.
    DELETE FROM expense e
    WHERE e.sourcetype = 'PayrollEmployeeLoan'
      AND e.sourceid = p_poultrypayrollrunid
      AND e.farmid = v_farmguid;

    -- 441: and the kept-wages top-up, the same way.
    DELETE FROM expense e
    WHERE e.sourcetype = 'PayrollEmployeeCredit'
      AND e.sourceid = p_poultrypayrollrunid
      AND e.farmid = v_farmguid;

    UPDATE poultrypayrollruns r
    SET    status = 'Reopened', reopenedby = p_reopenedby, reopenedat = (now() at time zone 'utc'),
           reopenreason = p_reason, paidby = NULL, paidat = NULL, updatedat = (now() at time zone 'utc')
    WHERE  r.poultrypayrollrunid = p_poultrypayrollrunid AND r.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 9d. Cash Flow: splice in the employee credit arm.
-- (live body via pg_get_functiondef 2026-11-16; only the 441 lines added)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
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

    -- ---- 1. customer receipts, ONE row per payment (358) -------------------
    -- A payment (paymentgroupid) has one poultrypayments row per sale it pays.
    -- It is one receipt: one row here, whatever the number of sales.
    RETURN QUERY
    SELECT 'Receipt'::text,
           FALSE,
           MIN(p.poultrypaymentid),
           NULL::integer,
           NULL::text,
           MIN(p.paymentdate),
           'CashIn'::text,
           'CustomerPayment'::text,
           CASE WHEN COUNT(DISTINCT p.saleid) = 1 THEN MIN(p.saleid) END,
           FALSE,
           SUM(COALESCE(p.amount, 0))::numeric,
           concat_ws(' Â· ',
               CASE WHEN COUNT(DISTINCT p.saleid) = 1
                    THEN 'Sale ' || COALESCE(MIN(s.salegroupno), '#' || MIN(p.saleid)::text)
                    WHEN COUNT(p.saleid) = 0 AND COUNT(p.debtid) > 0 THEN 'Customer debt payment'   -- 369: debt, received
                    WHEN COUNT(p.saleid) = 0 THEN 'Customer advance'   -- 367: advance, received
                    ELSE COUNT(DISTINCT p.saleid)::text || ' sales' END,
               NULLIF(btrim(COALESCE(MIN(s.customername)::text,
                   (SELECT c.name::text FROM customer c
                    WHERE c.customerid = MIN(p.customerid) AND c.farmid = p_farmid))), ''),
               MIN(p.paymentnumber))::text,
           'OperatingIn'::text,
           MIN(p.createddate)
    FROM   poultrypayments p
    LEFT   JOIN sale s ON s.saleid = p.saleid AND s.farmid = p.farmid
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) <> 0
      -- 351: a REVERSED receipt still came in on its date; it goes back out
      -- on the reversal leg below, so the two net to zero and both show.
      AND  COALESCE(p.status, 'Posted') IN ('Posted', 'Reversed')
      -- 363: no cash behind an opening credit or a credit note.
      AND  COALESCE(p.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote')
      AND  p.paymentdate >= v_from
      AND  p.paymentdate <= v_to
    GROUP  BY COALESCE(p.paymentgroupid::text, 'row:' || p.poultrypaymentid::text);

    -- ---- 1b. (351) receipts reversed, on the business day of the reversal ----
    -- Money Out, but CONTRA-SALES: flowgroup OperatingIn with a negative amount.
    -- 358: one row per reversed payment, like the receipt it undoes.
    RETURN QUERY
    SELECT 'ReceiptReversal'::text,
           FALSE,
           MIN(p.poultrypaymentid),
           NULL::integer,
           NULL::text,
           fnpoultry_businessdateof(p_farmid, MIN(p.reversedat))::timestamp,
           'CashOut'::text,
           'PaymentReversal'::text,
           CASE WHEN COUNT(DISTINCT p.saleid) = 1 THEN MIN(p.saleid) END,
           FALSE,
           -SUM(COALESCE(p.amount, 0))::numeric,
           concat_ws(' Â· ',
               'Payment reversal' || COALESCE(' ' || MIN(p.paymentnumber), ''),
               CASE WHEN COUNT(DISTINCT p.saleid) = 1
                    THEN 'Sale ' || COALESCE(MIN(s.salegroupno), '#' || MIN(p.saleid)::text)
                    WHEN COUNT(p.saleid) = 0 AND COUNT(p.debtid) > 0 THEN 'Customer debt payment'   -- 369: debt, reversed
                    WHEN COUNT(p.saleid) = 0 THEN 'Customer advance'   -- 367: advance, reversed
                    ELSE COUNT(DISTINCT p.saleid)::text || ' sales' END)::text,
           'OperatingIn'::text,
           MIN(p.reversedat)
    FROM   poultrypayments p
    LEFT   JOIN sale s ON s.saleid = p.saleid AND s.farmid = p.farmid
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) <> 0
      AND  p.status = 'Reversed'
      AND  p.reversedat IS NOT NULL
      -- 363: an opening credit or credit note never came in, so never goes out.
      AND  COALESCE(p.sourcetype, '') NOT IN ('OpeningCredit', 'CreditNote')
      AND  fnpoultry_businessdateof(p_farmid, p.reversedat)::timestamp >= v_from
      AND  fnpoultry_businessdateof(p_farmid, p.reversedat)::timestamp <= v_to
    GROUP  BY COALESCE(p.paymentgroupid::text, 'row:' || p.poultrypaymentid::text),
              fnpoultry_businessdateof(p_farmid, p.reversedat);

    -- ---- 1c. (351) customer refunds: money handed back out of credit --------
    RETURN QUERY
    SELECT 'CustomerRefund'::text,
           FALSE,
           r.refundid,
           r.poultrycashaccountid,
           NULL::text,
           r.refunddate::timestamp,
           'CashOut'::text,
           'CustomerRefund'::text,
           r.refundid,
           FALSE,
           -r.amount::numeric,
           ('Customer refund ' || r.refundnumber || COALESCE(' - ' || NULLIF(btrim(c.name), ''), ''))::text,
           'OperatingIn'::text,
           r.createdat
    FROM   poultrycustomerrefunds r
    LEFT   JOIN customer c ON c.customerid = r.customerid AND c.farmid = r.farmid
    WHERE  lower(r.farmid) = lower(p_farmid)
      AND  r.status IN ('Posted', 'Reversed')   -- 367: a reversed refund keeps its Money Out
      AND  r.refunddate::timestamp >= v_from
      AND  r.refunddate::timestamp <= v_to;

    -- ---- 1d. (367) a refund reversed: the money came back ------------------
    RETURN QUERY
    SELECT 'CustomerRefundReversal'::text,
           FALSE,
           r.refundid,
           r.poultrycashaccountid,
           NULL::text,
           r.reversaldate::timestamp,
           'CashIn'::text,
           'CustomerRefundReversal'::text,
           r.refundid,
           FALSE,
           r.amount::numeric,
           ('Refund reversal ' || r.refundnumber || COALESCE(' - ' || NULLIF(btrim(c.name), ''), ''))::text,
           'OperatingIn'::text,
           r.reversedat
    FROM   poultrycustomerrefunds r
    LEFT   JOIN customer c ON c.customerid = r.customerid AND c.farmid = r.farmid
    WHERE  lower(r.farmid) = lower(p_farmid)
      AND  r.status = 'Reversed'
      AND  r.reversaldate IS NOT NULL
      AND  r.reversaldate::timestamp >= v_from
      AND  r.reversaldate::timestamp <= v_to;



    -- ---- 2. the part paid at the counter -----------------------------------

    -- Not every receipt becomes a payment row: a sale entered as already paid

    -- sets amountpaid directly. Counting the difference here picks those up

    -- without double counting the ones that DID create a row.

    --

    -- `paid` is honoured ahead of amountpaid because older rows were marked paid

    -- without amountpaid ever being populated -- the same rule CashController

    -- applies. Without it, historic cash sales vanish from the report.

    RETURN QUERY

    SELECT 'SaleResidual'::text,

           FALSE,

           s.saleid,

           s.poultrycashaccountid,

           NULL::text,

           -- sale.saledate is DATE while this function returns TIMESTAMP, so the

           -- cast is load-bearing: without it Postgres refuses the whole

           -- function with "structure of query does not match function result

           -- type". The live 235 carries this; the copy of 235 in this repo does

           -- NOT, so anyone reproducing that file inherits the fault.

           s.saledate::timestamp,

           'CashIn'::text,

           'Sale'::text,

           s.saleid,

           FALSE,

           v.residual,

           ('Sale #' || s.saleid::text ||

            COALESCE(' - ' || NULLIF(btrim(s.customername), ''), ''))::text,

           'OperatingIn'::text

           , s.createddate   -- 302: the entry time
    FROM   sale s

    CROSS  JOIN LATERAL (

        SELECT ROUND(

                   CASE WHEN COALESCE(s.paid, false)

                        THEN COALESCE(s.totalamount, 0)

                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),

                                   COALESCE(s.totalamount, 0))

                   END

                                  - fnpoultrysale_allocated(s.farmid::text, s.saleid)   -- 351: allocations, so applied credit is not fresh cash

               , 2) AS residual

    ) v

    WHERE  lower(s.farmid::text) = lower(p_farmid)

      -- Only a POSITIVE residual. A negative one means the payment rows already

      -- exceed what the sale records as paid, which is a data inconsistency; it

      -- is surfaced by this file's verification query rather than quietly

      -- subtracted from the day's income.

      AND  s.status = 'Posted'
      AND  v.residual > 0

      AND  s.saledate >= v_from

      AND  s.saledate <= v_to;



    -- ---- 3. money paid out when the expense was recorded --------------------

    -- Every kind of spending, because every module writes here. NonCash is still

    -- the only category-level exclusion: internal use posts it to record stock

    -- leaving without any money moving (migration 216).

    --

    -- What changed from 235 is the AMOUNT. It was e.amount -- the full bill.

    -- It is now what was actually paid at entry: the expense's resolved

    -- amountpaid, less anything a supplier payment has since covered (which the

    -- next arm reports on its own, later, date).

    --

    -- amountpaid IS NULL means paid in full, so a legacy row resolves straight

    -- back to e.amount and this arm returns exactly what 235 returned.

    RETURN QUERY

    SELECT 'Expense'::text,

           FALSE,

           e.expenseid,

           e.poultrycashaccountid,

           NULL::text,

           e.expensedate,

           'CashOut'::text,

           'Expense'::text,

           e.expenseid,

           FALSE,

           -v.paidatentry,

           COALESCE(NULLIF(btrim(e.description), ''), e.category)::text,

           'OperatingOut'::text

           , e.createddate   -- 302: the entry time
    FROM   expense e

    CROSS  JOIN LATERAL (

        SELECT GREATEST(

                   COALESCE(e.amountpaid, e.amount)

                 - COALESCE((SELECT SUM(sa.amountapplied)

                             FROM   supplierpaymentallocation sa

                             WHERE  sa.farmid = p_farmid

                               AND  sa.module = 'poultry'

                               AND  sa.status = 'Posted'

                               AND  sa.documenttype = 'Expense'

                               AND  sa.documentid = e.expenseid), 0)

               , 0)::numeric AS paidatentry

    ) v

    WHERE  lower(e.farmid::text) = lower(p_farmid)

      AND  v.paidatentry > 0

      AND  COALESCE(e.paymentmethod, '') <> 'NonCash'

      AND  e.expensedate >= v_from

      AND  e.expensedate <= v_to;



    -- ---- 3b. money paid out later, against a bill already recorded ----------

    -- A supplier payment settling an unpaid expense. It belongs to the day the

    -- money moved, not the day the bill was entered -- the same principle arm 1

    -- applies to customer receipts.

    --

    -- sourceid is the EXPENSE id so the row still drills through to the bill it

    -- paid (and so _detail's category join finds it); sourcerowid is the

    -- allocation id, which is what makes each row unique.

    --

    -- Only documenttype='Expense'. A payment against a raw-material purchase or

    -- a flock batch books its own expense row dated the payment date (224:414)

    -- and is already counted by arm 3; adding it here would double it.

    RETURN QUERY

    SELECT 'ExpensePayment'::text,

           FALSE,

           sa.allocationid,

           sp.poultrycashaccountid,

           NULL::text,

           sp.paymentdate,

           'CashOut'::text,

           'ExpensePayment'::text,

           sa.documentid,

           FALSE,

           -sa.amountapplied::numeric,

           ('Payment for expense #' || sa.documentid::text ||

            COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,

           'OperatingOut'::text

           , sa.createdat   -- 302: the entry time
    FROM   supplierpaymentallocation sa

    JOIN   poultrysupplierpayments sp

           ON  sp.poultrysupplierpaymentid = sa.paymentid

           AND sp.farmid = sa.farmid

    LEFT   JOIN supplier s

           ON  s.supplierid = sp.supplierid AND s.farmid = sp.farmid

    WHERE  sa.farmid = p_farmid

      AND  sa.module = 'poultry'

      AND  sa.status = 'Posted'

      AND  sa.documenttype = 'Expense'
      AND  NOT fnpoultrysupplier_iscreditkind(sp.sourcetype)   -- 370: 3b not a manual credit

      AND  sp.status = 'Posted'

      AND  sa.amountapplied <> 0

      AND  sp.paymentdate >= v_from

      AND  sp.paymentdate <= v_to;

    -- ---- 3c. (341) paid at entry for stock expensed when USED ---------------
    -- A deferred lot books no expense, so arm 3 never sees its cash. Only
    -- the part not covered by a supplier payment (that is 3d's).
    RETURN QUERY
    SELECT 'InventoryPurchase'::text,
           FALSE,
           pu.poultryrawmaterialpurchaseid,
           pu.poultrycashaccountid,
           NULL::text,
           pu.purchasedate,
           'CashOut'::text,
           'RawMaterialPurchase'::text,
           pu.poultryrawmaterialpurchaseid,
           FALSE,
           -v.paidatentry,
           ('Stock purchase: ' || COALESCE(i.itemname, 'item'))::text,
           'OperatingOut'::text,
           pu.createdat
    FROM   poultryrawmaterialpurchases pu
    LEFT   JOIN poultryrawmaterialitems i
           ON i.poultryrawmaterialitemid = pu.poultryrawmaterialitemid
    CROSS  JOIN LATERAL (
        SELECT GREATEST(
                   pu.amountpaid
                 - COALESCE((SELECT SUM(sa.amountapplied)
                             FROM   supplierpaymentallocation sa
                             WHERE  sa.farmid = p_farmid
                               AND  sa.module = 'poultry'
                               AND  sa.status = 'Posted'
                               AND  sa.documenttype = 'RawMaterialPurchase'
                               AND  sa.documentid = pu.poultryrawmaterialpurchaseid), 0)
               , 0)::numeric AS paidatentry
    ) v
    WHERE  pu.farmid = p_farmid
      AND  NOT fnpoultrycostrecognition_expenseatpurchase(pu.costrecognitionmethod)
      AND  pu.sourcefeedproductionbatchid IS NULL
      AND  COALESCE(pu.lotsource, '') <> 'ManualDeferredCost'   -- 371: a manual cost is not cash
      AND  v.paidatentry > 0
      AND  pu.purchasedate >= v_from
      AND  pu.purchasedate <= v_to;

    -- ---- 3d. (341) supplier payments for stock expensed when USED -----------
    RETURN QUERY
    SELECT 'InventoryPurchasePayment'::text,
           FALSE,
           sa.allocationid,
           sp.poultrycashaccountid,
           NULL::text,
           sp.paymentdate,
           'CashOut'::text,
           'RawMaterialPurchase'::text,
           sa.documentid,
           FALSE,
           -sa.amountapplied::numeric,
           ('Payment for stock purchase' ||
            COALESCE(': ' || NULLIF(btrim(i.itemname), ''), '') ||
            COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,
           'OperatingOut'::text,
           sa.createdat
    FROM   supplierpaymentallocation sa
    JOIN   poultrysupplierpayments sp
           ON  sp.poultrysupplierpaymentid = sa.paymentid
           AND sp.farmid = sa.farmid
    JOIN   poultryrawmaterialpurchases pu
           ON  pu.poultryrawmaterialpurchaseid = sa.documentid
           AND pu.farmid = sa.farmid
    LEFT   JOIN poultryrawmaterialitems i
           ON  i.poultryrawmaterialitemid = pu.poultryrawmaterialitemid
    LEFT   JOIN supplier s
           ON  s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sa.farmid = p_farmid
      AND  sa.module = 'poultry'
      AND  sa.status = 'Posted'
      AND  sa.documenttype = 'RawMaterialPurchase'
      AND  NOT fnpoultrysupplier_iscreditkind(sp.sourcetype)   -- 370: 3d not a manual credit
      AND  sp.status = 'Posted'
      AND  sa.amountapplied <> 0
      AND  NOT fnpoultrycostrecognition_expenseatpurchase(pu.costrecognitionmethod)
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;




    -- ---- 3e. (370) supplier advances: the part of a payment no other row shows --
    -- A payment's cash otherwise reaches Cash Flow only through what it was
    -- applied to (arms 3, 3b, 3d, 3f). What is left -- an advance, an
    -- overpayment, or credit later applied to a lot expensed at purchase or
    -- to birds (their cost is booked NonCash, so arm 3 skips it) -- is shown
    -- here, on the payment's own day. A payment therefore always totals its
    -- amount, whatever happens to its credit later.
    RETURN QUERY
    SELECT 'SupplierAdvance'::text,
           FALSE,
           sp.poultrysupplierpaymentid,
           sp.poultrycashaccountid,
           NULL::text,
           sp.paymentdate,
           'CashOut'::text,
           'SupplierAdvance'::text,
           sp.poultrysupplierpaymentid,
           FALSE,
           -v.amt,
           ((CASE WHEN v.hadallocs THEN 'Supplier overpayment' ELSE 'Supplier advance' END) ||
            COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,
           'OperatingOut'::text,
           sp.createdat
    FROM   poultrysupplierpayments sp
    LEFT   JOIN supplier s ON s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    CROSS  JOIN LATERAL (
        SELECT (sp.totalamount
                - COALESCE(SUM(sa.amountapplied), 0)
                + COALESCE(SUM(sa.amountapplied) FILTER (
                      WHERE sa.fromcredit
                        AND (sa.documenttype = 'FlockBatch'
                             OR (sa.documenttype = 'RawMaterialPurchase'
                                 AND fnpoultrycostrecognition_expenseatpurchase(
                                         (SELECT pu.costrecognitionmethod FROM poultryrawmaterialpurchases pu
                                          WHERE pu.poultryrawmaterialpurchaseid = sa.documentid AND pu.farmid = sa.farmid))))), 0)
               )::numeric AS amt,
               bool_or(NOT sa.fromcredit) IS TRUE AS hadallocs
        FROM   supplierpaymentallocation sa
        WHERE  sa.farmid = sp.farmid AND sa.module = 'poultry'
          AND  sa.paymentid = sp.poultrysupplierpaymentid AND sa.status = 'Posted'
    ) v
    WHERE  sp.farmid = p_farmid
      AND  sp.status = 'Posted'
      AND  NOT fnpoultrysupplier_iscreditkind(sp.sourcetype)
      AND  v.amt <> 0
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;

    -- ---- 3f. (370) payments of supplier debts, on the payment's day ----------
    RETURN QUERY
    SELECT 'SupplierDebtPayment'::text,
           FALSE,
           sa.allocationid,
           sp.poultrycashaccountid,
           NULL::text,
           sp.paymentdate,
           'CashOut'::text,
           'SupplierDebtPayment'::text,
           sa.documentid,
           FALSE,
           -sa.amountapplied::numeric,
           ('Payment of supplier debt ' || COALESCE(d.debtnumber, '#' || sa.documentid::text) ||
            COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,
           'OperatingOut'::text,
           sa.createdat
    FROM   supplierpaymentallocation sa
    JOIN   poultrysupplierpayments sp
           ON  sp.poultrysupplierpaymentid = sa.paymentid AND sp.farmid = sa.farmid
    LEFT   JOIN poultrysupplierdebts d ON d.debtid = sa.documentid AND d.farmid = sa.farmid
    LEFT   JOIN supplier s ON s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sa.farmid = p_farmid
      AND  sa.module = 'poultry'
      AND  sa.status = 'Posted'
      AND  sa.documenttype = 'SupplierDebt'
      AND  sp.status = 'Posted'
      AND  NOT fnpoultrysupplier_iscreditkind(sp.sourcetype)
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;

    -- ---- 3i. (376) a REVERSED supplier payment still went out on its day ---
    -- Every arm above reads Posted payments only, so a reversed payment used to
    -- vanish. Like a reversed customer receipt (1 / 1b): the payment keeps its
    -- Money Out on its own date -- one row, the full amount -- and the
    -- reversal is its own Money In (3j). The two net to zero and both show.
    RETURN QUERY
    SELECT 'SupplierPayment'::text,
           FALSE,
           sp.poultrysupplierpaymentid,
           sp.poultrycashaccountid,
           NULL::text,
           sp.paymentdate,
           'CashOut'::text,
           'PoultrySupplierPayment'::text,
           sp.poultrysupplierpaymentid,
           FALSE,
           -sp.totalamount::numeric,
           ('Supplier payment #' || sp.poultrysupplierpaymentid::text ||
            COALESCE(' - ' || NULLIF(btrim(s.name), ''), '') || ' (reversed later)')::text,
           'OperatingOut'::text,
           sp.createdat
    FROM   poultrysupplierpayments sp
    LEFT   JOIN supplier s ON s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  sp.status = 'Reversed'
      AND  NOT fnpoultrysupplier_iscreditkind(sp.sourcetype)
      AND  COALESCE(sp.totalamount, 0) <> 0
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;

    -- ---- 3j. (376) a supplier payment reversed: the money came back --------
    -- Money In on the business day of the reversal, against operating
    -- outflows (like a supplier refund, 3g).
    RETURN QUERY
    SELECT 'SupplierPaymentReversal'::text,
           FALSE,
           sp.poultrysupplierpaymentid,
           sp.poultrycashaccountid,
           NULL::text,
           fnpoultry_businessdateof(p_farmid, sp.reversedat)::timestamp,
           'CashIn'::text,
           'SupplierPaymentReversal'::text,
           sp.poultrysupplierpaymentid,
           FALSE,
           sp.totalamount::numeric,
           ('Supplier payment reversal #' || sp.poultrysupplierpaymentid::text ||
            COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,
           'OperatingOut'::text,
           sp.reversedat
    FROM   poultrysupplierpayments sp
    LEFT   JOIN supplier s ON s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sp.farmid = p_farmid
      AND  sp.status = 'Reversed'
      AND  sp.reversedat IS NOT NULL
      AND  NOT fnpoultrysupplier_iscreditkind(sp.sourcetype)
      AND  COALESCE(sp.totalamount, 0) <> 0
      AND  fnpoultry_businessdateof(p_farmid, sp.reversedat)::timestamp >= v_from
      AND  fnpoultry_businessdateof(p_farmid, sp.reversedat)::timestamp <= v_to;

    -- ---- 3g. (370) a supplier sends money back out of credit: Money In ------
    -- Kept when reversed; the reversal is its own Money Out (3h).
    RETURN QUERY
    SELECT 'SupplierRefund'::text,
           FALSE,
           r.refundid,
           r.poultrycashaccountid,
           NULL::text,
           r.refunddate::timestamp,
           'CashIn'::text,
           'SupplierRefund'::text,
           r.refundid,
           FALSE,
           r.amount::numeric,
           ('Supplier refund ' || r.refundnumber || COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,
           'OperatingOut'::text,
           r.createdat
    FROM   poultrysupplierrefunds r
    LEFT   JOIN supplier s ON s.supplierid = r.supplierid AND s.farmid = r.farmid
    WHERE  r.farmid = p_farmid
      AND  r.status IN ('Posted', 'Reversed')
      AND  r.refunddate::timestamp >= v_from
      AND  r.refunddate::timestamp <= v_to;

    -- ---- 3h. (370) a supplier refund reversed: Money Out --------------------
    RETURN QUERY
    SELECT 'SupplierRefundReversal'::text,
           FALSE,
           r.refundid,
           r.poultrycashaccountid,
           NULL::text,
           r.reversaldate::timestamp,
           'CashOut'::text,
           'SupplierRefundReversal'::text,
           r.refundid,
           FALSE,
           -r.amount::numeric,
           ('Supplier refund reversal ' || r.refundnumber || COALESCE(' - ' || NULLIF(btrim(s.name), ''), ''))::text,
           'OperatingOut'::text,
           r.reversedat
    FROM   poultrysupplierrefunds r
    LEFT   JOIN supplier s ON s.supplierid = r.supplierid AND s.farmid = r.farmid
    WHERE  r.farmid = p_farmid
      AND  r.status = 'Reversed'
      AND  r.reversaldate IS NOT NULL
      AND  r.reversaldate::timestamp >= v_from
      AND  r.reversaldate::timestamp <= v_to;

    -- ---- 4. owner money (253) ----------------------------------------------

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

    -- when cashadjustment is absent, so anything below it is skipped on a farm

    -- with no capital records.

    RETURN QUERY

    SELECT 'OwnerMoney'::text,

           FALSE,

           o.poultryownermoneyid,

           o.poultrycashaccountid,

           a.accountname::text,

           o.transactiondate,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'CashIn' ELSE 'CashOut' END::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END::text,

           o.poultryownermoneyid,

           FALSE,

           -- Stored positive; the sign is applied here, once.

           (CASE WHEN o.transactiontype = 'Contribution' THEN o.amount ELSE -o.amount END)::numeric,

           COALESCE(NULLIF(btrim(o.notes), ''),

                    NULLIF(btrim(o.ownername), ''),

                    CASE WHEN o.transactiontype = 'Contribution'

                         THEN 'Owner contribution' ELSE 'Owner draw' END)::text,

           CASE WHEN o.transactiontype = 'Contribution' THEN 'FinancingIn' ELSE 'FinancingOut' END::text

           , o.createdat   -- 302: the entry time
    FROM   poultryownermoney o

    LEFT   JOIN poultrycashaccounts a

           ON a.poultrycashaccountid = o.poultrycashaccountid

    WHERE  o.farmid = p_farmid

      AND  o.status = 'Posted'
      -- 296. A record backfilled from a Cash Flow adjustment has NO cash
      -- row of its own: the ADJUSTMENT is still the cash event, and the
      -- legacy adjustment arm below already reports it. Without this the
      -- same money is counted twice -- the trap 292 hit for loans.
      AND  o.sourceadjustmentid IS NULL

      AND  o.transactiondate >= v_from

      AND  o.transactiondate <= v_to;



    -- ---- 5. loans received (254) -------------------------------------------

    -- Borrowed money arriving. FINANCING: the business received it, it did not

    -- earn it, so it is money in and never revenue.

    --

    -- The AMOUNT RECEIVED, not the principal. A lender that withholds a fee

    -- pays out less than it lends, and only what arrived is cash in.

    RETURN QUERY

    SELECT 'Loan'::text,

           FALSE,

           l.poultryloanid,

           l.poultrycashaccountid,

           a.accountname::text,

           -- 256. loandate is a DATE, so this was always midnight and a loan

           -- recorded this afternoon sorted below everything else recorded

           -- today. Same rule as lib/utils/date-key.entryTimestamp: a loan

           -- dated TODAY carries the moment it was actually recorded, and a

           -- back-dated one keeps midnight, because nobody knows what time last

           -- Tuesday's disbursement landed.

           CASE WHEN l.loandate = l.createdat::date THEN l.createdat

                ELSE l.loandate::timestamp END,

           'CashIn'::text,

           'LoanReceived'::text,

           l.poultryloanid,

           FALSE,

           l.amountreceived::numeric,

           ('Loan received from ' || l.lendername)::text,

           'FinancingIn'::text

           , l.createdat   -- 302: the entry time
    FROM   poultryloans l

    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = l.poultrycashaccountid

    WHERE  l.farmid = p_farmid

      AND  l.amountreceived > 0

      -- 292. A loan converted from a Cash Flow adjustment has NO cash row of

      -- its own: the ADJUSTMENT is the cash event, and arm 8 below already

      -- reports it. Without this the same borrowing is money-in twice -- which

      -- is precisely what the stage check caught.

      AND  l.sourceadjustmentid IS NULL

      AND  l.status NOT IN ('Cancelled', 'Reversed', 'Draft')

      AND  l.loandate::timestamp >= v_from

      AND  l.loandate::timestamp <= v_to;



    -- ---- 6. loan repayments (254) ------------------------------------------

    -- The FULL payment leaves the account, so the full payment is money out --

    -- principal, interest and fees together.

    --

    -- This does NOT double count the interest and fee expenses those payments

    -- create: they are written paymentmethod = 'NonCash', and arm 3 above skips

    -- NonCash. The P&L reads the expense table directly and still counts them,

    -- which is the whole point -- cash out is 12,500, cost is 2,500.

    RETURN QUERY

    SELECT 'LoanPayment'::text,

           FALSE,

           p.poultryloanpaymentid,

           p.poultrycashaccountid,

           a.accountname::text,

           p.paymentdate,

           'CashOut'::text,

           'LoanRepayment'::text,

           p.poultryloanid,

           FALSE,

           -p.totalamount::numeric,

           ('Loan repayment to ' || l.lendername)::text,

           'FinancingOut'::text

           , p.createdat   -- 302: the entry time
    FROM   poultryloanpayments p

    JOIN   poultryloans l ON l.poultryloanid = p.poultryloanid

    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = p.poultrycashaccountid

    WHERE  p.farmid = p_farmid

      AND  p.status = 'Posted'

      AND  p.paymentdate >= v_from

      AND  p.paymentdate <= v_to;



    -- ---- 7. capital in and out (legacy cash adjustments) --------------------

    -- Owner injections, loans received, withdrawals. Financing, not operating:

    -- money the business received or returned rather than earned or spent.

    --

    -- MUST STAY LAST: it RETURNs early when the table is absent, and anything

    -- below it would be silently skipped on a farm without capital records.

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

        RETURN;                     -- no capital records; the four legs stand

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

               ca.amount::numeric,     -- already signed

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

    -- ---- 8. employee advances (305/307) ------------------------------------

    -- Disbursements out, manual repayments in, payroll deductions NOWHERE:

    -- a deduction moves no money, so it is not a cash event. The arms live in

    -- their own function, so this body is touched once and never again.

    RETURN QUERY

    SELECT * FROM public.sppoultryemployeeloan_cashflowrows(p_farmid, v_from, v_to);

    -- ---- 9. (435) birds sold before tracking: the money received ------
    RETURN QUERY
    SELECT * FROM public.sppoultryhistoricalsale_cashflowrows(p_farmid, v_from, v_to);

    -- ---- 10. (441) employee credit: money handed in, paid out, reversed -----
    -- Payroll savings move no cash (net pay is already lower), so they are not
    -- here at all.
    RETURN QUERY
    SELECT * FROM public.sppoultryemployeecredit_cashflowrows(p_farmid, v_from, v_to);


END;

$function$;

-- -----------------------------------------------------------------------------
-- 9e. Cash Flow detail: one bucket for employee credit.
-- (live body via pg_get_functiondef 2026-11-16; only the 441 lines added)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycashflow_detail(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text, category text, createdat timestamp without time zone)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid, r.accountname,
           r.transactiondate, r.transactiontype, r.sourcetype, r.sourceid,
           r.istransfer, r.amount, r.description, r.flowgroup,
           CASE
               WHEN r.rowsource IN ('Expense', 'ExpensePayment')
                   THEN COALESCE(NULLIF(btrim(e.category), ''), 'Uncategorised')
               WHEN r.rowsource IN ('Receipt', 'SaleResidual') THEN 'Sales'
               WHEN r.rowsource = 'ReceiptReversal' THEN 'Sale payment reversals'
               WHEN r.rowsource = 'CustomerRefund'  THEN 'Customer refunds'
               WHEN r.rowsource = 'CustomerRefundReversal' THEN 'Customer refunds'   -- 367: refund reversal
               WHEN r.rowsource = 'SupplierAdvance' THEN 'Supplier advances'   -- 370: supplier credit rows
               WHEN r.rowsource = 'SupplierDebtPayment' THEN 'Supplier debt payments'
               WHEN r.rowsource IN ('SupplierRefund', 'SupplierRefundReversal') THEN 'Supplier refunds'
               WHEN r.rowsource = 'HistoricalSale' THEN 'Bird sales (before tracking)'   -- 435
               WHEN r.rowsource IN ('EmployeeCredit', 'EmployeeCreditReversal') THEN 'Employee credit'   -- 441
               -- Capital keeps its own type as the bucket, so an owner injection
               -- never merges into a generic "Adjustment" slice.
               ELSE COALESCE(NULLIF(btrim(r.sourcetype), ''), 'Other')
           END::text,
           r.createdat              -- 302: the entry time
    FROM   public.sppoultrycashflow_rows(p_farmid, p_fromdate, p_todate) r
    -- LEFT, so an expense deleted after the fact still appears in the totals as
    -- Uncategorised rather than dropping out of them.
    LEFT   JOIN expense e
           ON  r.rowsource IN ('Expense', 'ExpensePayment')
           AND e.expenseid = r.sourceid
           AND lower(e.farmid::text) = lower(p_farmid);
$function$;

-- -----------------------------------------------------------------------------
-- 9f. Financial Activity type names.
-- (live body via pg_get_functiondef 2026-11-16; only the 441 lines added)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryfa_type(p_source text, p_costtype text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE p_source
        WHEN 'Sale'                          THEN 'Sale'
        WHEN 'CustomerPayment'               THEN 'Customer Payment'
        WHEN 'SupplierPayment'               THEN 'Supplier Payment'
        WHEN 'LoanReceived'                  THEN 'Loan Received'
        WHEN 'LoanPayment'                   THEN 'Loan Repayment'
        WHEN 'OwnerContribution'             THEN 'Owner Contribution'
        WHEN 'OwnerDraw'                     THEN 'Owner Draw'
        WHEN 'CashTransfer'                  THEN 'Cash Transfer'
        WHEN 'AssetDepreciation'             THEN 'Depreciation'
        WHEN 'CapitalAsset'                  THEN 'Capital Investment'
        WHEN 'CapitalAssetCost'              THEN 'Capital Investment'
        WHEN 'PoultryFeedConsumption'        THEN 'Feed Consumption'
        WHEN 'PoultryMedicationConsumption'  THEN 'Medication Consumption'
        WHEN 'PoultryInternalUsage'          THEN 'Internal Use'
        WHEN 'PoultryRawMaterialPurchase'    THEN 'Inventory Purchase'
        WHEN 'MainFlockBatch'                THEN 'Flock Purchase'
        WHEN 'Payroll'                       THEN 'Payroll'
        WHEN 'Adjustment'                    THEN 'Cash Adjustment'
        -- 305/307/308. Named for what they are to the BUSINESS rather than for
        -- the table they came from: an owner reads this column.
        WHEN 'EmployeeLoanDisbursement'      THEN 'Employee Advance'
        WHEN 'EmployeeLoanRepayment'         THEN 'Advance Repaid'
        WHEN 'EmployeeLoanPayrollRepayment'  THEN 'Advance Repaid from Wages'
        -- 441. Money the farm holds for staff.
        WHEN 'EmployeeCreditDeposit'         THEN 'Employee Credit Received'
        WHEN 'EmployeeCreditPayout'          THEN 'Employee Credit Paid Out'
        WHEN 'EmployeeCreditReversal'        THEN 'Employee Credit Reversal'
        WHEN 'PayrollEmployeeCredit'         THEN 'Payroll'
        WHEN 'EmployeeCreditWages'           THEN 'Payroll'
        ELSE CASE WHEN COALESCE(p_costtype,'') = 'CapitalAsset' THEN 'Capital Investment'
                  ELSE 'Expense' END
    END;
$function$;

-- -----------------------------------------------------------------------------
-- 9g. Financial Activity categories.
-- (live body via pg_get_functiondef 2026-11-16; only the 441 lines added)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryfa_category(p_source text, p_costtype text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE p_source
        WHEN 'Sale'                          THEN 'Sales'
        WHEN 'CustomerPayment'               THEN 'Customer Collections'
        WHEN 'SupplierPayment'               THEN 'Supplier Payment'
        WHEN 'LoanReceived'                  THEN 'Financing'
        WHEN 'LoanPayment'                   THEN 'Financing Cost'
        WHEN 'OwnerContribution'             THEN 'Owner Capital'
        WHEN 'OwnerDraw'                     THEN 'Owner Capital'
        WHEN 'CashTransfer'                  THEN 'Internal Transfer'
        WHEN 'AssetDepreciation'             THEN 'Depreciation'
        WHEN 'CapitalAsset'                  THEN 'Capital Investment'
        WHEN 'CapitalAssetCost'              THEN 'Capital Investment'
        WHEN 'PoultryFeedConsumption'        THEN 'Cost Recognition'
        WHEN 'PoultryMedicationConsumption'  THEN 'Cost Recognition'
        WHEN 'PoultryInternalUsage'          THEN 'Internal Use'
        WHEN 'PoultryRawMaterialPurchase'    THEN 'Inventory Purchase'
        WHEN 'MainFlockBatch'                THEN 'Inventory Purchase'
        WHEN 'Payroll'                       THEN 'Payroll'
        WHEN 'Adjustment'                    THEN 'Adjustment'
        -- One category for all three, so filtering by it tells the whole story
        -- of an advance: out, back in cash, and back through the wage.
        WHEN 'EmployeeLoanDisbursement'      THEN 'Employee Advance'
        WHEN 'EmployeeLoanRepayment'         THEN 'Employee Advance'
        WHEN 'EmployeeLoanPayrollRepayment'  THEN 'Employee Advance'
        -- 441. The cost is Payroll; the cash legs are Employee Credit.
        WHEN 'EmployeeCreditDeposit'         THEN 'Employee Credit'
        WHEN 'EmployeeCreditPayout'          THEN 'Employee Credit'
        WHEN 'EmployeeCreditReversal'        THEN 'Employee Credit'
        WHEN 'PayrollEmployeeCredit'         THEN 'Payroll'
        WHEN 'EmployeeCreditWages'           THEN 'Payroll'
        ELSE CASE WHEN COALESCE(p_costtype,'') = 'CapitalAsset' THEN 'Capital Investment'
                  ELSE 'Operating Expense' END
    END;
$function$;

-- -----------------------------------------------------------------------------
-- 9h. Financial Activity activity types.
-- (live body via pg_get_functiondef 2026-11-16; only the 441 lines added)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryfa_activitytype(p_source text, p_costtype text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        WHEN p_source IN ('LoanReceived', 'LoanPayment', 'Adjustment')        THEN 'Financing'
        WHEN p_source IN ('OwnerContribution', 'OwnerDraw')                   THEN 'Owner'
        -- Its own activity, deliberately not Financing. Financing here means
        -- money the BUSINESS raised; lending to a worker runs the other way,
        -- and filing it under Financing would put an advance and a bank loan in
        -- the same bucket. Not Operating either -- that is where the classifier
        -- puts costs, and an advance is not a cost.
        WHEN p_source IN ('EmployeeLoanDisbursement', 'EmployeeLoanRepayment',
                          'EmployeeLoanPayrollRepayment')                     THEN 'EmployeeLoan'
        -- 441. Settling money held for staff: not a cost, not financing.
        WHEN p_source IN ('EmployeeCreditDeposit', 'EmployeeCreditPayout',
                          'EmployeeCreditReversal')                           THEN 'EmployeeCredit'
        WHEN p_source IN ('CapitalAsset', 'CapitalAssetCost', 'AssetDepreciation')
             OR COALESCE(p_costtype,'') = 'CapitalAsset'                      THEN 'Capital'
        WHEN p_source IN ('PoultryFeedConsumption', 'PoultryMedicationConsumption',
                          'PoultryInternalUsage', 'PoultryRawMaterialPurchase',
                          'MainFlockBatch')                                   THEN 'Inventory'
        WHEN p_source = 'CashTransfer'                                        THEN 'Transfer'
        ELSE 'Operating'
    END;
$function$;

-- -----------------------------------------------------------------------------
-- 9i. Financial Activity: the Employee Credit liability position.
-- (live body via pg_get_functiondef 2026-11-16; only the 441 lines added)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryfa_positions(p_farmid text, p_from date, p_to date)
 RETURNS TABLE(eventkey text, positiontype text, positionname text, increaseamount numeric, decreaseamount numeric, explanation text)
 LANGUAGE sql
 STABLE
AS $function$
    -- Loan received: the debt the farm took on. The LIABILITY is the principal;
    -- the CASH was amountreceived, which is smaller when the lender withheld a
    -- fee. Two different numbers on purpose.
    SELECT 'Loan:' || l.poultryloanid,
           'LoanLiability',
           l.lendername::text,
           l.originalprincipal::numeric, 0::numeric,
           'Outstanding loan increased'
    FROM   poultryloans l
    WHERE  l.farmid = p_farmid
      AND  l.status NOT IN ('Cancelled', 'Reversed', 'Draft')
      AND  l.loandate >= p_from AND l.loandate <= p_to

    UNION ALL
    -- Loan repayment: only the PRINCIPAL reduces the debt. Interest and fees are
    -- the cost of borrowing and are already the expense leg of the same row.
    SELECT 'LoanPayment:' || p.poultryloanpaymentid,
           'LoanLiability',
           l.lendername::text,
           0::numeric, p.principalamount::numeric,
           'Outstanding loan reduced'
    FROM   poultryloanpayments p
    JOIN   poultryloans l ON l.poultryloanid = p.poultryloanid
    WHERE  p.farmid = p_farmid AND p.status = 'Posted'
      AND  p.principalamount > 0
      AND  p.paymentdate >= p_from::timestamp AND p.paymentdate < (p_to + 1)::timestamp

    UNION ALL
    SELECT 'OwnerMoney:' || o.poultryownermoneyid,
           'OwnerCapital',
           COALESCE(NULLIF(btrim(o.ownername), ''), 'Owner'),
           CASE WHEN o.transactiontype = 'Contribution' THEN o.amount ELSE 0 END::numeric,
           CASE WHEN o.transactiontype = 'Contribution' THEN 0 ELSE o.amount END::numeric,
           CASE WHEN o.transactiontype = 'Contribution'
                THEN 'Owner funding increased' ELSE 'Owner funding reduced' END
    FROM   poultryownermoney o
    WHERE  o.farmid = p_farmid AND o.status = 'Posted'
      AND  o.transactiondate >= p_from::timestamp AND o.transactiondate < (p_to + 1)::timestamp

    UNION ALL
    -- A collection settles a debt the customer already owed. No revenue: that
    -- was recognised when the sale happened.
    SELECT 'CustomerPayment:' || pp.poultrypaymentid,
           'CustomerReceivable',
           COALESCE(NULLIF(btrim(s.customername), ''), 'Customer'),
           0::numeric, pp.amount::numeric,
           'Customer debt reduced'
    FROM   poultrypayments pp
    LEFT   JOIN sale s ON s.saleid = pp.saleid
    WHERE  lower(pp.farmid::text) = lower(p_farmid)
      AND  COALESCE(pp.status, 'Posted') = 'Posted'
      AND  pp.amount <> 0
      AND  pp.saleid IS NOT NULL
      AND  pp.paymentdate >= p_from::timestamp AND pp.paymentdate < (p_to + 1)::timestamp

    UNION ALL
    -- 363: customer paid in advance (Deposit): credit held for them.
    SELECT 'CustomerPayment:' || pp.poultrypaymentid,
           'CustomerCredit',
           COALESCE(NULLIF(btrim(c.name), ''), 'Customer'),
           pp.amount::numeric, 0::numeric,
           'Customer paid in advance'
    FROM   poultrypayments pp
    LEFT   JOIN customer c ON c.customerid = pp.customerid AND c.farmid = pp.farmid
    WHERE  lower(pp.farmid::text) = lower(p_farmid)
      AND  pp.saleid IS NULL AND pp.sourcetype = 'Deposit'
      AND  COALESCE(pp.status, 'Posted') = 'Posted'
      AND  pp.amount <> 0
      AND  pp.paymentdate >= p_from::timestamp AND pp.paymentdate < (p_to + 1)::timestamp

    UNION ALL
    -- The unpaid part of a sale is money the customer now owes.
    SELECT 'Sale:' || s.saleid,
           'CustomerReceivable',
           COALESCE(NULLIF(btrim(s.customername), ''), 'Customer'),
           v.owed, 0::numeric,
           'Customer now owes this amount'
    FROM   sale s
    CROSS  JOIN LATERAL (
        SELECT ROUND(COALESCE(s.totalamount, 0)
                     - CASE WHEN COALESCE(s.paid, false) THEN COALESCE(s.totalamount, 0)
                            ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),
                                       COALESCE(s.totalamount, 0)) END, 2) AS owed
    ) v
    WHERE  lower(s.farmid::text) = lower(p_farmid)
      AND  s.status = 'Posted'
      AND  v.owed > 0
      AND  s.saledate >= p_from AND s.saledate <= p_to

    UNION ALL
    -- The unpaid part of a bill is money the farm now owes its supplier.
    SELECT 'Expense:' || e.expenseid,
           'SupplierPayable',
           COALESCE(NULLIF(btrim(s.name), ''), 'Supplier'),
           v.owed, 0::numeric,
           'Supplier is owed this amount'
    FROM   expense e
    LEFT   JOIN supplier s ON s.supplierid = e.supplierid
    CROSS  JOIN LATERAL (
        SELECT ROUND(GREATEST(COALESCE(e.amount, 0) - COALESCE(e.amountpaid, e.amount), 0), 2) AS owed
    ) v
    WHERE  lower(e.farmid::text) = lower(p_farmid)
      AND  v.owed > 0
      AND  e.expensedate >= p_from AND e.expensedate < (p_to + 1)

    UNION ALL
    -- Paying a supplier settles that debt. It is not a second expense.
    SELECT 'SupplierPayment:' || sa.allocationid,
           'SupplierPayable',
           COALESCE(NULLIF(btrim(s.name), ''), 'Supplier'),
           0::numeric, sa.amountapplied::numeric,
           'Supplier debt reduced'
    FROM   supplierpaymentallocation sa
    JOIN   poultrysupplierpayments sp
           ON sp.poultrysupplierpaymentid = sa.paymentid AND sp.farmid = sa.farmid
    LEFT   JOIN supplier s ON s.supplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sa.farmid = p_farmid AND sa.module = 'poultry'
      AND  sa.status = 'Posted' AND sp.status = 'Posted' AND sa.amountapplied <> 0
      AND  sp.paymentdate >= p_from::timestamp AND sp.paymentdate < (p_to + 1)::timestamp

    UNION ALL
    -- Stock bought, and stock consumed. Which of the two an item does at
    -- purchase is the farm's cost-recognition setting (261-268); this reads the
    -- classification rather than re-deciding it.
    SELECT 'Expense:' || e.expenseid,
           CASE WHEN e.costtype = 'CapitalAsset' THEN 'CapitalAsset'
                WHEN e.sourcetype = 'AssetDepreciation' THEN 'AccumulatedDepreciation'
                ELSE 'Inventory' END,
           CASE WHEN e.costtype = 'CapitalAsset' THEN COALESCE(NULLIF(btrim(e.description),''), 'Capital asset')
                WHEN e.sourcetype = 'AssetDepreciation' THEN COALESCE(NULLIF(btrim(e.description),''), 'Depreciation')
                ELSE COALESCE(NULLIF(btrim(e.category), ''), 'Inventory') END,
           CASE WHEN e.sourcetype IN ('PoultryFeedConsumption', 'PoultryMedicationConsumption',
                                      'PoultryInternalUsage')
                THEN 0 ELSE COALESCE(e.amount, 0) END::numeric,
           CASE WHEN e.sourcetype IN ('PoultryFeedConsumption', 'PoultryMedicationConsumption',
                                      'PoultryInternalUsage')
                THEN COALESCE(e.amount, 0) ELSE 0 END::numeric,
           CASE WHEN e.costtype = 'CapitalAsset'            THEN 'Capital asset acquired'
                WHEN e.sourcetype = 'AssetDepreciation'     THEN 'Asset book value reduced'
                WHEN e.sourcetype = 'PoultryFeedConsumption' THEN 'Feed stock consumed'
                WHEN e.sourcetype = 'PoultryMedicationConsumption' THEN 'Medication stock consumed'
                WHEN e.sourcetype = 'PoultryInternalUsage'  THEN 'Stock taken for internal use'
                ELSE 'Inventory value increased' END
    FROM   public.fnpoultrypl_expenselines(p_farmid, p_from, p_to) e
    WHERE  e.costtype = 'CapitalAsset'
       OR  e.sourcetype IN ('AssetDepreciation', 'PoultryFeedConsumption',
                            'PoultryMedicationConsumption', 'PoultryInternalUsage',
                            'PoultryRawMaterialPurchase', 'MainFlockBatch')

    UNION ALL
    -- Both legs of a transfer, which is the whole explanation of why the event
    -- shows no Money In and no Money Out: the money is still the farm's.
    SELECT 'CashTransfer:' || t.poultrycashtransferid,
           'Cash', COALESCE(fa.accountname::text, 'From account'),
           0::numeric, t.amount::numeric, 'Money left this account'
    FROM   poultrycashtransfers t
    LEFT   JOIN poultrycashaccounts fa ON fa.poultrycashaccountid = t.frompoultrycashaccountid
    WHERE  t.farmid = p_farmid AND t.status = 'Approved'
      AND  t.transferdate >= p_from::timestamp AND t.transferdate < (p_to + 1)::timestamp

    UNION ALL
    SELECT 'CashTransfer:' || t.poultrycashtransferid,
           'Cash', COALESCE(ta.accountname::text, 'To account'),
           t.amount::numeric, 0::numeric, 'Money arrived in this account'
    FROM   poultrycashtransfers t
    LEFT   JOIN poultrycashaccounts ta ON ta.poultrycashaccountid = t.topoultrycashaccountid
    WHERE  t.farmid = p_farmid AND t.status = 'Approved'
      AND  t.transferdate >= p_from::timestamp AND t.transferdate < (p_to + 1)::timestamp

    UNION ALL
    -- Employee advance handed over: the worker now owes the farm. The
    -- RECEIVABLE is everything repayable; the CASH that left was the principal
    -- only. Two different numbers on purpose, exactly as the loan arm above
    -- distinguishes originalprincipal from amountreceived -- interest is owed
    -- from day one and was never money that left the building.
    SELECT 'Cash:EmployeeLoan:' || l.poultryemployeeloanid,
           'EmployeeLoanReceivable',
           btrim(s.firstname || ' ' || s.lastname)::text,
           l.totalrepayable::numeric, 0::numeric,
           CASE WHEN l.interestamount > 0
                THEN 'Advance to staff, including interest owed'
                ELSE 'Advance to staff' END
    FROM   poultryemployeeloans l
    JOIN   poultrystaff s ON s.poultrystaffid = l.poultrystaffid
    WHERE  l.farmid = p_farmid
      AND  l.status NOT IN ('Draft', 'Cancelled', 'Reversed')
      AND  l.poultrycashaccountid IS NOT NULL
      -- The same date expression the cash arm uses, so the position lands on
      -- the event rather than beside it.
      AND  (CASE WHEN l.disbursementdate = l.createdat::date THEN l.createdat
                 ELSE l.disbursementdate::timestamp END) >= p_from::timestamp
      AND  (CASE WHEN l.disbursementdate = l.createdat::date THEN l.createdat
                 ELSE l.disbursementdate::timestamp END) <  (p_to + 1)::timestamp

    UNION ALL
    -- Repaid in cash. The WHOLE repayment reduces what is owed: unlike a
    -- company loan, where only principal touches the debt and interest is the
    -- cost of borrowing, here the interest was part of the receivable from the
    -- start, so recovering it reduces the receivable too.
    SELECT 'Cash:EmployeeLoanRepayment:' || r.poultryemployeeloanrepaymentid,
           'EmployeeLoanReceivable',
           btrim(s.firstname || ' ' || s.lastname)::text,
           0::numeric, r.amount::numeric,
           'Advance repaid by staff'
    FROM   poultryemployeeloanrepayments r
    JOIN   poultrystaff s ON s.poultrystaffid = r.poultrystaffid
    WHERE  r.farmid = p_farmid
      AND  r.status = 'Posted'
      AND  r.sourcetype <> 'Payroll'
      AND  r.repaymentdate >= p_from::timestamp
      AND  r.repaymentdate <  (p_to + 1)::timestamp

    UNION ALL
    -- Repaid by payroll deduction. Same reduction, no cash -- this is the
    -- position that leg E of fnpoultryfa_events exists to carry.
    SELECT 'EmployeeLoanPayrollRepayment:' || r.poultryemployeeloanrepaymentid,
           'EmployeeLoanReceivable',
           btrim(s.firstname || ' ' || s.lastname)::text,
           0::numeric, r.amount::numeric,
           'Advance repaid from wages'
    FROM   poultryemployeeloanrepayments r
    JOIN   poultrystaff s ON s.poultrystaffid = r.poultrystaffid
    WHERE  r.farmid = p_farmid
      AND  r.status = 'Posted'
      AND  r.sourcetype = 'Payroll'
      AND  r.repaymentdate >= p_from::timestamp
      AND  r.repaymentdate <  (p_to + 1)::timestamp

    UNION ALL
    -- 441. Employee credit: what the farm OWES its staff. Up when wages are
    -- kept or money is handed in, down when it is paid out.
    SELECT 'Cash:EmployeeCredit:' || c.poultryemployeecreditid,
           'EmployeeCreditLiability',
           btrim(s.firstname || ' ' || s.lastname)::text,
           CASE WHEN c.entrytype = 'Deposit' THEN c.amount ELSE 0 END::numeric,
           CASE WHEN c.entrytype = 'Payout'  THEN c.amount ELSE 0 END::numeric,
           CASE WHEN c.entrytype = 'Deposit' THEN 'Money handed in to keep'
                ELSE 'Employee credit paid out' END
    FROM   poultryemployeecredits c
    JOIN   poultrystaff s ON s.poultrystaffid = c.poultrystaffid
    WHERE  c.farmid = p_farmid
      AND  c.entrytype IN ('Deposit', 'Payout')
      AND  CASE WHEN c.entrydate = c.createdat::date THEN c.createdat ELSE c.entrydate::timestamp END
           >= p_from::timestamp
      AND  CASE WHEN c.entrydate = c.createdat::date THEN c.createdat ELSE c.entrydate::timestamp END
           <  (p_to + 1)::timestamp

    UNION ALL
    SELECT 'Cash:EmployeeCreditReversal:' || c.poultryemployeecreditid,
           'EmployeeCreditLiability',
           btrim(s.firstname || ' ' || s.lastname)::text,
           CASE WHEN c.entrytype = 'Payout'  THEN c.amount ELSE 0 END::numeric,
           CASE WHEN c.entrytype = 'Deposit' THEN c.amount ELSE 0 END::numeric,
           'Employee credit entry reversed'
    FROM   poultryemployeecredits c
    JOIN   poultrystaff s ON s.poultrystaffid = c.poultrystaffid
    WHERE  c.farmid = p_farmid
      AND  c.entrytype IN ('Deposit', 'Payout')
      AND  c.status = 'Reversed'
      AND  c.reversedat >= p_from::timestamp
      AND  c.reversedat <  (p_to + 1)::timestamp

    UNION ALL
    -- Wages kept: on the event of the expense that recognised them.
    SELECT 'Expense:' || e.expenseid,
           'EmployeeCreditLiability',
           btrim(s.firstname || ' ' || s.lastname)::text,
           c.amount::numeric, 0::numeric,
           'Wages kept as employee credit'
    FROM   poultryemployeecredits c
    JOIN   poultrystaff s ON s.poultrystaffid = c.poultrystaffid
    JOIN   expense e
           ON (c.entrytype = 'PayrollSaving' AND e.sourcetype = 'PayrollEmployeeCredit'
               AND e.sourceid = c.poultrypayrollrunid)
           OR (c.entrytype = 'WagesOwed' AND e.expenseid = c.expenseid)
    WHERE  c.farmid = p_farmid
      AND  lower(e.farmid::text) = lower(p_farmid)
      AND  c.entrytype IN ('PayrollSaving', 'WagesOwed')
      AND  c.status = 'Posted'
      AND  e.expensedate >= p_from AND e.expensedate < (p_to + 1);
$function$;

COMMIT;
