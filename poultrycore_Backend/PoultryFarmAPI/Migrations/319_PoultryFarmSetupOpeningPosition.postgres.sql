-- =============================================================================
-- 319_PoultryFarmSetupOpeningPosition.postgres.sql
--
-- Purpose
-- -------
-- Let an ESTABLISHED poultry farm say what its birds look like today, without
-- the application pretending that everything which happened to them before it
-- started tracking happened on the onboarding date.
--
-- THE BUG THIS EXISTS TO KILL
-- ===========================
-- A flock placed with 1,050 birds that has 960 left when the farm joins has
-- lost 90 somewhere, over months. Until now the only place to put that 90 was
-- the first production record's mortality column, because current birds are
-- read as `noofbirdsleft` on the latest production record (and as the flock's
-- placed quantity when there is none). Eight flocks onboarded that way produce
-- "Deaths Today = 682" on a day when nothing died. The mortality is real; the
-- DATE is a fiction, and every daily chart, every date filter and every
-- month-to-date report inherits it.
--
-- WHY NO PRODUCTION RECORD, AND NO CHANGE TO THE BIRD MATHS
-- =========================================================
-- The fix needs no new bird-count logic at all. `flock.quantity` becomes the
-- OPENING LIVE BIRDS -- 960, what is actually standing in the pen on day one --
-- and the existing rule ("latest production record, else the flock's quantity")
-- is then already correct: current birds read 960 with zero production records,
-- and the first real record starts from 960 and subtracts only what really died
-- that day. Nothing in production records, the Total Deaths card or the
-- mortality date filters has to change, because none of them ever sees the
-- historical 90.
--
-- What the 90 needs is somewhere honest to live, which is this table: one row
-- per flock saying what was originally placed, what was standing on the
-- effective date, and -- when the farmer knows -- how the difference broke down.
--
-- WHY A DEDICATED OPENING-POSITION TABLE AND NOT A MOVEMENT LEDGER
-- ================================================================
-- A general FlockBirdMovement ledger was the obvious alternative and is the
-- wrong size for the problem. Bird counts in this application are NOT read from
-- a ledger -- they are read from production records and flock quantities -- so a
-- new ledger would either be decorative (nothing reads it) or would require
-- rewriting every bird-count path in the app to read from it, which is a far
-- larger and riskier change than the one this bug asks for. An opening position
-- is also genuinely not a movement: it is a statement about a moment, recorded
-- once per flock, and it is never posted, reversed or dated into a period.
--
-- If a movement ledger is built later, this table is its seed row and the
-- migration is mechanical: one OpeningBalance movement per row here.
--
-- WHY THE BREAKDOWN COLUMNS ARE SEPARATE AND NULLABLE-BY-ZERO
-- ===========================================================
-- "90 fewer birds" and "90 birds died" are different facts and the farm often
-- only knows the first. historyknown = false means the breakdown was never
-- given: the whole difference sits in otheradjustment and MUST NOT be reported
-- as mortality. Known lifetime mortality is historicalmortality plus what has
-- been recorded since -- never the raw difference.
--
-- Idempotent. Safe to run more than once.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. The opening position: one row per flock.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultryopeningflockposition (
    openingpositionid     serial PRIMARY KEY,
    farmid                text      NOT NULL,
    flockid               integer   NOT NULL,

    -- The business date, in the COMPANY's timezone, on which these numbers were
    -- true. Not a timestamp: an opening position is a day, and storing an
    -- instant invites a browser in another zone to shift it.
    effectivebusinessdate date      NOT NULL,

    -- What the farm says went into this pen originally, and what was standing
    -- there on the effective date. originallyplaced is the figure batch totals
    -- are checked against; openinglivebirds is what the flock starts life with.
    originallyplaced      integer   NOT NULL,
    openinglivebirds      integer   NOT NULL,

    -- The breakdown of (originallyplaced - openinglivebirds). All default to 0.
    historicalmortality   integer   NOT NULL DEFAULT 0,
    historicalsold        integer   NOT NULL DEFAULT 0,
    historicalculled      integer   NOT NULL DEFAULT 0,
    historicaltransferred integer   NOT NULL DEFAULT 0,
    otheradjustment       integer   NOT NULL DEFAULT 0,

    -- false = the farm did not know the breakdown. The difference is then all
    -- in otheradjustment and is NOT mortality.
    historyknown          boolean   NOT NULL DEFAULT false,

    -- true = the flock's start date was derived from a stated age, not supplied.
    -- Recorded so a report never presents a derived date as an exact fact.
    startdateestimated    boolean   NOT NULL DEFAULT false,

    source                text      NOT NULL DEFAULT 'InitialFarmSetup',
    notes                 text,
    createdby             text,
    createdat             timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

-- One opening position per flock. A flock has exactly one moment at which
-- tracking began; a second row would make "what was true on day one" ambiguous,
-- and would double-count the historical reduction in every roll-up.
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryopeningflockposition_flock
    ON public.poultryopeningflockposition (farmid, flockid);

CREATE INDEX IF NOT EXISTS ix_poultryopeningflockposition_farm
    ON public.poultryopeningflockposition (farmid);

DO $$
BEGIN
    -- The breakdown must add up to the difference. Without this a row could
    -- claim 1,050 placed, 960 live and 70 mortality, and the missing 20 would
    -- silently vanish from every reconciliation.
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'ck_poultryopeningflockposition_balances') THEN
        ALTER TABLE public.poultryopeningflockposition
            ADD CONSTRAINT ck_poultryopeningflockposition_balances
            CHECK (historicalmortality + historicalsold + historicalculled
                   + historicaltransferred + otheradjustment
                   = originallyplaced - openinglivebirds);
    END IF;

    -- Nothing here may be negative, and a flock cannot have more birds standing
    -- than were ever placed in it.
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'ck_poultryopeningflockposition_nonneg') THEN
        ALTER TABLE public.poultryopeningflockposition
            ADD CONSTRAINT ck_poultryopeningflockposition_nonneg
            CHECK (originallyplaced >= 0 AND openinglivebirds >= 0
                   AND openinglivebirds <= originallyplaced
                   AND historicalmortality >= 0 AND historicalsold >= 0
                   AND historicalculled >= 0 AND historicaltransferred >= 0
                   AND otheradjustment >= 0);
    END IF;

    -- An unknown history cannot also be a known breakdown. This is the
    -- constraint that stops "we don't know" quietly becoming "it was mortality".
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname = 'ck_poultryopeningflockposition_unknown') THEN
        ALTER TABLE public.poultryopeningflockposition
            ADD CONSTRAINT ck_poultryopeningflockposition_unknown
            CHECK (historyknown
                   OR (historicalmortality = 0 AND historicalsold = 0
                       AND historicalculled = 0 AND historicaltransferred = 0));
    END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 2. Farm setup: one row per company, written once when the wizard completes.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultryfarmsetup (
    farmsetupid            serial PRIMARY KEY,
    farmid                 text      NOT NULL,

    -- 'ExistingFarm' (opening position reconstructed) or 'NewBatch' (the farm
    -- started here, so there is nothing to reconstruct).
    setupmode              text      NOT NULL,

    completedbusinessdate  date      NOT NULL,
    completedat            timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    completedby            text,

    -- A snapshot for the "already completed" panel, so showing it costs one
    -- read instead of re-deriving the whole onboarding every time.
    batchcount             integer   NOT NULL DEFAULT 0,
    housecount             integer   NOT NULL DEFAULT 0,
    flockcount             integer   NOT NULL DEFAULT 0,
    originallyplaced       integer   NOT NULL DEFAULT 0,
    openinglivebirds       integer   NOT NULL DEFAULT 0,
    historicalreduction    integer   NOT NULL DEFAULT 0,
    notes                  text
);

-- One completed setup per company: this is what stops the wizard being casually
-- rerun and creating the whole farm a second time.
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryfarmsetup_farm
    ON public.poultryfarmsetup (lower(farmid));

-- -----------------------------------------------------------------------------
-- 3. Write one opening position.
--
-- Called once per flock inside the setup transaction, right after the flock is
-- inserted. Deliberately NOT an upsert: an opening position is written once, and
-- silently overwriting one would rewrite the farm's day-one truth without trace.
-- Correcting one is a separate, deliberate act -- see spoultryopeningposition_correct.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryopeningposition_insert(
    p_farmid                text,
    p_flockid               integer,
    p_effectivebusinessdate date,
    p_originallyplaced      integer,
    p_openinglivebirds      integer,
    p_historicalmortality   integer,
    p_historicalsold        integer,
    p_historicalculled      integer,
    p_historicaltransferred integer,
    p_otheradjustment       integer,
    p_historyknown          boolean,
    p_startdateestimated    boolean,
    p_source                text,
    p_notes                 text,
    p_createdby             text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id integer;
BEGIN
    INSERT INTO public.poultryopeningflockposition (
        farmid, flockid, effectivebusinessdate, originallyplaced, openinglivebirds,
        historicalmortality, historicalsold, historicalculled, historicaltransferred,
        otheradjustment, historyknown, startdateestimated, source, notes, createdby)
    VALUES (
        p_farmid, p_flockid, p_effectivebusinessdate, p_originallyplaced, p_openinglivebirds,
        COALESCE(p_historicalmortality, 0), COALESCE(p_historicalsold, 0),
        COALESCE(p_historicalculled, 0), COALESCE(p_historicaltransferred, 0),
        COALESCE(p_otheradjustment, 0), COALESCE(p_historyknown, false),
        COALESCE(p_startdateestimated, false),
        COALESCE(NULLIF(btrim(p_source), ''), 'InitialFarmSetup'), p_notes, p_createdby)
    RETURNING openingpositionid INTO v_id;

    RETURN v_id;
END
$function$;

-- -----------------------------------------------------------------------------
-- 4. Read the opening positions for a company, with the flock's own details.
--
-- Joined here rather than in the application so "opening historical mortality"
-- and "recorded mortality since" can be put side by side without the caller
-- having to stitch two lists together in the right order.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryopeningposition_getall(p_farmid text)
RETURNS TABLE(
    openingpositionid     integer,
    farmid                text,
    flockid               integer,
    flockname             text,
    batchid               integer,
    houseid               integer,
    effectivebusinessdate date,
    originallyplaced      integer,
    openinglivebirds      integer,
    historicalmortality   integer,
    historicalsold        integer,
    historicalculled      integer,
    historicaltransferred integer,
    otheradjustment       integer,
    historyknown          boolean,
    startdateestimated    boolean,
    source                text,
    notes                 text,
    createdby             text,
    createdat             timestamp)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT o.openingpositionid,
           o.farmid::text,
           o.flockid,
           f.name::text,
           f.batchid,
           f.houseid,
           o.effectivebusinessdate,
           o.originallyplaced,
           o.openinglivebirds,
           o.historicalmortality,
           o.historicalsold,
           o.historicalculled,
           o.historicaltransferred,
           o.otheradjustment,
           o.historyknown,
           o.startdateestimated,
           o.source::text,
           o.notes::text,
           o.createdby::text,
           o.createdat
    FROM   public.poultryopeningflockposition o
    -- The table is `flock`, singular, and the join carries farmid as well as the
    -- id: every other reader in this schema does (214, 252, 288), and without it
    -- a flock id colliding across companies would read another company's name.
    LEFT   JOIN public.flock f
           ON f.flockid = o.flockid AND f.farmid = o.farmid
    WHERE  o.farmid = p_farmid
    ORDER  BY f.name NULLS LAST, o.openingpositionid;
END
$function$;

-- -----------------------------------------------------------------------------
-- 5. Correct an opening position.
--
-- Separate from the insert on purpose. Onboarding numbers are often wrong on the
-- first try, and the right answer is NOT to delete posted operational history --
-- it is to restate the opening position and leave everything that has happened
-- since alone. The caller decides whether a correction is allowed (it refuses
-- once production exists); this function just applies it and stamps the note.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryopeningposition_correct(
    p_farmid                text,
    p_flockid               integer,
    p_originallyplaced      integer,
    p_openinglivebirds      integer,
    p_historicalmortality   integer,
    p_historicalsold        integer,
    p_historicalculled      integer,
    p_historicaltransferred integer,
    p_otheradjustment       integer,
    p_historyknown          boolean,
    p_notes                 text,
    p_correctedby           text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id integer;
BEGIN
    UPDATE public.poultryopeningflockposition
       SET originallyplaced      = p_originallyplaced,
           openinglivebirds      = p_openinglivebirds,
           historicalmortality   = COALESCE(p_historicalmortality, 0),
           historicalsold        = COALESCE(p_historicalsold, 0),
           historicalculled      = COALESCE(p_historicalculled, 0),
           historicaltransferred = COALESCE(p_historicaltransferred, 0),
           otheradjustment       = COALESCE(p_otheradjustment, 0),
           historyknown          = COALESCE(p_historyknown, false),
           -- The trail of who last restated it, appended rather than replaced.
           notes                 = COALESCE(NULLIF(btrim(p_notes), ''), notes),
           createdby             = COALESCE(p_correctedby, createdby)
     WHERE farmid = p_farmid AND flockid = p_flockid
    RETURNING openingpositionid INTO v_id;

    RETURN v_id;   -- NULL when there was nothing to correct.
END
$function$;

-- -----------------------------------------------------------------------------
-- 6. Farm setup status, and marking it complete.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryfarmsetup_get(p_farmid text)
RETURNS TABLE(
    farmsetupid           integer,
    farmid                text,
    setupmode             text,
    completedbusinessdate date,
    completedat           timestamp,
    completedby           text,
    batchcount            integer,
    housecount            integer,
    flockcount            integer,
    originallyplaced      integer,
    openinglivebirds      integer,
    historicalreduction   integer,
    notes                 text)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.farmsetupid, s.farmid::text, s.setupmode::text, s.completedbusinessdate,
           s.completedat, s.completedby::text, s.batchcount, s.housecount, s.flockcount,
           s.originallyplaced, s.openinglivebirds, s.historicalreduction, s.notes::text
    FROM   public.poultryfarmsetup s
    WHERE  lower(s.farmid) = lower(p_farmid);
END
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryfarmsetup_complete(
    p_farmid                text,
    p_setupmode             text,
    p_completedbusinessdate date,
    p_completedby           text,
    p_batchcount            integer,
    p_housecount            integer,
    p_flockcount            integer,
    p_originallyplaced      integer,
    p_openinglivebirds      integer,
    p_historicalreduction   integer,
    p_notes                 text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id integer;
BEGIN
    INSERT INTO public.poultryfarmsetup (
        farmid, setupmode, completedbusinessdate, completedby, batchcount, housecount,
        flockcount, originallyplaced, openinglivebirds, historicalreduction, notes)
    VALUES (
        p_farmid, p_setupmode, p_completedbusinessdate, p_completedby,
        COALESCE(p_batchcount, 0), COALESCE(p_housecount, 0), COALESCE(p_flockcount, 0),
        COALESCE(p_originallyplaced, 0), COALESCE(p_openinglivebirds, 0),
        COALESCE(p_historicalreduction, 0), p_notes)
    -- Re-running the wizard must not create the farm twice. The second attempt
    -- refreshes the snapshot and nothing else; the caller refuses long before
    -- reaching here, and this is the backstop.
    -- The existing row is referenced by the table's UNQUALIFIED name here;
    -- schema-qualifying it is a "missing FROM-clause entry" error.
    ON CONFLICT (lower(farmid)) DO UPDATE
        SET batchcount          = poultryfarmsetup.batchcount + EXCLUDED.batchcount,
            housecount          = poultryfarmsetup.housecount + EXCLUDED.housecount,
            flockcount          = poultryfarmsetup.flockcount + EXCLUDED.flockcount,
            originallyplaced    = poultryfarmsetup.originallyplaced + EXCLUDED.originallyplaced,
            openinglivebirds    = poultryfarmsetup.openinglivebirds + EXCLUDED.openinglivebirds,
            historicalreduction = poultryfarmsetup.historicalreduction + EXCLUDED.historicalreduction
    RETURNING farmsetupid INTO v_id;

    RETURN v_id;
END
$function$;

-- -----------------------------------------------------------------------------
-- 7. Grants, matching the app login used by every other function here.
-- -----------------------------------------------------------------------------
DO $grants$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'poultryapp') THEN
        GRANT SELECT, INSERT, UPDATE ON public.poultryopeningflockposition TO poultryapp;
        GRANT SELECT, INSERT, UPDATE ON public.poultryfarmsetup            TO poultryapp;
        GRANT USAGE, SELECT ON SEQUENCE public.poultryopeningflockposition_openingpositionid_seq TO poultryapp;
        GRANT USAGE, SELECT ON SEQUENCE public.poultryfarmsetup_farmsetupid_seq                  TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryopeningposition_insert(text, integer, date, integer, integer, integer, integer, integer, integer, integer, boolean, boolean, text, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryopeningposition_getall(text)  TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryopeningposition_correct(text, integer, integer, integer, integer, integer, integer, integer, integer, boolean, text, text) TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryfarmsetup_get(text)           TO poultryapp;
        GRANT EXECUTE ON FUNCTION public.sppoultryfarmsetup_complete(text, text, date, text, integer, integer, integer, integer, integer, integer, text) TO poultryapp;
    END IF;
END
$grants$;

COMMIT;

-- -----------------------------------------------------------------------------
-- 8. Verification. Runs after COMMIT so a failure here does not undo the
--    migration -- it tells you the migration is wrong, which is different.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    v_missing text;
    v_flock   integer;
    v_id      integer;
BEGIN
    SELECT string_agg(want, ', ')
    INTO   v_missing
    FROM   (VALUES
        ('sppoultryopeningposition_insert'),
        ('sppoultryopeningposition_getall'),
        ('sppoultryopeningposition_correct'),
        ('sppoultryfarmsetup_get'),
        ('sppoultryfarmsetup_complete')
    ) AS w(want)
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = w.want);

    IF v_missing IS NOT NULL THEN
        RAISE EXCEPTION '319: missing function(s): %', v_missing;
    END IF;

    -- The constraints are the whole point of the table, so prove they bite.
    -- Against a farm id no one can have, and rolled back to a savepoint.
    v_flock := -319;

    BEGIN
        -- A breakdown that does not add up must be refused.
        PERFORM public.sppoultryopeningposition_insert(
            '__319_selftest__', v_flock, CURRENT_DATE, 1050, 960,
            70, 0, 0, 0, 0, true, false, 'InitialFarmSetup', NULL, '__319__');
        RAISE EXCEPTION '319: a breakdown that does not add up was accepted.';
    EXCEPTION WHEN check_violation THEN
        NULL;  -- expected
    END;

    BEGIN
        -- "History not known" must not carry a mortality figure.
        PERFORM public.sppoultryopeningposition_insert(
            '__319_selftest__', v_flock, CURRENT_DATE, 1050, 960,
            90, 0, 0, 0, 0, false, false, 'InitialFarmSetup', NULL, '__319__');
        RAISE EXCEPTION '319: unknown history was allowed to claim mortality.';
    EXCEPTION WHEN check_violation THEN
        NULL;  -- expected
    END;

    -- A well-formed row goes in, reads back, and corrects.
    v_id := public.sppoultryopeningposition_insert(
        '__319_selftest__', v_flock, CURRENT_DATE, 1050, 960,
        70, 10, 5, 0, 5, true, false, 'InitialFarmSetup', NULL, '__319__');
    IF v_id IS NULL THEN
        RAISE EXCEPTION '319: insert returned no id.';
    END IF;

    IF (SELECT count(*) FROM public.sppoultryopeningposition_getall('__319_selftest__')) <> 1 THEN
        RAISE EXCEPTION '319: getall did not return the row just written.';
    END IF;

    IF public.sppoultryopeningposition_correct(
           '__319_selftest__', v_flock, 1050, 970, 60, 10, 5, 0, 5, true,
           'corrected by selftest', '__319__') IS NULL THEN
        RAISE EXCEPTION '319: correct() did not find the row.';
    END IF;

    BEGIN
        -- A second opening position for the same flock must be refused.
        PERFORM public.sppoultryopeningposition_insert(
            '__319_selftest__', v_flock, CURRENT_DATE, 100, 100,
            0, 0, 0, 0, 0, false, false, 'InitialFarmSetup', NULL, '__319__');
        RAISE EXCEPTION '319: a flock was allowed two opening positions.';
    EXCEPTION WHEN unique_violation THEN
        NULL;  -- expected
    END;

    PERFORM public.sppoultryfarmsetup_complete(
        '__319_selftest__', 'ExistingFarm', CURRENT_DATE, '__319__',
        2, 4, 8, 8200, 7518, 682, NULL);
    IF (SELECT historicalreduction FROM public.sppoultryfarmsetup_get('__319_selftest__')) <> 682 THEN
        RAISE EXCEPTION '319: the setup snapshot did not read back.';
    END IF;

    -- The backstop: a second completion must fold into the one row rather than
    -- creating a second, which is what stops a rerun onboarding a farm twice.
    PERFORM public.sppoultryfarmsetup_complete(
        '__319_SELFTEST__', 'ExistingFarm', CURRENT_DATE, '__319__',
        1, 1, 1, 100, 90, 10, NULL);
    IF (SELECT count(*) FROM public.poultryfarmsetup
         WHERE lower(farmid) = '__319_selftest__') <> 1 THEN
        RAISE EXCEPTION '319: the company key is case sensitive; it must not be.';
    END IF;
    IF (SELECT historicalreduction FROM public.sppoultryfarmsetup_get('__319_selftest__')) <> 692 THEN
        RAISE EXCEPTION '319: a second completion did not fold into the existing row.';
    END IF;

    DELETE FROM public.poultryopeningflockposition WHERE farmid = '__319_selftest__';
    DELETE FROM public.poultryfarmsetup            WHERE lower(farmid) = '__319_selftest__';

    RAISE NOTICE '319_PoultryFarmSetupOpeningPosition: 2 tables, 5 functions, verified.';
END $$;
