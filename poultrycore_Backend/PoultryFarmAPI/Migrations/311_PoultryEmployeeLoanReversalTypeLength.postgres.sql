-- =============================================================================
-- 311_PoultryEmployeeLoanReversalTypeLength.postgres.sql
--
-- Fixes a bug in 305: reversing a disbursed advance failed with
--
--     value too long for type character varying(30)
--
-- poultrycashtransactions.transactiontype is varchar(30). The reversal wrote
-- 'EmployeeLoanDisbursementReversal', which is 32 characters, so every attempt
-- to reverse an advance was refused by the column.
--
-- Nothing was half-done by those failed attempts: the whole function is one
-- transaction, so an advance that could not be reversed simply stayed exactly
-- as it was. There is no wreckage to clean up.
--
-- The value is now 'EmployeeLoanReversal' (20). The sibling path, reversing a
-- MANUAL repayment, writes 'EmployeeLoanRepaymentReversal' at 29 characters --
-- it fits, it is already in use on real rows, and renaming it now would leave
-- the same event recorded two different ways either side of this migration. It
-- is left alone deliberately.
--
-- WHY THE LENGTHS WERE NOT CHECKED WHEN 305 WAS WRITTEN
-- -----------------------------------------------------
-- The dry run applied every migration and called the read functions, but it
-- never called a WRITE path -- there was no advance to reverse, so the INSERT
-- that overflows was never executed. A constraint only fails when something
-- reaches it.
--
-- Idempotent.
-- =============================================================================

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

DO $checks$
DECLARE v_body text;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_body
    FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE  n.nspname = 'public' AND p.proname = 'sppoultryemployeeloan_reverse' LIMIT 1;

    IF v_body IS NULL THEN
        RAISE EXCEPTION '311: sppoultryemployeeloan_reverse is missing.';
    END IF;
    IF position('EmployeeLoanDisbursementReversal' in v_body) > 0 THEN
        RAISE EXCEPTION '311: the over-long transaction type is still there.';
    END IF;

    -- Every literal this feature writes into that column, measured rather than
    -- eyeballed. Cheap, and it is what would have caught this in the first place.
    IF EXISTS (
        SELECT 1 FROM (VALUES
            ('EmployeeLoanDisbursement'), ('EmployeeLoanReversal'),
            ('EmployeeLoanRepayment'), ('EmployeeLoanRepaymentReversal')
        ) AS v(t) WHERE length(v.t) > 30) THEN
        RAISE EXCEPTION '311: a transaction type is still longer than the column allows.';
    END IF;

    RAISE NOTICE '311_PoultryEmployeeLoanReversalTypeLength: advances can be reversed again.';
END
$checks$;
