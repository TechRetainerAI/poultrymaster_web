-- =============================================================================
-- 261_PoultryCostRecognitionFoundation.postgres.sql
--
-- Purpose
-- -------
-- Phase 1 of the cost-recognition work: the configuration and classification
-- foundation. It decides, for any item on any day, WHEN an inventory purchase
-- should hit Profit & Loss -- and records that decision on the purchase so it
-- can never be re-interpreted later.
--
-- It changes no behaviour on its own. 262 is the file that makes purchases act
-- on the decision; this one only writes it down.
--
-- WHAT "EXPENSE WHEN PURCHASED" ACTUALLY MEANS TODAY
-- ==================================================
-- Worth stating plainly, because it is not what the phrase suggests and every
-- later phase depends on getting it right.
--
-- sppoultryrawmaterialpurchase_insert writes an expense row for AMOUNTPAID,
-- not for totalcost. A 100,000 purchase entered as unpaid creates NO expense
-- at all. Each later supplier payment writes another expense row, and
-- migration 207's invariant is that "a purchase's linked expense rows sum to
-- its amountpaid".
--
-- So poultry raw-material cost recognition is CASH-BASIS today: the cost lands
-- in the P&L as the supplier is paid. That is the behaviour EXPENSE_WHEN_
-- PURCHASED has to preserve exactly, and it is why 262 has to suppress the
-- expense in TWO places rather than one -- the purchase and the payment.
--
-- THE TWO METHODS
-- ===============
--   EXPENSE_WHEN_PURCHASED   today's behaviour, unchanged. Quantity goes up,
--                            the cost reaches the P&L as it is paid, and later
--                            consumption must never expense it again.
--   EXPENSE_WHEN_CONSUMED    quantity goes up and the cost is held as inventory
--                            value. Cash and supplier balance behave exactly as
--                            before; the P&L waits. Phase 2 recognises it as
--                            the stock is used.
--
-- Physical tracking and financial recognition are separate concepts. An item is
-- counted in inventory either way; the method only decides when its cost is a
-- cost.
--
-- RESOLUTION ORDER
-- ================
--   1. the item's own override, when it has one
--   2. the farm default for the item's category group
--   3. EXPENSE_WHEN_PURCHASED
--
-- Step 3 is not decoration. It is what guarantees a category nobody has
-- configured, an item that has been deleted, or a farm with no settings row
-- keeps behaving exactly as it does today.
--
-- WHICH CATEGORIES FOLLOW WHICH DEFAULT
-- =====================================
-- Only two groups are configurable, matching the two settings:
--
--   Feed        FeedIngredient, FinishedFeed, Grain
--   Medication  Medication
--
-- Everything else -- Supplement, Packaging, Equipment, Other, and any category
-- added later -- is hard-wired to EXPENSE_WHEN_PURCHASED and cannot be deferred
-- by a farm-level setting. An item in one of those categories can still be
-- deferred individually with an override, which is the escape hatch for the
-- exceptions without opening the door for the rest.
--
-- TWO JUDGEMENT CALLS, RECORDED SO THEY CAN BE ARGUED WITH
-- --------------------------------------------------------
-- GRAIN follows the Feed default. The spec's own worked example is maize, and
-- several farms have filed maize and soya under Grain rather than
-- FeedIngredient; leaving Grain out would have meant the headline example did
-- not work on their data. If that is wrong for a farm, the item override fixes
-- it item by item.
--
-- SUPPLEMENT does NOT follow the Medication default. A supplement is closer to
-- a feed additive than to a drug, and guessing either way would move a real
-- category into deferred costing on a farm that never asked for it. Left
-- unconfigured deliberately.
--
-- WHY A SNAPSHOT ON THE PURCHASE
-- ==============================
-- A farm that switches to EXPENSE_WHEN_CONSUMED in October must not have its
-- September purchases re-read as deferred -- that would silently rewrite a
-- closed month's P&L. So the effective method is stamped onto each purchase
-- when it is created and never consulted from the settings again.
--
-- The column is NOT NULL with a default of EXPENSE_WHEN_PURCHASED, so a code
-- path that forgets to set it produces today's behaviour rather than a NULL
-- nobody notices. All 77 existing purchases are backfilled explicitly, because
-- that is what the system did to them.
--
-- EFFECTIVE-FROM DATE
-- ===================
-- effectivefromdate is a FORWARD-DATED activation and nothing else. NULL means
-- in force now. A date means the setting applies from that day; before it, the
-- baseline EXPENSE_WHEN_PURCHASED applies. The upsert refuses a past date,
-- because backdating would claim to change how transactions were treated when
-- their snapshots say otherwise.
--
-- EFFECT ON TODAY'S NUMBERS: none. One new table seeded to today's behaviour,
-- two nullable columns, one backfill of a label, and functions that nothing
-- calls yet.
--
-- Order: after 260.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Drop by NAME, not by signature.
--
-- The item functions gain arguments and return columns, and CREATE OR REPLACE
-- can change neither. Leaving an old overload in place would let Npgsql bind
-- either one by named argument and silently drop the override.
-- -----------------------------------------------------------------------------
DO $drop$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM   pg_proc p
        JOIN   pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'public'
          AND  p.proname IN ('sppoultryrawmaterialitem_insert',
                             'sppoultryrawmaterialitem_update',
                             'sppoultryrawmaterialitem_getall',
                             'sppoultryfinancialsettings_get',
                             'sppoultryfinancialsettings_upsert',
                             'fnpoultrycostrecognition_categorygroup',
                             'fnpoultrycostrecognition_farmdefault',
                             'fnpoultrycostrecognition_effective',
                             'fnpoultrycostrecognition_expenseatpurchase',
                             'fnpoultrycostrecognition_expenseatconsumption')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- -----------------------------------------------------------------------------
-- 1. The farm-level settings.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS poultryfinancialsettings (
    poultryfinancialsettingsid serial PRIMARY KEY,
    farmid                     varchar(450) NOT NULL,

    -- The two methods are independent on purpose: a farm may defer feed and
    -- expense medication on purchase, or the other way round.
    feedcostrecognitionmethod       text NOT NULL DEFAULT 'EXPENSE_WHEN_PURCHASED'
        CHECK (feedcostrecognitionmethod IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED')),
    medicationcostrecognitionmethod text NOT NULL DEFAULT 'EXPENSE_WHEN_PURCHASED'
        CHECK (medicationcostrecognitionmethod IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED')),

    -- Forward-dated activation only. See the header.
    effectivefromdate date NULL,

    createdby text NULL,
    createdat timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby text NULL,
    updatedat timestamp NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryfinancialsettings_farm
    ON poultryfinancialsettings (farmid);

COMMENT ON TABLE poultryfinancialsettings IS
    'When inventory costs reach Profit & Loss, per poultry company. Absent row '
    'means today''s behaviour: expense when purchased, both groups.';
COMMENT ON COLUMN poultryfinancialsettings.effectivefromdate IS
    'Forward-dated activation. NULL = in force now. Before the date the '
    'baseline EXPENSE_WHEN_PURCHASED applies; the upsert refuses a past date.';

-- -----------------------------------------------------------------------------
-- 2. The item-level override.
--
-- NULL means "use the farm default". A nullable column rather than a third
-- enum value, so the resolver is COALESCE and not a CASE nobody can read.
-- -----------------------------------------------------------------------------
ALTER TABLE poultryrawmaterialitems
    ADD COLUMN IF NOT EXISTS costrecognitionoverride text NULL;

DO $ck$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'ck_poultryrawmaterialitems_costrecognition') THEN
        ALTER TABLE poultryrawmaterialitems
            ADD CONSTRAINT ck_poultryrawmaterialitems_costrecognition
            CHECK (costrecognitionoverride IS NULL
                   OR costrecognitionoverride IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED'));
    END IF;
END
$ck$;

COMMENT ON COLUMN poultryrawmaterialitems.costrecognitionoverride IS
    'NULL = follow the farm default for this item''s category group. A value '
    'here wins over the farm setting, and survives a category change.';

-- -----------------------------------------------------------------------------
-- 3. The snapshot on the purchase.
--
-- Backfilled to EXPENSE_WHEN_PURCHASED, then made NOT NULL with that default.
-- Every existing purchase WAS treated that way, so the backfill records history
-- rather than inventing it, and the default means a forgotten code path fails
-- into today's behaviour instead of into a NULL.
-- -----------------------------------------------------------------------------
ALTER TABLE poultryrawmaterialpurchases
    ADD COLUMN IF NOT EXISTS costrecognitionmethod text NULL;

UPDATE poultryrawmaterialpurchases
SET    costrecognitionmethod = 'EXPENSE_WHEN_PURCHASED'
WHERE  costrecognitionmethod IS NULL;

ALTER TABLE poultryrawmaterialpurchases
    ALTER COLUMN costrecognitionmethod SET DEFAULT 'EXPENSE_WHEN_PURCHASED';
ALTER TABLE poultryrawmaterialpurchases
    ALTER COLUMN costrecognitionmethod SET NOT NULL;

DO $ck2$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'ck_poultryrawmaterialpurchases_costrecognition') THEN
        ALTER TABLE poultryrawmaterialpurchases
            ADD CONSTRAINT ck_poultryrawmaterialpurchases_costrecognition
            CHECK (costrecognitionmethod IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED'));
    END IF;
END
$ck2$;

COMMENT ON COLUMN poultryrawmaterialpurchases.costrecognitionmethod IS
    'The method in force when this purchase was created. Never recomputed: a '
    'later settings change must not rewrite a closed month''s P&L.';

-- Phase 2 will sweep deferred purchases with stock left; this is the index it
-- will want, and it costs nothing now.
CREATE INDEX IF NOT EXISTS ix_poultryrawmaterialpurchases_deferred
    ON poultryrawmaterialpurchases (farmid, poultryrawmaterialitemid)
    WHERE costrecognitionmethod = 'EXPENSE_WHEN_CONSUMED';

-- -----------------------------------------------------------------------------
-- 4. Which global default a category follows.
--
-- One place, so the settings page, the item form, the resolver and Phase 2
-- cannot drift into three different opinions about what "feed" means.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrycostrecognition_categorygroup(p_category text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE upper(btrim(COALESCE(p_category, '')))
             -- See the header for why Grain is here and Supplement is not.
             WHEN 'FEEDINGREDIENT' THEN 'Feed'
             WHEN 'FINISHEDFEED'   THEN 'Feed'
             WHEN 'GRAIN'          THEN 'Feed'
             WHEN 'MEDICATION'     THEN 'Medication'
             ELSE 'Unconfigured'
           END;
$function$;

COMMENT ON FUNCTION public.fnpoultrycostrecognition_categorygroup(text) IS
    'Feed | Medication | Unconfigured. Unconfigured categories always expense '
    'on purchase and cannot be deferred by a farm setting -- only by an item '
    'override.';

-- -----------------------------------------------------------------------------
-- 5. The farm default for a category, honouring the activation date.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrycostrecognition_farmdefault(
    p_farmid   text,
    p_category text,
    p_asof     date DEFAULT NULL
) RETURNS text
LANGUAGE sql STABLE
AS $function$
    SELECT COALESCE(
        (SELECT CASE
                  -- Not yet in force: the baseline still applies.
                  WHEN s.effectivefromdate IS NOT NULL
                       AND s.effectivefromdate > COALESCE(p_asof, CURRENT_DATE)
                       THEN 'EXPENSE_WHEN_PURCHASED'
                  WHEN public.fnpoultrycostrecognition_categorygroup(p_category) = 'Feed'
                       THEN s.feedcostrecognitionmethod
                  WHEN public.fnpoultrycostrecognition_categorygroup(p_category) = 'Medication'
                       THEN s.medicationcostrecognitionmethod
                  -- Unconfigured category: no farm setting reaches it.
                  ELSE 'EXPENSE_WHEN_PURCHASED'
                END
         FROM   poultryfinancialsettings s
         WHERE  s.farmid = p_farmid),
        -- No settings row at all: every farm behaved this way before 261.
        'EXPENSE_WHEN_PURCHASED');
$function$;

-- -----------------------------------------------------------------------------
-- 6. THE resolver.
--
-- Item override, else farm default, else the baseline. Every caller -- the item
-- form, the purchase, the API, Phase 2's consumption engine -- goes through
-- this one function, so there is exactly one answer to "how is this treated".
--
-- p_category is optional: passing it saves a lookup on paths that already have
-- it, and omitting it reads the item's own category. Passing a category for an
-- item that does not exist is how the settings page previews a default.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrycostrecognition_effective(
    p_farmid   text,
    p_itemid   integer DEFAULT NULL,
    p_category text    DEFAULT NULL,
    p_asof     date    DEFAULT NULL
) RETURNS TABLE(
    method      text,   -- EXPENSE_WHEN_PURCHASED | EXPENSE_WHEN_CONSUMED
    source      text,   -- ItemOverride | FarmDefault
    farmdefault text,   -- what the farm would have said, for "you are overriding X"
    categorygroup text  -- Feed | Medication | Unconfigured
)
LANGUAGE plpgsql STABLE
AS $function$
DECLARE
    v_override text;
    v_category text := p_category;
    v_default  text;
    v_group    text;
BEGIN
    IF p_itemid IS NOT NULL THEN
        SELECT i.costrecognitionoverride, COALESCE(p_category, i.category)
        INTO   v_override, v_category
        FROM   poultryrawmaterialitems i
        WHERE  i.poultryrawmaterialitemid = p_itemid AND i.farmid = p_farmid;
    END IF;

    v_group   := public.fnpoultrycostrecognition_categorygroup(v_category);
    v_default := public.fnpoultrycostrecognition_farmdefault(p_farmid, v_category, p_asof);

    RETURN QUERY SELECT
        COALESCE(v_override, v_default),
        CASE WHEN v_override IS NOT NULL THEN 'ItemOverride' ELSE 'FarmDefault' END,
        v_default,
        v_group;
END;
$function$;

COMMENT ON FUNCTION public.fnpoultrycostrecognition_effective(text, integer, text, date) IS
    'The one resolver. Item override, else farm default for the category group, '
    'else EXPENSE_WHEN_PURCHASED. Do not re-implement this anywhere.';

-- -----------------------------------------------------------------------------
-- 7. The two predicates every writer should ask, rather than comparing strings.
--
-- They take the SNAPSHOT off the transaction, not a farm id, precisely so a
-- caller cannot accidentally ask today's settings about last month's purchase.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrycostrecognition_expenseatpurchase(p_method text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $function$
    -- Unknown or missing reads as today's behaviour. A method nobody recognises
    -- must not silently defer a cost out of the P&L.
    SELECT COALESCE(p_method, '') <> 'EXPENSE_WHEN_CONSUMED';
$function$;

CREATE OR REPLACE FUNCTION public.fnpoultrycostrecognition_expenseatconsumption(p_method text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT COALESCE(p_method, '') = 'EXPENSE_WHEN_CONSUMED';
$function$;

COMMENT ON FUNCTION public.fnpoultrycostrecognition_expenseatpurchase(text) IS
    'Exactly one of this and _expenseatconsumption is true for any input, which '
    'is what stops a cost being expensed twice or not at all.';

-- -----------------------------------------------------------------------------
-- 8. Settings reads and writes.
--
-- _get never writes. A farm with no row reads as the defaults, so opening the
-- settings page does not create rows for 35 farms that never touched it.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryfinancialsettings_get(p_farmid text)
RETURNS TABLE(
    farmid                          text,
    feedcostrecognitionmethod       text,
    medicationcostrecognitionmethod text,
    effectivefromdate               date,
    isconfigured                    boolean,
    createdby                       text,
    createdat                       timestamp,
    updatedby                       text,
    updatedat                       timestamp
)
LANGUAGE sql STABLE
AS $function$
    SELECT p_farmid,
           COALESCE(s.feedcostrecognitionmethod, 'EXPENSE_WHEN_PURCHASED'),
           COALESCE(s.medicationcostrecognitionmethod, 'EXPENSE_WHEN_PURCHASED'),
           s.effectivefromdate,
           -- False means "nobody has chosen yet", which the page says out loud
           -- rather than showing a default as though it were a decision.
           (s.farmid IS NOT NULL),
           s.createdby::text, s.createdat, s.updatedby::text, s.updatedat
    FROM   (SELECT p_farmid AS f) anchor
    LEFT   JOIN poultryfinancialsettings s ON s.farmid = anchor.f;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryfinancialsettings_upsert(
    p_farmid            text,
    p_feedmethod        text,
    p_medicationmethod  text,
    p_effectivefromdate date DEFAULT NULL,
    p_updatedby         text DEFAULT NULL
) RETURNS TABLE(
    farmid                          text,
    feedcostrecognitionmethod       text,
    medicationcostrecognitionmethod text,
    effectivefromdate               date,
    isconfigured                    boolean,
    createdby                       text,
    createdat                       timestamp,
    updatedby                       text,
    updatedat                       timestamp,
    -- Returned so the caller can audit the change without reading twice and
    -- racing itself.
    previousfeedmethod              text,
    previousmedicationmethod        text
)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_prevfeed text;
    v_prevmed  text;
BEGIN
    IF COALESCE(p_feedmethod, '') NOT IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED') THEN
        RAISE EXCEPTION 'Unknown feed cost recognition method: "%".', p_feedmethod;
    END IF;
    IF COALESCE(p_medicationmethod, '') NOT IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED') THEN
        RAISE EXCEPTION 'Unknown medication cost recognition method: "%".', p_medicationmethod;
    END IF;
    -- Backdating would claim to change how past transactions were treated,
    -- while their snapshots say otherwise. Refuse rather than lie.
    IF p_effectivefromdate IS NOT NULL AND p_effectivefromdate < CURRENT_DATE THEN
        RAISE EXCEPTION 'An effective date cannot be in the past (got %). Existing purchases keep the method they were created with.',
            p_effectivefromdate;
    END IF;

    SELECT s.feedcostrecognitionmethod, s.medicationcostrecognitionmethod
    INTO   v_prevfeed, v_prevmed
    FROM   poultryfinancialsettings s WHERE s.farmid = p_farmid;

    v_prevfeed := COALESCE(v_prevfeed, 'EXPENSE_WHEN_PURCHASED');
    v_prevmed  := COALESCE(v_prevmed,  'EXPENSE_WHEN_PURCHASED');

    -- Explicit UPDATE-else-INSERT rather than ON CONFLICT, and not by choice:
    -- this function RETURNS TABLE(farmid ...), so `ON CONFLICT (farmid)` cannot
    -- tell the output column from the table column and Postgres refuses it as
    -- ambiguous. Same shape spfarmproductionsettings_upsert already uses.
    IF EXISTS (SELECT 1 FROM poultryfinancialsettings s WHERE s.farmid = p_farmid) THEN
        UPDATE poultryfinancialsettings s
        SET    feedcostrecognitionmethod       = p_feedmethod,
               medicationcostrecognitionmethod = p_medicationmethod,
               effectivefromdate               = p_effectivefromdate,
               updatedby                       = p_updatedby,
               updatedat                       = (now() at time zone 'utc')
        WHERE  s.farmid = p_farmid;
    ELSE
        INSERT INTO poultryfinancialsettings (
            farmid, feedcostrecognitionmethod, medicationcostrecognitionmethod,
            effectivefromdate, createdby, updatedby, updatedat)
        VALUES (
            p_farmid, p_feedmethod, p_medicationmethod,
            p_effectivefromdate, p_updatedby, p_updatedby, (now() at time zone 'utc'));
    END IF;

    RETURN QUERY
    SELECT g.*, v_prevfeed, v_prevmed
    FROM   sppoultryfinancialsettings_get(p_farmid) g;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 9. The item functions, carrying the override.
--
-- Reproduced from the LIVE definitions. The FIFO/LIFO/HIFO handling, the
-- purchase-unit fallback and the ordering are untouched; the override argument
-- is appended and defaulted, and the read gains four resolved columns so the
-- list and the form never have to work the rule out for themselves.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialitem_insert(
    p_farmid                text,
    p_itemname              text,
    p_category              text,
    p_unitofmeasure         text DEFAULT NULL,
    p_minimumstockalert     numeric DEFAULT 0,
    p_notes                 text DEFAULT NULL,
    p_usagemethod           text DEFAULT 'FIFO',
    p_purchaseunitofmeasure text DEFAULT NULL,
    -- Appended and defaulted, so a caller that predates 261 still binds and
    -- still means "follow the farm default".
    p_costrecognitionoverride text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_usagemethod text := p_usagemethod;
    v_override    text := NULLIF(btrim(COALESCE(p_costrecognitionoverride, '')), '');
    v_newid       integer;
BEGIN
    IF (v_usagemethod IS NULL OR v_usagemethod NOT IN ('FIFO', 'LIFO', 'HIFO')) THEN
        v_usagemethod := 'FIFO';
    END IF;
    -- 'USE_DEFAULT' is accepted as a spelling of "no override" so a frontend
    -- that sends the radio value verbatim cannot write a bogus method.
    IF v_override = 'USE_DEFAULT' THEN v_override := NULL; END IF;
    IF v_override IS NOT NULL
       AND v_override NOT IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED') THEN
        RAISE EXCEPTION 'Unknown cost recognition override: "%".', v_override;
    END IF;

    INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, minimumstockalert, notes, usagemethod, purchaseunitofmeasure, costrecognitionoverride)
    VALUES (p_farmid, p_itemname, p_category, p_unitofmeasure, COALESCE(p_minimumstockalert, 0), p_notes, v_usagemethod, COALESCE(p_purchaseunitofmeasure, p_unitofmeasure), v_override)
    RETURNING poultryrawmaterialitemid INTO v_newid;

    RETURN v_newid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialitem_update(
    p_poultryrawmaterialitemid integer,
    p_farmid                   text,
    p_itemname                 text,
    p_category                 text,
    p_unitofmeasure            text DEFAULT NULL,
    p_minimumstockalert        numeric DEFAULT 0,
    p_isactive                 boolean DEFAULT true,
    p_notes                    text DEFAULT NULL,
    p_usagemethod              text DEFAULT 'FIFO',
    p_purchaseunitofmeasure    text DEFAULT NULL,
    p_costrecognitionoverride  text DEFAULT NULL,
    -- The override is nullable and NULL means something ("follow the farm"), so
    -- an update cannot tell "clear it" from "leave it alone" by value. This
    -- flag says which was meant. Defaulting to FALSE keeps every pre-261 caller
    -- working: they neither set nor clear it.
    p_setcostrecognitionoverride boolean DEFAULT FALSE
) RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_usagemethod text := p_usagemethod;
    v_override    text := NULLIF(btrim(COALESCE(p_costrecognitionoverride, '')), '');
BEGIN
    IF (v_usagemethod IS NULL OR v_usagemethod NOT IN ('FIFO','LIFO','HIFO')) THEN
        v_usagemethod := 'FIFO';
    END IF;
    IF v_override = 'USE_DEFAULT' THEN v_override := NULL; END IF;
    IF v_override IS NOT NULL
       AND v_override NOT IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED') THEN
        RAISE EXCEPTION 'Unknown cost recognition override: "%".', v_override;
    END IF;

    UPDATE poultryrawmaterialitems i
    SET    itemname = p_itemname, category = p_category, unitofmeasure = p_unitofmeasure,
           minimumstockalert = COALESCE(p_minimumstockalert, 0), isactive = COALESCE(p_isactive, TRUE),
           notes = p_notes, usagemethod = v_usagemethod,
           purchaseunitofmeasure = COALESCE(p_purchaseunitofmeasure, p_unitofmeasure),
           -- A category change on its own never disturbs an explicit override:
           -- the user chose a method, not a category's method.
           costrecognitionoverride = CASE WHEN p_setcostrecognitionoverride
                                          THEN v_override
                                          ELSE i.costrecognitionoverride END,
           updatedat = (now() at time zone 'utc')
    WHERE  i.poultryrawmaterialitemid = p_poultryrawmaterialitemid AND i.farmid = p_farmid;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryrawmaterialitem_getall(p_farmid text)
RETURNS TABLE(
    poultryrawmaterialitemid integer,
    farmid                   text,
    itemname                 text,
    category                 text,
    unitofmeasure            text,
    minimumstockalert        numeric,
    currentquantity          numeric,
    isactive                 boolean,
    notes                    text,
    createdat                timestamp without time zone,
    updatedat                timestamp without time zone,
    usagemethod              text,
    purchaseunitofmeasure    text,
    islowstock               boolean,
    -- 261. Resolved here so the list, the form and the API cannot disagree
    -- about what an item's treatment actually is.
    costrecognitionoverride  text,
    effectivecostrecognitionmethod text,
    costrecognitionsource    text,
    costrecognitioncategorygroup   text
)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT i.poultryrawmaterialitemid, i.farmid::text, i.itemname::text, i.category::text,
           i.unitofmeasure::text, i.minimumstockalert, i.currentquantity, i.isactive,
           i.notes::text, i.createdat, i.updatedat, i.usagemethod::text, i.purchaseunitofmeasure::text,
           COALESCE(i.currentquantity <= i.minimumstockalert, FALSE) AS islowstock,
           i.costrecognitionoverride::text,
           r.method, r.source, r.categorygroup
    FROM   poultryrawmaterialitems i
    CROSS  JOIN LATERAL public.fnpoultrycostrecognition_effective(
                            p_farmid, i.poultryrawmaterialitemid, i.category, NULL) r
    WHERE  i.farmid = p_farmid
    ORDER  BY i.isactive DESC NULLS LAST, i.itemname;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'every purchase is snapshotted' AS check,
       CASE WHEN COUNT(*) FILTER (WHERE costrecognitionmethod IS NULL) = 0
            THEN 'OK' ELSE 'NULL on ' || COUNT(*) FILTER (WHERE costrecognitionmethod IS NULL) END AS result
FROM   poultryrawmaterialpurchases

UNION ALL
-- Nothing may have been backfilled as deferred: no farm asked for that.
SELECT 'no purchase backfilled as deferred',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   poultryrawmaterialpurchases
WHERE  costrecognitionmethod = 'EXPENSE_WHEN_CONSUMED'

UNION ALL
SELECT 'no item starts with an override',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   poultryrawmaterialitems
WHERE  costrecognitionoverride IS NOT NULL

UNION ALL
-- The point of the whole file: every existing item still resolves to today's
-- behaviour, because no settings row exists and no override was written.
SELECT 'every item still resolves to purchased',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'CHANGED ' || COUNT(*) END
FROM   poultryrawmaterialitems i
CROSS  JOIN LATERAL public.fnpoultrycostrecognition_effective(i.farmid, i.poultryrawmaterialitemid, i.category, NULL) r
WHERE  r.method <> 'EXPENSE_WHEN_PURCHASED';
