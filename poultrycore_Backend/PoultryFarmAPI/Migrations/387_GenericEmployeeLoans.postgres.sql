-- =============================================================================
-- 387_GenericEmployeeLoans.postgres.sql
--
-- Purpose
-- -------
-- Money the company LENDS TO A MEMBER OF STAFF: what was advanced, what has
-- come back, and how each repayment was made.
--
-- THIS IS THE OPPOSITE OF genericloans
-- ==========================================
-- genericloans is money the company BORROWED -- a liability. This is money
-- the company ADVANCED -- an asset, a receivable. The two must never share
-- semantics:
--
--   genericloans           cash IN  at creation, liability up,  cash OUT to repay
--   genericemployeeloans   cash OUT at creation, RECEIVABLE up, cash IN to repay
--
-- Nothing here touches genericloans, and a staff advance never becomes a
-- supplier payable or a customer receivable. It is its own asset line.
--
-- THE FOUR RULES A STAFF ADVANCE HAS TO OBEY
-- ==========================================
-- 1. LENDING IS NOT AN EXPENSE.
-- 2. GETTING PRINCIPAL BACK IS NOT REVENUE.
-- 3. A PAYROLL DEDUCTION MOVES NO CASH.
-- 4. THE BALANCE MUST BE EXPLAINABLE.
--
-- Idempotent. Safe to run more than once.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. The advance.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericemployeeloans (
    genericemployeeloanid serial PRIMARY KEY,
    farmid                varchar(450) NOT NULL,
    genericstaffid        integer NOT NULL REFERENCES genericstaff (genericstaffid),

    loannumber            text NULL,

    loantype              text NOT NULL DEFAULT 'EmployeeLoan'
                          CHECK (loantype IN ('EmployeeLoan', 'SalaryAdvance', 'OtherAdvance')),

    principalamount       numeric(14,2) NOT NULL CHECK (principalamount > 0),

    interestenabled       boolean NOT NULL DEFAULT FALSE,
    interestamount        numeric(14,2) NOT NULL DEFAULT 0 CHECK (interestamount >= 0),
    interestrate          numeric(9,4) NULL,
    interesttype          text NULL CHECK (interesttype IS NULL OR
                          interesttype IN ('Flat', 'Simple')),

    totalrepayable        numeric(14,2) NOT NULL,

    disbursementdate      date NOT NULL,

    repaymentmethod       text NOT NULL DEFAULT 'PayrollDeduction'
                          CHECK (repaymentmethod IN ('PayrollDeduction', 'Cash', 'MoMo',
                                                     'Bank', 'Mixed', 'Other')),
    defaultpayrolldeduction numeric(14,2) NULL CHECK (defaultpayrolldeduction IS NULL OR
                                                      defaultpayrolldeduction > 0),

    expectedstartdate     date NULL,
    expectedenddate       date NULL,

    purpose               text NULL,
    description           text NULL,
    notes                 text NULL,

    status                text NOT NULL DEFAULT 'Draft'
                          CHECK (status IN ('Draft', 'Active', 'Paid', 'Cancelled',
                                            'Reversed', 'WrittenOff')),
    paidat                timestamp NULL,

    totalprincipalrepaid  numeric(14,2) NOT NULL DEFAULT 0 CHECK (totalprincipalrepaid >= 0),
    totalinterestrepaid   numeric(14,2) NOT NULL DEFAULT 0 CHECK (totalinterestrepaid >= 0),
    outstandingbalance    numeric(14,2) NOT NULL DEFAULT 0,

    genericcashaccountid      integer NULL,
    paymentmethod             text NULL,
    referencenumber           text NULL,
    genericcashtransactionid  integer NULL,
    reversalcashtransactionid integer NULL,
    disbursedby               text NULL,
    disbursedat               timestamp NULL,

    createdby      text NULL,
    createdat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby      text NULL,
    updatedat      timestamp NULL,
    reversedby     text NULL,
    reversedat     timestamp NULL,
    reversalreason text NULL,

    CONSTRAINT ck_genericemployeeloans_repayable
        CHECK (totalrepayable = principalamount + interestamount),
    CONSTRAINT ck_genericemployeeloans_interest
        CHECK (interestenabled OR interestamount = 0)
);

CREATE INDEX IF NOT EXISTS ix_genericemployeeloans_farm_status
    ON genericemployeeloans (farmid, status, disbursementdate DESC);
CREATE INDEX IF NOT EXISTS ix_genericemployeeloans_staff
    ON genericemployeeloans (farmid, genericstaffid, status);
CREATE UNIQUE INDEX IF NOT EXISTS ux_genericemployeeloans_number
    ON genericemployeeloans (farmid, loannumber) WHERE loannumber IS NOT NULL;

COMMENT ON TABLE genericemployeeloans IS
    'Money advanced TO staff -- a receivable, an ASSET. The mirror image of '
    'genericloans, which is money the company borrowed. Never a payroll '
    'expense at disbursement and never a supplier payable.';
COMMENT ON COLUMN genericemployeeloans.outstandingbalance IS
    'Cache. The authority is genericemployeeloanrepayments; this is what the '
    'repayment functions leave behind so a list page need not aggregate the '
    'history per row. Paid is decided by THIS reaching zero.';
COMMENT ON COLUMN genericemployeeloans.defaultpayrolldeduction IS
    'A suggestion shown when preparing payroll. Nothing posts a repayment '
    'because this is set -- the payroll user must add the deduction.';

-- -----------------------------------------------------------------------------
-- 2. The repayment.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericemployeeloanrepayments (
    genericemployeeloanrepaymentid serial PRIMARY KEY,
    farmid                varchar(450) NOT NULL,
    genericemployeeloanid integer NOT NULL
                          REFERENCES genericemployeeloans (genericemployeeloanid),
    genericstaffid        integer NOT NULL REFERENCES genericstaff (genericstaffid),

    repaymentnumber       text NULL,
    repaymentdate         timestamp NOT NULL DEFAULT (now() at time zone 'utc'),

    amount          numeric(14,2) NOT NULL CHECK (amount > 0),
    principalamount numeric(14,2) NOT NULL DEFAULT 0 CHECK (principalamount >= 0),
    interestamount  numeric(14,2) NOT NULL DEFAULT 0 CHECK (interestamount >= 0),

    sourcetype text NOT NULL
               CHECK (sourcetype IN ('Payroll', 'ManualCash', 'Bank', 'MoMo', 'Other')),

    -- Set only when the source is Payroll.
    genericpayrollrunid       integer NULL,
    genericpayrollitemid      integer NULL,

    -- NULL for a payroll deduction: no money changed hands.
    genericcashaccountid integer NULL,
    paymentmethod        text NULL,
    referencenumber      text NULL,
    description          text NULL,
    notes                text NULL,

    balancebefore numeric(14,2) NOT NULL,
    balanceafter  numeric(14,2) NOT NULL,

    status text NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),

    genericcashtransactionid  integer NULL,
    reversalcashtransactionid integer NULL,

    createdby      text NULL,
    createdat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby     text NULL,
    reversedat     timestamp NULL,
    reversalreason text NULL,

    CONSTRAINT ck_genericemployeeloanrepayments_total
        CHECK (amount = principalamount + interestamount),
    CONSTRAINT ck_genericemployeeloanrepayments_cash
        CHECK ((sourcetype = 'Payroll' AND genericcashaccountid IS NULL)
            OR (sourcetype <> 'Payroll' AND genericcashaccountid IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS ix_genericemployeeloanrepayments_loan
    ON genericemployeeloanrepayments (genericemployeeloanid, repaymentdate DESC);
CREATE INDEX IF NOT EXISTS ix_genericemployeeloanrepayments_farm
    ON genericemployeeloanrepayments (farmid, status, repaymentdate DESC);
CREATE INDEX IF NOT EXISTS ix_genericemployeeloanrepayments_run
    ON genericemployeeloanrepayments (genericpayrollrunid)
    WHERE genericpayrollrunid IS NOT NULL;

COMMENT ON CONSTRAINT ck_genericemployeeloanrepayments_cash ON genericemployeeloanrepayments IS
    'A payroll deduction moves no money -- the wage paid out is already net -- '
    'so it must not name a cash account. Every other source must name one, '
    'because the worker actually handed something over.';

-- -----------------------------------------------------------------------------
-- 3. Create an advance, and hand the money over if it is going out now.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericemployeeloan_create(
    p_farmid                  text,
    p_genericstaffid          integer,
    p_principalamount         numeric,
    p_disbursementdate        date,
    p_loantype                text DEFAULT 'EmployeeLoan',
    p_interestenabled         boolean DEFAULT FALSE,
    p_interestamount          numeric DEFAULT 0,
    p_interestrate            numeric DEFAULT NULL,
    p_interesttype            text DEFAULT NULL,
    p_repaymentmethod         text DEFAULT 'PayrollDeduction',
    p_defaultpayrolldeduction numeric DEFAULT NULL,
    p_expectedstartdate       date DEFAULT NULL,
    p_expectedenddate         date DEFAULT NULL,
    p_purpose                 text DEFAULT NULL,
    p_description             text DEFAULT NULL,
    p_notes                   text DEFAULT NULL,
    p_disbursenow             boolean DEFAULT FALSE,
    p_genericcashaccountid    integer DEFAULT NULL,
    p_paymentmethod           text DEFAULT NULL,
    p_referencenumber         text DEFAULT NULL,
    p_createdby               text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id        integer;
    v_principal numeric := COALESCE(p_principalamount, 0);
    v_interest  numeric := CASE WHEN COALESCE(p_interestenabled, FALSE)
                                THEN COALESCE(p_interestamount, 0) ELSE 0 END;
    v_total     numeric;
    v_staffname text;
    v_number    text;
    v_seq       integer;
BEGIN
    IF v_principal <= 0 THEN
        RAISE EXCEPTION 'An advance must be more than zero.';
    END IF;
    IF v_interest < 0 THEN
        RAISE EXCEPTION 'Interest cannot be negative.';
    END IF;
    v_total := v_principal + v_interest;

    SELECT btrim(s.firstname || ' ' || s.lastname)
    INTO   v_staffname
    FROM   genericstaff s
    WHERE  s.genericstaffid = p_genericstaffid AND s.farmid = p_farmid;

    IF v_staffname IS NULL THEN
        RAISE EXCEPTION 'Staff member does not exist or does not belong to this farm.';
    END IF;

    IF COALESCE(p_defaultpayrolldeduction, 0) > v_total THEN
        RAISE EXCEPTION 'The suggested payroll deduction of % is more than the % repayable.',
            p_defaultpayrolldeduction, v_total;
    END IF;

    INSERT INTO genericemployeeloans (
        farmid, genericstaffid, loantype, principalamount,
        interestenabled, interestamount, interestrate, interesttype, totalrepayable,
        disbursementdate, repaymentmethod, defaultpayrolldeduction,
        expectedstartdate, expectedenddate,
        purpose, description, notes,
        status, outstandingbalance, createdby)
    VALUES (
        p_farmid, p_genericstaffid, COALESCE(NULLIF(btrim(p_loantype), ''), 'EmployeeLoan'),
        v_principal,
        COALESCE(p_interestenabled, FALSE), v_interest, p_interestrate,
        NULLIF(btrim(p_interesttype), ''), v_total,
        p_disbursementdate,
        COALESCE(NULLIF(btrim(p_repaymentmethod), ''), 'PayrollDeduction'),
        p_defaultpayrolldeduction,
        p_expectedstartdate, p_expectedenddate,
        NULLIF(btrim(p_purpose), ''), NULLIF(btrim(p_description), ''),
        NULLIF(btrim(p_notes), ''),
        'Draft', 0, p_createdby)
    RETURNING genericemployeeloanid INTO v_id;

    PERFORM pg_advisory_xact_lock(hashtext('genericemployeeloan:' || p_farmid));
    SELECT COUNT(*) INTO v_seq FROM genericemployeeloans WHERE farmid = p_farmid;
    v_number := 'EL-' || lpad(v_seq::text, 4, '0');
    UPDATE genericemployeeloans SET loannumber = v_number
    WHERE  genericemployeeloanid = v_id;

    IF COALESCE(p_disbursenow, FALSE) THEN
        PERFORM public.spgenericemployeeloan_disburse(
            p_farmid, v_id, p_genericcashaccountid,
            p_paymentmethod, p_referencenumber, p_createdby);
    END IF;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Hand the money over.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericemployeeloan_disburse(
    p_farmid               text,
    p_genericemployeeloanid integer,
    p_genericcashaccountid integer,
    p_paymentmethod        text DEFAULT NULL,
    p_referencenumber      text DEFAULT NULL,
    p_disbursedby          text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status    text;
    v_principal numeric;
    v_total     numeric;
    v_number    text;
    v_staffid   integer;
    v_staffname text;
    v_date      date;
    v_balance   numeric;
    v_allowneg  boolean;
    v_txid      integer;
BEGIN
    SELECT l.status, l.principalamount, l.totalrepayable, l.loannumber,
           l.genericstaffid, l.disbursementdate
    INTO   v_status, v_principal, v_total, v_number, v_staffid, v_date
    FROM   genericemployeeloans l
    WHERE  l.genericemployeeloanid = p_genericemployeeloanid AND l.farmid = p_farmid
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Advance % not found.', p_genericemployeeloanid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a Draft advance can be disbursed; this one is %.', v_status;
    END IF;

    SELECT btrim(s.firstname || ' ' || s.lastname) INTO v_staffname
    FROM   genericstaff s WHERE s.genericstaffid = v_staffid;

    SELECT a.currentbalance, a.allownegativebalance
    INTO   v_balance, v_allowneg
    FROM   genericcashaccounts a
    WHERE  a.genericcashaccountid = p_genericcashaccountid AND a.farmid = p_farmid;

    IF v_balance IS NULL THEN
        RAISE EXCEPTION 'Cash account does not exist or does not belong to this farm.';
    END IF;
    IF v_allowneg = FALSE AND (v_balance - v_principal) < 0 THEN
        RAISE EXCEPTION 'This advance would take the cash account below zero.';
    END IF;

    INSERT INTO genericcashtransactions (
        farmid, genericcashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
    VALUES (
        p_farmid, p_genericcashaccountid, v_date::timestamp, 'EmployeeLoanDisbursement',
        'EmployeeLoan', p_genericemployeeloanid, -v_principal,
        'Employee advance to ' || COALESCE(v_staffname, 'staff') ||
            ' - ' || COALESCE(v_number, p_genericemployeeloanid::text),
        p_disbursedby, p_disbursedby, (now() at time zone 'utc'))
    RETURNING genericcashtransactionid INTO v_txid;

    UPDATE genericcashaccounts a
    SET    currentbalance = a.currentbalance - v_principal,
           updatedat = (now() at time zone 'utc')
    WHERE  a.genericcashaccountid = p_genericcashaccountid;

    UPDATE genericemployeeloans
    SET    status = 'Active',
           outstandingbalance = v_total,
           genericcashaccountid = p_genericcashaccountid,
           paymentmethod = NULLIF(btrim(p_paymentmethod), ''),
           referencenumber = NULLIF(btrim(p_referencenumber), ''),
           genericcashtransactionid = v_txid,
           disbursedby = p_disbursedby,
           disbursedat = (now() at time zone 'utc'),
           updatedat = (now() at time zone 'utc'),
           updatedby = p_disbursedby
    WHERE  genericemployeeloanid = p_genericemployeeloanid;

    RETURN v_txid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Edit an advance.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericemployeeloan_update(
    p_farmid                  text,
    p_genericemployeeloanid   integer,
    p_principalamount         numeric DEFAULT NULL,
    p_disbursementdate        date DEFAULT NULL,
    p_loantype                text DEFAULT NULL,
    p_interestenabled         boolean DEFAULT NULL,
    p_interestamount          numeric DEFAULT NULL,
    p_interestrate            numeric DEFAULT NULL,
    p_interesttype            text DEFAULT NULL,
    p_repaymentmethod         text DEFAULT NULL,
    p_defaultpayrolldeduction numeric DEFAULT NULL,
    p_expectedstartdate       date DEFAULT NULL,
    p_expectedenddate         date DEFAULT NULL,
    p_purpose                 text DEFAULT NULL,
    p_description             text DEFAULT NULL,
    p_notes                   text DEFAULT NULL,
    p_updatedby               text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status    text;
    v_principal numeric;
    v_intOn     boolean;
    v_interest  numeric;
BEGIN
    SELECT l.status, l.principalamount, l.interestenabled, l.interestamount
    INTO   v_status, v_principal, v_intOn, v_interest
    FROM   genericemployeeloans l
    WHERE  l.genericemployeeloanid = p_genericemployeeloanid AND l.farmid = p_farmid
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Advance % not found.', p_genericemployeeloanid;
    END IF;

    IF v_status <> 'Draft' AND (
           p_principalamount IS NOT NULL
        OR p_interestenabled IS NOT NULL
        OR p_interestamount IS NOT NULL) THEN
        RAISE EXCEPTION
            'The amount of a disbursed advance cannot be changed. Reverse it and record the correct one.';
    END IF;

    v_principal := COALESCE(p_principalamount, v_principal);
    v_intOn     := COALESCE(p_interestenabled, v_intOn);
    v_interest  := CASE WHEN v_intOn THEN COALESCE(p_interestamount, v_interest) ELSE 0 END;

    IF v_principal <= 0 THEN
        RAISE EXCEPTION 'An advance must be more than zero.';
    END IF;

    UPDATE genericemployeeloans l
    SET    principalamount = v_principal,
           interestenabled = v_intOn,
           interestamount  = v_interest,
           totalrepayable  = v_principal + v_interest,
           outstandingbalance = CASE WHEN l.status = 'Draft' THEN 0
                                     ELSE l.outstandingbalance END,
           interestrate      = COALESCE(p_interestrate, l.interestrate),
           interesttype      = COALESCE(NULLIF(btrim(p_interesttype), ''), l.interesttype),
           disbursementdate  = COALESCE(p_disbursementdate, l.disbursementdate),
           loantype          = COALESCE(NULLIF(btrim(p_loantype), ''), l.loantype),
           repaymentmethod   = COALESCE(NULLIF(btrim(p_repaymentmethod), ''), l.repaymentmethod),
           defaultpayrolldeduction = COALESCE(p_defaultpayrolldeduction, l.defaultpayrolldeduction),
           expectedstartdate = COALESCE(p_expectedstartdate, l.expectedstartdate),
           expectedenddate   = COALESCE(p_expectedenddate, l.expectedenddate),
           purpose           = COALESCE(NULLIF(btrim(p_purpose), ''), l.purpose),
           description       = COALESCE(NULLIF(btrim(p_description), ''), l.description),
           notes             = COALESCE(NULLIF(btrim(p_notes), ''), l.notes),
           updatedby = p_updatedby,
           updatedat = (now() at time zone 'utc')
    WHERE  l.genericemployeeloanid = p_genericemployeeloanid AND l.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Cancel a Draft.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericemployeeloan_cancel(
    p_farmid                text,
    p_genericemployeeloanid integer,
    p_cancelledby           text DEFAULT NULL,
    p_reason                text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v_status text;
BEGIN
    SELECT l.status INTO v_status
    FROM   genericemployeeloans l
    WHERE  l.genericemployeeloanid = p_genericemployeeloanid AND l.farmid = p_farmid
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Advance % not found.', p_genericemployeeloanid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION
            'Only a Draft advance can be cancelled; a disbursed one must be reversed.';
    END IF;

    UPDATE genericemployeeloans
    SET    status = 'Cancelled',
           reversalreason = NULLIF(btrim(p_reason), ''),
           updatedby = p_cancelledby,
           updatedat = (now() at time zone 'utc')
    WHERE  genericemployeeloanid = p_genericemployeeloanid AND farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 7. Reverse a disbursement.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericemployeeloan_reverse(
    p_farmid                text,
    p_genericemployeeloanid integer,
    p_reversedby            text DEFAULT NULL,
    p_reason                text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status    text;
    v_principal numeric;
    v_number    text;
    v_acct      integer;
    v_staffname text;
    v_live      integer;
    v_txid      integer;
BEGIN
    SELECT l.status, l.principalamount, l.loannumber, l.genericcashaccountid,
           btrim(s.firstname || ' ' || s.lastname)
    INTO   v_status, v_principal, v_number, v_acct, v_staffname
    FROM   genericemployeeloans l
    JOIN   genericstaff s ON s.genericstaffid = l.genericstaffid
    WHERE  l.genericemployeeloanid = p_genericemployeeloanid AND l.farmid = p_farmid
    FOR UPDATE OF l;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Advance % not found.', p_genericemployeeloanid;
    END IF;
    IF v_status IN ('Reversed', 'Cancelled') THEN
        RAISE EXCEPTION 'This advance is already %.', v_status;
    END IF;
    IF v_status = 'Draft' THEN
        RAISE EXCEPTION 'A Draft advance has nothing to reverse; cancel it instead.';
    END IF;

    SELECT COUNT(*) INTO v_live
    FROM   genericemployeeloanrepayments r
    WHERE  r.genericemployeeloanid = p_genericemployeeloanid AND r.status = 'Posted';

    IF v_live > 0 THEN
        RAISE EXCEPTION
            'This advance has % posted repayment(s). Reverse them first -- or, for a payroll repayment, unapprove the payroll that created it.',
            v_live;
    END IF;

    IF v_acct IS NOT NULL THEN
        INSERT INTO genericcashtransactions (
            farmid, genericcashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, v_acct, (now() at time zone 'utc'),
            'EmployeeLoanReversal',
            'EmployeeLoanReversal', p_genericemployeeloanid, v_principal,
            'Reversal of employee advance to ' || COALESCE(v_staffname, 'staff') ||
                ' - ' || COALESCE(v_number, p_genericemployeeloanid::text),
            p_reversedby, p_reversedby, (now() at time zone 'utc'))
        RETURNING genericcashtransactionid INTO v_txid;

        UPDATE genericcashaccounts a
        SET    currentbalance = a.currentbalance + v_principal,
               updatedat = (now() at time zone 'utc')
        WHERE  a.genericcashaccountid = v_acct;
    END IF;

    UPDATE genericemployeeloans
    SET    status = 'Reversed',
           outstandingbalance = 0,
           reversalcashtransactionid = v_txid,
           reversedby = p_reversedby,
           reversedat = (now() at time zone 'utc'),
           reversalreason = NULLIF(btrim(p_reason), ''),
           updatedat = (now() at time zone 'utc')
    WHERE  genericemployeeloanid = p_genericemployeeloanid AND farmid = p_farmid;

    RETURN v_txid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 8. Record a repayment.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericemployeeloanrepayment_record(
    p_farmid                  text,
    p_genericemployeeloanid   integer,
    p_amount                  numeric,
    p_sourcetype              text DEFAULT 'ManualCash',
    p_principalamount         numeric DEFAULT NULL,
    p_interestamount          numeric DEFAULT 0,
    p_repaymentdate           timestamp DEFAULT NULL,
    p_genericcashaccountid    integer DEFAULT NULL,
    p_paymentmethod           text DEFAULT NULL,
    p_referencenumber         text DEFAULT NULL,
    p_description             text DEFAULT NULL,
    p_notes                   text DEFAULT NULL,
    p_genericpayrollrunid     integer DEFAULT NULL,
    p_genericpayrollitemid    integer DEFAULT NULL,
    p_genericstaffid          integer DEFAULT NULL,
    p_createdby               text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id          integer;
    v_date        timestamp := COALESCE(p_repaymentdate, (now() at time zone 'utc'));
    v_source      text := COALESCE(NULLIF(btrim(p_sourcetype), ''), 'ManualCash');
    v_amount      numeric := COALESCE(p_amount, 0);
    v_interest    numeric := COALESCE(p_interestamount, 0);
    v_principal   numeric;
    v_status      text;
    v_outstanding numeric;
    v_staffid     integer;
    v_staffname   text;
    v_number      text;
    v_newout      numeric;
    v_txid        integer;
    v_seq         integer;
BEGIN
    IF v_amount <= 0 THEN
        RAISE EXCEPTION 'A repayment must be more than zero.';
    END IF;
    IF v_interest < 0 THEN
        RAISE EXCEPTION 'The interest part of a repayment cannot be negative.';
    END IF;

    v_principal := COALESCE(p_principalamount, v_amount - v_interest);
    IF v_principal < 0 THEN
        RAISE EXCEPTION 'The interest part cannot be more than the repayment.';
    END IF;
    IF v_principal + v_interest <> v_amount THEN
        RAISE EXCEPTION 'Principal % plus interest % does not equal the repayment of %.',
            v_principal, v_interest, v_amount;
    END IF;

    SELECT l.status, l.outstandingbalance, l.genericstaffid, l.loannumber
    INTO   v_status, v_outstanding, v_staffid, v_number
    FROM   genericemployeeloans l
    WHERE  l.genericemployeeloanid = p_genericemployeeloanid AND l.farmid = p_farmid
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Advance % not found on this farm.', p_genericemployeeloanid;
    END IF;
    IF v_status = 'Draft' THEN
        RAISE EXCEPTION 'Disburse the advance before recording repayments against it.';
    END IF;
    IF v_status IN ('Cancelled', 'Reversed') THEN
        RAISE EXCEPTION 'A % advance cannot be repaid.', v_status;
    END IF;

    IF p_genericstaffid IS NOT NULL AND p_genericstaffid <> v_staffid THEN
        RAISE EXCEPTION 'That advance belongs to a different member of staff.';
    END IF;

    IF v_amount > v_outstanding THEN
        RAISE EXCEPTION 'Repayment of % is more than the % still outstanding on %.',
            v_amount, v_outstanding, COALESCE(v_number, p_genericemployeeloanid::text);
    END IF;

    IF v_source = 'Payroll' THEN
        IF p_genericcashaccountid IS NOT NULL THEN
            RAISE EXCEPTION
                'A payroll deduction moves no cash, so it cannot name a cash account.';
        END IF;
    ELSIF p_genericcashaccountid IS NULL THEN
        RAISE EXCEPTION 'A % repayment must say which cash account received it.', v_source;
    ELSE
        PERFORM 1 FROM genericcashaccounts a
        WHERE  a.genericcashaccountid = p_genericcashaccountid AND a.farmid = p_farmid;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Cash account does not exist or does not belong to this farm.';
        END IF;
    END IF;

    SELECT btrim(s.firstname || ' ' || s.lastname) INTO v_staffname
    FROM   genericstaff s WHERE s.genericstaffid = v_staffid;

    v_newout := v_outstanding - v_amount;

    INSERT INTO genericemployeeloanrepayments (
        farmid, genericemployeeloanid, genericstaffid, repaymentdate,
        amount, principalamount, interestamount, sourcetype,
        genericpayrollrunid, genericpayrollitemid,
        genericcashaccountid, paymentmethod, referencenumber, description, notes,
        balancebefore, balanceafter, status, createdby)
    VALUES (
        p_farmid, p_genericemployeeloanid, v_staffid, v_date,
        v_amount, v_principal, v_interest, v_source,
        p_genericpayrollrunid, p_genericpayrollitemid,
        p_genericcashaccountid, NULLIF(btrim(p_paymentmethod), ''),
        NULLIF(btrim(p_referencenumber), ''), NULLIF(btrim(p_description), ''),
        NULLIF(btrim(p_notes), ''),
        v_outstanding, v_newout, 'Posted', p_createdby)
    RETURNING genericemployeeloanrepaymentid INTO v_id;

    PERFORM pg_advisory_xact_lock(hashtext('genericemployeeloanrepayment:' || p_farmid));
    SELECT COUNT(*) INTO v_seq
    FROM   genericemployeeloanrepayments WHERE farmid = p_farmid;
    UPDATE genericemployeeloanrepayments
    SET    repaymentnumber = 'ELR-' || lpad(v_seq::text, 4, '0')
    WHERE  genericemployeeloanrepaymentid = v_id;

    -- ---- cash, only when cash actually moved ----------------------------
    IF v_source <> 'Payroll' THEN
        INSERT INTO genericcashtransactions (
            farmid, genericcashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, p_genericcashaccountid, v_date, 'EmployeeLoanRepayment',
            'EmployeeLoanRepayment', v_id, v_amount,
            'Advance repayment from ' || COALESCE(v_staffname, 'staff') ||
                ' - ' || COALESCE(v_number, p_genericemployeeloanid::text),
            p_createdby, p_createdby, (now() at time zone 'utc'))
        RETURNING genericcashtransactionid INTO v_txid;

        UPDATE genericcashaccounts a
        SET    currentbalance = a.currentbalance + v_amount,
               updatedat = (now() at time zone 'utc')
        WHERE  a.genericcashaccountid = p_genericcashaccountid;

        UPDATE genericemployeeloanrepayments
        SET    genericcashtransactionid = v_txid
        WHERE  genericemployeeloanrepaymentid = v_id;
    END IF;

    -- ---- the receivable -------------------------------------------------
    UPDATE genericemployeeloans l
    SET    totalprincipalrepaid = l.totalprincipalrepaid + v_principal,
           totalinterestrepaid  = l.totalinterestrepaid + v_interest,
           outstandingbalance   = v_newout,
           status = CASE WHEN v_newout <= 0 THEN 'Paid' ELSE 'Active' END,
           paidat = CASE WHEN v_newout <= 0 THEN v_date ELSE NULL END,
           updatedat = (now() at time zone 'utc')
    WHERE  l.genericemployeeloanid = p_genericemployeeloanid AND l.farmid = p_farmid;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 9. Reverse a repayment.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericemployeeloanrepayment_reverse(
    p_farmid       text,
    p_genericemployeeloanrepaymentid integer,
    p_reversedby   text DEFAULT NULL,
    p_reason       text DEFAULT NULL,
    p_allowpayroll boolean DEFAULT FALSE
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status    text;
    v_source    text;
    v_loanid    integer;
    v_amount    numeric;
    v_principal numeric;
    v_interest  numeric;
    v_acct      integer;
    v_runid     integer;
    v_number    text;
    v_loanstatus text;
    v_outstanding numeric;
    v_total     numeric;
    v_staffname text;
    v_newout    numeric;
    v_txid      integer;
BEGIN
    SELECT r.status, r.sourcetype, r.genericemployeeloanid, r.amount,
           r.principalamount, r.interestamount, r.genericcashaccountid,
           r.genericpayrollrunid, r.repaymentnumber
    INTO   v_status, v_source, v_loanid, v_amount,
           v_principal, v_interest, v_acct, v_runid, v_number
    FROM   genericemployeeloanrepayments r
    WHERE  r.genericemployeeloanrepaymentid = p_genericemployeeloanrepaymentid
      AND  r.farmid = p_farmid
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Repayment % not found on this farm.', p_genericemployeeloanrepaymentid;
    END IF;
    IF v_status = 'Reversed' THEN
        RAISE EXCEPTION 'This repayment has already been reversed.';
    END IF;

    IF v_source = 'Payroll' AND NOT COALESCE(p_allowpayroll, FALSE) THEN
        RAISE EXCEPTION
            'This repayment was created by payroll run %. Unapprove that payroll to reverse it.',
            COALESCE(v_runid::text, '(unknown)');
    END IF;

    SELECT l.status, l.outstandingbalance, l.totalrepayable,
           btrim(s.firstname || ' ' || s.lastname)
    INTO   v_loanstatus, v_outstanding, v_total, v_staffname
    FROM   genericemployeeloans l
    JOIN   genericstaff s ON s.genericstaffid = l.genericstaffid
    WHERE  l.genericemployeeloanid = v_loanid
    FOR UPDATE OF l;

    IF v_loanstatus IN ('Reversed', 'Cancelled') THEN
        RAISE EXCEPTION 'The advance is %, so its repayments can no longer be reversed.',
            v_loanstatus;
    END IF;

    v_newout := v_outstanding + v_amount;
    IF v_newout > v_total THEN
        RAISE EXCEPTION
            'Reversing this repayment would leave % outstanding on an advance of only %.',
            v_newout, v_total;
    END IF;

    UPDATE genericemployeeloanrepayments
    SET    status = 'Reversed',
           reversedby = p_reversedby,
           reversedat = (now() at time zone 'utc'),
           reversalreason = NULLIF(btrim(p_reason), '')
    WHERE  genericemployeeloanrepaymentid = p_genericemployeeloanrepaymentid;

    IF v_source <> 'Payroll' AND v_acct IS NOT NULL THEN
        INSERT INTO genericcashtransactions (
            farmid, genericcashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, v_acct, (now() at time zone 'utc'), 'EmployeeLoanRepaymentReversal',
            'EmployeeLoanRepaymentReversal', p_genericemployeeloanrepaymentid, -v_amount,
            'Reversal of advance repayment from ' || COALESCE(v_staffname, 'staff') ||
                ' - ' || COALESCE(v_number, p_genericemployeeloanrepaymentid::text),
            p_reversedby, p_reversedby, (now() at time zone 'utc'))
        RETURNING genericcashtransactionid INTO v_txid;

        UPDATE genericcashaccounts a
        SET    currentbalance = a.currentbalance - v_amount,
               updatedat = (now() at time zone 'utc')
        WHERE  a.genericcashaccountid = v_acct;

        UPDATE genericemployeeloanrepayments
        SET    reversalcashtransactionid = v_txid
        WHERE  genericemployeeloanrepaymentid = p_genericemployeeloanrepaymentid;
    END IF;

    UPDATE genericemployeeloans l
    SET    totalprincipalrepaid = GREATEST(l.totalprincipalrepaid - v_principal, 0),
           totalinterestrepaid  = GREATEST(l.totalinterestrepaid - v_interest, 0),
           outstandingbalance   = v_newout,
           status = CASE WHEN v_newout <= 0 THEN 'Paid' ELSE 'Active' END,
           paidat = CASE WHEN v_newout <= 0 THEN l.paidat ELSE NULL END,
           updatedat = (now() at time zone 'utc')
    WHERE  l.genericemployeeloanid = v_loanid;

    RETURN v_txid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 10. The list.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericemployeeloan_getall(
    p_farmid          text,
    p_genericstaffid  integer DEFAULT NULL,
    p_loantype        text DEFAULT NULL,
    p_status          text DEFAULT NULL,
    p_repaymentmethod text DEFAULT NULL,
    p_fromdate        date DEFAULT NULL,
    p_todate          date DEFAULT NULL,
    p_search          text DEFAULT NULL,
    p_limit           integer DEFAULT 50,
    p_offset          integer DEFAULT 0
) RETURNS TABLE(
    genericemployeeloanid integer,
    farmid varchar,
    genericstaffid integer,
    staffname text,
    staffrole text,
    loannumber text,
    loantype text,
    principalamount numeric,
    interestenabled boolean,
    interestamount numeric,
    interestrate numeric,
    interesttype text,
    totalrepayable numeric,
    disbursementdate date,
    repaymentmethod text,
    defaultpayrolldeduction numeric,
    expectedstartdate date,
    expectedenddate date,
    purpose text,
    description text,
    notes text,
    status text,
    paidat timestamp,
    totalrepaid numeric,
    totalprincipalrepaid numeric,
    totalinterestrepaid numeric,
    outstandingbalance numeric,
    repaymentcount integer,
    genericcashaccountid integer,
    cashaccountname text,
    paymentmethod text,
    referencenumber text,
    genericcashtransactionid integer,
    disbursedby text,
    disbursedat timestamp,
    createdby text,
    createdat timestamp,
    reversedby text,
    reversedat timestamp,
    reversalreason text,
    totalcount bigint
)
LANGUAGE sql
AS $function$
    WITH base AS (
        SELECT l.*,
               btrim(s.firstname || ' ' || s.lastname) AS staffname,
               s.role AS staffrole,
               a.accountname::text AS cashaccountname
        FROM   genericemployeeloans l
        JOIN   genericstaff s ON s.genericstaffid = l.genericstaffid
        LEFT   JOIN genericcashaccounts a
               ON a.genericcashaccountid = l.genericcashaccountid
        WHERE  l.farmid = p_farmid
          AND (p_genericstaffid  IS NULL OR l.genericstaffid = p_genericstaffid)
          AND (p_loantype        IS NULL OR l.loantype = p_loantype)
          AND (p_status          IS NULL OR l.status = p_status)
          AND (p_repaymentmethod IS NULL OR l.repaymentmethod = p_repaymentmethod)
          AND (p_fromdate        IS NULL OR l.disbursementdate >= p_fromdate)
          AND (p_todate          IS NULL OR l.disbursementdate <= p_todate)
          AND (NULLIF(btrim(COALESCE(p_search, '')), '') IS NULL
               OR l.loannumber ILIKE '%' || btrim(p_search) || '%'
               OR btrim(s.firstname || ' ' || s.lastname) ILIKE '%' || btrim(p_search) || '%'
               OR COALESCE(l.description, '') ILIKE '%' || btrim(p_search) || '%'
               OR COALESCE(l.purpose, '')     ILIKE '%' || btrim(p_search) || '%'
               OR COALESCE(l.referencenumber, '') ILIKE '%' || btrim(p_search) || '%')
    ),
    counted AS (SELECT COUNT(*) AS n FROM base)
    SELECT b.genericemployeeloanid, b.farmid, b.genericstaffid, b.staffname, b.staffrole,
           b.loannumber, b.loantype, b.principalamount,
           b.interestenabled, b.interestamount, b.interestrate, b.interesttype,
           b.totalrepayable, b.disbursementdate, b.repaymentmethod,
           b.defaultpayrolldeduction, b.expectedstartdate, b.expectedenddate,
           b.purpose, b.description, b.notes, b.status, b.paidat,
           (b.totalprincipalrepaid + b.totalinterestrepaid)::numeric(14,2) AS totalrepaid,
           b.totalprincipalrepaid, b.totalinterestrepaid, b.outstandingbalance,
           (SELECT COUNT(*)::integer FROM genericemployeeloanrepayments r
             WHERE r.genericemployeeloanid = b.genericemployeeloanid
               AND r.status = 'Posted') AS repaymentcount,
           b.genericcashaccountid, b.cashaccountname, b.paymentmethod, b.referencenumber,
           b.genericcashtransactionid, b.disbursedby, b.disbursedat,
           b.createdby, b.createdat, b.reversedby, b.reversedat, b.reversalreason,
           c.n AS totalcount
    FROM   base b CROSS JOIN counted c
    ORDER  BY b.disbursementdate DESC, b.genericemployeeloanid DESC
    LIMIT  COALESCE(NULLIF(p_limit, 0), 50) OFFSET COALESCE(p_offset, 0);
$function$;

-- -----------------------------------------------------------------------------
-- 11. One advance's repayment history.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericemployeeloanrepayment_getall(
    p_farmid                text,
    p_genericemployeeloanid integer
) RETURNS TABLE(
    genericemployeeloanrepaymentid integer,
    genericemployeeloanid integer,
    genericstaffid integer,
    staffname text,
    repaymentnumber text,
    repaymentdate timestamp,
    amount numeric,
    principalamount numeric,
    interestamount numeric,
    sourcetype text,
    genericpayrollrunid integer,
    payrollperiodstart date,
    payrollperiodend date,
    genericpayrollitemid integer,
    genericcashaccountid integer,
    cashaccountname text,
    paymentmethod text,
    referencenumber text,
    description text,
    notes text,
    balancebefore numeric,
    balanceafter numeric,
    status text,
    genericcashtransactionid integer,
    reversalcashtransactionid integer,
    createdby text,
    createdat timestamp,
    reversedby text,
    reversedat timestamp,
    reversalreason text
)
LANGUAGE sql
AS $function$
    SELECT r.genericemployeeloanrepaymentid, r.genericemployeeloanid, r.genericstaffid,
           btrim(s.firstname || ' ' || s.lastname),
           r.repaymentnumber, r.repaymentdate,
           r.amount, r.principalamount, r.interestamount, r.sourcetype,
           r.genericpayrollrunid, pr.periodstart, pr.periodend,
           r.genericpayrollitemid,
           r.genericcashaccountid, a.accountname::text,
           r.paymentmethod, r.referencenumber, r.description, r.notes,
           r.balancebefore, r.balanceafter, r.status,
           r.genericcashtransactionid, r.reversalcashtransactionid,
           r.createdby, r.createdat, r.reversedby, r.reversedat, r.reversalreason
    FROM   genericemployeeloanrepayments r
    JOIN   genericstaff s ON s.genericstaffid = r.genericstaffid
    LEFT   JOIN genericcashaccounts a ON a.genericcashaccountid = r.genericcashaccountid
    LEFT   JOIN genericpayrollruns pr ON pr.genericpayrollrunid = r.genericpayrollrunid
    WHERE  r.farmid = p_farmid
      AND  r.genericemployeeloanid = p_genericemployeeloanid
    ORDER  BY r.repaymentdate DESC, r.genericemployeeloanrepaymentid DESC;
$function$;

-- -----------------------------------------------------------------------------
-- 12. The four cards.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericemployeeloan_summary(
    p_farmid   text,
    p_fromdate date DEFAULT NULL,
    p_todate   date DEFAULT NULL
) RETURNS TABLE(
    outstandingtotal numeric,
    disbursedinperiod numeric,
    repaidinperiod numeric,
    activeloans integer,
    staffwithactiveloans integer,
    paidloans integer,
    draftloans integer
)
LANGUAGE sql
AS $function$
    SELECT
        COALESCE((SELECT SUM(l.outstandingbalance) FROM genericemployeeloans l
                   WHERE l.farmid = p_farmid
                     AND l.status IN ('Active', 'WrittenOff')), 0)::numeric(14,2),

        COALESCE((SELECT SUM(l.principalamount) FROM genericemployeeloans l
                   WHERE l.farmid = p_farmid
                     AND l.status NOT IN ('Draft', 'Cancelled', 'Reversed')
                     AND (p_fromdate IS NULL OR l.disbursementdate >= p_fromdate)
                     AND (p_todate   IS NULL OR l.disbursementdate <= p_todate)), 0)::numeric(14,2),

        COALESCE((SELECT SUM(r.amount) FROM genericemployeeloanrepayments r
                   WHERE r.farmid = p_farmid
                     AND r.status = 'Posted'
                     AND (p_fromdate IS NULL OR r.repaymentdate::date >= p_fromdate)
                     AND (p_todate   IS NULL OR r.repaymentdate::date <= p_todate)), 0)::numeric(14,2),

        (SELECT COUNT(*)::integer FROM genericemployeeloans l
          WHERE l.farmid = p_farmid AND l.status = 'Active'),

        (SELECT COUNT(DISTINCT l.genericstaffid)::integer FROM genericemployeeloans l
          WHERE l.farmid = p_farmid AND l.status = 'Active'),

        (SELECT COUNT(*)::integer FROM genericemployeeloans l
          WHERE l.farmid = p_farmid AND l.status = 'Paid'),

        (SELECT COUNT(*)::integer FROM genericemployeeloans l
          WHERE l.farmid = p_farmid AND l.status = 'Draft');
$function$;

-- -----------------------------------------------------------------------------
-- 13. Which advances a payroll deduction may be applied to.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericemployeeloan_eligible(
    p_farmid         text,
    p_genericstaffid integer
) RETURNS TABLE(
    genericemployeeloanid integer,
    loannumber text,
    loantype text,
    outstandingbalance numeric,
    defaultpayrolldeduction numeric,
    repaymentmethod text,
    disbursementdate date
)
LANGUAGE sql
AS $function$
    SELECT l.genericemployeeloanid, l.loannumber, l.loantype,
           l.outstandingbalance, l.defaultpayrolldeduction,
           l.repaymentmethod, l.disbursementdate
    FROM   genericemployeeloans l
    WHERE  l.farmid = p_farmid
      AND  l.genericstaffid = p_genericstaffid
      AND  l.status = 'Active'
      AND  l.outstandingbalance > 0
    ORDER  BY l.disbursementdate, l.genericemployeeloanid;
$function$;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
DO $$
DECLARE v_missing text;
BEGIN
    SELECT string_agg(want, ', ')
    INTO   v_missing
    FROM   (VALUES
        ('spgenericemployeeloan_create'),
        ('spgenericemployeeloan_disburse'),
        ('spgenericemployeeloan_update'),
        ('spgenericemployeeloan_cancel'),
        ('spgenericemployeeloan_reverse'),
        ('spgenericemployeeloanrepayment_record'),
        ('spgenericemployeeloanrepayment_reverse'),
        ('spgenericemployeeloan_getall'),
        ('spgenericemployeeloanrepayment_getall'),
        ('spgenericemployeeloan_summary'),
        ('spgenericemployeeloan_eligible')
    ) AS w(want)
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = w.want);

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '387: missing function(s): %', v_missing;
    END IF;

    IF EXISTS (SELECT 1 FROM genericemployeeloans
                WHERE totalrepayable <> principalamount + interestamount) THEN
        RAISE EXCEPTION '387: an advance disagrees with its own total.';
    END IF;
    IF EXISTS (SELECT 1 FROM genericemployeeloans
                WHERE outstandingbalance > totalrepayable) THEN
        RAISE EXCEPTION '387: an advance owes more than it is worth.';
    END IF;

    RAISE NOTICE '387_GenericEmployeeLoans: 2 tables, 11 functions, verified.';
END $$;
