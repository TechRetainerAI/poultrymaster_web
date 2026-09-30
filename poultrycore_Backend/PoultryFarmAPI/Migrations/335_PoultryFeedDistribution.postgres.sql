-- =============================================================================
-- 335_PoultryFeedDistribution.postgres.sql
--
-- Purpose
-- -------
-- Distribute Feed: give one feed product to many flocks for one business date
-- in a single operation. An ORCHESTRATION tool -- it produces exactly the
-- records a farmer would get by opening each flock's production record and
-- adding the feed line by hand.
--
-- HOW FEED LEAVES STOCK IN THIS SYSTEM (and therefore how this posts)
-- ===================================================================
-- Feed is drawn from inventory in exactly one place: the feed LINES on a
-- flock's production record for the day. spproductionrecord_update calls
-- sppoultryproductionrawmaterialsync, which
--   * restores and re-draws the record's lots through
--     sppoultryrawmaterialitem_consumebatches (FIFO / LIFO / HIFO per item),
--   * writes poultryrawmaterialusage / usagebatch and productionrecordfeeds,
--   * books or reverses the consumption expense (266 / 272) according to the
--     cost-recognition method stamped on each lot -- nothing for feed expensed
--     at purchase, a NonCash 'PoultryFeedConsumption' row for feed expensed at
--     consumption,
--   * and the feedusage trigger keeps the flock's feedusage row in step.
-- (/feed-usage writes a label + kg only and never touches stock, so it is NOT
-- the path to reuse.)
--
-- So posting a distribution = for each flock, call spproductionrecord_update
-- with every field of that flock's record unchanged, its existing feed lines
-- PLUS the distributed line, and its medication lines passed through as they
-- are. No stock movement, lot draw, cost or expense is computed here. Stock
-- therefore decreases exactly once per distributed kg, through the engine.
--
-- PRODUCTION FIRST (decided 2026-09-30)
-- =====================================
-- A flock is distributed to only if it has exactly ONE production record for
-- the date. No record: refused ("record production first") -- creating a
-- feed-only record would make Farm Completeness and Daily Closing read the
-- day's production as done. Two or more records: refused (fix the duplicate
-- first; which record the feed belongs on is not a guess to make).
--
-- FEED KG ON THE RECORD
-- =====================
-- The form's rule is kept: when a record has feed lines from stock, its feed kg
-- IS their sum. A record that only had a manual kg (no stock lines) therefore
-- has that manual figure replaced by the stock lines -- exactly what happens
-- when the same line is added on the form. The manual figure is kept on the
-- distribution line and put back if the distribution is reversed.
--
-- CONCURRENCY
-- ===========
-- The post takes an advisory lock for (farm, feed item) and locks the item's
-- purchase lots FOR UPDATE, then re-reads what the lots can supply. Two users
-- distributing the same feed at once serialise; the second sees what the first
-- left and is refused if it no longer fits. An individual production save for
-- the same item waits on the lot locks too.
--
-- NEGATIVE STOCK
-- ==============
-- There is no negative-stock setting for raw materials (181 removed the last
-- one; the consume engine refuses any shortfall). A distribution larger than
-- the lots can supply is refused before anything moves.
--
-- REVERSAL
-- ========
-- Append-only at the document level: the distribution and its lines are never
-- deleted (a trigger refuses it); reversal marks them Reversed with who / when
-- / why. Each flock's distributed quantity is removed from its record through
-- the same spproductionrecord_update, so the engine restores the lots and
-- appends the opposite consumption-expense row. NOTE -- inherited, not added:
-- when ANY production record is edited, the engine rewrites that record's live
-- usage rows rather than appending (only a record DELETE is append-only in the
-- stock ledger). Distribution posting and reversal are record edits, so they
-- behave exactly like editing the record by hand.
--
-- Depends on 332 (flock eligibility). Idempotent. Safe to run more than once.
-- EFFECT ON TODAY'S NUMBERS: none until a distribution is posted.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Documents (append-only).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultryfeeddistributions (
    poultryfeeddistributionid serial      PRIMARY KEY,
    farmid                    text        NOT NULL,
    businessdate              date        NOT NULL,
    poultryrawmaterialitemid  integer     NOT NULL,
    itemname                  text,
    basis                     text        NOT NULL DEFAULT 'Manual'
        CONSTRAINT ck_poultryfeeddist_basis CHECK (basis IN ('Manual', 'Rate', 'RecentAverage')),
    gramsperbirdperday        numeric(10,3),
    totalsuggestedkg          numeric(14,3),
    totalactualkg             numeric(14,3) NOT NULL,
    totalcost                 numeric(14,2),
    flockcount                integer     NOT NULL,
    status                    text        NOT NULL DEFAULT 'Posted'
        CONSTRAINT ck_poultryfeeddist_status CHECK (status IN ('Posted', 'Reversed')),
    notes                     text,
    postedby                  text,
    postedatutc               timestamptz NOT NULL DEFAULT now(),
    reversedby                text,
    reversedatutc             timestamptz,
    reversalreason            text
);
CREATE INDEX IF NOT EXISTS ix_poultryfeeddist_farm_date ON public.poultryfeeddistributions (farmid, businessdate DESC);

CREATE TABLE IF NOT EXISTS public.poultryfeeddistributionlines (
    poultryfeeddistributionlineid serial   PRIMARY KEY,
    poultryfeeddistributionid     integer  NOT NULL REFERENCES public.poultryfeeddistributions (poultryfeeddistributionid),
    farmid                        text     NOT NULL,
    flockid                       integer  NOT NULL,
    flockname                     text,
    productionrecordid            integer  NOT NULL,
    birds                         integer,
    suggestedkg                   numeric(14,3),
    actualkg                      numeric(14,3) NOT NULL CHECK (actualkg > 0),
    unitcost                      numeric(14,4),
    totalcost                     numeric(14,2),
    notes                         text,
    -- The record's feed kg and whether it had stock lines BEFORE this line was
    -- added, so a reversal can restore a manual-only figure the post replaced.
    feedkgbefore                  numeric(14,3),
    hadstocklinesbefore           boolean  NOT NULL DEFAULT FALSE,
    reversalnote                  text
);
CREATE INDEX IF NOT EXISTS ix_poultryfeeddistline_dist ON public.poultryfeeddistributionlines (poultryfeeddistributionid);
CREATE INDEX IF NOT EXISTS ix_poultryfeeddistline_record ON public.poultryfeeddistributionlines (productionrecordid);

CREATE OR REPLACE FUNCTION public.trg_poultryfeeddist_nodelete()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    RAISE EXCEPTION 'Feed distributions are append-only; reverse the distribution instead of deleting it.';
END;
$function$;

DROP TRIGGER IF EXISTS trg_poultryfeeddist_nodelete ON public.poultryfeeddistributions;
CREATE TRIGGER trg_poultryfeeddist_nodelete BEFORE DELETE ON public.poultryfeeddistributions
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryfeeddist_nodelete();
DROP TRIGGER IF EXISTS trg_poultryfeeddistline_nodelete ON public.poultryfeeddistributionlines;
CREATE TRIGGER trg_poultryfeeddistline_nodelete BEFORE DELETE ON public.poultryfeeddistributionlines
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryfeeddist_nodelete();

-- -----------------------------------------------------------------------------
-- 2. Feed rate (grams per bird per day) -- the farm's own figure per feed
--    product. Nothing here assumes a "standard" rate: no row, no suggestion.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultryfeedrates (
    farmid                   text NOT NULL,
    poultryrawmaterialitemid integer NOT NULL,
    gramsperbirdperday       numeric(10,3) NOT NULL CHECK (gramsperbirdperday > 0),
    updatedby                text,
    updatedatutc             timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (farmid, poultryrawmaterialitemid)
);

CREATE OR REPLACE FUNCTION public.sppoultryfeedrate_set(
    p_farmid text, p_itemid integer, p_grams numeric, p_updatedby text)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM poultryrawmaterialitems i
                   WHERE i.poultryrawmaterialitemid = p_itemid AND i.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Feed product not found for this company.';
    END IF;
    IF p_grams IS NULL THEN
        DELETE FROM poultryfeedrates r WHERE r.farmid = p_farmid AND r.poultryrawmaterialitemid = p_itemid;
        RETURN;
    END IF;
    IF p_grams <= 0 THEN
        RAISE EXCEPTION 'A feed rate must be more than 0 grams per bird per day.';
    END IF;
    INSERT INTO poultryfeedrates AS t (farmid, poultryrawmaterialitemid, gramsperbirdperday, updatedby, updatedatutc)
    VALUES (p_farmid, p_itemid, p_grams, p_updatedby, now())
    ON CONFLICT (farmid, poultryrawmaterialitemid) DO UPDATE
    SET gramsperbirdperday = EXCLUDED.gramsperbirdperday, updatedby = EXCLUDED.updatedby, updatedatutc = now();
END;
$function$;

-- -----------------------------------------------------------------------------
-- 3. What the chosen feed can supply right now -- from its purchase LOTS,
--    because that is exactly what the consume engine will draw from.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryfeeddistribution_availability(text, integer);
CREATE FUNCTION public.sppoultryfeeddistribution_availability(p_farmid text, p_itemid integer)
RETURNS TABLE(
    poultryrawmaterialitemid integer, itemname text, category text, unitofmeasure text,
    usagemethod text, availablekg numeric, currentquantity numeric, lotcount integer,
    costrecognitionmethod text, gramsperbirdperday numeric)
LANGUAGE sql
STABLE
AS $function$
    SELECT i.poultryrawmaterialitemid, i.itemname::text, i.category::text, i.unitofmeasure::text,
           COALESCE(i.usagemethod, 'FIFO')::text,
           COALESCE((SELECT sum(p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1))
                     FROM poultryrawmaterialpurchases p
                     WHERE p.farmid = p_farmid AND p.poultryrawmaterialitemid = i.poultryrawmaterialitemid
                       AND p.remainingquantity > 0), 0)::numeric(14,3),
           i.currentquantity,
           (SELECT count(*)::int FROM poultryrawmaterialpurchases p
            WHERE p.farmid = p_farmid AND p.poultryrawmaterialitemid = i.poultryrawmaterialitemid
              AND p.remainingquantity > 0),
           (SELECT e.method FROM public.fnpoultrycostrecognition_effective(
                p_farmid, i.poultryrawmaterialitemid, i.category, public.fncompany_businessdate(p_farmid)) e),
           (SELECT r.gramsperbirdperday FROM poultryfeedrates r
            WHERE r.farmid = p_farmid AND r.poultryrawmaterialitemid = i.poultryrawmaterialitemid)
    FROM   poultryrawmaterialitems i
    WHERE  i.farmid = p_farmid AND i.poultryrawmaterialitemid = p_itemid;
$function$;

-- -----------------------------------------------------------------------------
-- 4. The grid: every flock that is expected to report on the date (the same
--    eligibility as Farm Completeness, 332), with what the suggestion needs.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryfeeddistribution_candidates(text, date, integer, integer);
CREATE FUNCTION public.sppoultryfeeddistribution_candidates(
    p_farmid text, p_businessdate date, p_itemid integer, p_avgdays integer DEFAULT 7)
RETURNS TABLE(
    flockid integer, flockname text, batchname text, housename text,
    recordcount integer, productionrecordid integer, birds integer,
    manualfeedkg numeric, stockfeedkg numeric, thisitemkg numeric,
    recentavgkg numeric, recentavgdays integer)
LANGUAGE plpgsql
STABLE
AS $function$
#variable_conflict use_column
DECLARE
    v_days integer := LEAST(GREATEST(COALESCE(p_avgdays, 7), 1), 60);
BEGIN
    RETURN QUERY
    WITH e AS (
        SELECT * FROM public.sppoultryactivity_productioncompleteness(p_farmid, p_businessdate)
    ),
    rec AS (
        SELECT pr.flockid, count(*)::int AS n, min(pr.id) AS id
        FROM   productionrecords pr
        WHERE  pr.farmid = p_farmid AND pr.date = p_businessdate
        GROUP  BY pr.flockid
    )
    SELECT e.flockid, e.flockname, e.batchname, e.housename,
           COALESCE(rec.n, 0),
           CASE WHEN rec.n = 1 THEN rec.id END,
           -- Birds: the day's record (opening birds, else birds left); with no
           -- record, the last record before the day, else the flock's count.
           COALESCE(
               (SELECT COALESCE(NULLIF(pr.noofbirds, 0), pr.noofbirdsleft) FROM productionrecords pr
                WHERE pr.id = rec.id AND rec.n = 1),
               (SELECT pr.noofbirdsleft FROM productionrecords pr
                WHERE pr.farmid = p_farmid AND pr.flockid = e.flockid AND pr.date < p_businessdate
                ORDER BY pr.date DESC, pr.id DESC LIMIT 1),
               (SELECT f.quantity FROM flock f WHERE f.flockid = e.flockid)),
           -- Feed already on the day's record: manual kg (only meaningful when
           -- it has no stock lines), stock lines in total, and this product.
           CASE WHEN rec.n = 1 AND NOT EXISTS (SELECT 1 FROM productionrecordfeeds f WHERE f.productionrecordid = rec.id)
                THEN (SELECT pr.feedkg FROM productionrecords pr WHERE pr.id = rec.id) END,
           (SELECT COALESCE(sum(f.quantityconsumed), 0) FROM productionrecordfeeds f
            WHERE rec.n = 1 AND f.productionrecordid = rec.id),
           (SELECT COALESCE(sum(f.quantityconsumed), 0) FROM productionrecordfeeds f
            WHERE rec.n = 1 AND f.productionrecordid = rec.id AND f.poultryrawmaterialitemid = p_itemid),
           -- Recent average of THIS product: per day it was actually given, over
           -- the days before the date. Null when there is no history -- never a
           -- stand-in figure.
           (SELECT round(sum(f.quantityconsumed) / count(DISTINCT pr.date), 3)
            FROM productionrecords pr JOIN productionrecordfeeds f ON f.productionrecordid = pr.id
            WHERE pr.farmid = p_farmid AND pr.flockid = e.flockid
              AND pr.date BETWEEN p_businessdate - v_days AND p_businessdate - 1
              AND f.poultryrawmaterialitemid = p_itemid),
           (SELECT count(DISTINCT pr.date)::int
            FROM productionrecords pr JOIN productionrecordfeeds f ON f.productionrecordid = pr.id
            WHERE pr.farmid = p_farmid AND pr.flockid = e.flockid
              AND pr.date BETWEEN p_businessdate - v_days AND p_businessdate - 1
              AND f.poultryrawmaterialitemid = p_itemid)
    FROM   e
    LEFT   JOIN rec ON rec.flockid = e.flockid
    ORDER  BY e.batchname NULLS LAST, e.housename NULLS LAST, e.flockname, e.flockid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Change one record's quantity of one feed item by p_delta, through the
--    ordinary record update. Internal: post and reverse are its only callers.
--    Returns the unit cost and total cost of the line added (post only).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultryfeeddist_changerecordfeed(
    p_farmid text, p_recordid integer, p_itemid integer, p_delta numeric,
    p_by text, p_restorefeedkg numeric DEFAULT NULL,
    OUT addedunitcost numeric, OUT addedtotalcost numeric)
RETURNS record
LANGUAGE plpgsql
AS $function$
DECLARE
    r        productionrecords%ROWTYPE;
    v_feeds  jsonb;
    v_meds   jsonb;
    v_have   numeric;
    v_left   numeric;
    v_line   record;
    v_sum    numeric;
    v_feedkg numeric;
BEGIN
    SELECT * INTO r FROM productionrecords pr WHERE pr.id = p_recordid AND pr.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Production record % not found for this company.', p_recordid;
    END IF;

    -- The record's current lines are its truth (the sync rewrites them).
    SELECT COALESCE(jsonb_agg(jsonb_build_object('itemId', f.poultryrawmaterialitemid, 'qty', f.quantityconsumed)
                              ORDER BY f.productionrecordfeedid), '[]'::jsonb)
    INTO v_feeds FROM productionrecordfeeds f WHERE f.productionrecordid = p_recordid;
    SELECT COALESCE(jsonb_agg(jsonb_build_object('itemId', m.poultryrawmaterialitemid, 'qty', m.quantityconsumed)
                              ORDER BY m.productionrecordmedicationid), '[]'::jsonb)
    INTO v_meds FROM productionrecordmedications m WHERE m.productionrecordid = p_recordid;

    IF p_delta > 0 THEN
        v_feeds := v_feeds || jsonb_build_object('itemId', p_itemid, 'qty', p_delta);
    ELSIF p_delta < 0 THEN
        SELECT COALESCE(sum((x->>'qty')::numeric), 0) INTO v_have
        FROM jsonb_array_elements(v_feeds) x WHERE (x->>'itemId')::int = p_itemid;
        IF v_have + 0.0005 < -p_delta THEN
            RAISE EXCEPTION 'Record % now has only % of this feed, less than the % being reversed. It was edited after the distribution; adjust it on the record instead.',
                p_recordid, v_have, -p_delta USING ERRCODE = 'P0005';
        END IF;
        -- Take the quantity back from this item's lines, newest line first.
        v_left := -p_delta;
        SELECT COALESCE(jsonb_agg(z.line ORDER BY z.ord), '[]'::jsonb) INTO v_feeds
        FROM (
            SELECT w.ord,
                   CASE WHEN (w.line->>'itemId')::int <> p_itemid THEN w.line
                        ELSE jsonb_build_object('itemId', p_itemid,
                             'qty', (w.line->>'qty')::numeric - LEAST((w.line->>'qty')::numeric,
                                    GREATEST(-p_delta - COALESCE(w.takenafter, 0), 0)))
                   END AS line
            FROM (
                SELECT x.line, x.ord,
                       sum(CASE WHEN (x.line->>'itemId')::int = p_itemid THEN (x.line->>'qty')::numeric ELSE 0 END)
                           OVER (ORDER BY x.ord DESC ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS takenafter
                FROM jsonb_array_elements(v_feeds) WITH ORDINALITY AS x(line, ord)
            ) w
        ) z
        WHERE (z.line->>'qty')::numeric > 0.0005;
    END IF;

    SELECT COALESCE(sum((x->>'qty')::numeric), 0) INTO v_sum FROM jsonb_array_elements(v_feeds) x;
    -- The form's rule: stock lines, when present, ARE the record's feed kg.
    v_feedkg := CASE WHEN v_sum > 0 THEN v_sum ELSE COALESCE(p_restorefeedkg, r.feedkg) END;

    PERFORM public.spproductionrecord_update(
        p_recordid => r.id, p_updatedby => p_by,
        p_ageinweeks => r.ageinweeks, p_ageindays => r.ageindays, p_date => r.date,
        p_noofbirds => r.noofbirds, p_mortality => r.mortality, p_noofbirdsleft => r.noofbirdsleft,
        p_feedkg => v_feedkg, p_medication => r.medication,
        p_production9am => r.production9am, p_production12pm => r.production12pm, p_production4pm => r.production4pm,
        p_totalproduction => r.totalproduction, p_flockid => r.flockid, p_brokeneggs => r.brokeneggs,
        p_notes => r.notes, p_eggcount => r.eggcount, p_egggrade => r.egggrade,
        p_meatyeggs => r.meatyeggs, p_softeggs => r.softeggs, p_losteggs => r.losteggs,
        p_feedunitcost => r.feedunitcost, p_totalfeedcost => r.totalfeedcost,
        p_medicationunitcost => r.medicationunitcost, p_totalmedicationcost => r.totalmedicationcost,
        p_medicationsjson => v_meds::text,
        p_feedsjson => v_feeds::text);

    IF p_delta > 0 THEN
        -- The distributed line is the last one the sync wrote for this record.
        SELECT f.unitcost, f.totalcost INTO addedunitcost, addedtotalcost
        FROM productionrecordfeeds f
        WHERE f.productionrecordid = p_recordid AND f.poultryrawmaterialitemid = p_itemid
        ORDER BY f.productionrecordfeedid DESC LIMIT 1;
    END IF;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Post. p_linesjson: [{flockId, actualKg, suggestedKg?, birds?, notes?}].
--    All flocks or none: any problem raises and nothing moves.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryfeeddistribution_post(text, date, integer, text, numeric, text, text, text);
CREATE FUNCTION public.sppoultryfeeddistribution_post(
    p_farmid       text,
    p_businessdate date,
    p_itemid       integer,
    p_basis        text,
    p_grams        numeric,
    p_notes        text,
    p_linesjson    text,
    p_postedby     text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
    v_item      record;
    v_available numeric;
    v_total     numeric;
    v_id        integer;
    v_line      record;
    v_rec       record;
    v_cost      record;
    v_n         integer;
    v_totalcost numeric := 0;
    v_problems  text;
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN RAISE EXCEPTION 'Company ID is required.'; END IF;
    IF p_businessdate IS NULL THEN RAISE EXCEPTION 'A business date is required.'; END IF;
    IF p_businessdate > public.fncompany_businessdate(p_farmid) THEN
        RAISE EXCEPTION 'You cannot distribute feed for a future date.';
    END IF;
    IF p_postedby IS NULL OR btrim(p_postedby) = '' THEN
        -- The consumption expense (266) is not written without a user.
        RAISE EXCEPTION 'The person posting is required.';
    END IF;

    SELECT i.poultryrawmaterialitemid, i.itemname, COALESCE(i.isactive, TRUE) AS isactive
    INTO v_item FROM poultryrawmaterialitems i
    WHERE i.poultryrawmaterialitemid = p_itemid AND i.farmid = p_farmid;
    IF v_item.poultryrawmaterialitemid IS NULL THEN
        RAISE EXCEPTION 'Feed product not found for this company.';
    END IF;
    IF NOT v_item.isactive THEN RAISE EXCEPTION 'This feed product is inactive.'; END IF;

    DROP TABLE IF EXISTS tmp_feeddist_lines;
    CREATE TEMP TABLE tmp_feeddist_lines ON COMMIT DROP AS
    SELECT (x->>'flockId')::int AS flockid,
           round((x->>'actualKg')::numeric, 3) AS actualkg,
           round(NULLIF(x->>'suggestedKg', '')::numeric, 3) AS suggestedkg,
           NULLIF(x->>'birds', '')::int AS birds,
           NULLIF(btrim(x->>'notes'), '') AS notes
    FROM jsonb_array_elements(COALESCE(NULLIF(p_linesjson, ''), '[]')::jsonb) x
    WHERE COALESCE((x->>'actualKg')::numeric, 0) > 0;

    SELECT count(*), sum(actualkg) INTO v_n, v_total FROM tmp_feeddist_lines;
    IF v_n = 0 THEN RAISE EXCEPTION 'Enter feed for at least one flock.'; END IF;
    IF EXISTS (SELECT flockid FROM tmp_feeddist_lines GROUP BY flockid HAVING count(*) > 1) THEN
        RAISE EXCEPTION 'A flock appears more than once in this distribution.';
    END IF;

    -- Serialise with any other distribution of this feed, and hold the lots so
    -- an individual production save cannot draw them out from under us.
    PERFORM pg_advisory_xact_lock(hashtext('poultry-feed-distribute:' || p_farmid || ':' || p_itemid::text));
    PERFORM 1 FROM poultryrawmaterialpurchases p
    WHERE p.farmid = p_farmid AND p.poultryrawmaterialitemid = p_itemid FOR UPDATE;

    SELECT a.availablekg INTO v_available FROM public.sppoultryfeeddistribution_availability(p_farmid, p_itemid) a;
    IF v_total > COALESCE(v_available, 0) + 0.0005 THEN
        RAISE EXCEPTION 'Not enough % in stock: % kg available, % kg to distribute.',
            v_item.itemname, round(COALESCE(v_available, 0), 3), v_total USING ERRCODE = 'P0003';
    END IF;

    -- Every flock must be eligible on the date and have exactly one record.
    DROP TABLE IF EXISTS tmp_feeddist_cand;
    CREATE TEMP TABLE tmp_feeddist_cand ON COMMIT DROP AS
    SELECT c.* FROM public.sppoultryfeeddistribution_candidates(p_farmid, p_businessdate, p_itemid) c;

    SELECT string_agg(
               CASE WHEN c.flockid IS NULL THEN format('flock #%s is not an active flock of this company', l.flockid)
                    WHEN c.recordcount = 0 THEN format('%s has no production record for this date — record production first', c.flockname)
                    WHEN c.recordcount > 1 THEN format('%s has %s production records for this date — fix the duplicate first', c.flockname, c.recordcount)
               END, '; ')
    INTO v_problems
    FROM tmp_feeddist_lines l LEFT JOIN tmp_feeddist_cand c ON c.flockid = l.flockid
    WHERE c.flockid IS NULL OR c.recordcount <> 1;
    IF v_problems IS NOT NULL THEN
        RAISE EXCEPTION 'Cannot post: %.', v_problems USING ERRCODE = 'P0004';
    END IF;

    INSERT INTO poultryfeeddistributions (farmid, businessdate, poultryrawmaterialitemid, itemname, basis,
        gramsperbirdperday, totalsuggestedkg, totalactualkg, flockcount, status, notes, postedby)
    VALUES (p_farmid, p_businessdate, p_itemid, v_item.itemname,
            COALESCE(NULLIF(p_basis, ''), 'Manual'), p_grams,
            (SELECT sum(suggestedkg) FROM tmp_feeddist_lines), v_total, v_n, 'Posted',
            NULLIF(btrim(p_notes), ''), p_postedby)
    RETURNING poultryfeeddistributionid INTO v_id;

    FOR v_line IN
        SELECT l.*, c.flockname, c.productionrecordid, c.birds AS candbirds
        FROM tmp_feeddist_lines l JOIN tmp_feeddist_cand c ON c.flockid = l.flockid
        ORDER BY c.batchname NULLS LAST, c.housename NULLS LAST, c.flockname, l.flockid
    LOOP
        SELECT pr.feedkg, EXISTS (SELECT 1 FROM productionrecordfeeds f WHERE f.productionrecordid = pr.id) AS hadlines
        INTO v_rec FROM productionrecords pr WHERE pr.id = v_line.productionrecordid;

        SELECT * INTO v_cost FROM public.fnpoultryfeeddist_changerecordfeed(
            p_farmid, v_line.productionrecordid, p_itemid, v_line.actualkg, p_postedby);

        INSERT INTO poultryfeeddistributionlines (poultryfeeddistributionid, farmid, flockid, flockname,
            productionrecordid, birds, suggestedkg, actualkg, unitcost, totalcost, notes,
            feedkgbefore, hadstocklinesbefore)
        VALUES (v_id, p_farmid, v_line.flockid, v_line.flockname, v_line.productionrecordid,
                COALESCE(v_line.birds, v_line.candbirds), v_line.suggestedkg, v_line.actualkg,
                v_cost.addedunitcost, v_cost.addedtotalcost, v_line.notes,
                v_rec.feedkg, v_rec.hadlines);
        v_totalcost := v_totalcost + COALESCE(v_cost.addedtotalcost, 0);
    END LOOP;

    UPDATE poultryfeeddistributions d SET totalcost = v_totalcost WHERE d.poultryfeeddistributionid = v_id;
    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 7. Reverse. Reason required; the document stays, marked Reversed.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryfeeddistribution_reverse(integer, text, text, text);
CREATE FUNCTION public.sppoultryfeeddistribution_reverse(
    p_id integer, p_farmid text, p_reason text, p_reversedby text)
RETURNS void
LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
    v_doc  record;
    v_line record;
BEGIN
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a feed distribution.';
    END IF;
    IF p_reversedby IS NULL OR btrim(p_reversedby) = '' THEN
        RAISE EXCEPTION 'The person reversing is required.';
    END IF;

    SELECT * INTO v_doc FROM poultryfeeddistributions d
    WHERE d.poultryfeeddistributionid = p_id AND d.farmid = p_farmid FOR UPDATE;
    IF v_doc.poultryfeeddistributionid IS NULL THEN RAISE EXCEPTION 'Feed distribution not found.'; END IF;
    IF v_doc.status <> 'Posted' THEN RAISE EXCEPTION 'This feed distribution is already reversed.'; END IF;

    PERFORM pg_advisory_xact_lock(hashtext('poultry-feed-distribute:' || p_farmid || ':' || v_doc.poultryrawmaterialitemid::text));

    FOR v_line IN
        SELECT * FROM poultryfeeddistributionlines l
        WHERE l.poultryfeeddistributionid = p_id ORDER BY l.poultryfeeddistributionlineid
    LOOP
        IF NOT EXISTS (SELECT 1 FROM productionrecords pr WHERE pr.id = v_line.productionrecordid AND pr.farmid = p_farmid) THEN
            -- The record was deleted since: its delete already gave the stock
            -- back (the engine's pure reversal). Nothing left to undo here.
            UPDATE poultryfeeddistributionlines l
            SET reversalnote = 'Production record was deleted after posting; its stock had already been returned.'
            WHERE l.poultryfeeddistributionlineid = v_line.poultryfeeddistributionlineid;
            CONTINUE;
        END IF;

        PERFORM public.fnpoultryfeeddist_changerecordfeed(
            p_farmid, v_line.productionrecordid, v_doc.poultryrawmaterialitemid, -v_line.actualkg, p_reversedby,
            CASE WHEN v_line.hadstocklinesbefore THEN NULL ELSE v_line.feedkgbefore END);
    END LOOP;

    UPDATE poultryfeeddistributions d
    SET status = 'Reversed', reversedby = p_reversedby, reversedatutc = now(), reversalreason = btrim(p_reason)
    WHERE d.poultryfeeddistributionid = p_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 8. Readers.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryfeeddistribution_getall(text, date, date);
CREATE FUNCTION public.sppoultryfeeddistribution_getall(p_farmid text, p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL)
RETURNS SETOF public.poultryfeeddistributions
LANGUAGE sql
STABLE
AS $function$
    SELECT * FROM poultryfeeddistributions d
    WHERE d.farmid = p_farmid
      AND (p_fromdate IS NULL OR d.businessdate >= p_fromdate)
      AND (p_todate IS NULL OR d.businessdate <= p_todate)
    ORDER BY d.businessdate DESC, d.poultryfeeddistributionid DESC;
$function$;

DROP FUNCTION IF EXISTS public.sppoultryfeeddistribution_lines(integer, text);
CREATE FUNCTION public.sppoultryfeeddistribution_lines(p_id integer, p_farmid text)
RETURNS SETOF public.poultryfeeddistributionlines
LANGUAGE sql
STABLE
AS $function$
    SELECT * FROM poultryfeeddistributionlines l
    WHERE l.poultryfeeddistributionid = p_id AND l.farmid = p_farmid
    ORDER BY l.poultryfeeddistributionlineid;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification. Every fixture is rolled back by the sentinel at the end.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    a   text := '44444444-3333-4333-8333-000000000335';   -- uuid-shaped: expense.farmid is uuid
    b   text := '55555555-3333-4333-8333-000000000335';
    d   date := date '2026-03-10';
    v_created timestamp := timestamp '2026-01-01 08:00';
    who text := '__335__';
    it  integer; it2 integer; itb integer;
    lot1 integer; lot2 integer; lot3 integer; lot4 integer; lotd integer;
    f1 integer; f2 integer; f3 integer; f4 integer; f5 integer; f6 integer; f7 integer; fb integer;
    r1 integer; r2 integer; r4 integer; r5 integer; r6 integer; r7a integer; r7b integer;
    dist1 integer; dist2 integer; dist3 integer; v_n numeric; v_c numeric;
    rr record;
BEGIN
    BEGIN
        INSERT INTO farms (id, farmid, name, email, type, timezoneid)
        VALUES (a, a, 'Selftest A', 'a@selftest.invalid', 'Poultry', 'UTC'),
               (b, b, 'Selftest B', 'b@selftest.invalid', 'Poultry', 'UTC');

        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive, usagemethod)
        VALUES (a, 'Layer Mash', 'FinishedFeed', 'kg', 200, TRUE, 'FIFO') RETURNING poultryrawmaterialitemid INTO it;
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive, usagemethod)
        VALUES (a, 'Grower Mash', 'FinishedFeed', 'kg', 100, TRUE, 'FIFO') RETURNING poultryrawmaterialitemid INTO it2;
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive, usagemethod)
        VALUES (b, 'B Mash', 'FinishedFeed', 'kg', 100, TRUE, 'FIFO') RETURNING poultryrawmaterialitemid INTO itb;

        -- Layer Mash: two lots, expensed at purchase (no deferred cost).
        INSERT INTO poultryrawmaterialpurchases (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
            productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod, deferredtotalcost, deferredremainingcost)
        VALUES (a, it, d - 10, 100, 2, 200, 1, 100, 'EXPENSE_WHEN_PURCHASED', 0, 0) RETURNING poultryrawmaterialpurchaseid INTO lot1;
        INSERT INTO poultryrawmaterialpurchases (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
            productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod, deferredtotalcost, deferredremainingcost)
        VALUES (a, it, d - 5, 100, 3, 300, 1, 100, 'EXPENSE_WHEN_PURCHASED', 0, 0) RETURNING poultryrawmaterialpurchaseid INTO lot2;
        -- Grower Mash: one lot expensed at CONSUMPTION (cost deferred).
        INSERT INTO poultryrawmaterialpurchases (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
            productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod, deferredtotalcost, deferredremainingcost)
        VALUES (a, it2, d - 5, 100, 4, 400, 1, 100, 'EXPENSE_WHEN_CONSUMED', 400, 400) RETURNING poultryrawmaterialpurchaseid INTO lotd;
        INSERT INTO poultryrawmaterialpurchases (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
            productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod, deferredtotalcost, deferredremainingcost)
        VALUES (b, itb, d - 5, 100, 1, 100, 1, 100, 'EXPENSE_WHEN_PURCHASED', 0, 0);

        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'F1', d - 30, 'Brown', 1000, TRUE, TRUE, -335, v_created) RETURNING flockid INTO f1;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'F2', d - 30, 'Brown', 1840, TRUE, TRUE, -335, v_created) RETURNING flockid INTO f2;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'F3 no record', d - 30, 'Brown', 500, TRUE, TRUE, -335, v_created) RETURNING flockid INTO f3;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'F4', d - 30, 'Brown', 100, TRUE, TRUE, -335, v_created) RETURNING flockid INTO f4;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'F5', d - 30, 'Brown', 100, TRUE, TRUE, -335, v_created) RETURNING flockid INTO f5;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'F6', d - 30, 'Brown', 100, TRUE, TRUE, -335, v_created) RETURNING flockid INTO f6;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'F7 duplicate', d - 30, 'Brown', 100, TRUE, TRUE, -335, v_created) RETURNING flockid INTO f7;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, b, 'B1', d - 30, 'Brown', 100, TRUE, TRUE, -335, v_created) RETURNING flockid INTO fb;

        -- Day records. F1 has a MANUAL feed kg (no stock lines); F7 has two records.
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (a, who, who, 10, 70, d, 1000, 0, 1000, 50, 1, 1, 1, 3, f1, 'ManualSingleFlock', now()) RETURNING id INTO r1;
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (a, who, who, 10, 70, d, 1840, 2, 1838, 0, 1, 1, 1, 3, f2, 'ManualSingleFlock', now()) RETURNING id INTO r2;
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (a, who, who, 10, 70, d, 100, 0, 100, 0, 1, 1, 1, 3, f4, 'ManualSingleFlock', now()) RETURNING id INTO r4;
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (a, who, who, 10, 70, d, 100, 0, 100, 0, 1, 1, 1, 3, f5, 'ManualSingleFlock', now()) RETURNING id INTO r5;
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (a, who, who, 10, 70, d, 100, 0, 100, 0, 1, 1, 1, 3, f6, 'ManualSingleFlock', now()) RETURNING id INTO r6;
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (a, who, who, 10, 70, d, 100, 0, 100, 0, 1, 1, 1, 3, f7, 'ManualSingleFlock', now()),
               (a, who, who, 10, 70, d, 100, 0, 100, 0, 1, 1, 1, 3, f7, 'ManualSingleFlock', now());
        -- History for the recent average: F2 got Layer Mash on d-1 (10) and d-3 (20).
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (a, who, who, 10, 70, d - 1, 1840, 0, 1840, 10, 1, 1, 1, 3, f2, 'ManualSingleFlock', now()) RETURNING id INTO r7a;
        INSERT INTO productionrecords (farmid, userid, createdby, ageinweeks, ageindays, date, noofbirds, mortality,
            noofbirdsleft, feedkg, production9am, production12pm, production4pm, totalproduction, flockid, sourcetype, createdat)
        VALUES (a, who, who, 10, 70, d - 3, 1840, 0, 1840, 20, 1, 1, 1, 3, f2, 'ManualSingleFlock', now()) RETURNING id INTO r7b;
        INSERT INTO productionrecordfeeds (farmid, productionrecordid, poultryrawmaterialitemid, itemname, quantityconsumed, unitcost, totalcost)
        VALUES (a, r7a, it, 'Layer Mash', 10, 2, 20), (a, r7b, it, 'Layer Mash', 20, 2, 40);

        -- ---- Grid ------------------------------------------------------------
        SELECT * INTO rr FROM public.sppoultryfeeddistribution_candidates(a, d, it) c WHERE c.flockid = f2;
        IF rr.recordcount <> 1 OR rr.productionrecordid <> r2 OR rr.birds <> 1840
           OR rr.recentavgkg <> 15 OR rr.recentavgdays <> 2 THEN
            RAISE EXCEPTION '335: F2 grid row wrong (recent average = (10+20)/2 days): %', rr;
        END IF;
        SELECT * INTO rr FROM public.sppoultryfeeddistribution_candidates(a, d, it) c WHERE c.flockid = f1;
        IF rr.manualfeedkg <> 50 OR rr.recentavgkg IS NOT NULL THEN
            RAISE EXCEPTION '335: F1 should show its manual 50 kg and NO recent average (no history): %', rr;
        END IF;
        IF (SELECT c.recordcount FROM public.sppoultryfeeddistribution_candidates(a, d, it) c WHERE c.flockid = f3) <> 0
           OR (SELECT c.recordcount FROM public.sppoultryfeeddistribution_candidates(a, d, it) c WHERE c.flockid = f7) <> 2 THEN
            RAISE EXCEPTION '335: record counts for F3 / F7 wrong.';
        END IF;
        IF EXISTS (SELECT 1 FROM public.sppoultryfeeddistribution_candidates(a, d, it) c WHERE c.flockid = fb) THEN
            RAISE EXCEPTION '335: another company''s flock is in the grid.';
        END IF;
        IF (SELECT x.availablekg FROM public.sppoultryfeeddistribution_availability(a, it) x) <> 200 THEN
            RAISE EXCEPTION '335: availability should be the lots'' 200 kg.';
        END IF;

        -- ---- One flock -------------------------------------------------------
        dist1 := public.sppoultryfeeddistribution_post(a, d, it, 'Manual', NULL, NULL,
            json_build_array(json_build_object('flockId', f2, 'actualKg', 30))::text, who);
        SELECT * INTO rr FROM productionrecordfeeds f WHERE f.productionrecordid = r2;
        IF rr.quantityconsumed <> 30 OR rr.unitcost <> 2 THEN
            RAISE EXCEPTION '335: F2 should have one 30 kg line at the FIFO cost 2: %', rr;
        END IF;
        IF (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = lot1) <> 70
           OR (SELECT currentquantity FROM poultryrawmaterialitems WHERE poultryrawmaterialitemid = it) <> 170
           OR (SELECT feedkg FROM productionrecords WHERE id = r2) <> 30
           OR (SELECT totalfeedcost FROM productionrecords WHERE id = r2) <> 60 THEN
            RAISE EXCEPTION '335: one-flock stock / record figures wrong.';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM feedusage fu WHERE fu.sourceproductionrecordid = r2 AND fu.quantitykg = 30) THEN
            RAISE EXCEPTION '335: the feedusage row was not kept in step by the trigger.';
        END IF;
        -- Purchase-based recognition: no consumption expense.
        IF EXISTS (SELECT 1 FROM expense e WHERE e.sourcetype = 'PoultryFeedConsumption' AND e.sourceid = r2) THEN
            RAISE EXCEPTION '335: feed expensed at purchase must not be expensed again at consumption.';
        END IF;

        -- ---- Many flocks; F1's manual 50 kg is replaced by its stock line ----
        dist2 := public.sppoultryfeeddistribution_post(a, d, it, 'Rate', 20, 'morning feed',
            json_build_array(json_build_object('flockId', f1, 'actualKg', 20, 'suggestedKg', 20),
                             json_build_object('flockId', f2, 'actualKg', 45.5, 'suggestedKg', 36.8))::text, who);
        -- Stock decreased exactly once: 200 - 30 - 20 - 45.5.
        SELECT sum(remainingquantity) INTO v_n FROM poultryrawmaterialpurchases WHERE poultryrawmaterialitemid = it;
        IF v_n <> 104.5 OR (SELECT currentquantity FROM poultryrawmaterialitems WHERE poultryrawmaterialitemid = it) <> 104.5 THEN
            RAISE EXCEPTION '335: stock should be 104.5 after three draws, lots %.', v_n;
        END IF;
        SELECT sum(quantityused) INTO v_n FROM poultryrawmaterialusage
        WHERE poultryrawmaterialitemid = it AND isreversed = FALSE AND productionrecordid IN (r1, r2);
        IF v_n <> 95.5 THEN
            RAISE EXCEPTION '335: live usage should be 95.5, got %.', v_n;
        END IF;
        IF (SELECT feedkg FROM productionrecords WHERE id = r1) <> 20
           OR (SELECT count(*) FROM productionrecordfeeds WHERE productionrecordid = r2) <> 2
           OR (SELECT feedkg FROM productionrecords WHERE id = r2) <> 75.5 THEN
            RAISE EXCEPTION '335: record feed lines / kg wrong after the second distribution.';
        END IF;
        IF (SELECT flockcount FROM poultryfeeddistributions WHERE poultryfeeddistributionid = dist2) <> 2
           OR (SELECT totalactualkg FROM poultryfeeddistributions WHERE poultryfeeddistributionid = dist2) <> 65.5 THEN
            RAISE EXCEPTION '335: distribution header totals wrong.';
        END IF;

        -- ---- Insufficient stock: refused, nothing moves ----------------------
        BEGIN
            PERFORM public.sppoultryfeeddistribution_post(a, d, it, 'Manual', NULL, NULL,
                json_build_array(json_build_object('flockId', f4, 'actualKg', 60),
                                 json_build_object('flockId', f5, 'actualKg', 60))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '335: distributed more than the lots hold.';
        EXCEPTION WHEN SQLSTATE 'P0003' THEN NULL;
        END;
        IF (SELECT count(*) FROM productionrecordfeeds WHERE productionrecordid IN (r4, r5)) <> 0 THEN
            RAISE EXCEPTION '335: a refused distribution moved stock.';
        END IF;

        -- ---- No record / duplicate records / other company: refused, atomic --
        BEGIN
            PERFORM public.sppoultryfeeddistribution_post(a, d, it, 'Manual', NULL, NULL,
                json_build_array(json_build_object('flockId', f4, 'actualKg', 5),
                                 json_build_object('flockId', f3, 'actualKg', 5))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '335: posted to a flock with no production record.';
        EXCEPTION WHEN SQLSTATE 'P0004' THEN NULL;
        END;
        BEGIN
            PERFORM public.sppoultryfeeddistribution_post(a, d, it, 'Manual', NULL, NULL,
                json_build_array(json_build_object('flockId', f7, 'actualKg', 5))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '335: posted to a flock with two records.';
        EXCEPTION WHEN SQLSTATE 'P0004' THEN NULL;
        END;
        BEGIN
            PERFORM public.sppoultryfeeddistribution_post(a, d, it, 'Manual', NULL, NULL,
                json_build_array(json_build_object('flockId', fb, 'actualKg', 5))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '335: posted to another company''s flock.';
        EXCEPTION WHEN SQLSTATE 'P0004' THEN NULL;
        END;
        BEGIN
            PERFORM public.sppoultryfeeddistribution_post(a, d, itb, 'Manual', NULL, NULL,
                json_build_array(json_build_object('flockId', f4, 'actualKg', 5))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '335: used another company''s feed.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        IF (SELECT count(*) FROM productionrecordfeeds WHERE productionrecordid = r4) <> 0 THEN
            RAISE EXCEPTION '335: a refused distribution changed F4.';
        END IF;

        -- ---- FIFO / LIFO / HIFO come from the item, through the engine -------
        INSERT INTO poultryrawmaterialpurchases (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
            productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod, deferredtotalcost, deferredremainingcost)
        VALUES (a, it, d - 1, 50, 5, 250, 1, 50, 'EXPENSE_WHEN_PURCHASED', 0, 0) RETURNING poultryrawmaterialpurchaseid INTO lot3;
        INSERT INTO poultryrawmaterialpurchases (farmid, poultryrawmaterialitemid, purchasedate, quantity, unitcost, totalcost,
            productionunitsperpurchaseunit, remainingquantity, costrecognitionmethod, deferredtotalcost, deferredremainingcost)
        VALUES (a, it, d - 2, 50, 9, 450, 1, 50, 'EXPENSE_WHEN_PURCHASED', 0, 0) RETURNING poultryrawmaterialpurchaseid INTO lot4;
        UPDATE poultryrawmaterialitems SET currentquantity = currentquantity + 100 WHERE poultryrawmaterialitemid = it;
        -- lot1 (cost 2, oldest) still has 4.5 kg; lot3 (cost 5) is newest; lot4 (cost 9)
        -- is dearest. One kg each way picks exactly one of them.
        PERFORM public.sppoultryfeeddistribution_post(a, d, it, 'Manual', NULL, NULL,
            json_build_array(json_build_object('flockId', f4, 'actualKg', 1))::text, who);
        UPDATE poultryrawmaterialitems SET usagemethod = 'LIFO' WHERE poultryrawmaterialitemid = it;
        PERFORM public.sppoultryfeeddistribution_post(a, d, it, 'Manual', NULL, NULL,
            json_build_array(json_build_object('flockId', f5, 'actualKg', 1))::text, who);
        UPDATE poultryrawmaterialitems SET usagemethod = 'HIFO' WHERE poultryrawmaterialitemid = it;
        PERFORM public.sppoultryfeeddistribution_post(a, d, it, 'Manual', NULL, NULL,
            json_build_array(json_build_object('flockId', f6, 'actualKg', 1))::text, who);
        IF (SELECT unitcost FROM productionrecordfeeds WHERE productionrecordid = r4) <> 2
           OR (SELECT unitcost FROM productionrecordfeeds WHERE productionrecordid = r5) <> 5
           OR (SELECT unitcost FROM productionrecordfeeds WHERE productionrecordid = r6) <> 9 THEN
            RAISE EXCEPTION '335: FIFO/LIFO/HIFO costs wrong: % % %',
                (SELECT unitcost FROM productionrecordfeeds WHERE productionrecordid = r4),
                (SELECT unitcost FROM productionrecordfeeds WHERE productionrecordid = r5),
                (SELECT unitcost FROM productionrecordfeeds WHERE productionrecordid = r6);
        END IF;
        UPDATE poultryrawmaterialitems SET usagemethod = 'FIFO' WHERE poultryrawmaterialitemid = it;

        -- ---- Consumption-based recognition: a NonCash expense, and back -----
        dist3 := public.sppoultryfeeddistribution_post(a, d, it2, 'Manual', NULL, NULL,
            json_build_array(json_build_object('flockId', f4, 'actualKg', 25))::text, who);
        SELECT COALESCE(sum(e.amount), 0) INTO v_c FROM expense e
        WHERE e.sourcetype = 'PoultryFeedConsumption' AND e.sourceid = r4 AND e.paymentmethod = 'NonCash';
        IF v_c <> 100 THEN
            RAISE EXCEPTION '335: 25 kg of deferred feed at 4 should recognise 100, got %.', v_c;
        END IF;
        IF (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = lotd) <> 300 THEN
            RAISE EXCEPTION '335: the lot''s deferred cost should drop to 300.';
        END IF;

        -- ---- Reversal -------------------------------------------------------
        BEGIN
            PERFORM public.sppoultryfeeddistribution_reverse(dist3, a, '  ', who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '335: reversed without a reason.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        BEGIN
            PERFORM public.sppoultryfeeddistribution_reverse(dist3, b, 'not mine', who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '335: another company reversed it.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        PERFORM public.sppoultryfeeddistribution_reverse(dist3, a, 'Wrong feed', who);
        SELECT COALESCE(sum(e.amount), 0) INTO v_c FROM expense e
        WHERE e.sourcetype = 'PoultryFeedConsumption' AND e.sourceid = r4;
        IF v_c <> 0 OR (SELECT count(*) FROM expense e WHERE e.sourcetype = 'PoultryFeedConsumption' AND e.sourceid = r4) < 2 THEN
            RAISE EXCEPTION '335: the consumption expense should net to 0 through an opposite row (net %).', v_c;
        END IF;
        IF (SELECT remainingquantity FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = lotd) <> 100
           OR (SELECT deferredremainingcost FROM poultryrawmaterialpurchases WHERE poultryrawmaterialpurchaseid = lotd) <> 400
           OR EXISTS (SELECT 1 FROM productionrecordfeeds WHERE productionrecordid = r4 AND poultryrawmaterialitemid = it2) THEN
            RAISE EXCEPTION '335: reversal did not restore the lot / remove the line.';
        END IF;
        IF (SELECT status FROM poultryfeeddistributions WHERE poultryfeeddistributionid = dist3) <> 'Reversed' THEN
            RAISE EXCEPTION '335: distribution not marked Reversed.';
        END IF;
        BEGIN
            PERFORM public.sppoultryfeeddistribution_reverse(dist3, a, 'again', who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '335: reversed twice.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- Reversing dist2 gives F1 its manual 50 kg back and leaves F2's first line.
        PERFORM public.sppoultryfeeddistribution_reverse(dist2, a, 'Double entry', who);
        IF (SELECT feedkg FROM productionrecords WHERE id = r1) <> 50
           OR EXISTS (SELECT 1 FROM productionrecordfeeds WHERE productionrecordid = r1)
           OR (SELECT sum(quantityconsumed) FROM productionrecordfeeds WHERE productionrecordid = r2) <> 30 THEN
            RAISE EXCEPTION '335: reversing dist2 left the records wrong.';
        END IF;

        -- ---- Append-only documents -------------------------------------------
        BEGIN
            DELETE FROM poultryfeeddistributions WHERE poultryfeeddistributionid = dist1;
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '335: a distribution could be deleted.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- ---- Revalidated at post time (the concurrency guard's check) --------
        SELECT x.availablekg INTO v_n FROM public.sppoultryfeeddistribution_availability(a, it) x;
        BEGIN
            PERFORM public.sppoultryfeeddistribution_post(a, d, it, 'Manual', NULL, NULL,
                json_build_array(json_build_object('flockId', f5, 'actualKg', v_n + 1))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '335: posted past what the lots hold now.';
        EXCEPTION WHEN SQLSTATE 'P0003' THEN NULL;
        END;

        -- ---- Feed rate ------------------------------------------------------
        PERFORM public.sppoultryfeedrate_set(a, it, 112.5, who);
        IF (SELECT x.gramsperbirdperday FROM public.sppoultryfeeddistribution_availability(a, it) x) <> 112.5 THEN
            RAISE EXCEPTION '335: feed rate not saved.';
        END IF;
        BEGIN
            PERFORM public.sppoultryfeedrate_set(a, itb, 100, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '335: set a rate on another company''s feed.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- ---- Future date refused --------------------------------------------
        BEGIN
            PERFORM public.sppoultryfeeddistribution_post(a, current_date + 5, it, 'Manual', NULL, NULL,
                json_build_array(json_build_object('flockId', f5, 'actualKg', 1))::text, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '335: distributed feed for a future date.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '__335_ok__';
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
        NULL;
    END;

    RAISE NOTICE '335_PoultryFeedDistribution: verified (one flock, many flocks, stock once, manual kg, insufficient stock, no record, duplicate, isolation, FIFO/LIFO/HIFO, consumption & purchase recognition, reversal, append-only, revalidation, feed rate, future date).';
END $$;
