-- =============================================================================
-- 321_HotelSupplierBalances.postgres.sql
--
-- Purpose
-- -------
-- Supplier (creditor) balance tracking for the Hotel module.
--
-- Tables created
-- --------------
--   hotelsuppliers          supplier master records
--   hotelsupplierledger     immutable debit/credit ledger
--   hotelsupplierpayments   payment workflow (Draft -> Approved -> Cancelled)
--
-- Convention: CurrentBalance > 0 means we OWE the supplier.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. hotelsuppliers
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotelsuppliers (
    hotelsupplierid        serial       PRIMARY KEY,
    farmid                 text         NOT NULL,
    suppliername           text         NOT NULL,
    suppliertype           text         NOT NULL DEFAULT 'ProductSupplier',
    phone                  text,
    email                  text,
    location               text,
    address                text,
    paymenttermdays        int          NOT NULL DEFAULT 0,
    openingbalance         numeric(14,2) NOT NULL DEFAULT 0,
    currentbalance         numeric(14,2) NOT NULL DEFAULT 0,
    isactive               boolean      NOT NULL DEFAULT true,
    isdeleted              boolean      NOT NULL DEFAULT false,
    notes                  text,
    createdby              text,
    createdat              timestamptz  NOT NULL DEFAULT now(),
    updatedat              timestamptz
);

CREATE INDEX IF NOT EXISTS ix_hotelsuppliers_farmid ON public.hotelsuppliers(farmid);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. hotelsupplierledger
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotelsupplierledger (
    hotelsupplierledgerid  bigserial    PRIMARY KEY,
    farmid                 text         NOT NULL,
    hotelsupplierid        int          NOT NULL REFERENCES public.hotelsuppliers(hotelsupplierid),
    transactiondate        timestamptz  NOT NULL DEFAULT now(),
    transactiontype        text         NOT NULL,
    expenseid              int,
    paymentid              int,
    debitamount            numeric(14,2) NOT NULL DEFAULT 0,
    creditamount           numeric(14,2) NOT NULL DEFAULT 0,
    balanceaftertransaction numeric(14,2) NOT NULL DEFAULT 0,
    description            text,
    createdby              text,
    createdat              timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT ck_hotelsuppledger_oneleg CHECK (
        (debitamount > 0 AND creditamount = 0) OR (debitamount = 0 AND creditamount > 0)
    )
);

CREATE INDEX IF NOT EXISTS ix_hotelsupplierledger_farmid ON public.hotelsupplierledger(farmid);
CREATE INDEX IF NOT EXISTS ix_hotelsupplierledger_suppid ON public.hotelsupplierledger(hotelsupplierid);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. hotelsupplierpayments
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotelsupplierpayments (
    hotelsupplierpaymentid serial       PRIMARY KEY,
    farmid                 text         NOT NULL,
    hotelsupplierid        int          NOT NULL REFERENCES public.hotelsuppliers(hotelsupplierid),
    paymentdate            timestamptz  NOT NULL DEFAULT now(),
    amount                 numeric(14,2) NOT NULL CHECK (amount > 0),
    paymentmethod          text         NOT NULL DEFAULT 'Cash',
    hotelcashaccountid     int,
    reference              text,
    linkedexpenseid        int,
    status                 text         NOT NULL DEFAULT 'Draft',
    notes                  text,
    createdby              text,
    approvedby             text,
    approvedat             timestamptz,
    createdat              timestamptz  NOT NULL DEFAULT now(),
    updatedat              timestamptz
);

CREATE INDEX IF NOT EXISTS ix_hotelsupplierpayments_farmid ON public.hotelsupplierpayments(farmid);

-- =============================================================================
-- STORED PROCEDURES
-- =============================================================================

-- ── Supplier CRUD ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.sphotelsupplier_insert(
    p_farmid text, p_name text, p_type text DEFAULT 'ProductSupplier',
    p_phone text DEFAULT NULL, p_email text DEFAULT NULL, p_location text DEFAULT NULL,
    p_address text DEFAULT NULL, p_termdays int DEFAULT 0, p_opening numeric DEFAULT 0,
    p_notes text DEFAULT NULL, p_createdby text DEFAULT NULL
) RETURNS int AS $$
DECLARE v_id int;
BEGIN
    INSERT INTO public.hotelsuppliers(farmid, suppliername, suppliertype, phone, email, location, address, paymenttermdays, openingbalance, currentbalance, notes, createdby)
    VALUES (p_farmid, p_name, p_type, p_phone, p_email, p_location, p_address, p_termdays, p_opening, p_opening, p_notes, p_createdby)
    RETURNING hotelsupplierid INTO v_id;

    IF p_opening <> 0 THEN
        INSERT INTO public.hotelsupplierledger(farmid, hotelsupplierid, transactiondate, transactiontype,
            debitamount, creditamount, balanceaftertransaction, description, createdby)
        VALUES (p_farmid, v_id, now(), 'OpeningBalance',
            CASE WHEN p_opening < 0 THEN ABS(p_opening) ELSE 0 END,
            CASE WHEN p_opening > 0 THEN p_opening ELSE 0 END,
            p_opening, 'Opening balance', p_createdby);
    END IF;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.sphotelsupplier_update(
    p_id int, p_farmid text, p_name text, p_type text DEFAULT 'ProductSupplier',
    p_phone text DEFAULT NULL, p_email text DEFAULT NULL, p_location text DEFAULT NULL,
    p_address text DEFAULT NULL, p_termdays int DEFAULT 0, p_notes text DEFAULT NULL,
    p_isactive boolean DEFAULT true
) RETURNS void AS $$
BEGIN
    UPDATE public.hotelsuppliers SET suppliername=p_name, suppliertype=p_type, phone=p_phone, email=p_email,
        location=p_location, address=p_address, paymenttermdays=p_termdays, notes=p_notes, isactive=p_isactive, updatedat=now()
    WHERE hotelsupplierid=p_id AND farmid=p_farmid AND isdeleted=false;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.sphotelsupplier_delete(p_id int, p_farmid text) RETURNS void AS $$
BEGIN UPDATE public.hotelsuppliers SET isdeleted=true, updatedat=now() WHERE hotelsupplierid=p_id AND farmid=p_farmid; END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.sphotelsupplier_getall(p_farmid text)
RETURNS TABLE (hotelsupplierid int, farmid text, suppliername text, suppliertype text, phone text, email text,
    location text, address text, paymenttermdays int, openingbalance numeric, currentbalance numeric,
    isactive boolean, notes text, createdby text, createdat timestamptz, updatedat timestamptz) AS $$
BEGIN
    RETURN QUERY SELECT s.hotelsupplierid, s.farmid, s.suppliername, s.suppliertype, s.phone, s.email,
        s.location, s.address, s.paymenttermdays, s.openingbalance, s.currentbalance,
        s.isactive, s.notes, s.createdby, s.createdat, s.updatedat
    FROM public.hotelsuppliers s WHERE s.farmid=p_farmid AND s.isdeleted=false ORDER BY s.suppliername;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.sphotelsupplier_getbyid(p_id int, p_farmid text)
RETURNS TABLE (hotelsupplierid int, farmid text, suppliername text, suppliertype text, phone text, email text,
    location text, address text, paymenttermdays int, openingbalance numeric, currentbalance numeric,
    isactive boolean, notes text, createdby text, createdat timestamptz, updatedat timestamptz) AS $$
BEGIN
    RETURN QUERY SELECT s.hotelsupplierid, s.farmid, s.suppliername, s.suppliertype, s.phone, s.email,
        s.location, s.address, s.paymenttermdays, s.openingbalance, s.currentbalance,
        s.isactive, s.notes, s.createdby, s.createdat, s.updatedat
    FROM public.hotelsuppliers s WHERE s.hotelsupplierid=p_id AND s.farmid=p_farmid AND s.isdeleted=false;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.sphotelsupplier_getowedtothem(p_farmid text)
RETURNS TABLE (hotelsupplierid int, farmid text, suppliername text, suppliertype text, phone text, paymenttermdays int, currentbalance numeric) AS $$
BEGIN
    RETURN QUERY SELECT s.hotelsupplierid, s.farmid, s.suppliername, s.suppliertype, s.phone, s.paymenttermdays, s.currentbalance
    FROM public.hotelsuppliers s WHERE s.farmid=p_farmid AND s.isdeleted=false AND s.currentbalance>0 ORDER BY s.currentbalance DESC;
END;
$$ LANGUAGE plpgsql;

-- ── Ledger ───────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.sphotelsupplierledger_getforsupplier(p_supplierid int, p_farmid text)
RETURNS TABLE (hotelsupplierledgerid bigint, farmid text, hotelsupplierid int, transactiondate timestamptz,
    transactiontype text, expenseid int, paymentid int, debitamount numeric, creditamount numeric,
    balanceaftertransaction numeric, description text, createdby text, createdat timestamptz) AS $$
BEGIN
    RETURN QUERY SELECT l.hotelsupplierledgerid, l.farmid, l.hotelsupplierid, l.transactiondate, l.transactiontype,
        l.expenseid, l.paymentid, l.debitamount, l.creditamount, l.balanceaftertransaction,
        l.description, l.createdby, l.createdat
    FROM public.hotelsupplierledger l WHERE l.hotelsupplierid=p_supplierid AND l.farmid=p_farmid
    ORDER BY l.transactiondate, l.hotelsupplierledgerid;
END;
$$ LANGUAGE plpgsql;

-- Post expense to supplier ledger (increases balance)
CREATE OR REPLACE FUNCTION public.sphotelsupplier_postexpense(
    p_farmid text, p_supplierid int, p_expenseid int, p_amount numeric, p_description text DEFAULT NULL, p_createdby text DEFAULT NULL
) RETURNS void AS $$
DECLARE v_bal numeric;
BEGIN
    IF p_amount <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;
    SELECT currentbalance INTO v_bal FROM public.hotelsuppliers WHERE hotelsupplierid=p_supplierid AND farmid=p_farmid AND isdeleted=false FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Supplier not found'; END IF;
    v_bal := v_bal + p_amount;
    INSERT INTO public.hotelsupplierledger(farmid, hotelsupplierid, transactiondate, transactiontype, expenseid, debitamount, creditamount, balanceaftertransaction, description, createdby)
    VALUES (p_farmid, p_supplierid, now(), 'ExpenseCredit', p_expenseid, 0, p_amount, v_bal, COALESCE(p_description, 'Expense charge'), p_createdby);
    UPDATE public.hotelsuppliers SET currentbalance=v_bal, updatedat=now() WHERE hotelsupplierid=p_supplierid AND farmid=p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Post adjustment
CREATE OR REPLACE FUNCTION public.sphotelsupplier_postadjustment(
    p_farmid text, p_supplierid int, p_amount numeric, p_description text DEFAULT NULL, p_createdby text DEFAULT NULL
) RETURNS void AS $$
DECLARE v_bal numeric; v_type text;
BEGIN
    IF p_amount = 0 THEN RAISE EXCEPTION 'Amount cannot be zero'; END IF;
    SELECT currentbalance INTO v_bal FROM public.hotelsuppliers WHERE hotelsupplierid=p_supplierid AND farmid=p_farmid AND isdeleted=false FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Supplier not found'; END IF;
    v_bal := v_bal + p_amount;
    v_type := CASE WHEN p_amount > 0 THEN 'AdjustmentCredit' ELSE 'AdjustmentDebit' END;
    INSERT INTO public.hotelsupplierledger(farmid, hotelsupplierid, transactiondate, transactiontype, debitamount, creditamount, balanceaftertransaction, description, createdby)
    VALUES (p_farmid, p_supplierid, now(), v_type,
        CASE WHEN p_amount < 0 THEN ABS(p_amount) ELSE 0 END,
        CASE WHEN p_amount > 0 THEN p_amount ELSE 0 END,
        v_bal, COALESCE(p_description, 'Manual adjustment'), p_createdby);
    UPDATE public.hotelsuppliers SET currentbalance=v_bal, updatedat=now() WHERE hotelsupplierid=p_supplierid AND farmid=p_farmid;
END;
$$ LANGUAGE plpgsql;

-- ── Payments ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.sphotelsupplierpayment_insert(
    p_farmid text, p_supplierid int, p_amount numeric, p_method text DEFAULT 'Cash',
    p_cashaccountid int DEFAULT NULL, p_reference text DEFAULT NULL, p_linkedexpenseid int DEFAULT NULL,
    p_paymentdate timestamptz DEFAULT NULL, p_notes text DEFAULT NULL, p_createdby text DEFAULT NULL
) RETURNS int AS $$
DECLARE v_id int;
BEGIN
    IF p_amount <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.hotelsuppliers WHERE hotelsupplierid=p_supplierid AND farmid=p_farmid AND isdeleted=false)
    THEN RAISE EXCEPTION 'Supplier not found'; END IF;
    INSERT INTO public.hotelsupplierpayments(farmid, hotelsupplierid, paymentdate, amount, paymentmethod, hotelcashaccountid, reference, linkedexpenseid, status, notes, createdby)
    VALUES (p_farmid, p_supplierid, COALESCE(p_paymentdate, now()), p_amount, p_method, p_cashaccountid, p_reference, p_linkedexpenseid, 'Draft', p_notes, p_createdby)
    RETURNING hotelsupplierpaymentid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.sphotelsupplierpayment_approve(p_paymentid int, p_farmid text, p_approvedby text DEFAULT NULL) RETURNS void AS $$
DECLARE v_rec record; v_suppbal numeric; v_cashbal numeric;
BEGIN
    SELECT * INTO v_rec FROM public.hotelsupplierpayments WHERE hotelsupplierpaymentid=p_paymentid AND farmid=p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
    IF v_rec.status = 'Approved' THEN RETURN; END IF;
    IF v_rec.status <> 'Draft' THEN RAISE EXCEPTION 'Only Draft payments can be approved'; END IF;

    SELECT currentbalance INTO v_suppbal FROM public.hotelsuppliers WHERE hotelsupplierid=v_rec.hotelsupplierid AND farmid=p_farmid FOR UPDATE;
    v_suppbal := v_suppbal - v_rec.amount;

    UPDATE public.hotelsupplierpayments SET status='Approved', approvedby=p_approvedby, approvedat=now(), updatedat=now()
    WHERE hotelsupplierpaymentid=p_paymentid AND farmid=p_farmid;

    INSERT INTO public.hotelsupplierledger(farmid, hotelsupplierid, transactiondate, transactiontype, paymentid, debitamount, creditamount, balanceaftertransaction, description, createdby)
    VALUES (p_farmid, v_rec.hotelsupplierid, v_rec.paymentdate, 'PaymentDebit', p_paymentid, v_rec.amount, 0, v_suppbal, COALESCE(v_rec.notes, 'Supplier payment'), p_approvedby);

    UPDATE public.hotelsuppliers SET currentbalance=v_suppbal, updatedat=now() WHERE hotelsupplierid=v_rec.hotelsupplierid AND farmid=p_farmid;

    IF v_rec.hotelcashaccountid IS NOT NULL THEN
        SELECT currentbalance INTO v_cashbal FROM public.hotelcashaccounts WHERE hotelcashaccountid=v_rec.hotelcashaccountid AND farmid=p_farmid FOR UPDATE;
        v_cashbal := v_cashbal - v_rec.amount;
        INSERT INTO public.hotelcashtransactions(farmid, hotelcashaccountid, txntype, amount, balanceafter, description, reference, sourcetype, sourceid, createdby)
        VALUES (p_farmid, v_rec.hotelcashaccountid, 'Debit', v_rec.amount, v_cashbal, COALESCE(v_rec.notes, 'Supplier payment'), v_rec.reference, 'SupplierPayment', p_paymentid, p_approvedby);
        UPDATE public.hotelcashaccounts SET currentbalance=v_cashbal, updatedat=now() WHERE hotelcashaccountid=v_rec.hotelcashaccountid AND farmid=p_farmid;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.sphotelsupplierpayment_cancel(p_paymentid int, p_farmid text) RETURNS void AS $$
DECLARE v_status text;
BEGIN
    SELECT status INTO v_status FROM public.hotelsupplierpayments WHERE hotelsupplierpaymentid=p_paymentid AND farmid=p_farmid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found'; END IF;
    IF v_status <> 'Draft' THEN RAISE EXCEPTION 'Only Draft payments can be cancelled'; END IF;
    UPDATE public.hotelsupplierpayments SET status='Cancelled', updatedat=now() WHERE hotelsupplierpaymentid=p_paymentid AND farmid=p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.sphotelsupplierpayment_getall(p_farmid text, p_status text DEFAULT NULL)
RETURNS TABLE (hotelsupplierpaymentid int, farmid text, hotelsupplierid int, suppliername text,
    paymentdate timestamptz, amount numeric, paymentmethod text, hotelcashaccountid int, reference text,
    linkedexpenseid int, status text, notes text, createdby text, approvedby text, approvedat timestamptz,
    createdat timestamptz, updatedat timestamptz) AS $$
BEGIN
    RETURN QUERY SELECT p.hotelsupplierpaymentid, p.farmid, p.hotelsupplierid, s.suppliername,
        p.paymentdate, p.amount, p.paymentmethod, p.hotelcashaccountid, p.reference, p.linkedexpenseid,
        p.status, p.notes, p.createdby, p.approvedby, p.approvedat, p.createdat, p.updatedat
    FROM public.hotelsupplierpayments p JOIN public.hotelsuppliers s ON s.hotelsupplierid=p.hotelsupplierid
    WHERE p.farmid=p_farmid AND (p_status IS NULL OR p.status=p_status) ORDER BY p.createdat DESC;
END;
$$ LANGUAGE plpgsql;

-- Summary
CREATE OR REPLACE FUNCTION public.sphotelsupplier_balancesummary(p_farmid text)
RETURNS TABLE (totalsuppliers int, suppliersowed int, totalbalance numeric) AS $$
BEGIN
    RETURN QUERY SELECT COUNT(*)::int, COUNT(*) FILTER (WHERE s.currentbalance>0)::int,
        COALESCE(SUM(s.currentbalance) FILTER (WHERE s.currentbalance>0), 0)
    FROM public.hotelsuppliers s WHERE s.farmid=p_farmid AND s.isdeleted=false;
END;
$$ LANGUAGE plpgsql;

COMMIT;
