-- =============================================================================
-- 342_PoultryEggSorting.postgres.sql          (requires 341)
--
-- Purpose
-- -------
-- The Egg Sorting Workspace engine: turn Unsorted egg stock into sized stock,
-- either one pick at a time ("sort after each pick") or as a pool ("collect
-- everything, sort later"), in as many sessions as the farm likes, on the
-- production day or any later day.
--
-- WHAT A SORTING IS
-- =================
-- An inventory TRANSFORMATION. It creates no eggs:
--
--     Unsorted   -input          ('Sorting Out')
--     each size  +its quantity   ('Sorting In')
--     loss       recorded on the session, never stocked
--
--     input = sized outputs + losses        (enforced: input IS that sum)
--
-- The user never retypes production. They enter only what they sorted and how
-- it graded; the input is the sum of those lines, and what is still waiting is
-- read from the production record.
--
-- PICKS STAY ON THE PRODUCTION RECORD
-- ===================================
-- productionrecords.production9am .. production6thpick remain the one truth for
-- what each pick collected (no EggCollectionPick copy to drift from it). A
-- session's SOURCES say which record and pick each sorted egg came from:
--
--     poultryeggsortingsources (sessionid, productionrecordid, picknumber, qty)
--
-- What is left to sort:
--     pick   : gross pick - posted sources for that pick
--     record : saleable - posted sources for the record, where saleable is the
--              figure production already posted to stock (total - broken -
--              meaty - soft - lost, floored at 0; migration 198's rule)
--     available for a pick = LEAST(pick left, record left)
-- Broken/meaty/soft/lost are recorded per DAY, not per pick, so they are not
-- spread across picks by guesswork: a pick can be sorted up to its count, the
-- day up to its saleable eggs.
--
-- MODES
-- =====
--   ByPick    one record, one pick. Composition by pick comes ONLY from these.
--   Combined  one flock, one or more of its records; the input is allocated to
--             picks FIFO (production date, then pick number). The allocation
--             is kept for traceability and availability, but reports never
--             present a Combined session's sizes as a pick's composition.
--
-- LIFECYCLE
-- =========
--   Draft     editable, moves no stock, can be discarded.
--   Posted    the ledger rows exist. Re-posting is a no-op (double-click safe).
--   Reversed  opposite 'Sorting Reversal' rows restore Unsorted and remove the
--             sized eggs. Refused while any size it created has since been
--             sold or used (on hand < what the reversal would remove):
--             reverse those first. Nothing is ever deleted once posted.
--
-- CONCURRENCY: post and reverse take an advisory lock per farm and re-read
-- availability inside it, so two people sorting the same pick cannot sort more
-- than it holds. A production record with posted sorting cannot be deleted,
-- moved to another flock/day, or edited below what was already sorted from it.
--
-- Error codes: P0003 not enough eggs left to sort / unsorted stock,
--              P0006 reversal blocked by downstream use, P0001 anything else.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultryeggsortingsessions (
    sessionid           serial      PRIMARY KEY,
    farmid              text        NOT NULL,
    sessionno           text        NOT NULL,
    sortingmode         text        NOT NULL
        CONSTRAINT ck_poultryeggsorting_mode CHECK (sortingmode IN ('ByPick', 'Combined')),
    flockid             integer     NOT NULL,
    -- ByPick: the one record and pick. Combined: NULL.
    productionrecordid  integer,
    picknumber          smallint    CHECK (picknumber BETWEEN 1 AND 6),
    -- The records this session may draw from (ByPick: just its own).
    scoperecordids      integer[]   NOT NULL,
    sortingdate         date        NOT NULL,
    status              text        NOT NULL DEFAULT 'Draft'
        CONSTRAINT ck_poultryeggsorting_status CHECK (status IN ('Draft', 'Posted', 'Reversed')),
    inputquantity       integer     NOT NULL DEFAULT 0,
    outputquantity      integer     NOT NULL DEFAULT 0,
    lossquantity        integer     NOT NULL DEFAULT 0,
    notes               text,
    clientrequestid     uuid,
    createdby           text,
    createdatutc        timestamptz NOT NULL DEFAULT now(),
    updatedatutc        timestamptz,
    postedby            text,
    postedatutc         timestamptz,
    reversedby          text,
    reversedatutc       timestamptz,
    reversalreason      text,
    CONSTRAINT ck_poultryeggsorting_bypick CHECK (
        sortingmode <> 'ByPick' OR (productionrecordid IS NOT NULL AND picknumber IS NOT NULL)),
    CONSTRAINT ck_poultryeggsorting_balance CHECK (inputquantity = outputquantity + lossquantity)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_poultryeggsorting_no ON public.poultryeggsortingsessions (farmid, sessionno);
CREATE UNIQUE INDEX IF NOT EXISTS uq_poultryeggsorting_request ON public.poultryeggsortingsessions (farmid, clientrequestid)
    WHERE clientrequestid IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_poultryeggsorting_farm_date ON public.poultryeggsortingsessions (farmid, sortingdate DESC);

CREATE TABLE IF NOT EXISTS public.poultryeggsortinglines (
    lineid      serial   PRIMARY KEY,
    sessionid   integer  NOT NULL REFERENCES public.poultryeggsortingsessions (sessionid),
    farmid      text     NOT NULL,
    linetype    text     NOT NULL
        CONSTRAINT ck_poultryeggsortingline_type CHECK (linetype IN ('SizedOutput', 'Reject', 'Breakage', 'OtherLoss')),
    eggsizeid   integer  REFERENCES public.poultryeggsizes (eggsizeid),
    quantity    integer  NOT NULL CHECK (quantity > 0),
    notes       text,
    CONSTRAINT ck_poultryeggsortingline_size CHECK ((linetype = 'SizedOutput') = (eggsizeid IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS ix_poultryeggsortingline_session ON public.poultryeggsortinglines (sessionid);

CREATE TABLE IF NOT EXISTS public.poultryeggsortingsources (
    sourceid            serial   PRIMARY KEY,
    sessionid           integer  NOT NULL REFERENCES public.poultryeggsortingsessions (sessionid),
    farmid              text     NOT NULL,
    productionrecordid  integer  NOT NULL,
    picknumber          smallint NOT NULL CHECK (picknumber BETWEEN 1 AND 6),
    flockid             integer  NOT NULL,
    productiondate      date     NOT NULL,
    quantity            integer  NOT NULL CHECK (quantity > 0)
);
CREATE INDEX IF NOT EXISTS ix_poultryeggsortingsrc_record ON public.poultryeggsortingsources (productionrecordid, picknumber);
CREATE INDEX IF NOT EXISTS ix_poultryeggsortingsrc_session ON public.poultryeggsortingsources (sessionid);

-- Only a draft can be discarded; posted history is permanent.
CREATE OR REPLACE FUNCTION public.trg_poultryeggsorting_guard()
RETURNS trigger LANGUAGE plpgsql AS $function$
DECLARE
    v_status text;
BEGIN
    IF TG_TABLE_NAME = 'poultryeggsortingsessions' THEN
        IF OLD.status <> 'Draft' THEN
            RAISE EXCEPTION 'A % sorting cannot be deleted. Reverse it instead, so the stock history survives.', lower(OLD.status);
        END IF;
        RETURN OLD;
    END IF;
    IF TG_TABLE_NAME = 'poultryeggsortingsources' THEN
        RAISE EXCEPTION 'Sorting sources are permanent history.';
    END IF;
    -- lines: only while the session is a draft
    SELECT s.status INTO v_status FROM poultryeggsortingsessions s
    WHERE  s.sessionid = CASE WHEN TG_OP = 'INSERT' THEN NEW.sessionid ELSE OLD.sessionid END;
    IF v_status IS DISTINCT FROM 'Draft' THEN
        RAISE EXCEPTION 'The lines of a % sorting cannot be changed.', lower(COALESCE(v_status, 'missing'));
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_poultryeggsorting_nodelete ON public.poultryeggsortingsessions;
CREATE TRIGGER trg_poultryeggsorting_nodelete BEFORE DELETE ON public.poultryeggsortingsessions
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryeggsorting_guard();
DROP TRIGGER IF EXISTS trg_poultryeggsortingsrc_nodelete ON public.poultryeggsortingsources;
CREATE TRIGGER trg_poultryeggsortingsrc_nodelete BEFORE DELETE OR UPDATE ON public.poultryeggsortingsources
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryeggsorting_guard();
DROP TRIGGER IF EXISTS trg_poultryeggsortingline_guard ON public.poultryeggsortinglines;
CREATE TRIGGER trg_poultryeggsortingline_guard BEFORE INSERT OR UPDATE OR DELETE ON public.poultryeggsortinglines
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryeggsorting_guard();

-- -----------------------------------------------------------------------------
-- 2. What is left to sort, per record and pick
-- -----------------------------------------------------------------------------
-- One row per pick that collected eggs. Record-level figures repeat on each
-- of the record's rows. Only POSTED sessions count as sorted.
CREATE OR REPLACE FUNCTION public.sppoultryeggsorting_picks(
    p_farmid text, p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL,
    p_flockid integer DEFAULT NULL, p_recordids integer[] DEFAULT NULL)
RETURNS TABLE (productionrecordid integer, flockid integer, flockname text, batchname text, housename text,
               productiondate date, picknumber integer, pickgross integer, picksorted integer, pickleft integer,
               available integer, recordgross integer, recordcollectionloss integer, recordsaleable integer,
               recordsorted integer, recordleft integer, bypicksorted integer)
LANGUAGE sql
STABLE
AS $function$
    WITH rec AS (
        SELECT pr.id, pr.flockid, pr.date,
               COALESCE(pr.totalproduction, 0) AS gross,
               COALESCE(pr.brokeneggs, 0) + COALESCE(pr.meatyeggs, 0) + COALESCE(pr.softeggs, 0) + COALESCE(pr.losteggs, 0) AS loss,
               GREATEST(COALESCE(pr.totalproduction, 0) - COALESCE(pr.brokeneggs, 0) - COALESCE(pr.meatyeggs, 0)
                        - COALESCE(pr.softeggs, 0) - COALESCE(pr.losteggs, 0), 0) AS saleable,
               ARRAY[COALESCE(pr.production9am, 0), COALESCE(pr.production12pm, 0), COALESCE(pr.production4pm, 0),
                     COALESCE(pr.production4thpick, 0), COALESCE(pr.production5thpick, 0), COALESCE(pr.production6thpick, 0)] AS picks
        FROM   productionrecords pr
        WHERE  pr.farmid = p_farmid AND pr.flockid IS NOT NULL
          AND  (p_fromdate IS NULL OR pr.date >= p_fromdate)
          AND  (p_todate   IS NULL OR pr.date <= p_todate)
          AND  (p_flockid  IS NULL OR pr.flockid = p_flockid)
          AND  (p_recordids IS NULL OR pr.id = ANY (p_recordids))
    ),
    done AS (
        SELECT src.productionrecordid, src.picknumber,
               SUM(src.quantity)::int AS qty,
               SUM(CASE WHEN s.sortingmode = 'ByPick' THEN src.quantity ELSE 0 END)::int AS bypick
        FROM   poultryeggsortingsources src
        JOIN   poultryeggsortingsessions s ON s.sessionid = src.sessionid
        WHERE  src.farmid = p_farmid AND s.status = 'Posted'
          AND  src.productionrecordid IN (SELECT id FROM rec)
        GROUP  BY src.productionrecordid, src.picknumber
    ),
    recdone AS (
        SELECT d.productionrecordid, SUM(d.qty)::int AS qty FROM done d GROUP BY d.productionrecordid
    )
    SELECT r.id, r.flockid, f.name::text, b.batchname::text, h.housename::text, r.date,
           p.n::int, p.gross,
           COALESCE(d.qty, 0),
           GREATEST(p.gross - COALESCE(d.qty, 0), 0),
           GREATEST(LEAST(p.gross - COALESCE(d.qty, 0), r.saleable - COALESCE(rd.qty, 0)), 0),
           r.gross, r.loss, r.saleable,
           COALESCE(rd.qty, 0),
           GREATEST(r.saleable - COALESCE(rd.qty, 0), 0),
           COALESCE(d.bypick, 0)
    FROM   rec r
    CROSS  JOIN LATERAL unnest(r.picks) WITH ORDINALITY AS p(gross, n)
    LEFT   JOIN done d     ON d.productionrecordid = r.id AND d.picknumber = p.n
    LEFT   JOIN recdone rd ON rd.productionrecordid = r.id
    LEFT   JOIN flock f    ON f.flockid = r.flockid
    LEFT   JOIN mainflockbatch b ON b.batchid = f.batchid AND b.farmid = f.farmid
    LEFT   JOIN houses h   ON h.houseid = f.houseid AND h.farmid = f.farmid
    WHERE  p.gross > 0 OR COALESCE(d.qty, 0) > 0
    ORDER  BY r.date DESC, f.name, r.id, p.n;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Draft: create or replace
-- -----------------------------------------------------------------------------
-- p_linesjson: [{"lineType":"SizedOutput","eggSizeId":3,"quantity":260,"notes":null}, ...]
-- ByPick: p_recordids = {record}, p_picknumber set. Combined: the flock's records.
CREATE OR REPLACE FUNCTION public.sppoultryeggsorting_save(
    p_farmid text, p_sessionid integer, p_mode text, p_sortingdate date,
    p_recordids integer[], p_picknumber integer, p_linesjson text,
    p_notes text DEFAULT NULL, p_clientrequestid uuid DEFAULT NULL, p_by text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id      integer;
    v_status  text;
    v_flocks  integer;
    v_flock   integer;
    v_n       integer;
    v_first   date;
    v_out     integer;
    v_loss    integer;
    v_today   date := public.fncompany_businessdate(p_farmid);
    v_no      text;
    v_lines   jsonb := COALESCE(NULLIF(btrim(COALESCE(p_linesjson, '')), ''), '[]')::jsonb;
BEGIN
    -- A retried "create" (double-click, flaky network) returns the first one.
    IF p_sessionid IS NULL AND p_clientrequestid IS NOT NULL THEN
        SELECT s.sessionid INTO v_id FROM poultryeggsortingsessions s
        WHERE  s.farmid = p_farmid AND s.clientrequestid = p_clientrequestid;
        IF v_id IS NOT NULL THEN RETURN v_id; END IF;
    END IF;

    IF p_mode NOT IN ('ByPick', 'Combined') THEN
        RAISE EXCEPTION 'Choose how you are sorting: one pick, or all available eggs.';
    END IF;
    IF p_sortingdate IS NULL THEN
        RAISE EXCEPTION 'Enter the date the eggs were sorted.';
    END IF;
    IF p_sortingdate > v_today THEN
        RAISE EXCEPTION 'The sorting date cannot be in the future (today is %).', to_char(v_today, 'FMDD Mon YYYY');
    END IF;
    IF p_recordids IS NULL OR cardinality(p_recordids) = 0 THEN
        RAISE EXCEPTION 'Choose the production the eggs came from.';
    END IF;

    SELECT count(*), count(DISTINCT pr.flockid), min(pr.flockid), min(pr.date)
    INTO   v_n, v_flocks, v_flock, v_first
    FROM   productionrecords pr
    WHERE  pr.farmid = p_farmid AND pr.id = ANY (p_recordids) AND pr.flockid IS NOT NULL;

    IF v_n <> cardinality(ARRAY(SELECT DISTINCT unnest(p_recordids))) THEN
        RAISE EXCEPTION 'One or more of those production records do not belong to this company.';
    END IF;
    IF v_flocks <> 1 THEN
        RAISE EXCEPTION 'Sort one flock at a time, so each flock''s egg sizes stay its own.';
    END IF;
    IF p_sortingdate < v_first THEN
        RAISE EXCEPTION 'Eggs cannot be sorted before they were collected (%).', to_char(v_first, 'FMDD Mon YYYY');
    END IF;
    IF p_mode = 'ByPick' THEN
        IF v_n <> 1 OR p_picknumber IS NULL OR p_picknumber NOT BETWEEN 1 AND 6 THEN
            RAISE EXCEPTION 'Sorting a pick needs exactly one production record and the pick number.';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.sppoultryeggsorting_picks(p_farmid, NULL, NULL, NULL, p_recordids) x
                       WHERE x.picknumber = p_picknumber AND x.pickgross > 0) THEN
            RAISE EXCEPTION 'Pick % collected no eggs on that record.', p_picknumber;
        END IF;
    END IF;

    -- Lines: shape, sizes of this farm, whole positive eggs.
    IF jsonb_typeof(v_lines) <> 'array' THEN
        RAISE EXCEPTION 'The sorting lines could not be read.';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_lines) e
               WHERE COALESCE(e->>'lineType', '') NOT IN ('SizedOutput', 'Reject', 'Breakage', 'OtherLoss')) THEN
        RAISE EXCEPTION 'Each line must be a size or a loss (reject, breakage or other).';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_lines) e
               WHERE (e->>'quantity') IS NULL OR (e->>'quantity')::numeric <= 0
                  OR (e->>'quantity')::numeric <> trunc((e->>'quantity')::numeric)) THEN
        RAISE EXCEPTION 'Every quantity must be a whole number of eggs greater than 0.';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_lines) e
               WHERE e->>'lineType' = 'SizedOutput'
                 AND NOT EXISTS (SELECT 1 FROM poultryeggsizes s
                                 WHERE s.eggsizeid = (e->>'eggSizeId')::int AND s.farmid = p_farmid AND s.isactive)) THEN
        RAISE EXCEPTION 'One of the sizes is not an active egg size of this company.';
    END IF;
    SELECT COALESCE(SUM((e->>'quantity')::int) FILTER (WHERE e->>'lineType' = 'SizedOutput'), 0),
           COALESCE(SUM((e->>'quantity')::int) FILTER (WHERE e->>'lineType' <> 'SizedOutput'), 0)
    INTO   v_out, v_loss
    FROM   jsonb_array_elements(v_lines) e;

    IF p_sessionid IS NULL THEN
        -- Session numbers per farm, serialised so two saves cannot share one.
        PERFORM pg_advisory_xact_lock(hashtext('poultry-eggsort-no:' || p_farmid));
        SELECT 'SRT-' || lpad((COALESCE(max(NULLIF(regexp_replace(s.sessionno, '\D', '', 'g'), '')::int), 0) + 1)::text, 5, '0')
        INTO   v_no
        FROM   poultryeggsortingsessions s WHERE s.farmid = p_farmid;

        INSERT INTO poultryeggsortingsessions
            (farmid, sessionno, sortingmode, flockid, productionrecordid, picknumber, scoperecordids,
             sortingdate, status, inputquantity, outputquantity, lossquantity, notes, clientrequestid, createdby)
        VALUES
            (p_farmid, v_no, p_mode, v_flock,
             CASE WHEN p_mode = 'ByPick' THEN p_recordids[1] END,
             CASE WHEN p_mode = 'ByPick' THEN p_picknumber END,
             ARRAY(SELECT DISTINCT unnest(p_recordids) ORDER BY 1),
             p_sortingdate, 'Draft', v_out + v_loss, v_out, v_loss, NULLIF(btrim(COALESCE(p_notes, '')), ''),
             p_clientrequestid, p_by)
        RETURNING sessionid INTO v_id;
    ELSE
        SELECT s.status INTO v_status FROM poultryeggsortingsessions s
        WHERE  s.sessionid = p_sessionid AND s.farmid = p_farmid FOR UPDATE;
        IF v_status IS NULL THEN
            RAISE EXCEPTION 'Sorting % not found for this company.', p_sessionid;
        END IF;
        IF v_status <> 'Draft' THEN
            RAISE EXCEPTION 'Only a draft can be edited. This sorting is %.', lower(v_status);
        END IF;
        v_id := p_sessionid;
        DELETE FROM poultryeggsortinglines WHERE sessionid = v_id;
        UPDATE poultryeggsortingsessions s
        SET    sortingmode = p_mode, flockid = v_flock,
               productionrecordid = CASE WHEN p_mode = 'ByPick' THEN p_recordids[1] END,
               picknumber = CASE WHEN p_mode = 'ByPick' THEN p_picknumber END,
               scoperecordids = ARRAY(SELECT DISTINCT unnest(p_recordids) ORDER BY 1),
               sortingdate = p_sortingdate,
               inputquantity = v_out + v_loss, outputquantity = v_out, lossquantity = v_loss,
               notes = NULLIF(btrim(COALESCE(p_notes, '')), ''), updatedatutc = now()
        WHERE  s.sessionid = v_id;
    END IF;

    INSERT INTO poultryeggsortinglines (sessionid, farmid, linetype, eggsizeid, quantity, notes)
    SELECT v_id, p_farmid, e->>'lineType',
           CASE WHEN e->>'lineType' = 'SizedOutput' THEN (e->>'eggSizeId')::int END,
           (e->>'quantity')::int, NULLIF(btrim(COALESCE(e->>'notes', '')), '')
    FROM   jsonb_array_elements(v_lines) e;

    RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryeggsorting_discard(p_farmid text, p_sessionid integer)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_status text;
BEGIN
    SELECT s.status INTO v_status FROM poultryeggsortingsessions s
    WHERE  s.sessionid = p_sessionid AND s.farmid = p_farmid FOR UPDATE;
    IF v_status IS NULL THEN RETURN; END IF;
    IF v_status <> 'Draft' THEN
        RAISE EXCEPTION 'A % sorting cannot be discarded. Reverse it instead.', lower(v_status);
    END IF;
    DELETE FROM poultryeggsortinglines WHERE sessionid = p_sessionid;
    DELETE FROM poultryeggsortingsessions WHERE sessionid = p_sessionid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Post: the transformation, atomically
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryeggsorting_post(p_farmid text, p_sessionid integer, p_by text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    s          record;
    pk         record;
    v_input    integer;
    v_out      integer;
    v_loss     integer;
    v_avail    integer;
    v_need     integer;
    v_take     integer;
    v_rec      integer := NULL;
    v_recleft  integer := 0;
    v_unsorted integer;
    v_onhand   numeric;
    v_note     text;
    v_today    date := public.fncompany_businessdate(p_farmid);
    ln         record;
BEGIN
    -- One sorter at a time per farm: availability is re-read below, inside it.
    PERFORM pg_advisory_xact_lock(hashtext('poultry-eggsort:' || p_farmid));

    SELECT * INTO s FROM poultryeggsortingsessions x
    WHERE  x.sessionid = p_sessionid AND x.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sorting % not found for this company.', p_sessionid;
    END IF;
    IF s.status = 'Posted' THEN
        RETURN p_sessionid;                      -- already done: double-click safe
    END IF;
    IF s.status <> 'Draft' THEN
        RAISE EXCEPTION 'A % sorting cannot be posted. Start a new sorting instead.', lower(s.status);
    END IF;
    IF s.sortingdate > v_today THEN
        RAISE EXCEPTION 'The sorting date cannot be in the future.';
    END IF;

    SELECT COALESCE(SUM(quantity) FILTER (WHERE linetype = 'SizedOutput'), 0)::int,
           COALESCE(SUM(quantity) FILTER (WHERE linetype <> 'SizedOutput'), 0)::int
    INTO   v_out, v_loss
    FROM   poultryeggsortinglines WHERE sessionid = p_sessionid;
    v_input := v_out + v_loss;
    IF v_input <= 0 THEN
        RAISE EXCEPTION 'Enter how the eggs graded before posting.';
    END IF;
    IF EXISTS (SELECT 1 FROM poultryeggsortinglines l JOIN poultryeggsizes z ON z.eggsizeid = l.eggsizeid
               WHERE l.sessionid = p_sessionid AND (z.farmid <> p_farmid OR NOT z.isactive)) THEN
        RAISE EXCEPTION 'One of the sizes is no longer active. Edit the draft and choose another size.';
    END IF;

    -- ---- What is left, now --------------------------------------------------
    IF s.sortingmode = 'ByPick' THEN
        SELECT x.available INTO v_avail
        FROM   public.sppoultryeggsorting_picks(p_farmid, NULL, NULL, NULL, ARRAY[s.productionrecordid]) x
        WHERE  x.picknumber = s.picknumber;
        v_avail := COALESCE(v_avail, 0);
        IF v_input > v_avail THEN
            RAISE EXCEPTION 'Only % egg(s) of pick % are left to sort, but this sorting accounts for %. Someone may have sorted part of it already -- refresh and check.',
                v_avail, s.picknumber, v_input USING ERRCODE = 'P0003';
        END IF;
        INSERT INTO poultryeggsortingsources (sessionid, farmid, productionrecordid, picknumber, flockid, productiondate, quantity)
        SELECT p_sessionid, p_farmid, s.productionrecordid, s.picknumber, pr.flockid, pr.date, v_input
        FROM   productionrecords pr WHERE pr.id = s.productionrecordid;
    ELSE
        -- FIFO across the scope: oldest production first, then pick order.
        -- The record's own remaining saleable eggs cap what its picks give.
        v_need := v_input;
        FOR pk IN
            SELECT x.productionrecordid, x.picknumber, x.pickleft, x.recordleft, x.flockid, x.productiondate
            FROM   public.sppoultryeggsorting_picks(p_farmid, NULL, NULL, NULL, s.scoperecordids) x
            ORDER  BY x.productiondate, x.productionrecordid, x.picknumber
        LOOP
            EXIT WHEN v_need = 0;
            IF v_rec IS DISTINCT FROM pk.productionrecordid THEN
                v_rec := pk.productionrecordid;
                v_recleft := pk.recordleft;
            END IF;
            IF pk.productiondate > s.sortingdate THEN CONTINUE; END IF;
            v_take := LEAST(v_need, pk.pickleft, v_recleft);
            IF v_take > 0 THEN
                INSERT INTO poultryeggsortingsources (sessionid, farmid, productionrecordid, picknumber, flockid, productiondate, quantity)
                VALUES (p_sessionid, p_farmid, pk.productionrecordid, pk.picknumber, pk.flockid, pk.productiondate, v_take);
                v_need := v_need - v_take;
                v_recleft := v_recleft - v_take;
            END IF;
        END LOOP;
        IF v_need > 0 THEN
            RAISE EXCEPTION 'Only % egg(s) from this production are left to sort, but this sorting accounts for %. Someone may have sorted part of it already -- refresh and check.',
                v_input - v_need, v_input USING ERRCODE = 'P0003';
        END IF;
    END IF;

    -- ---- The ledger can actually give them ----------------------------------
    -- Unsorted eggs can also leave by an unsorted sale or internal use, so the
    -- production figure alone is not proof the eggs are still on the shelf.
    v_unsorted := public.fnpoultry_unsortedeggproduct(p_farmid);
    SELECT COALESCE(SUM(t.quantity), 0) INTO v_onhand
    FROM   poultrystocktransactions t WHERE t.farmid = p_farmid AND t.poultryproductid = v_unsorted;
    IF v_onhand < v_input THEN
        RAISE EXCEPTION 'Only % unsorted egg(s) are in stock, but this sorting needs %. Some were sold or used unsorted -- record fewer, or correct the stock first.',
            trunc(v_onhand), v_input USING ERRCODE = 'P0003';
    END IF;

    v_note := 'Egg sorting ' || s.sessionno;
    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby)
    VALUES (p_farmid, v_unsorted, 'Sorting Out', -v_input, NULL, p_sessionid, v_note, p_by);

    FOR ln IN
        SELECT z.poultryproductid, SUM(l.quantity)::int AS qty
        FROM   poultryeggsortinglines l JOIN poultryeggsizes z ON z.eggsizeid = l.eggsizeid
        WHERE  l.sessionid = p_sessionid AND l.linetype = 'SizedOutput'
        GROUP  BY z.poultryproductid
    LOOP
        INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby)
        VALUES (p_farmid, ln.poultryproductid, 'Sorting In', ln.qty, NULL, p_sessionid, v_note, p_by);
    END LOOP;

    UPDATE poultryeggsortingsessions x
    SET    status = 'Posted', inputquantity = v_input, outputquantity = v_out, lossquantity = v_loss,
           postedby = p_by, postedatutc = now(), updatedatutc = now()
    WHERE  x.sessionid = p_sessionid;

    RETURN p_sessionid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. Reverse
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryeggsorting_reverse(
    p_farmid text, p_sessionid integer, p_reason text, p_by text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    s         record;
    ln        record;
    v_onhand  numeric;
    v_short   text := '';
    v_note    text;
BEGIN
    IF btrim(COALESCE(p_reason, '')) = '' THEN
        RAISE EXCEPTION 'A reason is required to reverse a sorting.';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('poultry-eggsort:' || p_farmid));

    SELECT * INTO s FROM poultryeggsortingsessions x
    WHERE  x.sessionid = p_sessionid AND x.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sorting % not found for this company.', p_sessionid;
    END IF;
    IF s.status = 'Reversed' THEN RETURN; END IF;
    IF s.status <> 'Posted' THEN
        RAISE EXCEPTION 'Only a posted sorting can be reversed. A draft can simply be discarded.';
    END IF;

    -- Every sized egg it created must still be on the shelf.
    FOR ln IN
        SELECT z.poultryproductid, z.name, SUM(l.quantity)::int AS qty
        FROM   poultryeggsortinglines l JOIN poultryeggsizes z ON z.eggsizeid = l.eggsizeid
        WHERE  l.sessionid = p_sessionid AND l.linetype = 'SizedOutput'
        GROUP  BY z.poultryproductid, z.name
    LOOP
        SELECT COALESCE(SUM(t.quantity), 0) INTO v_onhand
        FROM   poultrystocktransactions t WHERE t.farmid = p_farmid AND t.poultryproductid = ln.poultryproductid;
        IF v_onhand < ln.qty THEN
            v_short := v_short || format('%s%s: %s sorted, only %s left', CASE WHEN v_short = '' THEN '' ELSE '; ' END,
                                         ln.name, ln.qty, trunc(GREATEST(v_onhand, 0)));
        END IF;
    END LOOP;
    IF v_short <> '' THEN
        RAISE EXCEPTION 'This sorting cannot be reversed because some of its eggs have already been sold or used (%). Reverse those sales or uses first, then reverse the sorting.',
            v_short USING ERRCODE = 'P0006';
    END IF;

    v_note := 'Reversal of egg sorting ' || s.sessionno;
    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby)
    SELECT p_farmid, z.poultryproductid, 'Sorting Reversal', -SUM(l.quantity), NULL, p_sessionid, v_note, p_by
    FROM   poultryeggsortinglines l JOIN poultryeggsizes z ON z.eggsizeid = l.eggsizeid
    WHERE  l.sessionid = p_sessionid AND l.linetype = 'SizedOutput'
    GROUP  BY z.poultryproductid;

    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby)
    VALUES (p_farmid, public.fnpoultry_unsortedeggproduct(p_farmid), 'Sorting Reversal', s.inputquantity, NULL, p_sessionid, v_note, p_by);

    UPDATE poultryeggsortingsessions x
    SET    status = 'Reversed', reversedby = p_by, reversedatutc = now(),
           reversalreason = btrim(p_reason), updatedatutc = now()
    WHERE  x.sessionid = p_sessionid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Readers
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryeggsorting_sessions(
    p_farmid text, p_fromdate date DEFAULT NULL, p_todate date DEFAULT NULL,
    p_status text DEFAULT NULL, p_recordid integer DEFAULT NULL, p_sessionid integer DEFAULT NULL)
RETURNS TABLE (sessionid integer, sessionno text, sortingmode text, flockid integer, flockname text,
               productionrecordid integer, picknumber integer, scoperecordids integer[], sortingdate date,
               status text, inputquantity integer, outputquantity integer, lossquantity integer, notes text,
               createdby text, createdatutc timestamptz, postedby text, postedatutc timestamptz,
               reversedby text, reversedatutc timestamptz, reversalreason text,
               firstproductiondate date, lastproductiondate date, linesjson text, sourcesjson text)
LANGUAGE sql
STABLE
AS $function$
    SELECT s.sessionid, s.sessionno, s.sortingmode, s.flockid, f.name::text,
           s.productionrecordid, s.picknumber::int, s.scoperecordids, s.sortingdate,
           s.status, s.inputquantity, s.outputquantity, s.lossquantity, s.notes,
           s.createdby, s.createdatutc, s.postedby, s.postedatutc,
           s.reversedby, s.reversedatutc, s.reversalreason,
           (SELECT min(pr.date) FROM productionrecords pr WHERE pr.id = ANY (s.scoperecordids)),
           (SELECT max(pr.date) FROM productionrecords pr WHERE pr.id = ANY (s.scoperecordids)),
           (SELECT json_agg(json_build_object(
                       'lineId', l.lineid, 'lineType', l.linetype, 'eggSizeId', l.eggsizeid,
                       'sizeName', z.name, 'quantity', l.quantity, 'notes', l.notes)
                   ORDER BY CASE WHEN l.linetype = 'SizedOutput' THEN 0 ELSE 1 END, z.sortorder, l.lineid)::text
            FROM poultryeggsortinglines l LEFT JOIN poultryeggsizes z ON z.eggsizeid = l.eggsizeid
            WHERE l.sessionid = s.sessionid),
           (SELECT json_agg(json_build_object(
                       'productionRecordId', src.productionrecordid, 'pickNumber', src.picknumber,
                       'productionDate', src.productiondate, 'quantity', src.quantity)
                   ORDER BY src.productiondate, src.picknumber)::text
            FROM poultryeggsortingsources src WHERE src.sessionid = s.sessionid)
    FROM   poultryeggsortingsessions s
    LEFT   JOIN flock f ON f.flockid = s.flockid
    WHERE  s.farmid = p_farmid
      AND  (p_fromdate IS NULL OR s.sortingdate >= p_fromdate)
      AND  (p_todate   IS NULL OR s.sortingdate <= p_todate)
      AND  (p_status   IS NULL OR s.status = p_status)
      AND  (p_recordid IS NULL OR p_recordid = ANY (s.scoperecordids))
      AND  (p_sessionid IS NULL OR s.sessionid = p_sessionid)
    ORDER  BY s.sortingdate DESC, s.sessionid DESC;
$function$;

-- Headline figures for a business date.
CREATE OR REPLACE FUNCTION public.sppoultryeggsorting_summary(p_farmid text, p_date date DEFAULT NULL)
RETURNS TABLE (businessdate date, unsortedonhand numeric, sizedonhand numeric,
               sortedtoday integer, sizedcreatedtoday integer, losstoday integer, sessionstoday integer,
               productionleft integer, recordswithleft integer, oldestleftdate date)
LANGUAGE sql
STABLE
AS $function$
    WITH d AS (SELECT COALESCE(p_date, public.fncompany_businessdate(p_farmid)) AS day),
    cls AS (SELECT * FROM public.sppoultryeggclasses_get(p_farmid, TRUE)),
    today AS (
        SELECT COALESCE(SUM(s.inputquantity), 0)::int AS input,
               COALESCE(SUM(s.outputquantity), 0)::int AS output,
               COALESCE(SUM(s.lossquantity), 0)::int AS loss,
               COUNT(*)::int AS n
        FROM   poultryeggsortingsessions s, d
        WHERE  s.farmid = p_farmid AND s.status = 'Posted' AND s.sortingdate = d.day
    ),
    lefts AS (
        SELECT x.productionrecordid, MAX(x.recordleft) AS recordleft, MIN(x.productiondate) AS pdate
        FROM   public.sppoultryeggsorting_picks(p_farmid, NULL, (SELECT day FROM d), NULL, NULL) x
        GROUP  BY x.productionrecordid
        HAVING MAX(x.recordleft) > 0
    )
    SELECT d.day,
           COALESCE((SELECT SUM(onhand) FROM cls WHERE classkind = 'Unsorted'), 0),
           COALESCE((SELECT SUM(onhand) FROM cls WHERE classkind = 'Size'), 0),
           t.input, t.output, t.loss, t.n,
           COALESCE((SELECT SUM(recordleft) FROM lefts), 0)::int,
           (SELECT COUNT(*) FROM lefts)::int,
           (SELECT MIN(pdate) FROM lefts)
    FROM d, today t;
$function$;

-- -----------------------------------------------------------------------------
-- 7. Production records must stay consistent with what was sorted from them
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tr_productionrecords_sortingguard_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_sorted   integer;
    v_pick     record;
    v_saleable integer;
    v_new      integer[];
BEGIN
    SELECT COALESCE(SUM(src.quantity), 0)::int INTO v_sorted
    FROM   poultryeggsortingsources src
    JOIN   poultryeggsortingsessions s ON s.sessionid = src.sessionid
    WHERE  src.productionrecordid = OLD.id AND s.status = 'Posted';

    IF v_sorted = 0 THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION '% egg(s) from this production record have been sorted. Reverse those sortings in the Egg Sorting Workspace before deleting the record.',
            v_sorted;
    END IF;

    IF NEW.flockid IS DISTINCT FROM OLD.flockid OR NEW.date IS DISTINCT FROM OLD.date
       OR NEW.farmid IS DISTINCT FROM OLD.farmid THEN
        RAISE EXCEPTION 'Eggs from this production record have been sorted, so its flock and date cannot change. Reverse the sortings first.';
    END IF;

    v_saleable := GREATEST(COALESCE(NEW.totalproduction, 0) - COALESCE(NEW.brokeneggs, 0) - COALESCE(NEW.meatyeggs, 0)
                           - COALESCE(NEW.softeggs, 0) - COALESCE(NEW.losteggs, 0), 0);
    IF v_saleable < v_sorted THEN
        RAISE EXCEPTION '% egg(s) from this record have already been sorted, so its saleable eggs cannot drop to %. Reverse the sortings first, or correct the sorting.',
            v_sorted, v_saleable;
    END IF;

    v_new := ARRAY[COALESCE(NEW.production9am, 0), COALESCE(NEW.production12pm, 0), COALESCE(NEW.production4pm, 0),
                   COALESCE(NEW.production4thpick, 0), COALESCE(NEW.production5thpick, 0), COALESCE(NEW.production6thpick, 0)];
    FOR v_pick IN
        SELECT src.picknumber, SUM(src.quantity)::int AS qty
        FROM   poultryeggsortingsources src
        JOIN   poultryeggsortingsessions s ON s.sessionid = src.sessionid
        WHERE  src.productionrecordid = OLD.id AND s.status = 'Posted'
        GROUP  BY src.picknumber
    LOOP
        IF v_new[v_pick.picknumber] < v_pick.qty THEN
            RAISE EXCEPTION '% egg(s) of pick % have already been sorted, so the pick cannot be changed to %. Reverse the sortings first.',
                v_pick.qty, v_pick.picknumber, v_new[v_pick.picknumber];
        END IF;
    END LOOP;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS tr_productionrecords_sortingguard ON public.productionrecords;
CREATE TRIGGER tr_productionrecords_sortingguard BEFORE UPDATE OR DELETE ON public.productionrecords
    FOR EACH ROW EXECUTE FUNCTION public.tr_productionrecords_sortingguard_fn();

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification. Every fixture is rolled back by the sentinel at the end.
-- Scenarios follow the spec's numbering (66-76).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    a   text := '44444444-3333-4333-8333-000000000342';
    b   text := '55555555-3333-4333-8333-000000000342';
    d   date := current_date - 3;
    who text := '__342__';
    f1 integer; f2 integer; fb integer;
    r1 integer; r2 integer; r3 integer; rb integer;
    un integer; lg integer; md integer; sm integer; pw integer;
    zl integer; zm integer; zs integer; zp integer; zbl integer;
    s1 integer; s2 integer; s3 integer; s4 integer; sale1 integer;
    v_n numeric;
    q  record;
    req uuid := gen_random_uuid();
BEGIN
    BEGIN
        INSERT INTO farms (id, farmid, name, email, type, timezoneid)
        VALUES (a, a, 'Selftest A', 'a@selftest.invalid', 'Poultry', 'UTC'),
               (b, b, 'Selftest B', 'b@selftest.invalid', 'Poultry', 'UTC');
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'Flock 3', d - 200, 'Brown', 2000, TRUE, TRUE, -342, timestamp '2026-01-01') RETURNING flockid INTO f1;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'Flock 4', d - 200, 'Brown', 2000, TRUE, TRUE, -342, timestamp '2026-01-01') RETURNING flockid INTO f2;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, b, 'FB', d - 200, 'Brown', 2000, TRUE, TRUE, -342, timestamp '2026-01-01') RETURNING flockid INTO fb;

        PERFORM public.sppoultryeggsizes_ensure(a, who);
        -- This farm grades Large / Medium / Small / Peewee.
        PERFORM public.sppoultryeggsize_save(a, NULL, 'Peewee', 5, TRUE, who);
        SELECT eggsizeid, poultryproductid INTO zl, lg FROM poultryeggsizes WHERE farmid = a AND name = 'Large';
        SELECT eggsizeid, poultryproductid INTO zm, md FROM poultryeggsizes WHERE farmid = a AND name = 'Medium';
        SELECT eggsizeid, poultryproductid INTO zs, sm FROM poultryeggsizes WHERE farmid = a AND name = 'Small';
        SELECT eggsizeid, poultryproductid INTO zp, pw FROM poultryeggsizes WHERE farmid = a AND name = 'Peewee';
        un := public.fnpoultry_unsortedeggproduct(a);

        -- ---- 67: Pick 1 500, Pick 2 600, Pick 3 610 -> Unsorted +1,710 ------
        r1 := public.spproductionrecord_insert(a, who, who, 28, 196, d, 2000, 0, 2000, 0, NULL, 500, 600, 610, 1710, f1, 0);
        IF (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = un) <> 1710 THEN
            RAISE EXCEPTION '342: production should put 1,710 into Unsorted.';
        END IF;
        IF (SELECT count(*) FROM public.sppoultryeggsorting_picks(a, d, d, f1)) <> 3
           OR (SELECT SUM(available) FROM public.sppoultryeggsorting_picks(a, d, d, f1)) <> 1710 THEN
            RAISE EXCEPTION '342: three picks, 1,710 available.';
        END IF;

        -- ---- 68: sort Pick 1 immediately ------------------------------------
        s1 := public.sppoultryeggsorting_save(a, NULL, 'ByPick', d, ARRAY[r1], 1,
              json_build_array(
                  json_build_object('lineType', 'SizedOutput', 'eggSizeId', zl, 'quantity', 260),
                  json_build_object('lineType', 'SizedOutput', 'eggSizeId', zm, 'quantity', 150),
                  json_build_object('lineType', 'SizedOutput', 'eggSizeId', zs, 'quantity', 60),
                  json_build_object('lineType', 'SizedOutput', 'eggSizeId', zp, 'quantity', 20),
                  json_build_object('lineType', 'Reject', 'quantity', 10))::text, NULL, req, who);
        -- Draft moves nothing; a retried create returns the same draft.
        IF (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = un) <> 1710 THEN
            RAISE EXCEPTION '342: a draft moved stock.';
        END IF;
        IF public.sppoultryeggsorting_save(a, NULL, 'ByPick', d, ARRAY[r1], 1, '[]', NULL, req, who) <> s1 THEN
            RAISE EXCEPTION '342: a retried create made a second draft.';
        END IF;
        PERFORM public.sppoultryeggsorting_post(a, s1, who);
        PERFORM public.sppoultryeggsorting_post(a, s1, who);      -- 61: double post is a no-op
        IF (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = un) <> 1210
           OR (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = lg) <> 260
           OR (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = pw) <> 20 THEN
            RAISE EXCEPTION '342: pick 1 transformation wrong (or posted twice).';
        END IF;
        SELECT * INTO q FROM public.sppoultryeggsorting_picks(a, d, d, f1) x WHERE x.picknumber = 1;
        IF q.available <> 0 OR q.picksorted <> 500 OR q.bypicksorted <> 500 THEN
            RAISE EXCEPTION '342: pick 1 should be complete: %', q;
        END IF;

        -- ---- 69: partial pick sort, then continue --------------------------
        s2 := public.sppoultryeggsorting_save(a, NULL, 'ByPick', d, ARRAY[r1], 2,
              json_build_array(json_build_object('lineType', 'SizedOutput', 'eggSizeId', zl, 'quantity', 290),
                               json_build_object('lineType', 'Breakage', 'quantity', 10))::text, NULL, NULL, who);
        PERFORM public.sppoultryeggsorting_post(a, s2, who);
        SELECT * INTO q FROM public.sppoultryeggsorting_picks(a, d, d, f1) x WHERE x.picknumber = 2;
        IF q.available <> 300 THEN
            RAISE EXCEPTION '342: pick 2 should have 300 left: %', q;
        END IF;

        -- ---- 76: concurrency -- two drafts over the same 300 -----------------
        s3 := public.sppoultryeggsorting_save(a, NULL, 'ByPick', d, ARRAY[r1], 2,
              json_build_array(json_build_object('lineType', 'SizedOutput', 'eggSizeId', zm, 'quantity', 200))::text, NULL, NULL, who);
        s4 := public.sppoultryeggsorting_save(a, NULL, 'ByPick', d, ARRAY[r1], 2,
              json_build_array(json_build_object('lineType', 'SizedOutput', 'eggSizeId', zm, 'quantity', 150))::text, NULL, NULL, who);
        PERFORM public.sppoultryeggsorting_post(a, s3, who);
        BEGIN
            PERFORM public.sppoultryeggsorting_post(a, s4, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '342: 350 sorted from a pick with 300 left.';
        EXCEPTION WHEN SQLSTATE 'P0003' THEN NULL;
        END;
        IF (SELECT status FROM poultryeggsortingsessions WHERE sessionid = s4) <> 'Draft' THEN
            RAISE EXCEPTION '342: the refused draft should stay a draft.';
        END IF;
        PERFORM public.sppoultryeggsorting_discard(a, s4);

        -- ---- 70: mixed -- Sort All Available across pick 2's rest + pick 3 ----
        s4 := public.sppoultryeggsorting_save(a, NULL, 'Combined', d, ARRAY[r1], NULL,
              json_build_array(json_build_object('lineType', 'SizedOutput', 'eggSizeId', zl, 'quantity', 480),
                               json_build_object('lineType', 'SizedOutput', 'eggSizeId', zm, 'quantity', 200),
                               json_build_object('lineType', 'OtherLoss', 'quantity', 20))::text, NULL, NULL, who);
        PERFORM public.sppoultryeggsorting_post(a, s4, who);
        -- FIFO: pick 2's last 100 first, then 600 of pick 3; 10 left on pick 3.
        IF (SELECT quantity FROM poultryeggsortingsources WHERE sessionid = s4 AND picknumber = 2) <> 100
           OR (SELECT quantity FROM poultryeggsortingsources WHERE sessionid = s4 AND picknumber = 3) <> 600 THEN
            RAISE EXCEPTION '342: combined allocation should take pick 2 (100) then pick 3 (600).';
        END IF;
        IF (SELECT SUM(available) FROM public.sppoultryeggsorting_picks(a, d, d, f1)) <> 10 THEN
            RAISE EXCEPTION '342: 10 eggs should remain unsorted.';
        END IF;
        -- 20: daily reconciliation -- net production = sized + loss + left.
        IF (SELECT SUM(outputquantity) + SUM(lossquantity) FROM poultryeggsortingsessions WHERE farmid = a AND status = 'Posted') + 10 <> 1710 THEN
            RAISE EXCEPTION '342: the day does not reconcile.';
        END IF;
        -- No production record was created by sorting.
        IF (SELECT count(*) FROM productionrecords WHERE farmid = a AND flockid = f1) <> 1 THEN
            RAISE EXCEPTION '342: sorting created a production record.';
        END IF;

        -- ---- 71: production on D, sorted on D+1 ----------------------------
        r2 := public.spproductionrecord_insert(a, who, who, 28, 196, d + 1, 2000, 0, 2000, 0, NULL, 100, 0, 0, 100, f1, 0);
        s1 := public.sppoultryeggsorting_save(a, NULL, 'ByPick', d + 2, ARRAY[r2], 1,
              json_build_array(json_build_object('lineType', 'SizedOutput', 'eggSizeId', zs, 'quantity', 100))::text, NULL, NULL, who);
        PERFORM public.sppoultryeggsorting_post(a, s1, who);
        IF (SELECT productiondate FROM poultryeggsortingsources WHERE sessionid = s1) <> d + 1
           OR (SELECT sortingdate FROM poultryeggsortingsessions WHERE sessionid = s1) <> d + 2 THEN
            RAISE EXCEPTION '342: production and sorting dates must both be kept.';
        END IF;
        BEGIN
            PERFORM public.sppoultryeggsorting_save(a, NULL, 'ByPick', d - 1, ARRAY[r2], 1, '[]', NULL, NULL, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '342: sorted before the eggs were collected.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- ---- Broken at collection caps the day, not a pick ------------------
        r3 := public.spproductionrecord_insert(a, who, who, 28, 196, d, 2000, 0, 2000, 0, NULL, 200, 100, 0, 300, f2, 20);
        IF (SELECT max(recordleft) FROM public.sppoultryeggsorting_picks(a, d, d, f2)) <> 280 THEN
            RAISE EXCEPTION '342: the record should have 280 saleable eggs to sort.';
        END IF;
        s2 := public.sppoultryeggsorting_save(a, NULL, 'Combined', d, ARRAY[r3], NULL,
              json_build_array(json_build_object('lineType', 'SizedOutput', 'eggSizeId', zl, 'quantity', 281))::text, NULL, NULL, who);
        BEGIN
            PERFORM public.sppoultryeggsorting_post(a, s2, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '342: sorted more than the day''s saleable eggs.';
        EXCEPTION WHEN SQLSTATE 'P0003' THEN NULL;
        END;
        PERFORM public.sppoultryeggsorting_discard(a, s2);

        -- ---- 72-75: sell sized, then try to reverse the sorting ------------
        sale1 := public.spsale_insert(who, a, d::timestamp, 'Fresh Eggs', 600, 20, 400, 'Cash', 'Market Woman A');
        PERFORM public.sppoultrysale_setegg(a, sale1, lg, NULL, who);
        -- Large on hand: 260 + 290 + 480 = 1,030; sold 600 -> 430. s4 made 480 Large.
        BEGIN
            PERFORM public.sppoultryeggsorting_reverse(a, s4, 'graded wrong', who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '342: reversed a sorting whose eggs were sold.';
        EXCEPTION WHEN SQLSTATE 'P0006' THEN NULL;
        END;
        PERFORM public.spsale_delete(a, who, sale1);                    -- 74: Large restored, not Unsorted
        IF (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = lg) <> 1030 THEN
            RAISE EXCEPTION '342: deleting the Large sale should restore Large.';
        END IF;
        v_n := (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = un);
        PERFORM public.sppoultryeggsorting_reverse(a, s4, 'graded wrong', who);
        IF (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = un) <> v_n + 700
           OR (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = lg) <> 550
           OR (SELECT SUM(available) FROM public.sppoultryeggsorting_picks(a, d, d, f1)) <> 710 THEN
            RAISE EXCEPTION '342: reversal should restore 700 Unsorted, remove 480 Large and reopen the picks.';
        END IF;
        IF (SELECT count(*) FROM poultrystocktransactions WHERE farmid = a AND relatedid = s4
                AND txntype IN ('Sorting Out', 'Sorting In')) = 0 THEN
            RAISE EXCEPTION '342: the original sorting rows must survive a reversal.';
        END IF;
        BEGIN
            DELETE FROM poultryeggsortingsessions WHERE sessionid = s4;
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '342: a reversed sorting was deleted.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- ---- Production edits cannot undercut what was sorted ---------------
        BEGIN
            UPDATE productionrecords SET production9am = 400, totalproduction = 1610 WHERE id = r1;
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '342: pick 1 cut below what was sorted from it.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        BEGIN
            PERFORM public.spproductionrecord_delete(r1, who, a);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '342: deleted a record with posted sorting.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        UPDATE productionrecords SET notes = 'still editable' WHERE id = r1;

        -- ---- Unsorted sold away: the ledger check stops a sort ---------------
        sale1 := public.spsale_insert(who, a, d::timestamp, 'Fresh Eggs', (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = un) - 5,
                                      16, 100, 'Cash', NULL);
        s2 := public.sppoultryeggsorting_save(a, NULL, 'ByPick', d, ARRAY[r1], 3,
              json_build_array(json_build_object('lineType', 'SizedOutput', 'eggSizeId', zl, 'quantity', 10))::text, NULL, NULL, who);
        BEGIN
            PERFORM public.sppoultryeggsorting_post(a, s2, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '342: sorted eggs that were already sold unsorted.';
        EXCEPTION WHEN SQLSTATE 'P0003' THEN NULL;
        END;

        -- ---- Isolation ------------------------------------------------------
        rb := public.spproductionrecord_insert(b, who, who, 28, 196, d, 2000, 0, 2000, 0, NULL, 50, 0, 0, 50, fb, 0);
        BEGIN
            PERFORM public.sppoultryeggsorting_save(a, NULL, 'ByPick', d, ARRAY[rb], 1, '[]', NULL, NULL, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '342: sorted another company''s production.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        PERFORM public.sppoultryeggsizes_ensure(b, who);
        SELECT eggsizeid INTO zbl FROM poultryeggsizes WHERE farmid = b AND name = 'Large';
        BEGIN
            PERFORM public.sppoultryeggsorting_save(a, NULL, 'ByPick', d, ARRAY[r1], 3,
                    json_build_array(json_build_object('lineType', 'SizedOutput', 'eggSizeId', zbl, 'quantity', 1))::text, NULL, NULL, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '342: used another company''s egg size.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        BEGIN
            PERFORM public.sppoultryeggsorting_save(a, NULL, 'Combined', d, ARRAY[r1, r3], NULL, '[]', NULL, NULL, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '342: one session sorted two flocks.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        IF EXISTS (SELECT 1 FROM public.sppoultryeggsorting_sessions(b)) THEN
            RAISE EXCEPTION '342: company B can see company A''s sortings.';
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '__342_ok__';
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
        NULL;
    END;

    RAISE NOTICE '342_PoultryEggSorting: verified (production -> unsorted, sort by pick, draft moves nothing, idempotent create & post, partial + continue, concurrency, combined FIFO, reconciliation, no new production record, next-day sorting, collection loss caps the day, sized sale, unsafe reversal blocked, sale reversal restores class, safe reversal, append-only, production edit/delete guarded, unsorted-stock check, isolation, one flock per session).';
END $$;
