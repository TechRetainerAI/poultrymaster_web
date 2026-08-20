-- =============================================================================
-- 207 (PostgreSQL): restore the linked Expense on poultry raw-material purchases
--
-- SYMPTOM
--   Buying a raw material — medication, equipment, feed ingredient, anything —
--   increases stock but posts nothing to /expenses, so /cash never shows the
--   money leaving. Reported as "purchasing equipment creates no expense"; the
--   category is irrelevant, it happens for every item.
--
-- CAUSE
--   Migration 130 gave the four purchase procs a linked dbo.Expense row keyed
--   (SourceType='PoultryRawMaterialPurchase', SourceId=purchase id):
--     Insert     -> one expense for the amount actually paid
--     Update     -> keep the earliest linked expense in step
--     Delete     -> remove the linked expenses
--     PayBalance -> add one expense per balance payment
--   Migration 153 (FIFO/LIFO/HIFO batch costing) rewrote Insert/Update/Delete
--   and dropped the expense blocks; 157 (production-unit stock) layered onto
--   153's already-stripped bodies, and the PostgreSQL port carried the loss
--   over verbatim. PayBalance was never rewritten, so it still posts — which is
--   why some purchases have an expense and recent ones have none.
--
--   Measured on VisibilityCoreDB before this migration:
--     70 purchases, 65 with amountpaid > 0, but only 12 linked expense rows;
--     newest linked expense 2026-07-31 against purchases running to 2026-08-18.
--     54 purchases totalling 380,962.00 paid with nothing booked as an expense.
--
-- FIX
--   Re-add the expense blocks to the three functions, bodies otherwise byte-for-
--   byte as they stand today (157's production-unit stock maths and 153's batch
--   costing are untouched). Two deliberate improvements on 130:
--
--   * Update keeps the invariant "linked expense rows sum to amountpaid" instead
--     of blindly writing amountpaid onto the earliest row. Under 130, editing a
--     purchase after a balance payment set the initial expense to the cumulative
--     amount while the PayBalance rows still stood, double-counting the payment.
--   * Update inserts the expense when none exists yet (userid taken from the
--     purchase's createdby), so re-saving one of the 54 stranded purchases
--     repairs it. 130 only ever updated an existing row.
--
--   Guards are 130's: farmid must cast to uuid and a userid must be known, so a
--   purchase never fails just because expense linking cannot run.
--
-- SCOPE
--   Behaviour only. No schema change, and no backfill of the 54 stranded
--   purchases — that moves ~380,962.00 out of cash at hand and is a books
--   decision, not a deployment one. Run it separately when you have decided.
-- =============================================================================

BEGIN;

-- ---- Insert: purchase + stock increment + linked expense --------------------
CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialpurchase_insert(
    p_farmid text,
    p_poultryrawmaterialitemid integer,
    p_suppliername text DEFAULT NULL::text,
    p_supplierid integer DEFAULT NULL::integer,
    p_purchasedate timestamp without time zone DEFAULT NULL::timestamp without time zone,
    p_quantity numeric DEFAULT NULL::numeric,
    p_unitcost numeric DEFAULT NULL::numeric,
    p_totalcost numeric DEFAULT NULL::numeric,
    p_productionunit text DEFAULT NULL::text,
    p_productionunitsperpurchaseunit numeric DEFAULT NULL::numeric,
    p_paymentmethod text DEFAULT NULL::text,
    p_amountpaid numeric DEFAULT 0,
    p_receipturl text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text,
    p_createdby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_totalcost  numeric(14,2) := p_totalcost;
    v_amountpaid numeric(14,2) := p_amountpaid;
    v_mult       numeric(18,8);
    v_newid      integer;
    v_itemname   text;
    v_unit       text;
    v_gid        uuid;
BEGIN
    IF (p_quantity <= 0) THEN RAISE EXCEPTION 'Quantity must be > 0.'; END IF;
    IF (p_unitcost < 0)  THEN RAISE EXCEPTION 'UnitCost cannot be negative.'; END IF;
    IF (v_totalcost IS NULL OR v_totalcost <= 0) THEN
        v_totalcost := (p_quantity::numeric(14,2)) * p_unitcost;
    END IF;
    IF (v_amountpaid IS NULL) THEN v_amountpaid := 0; END IF;
    IF (v_amountpaid > v_totalcost) THEN v_amountpaid := v_totalcost; END IF;

    v_mult := COALESCE(NULLIF(p_productionunitsperpurchaseunit, 0), 1);   -- 157

    SELECT i.itemname, i.unitofmeasure INTO v_itemname, v_unit
    FROM   poultryrawmaterialitems i
    WHERE  i.poultryrawmaterialitemid = p_poultryrawmaterialitemid AND i.farmid = p_farmid
    LIMIT 1;

    INSERT INTO poultryrawmaterialpurchases (
        farmid, poultryrawmaterialitemid, suppliername, supplierid, purchasedate,
        quantity, unitcost, totalcost, productionunit, productionunitsperpurchaseunit,
        paymentmethod, amountpaid, receipturl, notes, createdby, remainingquantity
    )
    VALUES (
        p_farmid, p_poultryrawmaterialitemid, p_suppliername, p_supplierid, COALESCE(p_purchasedate, (now() at time zone 'utc')),
        p_quantity, p_unitcost, v_totalcost, p_productionunit, p_productionunitsperpurchaseunit,
        p_paymentmethod, v_amountpaid, p_receipturl, p_notes, p_createdby, p_quantity   -- RemainingQuantity in PURCHASE units
    )
    RETURNING poultryrawmaterialpurchases.poultryrawmaterialpurchaseid INTO v_newid;

    UPDATE poultryrawmaterialitems i
    SET    currentquantity = i.currentquantity + (p_quantity * v_mult), updatedat = (now() at time zone 'utc')   -- 157: production units
    WHERE  i.poultryrawmaterialitemid = p_poultryrawmaterialitemid AND i.farmid = p_farmid;

    -- Linked expense (actual cash out). Guard on userid + uuid-castable farmid,
    -- so the purchase still succeeds when expense linking cannot run.   -- 130/207
    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;

    IF (v_gid IS NOT NULL AND p_createdby IS NOT NULL AND v_amountpaid > 0) THEN
        INSERT INTO expense (expensedate, category, description, amount, paymentmethod, supplier, flockid, createddate, userid, farmid, sourcetype, sourceid)
        VALUES (COALESCE(p_purchasedate, (now() at time zone 'utc')), 'Raw Materials / Inventory Purchase',
                'Raw material purchase: ' || COALESCE(v_itemname, 'item') || ' (' || p_quantity::text || ' ' || COALESCE(v_unit, '') || ')',
                v_amountpaid, COALESCE(p_paymentmethod, 'Cash'), p_suppliername, NULL, (now() at time zone 'utc'), p_createdby, v_gid,
                'PoultryRawMaterialPurchase', v_newid);
    END IF;

    RETURN v_newid;
END;
$function$;

-- ---- Update: stock delta + keep the linked expenses summing to amountpaid ----
CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialpurchase_update(
    p_poultryrawmaterialpurchaseid integer,
    p_farmid text,
    p_suppliername text DEFAULT NULL::text,
    p_supplierid integer DEFAULT NULL::integer,
    p_purchasedate timestamp without time zone DEFAULT NULL::timestamp without time zone,
    p_quantity numeric DEFAULT NULL::numeric,
    p_unitcost numeric DEFAULT NULL::numeric,
    p_totalcost numeric DEFAULT NULL::numeric,
    p_productionunit text DEFAULT NULL::text,
    p_productionunitsperpurchaseunit numeric DEFAULT NULL::numeric,
    p_paymentmethod text DEFAULT NULL::text,
    p_amountpaid numeric DEFAULT 0,
    p_receipturl text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_totalcost    numeric(14,2) := p_totalcost;
    v_oldqty       numeric(14,3);
    v_oldremaining numeric(14,3);
    v_itemid       integer;
    v_oldmult      numeric(18,8);
    v_alreadydrawn numeric(14,3);
    v_newmult      numeric(18,8);
    v_deltaprod    numeric(18,4);
    v_currentstock numeric(18,4);
    v_msg          text;
    v_msg2         text;
    v_gid          uuid;
    v_firstid      integer;
    v_others       numeric(14,2);
    v_target       numeric(14,2);
    v_createdby    text;
    v_itemname     text;
    v_unit         text;
BEGIN
    IF (p_quantity <= 0) THEN RAISE EXCEPTION 'Quantity must be > 0.'; END IF;
    IF (p_unitcost < 0)  THEN RAISE EXCEPTION 'UnitCost cannot be negative.'; END IF;
    IF (v_totalcost IS NULL OR v_totalcost <= 0) THEN
        v_totalcost := (p_quantity::numeric(14,2)) * p_unitcost;
    END IF;

    SELECT pu.quantity, pu.remainingquantity, pu.poultryrawmaterialitemid,
           COALESCE(NULLIF(pu.productionunitsperpurchaseunit, 0), 1), pu.createdby
    INTO   v_oldqty, v_oldremaining, v_itemid, v_oldmult, v_createdby
    FROM   poultryrawmaterialpurchases pu
    WHERE  pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid AND pu.farmid = p_farmid
    LIMIT 1;

    IF v_oldqty IS NULL THEN
        RAISE EXCEPTION 'Purchase % not found.', p_poultryrawmaterialpurchaseid;
    END IF;

    -- Cannot reduce the (purchase-unit) quantity below what's already been drawn.
    v_alreadydrawn := v_oldqty - COALESCE(v_oldremaining, v_oldqty);
    IF (p_quantity < v_alreadydrawn) THEN
        v_msg2 := 'Cannot reduce quantity below ' || v_alreadydrawn::text || ' — that much has already been used from this batch.';
        RAISE EXCEPTION '%', v_msg2;
    END IF;

    -- Stock delta in PRODUCTION units (157).
    v_newmult := COALESCE(NULLIF(p_productionunitsperpurchaseunit, 0), 1);
    v_deltaprod := ((p_quantity * v_newmult) - (v_oldqty * v_oldmult))::numeric(18,4);
    IF (v_deltaprod < 0) THEN
        SELECT i.currentquantity INTO v_currentstock
        FROM   poultryrawmaterialitems i
        WHERE  i.poultryrawmaterialitemid = v_itemid AND i.farmid = p_farmid;
        IF (v_currentstock + v_deltaprod < 0) THEN
            v_msg := 'Cannot reduce quantity: only ' || v_currentstock::text || ' production units remain in stock.';
            RAISE EXCEPTION '%', v_msg;
        END IF;
    END IF;

    UPDATE poultryrawmaterialpurchases pu
    SET    suppliername = p_suppliername, supplierid = p_supplierid,
           purchasedate = COALESCE(p_purchasedate, pu.purchasedate),
           quantity = p_quantity, unitcost = p_unitcost, totalcost = v_totalcost,
           productionunit = p_productionunit, productionunitsperpurchaseunit = p_productionunitsperpurchaseunit,
           paymentmethod = p_paymentmethod, amountpaid = p_amountpaid,
           receipturl = p_receipturl, notes = p_notes, updatedat = (now() at time zone 'utc'),
           remainingquantity = p_quantity - v_alreadydrawn   -- PURCHASE units, unchanged
    WHERE  pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid AND pu.farmid = p_farmid;

    IF (v_deltaprod <> 0) THEN
        UPDATE poultryrawmaterialitems i
        SET    currentquantity = i.currentquantity + v_deltaprod, updatedat = (now() at time zone 'utc')   -- 157: production-level delta
        WHERE  i.poultryrawmaterialitemid = v_itemid AND i.farmid = p_farmid;
    END IF;

    -- Keep the linked expenses summing to amountpaid. The earliest row is the
    -- purchase's own expense; any later ones are PayBalance payments and are
    -- left alone, so the initial row absorbs the difference.            -- 130/207
    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;

    IF (v_gid IS NOT NULL) THEN
        SELECT min(e.expenseid) INTO v_firstid
        FROM   expense e
        WHERE  e.farmid = v_gid AND e.sourcetype = 'PoultryRawMaterialPurchase'
               AND e.sourceid = p_poultryrawmaterialpurchaseid;

        SELECT COALESCE(sum(e.amount), 0) INTO v_others
        FROM   expense e
        WHERE  e.farmid = v_gid AND e.sourcetype = 'PoultryRawMaterialPurchase'
               AND e.sourceid = p_poultryrawmaterialpurchaseid
               AND v_firstid IS NOT NULL AND e.expenseid <> v_firstid;

        v_target := GREATEST(COALESCE(p_amountpaid, 0) - v_others, 0)::numeric(14,2);

        IF (v_firstid IS NOT NULL) THEN
            UPDATE expense e
            SET    amount = v_target,
                   supplier = p_suppliername,
                   paymentmethod = COALESCE(p_paymentmethod, e.paymentmethod)
            WHERE  e.expenseid = v_firstid;
        ELSIF (v_target > 0 AND v_createdby IS NOT NULL) THEN
            -- No expense yet: a purchase recorded while 153/157 had the link
            -- stripped. Re-saving it repairs the books.
            SELECT i.itemname, i.unitofmeasure INTO v_itemname, v_unit
            FROM   poultryrawmaterialitems i
            WHERE  i.poultryrawmaterialitemid = v_itemid AND i.farmid = p_farmid
            LIMIT 1;

            INSERT INTO expense (expensedate, category, description, amount, paymentmethod, supplier, flockid, createddate, userid, farmid, sourcetype, sourceid)
            VALUES (COALESCE(p_purchasedate, (now() at time zone 'utc')), 'Raw Materials / Inventory Purchase',
                    'Raw material purchase: ' || COALESCE(v_itemname, 'item') || ' (' || p_quantity::text || ' ' || COALESCE(v_unit, '') || ')',
                    v_target, COALESCE(p_paymentmethod, 'Cash'), p_suppliername, NULL, (now() at time zone 'utc'), v_createdby, v_gid,
                    'PoultryRawMaterialPurchase', p_poultryrawmaterialpurchaseid);
        END IF;
    END IF;
END;
$function$;

-- ---- Delete: reverse stock + remove the linked expenses ----------------------
CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialpurchase_delete(
    p_poultryrawmaterialpurchaseid integer,
    p_farmid text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_qty     numeric(14,3);
    v_itemid  integer;
    v_mult    numeric(18,8);
    v_prodqty numeric(18,4);
    v_gid     uuid;
BEGIN
    IF EXISTS (SELECT 1 FROM poultryrawmaterialusagebatch ub
               WHERE ub.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid) THEN
        RAISE EXCEPTION 'Cannot delete: this purchase batch has already been drawn from by a production/medication record. Delete or edit those records first.';
    END IF;

    SELECT pu.quantity, pu.poultryrawmaterialitemid,
           COALESCE(NULLIF(pu.productionunitsperpurchaseunit, 0), 1)
    INTO   v_qty, v_itemid, v_mult
    FROM   poultryrawmaterialpurchases pu
    WHERE  pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid AND pu.farmid = p_farmid
    LIMIT 1;

    IF v_qty IS NULL THEN
        RAISE EXCEPTION 'Purchase % not found.', p_poultryrawmaterialpurchaseid;
    END IF;

    v_prodqty := (v_qty * v_mult)::numeric(18,4);   -- 157

    -- Drop the linked expenses first, or deleting the purchase strands them
    -- on /expenses with no way back to a source.                        -- 130/207
    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;

    IF (v_gid IS NOT NULL) THEN
        DELETE FROM expense e
        WHERE  e.farmid = v_gid AND e.sourcetype = 'PoultryRawMaterialPurchase'
               AND e.sourceid = p_poultryrawmaterialpurchaseid;
    END IF;

    DELETE FROM poultryrawmaterialpurchases pu
    WHERE  pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid AND pu.farmid = p_farmid;

    UPDATE poultryrawmaterialitems i
    SET    currentquantity = CASE WHEN i.currentquantity - v_prodqty < 0 THEN 0 ELSE i.currentquantity - v_prodqty END,
           updatedat = (now() at time zone 'utc')
    WHERE  i.poultryrawmaterialitemid = v_itemid AND i.farmid = p_farmid;
END;
$function$;

COMMIT;

-- ---- Verification ------------------------------------------------------------
-- All four purchase functions should now mention the expense table.
SELECT p.proname AS function, (p.prosrc ILIKE '%INSERT INTO expense%'
                            OR p.prosrc ILIKE '%UPDATE expense%'
                            OR p.prosrc ILIKE '%DELETE FROM expense%') AS touches_expense
FROM   pg_proc p
WHERE  p.pronamespace = 'public'::regnamespace
       AND p.proname LIKE 'sppoultryrawmaterialpurchase\_%'
ORDER  BY p.proname;

-- Purchases that are paid but carry no linked expense (the pre-existing gap;
-- this migration stops it growing, it does not backfill).
SELECT count(*) AS unbooked_purchases, COALESCE(sum(pu.amountpaid), 0) AS unbooked_amount
FROM   poultryrawmaterialpurchases pu
WHERE  pu.amountpaid > 0
       AND NOT EXISTS (SELECT 1 FROM expense e
                       WHERE e.sourcetype = 'PoultryRawMaterialPurchase'
                             AND e.sourceid = pu.poultryrawmaterialpurchaseid);
