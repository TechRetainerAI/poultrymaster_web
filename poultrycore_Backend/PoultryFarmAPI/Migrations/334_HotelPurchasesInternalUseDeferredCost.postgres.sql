-- =============================================================================
-- 334_HotelPurchasesInternalUseDeferredCost.postgres.sql
--
-- Purpose
-- -------
-- Hotel feature 4 of 5: supply PURCHASES -> INTERNAL USE -> DEFERRED INVENTORY
-- COST, copied from Poultry (216 internal use, 261-268 deferred purchase cost,
-- 288) along the hospitality template the Restaurant built in 329 / 330.
-- HOTEL ONLY: no Poultry, Water, Generic or Restaurant object is touched.
--
-- Supplies are the hotel's own stock (hotelinventoryitems): toiletries and guest
-- amenities, linen and towels, cleaning products, housekeeping and maintenance
-- stock, kitchen / F&B stock, office supplies.
--
--   * A PURCHASE is a delivery of one supply item: supplier, quantity, total
--     cost, amount paid now (from a cash account, 'SupplyPurchase' through
--     fnhotelcash_postonce), due date. It adds stock, becomes a FIFO cost LOT
--     (hotelsupplypurchases), and the unpaid part is a 'Purchase' document on
--     Supplier Balances / Supplier Payments (the 332 payables definition gains
--     it). The supplier ledger (321) follows. Reversal: refused once stock from
--     the lot was used or a supplier payment applied; the cash comes back today.
--   * Each supply CATEGORY is "Expense when purchased" (default) or "Expense
--     when consumed" (Poultry 261). The choice is stamped on the purchase.
--       - when purchased: the whole cost is a P&L line on the purchase date
--         ("Supplies purchased"), whatever was paid.
--       - when consumed: the cost is held as stock value and each draw on the
--         lot moves its pro-rata share into P&L ("Supplies used", non-cash).
--     Stock that never came through a purchase carries no cost (it was expensed
--     however it was paid for), so every unit's cost reaches P&L exactly once.
--   * INTERNAL USE (Poultry 216): stock the hotel uses itself -- rooms restocked
--     with amenities, housekeeping consumption, staff use, complimentary,
--     donation, damaged / written off, other. Draft -> Posted -> Reversed;
--     posting draws through the lots; non-cash; reversal hands every draw back
--     to its lot with a negative-cost draw dated today.
--   * The read-only DEFERRED INVENTORY COST page (Poultry 288) over the lots.
--
-- Re-emits (every earlier arm kept): fnhotel_payables and
-- fnhotelsupplierpayment_apply (332) with the 'Purchase' document;
-- sphotelcashflow_rows / _detail (332) with arms 16 / 16b; sphotelreport_pllines
-- and sphotelreport_plexpensedetail (331) with the two supply lines.
-- Chain: 325 -> 327 -> 331 -> 332 -> 334.
--
-- Schema change to an existing table: hotelinventoryitems.stockonhand becomes
-- numeric (litres of cleaning fluid); read only by SELECT * into name-keyed
-- dictionaries (HotelOperationsController) -- checked, no function reads it.
-- Idempotent.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. Drop the functions this file owns, by NAME (every overload).
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN (
            'fnhotelsupply_costmode', 'sphotelsupply_costmode_list', 'sphotelsupply_costmode_set',
            'fnhotelsupply_refreshcost', 'fnhotelsupply_draw',
            'sphotelsupplypurchase_create', 'sphotelsupplypurchase_reverse', 'sphotelsupplypurchase_list',
            'fnhotelinternalusage_categoryok', 'fnhotelinternalusage_unitcost', 'sphotelinternalusage_items',
            'sphotelinternalusage_getall', 'sphotelinternalusage_getbyid', 'sphotelinternalusage_replaceitems',
            'sphotelinternalusage_insert', 'sphotelinternalusage_update', 'sphotelinternalusage_delete',
            'sphotelinternalusage_post', 'sphotelinternalusage_reverse',
            'fnhotelsupply_deferredrows', 'sphotelsupply_deferred_getall', 'sphotelsupply_deferred_summary',
            'sphotelsupply_deferred_history')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Tables
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF (SELECT data_type FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'hotelinventoryitems' AND column_name = 'stockonhand') = 'integer' THEN
        ALTER TABLE public.hotelinventoryitems ALTER COLUMN stockonhand TYPE numeric(14,4);
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.hotelsupplycostmodes (
    farmid    text        NOT NULL,
    category  text        NOT NULL,
    costmode  text        NOT NULL DEFAULT 'EXPENSE_WHEN_PURCHASED',
    updatedby text,
    updatedat timestamp   NOT NULL DEFAULT now(),
    CONSTRAINT ck_hotelsupplycostmodes_mode CHECK (costmode IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED'))
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelsupplycostmodes ON public.hotelsupplycostmodes (farmid, lower(category));

CREATE TABLE IF NOT EXISTS public.hotelsupplypurchases (
    purchaseid                serial PRIMARY KEY,
    farmid                    text          NOT NULL,
    hotelinventoryitemid      int           NOT NULL REFERENCES public.hotelinventoryitems(hotelinventoryitemid),
    purchasedate              date          NOT NULL,
    hotelsupplierid           int           REFERENCES public.hotelsuppliers(hotelsupplierid),
    suppliername              text,
    quantity                  numeric(14,4) NOT NULL,
    unit                      text,
    unitcost                  numeric(14,4) NOT NULL,
    totalcost                 numeric(14,2) NOT NULL,
    paymentmethod             text,
    amountpaid                numeric(14,2) NOT NULL DEFAULT 0,
    hotelcashaccountid        int,
    duedate                   date,
    costmode                  text          NOT NULL DEFAULT 'EXPENSE_WHEN_PURCHASED',
    remainingquantity         numeric(14,4) NOT NULL,
    deferredtotalcost         numeric(14,2) NOT NULL DEFAULT 0,
    deferredremainingcost     numeric(14,2) NOT NULL DEFAULT 0,
    notes                     text,
    status                    text          NOT NULL DEFAULT 'Posted',
    cashtransactionid         int,
    reversalcashtransactionid int,
    createdby                 text,
    createdat                 timestamp     NOT NULL DEFAULT now(),
    reversedby                text,
    reversedat                timestamp,
    reversalreason            text,
    CONSTRAINT ck_hotelsupplypurchases_qty  CHECK (quantity > 0),
    CONSTRAINT ck_hotelsupplypurchases_cost CHECK (totalcost >= 0),
    CONSTRAINT ck_hotelsupplypurchases_paid CHECK (amountpaid >= 0 AND amountpaid <= totalcost),
    CONSTRAINT ck_hotelsupplypurchases_mode CHECK (costmode IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED')),
    CONSTRAINT ck_hotelsupplypurchases_lot  CHECK (remainingquantity >= 0 AND remainingquantity <= quantity
                                                   AND deferredremainingcost >= 0
                                                   AND deferredremainingcost <= deferredtotalcost),
    CONSTRAINT ck_hotelsupplypurchases_status CHECK (status IN ('Posted', 'Reversed'))
);
CREATE INDEX IF NOT EXISTS ix_hotelsupplypurchases_farm ON public.hotelsupplypurchases (farmid, purchasedate);
CREATE INDEX IF NOT EXISTS ix_hotelsupplypurchases_lots
    ON public.hotelsupplypurchases (hotelinventoryitemid, purchasedate, purchaseid) WHERE status = 'Posted' AND remainingquantity > 0;

-- Every draw on stock: which lot (or none), how much, what cost moved to P&L.
CREATE TABLE IF NOT EXISTS public.hotelsupplydraws (
    drawid               serial PRIMARY KEY,
    farmid               text          NOT NULL,
    hotelinventoryitemid int           NOT NULL REFERENCES public.hotelinventoryitems(hotelinventoryitemid),
    purchaseid           int           REFERENCES public.hotelsupplypurchases(purchaseid),
    drawtype             text          NOT NULL,     -- InternalUse | InternalUseReversal | Shortfall
    sourceid             int,                        -- hotelinternalusagestock.usagestockid
    drawdate             date          NOT NULL,
    quantity             numeric(14,4) NOT NULL CHECK (quantity > 0),
    unitcost             numeric(14,4) NOT NULL DEFAULT 0,
    costmode             text          NOT NULL,     -- the lot's, or UNLOTTED
    deferredcost         numeric(14,2) NOT NULL DEFAULT 0,
    reference            text,
    createdby            text,
    createdat            timestamp     NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_hotelsupplydraws_farm ON public.hotelsupplydraws (farmid, drawdate);
CREATE INDEX IF NOT EXISTS ix_hotelsupplydraws_source ON public.hotelsupplydraws (drawtype, sourceid);
CREATE INDEX IF NOT EXISTS ix_hotelsupplydraws_purchase ON public.hotelsupplydraws (purchaseid);

CREATE TABLE IF NOT EXISTS public.hotelinternalusage (
    internalusageid    serial PRIMARY KEY,
    farmid             text          NOT NULL,
    usagedate          date          NOT NULL DEFAULT CURRENT_DATE,
    referenceno        text,
    -- RoomAmenities | Housekeeping | StaffWelfare | Complimentary | Donation | Damaged | Other
    category           text          NOT NULL,
    reason             text,
    recipientname      text,
    staffcount         int,
    status             text          NOT NULL DEFAULT 'Draft',
    totalcostvalue     numeric(14,2) NOT NULL DEFAULT 0,
    notes              text,
    postedby text, postedat timestamp,
    reversedby text, reversedat timestamp, reversalreason text,
    createdby          text,
    createdat          timestamp     NOT NULL DEFAULT now(),
    updatedat          timestamp,
    CONSTRAINT ck_hotelinternalusage_status CHECK (status IN ('Draft', 'Posted', 'Reversed'))
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelinternalusage_farm_ref ON public.hotelinternalusage (farmid, referenceno) WHERE referenceno IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_hotelinternalusage_farm_date ON public.hotelinternalusage (farmid, usagedate);

CREATE TABLE IF NOT EXISTS public.hotelinternalusageitems (
    internalusageitemid  serial PRIMARY KEY,
    internalusageid      int           NOT NULL REFERENCES public.hotelinternalusage(internalusageid) ON DELETE CASCADE,
    farmid               text          NOT NULL,
    hotelinventoryitemid int           NOT NULL REFERENCES public.hotelinventoryitems(hotelinventoryitemid),
    entryquantity        numeric(14,4) NOT NULL,
    entryunit            text,
    quantityperstaff     numeric(14,4),
    entryunitcost        numeric(14,4) NOT NULL DEFAULT 0,
    totalcost            numeric(14,2) NOT NULL DEFAULT 0,
    itemnotes            text,
    CONSTRAINT ck_hotelinternalusageitems_qty CHECK (entryquantity > 0 AND entryunitcost >= 0)
);
CREATE INDEX IF NOT EXISTS ix_hotelinternalusageitems_parent ON public.hotelinternalusageitems (internalusageid);

-- One row per item per posting; reversedat set when it came back.
CREATE TABLE IF NOT EXISTS public.hotelinternalusagestock (
    usagestockid         serial PRIMARY KEY,
    internalusageid      int           NOT NULL REFERENCES public.hotelinternalusage(internalusageid) ON DELETE CASCADE,
    farmid               text          NOT NULL,
    hotelinventoryitemid int           NOT NULL REFERENCES public.hotelinventoryitems(hotelinventoryitemid),
    quantity             numeric(14,4) NOT NULL CHECK (quantity > 0),
    deferredcost         numeric(14,2) NOT NULL DEFAULT 0,
    createdat            timestamp     NOT NULL DEFAULT now(),
    reversedat           timestamp
);
CREATE INDEX IF NOT EXISTS ix_hotelinternalusagestock_parent ON public.hotelinternalusagestock (internalusageid);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Cost recognition per supply category (Poultry 261)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.fnhotelsupply_costmode(p_farmid text, p_category text)
RETURNS text LANGUAGE sql STABLE AS $function$
    SELECT COALESCE((SELECT m.costmode FROM public.hotelsupplycostmodes m
                      WHERE m.farmid = p_farmid AND lower(m.category) = lower(btrim(COALESCE(p_category, '')))),
                    'EXPENSE_WHEN_PURCHASED');
$function$;

CREATE FUNCTION public.sphotelsupply_costmode_list(p_farmid text)
RETURNS TABLE(category text, costmode text, itemcount int, isconfigured boolean, updatedby text, updatedat timestamp)
LANGUAGE sql STABLE AS $function$
    WITH cats AS (
        SELECT btrim(i.category) AS category FROM public.hotelinventoryitems i
         WHERE i.farmid = p_farmid AND NULLIF(btrim(i.category), '') IS NOT NULL
        UNION
        SELECT m.category FROM public.hotelsupplycostmodes m WHERE m.farmid = p_farmid
    ), one AS (
        SELECT DISTINCT ON (lower(c.category)) c.category FROM cats c ORDER BY lower(c.category), c.category
    )
    SELECT o.category::text, public.fnhotelsupply_costmode(p_farmid, o.category),
           (SELECT COUNT(*)::int FROM public.hotelinventoryitems i
             WHERE i.farmid = p_farmid AND lower(btrim(i.category)) = lower(o.category)),
           (m.farmid IS NOT NULL), m.updatedby, m.updatedat
    FROM   one o
    LEFT   JOIN public.hotelsupplycostmodes m ON m.farmid = p_farmid AND lower(m.category) = lower(o.category)
    ORDER  BY o.category;
$function$;

-- Applies to purchases recorded from now on; recorded ones keep their stamp.
CREATE FUNCTION public.sphotelsupply_costmode_set(p_farmid text, p_category text, p_costmode text, p_updatedby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
    IF COALESCE(btrim(p_category), '') = '' THEN RAISE EXCEPTION 'Choose a category.'; END IF;
    IF p_costmode NOT IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED') THEN
        RAISE EXCEPTION 'Choose Expense when purchased or Expense when consumed.';
    END IF;
    INSERT INTO public.hotelsupplycostmodes (farmid, category, costmode, updatedby, updatedat)
    VALUES (p_farmid, btrim(p_category), p_costmode, p_updatedby, now())
    ON CONFLICT (farmid, lower(category))
    DO UPDATE SET costmode = EXCLUDED.costmode, updatedby = EXCLUDED.updatedby, updatedat = now();
END $function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. The FIFO engine (Restaurant 329 / Poultry 264)
-- ─────────────────────────────────────────────────────────────────────────────
-- Cost per unit = value on hand / quantity on hand (lots at their cost, stock
-- with no purchase behind it at the old figure).
CREATE FUNCTION public.fnhotelsupply_refreshcost(p_itemid int)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE v_stock numeric; v_old numeric; v_lq numeric; v_lv numeric; v_un numeric; v_last numeric;
BEGIN
    SELECT COALESCE(i.stockonhand, 0), COALESCE(i.unitcost, 0) INTO v_stock, v_old
    FROM   public.hotelinventoryitems i WHERE i.hotelinventoryitemid = p_itemid;
    SELECT COALESCE(SUM(p.remainingquantity), 0), COALESCE(SUM(p.remainingquantity * p.unitcost), 0) INTO v_lq, v_lv
    FROM   public.hotelsupplypurchases p
    WHERE  p.hotelinventoryitemid = p_itemid AND p.status = 'Posted' AND p.remainingquantity > 0;
    v_un := GREATEST(v_stock - v_lq, 0);
    IF v_lq + v_un > 0 THEN
        UPDATE public.hotelinventoryitems SET unitcost = ROUND((v_lv + v_un * v_old) / (v_lq + v_un), 4), updatedat = now()
        WHERE  hotelinventoryitemid = p_itemid;
    ELSE
        SELECT p.unitcost INTO v_last FROM public.hotelsupplypurchases p
        WHERE  p.hotelinventoryitemid = p_itemid AND p.status = 'Posted'
        ORDER  BY p.purchasedate DESC, p.purchaseid DESC LIMIT 1;
        IF v_last IS NOT NULL THEN
            UPDATE public.hotelinventoryitems SET unitcost = v_last, updatedat = now() WHERE hotelinventoryitemid = p_itemid;
        END IF;
    END IF;
END $function$;

-- Draws p_qty of an item. MUST be called BEFORE stockonhand is lowered. Stock
-- with no purchase behind it goes first (oldest, no deferred cost), then lots
-- oldest first; each lot gives up its deferred cost pro rata (the last unit
-- takes what is left). Returns the deferred cost moved into P&L.
CREATE FUNCTION public.fnhotelsupply_draw(p_farmid text, p_itemid int, p_qty numeric, p_drawtype text,
                                          p_sourceid int, p_date date, p_reference text, p_by text)
RETURNS numeric LANGUAGE plpgsql AS $function$
DECLARE
    v_left numeric := COALESCE(p_qty, 0); v_stock numeric; v_cpu numeric; v_lots numeric; v_un numeric;
    v_take numeric; v_share numeric(14,2); v_total numeric(14,2) := 0; l record;
BEGIN
    IF v_left <= 0 THEN RETURN 0; END IF;
    SELECT COALESCE(i.stockonhand, 0), COALESCE(i.unitcost, 0) INTO v_stock, v_cpu
    FROM   public.hotelinventoryitems i WHERE i.hotelinventoryitemid = p_itemid AND i.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Supply item not found for this hotel.'; END IF;
    SELECT COALESCE(SUM(p.remainingquantity), 0) INTO v_lots FROM public.hotelsupplypurchases p
    WHERE  p.hotelinventoryitemid = p_itemid AND p.status = 'Posted' AND p.remainingquantity > 0;

    v_un := LEAST(GREATEST(v_stock - v_lots, 0), v_left);
    IF v_un > 0 THEN
        INSERT INTO public.hotelsupplydraws (farmid, hotelinventoryitemid, purchaseid, drawtype, sourceid, drawdate,
                                             quantity, unitcost, costmode, deferredcost, reference, createdby)
        VALUES (p_farmid, p_itemid, NULL, p_drawtype, p_sourceid, p_date, v_un, v_cpu, 'UNLOTTED', 0, p_reference, p_by);
        v_left := v_left - v_un;
    END IF;

    FOR l IN SELECT p.purchaseid, p.remainingquantity, p.unitcost, p.costmode, p.deferredremainingcost
             FROM   public.hotelsupplypurchases p
             WHERE  p.hotelinventoryitemid = p_itemid AND p.status = 'Posted' AND p.remainingquantity > 0
             ORDER  BY p.purchasedate, p.purchaseid
             FOR UPDATE
    LOOP
        EXIT WHEN v_left <= 0;
        v_take := LEAST(v_left, l.remainingquantity);
        v_share := CASE WHEN v_take >= l.remainingquantity THEN l.deferredremainingcost
                        ELSE ROUND(l.deferredremainingcost * v_take / l.remainingquantity, 2) END;
        UPDATE public.hotelsupplypurchases
        SET    remainingquantity = remainingquantity - v_take, deferredremainingcost = deferredremainingcost - v_share
        WHERE  purchaseid = l.purchaseid;
        INSERT INTO public.hotelsupplydraws (farmid, hotelinventoryitemid, purchaseid, drawtype, sourceid, drawdate,
                                             quantity, unitcost, costmode, deferredcost, reference, createdby)
        VALUES (p_farmid, p_itemid, l.purchaseid, p_drawtype, p_sourceid, p_date, v_take, l.unitcost, l.costmode,
                v_share, p_reference, p_by);
        v_total := v_total + v_share;
        v_left := v_left - v_take;
    END LOOP;

    IF v_left > 0 THEN
        INSERT INTO public.hotelsupplydraws (farmid, hotelinventoryitemid, purchaseid, drawtype, sourceid, drawdate,
                                             quantity, unitcost, costmode, deferredcost, reference, createdby)
        VALUES (p_farmid, p_itemid, NULL, p_drawtype, p_sourceid, p_date, v_left, v_cpu, 'UNLOTTED', 0, p_reference, p_by);
    END IF;
    RETURN v_total;
END $function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Purchases
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.sphotelsupplypurchase_create(
    p_farmid text, p_itemid int, p_quantity numeric, p_totalcost numeric,
    p_purchasedate date DEFAULT NULL, p_supplierid int DEFAULT NULL, p_suppliername text DEFAULT NULL,
    p_paymentmethod text DEFAULT 'Cash', p_amountpaid numeric DEFAULT NULL, p_cashaccountid int DEFAULT NULL,
    p_duedate date DEFAULT NULL, p_notes text DEFAULT NULL, p_createdby text DEFAULT NULL)
RETURNS int LANGUAGE plpgsql AS $function$
DECLARE
    v_date   date := COALESCE(p_purchasedate, CURRENT_DATE);
    v_qty    numeric(14,4) := ROUND(COALESCE(p_quantity, 0), 4);
    v_total  numeric(14,2) := ROUND(COALESCE(p_totalcost, 0), 2);
    v_method text := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash');
    v_credit boolean; v_paid numeric(14,2); v_acc int; v_txn int;
    v_sup int := p_supplierid; v_supname text := NULLIF(btrim(p_suppliername), '');
    v_item record; v_mode text; v_id int; v_short numeric;
BEGIN
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Quantity must be greater than 0.'; END IF;
    IF v_total < 0 THEN RAISE EXCEPTION 'Total cost cannot be negative.'; END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'A purchase cannot be dated in the future.'; END IF;

    SELECT * INTO v_item FROM public.hotelinventoryitems i
    WHERE  i.hotelinventoryitemid = p_itemid AND i.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Pick a supply item of this hotel.'; END IF;

    IF v_sup IS NOT NULL THEN
        SELECT s.suppliername INTO v_supname FROM public.hotelsuppliers s
        WHERE  s.hotelsupplierid = v_sup AND s.farmid = p_farmid AND NOT s.isdeleted;
        IF v_supname IS NULL THEN RAISE EXCEPTION 'Supplier does not belong to this company.'; END IF;
    ELSIF v_supname IS NOT NULL THEN
        SELECT MIN(s.hotelsupplierid) INTO v_sup FROM public.hotelsuppliers s
        WHERE  s.farmid = p_farmid AND NOT s.isdeleted AND lower(btrim(s.suppliername)) = lower(v_supname)
        HAVING COUNT(*) = 1;
    END IF;

    v_credit := lower(v_method) = 'credit';
    v_paid := ROUND(COALESCE(p_amountpaid, CASE WHEN v_credit THEN 0 ELSE v_total END), 2);
    IF v_paid < 0 THEN RAISE EXCEPTION 'Amount paid cannot be negative.'; END IF;
    IF v_paid > v_total THEN
        RAISE EXCEPTION 'Amount paid now (%) cannot be more than the total cost (%).', v_paid, v_total;
    END IF;
    IF v_credit AND v_paid > 0 THEN
        RAISE EXCEPTION 'A credit purchase has nothing paid now. Choose how the % was paid, or leave Amount paid now empty.', v_paid;
    END IF;
    IF v_paid < v_total AND v_sup IS NULL THEN
        RAISE EXCEPTION 'Choose the supplier: % of this purchase is still owed.', (v_total - v_paid);
    END IF;
    IF v_paid > 0 THEN
        v_acc := p_cashaccountid;
        IF v_acc IS NULL THEN RAISE EXCEPTION 'Choose the cash account this was paid from.'; END IF;
        PERFORM public.fnhotelcash_assertcanpay(p_farmid, v_acc, v_paid,
            'This account does not have enough money for this payment, and it is not allowed to go negative.');
    END IF;

    v_mode := public.fnhotelsupply_costmode(p_farmid, v_item.category);

    INSERT INTO public.hotelsupplypurchases
        (farmid, hotelinventoryitemid, purchasedate, hotelsupplierid, suppliername, quantity, unit, unitcost, totalcost,
         paymentmethod, amountpaid, hotelcashaccountid, duedate, costmode, remainingquantity,
         deferredtotalcost, deferredremainingcost, notes, createdby)
    VALUES
        (p_farmid, p_itemid, v_date, v_sup, v_supname, v_qty, v_item.unit, ROUND(v_total / v_qty, 4), v_total,
         v_method, v_paid, CASE WHEN v_paid > 0 THEN v_acc END, CASE WHEN v_paid < v_total THEN p_duedate END,
         v_mode, v_qty,
         CASE WHEN v_mode = 'EXPENSE_WHEN_CONSUMED' THEN v_total ELSE 0 END,
         CASE WHEN v_mode = 'EXPENSE_WHEN_CONSUMED' THEN v_total ELSE 0 END,
         NULLIF(btrim(p_notes), ''), p_createdby)
    RETURNING purchaseid INTO v_id;

    -- Stock already used before this delivery was recorded (below zero) is
    -- taken from the new lot straight away, so its cost is not left waiting.
    v_short := LEAST(GREATEST(-COALESCE(v_item.stockonhand, 0), 0), v_qty);
    UPDATE public.hotelinventoryitems SET stockonhand = COALESCE(stockonhand, 0) + v_qty, updatedat = now()
    WHERE  hotelinventoryitemid = p_itemid;
    IF v_short > 0 THEN
        UPDATE public.hotelinventoryitems SET stockonhand = stockonhand + v_short WHERE hotelinventoryitemid = p_itemid;
        PERFORM public.fnhotelsupply_draw(p_farmid, p_itemid, v_short, 'Shortfall', v_id, v_date, 'Purchase PO-' || v_id, p_createdby);
        UPDATE public.hotelinventoryitems SET stockonhand = stockonhand - v_short WHERE hotelinventoryitemid = p_itemid;
    END IF;
    PERFORM public.fnhotelsupply_refreshcost(p_itemid);

    IF v_paid > 0 THEN
        v_txn := public.fnhotelcash_postonce(p_farmid, v_acc, 'Debit', v_paid,
                    'Purchase: ' || v_item.name || COALESCE(' (' || v_supname || ')', ''), 'PO-' || v_id,
                    'SupplyPurchase', v_id, p_createdby, v_date::timestamptz);
        UPDATE public.hotelsupplypurchases SET cashtransactionid = v_txn WHERE purchaseid = v_id;
    END IF;
    IF v_paid < v_total THEN
        PERFORM public.fnhotelsupplier_ledger(p_farmid, v_sup, 'PurchaseCredit', v_total - v_paid, NULL, NULL,
                                              'Purchase PO-' || v_id || ': ' || v_item.name, p_createdby);
    END IF;
    RETURN v_id;
END $function$;

-- Undo a purchase recorded in error: refused once any of its stock has been
-- used or a supplier payment applied. Rows kept and marked; cash back today.
CREATE FUNCTION public.sphotelsupplypurchase_reverse(p_farmid text, p_purchaseid int, p_reason text, p_reversedby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE v_p record; v_r int;
BEGIN
    SELECT * INTO v_p FROM public.hotelsupplypurchases p WHERE p.purchaseid = p_purchaseid AND p.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Purchase not found for this company.'; END IF;
    IF v_p.status = 'Reversed' THEN RAISE EXCEPTION 'This purchase has already been reversed.'; END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to reverse a purchase.'; END IF;
    IF public.fnhotel_allocated(p_farmid, 'Purchase', p_purchaseid) > 0 THEN
        RAISE EXCEPTION 'A supplier payment has been recorded against this purchase. Reverse the payment on Supplier Payments first.';
    END IF;
    IF v_p.remainingquantity < v_p.quantity THEN
        RAISE EXCEPTION 'Stock from this purchase has already been used, so it cannot be reversed. Record internal use instead.';
    END IF;

    UPDATE public.hotelinventoryitems SET stockonhand = stockonhand - v_p.quantity, updatedat = now()
    WHERE  hotelinventoryitemid = v_p.hotelinventoryitemid;
    IF v_p.cashtransactionid IS NOT NULL THEN
        v_r := public.fnhotelcash_reverse(p_farmid, v_p.cashtransactionid, 'SupplyPurchaseReversal', btrim(p_reason), p_reversedby);
    END IF;
    IF v_p.amountpaid < v_p.totalcost AND v_p.hotelsupplierid IS NOT NULL THEN
        PERFORM public.fnhotelsupplier_ledger(p_farmid, v_p.hotelsupplierid, 'PurchaseReversal', -(v_p.totalcost - v_p.amountpaid),
                                              NULL, NULL, 'Reversal of purchase PO-' || p_purchaseid || ': ' || btrim(p_reason), p_reversedby);
    END IF;
    UPDATE public.hotelsupplypurchases
    SET    status = 'Reversed', remainingquantity = 0, deferredremainingcost = 0, reversalcashtransactionid = v_r,
           reversedby = p_reversedby, reversedat = now(), reversalreason = btrim(p_reason)
    WHERE  purchaseid = p_purchaseid;
    PERFORM public.fnhotelsupply_refreshcost(v_p.hotelinventoryitemid);
END $function$;

CREATE FUNCTION public.sphotelsupplypurchase_list(p_farmid text, p_from date DEFAULT NULL, p_to date DEFAULT NULL,
                                                  p_supplierid int DEFAULT NULL, p_itemid int DEFAULT NULL,
                                                  p_purchaseid int DEFAULT NULL)
RETURNS TABLE(purchaseid int, purchasedate date, itemid int, itemname text, category text, unit text,
              supplierid int, suppliername text, quantity numeric, unitcost numeric, totalcost numeric,
              paymentmethod text, amountpaid numeric, allocated numeric, balance numeric, paymentstatus text,
              duedate date, cashaccountid int, cashaccountname text, costmode text, remainingquantity numeric,
              deferredtotalcost numeric, deferredremainingcost numeric, notes text, status text,
              createdby text, createdat timestamp, reversedby text, reversedat timestamp, reversalreason text)
LANGUAGE sql STABLE AS $function$
    SELECT p.purchaseid, p.purchasedate, p.hotelinventoryitemid, i.name::text, i.category::text, p.unit,
           p.hotelsupplierid, COALESCE(s.suppliername, p.suppliername), p.quantity, p.unitcost, p.totalcost,
           p.paymentmethod, p.amountpaid, a.alloc,
           CASE WHEN p.status = 'Posted' THEN GREATEST(p.totalcost - p.amountpaid - a.alloc, 0) ELSE 0 END::numeric(14,2),
           CASE WHEN p.status = 'Reversed' THEN 'Reversed'
                WHEN p.totalcost - p.amountpaid - a.alloc <= 0 THEN 'Paid'
                WHEN p.amountpaid + a.alloc > 0 THEN 'Partially Paid' ELSE 'Unpaid' END,
           p.duedate, p.hotelcashaccountid, ca.accountname::text, p.costmode, p.remainingquantity,
           p.deferredtotalcost, p.deferredremainingcost, p.notes, p.status,
           p.createdby, p.createdat, p.reversedby, p.reversedat, p.reversalreason
    FROM   public.hotelsupplypurchases p
    JOIN   public.hotelinventoryitems i ON i.hotelinventoryitemid = p.hotelinventoryitemid
    LEFT   JOIN public.hotelsuppliers s ON s.hotelsupplierid = p.hotelsupplierid
    LEFT   JOIN public.hotelcashaccounts ca ON ca.hotelcashaccountid = p.hotelcashaccountid
    CROSS  JOIN LATERAL (SELECT public.fnhotel_allocated(p_farmid, 'Purchase', p.purchaseid) AS alloc) a
    WHERE  p.farmid = p_farmid
      AND  (p_from IS NULL OR p.purchasedate >= p_from)
      AND  (p_to IS NULL OR p.purchasedate <= p_to)
      AND  (p_supplierid IS NULL OR p.hotelsupplierid = p_supplierid)
      AND  (p_itemid IS NULL OR p.hotelinventoryitemid = p_itemid)
      AND  (p_purchaseid IS NULL OR p.purchaseid = p_purchaseid)
    ORDER  BY p.purchasedate DESC, p.purchaseid DESC;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Internal Use (Poultry 216 / 218 / 219 / 220; Restaurant 330)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.fnhotelinternalusage_categoryok(p_category text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $function$
    SELECT p_category IN ('RoomAmenities', 'Housekeeping', 'StaffWelfare', 'Complimentary', 'Donation', 'Damaged', 'Other');
$function$;

-- The suggested cost (Poultry 218: from stock history), 0 when nothing is known.
CREATE FUNCTION public.fnhotelinternalusage_unitcost(p_farmid text, p_itemid int)
RETURNS numeric LANGUAGE sql STABLE AS $function$
    SELECT ROUND(COALESCE(NULLIF(i.unitcost, 0),
                          (SELECT p.unitcost FROM public.hotelsupplypurchases p
                            WHERE p.hotelinventoryitemid = i.hotelinventoryitemid AND p.status = 'Posted'
                            ORDER BY p.purchasedate DESC, p.purchaseid DESC LIMIT 1), 0), 4)::numeric
    FROM   public.hotelinventoryitems i
    WHERE  i.hotelinventoryitemid = p_itemid AND i.farmid = p_farmid;
$function$;

CREATE FUNCTION public.sphotelinternalusage_items(p_farmid text)
RETURNS TABLE(itemtype text, itemid int, name text, category text, unit text, onhand numeric,
              suggestedunitcost numeric, costmode text)
LANGUAGE sql STABLE AS $function$
    SELECT 'Supply'::text, i.hotelinventoryitemid, i.name::text, i.category::text, i.unit::text,
           COALESCE(i.stockonhand, 0)::numeric,
           COALESCE(public.fnhotelinternalusage_unitcost(p_farmid, i.hotelinventoryitemid), 0),
           public.fnhotelsupply_costmode(p_farmid, i.category)
    FROM   public.hotelinventoryitems i
    WHERE  i.farmid = p_farmid AND COALESCE(i.isactive, TRUE)
    ORDER  BY i.category, i.name;
$function$;

-- plcost: what the CURRENT posting moved into P&L (0 for draft / reversed, and
-- 0 for stock expensed when purchased).
CREATE FUNCTION public.sphotelinternalusage_getall(
    p_farmid text, p_status text DEFAULT NULL, p_category text DEFAULT NULL,
    p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL)
RETURNS TABLE(internalusageid int, farmid text, usagedate date, referenceno text, category text, reason text,
              recipientname text, staffcount int, status text, totalcostvalue numeric, plcost numeric, notes text,
              postedby text, postedat timestamp, reversedby text, reversedat timestamp, reversalreason text,
              createdby text, createdat timestamp, updatedat timestamp, itemsjson text)
LANGUAGE sql STABLE AS $function$
    SELECT h.internalusageid, h.farmid, h.usagedate, h.referenceno, h.category, h.reason, h.recipientname,
           h.staffcount, h.status, h.totalcostvalue,
           COALESCE((SELECT SUM(s.deferredcost) FROM public.hotelinternalusagestock s
                      WHERE s.internalusageid = h.internalusageid AND s.reversedat IS NULL), 0)::numeric(14,2),
           h.notes, h.postedby, h.postedat, h.reversedby, h.reversedat, h.reversalreason,
           h.createdby, h.createdat, h.updatedat,
           COALESCE((
               SELECT json_agg(json_build_object(
                          'internalUsageItemId', i.internalusageitemid,
                          'itemType',            'Supply',
                          'itemId',              i.hotelinventoryitemid,
                          'itemName',            g.name,
                          'entryQuantity',       i.entryquantity,
                          'entryUnit',           i.entryunit,
                          'quantityPerStaff',    i.quantityperstaff,
                          'entryUnitCost',       i.entryunitcost,
                          'totalCost',           i.totalcost,
                          'itemNotes',           i.itemnotes)
                      ORDER BY i.internalusageitemid)::text
               FROM public.hotelinternalusageitems i
               LEFT JOIN public.hotelinventoryitems g ON g.hotelinventoryitemid = i.hotelinventoryitemid
               WHERE i.internalusageid = h.internalusageid), '[]')
    FROM   public.hotelinternalusage h
    WHERE  h.farmid = p_farmid
      AND  (p_status IS NULL OR h.status = p_status)
      AND  (p_category IS NULL OR h.category = p_category)
      AND  (p_fromdate IS NULL OR h.usagedate >= p_fromdate)
      AND  (p_todate IS NULL OR h.usagedate <= p_todate)
    ORDER  BY h.usagedate DESC, h.internalusageid DESC;
$function$;

CREATE FUNCTION public.sphotelinternalusage_getbyid(p_internalusageid int, p_farmid text)
RETURNS TABLE(internalusageid int, farmid text, usagedate date, referenceno text, category text, reason text,
              recipientname text, staffcount int, status text, totalcostvalue numeric, plcost numeric, notes text,
              postedby text, postedat timestamp, reversedby text, reversedat timestamp, reversalreason text,
              createdby text, createdat timestamp, updatedat timestamp, itemsjson text)
LANGUAGE sql STABLE AS $function$
    SELECT g.* FROM public.sphotelinternalusage_getall(p_farmid) g WHERE g.internalusageid = p_internalusageid;
$function$;

-- Lines are replaced whole; the header total follows. Items must be this hotel's.
CREATE FUNCTION public.sphotelinternalusage_replaceitems(p_internalusageid int, p_farmid text, p_itemsjson text)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE v_bad int;
BEGIN
    DELETE FROM public.hotelinternalusageitems WHERE internalusageid = p_internalusageid;
    IF p_itemsjson IS NOT NULL AND btrim(p_itemsjson) NOT IN ('', '[]') THEN
        SELECT COUNT(*) INTO v_bad
        FROM   json_to_recordset(p_itemsjson::json) AS j("itemId" int, "entryQuantity" numeric)
        WHERE  COALESCE(j."entryQuantity", 0) > 0
          AND  NOT EXISTS (SELECT 1 FROM public.hotelinventoryitems i WHERE i.hotelinventoryitemid = j."itemId" AND i.farmid = p_farmid);
        IF v_bad > 0 THEN RAISE EXCEPTION 'Pick a supply item of this hotel.'; END IF;

        INSERT INTO public.hotelinternalusageitems (internalusageid, farmid, hotelinventoryitemid, entryquantity, entryunit,
                                                    quantityperstaff, entryunitcost, totalcost, itemnotes)
        SELECT p_internalusageid, p_farmid, j."itemId", ROUND(j."entryQuantity", 4),
               COALESCE(NULLIF(btrim(j."entryUnit"), ''), g.unit), j."quantityPerStaff",
               ROUND(GREATEST(COALESCE(j."entryUnitCost", 0), 0), 4),
               ROUND(j."entryQuantity" * GREATEST(COALESCE(j."entryUnitCost", 0), 0), 2),
               NULLIF(btrim(j."itemNotes"), '')
        FROM   json_to_recordset(p_itemsjson::json) AS j("itemId" int, "entryQuantity" numeric, "entryUnit" text,
                                                         "quantityPerStaff" numeric, "entryUnitCost" numeric, "itemNotes" text)
        LEFT   JOIN public.hotelinventoryitems g ON g.hotelinventoryitemid = j."itemId" AND g.farmid = p_farmid
        WHERE  COALESCE(j."entryQuantity", 0) > 0;
    END IF;
    UPDATE public.hotelinternalusage h
    SET    totalcostvalue = COALESCE((SELECT SUM(i.totalcost) FROM public.hotelinternalusageitems i
                                       WHERE i.internalusageid = h.internalusageid), 0),
           updatedat = now()
    WHERE  h.internalusageid = p_internalusageid;
END $function$;

CREATE FUNCTION public.sphotelinternalusage_insert(
    p_farmid text, p_usagedate date, p_category text, p_reason text DEFAULT NULL, p_recipientname text DEFAULT NULL,
    p_staffcount int DEFAULT NULL, p_notes text DEFAULT NULL, p_itemsjson text DEFAULT NULL, p_createdby text DEFAULT NULL)
RETURNS int LANGUAGE plpgsql AS $function$
DECLARE v_id int; v_date date := COALESCE(p_usagedate, CURRENT_DATE);
BEGIN
    IF NOT COALESCE(public.fnhotelinternalusage_categoryok(p_category), FALSE) THEN
        RAISE EXCEPTION 'Pick what the stock was used for.';
    END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'The date cannot be in the future.'; END IF;
    INSERT INTO public.hotelinternalusage (farmid, usagedate, category, reason, recipientname, staffcount, notes, status, createdby)
    VALUES (p_farmid, v_date, p_category, NULLIF(btrim(p_reason), ''), NULLIF(btrim(p_recipientname), ''),
            p_staffcount, NULLIF(btrim(p_notes), ''), 'Draft', p_createdby)
    RETURNING internalusageid INTO v_id;
    UPDATE public.hotelinternalusage
    SET    referenceno = 'IU-' || to_char(v_date, 'YYYY') || '-' || lpad(v_id::text, 4, '0')
    WHERE  internalusageid = v_id;
    PERFORM public.sphotelinternalusage_replaceitems(v_id, p_farmid, p_itemsjson);
    RETURN v_id;
END $function$;

CREATE FUNCTION public.sphotelinternalusage_update(
    p_internalusageid int, p_farmid text, p_usagedate date, p_category text, p_reason text DEFAULT NULL,
    p_recipientname text DEFAULT NULL, p_staffcount int DEFAULT NULL, p_notes text DEFAULT NULL,
    p_itemsjson text DEFAULT NULL, p_updatedby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE v_status text; v_date date;
BEGIN
    SELECT h.status, COALESCE(p_usagedate, h.usagedate) INTO v_status, v_date
    FROM   public.hotelinternalusage h WHERE h.internalusageid = p_internalusageid AND h.farmid = p_farmid FOR UPDATE;
    IF v_status IS NULL THEN RAISE EXCEPTION 'Internal use record % not found.', p_internalusageid; END IF;
    IF v_status NOT IN ('Draft', 'Reversed') THEN
        RAISE EXCEPTION 'Only a draft or a reversed record can be edited. This one is %. Reverse it first.', v_status;
    END IF;
    IF p_category IS NOT NULL AND btrim(p_category) <> '' AND NOT public.fnhotelinternalusage_categoryok(p_category) THEN
        RAISE EXCEPTION 'Pick what the stock was used for.';
    END IF;
    IF v_date > CURRENT_DATE THEN RAISE EXCEPTION 'The date cannot be in the future.'; END IF;
    UPDATE public.hotelinternalusage
    SET    usagedate = v_date, category = COALESCE(NULLIF(btrim(p_category), ''), category),
           reason = NULLIF(btrim(p_reason), ''), recipientname = NULLIF(btrim(p_recipientname), ''),
           staffcount = p_staffcount, notes = NULLIF(btrim(p_notes), ''), updatedat = now()
    WHERE  internalusageid = p_internalusageid AND farmid = p_farmid;
    PERFORM public.sphotelinternalusage_replaceitems(p_internalusageid, p_farmid, p_itemsjson);
END $function$;

CREATE FUNCTION public.sphotelinternalusage_delete(p_internalusageid int, p_farmid text, p_userid text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE v_status text; v_open numeric;
BEGIN
    SELECT h.status INTO v_status FROM public.hotelinternalusage h
    WHERE  h.internalusageid = p_internalusageid AND h.farmid = p_farmid FOR UPDATE;
    IF v_status IS NULL THEN RETURN; END IF;
    IF v_status NOT IN ('Draft', 'Reversed') THEN
        RAISE EXCEPTION 'A % record cannot be deleted -- reverse it first, so the stock history survives.', v_status;
    END IF;
    SELECT COALESCE(SUM(s.quantity), 0) INTO v_open FROM public.hotelinternalusagestock s
    WHERE  s.internalusageid = p_internalusageid AND s.reversedat IS NULL;
    IF v_open <> 0 THEN
        RAISE EXCEPTION 'This record is marked Reversed but % units are still out of stock. Reverse it properly before deleting it.', trim_scale(v_open);
    END IF;
    -- The draws stay (they carry the record's reference); the stock rows go.
    UPDATE public.hotelsupplydraws d SET sourceid = NULL
    WHERE  d.drawtype IN ('InternalUse', 'InternalUseReversal')
      AND  d.sourceid IN (SELECT s.usagestockid FROM public.hotelinternalusagestock s WHERE s.internalusageid = p_internalusageid);
    DELETE FROM public.hotelinternalusage WHERE internalusageid = p_internalusageid AND farmid = p_farmid;
END $function$;

CREATE FUNCTION public.sphotelinternalusage_post(p_internalusageid int, p_farmid text, p_postedby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE v_h record; v_total numeric(14,2); v_stock numeric; v_name text; v_cost numeric(14,2); v_ref text; v_sid int; n record;
BEGIN
    SELECT * INTO v_h FROM public.hotelinternalusage h
    WHERE  h.internalusageid = p_internalusageid AND h.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Internal use record % not found.', p_internalusageid; END IF;
    IF v_h.status = 'Posted' THEN RETURN; END IF;
    IF v_h.status NOT IN ('Draft', 'Reversed') THEN RAISE EXCEPTION 'Cannot post a % record.', v_h.status; END IF;
    IF v_h.usagedate > CURRENT_DATE THEN RAISE EXCEPTION 'The date cannot be in the future.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.hotelinternalusageitems WHERE internalusageid = p_internalusageid) THEN
        RAISE EXCEPTION 'Add at least one product before posting.';
    END IF;
    IF EXISTS (SELECT 1 FROM public.hotelinternalusagestock s WHERE s.internalusageid = p_internalusageid AND s.reversedat IS NULL) THEN
        RAISE EXCEPTION 'This record already has stock out. Reverse it first.';
    END IF;

    UPDATE public.hotelinternalusageitems i
    SET    entryunitcost = COALESCE(public.fnhotelinternalusage_unitcost(p_farmid, i.hotelinventoryitemid), 0)
    WHERE  i.internalusageid = p_internalusageid AND i.entryunitcost = 0;
    UPDATE public.hotelinternalusageitems SET totalcost = ROUND(entryquantity * entryunitcost, 2)
    WHERE  internalusageid = p_internalusageid;

    -- Pre-flight: refuse the whole record rather than drive an item negative.
    FOR n IN SELECT i.hotelinventoryitemid AS itemid, SUM(i.entryquantity) AS qty
             FROM public.hotelinternalusageitems i WHERE i.internalusageid = p_internalusageid
             GROUP BY i.hotelinventoryitemid ORDER BY i.hotelinventoryitemid
    LOOP
        SELECT COALESCE(g.stockonhand, 0), g.name INTO v_stock, v_name FROM public.hotelinventoryitems g
        WHERE  g.hotelinventoryitemid = n.itemid AND g.farmid = p_farmid FOR UPDATE;
        IF v_name IS NULL THEN RAISE EXCEPTION 'Pick a supply item of this hotel.'; END IF;
        IF n.qty > v_stock THEN
            RAISE EXCEPTION 'Not enough %: % in stock, % needed.', v_name, trim_scale(v_stock), trim_scale(n.qty);
        END IF;
    END LOOP;

    v_ref := COALESCE(v_h.referenceno, 'IU #' || p_internalusageid);
    FOR n IN SELECT i.hotelinventoryitemid AS itemid, SUM(i.entryquantity) AS qty
             FROM public.hotelinternalusageitems i WHERE i.internalusageid = p_internalusageid
             GROUP BY i.hotelinventoryitemid ORDER BY i.hotelinventoryitemid
    LOOP
        INSERT INTO public.hotelinternalusagestock (internalusageid, farmid, hotelinventoryitemid, quantity)
        VALUES (p_internalusageid, p_farmid, n.itemid, n.qty) RETURNING usagestockid INTO v_sid;
        v_cost := public.fnhotelsupply_draw(p_farmid, n.itemid, n.qty, 'InternalUse', v_sid, v_h.usagedate,
                                            'Internal use ' || v_ref, p_postedby);
        UPDATE public.hotelinventoryitems SET stockonhand = stockonhand - n.qty, updatedat = now()
        WHERE  hotelinventoryitemid = n.itemid;
        PERFORM public.fnhotelsupply_refreshcost(n.itemid);
        UPDATE public.hotelinternalusagestock SET deferredcost = COALESCE(v_cost, 0) WHERE usagestockid = v_sid;
    END LOOP;

    SELECT COALESCE(SUM(totalcost), 0) INTO v_total FROM public.hotelinternalusageitems WHERE internalusageid = p_internalusageid;
    UPDATE public.hotelinternalusage
    SET    status = 'Posted', totalcostvalue = v_total, postedby = p_postedby, postedat = now(),
           reversedby = NULL, reversedat = NULL, reversalreason = NULL, updatedat = now()
    WHERE  internalusageid = p_internalusageid;
END $function$;

-- Reverse: stock back today; every draw handed back to its lot with a
-- negative-cost draw dated today, so the P&L takes it back on that day.
CREATE FUNCTION public.sphotelinternalusage_reverse(p_internalusageid int, p_farmid text, p_reason text DEFAULT NULL,
                                                    p_reversedby text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE v_h record; v_ref text; s record; d record;
BEGIN
    SELECT * INTO v_h FROM public.hotelinternalusage h
    WHERE  h.internalusageid = p_internalusageid AND h.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Internal use record % not found.', p_internalusageid; END IF;
    IF v_h.status = 'Reversed' THEN RETURN; END IF;
    IF v_h.status <> 'Posted' THEN RAISE EXCEPTION 'Only a posted record can be reversed. This one is %.', v_h.status; END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'A reason is required to reverse this internal use.'; END IF;

    v_ref := COALESCE(v_h.referenceno, 'IU #' || p_internalusageid);
    FOR s IN SELECT * FROM public.hotelinternalusagestock x
             WHERE x.internalusageid = p_internalusageid AND x.reversedat IS NULL
             ORDER BY x.hotelinventoryitemid FOR UPDATE
    LOOP
        PERFORM 1 FROM public.hotelinventoryitems i WHERE i.hotelinventoryitemid = s.hotelinventoryitemid FOR UPDATE;
        FOR d IN SELECT * FROM public.hotelsupplydraws x
                 WHERE x.drawtype = 'InternalUse' AND x.sourceid = s.usagestockid ORDER BY x.drawid
        LOOP
            IF d.purchaseid IS NOT NULL THEN
                UPDATE public.hotelsupplypurchases
                SET    remainingquantity = remainingquantity + d.quantity, deferredremainingcost = deferredremainingcost + d.deferredcost
                WHERE  purchaseid = d.purchaseid AND status = 'Posted';
                IF NOT FOUND THEN
                    RAISE EXCEPTION 'The purchase this stock came from (PO-%) is no longer on the books, so the stock cannot go back to it.', d.purchaseid;
                END IF;
            END IF;
            INSERT INTO public.hotelsupplydraws (farmid, hotelinventoryitemid, purchaseid, drawtype, sourceid, drawdate,
                                                 quantity, unitcost, costmode, deferredcost, reference, createdby)
            VALUES (p_farmid, d.hotelinventoryitemid, d.purchaseid, 'InternalUseReversal', s.usagestockid, CURRENT_DATE,
                    d.quantity, d.unitcost, d.costmode, -d.deferredcost, 'Reversal of internal use ' || v_ref, p_reversedby);
        END LOOP;
        UPDATE public.hotelinventoryitems SET stockonhand = COALESCE(stockonhand, 0) + s.quantity, updatedat = now()
        WHERE  hotelinventoryitemid = s.hotelinventoryitemid;
        PERFORM public.fnhotelsupply_refreshcost(s.hotelinventoryitemid);
        UPDATE public.hotelinternalusagestock SET reversedat = now() WHERE usagestockid = s.usagestockid;
    END LOOP;

    UPDATE public.hotelinternalusage
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = now(), reversalreason = btrim(p_reason), updatedat = now()
    WHERE  internalusageid = p_internalusageid;
END $function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Deferred inventory cost (Poultry 288, the Restaurant 329 columns)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.fnhotelsupply_deferredrows(p_farmid text)
RETURNS TABLE(purchaseid int, purchasedate date, itemid int, itemname text, category text, unit text,
              supplierid int, suppliername text, purchasedquantity numeric, consumedquantity numeric,
              remainingquantity numeric, operationalcost numeric, deferredtotalcost numeric, recognizedcost numeric,
              deferredremainingcost numeric, recognitionpercent numeric, allocatedrecognizedcost numeric,
              recognitiondrift numeric, costrecognitionmethod text, recognitionmethodlabel text, status text,
              exceptionreason text, recognitionevents int, lastrecognitiondate date, costingmethod text,
              queueposition int, quantityaheadinqueue numeric)
LANGUAGE sql STABLE AS $function$
    WITH lots AS (
        SELECT p.*, i.name AS iname, i.category AS icat, COALESCE(i.stockonhand, 0) AS stock,
               COALESCE(s.suppliername, p.suppliername) AS sname,
               COALESCE((SELECT SUM(d.deferredcost) FROM public.hotelsupplydraws d WHERE d.purchaseid = p.purchaseid), 0) AS drawn,
               (SELECT COUNT(*)::int FROM public.hotelsupplydraws d WHERE d.purchaseid = p.purchaseid AND d.deferredcost <> 0) AS events,
               (SELECT MAX(d.drawdate) FROM public.hotelsupplydraws d WHERE d.purchaseid = p.purchaseid AND d.deferredcost <> 0) AS lastdate
        FROM   public.hotelsupplypurchases p
        JOIN   public.hotelinventoryitems i ON i.hotelinventoryitemid = p.hotelinventoryitemid
        LEFT   JOIN public.hotelsuppliers s ON s.hotelsupplierid = p.hotelsupplierid
        WHERE  p.farmid = p_farmid AND p.status = 'Posted'
    ), q AS (
        SELECT l.purchaseid,
               (ROW_NUMBER() OVER (PARTITION BY l.hotelinventoryitemid ORDER BY l.purchasedate, l.purchaseid))::int AS pos,
               GREATEST(l.stock - SUM(l.remainingquantity) OVER (PARTITION BY l.hotelinventoryitemid), 0)
               + COALESCE(SUM(l.remainingquantity) OVER (PARTITION BY l.hotelinventoryitemid ORDER BY l.purchasedate, l.purchaseid
                                                          ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS ahead
        FROM   lots l WHERE l.remainingquantity > 0
    )
    SELECT l.purchaseid, l.purchasedate, l.hotelinventoryitemid, l.iname::text, l.icat::text, l.unit::text,
           l.hotelsupplierid, l.sname::text, l.quantity, l.quantity - l.remainingquantity, l.remainingquantity,
           l.totalcost, l.deferredtotalcost, (l.deferredtotalcost - l.deferredremainingcost)::numeric(14,2),
           l.deferredremainingcost,
           CASE WHEN l.deferredtotalcost > 0
                THEN ROUND((l.deferredtotalcost - l.deferredremainingcost) / l.deferredtotalcost * 100, 1) ELSE 0 END,
           l.drawn::numeric(14,2),
           ((l.deferredtotalcost - l.deferredremainingcost) - l.drawn)::numeric(14,2),
           l.costmode,
           CASE WHEN l.costmode = 'EXPENSE_WHEN_CONSUMED' THEN 'Expense when used' ELSE 'Expense when purchased' END,
           CASE WHEN (l.remainingquantity = 0 AND l.deferredremainingcost > 0)
                  OR ABS((l.deferredtotalcost - l.deferredremainingcost) - l.drawn) > 0.05 THEN 'Exception'
                WHEN l.costmode = 'EXPENSE_WHEN_PURCHASED' OR l.deferredtotalcost = 0 THEN 'Expensed at purchase'
                WHEN l.deferredremainingcost >= l.deferredtotalcost THEN 'Not yet expensed'
                WHEN l.deferredremainingcost <= 0 THEN 'Fully expensed'
                ELSE 'Partly expensed' END,
           CASE WHEN l.remainingquantity = 0 AND l.deferredremainingcost > 0
                  THEN 'Cost is still deferred but none of this stock is left.'
                WHEN ABS((l.deferredtotalcost - l.deferredremainingcost) - l.drawn) > 0.05
                  THEN 'Lot balance says ' || (l.deferredtotalcost - l.deferredremainingcost) || '; its usages say ' || l.drawn || '.'
           END::text,
           l.events, l.lastdate, 'FIFO'::text, q.pos, COALESCE(q.ahead, 0)::numeric
    FROM   lots l LEFT JOIN q ON q.purchaseid = l.purchaseid;
$function$;

CREATE FUNCTION public.sphotelsupply_deferred_getall(p_farmid text, p_scope text DEFAULT 'DEFERRED',
                                                     p_itemid int DEFAULT NULL, p_supplierid int DEFAULT NULL,
                                                     p_category text DEFAULT NULL, p_fromdate date DEFAULT NULL,
                                                     p_todate date DEFAULT NULL, p_search text DEFAULT NULL)
RETURNS TABLE(purchaseid int, purchasedate date, itemid int, itemname text, category text, unit text,
              supplierid int, suppliername text, purchasedquantity numeric, consumedquantity numeric,
              remainingquantity numeric, operationalcost numeric, deferredtotalcost numeric, recognizedcost numeric,
              deferredremainingcost numeric, recognitionpercent numeric, allocatedrecognizedcost numeric,
              recognitiondrift numeric, costrecognitionmethod text, recognitionmethodlabel text, status text,
              exceptionreason text, recognitionevents int, lastrecognitiondate date, costingmethod text,
              queueposition int, quantityaheadinqueue numeric)
LANGUAGE sql STABLE AS $function$
    SELECT r.* FROM public.fnhotelsupply_deferredrows(p_farmid) r
    WHERE  CASE upper(COALESCE(p_scope, 'DEFERRED'))
                WHEN 'DEFERRED'   THEN r.deferredremainingcost > 0
                WHEN 'RECOGNIZED' THEN r.deferredtotalcost > 0 AND r.deferredremainingcost <= 0
                WHEN 'EXCEPTION'  THEN r.status = 'Exception'
                ELSE TRUE END
      AND  (p_itemid IS NULL OR r.itemid = p_itemid)
      AND  (p_supplierid IS NULL OR r.supplierid = p_supplierid)
      AND  (p_category IS NULL OR lower(r.category) = lower(p_category))
      AND  (p_fromdate IS NULL OR r.purchasedate >= p_fromdate)
      AND  (p_todate IS NULL OR r.purchasedate <= p_todate)
      AND  (p_search IS NULL OR btrim(p_search) = ''
            OR r.itemname ILIKE '%' || btrim(p_search) || '%'
            OR COALESCE(r.suppliername, '') ILIKE '%' || btrim(p_search) || '%'
            OR r.purchaseid::text = regexp_replace(btrim(p_search), '^(PO-|#)', '', 'i'))
    ORDER  BY r.purchasedate DESC, r.purchaseid DESC;
$function$;

CREATE FUNCTION public.sphotelsupply_deferred_summary(p_farmid text, p_scope text DEFAULT 'DEFERRED',
                                                      p_itemid int DEFAULT NULL, p_supplierid int DEFAULT NULL,
                                                      p_category text DEFAULT NULL, p_fromdate date DEFAULT NULL,
                                                      p_todate date DEFAULT NULL, p_search text DEFAULT NULL)
RETURNS TABLE(remainingdeferredcost numeric, recognizedcost numeric, deferredbasis numeric, operationalcost numeric,
              purchasecount int, deferredpurchases int, fullyrecognized int, notrecognized int, exceptions int,
              exceptiondrift numeric, recognitionpercent numeric, blockedpurchases int, blockedcost numeric)
LANGUAGE sql STABLE AS $function$
    WITH r AS (SELECT * FROM public.sphotelsupply_deferred_getall(p_farmid, p_scope, p_itemid, p_supplierid,
                                                                   p_category, p_fromdate, p_todate, p_search))
    SELECT COALESCE(SUM(r.deferredremainingcost), 0)::numeric(14,2),
           COALESCE(SUM(r.recognizedcost), 0)::numeric(14,2),
           COALESCE(SUM(r.deferredtotalcost), 0)::numeric(14,2),
           COALESCE(SUM(r.operationalcost), 0)::numeric(14,2),
           COUNT(*)::int,
           COUNT(*) FILTER (WHERE r.deferredremainingcost > 0)::int,
           COUNT(*) FILTER (WHERE r.deferredtotalcost > 0 AND r.deferredremainingcost <= 0)::int,
           COUNT(*) FILTER (WHERE r.deferredtotalcost > 0 AND r.recognizedcost = 0)::int,
           COUNT(*) FILTER (WHERE r.status = 'Exception')::int,
           COALESCE(SUM(r.recognitiondrift) FILTER (WHERE r.status = 'Exception'), 0)::numeric(14,2),
           CASE WHEN COALESCE(SUM(r.deferredtotalcost), 0) > 0
                THEN ROUND(SUM(r.recognizedcost) / SUM(r.deferredtotalcost) * 100, 1) ELSE 0 END,
           COUNT(*) FILTER (WHERE r.deferredremainingcost > 0 AND r.quantityaheadinqueue > 0)::int,
           COALESCE(SUM(r.deferredremainingcost) FILTER (WHERE r.quantityaheadinqueue > 0), 0)::numeric(14,2)
    FROM   r;
$function$;

CREATE FUNCTION public.sphotelsupply_deferred_history(p_farmid text, p_purchaseid int)
RETURNS TABLE(drawid int, useddate date, sourcetype text, sourcelabel text, quantitydrawn numeric, unit text,
              unitcostatdraw numeric, operationalcost numeric, recognizedcost numeric, recognitionoutcome text,
              isreversed boolean)
LANGUAGE sql STABLE AS $function$
    SELECT d.drawid, d.drawdate,
           CASE d.drawtype WHEN 'InternalUse' THEN 'Internal use' WHEN 'InternalUseReversal' THEN 'Internal use reversed'
                           WHEN 'Shortfall' THEN 'Used before delivery' ELSE 'Adjustment' END::text,
           COALESCE(d.reference, d.drawtype)::text,
           d.quantity, p.unit, d.unitcost, ROUND(d.quantity * d.unitcost, 2), d.deferredcost,
           CASE WHEN d.costmode = 'EXPENSE_WHEN_CONSUMED' THEN 'Expensed now' ELSE 'Already expensed at purchase' END::text,
           (d.drawtype = 'InternalUseReversal')
    FROM   public.hotelsupplydraws d
    JOIN   public.hotelsupplypurchases p ON p.purchaseid = d.purchaseid
    WHERE  d.farmid = p_farmid AND d.purchaseid = p_purchaseid
    ORDER  BY d.drawdate, d.drawid;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Supplier Balances / Payments (332's bodies) gain the 'Purchase' document.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fnhotel_payables(p_farmid text)
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
    -- 334: a supply purchase: what was not paid when it was recorded.
    SELECT 'Purchase'::text, p.purchaseid, p.hotelsupplierid, p.purchasedate,
           (i.name || ' - ' || trim_scale(p.quantity)::text || COALESCE(' ' || p.unit, ''))::text,
           ('PO-' || p.purchaseid)::text,
           p.totalcost, p.amountpaid, a.x, (p.amountpaid + a.x)::numeric(14,2),
           GREATEST(p.totalcost - p.amountpaid - a.x, 0)::numeric(14,2), p.hotelcashaccountid,
           COALESCE(p.duedate, p.purchasedate + COALESCE(s.paymenttermdays, 0))
    FROM   public.hotelsupplypurchases p
    JOIN   public.hotelinventoryitems i ON i.hotelinventoryitemid = p.hotelinventoryitemid
    LEFT   JOIN public.hotelsuppliers s ON s.hotelsupplierid = p.hotelsupplierid
    CROSS  JOIN LATERAL (SELECT public.fnhotel_allocated(p_farmid, 'Purchase', p.purchaseid) AS x) a
    WHERE  p.farmid = p_farmid AND p.status = 'Posted' AND p.hotelsupplierid IS NOT NULL
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

CREATE OR REPLACE FUNCTION public.fnhotelsupplierpayment_apply(p_farmid text, p_paymentid int, p_allocations jsonb, p_by text)
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
      AND  COALESCE(x.documenttype, '') NOT IN ('Expense', 'AssetCost', 'OpeningBalance', 'Purchase');
    IF v_bad > 0 THEN RAISE EXCEPTION 'Unknown document type. Expected Purchase, Expense, AssetCost or OpeningBalance.'; END IF;

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


-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Cash Flow: 332's rows and detail, byte for byte, plus arms 16 / 16b.
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

    -- ---- 16. supply purchases paid now (334) ----------------------------------
    -- Only the amount paid when the delivery was recorded; the rest leaves as a
    -- supplier payment (arm 9). On its day even if reversed later (16b).
    IF to_regclass('public.hotelsupplypurchases') IS NOT NULL THEN
        RETURN QUERY
        SELECT 'SupplyPurchase'::text,
               FALSE,
               p.purchaseid,
               p.hotelcashaccountid,
               NULL::text,
               p.purchasedate::timestamp,
               'CashOut'::text,
               'SupplyPurchase'::text,
               p.purchaseid,
               FALSE,
               -(p.amountpaid::numeric),
               ('Purchase PO-' || p.purchaseid || ': ' || COALESCE(i.name, 'supplies')
                || COALESCE(' (' || NULLIF(btrim(p.suppliername), '') || ')', ''))::text,
               'OperatingOut'::text,
               p.createdat::timestamp
        FROM   hotelsupplypurchases p
        LEFT   JOIN hotelinventoryitems i ON i.hotelinventoryitemid = p.hotelinventoryitemid
        WHERE  lower(p.farmid::text) = lower(p_farmid)
          AND  p.cashtransactionid IS NOT NULL
          AND  p.amountpaid > 0
          AND  p.purchasedate::timestamp >= v_from
          AND  p.purchasedate::timestamp <= v_to;

        -- ---- 16b. purchase reversed: the money paid comes back (334) --------
        RETURN QUERY
        SELECT 'SupplyPurchaseReversal'::text,
               FALSE,
               p.purchaseid,
               p.hotelcashaccountid,
               NULL::text,
               p.reversedat::timestamp,
               'CashIn'::text,
               'SupplyPurchaseReversal'::text,
               p.purchaseid,
               FALSE,
               p.amountpaid::numeric,
               ('Reversal of purchase PO-' || p.purchaseid || COALESCE(' - ' || NULLIF(btrim(p.reversalreason), ''), ''))::text,
               'OperatingIn'::text,
               p.reversedat::timestamp
        FROM   hotelsupplypurchases p
        WHERE  lower(p.farmid::text) = lower(p_farmid)
          AND  p.reversalcashtransactionid IS NOT NULL
          AND  p.amountpaid > 0
          AND  p.reversedat::timestamp >= v_from
          AND  p.reversedat::timestamp <= v_to;
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
               WHEN r.rowsource IN ('CustomerPayment', 'CustomerPaymentReversal') THEN 'Customer payments'
               WHEN r.rowsource IN ('SupplierPayment', 'SupplierPaymentReversal') THEN 'Supplier payments'
               WHEN r.rowsource IN ('CapitalAsset', 'CapitalAssetReversal') THEN 'Capital Asset'
               WHEN r.rowsource IN ('SupplyPurchase', 'SupplyPurchaseReversal') THEN 'Supplies'
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
-- 9. Profit & Loss: 331's lines and expense drilldown plus the two supply lines
--    (Operating Expenses; plsummary already sums every OperatingExpense line).
-- ─────────────────────────────────────────────────────────────────────────────
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
    -- Depreciation & Financing (331): the cost of borrowing. Interest and fees
    -- from each posted loan repayment -- Poultry 272's LoanInterest / LoanFees
    -- lines. The principal is NOT here: repaying it is not a cost. The cash for
    -- the whole repayment is one Financing row on Cash Flow; this is the P&L's
    -- view of the same payment, so nothing is counted twice.
    oth_loaninterest AS (
        SELECT 'OtherCost'::text        AS sec,
               'LoanInterest'           AS k,
               'Loan Interest'          AS lbl,
               ROUND(COALESCE(SUM(p.interestamount), 0), 2) AS amt,
               310                      AS so,
               FALSE                    AS info,
               COUNT(*)::integer        AS n
        FROM   hotelloanpayments p
        WHERE  lower(p.farmid::text) = lower(p_farmid)
          AND  p.status = 'Posted'
          AND  p.interestamount > 0
          AND  p.paymentdate::date >= p_startdate
          AND  p.paymentdate::date <= p_enddate
    ),
    oth_loanfees AS (
        SELECT 'OtherCost'::text        AS sec,
               'LoanFees'               AS k,
               'Loan Fees & Charges'    AS lbl,
               ROUND(COALESCE(SUM(p.feeamount), 0), 2) AS amt,
               320                      AS so,
               FALSE                    AS info,
               COUNT(*)::integer        AS n
        FROM   hotelloanpayments p
        WHERE  lower(p.farmid::text) = lower(p_farmid)
          AND  p.status = 'Posted'
          AND  p.feeamount > 0
          AND  p.paymentdate::date >= p_startdate
          AND  p.paymentdate::date <= p_enddate
    ),
    -- 334: supplies, each unit's cost exactly once. Stock expensed when
    -- purchased: the whole purchase on its date. Stock expensed when consumed:
    -- the deferred cost each draw moved (internal use; a reversal is negative,
    -- on its day). Stock that never came through a purchase costs nothing here.
    exp_suppliespurchased AS (
        SELECT 'OperatingExpense'::text AS sec,
               'SuppliesPurchased'      AS k,
               'Supplies purchased'     AS lbl,
               ROUND(COALESCE(SUM(p.totalcost), 0), 2) AS amt,
               210                      AS so,
               FALSE                    AS info,
               COUNT(*)::integer        AS n
        FROM   hotelsupplypurchases p
        WHERE  lower(p.farmid::text) = lower(p_farmid)
          AND  p.status = 'Posted'
          AND  p.costmode = 'EXPENSE_WHEN_PURCHASED'
          AND  p.totalcost > 0
          AND  p.purchasedate >= p_startdate
          AND  p.purchasedate <= p_enddate
    ),
    exp_suppliesused AS (
        SELECT 'OperatingExpense'::text AS sec,
               'SuppliesUsed'           AS k,
               'Supplies used'          AS lbl,
               ROUND(COALESCE(SUM(d.deferredcost), 0), 2) AS amt,
               220                      AS so,
               FALSE                    AS info,
               COUNT(*)::integer        AS n
        FROM   hotelsupplydraws d
        WHERE  lower(d.farmid::text) = lower(p_farmid)
          AND  d.deferredcost <> 0
          AND  d.drawdate >= p_startdate
          AND  d.drawdate <= p_enddate
    ),
    all_lines AS (
        SELECT * FROM rev_payments
        UNION ALL SELECT * FROM rev_restaurant
        UNION ALL SELECT * FROM rev_loaninterest
        UNION ALL SELECT * FROM exp_payroll
        UNION ALL SELECT * FROM exp_by_cat
        UNION ALL SELECT * FROM exp_suppliespurchased
        UNION ALL SELECT * FROM exp_suppliesused
        UNION ALL SELECT * FROM oth_depreciation
        UNION ALL SELECT * FROM oth_loaninterest
        UNION ALL SELECT * FROM oth_loanfees
    )
    SELECT a.sec, a.k, a.lbl, a.amt, a.so, a.info, a.n
    FROM   all_lines a
    WHERE  a.amt <> 0
    ORDER  BY a.so, a.lbl;
$function$;

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

        UNION ALL

        -- 331: the interest / fee parts of loan repayments, when their line is opened.
        SELECT p.hotelloanpaymentid,
               p.paymentdate::date,
               CASE WHEN p_linekey = 'LoanInterest' THEN 'Loan Interest' ELSE 'Loan Fees & Charges' END::text,
               ((CASE WHEN p_linekey = 'LoanInterest' THEN 'Interest on loan ' ELSE 'Fee on loan ' END)
                || COALESCE(l.loannumber, '#' || l.hotelloanid::text)
                || COALESCE(' - ' || p.paymentnumber, ''))::text,
               CASE WHEN p_linekey = 'LoanInterest' THEN p.interestamount ELSE p.feeamount END,
               l.lendername::text,
               'NonCash'::text,
               p.status::text,
               p_linekey::text
        FROM   hotelloanpayments p
        JOIN   hotelloans l ON l.hotelloanid = p.hotelloanid
        WHERE  p_linekey IN ('LoanInterest', 'LoanFees')
          AND  lower(p.farmid::text) = lower(p_farmid)
          AND  p.status = 'Posted'
          AND  (CASE WHEN p_linekey = 'LoanInterest' THEN p.interestamount ELSE p.feeamount END) > 0
          AND  p.paymentdate::date >= p_startdate
          AND  p.paymentdate::date <= p_enddate

        UNION ALL

        -- 334: the supply lines, when opened.
        SELECT p.purchaseid,
               p.purchasedate,
               'Supplies purchased'::text,
               ('PO-' || p.purchaseid || ' ' || COALESCE(i.name, '') || ' x ' || trim_scale(p.quantity))::text,
               p.totalcost,
               p.suppliername::text,
               p.paymentmethod::text,
               p.status::text,
               'SuppliesPurchased'::text
        FROM   hotelsupplypurchases p
        LEFT   JOIN hotelinventoryitems i ON i.hotelinventoryitemid = p.hotelinventoryitemid
        WHERE  p_linekey = 'SuppliesPurchased'
          AND  lower(p.farmid::text) = lower(p_farmid)
          AND  p.status = 'Posted' AND p.costmode = 'EXPENSE_WHEN_PURCHASED' AND p.totalcost > 0
          AND  p.purchasedate >= p_startdate AND p.purchasedate <= p_enddate

        UNION ALL

        SELECT d.drawid,
               d.drawdate,
               'Supplies used'::text,
               (COALESCE(i.name, '') || ' x ' || trim_scale(d.quantity) || COALESCE(' - ' || d.reference, ''))::text,
               d.deferredcost,
               NULL::text,
               'NonCash'::text,
               d.drawtype::text,
               'SuppliesUsed'::text
        FROM   hotelsupplydraws d
        LEFT   JOIN hotelinventoryitems i ON i.hotelinventoryitemid = d.hotelinventoryitemid
        WHERE  p_linekey = 'SuppliesUsed'
          AND  lower(d.farmid::text) = lower(p_farmid)
          AND  d.deferredcost <> 0
          AND  d.drawdate >= p_startdate AND d.drawdate <= p_enddate
    ) x
    ORDER BY 2, 1;
$function$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 10. Verification (read-only)
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE v_missing text;
BEGIN
    SELECT string_agg(f, ', ') INTO v_missing
    FROM   unnest(ARRAY[
               'fnhotelsupply_costmode', 'sphotelsupply_costmode_list', 'sphotelsupply_costmode_set',
               'fnhotelsupply_refreshcost', 'fnhotelsupply_draw', 'sphotelsupplypurchase_create',
               'sphotelsupplypurchase_reverse', 'sphotelsupplypurchase_list', 'sphotelinternalusage_items',
               'sphotelinternalusage_getall', 'sphotelinternalusage_insert', 'sphotelinternalusage_update',
               'sphotelinternalusage_delete', 'sphotelinternalusage_post', 'sphotelinternalusage_reverse',
               'fnhotelsupply_deferredrows', 'sphotelsupply_deferred_getall', 'sphotelsupply_deferred_summary',
               'sphotelsupply_deferred_history', 'fnhotel_payables', 'fnhotelsupplierpayment_apply',
               'sphotelcashflow_rows', 'sphotelcashflow_detail', 'sphotelreport_pllines', 'sphotelreport_plexpensedetail'
           ]) f
    WHERE  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                       WHERE n.nspname = 'public' AND p.proname = f);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '334 verification failed, missing: %', v_missing;
    END IF;
END $$;
