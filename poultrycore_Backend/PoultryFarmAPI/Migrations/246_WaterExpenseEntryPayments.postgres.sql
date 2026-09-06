-- =============================================================================
-- 246_WaterExpenseEntryPayments.postgres.sql
--
-- Purpose
-- -------
-- The water twin of 245: money paid on a bill at entry becomes a real supplier
-- payment, so it reaches the Supplier Payments ledger instead of only moving a
-- column on the bill.
--
-- Water is a SMALLER change than poultry, for one reason: 240 deliberately kept
-- payment state out of spwaterexpense_insert / _update and put it in a separate
-- spwaterexpense_setpayment, because those two write fifteen columns through a
-- body this repo does not contain. That decision pays off here -- there is
-- exactly one function to change, and the untouchable ones stay untouched.
--
-- Where water DIFFERS from 245, and why it matters
-- -----------------------------------------------
--
-- 1. A SYSTEM-GENERATED BILL MUST NEVER RECORD A PAYMENT. This is the same trap
--    240 section 2 describes, one step further on.
--    spwatersupplierpaymentcash_sync writes supplierid onto the aggregated
--    waterexpenses row it books for a payment. If that row could record a
--    payment of its own, paying a supplier would book a payment, whose expense
--    row would book another payment, and so on. So the test includes
--    `sourcetype IS NULL` -- a bill somebody typed in. Anything with a
--    sourcetype is the shadow of another document.
--
-- 2. "PAID" RESOLVES DIFFERENTLY. Water's untouched row is
--        COALESCE(amountpaid, CASE WHEN paymentmethod = 'Credit' THEN 0 ELSE amount END)
--    because a Credit bill has always been an unpaid one (047). The delta this
--    file records is measured against THAT, not against poultry's flat
--    COALESCE(amountpaid, amount) -- otherwise every Credit bill would look like
--    it had already been paid in full and no payment would ever be recorded.
--
-- 3. THE PAYMENT NEEDS A METHOD OF ITS OWN. A bill whose paymentmethod is
--    'Credit' is by definition not paid by credit when it IS paid, so the
--    caller passes how it was actually settled. Unset falls back to the bill's
--    own method, and a 'Credit' fallback is written as NULL rather than
--    recording a payment that claims to be unpaid.
--
-- EFFECT ON TODAY'S NUMBERS: none. No existing row is read or rewritten, there
-- is no backfill, and no historical bill gains a retrospective payment record.
-- Note this is separate from 240, which DID move water supplier balances -- this
-- file moves nothing.
--
-- Order: independent of 245. Either may be applied first.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Shared decision: does this bill record a payment?
-- -----------------------------------------------------------------------------
-- The water twin of fnpoultryexpenserecordspayment, with the sourcetype guard
-- that poultry does not need.
CREATE OR REPLACE FUNCTION public.fnwaterexpenserecordspayment(
    p_supplierid    integer,
    p_sourcetype    text,
    p_paymentmethod text,
    p_amountpaid    numeric)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT p_supplierid IS NOT NULL
       AND p_sourcetype IS NULL
       AND COALESCE(p_paymentmethod, '') <> 'NonCash'
       AND COALESCE(p_amountpaid, 0) > 0;
$function$;

COMMENT ON FUNCTION public.fnwaterexpenserecordspayment(integer, text, text, numeric) IS
    'Whether money paid on a water bill should be recorded as a supplier payment. '
    'False for a bill with no supplier, for a SYSTEM-GENERATED row (sourcetype is '
    'set -- above all the expense a supplier payment books for itself, which would '
    'otherwise record a payment of its own, forever), for NonCash, and for nothing paid.';

-- -----------------------------------------------------------------------------
-- 2. Setting payment state records the money.
-- -----------------------------------------------------------------------------
-- Gains a method and a cash account. The payment posts the CashOut now, and a
-- payment with no account posts none at all -- which, with the bill's own cash
-- line resolving to what allocations have not covered, would lose the money.
-- The account falls back to the bill's own, which is the account the Expenses
-- page already stamped on it.
DROP FUNCTION IF EXISTS public.spwaterexpense_setpayment(text, integer, numeric, date);

CREATE OR REPLACE FUNCTION public.spwaterexpense_setpayment(
    p_farmid         text,
    p_waterexpenseid integer,
    p_amountpaid     numeric DEFAULT NULL::numeric,
    p_duedate        date    DEFAULT NULL::date,
    p_paymentmethod  text    DEFAULT NULL::text,
    p_cashaccountid  integer DEFAULT NULL::integer)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_amount   numeric(14,2);
    v_alloc    numeric(14,2);
    v_paid     numeric(14,2) := p_amountpaid;
    v_current  numeric(14,2);
    v_target   numeric(14,2);
    v_delta    numeric(14,2);
    v_supplier integer;
    v_source   text;
    v_method   text;
    v_billacct integer;
    v_acct     integer;
    v_pays     boolean;
BEGIN
    SELECT e.amount,
           -- Water's resolved paid: a Credit bill has never been paid.
           COALESCE(e.amountpaid,
                    CASE WHEN COALESCE(e.paymentmethod, '') = 'Credit'
                         THEN 0 ELSE e.amount END),
           e.supplierid, e.sourcetype, e.paymentmethod, e.watercashaccountid
      INTO v_amount, v_current, v_supplier, v_source, v_method, v_billacct
    FROM   waterexpenses e
    WHERE  e.waterexpenseid = p_waterexpenseid AND e.farmid = p_farmid
    LIMIT  1;

    IF v_amount IS NULL THEN
        RAISE EXCEPTION 'Expense not found for this company.';
    END IF;

    -- What supplier payments have already settled. An edit must never contradict
    -- money that has actually moved, or the balance on screen and
    -- fnwaterbalanceaudit disagree from that moment on.
    SELECT COALESCE(SUM(sa.amountapplied), 0) INTO v_alloc
    FROM   supplierpaymentallocation sa
    WHERE  sa.farmid = p_farmid AND sa.module = 'water' AND sa.status = 'Posted'
      AND  sa.documenttype = 'Expense' AND sa.documentid = p_waterexpenseid;

    IF v_paid IS NOT NULL THEN
        IF v_paid < 0 THEN
            RAISE EXCEPTION 'Amount paid cannot be negative.';
        END IF;
        IF v_paid > v_amount THEN
            RAISE EXCEPTION 'Amount paid (%) cannot exceed the expense total (%).', v_paid, v_amount;
        END IF;
        IF v_paid < v_alloc THEN
            RAISE EXCEPTION 'Supplier payments totalling % have been applied to this expense, so amount paid cannot be set to %. Reverse the payment on Supplier Payments first.',
                  v_alloc, v_paid;
        END IF;
    END IF;

    -- An unset amountpaid means paid in full, which is what a non-Credit bill
    -- already resolves to. Measure the delta against what the bill said before.
    v_target := COALESCE(v_paid,
                         CASE WHEN COALESCE(p_paymentmethod, v_method, '') = 'Credit'
                              THEN 0 ELSE v_amount END);
    v_delta  := v_target - v_current;
    v_pays   := fnwaterexpenserecordspayment(v_supplier, v_source,
                                             COALESCE(p_paymentmethod, v_method), v_delta);

    UPDATE waterexpenses
    SET    amountpaid = CASE
                            -- Hold at what was already paid; the payment below
                            -- adds the difference. _record ADDS, so writing the
                            -- target here would land double.
                            WHEN v_pays THEN v_current
                            ELSE v_paid
                        END,
           duedate    = p_duedate,
           updatedat  = (now() at time zone 'utc')
    WHERE  waterexpenseid = p_waterexpenseid AND farmid = p_farmid;

    -- After the UPDATE, never before: _record reads the row to validate against.
    IF v_pays THEN
        v_acct := COALESCE(p_cashaccountid, v_billacct);

        PERFORM spwatersupplierpayment_record(
            p_farmid,
            v_supplier,
            v_delta,
            jsonb_build_array(jsonb_build_object(
                'documenttype', 'Expense', 'documentid', p_waterexpenseid, 'amount', v_delta)),
            -- 'Credit' means NOT paid, so it is never how a payment was made.
            NULLIF(COALESCE(p_paymentmethod, v_method, ''), 'Credit'),
            (now() at time zone 'utc'),
            v_acct,
            NULL,
            'Recorded when the bill was entered',
            'ExpenseEntry',
            NULL);
    END IF;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 3. Verification.
-- -----------------------------------------------------------------------------
SELECT 'functions' AS check,
       CASE WHEN COUNT(*) = 2 THEN 'OK' ELSE 'ONLY ' || COUNT(*) END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('fnwaterexpenserecordspayment', 'spwaterexpense_setpayment');

-- Exactly ONE overload, or the old 4-argument signature still shadows the new
-- one and the API keeps calling the version that records nothing.
SELECT 'overloads' AS check, COUNT(*) AS n,
       CASE WHEN COUNT(*) = 1 THEN 'OK' ELSE 'DUPLICATE' END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname = 'spwaterexpense_setpayment';

-- The decision table, spelled out. Every row must say OK.
-- The third row is the one that matters most: it is the trap in 240 section 2.
SELECT 'decision' AS check, supplierid, sourcetype, method, paid, expected,
       fnwaterexpenserecordspayment(supplierid, sourcetype, method, paid) AS got,
       CASE WHEN fnwaterexpenserecordspayment(supplierid, sourcetype, method, paid) = expected
            THEN 'OK' ELSE 'WRONG' END AS result
FROM (VALUES
    (7,    NULL,                  'Cash',    100.00, TRUE),   -- a typed-in bill, paid
    (7,    NULL,                  'Cash',      0.00, FALSE),  -- nothing paid
    (7,    'WaterSupplierPayment','Cash',    100.00, FALSE),  -- a payment's own shadow row
    (7,    'WaterInternalUsage',  'NonCash', 100.00, FALSE),  -- internal use
    (NULL, NULL,                  'Cash',    100.00, FALSE),  -- nobody to owe
    (7,    NULL,                  'NonCash', 100.00, FALSE)   -- no money moved
) AS t(supplierid, sourcetype, method, paid, expected);

-- NO BACKFILL. Not one historical bill may have gained a payment record.
-- Expect NO ROWS.
SELECT sa.documentid, sa.amountapplied, sp.sourcetype, sp.paymentdate
FROM   supplierpaymentallocation sa
JOIN   watersupplierpayments sp ON sp.watersupplierpaymentid = sa.paymentid
WHERE  sa.module = 'water' AND sa.documenttype = 'Expense'
  AND  sp.sourcetype = 'ExpenseEntry'
  AND  sp.createdat < (now() at time zone 'utc') - interval '1 minute';

-- A system-generated bill must never be behind an ExpenseEntry payment.
-- Expect NO ROWS.
SELECT e.waterexpenseid, e.sourcetype, sa.amountapplied
FROM   supplierpaymentallocation sa
JOIN   watersupplierpayments sp ON sp.watersupplierpaymentid = sa.paymentid
JOIN   waterexpenses e ON e.waterexpenseid = sa.documentid AND e.farmid = sa.farmid
WHERE  sa.module = 'water' AND sa.documenttype = 'Expense'
  AND  sp.sourcetype = 'ExpenseEntry'
  AND  e.sourcetype IS NOT NULL;

-- The invariant, per farm. Expect NO ROWS.
SELECT f.farmid, a.*
FROM   (SELECT DISTINCT farmid FROM watersupplierpayments) f
CROSS  JOIN LATERAL fnwaterbalanceaudit(f.farmid) a;
