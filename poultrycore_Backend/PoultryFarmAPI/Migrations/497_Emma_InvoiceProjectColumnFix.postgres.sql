-- Migration 497 — Fix "column si.genericprojectid does not exist" in invoice generation.
--
-- The generate SP (494) assumed genericsaleitems had a genericprojectid column,
-- but projects are linked through genericprojectallocations (483). This migration
-- fixes the generate SP to look up the project from the allocations table, and
-- also fixes the getsalelines SP to return the actual project allocation per line.

-- ---------------------------------------------------------------------------
-- 1. Fix spgenericinvoicedocument_generate — look up project from allocations
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
    -- 1. Validate the sale exists, is approved, and belongs to this farm
    SELECT s.genericsaleid, s.genericcustomerid, s.saledate,
           s.totalamount, s.amountpaid, s.balance,
           s.status, s.duedate AS saleduedate
    INTO   v_sale
    FROM   genericsales s
    WHERE  s.genericsaleid = p_saleid
    AND    s.farmid = p_farmid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sale #% not found for this company.', p_saleid;
    END IF;
    IF v_sale.status NOT IN ('Approved', 'Posted') THEN
        RAISE EXCEPTION 'Sale #% must be Approved or Posted to generate an invoice (current status: %).', p_saleid, v_sale.status;
    END IF;

    -- 2. Check no active (non-voided) invoice already exists for this sale
    IF EXISTS (SELECT 1 FROM genericinvoicedocuments
               WHERE genericsaleid = p_saleid AND farmid = p_farmid
               AND isdeleted = FALSE AND documentstatus <> 'Voided') THEN
        RAISE EXCEPTION 'An active invoice already exists for sale #%. Void it first to regenerate.', p_saleid;
    END IF;

    -- 3. Get customer details
    SELECT c.customername, c.address, c.email, c.phonenumber
    INTO   v_customer
    FROM   genericcustomers c
    WHERE  c.genericcustomerid = v_sale.genericcustomerid;

    -- 4. Get invoice settings
    SELECT s.defaultpaymentterms, s.paymentinstructions,
           s.footernotes, s.termsandconditions
    INTO   v_settings
    FROM   genericinvoicesettings s
    WHERE  s.farmid = p_farmid;

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

    -- 7. Find project attribution from allocations table (first active allocation)
    SELECT a.genericprojectid INTO v_projectid
    FROM   genericprojectallocations a
    WHERE  a.farmid = p_farmid
    AND    a.sourcetype = 'SaleLine'
    AND    a.sourceid = p_saleid
    AND    a.status = 'Active'
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
    RETURNING genericinvoicedocuments.genericinvoicedocumentid INTO v_docid;

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
-- 2. Fix spgenericinvoicedocument_getsalelines — return actual project per line
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
           a.genericprojectid
    FROM   genericsaleitems si
    LEFT   JOIN genericproducts pr ON pr.genericproductid = si.genericproductid
    LEFT   JOIN genericservices sv ON sv.genericserviceid = si.genericserviceid
    LEFT   JOIN genericprojectallocations a
           ON a.sourcetype = 'SaleLine'
           AND a.sourceid = si.genericsaleid
           AND a.sourcelineid = si.genericsaleitemid
           AND a.status = 'Active'
           AND a.farmid = p_farmid
    WHERE  si.genericsaleid = p_saleid
    AND    EXISTS (SELECT 1 FROM genericsales s
                   WHERE s.genericsaleid = p_saleid AND s.farmid = p_farmid)
    ORDER  BY si.genericsaleitemid;
$function$;
