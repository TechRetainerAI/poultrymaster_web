-- 509: Generic Loans get Draft -> Approve, like Poultry's employee advances (305).
--
-- THE LIFE OF A LOAN
--   Draft     Saved, nothing posted. No cash has moved, nothing is owed, and
--             EVERYTHING can be edited: lender, amounts, account, dates, terms.
--   Approve   The money posts: the amount received goes into the account (one
--             ledger row, as in 455) and the debt starts at the principal.
--   Active /  Locked. Only a LIGHT edit is allowed: lender name and type,
--   PaidOff   account number, due date, next payment date and notes. Nothing
--             that is money or a term of the loan.
--   Reverse   An approved loan with no posted repayments goes BACK TO DRAFT:
--             the money received is taken back out of the account, the debt
--             comes off, and the loan can be corrected and approved again.
--             (Before 509 a reversed loan was dead -- Cancelled -- and had to be
--             typed in again as a new loan.)
--   Cancel    Only a Draft. Discards it; it stays on the record as Cancelled.
--
-- READERS (nothing to change in them)
--   Every money reader takes loans by "Status" IN ('Active', 'Paid') --
--   spgenericcashflow_rows arm 7 (504) and fngenericproject_cashrows (503) --
--   so a Draft never counts. The project P&L (484) only reads posted
--   repayments, which a Draft cannot have. The reverse writes its cash row as
--   'LoanCancelled', the source type 496/501/503 already keep out of the
--   project cash rows (the loan arm reads the loan table instead).
--
-- EXISTING LOANS are all approved already (455 posted them on save), so they
-- stay Active / Paid / Cancelled; ApprovedAt is filled from CreatedAt.
--
-- API: spgenericloan_create gains p_approve (DEFAULT TRUE, so an old caller
-- still posts on save), spgenericloan_update gains the money fields (Draft
-- only), and spgenericloan_approve / spgenericloan_reverse are new.
-- Needs a Farm API rebuild.

BEGIN;

ALTER TABLE "GenericLoans"
    ADD COLUMN IF NOT EXISTS "ApprovedBy"     text,
    ADD COLUMN IF NOT EXISTS "ApprovedAt"     timestamp,
    ADD COLUMN IF NOT EXISTS "ReversedBy"     text,
    ADD COLUMN IF NOT EXISTS "ReversedAt"     timestamp,
    ADD COLUMN IF NOT EXISTS "ReversalReason" text;

UPDATE "GenericLoans"
SET    "ApprovedAt" = "CreatedAt", "ApprovedBy" = "CreatedBy"
WHERE  "ApprovedAt" IS NULL AND "Status" IN ('Active', 'Paid');

-- ---------------------------------------------------------------------------
-- create: Draft (nothing posts) or approved straight away (posts as in 455)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS spgenericloan_create(text, text, numeric, numeric, numeric, timestamp, timestamp, timestamp, integer, text, text, text, text, text, integer, text, date);
DROP FUNCTION IF EXISTS spgenericloan_create(text, text, numeric, numeric, numeric, timestamp, timestamp, timestamp, integer, text, text, text, text, text, integer, text, date, boolean);

CREATE FUNCTION spgenericloan_create(
    p_farmid text, p_lendername text, p_originalprincipal numeric, p_amountreceived numeric,
    p_interestrate numeric, p_loandate timestamp, p_startdate timestamp, p_duedate timestamp,
    p_cashaccountid integer, p_notes text, p_createdby text,
    p_lendertype text DEFAULT 'Other', p_accountnumber text DEFAULT NULL, p_interesttype text DEFAULT NULL,
    p_termmonths integer DEFAULT NULL, p_paymentfrequency text DEFAULT NULL, p_nextpaymentdate date DEFAULT NULL,
    p_approve boolean DEFAULT TRUE)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE
    v_id   integer;
    v_recv numeric := COALESCE(p_amountreceived, 0);
    v_date timestamp := COALESCE(p_loandate, p_startdate, (now() AT TIME ZONE 'utc'));
BEGIN
    IF COALESCE(btrim(p_lendername), '') = '' THEN RAISE EXCEPTION 'Who lent the money?' USING ERRCODE = 'P0001'; END IF;
    IF COALESCE(p_originalprincipal, 0) <= 0 THEN RAISE EXCEPTION 'Enter the loan amount.' USING ERRCODE = 'P0001'; END IF;
    IF v_recv < 0 THEN RAISE EXCEPTION 'The amount received cannot be negative.' USING ERRCODE = 'P0001'; END IF;
    IF v_recv > p_originalprincipal THEN RAISE EXCEPTION 'Received cannot exceed the principal.' USING ERRCODE = 'P0001'; END IF;
    IF COALESCE(p_interestrate, 0) < 0 OR COALESCE(p_termmonths, 0) < 0 THEN
        RAISE EXCEPTION 'Rate and term cannot be negative.' USING ERRCODE = 'P0001';
    END IF;

    -- Saved as a Draft first; spgenericloan_approve does the posting, so a
    -- loan approved on save and one approved later post exactly the same way.
    INSERT INTO "GenericLoans"
        ("FarmId", "LenderName", "LenderType", "AccountNumber", "OriginalPrincipal", "AmountReceived",
         "InterestRate", "InterestType", "TermMonths", "PaymentFrequency", "NextPaymentDate",
         "OutstandingBalance", "LoanDate", "StartDate", "DueDate", "Status",
         "GenericCashAccountId", "Notes", "CreatedBy", "CreatedAt")
    VALUES (p_farmid, btrim(p_lendername), COALESCE(NULLIF(btrim(p_lendertype), ''), 'Other'), NULLIF(btrim(p_accountnumber), ''),
            p_originalprincipal, v_recv, COALESCE(p_interestrate, 0), NULLIF(btrim(p_interesttype), ''),
            p_termmonths, NULLIF(btrim(p_paymentfrequency), ''), p_nextpaymentdate,
            0, v_date, COALESCE(p_startdate, v_date), p_duedate, 'Draft',
            p_cashaccountid, NULLIF(btrim(p_notes), ''), p_createdby,
            (now() AT TIME ZONE 'utc'))
    RETURNING "GenericLoanId" INTO v_id;

    UPDATE "GenericLoans" SET "LoanNumber" = 'LN-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  "GenericLoanId" = v_id;

    IF COALESCE(p_approve, TRUE) THEN
        PERFORM spgenericloan_approve(v_id, p_farmid, p_createdby);
    END IF;
    RETURN v_id;
END
$fn$;

-- ---------------------------------------------------------------------------
-- approve: Draft -> Active. The money posts here and nowhere else.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS spgenericloan_approve(integer, text, text);

CREATE FUNCTION spgenericloan_approve(p_genericloanid integer, p_farmid text, p_approvedby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    v_status text; v_principal numeric; v_recv numeric; v_acct integer; v_date timestamp; v_lender text;
    v_now timestamp := (now() AT TIME ZONE 'utc');
BEGIN
    SELECT l."Status", l."OriginalPrincipal", COALESCE(l."AmountReceived", 0), l."GenericCashAccountId",
           COALESCE(l."LoanDate", l."CreatedAt"), l."LenderName"
    INTO   v_status, v_principal, v_recv, v_acct, v_date, v_lender
    FROM   "GenericLoans" l WHERE l."GenericLoanId" = p_genericloanid AND l."FarmId" = p_farmid FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Loan % not found.', p_genericloanid USING ERRCODE = 'P0001'; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a Draft loan can be approved; this one is %.',
            CASE WHEN v_status = 'Paid' THEN 'PaidOff' ELSE v_status END USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(btrim(v_lender), '') = '' THEN RAISE EXCEPTION 'Who lent the money?' USING ERRCODE = 'P0001'; END IF;
    IF COALESCE(v_principal, 0) <= 0 THEN RAISE EXCEPTION 'Enter the loan amount.' USING ERRCODE = 'P0001'; END IF;
    IF v_recv > v_principal THEN RAISE EXCEPTION 'Received cannot exceed the principal.' USING ERRCODE = 'P0001'; END IF;
    IF v_recv > 0 AND v_acct IS NULL THEN RAISE EXCEPTION 'Which account received it?' USING ERRCODE = 'P0001'; END IF;

    -- Money in, not revenue. One ledger row and the balance, together.
    IF v_recv > 0 THEN
        PERFORM fngenericcash_move(p_farmid, v_acct, v_recv, v_date, 'LoanReceived', p_genericloanid,
                                   'Loan from ' || btrim(v_lender), p_approvedby, FALSE);
    END IF;

    UPDATE "GenericLoans"
    SET    "Status" = 'Active', "OutstandingBalance" = v_principal,
           "TotalPrincipalPaid" = 0, "TotalInterestPaid" = 0, "TotalFeesPaid" = 0, "PaidOffDate" = NULL,
           -- An account only means something when money arrived in it.
           "GenericCashAccountId" = CASE WHEN v_recv > 0 THEN v_acct END,
           "ApprovedBy" = p_approvedby, "ApprovedAt" = v_now,
           "UpdatedBy" = p_approvedby, "UpdatedAt" = v_now
    WHERE  "GenericLoanId" = p_genericloanid AND "FarmId" = p_farmid;
END
$fn$;

-- ---------------------------------------------------------------------------
-- update: a Draft edits everything; an approved loan only the light fields
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS spgenericloan_update(integer, text, text, text, text, numeric, text, integer, text, date, date, text, text);
DROP FUNCTION IF EXISTS spgenericloan_update(integer, text, text, text, text, numeric, text, integer, text, date, date, text, text, numeric, numeric, integer, date);

CREATE FUNCTION spgenericloan_update(
    p_genericloanid integer, p_farmid text,
    p_lendername text DEFAULT NULL, p_lendertype text DEFAULT NULL, p_accountnumber text DEFAULT NULL,
    p_interestrate numeric DEFAULT NULL, p_interesttype text DEFAULT NULL, p_termmonths integer DEFAULT NULL,
    p_paymentfrequency text DEFAULT NULL, p_duedate date DEFAULT NULL, p_nextpaymentdate date DEFAULT NULL,
    p_notes text DEFAULT NULL, p_updatedby text DEFAULT NULL,
    p_originalprincipal numeric DEFAULT NULL, p_amountreceived numeric DEFAULT NULL,
    p_cashaccountid integer DEFAULT NULL, p_loandate date DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    l "GenericLoans"%ROWTYPE;
    v_principal numeric; v_recv numeric;
BEGIN
    SELECT * INTO l FROM "GenericLoans" g
    WHERE  g."GenericLoanId" = p_genericloanid AND g."FarmId" = p_farmid FOR UPDATE;
    IF l."GenericLoanId" IS NULL THEN RAISE EXCEPTION 'Loan % not found.', p_genericloanid USING ERRCODE = 'P0001'; END IF;
    IF l."Status" IN ('Cancelled', 'Reversed') THEN
        RAISE EXCEPTION 'A % loan cannot be edited.', l."Status" USING ERRCODE = 'P0001';
    END IF;

    -- Approved: light edit only. A field counts as changed only when it differs,
    -- so a form that sends the loan back unchanged is not refused.
    IF l."Status" <> 'Draft' AND (
           (p_originalprincipal IS NOT NULL AND p_originalprincipal IS DISTINCT FROM l."OriginalPrincipal")
        OR (p_amountreceived    IS NOT NULL AND p_amountreceived    IS DISTINCT FROM l."AmountReceived")
        OR (p_cashaccountid     IS NOT NULL AND p_cashaccountid     IS DISTINCT FROM l."GenericCashAccountId")
        OR (p_loandate          IS NOT NULL AND p_loandate          IS DISTINCT FROM l."LoanDate"::date)
        OR (p_interestrate      IS NOT NULL AND p_interestrate      IS DISTINCT FROM l."InterestRate")
        OR (NULLIF(btrim(p_interesttype), '')     IS NOT NULL AND btrim(p_interesttype)     IS DISTINCT FROM l."InterestType")
        OR (p_termmonths        IS NOT NULL AND p_termmonths        IS DISTINCT FROM l."TermMonths")
        OR (NULLIF(btrim(p_paymentfrequency), '') IS NOT NULL AND btrim(p_paymentfrequency) IS DISTINCT FROM l."PaymentFrequency")) THEN
        RAISE EXCEPTION 'This loan is approved. Only the lender, account number, due dates and notes can change. Reverse it to Draft to change the amounts or terms.'
            USING ERRCODE = 'P0001';
    END IF;

    IF COALESCE(p_interestrate, 0) < 0 OR COALESCE(p_termmonths, 0) < 0 THEN
        RAISE EXCEPTION 'Rate and term cannot be negative.' USING ERRCODE = 'P0001';
    END IF;

    v_principal := COALESCE(p_originalprincipal, l."OriginalPrincipal");
    v_recv      := COALESCE(p_amountreceived, l."AmountReceived");
    IF l."Status" = 'Draft' THEN
        IF COALESCE(v_principal, 0) <= 0 THEN RAISE EXCEPTION 'Enter the loan amount.' USING ERRCODE = 'P0001'; END IF;
        IF COALESCE(v_recv, 0) < 0 THEN RAISE EXCEPTION 'The amount received cannot be negative.' USING ERRCODE = 'P0001'; END IF;
        IF v_recv > v_principal THEN RAISE EXCEPTION 'Received cannot exceed the principal.' USING ERRCODE = 'P0001'; END IF;
    END IF;

    UPDATE "GenericLoans" g
    SET    "LenderName"        = COALESCE(NULLIF(btrim(p_lendername), ''), g."LenderName"),
           "LenderType"        = COALESCE(NULLIF(btrim(p_lendertype), ''), g."LenderType"),
           "AccountNumber"     = COALESCE(NULLIF(btrim(p_accountnumber), ''), g."AccountNumber"),
           "InterestRate"      = COALESCE(p_interestrate, g."InterestRate"),
           "InterestType"      = COALESCE(NULLIF(btrim(p_interesttype), ''), g."InterestType"),
           "TermMonths"        = COALESCE(p_termmonths, g."TermMonths"),
           "PaymentFrequency"  = COALESCE(NULLIF(btrim(p_paymentfrequency), ''), g."PaymentFrequency"),
           "DueDate"           = COALESCE(p_duedate::timestamp, g."DueDate"),
           "NextPaymentDate"   = COALESCE(p_nextpaymentdate, g."NextPaymentDate"),
           "Notes"             = COALESCE(NULLIF(btrim(p_notes), ''), g."Notes"),
           -- money fields: reached only on a Draft (refused above otherwise)
           "OriginalPrincipal" = v_principal,
           "AmountReceived"    = v_recv,
           "GenericCashAccountId" = COALESCE(p_cashaccountid, g."GenericCashAccountId"),
           "LoanDate"          = COALESCE(p_loandate::timestamp, g."LoanDate"),
           "StartDate"         = CASE WHEN p_loandate IS NOT NULL THEN p_loandate::timestamp ELSE g."StartDate" END,
           "UpdatedBy"         = p_updatedby,
           "UpdatedAt"         = (now() AT TIME ZONE 'utc')
    WHERE  g."GenericLoanId" = p_genericloanid AND g."FarmId" = p_farmid;

    IF l."Status" = 'Draft' AND p_loandate IS NOT NULL THEN
        UPDATE "GenericLoans"
        SET    "LoanNumber" = 'LN-' || to_char(p_loandate, 'YYYY') || '-' || lpad(p_genericloanid::text, 4, '0')
        WHERE  "GenericLoanId" = p_genericloanid AND "LoanNumber" LIKE 'LN-____-%';
    END IF;
END
$fn$;

-- ---------------------------------------------------------------------------
-- reverse: an approved loan goes back to Draft
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS spgenericloan_reverse(integer, text, text, text);

CREATE FUNCTION spgenericloan_reverse(p_genericloanid integer, p_farmid text, p_reason text, p_reversedby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    v_status text; v_recv numeric; v_acct integer; v_num text; v_paid integer;
    v_now timestamp := (now() AT TIME ZONE 'utc');
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to reverse a loan.' USING ERRCODE = 'P0001'; END IF;

    SELECT l."Status", COALESCE(l."AmountReceived", 0), l."GenericCashAccountId", l."LoanNumber"
    INTO   v_status, v_recv, v_acct, v_num
    FROM   "GenericLoans" l WHERE l."GenericLoanId" = p_genericloanid AND l."FarmId" = p_farmid FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Loan % not found.', p_genericloanid USING ERRCODE = 'P0001'; END IF;
    IF v_status = 'Draft' THEN RAISE EXCEPTION 'This loan is already a Draft; nothing has posted.' USING ERRCODE = 'P0001'; END IF;
    IF v_status IN ('Cancelled', 'Reversed') THEN RAISE EXCEPTION 'This loan is %.', v_status USING ERRCODE = 'P0001'; END IF;

    SELECT COUNT(*) INTO v_paid FROM "GenericLoanPayments" p
    WHERE  p."GenericLoanId" = p_genericloanid AND p."FarmId" = p_farmid AND NOT COALESCE(p."IsReversed", FALSE);
    IF v_paid > 0 THEN
        RAISE EXCEPTION 'This loan has % posted repayment(s); reverse them before reversing the loan.', v_paid USING ERRCODE = 'P0001';
    END IF;

    -- The money that arrived leaves again. Refuses if the account no longer holds it.
    IF v_recv > 0 AND v_acct IS NOT NULL THEN
        PERFORM fngenericcash_move(p_farmid, v_acct, -v_recv, v_now, 'LoanCancelled', p_genericloanid,
                                   'Reversed loan ' || COALESCE(v_num, p_genericloanid::text) || ' back to draft',
                                   p_reversedby, TRUE);
    END IF;

    UPDATE "GenericLoans"
    SET    "Status" = 'Draft', "OutstandingBalance" = 0,
           "TotalPrincipalPaid" = 0, "TotalInterestPaid" = 0, "TotalFeesPaid" = 0, "PaidOffDate" = NULL,
           "ApprovedBy" = NULL, "ApprovedAt" = NULL,
           "ReversedBy" = p_reversedby, "ReversedAt" = v_now, "ReversalReason" = btrim(p_reason),
           "UpdatedBy" = p_reversedby, "UpdatedAt" = v_now
    WHERE  "GenericLoanId" = p_genericloanid AND "FarmId" = p_farmid;
END
$fn$;

-- ---------------------------------------------------------------------------
-- cancel: a Draft only. An approved loan is reversed to Draft first.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS spgenericloan_cancel(integer, text, text, text);

CREATE FUNCTION spgenericloan_cancel(p_genericloanid integer, p_farmid text, p_reason text, p_cancelledby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    v_status text;
    v_now timestamp := (now() AT TIME ZONE 'utc');
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to cancel a loan.' USING ERRCODE = 'P0001'; END IF;

    SELECT l."Status" INTO v_status
    FROM   "GenericLoans" l WHERE l."GenericLoanId" = p_genericloanid AND l."FarmId" = p_farmid FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Loan % not found.', p_genericloanid USING ERRCODE = 'P0001'; END IF;
    IF v_status IN ('Cancelled', 'Reversed') THEN RAISE EXCEPTION 'This loan is already %.', v_status USING ERRCODE = 'P0001'; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a Draft loan can be cancelled. Reverse this one to Draft first.' USING ERRCODE = 'P0001';
    END IF;

    UPDATE "GenericLoans"
    SET    "Status" = 'Cancelled', "OutstandingBalance" = 0, "CancelledBy" = p_cancelledby, "CancelledAt" = v_now,
           "CancelReason" = btrim(p_reason), "UpdatedBy" = p_cancelledby, "UpdatedAt" = v_now
    WHERE  "GenericLoanId" = p_genericloanid AND "FarmId" = p_farmid;
END
$fn$;

-- ---------------------------------------------------------------------------
-- list: 455's columns in the same order, plus the approval / reversal trail.
-- 484 reads it with SELECT * and names its columns, so adding at the end is safe.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS spgenericloan_list(text);

CREATE FUNCTION spgenericloan_list(p_farmid text)
RETURNS TABLE("GenericLoanId" integer, "FarmId" text, "LenderName" text, "OriginalPrincipal" numeric,
              "AmountReceived" numeric, "InterestRate" numeric, "TotalInterestPaid" numeric, "TotalFeesPaid" numeric,
              "TotalPrincipalPaid" numeric, "OutstandingBalance" numeric, "LoanDate" timestamp, "StartDate" timestamp,
              "DueDate" timestamp, "Status" text, "Notes" text, "CreatedAt" timestamp,
              "LoanNumber" text, "LenderType" text, "AccountNumber" text, "InterestType" text, "TermMonths" integer,
              "PaymentFrequency" text, "NextPaymentDate" date, "GenericCashAccountId" integer, "AccountName" text,
              "PaymentCount" integer, "IsOverdue" boolean, "PaidOffDate" timestamp, "CancelReason" text,
              "ApprovedBy" text, "ApprovedAt" timestamp, "ReversedAt" timestamp, "ReversalReason" text)
LANGUAGE sql STABLE AS $fn$
    SELECT l."GenericLoanId", l."FarmId", l."LenderName", l."OriginalPrincipal", l."AmountReceived",
           l."InterestRate", l."TotalInterestPaid", l."TotalFeesPaid", l."TotalPrincipalPaid",
           l."OutstandingBalance", l."LoanDate", l."StartDate", l."DueDate",
           CASE WHEN l."Status" = 'Paid' THEN 'PaidOff' ELSE l."Status" END::text,
           l."Notes", l."CreatedAt",
           l."LoanNumber", l."LenderType", l."AccountNumber", l."InterestType", l."TermMonths",
           l."PaymentFrequency", l."NextPaymentDate", l."GenericCashAccountId", a.accountname::text,
           (SELECT COUNT(*) FROM "GenericLoanPayments" p
            WHERE p."GenericLoanId" = l."GenericLoanId" AND NOT COALESCE(p."IsReversed", FALSE))::int,
           (l."Status" = 'Active' AND l."NextPaymentDate" IS NOT NULL
            AND l."NextPaymentDate" < CURRENT_DATE AND l."OutstandingBalance" > 0),
           l."PaidOffDate", l."CancelReason",
           l."ApprovedBy", l."ApprovedAt", l."ReversedAt", l."ReversalReason"
    FROM   "GenericLoans" l
    LEFT   JOIN genericcashaccounts a ON a.genericcashaccountid = l."GenericCashAccountId"
    WHERE  l."FarmId" = p_farmid
    ORDER  BY l."LoanDate" DESC, l."GenericLoanId" DESC;
$fn$;

COMMIT;
