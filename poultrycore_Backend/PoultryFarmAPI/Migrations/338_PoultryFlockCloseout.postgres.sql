-- =============================================================================
-- 338  End-of-flock closeout (spent-layer disposal)
-- =============================================================================
--
-- WHAT THIS IS
-- ------------
-- A controlled way to END a flock's operational life, replacing the only
-- mechanism that existed: flipping flock.active off and typing a reason. That
-- toggle recorded nothing about where the birds went, could be flipped straight
-- back on by the edit form (or by the Flocks page's auto-activate sweep), and
-- the other way people "closed" a flock -- deleting it -- destroyed history.
--
-- A closeout is:
--   1. a RECONCILIATION of the flock's birds, derived, never typed;
--   2. DISPOSITIONS that account for every live bird still on hand: sold
--      (through the ordinary sale, which the C# layer creates with the existing
--      SaleService -- this migration writes no sale rows), culled, or
--      transferred off the farm;
--   3. the flock marked closed (active = false, plus who/when/why), which
--      releases its house because occupancy is derived from ACTIVE flocks only.
--      flock.houseid is deliberately kept, so the flock-house history survives.
--
-- THE BIRD AUTHORITY (fnflock_birdposition)
-- -----------------------------------------
-- Birds are NOT read from the stock ledger (see 325): the flock plus its
-- production records are the authority. This migration keeps that and makes
-- every figure explicit:
--
--   originally placed          opening position, else flock.quantity
--   - opening historical       mortality / sold / culled / transferred / other,
--                              known only when Initial Farm Setup recorded them
--   = opening live birds       flock.quantity -- what the flock started life with
--   - recorded mortality       SUM(productionrecords.mortality)
--   +/- count corrections      the part of the last count that recorded
--                              mortality does not explain (re-counts, legacy
--                              imports, a sale someone deducted by hand)
--   = last counted birds       noofbirdsleft on the latest production record
--   - birds sold               bird sales tagged to this flock
--   - culled                   closeout dispositions
--   - transferred              closeout dispositions
--   = current live birds
--
-- "birds sold" is ALL flock-tagged bird sales, because a sale has never moved
-- the flock's count (sales page, "which is why a bird sale does not move that
-- number"). The correction line is where a hand-made deduction would surface,
-- so it is visible rather than silently double counted.
--
-- A flock closes only when current live birds is EXACTLY zero. Nothing here
-- will invent mortality to get there: unrecorded deaths must be recorded as
-- mortality on a production record first, which is a real event with a date.
--
-- WHAT IS NOT DONE, deliberately
-- ------------------------------
-- * Transfer means birds LEAVING the company (another farm, a sister site).
--   A flock-to-flock transfer inside the company would need the receiving
--   flock's count to rise, and that count is its own production records, not
--   something this migration can raise without faking one. Birds changing
--   house within the same flock are not a closeout at all -- edit the house.
-- * No "Other" disposition. Every other way a bird leaves is already modelled
--   (mortality, sale), and an open-ended bucket is exactly the fake-mortality
--   hole the requirement rules out.
--
-- GUARDS
-- ------
-- Triggers stop a closed flock from being changed behind the closeout's back:
-- re-activated by the edit form, deleted, given new production records or feed
-- usage, or having the bird sales that closed it edited or deleted. Each says
-- "reopen the flock first". Reopening is its own audited function.
--
-- EFFECT ON TODAY'S NUMBERS: none. No flock is closed by this migration; every
-- guard only fires on a flock with closeddate set, and none has one yet.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. The flock carries its closed state
-- ---------------------------------------------------------------------------
-- A mirror of the open closeout, so every reader can tell a closed flock from a
-- merely inactive one without a join. closeddate is the BUSINESS date (the
-- company's calendar day), closedat the instant it was done -- the two are not
-- substitutes for each other (timezone programme, 298).
ALTER TABLE flock ADD COLUMN IF NOT EXISTS closeddate  date;
ALTER TABLE flock ADD COLUMN IF NOT EXISTS closedat    timestamp without time zone;
ALTER TABLE flock ADD COLUMN IF NOT EXISTS closedby    text;
ALTER TABLE flock ADD COLUMN IF NOT EXISTS closereason text;
ALTER TABLE flock ADD COLUMN IF NOT EXISTS closeoutid  integer;

-- ---------------------------------------------------------------------------
-- 2. The closeout record and its dispositions
-- ---------------------------------------------------------------------------
-- Append-only in spirit: reopening does not delete the closeout, it stamps
-- reopenedat/by/reason on it. Closing again writes a NEW row. So the table is
-- the flock's full close/reopen history.
CREATE TABLE IF NOT EXISTS flockcloseouts (
    closeoutid             serial PRIMARY KEY,
    farmid                 text        NOT NULL,
    flockid                integer     NOT NULL,
    closeddate             date        NOT NULL,
    reason                 text        NOT NULL,
    notes                  text,
    closedby               text        NOT NULL,
    closedat               timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    -- What the flock looked like before it was closed, so a reopen restores
    -- a legacy-inactive flock to inactive rather than promoting it to active.
    wasactive              boolean     NOT NULL,
    -- The house it was released from. flock.houseid keeps it too; this is the
    -- record that the release happened.
    houseid                integer,

    -- Reconciliation snapshot, frozen at close. The live figures are always
    -- re-derivable; this is what the person saw and signed off.
    hasopeningposition     boolean     NOT NULL,
    historyknown           boolean     NOT NULL,
    originallyplaced       integer     NOT NULL,
    openingmortality       integer     NOT NULL,
    openingsold            integer     NOT NULL,
    openingculled          integer     NOT NULL,
    openingtransferred     integer     NOT NULL,
    openingother           integer     NOT NULL,
    openinglivebirds       integer     NOT NULL,
    recordedmortality      integer     NOT NULL,
    correction             integer     NOT NULL,
    lastcountedbirds       integer     NOT NULL,
    lastcountdate          date,
    soldbeforecloseout     integer     NOT NULL,
    livebirdsatcloseout    integer     NOT NULL,
    disposedsold           integer     NOT NULL,
    disposedculled         integer     NOT NULL,
    disposedtransferred    integer     NOT NULL,

    reopenedat             timestamp without time zone,
    reopenedby             text,
    reopenreason           text,

    CONSTRAINT ck_flockcloseouts_reason   CHECK (length(btrim(reason)) > 0),
    CONSTRAINT ck_flockcloseouts_balanced CHECK (
        livebirdsatcloseout = disposedsold + disposedculled + disposedtransferred),
    CONSTRAINT ck_flockcloseouts_reopen   CHECK (
        (reopenedat IS NULL AND reopenedby IS NULL AND reopenreason IS NULL)
        OR (reopenedat IS NOT NULL AND length(btrim(COALESCE(reopenreason, ''))) > 0))
);

-- One OPEN closeout per flock. History rows (reopened) are unlimited.
CREATE UNIQUE INDEX IF NOT EXISTS ux_flockcloseouts_open
    ON flockcloseouts (flockid) WHERE reopenedat IS NULL;
CREATE INDEX IF NOT EXISTS ix_flockcloseouts_farm
    ON flockcloseouts (farmid, flockid);

CREATE TABLE IF NOT EXISTS flockcloseoutdispositions (
    dispositionid          serial PRIMARY KEY,
    closeoutid             integer     NOT NULL REFERENCES flockcloseouts (closeoutid),
    farmid                 text        NOT NULL,
    flockid                integer     NOT NULL,
    disposition            text        NOT NULL,
    quantity               integer     NOT NULL,
    -- Sale: the ordinary sale row the C# layer created through SaleService.
    saleid                 integer,
    -- Transfer: where the birds went. Free text -- they left the company.
    destination            text,
    notes                  text,
    createdat              timestamp without time zone NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    -- Set when the closeout is reopened. The row stays as history.
    reversedat             timestamp without time zone,

    CONSTRAINT ck_flockcloseoutdisp_kind CHECK (disposition IN ('Sale', 'Cull', 'Transfer')),
    CONSTRAINT ck_flockcloseoutdisp_qty  CHECK (quantity > 0),
    CONSTRAINT ck_flockcloseoutdisp_sale CHECK ((disposition = 'Sale') = (saleid IS NOT NULL)),
    CONSTRAINT ck_flockcloseoutdisp_dest CHECK (
        disposition <> 'Transfer' OR length(btrim(COALESCE(destination, ''))) > 0)
);

CREATE INDEX IF NOT EXISTS ix_flockcloseoutdisp_closeout
    ON flockcloseoutdispositions (closeoutid);
-- A sale can close at most one live closeout.
CREATE UNIQUE INDEX IF NOT EXISTS ux_flockcloseoutdisp_sale
    ON flockcloseoutdispositions (saleid) WHERE saleid IS NOT NULL AND reversedat IS NULL;

-- ---------------------------------------------------------------------------
-- 3. What counts as a bird sale
-- ---------------------------------------------------------------------------
-- EXACTLY spsale_insert's rule -- the rule that decides whether a sale posts a
-- 'Bird Sale' row. A broader rule here (profitlossbyflock's, which also
-- matches "layer", "hen", "spent") would count sales as birds that the stock
-- side never did, and the two would disagree about how many birds left.
CREATE OR REPLACE FUNCTION fnpoultrysale_isbirdsale(p_product text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $f$
    SELECT (lower(COALESCE(p_product, '')) = 'birds'
            OR lower(COALESCE(p_product, '')) LIKE '%bird%'
            OR lower(COALESCE(p_product, '')) LIKE '%chick%'
            OR lower(COALESCE(p_product, '')) LIKE '%cockerel%')
       AND lower(COALESCE(p_product, '')) NOT LIKE '%egg%';
$f$;

-- ---------------------------------------------------------------------------
-- 4. The bird position of one flock
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fnflock_birdposition(p_farmid text, p_flockid integer)
RETURNS TABLE (
    flockid              integer,
    hasopeningposition   boolean,
    historyknown         boolean,
    originallyplaced     integer,
    openingmortality     integer,
    openingsold          integer,
    openingculled        integer,
    openingtransferred   integer,
    openingother         integer,
    openinglivebirds     integer,
    recordedmortality    integer,
    productionrecordcount integer,
    lastcountedbirds     integer,
    lastcountdate        date,
    correction           integer,
    birdssold            integer,
    birdsculled          integer,
    birdstransferred     integer,
    currentlivebirds     integer
)
LANGUAGE plpgsql
STABLE
AS $f$
BEGIN
    RETURN QUERY
    WITH f AS (
        SELECT fl.flockid AS c_flockid, COALESCE(fl.quantity, 0) AS c_quantity
        FROM   flock fl
        WHERE  fl.farmid = p_farmid AND fl.flockid = p_flockid
    ),
    o AS (
        -- One opening position per flock is what Initial Farm Setup writes;
        -- the latest wins if a second ever appears.
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
    -- Latest count: newest date, then newest row -- the same tie-break the
    -- End of Flock report uses, so the two cannot pick different records.
    lr AS (
        SELECT r.noofbirdsleft AS c_left, r.date AS c_date
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.flockid = p_flockid
        ORDER  BY r.date DESC, r.id DESC
        LIMIT  1
    ),
    s AS (
        SELECT COALESCE(ROUND(SUM(sa.quantity)), 0)::int AS c_sold
        FROM   sale sa
        WHERE  sa.farmid = p_farmid AND sa.flockid = p_flockid
          AND  fnpoultrysale_isbirdsale(sa.product)
    ),
    d AS (
        -- Only the dispositions of the OPEN closeout. A reopened closeout's
        -- culls and transfers were reversed and no longer took any birds.
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
        -- No opening position means the app saw the flock from placement, so
        -- there is no unknown history.
        COALESCE(o.historyknown, TRUE),
        COALESCE(o.originallyplaced, f.c_quantity),
        COALESCE(o.historicalmortality, 0),
        COALESCE(o.historicalsold, 0),
        COALESCE(o.historicalculled, 0),
        COALESCE(o.historicaltransferred, 0),
        COALESCE(o.otheradjustment, 0),
        f.c_quantity,
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
        GREATEST(COALESCE(lr.c_left, f.c_quantity), 0) - s.c_sold - d.c_culled - d.c_transferred
    FROM   f
    CROSS  JOIN pr
    CROSS  JOIN s
    CROSS  JOIN d
    LEFT   JOIN o  ON TRUE
    LEFT   JOIN lr ON TRUE;
END
$f$;

-- ---------------------------------------------------------------------------
-- 5. Guards
-- ---------------------------------------------------------------------------
-- The closeout and reopen functions set this for the length of their own work
-- and clear it again, so the guards below can tell "the closeout is closing
-- this flock" from "the edit form is un-closing it".
CREATE OR REPLACE FUNCTION fnflock_closeoutinprogress()
RETURNS boolean
LANGUAGE sql
STABLE
AS $f$
    SELECT COALESCE(current_setting('app.flock_closeout', true), '') = 'on';
$f$;

CREATE OR REPLACE FUNCTION fnflock_isclosed(p_flockid integer)
RETURNS boolean
LANGUAGE sql
STABLE
AS $f$
    SELECT EXISTS (SELECT 1 FROM flock f WHERE f.flockid = p_flockid AND f.closeddate IS NOT NULL);
$f$;

-- 5a. The flock row itself.
CREATE OR REPLACE FUNCTION tr_flock_closeoutguard_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $f$
BEGIN
    IF fnflock_closeoutinprogress() THEN
        RETURN NEW;
    END IF;

    -- Nobody but the closeout may set or clear the closed state.
    IF NEW.closeddate IS DISTINCT FROM OLD.closeddate
       OR NEW.closedat IS DISTINCT FROM OLD.closedat
       OR NEW.closedby IS DISTINCT FROM OLD.closedby
       OR NEW.closereason IS DISTINCT FROM OLD.closereason
       OR NEW.closeoutid IS DISTINCT FROM OLD.closeoutid THEN
        RAISE EXCEPTION 'A flock is closed and reopened only through Close Flock / Reopen Flock.'
            USING ERRCODE = 'P0001';
    END IF;

    IF OLD.closeddate IS NOT NULL THEN
        -- Name, breed and notes stay editable; anything that changes where the
        -- birds are, how many there were, or whether the flock is running does not.
        IF COALESCE(NEW.active, TRUE)
           OR NEW.quantity   IS DISTINCT FROM OLD.quantity
           OR NEW.batchid    IS DISTINCT FROM OLD.batchid
           OR NEW.houseid    IS DISTINCT FROM OLD.houseid
           OR NEW.startdate  IS DISTINCT FROM OLD.startdate
           OR NEW.hasarrived IS DISTINCT FROM OLD.hasarrived
           OR COALESCE(NEW.isdeleted, FALSE) IS DISTINCT FROM COALESCE(OLD.isdeleted, FALSE) THEN
            RAISE EXCEPTION 'Flock "%" was closed on %. Reopen it before changing its birds, house, dates or status.',
                OLD.name, to_char(OLD.closeddate, 'DD Mon YYYY')
                USING ERRCODE = 'P0001';
        END IF;
    END IF;

    RETURN NEW;
END
$f$;

DROP TRIGGER IF EXISTS tr_flock_closeoutguard ON flock;
CREATE TRIGGER tr_flock_closeoutguard
    BEFORE UPDATE ON flock
    FOR EACH ROW EXECUTE FUNCTION tr_flock_closeoutguard_fn();

-- 5b. Production records. INSERT and DELETE of any row, and an UPDATE of the
-- bird-count columns. Cost columns stay writable: inventory re-costing updates
-- totalfeedcost on historical rows and must not fail because a flock closed.
CREATE OR REPLACE FUNCTION tr_productionrecords_closeoutguard_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $f$
DECLARE
    v_flockid integer;
BEGIN
    IF fnflock_closeoutinprogress() THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    IF TG_OP = 'INSERT' THEN
        v_flockid := NEW.flockid;
    ELSIF TG_OP = 'DELETE' THEN
        v_flockid := OLD.flockid;
    ELSE
        IF NEW.flockid IS NOT DISTINCT FROM OLD.flockid
           AND NEW.date IS NOT DISTINCT FROM OLD.date
           AND NEW.noofbirds IS NOT DISTINCT FROM OLD.noofbirds
           AND NEW.mortality IS NOT DISTINCT FROM OLD.mortality
           AND NEW.noofbirdsleft IS NOT DISTINCT FROM OLD.noofbirdsleft THEN
            RETURN NEW;
        END IF;
        v_flockid := CASE WHEN fnflock_isclosed(OLD.flockid) THEN OLD.flockid ELSE NEW.flockid END;
    END IF;

    IF v_flockid IS NOT NULL AND fnflock_isclosed(v_flockid) THEN
        RAISE EXCEPTION 'This flock is closed. Reopen it before adding or changing its production, mortality or bird counts.'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN COALESCE(NEW, OLD);
END
$f$;

DROP TRIGGER IF EXISTS tr_productionrecords_closeoutguard ON productionrecords;
CREATE TRIGGER tr_productionrecords_closeoutguard
    BEFORE INSERT OR UPDATE OR DELETE ON productionrecords
    FOR EACH ROW EXECUTE FUNCTION tr_productionrecords_closeoutguard_fn();

-- 5c. Feed usage: a closed flock eats nothing.
CREATE OR REPLACE FUNCTION tr_feedusage_closeoutguard_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $f$
BEGIN
    IF NEW.flockid IS NOT NULL
       AND (TG_OP = 'INSERT' OR NEW.flockid IS DISTINCT FROM OLD.flockid)
       AND fnflock_isclosed(NEW.flockid) THEN
        RAISE EXCEPTION 'This flock is closed. Feed cannot be issued to it.'
            USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END
$f$;

DROP TRIGGER IF EXISTS tr_feedusage_closeoutguard ON feedusage;
CREATE TRIGGER tr_feedusage_closeoutguard
    BEFORE INSERT OR UPDATE ON feedusage
    FOR EACH ROW EXECUTE FUNCTION tr_feedusage_closeoutguard_fn();

-- 5d. Sales. A closed flock has no birds to sell, and the sales that closed it
-- are part of its reconciliation: their quantity, product and flock are locked
-- while the closeout stands. Price, customer and payment stay editable -- the
-- money side of a sale is the sales and payments pages' business.
CREATE OR REPLACE FUNCTION tr_sale_closeoutguard_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $f$
DECLARE
    v_locked boolean;
BEGIN
    IF fnflock_closeoutinprogress() THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        SELECT EXISTS (
            SELECT 1
            FROM   flockcloseoutdispositions x
            JOIN   flockcloseouts c ON c.closeoutid = x.closeoutid
            WHERE  x.saleid = OLD.saleid AND x.reversedat IS NULL AND c.reopenedat IS NULL
        ) INTO v_locked;

        IF v_locked AND (TG_OP = 'DELETE'
                         OR NEW.quantity IS DISTINCT FROM OLD.quantity
                         OR NEW.product  IS DISTINCT FROM OLD.product
                         OR NEW.flockid  IS DISTINCT FROM OLD.flockid) THEN
            RAISE EXCEPTION 'This sale closed a flock. Reopen the flock before changing the birds sold or deleting the sale.'
                USING ERRCODE = 'P0001';
        END IF;
    END IF;

    IF TG_OP IN ('INSERT', 'UPDATE')
       AND NEW.flockid IS NOT NULL
       AND fnpoultrysale_isbirdsale(NEW.product)
       AND (TG_OP = 'INSERT'
            OR NEW.flockid  IS DISTINCT FROM OLD.flockid
            OR NEW.quantity IS DISTINCT FROM OLD.quantity
            OR NEW.product  IS DISTINCT FROM OLD.product)
       AND fnflock_isclosed(NEW.flockid) THEN
        RAISE EXCEPTION 'This flock is closed and has no birds left to sell.'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN COALESCE(NEW, OLD);
END
$f$;

DROP TRIGGER IF EXISTS tr_sale_closeoutguard ON sale;
CREATE TRIGGER tr_sale_closeoutguard
    BEFORE INSERT OR UPDATE OR DELETE ON sale
    FOR EACH ROW EXECUTE FUNCTION tr_sale_closeoutguard_fn();

-- ---------------------------------------------------------------------------
-- 6. Close a flock
-- ---------------------------------------------------------------------------
-- p_dispositions: jsonb array of
--   {"disposition":"Sale","quantity":n,"saleId":id}
--   {"disposition":"Cull","quantity":n,"notes":"..."}
--   {"disposition":"Transfer","quantity":n,"destination":"...","notes":"..."}
-- Keys are camelCase, matched with QUOTED identifiers -- jsonb_to_recordset is
-- case-sensitive and an unquoted column silently reads NULL.
--
-- Sales are created by the caller BEFORE this runs (through SaleService, so
-- they get the cash account, customer and payment handling every other sale
-- gets). This function only links them, after checking each one is a bird sale
-- of this flock for exactly the quantity claimed.
CREATE OR REPLACE FUNCTION spflock_closeout(
    p_farmid        text,
    p_flockid       integer,
    p_closeddate    date,
    p_reason        text,
    p_notes         text,
    p_closedby      text,
    p_dispositions  jsonb
)
RETURNS integer
LANGUAGE plpgsql
AS $f$
DECLARE
    v_flock      flock%ROWTYPE;
    v_today      date;
    v_closeoutid integer;
    v_pos        record;
    v_row        record;
    v_dispid     integer;
    v_sale       record;
    v_sold       integer := 0;
    v_culled     integer := 0;
    v_transfer   integer := 0;
BEGIN
    IF p_reason IS NULL OR length(btrim(p_reason)) = 0 THEN
        RAISE EXCEPTION 'A reason is required to close a flock.' USING ERRCODE = 'P0001';
    END IF;
    IF p_closeddate IS NULL THEN
        RAISE EXCEPTION 'A closing date is required.' USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_flock FROM flock f
    WHERE  f.flockid = p_flockid AND f.farmid = p_farmid
    FOR UPDATE;

    IF NOT FOUND OR COALESCE(v_flock.isdeleted, FALSE) THEN
        RAISE EXCEPTION 'Flock not found on this farm.' USING ERRCODE = 'P0002';
    END IF;
    IF v_flock.closeddate IS NOT NULL THEN
        RAISE EXCEPTION 'Flock "%" is already closed.', v_flock.name USING ERRCODE = 'P0001';
    END IF;
    IF NOT COALESCE(v_flock.hasarrived, TRUE) THEN
        RAISE EXCEPTION 'Flock "%" has not arrived yet; there are no birds to close out.', v_flock.name
            USING ERRCODE = 'P0001';
    END IF;

    v_today := fncompany_businessdate(p_farmid);
    IF p_closeddate > v_today THEN
        RAISE EXCEPTION 'The closing date cannot be in the future.' USING ERRCODE = 'P0001';
    END IF;
    IF p_closeddate < v_flock.startdate THEN
        RAISE EXCEPTION 'The closing date cannot be before the flock started (%).',
            to_char(v_flock.startdate, 'DD Mon YYYY') USING ERRCODE = 'P0001';
    END IF;

    -- The position BEFORE this closeout's dispositions.
    SELECT * INTO v_pos FROM fnflock_birdposition(p_farmid, p_flockid);

    IF v_pos.lastcountdate IS NOT NULL AND p_closeddate < v_pos.lastcountdate THEN
        RAISE EXCEPTION 'The closing date cannot be before the last production record (%).',
            to_char(v_pos.lastcountdate, 'DD Mon YYYY') USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO flockcloseouts (
        farmid, flockid, closeddate, reason, notes, closedby, wasactive, houseid,
        hasopeningposition, historyknown, originallyplaced,
        openingmortality, openingsold, openingculled, openingtransferred, openingother,
        openinglivebirds, recordedmortality, correction, lastcountedbirds, lastcountdate,
        soldbeforecloseout, livebirdsatcloseout, disposedsold, disposedculled, disposedtransferred)
    VALUES (
        p_farmid, p_flockid, p_closeddate, btrim(p_reason), NULLIF(btrim(COALESCE(p_notes, '')), ''),
        p_closedby, COALESCE(v_flock.active, TRUE), v_flock.houseid,
        v_pos.hasopeningposition, v_pos.historyknown, v_pos.originallyplaced,
        v_pos.openingmortality, v_pos.openingsold, v_pos.openingculled, v_pos.openingtransferred, v_pos.openingother,
        v_pos.openinglivebirds, v_pos.recordedmortality, v_pos.correction, v_pos.lastcountedbirds, v_pos.lastcountdate,
        -- Filled in below once the sales are linked.
        0, 0, 0, 0, 0)
    RETURNING closeoutid INTO v_closeoutid;

    FOR v_row IN
        SELECT j."disposition" AS disposition, j."quantity" AS quantity, j."saleId" AS saleid,
               NULLIF(btrim(COALESCE(j."destination", '')), '') AS destination,
               NULLIF(btrim(COALESCE(j."notes", '')), '') AS notes
        FROM   jsonb_to_recordset(COALESCE(p_dispositions, '[]'::jsonb))
               AS j("disposition" text, "quantity" integer, "saleId" integer, "destination" text, "notes" text)
    LOOP
        IF v_row.disposition NOT IN ('Sale', 'Cull', 'Transfer') THEN
            RAISE EXCEPTION 'Unknown disposition "%". Birds can be sold, culled or transferred.',
                COALESCE(v_row.disposition, '(blank)') USING ERRCODE = 'P0001';
        END IF;
        IF COALESCE(v_row.quantity, 0) <= 0 THEN
            RAISE EXCEPTION 'Every disposition needs a quantity above zero.' USING ERRCODE = 'P0001';
        END IF;

        IF v_row.disposition = 'Sale' THEN
            SELECT s.saleid, s.flockid, s.product, s.quantity INTO v_sale
            FROM   sale s WHERE s.saleid = v_row.saleid AND s.farmid = p_farmid;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Sale #% was not found on this farm.', v_row.saleid USING ERRCODE = 'P0001';
            END IF;
            IF v_sale.flockid IS DISTINCT FROM p_flockid OR NOT fnpoultrysale_isbirdsale(v_sale.product) THEN
                RAISE EXCEPTION 'Sale #% is not a bird sale of this flock.', v_row.saleid USING ERRCODE = 'P0001';
            END IF;
            IF v_sale.quantity <> v_row.quantity THEN
                RAISE EXCEPTION 'Sale #% sold % birds, not %.', v_row.saleid, v_sale.quantity, v_row.quantity
                    USING ERRCODE = 'P0001';
            END IF;
            v_sold := v_sold + v_row.quantity;
        ELSIF v_row.disposition = 'Transfer' THEN
            IF v_row.destination IS NULL THEN
                RAISE EXCEPTION 'Say where the transferred birds went.' USING ERRCODE = 'P0001';
            END IF;
            v_transfer := v_transfer + v_row.quantity;
        ELSE
            v_culled := v_culled + v_row.quantity;
        END IF;

        INSERT INTO flockcloseoutdispositions
            (closeoutid, farmid, flockid, disposition, quantity, saleid, destination, notes)
        VALUES
            (v_closeoutid, p_farmid, p_flockid, v_row.disposition, v_row.quantity,
             CASE WHEN v_row.disposition = 'Sale' THEN v_row.saleid END,
             CASE WHEN v_row.disposition = 'Transfer' THEN v_row.destination END,
             v_row.notes)
        RETURNING dispositionid INTO v_dispid;

        -- Birds leaving the company leave the bird ledger. Sales already posted
        -- their own 'Bird Sale' row when they were created. Dated to the
        -- closing date, so the closing report puts them on the right day.
        IF v_row.disposition = 'Cull' THEN
            PERFORM sppoultrybirdstock_postdated(p_farmid, 'Flock Cull', -v_row.quantity, v_dispid,
                                                 p_closeddate, 'Culled at flock closeout', p_closedby);
        ELSIF v_row.disposition = 'Transfer' THEN
            PERFORM sppoultrybirdstock_postdated(p_farmid, 'Flock Transfer Out', -v_row.quantity, v_dispid,
                                                 p_closeddate, 'Transferred out at flock closeout: ' || v_row.destination,
                                                 p_closedby);
        END IF;
    END LOOP;

    -- The position AFTER: the linked sales are already in birdssold, the culls
    -- and transfers in their own columns. Anything but zero is unreconciled.
    SELECT * INTO v_pos FROM fnflock_birdposition(p_farmid, p_flockid);

    IF v_pos.currentlivebirds > 0 THEN
        RAISE EXCEPTION 'Unresolved bird balance: % bird(s) are still unaccounted for. Sell, cull or transfer them, or record any unrecorded deaths as mortality on a production record, before closing.',
            v_pos.currentlivebirds USING ERRCODE = 'P0001';
    ELSIF v_pos.currentlivebirds < 0 THEN
        RAISE EXCEPTION 'Unresolved bird balance: the dispositions account for % more bird(s) than the flock has.',
            -v_pos.currentlivebirds USING ERRCODE = 'P0001';
    END IF;

    UPDATE flockcloseouts c
    SET    disposedsold        = v_sold,
           disposedculled      = v_culled,
           disposedtransferred = v_transfer,
           soldbeforecloseout  = v_pos.birdssold - v_sold,
           livebirdsatcloseout = v_sold + v_culled + v_transfer
    WHERE  c.closeoutid = v_closeoutid;

    PERFORM set_config('app.flock_closeout', 'on', true);

    -- active = false is what releases the house: occupancy counts active flocks
    -- only. houseid stays, so the flock-house history is not lost.
    UPDATE flock f
    SET    active             = FALSE,
           inactivationreason = 'closed',
           otherreason        = NULL,
           closeddate         = p_closeddate,
           closedat           = (now() AT TIME ZONE 'utc'),
           closedby           = p_closedby,
           closereason        = btrim(p_reason),
           closeoutid         = v_closeoutid,
           updatedat          = (now() AT TIME ZONE 'utc')
    WHERE  f.flockid = p_flockid AND f.farmid = p_farmid;

    PERFORM set_config('app.flock_closeout', 'off', true);

    RETURN v_closeoutid;
END
$f$;

-- ---------------------------------------------------------------------------
-- 7. Reopen a closed flock
-- ---------------------------------------------------------------------------
-- Reverses the closeout's culls and transfers (append-only: the ledger gets
-- the opposite row, the disposition rows are stamped reversed, nothing is
-- deleted) and restores the flock to how it was before it closed.
--
-- SALES ARE LEFT ALONE. They are real sales with customers and money, and
-- they stay sold after a reopen; what changes is that they are no longer
-- locked, so if one was a mistake it can now be edited or deleted on the
-- Sales page, which reverses its cash and stock the ordinary way.
CREATE OR REPLACE FUNCTION spflock_reopen(
    p_farmid     text,
    p_flockid    integer,
    p_reason     text,
    p_reopenedby text
)
RETURNS integer
LANGUAGE plpgsql
AS $f$
DECLARE
    v_flock    flock%ROWTYPE;
    v_closeout flockcloseouts%ROWTYPE;
    v_disp     record;
    v_today    date;
    v_hascloseout boolean;
BEGIN
    IF p_reason IS NULL OR length(btrim(p_reason)) = 0 THEN
        RAISE EXCEPTION 'A reason is required to reopen a flock.' USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_flock FROM flock f
    WHERE  f.flockid = p_flockid AND f.farmid = p_farmid
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Flock not found on this farm.' USING ERRCODE = 'P0002';
    END IF;
    IF v_flock.closeddate IS NULL THEN
        RAISE EXCEPTION 'Flock "%" is not closed.', v_flock.name USING ERRCODE = 'P0001';
    END IF;

    SELECT * INTO v_closeout FROM flockcloseouts c
    WHERE  c.flockid = p_flockid AND c.farmid = p_farmid AND c.reopenedat IS NULL
    FOR UPDATE;
    -- Captured now: every PERFORM below resets FOUND.
    v_hascloseout := FOUND;

    v_today := fncompany_businessdate(p_farmid);

    PERFORM set_config('app.flock_closeout', 'on', true);

    IF v_hascloseout THEN
        FOR v_disp IN
            SELECT x.dispositionid, x.disposition
            FROM   flockcloseoutdispositions x
            WHERE  x.closeoutid = v_closeout.closeoutid AND x.reversedat IS NULL
        LOOP
            -- Posting quantity 0 makes the append-only sync write the exact
            -- opposite of what the closeout posted.
            IF v_disp.disposition = 'Cull' THEN
                PERFORM sppoultrybirdstock_postdated(p_farmid, 'Flock Cull', 0, v_disp.dispositionid,
                                                     v_today, NULL, p_reopenedby);
            ELSIF v_disp.disposition = 'Transfer' THEN
                PERFORM sppoultrybirdstock_postdated(p_farmid, 'Flock Transfer Out', 0, v_disp.dispositionid,
                                                     v_today, NULL, p_reopenedby);
            END IF;
        END LOOP;

        UPDATE flockcloseoutdispositions x
        SET    reversedat = (now() AT TIME ZONE 'utc')
        WHERE  x.closeoutid = v_closeout.closeoutid AND x.reversedat IS NULL;

        UPDATE flockcloseouts c
        SET    reopenedat   = (now() AT TIME ZONE 'utc'),
               reopenedby   = p_reopenedby,
               reopenreason = btrim(p_reason)
        WHERE  c.closeoutid = v_closeout.closeoutid;
    END IF;

    UPDATE flock f
    SET    active             = COALESCE(v_closeout.wasactive, TRUE),
           inactivationreason = CASE WHEN COALESCE(v_closeout.wasactive, TRUE) THEN NULL
                                     ELSE 'other' END,
           otherreason        = CASE WHEN COALESCE(v_closeout.wasactive, TRUE) THEN NULL
                                     ELSE 'Reopened after closeout: ' || btrim(p_reason) END,
           closeddate         = NULL,
           closedat           = NULL,
           closedby           = NULL,
           closereason        = NULL,
           closeoutid         = NULL,
           updatedat          = (now() AT TIME ZONE 'utc')
    WHERE  f.flockid = p_flockid AND f.farmid = p_farmid;

    PERFORM set_config('app.flock_closeout', 'off', true);

    RETURN v_closeout.closeoutid;
END
$f$;

-- ---------------------------------------------------------------------------
-- 8. Closeout history of a flock (newest first) with its dispositions
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION spflock_closeouthistory(p_farmid text, p_flockid integer)
RETURNS TABLE (
    closeoutid integer, flockid integer, closeddate date, reason text, notes text,
    closedby text, closedat timestamp without time zone, houseid integer,
    hasopeningposition boolean, historyknown boolean, originallyplaced integer,
    openingmortality integer, openingsold integer, openingculled integer,
    openingtransferred integer, openingother integer, openinglivebirds integer,
    recordedmortality integer, correction integer, lastcountedbirds integer,
    lastcountdate date, soldbeforecloseout integer, livebirdsatcloseout integer,
    disposedsold integer, disposedculled integer, disposedtransferred integer,
    reopenedat timestamp without time zone, reopenedby text, reopenreason text,
    dispositions jsonb
)
LANGUAGE sql
STABLE
AS $f$
    SELECT c.closeoutid, c.flockid, c.closeddate, c.reason, c.notes,
           c.closedby, c.closedat, c.houseid,
           c.hasopeningposition, c.historyknown, c.originallyplaced,
           c.openingmortality, c.openingsold, c.openingculled,
           c.openingtransferred, c.openingother, c.openinglivebirds,
           c.recordedmortality, c.correction, c.lastcountedbirds,
           c.lastcountdate, c.soldbeforecloseout, c.livebirdsatcloseout,
           c.disposedsold, c.disposedculled, c.disposedtransferred,
           c.reopenedat, c.reopenedby, c.reopenreason,
           COALESCE((
               SELECT jsonb_agg(jsonb_build_object(
                          'dispositionId', x.dispositionid,
                          'disposition',   x.disposition,
                          'quantity',      x.quantity,
                          'saleId',        x.saleid,
                          'destination',   x.destination,
                          'notes',         x.notes,
                          'reversedAt',    x.reversedat,
                          'totalAmount',   s.totalamount,
                          'customerName',  s.customername,
                          'paid',          s.paid)
                        ORDER BY x.dispositionid)
               FROM   flockcloseoutdispositions x
               LEFT   JOIN sale s ON s.saleid = x.saleid AND s.farmid = x.farmid
               WHERE  x.closeoutid = c.closeoutid), '[]'::jsonb)
    FROM   flockcloseouts c
    WHERE  c.farmid = p_farmid AND c.flockid = p_flockid
    ORDER  BY c.closeoutid DESC;
$f$;

-- ---------------------------------------------------------------------------
-- 9. Flock lifetime performance
-- ---------------------------------------------------------------------------
-- One row per flock, with the dimensions a comparison needs (batch, breed,
-- supplier, house) carried on the row, so Batch vs Batch, Breed vs Breed,
-- Supplier vs Supplier, Flock vs Flock and House vs House are all a GROUP BY
-- over this function and never a second definition of profit.
--
-- ONLY COSTS THAT BELONG TO THE FLOCK:
--   feed / medication  -- issued to the flock on its production records, at the
--                         FIFO/LIFO cost the issue drew (not expense categories,
--                         which are purchases and would count stock still in
--                         the store)
--   bird cost          -- this flock's share of its batch's recorded cost, by
--                         birds placed (the batch was bought at one price per
--                         bird). Zero, and flagged, when the batch has no cost.
--   labour / other     -- expenses a person TAGGED to this flock. Capital
--                         purchases are excluded; they are depreciated, not
--                         expensed to one flock.
-- Untagged payroll, utilities and overheads are NOT spread across flocks.
-- There is no allocation rule in the app to spread them by, and inventing one
-- here would make every flock's profit depend on a guess.
--
-- REVENUE is sales TAGGED to the flock. Egg sales are frequently recorded
-- without a flock; those are not attributed.
--
-- MORTALITY RATES keep the two periods apart:
--   tracked   = recorded mortality / opening live birds  (what happened here)
--   lifetime  = (opening + recorded mortality) / placed  -- NULL when the
--               opening history was never broken down, because then the
--               opening losses are not known to be deaths at all.
CREATE OR REPLACE FUNCTION fnflock_lifetimesummary(
    p_farmid       text,
    p_flockid      integer DEFAULT NULL,
    p_closedonly   boolean DEFAULT FALSE
)
RETURNS TABLE (
    flockid                 integer,
    flockname               text,
    breed                   text,
    status                  text,
    batchid                 integer,
    batchcode               text,
    batchname               text,
    supplierid              integer,
    suppliertype            text,
    houseid                 integer,
    housename               text,
    startdate               date,
    closeddate              date,
    daysinproduction        integer,
    hasopeningposition      boolean,
    historyknown            boolean,
    originallyplaced        integer,
    openinglivebirds        integer,
    openingmortality        integer,
    recordedmortality       integer,
    birdssold               integer,
    birdsculled             integer,
    birdstransferred        integer,
    finalbirds              integer,
    trackedmortalityrate    numeric,
    lifetimemortalityrate   numeric,
    totaleggs               bigint,
    productiondays          integer,
    eggrevenue              numeric,
    birdsalerevenue         numeric,
    otherrevenue            numeric,
    totalrevenue            numeric,
    feedconsumedkg          numeric,
    feedcost                numeric,
    medicationcost          numeric,
    birdcost                numeric,
    birdcostrecorded        boolean,
    laborcost               numeric,
    otherdirectcost         numeric,
    totalcost               numeric,
    profit                  numeric,
    profitperoriginalbird   numeric,
    revenueperoriginalbird  numeric,
    feedkgperdozeneggs      numeric
)
LANGUAGE plpgsql
STABLE
AS $f$
DECLARE
    v_gid   uuid;
    v_today date;
BEGIN
    BEGIN
        v_gid := p_farmid::uuid;       -- expense.farmid is a uuid
    EXCEPTION WHEN OTHERS THEN
        v_gid := NULL;
    END;
    v_today := fncompany_businessdate(p_farmid);

    RETURN QUERY
    WITH fl AS (
        SELECT f.*
        FROM   flock f
        WHERE  f.farmid = p_farmid
          AND  COALESCE(f.isdeleted, FALSE) = FALSE
          AND  (p_flockid IS NULL OR f.flockid = p_flockid)
          AND  (NOT p_closedonly OR f.closeddate IS NOT NULL)
    ),
    pr AS (
        SELECT r.flockid AS c_flockid,
               SUM(COALESCE(r.totalproduction, 0))::bigint    AS c_eggs,
               COUNT(DISTINCT r.date)::int                    AS c_days,
               SUM(COALESCE(r.feedkg, 0))                     AS c_feedkg,
               SUM(COALESCE(r.totalfeedcost, 0))              AS c_feedcost,
               SUM(COALESCE(r.totalmedicationcost, 0))        AS c_medcost
        FROM   productionrecords r
        WHERE  r.farmid = p_farmid AND r.flockid IN (SELECT fl.flockid FROM fl)
        GROUP  BY r.flockid
    ),
    rev AS (
        SELECT s.flockid AS c_flockid,
               SUM(s.totalamount) FILTER (WHERE lower(COALESCE(s.product, '')) LIKE '%egg%') AS c_egg,
               SUM(s.totalamount) FILTER (WHERE fnpoultrysale_isbirdsale(s.product))         AS c_bird,
               SUM(s.totalamount)                                                            AS c_total
        FROM   sale s
        WHERE  s.farmid = p_farmid AND s.flockid IN (SELECT fl.flockid FROM fl)
        GROUP  BY s.flockid
    ),
    ex AS (
        SELECT e.flockid AS c_flockid,
               SUM(e.amount) FILTER (WHERE e.category ILIKE '%labo%' OR e.category ILIKE '%salary%'
                                        OR e.category ILIKE '%wage%' OR e.category ILIKE '%payroll%') AS c_labor,
               SUM(e.amount) FILTER (WHERE NOT (e.category ILIKE '%labo%' OR e.category ILIKE '%salary%'
                                        OR e.category ILIKE '%wage%' OR e.category ILIKE '%payroll%')) AS c_other
        FROM   expense e
        WHERE  e.farmid = v_gid
          AND  e.flockid IN (SELECT fl.flockid FROM fl)
          AND  e.poultrycapitalassetid IS NULL
          AND  COALESCE(e.financialcosttype, '') NOT IN ('CapitalAsset', 'NonCashExpense')
        GROUP  BY e.flockid
    ),
    base AS (
        SELECT fl.flockid                                         AS c_flockid,
               fl.name::text                                      AS c_name,
               fl.breed::text                                     AS c_breed,
               CASE WHEN fl.closeddate IS NOT NULL THEN 'Closed'
                    WHEN NOT COALESCE(fl.hasarrived, TRUE) THEN 'Pending'
                    WHEN COALESCE(fl.active, TRUE) THEN 'Active'
                    ELSE 'Inactive' END                           AS c_status,
               fl.batchid                                         AS c_batchid,
               b.batchcode::text                                  AS c_batchcode,
               b.batchname::text                                  AS c_batchname,
               b.supplierid                                       AS c_supplierid,
               b.suppliertype::text                               AS c_suppliertype,
               fl.houseid                                         AS c_houseid,
               h.housename::text                                  AS c_housename,
               fl.startdate                                       AS c_startdate,
               fl.closeddate                                      AS c_closeddate,
               GREATEST(COALESCE(fl.closeddate, v_today) - fl.startdate, 0)::int AS c_days,
               p.*,
               COALESCE(pr.c_eggs, 0)                             AS c_eggs,
               COALESCE(pr.c_days, 0)                             AS c_proddays,
               COALESCE(pr.c_feedkg, 0)                           AS c_feedkg,
               COALESCE(pr.c_feedcost, 0)                         AS c_feedcost,
               COALESCE(pr.c_medcost, 0)                          AS c_medcost,
               COALESCE(rev.c_egg, 0)                             AS c_eggrev,
               COALESCE(rev.c_bird, 0)                            AS c_birdrev,
               COALESCE(rev.c_total, 0)                           AS c_totalrev,
               COALESCE(ex.c_labor, 0)                            AS c_labor,
               COALESCE(ex.c_other, 0)                            AS c_other,
               CASE WHEN COALESCE(b.totalcost, 0) > 0 AND COALESCE(b.numberofbirds, 0) > 0
                    THEN ROUND(b.totalcost * p.originallyplaced / b.numberofbirds, 2)
                    ELSE 0 END                                    AS c_birdcost,
               (COALESCE(b.totalcost, 0) > 0 AND COALESCE(b.numberofbirds, 0) > 0) AS c_birdcostrecorded
        FROM   fl
        CROSS  JOIN LATERAL fnflock_birdposition(p_farmid, fl.flockid) p
        LEFT   JOIN mainflockbatch b ON b.batchid = fl.batchid AND b.farmid = fl.farmid
        LEFT   JOIN houses h         ON h.houseid = fl.houseid AND h.farmid = fl.farmid
        LEFT   JOIN pr  ON pr.c_flockid  = fl.flockid
        LEFT   JOIN rev ON rev.c_flockid = fl.flockid
        LEFT   JOIN ex  ON ex.c_flockid  = fl.flockid
    )
    SELECT
        c_flockid, c_name, c_breed, c_status,
        c_batchid, c_batchcode, c_batchname, c_supplierid, c_suppliertype,
        c_houseid, c_housename, c_startdate, c_closeddate, c_days,
        base.hasopeningposition, base.historyknown,
        base.originallyplaced, base.openinglivebirds, base.openingmortality, base.recordedmortality,
        base.birdssold, base.birdsculled, base.birdstransferred,
        base.currentlivebirds,
        CASE WHEN base.openinglivebirds > 0
             THEN ROUND(base.recordedmortality::numeric / base.openinglivebirds, 4) END,
        CASE WHEN base.historyknown AND base.originallyplaced > 0
             THEN ROUND((base.openingmortality + base.recordedmortality)::numeric / base.originallyplaced, 4) END,
        c_eggs, c_proddays,
        c_eggrev, c_birdrev, c_totalrev - c_eggrev - c_birdrev, c_totalrev,
        c_feedkg, c_feedcost, c_medcost, c_birdcost, c_birdcostrecorded, c_labor, c_other,
        c_feedcost + c_medcost + c_birdcost + c_labor + c_other,
        c_totalrev - (c_feedcost + c_medcost + c_birdcost + c_labor + c_other),
        CASE WHEN base.originallyplaced > 0
             THEN ROUND((c_totalrev - (c_feedcost + c_medcost + c_birdcost + c_labor + c_other))
                        / base.originallyplaced, 2) END,
        CASE WHEN base.originallyplaced > 0 THEN ROUND(c_totalrev / base.originallyplaced, 2) END,
        CASE WHEN c_eggs > 0 THEN ROUND(c_feedkg / (c_eggs / 12.0), 3) END
    FROM   base
    ORDER  BY c_startdate DESC, c_flockid DESC;
END
$f$;

-- ---------------------------------------------------------------------------
-- 10. Flock readers carry the closed state
-- ---------------------------------------------------------------------------
-- RETURNS TABLE is part of the signature, so adding columns needs DROP, not
-- CREATE OR REPLACE. Dropped BY NAME so no stale overload survives beside the
-- new one (postgres-sp-gotchas #3). Bodies are the live ones (301) plus the
-- five closed-state columns; the row filter is deliberately unchanged.
DO $d$
DECLARE r record;
BEGIN
    FOR r IN SELECT p.oid::regprocedure::text AS sig
             FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE  n.nspname = 'public' AND p.proname IN ('spflock_getall', 'spflock_getbyid')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$d$;

CREATE FUNCTION spflock_getall(p_farmid text, p_userid text DEFAULT NULL::text)
RETURNS TABLE(flockid integer, userid text, farmid text, name text, breed text, startdate date,
              quantity integer, active boolean, houseid integer, batchid integer,
              inactivationreason text, otherreason text, notes text, hasarrived boolean,
              batchname text, createdat timestamp without time zone,
              closeddate date, closedat timestamp without time zone, closedby text,
              closereason text, closeoutid integer)
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
        f.createdat,                          -- 301
        f.closeddate,                         -- 338
        f.closedat,
        f.closedby,
        f.closereason,
        f.closeoutid
    FROM flock f
    LEFT JOIN mainflockbatch b
        ON f.batchid = b.batchid AND f.farmid = b.farmid
    WHERE f.farmid = p_farmid
    ORDER BY f.startdate DESC;
END
$function$;

CREATE FUNCTION spflock_getbyid(p_flockid integer, p_farmid text)
RETURNS TABLE(flockid integer, userid text, farmid text, name text, breed text, startdate date,
              quantity integer, active boolean, houseid integer, batchid integer,
              inactivationreason text, otherreason text, notes text, hasarrived boolean,
              batchname text,
              closeddate date, closedat timestamp without time zone, closedby text,
              closereason text, closeoutid integer)
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
        f.closeddate,                         -- 338
        f.closedat,
        f.closedby,
        f.closereason,
        f.closeoutid
    FROM flock f
    LEFT JOIN mainflockbatch b
        ON f.batchid = b.batchid AND f.farmid = b.farmid
    WHERE f.flockid = p_flockid
      AND f.farmid = p_farmid;
END
$function$;

-- ---------------------------------------------------------------------------
-- 11. Missing Daily Records: a closed flock is expected up to its closing date
-- ---------------------------------------------------------------------------
-- The live report counted ACTIVE flocks only, so closing a flock (active =
-- false) would have made its past gaps vanish from history too. A closed flock
-- now counts for the days it was running -- start date through closing date --
-- and never after. Any other inactive flock is excluded exactly as before.
-- RETURNS TABLE unchanged, so CREATE OR REPLACE is safe here.
CREATE OR REPLACE FUNCTION sppoultryreport_missingdailyrecords_rs1(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer)
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
                      WHERE pr.farmid = p_farmid AND pr.flockid = fl.c_flockid AND pr.date = d.c_dt)
                                            AS c_hasproductionrecord,
               (EXISTS(SELECT 1 FROM feedusage fu
                       WHERE fu.farmid = p_farmid AND fu.flockid = fl.c_flockid AND fu.usagedate = d.c_dt)
                OR EXISTS(SELECT 1 FROM productionrecords pr
                          WHERE pr.farmid = p_farmid AND pr.flockid = fl.c_flockid AND pr.date = d.c_dt AND pr.feedkg > 0))
                                            AS c_hasfeedusage,
               EXISTS(SELECT 1 FROM productionrecords pr
                      WHERE pr.farmid = p_farmid AND pr.flockid = fl.c_flockid AND pr.date = d.c_dt)
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

CREATE OR REPLACE FUNCTION sppoultryreport_missingdailyrecords_rs2(p_farmid text, p_startdate date, p_enddate date, p_flockid integer DEFAULT NULL::integer)
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
                      WHERE pr.farmid = p_farmid AND pr.flockid = fl.c_flockid AND pr.date = d.c_dt)
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

-- ---------------------------------------------------------------------------
-- 12. Permissions
-- ---------------------------------------------------------------------------
-- Its own resource, poultry.flock-closeout, so closing a flock is not simply
-- "can edit flocks" and reopening one is narrower still:
--   view    -- see the reconciliation, history and lifetime summary
--   create  -- close a flock                       (from poultry.flocks.edit)
--   approve -- reopen a closed flock (the /reverse route; dangerous)
--                                                  (from poultry.flocks.delete)
DO $iam$
DECLARE
    v_added_keys  integer := 0;
    v_added_roles integer := 0;
    v_added_users integer := 0;
    v_n           integer;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '338: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'poultry.flock-closeout.' || a.action, 'poultry', 'flock-closeout', a.action,
           'Flock & Birds', 'Flock Closeout',
           'Ending a flock''s life: reconciling its birds, selling, culling or '
           || 'transferring the last of them, and releasing its house. Approve '
           || 'covers reopening a closed flock.',
           'Poultry',
           a.action = 'approve', 11
    FROM (VALUES ('view'), ('create'), ('approve')) AS a(action)
    ON CONFLICT (permissionkey) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_added_keys := v_added_keys + v_n;

    IF to_regclass('public.iamrolepermissions') IS NOT NULL THEN
        INSERT INTO iamrolepermissions (roleid, permissionkey)
        SELECT rp.roleid, m.new_key
        FROM   iamrolepermissions rp
        JOIN   (VALUES
                  ('poultry.flocks.view',   'poultry.flock-closeout.view'),
                  ('poultry.flocks.edit',   'poultry.flock-closeout.create'),
                  ('poultry.flocks.delete', 'poultry.flock-closeout.approve')
               ) AS m(old_key, new_key) ON m.old_key = rp.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
        ON CONFLICT (roleid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_added_roles = ROW_COUNT;
    END IF;

    -- Farm-scoped and carrying an effect; both copied verbatim so a Deny stays
    -- a Deny rather than quietly becoming an Allow on a new key.
    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        INSERT INTO iamuserpermissions (userid, farmid, permissionkey, effect, reason, grantedby, grantedat)
        SELECT up.userid, up.farmid, m.new_key, up.effect,
               'Carried over from ' || up.permissionkey || ' by migration 338',
               up.grantedby, (now() at time zone 'utc')
        FROM   iamuserpermissions up
        JOIN   (VALUES
                  ('poultry.flocks.view',   'poultry.flock-closeout.view'),
                  ('poultry.flocks.edit',   'poultry.flock-closeout.create'),
                  ('poultry.flocks.delete', 'poultry.flock-closeout.approve')
               ) AS m(old_key, new_key) ON m.old_key = up.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
          AND  (up.expiresat IS NULL OR up.expiresat > (now() at time zone 'utc'))
        ON CONFLICT (userid, farmid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_added_users = ROW_COUNT;
    END IF;

    RAISE NOTICE '338: % catalog key(s), % role grant(s), % user grant(s) added.',
        v_added_keys, v_added_roles, v_added_users;
END;
$iam$;

COMMIT;
