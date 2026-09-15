-- =============================================================================
-- 265_PoultryDeferredCostTransfer.postgres.sql
--
-- Purpose
-- -------
-- Phase 2, part 2: fill in the deferred numbers 264 added. Two writers open
-- deferred cost, and one carries it from one lot into another.
--
--   the purchase          a deferred lot opens with its whole cost deferred
--   feed production       the deferred share of the ingredients moves into the
--                         finished-feed lot -- a TRANSFER, not an expense
--
-- Still nothing reaches Profit & Loss. That is 266.
--
-- THE PART THAT IS EASY TO GET WRONG
-- ==================================
-- A produced feed lot's deferred cost is NOT its production cost.
--
--   Maize   5,000  deferred        (the farm defers feed)
--   Premix  2,000  already expensed (the item overrides to expense on purchase)
--   -----------------------------------------------------------------------
--   totalcost         7,000   what the feed cost to make -- unchanged, and what
--                             cost-per-kg, formula analysis and the production
--                             reports go on reading
--   deferredtotalcost 5,000   what may still reach the P&L
--
-- Expensing 7,000 when that feed is eaten would charge the premix a second time.
-- So the finished-feed lot's deferred cost is the SUM OF WHAT WAS ACTUALLY
-- DEFERRED on the ingredient draws -- read from the allocations 264 now records,
-- never re-derived from settings, and never assumed to equal the production cost.
--
-- WHERE THE NUMBER COMES FROM
-- ---------------------------
-- After _consumebatches has run for an ingredient line, the deferred share of
-- that draw is sitting on poultryrawmaterialusagebatch.deferredcostdrawn. This
-- file sums it per batch. That means the transfer is exact by construction: the
-- feed lot receives precisely what the ingredient lots gave up, so no deferred
-- cost is created or destroyed by mixing feed.
--
-- BOUGHT DURING PRODUCTION
-- ========================
-- An ingredient can be bought and consumed in the same posting. That path
-- writes its own lot and immediately empties it, so it never went through the
-- ordinary purchase SP and never got a recognition snapshot. It gets one here,
-- resolved the same way any other purchase would be:
--
--   expensed on purchase   the ingredient's cost is already in the P&L (via the
--                          purchase's own expense), so it contributes 0 deferred
--   deferred               the cost is deferred and passes straight through into
--                          the finished feed
--
-- Either way the cash and supplier behaviour of that line is untouched: buying
-- and expensing are different events, as they have been since 262.
--
-- THE FINISHED-FEED LOT'S OWN SNAPSHOT
-- ====================================
-- It is set from the OUTCOME, not from the farm setting: a lot with deferred
-- cost is EXPENSE_WHEN_CONSUMED, one without is EXPENSE_WHEN_PURCHASED. A farm
-- that defers feed but happens to mix a batch entirely from already-expensed
-- ingredients produces a lot with nothing left to expense, and that lot should
-- say so rather than claiming a deferral it cannot honour.
--
-- EDITING A DEFERRED PURCHASE
-- ===========================
-- Changing the cost of a lot has to move its deferred balance with it, or the
-- two drift apart. This file rewrites the deferred figures on edit ONLY while
-- the lot is untouched -- nothing drawn from it yet. Once stock has been taken,
-- part of the deferred cost may already have been recognised downstream, and
-- silently rescaling it would rewrite an expense that has already been reported.
-- That case raises instead, which is the honest answer until 267 offers a
-- proper correction path.
--
-- EFFECT ON TODAY'S NUMBERS: none. Every existing lot is expensed-at-purchase
-- and stays at deferred 0, every farm is still on the default setting, and the
-- production-cost fields the reports read are untouched.
--
-- Order: after 264.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The purchase opens a deferred layer when its snapshot says so.
--
-- Reproduced from the LIVE definition, which already carries 262's expense gate.
-- The validations, the total-cost fallback, the amountpaid clamp, the stock
-- update and the expense gate are byte for byte what they were.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialpurchase_insert(p_farmid text, p_poultryrawmaterialitemid integer, p_suppliername text DEFAULT NULL::text, p_supplierid integer DEFAULT NULL::integer, p_purchasedate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_quantity numeric DEFAULT NULL::numeric, p_unitcost numeric DEFAULT NULL::numeric, p_totalcost numeric DEFAULT NULL::numeric, p_productionunit text DEFAULT NULL::text, p_productionunitsperpurchaseunit numeric DEFAULT NULL::numeric, p_paymentmethod text DEFAULT NULL::text, p_amountpaid numeric DEFAULT 0, p_receipturl text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text)
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
    v_method     text;
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

    -- 262. Resolve ONCE, here, and stamp it on the row below. Asked again
    -- later it could give a different answer, and a purchase that changes its
    -- mind about how it was treated is how a closed month's P&L moves.
    SELECT r.method INTO v_method
    FROM   fnpoultrycostrecognition_effective(
               p_farmid, p_poultryrawmaterialitemid, NULL,
               COALESCE(p_purchasedate, (now() at time zone 'utc'))::date) r;
    v_method := COALESCE(v_method, 'EXPENSE_WHEN_PURCHASED');

    INSERT INTO poultryrawmaterialpurchases (
        farmid, poultryrawmaterialitemid, suppliername, supplierid, purchasedate,
        quantity, unitcost, totalcost, productionunit, productionunitsperpurchaseunit,
        paymentmethod, amountpaid, receipturl, notes, createdby, remainingquantity,
        costrecognitionmethod, deferredtotalcost, deferredremainingcost
    )
    VALUES (
        p_farmid, p_poultryrawmaterialitemid, p_suppliername, p_supplierid, COALESCE(p_purchasedate, (now() at time zone 'utc')),
        p_quantity, p_unitcost, v_totalcost, p_productionunit, p_productionunitsperpurchaseunit,
        p_paymentmethod, v_amountpaid, p_receipturl, p_notes, p_createdby, p_quantity,  -- RemainingQuantity in PURCHASE units
        v_method,
        -- 265. A deferred lot opens with its WHOLE cost waiting, and an expensed
        -- one with none. Note this is totalcost, not amountpaid: what is deferred
        -- is the cost of the stock, and paying for it later is a cash event, not
        -- a costing one.
        CASE WHEN fnpoultrycostrecognition_expenseatpurchase(v_method) THEN 0 ELSE v_totalcost END,
        CASE WHEN fnpoultrycostrecognition_expenseatpurchase(v_method) THEN 0 ELSE v_totalcost END
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

    -- 262. The one new condition. A deferred purchase writes NO expense: its
    -- cost is inventory value until Phase 2 recognises it on consumption. Cash,
    -- supplier balance and stock quantity below are all untouched -- paying for
    -- something and expensing it are different events.
    IF (v_gid IS NOT NULL AND p_createdby IS NOT NULL AND v_amountpaid > 0
        AND fnpoultrycostrecognition_expenseatpurchase(v_method)) THEN
        INSERT INTO expense (expensedate, category, description, amount, paymentmethod, supplier, flockid, createddate, userid, farmid, sourcetype, sourceid)
        VALUES (COALESCE(p_purchasedate, (now() at time zone 'utc')), 'Raw Materials / Inventory Purchase',
                'Raw material purchase: ' || COALESCE(v_itemname, 'item') || ' (' || p_quantity::text || ' ' || COALESCE(v_unit, '') || ')',
                v_amountpaid, COALESCE(p_paymentmethod, 'Cash'), p_suppliername, NULL, (now() at time zone 'utc'), p_createdby, v_gid,
                'PoultryRawMaterialPurchase', v_newid);
    END IF;

    RETURN v_newid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. The edit keeps the deferred balance in step, or refuses.
--
-- Reproduced from the LIVE definition, which already carries 262's expense gate.
-- The quantity guards, the already-drawn check, the stock delta and the expense
-- rebalancing are unchanged.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialpurchase_update(p_poultryrawmaterialpurchaseid integer, p_farmid text, p_suppliername text DEFAULT NULL::text, p_supplierid integer DEFAULT NULL::integer, p_purchasedate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_quantity numeric DEFAULT NULL::numeric, p_unitcost numeric DEFAULT NULL::numeric, p_totalcost numeric DEFAULT NULL::numeric, p_productionunit text DEFAULT NULL::text, p_productionunitsperpurchaseunit numeric DEFAULT NULL::numeric, p_paymentmethod text DEFAULT NULL::text, p_amountpaid numeric DEFAULT 0, p_receipturl text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
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
    v_unit         text;    v_method      text;
    v_deferredmethod text;
    v_drawnalready   numeric;

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

    -- 265. Keep the deferred balance in step with the cost, but only while the
    -- lot is untouched. Once stock has been drawn, some of that deferred cost may
    -- already have been recognised downstream, and quietly rescaling it would
    -- rewrite an expense that has already been reported.
    SELECT pu.costrecognitionmethod, (pu.quantity - pu.remainingquantity)
    INTO   v_deferredmethod, v_drawnalready
    FROM   poultryrawmaterialpurchases pu
    WHERE  pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid
      AND  pu.farmid = p_farmid;

    IF NOT fnpoultrycostrecognition_expenseatpurchase(v_deferredmethod) THEN
        IF COALESCE(v_drawnalready, 0) > 0.0005 AND v_totalcost <> (
               SELECT pu.totalcost FROM poultryrawmaterialpurchases pu
               WHERE pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid) THEN
            RAISE EXCEPTION 'This purchase defers its cost and stock has already been drawn from it, so the cost cannot be changed. Reverse the usage that drew from it first.';
        END IF;
        UPDATE poultryrawmaterialpurchases pu
        SET    deferredtotalcost = v_totalcost, deferredremainingcost = v_totalcost
        WHERE  pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid
          AND  pu.farmid = p_farmid;
    END IF;

    -- 262. A deferred purchase has no linked expense and must not grow one.
    -- Without this, editing such a purchase would run the repair path below,
    -- find no expense row, decide the books were broken, and create the very
    -- expense the insert deliberately withheld.
    SELECT pu.costrecognitionmethod INTO v_method
    FROM   poultryrawmaterialpurchases pu
    WHERE  pu.poultryrawmaterialpurchaseid = p_poultryrawmaterialpurchaseid
      AND  pu.farmid = p_farmid;

    IF (v_gid IS NOT NULL AND fnpoultrycostrecognition_expenseatpurchase(v_method)) THEN
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

-- -----------------------------------------------------------------------------
-- 3. Feed production transfers the deferred cost into the finished feed.
--
-- Reproduced from the LIVE definition. The stock guard, the ingredient loop, the
-- FIFO draws, the cost roll-up, the cash postings and the status transition are
-- all exactly what they were. What is added is the deferred tally: each line
-- reports what it gave up, and the finished-feed lot receives the sum.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryfeedproductionbatch_post(p_farmid text, p_poultryfeedproductionbatchid integer, p_postedby text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status             text;
    v_finishedfeeditemid integer;
    v_qtyproduced        numeric(14,3);
    v_batchnumber        text;
    v_productiondate     timestamp;
    v_outputunit         text;
    v_short              text := NULL;
    v_msg                text;
    v_cyclestart         timestamp;
    v_invcost            numeric(14,4);
    v_invportion         numeric(14,2);
    v_purportion         numeric(14,2);
    v_usageid            integer;
    v_purlotid           integer;
    v_purusageid         integer;
    v_ingcost            numeric(14,2);
    v_addcost            numeric(14,2);
    v_totcost            numeric(14,2);
    v_cpu                numeric(18,4);
    v_newbal             numeric(14,2);
    -- 265. What the ingredients gave up, and what the finished feed inherits.
    v_linedeferred       numeric(14,2);
    v_deferredtotal      numeric(14,2) := 0;
    v_purmethod          text;
    v_purdeferred        numeric(14,2);
    r                    record;
BEGIN
    SELECT b.status, b.finishedfeeditemid, b.quantityproduced,
           b.batchnumber, b.productiondate, b.outputunit
    INTO   v_status, v_finishedfeeditemid, v_qtyproduced,
           v_batchnumber, v_productiondate, v_outputunit
    FROM   poultryfeedproductionbatches b
    WHERE  b.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid AND b.farmid = p_farmid;

    IF v_status IS NULL    THEN RAISE EXCEPTION 'Feed production batch not found.'; END IF;
    IF v_status = 'Posted' THEN RAISE EXCEPTION 'Batch is already posted.'; END IF;
    -- A Reversed batch MAY be reposted: each cycle is scoped by CreatedAt/PostedAt.
    IF COALESCE(v_qtyproduced, 0) <= 0 THEN RAISE EXCEPTION 'Quantity produced must be greater than zero.'; END IF;

    IF NOT EXISTS (SELECT 1 FROM poultryfeedproductionbatchlines l
                   WHERE l.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid) THEN
        RAISE EXCEPTION 'Add at least one ingredient line before posting.';
    END IF;

    IF EXISTS (SELECT 1 FROM poultryfeedproductionbatchlines l
               WHERE l.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid
                 AND COALESCE(l.amountpaid, 0) > 0 AND l.paidfromcashaccountid IS NULL) THEN
        RAISE EXCEPTION 'Select a cash account for paid ingredient purchases.';
    END IF;
    IF EXISTS (SELECT 1 FROM poultryfeedproductionadditionalcosts c
               WHERE c.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid
                 AND COALESCE(c.amountpaid, 0) > 0 AND c.paidfromcashaccountid IS NULL) THEN
        RAISE EXCEPTION 'Select a cash account for paid production costs.';
    END IF;

    -- -------------------------------------------------------------------------
    -- Stock guard against the DRAWABLE LOT POOL, aggregated per ITEM.
    -- Tolerance 0.0005 matches ConsumeBatches and the reversal guard.
    -- -------------------------------------------------------------------------
    WITH need AS (
        SELECT   l.ingredientitemid AS itemid, SUM(COALESCE(l.inventoryquantityused, 0)) AS qty
        FROM     poultryfeedproductionbatchlines l
        WHERE    l.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid
        GROUP BY l.ingredientitemid
        HAVING   SUM(COALESCE(l.inventoryquantityused, 0)) > 0
    ),
    avail AS (
        SELECT n.itemid, n.qty,
               it.itemname AS itemname,
               COALESCE(NULLIF(it.unitofmeasure, ''), '') AS unit,
               COALESCE((
                   SELECT SUM(p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1))
                   FROM   poultryrawmaterialpurchases p
                   WHERE  p.poultryrawmaterialitemid = n.itemid AND p.farmid = p_farmid
                     AND  p.remainingquantity > 0), 0) AS pool
        FROM   need n
        JOIN   poultryrawmaterialitems it
               ON it.poultryrawmaterialitemid = n.itemid AND it.farmid = p_farmid
    )
    SELECT string_agg(
               a.itemname
               || ' needs '    || (a.qty::numeric(14,3))::text
               || ' but only ' || (a.pool::numeric(14,3))::text
               || CASE WHEN a.unit = '' THEN '' ELSE ' ' || a.unit END
               || ' is available.',
               ' ' ORDER BY a.itemname)
    INTO   v_short
    FROM   avail a
    WHERE  a.qty > a.pool + 0.0005;

    IF v_short IS NOT NULL THEN
        v_msg := left(
            'This batch needs more ingredient stock than is available. ' || v_short
          || ' Reduce the quantity produced, or set the short ingredients to "Bought During Production" so they are purchased with the batch.'
          || ' (Stock added by adjustment rather than by a recorded purchase cannot be drawn - record a purchase for it first.)', 2048);
        RAISE EXCEPTION '%', v_msg;
    END IF;

    -- One timestamp for the whole cycle: stamped on every row + stored as PostedAt,
    -- so reversal can select exactly this cycle's rows with CreatedAt >= PostedAt.
    v_cyclestart := (now() AT TIME ZONE 'utc');

    FOR r IN
        SELECT l.poultryfeedproductionbatchlineid AS lineid,
               l.ingredientitemid                 AS itemid,
               l.quantityused                     AS qty,
               COALESCE(l.inventoryquantityused, 0) AS invqty,
               COALESCE(l.purchasedquantityused, 0) AS purqty,
               COALESCE(l.purchasedunitcost, 0)     AS purunit,
               l.unitofmeasure                    AS unit,
               l.supplierid                       AS supplierid,
               l.suppliername                     AS suppliername,
               l.paymentmethod                    AS paymentmethod
        FROM   poultryfeedproductionbatchlines l
        WHERE  l.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid
        ORDER  BY l.sortorder, l.poultryfeedproductionbatchlineid
    LOOP
        v_invcost := 0; v_invportion := 0; v_purportion := 0; v_usageid := NULL;
        v_linedeferred := 0;

        -- Inventory portion: consume from real stock lots (authoritative cost).
        IF r.invqty > 0 THEN
            INSERT INTO poultryrawmaterialusage
                (farmid, poultryrawmaterialitemid, poultryfeedproductionbatchid, quantityused, notes, createdby, createdat)
            VALUES (p_farmid, r.itemid, p_poultryfeedproductionbatchid, r.invqty,
                    concat('Feed production ', v_batchnumber), p_postedby, v_cyclestart)
            RETURNING poultryrawmaterialusageid INTO v_usageid;

            v_invcost := sppoultryrawmaterialitem_consumebatches(
                             p_farmid    => p_farmid,
                             p_itemid    => r.itemid,
                             p_usageid   => v_usageid,
                             p_neededqty => r.invqty);

            UPDATE poultryrawmaterialitems it
            SET    currentquantity = it.currentquantity - r.invqty,
                   updatedat       = (now() AT TIME ZONE 'utc')
            WHERE  it.poultryrawmaterialitemid = r.itemid AND it.farmid = p_farmid;

            UPDATE poultryrawmaterialusage u SET unitcost = v_invcost
            WHERE  u.poultryrawmaterialusageid = v_usageid;

            v_invportion := (COALESCE(v_invcost, 0) * r.invqty)::numeric(14,2);

            -- 265. Read what the draw actually deferred rather than recomputing
            -- it: _consumebatches has just written the exact per-lot split, and
            -- some of the lots it drew from may have been expensed at purchase.
            v_linedeferred := v_linedeferred + COALESCE((
                SELECT SUM(b.deferredcostdrawn) FROM poultryrawmaterialusagebatch b
                WHERE  b.poultryrawmaterialusageid = v_usageid), 0);
        END IF;

        -- Purchased portion: a bought-and-consumed lot (net-zero stock) for audit.
        IF r.purqty > 0 THEN
            -- 265. This lot never went through the purchase SP, so it has no
            -- snapshot of its own. Resolve it exactly as that SP would.
            SELECT rr.method INTO v_purmethod
            FROM   fnpoultrycostrecognition_effective(
                       p_farmid, r.itemid, NULL, v_productiondate::date) rr;
            v_purmethod := COALESCE(v_purmethod, 'EXPENSE_WHEN_PURCHASED');
            v_purdeferred := CASE WHEN fnpoultrycostrecognition_expenseatpurchase(v_purmethod)
                                  THEN 0 ELSE (r.purqty * r.purunit)::numeric(14,2) END;

            INSERT INTO poultryrawmaterialpurchases
                (farmid, poultryrawmaterialitemid, suppliername, supplierid, purchasedate, quantity, unitcost, totalcost,
                 productionunit, productionunitsperpurchaseunit, remainingquantity, paymentmethod, amountpaid,
                 sourcefeedproductionbatchid, notes, createdby, createdat,
                 costrecognitionmethod, deferredtotalcost, deferredremainingcost)
            VALUES (p_farmid, r.itemid, r.suppliername, r.supplierid, v_productiondate, r.purqty, r.purunit,
                    (r.purqty * r.purunit)::numeric(14,2),
                    r.unit, 1, r.purqty, r.paymentmethod, (r.purqty * r.purunit)::numeric(14,2),
                    p_poultryfeedproductionbatchid, concat('Bought for feed production ', v_batchnumber),
                    p_postedby, v_cyclestart,
                    v_purmethod, v_purdeferred, v_purdeferred)
            RETURNING poultryrawmaterialpurchaseid INTO v_purlotid;

            INSERT INTO poultryrawmaterialusage
                (farmid, poultryrawmaterialitemid, poultryfeedproductionbatchid, quantityused, unitcost, notes, createdby, createdat)
            VALUES (p_farmid, r.itemid, p_poultryfeedproductionbatchid, r.purqty, r.purunit,
                    concat('Bought & consumed for feed production ', v_batchnumber), p_postedby, v_cyclestart)
            RETURNING poultryrawmaterialusageid INTO v_purusageid;

            -- Bought and consumed in one step, so the whole lot is drawn and
            -- its whole deferred cost passes into the batch.
            INSERT INTO poultryrawmaterialusagebatch
                (poultryrawmaterialusageid, poultryrawmaterialpurchaseid, quantitydrawn, unitcostatdraw, deferredcostdrawn)
            VALUES (v_purusageid, v_purlotid, r.purqty, r.purunit, v_purdeferred);

            UPDATE poultryrawmaterialpurchases p
            SET    remainingquantity = 0, deferredremainingcost = 0,
                   updatedat = (now() AT TIME ZONE 'utc')
            WHERE  p.poultryrawmaterialpurchaseid = v_purlotid;

            v_purportion := (r.purqty * r.purunit)::numeric(14,2);
            v_linedeferred := v_linedeferred + v_purdeferred;
        END IF;

        v_deferredtotal := v_deferredtotal + COALESCE(v_linedeferred, 0);

        UPDATE poultryfeedproductionbatchlines l
        SET    inventoryunitcost = v_invcost,
               totalcost         = v_invportion + v_purportion,
               unitcost          = ((v_invportion + v_purportion) / NULLIF(r.qty, 0))::numeric(18,4)
        WHERE  l.poultryfeedproductionbatchlineid = r.lineid;
    END LOOP;

    -- Roll up the finalised costs.
    v_ingcost := COALESCE((SELECT SUM(l.totalcost) FROM poultryfeedproductionbatchlines l
                           WHERE l.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid), 0);
    v_addcost := COALESCE((SELECT SUM(c.amount) FROM poultryfeedproductionadditionalcosts c
                           WHERE c.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid), 0);
    v_totcost := v_ingcost + v_addcost;
    v_cpu     := (v_totcost / NULLIF(v_qtyproduced, 0))::numeric(18,4);

    -- Produced finished-feed stock lot (consumable by flocks at cost/unit).
    -- 265. totalcost stays the OPERATIONAL production cost -- cost per kg,
    -- formula analysis and the production reports all read it and must not move.
    -- The deferred figure is separate and is only what the ingredients actually
    -- gave up, so an already-expensed ingredient cannot be charged twice.
    --
    -- The snapshot follows the outcome, not the farm setting: a batch mixed
    -- entirely from expensed stock has nothing left to expense and should say so
    -- rather than claim a deferral it cannot honour.
    --
    -- Additional costs (labour, milling, transport) are NOT deferred. They are
    -- their own expenses, recognised wherever they were entered; folding them
    -- into the feed's deferred cost would expense them a second time when the
    -- feed is eaten.
    INSERT INTO poultryrawmaterialpurchases
        (farmid, poultryrawmaterialitemid, suppliername, purchasedate, quantity, unitcost, totalcost,
         productionunit, productionunitsperpurchaseunit, remainingquantity, paymentmethod, amountpaid,
         sourcefeedproductionbatchid, notes, createdby, createdat,
         costrecognitionmethod, deferredtotalcost, deferredremainingcost)
    VALUES (p_farmid, v_finishedfeeditemid, 'Feed Production', v_productiondate, v_qtyproduced, v_cpu, v_totcost,
         v_outputunit, 1, v_qtyproduced, 'Production', v_totcost,
         p_poultryfeedproductionbatchid, concat('Produced feed ', v_batchnumber), p_postedby, v_cyclestart,
         CASE WHEN COALESCE(v_deferredtotal, 0) > 0
              THEN 'EXPENSE_WHEN_CONSUMED' ELSE 'EXPENSE_WHEN_PURCHASED' END,
         COALESCE(v_deferredtotal, 0), COALESCE(v_deferredtotal, 0));

    UPDATE poultryrawmaterialitems it
    SET    currentquantity = it.currentquantity + v_qtyproduced,
           updatedat       = (now() AT TIME ZONE 'utc')
    WHERE  it.poultryrawmaterialitemid = v_finishedfeeditemid AND it.farmid = p_farmid;

    -- Cash out - one posting per account (paid ingredient purchases + paid costs).
    FOR r IN
        WITH pay AS (
            SELECT l.paidfromcashaccountid AS acctid, SUM(COALESCE(l.amountpaid, 0)) AS paid
            FROM   poultryfeedproductionbatchlines l
            WHERE  l.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid
              AND  l.paidfromcashaccountid IS NOT NULL AND COALESCE(l.amountpaid, 0) > 0
            GROUP  BY l.paidfromcashaccountid
            UNION ALL
            SELECT c.paidfromcashaccountid, SUM(COALESCE(c.amountpaid, 0))
            FROM   poultryfeedproductionadditionalcosts c
            WHERE  c.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid
              AND  c.paidfromcashaccountid IS NOT NULL AND COALESCE(c.amountpaid, 0) > 0
            GROUP  BY c.paidfromcashaccountid
        )
        SELECT pay.acctid AS acctid, SUM(pay.paid)::numeric(14,2) AS paid
        FROM   pay GROUP BY pay.acctid HAVING SUM(pay.paid) > 0
    LOOP
        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance - r.paid, updatedat = (now() AT TIME ZONE 'utc')
        WHERE  a.poultrycashaccountid = r.acctid AND a.farmid = p_farmid;

        SELECT a.currentbalance INTO v_newbal
        FROM   poultrycashaccounts a
        WHERE  a.poultrycashaccountid = r.acctid AND a.farmid = p_farmid;

        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
             amount, balanceaftertransaction, description, createdby, createdat)
        VALUES (p_farmid, r.acctid, v_productiondate, 'CashOut', 'FeedProduction', p_poultryfeedproductionbatchid,
                -r.paid, v_newbal, concat('Feed production ', v_batchnumber), p_postedby, v_cyclestart);
    END LOOP;

    -- -> Posted. PostedAt = the cycle start (so reversal can scope this cycle).
    -- Clear any reversal stamp left from a prior reverse (repost case).
    UPDATE poultryfeedproductionbatches b
    SET    totalingredientcost = v_ingcost, totaladditionalcost = v_addcost, totalproductioncost = v_totcost,
           costperoutputunit = v_cpu, status = 'Posted', postedby = p_postedby, postedat = v_cyclestart,
           reversedby = NULL, reversedat = NULL, reversalreason = NULL, updatedat = (now() AT TIME ZONE 'utc')
    WHERE  b.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid AND b.farmid = p_farmid;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'no expensed lot carries deferred cost' AS check,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END AS result
FROM   poultryrawmaterialpurchases
WHERE  costrecognitionmethod = 'EXPENSE_WHEN_PURCHASED' AND deferredtotalcost <> 0

UNION ALL
SELECT 'no deferred lot is missing its cost',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   poultryrawmaterialpurchases
WHERE  costrecognitionmethod = 'EXPENSE_WHEN_CONSUMED' AND deferredtotalcost = 0

UNION ALL
-- Nothing existing may have changed: every farm is still on the default.
SELECT 'still nothing deferred anywhere',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   poultryrawmaterialpurchases
WHERE  deferredremainingcost > 0;
