-- =============================================================================
-- 476_GenericSaleUnitsAndCredit.postgres.sql
--
-- 1. Sale items get saleunit + unitfactor (like purchases have purchaseunit +
--    unitfactor from 472). Stock deduction uses quantity * unitfactor.
-- 2. Sales get an applycreditamount column so the frontend can request explicit
--    credit application. The approve SP validates ownership and balance with
--    SELECT FOR UPDATE to prevent concurrent credit spending.
-- 3. The approve SP is updated for unit-factor stock deduction.
-- 4. The insert SP and reader are updated for the new columns.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- =============================================================================
-- 1. Schema: add saleunit + unitfactor to genericsaleitems
-- =============================================================================

ALTER TABLE genericsaleitems ADD COLUMN IF NOT EXISTS saleunit VARCHAR(50) NULL;
ALTER TABLE genericsaleitems ADD COLUMN IF NOT EXISTS unitfactor NUMERIC(14, 4) NOT NULL DEFAULT 1;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_genericsaleitems_unitfactor') THEN
        ALTER TABLE genericsaleitems
            ADD CONSTRAINT ck_genericsaleitems_unitfactor CHECK (unitfactor > 0);
    END IF;
END $$;

-- Add applycreditamount to genericsales header
ALTER TABLE genericsales ADD COLUMN IF NOT EXISTS applycreditamount NUMERIC(14,2) NOT NULL DEFAULT 0;

-- =============================================================================
-- 2. Rewrite spgenericsale_insert — accept saleunit, unitfactor, applycreditamount
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spgenericsale_insert(
    p_farmid text,
    p_saledate timestamp DEFAULT NULL,
    p_genericcustomerid integer DEFAULT NULL,
    p_branchid integer DEFAULT NULL,
    p_salestype text DEFAULT 'WalkInSale',
    p_saleschannel text DEFAULT NULL,
    p_salespersonstaffid integer DEFAULT NULL,
    p_headerdiscountamount numeric DEFAULT 0,
    p_taxamount numeric DEFAULT 0,
    p_amountpaid numeric DEFAULT 0,
    p_paymentmethod text DEFAULT NULL,
    p_genericcashaccountid integer DEFAULT NULL,
    p_receiptnumber text DEFAULT NULL,
    p_notes text DEFAULT NULL,
    p_createdby text DEFAULT NULL,
    p_items jsonb DEFAULT NULL,
    p_applycreditamount numeric DEFAULT 0)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_subtotal  numeric;
    v_total     numeric;
    v_balance   numeric;
    v_paystatus text;
    v_newid     integer;
BEGIN
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Sale must have at least one item.';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_items) AS it(quantity numeric)
               WHERE it.quantity <= 0) THEN
        RAISE EXCEPTION 'Item quantity must be greater than zero.';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_items) AS it(unitprice numeric)
               WHERE it.unitprice < 0) THEN
        RAISE EXCEPTION 'Item unit price cannot be negative.';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_items) AS it(unitfactor numeric)
               WHERE it.unitfactor IS NOT NULL AND it.unitfactor <= 0) THEN
        RAISE EXCEPTION 'Unit conversion factor must be greater than zero.';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_items) AS it(itemtype text)
               WHERE it.itemtype NOT IN ('Product', 'Service')) THEN
        RAISE EXCEPTION 'Item type must be Product or Service.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_to_recordset(p_items) AS it(itemtype text, genericproductid integer, genericserviceid integer)
        WHERE (it.itemtype = 'Product' AND it.genericproductid IS NULL)
           OR (it.itemtype = 'Service' AND it.genericserviceid IS NULL)) THEN
        RAISE EXCEPTION 'Product items need GenericProductId; service items need GenericServiceId.';
    END IF;

    SELECT COALESCE(SUM(it.quantity * it.unitprice - COALESCE(it.discountamount, 0)), 0)
    INTO   v_subtotal
    FROM   jsonb_to_recordset(p_items) AS it(quantity numeric, unitprice numeric, discountamount numeric);

    v_total   := v_subtotal - COALESCE(p_headerdiscountamount, 0) + COALESCE(p_taxamount, 0);
    v_balance := v_total - COALESCE(p_amountpaid, 0) - COALESCE(p_applycreditamount, 0);
    v_paystatus :=
        CASE
            WHEN (COALESCE(p_amountpaid, 0) + COALESCE(p_applycreditamount, 0)) = 0 THEN 'Unpaid'
            WHEN (COALESCE(p_amountpaid, 0) + COALESCE(p_applycreditamount, 0)) >= v_total THEN 'Paid'
            ELSE 'Partial'
        END;

    INSERT INTO genericsales (
        farmid, saledate, genericcustomerid, branchid, salestype, saleschannel,
        salespersonstaffid, subtotalamount, discountamount, taxamount,
        totalamount, amountpaid, balance, paymentstatus, paymentmethod,
        genericcashaccountid, receiptnumber, status, notes, createdby,
        applycreditamount
    )
    VALUES (
        p_farmid, COALESCE(p_saledate, (now() at time zone 'utc')), p_genericcustomerid, p_branchid,
        p_salestype, p_saleschannel, p_salespersonstaffid,
        v_subtotal, COALESCE(p_headerdiscountamount, 0), COALESCE(p_taxamount, 0),
        v_total, COALESCE(p_amountpaid, 0), GREATEST(v_balance, 0), v_paystatus, p_paymentmethod,
        p_genericcashaccountid, p_receiptnumber, 'Draft', p_notes, p_createdby,
        COALESCE(p_applycreditamount, 0)
    )
    RETURNING genericsaleid INTO v_newid;

    INSERT INTO genericsaleitems (
        genericsaleid, farmid, itemtype, genericproductid, genericserviceid,
        description, quantity, unitprice, discountamount, costamount, notes,
        saleunit, unitfactor
    )
    SELECT v_newid, p_farmid, it.itemtype, it.genericproductid, it.genericserviceid,
           it.description, it.quantity, it.unitprice, COALESCE(it.discountamount, 0),
           it.costamount, it.notes,
           NULLIF(btrim(it.saleunit), ''), COALESCE(it.unitfactor, 1)
    FROM   jsonb_to_recordset(p_items) AS it(
               itemtype text, genericproductid integer, genericserviceid integer,
               description text, quantity numeric, unitprice numeric,
               discountamount numeric, costamount numeric, notes text,
               saleunit text, unitfactor numeric);

    RETURN v_newid;
END;
$function$;

-- =============================================================================
-- 3. Rewrite spgenericsale_approve — unit-factor stock + explicit credit
-- =============================================================================

CREATE OR REPLACE FUNCTION public.spgenericsale_approve(
    p_genericsaleid integer,
    p_farmid text,
    p_approvedby text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_customerid integer;
    v_cashaccountid integer;
    v_amountpaid numeric;
    v_balance numeric;
    v_totalamount numeric;
    v_saledate timestamp;
    v_receiptnumber text;
    v_paymentmethod text;
    v_applycreditamount numeric;
    v_cashnewbalance numeric := NULL;
    v_cashallowneg boolean;
    v_cashcurrent numeric;
    v_customernewbalance numeric;
    v_customerbalance numeric;
    v_paymentid integer;
    v_now timestamp := (now() at time zone 'utc');
BEGIN
    -- Idempotent
    IF EXISTS (SELECT 1 FROM genericsales s
               WHERE s.genericsaleid = p_genericsaleid AND s.farmid = p_farmid
                 AND s.status = 'Approved') THEN
        RETURN;
    END IF;

    SELECT s.status, s.genericcustomerid, s.genericcashaccountid,
           s.amountpaid, s.balance, s.totalamount, s.saledate,
           s.receiptnumber, s.paymentmethod,
           COALESCE(s.applycreditamount, 0)
    INTO   v_status, v_customerid, v_cashaccountid,
           v_amountpaid, v_balance, v_totalamount, v_saledate,
           v_receiptnumber, v_paymentmethod, v_applycreditamount
    FROM   genericsales s
    WHERE  s.genericsaleid = p_genericsaleid AND s.farmid = p_farmid
       AND s.isdeleted = FALSE
    LIMIT 1;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Sale % not found.', p_genericsaleid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Sale cannot be approved from status %.', v_status;
    END IF;
    IF (v_amountpaid > 0 AND v_cashaccountid IS NULL) THEN
        RAISE EXCEPTION 'AmountPaid is greater than zero but no GenericCashAccountId is set.';
    END IF;
    -- Recalculate balance including credit
    v_balance := GREATEST(v_totalamount - v_amountpaid - v_applycreditamount, 0);
    IF (v_balance > 0 AND v_customerid IS NULL) THEN
        RAISE EXCEPTION 'Sale has an unpaid balance but no customer is attached (credit sales require a customer).';
    END IF;

    -- Credit pre-flight: pessimistic lock on customer to prevent double-spend
    IF (v_applycreditamount > 0) THEN
        IF v_customerid IS NULL THEN
            RAISE EXCEPTION 'Cannot apply credit without a customer.';
        END IF;
        SELECT c.currentbalance INTO v_customerbalance
        FROM   genericcustomers c
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid
        FOR UPDATE;  -- lock the row

        IF v_customerbalance IS NULL THEN
            RAISE EXCEPTION 'Customer not found.';
        END IF;
        -- Credit = negative balance; available = ABS of negative portion
        IF v_customerbalance >= 0 THEN
            RAISE EXCEPTION 'Customer has no credit available (balance: %).', v_customerbalance;
        END IF;
        IF v_applycreditamount > ABS(v_customerbalance) THEN
            RAISE EXCEPTION 'Credit requested (%) exceeds available credit (%).', v_applycreditamount, ABS(v_customerbalance);
        END IF;
    END IF;

    -- Stock pre-flight (using unitfactor for base-unit check)
    IF EXISTS (
        SELECT 1
        FROM   genericsaleitems i
        INNER  JOIN genericproducts p
            ON p.genericproductid = i.genericproductid AND p.farmid = p_farmid
        WHERE  i.genericsaleid = p_genericsaleid
           AND i.itemtype = 'Product'
           AND p.trackinventory = TRUE
           AND p.currentstock - (i.quantity * i.unitfactor) < 0
    ) THEN
        RAISE EXCEPTION 'Insufficient stock for one or more products on this sale.';
    END IF;

    -- Cash pre-flight
    IF (v_amountpaid > 0) THEN
        SELECT ca.allownegativebalance, ca.currentbalance
        INTO   v_cashallowneg, v_cashcurrent
        FROM   genericcashaccounts ca
        WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid
        LIMIT 1;

        IF v_cashcurrent IS NULL THEN
            RAISE EXCEPTION 'Cash account on the sale does not exist or belongs to another farm.';
        END IF;
        v_cashnewbalance := v_cashcurrent + v_amountpaid;
    END IF;

    -- =========================================================================
    -- TRANSACTION BODY
    -- =========================================================================

    -- 1. Mark sale approved, update balance to reflect credit
    UPDATE genericsales s
    SET    status = 'Approved', approvedby = p_approvedby,
           approvedat = v_now, updatedat = v_now,
           balance = v_balance,
           paymentstatus = CASE
               WHEN (v_amountpaid + v_applycreditamount) >= v_totalamount THEN 'Paid'
               WHEN (v_amountpaid + v_applycreditamount) > 0 THEN 'Partial'
               ELSE 'Unpaid'
           END
    WHERE  s.genericsaleid = p_genericsaleid AND s.farmid = p_farmid;

    -- 2. Inventory: SaleOut in BASE units (quantity * unitfactor)
    INSERT INTO genericstockmovements (
        farmid, genericproductid, movementdate, movementtype, quantity,
        unitcost, unitsellingprice, totalcostvalue, referencetype, referenceid,
        reason, createdby, approvedby, approvedat
    )
    SELECT p_farmid, i.genericproductid, v_saledate, 'SaleOut',
           -(i.quantity * i.unitfactor),  -- base units
           p.costprice,
           i.unitprice / i.unitfactor,    -- base-unit selling price
           p.costprice * i.quantity * i.unitfactor,  -- total cost in base units
           'Sale', p_genericsaleid,
           'Sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text)
               || CASE WHEN i.saleunit IS NOT NULL AND i.unitfactor <> 1
                       THEN ' (' || trim(to_char(i.quantity, 'FM999999999990.###')) || ' ' || i.saleunit || ')'
                       ELSE '' END,
           p_approvedby, p_approvedby, v_now
    FROM   genericsaleitems i
    INNER  JOIN genericproducts p
        ON p.genericproductid = i.genericproductid AND p.farmid = p_farmid
    WHERE  i.genericsaleid = p_genericsaleid
       AND i.itemtype = 'Product'
       AND p.trackinventory = TRUE;

    UPDATE genericproducts p
    SET    currentstock = p.currentstock - x.qty,
           updatedat    = v_now
    FROM   (SELECT i.genericproductid, SUM(i.quantity * i.unitfactor) AS qty
            FROM   genericsaleitems i
            WHERE  i.genericsaleid = p_genericsaleid AND i.farmid = p_farmid
              AND  i.itemtype = 'Product'
            GROUP  BY i.genericproductid) x
    WHERE  x.genericproductid = p.genericproductid
       AND p.trackinventory = TRUE
       AND p.farmid = p_farmid;

    -- 3. Customer side: SaleDebit for FULL TotalAmount (accrual revenue)
    IF (v_customerid IS NOT NULL AND v_totalamount > 0) THEN
        SELECT c.currentbalance INTO v_customerbalance
        FROM   genericcustomers c
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

        v_customernewbalance := v_customerbalance + v_totalamount;

        INSERT INTO genericcustomerledger (
            farmid, genericcustomerid, transactiondate, transactiontype,
            saleid, debitamount, creditamount, balanceaftertransaction,
            description, createdby
        )
        VALUES (
            p_farmid, v_customerid, v_saledate, 'SaleDebit',
            p_genericsaleid, v_totalamount, 0, v_customernewbalance,
            'Sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby
        );

        UPDATE genericcustomers c
        SET    currentbalance = v_customernewbalance, updatedat = v_now
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;
    END IF;

    -- 4. Auto-create customer payment for AmountPaid (unified payment path)
    IF (v_amountpaid > 0) THEN
        INSERT INTO genericcustomerpayments (
            farmid, genericcustomerid, paymentdate, amount, paymentmethod,
            genericcashaccountid, linkedsaleid, status, notes, createdby,
            paymentgroupid
        )
        VALUES (
            p_farmid, COALESCE(v_customerid, 0), v_saledate, v_amountpaid,
            COALESCE(v_paymentmethod, 'Cash'), v_cashaccountid, p_genericsaleid,
            'Approved',
            'Payment on sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby, gen_random_uuid()
        )
        RETURNING genericcustomerpaymentid INTO v_paymentid;

        -- Customer ledger: PaymentCredit
        IF (v_customerid IS NOT NULL) THEN
            SELECT c.currentbalance INTO v_customerbalance
            FROM   genericcustomers c
            WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

            v_customernewbalance := v_customerbalance - v_amountpaid;

            INSERT INTO genericcustomerledger (
                farmid, genericcustomerid, transactiondate, transactiontype,
                paymentid, debitamount, creditamount, balanceaftertransaction,
                description, createdby
            )
            VALUES (
                p_farmid, v_customerid, v_saledate, 'PaymentCredit',
                v_paymentid, 0, v_amountpaid, v_customernewbalance,
                'Payment on sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
                p_approvedby
            );

            UPDATE genericcustomers c
            SET    currentbalance = v_customernewbalance, updatedat = v_now
            WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;
        END IF;

        -- Cash side: CashIn
        INSERT INTO genericcashtransactions (
            farmid, genericcashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, balanceaftertransaction, description,
            createdby, approvedby, approvedat
        )
        VALUES (
            p_farmid, v_cashaccountid, v_saledate, 'CashIn',
            'CustomerPayment', v_paymentid, v_amountpaid, v_cashnewbalance,
            'Payment on sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby, p_approvedby, v_now
        );

        UPDATE genericcashaccounts ca
        SET    currentbalance = v_cashnewbalance, updatedat = v_now
        WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid;
    END IF;

    -- 5. Explicit credit application (from form, with pessimistic lock above)
    IF (v_applycreditamount > 0 AND v_customerid IS NOT NULL) THEN
        SELECT c.currentbalance INTO v_customerbalance
        FROM   genericcustomers c
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

        v_customernewbalance := v_customerbalance + v_applycreditamount;

        INSERT INTO genericcustomerledger (
            farmid, genericcustomerid, transactiondate, transactiontype,
            saleid, debitamount, creditamount, balanceaftertransaction,
            description, createdby
        )
        VALUES (
            p_farmid, v_customerid, v_saledate, 'CreditApplied',
            p_genericsaleid, v_applycreditamount, 0, v_customernewbalance,
            'Credit applied to sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby
        );

        UPDATE genericcustomers c
        SET    currentbalance = v_customernewbalance, updatedat = v_now
        WHERE  c.genericcustomerid = v_customerid AND c.farmid = p_farmid;

        INSERT INTO genericcustomercreditapplications (
            farmid, genericcustomerid, genericsaleid, amountapplied,
            applicationdate, description, createdby
        )
        VALUES (
            p_farmid, v_customerid, p_genericsaleid, v_applycreditamount,
            v_saledate,
            'Credit applied to sale ' || COALESCE(v_receiptnumber, p_genericsaleid::text),
            p_approvedby
        );
    END IF;
END
$function$;

-- =============================================================================
-- 4. Update reader to return saleunit + unitfactor
-- =============================================================================

DROP FUNCTION IF EXISTS public.spgenericsale_getbyid_rs2(integer, text);
CREATE FUNCTION public.spgenericsale_getbyid_rs2(p_genericsaleid integer, p_farmid text)
RETURNS TABLE(genericsaleitemid integer, genericsaleid integer, farmid text, itemtype text,
              genericproductid integer, genericserviceid integer, description text,
              quantity numeric, unitprice numeric, discountamount numeric, linetotal numeric,
              costamount numeric, notes text, saleunit text, unitfactor numeric)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT i.genericsaleitemid, i.genericsaleid, i.farmid::text, i.itemtype::text,
           i.genericproductid, i.genericserviceid, i.description::text,
           i.quantity, i.unitprice, i.discountamount, i.linetotal,
           i.costamount, i.notes::text,
           i.saleunit::text, i.unitfactor
    FROM   genericsaleitems i
    WHERE  i.genericsaleid = p_genericsaleid AND i.farmid = p_farmid
    ORDER  BY i.genericsaleitemid;
END
$function$;

COMMIT;

DO $$
BEGIN
    RAISE NOTICE '476: Sale units, credit application, and unit-factor stock deduction deployed.';
END $$;
