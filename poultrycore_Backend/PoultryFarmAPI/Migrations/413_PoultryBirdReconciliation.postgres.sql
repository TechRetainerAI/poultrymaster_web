-- =============================================================================
-- 413_PoultryBirdReconciliation.postgres.sql   (requires 319, 325, 359, 369, 373, 406)
--
-- Purpose
-- -------
-- Every bird bought in a batch is accounted for: alive in a flock, alive but not
-- yet placed, or gone (sold / died / culled / transferred / corrected) through a
-- movement that names its batch, its flock (or explicitly "not placed in a
-- flock") and its reason.
--
-- WHAT WAS WRONG (found against the live database, 2026-11-08)
-- ------------------------------------------------------------
--  1. EVERY batch-level bird movement failed.  sppoultrybirdadjustment_post (359)
--     names v_flock.name inside a CASE even when no flock was chosen, and PL/pgSQL
--     refuses to read an unassigned record:  "record v_flock is not assigned
--     yet".  So "Not placed in a flock - 6,277 birds" on the Stock page could
--     never be saved.
--  2. A flock with no production record could not be adjusted at all: 359 moved
--     the count on the flock's latest production record and refused when there
--     was none.  The Stock page greyed such flocks out.
--  3. Initial Farm Setup's 'Opening Adjustment' ledger rows were written by
--     sppoultryopeningbirdstock_post (325) before 373 added batchid / flockid to
--     the ledger, and it was never taught to fill them.  The FLOCK's birds were
--     right all along (flock.quantity is the opening live count, 319) -- only the
--     movement's batch / flock link was missing.  All 8 live rows resolve
--     exactly through relatedid -> poultryopeningflockposition.
--  4. Nothing recorded what happened to birds that never went into a flock, so a
--     batch of 16,000 with 6,500 placed simply "had 9,500 left".
--
-- WHAT THIS DOES
-- --------------
--  * poultrybirdadjustments gets an explicit SCOPE ('Flock' | 'BatchUnallocated')
--    and APPLIEDTO ('ProductionRecord' | 'FlockQuantity' | 'BatchUnallocated'),
--    plus source / request-key / reversal links.  Existing rows are classified
--    from what 359 wrote (it only ever wrote explicit batch or flock rows).
--  * sppoultrybirdmovement_post: THE one function that moves birds.
--      Flock, has production records -> latest record's count (359, unchanged)
--      Flock, no production record   -> flock.quantity          (NEW)
--      BatchUnallocated               -> the batch's unplaced pool (359)
--    sppoultrybirdadjustment_post keeps its signature and delegates to it.
--  * spflock_getconsumedforbatch adds FlockQuantity adjustments back, exactly
--    as it already adds opening reductions back: a flock-level loss never hands
--    birds back to the batch.  Batch-level and flock-level are separate pools.
--  * fnflock_birdposition: originallyplaced / openinglivebirds no longer drift
--    when a flock's quantity is adjusted before its first production record.
--  * Batch Bird Reconciliation: poultrybatchbirdreconciliations (one row per
--    posting), poultryhistoricalbirdsales (quantity, price, value, received,
--    owed, linked opening customer debt), sppoultrybatchreconcile_post /
--    _reverse / _summary / _detail.
--  * Flock-to-flock transfer: sppoultrybirdtransfer_post (company total
--    unchanged).
--  * Repair: fnpoultrybirdrepair_diagnose + sppoultrybirdrepair_apply
--    (metadata-only, verified links only, logged, idempotent).
--  * sppoultrymanualmovement_post takes an explicit p_scope.
--
-- FINANCIAL RULES (see the completion report)
--  * A historical sale writes NO sale row, NO cash, NO revenue.  Its value is
--    kept on poultryhistoricalbirdsales.  Only an amount STILL OWED becomes an
--    opening customer debt (369, entrytype 'HistoricalDebt'), once.
--  * A sale in the current period is refused here: it belongs on Sales.
--  * Bird cost is untouched: Profit & Loss by Flock already charges a flock
--    totalcost * originallyplaced / numberofbirds, so birds sold before placing
--    never land in any flock's cost.
--
-- Deploy order: this migration, then the Farm API, then the web app.
-- =============================================================================
\set ON_ERROR_STOP on

BEGIN;

-- ============================================================ 1. schema ======
ALTER TABLE public.poultrybirdadjustments ADD COLUMN IF NOT EXISTS scope            text;
ALTER TABLE public.poultrybirdadjustments ADD COLUMN IF NOT EXISTS appliedto        text;
ALTER TABLE public.poultrybirdadjustments ADD COLUMN IF NOT EXISTS sourcetype       text;
ALTER TABLE public.poultrybirdadjustments ADD COLUMN IF NOT EXISTS sourceid         integer;
ALTER TABLE public.poultrybirdadjustments ADD COLUMN IF NOT EXISTS requestkey       text;
ALTER TABLE public.poultrybirdadjustments ADD COLUMN IF NOT EXISTS reversesid       integer;
ALTER TABLE public.poultrybirdadjustments ADD COLUMN IF NOT EXISTS reversedbyid     integer;

-- 359 wrote only two shapes: flockid NULL = "the batch's unplaced birds" (its
-- own documented meaning) and flockid set = that flock via its production
-- record (it refused flocks without one).  So this classification is exact.
UPDATE public.poultrybirdadjustments
SET    scope     = CASE WHEN flockid IS NULL THEN 'BatchUnallocated' ELSE 'Flock' END,
       appliedto = CASE WHEN flockid IS NULL THEN 'BatchUnallocated' ELSE 'ProductionRecord' END
WHERE  scope IS NULL;

ALTER TABLE public.poultrybirdadjustments ALTER COLUMN scope SET NOT NULL;
ALTER TABLE public.poultrybirdadjustments ALTER COLUMN appliedto SET NOT NULL;
ALTER TABLE public.poultrybirdadjustments DROP CONSTRAINT IF EXISTS ck_poultrybirdadjustments_scope;
ALTER TABLE public.poultrybirdadjustments ADD CONSTRAINT ck_poultrybirdadjustments_scope CHECK (
       (scope = 'Flock'            AND flockid IS NOT NULL AND appliedto IN ('ProductionRecord', 'FlockQuantity'))
    OR (scope = 'BatchUnallocated' AND flockid IS NULL     AND appliedto = 'BatchUnallocated'));
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrybirdadjustments_requestkey
    ON public.poultrybirdadjustments (farmid, requestkey) WHERE requestkey IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_poultrybirdadjustments_source
    ON public.poultrybirdadjustments (farmid, sourcetype, sourceid) WHERE sourcetype IS NOT NULL;

-- The ledger row says which pool a bird movement touched.  NULL = legacy /
-- not a scoped bird movement; never read as "batch unallocated".
ALTER TABLE public.poultrystocktransactions ADD COLUMN IF NOT EXISTS birdscope text;
ALTER TABLE public.poultrystocktransactions DROP CONSTRAINT IF EXISTS ck_poultrystocktxn_birdscope;
ALTER TABLE public.poultrystocktransactions ADD CONSTRAINT ck_poultrystocktxn_birdscope
    CHECK (birdscope IS NULL OR birdscope IN ('Flock', 'BatchUnallocated'));
UPDATE public.poultrystocktransactions t
SET    birdscope = a.scope
FROM   public.poultrybirdadjustments a
WHERE  t.txntype = 'Bird Adjustment' AND t.relatedid = a.birdadjustmentid AND t.farmid = a.farmid
  AND  t.birdscope IS NULL;

-- One row per reconciliation POSTING of a batch's never-placed birds.
CREATE TABLE IF NOT EXISTS public.poultrybatchbirdreconciliations (
    reconciliationid     integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    farmid               text      NOT NULL,
    batchid              integer   NOT NULL,
    reconciliationno     text      NOT NULL,
    asofdate             date      NOT NULL,
    source               text      NOT NULL DEFAULT 'Batch',
    unallocatedbefore    integer   NOT NULL,
    removedbirds         integer   NOT NULL DEFAULT 0,   -- net birds this posting took out of the pool
    unallocatedafter     integer   NOT NULL,
    stillunallocatedlive integer   NOT NULL CHECK (stillunallocatedlive >= 0),
    unexplainedbirds     integer   NOT NULL CHECK (unexplainedbirds >= 0),
    status               text      NOT NULL CHECK (status IN ('Reconciled', 'Unexplained', 'Reversed')),
    notes                text,
    requestkey           text,
    createdby            text,
    createdat            timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    reversedat           timestamp,
    reversedby           text,
    reversalreason       text
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrybatchbirdrecon_no
    ON public.poultrybatchbirdreconciliations (farmid, reconciliationno);
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultrybatchbirdrecon_requestkey
    ON public.poultrybatchbirdreconciliations (farmid, requestkey) WHERE requestkey IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_poultrybatchbirdrecon_batch
    ON public.poultrybatchbirdreconciliations (farmid, batchid);

-- A sale that happened before the farm used the application.  Physical effect
-- is the linked bird adjustment (batch pool) or the flock's opening position
-- (flock pool).  Financial effect is ONLY the linked opening debt, if any.
CREATE TABLE IF NOT EXISTS public.poultryhistoricalbirdsales (
    historicalsaleid     integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    farmid               text          NOT NULL,
    batchid              integer       NOT NULL,
    flockid              integer,                      -- set = valued from the flock's opening "sold"
    scope                text          NOT NULL CHECK (scope IN ('Flock', 'BatchUnallocated')),
    reconciliationid     integer,
    saledate             date          NOT NULL,
    birds                integer       NOT NULL CHECK (birds > 0),
    priceperbird         numeric(14,2) CHECK (priceperbird IS NULL OR priceperbird >= 0),
    totalvalue           numeric(14,2) CHECK (totalvalue IS NULL OR totalvalue >= 0),
    valueunknown         boolean       NOT NULL DEFAULT FALSE,
    customerid           integer,
    amountreceived       numeric(14,2) NOT NULL DEFAULT 0 CHECK (amountreceived >= 0),
    amountowed           numeric(14,2) NOT NULL DEFAULT 0 CHECK (amountowed >= 0),
    classification       text          NOT NULL DEFAULT 'PreCutover' CHECK (classification IN ('PreCutover')),
    financialtreatment   text          NOT NULL CHECK (financialtreatment IN
                             ('QuantityOnly', 'HistoricalPaid', 'HistoricalReceivable', 'HistoricalUnpaidNotTracked')),
    debtid               integer,
    debtcreated          boolean       NOT NULL DEFAULT FALSE,
    birdadjustmentid     integer,
    reference            text,
    notes                text,
    status               text          NOT NULL DEFAULT 'Posted' CHECK (status IN ('Posted', 'Reversed')),
    createdby            text,
    createdat            timestamp     NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    reversedat           timestamp,
    reversedby           text,
    CONSTRAINT ck_poultryhistoricalbirdsales_scope CHECK ((scope = 'Flock') = (flockid IS NOT NULL)),
    CONSTRAINT ck_poultryhistoricalbirdsales_value CHECK (
        (valueunknown AND totalvalue IS NULL AND priceperbird IS NULL AND amountreceived = 0 AND amountowed = 0)
        OR (NOT valueunknown AND totalvalue IS NOT NULL AND amountreceived + amountowed = totalvalue))
);
CREATE INDEX IF NOT EXISTS ix_poultryhistoricalbirdsales_batch ON public.poultryhistoricalbirdsales (farmid, batchid);
-- One debt is never claimed by two historical sales.
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryhistoricalbirdsales_debt
    ON public.poultryhistoricalbirdsales (farmid, debtid) WHERE debtid IS NOT NULL AND status = 'Posted';

-- What the repair changed, row by row.
CREATE TABLE IF NOT EXISTS public.poultrybirdrepairlog (
    repairid      integer GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    farmid        text      NOT NULL,
    checkcode     text      NOT NULL,
    tablename     text      NOT NULL,
    rowid         integer   NOT NULL,
    beforevalues  jsonb,
    aftervalues   jsonb,
    evidence      text,
    repairedby    text,
    repairedat    timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
CREATE INDEX IF NOT EXISTS ix_poultrybirdrepairlog_farm ON public.poultrybirdrepairlog (farmid, repairedat);

-- ====================================================== 2. reasons ==========
-- Reasons a bird can leave (or rejoin) a pool.  Decrease-only reasons can never
-- be posted as an increase except by the reversal path.
CREATE OR REPLACE FUNCTION public.fnpoultrybird_decreasereasons()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $f$
    SELECT ARRAY['Historical Sale', 'Historical Sale / Use', 'Historical Mortality', 'Cull',
                 'Transfer Out', 'Damage', 'Loss', 'Disposal'];
$f$;

-- ================================================ 3. consumed / position =====
-- Birds a batch has given out, on the PLACED basis.  Adds back:
--   * opening reductions (325)            -- flock.quantity is the opening live count
--   * FlockQuantity adjustments (413)     -- flock.quantity moved before any record
-- and takes off the batch-unallocated adjustments (359).  A flock-level event
-- therefore NEVER moves the batch pool, and a batch-level event never moves a flock.
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
      AND  (p_flockidtoexclude IS NULL OR f.flockid <> p_flockidtoexclude);

    -- 413: a flock's quantity moved by an adjustment is still birds the batch gave out.
    v_total := COALESCE(v_total, 0) - COALESCE((
        SELECT SUM(a.quantity) FROM public.poultrybirdadjustments a
        JOIN   flock f ON f.flockid = a.flockid AND f.farmid = a.farmid
        WHERE  a.farmid = p_farmid AND f.batchid = p_batchid AND a.appliedto = 'FlockQuantity'
          AND  (p_flockidtoexclude IS NULL OR a.flockid <> p_flockidtoexclude)), 0);

    -- 359: birds lost (or found) before being placed in any flock.
    v_total := v_total - COALESCE((
        SELECT SUM(a.quantity) FROM public.poultrybirdadjustments a
        WHERE  a.farmid = p_farmid AND a.batchid = p_batchid AND a.scope = 'BatchUnallocated'), 0);

    RETURN COALESCE(v_total, 0);
END
$function$;

-- Net FlockQuantity adjustments of one flock (the part of flock.quantity that is
-- not "what was placed / opened with").
CREATE OR REPLACE FUNCTION public.fnflock_quantityadjustments(p_farmid text, p_flockid integer)
RETURNS integer LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(SUM(a.quantity), 0)::int FROM public.poultrybirdadjustments a
    WHERE  a.farmid = p_farmid AND a.flockid = p_flockid AND a.appliedto = 'FlockQuantity';
$f$;

-- 406's body, with flock.quantity read as (opening / placed) + FlockQuantity
-- adjustments.  currentlivebirds is unchanged for every flock that has no
-- FlockQuantity adjustment, i.e. every flock that exists today.
CREATE OR REPLACE FUNCTION public.fnflock_birdposition(p_farmid text, p_flockid integer)
 RETURNS TABLE(flockid integer, hasopeningposition boolean, historyknown boolean, originallyplaced integer, openingmortality integer, openingsold integer, openingculled integer, openingtransferred integer, openingother integer, openinglivebirds integer, recordedmortality integer, productionrecordcount integer, lastcountedbirds integer, lastcountdate date, correction integer, birdssold integer, birdsculled integer, birdstransferred integer, currentlivebirds integer)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    WITH f AS (
        SELECT fl.flockid AS c_flockid, COALESCE(fl.quantity, 0) AS c_quantity,
               public.fnflock_quantityadjustments(p_farmid, p_flockid) AS c_qadj
        FROM   flock fl
        WHERE  fl.farmid = p_farmid AND fl.flockid = p_flockid
    ),
    o AS (
        SELECT op.*
        FROM   poultryopeningflockposition op
        WHERE  op.farmid = p_farmid AND op.flockid = p_flockid
        ORDER  BY op.openingpositionid DESC
        LIMIT  1
    ),
    pr AS (
        SELECT COALESCE(SUM(COALESCE(r.mortality, 0)), 0)::int AS c_mort,
               COUNT(*)::int                                    AS c_n
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.flockid = p_flockid
    ),
    lr AS (
        SELECT r.noofbirdsleft AS c_left, r.date AS c_date, COALESCE(r.birdssoldreflected, 0) AS c_refl
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.flockid = p_flockid
        ORDER  BY r.date DESC, r.id DESC
        LIMIT  1
    ),
    s AS (
        SELECT COALESCE(ROUND(SUM(sa.quantity)), 0)::int AS c_sold
        FROM   sale sa
        WHERE  sa.status = 'Posted' AND sa.farmid = p_farmid AND sa.flockid = p_flockid
          AND  fnpoultrysale_isbirdsale(sa.product)
    ),
    d AS (
        SELECT COALESCE(SUM(x.quantity) FILTER (WHERE x.disposition = 'Cull'), 0)::int     AS c_culled,
               COALESCE(SUM(x.quantity) FILTER (WHERE x.disposition = 'Transfer'), 0)::int AS c_transferred
        FROM   flockcloseoutdispositions x
        JOIN   flockcloseouts c ON c.closeoutid = x.closeoutid
        WHERE  x.farmid = p_farmid AND x.flockid = p_flockid
          AND  x.reversedat IS NULL AND c.reopenedat IS NULL
    )
    SELECT
        f.c_flockid,
        (o.openingpositionid IS NOT NULL),
        COALESCE(o.historyknown, TRUE),
        COALESCE(o.originallyplaced, f.c_quantity - f.c_qadj),
        COALESCE(o.historicalmortality, 0),
        COALESCE(o.historicalsold, 0),
        COALESCE(o.historicalculled, 0),
        COALESCE(o.historicaltransferred, 0),
        COALESCE(o.otheradjustment, 0),
        f.c_quantity - f.c_qadj,
        pr.c_mort,
        pr.c_n,
        GREATEST(COALESCE(lr.c_left, f.c_quantity), 0),
        lr.c_date,
        CASE WHEN lr.c_date IS NULL THEN 0
             ELSE GREATEST(COALESCE(lr.c_left, f.c_quantity), 0) - (f.c_quantity - pr.c_mort)
        END,
        s.c_sold,
        d.c_culled,
        d.c_transferred,
        GREATEST(COALESCE(lr.c_left, f.c_quantity), 0) - (s.c_sold - COALESCE(lr.c_refl, 0)) - d.c_culled - d.c_transferred
    FROM   f
    CROSS  JOIN pr
    CROSS  JOIN s
    CROSS  JOIN d
    LEFT   JOIN o  ON TRUE
    LEFT   JOIN lr ON TRUE;
END
$function$;

-- Birds a batch holds that are not in any flock (never negative).
CREATE OR REPLACE FUNCTION public.fnpoultrybatch_unallocated(p_farmid text, p_batchid integer)
RETURNS integer LANGUAGE sql STABLE AS $f$
    SELECT GREATEST(b.numberofbirds - spflock_getconsumedforbatch(b.batchid, p_farmid, NULL), 0)
    FROM   mainflockbatch b WHERE b.batchid = p_batchid AND b.farmid = p_farmid;
$f$;

-- ========================================== 4. THE bird movement function ====
-- p_quantity is SIGNED.  Returns the poultrybirdadjustments id.  A repeated
-- p_requestkey returns the id it posted the first time and moves nothing.
CREATE OR REPLACE FUNCTION public.sppoultrybirdmovement_post(
    p_farmid        text,
    p_scope         text,
    p_batchid       integer,
    p_flockid       integer,
    p_movementtype  text,
    p_quantity      integer,
    p_effectivedate date    DEFAULT NULL,
    p_reason        text    DEFAULT NULL,
    p_note          text    DEFAULT NULL,
    p_sourcetype    text    DEFAULT NULL,
    p_sourceid      integer DEFAULT NULL,
    p_requestkey    text    DEFAULT NULL,
    p_by            text    DEFAULT NULL,
    p_reversesid    integer DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_today     date := fncompany_businessdate(p_farmid);
    v_date      date := COALESCE(p_effectivedate, fncompany_businessdate(p_farmid));
    v_key       text := NULLIF(btrim(COALESCE(p_requestkey, '')), '');
    v_note      text := NULLIF(btrim(COALESCE(p_note, '')), '');
    v_reason    text := NULLIF(btrim(COALESCE(p_reason, '')), '');
    v_batchcode text;
    v_flockname text;
    v_flockbatch integer;
    v_closed    date;
    v_start     date;
    v_qty       integer;
    v_recid     integer;
    v_recleft   integer;
    v_applied   text;
    v_before    integer;
    v_after     integer;
    v_id        integer;
BEGIN
    IF v_key IS NOT NULL THEN
        SELECT a.birdadjustmentid INTO v_id FROM poultrybirdadjustments a
        WHERE  a.farmid = p_farmid AND a.requestkey = v_key;
        IF v_id IS NOT NULL THEN RETURN v_id; END IF;
    END IF;

    IF COALESCE(p_quantity, 0) = 0 THEN
        RAISE EXCEPTION 'Enter how many birds to adjust.' USING ERRCODE = 'P0001';
    END IF;
    IF p_scope IS NULL OR p_scope NOT IN ('Flock', 'BatchUnallocated') THEN
        RAISE EXCEPTION 'Say whether this is a flock''s birds or the batch''s birds not placed in a flock.' USING ERRCODE = 'P0001';
    END IF;
    IF p_scope = 'Flock' AND p_flockid IS NULL THEN
        RAISE EXCEPTION 'Choose the flock.' USING ERRCODE = 'P0001';
    END IF;
    IF p_scope = 'BatchUnallocated' AND p_flockid IS NOT NULL THEN
        RAISE EXCEPTION 'Birds not placed in a flock cannot name a flock.' USING ERRCODE = 'P0001';
    END IF;
    IF v_date > v_today THEN
        RAISE EXCEPTION 'The effective date (%) is in the future.', v_date USING ERRCODE = 'P0001';
    END IF;
    -- Decrease-only reasons stay decreases; only the reversal path may undo them.
    IF p_quantity > 0 AND p_reversesid IS NULL AND v_reason = ANY (fnpoultrybird_decreasereasons()) THEN
        RAISE EXCEPTION '"%" takes birds away; it cannot be an increase. Reverse the original movement instead.', v_reason
            USING ERRCODE = 'P0001';
    END IF;

    SELECT b.batchcode INTO v_batchcode FROM mainflockbatch b WHERE b.batchid = p_batchid AND b.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That batch does not belong to this company.' USING ERRCODE = 'P0001';
    END IF;

    -- Same key as BirdFlockService.AllocateBatchToFlocks: an adjustment and an
    -- allocation of the same batch cannot both read the old figures.
    PERFORM pg_advisory_xact_lock(hashtext('flock-alloc:' || p_farmid || ':' || p_batchid));

    IF p_scope = 'Flock' THEN
        SELECT f.name, f.batchid, f.closeddate::date, f.startdate::date
        INTO   v_flockname, v_flockbatch, v_closed, v_start
        FROM   flock f
        WHERE  f.flockid = p_flockid AND f.farmid = p_farmid AND NOT f.isdeleted
        FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'That flock does not belong to this company.' USING ERRCODE = 'P0001';
        END IF;
        IF v_flockbatch IS DISTINCT FROM p_batchid THEN
            RAISE EXCEPTION 'Flock "%" is not part of batch %.', v_flockname, v_batchcode USING ERRCODE = 'P0001';
        END IF;
        IF v_closed IS NOT NULL THEN
            RAISE EXCEPTION 'Flock "%" is closed. Reopen it before adjusting its birds.', v_flockname USING ERRCODE = 'P0001';
        END IF;
        IF v_start IS NOT NULL AND v_date < v_start THEN
            RAISE EXCEPTION 'Flock "%" started on %, so it had no birds on %.', v_flockname, v_start, v_date USING ERRCODE = 'P0001';
        END IF;

        SELECT bp.currentlivebirds INTO v_before FROM fnflock_birdposition(p_farmid, p_flockid) bp;
        v_before := COALESCE(v_before, 0);
        v_after  := v_before + p_quantity;
        IF v_after < 0 THEN
            RAISE EXCEPTION 'Flock "%" has % birds, so it cannot lose %.', v_flockname, v_before, -p_quantity
                USING ERRCODE = 'P0001';
        END IF;

        SELECT r.id, COALESCE(r.noofbirdsleft, 0) INTO v_recid, v_recleft
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.flockid = p_flockid
        ORDER  BY r.date DESC, r.id DESC
        LIMIT  1
        FOR UPDATE;

        IF v_recid IS NOT NULL THEN
            -- 359: the latest record opens with the corrected count.
            IF v_recleft + p_quantity < 0 THEN
                RAISE EXCEPTION 'Flock "%" has % birds on its latest record, so it cannot lose %.', v_flockname, v_recleft, -p_quantity
                    USING ERRCODE = 'P0001';
            END IF;
            UPDATE productionrecords r
            SET    noofbirds     = GREATEST(COALESCE(r.noofbirds, 0) + p_quantity, 0),
                   noofbirdsleft = COALESCE(r.noofbirdsleft, 0) + p_quantity,
                   updatedat     = (now() AT TIME ZONE 'utc'),
                   updatedby     = p_by
            WHERE  r.id = v_recid;
            v_applied := 'ProductionRecord';
        ELSE
            -- 413: no production record yet -- the flock's own count IS its
            -- birds.  spflock_getconsumedforbatch adds this back, so the batch
            -- does not get the birds back.
            UPDATE flock f SET quantity = COALESCE(f.quantity, 0) + p_quantity
            WHERE  f.flockid = p_flockid AND f.farmid = p_farmid;
            v_applied := 'FlockQuantity';
        END IF;
    ELSE
        v_before := fnpoultrybatch_unallocated(p_farmid, p_batchid);
        v_after  := v_before + p_quantity;
        IF v_after < 0 THEN
            RAISE EXCEPTION 'Batch % has % birds not placed in a flock, so it cannot lose %. To change birds already in a flock, choose the flock.',
                v_batchcode, v_before, -p_quantity USING ERRCODE = 'P0001';
        END IF;
        v_applied := 'BatchUnallocated';
    END IF;

    INSERT INTO poultrybirdadjustments
        (farmid, batchid, flockid, adjustmentdate, movementtype, quantity, productionrecordid,
         birdsbefore, birdsafter, note, createdby, reason, scope, appliedto, sourcetype, sourceid,
         requestkey, reversesid)
    VALUES
        (p_farmid, p_batchid, CASE WHEN p_scope = 'Flock' THEN p_flockid END, v_date,
         COALESCE(NULLIF(btrim(COALESCE(p_movementtype, '')), ''), 'Adjustment'),
         p_quantity, v_recid, v_before, v_after, v_note, p_by, v_reason, p_scope, v_applied,
         NULLIF(btrim(COALESCE(p_sourcetype, '')), ''), p_sourceid, v_key, p_reversesid)
    RETURNING birdadjustmentid INTO v_id;

    IF p_reversesid IS NOT NULL THEN
        UPDATE poultrybirdadjustments a SET reversedbyid = v_id
        WHERE  a.birdadjustmentid = p_reversesid AND a.farmid = p_farmid;
    END IF;

    PERFORM sppoultrybirdstock_postdated(p_farmid, 'Bird Adjustment', p_quantity::numeric, v_id, v_date,
        left((CASE WHEN p_scope = 'BatchUnallocated'
                   THEN 'Batch ' || v_batchcode || ' (not placed in a flock)'
                   ELSE 'Flock ' || v_flockname END)
             || COALESCE(' - ' || v_reason, '') || COALESCE(' - ' || v_note, ''), 500),
        p_by);
    UPDATE poultrystocktransactions t
    SET    batchid = p_batchid, flockid = CASE WHEN p_scope = 'Flock' THEN p_flockid END,
           effectivedate = v_date, reason = COALESCE(v_reason, t.reason), birdscope = p_scope
    WHERE  t.farmid = p_farmid AND t.txntype = 'Bird Adjustment' AND t.relatedid = v_id;

    RETURN v_id;
END
$function$;

-- 359's entry point, same signature: FlockId set = that flock, null = the
-- batch's unplaced birds (the meaning its API always documented).
CREATE OR REPLACE FUNCTION public.sppoultrybirdadjustment_post(
    p_farmid text, p_batchid integer, p_flockid integer, p_movementtype text,
    p_quantity integer, p_note text DEFAULT NULL, p_by text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN public.sppoultrybirdmovement_post(
        p_farmid, CASE WHEN p_flockid IS NULL THEN 'BatchUnallocated' ELSE 'Flock' END,
        p_batchid, p_flockid, p_movementtype, p_quantity, NULL,
        CASE WHEN p_movementtype = 'Reversal' THEN 'Reversal' END, p_note,
        NULL, NULL, NULL, p_by, NULL);
END
$function$;

CREATE OR REPLACE FUNCTION public.sppoultrybirdadjustment_getall(p_farmid text)
RETURNS TABLE (birdadjustmentid integer, adjustmentdate date, batchid integer, batchcode text,
               flockid integer, flockname text, movementtype text, quantity integer,
               birdsbefore integer, birdsafter integer, productionrecordid integer,
               note text, createdby text, createdat timestamp without time zone)
LANGUAGE sql
STABLE
AS $function$
    SELECT a.birdadjustmentid, a.adjustmentdate, a.batchid, b.batchcode::text,
           a.flockid, f.name::text, a.movementtype, a.quantity,
           a.birdsbefore, a.birdsafter, a.productionrecordid,
           a.note, a.createdby, a.createdat
    FROM   poultrybirdadjustments a
    LEFT   JOIN mainflockbatch b ON b.batchid = a.batchid
    LEFT   JOIN flock f ON f.flockid = a.flockid
    WHERE  a.farmid = p_farmid
    ORDER  BY a.createdat DESC, a.birdadjustmentid DESC;
$function$;

-- ============================================ 5. opening ledger metadata =====
-- 325's post, now also tagging the row with its batch / flock / date / reason.
CREATE OR REPLACE FUNCTION public.sppoultryopeningbirdstock_post(
    p_farmid text, p_openingpositionid integer, p_reduction integer, p_effectivedate date,
    p_note text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_rows integer;
BEGIN
    IF p_farmid IS NULL OR p_openingpositionid IS NULL THEN
        RAISE EXCEPTION '325: farmid and openingpositionid are required.';
    END IF;

    v_rows := public.sppoultrybirdstock_postdated(
        p_farmid, 'Opening Adjustment', -ABS(COALESCE(p_reduction, 0)), p_openingpositionid, p_effectivedate,
        COALESCE(NULLIF(btrim(p_note), ''), 'Opening historical reduction (Initial Farm Setup)'),
        p_createdby);

    -- 413: every row of this opening position names its flock and batch.
    UPDATE poultrystocktransactions t
    SET    batchid = f.batchid, flockid = o.flockid,
           effectivedate = COALESCE(t.effectivedate, o.effectivebusinessdate),
           reason = COALESCE(t.reason, 'Opening Historical Reduction'),
           birdscope = 'Flock'
    FROM   poultryopeningflockposition o
    JOIN   flock f ON f.flockid = o.flockid AND f.farmid = o.farmid
    WHERE  o.openingpositionid = p_openingpositionid AND o.farmid = p_farmid
      AND  t.farmid = p_farmid AND t.txntype = 'Opening Adjustment' AND t.relatedid = p_openingpositionid
      AND  (t.batchid IS NULL OR t.flockid IS NULL);

    RETURN v_rows;
END
$function$;

-- ========================================= 6. manual movement: scope =========
-- 373's body with an explicit p_scope.  Birds with no flock are refused unless
-- the caller says 'BatchUnallocated' -- a null flock alone proves nothing.
DROP FUNCTION IF EXISTS public.sppoultrymanualmovement_post(text, integer, integer, text, numeric, numeric, integer, integer, date, text, text, text, text, text);
CREATE FUNCTION public.sppoultrymanualmovement_post(
    p_farmid text, p_poultryproductid integer, p_rawmaterialitemid integer,
    p_movementtype text, p_quantity numeric, p_unitcost numeric,
    p_batchid integer, p_flockid integer, p_effectivedate date, p_reason text,
    p_disposition text, p_note text, p_requestkey text, p_by text,
    p_scope text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    v_today    date := fncompany_businessdate(p_farmid);
    v_date     date := COALESCE(p_effectivedate, fncompany_businessdate(p_farmid));
    v_ts       timestamp;
    v_sign     integer;
    v_qty      numeric;
    v_reason   text := btrim(COALESCE(p_reason, ''));
    v_note     text := NULLIF(btrim(COALESCE(p_note, '')), '');
    v_disp     text := NULLIF(btrim(COALESCE(p_disposition, '')), '');
    v_scope    text := NULLIF(btrim(COALESCE(p_scope, '')), '');
    v_p        record;
    v_kind     text;
    v_role     text;
    v_isegg    boolean := FALSE;
    v_batch    integer := p_batchid;
    v_flock    record;
    v_flockname text;
    v_id       integer;
    v_no       text;
    v_name     text;
    v_before   numeric;
    v_after    numeric;
    v_adj      integer;
    v_raw      integer;
    v_rawqty   numeric;
    v_txn      text;
    v_dead     integer;
    v_broken   integer;
    v_label    text;
BEGIN
    IF NULLIF(btrim(COALESCE(p_requestkey, '')), '') IS NOT NULL THEN
        SELECT m.movementid, m.movementno INTO v_id, v_no FROM poultrymanualstockmovements m
        WHERE  m.farmid = p_farmid AND m.requestkey = btrim(p_requestkey);
        IF v_id IS NOT NULL THEN
            RETURN jsonb_build_object('movementId', v_id, 'movementNo', v_no, 'repeated', TRUE);
        END IF;
    END IF;

    IF (p_poultryproductid IS NULL) = (p_rawmaterialitemid IS NULL) THEN
        RAISE EXCEPTION 'Pick one item.' USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(p_quantity, 0) <= 0 THEN
        RAISE EXCEPTION 'Quantity must be greater than 0. The movement type sets the direction.' USING ERRCODE = 'P0001';
    END IF;
    v_sign := CASE p_movementtype WHEN 'Increase' THEN 1 WHEN 'Adjustment' THEN 1
                                  WHEN 'Decrease' THEN -1 WHEN 'Damage/Loss' THEN -1 END;
    IF v_sign IS NULL THEN
        RAISE EXCEPTION 'Unknown movement type "%".', p_movementtype USING ERRCODE = 'P0001';
    END IF;
    v_qty := v_sign * p_quantity;

    IF v_reason = '' THEN
        RAISE EXCEPTION 'Choose the reason for this movement.' USING ERRCODE = 'P0001';
    END IF;
    IF NOT (v_reason = ANY (fnpoultrymanualmovement_reasons())) THEN
        RAISE EXCEPTION 'Unknown reason "%".', v_reason USING ERRCODE = 'P0001';
    END IF;
    IF v_reason = 'Other' AND v_note IS NULL THEN
        RAISE EXCEPTION 'Reason "Other" needs a note saying what happened.' USING ERRCODE = 'P0001';
    END IF;
    IF v_date > v_today THEN
        RAISE EXCEPTION 'The effective date (%) is in the future.', v_date USING ERRCODE = 'P0001';
    END IF;
    v_ts := CASE WHEN v_date < v_today THEN v_date::timestamp ELSE (now() AT TIME ZONE 'utc') END;

    IF p_poultryproductid IS NOT NULL THEN
        SELECT p.* INTO v_p FROM poultryproducts p WHERE p.poultryproductid = p_poultryproductid AND p.farmid = p_farmid;
        IF NOT FOUND THEN RAISE EXCEPTION 'That item does not belong to this company.' USING ERRCODE = 'P0001'; END IF;
        v_name := v_p.name;
        v_role := v_p.systemrole;
        v_kind := CASE WHEN (COALESCE(v_p.isbirdproduct, FALSE) OR v_p.name = 'Birds') AND v_role IS NULL
                       THEN 'Birds' ELSE 'Product' END;
        v_isegg := fnpoultryproduct_isegg(p_poultryproductid);
    ELSE
        SELECT i.itemname INTO v_name FROM poultryrawmaterialitems i
        WHERE  i.poultryrawmaterialitemid = p_rawmaterialitemid AND i.farmid = p_farmid;
        IF NOT FOUND THEN RAISE EXCEPTION 'That item does not belong to this company.' USING ERRCODE = 'P0001'; END IF;
        v_kind := 'RawMaterial';
    END IF;

    IF v_kind = 'RawMaterial' THEN
        v_batch := NULL;
    ELSIF p_flockid IS NOT NULL THEN
        SELECT f.flockid, f.name, f.batchid, f.closeddate INTO v_flock
        FROM   flock f WHERE f.flockid = p_flockid AND f.farmid = p_farmid AND NOT f.isdeleted;
        IF NOT FOUND THEN RAISE EXCEPTION 'That flock does not belong to this company.' USING ERRCODE = 'P0001'; END IF;
        IF p_batchid IS NOT NULL AND v_flock.batchid IS DISTINCT FROM p_batchid THEN
            RAISE EXCEPTION 'Flock "%" is not part of the chosen batch.', v_flock.name USING ERRCODE = 'P0001';
        END IF;
        v_batch := COALESCE(v_flock.batchid, p_batchid);
        v_flockname := v_flock.name;
    ELSIF p_batchid IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM mainflockbatch b WHERE b.batchid = p_batchid AND b.farmid = p_farmid) THEN
            RAISE EXCEPTION 'That batch does not belong to this company.' USING ERRCODE = 'P0001';
        END IF;
    END IF;

    IF v_reason = 'Historical Mortality' AND NOT ((v_kind = 'Birds' AND v_sign < 0) OR (v_role = 'DeadBirds' AND v_sign > 0)) THEN
        RAISE EXCEPTION 'Historical Mortality is a decrease of Birds (or an increase of Dead Birds).' USING ERRCODE = 'P0001';
    END IF;
    IF v_reason = 'Cull' AND NOT (v_kind = 'Birds' AND v_sign < 0) THEN
        RAISE EXCEPTION 'Cull is a decrease of Birds.' USING ERRCODE = 'P0001';
    END IF;
    IF v_reason = 'Opening Bird Count' AND NOT (v_kind = 'Birds' AND v_sign > 0) THEN
        RAISE EXCEPTION 'Opening Bird Count is an increase of Birds.' USING ERRCODE = 'P0001';
    END IF;
    IF v_reason = 'Opening Inventory' AND v_sign < 0 THEN
        RAISE EXCEPTION 'Opening Inventory is an increase.' USING ERRCODE = 'P0001';
    END IF;
    IF v_reason = 'Disposal' AND (v_sign > 0 OR v_kind = 'Birds') THEN
        RAISE EXCEPTION 'Disposal is a decrease of stock (live birds leave as mortality or a cull).' USING ERRCODE = 'P0001';
    END IF;
    IF v_reason = 'Unrecorded Breakage' AND NOT ((v_isegg AND v_sign < 0) OR (v_role = 'BrokenEggs' AND v_sign > 0)) THEN
        RAISE EXCEPTION 'Unrecorded Breakage is a decrease of an egg product (it becomes Broken Eggs).' USING ERRCODE = 'P0001';
    END IF;
    -- 413: birds leaving through a sale / loss are never an increase.
    IF v_kind = 'Birds' AND v_sign > 0 AND v_reason = ANY (fnpoultrybird_decreasereasons()) THEN
        RAISE EXCEPTION '"%" takes birds away, so it is a Decrease. To undo one, reverse it.', v_reason USING ERRCODE = 'P0001';
    END IF;
    IF v_disp IS NOT NULL AND NOT (v_kind = 'Birds' AND v_reason = 'Historical Mortality') THEN
        v_disp := NULL;
    END IF;
    IF v_kind = 'Birds' AND v_reason = 'Historical Mortality' THEN
        v_disp := COALESCE(v_disp, 'Keep');
        IF v_disp NOT IN ('Keep', 'Disposed') THEN
            RAISE EXCEPTION 'Disposition must be Keep or Disposed.' USING ERRCODE = 'P0001';
        END IF;
    END IF;
    IF v_kind = 'Birds' THEN
        IF v_batch IS NULL THEN
            RAISE EXCEPTION 'Birds belong to a batch: choose the batch, then the flock or "Not placed in a flock".' USING ERRCODE = 'P0001';
        END IF;
        IF p_quantity <> trunc(p_quantity) THEN
            RAISE EXCEPTION 'Birds are whole numbers.' USING ERRCODE = 'P0001';
        END IF;
        -- 413: explicit scope.
        IF p_flockid IS NOT NULL THEN
            IF v_scope IS NOT NULL AND v_scope <> 'Flock' THEN
                RAISE EXCEPTION 'A movement on flock "%" is a flock movement.', v_flockname USING ERRCODE = 'P0001';
            END IF;
            v_scope := 'Flock';
        ELSIF v_scope IS DISTINCT FROM 'BatchUnallocated' THEN
            RAISE EXCEPTION 'Choose the flock, or "Not placed in a flock" for the batch''s birds that are in no flock.' USING ERRCODE = 'P0001';
        END IF;
    ELSE
        v_scope := NULL;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('poultry-msm:' || p_farmid));
    SELECT 'MSM-' || lpad((COALESCE(MAX(substring(m.movementno FROM 5)::int), 0) + 1)::text, 5, '0') INTO v_no
    FROM   poultrymanualstockmovements m WHERE m.farmid = p_farmid AND m.movementno ~ '^MSM-[0-9]+$';

    INSERT INTO poultrymanualstockmovements
        (farmid, movementno, itemkind, poultryproductid, rawmaterialitemid, itemname, movementtype, quantity,
         unitcost, batchid, flockid, effectivedate, reason, disposition, note, requestkey, createdby)
    VALUES
        (p_farmid, v_no, v_kind, p_poultryproductid, p_rawmaterialitemid, v_name, p_movementtype, v_qty,
         CASE WHEN v_kind = 'Birds' THEN NULL ELSE NULLIF(p_unitcost, 0) END, v_batch,
         CASE WHEN v_kind = 'RawMaterial' THEN NULL ELSE p_flockid END, v_date, v_reason,
         v_disp, v_note, NULLIF(btrim(COALESCE(p_requestkey, '')), ''), p_by)
    RETURNING movementid INTO v_id;

    v_label := v_no || ' ' || v_reason || COALESCE(' - ' || v_note, '');

    IF v_kind = 'Birds' THEN
        v_adj := sppoultrybirdmovement_post(p_farmid, v_scope, v_batch, p_flockid, p_movementtype, v_qty::int,
                                            v_date, v_reason, v_no || COALESCE(' - ' || v_note, ''),
                                            'ManualStockMovement', v_id, NULL, p_by);
        UPDATE poultrybirdadjustments a SET manualmovementid = v_id
        WHERE  a.birdadjustmentid = v_adj
        RETURNING a.birdsbefore, a.birdsafter INTO v_before, v_after;
        UPDATE poultrystocktransactions t
        SET    createddate = v_ts, manualmovementid = v_id
        WHERE  t.farmid = p_farmid AND t.txntype = 'Bird Adjustment' AND t.relatedid = v_adj;

        IF v_reason = 'Historical Mortality' THEN
            v_dead := fnpoultry_byproduct(p_farmid, 'DeadBirds');
            INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, relatedid, note, createdby,
                                                  createddate, batchid, flockid, effectivedate, reason, manualmovementid)
            VALUES (p_farmid, v_dead, 'Hist Mortality In', -v_qty, v_id, left(v_label, 500), p_by,
                    v_ts, v_batch, p_flockid, v_date, v_reason, v_id);
            IF v_disp = 'Disposed' THEN
                INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, relatedid, note, createdby,
                                                      createddate, batchid, flockid, effectivedate, reason, manualmovementid)
                VALUES (p_farmid, v_dead, 'Hist Mortality Disp', v_qty, v_id, left(v_label || ' (already disposed)', 500), p_by,
                        v_ts, v_batch, p_flockid, v_date, v_reason, v_id);
            END IF;
        END IF;
        UPDATE poultrymanualstockmovements m SET birdadjustmentid = v_adj, itembefore = v_before, itemafter = v_after
        WHERE  m.movementid = v_id;

    ELSIF v_kind = 'RawMaterial' THEN
        SELECT i.currentquantity INTO v_before FROM poultryrawmaterialitems i
        WHERE  i.poultryrawmaterialitemid = p_rawmaterialitemid AND i.farmid = p_farmid FOR UPDATE;
        IF v_before + v_qty < 0 THEN
            RAISE EXCEPTION '% has % on hand, so it cannot lose %.', v_name, trim_scale(v_before), trim_scale(-v_qty)
                USING ERRCODE = 'P0001';
        END IF;
        SELECT x.poultryrawmaterialadjustmentid, x.currentquantity INTO v_raw, v_rawqty
        FROM   sppoultryrawmaterialitem_adjust(p_farmid, p_rawmaterialitemid, v_qty, NULLIF(p_unitcost, 0),
                                               p_movementtype, left(v_label, 500), p_by) x;
        UPDATE poultryrawmaterialadjustments a
        SET    adjusteddate = v_ts, reason = v_reason, manualmovementid = v_id
        WHERE  a.poultryrawmaterialadjustmentid = v_raw;
        UPDATE poultrymanualstockmovements m SET rawadjustmentid = v_raw, itembefore = v_before, itemafter = v_rawqty
        WHERE  m.movementid = v_id;

    ELSE
        PERFORM 1 FROM poultryproducts p WHERE p.poultryproductid = p_poultryproductid FOR UPDATE;
        SELECT COALESCE(SUM(t.quantity), 0) INTO v_before FROM poultrystocktransactions t
        WHERE  t.farmid = p_farmid AND t.poultryproductid = p_poultryproductid;
        IF v_role IS NOT NULL AND v_before + v_qty < 0 THEN
            RAISE EXCEPTION 'There are only % % on hand.', trim_scale(GREATEST(v_before, 0)), v_name USING ERRCODE = 'P0001';
        END IF;
        v_txn := CASE WHEN v_reason = 'Disposal' THEN 'Disposal' ELSE p_movementtype END;
        INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby,
                                              createddate, batchid, flockid, effectivedate, reason, manualmovementid)
        VALUES (p_farmid, p_poultryproductid, v_txn, v_qty, NULLIF(p_unitcost, 0), v_id, left(v_label, 500), p_by,
                v_ts, v_batch, p_flockid, v_date, v_reason, v_id);

        IF v_reason = 'Unrecorded Breakage' AND v_isegg THEN
            v_broken := fnpoultry_byproduct(p_farmid, 'BrokenEggs');
            INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, relatedid, note, createdby,
                                                  createddate, batchid, flockid, effectivedate, reason, manualmovementid)
            VALUES (p_farmid, v_broken, 'Breakage In', -v_qty, v_id, left(v_label || ' (from ' || v_name || ')', 500), p_by,
                    v_ts, v_batch, p_flockid, v_date, v_reason, v_id);
            UPDATE poultrymanualstockmovements m SET convertedtobroken = TRUE WHERE m.movementid = v_id;
        END IF;
        UPDATE poultrymanualstockmovements m SET itembefore = v_before, itemafter = v_before + v_qty
        WHERE  m.movementid = v_id;
    END IF;

    RETURN jsonb_build_object(
        'movementId', v_id, 'movementNo', v_no, 'repeated', FALSE, 'scope', v_scope,
        'itemBefore', v_before, 'itemAfter', (SELECT m.itemafter FROM poultrymanualstockmovements m WHERE m.movementid = v_id),
        'farmLiveBirds', CASE WHEN v_kind = 'Birds' THEN fnpoultry_farmlivebirds(p_farmid) END);
END
$f$;

-- 373's reverse, bird branch only changed: it undoes the exact adjustment with
-- the same scope (a reversal of a batch-pool movement goes back to the pool).
CREATE OR REPLACE FUNCTION public.sppoultrymanualmovement_reverse(
    p_farmid text, p_movementid integer, p_reason text, p_by text)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    v_m      record;
    v_today  date := fncompany_businessdate(p_farmid);
    v_note   text;
    v_adj    integer;
    v_raw    integer;
    r        record;
    v_before numeric;
    v_after  numeric;
    v_scope  text;
BEGIN
    IF NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Say why this movement is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    SELECT m.* INTO v_m FROM poultrymanualstockmovements m
    WHERE  m.movementid = p_movementid AND m.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Movement not found for this company.' USING ERRCODE = 'P0001'; END IF;
    IF v_m.status <> 'Posted' THEN
        RAISE EXCEPTION '% is already reversed.', v_m.movementno USING ERRCODE = 'P0001';
    END IF;
    v_note := left('Reversal of ' || v_m.movementno || ': ' || btrim(p_reason), 500);

    IF v_m.itemkind = 'Birds' THEN
        SELECT a.scope INTO v_scope FROM poultrybirdadjustments a WHERE a.birdadjustmentid = v_m.birdadjustmentid;
        v_scope := COALESCE(v_scope, CASE WHEN v_m.flockid IS NULL THEN 'BatchUnallocated' ELSE 'Flock' END);
        v_adj := sppoultrybirdmovement_post(p_farmid, v_scope, v_m.batchid, v_m.flockid, 'Reversal', (-v_m.quantity)::int,
                                            v_today, 'Reversal', v_note, 'ManualStockMovementReversal', v_m.movementid,
                                            NULL, p_by, v_m.birdadjustmentid);
        UPDATE poultrybirdadjustments a SET manualmovementid = v_m.movementid WHERE a.birdadjustmentid = v_adj;
        UPDATE poultrystocktransactions t
        SET    manualmovementid = v_m.movementid, manualreversal = TRUE
        WHERE  t.farmid = p_farmid AND t.txntype = 'Bird Adjustment' AND t.relatedid = v_adj;
    ELSIF v_m.itemkind = 'RawMaterial' THEN
        SELECT i.currentquantity INTO v_before FROM poultryrawmaterialitems i
        WHERE  i.poultryrawmaterialitemid = v_m.rawmaterialitemid AND i.farmid = p_farmid FOR UPDATE;
        IF v_before - v_m.quantity < 0 THEN
            RAISE EXCEPTION '% has only % on hand -- some of what % added has been used. Reverse that first.',
                v_m.itemname, trim_scale(v_before), v_m.movementno USING ERRCODE = 'P0001';
        END IF;
        SELECT x.poultryrawmaterialadjustmentid INTO v_raw
        FROM   sppoultryrawmaterialitem_adjust(p_farmid, v_m.rawmaterialitemid, -v_m.quantity, v_m.unitcost,
                                               'Reversal', v_note, p_by) x;
        UPDATE poultryrawmaterialadjustments a SET reason = 'Reversal', manualmovementid = v_m.movementid
        WHERE  a.poultryrawmaterialadjustmentid = v_raw;
    END IF;

    FOR r IN
        SELECT t.poultryproductid, t.txntype, SUM(t.quantity) AS qty, MAX(t.unitcost) AS unitcost
        FROM   poultrystocktransactions t
        WHERE  t.farmid = p_farmid AND t.manualmovementid = v_m.movementid AND NOT t.manualreversal
          AND  t.txntype <> 'Bird Adjustment'
        GROUP  BY t.poultryproductid, t.txntype
        HAVING SUM(t.quantity) <> 0
    LOOP
        SELECT COALESCE(SUM(t.quantity), 0) INTO v_before FROM poultrystocktransactions t
        WHERE  t.farmid = p_farmid AND t.poultryproductid = r.poultryproductid;
        INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby,
                                              batchid, flockid, effectivedate, reason, manualmovementid, manualreversal)
        VALUES (p_farmid, r.poultryproductid, r.txntype, -r.qty, r.unitcost, v_m.movementid, v_note, p_by,
                v_m.batchid, v_m.flockid, v_today, 'Reversal', v_m.movementid, TRUE);
        v_after := v_before - r.qty;
        IF v_after < 0 AND v_after < v_before THEN
            RAISE EXCEPTION 'Reversing % would leave % at % -- some of it has since been sold, used or disposed. Reverse that first.',
                v_m.movementno, (SELECT p.name FROM poultryproducts p WHERE p.poultryproductid = r.poultryproductid),
                trim_scale(v_after) USING ERRCODE = 'P0001';
        END IF;
    END LOOP;

    UPDATE poultrymanualstockmovements m
    SET    status = 'Reversed', reversedat = (now() AT TIME ZONE 'utc'), reversedby = p_by, reversalreason = btrim(p_reason),
           reversalbirdadjustmentid = v_adj, reversalrawadjustmentid = v_raw
    WHERE  m.movementid = v_m.movementid;

    RETURN jsonb_build_object('movementId', v_m.movementid, 'movementNo', v_m.movementno, 'status', 'Reversed');
END
$f$;

-- 'Historical Sale' and 'Transfer Out' join the manual-movement reasons.
CREATE OR REPLACE FUNCTION public.fnpoultrymanualmovement_reasons()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $f$
    SELECT ARRAY['Opening Inventory', 'Opening Bird Count', 'Historical Mortality', 'Historical Production',
                 'Stock Count Correction', 'Unrecorded Breakage', 'Cull', 'Historical Sale / Use', 'Disposal',
                 'Transfer Adjustment', 'Migration', 'Data Correction', 'Damage', 'Loss', 'Other',
                 'Historical Sale', 'Transfer Out'];
$f$;

-- The ledger list now says which pool a bird row touched.
DROP FUNCTION IF EXISTS public.sppoultrystock_gettransactions(text, integer);
CREATE FUNCTION public.sppoultrystock_gettransactions(p_farmid text, p_poultryproductid integer DEFAULT NULL::integer)
RETURNS TABLE(poultrystocktransactionid integer, farmid text, poultryproductid integer, txntype text, quantity numeric,
              unitcost numeric, relatedid integer, note text, createddate timestamp without time zone, createdby text,
              productname text,
              batchid integer, batchcode text, flockid integer, flockname text, effectivedate date, reason text,
              manualmovementid integer, manualreversal boolean,
              birdscope text)
LANGUAGE plpgsql AS $function$
BEGIN
    RETURN QUERY
    SELECT t.poultrystocktransactionid, t.farmid::text, t.poultryproductid, t.txntype::text,
           t.quantity, t.unitcost, t.relatedid, t.note::text, t.createddate, t.createdby::text,
           p.name::text AS productname,
           t.batchid, b.batchcode::text, t.flockid, f.name::text, t.effectivedate, t.reason,
           t.manualmovementid, t.manualreversal,
           t.birdscope
    FROM   poultrystocktransactions t
    INNER  JOIN poultryproducts p ON p.poultryproductid = t.poultryproductid
    LEFT   JOIN mainflockbatch b ON b.batchid = t.batchid
    LEFT   JOIN flock f ON f.flockid = t.flockid
    WHERE  t.farmid = p_farmid
       AND (p_poultryproductid IS NULL OR t.poultryproductid = p_poultryproductid)
    ORDER  BY t.createddate DESC, t.poultrystocktransactionid DESC;
END;
$function$;

-- ============================================== 7. flock-to-flock transfer ===
-- Two linked movements in one transaction: the company total does not move,
-- and neither batch's unplaced pool does (both are flock-scope).
CREATE OR REPLACE FUNCTION public.sppoultrybirdtransfer_post(
    p_farmid text, p_fromflockid integer, p_toflockid integer, p_quantity integer,
    p_effectivedate date DEFAULT NULL, p_note text DEFAULT NULL, p_requestkey text DEFAULT NULL, p_by text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    v_key   text := NULLIF(btrim(COALESCE(p_requestkey, '')), '');
    v_from  record;
    v_to    record;
    v_out   integer;
    v_in    integer;
BEGIN
    IF COALESCE(p_quantity, 0) <= 0 THEN
        RAISE EXCEPTION 'Enter how many birds move.' USING ERRCODE = 'P0001';
    END IF;
    IF p_fromflockid IS NULL OR p_toflockid IS NULL OR p_fromflockid = p_toflockid THEN
        RAISE EXCEPTION 'Choose two different flocks.' USING ERRCODE = 'P0001';
    END IF;
    SELECT f.flockid, f.batchid, f.name INTO v_from FROM flock f WHERE f.flockid = p_fromflockid AND f.farmid = p_farmid AND NOT f.isdeleted;
    IF NOT FOUND THEN RAISE EXCEPTION 'The source flock does not belong to this company.' USING ERRCODE = 'P0001'; END IF;
    SELECT f.flockid, f.batchid, f.name INTO v_to FROM flock f WHERE f.flockid = p_toflockid AND f.farmid = p_farmid AND NOT f.isdeleted;
    IF NOT FOUND THEN RAISE EXCEPTION 'The destination flock does not belong to this company.' USING ERRCODE = 'P0001'; END IF;

    v_out := sppoultrybirdmovement_post(p_farmid, 'Flock', v_from.batchid, v_from.flockid, 'Transfer', -p_quantity,
                 p_effectivedate, 'Transfer Out', COALESCE(p_note, '') || ' -> ' || v_to.name, 'FlockTransfer', NULL,
                 CASE WHEN v_key IS NOT NULL THEN v_key || ':out' END, p_by);
    v_in  := sppoultrybirdmovement_post(p_farmid, 'Flock', v_to.batchid, v_to.flockid, 'Transfer', p_quantity,
                 p_effectivedate, 'Transfer In', COALESCE(p_note, '') || ' <- ' || v_from.name, 'FlockTransfer', v_out,
                 CASE WHEN v_key IS NOT NULL THEN v_key || ':in' END, p_by);
    UPDATE poultrybirdadjustments a SET sourceid = v_in WHERE a.birdadjustmentid = v_out AND a.sourceid IS NULL;

    RETURN jsonb_build_object('outAdjustmentId', v_out, 'inAdjustmentId', v_in,
                              'farmLiveBirds', fnpoultry_farmlivebirds(p_farmid));
END
$f$;

-- ======================================== 8. batch bird reconciliation =======
-- p_lines: [{ "kind": "Sale"|"Mortality"|"Cull"|"TransferOut"|"StockCorrection"|"Other",
--             "quantity": 2000, "date": "2026-07-10", "note": "...",
--             "direction": "Decrease"|"Increase"   (StockCorrection only; default Decrease),
--             -- Sale only:
--             "flockId": null, "pricePerBird": 45, "valueUnknown": false,
--             "customerId": 12, "amountReceived": 60000, "createReceivable": true,
--             "linkDebtId": null, "reference": "INV-9", "classification": "PreCutover" }]
-- p_stillalive: birds the farm says are alive and still not in any flock AFTER
--               these lines.  The rest of the pool is UNEXPLAINED -- kept, never
--               turned into mortality to make the numbers balance.
CREATE OR REPLACE FUNCTION public.sppoultrybatchreconcile_post(
    p_farmid text, p_batchid integer, p_asofdate date, p_lines jsonb, p_stillalive integer,
    p_notes text DEFAULT NULL, p_source text DEFAULT 'Batch', p_requestkey text DEFAULT NULL, p_by text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    v_key      text := NULLIF(btrim(COALESCE(p_requestkey, '')), '');
    v_today    date := fncompany_businessdate(p_farmid);
    v_asof     date := COALESCE(p_asofdate, fncompany_businessdate(p_farmid));
    v_b        record;
    v_id       integer;
    v_no       text;
    v_before   integer;
    v_after    integer;
    v_line     jsonb;
    v_kind     text;
    v_qty      integer;
    v_date     date;
    v_reason   text;
    v_sign     integer;
    v_adj      integer;
    v_flock    record;
    v_price    numeric(14,2);
    v_total    numeric(14,2);
    v_recv     numeric(14,2);
    v_owed     numeric(14,2);
    v_unknown  boolean;
    v_cust     integer;
    v_debt     integer;
    v_created  boolean;
    v_treat    text;
    v_valued   integer;
    v_res      jsonb;
    v_i        integer := 0;
    v_removed  integer := 0;
    v_salebirds integer := 0;
    v_salevalue numeric(14,2) := 0;
    v_received numeric(14,2) := 0;
    v_owedall  numeric(14,2) := 0;
    v_debts    integer := 0;
BEGIN
    IF v_key IS NOT NULL THEN
        SELECT r.reconciliationid, r.reconciliationno INTO v_id, v_no FROM poultrybatchbirdreconciliations r
        WHERE  r.farmid = p_farmid AND r.requestkey = v_key;
        IF v_id IS NOT NULL THEN
            RETURN jsonb_build_object('reconciliationId', v_id, 'reconciliationNo', v_no, 'repeated', TRUE);
        END IF;
    END IF;

    SELECT b.batchid, b.batchcode, b.numberofbirds, b.startdate INTO v_b
    FROM   mainflockbatch b WHERE b.batchid = p_batchid AND b.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'That batch does not belong to this company.' USING ERRCODE = 'P0001';
    END IF;
    IF v_asof > v_today THEN
        RAISE EXCEPTION 'The as-of date (%) is in the future.', v_asof USING ERRCODE = 'P0001';
    END IF;
    IF COALESCE(p_stillalive, -1) < 0 THEN
        RAISE EXCEPTION 'Enter how many birds are still alive and not in any flock (0 if none).' USING ERRCODE = 'P0001';
    END IF;
    IF p_lines IS NOT NULL AND jsonb_typeof(p_lines) <> 'array' THEN
        RAISE EXCEPTION 'Lines must be a list.' USING ERRCODE = 'P0001';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('flock-alloc:' || p_farmid || ':' || p_batchid));
    v_before := fnpoultrybatch_unallocated(p_farmid, p_batchid);

    PERFORM pg_advisory_xact_lock(hashtext('poultry-batchrecon-no:' || p_farmid));
    SELECT 'BR-' || lpad((COALESCE(MAX(NULLIF(regexp_replace(r.reconciliationno, '\D', '', 'g'), '')::int), 0) + 1)::text, 5, '0')
    INTO   v_no FROM poultrybatchbirdreconciliations r WHERE r.farmid = p_farmid;

    INSERT INTO poultrybatchbirdreconciliations
        (farmid, batchid, reconciliationno, asofdate, source, unallocatedbefore, unallocatedafter,
         stillunallocatedlive, unexplainedbirds, status, notes, requestkey, createdby)
    VALUES
        (p_farmid, p_batchid, v_no, v_asof, COALESCE(NULLIF(btrim(COALESCE(p_source, '')), ''), 'Batch'),
         v_before, v_before, 0, 0, 'Unexplained', NULLIF(btrim(COALESCE(p_notes, '')), ''), v_key, p_by)
    RETURNING reconciliationid INTO v_id;

    FOR v_line IN SELECT * FROM jsonb_array_elements(COALESCE(p_lines, '[]'::jsonb))
    LOOP
        v_i    := v_i + 1;
        v_kind := v_line->>'kind';
        v_qty  := COALESCE(NULLIF(v_line->>'quantity', '')::numeric, 0)::int;
        IF v_qty = 0 THEN CONTINUE; END IF;
        IF v_qty < 0 OR (v_line->>'quantity')::numeric <> trunc((v_line->>'quantity')::numeric) THEN
            RAISE EXCEPTION 'Line %: birds are whole numbers greater than 0.', v_i USING ERRCODE = 'P0001';
        END IF;
        v_date := COALESCE(NULLIF(v_line->>'date', '')::date, v_asof);
        IF v_date > v_today THEN
            RAISE EXCEPTION 'Line %: the date % is in the future.', v_i, v_date USING ERRCODE = 'P0001';
        END IF;
        v_reason := CASE v_kind WHEN 'Sale' THEN 'Historical Sale' WHEN 'Mortality' THEN 'Historical Mortality'
                                WHEN 'Cull' THEN 'Cull' WHEN 'TransferOut' THEN 'Transfer Out'
                                WHEN 'StockCorrection' THEN 'Stock Count Correction' WHEN 'Other' THEN 'Other' END;
        IF v_reason IS NULL THEN
            RAISE EXCEPTION 'Line %: unknown kind "%".', v_i, v_kind USING ERRCODE = 'P0001';
        END IF;
        IF v_kind = 'Other' AND NULLIF(btrim(COALESCE(v_line->>'note', '')), '') IS NULL THEN
            RAISE EXCEPTION 'Line %: "Other" needs a note saying what happened.', v_i USING ERRCODE = 'P0001';
        END IF;
        v_sign := CASE WHEN v_kind = 'StockCorrection' AND v_line->>'direction' = 'Increase' THEN 1 ELSE -1 END;

        IF v_kind = 'Sale' AND NULLIF(v_line->>'flockId', '') IS NOT NULL THEN
            -- Sold AFTER placing: the birds already left through the flock's
            -- opening position.  This line only VALUES them -- no bird moves.
            SELECT f.flockid, f.name, o.historicalsold INTO v_flock
            FROM   flock f JOIN poultryopeningflockposition o ON o.flockid = f.flockid AND o.farmid = f.farmid
            WHERE  f.flockid = (v_line->>'flockId')::int AND f.farmid = p_farmid AND f.batchid = p_batchid;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Line %: that flock is not part of batch % or has no opening position. Sales from a flock are counted in the flock''s opening position.', v_i, v_b.batchcode USING ERRCODE = 'P0001';
            END IF;
            SELECT COALESCE(SUM(h.birds), 0) INTO v_valued FROM poultryhistoricalbirdsales h
            WHERE  h.farmid = p_farmid AND h.flockid = v_flock.flockid AND h.status = 'Posted';
            IF v_valued + v_qty > v_flock.historicalsold THEN
                RAISE EXCEPTION 'Line %: flock "%" recorded % birds sold before tracking; % are already valued, so % more cannot be.',
                    v_i, v_flock.name, v_flock.historicalsold, v_valued, v_qty USING ERRCODE = 'P0001';
            END IF;
            v_adj := NULL;
        ELSE
            v_adj := sppoultrybirdmovement_post(p_farmid, 'BatchUnallocated', p_batchid, NULL,
                         CASE WHEN v_sign < 0 THEN 'Decrease' ELSE 'Increase' END, v_sign * v_qty, v_date, v_reason,
                         left(v_no || COALESCE(' - ' || NULLIF(btrim(COALESCE(v_line->>'note', '')), ''), ''), 500),
                         'BatchReconciliation', v_id, NULL, p_by);
            v_removed := v_removed - v_sign * v_qty;
        END IF;

        IF v_kind = 'Sale' THEN
            IF COALESCE(v_line->>'classification', 'PreCutover') <> 'PreCutover' THEN
                RAISE EXCEPTION 'Line %: a sale in the current period belongs on Sales (record it there, back-dated), not in reconciliation.', v_i
                    USING ERRCODE = 'P0001';
            END IF;
            v_unknown := COALESCE((v_line->>'valueUnknown')::boolean, FALSE);
            v_cust    := NULLIF(v_line->>'customerId', '')::int;
            v_debt    := NULL;
            v_created := FALSE;
            IF v_cust IS NOT NULL AND NOT EXISTS (SELECT 1 FROM customer c WHERE c.customerid = v_cust AND c.farmid = p_farmid) THEN
                RAISE EXCEPTION 'Line %: that customer does not belong to this company.', v_i USING ERRCODE = 'P0001';
            END IF;
            IF v_unknown THEN
                v_price := NULL; v_total := NULL; v_recv := 0; v_owed := 0; v_treat := 'QuantityOnly';
            ELSE
                v_price := round(COALESCE(NULLIF(v_line->>'pricePerBird', '')::numeric, -1), 2);
                IF v_price < 0 THEN
                    RAISE EXCEPTION 'Line %: enter the selling price per bird, or mark the value as unknown.', v_i USING ERRCODE = 'P0001';
                END IF;
                v_total := round(v_qty * v_price, 2);
                v_recv  := round(COALESCE(NULLIF(v_line->>'amountReceived', '')::numeric, v_total), 2);
                IF v_recv < 0 OR v_recv > v_total THEN
                    RAISE EXCEPTION 'Line %: amount received (%) must be between 0 and the sale value (%).', v_i, v_recv, v_total
                        USING ERRCODE = 'P0001';
                END IF;
                v_owed := v_total - v_recv;
                IF v_owed = 0 THEN
                    v_treat := 'HistoricalPaid';
                ELSIF COALESCE((v_line->>'createReceivable')::boolean, FALSE) OR NULLIF(v_line->>'linkDebtId', '') IS NOT NULL THEN
                    IF v_cust IS NULL THEN
                        RAISE EXCEPTION 'Line %: choose the customer who still owes %.', v_i, v_owed USING ERRCODE = 'P0001';
                    END IF;
                    IF NULLIF(v_line->>'linkDebtId', '') IS NOT NULL THEN
                        -- Already recorded as an opening debt: link it, never a second one.
                        SELECT d.debtid INTO v_debt FROM poultrycustomerdebts d
                        WHERE  d.debtid = (v_line->>'linkDebtId')::int AND d.farmid = p_farmid
                          AND  d.customerid = v_cust AND d.status = 'Posted';
                        IF v_debt IS NULL THEN
                            RAISE EXCEPTION 'Line %: that debt is not a posted debt of this customer.', v_i USING ERRCODE = 'P0001';
                        END IF;
                        IF (SELECT d.amount FROM poultrycustomerdebts d WHERE d.debtid = v_debt) <> v_owed THEN
                            RAISE EXCEPTION 'Line %: that debt is for %, but this sale still has % owing.', v_i,
                                (SELECT d.amount FROM poultrycustomerdebts d WHERE d.debtid = v_debt), v_owed USING ERRCODE = 'P0001';
                        END IF;
                    ELSE
                        v_res := sppoultrycustomerdebt_create(p_farmid, v_cust, v_owed, v_date, 'HistoricalDebt',
                                     'Historical bird sale - batch ' || v_b.batchcode || ', ' || v_qty || ' birds on ' || v_date,
                                     NULLIF(btrim(COALESCE(v_line->>'reference', '')), ''),
                                     v_no || COALESCE(' - ' || NULLIF(btrim(COALESCE(v_line->>'note', '')), ''), ''), p_by);
                        v_debt := (v_res->>'debtId')::int;
                        v_created := TRUE;
                        v_debts := v_debts + 1;
                    END IF;
                    v_treat := 'HistoricalReceivable';
                ELSE
                    v_treat := 'HistoricalUnpaidNotTracked';
                END IF;
            END IF;

            INSERT INTO poultryhistoricalbirdsales
                (farmid, batchid, flockid, scope, reconciliationid, saledate, birds, priceperbird, totalvalue,
                 valueunknown, customerid, amountreceived, amountowed, classification, financialtreatment,
                 debtid, debtcreated, birdadjustmentid, reference, notes, createdby)
            VALUES
                (p_farmid, p_batchid, NULLIF(v_line->>'flockId', '')::int,
                 CASE WHEN NULLIF(v_line->>'flockId', '') IS NULL THEN 'BatchUnallocated' ELSE 'Flock' END,
                 v_id, v_date, v_qty, v_price, v_total, v_unknown, v_cust, v_recv, v_owed, 'PreCutover', v_treat,
                 v_debt, v_created, v_adj, NULLIF(btrim(COALESCE(v_line->>'reference', '')), ''),
                 NULLIF(btrim(COALESCE(v_line->>'note', '')), ''), p_by);

            v_salebirds := v_salebirds + v_qty;
            v_salevalue := v_salevalue + COALESCE(v_total, 0);
            v_received  := v_received + v_recv;
            v_owedall   := v_owedall + v_owed;
        END IF;
    END LOOP;

    v_after := fnpoultrybatch_unallocated(p_farmid, p_batchid);
    IF p_stillalive > v_after THEN
        RAISE EXCEPTION 'After these entries batch % has % birds not in any flock, so % cannot still be alive there.',
            v_b.batchcode, v_after, p_stillalive USING ERRCODE = 'P0001';
    END IF;

    UPDATE poultrybatchbirdreconciliations r
    SET    removedbirds = v_removed, unallocatedafter = v_after, stillunallocatedlive = p_stillalive,
           unexplainedbirds = v_after - p_stillalive,
           status = CASE WHEN v_after - p_stillalive = 0 THEN 'Reconciled' ELSE 'Unexplained' END
    WHERE  r.reconciliationid = v_id;

    RETURN jsonb_build_object(
        'reconciliationId', v_id, 'reconciliationNo', v_no, 'repeated', FALSE,
        'unallocatedBefore', v_before, 'removedBirds', v_removed, 'unallocatedAfter', v_after,
        'stillUnallocatedLive', p_stillalive, 'unexplainedBirds', v_after - p_stillalive,
        'status', CASE WHEN v_after - p_stillalive = 0 THEN 'Reconciled' ELSE 'Unexplained' END,
        'historicalSaleBirds', v_salebirds, 'historicalSaleValue', v_salevalue,
        'historicalReceived', v_received, 'historicalOwed', v_owedall, 'debtsCreated', v_debts,
        -- Stated, so a caller can show it: a reconciliation never moves money.
        'newCashMovement', 0, 'currentPeriodRevenue', 0, 'currentPeriodExpense', 0);
END
$f$;

-- Undo one posting: birds go back to the batch pool, debts it created are
-- reversed (refused if anything has been paid on them), sales marked Reversed.
CREATE OR REPLACE FUNCTION public.sppoultrybatchreconcile_reverse(
    p_farmid text, p_reconciliationid integer, p_reason text, p_by text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
    v_r    record;
    a      record;
    h      record;
    v_n    integer := 0;
BEGIN
    IF NULLIF(btrim(COALESCE(p_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Say why this reconciliation is being reversed.' USING ERRCODE = 'P0001';
    END IF;
    SELECT r.* INTO v_r FROM poultrybatchbirdreconciliations r
    WHERE  r.reconciliationid = p_reconciliationid AND r.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Reconciliation not found for this company.' USING ERRCODE = 'P0001'; END IF;
    IF v_r.status = 'Reversed' THEN
        RAISE EXCEPTION '% is already reversed.', v_r.reconciliationno USING ERRCODE = 'P0001';
    END IF;

    FOR a IN
        SELECT x.* FROM poultrybirdadjustments x
        WHERE  x.farmid = p_farmid AND x.sourcetype = 'BatchReconciliation' AND x.sourceid = v_r.reconciliationid
          AND  x.reversedbyid IS NULL
        ORDER  BY x.birdadjustmentid DESC
    LOOP
        -- An increase being undone needs the birds to still be in the pool; the
        -- movement function refuses if they have since been placed in a flock.
        PERFORM sppoultrybirdmovement_post(p_farmid, 'BatchUnallocated', a.batchid, NULL, 'Reversal', -a.quantity,
                    fncompany_businessdate(p_farmid), 'Reversal',
                    'Reversal of ' || v_r.reconciliationno || ': ' || btrim(p_reason),
                    'BatchReconciliationReversal', v_r.reconciliationid, NULL, p_by, a.birdadjustmentid);
        v_n := v_n + 1;
    END LOOP;

    FOR h IN
        SELECT x.* FROM poultryhistoricalbirdsales x
        WHERE  x.farmid = p_farmid AND x.reconciliationid = v_r.reconciliationid AND x.status = 'Posted'
    LOOP
        IF h.debtcreated AND h.debtid IS NOT NULL THEN
            PERFORM sppoultrycustomerdebt_reverse(p_farmid, h.debtid,
                        'Reversal of ' || v_r.reconciliationno || ': ' || btrim(p_reason), p_by);
        END IF;
        UPDATE poultryhistoricalbirdsales x SET status = 'Reversed', reversedat = (now() AT TIME ZONE 'utc'), reversedby = p_by
        WHERE  x.historicalsaleid = h.historicalsaleid;
    END LOOP;

    UPDATE poultrybatchbirdreconciliations r
    SET    status = 'Reversed', reversedat = (now() AT TIME ZONE 'utc'), reversedby = p_by, reversalreason = btrim(p_reason)
    WHERE  r.reconciliationid = v_r.reconciliationid;

    RETURN jsonb_build_object('reconciliationId', v_r.reconciliationid, 'reconciliationNo', v_r.reconciliationno,
                              'status', 'Reversed', 'movementsReversed', v_n,
                              'unallocatedNow', fnpoultrybatch_unallocated(p_farmid, v_r.batchid));
END
$f$;

-- One row per batch: where every bird bought went.
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

-- Drilldown: the batch, its flocks, every batch-level movement, historical
-- sales and reconciliation postings.
CREATE OR REPLACE FUNCTION public.sppoultrybatchreconcile_detail(p_farmid text, p_batchid integer)
RETURNS jsonb LANGUAGE sql STABLE AS $f$
    SELECT jsonb_build_object(
        'summary', (SELECT to_jsonb(s) FROM sppoultrybatchreconcile_summary(p_farmid) s WHERE s.batchid = p_batchid),
        'flocks', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'flockId', f.flockid, 'flockName', f.name, 'isClosed', f.closeddate IS NOT NULL,
                       'isDeleted', f.isdeleted,
                       'originallyPlaced', bp.originallyplaced, 'hasOpeningPosition', bp.hasopeningposition,
                       'historicalMortality', bp.openingmortality, 'historicalSold', bp.openingsold,
                       'historicalCulled', bp.openingculled, 'historicalTransferred', bp.openingtransferred,
                       'historicalOther', bp.openingother, 'openingLiveBirds', bp.openinglivebirds,
                       'recordedMortality', bp.recordedmortality, 'birdsSold', bp.birdssold,
                       'birdsCulled', bp.birdsculled, 'birdsTransferred', bp.birdstransferred,
                       'productionRecordCount', bp.productionrecordcount,
                       'quantityAdjustments', fnflock_quantityadjustments(p_farmid, f.flockid),
                       'currentLiveBirds', bp.currentlivebirds) ORDER BY f.name)
            FROM flock f CROSS JOIN LATERAL fnflock_birdposition(p_farmid, f.flockid) bp
            WHERE f.farmid = p_farmid AND f.batchid = p_batchid), '[]'::jsonb),
        'movements', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'birdAdjustmentId', a.birdadjustmentid, 'date', a.adjustmentdate, 'scope', a.scope,
                       'appliedTo', a.appliedto, 'flockId', a.flockid, 'flockName', f.name,
                       'reason', a.reason, 'movementType', a.movementtype, 'quantity', a.quantity,
                       'birdsBefore', a.birdsbefore, 'birdsAfter', a.birdsafter, 'note', a.note,
                       'sourceType', a.sourcetype, 'sourceId', a.sourceid,
                       'reversesId', a.reversesid, 'reversedById', a.reversedbyid,
                       'createdBy', a.createdby, 'createdAt', a.createdat) ORDER BY a.adjustmentdate DESC, a.birdadjustmentid DESC)
            FROM poultrybirdadjustments a LEFT JOIN flock f ON f.flockid = a.flockid
            WHERE a.farmid = p_farmid AND a.batchid = p_batchid), '[]'::jsonb),
        'historicalSales', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'historicalSaleId', h.historicalsaleid, 'saleDate', h.saledate, 'scope', h.scope,
                       'flockId', h.flockid, 'flockName', f.name, 'birds', h.birds, 'pricePerBird', h.priceperbird,
                       'totalValue', h.totalvalue, 'valueUnknown', h.valueunknown, 'customerId', h.customerid,
                       'customerName', c.name, 'amountReceived', h.amountreceived, 'amountOwed', h.amountowed,
                       'financialTreatment', h.financialtreatment, 'debtId', h.debtid, 'debtNumber', d.debtnumber,
                       'debtCreated', h.debtcreated, 'reference', h.reference, 'notes', h.notes, 'status', h.status,
                       'reconciliationId', h.reconciliationid) ORDER BY h.saledate, h.historicalsaleid)
            FROM poultryhistoricalbirdsales h
            LEFT JOIN flock f ON f.flockid = h.flockid
            LEFT JOIN customer c ON c.customerid = h.customerid
            LEFT JOIN poultrycustomerdebts d ON d.debtid = h.debtid
            WHERE h.farmid = p_farmid AND h.batchid = p_batchid), '[]'::jsonb),
        'reconciliations', COALESCE((
            SELECT jsonb_agg(to_jsonb(r) ORDER BY r.reconciliationid DESC)
            FROM poultrybatchbirdreconciliations r
            WHERE r.farmid = p_farmid AND r.batchid = p_batchid), '[]'::jsonb));
$f$;

-- ================================================== 9. repair ================
-- Read only.  Each row: what is wrong, the evidence, the proposed fix, and
-- whether sppoultrybirdrepair_apply will make it (Verified + metadata only).
CREATE OR REPLACE FUNCTION public.fnpoultrybirdrepair_diagnose(p_farmid text DEFAULT NULL)
RETURNS TABLE(farmid text, checkcode text, severity text, ledgerrowid integer, openingpositionid integer,
              batchid integer, flockid integer, flockname text, currentvalue text, expectedvalue text,
              missingrelationship text, proposedcorrection text, doubleapplicationrisk text,
              confidence text, evidence text, autorepairable boolean)
LANGUAGE sql STABLE AS $f$
    -- R1: opening ledger rows without batch / flock, resolvable by relatedid.
    SELECT t.farmid::text, 'OPENING_LEDGER_UNLINKED', 'Fix',
           t.poultrystocktransactionid, o.openingpositionid, f.batchid, o.flockid, f.name::text,
           'batch=' || COALESCE(t.batchid::text, 'null') || ', flock=' || COALESCE(t.flockid::text, 'null'),
           'batch=' || COALESCE(f.batchid::text, '?') || ', flock=' || COALESCE(o.flockid::text, '?'),
           'BatchId / FlockId / effective date / reason on the ledger row',
           'Set the link only. Quantity unchanged.',
           'None: no quantity is posted; the flock''s birds already equal the opening live count.',
           CASE WHEN f.flockid IS NOT NULL THEN 'Verified' ELSE 'Unresolved' END,
           'relatedid ' || t.relatedid || ' = opening position ' || COALESCE(o.openingpositionid::text, 'NOT FOUND')
             || COALESCE(' of flock "' || f.name || '"', ''),
           f.flockid IS NOT NULL
    FROM   poultrystocktransactions t
    LEFT   JOIN poultryopeningflockposition o ON o.openingpositionid = t.relatedid AND o.farmid = t.farmid
    LEFT   JOIN flock f ON f.flockid = o.flockid AND f.farmid = o.farmid
    WHERE  t.txntype = 'Opening Adjustment' AND (t.batchid IS NULL OR t.flockid IS NULL)
      AND  (p_farmid IS NULL OR t.farmid = p_farmid)
    UNION ALL
    -- R2: bird-adjustment ledger rows without their batch.
    SELECT t.farmid::text, 'BIRD_ADJUSTMENT_LEDGER_UNLINKED', 'Fix',
           t.poultrystocktransactionid, NULL, a.batchid, a.flockid, f.name::text,
           'batch=' || COALESCE(t.batchid::text, 'null'), 'batch=' || COALESCE(a.batchid::text, '?'),
           'BatchId / FlockId / scope on the ledger row', 'Set the link only. Quantity unchanged.', 'None',
           CASE WHEN a.birdadjustmentid IS NOT NULL THEN 'Verified' ELSE 'Unresolved' END,
           'relatedid ' || t.relatedid || ' = bird adjustment ' || COALESCE(a.birdadjustmentid::text, 'NOT FOUND'),
           a.birdadjustmentid IS NOT NULL
    FROM   poultrystocktransactions t
    LEFT   JOIN poultrybirdadjustments a ON a.birdadjustmentid = t.relatedid AND a.farmid = t.farmid
    LEFT   JOIN flock f ON f.flockid = a.flockid
    WHERE  t.txntype = 'Bird Adjustment' AND (t.batchid IS NULL OR t.birdscope IS NULL)
      AND  (p_farmid IS NULL OR t.farmid = p_farmid)
    UNION ALL
    -- R3: batch purchase ledger rows without their batch.
    SELECT t.farmid::text, 'BATCH_PURCHASE_LEDGER_UNLINKED', 'Fix',
           t.poultrystocktransactionid, NULL, b.batchid, NULL, NULL,
           'batch=null', 'batch=' || COALESCE(b.batchid::text, '?'),
           'BatchId on the purchase ledger row', 'Set the link only. Quantity unchanged.', 'None',
           CASE WHEN b.batchid IS NOT NULL THEN 'Verified' ELSE 'Unresolved' END,
           'relatedid ' || t.relatedid || ' = batch ' || COALESCE(b.batchcode::text, 'NOT FOUND'),
           b.batchid IS NOT NULL
    FROM   poultrystocktransactions t
    LEFT   JOIN mainflockbatch b ON b.batchid = t.relatedid AND b.farmid = t.farmid
    WHERE  t.txntype = 'Bird Batch Purchase' AND t.batchid IS NULL
      AND  (p_farmid IS NULL OR t.farmid = p_farmid)
    UNION ALL
    -- R4: the ledger does not net to the opening position's reduction
    -- (recorded twice, restated without the ledger, or never posted).
    SELECT o.farmid, CASE WHEN COALESCE(l.n, 0) = 0 THEN 'OPENING_LEDGER_MISSING' ELSE 'OPENING_LEDGER_MISMATCH' END, 'Review',
           NULL, o.openingpositionid, f.batchid, o.flockid, f.name::text,
           'ledger nets ' || COALESCE(l.net, 0), 'should net ' || -(o.originallyplaced - o.openinglivebirds),
           NULL,
           'Re-post through sppoultryopeningbirdstock_post (delta only) after checking no manual bird adjustment already compensated.',
           CASE WHEN EXISTS (SELECT 1 FROM poultrybirdadjustments a WHERE a.farmid = o.farmid AND a.flockid = o.flockid)
                THEN 'HIGH: this flock also has manual bird adjustments.' ELSE 'Low' END,
           'Review', 'opening position ' || o.openingpositionid || ': placed ' || o.originallyplaced || ', opening live ' || o.openinglivebirds,
           FALSE
    FROM   poultryopeningflockposition o
    JOIN   flock f ON f.flockid = o.flockid AND f.farmid = o.farmid
    LEFT   JOIN LATERAL (SELECT COUNT(*) AS n, SUM(t.quantity) AS net FROM poultrystocktransactions t
                         WHERE t.farmid = o.farmid AND t.txntype = 'Opening Adjustment' AND t.relatedid = o.openingpositionid) l ON TRUE
    WHERE  COALESCE(l.net, 0) <> -(o.originallyplaced - o.openinglivebirds)
      AND  (p_farmid IS NULL OR o.farmid = p_farmid)
    UNION ALL
    -- R5: a flock with no production record whose count is not its opening live
    -- birds plus its own adjustments -- the historical reduction did not land.
    SELECT o.farmid, 'OPENING_FLOCK_NOT_REDUCED', 'Review', NULL, o.openingpositionid, f.batchid, f.flockid, f.name::text,
           'flock quantity ' || f.quantity, 'expected ' || (o.openinglivebirds + fnflock_quantityadjustments(o.farmid, f.flockid)),
           NULL, 'Check whether the quantity was edited on purpose on the Flocks page before correcting.',
           'Medium: an intended edit would be undone.', 'Review',
           'opening position ' || o.openingpositionid || ' says ' || o.openinglivebirds || ' live',
           FALSE
    FROM   poultryopeningflockposition o
    JOIN   flock f ON f.flockid = o.flockid AND f.farmid = o.farmid
    WHERE  NOT f.isdeleted
      AND  NOT EXISTS (SELECT 1 FROM productionrecords r WHERE r.farmid = f.farmid AND r.flockid = f.flockid)
      AND  f.quantity <> o.openinglivebirds + fnflock_quantityadjustments(o.farmid, f.flockid)
      AND  (p_farmid IS NULL OR o.farmid = p_farmid)
    UNION ALL
    -- R6 / R7: batches whose birds do not add up.
    SELECT p.farmid, CASE WHEN s.status = 'OverAllocated' THEN 'BATCH_OVER_ALLOCATED' ELSE 'BATCH_UNEXPLAINED_BIRDS' END,
           CASE WHEN s.status = 'OverAllocated' THEN 'Review' ELSE 'Info' END,
           NULL, NULL, s.batchid, NULL, NULL,
           'unexplained ' || s.unexplained, 'unexplained 0', NULL,
           CASE WHEN s.status = 'OverAllocated' THEN 'More birds were placed than the batch holds: correct the batch size or a flock.'
                ELSE 'Reconcile the batch (Batch Bird Reconciliation).' END,
           'None', 'Review', 'batch ' || s.batchcode || ': ' || s.originalbirds || ' bought, ' || s.originallyallocated || ' placed, '
             || s.unallocatedpool || ' not in a flock', FALSE
    FROM   (SELECT DISTINCT b.farmid::text AS farmid FROM mainflockbatch b WHERE p_farmid IS NULL OR b.farmid = p_farmid) p
    CROSS  JOIN LATERAL sppoultrybatchreconcile_summary(p.farmid) s
    WHERE  s.status <> 'FullyAccountedFor'
    UNION ALL
    -- R8: other bird ledger rows with no batch.  Their relatedid does not
    -- reliably identify a flock (only 32 of 60 Mortality rows match a live
    -- production record), so they are reported, never guessed.
    SELECT t.farmid::text, 'LEGACY_BIRD_ROW_UNLINKED', 'Info', t.poultrystocktransactionid, NULL, NULL, NULL, NULL,
           t.txntype || ' ' || t.quantity, NULL, 'BatchId / FlockId', 'Left as is (cannot be proven).', 'n/a', 'Unresolved',
           COALESCE(t.note, ''), FALSE
    FROM   poultrystocktransactions t
    JOIN   poultryproducts p ON p.poultryproductid = t.poultryproductid
    WHERE  (COALESCE(p.isbirdproduct, FALSE) OR p.name = 'Birds') AND p.systemrole IS NULL
      AND  t.batchid IS NULL
      AND  t.txntype NOT IN ('Opening Adjustment', 'Bird Adjustment', 'Bird Batch Purchase')
      AND  (p_farmid IS NULL OR t.farmid = p_farmid);
$f$;

-- Applies the Verified, metadata-only fixes (R1-R3).  p_dryrun = TRUE reports
-- what it would change and changes nothing.  Re-running changes nothing.
CREATE OR REPLACE FUNCTION public.sppoultrybirdrepair_apply(p_farmid text, p_by text DEFAULT NULL, p_dryrun boolean DEFAULT TRUE)
RETURNS TABLE(checkcode text, ledgerrowid integer, batchid integer, flockid integer, applied boolean, evidence text)
LANGUAGE plpgsql AS $f$
DECLARE
    r record;
BEGIN
    IF p_farmid IS NULL THEN
        RAISE EXCEPTION 'Repair runs one company at a time.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('poultry-birdrepair:' || p_farmid));

    FOR r IN
        SELECT d.* FROM fnpoultrybirdrepair_diagnose(p_farmid) d
        WHERE  d.autorepairable AND d.confidence = 'Verified'
          AND  d.checkcode IN ('OPENING_LEDGER_UNLINKED', 'BIRD_ADJUSTMENT_LEDGER_UNLINKED', 'BATCH_PURCHASE_LEDGER_UNLINKED')
    LOOP
        checkcode := r.checkcode; ledgerrowid := r.ledgerrowid; batchid := r.batchid; flockid := r.flockid;
        evidence := r.evidence; applied := NOT p_dryrun;
        IF NOT p_dryrun THEN
            INSERT INTO poultrybirdrepairlog (farmid, checkcode, tablename, rowid, beforevalues, aftervalues, evidence, repairedby)
            SELECT p_farmid, r.checkcode, 'poultrystocktransactions', t.poultrystocktransactionid,
                   jsonb_build_object('batchid', t.batchid, 'flockid', t.flockid, 'effectivedate', t.effectivedate,
                                      'reason', t.reason, 'birdscope', t.birdscope),
                   jsonb_build_object('batchid', r.batchid, 'flockid', r.flockid), r.evidence, p_by
            FROM   poultrystocktransactions t WHERE t.poultrystocktransactionid = r.ledgerrowid;

            IF r.checkcode = 'OPENING_LEDGER_UNLINKED' THEN
                UPDATE poultrystocktransactions t
                SET    batchid = r.batchid, flockid = r.flockid, birdscope = 'Flock',
                       effectivedate = COALESCE(t.effectivedate, o.effectivebusinessdate),
                       reason = COALESCE(t.reason, 'Opening Historical Reduction')
                FROM   poultryopeningflockposition o
                WHERE  t.poultrystocktransactionid = r.ledgerrowid AND o.openingpositionid = r.openingpositionid;
            ELSIF r.checkcode = 'BIRD_ADJUSTMENT_LEDGER_UNLINKED' THEN
                UPDATE poultrystocktransactions t
                SET    batchid = a.batchid, flockid = a.flockid, birdscope = a.scope,
                       effectivedate = COALESCE(t.effectivedate, a.adjustmentdate), reason = COALESCE(t.reason, a.reason)
                FROM   poultrybirdadjustments a
                WHERE  t.poultrystocktransactionid = r.ledgerrowid AND a.birdadjustmentid = t.relatedid AND a.farmid = t.farmid;
            ELSE
                UPDATE poultrystocktransactions t SET batchid = r.batchid
                WHERE  t.poultrystocktransactionid = r.ledgerrowid;
            END IF;
        END IF;
        RETURN NEXT;
    END LOOP;
END
$f$;

-- ============================================================ 10. grants =====
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT SELECT, INSERT, UPDATE ON public.poultrybatchbirdreconciliations TO poultryapp;
        GRANT SELECT, INSERT, UPDATE ON public.poultryhistoricalbirdsales TO poultryapp;
        GRANT SELECT, INSERT ON public.poultrybirdrepairlog TO poultryapp;
        GRANT SELECT, INSERT, UPDATE ON public.poultrybirdadjustments TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.fnpoultrybird_decreasereasons() TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.spflock_getconsumedforbatch(integer, text, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.fnflock_quantityadjustments(text, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.fnflock_birdposition(text, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.fnpoultrybatch_unallocated(text, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultrybirdmovement_post(text, text, integer, integer, text, integer, date, text, text, text, integer, text, text, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultrybirdadjustment_post(text, integer, integer, text, integer, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultrybirdadjustment_getall(text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryopeningbirdstock_post(text, integer, integer, date, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultrymanualmovement_post(text, integer, integer, text, numeric, numeric, integer, integer, date, text, text, text, text, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultrymanualmovement_reverse(text, integer, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.fnpoultrymanualmovement_reasons() TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultrystock_gettransactions(text, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultrybirdtransfer_post(text, integer, integer, integer, date, text, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultrybatchreconcile_post(text, integer, date, jsonb, integer, text, text, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultrybatchreconcile_reverse(text, integer, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultrybatchreconcile_summary(text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultrybatchreconcile_detail(text, integer) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.fnpoultrybirdrepair_diagnose(text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultrybirdrepair_apply(text, text, boolean) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- ======================================================= 11. verification ====
-- Read-only checks.  The behavioural tests are in
-- 413_PoultryBirdReconciliation_tests.sql (fixture farm, always rolled back).
DO $$
DECLARE
    v_missing text;
    v_bad     integer;
BEGIN
    SELECT string_agg(want, ', ') INTO v_missing
    FROM   (VALUES ('sppoultrybirdmovement_post'), ('sppoultrybatchreconcile_post'), ('sppoultrybatchreconcile_reverse'),
                   ('sppoultrybatchreconcile_summary'), ('sppoultrybatchreconcile_detail'), ('sppoultrybirdtransfer_post'),
                   ('fnpoultrybirdrepair_diagnose'), ('sppoultrybirdrepair_apply'), ('fnpoultrybatch_unallocated'),
                   ('fnflock_quantityadjustments')) AS w(want)
    WHERE  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                       WHERE n.nspname = 'public' AND p.proname = w.want);
    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '413: missing function(s): %', v_missing;
    END IF;

    -- No flock exists yet with a FlockQuantity adjustment, so every flock's
    -- position must be exactly what 406 computed.  originallyplaced for a flock
    -- without an opening position is still its quantity.
    SELECT COUNT(*) INTO v_bad
    FROM   flock f CROSS JOIN LATERAL fnflock_birdposition(f.farmid, f.flockid) bp
    WHERE  NOT bp.hasopeningposition AND bp.originallyplaced <> COALESCE(f.quantity, 0)
      AND  fnflock_quantityadjustments(f.farmid, f.flockid) = 0;
    IF v_bad > 0 THEN
        RAISE EXCEPTION '413: % flock(s) changed originallyplaced without any adjustment.', v_bad;
    END IF;

    RAISE NOTICE '413_PoultryBirdReconciliation: verified.';
END $$;
