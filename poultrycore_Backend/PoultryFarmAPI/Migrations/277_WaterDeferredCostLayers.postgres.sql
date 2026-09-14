-- =============================================================================
-- 277_WaterDeferredCostLayers.postgres.sql
--
-- Purpose
-- -------
-- The water mirror of 264. Phase 2, part 1: give the existing cost-layer engine
-- a second number.
--
-- WHAT ALREADY EXISTED, AND IS NOT REBUILT HERE
-- =============================================
-- Worth stating, because the obvious reading of "add inventory cost layers" is
-- to add a table, and that would have been the wrong move:
--
--   waterrawmaterialpurchases    IS the cost-layer table. quantity, unitcost,
--                                totalcost, remainingquantity, the
--                                purchase-to-production unit multiplier, and
--                                since 274 the recognition snapshot.
--   waterrawmaterialusagebatch   IS the consumption-allocation table. Which
--                                usage drew from which lot, how much, at what
--                                unit cost.
--   ..._consumebatches           IS the FIFO/LIFO/HIFO engine. It orders the
--                                lots, normalises purchase units into production
--                                units, depletes remainingquantity, writes the
--                                allocations and returns the weighted cost per
--                                production unit.
--
-- A second cost-layer model beside that would be two answers to "how much stock
-- is left", and they would drift within a month.
--
-- THE ONE THING THE MODEL COULD NOT EXPRESS
-- =========================================
-- A lot has ONE totalcost, and that number means "what this stock cost" --
-- operational cost, used by production-batch costing, cost per unit and the
-- production reports. It cannot also mean "how much of this is still waiting to
-- hit Profit & Loss", because for a lot built out of other lots those are
-- different numbers:
--
--   Sachet film   5,000 deferred         (company defers packaging)
--   Chlorine      2,000 already expensed (item overrides to expense on purchase)
--   ------------------------------------
--   operational cost 7,000, but only 5,000 may ever reach the P&L again.
--   Expensing 7,000 on consumption would charge the chlorine twice.
--
-- So the lot gains a SECOND pair of numbers that shadow the first:
--
--   deferredtotalcost      what was deferred when the lot was created
--   deferredremainingcost  how much of that is left, depleted as it is consumed
--
-- totalcost and remainingquantity keep their existing meanings exactly. Nothing
-- that reads them today changes.
--
-- WHY NOT DERIVE THE DEFERRED PORTION FROM THE SNAPSHOT
-- -----------------------------------------------------
-- For a purchased lot you could: method = EXPENSE_WHEN_CONSUMED means all of it
-- is deferred. For a lot produced from other lots you could not -- the deferred
-- fraction depends on which inputs happened to be deferred on the day it was
-- made, and that is not recoverable from any current setting. It has to be
-- stored when the lot is created, which is what 278 does.
--
-- THE ALLOCATION GAINS THE SAME
-- =============================
-- waterrawmaterialusagebatch records what was drawn and what it cost. It now
-- also records how much of that cost was DEFERRED -- the amount that becomes a
-- P&L expense on consumption (279) and that has to be given back on reversal.
--
-- Storing it per allocation rather than recomputing it is what makes reversal
-- exact: the lots a usage drew from may since have been drawn from again, and
-- re-deriving the split would use today's remaining balances rather than the
-- ones that applied at the time.
--
-- EVERYTHING STARTS AT ZERO
-- =========================
-- Every existing lot is EXPENSE_WHEN_PURCHASED (274 backfilled them, and 275's
-- interlock means nothing else can have been written since), so every one of
-- them has deferred cost 0: their cost has already reached the P&L as it was
-- paid, and consuming them must never charge it again. Legacy stock is treated
-- as already expensed rather than valued by guesswork.
--
-- WHERE THIS DIFFERS FROM THE POULTRY FILE
-- ========================================
-- Only in idiom, and deliberately so. Poultry's 264 rewrote its engine around a
-- TEMP TABLE (tmp_consume_draws). Water's live engine collects its draws into a
-- **jsonb array** instead, and this file keeps that: the deferred figures are
-- two more keys on each element rather than two more columns on a temp table.
--
-- Porting poultry's temp-table shape across would have meant rewriting a working
-- engine's control flow to make a two-column addition, which is exactly the kind
-- of gratuitous divergence that makes the next person distrust the diff. The
-- arithmetic below is identical to poultry's; only the container differs.
--
-- Water's engine also carries a fifth parameter, p_computedunitcost, which the
-- live body accepts and immediately ignores (it assigns NULL over it). That is
-- preserved exactly -- the signature is what the C# layer calls, and changing it
-- here would be an unrelated break.
--
-- EFFECT ON TODAY'S NUMBERS: none. Three nullable-then-zero columns and an
-- engine that computes an extra figure nothing reads yet. No P&L, no cash, no
-- stock quantity, no operational cost moves. Every draw computes a deferred
-- share of zero, because every lot's deferred balance is zero.
--
-- Order: after 275. Before 278.
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
          AND  column_name = 'costrecognitionmethod'
    ) THEN
        RAISE EXCEPTION '277 requires 274 (waterrawmaterialpurchases.costrecognitionmethod is missing).';
    END IF;
END
$guard$;

-- -----------------------------------------------------------------------------
-- 1. The deferred pair on the cost layer.
--
-- NOT NULL DEFAULT 0 on purpose: a lot written by a code path that has never
-- heard of deferral carries no deferred cost, which is today's behaviour, rather
-- than a NULL that later arithmetic would turn into a silent nothing.
-- -----------------------------------------------------------------------------
ALTER TABLE waterrawmaterialpurchases
    ADD COLUMN IF NOT EXISTS deferredtotalcost     numeric(14,2);
ALTER TABLE waterrawmaterialpurchases
    ADD COLUMN IF NOT EXISTS deferredremainingcost numeric(14,2);

UPDATE waterrawmaterialpurchases
SET    deferredtotalcost     = COALESCE(deferredtotalcost, 0),
       deferredremainingcost = COALESCE(deferredremainingcost, 0)
WHERE  deferredtotalcost IS NULL OR deferredremainingcost IS NULL;

ALTER TABLE waterrawmaterialpurchases
    ALTER COLUMN deferredtotalcost     SET DEFAULT 0,
    ALTER COLUMN deferredremainingcost SET DEFAULT 0;
ALTER TABLE waterrawmaterialpurchases
    ALTER COLUMN deferredtotalcost     SET NOT NULL,
    ALTER COLUMN deferredremainingcost SET NOT NULL;

DO $ck$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'ck_waterrawmaterialpurchases_deferred') THEN
        ALTER TABLE waterrawmaterialpurchases
            ADD CONSTRAINT ck_waterrawmaterialpurchases_deferred
            -- Deferred cost cannot go negative, and what is left cannot exceed
            -- what there was. A consumption engine that overdraws a layer would
            -- otherwise show up as a refund rather than as an error.
            CHECK (deferredtotalcost >= 0
                   AND deferredremainingcost >= 0
                   AND deferredremainingcost <= deferredtotalcost + 0.005);
    END IF;
END
$ck$;

COMMENT ON COLUMN waterrawmaterialpurchases.totalcost IS
    'OPERATIONAL cost of this lot: what the stock cost. Drives production-batch '
    'costing, cost per unit and the production reports. Says nothing about when '
    'the cost reaches Profit & Loss.';
COMMENT ON COLUMN waterrawmaterialpurchases.deferredtotalcost IS
    'The portion of this lot never yet charged to Profit & Loss. Zero for a lot '
    'expensed at purchase. For a lot produced from other lots it is the deferred '
    'share of the inputs, which is why it cannot be derived from the snapshot.';
COMMENT ON COLUMN waterrawmaterialpurchases.deferredremainingcost IS
    'What is left of deferredtotalcost. Depleted as the lot is consumed; that '
    'depletion is the P&L expense.';

-- The deferred stock read and the reconciliation query both read this shape.
CREATE INDEX IF NOT EXISTS ix_waterrawmaterialpurchases_deferredopen
    ON waterrawmaterialpurchases (farmid, waterrawmaterialitemid)
    WHERE deferredremainingcost > 0;

-- -----------------------------------------------------------------------------
-- 2. The deferred share on the allocation.
--
-- Recorded rather than recomputed. By the time a usage is reversed the lots it
-- drew from may have been drawn from again, and re-deriving the split would use
-- today's balances instead of the ones that actually applied.
-- -----------------------------------------------------------------------------
ALTER TABLE waterrawmaterialusagebatch
    ADD COLUMN IF NOT EXISTS deferredcostdrawn numeric(14,2);

UPDATE waterrawmaterialusagebatch
SET    deferredcostdrawn = 0
WHERE  deferredcostdrawn IS NULL;

ALTER TABLE waterrawmaterialusagebatch
    ALTER COLUMN deferredcostdrawn SET DEFAULT 0;
ALTER TABLE waterrawmaterialusagebatch
    ALTER COLUMN deferredcostdrawn SET NOT NULL;

COMMENT ON COLUMN waterrawmaterialusagebatch.deferredcostdrawn IS
    'How much of this draw had never reached Profit & Loss. This is the amount '
    'consumption recognises as expense, and the amount a reversal gives back. '
    'Zero when the lot was expensed at purchase.';

-- -----------------------------------------------------------------------------
-- 3. A lot's deferred unit cost, per PRODUCTION unit.
--
-- The engine works in production units; the lot stores its remaining quantity in
-- PURCHASE units. One place for that conversion, so the callers cannot each get
-- the multiplier slightly wrong.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwaterlot_deferredunitcost(
    p_deferredremaining numeric,
    p_remainingqty      numeric,
    p_mult              numeric
) RETURNS numeric
LANGUAGE sql IMMUTABLE
AS $function$
    -- Deferred cost left, spread over the production units still in the lot.
    -- NULLIF guards the exhausted lot: no quantity left means no unit cost,
    -- not a division error.
    SELECT COALESCE(p_deferredremaining, 0)
           / NULLIF(COALESCE(p_remainingqty, 0) * COALESCE(NULLIF(p_mult, 0), 1), 0);
$function$;

COMMENT ON FUNCTION public.fnwaterlot_deferredunitcost(numeric, numeric, numeric) IS
    'Deferred cost per PRODUCTION unit remaining in a lot. Returns NULL for an '
    'exhausted lot rather than dividing by zero.';

-- -----------------------------------------------------------------------------
-- 4. The consumption engine, now also reporting the deferred share.
--
-- Reproduced from the LIVE definition. The FOR UPDATE lot lock, the ordering
-- (including its NULLS FIRST / NULLS LAST, which poultry's copy does not have),
-- the unit normalisation, the shortfall guard and its 0.0005 tolerance, the
-- remainingquantity depletion, the purchase-unit allocation rows and the
-- returned unit cost are byte for byte what they were. This function's
-- OPERATIONAL behaviour does not change at all.
--
-- What is added: each draw's DEFERRED portion is computed from the lot it came
-- from, written onto the allocation, and taken off the lot's deferred balance.
--
-- The deferred share is taken PRO RATA of the lot's remaining deferred cost
-- rather than as (quantity x deferred unit cost). Those differ by rounding, and
-- pro rata is the one that reaches exactly zero when a lot is emptied -- which is
-- what stops a lot retaining half a pesewa of deferred cost for ever.
--
-- Note the draw expression appears three times in the SELECT below -- once for
-- proddrawn, once for purchasedrawn and once inside the pro-rata. That
-- repetition is in the live body already (the first two), and the third follows
-- it rather than introducing a LATERAL that would change the plan of a function
-- that runs on every production batch.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterrawmaterialitem_consumebatches(p_farmid text, p_itemid integer, p_usageid integer, p_neededqty numeric, p_computedunitcost numeric DEFAULT NULL::numeric)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_computedunitcost numeric;
    v_usagemethod      text;
    v_draws            jsonb;
    v_totaldrawn       numeric;
    v_itemname         text;
    v_msg              text;
BEGIN
    v_computedunitcost := NULL;
    IF p_neededqty IS NULL OR p_neededqty <= 0 THEN
        RETURN NULL;
    END IF;

    v_usagemethod := COALESCE((
        SELECT mi.usagemethod FROM waterrawmaterialitems mi
        WHERE mi.waterrawmaterialitemid = p_itemid AND mi.farmid = p_farmid), 'FIFO');

    -- WITH (UPDLOCK, ROWLOCK) on the lot pool.
    PERFORM 1 FROM waterrawmaterialpurchases p
    WHERE p.waterrawmaterialitemid = p_itemid AND p.farmid = p_farmid AND p.remainingquantity > 0
    FOR UPDATE;

    SELECT jsonb_agg(jsonb_build_object(
               'purchaseid',    o.waterrawmaterialpurchaseid,
               'proddrawn',     o.prodtake,
               'purchasedrawn', o.prodtake / o.mult,
               'unitcost',      o.unitcost,
               'mult',          o.mult,
               -- 277. PRO RATA of what is left on the lot, not quantity x unit
               -- cost. Emptying a lot then takes its deferred balance to exactly
               -- zero instead of leaving a rounding crumb that could never be
               -- recognised.
               'deferreddrawn', ROUND(
                                    o.deferredremainingcost * o.prodtake
                                    / NULLIF(o.availprod, 0), 2)))
      INTO v_draws
    FROM (
        SELECT ord.waterrawmaterialpurchaseid,
               ord.unitcost,
               ord.mult,
               CASE WHEN ord.runningtotal <= p_neededqty
                    THEN ord.availprod
                    ELSE p_neededqty - (ord.runningtotal - ord.availprod) END AS prodtake,
               ord.runningtotal,
               ord.availprod,
               ord.deferredremainingcost                                   -- 277
        FROM (
            SELECT p.waterrawmaterialpurchaseid,
                   p.remainingquantity,
                   p.unitcost,
                   p.deferredremainingcost,                                -- 277
                   COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1) AS mult,
                   p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1) AS availprod,
                   SUM(p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1)) OVER (
                       ORDER BY
                           CASE WHEN v_usagemethod = 'FIFO' THEN p.purchasedate END ASC NULLS FIRST,
                           CASE WHEN v_usagemethod = 'LIFO' THEN p.purchasedate END DESC NULLS LAST,
                           CASE WHEN v_usagemethod = 'HIFO' THEN p.unitcost END DESC NULLS LAST,
                           -- Same-day lots tie on the date; under LIFO the later row
                           -- is the later purchase, so it must go first.
                           CASE WHEN v_usagemethod = 'LIFO' THEN p.waterrawmaterialpurchaseid END DESC NULLS LAST,
                           p.waterrawmaterialpurchaseid ASC
                       ROWS UNBOUNDED PRECEDING) AS runningtotal
            FROM waterrawmaterialpurchases p
            WHERE p.waterrawmaterialitemid = p_itemid AND p.farmid = p_farmid AND p.remainingquantity > 0
        ) ord
        WHERE ord.runningtotal - ord.availprod < p_neededqty
    ) o;

    SELECT COALESCE(SUM((d.value->>'proddrawn')::numeric), 0)
      INTO v_totaldrawn
    FROM jsonb_array_elements(COALESCE(v_draws, '[]'::jsonb)) AS d(value);

    IF (v_totaldrawn + 0.0005 < p_neededqty) THEN
        SELECT mi.itemname INTO v_itemname FROM waterrawmaterialitems mi
        WHERE mi.waterrawmaterialitemid = p_itemid;

        v_msg := 'Not enough tracked batch stock for "' || COALESCE(v_itemname, 'item') || '": need '
                 || p_neededqty::text || ', only ' || v_totaldrawn::text
                 || ' available across purchase batches.';
        RAISE EXCEPTION '%', v_msg;
    END IF;

    UPDATE waterrawmaterialpurchases p
    SET remainingquantity = p.remainingquantity - d.purchasedrawn,
        -- 277. The deferred balance falls with the stock. GREATEST guards the
        -- last draw on a lot: rounding must never push it below zero, and the
        -- pro-rata share above means the final draw lands exactly on it.
        deferredremainingcost = GREATEST(p.deferredremainingcost - COALESCE(d.deferreddrawn, 0), 0),
        updatedat = (now() at time zone 'utc')
    FROM (
        SELECT (e.value->>'purchaseid')::integer      AS purchaseid,
               (e.value->>'purchasedrawn')::numeric   AS purchasedrawn,
               (e.value->>'deferreddrawn')::numeric   AS deferreddrawn     -- 277
        FROM jsonb_array_elements(COALESCE(v_draws, '[]'::jsonb)) AS e(value)
    ) d
    WHERE d.purchaseid = p.waterrawmaterialpurchaseid;

    -- 277. A lot emptied of stock must be emptied of deferred cost too. Without
    -- this a rounding crumb would sit on an exhausted lot for ever: never
    -- consumable, but still counted as inventory value waiting to be expensed.
    UPDATE waterrawmaterialpurchases p
    SET    deferredremainingcost = 0
    FROM (
        SELECT (e.value->>'purchaseid')::integer AS purchaseid
        FROM jsonb_array_elements(COALESCE(v_draws, '[]'::jsonb)) AS e(value)
    ) d
    WHERE  d.purchaseid = p.waterrawmaterialpurchaseid
      AND  p.remainingquantity <= 0.0005
      AND  p.deferredremainingcost <> 0;

    -- Stored in PURCHASE units + per-purchase cost, so a reopen restores each
    -- lot with a plain `RemainingQuantity += SUM(QuantityDrawn)`.
    INSERT INTO waterrawmaterialusagebatch (waterrawmaterialusageid, waterrawmaterialpurchaseid, quantitydrawn, unitcostatdraw, deferredcostdrawn)
    SELECT p_usageid,
           (e.value->>'purchaseid')::integer,
           (e.value->>'purchasedrawn')::numeric,
           ((e.value->>'unitcost')::numeric)::numeric(14,2),
           COALESCE((e.value->>'deferreddrawn')::numeric, 0)                -- 277
    FROM jsonb_array_elements(COALESCE(v_draws, '[]'::jsonb)) AS e(value)
    WHERE (e.value->>'proddrawn')::numeric > 0;

    -- Cost per PRODUCTION unit = total purchase-cost drawn / production units drawn.
    SELECT SUM((e.value->>'purchasedrawn')::numeric * (e.value->>'unitcost')::numeric)
           / NULLIF(SUM((e.value->>'proddrawn')::numeric), 0)
      INTO v_computedunitcost
    FROM jsonb_array_elements(COALESCE(v_draws, '[]'::jsonb)) AS e(value);

    RETURN v_computedunitcost::numeric(14,4);
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Grants.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.spwaterrawmaterialitem_consumebatches(
            text, integer, integer, numeric, numeric) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.fnwaterlot_deferredunitcost(
            numeric, numeric, numeric) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'no lot starts with deferred cost' AS check,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END AS result
FROM   waterrawmaterialpurchases
WHERE  deferredtotalcost <> 0 OR deferredremainingcost <> 0

UNION ALL
SELECT 'no allocation starts with deferred cost',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   waterrawmaterialusagebatch
WHERE  deferredcostdrawn <> 0

UNION ALL
-- Legacy stock is treated as already expensed, never valued by guesswork.
SELECT 'every legacy lot reads as expensed',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   waterrawmaterialpurchases
WHERE  costrecognitionmethod = 'EXPENSE_WHEN_PURCHASED' AND deferredremainingcost > 0

UNION ALL
-- The interlock is 279's to open, not this file's.
SELECT 'deferral interlock still shut',
       CASE WHEN public.fnwatercostrecognition_deferralready() THEN 'OPEN -- WRONG' ELSE 'OK' END;
