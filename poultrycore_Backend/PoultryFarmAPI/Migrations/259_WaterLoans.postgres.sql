-- =============================================================================
-- 259_WaterLoans.postgres.sql
--
-- Purpose
-- -------
-- Borrowed money, and paying it back. The water twin of 254.
--
-- THE THREE RULES
-- ===============
-- 1. REPAYING PRINCIPAL IS NOT AN EXPENSE.
--    Handing back money you were lent does not make the business poorer; it
--    settles a liability. Only the interest and the fees are the cost of
--    borrowing, and only they reach the P&L.
--
-- 2. CASH MOVES ONCE, FOR THE TOTAL.
--    A payment of 10,000 principal + 2,000 interest + 500 fee takes 12,500 out
--    of the account. ONE cash row of 12,500 -- not one of 12,500 and two more
--    of 2,000 and 500 for the expense rows. The check file counts the rows to
--    prove it.
--
-- 3. A LENDER IS NOT A SUPPLIER.
--    No supplier payment, no supplier allocation, no supplier balance. The
--    liability is a loan, and it is reduced by recording a loan payment.
--
-- HOW RULES 1 AND 2 ARE BOTH KEPT AT ONCE
-- =======================================
-- The interest and fee expense rows are written with paymentmethod = 'NonCash'
-- -- the marker that already means "a cost recorded without money moving for
-- THIS row" (internal use has used it since migration 216). Following it
-- through the places it matters on the water rail:
--
--   spwatercashflow_rows   The expense arm below gains ONE new clause,
--                          `paymentmethod <> 'NonCash'`, so the 2,500 does not
--                          land twice; the loan arm reports the full 12,500 as
--                          one Loan Repayment.
--   fnwaterpayables        ALREADY excludes these twice over: it requires
--                          `supplierid IS NOT NULL` and `sourcetype IS NULL`,
--                          and a loan expense has neither. Interest can never
--                          turn a lender into a creditor on Supplier Balances.
--   fnwaterexpenserows     Does NOT filter NonCash, so interest and fees DO
--                          count as expenses everywhere expenses are reported.
--
-- THE ONE NEW CLAUSE, AND WHY IT IS SAFE
-- --------------------------------------
-- Water's expense arm was rewritten by 241 to gate on `paidatentry > 0` rather
-- than on paymentmethod, so unlike poultry it has no NonCash clause to inherit.
-- One is added here. It is a verified no-op on today's data: there are ZERO
-- water expenses with paymentmethod = 'NonCash' in the database (the water
-- internal-use path writes its own rows differently), so no existing figure can
-- move. The check file pins the money-in/money-out totals either side to prove
-- it.
--
-- Adding the clause rather than leaning on `amountpaid = 0` is deliberate: an
-- expense with amountpaid 0 reads as an UNPAID BILL everywhere else in the
-- system, and a loan's interest is not something the business still owes a
-- supplier. The marker says what is true; the amount says what was paid.
--
-- WHAT REVERSAL DOES ABOUT THE EXPENSES
-- -------------------------------------
-- Nothing in this codebase deletes a financial row, so a reversal writes
-- COMPENSATING expense rows -- same category, negative amount, and their own
-- reversal sourcetype (see the next section). Expense reports sum amounts, so
-- the pair nets to zero; both rows stay on the record.
--
-- ONE SHADOW EXPENSE PER SOURCE DOCUMENT
-- --------------------------------------
-- waterexpenses carries a unique index poultry has no equivalent of:
--
--   ux_waterexpenses_farmsource_active
--       UNIQUE (farmid, sourcetype, sourceid) WHERE sourcetype IS NOT NULL
--                                               AND isdeleted = false
--
-- It says a source document gets AT MOST ONE auto-written expense -- one per
-- raw-material purchase, one per payroll run, one per internal usage. That is a
-- real invariant of the water rail and worth keeping, so a repayment does not
-- write two rows under one sourcetype. Interest and fee get their own:
--
--   LoanPaymentInterest / LoanPaymentFee                  the cost
--   LoanPaymentInterestReversal / LoanPaymentFeeReversal  its cancellation
--
-- Four sourcetypes where poultry uses two. Everything that matters keys off
-- paymentmethod = 'NonCash' and off sourcetype being non-null, so neither the
-- cash-flow exclusion nor the payables exclusion cares how many there are.
--
-- THE CATEGORY PROBLEM WATER HAS AND POULTRY DOES NOT
-- ---------------------------------------------------
-- poultry.expense stores its category as free text. waterexpenses stores a NOT
-- NULL foreign key to waterexpensecategories, which is per-company. So this
-- file adds spwaterexpensecategory_ensureloancost, the same get-or-create shape
-- as spwaterexpensecategory_ensureinternaluse, and calls it for 'Interest
-- Expense' and 'Loan Fee' on the company the payment belongs to.
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
-- THE LOAN DATE CARRIES A TIME
-- ----------------------------
-- 256 had to go back and fix this on poultry: loandate is a DATE, so casting it
-- to a timestamp gives midnight, and a loan recorded this afternoon sorted
-- below everything else recorded today. The rule is baked in here from the
-- start -- a loan dated TODAY reports the moment it was recorded, a back-dated
-- one keeps midnight -- so water never needs the follow-up migration.
--
-- EFFECT ON TODAY'S NUMBERS: none. Two new tables, new functions, one no-op
-- clause on the expense arm, and two more arms on spwatercashflow_rows that
-- return nothing until a loan exists.
--
-- Order: after 258.
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
          AND  p.proname IN ('spwaterloan_create',
                             'spwaterloan_update',
                             'spwaterloan_cancel',
                             'spwaterloan_getall',
                             'spwaterloan_summary',
                             'spwaterloanpayment_record',
                             'spwaterloanpayment_reverse',
                             'spwaterloanpayment_getall',
                             'spwaterexpensecategory_ensureloancost')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- -----------------------------------------------------------------------------
-- 1. The loan.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS waterloans (
    waterloanid          serial PRIMARY KEY,
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

    watercashaccountid   integer NULL,

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
    watercashtransactionid integer NULL,

    createdby      text NULL,
    createdat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby      text NULL,
    updatedat      timestamp NULL,
    reversedby     text NULL,
    reversedat     timestamp NULL,
    reversalreason text NULL
);

CREATE INDEX IF NOT EXISTS ix_waterloans_farm_status
    ON waterloans (farmid, status, startdate DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_waterloans_number
    ON waterloans (farmid, loannumber) WHERE loannumber IS NOT NULL;

COMMENT ON COLUMN waterloans.originalprincipal IS
    'What is OWED. May exceed amountreceived when the lender withheld a fee.';
COMMENT ON COLUMN waterloans.amountreceived IS
    'What actually ARRIVED. This, not the principal, is the cash in.';
COMMENT ON COLUMN waterloans.outstandingprincipal IS
    'Maintained by the payment functions. Payoff is decided by THIS reaching '
    'zero, never by comparing total paid against the original principal -- '
    'those differ by every cedi of interest.';

-- -----------------------------------------------------------------------------
-- 2. The repayment.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS waterloanpayments (
    waterloanpaymentid serial PRIMARY KEY,
    farmid             varchar(450) NOT NULL,
    waterloanid        integer NOT NULL REFERENCES waterloans (waterloanid),
    paymentnumber      text NULL,
    paymentdate        timestamp NOT NULL DEFAULT (now() at time zone 'utc'),

    -- The four parts, and their sum. Stored rather than derived so a historic
    -- payment still reads correctly if the split rules ever change.
    totalamount     numeric(14,2) NOT NULL CHECK (totalamount > 0),
    principalamount numeric(14,2) NOT NULL DEFAULT 0 CHECK (principalamount >= 0),
    interestamount  numeric(14,2) NOT NULL DEFAULT 0 CHECK (interestamount >= 0),
    feeamount       numeric(14,2) NOT NULL DEFAULT 0 CHECK (feeamount >= 0),
    otheramount     numeric(14,2) NOT NULL DEFAULT 0 CHECK (otheramount >= 0),

    watercashaccountid integer NOT NULL,
    paymentmethod      text NULL,
    referencenumber    text NULL,
    notes              text NULL,

    status text NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),

    -- The ONE cash row, and the expense rows for the cost of borrowing.
    watercashtransactionid    integer NULL,
    interestexpenseid         integer NULL,
    feeexpenseid              integer NULL,
    reversalcashtransactionid integer NULL,

    createdby      text NULL,
    createdat      timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    reversedby     text NULL,
    reversedat     timestamp NULL,
    reversalreason text NULL,

    -- The arithmetic can never be wrong, because the row cannot exist if it is.
    CONSTRAINT ck_waterloanpayments_total
        CHECK (totalamount = principalamount + interestamount + feeamount + otheramount)
);

CREATE INDEX IF NOT EXISTS ix_waterloanpayments_loan
    ON waterloanpayments (waterloanid, paymentdate DESC);
CREATE INDEX IF NOT EXISTS ix_waterloanpayments_farm
    ON waterloanpayments (farmid, status, paymentdate DESC);

COMMENT ON CONSTRAINT ck_waterloanpayments_total ON waterloanpayments IS
    'The split must add up. Enforced by the table so no code path can write a '
    'payment whose parts disagree with its total.';

-- -----------------------------------------------------------------------------
-- 2b. The expense category for a cost of borrowing.
--
-- waterexpenses.waterexpensecategoryid is NOT NULL and categories are
-- per-company, so a loan payment cannot write an expense without one. Same
-- get-or-create shape as spwaterexpensecategory_ensureinternaluse.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterexpensecategory_ensureloancost(
    p_farmid text,
    p_name   text
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id integer;
BEGIN
    SELECT c.waterexpensecategoryid INTO v_id
    FROM   waterexpensecategories c
    WHERE  c.farmid = p_farmid AND c.name = p_name
      AND  COALESCE(c.isdeleted, FALSE) = FALSE
    LIMIT  1;

    IF v_id IS NULL THEN
        INSERT INTO waterexpensecategories (farmid, name, description)
        VALUES (p_farmid, p_name,
                'The cost of borrowing. Written by loan repayments; principal '
                'repayment is never an expense and never appears here.')
        RETURNING waterexpensecategoryid INTO v_id;
    END IF;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Record a loan, and take the money if it has arrived.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterloan_create(
    p_farmid             text,
    p_lendername         text,
    p_originalprincipal  numeric,
    p_startdate          date,
    p_amountreceived     numeric DEFAULT 0,
    p_watercashaccountid integer DEFAULT NULL,
    p_lendertype         text DEFAULT 'Other',
    p_accountnumber      text DEFAULT NULL,
    p_loandate           date DEFAULT NULL,
    p_interestrate       numeric DEFAULT NULL,
    p_interesttype       text DEFAULT NULL,
    p_termmonths         integer DEFAULT NULL,
    p_paymentfrequency   text DEFAULT NULL,
    p_enddate            date DEFAULT NULL,
    p_nextpaymentdate    date DEFAULT NULL,
    p_status             text DEFAULT 'Active',
    p_notes              text DEFAULT NULL,
    p_createdby          text DEFAULT NULL
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
        IF p_watercashaccountid IS NULL THEN
            RAISE EXCEPTION 'Say which cash account received the money.';
        END IF;
        SELECT a.currentbalance INTO v_balance
        FROM   watercashaccounts a
        WHERE  a.watercashaccountid = p_watercashaccountid AND a.farmid = p_farmid;
        IF v_balance IS NULL THEN
            RAISE EXCEPTION 'Cash account does not exist or does not belong to this company.';
        END IF;
    END IF;

    INSERT INTO waterloans (
        farmid, lendername, lendertype, accountnumber, loandate,
        originalprincipal, amountreceived, interestrate, interesttype, termmonths,
        paymentfrequency, startdate, enddate, nextpaymentdate, watercashaccountid,
        -- The debt starts at what is OWED, not at what arrived.
        outstandingprincipal, status, notes, createdby)
    VALUES (
        p_farmid, btrim(p_lendername), COALESCE(p_lendertype, 'Other'),
        NULLIF(btrim(p_accountnumber), ''), v_date,
        p_originalprincipal, COALESCE(p_amountreceived, 0),
        p_interestrate, p_interesttype, p_termmonths,
        p_paymentfrequency, p_startdate, p_enddate, p_nextpaymentdate,
        p_watercashaccountid,
        p_originalprincipal, p_status, NULLIF(btrim(p_notes), ''), p_createdby)
    RETURNING waterloanid INTO v_id;

    UPDATE waterloans
    SET    loannumber = 'LN-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  waterloanid = v_id;

    -- The disbursement. ONE cash row, and only if the money actually arrived.
    IF COALESCE(p_amountreceived, 0) > 0 THEN
        INSERT INTO watercashtransactions (
            farmid, watercashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, p_watercashaccountid, v_date::timestamp, 'LoanReceived',
            'Loan', v_id, p_amountreceived,
            'Loan received from ' || btrim(p_lendername),
            p_createdby, p_createdby, (now() at time zone 'utc'))
        RETURNING watercashtransactionid INTO v_txid;

        UPDATE watercashaccounts a
        SET    currentbalance = a.currentbalance + p_amountreceived,
               updatedat = (now() at time zone 'utc')
        WHERE  a.watercashaccountid = p_watercashaccountid;

        UPDATE waterloans SET watercashtransactionid = v_txid WHERE waterloanid = v_id;
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
CREATE OR REPLACE FUNCTION public.spwaterloan_update(
    p_waterloanid      integer,
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
    SELECT l.status INTO v_status FROM waterloans l
    WHERE  l.waterloanid = p_waterloanid AND l.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Loan % not found.', p_waterloanid;
    END IF;
    IF v_status IN ('Cancelled', 'Reversed') THEN
        RAISE EXCEPTION 'A % loan cannot be edited.', v_status;
    END IF;

    UPDATE waterloans l
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
    WHERE  l.waterloanid = p_waterloanid AND l.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Cancel a loan that never happened.
--
-- Only while nothing has been repaid. A loan with payments against it has a
-- history, and cancelling it would orphan them.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterloan_cancel(
    p_waterloanid integer,
    p_farmid      text,
    p_reason      text,
    p_cancelledby text DEFAULT NULL
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

    SELECT l.status, l.amountreceived, l.watercashaccountid
    INTO   v_status, v_received, v_acct
    FROM   waterloans l
    WHERE  l.waterloanid = p_waterloanid AND l.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Loan % not found.', p_waterloanid;
    END IF;
    IF v_status IN ('Cancelled', 'Reversed') THEN
        RAISE EXCEPTION 'This loan is already %.', v_status;
    END IF;

    SELECT COUNT(*) INTO v_paid FROM waterloanpayments p
    WHERE  p.waterloanid = p_waterloanid AND p.status = 'Posted';
    IF v_paid > 0 THEN
        RAISE EXCEPTION 'This loan has % posted repayment(s); reverse them before cancelling it.', v_paid;
    END IF;

    -- If money was disbursed it has to go back, or the cash account keeps cash
    -- from a loan that no longer exists.
    IF COALESCE(v_received, 0) > 0 THEN
        INSERT INTO watercashtransactions (
            farmid, watercashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, v_acct, v_now, 'LoanReceivedReversal',
            'Loan', p_waterloanid, -v_received,
            'Cancelled loan ' || p_waterloanid::text,
            p_cancelledby, p_cancelledby, v_now);

        UPDATE watercashaccounts a
        SET    currentbalance = a.currentbalance - v_received, updatedat = v_now
        WHERE  a.watercashaccountid = v_acct;
    END IF;

    UPDATE waterloans l
    SET    status = 'Cancelled', outstandingprincipal = 0,
           reversedby = p_cancelledby, reversedat = v_now,
           reversalreason = btrim(p_reason), updatedat = v_now
    WHERE  l.waterloanid = p_waterloanid AND l.farmid = p_farmid;
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
CREATE OR REPLACE FUNCTION public.spwaterloanpayment_record(
    p_farmid             text,
    p_waterloanid        integer,
    p_watercashaccountid integer,
    p_principalamount    numeric DEFAULT 0,
    p_interestamount     numeric DEFAULT 0,
    p_feeamount          numeric DEFAULT 0,
    p_otheramount        numeric DEFAULT 0,
    p_paymentdate        timestamp DEFAULT NULL,
    p_paymentmethod      text DEFAULT NULL,
    p_referencenumber    text DEFAULT NULL,
    p_notes              text DEFAULT NULL,
    p_nextpaymentdate    date DEFAULT NULL,
    p_createdby          text DEFAULT NULL
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
    v_cat         integer;
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
    FROM   waterloans l
    WHERE  l.waterloanid = p_waterloanid AND l.farmid = p_farmid;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Loan % not found.', p_waterloanid;
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
    FROM   watercashaccounts a
    WHERE  a.watercashaccountid = p_watercashaccountid AND a.farmid = p_farmid;

    IF v_balance IS NULL THEN
        RAISE EXCEPTION 'Cash account does not exist or does not belong to this company.';
    END IF;
    IF v_allowneg = FALSE AND (v_balance - v_total) < 0 THEN
        RAISE EXCEPTION 'This repayment would take the cash account below zero.';
    END IF;

    INSERT INTO waterloanpayments (
        farmid, waterloanid, paymentdate, totalamount,
        principalamount, interestamount, feeamount, otheramount,
        watercashaccountid, paymentmethod, referencenumber, notes,
        status, createdby)
    VALUES (
        p_farmid, p_waterloanid, v_date, v_total,
        v_principal, v_interest, v_fee, v_other,
        p_watercashaccountid, NULLIF(btrim(p_paymentmethod), ''),
        NULLIF(btrim(p_referencenumber), ''), NULLIF(btrim(p_notes), ''),
        'Posted', p_createdby)
    RETURNING waterloanpaymentid INTO v_id;

    UPDATE waterloanpayments
    SET    paymentnumber = 'LP-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  waterloanpaymentid = v_id;

    -- ---- ONE cash row, for the TOTAL ------------------------------------
    INSERT INTO watercashtransactions (
        farmid, watercashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
    VALUES (
        p_farmid, p_watercashaccountid, v_date, 'LoanRepayment',
        'LoanPayment', v_id, -v_total,
        'Loan repayment to ' || COALESCE(v_lender, 'lender'),
        p_createdby, p_createdby, (now() at time zone 'utc'))
    RETURNING watercashtransactionid INTO v_txid;

    UPDATE watercashaccounts a
    SET    currentbalance = a.currentbalance - v_total, updatedat = (now() at time zone 'utc')
    WHERE  a.watercashaccountid = p_watercashaccountid;

    -- ---- the cost of borrowing, as expenses that move no further cash -----
    -- paymentmethod 'NonCash' is what keeps the 12,500 from being counted as
    -- 15,000: the cash-flow expense arm skips these rows, the loan arm reports
    -- the full total, and every expense report still sees the interest and fee.
    --
    -- status 'Approved' because the cost is recognised the moment it is paid --
    -- there is no approval workflow behind a loan repayment -- and supplierid
    -- stays NULL because a lender is not a supplier.
    IF v_interest > 0 THEN
        v_cat := spwaterexpensecategory_ensureloancost(p_farmid, 'Interest Expense');
        INSERT INTO waterexpenses (
            farmid, expensedate, waterexpensecategoryid, description, amount,
            paymentmethod, watercashaccountid, amountpaid, status,
            sourcetype, sourceid, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, v_date, v_cat,
            'Interest on loan ' || COALESCE(v_number, p_waterloanid::text),
            v_interest, 'NonCash', NULL, v_interest, 'Approved',
            'LoanPaymentInterest', v_id, p_createdby, p_createdby, (now() at time zone 'utc'))
        RETURNING waterexpenseid INTO v_intexp;
    END IF;

    IF v_fee > 0 THEN
        v_cat := spwaterexpensecategory_ensureloancost(p_farmid, 'Loan Fee');
        INSERT INTO waterexpenses (
            farmid, expensedate, waterexpensecategoryid, description, amount,
            paymentmethod, watercashaccountid, amountpaid, status,
            sourcetype, sourceid, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, v_date, v_cat,
            'Fee on loan ' || COALESCE(v_number, p_waterloanid::text),
            v_fee, 'NonCash', NULL, v_fee, 'Approved',
            'LoanPaymentFee', v_id, p_createdby, p_createdby, (now() at time zone 'utc'))
        RETURNING waterexpenseid INTO v_feeexp;
    END IF;

    UPDATE waterloanpayments
    SET    watercashtransactionid = v_txid,
           interestexpenseid = v_intexp,
           feeexpenseid = v_feeexp
    WHERE  waterloanpaymentid = v_id;

    -- ---- the debt ---------------------------------------------------------
    v_newout := v_outstanding - v_principal;

    UPDATE waterloans l
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
    WHERE  l.waterloanid = p_waterloanid AND l.farmid = p_farmid;

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
CREATE OR REPLACE FUNCTION public.spwaterloanpayment_reverse(
    p_waterloanpaymentid integer,
    p_farmid             text,
    p_reason             text,
    p_reversedby         text DEFAULT NULL
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
    v_cat       integer;
    v_now       timestamp := (now() at time zone 'utc');
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a repayment.';
    END IF;

    SELECT p.waterloanid, p.status, p.totalamount, p.principalamount,
           p.interestamount, p.feeamount, p.watercashaccountid, p.paymentnumber
    INTO   v_loan, v_status, v_total, v_principal, v_interest, v_fee, v_acct, v_number
    FROM   waterloanpayments p
    WHERE  p.waterloanpaymentid = p_waterloanpaymentid AND p.farmid = p_farmid;

    IF v_loan IS NULL THEN
        RAISE EXCEPTION 'Loan payment % not found.', p_waterloanpaymentid;
    END IF;
    IF v_status <> 'Posted' THEN
        RAISE EXCEPTION 'Only a posted repayment can be reversed (this one is %).', v_status;
    END IF;

    SELECT l.loannumber INTO v_loannum FROM waterloans l WHERE l.waterloanid = v_loan;

    -- The money comes back into the account it left.
    INSERT INTO watercashtransactions (
        farmid, watercashaccountid, transactiondate, transactiontype,
        sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
    VALUES (
        p_farmid, v_acct, v_now, 'LoanRepaymentReversal',
        'LoanPayment', p_waterloanpaymentid, v_total,
        'Reversal of repayment ' || COALESCE(v_number, p_waterloanpaymentid::text),
        p_reversedby, p_reversedby, v_now)
    RETURNING watercashtransactionid INTO v_txid;

    UPDATE watercashaccounts a
    SET    currentbalance = a.currentbalance + v_total, updatedat = v_now
    WHERE  a.watercashaccountid = v_acct;

    -- The cost of borrowing is cancelled by a compensating row, not by deletion:
    -- nothing here deletes a financial record.
    IF v_interest > 0 THEN
        v_cat := spwaterexpensecategory_ensureloancost(p_farmid, 'Interest Expense');
        INSERT INTO waterexpenses (
            farmid, expensedate, waterexpensecategoryid, description, amount,
            paymentmethod, watercashaccountid, amountpaid, status,
            sourcetype, sourceid, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, v_now, v_cat,
            'Reversal: interest on loan ' || COALESCE(v_loannum, v_loan::text),
            -v_interest, 'NonCash', NULL, -v_interest, 'Approved',
            'LoanPaymentInterestReversal', p_waterloanpaymentid, p_reversedby, p_reversedby, v_now);
    END IF;

    IF v_fee > 0 THEN
        v_cat := spwaterexpensecategory_ensureloancost(p_farmid, 'Loan Fee');
        INSERT INTO waterexpenses (
            farmid, expensedate, waterexpensecategoryid, description, amount,
            paymentmethod, watercashaccountid, amountpaid, status,
            sourcetype, sourceid, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, v_now, v_cat,
            'Reversal: fee on loan ' || COALESCE(v_loannum, v_loan::text),
            -v_fee, 'NonCash', NULL, -v_fee, 'Approved',
            'LoanPaymentFeeReversal', p_waterloanpaymentid, p_reversedby, p_reversedby, v_now);
    END IF;

    -- The debt goes back up, and a loan that was paid off is live again.
    UPDATE waterloans l
    SET    outstandingprincipal = l.outstandingprincipal + v_principal,
           totalprincipalrepaid = GREATEST(l.totalprincipalrepaid - v_principal, 0),
           totalinterestpaid    = GREATEST(l.totalinterestpaid - v_interest, 0),
           totalfeespaid        = GREATEST(l.totalfeespaid - v_fee, 0),
           status = CASE WHEN l.status = 'PaidOff' AND (l.outstandingprincipal + v_principal) > 0
                         THEN 'Active' ELSE l.status END,
           paidoffdate = CASE WHEN (l.outstandingprincipal + v_principal) > 0
                              THEN NULL ELSE l.paidoffdate END,
           updatedat = v_now
    WHERE  l.waterloanid = v_loan;

    UPDATE waterloanpayments p
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = v_now,
           reversalreason = btrim(p_reason), reversalcashtransactionid = v_txid
    WHERE  p.waterloanpaymentid = p_waterloanpaymentid AND p.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 8. Reads.
--
-- Overdue is DERIVED, never stored: a loan is overdue when its next payment
-- date has passed and it still owes something. Stamping a status would need a
-- nightly job this system does not have, and would be stale the moment one ran.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterloan_getall(
    p_farmid text,
    p_status text DEFAULT NULL
) RETURNS TABLE(
    waterloanid          integer,
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
    watercashaccountid   integer,
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
    SELECT l.waterloanid, l.farmid::text, l.loannumber::text,
           l.lendername::text, l.lendertype::text, l.accountnumber::text,
           l.loandate, l.originalprincipal, l.amountreceived,
           l.interestrate, l.interesttype::text, l.termmonths, l.paymentfrequency::text,
           l.startdate, l.enddate, l.nextpaymentdate,
           l.watercashaccountid, a.accountname::text,
           l.outstandingprincipal, l.totalprincipalrepaid,
           l.totalinterestpaid, l.totalfeespaid,
           l.status::text,
           (l.status = 'Active'
            AND l.nextpaymentdate IS NOT NULL
            AND l.nextpaymentdate < CURRENT_DATE
            AND l.outstandingprincipal > 0) AS isoverdue,
           (SELECT COUNT(*)::int FROM waterloanpayments p
             WHERE p.waterloanid = l.waterloanid AND p.status = 'Posted'),
           l.paidoffdate, l.notes::text, l.createdby::text, l.createdat,
           l.reversalreason::text
    FROM   waterloans l
    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = l.watercashaccountid
    WHERE  l.farmid = p_farmid
      AND  (p_status IS NULL OR p_status = 'All' OR l.status = p_status)
    ORDER  BY l.startdate DESC, l.waterloanid DESC;
$function$;

CREATE OR REPLACE FUNCTION public.spwaterloanpayment_getall(
    p_farmid text,
    p_loanid integer DEFAULT NULL,
    p_from   date DEFAULT NULL,
    p_to     date DEFAULT NULL
) RETURNS TABLE(
    waterloanpaymentid integer,
    farmid             text,
    waterloanid        integer,
    loannumber         text,
    lendername         text,
    paymentnumber      text,
    paymentdate        timestamp,
    totalamount        numeric,
    principalamount    numeric,
    interestamount     numeric,
    feeamount          numeric,
    otheramount        numeric,
    watercashaccountid integer,
    accountname        text,
    paymentmethod      text,
    referencenumber    text,
    notes              text,
    status             text,
    interestexpenseid  integer,
    feeexpenseid       integer,
    createdby          text,
    createdat          timestamp,
    reversedby         text,
    reversedat         timestamp,
    reversalreason     text
)
LANGUAGE sql STABLE
AS $function$
    SELECT p.waterloanpaymentid, p.farmid::text, p.waterloanid,
           l.loannumber::text, l.lendername::text,
           p.paymentnumber::text, p.paymentdate, p.totalamount,
           p.principalamount, p.interestamount, p.feeamount, p.otheramount,
           p.watercashaccountid, a.accountname::text,
           p.paymentmethod::text, p.referencenumber::text, p.notes::text,
           p.status::text, p.interestexpenseid, p.feeexpenseid,
           p.createdby::text, p.createdat,
           p.reversedby::text, p.reversedat, p.reversalreason::text
    FROM   waterloanpayments p
    JOIN   waterloans l ON l.waterloanid = p.waterloanid
    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = p.watercashaccountid
    WHERE  p.farmid = p_farmid
      AND  (p_loanid IS NULL OR p.waterloanid = p_loanid)
      AND  (p_from IS NULL OR p.paymentdate >= p_from::timestamp)
      AND  (p_to   IS NULL OR p.paymentdate <  (p_to + 1)::timestamp)
    ORDER  BY p.paymentdate DESC, p.waterloanpaymentid DESC;
$function$;

-- The cards on the page.
CREATE OR REPLACE FUNCTION public.spwaterloan_summary(p_farmid text)
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
    FROM waterloans l
    WHERE l.farmid = p_farmid;
$function$;

-- -----------------------------------------------------------------------------
-- 9. Cash Flow learns to read loans.
--
-- Reproduced from the LIVE definition of spwatercashflow_rows -- which now
-- includes 258's owner-money arm. Every existing arm is byte for byte what it
-- was apart from ONE added clause on the expense arm (`paymentmethod <>
-- 'NonCash'`, a verified no-op today); the other change is the two new arms
-- above the legacy capital one.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwatercashflow_rows(p_farmid text, p_fromdate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_todate timestamp without time zone DEFAULT NULL::timestamp without time zone)
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
    FROM   waterpayments p
    WHERE  lower(p.farmid::text) = lower(p_farmid)
      AND  COALESCE(p.amount, 0) <> 0
      -- A REVERSED payment is money that came back. 227 added this column and
      -- flips it on reversal rather than deleting the row, so without this filter
      -- the report counts a refunded receipt as income for ever.
      AND  COALESCE(p.status, 'Posted') = 'Posted'
      AND  p.paymentdate >= v_from
      AND  p.paymentdate <= v_to;

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
    FROM   supplierpaymentallocation sa
    JOIN   watersupplierpayments sp
           ON  sp.watersupplierpaymentid = sa.paymentid
           AND sp.farmid = sa.farmid
    LEFT   JOIN watersuppliers s
           ON  s.watersupplierid = sp.supplierid AND s.farmid = sp.farmid
    WHERE  sa.farmid = p_farmid
      AND  sa.module = 'water'
      AND  sa.status = 'Posted'
      AND  sa.documenttype = 'Expense'
      AND  COALESCE(sp.status, 'Posted') = 'Posted'
      AND  sa.amountapplied <> 0
      AND  sp.paymentdate >= v_from
      AND  sp.paymentdate <= v_to;

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
    FROM   waterownermoney o
    LEFT   JOIN watercashaccounts a
           ON a.watercashaccountid = o.watercashaccountid
    WHERE  o.farmid = p_farmid
      AND  o.status = 'Posted'
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
    FROM   waterloans l
    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = l.watercashaccountid
    WHERE  l.farmid = p_farmid
      AND  l.amountreceived > 0
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
    FROM   waterloanpayments p
    JOIN   waterloans l ON l.waterloanid = p.waterloanid
    LEFT   JOIN watercashaccounts a ON a.watercashaccountid = p.watercashaccountid
    WHERE  p.farmid = p_farmid
      AND  p.status = 'Posted'
      AND  p.paymentdate >= v_from
      AND  p.paymentdate <= v_to;

    -- ---- 7. capital in and out (legacy cash adjustments) --------------------
    -- Expected to return nothing on Water today -- see 236's header note.
    --
    -- MUST STAY LAST: it RETURNs early when the table is absent, and anything
    -- below it would be silently skipped.
    v_tbl := COALESCE(to_regclass('public.cashadjustment')::text,
                      to_regclass('public.cashadjustments')::text);

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
