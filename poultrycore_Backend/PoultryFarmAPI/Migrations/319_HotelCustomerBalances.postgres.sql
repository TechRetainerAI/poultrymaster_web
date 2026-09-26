-- =============================================================================
-- 319_HotelCustomerBalances.postgres.sql
--
-- Purpose
-- -------
-- Customer (debtor) balance tracking for the Hotel module.
--
-- Tables created
-- --------------
--   hotelcustomers          corporate / credit-account customers
--   hotelcustomerledger     immutable debit/credit ledger per customer
--   hotelcustomerpayments   payment workflow (Draft -> Approved -> Cancelled)
--
-- Convention: CurrentBalance > 0 means the customer OWES the hotel.
--
-- Balance changes from:
--   InvoiceCredit   — guest invoice raised (increases balance)
--   PaymentDebit    — customer payment approved (decreases balance)
--   AdjustmentDebit / AdjustmentCredit — manual corrections
--   OpeningBalance  — initial balance at creation
--
-- Every write is atomic (single function call, full transaction).
-- Ledger rows are append-only: reversals insert signed correction rows.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. hotelcustomers
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotelcustomers (
    hotelcustomerid        serial       PRIMARY KEY,
    farmid                 text         NOT NULL,
    customername           text         NOT NULL,
    customertype           text         NOT NULL DEFAULT 'Corporate',
    phone                  text,
    email                  text,
    address                text,
    city                   text,
    paymenttermdays        int          NOT NULL DEFAULT 0,
    creditlimit            numeric(14,2) NOT NULL DEFAULT 0,
    openingbalance         numeric(14,2) NOT NULL DEFAULT 0,
    currentbalance         numeric(14,2) NOT NULL DEFAULT 0,
    isactive               boolean      NOT NULL DEFAULT true,
    isdeleted              boolean      NOT NULL DEFAULT false,
    notes                  text,
    createdby              text,
    createdat              timestamptz  NOT NULL DEFAULT now(),
    updatedat              timestamptz
);

CREATE INDEX IF NOT EXISTS ix_hotelcustomers_farmid
    ON public.hotelcustomers(farmid);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. hotelcustomerledger
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotelcustomerledger (
    hotelcustomerledgerid  bigserial    PRIMARY KEY,
    farmid                 text         NOT NULL,
    hotelcustomerid        int          NOT NULL REFERENCES public.hotelcustomers(hotelcustomerid),
    transactiondate        timestamptz  NOT NULL DEFAULT now(),
    transactiontype        text         NOT NULL,
    invoiceid              int,
    paymentid              int,
    debitamount            numeric(14,2) NOT NULL DEFAULT 0,
    creditamount           numeric(14,2) NOT NULL DEFAULT 0,
    balanceaftertransaction numeric(14,2) NOT NULL DEFAULT 0,
    description            text,
    createdby              text,
    createdat              timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_hotelcustledger_oneleg CHECK (
        (debitamount > 0 AND creditamount = 0)
        OR (debitamount = 0 AND creditamount > 0)
    )
);

CREATE INDEX IF NOT EXISTS ix_hotelcustomerledger_farmid
    ON public.hotelcustomerledger(farmid);
CREATE INDEX IF NOT EXISTS ix_hotelcustomerledger_custid
    ON public.hotelcustomerledger(hotelcustomerid);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. hotelcustomerpayments
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotelcustomerpayments (
    hotelcustomerpaymentid serial       PRIMARY KEY,
    farmid                 text         NOT NULL,
    hotelcustomerid        int          NOT NULL REFERENCES public.hotelcustomers(hotelcustomerid),
    paymentdate            timestamptz  NOT NULL DEFAULT now(),
    amount                 numeric(14,2) NOT NULL CHECK (amount > 0),
    paymentmethod          text         NOT NULL DEFAULT 'Cash',
    hotelcashaccountid     int,
    reference              text,
    linkedinvoiceid        int,
    status                 text         NOT NULL DEFAULT 'Draft',
    notes                  text,
    createdby              text,
    approvedby             text,
    approvedat             timestamptz,
    createdat              timestamptz  NOT NULL DEFAULT now(),
    updatedat              timestamptz
);

CREATE INDEX IF NOT EXISTS ix_hotelcustomerpayments_farmid
    ON public.hotelcustomerpayments(farmid);
CREATE INDEX IF NOT EXISTS ix_hotelcustomerpayments_custid
    ON public.hotelcustomerpayments(hotelcustomerid);

-- =============================================================================
-- STORED PROCEDURES
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- Customer CRUD
-- ─────────────────────────────────────────────────────────────────────────────

-- Insert
CREATE OR REPLACE FUNCTION public.sphotelcustomer_insert(
    p_farmid        text,
    p_customername  text,
    p_customertype  text DEFAULT 'Corporate',
    p_phone         text DEFAULT NULL,
    p_email         text DEFAULT NULL,
    p_address       text DEFAULT NULL,
    p_city          text DEFAULT NULL,
    p_paymenttermdays int DEFAULT 0,
    p_creditlimit   numeric DEFAULT 0,
    p_openingbalance numeric DEFAULT 0,
    p_notes         text DEFAULT NULL,
    p_createdby     text DEFAULT NULL
) RETURNS int AS $$
DECLARE
    v_id int;
BEGIN
    INSERT INTO public.hotelcustomers(
        farmid, customername, customertype, phone, email, address, city,
        paymenttermdays, creditlimit, openingbalance, currentbalance, notes, createdby
    ) VALUES (
        p_farmid, p_customername, p_customertype, p_phone, p_email, p_address, p_city,
        p_paymenttermdays, p_creditlimit, p_openingbalance, p_openingbalance, p_notes, p_createdby
    ) RETURNING hotelcustomerid INTO v_id;

    -- Post opening balance to ledger if non-zero
    IF p_openingbalance <> 0 THEN
        INSERT INTO public.hotelcustomerledger(
            farmid, hotelcustomerid, transactiondate, transactiontype,
            debitamount, creditamount, balanceaftertransaction, description, createdby
        ) VALUES (
            p_farmid, v_id, now(), 'OpeningBalance',
            CASE WHEN p_openingbalance < 0 THEN ABS(p_openingbalance) ELSE 0 END,
            CASE WHEN p_openingbalance > 0 THEN p_openingbalance ELSE 0 END,
            p_openingbalance,
            'Opening balance', p_createdby
        );
    END IF;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Update
CREATE OR REPLACE FUNCTION public.sphotelcustomer_update(
    p_id            int,
    p_farmid        text,
    p_customername  text,
    p_customertype  text DEFAULT 'Corporate',
    p_phone         text DEFAULT NULL,
    p_email         text DEFAULT NULL,
    p_address       text DEFAULT NULL,
    p_city          text DEFAULT NULL,
    p_paymenttermdays int DEFAULT 0,
    p_creditlimit   numeric DEFAULT 0,
    p_notes         text DEFAULT NULL,
    p_isactive      boolean DEFAULT true
) RETURNS void AS $$
BEGIN
    UPDATE public.hotelcustomers SET
        customername    = p_customername,
        customertype    = p_customertype,
        phone           = p_phone,
        email           = p_email,
        address         = p_address,
        city            = p_city,
        paymenttermdays = p_paymenttermdays,
        creditlimit     = p_creditlimit,
        notes           = p_notes,
        isactive        = p_isactive,
        updatedat       = now()
    WHERE hotelcustomerid = p_id AND farmid = p_farmid AND isdeleted = false;
END;
$$ LANGUAGE plpgsql;

-- Soft delete
CREATE OR REPLACE FUNCTION public.sphotelcustomer_delete(
    p_id     int,
    p_farmid text
) RETURNS void AS $$
BEGIN
    UPDATE public.hotelcustomers SET isdeleted = true, updatedat = now()
    WHERE hotelcustomerid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Get all
CREATE OR REPLACE FUNCTION public.sphotelcustomer_getall(
    p_farmid text
) RETURNS TABLE (
    hotelcustomerid   int,
    farmid            text,
    customername      text,
    customertype      text,
    phone             text,
    email             text,
    address           text,
    city              text,
    paymenttermdays   int,
    creditlimit       numeric,
    openingbalance    numeric,
    currentbalance    numeric,
    isactive          boolean,
    notes             text,
    createdby         text,
    createdat         timestamptz,
    updatedat         timestamptz
) AS $$
BEGIN
    RETURN QUERY
    SELECT c.hotelcustomerid, c.farmid, c.customername, c.customertype,
           c.phone, c.email, c.address, c.city, c.paymenttermdays,
           c.creditlimit, c.openingbalance, c.currentbalance,
           c.isactive, c.notes, c.createdby, c.createdat, c.updatedat
    FROM   public.hotelcustomers c
    WHERE  c.farmid = p_farmid AND c.isdeleted = false
    ORDER BY c.customername;
END;
$$ LANGUAGE plpgsql;

-- Get by ID
CREATE OR REPLACE FUNCTION public.sphotelcustomer_getbyid(
    p_id     int,
    p_farmid text
) RETURNS TABLE (
    hotelcustomerid   int,
    farmid            text,
    customername      text,
    customertype      text,
    phone             text,
    email             text,
    address           text,
    city              text,
    paymenttermdays   int,
    creditlimit       numeric,
    openingbalance    numeric,
    currentbalance    numeric,
    isactive          boolean,
    notes             text,
    createdby         text,
    createdat         timestamptz,
    updatedat         timestamptz
) AS $$
BEGIN
    RETURN QUERY
    SELECT c.hotelcustomerid, c.farmid, c.customername, c.customertype,
           c.phone, c.email, c.address, c.city, c.paymenttermdays,
           c.creditlimit, c.openingbalance, c.currentbalance,
           c.isactive, c.notes, c.createdby, c.createdat, c.updatedat
    FROM   public.hotelcustomers c
    WHERE  c.hotelcustomerid = p_id AND c.farmid = p_farmid AND c.isdeleted = false;
END;
$$ LANGUAGE plpgsql;

-- Get customers who owe money
CREATE OR REPLACE FUNCTION public.sphotelcustomer_getowedthem(
    p_farmid text
) RETURNS TABLE (
    hotelcustomerid   int,
    farmid            text,
    customername      text,
    customertype      text,
    phone             text,
    paymenttermdays   int,
    currentbalance    numeric
) AS $$
BEGIN
    RETURN QUERY
    SELECT c.hotelcustomerid, c.farmid, c.customername, c.customertype,
           c.phone, c.paymenttermdays, c.currentbalance
    FROM   public.hotelcustomers c
    WHERE  c.farmid = p_farmid AND c.isdeleted = false AND c.currentbalance > 0
    ORDER BY c.currentbalance DESC;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- Ledger
-- ─────────────────────────────────────────────────────────────────────────────

-- Get ledger for a customer
CREATE OR REPLACE FUNCTION public.sphotelcustomerledger_getforcustomer(
    p_customerid int,
    p_farmid     text
) RETURNS TABLE (
    hotelcustomerledgerid  bigint,
    farmid                 text,
    hotelcustomerid        int,
    transactiondate        timestamptz,
    transactiontype        text,
    invoiceid              int,
    paymentid              int,
    debitamount            numeric,
    creditamount           numeric,
    balanceaftertransaction numeric,
    description            text,
    createdby              text,
    createdat              timestamptz
) AS $$
BEGIN
    RETURN QUERY
    SELECT l.hotelcustomerledgerid, l.farmid, l.hotelcustomerid,
           l.transactiondate, l.transactiontype, l.invoiceid, l.paymentid,
           l.debitamount, l.creditamount, l.balanceaftertransaction,
           l.description, l.createdby, l.createdat
    FROM   public.hotelcustomerledger l
    WHERE  l.hotelcustomerid = p_customerid AND l.farmid = p_farmid
    ORDER BY l.transactiondate, l.hotelcustomerledgerid;
END;
$$ LANGUAGE plpgsql;

-- Post an invoice (charge) to customer ledger
CREATE OR REPLACE FUNCTION public.sphotelcustomer_postinvoice(
    p_farmid       text,
    p_customerid   int,
    p_invoiceid    int,
    p_amount       numeric,
    p_description  text DEFAULT NULL,
    p_createdby    text DEFAULT NULL
) RETURNS void AS $$
DECLARE
    v_bal numeric;
BEGIN
    IF p_amount <= 0 THEN RAISE EXCEPTION 'Invoice amount must be positive'; END IF;

    SELECT currentbalance INTO v_bal FROM public.hotelcustomers
    WHERE hotelcustomerid = p_customerid AND farmid = p_farmid AND isdeleted = false
    FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;

    v_bal := v_bal + p_amount;

    INSERT INTO public.hotelcustomerledger(
        farmid, hotelcustomerid, transactiondate, transactiontype,
        invoiceid, debitamount, creditamount, balanceaftertransaction,
        description, createdby
    ) VALUES (
        p_farmid, p_customerid, now(), 'InvoiceCredit',
        p_invoiceid, 0, p_amount, v_bal,
        COALESCE(p_description, 'Invoice charge'), p_createdby
    );

    UPDATE public.hotelcustomers SET currentbalance = v_bal, updatedat = now()
    WHERE hotelcustomerid = p_customerid AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Post a manual adjustment
CREATE OR REPLACE FUNCTION public.sphotelcustomer_postadjustment(
    p_farmid       text,
    p_customerid   int,
    p_amount       numeric,   -- positive = increase balance (customer owes more), negative = decrease
    p_description  text DEFAULT NULL,
    p_createdby    text DEFAULT NULL
) RETURNS void AS $$
DECLARE
    v_bal numeric;
    v_type text;
BEGIN
    IF p_amount = 0 THEN RAISE EXCEPTION 'Adjustment amount cannot be zero'; END IF;

    SELECT currentbalance INTO v_bal FROM public.hotelcustomers
    WHERE hotelcustomerid = p_customerid AND farmid = p_farmid AND isdeleted = false
    FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;

    v_bal := v_bal + p_amount;

    IF p_amount > 0 THEN
        v_type := 'AdjustmentCredit';
    ELSE
        v_type := 'AdjustmentDebit';
    END IF;

    INSERT INTO public.hotelcustomerledger(
        farmid, hotelcustomerid, transactiondate, transactiontype,
        debitamount, creditamount, balanceaftertransaction,
        description, createdby
    ) VALUES (
        p_farmid, p_customerid, now(), v_type,
        CASE WHEN p_amount < 0 THEN ABS(p_amount) ELSE 0 END,
        CASE WHEN p_amount > 0 THEN p_amount ELSE 0 END,
        v_bal,
        COALESCE(p_description, 'Manual adjustment'), p_createdby
    );

    UPDATE public.hotelcustomers SET currentbalance = v_bal, updatedat = now()
    WHERE hotelcustomerid = p_customerid AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- Payments
-- ─────────────────────────────────────────────────────────────────────────────

-- Insert payment (Draft)
CREATE OR REPLACE FUNCTION public.sphotelcustomerpayment_insert(
    p_farmid           text,
    p_customerid       int,
    p_amount           numeric,
    p_paymentmethod    text DEFAULT 'Cash',
    p_cashaccountid    int  DEFAULT NULL,
    p_reference        text DEFAULT NULL,
    p_linkedinvoiceid  int  DEFAULT NULL,
    p_paymentdate      timestamptz DEFAULT NULL,
    p_notes            text DEFAULT NULL,
    p_createdby        text DEFAULT NULL
) RETURNS int AS $$
DECLARE
    v_id int;
BEGIN
    IF p_amount <= 0 THEN RAISE EXCEPTION 'Payment amount must be positive'; END IF;

    -- Validate customer exists
    IF NOT EXISTS (SELECT 1 FROM public.hotelcustomers
                   WHERE hotelcustomerid = p_customerid AND farmid = p_farmid AND isdeleted = false)
    THEN RAISE EXCEPTION 'Customer not found'; END IF;

    INSERT INTO public.hotelcustomerpayments(
        farmid, hotelcustomerid, paymentdate, amount, paymentmethod,
        hotelcashaccountid, reference, linkedinvoiceid, status, notes, createdby
    ) VALUES (
        p_farmid, p_customerid, COALESCE(p_paymentdate, now()), p_amount, p_paymentmethod,
        p_cashaccountid, p_reference, p_linkedinvoiceid, 'Draft', p_notes, p_createdby
    ) RETURNING hotelcustomerpaymentid INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Approve payment (ATOMIC: update payment + ledger + customer balance + cash)
CREATE OR REPLACE FUNCTION public.sphotelcustomerpayment_approve(
    p_paymentid  int,
    p_farmid     text,
    p_approvedby text DEFAULT NULL
) RETURNS void AS $$
DECLARE
    v_rec       record;
    v_custbal   numeric;
    v_cashbal   numeric;
BEGIN
    -- Fetch payment
    SELECT * INTO v_rec FROM public.hotelcustomerpayments
    WHERE hotelcustomerpaymentid = p_paymentid AND farmid = p_farmid;

    IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
    IF v_rec.status = 'Approved' THEN RETURN; END IF;  -- idempotent
    IF v_rec.status <> 'Draft' THEN RAISE EXCEPTION 'Only Draft payments can be approved'; END IF;

    -- Lock customer row
    SELECT currentbalance INTO v_custbal FROM public.hotelcustomers
    WHERE hotelcustomerid = v_rec.hotelcustomerid AND farmid = p_farmid
    FOR UPDATE;

    v_custbal := v_custbal - v_rec.amount;

    -- 1. Update payment status
    UPDATE public.hotelcustomerpayments SET
        status = 'Approved', approvedby = p_approvedby, approvedat = now(), updatedat = now()
    WHERE hotelcustomerpaymentid = p_paymentid AND farmid = p_farmid;

    -- 2. Insert ledger entry (PaymentDebit reduces balance)
    INSERT INTO public.hotelcustomerledger(
        farmid, hotelcustomerid, transactiondate, transactiontype,
        paymentid, debitamount, creditamount, balanceaftertransaction,
        description, createdby
    ) VALUES (
        p_farmid, v_rec.hotelcustomerid, v_rec.paymentdate, 'PaymentDebit',
        p_paymentid, v_rec.amount, 0, v_custbal,
        COALESCE(v_rec.notes, 'Customer payment'), p_approvedby
    );

    -- 3. Update customer balance
    UPDATE public.hotelcustomers SET currentbalance = v_custbal, updatedat = now()
    WHERE hotelcustomerid = v_rec.hotelcustomerid AND farmid = p_farmid;

    -- 4. If cash account specified, post CashIn
    IF v_rec.hotelcashaccountid IS NOT NULL THEN
        SELECT currentbalance INTO v_cashbal FROM public.hotelcashaccounts
        WHERE hotelcashaccountid = v_rec.hotelcashaccountid AND farmid = p_farmid
        FOR UPDATE;

        v_cashbal := v_cashbal + v_rec.amount;

        INSERT INTO public.hotelcashtransactions(
            farmid, hotelcashaccountid, txntype, amount, balanceafter,
            description, reference, sourcetype, sourceid, createdby
        ) VALUES (
            p_farmid, v_rec.hotelcashaccountid, 'Credit', v_rec.amount, v_cashbal,
            COALESCE(v_rec.notes, 'Customer payment'), v_rec.reference,
            'CustomerPayment', p_paymentid, p_approvedby
        );

        UPDATE public.hotelcashaccounts SET currentbalance = v_cashbal, updatedat = now()
        WHERE hotelcashaccountid = v_rec.hotelcashaccountid AND farmid = p_farmid;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Cancel payment (Draft only)
CREATE OR REPLACE FUNCTION public.sphotelcustomerpayment_cancel(
    p_paymentid int,
    p_farmid    text
) RETURNS void AS $$
DECLARE
    v_status text;
BEGIN
    SELECT status INTO v_status FROM public.hotelcustomerpayments
    WHERE hotelcustomerpaymentid = p_paymentid AND farmid = p_farmid;

    IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
    IF v_status <> 'Draft' THEN RAISE EXCEPTION 'Only Draft payments can be cancelled'; END IF;

    UPDATE public.hotelcustomerpayments SET status = 'Cancelled', updatedat = now()
    WHERE hotelcustomerpaymentid = p_paymentid AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Get payments
CREATE OR REPLACE FUNCTION public.sphotelcustomerpayment_getall(
    p_farmid  text,
    p_status  text DEFAULT NULL
) RETURNS TABLE (
    hotelcustomerpaymentid int,
    farmid                 text,
    hotelcustomerid        int,
    customername           text,
    paymentdate            timestamptz,
    amount                 numeric,
    paymentmethod          text,
    hotelcashaccountid     int,
    reference              text,
    linkedinvoiceid        int,
    status                 text,
    notes                  text,
    createdby              text,
    approvedby             text,
    approvedat             timestamptz,
    createdat              timestamptz,
    updatedat              timestamptz
) AS $$
BEGIN
    RETURN QUERY
    SELECT p.hotelcustomerpaymentid, p.farmid, p.hotelcustomerid,
           c.customername,
           p.paymentdate, p.amount, p.paymentmethod, p.hotelcashaccountid,
           p.reference, p.linkedinvoiceid, p.status, p.notes,
           p.createdby, p.approvedby, p.approvedat, p.createdat, p.updatedat
    FROM   public.hotelcustomerpayments p
    JOIN   public.hotelcustomers c ON c.hotelcustomerid = p.hotelcustomerid
    WHERE  p.farmid = p_farmid
      AND  (p_status IS NULL OR p.status = p_status)
    ORDER BY p.createdat DESC;
END;
$$ LANGUAGE plpgsql;

-- Get payment by ID
CREATE OR REPLACE FUNCTION public.sphotelcustomerpayment_getbyid(
    p_paymentid int,
    p_farmid    text
) RETURNS TABLE (
    hotelcustomerpaymentid int,
    farmid                 text,
    hotelcustomerid        int,
    customername           text,
    paymentdate            timestamptz,
    amount                 numeric,
    paymentmethod          text,
    hotelcashaccountid     int,
    reference              text,
    linkedinvoiceid        int,
    status                 text,
    notes                  text,
    createdby              text,
    approvedby             text,
    approvedat             timestamptz,
    createdat              timestamptz,
    updatedat              timestamptz
) AS $$
BEGIN
    RETURN QUERY
    SELECT p.hotelcustomerpaymentid, p.farmid, p.hotelcustomerid,
           c.customername,
           p.paymentdate, p.amount, p.paymentmethod, p.hotelcashaccountid,
           p.reference, p.linkedinvoiceid, p.status, p.notes,
           p.createdby, p.approvedby, p.approvedat, p.createdat, p.updatedat
    FROM   public.hotelcustomerpayments p
    JOIN   public.hotelcustomers c ON c.hotelcustomerid = p.hotelcustomerid
    WHERE  p.hotelcustomerpaymentid = p_paymentid AND p.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Customer balance summary
CREATE OR REPLACE FUNCTION public.sphotelcustomer_balancesummary(
    p_farmid text
) RETURNS TABLE (
    totalcustomers    int,
    customersowing    int,
    totalbalance      numeric,
    totaloverduecount int
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*)::int,
        COUNT(*) FILTER (WHERE c.currentbalance > 0)::int,
        COALESCE(SUM(c.currentbalance) FILTER (WHERE c.currentbalance > 0), 0),
        0::int  -- overdue count placeholder
    FROM   public.hotelcustomers c
    WHERE  c.farmid = p_farmid AND c.isdeleted = false;
END;
$$ LANGUAGE plpgsql;

COMMIT;
