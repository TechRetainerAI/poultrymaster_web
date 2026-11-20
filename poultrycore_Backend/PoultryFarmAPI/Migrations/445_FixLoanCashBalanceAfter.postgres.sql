-- 445_FixLoanCashBalanceAfter.postgres.sql
-- All 4 employee-loan cash-transaction INSERTs were missing the NOT NULL
-- column balanceaftertransaction.  Re-create each function with the fix.

-- ============================================================================
-- 1. Disburse  (balance is already in v_balance)
-- ============================================================================
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
        sourcetype, sourceid, amount, balanceaftertransaction,
        description, createdby, approvedby, approvedat)
    VALUES (
        p_farmid, p_genericcashaccountid, v_date::timestamp, 'EmployeeLoanDisbursement',
        'EmployeeLoan', p_genericemployeeloanid, -v_principal,
        v_balance - v_principal,
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

-- ============================================================================
-- 2. Reverse disbursement
-- ============================================================================
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
    v_balance   numeric;
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
        SELECT a.currentbalance INTO v_balance
        FROM   genericcashaccounts a WHERE a.genericcashaccountid = v_acct;

        INSERT INTO genericcashtransactions (
            farmid, genericcashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, balanceaftertransaction,
            description, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, v_acct, (now() at time zone 'utc'),
            'EmployeeLoanReversal',
            'EmployeeLoanReversal', p_genericemployeeloanid, v_principal,
            COALESCE(v_balance, 0) + v_principal,
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

-- ============================================================================
-- 3. Record repayment
-- ============================================================================
CREATE OR REPLACE FUNCTION public.spgenericemployeeloanrepayment_record(
    p_farmid                  text,
    p_genericemployeeloanid   integer,
    p_amount                  numeric,
    p_sourcetype              text DEFAULT 'ManualCash',
    p_genericcashaccountid    integer DEFAULT NULL,
    p_paymentmethod           text DEFAULT NULL,
    p_referencenumber         text DEFAULT NULL,
    p_description             text DEFAULT NULL,
    p_notes                   text DEFAULT NULL,
    p_genericpayrollrunid     integer DEFAULT NULL,
    p_genericpayrollitemid    integer DEFAULT NULL,
    p_repaymentdate           timestamp DEFAULT NULL,
    p_principalamount         numeric DEFAULT NULL,
    p_interestamount          numeric DEFAULT NULL,
    p_createdby               text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_outstanding numeric;
    v_total       numeric;
    v_interest_en boolean;
    v_staffid     integer;
    v_staffname   text;
    v_number      text;
    v_source      text;
    v_amount      numeric;
    v_principal   numeric;
    v_interest    numeric;
    v_newout      numeric;
    v_id          integer;
    v_txid        integer;
    v_seq         integer;
    v_date        timestamp;
    v_balance     numeric;
BEGIN
    v_amount := COALESCE(p_amount, 0);
    IF v_amount <= 0 THEN
        RAISE EXCEPTION 'Repayment amount must be positive.';
    END IF;

    v_source := COALESCE(NULLIF(btrim(p_sourcetype), ''), 'ManualCash');
    v_date   := COALESCE(p_repaymentdate, now() at time zone 'utc');

    SELECT l.outstandingbalance, l.totalrepayable, l.interestenabled,
           l.genericstaffid, l.loannumber
    INTO   v_outstanding, v_total, v_interest_en, v_staffid, v_number
    FROM   genericemployeeloans l
    WHERE  l.genericemployeeloanid = p_genericemployeeloanid AND l.farmid = p_farmid
    FOR UPDATE;

    IF v_outstanding IS NULL THEN
        RAISE EXCEPTION 'Advance % not found.', p_genericemployeeloanid;
    END IF;
    IF v_outstanding <= 0 THEN
        RAISE EXCEPTION 'This advance is fully repaid.';
    END IF;
    IF v_amount > v_outstanding THEN
        RAISE EXCEPTION 'Repayment of % exceeds the outstanding balance of %.', v_amount, v_outstanding;
    END IF;

    v_interest  := CASE WHEN v_interest_en THEN COALESCE(p_interestamount, 0) ELSE 0 END;
    v_principal := COALESCE(p_principalamount, v_amount - v_interest);
    IF v_principal + v_interest <> v_amount THEN
        RAISE EXCEPTION 'Principal (%) + interest (%) does not equal the repayment amount (%).', v_principal, v_interest, v_amount;
    END IF;

    IF v_source <> 'Payroll' AND p_genericcashaccountid IS NULL THEN
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
        SELECT a.currentbalance INTO v_balance
        FROM   genericcashaccounts a WHERE a.genericcashaccountid = p_genericcashaccountid;

        INSERT INTO genericcashtransactions (
            farmid, genericcashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, balanceaftertransaction,
            description, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, p_genericcashaccountid, v_date, 'EmployeeLoanRepayment',
            'EmployeeLoanRepayment', v_id, v_amount,
            COALESCE(v_balance, 0) + v_amount,
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

-- ============================================================================
-- 4. Reverse repayment
-- ============================================================================
CREATE OR REPLACE FUNCTION public.spgenericemployeeloanrepayment_reverse(
    p_farmid                           text,
    p_genericemployeeloanrepaymentid   integer,
    p_reversedby                       text DEFAULT NULL,
    p_reason                           text DEFAULT NULL,
    p_allowpayroll                     boolean DEFAULT FALSE
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status      text;
    v_amount      numeric;
    v_principal   numeric;
    v_interest    numeric;
    v_source      text;
    v_acct        integer;
    v_runid       integer;
    v_loanid      integer;
    v_loanstatus  text;
    v_outstanding numeric;
    v_total       numeric;
    v_staffname   text;
    v_number      text;
    v_newout      numeric;
    v_txid        integer;
    v_balance     numeric;
BEGIN
    SELECT r.status, r.amount, r.principalamount, r.interestamount,
           r.sourcetype, r.genericcashaccountid, r.genericpayrollrunid,
           r.genericemployeeloanid
    INTO   v_status, v_amount, v_principal, v_interest,
           v_source, v_acct, v_runid, v_loanid
    FROM   genericemployeeloanrepayments r
    WHERE  r.genericemployeeloanrepaymentid = p_genericemployeeloanrepaymentid
           AND r.farmid = p_farmid
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Repayment % not found.', p_genericemployeeloanrepaymentid;
    END IF;
    IF v_status = 'Reversed' THEN
        RAISE EXCEPTION 'This repayment is already reversed.';
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

    SELECT l.loannumber INTO v_number
    FROM   genericemployeeloans l WHERE l.genericemployeeloanid = v_loanid;

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
        SELECT a.currentbalance INTO v_balance
        FROM   genericcashaccounts a WHERE a.genericcashaccountid = v_acct;

        INSERT INTO genericcashtransactions (
            farmid, genericcashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, balanceaftertransaction,
            description, createdby, approvedby, approvedat)
        VALUES (
            p_farmid, v_acct, (now() at time zone 'utc'), 'EmployeeLoanRepaymentReversal',
            'EmployeeLoanRepaymentReversal', p_genericemployeeloanrepaymentid, -v_amount,
            COALESCE(v_balance, 0) - v_amount,
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
           paidat = CASE WHEN v_newout <= 0 THEN (now() at time zone 'utc') ELSE NULL END,
           updatedat = (now() at time zone 'utc')
    WHERE  l.genericemployeeloanid = v_loanid AND l.farmid = p_farmid;

    RETURN p_genericemployeeloanrepaymentid;
END;
$function$;
