-- =============================================================================
-- 325_HotelEmployeeLoansPayroll.postgres.sql
--
-- Purpose
-- -------
-- Make Hotel employee loans and salary advances work end to end, and wire them
-- into Hotel payroll, Cash Flow and the P&L. Modelled on the Water/Poultry
-- design (313-317 / 305-310), adapted to the Hotel tables. HOTEL ONLY: no
-- Poultry, Water, Generic or Restaurant object is created or changed.
--
-- What was broken (migration 320)
-- -------------------------------
--   * Disburse and repay with a cash account crashed: they used
--     RETURNING hotelcashtransactionid, but the ledger's key is hotelcashtxnid.
--   * Reversing a disbursed loan crashed: 'EmployeeLoanDisbursementReversal'
--     is 32 characters and hotelcashtransactions.sourcetype is varchar(30).
--   * Disbursement moved principal + interest out of the cash account. Only the
--     principal leaves; interest is what the staff member owes on top.
--   * "No account" was accepted, so money could move with no ledger trace.
--   * Payroll had no link to loans at all.
--
-- The money rules (unchanged from Poultry/Water)
-- ----------------------------------------------
--   * An advance is NOT an expense and a repayment is NOT revenue. Disbursing
--     moves cash out; getting it back moves cash in. Interest repaid is income.
--   * A payroll deduction moves NO cash: the staff member simply receives less.
--     Approving the payroll run turns each deduction into a repayment. Marking
--     the run Paid posts the NET pay to the cash account. The P&L keeps wages at
--     GROSS pay, so the wage cost is not understated by the deduction.
--   * Every correction is a new reversing entry. Nothing posted is deleted.
--
-- Payroll lifecycle after this migration
-- --------------------------------------
--   Draft     -> lines and loan deductions can be edited
--   Approved  -> each loan deduction becomes a Payroll repayment (balance falls)
--   Paid      -> net pay leaves the run's cash account (or the Payroll account)
--   Approved  -> Draft      (Reopen: repayments reversed, deductions editable)
--   Draft/Approved -> Cancelled (repayments reversed, deductions Reversed)
--
-- Order: after 324. Idempotent: safe to run twice.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Schema
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.hotelemployeeloans
    ADD COLUMN IF NOT EXISTS loannumber                text,
    ADD COLUMN IF NOT EXISTS reversalcashtransactionid int;

-- Number existing loans per hotel, oldest first: EL-0001, EL-0002, ...
WITH numbered AS (
    SELECT hotelemployeeloanid,
           'EL-' || lpad(row_number() OVER (PARTITION BY farmid ORDER BY createdat, hotelemployeeloanid)::text, 4, '0') AS n
    FROM   public.hotelemployeeloans
)
UPDATE public.hotelemployeeloans l
SET    loannumber = n.n
FROM   numbered n
WHERE  n.hotelemployeeloanid = l.hotelemployeeloanid
  AND  l.loannumber IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelemployeeloans_farm_number
    ON public.hotelemployeeloans(farmid, loannumber);
CREATE INDEX IF NOT EXISTS ix_hotelemployeeloans_farm_staff_status
    ON public.hotelemployeeloans(farmid, hotelstaffid, status);

ALTER TABLE public.hotelemployeeloanrepayments
    ADD COLUMN IF NOT EXISTS hotelstaffid              int,
    ADD COLUMN IF NOT EXISTS hotelpayrollrunid         int,
    ADD COLUMN IF NOT EXISTS hotelpayrolldeductionid   int,
    ADD COLUMN IF NOT EXISTS reversalcashtransactionid int;

UPDATE public.hotelemployeeloanrepayments r
SET    hotelstaffid = l.hotelstaffid
FROM   public.hotelemployeeloans l
WHERE  l.hotelemployeeloanid = r.hotelemployeeloanid
  AND  r.hotelstaffid IS NULL;

-- A payroll deduction can be posted as a repayment only once at a time.
CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelrepayments_payrolldeduction_posted
    ON public.hotelemployeeloanrepayments(hotelpayrolldeductionid)
    WHERE status = 'Posted' AND hotelpayrolldeductionid IS NOT NULL;

-- Payroll lines: "other deductions" is what the user types (tax, penalties,
-- etc.); loan deductions are itemised in hotelpayrollitemdeductions. The line's
-- deductions column becomes their sum. Existing lines have no itemised rows,
-- so everything they already deduct is carried over as "other".
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name = 'hotelpayrollitems'
                     AND column_name = 'otherdeductions') THEN
        ALTER TABLE public.hotelpayrollitems
            ADD COLUMN otherdeductions numeric(12,2) NOT NULL DEFAULT 0;
        UPDATE public.hotelpayrollitems SET otherdeductions = deductions;
    END IF;
END $$;

ALTER TABLE public.hotelpayrollruns
    ADD COLUMN IF NOT EXISTS cashtransactionid int,
    ADD COLUMN IF NOT EXISTS reopenedby        text,
    ADD COLUMN IF NOT EXISTS reopenedat        timestamptz,
    ADD COLUMN IF NOT EXISTS reopenreason      text;

CREATE TABLE IF NOT EXISTS public.hotelpayrollitemdeductions (
    hotelpayrolldeductionid      serial        PRIMARY KEY,
    farmid                       text          NOT NULL,
    hotelpayrollrunid            int           NOT NULL REFERENCES public.hotelpayrollruns(hotelpayrollrunid) ON DELETE CASCADE,
    hotelpayrollitemid           int           NOT NULL REFERENCES public.hotelpayrollitems(hotelpayrollitemid) ON DELETE CASCADE,
    hotelstaffid                 int           NOT NULL,
    hotelemployeeloanid          int           NOT NULL REFERENCES public.hotelemployeeloans(hotelemployeeloanid),
    deductiontype                text          NOT NULL
                                 CHECK (deductiontype IN ('EmployeeLoanRepayment', 'SalaryAdvanceRepayment')),
    amount                       numeric(12,2) NOT NULL CHECK (amount > 0),
    status                       text          NOT NULL DEFAULT 'Draft'
                                 CHECK (status IN ('Draft', 'Posted', 'Reversed')),
    hotelemployeeloanrepaymentid int,
    createdby                    text,
    createdat                    timestamptz   NOT NULL DEFAULT now(),
    updatedat                    timestamptz
);

CREATE INDEX IF NOT EXISTS ix_hotelpayrolldeductions_run
    ON public.hotelpayrollitemdeductions(hotelpayrollrunid);
CREATE INDEX IF NOT EXISTS ix_hotelpayrolldeductions_loan_status
    ON public.hotelpayrollitemdeductions(hotelemployeeloanid, status);
-- One live deduction per loan per payroll line.
CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelpayrolldeductions_item_loan_live
    ON public.hotelpayrollitemdeductions(hotelpayrollitemid, hotelemployeeloanid)
    WHERE status IN ('Draft', 'Posted');

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Cash helpers (the one place a Hotel loan or payroll moves a balance)
-- ─────────────────────────────────────────────────────────────────────────────

-- Posts one ledger row and moves the cached balance by the same amount, under a
-- row lock on the account. Returns the ledger id (hotelcashtxnid).
CREATE OR REPLACE FUNCTION public.fnhotelcash_post(
    p_farmid         text,
    p_accountid      int,
    p_txntype        text,          -- 'Credit' (money in) | 'Debit' (money out)
    p_amount         numeric,
    p_description    text,
    p_reference      text,
    p_sourcetype     text,
    p_sourceid       int,
    p_by             text,
    p_txndate        timestamptz DEFAULT NULL,
    p_allowinactive  boolean     DEFAULT FALSE
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE
    v_bal    numeric;
    v_active boolean;
    v_id     int;
BEGIN
    IF p_accountid IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account the money moves through.';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'A cash movement must be more than zero.';
    END IF;
    IF p_txntype NOT IN ('Credit', 'Debit') THEN
        RAISE EXCEPTION 'Unknown cash movement type %.', p_txntype;
    END IF;
    IF length(p_sourcetype) > 30 THEN
        RAISE EXCEPTION 'Source type % is longer than the ledger allows (30).', p_sourcetype;
    END IF;

    SELECT a.currentbalance, a.isactive INTO v_bal, v_active
    FROM   public.hotelcashaccounts a
    WHERE  a.hotelcashaccountid = p_accountid AND a.farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That cash account does not belong to this hotel.';
    END IF;
    IF NOT v_active AND NOT p_allowinactive THEN
        RAISE EXCEPTION 'That cash account is inactive. Choose an active account.';
    END IF;

    v_bal := v_bal + CASE WHEN p_txntype = 'Credit' THEN p_amount ELSE -p_amount END;

    INSERT INTO public.hotelcashtransactions(
        farmid, hotelcashaccountid, txntype, amount, balanceafter,
        description, reference, sourcetype, sourceid, txndate, createdby)
    VALUES (
        p_farmid, p_accountid, p_txntype, p_amount, v_bal,
        left(p_description, 500), left(p_reference, 100), p_sourcetype, p_sourceid,
        COALESCE(p_txndate, now()), p_by)
    RETURNING hotelcashtxnid INTO v_id;

    UPDATE public.hotelcashaccounts
    SET    currentbalance = v_bal, updatedat = now()
    WHERE  hotelcashaccountid = p_accountid;

    RETURN v_id;
END;
$function$;

-- The hotel's account for a purpose ('Payroll', ...), created on first use with
-- the same name the API's HotelCashLedgerService gives it.
CREATE OR REPLACE FUNCTION public.fnhotelcash_purposeaccount(
    p_farmid  text,
    p_purpose text,
    p_name    text
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE v_id int;
BEGIN
    SELECT a.hotelcashaccountid INTO v_id
    FROM   public.hotelcashaccounts a
    WHERE  a.farmid = p_farmid AND a.purpose = p_purpose AND a.isactive
    ORDER  BY a.hotelcashaccountid
    LIMIT  1;

    IF v_id IS NULL THEN
        INSERT INTO public.hotelcashaccounts(farmid, accountname, accounttype, openingbalance, currentbalance, purpose)
        VALUES (p_farmid, p_name, 'Cash', 0, 0, p_purpose)
        RETURNING hotelcashaccountid INTO v_id;
    END IF;
    RETURN v_id;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Loans
-- ─────────────────────────────────────────────────────────────────────────────

-- Old overloads whose parameter lists change below.
DROP FUNCTION IF EXISTS public.sphotelemployeeloanrepayment_record(int, text, numeric, text, int, timestamptz, text, text, text);
DROP FUNCTION IF EXISTS public.sphotelemployeeloanrepayment_reverse(int, text, text, text);
-- Read functions whose result columns change (CREATE OR REPLACE cannot do that).
DROP FUNCTION IF EXISTS public.sphotelemployeeloan_getall(text, text, int);
DROP FUNCTION IF EXISTS public.sphotelemployeeloan_getbyid(int, text);
DROP FUNCTION IF EXISTS public.sphotelemployeeloanrepayment_getall(int, text);
DROP FUNCTION IF EXISTS public.sphotelemployeeloan_summary(text, timestamptz, timestamptz);

-- Create a loan as a Draft. Same parameters as 320, so the API call is unchanged.
CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_create(
    p_farmid           text,
    p_staffid          int,
    p_staffname        text DEFAULT NULL,
    p_loantype         text DEFAULT 'SalaryAdvance',
    p_principalamount  numeric DEFAULT 0,
    p_interestamount   numeric DEFAULT 0,
    p_repaymentmethod  text DEFAULT 'Cash',
    p_defaultdeduction numeric DEFAULT 0,
    p_expectedenddate  timestamptz DEFAULT NULL,
    p_reference        text DEFAULT NULL,
    p_notes            text DEFAULT NULL,
    p_createdby        text DEFAULT NULL,
    p_disbursenow      boolean DEFAULT false,
    p_cashaccountid    int DEFAULT NULL,
    p_disbursementdate timestamptz DEFAULT NULL
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id     int;
    v_total  numeric;
    v_sname  text;
    v_active boolean;
    v_next   int;
BEGIN
    SELECT btrim(s.firstname || ' ' || s.lastname), s.isactive INTO v_sname, v_active
    FROM   public.hotelstaff s
    WHERE  s.hotelstaffid = p_staffid AND s.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Choose a staff member of this hotel.';
    END IF;
    IF NOT v_active THEN
        RAISE EXCEPTION '% is marked inactive. Reactivate them before giving a loan or advance.', v_sname;
    END IF;

    IF p_loantype NOT IN ('SalaryAdvance', 'EmployeeLoan', 'OtherAdvance') THEN
        RAISE EXCEPTION 'Unknown loan type %.', p_loantype;
    END IF;
    IF p_repaymentmethod NOT IN ('PayrollDeduction', 'Cash', 'MoMo', 'Bank', 'Mixed', 'Other') THEN
        RAISE EXCEPTION 'Unknown repayment method %.', p_repaymentmethod;
    END IF;
    IF COALESCE(p_principalamount, 0) <= 0 THEN
        RAISE EXCEPTION 'The amount given must be more than zero.';
    END IF;
    IF COALESCE(p_interestamount, 0) < 0 THEN
        RAISE EXCEPTION 'Interest cannot be negative.';
    END IF;

    v_total := p_principalamount + COALESCE(p_interestamount, 0);

    IF COALESCE(p_defaultdeduction, 0) < 0 OR COALESCE(p_defaultdeduction, 0) > v_total THEN
        RAISE EXCEPTION 'The deduction per payroll must be between 0 and the total to repay (%).', v_total;
    END IF;
    IF p_repaymentmethod IN ('PayrollDeduction', 'Mixed') AND COALESCE(p_defaultdeduction, 0) = 0 THEN
        RAISE EXCEPTION 'Set how much to deduct from each payroll, or choose a different repayment method.';
    END IF;

    -- Per-hotel loan number, serialised so two users cannot get the same one.
    PERFORM pg_advisory_xact_lock(hashtext('hotelemployeeloan:' || p_farmid));
    SELECT COALESCE(MAX(NULLIF(regexp_replace(l.loannumber, '\D', '', 'g'), '')::int), 0) + 1 INTO v_next
    FROM   public.hotelemployeeloans l
    WHERE  l.farmid = p_farmid;

    INSERT INTO public.hotelemployeeloans(
        farmid, hotelstaffid, staffname, loannumber, loantype, status,
        principalamount, interestamount, totalrepayable, outstandingbalance,
        repaymentmethod, defaultpayrolldeduction, expectedenddate,
        reference, notes, createdby)
    VALUES (
        p_farmid, p_staffid, COALESCE(v_sname, p_staffname), 'EL-' || lpad(v_next::text, 4, '0'),
        p_loantype, 'Draft',
        p_principalamount, COALESCE(p_interestamount, 0), v_total, 0,
        p_repaymentmethod, COALESCE(p_defaultdeduction, 0), p_expectedenddate,
        NULLIF(btrim(p_reference), ''), NULLIF(btrim(p_notes), ''), p_createdby)
    RETURNING hotelemployeeloanid INTO v_id;

    IF p_disbursenow THEN
        PERFORM public.sphotelemployeeloan_disburse(v_id, p_farmid, p_cashaccountid, p_disbursementdate, p_reference, p_createdby);
    END IF;

    RETURN v_id;
END;
$function$;

-- Edit a loan. A Draft can change anything; once money has moved only the
-- repayment plan and the descriptive fields can change.
CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_update(
    p_loanid           int,
    p_farmid           text,
    p_loantype         text,
    p_principalamount  numeric,
    p_interestamount   numeric,
    p_repaymentmethod  text,
    p_defaultdeduction numeric,
    p_expectedenddate  timestamptz,
    p_reference        text,
    p_notes            text,
    p_by               text
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v   record;
    v_total numeric;
BEGIN
    SELECT * INTO v FROM public.hotelemployeeloans
    WHERE  hotelemployeeloanid = p_loanid AND farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found.'; END IF;
    IF v.status NOT IN ('Draft', 'Active', 'Paid') THEN
        RAISE EXCEPTION 'A % loan cannot be edited.', lower(v.status);
    END IF;
    IF p_loantype NOT IN ('SalaryAdvance', 'EmployeeLoan', 'OtherAdvance') THEN
        RAISE EXCEPTION 'Unknown loan type %.', p_loantype;
    END IF;
    IF p_repaymentmethod NOT IN ('PayrollDeduction', 'Cash', 'MoMo', 'Bank', 'Mixed', 'Other') THEN
        RAISE EXCEPTION 'Unknown repayment method %.', p_repaymentmethod;
    END IF;

    IF v.status = 'Draft' THEN
        IF COALESCE(p_principalamount, 0) <= 0 THEN RAISE EXCEPTION 'The amount given must be more than zero.'; END IF;
        IF COALESCE(p_interestamount, 0) < 0 THEN RAISE EXCEPTION 'Interest cannot be negative.'; END IF;
        v_total := p_principalamount + COALESCE(p_interestamount, 0);
    ELSE
        IF p_principalamount IS DISTINCT FROM v.principalamount
           OR COALESCE(p_interestamount, 0) IS DISTINCT FROM v.interestamount
           OR p_loantype IS DISTINCT FROM v.loantype THEN
            RAISE EXCEPTION 'The type and amounts can only change while the loan is a Draft. Reverse it and create a new one instead.';
        END IF;
        v_total := v.totalrepayable;
    END IF;

    IF COALESCE(p_defaultdeduction, 0) < 0 OR COALESCE(p_defaultdeduction, 0) > v_total THEN
        RAISE EXCEPTION 'The deduction per payroll must be between 0 and the total to repay (%).', v_total;
    END IF;
    IF p_repaymentmethod IN ('PayrollDeduction', 'Mixed') AND COALESCE(p_defaultdeduction, 0) = 0 THEN
        RAISE EXCEPTION 'Set how much to deduct from each payroll, or choose a different repayment method.';
    END IF;

    UPDATE public.hotelemployeeloans SET
        loantype                = p_loantype,
        principalamount         = CASE WHEN v.status = 'Draft' THEN p_principalamount ELSE principalamount END,
        interestamount          = CASE WHEN v.status = 'Draft' THEN COALESCE(p_interestamount, 0) ELSE interestamount END,
        totalrepayable          = v_total,
        repaymentmethod         = p_repaymentmethod,
        defaultpayrolldeduction = COALESCE(p_defaultdeduction, 0),
        expectedenddate         = p_expectedenddate,
        reference               = NULLIF(btrim(p_reference), ''),
        notes                   = NULLIF(btrim(p_notes), ''),
        updatedat               = now()
    WHERE hotelemployeeloanid = p_loanid AND farmid = p_farmid;
END;
$function$;

-- Disburse: Draft -> Active. The PRINCIPAL leaves the chosen cash account.
CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_disburse(
    p_loanid           int,
    p_farmid           text,
    p_cashaccountid    int DEFAULT NULL,
    p_disbursementdate timestamptz DEFAULT NULL,
    p_reference        text DEFAULT NULL,
    p_createdby        text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v      record;
    v_date timestamptz := COALESCE(p_disbursementdate, now());
    v_txn  int;
BEGIN
    SELECT * INTO v FROM public.hotelemployeeloans
    WHERE  hotelemployeeloanid = p_loanid AND farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found.'; END IF;
    IF v.status <> 'Draft' THEN RAISE EXCEPTION 'Only a Draft loan can be disbursed (this one is %).', v.status; END IF;
    IF p_cashaccountid IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account the money is paid from.';
    END IF;

    v_txn := public.fnhotelcash_post(
        p_farmid, p_cashaccountid, 'Debit', v.principalamount,
        'Staff ' || CASE WHEN v.loantype = 'SalaryAdvance' THEN 'advance' ELSE 'loan' END
            || ' ' || COALESCE(v.loannumber, '') || ' to ' || COALESCE(v.staffname, 'staff'),
        COALESCE(NULLIF(btrim(p_reference), ''), v.reference, v.loannumber),
        'EmployeeLoanDisbursement', p_loanid, p_createdby, v_date);

    UPDATE public.hotelemployeeloans SET
        status             = 'Active',
        disbursementdate   = v_date,
        hotelcashaccountid = p_cashaccountid,
        cashtransactionid  = v_txn,
        outstandingbalance = totalrepayable,
        reference          = COALESCE(NULLIF(btrim(p_reference), ''), reference),
        updatedat          = now()
    WHERE hotelemployeeloanid = p_loanid AND farmid = p_farmid;
END;
$function$;

-- Cancel: Draft only, no money has moved.
CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_cancel(
    p_loanid int,
    p_farmid text,
    p_reason text DEFAULT NULL,
    p_by     text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v_status text;
BEGIN
    SELECT status INTO v_status FROM public.hotelemployeeloans
    WHERE  hotelemployeeloanid = p_loanid AND farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found.'; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a Draft loan can be cancelled. A disbursed loan is reversed instead.';
    END IF;

    UPDATE public.hotelemployeeloans SET
        status = 'Cancelled', reversedreason = NULLIF(btrim(p_reason), ''), reversedby = p_by,
        reversedat = now(), outstandingbalance = 0, updatedat = now()
    WHERE hotelemployeeloanid = p_loanid AND farmid = p_farmid;
END;
$function$;

-- Reverse: the loan was a mistake. The principal goes back into the account it
-- came from. Refused while any repayment is still posted, or while a draft
-- payroll run is set to deduct from it.
CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_reverse(
    p_loanid int,
    p_farmid text,
    p_reason text DEFAULT NULL,
    p_by     text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v       record;
    v_n     int;
    v_runs  text;
    v_txn   int;
BEGIN
    SELECT * INTO v FROM public.hotelemployeeloans
    WHERE  hotelemployeeloanid = p_loanid AND farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found.'; END IF;
    IF v.status NOT IN ('Active', 'Paid') THEN
        RAISE EXCEPTION 'Only an Active or Paid loan can be reversed (this one is %).', v.status;
    END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for reversing the loan.';
    END IF;

    SELECT COUNT(*) INTO v_n FROM public.hotelemployeeloanrepayments
    WHERE  hotelemployeeloanid = p_loanid AND status = 'Posted';
    IF v_n > 0 THEN
        RAISE EXCEPTION 'This loan has % posted repayment(s). Reverse them first (payroll repayments are reversed by reopening or cancelling the payroll run).', v_n;
    END IF;

    SELECT string_agg(DISTINCT 'run #' || d.hotelpayrollrunid, ', ') INTO v_runs
    FROM   public.hotelpayrollitemdeductions d
    WHERE  d.hotelemployeeloanid = p_loanid AND d.status = 'Draft';
    IF v_runs IS NOT NULL THEN
        RAISE EXCEPTION 'A draft payroll (%) is set to deduct from this loan. Remove the deduction there first.', v_runs;
    END IF;

    IF v.cashtransactionid IS NOT NULL AND v.hotelcashaccountid IS NOT NULL THEN
        v_txn := public.fnhotelcash_post(
            p_farmid, v.hotelcashaccountid, 'Credit', v.principalamount,
            'REVERSAL of staff loan ' || COALESCE(v.loannumber, '') || ' to ' || COALESCE(v.staffname, 'staff'),
            COALESCE(v.reference, v.loannumber), 'EmployeeLoanReversal', p_loanid, p_by, now(), TRUE);
    END IF;

    UPDATE public.hotelemployeeloans SET
        status = 'Reversed', reversedreason = btrim(p_reason), reversedby = p_by, reversedat = now(),
        reversalcashtransactionid = v_txn, outstandingbalance = 0, updatedat = now()
    WHERE hotelemployeeloanid = p_loanid AND farmid = p_farmid;
END;
$function$;

-- Record a repayment. The single path for every source:
--   Cash / MoMo / Bank / Other -> money comes INTO the chosen account
--   Payroll                    -> no cash moves (net pay was already reduced);
--                                 only payroll approval calls this with a
--                                 deduction id.
-- Interest is repaid first, then principal.
CREATE OR REPLACE FUNCTION public.sphotelemployeeloanrepayment_record(
    p_loanid          int,
    p_farmid          text,
    p_amount          numeric,
    p_sourcetype      text DEFAULT 'Cash',
    p_cashaccountid   int DEFAULT NULL,
    p_repaymentdate   timestamptz DEFAULT NULL,
    p_reference       text DEFAULT NULL,
    p_notes           text DEFAULT NULL,
    p_createdby       text DEFAULT NULL,
    p_deductionid     int DEFAULT NULL,
    p_payrollrunid    int DEFAULT NULL
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE
    v          record;
    v_before   numeric;
    v_after    numeric;
    v_interest numeric;
    v_princ    numeric;
    v_repid    int;
    v_txn      int;
    v_date     timestamptz := COALESCE(p_repaymentdate, now());
BEGIN
    SELECT * INTO v FROM public.hotelemployeeloans
    WHERE  hotelemployeeloanid = p_loanid AND farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found.'; END IF;
    IF v.status <> 'Active' THEN
        RAISE EXCEPTION 'Loan % is % — only an Active loan takes repayments.', COALESCE(v.loannumber, '#' || p_loanid), v.status;
    END IF;
    IF p_sourcetype NOT IN ('Cash', 'MoMo', 'Bank', 'Other', 'Payroll') THEN
        RAISE EXCEPTION 'Unknown repayment source %.', p_sourcetype;
    END IF;
    IF COALESCE(p_amount, 0) <= 0 THEN RAISE EXCEPTION 'The repayment must be more than zero.'; END IF;
    IF p_amount > v.outstandingbalance THEN
        RAISE EXCEPTION 'The repayment (%) is more than % still owes on % (%).',
            p_amount, COALESCE(v.staffname, 'the staff member'), COALESCE(v.loannumber, 'this loan'), v.outstandingbalance;
    END IF;

    IF p_sourcetype = 'Payroll' THEN
        IF p_deductionid IS NULL THEN
            RAISE EXCEPTION 'Payroll repayments are created by approving a payroll run.';
        END IF;
        IF p_cashaccountid IS NOT NULL THEN
            RAISE EXCEPTION 'A payroll repayment moves no cash, so it takes no cash account.';
        END IF;
    ELSIF p_cashaccountid IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account the repayment is paid into.';
    END IF;

    v_before   := v.outstandingbalance;
    v_after    := v_before - p_amount;
    v_interest := LEAST(p_amount, GREATEST(v.interestamount - v.totalinterestrepaid, 0));
    v_princ    := p_amount - v_interest;

    INSERT INTO public.hotelemployeeloanrepayments(
        farmid, hotelemployeeloanid, hotelstaffid, amount, principalamount, interestamount,
        sourcetype, paymentmethod, hotelcashaccountid,
        balancebefore, balanceafter, repaymentdate, reference, notes, status, createdby,
        hotelpayrollrunid, hotelpayrolldeductionid)
    VALUES (
        p_farmid, p_loanid, v.hotelstaffid, p_amount, v_princ, v_interest,
        p_sourcetype, p_sourcetype, p_cashaccountid,
        v_before, v_after, v_date, NULLIF(btrim(p_reference), ''), NULLIF(btrim(p_notes), ''), 'Posted', p_createdby,
        p_payrollrunid, p_deductionid)
    RETURNING hotelemployeeloanrepaymentid INTO v_repid;

    IF p_sourcetype <> 'Payroll' THEN
        v_txn := public.fnhotelcash_post(
            p_farmid, p_cashaccountid, 'Credit', p_amount,
            'Staff loan repayment ' || COALESCE(v.loannumber, '') || ' from ' || COALESCE(v.staffname, 'staff'),
            COALESCE(NULLIF(btrim(p_reference), ''), v.loannumber),
            'EmployeeLoanRepayment', v_repid, p_createdby, v_date);
        UPDATE public.hotelemployeeloanrepayments SET cashtransactionid = v_txn
        WHERE  hotelemployeeloanrepaymentid = v_repid;
    END IF;

    UPDATE public.hotelemployeeloans SET
        totalprincipalrepaid = totalprincipalrepaid + v_princ,
        totalinterestrepaid  = totalinterestrepaid  + v_interest,
        outstandingbalance   = v_after,
        status               = CASE WHEN v_after <= 0 THEN 'Paid' ELSE 'Active' END,
        updatedat            = now()
    WHERE hotelemployeeloanid = p_loanid AND farmid = p_farmid;

    RETURN v_repid;
END;
$function$;

-- Reverse a repayment. Cash repayments put the money back out of the account
-- they came into. Payroll repayments can only be reversed by the payroll
-- functions (p_allowpayroll), so the payroll run and the loan never disagree.
CREATE OR REPLACE FUNCTION public.sphotelemployeeloanrepayment_reverse(
    p_repaymentid  int,
    p_farmid       text,
    p_reason       text DEFAULT NULL,
    p_by           text DEFAULT NULL,
    p_allowpayroll boolean DEFAULT FALSE
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    r     record;
    v     record;
    v_txn int;
BEGIN
    SELECT * INTO r FROM public.hotelemployeeloanrepayments
    WHERE  hotelemployeeloanrepaymentid = p_repaymentid AND farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Repayment not found.'; END IF;
    IF r.status <> 'Posted' THEN RAISE EXCEPTION 'This repayment is already reversed.'; END IF;
    IF r.sourcetype = 'Payroll' AND NOT p_allowpayroll THEN
        RAISE EXCEPTION 'A payroll repayment is reversed by reopening or cancelling its payroll run%.',
            COALESCE(' (#' || r.hotelpayrollrunid || ')', '');
    END IF;
    IF NOT p_allowpayroll AND NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for reversing the repayment.';
    END IF;

    SELECT * INTO v FROM public.hotelemployeeloans
    WHERE  hotelemployeeloanid = r.hotelemployeeloanid AND farmid = p_farmid
    FOR UPDATE;
    IF v.status NOT IN ('Active', 'Paid') THEN
        RAISE EXCEPTION 'Loan % is %, so its repayments cannot be reversed.', COALESCE(v.loannumber, ''), v.status;
    END IF;

    IF r.cashtransactionid IS NOT NULL AND r.hotelcashaccountid IS NOT NULL THEN
        v_txn := public.fnhotelcash_post(
            p_farmid, r.hotelcashaccountid, 'Debit', r.amount,
            'REVERSAL of staff loan repayment ' || COALESCE(v.loannumber, '') || ' from ' || COALESCE(v.staffname, 'staff'),
            r.reference, 'EmployeeLoanRepaymentReversal', p_repaymentid, p_by, now(), TRUE);
    END IF;

    UPDATE public.hotelemployeeloanrepayments SET
        status = 'Reversed', reversedby = p_by, reversedreason = NULLIF(btrim(p_reason), ''),
        reversedat = now(), reversalcashtransactionid = v_txn
    WHERE hotelemployeeloanrepaymentid = p_repaymentid;

    UPDATE public.hotelemployeeloans SET
        totalprincipalrepaid = totalprincipalrepaid - r.principalamount,
        totalinterestrepaid  = totalinterestrepaid  - r.interestamount,
        outstandingbalance   = LEAST(totalrepayable, outstandingbalance + r.amount),
        status               = 'Active',
        updatedat            = now()
    WHERE hotelemployeeloanid = r.hotelemployeeloanid AND farmid = p_farmid;
END;
$function$;

-- ── Reads ──────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_getall(
    p_farmid  text,
    p_status  text DEFAULT NULL,
    p_staffid int  DEFAULT NULL
) RETURNS TABLE (
    hotelemployeeloanid     int,
    farmid                  text,
    hotelstaffid            int,
    staffname               text,
    staffisactive           boolean,
    loannumber              text,
    loantype                text,
    status                  text,
    principalamount         numeric,
    interestamount          numeric,
    totalrepayable          numeric,
    totalprincipalrepaid    numeric,
    totalinterestrepaid     numeric,
    outstandingbalance      numeric,
    repaymentmethod         text,
    defaultpayrolldeduction numeric,
    disbursementdate        timestamptz,
    expectedenddate         timestamptz,
    hotelcashaccountid      int,
    cashaccountname         text,
    reference               text,
    notes                   text,
    createdby               text,
    createdat               timestamptz,
    updatedat               timestamptz,
    reversedby              text,
    reversedreason          text,
    reversedat              timestamptz,
    repaymentcount          int,
    lastrepaymentdate       timestamptz,
    draftpayrollclaims      numeric
)
LANGUAGE sql STABLE
AS $function$
    SELECT l.hotelemployeeloanid, l.farmid, l.hotelstaffid,
           COALESCE(NULLIF(btrim(s.firstname || ' ' || s.lastname), ''), l.staffname),
           COALESCE(s.isactive, FALSE),
           l.loannumber, l.loantype, l.status,
           l.principalamount, l.interestamount, l.totalrepayable,
           l.totalprincipalrepaid, l.totalinterestrepaid, l.outstandingbalance,
           l.repaymentmethod, l.defaultpayrolldeduction,
           l.disbursementdate, l.expectedenddate, l.hotelcashaccountid,
           a.accountname::text,
           l.reference, l.notes, l.createdby, l.createdat, l.updatedat,
           l.reversedby, l.reversedreason, l.reversedat,
           COALESCE(rp.n, 0)::int, rp.lastdate,
           COALESCE(dd.claims, 0)::numeric
    FROM   public.hotelemployeeloans l
    LEFT   JOIN public.hotelstaff s
           ON  s.hotelstaffid = l.hotelstaffid AND s.farmid = l.farmid
    LEFT   JOIN public.hotelcashaccounts a
           ON  a.hotelcashaccountid = l.hotelcashaccountid AND a.farmid = l.farmid
    LEFT   JOIN LATERAL (
               SELECT COUNT(*) AS n, MAX(r.repaymentdate) AS lastdate
               FROM   public.hotelemployeeloanrepayments r
               WHERE  r.hotelemployeeloanid = l.hotelemployeeloanid AND r.status = 'Posted'
           ) rp ON TRUE
    LEFT   JOIN LATERAL (
               SELECT SUM(d.amount) AS claims
               FROM   public.hotelpayrollitemdeductions d
               WHERE  d.hotelemployeeloanid = l.hotelemployeeloanid AND d.status = 'Draft'
           ) dd ON TRUE
    WHERE  l.farmid = p_farmid
      AND  (p_status  IS NULL OR l.status = p_status)
      AND  (p_staffid IS NULL OR l.hotelstaffid = p_staffid)
    ORDER  BY l.createdat DESC, l.hotelemployeeloanid DESC;
$function$;

-- Same columns as getall, one loan.
CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_getbyid(
    p_loanid int,
    p_farmid text
) RETURNS TABLE (
    hotelemployeeloanid     int,
    farmid                  text,
    hotelstaffid            int,
    staffname               text,
    staffisactive           boolean,
    loannumber              text,
    loantype                text,
    status                  text,
    principalamount         numeric,
    interestamount          numeric,
    totalrepayable          numeric,
    totalprincipalrepaid    numeric,
    totalinterestrepaid     numeric,
    outstandingbalance      numeric,
    repaymentmethod         text,
    defaultpayrolldeduction numeric,
    disbursementdate        timestamptz,
    expectedenddate         timestamptz,
    hotelcashaccountid      int,
    cashaccountname         text,
    reference               text,
    notes                   text,
    createdby               text,
    createdat               timestamptz,
    updatedat               timestamptz,
    reversedby              text,
    reversedreason          text,
    reversedat              timestamptz,
    repaymentcount          int,
    lastrepaymentdate       timestamptz,
    draftpayrollclaims      numeric
)
LANGUAGE sql STABLE
AS $function$
    SELECT g.* FROM public.sphotelemployeeloan_getall(p_farmid, NULL, NULL) g
    WHERE  g.hotelemployeeloanid = p_loanid;
$function$;

-- Repayment history for one loan (p_loanid) or for the whole hotel (NULL),
-- including reversed rows, oldest first.
CREATE OR REPLACE FUNCTION public.sphotelemployeeloanrepayment_getall(
    p_loanid int,
    p_farmid text
) RETURNS TABLE (
    hotelemployeeloanrepaymentid int,
    farmid                  text,
    hotelemployeeloanid     int,
    loannumber              text,
    hotelstaffid            int,
    staffname               text,
    amount                  numeric,
    principalamount         numeric,
    interestamount          numeric,
    sourcetype              text,
    paymentmethod           text,
    hotelcashaccountid      int,
    cashaccountname         text,
    cashtransactionid       int,
    hotelpayrollrunid       int,
    payrollperiod           text,
    balancebefore           numeric,
    balanceafter            numeric,
    repaymentdate           timestamptz,
    reference               text,
    notes                   text,
    status                  text,
    createdby               text,
    createdat               timestamptz,
    reversedby              text,
    reversedreason          text,
    reversedat              timestamptz
)
LANGUAGE sql STABLE
AS $function$
    SELECT r.hotelemployeeloanrepaymentid, r.farmid, r.hotelemployeeloanid, l.loannumber,
           l.hotelstaffid, l.staffname,
           r.amount, r.principalamount, r.interestamount,
           r.sourcetype, r.paymentmethod, r.hotelcashaccountid, a.accountname::text,
           r.cashtransactionid, r.hotelpayrollrunid,
           CASE WHEN pr.hotelpayrollrunid IS NOT NULL
                THEN to_char(pr.periodstart, 'DD Mon') || ' – ' || to_char(pr.periodend, 'DD Mon YYYY') END,
           r.balancebefore, r.balanceafter, r.repaymentdate,
           r.reference, r.notes, r.status, r.createdby, r.createdat,
           r.reversedby, r.reversedreason, r.reversedat
    FROM   public.hotelemployeeloanrepayments r
    JOIN   public.hotelemployeeloans l ON l.hotelemployeeloanid = r.hotelemployeeloanid
    LEFT   JOIN public.hotelcashaccounts a
           ON  a.hotelcashaccountid = r.hotelcashaccountid AND a.farmid = r.farmid
    LEFT   JOIN public.hotelpayrollruns pr ON pr.hotelpayrollrunid = r.hotelpayrollrunid
    WHERE  r.farmid = p_farmid
      AND  (p_loanid IS NULL OR r.hotelemployeeloanid = p_loanid)
    ORDER  BY r.repaymentdate, r.hotelemployeeloanrepaymentid;
$function$;

-- The cards on the loans page. Disbursed is PRINCIPAL; repaid and interest are
-- from posted repayments; the period (optional) filters the flows, not the
-- balances.
CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_summary(
    p_farmid   text,
    p_fromdate timestamptz DEFAULT NULL,
    p_todate   timestamptz DEFAULT NULL
) RETURNS TABLE (
    totaloutstanding    numeric,
    totaldisbursed      numeric,
    totalrepaid         numeric,
    activecount         int,
    staffwithloans      int,
    draftcount          int,
    paidcount           int,
    interestearned      numeric,
    repaidviapayroll    numeric,
    draftpayrollclaims  numeric
)
LANGUAGE sql STABLE
AS $function$
    SELECT
        COALESCE((SELECT SUM(l.outstandingbalance) FROM public.hotelemployeeloans l
                  WHERE l.farmid = p_farmid AND l.status = 'Active'), 0),
        COALESCE((SELECT SUM(l.principalamount) FROM public.hotelemployeeloans l
                  WHERE l.farmid = p_farmid AND l.status IN ('Active', 'Paid')
                    AND (p_fromdate IS NULL OR l.disbursementdate >= p_fromdate)
                    AND (p_todate   IS NULL OR l.disbursementdate <= p_todate)), 0),
        COALESCE((SELECT SUM(r.amount) FROM public.hotelemployeeloanrepayments r
                  WHERE r.farmid = p_farmid AND r.status = 'Posted'
                    AND (p_fromdate IS NULL OR r.repaymentdate >= p_fromdate)
                    AND (p_todate   IS NULL OR r.repaymentdate <= p_todate)), 0),
        (SELECT COUNT(*) FROM public.hotelemployeeloans l WHERE l.farmid = p_farmid AND l.status = 'Active')::int,
        (SELECT COUNT(DISTINCT l.hotelstaffid) FROM public.hotelemployeeloans l WHERE l.farmid = p_farmid AND l.status = 'Active')::int,
        (SELECT COUNT(*) FROM public.hotelemployeeloans l WHERE l.farmid = p_farmid AND l.status = 'Draft')::int,
        (SELECT COUNT(*) FROM public.hotelemployeeloans l WHERE l.farmid = p_farmid AND l.status = 'Paid')::int,
        COALESCE((SELECT SUM(r.interestamount) FROM public.hotelemployeeloanrepayments r
                  WHERE r.farmid = p_farmid AND r.status = 'Posted'
                    AND (p_fromdate IS NULL OR r.repaymentdate >= p_fromdate)
                    AND (p_todate   IS NULL OR r.repaymentdate <= p_todate)), 0),
        COALESCE((SELECT SUM(r.amount) FROM public.hotelemployeeloanrepayments r
                  WHERE r.farmid = p_farmid AND r.status = 'Posted' AND r.sourcetype = 'Payroll'
                    AND (p_fromdate IS NULL OR r.repaymentdate >= p_fromdate)
                    AND (p_todate   IS NULL OR r.repaymentdate <= p_todate)), 0),
        COALESCE((SELECT SUM(d.amount) FROM public.hotelpayrollitemdeductions d
                  WHERE d.farmid = p_farmid AND d.status = 'Draft'), 0);
$function$;

-- A staff member's open loans, for the payroll screen: what they owe, what
-- other draft payroll lines already claim, and the suggested deduction.
CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_eligible(
    p_farmid        text,
    p_staffid       int,
    p_excludeitemid int DEFAULT NULL
) RETURNS TABLE (
    hotelemployeeloanid     int,
    loannumber              text,
    loantype                text,
    repaymentmethod         text,
    outstandingbalance      numeric,
    defaultpayrolldeduction numeric,
    claimedelsewhere        numeric,
    available               numeric,
    suggesteddeduction      numeric,
    currentdeduction        numeric
)
LANGUAGE sql STABLE
AS $function$
    WITH base AS (
        SELECT l.hotelemployeeloanid, l.loannumber, l.loantype, l.repaymentmethod,
               l.outstandingbalance, l.defaultpayrolldeduction, l.disbursementdate,
               COALESCE((SELECT SUM(d.amount) FROM public.hotelpayrollitemdeductions d
                         WHERE d.hotelemployeeloanid = l.hotelemployeeloanid AND d.status = 'Draft'
                           AND (p_excludeitemid IS NULL OR d.hotelpayrollitemid <> p_excludeitemid)), 0) AS other,
               COALESCE((SELECT SUM(d.amount) FROM public.hotelpayrollitemdeductions d
                         WHERE d.hotelemployeeloanid = l.hotelemployeeloanid AND d.status = 'Draft'
                           AND d.hotelpayrollitemid = p_excludeitemid), 0) AS cur
        FROM   public.hotelemployeeloans l
        WHERE  l.farmid = p_farmid AND l.hotelstaffid = p_staffid
          AND  l.status = 'Active' AND l.outstandingbalance > 0
    )
    SELECT b.hotelemployeeloanid, b.loannumber, b.loantype, b.repaymentmethod,
           b.outstandingbalance, b.defaultpayrolldeduction, b.other,
           GREATEST(b.outstandingbalance - b.other, 0),
           CASE WHEN b.repaymentmethod IN ('PayrollDeduction', 'Mixed')
                THEN LEAST(b.defaultpayrolldeduction, GREATEST(b.outstandingbalance - b.other, 0))
                ELSE 0 END,
           b.cur
    FROM   base b
    ORDER  BY b.disbursementdate, b.hotelemployeeloanid;
$function$;

-- Per staff member: what they owe now, and what moved in the period. Feeds the
-- Staff page column and the "Staff Loans & Advances" report.
CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_staffreport(
    p_farmid   text,
    p_fromdate timestamptz DEFAULT NULL,
    p_todate   timestamptz DEFAULT NULL
) RETURNS TABLE (
    hotelstaffid        int,
    staffname           text,
    department          text,
    staffisactive       boolean,
    activeloans         int,
    outstanding         numeric,
    disbursedinperiod   numeric,
    repaidcashinperiod  numeric,
    repaidpayrollinperiod numeric,
    interestinperiod    numeric,
    lastrepaymentdate   timestamptz,
    totalever           numeric
)
LANGUAGE sql STABLE
AS $function$
    WITH staff_with_loans AS (
        SELECT DISTINCT l.hotelstaffid
        FROM   public.hotelemployeeloans l
        WHERE  l.farmid = p_farmid AND l.status IN ('Active', 'Paid')
    )
    SELECT sw.hotelstaffid,
           COALESCE(NULLIF(btrim(s.firstname || ' ' || s.lastname), ''),
                    (SELECT l.staffname FROM public.hotelemployeeloans l
                     WHERE l.farmid = p_farmid AND l.hotelstaffid = sw.hotelstaffid LIMIT 1),
                    'Staff #' || sw.hotelstaffid),
           s.department::text,
           COALESCE(s.isactive, FALSE),
           (SELECT COUNT(*) FROM public.hotelemployeeloans l
            WHERE l.farmid = p_farmid AND l.hotelstaffid = sw.hotelstaffid AND l.status = 'Active')::int,
           COALESCE((SELECT SUM(l.outstandingbalance) FROM public.hotelemployeeloans l
                     WHERE l.farmid = p_farmid AND l.hotelstaffid = sw.hotelstaffid AND l.status = 'Active'), 0),
           COALESCE((SELECT SUM(l.principalamount) FROM public.hotelemployeeloans l
                     WHERE l.farmid = p_farmid AND l.hotelstaffid = sw.hotelstaffid AND l.status IN ('Active', 'Paid')
                       AND (p_fromdate IS NULL OR l.disbursementdate >= p_fromdate)
                       AND (p_todate   IS NULL OR l.disbursementdate <= p_todate)), 0),
           COALESCE((SELECT SUM(r.amount) FROM public.hotelemployeeloanrepayments r
                     WHERE r.farmid = p_farmid AND r.hotelstaffid = sw.hotelstaffid AND r.status = 'Posted'
                       AND r.sourcetype <> 'Payroll'
                       AND (p_fromdate IS NULL OR r.repaymentdate >= p_fromdate)
                       AND (p_todate   IS NULL OR r.repaymentdate <= p_todate)), 0),
           COALESCE((SELECT SUM(r.amount) FROM public.hotelemployeeloanrepayments r
                     WHERE r.farmid = p_farmid AND r.hotelstaffid = sw.hotelstaffid AND r.status = 'Posted'
                       AND r.sourcetype = 'Payroll'
                       AND (p_fromdate IS NULL OR r.repaymentdate >= p_fromdate)
                       AND (p_todate   IS NULL OR r.repaymentdate <= p_todate)), 0),
           COALESCE((SELECT SUM(r.interestamount) FROM public.hotelemployeeloanrepayments r
                     WHERE r.farmid = p_farmid AND r.hotelstaffid = sw.hotelstaffid AND r.status = 'Posted'
                       AND (p_fromdate IS NULL OR r.repaymentdate >= p_fromdate)
                       AND (p_todate   IS NULL OR r.repaymentdate <= p_todate)), 0),
           (SELECT MAX(r.repaymentdate) FROM public.hotelemployeeloanrepayments r
            WHERE r.farmid = p_farmid AND r.hotelstaffid = sw.hotelstaffid AND r.status = 'Posted'),
           COALESCE((SELECT SUM(l.principalamount) FROM public.hotelemployeeloans l
                     WHERE l.farmid = p_farmid AND l.hotelstaffid = sw.hotelstaffid AND l.status IN ('Active', 'Paid')), 0)
    FROM   staff_with_loans sw
    LEFT   JOIN public.hotelstaff s ON s.hotelstaffid = sw.hotelstaffid AND s.farmid = p_farmid
    ORDER  BY 6 DESC, 2;
$function$;

-- A staff member with an open loan cannot be deleted: the loan would be left
-- pointing at nobody and payroll could never collect it.
CREATE OR REPLACE FUNCTION public.trghotelstaff_openloanguard()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE v_n int;
BEGIN
    SELECT COUNT(*) INTO v_n FROM public.hotelemployeeloans
    WHERE  farmid = OLD.farmid AND hotelstaffid = OLD.hotelstaffid AND status IN ('Draft', 'Active');
    IF v_n > 0 THEN
        RAISE EXCEPTION '% % has % open loan(s) or advance(s). Settle, cancel or reverse them first, or mark the staff member inactive instead.',
            OLD.firstname, OLD.lastname, v_n;
    END IF;
    RETURN OLD;
END;
$function$;

DROP TRIGGER IF EXISTS trghotelstaff_openloanguard ON public.hotelstaff;
CREATE TRIGGER trghotelstaff_openloanguard
    BEFORE DELETE ON public.hotelstaff
    FOR EACH ROW EXECUTE FUNCTION public.trghotelstaff_openloanguard();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Payroll
-- ─────────────────────────────────────────────────────────────────────────────

-- Recompute every line of a run, then the run totals. A line's deductions are
-- its "other" deductions plus its loan deductions that are not reversed.
CREATE OR REPLACE FUNCTION public.fnhotelpayrollrun_recalc(p_runid int)
RETURNS void
LANGUAGE sql
AS $function$
    WITH loan AS (
        SELECT i.hotelpayrollitemid,
               COALESCE((SELECT SUM(d.amount) FROM public.hotelpayrollitemdeductions d
                         WHERE d.hotelpayrollitemid = i.hotelpayrollitemid AND d.status <> 'Reversed'), 0) AS amt
        FROM   public.hotelpayrollitems i
        WHERE  i.hotelpayrollrunid = p_runid
    )
    UPDATE public.hotelpayrollitems i
    SET    deductions = i.otherdeductions + loan.amt,
           netpay     = i.basicpay + i.dailywage + i.commission + i.bonus - i.otherdeductions - loan.amt
    FROM   loan
    WHERE  loan.hotelpayrollitemid = i.hotelpayrollitemid;

    UPDATE public.hotelpayrollruns r
    SET    totalgrosspay   = COALESCE(t.gross, 0),
           totaldeductions = COALESCE(t.ded, 0),
           totalnetpay     = COALESCE(t.net, 0),
           updatedat       = now()
    FROM  (SELECT SUM(i.basicpay + i.dailywage + i.commission + i.bonus) AS gross,
                  SUM(i.deductions) AS ded,
                  SUM(i.netpay)     AS net
           FROM   public.hotelpayrollitems i
           WHERE  i.hotelpayrollrunid = p_runid) t
    WHERE  r.hotelpayrollrunid = p_runid;
$function$;

-- Save one payroll line (insert or update in place, so its loan deductions
-- survive), together with its loan deductions.
--   p_loandeductions: NULL  -> leave this line's loan deductions as they are
--                     array -> replace them: [{"loanId": 12, "amount": 200}, ...]
--                              an amount of 0 (or a loan left out) removes it.
-- Returns the payroll item id.
CREATE OR REPLACE FUNCTION public.sphotelpayrollitem_save(
    p_farmid          text,
    p_runid           int,
    p_staffid         int,
    p_staffname       text,
    p_staffrole       text,
    p_basicpay        numeric,
    p_dailywage       numeric,
    p_commission      numeric,
    p_bonus           numeric,
    p_otherdeductions numeric,
    p_paymentmethod   text,
    p_notes           text,
    p_loandeductions  jsonb DEFAULT NULL,
    p_by              text  DEFAULT NULL
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status  text;
    v_sname   text;
    v_role    text;
    v_itemid  int;
    v_gross   numeric;
    v_loanded numeric;
    d         record;
    l         record;
    v_other   numeric;
BEGIN
    SELECT status INTO v_status FROM public.hotelpayrollruns
    WHERE  hotelpayrollrunid = p_runid AND farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payroll run not found.'; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'This payroll run is %. Lines can only change while it is a Draft (reopen it first).', v_status;
    END IF;

    SELECT btrim(s.firstname || ' ' || s.lastname), s.role INTO v_sname, v_role
    FROM   public.hotelstaff s
    WHERE  s.hotelstaffid = p_staffid AND s.farmid = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Choose a staff member of this hotel.'; END IF;

    IF LEAST(COALESCE(p_basicpay, 0), COALESCE(p_dailywage, 0), COALESCE(p_commission, 0),
             COALESCE(p_bonus, 0), COALESCE(p_otherdeductions, 0)) < 0 THEN
        RAISE EXCEPTION 'Pay and deduction amounts cannot be negative.';
    END IF;

    SELECT i.hotelpayrollitemid INTO v_itemid
    FROM   public.hotelpayrollitems i
    WHERE  i.hotelpayrollrunid = p_runid AND i.hotelstaffid = p_staffid
    ORDER  BY i.hotelpayrollitemid
    LIMIT  1;

    IF v_itemid IS NULL THEN
        INSERT INTO public.hotelpayrollitems(
            hotelpayrollrunid, hotelstaffid, staffname, staffrole,
            basicpay, dailywage, commission, bonus, otherdeductions, deductions, netpay,
            paymentmethod, notes)
        VALUES (
            p_runid, p_staffid, COALESCE(NULLIF(btrim(p_staffname), ''), v_sname), COALESCE(NULLIF(btrim(p_staffrole), ''), v_role),
            COALESCE(p_basicpay, 0), COALESCE(p_dailywage, 0), COALESCE(p_commission, 0), COALESCE(p_bonus, 0),
            COALESCE(p_otherdeductions, 0), 0, 0,
            COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash'), NULLIF(btrim(p_notes), ''))
        RETURNING hotelpayrollitemid INTO v_itemid;
    ELSE
        UPDATE public.hotelpayrollitems SET
            staffname       = COALESCE(NULLIF(btrim(p_staffname), ''), v_sname),
            staffrole       = COALESCE(NULLIF(btrim(p_staffrole), ''), v_role),
            basicpay        = COALESCE(p_basicpay, 0),
            dailywage       = COALESCE(p_dailywage, 0),
            commission      = COALESCE(p_commission, 0),
            bonus           = COALESCE(p_bonus, 0),
            otherdeductions = COALESCE(p_otherdeductions, 0),
            paymentmethod   = COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash'),
            notes           = NULLIF(btrim(p_notes), '')
        WHERE hotelpayrollitemid = v_itemid;
    END IF;

    IF p_loandeductions IS NOT NULL THEN
        IF jsonb_typeof(p_loandeductions) <> 'array' THEN
            RAISE EXCEPTION 'Loan deductions must be a list.';
        END IF;

        -- Validate every requested deduction before changing anything.
        FOR d IN
            SELECT (e->>'loanId')::int AS loanid, SUM(COALESCE((e->>'amount')::numeric, 0)) AS amount, COUNT(*) AS n
            FROM   jsonb_array_elements(p_loandeductions) e
            GROUP  BY (e->>'loanId')::int
        LOOP
            IF d.loanid IS NULL THEN RAISE EXCEPTION 'A loan deduction is missing its loan.'; END IF;
            IF d.n > 1 THEN RAISE EXCEPTION 'The same loan is listed twice on this payroll line.'; END IF;
            IF d.amount < 0 THEN RAISE EXCEPTION 'A loan deduction cannot be negative.'; END IF;
            CONTINUE WHEN d.amount = 0;

            SELECT * INTO l FROM public.hotelemployeeloans
            WHERE  hotelemployeeloanid = d.loanid AND farmid = p_farmid
            FOR UPDATE;
            IF NOT FOUND THEN RAISE EXCEPTION 'Loan #% does not belong to this hotel.', d.loanid; END IF;
            IF l.hotelstaffid <> p_staffid THEN
                RAISE EXCEPTION 'Loan % belongs to %, not to %.', COALESCE(l.loannumber, '#' || d.loanid), l.staffname, v_sname;
            END IF;
            IF l.status <> 'Active' THEN
                RAISE EXCEPTION 'Loan % is %, so nothing can be deducted for it.', COALESCE(l.loannumber, '#' || d.loanid), l.status;
            END IF;

            SELECT COALESCE(SUM(x.amount), 0) INTO v_other
            FROM   public.hotelpayrollitemdeductions x
            WHERE  x.hotelemployeeloanid = d.loanid AND x.status = 'Draft'
              AND  x.hotelpayrollitemid <> v_itemid;
            IF d.amount > l.outstandingbalance - v_other THEN
                RAISE EXCEPTION 'At most % can be deducted for loan % (% owes %, and % is already set aside on another draft payroll).',
                    GREATEST(l.outstandingbalance - v_other, 0), COALESCE(l.loannumber, '#' || d.loanid),
                    v_sname, l.outstandingbalance, v_other;
            END IF;
        END LOOP;

        -- Remove what is no longer asked for.
        DELETE FROM public.hotelpayrollitemdeductions x
        WHERE  x.hotelpayrollitemid = v_itemid AND x.status = 'Draft'
          AND  NOT EXISTS (
                   SELECT 1 FROM jsonb_array_elements(p_loandeductions) e
                   WHERE  (e->>'loanId')::int = x.hotelemployeeloanid
                     AND  COALESCE((e->>'amount')::numeric, 0) > 0);

        -- Update what stays, add what is new.
        FOR d IN
            SELECT (e->>'loanId')::int AS loanid, (e->>'amount')::numeric AS amount
            FROM   jsonb_array_elements(p_loandeductions) e
            WHERE  COALESCE((e->>'amount')::numeric, 0) > 0
        LOOP
            UPDATE public.hotelpayrollitemdeductions x
            SET    amount = d.amount, updatedat = now()
            WHERE  x.hotelpayrollitemid = v_itemid AND x.hotelemployeeloanid = d.loanid AND x.status = 'Draft';
            IF NOT FOUND THEN
                INSERT INTO public.hotelpayrollitemdeductions(
                    farmid, hotelpayrollrunid, hotelpayrollitemid, hotelstaffid, hotelemployeeloanid,
                    deductiontype, amount, status, createdby)
                SELECT p_farmid, p_runid, v_itemid, p_staffid, d.loanid,
                       CASE WHEN l2.loantype = 'SalaryAdvance' THEN 'SalaryAdvanceRepayment' ELSE 'EmployeeLoanRepayment' END,
                       d.amount, 'Draft', p_by
                FROM   public.hotelemployeeloans l2
                WHERE  l2.hotelemployeeloanid = d.loanid;
            END IF;
        END LOOP;
    END IF;

    -- The line must not pay out less than nothing.
    SELECT i.basicpay + i.dailywage + i.commission + i.bonus INTO v_gross
    FROM   public.hotelpayrollitems i WHERE i.hotelpayrollitemid = v_itemid;
    SELECT COALESCE(SUM(x.amount), 0) INTO v_loanded
    FROM   public.hotelpayrollitemdeductions x
    WHERE  x.hotelpayrollitemid = v_itemid AND x.status <> 'Reversed';
    IF COALESCE(p_otherdeductions, 0) + v_loanded > v_gross THEN
        RAISE EXCEPTION 'Deductions for % (%) are more than their gross pay (%).',
            v_sname, COALESCE(p_otherdeductions, 0) + v_loanded, v_gross;
    END IF;

    PERFORM public.fnhotelpayrollrun_recalc(p_runid);
    RETURN v_itemid;
END;
$function$;

-- Remove a line from a Draft run. Its draft loan deductions go with it.
CREATE OR REPLACE FUNCTION public.sphotelpayrollitem_delete(
    p_farmid text,
    p_itemid int
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v_runid int; v_status text;
BEGIN
    SELECT r.hotelpayrollrunid, r.status INTO v_runid, v_status
    FROM   public.hotelpayrollitems i
    JOIN   public.hotelpayrollruns r ON r.hotelpayrollrunid = i.hotelpayrollrunid
    WHERE  i.hotelpayrollitemid = p_itemid AND r.farmid = p_farmid
    FOR UPDATE OF r;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payroll line not found.'; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'This payroll run is %. Lines can only be removed while it is a Draft.', v_status;
    END IF;

    DELETE FROM public.hotelpayrollitems WHERE hotelpayrollitemid = p_itemid;
    PERFORM public.fnhotelpayrollrun_recalc(v_runid);
END;
$function$;

-- The loan deductions of one run (for the payroll screen).
CREATE OR REPLACE FUNCTION public.sphotelpayrolldeduction_getforrun(
    p_farmid text,
    p_runid  int
) RETURNS TABLE (
    hotelpayrolldeductionid      int,
    hotelpayrollitemid           int,
    hotelstaffid                 int,
    hotelemployeeloanid          int,
    loannumber                   text,
    loantype                     text,
    deductiontype                text,
    amount                       numeric,
    status                       text,
    hotelemployeeloanrepaymentid int,
    outstandingbalance           numeric
)
LANGUAGE sql STABLE
AS $function$
    SELECT d.hotelpayrolldeductionid, d.hotelpayrollitemid, d.hotelstaffid, d.hotelemployeeloanid,
           l.loannumber, l.loantype, d.deductiontype, d.amount, d.status,
           d.hotelemployeeloanrepaymentid, l.outstandingbalance
    FROM   public.hotelpayrollitemdeductions d
    JOIN   public.hotelemployeeloans l ON l.hotelemployeeloanid = d.hotelemployeeloanid
    WHERE  d.farmid = p_farmid AND d.hotelpayrollrunid = p_runid
    ORDER  BY d.hotelpayrollitemid, d.hotelpayrolldeductionid;
$function$;

-- Approve: Draft -> Approved. Every draft loan deduction becomes a Payroll
-- repayment dated the pay date. If any one fails, nothing is approved.
CREATE OR REPLACE FUNCTION public.sphotelpayrollrun_approve(
    p_farmid text,
    p_runid  int,
    p_by     text
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE
    v_run   record;
    d       record;
    v_rep   int;
    v_n     int := 0;
    v_neg   text;
    v_label text;
BEGIN
    SELECT * INTO v_run FROM public.hotelpayrollruns
    WHERE  hotelpayrollrunid = p_runid AND farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payroll run not found.'; END IF;
    IF v_run.status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a Draft payroll run can be approved (this one is %).', v_run.status;
    END IF;

    PERFORM public.fnhotelpayrollrun_recalc(p_runid);

    SELECT string_agg(COALESCE(i.staffname, 'Staff #' || i.hotelstaffid), ', ') INTO v_neg
    FROM   public.hotelpayrollitems i
    WHERE  i.hotelpayrollrunid = p_runid AND i.netpay < 0;
    IF v_neg IS NOT NULL THEN
        RAISE EXCEPTION 'Net pay would be below zero for: %. Reduce their deductions first.', v_neg;
    END IF;

    v_label := 'Payroll ' || to_char(v_run.periodstart, 'DD Mon') || ' – ' || to_char(v_run.periodend, 'DD Mon YYYY');

    FOR d IN
        SELECT x.*, l.loannumber, i.staffname
        FROM   public.hotelpayrollitemdeductions x
        JOIN   public.hotelemployeeloans l ON l.hotelemployeeloanid = x.hotelemployeeloanid
        JOIN   public.hotelpayrollitems  i ON i.hotelpayrollitemid  = x.hotelpayrollitemid
        WHERE  x.hotelpayrollrunid = p_runid AND x.status = 'Draft'
        ORDER  BY x.hotelpayrolldeductionid
    LOOP
        BEGIN
            v_rep := public.sphotelemployeeloanrepayment_record(
                d.hotelemployeeloanid, p_farmid, d.amount, 'Payroll', NULL,
                COALESCE(v_run.paydate, v_run.periodend)::timestamptz,
                'PR-' || p_runid, v_label, p_by, d.hotelpayrolldeductionid, p_runid);
        EXCEPTION WHEN raise_exception THEN
            RAISE EXCEPTION 'Could not deduct % from % for loan %: %',
                d.amount, COALESCE(d.staffname, 'staff'), COALESCE(d.loannumber, '#' || d.hotelemployeeloanid), SQLERRM;
        END;

        UPDATE public.hotelpayrollitemdeductions
        SET    status = 'Posted', hotelemployeeloanrepaymentid = v_rep, updatedat = now()
        WHERE  hotelpayrolldeductionid = d.hotelpayrolldeductionid;
        v_n := v_n + 1;
    END LOOP;

    UPDATE public.hotelpayrollruns
    SET    status = 'Approved', approvedby = p_by, approvedat = now(), updatedat = now()
    WHERE  hotelpayrollrunid = p_runid;

    RETURN v_n;
END;
$function$;

-- Reverses the payroll repayments of a run (used by reopen and cancel).
CREATE OR REPLACE FUNCTION public.fnhotelpayrollrun_reverserepayments(
    p_farmid    text,
    p_runid     int,
    p_reason    text,
    p_by        text,
    p_newstatus text           -- what the deductions become: 'Draft' or 'Reversed'
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE d record; v_n int := 0;
BEGIN
    FOR d IN
        SELECT x.* FROM public.hotelpayrollitemdeductions x
        WHERE  x.hotelpayrollrunid = p_runid AND x.status = 'Posted'
        ORDER  BY x.hotelpayrolldeductionid
    LOOP
        IF d.hotelemployeeloanrepaymentid IS NOT NULL THEN
            PERFORM public.sphotelemployeeloanrepayment_reverse(
                d.hotelemployeeloanrepaymentid, p_farmid, p_reason, p_by, TRUE);
        END IF;
        UPDATE public.hotelpayrollitemdeductions
        SET    status = p_newstatus,
               hotelemployeeloanrepaymentid = CASE WHEN p_newstatus = 'Draft' THEN NULL ELSE hotelemployeeloanrepaymentid END,
               updatedat = now()
        WHERE  hotelpayrolldeductionid = d.hotelpayrolldeductionid;
        v_n := v_n + 1;
    END LOOP;
    RETURN v_n;
END;
$function$;

-- Reopen: Approved -> Draft, to correct a run before it is paid. Its payroll
-- repayments are reversed and its loan deductions become editable again.
CREATE OR REPLACE FUNCTION public.sphotelpayrollrun_unapprove(
    p_farmid text,
    p_runid  int,
    p_reason text,
    p_by     text
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE v_status text; v_n int;
BEGIN
    SELECT status INTO v_status FROM public.hotelpayrollruns
    WHERE  hotelpayrollrunid = p_runid AND farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payroll run not found.'; END IF;
    IF v_status <> 'Approved' THEN
        RAISE EXCEPTION 'Only an Approved payroll run can be reopened (this one is %).', v_status;
    END IF;
    IF NULLIF(btrim(p_reason), '') IS NULL THEN
        RAISE EXCEPTION 'Give a reason for reopening the payroll run.';
    END IF;

    v_n := public.fnhotelpayrollrun_reverserepayments(
        p_farmid, p_runid, 'Payroll run #' || p_runid || ' reopened: ' || btrim(p_reason), p_by, 'Draft');

    UPDATE public.hotelpayrollruns
    SET    status = 'Draft', approvedby = NULL, approvedat = NULL,
           reopenedby = p_by, reopenedat = now(), reopenreason = btrim(p_reason), updatedat = now()
    WHERE  hotelpayrollrunid = p_runid;

    PERFORM public.fnhotelpayrollrun_recalc(p_runid);
    RETURN v_n;
END;
$function$;

-- Cancel: Draft or Approved -> Cancelled. Payroll repayments are reversed and
-- every loan deduction is marked Reversed, so no loan balance changes.
CREATE OR REPLACE FUNCTION public.sphotelpayrollrun_cancel(
    p_farmid text,
    p_runid  int,
    p_reason text,
    p_by     text
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE v_status text; v_n int;
BEGIN
    SELECT status INTO v_status FROM public.hotelpayrollruns
    WHERE  hotelpayrollrunid = p_runid AND farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payroll run not found.'; END IF;
    IF v_status NOT IN ('Draft', 'Approved') THEN
        RAISE EXCEPTION 'Only a Draft or Approved payroll run can be cancelled (this one is %).', v_status;
    END IF;

    v_n := public.fnhotelpayrollrun_reverserepayments(
        p_farmid, p_runid,
        'Payroll run #' || p_runid || ' cancelled' || COALESCE(': ' || NULLIF(btrim(p_reason), ''), ''),
        p_by, 'Reversed');

    UPDATE public.hotelpayrollitemdeductions
    SET    status = 'Reversed', updatedat = now()
    WHERE  hotelpayrollrunid = p_runid AND status = 'Draft';

    UPDATE public.hotelpayrollruns
    SET    status = 'Cancelled', cancelledby = p_by, cancelreason = NULLIF(btrim(p_reason), ''), updatedat = now()
    WHERE  hotelpayrollrunid = p_runid;
    RETURN v_n;
END;
$function$;

-- Mark paid: Approved -> Paid. Net pay leaves the run's cash account, or the
-- hotel's Payroll account when the run has none. Returns the ledger id (NULL
-- when the run pays out nothing).
CREATE OR REPLACE FUNCTION public.sphotelpayrollrun_markpaid(
    p_farmid  text,
    p_runid   int,
    p_paydate date,
    p_by      text
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE
    v_run  record;
    v_acct int;
    v_name text;
    v_txn  int;
    v_date date;
BEGIN
    SELECT * INTO v_run FROM public.hotelpayrollruns
    WHERE  hotelpayrollrunid = p_runid AND farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payroll run not found.'; END IF;
    IF v_run.status <> 'Approved' THEN
        RAISE EXCEPTION 'Only an Approved payroll run can be marked paid (this one is %).', v_run.status;
    END IF;

    v_date := COALESCE(p_paydate, v_run.paydate, CURRENT_DATE);
    v_acct := COALESCE(v_run.hotelcashaccountid,
                       public.fnhotelcash_purposeaccount(p_farmid, 'Payroll', 'Payroll Account'));
    SELECT a.accountname INTO v_name FROM public.hotelcashaccounts a WHERE a.hotelcashaccountid = v_acct;

    IF COALESCE(v_run.totalnetpay, 0) > 0 THEN
        v_txn := public.fnhotelcash_post(
            p_farmid, v_acct, 'Debit', v_run.totalnetpay,
            'Payroll ' || to_char(v_run.periodstart, 'DD Mon') || ' – ' || to_char(v_run.periodend, 'DD Mon YYYY') || ' (net pay)',
            'PR-' || p_runid, 'Payroll', p_runid, p_by, v_date::timestamptz);
    END IF;

    UPDATE public.hotelpayrollruns
    SET    status = 'Paid', paidby = p_by, paidat = now(), paydate = v_date,
           hotelcashaccountid = v_acct, cashaccountname = v_name,
           cashtransactionid = v_txn, updatedat = now()
    WHERE  hotelpayrollrunid = p_runid;

    RETURN v_txn;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Cash Flow: add the staff-loan arm (7) to sphotelcashflow_rows
-- ─────────────────────────────────────────────────────────────────────────────
-- Arms 1-6 are copied unchanged from 316. Same signature and result columns, so
-- CREATE OR REPLACE is enough and _summary / _detail keep working. New
-- flowgroups EmployeeLoanOut / EmployeeLoanIn are the names the shared
-- frontend already labels ("Employee advance" / "Employee advance repaid").
CREATE OR REPLACE FUNCTION public.sphotelcashflow_rows(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    rowsource       text,        -- GuestPayment | RestaurantOrder | DepositIn | DepositOut | Expense | Payroll
    offledger       boolean,
    sourcerowid     integer,
    cashaccountid   integer,
    accountname     text,
    transactiondate timestamp,
    transactiontype text,
    sourcetype      text,
    sourceid        integer,
    istransfer      boolean,
    amount          numeric,
    description     text,
    flowgroup       text,        -- OperatingIn | OperatingOut
    createdat       timestamp)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);
    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);
BEGIN
    -- ---- 1. guest payments (the main revenue) --------------------------------
    -- Money received from guests against invoices or bookings. This is the
    -- primary inflow for a hotel, covering room revenue, charged F&B, and any
    -- other folio items the guest settles.
    RETURN QUERY
    SELECT 'GuestPayment'::text,
           FALSE,
           hp.hotelpaymentid,
           NULL::integer,
           NULL::text,
           hp.paymentdate::timestamp,
           'CashIn'::text,
           'GuestPayment'::text,
           hp.hotelpaymentid,
           FALSE,
           COALESCE(hp.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(hp.notes), ''),
               NULLIF(btrim(hp.reference), ''),
               'Guest payment #' || hp.hotelpaymentid::text
           )::text,
           'OperatingIn'::text,
           hp.createdat::timestamp
    FROM   hotelpayments hp
    WHERE  lower(hp.farmid::text) = lower(p_farmid)
      AND  COALESCE(hp.amount, 0) > 0
      AND  hp.paymentdate::timestamp >= v_from
      AND  hp.paymentdate::timestamp <= v_to;

    -- ---- 2. walk-in restaurant / F&B orders ----------------------------------
    -- Only orders NOT linked to a booking. Room-service and in-house dining
    -- with hotelbookingid set are charged to the guest's folio and collected
    -- through hotelpayments when the invoice is settled. Counting both would
    -- double the revenue.
    --
    -- Only delivered orders: placed/preparing/ready orders have not been paid.
    -- Cancelled orders moved no money.
    RETURN QUERY
    SELECT 'RestaurantOrder'::text,
           FALSE,
           ro.hotelrestaurantorderid,
           NULL::integer,
           NULL::text,
           COALESCE(ro.deliveredtime, ro.ordertime)::timestamp,
           'CashIn'::text,
           'RestaurantOrder'::text,
           ro.hotelrestaurantorderid,
           FALSE,
           COALESCE(ro.totalamount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(ro.notes), ''),
               'Restaurant order #' || ro.hotelrestaurantorderid::text
               || COALESCE(' - Table ' || NULLIF(btrim(ro.tablenumber), ''), '')
           )::text,
           'OperatingIn'::text,
           ro.createdat::timestamp
    FROM   hotelrestaurantorders ro
    WHERE  lower(ro.farmid::text) = lower(p_farmid)
      AND  ro.hotelbookingid IS NULL
      AND  ro.status = 'Delivered'
      AND  COALESCE(ro.totalamount, 0) > 0
      AND  COALESCE(ro.deliveredtime, ro.ordertime)::timestamp >= v_from
      AND  COALESCE(ro.deliveredtime, ro.ordertime)::timestamp <= v_to;

    -- ---- 3. deposits collected -----------------------------------------------
    -- Security or advance deposits received from guests. Money in, but
    -- operating (not financing) because it is part of the guest transaction
    -- cycle, not capital from an owner or lender.
    IF to_regclass('public.hoteldeposits') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'DepositIn'::text,
               FALSE,
               hd.hoteldepositid,
               NULL::integer,
               NULL::text,
               hd.createdat::timestamp,
               'CashIn'::text,
               'DepositCollected'::text,
               hd.hoteldepositid,
               FALSE,
               COALESCE(hd.amount, 0)::numeric,
               COALESCE(
                   NULLIF(btrim(hd.notes), ''),
                   'Deposit collected #' || hd.hoteldepositid::text
               )::text,
               'OperatingIn'::text,
               hd.createdat::timestamp
        FROM   hoteldeposits hd
        WHERE  lower(hd.farmid::text) = lower(p_farmid)
          AND  hd.deposittype = 'Collected'
          AND  COALESCE(hd.amount, 0) > 0
          AND  hd.createdat::timestamp >= v_from
          AND  hd.createdat::timestamp <= v_to;

        -- ---- 4. deposits refunded --------------------------------------------
        -- Money returned to the guest. Negative (outflow), still operating.
        RETURN QUERY
        SELECT 'DepositOut'::text,
               FALSE,
               hd.hoteldepositid,
               NULL::integer,
               NULL::text,
               hd.createdat::timestamp,
               'CashOut'::text,
               'DepositRefunded'::text,
               hd.hoteldepositid,
               FALSE,
               -COALESCE(hd.amount, 0)::numeric,
               COALESCE(
                   NULLIF(btrim(hd.notes), ''),
                   'Deposit refunded #' || hd.hoteldepositid::text
               )::text,
               'OperatingOut'::text,
               hd.createdat::timestamp
        FROM   hoteldeposits hd
        WHERE  lower(hd.farmid::text) = lower(p_farmid)
          AND  hd.deposittype = 'Refunded'
          AND  COALESCE(hd.amount, 0) > 0
          AND  hd.createdat::timestamp >= v_from
          AND  hd.createdat::timestamp <= v_to;
    END IF;

    -- ---- 5. expenses ---------------------------------------------------------
    -- Operational spending: utilities, supplies, maintenance, etc.
    -- Only Approved or Paid expenses count as cash that moved. Draft and
    -- Submitted are intentions; Cancelled never happened.
    RETURN QUERY
    SELECT 'Expense'::text,
           FALSE,
           he.hotelexpenseid,
           he.hotelcashaccountid,
           NULL::text,
           he.expensedate::timestamp,
           'CashOut'::text,
           'Expense'::text,
           he.hotelexpenseid,
           FALSE,
           -COALESCE(he.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(he.description), ''),
               COALESCE(he.category, 'Expense')
           )::text,
           'OperatingOut'::text,
           he.createdat::timestamp
    FROM   hotelexpenses he
    WHERE  lower(he.farmid::text) = lower(p_farmid)
      AND  COALESCE(he.amount, 0) > 0
      AND  he.status IN ('Approved', 'Paid')
      AND  he.expensedate >= v_from
      AND  he.expensedate <= v_to;

    -- ---- 6. payroll ----------------------------------------------------------
    -- Staff wages paid. Only runs that reached 'Paid' status moved money.
    -- The total is netpay (gross minus deductions), which is the cash that
    -- actually left the business.
    RETURN QUERY
    SELECT 'Payroll'::text,
           FALSE,
           pr.hotelpayrollrunid,
           pr.hotelcashaccountid,
           NULL::text,
           COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::timestamp,
           'CashOut'::text,
           'Payroll'::text,
           pr.hotelpayrollrunid,
           FALSE,
           -COALESCE(pr.totalnetpay, 0)::numeric,
           COALESCE(
               NULLIF(btrim(pr.notes), ''),
               'Payroll ' || to_char(pr.periodstart, 'DD Mon') || ' - ' || to_char(pr.periodend, 'DD Mon YYYY')
           )::text,
           'OperatingOut'::text,
           pr.createdat::timestamp
    FROM   hotelpayrollruns pr
    WHERE  lower(pr.farmid::text) = lower(p_farmid)
      AND  pr.status = 'Paid'
      AND  COALESCE(pr.totalnetpay, 0) > 0
      AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::timestamp >= v_from
      AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::timestamp <= v_to;

    -- ---- 7. staff loans and advances (added by 325) -------------------------
    -- Only movements that actually posted to a cash account (a ledger id is
    -- set), so Cash Flow and the account balances move together. A reversal is
    -- its own row on the day it happened, as in the ledger, instead of making
    -- the original disappear. Payroll deductions move no cash and are not here:
    -- the net pay in arm 6 is already smaller by the deducted amount.
    IF to_regclass('public.hotelemployeeloans') IS NOT NULL THEN
        -- 7a. advance paid out
        RETURN QUERY
        SELECT 'LoanDisbursed'::text,
               FALSE,
               l.hotelemployeeloanid,
               l.hotelcashaccountid,
               NULL::text,
               l.disbursementdate::timestamp,
               'CashOut'::text,
               'EmployeeLoanDisbursement'::text,
               l.hotelemployeeloanid,
               FALSE,
               -(l.principalamount::numeric),
               ('Staff ' || CASE WHEN l.loantype = 'SalaryAdvance' THEN 'advance' ELSE 'loan' END
                || ' ' || COALESCE(l.loannumber, '') || ' to ' || COALESCE(l.staffname, 'staff'))::text,
               'EmployeeLoanOut'::text,
               l.createdat::timestamp
        FROM   hotelemployeeloans l
        WHERE  lower(l.farmid::text) = lower(p_farmid)
          AND  l.cashtransactionid IS NOT NULL
          AND  l.disbursementdate::timestamp >= v_from
          AND  l.disbursementdate::timestamp <= v_to;

        -- 7b. advance reversed: the principal came back
        RETURN QUERY
        SELECT 'LoanReversed'::text,
               FALSE,
               l.hotelemployeeloanid,
               l.hotelcashaccountid,
               NULL::text,
               l.reversedat::timestamp,
               'CashIn'::text,
               'EmployeeLoanReversal'::text,
               l.hotelemployeeloanid,
               FALSE,
               l.principalamount::numeric,
               ('Reversal of staff loan ' || COALESCE(l.loannumber, '') || ' to ' || COALESCE(l.staffname, 'staff'))::text,
               'EmployeeLoanIn'::text,
               l.reversedat::timestamp
        FROM   hotelemployeeloans l
        WHERE  lower(l.farmid::text) = lower(p_farmid)
          AND  l.reversalcashtransactionid IS NOT NULL
          AND  l.reversedat::timestamp >= v_from
          AND  l.reversedat::timestamp <= v_to;

        -- 7c. repayment received in cash, MoMo or bank
        RETURN QUERY
        SELECT 'LoanRepaid'::text,
               FALSE,
               r.hotelemployeeloanrepaymentid,
               r.hotelcashaccountid,
               NULL::text,
               r.repaymentdate::timestamp,
               'CashIn'::text,
               'EmployeeLoanRepayment'::text,
               r.hotelemployeeloanid,
               FALSE,
               r.amount::numeric,
               ('Loan repayment ' || COALESCE(l.loannumber, '') || ' from ' || COALESCE(l.staffname, 'staff'))::text,
               'EmployeeLoanIn'::text,
               r.createdat::timestamp
        FROM   hotelemployeeloanrepayments r
        JOIN   hotelemployeeloans l ON l.hotelemployeeloanid = r.hotelemployeeloanid
        WHERE  lower(r.farmid::text) = lower(p_farmid)
          AND  r.cashtransactionid IS NOT NULL
          AND  r.repaymentdate::timestamp >= v_from
          AND  r.repaymentdate::timestamp <= v_to;

        -- 7d. repayment reversed: the money went back out
        RETURN QUERY
        SELECT 'LoanRepayReversed'::text,
               FALSE,
               r.hotelemployeeloanrepaymentid,
               r.hotelcashaccountid,
               NULL::text,
               r.reversedat::timestamp,
               'CashOut'::text,
               'EmployeeLoanRepaymentReversal'::text,
               r.hotelemployeeloanid,
               FALSE,
               -(r.amount::numeric),
               ('Reversal of loan repayment ' || COALESCE(l.loannumber, '') || ' from ' || COALESCE(l.staffname, 'staff'))::text,
               'EmployeeLoanOut'::text,
               r.reversedat::timestamp
        FROM   hotelemployeeloanrepayments r
        JOIN   hotelemployeeloans l ON l.hotelemployeeloanid = r.hotelemployeeloanid
        WHERE  lower(r.farmid::text) = lower(p_farmid)
          AND  r.reversalcashtransactionid IS NOT NULL
          AND  r.reversedat::timestamp >= v_from
          AND  r.reversedat::timestamp <= v_to;
    END IF;
END;
$function$;

-- Detail: same as 316, plus a category for each staff-loan row.
CREATE OR REPLACE FUNCTION public.sphotelcashflow_detail(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    rowsource       text,
    offledger       boolean,
    sourcerowid     integer,
    cashaccountid   integer,
    accountname     text,
    transactiondate timestamp,
    transactiontype text,
    sourcetype      text,
    sourceid        integer,
    istransfer      boolean,
    amount          numeric,
    description     text,
    flowgroup       text,
    category        text,
    createdat       timestamp)
LANGUAGE sql
STABLE
AS $function$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid, r.accountname,
           r.transactiondate, r.transactiontype, r.sourcetype, r.sourceid,
           r.istransfer, r.amount, r.description, r.flowgroup,
           CASE
               WHEN r.rowsource = 'Expense'
                   THEN COALESCE(
                       NULLIF(btrim(
                           COALESCE(ec.name, he.category)
                       ), ''),
                       'Uncategorised'
                   )
               WHEN r.rowsource = 'GuestPayment'
                   THEN COALESCE(
                       'Room revenue (' || NULLIF(btrim(hp.paymentmethod), '') || ')',
                       'Room revenue'
                   )
               WHEN r.rowsource = 'RestaurantOrder' THEN 'Restaurant / F&B'
               WHEN r.rowsource = 'DepositIn'       THEN 'Guest deposits'
               WHEN r.rowsource = 'DepositOut'      THEN 'Deposit refunds'
               WHEN r.rowsource = 'Payroll'         THEN 'Staff wages'
               WHEN r.rowsource IN ('LoanDisbursed', 'LoanReversed')  THEN 'Staff loans & advances'
               WHEN r.rowsource IN ('LoanRepaid', 'LoanRepayReversed') THEN 'Staff loan repayments'
               ELSE 'Other'
           END::text,
           r.createdat
    FROM   public.sphotelcashflow_rows(p_farmid, p_fromdate, p_todate) r
    -- Expense: join to get the category name
    LEFT   JOIN hotelexpenses he
           ON  r.rowsource = 'Expense'
           AND he.hotelexpenseid = r.sourcerowid
           AND lower(he.farmid::text) = lower(p_farmid)
    LEFT   JOIN hotelexpensecategories ec
           ON  he.hotelexpensecategoryid = ec.hotelexpensecategoryid
    -- Guest payment: join to get the payment method for the category label
    LEFT   JOIN hotelpayments hp
           ON  r.rowsource = 'GuestPayment'
           AND hp.hotelpaymentid = r.sourcerowid
           AND lower(hp.farmid::text) = lower(p_farmid);
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Profit & Loss: wages at GROSS pay, and interest on staff loans as income
-- ─────────────────────────────────────────────────────────────────────────────
-- Wages were net pay (317). Once loan deductions exist, net pay understates
-- what staff earned: the deducted part repaid their loan but is still a wage
-- cost. For runs with no deductions gross equals net, so they read as before.
-- Interest repaid on a staff loan is the one part of it that is income; the
-- principal never is.
CREATE OR REPLACE FUNCTION public.sphotelreport_pllines(
    p_farmid    text,
    p_startdate date,
    p_enddate   date
) RETURNS TABLE(
    section         text,
    linekey         text,
    linelabel       text,
    amount          numeric,
    sortorder       integer,
    isinformational boolean,
    entrycount      integer
)
LANGUAGE sql STABLE
AS $function$
    -- Revenue lines
    WITH rev_payments AS (
        SELECT 'Revenue'::text   AS sec,
               'RoomRevenue'     AS k,
               'Room Revenue'    AS lbl,
               ROUND(COALESCE(SUM(hp.amount), 0), 2) AS amt,
               10                AS so,
               FALSE             AS info,
               COUNT(*)::integer AS n
        FROM   hotelpayments hp
        WHERE  lower(hp.farmid::text) = lower(p_farmid)
          AND  hp.paymentdate::date >= p_startdate
          AND  hp.paymentdate::date <= p_enddate
          AND  COALESCE(hp.amount, 0) > 0
    ),
    rev_restaurant AS (
        SELECT 'Revenue'::text       AS sec,
               'RestaurantRevenue'   AS k,
               'Restaurant / F&B'    AS lbl,
               ROUND(COALESCE(SUM(ro.totalamount), 0), 2) AS amt,
               20                    AS so,
               FALSE                 AS info,
               COUNT(*)::integer     AS n
        FROM   hotelrestaurantorders ro
        WHERE  lower(ro.farmid::text) = lower(p_farmid)
          AND  ro.hotelbookingid IS NULL
          AND  ro.status = 'Delivered'
          AND  COALESCE(ro.totalamount, 0) > 0
          AND  COALESCE(ro.deliveredtime, ro.ordertime)::date >= p_startdate
          AND  COALESCE(ro.deliveredtime, ro.ordertime)::date <= p_enddate
    ),
    dep_collected AS (
        SELECT COALESCE(SUM(hd.amount), 0) AS amt, COUNT(*)::integer AS n
        FROM   hoteldeposits hd
        WHERE  lower(hd.farmid::text) = lower(p_farmid)
          AND  hd.deposittype = 'Collected'
          AND  COALESCE(hd.amount, 0) > 0
          AND  hd.createdat::date >= p_startdate
          AND  hd.createdat::date <= p_enddate
    ),
    dep_refunded AS (
        SELECT COALESCE(SUM(hd.amount), 0) AS amt, COUNT(*)::integer AS n
        FROM   hoteldeposits hd
        WHERE  lower(hd.farmid::text) = lower(p_farmid)
          AND  hd.deposittype = 'Refunded'
          AND  COALESCE(hd.amount, 0) > 0
          AND  hd.createdat::date >= p_startdate
          AND  hd.createdat::date <= p_enddate
    ),
    rev_deposits AS (
        SELECT 'Revenue'::text       AS sec,
               'DepositsNet'         AS k,
               'Deposits (net)'      AS lbl,
               ROUND((SELECT amt FROM dep_collected) - (SELECT amt FROM dep_refunded), 2) AS amt,
               30                    AS so,
               FALSE                 AS info,
               ((SELECT n FROM dep_collected) + (SELECT n FROM dep_refunded))::integer AS n
    ),
    -- Expense: payroll, at GROSS pay (325; was net pay in 317)
    exp_payroll AS (
        SELECT 'OperatingExpense'::text AS sec,
               'StaffWages'             AS k,
               'Staff Wages'            AS lbl,
               ROUND(COALESCE(SUM(pr.totalgrosspay), 0), 2) AS amt,
               100                      AS so,
               FALSE                    AS info,
               COUNT(*)::integer        AS n
        FROM   hotelpayrollruns pr
        WHERE  lower(pr.farmid::text) = lower(p_farmid)
          AND  pr.status = 'Paid'
          AND  COALESCE(pr.totalgrosspay, 0) > 0
          AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::date >= p_startdate
          AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::date <= p_enddate
    ),
    -- Revenue: interest repaid on staff loans and advances (325)
    rev_loaninterest AS (
        SELECT 'Revenue'::text              AS sec,
               'StaffLoanInterest'          AS k,
               'Interest on staff loans'    AS lbl,
               ROUND(COALESCE(SUM(r.interestamount), 0), 2) AS amt,
               40                           AS so,
               FALSE                        AS info,
               COUNT(*)::integer            AS n
        FROM   hotelemployeeloanrepayments r
        WHERE  lower(r.farmid::text) = lower(p_farmid)
          AND  r.status = 'Posted'
          AND  r.interestamount > 0
          AND  r.repaymentdate::date >= p_startdate
          AND  r.repaymentdate::date <= p_enddate
    ),
    -- Expense: each category from hotelexpenses
    exp_by_cat AS (
        SELECT 'OperatingExpense'::text AS sec,
               COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised') AS k,
               COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised') AS lbl,
               ROUND(SUM(he.amount), 2) AS amt,
               200                       AS so,
               FALSE                     AS info,
               COUNT(*)::integer         AS n
        FROM   hotelexpenses he
        LEFT   JOIN hotelexpensecategories ec
               ON  he.hotelexpensecategoryid = ec.hotelexpensecategoryid
        WHERE  lower(he.farmid::text) = lower(p_farmid)
          AND  he.status IN ('Approved', 'Paid')
          AND  COALESCE(he.amount, 0) > 0
          AND  he.expensedate >= p_startdate
          AND  he.expensedate <= p_enddate
        GROUP BY COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised')
    ),
    all_lines AS (
        SELECT * FROM rev_payments
        UNION ALL SELECT * FROM rev_restaurant
        UNION ALL SELECT * FROM rev_deposits
        UNION ALL SELECT * FROM rev_loaninterest
        UNION ALL SELECT * FROM exp_payroll
        UNION ALL SELECT * FROM exp_by_cat
    )
    SELECT a.sec, a.k, a.lbl, a.amt, a.so, a.info, a.n
    FROM   all_lines a
    WHERE  a.amt <> 0
    ORDER  BY a.so, a.lbl;
$function$;

-- Summary: a revenue line other than the three named ones (today, staff-loan
-- interest) is added to total revenue, so the totals still equal the lines.
CREATE OR REPLACE FUNCTION public.sphotelreport_plsummary(
    p_farmid    text,
    p_startdate date,
    p_enddate   date
) RETURNS TABLE(
    -- Revenue
    roomrevenue          numeric,
    restaurantrevenue    numeric,
    depositsnet          numeric,
    totalrevenue         numeric,
    -- Expenses
    staffwages           numeric,
    totalexpensecategory numeric,
    totalexpenses        numeric,
    -- Profit
    netprofit            numeric,
    netmarginpercent     numeric,
    status               text,
    -- Counts
    revenueentries       integer,
    expenseentries       integer
)
LANGUAGE plpgsql STABLE
AS $function$
DECLARE
    v_room     numeric := 0;
    v_rest     numeric := 0;
    v_depnet   numeric := 0;
    v_otherrev numeric := 0;
    v_wages    numeric := 0;
    v_expcat   numeric := 0;
    v_revn     integer := 0;
    v_expn     integer := 0;
    v_rev      numeric;
    v_exp      numeric;
    v_net      numeric;
    r          record;
BEGIN
    -- Sum from the lines function so the totals match the statement exactly
    FOR r IN SELECT * FROM sphotelreport_pllines(p_farmid, p_startdate, p_enddate)
    LOOP
        CASE r.linekey
            WHEN 'RoomRevenue'       THEN v_room   := r.amount; v_revn := v_revn + r.entrycount;
            WHEN 'RestaurantRevenue' THEN v_rest   := r.amount; v_revn := v_revn + r.entrycount;
            WHEN 'DepositsNet'       THEN v_depnet := r.amount; v_revn := v_revn + r.entrycount;
            WHEN 'StaffWages'        THEN v_wages  := r.amount; v_expn := v_expn + r.entrycount;
            ELSE
                IF r.section = 'Revenue' THEN
                    v_otherrev := v_otherrev + r.amount;
                    v_revn     := v_revn + r.entrycount;
                ELSIF r.section = 'OperatingExpense' THEN
                    v_expcat := v_expcat + r.amount;
                    v_expn   := v_expn + r.entrycount;
                END IF;
        END CASE;
    END LOOP;

    v_rev := ROUND(v_room + v_rest + v_depnet + v_otherrev, 2);
    v_exp := ROUND(v_wages + v_expcat, 2);
    v_net := ROUND(v_rev - v_exp, 2);

    RETURN QUERY SELECT
        v_room, v_rest, v_depnet, v_rev,
        v_wages, v_expcat, v_exp,
        v_net,
        CASE WHEN v_rev > 0 THEN ROUND(v_net / v_rev * 100, 1) ELSE NULL::numeric END,
        CASE WHEN v_net > 0 THEN 'Profit'
             WHEN v_net < 0 THEN 'Loss'
             ELSE 'Break-even' END::text,
        v_revn, v_expn;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Verification (read-only)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE v_missing text;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
    FROM   unnest(ARRAY[
               'fnhotelcash_post', 'fnhotelcash_purposeaccount',
               'sphotelemployeeloan_create', 'sphotelemployeeloan_update', 'sphotelemployeeloan_disburse',
               'sphotelemployeeloan_cancel', 'sphotelemployeeloan_reverse',
               'sphotelemployeeloanrepayment_record', 'sphotelemployeeloanrepayment_reverse',
               'sphotelemployeeloan_getall', 'sphotelemployeeloan_getbyid', 'sphotelemployeeloanrepayment_getall',
               'sphotelemployeeloan_summary', 'sphotelemployeeloan_eligible', 'sphotelemployeeloan_staffreport',
               'fnhotelpayrollrun_recalc', 'sphotelpayrollitem_save', 'sphotelpayrollitem_delete',
               'sphotelpayrolldeduction_getforrun', 'sphotelpayrollrun_approve', 'sphotelpayrollrun_unapprove',
               'sphotelpayrollrun_cancel', 'sphotelpayrollrun_markpaid', 'fnhotelpayrollrun_reverserepayments',
               'sphotelcashflow_rows', 'sphotelcashflow_detail', 'sphotelreport_pllines', 'sphotelreport_plsummary'
           ]) f
    WHERE  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                       WHERE n.nspname = 'public' AND p.proname = f);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '325 verification failed, missing: %', v_missing;
    END IF;

    -- Exactly one repayment_record / repayment_reverse (the old overloads are gone).
    IF (SELECT COUNT(*) FROM pg_proc WHERE proname = 'sphotelemployeeloanrepayment_record') <> 1
       OR (SELECT COUNT(*) FROM pg_proc WHERE proname = 'sphotelemployeeloanrepayment_reverse') <> 1 THEN
        RAISE EXCEPTION '325 verification failed: an old repayment overload is still present';
    END IF;
END $$;
