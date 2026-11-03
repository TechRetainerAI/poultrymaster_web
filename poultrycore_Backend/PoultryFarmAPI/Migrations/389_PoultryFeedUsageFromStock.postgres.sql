-- =============================================================================
-- 389_PoultryFeedUsageFromStock.postgres.sql
--
-- Purpose
-- -------
-- Feed Usage draws feed from inventory. Before this, /feed-usage saved a label
-- ("Layer Feed") and a kg figure into feedusage and never touched stock; it
-- then pushed the kg into the flock's production record, whose own mirror row
-- counted the same feed a second time.
--
-- Now a Feed Usage entry is a document (header + lines, append-only, like
-- Distribute Feed 335) whose lines are FEED LINES on each flock's production
-- record for the day. That is the one place feed leaves stock
-- (spproductionrecord_update -> sppoultryproductionrawmaterialsync ->
-- FIFO / LIFO / HIFO lots, consumption expense 266/272), so stock, cost, the
-- production record and the feedusage mirror move together, once.
--
-- NO PRODUCTION RECORD YET (decided 2026-10-31)
-- ==============================================
-- Feed may be recorded before production. The entry then creates the day's
-- production record holding only the feed, marked sourcetype = 'FeedUsage'
-- ("feed only -- production not filled yet"). Such a record:
--   * is NOT production: Farm Completeness, Daily Closing, the missing-records
--     report and batch posting treat the flock-day as still missing, and the
--     egg-rate readers (hen-day, daily eggs, flock anomalies) skip it;
--   * IS feed: stock, feed cost, feed kg and the feedusage mirror count it;
--   * is completed, not duplicated, when production arrives:
--       - spproductionrecord_insert for that flock-day (the production form,
--         and batch posting) takes the record over -- its feed lines are kept,
--         the new lines are added, every other field comes from the insert,
--         and it becomes an ordinary record;
--       - saving the record from the production form marks it recorded
--         (sppoultryproductionrecord_markrecorded, called by the API).
--
-- BATCH ENTRY
-- ===========
-- A whole batch can be fed at once, but the entry is stored per flock: the
-- client splits the total (by birds, equally, or by hand) and posts one line
-- per flock and feed. The post refuses a batch entry whose lines do not cover
-- only that batch's flocks.
--
-- REVERSAL
-- ========
-- Reason required; the entry stays, marked Reversed. Each line is taken back
-- off its record through the same engine (stock returns). A feed-only record
-- left with no feed is deleted, since it then holds nothing.
--
-- Depends on 332 (eligibility), 335 (fnpoultryfeeddist_changerecordfeed,
-- sppoultryfeeddistribution_availability). Idempotent.
-- EFFECT ON TODAY'S NUMBERS: none until an entry is posted. The feedusage
-- mirror's label changes from "General Feed" to the feed names on records
-- saved from now on.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Documents (append-only).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultryfeedusageentries (
    poultryfeedusageentryid serial      PRIMARY KEY,
    farmid                  text        NOT NULL,
    businessdate            date        NOT NULL,
    scope                   text        NOT NULL DEFAULT 'Flock'
        CONSTRAINT ck_poultryfeedusage_scope CHECK (scope IN ('Flock', 'Batch')),
    batchid                 integer,
    batchname               text,
    splitbasis              text
        CONSTRAINT ck_poultryfeedusage_split CHECK (splitbasis IS NULL OR splitbasis IN ('Birds', 'Equal', 'Manual')),
    totalkg                 numeric(14,3) NOT NULL,
    totalcost               numeric(14,2),
    flockcount              integer     NOT NULL,
    feedonlyrecords         integer     NOT NULL DEFAULT 0,
    status                  text        NOT NULL DEFAULT 'Posted'
        CONSTRAINT ck_poultryfeedusage_status CHECK (status IN ('Posted', 'Reversed')),
    notes                   text,
    postedby                text,
    postedatutc             timestamptz NOT NULL DEFAULT now(),
    reversedby              text,
    reversedatutc           timestamptz,
    reversalreason          text
);
CREATE INDEX IF NOT EXISTS ix_poultryfeedusage_farm_date ON public.poultryfeedusageentries (farmid, businessdate DESC);

CREATE TABLE IF NOT EXISTS public.poultryfeedusagelines (
    poultryfeedusagelineid   serial   PRIMARY KEY,
    poultryfeedusageentryid  integer  NOT NULL REFERENCES public.poultryfeedusageentries (poultryfeedusageentryid),
    farmid                   text     NOT NULL,
    flockid                  integer  NOT NULL,
    flockname                text,
    productionrecordid       integer  NOT NULL,
    -- TRUE when this entry created the record as feed-only.
    createdrecord            boolean  NOT NULL DEFAULT FALSE,
    poultryrawmaterialitemid integer  NOT NULL,
    itemname                 text,
    quantitykg               numeric(14,3) NOT NULL CHECK (quantitykg > 0),
    unitcost                 numeric(14,4),
    totalcost                numeric(14,2),
    birds                    integer,
    -- The record's feed kg and whether it had stock lines BEFORE this line, so a
    -- reversal can put back a manual-only figure the line replaced.
    feedkgbefore             numeric(14,3),
    hadstocklinesbefore      boolean  NOT NULL DEFAULT FALSE,
    reversalnote             text
);
CREATE INDEX IF NOT EXISTS ix_poultryfeedusageline_entry ON public.poultryfeedusagelines (poultryfeedusageentryid);
CREATE INDEX IF NOT EXISTS ix_poultryfeedusageline_record ON public.poultryfeedusagelines (productionrecordid);

CREATE OR REPLACE FUNCTION public.trg_poultryfeedusage_nodelete()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    RAISE EXCEPTION 'Feed usage entries are append-only; reverse the entry instead of deleting it.';
END;
$function$;

DROP TRIGGER IF EXISTS trg_poultryfeedusage_nodelete ON public.poultryfeedusageentries;
CREATE TRIGGER trg_poultryfeedusage_nodelete BEFORE DELETE ON public.poultryfeedusageentries
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryfeedusage_nodelete();
DROP TRIGGER IF EXISTS trg_poultryfeedusageline_nodelete ON public.poultryfeedusagelines;
CREATE TRIGGER trg_poultryfeedusageline_nodelete BEFORE DELETE ON public.poultryfeedusagelines
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryfeedusage_nodelete();

-- -----------------------------------------------------------------------------
-- 2. Flocks that can be fed on a date, and the state of each one's record.
--    recordstatus: None | FeedOnly | Recorded | Duplicate.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryfeedusage_candidates(text, date);
CREATE FUNCTION public.sppoultryfeedusage_candidates(p_farmid text, p_businessdate date)
RETURNS TABLE(flockid integer, flockname text, batchid integer, batchname text, housename text,
              recordstatus text, productionrecordid integer, birds integer, stockfeedkg numeric, feedlines text)
LANGUAGE plpgsql
STABLE
AS $function$
#variable_conflict use_column
BEGIN
    RETURN QUERY
    WITH e AS (
        SELECT * FROM public.sppoultryactivity_productioncompleteness(p_farmid, p_businessdate)
    ),
    rec AS (
        SELECT pr.flockid, count(*)::int AS n, min(pr.id) AS id,
               bool_and(pr.sourcetype = 'FeedUsage') AS feedonly
        FROM   productionrecords pr
        WHERE  pr.farmid = p_farmid AND pr.date = p_businessdate
        GROUP  BY pr.flockid
    )
    SELECT e.flockid, e.flockname, e.batchid, e.batchname, e.housename,
           CASE WHEN rec.n IS NULL THEN 'None'
                WHEN rec.n > 1     THEN 'Duplicate'
                WHEN rec.feedonly  THEN 'FeedOnly'
                ELSE                    'Recorded' END,
           CASE WHEN rec.n = 1 THEN rec.id END,
           public.fnpoultryfeedusage_birds(p_farmid, e.flockid, p_businessdate),
           (SELECT COALESCE(sum(f.quantityconsumed), 0) FROM productionrecordfeeds f
            WHERE rec.n = 1 AND f.productionrecordid = rec.id),
           (SELECT string_agg(format('%s %s kg', f.itemname, round(f.quantityconsumed, 2)), ', ' ORDER BY f.productionrecordfeedid)
            FROM productionrecordfeeds f WHERE rec.n = 1 AND f.productionrecordid = rec.id)
    FROM   e
    LEFT   JOIN rec ON rec.flockid = e.flockid
    ORDER  BY e.batchname NULLS LAST, e.housename NULLS LAST, e.flockname, e.flockid;
END;
$function$;

-- Birds for a flock on a date: the day's record (opening birds, else birds
-- left); with no record, the last record before the day; else the flock's
-- opening count. Same order Distribute Feed uses.
CREATE OR REPLACE FUNCTION public.fnpoultryfeedusage_birds(p_farmid text, p_flockid integer, p_date date)
RETURNS integer
LANGUAGE sql
STABLE
AS $function$
    SELECT COALESCE(
        (SELECT COALESCE(NULLIF(pr.noofbirds, 0), pr.noofbirdsleft) FROM productionrecords pr
         WHERE pr.farmid = p_farmid AND pr.flockid = p_flockid AND pr.date = p_date
         ORDER BY pr.id LIMIT 1),
        (SELECT pr.noofbirdsleft FROM productionrecords pr
         WHERE pr.farmid = p_farmid AND pr.flockid = p_flockid AND pr.date < p_date
         ORDER BY pr.date DESC, pr.id DESC LIMIT 1),
        (SELECT f.quantity FROM flock f WHERE f.flockid = p_flockid AND f.farmid = p_farmid));
$function$;

-- -----------------------------------------------------------------------------
-- 3. A feed-only record for a flock-day: no eggs, no deaths, today's birds.
--    Made through spproductionrecord_insert so every stock side effect runs
--    (all zero here), then stamped FeedUsage. The feed is added after.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryfeedusage_newrecord(p_farmid text, p_flockid integer, p_date date, p_by text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_start date;
    v_days  integer;
    v_birds integer;
    v_id    integer;
BEGIN
    SELECT f.startdate INTO v_start FROM flock f WHERE f.flockid = p_flockid AND f.farmid = p_farmid;
    v_days  := GREATEST(p_date - COALESCE(v_start, p_date), 0);
    v_birds := COALESCE(public.fnpoultryfeedusage_birds(p_farmid, p_flockid, p_date), 0);

    v_id := public.spproductionrecord_insert(
        p_farmid => p_farmid, p_createdby => p_by, p_userid => p_by,
        p_ageinweeks => v_days / 7, p_ageindays => v_days, p_date => p_date,
        p_noofbirds => v_birds, p_mortality => 0, p_noofbirdsleft => v_birds,
        p_feedkg => 0, p_medication => NULL,
        p_production9am => 0, p_production12pm => 0, p_production4pm => 0, p_totalproduction => 0,
        p_flockid => p_flockid, p_brokeneggs => 0,
        p_notes => 'Feed recorded from Feed Usage. Production not filled in yet.',
        p_feedsjson => '[]', p_medicationsjson => '[]');

    UPDATE productionrecords pr SET sourcetype = 'FeedUsage' WHERE pr.id = v_id;
    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Post. p_linesjson: [{flockId, itemId, qty, birds?}] -- one row per flock
--    and feed. All or nothing: any problem raises and nothing moves.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryfeedusage_post(text, date, text, integer, text, text, text, text);
CREATE FUNCTION public.sppoultryfeedusage_post(
    p_farmid       text,
    p_businessdate date,
    p_scope        text,
    p_batchid      integer,
    p_splitbasis   text,
    p_notes        text,
    p_linesjson    text,
    p_postedby     text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
    v_scope     text := COALESCE(NULLIF(btrim(p_scope), ''), 'Flock');
    v_n         integer;
    v_flocks    integer;
    v_total     numeric;
    v_problems  text;
    v_item      record;
    v_available numeric;
    v_id        integer;
    v_line      record;
    v_rec       record;
    v_cost      record;
    v_recid     integer;
    v_created   boolean;
    v_newrecs   integer := 0;
    v_totalcost numeric := 0;
    v_batchname text;
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN RAISE EXCEPTION 'Company ID is required.'; END IF;
    IF p_businessdate IS NULL THEN RAISE EXCEPTION 'A date is required.'; END IF;
    IF p_businessdate > public.fncompany_businessdate(p_farmid) THEN
        RAISE EXCEPTION 'You cannot record feed for a future date.';
    END IF;
    IF p_postedby IS NULL OR btrim(p_postedby) = '' THEN
        -- The consumption expense (266) is not written without a user.
        RAISE EXCEPTION 'The person recording is required.';
    END IF;
    IF v_scope NOT IN ('Flock', 'Batch') THEN RAISE EXCEPTION 'Unknown scope %.', v_scope; END IF;

    DROP TABLE IF EXISTS tmp_feedusage_lines;
    CREATE TEMP TABLE tmp_feedusage_lines ON COMMIT DROP AS
    SELECT (x->>'flockId')::int AS flockid,
           (x->>'itemId')::int  AS itemid,
           round((x->>'qty')::numeric, 3) AS qty,
           NULLIF(x->>'birds', '')::int AS birds
    FROM jsonb_array_elements(COALESCE(NULLIF(p_linesjson, ''), '[]')::jsonb) x
    WHERE COALESCE((x->>'qty')::numeric, 0) > 0;

    SELECT count(*), count(DISTINCT flockid), sum(qty) INTO v_n, v_flocks, v_total FROM tmp_feedusage_lines;
    IF v_n = 0 THEN RAISE EXCEPTION 'Enter the feed used for at least one flock.'; END IF;
    IF EXISTS (SELECT 1 FROM tmp_feedusage_lines GROUP BY flockid, itemid HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'The same feed appears twice for one flock. Put it on one line.';
    END IF;
    IF v_scope = 'Flock' AND v_flocks > 1 THEN
        RAISE EXCEPTION 'A single-flock entry can only feed one flock.';
    END IF;

    -- Every flock must be one that is expected to report on the date.
    DROP TABLE IF EXISTS tmp_feedusage_cand;
    CREATE TEMP TABLE tmp_feedusage_cand ON COMMIT DROP AS
    SELECT c.* FROM public.sppoultryfeedusage_candidates(p_farmid, p_businessdate) c;

    SELECT string_agg(DISTINCT
               CASE WHEN c.flockid IS NULL THEN format('flock #%s is not an active flock on this date', l.flockid)
                    WHEN c.recordstatus = 'Duplicate' THEN format('%s has more than one production record on this date — fix the duplicate first', c.flockname)
                    WHEN v_scope = 'Batch' AND c.batchid IS DISTINCT FROM p_batchid THEN format('%s is not in this batch', c.flockname)
               END, '; ')
    INTO v_problems
    FROM tmp_feedusage_lines l LEFT JOIN tmp_feedusage_cand c ON c.flockid = l.flockid
    WHERE c.flockid IS NULL OR c.recordstatus = 'Duplicate'
       OR (v_scope = 'Batch' AND c.batchid IS DISTINCT FROM p_batchid);
    IF v_problems IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot record: %.', v_problems USING ERRCODE = 'P0004';
    END IF;
    IF v_scope = 'Batch' THEN
        SELECT b.batchname INTO v_batchname FROM mainflockbatch b WHERE b.batchid = p_batchid AND b.farmid = p_farmid;
        IF v_batchname IS NULL THEN RAISE EXCEPTION 'Batch not found for this company.'; END IF;
    END IF;

    -- Each feed: serialise with Distribute Feed and any other entry of it, hold
    -- its lots, then check the total fits what the lots can supply.
    FOR v_item IN
        SELECT l.itemid, sum(l.qty) AS qty, i.itemname, COALESCE(i.isactive, TRUE) AS isactive,
               i.poultryrawmaterialitemid AS found
        FROM tmp_feedusage_lines l
        LEFT JOIN poultryrawmaterialitems i ON i.poultryrawmaterialitemid = l.itemid AND i.farmid = p_farmid
        GROUP BY l.itemid, i.itemname, i.isactive, i.poultryrawmaterialitemid
        ORDER BY l.itemid
    LOOP
        IF v_item.found IS NULL THEN RAISE EXCEPTION 'Feed #% not found for this company.', v_item.itemid; END IF;
        IF NOT v_item.isactive THEN RAISE EXCEPTION '% is inactive.', v_item.itemname; END IF;
        PERFORM pg_advisory_xact_lock(hashtext('poultry-feed-distribute:' || p_farmid || ':' || v_item.itemid::text));
        PERFORM 1 FROM poultryrawmaterialpurchases p
        WHERE p.farmid = p_farmid AND p.poultryrawmaterialitemid = v_item.itemid FOR UPDATE;
        SELECT a.availablekg INTO v_available FROM public.sppoultryfeeddistribution_availability(p_farmid, v_item.itemid) a;
        IF v_item.qty > COALESCE(v_available, 0) + 0.0005 THEN
            RAISE EXCEPTION 'Not enough % in stock: % kg available, % kg entered.',
                v_item.itemname, round(COALESCE(v_available, 0), 3), v_item.qty USING ERRCODE = 'P0003';
        END IF;
    END LOOP;

    INSERT INTO poultryfeedusageentries (farmid, businessdate, scope, batchid, batchname, splitbasis,
        totalkg, flockcount, status, notes, postedby)
    VALUES (p_farmid, p_businessdate, v_scope, CASE WHEN v_scope = 'Batch' THEN p_batchid END, v_batchname,
            CASE WHEN v_scope = 'Batch' THEN COALESCE(NULLIF(p_splitbasis, ''), 'Manual') END,
            v_total, v_flocks, 'Posted', NULLIF(btrim(p_notes), ''), p_postedby)
    RETURNING poultryfeedusageentryid INTO v_id;

    FOR v_line IN
        SELECT l.*, c.flockname, c.recordstatus, c.productionrecordid, c.birds AS candbirds, i.itemname
        FROM tmp_feedusage_lines l
        JOIN tmp_feedusage_cand c ON c.flockid = l.flockid
        JOIN poultryrawmaterialitems i ON i.poultryrawmaterialitemid = l.itemid
        ORDER BY c.batchname NULLS LAST, c.housename NULLS LAST, c.flockname, l.flockid, l.itemid
    LOOP
        -- The flock's record for the day; made feed-only the first time it is needed.
        SELECT pr.id INTO v_recid FROM productionrecords pr
        WHERE pr.farmid = p_farmid AND pr.flockid = v_line.flockid AND pr.date = p_businessdate
        ORDER BY pr.id LIMIT 1;
        v_created := FALSE;
        IF v_recid IS NULL THEN
            v_recid := public.fnpoultryfeedusage_newrecord(p_farmid, v_line.flockid, p_businessdate, p_postedby);
            v_created := TRUE;
            v_newrecs := v_newrecs + 1;
        END IF;

        SELECT pr.feedkg, EXISTS (SELECT 1 FROM productionrecordfeeds f WHERE f.productionrecordid = pr.id) AS hadlines
        INTO v_rec FROM productionrecords pr WHERE pr.id = v_recid;

        SELECT * INTO v_cost FROM public.fnpoultryfeeddist_changerecordfeed(
            p_farmid, v_recid, v_line.itemid, v_line.qty, p_postedby);

        INSERT INTO poultryfeedusagelines (poultryfeedusageentryid, farmid, flockid, flockname, productionrecordid,
            createdrecord, poultryrawmaterialitemid, itemname, quantitykg, unitcost, totalcost, birds,
            feedkgbefore, hadstocklinesbefore)
        VALUES (v_id, p_farmid, v_line.flockid, v_line.flockname, v_recid,
                v_created, v_line.itemid, v_line.itemname, v_line.qty, v_cost.addedunitcost, v_cost.addedtotalcost,
                COALESCE(v_line.birds, v_line.candbirds), v_rec.feedkg, v_rec.hadlines);
        v_totalcost := v_totalcost + COALESCE(v_cost.addedtotalcost, 0);
    END LOOP;

    UPDATE poultryfeedusageentries e
    SET totalcost = v_totalcost, feedonlyrecords = v_newrecs
    WHERE e.poultryfeedusageentryid = v_id;
    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Reverse. Reason required; the entry stays, marked Reversed.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryfeedusage_reverse(integer, text, text, text);
CREATE FUNCTION public.sppoultryfeedusage_reverse(p_id integer, p_farmid text, p_reason text, p_reversedby text)
RETURNS void
LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
    v_doc  record;
    v_line record;
    v_rec  integer;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a feed usage entry.';
    END IF;
    IF p_reversedby IS NULL OR btrim(p_reversedby) = '' THEN
        RAISE EXCEPTION 'The person reversing is required.';
    END IF;

    SELECT * INTO v_doc FROM poultryfeedusageentries e
    WHERE e.poultryfeedusageentryid = p_id AND e.farmid = p_farmid FOR UPDATE;
    IF v_doc.poultryfeedusageentryid IS NULL THEN RAISE EXCEPTION 'Feed usage entry not found.'; END IF;
    IF v_doc.status <> 'Posted' THEN RAISE EXCEPTION 'This feed usage entry is already reversed.'; END IF;

    FOR v_line IN
        SELECT * FROM poultryfeedusagelines l
        WHERE l.poultryfeedusageentryid = p_id ORDER BY l.poultryfeedusagelineid DESC
    LOOP
        PERFORM pg_advisory_xact_lock(hashtext('poultry-feed-distribute:' || p_farmid || ':' || v_line.poultryrawmaterialitemid::text));
        IF NOT EXISTS (SELECT 1 FROM productionrecords pr WHERE pr.id = v_line.productionrecordid AND pr.farmid = p_farmid) THEN
            -- Deleted since: its delete already gave the stock back.
            UPDATE poultryfeedusagelines l
            SET reversalnote = 'Production record was deleted after this entry; its stock had already been returned.'
            WHERE l.poultryfeedusagelineid = v_line.poultryfeedusagelineid;
            CONTINUE;
        END IF;
        PERFORM public.fnpoultryfeeddist_changerecordfeed(
            p_farmid, v_line.productionrecordid, v_line.poultryrawmaterialitemid, -v_line.quantitykg, p_reversedby,
            CASE WHEN v_line.hadstocklinesbefore THEN NULL ELSE v_line.feedkgbefore END);
    END LOOP;

    -- A feed-only record with no feed left holds nothing: remove it, so the day
    -- reads as plainly missing again.
    FOR v_rec IN
        SELECT DISTINCT l.productionrecordid FROM poultryfeedusagelines l
        JOIN productionrecords pr ON pr.id = l.productionrecordid AND pr.farmid = p_farmid
        WHERE l.poultryfeedusageentryid = p_id
          AND pr.sourcetype = 'FeedUsage'
          AND NOT EXISTS (SELECT 1 FROM productionrecordfeeds f WHERE f.productionrecordid = pr.id)
          AND NOT EXISTS (SELECT 1 FROM productionrecordmedications m WHERE m.productionrecordid = pr.id)
    LOOP
        PERFORM public.spproductionrecord_delete(v_rec, p_reversedby, p_farmid);
    END LOOP;

    UPDATE poultryfeedusageentries e
    SET status = 'Reversed', reversedby = p_reversedby, reversedatutc = now(), reversalreason = btrim(p_reason)
    WHERE e.poultryfeedusageentryid = p_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Production form saved a feed-only record: it is now production.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryproductionrecord_markrecorded(p_recordid integer, p_farmid text)
RETURNS void
LANGUAGE sql
AS $function$
    UPDATE productionrecords pr SET sourcetype = 'ManualSingleFlock'
    WHERE pr.id = p_recordid AND pr.farmid = p_farmid AND pr.sourcetype = 'FeedUsage';
$function$;

-- -----------------------------------------------------------------------------
-- 7. Readers.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryfeedusage_getall(text, date, date);
CREATE FUNCTION public.sppoultryfeedusage_getall(p_farmid text, p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL)
RETURNS SETOF public.poultryfeedusageentries
LANGUAGE sql
STABLE
AS $function$
    SELECT * FROM poultryfeedusageentries e
    WHERE e.farmid = p_farmid
      AND (p_fromdate IS NULL OR e.businessdate >= p_fromdate)
      AND (p_todate IS NULL OR e.businessdate <= p_todate)
    ORDER BY e.businessdate DESC, e.poultryfeedusageentryid DESC;
$function$;

DROP FUNCTION IF EXISTS public.sppoultryfeedusage_lines(integer, text);
CREATE FUNCTION public.sppoultryfeedusage_lines(p_id integer, p_farmid text)
RETURNS SETOF public.poultryfeedusagelines
LANGUAGE sql
STABLE
AS $function$
    SELECT * FROM poultryfeedusagelines l
    WHERE l.poultryfeedusageentryid = p_id AND l.farmid = p_farmid
    ORDER BY l.poultryfeedusagelineid;
$function$;

-- Every feed line on every production record in the range: the farm's actual
-- feed use, whichever screen entered it. entryid / distributionid say whether
-- a Feed Usage entry or a distribution put it there (same record and feed).
-- Old feedusage rows typed before 389 (no stock) come last, marked Legacy.
DROP FUNCTION IF EXISTS public.sppoultryfeedusage_log(text, date, date);
CREATE FUNCTION public.sppoultryfeedusage_log(p_farmid text, p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL)
RETURNS TABLE(usagedate date, flockid integer, flockname text, productionrecordid integer, recordsource text,
              feedonly boolean, itemid integer, itemname text, quantitykg numeric, unitcost numeric, totalcost numeric,
              entryid integer, distributionid integer, legacyfeedusageid integer)
LANGUAGE sql
STABLE
AS $function$
    SELECT pr.date, pr.flockid, f.name::text, pr.id, pr.sourcetype::text,
           (pr.sourcetype = 'FeedUsage'),
           fl.poultryrawmaterialitemid, COALESCE(fl.itemname, i.itemname)::text,
           fl.quantityconsumed, fl.unitcost, fl.totalcost,
           (SELECT max(l.poultryfeedusageentryid) FROM poultryfeedusagelines l
            JOIN poultryfeedusageentries e ON e.poultryfeedusageentryid = l.poultryfeedusageentryid AND e.status = 'Posted'
            WHERE l.productionrecordid = pr.id AND l.poultryrawmaterialitemid = fl.poultryrawmaterialitemid),
           (SELECT max(dl.poultryfeeddistributionid) FROM poultryfeeddistributionlines dl
            JOIN poultryfeeddistributions d ON d.poultryfeeddistributionid = dl.poultryfeeddistributionid AND d.status = 'Posted'
            WHERE dl.productionrecordid = pr.id AND d.poultryrawmaterialitemid = fl.poultryrawmaterialitemid),
           NULL::integer
    FROM productionrecordfeeds fl
    JOIN productionrecords pr ON pr.id = fl.productionrecordid AND pr.farmid = p_farmid
    LEFT JOIN flock f ON f.flockid = pr.flockid
    LEFT JOIN poultryrawmaterialitems i ON i.poultryrawmaterialitemid = fl.poultryrawmaterialitemid
    WHERE (p_fromdate IS NULL OR pr.date >= p_fromdate)
      AND (p_todate IS NULL OR pr.date <= p_todate)
    UNION ALL
    SELECT fu.usagedate, fu.flockid, f.name::text, NULL, 'Legacy', FALSE, NULL, fu.feedtype::text,
           fu.quantitykg, NULL, NULL, NULL, NULL, fu.feedusageid
    FROM feedusage fu
    LEFT JOIN flock f ON f.flockid = fu.flockid
    WHERE fu.farmid = p_farmid AND fu.sourceproductionrecordid IS NULL
      AND (p_fromdate IS NULL OR fu.usagedate >= p_fromdate)
      AND (p_todate IS NULL OR fu.usagedate <= p_todate)
    ORDER BY 1 DESC, 3, 8;
$function$;

-- -----------------------------------------------------------------------------
-- 8. feedusage mirror: the feed's name, once the record's lines are written.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultry_recordfeedlabel(p_recordid integer)
RETURNS text
LANGUAGE sql
STABLE
AS $function$
    SELECT left(COALESCE(
        (SELECT string_agg(DISTINCT COALESCE(f.itemname, i.itemname), ', ')
         FROM productionrecordfeeds f
         LEFT JOIN poultryrawmaterialitems i ON i.poultryrawmaterialitemid = f.poultryrawmaterialitemid
         WHERE f.productionrecordid = p_recordid),
        'General Feed'), 100);
$function$;

CREATE OR REPLACE FUNCTION public.trg_productionrecord_insertfeedusage_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO feedusage (flockid, usagedate, feedtype, quantitykg, userid, farmid, sourceproductionrecordid)
    SELECT COALESCE(i.flockid, 0), i.date, public.fnpoultry_recordfeedlabel(i.id), i.feedkg, i.userid, i.farmid, i.id
    FROM   inserted i
    WHERE  i.feedkg > 0 AND i.flockid IS NOT NULL;
    RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION public.trg_productionrecord_updatefeedusage_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Update existing FeedUsage rows sourced from these production records
    UPDATE feedusage fu
       SET usagedate  = i.date,
           quantitykg = i.feedkg,
           flockid    = COALESCE(i.flockid, fu.flockid),
           feedtype   = public.fnpoultry_recordfeedlabel(i.id)   -- 389
      FROM inserted i
     WHERE fu.sourceproductionrecordid = i.id
       AND i.feedkg > 0;

    -- Delete FeedUsage if FeedKg is now 0
    DELETE FROM feedusage fu
     USING inserted i
     WHERE fu.sourceproductionrecordid = i.id
       AND i.feedkg = 0;

    -- Insert new FeedUsage if FeedKg changed from 0 to > 0
    INSERT INTO feedusage (flockid, usagedate, feedtype, quantitykg, userid, farmid, sourceproductionrecordid)
    SELECT COALESCE(i.flockid, 0), i.date, public.fnpoultry_recordfeedlabel(i.id), i.feedkg, i.userid, i.farmid, i.id
    FROM   inserted i
    LEFT   JOIN feedusage fu ON fu.sourceproductionrecordid = i.id
    WHERE  i.feedkg > 0 AND fu.feedusageid IS NULL AND i.flockid IS NOT NULL;

    RETURN NULL;
END $function$;

-- -----------------------------------------------------------------------------
-- 9. Existing functions taught about feed-only records (see the header), and
--    the production record readers now return sourcetype.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sppoultryactivity_productioncompleteness(p_farmid text, p_businessdate date DEFAULT NULL::date, p_asof timestamp with time zone DEFAULT now())
 RETURNS TABLE(businessdate date, flockid integer, flockname text, batchid integer, batchname text, houseid integer, housename text, expectedfrom date, hasproduction boolean, recordcount integer, lastproductiondate date, daysmissing integer, pendingbatchrecordid integer, pendingbatchstatus text, severity text)
 LANGUAGE plpgsql
 STABLE
AS $function$
#variable_conflict use_column
DECLARE
    v_tz       text      := public.fncompany_timezone(p_farmid);
    v_local    timestamp := p_asof AT TIME ZONE public.fncompany_timezone(p_farmid);
    v_today    date;
    v_date     date;
    v_lastpick time      := public.fnpoultry_lastpicktime(p_farmid);
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN
        RAISE EXCEPTION 'Company ID is required.';
    END IF;

    v_today := v_local::date;
    v_date  := COALESCE(p_businessdate, v_today);

    IF v_date > v_today THEN
        RAISE EXCEPTION 'Business date % is in the future for this company (today is %).',
            v_date, v_today;
    END IF;

    RETURN QUERY
    WITH eligible AS (
        SELECT f.flockid,
               f.name::text                 AS flockname,
               f.batchid,
               b.batchname::text            AS batchname,
               f.houseid,
               h.housename::text            AS housename,
               GREATEST(
                   f.startdate,
                   COALESCE(o.effectivebusinessdate, f.startdate),
                   -- createdat is written by DEFAULT now() in a UTC session.
                   ((f.createdat AT TIME ZONE 'UTC') AT TIME ZONE v_tz)::date
               )                             AS expectedfrom
        FROM   flock f
        LEFT JOIN mainflockbatch b ON b.batchid = f.batchid AND b.farmid = f.farmid
        LEFT JOIN houses h         ON h.houseid = f.houseid AND h.farmid = f.farmid
        LEFT JOIN LATERAL (
            SELECT max(op.effectivebusinessdate) AS effectivebusinessdate
            FROM   poultryopeningflockposition op
            WHERE  op.farmid = p_farmid AND op.flockid = f.flockid
        ) o ON TRUE
        WHERE  f.farmid = p_farmid
          AND  f.active
          AND  f.hasarrived
          AND  NOT COALESCE(f.isdeleted, FALSE)
    ),
    scored AS (
        SELECT e.*,
               COALESCE(onday.n, 0)::integer  AS recordcount,
               lastrec.d                      AS lastproductiondate,
               pend.id                        AS pendingbatchrecordid,
               pend.status::text              AS pendingbatchstatus
        FROM   eligible e
        LEFT JOIN LATERAL (
            SELECT count(*) AS n
            FROM   productionrecords pr
            WHERE  pr.farmid = p_farmid AND pr.flockid = e.flockid AND pr.date = v_date AND pr.sourcetype <> 'FeedUsage'
        ) onday ON TRUE
        LEFT JOIN LATERAL (
            SELECT max(pr.date) AS d
            FROM   productionrecords pr
            WHERE  pr.farmid = p_farmid AND pr.flockid = e.flockid AND pr.date <= v_date AND pr.sourcetype <> 'FeedUsage'
        ) lastrec ON TRUE
        LEFT JOIN LATERAL (
            -- An unposted Batch Production Entry for this day that includes the
            -- flock. Posted batches have already written productionrecords;
            -- Reversed / Cancelled ones never will.
            SELECT r.id, r.status
            FROM   productionbatchrecords r
            JOIN   productionbatchincludedflocks i ON i.productionbatchrecordid = r.id
            WHERE  r.farmid = p_farmid
              AND  r.productiondate = v_date
              AND  i.flockid = e.flockid
              AND  r.status IN ('Draft', 'PendingAllocation', 'Allocated')
            ORDER  BY r.id DESC
            LIMIT  1
        ) pend ON TRUE
        WHERE  e.expectedfrom <= v_date
    ),
    gaps AS (
        SELECT s.*,
               (s.recordcount > 0) AS done,
               CASE WHEN s.recordcount > 0 THEN 0
                    -- Consecutive unrecorded days ending on v_date, counted from
                    -- the day after the last record, or from expected-from if the
                    -- flock has never reported (or its last record predates it).
                    ELSE (v_date - GREATEST(COALESCE(s.lastproductiondate + 1, s.expectedfrom),
                                            s.expectedfrom) + 1)::integer
               END AS gap
        FROM   scored s
    )
    SELECT v_date,
           g.flockid,
           g.flockname,
           g.batchid,
           g.batchname,
           g.houseid,
           g.housename,
           g.expectedfrom,
           g.done,
           g.recordcount,
           g.lastproductiondate,
           g.gap,
           g.pendingbatchrecordid,
           g.pendingbatchstatus,
           CASE WHEN g.done                          THEN NULL
                WHEN v_date < v_today OR g.gap >= 2  THEN 'Critical'
                WHEN v_local::time >= v_lastpick     THEN 'Warning'
                ELSE                                      'Information'
           END
    FROM   gaps g
    ORDER  BY g.done, g.batchname NULLS LAST, g.housename NULLS LAST, g.flockname, g.flockid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryactivity_flockmissingdates(p_farmid text, p_flockid integer, p_businessdate date DEFAULT NULL::date, p_days integer DEFAULT 30, p_asof timestamp with time zone DEFAULT now())
 RETURNS TABLE(businessdate date, missingdate date, pendingbatchrecordid integer, pendingbatchstatus text)
 LANGUAGE plpgsql
 STABLE
AS $function$
#variable_conflict use_column
DECLARE
    v_date date;
    v_from date;
    v_days integer := LEAST(GREATEST(COALESCE(p_days, 30), 1), 366);
BEGIN
    SELECT x.businessdate, x.expectedfrom INTO v_date, v_from
    FROM   public.sppoultryactivity_productioncompleteness(p_farmid, p_businessdate, p_asof) x
    WHERE  x.flockid = p_flockid;

    IF v_date IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT v_date, g.d::date, pend.id, pend.status::text
    FROM   generate_series(GREATEST(v_from, v_date - (v_days - 1)), v_date, interval '1 day') g(d)
    LEFT JOIN LATERAL (
        SELECT r.id, r.status
        FROM   productionbatchrecords r
        JOIN   productionbatchincludedflocks i ON i.productionbatchrecordid = r.id
        WHERE  r.farmid = p_farmid
          AND  r.productiondate = g.d::date
          AND  i.flockid = p_flockid
          AND  r.status IN ('Draft', 'PendingAllocation', 'Allocated')
        ORDER  BY r.id DESC
        LIMIT  1
    ) pend ON TRUE
    WHERE  NOT EXISTS (SELECT 1 FROM productionrecords pr
                       WHERE pr.farmid = p_farmid AND pr.flockid = p_flockid AND pr.date = g.d::date AND pr.sourcetype <> 'FeedUsage')
    ORDER  BY g.d DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryactivity_missingproductionbydate(p_farmid text, p_businessdate date DEFAULT NULL::date, p_days integer DEFAULT 30, p_asof timestamp with time zone DEFAULT now())
 RETURNS TABLE(businessdate date, missingdate date, flockid integer, flockname text, batchname text, housename text, pendingbatchrecordid integer, pendingbatchstatus text)
 LANGUAGE plpgsql
 STABLE
AS $function$
#variable_conflict use_column
DECLARE
    v_days integer := LEAST(GREATEST(COALESCE(p_days, 30), 1), 366);
BEGIN
    RETURN QUERY
    WITH f AS (
        -- Raises for a future business date; returns only eligible flocks.
        SELECT * FROM public.sppoultryactivity_productioncompleteness(p_farmid, p_businessdate, p_asof)
    )
    SELECT f.businessdate, g.d::date, f.flockid, f.flockname, f.batchname, f.housename,
           pend.id, pend.status::text
    FROM   f
    CROSS  JOIN LATERAL generate_series(GREATEST(f.expectedfrom, f.businessdate - (v_days - 1)),
                                        f.businessdate, interval '1 day') g(d)
    LEFT   JOIN LATERAL (
        SELECT r.id, r.status
        FROM   productionbatchrecords r
        JOIN   productionbatchincludedflocks i ON i.productionbatchrecordid = r.id
        WHERE  r.farmid = p_farmid
          AND  r.productiondate = g.d::date
          AND  i.flockid = f.flockid
          AND  r.status IN ('Draft', 'PendingAllocation', 'Allocated')
        ORDER  BY r.id DESC
        LIMIT  1
    ) pend ON TRUE
    WHERE  NOT EXISTS (SELECT 1 FROM productionrecords pr
                       WHERE pr.farmid = p_farmid AND pr.flockid = f.flockid AND pr.date = g.d::date AND pr.sourcetype <> 'FeedUsage')
    ORDER  BY g.d DESC, f.batchname NULLS LAST, f.housename NULLS LAST, f.flockname, f.flockid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryreport_missingdailyrecords_rs1(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer)
 RETURNS TABLE(date date, flockid integer, flockname text, hasproductionrecord boolean, hasfeedusage boolean, hasmortalityupdate boolean, hashealthnote boolean)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH d AS (
        SELECT gs::date AS c_dt
        FROM   generate_series(p_startdate, p_enddate, INTERVAL '1 day') AS gs
    ),
    fl AS (
        SELECT f.flockid AS c_flockid, f.name AS c_name, f.startdate AS c_startdate,
               f.closeddate AS c_closeddate
        FROM   flock f
        WHERE  f.farmid = p_farmid
          AND  (f.closeddate IS NOT NULL OR COALESCE(f.active, TRUE))       -- 338
          AND  (p_flockid IS NULL OR f.flockid = p_flockid)
          AND  f.startdate <= p_enddate
          AND  (f.closeddate IS NULL OR f.closeddate >= p_startdate)        -- 338
    ),
    grid AS (
        SELECT d.c_dt                       AS c_date,
               fl.c_flockid                 AS c_flockid,
               fl.c_name                    AS c_flockname,
               EXISTS(SELECT 1 FROM productionrecords pr
                      WHERE pr.farmid = p_farmid AND pr.flockid = fl.c_flockid AND pr.date = d.c_dt AND pr.sourcetype <> 'FeedUsage')
                                            AS c_hasproductionrecord,
               (EXISTS(SELECT 1 FROM feedusage fu
                       WHERE fu.farmid = p_farmid AND fu.flockid = fl.c_flockid AND fu.usagedate = d.c_dt)
                OR EXISTS(SELECT 1 FROM productionrecords pr
                          WHERE pr.farmid = p_farmid AND pr.flockid = fl.c_flockid AND pr.date = d.c_dt AND pr.feedkg > 0))
                                            AS c_hasfeedusage,
               EXISTS(SELECT 1 FROM productionrecords pr
                      WHERE pr.farmid = p_farmid AND pr.flockid = fl.c_flockid AND pr.date = d.c_dt AND pr.sourcetype <> 'FeedUsage')
                                            AS c_hasmortalityupdate,
               EXISTS(SELECT 1 FROM healthrecord h
                      WHERE h.farmid = p_farmid AND h.flockid = fl.c_flockid AND h.recorddate::date = d.c_dt)
                                            AS c_hashealthnote
        FROM   d CROSS JOIN fl
        WHERE  d.c_dt >= fl.c_startdate
          AND  (fl.c_closeddate IS NULL OR d.c_dt <= fl.c_closeddate)       -- 338
    )
    SELECT g.c_date, g.c_flockid, g.c_flockname::text,
           g.c_hasproductionrecord, g.c_hasfeedusage, g.c_hasmortalityupdate, g.c_hashealthnote
    FROM   grid g
    WHERE  g.c_hasproductionrecord = FALSE OR g.c_hasfeedusage = FALSE
    ORDER  BY g.c_date DESC, g.c_flockname;
END
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryreport_missingdailyrecords_rs2(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer)
 RETURNS TABLE(activeflocks integer, missingproductionrecords integer, missingfeedrecords integer, missinghealthrecords integer, completeflockdays integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH d AS (
        SELECT gs::date AS c_dt
        FROM   generate_series(p_startdate, p_enddate, INTERVAL '1 day') AS gs
    ),
    fl AS (
        SELECT f.flockid AS c_flockid, f.startdate AS c_startdate, f.closeddate AS c_closeddate
        FROM   flock f
        WHERE  f.farmid = p_farmid
          AND  (f.closeddate IS NOT NULL OR COALESCE(f.active, TRUE))       -- 338
          AND  (p_flockid IS NULL OR f.flockid = p_flockid)
          AND  f.startdate <= p_enddate
          AND  (f.closeddate IS NULL OR f.closeddate >= p_startdate)        -- 338
    ),
    grid AS (
        SELECT EXISTS(SELECT 1 FROM productionrecords pr
                      WHERE pr.farmid = p_farmid AND pr.flockid = fl.c_flockid AND pr.date = d.c_dt AND pr.sourcetype <> 'FeedUsage')
                                            AS c_hasprod,
               (EXISTS(SELECT 1 FROM feedusage fu
                       WHERE fu.farmid = p_farmid AND fu.flockid = fl.c_flockid AND fu.usagedate = d.c_dt)
                OR EXISTS(SELECT 1 FROM productionrecords pr
                          WHERE pr.farmid = p_farmid AND pr.flockid = fl.c_flockid AND pr.date = d.c_dt AND pr.feedkg > 0))
                                            AS c_hasfeed,
               EXISTS(SELECT 1 FROM healthrecord h
                      WHERE h.farmid = p_farmid AND h.flockid = fl.c_flockid AND h.recorddate::date = d.c_dt)
                                            AS c_hashealth
        FROM   d CROSS JOIN fl
        WHERE  d.c_dt >= fl.c_startdate
          AND  (fl.c_closeddate IS NULL OR d.c_dt <= fl.c_closeddate)       -- 338
    )
    SELECT
        (SELECT COUNT(*)::int FROM fl)                                                   AS activeflocks,
        SUM(CASE WHEN g.c_hasprod   = FALSE THEN 1 ELSE 0 END)::int                      AS missingproductionrecords,
        SUM(CASE WHEN g.c_hasfeed   = FALSE THEN 1 ELSE 0 END)::int                      AS missingfeedrecords,
        SUM(CASE WHEN g.c_hashealth = FALSE THEN 1 ELSE 0 END)::int                      AS missinghealthrecords,
        SUM(CASE WHEN g.c_hasprod = TRUE AND g.c_hasfeed = TRUE THEN 1 ELSE 0 END)::int  AS completeflockdays
    FROM   grid g;
END
$function$;

CREATE OR REPLACE FUNCTION public.spproductionbatchrecord_post(p_id integer, p_farmid text, p_postedby text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_userid          text;
    v_status          text;
    v_date            date;
    v_conflicts       text;
    v_dupmsg          text;
    v_bp1 integer; v_bp2 integer; v_bp3 integer; v_bp4 integer; v_bp5 integer; v_bp6 integer;
    v_bbroken integer; v_bmeaty integer; v_bsoft integer; v_blost integer; v_bdeaths integer;
    v_ap1 integer; v_ap2 integer; v_ap3 integer; v_ap4 integer; v_ap5 integer; v_ap6 integer;
    v_abroken integer; v_ameaty integer; v_asoft integer; v_alost integer; v_adeaths integer;
    v_egggrade        text;
    v_batchmedication text;
    v_feedsjson       text;
    v_medsjson        text;
    v_newrecid        integer;
    a                 record;
BEGIN
    -- Lock the header for the duration: a concurrent Post blocks here, then sees
    -- Status = 'Posted' below and throws (idempotent - no double side-effects).
    SELECT r.userid, r.status, r.productiondate
      INTO v_userid, v_status, v_date
    FROM productionbatchrecords r
    WHERE r.id = p_id AND r.farmid = p_farmid
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Batch production record not found.';
    END IF;
    IF v_status = 'Posted' THEN
        RAISE EXCEPTION 'This batch has already been posted.';
    END IF;
    IF v_status NOT IN ('Allocated', 'PendingAllocation', 'Reversed') THEN
        RAISE EXCEPTION 'Only an allocated or reversed batch can be posted.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM productionbatchallocations pa WHERE pa.productionbatchrecordid = p_id) THEN
        RAISE EXCEPTION 'This batch has no allocation rows to post.';
    END IF;

    -- ---- Duplicate daily flock production guard. ----
    -- Any pre-existing ProductionRecord for an allocated flock on the same date
    -- is a genuine conflict (manual entry or another batch). Records generated by
    -- THIS batch's previous posting were hard-deleted on reversal, so they never
    -- appear here.
    SELECT string_agg(
               COALESCE(NULLIF(btrim(a2.flockname), ''), 'Flock ' || a2.flockid::text),
               ', ' ORDER BY a2.id)
      INTO v_conflicts
    FROM productionbatchallocations a2
    WHERE a2.productionbatchrecordid = p_id
      AND EXISTS (SELECT 1 FROM productionrecords pr
                  WHERE pr.farmid = p_farmid AND pr.flockid = a2.flockid AND pr.date = v_date
                    AND pr.sourcetype <> 'FeedUsage');

    IF v_conflicts IS NOT NULL AND length(v_conflicts) > 0 THEN
        v_dupmsg := 'Cannot post: the following flock(s) already have a production record for '
                    || to_char(v_date, 'Mon DD, YYYY') || ': ' || v_conflicts
                    || '. Edit or remove the existing production record(s) before posting this allocation.';
        RAISE EXCEPTION '%', v_dupmsg;
    END IF;

    -- ---- Reconciliation: allocated egg/death totals must equal batch totals. ----
    SELECT r.firstpicktotal, r.secondpicktotal, r.thirdpicktotal, r.fourthpicktotal,
           COALESCE(r.fifthpicktotal,0), COALESCE(r.sixthpicktotal,0),
           COALESCE(r.brokeneggs,0), COALESCE(r.meatyeggs,0), COALESCE(r.softeggs,0),
           COALESCE(r.losteggs,0), COALESCE(r.deaths,0)
      INTO v_bp1, v_bp2, v_bp3, v_bp4, v_bp5, v_bp6, v_bbroken, v_bmeaty, v_bsoft, v_blost, v_bdeaths
    FROM productionbatchrecords r WHERE r.id = p_id;

    SELECT COALESCE(SUM(a2.firstpickeggs),0), COALESCE(SUM(a2.secondpickeggs),0), COALESCE(SUM(a2.thirdpickeggs),0),
           COALESCE(SUM(a2.fourthpickeggs),0),
           COALESCE(SUM(COALESCE(a2.fifthpickeggs,0)),0), COALESCE(SUM(COALESCE(a2.sixthpickeggs,0)),0),
           COALESCE(SUM(COALESCE(a2.brokeneggs,0)),0),
           COALESCE(SUM(COALESCE(a2.meatyeggs,0)),0), COALESCE(SUM(COALESCE(a2.softeggs,0)),0),
           COALESCE(SUM(COALESCE(a2.losteggs,0)),0), COALESCE(SUM(COALESCE(a2.deaths,0)),0)
      INTO v_ap1, v_ap2, v_ap3, v_ap4, v_ap5, v_ap6, v_abroken, v_ameaty, v_asoft, v_alost, v_adeaths
    FROM productionbatchallocations a2 WHERE a2.productionbatchrecordid = p_id;

    IF (v_ap1 <> v_bp1 OR v_ap2 <> v_bp2 OR v_ap3 <> v_bp3 OR v_ap4 <> v_bp4
        OR v_ap5 <> v_bp5 OR v_ap6 <> v_bp6 OR v_abroken <> v_bbroken
        OR v_ameaty <> v_bmeaty OR v_asoft <> v_bsoft OR v_alost <> v_blost OR v_adeaths <> v_bdeaths) THEN
        RAISE EXCEPTION 'Allocation does not balance against the batch egg/death totals.';
    END IF;

    -- ---- Reconciliation: allocated feed qty per item must equal batch feed qty. ----
    IF EXISTS (
        SELECT bu.inventoryitemid
        FROM productionbatchfeedusage bu
        WHERE bu.productionbatchrecordid = p_id
        GROUP BY bu.inventoryitemid
        HAVING ABS(SUM(bu.quantityused) - COALESCE((
            SELECT SUM(afu.quantityallocated)
            FROM productionbatchallocationfeedusage afu
            JOIN productionbatchallocations a3 ON a3.id = afu.productionbatchallocationid
            WHERE a3.productionbatchrecordid = p_id AND afu.inventoryitemid = bu.inventoryitemid), 0)) > 0.001
    ) THEN
        RAISE EXCEPTION 'Allocated feed quantities do not balance against the batch feed totals.';
    END IF;

    -- ---- Reconciliation: allocated medication qty per item must equal batch. ----
    IF EXISTS (
        SELECT bu.inventoryitemid
        FROM productionbatchmedicationusage bu
        WHERE bu.productionbatchrecordid = p_id
        GROUP BY bu.inventoryitemid
        HAVING ABS(SUM(bu.quantityused) - COALESCE((
            SELECT SUM(amu.quantityallocated)
            FROM productionbatchallocationmedicationusage amu
            JOIN productionbatchallocations a4 ON a4.id = amu.productionbatchallocationid
            WHERE a4.productionbatchrecordid = p_id AND amu.inventoryitemid = bu.inventoryitemid), 0)) > 0.001
    ) THEN
        RAISE EXCEPTION 'Allocated medication quantities do not balance against the batch medication totals.';
    END IF;

    SELECT r.egggrade, r.medication INTO v_egggrade, v_batchmedication
    FROM productionbatchrecords r WHERE r.id = p_id;

    FOR a IN
        SELECT pa.id                                                            AS allocid,
               pa.flockid                                                       AS flockid,
               COALESCE(pa.ageinweeks,0)                                         AS aw,
               COALESCE(pa.ageindays,0)                                          AS ad,
               COALESCE(pa.birdsbefore,0)                                        AS birdsbefore,
               COALESCE(pa.deaths,0)                                             AS deaths,
               COALESCE(pa.birdsafter, COALESCE(pa.birdsbefore,0)-COALESCE(pa.deaths,0)) AS birdsafter,
               pa.firstpickeggs                                                  AS p1,
               pa.secondpickeggs                                                 AS p2,
               pa.thirdpickeggs                                                  AS p3,
               pa.fourthpickeggs                                                 AS p4,
               COALESCE(pa.fifthpickeggs, 0)                                     AS p5,
               COALESCE(pa.sixthpickeggs, 0)                                     AS p6,
               COALESCE(pa.brokeneggs,0)                                         AS broken,
               pa.meatyeggs                                                      AS meaty,
               pa.softeggs                                                       AS soft,
               pa.losteggs                                                       AS lost,
               pa.totaleggs                                                      AS total,
               COALESCE(pa.feedkg,0)                                             AS feedkg,
               pa.notes                                                          AS notes
        FROM productionbatchallocations pa
        WHERE pa.productionbatchrecordid = p_id
        ORDER BY pa.id
    LOOP
        -- Build [{itemId,qty}] feed/medication JSON for this allocation from the flattened usage.
        SELECT json_agg(json_build_object('itemId', afu.inventoryitemid, 'qty', afu.quantityallocated))::text
          INTO v_feedsjson
        FROM productionbatchallocationfeedusage afu
        WHERE afu.productionbatchallocationid = a.allocid AND afu.quantityallocated > 0;

        SELECT json_agg(json_build_object('itemId', amu.inventoryitemid, 'qty', amu.quantityallocated))::text
          INTO v_medsjson
        FROM productionbatchallocationmedicationusage amu
        WHERE amu.productionbatchallocationid = a.allocid AND amu.quantityallocated > 0;

        v_newrecid := NULL;
        SELECT spproductionrecord_insert(
                   p_farmid          => p_farmid,
                   p_createdby       => p_postedby,
                   p_userid          => v_userid,
                   p_ageinweeks      => a.aw,
                   p_ageindays       => a.ad,
                   p_date            => v_date,
                   p_noofbirds       => a.birdsbefore,
                   p_mortality       => a.deaths,
                   p_noofbirdsleft   => a.birdsafter,
                   p_feedkg          => a.feedkg,
                   p_medication      => v_batchmedication,
                   p_production9am   => a.p1,
                   p_production12pm  => a.p2,
                   p_production4pm   => a.p3,
                   p_totalproduction => a.total,
                   p_flockid         => a.flockid,
                   p_brokeneggs      => a.broken,
                   p_notes           => a.notes,
                   p_eggcount        => a.total,
                   p_egggrade        => v_egggrade,
                   p_meatyeggs       => a.meaty,
                   p_softeggs        => a.soft,
                   p_losteggs        => a.lost,
                   p_feedsjson       => v_feedsjson,
                   p_medicationsjson => v_medsjson)
          INTO v_newrecid;

        -- 4th pick + provenance stamp on the generated flock record.
        IF v_newrecid IS NOT NULL THEN
            IF to_regprocedure('spproductionrecord_setfourthpick(integer,text,integer)') IS NOT NULL THEN
                PERFORM spproductionrecord_setfourthpick(v_newrecid, p_farmid, a.p4);
            END IF;

            -- 5th / 6th pick on the generated flock record (migration 249).
            -- Probed the same way: a database without 249 simply posts four
            -- picks rather than failing the whole batch.
            IF to_regprocedure('spproductionrecord_setextrapicks(integer,text,integer,integer)') IS NOT NULL THEN
                PERFORM spproductionrecord_setextrapicks(v_newrecid, p_farmid, a.p5, a.p6);
            END IF;

            UPDATE productionrecords pr
            SET productionbatchid = p_id,
                productionbatchallocationid = a.allocid,
                sourcetype = 'BatchAllocation'
            WHERE pr.id = v_newrecid;

            UPDATE productionbatchallocations pa
            SET generatedproductionrecordid = v_newrecid
            WHERE pa.id = a.allocid;
        END IF;
    END LOOP;

    UPDATE productionbatchrecords r
    SET status = 'Posted',
        postingversion = COALESCE(r.postingversion,0) + 1,
        postedby = p_postedby,
        posteddate = (now() at time zone 'utc'),
        updatedby = p_postedby,
        updateddate = (now() at time zone 'utc')
    WHERE r.id = p_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fnpoultryanomaly_flockdaymetrics(p_farmid text, p_from date, p_to date)
 RETURNS TABLE(flockid integer, businessdate date, recordcount integer, birds integer, deaths integer, eggs integer, feedkg numeric, mortalityper1000 numeric, layingratepct numeric, feedgramsperbird numeric, onboardingday boolean, openingeffectivedate date)
 LANGUAGE sql
 STABLE
AS $function$
    WITH d AS (
        SELECT pr.flockid,
               pr.date                                   AS businessdate,
               count(*)::int                             AS recordcount,
               -- Birds at the START of the day: the population the day's deaths,
               -- eggs and feed belong to.
               max(pr.noofbirds)::int                    AS birds,
               sum(COALESCE(pr.mortality, 0))::int       AS deaths,
               sum(COALESCE(pr.totalproduction, 0))::int AS eggs,
               -- feedkg is kept equal to the record's feed lines (155).
               sum(COALESCE(pr.feedkg, 0))               AS feedkg,
               op.effectivebusinessdate                  AS opendate,
               -- No opening position: the first recorded day is where
               -- pre-tracking history was typed before 319 existed.
               (op.flockid IS NULL AND pr.date = first.d) AS onboardingday
        FROM   productionrecords pr
        JOIN   flock f ON f.flockid = pr.flockid AND f.farmid = pr.farmid
        LEFT   JOIN poultryopeningflockposition op ON op.farmid = pr.farmid AND op.flockid = pr.flockid
        LEFT   JOIN LATERAL (
                   SELECT min(p2.date) AS d FROM productionrecords p2
                   WHERE  p2.farmid = pr.farmid AND p2.flockid = pr.flockid AND p2.sourcetype <> 'FeedUsage'
               ) first ON TRUE
        WHERE  pr.farmid = p_farmid
          AND  pr.date BETWEEN p_from AND p_to
          AND  pr.sourcetype <> 'FeedUsage'
          AND  NOT COALESCE(f.isdeleted, FALSE)
          -- Before the opening position there was no tracking: ignore.
          AND  (op.effectivebusinessdate IS NULL OR pr.date >= op.effectivebusinessdate)
        GROUP  BY pr.flockid, pr.date, op.effectivebusinessdate, op.flockid, first.d
    )
    SELECT d.flockid, d.businessdate, d.recordcount, d.birds, d.deaths, d.eggs, d.feedkg,
           CASE WHEN d.birds > 0 THEN round(d.deaths * 1000.0 / d.birds, 4) END,
           CASE WHEN d.birds > 0 THEN round(d.eggs * 100.0 / d.birds, 4) END,
           -- 0 kg means "feed not recorded", not "the birds ate nothing".
           CASE WHEN d.birds > 0 AND d.feedkg > 0 THEN round(d.feedkg * 1000.0 / d.birds, 4) END,
           d.onboardingday, d.opendate
    FROM d;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryreport_hendayproduction(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer)
 RETURNS TABLE(date date, flockid integer, flockname text, livebirds bigint, eggsproduced bigint)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        pr.date                                     AS date,
        pr.flockid                                  AS flockid,
        COALESCE(f.name, 'Unassigned')::text        AS flockname,
        SUM(pr.noofbirdsleft::bigint)::bigint       AS livebirds,
        SUM(pr.totalproduction::bigint)::bigint     AS eggsproduced
    FROM   productionrecords pr
    LEFT JOIN flock f ON f.flockid = pr.flockid AND f.farmid = pr.farmid
    WHERE  pr.farmid = p_farmid AND pr.date >= p_startdate AND pr.date <= p_enddate AND pr.sourcetype <> 'FeedUsage'
      AND  (p_flockid IS NULL OR pr.flockid = p_flockid)
    GROUP  BY pr.date, pr.flockid, f.name
    ORDER  BY pr.date DESC, f.name;
END
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryreport_dailyeggproduction(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer)
 RETURNS TABLE(date date, flockid integer, flockname text, ageinweeks integer, morningeggs integer, middayeggs integer, eveningeggs integer, fourthpickeggs integer, fifthpickeggs integer, sixthpickeggs integer, totaleggs bigint, brokeneggs bigint, birdcount bigint, notes text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        pr.date                                                                                                                AS date,
        pr.flockid                                                                                                             AS flockid,
        COALESCE(f.name, 'Unassigned')::text                                                                                   AS flockname,
        MAX(pr.ageinweeks)                                                                                                     AS ageinweeks,
        SUM(pr.production9am)::int                                                                                             AS morningeggs,
        SUM(pr.production12pm)::int                                                                                            AS middayeggs,
        SUM(pr.production4pm)::int                                                                                             AS eveningeggs,
        SUM(COALESCE(pr.production4thpick, 0))::int                                                                            AS fourthpickeggs,
        SUM(COALESCE(pr.production5thpick, 0))::int                                                                            AS fifthpickeggs,
        SUM(COALESCE(pr.production6thpick, 0))::int                                                                            AS sixthpickeggs,
        SUM(pr.totalproduction::bigint)::bigint                                                                                AS totaleggs,
        SUM((COALESCE(pr.brokeneggs,0)+COALESCE(pr.meatyeggs,0)+COALESCE(pr.softeggs,0)+COALESCE(pr.losteggs,0))::bigint)::bigint AS brokeneggs,
        SUM(pr.noofbirdsleft::bigint)::bigint                                                                                  AS birdcount,
        MAX(pr.notes)::text                                                                                                    AS notes
    FROM   productionrecords pr
    LEFT JOIN flock f ON f.flockid = pr.flockid AND f.farmid = pr.farmid
    WHERE  pr.farmid = p_farmid AND pr.date >= p_startdate AND pr.date <= p_enddate AND pr.sourcetype <> 'FeedUsage'
      AND  (p_flockid IS NULL OR pr.flockid = p_flockid)
    GROUP  BY pr.date, pr.flockid, f.name
    ORDER  BY pr.date DESC, f.name;
END
$function$;

CREATE OR REPLACE FUNCTION public.spproductionrecord_insert(p_farmid text, p_createdby text, p_userid text, p_ageinweeks integer, p_ageindays integer, p_date date, p_noofbirds integer, p_mortality integer, p_noofbirdsleft integer, p_feedkg numeric, p_medication text DEFAULT NULL::text, p_production9am integer DEFAULT NULL::integer, p_production12pm integer DEFAULT NULL::integer, p_production4pm integer DEFAULT NULL::integer, p_totalproduction integer DEFAULT NULL::integer, p_flockid integer DEFAULT NULL::integer, p_brokeneggs integer DEFAULT NULL::integer, p_notes text DEFAULT NULL::text, p_eggcount integer DEFAULT NULL::integer, p_egggrade text DEFAULT NULL::text, p_meatyeggs integer DEFAULT NULL::integer, p_softeggs integer DEFAULT NULL::integer, p_losteggs integer DEFAULT NULL::integer, p_specificfeedusedid integer DEFAULT NULL::integer, p_specificfeedusedname text DEFAULT NULL::text, p_feedunitcost numeric DEFAULT NULL::numeric, p_totalfeedconsumed numeric DEFAULT NULL::numeric, p_totalfeedcost numeric DEFAULT NULL::numeric, p_specificmedicationusedid integer DEFAULT NULL::integer, p_specificmedicationusedname text DEFAULT NULL::text, p_medicationunitcost numeric DEFAULT NULL::numeric, p_totalmedicationconsumed numeric DEFAULT NULL::numeric, p_totalmedicationcost numeric DEFAULT NULL::numeric, p_totalcostofproduction numeric DEFAULT NULL::numeric, p_medicationsjson text DEFAULT NULL::text, p_feedsjson text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_newid  integer;
    v_cnt    integer;
    v_sum    numeric;
    v_first  integer;
    v_mq     numeric;
    v_good   integer;
    v_outfeedunitcost numeric;
    v_outtotalfeedcost numeric;
    v_outmedunitcost numeric;
    v_outtotalmedcost numeric;
    v_fo     integer;
    v_feeds  jsonb;
    v_meds   jsonb;
    v_fsum   numeric;
BEGIN
    p_eggcount := COALESCE(p_eggcount, p_totalproduction);

    -- 389: Feed Usage may have made a feed-only record for this flock-day.
    -- Production for that day completes THAT record: its feed lines are kept,
    -- the lines entered now are added, and every other field comes from this
    -- call. Batch posting comes through here too, so it takes it over as well.
    IF p_flockid IS NOT NULL THEN
        SELECT pr.id INTO v_fo FROM productionrecords pr
        WHERE pr.farmid = p_farmid AND pr.flockid = p_flockid AND pr.date = p_date
          AND pr.sourcetype = 'FeedUsage'
        ORDER BY pr.id LIMIT 1
        FOR UPDATE;
    END IF;
    IF v_fo IS NOT NULL THEN
        SELECT COALESCE(jsonb_agg(jsonb_build_object('itemId', f.poultryrawmaterialitemid, 'qty', f.quantityconsumed)
                                  ORDER BY f.productionrecordfeedid), '[]'::jsonb)
        INTO v_feeds FROM productionrecordfeeds f WHERE f.productionrecordid = v_fo;
        SELECT COALESCE(jsonb_agg(jsonb_build_object('itemId', m.poultryrawmaterialitemid, 'qty', m.quantityconsumed)
                                  ORDER BY m.productionrecordmedicationid), '[]'::jsonb)
        INTO v_meds FROM productionrecordmedications m WHERE m.productionrecordid = v_fo;

        IF NULLIF(p_feedsjson, '') IS NOT NULL THEN
            v_feeds := v_feeds || p_feedsjson::jsonb;
        ELSIF p_feedsjson IS NULL AND p_specificfeedusedid IS NOT NULL AND COALESCE(p_totalfeedconsumed, 0) > 0 THEN
            v_feeds := v_feeds || jsonb_build_array(jsonb_build_object('itemId', p_specificfeedusedid, 'qty', p_totalfeedconsumed));
        END IF;
        IF NULLIF(p_medicationsjson, '') IS NOT NULL THEN
            v_meds := v_meds || p_medicationsjson::jsonb;
        ELSIF p_medicationsjson IS NULL AND p_specificmedicationusedid IS NOT NULL AND COALESCE(p_totalmedicationconsumed, 0) > 0 THEN
            v_meds := v_meds || jsonb_build_array(jsonb_build_object('itemId', p_specificmedicationusedid, 'qty', p_totalmedicationconsumed));
        END IF;

        SELECT COALESCE(sum((x->>'qty')::numeric), 0) INTO v_fsum FROM jsonb_array_elements(v_feeds) x;

        PERFORM public.spproductionrecord_update(
            p_recordid => v_fo, p_updatedby => p_createdby,
            p_ageinweeks => p_ageinweeks, p_ageindays => p_ageindays, p_date => p_date,
            p_noofbirds => p_noofbirds, p_mortality => p_mortality, p_noofbirdsleft => p_noofbirdsleft,
            -- The form's rule: stock lines, when present, ARE the feed kg.
            p_feedkg => CASE WHEN v_fsum > 0 THEN v_fsum ELSE p_feedkg END,
            p_medication => p_medication,
            p_production9am => p_production9am, p_production12pm => p_production12pm, p_production4pm => p_production4pm,
            p_totalproduction => p_totalproduction, p_flockid => p_flockid, p_brokeneggs => p_brokeneggs,
            p_notes => p_notes, p_eggcount => p_eggcount, p_egggrade => p_egggrade,
            p_meatyeggs => p_meatyeggs, p_softeggs => p_softeggs, p_losteggs => p_losteggs,
            p_medicationsjson => v_meds::text, p_feedsjson => v_feeds::text);

        UPDATE productionrecords pr SET sourcetype = 'ManualSingleFlock' WHERE pr.id = v_fo;
        RETURN v_fo;
    END IF;

    -- Derive the aggregate feed columns from the multi-line JSON when given.
    IF (p_feedsjson IS NOT NULL) THEN
        v_cnt := 0; v_sum := NULL; v_first := NULL;
        IF (length(p_feedsjson) > 0) THEN
            SELECT count(*)::int, sum(x.qty), (array_agg(x.itemid ORDER BY x.ord))[1]
            INTO v_cnt, v_sum, v_first
            FROM (SELECT (e.value->>'itemId')::integer AS itemid,
                         (e.value->>'qty')::numeric(14,3) AS qty,
                         e.ord
                  FROM jsonb_array_elements(p_feedsjson::jsonb) WITH ORDINALITY AS e(value, ord)) x
            WHERE x.itemid IS NOT NULL AND COALESCE(x.qty, 0) > 0;
        END IF;
        IF (v_cnt > 0) THEN
            p_totalfeedconsumed := v_sum;
            p_specificfeedusedid := v_first;
            SELECT it.itemname::text INTO p_specificfeedusedname FROM poultryrawmaterialitems it
            WHERE it.poultryrawmaterialitemid = p_specificfeedusedid AND it.farmid = p_farmid;
        ELSE
            p_specificfeedusedid := NULL; p_specificfeedusedname := NULL; p_totalfeedconsumed := NULL;
        END IF;
    END IF;

    -- Derive the aggregate medication columns from the multi-line JSON when given.
    IF (p_medicationsjson IS NOT NULL) THEN
        v_cnt := 0; v_sum := NULL; v_first := NULL;
        IF (length(p_medicationsjson) > 0) THEN
            SELECT count(*)::int, sum(x.qty), (array_agg(x.itemid ORDER BY x.ord))[1]
            INTO v_cnt, v_sum, v_first
            FROM (SELECT (e.value->>'itemId')::integer AS itemid,
                         (e.value->>'qty')::numeric(14,3) AS qty,
                         e.ord
                  FROM jsonb_array_elements(p_medicationsjson::jsonb) WITH ORDINALITY AS e(value, ord)) x
            WHERE x.itemid IS NOT NULL AND COALESCE(x.qty, 0) > 0;
        END IF;
        IF (v_cnt > 0) THEN
            p_totalmedicationconsumed := v_sum;
            p_specificmedicationusedid := v_first;
            SELECT it.itemname::text INTO p_specificmedicationusedname FROM poultryrawmaterialitems it
            WHERE it.poultryrawmaterialitemid = p_specificmedicationusedid AND it.farmid = p_farmid;
        ELSE
            p_specificmedicationusedid := NULL; p_specificmedicationusedname := NULL; p_totalmedicationconsumed := NULL;
        END IF;
    END IF;

    IF (p_totalcostofproduction IS NULL) THEN
        p_totalcostofproduction := COALESCE(p_totalfeedcost, 0) + COALESCE(p_totalmedicationcost, 0);
    END IF;

    INSERT INTO productionrecords (farmid, createdby, userid, ageinweeks, ageindays, date, noofbirds, mortality, noofbirdsleft, feedkg, medication, production9am, production12pm, production4pm, totalproduction, flockid, brokeneggs, notes, eggcount, egggrade, meatyeggs, softeggs, losteggs,
        specificfeedusedid, specificfeedusedname, feedunitcost, totalfeedconsumed, totalfeedcost,
        specificmedicationusedid, specificmedicationusedname, medicationunitcost, totalmedicationconsumed, totalmedicationcost,
        totalcostofproduction, createdat)
    VALUES (p_farmid, p_createdby, p_userid, p_ageinweeks, p_ageindays, p_date, p_noofbirds, p_mortality, p_noofbirdsleft, p_feedkg, p_medication, p_production9am, p_production12pm, p_production4pm, p_totalproduction, p_flockid, p_brokeneggs, p_notes, p_eggcount, p_egggrade, p_meatyeggs, p_softeggs, p_losteggs,
        p_specificfeedusedid, p_specificfeedusedname, p_feedunitcost, p_totalfeedconsumed, p_totalfeedcost,
        p_specificmedicationusedid, p_specificmedicationusedname, p_medicationunitcost, p_totalmedicationconsumed, p_totalmedicationcost,
        p_totalcostofproduction, (now() at time zone 'utc'))
    RETURNING id INTO v_newid;

    -- Bird mortality -> -birds
    v_mq := -(COALESCE(p_mortality, 0)::numeric(14,3));
    IF (v_mq <> 0) THEN
        PERFORM sppoultrybirdstock_sync(p_farmid, 'Mortality', v_mq, v_newid, 'Production mortality', p_userid);
    END IF;

    -- Good eggs -> +egg finished-product stock + stock movement
    v_good := COALESCE(p_totalproduction, 0) - COALESCE(p_brokeneggs, 0) - COALESCE(p_losteggs, 0);
    IF (v_good < 0) THEN v_good := 0; END IF;
    PERFORM sppoultryeggstock_syncforproduction(p_farmid, v_newid, v_good, NULL::numeric, p_userid);
    -- 372: broken eggs and dead birds into their own stock.
    PERFORM sppoultrybyproduct_syncforproduction(p_farmid, v_newid, FALSE, p_userid);

    -- Feed + medication -> -raw-material inventory, drawn per each item's FIFO/LIFO/HIFO policy.
    SELECT s.computedfeedunitcost, s.computedtotalfeedcost, s.computedmedicationunitcost, s.computedtotalmedicationcost
    INTO v_outfeedunitcost, v_outtotalfeedcost, v_outmedunitcost, v_outtotalmedcost
    FROM sppoultryproductionrawmaterialsync(
        p_farmid => p_farmid,
        p_productionid => v_newid,
        p_feeditemid => p_specificfeedusedid,
        p_feedqty => p_totalfeedconsumed,
        p_meditemid => p_specificmedicationusedid,
        p_medqty => p_totalmedicationconsumed,
        p_createdby => p_userid,
        p_medicationsjson => p_medicationsjson,
        p_feedsjson => p_feedsjson) s;

    UPDATE productionrecords pr
    SET feedunitcost = v_outfeedunitcost,
        totalfeedcost = v_outtotalfeedcost,
        medicationunitcost = v_outmedunitcost,
        totalmedicationcost = v_outtotalmedcost,
        totalcostofproduction = COALESCE(v_outtotalfeedcost, 0) + COALESCE(v_outtotalmedcost, 0)
    WHERE pr.id = v_newid;

    RETURN v_newid;
END;
$function$;

DROP FUNCTION IF EXISTS public.spproductionrecord_getall(text, text);
CREATE FUNCTION public.spproductionrecord_getall(p_userid text, p_farmid text)
 RETURNS TABLE(id integer, farmid text, userid text, createdby text, updatedby text, ageinweeks integer, ageindays integer, date date, noofbirds integer, mortality integer, noofbirdsleft integer, feedkg numeric, medication text, production9am integer, production12pm integer, production4pm integer, production4thpick integer, production5thpick integer, production6thpick integer, totalproduction integer, flockid integer, brokeneggs integer, notes text, eggcount integer, egggrade text, meatyeggs integer, softeggs integer, losteggs integer, specificfeedusedid integer, specificfeedusedname text, feedunitcost numeric, totalfeedconsumed numeric, totalfeedcost numeric, specificmedicationusedid integer, specificmedicationusedname text, medicationunitcost numeric, totalmedicationconsumed numeric, totalmedicationcost numeric, totalcostofproduction numeric, feedsjson text, medicationsjson text, createdat timestamp without time zone, updatedat timestamp without time zone, sourcetype text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        pr.id,
        pr.farmid::text,
        pr.userid::text,
        pr.createdby::text,
        pr.updatedby::text,
        pr.ageinweeks,
        pr.ageindays,
        pr.date,
        pr.noofbirds,
        pr.mortality,
        pr.noofbirdsleft,
        pr.feedkg,
        pr.medication::text,
        pr.production9am,
        pr.production12pm,
        pr.production4pm,
        COALESCE(pr.production4thpick, 0) AS production4thpick,
        COALESCE(pr.production5thpick, 0) AS production5thpick,
        COALESCE(pr.production6thpick, 0) AS production6thpick,
        pr.totalproduction,
        pr.flockid,
        pr.brokeneggs,
        pr.notes::text,
        COALESCE(pr.eggcount, pr.totalproduction) AS eggcount,
        pr.egggrade::text,
        pr.meatyeggs,
        pr.softeggs,
        pr.losteggs,
        pr.specificfeedusedid,
        pr.specificfeedusedname::text,
        pr.feedunitcost,
        pr.totalfeedconsumed,
        pr.totalfeedcost,
        pr.specificmedicationusedid,
        pr.specificmedicationusedname::text,
        pr.medicationunitcost,
        pr.totalmedicationconsumed,
        pr.totalmedicationcost,
        pr.totalcostofproduction,
        (SELECT json_strip_nulls(json_agg(json_build_object(
                    'specificFeedUsedId', f.poultryrawmaterialitemid,
                    'specificFeedUsedName', f.itemname,
                    'totalFeedConsumed', f.quantityconsumed,
                    'feedUnitCost', f.unitcost,
                    'totalFeedCost', f.totalcost) ORDER BY f.productionrecordfeedid))::text
         FROM productionrecordfeeds f
         WHERE f.productionrecordid = pr.id) AS feedsjson,
        (SELECT json_strip_nulls(json_agg(json_build_object(
                    'specificMedicationUsedId', m.poultryrawmaterialitemid,
                    'specificMedicationUsedName', m.itemname,
                    'totalMedicationConsumed', m.quantityconsumed,
                    'medicationUnitCost', m.unitcost,
                    'totalMedicationCost', m.totalcost) ORDER BY m.productionrecordmedicationid))::text
         FROM productionrecordmedications m
         WHERE m.productionrecordid = pr.id) AS medicationsjson,
        pr.createdat,
        pr.updatedat,
        pr.sourcetype::text AS sourcetype
    FROM productionrecords pr
    WHERE pr.farmid = p_farmid
    ORDER BY pr.date DESC, pr.createdat DESC;
END;
$function$;

DROP FUNCTION IF EXISTS public.spproductionrecord_getbyid(integer, text, text);
CREATE FUNCTION public.spproductionrecord_getbyid(p_recordid integer, p_userid text, p_farmid text)
 RETURNS TABLE(id integer, farmid text, userid text, createdby text, updatedby text, ageinweeks integer, ageindays integer, date date, noofbirds integer, mortality integer, noofbirdsleft integer, feedkg numeric, medication text, production9am integer, production12pm integer, production4pm integer, production4thpick integer, production5thpick integer, production6thpick integer, totalproduction integer, flockid integer, brokeneggs integer, notes text, eggcount integer, egggrade text, meatyeggs integer, softeggs integer, losteggs integer, specificfeedusedid integer, specificfeedusedname text, feedunitcost numeric, totalfeedconsumed numeric, totalfeedcost numeric, specificmedicationusedid integer, specificmedicationusedname text, medicationunitcost numeric, totalmedicationconsumed numeric, totalmedicationcost numeric, totalcostofproduction numeric, feedsjson text, medicationsjson text, createdat timestamp without time zone, updatedat timestamp without time zone, sourcetype text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        pr.id,
        pr.farmid::text,
        pr.userid::text,
        pr.createdby::text,
        pr.updatedby::text,
        pr.ageinweeks,
        pr.ageindays,
        pr.date,
        pr.noofbirds,
        pr.mortality,
        pr.noofbirdsleft,
        pr.feedkg,
        pr.medication::text,
        pr.production9am,
        pr.production12pm,
        pr.production4pm,
        COALESCE(pr.production4thpick, 0) AS production4thpick,
        COALESCE(pr.production5thpick, 0) AS production5thpick,
        COALESCE(pr.production6thpick, 0) AS production6thpick,
        pr.totalproduction,
        pr.flockid,
        pr.brokeneggs,
        pr.notes::text,
        COALESCE(pr.eggcount, pr.totalproduction) AS eggcount,
        pr.egggrade::text,
        pr.meatyeggs,
        pr.softeggs,
        pr.losteggs,
        pr.specificfeedusedid,
        pr.specificfeedusedname::text,
        pr.feedunitcost,
        pr.totalfeedconsumed,
        pr.totalfeedcost,
        pr.specificmedicationusedid,
        pr.specificmedicationusedname::text,
        pr.medicationunitcost,
        pr.totalmedicationconsumed,
        pr.totalmedicationcost,
        pr.totalcostofproduction,
        (SELECT json_strip_nulls(json_agg(json_build_object(
                    'specificFeedUsedId', f.poultryrawmaterialitemid,
                    'specificFeedUsedName', f.itemname,
                    'totalFeedConsumed', f.quantityconsumed,
                    'feedUnitCost', f.unitcost,
                    'totalFeedCost', f.totalcost) ORDER BY f.productionrecordfeedid))::text
         FROM productionrecordfeeds f
         WHERE f.productionrecordid = pr.id) AS feedsjson,
        (SELECT json_strip_nulls(json_agg(json_build_object(
                    'specificMedicationUsedId', m.poultryrawmaterialitemid,
                    'specificMedicationUsedName', m.itemname,
                    'totalMedicationConsumed', m.quantityconsumed,
                    'medicationUnitCost', m.unitcost,
                    'totalMedicationCost', m.totalcost) ORDER BY m.productionrecordmedicationid))::text
         FROM productionrecordmedications m
         WHERE m.productionrecordid = pr.id) AS medicationsjson,
        pr.createdat,
        pr.updatedat,
        pr.sourcetype::text AS sourcetype
    FROM productionrecords pr
    WHERE pr.id = p_recordid AND pr.farmid = p_farmid;
END;
$function$;

COMMIT;
