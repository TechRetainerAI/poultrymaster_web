-- =============================================================================
-- 305_PoultryEmployeeLoans.postgres.sql
--
-- Purpose
-- -------
-- Money the company LENDS TO A MEMBER OF STAFF: what was advanced, what has
-- come back, and how each repayment was made.
--
-- THIS IS THE OPPOSITE OF poultryloans (254)
-- ==========================================
-- 254 is money the company BORROWED -- a liability. This is money the company
-- ADVANCED -- an asset, a receivable. The two must never share semantics:
--
--   poultryloans           cash IN  at creation, liability up,  cash OUT to repay
--   poultryemployeeloans   cash OUT at creation, RECEIVABLE up, cash IN to repay
--
-- Nothing here touches poultryloans, and a staff advance never becomes a
-- supplier payable or a customer receivable. It is its own asset line.
--
-- THE FOUR RULES A STAFF ADVANCE HAS TO OBEY
-- ==========================================
-- 1. LENDING IS NOT AN EXPENSE.
--    Handing a worker 2,000 does not make the farm 2,000 poorer -- it swaps
--    cash for a claim on that worker. No expense row is written here, and
--    nothing in this file inserts into `expense`. In particular a salary
--    advance is NOT payroll cost until it is earned or written off.
--
-- 2. GETTING PRINCIPAL BACK IS NOT REVENUE.
--    A worker repaying 500 is the farm recovering its own money. No sale, no
--    revenue line, no profit. Only INTEREST, where a farm charges any, could
--    be income -- and this file deliberately does not post that yet. See the
--    INTEREST note below.
--
-- 3. A PAYROLL DEDUCTION MOVES NO CASH.
--    If 100 is withheld from a 2,200 wage, the farm pays out 2,100 -- it does
--    not pay 2,200 and receive 100 back. So a payroll repayment writes NO cash
--    transaction: poultrycashaccountid is NULL and poultrycashtransactionid
--    stays NULL, and the receivable comes down on its own. The net-pay side is
--    already right because payroll has always paid NetPay. Inventing a 100
--    cash receipt here is the easiest way to break Cash Flow, and the table
--    constraint ck_poultryemployeeloanrepayments_cash makes it impossible.
--
--    A MANUAL repayment is the opposite case and DOES move cash: the worker
--    actually handed money over, so one cash row, positive, for the total.
--
-- 4. THE BALANCE MUST BE EXPLAINABLE.
--    outstandingbalance is a cache, maintained only by the repayment
--    functions. The authority is poultryemployeeloanrepayments, which is
--    append-only: a mistake is corrected by a reversal, never by a DELETE, and
--    every row carries balancebefore/balanceafter so a statement can be read
--    straight off the history.
--
-- INTEREST
-- --------
-- The fields exist and repayments split principal from interest, so the
-- history is complete and the outstanding figure is right whether or not a
-- farm charges interest. What this file does NOT do is post interest to the
-- P&L as income. The primary use case is interest-free advances; the P&L
-- revenue arms live in sppoultryreport_pllines (272), and adding one there is
-- a deliberate separate decision rather than something to smuggle in
-- underneath a feature whose whole point is that principal is not revenue.
-- Until that arm exists, a farm charging interest sees the interest in the
-- advance's history and in the cash it received, and not in profit. Recorded
-- as an open item rather than guessed at.
--
-- MULTIPLE ADVANCES, MULTIPLE REPAYMENTS
-- --------------------------------------
-- No UNIQUE on poultrystaffid. One worker may hold several advances at once
-- and any number over a career, each with its own number, history and
-- balance. There is no balance column on poultrystaff and there must never be
-- one: a single field cannot answer "which advance is being repaid".
--
-- CONCURRENCY
-- -----------
-- Every function that changes a balance takes the loan row with FOR UPDATE
-- before it validates. Two repayments of 400 and 300 against a 500 balance
-- therefore serialise, and the second fails on a balance it re-read rather
-- than on one it remembered. A Postgres function body is a single
-- transaction, so the read, the check and the write cannot be interleaved.
--
-- Idempotent. Safe to run more than once.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. The advance.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poultryemployeeloans (
    poultryemployeeloanid serial PRIMARY KEY,
    farmid                varchar(450) NOT NULL,
    poultrystaffid        integer NOT NULL REFERENCES poultrystaff (poultrystaffid),

    loannumber            text NULL,

    -- Architected for more types. A SalaryAdvance is the same receivable with
    -- a different name and, usually, a shorter life.
    loantype              text NOT NULL DEFAULT 'EmployeeLoan'
                          CHECK (loantype IN ('EmployeeLoan', 'SalaryAdvance', 'OtherAdvance')),

    principalamount       numeric(14,2) NOT NULL CHECK (principalamount > 0),

    interestenabled       boolean NOT NULL DEFAULT FALSE,
    interestamount        numeric(14,2) NOT NULL DEFAULT 0 CHECK (interestamount >= 0),
    interestrate          numeric(9,4) NULL,
    interesttype          text NULL CHECK (interesttype IS NULL OR
                          interesttype IN ('Flat', 'Simple')),

    -- Stored, not derived, so a historic advance still reads correctly if the
    -- interest rules ever change -- and constrained, so it can never disagree
    -- with its own parts.
    totalrepayable        numeric(14,2) NOT NULL,

    disbursementdate      date NOT NULL,

    repaymentmethod       text NOT NULL DEFAULT 'PayrollDeduction'
                          CHECK (repaymentmethod IN ('PayrollDeduction', 'Cash', 'MoMo',
                                                     'Bank', 'Mixed', 'Other')),
    -- A SUGGESTION for payroll, never an instruction. Nothing in this file or
    -- in 306 posts a repayment because this is set.
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

    -- Running totals. Maintained by the repayment functions, never edited.
    totalprincipalrepaid  numeric(14,2) NOT NULL DEFAULT 0 CHECK (totalprincipalrepaid >= 0),
    totalinterestrepaid   numeric(14,2) NOT NULL DEFAULT 0 CHECK (totalinterestrepaid >= 0),
    outstandingbalance    numeric(14,2) NOT NULL DEFAULT 0,

    -- The disbursement: where the money left from, and the ONE cash row it
    -- wrote. NULL on a Draft that has not been handed over yet.
    poultrycashaccountid      integer NULL,
    paymentmethod             text NULL,
    referencenumber           text NULL,
    poultrycashtransactionid  integer NULL,
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

    CONSTRAINT ck_poultryemployeeloans_repayable
        CHECK (totalrepayable = principalamount + interestamount),
    CONSTRAINT ck_poultryemployeeloans_interest
        CHECK (interestenabled OR interestamount = 0)
);

CREATE INDEX IF NOT EXISTS ix_poultryemployeeloans_farm_status
    ON poultryemployeeloans (farmid, status, disbursementdate DESC);
CREATE INDEX IF NOT EXISTS ix_poultryemployeeloans_staff
    ON poultryemployeeloans (farmid, poultrystaffid, status);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryemployeeloans_number
    ON poultryemployeeloans (farmid, loannumber) WHERE loannumber IS NOT NULL;

COMMENT ON TABLE poultryemployeeloans IS
    'Money advanced TO staff -- a receivable, an ASSET. The mirror image of '
    'poultryloans, which is money the company borrowed. Never a payroll '
    'expense at disbursement and never a supplier payable.';
COMMENT ON COLUMN poultryemployeeloans.outstandingbalance IS
    'Cache. The authority is poultryemployeeloanrepayments; this is what the '
    'repayment functions leave behind so a list page need not aggregate the '
    'history per row. Paid is decided by THIS reaching zero.';
COMMENT ON COLUMN poultryemployeeloans.defaultpayrolldeduction IS
    'A suggestion shown when preparing payroll. Nothing posts a repayment '
    'because this is set -- the payroll user must add the deduction.';

-- -----------------------------------------------------------------------------
-- 2. The repayment.
--
-- One row per repayment, whatever the source. A payroll deduction and a MoMo
-- transfer are the same event to the receivable and differ only in whether
-- cash moved -- which is exactly what sourcetype and poultrycashaccountid say.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poultryemployeeloanrepayments (
    poultryemployeeloanrepaymentid serial PRIMARY KEY,
    farmid                varchar(450) NOT NULL,
    poultryemployeeloanid integer NOT NULL
                          REFERENCES poultryemployeeloans (poultryemployeeloanid),
    -- Denormalised from the advance on purpose: a repayment must be provably
    -- against the right worker without a join, and the functions below verify
    -- it matches, so "repayment against another worker's advance" cannot be
    -- written even if a caller asks for it.
    poultrystaffid        integer NOT NULL REFERENCES poultrystaff (poultrystaffid),

    repaymentnumber       text NULL,
    repaymentdate         timestamp NOT NULL DEFAULT (now() at time zone 'utc'),

    amount          numeric(14,2) NOT NULL CHECK (amount > 0),
    principalamount numeric(14,2) NOT NULL DEFAULT 0 CHECK (principalamount >= 0),
    interestamount  numeric(14,2) NOT NULL DEFAULT 0 CHECK (interestamount >= 0),

    sourcetype text NOT NULL
               CHECK (sourcetype IN ('Payroll', 'ManualCash', 'Bank', 'MoMo', 'Other')),

    -- Set only when the source is Payroll. The deduction FK is added by 306,
    -- which is where the deduction table is created; it is a bare integer here
    -- so this file stands on its own.
    poultrypayrollrunid       integer NULL,
    poultrypayrollitemid      integer NULL,
    poultrypayrolldeductionid integer NULL,

    -- NULL for a payroll deduction: no money changed hands. See rule 3.
    poultrycashaccountid integer NULL,
    paymentmethod        text NULL,
    referencenumber      text NULL,
    description          text NULL,
    notes                text NULL,

    -- The statement, readable without re-deriving anything.
    balancebefore numeric(14,2) NOT NULL,
    balanceafter  numeric(14,2) NOT NULL,

    status text NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),

    poultrycashtransactionid  integer NULL,
    reversalcashtransactionid integer NULL,

    createdby      text NULL,
    createdat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby     text NULL,
    reversedat     timestamp NULL,
    reversalreason text NULL,

    CONSTRAINT ck_poultryemployeeloanrepayments_total
        CHECK (amount = principalamount + interestamount),
    -- Rule 3, enforced by the table: a payroll repayment cannot carry a cash
    -- account, and every other source must.
    CONSTRAINT ck_poultryemployeeloanrepayments_cash
        CHECK ((sourcetype = 'Payroll' AND poultrycashaccountid IS NULL)
            OR (sourcetype <> 'Payroll' AND poultrycashaccountid IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS ix_poultryemployeeloanrepayments_loan
    ON poultryemployeeloanrepayments (poultryemployeeloanid, repaymentdate DESC);
CREATE INDEX IF NOT EXISTS ix_poultryemployeeloanrepayments_farm
    ON poultryemployeeloanrepayments (farmid, status, repaymentdate DESC);
CREATE INDEX IF NOT EXISTS ix_poultryemployeeloanrepayments_run
    ON poultryemployeeloanrepayments (poultrypayrollrunid)
    WHERE poultrypayrollrunid IS NOT NULL;

-- Idempotency, spec section 80. One POSTED repayment per payroll deduction,
-- ever. A repeated approval therefore cannot double-charge the worker: the
-- second insert is refused by the index rather than relying on the approval
-- path remembering what it already did. Partial, so a reversed repayment
-- leaves the slot free for a re-approval to post a fresh one (section 44).
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryemployeeloanrepayments_deduction
    ON poultryemployeeloanrepayments (poultrypayrolldeductionid)
    WHERE poultrypayrolldeductionid IS NOT NULL AND status = 'Posted';

COMMENT ON CONSTRAINT ck_poultryemployeeloanrepayments_cash ON poultryemployeeloanrepayments IS
    'A payroll deduction moves no money -- the wage paid out is already net -- '
    'so it must not name a cash account. Every other source must name one, '
    'because the worker actually handed something over.';

-- -----------------------------------------------------------------------------
-- 3. Create an advance, and hand the money over if it is going out now.
--
-- Draft vs Active is the whole of the disbursement question. A Draft has been
-- agreed and not paid: no cash row, no receivable, nothing to repay. Only
-- disbursement makes it a claim on the worker.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryemployeeloan_create(
    p_farmid                  text,
    p_poultrystaffid          integer,
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
    p_poultrycashaccountid    integer DEFAULT NULL,
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

    -- Multi-company: the worker must belong to THIS farm. Never trust the id.
    SELECT btrim(s.firstname || ' ' || s.lastname)
    INTO   v_staffname
    FROM   poultrystaff s
    WHERE  s.poultrystaffid = p_poultrystaffid AND s.farmid = p_farmid;

    IF v_staffname IS NULL THEN
        RAISE EXCEPTION 'Staff member does not exist or does not belong to this farm.';
    END IF;

    IF COALESCE(p_defaultpayrolldeduction, 0) > v_total THEN
        RAISE EXCEPTION 'The suggested payroll deduction of % is more than the % repayable.',
            p_defaultpayrolldeduction, v_total;
    END IF;

    INSERT INTO poultryemployeeloans (
        farmid, poultrystaffid, loantype, principalamount,
        interestenabled, interestamount, interestrate, interesttype, totalrepayable,
        disbursementdate, repaymentmethod, defaultpayrolldeduction,
        expectedstartdate, expectedenddate,
        purpose, description, notes,
        status, outstandingbalance, createdby)
    VALUES (
        p_farmid, p_poultrystaffid, COALESCE(NULLIF(btrim(p_loantype), ''), 'EmployeeLoan'),
        v_principal,
        COALESCE(p_interestenabled, FALSE), v_interest, p_interestrate,
        NULLIF(btrim(p_interesttype), ''), v_total,
        p_disbursementdate,
        COALESCE(NULLIF(btrim(p_repaymentmethod), ''), 'PayrollDeduction'),
        p_defaultpayrolldeduction,
        p_expectedstartdate, p_expectedenddate,
        NULLIF(btrim(p_purpose), ''), NULLIF(btrim(p_description), ''),
        NULLIF(btrim(p_notes), ''),
        -- A Draft owes nothing yet. Disbursement is what creates the claim.
        'Draft', 0, p_createdby)
    RETURNING poultryemployeeloanid INTO v_id;

    -- Farm-scoped numbering. Counting this farm's rows rather than using the
    -- serial keeps the numbers per farm, which is what an owner reading
    -- "EL-0003" expects, and never exposes the primary key.
    --
    -- The advisory lock is why two people creating an advance in the same
    -- second do not both read the same count and both build 'EL-0007'. The
    -- unique index would catch that, but catching it means the second create
    -- FAILS rather than taking the next number, which is the numbering bug
    -- this codebase has already met once (PAY numbers, migrations 238-244).
    -- Taken on the farm, held to commit, so it never blocks another farm.
    PERFORM pg_advisory_xact_lock(hashtext('poultryemployeeloan:' || p_farmid));
    SELECT COUNT(*) INTO v_seq FROM poultryemployeeloans WHERE farmid = p_farmid;
    v_number := 'EL-' || lpad(v_seq::text, 4, '0');
    UPDATE poultryemployeeloans SET loannumber = v_number
    WHERE  poultryemployeeloanid = v_id;

    IF COALESCE(p_disbursenow, FALSE) THEN
        PERFORM public.sppoultryemployeeloan_disburse(
            p_farmid, v_id, p_poultrycashaccountid,
            p_paymentmethod, p_referencenumber, p_createdby);
    END IF;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Hand the money over.
--
-- Cash OUT, receivable UP, and NOTHING else: no expense, no payroll cost, no
-- supplier payable. One cash row for the principal actually handed over --
-- interest is not money that left the building, so it is never part of the
-- cash amount even when it is part of what is repayable.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryemployeeloan_disburse(
    p_farmid               text,
    p_poultryemployeeloanid integer,
    p_poultrycashaccountid integer,
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
           l.poultrystaffid, l.disbursementdate
    INTO   v_status, v_principal, v_total, v_number, v_staffid, v_date
    FROM   poultryemployeeloans l
    WHERE  l.poultryemployeeloanid = p_poultryemployeeloanid AND l.farmid = p_farmid
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Advance % not found.', p_poultryemployeeloanid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a Draft advance can be disbursed; this one is %.', v_status;
    END IF;

    SELECT btrim(s.firstname || ' ' || s.lastname) INTO v_staffname
    FROM   poultrystaff s WHERE s.poultrystaffid = v_staffid;

    SELECT a.currentbalance, a.allownegativebalance
    INTO   v_balance, v_allowneg
    FROM   poultrycashaccounts a
    WHERE  a.poultrycashaccountid = p_poultrycashaccountid AND a.farmid = p_farmid;

    IF v_balance IS NULL THEN
        RAISE EXCEPTION 'Cash account does not exist or does not belong to this farm.';
    END IF;
    -- The account's own policy decides, exactly as it does for every other
    -- payment in the system. This feature does not get an exemption.
    IF v_allowneg = FALSE AND (v_balance - v_principal) < 0 THEN
        RAISE EXCEPTION 'This advance would take the cash account below zero.';
    END IF;

    -- ---- ONE cash row, for the principal handed over --------------------
    INSERT INTO poultrycashtransactions (
        farmid, poultrycashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
    VALUES (
        p_farmid, p_poultrycashaccountid, v_date::timestamp, 'EmployeeLoanDisbursement',
        'EmployeeLoan', p_poultryemployeeloanid, -v_principal,
        'Employee advance to ' || COALESCE(v_staffname, 'staff') ||
            ' - ' || COALESCE(v_number, p_poultryemployeeloanid::text),
        p_disbursedby, p_disbursedby, (now() at time zone 'utc'))
    RETURNING poultrycashtransactionid INTO v_txid;

    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - v_principal,
           updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycashaccountid = p_poultrycashaccountid;

    -- ---- the claim on the worker ----------------------------------------
    UPDATE poultryemployeeloans
    SET    status = 'Active',
           outstandingbalance = v_total,
           poultrycashaccountid = p_poultrycashaccountid,
           paymentmethod = NULLIF(btrim(p_paymentmethod), ''),
           referencenumber = NULLIF(btrim(p_referencenumber), ''),
           poultrycashtransactionid = v_txid,
           disbursedby = p_disbursedby,
           disbursedat = (now() at time zone 'utc'),
           updatedat = (now() at time zone 'utc'),
           updatedby = p_disbursedby
    WHERE  poultryemployeeloanid = p_poultryemployeeloanid;

    RETURN v_txid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Edit an advance.
--
-- Only while it is a Draft, and only the terms. Once money has gone out, the
-- principal, the worker and the cash account are financial history: changing
-- them would rewrite a cash row that has already been reported. Correcting a
-- disbursed advance means reversing it and recording the right one.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryemployeeloan_update(
    p_farmid                  text,
    p_poultryemployeeloanid   integer,
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
    FROM   poultryemployeeloans l
    WHERE  l.poultryemployeeloanid = p_poultryemployeeloanid AND l.farmid = p_farmid
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Advance % not found.', p_poultryemployeeloanid;
    END IF;

    -- The money-shaped fields are frozen after disbursement; the descriptive
    -- ones stay editable for ever, because a better note never rewrote a
    -- balance.
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

    UPDATE poultryemployeeloans l
    SET    principalamount = v_principal,
           interestenabled = v_intOn,
           interestamount  = v_interest,
           totalrepayable  = v_principal + v_interest,
           -- A Draft owes nothing; an Active advance keeps the balance its
           -- repayments left behind.
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
    WHERE  l.poultryemployeeloanid = p_poultryemployeeloanid AND l.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Cancel a Draft.
--
-- Nothing financial has happened, so there is nothing to undo. A disbursed
-- advance is reversed instead -- see the next function.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryemployeeloan_cancel(
    p_farmid                text,
    p_poultryemployeeloanid integer,
    p_cancelledby           text DEFAULT NULL,
    p_reason                text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE v_status text;
BEGIN
    SELECT l.status INTO v_status
    FROM   poultryemployeeloans l
    WHERE  l.poultryemployeeloanid = p_poultryemployeeloanid AND l.farmid = p_farmid
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Advance % not found.', p_poultryemployeeloanid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION
            'Only a Draft advance can be cancelled; a disbursed one must be reversed.';
    END IF;

    UPDATE poultryemployeeloans
    SET    status = 'Cancelled',
           reversalreason = NULLIF(btrim(p_reason), ''),
           updatedby = p_cancelledby,
           updatedat = (now() at time zone 'utc')
    WHERE  poultryemployeeloanid = p_poultryemployeeloanid AND farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 7. Reverse a disbursement.
--
-- The money comes back and the claim disappears, by appending rather than
-- deleting. Refused while any repayment is still posted: undoing the advance
-- while its repayments stand would leave repayments against an advance that
-- was never made, and a receivable that goes negative. The caller reverses
-- the repayments first -- which is a decision a person should make explicitly,
-- not something a cascade should do quietly.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryemployeeloan_reverse(
    p_farmid                text,
    p_poultryemployeeloanid integer,
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
    SELECT l.status, l.principalamount, l.loannumber, l.poultrycashaccountid,
           btrim(s.firstname || ' ' || s.lastname)
    INTO   v_status, v_principal, v_number, v_acct, v_staffname
    FROM   poultryemployeeloans l
    JOIN   poultrystaff s ON s.poultrystaffid = l.poultrystaffid
    WHERE  l.poultryemployeeloanid = p_poultryemployeeloanid AND l.farmid = p_farmid
    FOR UPDATE OF l;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Advance % not found.', p_poultryemployeeloanid;
    END IF;
    IF v_status IN ('Reversed', 'Cancelled') THEN
        RAISE EXCEPTION 'This advance is already %.', v_status;
    END IF;
    IF v_status = 'Draft' THEN
        RAISE EXCEPTION 'A Draft advance has nothing to reverse; cancel it instead.';
    END IF;

    SELECT COUNT(*) INTO v_live
    FROM   poultryemployeeloanrepayments r
    WHERE  r.poultryemployeeloanid = p_poultryemployeeloanid AND r.status = 'Posted';

    IF v_live > 0 THEN
        RAISE EXCEPTION
            'This advance has % posted repayment(s). Reverse them first -- or, for a payroll repayment, unapprove the payroll that created it.',
            v_live;
    END IF;

    IF v_acct IS NOT NULL THEN
        INSERT INTO poultrycashtransactions (
            farmid, poultrycashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, v_acct, (now() at time zone 'utc'), -- 20 chars, and it has to be: transactiontype is varchar(30),
            -- and the obvious name for this event -- disbursement plus the word
            -- reversal -- is 32. See migration 311.
            'EmployeeLoanReversal',
            'EmployeeLoanReversal', p_poultryemployeeloanid, v_principal,
            'Reversal of employee advance to ' || COALESCE(v_staffname, 'staff') ||
                ' - ' || COALESCE(v_number, p_poultryemployeeloanid::text),
            p_reversedby, p_reversedby, (now() at time zone 'utc'))
        RETURNING poultrycashtransactionid INTO v_txid;

        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance + v_principal,
               updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = v_acct;
    END IF;

    UPDATE poultryemployeeloans
    SET    status = 'Reversed',
           outstandingbalance = 0,
           reversalcashtransactionid = v_txid,
           reversedby = p_reversedby,
           reversedat = (now() at time zone 'utc'),
           reversalreason = NULLIF(btrim(p_reason), ''),
           updatedat = (now() at time zone 'utc')
    WHERE  poultryemployeeloanid = p_poultryemployeeloanid AND farmid = p_farmid;

    RETURN v_txid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 8. Record a repayment.
--
-- ONE function for every source, because the receivable does not care how the
-- money came back and the balance arithmetic must live in exactly one place.
-- What the source decides is the CASH leg:
--
--   Payroll      no cash row at all. The wage paid out was already net, so
--                the money never moved as its own event (rule 3).
--   anything     one cash row, POSITIVE, for the total -- the worker handed
--   else         something over and the account really does hold more.
--
-- No negative-balance check: money is arriving, so no account can be driven
-- below zero by this.
--
-- The payroll approval path in 309 calls this with p_sourcetype => 'Payroll'
-- and the three payroll ids. It does not reimplement any of it.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryemployeeloanrepayment_record(
    p_farmid                  text,
    p_poultryemployeeloanid   integer,
    p_amount                  numeric,
    p_sourcetype              text DEFAULT 'ManualCash',
    p_principalamount         numeric DEFAULT NULL,
    p_interestamount          numeric DEFAULT 0,
    p_repaymentdate           timestamp DEFAULT NULL,
    p_poultrycashaccountid    integer DEFAULT NULL,
    p_paymentmethod           text DEFAULT NULL,
    p_referencenumber         text DEFAULT NULL,
    p_description             text DEFAULT NULL,
    p_notes                   text DEFAULT NULL,
    p_poultrypayrollrunid     integer DEFAULT NULL,
    p_poultrypayrollitemid    integer DEFAULT NULL,
    p_poultrypayrolldeductionid integer DEFAULT NULL,
    -- Optional, and checked when given: the caller states which worker it
    -- believes this is for, and we refuse if it is not the advance's own.
    p_poultrystaffid          integer DEFAULT NULL,
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

    -- Default the split to all-principal, which is the interest-free case and
    -- therefore almost every advance.
    v_principal := COALESCE(p_principalamount, v_amount - v_interest);
    IF v_principal < 0 THEN
        RAISE EXCEPTION 'The interest part cannot be more than the repayment.';
    END IF;
    IF v_principal + v_interest <> v_amount THEN
        RAISE EXCEPTION 'Principal % plus interest % does not equal the repayment of %.',
            v_principal, v_interest, v_amount;
    END IF;

    -- FOR UPDATE, and every check below reads from what it returned. Two
    -- concurrent repayments against the same advance serialise here, so the
    -- second one is validated against the balance the first one left.
    SELECT l.status, l.outstandingbalance, l.poultrystaffid, l.loannumber
    INTO   v_status, v_outstanding, v_staffid, v_number
    FROM   poultryemployeeloans l
    WHERE  l.poultryemployeeloanid = p_poultryemployeeloanid AND l.farmid = p_farmid
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Advance % not found on this farm.', p_poultryemployeeloanid;
    END IF;
    IF v_status = 'Draft' THEN
        RAISE EXCEPTION 'Disburse the advance before recording repayments against it.';
    END IF;
    IF v_status IN ('Cancelled', 'Reversed') THEN
        RAISE EXCEPTION 'A % advance cannot be repaid.', v_status;
    END IF;

    -- Section 33, server side. The page filters the dropdown; this is what
    -- makes it true.
    IF p_poultrystaffid IS NOT NULL AND p_poultrystaffid <> v_staffid THEN
        RAISE EXCEPTION 'That advance belongs to a different member of staff.';
    END IF;

    -- Sections 34 and 83. Repaying more than is owed would turn the worker
    -- into a creditor.
    IF v_amount > v_outstanding THEN
        RAISE EXCEPTION 'Repayment of % is more than the % still outstanding on %.',
            v_amount, v_outstanding, COALESCE(v_number, p_poultryemployeeloanid::text);
    END IF;

    IF v_source = 'Payroll' THEN
        IF p_poultrycashaccountid IS NOT NULL THEN
            RAISE EXCEPTION
                'A payroll deduction moves no cash, so it cannot name a cash account.';
        END IF;
        IF p_poultrypayrolldeductionid IS NULL THEN
            RAISE EXCEPTION
                'A payroll repayment must carry the deduction it came from, or it cannot be reversed with its payroll.';
        END IF;
    ELSIF p_poultrycashaccountid IS NULL THEN
        RAISE EXCEPTION 'A % repayment must say which cash account received it.', v_source;
    ELSE
        PERFORM 1 FROM poultrycashaccounts a
        WHERE  a.poultrycashaccountid = p_poultrycashaccountid AND a.farmid = p_farmid;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Cash account does not exist or does not belong to this farm.';
        END IF;
    END IF;

    SELECT btrim(s.firstname || ' ' || s.lastname) INTO v_staffname
    FROM   poultrystaff s WHERE s.poultrystaffid = v_staffid;

    v_newout := v_outstanding - v_amount;

    INSERT INTO poultryemployeeloanrepayments (
        farmid, poultryemployeeloanid, poultrystaffid, repaymentdate,
        amount, principalamount, interestamount, sourcetype,
        poultrypayrollrunid, poultrypayrollitemid, poultrypayrolldeductionid,
        poultrycashaccountid, paymentmethod, referencenumber, description, notes,
        balancebefore, balanceafter, status, createdby)
    VALUES (
        p_farmid, p_poultryemployeeloanid, v_staffid, v_date,
        v_amount, v_principal, v_interest, v_source,
        p_poultrypayrollrunid, p_poultrypayrollitemid, p_poultrypayrolldeductionid,
        p_poultrycashaccountid, NULLIF(btrim(p_paymentmethod), ''),
        NULLIF(btrim(p_referencenumber), ''), NULLIF(btrim(p_description), ''),
        NULLIF(btrim(p_notes), ''),
        v_outstanding, v_newout, 'Posted', p_createdby)
    RETURNING poultryemployeeloanrepaymentid INTO v_id;

    -- Same numbering lock as the advance, same reason.
    PERFORM pg_advisory_xact_lock(hashtext('poultryemployeeloanrepayment:' || p_farmid));
    SELECT COUNT(*) INTO v_seq
    FROM   poultryemployeeloanrepayments WHERE farmid = p_farmid;
    UPDATE poultryemployeeloanrepayments
    SET    repaymentnumber = 'ELR-' || lpad(v_seq::text, 4, '0')
    WHERE  poultryemployeeloanrepaymentid = v_id;

    -- ---- cash, only when cash actually moved ----------------------------
    IF v_source <> 'Payroll' THEN
        INSERT INTO poultrycashtransactions (
            farmid, poultrycashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, p_poultrycashaccountid, v_date, 'EmployeeLoanRepayment',
            'EmployeeLoanRepayment', v_id, v_amount,
            'Advance repayment from ' || COALESCE(v_staffname, 'staff') ||
                ' - ' || COALESCE(v_number, p_poultryemployeeloanid::text),
            p_createdby, p_createdby, (now() at time zone 'utc'))
        RETURNING poultrycashtransactionid INTO v_txid;

        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance + v_amount,
               updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = p_poultrycashaccountid;

        UPDATE poultryemployeeloanrepayments
        SET    poultrycashtransactionid = v_txid
        WHERE  poultryemployeeloanrepaymentid = v_id;
    END IF;

    -- ---- the receivable -------------------------------------------------
    UPDATE poultryemployeeloans l
    SET    totalprincipalrepaid = l.totalprincipalrepaid + v_principal,
           totalinterestrepaid  = l.totalinterestrepaid + v_interest,
           outstandingbalance   = v_newout,
           -- Paid is decided by what is OUTSTANDING, never by comparing what
           -- has been repaid against the principal: with interest those differ.
           status = CASE WHEN v_newout <= 0 THEN 'Paid' ELSE 'Active' END,
           paidat = CASE WHEN v_newout <= 0 THEN v_date ELSE NULL END,
           updatedat = (now() at time zone 'utc')
    WHERE  l.poultryemployeeloanid = p_poultryemployeeloanid AND l.farmid = p_farmid;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 9. Reverse a repayment.
--
-- Append, never delete: the row is marked Reversed, the receivable goes back
-- up, and any cash that came in goes back out on its own row. Both rows stay
-- on the statement, which is the point -- a balance nobody can explain is
-- worse than one that shows its mistakes.
--
-- p_allowpayroll is how section 60 is enforced. A repayment created by payroll
-- must be undone by unapproving that payroll, or the payroll would still claim
-- to have withheld money that the advance no longer shows as repaid. Only 310,
-- reversing the run, passes TRUE.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryemployeeloanrepayment_reverse(
    p_farmid       text,
    p_poultryemployeeloanrepaymentid integer,
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
    SELECT r.status, r.sourcetype, r.poultryemployeeloanid, r.amount,
           r.principalamount, r.interestamount, r.poultrycashaccountid,
           r.poultrypayrollrunid, r.repaymentnumber
    INTO   v_status, v_source, v_loanid, v_amount,
           v_principal, v_interest, v_acct, v_runid, v_number
    FROM   poultryemployeeloanrepayments r
    WHERE  r.poultryemployeeloanrepaymentid = p_poultryemployeeloanrepaymentid
      AND  r.farmid = p_farmid
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Repayment % not found on this farm.', p_poultryemployeeloanrepaymentid;
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
    FROM   poultryemployeeloans l
    JOIN   poultrystaff s ON s.poultrystaffid = l.poultrystaffid
    WHERE  l.poultryemployeeloanid = v_loanid
    FOR UPDATE OF l;

    -- Putting the money back on an advance that has itself been reversed
    -- would resurrect a receivable nobody owes.
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

    UPDATE poultryemployeeloanrepayments
    SET    status = 'Reversed',
           reversedby = p_reversedby,
           reversedat = (now() at time zone 'utc'),
           reversalreason = NULLIF(btrim(p_reason), '')
    WHERE  poultryemployeeloanrepaymentid = p_poultryemployeeloanrepaymentid;

    -- Cash only if cash came in. A payroll repayment never had a cash row, so
    -- its reversal must not invent one either.
    IF v_source <> 'Payroll' AND v_acct IS NOT NULL THEN
        INSERT INTO poultrycashtransactions (
            farmid, poultrycashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, v_acct, (now() at time zone 'utc'), 'EmployeeLoanRepaymentReversal',
            'EmployeeLoanRepaymentReversal', p_poultryemployeeloanrepaymentid, -v_amount,
            'Reversal of advance repayment from ' || COALESCE(v_staffname, 'staff') ||
                ' - ' || COALESCE(v_number, p_poultryemployeeloanrepaymentid::text),
            p_reversedby, p_reversedby, (now() at time zone 'utc'))
        RETURNING poultrycashtransactionid INTO v_txid;

        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance - v_amount,
               updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = v_acct;

        UPDATE poultryemployeeloanrepayments
        SET    reversalcashtransactionid = v_txid
        WHERE  poultryemployeeloanrepaymentid = p_poultryemployeeloanrepaymentid;
    END IF;

    UPDATE poultryemployeeloans l
    SET    totalprincipalrepaid = GREATEST(l.totalprincipalrepaid - v_principal, 0),
           totalinterestrepaid  = GREATEST(l.totalinterestrepaid - v_interest, 0),
           outstandingbalance   = v_newout,
           status = CASE WHEN v_newout <= 0 THEN 'Paid' ELSE 'Active' END,
           paidat = CASE WHEN v_newout <= 0 THEN l.paidat ELSE NULL END,
           updatedat = (now() at time zone 'utc')
    WHERE  l.poultryemployeeloanid = v_loanid;

    RETURN v_txid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 10. The list.
--
-- Server-side filtering and paging, because a farm that has been running for
-- years has more advances than a browser should hold (sections 70-72). The
-- repaid figure is the EFFECTIVE one -- posted repayments only -- so a
-- reversed repayment stops counting the moment it is reversed.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryemployeeloan_getall(
    p_farmid          text,
    p_poultrystaffid  integer DEFAULT NULL,
    p_loantype        text DEFAULT NULL,
    p_status          text DEFAULT NULL,
    p_repaymentmethod text DEFAULT NULL,
    p_fromdate        date DEFAULT NULL,
    p_todate          date DEFAULT NULL,
    p_search          text DEFAULT NULL,
    p_limit           integer DEFAULT 50,
    p_offset          integer DEFAULT 0
) RETURNS TABLE(
    poultryemployeeloanid integer,
    farmid varchar,
    poultrystaffid integer,
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
    poultrycashaccountid integer,
    cashaccountname text,
    paymentmethod text,
    referencenumber text,
    poultrycashtransactionid integer,
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
        FROM   poultryemployeeloans l
        JOIN   poultrystaff s ON s.poultrystaffid = l.poultrystaffid
        LEFT   JOIN poultrycashaccounts a
               ON a.poultrycashaccountid = l.poultrycashaccountid
        WHERE  l.farmid = p_farmid
          AND (p_poultrystaffid  IS NULL OR l.poultrystaffid = p_poultrystaffid)
          AND (p_loantype        IS NULL OR l.loantype = p_loantype)
          -- 'Active' and 'Paid' are the quick filters; anything else is the
          -- literal status.
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
    SELECT b.poultryemployeeloanid, b.farmid, b.poultrystaffid, b.staffname, b.staffrole,
           b.loannumber, b.loantype, b.principalamount,
           b.interestenabled, b.interestamount, b.interestrate, b.interesttype,
           b.totalrepayable, b.disbursementdate, b.repaymentmethod,
           b.defaultpayrolldeduction, b.expectedstartdate, b.expectedenddate,
           b.purpose, b.description, b.notes, b.status, b.paidat,
           (b.totalprincipalrepaid + b.totalinterestrepaid)::numeric(14,2) AS totalrepaid,
           b.totalprincipalrepaid, b.totalinterestrepaid, b.outstandingbalance,
           (SELECT COUNT(*)::integer FROM poultryemployeeloanrepayments r
             WHERE r.poultryemployeeloanid = b.poultryemployeeloanid
               AND r.status = 'Posted') AS repaymentcount,
           b.poultrycashaccountid, b.cashaccountname, b.paymentmethod, b.referencenumber,
           b.poultrycashtransactionid, b.disbursedby, b.disbursedat,
           b.createdby, b.createdat, b.reversedby, b.reversedat, b.reversalreason,
           c.n AS totalcount
    FROM   base b CROSS JOIN counted c
    ORDER  BY b.disbursementdate DESC, b.poultryemployeeloanid DESC
    LIMIT  COALESCE(NULLIF(p_limit, 0), 50) OFFSET COALESCE(p_offset, 0);
$function$;

-- -----------------------------------------------------------------------------
-- 11. One advance's repayment history.
--
-- Reversed rows come back too, and say so. This is the statement behind the
-- balance, and a statement that hides its corrections cannot be reconciled.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryemployeeloanrepayment_getall(
    p_farmid                text,
    p_poultryemployeeloanid integer
) RETURNS TABLE(
    poultryemployeeloanrepaymentid integer,
    poultryemployeeloanid integer,
    poultrystaffid integer,
    staffname text,
    repaymentnumber text,
    repaymentdate timestamp,
    amount numeric,
    principalamount numeric,
    interestamount numeric,
    sourcetype text,
    poultrypayrollrunid integer,
    payrollperiodstart date,
    payrollperiodend date,
    poultrypayrollitemid integer,
    poultrypayrolldeductionid integer,
    poultrycashaccountid integer,
    cashaccountname text,
    paymentmethod text,
    referencenumber text,
    description text,
    notes text,
    balancebefore numeric,
    balanceafter numeric,
    status text,
    poultrycashtransactionid integer,
    reversalcashtransactionid integer,
    createdby text,
    createdat timestamp,
    reversedby text,
    reversedat timestamp,
    reversalreason text
)
LANGUAGE sql
AS $function$
    SELECT r.poultryemployeeloanrepaymentid, r.poultryemployeeloanid, r.poultrystaffid,
           btrim(s.firstname || ' ' || s.lastname),
           r.repaymentnumber, r.repaymentdate,
           r.amount, r.principalamount, r.interestamount, r.sourcetype,
           r.poultrypayrollrunid, pr.periodstart, pr.periodend,
           r.poultrypayrollitemid, r.poultrypayrolldeductionid,
           r.poultrycashaccountid, a.accountname::text,
           r.paymentmethod, r.referencenumber, r.description, r.notes,
           r.balancebefore, r.balanceafter, r.status,
           r.poultrycashtransactionid, r.reversalcashtransactionid,
           r.createdby, r.createdat, r.reversedby, r.reversedat, r.reversalreason
    FROM   poultryemployeeloanrepayments r
    JOIN   poultrystaff s ON s.poultrystaffid = r.poultrystaffid
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = r.poultrycashaccountid
    LEFT   JOIN poultrypayrollruns pr ON pr.poultrypayrollrunid = r.poultrypayrollrunid
    WHERE  r.farmid = p_farmid
      AND  r.poultryemployeeloanid = p_poultryemployeeloanid
    ORDER  BY r.repaymentdate DESC, r.poultryemployeeloanrepaymentid DESC;
$function$;

-- -----------------------------------------------------------------------------
-- 12. The four cards.
--
-- Outstanding is the sum of the live advances and nothing else -- a Draft owes
-- nothing and a Reversed one never did. Disbursed and repaid are for the
-- chosen period; outstanding and the counts are as at now, because a balance
-- is not a period figure.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryemployeeloan_summary(
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
        COALESCE((SELECT SUM(l.outstandingbalance) FROM poultryemployeeloans l
                   WHERE l.farmid = p_farmid
                     AND l.status IN ('Active', 'WrittenOff')), 0)::numeric(14,2),

        COALESCE((SELECT SUM(l.principalamount) FROM poultryemployeeloans l
                   WHERE l.farmid = p_farmid
                     AND l.status NOT IN ('Draft', 'Cancelled', 'Reversed')
                     AND (p_fromdate IS NULL OR l.disbursementdate >= p_fromdate)
                     AND (p_todate   IS NULL OR l.disbursementdate <= p_todate)), 0)::numeric(14,2),

        COALESCE((SELECT SUM(r.amount) FROM poultryemployeeloanrepayments r
                   WHERE r.farmid = p_farmid
                     AND r.status = 'Posted'
                     AND (p_fromdate IS NULL OR r.repaymentdate::date >= p_fromdate)
                     AND (p_todate   IS NULL OR r.repaymentdate::date <= p_todate)), 0)::numeric(14,2),

        (SELECT COUNT(*)::integer FROM poultryemployeeloans l
          WHERE l.farmid = p_farmid AND l.status = 'Active'),

        (SELECT COUNT(DISTINCT l.poultrystaffid)::integer FROM poultryemployeeloans l
          WHERE l.farmid = p_farmid AND l.status = 'Active'),

        (SELECT COUNT(*)::integer FROM poultryemployeeloans l
          WHERE l.farmid = p_farmid AND l.status = 'Paid'),

        (SELECT COUNT(*)::integer FROM poultryemployeeloans l
          WHERE l.farmid = p_farmid AND l.status = 'Draft');
$function$;

-- -----------------------------------------------------------------------------
-- 13. Which advances a payroll deduction may be applied to.
--
-- Section 33, and the reason it is a function rather than a frontend filter:
-- the page shows what this returns, and sppoultryemployeeloanrepayment_record
-- re-checks the same rules at posting time. A caller that skips the dropdown
-- and posts a hand-made id gets the same refusal.
--
-- Also carries the suggested deduction, so the payroll page can offer it
-- without deciding anything (section 36).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryemployeeloan_eligible(
    p_farmid         text,
    p_poultrystaffid integer
) RETURNS TABLE(
    poultryemployeeloanid integer,
    loannumber text,
    loantype text,
    outstandingbalance numeric,
    defaultpayrolldeduction numeric,
    repaymentmethod text,
    disbursementdate date
)
LANGUAGE sql
AS $function$
    SELECT l.poultryemployeeloanid, l.loannumber, l.loantype,
           l.outstandingbalance, l.defaultpayrolldeduction,
           l.repaymentmethod, l.disbursementdate
    FROM   poultryemployeeloans l
    WHERE  l.farmid = p_farmid
      AND  l.poultrystaffid = p_poultrystaffid
      AND  l.status = 'Active'
      AND  l.outstandingbalance > 0
    ORDER  BY l.disbursementdate, l.poultryemployeeloanid;
$function$;

-- -----------------------------------------------------------------------------
-- Verification. Everything this file was supposed to create, and the two
-- invariants worth asserting on the way in.
-- -----------------------------------------------------------------------------
DO $$
DECLARE v_missing text;
BEGIN
    SELECT string_agg(want, ', ')
    INTO   v_missing
    FROM   (VALUES
        ('sppoultryemployeeloan_create'),
        ('sppoultryemployeeloan_disburse'),
        ('sppoultryemployeeloan_update'),
        ('sppoultryemployeeloan_cancel'),
        ('sppoultryemployeeloan_reverse'),
        ('sppoultryemployeeloanrepayment_record'),
        ('sppoultryemployeeloanrepayment_reverse'),
        ('sppoultryemployeeloan_getall'),
        ('sppoultryemployeeloanrepayment_getall'),
        ('sppoultryemployeeloan_summary'),
        ('sppoultryemployeeloan_eligible')
    ) AS w(want)
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = w.want);

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '305: missing function(s): %', v_missing;
    END IF;

    -- No advance may exist whose parts do not add up, and none may owe more
    -- than it was ever worth. Both are constraint-backed; this proves the
    -- constraints are actually on.
    IF EXISTS (SELECT 1 FROM poultryemployeeloans
                WHERE totalrepayable <> principalamount + interestamount) THEN
        RAISE EXCEPTION '305: an advance disagrees with its own total.';
    END IF;
    IF EXISTS (SELECT 1 FROM poultryemployeeloans
                WHERE outstandingbalance > totalrepayable) THEN
        RAISE EXCEPTION '305: an advance owes more than it is worth.';
    END IF;

    RAISE NOTICE '305_PoultryEmployeeLoans: 2 tables, 11 functions, verified.';
END $$;

