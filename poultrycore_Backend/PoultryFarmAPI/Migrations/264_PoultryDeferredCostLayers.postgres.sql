-- =============================================================================
-- 264_PoultryDeferredCostLayers.postgres.sql
--
-- Purpose
-- -------
-- Phase 2, part 1: give the existing cost-layer engine a second number.
--
-- WHAT ALREADY EXISTED, AND IS NOT REBUILT HERE
-- =============================================
-- Worth stating, because the obvious reading of "add inventory cost layers" is
-- to add a table, and that would have been the wrong move:
--
--   poultryrawmaterialpurchases     IS the cost-layer table. quantity, unitcost,
--                                   totalcost, remainingquantity, the
--                                   purchase-to-production unit multiplier, and
--                                   since 261 the recognition snapshot.
--   poultryrawmaterialusagebatch    IS the consumption-allocation table. Which
--                                   usage drew from which lot, how much, at what
--                                   unit cost.
--   ..._consumebatches              IS the FIFO/LIFO/HIFO engine. It orders the
--                                   lots, normalises purchase units into
--                                   production units, depletes remainingquantity,
--                                   writes the allocations and returns the
--                                   weighted cost per production unit.
--   Feed production                 ALREADY transfers value: it consumes
--                                   ingredient lots and writes the finished feed
--                                   back as a lot in the same table, so the
--                                   consumption engine cannot tell produced feed
--                                   from bought feed. It does not need to.
--
-- A second cost-layer model beside that would be two answers to "how much stock
-- is left", and they would drift within a month.
--
-- THE ONE THING THE MODEL COULD NOT EXPRESS
-- =========================================
-- A lot has ONE totalcost, and that number means "what this stock cost" --
-- operational cost, used by feed-production costing, cost per kg, formula
-- analysis and the production reports. It cannot also mean "how much of this is
-- still waiting to hit Profit & Loss", because for a produced feed lot those
-- are different numbers:
--
--   Maize   5,000 deferred        (farm defers feed)
--   Premix  2,000 already expensed (item overrides to expense on purchase)
--   ------------------------------
--   Produced feed: operational cost 7,000, but only 5,000 may ever reach the
--   P&L again. Expensing 7,000 on consumption would charge the premix twice.
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
-- is deferred. For a PRODUCED lot you could not -- the deferred fraction depends
-- on which ingredients happened to be deferred on the day it was mixed, and that
-- is not recoverable from any current setting. It has to be stored when the lot
-- is created, which is what 265 does.
--
-- THE ALLOCATION GAINS THE SAME
-- =============================
-- poultryrawmaterialusagebatch records what was drawn and what it cost. It now
-- also records how much of that cost was DEFERRED -- the amount that becomes a
-- P&L expense on consumption (266) and that has to be given back on reversal.
--
-- Storing it per allocation rather than recomputing it is what makes reversal
-- exact: the lots a usage drew from may since have been drawn from again, and
-- re-deriving the split would use today's remaining balances rather than the
-- ones that applied at the time.
--
-- EVERYTHING STARTS AT ZERO
-- =========================
-- All 77 existing lots are EXPENSE_WHEN_PURCHASED (261 backfilled them), so
-- every one of them has deferred cost 0: their cost has already reached the P&L
-- as it was paid, and consuming them must never charge it again. Legacy stock is
-- treated as already expensed rather than valued by guesswork -- exactly what
-- section 52 of the brief asks for.
--
-- EFFECT ON TODAY'S NUMBERS: none. Four nullable-then-zero columns and one
-- function that computes an extra figure nothing reads yet. No P&L, no cash, no
-- stock quantity, no operational cost moves.
--
-- Order: after 263.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The deferred pair on the cost layer.
--
-- NOT NULL DEFAULT 0 on purpose: a lot written by a code path that has never
-- heard of deferral carries no deferred cost, which is today's behaviour, rather
-- than a NULL that later arithmetic would turn into a silent nothing.
-- -----------------------------------------------------------------------------
ALTER TABLE poultryrawmaterialpurchases
    ADD COLUMN IF NOT EXISTS deferredtotalcost     numeric(14,2);
ALTER TABLE poultryrawmaterialpurchases
    ADD COLUMN IF NOT EXISTS deferredremainingcost numeric(14,2);

UPDATE poultryrawmaterialpurchases
SET    deferredtotalcost     = COALESCE(deferredtotalcost, 0),
       deferredremainingcost = COALESCE(deferredremainingcost, 0)
WHERE  deferredtotalcost IS NULL OR deferredremainingcost IS NULL;

ALTER TABLE poultryrawmaterialpurchases
    ALTER COLUMN deferredtotalcost     SET DEFAULT 0,
    ALTER COLUMN deferredremainingcost SET DEFAULT 0;
ALTER TABLE poultryrawmaterialpurchases
    ALTER COLUMN deferredtotalcost     SET NOT NULL,
    ALTER COLUMN deferredremainingcost SET NOT NULL;

DO $ck$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'ck_poultryrawmaterialpurchases_deferred') THEN
        ALTER TABLE poultryrawmaterialpurchases
            ADD CONSTRAINT ck_poultryrawmaterialpurchases_deferred
            -- Deferred cost cannot go negative, and what is left cannot exceed
            -- what there was. A consumption engine that overdraws a layer would
            -- otherwise show up as a refund rather than as an error.
            CHECK (deferredtotalcost >= 0
                   AND deferredremainingcost >= 0
                   AND deferredremainingcost <= deferredtotalcost + 0.005);
    END IF;
END
$ck$;

COMMENT ON COLUMN poultryrawmaterialpurchases.totalcost IS
    'OPERATIONAL cost of this lot: what the stock cost. Drives feed-production '
    'costing, cost per unit and the production reports. Says nothing about when '
    'the cost reaches Profit & Loss.';
COMMENT ON COLUMN poultryrawmaterialpurchases.deferredtotalcost IS
    'The portion of this lot never yet charged to Profit & Loss. Zero for a lot '
    'expensed at purchase. For PRODUCED feed it is the deferred share of the '
    'ingredients, which is why it cannot be derived from the snapshot.';
COMMENT ON COLUMN poultryrawmaterialpurchases.deferredremainingcost IS
    'What is left of deferredtotalcost. Depleted as the lot is consumed; that '
    'depletion is the P&L expense.';

-- The deferred stock report and the reconciliation query both read this shape.
CREATE INDEX IF NOT EXISTS ix_poultryrawmaterialpurchases_deferredopen
    ON poultryrawmaterialpurchases (farmid, poultryrawmaterialitemid)
    WHERE deferredremainingcost > 0;

-- -----------------------------------------------------------------------------
-- 2. The deferred share on the allocation.
--
-- Recorded rather than recomputed. By the time a usage is reversed the lots it
-- drew from may have been drawn from again, and re-deriving the split would use
-- today's balances instead of the ones that actually applied.
-- -----------------------------------------------------------------------------
ALTER TABLE poultryrawmaterialusagebatch
    ADD COLUMN IF NOT EXISTS deferredcostdrawn numeric(14,2);

UPDATE poultryrawmaterialusagebatch
SET    deferredcostdrawn = 0
WHERE  deferredcostdrawn IS NULL;

ALTER TABLE poultryrawmaterialusagebatch
    ALTER COLUMN deferredcostdrawn SET DEFAULT 0;
ALTER TABLE poultryrawmaterialusagebatch
    ALTER COLUMN deferredcostdrawn SET NOT NULL;

COMMENT ON COLUMN poultryrawmaterialusagebatch.deferredcostdrawn IS
    'How much of this draw had never reached Profit & Loss. This is the amount '
    'consumption recognises as expense, and the amount a reversal gives back. '
    'Zero when the lot was expensed at purchase.';

-- -----------------------------------------------------------------------------
-- 3. A lot's deferred unit cost, per PRODUCTION unit.
--
-- The engine works in production units; the lot stores its remaining quantity in
-- PURCHASE units. One place for that conversion, so the three callers cannot
-- each get the multiplier slightly wrong.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrylot_deferredunitcost(
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

COMMENT ON FUNCTION public.fnpoultrylot_deferredunitcost(numeric, numeric, numeric) IS
    'Deferred cost per PRODUCTION unit remaining in a lot. Returns NULL for an '
    'exhausted lot rather than dividing by zero.';

-- -----------------------------------------------------------------------------
-- 4. The consumption engine, now also reporting the deferred share.
--
-- Reproduced from the LIVE definition. The ordering, the unit normalisation, the
-- shortfall guard, the remainingquantity depletion and the returned unit cost are
-- byte for byte what they were -- this function's operational behaviour does not
-- change at all.
--
-- What is added: each draw's DEFERRED portion is computed from the lot it came
-- from, written onto the allocation, and taken off the lot's deferred balance.
--
-- The deferred share is taken PRO RATA of the lot's remaining deferred cost
-- rather than as (quantity x deferred unit cost). Those differ by rounding, and
-- pro rata is the one that reaches exactly zero when a lot is emptied -- which is
-- what section 33 asks for and what stops a lot retaining half a pesewa of
-- deferred cost for ever.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialitem_consumebatches(p_farmid text, p_itemid integer, p_usageid integer, p_neededqty numeric)
 RETURNS numeric
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_computedunitcost numeric := NULL;
    v_usagemethod text;
    v_totaldrawn numeric;
    v_itemname text;
BEGIN
    IF p_neededqty IS NULL OR p_neededqty <= 0 THEN
        RETURN NULL;
    END IF;

    v_usagemethod := COALESCE((
        SELECT i.usagemethod FROM poultryrawmaterialitems i
        WHERE i.poultryrawmaterialitemid = p_itemid AND i.farmid = p_farmid
        LIMIT 1), 'FIFO');

    DROP TABLE IF EXISTS tmp_consume_draws;
    CREATE TEMP TABLE tmp_consume_draws (
        purchaseid integer,
        proddrawn numeric,
        purchasedrawn numeric,
        unitcost numeric,
        mult numeric,
        -- 264. The lot's state at the moment of the draw, so the deferred share
        -- can be worked out below without reading the row twice.
        availprod numeric,
        deferredremaining numeric,
        deferreddrawn numeric
    ) ON COMMIT DROP;

    INSERT INTO tmp_consume_draws (purchaseid, proddrawn, purchasedrawn, unitcost, mult,
                                   availprod, deferredremaining, deferreddrawn)
    SELECT o.poultryrawmaterialpurchaseid,
           CASE WHEN o.runningtotal <= p_neededqty THEN o.availprod ELSE p_neededqty - (o.runningtotal - o.availprod) END,
           (CASE WHEN o.runningtotal <= p_neededqty THEN o.availprod ELSE p_neededqty - (o.runningtotal - o.availprod) END) / o.mult,
           o.unitcost, o.mult,
           o.availprod, o.deferredremainingcost,
           -- 264. PRO RATA of what is left, not quantity x unit cost. Emptying a
           -- lot then takes its deferred balance to exactly zero instead of
           -- leaving a rounding crumb that could never be recognised.
           ROUND(
             o.deferredremainingcost
             * (CASE WHEN o.runningtotal <= p_neededqty THEN o.availprod ELSE p_neededqty - (o.runningtotal - o.availprod) END)
             / NULLIF(o.availprod, 0)
           , 2)
    FROM (
        SELECT p.poultryrawmaterialpurchaseid, p.remainingquantity, p.unitcost,
               p.deferredremainingcost,
               COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1) AS mult,
               p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1) AS availprod,
               SUM(p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1)) OVER (
                   ORDER BY
                       CASE WHEN v_usagemethod = 'FIFO' THEN p.purchasedate END ASC,
                       CASE WHEN v_usagemethod = 'LIFO' THEN p.purchasedate END DESC,
                       CASE WHEN v_usagemethod = 'HIFO' THEN p.unitcost END DESC,
                       -- Same-day lots tie on the date; under LIFO the later row
                       -- is the later purchase, so it must go first.
                       CASE WHEN v_usagemethod = 'LIFO' THEN p.poultryrawmaterialpurchaseid END DESC,
                       p.poultryrawmaterialpurchaseid ASC
                   ROWS UNBOUNDED PRECEDING) AS runningtotal
        FROM poultryrawmaterialpurchases p
        WHERE p.poultryrawmaterialitemid = p_itemid AND p.farmid = p_farmid AND p.remainingquantity > 0
    ) o
    WHERE o.runningtotal - o.availprod < p_neededqty;

    v_totaldrawn := (SELECT COALESCE(SUM(d.proddrawn), 0) FROM tmp_consume_draws d);
    IF v_totaldrawn + 0.0005 < p_neededqty THEN
        SELECT i.itemname INTO v_itemname FROM poultryrawmaterialitems i
        WHERE i.poultryrawmaterialitemid = p_itemid
        LIMIT 1;
        RAISE EXCEPTION 'Not enough tracked batch stock for "%": need %, only % available across purchase batches.',
            COALESCE(v_itemname, 'item'), p_neededqty, v_totaldrawn;
    END IF;

    UPDATE poultryrawmaterialpurchases p
    SET remainingquantity = p.remainingquantity - d.purchasedrawn,
        -- 264. The deferred balance falls with the stock. GREATEST guards the
        -- last draw on a lot: rounding must never push it below zero, and the
        -- pro-rata share above means the final draw lands exactly on it.
        deferredremainingcost = GREATEST(p.deferredremainingcost - COALESCE(d.deferreddrawn, 0), 0),
        updatedat = (now() at time zone 'utc')
    FROM tmp_consume_draws d
    WHERE d.purchaseid = p.poultryrawmaterialpurchaseid;

    -- A lot emptied of stock must be emptied of deferred cost too. Without this
    -- a rounding crumb would sit on an exhausted lot for ever: never consumable,
    -- but still counted as inventory value waiting to be expensed.
    UPDATE poultryrawmaterialpurchases p
    SET    deferredremainingcost = 0
    FROM   tmp_consume_draws d
    WHERE  d.purchaseid = p.poultryrawmaterialpurchaseid
      AND  p.remainingquantity <= 0.0005
      AND  p.deferredremainingcost <> 0;

    -- Store the PURCHASE-unit draw + per-purchase cost, so 158's reversal
    -- (RemainingQuantity += SUM(QuantityDrawn)) restores lots correctly.
    INSERT INTO poultryrawmaterialusagebatch (poultryrawmaterialusageid, poultryrawmaterialpurchaseid, quantitydrawn, unitcostatdraw, deferredcostdrawn)
    SELECT p_usageid, d.purchaseid, d.purchasedrawn, d.unitcost::numeric(14,2),
           COALESCE(d.deferreddrawn, 0)
    FROM tmp_consume_draws d WHERE d.proddrawn > 0;

    -- Cost per PRODUCTION unit = total purchase-cost drawn / total production units drawn.
    SELECT SUM(d.purchasedrawn * d.unitcost) / NULLIF(SUM(d.proddrawn), 0)
      INTO v_computedunitcost
    FROM tmp_consume_draws d;

    DROP TABLE IF EXISTS tmp_consume_draws;
    RETURN v_computedunitcost;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'no lot starts with deferred cost' AS check,
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END AS result
FROM   poultryrawmaterialpurchases
WHERE  deferredtotalcost <> 0 OR deferredremainingcost <> 0

UNION ALL
SELECT 'no allocation starts with deferred cost',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   poultryrawmaterialusagebatch
WHERE  deferredcostdrawn <> 0

UNION ALL
-- Legacy stock is treated as already expensed, never valued by guesswork.
SELECT 'every legacy lot reads as expensed',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   poultryrawmaterialpurchases
WHERE  costrecognitionmethod = 'EXPENSE_WHEN_PURCHASED' AND deferredremainingcost > 0;
