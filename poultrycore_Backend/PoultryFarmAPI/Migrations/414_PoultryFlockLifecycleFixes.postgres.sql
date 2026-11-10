-- =============================================================================
-- 414_PoultryFlockLifecycleFixes.postgres.sql
--
-- Five issues found while testing 413 (bird reconciliation). Nothing here
-- changes the inventory or financial effect of any posted movement.
--
--   ISSUE 2  Stock movements written by sppoultrybirdstock_postdated (opening
--            reductions, historical batch purchases, closeout culls/transfers,
--            sale reversals) carried createddate = the EFFECTIVE date at 00:00,
--            so the table showed "8 Nov 2026" with no time.  createddate keeps
--            its meaning (as-of readers date rows by it); a separate POSTEDAT
--            column now records when a row was written.  Existing rows stay
--            NULL; the reader recovers the real time from the source record
--            where that is unambiguous and otherwise shows the date alone.
--
--   ISSUE 3  sppoultryflock_editcontext: everything Edit Flock needs to restore
--            the New/Existing mode, the opening position, the bird position
--            and the posted movement history -- read from the ledger, never
--            from browser state.  Saving an edit posts nothing.
--
--   ISSUE 4  "Deleted successfully" with the flock still listed.  The BEFORE
--            DELETE trigger tr_flock_softdelete turns every DELETE into
--            isdeleted = TRUE, but spflock_getall never filtered it.  Now:
--              * spflock_getall hides soft-deleted flocks;
--              * sppoultryflock_delete refuses a flock with posted activity,
--                naming it, and otherwise reverses the flock's own creation
--                ledger rows and RELEASES its birds back to the batch pool;
--              * flocks soft-deleted before 414 still count against their
--                batch (unchanged) until sppoultryflock_releasedeleted is run
--                for them -- explicitly, per flock, dry run first.
--
--   ISSUE 5  (no SQL needed) Initial Farm Setup now reads
--            sppoultrybatchreconcile_summary for each batch's already-posted
--            batch-level dispositions.  The summary below changes only by
--            excluding RELEASED deleted flocks from "originally allocated".
--
-- Idempotent.  Run after 413.
-- =============================================================================
BEGIN;

-- Snapshot of every batch's never-placed pool, compared at the end: this
-- migration must not move a single bird.
CREATE TEMP TABLE _414_pool ON COMMIT DROP AS
SELECT b.farmid, b.batchid, fnpoultrybatch_unallocated(b.farmid, b.batchid) AS pool,
       spflock_getconsumedforbatch(b.batchid, b.farmid, NULL) AS consumed
FROM   mainflockbatch b;

-- ============================================== 1. posting timestamp =========
ALTER TABLE public.poultrystocktransactions ADD COLUMN IF NOT EXISTS postedat timestamp without time zone;
-- Added WITHOUT a default first, so existing rows stay NULL (their posting time
-- is unknown, not "now"); new rows get the clock from here on.
ALTER TABLE public.poultrystocktransactions ALTER COLUMN postedat SET DEFAULT (now() AT TIME ZONE 'utc');

-- ============================================== 2. flock release columns =====
ALTER TABLE public.flock ADD COLUMN IF NOT EXISTS allocationreleasedat timestamp without time zone;
ALTER TABLE public.flock ADD COLUMN IF NOT EXISTS allocationreleasedby text;

-- ============================================== 3. consumed (placed basis) ===
-- 413's body; a deleted flock whose allocation was RELEASED no longer counts
-- against its batch.  Every flock that exists today has allocationreleasedat
-- NULL, so every batch's figure is unchanged by this migration.
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
    SELECT COALESCE(SUM(f.quantity), 0)
         + COALESCE(SUM(GREATEST(o.originallyplaced - o.openinglivebirds, 0)), 0)
    INTO   v_total
    FROM   flock f
    LEFT   JOIN public.poultryopeningflockposition o
           ON o.flockid = f.flockid AND o.farmid = f.farmid
    WHERE  f.batchid = p_batchid
      AND  f.farmid = p_farmid
      AND  f.allocationreleasedat IS NULL
      AND  (p_flockidtoexclude IS NULL OR f.flockid <> p_flockidtoexclude);

    v_total := COALESCE(v_total, 0) - COALESCE((
        SELECT SUM(a.quantity) FROM public.poultrybirdadjustments a
        JOIN   flock f ON f.flockid = a.flockid AND f.farmid = a.farmid
        WHERE  a.farmid = p_farmid AND f.batchid = p_batchid AND a.appliedto = 'FlockQuantity'
          AND  f.allocationreleasedat IS NULL
          AND  (p_flockidtoexclude IS NULL OR a.flockid <> p_flockidtoexclude)), 0);

    v_total := v_total - COALESCE((
        SELECT SUM(a.quantity) FROM public.poultrybirdadjustments a
        WHERE  a.farmid = p_farmid AND a.batchid = p_batchid AND a.scope = 'BatchUnallocated'), 0);

    RETURN COALESCE(v_total, 0);
END
$function$;

-- ============================================== 4. flock lists ===============
-- Same signature and columns as before; soft-deleted flocks are no longer
-- listed.  spflock_getbyid still returns them, so history screens can name a
-- deleted flock.
CREATE OR REPLACE FUNCTION public.spflock_getall(p_farmid text, p_userid text DEFAULT NULL::text)
 RETURNS TABLE(flockid integer, userid text, farmid text, name text, breed text, startdate date, quantity integer, active boolean, houseid integer, batchid integer, inactivationreason text, otherreason text, notes text, hasarrived boolean, batchname text, createdat timestamp without time zone, closeddate date, closedat timestamp without time zone, closedby text, closereason text, closeoutid integer, flocktype text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        f.flockid,
        f.userid::text,
        f.farmid::text,
        f.name::text,
        f.breed::text,
        f.startdate,
        f.quantity,
        COALESCE(f.active, TRUE) AS active,
        f.houseid,
        f.batchid,
        f.inactivationreason::text,
        f.otherreason::text,
        f.notes::text,
        COALESCE(f.hasarrived, FALSE) AS hasarrived,
        b.batchname::text,
        f.createdat,
        f.closeddate,
        f.closedat,
        f.closedby,
        f.closereason,
        f.closeoutid,
        f.flocktype
    FROM flock f
    LEFT JOIN mainflockbatch b
        ON f.batchid = b.batchid AND f.farmid = b.farmid
    WHERE f.farmid = p_farmid
      AND NOT COALESCE(f.isdeleted, FALSE)          -- 414
    ORDER BY f.startdate DESC;
END
$function$;

-- ============================================== 5. delete blockers ===========
-- Everything posted against a flock AFTER it was created.  The flock's own
-- creation records -- its opening position and the opening ledger rows that
-- position wrote -- are not activity: deleting the flock reverses them.
-- Derived/scheduled rows (alerts, lifecycle schedule, house assignment) are
-- not activity either.
CREATE OR REPLACE FUNCTION public.fnpoultryflock_deleteblockers(p_farmid text, p_flockid integer)
RETURNS TABLE(source text, label text, rows integer)
LANGUAGE sql STABLE AS $f$
    WITH c(source, label, rows) AS (
        SELECT 'productionrecords', 'production record(s)', (SELECT count(*) FROM productionrecords x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'productionrecord', 'legacy production record(s)', (SELECT count(*) FROM productionrecord x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'eggproduction', 'egg production record(s)', (SELECT count(*) FROM eggproduction x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'feedusage', 'feed usage record(s)', (SELECT count(*) FROM feedusage x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'poultryfeedusagelines', 'feed usage line(s)', (SELECT count(*) FROM poultryfeedusagelines x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'poultryfeeddistributionlines', 'feed distribution line(s)', (SELECT count(*) FROM poultryfeeddistributionlines x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'mortality', 'mortality record(s)', (SELECT count(*) FROM mortality x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'healthrecord', 'health record(s)', (SELECT count(*) FROM healthrecord x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'healthrecords', 'health record(s)', (SELECT count(*) FROM healthrecords x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'sale', 'sale(s)', (SELECT count(*) FROM sale x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'flockcloseouts', 'flock close-out(s)', (SELECT count(*) FROM flockcloseouts x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'poultrybirdadjustments', 'bird movement(s)', (SELECT count(*) FROM poultrybirdadjustments x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'poultryhistoricalbirdsales', 'historical sale(s)', (SELECT count(*) FROM poultryhistoricalbirdsales x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'poultrymanualstockmovements', 'manual stock movement(s)', (SELECT count(*) FROM poultrymanualstockmovements x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'poultrystocktransactions', 'other stock ledger movement(s)', (
            SELECT count(*) FROM poultrystocktransactions t
            WHERE  t.flockid = p_flockid
              AND  NOT (t.txntype = 'Opening Adjustment'
                        AND t.relatedid IN (SELECT o.openingpositionid FROM poultryopeningflockposition o
                                            WHERE o.flockid = p_flockid AND o.farmid = p_farmid)))::int
        UNION ALL SELECT 'poultrytreatmentcampaignflocks', 'treatment campaign(s)', (SELECT count(*) FROM poultrytreatmentcampaignflocks x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'poultrytreatmentcampaignpostlines', 'treatment posting(s)', (SELECT count(*) FROM poultrytreatmentcampaignpostlines x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'poultryflockweighins', 'weigh-in(s)', (SELECT count(*) FROM poultryflockweighins x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'poultryeggsortingsources', 'egg sorting record(s)', (SELECT count(*) FROM poultryeggsortingsources x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'poultryeggsortingsessions', 'egg sorting session(s)', (SELECT count(*) FROM poultryeggsortingsessions x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'productionbatchallocations', 'batch production allocation(s)', (SELECT count(*) FROM productionbatchallocations x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'productionbatchincludedflocks', 'batch production record(s)', (SELECT count(*) FROM productionbatchincludedflocks x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'expense', 'expense(s)', (SELECT count(*) FROM expense x WHERE x.flockid = p_flockid)::int
        UNION ALL SELECT 'poultrylifecycletaskevents', 'vaccination / lifecycle entr(ies)', (SELECT count(*) FROM poultrylifecycletaskevents x WHERE x.flockid = p_flockid)::int
    )
    SELECT c.source, c.label, c.rows FROM c WHERE c.rows > 0;
$f$;

-- Reverses the flock's creation ledger rows and releases its allocation.
-- Shared by the delete and by the explicit release of a pre-414 soft delete.
CREATE OR REPLACE FUNCTION public.fnpoultryflock_release(p_farmid text, p_flockid integer, p_by text, p_label text)
RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_rows integer := 0;
    v_g    record;
BEGIN
    FOR v_g IN
        SELECT t.txntype, t.relatedid, t.poultryproductid, t.batchid,
               SUM(t.quantity) AS net, MIN(t.createddate) AS createddate,
               MIN(COALESCE(t.effectivedate, t.createddate::date)) AS effectivedate
        FROM   poultrystocktransactions t
        WHERE  t.farmid = p_farmid AND t.flockid = p_flockid
        GROUP  BY t.txntype, t.relatedid, t.poultryproductid, t.batchid
        HAVING SUM(t.quantity) <> 0
    LOOP
        -- Dated like the row it cancels, so every as-of figure nets to zero
        -- on the same day; postedat says when the reversal really happened.
        INSERT INTO poultrystocktransactions
            (farmid, poultryproductid, txntype, quantity, relatedid, note, createdby, createddate,
             batchid, flockid, effectivedate, reason, birdscope)
        VALUES
            (p_farmid, v_g.poultryproductid, v_g.txntype, -v_g.net, v_g.relatedid,
             left('Reversal: ' || p_label, 500), p_by, v_g.createddate,
             v_g.batchid, p_flockid, v_g.effectivedate, 'Flock Deleted', 'Flock');
        v_rows := v_rows + 1;
    END LOOP;

    UPDATE flock f
    SET    allocationreleasedat = (now() AT TIME ZONE 'utc'), allocationreleasedby = p_by
    WHERE  f.flockid = p_flockid AND f.farmid = p_farmid;
    RETURN v_rows;
END
$f$;

-- ============================================== 6. delete ====================
CREATE OR REPLACE FUNCTION public.sppoultryflock_delete(p_farmid text, p_flockid integer, p_by text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    v_f        record;
    v_list     text;
    v_placed   integer;
    v_reversed integer;
BEGIN
    SELECT f.flockid, f.name, f.batchid, f.isdeleted, f.closeddate INTO v_f
    FROM   flock f WHERE f.flockid = p_flockid AND f.farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That flock does not exist on this farm.' USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(v_f.isdeleted, FALSE) THEN
        RAISE EXCEPTION 'Flock "%" was already deleted.', v_f.name USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('flock-alloc:' || p_farmid || ':' || COALESCE(v_f.batchid, 0)));

    SELECT string_agg(b.rows || ' ' || b.label, ', ' ORDER BY b.rows DESC) INTO v_list
    FROM   fnpoultryflock_deleteblockers(p_farmid, p_flockid) b;
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'Flock "%" has posted activity (%) and cannot be deleted. Reverse those entries first, or close the flock to keep its history.',
            v_f.name, v_list
            USING ERRCODE = 'P0001', HINT = 'FLOCK_HAS_ACTIVITY';
    END IF;

    SELECT bp.originallyplaced INTO v_placed FROM fnflock_birdposition(p_farmid, p_flockid) bp;
    v_reversed := fnpoultryflock_release(p_farmid, p_flockid, p_by, 'flock "' || v_f.name || '" deleted');

    UPDATE flock f
    SET    isdeleted = TRUE, updatedat = (now() AT TIME ZONE 'utc')
    WHERE  f.flockid = p_flockid AND f.farmid = p_farmid;

    RETURN jsonb_build_object(
        'deleted', TRUE, 'flockId', p_flockid, 'flockName', v_f.name, 'batchId', v_f.batchid,
        'birdsReleased', COALESCE(v_placed, 0), 'ledgerRowsReversed', v_reversed,
        'batchPoolAfter', CASE WHEN v_f.batchid IS NULL THEN NULL ELSE fnpoultrybatch_unallocated(p_farmid, v_f.batchid) END);
END
$f$;

-- Explicit, per flock: release a flock soft-deleted BEFORE 414 (its birds still
-- count against its batch).  Dry run by default; refused if it has activity.
CREATE OR REPLACE FUNCTION public.sppoultryflock_releasedeleted(p_farmid text, p_flockid integer, p_by text DEFAULT NULL, p_dryrun boolean DEFAULT TRUE)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    v_f      record;
    v_list   text;
    v_placed integer;
    v_rows   integer := 0;
    v_before integer;
BEGIN
    SELECT f.flockid, f.name, f.batchid, f.isdeleted, f.allocationreleasedat INTO v_f
    FROM   flock f WHERE f.flockid = p_flockid AND f.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'That flock does not exist on this farm.' USING ERRCODE = 'P0001'; END IF;
    IF NOT COALESCE(v_f.isdeleted, FALSE) THEN
        RAISE EXCEPTION 'Flock "%" is not deleted.', v_f.name USING ERRCODE = 'P0001';
    END IF;
    IF v_f.allocationreleasedat IS NOT NULL THEN
        RETURN jsonb_build_object('flockId', p_flockid, 'alreadyReleased', TRUE);
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('flock-alloc:' || p_farmid || ':' || COALESCE(v_f.batchid, 0)));
    SELECT string_agg(b.rows || ' ' || b.label, ', ') INTO v_list FROM fnpoultryflock_deleteblockers(p_farmid, p_flockid) b;
    IF v_list IS NOT NULL THEN
        RAISE EXCEPTION 'Flock "%" has posted activity (%); its birds stay counted against the batch.', v_f.name, v_list
            USING ERRCODE = 'P0001';
    END IF;
    SELECT bp.originallyplaced INTO v_placed FROM fnflock_birdposition(p_farmid, p_flockid) bp;
    v_before := CASE WHEN v_f.batchid IS NULL THEN NULL ELSE fnpoultrybatch_unallocated(p_farmid, v_f.batchid) END;
    IF NOT p_dryrun THEN
        v_rows := fnpoultryflock_release(p_farmid, p_flockid, p_by, 'deleted flock "' || v_f.name || '" released to its batch');
    END IF;
    RETURN jsonb_build_object('flockId', p_flockid, 'flockName', v_f.name, 'batchId', v_f.batchid, 'dryRun', p_dryrun,
        'birdsReleased', COALESCE(v_placed, 0), 'ledgerRowsReversed', v_rows, 'batchPoolBefore', v_before,
        'batchPoolAfter', CASE WHEN v_f.batchid IS NULL THEN NULL ELSE fnpoultrybatch_unallocated(p_farmid, v_f.batchid) END);
END
$f$;

-- ============================================== 7. edit context ==============
CREATE OR REPLACE FUNCTION public.sppoultryflock_editcontext(p_farmid text, p_flockid integer)
RETURNS jsonb LANGUAGE sql STABLE AS $f$
    WITH f AS (SELECT * FROM flock x WHERE x.flockid = p_flockid AND x.farmid = p_farmid),
    o AS (SELECT * FROM poultryopeningflockposition x WHERE x.flockid = p_flockid AND x.farmid = p_farmid
          ORDER BY x.openingpositionid DESC LIMIT 1),
    bp AS (SELECT * FROM fnflock_birdposition(p_farmid, p_flockid)),
    blk AS (SELECT COALESCE(jsonb_agg(jsonb_build_object('source', b.source, 'label', b.label, 'rows', b.rows)), '[]'::jsonb) AS j,
                   COUNT(*) AS n
            FROM fnpoultryflock_deleteblockers(p_farmid, p_flockid) b),
    adj AS (SELECT COUNT(*) AS n FROM poultrybirdadjustments a WHERE a.flockid = p_flockid AND a.farmid = p_farmid),
    mv AS (
        SELECT COALESCE(jsonb_agg(m ORDER BY m->>'effectiveDate', m->>'postedAt'), '[]'::jsonb) AS j FROM (
            SELECT jsonb_build_object(
                       'kind', 'Ledger', 'id', t.poultrystocktransactionid, 'type', t.txntype,
                       'reason', t.reason, 'quantity', t.quantity, 'note', t.note,
                       'effectiveDate', COALESCE(t.effectivedate, t.createddate::date),
                       'postedAt', COALESCE(t.postedat, o2.createdat,
                                            CASE WHEN t.createddate <> date_trunc('day', t.createddate) THEN t.createddate END),
                       'createdBy', t.createdby) AS m
            FROM   poultrystocktransactions t
            LEFT   JOIN poultryopeningflockposition o2
                   ON t.txntype = 'Opening Adjustment' AND o2.openingpositionid = t.relatedid AND o2.farmid = t.farmid
                   AND t.postedat IS NULL AND t.reason IS DISTINCT FROM 'Flock Deleted'
            WHERE  t.farmid = p_farmid AND t.flockid = p_flockid
            UNION ALL
            SELECT jsonb_build_object(
                       'kind', 'BirdAdjustment', 'id', a.birdadjustmentid, 'type', a.movementtype,
                       'reason', a.reason, 'quantity', a.quantity, 'note', a.note,
                       'effectiveDate', a.adjustmentdate, 'postedAt', a.createdat, 'createdBy', a.createdby,
                       'reversesId', a.reversesid, 'reversedById', a.reversedbyid)
            FROM   poultrybirdadjustments a
            WHERE  a.farmid = p_farmid AND a.flockid = p_flockid AND a.sourcetype IS DISTINCT FROM 'OpeningPosition'
        ) s(m))
    SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM f) THEN NULL ELSE jsonb_build_object(
        'flockId', p_flockid,
        -- Persisted, not remembered: a flock with an opening position was
        -- registered as already operating (Flocks page "Existing", the
        -- existing-flock endpoint, or Initial Farm Setup).
        'mode', CASE WHEN EXISTS (SELECT 1 FROM o) THEN 'Existing' ELSE 'New' END,
        'isDeleted', (SELECT COALESCE(isdeleted, FALSE) FROM f),
        'isClosed', (SELECT closeddate IS NOT NULL FROM f),
        'opening', (SELECT jsonb_build_object(
                        'openingPositionId', o.openingpositionid, 'effectiveDate', o.effectivebusinessdate,
                        'originallyPlaced', o.originallyplaced, 'openingLiveBirds', o.openinglivebirds,
                        'historicalMortality', o.historicalmortality, 'historicalSold', o.historicalsold,
                        'historicalCulled', o.historicalculled, 'historicalTransferred', o.historicaltransferred,
                        'otherAdjustment', o.otheradjustment, 'historyKnown', o.historyknown,
                        'startDateEstimated', o.startdateestimated, 'source', o.source, 'notes', o.notes,
                        'createdAt', o.createdat, 'createdBy', o.createdby) FROM o),
        'position', (SELECT to_jsonb(bp) FROM bp),
        'quantityAdjustments', fnflock_quantityadjustments(p_farmid, p_flockid),
        'movements', (SELECT j FROM mv),
        -- The bird count is posted history once any of these exist; Edit
        -- refuses to overwrite it (use the opening-position correction).
        'quantityLocked', EXISTS (SELECT 1 FROM o) OR (SELECT n FROM adj) > 0
                          OR (SELECT productionrecordcount FROM bp) > 0,
        'batchLocked', EXISTS (SELECT 1 FROM o) OR (SELECT n FROM blk) > 0,
        'canCorrectOpening', EXISTS (SELECT 1 FROM o),
        'deleteBlockers', (SELECT j FROM blk),
        'canDelete', (SELECT n FROM blk) = 0 AND NOT (SELECT COALESCE(isdeleted, FALSE) FROM f)
    ) END;
$f$;

-- ============================================== 8. stock movement reader =====
-- 413's columns plus POSTEDAT: when the row was written.  For a row written
-- before 414 it is recovered only where unambiguous: a row that already holds a
-- real time, or the FIRST row of an opening position / historical batch
-- purchase / closeout disposition (its source record's creation time).  Never
-- midnight-as-a-time.
DROP FUNCTION IF EXISTS public.sppoultrystock_gettransactions(text, integer);
CREATE FUNCTION public.sppoultrystock_gettransactions(p_farmid text, p_poultryproductid integer DEFAULT NULL::integer)
RETURNS TABLE(poultrystocktransactionid integer, farmid text, poultryproductid integer, txntype text, quantity numeric,
              unitcost numeric, relatedid integer, note text, createddate timestamp without time zone, createdby text,
              productname text,
              batchid integer, batchcode text, flockid integer, flockname text, effectivedate date, reason text,
              manualmovementid integer, manualreversal boolean,
              birdscope text,
              postedat timestamp without time zone)
LANGUAGE plpgsql AS $function$
BEGIN
    RETURN QUERY
    WITH t AS (
        SELECT x.*,
               ROW_NUMBER() OVER (PARTITION BY x.farmid, x.txntype, x.relatedid
                                  ORDER BY x.poultrystocktransactionid) AS rn
        FROM   poultrystocktransactions x
        WHERE  x.farmid = p_farmid
          AND  (p_poultryproductid IS NULL OR x.poultryproductid = p_poultryproductid)
    )
    SELECT t.poultrystocktransactionid, t.farmid::text, t.poultryproductid, t.txntype::text,
           t.quantity, t.unitcost, t.relatedid, t.note::text, t.createddate, t.createdby::text,
           p.name::text AS productname,
           t.batchid, b.batchcode::text, t.flockid, f.name::text, t.effectivedate, t.reason,
           t.manualmovementid, t.manualreversal,
           t.birdscope,
           COALESCE(
               t.postedat,
               CASE WHEN t.createddate <> date_trunc('day', t.createddate) THEN t.createddate END,
               CASE WHEN t.rn = 1 AND t.txntype = 'Opening Adjustment' THEN o.createdat END,
               CASE WHEN t.rn = 1 AND t.txntype = 'Bird Batch Purchase' THEN pb.createddate END,
               CASE WHEN t.rn = 1 AND t.txntype IN ('Flock Cull', 'Flock Transfer Out') THEN d.createdat END
           ) AS postedat
    FROM   t
    INNER  JOIN poultryproducts p ON p.poultryproductid = t.poultryproductid
    LEFT   JOIN mainflockbatch b ON b.batchid = t.batchid
    LEFT   JOIN flock f ON f.flockid = t.flockid
    LEFT   JOIN poultryopeningflockposition o
           ON t.txntype = 'Opening Adjustment' AND o.openingpositionid = t.relatedid AND o.farmid = t.farmid
    LEFT   JOIN mainflockbatch pb
           ON t.txntype = 'Bird Batch Purchase' AND pb.batchid = t.relatedid AND pb.farmid = t.farmid
    LEFT   JOIN flockcloseoutdispositions d
           ON t.txntype IN ('Flock Cull', 'Flock Transfer Out') AND d.dispositionid = t.relatedid AND d.farmid = t.farmid
    ORDER  BY t.createddate DESC, t.poultrystocktransactionid DESC;
END;
$function$;


-- ============================================== 9. batch summary =============
-- 413's body; only change: a RELEASED deleted flock no longer counts as
-- "originally allocated" (it gave its birds back to the pool).
CREATE OR REPLACE FUNCTION public.sppoultrybatchreconcile_summary(p_farmid text)
RETURNS TABLE(batchid integer, batchcode text, batchname text, startdate date, ishistorical boolean,
              originalbirds integer, originallyallocated integer, flockcount integer,
              batchsold integer, batchmortality integer, batchculled integer, batchtransferred integer,
              batchotherremovals integer, batchadditions integer,
              unallocatedpool integer, unallocatedlive integer, unexplained integer,
              flocklivebirds integer, totallivebirds integer,
              flockhistoricalreductions integer,
              historicalsalebirds integer, historicalsalevalue numeric, historicalreceived numeric, historicalowed numeric,
              status text, lastreconciledat timestamp, lastreconciliationno text)
LANGUAGE sql STABLE AS $f$
    WITH b AS (
        SELECT b.batchid, b.batchcode::text AS code, b.batchname::text AS name, b.startdate::date AS sd,
               COALESCE(b.ishistorical, FALSE) AS hist, b.numberofbirds AS orig
        FROM   mainflockbatch b WHERE b.farmid = p_farmid
    ),
    fl AS (
        SELECT f.batchid, COUNT(*)::int AS n,
               SUM(bp.originallyplaced)::int AS placed,
               SUM(CASE WHEN f.closeddate IS NULL THEN bp.currentlivebirds ELSE 0 END)::int AS live,
               SUM(bp.openingmortality + bp.openingsold + bp.openingculled + bp.openingtransferred + bp.openingother)::int AS hred
        FROM   flock f CROSS JOIN LATERAL fnflock_birdposition(p_farmid, f.flockid) bp
        WHERE  f.farmid = p_farmid AND NOT f.isdeleted
        GROUP  BY f.batchid
    ),
    -- Soft-deleted flocks still count against their batch in
    -- spflock_getconsumedforbatch (325 kept that on purpose), so they are part
    -- of "originally allocated" here too, or the identity would not hold.
    fld AS (
        SELECT f.batchid, SUM(bp.originallyplaced)::int AS placed
        FROM   flock f CROSS JOIN LATERAL fnflock_birdposition(p_farmid, f.flockid) bp
        WHERE  f.farmid = p_farmid AND f.isdeleted
          AND  f.allocationreleasedat IS NULL      -- 414: a released flock gave its birds back
        GROUP  BY f.batchid
    ),
    adj AS (
        SELECT a.batchid,
               -SUM(a.quantity) FILTER (WHERE a.reason IN ('Historical Sale', 'Historical Sale / Use'))::int AS sold,
               -SUM(a.quantity) FILTER (WHERE a.reason = 'Historical Mortality')::int                      AS mort,
               -SUM(a.quantity) FILTER (WHERE a.reason = 'Cull')::int                                      AS cull,
               -SUM(a.quantity) FILTER (WHERE a.reason = 'Transfer Out')::int                              AS xfer,
               -SUM(a.quantity) FILTER (WHERE (a.reason IS NULL OR a.reason NOT IN
                    ('Historical Sale', 'Historical Sale / Use', 'Historical Mortality', 'Cull', 'Transfer Out'))
                    AND a.quantity < 0)::int                                                               AS othr,
               SUM(a.quantity) FILTER (WHERE (a.reason IS NULL OR a.reason NOT IN
                    ('Historical Sale', 'Historical Sale / Use', 'Historical Mortality', 'Cull', 'Transfer Out'))
                    AND a.quantity > 0)::int                                                               AS addn
        FROM   poultrybirdadjustments a
        WHERE  a.farmid = p_farmid AND a.scope = 'BatchUnallocated'
          -- a reversed movement and its reversal cancel out: neither is reported
          AND  a.reversedbyid IS NULL AND a.reversesid IS NULL
        GROUP  BY a.batchid
    ),
    hs AS (
        SELECT h.batchid, SUM(h.birds)::int AS birds, SUM(COALESCE(h.totalvalue, 0)) AS val,
               SUM(h.amountreceived) AS recv, SUM(h.amountowed) AS owed
        FROM   poultryhistoricalbirdsales h WHERE h.farmid = p_farmid AND h.status = 'Posted'
        GROUP  BY h.batchid
    ),
    lr AS (
        SELECT DISTINCT ON (r.batchid) r.batchid, r.unexplainedbirds, r.createdat, r.reconciliationno
        FROM   poultrybatchbirdreconciliations r
        WHERE  r.farmid = p_farmid AND r.status <> 'Reversed'
        ORDER  BY r.batchid, r.reconciliationid DESC
    ),
    calc AS (
        SELECT b.*, COALESCE(fl.n, 0) AS n, COALESCE(fl.placed, 0) + COALESCE(fld.placed, 0) AS placed,
               COALESCE(fl.live, 0) AS live, COALESCE(fl.hred, 0) AS hred,
               COALESCE(adj.sold, 0) AS sold, COALESCE(adj.mort, 0) AS mort, COALESCE(adj.cull, 0) AS cull,
               COALESCE(adj.xfer, 0) AS xfer, COALESCE(adj.othr, 0) AS othr, COALESCE(adj.addn, 0) AS addn,
               fnpoultrybatch_unallocated(p_farmid, b.batchid) AS pool,
               lr.unexplainedbirds AS lrx, lr.createdat AS lrat, lr.reconciliationno AS lrno,
               hs.birds AS hsb, hs.val AS hsv, hs.recv AS hsr, hs.owed AS hso
        FROM   b
        LEFT   JOIN fl  ON fl.batchid  = b.batchid
        LEFT   JOIN fld ON fld.batchid = b.batchid
        LEFT   JOIN adj ON adj.batchid = b.batchid
        LEFT   JOIN hs  ON hs.batchid  = b.batchid
        LEFT   JOIN lr  ON lr.batchid  = b.batchid
    ),
    x AS (
        SELECT c.*,
               -- Unexplained: a historical batch never reconciled holds nothing
               -- confirmed; otherwise what the last posting left unexplained,
               -- never more than the pool still holds.  A new purchase's unplaced
               -- birds are simply birds waiting to be placed.
               CASE WHEN c.lrx IS NOT NULL THEN LEAST(c.lrx, c.pool)
                    WHEN c.hist THEN c.pool
                    ELSE 0 END
               -- over-allocation shows up as a negative difference
               + LEAST(c.orig + c.addn - c.placed - c.sold - c.mort - c.cull - c.xfer - c.othr, 0) AS unx
        FROM   calc c
    )
    SELECT x.batchid, x.code, x.name, x.sd, x.hist, x.orig, x.placed, x.n,
           x.sold, x.mort, x.cull, x.xfer, x.othr, x.addn,
           x.pool, x.pool - GREATEST(x.unx, 0), x.unx,
           x.live, x.live + x.pool - GREATEST(x.unx, 0), x.hred,
           COALESCE(x.hsb, 0), COALESCE(x.hsv, 0)::numeric(14,2), COALESCE(x.hsr, 0)::numeric(14,2), COALESCE(x.hso, 0)::numeric(14,2),
           CASE WHEN x.unx < 0 THEN 'OverAllocated'
                WHEN x.unx > 0 THEN 'NeedsReconciliation'
                ELSE 'FullyAccountedFor' END,
           x.lrat, x.lrno
    FROM   x
    ORDER  BY x.sd DESC, x.batchid DESC;
$f$;

-- ============================================== 10. grants ===================
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT EXECUTE ON FUNCTION public.spflock_getconsumedforbatch(integer, text, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spflock_getall(text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.fnpoultryflock_deleteblockers(text, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.fnpoultryflock_release(text, integer, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryflock_delete(text, integer, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryflock_releasedeleted(text, integer, text, boolean) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryflock_editcontext(text, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultrystock_gettransactions(text, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultrybatchreconcile_summary(text) TO poultryapp;
    END IF;
END
$grants$;

-- ============================================== 11. verification =============
DO $$
DECLARE
    v_moved   text;
    v_missing text;
BEGIN
    SELECT string_agg(s.farmid || '/' || s.batchid || ' ' || s.pool || '->' || fnpoultrybatch_unallocated(s.farmid, s.batchid), '; ')
    INTO   v_moved
    FROM   _414_pool s
    WHERE  fnpoultrybatch_unallocated(s.farmid, s.batchid) IS DISTINCT FROM s.pool
       OR  spflock_getconsumedforbatch(s.batchid, s.farmid, NULL) IS DISTINCT FROM s.consumed;
    IF v_moved IS NOT NULL THEN
        RAISE EXCEPTION '414: batch pools moved: %', v_moved;
    END IF;

    SELECT string_agg(want, ', ') INTO v_missing
    FROM   (VALUES ('sppoultryflock_delete'), ('sppoultryflock_releasedeleted'), ('sppoultryflock_editcontext'),
                   ('fnpoultryflock_deleteblockers'), ('fnpoultryflock_release')) AS w(want)
    WHERE  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                       WHERE n.nspname = 'public' AND p.proname = w.want);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '414: missing function(s): %', v_missing;
    END IF;

    -- Existing rows must keep postedat NULL (unknown), never "now".
    IF EXISTS (SELECT 1 FROM _414_pool) AND EXISTS (
        SELECT 1 FROM poultrystocktransactions t
        WHERE  t.postedat IS NOT NULL AND t.reason IS DISTINCT FROM 'Flock Deleted'
          AND  t.createddate < (now() AT TIME ZONE 'utc') - interval '1 minute') THEN
        RAISE EXCEPTION '414: existing stock rows were given a posting time.';
    END IF;

    RAISE NOTICE '414_PoultryFlockLifecycleFixes: verified (no batch pool moved).';
END $$;

COMMIT;
