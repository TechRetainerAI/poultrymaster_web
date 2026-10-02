-- =============================================================================
-- backfill-325-opening-bird-ledger.sql
--
-- One-off data fix for farms onboarded through Initial Farm Setup BEFORE
-- migration 325 existed.
--
-- Those farms have an opening position saying "1,000 placed, 919 standing" but
-- no corresponding movement in the bird ledger, so sppoultryclosingreport_get
-- reports two different bird counts from the same screen:
--     birdsleft    (flock + productionrecords) -> 919
--     closingbirds (poultrystocktransactions)  -> 1,000
-- This posts the missing movement so they agree.
--
-- WHAT IT CHANGES: closingbirds/openingbirds on the closing report drop by the
-- historical reduction, to the figure the flocks have always reported. No flock,
-- production record, sale, expense or cash row is touched. Nothing else in the
-- application reads the bird ledger -- sppoultryproduct_getall special-cases the
-- Birds product and computes it from flocks, so the Stock page does not move.
--
-- SAFE TO RUN MORE THAN ONCE. sppoultryopeningbirdstock_post is append-only and
-- posts the DELTA needed to reach the target for (farmid, 'Opening Adjustment',
-- openingpositionid). A position that already carries its movement gets a delta
-- of zero and no row is written.
--
-- Each movement is dated to its own opening position's effectivebusinessdate --
-- the day that farm's tracking actually began -- not to the day this script ran,
-- so a backfilled farm's opening position lands in the period it belongs to.
--
-- Requires: migration 325 applied.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    v_row     record;
    v_written integer;
    v_rows    integer := 0;
    v_birds   integer := 0;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'public' AND p.proname = 'sppoultryopeningbirdstock_post') THEN
        RAISE EXCEPTION 'backfill-325: migration 325 has not been applied.';
    END IF;

    FOR v_row IN
        SELECT o.farmid,
               o.openingpositionid,
               o.flockid,
               (o.originallyplaced - o.openinglivebirds) AS reduction,
               o.effectivebusinessdate
        FROM   public.poultryopeningflockposition o
        WHERE  o.originallyplaced > o.openinglivebirds
        ORDER  BY o.farmid, o.openingpositionid
    LOOP
        v_written := public.sppoultryopeningbirdstock_post(
            v_row.farmid,
            v_row.openingpositionid,
            v_row.reduction,
            v_row.effectivebusinessdate,
            'Opening historical reduction (backfilled for migration 325)',
            'backfill-325');

        IF v_written > 0 THEN
            v_rows  := v_rows + v_written;
            v_birds := v_birds + v_row.reduction;
            RAISE NOTICE 'backfill-325: farm % flock % opening position % -> -% birds on %',
                v_row.farmid, v_row.flockid, v_row.openingpositionid,
                v_row.reduction, v_row.effectivebusinessdate;
        END IF;
    END LOOP;

    RAISE NOTICE 'backfill-325: % movement(s) written, % bird(s) in total.', v_rows, v_birds;
END $$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification. Every opening position that lost birds must now carry exactly
-- its own reduction in the ledger -- no more, no less, and never twice.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_bad integer;
BEGIN
    SELECT count(*)
    INTO   v_bad
    FROM   public.poultryopeningflockposition o
    WHERE  o.originallyplaced > o.openinglivebirds
      AND  COALESCE((SELECT SUM(t.quantity) FROM public.poultrystocktransactions t
                     WHERE t.farmid = o.farmid
                       AND t.txntype = 'Opening Adjustment'
                       AND t.relatedid = o.openingpositionid), 0)
           <> -(o.originallyplaced - o.openinglivebirds);

    IF v_bad > 0 THEN
        RAISE EXCEPTION 'backfill-325: % opening position(s) still disagree with the ledger.', v_bad;
    END IF;

    RAISE NOTICE 'backfill-325: every opening position reconciles with the bird ledger.';
END $$;
