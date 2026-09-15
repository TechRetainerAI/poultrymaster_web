-- =============================================================================
-- 278_WaterDeferredCostOpening.postgres.sql
--
-- Purpose
-- -------
-- Phase 2, part 2: fill in the deferred numbers 277 added. A deferred lot opens
-- with its whole cost deferred, and an edit to that lot carries the balance with
-- it.
--
-- Still nothing reaches Profit & Loss. That is 279.
--
-- WHY THIS IS NOT THE POULTRY FILE, AND WHY THE NAME CHANGED
-- ==========================================================
-- The plan in apply-water-cost-recognition.ps1 called stage 5 "the deferred cost
-- is opened at purchase and CARRIED THROUGH A PRODUCTION BATCH into the finished
-- product", mirroring poultry's 265. Half of that does not exist in water, so
-- this file is named for what it actually does.
--
-- Poultry feed production consumes ingredient lots and writes the finished feed
-- back as a lot IN THE SAME TABLE. A poultry lot can therefore be built out of
-- other lots, its deferred cost is the sum of what those ingredients gave up,
-- and 265 needs a genuine lot-to-lot transfer that neither creates nor destroys
-- deferred cost.
--
-- Water has no such path. Checked, not assumed:
--
--   * spwaterrawmaterialpurchase_insert is the ONLY function in the database
--     that INSERTs into waterrawmaterialpurchases. Every lot is bought; none is
--     produced.
--   * spwaterproductionbatch_approve consumes raw material through
--     _consumebatches and writes its output to waterstocktransactions as a
--     Restock of a waterproduct -- finished sachets or bottles, priced at
--     costperbag. Different table, different unit, different kind of thing.
--
-- So in water the production draw is not a transfer between lots, it is the END
-- of the deferred cost's life. 274 says so in as many words: "Phase 2 recognises
-- it as the stock is drawn by a production batch." Recognition at the draw is
-- 279's job, and there is nothing for this file to carry.
--
-- If water ever gains a produced raw-material lot (a blended concentrate, say),
-- poultry's 265 is the shape to copy, and the number to move is
-- SUM(waterrawmaterialusagebatch.deferredcostdrawn) for the batch -- read from
-- the allocations 277 records, never re-derived from settings.
--
-- WHOLE COST, NOT THE PAID PART
-- =============================
-- The lot opens at totalcost. What is still owed to the supplier has no bearing
-- on what the stock cost: a 1,000 credit purchase that defers holds 1,000 from
-- the day it is entered, rather than nothing-then-1,000 as it is paid. Deferral
-- is about WHEN a cost reaches the P&L, and cash-basis payment timing is exactly
-- the thing it is being taken out of.
--
-- EDITING A DEFERRED PURCHASE
-- ===========================
-- Poultry's 265 had to work hard here: rewrite the deferred figures ONLY while
-- the lot is untouched, and raise once stock has been drawn, because rescaling a
-- partly-recognised balance would rewrite an expense that has already been
-- reported.
--
-- Water needs none of that care, because it already refuses the dangerous case
-- outright. The first statement in spwaterrawmaterialpurchase_update is:
--
--   IF EXISTS (SELECT 1 FROM waterrawmaterialusagebatch ub WHERE ...)
--       RAISE EXCEPTION 'This purchase batch has already been drawn from by an
--                        approved production batch. Reopen that batch first.';
--
-- By the time the UPDATE below runs, nothing has ever been drawn from this lot,
-- no deferred cost can have been recognised downstream, and rewriting the pair
-- outright is not merely safe but exact. The check file pins that guard, so a
-- future relaxation of it cannot quietly take this file down with it.
--
-- EFFECT ON TODAY'S NUMBERS: none. The interlock -- still shut until 279 -- means
-- no lot can be EXPENSE_WHEN_CONSUMED, so both CASE expressions below take their
-- ELSE branch and write the zero that is already there.
--
-- Order: after 277. Before 279.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Refuse to run out of order.
-- -----------------------------------------------------------------------------
DO $guard$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE  table_name = 'waterrawmaterialpurchases'
          AND  column_name = 'deferredtotalcost'
    ) THEN
        RAISE EXCEPTION '278 requires 277 (waterrawmaterialpurchases.deferredtotalcost is missing).';
    END IF;
END
$guard$;

-- -----------------------------------------------------------------------------
-- 1. The purchase: open the deferred balance.
--
-- Reproduced from the LIVE definition, which is 275's. Everything outside the
-- blocks marked "-- 278." is what 275 left behind.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterrawmaterialpurchase_insert(p_farmid text, p_waterrawmaterialitemid integer, p_suppliername text DEFAULT NULL::text, p_purchasedate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_quantity numeric DEFAULT NULL::numeric, p_unitcost numeric DEFAULT NULL::numeric, p_paymentmethod text DEFAULT NULL::text, p_amountpaid numeric DEFAULT 0, p_receipturl text DEFAULT NULL::text, p_receivedbystaffid integer DEFAULT NULL::integer, p_notes text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text, p_supplierid integer DEFAULT NULL::integer, p_totalcost numeric DEFAULT NULL::numeric, p_watercashaccountid integer DEFAULT NULL::integer, p_productionunit text DEFAULT NULL::text, p_productionunitsperpurchaseunit numeric DEFAULT NULL::numeric)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_totalcost     numeric := p_totalcost;
    v_amountpaid    numeric := p_amountpaid;
    v_suppliername  text    := p_suppliername;
    v_prodqty       numeric;
    v_itemname      text;
    v_catid         integer;
    v_cashaccountid integer;
    v_effectivepaymentmethod text;
    v_newid         integer;
    v_expenseid     integer := NULL;
    v_method        text;            -- 275
BEGIN
    IF (p_quantity <= 0) THEN
        RAISE EXCEPTION 'Quantity must be > 0.';
    END IF;
    IF (p_unitcost < 0) THEN
        RAISE EXCEPTION 'UnitCost cannot be negative.';
    END IF;

    IF (v_totalcost IS NULL OR v_totalcost <= 0) THEN
        v_totalcost := p_quantity::numeric(14,2) * p_unitcost;
    END IF;

    IF v_amountpaid IS NULL THEN
        v_amountpaid := 0;
    END IF;
    IF v_amountpaid > v_totalcost THEN
        v_amountpaid := v_totalcost;
    END IF;

    -- Production-level quantity added to stock.
    v_prodqty := (p_quantity * COALESCE(NULLIF(p_productionunitsperpurchaseunit, 0), 1))::numeric(18,4);

    -- A new purchase is a full lot. RemainingQuantity is in PURCHASE units,
    -- matching Quantity, and is what production draws against.

    SELECT mi.itemname::text INTO v_itemname FROM waterrawmaterialitems mi
    WHERE mi.waterrawmaterialitemid = p_waterrawmaterialitemid AND mi.farmid = p_farmid;

    IF (p_supplierid IS NOT NULL AND (v_suppliername IS NULL OR v_suppliername = '')) THEN
        SELECT s.suppliername::text INTO v_suppliername FROM watersuppliers s
        WHERE s.watersupplierid = p_supplierid AND s.farmid = p_farmid;
    END IF;

    -- 275. Resolve ONCE, here, and stamp it on the row below. Asked again later
    -- it could give a different answer, and a purchase that changes its mind
    -- about how it was treated is how a closed month's P&L moves.
    SELECT r.method INTO v_method
    FROM   fnwatercostrecognition_effective(
               p_farmid, p_waterrawmaterialitemid, NULL,
               COALESCE(p_purchasedate, (now() at time zone 'utc'))::date) r;
    v_method := COALESCE(v_method, 'EXPENSE_WHEN_PURCHASED');

    PERFORM spwaterexpensecategory_ensurerawmaterialpurchase(p_farmid);

    SELECT c.waterexpensecategoryid INTO v_catid FROM waterexpensecategories c
    WHERE c.farmid = p_farmid AND c.name = 'Raw Materials / Inventory Purchase';

    IF p_watercashaccountid IS NOT NULL THEN
        SELECT ca.watercashaccountid INTO v_cashaccountid FROM watercashaccounts ca
        WHERE ca.watercashaccountid = p_watercashaccountid AND ca.farmid = p_farmid AND ca.isactive = TRUE;
    END IF;
    IF v_cashaccountid IS NULL THEN
        SELECT ca.watercashaccountid INTO v_cashaccountid FROM watercashaccounts ca
        WHERE ca.farmid = p_farmid AND ca.isactive = TRUE ORDER BY ca.watercashaccountid LIMIT 1;
    END IF;

    v_effectivepaymentmethod :=
        CASE WHEN p_paymentmethod IN ('Cash','MoMo','Bank','Card','Credit','Mixed') THEN p_paymentmethod
             WHEN v_cashaccountid IS NULL THEN 'Credit' ELSE 'Cash' END;

    INSERT INTO waterrawmaterialpurchases (
        farmid, waterrawmaterialitemid, suppliername, purchasedate, quantity, unitcost, totalcost,
        paymentmethod, amountpaid, receipturl, receivedbystaffid, notes, createdby, supplierid,
        productionunit, productionunitsperpurchaseunit, remainingquantity,
        costrecognitionmethod,                                             -- 275
        deferredtotalcost, deferredremainingcost                           -- 278
    )
    VALUES (
        p_farmid, p_waterrawmaterialitemid, v_suppliername,
        COALESCE(p_purchasedate, (now() at time zone 'utc')), p_quantity, p_unitcost, v_totalcost,
        v_effectivepaymentmethod, v_amountpaid, p_receipturl, p_receivedbystaffid, p_notes, p_createdby, p_supplierid,
        p_productionunit, p_productionunitsperpurchaseunit, p_quantity,
        v_method,                                                          -- 275
        -- 278. A deferred lot opens with its WHOLE cost deferred, and an
        -- expensed one with none. Note it is totalcost, not amountpaid: what is
        -- owed to the supplier has no bearing on what the stock cost, and a
        -- credit purchase that defers must hold its full cost from day one
        -- rather than growing a balance as it is paid.
        CASE WHEN fnwatercostrecognition_expenseatconsumption(v_method) THEN v_totalcost ELSE 0 END,
        CASE WHEN fnwatercostrecognition_expenseatconsumption(v_method) THEN v_totalcost ELSE 0 END
    )
    RETURNING waterrawmaterialpurchaseid INTO v_newid;

    UPDATE waterrawmaterialitems mi
    SET currentquantity = mi.currentquantity + v_prodqty,   -- production-level qty
        updatedat = (now() at time zone 'utc')
    WHERE mi.waterrawmaterialitemid = p_waterrawmaterialitemid AND mi.farmid = p_farmid;

    -- 275. The one new condition on this block. A deferred purchase writes NO
    -- expense: its cost is inventory value until 279 recognises it on
    -- consumption. Note what is NOT inside the condition -- the stock update
    -- above already ran, and the cash transaction below is nested INSIDE this
    -- block in the live body, which is correct: the cash row is keyed to the
    -- expense it pays for (sourcetype 'Expense', sourceid v_expenseid) and
    -- cannot exist without it.
    --
    -- That means a deferred CASH purchase moves no cash here either. It does not
    -- need to: a deferred purchase is entered on credit in every real workflow,
    -- and 278 below opens its deferred balance from totalcost regardless of what
    -- has been paid. (275 wrote "277" here; the opening turned out to be 278.) If that assumption ever breaks, the fix is a cash row that does
    -- not hang off an expense id -- not moving this gate.
    IF (v_catid IS NOT NULL AND v_amountpaid > 0
        AND fnwatercostrecognition_expenseatpurchase(v_method)) THEN         -- 275
        INSERT INTO waterexpenses
            (farmid, expensedate, waterexpensecategoryid, description, amount, paidto,
             paymentmethod, watercashaccountid, linkedwaterproductionbatchid,
             status, notes, createdby, approvedby, approvedat, supplierid, sourcetype, sourceid)
        VALUES
            (p_farmid, COALESCE(p_purchasedate, (now() at time zone 'utc')), v_catid,
             concat('Raw material purchase: ',
                    COALESCE(v_itemname, 'item #' || p_waterrawmaterialitemid::text),
                    ' (', p_quantity::numeric(14,3)::text, ' units)',
                    CASE WHEN v_amountpaid < v_totalcost
                         THEN concat(' - part payment of ', v_amountpaid::numeric(14,2)::text,
                                     ' of ', v_totalcost::numeric(14,2)::text)
                         ELSE '' END),
             v_amountpaid, v_suppliername, v_effectivepaymentmethod,
             CASE WHEN v_effectivepaymentmethod = 'Credit' THEN NULL ELSE v_cashaccountid END, NULL,
             'Approved', 'Auto-created from raw material purchase.',
             p_createdby, p_createdby, (now() at time zone 'utc'), p_supplierid, 'RawMaterialPurchase', v_newid)
        RETURNING waterexpenseid INTO v_expenseid;

        IF (v_effectivepaymentmethod <> 'Credit' AND v_cashaccountid IS NOT NULL) THEN
            INSERT INTO watercashtransactions (
                farmid, watercashaccountid, transactiondate, transactiontype,
                sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
            VALUES (
                p_farmid, v_cashaccountid, COALESCE(p_purchasedate, (now() at time zone 'utc')), 'CashOut',
                'Expense', v_expenseid, -v_amountpaid,
                concat('Raw material purchase #', v_newid), p_createdby, p_createdby, (now() at time zone 'utc'));

            UPDATE watercashaccounts ca
            SET currentbalance = ca.currentbalance - v_amountpaid,
                updatedat = (now() at time zone 'utc')
            WHERE ca.watercashaccountid = v_cashaccountid;
        END IF;

        UPDATE waterrawmaterialpurchases p SET linkedwaterexpenseid = v_expenseid
        WHERE p.waterrawmaterialpurchaseid = v_newid;
    END IF;

    RETURN v_newid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. The edit: carry the deferred balance with the cost.
--
-- Reproduced from the LIVE definition, untouched by 275 and 277. The
-- already-drawn guard, the quantity validation, the stock-delta arithmetic, the
-- negative-stock refusal and the linked-expense update are unchanged.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterrawmaterialpurchase_update(p_waterrawmaterialpurchaseid integer, p_farmid text, p_suppliername text DEFAULT NULL::text, p_purchasedate timestamp without time zone DEFAULT NULL::timestamp without time zone, p_quantity numeric DEFAULT NULL::numeric, p_unitcost numeric DEFAULT NULL::numeric, p_paymentmethod text DEFAULT NULL::text, p_amountpaid numeric DEFAULT 0, p_receipturl text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_supplierid integer DEFAULT NULL::integer, p_totalcost numeric DEFAULT NULL::numeric, p_watercashaccountid integer DEFAULT NULL::integer, p_productionunit text DEFAULT NULL::text, p_productionunitsperpurchaseunit numeric DEFAULT NULL::numeric)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_totalcost       numeric := p_totalcost;
    v_suppliername    text    := p_suppliername;
    v_oldqty          numeric;
    v_itemid          integer;
    v_linkedexpenseid integer;
    v_oldmult         numeric;
    v_newmult         numeric;
    v_delta           numeric;
    v_currentstock    numeric;
    v_msg1            text;
    v_updcashaccountid integer := NULL;
BEGIN
    -- A lot that an approved production batch has already drawn from can't be
    -- re-quantified underneath it - the draw records and remaining balances
    -- would stop agreeing. Reopen that batch first.
    IF EXISTS (SELECT 1 FROM waterrawmaterialusagebatch ub
               WHERE ub.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid) THEN
        RAISE EXCEPTION 'This purchase batch has already been drawn from by an approved production batch. Reopen that batch first.';
    END IF;

    IF (p_quantity <= 0) THEN
        RAISE EXCEPTION 'Quantity must be > 0.';
    END IF;
    IF (p_unitcost < 0) THEN
        RAISE EXCEPTION 'UnitCost cannot be negative.';
    END IF;

    IF (v_totalcost IS NULL OR v_totalcost <= 0) THEN
        v_totalcost := p_quantity::numeric(14,2) * p_unitcost;
    END IF;

    SELECT p.quantity, p.waterrawmaterialitemid, p.linkedwaterexpenseid,
           COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1)
      INTO v_oldqty, v_itemid, v_linkedexpenseid, v_oldmult
    FROM waterrawmaterialpurchases p
    WHERE p.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid AND p.farmid = p_farmid;

    IF v_oldqty IS NULL THEN
        RAISE EXCEPTION 'Purchase % not found.', p_waterrawmaterialpurchaseid;
    END IF;

    -- Stock delta measured in PRODUCTION units (new prod qty - old prod qty).
    v_newmult := COALESCE(NULLIF(p_productionunitsperpurchaseunit, 0), 1);
    v_delta   := ((p_quantity * v_newmult) - (v_oldqty * v_oldmult))::numeric(18,4);

    IF (v_delta < 0) THEN
        SELECT mi.currentquantity::numeric(18,4) INTO v_currentstock
        FROM waterrawmaterialitems mi
        WHERE mi.waterrawmaterialitemid = v_itemid AND mi.farmid = p_farmid;

        IF (v_currentstock + v_delta < 0) THEN
            v_msg1 := 'Cannot reduce quantity: only ' || v_currentstock::text
                      || ' production units of this item remain in stock. Reverse usages first.';
            RAISE EXCEPTION '%', v_msg1;
        END IF;
    END IF;

    IF (p_supplierid IS NOT NULL AND (v_suppliername IS NULL OR v_suppliername = '')) THEN
        SELECT s.suppliername::text INTO v_suppliername FROM watersuppliers s
        WHERE s.watersupplierid = p_supplierid AND s.farmid = p_farmid;
    END IF;

    IF (p_watercashaccountid IS NOT NULL AND p_paymentmethod <> 'Credit') THEN
        SELECT ca.watercashaccountid INTO v_updcashaccountid FROM watercashaccounts ca
        WHERE ca.watercashaccountid = p_watercashaccountid AND ca.farmid = p_farmid AND ca.isactive = TRUE;
    END IF;

    UPDATE waterrawmaterialpurchases p
    SET suppliername  = v_suppliername,
        supplierid    = p_supplierid,
        purchasedate  = COALESCE(p_purchasedate, p.purchasedate),
        quantity      = p_quantity,
        unitcost      = p_unitcost,
        totalcost     = v_totalcost,
        paymentmethod = p_paymentmethod,
        amountpaid    = p_amountpaid,
        receipturl    = p_receipturl,
        notes         = p_notes,
        productionunit = p_productionunit,
        productionunitsperpurchaseunit = p_productionunitsperpurchaseunit,
        updatedat     = (now() at time zone 'utc'),
        remainingquantity = p_quantity,
        -- 278. The deferred balance follows the cost. Safe to rewrite outright
        -- rather than rescale, because the guard at the top of this function has
        -- already refused any lot that has been drawn from: nothing downstream
        -- can have recognised part of this balance yet, so there is no reported
        -- expense to contradict.
        --
        -- Keyed on the lot's OWN snapshot, never on today's setting. A company
        -- that switched deferral off last week must not have last month's
        -- deferred purchase silently zeroed by an unrelated edit to its notes.
        deferredtotalcost     = CASE WHEN fnwatercostrecognition_expenseatconsumption(p.costrecognitionmethod)
                                     THEN v_totalcost ELSE 0 END,
        deferredremainingcost = CASE WHEN fnwatercostrecognition_expenseatconsumption(p.costrecognitionmethod)
                                     THEN v_totalcost ELSE 0 END
    WHERE p.waterrawmaterialpurchaseid = p_waterrawmaterialpurchaseid AND p.farmid = p_farmid;

    IF (v_delta <> 0) THEN
        UPDATE waterrawmaterialitems mi
        SET currentquantity = mi.currentquantity + v_delta,   -- production-level delta
            updatedat = (now() at time zone 'utc')
        WHERE mi.waterrawmaterialitemid = v_itemid AND mi.farmid = p_farmid;
    END IF;

    IF (v_linkedexpenseid IS NOT NULL) THEN
        UPDATE waterexpenses e
        SET amount     = p_amountpaid,
            paidto     = v_suppliername,
            supplierid = p_supplierid,
            expensedate = COALESCE(p_purchasedate, e.expensedate),
            watercashaccountid = CASE WHEN p_watercashaccountid IS NOT NULL THEN v_updcashaccountid ELSE e.watercashaccountid END,
            updatedat  = (now() at time zone 'utc')
        WHERE e.waterexpenseid = v_linkedexpenseid AND e.farmid = p_farmid
          AND e.isdeleted = FALSE AND e.status IN ('Draft','Submitted','Approved');
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Grants.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.spwaterrawmaterialpurchase_insert(
            text, integer, text, timestamp without time zone, numeric, numeric, text,
            numeric, text, integer, text, text, integer, numeric, integer, text, numeric)
            TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spwaterrawmaterialpurchase_update(
            integer, text, text, timestamp without time zone, numeric, numeric, text,
            numeric, text, text, integer, numeric, integer, text, numeric)
            TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'the purchase opens a deferred balance' AS check,
       CASE WHEN position('deferredtotalcost' in pg_get_functiondef(p.oid)) > 0
            THEN 'OK' ELSE 'NOT WIRED' END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname = 'spwaterrawmaterialpurchase_insert'

UNION ALL
SELECT 'the edit carries it',
       CASE WHEN position('deferredtotalcost' in pg_get_functiondef(p.oid)) > 0
            THEN 'OK' ELSE 'NOT WIRED' END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname = 'spwaterrawmaterialpurchase_update'

UNION ALL
-- Nothing may have opened a balance yet: the interlock is 279's to lift.
SELECT 'still no lot with deferred cost',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   waterrawmaterialpurchases WHERE deferredremainingcost <> 0

UNION ALL
SELECT 'deferral interlock still shut',
       CASE WHEN public.fnwatercostrecognition_deferralready() THEN 'OPEN -- WRONG' ELSE 'OK' END;
