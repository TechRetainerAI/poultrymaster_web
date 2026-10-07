-- =============================================================================
-- 341_PoultryEggClasses.postgres.sql
--
-- Purpose
-- -------
-- Foundation for the Egg Sorting Workspace (342): egg stock by CLASS, egg
-- sales by class, and one production record per flock per day.
--
--   PRODUCTION CREATES EGGS. SORTING DOES NOT CREATE EGGS -- IT RECLASSIFIES
--   EGGS THAT ALREADY EXIST. SALES CONSUME THE CLASS BEING SOLD.
--
-- ONE LEDGER, SEVERAL CLASSES
-- ===========================
-- Egg stock already lives in exactly one place: poultrystocktransactions
-- against the farm's raw-egg product (204 made the ledger the single source of
-- truth; 206 made its unit the egg, not the crate). This migration keeps that
-- product and gives it a second name in the UI: "Unsorted / General eggs".
-- Production keeps posting to it exactly as before -- nothing about
-- sppoultryeggstock_syncforproduction changes.
--
-- Each egg SIZE a farm sorts into is its own poultryproducts row (unit 'Egg',
-- israweggproduct FALSE) linked from poultryeggsizes. So "Large eggs on hand"
-- is SUM(quantity) for the Large product -- the same formula as every other
-- product -- and there is still one ledger, not a production inventory beside a
-- sorting inventory. Sizes are per farm and editable; the seed is the list the
-- app already offered (lib/constants/egg-grade.ts): Small, Medium, Large,
-- XLarge, Jumbo, Seconds, Cracks, Mixed. Seeding is lazy (on first use), so a
-- farm that never sorts never sees eight empty products in its product list.
--
-- EGG SALES BY CLASS
-- ==================
-- sale gains poultryproductid (NULL = Unsorted, which is every sale made
-- before this migration) and salegroupno (several sale rows entered together
-- as one multi-size sale). sppoultryeggstock_syncforsale now deducts from the
-- sale's own class; a Large sale can never be satisfied from Unsorted stock,
-- and deleting it restores Large, not Unsorted, because the movement it
-- removes is the Large one. The spsale_insert / spsale_update signatures do
-- NOT change: the class is set afterwards by sppoultrysale_setegg, which
-- re-runs the (idempotent, delete-and-reinsert) sync.
--
-- ONE PRODUCTION RECORD PER FLOCK PER DAY
-- =======================================
-- productionrecords has no unique constraint on (farm, flock, date) and 14
-- duplicate groups exist live (none of them carry an egg grade). A unique
-- index would fail on them, so the rule is a trigger instead: a NEW record, or
-- an edit that MOVES a record onto a flock/date that already has one, is
-- refused with SQLSTATE P0010 and a sentence the user can act on. Existing
-- duplicates can still be edited in place and are listed by
-- sppoultryproduction_duplicates for a person to merge -- nothing is deleted
-- or merged automatically.
--
-- The legacy Egg Sorting page (/egg-production) writes productionrecords
-- through speggproduction_insert and used to add one row per grade. Its UI is
-- unchanged (user decision 2026-10-05); a save that would duplicate a flock's
-- day is now refused with the P0010 message, which points at the Egg Sorting
-- Workspace. Batch posting already refused duplicates (251) and keeps its own
-- message because its check runs first.
--
-- NOTE: the self-tests of 332 and 333 insert deliberate duplicates. They have
-- run; re-running those two files after this one would trip the new rule.
--
-- Rollback: DROP TRIGGER tr_productionrecords_oneperday ON productionrecords;
-- restore sppoultryeggstock_syncforsale / fnpoultrycrateunits from the live
-- definitions captured 2026-10-05 (egg_inspect_out.txt); the new tables and
-- columns are additive.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Settings: is sorting on, and does it gate Daily Closing?
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultryeggsortingsettings (
    farmid               text        PRIMARY KEY,
    enableeggsorting     boolean     NOT NULL DEFAULT FALSE,
    -- What Daily Closing does when the day's eggs are not all sorted.
    -- Off = say nothing, Warning (default) = inform, Blocking = refuse to close.
    -- Default is NOT blocking: many farms sort the next morning.
    closingpolicy        text        NOT NULL DEFAULT 'Warning'
        CONSTRAINT ck_poultryeggsortingsettings_policy CHECK (closingpolicy IN ('Off', 'Warning', 'Blocking')),
    updatedby            text,
    updatedatutc         timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.sppoultryeggsortingsettings_get(p_farmid text)
RETURNS TABLE (farmid text, enableeggsorting boolean, closingpolicy text, iscustomised boolean,
               updatedby text, updatedatutc timestamptz)
LANGUAGE sql
STABLE
AS $function$
    SELECT p_farmid,
           COALESCE(s.enableeggsorting, FALSE),
           COALESCE(s.closingpolicy, 'Warning'),
           s.farmid IS NOT NULL,
           s.updatedby,
           s.updatedatutc
    FROM   (SELECT 1) one
    LEFT   JOIN poultryeggsortingsettings s ON s.farmid = p_farmid;
$function$;

-- -----------------------------------------------------------------------------
-- 2. Egg sizes (per farm) and the product behind each one
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultryeggsizes (
    eggsizeid         serial      PRIMARY KEY,
    farmid            text        NOT NULL,
    name              varchar(50) NOT NULL CHECK (btrim(name) <> ''),
    sortorder         integer     NOT NULL DEFAULT 0,
    isactive          boolean     NOT NULL DEFAULT TRUE,
    poultryproductid  integer     NOT NULL REFERENCES public.poultryproducts (poultryproductid),
    createdby         text,
    createdatutc      timestamptz NOT NULL DEFAULT now(),
    updatedatutc      timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_poultryeggsizes_farm_name ON public.poultryeggsizes (farmid, lower(name));
CREATE UNIQUE INDEX IF NOT EXISTS uq_poultryeggsizes_product ON public.poultryeggsizes (poultryproductid);

-- Sizes are history: a sorting line or a sale points at one. Deactivate instead.
CREATE OR REPLACE FUNCTION public.trg_poultryeggsizes_nodelete()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    RAISE EXCEPTION 'Egg sizes cannot be deleted because stock history refers to them. Mark the size inactive instead.';
END;
$function$;
DROP TRIGGER IF EXISTS trg_poultryeggsizes_nodelete ON public.poultryeggsizes;
CREATE TRIGGER trg_poultryeggsizes_nodelete BEFORE DELETE ON public.poultryeggsizes
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryeggsizes_nodelete();

-- The farm's Unsorted product: the existing raw-egg product, found the way
-- every egg sync finds it, created the way they create it when missing.
CREATE OR REPLACE FUNCTION public.fnpoultry_unsortedeggproduct(p_farmid text)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_egg integer;
BEGIN
    SELECT pp.poultryproductid INTO v_egg
    FROM   poultryproducts pp
    WHERE  pp.farmid = p_farmid AND (pp.israweggproduct = TRUE OR pp.name IN ('Eggs', 'Chicken Eggs'))
    ORDER  BY pp.israweggproduct DESC, pp.poultryproductid
    LIMIT  1;

    IF v_egg IS NULL THEN
        INSERT INTO poultryproducts (farmid, name, unit, unitprice, producttype, israweggproduct, requiresrecipesetup)
        VALUES (p_farmid, 'Eggs', 'Egg', 0, 'FinishedGood', TRUE, FALSE)
        RETURNING poultryproductid INTO v_egg;
    END IF;
    RETURN v_egg;
END;
$function$;

-- Is this product one of the farm's egg classes (Unsorted or a size)?
CREATE OR REPLACE FUNCTION public.fnpoultry_iseggclass(p_farmid text, p_poultryproductid integer)
RETURNS boolean
LANGUAGE sql
STABLE
AS $function$
    SELECT EXISTS (SELECT 1 FROM poultryproducts p
                   WHERE p.poultryproductid = p_poultryproductid AND p.farmid = p_farmid
                     AND (p.israweggproduct = TRUE OR p.name IN ('Eggs', 'Chicken Eggs')))
        OR EXISTS (SELECT 1 FROM poultryeggsizes s
                   WHERE s.poultryproductid = p_poultryproductid AND s.farmid = p_farmid);
$function$;

-- Create the size AND its product. The product is named "Eggs - <size>"; if a
-- farm already has an unrelated product with that name, " (sorted)" is added
-- rather than adopting someone else's stock history.
CREATE OR REPLACE FUNCTION public.sppoultryeggsize_save(
    p_farmid text, p_eggsizeid integer, p_name text, p_sortorder integer DEFAULT NULL,
    p_isactive boolean DEFAULT TRUE, p_by text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_name    text := btrim(COALESCE(p_name, ''));
    v_prod    integer;
    v_pname   text;
    v_id      integer;
BEGIN
    IF v_name = '' THEN
        RAISE EXCEPTION 'Enter a name for the egg size.';
    END IF;
    IF length(v_name) > 40 THEN
        RAISE EXCEPTION 'Keep the egg size name to 40 characters or fewer.';
    END IF;
    IF lower(v_name) IN ('unsorted', 'general', 'unsorted / general', 'eggs') THEN
        RAISE EXCEPTION '"%" is reserved for eggs that have not been sorted.', v_name;
    END IF;
    IF EXISTS (SELECT 1 FROM poultryeggsizes s
               WHERE s.farmid = p_farmid AND lower(s.name) = lower(v_name)
                 AND s.eggsizeid IS DISTINCT FROM p_eggsizeid) THEN
        RAISE EXCEPTION 'There is already an egg size called %.', v_name;
    END IF;

    v_pname := 'Eggs - ' || v_name;
    IF EXISTS (SELECT 1 FROM poultryproducts p WHERE p.farmid = p_farmid AND p.name = v_pname
               AND NOT EXISTS (SELECT 1 FROM poultryeggsizes s
                               WHERE s.poultryproductid = p.poultryproductid AND s.eggsizeid IS NOT DISTINCT FROM p_eggsizeid)) THEN
        v_pname := v_pname || ' (sorted)';
    END IF;

    IF p_eggsizeid IS NULL THEN
        INSERT INTO poultryproducts (farmid, name, unit, unitprice, producttype, israweggproduct, requiresrecipesetup, size, notes)
        VALUES (p_farmid, v_pname, 'Egg', 0, 'FinishedGood', FALSE, FALSE, v_name,
                'Sorted eggs. Stock comes from the Egg Sorting Workspace.')
        RETURNING poultryproductid INTO v_prod;

        INSERT INTO poultryeggsizes (farmid, name, sortorder, isactive, poultryproductid, createdby)
        VALUES (p_farmid, v_name,
                COALESCE(p_sortorder, (SELECT COALESCE(max(sortorder), 0) + 10 FROM poultryeggsizes WHERE farmid = p_farmid)),
                COALESCE(p_isactive, TRUE), v_prod, p_by)
        RETURNING eggsizeid INTO v_id;
        RETURN v_id;
    END IF;

    UPDATE poultryeggsizes s
    SET    name = v_name, sortorder = COALESCE(p_sortorder, s.sortorder),
           isactive = COALESCE(p_isactive, s.isactive), updatedatutc = now()
    WHERE  s.eggsizeid = p_eggsizeid AND s.farmid = p_farmid
    RETURNING s.poultryproductid INTO v_prod;

    IF v_prod IS NULL THEN
        RAISE EXCEPTION 'Egg size % not found for this company.', p_eggsizeid;
    END IF;

    UPDATE poultryproducts p
    SET    name = v_pname, size = v_name, isactive = COALESCE(p_isactive, p.isactive),
           updateddate = (now() at time zone 'utc')
    WHERE  p.poultryproductid = v_prod AND p.farmid = p_farmid;

    RETURN p_eggsizeid;
END;
$function$;

-- Seed the default list once per farm. Safe to call on every page load.
CREATE OR REPLACE FUNCTION public.sppoultryeggsizes_ensure(p_farmid text, p_by text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_name text;
    v_ord  integer := 0;
BEGIN
    PERFORM public.fnpoultry_unsortedeggproduct(p_farmid);
    IF EXISTS (SELECT 1 FROM poultryeggsizes WHERE farmid = p_farmid) THEN
        RETURN 0;
    END IF;
    -- Serialise two first visits so the seed cannot run twice.
    PERFORM pg_advisory_xact_lock(hashtext('poultry-eggsizes-seed:' || p_farmid));
    IF EXISTS (SELECT 1 FROM poultryeggsizes WHERE farmid = p_farmid) THEN
        RETURN 0;
    END IF;
    FOREACH v_name IN ARRAY ARRAY['Small', 'Medium', 'Large', 'XLarge', 'Jumbo', 'Seconds', 'Cracks', 'Mixed'] LOOP
        v_ord := v_ord + 10;
        PERFORM public.sppoultryeggsize_save(p_farmid, NULL, v_name, v_ord, TRUE, p_by);
    END LOOP;
    RETURN 8;
END;
$function$;

-- Every egg class with what is on hand: Unsorted first, then sizes in order.
CREATE OR REPLACE FUNCTION public.sppoultryeggclasses_get(p_farmid text, p_includeinactive boolean DEFAULT FALSE)
RETURNS TABLE (poultryproductid integer, eggsizeid integer, name text, classkind text,
               sortorder integer, isactive boolean, onhand numeric)
LANGUAGE sql
STABLE
AS $function$
    WITH u AS (
        SELECT pp.poultryproductid
        FROM   poultryproducts pp
        WHERE  pp.farmid = p_farmid AND (pp.israweggproduct = TRUE OR pp.name IN ('Eggs', 'Chicken Eggs'))
        ORDER  BY pp.israweggproduct DESC, pp.poultryproductid
        LIMIT  1
    )
    SELECT u.poultryproductid, NULL::integer, 'Unsorted / General'::text, 'Unsorted'::text, 0, TRUE,
           COALESCE((SELECT SUM(t.quantity) FROM poultrystocktransactions t
                     WHERE t.farmid = p_farmid AND t.poultryproductid = u.poultryproductid), 0)::numeric(18,3)
    FROM   u
    UNION ALL
    SELECT s.poultryproductid, s.eggsizeid, s.name::text, 'Size'::text, s.sortorder, s.isactive,
           COALESCE((SELECT SUM(t.quantity) FROM poultrystocktransactions t
                     WHERE t.farmid = p_farmid AND t.poultryproductid = s.poultryproductid), 0)::numeric(18,3)
    FROM   poultryeggsizes s
    WHERE  s.farmid = p_farmid AND (p_includeinactive OR s.isactive)
    ORDER  BY 5, 3;
$function$;

-- -----------------------------------------------------------------------------
-- 3. Crate conversion: a sorted size is counted in eggs too, 30 to the crate,
--    exactly like the raw-egg product (internal use, driver loading).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fnpoultrycrateunits(p_poultryproductid integer, p_eggspercrate integer)
RETURNS integer
LANGUAGE sql
STABLE
AS $function$
    -- Eggs are the only products whose ledger unit differs from the crate the
    -- driver module counts in -- the raw-egg (Unsorted) product and, since 341,
    -- every sorted egg size. Birds and other finished goods convert 1:1.
    SELECT CASE
             WHEN EXISTS (SELECT 1 FROM poultryproducts p
                          WHERE p.poultryproductid = p_poultryproductid
                            AND COALESCE(p.israweggproduct, FALSE) = TRUE)
               OR EXISTS (SELECT 1 FROM poultryeggsizes s
                          WHERE s.poultryproductid = p_poultryproductid)
             THEN GREATEST(COALESCE(p_eggspercrate, 30), 1)
             ELSE 1
           END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Egg sales by class
-- -----------------------------------------------------------------------------
ALTER TABLE public.sale ADD COLUMN IF NOT EXISTS poultryproductid integer;
ALTER TABLE public.sale ADD COLUMN IF NOT EXISTS salegroupno text;
CREATE INDEX IF NOT EXISTS ix_sale_farm_group ON public.sale (farmid, salegroupno) WHERE salegroupno IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sppoultryeggstock_syncforsale(p_farmid text, p_saleid integer, p_qtysold numeric, p_createdby text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_egg   integer;
    v_class integer;
BEGIN
    -- Idempotent: drop any prior egg-sale movement for this sale (whatever
    -- class it was in -- a sale moved from Unsorted to Large loses its Unsorted
    -- row here and gains a Large one below).
    DELETE FROM poultrystocktransactions t
    WHERE t.farmid = p_farmid AND t.txntype = 'Sale' AND t.relatedid = p_saleid;

    IF (COALESCE(p_qtysold, 0) <= 0) THEN RETURN; END IF;

    -- Sales generated by a driver return / delivery move no stock of their own:
    -- the eggs left as 'Driver Load Out' and came back as 'Driver Return In'.
    IF EXISTS (SELECT 1 FROM sale s
               WHERE s.saleid = p_saleid AND s.farmid = p_farmid
                 AND (s.saledescription ILIKE 'Driver return #%' OR s.saledescription ILIKE 'Delivery #%')) THEN
        RETURN;
    END IF;

    -- 341: the class the sale says it sold. NULL (every sale before 341, and
    -- every sale that does not pick a size) is Unsorted / General.
    SELECT s.poultryproductid INTO v_class
    FROM   sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid;

    IF v_class IS NOT NULL AND public.fnpoultry_iseggclass(p_farmid, v_class) THEN
        v_egg := v_class;
    ELSE
        v_egg := public.fnpoultry_unsortedeggproduct(p_farmid);
    END IF;

    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby)
    VALUES (p_farmid, v_egg, 'Sale', -(p_qtysold::numeric(14,3)), NULL, p_saleid, 'Egg sale', p_createdby);
END;
$function$;

-- Set (or clear) the egg class of a sale and its group number, then re-post
-- its egg movement against that class. NULL class = Unsorted / General.
CREATE OR REPLACE FUNCTION public.sppoultrysale_setegg(
    p_farmid text, p_saleid integer, p_poultryproductid integer DEFAULT NULL,
    p_salegroupno text DEFAULT NULL, p_by text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_product text;
    v_qty     numeric;
    v_class   integer := p_poultryproductid;
    v_size    text;
BEGIN
    SELECT s.product, s.quantity INTO v_product, v_qty
    FROM   sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sale #% does not belong to this company.', p_saleid;
    END IF;

    IF lower(COALESCE(v_product, '')) NOT LIKE '%egg%' THEN
        v_class := NULL;          -- a class only means something on an egg sale
    ELSIF v_class IS NOT NULL THEN
        IF NOT public.fnpoultry_iseggclass(p_farmid, v_class) THEN
            RAISE EXCEPTION 'That egg class does not belong to this company.';
        END IF;
        SELECT s.name INTO v_size FROM poultryeggsizes s
        WHERE  s.poultryproductid = v_class AND s.farmid = p_farmid;
        IF v_size IS NULL THEN
            v_class := NULL;      -- the Unsorted product itself: store as NULL
        END IF;
    END IF;

    UPDATE sale s
    SET    poultryproductid = v_class,
           -- A sale number, once given, is kept: an edit that does not send
           -- one must not split the line from its multi-size sale.
           salegroupno      = COALESCE(NULLIF(btrim(COALESCE(p_salegroupno, '')), ''), s.salegroupno),
           -- The size column predates classes and feeds the weekly report's
           -- "Egg sales by size"; keep it the class name so both agree.
           size             = CASE WHEN lower(COALESCE(v_product, '')) LIKE '%egg%' THEN v_size ELSE s.size END,
           dateupdated      = (now() at time zone 'utc')
    WHERE  s.saleid = p_saleid AND s.farmid = p_farmid;

    IF lower(COALESCE(v_product, '')) LIKE '%egg%' THEN
        PERFORM public.sppoultryeggstock_syncforsale(p_farmid, p_saleid, COALESCE(v_qty, 0), p_by);
    END IF;
END;
$function$;

-- Readers return the two new columns. RETURNS TABLE changes, so drop first.
DROP FUNCTION IF EXISTS public.spsale_getall(text);
CREATE FUNCTION public.spsale_getall(p_farmid text)
RETURNS TABLE(saleid integer, userid text, farmid text, saledate date, product text, quantity numeric,
              unitprice numeric, totalamount numeric, paymentmethod text, customername text, flockid integer,
              saledescription text, paid boolean, size text, poultrycashaccountid integer, amountpaid numeric,
              createddate timestamp without time zone, customerid integer,
              poultryproductid integer, salegroupno text)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.saleid, s.userid::text, s.farmid::text, s.saledate, s.product::text,
           s.quantity, s.unitprice, s.totalamount,
           s.paymentmethod::text, s.customername::text, s.flockid, s.saledescription::text,
           COALESCE(s.paid, TRUE) AS paid,
           s.size::text, s.poultrycashaccountid, COALESCE(s.amountpaid, 0) AS amountpaid,
           s.createddate, s.customerid,
           s.poultryproductid, s.salegroupno
    FROM sale s
    WHERE s.farmid = p_farmid
    ORDER BY s.saledate DESC, s.createddate DESC;
END;
$function$;

DROP FUNCTION IF EXISTS public.spsale_getbyid(integer, text);
CREATE FUNCTION public.spsale_getbyid(p_saleid integer, p_farmid text)
RETURNS TABLE(saleid integer, userid text, farmid text, saledate date, product text, quantity numeric,
              unitprice numeric, totalamount numeric, paymentmethod text, customername text, flockid integer,
              saledescription text, paid boolean, size text, poultrycashaccountid integer, amountpaid numeric,
              createddate timestamp without time zone, customerid integer,
              poultryproductid integer, salegroupno text)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT s.saleid, s.userid::text, s.farmid::text, s.saledate, s.product::text,
           s.quantity, s.unitprice, s.totalamount,
           s.paymentmethod::text, s.customername::text, s.flockid, s.saledescription::text,
           COALESCE(s.paid, TRUE) AS paid,
           s.size::text, s.poultrycashaccountid, COALESCE(s.amountpaid, 0) AS amountpaid,
           s.createddate, s.customerid,
           s.poultryproductid, s.salegroupno
    FROM sale s
    WHERE s.saleid = p_saleid AND s.farmid = p_farmid;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5. One production record per flock per day
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tr_productionrecords_oneperday_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_flock text;
BEGIN
    IF NEW.flockid IS NULL THEN
        RETURN NEW;
    END IF;
    -- An edit that leaves the flock and the date alone is always allowed, so a
    -- pre-existing duplicate can still be corrected in place.
    IF TG_OP = 'UPDATE'
       AND NEW.flockid IS NOT DISTINCT FROM OLD.flockid
       AND NEW.date    IS NOT DISTINCT FROM OLD.date
       AND NEW.farmid  IS NOT DISTINCT FROM OLD.farmid THEN
        RETURN NEW;
    END IF;

    -- Two saves for the same flock-day at the same moment: the second waits
    -- here and then sees the first.
    PERFORM pg_advisory_xact_lock(hashtext('poultry-prodrec:' || NEW.farmid || ':' || NEW.flockid::text || ':' || NEW.date::text));

    IF EXISTS (SELECT 1 FROM productionrecords pr
               WHERE pr.farmid = NEW.farmid AND pr.flockid = NEW.flockid AND pr.date = NEW.date
                 AND pr.id IS DISTINCT FROM NEW.id) THEN
        SELECT f.name INTO v_flock FROM flock f WHERE f.flockid = NEW.flockid;
        RAISE EXCEPTION '% already has a production record for %. Edit that record instead of adding another one. To record egg sizes, use the Egg Sorting Workspace -- sorting never needs a second production record.',
            COALESCE(v_flock, 'This flock'), to_char(NEW.date, 'FMDD Mon YYYY')
            USING ERRCODE = 'P0010';
    END IF;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS tr_productionrecords_oneperday ON public.productionrecords;
CREATE TRIGGER tr_productionrecords_oneperday BEFORE INSERT OR UPDATE ON public.productionrecords
    FOR EACH ROW EXECUTE FUNCTION public.tr_productionrecords_oneperday_fn();

-- The duplicates that predate the rule, for a person to merge.
CREATE OR REPLACE FUNCTION public.sppoultryproduction_duplicates(p_farmid text)
RETURNS TABLE (flockid integer, flockname text, productiondate date, recordcount integer,
               recordids integer[], totaleggs bigint, grades text)
LANGUAGE sql
STABLE
AS $function$
    SELECT pr.flockid, MAX(f.name)::text, pr.date, COUNT(*)::int,
           array_agg(pr.id ORDER BY pr.createdat, pr.id),
           SUM(COALESCE(pr.totalproduction, 0))::bigint,
           string_agg(DISTINCT pr.egggrade, ', ')
    FROM   productionrecords pr
    LEFT   JOIN flock f ON f.flockid = pr.flockid
    WHERE  pr.farmid = p_farmid AND pr.flockid IS NOT NULL
    GROUP  BY pr.flockid, pr.date
    HAVING COUNT(*) > 1
    ORDER  BY pr.date DESC, 2;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Permissions: poultry.egg-sorting
--   view    -- the workspace, sizes and composition reports
--   create  -- draft and post a sorting (the C# post route is checked as create)
--   edit    -- egg sizes and the sorting settings
--   delete  -- reverse a posted sorting / discard a draft
-- Carried over from poultry.egg-production (the legacy page's key), so whoever
-- could record egg sorting before can use the workspace now.
-- -----------------------------------------------------------------------------
DO $iam$
DECLARE
    v_keys integer := 0; v_roles integer := 0; v_users integer := 0;
BEGIN
    IF to_regclass('public.iampermissions') IS NULL THEN
        RAISE NOTICE '341: iampermissions not present, skipping catalog seed.';
        RETURN;
    END IF;

    INSERT INTO iampermissions (permissionkey, module, resource, action,
                                permissiongroup, resourcelabel, description,
                                companytype, isdangerous, sortorder)
    SELECT 'poultry.egg-sorting.' || a.action, 'poultry', 'egg-sorting', a.action,
           'Production', 'Egg Sorting Workspace',
           'Sorting collected eggs into sizes: turning unsorted egg stock into '
           || 'sized stock, recording sorting losses, and reversing a sorting. '
           || 'Edit covers the farm''s egg sizes and sorting settings.',
           'Poultry', a.action = 'delete', 12
    FROM (VALUES ('view'), ('create'), ('edit'), ('delete')) AS a(action)
    ON CONFLICT (permissionkey) DO NOTHING;
    GET DIAGNOSTICS v_keys = ROW_COUNT;

    IF to_regclass('public.iamrolepermissions') IS NOT NULL THEN
        INSERT INTO iamrolepermissions (roleid, permissionkey)
        SELECT rp.roleid, m.new_key
        FROM   iamrolepermissions rp
        JOIN   (VALUES ('poultry.egg-production.view',   'poultry.egg-sorting.view'),
                       ('poultry.egg-production.create', 'poultry.egg-sorting.create'),
                       ('poultry.egg-production.edit',   'poultry.egg-sorting.edit'),
                       ('poultry.egg-production.delete', 'poultry.egg-sorting.delete')
               ) AS m(old_key, new_key) ON m.old_key = rp.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
        ON CONFLICT (roleid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_roles = ROW_COUNT;
    END IF;

    IF to_regclass('public.iamuserpermissions') IS NOT NULL THEN
        INSERT INTO iamuserpermissions (userid, farmid, permissionkey, effect, reason, grantedby, grantedat)
        SELECT up.userid, up.farmid, m.new_key, up.effect,
               'Carried over from ' || up.permissionkey || ' by migration 341',
               up.grantedby, (now() at time zone 'utc')
        FROM   iamuserpermissions up
        JOIN   (VALUES ('poultry.egg-production.view',   'poultry.egg-sorting.view'),
                       ('poultry.egg-production.create', 'poultry.egg-sorting.create'),
                       ('poultry.egg-production.edit',   'poultry.egg-sorting.edit'),
                       ('poultry.egg-production.delete', 'poultry.egg-sorting.delete')
               ) AS m(old_key, new_key) ON m.old_key = up.permissionkey
        WHERE  EXISTS (SELECT 1 FROM iampermissions p WHERE p.permissionkey = m.new_key)
          AND  (up.expiresat IS NULL OR up.expiresat > (now() at time zone 'utc'))
        ON CONFLICT (userid, farmid, permissionkey) DO NOTHING;
        GET DIAGNOSTICS v_users = ROW_COUNT;
    END IF;

    RAISE NOTICE '341: % catalog key(s), % role grant(s), % user grant(s) added.', v_keys, v_roles, v_users;
END;
$iam$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification. Every fixture is rolled back by the sentinel at the end.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    a   text := '44444444-3333-4333-8333-000000000341';
    b   text := '55555555-3333-4333-8333-000000000341';
    d   date := date '2026-03-10';
    who text := '__341__';
    f1 integer; f2 integer; fb integer;
    r1 integer; r2 integer;
    unsorted integer; large integer; medium integer; blarge integer;
    s1 integer; s2 integer;
    v_n numeric;
BEGIN
    BEGIN
        INSERT INTO farms (id, farmid, name, email, type, timezoneid)
        VALUES (a, a, 'Selftest A', 'a@selftest.invalid', 'Poultry', 'UTC'),
               (b, b, 'Selftest B', 'b@selftest.invalid', 'Poultry', 'UTC');
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'F1', d - 200, 'Brown', 1000, TRUE, TRUE, -341, timestamp '2026-01-01') RETURNING flockid INTO f1;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'F2', d - 200, 'Brown', 1000, TRUE, TRUE, -341, timestamp '2026-01-01') RETURNING flockid INTO f2;
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, b, 'FB', d - 200, 'Brown', 1000, TRUE, TRUE, -341, timestamp '2026-01-01') RETURNING flockid INTO fb;

        -- ---- One production record per flock per day -------------------------
        r1 := public.spproductionrecord_insert(a, who, who, 28, 196, d, 1000, 0, 1000, 0, NULL,
                                               500, 600, 610, 1710, f1, 0);
        IF (SELECT COALESCE(SUM(quantity), 0) FROM poultrystocktransactions
            WHERE farmid = a AND txntype = 'Production' AND relatedid = r1) <> 1710 THEN
            RAISE EXCEPTION '341: production should post 1,710 unsorted eggs.';
        END IF;
        BEGIN
            PERFORM public.spproductionrecord_insert(a, who, who, 28, 196, d, 1000, 0, 1000, 0, NULL,
                                                     10, 0, 0, 10, f1, 0);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '341: a second record for the same flock-day was accepted.';
        EXCEPTION WHEN SQLSTATE 'P0010' THEN NULL;
        END;
        BEGIN
            PERFORM public.speggproduction_insert(f1, d, 30, 30, 0, 0, 0, NULL, NULL, who, a, 'Large');
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '341: the legacy egg page created a per-grade duplicate.';
        EXCEPTION WHEN SQLSTATE 'P0010' THEN NULL;
        END;
        r2 := public.spproductionrecord_insert(a, who, who, 28, 196, d + 1, 1000, 0, 1000, 0, NULL,
                                               100, 0, 0, 100, f1, 0);
        BEGIN
            UPDATE productionrecords SET date = d WHERE id = r2;
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '341: moving a record onto an occupied day was accepted.';
        EXCEPTION WHEN SQLSTATE 'P0010' THEN NULL;
        END;
        -- Same flock, other day and other flock same day are fine; so is an edit in place.
        PERFORM public.spproductionrecord_insert(a, who, who, 28, 196, d, 1000, 0, 1000, 0, NULL, 5, 0, 0, 5, f2, 0);
        UPDATE productionrecords SET notes = 'edited' WHERE id = r1;
        -- Another company's identical flock-day is not a duplicate.
        PERFORM public.spproductionrecord_insert(b, who, who, 28, 196, d, 1000, 0, 1000, 0, NULL, 5, 0, 0, 5, fb, 0);

        -- ---- Sizes ------------------------------------------------------------
        IF public.sppoultryeggsizes_ensure(a, who) <> 8 OR public.sppoultryeggsizes_ensure(a, who) <> 0 THEN
            RAISE EXCEPTION '341: seeding should add 8 sizes once.';
        END IF;
        unsorted := public.fnpoultry_unsortedeggproduct(a);
        SELECT poultryproductid INTO large  FROM poultryeggsizes WHERE farmid = a AND name = 'Large';
        SELECT poultryproductid INTO medium FROM poultryeggsizes WHERE farmid = a AND name = 'Medium';
        IF large IS NULL OR large = unsorted
           OR (SELECT israweggproduct FROM poultryproducts WHERE poultryproductid = large) THEN
            RAISE EXCEPTION '341: Large must be its own, non-raw product.';
        END IF;
        -- Production still finds Unsorted, never a size.
        IF (SELECT poultryproductid FROM poultrystocktransactions WHERE relatedid = r1 AND txntype = 'Production' LIMIT 1) <> unsorted THEN
            RAISE EXCEPTION '341: production posted somewhere other than Unsorted.';
        END IF;
        IF public.fnpoultrycrateunits(large, 30) <> 30 OR public.fnpoultrycrateunits(unsorted, 30) <> 30 THEN
            RAISE EXCEPTION '341: sized eggs must convert 30 to the crate.';
        END IF;
        IF (SELECT count(*) FROM public.sppoultryeggclasses_get(a)) <> 9
           OR (SELECT classkind FROM public.sppoultryeggclasses_get(a) LIMIT 1) <> 'Unsorted' THEN
            RAISE EXCEPTION '341: classes should be Unsorted + 8 sizes, Unsorted first.';
        END IF;
        BEGIN
            PERFORM public.sppoultryeggsize_save(a, NULL, 'large', NULL, TRUE, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '341: a duplicate size name was accepted.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        BEGIN
            DELETE FROM poultryeggsizes WHERE farmid = a AND name = 'Mixed';
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '341: a size was deleted.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- ---- Sales by class ---------------------------------------------------
        -- Unsorted now holds r1 1,710 + r2 100 + F2's 5 = 1,815.
        s1 := public.spsale_insert(who, a, d::timestamp, 'Fresh Eggs', 300, 20, 200, 'Cash', 'Market Woman A');
        IF (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = unsorted) <> 1515 THEN
            RAISE EXCEPTION '341: an unclassified egg sale should come out of Unsorted.';
        END IF;
        PERFORM public.sppoultrysale_setegg(a, s1, large, 'SG-1', who);
        IF (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = unsorted) <> 1815
           OR (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = large) <> -300
           OR (SELECT size FROM sale WHERE saleid = s1) <> 'Large' THEN
            RAISE EXCEPTION '341: a Large sale must deduct Large, not Unsorted.';
        END IF;
        -- Editing the sale (spsale_update) keeps its class.
        PERFORM public.spsale_update(who, a, s1, d::timestamp, 'Fresh Eggs', 240, 20, 160, 'Cash', 'Market Woman A');
        IF (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = large) <> -240 THEN
            RAISE EXCEPTION '341: an edited Large sale should still deduct Large.';
        END IF;
        s2 := public.spsale_insert(who, a, d::timestamp, 'Fresh Eggs', 150, 18, 90, 'Cash', 'Market Woman A');
        PERFORM public.sppoultrysale_setegg(a, s2, medium, 'SG-1', who);
        -- Deleting restores the SAME class.
        PERFORM public.spsale_delete(a, who, s1);
        IF (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = large) <> 0
           OR (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = medium) <> -150
           OR (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = unsorted) <> 1815 THEN
            RAISE EXCEPTION '341: deleting a Large sale must restore Large only.';
        END IF;
        -- Isolation: another company's size cannot be sold here.
        PERFORM public.sppoultryeggsizes_ensure(b, who);
        SELECT poultryproductid INTO blarge FROM poultryeggsizes WHERE farmid = b AND name = 'Large';
        BEGIN
            PERFORM public.sppoultrysale_setegg(a, s2, blarge, NULL, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '341: sold another company''s egg size.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        -- A non-egg sale ignores a class.
        s1 := public.spsale_insert(who, a, d::timestamp, 'Manure', 2, 10, 20, 'Cash', NULL);
        PERFORM public.sppoultrysale_setegg(a, s1, large, NULL, who);
        IF (SELECT poultryproductid FROM sale WHERE saleid = s1) IS NOT NULL THEN
            RAISE EXCEPTION '341: a manure sale took an egg class.';
        END IF;

        -- ---- Duplicates report -----------------------------------------------
        IF EXISTS (SELECT 1 FROM public.sppoultryproduction_duplicates(a)) THEN
            RAISE EXCEPTION '341: no duplicates should exist in the fixture.';
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '__341_ok__';
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
        NULL;
    END;

    RAISE NOTICE '341_PoultryEggClasses: verified (one record per flock-day incl. legacy egg page, move refused, edit in place, isolation; sizes seeded once, own products, crate units, classes; sales deduct their class, edit keeps it, delete restores it, foreign size refused, non-egg ignored).';
END $$;
