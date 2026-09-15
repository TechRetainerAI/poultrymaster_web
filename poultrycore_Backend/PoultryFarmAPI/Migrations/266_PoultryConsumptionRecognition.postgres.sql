-- =============================================================================
-- 266_PoultryConsumptionRecognition.postgres.sql
--
-- Purpose
-- -------
-- Phase 2, part 3: the deferred cost finally reaches Profit & Loss.
--
-- 264 gave the lots a deferred balance. 265 opened it on purchase and carried it
-- through feed production. This file spends it: when feed or medication is
-- actually consumed, the deferred share of what was drawn becomes an expense.
--
-- ONE PLACE, NOT FOUR
-- ===================
-- Feed usage and medication usage both run through
-- sppoultryproductionrawmaterialsync -- one function, called when a production
-- record is created, edited or deleted. So consumption recognition needs one
-- integration point, not one per screen, and the FIFO/LIFO/HIFO engine below it
-- has already worked out the per-lot split before this file adds anything.
--
-- WHAT IS RECOGNISED, AND WHAT IS NOT
-- ===================================
--   deferredcostdrawn > 0    the lot had never been expensed. That amount is
--                            the expense, and it is exactly what 264 recorded
--                            on the allocation.
--   deferredcostdrawn = 0    the lot was expensed when it was bought. Consuming
--                            it costs nothing further. THIS is the rule that
--                            stops the same cedi being charged twice, and it is
--                            per LOT, not per item -- one draw can cross an old
--                            expensed lot and a new deferred one and recognise
--                            only the second.
--
-- The decision is never taken from today's settings. It comes from the
-- allocation, which came from the lot, which was stamped when it was created.
--
-- A NON-CASH EVENT
-- ================
-- The expense is written paymentmethod = 'NonCash' -- the marker this codebase
-- has used since 216 for "a cost recorded, but the money moved elsewhere".
-- Following it through:
--
--   sppoultrycashflow_rows   skips NonCash, so consuming stock moves no cash
--   fnpoultrypayables        skips NonCash, so it never becomes a debt
--   sppoultryreport_profitloss  does NOT skip it -- which is the whole point
--
-- No cash transaction. No supplier payment. No supplier balance. The money left
-- when the stock was paid for; this is only the P&L catching up.
--
-- CATEGORIES
-- ----------
-- 'Feed Cost' and 'Medication', chosen to match what sppoultryreport_profitloss
-- already sorts on ('%feed%' and '%medic%'). Consumption cost therefore lands
-- in the same P&L line as the purchase cost it replaces, rather than in Other.
--
-- LINKED TO THE RECORD, NOT THE USAGE ROW
-- =======================================
-- The expense carries sourcetype 'PoultryFeedConsumption' /
-- 'PoultryMedicationConsumption' and sourceid = the PRODUCTION RECORD.
--
-- Not the usage row, deliberately. Editing a production record DELETES its live
-- usage rows and rewrites them -- that is how this function has always worked --
-- so an expense pointing at a usage id would dangle after the first edit. The
-- production record is stable, and the trail is still complete: record -> usage
-- rows -> allocations -> lots.
--
-- REVERSAL AND EDIT ARE THE SAME PROBLEM
-- ======================================
-- Both mean "what was recognised for this record is no longer true". Both are
-- handled the same way and append-only: before anything is restored, the live
-- recognition for the record is compensated by one opposite row, and then --
-- for an edit -- the new lines recognise afresh. Nothing is deleted, and the
-- rows for a record always sum to what is currently recognised, which is what
-- makes the compensation self-correcting however many times it is edited.
--
-- THE OTHER HALF OF REVERSAL
-- ==========================
-- Restoring stock has to restore its deferred cost too, or the second
-- consumption of the same stock would recognise nothing. Both reversal paths
-- gain that: the production-record restore here, and the feed-production
-- reversal, which puts the ingredients' deferred cost back on the lots it took
-- it from.
--
-- Feed production reversal creates NO P&L entry, because posting created none --
-- it was a transfer. Section 71C of the brief, and it falls out of the design
-- rather than needing a special case.
--
-- WHAT IS NOT DONE HERE
-- =====================
-- Internal use and stock adjustments can also reduce stock. Neither is wired to
-- recognition in this file: internal use already writes its own non-cash expense
-- (216), so adding a second would double-count, and a negative adjustment may be
-- a loss, a correction or a count fix -- three different expenses, and guessing
-- would be worse than waiting. 267 reports both as reconciliation gaps rather
-- than silently mis-recognising them.
--
-- EFFECT ON TODAY'S NUMBERS: none. Every lot in the database is deferred 0, so
-- every draw recognises 0 and every compensation is 0.
--
-- Order: after 265.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Recognise a consumed deferred cost.
--
-- One writer for both feed and medication, so the two can never drift into
-- different ideas of what a consumption expense looks like. Returns the expense
-- id, or NULL when there was nothing to recognise -- which is the ordinary case
-- on a farm that expenses at purchase.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryconsumption_recognise(
    p_farmid       text,
    p_sourcetype   text,      -- PoultryFeedConsumption | PoultryMedicationConsumption
    p_sourceid     integer,   -- the production record
    p_category     text,      -- Feed Cost | Medication
    p_amount       numeric,
    p_date         timestamp,
    p_description  text,
    p_createdby    text
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_gid uuid;
    v_id  integer;
BEGIN
    IF COALESCE(p_amount, 0) = 0 THEN
        RETURN NULL;               -- nothing deferred; nothing to say
    END IF;

    -- expense.farmid is a uuid where every other poultry table uses varchar.
    -- A farm whose id will not cast cannot have expenses linked at all, and the
    -- consumption must still succeed -- same guard the purchase SP has used
    -- since 130/207.
    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;
    IF v_gid IS NULL OR p_createdby IS NULL THEN
        RETURN NULL;
    END IF;

    INSERT INTO expense
        (expensedate, category, description, amount, paymentmethod, supplier, flockid,
         createddate, userid, farmid, sourcetype, sourceid, amountpaid)
    VALUES
        (COALESCE(p_date, (now() at time zone 'utc')), p_category, p_description,
         p_amount,
         -- The marker that keeps it out of cash flow and out of payables while
         -- leaving it in the P&L.
         'NonCash',
         -- No supplier. A lender is not a supplier and neither is a flock: this
         -- is the business consuming its own stock.
         NULL, NULL,
         (now() at time zone 'utc'), p_createdby, v_gid,
         p_sourcetype, p_sourceid,
         -- Settled by definition: the money went when the stock was bought, so
         -- this must never read as an unpaid bill.
         p_amount)
    RETURNING expenseid INTO v_id;

    RETURN v_id;
END;
$function$;

COMMENT ON FUNCTION public.sppoultryconsumption_recognise(text, text, integer, text, numeric, timestamp, text, text) IS
    'Writes ONE non-cash P&L expense for a deferred cost that has been consumed. '
    'Never writes cash, a supplier payment or a balance. Returns NULL when there '
    'was nothing deferred, which is the normal case on a farm that expenses at '
    'purchase.';

-- -----------------------------------------------------------------------------
-- 2. Undo what a record has recognised so far.
--
-- Append-only: one opposite row, the originals kept. Because it always
-- compensates the CURRENT SUM, calling it twice is harmless and calling it after
-- five edits still lands on zero -- there is no running total to get wrong.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryconsumption_unrecognise(
    p_farmid     text,
    p_sourcetype text,
    p_sourceid   integer,
    p_category   text,
    p_reason     text,
    p_createdby  text
) RETURNS numeric
LANGUAGE plpgsql
AS $function$
DECLARE
    v_gid uuid;
    v_net numeric(14,2);
BEGIN
    BEGIN
        v_gid := p_farmid::uuid;
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;
    IF v_gid IS NULL THEN RETURN 0; END IF;

    SELECT COALESCE(SUM(e.amount), 0)::numeric(14,2) INTO v_net
    FROM   expense e
    WHERE  e.farmid = v_gid AND e.sourcetype = p_sourcetype AND e.sourceid = p_sourceid;

    IF COALESCE(v_net, 0) = 0 THEN
        RETURN 0;
    END IF;

    INSERT INTO expense
        (expensedate, category, description, amount, paymentmethod, supplier, flockid,
         createddate, userid, farmid, sourcetype, sourceid, amountpaid)
    VALUES
        ((now() at time zone 'utc'), p_category, p_reason,
         -v_net, 'NonCash', NULL, NULL,
         (now() at time zone 'utc'), p_createdby, v_gid,
         p_sourcetype, p_sourceid, -v_net);

    RETURN v_net;
END;
$function$;

COMMENT ON FUNCTION public.sppoultryconsumption_unrecognise(text, text, integer, text, text, text) IS
    'Cancels a record''s consumption expense with one opposite row, keeping the '
    'originals. Compensates the CURRENT SUM, so repeated edits cannot drift.';

-- -----------------------------------------------------------------------------
-- 3. Consumption recognises; reversal and edit give it back.
--
-- Reproduced from the LIVE definition of sppoultryproductionrawmaterialsync.
-- The line building, the pure-reversal detection, the lot restore, the
-- compensating adjustments, both consumption loops and the computed unit costs
-- it returns are all exactly what they were.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryproductionrawmaterialsync(p_farmid text, p_productionid integer, p_feeditemid integer DEFAULT NULL::integer, p_feedqty numeric DEFAULT NULL::numeric, p_meditemid integer DEFAULT NULL::integer, p_medqty numeric DEFAULT NULL::numeric, p_createdby text DEFAULT NULL::text, p_medicationsjson text DEFAULT NULL::text, p_feedsjson text DEFAULT NULL::text, OUT computedfeedunitcost numeric, OUT computedtotalfeedcost numeric, OUT computedmedicationunitcost numeric, OUT computedtotalmedicationcost numeric)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_ispurereversal boolean;
    v_feedtotalcost  numeric := 0;
    v_feedtotalqty   numeric := 0;
    v_appliedanyfeed boolean := FALSE;
    v_medtotalcost   numeric := 0;
    v_medtotalqty    numeric := 0;
    v_appliedanymed  boolean := FALSE;
    v_usageid        integer;
    v_lineunitcost   numeric;
    v_linetotal      numeric;
    v_linename       text;
    -- 266. What each draw actually deferred, and the running totals that become
    -- the two consumption expenses.
    v_linedeferred   numeric(14,2);
    v_feeddeferred   numeric(14,2) := 0;
    v_meddeferred    numeric(14,2) := 0;
    v_rec            record;
BEGIN
    computedfeedunitcost := NULL; computedtotalfeedcost := NULL;
    computedmedicationunitcost := NULL; computedtotalmedicationcost := NULL;

    -- Build the feed / medication lines to (re)apply up-front so we can tell a PURE
    -- REVERSAL (nothing to re-apply - the delete path) from a re-apply (insert/edit).
    DROP TABLE IF EXISTS tmp_prms_feedlines;
    CREATE TEMP TABLE tmp_prms_feedlines (seq integer, itemid integer, qty numeric) ON COMMIT DROP;
    IF (p_feedsjson IS NOT NULL AND length(p_feedsjson) > 0) THEN
        INSERT INTO tmp_prms_feedlines (seq, itemid, qty)
        SELECT row_number() OVER (ORDER BY x.ord), x.itemid, x.qty
        FROM (SELECT (e.value->>'itemId')::integer AS itemid,
                     (e.value->>'qty')::numeric(14,3) AS qty,
                     e.ord
              FROM jsonb_array_elements(p_feedsjson::jsonb) WITH ORDINALITY AS e(value, ord)) x
        WHERE x.itemid IS NOT NULL AND COALESCE(x.qty, 0) > 0;
    ELSIF (p_feeditemid IS NOT NULL AND COALESCE(p_feedqty, 0) > 0) THEN
        INSERT INTO tmp_prms_feedlines (seq, itemid, qty) VALUES (1, p_feeditemid, p_feedqty);
    END IF;

    DROP TABLE IF EXISTS tmp_prms_medlines;
    CREATE TEMP TABLE tmp_prms_medlines (seq integer, itemid integer, qty numeric) ON COMMIT DROP;
    IF (p_medicationsjson IS NOT NULL AND length(p_medicationsjson) > 0) THEN
        INSERT INTO tmp_prms_medlines (seq, itemid, qty)
        SELECT row_number() OVER (ORDER BY x.ord), x.itemid, x.qty
        FROM (SELECT (e.value->>'itemId')::integer AS itemid,
                     (e.value->>'qty')::numeric(14,3) AS qty,
                     e.ord
              FROM jsonb_array_elements(p_medicationsjson::jsonb) WITH ORDINALITY AS e(value, ord)) x
        WHERE x.itemid IS NOT NULL AND COALESCE(x.qty, 0) > 0;
    ELSIF (p_meditemid IS NOT NULL AND COALESCE(p_medqty, 0) > 0) THEN
        INSERT INTO tmp_prms_medlines (seq, itemid, qty) VALUES (1, p_meditemid, p_medqty);
    END IF;

    v_ispurereversal := (NOT EXISTS (SELECT 1 FROM tmp_prms_feedlines)
                         AND NOT EXISTS (SELECT 1 FROM tmp_prms_medlines));

    -- 266. Whatever this record has recognised so far is about to stop being
    -- true -- the lines are being restored and, on an edit, rewritten. Give it
    -- back FIRST, with one opposite row, before anything else moves. Doing it
    -- here rather than at the end means a failure part-way through cannot leave
    -- an expense standing for stock that was handed back.
    PERFORM sppoultryconsumption_unrecognise(
        p_farmid, 'PoultryFeedConsumption', p_productionid, 'Feed Cost',
        'Reversal of feed consumption (record #' || p_productionid::text || ')', p_createdby);
    PERFORM sppoultryconsumption_unrecognise(
        p_farmid, 'PoultryMedicationConsumption', p_productionid, 'Medication',
        'Reversal of medication consumption (record #' || p_productionid::text || ')', p_createdby);

    -- 1. Reverse this record's still-live consumption. Restore the drawn lots +
    --    CurrentQuantity (scoped to non-reversed rows so a later edit never
    --    double-restores).
    DROP TABLE IF EXISTS tmp_prms_restore;
    CREATE TEMP TABLE tmp_prms_restore ON COMMIT DROP AS
    SELECT u.poultryrawmaterialitemid AS itemid, SUM(u.quantityused) AS qty
    FROM poultryrawmaterialusage u
    WHERE u.farmid = p_farmid AND u.productionrecordid = p_productionid AND u.isreversed = FALSE
    GROUP BY u.poultryrawmaterialitemid;

    UPDATE poultryrawmaterialpurchases p
    SET remainingquantity = p.remainingquantity + bb.qty,
        -- 266. The deferred cost comes back with the stock, from the exact
        -- allocations that took it. Without this the same stock could be
        -- consumed twice and only be expensed once.
        --
        -- LEAST caps it at what the lot started with: restoring more deferred
        -- cost than a lot ever had would create money, and the check constraint
        -- from 264 would refuse the row anyway.
        deferredremainingcost = LEAST(p.deferredremainingcost + bb.deferred, p.deferredtotalcost),
        updatedat = (now() at time zone 'utc')
    FROM (
        SELECT b.poultryrawmaterialpurchaseid AS purchaseid, SUM(b.quantitydrawn) AS qty,
               SUM(b.deferredcostdrawn) AS deferred
        FROM poultryrawmaterialusagebatch b
        JOIN poultryrawmaterialusage u ON u.poultryrawmaterialusageid = b.poultryrawmaterialusageid
        WHERE u.farmid = p_farmid AND u.productionrecordid = p_productionid AND u.isreversed = FALSE
        GROUP BY b.poultryrawmaterialpurchaseid
    ) bb
    WHERE bb.purchaseid = p.poultryrawmaterialpurchaseid;

    UPDATE poultryrawmaterialitems it
    SET currentquantity = it.currentquantity + r.qty,
        updatedat = (now() at time zone 'utc')
    FROM tmp_prms_restore r
    WHERE r.itemid = it.poultryrawmaterialitemid AND it.farmid = p_farmid;

    IF v_ispurereversal THEN
        -- KEEP the original usage rows (append-only ledger); flag them reversed so
        -- they drop out of the next restore aggregate.
        UPDATE poultryrawmaterialusage u
        SET isreversed = TRUE, reversedat = (now() at time zone 'utc')
        WHERE u.farmid = p_farmid AND u.productionrecordid = p_productionid AND u.isreversed = FALSE;

        -- Compensating IN adjustment per item - the visible opposite entry, and it
        -- keeps recalc (purchases - usage + adjustments) consistent with the restore.
        INSERT INTO poultryrawmaterialadjustments (farmid, poultryrawmaterialitemid, adjusteddate, quantity, movementtype, note, createdby)
        SELECT p_farmid, r.itemid, (now() at time zone 'utc'), r.qty, 'ProductionReversal',
               'Reversal of production consumption (record #' || p_productionid::text || ')', p_createdby
        FROM tmp_prms_restore r WHERE r.qty <> 0;
    ELSE
        -- Re-apply (insert/edit): physically remove the current live usage rows;
        -- the loops below rewrite them. Reversed rows (if any) are left untouched.
        DELETE FROM poultryrawmaterialusage u
        WHERE u.farmid = p_farmid AND u.productionrecordid = p_productionid AND u.isreversed = FALSE;
    END IF;

    -- Costing detail is current-state (not a stock ledger) - keep replacing it.
    DELETE FROM productionrecordfeeds f
    WHERE f.farmid = p_farmid AND f.productionrecordid = p_productionid;

    DELETE FROM productionrecordmedications m
    WHERE m.farmid = p_farmid AND m.productionrecordid = p_productionid;

    -- 2. Apply feed consumption from the lines built above.
    FOR v_rec IN SELECT fl.itemid, fl.qty FROM tmp_prms_feedlines fl ORDER BY fl.seq LOOP
        IF (v_rec.itemid IS NOT NULL AND v_rec.qty > 0) THEN
            v_lineunitcost := NULL;
            INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, productionrecordid, quantityused, notes, createdby)
            VALUES (p_farmid, v_rec.itemid, p_productionid, v_rec.qty, 'Feed used in production', p_createdby)
            RETURNING poultryrawmaterialusageid INTO v_usageid;

            v_lineunitcost := sppoultryrawmaterialitem_consumebatches(p_farmid, v_rec.itemid, v_usageid, v_rec.qty);

            -- 266. Read the deferred share the engine has just recorded, per
            -- lot. A draw that crossed an old expensed lot and a new deferred
            -- one contributes only the second.
            v_linedeferred := COALESCE((
                SELECT SUM(b.deferredcostdrawn) FROM poultryrawmaterialusagebatch b
                WHERE  b.poultryrawmaterialusageid = v_usageid), 0);
            v_feeddeferred := v_feeddeferred + v_linedeferred;

            UPDATE poultryrawmaterialitems it
            SET currentquantity = it.currentquantity - v_rec.qty,
                updatedat = (now() at time zone 'utc')
            WHERE it.poultryrawmaterialitemid = v_rec.itemid AND it.farmid = p_farmid;

            SELECT it.itemname INTO v_linename FROM poultryrawmaterialitems it
            WHERE it.poultryrawmaterialitemid = v_rec.itemid AND it.farmid = p_farmid;
            v_linetotal := (COALESCE(v_lineunitcost, 0) * v_rec.qty)::numeric(14,2);

            INSERT INTO productionrecordfeeds (farmid, productionrecordid, poultryrawmaterialitemid, itemname, quantityconsumed, unitcost, totalcost)
            VALUES (p_farmid, p_productionid, v_rec.itemid, v_linename, v_rec.qty, COALESCE(v_lineunitcost, 0), v_linetotal);

            v_feedtotalcost := v_feedtotalcost + v_linetotal;
            v_feedtotalqty  := v_feedtotalqty + v_rec.qty;
            v_appliedanyfeed := TRUE;
        END IF;
    END LOOP;

    IF v_appliedanyfeed THEN
        computedfeedunitcost := CASE WHEN v_feedtotalqty > 0 THEN v_feedtotalcost / v_feedtotalqty ELSE NULL END;
        computedtotalfeedcost := v_feedtotalcost;
    END IF;

    -- 3. Apply medication consumption from the lines built above.
    FOR v_rec IN SELECT ml.itemid, ml.qty FROM tmp_prms_medlines ml ORDER BY ml.seq LOOP
        IF (v_rec.itemid IS NOT NULL AND v_rec.qty > 0) THEN
            v_lineunitcost := NULL;
            INSERT INTO poultryrawmaterialusage (farmid, poultryrawmaterialitemid, productionrecordid, quantityused, notes, createdby)
            VALUES (p_farmid, v_rec.itemid, p_productionid, v_rec.qty, 'Medication used in production', p_createdby)
            RETURNING poultryrawmaterialusageid INTO v_usageid;

            v_lineunitcost := sppoultryrawmaterialitem_consumebatches(p_farmid, v_rec.itemid, v_usageid, v_rec.qty);

            v_linedeferred := COALESCE((
                SELECT SUM(b.deferredcostdrawn) FROM poultryrawmaterialusagebatch b
                WHERE  b.poultryrawmaterialusageid = v_usageid), 0);
            v_meddeferred := v_meddeferred + v_linedeferred;

            UPDATE poultryrawmaterialitems it
            SET currentquantity = it.currentquantity - v_rec.qty,
                updatedat = (now() at time zone 'utc')
            WHERE it.poultryrawmaterialitemid = v_rec.itemid AND it.farmid = p_farmid;

            SELECT it.itemname INTO v_linename FROM poultryrawmaterialitems it
            WHERE it.poultryrawmaterialitemid = v_rec.itemid AND it.farmid = p_farmid;
            v_linetotal := (COALESCE(v_lineunitcost, 0) * v_rec.qty)::numeric(14,2);

            INSERT INTO productionrecordmedications (farmid, productionrecordid, poultryrawmaterialitemid, itemname, quantityconsumed, unitcost, totalcost)
            VALUES (p_farmid, p_productionid, v_rec.itemid, v_linename, v_rec.qty, COALESCE(v_lineunitcost, 0), v_linetotal);

            v_medtotalcost := v_medtotalcost + v_linetotal;
            v_medtotalqty  := v_medtotalqty + v_rec.qty;
            v_appliedanymed := TRUE;
        END IF;
    END LOOP;

    IF v_appliedanymed THEN
        computedmedicationunitcost := CASE WHEN v_medtotalqty > 0 THEN v_medtotalcost / v_medtotalqty ELSE NULL END;
        computedtotalmedicationcost := v_medtotalcost;
    END IF;

    -- 266. And finally the P&L. One expense per kind, for the deferred share
    -- only -- both are zero, and nothing is written at all, on a farm that
    -- expenses at purchase.
    --
    -- After the loops on purpose: the totals are only known once every line has
    -- drawn, and writing per line would scatter a single event across the
    -- expense list.
    PERFORM sppoultryconsumption_recognise(
        p_farmid, 'PoultryFeedConsumption', p_productionid, 'Feed Cost',
        v_feeddeferred, (now() at time zone 'utc'),
        'Feed consumed (production record #' || p_productionid::text || ')', p_createdby);

    PERFORM sppoultryconsumption_recognise(
        p_farmid, 'PoultryMedicationConsumption', p_productionid, 'Medication',
        v_meddeferred, (now() at time zone 'utc'),
        'Medication consumed (production record #' || p_productionid::text || ')', p_createdby);
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Feed production reversal puts the deferred cost back too.
--
-- Reproduced from the LIVE definition. The cycle boundary, the already-used
-- guard, the compensating adjustments, the produced-lot draw-down and the cash
-- reversal are all unchanged. What is added is the deferred cost travelling with
-- the quantity, in both directions.
--
-- The already-used guard is worth pointing at rather than adding to: it already
-- refuses to reverse a batch whose feed has been eaten, which is exactly what
-- section 30 of the brief asks for and was in place long before this work.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryfeedproductionbatch_reverse(p_farmid text, p_poultryfeedproductionbatchid integer, p_reversedby text DEFAULT NULL::text, p_reversalreason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_status             text;
    v_finishedfeeditemid integer;
    v_batchnumber        text;
    v_productiondate     timestamp;
    v_postedat           timestamp;
    v_producedlotcount   integer;
    v_boundary           timestamp;
    v_produced           numeric(18,3);
    v_remaining          numeric(18,3);
    v_revusageid         integer;
    v_newbal             numeric(14,2);
    r                    record;
BEGIN
    SELECT b.status, b.finishedfeeditemid, b.batchnumber, b.productiondate, b.postedat
    INTO   v_status, v_finishedfeeditemid, v_batchnumber, v_productiondate, v_postedat
    FROM   poultryfeedproductionbatches b
    WHERE  b.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid AND b.farmid = p_farmid;

    IF v_status IS NULL      THEN RAISE EXCEPTION 'Feed production batch not found.'; END IF;
    IF v_status = 'Draft'    THEN RAISE EXCEPTION 'Draft batches are edited or deleted, not reversed.'; END IF;
    IF v_status = 'Reversed' THEN RAISE EXCEPTION 'This batch has already been reversed.'; END IF;

    -- Cycle boundary: only offset rows created since this cycle's PostedAt. Skipped
    -- (NULL) for a batch that was never reposted (a single produced lot) so legacy
    -- batches - whose PostedAt predates the cycle-stamp scheme - reverse in full.
    v_producedlotcount := (SELECT COUNT(*) FROM poultryrawmaterialpurchases p
        WHERE p.sourcefeedproductionbatchid = p_poultryfeedproductionbatchid
          AND p.poultryrawmaterialitemid = v_finishedfeeditemid AND p.farmid = p_farmid);
    v_boundary := CASE WHEN v_producedlotcount > 1 THEN v_postedat ELSE NULL END;

    -- Guard: block if the CURRENT cycle's produced feed has been used (lot not intact).
    v_produced  := COALESCE((SELECT SUM(p.quantity) FROM poultryrawmaterialpurchases p
        WHERE p.sourcefeedproductionbatchid = p_poultryfeedproductionbatchid
          AND p.poultryrawmaterialitemid = v_finishedfeeditemid AND p.farmid = p_farmid
          AND (v_boundary IS NULL OR p.createdat >= v_boundary)), 0);
    v_remaining := COALESCE((SELECT SUM(p.remainingquantity) FROM poultryrawmaterialpurchases p
        WHERE p.sourcefeedproductionbatchid = p_poultryfeedproductionbatchid
          AND p.poultryrawmaterialitemid = v_finishedfeeditemid AND p.farmid = p_farmid
          AND (v_boundary IS NULL OR p.createdat >= v_boundary)), 0);
    IF (v_remaining + 0.0005 < v_produced) THEN
        RAISE EXCEPTION 'This batch cannot be reversed because some of the produced feed has already been used. Reverse the related feed usage first.';
    END IF;

    -- 1. Reverse the current cycle's INVENTORY-portion ingredient draws (drew from
    --    normal lots - SourceFeedProductionBatchId IS NULL).
    -- 1a. Return the ingredient to the exact lots it was drawn from.
    UPDATE poultryrawmaterialpurchases p
    SET    remainingquantity = p.remainingquantity + ub.quantitydrawn,
           -- 266. The deferred cost goes back to the lots it came from, exactly
           -- as the quantity does. Without it the ingredients would return to
           -- stock stripped of the cost that was still waiting to be recognised,
           -- and mixing them again would defer nothing.
           deferredremainingcost = LEAST(p.deferredremainingcost + ub.deferredcostdrawn,
                                         p.deferredtotalcost),
           updatedat         = (now() AT TIME ZONE 'utc')
    FROM   poultryrawmaterialusagebatch ub
    JOIN   poultryrawmaterialusage u ON u.poultryrawmaterialusageid = ub.poultryrawmaterialusageid
    WHERE  ub.poultryrawmaterialpurchaseid = p.poultryrawmaterialpurchaseid
      AND  u.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid AND u.farmid = p_farmid
      AND  p.sourcefeedproductionbatchid IS NULL
      AND  (v_boundary IS NULL OR u.createdat >= v_boundary);

    -- 1b. Compensating IN adjustment per ingredient + bump CurrentQuantity. Usage rows KEPT.
    WITH invuse AS (
        SELECT u.poultryrawmaterialitemid AS itemid, SUM(ub.quantitydrawn) AS qty
        FROM   poultryrawmaterialusage u
        JOIN   poultryrawmaterialusagebatch ub ON ub.poultryrawmaterialusageid = u.poultryrawmaterialusageid
        JOIN   poultryrawmaterialpurchases p ON p.poultryrawmaterialpurchaseid = ub.poultryrawmaterialpurchaseid
        WHERE  u.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid AND u.farmid = p_farmid
          AND  p.sourcefeedproductionbatchid IS NULL
          AND  (v_boundary IS NULL OR u.createdat >= v_boundary)
        GROUP  BY u.poultryrawmaterialitemid
    )
    INSERT INTO poultryrawmaterialadjustments
        (farmid, poultryrawmaterialitemid, adjusteddate, quantity, movementtype, note, createdby)
    SELECT p_farmid, invuse.itemid, (now() AT TIME ZONE 'utc'), invuse.qty, 'FeedProductionReversal',
           concat('Reversal of feed production ', v_batchnumber), p_reversedby
    FROM   invuse WHERE invuse.qty > 0;

    UPDATE poultryrawmaterialitems it
    SET    currentquantity = it.currentquantity + iv.qty,
           updatedat       = (now() AT TIME ZONE 'utc')
    FROM  (SELECT u.poultryrawmaterialitemid AS itemid, SUM(ub.quantitydrawn) AS qty
           FROM   poultryrawmaterialusage u
           JOIN   poultryrawmaterialusagebatch ub ON ub.poultryrawmaterialusageid = u.poultryrawmaterialusageid
           JOIN   poultryrawmaterialpurchases p ON p.poultryrawmaterialpurchaseid = ub.poultryrawmaterialpurchaseid
           WHERE  u.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid AND u.farmid = p_farmid
             AND  p.sourcefeedproductionbatchid IS NULL
             AND  (v_boundary IS NULL OR u.createdat >= v_boundary)
           GROUP  BY u.poultryrawmaterialitemid) iv
    WHERE  iv.itemid = it.poultryrawmaterialitemid
      AND  it.farmid = p_farmid;

    -- 2. Remove the current cycle's PRODUCED finished feed via an append-only draw
    --    against its produced lot(s), zeroing them. Lot rows KEPT.
    FOR r IN
        SELECT p.poultryrawmaterialpurchaseid AS prodlotid,
               p.remainingquantity            AS prodqty,
               p.unitcost                     AS produnitcost,
               p.deferredremainingcost        AS proddeferred
        FROM   poultryrawmaterialpurchases p
        WHERE  p.sourcefeedproductionbatchid = p_poultryfeedproductionbatchid
          AND  p.poultryrawmaterialitemid = v_finishedfeeditemid AND p.farmid = p_farmid
          AND  p.remainingquantity > 0
          AND  (v_boundary IS NULL OR p.createdat >= v_boundary)
    LOOP
        INSERT INTO poultryrawmaterialusage
            (farmid, poultryrawmaterialitemid, quantityused, unitcost, notes, createdby)
        VALUES (p_farmid, v_finishedfeeditemid, r.prodqty, r.produnitcost,
                concat('Reversal of produced feed ', v_batchnumber), p_reversedby)
        RETURNING poultryrawmaterialusageid INTO v_revusageid;

        -- 266. The draw carries the produced lot's remaining deferred cost, so
        -- the ledger balances: what the ingredients got back is exactly what
        -- the finished feed gave up. Note this is NOT recognised as an expense --
        -- posting the batch never expensed anything, it only moved value, so
        -- unposting it has nothing to charge.
        INSERT INTO poultryrawmaterialusagebatch
            (poultryrawmaterialusageid, poultryrawmaterialpurchaseid, quantitydrawn, unitcostatdraw, deferredcostdrawn)
        VALUES (v_revusageid, r.prodlotid, r.prodqty, r.produnitcost, COALESCE(r.proddeferred, 0));

        UPDATE poultryrawmaterialpurchases p
        SET    remainingquantity = 0, deferredremainingcost = 0,
               updatedat = (now() AT TIME ZONE 'utc')
        WHERE  p.poultryrawmaterialpurchaseid = r.prodlotid;
    END LOOP;

    UPDATE poultryrawmaterialitems it
    SET    currentquantity = CASE WHEN it.currentquantity - v_produced < 0 THEN 0
                                  ELSE it.currentquantity - v_produced END,
           updatedat = (now() AT TIME ZONE 'utc')
    WHERE  it.poultryrawmaterialitemid = v_finishedfeeditemid AND it.farmid = p_farmid;

    -- 3. Bought-during-production ingredient lots are net-zero; rows KEPT, no offset.

    -- 4. Reverse the current cycle's cash - append an opposite CashIn per account.
    FOR r IN
        SELECT t.poultrycashaccountid AS acctid, SUM(t.amount) AS outamt   -- Amount is negative (cash out)
        FROM   poultrycashtransactions t
        WHERE  t.sourcetype = 'FeedProduction' AND t.sourceid = p_poultryfeedproductionbatchid
          AND  t.farmid = p_farmid
          AND  (v_boundary IS NULL OR t.createdat >= v_boundary)
        GROUP  BY t.poultrycashaccountid
    LOOP
        UPDATE poultrycashaccounts a
        SET    currentbalance = a.currentbalance - r.outamt, updatedat = (now() AT TIME ZONE 'utc')
        WHERE  a.poultrycashaccountid = r.acctid AND a.farmid = p_farmid;

        SELECT a.currentbalance INTO v_newbal
        FROM   poultrycashaccounts a
        WHERE  a.poultrycashaccountid = r.acctid AND a.farmid = p_farmid;

        INSERT INTO poultrycashtransactions
            (farmid, poultrycashaccountid, transactiondate, transactiontype, sourcetype, sourceid,
             amount, balanceaftertransaction, description, createdby)
        VALUES (p_farmid, r.acctid, v_productiondate, 'CashIn', 'FeedProductionReversal',
                p_poultryfeedproductionbatchid, -r.outamt, v_newbal,
                concat('Reversal of feed production ', v_batchnumber), p_reversedby);
    END LOOP;

    -- 5. Mark reversed (keep line/cost + all ledger history for the record).
    UPDATE poultryfeedproductionbatches b
    SET    status = 'Reversed', reversedby = p_reversedby, reversedat = (now() AT TIME ZONE 'utc'),
           reversalreason = p_reversalreason, updatedat = (now() AT TIME ZONE 'utc')
    WHERE  b.poultryfeedproductionbatchid = p_poultryfeedproductionbatchid AND b.farmid = p_farmid;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'no consumption expense exists yet' AS check,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END AS result
FROM   expense
WHERE  sourcetype IN ('PoultryFeedConsumption', 'PoultryMedicationConsumption')

UNION ALL
-- Nothing is deferred anywhere, so nothing could have been recognised.
SELECT 'still nothing deferred anywhere',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   poultryrawmaterialpurchases
WHERE  deferredremainingcost > 0

UNION ALL
-- The two writers must exist for the sync function to call them.
SELECT 'both recognition functions exist',
       CASE WHEN COUNT(*) = 2 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'public'
  AND  p.proname IN ('sppoultryconsumption_recognise', 'sppoultryconsumption_unrecognise');
