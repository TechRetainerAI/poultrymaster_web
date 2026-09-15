-- =============================================================================
-- 254_PoultryLoans.postgres.sql
--
-- Purpose
-- -------
-- Borrowed money: who lent it, how much is still owed, and what each repayment
-- was actually made of.
--
-- Poultry has had "Loan received" as a cash-adjustment type for years. The cash
-- landed and that was the end of it -- no lender, no principal, no schedule,
-- and no way to record paying any of it back. This file makes a loan a thing
-- the business owes.
--
-- THE THREE RULES A REPAYMENT HAS TO OBEY
-- =======================================
--
-- 1. PRINCIPAL IS NOT AN EXPENSE.
--    Repaying 10,000 of principal does not make the business 10,000 poorer --
--    it swaps cash for a smaller debt. Only the interest and the fees are the
--    cost of borrowing, and only they reach the P&L.
--
-- 2. CASH MOVES ONCE, FOR THE TOTAL.
--    A payment of 10,000 principal + 2,000 interest + 500 fee takes 12,500 out
--    of the account. ONE cash row of 12,500 -- not one of 12,500 and two more
--    of 2,000 and 500 for the expense rows. This is the failure the spec calls
--    out by name, and the check file counts the rows to prove it.
--
-- 3. A LENDER IS NOT A SUPPLIER.
--    No supplier payment, no supplier allocation, no supplier balance. The
--    liability is a loan, and it is reduced by recording a loan payment.
--
-- HOW RULES 1 AND 2 ARE BOTH KEPT AT ONCE
-- =======================================
-- The interest and fee expense rows are written with paymentmethod = 'NonCash'.
-- That marker already exists and already means exactly this: a cost recorded
-- without money moving for THIS row (internal use has used it since migration
-- 216). Following the marker through the three places it matters:
--
--   sppoultrycashflow_rows   EXCLUDES NonCash from the expense arm, so the
--                            2,500 does not land twice; the loan arm below
--                            reports the full 12,500 as one Loan Repayment.
--   fnpoultrypayables        EXCLUDES NonCash, so interest never turns the
--                            lender into a creditor on Supplier Balances.
--   sppoultryexpensecash_*   EXCLUDE NonCash, so no cash row is ever synced
--                            from these expenses.
--   sppoultryreport_profitloss  does NOT filter NonCash -- it sums e.amount --
--                            so interest and fees DO count as expenses.
--
-- That is the whole trick, and it is why nothing here needed a new flag: the
-- codebase already had a word for "recorded, but the money moved elsewhere".
--
-- WHAT REVERSAL DOES ABOUT THE EXPENSES
-- -------------------------------------
-- expense has no status column and nothing in this codebase deletes a financial
-- row, so a reversal writes COMPENSATING expense rows -- same category, negative
-- amount, sourcetype 'LoanPaymentReversal'. The P&L sums amounts, so the pair
-- nets to zero; both rows stay on the record. Deleting them would have been
-- tidier to read and wrong to keep.
--
-- ORIGINAL PRINCIPAL vs AMOUNT RECEIVED
-- -------------------------------------
-- A lender that withholds a 2,000 arrangement fee on a 100,000 loan pays out
-- 98,000, and the business still owes 100,000. Both numbers are stored, cash in
-- is the amount RECEIVED, and outstanding principal starts at the ORIGINAL.
-- The difference is not automatically expensed: only the owner knows whether it
-- was a fee or a rounding, and inventing a 2,000 expense nobody entered is
-- worse than leaving it to them.
--
-- EFFECT ON TODAY'S NUMBERS: none. Two new tables, new functions, and two more
-- arms on sppoultrycashflow_rows that return nothing until a loan exists.
--
-- Order: after 253.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Drop by NAME, not by signature.
-- -----------------------------------------------------------------------------
DO $drop$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM   pg_proc p
        JOIN   pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('sppoultryloan_create',
                             'sppoultryloan_update',
                             'sppoultryloan_cancel',
                             'sppoultryloan_getall',
                             'sppoultryloan_summary',
                             'sppoultryloanpayment_record',
                             'sppoultryloanpayment_reverse',
                             'sppoultryloanpayment_getall')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- -----------------------------------------------------------------------------
-- 1. The loan.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poultryloans (
    poultryloanid        serial PRIMARY KEY,
    farmid               varchar(450) NOT NULL,
    loannumber           text NULL,

    lendername           text NOT NULL,
    lendertype           text NOT NULL DEFAULT 'Other'
                         CHECK (lendertype IN ('Bank', 'FinancialInstitution', 'Individual',
                                               'Owner', 'FamilyFriend', 'Supplier', 'Other')),
    accountnumber        text NULL,

    loandate             date NOT NULL,
    -- What is OWED. May exceed what arrived: see the header.
    originalprincipal    numeric(14,2) NOT NULL CHECK (originalprincipal > 0),
    -- What actually ARRIVED in the bank.
    amountreceived       numeric(14,2) NOT NULL DEFAULT 0 CHECK (amountreceived >= 0),

    interestrate         numeric(9,4) NULL,
    interesttype         text NULL CHECK (interesttype IS NULL OR
                         interesttype IN ('Simple', 'ReducingBalance', 'Flat', 'Unknown')),
    termmonths           integer NULL CHECK (termmonths IS NULL OR termmonths > 0),
    paymentfrequency     text NULL CHECK (paymentfrequency IS NULL OR
                         paymentfrequency IN ('Weekly', 'BiWeekly', 'Monthly', 'Quarterly', 'Custom')),

    startdate            date NOT NULL,
    enddate              date NULL,
    nextpaymentdate      date NULL,

    poultrycashaccountid integer NULL,

    -- Running totals. Maintained by the payment functions, never edited.
    outstandingprincipal numeric(14,2) NOT NULL DEFAULT 0,
    totalprincipalrepaid numeric(14,2) NOT NULL DEFAULT 0,
    totalinterestpaid    numeric(14,2) NOT NULL DEFAULT 0,
    totalfeespaid        numeric(14,2) NOT NULL DEFAULT 0,

    status               text NOT NULL DEFAULT 'Active'
                         CHECK (status IN ('Draft', 'Active', 'PaidOff', 'Overdue',
                                           'Cancelled', 'Reversed')),
    paidoffdate          date NULL,
    notes                text NULL,

    -- The single cash row the disbursement wrote.
    poultrycashtransactionid integer NULL,

    createdby      text NULL,
    createdat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby      text NULL,
    updatedat      timestamp NULL,
    reversedby     text NULL,
    reversedat     timestamp NULL,
    reversalreason text NULL
);

CREATE INDEX IF NOT EXISTS ix_poultryloans_farm_status
    ON poultryloans (farmid, status, startdate DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryloans_number
    ON poultryloans (farmid, loannumber) WHERE loannumber IS NOT NULL;

COMMENT ON COLUMN poultryloans.originalprincipal IS
    'What is OWED. May exceed amountreceived when the lender withheld a fee.';
COMMENT ON COLUMN poultryloans.amountreceived IS
    'What actually ARRIVED. This, not the principal, is the cash in.';
COMMENT ON COLUMN poultryloans.outstandingprincipal IS
    'Maintained by the payment functions. Payoff is decided by THIS reaching '
    'zero, never by comparing total paid against the original principal -- '
    'those differ by every cedi of interest.';

-- -----------------------------------------------------------------------------
-- 2. The repayment.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poultryloanpayments (
    poultryloanpaymentid serial PRIMARY KEY,
    farmid               varchar(450) NOT NULL,
    poultryloanid        integer NOT NULL REFERENCES poultryloans (poultryloanid),
    paymentnumber        text NULL,
    paymentdate          timestamp NOT NULL DEFAULT (now() at time zone 'utc'),

    -- The four parts, and their sum. Stored rather than derived so a historic
    -- payment still reads correctly if the split rules ever change.
    totalamount     numeric(14,2) NOT NULL CHECK (totalamount > 0),
    principalamount numeric(14,2) NOT NULL DEFAULT 0 CHECK (principalamount >= 0),
    interestamount  numeric(14,2) NOT NULL DEFAULT 0 CHECK (interestamount >= 0),
    feeamount       numeric(14,2) NOT NULL DEFAULT 0 CHECK (feeamount >= 0),
    otheramount     numeric(14,2) NOT NULL DEFAULT 0 CHECK (otheramount >= 0),

    poultrycashaccountid integer NOT NULL,
    paymentmethod        text NULL,
    referencenumber      text NULL,
    notes                text NULL,

    status text NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),

    -- The ONE cash row, and the expense rows for the cost of borrowing.
    poultrycashtransactionid integer NULL,
    interestexpenseid        integer NULL,
    feeexpenseid             integer NULL,
    reversalcashtransactionid integer NULL,

    createdby      text NULL,
    createdat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby     text NULL,
    reversedat     timestamp NULL,
    reversalreason text NULL,

    -- The arithmetic can never be wrong, because the row cannot exist if it is.
    CONSTRAINT ck_poultryloanpayments_total
        CHECK (totalamount = principalamount + interestamount + feeamount + otheramount)
);

CREATE INDEX IF NOT EXISTS ix_poultryloanpayments_loan
    ON poultryloanpayments (poultryloanid, paymentdate DESC);
CREATE INDEX IF NOT EXISTS ix_poultryloanpayments_farm
    ON poultryloanpayments (farmid, status, paymentdate DESC);

COMMENT ON CONSTRAINT ck_poultryloanpayments_total ON poultryloanpayments IS
    'The split must add up. Enforced by the table so no code path can write a '
    'payment whose parts disagree with its total.';

-- -----------------------------------------------------------------------------
-- 3. Record a loan, and take the money if it has arrived.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryloan_create(
    p_farmid               text,
    p_lendername           text,
    p_originalprincipal    numeric,
    p_startdate            date,
    p_amountreceived       numeric DEFAULT 0,
    p_poultrycashaccountid integer DEFAULT NULL,
    p_lendertype           text DEFAULT 'Other',
    p_accountnumber        text DEFAULT NULL,
    p_loandate             date DEFAULT NULL,
    p_interestrate         numeric DEFAULT NULL,
    p_interesttype         text DEFAULT NULL,
    p_termmonths           integer DEFAULT NULL,
    p_paymentfrequency     text DEFAULT NULL,
    p_enddate              date DEFAULT NULL,
    p_nextpaymentdate      date DEFAULT NULL,
    p_status               text DEFAULT 'Active',
    p_notes                text DEFAULT NULL,
    p_createdby            text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id      integer;
    v_date    date := COALESCE(p_loandate, p_startdate);
    v_txid    integer;
    v_balance numeric;
BEGIN
    IF COALESCE(btrim(p_lendername), '') = '' THEN
        RAISE EXCEPTION 'A lender is required.';
    END IF;
    IF COALESCE(p_originalprincipal, 0) <= 0 THEN
        RAISE EXCEPTION 'The loan principal must be greater than zero.';
    END IF;
    IF COALESCE(p_amountreceived, 0) < 0 THEN
        RAISE EXCEPTION 'The amount received cannot be negative.';
    END IF;
    -- Receiving MORE than was borrowed is not a loan, it is a data-entry slip.
    IF COALESCE(p_amountreceived, 0) > p_originalprincipal THEN
        RAISE EXCEPTION 'The amount received (%) cannot exceed the principal (%).',
            p_amountreceived, p_originalprincipal;
    END IF;
    IF p_status NOT IN ('Draft', 'Active') THEN
        RAISE EXCEPTION 'A new loan starts as Draft or Active, not %.', p_status;
    END IF;

    IF COALESCE(p_amountreceived, 0) > 0 THEN
        IF p_poultrycashaccountid IS NULL THEN
            RAISE EXCEPTION 'Say which cash account received the money.';
        END IF;
        SELECT a.currentbalance INTO v_balance
        FROM   poultrycashaccounts a
        WHERE  a.poultrycashaccountid = p_poultrycashaccountid AND a.farmid = p_farmid;
        IF v_balance IS NULL THEN
            RAISE EXCEPTION 'Cash account does not exist or does not belong to this farm.';
        END IF;
    END IF;

    INSERT INTO poultryloans (
        farmid, lendername, lendertype, accountnumber, loandate,
        originalprincipal, amountreceived, interestrate, interesttype, termmonths,
        paymentfrequency, startdate, enddate, nextpaymentdate, poultrycashaccountid,
        -- The debt starts at what is OWED, not at what arrived.
        outstandingprincipal, status, notes, createdby)
    VALUES (
        p_farmid, btrim(p_lendername), COALESCE(p_lendertype, 'Other'),
        NULLIF(btrim(p_accountnumber), ''), v_date,
        p_originalprincipal, COALESCE(p_amountreceived, 0),
        p_interestrate, p_interesttype, p_termmonths,
        p_paymentfrequency, p_startdate, p_enddate, p_nextpaymentdate,
        p_poultrycashaccountid,
        p_originalprincipal, p_status, NULLIF(btrim(p_notes), ''), p_createdby)
    RETURNING poultryloanid INTO v_id;

    UPDATE poultryloans
    SET    loannumber = 'LN-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  poultryloanid = v_id;

    -- The disbursement. ONE cash row, and only if the money actually arrived.
    IF COALESCE(p_amountreceived, 0) > 0 THEN
        INSERT INTO poultrycashtransactions (
            farmid, poultrycashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, p_poultrycashaccountid, v_date::timestamp, 'LoanReceived',
            'Loan', v_id, p_amountreceived,
            'Loan received from ' || btrim(p_lendername),
            p_createdby, p_createdby, (now() at time zone 'utc'))
        RETURNING poultrycashtransactionid INTO v_txid;

        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance + p_amountreceived,
               updatedat = (now() at time zone 'utc')
        WHERE  a.poultrycashaccountid = p_poultrycashaccountid;

        UPDATE poultryloans SET poultrycashtransactionid = v_txid WHERE poultryloanid = v_id;
    END IF;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Edit the descriptive fields.
--
-- Deliberately cannot touch principal, amount received, outstanding or any
-- running total: those are consequences of postings, and letting a form rewrite
-- them is how a loan's history stops matching its payments.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryloan_update(
    p_poultryloanid    integer,
    p_farmid           text,
    p_lendername       text DEFAULT NULL,
    p_lendertype       text DEFAULT NULL,
    p_accountnumber    text DEFAULT NULL,
    p_interestrate     numeric DEFAULT NULL,
    p_interesttype     text DEFAULT NULL,
    p_termmonths       integer DEFAULT NULL,
    p_paymentfrequency text DEFAULT NULL,
    p_enddate          date DEFAULT NULL,
    p_nextpaymentdate  date DEFAULT NULL,
    p_notes            text DEFAULT NULL,
    p_updatedby        text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
BEGIN
    SELECT l.status INTO v_status FROM poultryloans l
    WHERE  l.poultryloanid = p_poultryloanid AND l.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Loan % not found.', p_poultryloanid;
    END IF;
    IF v_status IN ('Cancelled', 'Reversed') THEN
        RAISE EXCEPTION 'A % loan cannot be edited.', v_status;
    END IF;

    UPDATE poultryloans l
    SET    lendername       = COALESCE(NULLIF(btrim(p_lendername), ''), l.lendername),
           lendertype       = COALESCE(p_lendertype, l.lendertype),
           accountnumber    = COALESCE(NULLIF(btrim(p_accountnumber), ''), l.accountnumber),
           interestrate     = COALESCE(p_interestrate, l.interestrate),
           interesttype     = COALESCE(p_interesttype, l.interesttype),
           termmonths       = COALESCE(p_termmonths, l.termmonths),
           paymentfrequency = COALESCE(p_paymentfrequency, l.paymentfrequency),
           enddate          = COALESCE(p_enddate, l.enddate),
           nextpaymentdate  = COALESCE(p_nextpaymentdate, l.nextpaymentdate),
           notes            = COALESCE(NULLIF(btrim(p_notes), ''), l.notes),
           updatedby        = p_updatedby,
           updatedat        = (now() at time zone 'utc')
    WHERE  l.poultryloanid = p_poultryloanid AND l.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Cancel a loan that never happened.
--
-- Only while nothing has been repaid. A loan with payments against it has a
-- history, and cancelling it would orphan them.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryloan_cancel(
    p_poultryloanid integer,
    p_farmid        text,
    p_reason        text,
    p_cancelledby   text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status   text;
    v_received numeric;
    v_acct     integer;
    v_paid     integer;
    v_now      timestamp := (now() at time zone 'utc');
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to cancel a loan.';
    END IF;

    SELECT l.status, l.amountreceived, l.poultrycashaccountid
    INTO   v_status, v_received, v_acct
    FROM   poultryloans l
    WHERE  l.poultryloanid = p_poultryloanid AND l.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Loan % not found.', p_poultryloanid;
    END IF;
    IF v_status IN ('Cancelled', 'Reversed') THEN
        RAISE EXCEPTION 'This loan is already %.', v_status;
    END IF;

    SELECT COUNT(*) INTO v_paid FROM poultryloanpayments p
    WHERE  p.poultryloanid = p_poultryloanid AND p.status = 'Posted';
    IF v_paid > 0 THEN
        RAISE EXCEPTION 'This loan has % posted repayment(s); reverse them before cancelling it.', v_paid;
    END IF;

    -- If money was disbursed it has to go back, or the cash account keeps cash
    -- from a loan that no longer exists.
    IF COALESCE(v_received, 0) > 0 THEN
        INSERT INTO poultrycashtransactions (
            farmid, poultrycashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, v_acct, v_now, 'LoanReceivedReversal',
            'Loan', p_poultryloanid, -v_received,
            'Cancelled loan ' || p_poultryloanid::text,
            p_cancelledby, p_cancelledby, v_now);

        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance - v_received, updatedat = v_now
        WHERE  a.poultrycashaccountid = v_acct;
    END IF;

    UPDATE poultryloans l
    SET    status = 'Cancelled', outstandingprincipal = 0,
           reversedby = p_cancelledby, reversedat = v_now,
           reversalreason = btrim(p_reason), updatedat = v_now
    WHERE  l.poultryloanid = p_poultryloanid AND l.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Record a repayment.
--
-- The whole chunk comes down to this function. It writes, in order:
--
--   one loan payment row          the split, checked by the table constraint
--   the loan's running totals     principal down, interest and fees up
--   ONE cash row for the TOTAL    the only money movement
--   an interest expense           NonCash, so it costs without paying twice
--   a fee expense                 same
--
-- and nothing else. No supplier payment, no allocation, no second cash row.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryloanpayment_record(
    p_farmid               text,
    p_poultryloanid        integer,
    p_poultrycashaccountid integer,
    p_principalamount      numeric DEFAULT 0,
    p_interestamount       numeric DEFAULT 0,
    p_feeamount            numeric DEFAULT 0,
    p_otheramount          numeric DEFAULT 0,
    p_paymentdate          timestamp DEFAULT NULL,
    p_paymentmethod        text DEFAULT NULL,
    p_referencenumber      text DEFAULT NULL,
    p_notes                text DEFAULT NULL,
    p_nextpaymentdate      date DEFAULT NULL,
    p_createdby            text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id          integer;
    v_date        timestamp := COALESCE(p_paymentdate, (now() at time zone 'utc'));
    v_principal   numeric := COALESCE(p_principalamount, 0);
    v_interest    numeric := COALESCE(p_interestamount, 0);
    v_fee         numeric := COALESCE(p_feeamount, 0);
    v_other       numeric := COALESCE(p_otheramount, 0);
    v_total       numeric;
    v_status      text;
    v_outstanding numeric;
    v_lender      text;
    v_number      text;
    v_balance     numeric;
    v_allowneg    boolean;
    v_txid        integer;
    v_intexp      integer;
    v_feeexp      integer;
    v_newout      numeric;
BEGIN
    v_total := v_principal + v_interest + v_fee + v_other;

    IF v_principal < 0 OR v_interest < 0 OR v_fee < 0 OR v_other < 0 THEN
        RAISE EXCEPTION 'No part of a repayment can be negative.';
    END IF;
    IF v_total <= 0 THEN
        RAISE EXCEPTION 'A repayment must be greater than zero.';
    END IF;

    SELECT l.status, l.outstandingprincipal, l.lendername, l.loannumber
    INTO   v_status, v_outstanding, v_lender, v_number
    FROM   poultryloans l
    WHERE  l.poultryloanid = p_poultryloanid AND l.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Loan % not found.', p_poultryloanid;
    END IF;
    IF v_status IN ('Cancelled', 'Reversed') THEN
        RAISE EXCEPTION 'A % loan cannot be repaid.', v_status;
    END IF;
    IF v_status = 'Draft' THEN
        RAISE EXCEPTION 'Activate the loan before recording repayments against it.';
    END IF;

    -- Paying off more principal than is owed would drive the debt negative and
    -- turn the lender into a debtor.
    IF v_principal > v_outstanding THEN
        RAISE EXCEPTION 'Principal of % is more than the % still outstanding.',
            v_principal, v_outstanding;
    END IF;

    SELECT a.currentbalance, a.allownegativebalance
    INTO   v_balance, v_allowneg
    FROM   poultrycashaccounts a
    WHERE  a.poultrycashaccountid = p_poultrycashaccountid AND a.farmid = p_farmid;

    IF v_balance IS NULL THEN
        RAISE EXCEPTION 'Cash account does not exist or does not belong to this farm.';
    END IF;
    IF v_allowneg = FALSE AND (v_balance - v_total) < 0 THEN
        RAISE EXCEPTION 'This repayment would take the cash account below zero.';
    END IF;

    INSERT INTO poultryloanpayments (
        farmid, poultryloanid, paymentdate, totalamount,
        principalamount, interestamount, feeamount, otheramount,
        poultrycashaccountid, paymentmethod, referencenumber, notes,
        status, createdby)
    VALUES (
        p_farmid, p_poultryloanid, v_date, v_total,
        v_principal, v_interest, v_fee, v_other,
        p_poultrycashaccountid, NULLIF(btrim(p_paymentmethod), ''),
        NULLIF(btrim(p_referencenumber), ''), NULLIF(btrim(p_notes), ''),
        'Posted', p_createdby)
    RETURNING poultryloanpaymentid INTO v_id;

    UPDATE poultryloanpayments
    SET    paymentnumber = 'LP-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  poultryloanpaymentid = v_id;

    -- ---- ONE cash row, for the TOTAL ------------------------------------
    INSERT INTO poultrycashtransactions (
        farmid, poultrycashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
    VALUES (
        p_farmid, p_poultrycashaccountid, v_date, 'LoanRepayment',
        'LoanPayment', v_id, -v_total,
        'Loan repayment to ' || COALESCE(v_lender, 'lender'),
        p_createdby, p_createdby, (now() at time zone 'utc'))
    RETURNING poultrycashtransactionid INTO v_txid;

    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance - v_total, updatedat = (now() at time zone 'utc')
    WHERE  a.poultrycashaccountid = p_poultrycashaccountid;

    -- ---- the cost of borrowing, as expenses that move no further cash -----
    -- paymentmethod 'NonCash' is what keeps the 12,500 from being counted as
    -- 15,000: the cash-flow expense arm skips these rows, the loan arm reports
    -- the full total, and the P&L still sees the interest and the fee.
    IF v_interest > 0 THEN
        INSERT INTO expense (
            farmid, expensedate, category, description, amount, paymentmethod,
            sourcetype, sourceid, poultrycashaccountid, amountpaid, userid)
        VALUES (
            p_farmid::uuid, v_date, 'Interest Expense',
            'Interest on loan ' || COALESCE(v_number, p_poultryloanid::text),
            v_interest, 'NonCash', 'LoanPayment', v_id, NULL, v_interest, p_createdby)
        RETURNING expenseid INTO v_intexp;
    END IF;

    IF v_fee > 0 THEN
        INSERT INTO expense (
            farmid, expensedate, category, description, amount, paymentmethod,
            sourcetype, sourceid, poultrycashaccountid, amountpaid, userid)
        VALUES (
            p_farmid::uuid, v_date, 'Loan Fee',
            'Fee on loan ' || COALESCE(v_number, p_poultryloanid::text),
            v_fee, 'NonCash', 'LoanPayment', v_id, NULL, v_fee, p_createdby)
        RETURNING expenseid INTO v_feeexp;
    END IF;

    UPDATE poultryloanpayments
    SET    poultrycashtransactionid = v_txid,
           interestexpenseid = v_intexp,
           feeexpenseid = v_feeexp
    WHERE  poultryloanpaymentid = v_id;

    -- ---- the debt ---------------------------------------------------------
    v_newout := v_outstanding - v_principal;

    UPDATE poultryloans l
    SET    outstandingprincipal = v_newout,
           totalprincipalrepaid = l.totalprincipalrepaid + v_principal,
           totalinterestpaid    = l.totalinterestpaid + v_interest,
           totalfeespaid        = l.totalfeespaid + v_fee,
           nextpaymentdate      = COALESCE(p_nextpaymentdate, l.nextpaymentdate),
           -- Paid off is decided by what is OUTSTANDING, never by comparing
           -- total paid against the original principal: those differ by every
           -- cedi of interest ever charged.
           status = CASE WHEN v_newout <= 0 THEN 'PaidOff' ELSE 'Active' END,
           paidoffdate = CASE WHEN v_newout <= 0 THEN v_date::date ELSE NULL END,
           updatedat = (now() at time zone 'utc')
    WHERE  l.poultryloanid = p_poultryloanid AND l.farmid = p_farmid;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 7. Reverse a repayment.
--
-- Everything the posting did, undone by appending rather than deleting:
-- the debt goes back up, the cash comes back, and the interest and fee expenses
-- are cancelled by compensating negative rows. Both the original expense and
-- its cancellation stay on the record.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryloanpayment_reverse(
    p_poultryloanpaymentid integer,
    p_farmid               text,
    p_reason               text,
    p_reversedby           text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_loan      integer;
    v_status    text;
    v_total     numeric;
    v_principal numeric;
    v_interest  numeric;
    v_fee       numeric;
    v_acct      integer;
    v_number    text;
    v_loannum   text;
    v_txid      integer;
    v_now       timestamp := (now() at time zone 'utc');
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a repayment.';
    END IF;

    SELECT p.poultryloanid, p.status, p.totalamount, p.principalamount,
           p.interestamount, p.feeamount, p.poultrycashaccountid, p.paymentnumber
    INTO   v_loan, v_status, v_total, v_principal, v_interest, v_fee, v_acct, v_number
    FROM   poultryloanpayments p
    WHERE  p.poultryloanpaymentid = p_poultryloanpaymentid AND p.farmid = p_farmid;

    IF v_loan IS NULL THEN
        RAISE EXCEPTION 'Loan payment % not found.', p_poultryloanpaymentid;
    END IF;
    IF v_status <> 'Posted' THEN
        RAISE EXCEPTION 'Only a posted repayment can be reversed (this one is %).', v_status;
    END IF;

    SELECT l.loannumber INTO v_loannum FROM poultryloans l WHERE l.poultryloanid = v_loan;

    -- The money comes back into the account it left.
    INSERT INTO poultrycashtransactions (
        farmid, poultrycashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
    VALUES (
        p_farmid, v_acct, v_now, 'LoanRepaymentReversal',
        'LoanPayment', p_poultryloanpaymentid, v_total,
        'Reversal of repayment ' || COALESCE(v_number, p_poultryloanpaymentid::text),
        p_reversedby, p_reversedby, v_now)
    RETURNING poultrycashtransactionid INTO v_txid;

    UPDATE poultrycashaccounts a
    SET    currentbalance = a.currentbalance + v_total, updatedat = v_now
    WHERE  a.poultrycashaccountid = v_acct;

    -- The cost of borrowing is cancelled by a compensating row, not by deletion.
    -- expense has no status column and nothing here deletes a financial record.
    IF v_interest > 0 THEN
        INSERT INTO expense (
            farmid, expensedate, category, description, amount, paymentmethod,
            sourcetype, sourceid, poultrycashaccountid, amountpaid, userid)
        VALUES (
            p_farmid::uuid, v_now, 'Interest Expense',
            'Reversal: interest on loan ' || COALESCE(v_loannum, v_loan::text),
            -v_interest, 'NonCash', 'LoanPaymentReversal', p_poultryloanpaymentid,
            NULL, -v_interest, p_reversedby);
    END IF;

    IF v_fee > 0 THEN
        INSERT INTO expense (
            farmid, expensedate, category, description, amount, paymentmethod,
            sourcetype, sourceid, poultrycashaccountid, amountpaid, userid)
        VALUES (
            p_farmid::uuid, v_now, 'Loan Fee',
            'Reversal: fee on loan ' || COALESCE(v_loannum, v_loan::text),
            -v_fee, 'NonCash', 'LoanPaymentReversal', p_poultryloanpaymentid,
            NULL, -v_fee, p_reversedby);
    END IF;

    -- The debt goes back up, and a loan that was paid off is live again.
    UPDATE poultryloans l
    SET    outstandingprincipal = l.outstandingprincipal + v_principal,
           totalprincipalrepaid = GREATEST(l.totalprincipalrepaid - v_principal, 0),
           totalinterestpaid    = GREATEST(l.totalinterestpaid - v_interest, 0),
           totalfeespaid        = GREATEST(l.totalfeespaid - v_fee, 0),
           status = CASE WHEN l.status = 'PaidOff' AND (l.outstandingprincipal + v_principal) > 0
                         THEN 'Active' ELSE l.status END,
           paidoffdate = CASE WHEN (l.outstandingprincipal + v_principal) > 0
                              THEN NULL ELSE l.paidoffdate END,
           updatedat = v_now
    WHERE  l.poultryloanid = v_loan;

    UPDATE poultryloanpayments p
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = btrim(p_reason), reversalcashtransactionid = v_txid
    WHERE  p.poultryloanpaymentid = p_poultryloanpaymentid AND p.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 8. Reads.
--
-- Overdue is DERIVED, never stored: a loan is overdue when its next payment
-- date has passed and it still owes something. Stamping a status would need a
-- nightly job this system does not have, and would be stale the moment one ran.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryloan_getall(
    p_farmid text,
    p_status text DEFAULT NULL
) RETURNS TABLE(
    poultryloanid        integer,
    farmid               text,
    loannumber           text,
    lendername           text,
    lendertype           text,
    accountnumber        text,
    loandate             date,
    originalprincipal    numeric,
    amountreceived       numeric,
    interestrate         numeric,
    interesttype         text,
    termmonths           integer,
    paymentfrequency     text,
    startdate            date,
    enddate              date,
    nextpaymentdate      date,
    poultrycashaccountid integer,
    accountname          text,
    outstandingprincipal numeric,
    totalprincipalrepaid numeric,
    totalinterestpaid    numeric,
    totalfeespaid        numeric,
    status               text,
    isoverdue            boolean,
    paymentcount         integer,
    paidoffdate          date,
    notes                text,
    createdby            text,
    createdat            timestamp,
    reversalreason       text
)
LANGUAGE sql STABLE
AS $function$
    SELECT l.poultryloanid, l.farmid::text, l.loannumber::text,
           l.lendername::text, l.lendertype::text, l.accountnumber::text,
           l.loandate, l.originalprincipal, l.amountreceived,
           l.interestrate, l.interesttype::text, l.termmonths, l.paymentfrequency::text,
           l.startdate, l.enddate, l.nextpaymentdate,
           l.poultrycashaccountid, a.accountname::text,
           l.outstandingprincipal, l.totalprincipalrepaid,
           l.totalinterestpaid, l.totalfeespaid,
           l.status::text,
           (l.status = 'Active'
            AND l.nextpaymentdate IS NOT NULL
            AND l.nextpaymentdate < CURRENT_DATE
            AND l.outstandingprincipal > 0) AS isoverdue,
           (SELECT COUNT(*)::int FROM poultryloanpayments p
             WHERE p.poultryloanid = l.poultryloanid AND p.status = 'Posted'),
           l.paidoffdate, l.notes::text, l.createdby::text, l.createdat,
           l.reversalreason::text
    FROM   poultryloans l
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = l.poultrycashaccountid
    WHERE  l.farmid = p_farmid
      AND  (p_status IS NULL OR p_status = 'All' OR l.status = p_status)
    ORDER  BY l.startdate DESC, l.poultryloanid DESC;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryloanpayment_getall(
    p_farmid text,
    p_loanid integer DEFAULT NULL,
    p_from   date DEFAULT NULL,
    p_to     date DEFAULT NULL
) RETURNS TABLE(
    poultryloanpaymentid integer,
    farmid               text,
    poultryloanid        integer,
    loannumber           text,
    lendername           text,
    paymentnumber        text,
    paymentdate          timestamp,
    totalamount          numeric,
    principalamount      numeric,
    interestamount       numeric,
    feeamount            numeric,
    otheramount          numeric,
    poultrycashaccountid integer,
    accountname          text,
    paymentmethod        text,
    referencenumber      text,
    notes                text,
    status               text,
    interestexpenseid    integer,
    feeexpenseid         integer,
    createdby            text,
    createdat            timestamp,
    reversedby           text,
    reversedat           timestamp,
    reversalreason       text
)
LANGUAGE sql STABLE
AS $function$
    SELECT p.poultryloanpaymentid, p.farmid::text, p.poultryloanid,
           l.loannumber::text, l.lendername::text,
           p.paymentnumber::text, p.paymentdate, p.totalamount,
           p.principalamount, p.interestamount, p.feeamount, p.otheramount,
           p.poultrycashaccountid, a.accountname::text,
           p.paymentmethod::text, p.referencenumber::text, p.notes::text,
           p.status::text, p.interestexpenseid, p.feeexpenseid,
           p.createdby::text, p.createdat,
           p.reversedby::text, p.reversedat, p.reversalreason::text
    FROM   poultryloanpayments p
    JOIN   poultryloans l ON l.poultryloanid = p.poultryloanid
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = p.poultrycashaccountid
    WHERE  p.farmid = p_farmid
      AND  (p_loanid IS NULL OR p.poultryloanid = p_loanid)
      AND  (p_from IS NULL OR p.paymentdate >= p_from::timestamp)
      AND  (p_to   IS NULL OR p.paymentdate <  (p_to + 1)::timestamp)
    ORDER  BY p.paymentdate DESC, p.poultryloanpaymentid DESC;
$function$;

-- The cards on the page.
CREATE OR REPLACE FUNCTION public.sppoultryloan_summary(p_farmid text)
RETURNS TABLE(
    activeloans          integer,
    totalborrowed        numeric,
    totalreceived        numeric,
    outstandingprincipal numeric,
    totalprincipalrepaid numeric,
    totalinterestpaid    numeric,
    totalfeespaid        numeric,
    overdueloans         integer,
    nextpaymentdate      date
)
LANGUAGE sql STABLE
AS $function$
    SELECT
        COUNT(*) FILTER (WHERE l.status IN ('Active', 'Overdue'))::int,
        COALESCE(SUM(l.originalprincipal) FILTER (WHERE l.status <> 'Cancelled'), 0)::numeric(14,2),
        COALESCE(SUM(l.amountreceived)    FILTER (WHERE l.status <> 'Cancelled'), 0)::numeric(14,2),
        COALESCE(SUM(l.outstandingprincipal), 0)::numeric(14,2),
        COALESCE(SUM(l.totalprincipalrepaid), 0)::numeric(14,2),
        COALESCE(SUM(l.totalinterestpaid), 0)::numeric(14,2),
        COALESCE(SUM(l.totalfeespaid), 0)::numeric(14,2),
        COUNT(*) FILTER (WHERE l.status = 'Active'
                           AND l.nextpaymentdate IS NOT NULL
                           AND l.nextpaymentdate < CURRENT_DATE
                           AND l.outstandingprincipal > 0)::int,
        MIN(l.nextpaymentdate) FILTER (WHERE l.status = 'Active' AND l.outstandingprincipal > 0)
    FROM poultryloans l
    WHERE l.farmid = p_farmid;
$function$;

-- -----------------------------------------------------------------------------
-- 9. Cash Flow learns to read loans.
--
-- Reproduced from the LIVE definition of sppoultrycashflow_rows -- which now
-- includes 253's owner-money arm. Every existing arm is byte for byte what it
-- was; the only change is the two arms above the legacy capital one.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultrycashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
 RETURNS TABLE(rowsource text, offledger boolean, sourcerowid integer, cashaccountid integer, accountname text, transactiondate timestamp without time zone, transactiontype text, sourcetype text, sourceid integer, istransfer boolean, amount numeric, description text, flowgroup text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_tbl  text;
    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);
    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);
BEGIN
    -- ---- 1. customer receipts, dated when the money arrived -----------------
    -- This is the leg that makes it a CASH flow rather than a sales report. A
    -- January sale part-paid in August belongs in August, and poultrypayments is
    -- the only place that date exists (145_PoultryPayments.sql:36).
    RETURN QUERY
    SELECT 'Receipt'::text,
           FALSE,
           p.poultrypaymentid,
           NULL::integer,
           NULL::text,
           p.paymentdate,
           'CashIn'::text,
           'CustomerPayment'::text,
           p.saleid,
           FALSE,
           COALESCE(p.amount, 0)::numeric,
           COALESCE(NULLIF(btrim(p.note), ''),
                    NULLIF(btrim(p.reference), ''),
                    'Payment for sale #' || p.saleid::text)::text,
           'OperatingIn'::text
    FROM   poultrypayments p
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) <> 0
      -- A REVERSED payment is money that came back. 222/227 added this column and
      -- flip it on reversal rather than deleting the row, so without this filter
      -- the report counts a refunded receipt as income for ever.
      AND  COALESCE(p.status, 'Posted') = 'Posted' 
      AND  p.paymentdate >= v_from
      AND  p.paymentdate <= v_to;

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
    FROM   sale s
    CROSS  JOIN LATERAL (
        SELECT ROUND(
                   CASE WHEN COALESCE(s.paid, false)
                        THEN COALESCE(s.totalamount, 0)
                        ELSE LEAST(GREATEST(COALESCE(s.amountpaid, 0), 0),
                                   COALESCE(s.totalamount, 0))
                   END
                 - COALESCE((SELECT SUM(pp.amount)
                             FROM   poultrypayments pp
                             WHERE  pp.saleid = s.saleid
                               AND  lower(pp.farmid::text) = lower(p_farmid)
                               -- Same reason: a reversed payment never covered
                               -- anything, so it must not reduce the residual.
                               AND  COALESCE(pp.status, 'Posted') = 'Posted'), 0)
               , 2) AS residual
    ) v
    WHERE  lower(s.farmid::text) = lower(p_farmid)
      -- Only a POSITIVE residual. A negative one means the payment rows already
      -- exceed what the sale records as paid, which is a data inconsistency; it
      -- is surfaced by this file's verification query rather than quietly
      -- subtracted from the day's income.
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
      AND  sp.status = 'Posted'
      AND  sa.amountapplied <> 0
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;

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
    FROM   poultryownermoney o
    LEFT   JOIN poultrycashaccounts a
           ON a.poultrycashaccountid = o.poultrycashaccountid
    WHERE  o.farmid = p_farmid
      AND  o.status = 'Posted'
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
           l.loandate::timestamp,
           'CashIn'::text,
           'LoanReceived'::text,
           l.poultryloanid,
           FALSE,
           l.amountreceived::numeric,
           ('Loan received from ' || l.lendername)::text,
           'FinancingIn'::text
    FROM   poultryloans l
    LEFT   JOIN poultrycashaccounts a ON a.poultrycashaccountid = l.poultrycashaccountid
    WHERE  l.farmid = p_farmid
      AND  l.amountreceived > 0
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
               CASE WHEN ca.amount >= 0 THEN 'FinancingIn' ELSE 'FinancingOut' END::text
        FROM   %s ca
        WHERE  lower(ca.farmid::text) = lower($1)
          AND  ca.amount <> 0
          AND  ca.adjustmentdate >= $2
          AND  ca.adjustmentdate <= $3
    $sql$, v_tbl)
    USING p_farmid, v_from, v_to;
END;
$function$;

COMMIT;
