-- =============================================================================
-- Migration 494 — Generic Invoice Documents
-- Branch: emma
--
-- Creates the invoice-document layer on top of existing genericsales.
-- An invoice document is a formal billing record that references an
-- authoritative posted Sale. It does NOT create revenue, inventory, or
-- cash — the Sale already did that.
--
-- Tables:
--   genericinvoicesettings   — per-company invoice configuration
--   genericinvoicedocuments  — the invoice document itself
--   genericinvoicehistory    — audit trail for invoice lifecycle events
--
-- Stored procedures:
--   spgenericinvoicesettings_get       — read company invoice settings
--   spgenericinvoicesettings_save      — upsert company invoice settings
--   spgenericinvoicenumber_next        — concurrency-safe next invoice number
--   spgenericinvoicedocument_generate  — create invoice from posted sale
--   spgenericinvoicedocument_get       — get one invoice with sale details
--   spgenericinvoicedocument_getall    — list invoices with filters
--   spgenericinvoicedocument_issue     — approve/issue a draft invoice
--   spgenericinvoicedocument_void      — void an issued invoice
--   spgenericinvoicedocument_updatedraft — edit a draft invoice
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. genericinvoicesettings — per-company invoice configuration
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericinvoicesettings (
    farmid                          text        NOT NULL PRIMARY KEY,
    invoiceprefix                   text        NOT NULL DEFAULT 'INV',
    nextnumber                      integer     NOT NULL DEFAULT 1,
    defaultpaymentterms             text        NOT NULL DEFAULT 'DueImmediately',
    paymentinstructions             text,
    footernotes                     text,
    termsandconditions              text,
    autogenerateinvoiceaftersale    boolean     NOT NULL DEFAULT FALSE,
    autosendinvoiceafterissuance    boolean     NOT NULL DEFAULT FALSE,
    createdat                       timestamp   NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updatedat                       timestamp
);

-- ---------------------------------------------------------------------------
-- 2. genericinvoicedocuments — the invoice document record
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericinvoicedocuments (
    genericinvoicedocumentid    serial      PRIMARY KEY,
    farmid                      text        NOT NULL,
    genericsaleid               integer     NOT NULL REFERENCES genericsales (genericsaleid),
    invoicenumber               text        NOT NULL,
    issuedate                   date        NOT NULL DEFAULT CURRENT_DATE,
    duedate                     date,
    paymentterms                text        NOT NULL DEFAULT 'DueImmediately',
    documentstatus              text        NOT NULL DEFAULT 'Draft',
    -- Customer billing snapshot (frozen at generation time)
    customerbillingname         text,
    customerbillingaddress      text,
    customerbillingemail        text,
    customerbillingphone        text,
    -- Optional references
    paymentinstructions         text,
    footernotes                 text,
    termsandconditions          text,
    purchaseorderreference      text,
    deliveryreference           text,
    genericprojectid            integer,
    -- Versioning
    version                     integer     NOT NULL DEFAULT 1,
    supersededby                integer     REFERENCES genericinvoicedocuments (genericinvoicedocumentid),
    -- Void tracking
    voidedby                    text,
    voidedat                    timestamp,
    voidreason                  text,
    -- Issuance tracking
    issuedby                    text,
    issuedat                    timestamp,
    -- Metadata
    createdby                   text,
    createdat                   timestamp   NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updatedat                   timestamp,
    isdeleted                   boolean     NOT NULL DEFAULT FALSE,

    -- One active (non-voided, non-superseded, non-deleted) invoice per sale
    CONSTRAINT uq_invoicedocument_active_sale
        UNIQUE (farmid, genericsaleid)
        -- Partial unique index below handles the real constraint;
        -- this full unique is a fallback for simpler checks.
);

-- Drop the full unique constraint and replace with a partial one
-- that only enforces uniqueness for active documents.
ALTER TABLE genericinvoicedocuments
    DROP CONSTRAINT IF EXISTS uq_invoicedocument_active_sale;

CREATE UNIQUE INDEX IF NOT EXISTS ux_invoicedocument_active_sale
    ON genericinvoicedocuments (farmid, genericsaleid)
    WHERE documentstatus NOT IN ('Voided', 'Superseded') AND isdeleted = FALSE;

-- Company-scoped unique invoice numbers
CREATE UNIQUE INDEX IF NOT EXISTS ux_invoicedocument_number
    ON genericinvoicedocuments (farmid, invoicenumber)
    WHERE isdeleted = FALSE;

CREATE INDEX IF NOT EXISTS ix_invoicedocument_farmid
    ON genericinvoicedocuments (farmid);

CREATE INDEX IF NOT EXISTS ix_invoicedocument_customer
    ON genericinvoicedocuments (farmid, customerbillingname);

CREATE INDEX IF NOT EXISTS ix_invoicedocument_status
    ON genericinvoicedocuments (farmid, documentstatus);

CREATE INDEX IF NOT EXISTS ix_invoicedocument_duedate
    ON genericinvoicedocuments (farmid, duedate)
    WHERE documentstatus = 'Issued' AND isdeleted = FALSE;

-- ---------------------------------------------------------------------------
-- 3. genericinvoicehistory — audit trail
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS genericinvoicehistory (
    genericinvoicehistoryid     serial      PRIMARY KEY,
    farmid                      text        NOT NULL,
    genericinvoicedocumentid    integer     NOT NULL REFERENCES genericinvoicedocuments (genericinvoicedocumentid),
    genericsaleid               integer,
    genericprojectid            integer,
    action                      text        NOT NULL,
    previousvalue               text,
    newvalue                    text,
    userid                      text,
    createdat                   timestamp   NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE INDEX IF NOT EXISTS ix_invoicehistory_document
    ON genericinvoicehistory (genericinvoicedocumentid);

CREATE INDEX IF NOT EXISTS ix_invoicehistory_farmid
    ON genericinvoicehistory (farmid);

-- ==========================================================================
-- STORED PROCEDURES
-- ==========================================================================

-- ---------------------------------------------------------------------------
-- spgenericinvoicesettings_get — read company invoice settings
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinvoicesettings_get(p_farmid text)
RETURNS TABLE(
    farmid                          text,
    invoiceprefix                   text,
    nextnumber                      integer,
    defaultpaymentterms             text,
    paymentinstructions             text,
    footernotes                     text,
    termsandconditions              text,
    autogenerateinvoiceaftersale    boolean,
    autosendinvoiceafterissuance    boolean)
LANGUAGE sql
STABLE
AS $function$
    SELECT COALESCE(s.farmid, p_farmid),
           COALESCE(s.invoiceprefix, 'INV'),
           COALESCE(s.nextnumber, 1),
           COALESCE(s.defaultpaymentterms, 'DueImmediately'),
           s.paymentinstructions,
           s.footernotes,
           s.termsandconditions,
           COALESCE(s.autogenerateinvoiceaftersale, FALSE),
           COALESCE(s.autosendinvoiceafterissuance, FALSE)
    FROM   (SELECT 1) AS dummy
    LEFT   JOIN genericinvoicesettings s ON s.farmid = p_farmid;
$function$;

-- ---------------------------------------------------------------------------
-- spgenericinvoicesettings_save — upsert company invoice settings
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinvoicesettings_save(
    p_farmid                        text,
    p_invoiceprefix                 text,
    p_defaultpaymentterms           text,
    p_paymentinstructions           text,
    p_footernotes                   text,
    p_termsandconditions            text,
    p_autogenerateinvoiceaftersale  boolean,
    p_autosendinvoiceafterissuance  boolean)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO genericinvoicesettings (
        farmid, invoiceprefix, defaultpaymentterms,
        paymentinstructions, footernotes, termsandconditions,
        autogenerateinvoiceaftersale, autosendinvoiceafterissuance, updatedat)
    VALUES (
        p_farmid, COALESCE(p_invoiceprefix, 'INV'), COALESCE(p_defaultpaymentterms, 'DueImmediately'),
        p_paymentinstructions, p_footernotes, p_termsandconditions,
        COALESCE(p_autogenerateinvoiceaftersale, FALSE),
        COALESCE(p_autosendinvoiceafterissuance, FALSE),
        now() AT TIME ZONE 'utc')
    ON CONFLICT (farmid) DO UPDATE SET
        invoiceprefix                  = EXCLUDED.invoiceprefix,
        defaultpaymentterms            = EXCLUDED.defaultpaymentterms,
        paymentinstructions            = EXCLUDED.paymentinstructions,
        footernotes                    = EXCLUDED.footernotes,
        termsandconditions             = EXCLUDED.termsandconditions,
        autogenerateinvoiceaftersale   = EXCLUDED.autogenerateinvoiceaftersale,
        autosendinvoiceafterissuance   = EXCLUDED.autosendinvoiceafterissuance,
        updatedat                      = EXCLUDED.updatedat;
END;
$function$;

-- ---------------------------------------------------------------------------
-- spgenericinvoicenumber_next — concurrency-safe next invoice number
--
-- Uses advisory lock keyed on farmid hash to prevent race conditions.
-- Returns formatted invoice number like "INV-2026-000001".
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinvoicenumber_next(p_farmid text)
RETURNS text
LANGUAGE plpgsql
AS $function$
DECLARE
    v_prefix text;
    v_num    integer;
    v_year   text := EXTRACT(YEAR FROM CURRENT_DATE)::text;
BEGIN
    -- Advisory lock scoped to this farm (hash the farmid)
    PERFORM pg_advisory_xact_lock(hashtext('invoice_seq_' || p_farmid));

    -- Ensure a settings row exists
    INSERT INTO genericinvoicesettings (farmid)
    VALUES (p_farmid)
    ON CONFLICT (farmid) DO NOTHING;

    -- Read and increment atomically
    UPDATE genericinvoicesettings
    SET    nextnumber = nextnumber + 1,
           updatedat  = now() AT TIME ZONE 'utc'
    WHERE  farmid = p_farmid
    RETURNING invoiceprefix, nextnumber - 1
    INTO v_prefix, v_num;

    RETURN v_prefix || '-' || v_year || '-' || LPAD(v_num::text, 6, '0');
END;
$function$;

-- ---------------------------------------------------------------------------
-- spgenericinvoicedocument_generate — create invoice from posted sale
--
-- Validates:
--   - Sale exists, belongs to farm, is Approved, not deleted
--   - No active invoice document already exists for this sale
-- Creates the invoice document with customer snapshot and company defaults.
-- Returns the new genericinvoicedocumentid.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinvoicedocument_generate(
    p_farmid        text,
    p_saleid        integer,
    p_duedate       date        DEFAULT NULL,
    p_paymentterms  text        DEFAULT NULL,
    p_poref         text        DEFAULT NULL,
    p_deliveryref   text        DEFAULT NULL,
    p_notes         text        DEFAULT NULL,
    p_createdby     text        DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_sale          record;
    v_customer      record;
    v_settings      record;
    v_invoicenumber text;
    v_duedate       date;
    v_projectid     integer;
    v_docid         integer;
BEGIN
    -- 1. Validate the sale
    SELECT s.genericsaleid, s.farmid, s.status, s.isdeleted,
           s.genericcustomerid, s.saledate, s.totalamount,
           s.genericsubscriptionid, s.duedate AS saleduedate
    INTO   v_sale
    FROM   genericsales s
    WHERE  s.genericsaleid = p_saleid AND s.farmid = p_farmid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sale % not found for this company.', p_saleid;
    END IF;

    IF COALESCE(v_sale.isdeleted, FALSE) THEN
        RAISE EXCEPTION 'Sale % has been deleted and cannot be invoiced.', p_saleid;
    END IF;

    IF v_sale.status <> 'Approved' THEN
        RAISE EXCEPTION 'Only approved sales can be invoiced. Sale % is "%".', p_saleid, v_sale.status;
    END IF;

    -- 2. Check for existing active invoice
    IF EXISTS (
        SELECT 1 FROM genericinvoicedocuments
        WHERE  farmid = p_farmid AND genericsaleid = p_saleid
        AND    documentstatus NOT IN ('Voided', 'Superseded')
        AND    isdeleted = FALSE
    ) THEN
        RAISE EXCEPTION 'An active invoice already exists for sale %. Use the existing invoice or void it first.', p_saleid;
    END IF;

    -- 3. Get customer snapshot
    SELECT c.customername, c.address, c.email, c.phonenumber
    INTO   v_customer
    FROM   genericcustomers c
    WHERE  c.genericcustomerid = v_sale.genericcustomerid
    AND    c.farmid = p_farmid;

    -- 4. Get company invoice settings
    SELECT s.invoiceprefix, s.defaultpaymentterms,
           s.paymentinstructions, s.footernotes, s.termsandconditions
    INTO   v_settings
    FROM   spgenericinvoicesettings_get(p_farmid) s;

    -- 5. Generate invoice number (concurrency-safe)
    v_invoicenumber := spgenericinvoicenumber_next(p_farmid);

    -- 6. Calculate due date
    -- Priority: explicit param > sale's duedate > payment terms calculation
    IF p_duedate IS NOT NULL THEN
        v_duedate := p_duedate;
    ELSIF v_sale.saleduedate IS NOT NULL THEN
        v_duedate := v_sale.saleduedate;
    ELSE
        v_duedate := CASE COALESCE(p_paymentterms, v_settings.defaultpaymentterms)
            WHEN 'DueImmediately' THEN CURRENT_DATE
            WHEN 'Net7'           THEN CURRENT_DATE + 7
            WHEN 'Net14'          THEN CURRENT_DATE + 14
            WHEN 'Net30'          THEN CURRENT_DATE + 30
            WHEN 'Net45'          THEN CURRENT_DATE + 45
            WHEN 'Net60'          THEN CURRENT_DATE + 60
            ELSE CURRENT_DATE
        END;
    END IF;

    -- 7. Find project attribution from sale items (first non-null project)
    SELECT si.genericprojectid INTO v_projectid
    FROM   genericsaleitems si
    WHERE  si.genericsaleid = p_saleid AND si.genericprojectid IS NOT NULL
    LIMIT  1;

    -- 8. Insert the invoice document
    INSERT INTO genericinvoicedocuments (
        farmid, genericsaleid, invoicenumber, issuedate, duedate,
        paymentterms, documentstatus,
        customerbillingname, customerbillingaddress,
        customerbillingemail, customerbillingphone,
        paymentinstructions, footernotes, termsandconditions,
        purchaseorderreference, deliveryreference,
        genericprojectid, createdby)
    VALUES (
        p_farmid, p_saleid, v_invoicenumber, CURRENT_DATE, v_duedate,
        COALESCE(p_paymentterms, v_settings.defaultpaymentterms), 'Draft',
        v_customer.customername, v_customer.address,
        v_customer.email, v_customer.phonenumber,
        COALESCE(p_notes, v_settings.paymentinstructions),
        v_settings.footernotes, v_settings.termsandconditions,
        p_poref, p_deliveryref,
        v_projectid, p_createdby)
    RETURNING genericinvoicedocumentid INTO v_docid;

    -- 9. Audit
    INSERT INTO genericinvoicehistory (
        farmid, genericinvoicedocumentid, genericsaleid,
        genericprojectid, action, newvalue, userid)
    VALUES (
        p_farmid, v_docid, p_saleid,
        v_projectid, 'InvoiceCreated',
        v_invoicenumber || ' for sale #' || p_saleid, p_createdby);

    RETURN v_docid;
END;
$function$;

-- ---------------------------------------------------------------------------
-- spgenericinvoicedocument_get — get one invoice with sale + line details
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinvoicedocument_get(
    p_farmid    text,
    p_docid     integer)
RETURNS TABLE(
    genericinvoicedocumentid    integer,
    farmid                      text,
    genericsaleid               integer,
    invoicenumber               text,
    issuedate                   date,
    duedate                     date,
    paymentterms                text,
    documentstatus              text,
    customerbillingname         text,
    customerbillingaddress      text,
    customerbillingemail        text,
    customerbillingphone        text,
    paymentinstructions         text,
    footernotes                 text,
    termsandconditions          text,
    purchaseorderreference      text,
    deliveryreference           text,
    genericprojectid            integer,
    projectname                 text,
    version                     integer,
    voidedby                    text,
    voidedat                    timestamp,
    voidreason                  text,
    issuedby                    text,
    issuedat                    timestamp,
    createdby                   text,
    createdat                   timestamp,
    -- Sale fields
    salereceiptnumber           text,
    saledate                    timestamp,
    salestype                   text,
    subtotalamount              numeric,
    discountamount              numeric,
    taxamount                   numeric,
    totalamount                 numeric,
    amountpaid                  numeric,
    balance                     numeric,
    paymentstatus               text,
    salestatus                  text,
    -- Derived
    isoverdue                   boolean,
    daysuntildue                integer)
LANGUAGE sql
STABLE
AS $function$
    SELECT d.genericinvoicedocumentid, d.farmid, d.genericsaleid,
           d.invoicenumber, d.issuedate, d.duedate,
           d.paymentterms, d.documentstatus,
           d.customerbillingname, d.customerbillingaddress,
           d.customerbillingemail, d.customerbillingphone,
           d.paymentinstructions, d.footernotes, d.termsandconditions,
           d.purchaseorderreference, d.deliveryreference,
           d.genericprojectid,
           p.name::text,
           d.version,
           d.voidedby, d.voidedat, d.voidreason,
           d.issuedby, d.issuedat,
           d.createdby, d.createdat,
           -- Sale
           s.receiptnumber::text, s.saledate,
           s.salestype::text,
           s.subtotalamount, s.discountamount, s.taxamount,
           s.totalamount, s.amountpaid, s.balance,
           s.paymentstatus::text, s.status::text,
           -- Derived
           (d.documentstatus = 'Issued' AND s.balance > 0
            AND d.duedate IS NOT NULL AND d.duedate < CURRENT_DATE),
           (d.duedate - CURRENT_DATE)::integer
    FROM   genericinvoicedocuments d
    JOIN   genericsales s ON s.genericsaleid = d.genericsaleid
    LEFT   JOIN genericprojects p ON p.genericprojectid = d.genericprojectid
    WHERE  d.genericinvoicedocumentid = p_docid
    AND    d.farmid = p_farmid
    AND    d.isdeleted = FALSE;
$function$;

-- ---------------------------------------------------------------------------
-- spgenericinvoicedocument_getbysale — get invoice document for a sale
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinvoicedocument_getbysale(
    p_farmid    text,
    p_saleid    integer)
RETURNS TABLE(
    genericinvoicedocumentid    integer,
    invoicenumber               text,
    documentstatus              text,
    issuedate                   date,
    duedate                     date)
LANGUAGE sql
STABLE
AS $function$
    SELECT d.genericinvoicedocumentid, d.invoicenumber,
           d.documentstatus, d.issuedate, d.duedate
    FROM   genericinvoicedocuments d
    WHERE  d.farmid = p_farmid
    AND    d.genericsaleid = p_saleid
    AND    d.documentstatus NOT IN ('Voided', 'Superseded')
    AND    d.isdeleted = FALSE
    LIMIT  1;
$function$;

-- ---------------------------------------------------------------------------
-- spgenericinvoicedocument_getall — list invoices with filters
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinvoicedocument_getall(
    p_farmid            text,
    p_documentstatus    text        DEFAULT NULL,
    p_paymentstatus     text        DEFAULT NULL,
    p_customerid        integer     DEFAULT NULL,
    p_projectid         integer     DEFAULT NULL,
    p_from              date        DEFAULT NULL,
    p_to                date        DEFAULT NULL,
    p_overdueonly       boolean     DEFAULT FALSE)
RETURNS TABLE(
    genericinvoicedocumentid    integer,
    genericsaleid               integer,
    invoicenumber               text,
    issuedate                   date,
    duedate                     date,
    paymentterms                text,
    documentstatus              text,
    customerbillingname         text,
    genericprojectid            integer,
    projectname                 text,
    -- Sale financials (live, not snapshot)
    salereceiptnumber           text,
    totalamount                 numeric,
    amountpaid                  numeric,
    balance                     numeric,
    paymentstatus               text,
    -- Derived
    isoverdue                   boolean,
    daysuntildue                integer,
    createdat                   timestamp)
LANGUAGE sql
STABLE
AS $function$
    SELECT d.genericinvoicedocumentid, d.genericsaleid,
           d.invoicenumber, d.issuedate, d.duedate,
           d.paymentterms, d.documentstatus,
           d.customerbillingname,
           d.genericprojectid,
           p.name::text,
           s.receiptnumber::text,
           s.totalamount, s.amountpaid, s.balance,
           s.paymentstatus::text,
           -- Overdue: only Issued documents with unpaid balance past due
           (d.documentstatus = 'Issued' AND s.balance > 0
            AND d.duedate IS NOT NULL AND d.duedate < CURRENT_DATE),
           (d.duedate - CURRENT_DATE)::integer,
           d.createdat
    FROM   genericinvoicedocuments d
    JOIN   genericsales s ON s.genericsaleid = d.genericsaleid
    LEFT   JOIN genericprojects p ON p.genericprojectid = d.genericprojectid
    WHERE  d.farmid = p_farmid
    AND    d.isdeleted = FALSE
    AND    (p_documentstatus IS NULL OR p_documentstatus = 'All'
            OR d.documentstatus = p_documentstatus)
    AND    (p_paymentstatus IS NULL OR p_paymentstatus = 'All'
            OR s.paymentstatus = p_paymentstatus)
    AND    (p_customerid IS NULL
            OR s.genericcustomerid = p_customerid)
    AND    (p_projectid IS NULL
            OR d.genericprojectid = p_projectid)
    AND    (p_from IS NULL OR d.issuedate >= p_from)
    AND    (p_to   IS NULL OR d.issuedate <= p_to)
    AND    (NOT p_overdueonly
            OR (d.documentstatus = 'Issued' AND s.balance > 0
                AND d.duedate IS NOT NULL AND d.duedate < CURRENT_DATE))
    ORDER  BY d.issuedate DESC, d.genericinvoicedocumentid DESC;
$function$;

-- ---------------------------------------------------------------------------
-- spgenericinvoicedocument_issue — issue (approve) a draft invoice
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinvoicedocument_issue(
    p_farmid    text,
    p_docid     integer,
    p_issuedby  text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_doc   record;
    v_now   timestamp := now() AT TIME ZONE 'utc';
BEGIN
    SELECT d.genericinvoicedocumentid, d.documentstatus, d.genericsaleid,
           d.invoicenumber, d.genericprojectid
    INTO   v_doc
    FROM   genericinvoicedocuments d
    WHERE  d.genericinvoicedocumentid = p_docid
    AND    d.farmid = p_farmid
    AND    d.isdeleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice document % not found.', p_docid;
    END IF;

    IF v_doc.documentstatus <> 'Draft' THEN
        RAISE EXCEPTION 'Only draft invoices can be issued. This invoice is "%".', v_doc.documentstatus;
    END IF;

    UPDATE genericinvoicedocuments
    SET    documentstatus = 'Issued',
           issuedby       = p_issuedby,
           issuedat       = v_now,
           updatedat      = v_now
    WHERE  genericinvoicedocumentid = p_docid;

    INSERT INTO genericinvoicehistory (
        farmid, genericinvoicedocumentid, genericsaleid,
        genericprojectid, action, previousvalue, newvalue, userid)
    VALUES (
        p_farmid, p_docid, v_doc.genericsaleid,
        v_doc.genericprojectid, 'InvoiceIssued',
        'Draft', 'Issued', p_issuedby);
END;
$function$;

-- ---------------------------------------------------------------------------
-- spgenericinvoicedocument_void — void an issued invoice
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinvoicedocument_void(
    p_farmid    text,
    p_docid     integer,
    p_reason    text,
    p_voidedby  text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_doc   record;
    v_now   timestamp := now() AT TIME ZONE 'utc';
BEGIN
    IF COALESCE(BTRIM(p_reason), '') = '' THEN
        RAISE EXCEPTION 'A reason is required to void an invoice.';
    END IF;

    SELECT d.genericinvoicedocumentid, d.documentstatus, d.genericsaleid,
           d.invoicenumber, d.genericprojectid
    INTO   v_doc
    FROM   genericinvoicedocuments d
    WHERE  d.genericinvoicedocumentid = p_docid
    AND    d.farmid = p_farmid
    AND    d.isdeleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice document % not found.', p_docid;
    END IF;

    IF v_doc.documentstatus NOT IN ('Draft', 'Issued') THEN
        RAISE EXCEPTION 'Cannot void a "%" invoice.', v_doc.documentstatus;
    END IF;

    UPDATE genericinvoicedocuments
    SET    documentstatus = 'Voided',
           voidedby       = p_voidedby,
           voidedat       = v_now,
           voidreason     = p_reason,
           updatedat      = v_now
    WHERE  genericinvoicedocumentid = p_docid;

    INSERT INTO genericinvoicehistory (
        farmid, genericinvoicedocumentid, genericsaleid,
        genericprojectid, action, previousvalue, newvalue, userid)
    VALUES (
        p_farmid, p_docid, v_doc.genericsaleid,
        v_doc.genericprojectid, 'InvoiceVoided',
        v_doc.documentstatus, 'Voided: ' || p_reason, p_voidedby);
END;
$function$;

-- ---------------------------------------------------------------------------
-- spgenericinvoicedocument_updatedraft — edit a draft invoice
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinvoicedocument_updatedraft(
    p_farmid        text,
    p_docid         integer,
    p_duedate       date        DEFAULT NULL,
    p_paymentterms  text        DEFAULT NULL,
    p_poref         text        DEFAULT NULL,
    p_deliveryref   text        DEFAULT NULL,
    p_notes         text        DEFAULT NULL,
    p_footernotes   text        DEFAULT NULL,
    p_terms         text        DEFAULT NULL,
    p_updatedby     text        DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_doc   record;
    v_now   timestamp := now() AT TIME ZONE 'utc';
BEGIN
    SELECT d.genericinvoicedocumentid, d.documentstatus, d.genericsaleid,
           d.genericprojectid
    INTO   v_doc
    FROM   genericinvoicedocuments d
    WHERE  d.genericinvoicedocumentid = p_docid
    AND    d.farmid = p_farmid
    AND    d.isdeleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice document % not found.', p_docid;
    END IF;

    IF v_doc.documentstatus <> 'Draft' THEN
        RAISE EXCEPTION 'Only draft invoices can be edited. This invoice is "%".', v_doc.documentstatus;
    END IF;

    UPDATE genericinvoicedocuments
    SET    duedate                 = COALESCE(p_duedate, duedate),
           paymentterms            = COALESCE(p_paymentterms, paymentterms),
           purchaseorderreference  = COALESCE(p_poref, purchaseorderreference),
           deliveryreference       = COALESCE(p_deliveryref, deliveryreference),
           paymentinstructions     = COALESCE(p_notes, paymentinstructions),
           footernotes             = COALESCE(p_footernotes, footernotes),
           termsandconditions      = COALESCE(p_terms, termsandconditions),
           updatedat               = v_now
    WHERE  genericinvoicedocumentid = p_docid;

    INSERT INTO genericinvoicehistory (
        farmid, genericinvoicedocumentid, genericsaleid,
        genericprojectid, action, userid)
    VALUES (
        p_farmid, p_docid, v_doc.genericsaleid,
        v_doc.genericprojectid, 'DraftUpdated', p_updatedby);
END;
$function$;

-- ---------------------------------------------------------------------------
-- spgenericinvoicedocument_getsalelines — get sale line items for an invoice
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinvoicedocument_getsalelines(
    p_farmid    text,
    p_saleid    integer)
RETURNS TABLE(
    genericsaleitemid   integer,
    itemtype            text,
    genericproductid    integer,
    genericserviceid    integer,
    productname         text,
    servicename         text,
    description         text,
    quantity            numeric,
    unitname            text,
    unitprice           numeric,
    discountamount      numeric,
    taxamount           numeric,
    linetotal           numeric,
    genericprojectid    integer)
LANGUAGE sql
STABLE
AS $function$
    SELECT si.genericsaleitemid,
           si.itemtype::text,
           si.genericproductid, si.genericserviceid,
           pr.productname::text,
           sv.servicename::text,
           COALESCE(si.description, pr.productname, sv.servicename)::text,
           si.quantity,
           COALESCE(si.saleunit, 'unit')::text,
           si.unitprice, si.discountamount,
           0::numeric,
           si.linetotal,
           NULL::integer
    FROM   genericsaleitems si
    LEFT   JOIN genericproducts pr ON pr.genericproductid = si.genericproductid
    LEFT   JOIN genericservices sv ON sv.genericserviceid = si.genericserviceid
    WHERE  si.genericsaleid = p_saleid
    AND    EXISTS (SELECT 1 FROM genericsales s
                   WHERE s.genericsaleid = p_saleid AND s.farmid = p_farmid)
    ORDER  BY si.genericsaleitemid;
$function$;

-- ---------------------------------------------------------------------------
-- spgenericinvoicedocument_gethistory — audit history for an invoice
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericinvoicedocument_gethistory(
    p_farmid    text,
    p_docid     integer)
RETURNS TABLE(
    genericinvoicehistoryid     integer,
    action                      text,
    previousvalue               text,
    newvalue                    text,
    userid                      text,
    createdat                   timestamp)
LANGUAGE sql
STABLE
AS $function$
    SELECT h.genericinvoicehistoryid, h.action,
           h.previousvalue, h.newvalue,
           h.userid, h.createdat
    FROM   genericinvoicehistory h
    WHERE  h.genericinvoicedocumentid = p_docid
    AND    h.farmid = p_farmid
    ORDER  BY h.createdat DESC;
$function$;

-- ==========================================================================
-- VERIFICATION
-- ==========================================================================

-- Tables exist
SELECT 'tables' AS check,
       (SELECT COUNT(*) FROM information_schema.tables
        WHERE table_schema = 'public'
        AND   table_name IN ('genericinvoicesettings', 'genericinvoicedocuments', 'genericinvoicehistory')) AS found,
       3 AS expected;

-- Functions exist
SELECT 'functions' AS check,
       (SELECT COUNT(*) FROM pg_proc
        WHERE proname IN (
            'spgenericinvoicesettings_get', 'spgenericinvoicesettings_save',
            'spgenericinvoicenumber_next',
            'spgenericinvoicedocument_generate', 'spgenericinvoicedocument_get',
            'spgenericinvoicedocument_getbysale', 'spgenericinvoicedocument_getall',
            'spgenericinvoicedocument_issue', 'spgenericinvoicedocument_void',
            'spgenericinvoicedocument_updatedraft',
            'spgenericinvoicedocument_getsalelines',
            'spgenericinvoicedocument_gethistory')) AS found,
       12 AS expected;

-- No data corruption: existing tables untouched
SELECT 'no_data_change' AS check,
       (SELECT COUNT(*) FROM genericinvoicedocuments) AS invoice_docs,
       0 AS expected;
