-- 437: "Recalculate product stock" -- Birds row counts the whole farm.
--
-- Before: Birds In = flock.quantity of active flocks (for a flock set up
-- through Initial Farm Setup that is the birds ALIVE at setup, not bought),
-- Out = that minus the last production record's "birds left". Batch
-- purchases, setup deaths, historical sales and birds not yet in a flock
-- were all ignored, so a farm that bought 73,000 and has 56,000 alive showed
-- In 56,000 / Out 0.
--
-- Now the same rule as the Flocks page cards (lib/flocks/farm-bird-totals.ts):
--   In      = birds bought (batch sizes + flocks with no batch)
--   Out     = deaths + sold + other  (= In - Current)
--   Current = birds alive (in flocks + batch birds not yet in a flock)
-- Batches still Pending or starting after today: their birds not in a flock
-- are left out (not on the farm yet). Every other product is unchanged
-- (ledger In / Out / Current). Read-only: nothing is written.

BEGIN;

CREATE OR REPLACE FUNCTION public.sppoultryproduct_reconcilestock(p_farmid text, p_poultryproductid integer DEFAULT NULL::integer)
 RETURNS TABLE(poultryproductid integer, name text, stockin numeric, stockout numeric, currentstock numeric)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_birdid   integer;
    v_bought   numeric := 0;
    v_live     numeric := 0;
BEGIN
    SELECT p.poultryproductid INTO v_birdid
    FROM   poultryproducts p
    WHERE  p.farmid = p_farmid AND (COALESCE(p.isbirdproduct, FALSE) = TRUE OR p.name = 'Birds')
    ORDER  BY p.isbirdproduct DESC NULLS LAST, p.poultryproductid
    LIMIT 1;

    IF v_birdid IS NOT NULL AND (p_poultryproductid IS NULL OR p_poultryproductid = v_birdid) THEN
        -- Batches (413/420 reconciliation): every batch bird, in a flock or not.
        SELECT COALESCE(SUM(s.originalbirds - CASE WHEN na.notarrived THEN GREATEST(COALESCE(s.unallocatedlive, 0), 0) ELSE 0 END), 0),
               COALESCE(SUM(s.totallivebirds - CASE WHEN na.notarrived THEN GREATEST(COALESCE(s.unallocatedlive, 0), 0) ELSE 0 END), 0)
        INTO   v_bought, v_live
        FROM   sppoultrybatchreconcile_summary(p_farmid => p_farmid) s
        JOIN   mainflockbatch b ON b.batchid = s.batchid
        CROSS  JOIN LATERAL (SELECT (LOWER(COALESCE(b.status, '')) = 'pending'
                                     OR b.startdate::date > CURRENT_DATE) AS notarrived) na;

        -- Flocks the batches do not cover: no batch, or a batch that no longer exists.
        SELECT v_bought + COALESCE(SUM(CASE WHEN bp.historyknown THEN bp.originallyplaced ELSE bp.openinglivebirds END), 0),
               v_live   + COALESCE(SUM(bp.currentlivebirds), 0)
        INTO   v_bought, v_live
        FROM   flock f
        CROSS  JOIN LATERAL fnflock_birdposition(p_farmid, f.flockid) bp
        WHERE  f.farmid = p_farmid AND NOT COALESCE(f.isdeleted, FALSE)
          AND  (f.batchid IS NULL OR NOT EXISTS (SELECT 1 FROM mainflockbatch b2
                                                 WHERE b2.batchid = f.batchid AND b2.farmid = p_farmid));
    END IF;

    RETURN QUERY
    SELECT p.poultryproductid,
           p.name::text,
           (CASE
                WHEN p.poultryproductid = v_birdid THEN v_bought
                ELSE COALESCE((SELECT SUM(t.quantity) FROM poultrystocktransactions t
                               WHERE t.poultryproductid = p.poultryproductid AND t.farmid = p.farmid
                                 AND t.quantity > 0), 0)
           END)::numeric(18,3) AS stockin,
           (CASE
                WHEN p.poultryproductid = v_birdid THEN v_bought - v_live
                ELSE COALESCE((SELECT SUM(-t.quantity) FROM poultrystocktransactions t
                               WHERE t.poultryproductid = p.poultryproductid AND t.farmid = p.farmid
                                 AND t.quantity < 0), 0)
           END)::numeric(18,3) AS stockout,
           (CASE
                WHEN p.poultryproductid = v_birdid THEN v_live
                ELSE COALESCE((SELECT SUM(t.quantity) FROM poultrystocktransactions t
                               WHERE t.poultryproductid = p.poultryproductid AND t.farmid = p.farmid), 0)
           END)::numeric(18,3) AS currentstock
    FROM   poultryproducts p
    WHERE  p.farmid = p_farmid AND (p_poultryproductid IS NULL OR p.poultryproductid = p_poultryproductid)
    ORDER  BY p.name;
END;
$function$;

-- Self-test: on the test farm, Birds = 64,450 bought / 31,316 alive (Flocks page cards).
DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM sppoultryproduct_reconcilestock('3c4ac3cd-8792-4739-9b20-5f3b7d655a02')
    WHERE name = 'Birds';
    IF r IS NULL THEN
        RAISE NOTICE '437 self-test skipped (test farm has no Birds product)';
    ELSE
        RAISE NOTICE '437 Birds: in %, out %, current %', r.stockin, r.stockout, r.currentstock;
        IF r.stockin - r.stockout <> r.currentstock THEN
            RAISE EXCEPTION '437 self-test: in - out <> current';
        END IF;
    END IF;
END $$;

COMMIT;
