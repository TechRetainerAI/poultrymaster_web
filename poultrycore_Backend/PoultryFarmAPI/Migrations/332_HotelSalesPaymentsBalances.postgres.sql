-- =============================================================================
-- 332_HotelSalesPaymentsBalances.postgres.sql
--
-- Purpose
-- -------
-- Hotel feature 3 of 5: the SALES column (Sales, Payments, Customer Balances)
-- and the supplier half of EXPENSES (Supplier Payments, Supplier Balances),
-- copied from Poultry (222 / 223 / 224 / 238 / 262 / 304) onto the Hotel's own
-- documents. HOTEL ONLY: no Poultry, Water, Generic or Restaurant object is
-- touched. The two shared allocation tables of 222 get rows with
-- module = 'hotel' (and 'hotelopening', below); every other module's readers
-- filter on their own module value, so nothing they read changes.
--
-- What a hotel sells, and what a customer owes on
-- -----------------------------------------------
--   * 'Stay'  -- a booking (not Cancelled / NoShow). Its bill is the one 327
--     definition, fnhotelbooking_billtotal: room nights (the booking total) plus
--     every folio charge (restaurant / room service charged to the room, extras,
--     overstay nights). Paid = the booking's posted guest payments. The PARTY
--     is the guest, or -- when the stay has been billed to a corporate account
--     (hotelbookingbillto, new) -- that customer. A stay is OWED on (Customer
--     Balances) once the guest is in house or has checked out.
--   * 'OpeningBalance' -- a corporate customer's opening balance (319's field).
--   * 'Order' -- a walk-in restaurant order paid at the till. Always settled;
--     listed on Sales, never owed.
--
-- Party ids on Customer Balances: a guest is its hotelguestid (> 0), a corporate
-- account is MINUS its hotelcustomerid (< 0). One integer space, no collision.
--
-- Money (all through fnhotelcash_postonce / fnhotelcash_reverse, 327):
--   * A customer payment is a GROUP (paymentgroupid, Poultry 223): one money row
--     per document it settles -- a hotelpayments row per stay ('Payment' ledger
--     row, exactly what the Billing page has always written) and a
--     hotelcustomerpayments row for an opening balance ('CustomerPayment').
--     Each row has its allocation in customerpaymentallocation ('hotel': saleid =
--     booking; 'hotelopening': saleid = customer). Allocations must add up to
--     the payment; overpayment is refused (no credit balance, as Poultry).
--   * Reversing a group voids its guest payments (327's void: reversal row dated
--     today, invoice recomputed) and reverses its corporate rows
--     ('CustomerPaymentReversal'), with a reason; allocations are marked
--     Reversed. Nothing is deleted.
--   * A supplier payment is ONE hotelsupplierpayments row (status Approved = the
--     money left), one 'SupplierPayment' ledger row, allocations in
--     supplierpaymentallocation across 'Expense' (an approved Credit expense
--     naming a supplier), 'AssetCost' (the unpaid part of a capital asset cost)
--     and 'OpeningBalance'. Reversal: 'SupplierPaymentReversal', dated today.
--   * The old Draft -> Approve workflows (Customer Payments / Supplier Payments
--     pages, 319 / 321) now allocate oldest-first through the same functions,
--     so no approved payment floats unallocated again.
--   * Capital asset costs gain Poultry's "Paid from" account and "Amount paid
--     now": only the paid part moves cash ('AssetPurchase'); the rest is owed to
--     the supplier. A cost with a supplier payment against it cannot be
--     reversed (Poultry 270 / 313).
--   * The 319 / 321 ledgers (hotelcustomerledger / hotelsupplierledger and each
--     party's currentbalance) now follow every one of these movements, so the
--     Customers and Suppliers pages agree with the balances pages;
--     sphotelcustomer_postinvoice and sphotelsupplier_postexpense finally have
--     callers.
--
-- Profit & Loss stays CASH-BASIS for room revenue (see the report): the P&L
-- functions are NOT re-emitted. Cash Flow rows/detail are re-emitted from 331
-- with arms 8-10 changed and 8b / 9b / 10b added (every other arm byte for byte).
-- Chain: 325 -> 327 -> 331 -> 332.
--
-- Columns added (nullable / defaulted) to hotelpayments, hotelcustomerpayments,
-- hotelsupplierpayments, hotelexpenses, hotelcapitalassetcosts. Checked first:
-- no function reads those tables with t.* into a RETURNS TABLE, and the C#
-- reads them by column name (ReadRow dictionaries).
--
-- Idempotent: safe to run twice.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. Drop the functions this file owns, by NAME (catches every overload).
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN (
            'fnhotelcustomer_ledger', 'fnhotelsupplier_ledger',
            'fnhotelsale_docs', 'fnhotelcustomer_moneyrows', 'fnhotelcustomer_partyname',
            'fnhotelpayment_post',
            'sphotelsale_list', 'sphotelsale_billto',
            'sphotelcustomerbalances', 'sphotelcustomerbalancesummary', 'sphotelcustomeropendocs',
            'sphotelcustomerpayment_record', 'sphotelcustomerpayment_reverse',
            'sphotelcustomerpayment_history', 'sphotelcustomerpayment_allocations',
            'sphotelcustomerstatement', 'sphotelbalanceaudit',
            'fnhotel_allocated', 'fnhotel_payables',
            'sphotelsupplierbalances', 'sphotelsupplierbalancesummary', 'sphotelsupplieropenpurchases',
            'fnhotelsupplierpayment_apply', 'sphotelsupplierpayment_record', 'sphotelsupplierpayment_reverse',
            'sphotelsupplierpayment_history', 'sphotelsupplierpayment_allocations', 'sphotelsupplierstatement',
            'fnhotelassetcost_settle', 'sphotelcapitalasset_createpaid', 'sphotelcapitalasset_addcostpaid')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Schema
-- ─────────────────────────────────────────────────────────────────────────────

-- A guest payment belongs to a payment GROUP (the payment the person made).
-- The volatile default gives every existing row its own group: each old
-- payment was one payment against one booking.
ALTER TABLE public.hotelpayments
    ADD COLUMN IF NOT EXISTS paymentgroupid  uuid NOT NULL DEFAULT gen_random_uuid(),
    ADD COLUMN IF NOT EXISTS sourcetype      text NOT NULL DEFAULT 'SaleEntry',
    ADD COLUMN IF NOT EXISTS hotelcustomerid int;          -- the corporate payer, when the stay is billed to an account

CREATE INDEX IF NOT EXISTS ix_hotelpayments_group ON public.hotelpayments (farmid, paymentgroupid);

ALTER TABLE public.hotelcustomerpayments
    ADD COLUMN IF NOT EXISTS paymentgroupid            uuid NOT NULL DEFAULT gen_random_uuid(),
    ADD COLUMN IF NOT EXISTS sourcetype                text,
    -- An old-style Draft approved through the allocation path: the money rows
    -- are the group it points at, not this row.
    ADD COLUMN IF NOT EXISTS appliedgroupid            uuid,
    ADD COLUMN IF NOT EXISTS reversedby                text,
    ADD COLUMN IF NOT EXISTS reversedat                timestamptz,
    ADD COLUMN IF NOT EXISTS reversalreason            text,
    ADD COLUMN IF NOT EXISTS reversalcashtransactionid int;

ALTER TABLE public.hotelsupplierpayments
    ADD COLUMN IF NOT EXISTS sourcetype                text,
    ADD COLUMN IF NOT EXISTS reversedby                text,
    ADD COLUMN IF NOT EXISTS reversedat                timestamptz,
    ADD COLUMN IF NOT EXISTS reversalreason            text,
    ADD COLUMN IF NOT EXISTS reversalcashtransactionid int;

-- An expense may name the supplier it is owed to (Poultry 238). A Credit
-- expense with a supplier is a bill on Supplier Balances.
ALTER TABLE public.hotelexpenses
    ADD COLUMN IF NOT EXISTS hotelsupplierid int,
    ADD COLUMN IF NOT EXISTS duedate         date;

-- Capital asset costs: Poultry's paid-from account and amount paid now.
-- amountpaid NULL = a cost recorded before 332 (no cash account, as 327 found).
ALTER TABLE public.hotelcapitalassetcosts
    ADD COLUMN IF NOT EXISTS hotelsupplierid           int,
    ADD COLUMN IF NOT EXISTS hotelcashaccountid        int,
    ADD COLUMN IF NOT EXISTS amountpaid                numeric(14,2),
    ADD COLUMN IF NOT EXISTS duedate                   date,
    ADD COLUMN IF NOT EXISTS cashtransactionid         int,
    ADD COLUMN IF NOT EXISTS reversalcashtransactionid int,
    ADD COLUMN IF NOT EXISTS reversalreason            text;

-- A stay billed to a corporate account ("on account"). A side table, so
-- hotelbookings (read in many places) gains no column.
CREATE TABLE IF NOT EXISTS public.hotelbookingbillto (
    hotelbookingid  int           PRIMARY KEY REFERENCES public.hotelbookings(hotelbookingid),
    farmid          text          NOT NULL,
    hotelcustomerid int           NOT NULL REFERENCES public.hotelcustomers(hotelcustomerid),
    hotelinvoiceid  int,
    amountbilled    numeric(14,2) NOT NULL,
    createdby       text,
    createdat       timestamptz   NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_hotelbookingbillto_customer ON public.hotelbookingbillto (farmid, hotelcustomerid);

-- Backfill: every existing guest payment becomes an allocation against its
-- booking (Poultry 222 section 4), before/after as a running total in payment
-- order. A void payment's allocation is Reversed. Re-runnable (unique key).
INSERT INTO customerpaymentallocation
    (farmid, module, paymentid, saleid, amountapplied, salebalancebefore, salebalanceafter,
     status, createdby, createdat, reversedby, reversedat, reversalreason)
SELECT o.farmid, 'hotel', o.hotelpaymentid, o.hotelbookingid, o.amount,
       (o.bill - o.priorpaid)::numeric(14,2), (o.bill - o.priorpaid - o.amount)::numeric(14,2),
       CASE WHEN o.status = 'Void' THEN 'Reversed' ELSE 'Posted' END,
       o.receivedby, o.paymentdate::timestamp,
       o.voidedby, o.voidedat::timestamp, o.voidreason
FROM (
    SELECT hp.*, public.fnhotelbooking_billtotal(hp.farmid, hp.hotelbookingid) AS bill,
           COALESCE(SUM(CASE WHEN hp.status = 'Void' THEN 0 ELSE hp.amount END) OVER (
               PARTITION BY hp.farmid, hp.hotelbookingid
               ORDER BY hp.paymentdate, hp.hotelpaymentid
               ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS priorpaid
    FROM   public.hotelpayments hp
) o
WHERE o.amount > 0
ON CONFLICT (module, paymentid, saleid) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. The 319 / 321 ledgers follow the money. delta > 0 = the party owes more
--    (319's convention: creditamount raises the balance).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.fnhotelcustomer_ledger(
    p_farmid text, p_customerid int, p_type text, p_delta numeric,
    p_invoiceid int, p_paymentid int, p_description text, p_by text,
    p_date timestamptz DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE v_bal numeric;
BEGIN
    IF p_customerid IS NULL OR COALESCE(p_delta, 0) = 0 THEN RETURN; END IF;
    SELECT c.currentbalance INTO v_bal FROM public.hotelcustomers c
    WHERE  c.hotelcustomerid = p_customerid AND c.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;
    v_bal := v_bal + p_delta;
    INSERT INTO public.hotelcustomerledger(farmid, hotelcustomerid, transactiondate, transactiontype, invoiceid, paymentid,
                                           debitamount, creditamount, balanceaftertransaction, description, createdby)
    VALUES (p_farmid, p_customerid, COALESCE(p_date, now()), p_type, p_invoiceid, p_paymentid,
            CASE WHEN p_delta < 0 THEN -p_delta ELSE 0 END, CASE WHEN p_delta > 0 THEN p_delta ELSE 0 END,
            v_bal, p_description, p_by);
    UPDATE public.hotelcustomers SET currentbalance = v_bal, updatedat = now()
    WHERE  hotelcustomerid = p_customerid AND farmid = p_farmid;
END $function$;

CREATE FUNCTION public.fnhotelsupplier_ledger(
    p_farmid text, p_supplierid int, p_type text, p_delta numeric,
    p_expenseid int, p_paymentid int, p_description text, p_by text,
    p_date timestamptz DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE v_bal numeric;
BEGIN
    IF p_supplierid IS NULL OR COALESCE(p_delta, 0) = 0 THEN RETURN; END IF;
    SELECT s.currentbalance INTO v_bal FROM public.hotelsuppliers s
    WHERE  s.hotelsupplierid = p_supplierid AND s.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Supplier not found'; END IF;
    v_bal := v_bal + p_delta;
    INSERT INTO public.hotelsupplierledger(farmid, hotelsupplierid, transactiondate, transactiontype, expenseid, paymentid,
                                           debitamount, creditamount, balanceaftertransaction, description, createdby)
    VALUES (p_farmid, p_supplierid, COALESCE(p_date, now()), p_type, p_expenseid, p_paymentid,
            CASE WHEN p_delta < 0 THEN -p_delta ELSE 0 END, CASE WHEN p_delta > 0 THEN p_delta ELSE 0 END,
            v_bal, p_description, p_by);
    UPDATE public.hotelsuppliers SET currentbalance = v_bal, updatedat = now()
    WHERE  hotelsupplierid = p_supplierid AND farmid = p_farmid;
END $function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Sales documents (the one definition every customer-side reader uses)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.fnhotelcustomer_partyname(p_farmid text, p_partyid int)
RETURNS text LANGUAGE sql STABLE AS $function$
    SELECT CASE WHEN p_partyid < 0 THEN
                (SELECT c.customername FROM public.hotelcustomers c
                  WHERE c.hotelcustomerid = -p_partyid AND c.farmid = p_farmid)
           ELSE (SELECT COALESCE(NULLIF(btrim(COALESCE(g.firstname, '') || ' ' || COALESCE(g.lastname, '')), ''), 'Guest #' || g.hotelguestid)
                   FROM public.hotelguests g WHERE g.hotelguestid = p_partyid AND g.farmid = p_farmid)
           END::text;
$function$;

CREATE FUNCTION public.fnhotelsale_docs(p_farmid text)
RETURNS TABLE(documenttype text, documentid int, partyid int, hotelguestid int, hotelcustomerid int,
              docdate date, duedate date, reference text, label text, partyname text,
              totalamount numeric, amountpaid numeric, balance numeric, bookingstatus text,
              isowing boolean, nights int, roomnumber text, paymentmethod text)
LANGUAGE sql STABLE AS $function$
    -- Stays: the booking's whole bill (327's fnhotelbooking_billtotal).
    SELECT 'Stay'::text, b.hotelbookingid,
           COALESCE(-bt.hotelcustomerid, b.hotelguestid), b.hotelguestid, bt.hotelcustomerid,
           b.checkindate,
           (b.checkoutdate + COALESCE(c.paymenttermdays, 0))::date,
           b.bookingref::text,
           ('Stay ' || b.bookingref || COALESCE(' - Room ' || r.roomnumber, '') || ' - '
             || GREATEST(b.checkoutdate - b.checkindate, 1)::text
             || CASE WHEN GREATEST(b.checkoutdate - b.checkindate, 1) = 1 THEN ' night' ELSE ' nights' END)::text,
           COALESCE(c.customername,
                    NULLIF(btrim(COALESCE(g.firstname, '') || ' ' || COALESCE(g.lastname, '')), ''),
                    'Guest #' || b.hotelguestid)::text,
           t.total, LEAST(p.paid, GREATEST(t.total, p.paid))::numeric(14,2),
           GREATEST(t.total - p.paid, 0)::numeric(14,2),
           b.status::text, b.status IN ('CheckedIn', 'CheckedOut'),
           GREATEST(b.checkoutdate - b.checkindate, 1), r.roomnumber::text,
           (SELECT hp.paymentmethod FROM public.hotelpayments hp
             WHERE hp.farmid = p_farmid AND hp.hotelbookingid = b.hotelbookingid AND hp.status <> 'Void'
             ORDER BY hp.paymentdate DESC, hp.hotelpaymentid DESC LIMIT 1)::text
    FROM   public.hotelbookings b
    JOIN   public.hotelguests g ON g.hotelguestid = b.hotelguestid
    LEFT   JOIN public.hotelrooms r ON r.hotelroomid = b.hotelroomid
    LEFT   JOIN public.hotelbookingbillto bt ON bt.hotelbookingid = b.hotelbookingid
    LEFT   JOIN public.hotelcustomers c ON c.hotelcustomerid = bt.hotelcustomerid
    CROSS  JOIN LATERAL (SELECT ROUND(public.fnhotelbooking_billtotal(p_farmid, b.hotelbookingid), 2)::numeric(14,2) AS total) t
    CROSS  JOIN LATERAL (SELECT COALESCE(SUM(hp.amount), 0)::numeric(14,2) AS paid FROM public.hotelpayments hp
                          WHERE hp.farmid = p_farmid AND hp.hotelbookingid = b.hotelbookingid AND hp.status <> 'Void') p
    WHERE  b.farmid = p_farmid AND b.status NOT IN ('Cancelled', 'NoShow')

    UNION ALL
    -- A corporate account's opening balance (319), settled by allocations.
    SELECT 'OpeningBalance'::text, c.hotelcustomerid, -c.hotelcustomerid, NULL::int, c.hotelcustomerid,
           c.createdat::date, (c.createdat::date + c.paymenttermdays)::date,
           ('OB-' || c.hotelcustomerid)::text, 'Opening balance'::text, c.customername::text,
           c.openingbalance::numeric(14,2), a.x, GREATEST(c.openingbalance - a.x, 0)::numeric(14,2),
           NULL::text, TRUE, NULL::int, NULL::text, NULL::text
    FROM   public.hotelcustomers c
    CROSS  JOIN LATERAL (SELECT COALESCE(SUM(ca.amountapplied), 0)::numeric(14,2) AS x
                           FROM customerpaymentallocation ca
                          WHERE ca.farmid = p_farmid AND ca.module = 'hotelopening'
                            AND ca.saleid = c.hotelcustomerid AND ca.status = 'Posted') a
    WHERE  c.farmid = p_farmid AND NOT c.isdeleted AND c.openingbalance > 0

    UNION ALL
    -- Walk-in restaurant orders paid at the till: sold and settled together.
    SELECT 'Order'::text, o.hotelrestaurantorderid, NULL::int, NULL::int, NULL::int,
           o.ordertime::date, o.ordertime::date,
           ('ORD-' || o.hotelrestaurantorderid)::text,
           ('Restaurant order #' || o.hotelrestaurantorderid
             || COALESCE(' - Table ' || NULLIF(btrim(o.tablenumber), ''), ''))::text,
           'Walk-in'::text,
           o.totalamount::numeric(14,2), o.totalamount::numeric(14,2), 0::numeric(14,2),
           o.status::text, FALSE, NULL::int, NULL::text, o.paymentmethod::text
    FROM   public.hotelrestaurantorders o
    WHERE  o.farmid = p_farmid AND o.settlement = 'Paid' AND o.status <> 'Cancelled'
      AND  o.cashtransactionid IS NOT NULL AND COALESCE(o.totalamount, 0) > 0;
$function$;

-- The Sales page list (Poultry's Sales table: Total / Paid / Balance / Status).
CREATE FUNCTION public.sphotelsale_list(p_farmid text, p_from date DEFAULT NULL, p_to date DEFAULT NULL)
RETURNS TABLE(documenttype text, documentid int, partyid int, partyname text, docdate date, duedate date,
              reference text, label text, totalamount numeric, amountpaid numeric, balance numeric,
              paymentstatus text, bookingstatus text, nights int, roomnumber text, paymentmethod text,
              billedtoaccount boolean, isowing boolean, isoverdue boolean)
LANGUAGE sql STABLE AS $function$
    SELECT d.documenttype, d.documentid, d.partyid, d.partyname, d.docdate, d.duedate, d.reference, d.label,
           d.totalamount, d.amountpaid, d.balance,
           CASE WHEN d.balance <= 0 THEN 'Paid' WHEN d.amountpaid > 0 THEN 'Partial' ELSE 'Pending' END,
           d.bookingstatus, d.nights, d.roomnumber, d.paymentmethod,
           (d.documenttype = 'Stay' AND d.hotelcustomerid IS NOT NULL),
           d.isowing, (d.isowing AND d.balance > 0 AND d.duedate < CURRENT_DATE)
    FROM   public.fnhotelsale_docs(p_farmid) d
    WHERE  d.documenttype <> 'OpeningBalance'
      AND  (p_from IS NULL OR d.docdate >= p_from)
      AND  (p_to   IS NULL OR d.docdate <= p_to)
    ORDER  BY d.docdate DESC, d.documentid DESC;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Guest payments. One money row per stay settled. 327's rules plus: the row
--    joins a payment group, carries its allocation, cannot overpay the bill,
--    and a stay billed to an account moves that account's ledger.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.fnhotelpayment_post(
    p_farmid text, p_bookingid int, p_amount numeric, p_paymentmethod text,
    p_reference text, p_notes text, p_invoiceid int, p_cashaccountid int, p_by text,
    p_paymentdate timestamptz, p_groupid uuid, p_sourcetype text)
RETURNS int LANGUAGE plpgsql AS $function$
DECLARE
    v_inv  int;
    v_acct int;
    v_id   int;
    v_txn  int;
    v_date timestamptz := COALESCE(p_paymentdate, now());
    v_ref  text;
    v_bill numeric(14,2);
    v_paid numeric(14,2);
    v_bal  numeric(14,2);
    v_cust int;
    v_stat text;
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
    SELECT b.status INTO v_stat FROM public.hotelbookings b
    WHERE  b.hotelbookingid = p_bookingid AND b.farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Booking not found.'; END IF;
    IF v_stat IN ('Cancelled', 'NoShow') THEN
        RAISE EXCEPTION 'This booking is % -- there is no bill to pay.', v_stat;
    END IF;

    -- Poultry: overpayment is blocked, there is no credit balance to hold it.
    v_bill := ROUND(public.fnhotelbooking_billtotal(p_farmid, p_bookingid), 2);
    SELECT COALESCE(SUM(hp.amount), 0) INTO v_paid FROM public.hotelpayments hp
    WHERE  hp.farmid = p_farmid AND hp.hotelbookingid = p_bookingid AND hp.status <> 'Void';
    v_bal := GREATEST(v_bill - v_paid, 0);
    IF v_bal <= 0 THEN
        RAISE EXCEPTION 'This bill is already fully paid.';
    END IF;
    IF ROUND(p_amount, 2) > v_bal THEN
        RAISE EXCEPTION 'Cannot apply % to this bill -- its balance is only %.', ROUND(p_amount, 2), v_bal;
    END IF;

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

    SELECT bt.hotelcustomerid INTO v_cust FROM public.hotelbookingbillto bt
    WHERE  bt.hotelbookingid = p_bookingid AND bt.farmid = p_farmid;

    v_acct := COALESCE(p_cashaccountid,
                       public.fnhotelcash_purposeaccount(p_farmid, 'FrontDesk', 'Front Desk Cash'));
    v_ref  := COALESCE(NULLIF(btrim(p_reference), ''),
                       'PAY-' || to_char(now() AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISS') || '-' || p_bookingid::text);

    INSERT INTO public.hotelpayments(farmid, hotelbookingid, hotelinvoiceid, amount, paymentmethod,
                                     reference, notes, receivedby, paymentdate, status, hotelcashaccountid,
                                     paymentgroupid, sourcetype, hotelcustomerid)
    VALUES (p_farmid, p_bookingid, v_inv, ROUND(p_amount, 2), p_paymentmethod,
            v_ref, p_notes, p_by, v_date, 'Posted', v_acct,
            COALESCE(p_groupid, gen_random_uuid()), COALESCE(NULLIF(btrim(p_sourcetype), ''), 'SaleEntry'), v_cust)
    RETURNING hotelpaymentid INTO v_id;

    v_txn := public.fnhotelcash_postonce(
        p_farmid, v_acct, 'Credit', ROUND(p_amount, 2),
        'Guest payment (' || p_paymentmethod || ') - ' || v_ref, v_ref,
        'Payment', v_id, p_by, v_date);
    UPDATE public.hotelpayments SET cashtransactionid = v_txn WHERE hotelpaymentid = v_id;

    INSERT INTO customerpaymentallocation
        (farmid, module, paymentid, saleid, amountapplied, salebalancebefore, salebalanceafter, status, createdby, createdat)
    VALUES (p_farmid, 'hotel', v_id, p_bookingid, ROUND(p_amount, 2), v_bal, v_bal - ROUND(p_amount, 2),
            'Posted', p_by, v_date::timestamp);

    PERFORM public.fnhotelcustomer_ledger(p_farmid, v_cust, 'PaymentDebit', -ROUND(p_amount, 2),
                                          v_inv, v_id, 'Payment ' || v_ref, p_by, v_date);

    IF v_inv IS NOT NULL THEN
        PERFORM public.sphotelinvoice_recompute(p_farmid, v_inv);
    END IF;
    RETURN v_id;
END $function$;

-- The Billing page's endpoint: unchanged signature (327), now a one-document
-- payment through the same path as Customer Balances.
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
BEGIN
    RETURN public.fnhotelpayment_post(p_farmid, p_bookingid, p_amount, p_paymentmethod, p_reference, p_notes,
                                      p_invoiceid, p_cashaccountid, p_by, p_paymentdate, NULL, 'SaleEntry');
END;
$function$;

-- 327's void plus: the allocation is marked Reversed and an account-billed
-- stay's ledger gets the money back on it.
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

    UPDATE customerpaymentallocation SET
        status = 'Reversed', reversedby = p_by, reversedat = now()::timestamp, reversalreason = btrim(p_reason)
    WHERE  farmid = p_farmid AND module = 'hotel' AND paymentid = p_paymentid AND status = 'Posted';

    PERFORM public.fnhotelcustomer_ledger(p_farmid, v.hotelcustomerid, 'PaymentReversal', v.amount,
                                          v.hotelinvoiceid, p_paymentid,
                                          'Reversal of payment ' || COALESCE(v.reference, '#' || p_paymentid) || ': ' || btrim(p_reason),
                                          p_by);

    IF v.hotelinvoiceid IS NOT NULL THEN
        PERFORM public.sphotelinvoice_recompute(p_farmid, v.hotelinvoiceid);
    END IF;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Customer payments across documents (Poultry 223 section 8)
-- ─────────────────────────────────────────────────────────────────────────────
-- Every row of money a customer handed over: guest payments, and corporate
-- rows that moved cash themselves (opening balances; approved before 332).
CREATE FUNCTION public.fnhotelcustomer_moneyrows(p_farmid text)
RETURNS TABLE(paymentgroupid uuid, rowkind text, rowid int, partyid int, documenttype text, documentid int,
              paymentdate timestamp, amount numeric, paymentmethod text, reference text, notes text,
              sourcetype text, status text, cashaccountid int, createdby text,
              reversedby text, reversedat timestamp, reversalreason text, createdat timestamp)
LANGUAGE sql STABLE AS $function$
    SELECT hp.paymentgroupid, 'Stay'::text, hp.hotelpaymentid,
           COALESCE(-hp.hotelcustomerid, b.hotelguestid), 'Stay'::text, hp.hotelbookingid,
           hp.paymentdate::timestamp, hp.amount::numeric, hp.paymentmethod::text, hp.reference::text, hp.notes::text,
           hp.sourcetype, CASE WHEN hp.status = 'Void' THEN 'Reversed' ELSE 'Posted' END,
           hp.hotelcashaccountid, hp.receivedby, hp.voidedby, hp.voidedat::timestamp, hp.voidreason, hp.createdat::timestamp
    FROM   public.hotelpayments hp
    JOIN   public.hotelbookings b ON b.hotelbookingid = hp.hotelbookingid
    WHERE  hp.farmid = p_farmid AND hp.amount > 0
    UNION ALL
    SELECT cp.paymentgroupid, 'Account'::text, cp.hotelcustomerpaymentid,
           -cp.hotelcustomerid,
           CASE WHEN EXISTS (SELECT 1 FROM customerpaymentallocation ca WHERE ca.farmid = p_farmid
                               AND ca.module = 'hotelopening' AND ca.paymentid = cp.hotelcustomerpaymentid)
                THEN 'OpeningBalance' END::text,
           cp.hotelcustomerid,
           cp.paymentdate::timestamp, cp.amount::numeric, cp.paymentmethod, cp.reference, cp.notes,
           COALESCE(cp.sourcetype, 'CustomerPayments'),
           CASE WHEN cp.status = 'Reversed' THEN 'Reversed' ELSE 'Posted' END,
           cp.hotelcashaccountid, COALESCE(cp.approvedby, cp.createdby), cp.reversedby, cp.reversedat::timestamp,
           cp.reversalreason, cp.createdat::timestamp
    FROM   public.hotelcustomerpayments cp
    WHERE  cp.farmid = p_farmid AND cp.appliedgroupid IS NULL
      AND  cp.status IN ('Approved', 'Reversed');
$function$;

-- p_allocations: [{"documenttype": "Stay"|"OpeningBalance", "documentid": n, "amount": x}]
-- (lower-case keys, 223's lesson). Returns the payment group id.
CREATE FUNCTION public.sphotelcustomerpayment_record(
    p_farmid text, p_partyid int, p_amount numeric, p_allocations jsonb,
    p_paymentmethod text DEFAULT NULL, p_paymentdate timestamp DEFAULT NULL, p_cashaccountid int DEFAULT NULL,
    p_reference text DEFAULT NULL, p_notes text DEFAULT NULL, p_sourcetype text DEFAULT 'CustomerBalances',
    p_createdby text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $function$
DECLARE
    v_group  uuid := gen_random_uuid();
    v_amt    numeric(14,2) := ROUND(COALESCE(p_amount, 0), 2);
    v_date   timestamptz := COALESCE(p_paymentdate::timestamptz, now());
    v_method text := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash');
    v_src    text := COALESCE(NULLIF(btrim(p_sourcetype), ''), 'CustomerBalances');
    v_n int; v_sum numeric; v_min numeric; v_dups int; v_bad int; v_matched int := 0;
    v_acct int; v_cpid int; v_txn int;
    a record;
BEGIN
    IF v_amt <= 0 THEN RAISE EXCEPTION 'Payment amount must be greater than 0.'; END IF;
    IF p_partyid IS NULL OR p_partyid = 0 THEN RAISE EXCEPTION 'A customer is required to receive a payment.'; END IF;
    IF public.fnhotelcustomer_partyname(p_farmid, p_partyid) IS NULL THEN
        RAISE EXCEPTION 'Customer does not belong to this company.';
    END IF;
    IF p_cashaccountid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.hotelcashaccounts c
                   WHERE c.hotelcashaccountid = p_cashaccountid AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Cash account does not belong to this company.';
    END IF;
    IF v_date > now() + interval '1 day' THEN RAISE EXCEPTION 'A payment cannot be dated in the future.'; END IF;

    SELECT COUNT(*), COALESCE(SUM(ROUND(x.amount, 2)), 0), MIN(x.amount) INTO v_n, v_sum, v_min
    FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb)) AS x(documenttype text, documentid int, amount numeric)
    WHERE  x.documentid IS NOT NULL AND COALESCE(x.amount, 0) <> 0;
    IF v_n = 0 THEN RAISE EXCEPTION 'Select at least one sale to apply this payment to.'; END IF;
    SELECT COUNT(*) INTO v_dups FROM (
        SELECT 1 FROM jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb)) AS x(documenttype text, documentid int, amount numeric)
        WHERE x.documentid IS NOT NULL AND COALESCE(x.amount, 0) <> 0
        GROUP BY COALESCE(x.documenttype, 'Stay'), x.documentid HAVING COUNT(*) > 1) z;
    IF v_dups > 0 THEN RAISE EXCEPTION 'The same sale appears more than once in this payment.'; END IF;
    IF v_min <= 0 THEN RAISE EXCEPTION 'Each allocation must be greater than 0.'; END IF;
    IF ROUND(v_sum, 2) <> v_amt THEN
        RAISE EXCEPTION 'Allocated total (%) must equal the payment amount (%).', ROUND(v_sum, 2), v_amt;
    END IF;
    SELECT COUNT(*) INTO v_bad
    FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb)) AS x(documenttype text, documentid int, amount numeric)
    WHERE  x.documentid IS NOT NULL AND COALESCE(x.amount, 0) <> 0
      AND  COALESCE(x.documenttype, 'Stay') NOT IN ('Stay', 'OpeningBalance');
    IF v_bad > 0 THEN RAISE EXCEPTION 'Unknown document type. Expected Stay or OpeningBalance.'; END IF;

    -- One payment run per hotel at a time: two clerks cannot both see a full balance.
    PERFORM pg_advisory_xact_lock(hashtext('hotelcustomerpayment:' || p_farmid));

    FOR a IN
        SELECT COALESCE(x.documenttype, 'Stay') AS documenttype, x.documentid, ROUND(x.amount, 2) AS amount,
               d.balance, d.partyid, d.isowing, d.reference
        FROM   jsonb_to_recordset(p_allocations) AS x(documenttype text, documentid int, amount numeric)
        JOIN   public.fnhotelsale_docs(p_farmid) d
               ON d.documenttype = COALESCE(x.documenttype, 'Stay') AND d.documentid = x.documentid
        WHERE  x.documentid IS NOT NULL AND COALESCE(x.amount, 0) <> 0
        ORDER  BY d.docdate, d.documentid
    LOOP
        v_matched := v_matched + 1;
        IF a.partyid IS DISTINCT FROM p_partyid THEN
            RAISE EXCEPTION 'Sale % does not belong to this customer.', a.reference;
        END IF;
        IF a.balance <= 0 THEN RAISE EXCEPTION 'Sale % is already fully paid.', a.reference; END IF;
        IF a.amount > a.balance THEN
            RAISE EXCEPTION 'Cannot apply % to sale % -- its balance is only %.', a.amount, a.reference, a.balance;
        END IF;

        IF a.documenttype = 'Stay' THEN
            PERFORM public.fnhotelpayment_post(p_farmid, a.documentid, a.amount, v_method, p_reference, p_notes,
                                               NULL, p_cashaccountid, p_createdby, v_date, v_group, v_src);
        ELSE
            v_acct := COALESCE(p_cashaccountid,
                               public.fnhotelcash_purposeaccount(p_farmid, 'FrontDesk', 'Front Desk Cash'));
            INSERT INTO public.hotelcustomerpayments(farmid, hotelcustomerid, paymentdate, amount, paymentmethod,
                        hotelcashaccountid, reference, status, notes, createdby, approvedby, approvedat,
                        paymentgroupid, sourcetype)
            VALUES (p_farmid, a.documentid, v_date, a.amount, v_method, v_acct, NULLIF(btrim(p_reference), ''),
                    'Approved', NULLIF(btrim(p_notes), ''), p_createdby, p_createdby, now(), v_group, v_src)
            RETURNING hotelcustomerpaymentid INTO v_cpid;
            v_txn := public.fnhotelcash_postonce(p_farmid, v_acct, 'Credit', a.amount,
                        'Customer payment (opening balance) - ' || public.fnhotelcustomer_partyname(p_farmid, p_partyid),
                        NULLIF(btrim(p_reference), ''), 'CustomerPayment', v_cpid, p_createdby, v_date);
            UPDATE public.hotelcustomerpayments SET cashtransactionid = v_txn WHERE hotelcustomerpaymentid = v_cpid;
            INSERT INTO customerpaymentallocation
                (farmid, module, paymentid, saleid, amountapplied, salebalancebefore, salebalanceafter, status, createdby, createdat)
            VALUES (p_farmid, 'hotelopening', v_cpid, a.documentid, a.amount, a.balance, a.balance - a.amount,
                    'Posted', p_createdby, v_date::timestamp);
            PERFORM public.fnhotelcustomer_ledger(p_farmid, a.documentid, 'PaymentDebit', -a.amount,
                                                  NULL, v_cpid, 'Payment against opening balance', p_createdby, v_date);
        END IF;
    END LOOP;
    IF v_matched < v_n THEN
        RAISE EXCEPTION '% of the selected sales do not belong to this company.', (v_n - v_matched);
    END IF;
    RETURN v_group;
END $function$;

-- Append-only reversal of a whole payment (Poultry 223 section 9).
CREATE FUNCTION public.sphotelcustomerpayment_reverse(
    p_farmid text, p_paymentgroupid uuid, p_reason text DEFAULT NULL, p_reversedby text DEFAULT NULL)
RETURNS int LANGUAGE plpgsql AS $function$
DECLARE
    v_count int := 0;
    r record;
    v_r int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.fnhotelcustomer_moneyrows(p_farmid) m WHERE m.paymentgroupid = p_paymentgroupid) THEN
        RAISE EXCEPTION 'Payment not found for this company.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.fnhotelcustomer_moneyrows(p_farmid) m
                   WHERE m.paymentgroupid = p_paymentgroupid AND m.status = 'Posted') THEN
        RAISE EXCEPTION 'This payment has already been reversed.';
    END IF;
    IF NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'A reason is required to reverse a payment.';
    END IF;

    FOR r IN SELECT hp.hotelpaymentid FROM public.hotelpayments hp
             WHERE hp.farmid = p_farmid AND hp.paymentgroupid = p_paymentgroupid AND hp.status <> 'Void'
             ORDER BY hp.hotelpaymentid
    LOOP
        PERFORM public.sphotelpayment_void(p_farmid, r.hotelpaymentid, btrim(p_reason), p_reversedby);
        v_count := v_count + 1;
    END LOOP;

    FOR r IN SELECT cp.* FROM public.hotelcustomerpayments cp
             WHERE cp.farmid = p_farmid AND cp.paymentgroupid = p_paymentgroupid
               AND cp.appliedgroupid IS NULL AND cp.status = 'Approved'
             FOR UPDATE
    LOOP
        v_r := NULL;
        IF r.cashtransactionid IS NOT NULL THEN
            v_r := public.fnhotelcash_reverse(p_farmid, r.cashtransactionid, 'CustomerPaymentReversal', btrim(p_reason), p_reversedby);
        END IF;
        UPDATE public.hotelcustomerpayments SET
            status = 'Reversed', reversedby = p_reversedby, reversedat = now(), reversalreason = btrim(p_reason),
            reversalcashtransactionid = v_r, updatedat = now()
        WHERE hotelcustomerpaymentid = r.hotelcustomerpaymentid;
        UPDATE customerpaymentallocation SET
            status = 'Reversed', reversedby = p_reversedby, reversedat = now()::timestamp, reversalreason = btrim(p_reason)
        WHERE farmid = p_farmid AND module = 'hotelopening' AND paymentid = r.hotelcustomerpaymentid AND status = 'Posted';
        PERFORM public.fnhotelcustomer_ledger(p_farmid, r.hotelcustomerid, 'PaymentReversal', r.amount, NULL,
                                              r.hotelcustomerpaymentid, 'Reversal of customer payment: ' || btrim(p_reason),
                                              p_reversedby);
        v_count := v_count + 1;
    END LOOP;

    -- An old-style Draft that was approved into this group follows it.
    UPDATE public.hotelcustomerpayments SET
        status = 'Reversed', reversedby = p_reversedby, reversedat = now(), reversalreason = btrim(p_reason), updatedat = now()
    WHERE  farmid = p_farmid AND appliedgroupid = p_paymentgroupid AND status = 'Approved';

    RETURN v_count;
END $function$;

-- The old Customer Payments workflow (319): approving a Draft now allocates it,
-- oldest first, across what the account owes -- through the function above.
CREATE OR REPLACE FUNCTION public.sphotelcustomerpayment_approve(
    p_paymentid  int,
    p_farmid     text,
    p_approvedby text DEFAULT NULL
) RETURNS void AS $$
DECLARE
    v_rec    record;
    v_left   numeric(14,2);
    v_allocs jsonb := '[]'::jsonb;
    v_take   numeric(14,2);
    v_owed   numeric(14,2);
    v_group  uuid;
    d        record;
BEGIN
    SELECT * INTO v_rec FROM public.hotelcustomerpayments
    WHERE hotelcustomerpaymentid = p_paymentid AND farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
    IF v_rec.status = 'Approved' THEN RETURN; END IF;  -- idempotent
    IF v_rec.status <> 'Draft' THEN RAISE EXCEPTION 'Only Draft payments can be approved'; END IF;

    v_left := ROUND(v_rec.amount, 2);
    SELECT COALESCE(SUM(x.balance), 0) INTO v_owed FROM public.fnhotelsale_docs(p_farmid) x
    WHERE  x.partyid = -v_rec.hotelcustomerid AND x.isowing AND x.balance > 0;
    IF v_left > v_owed THEN
        RAISE EXCEPTION 'This payment (%) is more than the customer owes (%). Reduce it, or bill the stay to the account first.', v_left, v_owed;
    END IF;

    FOR d IN SELECT x.* FROM public.fnhotelsale_docs(p_farmid) x
             WHERE x.partyid = -v_rec.hotelcustomerid AND x.isowing AND x.balance > 0
             ORDER BY x.docdate, x.documentid
    LOOP
        EXIT WHEN v_left <= 0;
        v_take := LEAST(v_left, d.balance);
        v_allocs := v_allocs || jsonb_build_array(jsonb_build_object(
                        'documenttype', d.documenttype, 'documentid', d.documentid, 'amount', v_take));
        v_left := v_left - v_take;
    END LOOP;

    v_group := public.sphotelcustomerpayment_record(
        p_farmid, -v_rec.hotelcustomerid, v_rec.amount, v_allocs, v_rec.paymentmethod,
        v_rec.paymentdate::timestamp, v_rec.hotelcashaccountid, v_rec.reference, v_rec.notes,
        'CustomerPayments', p_approvedby);

    UPDATE public.hotelcustomerpayments SET
        status = 'Approved', approvedby = p_approvedby, approvedat = now(), updatedat = now(),
        appliedgroupid = v_group
    WHERE hotelcustomerpaymentid = p_paymentid AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Bill a stay to a corporate account (the post-invoice of 319, finally
--    called). The stay's remaining balance moves from the guest to the account;
--    the account's ledger is charged; the invoice gets the account's due date.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.sphotelsale_billto(p_farmid text, p_bookingid int, p_customerid int, p_by text DEFAULT NULL)
RETURNS int LANGUAGE plpgsql AS $function$
DECLARE
    v_stat text; v_ref text; v_terms int; v_bal numeric(14,2); v_inv int;
BEGIN
    SELECT b.status, b.bookingref INTO v_stat, v_ref FROM public.hotelbookings b
    WHERE  b.hotelbookingid = p_bookingid AND b.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Booking not found.'; END IF;
    IF v_stat <> 'CheckedOut' THEN
        RAISE EXCEPTION 'Only a checked-out stay can be billed to an account (this one is %).', v_stat;
    END IF;
    SELECT c.paymenttermdays INTO v_terms FROM public.hotelcustomers c
    WHERE  c.hotelcustomerid = p_customerid AND c.farmid = p_farmid AND NOT c.isdeleted AND c.isactive;
    IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;
    IF EXISTS (SELECT 1 FROM public.hotelbookingbillto x WHERE x.hotelbookingid = p_bookingid) THEN
        RAISE EXCEPTION 'This stay is already billed to an account.';
    END IF;
    SELECT d.balance INTO v_bal FROM public.fnhotelsale_docs(p_farmid) d
    WHERE  d.documenttype = 'Stay' AND d.documentid = p_bookingid;
    IF COALESCE(v_bal, 0) <= 0 THEN RAISE EXCEPTION 'This bill is already fully paid.'; END IF;

    v_inv := public.sphotelinvoice_generate(p_farmid, p_bookingid, p_by);
    UPDATE public.hotelinvoices SET duedate = CURRENT_DATE + COALESCE(v_terms, 0), updatedat = now()
    WHERE  hotelinvoiceid = v_inv;

    INSERT INTO public.hotelbookingbillto(hotelbookingid, farmid, hotelcustomerid, hotelinvoiceid, amountbilled, createdby)
    VALUES (p_bookingid, p_farmid, p_customerid, v_inv, v_bal, p_by);

    PERFORM public.fnhotelcustomer_ledger(p_farmid, p_customerid, 'InvoiceCredit', v_bal, v_inv, NULL,
                                          'Stay ' || v_ref || ' billed to account', p_by);
    RETURN v_inv;
END $function$;

-- 319's endpoint, same signature: an invoice is posted to the account by
-- billing its stay (the amount is the stay's balance, not a free number).
CREATE OR REPLACE FUNCTION public.sphotelcustomer_postinvoice(
    p_farmid       text,
    p_customerid   int,
    p_invoiceid    int,
    p_amount       numeric,
    p_description  text DEFAULT NULL,
    p_createdby    text DEFAULT NULL
) RETURNS void AS $$
DECLARE v_booking int;
BEGIN
    IF p_amount <= 0 THEN RAISE EXCEPTION 'Invoice amount must be positive'; END IF;
    SELECT i.hotelbookingid INTO v_booking FROM public.hotelinvoices i
    WHERE  i.hotelinvoiceid = p_invoiceid AND i.farmid = p_farmid;
    IF v_booking IS NULL THEN RAISE EXCEPTION 'Invoice not found.'; END IF;
    PERFORM public.sphotelsale_billto(p_farmid, v_booking, p_customerid, p_createdby);
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Customer Balances reads (Poultry 223 section 10-12, same result shapes)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.sphotelcustomerbalances(
    p_farmid text, p_from date DEFAULT NULL, p_to date DEFAULT NULL, p_partyid int DEFAULT NULL,
    p_status text DEFAULT 'All', p_minbalance numeric DEFAULT NULL, p_search text DEFAULT NULL)
RETURNS TABLE(partyid int, partyname text, contactphone text, contactemail text, paymenttermsdays int,
              totalbalance numeric, opendocumentcount int, oldestdocumentdate date, latestdocumentdate date,
              lastpaymentdate timestamp, overdueamount numeric, totalinvoiced numeric, totalpaid numeric)
LANGUAGE sql STABLE AS $function$
    WITH opendocs AS (
        SELECT d.*, (d.duedate < CURRENT_DATE) AS isoverdue
        FROM   public.fnhotelsale_docs(p_farmid) d
        WHERE  d.isowing AND d.balance > 0 AND d.partyid IS NOT NULL
          AND  (p_partyid IS NULL OR d.partyid = p_partyid)
          AND  (p_from IS NULL OR d.docdate >= p_from)
          AND  (p_to   IS NULL OR d.docdate <= p_to)
          AND  CASE COALESCE(p_status, 'All')
                    WHEN 'Partial' THEN d.amountpaid > 0
                    WHEN 'Unpaid'  THEN d.amountpaid = 0
                    WHEN 'Overdue' THEN d.duedate < CURRENT_DATE
                    ELSE TRUE END
    ),
    parties AS (
        SELECT g.hotelguestid AS pid,
               COALESCE(NULLIF(btrim(COALESCE(g.firstname, '') || ' ' || COALESCE(g.lastname, '')), ''), 'Guest #' || g.hotelguestid)::text AS pname,
               g.phone::text AS phone, g.email::text AS email, 0 AS terms
        FROM   public.hotelguests g WHERE g.farmid = p_farmid
        UNION ALL
        SELECT -c.hotelcustomerid, c.customername::text, c.phone::text, c.email::text, c.paymenttermdays
        FROM   public.hotelcustomers c WHERE c.farmid = p_farmid
    )
    SELECT p.pid, p.pname, p.phone, p.email, p.terms,
           SUM(o.balance)::numeric(14,2), COUNT(*)::int, MIN(o.docdate), MAX(o.docdate),
           (SELECT MAX(m.paymentdate) FROM public.fnhotelcustomer_moneyrows(p_farmid) m
             WHERE m.partyid = p.pid AND m.status = 'Posted'),
           SUM(CASE WHEN o.isoverdue THEN o.balance ELSE 0 END)::numeric(14,2),
           SUM(o.totalamount)::numeric(14,2), SUM(o.amountpaid)::numeric(14,2)
    FROM   opendocs o JOIN parties p ON p.pid = o.partyid
    WHERE  (p_search IS NULL OR btrim(p_search) = ''
            OR p.pname ILIKE '%' || btrim(p_search) || '%'
            OR COALESCE(p.phone, '') ILIKE '%' || btrim(p_search) || '%')
    GROUP  BY p.pid, p.pname, p.phone, p.email, p.terms
    HAVING (p_minbalance IS NULL OR SUM(o.balance) >= p_minbalance)
    ORDER  BY SUM(o.balance) DESC;
$function$;

CREATE FUNCTION public.sphotelcustomerbalancesummary(p_farmid text)
RETURNS TABLE(totalbalance numeric, partycount int, overduebalance numeric, paymentstoday numeric,
              largestbalance numeric, largestbalanceparty text)
LANGUAGE sql STABLE AS $function$
    WITH b AS (SELECT * FROM public.sphotelcustomerbalances(p_farmid))
    SELECT COALESCE(SUM(b.totalbalance), 0)::numeric(14,2), COUNT(*)::int,
           COALESCE(SUM(b.overdueamount), 0)::numeric(14,2),
           COALESCE((SELECT SUM(m.amount) FROM public.fnhotelcustomer_moneyrows(p_farmid) m
                      WHERE m.status = 'Posted' AND m.paymentdate::date = CURRENT_DATE), 0)::numeric(14,2),
           COALESCE(MAX(b.totalbalance), 0)::numeric(14,2),
           (SELECT b2.partyname FROM b b2 ORDER BY b2.totalbalance DESC LIMIT 1)
    FROM b;
$function$;

CREATE FUNCTION public.sphotelcustomeropendocs(
    p_farmid text, p_partyid int, p_from date DEFAULT NULL, p_to date DEFAULT NULL, p_status text DEFAULT 'All')
RETURNS TABLE(documenttype text, documentid int, reference text, documentdate date, label text, description text,
              totalamount numeric, amountpaid numeric, balance numeric, duedate date, agedays int,
              status text, isoverdue boolean, cashaccountid int)
LANGUAGE sql STABLE AS $function$
    SELECT d.documenttype, d.documentid, d.reference, d.docdate, d.label, d.bookingstatus,
           d.totalamount, d.amountpaid, d.balance, d.duedate,
           GREATEST(CURRENT_DATE - d.docdate, 0)::int,
           CASE WHEN d.amountpaid > 0 THEN 'Partially Paid' ELSE 'Unpaid' END::text,
           (d.duedate < CURRENT_DATE), NULL::int
    FROM   public.fnhotelsale_docs(p_farmid) d
    WHERE  d.partyid = p_partyid AND d.isowing AND d.balance > 0
      AND  (p_from IS NULL OR d.docdate >= p_from)
      AND  (p_to   IS NULL OR d.docdate <= p_to)
      AND  CASE COALESCE(p_status, 'All')
                WHEN 'Partial' THEN d.amountpaid > 0
                WHEN 'Unpaid'  THEN d.amountpaid = 0
                WHEN 'Overdue' THEN d.duedate < CURRENT_DATE
                ELSE TRUE END
    ORDER  BY d.docdate, d.documentid;
$function$;

-- One row per payment the customer made (Poultry 223 section 12 + 241 + 304).
CREATE FUNCTION public.sphotelcustomerpayment_history(
    p_farmid text, p_partyid int DEFAULT NULL, p_saleid int DEFAULT NULL,
    p_from date DEFAULT NULL, p_to date DEFAULT NULL)
RETURNS TABLE(paymentid text, paymentnumber text, partyid int, partyname text, paymentdate timestamp,
              totalamount numeric, paymentmethod text, reference text, notes text, sourcetype text, status text,
              allocationcount int, cashaccountid int, createdby text, reversedby text, reversedat timestamp,
              reversalreason text, createdat timestamp, saleid int, saletotal numeric, balancebefore numeric,
              amountapplied numeric, balanceafter numeric)
LANGUAGE sql STABLE AS $function$
    WITH m AS (SELECT * FROM public.fnhotelcustomer_moneyrows(p_farmid)),
    g AS (
        SELECT m.paymentgroupid,
               MIN(m.partyid) AS partyid,
               MIN(m.paymentdate) AS paymentdate,
               SUM(m.amount)::numeric(14,2) AS totalamount,
               MIN(m.paymentmethod) AS paymentmethod,
               MIN(m.reference) AS reference,
               MIN(m.notes) AS notes,
               MIN(m.sourcetype) AS sourcetype,
               CASE WHEN bool_or(m.status = 'Posted') THEN 'Posted' ELSE 'Reversed' END AS status,
               COUNT(*)::int AS n,
               MIN(m.cashaccountid) AS cashaccountid,
               MIN(m.createdby) AS createdby,
               MIN(m.reversedby) AS reversedby,
               MIN(m.reversedat) AS reversedat,
               MIN(m.reversalreason) AS reversalreason,
               MIN(m.createdat) AS createdat,
               MIN(m.rowid) FILTER (WHERE m.rowkind = 'Stay') AS stayrow,
               MIN(m.documentid) FILTER (WHERE m.rowkind = 'Stay') AS stayid
        FROM   m
        GROUP  BY m.paymentgroupid
    )
    SELECT g.paymentgroupid::text, g.reference, g.partyid, public.fnhotelcustomer_partyname(p_farmid, g.partyid),
           g.paymentdate, g.totalamount, g.paymentmethod, g.reference, g.notes, g.sourcetype, g.status,
           g.n, g.cashaccountid, g.createdby, g.reversedby, g.reversedat, g.reversalreason, g.createdat,
           CASE WHEN g.n = 1 THEN g.stayid END,
           CASE WHEN g.n = 1 AND g.stayid IS NOT NULL THEN ROUND(public.fnhotelbooking_billtotal(p_farmid, g.stayid), 2) END,
           CASE WHEN g.n = 1 THEN ca.salebalancebefore END,
           CASE WHEN g.n = 1 THEN ca.amountapplied END,
           CASE WHEN g.n = 1 THEN ca.salebalanceafter END
    FROM   g
    LEFT   JOIN customerpaymentallocation ca
           ON ca.farmid = p_farmid AND ca.module = 'hotel' AND ca.paymentid = g.stayrow
    WHERE  (p_partyid IS NULL OR g.partyid = p_partyid)
      AND  (p_from IS NULL OR g.paymentdate::date >= p_from)
      AND  (p_to   IS NULL OR g.paymentdate::date <= p_to)
      AND  (p_saleid IS NULL OR EXISTS (SELECT 1 FROM m m2 WHERE m2.paymentgroupid = g.paymentgroupid
                                          AND m2.rowkind = 'Stay' AND m2.documentid = p_saleid))
    ORDER  BY g.paymentdate DESC, g.createdat DESC;
$function$;

CREATE FUNCTION public.sphotelcustomerpayment_allocations(p_farmid text, p_paymentgroupid uuid)
RETURNS TABLE(allocationid int, documenttype text, documentid int, reference text, documentdate date, label text,
              documenttotal numeric, amountapplied numeric, balancebefore numeric, balanceafter numeric, status text)
LANGUAGE sql STABLE AS $function$
    SELECT ca.allocationid, 'Stay'::text, ca.saleid, b.bookingref::text, b.checkindate,
           ('Stay ' || b.bookingref)::text, ROUND(public.fnhotelbooking_billtotal(p_farmid, ca.saleid), 2),
           ca.amountapplied, ca.salebalancebefore, ca.salebalanceafter, ca.status
    FROM   public.hotelpayments hp
    JOIN   customerpaymentallocation ca ON ca.farmid = p_farmid AND ca.module = 'hotel' AND ca.paymentid = hp.hotelpaymentid
    LEFT   JOIN public.hotelbookings b ON b.hotelbookingid = ca.saleid
    WHERE  hp.farmid = p_farmid AND hp.paymentgroupid = p_paymentgroupid
    UNION ALL
    SELECT ca.allocationid, 'OpeningBalance'::text, ca.saleid, ('OB-' || ca.saleid)::text, c.createdat::date,
           'Opening balance'::text, c.openingbalance, ca.amountapplied, ca.salebalancebefore, ca.salebalanceafter, ca.status
    FROM   public.hotelcustomerpayments cp
    JOIN   customerpaymentallocation ca ON ca.farmid = p_farmid AND ca.module = 'hotelopening' AND ca.paymentid = cp.hotelcustomerpaymentid
    LEFT   JOIN public.hotelcustomers c ON c.hotelcustomerid = ca.saleid
    WHERE  cp.farmid = p_farmid AND cp.paymentgroupid = p_paymentgroupid
    ORDER  BY 5, 1;
$function$;

-- Statement (Poultry 223 section 11 + 242): the documents owed on, and each
-- payment EVENT as one credit. debit = increases what is owed.
CREATE FUNCTION public.sphotelcustomerstatement(
    p_farmid text, p_partyid int, p_from date DEFAULT NULL, p_to date DEFAULT NULL)
RETURNS TABLE(entrydate date, entrytype text, reference text, description text, debit numeric, credit numeric,
              runningbalance numeric, documenttype text, documentid int, paymentid text, allocationcount int,
              sourcetype text)
LANGUAGE sql STABLE AS $function$
    WITH docs AS (SELECT * FROM public.fnhotelsale_docs(p_farmid) d WHERE d.partyid = p_partyid AND d.isowing),
    pays AS (
        SELECT m.paymentgroupid, MIN(m.paymentdate)::date AS pdate, SUM(m.amount)::numeric(14,2) AS amt,
               COUNT(*)::int AS n, MIN(m.reference) AS ref, MIN(m.paymentmethod) AS method, MIN(m.sourcetype) AS src
        FROM   public.fnhotelcustomer_moneyrows(p_farmid) m
        WHERE  m.partyid = p_partyid AND m.status = 'Posted'
        GROUP  BY m.paymentgroupid
    ),
    lines AS (
        SELECT p_from AS entrydate, 'OpeningBalance'::text AS entrytype, NULL::text AS reference,
               'Opening balance'::text AS description,
               CASE WHEN p_from IS NULL THEN 0::numeric(14,2)
                    ELSE COALESCE((SELECT SUM(d.balance) FROM docs d WHERE d.docdate < p_from), 0)::numeric(14,2) END AS debit,
               0::numeric(14,2) AS credit, NULL::text AS documenttype, NULL::int AS documentid,
               NULL::text AS paymentid, NULL::int AS allocationcount, NULL::text AS sourcetype, 0 AS sortkey, 0 AS pin
        UNION ALL
        SELECT d.docdate, 'Sale'::text, d.reference, d.label, d.totalamount::numeric(14,2), 0::numeric(14,2),
               d.documenttype, d.documentid, NULL::text, NULL::int, NULL::text, 1, 1
        FROM   docs d
        WHERE  (p_from IS NULL OR d.docdate >= p_from) AND (p_to IS NULL OR d.docdate <= p_to)
        UNION ALL
        SELECT p.pdate, 'Payment'::text, p.ref,
               ('Payment received' || COALESCE(' (' || NULLIF(btrim(p.method), '') || ')', ''))::text,
               0::numeric(14,2), p.amt, NULL::text, NULL::int, p.paymentgroupid::text, p.n, p.src, 2, 1
        FROM   pays p
        WHERE  (p_from IS NULL OR p.pdate >= p_from) AND (p_to IS NULL OR p.pdate <= p_to)
    )
    SELECT l.entrydate, l.entrytype, l.reference, l.description, l.debit, l.credit,
           SUM(l.debit - l.credit) OVER (ORDER BY l.pin, l.entrydate, l.sortkey, l.documentid NULLS FIRST, l.paymentid
                                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::numeric(14,2),
           l.documenttype, l.documentid, l.paymentid, l.allocationcount, l.sourcetype
    FROM   lines l
    WHERE  NOT (l.entrytype = 'OpeningBalance' AND l.debit = 0)
    ORDER  BY l.pin, l.entrydate, l.sortkey, l.documentid NULLS FIRST, l.paymentid;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Payables: the ONE definition every supplier reader uses (Poultry 238's
--    fnpoultrypayables). amountpaid = paid at entry + supplier payments applied.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.fnhotel_allocated(p_farmid text, p_documenttype text, p_documentid int)
RETURNS numeric LANGUAGE sql STABLE AS $function$
    SELECT COALESCE(SUM(a.amountapplied), 0)::numeric(14,2)
    FROM   supplierpaymentallocation a
    WHERE  a.farmid = p_farmid AND a.module = 'hotel' AND a.status = 'Posted'
      AND  a.documenttype = p_documenttype AND a.documentid = p_documentid;
$function$;

CREATE FUNCTION public.fnhotel_payables(p_farmid text)
RETURNS TABLE(documenttype text, documentid int, supplierid int, docdate date, label text, reference text,
              totalcost numeric, paidatentry numeric, allocated numeric, amountpaid numeric, balance numeric,
              cashaccountid int, duedate date)
LANGUAGE sql STABLE AS $function$
    -- An approved expense naming a supplier. A Credit expense is owed in full;
    -- any other method was paid when it was approved.
    SELECT 'Expense'::text, e.hotelexpenseid, e.hotelsupplierid, e.expensedate,
           (COALESCE(NULLIF(btrim(e.category), '') || ': ', '') || COALESCE(e.description, ''))::text,
           ('E' || e.hotelexpenseid)::text,
           e.amount::numeric(14,2), x.paid, a.x, (x.paid + a.x)::numeric(14,2),
           GREATEST(e.amount - x.paid - a.x, 0)::numeric(14,2), e.hotelcashaccountid,
           COALESCE(e.duedate, e.expensedate + COALESCE(s.paymenttermdays, 0))
    FROM   public.hotelexpenses e
    LEFT   JOIN public.hotelsuppliers s ON s.hotelsupplierid = e.hotelsupplierid
    CROSS  JOIN LATERAL (SELECT (CASE WHEN COALESCE(e.paymentmethod, 'Cash') = 'Credit' THEN 0 ELSE e.amount END)::numeric(14,2) AS paid) x
    CROSS  JOIN LATERAL (SELECT public.fnhotel_allocated(p_farmid, 'Expense', e.hotelexpenseid) AS x) a
    WHERE  e.farmid = p_farmid AND e.hotelsupplierid IS NOT NULL AND e.status IN ('Approved', 'Paid')
    UNION ALL
    -- A capital asset cost bought from a supplier: what was not paid now.
    SELECT 'AssetCost'::text, cc.hotelcapitalassetcostid, cc.hotelsupplierid,
           COALESCE(cc.costdate, ca.acquisitiondate, cc.createdat::date),
           ('Capital investment: ' || ca.assetname
             || COALESCE(' - ' || NULLIF(NULLIF(btrim(cc.description), ''), ca.assetname), ''))::text,
           COALESCE(ca.assetnumber, 'AST-' || ca.hotelcapitalassetid)::text,
           cc.amount::numeric(14,2), COALESCE(cc.amountpaid, cc.amount)::numeric(14,2), a.x,
           (COALESCE(cc.amountpaid, cc.amount) + a.x)::numeric(14,2),
           GREATEST(cc.amount - COALESCE(cc.amountpaid, cc.amount) - a.x, 0)::numeric(14,2),
           cc.hotelcashaccountid,
           COALESCE(cc.duedate, COALESCE(cc.costdate, ca.acquisitiondate, cc.createdat::date) + COALESCE(s.paymenttermdays, 0))
    FROM   public.hotelcapitalassetcosts cc
    JOIN   public.hotelcapitalassets ca ON ca.hotelcapitalassetid = cc.hotelcapitalassetid
    LEFT   JOIN public.hotelsuppliers s ON s.hotelsupplierid = cc.hotelsupplierid
    CROSS  JOIN LATERAL (SELECT public.fnhotel_allocated(p_farmid, 'AssetCost', cc.hotelcapitalassetcostid) AS x) a
    WHERE  cc.farmid = p_farmid AND cc.status = 'Posted' AND ca.status <> 'Reversed'
      AND  cc.hotelsupplierid IS NOT NULL
    UNION ALL
    -- A supplier's opening balance (321).
    SELECT 'OpeningBalance'::text, s.hotelsupplierid, s.hotelsupplierid, s.createdat::date,
           'Opening balance'::text, ('OB-' || s.hotelsupplierid)::text,
           s.openingbalance::numeric(14,2), 0::numeric(14,2), a.x, a.x,
           GREATEST(s.openingbalance - a.x, 0)::numeric(14,2), NULL::int,
           (s.createdat::date + s.paymenttermdays)
    FROM   public.hotelsuppliers s
    CROSS  JOIN LATERAL (SELECT public.fnhotel_allocated(p_farmid, 'OpeningBalance', s.hotelsupplierid) AS x) a
    WHERE  s.farmid = p_farmid AND NOT s.isdeleted AND s.openingbalance > 0;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Supplier Balances (Poultry 224 / 238, same result columns)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.sphotelsupplierbalances(
    p_farmid text, p_from date DEFAULT NULL, p_to date DEFAULT NULL, p_supplierid int DEFAULT NULL,
    p_status text DEFAULT 'All', p_minbalance numeric DEFAULT NULL, p_search text DEFAULT NULL)
RETURNS TABLE(partyid int, partyname text, contactphone text, contactemail text, paymenttermsdays int,
              totalbalance numeric, opendocumentcount int, oldestdocumentdate date, latestdocumentdate date,
              lastpaymentdate timestamp, overdueamount numeric, totalinvoiced numeric, totalpaid numeric)
LANGUAGE sql STABLE AS $function$
    WITH openpurchases AS (
        SELECT d.*, (d.duedate < CURRENT_DATE) AS isoverdue
        FROM   public.fnhotel_payables(p_farmid) d
        WHERE  d.balance > 0
          AND  (p_supplierid IS NULL OR d.supplierid = p_supplierid)
          AND  (p_from IS NULL OR d.docdate >= p_from)
          AND  (p_to   IS NULL OR d.docdate <= p_to)
          AND  CASE COALESCE(p_status, 'All')
                    WHEN 'Partial' THEN d.amountpaid > 0
                    WHEN 'Unpaid'  THEN d.amountpaid = 0
                    WHEN 'Overdue' THEN d.duedate < CURRENT_DATE
                    ELSE TRUE END
    )
    SELECT s.hotelsupplierid, s.suppliername::text, s.phone::text, s.email::text, s.paymenttermdays,
           SUM(o.balance)::numeric(14,2), COUNT(*)::int, MIN(o.docdate), MAX(o.docdate),
           (SELECT MAX(sp.paymentdate)::timestamp FROM public.hotelsupplierpayments sp
             WHERE sp.farmid = p_farmid AND sp.hotelsupplierid = s.hotelsupplierid AND sp.status = 'Approved'),
           SUM(CASE WHEN o.isoverdue THEN o.balance ELSE 0 END)::numeric(14,2),
           SUM(o.totalcost)::numeric(14,2), SUM(o.amountpaid)::numeric(14,2)
    FROM   openpurchases o
    JOIN   public.hotelsuppliers s ON s.hotelsupplierid = o.supplierid AND s.farmid = p_farmid
    WHERE  (p_search IS NULL OR btrim(p_search) = ''
            OR s.suppliername ILIKE '%' || btrim(p_search) || '%'
            OR COALESCE(s.phone, '') ILIKE '%' || btrim(p_search) || '%')
    GROUP  BY s.hotelsupplierid, s.suppliername, s.phone, s.email, s.paymenttermdays
    HAVING (p_minbalance IS NULL OR SUM(o.balance) >= p_minbalance)
    ORDER  BY SUM(o.balance) DESC;
$function$;

CREATE FUNCTION public.sphotelsupplierbalancesummary(p_farmid text)
RETURNS TABLE(totalbalance numeric, partycount int, overduebalance numeric, paymentstoday numeric,
              largestbalance numeric, largestbalanceparty text)
LANGUAGE sql STABLE AS $function$
    WITH b AS (SELECT * FROM public.sphotelsupplierbalances(p_farmid))
    SELECT COALESCE(SUM(b.totalbalance), 0)::numeric(14,2), COUNT(*)::int,
           COALESCE(SUM(b.overdueamount), 0)::numeric(14,2),
           COALESCE((SELECT SUM(sp.amount) FROM public.hotelsupplierpayments sp
                      WHERE sp.farmid = p_farmid AND sp.status = 'Approved'
                        AND sp.paymentdate::date = CURRENT_DATE), 0)::numeric(14,2),
           COALESCE(MAX(b.totalbalance), 0)::numeric(14,2),
           (SELECT b2.partyname FROM b b2 ORDER BY b2.totalbalance DESC LIMIT 1)
    FROM b;
$function$;

CREATE FUNCTION public.sphotelsupplieropenpurchases(
    p_farmid text, p_supplierid int, p_from date DEFAULT NULL, p_to date DEFAULT NULL, p_status text DEFAULT 'All')
RETURNS TABLE(documenttype text, documentid int, reference text, documentdate date, label text, description text,
              totalamount numeric, amountpaid numeric, balance numeric, duedate date, agedays int,
              status text, isoverdue boolean, cashaccountid int)
LANGUAGE sql STABLE AS $function$
    SELECT d.documenttype, d.documentid, d.reference, d.docdate, d.label, NULL::text,
           d.totalcost, d.amountpaid, d.balance, d.duedate,
           GREATEST(CURRENT_DATE - d.docdate, 0)::int,
           CASE WHEN d.amountpaid > 0 THEN 'Partially Paid' ELSE 'Unpaid' END::text,
           (d.duedate < CURRENT_DATE), d.cashaccountid
    FROM   public.fnhotel_payables(p_farmid) d
    WHERE  d.supplierid = p_supplierid AND d.balance > 0
      AND  (p_from IS NULL OR d.docdate >= p_from)
      AND  (p_to   IS NULL OR d.docdate <= p_to)
      AND  CASE COALESCE(p_status, 'All')
                WHEN 'Partial' THEN d.amountpaid > 0
                WHEN 'Unpaid'  THEN d.amountpaid = 0
                WHEN 'Overdue' THEN d.duedate < CURRENT_DATE
                ELSE TRUE END
    ORDER  BY d.docdate, d.documenttype, d.documentid;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. Supplier payments: ONE cash-out per payment (Poultry 262 / Restaurant 329)
-- ─────────────────────────────────────────────────────────────────────────────
-- Applies an existing payment header: validates the allocation list, writes the
-- allocations, moves the money once, charges the supplier ledger.
CREATE FUNCTION public.fnhotelsupplierpayment_apply(p_farmid text, p_paymentid int, p_allocations jsonb, p_by text)
RETURNS int LANGUAGE plpgsql AS $function$
DECLARE
    v_p record; v_name text; v_n int; v_sum numeric; v_min numeric; v_dups int; v_bad int; v_matched int := 0;
    a record; v_txn int;
BEGIN
    SELECT * INTO v_p FROM public.hotelsupplierpayments sp
    WHERE  sp.hotelsupplierpaymentid = p_paymentid AND sp.farmid = p_farmid FOR UPDATE;
    SELECT s.suppliername INTO v_name FROM public.hotelsuppliers s
    WHERE  s.hotelsupplierid = v_p.hotelsupplierid AND s.farmid = p_farmid;

    SELECT COUNT(*), COALESCE(SUM(ROUND(x.amount, 2)), 0), MIN(x.amount) INTO v_n, v_sum, v_min
    FROM   jsonb_to_recordset(COALESCE(p_allocations, '[]'::jsonb)) AS x(documenttype text, documentid int, amount numeric)
    WHERE  x.documentid IS NOT NULL AND COALESCE(x.amount, 0) <> 0;
    IF v_n = 0 THEN RAISE EXCEPTION 'Select at least one purchase to apply this payment to.'; END IF;
    SELECT COUNT(*) INTO v_dups FROM (
        SELECT 1 FROM jsonb_to_recordset(p_allocations) AS x(documenttype text, documentid int, amount numeric)
        WHERE x.documentid IS NOT NULL AND COALESCE(x.amount, 0) <> 0
        GROUP BY x.documenttype, x.documentid HAVING COUNT(*) > 1) z;
    IF v_dups > 0 THEN RAISE EXCEPTION 'The same purchase appears more than once in this payment.'; END IF;
    IF v_min <= 0 THEN RAISE EXCEPTION 'Each allocation must be greater than 0.'; END IF;
    IF ROUND(v_sum, 2) <> ROUND(v_p.amount, 2) THEN
        RAISE EXCEPTION 'Allocated total (%) must equal the payment amount (%).', ROUND(v_sum, 2), ROUND(v_p.amount, 2);
    END IF;
    SELECT COUNT(*) INTO v_bad FROM jsonb_to_recordset(p_allocations) AS x(documenttype text, documentid int, amount numeric)
    WHERE  x.documentid IS NOT NULL AND COALESCE(x.amount, 0) <> 0
      AND  COALESCE(x.documenttype, '') NOT IN ('Expense', 'AssetCost', 'OpeningBalance');
    IF v_bad > 0 THEN RAISE EXCEPTION 'Unknown document type. Expected Expense, AssetCost or OpeningBalance.'; END IF;

    FOR a IN
        SELECT x.documenttype, x.documentid, ROUND(x.amount, 2) AS amount, d.balance, d.reference
        FROM   jsonb_to_recordset(p_allocations) AS x(documenttype text, documentid int, amount numeric)
        JOIN   public.fnhotel_payables(p_farmid) d
               ON d.documenttype = x.documenttype AND d.documentid = x.documentid AND d.supplierid = v_p.hotelsupplierid
        WHERE  x.documentid IS NOT NULL AND COALESCE(x.amount, 0) <> 0
        ORDER  BY d.docdate, d.documentid
    LOOP
        v_matched := v_matched + 1;
        IF a.balance <= 0 THEN RAISE EXCEPTION '% is already fully paid.', a.reference; END IF;
        IF a.amount > a.balance THEN
            RAISE EXCEPTION 'Cannot apply % to % -- its balance is only %.', a.amount, a.reference, a.balance;
        END IF;
        INSERT INTO supplierpaymentallocation (farmid, module, paymentid, documenttype, documentid, amountapplied,
                                               documentbalancebefore, documentbalanceafter, status, createdby)
        VALUES (p_farmid, 'hotel', p_paymentid, a.documenttype, a.documentid, a.amount, a.balance,
                a.balance - a.amount, 'Posted', p_by);
    END LOOP;
    IF v_matched < v_n THEN
        RAISE EXCEPTION '% of the selected purchases do not belong to this supplier or company.', (v_n - v_matched);
    END IF;

    PERFORM public.fnhotelcash_assertcanpay(p_farmid, v_p.hotelcashaccountid, v_p.amount,
            'This account does not have enough money for this payment, and it is not allowed to go negative.');
    v_txn := public.fnhotelcash_postonce(p_farmid, v_p.hotelcashaccountid, 'Debit', v_p.amount,
            'Supplier payment: ' || COALESCE(v_name, '?') || COALESCE(' (' || NULLIF(btrim(v_p.reference), '') || ')', ''),
            v_p.reference, 'SupplierPayment', p_paymentid, p_by, v_p.paymentdate);
    UPDATE public.hotelsupplierpayments SET cashtransactionid = v_txn WHERE hotelsupplierpaymentid = p_paymentid;

    PERFORM public.fnhotelsupplier_ledger(p_farmid, v_p.hotelsupplierid, 'PaymentDebit', -v_p.amount, NULL, p_paymentid,
                                          COALESCE(v_p.notes, 'Supplier payment'), p_by, v_p.paymentdate);
    RETURN v_matched;
END $function$;

CREATE FUNCTION public.sphotelsupplierpayment_record(
    p_farmid text, p_supplierid int, p_amount numeric, p_allocations jsonb,
    p_paymentmethod text DEFAULT NULL, p_paymentdate timestamp DEFAULT NULL, p_cashaccountid int DEFAULT NULL,
    p_reference text DEFAULT NULL, p_notes text DEFAULT NULL, p_sourcetype text DEFAULT 'SupplierBalances',
    p_createdby text DEFAULT NULL)
RETURNS int LANGUAGE plpgsql AS $function$
DECLARE
    v_amt  numeric(14,2) := ROUND(COALESCE(p_amount, 0), 2);
    v_when timestamptz := COALESCE(p_paymentdate::timestamptz, now());
    v_id   int;
BEGIN
    IF v_amt <= 0 THEN RAISE EXCEPTION 'Payment amount must be greater than 0.'; END IF;
    IF p_supplierid IS NULL THEN RAISE EXCEPTION 'Choose the supplier this payment is for.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.hotelsuppliers s WHERE s.hotelsupplierid = p_supplierid AND s.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Supplier does not belong to this company.';
    END IF;
    IF p_cashaccountid IS NULL THEN RAISE EXCEPTION 'Choose the cash account this payment is paid from.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.hotelcashaccounts c WHERE c.hotelcashaccountid = p_cashaccountid AND c.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Cash account does not belong to this company.';
    END IF;
    IF v_when > now() + interval '1 day' THEN RAISE EXCEPTION 'A payment cannot be dated in the future.'; END IF;

    PERFORM pg_advisory_xact_lock(hashtext('hotelsupplierpayment:' || p_farmid));

    INSERT INTO public.hotelsupplierpayments(farmid, hotelsupplierid, paymentdate, amount, paymentmethod,
                hotelcashaccountid, reference, status, notes, createdby, approvedby, approvedat, sourcetype)
    VALUES (p_farmid, p_supplierid, v_when, v_amt, COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash'),
            p_cashaccountid, NULLIF(btrim(p_reference), ''), 'Approved', NULLIF(btrim(p_notes), ''),
            p_createdby, p_createdby, now(), COALESCE(NULLIF(btrim(p_sourcetype), ''), 'SupplierBalances'))
    RETURNING hotelsupplierpaymentid INTO v_id;

    PERFORM public.fnhotelsupplierpayment_apply(p_farmid, v_id, p_allocations, p_createdby);
    RETURN v_id;
END $function$;

-- The old Supplier Payments workflow (321): approving a Draft allocates it,
-- oldest first (its linked expense first), through the same apply.
CREATE OR REPLACE FUNCTION public.sphotelsupplierpayment_approve(
    p_paymentid  int,
    p_farmid     text,
    p_approvedby text DEFAULT NULL
) RETURNS void AS $$
DECLARE
    v_rec record; v_left numeric(14,2); v_allocs jsonb := '[]'::jsonb; v_take numeric(14,2); v_owed numeric(14,2);
    d record;
BEGIN
    SELECT * INTO v_rec FROM public.hotelsupplierpayments
    WHERE hotelsupplierpaymentid = p_paymentid AND farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
    IF v_rec.status = 'Approved' THEN RETURN; END IF;
    IF v_rec.status <> 'Draft' THEN RAISE EXCEPTION 'Only Draft payments can be approved'; END IF;

    v_left := ROUND(v_rec.amount, 2);
    SELECT COALESCE(SUM(x.balance), 0) INTO v_owed FROM public.fnhotel_payables(p_farmid) x
    WHERE  x.supplierid = v_rec.hotelsupplierid AND x.balance > 0;
    IF v_left > v_owed THEN
        RAISE EXCEPTION 'This payment (%) is more than the supplier is owed (%).', v_left, v_owed;
    END IF;
    FOR d IN SELECT x.* FROM public.fnhotel_payables(p_farmid) x
             WHERE x.supplierid = v_rec.hotelsupplierid AND x.balance > 0
             ORDER BY (x.documenttype = 'Expense' AND x.documentid = v_rec.linkedexpenseid) DESC, x.docdate, x.documentid
    LOOP
        EXIT WHEN v_left <= 0;
        v_take := LEAST(v_left, d.balance);
        v_allocs := v_allocs || jsonb_build_array(jsonb_build_object(
                        'documenttype', d.documenttype, 'documentid', d.documentid, 'amount', v_take));
        v_left := v_left - v_take;
    END LOOP;

    UPDATE public.hotelsupplierpayments SET
        status = 'Approved', approvedby = p_approvedby, approvedat = now(), updatedat = now(),
        hotelcashaccountid = COALESCE(hotelcashaccountid,
                                      public.fnhotelcash_purposeaccount(p_farmid, 'Expenses', 'Expenses Account')),
        sourcetype = COALESCE(sourcetype, 'SupplierPayments')
    WHERE hotelsupplierpaymentid = p_paymentid AND farmid = p_farmid;

    PERFORM public.fnhotelsupplierpayment_apply(p_farmid, p_paymentid, v_allocs, p_approvedby);
END;
$$ LANGUAGE plpgsql;

-- Reverse an approved supplier payment (327 left none): the money comes back
-- through a new ledger row dated today; a reason is required.
CREATE FUNCTION public.sphotelsupplierpayment_reverse(p_farmid text, p_paymentid int, p_reason text DEFAULT NULL,
                                                      p_reversedby text DEFAULT NULL)
RETURNS int LANGUAGE plpgsql AS $function$
DECLARE v_p record; v_n int; v_r int;
BEGIN
    SELECT * INTO v_p FROM public.hotelsupplierpayments sp
    WHERE  sp.hotelsupplierpaymentid = p_paymentid AND sp.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found for this company.'; END IF;
    IF v_p.status = 'Reversed' THEN RAISE EXCEPTION 'This payment has already been reversed.'; END IF;
    IF v_p.status <> 'Approved' THEN RAISE EXCEPTION 'Only a paid (approved) payment can be reversed.'; END IF;
    IF NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'A reason is required to reverse a payment.'; END IF;

    UPDATE supplierpaymentallocation
       SET status = 'Reversed', reversedby = p_reversedby, reversedat = now()::timestamp, reversalreason = btrim(p_reason)
     WHERE farmid = p_farmid AND module = 'hotel' AND paymentid = p_paymentid AND status = 'Posted';
    GET DIAGNOSTICS v_n = ROW_COUNT;

    IF v_p.cashtransactionid IS NOT NULL THEN
        v_r := public.fnhotelcash_reverse(p_farmid, v_p.cashtransactionid, 'SupplierPaymentReversal', btrim(p_reason), p_reversedby);
    END IF;

    UPDATE public.hotelsupplierpayments SET
        status = 'Reversed', reversedby = p_reversedby, reversedat = now(), reversalreason = btrim(p_reason),
        reversalcashtransactionid = v_r, updatedat = now()
    WHERE hotelsupplierpaymentid = p_paymentid;

    PERFORM public.fnhotelsupplier_ledger(p_farmid, v_p.hotelsupplierid, 'PaymentReversal', v_p.amount, NULL, p_paymentid,
                                          'Reversal of supplier payment: ' || btrim(p_reason), p_reversedby);
    RETURN v_n;
END $function$;

CREATE FUNCTION public.sphotelsupplierpayment_history(p_farmid text, p_supplierid int DEFAULT NULL,
                                                      p_documenttype text DEFAULT NULL, p_documentid int DEFAULT NULL,
                                                      p_from date DEFAULT NULL, p_to date DEFAULT NULL)
RETURNS TABLE(paymentid text, paymentnumber text, partyid int, partyname text, paymentdate timestamp,
              totalamount numeric, paymentmethod text, reference text, notes text, sourcetype text, status text,
              allocationcount int, cashaccountid int, createdby text, reversedby text, reversedat timestamp,
              reversalreason text, createdat timestamp)
LANGUAGE sql STABLE AS $function$
    SELECT sp.hotelsupplierpaymentid::text, NULL::text, sp.hotelsupplierid, s.suppliername::text,
           sp.paymentdate::timestamp, sp.amount::numeric, sp.paymentmethod, sp.reference, sp.notes,
           COALESCE(sp.sourcetype, 'SupplierPayments'),
           CASE WHEN sp.status = 'Reversed' THEN 'Reversed' ELSE 'Posted' END,
           (SELECT COUNT(*)::int FROM supplierpaymentallocation a
             WHERE a.farmid = p_farmid AND a.module = 'hotel' AND a.paymentid = sp.hotelsupplierpaymentid),
           sp.hotelcashaccountid, COALESCE(sp.approvedby, sp.createdby), sp.reversedby, sp.reversedat::timestamp,
           sp.reversalreason, sp.createdat::timestamp
    FROM   public.hotelsupplierpayments sp
    LEFT   JOIN public.hotelsuppliers s ON s.hotelsupplierid = sp.hotelsupplierid
    WHERE  sp.farmid = p_farmid AND sp.status IN ('Approved', 'Reversed')
      AND  (p_supplierid IS NULL OR sp.hotelsupplierid = p_supplierid)
      AND  (p_from IS NULL OR sp.paymentdate::date >= p_from)
      AND  (p_to   IS NULL OR sp.paymentdate::date <= p_to)
      AND  (p_documentid IS NULL OR EXISTS (
            SELECT 1 FROM supplierpaymentallocation a
             WHERE a.farmid = p_farmid AND a.module = 'hotel' AND a.paymentid = sp.hotelsupplierpaymentid
               AND a.documentid = p_documentid AND (p_documenttype IS NULL OR a.documenttype = p_documenttype)))
    ORDER  BY sp.paymentdate DESC, sp.hotelsupplierpaymentid DESC;
$function$;

CREATE FUNCTION public.sphotelsupplierpayment_allocations(p_farmid text, p_paymentid int)
RETURNS TABLE(allocationid int, documenttype text, documentid int, reference text, documentdate date, label text,
              documenttotal numeric, amountapplied numeric, balancebefore numeric, balanceafter numeric, status text)
LANGUAGE sql STABLE AS $function$
    SELECT a.allocationid, a.documenttype, a.documentid, d.reference, d.docdate, d.label,
           d.totalcost, a.amountapplied, a.documentbalancebefore, a.documentbalanceafter, a.status
    FROM   supplierpaymentallocation a
    LEFT   JOIN public.fnhotel_payables(p_farmid) d ON d.documenttype = a.documenttype AND d.documentid = a.documentid
    WHERE  a.farmid = p_farmid AND a.module = 'hotel' AND a.paymentid = p_paymentid
    ORDER  BY a.allocationid;
$function$;

-- Statement: billed (debit = increases what is owed), paid at entry, payments.
CREATE FUNCTION public.sphotelsupplierstatement(p_farmid text, p_supplierid int, p_from date DEFAULT NULL,
                                                p_to date DEFAULT NULL)
RETURNS TABLE(entrydate date, entrytype text, reference text, description text, debit numeric, credit numeric,
              runningbalance numeric, documenttype text, documentid int, paymentid text, allocationcount int,
              sourcetype text)
LANGUAGE sql STABLE AS $function$
    WITH docs AS (SELECT * FROM public.fnhotel_payables(p_farmid) d WHERE d.supplierid = p_supplierid),
    lines AS (
        SELECT p_from AS entrydate, 'OpeningBalance'::text AS entrytype, NULL::text AS reference,
               'Opening balance'::text AS description,
               CASE WHEN p_from IS NULL THEN 0::numeric(14,2)
                    ELSE COALESCE((SELECT SUM(d.balance) FROM docs d WHERE d.docdate < p_from), 0)::numeric(14,2) END AS debit,
               0::numeric(14,2) AS credit, NULL::text AS documenttype, NULL::int AS documentid,
               NULL::text AS paymentid, NULL::int AS allocationcount, NULL::text AS sourcetype, 0 AS sortkey, 0 AS pin
        UNION ALL
        SELECT d.docdate, CASE WHEN d.documenttype = 'Expense' THEN 'Expense' ELSE 'Purchase' END::text,
               d.reference, d.label, d.totalcost::numeric(14,2), 0::numeric(14,2), d.documenttype, d.documentid,
               NULL::text, NULL::int, NULL::text, 1, 1
        FROM   docs d
        WHERE  (p_from IS NULL OR d.docdate >= p_from) AND (p_to IS NULL OR d.docdate <= p_to)
        UNION ALL
        SELECT d.docdate, 'Payment'::text, d.reference,
               CASE WHEN d.documenttype = 'Expense' THEN 'Paid when recorded' ELSE 'Paid at time of purchase' END::text,
               0::numeric(14,2), d.paidatentry::numeric(14,2), d.documenttype, d.documentid, NULL::text, NULL::int,
               NULL::text, 2, 1
        FROM   docs d
        WHERE  d.paidatentry > 0 AND (p_from IS NULL OR d.docdate >= p_from) AND (p_to IS NULL OR d.docdate <= p_to)
        UNION ALL
        SELECT sp.paymentdate::date, 'Payment'::text,
               COALESCE(NULLIF(btrim(sp.reference), ''), 'SP' || sp.hotelsupplierpaymentid::text)::text,
               ('Payment made' || COALESCE(' (' || NULLIF(btrim(sp.paymentmethod), '') || ')', ''))::text,
               0::numeric(14,2), sp.amount::numeric(14,2), NULL::text, NULL::int,
               sp.hotelsupplierpaymentid::text, NULL::int, sp.sourcetype, 2, 1
        FROM   public.hotelsupplierpayments sp
        WHERE  sp.farmid = p_farmid AND sp.hotelsupplierid = p_supplierid AND sp.status = 'Approved'
          AND  (p_from IS NULL OR sp.paymentdate::date >= p_from)
          AND  (p_to   IS NULL OR sp.paymentdate::date <= p_to)
    )
    SELECT l.entrydate, l.entrytype, l.reference, l.description, l.debit, l.credit,
           SUM(l.debit - l.credit) OVER (ORDER BY l.pin, l.entrydate, l.sortkey, l.documentid NULLS FIRST, l.paymentid
                                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::numeric(14,2),
           l.documenttype, l.documentid, l.paymentid, l.allocationcount, l.sourcetype
    FROM   lines l
    WHERE  NOT (l.entrytype = 'OpeningBalance' AND l.debit = 0)
    ORDER  BY l.pin, l.entrydate, l.sortkey, l.documentid NULLS FIRST, l.paymentid;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. Expenses: 327's approve / cancel plus the supplier. A Credit expense that
--     names a supplier is owed to that supplier (ledger charged); a cancelled
--     one with a supplier payment against it is refused (Poultry 238).
-- ─────────────────────────────────────────────────────────────────────────────
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
    IF v.hotelsupplierid IS NOT NULL AND NOT EXISTS (
           SELECT 1 FROM public.hotelsuppliers s WHERE s.hotelsupplierid = v.hotelsupplierid AND s.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Supplier does not belong to this company.';
    END IF;

    IF COALESCE(v.paymentmethod, 'Cash') <> 'Credit' THEN
        v_acct := COALESCE(v.hotelcashaccountid,
                           public.fnhotelcash_purposeaccount(p_farmid, 'Expenses', 'Expenses Account'));
        v_txn := public.fnhotelcash_postonce(
            p_farmid, v_acct, 'Debit', v.amount,
            COALESCE(v.category, 'Expense') || ': ' || COALESCE(v.description, ''), v.receiptref,
            'Expense', p_expenseid, p_by, v.expensedate::timestamptz);
    ELSIF v.hotelsupplierid IS NOT NULL THEN
        PERFORM public.fnhotelsupplier_ledger(p_farmid, v.hotelsupplierid, 'ExpenseCredit', v.amount, p_expenseid, NULL,
                                              COALESCE(v.category, 'Expense') || ': ' || COALESCE(v.description, ''), p_by);
    END IF;

    UPDATE public.hotelexpenses SET
        status = 'Approved', approvedby = p_by, approvedat = now(), updatedat = now(),
        hotelcashaccountid = COALESCE(v_acct, hotelcashaccountid),
        cashtransactionid  = v_txn
    WHERE  hotelexpenseid = p_expenseid;
END;
$function$;

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
    IF public.fnhotel_allocated(p_farmid, 'Expense', p_expenseid) > 0 THEN
        RAISE EXCEPTION 'A supplier payment has been recorded against this expense. Reverse the payment on Supplier Payments first.';
    END IF;

    IF v.cashtransactionid IS NOT NULL THEN
        v_r := public.fnhotelcash_reverse(p_farmid, v.cashtransactionid, 'ExpenseReversal',
                                          COALESCE(p_reason, 'Expense cancelled'), p_by);
    END IF;
    IF v.status IN ('Approved', 'Paid') AND COALESCE(v.paymentmethod, 'Cash') = 'Credit' AND v.hotelsupplierid IS NOT NULL THEN
        PERFORM public.fnhotelsupplier_ledger(p_farmid, v.hotelsupplierid, 'ExpenseReversal', -v.amount, p_expenseid, NULL,
                                              'Cancelled: ' || COALESCE(v.description, '') || COALESCE(' - ' || p_reason, ''), p_by);
    END IF;

    UPDATE public.hotelexpenses SET
        status = 'Cancelled', cancelreason = p_reason, cancelledby = p_by, cancelledat = now(),
        reversalcashtransactionid = v_r, updatedat = now()
    WHERE  hotelexpenseid = p_expenseid;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. Capital asset costs: Poultry's paid-from account and amount paid now.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.fnhotelassetcost_settle(
    p_farmid text, p_costid int, p_supplierid int, p_cashaccountid int, p_amountpaid numeric,
    p_duedate date, p_by text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE c record; v_paid numeric(14,2); v_txn int; v_name text;
BEGIN
    SELECT cc.*, a.assetname, a.assetnumber INTO c
    FROM   public.hotelcapitalassetcosts cc JOIN public.hotelcapitalassets a ON a.hotelcapitalassetid = cc.hotelcapitalassetid
    WHERE  cc.hotelcapitalassetcostid = p_costid AND cc.farmid = p_farmid FOR UPDATE OF cc;
    IF NOT FOUND THEN RAISE EXCEPTION 'Asset cost not found.'; END IF;
    v_paid := ROUND(COALESCE(p_amountpaid, c.amount), 2);
    IF v_paid < 0 THEN RAISE EXCEPTION 'Amount paid cannot be negative.'; END IF;
    IF v_paid > c.amount THEN RAISE EXCEPTION 'Amount paid cannot be more than the cost (%).', c.amount; END IF;
    IF v_paid > 0 AND p_cashaccountid IS NULL THEN
        RAISE EXCEPTION 'Choose the cash account this was paid from.';
    END IF;
    IF p_supplierid IS NOT NULL THEN
        SELECT s.suppliername INTO v_name FROM public.hotelsuppliers s
        WHERE  s.hotelsupplierid = p_supplierid AND s.farmid = p_farmid AND NOT s.isdeleted;
        IF NOT FOUND THEN RAISE EXCEPTION 'Supplier does not belong to this company.'; END IF;
    END IF;
    IF v_paid < c.amount AND p_supplierid IS NULL THEN
        RAISE EXCEPTION 'Choose the supplier the unpaid % is owed to.', (c.amount - v_paid);
    END IF;
    IF v_paid > 0 THEN
        PERFORM public.fnhotelcash_assertcanpay(p_farmid, p_cashaccountid, v_paid,
            'This account does not have enough money for this payment, and it is not allowed to go negative.');
        v_txn := public.fnhotelcash_postonce(p_farmid, p_cashaccountid, 'Debit', v_paid,
            'Capital investment: ' || c.assetname || COALESCE(' ' || c.assetnumber, ''), c.assetnumber,
            'AssetPurchase', p_costid, p_by, COALESCE(c.costdate, CURRENT_DATE)::timestamptz);
    END IF;
    UPDATE public.hotelcapitalassetcosts SET
        hotelsupplierid = p_supplierid, hotelcashaccountid = p_cashaccountid, amountpaid = v_paid,
        duedate = CASE WHEN v_paid < c.amount THEN p_duedate END, cashtransactionid = v_txn
    WHERE  hotelcapitalassetcostid = p_costid;
    IF v_paid < c.amount THEN
        PERFORM public.fnhotelsupplier_ledger(p_farmid, p_supplierid, 'AssetCost', c.amount - v_paid, NULL, NULL,
                                              'Capital investment: ' || c.assetname, p_by);
    END IF;
END $function$;

CREATE FUNCTION public.sphotelcapitalasset_createpaid(
    p_farmid text, p_name text, p_categoryid int, p_acquisitiondate date, p_inservicedate date,
    p_residualvalue numeric, p_usefullifemonths int, p_amount numeric, p_supplier text, p_location text,
    p_serialnumber text, p_notes text, p_createdby text,
    p_supplierid int, p_cashaccountid int, p_amountpaid numeric, p_duedate date)
RETURNS int LANGUAGE plpgsql AS $function$
DECLARE v_id int; v_cost int; v_sup text := p_supplier;
BEGIN
    IF p_supplierid IS NOT NULL AND NULLIF(btrim(COALESCE(v_sup, '')), '') IS NULL THEN
        SELECT s.suppliername INTO v_sup FROM public.hotelsuppliers s WHERE s.hotelsupplierid = p_supplierid AND s.farmid = p_farmid;
    END IF;
    v_id := public.sphotelcapitalasset_create(p_farmid, p_name, p_categoryid, p_acquisitiondate, p_inservicedate,
                                              p_residualvalue, p_usefullifemonths, p_amount, v_sup, p_location,
                                              p_serialnumber, p_notes, p_createdby);
    SELECT cc.hotelcapitalassetcostid INTO v_cost FROM public.hotelcapitalassetcosts cc
    WHERE  cc.hotelcapitalassetid = v_id AND cc.sourcetype = 'Acquisition' ORDER BY cc.hotelcapitalassetcostid LIMIT 1;
    IF v_cost IS NOT NULL THEN
        PERFORM public.fnhotelassetcost_settle(p_farmid, v_cost, p_supplierid, p_cashaccountid, p_amountpaid, p_duedate, p_createdby);
    END IF;
    RETURN v_id;
END $function$;

CREATE FUNCTION public.sphotelcapitalasset_addcostpaid(
    p_assetid int, p_farmid text, p_amount numeric, p_description text, p_costdate date, p_createdby text,
    p_supplierid int, p_cashaccountid int, p_amountpaid numeric, p_duedate date)
RETURNS int LANGUAGE plpgsql AS $function$
DECLARE v_cost int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.hotelcapitalassets a WHERE a.hotelcapitalassetid = p_assetid AND a.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Asset not found.';
    END IF;
    v_cost := public.sphotelcapitalasset_addcost(p_assetid, p_farmid, p_amount, p_description, p_costdate, p_createdby);
    PERFORM public.fnhotelassetcost_settle(p_farmid, v_cost, p_supplierid, p_cashaccountid, p_amountpaid, p_duedate, p_createdby);
    RETURN v_cost;
END $function$;

-- 322's reverse-cost plus: refused while a supplier payment is applied to it;
-- the money paid now comes back; the supplier's ledger drops the unpaid part.
CREATE OR REPLACE FUNCTION public.sphotelcapitalasset_reversecost(
    p_costid int, p_assetid int, p_farmid text, p_reason text DEFAULT NULL, p_by text DEFAULT NULL
) RETURNS void AS $$
DECLARE c record; v_r int;
BEGIN
    SELECT * INTO c FROM public.hotelcapitalassetcosts
    WHERE  hotelcapitalassetcostid = p_costid AND hotelcapitalassetid = p_assetid AND farmid = p_farmid AND status = 'Posted'
    FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;
    IF public.fnhotel_allocated(p_farmid, 'AssetCost', p_costid) > 0 THEN
        RAISE EXCEPTION 'A supplier payment has been recorded against this cost. Reverse the payment on Supplier Payments first.';
    END IF;
    IF c.cashtransactionid IS NOT NULL AND c.reversalcashtransactionid IS NULL THEN
        v_r := public.fnhotelcash_reverse(p_farmid, c.cashtransactionid, 'AssetPurchaseReversal',
                                          COALESCE(p_reason, 'Asset cost reversed'), p_by);
    END IF;
    IF c.amountpaid IS NOT NULL AND c.amountpaid < c.amount AND c.hotelsupplierid IS NOT NULL THEN
        PERFORM public.fnhotelsupplier_ledger(p_farmid, c.hotelsupplierid, 'AssetCostReversal', -(c.amount - c.amountpaid),
                                              NULL, NULL, 'Asset cost reversed' || COALESCE(': ' || p_reason, ''), p_by);
    END IF;
    UPDATE public.hotelcapitalassetcosts SET status = 'Reversed', reversedby = p_by, reversedat = now(),
           reversalreason = p_reason, reversalcashtransactionid = COALESCE(v_r, reversalcashtransactionid)
    WHERE  hotelcapitalassetcostid = p_costid;
    PERFORM fnhotelcapitalasset_recalc(p_assetid);
END;
$$ LANGUAGE plpgsql;

-- 322's reverse plus the same money rules for every posted cost of the asset.
CREATE OR REPLACE FUNCTION public.sphotelcapitalasset_reverse(
    p_id int, p_farmid text, p_reason text DEFAULT NULL, p_by text DEFAULT NULL
) RETURNS void AS $$
DECLARE v_depcount int; c record; v_r int;
BEGIN
    SELECT COUNT(*) INTO v_depcount FROM public.hotelassetdepreciation WHERE hotelcapitalassetid=p_id AND status='Posted';
    IF v_depcount > 0 THEN RAISE EXCEPTION 'Cannot reverse: % depreciation entries exist. Reverse them first.', v_depcount; END IF;
    IF EXISTS (SELECT 1 FROM public.hotelcapitalassetcosts cc
               WHERE cc.hotelcapitalassetid = p_id AND cc.farmid = p_farmid AND cc.status = 'Posted'
                 AND public.fnhotel_allocated(p_farmid, 'AssetCost', cc.hotelcapitalassetcostid) > 0) THEN
        RAISE EXCEPTION 'A supplier payment has been recorded against this asset. Reverse the payment on Supplier Payments first.';
    END IF;
    FOR c IN SELECT * FROM public.hotelcapitalassetcosts cc
             WHERE cc.hotelcapitalassetid = p_id AND cc.farmid = p_farmid AND cc.status = 'Posted' FOR UPDATE
    LOOP
        v_r := NULL;
        IF c.cashtransactionid IS NOT NULL AND c.reversalcashtransactionid IS NULL THEN
            v_r := public.fnhotelcash_reverse(p_farmid, c.cashtransactionid, 'AssetPurchaseReversal',
                                              COALESCE(p_reason, 'Asset reversed'), p_by);
            UPDATE public.hotelcapitalassetcosts SET reversalcashtransactionid = v_r, reversedat = COALESCE(reversedat, now()),
                   reversedby = COALESCE(reversedby, p_by), reversalreason = COALESCE(reversalreason, p_reason)
            WHERE  hotelcapitalassetcostid = c.hotelcapitalassetcostid;
        END IF;
        IF c.amountpaid IS NOT NULL AND c.amountpaid < c.amount AND c.hotelsupplierid IS NOT NULL THEN
            PERFORM public.fnhotelsupplier_ledger(p_farmid, c.hotelsupplierid, 'AssetCostReversal', -(c.amount - c.amountpaid),
                                                  NULL, NULL, 'Asset reversed' || COALESCE(': ' || p_reason, ''), p_by);
        END IF;
    END LOOP;
    UPDATE public.hotelcapitalassets SET status='Reversed', reversedreason=p_reason, reversedby=p_by, reversedat=now(), updatedat=now()
    WHERE hotelcapitalassetid=p_id AND farmid=p_farmid;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- 13. Balance audit (Poultry's fnbalanceaudit): empty when healthy.
--     customer -- a stay's posted payments must equal its posted allocations;
--     supplier -- allocations must never exceed what a document costs.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.sphotelbalanceaudit(p_farmid text)
RETURNS TABLE(side text, documenttype text, documentid int, amountpaid numeric, allocated numeric, difference numeric)
LANGUAGE sql STABLE AS $function$
    SELECT 'customer'::text, 'Stay'::text, b.hotelbookingid, p.paid, a.alloc, (p.paid - a.alloc)
    FROM   public.hotelbookings b
    CROSS  JOIN LATERAL (SELECT COALESCE(SUM(hp.amount), 0)::numeric(14,2) AS paid FROM public.hotelpayments hp
                          WHERE hp.farmid = p_farmid AND hp.hotelbookingid = b.hotelbookingid AND hp.status <> 'Void') p
    CROSS  JOIN LATERAL (SELECT COALESCE(SUM(ca.amountapplied), 0)::numeric(14,2) AS alloc FROM customerpaymentallocation ca
                          WHERE ca.farmid = p_farmid AND ca.module = 'hotel' AND ca.saleid = b.hotelbookingid
                            AND ca.status = 'Posted') a
    WHERE  b.farmid = p_farmid AND p.paid <> a.alloc
    UNION ALL
    SELECT 'supplier'::text, d.documenttype, d.documentid, d.totalcost, d.allocated + d.paidatentry,
           (d.totalcost - d.allocated - d.paidatentry)
    FROM   public.fnhotel_payables(p_farmid) d
    WHERE  d.allocated + d.paidatentry > d.totalcost;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 14. Cash Flow. 331's body; only arms 8, 9 and 10 changed (marked 332) and
--     8b / 9b / 10' / 10b added. Every other arm is 331's, byte for byte.
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
          -- 332: a Draft approved INTO a payment group moved no cash itself (its
          -- guest-payment rows are arm 1); a reversed row still received on its day.
          AND  cp.appliedgroupid IS NULL
          AND  (cp.status = 'Approved' OR (cp.status = 'Reversed' AND cp.cashtransactionid IS NOT NULL))
          AND  cp.amount > 0
          AND  cp.paymentdate::timestamp >= v_from
          AND  cp.paymentdate::timestamp <= v_to;

        -- ---- 8b. customer payment reversed (332) -----------------------------
        RETURN QUERY
        SELECT 'CustomerPaymentReversal'::text,
               FALSE,
               cp.hotelcustomerpaymentid,
               cp.hotelcashaccountid,
               NULL::text,
               cp.reversedat::timestamp,
               'CashOut'::text,
               'CustomerPaymentReversal'::text,
               cp.hotelcustomerpaymentid,
               FALSE,
               -(cp.amount::numeric),
               ('Reversal of customer payment' || COALESCE(' from ' || NULLIF(btrim(c.customername), ''), '')
                || COALESCE(' - ' || NULLIF(btrim(cp.reversalreason), ''), ''))::text,
               'OperatingOut'::text,
               cp.reversedat::timestamp
        FROM   hotelcustomerpayments cp
        LEFT   JOIN hotelcustomers c ON c.hotelcustomerid = cp.hotelcustomerid
        WHERE  lower(cp.farmid::text) = lower(p_farmid)
          AND  cp.reversalcashtransactionid IS NOT NULL
          AND  cp.reversedat::timestamp >= v_from
          AND  cp.reversedat::timestamp <= v_to;
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
          -- 332: a payment reversed later still left on its day (9b brings it back).
          AND  (sp.status = 'Approved' OR (sp.status = 'Reversed' AND sp.cashtransactionid IS NOT NULL))
          AND  sp.amount > 0
          AND  sp.paymentdate::timestamp >= v_from
          AND  sp.paymentdate::timestamp <= v_to;

        -- ---- 9b. supplier payment reversed (332) -----------------------------
        RETURN QUERY
        SELECT 'SupplierPaymentReversal'::text,
               FALSE,
               sp.hotelsupplierpaymentid,
               sp.hotelcashaccountid,
               NULL::text,
               sp.reversedat::timestamp,
               'CashIn'::text,
               'SupplierPaymentReversal'::text,
               sp.hotelsupplierpaymentid,
               FALSE,
               sp.amount::numeric,
               ('Reversal of supplier payment' || COALESCE(' to ' || NULLIF(btrim(s.suppliername), ''), '')
                || COALESCE(' - ' || NULLIF(btrim(sp.reversalreason), ''), ''))::text,
               'OperatingIn'::text,
               sp.reversedat::timestamp
        FROM   hotelsupplierpayments sp
        LEFT   JOIN hotelsuppliers s ON s.hotelsupplierid = sp.hotelsupplierid
        WHERE  lower(sp.farmid::text) = lower(p_farmid)
          AND  sp.reversalcashtransactionid IS NOT NULL
          AND  sp.reversedat::timestamp >= v_from
          AND  sp.reversedat::timestamp <= v_to;
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
          AND  cc.amountpaid IS NULL          -- 332: only costs recorded before "Paid from"
          AND  COALESCE(cc.costdate, a.acquisitiondate, cc.createdat::date)::timestamp >= v_from
          AND  COALESCE(cc.costdate, a.acquisitiondate, cc.createdat::date)::timestamp <= v_to;

        -- ---- 10'. capital asset cost paid now (332) ----------------------------
        -- Poultry's "Amount paid now" from the "Paid from" account: only that
        -- part is cash; the rest is owed and leaves as a supplier payment (arm 9).
        -- On its day even if reversed later (10b brings it back).
        RETURN QUERY
        SELECT 'CapitalAsset'::text,
               FALSE,
               cc.hotelcapitalassetcostid,
               cc.hotelcashaccountid,
               NULL::text,
               COALESCE(cc.costdate, a.acquisitiondate, cc.createdat::date)::timestamp,
               'CashOut'::text,
               'CapitalAsset'::text,
               a.hotelcapitalassetid,
               FALSE,
               -(cc.amountpaid::numeric),
               (COALESCE(NULLIF(btrim(a.assetname), ''), 'Asset')
                || COALESCE(' ' || a.assetnumber, '')
                || COALESCE(' - ' || NULLIF(btrim(cc.description), ''), ''))::text,
               'OperatingOut'::text,
               cc.createdat::timestamp
        FROM   hotelcapitalassetcosts cc
        JOIN   hotelcapitalassets a ON a.hotelcapitalassetid = cc.hotelcapitalassetid
        WHERE  lower(cc.farmid::text) = lower(p_farmid)
          AND  cc.cashtransactionid IS NOT NULL
          AND  cc.amountpaid > 0
          AND  COALESCE(cc.costdate, a.acquisitiondate, cc.createdat::date)::timestamp >= v_from
          AND  COALESCE(cc.costdate, a.acquisitiondate, cc.createdat::date)::timestamp <= v_to;

        -- ---- 10b. capital asset cost reversed: the money paid comes back (332)
        RETURN QUERY
        SELECT 'CapitalAssetReversal'::text,
               FALSE,
               cc.hotelcapitalassetcostid,
               cc.hotelcashaccountid,
               NULL::text,
               cc.reversedat::timestamp,
               'CashIn'::text,
               'CapitalAsset'::text,
               a.hotelcapitalassetid,
               FALSE,
               cc.amountpaid::numeric,
               ('Reversal: ' || COALESCE(NULLIF(btrim(a.assetname), ''), 'Asset')
                || COALESCE(' ' || a.assetnumber, '')
                || COALESCE(' - ' || NULLIF(btrim(cc.reversalreason), ''), ''))::text,
               'OperatingIn'::text,
               cc.reversedat::timestamp
        FROM   hotelcapitalassetcosts cc
        JOIN   hotelcapitalassets a ON a.hotelcapitalassetid = cc.hotelcapitalassetid
        WHERE  lower(cc.farmid::text) = lower(p_farmid)
          AND  cc.reversalcashtransactionid IS NOT NULL
          AND  cc.amountpaid > 0
          AND  cc.reversedat::timestamp >= v_from
          AND  cc.reversedat::timestamp <= v_to;
    END IF;

    -- ---- 11. owner money (331, Poultry 253 arm 4) -----------------------------
    -- FINANCING, not operating: the owner funded the hotel or took funding back.
    -- Every record on its own day, including one reversed later; the reversal is
    -- its own row (11b) on the day it happened, as in the ledger.
    IF to_regclass('public.hotelownermoney') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'OwnerMoney'::text,
               FALSE,
               o.hotelownermoneyid,
               o.hotelcashaccountid,
               NULL::text,
               o.transactiondate::timestamp,
               CASE WHEN o.transactiontype = 'Contribution' THEN 'CashIn' ELSE 'CashOut' END::text,
               CASE WHEN o.transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END::text,
               o.hotelownermoneyid,
               FALSE,
               (CASE WHEN o.transactiontype = 'Contribution' THEN o.amount ELSE -o.amount END)::numeric,
               COALESCE(NULLIF(btrim(o.notes), ''), NULLIF(btrim(o.ownername), ''),
                        CASE WHEN o.transactiontype = 'Contribution' THEN 'Owner contribution' ELSE 'Owner draw' END)::text,
               CASE WHEN o.transactiontype = 'Contribution' THEN 'FinancingIn' ELSE 'FinancingOut' END::text,
               o.createdat::timestamp
        FROM   hotelownermoney o
        WHERE  lower(o.farmid::text) = lower(p_farmid)
          AND  o.cashtransactionid IS NOT NULL
          AND  o.transactiondate::timestamp >= v_from
          AND  o.transactiondate::timestamp <= v_to;

        RETURN QUERY
        SELECT 'OwnerMoneyReversal'::text,
               FALSE,
               o.hotelownermoneyid,
               o.hotelcashaccountid,
               NULL::text,
               o.reversedat::timestamp,
               CASE WHEN o.transactiontype = 'Contribution' THEN 'CashOut' ELSE 'CashIn' END::text,
               CASE WHEN o.transactiontype = 'Contribution' THEN 'OwnerContribution' ELSE 'OwnerDraw' END::text,
               o.hotelownermoneyid,
               FALSE,
               (CASE WHEN o.transactiontype = 'Contribution' THEN -o.amount ELSE o.amount END)::numeric,
               ('Reversal of ' || COALESCE(o.transactionnumber, 'owner money #' || o.hotelownermoneyid::text)
                || COALESCE(' - ' || NULLIF(btrim(o.reversalreason), ''), ''))::text,
               CASE WHEN o.transactiontype = 'Contribution' THEN 'FinancingOut' ELSE 'FinancingIn' END::text,
               o.reversedat::timestamp
        FROM   hotelownermoney o
        WHERE  lower(o.farmid::text) = lower(p_farmid)
          AND  o.reversalcashtransactionid IS NOT NULL
          AND  o.reversedat::timestamp >= v_from
          AND  o.reversedat::timestamp <= v_to;
    END IF;

    -- ---- 12. loans received (331, Poultry 254 arm 5) --------------------------
    -- The AMOUNT RECEIVED, not the principal: only what arrived is cash in.
    -- Financing -- borrowed, not earned. A cancelled loan's money going back is
    -- its own row (12b).
    IF to_regclass('public.hotelloans') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'FinancingLoan'::text,
               FALSE,
               l.hotelloanid,
               l.hotelcashaccountid,
               NULL::text,
               l.loandate::timestamp,
               'CashIn'::text,
               'LoanReceived'::text,
               l.hotelloanid,
               FALSE,
               l.amountreceived::numeric,
               ('Loan received from ' || l.lendername)::text,
               'FinancingIn'::text,
               l.createdat::timestamp
        FROM   hotelloans l
        WHERE  lower(l.farmid::text) = lower(p_farmid)
          AND  l.cashtransactionid IS NOT NULL
          AND  l.amountreceived > 0
          AND  l.loandate::timestamp >= v_from
          AND  l.loandate::timestamp <= v_to;

        RETURN QUERY
        SELECT 'FinancingLoanCancelled'::text,
               FALSE,
               l.hotelloanid,
               l.hotelcashaccountid,
               NULL::text,
               l.reversedat::timestamp,
               'CashOut'::text,
               'LoanReceived'::text,
               l.hotelloanid,
               FALSE,
               -(l.amountreceived::numeric),
               ('Cancelled loan ' || COALESCE(l.loannumber, '#' || l.hotelloanid::text) || ' from ' || l.lendername)::text,
               'FinancingOut'::text,
               l.reversedat::timestamp
        FROM   hotelloans l
        WHERE  lower(l.farmid::text) = lower(p_farmid)
          AND  l.reversalcashtransactionid IS NOT NULL
          AND  l.reversedat::timestamp >= v_from
          AND  l.reversedat::timestamp <= v_to;

        -- ---- 13. loan repayments (331, Poultry 254 arm 6) ---------------------
        -- The FULL payment leaves the account, so the full payment is money out
        -- -- principal, interest and fees together. The P&L counts only the
        -- interest and fees (from the same row); nothing here is counted twice.
        RETURN QUERY
        SELECT 'FinancingLoanPayment'::text,
               FALSE,
               p.hotelloanpaymentid,
               p.hotelcashaccountid,
               NULL::text,
               p.paymentdate::timestamp,
               'CashOut'::text,
               'LoanRepayment'::text,
               p.hotelloanid,
               FALSE,
               -(p.totalamount::numeric),
               ('Loan repayment to ' || l.lendername)::text,
               'FinancingOut'::text,
               p.createdat::timestamp
        FROM   hotelloanpayments p
        JOIN   hotelloans l ON l.hotelloanid = p.hotelloanid
        WHERE  lower(p.farmid::text) = lower(p_farmid)
          AND  p.cashtransactionid IS NOT NULL
          AND  p.paymentdate::timestamp >= v_from
          AND  p.paymentdate::timestamp <= v_to;

        RETURN QUERY
        SELECT 'FinancingLoanPaymentReversal'::text,
               FALSE,
               p.hotelloanpaymentid,
               p.hotelcashaccountid,
               NULL::text,
               p.reversedat::timestamp,
               'CashIn'::text,
               'LoanRepayment'::text,
               p.hotelloanid,
               FALSE,
               p.totalamount::numeric,
               ('Reversal of repayment ' || COALESCE(p.paymentnumber, '#' || p.hotelloanpaymentid::text)
                || ' to ' || l.lendername)::text,
               'FinancingIn'::text,
               p.reversedat::timestamp
        FROM   hotelloanpayments p
        JOIN   hotelloans l ON l.hotelloanid = p.hotelloanid
        WHERE  lower(p.farmid::text) = lower(p_farmid)
          AND  p.reversalcashtransactionid IS NOT NULL
          AND  p.reversedat::timestamp >= v_from
          AND  p.reversedat::timestamp <= v_to;
    END IF;

    -- ---- 14. reconciliation differences (331) ---------------------------------
    -- What a count found over or short, as posted. Operating (cash over/short),
    -- never an expense and never in the P&L. Amounts come from the ledger rows
    -- the count wrote, so this arm cannot disagree with the ledger.
    IF to_regclass('public.hotelcashreconciliations') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'ReconciliationAdjustment'::text,
               FALSE,
               h.hotelcashreconciliationid,
               h.hotelcashaccountid,
               NULL::text,
               t.txndate::timestamp,
               CASE WHEN t.txntype = 'Credit' THEN 'CashIn' ELSE 'CashOut' END::text,
               'ReconciliationAdjustment'::text,
               h.hotelcashreconciliationid,
               FALSE,
               (CASE WHEN t.txntype = 'Credit' THEN t.amount ELSE -t.amount END)::numeric,
               COALESCE(t.description, 'Cash count')::text,
               CASE WHEN t.txntype = 'Credit' THEN 'OperatingIn' ELSE 'OperatingOut' END::text,
               t.createdat::timestamp
        FROM   hotelcashreconciliations h
        JOIN   hotelcashtransactions t ON t.hotelcashtxnid = h.adjustmenttransactionid
        WHERE  lower(h.farmid::text) = lower(p_farmid)
          AND  t.txndate::timestamp >= v_from
          AND  t.txndate::timestamp <= v_to;

        RETURN QUERY
        SELECT 'ReconciliationReversal'::text,
               FALSE,
               h.hotelcashreconciliationid,
               h.hotelcashaccountid,
               NULL::text,
               t.txndate::timestamp,
               CASE WHEN t.txntype = 'Credit' THEN 'CashIn' ELSE 'CashOut' END::text,
               'ReconciliationAdjustment'::text,
               h.hotelcashreconciliationid,
               FALSE,
               (CASE WHEN t.txntype = 'Credit' THEN t.amount ELSE -t.amount END)::numeric,
               COALESCE(t.description, 'Reversal of cash count')::text,
               CASE WHEN t.txntype = 'Credit' THEN 'OperatingIn' ELSE 'OperatingOut' END::text,
               t.createdat::timestamp
        FROM   hotelcashreconciliations h
        JOIN   hotelcashtransactions t ON t.hotelcashtxnid = h.reversaltransactionid
        WHERE  lower(h.farmid::text) = lower(p_farmid)
          AND  t.txndate::timestamp >= v_from
          AND  t.txndate::timestamp <= v_to;
    END IF;

    -- ---- 15. recorded cash adjustments (331) ---------------------------------
    -- sourcetype 'Adjustment' + the reason as description, exactly the shape
    -- lib/cash's flowLabel reads for Poultry's adjustments. An owner draw or
    -- contribution that was never recorded is Financing; everything else is
    -- Operating.
    IF to_regclass('public.hotelcashadjustments') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'CashAdjustment'::text,
               FALSE,
               x.hotelcashadjustmentid,
               x.hotelcashaccountid,
               NULL::text,
               x.adjustmentdate::timestamp,
               CASE WHEN x.amount > 0 THEN 'CashIn' ELSE 'CashOut' END::text,
               'Adjustment'::text,
               x.hotelcashadjustmentid,
               FALSE,
               x.amount::numeric,
               x.reason::text,
               (CASE WHEN x.reason IN ('Owner contribution not recorded', 'Owner draw not recorded')
                     THEN 'Financing' ELSE 'Operating' END
                || CASE WHEN x.amount > 0 THEN 'In' ELSE 'Out' END)::text,
               x.createdat::timestamp
        FROM   hotelcashadjustments x
        WHERE  lower(x.farmid::text) = lower(p_farmid)
          AND  x.cashtransactionid IS NOT NULL
          AND  x.adjustmentdate::timestamp >= v_from
          AND  x.adjustmentdate::timestamp <= v_to;

        RETURN QUERY
        SELECT 'CashAdjustmentReversal'::text,
               FALSE,
               x.hotelcashadjustmentid,
               x.hotelcashaccountid,
               NULL::text,
               x.reversedat::timestamp,
               CASE WHEN x.amount > 0 THEN 'CashOut' ELSE 'CashIn' END::text,
               'Adjustment'::text,
               x.hotelcashadjustmentid,
               FALSE,
               -(x.amount::numeric),
               x.reason::text,
               (CASE WHEN x.reason IN ('Owner contribution not recorded', 'Owner draw not recorded')
                     THEN 'Financing' ELSE 'Operating' END
                || CASE WHEN x.amount > 0 THEN 'Out' ELSE 'In' END)::text,
               x.reversedat::timestamp
        FROM   hotelcashadjustments x
        WHERE  lower(x.farmid::text) = lower(p_farmid)
          AND  x.reversalcashtransactionid IS NOT NULL
          AND  x.reversedat::timestamp >= v_from
          AND  x.reversedat::timestamp <= v_to;
    END IF;
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 15. Cash Flow detail: 331's categories; the reversal rows land in their
--     original's bucket.
-- ─────────────────────────────────────────────────────────────────────────────
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
               WHEN r.rowsource IN ('CustomerPayment', 'CustomerPaymentReversal') THEN 'Customer payments'
               WHEN r.rowsource IN ('SupplierPayment', 'SupplierPaymentReversal') THEN 'Supplier payments'
               WHEN r.rowsource IN ('CapitalAsset', 'CapitalAssetReversal') THEN 'Capital Asset'
               -- 331: Poultry's own category keys, so lib/cash labels them in
               -- Poultry's words; a reversal lands in its original's bucket.
               WHEN r.rowsource IN ('OwnerMoney', 'OwnerMoneyReversal',
                                    'FinancingLoan', 'FinancingLoanCancelled',
                                    'FinancingLoanPayment', 'FinancingLoanPaymentReversal',
                                    'ReconciliationAdjustment', 'ReconciliationReversal')
                   THEN r.sourcetype
               WHEN r.rowsource IN ('CashAdjustment', 'CashAdjustmentReversal')
                   THEN COALESCE(NULLIF(btrim(r.description), ''), 'Adjustment')
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
-- 16. Verification (read-only)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE v_missing text;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
    FROM   unnest(ARRAY[
               'fnhotelsale_docs', 'sphotelsale_list', 'sphotelsale_billto', 'fnhotelpayment_post',
               'sphotelcustomerbalances', 'sphotelcustomerbalancesummary', 'sphotelcustomeropendocs',
               'sphotelcustomerpayment_record', 'sphotelcustomerpayment_reverse', 'sphotelcustomerpayment_history',
               'sphotelcustomerpayment_allocations', 'sphotelcustomerstatement', 'sphotelbalanceaudit',
               'fnhotel_payables', 'sphotelsupplierbalances', 'sphotelsupplierbalancesummary',
               'sphotelsupplieropenpurchases', 'sphotelsupplierpayment_record', 'sphotelsupplierpayment_reverse',
               'sphotelsupplierpayment_history', 'sphotelsupplierpayment_allocations', 'sphotelsupplierstatement',
               'fnhotelassetcost_settle', 'sphotelcapitalasset_createpaid', 'sphotelcapitalasset_addcostpaid',
               'sphotelcashflow_rows', 'sphotelcashflow_detail'
           ]) f
    WHERE  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                       WHERE n.nspname = 'public' AND p.proname = f);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '332 verification failed, missing: %', v_missing;
    END IF;
    -- The backfill left no stay whose payments disagree with its allocations.
    IF EXISTS (SELECT 1 FROM public.hotelbookings b, LATERAL public.sphotelbalanceaudit(b.farmid) a
               WHERE a.side = 'customer' LIMIT 1) THEN
        RAISE EXCEPTION '332 verification failed: customer allocations disagree with guest payments';
    END IF;
END $$;
