-- =============================================================================
-- 348  Recurring Expense Engine -- shared by every company type
-- =============================================================================
--
-- WHAT THIS IS
-- ------------
-- Rent, security, internet, software, waste collection, fixed service fees:
-- a business writes the same expense every period. A Recurring Expense
-- TEMPLATE says what, how much, how often and from when; the engine works out
-- each due date and, when one arrives, raises a DRAFT for a person to review,
-- adjust (amount, date, cash account) and then POST or SKIP.
--
-- ONE ENGINE, FIVE EXPENSE MODULES
-- --------------------------------
-- Poultry, Water, Generic, Hotel and Restaurant each keep their own expense
-- table, cash posting and payables, and those stay the authority. This file
-- owns only what is common: templates, their occurrences, the recurrence
-- arithmetic, idempotency and history. A template carries `module`; its
-- supplier / cash account / category ids are that module's own ids, checked
-- against that module's tables by fnrecurringexpense_refok.
--
-- POSTING is done by the API through each module's EXISTING expense service
-- (the same call its Expenses page makes), so cash, supplier payments and
-- payables follow that module's rules exactly. Nothing here writes an expense
-- row or a cash row. The handshake that keeps it idempotent:
--
--     claim     Draft -> Posting (row lock; a second claim is refused)
--     post      the module creates the expense
--     complete  Posting -> Posted, expense id recorded
--     release   Posting -> Draft if the module refused
--
-- A Posting claim that is never completed (the API died mid-post) is NOT
-- retried automatically -- that is how a double expense happens. It shows as
-- "Posting interrupted"; a person either links the expense that was created
-- or releases it back to Draft.
--
-- DRAFTS LIVE HERE, NOT IN THE EXPENSE TABLES
-- -------------------------------------------
-- No module's expense table has a draft state its readers respect (Poultry's
-- has no status at all), so a draft row there would reach P&L, cash flow and
-- daily closing the moment it existed. A draft is an occurrence row; it
-- becomes an expense only when posted.
--
-- RECURRENCE (fnrecurringexpense_occurrencedate)
-- ----------------------------------------------
-- Occurrence N is computed from the START DATE, never chained from the
-- previous occurrence:
--     Weekly      start + 7N days          Biweekly    start + 14N days
--     Monthly     start + N months         Quarterly   start + 3N months
--     SemiAnnual  start + 6N months        Annual      start + N years
-- Postgres clamps month arithmetic to the month's last day, and because each
-- date comes from the anchor the clamp never compounds:
--     start 31 Jan -> 31 Jan, 28 Feb (29 in a leap year), 31 Mar, 30 Apr ...
--     start 29 Feb 2028 (Annual) -> 28 Feb 2029, ..., 29 Feb 2032
-- (The older Generic-only fngenericnextduedate chains, so 31 Jan drifts to
-- 28 Feb and then 28 Mar. It is left in place for the legacy Generic page.)
--
-- IDEMPOTENCY
-- -----------
-- An occurrence's identity is (template, occurrence number). UNIQUE on it,
-- and generation inserts ON CONFLICT DO NOTHING under a per-company advisory
-- lock, so running generation twice -- or from two browsers at once -- cannot
-- raise September's rent twice. Skipping or posting September does not free
-- its number either.
--
-- DATES: "due" is judged on fncompany_businessdate(farm), the company's date
-- in its own time zone.
--
-- PAUSE / RESUME / END
-- --------------------
--   Pause   no new drafts while paused.
--   Resume  continues from today: occurrences that fell during the pause are
--           not raised (generatefrom moves to the resume date).
--   End     no occurrences after the end date. Existing drafts stay for
--           review; posted expenses are never touched.
-- A template with any occurrence cannot be deleted, and its frequency and
-- start date are frozen (they define every occurrence's identity).
--
-- Idempotent. PostgreSQL.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------- 1. tables --
CREATE TABLE IF NOT EXISTS public.recurringexpensetemplates (
    templateid       serial PRIMARY KEY,
    farmid           text          NOT NULL,
    module           text          NOT NULL,
    name             text          NOT NULL,
    categoryid       integer       NULL,   -- the module's category id (Water/Generic/Hotel/Restaurant)
    categoryname     text          NULL,   -- Poultry's free-text category, and a display copy for the rest
    supplierid       integer       NULL,   -- the module's supplier id
    payeename        text          NULL,
    amount           numeric(14,2) NOT NULL,
    isvariable       boolean       NOT NULL DEFAULT FALSE,   -- amount is an estimate; confirm each time
    frequency        text          NOT NULL,
    startdate        date          NOT NULL,
    enddate          date          NULL,
    generatefrom     date          NOT NULL,                 -- moved forward by Resume
    paymentmethod    text          NOT NULL DEFAULT 'Cash',  -- 'Credit' = posted unpaid
    cashaccountid    integer       NULL,
    description      text          NULL,
    approvalmode     text          NOT NULL DEFAULT 'Draft', -- 'Draft' (review) | 'AutoPost'
    status           text          NOT NULL DEFAULT 'Active',
    createdby        text          NULL,
    createdat        timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby        text          NULL,
    updatedat        timestamp     NULL,
    pausedby         text          NULL,
    pausedat         timestamp     NULL,
    endedby          text          NULL,
    endedat          timestamp     NULL,
    endreason        text          NULL,
    CONSTRAINT ck_recexp_module    CHECK (module IN ('poultry', 'water', 'generic', 'hotel', 'restaurant')),
    CONSTRAINT ck_recexp_name      CHECK (btrim(name) <> ''),
    CONSTRAINT ck_recexp_amount    CHECK (amount > 0),
    CONSTRAINT ck_recexp_frequency CHECK (frequency IN ('Weekly', 'Biweekly', 'Monthly', 'Quarterly', 'SemiAnnual', 'Annual')),
    CONSTRAINT ck_recexp_dates     CHECK (enddate IS NULL OR enddate >= startdate),
    CONSTRAINT ck_recexp_approval  CHECK (approvalmode IN ('Draft', 'AutoPost')),
    CONSTRAINT ck_recexp_status    CHECK (status IN ('Active', 'Paused', 'Ended'))
);
CREATE INDEX IF NOT EXISTS ix_recexp_farm ON public.recurringexpensetemplates (farmid, status);

CREATE TABLE IF NOT EXISTS public.recurringexpenseoccurrences (
    occurrenceid     serial PRIMARY KEY,
    templateid       integer       NOT NULL REFERENCES public.recurringexpensetemplates (templateid),
    farmid           text          NOT NULL,
    module           text          NOT NULL,
    occurrenceno     integer       NOT NULL,   -- 0-based index from the template's start date
    scheduleddate    date          NOT NULL,
    status           text          NOT NULL DEFAULT 'Draft',
    -- The reviewable figures, seeded from the template and editable while Draft.
    amount           numeric(14,2) NOT NULL,
    expensedate      date          NOT NULL,
    paymentmethod    text          NOT NULL,
    cashaccountid    integer       NULL,
    supplierid       integer       NULL,
    description      text          NULL,
    note             text          NULL,
    -- Posting.
    claimtoken       uuid          NULL,
    claimedby        text          NULL,
    claimedat        timestamp     NULL,
    expenseid        integer       NULL,      -- the module's expense row
    postedby         text          NULL,
    postedat         timestamp     NULL,
    skippedby        text          NULL,
    skippedat        timestamp     NULL,
    skipreason       text          NULL,
    createdat        timestamp     NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedat        timestamp     NULL,
    CONSTRAINT ck_recocc_status CHECK (status IN ('Draft', 'Posting', 'Posted', 'Skipped')),
    CONSTRAINT ck_recocc_amount CHECK (amount > 0),
    CONSTRAINT ck_recocc_posted CHECK ((status = 'Posted') = (expenseid IS NOT NULL)),
    CONSTRAINT ux_recocc_identity UNIQUE (templateid, occurrenceno)
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_recocc_expense
    ON public.recurringexpenseoccurrences (module, farmid, expenseid) WHERE expenseid IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_recocc_farm ON public.recurringexpenseoccurrences (farmid, status, scheduleddate);

CREATE TABLE IF NOT EXISTS public.recurringexpenseevents (
    eventid       bigserial PRIMARY KEY,
    farmid        text        NOT NULL,
    templateid    integer     NOT NULL,
    occurrenceid  integer     NULL,
    eventtype     text        NOT NULL,   -- TemplateCreated/Updated/Paused/Resumed/Ended, Generated, Edited, Posted, Skipped, Restored, Released
    details       jsonb       NULL,
    actor         text        NULL,
    atutc         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_recexpevents ON public.recurringexpenseevents (farmid, templateid, eventid);

CREATE OR REPLACE FUNCTION public.trg_recurringexpenseevents_appendonly_fn()
RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
    RAISE EXCEPTION 'Recurring expense history is append-only.';
END $f$;
DROP TRIGGER IF EXISTS trg_recurringexpenseevents_appendonly ON public.recurringexpenseevents;
CREATE TRIGGER trg_recurringexpenseevents_appendonly
    BEFORE UPDATE OR DELETE ON public.recurringexpenseevents
    FOR EACH ROW EXECUTE FUNCTION public.trg_recurringexpenseevents_appendonly_fn();

-- --------------------------------------------- 2. drop old overloads by name --
DO $d$ DECLARE r record; BEGIN
    FOR r IN SELECT p.oid::regprocedure::text AS sig FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname LIKE ANY (ARRAY['fnrecurringexpense\_%', 'sprecurringexpense\_%'])
    LOOP EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig; END LOOP;
END $d$;

-- ------------------------------------------------------ 3. module adapters ----
-- The module of a company, from its type. Legacy poultry farms carry NULL.
CREATE FUNCTION public.fnrecurringexpense_module(p_farmid text)
RETURNS text LANGUAGE sql STABLE AS $f$
    SELECT CASE lower(COALESCE(NULLIF(btrim(spfarm_gettype(p_farmid)), ''), 'poultry'))
               WHEN 'poultry' THEN 'poultry' WHEN 'water' THEN 'water' WHEN 'generic' THEN 'generic'
               WHEN 'hotel' THEN 'hotel' WHEN 'restaurant' THEN 'restaurant' ELSE NULL END;
$f$;

-- Does this module-specific id belong to this company? kind = supplier | cashaccount | category.
CREATE FUNCTION public.fnrecurringexpense_refok(p_module text, p_kind text, p_id integer, p_farmid text)
RETURNS boolean LANGUAGE plpgsql STABLE AS $f$
DECLARE
    v_tbl text; v_col text; v_ok boolean;
BEGIN
    IF p_id IS NULL THEN RETURN TRUE; END IF;
    SELECT t.tbl, t.col INTO v_tbl, v_col FROM (VALUES
        ('poultry',    'supplier',    'supplier',                    'supplierid'),
        ('poultry',    'cashaccount', 'poultrycashaccounts',         'poultrycashaccountid'),
        ('water',      'supplier',    'watersuppliers',              'watersupplierid'),
        ('water',      'cashaccount', 'watercashaccounts',           'watercashaccountid'),
        ('water',      'category',    'waterexpensecategories',      'waterexpensecategoryid'),
        ('generic',    'supplier',    'genericsuppliers',            'genericsupplierid'),
        ('generic',    'cashaccount', 'genericcashaccounts',         'genericcashaccountid'),
        ('generic',    'category',    'genericexpensecategories',    'genericexpensecategoryid'),
        ('hotel',      'supplier',    'hotelsuppliers',              'hotelsupplierid'),
        ('hotel',      'cashaccount', 'hotelcashaccounts',           'hotelcashaccountid'),
        ('hotel',      'category',    'hotelexpensecategories',      'hotelexpensecategoryid'),
        ('restaurant', 'supplier',    'restaurantsuppliers',         'restaurantsupplierid'),
        ('restaurant', 'cashaccount', 'restaurantcashaccounts',      'cashaccountid'),
        ('restaurant', 'category',    'restaurantexpensecategories', 'expensecategoryid')
    ) AS t(module, kind, tbl, col)
    WHERE t.module = p_module AND t.kind = p_kind;
    IF v_tbl IS NULL THEN RETURN FALSE; END IF;   -- e.g. a poultry category id: Poultry categories are text
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM %I WHERE %I = $1 AND farmid::text = $2)', v_tbl, v_col)
       INTO v_ok USING p_id, p_farmid;
    RETURN v_ok;
END $f$;

-- ------------------------------------------------------- 4. recurrence -------
CREATE FUNCTION public.fnrecurringexpense_occurrencedate(p_start date, p_frequency text, p_n integer)
RETURNS date LANGUAGE sql IMMUTABLE AS $f$
    SELECT (CASE p_frequency
                WHEN 'Weekly'     THEN p_start + (7 * p_n)
                WHEN 'Biweekly'   THEN p_start + (14 * p_n)
                WHEN 'Monthly'    THEN (p_start + make_interval(months => p_n))::date
                WHEN 'Quarterly'  THEN (p_start + make_interval(months => 3 * p_n))::date
                WHEN 'SemiAnnual' THEN (p_start + make_interval(months => 6 * p_n))::date
                WHEN 'Annual'     THEN (p_start + make_interval(years => p_n))::date
            END)::date;
$f$;

-- Every occurrence of a template falling in [p_from, p_to], with its number.
CREATE FUNCTION public.fnrecurringexpense_series(p_start date, p_frequency text, p_enddate date, p_from date, p_to date)
RETURNS TABLE(occurrenceno integer, scheduleddate date)
LANGUAGE plpgsql IMMUTABLE AS $f$
DECLARE
    v_n    integer;
    v_d    date;
    v_days integer := CASE p_frequency WHEN 'Weekly' THEN 7 WHEN 'Biweekly' THEN 14 WHEN 'Monthly' THEN 28
                                       WHEN 'Quarterly' THEN 89 WHEN 'SemiAnnual' THEN 181 ELSE 365 END;
BEGIN
    IF p_to < p_from THEN RETURN; END IF;
    -- Jump close to p_from without overshooting (the per-step minimum length
    -- guarantees n never skips an occurrence), then walk.
    v_n := GREATEST(0, (p_from - p_start) / v_days - 1);
    LOOP
        v_d := fnrecurringexpense_occurrencedate(p_start, p_frequency, v_n);
        EXIT WHEN v_d > p_to OR (p_enddate IS NOT NULL AND v_d > p_enddate);
        IF v_d >= p_from THEN
            occurrenceno := v_n; scheduleddate := v_d; RETURN NEXT;
        END IF;
        v_n := v_n + 1;
        EXIT WHEN v_n > 100000;
    END LOOP;
END $f$;

-- ------------------------------------------------------- 5. events -----------
CREATE FUNCTION public.fnrecurringexpense_log(p_farmid text, p_templateid integer, p_occurrenceid integer,
                                              p_type text, p_details jsonb, p_actor text)
RETURNS void LANGUAGE sql AS $f$
    INSERT INTO recurringexpenseevents (farmid, templateid, occurrenceid, eventtype, details, actor)
    VALUES (p_farmid, p_templateid, p_occurrenceid, p_type, p_details, p_actor);
$f$;

-- ------------------------------------------------------- 6. templates --------
CREATE FUNCTION public.sprecurringexpense_savetemplate(
    p_farmid        text,
    p_templateid    integer,
    p_name          text,
    p_categoryid    integer,
    p_categoryname  text,
    p_supplierid    integer,
    p_payeename     text,
    p_amount        numeric,
    p_isvariable    boolean,
    p_frequency     text,
    p_startdate     date,
    p_enddate       date,
    p_paymentmethod text,
    p_cashaccountid integer,
    p_description   text,
    p_approvalmode  text,
    p_actor         text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql AS $f$
DECLARE
    v_module text := fnrecurringexpense_module(p_farmid);
    v_id     integer := p_templateid;
    v_old    record;
    v_hasocc boolean := FALSE;
    v_method text := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash');
BEGIN
    IF COALESCE(btrim(p_farmid), '') = '' THEN RAISE EXCEPTION 'Company is required.'; END IF;
    IF v_module IS NULL THEN RAISE EXCEPTION 'Recurring expenses are not available for this company type.'; END IF;
    IF COALESCE(btrim(p_name), '') = '' THEN RAISE EXCEPTION 'Give the recurring expense a name.'; END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'The amount must be greater than 0.'; END IF;
    IF p_frequency NOT IN ('Weekly', 'Biweekly', 'Monthly', 'Quarterly', 'SemiAnnual', 'Annual') THEN
        RAISE EXCEPTION 'Choose how often it repeats.';
    END IF;
    IF p_startdate IS NULL THEN RAISE EXCEPTION 'Choose the first date it is due.'; END IF;
    IF p_enddate IS NOT NULL AND p_enddate < p_startdate THEN
        RAISE EXCEPTION 'The end date (%) is before the start date (%).', p_enddate, p_startdate;
    END IF;
    IF COALESCE(p_approvalmode, 'Draft') NOT IN ('Draft', 'AutoPost') THEN
        RAISE EXCEPTION 'Approval must be Draft (review first) or AutoPost.';
    END IF;
    IF v_module = 'poultry' AND COALESCE(btrim(p_categoryname), '') = '' THEN
        RAISE EXCEPTION 'Choose a category.';
    END IF;
    IF v_module <> 'poultry' AND p_categoryid IS NULL THEN RAISE EXCEPTION 'Choose a category.'; END IF;
    IF v_module <> 'poultry' AND NOT fnrecurringexpense_refok(v_module, 'category', p_categoryid, p_farmid) THEN
        RAISE EXCEPTION 'That category does not belong to this company.';
    END IF;
    IF NOT fnrecurringexpense_refok(v_module, 'supplier', p_supplierid, p_farmid) THEN
        RAISE EXCEPTION 'That supplier does not belong to this company.';
    END IF;
    IF NOT fnrecurringexpense_refok(v_module, 'cashaccount', p_cashaccountid, p_farmid) THEN
        RAISE EXCEPTION 'That cash account does not belong to this company.';
    END IF;
    IF v_method = 'Credit' AND p_supplierid IS NULL THEN
        RAISE EXCEPTION 'An expense bought on credit needs a supplier, so it can be owed to someone.';
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO recurringexpensetemplates
            (farmid, module, name, categoryid, categoryname, supplierid, payeename, amount, isvariable,
             frequency, startdate, enddate, generatefrom, paymentmethod, cashaccountid, description,
             approvalmode, createdby)
        VALUES (p_farmid, v_module, btrim(p_name), p_categoryid, NULLIF(btrim(p_categoryname), ''), p_supplierid,
                NULLIF(btrim(p_payeename), ''), round(p_amount, 2), COALESCE(p_isvariable, FALSE),
                p_frequency, p_startdate, p_enddate, p_startdate, v_method, p_cashaccountid,
                NULLIF(btrim(p_description), ''), COALESCE(p_approvalmode, 'Draft'), p_actor)
        RETURNING templateid INTO v_id;
        PERFORM fnrecurringexpense_log(p_farmid, v_id, NULL, 'TemplateCreated', NULL, p_actor);
        RETURN v_id;
    END IF;

    SELECT t.* INTO v_old FROM recurringexpensetemplates t WHERE t.templateid = v_id AND t.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Recurring expense not found for this company.'; END IF;
    IF v_old.status = 'Ended' THEN RAISE EXCEPTION 'This recurring expense has ended and can no longer be edited.'; END IF;
    v_hasocc := EXISTS (SELECT 1 FROM recurringexpenseoccurrences o WHERE o.templateid = v_id);
    IF v_hasocc AND (p_frequency <> v_old.frequency OR p_startdate <> v_old.startdate) THEN
        RAISE EXCEPTION 'The frequency and start date cannot change once an occurrence exists -- they define which period each one is. End this one and create a new recurring expense instead.';
    END IF;

    UPDATE recurringexpensetemplates t
    SET    name = btrim(p_name), categoryid = p_categoryid, categoryname = NULLIF(btrim(p_categoryname), ''),
           supplierid = p_supplierid, payeename = NULLIF(btrim(p_payeename), ''), amount = round(p_amount, 2),
           isvariable = COALESCE(p_isvariable, FALSE), frequency = p_frequency, startdate = p_startdate,
           enddate = p_enddate,
           generatefrom = CASE WHEN v_hasocc THEN t.generatefrom ELSE p_startdate END,
           paymentmethod = v_method, cashaccountid = p_cashaccountid,
           description = NULLIF(btrim(p_description), ''), approvalmode = COALESCE(p_approvalmode, 'Draft'),
           updatedby = p_actor, updatedat = (now() at time zone 'utc')
    WHERE  t.templateid = v_id;
    PERFORM fnrecurringexpense_log(p_farmid, v_id, NULL, 'TemplateUpdated',
        jsonb_build_object('amount', jsonb_build_array(v_old.amount, round(p_amount, 2))), p_actor);
    RETURN v_id;
END $f$;

-- 'Pause' | 'Resume' | 'End'
CREATE FUNCTION public.sprecurringexpense_setstatus(p_farmid text, p_templateid integer, p_action text,
                                                   p_reason text DEFAULT NULL, p_actor text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql AS $f$
DECLARE
    v_t     record;
    v_today date := fncompany_businessdate(p_farmid);
BEGIN
    SELECT t.* INTO v_t FROM recurringexpensetemplates t WHERE t.templateid = p_templateid AND t.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Recurring expense not found for this company.'; END IF;
    IF v_t.status = 'Ended' THEN RAISE EXCEPTION 'This recurring expense has already ended.'; END IF;

    IF p_action = 'Pause' THEN
        IF v_t.status = 'Paused' THEN RAISE EXCEPTION 'It is already paused.'; END IF;
        UPDATE recurringexpensetemplates SET status = 'Paused', pausedby = p_actor, pausedat = (now() at time zone 'utc'),
               updatedat = (now() at time zone 'utc') WHERE templateid = p_templateid;
    ELSIF p_action = 'Resume' THEN
        IF v_t.status <> 'Paused' THEN RAISE EXCEPTION 'It is not paused.'; END IF;
        -- Continue from today: what fell due during the pause is not raised.
        UPDATE recurringexpensetemplates SET status = 'Active', generatefrom = GREATEST(generatefrom, v_today),
               pausedby = NULL, pausedat = NULL, updatedat = (now() at time zone 'utc') WHERE templateid = p_templateid;
    ELSIF p_action = 'End' THEN
        UPDATE recurringexpensetemplates SET status = 'Ended',
               enddate = LEAST(COALESCE(enddate, v_today), GREATEST(v_today, startdate)),
               endedby = p_actor, endedat = (now() at time zone 'utc'), endreason = NULLIF(btrim(p_reason), ''),
               updatedat = (now() at time zone 'utc') WHERE templateid = p_templateid;
    ELSE
        RAISE EXCEPTION 'Action must be Pause, Resume or End.';
    END IF;
    PERFORM fnrecurringexpense_log(p_farmid, p_templateid, NULL,
        CASE p_action WHEN 'Pause' THEN 'TemplatePaused' WHEN 'Resume' THEN 'TemplateResumed' ELSE 'TemplateEnded' END,
        CASE WHEN NULLIF(btrim(p_reason), '') IS NOT NULL THEN jsonb_build_object('reason', btrim(p_reason)) END, p_actor);
    RETURN (SELECT status FROM recurringexpensetemplates WHERE templateid = p_templateid);
END $f$;

-- Only a template that never produced anything may be deleted.
CREATE FUNCTION public.sprecurringexpense_deletetemplate(p_farmid text, p_templateid integer, p_actor text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql AS $f$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM recurringexpensetemplates t WHERE t.templateid = p_templateid AND t.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Recurring expense not found for this company.';
    END IF;
    IF EXISTS (SELECT 1 FROM recurringexpenseoccurrences o WHERE o.templateid = p_templateid) THEN
        RAISE EXCEPTION 'This recurring expense has history. End it instead -- its expenses stay as they are.';
    END IF;
    -- No occurrences means no history worth keeping beyond its own creation event.
    DELETE FROM recurringexpensetemplates t WHERE t.templateid = p_templateid AND t.farmid = p_farmid;
END $f$;

CREATE FUNCTION public.sprecurringexpense_gettemplates(p_farmid text)
RETURNS TABLE(templateid integer, module text, name text, categoryid integer, categoryname text,
              supplierid integer, payeename text, amount numeric, isvariable boolean, frequency text,
              startdate date, enddate date, generatefrom date, paymentmethod text, cashaccountid integer,
              description text, approvalmode text, status text, nextduedate date, drafts integer,
              posted integer, skipped integer, lastpostedat timestamp,
              createdby text, createdat timestamp, endedat timestamp, endreason text)
LANGUAGE sql STABLE AS $f$
    SELECT t.templateid, t.module, t.name, t.categoryid, t.categoryname, t.supplierid, t.payeename, t.amount,
           t.isvariable, t.frequency, t.startdate, t.enddate, t.generatefrom, t.paymentmethod, t.cashaccountid,
           t.description, t.approvalmode, t.status,
           (CASE WHEN t.status = 'Ended' THEN NULL ELSE
               (SELECT s.scheduleddate FROM fnrecurringexpense_series(t.startdate, t.frequency, t.enddate,
                          GREATEST(t.generatefrom, fncompany_businessdate(t.farmid)),
                          GREATEST(t.generatefrom, fncompany_businessdate(t.farmid)) + 800) s
                WHERE NOT EXISTS (SELECT 1 FROM recurringexpenseoccurrences o
                                  WHERE o.templateid = t.templateid AND o.occurrenceno = s.occurrenceno)
                ORDER BY s.scheduleddate LIMIT 1) END),
           (SELECT COUNT(*) FROM recurringexpenseoccurrences o WHERE o.templateid = t.templateid AND o.status IN ('Draft', 'Posting'))::int,
           (SELECT COUNT(*) FROM recurringexpenseoccurrences o WHERE o.templateid = t.templateid AND o.status = 'Posted')::int,
           (SELECT COUNT(*) FROM recurringexpenseoccurrences o WHERE o.templateid = t.templateid AND o.status = 'Skipped')::int,
           (SELECT MAX(o.postedat) FROM recurringexpenseoccurrences o WHERE o.templateid = t.templateid),
           t.createdby, t.createdat, t.endedat, t.endreason
    FROM   recurringexpensetemplates t
    WHERE  t.farmid = p_farmid
    ORDER  BY CASE t.status WHEN 'Active' THEN 0 WHEN 'Paused' THEN 1 ELSE 2 END, lower(t.name);
$f$;

-- ------------------------------------------------------- 7. generation -------
-- Raises a Draft for every occurrence due on or before p_asof (default: the
-- company's today) that does not exist yet. Safe to call any number of times.
-- Returns the occurrences it created (AutoPost ones included -- the API posts
-- those straight after, through the module's expense service).
CREATE FUNCTION public.sprecurringexpense_generate(p_farmid text, p_asof date DEFAULT NULL, p_actor text DEFAULT NULL)
RETURNS TABLE(occurrenceid integer, templateid integer, approvalmode text)
LANGUAGE plpgsql AS $f$
DECLARE
    v_asof date := COALESCE(p_asof, fncompany_businessdate(p_farmid));
    t      record;
    s      record;
    v_id   integer;
    v_n    integer;
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext('recurringexpense:' || lower(p_farmid)));
    FOR t IN SELECT x.* FROM recurringexpensetemplates x
             WHERE x.farmid = p_farmid AND x.status = 'Active' AND x.generatefrom <= v_asof
             ORDER BY x.templateid LOOP
        v_n := 0;
        FOR s IN SELECT * FROM fnrecurringexpense_series(t.startdate, t.frequency, t.enddate, t.generatefrom, v_asof)
                 ORDER BY 1 LOOP
            EXIT WHEN v_n >= 60;   -- a template two years behind catches up over a few calls, not one
            INSERT INTO recurringexpenseoccurrences
                (templateid, farmid, module, occurrenceno, scheduleddate, status, amount, expensedate,
                 paymentmethod, cashaccountid, supplierid, description)
            VALUES (t.templateid, p_farmid, t.module, s.occurrenceno, s.scheduleddate, 'Draft', t.amount,
                    s.scheduleddate, t.paymentmethod, t.cashaccountid, t.supplierid,
                    t.name || ' (' || to_char(s.scheduleddate, 'DD Mon YYYY') || ')'
                        || COALESCE(' -- ' || t.description, ''))
            ON CONFLICT ON CONSTRAINT ux_recocc_identity DO NOTHING
            RETURNING recurringexpenseoccurrences.occurrenceid INTO v_id;
            IF v_id IS NOT NULL THEN
                PERFORM fnrecurringexpense_log(p_farmid, t.templateid, v_id, 'Generated',
                    jsonb_build_object('scheduleddate', s.scheduleddate, 'occurrenceno', s.occurrenceno), p_actor);
                occurrenceid := v_id; templateid := t.templateid; approvalmode := t.approvalmode;
                RETURN NEXT;
                v_n := v_n + 1;
                v_id := NULL;
            END IF;
        END LOOP;
    END LOOP;
END $f$;

-- Upcoming = not yet raised, due in the next p_days (7 / 30 ...), active templates only.
CREATE FUNCTION public.sprecurringexpense_upcoming(p_farmid text, p_days integer DEFAULT 30)
RETURNS TABLE(templateid integer, name text, categoryname text, amount numeric, isvariable boolean,
              frequency text, occurrenceno integer, scheduleddate date, daysaway integer, today date)
LANGUAGE sql STABLE AS $f$
    WITH d AS (SELECT fncompany_businessdate(p_farmid) AS today)
    SELECT t.templateid, t.name, t.categoryname, t.amount, t.isvariable, t.frequency,
           s.occurrenceno, s.scheduleddate, (s.scheduleddate - d.today)::int, d.today
    FROM   recurringexpensetemplates t
    CROSS  JOIN d
    CROSS  JOIN LATERAL fnrecurringexpense_series(t.startdate, t.frequency, t.enddate,
                    GREATEST(t.generatefrom, d.today + 1), d.today + GREATEST(COALESCE(p_days, 30), 0)) s
    WHERE  t.farmid = p_farmid AND t.status = 'Active'
      AND  NOT EXISTS (SELECT 1 FROM recurringexpenseoccurrences o
                       WHERE o.templateid = t.templateid AND o.occurrenceno = s.occurrenceno)
    ORDER  BY s.scheduleddate, t.name;
$f$;

-- ------------------------------------------------------- 8. occurrences ------
CREATE FUNCTION public.sprecurringexpense_getoccurrences(p_farmid text, p_status text DEFAULT NULL, p_templateid integer DEFAULT NULL)
RETURNS TABLE(occurrenceid integer, templateid integer, templatename text, module text, occurrenceno integer,
              scheduleddate date, status text, amount numeric, templateamount numeric, isvariable boolean,
              expensedate date, paymentmethod text, cashaccountid integer, supplierid integer,
              categoryid integer, categoryname text, payeename text, description text, note text,
              expenseid integer, postedby text, postedat timestamp, skippedby text, skippedat timestamp,
              skipreason text, claimedby text, claimedat timestamp, isinterrupted boolean, createdat timestamp)
LANGUAGE sql STABLE AS $f$
    SELECT o.occurrenceid, o.templateid, t.name, o.module, o.occurrenceno, o.scheduleddate, o.status, o.amount,
           t.amount, t.isvariable, o.expensedate, o.paymentmethod, o.cashaccountid, o.supplierid,
           t.categoryid, t.categoryname, t.payeename, o.description, o.note, o.expenseid,
           o.postedby, o.postedat, o.skippedby, o.skippedat, o.skipreason, o.claimedby, o.claimedat,
           (o.status = 'Posting' AND o.claimedat < (now() at time zone 'utc') - interval '10 minutes'),
           o.createdat
    FROM   recurringexpenseoccurrences o
    JOIN   recurringexpensetemplates t ON t.templateid = o.templateid
    WHERE  o.farmid = p_farmid
      AND  (p_templateid IS NULL OR o.templateid = p_templateid)
      AND  (p_status IS NULL OR p_status = 'All' OR o.status = p_status
            OR (p_status = 'Open' AND o.status IN ('Draft', 'Posting')))
    ORDER  BY CASE o.status WHEN 'Posting' THEN 0 WHEN 'Draft' THEN 1 ELSE 2 END, o.scheduleddate DESC, o.occurrenceid DESC;
$f$;

-- Review edits on a Draft: amount, date, cash account, payment method, supplier, note.
CREATE FUNCTION public.sprecurringexpense_editoccurrence(
    p_farmid text, p_occurrenceid integer, p_amount numeric, p_expensedate date, p_paymentmethod text,
    p_cashaccountid integer, p_supplierid integer, p_description text, p_note text, p_actor text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql AS $f$
DECLARE
    o record;
    v_method text := COALESCE(NULLIF(btrim(p_paymentmethod), ''), 'Cash');
BEGIN
    SELECT x.* INTO o FROM recurringexpenseoccurrences x WHERE x.occurrenceid = p_occurrenceid AND x.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Recurring expense occurrence not found for this company.'; END IF;
    IF o.status <> 'Draft' THEN RAISE EXCEPTION 'Only a draft can be edited (this one is %).', lower(o.status); END IF;
    IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'The amount must be greater than 0.'; END IF;
    IF p_expensedate IS NULL THEN RAISE EXCEPTION 'Choose the expense date.'; END IF;
    IF p_expensedate > fncompany_businessdate(p_farmid) THEN
        RAISE EXCEPTION 'The expense date (%) is in the future.', p_expensedate;
    END IF;
    IF NOT fnrecurringexpense_refok(o.module, 'cashaccount', p_cashaccountid, p_farmid) THEN
        RAISE EXCEPTION 'That cash account does not belong to this company.';
    END IF;
    IF NOT fnrecurringexpense_refok(o.module, 'supplier', p_supplierid, p_farmid) THEN
        RAISE EXCEPTION 'That supplier does not belong to this company.';
    END IF;
    IF v_method = 'Credit' AND p_supplierid IS NULL THEN
        RAISE EXCEPTION 'An expense bought on credit needs a supplier, so it can be owed to someone.';
    END IF;
    UPDATE recurringexpenseoccurrences x
    SET    amount = round(p_amount, 2), expensedate = p_expensedate, paymentmethod = v_method,
           cashaccountid = p_cashaccountid, supplierid = p_supplierid,
           description = COALESCE(NULLIF(btrim(p_description), ''), x.description),
           note = NULLIF(btrim(p_note), ''), updatedat = (now() at time zone 'utc')
    WHERE  x.occurrenceid = p_occurrenceid;
    PERFORM fnrecurringexpense_log(p_farmid, o.templateid, p_occurrenceid, 'Edited',
        jsonb_build_object('amount', jsonb_build_array(o.amount, round(p_amount, 2)),
                           'expensedate', jsonb_build_array(o.expensedate, p_expensedate),
                           'cashaccountid', jsonb_build_array(o.cashaccountid, p_cashaccountid)), p_actor);
END $f$;

CREATE FUNCTION public.sprecurringexpense_skip(p_farmid text, p_occurrenceid integer, p_reason text, p_actor text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql AS $f$
DECLARE o record;
BEGIN
    SELECT x.* INTO o FROM recurringexpenseoccurrences x WHERE x.occurrenceid = p_occurrenceid AND x.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Recurring expense occurrence not found for this company.'; END IF;
    IF o.status <> 'Draft' THEN RAISE EXCEPTION 'Only a draft can be skipped (this one is %).', lower(o.status); END IF;
    IF COALESCE(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'Say why this one is being skipped.'; END IF;
    UPDATE recurringexpenseoccurrences SET status = 'Skipped', skippedby = p_actor, skippedat = (now() at time zone 'utc'),
           skipreason = btrim(p_reason), updatedat = (now() at time zone 'utc') WHERE occurrenceid = p_occurrenceid;
    PERFORM fnrecurringexpense_log(p_farmid, o.templateid, p_occurrenceid, 'Skipped', jsonb_build_object('reason', btrim(p_reason)), p_actor);
END $f$;

-- Skipped -> Draft (a skip made by mistake). Its occurrence number never changes.
CREATE FUNCTION public.sprecurringexpense_restore(p_farmid text, p_occurrenceid integer, p_actor text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql AS $f$
DECLARE o record;
BEGIN
    SELECT x.* INTO o FROM recurringexpenseoccurrences x WHERE x.occurrenceid = p_occurrenceid AND x.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Recurring expense occurrence not found for this company.'; END IF;
    IF o.status <> 'Skipped' THEN RAISE EXCEPTION 'Only a skipped occurrence can be restored.'; END IF;
    UPDATE recurringexpenseoccurrences SET status = 'Draft', skippedby = NULL, skippedat = NULL, skipreason = NULL,
           updatedat = (now() at time zone 'utc') WHERE occurrenceid = p_occurrenceid;
    PERFORM fnrecurringexpense_log(p_farmid, o.templateid, p_occurrenceid, 'Restored', NULL, p_actor);
END $f$;

-- ------------------------------------------------------- 9. posting ----------
-- Step 1: claim. Returns everything the module's expense service needs.
CREATE FUNCTION public.sprecurringexpense_claim(p_farmid text, p_occurrenceid integer, p_actor text DEFAULT NULL)
RETURNS TABLE(claimtoken uuid, occurrenceid integer, templateid integer, module text, amount numeric,
              expensedate date, paymentmethod text, cashaccountid integer, supplierid integer,
              categoryid integer, categoryname text, payeename text, description text, note text)
LANGUAGE plpgsql AS $f$
DECLARE
    o       record;
    v_token uuid := gen_random_uuid();
BEGIN
    SELECT x.* INTO o FROM recurringexpenseoccurrences x WHERE x.occurrenceid = p_occurrenceid AND x.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Recurring expense occurrence not found for this company.'; END IF;
    IF o.status = 'Posted'  THEN RAISE EXCEPTION 'This one is already posted (expense #%).', o.expenseid; END IF;
    IF o.status = 'Skipped' THEN RAISE EXCEPTION 'This one was skipped. Restore it first to post it.'; END IF;
    IF o.status = 'Posting' THEN
        RAISE EXCEPTION 'This one is already being posted%.',
              CASE WHEN o.claimedat < (now() at time zone 'utc') - interval '10 minutes'
                   THEN ' -- the post was interrupted. Check Expenses, then link the expense or release it back to draft'
                   ELSE ' by ' || COALESCE(o.claimedby, 'someone') END;
    END IF;
    IF o.expensedate > fncompany_businessdate(p_farmid) THEN
        RAISE EXCEPTION 'This one is dated % -- it cannot be posted before that date.', o.expensedate;
    END IF;
    UPDATE recurringexpenseoccurrences SET status = 'Posting', claimtoken = v_token, claimedby = p_actor,
           claimedat = (now() at time zone 'utc') WHERE recurringexpenseoccurrences.occurrenceid = p_occurrenceid;
    RETURN QUERY
    SELECT v_token, o.occurrenceid, o.templateid, o.module, o.amount, o.expensedate, o.paymentmethod,
           o.cashaccountid, o.supplierid, t.categoryid, t.categoryname, t.payeename, o.description, o.note
    FROM   recurringexpensetemplates t WHERE t.templateid = o.templateid;
END $f$;

-- Step 3: the module created expense p_expenseid.
CREATE FUNCTION public.sprecurringexpense_completepost(p_farmid text, p_occurrenceid integer, p_claimtoken uuid,
                                                      p_expenseid integer, p_actor text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql AS $f$
DECLARE o record;
BEGIN
    SELECT x.* INTO o FROM recurringexpenseoccurrences x WHERE x.occurrenceid = p_occurrenceid AND x.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Recurring expense occurrence not found for this company.'; END IF;
    IF o.status <> 'Posting' OR o.claimtoken IS DISTINCT FROM p_claimtoken THEN
        RAISE EXCEPTION 'This posting claim is no longer valid.';
    END IF;
    IF p_expenseid IS NULL THEN RAISE EXCEPTION 'The expense id is required.'; END IF;
    UPDATE recurringexpenseoccurrences SET status = 'Posted', expenseid = p_expenseid, postedby = p_actor,
           postedat = (now() at time zone 'utc'), claimtoken = NULL, updatedat = (now() at time zone 'utc')
    WHERE  occurrenceid = p_occurrenceid;
    PERFORM fnrecurringexpense_log(p_farmid, o.templateid, p_occurrenceid, 'Posted',
        jsonb_build_object('expenseid', p_expenseid, 'amount', o.amount, 'expensedate', o.expensedate,
                           'paymentmethod', o.paymentmethod, 'cashaccountid', o.cashaccountid), p_actor);
END $f$;

-- The module refused (step 2 failed), or a person releases an interrupted post.
-- p_claimtoken NULL = a person's manual release, allowed only once the claim is stale.
CREATE FUNCTION public.sprecurringexpense_releaseclaim(p_farmid text, p_occurrenceid integer, p_claimtoken uuid,
                                                      p_reason text DEFAULT NULL, p_actor text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql AS $f$
DECLARE o record;
BEGIN
    SELECT x.* INTO o FROM recurringexpenseoccurrences x WHERE x.occurrenceid = p_occurrenceid AND x.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Recurring expense occurrence not found for this company.'; END IF;
    IF o.status <> 'Posting' THEN RAISE EXCEPTION 'This one is not being posted.'; END IF;
    IF p_claimtoken IS NULL AND o.claimedat >= (now() at time zone 'utc') - interval '10 minutes' THEN
        RAISE EXCEPTION 'This post started less than 10 minutes ago. Wait, then check Expenses before releasing it.';
    END IF;
    IF p_claimtoken IS NOT NULL AND o.claimtoken IS DISTINCT FROM p_claimtoken THEN
        RAISE EXCEPTION 'This posting claim is no longer valid.';
    END IF;
    UPDATE recurringexpenseoccurrences SET status = 'Draft', claimtoken = NULL, claimedby = NULL, claimedat = NULL,
           updatedat = (now() at time zone 'utc') WHERE occurrenceid = p_occurrenceid;
    PERFORM fnrecurringexpense_log(p_farmid, o.templateid, p_occurrenceid, 'Released',
        jsonb_build_object('reason', NULLIF(btrim(p_reason), '')), p_actor);
END $f$;

-- An interrupted post whose expense DID get created: link it instead of posting again.
CREATE FUNCTION public.sprecurringexpense_linkexpense(p_farmid text, p_occurrenceid integer, p_expenseid integer, p_actor text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql AS $f$
DECLARE o record;
BEGIN
    SELECT x.* INTO o FROM recurringexpenseoccurrences x WHERE x.occurrenceid = p_occurrenceid AND x.farmid = p_farmid FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Recurring expense occurrence not found for this company.'; END IF;
    IF o.status <> 'Posting' OR o.claimedat >= (now() at time zone 'utc') - interval '10 minutes' THEN
        RAISE EXCEPTION 'Only an interrupted post (more than 10 minutes old) can be linked to an existing expense.';
    END IF;
    UPDATE recurringexpenseoccurrences SET status = 'Posted', expenseid = p_expenseid, postedby = p_actor,
           postedat = (now() at time zone 'utc'), claimtoken = NULL, updatedat = (now() at time zone 'utc')
    WHERE  occurrenceid = p_occurrenceid;
    PERFORM fnrecurringexpense_log(p_farmid, o.templateid, p_occurrenceid, 'Posted',
        jsonb_build_object('expenseid', p_expenseid, 'linked', true), p_actor);
END $f$;

CREATE FUNCTION public.sprecurringexpense_history(p_farmid text, p_templateid integer)
RETURNS TABLE(eventid bigint, occurrenceid integer, eventtype text, details jsonb, actor text, atutc timestamptz)
LANGUAGE sql STABLE AS $f$
    SELECT e.eventid, e.occurrenceid, e.eventtype, e.details, e.actor, e.atutc
    FROM   recurringexpenseevents e
    WHERE  e.farmid = p_farmid AND e.templateid = p_templateid
    ORDER  BY e.atutc DESC, e.eventid DESC;
$f$;

-- ---------------------------------------------------------- 10. permissions ---
-- Rides each module's EXISTING expenses resource: making a recurring expense
-- is making expenses. The route maps to "*.expenses", so the IAM filter
-- resolves poultry.expenses / water.expenses / ... per company. No new keys.

COMMIT;
