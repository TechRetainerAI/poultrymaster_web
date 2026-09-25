-- =============================================================================
-- 325_PoultryOpeningBirdLedger.postgres.sql
--
-- Purpose
-- -------
-- Put an onboarded farm's historical bird reduction into the bird stock ledger,
-- so the two places the application counts birds stop disagreeing.
--
-- THE CONTRADICTION THIS EXISTS TO KILL
-- =====================================
-- Migration 319 made a flock start life holding its OPENING LIVE birds (960 of
-- the 1,050 placed), which is what fixed "Deaths Today = 682" on a day nothing
-- died. But creating the batch still posts the full placed figure to the bird
-- ledger: spmainflockbatch_insert calls sppoultrybirdstock_sync with
-- 'Bird Batch Purchase' = numberofbirds. Nothing ever posts the 90 back out.
--
-- sppoultryclosingreport_get then returns BOTH counts on one report:
--     birdsleft     -- from flock + productionrecords -> 960
--     closingbirds  -- from poultrystocktransactions  -> 1,050
-- permanently apart by the historical reduction. This migration posts the
-- missing movement so they agree.
--
-- WHY ONE MOVEMENT AND NOT A TYPED BREAKDOWN
-- ==========================================
-- Posting -60 Mortality, -10 Bird Sale, -5 Cull was the obvious alternative and
-- is unsafe here. sppoultrybirdstock_sync identifies a movement by
-- (farmid, txntype, relatedid) and sums those rows to work out its delta. An
-- opening position id and a production record id are drawn from different
-- sequences and WILL collide: posting 'Mortality' with relatedid = 5 would read
-- production record 5's rows and compute a delta against them. Reusing an
-- existing txntype for a different kind of source silently corrupts both.
--
-- The breakdown is not lost -- it already lives in poultryopeningflockposition
-- under a CHECK constraint that forces it to reconcile. One movement here,
-- linked to that row by relatedid, keeps the ledger honest without duplicating
-- the detail in a place that cannot hold it safely.
--
-- WHY NOT sppoultrybirdstock_sync ITSELF
-- ======================================
-- It has no date parameter: every row it writes takes createddate's default of
-- now(). The closing report filters bird movements on createddate::date, so an
-- opening position dated to a company business date -- which is the whole point
-- of reading it server-side (298/299) -- would land in the wrong period when
-- posted through it. Adding a parameter would mean dropping the existing
-- function BY NAME and re-pointing all six of its callers; a sibling that takes
-- the date is the smaller and safer change. The append-only delta behaviour is
-- copied from it deliberately, so both behave identically on a re-run.
--
-- IDEMPOTENT, AND SO IS WHAT IT WRITES. Re-running Initial Farm Setup for the
-- same opening position posts a delta of zero, which writes no row at all.
--
-- EFFECT ON TODAY'S NUMBERS: none until Initial Farm Setup calls it.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Post a flock's opening historical reduction to the bird ledger.
--
-- p_reduction is the COUNT OF BIRDS that went missing before tracking began --
-- a positive number. The row written is negative, because the ledger's balance
-- is a plain SUM(quantity) and every outward movement in it is already stored
-- negative (Mortality and Bird Sale both are).
--
-- Returns the number of rows written: 1 the first time, 0 on a re-run.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryopeningbirdstock_post(
    p_farmid            text,
    p_openingpositionid integer,
    p_reduction         integer,
    p_effectivedate     date,
    p_note              text DEFAULT NULL,
    p_createdby         text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_bird   integer;
    v_target numeric;
    v_net    numeric;
    v_delta  numeric;
BEGIN
    IF p_farmid IS NULL OR p_openingpositionid IS NULL THEN
        RAISE EXCEPTION '325: farmid and openingpositionid are required.';
    END IF;

    -- Find the company's live-birds product, creating it if this is the first
    -- bird movement the farm has ever had. Same lookup order as
    -- sppoultrybirdstock_sync, so both always resolve to the same product.
    SELECT pp.poultryproductid INTO v_bird
    FROM   poultryproducts pp
    WHERE  pp.farmid = p_farmid AND (pp.isbirdproduct = TRUE OR pp.name = 'Birds')
    ORDER  BY pp.isbirdproduct DESC, pp.poultryproductid
    LIMIT  1;

    IF v_bird IS NULL THEN
        INSERT INTO poultryproducts (farmid, name, unit, unitprice, producttype,
                                     israweggproduct, requiresrecipesetup, isbirdproduct)
        VALUES (p_farmid, 'Birds', 'Bird', 0, 'FinishedGood', FALSE, FALSE, TRUE)
        RETURNING poultryproductid INTO v_bird;
    END IF;

    -- A reduction of zero is a flock that lost nothing. There is no movement to
    -- record, and writing a zero row would only add noise to the ledger.
    v_target := -ABS(COALESCE(p_reduction, 0));

    -- Append-only, exactly as sppoultrybirdstock_sync does it: post the delta
    -- needed to REACH the target for this (txntype, relatedid), never an
    -- absolute figure and never a DELETE. Re-running setup computes a delta of
    -- zero and writes nothing, which is the idempotency guarantee.
    SELECT COALESCE(SUM(t.quantity), 0) INTO v_net
    FROM   poultrystocktransactions t
    WHERE  t.farmid = p_farmid
      AND  t.txntype = 'Opening Adjustment'
      AND  t.relatedid = p_openingpositionid;

    v_delta := v_target - v_net;
    IF v_delta = 0 THEN
        RETURN 0;
    END IF;

    INSERT INTO poultrystocktransactions
        (farmid, poultryproductid, txntype, quantity, relatedid, note, createdby, createddate)
    VALUES
        (p_farmid, v_bird, 'Opening Adjustment', v_delta, p_openingpositionid,
         COALESCE(NULLIF(btrim(p_note), ''),
                  'Opening historical reduction (Initial Farm Setup)'),
         p_createdby,
         -- The COMPANY's business date, not now(). The closing report buckets
         -- bird movements by createddate::date, so a farm onboarding at 23:40
         -- in Accra must not have its opening position land in tomorrow.
         COALESCE(p_effectivedate, (now() AT TIME ZONE 'utc')::date)::timestamp);

    RETURN 1;
END
$function$;

-- -----------------------------------------------------------------------------
-- 2. Read a company's opening bird adjustments.
--
-- Joined to the opening position so a report can put "what the ledger was told"
-- beside "what the farm said the breakdown was" without stitching two lists
-- together in the caller.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryopeningbirdstock_getall(p_farmid text)
RETURNS TABLE(
    poultrystocktransactionid integer,
    farmid                    text,
    openingpositionid         integer,
    flockid                   integer,
    quantity                  numeric,
    effectivedate             date,
    note                      text,
    createdby                 text,
    originallyplaced          integer,
    openinglivebirds          integer,
    historicalreduction       integer)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT t.poultrystocktransactionid,
           t.farmid::text,
           t.relatedid,
           o.flockid,
           t.quantity,
           t.createddate::date,
           t.note::text,
           t.createdby::text,
           o.originallyplaced,
           o.openinglivebirds,
           (o.originallyplaced - o.openinglivebirds)
    FROM   poultrystocktransactions t
    LEFT   JOIN public.poultryopeningflockposition o
           ON o.openingpositionid = t.relatedid AND o.farmid = t.farmid
    WHERE  t.farmid = p_farmid
      AND  t.txntype = 'Opening Adjustment'
    ORDER  BY t.relatedid, t.poultrystocktransactionid;
END
$function$;

-- -----------------------------------------------------------------------------
-- 3. Birds a batch has actually given out.
--
-- spflock_gettotalquantityforbatch sums flock QUANTITIES, and since 319 a flock
-- created by Initial Farm Setup carries its opening LIVE birds -- 919 of the
-- 1,000 placed. Measured that way a fully-allocated batch looks like it still
-- has 81 spare, the Flock Purchases page offers to "Divide" them, and the
-- allocation guard lets someone create a flock out of birds that died months
-- ago.
--
-- A batch's numberofbirds is a PLACED figure, so what it has given out has to be
-- measured the same way: quantity plus whatever the opening position says went
-- missing before tracking began.
--
-- Deliberately a sibling rather than a redefinition of
-- spflock_gettotalquantityforbatch: that function answers a different and still
-- useful question (how many birds are standing in this batch's flocks), and
-- callers that want it should keep getting it.
--
-- It mirrors that function's row filter EXACTLY, including not filtering on
-- isdeleted -- a soft-deleted flock still counts against its batch today, and
-- changing that here would quietly hand birds back to batches all over the
-- application. If that is wrong it is wrong in both, and belongs in its own
-- migration.
--
-- No self-test below: flock carries a BEFORE DELETE soft-delete trigger
-- (tr_flock_softdelete), so fixture flocks cannot be removed again and a
-- self-test would leave sentinel rows in a real table. It is verified against
-- real batches instead, by comparing it with the figure it replaces.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spflock_getconsumedforbatch(
    p_batchid          integer,
    p_farmid           text,
    p_flockidtoexclude integer DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_total integer;
BEGIN
    -- The opening reduction is joined per flock and excluded along with its
    -- flock, so "everything except this one" stays consistent across both terms.
    SELECT COALESCE(SUM(f.quantity), 0)
         + COALESCE(SUM(GREATEST(o.originallyplaced - o.openinglivebirds, 0)), 0)
    INTO   v_total
    FROM   flock f
    LEFT   JOIN public.poultryopeningflockposition o
           ON o.flockid = f.flockid AND o.farmid = f.farmid
    WHERE  f.batchid = p_batchid
      AND  f.farmid = p_farmid
      AND  (p_flockidtoexclude IS NULL OR f.flockid <> p_flockidtoexclude);

    RETURN COALESCE(v_total, 0);
END
$function$;

-- -----------------------------------------------------------------------------
-- 4. Grants, matching the app login used by every other function here.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT SELECT, INSERT ON public.poultrystocktransactions TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryopeningbirdstock_post(text, integer, integer, date, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryopeningbirdstock_getall(text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spflock_getconsumedforbatch(integer, text, integer) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 4. Verification. Runs after COMMIT so a failure here does not undo the
--    migration -- it tells you the migration is wrong, which is different.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_missing text;
    v_farm    text := '__325_selftest__';
    v_opening integer := -325;
    v_rows    integer;
    v_net     numeric;
    v_when    date;
BEGIN
    SELECT string_agg(want, ', ')
    INTO   v_missing
    FROM   (VALUES
        ('sppoultryopeningbirdstock_post'),
        ('sppoultryopeningbirdstock_getall'),
        ('spflock_getconsumedforbatch')
    ) AS w(want)
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = w.want);

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '325: missing function(s): %', v_missing;
    END IF;

    -- The spec's worked example: 1,000 placed, 919 standing, 81 gone.
    v_when := DATE '2026-01-15';
    v_rows := public.sppoultryopeningbirdstock_post(
        v_farm, v_opening, 81, v_when, 'selftest', '__325__');
    IF v_rows <> 1 THEN
        RAISE EXCEPTION '325: the first post wrote % rows, expected 1.', v_rows;
    END IF;

    -- Stored NEGATIVE, because the ledger balance is a plain SUM.
    SELECT COALESCE(SUM(t.quantity), 0) INTO v_net
    FROM   poultrystocktransactions t
    WHERE  t.farmid = v_farm AND t.txntype = 'Opening Adjustment'
      AND  t.relatedid = v_opening;
    IF v_net <> -81 THEN
        RAISE EXCEPTION '325: the ledger nets % for the opening position, expected -81.', v_net;
    END IF;

    -- Dated to the business date it was given, not to now(). The closing report
    -- buckets on createddate::date, so this is the assertion that keeps an
    -- opening position out of the wrong period.
    IF NOT EXISTS (SELECT 1 FROM poultrystocktransactions t
                    WHERE t.farmid = v_farm AND t.txntype = 'Opening Adjustment'
                      AND t.relatedid = v_opening AND t.createddate::date = v_when) THEN
        RAISE EXCEPTION '325: the movement was not dated to the effective business date.';
    END IF;

    -- IDEMPOTENCY: re-running setup must not post a second -81.
    v_rows := public.sppoultryopeningbirdstock_post(
        v_farm, v_opening, 81, v_when, 'selftest rerun', '__325__');
    IF v_rows <> 0 THEN
        RAISE EXCEPTION '325: a re-run wrote % rows; the opening reduction was posted twice.', v_rows;
    END IF;

    SELECT COALESCE(SUM(t.quantity), 0) INTO v_net
    FROM   poultrystocktransactions t
    WHERE  t.farmid = v_farm AND t.txntype = 'Opening Adjustment'
      AND  t.relatedid = v_opening;
    IF v_net <> -81 THEN
        RAISE EXCEPTION '325: after a re-run the ledger nets %, expected -81.', v_net;
    END IF;

    -- A restated opening position moves the ledger by the DIFFERENCE, never by
    -- posting a second full row -- the same append-only rule the rest of the
    -- schema follows.
    v_rows := public.sppoultryopeningbirdstock_post(
        v_farm, v_opening, 70, v_when, 'selftest correction', '__325__');
    SELECT COALESCE(SUM(t.quantity), 0) INTO v_net
    FROM   poultrystocktransactions t
    WHERE  t.farmid = v_farm AND t.txntype = 'Opening Adjustment'
      AND  t.relatedid = v_opening;
    IF v_rows <> 1 OR v_net <> -70 THEN
        RAISE EXCEPTION '325: a restated reduction netted % in % row(s), expected -70.', v_net, v_rows;
    END IF;

    -- A flock that lost nothing writes nothing.
    IF public.sppoultryopeningbirdstock_post(v_farm, -3250, 0, v_when, NULL, '__325__') <> 0 THEN
        RAISE EXCEPTION '325: a zero reduction wrote a ledger row.';
    END IF;

    IF (SELECT count(*) FROM public.sppoultryopeningbirdstock_getall(v_farm)) <> 2 THEN
        RAISE EXCEPTION '325: getall did not return the rows just written.';
    END IF;

    DELETE FROM poultrystocktransactions
     WHERE farmid = v_farm AND txntype = 'Opening Adjustment';
    DELETE FROM poultryproducts WHERE farmid = v_farm;

    RAISE NOTICE '325_PoultryOpeningBirdLedger: 2 functions, verified.';
END $$;
