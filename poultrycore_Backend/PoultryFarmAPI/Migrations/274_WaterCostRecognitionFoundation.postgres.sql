-- =============================================================================
-- 274_WaterCostRecognitionFoundation.postgres.sql
--
-- Purpose
-- -------
-- The water mirror of 261. Phase 1 of the cost-recognition work: the
-- configuration and classification foundation. It decides, for any item on any
-- day, WHEN an inventory purchase should hit Profit & Loss -- and records that
-- decision on the purchase so it can never be re-interpreted later.
--
-- It changes no behaviour on its own. 275 is the file that makes purchases act
-- on the decision; this one only writes it down.
--
-- WHAT "EXPENSE WHEN PURCHASED" ACTUALLY MEANS TODAY
-- ==================================================
-- Same as poultry, and worth restating because every later phase depends on it.
--
-- Migration 090 made spWaterRawMaterialPurchase_Insert write its expense row
-- for AMOUNTPAID, not for totalcost. A 100,000 purchase entered as unpaid
-- creates NO expense at all. Each later supplier payment (091's _PayBalance)
-- writes another expense row.
--
-- So water raw-material cost recognition is CASH-BASIS today: the cost lands in
-- the P&L as the supplier is paid. That is the behaviour EXPENSE_WHEN_PURCHASED
-- has to preserve exactly, and it is why 275 has to suppress the expense in TWO
-- places rather than one -- the purchase and the payment.
--
-- WATER RECORDS EXPENSES IN ITS OWN TABLE
-- =======================================
-- Poultry writes to the shared `expense` table via spexpense_insert. Water does
-- not: it has `waterexpenses`, `waterexpensecategories` and the spwaterexpense_*
-- family, with spwaterexpensecategory_ensurerawmaterialpurchase minting the
-- category a purchase's expense is filed under. Nothing in this chain touches
-- the poultry side, and 282 adds financialcosttype to waterexpenses rather than
-- reusing 269's column on `expense`.
--
-- THE TWO METHODS
-- ===============
--   EXPENSE_WHEN_PURCHASED   today's behaviour, unchanged. Quantity goes up,
--                            the cost reaches the P&L as it is paid, and later
--                            consumption must never expense it again.
--   EXPENSE_WHEN_CONSUMED    quantity goes up and the cost is held as inventory
--                            value. Cash and supplier balance behave exactly as
--                            before; the P&L waits. Phase 2 recognises it as
--                            the stock is drawn by a production batch.
--
-- Physical tracking and financial recognition are separate concepts. An item is
-- counted in inventory either way; the method only decides when its cost is a
-- cost.
--
-- RESOLUTION ORDER
-- ================
--   1. the item's own override, when it has one
--   2. the company default for the item's category group
--   3. EXPENSE_WHEN_PURCHASED
--
-- Step 3 is not decoration. It is what guarantees a category nobody has
-- configured, an item that has been deleted, or a company with no settings row
-- keeps behaving exactly as it does today.
--
-- WHICH CATEGORIES FOLLOW WHICH DEFAULT
-- =====================================
-- Water's category list is PackagingRoll, SachetFilm, OuterBag, Chemical,
-- Filter, UVLamp, SparePart, Fuel, CleaningSupply, Other. Two groups are
-- configurable, matching the two settings:
--
--   Packaging   PackagingRoll, SachetFilm, OuterBag
--   Treatment   Chemical
--
-- Everything else -- Filter, UVLamp, SparePart, Fuel, CleaningSupply, Other,
-- and any category added later -- is hard-wired to EXPENSE_WHEN_PURCHASED and
-- cannot be deferred by a company-level setting. An item in one of those
-- categories can still be deferred individually with an override, which is the
-- escape hatch for the exceptions without opening the door for the rest.
--
-- TWO JUDGEMENT CALLS, RECORDED SO THEY CAN BE ARGUED WITH
-- --------------------------------------------------------
-- PACKAGING IS THE HEADLINE GROUP, not "raw material" in general. Film, rolls
-- and outer bags are the per-unit inputs that a sachet or bottle physically
-- consumes, and they are the costs a water company actually wants held back
-- until production. This is the direct analogue of Feed on the poultry side.
--
-- FILTER AND UVLAMP DO NOT FOLLOW THE TREATMENT DEFAULT. They are periodic
-- replacements rather than per-unit inputs, and with 283's asset register in
-- the same workstream several companies will reasonably file a UV lamp as a
-- capital asset or as maintenance. Sweeping them into deferred costing because
-- they sit near Chemical in a dropdown would move real money out of a company's
-- P&L that nobody asked to move. Left unconfigured deliberately; the item
-- override handles the company that disagrees. This mirrors 261's reasoning for
-- leaving Supplement out of the poultry Medication group.
--
-- WHY A SNAPSHOT ON THE PURCHASE
-- ==============================
-- A company that switches to EXPENSE_WHEN_CONSUMED in October must not have its
-- September purchases re-read as deferred -- that would silently rewrite a
-- closed month's P&L. So the effective method is stamped onto each purchase
-- when it is created and never consulted from the settings again.
--
-- The column is NOT NULL with a default of EXPENSE_WHEN_PURCHASED, so a code
-- path that forgets to set it produces today's behaviour rather than a NULL
-- nobody notices. Existing purchases are backfilled explicitly, because that is
-- what the system did to them.
--
-- EFFECTIVE-FROM DATE
-- ===================
-- effectivefromdate is a FORWARD-DATED activation and nothing else. NULL means
-- in force now. A date means the setting applies from that day; before it, the
-- baseline EXPENSE_WHEN_PURCHASED applies. The upsert refuses a past date,
-- because backdating would claim to change how transactions were treated when
-- their snapshots say otherwise.
--
-- WHAT THIS FILE DOES NOT DO, AND WHY
-- ===================================
-- 261 also reproduced sppoultryrawmaterialitem_insert / _update / _getall from
-- their LIVE definitions so the item form could carry the override and the list
-- could show the resolved method.
--
-- The equivalent water bodies are NOT reproduced here. The repo holds only the
-- pre-Postgres T-SQL for spWaterRawMaterialItem_* (044/146/147/190); the live
-- Postgres bodies were ported outside version control and are not available to
-- copy from. Rewriting them from the T-SQL would silently drop whatever the
-- live port actually does -- the FIFO/LIFO/HIFO ordering and the purchase-unit
-- fallback are exactly the kind of thing that fails quietly.
--
-- So the override is instead reached through two small, purely additive
-- functions at the end of this file:
--
--   spwaterrawmaterialitem_setcostrecognition   write one item's override
--   spwatercostrecognition_items                read every item's resolution
--
-- They leave the existing item SPs untouched, which means this migration cannot
-- regress the item list or the item form. When the live bodies are available
-- the two can be folded into _insert / _update / _getall exactly as 261 did,
-- and these wrappers retired.
--
-- EFFECT ON TODAY'S NUMBERS: none. One new table seeded to today's behaviour,
-- two nullable columns, one backfill of a label, and functions that nothing
-- calls yet.
--
-- Order: after 273.
--
-- Idempotent throughout.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 0. Drop by NAME, not by signature.
--
-- Only the functions this file OWNS are dropped. The existing item SPs are
-- deliberately absent from this list -- see the header.
--
-- Dropping by name matters because these functions gain arguments and return
-- columns later, and CREATE OR REPLACE can change neither. Leaving an old
-- overload in place would let Npgsql bind either one by named argument and
-- silently pick the wrong answer.
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
          AND  p.proname IN ('spwaterfinancialsettings_get',
                             'spwaterfinancialsettings_upsert',
                             'spwaterrawmaterialitem_setcostrecognition',
                             'spwatercostrecognition_items',
                             'fnwatercostrecognition_categorygroup',
                             'fnwatercostrecognition_farmdefault',
                             'fnwatercostrecognition_effective',
                             'fnwatercostrecognition_expenseatpurchase',
                             'fnwatercostrecognition_expenseatconsumption')
    LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig;
    END LOOP;
END
$drop$;

-- -----------------------------------------------------------------------------
-- 1. The company-level settings.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS waterfinancialsettings (
    waterfinancialsettingsid serial PRIMARY KEY,
    farmid                   varchar(450) NOT NULL,

    -- The two methods are independent on purpose: a company may defer packaging
    -- and expense treatment chemicals on purchase, or the other way round.
    packagingcostrecognitionmethod text NOT NULL DEFAULT 'EXPENSE_WHEN_PURCHASED'
        CHECK (packagingcostrecognitionmethod IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED')),
    treatmentcostrecognitionmethod text NOT NULL DEFAULT 'EXPENSE_WHEN_PURCHASED'
        CHECK (treatmentcostrecognitionmethod IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED')),

    -- Forward-dated activation only. See the header.
    effectivefromdate date NULL,

    createdby text NULL,
    createdat timestamp NOT NULL DEFAULT (now() at time zone 'utc'),
    updatedby text NULL,
    updatedat timestamp NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_waterfinancialsettings_farm
    ON waterfinancialsettings (farmid);

COMMENT ON TABLE waterfinancialsettings IS
    'When inventory costs reach Profit & Loss, per water company. Absent row '
    'means today''s behaviour: expense when purchased, both groups.';
COMMENT ON COLUMN waterfinancialsettings.effectivefromdate IS
    'Forward-dated activation. NULL = in force now. Before the date the '
    'baseline EXPENSE_WHEN_PURCHASED applies; the upsert refuses a past date.';

-- -----------------------------------------------------------------------------
-- 2. The item-level override.
--
-- NULL means "use the company default". A nullable column rather than a third
-- enum value, so the resolver is COALESCE and not a CASE nobody can read.
-- -----------------------------------------------------------------------------
ALTER TABLE waterrawmaterialitems
    ADD COLUMN IF NOT EXISTS costrecognitionoverride text NULL;

DO $ck$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'ck_waterrawmaterialitems_costrecognition') THEN
        ALTER TABLE waterrawmaterialitems
            ADD CONSTRAINT ck_waterrawmaterialitems_costrecognition
            CHECK (costrecognitionoverride IS NULL
                   OR costrecognitionoverride IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED'));
    END IF;
END
$ck$;

COMMENT ON COLUMN waterrawmaterialitems.costrecognitionoverride IS
    'NULL = follow the company default for this item''s category group. A value '
    'here wins over the company setting, and survives a category change.';

-- -----------------------------------------------------------------------------
-- 3. The snapshot on the purchase.
--
-- Backfilled to EXPENSE_WHEN_PURCHASED, then made NOT NULL with that default.
-- Every existing purchase WAS treated that way, so the backfill records history
-- rather than inventing it, and the default means a forgotten code path fails
-- into today's behaviour instead of into a NULL.
-- -----------------------------------------------------------------------------
ALTER TABLE waterrawmaterialpurchases
    ADD COLUMN IF NOT EXISTS costrecognitionmethod text NULL;

UPDATE waterrawmaterialpurchases
SET    costrecognitionmethod = 'EXPENSE_WHEN_PURCHASED'
WHERE  costrecognitionmethod IS NULL;

ALTER TABLE waterrawmaterialpurchases
    ALTER COLUMN costrecognitionmethod SET DEFAULT 'EXPENSE_WHEN_PURCHASED';
ALTER TABLE waterrawmaterialpurchases
    ALTER COLUMN costrecognitionmethod SET NOT NULL;

DO $ck2$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'ck_waterrawmaterialpurchases_costrecognition') THEN
        ALTER TABLE waterrawmaterialpurchases
            ADD CONSTRAINT ck_waterrawmaterialpurchases_costrecognition
            CHECK (costrecognitionmethod IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED'));
    END IF;
END
$ck2$;

COMMENT ON COLUMN waterrawmaterialpurchases.costrecognitionmethod IS
    'The method in force when this purchase was created. Never recomputed: a '
    'later settings change must not rewrite a closed month''s P&L.';

-- Phase 2 sweeps deferred purchases with stock left; this is the index it will
-- want, and it costs nothing now.
CREATE INDEX IF NOT EXISTS ix_waterrawmaterialpurchases_deferred
    ON waterrawmaterialpurchases (farmid, waterrawmaterialitemid)
    WHERE costrecognitionmethod = 'EXPENSE_WHEN_CONSUMED';

-- -----------------------------------------------------------------------------
-- 4. Which global default a category follows.
--
-- One place, so the settings page, the item form, the resolver and Phase 2
-- cannot drift into three different opinions about what "packaging" means.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwatercostrecognition_categorygroup(p_category text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT CASE upper(btrim(COALESCE(p_category, '')))
             -- See the header for why Filter and UVLamp are not in Treatment.
             WHEN 'PACKAGINGROLL' THEN 'Packaging'
             WHEN 'SACHETFILM'    THEN 'Packaging'
             WHEN 'OUTERBAG'      THEN 'Packaging'
             WHEN 'CHEMICAL'      THEN 'Treatment'
             ELSE 'Unconfigured'
           END;
$function$;

COMMENT ON FUNCTION public.fnwatercostrecognition_categorygroup(text) IS
    'Packaging | Treatment | Unconfigured. Unconfigured categories always '
    'expense on purchase and cannot be deferred by a company setting -- only by '
    'an item override.';

-- -----------------------------------------------------------------------------
-- 5. The company default for a category, honouring the activation date.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwatercostrecognition_farmdefault(
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
                  WHEN public.fnwatercostrecognition_categorygroup(p_category) = 'Packaging'
                       THEN s.packagingcostrecognitionmethod
                  WHEN public.fnwatercostrecognition_categorygroup(p_category) = 'Treatment'
                       THEN s.treatmentcostrecognitionmethod
                  -- Unconfigured category: no company setting reaches it.
                  ELSE 'EXPENSE_WHEN_PURCHASED'
                END
         FROM   waterfinancialsettings s
         WHERE  s.farmid = p_farmid),
        -- No settings row at all: every company behaved this way before 274.
        'EXPENSE_WHEN_PURCHASED');
$function$;

-- -----------------------------------------------------------------------------
-- 6. THE resolver.
--
-- Item override, else company default, else the baseline. Every caller -- the
-- item form, the purchase, the API, Phase 2's consumption engine -- goes through
-- this one function, so there is exactly one answer to "how is this treated".
--
-- p_category is optional: passing it saves a lookup on paths that already have
-- it, and omitting it reads the item's own category. Passing a category for an
-- item that does not exist is how the settings page previews a default.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwatercostrecognition_effective(
    p_farmid   text,
    p_itemid   integer DEFAULT NULL,
    p_category text    DEFAULT NULL,
    p_asof     date    DEFAULT NULL
) RETURNS TABLE(
    method        text,   -- EXPENSE_WHEN_PURCHASED | EXPENSE_WHEN_CONSUMED
    source        text,   -- ItemOverride | FarmDefault
    farmdefault   text,   -- what the company would have said, for "you are overriding X"
    categorygroup text    -- Packaging | Treatment | Unconfigured
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
        FROM   waterrawmaterialitems i
        WHERE  i.waterrawmaterialitemid = p_itemid AND i.farmid = p_farmid;
    END IF;

    v_group   := public.fnwatercostrecognition_categorygroup(v_category);
    v_default := public.fnwatercostrecognition_farmdefault(p_farmid, v_category, p_asof);

    RETURN QUERY SELECT
        COALESCE(v_override, v_default),
        CASE WHEN v_override IS NOT NULL THEN 'ItemOverride' ELSE 'FarmDefault' END,
        v_default,
        v_group;
END;
$function$;

COMMENT ON FUNCTION public.fnwatercostrecognition_effective(text, integer, text, date) IS
    'The one resolver. Item override, else company default for the category '
    'group, else EXPENSE_WHEN_PURCHASED. Do not re-implement this anywhere.';

-- -----------------------------------------------------------------------------
-- 7. The two predicates every writer should ask, rather than comparing strings.
--
-- They take the SNAPSHOT off the transaction, not a farm id, precisely so a
-- caller cannot accidentally ask today's settings about last month's purchase.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwatercostrecognition_expenseatpurchase(p_method text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $function$
    -- Unknown or missing reads as today's behaviour. A method nobody recognises
    -- must not silently defer a cost out of the P&L.
    SELECT COALESCE(p_method, '') <> 'EXPENSE_WHEN_CONSUMED';
$function$;

CREATE OR REPLACE FUNCTION public.fnwatercostrecognition_expenseatconsumption(p_method text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT COALESCE(p_method, '') = 'EXPENSE_WHEN_CONSUMED';
$function$;

COMMENT ON FUNCTION public.fnwatercostrecognition_expenseatpurchase(text) IS
    'Exactly one of this and _expenseatconsumption is true for any input, which '
    'is what stops a cost being expensed twice or not at all.';

-- -----------------------------------------------------------------------------
-- 7b. THE INTERLOCK. Deferral cannot be switched on before it works.
--
-- This is the most important function in the file and it exists because of a
-- gap the poultry side never had.
--
-- 261 and 262 were applied together: the moment a poultry farm could CHOOSE
-- EXPENSE_WHEN_CONSUMED, 262 was there to stop the purchase writing its expense.
-- On the water side 275 is blocked -- it rewrites spwaterrawmaterialpurchase_
-- insert, whose live body is not in this repo -- so 274 can land alone.
--
-- That opens a trap that would be very expensive and very quiet:
--
--   1. A company sets Packaging to EXPENSE_WHEN_CONSUMED today.
--   2. 274 stamps each new purchase costrecognitionmethod = EXPENSE_WHEN_CONSUMED.
--   3. But 275 is not applied, so the purchase STILL writes its P&L expense.
--   4. Months later 279 lands, reads those snapshots, and recognises the very
--      same cost again as the stock is consumed.
--
-- The cost is now in Profit & Loss TWICE, on purchases nobody will think to
-- re-examine, and the snapshot -- which by design is never recomputed -- says
-- the second charge was correct.
--
-- So the setting refuses the deferred method until the phase-2 chain says it is
-- ready. This function returns FALSE, and the migration that makes consumption
-- recognition real replaces it with one returning TRUE. Nothing else may.
--
-- Deliberately a function rather than a settings flag: a flag is something an
-- administrator can switch on, and this is not a preference. It is a statement
-- about which migrations have been applied, and only a migration can make it.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnwatercostrecognition_deferralready()
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $function$
    SELECT FALSE;
$function$;

COMMENT ON FUNCTION public.fnwatercostrecognition_deferralready() IS
    'FALSE until the phase-2 chain (275 and 277-281) is applied. Replaced with '
    'TRUE by the consumption-recognition migration, and by nothing else. While '
    'it is FALSE, spwaterfinancialsettings_upsert refuses EXPENSE_WHEN_CONSUMED '
    'so no purchase can be stamped deferred while purchases are still expensed '
    'at purchase -- which would expense the same cost twice.';

-- -----------------------------------------------------------------------------
-- 8. Settings reads and writes.
--
-- _get never writes. A company with no row reads as the defaults, so opening the
-- settings page does not create rows for companies that never touched it.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterfinancialsettings_get(p_farmid text)
RETURNS TABLE(
    farmid                         text,
    packagingcostrecognitionmethod text,
    treatmentcostrecognitionmethod text,
    effectivefromdate              date,
    isconfigured                   boolean,
    -- Whether EXPENSE_WHEN_CONSUMED can be chosen at all. Surfaced so the
    -- settings page can say WHY the option is unavailable instead of hardcoding
    -- a state the database owns, or -- worse -- offering it and letting the save
    -- fail. See section 7b.
    deferralavailable              boolean,
    createdby                      text,
    createdat                      timestamp,
    updatedby                      text,
    updatedat                      timestamp
)
LANGUAGE sql STABLE
AS $function$
    SELECT p_farmid,
           COALESCE(s.packagingcostrecognitionmethod, 'EXPENSE_WHEN_PURCHASED'),
           COALESCE(s.treatmentcostrecognitionmethod, 'EXPENSE_WHEN_PURCHASED'),
           s.effectivefromdate,
           -- False means "nobody has chosen yet", which the page says out loud
           -- rather than showing a default as though it were a decision.
           (s.farmid IS NOT NULL),
           public.fnwatercostrecognition_deferralready(),
           s.createdby::text, s.createdat, s.updatedby::text, s.updatedat
    FROM   (SELECT p_farmid AS f) anchor
    LEFT   JOIN waterfinancialsettings s ON s.farmid = anchor.f;
$function$;

CREATE OR REPLACE FUNCTION public.spwaterfinancialsettings_upsert(
    p_farmid            text,
    p_packagingmethod   text,
    p_treatmentmethod   text,
    p_effectivefromdate date DEFAULT NULL,
    p_updatedby         text DEFAULT NULL
) RETURNS TABLE(
    farmid                         text,
    packagingcostrecognitionmethod text,
    treatmentcostrecognitionmethod text,
    effectivefromdate              date,
    isconfigured                   boolean,
    deferralavailable              boolean,
    createdby                      text,
    createdat                      timestamp,
    updatedby                      text,
    updatedat                      timestamp,
    -- Returned so the caller can audit the change without reading twice and
    -- racing itself.
    previouspackagingmethod        text,
    previoustreatmentmethod        text
)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_prevpack text;
    v_prevtreat text;
BEGIN
    IF COALESCE(p_packagingmethod, '') NOT IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED') THEN
        RAISE EXCEPTION 'Unknown packaging cost recognition method: "%".', p_packagingmethod;
    END IF;
    IF COALESCE(p_treatmentmethod, '') NOT IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED') THEN
        RAISE EXCEPTION 'Unknown treatment cost recognition method: "%".', p_treatmentmethod;
    END IF;
    -- Backdating would claim to change how past transactions were treated,
    -- while their snapshots say otherwise. Refuse rather than lie.
    IF p_effectivefromdate IS NOT NULL AND p_effectivefromdate < CURRENT_DATE THEN
        RAISE EXCEPTION 'An effective date cannot be in the past (got %). Existing purchases keep the method they were created with.',
            p_effectivefromdate;
    END IF;
    -- See section 7b. Choosing deferral before the phase-2 chain is applied
    -- would stamp purchases as deferred while they are still being expensed at
    -- purchase, and the same cost would be charged again when 279 lands.
    IF (p_packagingmethod = 'EXPENSE_WHEN_CONSUMED' OR p_treatmentmethod = 'EXPENSE_WHEN_CONSUMED')
       AND NOT public.fnwatercostrecognition_deferralready() THEN
        RAISE EXCEPTION 'Deferred cost recognition is not available for Water yet. Expense-when-consumed needs the consumption-recognition migrations, which are not applied; choosing it now would charge the same cost to Profit & Loss twice.';
    END IF;

    SELECT s.packagingcostrecognitionmethod, s.treatmentcostrecognitionmethod
    INTO   v_prevpack, v_prevtreat
    FROM   waterfinancialsettings s WHERE s.farmid = p_farmid;

    v_prevpack  := COALESCE(v_prevpack,  'EXPENSE_WHEN_PURCHASED');
    v_prevtreat := COALESCE(v_prevtreat, 'EXPENSE_WHEN_PURCHASED');

    -- Explicit UPDATE-else-INSERT rather than ON CONFLICT, and not by choice:
    -- this function RETURNS TABLE(farmid ...), so `ON CONFLICT (farmid)` cannot
    -- tell the output column from the table column and Postgres refuses it as
    -- ambiguous. Same shape spwaterfarmsettings writers already use.
    IF EXISTS (SELECT 1 FROM waterfinancialsettings s WHERE s.farmid = p_farmid) THEN
        UPDATE waterfinancialsettings s
        SET    packagingcostrecognitionmethod = p_packagingmethod,
               treatmentcostrecognitionmethod = p_treatmentmethod,
               effectivefromdate              = p_effectivefromdate,
               updatedby                      = p_updatedby,
               updatedat                      = (now() at time zone 'utc')
        WHERE  s.farmid = p_farmid;
    ELSE
        INSERT INTO waterfinancialsettings (
            farmid, packagingcostrecognitionmethod, treatmentcostrecognitionmethod,
            effectivefromdate, createdby, updatedby, updatedat)
        VALUES (
            p_farmid, p_packagingmethod, p_treatmentmethod,
            p_effectivefromdate, p_updatedby, p_updatedby, (now() at time zone 'utc'));
    END IF;

    RETURN QUERY
    SELECT g.*, v_prevpack, v_prevtreat
    FROM   spwaterfinancialsettings_get(p_farmid) g;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 9. Reaching the item override WITHOUT touching the live item SPs.
--
-- See the header for why _insert / _update / _getall are left alone. These two
-- are purely additive: nothing existing calls them, so nothing existing can
-- break, and the item list keeps returning exactly the columns it returns today.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spwaterrawmaterialitem_setcostrecognition(
    p_waterrawmaterialitemid  integer,
    p_farmid                  text,
    -- NULL or 'USE_DEFAULT' clears the override. 'USE_DEFAULT' is accepted as a
    -- spelling of "no override" so a frontend that sends the radio value
    -- verbatim cannot write a bogus method.
    p_costrecognitionoverride text DEFAULT NULL,
    p_updatedby               text DEFAULT NULL
) RETURNS TABLE(
    waterrawmaterialitemid         integer,
    costrecognitionoverride        text,
    effectivecostrecognitionmethod text,
    costrecognitionsource          text,
    costrecognitioncategorygroup   text
)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_override text := NULLIF(btrim(COALESCE(p_costrecognitionoverride, '')), '');
BEGIN
    IF v_override = 'USE_DEFAULT' THEN v_override := NULL; END IF;
    IF v_override IS NOT NULL
       AND v_override NOT IN ('EXPENSE_WHEN_PURCHASED', 'EXPENSE_WHEN_CONSUMED') THEN
        RAISE EXCEPTION 'Unknown cost recognition override: "%".', v_override;
    END IF;
    -- The same interlock the company setting has, for the same reason: an item
    -- override reaches the purchase snapshot by exactly the same path, so
    -- leaving this door open would make section 7b's guard decorative.
    IF v_override = 'EXPENSE_WHEN_CONSUMED'
       AND NOT public.fnwatercostrecognition_deferralready() THEN
        RAISE EXCEPTION 'Deferred cost recognition is not available for Water yet. Expense-when-consumed needs the consumption-recognition migrations, which are not applied; choosing it now would charge the same cost to Profit & Loss twice.';
    END IF;

    -- Scoped by farmid as well as id: an item id from another company must not
    -- be writable just because it exists.
    UPDATE waterrawmaterialitems i
    SET    costrecognitionoverride = v_override,
           updatedat               = (now() at time zone 'utc')
    WHERE  i.waterrawmaterialitemid = p_waterrawmaterialitemid
      AND  i.farmid = p_farmid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Raw material item % does not belong to this company.',
              p_waterrawmaterialitemid;
    END IF;

    RETURN QUERY
    SELECT i.waterrawmaterialitemid,
           i.costrecognitionoverride::text,
           r.method, r.source, r.categorygroup
    FROM   waterrawmaterialitems i
    CROSS  JOIN LATERAL public.fnwatercostrecognition_effective(
                            p_farmid, i.waterrawmaterialitemid, i.category, NULL) r
    WHERE  i.waterrawmaterialitemid = p_waterrawmaterialitemid
      AND  i.farmid = p_farmid;
END;
$function$;

COMMENT ON FUNCTION public.spwaterrawmaterialitem_setcostrecognition(integer, text, text, text) IS
    'Writes one item''s cost-recognition override. Interim: folds into '
    'spwaterrawmaterialitem_update once its live Postgres body is available.';

-- The resolved view of every item, for the settings page and the item list to
-- join against. Deliberately a separate read rather than extra columns on
-- spwaterrawmaterialitem_getall, for the same reason.
CREATE OR REPLACE FUNCTION public.spwatercostrecognition_items(p_farmid text)
RETURNS TABLE(
    waterrawmaterialitemid         integer,
    itemname                       text,
    category                       text,
    isactive                       boolean,
    costrecognitionoverride        text,
    effectivecostrecognitionmethod text,
    costrecognitionsource          text,
    costrecognitioncategorygroup   text,
    farmdefaultmethod              text
)
LANGUAGE sql STABLE
AS $function$
    SELECT i.waterrawmaterialitemid,
           i.itemname::text,
           i.category::text,
           i.isactive,
           i.costrecognitionoverride::text,
           r.method, r.source, r.categorygroup, r.farmdefault
    FROM   waterrawmaterialitems i
    CROSS  JOIN LATERAL public.fnwatercostrecognition_effective(
                            p_farmid, i.waterrawmaterialitemid, i.category, NULL) r
    WHERE  i.farmid = p_farmid
    ORDER  BY i.isactive DESC NULLS LAST, i.itemname;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification.
-- -----------------------------------------------------------------------------
SELECT 'every purchase is snapshotted' AS check,
       CASE WHEN COUNT(*) FILTER (WHERE costrecognitionmethod IS NULL) = 0
            THEN 'OK' ELSE 'NULL on ' || COUNT(*) FILTER (WHERE costrecognitionmethod IS NULL) END AS result
FROM   waterrawmaterialpurchases

UNION ALL
-- Nothing may have been backfilled as deferred: no company asked for that.
SELECT 'no purchase backfilled as deferred',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   waterrawmaterialpurchases
WHERE  costrecognitionmethod = 'EXPENSE_WHEN_CONSUMED'

UNION ALL
SELECT 'no item starts with an override',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'FOUND ' || COUNT(*) END
FROM   waterrawmaterialitems
WHERE  costrecognitionoverride IS NOT NULL

UNION ALL
-- The point of the whole file: every existing item still resolves to today's
-- behaviour, because no settings row exists and no override was written.
SELECT 'every item still resolves to purchased',
       CASE WHEN COUNT(*) = 0 THEN 'OK' ELSE 'CHANGED ' || COUNT(*) END
FROM   waterrawmaterialitems i
CROSS  JOIN LATERAL public.fnwatercostrecognition_effective(i.farmid, i.waterrawmaterialitemid, i.category, NULL) r
WHERE  r.method <> 'EXPENSE_WHEN_PURCHASED';
