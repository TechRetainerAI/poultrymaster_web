-- =============================================================================
-- 245_PoultryExpenseEntryPayments.postgres.sql
--
-- Purpose
-- -------
-- Money paid on a bill AT ENTRY becomes a real supplier payment, so it appears
-- on the Supplier Payments ledger alongside money paid later through Supplier
-- Balances.
--
-- The gap this closes
-- -------------------
-- Since 238 there have been two ways to pay an expense, and only one of them
-- left a record:
--
--   Pay bill (RecordPaymentDialog)  -> sppoultrysupplierpayment_record
--                                      -> payment header + allocation.  VISIBLE.
--   Create/edit the expense with a  -> spexpense_insert / _update writes
--   payment status                     expense.amountpaid directly.     INVISIBLE.
--
-- That was a deliberate tolerance, not an oversight -- fnbalanceaudit's comment
-- in 238 says so outright: "an expense can be part-paid at entry, before any
-- payment record exists, so allocations must never EXCEED what was paid but are
-- not expected to equal it." The audit only ever flagged an overshoot, so money
-- entered directly was legal and unreported.
--
-- After this migration the two paths converge: a bill that names a supplier
-- records its entry payment the same way Supplier Balances does.
--
-- Four things this file has to get right
-- --------------------------------------
--
-- 1. CASH IS POSTED ONCE, BY THE PAYMENT. 238 already narrowed an expense's own
--    cash line to "resolved amountpaid MINUS posted allocations". So once the
--    entry payment IS an allocation, that line resolves to zero and the
--    payment's single CashOut carries the money. Nothing changes about how much
--    cash moves, only which row moves it. sppoultryexpensecash_sync is still
--    called afterwards by ExpenseService and is still correct -- it now posts
--    zero for these rows.
--
-- 2. THE ROW IS INSERTED UNPAID, THEN THE PAYMENT RAISES IT. _record does
--    `amountpaid = LEAST(COALESCE(amountpaid, amount) + applied, amount)` --
--    it ADDS. Writing the paid figure at insert AND allocating it would land
--    double. So a bill that is going to record a payment is written with
--    amountpaid = 0 and the payment moves it to where it belongs.
--
-- 3. NULL IS THE "PAID IN FULL" SENTINEL AND MUST NOT LEAK INTO THIS PATH.
--    238 stores a fully paid expense as amountpaid = NULL. If that were written
--    before the payment ran, COALESCE(amountpaid, amount) would read as fully
--    paid and the allocation would overshoot into 238's own guard. Every row on
--    this path carries an explicit number until the payment has finished with it.
--
-- 4. ONLY A BILL THAT HAS SOMEONE TO PAY. No supplierid means no creditor and
--    therefore no payment to record -- petty cash keeps behaving exactly as it
--    does today. NonCash (216, internal use) never moves money and is excluded
--    outright, the same test every other arm applies.
--
-- REDUCING WHAT WAS PAID
-- ----------------------
-- Nothing new is needed: 238's spexpense_update already refuses to set
-- amountpaid below what allocations have settled, with a message naming the
-- figure. Entry payments simply become subject to a guard that was already
-- there -- to take money back you reverse the payment, which leaves the
-- reversal in the ledger instead of quietly rewriting the row.
--
-- EFFECT ON TODAY'S NUMBERS: none. No existing row is read or rewritten, and
-- there is no backfill. Historical expenses keep amountpaid exactly as it is and
-- gain no retrospective payment records -- inventing payments nobody made would
-- be worse than the gap this closes. Only bills entered from now on are affected.
--
-- Order: 245, then 246 (water). Each is independent of the other.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Shared decision: does this bill record a payment?
-- -----------------------------------------------------------------------------
-- One place, so insert and update can never disagree about it. Returning a
-- boolean rather than inlining the test twice is the whole point -- the two
-- callers drifting apart is exactly how a bill would record a payment on
-- creation and then silently stop on the next edit.
CREATE OR REPLACE FUNCTION public.fnpoultryexpenserecordspayment(
    p_supplierid    integer,
    p_paymentmethod text,
    p_amountpaid    numeric)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT p_supplierid IS NOT NULL
       AND COALESCE(p_paymentmethod, '') <> 'NonCash'
       AND COALESCE(p_amountpaid, 0) > 0;
$function$;

COMMENT ON FUNCTION public.fnpoultryexpenserecordspayment(integer, text, numeric) IS
    'Whether money paid on an expense should be recorded as a supplier payment. '
    'False for a bill with no supplier (nobody to owe, so nothing to record), '
    'for NonCash internal costs (no money moved), and for nothing paid.';

-- -----------------------------------------------------------------------------
-- 2. Insert.
-- -----------------------------------------------------------------------------
-- Gains p_cashaccountid. It has to: the payment posts the CashOut now, and a
-- payment with no account posts none at all -- which, combined with the expense
-- line resolving to zero, would lose the cash entirely. ExpenseService already
-- holds the account (it passes it to sppoultryexpensecash_sync straight after)
-- and now passes it here too.
--
-- The parameter is LAST and defaulted, so the existing call still binds while
-- the API is redeployed.
DROP FUNCTION IF EXISTS public.spexpense_insert(timestamp without time zone, text, text,
    numeric, text, text, integer, text, uuid, bytea, text, integer, numeric, date);

CREATE OR REPLACE FUNCTION public.spexpense_insert(
    p_expensedate           timestamp without time zone,
    p_category              text,
    p_description           text,
    p_amount                numeric,
    p_paymentmethod         text,
    p_supplier              text,
    p_flockid               integer,
    p_userid                text,
    p_farmid                uuid,
    p_attachmentimage       bytea   DEFAULT NULL,
    p_attachmentcontenttype text    DEFAULT NULL,
    p_supplierid            integer DEFAULT NULL,
    p_amountpaid            numeric DEFAULT NULL,
    p_duedate               date    DEFAULT NULL,
    p_cashaccountid         integer DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id        integer;
    v_paid      numeric(14,2) := p_amountpaid;
    v_entrypaid numeric(14,2);
    v_pays      boolean;
    v_farmtext  text;
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than 0.';
    END IF;
    IF v_paid IS NOT NULL THEN
        IF v_paid < 0 THEN
            RAISE EXCEPTION 'Amount paid cannot be negative.';
        END IF;
        IF v_paid > p_amount THEN
            RAISE EXCEPTION 'Amount paid (%) cannot exceed the expense total (%).',
                  v_paid::numeric(14,2), p_amount::numeric(14,2);
        END IF;
    END IF;
    IF p_supplierid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM supplier s
                       WHERE s.supplierid = p_supplierid
                         AND lower(s.farmid::text) = lower(p_farmid::text)) THEN
        RAISE EXCEPTION 'Supplier does not belong to this company.';
    END IF;

    -- Resolved: NULL has always meant "paid in full", so that is what was paid.
    v_entrypaid := COALESCE(v_paid, p_amount);
    -- The account is REQUIRED, and that is a safety interlock, not a nicety.
    -- sppoultrysupplierpaymentcash_sync posts the CashOut only when the payment
    -- names an account. Recording a payment without one would leave no CashOut
    -- AND zero the expense's own cash line (it resolves to paid-minus-
    -- allocations), so the money would simply disappear from the account.
    --
    -- It also makes this migration safe to apply BEFORE the API is redeployed:
    -- an older caller binds no account, so v_pays is false and the bill takes
    -- byte-for-byte the path it takes today. Payments start being recorded when
    -- the API that passes the account goes out, not a moment sooner.
    v_pays := fnpoultryexpenserecordspayment(p_supplierid, p_paymentmethod, v_entrypaid)
              AND p_cashaccountid IS NOT NULL;

    IF v_pays THEN
        -- Written UNPAID on purpose. _record ADDS to amountpaid, so the payment
        -- below is what moves it to v_entrypaid. Zero, never NULL: NULL reads as
        -- paid in full and the allocation would overshoot 238's guard.
        v_paid := 0;
    ELSIF v_paid IS NOT NULL AND v_paid >= p_amount THEN
        -- Unchanged legacy shape: a fully paid expense with no payment record to
        -- make looks identical to every row written before migration 238.
        v_paid := NULL;
    END IF;

    INSERT INTO expense (expensedate, category, description, amount, paymentmethod,
                         supplier, supplierid, amountpaid, duedate, flockid,
                         userid, farmid, attachmentimage, attachmentcontenttype,
                         createddate)
    VALUES (p_expensedate, p_category, p_description, p_amount, p_paymentmethod,
            p_supplier, p_supplierid, v_paid, p_duedate, p_flockid,
            p_userid, p_farmid, p_attachmentimage, p_attachmentcontenttype,
            (now() at time zone 'utc'))
    RETURNING expenseid INTO v_id;

    IF v_pays THEN
        -- The supplier row carries the farmid in the TEXT form the payment
        -- tables use. expense.farmid is a uuid, and rendering it would risk a
        -- payment that does not group with the farm's others.
        SELECT s.farmid::text INTO v_farmtext
        FROM   supplier s WHERE s.supplierid = p_supplierid LIMIT 1;

        PERFORM sppoultrysupplierpayment_record(
            v_farmtext,
            p_supplierid,
            v_entrypaid,
            jsonb_build_array(jsonb_build_object(
                'documenttype', 'Expense', 'documentid', v_id, 'amount', v_entrypaid)),
            p_paymentmethod,
            p_expensedate,          -- dated the bill, which is when the money moved
            p_cashaccountid,
            NULL,
            'Paid when the bill was entered',
            'ExpenseEntry',
            p_userid);
    END IF;

    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Update.
-- -----------------------------------------------------------------------------
-- Raising amount paid on an existing bill is a payment and is recorded as one.
-- Lowering it is refused by the guard 238 already wrote -- reverse the payment
-- instead, so the correction is visible rather than silent.
DROP FUNCTION IF EXISTS public.spexpense_update(integer, timestamp without time zone, text,
    text, numeric, text, text, integer, text, uuid, boolean, bytea, text, integer, numeric, date);

CREATE OR REPLACE FUNCTION public.spexpense_update(
    p_expenseid             integer,
    p_expensedate           timestamp without time zone,
    p_category              text,
    p_description           text,
    p_amount                numeric,
    p_paymentmethod         text,
    p_supplier              text,
    p_flockid               integer,
    p_userid                text,
    p_farmid                uuid,
    p_attachmentimageset    boolean DEFAULT false,
    p_attachmentimage       bytea   DEFAULT NULL,
    p_attachmentcontenttype text    DEFAULT NULL,
    p_supplierid            integer DEFAULT NULL,
    p_amountpaid            numeric DEFAULT NULL,
    p_duedate               date    DEFAULT NULL,
    p_cashaccountid         integer DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_alloc    numeric(14,2);
    v_paid     numeric(14,2) := p_amountpaid;
    v_current  numeric(14,2);
    v_target   numeric(14,2);
    v_delta    numeric(14,2);
    v_pays     boolean;
    v_acct     integer;
    v_farmtext text;
BEGIN
    IF COALESCE(p_amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than 0.';
    END IF;

    -- What supplier payments have already settled against this expense. Editing
    -- the row must never contradict money that has actually moved -- the balance
    -- on screen and fnbalanceaudit would disagree from that moment on.
    SELECT COALESCE(SUM(sa.amountapplied), 0) INTO v_alloc
    FROM   supplierpaymentallocation sa
    WHERE  lower(sa.farmid) = lower(p_farmid::text) AND sa.module = 'poultry'
      AND  sa.status = 'Posted' AND sa.documenttype = 'Expense'
      AND  sa.documentid = p_expenseid;

    -- What the bill says was paid before this edit, resolved.
    SELECT COALESCE(e.amountpaid, e.amount) INTO v_current
    FROM   expense e
    WHERE  e.expenseid = p_expenseid AND e.farmid = p_farmid;

    IF v_current IS NULL THEN
        RAISE EXCEPTION 'Expense not found for this company.';
    END IF;

    IF p_amount < v_alloc THEN
        RAISE EXCEPTION 'Supplier payments totalling % have been applied to this expense, so its total cannot be reduced to %.',
              v_alloc, p_amount::numeric(14,2);
    END IF;
    IF v_paid IS NOT NULL THEN
        IF v_paid < 0 THEN
            RAISE EXCEPTION 'Amount paid cannot be negative.';
        END IF;
        IF v_paid > p_amount THEN
            RAISE EXCEPTION 'Amount paid (%) cannot exceed the expense total (%).',
                  v_paid::numeric(14,2), p_amount::numeric(14,2);
        END IF;
        IF v_paid < v_alloc THEN
            RAISE EXCEPTION 'Supplier payments totalling % have been applied to this expense, so amount paid cannot be set to %. Reverse the payment on Supplier Payments first.',
                  v_alloc, v_paid;
        END IF;
    END IF;
    IF p_supplierid IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM supplier s
                       WHERE s.supplierid = p_supplierid
                         AND lower(s.farmid::text) = lower(p_farmid::text)) THEN
        RAISE EXCEPTION 'Supplier does not belong to this company.';
    END IF;

    v_target := COALESCE(v_paid, p_amount);
    v_delta  := v_target - v_current;
    -- On an edit the bill usually already carries the account its cash went to
    -- (sppoultryexpensecash_sync stamps it), so fall back to that before giving
    -- up. Same interlock as the insert: no account, no payment, no lost cash.
    v_acct   := COALESCE(p_cashaccountid,
                         (SELECT e.poultrycashaccountid FROM expense e
                           WHERE e.expenseid = p_expenseid AND e.farmid = p_farmid));
    v_pays   := fnpoultryexpenserecordspayment(p_supplierid, p_paymentmethod, v_delta)
                AND v_acct IS NOT NULL;

    IF v_pays THEN
        -- Hold the row at what was already paid; the payment below adds the
        -- difference. An explicit number, never the NULL sentinel, for the same
        -- reason as the insert.
        v_paid := v_current;
    ELSIF v_paid IS NOT NULL AND v_paid >= p_amount THEN
        v_paid := NULL;
    END IF;

    UPDATE expense e
    SET    expensedate   = p_expensedate,
           category      = p_category,
           description   = p_description,
           amount        = p_amount,
           paymentmethod = p_paymentmethod,
           supplier      = p_supplier,
           supplierid    = p_supplierid,
           amountpaid    = v_paid,
           duedate       = p_duedate,
           flockid       = p_flockid,
           attachmentimage = CASE WHEN p_attachmentimageset THEN p_attachmentimage
                                  ELSE e.attachmentimage END,
           attachmentcontenttype = CASE WHEN p_attachmentimageset THEN p_attachmentcontenttype
                                        ELSE e.attachmentcontenttype END
    WHERE  e.expenseid = p_expenseid AND e.farmid = p_farmid;

    -- After the UPDATE, never before: _record reads the row's amount and
    -- supplier to validate the allocation against.
    IF v_pays THEN
        SELECT s.farmid::text INTO v_farmtext
        FROM   supplier s WHERE s.supplierid = p_supplierid LIMIT 1;

        PERFORM sppoultrysupplierpayment_record(
            v_farmtext,
            p_supplierid,
            v_delta,
            jsonb_build_array(jsonb_build_object(
                'documenttype', 'Expense', 'documentid', p_expenseid, 'amount', v_delta)),
            p_paymentmethod,
            (now() at time zone 'utc'),   -- paid today, not on the bill's date
            v_acct,
            NULL,
            'Recorded when the bill was edited',
            'ExpenseEntry',
            p_userid);
    END IF;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 4. Verification.
-- -----------------------------------------------------------------------------
SELECT 'functions' AS check,
       CASE WHEN COUNT(*) = 3 THEN 'OK' ELSE 'ONLY ' || COUNT(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('fnpoultryexpenserecordspayment', 'spexpense_insert', 'spexpense_update');

-- Exactly ONE overload of each, or the old signature is still shadowing the new
-- one and the API will keep calling the version that records nothing.
SELECT 'overloads' AS check, p.proname, COUNT(*) AS n,
       CASE WHEN COUNT(*) = 1 THEN 'OK' ELSE 'DUPLICATE' END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname IN ('spexpense_insert', 'spexpense_update')
GROUP  BY p.proname;

-- The decision table, spelled out. Every row must say OK.
SELECT 'decision' AS check, supplierid, method, paid, expected,
       fnpoultryexpenserecordspayment(supplierid, method, paid) AS got,
       CASE WHEN fnpoultryexpenserecordspayment(supplierid, method, paid) = expected
            THEN 'OK' ELSE 'WRONG' END AS result
FROM (VALUES
    (7,    'Cash',    100.00, TRUE),    -- an ordinary supplier bill, paid
    (7,    'Cash',      0.00, FALSE),   -- nothing paid, nothing to record
    (NULL, 'Cash',    100.00, FALSE),   -- petty cash: nobody to owe
    (7,    'NonCash', 100.00, FALSE),   -- internal use: no money moved
    (7,    NULL,      100.00, TRUE)     -- method unset still moved money
) AS t(supplierid, method, paid, expected);

-- NO BACKFILL. Not one historical expense may have gained a payment record.
-- Expect NO ROWS.
SELECT sa.documentid, sa.amountapplied, sp.sourcetype, sp.paymentdate
FROM   supplierpaymentallocation sa
JOIN   poultrysupplierpayments sp ON sp.poultrysupplierpaymentid = sa.paymentid
WHERE  sa.module = 'poultry' AND sa.documenttype = 'Expense'
  AND  sp.sourcetype = 'ExpenseEntry'
  AND  sp.createdat < (now() at time zone 'utc') - interval '1 minute';

-- The invariant, per farm. Expect NO ROWS.
SELECT f.farmid, a.*
FROM   (SELECT DISTINCT farmid FROM poultrysupplierpayments) f
CROSS  JOIN LATERAL fnbalanceaudit(f.farmid, 'poultry') a;
