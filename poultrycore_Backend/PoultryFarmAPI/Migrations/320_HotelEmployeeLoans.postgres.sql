-- =============================================================================
-- 320_HotelEmployeeLoans.postgres.sql
--
-- Purpose
-- -------
-- Employee loans and salary advances for the Hotel module.
--
-- Tables created
-- --------------
--   hotelemployeeloans           loan / advance records
--   hotelemployeeloanrepayments  append-only repayment history
--
-- Status flow: Draft -> Active -> Paid (or Cancelled / Reversed / WrittenOff)
-- Loan types: EmployeeLoan, SalaryAdvance, OtherAdvance
-- Repayment sources: Cash, MoMo, Bank, Payroll, Other
--
-- An advance is NOT an expense. Disbursement reduces cash but posts no P&L.
-- Getting principal back is NOT revenue. Repayment increases cash but posts no P&L.
-- A payroll deduction moves no cash — net pay is already reduced.
--
-- OutstandingBalance is append-only: never modified directly.
-- Authority is the repayment history (Posted repayments only).
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. hotelemployeeloans
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotelemployeeloans (
    hotelemployeeloanid     serial       PRIMARY KEY,
    farmid                  text         NOT NULL,
    hotelstaffid            int          NOT NULL,
    staffname               text,
    loantype                text         NOT NULL DEFAULT 'SalaryAdvance',
    status                  text         NOT NULL DEFAULT 'Draft',
    principalamount         numeric(14,2) NOT NULL CHECK (principalamount > 0),
    interestamount          numeric(14,2) NOT NULL DEFAULT 0,
    totalrepayable          numeric(14,2) NOT NULL DEFAULT 0,
    totalprincipalrepaid    numeric(14,2) NOT NULL DEFAULT 0,
    totalinterestrepaid     numeric(14,2) NOT NULL DEFAULT 0,
    outstandingbalance      numeric(14,2) NOT NULL DEFAULT 0,
    repaymentmethod         text         NOT NULL DEFAULT 'Cash',
    defaultpayrolldeduction numeric(14,2) NOT NULL DEFAULT 0,
    disbursementdate        timestamptz,
    expectedenddate         timestamptz,
    hotelcashaccountid      int,
    cashtransactionid       int,
    reference               text,
    notes                   text,
    createdby               text,
    createdat               timestamptz  NOT NULL DEFAULT now(),
    updatedat               timestamptz,
    reversedby              text,
    reversedreason          text,
    reversedat              timestamptz
);

CREATE INDEX IF NOT EXISTS ix_hotelemployeeloans_farmid
    ON public.hotelemployeeloans(farmid);
CREATE INDEX IF NOT EXISTS ix_hotelemployeeloans_staffid
    ON public.hotelemployeeloans(hotelstaffid);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. hotelemployeeloanrepayments
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotelemployeeloanrepayments (
    hotelemployeeloanrepaymentid serial    PRIMARY KEY,
    farmid                  text         NOT NULL,
    hotelemployeeloanid     int          NOT NULL REFERENCES public.hotelemployeeloans(hotelemployeeloanid),
    amount                  numeric(14,2) NOT NULL CHECK (amount > 0),
    principalamount         numeric(14,2) NOT NULL DEFAULT 0,
    interestamount          numeric(14,2) NOT NULL DEFAULT 0,
    sourcetype              text         NOT NULL DEFAULT 'Cash',
    paymentmethod           text,
    hotelcashaccountid      int,
    cashtransactionid       int,
    balancebefore           numeric(14,2) NOT NULL DEFAULT 0,
    balanceafter            numeric(14,2) NOT NULL DEFAULT 0,
    repaymentdate           timestamptz  NOT NULL DEFAULT now(),
    reference               text,
    notes                   text,
    status                  text         NOT NULL DEFAULT 'Posted',
    createdby               text,
    createdat               timestamptz  NOT NULL DEFAULT now(),
    reversedby              text,
    reversedreason          text,
    reversedat              timestamptz,
    CONSTRAINT ck_hotelrepay_cashsource CHECK (
        (sourcetype = 'Payroll' AND hotelcashaccountid IS NULL)
        OR (sourcetype <> 'Payroll')
    )
);

CREATE INDEX IF NOT EXISTS ix_hotelrepayments_loanid
    ON public.hotelemployeeloanrepayments(hotelemployeeloanid);

-- =============================================================================
-- STORED PROCEDURES
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- Create loan (Draft status, no cash movement)
-- ─────────────────────────────────────────────────────────────────────────────
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
) RETURNS int AS $$
DECLARE
    v_id int;
    v_total numeric;
    v_sname text;
BEGIN
    -- Resolve staff name
    IF p_staffname IS NULL THEN
        SELECT COALESCE(s.firstname || ' ' || s.lastname, 'Staff #' || p_staffid)
        INTO v_sname
        FROM public.hotelstaff s WHERE s.hotelstaffid = p_staffid AND s.farmid = p_farmid;
    ELSE
        v_sname := p_staffname;
    END IF;

    v_total := p_principalamount + p_interestamount;

    INSERT INTO public.hotelemployeeloans(
        farmid, hotelstaffid, staffname, loantype, status,
        principalamount, interestamount, totalrepayable,
        outstandingbalance, repaymentmethod, defaultpayrolldeduction,
        expectedenddate, reference, notes, createdby
    ) VALUES (
        p_farmid, p_staffid, v_sname, p_loantype, 'Draft',
        p_principalamount, p_interestamount, v_total,
        v_total, p_repaymentmethod, p_defaultdeduction,
        p_expectedenddate, p_reference, p_notes, p_createdby
    ) RETURNING hotelemployeeloanid INTO v_id;

    -- Optional immediate disbursement
    IF p_disbursenow THEN
        PERFORM sphotelemployeeloan_disburse(v_id, p_farmid, p_cashaccountid, p_disbursementdate, p_reference, p_createdby);
    END IF;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- Disburse (Draft -> Active, posts cash out)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_disburse(
    p_loanid          int,
    p_farmid          text,
    p_cashaccountid   int DEFAULT NULL,
    p_disbursementdate timestamptz DEFAULT NULL,
    p_reference       text DEFAULT NULL,
    p_createdby       text DEFAULT NULL
) RETURNS void AS $$
DECLARE
    v_rec record;
    v_cashbal numeric;
    v_txnid int;
BEGIN
    SELECT * INTO v_rec FROM public.hotelemployeeloans
    WHERE hotelemployeeloanid = p_loanid AND farmid = p_farmid FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found'; END IF;
    IF v_rec.status <> 'Draft' THEN RAISE EXCEPTION 'Only Draft loans can be disbursed'; END IF;

    -- Post cash out if account specified
    IF p_cashaccountid IS NOT NULL THEN
        SELECT currentbalance INTO v_cashbal FROM public.hotelcashaccounts
        WHERE hotelcashaccountid = p_cashaccountid AND farmid = p_farmid FOR UPDATE;

        v_cashbal := v_cashbal - v_rec.totalrepayable;

        INSERT INTO public.hotelcashtransactions(
            farmid, hotelcashaccountid, txntype, amount, balanceafter,
            description, reference, sourcetype, sourceid, createdby
        ) VALUES (
            p_farmid, p_cashaccountid, 'Debit', v_rec.totalrepayable, v_cashbal,
            'Employee loan disbursement: ' || v_rec.staffname,
            COALESCE(p_reference, v_rec.reference), 'EmployeeLoanDisbursement', p_loanid, p_createdby
        ) RETURNING hotelcashtransactionid INTO v_txnid;

        UPDATE public.hotelcashaccounts SET currentbalance = v_cashbal, updatedat = now()
        WHERE hotelcashaccountid = p_cashaccountid AND farmid = p_farmid;
    END IF;

    UPDATE public.hotelemployeeloans SET
        status = 'Active',
        disbursementdate = COALESCE(p_disbursementdate, now()),
        hotelcashaccountid = p_cashaccountid,
        cashtransactionid = v_txnid,
        reference = COALESCE(p_reference, reference),
        updatedat = now()
    WHERE hotelemployeeloanid = p_loanid AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- Cancel (Draft only, no financial impact)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_cancel(
    p_loanid  int,
    p_farmid  text,
    p_reason  text DEFAULT NULL,
    p_by      text DEFAULT NULL
) RETURNS void AS $$
DECLARE v_status text;
BEGIN
    SELECT status INTO v_status FROM public.hotelemployeeloans
    WHERE hotelemployeeloanid = p_loanid AND farmid = p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found'; END IF;
    IF v_status <> 'Draft' THEN RAISE EXCEPTION 'Only Draft loans can be cancelled'; END IF;

    UPDATE public.hotelemployeeloans SET
        status = 'Cancelled', reversedreason = p_reason, reversedby = p_by,
        reversedat = now(), updatedat = now()
    WHERE hotelemployeeloanid = p_loanid AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- Reverse (Active only, no posted repayments allowed)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_reverse(
    p_loanid  int,
    p_farmid  text,
    p_reason  text DEFAULT NULL,
    p_by      text DEFAULT NULL
) RETURNS void AS $$
DECLARE
    v_rec record;
    v_posted int;
BEGIN
    SELECT * INTO v_rec FROM public.hotelemployeeloans
    WHERE hotelemployeeloanid = p_loanid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found'; END IF;
    IF v_rec.status NOT IN ('Active', 'Paid') THEN RAISE EXCEPTION 'Only Active or Paid loans can be reversed'; END IF;

    SELECT COUNT(*) INTO v_posted FROM public.hotelemployeeloanrepayments
    WHERE hotelemployeeloanid = p_loanid AND status = 'Posted';
    IF v_posted > 0 THEN RAISE EXCEPTION 'Cannot reverse: % posted repayment(s) exist. Reverse them first.', v_posted; END IF;

    -- Reverse cash if disbursement had a cash account
    IF v_rec.hotelcashaccountid IS NOT NULL THEN
        DECLARE v_cashbal numeric;
        BEGIN
            SELECT currentbalance INTO v_cashbal FROM public.hotelcashaccounts
            WHERE hotelcashaccountid = v_rec.hotelcashaccountid AND farmid = p_farmid FOR UPDATE;

            v_cashbal := v_cashbal + v_rec.totalrepayable;

            INSERT INTO public.hotelcashtransactions(
                farmid, hotelcashaccountid, txntype, amount, balanceafter,
                description, reference, sourcetype, sourceid, createdby
            ) VALUES (
                p_farmid, v_rec.hotelcashaccountid, 'Credit', v_rec.totalrepayable, v_cashbal,
                'REVERSAL: Employee loan disbursement: ' || v_rec.staffname,
                v_rec.reference, 'EmployeeLoanDisbursementReversal', p_loanid, p_by
            );

            UPDATE public.hotelcashaccounts SET currentbalance = v_cashbal, updatedat = now()
            WHERE hotelcashaccountid = v_rec.hotelcashaccountid AND farmid = p_farmid;
        END;
    END IF;

    UPDATE public.hotelemployeeloans SET
        status = 'Reversed', reversedreason = p_reason, reversedby = p_by,
        reversedat = now(), updatedat = now()
    WHERE hotelemployeeloanid = p_loanid AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- Record repayment
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sphotelemployeeloanrepayment_record(
    p_loanid         int,
    p_farmid         text,
    p_amount         numeric,
    p_sourcetype     text DEFAULT 'Cash',
    p_cashaccountid  int DEFAULT NULL,
    p_repaymentdate  timestamptz DEFAULT NULL,
    p_reference      text DEFAULT NULL,
    p_notes          text DEFAULT NULL,
    p_createdby      text DEFAULT NULL
) RETURNS int AS $$
DECLARE
    v_loan record;
    v_balbefore numeric;
    v_balafter  numeric;
    v_principal numeric;
    v_interest  numeric;
    v_cashbal   numeric;
    v_txnid     int;
    v_repid     int;
BEGIN
    SELECT * INTO v_loan FROM public.hotelemployeeloans
    WHERE hotelemployeeloanid = p_loanid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Loan not found'; END IF;
    IF v_loan.status <> 'Active' THEN RAISE EXCEPTION 'Loan is not Active'; END IF;
    IF p_amount <= 0 THEN RAISE EXCEPTION 'Repayment amount must be positive'; END IF;
    IF p_amount > v_loan.outstandingbalance THEN RAISE EXCEPTION 'Repayment exceeds outstanding balance'; END IF;

    v_balbefore := v_loan.outstandingbalance;
    v_balafter  := v_balbefore - p_amount;

    -- Split principal vs interest (interest first)
    v_interest  := LEAST(p_amount, GREATEST(v_loan.interestamount - v_loan.totalinterestrepaid, 0));
    v_principal := p_amount - v_interest;

    -- Cash in (only for non-payroll repayments)
    IF p_sourcetype <> 'Payroll' AND p_cashaccountid IS NOT NULL THEN
        SELECT currentbalance INTO v_cashbal FROM public.hotelcashaccounts
        WHERE hotelcashaccountid = p_cashaccountid AND farmid = p_farmid FOR UPDATE;

        v_cashbal := v_cashbal + p_amount;

        INSERT INTO public.hotelcashtransactions(
            farmid, hotelcashaccountid, txntype, amount, balanceafter,
            description, reference, sourcetype, sourceid, createdby
        ) VALUES (
            p_farmid, p_cashaccountid, 'Credit', p_amount, v_cashbal,
            'Employee loan repayment: ' || v_loan.staffname,
            p_reference, 'EmployeeLoanRepayment', p_loanid, p_createdby
        ) RETURNING hotelcashtransactionid INTO v_txnid;

        UPDATE public.hotelcashaccounts SET currentbalance = v_cashbal, updatedat = now()
        WHERE hotelcashaccountid = p_cashaccountid AND farmid = p_farmid;
    END IF;

    INSERT INTO public.hotelemployeeloanrepayments(
        farmid, hotelemployeeloanid, amount, principalamount, interestamount,
        sourcetype, paymentmethod, hotelcashaccountid, cashtransactionid,
        balancebefore, balanceafter, repaymentdate, reference, notes, status, createdby
    ) VALUES (
        p_farmid, p_loanid, p_amount, v_principal, v_interest,
        p_sourcetype, p_sourcetype, p_cashaccountid, v_txnid,
        v_balbefore, v_balafter, COALESCE(p_repaymentdate, now()),
        p_reference, p_notes, 'Posted', p_createdby
    ) RETURNING hotelemployeeloanrepaymentid INTO v_repid;

    -- Update loan totals
    UPDATE public.hotelemployeeloans SET
        totalprincipalrepaid = totalprincipalrepaid + v_principal,
        totalinterestrepaid  = totalinterestrepaid  + v_interest,
        outstandingbalance   = v_balafter,
        status = CASE WHEN v_balafter <= 0 THEN 'Paid' ELSE status END,
        updatedat = now()
    WHERE hotelemployeeloanid = p_loanid AND farmid = p_farmid;

    RETURN v_repid;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- Reverse repayment
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sphotelemployeeloanrepayment_reverse(
    p_repaymentid int,
    p_farmid      text,
    p_reason      text DEFAULT NULL,
    p_by          text DEFAULT NULL
) RETURNS void AS $$
DECLARE
    v_rep  record;
    v_loan record;
    v_cashbal numeric;
BEGIN
    SELECT * INTO v_rep FROM public.hotelemployeeloanrepayments
    WHERE hotelemployeeloanrepaymentid = p_repaymentid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Repayment not found'; END IF;
    IF v_rep.status <> 'Posted' THEN RAISE EXCEPTION 'Only Posted repayments can be reversed'; END IF;
    IF v_rep.sourcetype = 'Payroll' THEN RAISE EXCEPTION 'Payroll repayments can only be reversed via payroll unapproval'; END IF;

    -- Reverse cash if applicable
    IF v_rep.hotelcashaccountid IS NOT NULL THEN
        SELECT currentbalance INTO v_cashbal FROM public.hotelcashaccounts
        WHERE hotelcashaccountid = v_rep.hotelcashaccountid AND farmid = p_farmid FOR UPDATE;

        v_cashbal := v_cashbal - v_rep.amount;

        INSERT INTO public.hotelcashtransactions(
            farmid, hotelcashaccountid, txntype, amount, balanceafter,
            description, reference, sourcetype, sourceid, createdby
        ) VALUES (
            p_farmid, v_rep.hotelcashaccountid, 'Debit', v_rep.amount, v_cashbal,
            'REVERSAL: Employee loan repayment',
            v_rep.reference, 'EmployeeLoanRepaymentReversal', v_rep.hotelemployeeloanid, p_by
        );

        UPDATE public.hotelcashaccounts SET currentbalance = v_cashbal, updatedat = now()
        WHERE hotelcashaccountid = v_rep.hotelcashaccountid AND farmid = p_farmid;
    END IF;

    -- Update repayment status
    UPDATE public.hotelemployeeloanrepayments SET
        status = 'Reversed', reversedby = p_by, reversedreason = p_reason, reversedat = now()
    WHERE hotelemployeeloanrepaymentid = p_repaymentid;

    -- Update loan totals
    UPDATE public.hotelemployeeloans SET
        totalprincipalrepaid = totalprincipalrepaid - v_rep.principalamount,
        totalinterestrepaid  = totalinterestrepaid  - v_rep.interestamount,
        outstandingbalance   = outstandingbalance + v_rep.amount,
        status = 'Active',
        updatedat = now()
    WHERE hotelemployeeloanid = v_rep.hotelemployeeloanid AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- Read functions
-- ─────────────────────────────────────────────────────────────────────────────

-- Get all loans (filtered)
CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_getall(
    p_farmid  text,
    p_status  text DEFAULT NULL,
    p_staffid int DEFAULT NULL
) RETURNS TABLE (
    hotelemployeeloanid     int,
    farmid                  text,
    hotelstaffid            int,
    staffname               text,
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
    reference               text,
    notes                   text,
    createdby               text,
    createdat               timestamptz,
    updatedat               timestamptz,
    reversedby              text,
    reversedreason          text,
    reversedat              timestamptz
) AS $$
BEGIN
    RETURN QUERY
    SELECT l.hotelemployeeloanid, l.farmid, l.hotelstaffid, l.staffname,
           l.loantype, l.status, l.principalamount, l.interestamount,
           l.totalrepayable, l.totalprincipalrepaid, l.totalinterestrepaid,
           l.outstandingbalance, l.repaymentmethod, l.defaultpayrolldeduction,
           l.disbursementdate, l.expectedenddate, l.hotelcashaccountid,
           l.reference, l.notes, l.createdby, l.createdat, l.updatedat,
           l.reversedby, l.reversedreason, l.reversedat
    FROM   public.hotelemployeeloans l
    WHERE  l.farmid = p_farmid
      AND  (p_status IS NULL OR l.status = p_status)
      AND  (p_staffid IS NULL OR l.hotelstaffid = p_staffid)
    ORDER BY l.createdat DESC;
END;
$$ LANGUAGE plpgsql;

-- Get loan by ID
CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_getbyid(
    p_loanid int,
    p_farmid text
) RETURNS TABLE (
    hotelemployeeloanid     int,
    farmid                  text,
    hotelstaffid            int,
    staffname               text,
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
    reference               text,
    notes                   text,
    createdby               text,
    createdat               timestamptz,
    updatedat               timestamptz,
    reversedby              text,
    reversedreason          text,
    reversedat              timestamptz
) AS $$
BEGIN
    RETURN QUERY
    SELECT l.hotelemployeeloanid, l.farmid, l.hotelstaffid, l.staffname,
           l.loantype, l.status, l.principalamount, l.interestamount,
           l.totalrepayable, l.totalprincipalrepaid, l.totalinterestrepaid,
           l.outstandingbalance, l.repaymentmethod, l.defaultpayrolldeduction,
           l.disbursementdate, l.expectedenddate, l.hotelcashaccountid,
           l.reference, l.notes, l.createdby, l.createdat, l.updatedat,
           l.reversedby, l.reversedreason, l.reversedat
    FROM   public.hotelemployeeloans l
    WHERE  l.hotelemployeeloanid = p_loanid AND l.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Get repayments for a loan
CREATE OR REPLACE FUNCTION public.sphotelemployeeloanrepayment_getall(
    p_loanid int,
    p_farmid text
) RETURNS TABLE (
    hotelemployeeloanrepaymentid int,
    farmid                  text,
    hotelemployeeloanid     int,
    amount                  numeric,
    principalamount         numeric,
    interestamount          numeric,
    sourcetype              text,
    paymentmethod           text,
    hotelcashaccountid      int,
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
) AS $$
BEGIN
    RETURN QUERY
    SELECT r.hotelemployeeloanrepaymentid, r.farmid, r.hotelemployeeloanid,
           r.amount, r.principalamount, r.interestamount,
           r.sourcetype, r.paymentmethod, r.hotelcashaccountid,
           r.balancebefore, r.balanceafter, r.repaymentdate,
           r.reference, r.notes, r.status, r.createdby, r.createdat,
           r.reversedby, r.reversedreason, r.reversedat
    FROM   public.hotelemployeeloanrepayments r
    WHERE  r.hotelemployeeloanid = p_loanid AND r.farmid = p_farmid
    ORDER BY r.createdat;
END;
$$ LANGUAGE plpgsql;

-- Summary (4 cards)
CREATE OR REPLACE FUNCTION public.sphotelemployeeloan_summary(
    p_farmid   text,
    p_fromdate timestamptz DEFAULT NULL,
    p_todate   timestamptz DEFAULT NULL
) RETURNS TABLE (
    totaloutstanding   numeric,
    totaldisbursed     numeric,
    totalrepaid        numeric,
    activecount        int
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(SUM(l.outstandingbalance) FILTER (WHERE l.status IN ('Active','Paid')), 0),
        COALESCE(SUM(l.totalrepayable) FILTER (WHERE l.status IN ('Active','Paid')
            AND (p_fromdate IS NULL OR l.disbursementdate >= p_fromdate)
            AND (p_todate IS NULL OR l.disbursementdate <= p_todate)), 0),
        COALESCE(SUM(l.totalprincipalrepaid + l.totalinterestrepaid) FILTER (WHERE l.status IN ('Active','Paid')), 0),
        COUNT(*) FILTER (WHERE l.status = 'Active')::int
    FROM   public.hotelemployeeloans l
    WHERE  l.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

COMMIT;
