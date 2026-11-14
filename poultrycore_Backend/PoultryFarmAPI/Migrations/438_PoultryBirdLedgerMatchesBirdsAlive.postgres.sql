-- 438: Stock Movements "Birds" Net = birds alive.
--
-- The Birds rows on Stock Movements should add up to the birds alive (the
-- Flocks page and "Recalculate product stock", 437). They did not, because:
--   A. Flocks deleted before 414 never took their birds back out of the rows
--      (414's delete releases them; the older delete only flagged the flock).
--   B. Deleting a batch zeroed its purchase but left its other bird rows
--      (historical sale, deaths of its flocks) behind.
--   C. A flock left alive after its batch was deleted (or never in a batch)
--      had no purchase row, only its deaths / sales.
--
-- 1. fnpoultrybirdledger_rows: every Birds row with the flock and batch it
--    belongs to (a death row via its production record, a sale via its sale).
-- 2. fnpoultrybirdledger_check: per batch / flock, rows vs birds alive -- the
--    diagnosis for any farm, before and after.
-- 3. spmainflockbatch_delete: refuses while the batch still has flocks or
--    birds sold / lost recorded against it, and takes the rows of its deleted
--    flocks out with it.
-- 4. One-off correction: one "Ledger Correction" row per flock / deleted
--    batch that is out (txntype Ledger Correction, reason says why). Nothing
--    is deleted or edited. Bird counts are not affected: the Flocks page,
--    reconciliation and reports read flocks and production records.
--
-- Left as is (they are real, not wrong rows):
--   * a historical batch not reconciled yet: the rows count its birds, the
--     bird counts call them unaccounted for until Batch Bird Reconciliation;
--   * a row with neither flock nor batch (an old sale with no flock).

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Every Birds row, with its flock and batch.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrybirdledger_rows(p_farmid text)
 RETURNS TABLE(poultrystocktransactionid integer, txntype text, reason text, quantity numeric, flockid integer, batchid integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH bird AS (
        SELECT p.poultryproductid
        FROM   poultryproducts p
        WHERE  p.farmid = p_farmid AND (COALESCE(p.isbirdproduct, FALSE) = TRUE OR p.name = 'Birds')
        ORDER  BY p.isbirdproduct DESC NULLS LAST, p.poultryproductid
        LIMIT  1
    ),
    t AS (
        SELECT t.poultrystocktransactionid, t.txntype::text AS txntype, t.reason, t.quantity, t.relatedid,
               t.batchid AS tbatch,
               COALESCE(t.flockid,
                        CASE WHEN t.txntype = 'Mortality' THEN (SELECT pr.flockid FROM productionrecords pr
                                                                WHERE pr.id = t.relatedid AND pr.farmid = t.farmid)
                             WHEN t.txntype = 'Bird Sale' THEN (SELECT s.flockid FROM sale s
                                                                WHERE s.saleid = t.relatedid AND s.farmid = t.farmid)
                        END) AS fid,
               CASE WHEN t.txntype = 'Bird Sale' THEN (SELECT s.batchid FROM sale s
                                                       WHERE s.saleid = t.relatedid AND s.farmid = t.farmid) END AS sbatch
        FROM   poultrystocktransactions t
        WHERE  t.farmid = p_farmid AND t.poultryproductid = (SELECT poultryproductid FROM bird)
    )
    SELECT t.poultrystocktransactionid, t.txntype, t.reason, t.quantity, t.fid,
           CASE WHEN t.txntype = 'Bird Batch Purchase' THEN t.relatedid
                ELSE COALESCE(t.tbatch, f.batchid, t.sbatch) END
    FROM   t LEFT JOIN flock f ON f.flockid = t.fid AND f.farmid = p_farmid;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Rows vs birds alive, per batch and per flock outside a batch.
--    kind: Batch | FlockNoBatch | DeletedFlockNoBatch | DeletedBatch | NoFlockNoBatch
--    expected = what the rows should add up to; difference = rows - expected.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrybirdledger_check(p_farmid text)
 RETURNS TABLE(kind text, batchid integer, flockid integer, label text, ledger numeric, expected numeric, difference numeric, note text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH l AS (SELECT * FROM fnpoultrybirdledger_rows(p_farmid)),
    b AS (SELECT b.batchid FROM mainflockbatch b WHERE b.farmid = p_farmid),
    s AS (SELECT * FROM sppoultrybatchreconcile_summary(p_farmid => p_farmid)),
    -- Flocks counted outside a batch: no batch, or their batch is gone.
    nb AS (
        SELECT f.flockid, f.name::text AS name, f.batchid, COALESCE(f.isdeleted, FALSE) AS del, bp.currentlivebirds
        FROM   flock f CROSS JOIN LATERAL fnflock_birdposition(p_farmid, f.flockid) bp
        WHERE  f.farmid = p_farmid AND (f.batchid IS NULL OR f.batchid NOT IN (SELECT batchid FROM b))
    )
    -- Existing batches: their rows (purchase, pool, flocks) = birds alive.
    -- A historical batch not reconciled yet keeps its unexplained birds.
    SELECT 'Batch', s.batchid, NULL::int, s.batchcode,
           COALESCE((SELECT SUM(x.quantity) FROM l x WHERE x.batchid = s.batchid), 0),
           (s.totallivebirds + CASE WHEN s.ishistorical THEN GREATEST(s.unexplained, 0) ELSE 0 END)::numeric,
           COALESCE((SELECT SUM(x.quantity) FROM l x WHERE x.batchid = s.batchid), 0)
             - (s.totallivebirds + CASE WHEN s.ishistorical THEN GREATEST(s.unexplained, 0) ELSE 0 END),
           CASE WHEN s.ishistorical AND s.unexplained > 0
                THEN s.unexplained || ' historical birds not reconciled yet (counted in the rows)' END
    FROM   s
    UNION ALL
    -- Flocks outside a batch: alive = their birds, deleted = nothing.
    SELECT CASE WHEN nb.del THEN 'DeletedFlockNoBatch' ELSE 'FlockNoBatch' END, nb.batchid, nb.flockid, nb.name,
           COALESCE((SELECT SUM(x.quantity) FROM l x WHERE x.flockid = nb.flockid), 0),
           CASE WHEN nb.del THEN 0 ELSE nb.currentlivebirds END::numeric,
           COALESCE((SELECT SUM(x.quantity) FROM l x WHERE x.flockid = nb.flockid), 0)
             - CASE WHEN nb.del THEN 0 ELSE nb.currentlivebirds END,
           NULL
    FROM   nb
    UNION ALL
    -- Batches that no longer exist: rows not belonging to one of the flocks above.
    SELECT 'DeletedBatch', x.batchid, NULL::int, 'batch #' || x.batchid, SUM(x.quantity), 0::numeric, SUM(x.quantity), NULL
    FROM   l x
    WHERE  x.batchid IS NOT NULL AND x.batchid NOT IN (SELECT batchid FROM b)
      AND  (x.flockid IS NULL OR x.flockid NOT IN (SELECT flockid FROM nb))
    GROUP  BY x.batchid
    UNION ALL
    SELECT 'NoFlockNoBatch', NULL::int, NULL::int, 'rows with no flock or batch', SUM(x.quantity), 0::numeric, SUM(x.quantity),
           'e.g. an old bird sale with no flock -- left as is'
    FROM   l x
    WHERE  x.batchid IS NULL AND x.flockid IS NULL
    HAVING SUM(x.quantity) <> 0;
$function$;

-- ---------------------------------------------------------------------------
-- 3. Batch delete.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spmainflockbatch_delete(p_batchid integer, p_userid text, p_farmid text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_code text;
    v_n    integer;
    v_net  numeric;
    v_bird integer;
    r      record;
BEGIN
    SELECT b.batchcode INTO v_code FROM mainflockbatch b
    WHERE  b.batchid = p_batchid AND b.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RETURN; END IF;

    -- 438: a flock left behind keeps birds with no purchase.
    SELECT COUNT(*) INTO v_n FROM flock f
    WHERE  f.farmid = p_farmid AND f.batchid = p_batchid AND NOT COALESCE(f.isdeleted, FALSE);
    IF v_n > 0 THEN
        RAISE EXCEPTION 'Batch "%" still has % flock(s). Delete those flocks first, or close them to keep their history.', v_code, v_n
            USING ERRCODE = 'P0001';
    END IF;

    -- 438: birds sold or lost straight from the batch (Batch Bird Reconciliation,
    -- historical sales) carry money and debts; they are reversed on their own.
    SELECT COALESCE(SUM(l.quantity), 0) INTO v_net FROM fnpoultrybirdledger_rows(p_farmid) l
    WHERE  l.batchid = p_batchid AND l.flockid IS NULL AND l.txntype <> 'Bird Batch Purchase';
    IF v_net <> 0 THEN
        RAISE EXCEPTION 'Batch "%" has % birds sold or lost recorded against it (Batch Bird Reconciliation). Reverse those first.', v_code, -v_net
            USING ERRCODE = 'P0001';
    END IF;

    -- 438: rows of its deleted flocks (deleted before 414) go with the batch.
    SELECT p.poultryproductid INTO v_bird FROM poultryproducts p
    WHERE  p.farmid = p_farmid AND (COALESCE(p.isbirdproduct, FALSE) = TRUE OR p.name = 'Birds')
    ORDER  BY p.isbirdproduct DESC NULLS LAST, p.poultryproductid LIMIT 1;
    FOR r IN
        SELECT l.flockid, SUM(l.quantity) AS net
        FROM   fnpoultrybirdledger_rows(p_farmid) l
        WHERE  l.batchid = p_batchid AND l.flockid IS NOT NULL
        GROUP  BY l.flockid HAVING SUM(l.quantity) <> 0
    LOOP
        INSERT INTO poultrystocktransactions
            (farmid, poultryproductid, txntype, quantity, note, createdby, batchid, flockid, effectivedate, reason, birdscope)
        VALUES
            (p_farmid, v_bird, 'Ledger Correction', -r.net,
             left('Batch ' || v_code || ' deleted: rows of its deleted flock #' || r.flockid || ' taken out', 500),
             p_userid, p_batchid, r.flockid, CURRENT_DATE, 'Batch Deleted', 'Flock');
    END LOOP;

    PERFORM sppoultrybirdstock_sync(p_farmid, 'Bird Batch Purchase', 0::numeric, p_batchid, NULL::text, p_userid);
    PERFORM spflockbatchexpense_sync(p_farmid, p_batchid, 0::numeric, NULL::timestamp, NULL::text, 0, p_userid);
    DELETE FROM mainflockbatch b WHERE b.batchid = p_batchid AND b.farmid = p_farmid;
END
$function$;

-- ---------------------------------------------------------------------------
-- 4. One-off correction, every poultry farm.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_farm  record;
    v_bird  integer;
    r       record;
    v_rows  integer := 0;
    v_birds numeric := 0;
BEGIN
    FOR v_farm IN SELECT DISTINCT t.farmid FROM poultrystocktransactions t LOOP
        SELECT p.poultryproductid INTO v_bird FROM poultryproducts p
        WHERE  p.farmid = v_farm.farmid AND (COALESCE(p.isbirdproduct, FALSE) = TRUE OR p.name = 'Birds')
        ORDER  BY p.isbirdproduct DESC NULLS LAST, p.poultryproductid LIMIT 1;
        CONTINUE WHEN v_bird IS NULL;

        FOR r IN
            WITH l AS (SELECT * FROM fnpoultrybirdledger_rows(v_farm.farmid)),
            b AS (SELECT b.batchid, b.batchcode::text AS code FROM mainflockbatch b WHERE b.farmid = v_farm.farmid),
            fl AS (
                SELECT f.flockid, f.name::text AS name, f.batchid, COALESCE(f.isdeleted, FALSE) AS del,
                       (f.batchid IS NOT NULL AND f.batchid IN (SELECT batchid FROM b)) AS inbatch,
                       (f.allocationreleasedat IS NOT NULL) AS released,
                       bp.originallyplaced, bp.currentlivebirds,
                       COALESCE((SELECT SUM(x.quantity) FROM l x WHERE x.flockid = f.flockid), 0) AS led
                FROM   flock f CROSS JOIN LATERAL fnflock_birdposition(v_farm.farmid, f.flockid) bp
                WHERE  f.farmid = v_farm.farmid
            )
            -- A. Deleted flock still in its batch: the batch purchase counted its
            --    placed birds; the reconciliation counts none of them alive.
            SELECT fl.flockid, fl.batchid, -(fl.originallyplaced + fl.led) AS qty, 'Flock Deleted' AS reason,
                   'Flock "' || fl.name || '" was deleted before its birds were taken out' AS note
            FROM   fl WHERE fl.del AND fl.inbatch AND NOT fl.released AND fl.originallyplaced + fl.led <> 0
            UNION ALL
            -- A deleted flock that gave its birds back to the batch (414): its own
            -- rows should already net to nothing.
            SELECT fl.flockid, fl.batchid, -fl.led, 'Flock Deleted',
                   'Flock "' || fl.name || '" was deleted and its birds given back to the batch; its rows taken out'
            FROM   fl WHERE fl.del AND fl.inbatch AND fl.released AND fl.led <> 0
            UNION ALL
            -- C. Flock alive outside a batch: its rows = its birds alive.
            SELECT fl.flockid, fl.batchid, fl.currentlivebirds - fl.led, 'Flock Without Batch',
                   'Flock "' || fl.name || '" has no batch purchase' ||
                   CASE WHEN fl.batchid IS NOT NULL THEN ' (its batch was deleted)' ELSE '' END || '; its birds alive added'
            FROM   fl WHERE NOT fl.del AND NOT fl.inbatch AND fl.currentlivebirds - fl.led <> 0
            UNION ALL
            -- Deleted flock outside a batch: nothing left.
            SELECT fl.flockid, fl.batchid, -fl.led, 'Flock Deleted',
                   'Flock "' || fl.name || '" was deleted; its rows taken out'
            FROM   fl WHERE fl.del AND NOT fl.inbatch AND fl.led <> 0
            UNION ALL
            -- B. Batch deleted: its remaining rows not belonging to a flock above.
            SELECT NULL::int, x.batchid, -SUM(x.quantity), 'Batch Deleted',
                   'Batch #' || x.batchid || ' was deleted; its remaining bird rows taken out'
            FROM   l x
            WHERE  x.batchid IS NOT NULL AND x.batchid NOT IN (SELECT batchid FROM b)
              AND  (x.flockid IS NULL OR x.flockid NOT IN (SELECT flockid FROM fl WHERE NOT fl.inbatch))
            GROUP  BY x.batchid HAVING SUM(x.quantity) <> 0
        LOOP
            INSERT INTO poultrystocktransactions
                (farmid, poultryproductid, txntype, quantity, note, createdby, batchid, flockid, effectivedate, reason, birdscope)
            VALUES
                (v_farm.farmid, v_bird, 'Ledger Correction', r.qty, left('Correction: ' || r.note, 500),
                 'migration 438', r.batchid, r.flockid, CURRENT_DATE, r.reason,
                 CASE WHEN r.flockid IS NULL THEN 'BatchUnallocated' ELSE 'Flock' END);
            v_rows := v_rows + 1;
            v_birds := v_birds + r.qty;
        END LOOP;
    END LOOP;
    RAISE NOTICE '438 correction: % rows, % birds net', v_rows, v_birds;
END $$;

-- ---------------------------------------------------------------------------
-- Self-test. Test farm: Birds rows = birds alive (437) + its historical batch
-- not reconciled yet (1,000) + one old sale with no flock (-3). Other farms
-- are listed, not failed: what is left there is outside this migration.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_f    text := '3c4ac3cd-8792-4739-9b20-5f3b7d655a02';
    v_net  numeric;
    v_live numeric;
    v_bad  integer;
    r      record;
BEGIN
    IF EXISTS (SELECT 1 FROM farms WHERE farmid = v_f) THEN
        SELECT COALESCE(SUM(l.quantity), 0) INTO v_net FROM fnpoultrybirdledger_rows(v_f) l;
        SELECT currentstock INTO v_live FROM sppoultryproduct_reconcilestock(v_f) WHERE name = 'Birds';
        SELECT COUNT(*) INTO v_bad FROM fnpoultrybirdledger_check(v_f) c WHERE c.kind <> 'NoFlockNoBatch' AND c.difference <> 0;
        RAISE NOTICE '438 test farm: Birds rows net %, birds alive %, batches / flocks out %', v_net, v_live, v_bad;
        IF v_bad > 0 THEN
            RAISE EXCEPTION '438 self-test: test farm still has % batches / flocks out', v_bad;
        END IF;
    END IF;

    FOR r IN SELECT left(f.farmid, 8) AS farm, c.kind, c.label, c.difference
             FROM (SELECT DISTINCT t.farmid FROM poultrystocktransactions t) f
             CROSS JOIN LATERAL fnpoultrybirdledger_check(f.farmid) c
             WHERE c.difference <> 0 ORDER BY 1, 2, 3 LOOP
        RAISE NOTICE '  still out: % % % (%)', r.farm, r.kind, r.label, r.difference;
    END LOOP;
END $$;

COMMIT;
