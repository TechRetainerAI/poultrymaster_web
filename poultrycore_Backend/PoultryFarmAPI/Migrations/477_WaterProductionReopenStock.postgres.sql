-- =============================================================================
-- 477  Water: reopening and re-approving a production record moves the right
--      amount of stock
-- =============================================================================
--
-- Two faults, both in finished-goods stock (waterstocktransactions):
--
--   1. spwaterproductionbatch_reopen reversed "-good bags" with a NULL
--      basequantity, so trgwaterstockbaseqty converted it at the product's
--      CURRENT per-pack figure. If the pack size changed after production the
--      reversal took off the wrong number of bottles/sachets (Fradesa,
--      2026-11-23: 100 packs booked at 12 = 1200, reversal would be -1500).
--      Now it reverses exactly what the batch still has in stock, packs and
--      base units both, and checks availability in base units.
--
--   2. spwaterproductionbatch_approve skipped the Restock whenever a Restock row
--      with the batch's note existed. Reopen appends an Adjust and never removes
--      that row, so approve -> reopen -> approve left the batch with no stock.
--      Now it skips only while the batch's stock is still on hand.
--
-- Both bodies are the LIVE dev definitions (pg_get_functiondef, 2026-11-23)
-- with only those sections changed. Same signatures, so CREATE OR REPLACE.
-- No data is changed here: records already left at zero by fault 2 (e.g.
-- company b28ba637 B-20260528-191134) are not repaired by this migration.
--
-- Idempotent.
-- =============================================================================

BEGIN;

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
    v_currentstock numeric;
    v_netpacks     numeric;        -- 477
    v_netbase      numeric;        -- 477
    v_baseunit     text;           -- 477
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

    -- 477. Reverse EXACTLY what this batch still has in stock, in the units it
    -- was booked in. The old code reversed -goodbags with a NULL basequantity,
    -- so trgwaterstockbaseqty re-converted at TODAY's per-pack figure: a batch
    -- booked at 12 bottles a pack and reopened after the product moved to 15
    -- took 1500 bottles off for the 1200 it had added.
    --
    -- "What this batch has in stock" = its Restock rows plus any earlier
    -- reversals, keyed on the same note text _approve writes. A batch that was
    -- approved, reopened and approved again under the old code can have two
    -- Restock rows or none left in stock, and this nets both cases correctly.
    SELECT COALESCE(SUM(st.quantity), 0), COALESCE(SUM(st.basequantity), 0)
      INTO v_netpacks, v_netbase
    FROM waterstocktransactions st
    WHERE st.farmid = p_farmid AND st.waterproductid = v_productid
      AND st.note IN (concat('Production batch ', v_batchno),
                      concat('Reopen production batch ', v_batchno));

    -- Compare in base units (bottles / sachets), the unit the ledger balances in.
    v_currentstock := COALESCE((
        SELECT SUM(st.basequantity) FROM waterstocktransactions st
        WHERE st.farmid = p_farmid AND st.waterproductid = v_productid
    ), 0);

    IF v_netbase > 0 AND v_currentstock < v_netbase THEN
        SELECT lower(COALESCE(NULLIF(trim(p.baseunit), ''), 'unit')) INTO v_baseunit
        FROM waterproducts p WHERE p.waterproductid = v_productid;
        RAISE EXCEPTION 'Cannot reopen: only % %s of this product remain in stock, but the batch added %. Cancel related sales or adjust stock first.',
                        round(v_currentstock, 2), v_baseunit, round(v_netbase, 2);
    END IF;

    -- Reverse the finished goods restock with a balancing Adjust txn. The
    -- basequantity is written explicitly so the trigger does not recompute it.
    IF v_netbase > 0 OR v_netpacks > 0 THEN
        INSERT INTO waterstocktransactions
            (farmid, waterproductid, txntype, quantity, basequantity, unitcost, relatedsaleid, note, createdby)
        VALUES
            (p_farmid, v_productid, 'Adjust', -round(v_netpacks)::int, -v_netbase, NULL, NULL,
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
    -- 477. Skip only when this batch's stock is still ON HAND (its Restock
    -- rows net of reopen reversals > 0). The old test was "a Restock row with
    -- this note exists", which a reopen never removes (it appends an Adjust),
    -- so approve -> reopen -> approve put the stock back to zero.
    IF (v_goodbags > 0)
       AND COALESCE((
           SELECT SUM(st.basequantity) FROM waterstocktransactions st
           WHERE st.farmid = p_farmid AND st.waterproductid = v_productid
             AND st.note IN (concat('Production batch ', v_batchno),
                             concat('Reopen production batch ', v_batchno))
       ), 0) <= 0 THEN
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

COMMIT;
