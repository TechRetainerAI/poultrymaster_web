-- 458. Generic purchases: buy in a unit (bag, rubber, kg ...) and edit a Draft.
--
-- 1. genericpurchaseitems gets purchaseunit (what the line was bought in, e.g. "bag")
--    and unitfactor (how many of the product's base unit one purchase unit holds,
--    e.g. 1 bag = 50 kg -> 50). Old rows: unit NULL, factor 1 = unchanged behaviour.
-- 2. spgenericpurchase_insert stores both.
-- 3. spgenericpurchase_approve stocks quantity * unitfactor in the base unit, at a
--    base-unit cost of unitcost / unitfactor. Bodies re-dumped from the live DB on
--    2026-11-21 before this change; everything else is unchanged.
-- 4. spgenericpurchase_getbyid_rs2 returns the two new columns (drop + create: the
--    RETURNS TABLE shape changes).
-- 5. New spgenericpurchase_update: rewrites header + lines of a Draft purchase only.

ALTER TABLE genericpurchaseitems ADD COLUMN IF NOT EXISTS purchaseunit VARCHAR(50) NULL;
ALTER TABLE genericpurchaseitems ADD COLUMN IF NOT EXISTS unitfactor NUMERIC(14, 4) NOT NULL DEFAULT 1;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_genericpurchaseitems_unitfactor') THEN
        ALTER TABLE genericpurchaseitems
            ADD CONSTRAINT ck_genericpurchaseitems_unitfactor CHECK (unitfactor > 0);
    END IF;
END $$;

-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericpurchase_insert(p_farmid text, p_purchasedate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_genericsupplierid integer DEFAULT NULL::integer, p_branchid integer DEFAULT NULL::integer, p_headerdiscountamount numeric DEFAULT 0, p_taxamount numeric DEFAULT 0, p_amountpaid numeric DEFAULT 0, p_paymentmethod text DEFAULT NULL::text, p_genericcashaccountid integer DEFAULT NULL::integer, p_invoicenumber text DEFAULT NULL::text, p_receipturl text DEFAULT NULL::text, p_receivedbystaffid integer DEFAULT NULL::integer, p_notes text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text, p_items jsonb DEFAULT NULL::jsonb)
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
        RAISE EXCEPTION 'Purchase must have at least one item.';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_items) AS it(quantity numeric)
               WHERE it.quantity <= 0) THEN
        RAISE EXCEPTION 'Item quantity must be greater than zero.';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_items) AS it(unitcost numeric)
               WHERE it.unitcost < 0) THEN
        RAISE EXCEPTION 'Item unit cost cannot be negative.';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_items) AS it(unitfactor numeric)
               WHERE it.unitfactor IS NOT NULL AND it.unitfactor <= 0) THEN
        RAISE EXCEPTION 'Unit conversion factor must be greater than zero.';
    END IF;

    SELECT COALESCE(SUM(it.quantity * it.unitcost - COALESCE(it.discountamount, 0)), 0)
    INTO   v_subtotal
    FROM   jsonb_to_recordset(p_items) AS it(quantity numeric, unitcost numeric, discountamount numeric);

    v_total   := v_subtotal - COALESCE(p_headerdiscountamount, 0) + COALESCE(p_taxamount, 0);
    v_balance := v_total - COALESCE(p_amountpaid, 0);
    v_paystatus :=
        CASE
            WHEN COALESCE(p_amountpaid, 0) = 0 THEN 'Unpaid'
            WHEN p_amountpaid >= v_total       THEN 'Paid'
            ELSE 'Partial'
        END;

    IF (v_balance > 0 AND p_genericsupplierid IS NULL) THEN
        RAISE EXCEPTION 'Credit purchase requires a supplier.';
    END IF;

    INSERT INTO genericpurchases (
        farmid, genericsupplierid, purchasedate, branchid,
        subtotalamount, discountamount, taxamount,
        totalamount, amountpaid, balance, paymentstatus, paymentmethod,
        genericcashaccountid, invoicenumber, receipturl, receivedbystaffid,
        status, notes, createdby
    )
    VALUES (
        p_farmid, p_genericsupplierid, COALESCE(p_purchasedate, (now() at time zone 'utc')), p_branchid,
        v_subtotal, COALESCE(p_headerdiscountamount, 0), COALESCE(p_taxamount, 0),
        v_total, COALESCE(p_amountpaid, 0), v_balance, v_paystatus, p_paymentmethod,
        p_genericcashaccountid, p_invoicenumber, p_receipturl, p_receivedbystaffid,
        'Draft', p_notes, p_createdby
    )
    RETURNING genericpurchaseid INTO v_newid;

    INSERT INTO genericpurchaseitems (
        genericpurchaseid, farmid, genericproductid, description,
        quantity, unitcost, discountamount, notes, purchaseunit, unitfactor
    )
    SELECT v_newid, p_farmid, it.genericproductid, it.description,
           it.quantity, it.unitcost, COALESCE(it.discountamount, 0), it.notes,
           NULLIF(btrim(it.purchaseunit), ''), COALESCE(it.unitfactor, 1)
    FROM   jsonb_to_recordset(p_items) AS it(
               genericproductid integer, description text, quantity numeric,
               unitcost numeric, discountamount numeric, notes text,
               purchaseunit text, unitfactor numeric);

    RETURN v_newid;
END;
$function$;

-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericpurchase_update(p_genericpurchaseid integer, p_farmid text, p_purchasedate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_genericsupplierid integer DEFAULT NULL::integer, p_headerdiscountamount numeric DEFAULT 0, p_taxamount numeric DEFAULT 0, p_amountpaid numeric DEFAULT 0, p_paymentmethod text DEFAULT NULL::text, p_genericcashaccountid integer DEFAULT NULL::integer, p_invoicenumber text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_items jsonb DEFAULT NULL::jsonb)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status    text;
    v_subtotal  numeric;
    v_total     numeric;
    v_balance   numeric;
    v_paystatus text;
BEGIN
    SELECT pu.status INTO v_status
    FROM   genericpurchases pu
    WHERE  pu.genericpurchaseid = p_genericpurchaseid AND pu.farmid = p_farmid AND pu.isdeleted = FALSE
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Purchase % not found.', p_genericpurchaseid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Only a Draft purchase can be edited (this one is %).', v_status;
    END IF;

    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Purchase must have at least one item.';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_items) AS it(quantity numeric)
               WHERE it.quantity <= 0) THEN
        RAISE EXCEPTION 'Item quantity must be greater than zero.';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_items) AS it(unitcost numeric)
               WHERE it.unitcost < 0) THEN
        RAISE EXCEPTION 'Item unit cost cannot be negative.';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_to_recordset(p_items) AS it(unitfactor numeric)
               WHERE it.unitfactor IS NOT NULL AND it.unitfactor <= 0) THEN
        RAISE EXCEPTION 'Unit conversion factor must be greater than zero.';
    END IF;

    SELECT COALESCE(SUM(it.quantity * it.unitcost - COALESCE(it.discountamount, 0)), 0)
    INTO   v_subtotal
    FROM   jsonb_to_recordset(p_items) AS it(quantity numeric, unitcost numeric, discountamount numeric);

    v_total   := v_subtotal - COALESCE(p_headerdiscountamount, 0) + COALESCE(p_taxamount, 0);
    v_balance := v_total - COALESCE(p_amountpaid, 0);
    v_paystatus :=
        CASE
            WHEN COALESCE(p_amountpaid, 0) = 0 THEN 'Unpaid'
            WHEN p_amountpaid >= v_total       THEN 'Paid'
            ELSE 'Partial'
        END;

    IF (v_balance > 0 AND p_genericsupplierid IS NULL) THEN
        RAISE EXCEPTION 'Credit purchase requires a supplier.';
    END IF;

    UPDATE genericpurchases pu
    SET    genericsupplierid    = p_genericsupplierid,
           purchasedate         = COALESCE(p_purchasedate, pu.purchasedate),
           subtotalamount       = v_subtotal,
           discountamount       = COALESCE(p_headerdiscountamount, 0),
           taxamount            = COALESCE(p_taxamount, 0),
           totalamount          = v_total,
           amountpaid           = COALESCE(p_amountpaid, 0),
           balance              = v_balance,
           paymentstatus        = v_paystatus,
           paymentmethod        = p_paymentmethod,
           genericcashaccountid = p_genericcashaccountid,
           invoicenumber        = p_invoicenumber,
           notes                = p_notes,
           updatedat            = (now() at time zone 'utc')
    WHERE  pu.genericpurchaseid = p_genericpurchaseid AND pu.farmid = p_farmid;

    DELETE FROM genericpurchaseitems i
    WHERE  i.genericpurchaseid = p_genericpurchaseid AND i.farmid = p_farmid;

    INSERT INTO genericpurchaseitems (
        genericpurchaseid, farmid, genericproductid, description,
        quantity, unitcost, discountamount, notes, purchaseunit, unitfactor
    )
    SELECT p_genericpurchaseid, p_farmid, it.genericproductid, it.description,
           it.quantity, it.unitcost, COALESCE(it.discountamount, 0), it.notes,
           NULLIF(btrim(it.purchaseunit), ''), COALESCE(it.unitfactor, 1)
    FROM   jsonb_to_recordset(p_items) AS it(
               genericproductid integer, description text, quantity numeric,
               unitcost numeric, discountamount numeric, notes text,
               purchaseunit text, unitfactor numeric);

    RETURN p_genericpurchaseid;
END;
$function$;

-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spgenericpurchase_getbyid_rs2(integer, text);
CREATE FUNCTION public.spgenericpurchase_getbyid_rs2(p_genericpurchaseid integer, p_farmid text)
 RETURNS TABLE(genericpurchaseitemid integer, genericpurchaseid integer, farmid text, genericproductid integer, description text, quantity numeric, unitcost numeric, discountamount numeric, linetotal numeric, notes text, purchaseunit text, unitfactor numeric)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT i.genericpurchaseitemid, i.genericpurchaseid, i.farmid::text, i.genericproductid,
           i.description::text, i.quantity, i.unitcost, i.discountamount, i.linetotal, i.notes::text,
           i.purchaseunit::text, i.unitfactor
    FROM   genericpurchaseitems i
    WHERE  i.genericpurchaseid = p_genericpurchaseid AND i.farmid = p_farmid
    ORDER  BY i.genericpurchaseitemid;
END
$function$;

-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spgenericpurchase_approve(p_genericpurchaseid integer, p_farmid text, p_approvedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
    v_supplierid integer;
    v_cashaccountid integer;
    v_amountpaid numeric;
    v_balance numeric;
    v_purchasedate timestamp;
    v_invoicenumber text;
    v_cashnewbalance numeric := NULL;
    v_cashallowneg boolean;
    v_cashcurrent numeric;
    v_suppliernewbalance numeric;
BEGIN
    IF EXISTS (SELECT 1 FROM genericpurchases pu
               WHERE  pu.genericpurchaseid = p_genericpurchaseid AND pu.farmid = p_farmid
                  AND pu.status = 'Approved') THEN
        RETURN;
    END IF;

    SELECT pu.status, pu.genericsupplierid, pu.genericcashaccountid,
           pu.amountpaid, pu.balance, pu.purchasedate, pu.invoicenumber
    INTO   v_status, v_supplierid, v_cashaccountid,
           v_amountpaid, v_balance, v_purchasedate, v_invoicenumber
    FROM   genericpurchases pu
    WHERE  pu.genericpurchaseid = p_genericpurchaseid AND pu.farmid = p_farmid
       AND pu.isdeleted = FALSE
    LIMIT 1;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Purchase % not found.', p_genericpurchaseid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Purchase cannot be approved from status %.', v_status;
    END IF;
    IF (v_amountpaid > 0 AND v_cashaccountid IS NULL) THEN
        RAISE EXCEPTION 'AmountPaid is greater than zero but no GenericCashAccountId is set.';
    END IF;
    IF (v_balance > 0 AND v_supplierid IS NULL) THEN
        RAISE EXCEPTION 'Purchase has an unpaid balance but no supplier is attached.';
    END IF;

    IF (v_amountpaid > 0) THEN
        SELECT ca.allownegativebalance, ca.currentbalance
        INTO   v_cashallowneg, v_cashcurrent
        FROM   genericcashaccounts ca
        WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid
        LIMIT 1;

        IF v_cashcurrent IS NULL THEN
            RAISE EXCEPTION 'Cash account on the purchase does not exist or belongs to another farm.';
        END IF;
        v_cashnewbalance := v_cashcurrent - v_amountpaid;
        IF (v_cashnewbalance < 0 AND v_cashallowneg = FALSE) THEN
            RAISE EXCEPTION 'Purchase would push cash account negative; account does not allow it.';
        END IF;
    END IF;

    UPDATE genericpurchases pu
    SET    status = 'Approved', approvedby = p_approvedby,
           approvedat = (now() at time zone 'utc'), updatedat = (now() at time zone 'utc')
    WHERE  pu.genericpurchaseid = p_genericpurchaseid AND pu.farmid = p_farmid;

    -- Inventory in the product's base unit: quantity x unitfactor (458).
    INSERT INTO genericstockmovements (
        farmid, genericproductid, movementdate, movementtype, quantity,
        unitcost, totalcostvalue, referencetype, referenceid,
        reason, createdby, approvedby, approvedat
    )
    SELECT p_farmid, i.genericproductid, v_purchasedate, 'PurchaseIn', i.quantity * i.unitfactor,
           i.unitcost / i.unitfactor, i.unitcost * i.quantity, 'Purchase', p_genericpurchaseid,
           'Purchase ' || COALESCE(v_invoicenumber, p_genericpurchaseid::text)
               || CASE WHEN i.purchaseunit IS NOT NULL AND i.unitfactor <> 1
                       THEN ' (' || trim(to_char(i.quantity, 'FM999999999990.###')) || ' ' || i.purchaseunit || ')'
                       ELSE '' END,
           p_approvedby, p_approvedby, (now() at time zone 'utc')
    FROM   genericpurchaseitems i
    INNER  JOIN genericproducts p
        ON p.genericproductid = i.genericproductid AND p.farmid = p_farmid
    WHERE  i.genericpurchaseid = p_genericpurchaseid
       AND p.trackinventory = TRUE;

    UPDATE genericproducts p
    SET    currentstock = p.currentstock + x.qty,
           updatedat    = (now() at time zone 'utc')
    FROM   (SELECT i.genericproductid, SUM(i.quantity * i.unitfactor) AS qty
            FROM   genericpurchaseitems i
            WHERE  i.genericpurchaseid = p_genericpurchaseid AND i.farmid = p_farmid
            GROUP  BY i.genericproductid) x
    WHERE  x.genericproductid = p.genericproductid
       AND p.trackinventory = TRUE
       AND p.farmid = p_farmid;

    IF (v_amountpaid > 0) THEN
        INSERT INTO genericcashtransactions (
            farmid, genericcashaccountid, transactiondate, transactiontype,
            sourcetype, sourceid, amount, balanceaftertransaction, description,
            createdby, approvedby, approvedat
        )
        VALUES (
            p_farmid, v_cashaccountid, v_purchasedate, 'CashOut',
            'Purchase', p_genericpurchaseid, -v_amountpaid, v_cashnewbalance,
            'Purchase ' || COALESCE(v_invoicenumber, p_genericpurchaseid::text),
            p_approvedby, p_approvedby, (now() at time zone 'utc')
        );

        UPDATE genericcashaccounts ca
        SET    currentbalance = v_cashnewbalance, updatedat = (now() at time zone 'utc')
        WHERE  ca.genericcashaccountid = v_cashaccountid AND ca.farmid = p_farmid;
    END IF;

    IF (v_balance > 0 AND v_supplierid IS NOT NULL) THEN
        SELECT s.currentbalance + v_balance INTO v_suppliernewbalance
        FROM   genericsuppliers s
        WHERE  s.genericsupplierid = v_supplierid AND s.farmid = p_farmid
        LIMIT 1;

        INSERT INTO genericsupplierledger (
            farmid, genericsupplierid, transactiondate, transactiontype,
            purchaseid, debitamount, creditamount, balanceaftertransaction,
            description, createdby
        )
        VALUES (
            p_farmid, v_supplierid, v_purchasedate, 'PurchaseCredit',
            p_genericpurchaseid, 0, v_balance, v_suppliernewbalance,
            'Credit on purchase ' || COALESCE(v_invoicenumber, p_genericpurchaseid::text),
            p_approvedby
        );

        UPDATE genericsuppliers s
        SET    currentbalance = v_suppliernewbalance, updatedat = (now() at time zone 'utc')
        WHERE  s.genericsupplierid = v_supplierid AND s.farmid = p_farmid;
    END IF;
END
$function$;
