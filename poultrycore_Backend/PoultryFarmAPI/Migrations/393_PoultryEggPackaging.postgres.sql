-- =============================================================================
-- 393: Egg packaging -- Boxes, Crates and Pieces (phase 1 of the egg packaging
-- programme: configuration + the one conversion rule).
--
-- A Box is a QUANTITY UNIT: N crates of the farm's crate size. It is not stock,
-- not a poultry batch, and not physically packed eggs. Egg stock stays in
-- individual eggs (poultrystocktransactions / sale.quantity are eggs); boxes
-- and crates are only ever conversions of that number.
--
--   1. poultryeggsortingsettings gains the per-company packaging columns.
--      Existing farms: Boxes OFF, display Crates & Pieces -- nothing changes
--      for them until they switch it on.
--   2. fnpoultry_eggpackaging(farm)        the farm's configuration (one row).
--      fnpoultry_eggpieces(b, c, p, ...)   Boxes/Crates/Pieces -> eggs.
--      fnpoultry_eggbreakdown(eggs, ...)   eggs -> whole boxes, crates, pieces.
--      fnpoultry_eggqtytext(eggs, ...)     "25 boxes + 5 crates + 25 pcs".
--   3. sppoultryeggpackaging_get / _save   read / change the configuration.
--      Saving never touches stock, sales or movements: a posted transaction
--      keeps the conversion it was recorded with (snapshots land with the
--      sales phase). packagingversion bumps whenever the conversion changes,
--      so caches can key on it.
--   4. The settings audit trigger records the packaging columns too.
--
-- The eggs-per-crate setting itself (344) is unchanged: it stays editable on
-- Sizes & settings, and Eggs per Box follows it (crates per box x crate size).
--
-- Idempotent: safe to run twice.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Columns
-- -----------------------------------------------------------------------------
ALTER TABLE public.poultryeggsortingsettings ADD COLUMN IF NOT EXISTS enableboxes boolean NOT NULL DEFAULT FALSE;
ALTER TABLE public.poultryeggsortingsettings ADD COLUMN IF NOT EXISTS cratesperbox integer NULL;
ALTER TABLE public.poultryeggsortingsettings ADD COLUMN IF NOT EXISTS eggdisplay text NOT NULL DEFAULT 'CratesPieces';
ALTER TABLE public.poultryeggsortingsettings ADD COLUMN IF NOT EXISTS saleentryunit text NOT NULL DEFAULT 'Crates';
ALTER TABLE public.poultryeggsortingsettings ADD COLUMN IF NOT EXISTS packagingversion integer NOT NULL DEFAULT 1;

DO $c$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_poultryeggsortingsettings_cratesperbox') THEN
        ALTER TABLE public.poultryeggsortingsettings
            ADD CONSTRAINT ck_poultryeggsortingsettings_cratesperbox CHECK (cratesperbox IS NULL OR cratesperbox BETWEEN 1 AND 200);
    END IF;
    -- Boxes on means a box size; a box size with boxes off is kept (switching
    -- off and on again should not lose it).
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_poultryeggsortingsettings_boxesneedsize') THEN
        ALTER TABLE public.poultryeggsortingsettings
            ADD CONSTRAINT ck_poultryeggsortingsettings_boxesneedsize CHECK (NOT enableboxes OR cratesperbox IS NOT NULL);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_poultryeggsortingsettings_eggdisplay') THEN
        ALTER TABLE public.poultryeggsortingsettings
            ADD CONSTRAINT ck_poultryeggsortingsettings_eggdisplay CHECK (eggdisplay IN ('BoxesCratesPieces', 'CratesPieces', 'Pieces'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_poultryeggsortingsettings_saleentryunit') THEN
        ALTER TABLE public.poultryeggsortingsettings
            ADD CONSTRAINT ck_poultryeggsortingsettings_saleentryunit CHECK (saleentryunit IN ('Boxes', 'Crates'));
    END IF;
END;
$c$;

-- -----------------------------------------------------------------------------
-- 2. The conversion rule. Integer arithmetic only: never a fractional egg.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fnpoultry_eggpackaging(text);
CREATE FUNCTION public.fnpoultry_eggpackaging(p_farmid text)
RETURNS TABLE (eggspercrate integer, enableboxes boolean, cratesperbox integer, eggsperbox integer,
               eggdisplay text, saleentryunit text, packagingversion integer)
LANGUAGE sql
STABLE
AS $function$
    SELECT COALESCE(s.eggspercrate, 30),
           COALESCE(s.enableboxes, FALSE),
           s.cratesperbox,
           CASE WHEN COALESCE(s.enableboxes, FALSE) AND s.cratesperbox IS NOT NULL
                THEN s.cratesperbox * COALESCE(s.eggspercrate, 30) END,
           -- A box display without boxes on falls back to crates: the stored
           -- preference survives switching boxes off and on.
           CASE WHEN COALESCE(s.eggdisplay, 'CratesPieces') = 'BoxesCratesPieces' AND NOT COALESCE(s.enableboxes, FALSE)
                THEN 'CratesPieces' ELSE COALESCE(s.eggdisplay, 'CratesPieces') END,
           CASE WHEN COALESCE(s.enableboxes, FALSE) THEN COALESCE(s.saleentryunit, 'Crates') ELSE 'Crates' END,
           COALESCE(s.packagingversion, 1)
    FROM   (SELECT 1) one
    LEFT   JOIN poultryeggsortingsettings s ON s.farmid = p_farmid;
$function$;

-- Boxes / Crates / Pieces -> eggs. Refuses what would make a wrong egg count
-- rather than guessing: negatives, boxes without a box size, absurd numbers.
CREATE OR REPLACE FUNCTION public.fnpoultry_eggpieces(
    p_boxes integer, p_crates integer, p_pieces integer, p_eggspercrate integer, p_cratesperbox integer)
RETURNS bigint
LANGUAGE plpgsql
IMMUTABLE
AS $function$
BEGIN
    IF COALESCE(p_boxes, 0) < 0 OR COALESCE(p_crates, 0) < 0 OR COALESCE(p_pieces, 0) < 0 THEN
        RAISE EXCEPTION 'Boxes, crates and pieces cannot be negative.';
    END IF;
    IF p_eggspercrate IS NULL OR p_eggspercrate < 1 THEN
        RAISE EXCEPTION 'Eggs per crate must be at least 1.';
    END IF;
    IF COALESCE(p_boxes, 0) > 0 AND (p_cratesperbox IS NULL OR p_cratesperbox < 1) THEN
        RAISE EXCEPTION 'Boxes are not set up for this farm. Set crates per box first.';
    END IF;
    IF COALESCE(p_boxes, 0) > 1000000 OR COALESCE(p_crates, 0) > 10000000 OR COALESCE(p_pieces, 0) > 100000000 THEN
        RAISE EXCEPTION 'That quantity is too large.';
    END IF;
    RETURN COALESCE(p_boxes, 0)::bigint * COALESCE(p_cratesperbox, 0) * p_eggspercrate
         + COALESCE(p_crates, 0)::bigint * p_eggspercrate
         + COALESCE(p_pieces, 0);
END;
$function$;

-- Eggs -> whole boxes, then whole crates, then loose pieces. p_cratesperbox
-- NULL (boxes off) gives 0 boxes. A negative count (a decrease, a correction)
-- is split by its size and every part carries the sign; remainders are never
-- negative on their own.
CREATE OR REPLACE FUNCTION public.fnpoultry_eggbreakdown(
    p_eggs numeric, p_eggspercrate integer, p_cratesperbox integer)
RETURNS TABLE (boxes bigint, crates bigint, pieces bigint)
LANGUAGE sql
IMMUTABLE
AS $function$
    WITH a AS (
        SELECT trunc(abs(COALESCE(p_eggs, 0)))::bigint AS n,
               CASE WHEN COALESCE(p_eggs, 0) < 0 THEN -1 ELSE 1 END AS sgn,
               GREATEST(COALESCE(p_eggspercrate, 30), 1)::bigint AS epc,
               CASE WHEN p_cratesperbox >= 1 THEN p_cratesperbox::bigint END AS cpb
    ), b AS (
        SELECT n, sgn, epc,
               CASE WHEN cpb IS NULL THEN 0 ELSE n / (cpb * epc) END AS bx,
               CASE WHEN cpb IS NULL THEN n ELSE n % (cpb * epc) END AS rest
        FROM a
    )
    SELECT sgn * bx, sgn * (rest / epc), sgn * (rest % epc) FROM b;
$function$;

-- One quantity as text, the same words the web app uses (lib/poultry/egg-packaging.ts):
-- BoxesCratesPieces "25 boxes + 5 crates + 25 pcs", CratesPieces "355 crates + 25 pcs",
-- Pieces "10,675 eggs". Zero parts are left out; nothing at all is "0 eggs".
CREATE OR REPLACE FUNCTION public.fnpoultry_eggqtytext(
    p_eggs numeric, p_eggspercrate integer, p_cratesperbox integer, p_display text DEFAULT 'CratesPieces')
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
    WITH d AS (
        SELECT CASE WHEN p_display = 'Pieces' THEN 'Pieces'
                    WHEN p_display = 'BoxesCratesPieces' AND p_cratesperbox >= 1 THEN 'BoxesCratesPieces'
                    ELSE 'CratesPieces' END AS mode
    ), k AS (
        SELECT d.mode, x.boxes, x.crates, x.pieces
        FROM d, public.fnpoultry_eggbreakdown(p_eggs, p_eggspercrate,
                                              CASE WHEN d.mode = 'BoxesCratesPieces' THEN p_cratesperbox END) x
    )
    SELECT CASE
        WHEN k.mode = 'Pieces' OR (k.boxes = 0 AND k.crates = 0) THEN
            to_char(trunc(COALESCE(p_eggs, 0)), 'FM999,999,999,990') || ' egg' || CASE WHEN abs(trunc(COALESCE(p_eggs, 0))) = 1 THEN '' ELSE 's' END
        ELSE
            concat_ws(' + ',
                CASE WHEN k.boxes  <> 0 THEN to_char(k.boxes,  'FM999,999,990') || ' box'   || CASE WHEN abs(k.boxes)  = 1 THEN '' ELSE 'es' END END,
                CASE WHEN k.crates <> 0 THEN to_char(k.crates, 'FM999,999,990') || ' crate' || CASE WHEN abs(k.crates) = 1 THEN '' ELSE 's'  END END,
                CASE WHEN k.pieces <> 0 THEN to_char(k.pieces, 'FM999,999,990') || ' pcs' END)
        END
    FROM k;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Read / change the configuration
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.sppoultryeggpackaging_get(text);
CREATE FUNCTION public.sppoultryeggpackaging_get(p_farmid text)
RETURNS TABLE (farmid text, eggspercrate integer, enableboxes boolean, cratesperbox integer, eggsperbox integer,
               eggdisplay text, saleentryunit text, packagingversion integer,
               storedcratesperbox integer, storeddisplay text, storedentryunit text)
LANGUAGE sql
STABLE
AS $function$
    SELECT p_farmid, e.eggspercrate, e.enableboxes, e.cratesperbox, e.eggsperbox,
           e.eggdisplay, e.saleentryunit, e.packagingversion,
           -- What the settings screen edits: the stored values, before the
           -- "boxes off" fallbacks above.
           s.cratesperbox, COALESCE(s.eggdisplay, 'CratesPieces'), COALESCE(s.saleentryunit, 'Crates')
    FROM   public.fnpoultry_eggpackaging(p_farmid) e
    LEFT   JOIN poultryeggsortingsettings s ON s.farmid = p_farmid;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryeggpackaging_save(
    p_farmid text, p_enableboxes boolean, p_cratesperbox integer,
    p_eggdisplay text, p_saleentryunit text, p_by text DEFAULT NULL)
RETURNS integer      -- the packaging version now in force
LANGUAGE plpgsql
AS $function$
DECLARE
    v_display text := COALESCE(NULLIF(btrim(p_eggdisplay), ''), 'CratesPieces');
    v_entry   text := COALESCE(NULLIF(btrim(p_saleentryunit), ''), 'Crates');
    v_old     poultryeggsortingsettings%ROWTYPE;
    v_version integer;
BEGIN
    IF p_farmid IS NULL OR btrim(p_farmid) = '' THEN
        RAISE EXCEPTION 'Company ID is required.';
    END IF;
    IF COALESCE(p_enableboxes, FALSE) AND p_cratesperbox IS NULL THEN
        RAISE EXCEPTION 'Enter how many crates are in one box.';
    END IF;
    IF p_cratesperbox IS NOT NULL AND p_cratesperbox NOT BETWEEN 1 AND 200 THEN
        RAISE EXCEPTION 'Crates per box must be a whole number from 1 to 200.';
    END IF;
    IF v_display NOT IN ('BoxesCratesPieces', 'CratesPieces', 'Pieces') THEN
        RAISE EXCEPTION 'Egg display must be Boxes, Crates & Pieces; Crates & Pieces; or Total eggs.';
    END IF;
    IF v_display = 'BoxesCratesPieces' AND NOT COALESCE(p_enableboxes, FALSE) THEN
        RAISE EXCEPTION 'Turn on Boxes to show quantities in boxes.';
    END IF;
    IF v_entry NOT IN ('Boxes', 'Crates') THEN
        RAISE EXCEPTION 'Sales entry can put Boxes or Crates first.';
    END IF;
    IF v_entry = 'Boxes' AND NOT COALESCE(p_enableboxes, FALSE) THEN
        RAISE EXCEPTION 'Turn on Boxes to enter sales in boxes first.';
    END IF;

    SELECT * INTO v_old FROM poultryeggsortingsettings s WHERE s.farmid = p_farmid FOR UPDATE;

    INSERT INTO poultryeggsortingsettings
        (farmid, enableeggsorting, closingpolicy, eggspercrate, enableboxes, cratesperbox, eggdisplay, saleentryunit,
         packagingversion, updatedby, updatedatutc)
    VALUES (p_farmid, FALSE, 'Warning', 30, COALESCE(p_enableboxes, FALSE), p_cratesperbox, v_display, v_entry,
            1, p_by, now())
    ON CONFLICT (farmid) DO UPDATE
    SET enableboxes  = EXCLUDED.enableboxes,
        cratesperbox = EXCLUDED.cratesperbox,
        eggdisplay   = EXCLUDED.eggdisplay,
        saleentryunit = EXCLUDED.saleentryunit,
        -- The conversion changed (on/off or box size): new version. Display and
        -- entry order are presentation only and keep the version.
        packagingversion = poultryeggsortingsettings.packagingversion
            + CASE WHEN (poultryeggsortingsettings.enableboxes, poultryeggsortingsettings.cratesperbox)
                        IS DISTINCT FROM (EXCLUDED.enableboxes, EXCLUDED.cratesperbox) THEN 1 ELSE 0 END,
        updatedby    = EXCLUDED.updatedby,
        updatedatutc = now()
    RETURNING packagingversion INTO v_version;

    RETURN v_version;
END;
$function$;

-- Changing the crate size changes eggs per box too: bump the version there as
-- well, so a cache keyed on it cannot keep the old box size.
CREATE OR REPLACE FUNCTION public.trg_poultryeggsettings_packagingversion_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.eggspercrate IS DISTINCT FROM OLD.eggspercrate
       AND NEW.packagingversion IS NOT DISTINCT FROM OLD.packagingversion THEN
        NEW.packagingversion := OLD.packagingversion + 1;
    END IF;
    RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS trg_poultryeggsettings_packagingversion ON public.poultryeggsortingsettings;
CREATE TRIGGER trg_poultryeggsettings_packagingversion BEFORE UPDATE ON public.poultryeggsortingsettings
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryeggsettings_packagingversion_fn();

-- -----------------------------------------------------------------------------
-- 4. Audit: the 344 trigger, plus the packaging columns.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_poultryeggsettings_audit_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF TG_OP = 'UPDATE'
       AND (NEW.enableeggsorting, NEW.closingpolicy, NEW.eggspercrate, NEW.unsortedpricepercrate,
            NEW.enableboxes, NEW.cratesperbox, NEW.eggdisplay, NEW.saleentryunit)
           IS NOT DISTINCT FROM (OLD.enableeggsorting, OLD.closingpolicy, OLD.eggspercrate, OLD.unsortedpricepercrate,
                                 OLD.enableboxes, OLD.cratesperbox, OLD.eggdisplay, OLD.saleentryunit) THEN
        RETURN NEW;
    END IF;
    INSERT INTO poultryeggsortingaudit (farmid, entity, entityid, action, actor, details)
    VALUES (NEW.farmid, 'Settings', NULL, 'SettingsChanged', COALESCE(NEW.updatedby, public.fnpoultryeggaudit_actor(NULL)),
            jsonb_build_object('enableEggSorting', NEW.enableeggsorting, 'closingPolicy', NEW.closingpolicy,
                               'eggsPerCrate', NEW.eggspercrate, 'unsortedPricePerCrate', NEW.unsortedpricepercrate,
                               'enableBoxes', NEW.enableboxes, 'cratesPerBox', NEW.cratesperbox,
                               'eggDisplay', NEW.eggdisplay, 'saleEntryUnit', NEW.saleentryunit,
                               'packagingVersion', NEW.packagingversion)
            || CASE WHEN TG_OP = 'UPDATE' THEN jsonb_build_object('before', jsonb_build_object(
                    'enableEggSorting', OLD.enableeggsorting, 'closingPolicy', OLD.closingpolicy,
                    'eggsPerCrate', OLD.eggspercrate, 'unsortedPricePerCrate', OLD.unsortedpricepercrate,
                    'enableBoxes', OLD.enableboxes, 'cratesPerBox', OLD.cratesperbox,
                    'eggDisplay', OLD.eggdisplay, 'saleEntryUnit', OLD.saleentryunit,
                    'packagingVersion', OLD.packagingversion))
                    ELSE '{}'::jsonb END);
    RETURN NEW;
END;
$function$;
