-- 417: undo for setups completed BEFORE 416, with a review step.
--
-- Those setups never recorded what they created. What can be found reliably:
--   * flocks       -- their opening position says source = 'Initial Farm Setup'
--   * reconciliations posted by the setup -- source = 'Initial Farm Setup'
-- What can only be guessed from those flocks:
--   * the batches they sit in (a setup could REUSE an existing batch)
--   * the houses they sit in  (a setup could REUSE an existing house)
--
-- So nothing is removed on a guess. fnpoultryfarmsetuplegacy_candidates lists
-- the candidates (flocks and reconciliations suggested, batches and houses
-- not); the farm ticks what to remove; sppoultryfarmsetuplegacy_reverse turns
-- exactly the ticked items into a 416 run and undoes it with
-- sppoultryfarmsetuprun_reverse -- the same checks, the same write paths, all
-- or nothing. A refused undo leaves no run behind (it rolls back).
--
-- Needs 416. Idempotent: CREATE OR REPLACE.

CREATE OR REPLACE FUNCTION public.fnpoultryfarmsetuplegacy_candidates(p_farmid text)
 RETURNS TABLE(type text, id integer, name text, batchid integer, suggested boolean,
               setupdate date, blockers jsonb)
 LANGUAGE sql
 STABLE
AS $function$
    WITH fl AS (   -- flocks an old setup created, not already part of a 416 run
        SELECT f.flockid, f.name, f.batchid, f.houseid, o.effectivebusinessdate AS d
        FROM   poultryopeningflockposition o
        JOIN   flock f ON f.flockid = o.flockid AND f.farmid = o.farmid
        WHERE  o.farmid = p_farmid AND o.source = 'Initial Farm Setup'
          AND  NOT COALESCE(f.isdeleted, FALSE)
          AND  NOT EXISTS (SELECT 1 FROM poultryfarmsetuprunitems i WHERE i.entitytype = 'Flock' AND i.entityid = f.flockid)
    ),
    rc AS (        -- reconciliations an old setup posted on those flocks' batches
        SELECT r.reconciliationid, r.reconciliationno, r.batchid, r.asofdate
        FROM   poultrybatchbirdreconciliations r
        WHERE  r.farmid = p_farmid AND r.source = 'Initial Farm Setup' AND r.status <> 'Reversed'
          AND  r.batchid IN (SELECT fl.batchid FROM fl)
          AND  NOT EXISTS (SELECT 1 FROM poultryfarmsetuprunitems i WHERE i.entitytype = 'Reconciliation' AND i.entityid = r.reconciliationid)
    )
    -- Flocks: suggested. Blocked by whatever the Flocks page refuses a delete over.
    SELECT 'Flock', fl.flockid, fl.name, fl.batchid, TRUE, fl.d,
           COALESCE((SELECT jsonb_agg(b.rows || ' ' || b.label) FROM fnpoultryflock_deleteblockers(p_farmid, fl.flockid) b), '[]'::jsonb)
    FROM   fl

    -- Batches: NOT suggested (could have existed before the setup).
    UNION ALL
    SELECT 'Batch', b.batchid, b.batchname || ' (' || b.batchcode || ')', b.batchid, FALSE,
           (SELECT min(fl.d) FROM fl WHERE fl.batchid = b.batchid),
           COALESCE((
               SELECT jsonb_agg(x) FROM (
                   SELECT 'flock "' || f.name || '" was not created by the setup' AS x
                   FROM   flock f
                   WHERE  f.farmid = p_farmid AND f.batchid = b.batchid AND NOT COALESCE(f.isdeleted, FALSE)
                     AND  f.flockid NOT IN (SELECT fl.flockid FROM fl)
                   UNION ALL
                   SELECT 'reconciliation ' || r.reconciliationno || ' was not posted by the setup'
                   FROM   poultrybatchbirdreconciliations r
                   WHERE  r.farmid = p_farmid AND r.batchid = b.batchid AND r.status <> 'Reversed'
                     AND  r.reconciliationid NOT IN (SELECT rc.reconciliationid FROM rc)
               ) z), '[]'::jsonb)
    FROM   mainflockbatch b
    WHERE  b.farmid = p_farmid AND b.batchid IN (SELECT fl.batchid FROM fl)

    -- Houses: NOT suggested (could have existed before the setup).
    UNION ALL
    SELECT 'House', h.houseid, h.housename, NULL::int, FALSE,
           (SELECT min(fl.d) FROM fl WHERE fl.houseid = h.houseid),
           COALESCE((
               SELECT jsonb_agg('flock "' || f.name || '" was not created by the setup')
               FROM   flock f
               WHERE  f.farmid = p_farmid AND f.houseid = h.houseid AND NOT COALESCE(f.isdeleted, FALSE)
                 AND  f.flockid NOT IN (SELECT fl.flockid FROM fl)), '[]'::jsonb)
    FROM   houses h
    WHERE  h.farmid = p_farmid AND h.houseid IN (SELECT fl.houseid FROM fl)

    -- Reconciliations: suggested; they go with their batch.
    UNION ALL
    SELECT 'Reconciliation', rc.reconciliationid, rc.reconciliationno, rc.batchid, TRUE, rc.asofdate, '[]'::jsonb
    FROM   rc;
$function$;


-- Undo exactly the ticked items of an old setup. p_items: [{"type":"Flock","id":12}, ...]
CREATE OR REPLACE FUNCTION public.sppoultryfarmsetuplegacy_reverse(
    p_farmid text, p_items jsonb, p_reason text, p_by text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_run  integer;
    v_bad  text;
    e      record;
BEGIN
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'Tick at least one item to undo.' USING ERRCODE = 'P0001';
    END IF;

    -- Only items the review step offered may be removed this way.
    SELECT string_agg(x.type || ' #' || x.id, ', ') INTO v_bad
    FROM   jsonb_to_recordset(p_items) AS x(type text, id integer)
    WHERE  NOT EXISTS (SELECT 1 FROM fnpoultryfarmsetuplegacy_candidates(p_farmid) c
                       WHERE c.type = x.type AND c.id = x.id);
    IF v_bad IS NOT NULL THEN
        RAISE EXCEPTION 'These were not created by an earlier setup on this farm: %.', v_bad USING ERRCODE = 'P0001';
    END IF;

    v_run := sppoultryfarmsetuprun_start(p_farmid, NULL, p_by, 'Initial Farm Setup (before tracking)');
    FOR e IN SELECT DISTINCT x.type, x.id FROM jsonb_to_recordset(p_items) AS x(type text, id integer) LOOP
        PERFORM sppoultryfarmsetuprun_additem(v_run, e.type, e.id);
    END LOOP;

    -- Same checks and write paths as a tracked setup. A refusal raises, and the
    -- run created just above rolls back with it.
    RETURN sppoultryfarmsetuprun_reverse(p_farmid, v_run, p_reason, p_by);
END
$function$;
