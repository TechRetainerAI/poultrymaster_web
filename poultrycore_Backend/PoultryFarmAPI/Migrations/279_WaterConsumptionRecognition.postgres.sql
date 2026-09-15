-- =============================================================================
-- 279_WaterConsumptionRecognition.postgres.sql
--
-- Purpose
-- -------
-- Phase 2, part 3: the deferred cost finally reaches Profit & Loss.
--
-- 277 gave the lots a deferred balance and taught the FIFO engine to draw it
-- down. 278 opened that balance at purchase. This file SPENDS it: when raw
-- material is actually consumed by a production batch, the deferred share of
-- what was drawn becomes an expense.
--
-- AND IT IS THE FILE THAT OPENS THE INTERLOCK. Section 4. Nothing else may.
--
-- ONE PLACE, NOT SEVERAL
-- ======================
-- Water consumes raw material in exactly one place: spwaterproductionbatch_approve
-- runs _consumebatches over the batch's usage lines. So recognition needs one
-- integration point, and the engine underneath it has already worked out the
-- per-lot split before this file adds anything.
--
-- WHAT IS RECOGNISED, AND WHAT IS NOT
-- ===================================
--   deferredcostdrawn > 0   the lot had never been expensed. That amount is the
--                           expense, and it is exactly what 277 recorded on the
--                           allocation.
--   deferredcostdrawn = 0   the lot was expensed when it was bought. Consuming
--                           it costs nothing further. THIS is the rule that
--                           stops the same cedi being charged twice, and it is
--                           per LOT, not per item -- one draw can cross an old
--                           expensed lot and a new deferred one and recognise
--                           only the second.
--
-- The decision is never taken from today's settings. It comes from the
-- allocation, which came from the lot, which was stamped when it was created.
--
-- WHERE IT LANDS IN THE P&L
-- =========================
-- 282 designed this and named the sourcetypes, before this file existed.
-- fnwaterexpense_plline already reads:
--
--   WHEN p_sourcetype = 'WaterPackagingConsumption' THEN 'Packaging'
--   WHEN p_sourcetype = 'WaterTreatmentConsumption' THEN 'Treatment'
--
-- So one expense is written per CATEGORY GROUP consumed by the batch, and the
-- sourcetype carries the group. Consumed packaging lands on the same P&L line a
-- packaging purchase would have landed on -- which is the whole point: deferral
-- changes WHEN a cost appears, never WHERE.
--
-- Section 1 adds the third rule, for the supplies group.
--
-- WHY THE SOURCEID IS THE BATCH
-- =============================
-- spwaterproductionbatch_update DELETEs and reinserts waterrawmaterialusage on
-- every edit, so an expense keyed on a usage id would dangle after the first
-- one. The batch is stable. The audit trail is still complete: batch -> usage
-- rows -> allocations -> lots.
--
-- Three sourcetypes against one batch id are three distinct keys, so
-- ux_waterexpenses_farmsource_active (farmid, sourcetype, sourceid) permits one
-- row per group and refuses a second of the same group. That index is doing real
-- work here, which is why section 3 has to be careful with it.
--
-- A NON-CASH EVENT
-- ================
-- No watercashtransactions row is written, so cash flow and the cash accounts do
-- not move -- the money left when the stock was paid for, and this is only the
-- P&L catching up. fnwaterpayables excludes every expense carrying a sourcetype
-- (240's rule, widened only for CapitalAsset by 283), so it never becomes a debt
-- either. paymentmethod is 'NonCash' and watercashaccountid is NULL: a 'Credit'
-- expense is one somebody is owed for, and nobody is owed anything here.
--
-- financialcosttype is deliberately left for fnwaterexpense_costtype to decide,
-- and it returns OperatingExpense. 282 made that call explicitly and wrote down
-- why: a consumed roll of film is a real operating cost of this period that
-- merely happened to be paid for earlier, and NonCashExpense would file it under
-- Other Costs beside depreciation.
--
-- REVERSAL
-- ========
-- Water reopens a batch rather than compensating it, and the existing
-- spwaterproductionbatch_reopen already does most of the work: it restores each
-- lot's remainingquantity from the allocations, deletes the allocations, and
-- cancels every expense linked to the batch. Two additions:
--
--   1. RESTORE THE DEFERRED COST TOO. Putting the stock back without putting its
--      deferred cost back would mean the second consumption of that stock
--      recognised nothing, and the cost would be lost for good.
--
--   2. SOFT-DELETE THE RECOGNITION ROWS, not merely cancel them. The unique
--      index is predicated on `isdeleted = false` and ignores status, so a
--      cancelled row keeps its slot and the next approval of the batch would
--      fail on a duplicate key. That is the same index 283 collided with from
--      the other direction.
--
-- WHAT IS NOT DONE HERE
-- =====================
-- Internal use, stock adjustments and loss records can also reduce stock. None
-- is wired to recognition: a negative adjustment may be a loss, a correction or
-- a count fix -- three different expenses -- and guessing would be worse than
-- waiting. 280 reports them as reconciliation gaps rather than silently
-- mis-recognising them.
--
-- EFFECT ON TODAY'S NUMBERS: none. Every lot in the database has deferred cost
-- 0, so every SUM(deferredcostdrawn) is 0, the HAVING clause admits nothing, and
-- no expense row is written for any existing or in-flight batch. What DOES
-- change is that from this moment a company MAY CHOOSE deferral -- which is the
-- point of the whole workstream, and why this file and no other lifts the guard.
--
-- Order: after 278. Before 280.
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
        WHERE  table_name = 'waterrawmaterialusagebatch'
          AND  column_name = 'deferredcostdrawn'
    ) THEN
        RAISE EXCEPTION '279 requires 277 (waterrawmaterialusagebatch.deferredcostdrawn is missing).';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public' AND p.proname = 'fnwaterexpense_plline'
    ) THEN
        RAISE EXCEPTION '279 requires 282 (fnwaterexpense_plline is missing).';
    END IF;
END
$guard$;

-- -----------------------------------------------------------------------------
-- 1. The P&L line for the third consumption group.
--
-- Reproduced from the LIVE definition with ONE clause added, marked "-- 279.".
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwaterexpense_plline(p_costtype text, p_sourcetype text, p_category text, p_itemcategory text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE
        -- ---- never profit ---------------------------------------------------
        WHEN p_costtype IN ('CapitalAsset', 'InventoryPurchase') THEN 'Excluded'

        -- ---- the cost of borrowing -----------------------------------------
        WHEN p_costtype = 'FinancingExpense' THEN
            CASE WHEN p_category ILIKE '%interest%' THEN 'LoanInterest'
                 WHEN p_category ILIKE '%fee%' OR p_category ILIKE '%charge%' THEN 'LoanFees'
                 ELSE 'OtherFinancing' END

        -- ---- depreciation ---------------------------------------------------
        WHEN p_sourcetype = 'AssetDepreciation' OR p_category ILIKE '%deprec%' THEN 'Depreciation'

        -- ---- the item decides, when there is one ----------------------------
        -- 274's grouping, so "is this packaging?" has one answer in the system.
        WHEN COALESCE(p_itemcategory, '') <> '' THEN
            CASE fnwatercostrecognition_categorygroup(p_itemcategory)
                 WHEN 'Packaging' THEN 'Packaging'
                 WHEN 'Treatment' THEN 'Treatment'
                 ELSE 'ProductionSupplies' END

        -- ---- the source decides ---------------------------------------------
        WHEN p_sourcetype = 'WaterPackagingConsumption' THEN 'Packaging'
        WHEN p_sourcetype = 'WaterTreatmentConsumption' THEN 'Treatment'
        -- 279. The third consumption group. 282 named the two above when it
        -- built this classifier, anticipating this migration; it could not name
        -- this one, because which categories fall OUTSIDE the two configurable
        -- groups was 274's decision and 274 had not been written yet.
        --
        -- 274 hard-wires Filter, UVLamp, SparePart, Fuel, CleaningSupply and
        -- Other to expense-at-purchase, so this line is only reachable through a
        -- deliberate per-item override. Rare -- but it must not fall through to
        -- Other Costs when it happens.
        WHEN p_sourcetype = 'WaterSuppliesConsumption' THEN 'ProductionSupplies'
        WHEN p_sourcetype = 'Payroll' THEN 'Payroll'
        WHEN p_sourcetype IN ('WaterDriverDelivery', 'DriverReturn', 'DeliveryReturn') THEN 'Transport'

        -- ---- direct production costs, by category ---------------------------
        WHEN p_category ILIKE '%sachet film%' OR p_category ILIKE '%packag%'
          OR p_category ILIKE '%preform%'     OR p_category ILIKE '%bottle%'
          OR p_category ILIKE '%shrink%'      OR p_category ILIKE '%label%'
          OR p_category ILIKE '%outer bag%'   OR p_category ILIKE '%cap%'
             THEN 'Packaging'
        WHEN p_category ILIKE '%chemical%'  OR p_category ILIKE '%chlorin%'
          OR p_category ILIKE '%treatment%' OR p_category ILIKE '%filter%'
          OR p_category ILIKE '%uv %'       OR p_category ILIKE '%lab test%'
          OR p_category ILIKE '%water quality%'
             THEN 'Treatment'
        -- See the header: production power must be NAMED to count as direct.
        WHEN p_category ILIKE '%production power%' OR p_category ILIKE '%plant electric%'
          OR p_category ILIKE '%production electric%'
             THEN 'ProductionUtilities'
        -- "Direct labour" has to be named to be counted as direct. A company
        -- that types "Labor" gets Payroll below, because nothing in the row says
        -- whether that wage belongs to the plant or to the office, and guessing
        -- would move real money between Gross Profit and Operating Profit.
        WHEN p_category ILIKE '%direct labo%' OR p_category ILIKE '%plant labo%'
          OR p_category ILIKE '%production labo%' THEN 'DirectLabour'
        WHEN p_category ILIKE '%production suppl%' OR p_category ILIKE '%raw material%'
          OR p_category ILIKE '%inventory purchase%' THEN 'ProductionSupplies'

        -- ---- operating expenses, by category --------------------------------
        WHEN p_category ILIKE '%payroll%' OR p_category ILIKE '%salary%'
          OR p_category ILIKE '%wage%'    OR p_category ILIKE '%labo%'
          OR p_category ILIKE '%staff%' THEN 'Payroll'
        WHEN p_category ILIKE '%utilit%'  OR p_category ILIKE '%electric%'
          OR p_category ILIKE '%power%'   OR p_category ILIKE '%water bill%' THEN 'Utilities'
        WHEN p_category ILIKE '%transport%' OR p_category ILIKE '%deliver%'
          OR p_category ILIKE '%fuel%'      OR p_category ILIKE '%vehicle%'
          OR p_category ILIKE '%travel%' THEN 'Transport'
        WHEN p_category ILIKE '%repair%' OR p_category ILIKE '%maintenance%'
          OR p_category ILIKE '%servicing%' THEN 'RepairsMaintenance'
        WHEN p_category ILIKE '%rent%' OR p_category ILIKE '%lease%' THEN 'Rent'
        WHEN p_category ILIKE '%market%' OR p_category ILIKE '%advert%'
          OR p_category ILIKE '%promot%' THEN 'Marketing'
        WHEN p_category ILIKE '%insur%' THEN 'Insurance'
        WHEN p_category ILIKE '%securit%' THEN 'Security'
        WHEN p_category ILIKE '%profession%' OR p_category ILIKE '%legal%'
          OR p_category ILIKE '%account%' OR p_category ILIKE '%consult%'
          OR p_category ILIKE '%audit%' THEN 'ProfessionalServices'
        WHEN p_category ILIKE '%licen%' OR p_category ILIKE '%permit%'
          OR p_category ILIKE '%fda%'   OR p_category ILIKE '%regulat%'
             THEN 'LicencesPermits'
        WHEN p_category ILIKE '%communic%' OR p_category ILIKE '%internet%'
          OR p_category ILIKE '%phone%' OR p_category ILIKE '%airtime%' THEN 'Communications'
        WHEN p_category ILIKE '%admin%' OR p_category ILIKE '%office%'
          OR p_category ILIKE '%stationer%' OR p_category ILIKE '%bank charge%' THEN 'Administration'

        ELSE 'OtherOperating'
    END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. Approval: recognise the deferred cost of what was drawn.
--
-- Reproduced from the LIVE definition. The idempotency guard, the shortfall
-- checks, the consume loop, the re-costing, the finished-goods restock, the raw
-- material decrements, the four production expense rows and the loss rows are
-- all unchanged. One block is added, marked "A0b. 279.", immediately after the
-- batch has been re-costed from the drawn prices.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterproductionbatch_approve(p_waterproductionbatchid integer, p_farmid text, p_approvedby text DEFAULT NULL::text)
 RETURNS TABLE(waterproductionbatchid integer, status text, approvedby text, approvedat timestamp without time zone)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status          text;
    v_productid       integer;
    v_bagsproduced    integer;
    v_damagedbags     integer;
    v_rejectedsachets integer;
    v_sachetsperbag   integer;
    v_totalcost       numeric;
    v_rawmatcost      numeric;
    v_electricitycost numeric;
    v_fuelcost        numeric;
    v_laborcost       numeric;
    v_othercost       numeric;
    v_productiondate  date;
    v_batchno         text;
    v_shortname       text;
    v_shorthave       numeric;
    v_shortneed       numeric;
    v_msg             text;
    v_goodbags        integer;
    v_allincost       numeric;
    v_costperbag      numeric;
    v_catelectricity  integer;
    v_catfuel         integer;
    v_catlabor        integer;
    v_catother        integer;
    v_defaultcashaccountid integer;
    v_proddatetime    timestamp;
    v_bagslossvalue    numeric;
    v_sachetslossvalue numeric;
    v_drawunitcost    numeric;
    u                 record;
    g                 record;          -- 279
    v_catrawmat       integer;         -- 279
BEGIN
    -- Idempotent: already-approved batches return their current state.
    IF EXISTS (SELECT 1 FROM waterproductionbatches b
               WHERE b.waterproductionbatchid = p_waterproductionbatchid
                 AND b.farmid = p_farmid AND b.status = 'Approved') THEN
        RETURN QUERY
        SELECT b.waterproductionbatchid, b.status::text, b.approvedby::text, b.approvedat
        FROM waterproductionbatches b
        WHERE b.waterproductionbatchid = p_waterproductionbatchid AND b.farmid = p_farmid;
        RETURN;
    END IF;

    SELECT b.status, b.waterproductid,
           b.bagsproduced, b.damagedbags,
           b.rejectedsachets,
           b.sachetsperbag,
           b.totalproductioncost,
           COALESCE(b.rawmaterialcost, 0),
           b.electricitycost,
           b.fuelcost, b.laborcost,
           b.otherproductioncost,
           b.productiondate,
           b.batchnumber
      INTO v_status, v_productid, v_bagsproduced, v_damagedbags, v_rejectedsachets,
           v_sachetsperbag, v_totalcost, v_rawmatcost, v_electricitycost,
           v_fuelcost, v_laborcost, v_othercost, v_productiondate, v_batchno
    FROM waterproductionbatches b
    WHERE b.waterproductionbatchid = p_waterproductionbatchid
      AND b.farmid = p_farmid AND b.isdeleted = FALSE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Production batch % not found.', p_waterproductionbatchid;
    END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'Production batch cannot be approved from status %.', v_status;
    END IF;

    -- Pre-check raw material availability against the DRAWABLE LOT POOL, not
    -- CurrentQuantity. The two differ whenever stock arrived by adjustment: it
    -- counts as on hand but has no purchase lot behind it, so the draw below
    -- would fail on a number the user can't see. Totals are per item, because
    -- one batch can list the same item on two lines.
    WITH need AS (
        SELECT u2.waterrawmaterialitemid AS itemid, SUM(u2.quantityused) AS needed
        FROM waterrawmaterialusage u2
        WHERE u2.farmid = p_farmid AND u2.waterproductionbatchid = p_waterproductionbatchid
        GROUP BY u2.waterrawmaterialitemid
    )
    SELECT mi.itemname::text, pool.lotstock, n.needed
      INTO v_shortname, v_shorthave, v_shortneed
    FROM need n
    JOIN waterrawmaterialitems mi ON mi.waterrawmaterialitemid = n.itemid
    CROSS JOIN LATERAL (
        SELECT COALESCE((
            SELECT SUM(p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1))
            FROM waterrawmaterialpurchases p
            WHERE p.waterrawmaterialitemid = n.itemid AND p.farmid = p_farmid), 0) AS lotstock
    ) pool
    WHERE n.needed > pool.lotstock + 0.0005
    LIMIT 1;

    IF v_shortname IS NOT NULL THEN
        v_msg := 'Not enough stock of "' || v_shortname || '" in purchase batches. Available to draw: '
                 || v_shorthave::numeric(18,4)::text || ', needed: '
                 || v_shortneed::numeric(18,4)::text
                 || '. Record a purchase or reduce the actual quantity used.';
        RAISE EXCEPTION '%', v_msg;
    END IF;

    v_goodbags := v_bagsproduced - COALESCE(v_damagedbags, 0);
    IF v_goodbags < 0 THEN
        v_goodbags := 0;
    END IF;

    -- All-in cost (excl loss writeoffs) for per-bag costing. Provisional, from the
    -- client's preview costs; both are recomputed once the lots have been drawn.
    v_allincost  := (v_totalcost + v_rawmatcost)::numeric(14,2);
    v_costperbag := (CASE WHEN v_goodbags > 0 THEN v_allincost * 1.0 / v_goodbags ELSE 0 END)::numeric(14,4);

    -- Ensure the four production expense categories exist.
    PERFORM spwaterexpensecategory_ensureproductiondefaults(p_farmid);

    SELECT c.waterexpensecategoryid INTO v_catelectricity
    FROM waterexpensecategories c WHERE c.farmid = p_farmid AND c.name = 'Electricity / Utilities';
    SELECT c.waterexpensecategoryid INTO v_catfuel
    FROM waterexpensecategories c WHERE c.farmid = p_farmid AND c.name = 'Fuel';
    SELECT c.waterexpensecategoryid INTO v_catlabor
    FROM waterexpensecategories c WHERE c.farmid = p_farmid AND c.name = 'Labor';
    SELECT c.waterexpensecategoryid INTO v_catother
    FROM waterexpensecategories c WHERE c.farmid = p_farmid AND c.name = 'Production Other';

    UPDATE waterproductionbatches b
    SET status = 'Approved', approvedby = p_approvedby,
        approvedat = (now() at time zone 'utc'), updatedat = (now() at time zone 'utc')
    WHERE b.waterproductionbatchid = p_waterproductionbatchid AND b.farmid = p_farmid;

    -- ---------------------------------------------------------------
    -- A0. Draw each material line from its purchase lots, per the item's
    --     FIFO/LIFO/HIFO policy, and take the price from what was actually drawn.
    -- ---------------------------------------------------------------
    FOR u IN
        SELECT u2.waterrawmaterialusageid AS usageid,
               u2.waterrawmaterialitemid  AS matitemid,
               u2.quantityused            AS matqty
        FROM waterrawmaterialusage u2
        WHERE u2.farmid = p_farmid AND u2.waterproductionbatchid = p_waterproductionbatchid
          AND COALESCE(u2.quantityused, 0) > 0
        ORDER BY u2.waterrawmaterialusageid
    LOOP
        v_drawunitcost := NULL;
        SELECT spwaterrawmaterialitem_consumebatches(
                   p_farmid   => p_farmid,
                   p_itemid   => u.matitemid,
                   p_usageid  => u.usageid,
                   p_neededqty=> u.matqty)
          INTO v_drawunitcost;

        -- Only overwrite when the draw produced a price. A NULL means there was
        -- nothing to price from, and the client's preview figure is left alone.
        IF v_drawunitcost IS NOT NULL THEN
            UPDATE waterrawmaterialusage w
            SET unitcost = v_drawunitcost
            WHERE w.waterrawmaterialusageid = u.usageid;
        END IF;
    END LOOP;

    -- Re-cost the batch from the drawn prices. WaterRawMaterialUsage.TotalCost
    -- is a generated column, so it follows UnitCost automatically.
    v_rawmatcost := COALESCE((SELECT SUM(u2.totalcost)
                              FROM waterrawmaterialusage u2
                              WHERE u2.farmid = p_farmid
                                AND u2.waterproductionbatchid = p_waterproductionbatchid), 0);

    UPDATE waterproductionbatches b
    SET rawmaterialcost = v_rawmatcost, updatedat = (now() at time zone 'utc')
    WHERE b.waterproductionbatchid = p_waterproductionbatchid AND b.farmid = p_farmid;

    -- ---------------------------------------------------------------
    -- A0b. 279. RECOGNITION. The deferred share of what was just drawn becomes
    --      a Profit & Loss expense, now, because the stock has been used.
    --
    -- _consumebatches has already worked out the per-lot split and written it to
    -- waterrawmaterialusagebatch.deferredcostdrawn (277). All this does is total
    -- it and book it. Nothing here re-derives the decision from settings: the
    -- number came from the allocation, which came from the lot, which was
    -- stamped when it was bought.
    --
    --   deferredcostdrawn > 0   the lot had never been expensed -> that amount
    --                           is the expense.
    --   deferredcostdrawn = 0   the lot was expensed when it was bought ->
    --                           consuming it costs nothing further.
    --
    -- The second line is what stops a cedi being charged twice, and it is per
    -- LOT: one draw can cross an old expensed lot and a new deferred one and
    -- recognise only the second.
    --
    -- ONE ROW PER CATEGORY GROUP, and the sourcetype carries the group, because
    -- that is what 282's fnwaterexpense_plline keys the P&L line on: consumed
    -- packaging lands on the same Packaging line a packaging purchase would have
    -- landed on. Deferral changes WHEN a cost appears, never WHERE.
    --
    -- The sourceid is the BATCH, not the usage row: spwaterproductionbatch_update
    -- deletes and reinserts waterrawmaterialusage on every edit, so a usage id
    -- would dangle after the first one. The batch is stable and the trail is
    -- still complete: batch -> usage -> allocations -> lots.
    --
    -- Three sourcetypes against one batch id are three distinct keys, so
    -- ux_waterexpenses_farmsource_active (farmid, sourcetype, sourceid) permits
    -- one row per group and refuses a second of the same group.
    --
    -- NO CASH, NO PAYABLE. No watercashtransactions row is written, so cash flow
    -- and the cash accounts do not move -- the money left when the stock was
    -- paid for, and this is only the P&L catching up. fnwaterpayables excludes
    -- every expense carrying a sourcetype, so it never becomes a debt.
    -- ---------------------------------------------------------------
    PERFORM spwaterexpensecategory_ensurerawmaterialpurchase(p_farmid);
    SELECT c.waterexpensecategoryid INTO v_catrawmat
    FROM   waterexpensecategories c
    WHERE  c.farmid = p_farmid AND c.name = 'Raw Materials / Inventory Purchase'
      AND  COALESCE(c.isdeleted, FALSE) = FALSE
    LIMIT  1;

    IF v_catrawmat IS NOT NULL THEN
        FOR g IN
            SELECT CASE fnwatercostrecognition_categorygroup(wmi.category::text)
                        WHEN 'Packaging' THEN 'WaterPackagingConsumption'
                        WHEN 'Treatment' THEN 'WaterTreatmentConsumption'
                        ELSE 'WaterSuppliesConsumption' END AS srctype,
                   SUM(wub.deferredcostdrawn)::numeric(14,2) AS amount
            -- Aliased wu/wub/wmi, NOT u/ub/mi. This function already DECLAREs
            -- a record variable named `u` for the consume loop above, and
            -- plpgsql resolves a qualified name against an in-scope variable
            -- before a table alias -- so `u.waterrawmaterialusageid` here bound
            -- to that record and failed with "record u has no field ...".
            FROM   waterrawmaterialusagebatch wub
            JOIN   waterrawmaterialusage wu
                   ON wu.waterrawmaterialusageid = wub.waterrawmaterialusageid
            JOIN   waterrawmaterialitems wmi
                   ON wmi.waterrawmaterialitemid = wu.waterrawmaterialitemid
            WHERE  wu.farmid = p_farmid
              AND  wu.waterproductionbatchid = p_waterproductionbatchid
            GROUP  BY 1
            HAVING SUM(wub.deferredcostdrawn) > 0
        LOOP
            -- Belt and braces against the unique index: a batch approved,
            -- reopened and approved again must not collide with a row the
            -- reopen somehow failed to retire.
            IF NOT EXISTS (SELECT 1 FROM waterexpenses e
                           WHERE e.farmid = p_farmid
                             AND e.sourcetype = g.srctype
                             AND e.sourceid = p_waterproductionbatchid
                             AND e.isdeleted = FALSE) THEN
                INSERT INTO waterexpenses
                    (farmid, expensedate, waterexpensecategoryid, description, amount,
                     paidto, paymentmethod, watercashaccountid,
                     linkedwaterproductionbatchid, status, notes, createdby,
                     approvedby, approvedat, sourcetype, sourceid)
                VALUES
                    -- v_productiondate::timestamp, NOT v_proddatetime: that
                    -- variable is not assigned until the production-expense
                    -- section further down, so reading it here writes a NULL
                    -- into a NOT NULL column. Same value, read from the batch.
                    (p_farmid, v_productiondate::timestamp, v_catrawmat,
                     concat('Inventory cost recognised on use - production batch ', v_batchno),
                     g.amount, NULL,
                     -- NOT 'Credit': a credit expense is one somebody is owed
                     -- for, and nobody is owed anything here. NULL cash account
                     -- so the reopen path's cash-reversal branch cannot fire.
                     'NonCash', NULL,
                     p_waterproductionbatchid, 'Approved',
                     'Deferred inventory cost recognised when the stock was consumed.',
                     p_approvedby, p_approvedby, (now() at time zone 'utc'),
                     g.srctype, p_waterproductionbatchid);
            END IF;
        END LOOP;
    END IF;

    -- Per-bag costing has to follow the real material cost.
    v_allincost  := (v_totalcost + v_rawmatcost)::numeric(14,2);
    v_costperbag := (CASE WHEN v_goodbags > 0 THEN v_allincost * 1.0 / v_goodbags ELSE 0 END)::numeric(14,4);

    -- ---------------------------------------------------------------
    -- A. Finished goods Restock (GoodBags only - never damaged bags).
    -- ---------------------------------------------------------------
    IF (v_goodbags > 0)
       AND NOT EXISTS (
           SELECT 1 FROM waterstocktransactions st
           WHERE st.farmid = p_farmid AND st.waterproductid = v_productid
             AND st.txntype = 'Restock'
             AND st.note = concat('Production batch ', v_batchno)
       ) THEN
        INSERT INTO waterstocktransactions (
            farmid, waterproductid, txntype, quantity, unitcost, relatedsaleid, note, createdby)
        VALUES (
            p_farmid, v_productid, 'Restock', v_goodbags,
            v_costperbag::numeric(12,2), NULL,
            concat('Production batch ', v_batchno), p_approvedby);
    END IF;

    -- ---------------------------------------------------------------
    -- B. Raw material decrements (aggregated per item first).
    -- ---------------------------------------------------------------
    WITH used AS (
        SELECT u2.waterrawmaterialitemid AS itemid, SUM(u2.quantityused) AS qty
        FROM waterrawmaterialusage u2
        WHERE u2.farmid = p_farmid AND u2.waterproductionbatchid = p_waterproductionbatchid
        GROUP BY u2.waterrawmaterialitemid
    )
    UPDATE waterrawmaterialitems mi
    SET currentquantity = mi.currentquantity - x.qty,
        updatedat       = (now() at time zone 'utc')
    FROM used x
    WHERE x.itemid = mi.waterrawmaterialitemid
      AND mi.farmid = p_farmid;

    -- ---------------------------------------------------------------
    -- C. Production-linked Expense rows (Electricity / Fuel / Labor / Other).
    -- ---------------------------------------------------------------
    SELECT ca.watercashaccountid INTO v_defaultcashaccountid
    FROM watercashaccounts ca
    WHERE ca.farmid = p_farmid AND ca.isactive = TRUE
    ORDER BY ca.watercashaccountid
    LIMIT 1;

    v_proddatetime := v_productiondate::timestamp;

    IF (v_electricitycost > 0 AND v_catelectricity IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM waterexpenses e
                        WHERE e.farmid = p_farmid
                          AND e.linkedwaterproductionbatchid = p_waterproductionbatchid
                          AND e.waterexpensecategoryid = v_catelectricity
                          AND e.isdeleted = FALSE
                          AND e.status IN ('Draft','Submitted','Approved'))) THEN
        INSERT INTO waterexpenses
            (farmid, expensedate, waterexpensecategoryid, description, amount,
             paymentmethod, watercashaccountid, linkedwaterproductionbatchid,
             status, notes, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_proddatetime, v_catelectricity,
             concat('Electricity - Production batch ', v_batchno),
             v_electricitycost,
             CASE WHEN v_defaultcashaccountid IS NULL THEN 'Credit' ELSE 'Cash' END,
             v_defaultcashaccountid, p_waterproductionbatchid,
             'Approved',
             'Auto-created from production batch approval.',
             p_approvedby, p_approvedby, (now() at time zone 'utc'));
    END IF;

    IF (v_fuelcost > 0 AND v_catfuel IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM waterexpenses e
                        WHERE e.farmid = p_farmid
                          AND e.linkedwaterproductionbatchid = p_waterproductionbatchid
                          AND e.waterexpensecategoryid = v_catfuel
                          AND e.isdeleted = FALSE
                          AND e.status IN ('Draft','Submitted','Approved'))) THEN
        INSERT INTO waterexpenses
            (farmid, expensedate, waterexpensecategoryid, description, amount,
             paymentmethod, watercashaccountid, linkedwaterproductionbatchid,
             status, notes, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_proddatetime, v_catfuel,
             concat('Fuel - Production batch ', v_batchno),
             v_fuelcost,
             CASE WHEN v_defaultcashaccountid IS NULL THEN 'Credit' ELSE 'Cash' END,
             v_defaultcashaccountid, p_waterproductionbatchid,
             'Approved',
             'Auto-created from production batch approval.',
             p_approvedby, p_approvedby, (now() at time zone 'utc'));
    END IF;

    IF (v_laborcost > 0 AND v_catlabor IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM waterexpenses e
                        WHERE e.farmid = p_farmid
                          AND e.linkedwaterproductionbatchid = p_waterproductionbatchid
                          AND e.waterexpensecategoryid = v_catlabor
                          AND e.isdeleted = FALSE
                          AND e.status IN ('Draft','Submitted','Approved'))) THEN
        INSERT INTO waterexpenses
            (farmid, expensedate, waterexpensecategoryid, description, amount,
             paymentmethod, watercashaccountid, linkedwaterproductionbatchid,
             status, notes, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_proddatetime, v_catlabor,
             concat('Labor - Production batch ', v_batchno),
             v_laborcost,
             CASE WHEN v_defaultcashaccountid IS NULL THEN 'Credit' ELSE 'Cash' END,
             v_defaultcashaccountid, p_waterproductionbatchid,
             'Approved',
             'Auto-created from production batch approval.',
             p_approvedby, p_approvedby, (now() at time zone 'utc'));
    END IF;

    IF (v_othercost > 0 AND v_catother IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM waterexpenses e
                        WHERE e.farmid = p_farmid
                          AND e.linkedwaterproductionbatchid = p_waterproductionbatchid
                          AND e.waterexpensecategoryid = v_catother
                          AND e.isdeleted = FALSE
                          AND e.status IN ('Draft','Submitted','Approved'))) THEN
        INSERT INTO waterexpenses
            (farmid, expensedate, waterexpensecategoryid, description, amount,
             paymentmethod, watercashaccountid, linkedwaterproductionbatchid,
             status, notes, createdby, approvedby, approvedat)
        VALUES
            (p_farmid, v_proddatetime, v_catother,
             concat('Other production cost - Production batch ', v_batchno),
             v_othercost,
             CASE WHEN v_defaultcashaccountid IS NULL THEN 'Credit' ELSE 'Cash' END,
             v_defaultcashaccountid, p_waterproductionbatchid,
             'Approved',
             'Auto-created from production batch approval.',
             p_approvedby, p_approvedby, (now() at time zone 'utc'));
    END IF;

    -- ---------------------------------------------------------------
    -- D. Production-linked Loss record (damaged bags + rejected sachets).
    -- ---------------------------------------------------------------
    IF (COALESCE(v_damagedbags,0) > 0 OR COALESCE(v_rejectedsachets,0) > 0)
       AND NOT EXISTS (
           SELECT 1 FROM waterproductionlosses l
           WHERE l.farmid = p_farmid
             AND l.sourcetype = 'ProductionBatch'
             AND l.sourceid   = p_waterproductionbatchid
             AND l.isdeleted  = FALSE
       ) THEN
        v_bagslossvalue := (COALESCE(v_damagedbags,0)::numeric(14,2) * v_costperbag)::numeric(14,2);
        v_sachetslossvalue := (CASE WHEN v_sachetsperbag > 0
                 THEN (COALESCE(v_rejectedsachets,0)::numeric(14,2) / v_sachetsperbag) * v_costperbag
                 ELSE 0 END)::numeric(14,2);

        INSERT INTO waterproductionlosses
            (farmid, lossdate, losstype, sourcetype, sourceid,
             waterproductid, bagslost, sachetslost, sachetsperbag,
             costperbag, bagslossvalue, sachetslossvalue,
             reason, status, notes, createdby)
        VALUES
            (p_farmid, v_productiondate, 'ProductionDamage',
             'ProductionBatch', p_waterproductionbatchid,
             v_productid, COALESCE(v_damagedbags,0), COALESCE(v_rejectedsachets,0),
             v_sachetsperbag,
             v_costperbag,
             v_bagslossvalue, v_sachetslossvalue,
             'Production damage / rejected during production',
             'Approved',
             concat('Auto-created from production batch ', v_batchno),
             p_approvedby);
    END IF;

    RETURN QUERY
    SELECT b.waterproductionbatchid, b.status::text, b.approvedby::text, b.approvedat
    FROM waterproductionbatches b
    WHERE b.waterproductionbatchid = p_waterproductionbatchid AND b.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Reopen: give the deferred cost back, and free the index slot.
--
-- Reproduced from the LIVE definition. The stock guard, the finished-goods
-- adjustment, the lot restore, the allocation delete, the item restore, the
-- expense cancellation with its cash reversal and the loss soft-delete are
-- unchanged. Two additions, both marked "-- 279.".
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterproductionbatch_reopen(p_waterproductionbatchid integer, p_farmid text, p_reopenedby text DEFAULT NULL::text)
 RETURNS TABLE(waterproductionbatchid integer, status text, approvedby text, approvedat timestamp without time zone)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status       text;
    v_productid    integer;
    v_bagsproduced integer;
    v_damagedbags  integer;
    v_batchno      text;
    v_goodbags     integer;
    v_currentstock integer;
    e              record;
BEGIN
    SELECT b.status, b.waterproductid, b.bagsproduced, b.damagedbags, b.batchnumber
      INTO v_status, v_productid, v_bagsproduced, v_damagedbags, v_batchno
    FROM waterproductionbatches b
    WHERE b.waterproductionbatchid = p_waterproductionbatchid
      AND b.farmid = p_farmid
      AND b.isdeleted = FALSE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Production batch % not found.', p_waterproductionbatchid;
    END IF;
    IF v_status <> 'Approved' THEN
        RAISE EXCEPTION 'Only Approved batches can be reopened. Current status: %.', v_status;
    END IF;

    v_goodbags := v_bagsproduced - COALESCE(v_damagedbags, 0);
    IF v_goodbags < 0 THEN
        v_goodbags := 0;
    END IF;

    v_currentstock := COALESCE((
        SELECT SUM(st.quantity)::int FROM waterstocktransactions st
        WHERE st.farmid = p_farmid AND st.waterproductid = v_productid
    ), 0);

    IF v_goodbags > 0 AND v_currentstock < v_goodbags THEN
        RAISE EXCEPTION 'Cannot reopen: only % bags of this product remain in stock, but the batch added %. Cancel related sales or adjust stock first.',
                        v_currentstock, v_goodbags;
    END IF;

    -- Reverse the finished goods restock with a balancing Adjust txn.
    IF v_goodbags > 0 THEN
        INSERT INTO waterstocktransactions
            (farmid, waterproductid, txntype, quantity, unitcost, relatedsaleid, note, createdby)
        VALUES
            (p_farmid, v_productid, 'Adjust', -v_goodbags, NULL, NULL,
             concat('Reopen production batch ', v_batchno), p_reopenedby);
    END IF;

    -- Restore the purchase lots this batch drew from, then the item totals.
    -- QuantityDrawn is in PURCHASE units, matching RemainingQuantity.
    WITH lotrestore AS (
        SELECT ub.waterrawmaterialpurchaseid AS purchaseid,
               SUM(ub.quantitydrawn) AS qty,
               SUM(ub.deferredcostdrawn) AS defcost                      -- 279
        FROM waterrawmaterialusagebatch ub
        JOIN waterrawmaterialusage u ON u.waterrawmaterialusageid = ub.waterrawmaterialusageid
        WHERE u.farmid = p_farmid AND u.waterproductionbatchid = p_waterproductionbatchid
        GROUP BY ub.waterrawmaterialpurchaseid
    )
    UPDATE waterrawmaterialpurchases p
    SET remainingquantity = p.remainingquantity + r.qty,
        -- 279. Restoring stock has to restore its deferred cost too, or the
        -- second consumption of the same stock would recognise nothing and the
        -- cost would be lost for good.
        --
        -- LEAST against deferredtotalcost keeps 277's check constraint
        -- (remaining <= total) true even if rounding on the way out and back
        -- disagrees by a pesewa. The allocation rows are deleted immediately
        -- below, so this restore can never be applied twice.
        deferredremainingcost = LEAST(
            p.deferredremainingcost + COALESCE(r.defcost, 0),
            p.deferredtotalcost),                                        -- 279
        updatedat         = (now() at time zone 'utc')
    FROM lotrestore r
    WHERE r.purchaseid = p.waterrawmaterialpurchaseid;

    -- The draw record is spent once the lots are back; leaving it would restore
    -- the same quantity again on a second reopen.
    DELETE FROM waterrawmaterialusagebatch ub
    USING waterrawmaterialusage u
    WHERE u.waterrawmaterialusageid = ub.waterrawmaterialusageid
      AND u.farmid = p_farmid
      AND u.waterproductionbatchid = p_waterproductionbatchid;

    -- Restore raw material quantities.
    WITH used AS (
        SELECT u.waterrawmaterialitemid AS itemid, SUM(u.quantityused) AS qty
        FROM waterrawmaterialusage u
        WHERE u.farmid = p_farmid AND u.waterproductionbatchid = p_waterproductionbatchid
        GROUP BY u.waterrawmaterialitemid
    )
    UPDATE waterrawmaterialitems mi
    SET currentquantity = mi.currentquantity + x.qty,
        updatedat       = (now() at time zone 'utc')
    FROM used x
    WHERE x.itemid = mi.waterrawmaterialitemid
      AND mi.farmid = p_farmid;

    -- Cancel linked expenses. For non-credit expenses that had been booked
    -- against a cash account at approve time, post a reversing CashIn so the
    -- balance comes back to where it was. Expenses already Rejected/Cancelled
    -- are skipped.
    FOR e IN
        SELECT x.waterexpenseid AS expenseid, x.amount AS expenseamount,
               x.paymentmethod AS expensepayment, x.watercashaccountid AS expensecash
        FROM waterexpenses x
        WHERE x.farmid = p_farmid
          AND x.linkedwaterproductionbatchid = p_waterproductionbatchid
          AND x.isdeleted = FALSE
          AND x.status IN ('Draft','Submitted','Approved')
    LOOP
        IF (e.expensepayment <> 'Credit' AND e.expensecash IS NOT NULL
            AND EXISTS (SELECT 1 FROM watercashtransactions ct
                        WHERE ct.sourcetype = 'Expense' AND ct.sourceid = e.expenseid
                          AND ct.amount < 0)) THEN
            INSERT INTO watercashtransactions (
                farmid, watercashaccountid, transactiondate, transactiontype,
                sourcetype, sourceid, amount, description, createdby, approvedby, approvedat)
            VALUES (
                p_farmid, e.expensecash, (now() at time zone 'utc'), 'Adjustment',
                'Expense', e.expenseid, e.expenseamount,
                concat('Reverse - production batch ', v_batchno, ' reopened'),
                p_reopenedby, p_reopenedby, (now() at time zone 'utc'));

            UPDATE watercashaccounts ca
            SET currentbalance = ca.currentbalance + e.expenseamount,
                updatedat = (now() at time zone 'utc')
            WHERE ca.watercashaccountid = e.expensecash;
        END IF;

        UPDATE waterexpenses x
        SET status    = 'Cancelled',
            updatedat = (now() at time zone 'utc'),
            notes     = left(COALESCE(x.notes, '') || chr(10) ||
                             'Cancelled - production batch reopened.', 1000)
        WHERE x.waterexpenseid = e.expenseid;
    END LOOP;

    -- 279. Retire the consumption-recognition rows properly.
    --
    -- The loop above set every linked expense to status 'Cancelled', which is
    -- right for the P&L but NOT enough here. ux_waterexpenses_farmsource_active
    -- is predicated on `isdeleted = false` and ignores status, so a merely
    -- cancelled recognition row keeps its (farmid, sourcetype, sourceid) slot
    -- and the next approval of this batch would fail on a duplicate key. That is
    -- the same index 283 collided with from the other direction.
    --
    -- These are the only expenses on a batch that carry a sourcetype, so this is
    -- targeted rather than a broad sweep.
    UPDATE waterexpenses x
    SET    isdeleted = TRUE,
           updatedat = (now() at time zone 'utc')
    WHERE  x.farmid = p_farmid
      AND  x.sourceid = p_waterproductionbatchid
      AND  x.sourcetype IN ('WaterPackagingConsumption',
                            'WaterTreatmentConsumption',
                            'WaterSuppliesConsumption')
      AND  x.isdeleted = FALSE;

    -- Soft-delete linked loss rows. (We don't hard-delete so the auditor can
    -- still see "what was once recorded".)
    UPDATE waterproductionlosses l
    SET isdeleted = TRUE,
        status    = 'Cancelled'
    WHERE l.farmid = p_farmid
      AND l.sourcetype = 'ProductionBatch'
      AND l.sourceid   = p_waterproductionbatchid
      AND l.isdeleted  = FALSE;

    -- Flip the batch back to Draft.
    UPDATE waterproductionbatches b
    SET status     = 'Draft',
        approvedby = NULL,
        approvedat = NULL,
        updatedat  = (now() at time zone 'utc')
    WHERE b.waterproductionbatchid = p_waterproductionbatchid
      AND b.farmid = p_farmid;

    RETURN QUERY
    SELECT b.waterproductionbatchid, b.status::text, b.approvedby::text, b.approvedat
    FROM waterproductionbatches b
    WHERE b.waterproductionbatchid = p_waterproductionbatchid AND b.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. THE INTERLOCK.
--
-- 274 shipped fnwatercostrecognition_deferralready() returning FALSE, and both
-- settings writers refuse EXPENSE_WHEN_CONSUMED while it does. That is what has
-- kept every company on today's behaviour through 275, 277 and 278 -- each of
-- which is fully built but reachable only by a company that can choose deferral,
-- which none could.
--
-- The chain is now complete:
--
--   274  the decision is recorded on the purchase
--   275  a deferred purchase writes no expense, at entry or at payment
--   277  the lot carries a deferred balance and the FIFO engine draws it down
--   278  the balance is opened at purchase and follows the cost on edit
--   279  drawing the stock turns that balance into a P&L expense, and
--        reopening the batch gives it back
--
-- So the guard comes off here, and ONLY here. Lifting it earlier would have let
-- a company defer a cost that nothing would ever recognise; leaving it on now
-- would mean the whole workstream shipped switched off.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwatercostrecognition_deferralready()
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
    -- 279. The consumption side exists. Deferral may now be switched on.
    SELECT TRUE;
$function$;

COMMENT ON FUNCTION public.fnwatercostrecognition_deferralready() IS
    'Whether the phase-2 consumption chain is applied, so a company may choose '
    'EXPENSE_WHEN_CONSUMED. Set TRUE by 279. Was FALSE from 274 until then, to '
    'stop a company deferring a cost nothing would recognise.';

-- -----------------------------------------------------------------------------
-- 5. Grants.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.fnwatercostrecognition_deferralready() TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.fnwaterexpense_plline(text, text, text, text) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'approval recognises deferred cost' AS check,
       CASE WHEN position('deferredcostdrawn' in pg_get_functiondef(p.oid)) > 0
            THEN 'OK' ELSE 'NOT WIRED' END AS result
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname = 'spwaterproductionbatch_approve'

UNION ALL
SELECT 'reopen restores it',
       CASE WHEN position('deferredremainingcost' in pg_get_functiondef(p.oid)) > 0
            THEN 'OK' ELSE 'NOT WIRED' END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public' AND p.proname = 'spwaterproductionbatch_reopen'

UNION ALL
SELECT 'the supplies P&L line exists',
       CASE WHEN fnwaterexpense_plline('OperatingExpense', 'WaterSuppliesConsumption', 'x', NULL)
                 = 'ProductionSupplies' THEN 'OK' ELSE 'WRONG' END

UNION ALL
SELECT 'packaging still lands on Packaging',
       CASE WHEN fnwaterexpense_plline('OperatingExpense', 'WaterPackagingConsumption', 'x', NULL)
                 = 'Packaging' THEN 'OK' ELSE 'WRONG' END

UNION ALL
-- The one that changes: deferral is available from now on.
SELECT 'deferral interlock is OPEN',
       CASE WHEN public.fnwatercostrecognition_deferralready() THEN 'OK' ELSE 'STILL SHUT' END

UNION ALL
-- And nothing has been recognised retrospectively.
SELECT 'no consumption expense exists yet',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   waterexpenses
WHERE  sourcetype IN ('WaterPackagingConsumption', 'WaterTreatmentConsumption',
                      'WaterSuppliesConsumption')
  AND  isdeleted = FALSE;
