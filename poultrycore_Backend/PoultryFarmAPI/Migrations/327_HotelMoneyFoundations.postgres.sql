-- =============================================================================
-- 327_HotelMoneyFoundations.postgres.sql
--
-- Purpose
-- -------
-- Make the Hotel money foundations sound, so Owner Money, Loans, Transfers,
-- Reconciliation, Balances, Internal Use, Deferred cost and Financial Activity
-- can later be built on one ledger the way Poultry's are built on its own.
-- HOTEL ONLY: no Poultry, Water, Generic or Restaurant object is touched.
--
-- What was wrong (read-only audit 2026-09-27, verified against dev data)
-- ----------------------------------------------------------------------
--   1. FOUR writers to hotelcashtransactions:
--        * HotelCashLedgerService.PostAsync, run as Task.Run fire-and-forget
--          with every error swallowed, for guest payments, expense approval and
--          restaurant orders. It had no row lock, so concurrent postings lost
--          updates: of 31 guest payments only 8 reached the ledger (payments 24,
--          25 and 26 were recorded in the same minute; 26 is missing). Expense
--          approval ignored the expense's own chosen account (expense 11 chose
--          Main Bank Account, the money left "Expenses Account").
--        * inline INSERTs in sphotelcustomerpayment_approve (319) and
--          sphotelsupplierpayment_approve (321);
--        * fnhotelcash_post (325), used only by staff loans and payroll.
--   2. hotelinvoices was never UPDATEd: amountpaid/balance/status frozen at
--      issue; hotelpayments.hotelinvoiceid never set. Generate created a second
--      invoice with the SAME number on every click (booking 16 has two), and
--      priced the invoice from stay charges only, ignoring the room.
--   3. Restaurant orders posted POS cash when PLACED, even when the food was
--      charged to the room (the page then added the folio charges in a second,
--      separate request). Cash Flow and the P&L only counted orders with status
--      'Delivered', a status the order screens never set, so walk-in F&B money
--      was in no report at all.
--   4. Night Audit posted a nightly "Room" stay charge for every checked-in
--      booking while the folio balance already included the booking total
--      (nightly rate x nights): booking 17 paid 1,650 for a 1,100 stay.
--   5. P&L: no depreciation; refundable deposits counted as revenue.
--      Cash Flow: no customer payments, supplier payments or asset purchases.
--
-- The rules after this migration
-- ------------------------------
--   * ONE posting path. Every Hotel cash movement is a call to fnhotelcash_post
--     (325: row lock on the account, balance moved in the same statement as the
--     ledger row), made inside the same transaction as the business row, via
--     fnhotelcash_postonce -- idempotent by (farmid, sourcetype, sourceid), now
--     also enforced by a unique index. Nothing is fire-and-forget; a failed
--     posting fails the whole request with the database's sentence.
--   * Corrections are new, opposite rows (fnhotelcash_reverse), dated the day
--     of the correction. Nothing posted is deleted or edited.
--   * An invoice follows the payments applied to it (Poultry's
--     sppoultrysale_recompute rule): amountpaid = SUM(posted payments),
--     balance = total - paid (never below 0), status Issued / PartiallyPaid /
--     Paid. A payment on a booking with exactly one open invoice is applied to
--     it; with two or more it is left unapplied rather than guessed.
--   * Room revenue has ONE source of truth: the booking total (rate x booked
--     nights). Night Audit charges a "Room" night only when the night is OUTSIDE
--     the booked dates (an overstay), which the booking total does not cover.
--   * Room-charged F&B becomes folio charges (hotelstaycharges, linked to the
--     order) in the same transaction as the order and moves no cash; paid
--     orders post POS cash; a cancelled order is reversed either way.
--
-- Historical rows (no destructive rewrites)
-- -----------------------------------------
--   * Existing ledger rows stay exactly as they are. The payments, expenses and
--     orders that DO have a ledger row get it linked (cashtransactionid), which
--     is exact: one row per (sourcetype, sourceid) and no duplicates exist.
--   * The 23 guest payments and 8 approved expenses the old service lost are NOT
--     back-posted: several account balances were already set by hand (Main Bank
--     Account 67,200 with no ledger rows), so re-posting would double-count
--     money the user has already reconciled. Reported, left alone.
--   * Guest payments on a booking with exactly one invoice are applied to that
--     invoice and every invoice is recomputed -- the invoice now tells the truth.
--   * The 10 Night Audit "Room" charges already posted are left in place; some
--     are overstay nights (legitimate), some fall inside the booked dates
--     (duplicates). Reported per booking, not guessed at.
--
-- Order: after 326. Idempotent: safe to run twice.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Schema (only new, nullable or defaulted columns -- no reader uses t.* or
--    ordinals on these tables; checked in pg_proc and the API)
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.hotelpayments
    ADD COLUMN IF NOT EXISTS status                    text NOT NULL DEFAULT 'Posted',
    ADD COLUMN IF NOT EXISTS hotelcashaccountid        int,
    ADD COLUMN IF NOT EXISTS cashtransactionid         int,
    ADD COLUMN IF NOT EXISTS voidreason                text,
    ADD COLUMN IF NOT EXISTS voidedby                  text,
    ADD COLUMN IF NOT EXISTS voidedat                  timestamptz,
    ADD COLUMN IF NOT EXISTS reversalcashtransactionid int;

ALTER TABLE public.hotelexpenses
    ADD COLUMN IF NOT EXISTS cashtransactionid         int,
    ADD COLUMN IF NOT EXISTS reversalcashtransactionid int,
    ADD COLUMN IF NOT EXISTS cancelledby               text,
    ADD COLUMN IF NOT EXISTS cancelledat               timestamptz;

ALTER TABLE public.hotelrestaurantorders
    ADD COLUMN IF NOT EXISTS settlement                text,   -- Paid | RoomCharge | NULL (before 327)
    ADD COLUMN IF NOT EXISTS paymentmethod             text,
    ADD COLUMN IF NOT EXISTS hotelcashaccountid        int,
    ADD COLUMN IF NOT EXISTS cashtransactionid         int,
    ADD COLUMN IF NOT EXISTS reversalcashtransactionid int,
    ADD COLUMN IF NOT EXISTS cancelledby               text,
    ADD COLUMN IF NOT EXISTS cancelledat               timestamptz;

ALTER TABLE public.hotelstaycharges
    ADD COLUMN IF NOT EXISTS sourcetype text,
    ADD COLUMN IF NOT EXISTS sourceid   int;

ALTER TABLE public.hoteldeposits
    ADD COLUMN IF NOT EXISTS hotelcashaccountid int,
    ADD COLUMN IF NOT EXISTS cashtransactionid  int;

ALTER TABLE public.hotelcustomerpayments
    ADD COLUMN IF NOT EXISTS cashtransactionid int;

ALTER TABLE public.hotelsupplierpayments
    ADD COLUMN IF NOT EXISTS cashtransactionid int;

-- One ledger row per business document (the rule fnhotelcash_postonce relies
-- on). Checked before writing this: the dev ledger has no duplicates.
CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelcashtxn_farm_source
    ON public.hotelcashtransactions(farmid, sourcetype, sourceid)
    WHERE sourceid IS NOT NULL;

CREATE INDEX IF NOT EXISTS ix_hotelpayments_farm_invoice
    ON public.hotelpayments(farmid, hotelinvoiceid);
CREATE INDEX IF NOT EXISTS ix_hotelstaycharges_farm_source
    ON public.hotelstaycharges(farmid, sourcetype, sourceid);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Posting helpers (everything below goes through fnhotelcash_post, 325)
-- ─────────────────────────────────────────────────────────────────────────────

-- Post once per (farmid, sourcetype, sourceid). A second call for the same
-- document returns the row already posted instead of moving money twice.
CREATE OR REPLACE FUNCTION public.fnhotelcash_postonce(
    p_farmid        text,
    p_accountid     int,
    p_txntype       text,
    p_amount        numeric,
    p_description   text,
    p_reference     text,
    p_sourcetype    text,
    p_sourceid      int,
    p_by            text,
    p_txndate       timestamptz DEFAULT NULL,
    p_allowinactive boolean     DEFAULT FALSE
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE v_id int;
BEGIN
    IF p_sourcetype IS NULL OR p_sourceid IS NULL THEN
        RAISE EXCEPTION 'A cash movement must name the document it belongs to.';
    END IF;

    SELECT t.hotelcashtxnid INTO v_id
    FROM   public.hotelcashtransactions t
    WHERE  t.farmid = p_farmid AND t.sourcetype = p_sourcetype AND t.sourceid = p_sourceid
    LIMIT  1;
    IF v_id IS NOT NULL THEN
        RETURN v_id;
    END IF;

    RETURN public.fnhotelcash_post(p_farmid, p_accountid, p_txntype, p_amount, p_description,
                                   p_reference, p_sourcetype, p_sourceid, p_by, p_txndate, p_allowinactive);
END;
$function$;

-- The opposite of one posted row, on the same account, dated now. Allowed on an
-- inactive account: money that went in or out of it has to be able to come back.
CREATE OR REPLACE FUNCTION public.fnhotelcash_reverse(
    p_farmid       text,
    p_txnid        int,
    p_reversaltype text,
    p_reason       text,
    p_by           text
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE v record;
BEGIN
    SELECT * INTO v FROM public.hotelcashtransactions t
    WHERE  t.hotelcashtxnid = p_txnid AND t.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'The cash movement to reverse was not found.';
    END IF;

    RETURN public.fnhotelcash_postonce(
        p_farmid, v.hotelcashaccountid,
        CASE WHEN v.txntype = 'Credit' THEN 'Debit' ELSE 'Credit' END,
        v.amount,
        'REVERSAL: ' || COALESCE(v.description, '') || COALESCE(' - ' || NULLIF(btrim(p_reason), ''), ''),
        v.reference, p_reversaltype, v.sourceid, p_by, now(), TRUE);
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Invoices follow their payments
-- ─────────────────────────────────────────────────────────────────────────────

-- Poultry's sppoultrysale_recompute rule, on a hotel invoice.
CREATE OR REPLACE FUNCTION public.sphotelinvoice_recompute(
    p_farmid    text,
    p_invoiceid int
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_total  numeric;
    v_status text;
    v_paid   numeric;
BEGIN
    SELECT i.totalamount, i.status INTO v_total, v_status
    FROM   public.hotelinvoices i
    WHERE  i.hotelinvoiceid = p_invoiceid AND i.farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;

    SELECT COALESCE(SUM(p.amount), 0) INTO v_paid
    FROM   public.hotelpayments p
    WHERE  p.farmid = p_farmid AND p.hotelinvoiceid = p_invoiceid
      AND  p.status = 'Posted';

    UPDATE public.hotelinvoices i SET
        amountpaid = ROUND(v_paid, 2),
        balance    = GREATEST(ROUND(COALESCE(v_total, 0) - v_paid, 2), 0),
        status     = CASE
                         WHEN v_status = 'Void'                          THEN 'Void'
                         WHEN v_paid > 0 AND v_paid >= COALESCE(v_total, 0) THEN 'Paid'
                         WHEN v_paid > 0                                  THEN 'PartiallyPaid'
                         WHEN v_status = 'Draft'                          THEN 'Draft'
                         ELSE 'Issued'
                     END,
        updatedat  = now()
    WHERE  i.hotelinvoiceid = p_invoiceid AND i.farmid = p_farmid;
END;
$function$;

-- The one open invoice of a booking, or NULL when there is none or more than one.
CREATE OR REPLACE FUNCTION public.fnhotelbooking_openinvoice(
    p_farmid    text,
    p_bookingid int
) RETURNS int
LANGUAGE sql STABLE
AS $function$
    SELECT CASE WHEN COUNT(*) = 1 THEN MIN(i.hotelinvoiceid) END
    FROM   public.hotelinvoices i
    WHERE  i.farmid = p_farmid AND i.hotelbookingid = p_bookingid
      AND  COALESCE(i.status, 'Issued') <> 'Void';
$function$;

-- What the guest owes for the stay: the booking total (rate x booked nights)
-- plus everything charged to the folio. The single definition of the bill.
CREATE OR REPLACE FUNCTION public.fnhotelbooking_billtotal(
    p_farmid    text,
    p_bookingid int
) RETURNS numeric
LANGUAGE sql STABLE
AS $function$
    SELECT COALESCE((SELECT b.totalamount FROM public.hotelbookings b
                     WHERE b.hotelbookingid = p_bookingid AND b.farmid = p_farmid), 0)
         + COALESCE((SELECT SUM(sc.totalamount) FROM public.hotelstaycharges sc
                     WHERE sc.hotelbookingid = p_bookingid AND sc.farmid = p_farmid), 0);
$function$;

-- Generate (or refresh) the invoice for a booking. Priced from the whole bill,
-- not the stay charges alone. A booking that already has an open invoice gets
-- that invoice refreshed instead of a second one with the same number.
CREATE OR REPLACE FUNCTION public.sphotelinvoice_generate(
    p_farmid    text,
    p_bookingid int,
    p_by        text DEFAULT NULL
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE
    v_guest int;
    v_sub   numeric;
    v_id    int;
BEGIN
    SELECT b.hotelguestid INTO v_guest
    FROM   public.hotelbookings b
    WHERE  b.hotelbookingid = p_bookingid AND b.farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Booking not found.'; END IF;

    v_sub := ROUND(public.fnhotelbooking_billtotal(p_farmid, p_bookingid), 2);

    SELECT i.hotelinvoiceid INTO v_id
    FROM   public.hotelinvoices i
    WHERE  i.farmid = p_farmid AND i.hotelbookingid = p_bookingid
      AND  COALESCE(i.status, 'Issued') <> 'Void'
    ORDER  BY i.createdat DESC, i.hotelinvoiceid DESC
    LIMIT  1;

    IF v_id IS NULL THEN
        INSERT INTO public.hotelinvoices(farmid, hotelbookingid, hotelguestid, invoicenumber,
                                         subtotal, totalamount, amountpaid, balance, status)
        VALUES (p_farmid, p_bookingid, v_guest,
                'INV-' || to_char(now() AT TIME ZONE 'UTC', 'YYYYMMDD') || '-' || lpad(p_bookingid::text, 3, '0'),
                v_sub, v_sub, 0, v_sub, 'Issued')
        RETURNING hotelinvoiceid INTO v_id;
    ELSE
        UPDATE public.hotelinvoices i SET
            subtotal    = v_sub,
            totalamount = v_sub + COALESCE(i.taxamount, 0) - COALESCE(i.discountamount, 0),
            status      = CASE WHEN i.status = 'Draft' THEN 'Issued' ELSE i.status END,
            updatedat   = now()
        WHERE  i.hotelinvoiceid = v_id;
    END IF;

    -- The booking's unapplied payments settle this invoice when it is the only
    -- open one. With two open invoices, nobody can say which was paid.
    IF public.fnhotelbooking_openinvoice(p_farmid, p_bookingid) = v_id THEN
        UPDATE public.hotelpayments p SET hotelinvoiceid = v_id
        WHERE  p.farmid = p_farmid AND p.hotelbookingid = p_bookingid
          AND  p.hotelinvoiceid IS NULL AND p.status = 'Posted';
    END IF;

    PERFORM public.sphotelinvoice_recompute(p_farmid, v_id);
    RETURN v_id;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Guest payments
-- ─────────────────────────────────────────────────────────────────────────────

-- Record a guest payment: the payment row, its ledger row and the invoice it
-- settles, in one transaction. The money goes to the account chosen, else to
-- the Front Desk account exactly as before.
CREATE OR REPLACE FUNCTION public.sphotelpayment_record(
    p_farmid        text,
    p_bookingid     int,
    p_amount        numeric,
    p_paymentmethod text,
    p_reference     text        DEFAULT NULL,
    p_notes         text        DEFAULT NULL,
    p_invoiceid     int         DEFAULT NULL,
    p_cashaccountid int         DEFAULT NULL,
    p_by            text        DEFAULT NULL,
    p_paymentdate   timestamptz DEFAULT NULL
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE
    v_inv  int;
    v_acct int;
    v_id   int;
    v_txn  int;
    v_date timestamptz := COALESCE(p_paymentdate, now());
    v_ref  text;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than zero.';
    END IF;
    IF NULLIF(btrim(COALESCE(p_paymentmethod, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Payment method is required.';
    END IF;
    IF v_date > now() + interval '1 day' THEN
        RAISE EXCEPTION 'A payment cannot be dated in the future.';
    END IF;
    PERFORM 1 FROM public.hotelbookings b
    WHERE  b.hotelbookingid = p_bookingid AND b.farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Booking not found.'; END IF;

    IF p_invoiceid IS NOT NULL THEN
        SELECT i.hotelinvoiceid INTO v_inv FROM public.hotelinvoices i
        WHERE  i.hotelinvoiceid = p_invoiceid AND i.farmid = p_farmid
          AND  i.hotelbookingid = p_bookingid AND COALESCE(i.status, 'Issued') <> 'Void';
        IF v_inv IS NULL THEN
            RAISE EXCEPTION 'That invoice does not belong to this booking.';
        END IF;
    ELSE
        v_inv := public.fnhotelbooking_openinvoice(p_farmid, p_bookingid);
    END IF;

    v_acct := COALESCE(p_cashaccountid,
                       public.fnhotelcash_purposeaccount(p_farmid, 'FrontDesk', 'Front Desk Cash'));
    v_ref  := COALESCE(NULLIF(btrim(p_reference), ''),
                       'PAY-' || to_char(now() AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS') || '-' || p_bookingid::text);

    INSERT INTO public.hotelpayments(farmid, hotelbookingid, hotelinvoiceid, amount, paymentmethod,
                                     reference, notes, receivedby, paymentdate, status, hotelcashaccountid)
    VALUES (p_farmid, p_bookingid, v_inv, p_amount, p_paymentmethod,
            v_ref, p_notes, p_by, v_date, 'Posted', v_acct)
    RETURNING hotelpaymentid INTO v_id;

    v_txn := public.fnhotelcash_postonce(
        p_farmid, v_acct, 'Credit', p_amount,
        'Guest payment (' || p_paymentmethod || ') - ' || v_ref, v_ref,
        'Payment', v_id, p_by, v_date);

    UPDATE public.hotelpayments SET cashtransactionid = v_txn WHERE hotelpaymentid = v_id;

    IF v_inv IS NOT NULL THEN
        PERFORM public.sphotelinvoice_recompute(p_farmid, v_inv);
    END IF;
    RETURN v_id;
END;
$function$;

-- Void a guest payment: the payment stays, marked Void with its reason; the
-- money goes back out of the account it came into; the invoice is recomputed.
CREATE OR REPLACE FUNCTION public.sphotelpayment_void(
    p_farmid    text,
    p_paymentid int,
    p_reason    text,
    p_by        text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v   record;
    v_r int;
BEGIN
    IF NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'A reason is required to void a payment.';
    END IF;
    SELECT * INTO v FROM public.hotelpayments p
    WHERE  p.hotelpaymentid = p_paymentid AND p.farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found.'; END IF;
    IF v.status = 'Void' THEN RAISE EXCEPTION 'This payment is already void.'; END IF;

    IF v.cashtransactionid IS NOT NULL THEN
        v_r := public.fnhotelcash_reverse(p_farmid, v.cashtransactionid, 'PaymentReversal', p_reason, p_by);
    END IF;

    UPDATE public.hotelpayments SET
        status = 'Void', voidreason = p_reason, voidedby = p_by, voidedat = now(),
        reversalcashtransactionid = v_r
    WHERE  hotelpaymentid = p_paymentid;

    IF v.hotelinvoiceid IS NOT NULL THEN
        PERFORM public.sphotelinvoice_recompute(p_farmid, v.hotelinvoiceid);
    END IF;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Expenses
-- ─────────────────────────────────────────────────────────────────────────────

-- Approve: the money leaves the account the expense chose. Only an expense with
-- no account (created before accounts were required) falls back to the
-- Expenses account, as the old service did. A Credit expense is a bill owed to
-- the supplier: approving it moves no cash (the supplier payment will).
CREATE OR REPLACE FUNCTION public.sphotelexpense_approve(
    p_farmid    text,
    p_expenseid int,
    p_by        text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v      record;
    v_acct int;
    v_txn  int;
BEGIN
    SELECT * INTO v FROM public.hotelexpenses e
    WHERE  e.hotelexpenseid = p_expenseid AND e.farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND OR v.status NOT IN ('Draft', 'Submitted') THEN
        RAISE EXCEPTION 'Expense not found or already approved/cancelled.';
    END IF;
    IF COALESCE(v.amount, 0) <= 0 THEN
        RAISE EXCEPTION 'Expense amount must be greater than zero.';
    END IF;

    IF COALESCE(v.paymentmethod, 'Cash') <> 'Credit' THEN
        v_acct := COALESCE(v.hotelcashaccountid,
                           public.fnhotelcash_purposeaccount(p_farmid, 'Expenses', 'Expenses Account'));
        v_txn := public.fnhotelcash_postonce(
            p_farmid, v_acct, 'Debit', v.amount,
            COALESCE(v.category, 'Expense') || ': ' || COALESCE(v.description, ''), v.receiptref,
            'Expense', p_expenseid, p_by, v.expensedate::timestamptz);
    END IF;

    UPDATE public.hotelexpenses SET
        status = 'Approved', approvedby = p_by, approvedat = now(), updatedat = now(),
        hotelcashaccountid = COALESCE(v_acct, hotelcashaccountid),
        cashtransactionid  = v_txn
    WHERE  hotelexpenseid = p_expenseid;
END;
$function$;

-- Cancel: an approved expense's money comes back to its account (a reversal
-- row dated today); a Draft/Submitted one simply stops.
CREATE OR REPLACE FUNCTION public.sphotelexpense_cancel(
    p_farmid    text,
    p_expenseid int,
    p_reason    text DEFAULT NULL,
    p_by        text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v   record;
    v_r int;
BEGIN
    SELECT * INTO v FROM public.hotelexpenses e
    WHERE  e.hotelexpenseid = p_expenseid AND e.farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND OR v.status = 'Cancelled' THEN
        RAISE EXCEPTION 'Expense not found or already cancelled.';
    END IF;

    IF v.cashtransactionid IS NOT NULL THEN
        v_r := public.fnhotelcash_reverse(p_farmid, v.cashtransactionid, 'ExpenseReversal',
                                          COALESCE(p_reason, 'Expense cancelled'), p_by);
    END IF;

    UPDATE public.hotelexpenses SET
        status = 'Cancelled', cancelreason = p_reason, cancelledby = p_by, cancelledat = now(),
        reversalcashtransactionid = v_r, updatedat = now()
    WHERE  hotelexpenseid = p_expenseid;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Restaurant orders
-- ─────────────────────────────────────────────────────────────────────────────

-- Place an order. p_items: [{"menuItemId":1,"quantity":2,"unitPrice":45,"notes":null}]
--   * charged to the room: each line becomes a folio charge on the booking,
--     linked to the order; no cash moves (the guest pays at checkout);
--   * otherwise the guest paid at the till: POS cash is posted now.
CREATE OR REPLACE FUNCTION public.sphotelrestaurantorder_create(
    p_farmid        text,
    p_tablenumber   text,
    p_servername    text,
    p_bookingid     int,
    p_roomid        int,
    p_items         jsonb,
    p_chargetoroom  boolean DEFAULT FALSE,
    p_paymentmethod text    DEFAULT NULL,
    p_cashaccountid int     DEFAULT NULL,
    p_by            text    DEFAULT NULL
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_id     int;
    v_sub    numeric := 0;
    v_acct   int;
    v_txn    int;
    v_item   jsonb;
    v_name   text;
    v_qty    int;
    v_price  numeric;
BEGIN
    IF p_bookingid IS NOT NULL THEN
        SELECT b.status INTO v_status FROM public.hotelbookings b
        WHERE  b.hotelbookingid = p_bookingid AND b.farmid = p_farmid;
        IF NOT FOUND THEN RAISE EXCEPTION 'Booking not found.'; END IF;
    END IF;
    IF COALESCE(p_chargetoroom, FALSE) THEN
        IF p_bookingid IS NULL THEN
            RAISE EXCEPTION 'Choose the guest''s booking to charge the order to the room.';
        END IF;
        IF v_status IN ('CheckedOut', 'Cancelled', 'NoShow') THEN
            RAISE EXCEPTION 'This booking is % -- the order cannot be charged to the room.', v_status;
        END IF;
    END IF;

    INSERT INTO public.hotelrestaurantorders(farmid, tablenumber, servername, hotelbookingid, hotelroomid,
                                             status, subtotal, totalamount, settlement, paymentmethod)
    VALUES (p_farmid, p_tablenumber, p_servername, p_bookingid, p_roomid, 'Placed', 0, 0,
            CASE WHEN COALESCE(p_chargetoroom, FALSE) THEN 'RoomCharge' ELSE 'Paid' END,
            CASE WHEN COALESCE(p_chargetoroom, FALSE) THEN 'Room' ELSE COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash') END)
    RETURNING hotelrestaurantorderid INTO v_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items, '[]'::jsonb))
    LOOP
        v_qty   := COALESCE((v_item->>'quantity')::int, 1);
        v_price := COALESCE((v_item->>'unitPrice')::numeric, 0);
        IF v_qty <= 0 THEN RAISE EXCEPTION 'Quantity must be at least 1.'; END IF;
        IF v_price < 0 THEN RAISE EXCEPTION 'Price cannot be negative.'; END IF;

        SELECT m.name INTO v_name FROM public.hotelmenuitems m
        WHERE  m.hotelmenuitemid = (v_item->>'menuItemId')::int AND m.farmid = p_farmid;
        IF v_name IS NULL THEN RAISE EXCEPTION 'Menu item % was not found.', v_item->>'menuItemId'; END IF;

        INSERT INTO public.hotelrestaurantorderitems(farmid, hotelrestaurantorderid, hotelmenuitemid, itemname,
                                                     quantity, unitprice, linetotal, notes)
        VALUES (p_farmid, v_id, (v_item->>'menuItemId')::int, v_name, v_qty, v_price, v_qty * v_price,
                v_item->>'notes');

        IF COALESCE(p_chargetoroom, FALSE) THEN
            INSERT INTO public.hotelstaycharges(farmid, hotelbookingid, chargetype, description, quantity,
                                                unitprice, totalamount, postedby, sourcetype, sourceid)
            VALUES (p_farmid, p_bookingid, 'Restaurant',
                    v_name || CASE WHEN v_qty > 1 THEN ' x' || v_qty::text ELSE '' END,
                    v_qty, v_price, v_qty * v_price, p_by, 'RestaurantOrder', v_id);
        END IF;

        v_sub := v_sub + v_qty * v_price;
        v_name := NULL;
    END LOOP;

    UPDATE public.hotelrestaurantorders SET subtotal = v_sub, totalamount = v_sub
    WHERE  hotelrestaurantorderid = v_id;

    IF NOT COALESCE(p_chargetoroom, FALSE) AND v_sub > 0 THEN
        v_acct := COALESCE(p_cashaccountid, public.fnhotelcash_purposeaccount(p_farmid, 'POS', 'POS / Restaurant'));
        v_txn := public.fnhotelcash_postonce(
            p_farmid, v_acct, 'Credit', v_sub,
            'Restaurant order #' || v_id::text || COALESCE(' (Table ' || NULLIF(btrim(p_tablenumber), '') || ')', ''),
            'ORD-' || v_id::text, 'Order', v_id, p_by, now());
        UPDATE public.hotelrestaurantorders SET hotelcashaccountid = v_acct, cashtransactionid = v_txn
        WHERE  hotelrestaurantorderid = v_id;
    END IF;

    RETURN v_id;
END;
$function$;

-- Move an order along. Cancelling undoes its money: a paid order's POS cash is
-- reversed, a room-charged order's folio charges are offset by opposite lines.
-- A cancelled order stays cancelled.
CREATE OR REPLACE FUNCTION public.sphotelrestaurantorder_setstatus(
    p_farmid  text,
    p_orderid int,
    p_status  text,
    p_by      text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v   record;
    v_r int;
BEGIN
    IF p_status NOT IN ('Placed', 'Preparing', 'Ready', 'Served', 'Delivered', 'Cancelled') THEN
        RAISE EXCEPTION 'Unknown order status %.', p_status;
    END IF;
    SELECT * INTO v FROM public.hotelrestaurantorders o
    WHERE  o.hotelrestaurantorderid = p_orderid AND o.farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
    IF v.status = 'Cancelled' THEN
        IF p_status = 'Cancelled' THEN RETURN; END IF;
        RAISE EXCEPTION 'This order was cancelled and cannot be reopened.';
    END IF;

    IF p_status = 'Cancelled' THEN
        IF v.cashtransactionid IS NOT NULL THEN
            v_r := public.fnhotelcash_reverse(p_farmid, v.cashtransactionid, 'OrderReversal', 'Order cancelled', p_by);
        END IF;
        INSERT INTO public.hotelstaycharges(farmid, hotelbookingid, chargetype, description, quantity,
                                            unitprice, totalamount, postedby, sourcetype, sourceid)
        SELECT sc.farmid, sc.hotelbookingid, sc.chargetype, 'Cancelled: ' || sc.description, sc.quantity,
               -sc.unitprice, -sc.totalamount, p_by, 'RestaurantOrderCancel', p_orderid
        FROM   public.hotelstaycharges sc
        WHERE  sc.farmid = p_farmid AND sc.sourcetype = 'RestaurantOrder' AND sc.sourceid = p_orderid
          AND  NOT EXISTS (SELECT 1 FROM public.hotelstaycharges x
                           WHERE x.farmid = p_farmid AND x.sourcetype = 'RestaurantOrderCancel'
                             AND x.sourceid = p_orderid);
        UPDATE public.hotelrestaurantorders SET
            status = 'Cancelled', cancelledby = p_by, cancelledat = now(),
            reversalcashtransactionid = v_r, updatedat = now()
        WHERE  hotelrestaurantorderid = p_orderid;
    ELSE
        UPDATE public.hotelrestaurantorders SET
            status = p_status, updatedat = now(),
            deliveredtime = CASE WHEN p_status IN ('Served', 'Delivered') THEN now() ELSE deliveredtime END
        WHERE  hotelrestaurantorderid = p_orderid;
    END IF;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Deposits (money in the Front Desk drawer, held for the guest)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sphoteldeposit_record(
    p_farmid        text,
    p_bookingid     int,
    p_guestid       int,
    p_deposittype   text,
    p_amount        numeric,
    p_method        text DEFAULT NULL,
    p_reference     text DEFAULT NULL,
    p_notes         text DEFAULT NULL,
    p_by            text DEFAULT NULL,
    p_cashaccountid int  DEFAULT NULL
) RETURNS int
LANGUAGE plpgsql
AS $function$
DECLARE
    v_held numeric;
    v_acct int;
    v_id   int;
    v_txn  int;
BEGIN
    IF p_deposittype NOT IN ('Collected', 'Refunded') THEN
        RAISE EXCEPTION 'A deposit is either Collected or Refunded.';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Deposit amount must be greater than zero.';
    END IF;
    PERFORM 1 FROM public.hotelbookings b
    WHERE  b.hotelbookingid = p_bookingid AND b.farmid = p_farmid AND b.hotelguestid = p_guestid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Booking not found for this guest.'; END IF;

    IF p_deposittype = 'Refunded' THEN
        SELECT COALESCE(SUM(CASE WHEN d.deposittype = 'Collected' THEN d.amount ELSE -d.amount END), 0)
        INTO   v_held
        FROM   public.hoteldeposits d
        WHERE  d.farmid = p_farmid AND d.hotelbookingid = p_bookingid;
        IF p_amount > v_held THEN
            RAISE EXCEPTION 'A refund cannot be more than the deposit held for this booking (%).', v_held;
        END IF;
    END IF;

    v_acct := COALESCE(p_cashaccountid, public.fnhotelcash_purposeaccount(p_farmid, 'FrontDesk', 'Front Desk Cash'));

    INSERT INTO public.hoteldeposits(farmid, hotelbookingid, hotelguestid, deposittype, amount, method,
                                     reference, notes, processedby, hotelcashaccountid)
    VALUES (p_farmid, p_bookingid, p_guestid, p_deposittype, p_amount, p_method,
            p_reference, p_notes, p_by, v_acct)
    RETURNING hoteldepositid INTO v_id;

    v_txn := public.fnhotelcash_postonce(
        p_farmid, v_acct,
        CASE WHEN p_deposittype = 'Collected' THEN 'Credit' ELSE 'Debit' END,
        p_amount,
        'Deposit ' || lower(p_deposittype) || ' - booking #' || p_bookingid::text,
        p_reference,
        CASE WHEN p_deposittype = 'Collected' THEN 'DepositCollected' ELSE 'DepositRefunded' END,
        v_id, p_by, now());

    UPDATE public.hoteldeposits SET cashtransactionid = v_txn WHERE hoteldepositid = v_id;
    RETURN v_id;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Customer and supplier payments: same bodies as 319/321, but the cash now
--    goes through the one posting path, dated when the money moved, and a
--    payment with no account lands in the Front Desk / Expenses account instead
--    of silently moving no cash at all.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sphotelcustomerpayment_approve(
    p_paymentid  int,
    p_farmid     text,
    p_approvedby text DEFAULT NULL
) RETURNS void AS $$
DECLARE
    v_rec     record;
    v_custbal numeric;
    v_acct    int;
    v_txn     int;
BEGIN
    SELECT * INTO v_rec FROM public.hotelcustomerpayments
    WHERE hotelcustomerpaymentid = p_paymentid AND farmid = p_farmid
    FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
    IF v_rec.status = 'Approved' THEN RETURN; END IF;  -- idempotent
    IF v_rec.status <> 'Draft' THEN RAISE EXCEPTION 'Only Draft payments can be approved'; END IF;

    SELECT currentbalance INTO v_custbal FROM public.hotelcustomers
    WHERE hotelcustomerid = v_rec.hotelcustomerid AND farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;

    v_custbal := v_custbal - v_rec.amount;

    INSERT INTO public.hotelcustomerledger(
        farmid, hotelcustomerid, transactiondate, transactiontype,
        paymentid, debitamount, creditamount, balanceaftertransaction,
        description, createdby
    ) VALUES (
        p_farmid, v_rec.hotelcustomerid, v_rec.paymentdate, 'PaymentDebit',
        p_paymentid, v_rec.amount, 0, v_custbal,
        COALESCE(v_rec.notes, 'Customer payment'), p_approvedby
    );

    UPDATE public.hotelcustomers SET currentbalance = v_custbal, updatedat = now()
    WHERE hotelcustomerid = v_rec.hotelcustomerid AND farmid = p_farmid;

    v_acct := COALESCE(v_rec.hotelcashaccountid,
                       public.fnhotelcash_purposeaccount(p_farmid, 'FrontDesk', 'Front Desk Cash'));
    v_txn := public.fnhotelcash_postonce(
        p_farmid, v_acct, 'Credit', v_rec.amount,
        COALESCE(v_rec.notes, 'Customer payment'), v_rec.reference,
        'CustomerPayment', p_paymentid, p_approvedby, v_rec.paymentdate);

    UPDATE public.hotelcustomerpayments SET
        status = 'Approved', approvedby = p_approvedby, approvedat = now(), updatedat = now(),
        hotelcashaccountid = v_acct, cashtransactionid = v_txn
    WHERE hotelcustomerpaymentid = p_paymentid AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.sphotelsupplierpayment_approve(
    p_paymentid  int,
    p_farmid     text,
    p_approvedby text DEFAULT NULL
) RETURNS void AS $$
DECLARE
    v_rec     record;
    v_suppbal numeric;
    v_acct    int;
    v_txn     int;
BEGIN
    SELECT * INTO v_rec FROM public.hotelsupplierpayments
    WHERE hotelsupplierpaymentid = p_paymentid AND farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
    IF v_rec.status = 'Approved' THEN RETURN; END IF;
    IF v_rec.status <> 'Draft' THEN RAISE EXCEPTION 'Only Draft payments can be approved'; END IF;

    SELECT currentbalance INTO v_suppbal FROM public.hotelsuppliers
    WHERE hotelsupplierid = v_rec.hotelsupplierid AND farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Supplier not found'; END IF;
    v_suppbal := v_suppbal - v_rec.amount;

    INSERT INTO public.hotelsupplierledger(farmid, hotelsupplierid, transactiondate, transactiontype, paymentid,
                                           debitamount, creditamount, balanceaftertransaction, description, createdby)
    VALUES (p_farmid, v_rec.hotelsupplierid, v_rec.paymentdate, 'PaymentDebit', p_paymentid,
            v_rec.amount, 0, v_suppbal, COALESCE(v_rec.notes, 'Supplier payment'), p_approvedby);

    UPDATE public.hotelsuppliers SET currentbalance = v_suppbal, updatedat = now()
    WHERE hotelsupplierid = v_rec.hotelsupplierid AND farmid = p_farmid;

    v_acct := COALESCE(v_rec.hotelcashaccountid,
                       public.fnhotelcash_purposeaccount(p_farmid, 'Expenses', 'Expenses Account'));
    v_txn := public.fnhotelcash_postonce(
        p_farmid, v_acct, 'Debit', v_rec.amount,
        COALESCE(v_rec.notes, 'Supplier payment'), v_rec.reference,
        'SupplierPayment', p_paymentid, p_approvedby, v_rec.paymentdate);

    UPDATE public.hotelsupplierpayments SET
        status = 'Approved', approvedby = p_approvedby, approvedat = now(), updatedat = now(),
        hotelcashaccountid = v_acct, cashtransactionid = v_txn
    WHERE hotelsupplierpaymentid = p_paymentid AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Link the history that is exactly linkable (no money moves here)
-- ─────────────────────────────────────────────────────────────────────────────
UPDATE public.hotelpayments p SET
    cashtransactionid  = t.hotelcashtxnid,
    hotelcashaccountid = COALESCE(p.hotelcashaccountid, t.hotelcashaccountid)
FROM   public.hotelcashtransactions t
WHERE  t.farmid = p.farmid AND t.sourcetype = 'Payment' AND t.sourceid = p.hotelpaymentid
  AND  p.cashtransactionid IS NULL;

UPDATE public.hotelexpenses e SET cashtransactionid = t.hotelcashtxnid
FROM   public.hotelcashtransactions t
WHERE  t.farmid = e.farmid AND t.sourcetype = 'Expense' AND t.sourceid = e.hotelexpenseid
  AND  e.cashtransactionid IS NULL;

UPDATE public.hotelrestaurantorders o SET
    cashtransactionid  = t.hotelcashtxnid,
    hotelcashaccountid = t.hotelcashaccountid,
    settlement         = COALESCE(o.settlement, 'Paid')
FROM   public.hotelcashtransactions t
WHERE  t.farmid = o.farmid AND t.sourcetype = 'Order' AND t.sourceid = o.hotelrestaurantorderid
  AND  o.cashtransactionid IS NULL;

UPDATE public.hotelcustomerpayments p SET cashtransactionid = t.hotelcashtxnid
FROM   public.hotelcashtransactions t
WHERE  t.farmid = p.farmid AND t.sourcetype = 'CustomerPayment' AND t.sourceid = p.hotelcustomerpaymentid
  AND  p.cashtransactionid IS NULL;

UPDATE public.hotelsupplierpayments p SET cashtransactionid = t.hotelcashtxnid
FROM   public.hotelcashtransactions t
WHERE  t.farmid = p.farmid AND t.sourcetype = 'SupplierPayment' AND t.sourceid = p.hotelsupplierpaymentid
  AND  p.cashtransactionid IS NULL;

-- A payment on a booking that has exactly one open invoice settles that invoice.
UPDATE public.hotelpayments p SET hotelinvoiceid = public.fnhotelbooking_openinvoice(p.farmid, p.hotelbookingid)
WHERE  p.hotelinvoiceid IS NULL AND p.status = 'Posted'
  AND  public.fnhotelbooking_openinvoice(p.farmid, p.hotelbookingid) IS NOT NULL;

-- Every invoice is recomputed from the payments applied to it.
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT i.farmid, i.hotelinvoiceid FROM public.hotelinvoices i LOOP
        PERFORM public.sphotelinvoice_recompute(r.farmid, r.hotelinvoiceid);
    END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. Cash Flow. Arms 1-7 are 325's; changes are marked. New arms 8-10.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.sphotelcashflow_rows(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    rowsource       text,
    offledger       boolean,
    sourcerowid     integer,
    cashaccountid   integer,
    accountname     text,
    transactiondate timestamp,
    transactiontype text,
    sourcetype      text,
    sourceid        integer,
    istransfer      boolean,
    amount          numeric,
    description     text,
    flowgroup       text,        -- OperatingIn | OperatingOut | EmployeeLoanIn | EmployeeLoanOut
    createdat       timestamp)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_from timestamp := COALESCE(p_fromdate, '-infinity'::timestamp);
    v_to   timestamp := COALESCE(p_todate,   'infinity'::timestamp);
BEGIN
    -- ---- 1. guest payments (the main revenue) --------------------------------
    -- Every payment on the day it was received, including one voided later:
    -- the void is its own row (1b) on the day it happened, as in the ledger.
    RETURN QUERY
    SELECT 'GuestPayment'::text,
           FALSE,
           hp.hotelpaymentid,
           hp.hotelcashaccountid,
           NULL::text,
           hp.paymentdate::timestamp,
           'CashIn'::text,
           'GuestPayment'::text,
           hp.hotelpaymentid,
           FALSE,
           COALESCE(hp.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(hp.notes), ''),
               NULLIF(btrim(hp.reference), ''),
               'Guest payment #' || hp.hotelpaymentid::text
           )::text,
           'OperatingIn'::text,
           hp.createdat::timestamp
    FROM   hotelpayments hp
    WHERE  lower(hp.farmid::text) = lower(p_farmid)
      AND  COALESCE(hp.amount, 0) > 0
      AND  hp.paymentdate::timestamp >= v_from
      AND  hp.paymentdate::timestamp <= v_to;

    -- ---- 1b. guest payment voided (327) --------------------------------------
    RETURN QUERY
    SELECT 'GuestPaymentVoid'::text,
           FALSE,
           hp.hotelpaymentid,
           hp.hotelcashaccountid,
           NULL::text,
           hp.voidedat::timestamp,
           'CashOut'::text,
           'GuestPaymentVoid'::text,
           hp.hotelpaymentid,
           FALSE,
           -COALESCE(hp.amount, 0)::numeric,
           ('Void of guest payment #' || hp.hotelpaymentid::text
            || COALESCE(' - ' || NULLIF(btrim(hp.voidreason), ''), ''))::text,
           'OperatingOut'::text,
           hp.voidedat::timestamp
    FROM   hotelpayments hp
    WHERE  lower(hp.farmid::text) = lower(p_farmid)
      AND  hp.status = 'Void'
      AND  hp.voidedat IS NOT NULL
      AND  COALESCE(hp.amount, 0) > 0
      AND  hp.voidedat::timestamp >= v_from
      AND  hp.voidedat::timestamp <= v_to;

    -- ---- 2. restaurant / F&B orders paid at the till (changed in 327) --------
    -- 316-325 required status 'Delivered', which the order screens never set,
    -- so this arm was always empty. The money arrives when the order is paid
    -- (placed and settled at the till: it has a POS ledger row). Orders charged
    -- to a room move no cash here -- they are on the folio and arrive through
    -- the guest's payment (arm 1).
    RETURN QUERY
    SELECT 'RestaurantOrder'::text,
           FALSE,
           ro.hotelrestaurantorderid,
           ro.hotelcashaccountid,
           NULL::text,
           ro.ordertime::timestamp,
           'CashIn'::text,
           'RestaurantOrder'::text,
           ro.hotelrestaurantorderid,
           FALSE,
           COALESCE(ro.totalamount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(ro.notes), ''),
               'Restaurant order #' || ro.hotelrestaurantorderid::text
               || COALESCE(' - Table ' || NULLIF(btrim(ro.tablenumber), ''), '')
           )::text,
           'OperatingIn'::text,
           ro.createdat::timestamp
    FROM   hotelrestaurantorders ro
    WHERE  lower(ro.farmid::text) = lower(p_farmid)
      AND  ro.cashtransactionid IS NOT NULL
      AND  COALESCE(ro.totalamount, 0) > 0
      AND  ro.ordertime::timestamp >= v_from
      AND  ro.ordertime::timestamp <= v_to;

    -- ---- 2b. paid order cancelled: the money went back (327) ----------------
    RETURN QUERY
    SELECT 'RestaurantOrderReversal'::text,
           FALSE,
           ro.hotelrestaurantorderid,
           ro.hotelcashaccountid,
           NULL::text,
           ro.cancelledat::timestamp,
           'CashOut'::text,
           'RestaurantOrderReversal'::text,
           ro.hotelrestaurantorderid,
           FALSE,
           -COALESCE(ro.totalamount, 0)::numeric,
           ('Cancelled restaurant order #' || ro.hotelrestaurantorderid::text)::text,
           'OperatingOut'::text,
           ro.cancelledat::timestamp
    FROM   hotelrestaurantorders ro
    WHERE  lower(ro.farmid::text) = lower(p_farmid)
      AND  ro.reversalcashtransactionid IS NOT NULL
      AND  COALESCE(ro.totalamount, 0) > 0
      AND  ro.cancelledat::timestamp >= v_from
      AND  ro.cancelledat::timestamp <= v_to;

    -- ---- 3. deposits collected (unchanged) -----------------------------------
    IF to_regclass('public.hoteldeposits') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'DepositIn'::text,
               FALSE,
               hd.hoteldepositid,
               hd.hotelcashaccountid,
               NULL::text,
               hd.createdat::timestamp,
               'CashIn'::text,
               'DepositCollected'::text,
               hd.hoteldepositid,
               FALSE,
               COALESCE(hd.amount, 0)::numeric,
               COALESCE(
                   NULLIF(btrim(hd.notes), ''),
                   'Deposit collected #' || hd.hoteldepositid::text
               )::text,
               'OperatingIn'::text,
               hd.createdat::timestamp
        FROM   hoteldeposits hd
        WHERE  lower(hd.farmid::text) = lower(p_farmid)
          AND  hd.deposittype = 'Collected'
          AND  COALESCE(hd.amount, 0) > 0
          AND  hd.createdat::timestamp >= v_from
          AND  hd.createdat::timestamp <= v_to;

        -- ---- 4. deposits refunded (unchanged) --------------------------------
        RETURN QUERY
        SELECT 'DepositOut'::text,
               FALSE,
               hd.hoteldepositid,
               hd.hotelcashaccountid,
               NULL::text,
               hd.createdat::timestamp,
               'CashOut'::text,
               'DepositRefunded'::text,
               hd.hoteldepositid,
               FALSE,
               -COALESCE(hd.amount, 0)::numeric,
               COALESCE(
                   NULLIF(btrim(hd.notes), ''),
                   'Deposit refunded #' || hd.hoteldepositid::text
               )::text,
               'OperatingOut'::text,
               hd.createdat::timestamp
        FROM   hoteldeposits hd
        WHERE  lower(hd.farmid::text) = lower(p_farmid)
          AND  hd.deposittype = 'Refunded'
          AND  COALESCE(hd.amount, 0) > 0
          AND  hd.createdat::timestamp >= v_from
          AND  hd.createdat::timestamp <= v_to;
    END IF;

    -- ---- 5. expenses (changed in 327) ----------------------------------------
    -- Approved/Paid as before. Two corrections: a Credit expense is a bill,
    -- not cash (its cash is the supplier payment, arm 9), and an approved
    -- expense cancelled later still spent the money on its day -- the refund is
    -- its own row (5b), as in the ledger.
    RETURN QUERY
    SELECT 'Expense'::text,
           FALSE,
           he.hotelexpenseid,
           he.hotelcashaccountid,
           NULL::text,
           he.expensedate::timestamp,
           'CashOut'::text,
           'Expense'::text,
           he.hotelexpenseid,
           FALSE,
           -COALESCE(he.amount, 0)::numeric,
           COALESCE(
               NULLIF(btrim(he.description), ''),
               COALESCE(he.category, 'Expense')
           )::text,
           'OperatingOut'::text,
           he.createdat::timestamp
    FROM   hotelexpenses he
    WHERE  lower(he.farmid::text) = lower(p_farmid)
      AND  COALESCE(he.amount, 0) > 0
      AND  COALESCE(he.paymentmethod, 'Cash') <> 'Credit'
      AND  (he.status IN ('Approved', 'Paid') OR he.cashtransactionid IS NOT NULL)
      AND  he.expensedate >= v_from
      AND  he.expensedate <= v_to;

    -- ---- 5b. approved expense cancelled: money back (327) --------------------
    RETURN QUERY
    SELECT 'ExpenseReversal'::text,
           FALSE,
           he.hotelexpenseid,
           he.hotelcashaccountid,
           NULL::text,
           he.cancelledat::timestamp,
           'CashIn'::text,
           'ExpenseReversal'::text,
           he.hotelexpenseid,
           FALSE,
           COALESCE(he.amount, 0)::numeric,
           ('Cancelled: ' || COALESCE(NULLIF(btrim(he.description), ''), COALESCE(he.category, 'Expense')))::text,
           'OperatingIn'::text,
           he.cancelledat::timestamp
    FROM   hotelexpenses he
    WHERE  lower(he.farmid::text) = lower(p_farmid)
      AND  he.reversalcashtransactionid IS NOT NULL
      AND  COALESCE(he.amount, 0) > 0
      AND  he.cancelledat::timestamp >= v_from
      AND  he.cancelledat::timestamp <= v_to;

    -- ---- 6. payroll (unchanged) ----------------------------------------------
    RETURN QUERY
    SELECT 'Payroll'::text,
           FALSE,
           pr.hotelpayrollrunid,
           pr.hotelcashaccountid,
           NULL::text,
           COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::timestamp,
           'CashOut'::text,
           'Payroll'::text,
           pr.hotelpayrollrunid,
           FALSE,
           -COALESCE(pr.totalnetpay, 0)::numeric,
           COALESCE(
               NULLIF(btrim(pr.notes), ''),
               'Payroll ' || to_char(pr.periodstart, 'DD Mon') || ' - ' || to_char(pr.periodend, 'DD Mon YYYY')
           )::text,
           'OperatingOut'::text,
           pr.createdat::timestamp
    FROM   hotelpayrollruns pr
    WHERE  lower(pr.farmid::text) = lower(p_farmid)
      AND  pr.status = 'Paid'
      AND  COALESCE(pr.totalnetpay, 0) > 0
      AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::timestamp >= v_from
      AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::timestamp <= v_to;

    -- ---- 7. staff loans and advances (325, unchanged) ------------------------
    IF to_regclass('public.hotelemployeeloans') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'LoanDisbursed'::text,
               FALSE,
               l.hotelemployeeloanid,
               l.hotelcashaccountid,
               NULL::text,
               l.disbursementdate::timestamp,
               'CashOut'::text,
               'EmployeeLoanDisbursement'::text,
               l.hotelemployeeloanid,
               FALSE,
               -(l.principalamount::numeric),
               ('Staff ' || CASE WHEN l.loantype = 'SalaryAdvance' THEN 'advance' ELSE 'loan' END
                || ' ' || COALESCE(l.loannumber, '') || ' to ' || COALESCE(l.staffname, 'staff'))::text,
               'EmployeeLoanOut'::text,
               l.createdat::timestamp
        FROM   hotelemployeeloans l
        WHERE  lower(l.farmid::text) = lower(p_farmid)
          AND  l.cashtransactionid IS NOT NULL
          AND  l.disbursementdate::timestamp >= v_from
          AND  l.disbursementdate::timestamp <= v_to;

        RETURN QUERY
        SELECT 'LoanReversed'::text,
               FALSE,
               l.hotelemployeeloanid,
               l.hotelcashaccountid,
               NULL::text,
               l.reversedat::timestamp,
               'CashIn'::text,
               'EmployeeLoanReversal'::text,
               l.hotelemployeeloanid,
               FALSE,
               l.principalamount::numeric,
               ('Reversal of staff loan ' || COALESCE(l.loannumber, '') || ' to ' || COALESCE(l.staffname, 'staff'))::text,
               'EmployeeLoanIn'::text,
               l.reversedat::timestamp
        FROM   hotelemployeeloans l
        WHERE  lower(l.farmid::text) = lower(p_farmid)
          AND  l.reversalcashtransactionid IS NOT NULL
          AND  l.reversedat::timestamp >= v_from
          AND  l.reversedat::timestamp <= v_to;

        RETURN QUERY
        SELECT 'LoanRepaid'::text,
               FALSE,
               r.hotelemployeeloanrepaymentid,
               r.hotelcashaccountid,
               NULL::text,
               r.repaymentdate::timestamp,
               'CashIn'::text,
               'EmployeeLoanRepayment'::text,
               r.hotelemployeeloanid,
               FALSE,
               r.amount::numeric,
               ('Loan repayment ' || COALESCE(l.loannumber, '') || ' from ' || COALESCE(l.staffname, 'staff'))::text,
               'EmployeeLoanIn'::text,
               r.createdat::timestamp
        FROM   hotelemployeeloanrepayments r
        JOIN   hotelemployeeloans l ON l.hotelemployeeloanid = r.hotelemployeeloanid
        WHERE  lower(r.farmid::text) = lower(p_farmid)
          AND  r.cashtransactionid IS NOT NULL
          AND  r.repaymentdate::timestamp >= v_from
          AND  r.repaymentdate::timestamp <= v_to;

        RETURN QUERY
        SELECT 'LoanRepayReversed'::text,
               FALSE,
               r.hotelemployeeloanrepaymentid,
               r.hotelcashaccountid,
               NULL::text,
               r.reversedat::timestamp,
               'CashOut'::text,
               'EmployeeLoanRepaymentReversal'::text,
               r.hotelemployeeloanid,
               FALSE,
               -(r.amount::numeric),
               ('Reversal of loan repayment ' || COALESCE(l.loannumber, '') || ' from ' || COALESCE(l.staffname, 'staff'))::text,
               'EmployeeLoanOut'::text,
               r.reversedat::timestamp
        FROM   hotelemployeeloanrepayments r
        JOIN   hotelemployeeloans l ON l.hotelemployeeloanid = r.hotelemployeeloanid
        WHERE  lower(r.farmid::text) = lower(p_farmid)
          AND  r.reversalcashtransactionid IS NOT NULL
          AND  r.reversedat::timestamp >= v_from
          AND  r.reversedat::timestamp <= v_to;
    END IF;

    -- ---- 8. customer (corporate account) payments received (327) ------------
    -- Poultry arm 1: a receipt from a customer is Operating, on the day the
    -- money arrived.
    IF to_regclass('public.hotelcustomerpayments') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'CustomerPayment'::text,
               FALSE,
               cp.hotelcustomerpaymentid,
               cp.hotelcashaccountid,
               NULL::text,
               cp.paymentdate::timestamp,
               'CashIn'::text,
               'CustomerPayment'::text,
               cp.hotelcustomerpaymentid,
               FALSE,
               cp.amount::numeric,
               ('Customer payment' || COALESCE(' from ' || NULLIF(btrim(c.customername), ''), ''))::text,
               'OperatingIn'::text,
               cp.createdat::timestamp
        FROM   hotelcustomerpayments cp
        LEFT   JOIN hotelcustomers c ON c.hotelcustomerid = cp.hotelcustomerid
        WHERE  lower(cp.farmid::text) = lower(p_farmid)
          AND  cp.status = 'Approved'
          AND  cp.amount > 0
          AND  cp.paymentdate::timestamp >= v_from
          AND  cp.paymentdate::timestamp <= v_to;
    END IF;

    -- ---- 9. supplier payments made (327) -------------------------------------
    -- Poultry arm 3b: paying a supplier's bill is Operating, on the day paid.
    IF to_regclass('public.hotelsupplierpayments') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'SupplierPayment'::text,
               FALSE,
               sp.hotelsupplierpaymentid,
               sp.hotelcashaccountid,
               NULL::text,
               sp.paymentdate::timestamp,
               'CashOut'::text,
               'SupplierPayment'::text,
               sp.hotelsupplierpaymentid,
               FALSE,
               -(sp.amount::numeric),
               ('Supplier payment' || COALESCE(' to ' || NULLIF(btrim(s.suppliername), ''), ''))::text,
               'OperatingOut'::text,
               sp.createdat::timestamp
        FROM   hotelsupplierpayments sp
        LEFT   JOIN hotelsuppliers s ON s.hotelsupplierid = sp.hotelsupplierid
        WHERE  lower(sp.farmid::text) = lower(p_farmid)
          AND  sp.status = 'Approved'
          AND  sp.amount > 0
          AND  sp.paymentdate::timestamp >= v_from
          AND  sp.paymentdate::timestamp <= v_to;
    END IF;

    -- ---- 10. capital asset purchases (327) -----------------------------------
    -- Poultry books an asset purchase as an expense row (costtype CapitalAsset)
    -- and its Cash Flow reports it in Operating Out; Hotel does the same here
    -- from the asset's posted cost entries. Asset cost entries carry no cash
    -- account, so this arm is the one movement with no ledger row
    -- (cashaccountid NULL) -- see the 327 report.
    IF to_regclass('public.hotelcapitalassetcosts') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'CapitalAsset'::text,
               FALSE,
               cc.hotelcapitalassetcostid,
               NULL::integer,
               NULL::text,
               COALESCE(cc.costdate, a.acquisitiondate, cc.createdat::date)::timestamp,
               'CashOut'::text,
               'CapitalAsset'::text,
               a.hotelcapitalassetid,
               FALSE,
               -(cc.amount::numeric),
               (COALESCE(NULLIF(btrim(a.assetname), ''), 'Asset')
                || COALESCE(' ' || a.assetnumber, '')
                || COALESCE(' - ' || NULLIF(btrim(cc.description), ''), ''))::text,
               'OperatingOut'::text,
               cc.createdat::timestamp
        FROM   hotelcapitalassetcosts cc
        JOIN   hotelcapitalassets a ON a.hotelcapitalassetid = cc.hotelcapitalassetid
        WHERE  lower(cc.farmid::text) = lower(p_farmid)
          AND  cc.status = 'Posted'
          AND  a.status <> 'Reversed'
          AND  cc.amount > 0
          AND  COALESCE(cc.costdate, a.acquisitiondate, cc.createdat::date)::timestamp >= v_from
          AND  COALESCE(cc.costdate, a.acquisitiondate, cc.createdat::date)::timestamp <= v_to;
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sphotelcashflow_detail(
    p_farmid   text,
    p_fromdate timestamp DEFAULT NULL,
    p_todate   timestamp DEFAULT NULL)
RETURNS TABLE (
    rowsource       text,
    offledger       boolean,
    sourcerowid     integer,
    cashaccountid   integer,
    accountname     text,
    transactiondate timestamp,
    transactiontype text,
    sourcetype      text,
    sourceid        integer,
    istransfer      boolean,
    amount          numeric,
    description     text,
    flowgroup       text,
    category        text,
    createdat       timestamp)
LANGUAGE sql
STABLE
AS $function$
    SELECT r.rowsource, r.offledger, r.sourcerowid, r.cashaccountid,
           COALESCE(r.accountname, ca.accountname::text),
           r.transactiondate, r.transactiontype, r.sourcetype, r.sourceid,
           r.istransfer, r.amount, r.description, r.flowgroup,
           CASE
               WHEN r.rowsource IN ('Expense', 'ExpenseReversal')
                   THEN COALESCE(
                       NULLIF(btrim(
                           COALESCE(ec.name, he.category)
                       ), ''),
                       'Uncategorised'
                   )
               WHEN r.rowsource IN ('GuestPayment', 'GuestPaymentVoid')
                   THEN COALESCE(
                       'Room revenue (' || NULLIF(btrim(hp.paymentmethod), '') || ')',
                       'Room revenue'
                   )
               WHEN r.rowsource IN ('RestaurantOrder', 'RestaurantOrderReversal') THEN 'Restaurant / F&B'
               WHEN r.rowsource = 'DepositIn'       THEN 'Guest deposits'
               WHEN r.rowsource = 'DepositOut'      THEN 'Deposit refunds'
               WHEN r.rowsource = 'Payroll'         THEN 'Staff wages'
               WHEN r.rowsource IN ('LoanDisbursed', 'LoanReversed')  THEN 'Staff loans & advances'
               WHEN r.rowsource IN ('LoanRepaid', 'LoanRepayReversed') THEN 'Staff loan repayments'
               WHEN r.rowsource = 'CustomerPayment' THEN 'Customer payments'
               WHEN r.rowsource = 'SupplierPayment' THEN 'Supplier payments'
               WHEN r.rowsource = 'CapitalAsset'    THEN 'Capital Asset'
               ELSE 'Other'
           END::text,
           r.createdat
    FROM   public.sphotelcashflow_rows(p_farmid, p_fromdate, p_todate) r
    LEFT   JOIN hotelcashaccounts ca
           ON  ca.hotelcashaccountid = r.cashaccountid
    LEFT   JOIN hotelexpenses he
           ON  r.rowsource IN ('Expense', 'ExpenseReversal')
           AND he.hotelexpenseid = r.sourcerowid
           AND lower(he.farmid::text) = lower(p_farmid)
    LEFT   JOIN hotelexpensecategories ec
           ON  he.hotelexpensecategoryid = ec.hotelexpensecategoryid
    LEFT   JOIN hotelpayments hp
           ON  r.rowsource IN ('GuestPayment', 'GuestPaymentVoid')
           AND hp.hotelpaymentid = r.sourcerowid
           AND lower(hp.farmid::text) = lower(p_farmid);
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. Profit & Loss
-- ─────────────────────────────────────────────────────────────────────────────
-- From 325's lines, three changes:
--   * DepositsNet is no longer revenue. hoteldeposits are refundable security
--     money: the guest folio never offsets them against the bill and they are
--     either refunded or kept. Money that must be given back is a liability,
--     not income -- the P&L would otherwise show a profit that walks out of
--     the door at checkout. The summary still reports the net held, outside
--     every total.
--   * Depreciation from hotelassetdepreciation (322) is a non-cash expense in
--     its own band after Operating Expenses -- Poultry 272's "Depreciation &
--     Financing" (section OtherCost, line key Depreciation).
--   * Restaurant revenue is the paid orders (a POS ledger row that was not
--     reversed); 'Delivered' was never set, so the line was always zero.
--     Voided guest payments leave Room Revenue.
CREATE OR REPLACE FUNCTION public.sphotelreport_pllines(
    p_farmid    text,
    p_startdate date,
    p_enddate   date
) RETURNS TABLE(
    section         text,
    linekey         text,
    linelabel       text,
    amount          numeric,
    sortorder       integer,
    isinformational boolean,
    entrycount      integer
)
LANGUAGE sql STABLE
AS $function$
    WITH rev_payments AS (
        SELECT 'Revenue'::text   AS sec,
               'RoomRevenue'     AS k,
               'Room Revenue'    AS lbl,
               ROUND(COALESCE(SUM(hp.amount), 0), 2) AS amt,
               10                AS so,
               FALSE             AS info,
               COUNT(*)::integer AS n
        FROM   hotelpayments hp
        WHERE  lower(hp.farmid::text) = lower(p_farmid)
          AND  hp.status = 'Posted'
          AND  hp.paymentdate::date >= p_startdate
          AND  hp.paymentdate::date <= p_enddate
          AND  COALESCE(hp.amount, 0) > 0
    ),
    rev_restaurant AS (
        SELECT 'Revenue'::text       AS sec,
               'RestaurantRevenue'   AS k,
               'Restaurant / F&B'    AS lbl,
               ROUND(COALESCE(SUM(ro.totalamount), 0), 2) AS amt,
               20                    AS so,
               FALSE                 AS info,
               COUNT(*)::integer     AS n
        FROM   hotelrestaurantorders ro
        WHERE  lower(ro.farmid::text) = lower(p_farmid)
          AND  ro.cashtransactionid IS NOT NULL
          AND  ro.reversalcashtransactionid IS NULL
          AND  COALESCE(ro.totalamount, 0) > 0
          AND  ro.ordertime::date >= p_startdate
          AND  ro.ordertime::date <= p_enddate
    ),
    exp_payroll AS (
        SELECT 'OperatingExpense'::text AS sec,
               'StaffWages'             AS k,
               'Staff Wages'            AS lbl,
               ROUND(COALESCE(SUM(pr.totalgrosspay), 0), 2) AS amt,
               100                      AS so,
               FALSE                    AS info,
               COUNT(*)::integer        AS n
        FROM   hotelpayrollruns pr
        WHERE  lower(pr.farmid::text) = lower(p_farmid)
          AND  pr.status = 'Paid'
          AND  COALESCE(pr.totalgrosspay, 0) > 0
          AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::date >= p_startdate
          AND  COALESCE(pr.paidat, pr.paydate::timestamp, pr.createdat)::date <= p_enddate
    ),
    rev_loaninterest AS (
        SELECT 'Revenue'::text              AS sec,
               'StaffLoanInterest'          AS k,
               'Interest on staff loans'    AS lbl,
               ROUND(COALESCE(SUM(r.interestamount), 0), 2) AS amt,
               40                           AS so,
               FALSE                        AS info,
               COUNT(*)::integer            AS n
        FROM   hotelemployeeloanrepayments r
        WHERE  lower(r.farmid::text) = lower(p_farmid)
          AND  r.status = 'Posted'
          AND  r.interestamount > 0
          AND  r.repaymentdate::date >= p_startdate
          AND  r.repaymentdate::date <= p_enddate
    ),
    exp_by_cat AS (
        SELECT 'OperatingExpense'::text AS sec,
               COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised') AS k,
               COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised') AS lbl,
               ROUND(SUM(he.amount), 2) AS amt,
               200                       AS so,
               FALSE                     AS info,
               COUNT(*)::integer         AS n
        FROM   hotelexpenses he
        LEFT   JOIN hotelexpensecategories ec
               ON  he.hotelexpensecategoryid = ec.hotelexpensecategoryid
        WHERE  lower(he.farmid::text) = lower(p_farmid)
          AND  he.status IN ('Approved', 'Paid')
          AND  COALESCE(he.amount, 0) > 0
          AND  he.expensedate >= p_startdate
          AND  he.expensedate <= p_enddate
        GROUP BY COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised')
    ),
    -- Depreciation & Financing (327): posted monthly depreciation, non-cash.
    oth_depreciation AS (
        SELECT 'OtherCost'::text        AS sec,
               'Depreciation'           AS k,
               'Depreciation'           AS lbl,
               ROUND(COALESCE(SUM(d.amount), 0), 2) AS amt,
               300                      AS so,
               FALSE                    AS info,
               COUNT(*)::integer        AS n
        FROM   hotelassetdepreciation d
        WHERE  lower(d.farmid::text) = lower(p_farmid)
          AND  d.status = 'Posted'
          AND  d.periodstart >= p_startdate
          AND  d.periodstart <= p_enddate
    ),
    all_lines AS (
        SELECT * FROM rev_payments
        UNION ALL SELECT * FROM rev_restaurant
        UNION ALL SELECT * FROM rev_loaninterest
        UNION ALL SELECT * FROM exp_payroll
        UNION ALL SELECT * FROM exp_by_cat
        UNION ALL SELECT * FROM oth_depreciation
    )
    SELECT a.sec, a.k, a.lbl, a.amt, a.so, a.info, a.n
    FROM   all_lines a
    WHERE  a.amt <> 0
    ORDER  BY a.so, a.lbl;
$function$;

-- The summary gains depreciation / totalothercosts (result columns change, so
-- drop first -- 251's pattern, catches every overload).
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname = 'sphotelreport_plsummary'
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.oid::regprocedure;
    END LOOP;
END $$;

CREATE FUNCTION public.sphotelreport_plsummary(
    p_farmid    text,
    p_startdate date,
    p_enddate   date
) RETURNS TABLE(
    roomrevenue          numeric,
    restaurantrevenue    numeric,
    depositsnet          numeric,   -- informational since 327: held for guests, NOT revenue
    totalrevenue         numeric,
    staffwages           numeric,
    totalexpensecategory numeric,
    totalexpenses        numeric,   -- operating expenses
    netprofit            numeric,
    netmarginpercent     numeric,
    status               text,
    revenueentries       integer,
    expenseentries       integer,
    depreciation         numeric,   -- 327
    totalothercosts      numeric    -- 327: Depreciation & Financing band
)
LANGUAGE plpgsql STABLE
AS $function$
DECLARE
    v_room     numeric := 0;
    v_rest     numeric := 0;
    v_otherrev numeric := 0;
    v_wages    numeric := 0;
    v_expcat   numeric := 0;
    v_dep      numeric := 0;
    v_other    numeric := 0;
    v_depnet   numeric := 0;
    v_revn     integer := 0;
    v_expn     integer := 0;
    v_rev      numeric;
    v_exp      numeric;
    v_net      numeric;
    r          record;
BEGIN
    FOR r IN SELECT * FROM sphotelreport_pllines(p_farmid, p_startdate, p_enddate)
    LOOP
        CASE r.linekey
            WHEN 'RoomRevenue'       THEN v_room  := r.amount; v_revn := v_revn + r.entrycount;
            WHEN 'RestaurantRevenue' THEN v_rest  := r.amount; v_revn := v_revn + r.entrycount;
            WHEN 'StaffWages'        THEN v_wages := r.amount; v_expn := v_expn + r.entrycount;
            ELSE
                IF r.section = 'Revenue' THEN
                    v_otherrev := v_otherrev + r.amount;
                    v_revn     := v_revn + r.entrycount;
                ELSIF r.section = 'OperatingExpense' THEN
                    v_expcat := v_expcat + r.amount;
                    v_expn   := v_expn + r.entrycount;
                ELSIF r.section = 'OtherCost' THEN
                    v_other := v_other + r.amount;
                    IF r.linekey = 'Depreciation' THEN v_dep := v_dep + r.amount; END IF;
                    v_expn  := v_expn + r.entrycount;
                END IF;
        END CASE;
    END LOOP;

    SELECT COALESCE(SUM(CASE WHEN hd.deposittype = 'Collected' THEN hd.amount
                             WHEN hd.deposittype = 'Refunded'  THEN -hd.amount ELSE 0 END), 0)
    INTO   v_depnet
    FROM   hoteldeposits hd
    WHERE  lower(hd.farmid::text) = lower(p_farmid)
      AND  hd.createdat::date >= p_startdate
      AND  hd.createdat::date <= p_enddate;

    v_rev := ROUND(v_room + v_rest + v_otherrev, 2);
    v_exp := ROUND(v_wages + v_expcat, 2);
    v_net := ROUND(v_rev - v_exp - v_other, 2);

    RETURN QUERY SELECT
        v_room, v_rest, ROUND(v_depnet, 2), v_rev,
        v_wages, v_expcat, v_exp,
        v_net,
        CASE WHEN v_rev > 0 THEN ROUND(v_net / v_rev * 100, 1) ELSE NULL::numeric END,
        CASE WHEN v_net > 0 THEN 'Profit'
             WHEN v_net < 0 THEN 'Loss'
             ELSE 'Break-even' END::text,
        v_revn, v_expn,
        ROUND(v_dep, 2), ROUND(v_other, 2);
END;
$function$;

-- Expense drilldown: 317's rows, plus the depreciation entries when the
-- Depreciation line is opened (only then, so every other drilldown is as before).
CREATE OR REPLACE FUNCTION public.sphotelreport_plexpensedetail(
    p_farmid    text,
    p_startdate date,
    p_enddate   date,
    p_linekey   text DEFAULT NULL
) RETURNS TABLE(
    hotelexpenseid       integer,
    expensedate          date,
    category             text,
    description          text,
    amount               numeric,
    vendor               text,
    paymentmethod        text,
    status               text,
    pllinekey            text
)
LANGUAGE sql STABLE
AS $function$
    SELECT * FROM (
        SELECT he.hotelexpenseid,
               he.expensedate,
               COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised'),
               he.description::text,
               he.amount,
               he.vendor::text,
               he.paymentmethod::text,
               he.status::text,
               COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised')
        FROM   hotelexpenses he
        LEFT   JOIN hotelexpensecategories ec
               ON  he.hotelexpensecategoryid = ec.hotelexpensecategoryid
        WHERE  lower(he.farmid::text) = lower(p_farmid)
          AND  he.status IN ('Approved', 'Paid')
          AND  COALESCE(he.amount, 0) > 0
          AND  he.expensedate >= p_startdate
          AND  he.expensedate <= p_enddate
          AND  (p_linekey IS NULL
                OR COALESCE(NULLIF(btrim(COALESCE(ec.name, he.category)), ''), 'Uncategorised') = p_linekey)

        UNION ALL

        SELECT d.hotelassetdepreciationid,
               d.periodstart,
               'Depreciation'::text,
               (COALESCE(a.assetname, 'Asset') || COALESCE(' ' || a.assetnumber, '')
                || ' - ' || to_char(d.periodstart, 'Mon YYYY'))::text,
               d.amount,
               NULL::text,
               'NonCash'::text,
               d.status::text,
               'Depreciation'::text
        FROM   hotelassetdepreciation d
        JOIN   hotelcapitalassets a ON a.hotelcapitalassetid = d.hotelcapitalassetid
        WHERE  p_linekey = 'Depreciation'
          AND  lower(d.farmid::text) = lower(p_farmid)
          AND  d.status = 'Posted'
          AND  d.periodstart >= p_startdate
          AND  d.periodstart <= p_enddate
    ) x
    ORDER BY 2, 1;
$function$;

-- Revenue drilldown: same predicates as the lines above.
CREATE OR REPLACE FUNCTION public.sphotelreport_plrevenuedetail(
    p_farmid    text,
    p_startdate date,
    p_enddate   date,
    p_linekey   text DEFAULT NULL
) RETURNS TABLE(
    sourcetype   text,
    sourceid     integer,
    entrydate    date,
    description  text,
    amount       numeric,
    method       text,
    pllinekey    text
)
LANGUAGE sql STABLE
AS $function$
    SELECT 'GuestPayment'::text,
           hp.hotelpaymentid,
           hp.paymentdate::date,
           COALESCE(NULLIF(btrim(hp.notes), ''), NULLIF(btrim(hp.reference), ''),
                    'Guest payment #' || hp.hotelpaymentid::text)::text,
           hp.amount,
           hp.paymentmethod::text,
           'RoomRevenue'::text
    FROM   hotelpayments hp
    WHERE  lower(hp.farmid::text) = lower(p_farmid)
      AND  hp.status = 'Posted'
      AND  COALESCE(hp.amount, 0) > 0
      AND  hp.paymentdate::date >= p_startdate
      AND  hp.paymentdate::date <= p_enddate
      AND  (p_linekey IS NULL OR p_linekey = 'RoomRevenue')

    UNION ALL

    SELECT 'RestaurantOrder'::text,
           ro.hotelrestaurantorderid,
           ro.ordertime::date,
           COALESCE(NULLIF(btrim(ro.notes), ''),
                    'Order #' || ro.hotelrestaurantorderid::text
                    || COALESCE(' - Table ' || NULLIF(btrim(ro.tablenumber), ''), ''))::text,
           ro.totalamount,
           ro.paymentmethod::text,
           'RestaurantRevenue'::text
    FROM   hotelrestaurantorders ro
    WHERE  lower(ro.farmid::text) = lower(p_farmid)
      AND  ro.cashtransactionid IS NOT NULL
      AND  ro.reversalcashtransactionid IS NULL
      AND  COALESCE(ro.totalamount, 0) > 0
      AND  ro.ordertime::date >= p_startdate
      AND  ro.ordertime::date <= p_enddate
      AND  (p_linekey IS NULL OR p_linekey = 'RestaurantRevenue')

    UNION ALL

    SELECT 'StaffLoanInterest'::text,
           r.hotelemployeeloanrepaymentid,
           r.repaymentdate::date,
           'Interest on staff loan repayment'::text,
           r.interestamount,
           r.sourcetype::text,
           'StaffLoanInterest'::text
    FROM   hotelemployeeloanrepayments r
    WHERE  lower(r.farmid::text) = lower(p_farmid)
      AND  r.status = 'Posted'
      AND  r.interestamount > 0
      AND  r.repaymentdate::date >= p_startdate
      AND  r.repaymentdate::date <= p_enddate
      AND  (p_linekey IS NULL OR p_linekey = 'StaffLoanInterest')

    ORDER BY 3, 2;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. Verification (read-only)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE v_missing text;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
    FROM   unnest(ARRAY[
               'fnhotelcash_post', 'fnhotelcash_postonce', 'fnhotelcash_reverse',
               'sphotelinvoice_recompute', 'fnhotelbooking_openinvoice', 'fnhotelbooking_billtotal',
               'sphotelinvoice_generate', 'sphotelpayment_record', 'sphotelpayment_void',
               'sphotelexpense_approve', 'sphotelexpense_cancel',
               'sphotelrestaurantorder_create', 'sphotelrestaurantorder_setstatus',
               'sphoteldeposit_record', 'sphotelcustomerpayment_approve', 'sphotelsupplierpayment_approve',
               'sphotelcashflow_rows', 'sphotelcashflow_detail', 'sphotelcashflow_summary',
               'sphotelreport_pllines', 'sphotelreport_plsummary',
               'sphotelreport_plexpensedetail', 'sphotelreport_plrevenuedetail'
           ]) f
    WHERE  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                       WHERE n.nspname = 'public' AND p.proname = f);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '327 verification failed, missing: %', v_missing;
    END IF;

    -- The two approve functions no longer write the ledger themselves.
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('sphotelcustomerpayment_approve', 'sphotelsupplierpayment_approve')
               AND prosrc ILIKE '%INSERT INTO public.hotelcashtransactions%') THEN
        RAISE EXCEPTION '327 verification failed: an approve function still inserts into the ledger directly';
    END IF;

    -- Every invoice agrees with the payments applied to it.
    IF EXISTS (SELECT 1 FROM hotelinvoices i
               WHERE COALESCE(i.amountpaid, 0) <> COALESCE((SELECT SUM(p.amount) FROM hotelpayments p
                                                            WHERE p.hotelinvoiceid = i.hotelinvoiceid
                                                              AND p.farmid = i.farmid AND p.status = 'Posted'), 0)) THEN
        RAISE EXCEPTION '327 verification failed: an invoice disagrees with its payments';
    END IF;
END $$;
