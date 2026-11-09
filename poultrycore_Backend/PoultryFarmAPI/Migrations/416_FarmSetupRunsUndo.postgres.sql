-- 416: Initial Farm Setup can be undone, and what it created can be listed.
--
-- Until now a completed setup left only a per-company snapshot of counts
-- (poultryfarmsetup); nothing remembered WHICH batches, houses, flocks and
-- batch reconciliations it created, so it could not be reversed. From this
-- migration on, every completed setup is a RUN with the ids it created.
-- Setups completed before 416 have no run and cannot be undone as a whole
-- (their items can still be edited or deleted one by one).
--
--   poultryfarmsetupruns        one row per completed setup
--   poultryfarmsetuprunitems    what that setup created (Batch/House/Flock/Reconciliation)
--
--   sppoultryfarmsetuprun_start / _additem   called by FarmSetupService.CompleteAsync,
--                                            inside the setup transaction
--   sppoultryfarmsetuprun_list               runs + their items + why each cannot go
--   sppoultryfarmsetuprun_reverse            undo a whole run, in one transaction
--
-- Undo is refused while anything has been recorded against what the run
-- created -- the same blockers the Flocks page uses to refuse a flock delete,
-- plus a later flock placed in one of its batches or houses, and later bird
-- movements or reconciliations on one of its batches. It reuses the existing
-- write paths: sppoultrybatchreconcile_reverse, sppoultryflock_delete (which
-- releases the flock's ledger rows) and spmainflockbatch_delete (which zeroes
-- the purchase's bird stock and expense).
--
-- Idempotent: IF NOT EXISTS / CREATE OR REPLACE.

CREATE TABLE IF NOT EXISTS public.poultryfarmsetupruns (
    setuprunid      serial PRIMARY KEY,
    farmid          text        NOT NULL,
    businessdate    date,
    completedat     timestamp   NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    completedby     text,
    source          text,
    status          text        NOT NULL DEFAULT 'Completed'
                    CHECK (status IN ('Completed', 'Reversed')),
    reversedat      timestamp,
    reversedby      text,
    reversalreason  text
);
CREATE INDEX IF NOT EXISTS ix_poultryfarmsetupruns_farm ON public.poultryfarmsetupruns (lower(farmid), setuprunid DESC);

CREATE TABLE IF NOT EXISTS public.poultryfarmsetuprunitems (
    setuprunid  integer NOT NULL REFERENCES public.poultryfarmsetupruns (setuprunid) ON DELETE CASCADE,
    entitytype  text    NOT NULL CHECK (entitytype IN ('Batch', 'House', 'Flock', 'Reconciliation')),
    entityid    integer NOT NULL,
    PRIMARY KEY (setuprunid, entitytype, entityid)
);


CREATE OR REPLACE FUNCTION public.sppoultryfarmsetuprun_start(
    p_farmid text, p_businessdate date, p_by text DEFAULT NULL, p_source text DEFAULT NULL)
 RETURNS integer
 LANGUAGE sql
AS $function$
    INSERT INTO public.poultryfarmsetupruns (farmid, businessdate, completedby, source)
    VALUES (p_farmid, p_businessdate, p_by, p_source)
    RETURNING setuprunid;
$function$;


CREATE OR REPLACE FUNCTION public.sppoultryfarmsetuprun_additem(
    p_setuprunid integer, p_entitytype text, p_entityid integer)
 RETURNS void
 LANGUAGE sql
AS $function$
    INSERT INTO public.poultryfarmsetuprunitems (setuprunid, entitytype, entityid)
    VALUES (p_setuprunid, p_entitytype, p_entityid)
    ON CONFLICT DO NOTHING;
$function$;


-- Why one item of a run cannot be deleted / the run cannot be undone.
-- One row per reason; nothing returned means it can go.
CREATE OR REPLACE FUNCTION public.fnpoultryfarmsetuprun_itemblockers(
    p_farmid text, p_setuprunid integer, p_entitytype text, p_entityid integer)
 RETURNS TABLE(reason text)
 LANGUAGE sql
 STABLE
AS $function$
    -- Flock: whatever the Flocks page would refuse a delete over.
    SELECT b.rows || ' ' || b.label
    FROM   fnpoultryflock_deleteblockers(p_farmid, p_entityid) b
    WHERE  p_entitytype = 'Flock'
      AND  EXISTS (SELECT 1 FROM flock f WHERE f.flockid = p_entityid AND f.farmid = p_farmid AND NOT COALESCE(f.isdeleted, FALSE))

    -- Batch: a flock placed in it that this run did not create.
    UNION ALL
    SELECT 'flock "' || f.name || '" placed in it later'
    FROM   flock f
    WHERE  p_entitytype = 'Batch' AND f.farmid = p_farmid AND f.batchid = p_entityid
      AND  NOT COALESCE(f.isdeleted, FALSE)
      AND  NOT EXISTS (SELECT 1 FROM poultryfarmsetuprunitems i
                       WHERE i.setuprunid = p_setuprunid AND i.entitytype = 'Flock' AND i.entityid = f.flockid)

    -- Batch: a bird reconciliation this run did not post.
    UNION ALL
    SELECT 'reconciliation ' || r.reconciliationno || ' posted later'
    FROM   poultrybatchbirdreconciliations r
    WHERE  p_entitytype = 'Batch' AND r.farmid = p_farmid AND r.batchid = p_entityid
      AND  r.status <> 'Reversed'
      AND  NOT EXISTS (SELECT 1 FROM poultryfarmsetuprunitems i
                       WHERE i.setuprunid = p_setuprunid AND i.entitytype = 'Reconciliation' AND i.entityid = r.reconciliationid)

    -- Batch: unplaced-bird movements that are not this run's reconciliations.
    UNION ALL
    SELECT count(*) || ' bird movement(s) on its unplaced birds'
    FROM   poultrybirdadjustments a
    WHERE  p_entitytype = 'Batch' AND a.farmid = p_farmid AND a.batchid = p_entityid
      AND  a.scope = 'BatchUnallocated' AND a.reversedbyid IS NULL AND a.reversesid IS NULL
      AND  NOT (a.sourcetype = 'BatchReconciliation'
                AND a.sourceid IN (SELECT i.entityid FROM poultryfarmsetuprunitems i
                                   WHERE i.setuprunid = p_setuprunid AND i.entitytype = 'Reconciliation'))
    HAVING count(*) > 0

    -- House: a flock in it that this run did not create.
    UNION ALL
    SELECT 'flock "' || f.name || '" placed in it later'
    FROM   flock f
    WHERE  p_entitytype = 'House' AND f.farmid = p_farmid AND f.houseid = p_entityid
      AND  NOT COALESCE(f.isdeleted, FALSE)
      AND  NOT EXISTS (SELECT 1 FROM poultryfarmsetuprunitems i
                       WHERE i.setuprunid = p_setuprunid AND i.entitytype = 'Flock' AND i.entityid = f.flockid);
$function$;


-- Every run of a company, newest first, with what it created and why it
-- cannot be undone (empty when it can). Items carry their current name and
-- whether they are already gone (deleted on their own page).
CREATE OR REPLACE FUNCTION public.sppoultryfarmsetuprun_list(p_farmid text)
 RETURNS TABLE(setuprunid integer, businessdate date, completedat timestamp, completedby text, source text,
               status text, reversedat timestamp, reversedby text, reversalreason text,
               items jsonb, blockers jsonb)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT r.setuprunid, r.businessdate, r.completedat, r.completedby, r.source,
           r.status, r.reversedat, r.reversedby, r.reversalreason,
           COALESCE((
               SELECT jsonb_agg(jsonb_build_object(
                          'type', i.entitytype, 'id', i.entityid,
                          'name', n.name, 'gone', n.gone,
                          'blockers', CASE WHEN r.status = 'Completed' AND NOT n.gone THEN COALESCE((
                              SELECT jsonb_agg(b.reason)
                              FROM   fnpoultryfarmsetuprun_itemblockers(p_farmid, r.setuprunid, i.entitytype, i.entityid) b), '[]'::jsonb)
                              ELSE '[]'::jsonb END)
                      ORDER BY array_position(ARRAY['Batch','House','Flock','Reconciliation'], i.entitytype), n.name)
               FROM   poultryfarmsetuprunitems i
               CROSS  JOIN LATERAL (
                   SELECT CASE i.entitytype
                              WHEN 'Batch' THEN (SELECT b.batchname || ' (' || b.batchcode || ')' FROM mainflockbatch b
                                                 WHERE b.batchid = i.entityid AND b.farmid = p_farmid)
                              WHEN 'House' THEN (SELECT h.housename FROM houses h WHERE h.houseid = i.entityid AND h.farmid = p_farmid)
                              WHEN 'Flock' THEN (SELECT f.name FROM flock f WHERE f.flockid = i.entityid AND f.farmid = p_farmid)
                              ELSE (SELECT x.reconciliationno FROM poultrybatchbirdreconciliations x
                                    WHERE x.reconciliationid = i.entityid AND x.farmid = p_farmid)
                          END AS name,
                          CASE i.entitytype
                              WHEN 'Batch' THEN NOT EXISTS (SELECT 1 FROM mainflockbatch b WHERE b.batchid = i.entityid AND b.farmid = p_farmid)
                              WHEN 'House' THEN NOT EXISTS (SELECT 1 FROM houses h WHERE h.houseid = i.entityid AND h.farmid = p_farmid)
                              WHEN 'Flock' THEN NOT EXISTS (SELECT 1 FROM flock f WHERE f.flockid = i.entityid AND f.farmid = p_farmid
                                                            AND NOT COALESCE(f.isdeleted, FALSE))
                              ELSE NOT EXISTS (SELECT 1 FROM poultrybatchbirdreconciliations x WHERE x.reconciliationid = i.entityid
                                               AND x.farmid = p_farmid AND x.status <> 'Reversed')
                          END AS gone
               ) n
               WHERE  i.setuprunid = r.setuprunid), '[]'::jsonb) AS items,
           CASE WHEN r.status <> 'Completed' THEN '[]'::jsonb ELSE COALESCE((
               SELECT jsonb_agg(DISTINCT i.entitytype || ' #' || i.entityid || ': ' || b.reason)
               FROM   poultryfarmsetuprunitems i
               CROSS  JOIN LATERAL fnpoultryfarmsetuprun_itemblockers(p_farmid, r.setuprunid, i.entitytype, i.entityid) b
               WHERE  i.setuprunid = r.setuprunid), '[]'::jsonb) END AS blockers
    FROM   poultryfarmsetupruns r
    WHERE  lower(r.farmid) = lower(p_farmid)
    ORDER  BY r.setuprunid DESC;
$function$;


-- Undo a whole setup. All or nothing; refused while anything it created has
-- been used since. Items already deleted on their own page are skipped.
CREATE OR REPLACE FUNCTION public.sppoultryfarmsetuprun_reverse(
    p_farmid text, p_setuprunid integer, p_reason text, p_by text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_run      record;
    v_list     text;
    v_label    text;
    i          record;
    v_recons   integer := 0;
    v_flocks   integer := 0;
    v_batches  integer := 0;
    v_houses   integer := 0;
BEGIN
    IF NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Say why this setup is being undone.' USING ERRCODE = 'P0001';
    END IF;

    -- Same lock the wizard takes, so a setup cannot be undone while another
    -- one is being completed.
    PERFORM pg_advisory_xact_lock(hashtext('farm-setup:' || p_farmid));

    SELECT r.* INTO v_run FROM poultryfarmsetupruns r
    WHERE  r.setuprunid = p_setuprunid AND lower(r.farmid) = lower(p_farmid)
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That setup does not exist on this farm.' USING ERRCODE = 'P0001';
    END IF;
    IF v_run.status = 'Reversed' THEN
        RAISE EXCEPTION 'This setup was already undone.' USING ERRCODE = 'P0001';
    END IF;

    SELECT string_agg(DISTINCT
               CASE it.entitytype
                   WHEN 'Batch' THEN 'batch ' || COALESCE((SELECT b.batchcode FROM mainflockbatch b WHERE b.batchid = it.entityid), '#' || it.entityid)
                   WHEN 'House' THEN 'house ' || COALESCE((SELECT h.housename FROM houses h WHERE h.houseid = it.entityid), '#' || it.entityid)
                   WHEN 'Flock' THEN 'flock ' || COALESCE((SELECT f.name FROM flock f WHERE f.flockid = it.entityid), '#' || it.entityid)
                   ELSE 'reconciliation #' || it.entityid
               END || ' has ' || b.reason, '; ')
    INTO   v_list
    FROM   poultryfarmsetuprunitems it
    CROSS  JOIN LATERAL fnpoultryfarmsetuprun_itemblockers(p_farmid, p_setuprunid, it.entitytype, it.entityid) b
    WHERE  it.setuprunid = p_setuprunid;
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'This setup cannot be undone because things have been recorded since: %. Reverse or delete those first.', v_list
            USING ERRCODE = 'P0001', HINT = 'SETUP_HAS_ACTIVITY';
    END IF;

    v_label := 'Initial Farm Setup undone: ' || btrim(p_reason);

    -- 1. Batch reconciliations (they took birds out of the unplaced pool).
    FOR i IN
        SELECT it.entityid FROM poultryfarmsetuprunitems it
        JOIN   poultrybatchbirdreconciliations x ON x.reconciliationid = it.entityid AND x.farmid = p_farmid
        WHERE  it.setuprunid = p_setuprunid AND it.entitytype = 'Reconciliation' AND x.status <> 'Reversed'
        ORDER  BY it.entityid DESC
    LOOP
        PERFORM sppoultrybatchreconcile_reverse(p_farmid, i.entityid, v_label, p_by);
        v_recons := v_recons + 1;
    END LOOP;

    -- 2. Flocks: the guarded delete (releases their opening ledger rows).
    FOR i IN
        SELECT it.entityid FROM poultryfarmsetuprunitems it
        JOIN   flock f ON f.flockid = it.entityid AND f.farmid = p_farmid
        WHERE  it.setuprunid = p_setuprunid AND it.entitytype = 'Flock' AND NOT COALESCE(f.isdeleted, FALSE)
        ORDER  BY it.entityid DESC
    LOOP
        PERFORM sppoultryflock_delete(p_farmid, i.entityid, p_by);
        v_flocks := v_flocks + 1;
    END LOOP;

    -- 3. Batches: the Batch page's delete (zeroes the purchase's stock and expense).
    FOR i IN
        SELECT it.entityid FROM poultryfarmsetuprunitems it
        JOIN   mainflockbatch b ON b.batchid = it.entityid AND b.farmid = p_farmid
        WHERE  it.setuprunid = p_setuprunid AND it.entitytype = 'Batch'
    LOOP
        PERFORM spmainflockbatch_delete(i.entityid, p_by, p_farmid);
        v_batches := v_batches + 1;
    END LOOP;

    -- 4. Houses. Checked above: nothing outside this run is in them.
    WITH d AS (
        DELETE FROM houses h
        USING  poultryfarmsetuprunitems it
        WHERE  it.setuprunid = p_setuprunid AND it.entitytype = 'House'
          AND  h.houseid = it.entityid AND h.farmid = p_farmid
        RETURNING 1)
    SELECT count(*) INTO v_houses FROM d;

    UPDATE poultryfarmsetupruns r
    SET    status = 'Reversed', reversedat = (now() AT TIME ZONE 'utc'), reversedby = p_by,
           reversalreason = btrim(p_reason)
    WHERE  r.setuprunid = p_setuprunid;

    -- The company snapshot no longer counts what was undone.
    UPDATE poultryfarmsetup s
    SET    batchcount = GREATEST(0, s.batchcount - v_batches),
           housecount = GREATEST(0, s.housecount - v_houses),
           flockcount = GREATEST(0, s.flockcount - v_flocks)
    WHERE  lower(s.farmid) = lower(p_farmid);

    RETURN jsonb_build_object('setupRunId', p_setuprunid, 'status', 'Reversed',
        'reconciliationsReversed', v_recons, 'flocksDeleted', v_flocks,
        'batchesDeleted', v_batches, 'housesDeleted', v_houses);
END
$function$;
