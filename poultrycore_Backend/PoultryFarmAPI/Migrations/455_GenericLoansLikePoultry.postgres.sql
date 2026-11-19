-- 455: Generic Loans (Financing) brought up to Poultry's loans (254).
--
-- WHAT WAS WRONG
--   * spgenericloan_create / _repay moved money with
--       UPDATE "GenericCashAccounts" ...
--     That table does not exist (the real one is genericcashaccounts), so any
--     loan or repayment with a cash account failed outright: "saves that don't
--     save". Without an account they saved, but moved no cash and wrote no row
--     to genericcashtransactions, so the account ledger, the cash summary and
--     reconciliation never saw them.
--   * Lender type, interest type and frequency were flattened into Notes; there
--     was no loan number, account number, term, next payment date, edit, cancel
--     or reversal.
--
-- WHAT THIS DOES
--   * New real columns on "GenericLoans" / "GenericLoanPayments".
--   * Every cash move goes through fngenericcash_move (one ledger row + the
--     balance, in one place). Repayments refuse to overdraw the account and
--     refuse principal above what is still owed. A received amount needs an
--     account.
--   * spgenericloan_update / _cancel and spgenericloanpayment_reverse, with
--     Poultry's rules (cancel only without posted repayments; a reason is
--     required for cancel and reverse).
--   * spgenericloan_list / _payments return the new fields. The existing column
--     names stay, so GenericProfitLoss (which reads both with SELECT *) is
--     unchanged. _payments now also returns reversed rows (with "IsReversed",
--     which every reader already filters on) and NULL loan id = every payment.
--
-- READERS (each loan event still counts exactly once)
--   * spgenericcashflow_rows arms 7/8 read the loan tables directly and never
--     the ledger rows written here: unchanged. A cancelled loan drops out of
--     arm 7 (it only takes Active/Paid), a reversed payment out of arm 8.
--   * Stored status stays 'Active' / 'Paid' / 'Cancelled' because arm 7 filters
--     on it; spgenericloan_list shows 'Paid' as 'PaidOff' like Poultry.
--
-- NO BACKFILL OF LEDGER ROWS: the old SPs could never have moved a balance
-- (the table they updated does not exist, so those saves rolled back), so no
-- existing loan or payment has money that is missing a ledger row.

ALTER TABLE "GenericLoans"
    ADD COLUMN IF NOT EXISTS "LoanNumber"       text,
    ADD COLUMN IF NOT EXISTS "LenderType"       text NOT NULL DEFAULT 'Other',
    ADD COLUMN IF NOT EXISTS "AccountNumber"    text,
    ADD COLUMN IF NOT EXISTS "InterestType"     text,
    ADD COLUMN IF NOT EXISTS "TermMonths"       integer,
    ADD COLUMN IF NOT EXISTS "PaymentFrequency" text,
    ADD COLUMN IF NOT EXISTS "NextPaymentDate"  date,
    ADD COLUMN IF NOT EXISTS "PaidOffDate"      timestamp,
    ADD COLUMN IF NOT EXISTS "CancelledBy"      text,
    ADD COLUMN IF NOT EXISTS "CancelledAt"      timestamp,
    ADD COLUMN IF NOT EXISTS "CancelReason"     text,
    ADD COLUMN IF NOT EXISTS "UpdatedBy"        text,
    ADD COLUMN IF NOT EXISTS "UpdatedAt"        timestamp;

ALTER TABLE "GenericLoanPayments"
    ADD COLUMN IF NOT EXISTS "PaymentNumber"   text,
    ADD COLUMN IF NOT EXISTS "OtherAmount"     numeric NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS "PaymentMethod"   text,
    ADD COLUMN IF NOT EXISTS "ReferenceNumber" text,
    ADD COLUMN IF NOT EXISTS "ReversedBy"      text,
    ADD COLUMN IF NOT EXISTS "ReversedAt"      timestamp,
    ADD COLUMN IF NOT EXISTS "ReversalReason"  text;

UPDATE "GenericLoans" SET "LoanNumber" = 'LN-' || to_char(COALESCE("LoanDate", "CreatedAt"), 'YYYY') || '-' || lpad("GenericLoanId"::text, 4, '0')
WHERE  "LoanNumber" IS NULL;
UPDATE "GenericLoanPayments" SET "PaymentNumber" = 'LP-' || to_char(COALESCE("PaymentDate", "CreatedAt"), 'YYYY') || '-' || lpad("GenericLoanPaymentId"::text, 4, '0')
WHERE  "PaymentNumber" IS NULL;

-- ---------------------------------------------------------------------------
-- create
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS spgenericloan_create(text, text, numeric, numeric, numeric, timestamp, timestamp, timestamp, integer, text, text);
DROP FUNCTION IF EXISTS spgenericloan_create(text, text, numeric, numeric, numeric, timestamp, timestamp, timestamp, integer, text, text, text, text, text, integer, text, date);

CREATE FUNCTION spgenericloan_create(
    p_farmid text, p_lendername text, p_originalprincipal numeric, p_amountreceived numeric,
    p_interestrate numeric, p_loandate timestamp, p_startdate timestamp, p_duedate timestamp,
    p_cashaccountid integer, p_notes text, p_createdby text,
    p_lendertype text DEFAULT 'Other', p_accountnumber text DEFAULT NULL, p_interesttype text DEFAULT NULL,
    p_termmonths integer DEFAULT NULL, p_paymentfrequency text DEFAULT NULL, p_nextpaymentdate date DEFAULT NULL)
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
    IF v_recv > 0 AND p_cashaccountid IS NULL THEN RAISE EXCEPTION 'Which account received it?' USING ERRCODE = 'P0001'; END IF;
    IF COALESCE(p_interestrate, 0) < 0 OR COALESCE(p_termmonths, 0) < 0 THEN
        RAISE EXCEPTION 'Rate and term cannot be negative.' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO "GenericLoans"
        ("FarmId", "LenderName", "LenderType", "AccountNumber", "OriginalPrincipal", "AmountReceived",
         "InterestRate", "InterestType", "TermMonths", "PaymentFrequency", "NextPaymentDate",
         "OutstandingBalance", "LoanDate", "StartDate", "DueDate", "Status",
         "GenericCashAccountId", "Notes", "CreatedBy", "CreatedAt")
    VALUES (p_farmid, btrim(p_lendername), COALESCE(NULLIF(btrim(p_lendertype), ''), 'Other'), NULLIF(btrim(p_accountnumber), ''),
            p_originalprincipal, v_recv, COALESCE(p_interestrate, 0), NULLIF(btrim(p_interesttype), ''),
            p_termmonths, NULLIF(btrim(p_paymentfrequency), ''), p_nextpaymentdate,
            p_originalprincipal, v_date, COALESCE(p_startdate, v_date), p_duedate, 'Active',
            CASE WHEN v_recv > 0 THEN p_cashaccountid END, NULLIF(btrim(p_notes), ''), p_createdby,
            (now() AT TIME ZONE 'utc'))
    RETURNING "GenericLoanId" INTO v_id;

    UPDATE "GenericLoans" SET "LoanNumber" = 'LN-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  "GenericLoanId" = v_id;

    -- Money in, not revenue. One ledger row and the balance, together.
    IF v_recv > 0 THEN
        PERFORM fngenericcash_move(p_farmid, p_cashaccountid, v_recv, v_date, 'LoanReceived', v_id,
                                   'Loan from ' || btrim(p_lendername), p_createdby, FALSE);
    END IF;
    RETURN v_id;
END
$fn$;

-- ---------------------------------------------------------------------------
-- update (terms only; the money is never edited, as on Poultry)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS spgenericloan_update(integer, text, text, text, text, numeric, text, integer, text, date, date, text, text);

CREATE FUNCTION spgenericloan_update(
    p_genericloanid integer, p_farmid text,
    p_lendername text DEFAULT NULL, p_lendertype text DEFAULT NULL, p_accountnumber text DEFAULT NULL,
    p_interestrate numeric DEFAULT NULL, p_interesttype text DEFAULT NULL, p_termmonths integer DEFAULT NULL,
    p_paymentfrequency text DEFAULT NULL, p_duedate date DEFAULT NULL, p_nextpaymentdate date DEFAULT NULL,
    p_notes text DEFAULT NULL, p_updatedby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE v_status text;
BEGIN
    SELECT l."Status" INTO v_status FROM "GenericLoans" l
    WHERE  l."GenericLoanId" = p_genericloanid AND l."FarmId" = p_farmid FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Loan % not found.', p_genericloanid USING ERRCODE = 'P0001'; END IF;
    IF v_status IN ('Cancelled', 'Reversed') THEN
        RAISE EXCEPTION 'A % loan cannot be edited.', v_status USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(p_interestrate, 0) < 0 OR COALESCE(p_termmonths, 0) < 0 THEN
        RAISE EXCEPTION 'Rate and term cannot be negative.' USING ERRCODE = 'P0001';
    END IF;

    UPDATE "GenericLoans" l
    SET    "LenderName"       = COALESCE(NULLIF(btrim(p_lendername), ''), l."LenderName"),
           "LenderType"       = COALESCE(NULLIF(btrim(p_lendertype), ''), l."LenderType"),
           "AccountNumber"    = COALESCE(NULLIF(btrim(p_accountnumber), ''), l."AccountNumber"),
           "InterestRate"     = COALESCE(p_interestrate, l."InterestRate"),
           "InterestType"     = COALESCE(NULLIF(btrim(p_interesttype), ''), l."InterestType"),
           "TermMonths"       = COALESCE(p_termmonths, l."TermMonths"),
           "PaymentFrequency" = COALESCE(NULLIF(btrim(p_paymentfrequency), ''), l."PaymentFrequency"),
           "DueDate"          = COALESCE(p_duedate::timestamp, l."DueDate"),
           "NextPaymentDate"  = COALESCE(p_nextpaymentdate, l."NextPaymentDate"),
           "Notes"            = COALESCE(NULLIF(btrim(p_notes), ''), l."Notes"),
           "UpdatedBy"        = p_updatedby,
           "UpdatedAt"        = (now() AT TIME ZONE 'utc')
    WHERE  l."GenericLoanId" = p_genericloanid AND l."FarmId" = p_farmid;
END
$fn$;

-- ---------------------------------------------------------------------------
-- cancel: only with no posted repayments; the money received goes back
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS spgenericloan_cancel(integer, text, text, text);

CREATE FUNCTION spgenericloan_cancel(p_genericloanid integer, p_farmid text, p_reason text, p_cancelledby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    v_status text; v_recv numeric; v_acct integer; v_num text; v_paid integer;
    v_now timestamp := (now() AT TIME ZONE 'utc');
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to cancel a loan.' USING ERRCODE = 'P0001'; END IF;

    SELECT l."Status", l."AmountReceived", l."GenericCashAccountId", l."LoanNumber"
    INTO   v_status, v_recv, v_acct, v_num
    FROM   "GenericLoans" l WHERE l."GenericLoanId" = p_genericloanid AND l."FarmId" = p_farmid FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Loan % not found.', p_genericloanid USING ERRCODE = 'P0001'; END IF;
    IF v_status IN ('Cancelled', 'Reversed') THEN RAISE EXCEPTION 'This loan is already %.', v_status USING ERRCODE = 'P0001'; END IF;

    SELECT COUNT(*) INTO v_paid FROM "GenericLoanPayments" p
    WHERE  p."GenericLoanId" = p_genericloanid AND p."FarmId" = p_farmid AND NOT COALESCE(p."IsReversed", FALSE);
    IF v_paid > 0 THEN
        RAISE EXCEPTION 'This loan has % posted repayment(s); reverse them before cancelling it.', v_paid USING ERRCODE = 'P0001';
    END IF;

    -- The money that arrived has to leave again, or the account keeps cash from
    -- a loan that no longer exists. Refuses if the account no longer holds it.
    IF COALESCE(v_recv, 0) > 0 AND v_acct IS NOT NULL THEN
        PERFORM fngenericcash_move(p_farmid, v_acct, -v_recv, v_now, 'LoanCancelled', p_genericloanid,
                                   'Cancelled loan ' || COALESCE(v_num, p_genericloanid::text), p_cancelledby, TRUE);
    END IF;

    UPDATE "GenericLoans"
    SET    "Status" = 'Cancelled', "OutstandingBalance" = 0, "CancelledBy" = p_cancelledby, "CancelledAt" = v_now,
           "CancelReason" = btrim(p_reason), "UpdatedBy" = p_cancelledby, "UpdatedAt" = v_now
    WHERE  "GenericLoanId" = p_genericloanid AND "FarmId" = p_farmid;
END
$fn$;

-- ---------------------------------------------------------------------------
-- repay
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS spgenericloan_repay(integer, text, numeric, numeric, numeric, timestamp, integer, text, text);
DROP FUNCTION IF EXISTS spgenericloan_repay(integer, text, numeric, numeric, numeric, timestamp, integer, text, text, numeric, text, text, date);

CREATE FUNCTION spgenericloan_repay(
    p_genericloanid integer, p_farmid text, p_principalamount numeric, p_interestamount numeric,
    p_feeamount numeric, p_paymentdate timestamp, p_cashaccountid integer, p_notes text, p_createdby text,
    p_otheramount numeric DEFAULT 0, p_paymentmethod text DEFAULT NULL, p_referencenumber text DEFAULT NULL,
    p_nextpaymentdate date DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE
    v_id integer; v_status text; v_owed numeric; v_lender text; v_num text;
    v_p numeric := COALESCE(p_principalamount, 0);
    v_i numeric := COALESCE(p_interestamount, 0);
    v_f numeric := COALESCE(p_feeamount, 0);
    v_o numeric := COALESCE(p_otheramount, 0);
    v_total numeric;
    v_date timestamp := COALESCE(p_paymentdate, (now() AT TIME ZONE 'utc'));
BEGIN
    v_total := v_p + v_i + v_f + v_o;
    IF v_p < 0 OR v_i < 0 OR v_f < 0 OR v_o < 0 THEN RAISE EXCEPTION 'Amounts cannot be negative.' USING ERRCODE = 'P0001'; END IF;
    IF v_total <= 0 THEN RAISE EXCEPTION 'Enter the repayment.' USING ERRCODE = 'P0001'; END IF;
    IF p_cashaccountid IS NULL THEN RAISE EXCEPTION 'Pick a cash account.' USING ERRCODE = 'P0001'; END IF;

    SELECT l."Status", l."OutstandingBalance", l."LenderName", l."LoanNumber"
    INTO   v_status, v_owed, v_lender, v_num
    FROM   "GenericLoans" l WHERE l."GenericLoanId" = p_genericloanid AND l."FarmId" = p_farmid FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Loan % not found.', p_genericloanid USING ERRCODE = 'P0001'; END IF;
    IF v_status <> 'Active' THEN RAISE EXCEPTION 'Only an active loan can be repaid (this one is %).', v_status USING ERRCODE = 'P0001'; END IF;
    IF v_p > v_owed THEN RAISE EXCEPTION 'Principal is more than is owed (%).', v_owed USING ERRCODE = 'P0001'; END IF;

    INSERT INTO "GenericLoanPayments"
        ("GenericLoanId", "FarmId", "PaymentDate", "PrincipalAmount", "InterestAmount", "FeeAmount", "OtherAmount",
         "TotalPayment", "GenericCashAccountId", "PaymentMethod", "ReferenceNumber", "Notes", "CreatedBy", "CreatedAt")
    VALUES (p_genericloanid, p_farmid, v_date, v_p, v_i, v_f, v_o, v_total, p_cashaccountid,
            NULLIF(btrim(p_paymentmethod), ''), NULLIF(btrim(p_referencenumber), ''), NULLIF(btrim(p_notes), ''),
            p_createdby, (now() AT TIME ZONE 'utc'))
    RETURNING "GenericLoanPaymentId" INTO v_id;

    UPDATE "GenericLoanPayments" SET "PaymentNumber" = 'LP-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  "GenericLoanPaymentId" = v_id;

    UPDATE "GenericLoans" l
    SET    "TotalPrincipalPaid" = l."TotalPrincipalPaid" + v_p,
           "TotalInterestPaid"  = l."TotalInterestPaid" + v_i,
           "TotalFeesPaid"      = l."TotalFeesPaid" + v_f,
           "OutstandingBalance" = l."OutstandingBalance" - v_p,
           "Status"             = CASE WHEN l."OutstandingBalance" - v_p <= 0 THEN 'Paid' ELSE l."Status" END,
           "PaidOffDate"        = CASE WHEN l."OutstandingBalance" - v_p <= 0 THEN v_date ELSE l."PaidOffDate" END,
           "NextPaymentDate"    = COALESCE(p_nextpaymentdate, l."NextPaymentDate"),
           "UpdatedBy" = p_createdby, "UpdatedAt" = (now() AT TIME ZONE 'utc')
    WHERE  l."GenericLoanId" = p_genericloanid AND l."FarmId" = p_farmid;

    -- The whole total leaves the account once; refuses to overdraw it.
    PERFORM fngenericcash_move(p_farmid, p_cashaccountid, -v_total, v_date, 'LoanRepayment', v_id,
                               'Loan repayment ' || COALESCE(v_num, '') || ' - ' || COALESCE(v_lender, ''), p_createdby, TRUE);
    RETURN v_id;
END
$fn$;

-- ---------------------------------------------------------------------------
-- reverse a repayment
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS spgenericloanpayment_reverse(integer, text, text, text);

CREATE FUNCTION spgenericloanpayment_reverse(p_genericloanpaymentid integer, p_farmid text, p_reason text, p_reversedby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE
    v_loan integer; v_rev boolean; v_total numeric; v_p numeric; v_i numeric; v_f numeric; v_acct integer;
    v_num text; v_lstatus text;
    v_now timestamp := (now() AT TIME ZONE 'utc');
BEGIN
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to reverse a repayment.' USING ERRCODE = 'P0001'; END IF;

    SELECT p."GenericLoanId", COALESCE(p."IsReversed", FALSE), p."TotalPayment", p."PrincipalAmount",
           p."InterestAmount", p."FeeAmount", p."GenericCashAccountId", p."PaymentNumber"
    INTO   v_loan, v_rev, v_total, v_p, v_i, v_f, v_acct, v_num
    FROM   "GenericLoanPayments" p
    WHERE  p."GenericLoanPaymentId" = p_genericloanpaymentid AND p."FarmId" = p_farmid FOR UPDATE;
    IF v_loan IS NULL THEN RAISE EXCEPTION 'Loan payment % not found.', p_genericloanpaymentid USING ERRCODE = 'P0001'; END IF;
    IF v_rev THEN RAISE EXCEPTION 'This repayment is already reversed.' USING ERRCODE = 'P0001'; END IF;

    SELECT l."Status" INTO v_lstatus FROM "GenericLoans" l WHERE l."GenericLoanId" = v_loan AND l."FarmId" = p_farmid FOR UPDATE;
    IF v_lstatus = 'Cancelled' THEN RAISE EXCEPTION 'The loan is cancelled.' USING ERRCODE = 'P0001'; END IF;

    -- The money comes back into the account it left. Repayments saved before
    -- 455 without an account never moved cash, so nothing comes back for them.
    IF v_acct IS NOT NULL AND COALESCE(v_total, 0) > 0 THEN
        PERFORM fngenericcash_move(p_farmid, v_acct, v_total, v_now, 'LoanRepaymentReversal', p_genericloanpaymentid,
                                   'Reversal of repayment ' || COALESCE(v_num, p_genericloanpaymentid::text), p_reversedby, FALSE);
    END IF;

    -- The debt goes back up; a paid-off loan is live again. Interest and fees
    -- leave the P&L because every reader skips reversed payments.
    UPDATE "GenericLoans" l
    SET    "OutstandingBalance" = l."OutstandingBalance" + v_p,
           "TotalPrincipalPaid" = GREATEST(l."TotalPrincipalPaid" - v_p, 0),
           "TotalInterestPaid"  = GREATEST(l."TotalInterestPaid" - v_i, 0),
           "TotalFeesPaid"      = GREATEST(l."TotalFeesPaid" - v_f, 0),
           "Status"      = CASE WHEN l."Status" = 'Paid' AND l."OutstandingBalance" + v_p > 0 THEN 'Active' ELSE l."Status" END,
           "PaidOffDate" = CASE WHEN l."OutstandingBalance" + v_p > 0 THEN NULL ELSE l."PaidOffDate" END,
           "UpdatedBy" = p_reversedby, "UpdatedAt" = v_now
    WHERE  l."GenericLoanId" = v_loan AND l."FarmId" = p_farmid;

    UPDATE "GenericLoanPayments"
    SET    "IsReversed" = TRUE, "ReversedBy" = p_reversedby, "ReversedAt" = v_now, "ReversalReason" = btrim(p_reason)
    WHERE  "GenericLoanPaymentId" = p_genericloanpaymentid AND "FarmId" = p_farmid;
END
$fn$;

-- ---------------------------------------------------------------------------
-- reads (old column names kept first: GenericProfitLoss reads them)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS spgenericloan_list(text);

CREATE FUNCTION spgenericloan_list(p_farmid text)
RETURNS TABLE("GenericLoanId" integer, "FarmId" text, "LenderName" text, "OriginalPrincipal" numeric,
              "AmountReceived" numeric, "InterestRate" numeric, "TotalInterestPaid" numeric, "TotalFeesPaid" numeric,
              "TotalPrincipalPaid" numeric, "OutstandingBalance" numeric, "LoanDate" timestamp, "StartDate" timestamp,
              "DueDate" timestamp, "Status" text, "Notes" text, "CreatedAt" timestamp,
              "LoanNumber" text, "LenderType" text, "AccountNumber" text, "InterestType" text, "TermMonths" integer,
              "PaymentFrequency" text, "NextPaymentDate" date, "GenericCashAccountId" integer, "AccountName" text,
              "PaymentCount" integer, "IsOverdue" boolean, "PaidOffDate" timestamp, "CancelReason" text)
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
           l."PaidOffDate", l."CancelReason"
    FROM   "GenericLoans" l
    LEFT   JOIN genericcashaccounts a ON a.genericcashaccountid = l."GenericCashAccountId"
    WHERE  l."FarmId" = p_farmid
    ORDER  BY l."LoanDate" DESC, l."GenericLoanId" DESC;
$fn$;

DROP FUNCTION IF EXISTS spgenericloan_payments(integer, text);

CREATE FUNCTION spgenericloan_payments(p_genericloanid integer, p_farmid text)
RETURNS TABLE("GenericLoanPaymentId" integer, "GenericLoanId" integer, "PaymentDate" timestamp,
              "PrincipalAmount" numeric, "InterestAmount" numeric, "FeeAmount" numeric, "TotalPayment" numeric,
              "Notes" text, "IsReversed" boolean, "CreatedAt" timestamp,
              "OtherAmount" numeric, "PaymentNumber" text, "PaymentMethod" text, "ReferenceNumber" text,
              "GenericCashAccountId" integer, "AccountName" text, "Status" text, "LoanNumber" text,
              "ReversedAt" timestamp, "ReversalReason" text)
LANGUAGE sql STABLE AS $fn$
    SELECT p."GenericLoanPaymentId", p."GenericLoanId", p."PaymentDate", p."PrincipalAmount", p."InterestAmount",
           p."FeeAmount", p."TotalPayment", p."Notes", COALESCE(p."IsReversed", FALSE), p."CreatedAt",
           p."OtherAmount", p."PaymentNumber", p."PaymentMethod", p."ReferenceNumber",
           p."GenericCashAccountId", a.accountname::text,
           CASE WHEN COALESCE(p."IsReversed", FALSE) THEN 'Reversed' ELSE 'Posted' END,
           l."LoanNumber", p."ReversedAt", p."ReversalReason"
    FROM   "GenericLoanPayments" p
    JOIN   "GenericLoans" l ON l."GenericLoanId" = p."GenericLoanId"
    LEFT   JOIN genericcashaccounts a ON a.genericcashaccountid = p."GenericCashAccountId"
    WHERE  p."FarmId" = p_farmid AND (p_genericloanid IS NULL OR p."GenericLoanId" = p_genericloanid)
    ORDER  BY p."PaymentDate" DESC, p."GenericLoanPaymentId" DESC;
$fn$;
