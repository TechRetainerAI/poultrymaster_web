-- =============================================================================
-- 344_PoultryEggSortingCompletion.postgres.sql        (requires 341, 342, 343)
--
-- Purpose
-- -------
-- The five pieces the first Egg Sorting build left out:
--
--   1. PRICE PER SIZE. A selling price per crate on each egg size and on
--      Unsorted / General, offered as the default price on the Sales page.
--      NOT poultryproducts.unitprice: migration 218 made that column the COST
--      internal use charges, and a selling price there would turn every
--      internal use of eggs into a charge at retail.
--   2. EGGS PER CRATE. A per-farm setting (default 30, 1..100). Read by
--      fnpoultry_eggspercrate(farmid); internal use costing uses it instead
--      of a literal 30, and the app reads it for every crate <-> egg entry.
--   3. AUDIT. poultryeggsortingaudit records, by trigger, every sorting draft
--      created / edited / discarded, posted (with its lines and source picks),
--      reversed (with the reason); every size added, renamed, re-priced or
--      switched off; every settings change; every change of a sale's egg
--      class; every class adjustment below. The actor comes from the row
--      (createdby / postedby / ...) or, where the row has none, from the
--      transaction setting poultry.actor that the calling function sets.
--   4. MISSING ACTIVITY. sppoultryactivity_unsortedeggs: production from
--      EARLIER days that is still unsorted -- never today's (sorting in the
--      evening or next morning is normal). Only when sorting is on and the
--      farm's Daily Closing policy is not Off. Capped by what Unsorted still
--      holds, newest production first: eggs sold unsorted are assumed to have
--      been the oldest, so they are not reported as waiting.
--   5. LOSSES AND ADJUSTMENTS BY CLASS. sppoultryeggclass_adjust posts a
--      ledger row against ONE class: breakage / loss (out, txntype 'Egg Loss')
--      or a stock-take correction (either way, 'Adjustment'). A reason is
--      required and a class cannot be driven below zero. This is not sorting
--      loss, which stays on the sorting session.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1 + 2. Columns
-- -----------------------------------------------------------------------------
ALTER TABLE public.poultryeggsizes ADD COLUMN IF NOT EXISTS pricepercrate numeric(14,2)
    CHECK (pricepercrate IS NULL OR pricepercrate >= 0);
ALTER TABLE public.poultryeggsortingsettings ADD COLUMN IF NOT EXISTS unsortedpricepercrate numeric(14,2)
    CHECK (unsortedpricepercrate IS NULL OR unsortedpricepercrate >= 0);
ALTER TABLE public.poultryeggsortingsettings ADD COLUMN IF NOT EXISTS eggspercrate integer NOT NULL DEFAULT 30;
DO $c$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_poultryeggsortingsettings_eggspercrate') THEN
        ALTER TABLE public.poultryeggsortingsettings
            ADD CONSTRAINT ck_poultryeggsortingsettings_eggspercrate CHECK (eggspercrate BETWEEN 1 AND 100);
    END IF;
END;
$c$;

CREATE OR REPLACE FUNCTION public.fnpoultry_eggspercrate(p_farmid text)
RETURNS integer
LANGUAGE sql
STABLE
AS $function$
    SELECT COALESCE((SELECT s.eggspercrate FROM poultryeggsortingsettings s WHERE s.farmid = p_farmid), 30);
$function$;

-- Settings reader gains the new columns (RETURNS TABLE changes: drop first).
DROP FUNCTION IF EXISTS public.sppoultryeggsortingsettings_get(text);
CREATE FUNCTION public.sppoultryeggsortingsettings_get(p_farmid text)
RETURNS TABLE (farmid text, enableeggsorting boolean, closingpolicy text, iscustomised boolean,
               updatedby text, updatedatutc timestamptz, eggspercrate integer, unsortedpricepercrate numeric)
LANGUAGE sql
STABLE
AS $function$
    SELECT p_farmid,
           COALESCE(s.enableeggsorting, FALSE),
           COALESCE(s.closingpolicy, 'Warning'),
           s.farmid IS NOT NULL,
           s.updatedby,
           s.updatedatutc,
           COALESCE(s.eggspercrate, 30),
           s.unsortedpricepercrate
    FROM   (SELECT 1) one
    LEFT   JOIN poultryeggsortingsettings s ON s.farmid = p_farmid;
$function$;

-- One call for every setting. The 343 _set stays for older callers.
CREATE OR REPLACE FUNCTION public.sppoultryeggsortingsettings_save(
    p_farmid text, p_enableeggsorting boolean, p_closingpolicy text, p_eggspercrate integer,
    p_unsortedpricepercrate numeric, p_by text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF COALESCE(p_closingpolicy, 'Warning') NOT IN ('Off', 'Warning', 'Blocking') THEN
        RAISE EXCEPTION 'Daily Closing can treat unsorted eggs as Off, Warning or Blocking.';
    END IF;
    IF COALESCE(p_eggspercrate, 30) NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION 'Eggs per crate must be between 1 and 100.';
    END IF;
    IF p_unsortedpricepercrate IS NOT NULL AND p_unsortedpricepercrate < 0 THEN
        RAISE EXCEPTION 'A price cannot be negative.';
    END IF;
    INSERT INTO poultryeggsortingsettings
        (farmid, enableeggsorting, closingpolicy, eggspercrate, unsortedpricepercrate, updatedby, updatedatutc)
    VALUES (p_farmid, COALESCE(p_enableeggsorting, FALSE), COALESCE(p_closingpolicy, 'Warning'),
            COALESCE(p_eggspercrate, 30), p_unsortedpricepercrate, p_by, now())
    ON CONFLICT (farmid) DO UPDATE
    SET enableeggsorting = EXCLUDED.enableeggsorting, closingpolicy = EXCLUDED.closingpolicy,
        eggspercrate = EXCLUDED.eggspercrate, unsortedpricepercrate = EXCLUDED.unsortedpricepercrate,
        updatedby = EXCLUDED.updatedby, updatedatutc = now();

    IF COALESCE(p_enableeggsorting, FALSE) THEN
        PERFORM public.sppoultryeggsizes_ensure(p_farmid, p_by);
    END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.sppoultryeggsize_setprice(
    p_farmid text, p_eggsizeid integer, p_pricepercrate numeric, p_by text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_pricepercrate IS NOT NULL AND p_pricepercrate < 0 THEN
        RAISE EXCEPTION 'A price cannot be negative.';
    END IF;
    PERFORM set_config('poultry.actor', COALESCE(p_by, ''), TRUE);
    UPDATE poultryeggsizes s SET pricepercrate = p_pricepercrate, updatedatutc = now()
    WHERE  s.eggsizeid = p_eggsizeid AND s.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Egg size % not found for this company.', p_eggsizeid;
    END IF;
END;
$function$;

-- Classes now carry their default selling price. RETURNS TABLE changes.
DROP FUNCTION IF EXISTS public.sppoultryeggclasses_get(text, boolean);
CREATE FUNCTION public.sppoultryeggclasses_get(p_farmid text, p_includeinactive boolean DEFAULT FALSE)
RETURNS TABLE (poultryproductid integer, eggsizeid integer, name text, classkind text,
               sortorder integer, isactive boolean, onhand numeric, pricepercrate numeric)
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
                     WHERE t.farmid = p_farmid AND t.poultryproductid = u.poultryproductid), 0)::numeric(18,3),
           (SELECT s.unsortedpricepercrate FROM poultryeggsortingsettings s WHERE s.farmid = p_farmid)
    FROM   u
    UNION ALL
    SELECT s.poultryproductid, s.eggsizeid, s.name::text, 'Size'::text, s.sortorder, s.isactive,
           COALESCE((SELECT SUM(t.quantity) FROM poultrystocktransactions t
                     WHERE t.farmid = p_farmid AND t.poultryproductid = s.poultryproductid), 0)::numeric(18,3),
           s.pricepercrate
    FROM   poultryeggsizes s
    WHERE  s.farmid = p_farmid AND (p_includeinactive OR s.isactive)
    ORDER  BY 5, 3;
$function$;

-- Internal use: blank costs scaled into crates by the farm's crate, not 30.
DO $patch$
DECLARE
    v_def text;
    v_old text := 'public.fnpoultryproductentrycost(p_farmid, i.poultryproductid, i.entryunit, 30)';
    v_new text := 'public.fnpoultryproductentrycost(p_farmid, i.poultryproductid, i.entryunit, public.fnpoultry_eggspercrate(p_farmid))';
BEGIN
    SELECT pg_get_functiondef('public.sppoultryinternalusage_post(integer,text,text)'::regprocedure) INTO v_def;
    IF position(v_new IN v_def) > 0 THEN
        RAISE NOTICE '344: internal use already reads the farm''s eggs per crate.';
    ELSIF position(v_old IN v_def) = 0 THEN
        RAISE EXCEPTION '344: sppoultryinternalusage_post no longer contains the expected crate cost call; patch it by hand.';
    ELSE
        EXECUTE replace(v_def, v_old, v_new);
        RAISE NOTICE '344: internal use now reads the farm''s eggs per crate.';
    END IF;
END;
$patch$;

-- -----------------------------------------------------------------------------
-- 3. Audit
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.poultryeggsortingaudit (
    auditid       bigserial   PRIMARY KEY,
    farmid        text        NOT NULL,
    entity        text        NOT NULL,     -- Sorting | EggSize | Settings | Sale | Adjustment
    entityid      integer,
    action        text        NOT NULL,
    actor         text,
    details       jsonb,
    atutc         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_poultryeggsortingaudit_farm ON public.poultryeggsortingaudit (farmid, atutc DESC);
CREATE INDEX IF NOT EXISTS ix_poultryeggsortingaudit_entity ON public.poultryeggsortingaudit (entity, entityid);

CREATE OR REPLACE FUNCTION public.trg_poultryeggsortingaudit_noedit()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    RAISE EXCEPTION 'The egg sorting audit trail cannot be changed or deleted.';
END;
$function$;
DROP TRIGGER IF EXISTS trg_poultryeggsortingaudit_noedit ON public.poultryeggsortingaudit;
CREATE TRIGGER trg_poultryeggsortingaudit_noedit BEFORE UPDATE OR DELETE ON public.poultryeggsortingaudit
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryeggsortingaudit_noedit();

-- Who did it, for rows that do not carry the person themselves: the
-- transaction's poultry.actor (set by the calling function), else p_fallback.
-- Rows that DO carry a person (postedby, updatedby ...) use that first.
CREATE OR REPLACE FUNCTION public.fnpoultryeggaudit_actor(p_fallback text)
RETURNS text LANGUAGE sql STABLE AS $function$
    SELECT COALESCE(NULLIF(current_setting('poultry.actor', TRUE), ''), p_fallback);
$function$;

CREATE OR REPLACE FUNCTION public.trg_poultryeggsorting_audit_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_action text;
    v_actor  text;
    v_det    jsonb;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_action := 'DraftCreated';
        v_actor  := COALESCE(NEW.createdby, public.fnpoultryeggaudit_actor(NULL));
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO poultryeggsortingaudit (farmid, entity, entityid, action, actor, details)
        VALUES (OLD.farmid, 'Sorting', OLD.sessionid, 'DraftDiscarded', public.fnpoultryeggaudit_actor(NULL),
                jsonb_build_object('sessionNo', OLD.sessionno, 'input', OLD.inputquantity));
        RETURN OLD;
    ELSIF NEW.status = 'Posted' AND OLD.status = 'Draft' THEN
        v_action := 'Posted';
        v_actor  := COALESCE(NEW.postedby, public.fnpoultryeggaudit_actor(NULL));
    ELSIF NEW.status = 'Reversed' AND OLD.status = 'Posted' THEN
        v_action := 'Reversed';
        v_actor  := COALESCE(NEW.reversedby, public.fnpoultryeggaudit_actor(NULL));
    ELSIF NEW.status = 'Draft' AND (NEW.inputquantity, NEW.outputquantity, NEW.lossquantity, NEW.sortingdate, NEW.scoperecordids, COALESCE(NEW.notes, ''))
                                 IS DISTINCT FROM (OLD.inputquantity, OLD.outputquantity, OLD.lossquantity, OLD.sortingdate, OLD.scoperecordids, COALESCE(OLD.notes, '')) THEN
        v_action := 'DraftEdited';
        v_actor  := public.fnpoultryeggaudit_actor(NEW.createdby);
    ELSE
        RETURN NEW;
    END IF;

    v_det := jsonb_build_object(
        'sessionNo', NEW.sessionno, 'mode', NEW.sortingmode, 'flockId', NEW.flockid,
        'pickNumber', NEW.picknumber, 'records', to_jsonb(NEW.scoperecordids), 'sortingDate', NEW.sortingdate,
        'input', NEW.inputquantity, 'sized', NEW.outputquantity, 'loss', NEW.lossquantity);
    IF v_action IN ('Posted', 'Reversed') THEN
        v_det := v_det
            || jsonb_build_object('lines', (SELECT jsonb_agg(jsonb_build_object('type', l.linetype, 'size', z.name, 'qty', l.quantity) ORDER BY l.lineid)
                                            FROM poultryeggsortinglines l LEFT JOIN poultryeggsizes z ON z.eggsizeid = l.eggsizeid
                                            WHERE l.sessionid = NEW.sessionid))
            || jsonb_build_object('sources', (SELECT jsonb_agg(jsonb_build_object('record', s.productionrecordid, 'pick', s.picknumber,
                                                                                   'productionDate', s.productiondate, 'qty', s.quantity) ORDER BY s.sourceid)
                                              FROM poultryeggsortingsources s WHERE s.sessionid = NEW.sessionid));
    END IF;
    IF v_action = 'Reversed' THEN
        v_det := v_det || jsonb_build_object('reason', NEW.reversalreason);
    END IF;

    INSERT INTO poultryeggsortingaudit (farmid, entity, entityid, action, actor, details)
    VALUES (NEW.farmid, 'Sorting', NEW.sessionid, v_action, v_actor, v_det);
    RETURN NEW;
END;
$function$;

-- AFTER: a Posted row's sources exist by the time the header turns Posted
-- (post inserts sources first, then updates the header).
DROP TRIGGER IF EXISTS trg_poultryeggsorting_audit ON public.poultryeggsortingsessions;
CREATE TRIGGER trg_poultryeggsorting_audit AFTER INSERT OR UPDATE ON public.poultryeggsortingsessions
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryeggsorting_audit_fn();
-- Discarding is a delete; BEFORE so the row is still readable.
DROP TRIGGER IF EXISTS trg_poultryeggsorting_audit_del ON public.poultryeggsortingsessions;
CREATE TRIGGER trg_poultryeggsorting_audit_del BEFORE DELETE ON public.poultryeggsortingsessions
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryeggsorting_audit_fn();

CREATE OR REPLACE FUNCTION public.trg_poultryeggsizes_audit_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_changes jsonb := '{}'::jsonb;
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO poultryeggsortingaudit (farmid, entity, entityid, action, actor, details)
        VALUES (NEW.farmid, 'EggSize', NEW.eggsizeid, 'SizeAdded', COALESCE(NEW.createdby, public.fnpoultryeggaudit_actor(NULL)),
                jsonb_build_object('name', NEW.name, 'price', NEW.pricepercrate));
        RETURN NEW;
    END IF;
    IF NEW.name IS DISTINCT FROM OLD.name THEN
        v_changes := v_changes || jsonb_build_object('name', jsonb_build_array(OLD.name, NEW.name));
    END IF;
    IF NEW.isactive IS DISTINCT FROM OLD.isactive THEN
        v_changes := v_changes || jsonb_build_object('active', jsonb_build_array(OLD.isactive, NEW.isactive));
    END IF;
    IF NEW.pricepercrate IS DISTINCT FROM OLD.pricepercrate THEN
        v_changes := v_changes || jsonb_build_object('pricePerCrate', jsonb_build_array(OLD.pricepercrate, NEW.pricepercrate));
    END IF;
    IF NEW.sortorder IS DISTINCT FROM OLD.sortorder THEN
        v_changes := v_changes || jsonb_build_object('order', jsonb_build_array(OLD.sortorder, NEW.sortorder));
    END IF;
    IF v_changes <> '{}'::jsonb THEN
        INSERT INTO poultryeggsortingaudit (farmid, entity, entityid, action, actor, details)
        VALUES (NEW.farmid, 'EggSize', NEW.eggsizeid, 'SizeChanged', public.fnpoultryeggaudit_actor(NULL),
                jsonb_build_object('name', NEW.name) || v_changes);
    END IF;
    RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS trg_poultryeggsizes_audit ON public.poultryeggsizes;
CREATE TRIGGER trg_poultryeggsizes_audit AFTER INSERT OR UPDATE ON public.poultryeggsizes
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryeggsizes_audit_fn();

CREATE OR REPLACE FUNCTION public.trg_poultryeggsettings_audit_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF TG_OP = 'UPDATE'
       AND (NEW.enableeggsorting, NEW.closingpolicy, NEW.eggspercrate, NEW.unsortedpricepercrate)
           IS NOT DISTINCT FROM (OLD.enableeggsorting, OLD.closingpolicy, OLD.eggspercrate, OLD.unsortedpricepercrate) THEN
        RETURN NEW;
    END IF;
    INSERT INTO poultryeggsortingaudit (farmid, entity, entityid, action, actor, details)
    VALUES (NEW.farmid, 'Settings', NULL, 'SettingsChanged', COALESCE(NEW.updatedby, public.fnpoultryeggaudit_actor(NULL)),
            jsonb_build_object('enableEggSorting', NEW.enableeggsorting, 'closingPolicy', NEW.closingpolicy,
                               'eggsPerCrate', NEW.eggspercrate, 'unsortedPricePerCrate', NEW.unsortedpricepercrate)
            || CASE WHEN TG_OP = 'UPDATE' THEN jsonb_build_object('before', jsonb_build_object(
                    'enableEggSorting', OLD.enableeggsorting, 'closingPolicy', OLD.closingpolicy,
                    'eggsPerCrate', OLD.eggspercrate, 'unsortedPricePerCrate', OLD.unsortedpricepercrate))
                    ELSE '{}'::jsonb END);
    RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS trg_poultryeggsettings_audit ON public.poultryeggsortingsettings;
CREATE TRIGGER trg_poultryeggsettings_audit AFTER INSERT OR UPDATE ON public.poultryeggsortingsettings
    FOR EACH ROW EXECUTE FUNCTION public.trg_poultryeggsettings_audit_fn();

-- A sale's egg class: the sale ledger row is rewritten on every edit (syncforsale
-- is delete-and-reinsert), so this is where a class change leaves its trace.
CREATE OR REPLACE FUNCTION public.trg_sale_eggclass_audit_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.poultryproductid IS NOT DISTINCT FROM OLD.poultryproductid
       AND NEW.salegroupno IS NOT DISTINCT FROM OLD.salegroupno THEN
        RETURN NEW;
    END IF;
    INSERT INTO poultryeggsortingaudit (farmid, entity, entityid, action, actor, details)
    VALUES (NEW.farmid, 'Sale', NEW.saleid, 'SaleEggClassSet',
            public.fnpoultryeggaudit_actor(COALESCE(NEW.updatedby, NEW.createdby, NEW.userid)),
            jsonb_build_object(
                'from', COALESCE((SELECT z.name FROM poultryeggsizes z WHERE z.poultryproductid = OLD.poultryproductid), 'Unsorted / General'),
                'to',   COALESCE((SELECT z.name FROM poultryeggsizes z WHERE z.poultryproductid = NEW.poultryproductid), 'Unsorted / General'),
                'quantity', NEW.quantity, 'saleGroupNo', NEW.salegroupno, 'customer', NEW.customername));
    RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS trg_sale_eggclass_audit ON public.sale;
CREATE TRIGGER trg_sale_eggclass_audit AFTER UPDATE OF poultryproductid, salegroupno ON public.sale
    FOR EACH ROW EXECUTE FUNCTION public.trg_sale_eggclass_audit_fn();

-- Discard now records who discarded. New signature: drop the 342 one first so
-- a two-argument call is not ambiguous.
DROP FUNCTION IF EXISTS public.sppoultryeggsorting_discard(text, integer);
CREATE FUNCTION public.sppoultryeggsorting_discard(p_farmid text, p_sessionid integer, p_by text DEFAULT NULL)
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
    PERFORM set_config('poultry.actor', COALESCE(p_by, ''), TRUE);
    DELETE FROM poultryeggsortinglines WHERE sessionid = p_sessionid;
    DELETE FROM poultryeggsortingsessions WHERE sessionid = p_sessionid;
END;
$function$;

-- setegg (341) stamps who changed the class.
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
        v_class := NULL;
    ELSIF v_class IS NOT NULL THEN
        IF NOT public.fnpoultry_iseggclass(p_farmid, v_class) THEN
            RAISE EXCEPTION 'That egg class does not belong to this company.';
        END IF;
        SELECT s.name INTO v_size FROM poultryeggsizes s
        WHERE  s.poultryproductid = v_class AND s.farmid = p_farmid;
        IF v_size IS NULL THEN
            v_class := NULL;
        END IF;
    END IF;

    PERFORM set_config('poultry.actor', COALESCE(p_by, ''), TRUE);
    UPDATE sale s
    SET    poultryproductid = v_class,
           salegroupno      = COALESCE(NULLIF(btrim(COALESCE(p_salegroupno, '')), ''), s.salegroupno),
           size             = CASE WHEN lower(COALESCE(v_product, '')) LIKE '%egg%' THEN v_size ELSE s.size END,
           dateupdated      = (now() at time zone 'utc')
    WHERE  s.saleid = p_saleid AND s.farmid = p_farmid;

    IF lower(COALESCE(v_product, '')) LIKE '%egg%' THEN
        PERFORM public.sppoultryeggstock_syncforsale(p_farmid, p_saleid, COALESCE(v_qty, 0), p_by);
    END IF;
END;
$function$;

-- size_save (341) stamps who renamed or switched a size.
DO $patch2$
DECLARE
    v_def text;
    v_anchor text := 'v_pname := ''Eggs - '' || v_name;';
BEGIN
    SELECT pg_get_functiondef('public.sppoultryeggsize_save(text,integer,text,integer,boolean,text)'::regprocedure) INTO v_def;
    IF position('poultry.actor' IN v_def) = 0 THEN
        IF position(v_anchor IN v_def) = 0 THEN
            RAISE EXCEPTION '344: sppoultryeggsize_save changed shape; add the actor by hand.';
        END IF;
        EXECUTE replace(v_def, v_anchor,
                        'PERFORM set_config(''poultry.actor'', COALESCE(p_by, ''''), TRUE);' || E'\n    ' || v_anchor);
    END IF;
END;
$patch2$;

CREATE OR REPLACE FUNCTION public.sppoultryeggsorting_audit(
    p_farmid text, p_entity text DEFAULT NULL, p_entityid integer DEFAULT NULL, p_limit integer DEFAULT 200)
RETURNS TABLE (auditid bigint, entity text, entityid integer, action text, actor text, details text, atutc timestamptz)
LANGUAGE sql
STABLE
AS $function$
    SELECT a.auditid, a.entity, a.entityid, a.action, a.actor, a.details::text, a.atutc
    FROM   poultryeggsortingaudit a
    WHERE  a.farmid = p_farmid
      AND  (p_entity IS NULL OR a.entity = p_entity)
      AND  (p_entityid IS NULL OR a.entityid = p_entityid)
    ORDER  BY a.atutc DESC, a.auditid DESC
    LIMIT  LEAST(GREATEST(COALESCE(p_limit, 200), 1), 1000);
$function$;

-- -----------------------------------------------------------------------------
-- 5. Losses and adjustments against one class
-- -----------------------------------------------------------------------------
-- p_kind: Breakage | Loss (p_quantity = eggs lost, posted negative)
--         Stocktake | Correction (p_quantity signed: + found, - missing)
CREATE OR REPLACE FUNCTION public.sppoultryeggclass_adjust(
    p_farmid text, p_poultryproductid integer, p_kind text, p_quantity integer,
    p_reason text, p_by text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $function$
DECLARE
    v_delta   integer;
    v_onhand  numeric;
    v_name    text;
    v_type    text;
    v_id      integer;
BEGIN
    IF p_kind NOT IN ('Breakage', 'Loss', 'Stocktake', 'Correction') THEN
        RAISE EXCEPTION 'Choose breakage, loss, stock-take or correction.';
    END IF;
    IF btrim(COALESCE(p_reason, '')) = '' THEN
        RAISE EXCEPTION 'A reason is required for an egg adjustment.';
    END IF;
    IF COALESCE(p_quantity, 0) = 0 THEN
        RAISE EXCEPTION 'Enter how many eggs.';
    END IF;
    IF NOT public.fnpoultry_iseggclass(p_farmid, p_poultryproductid) THEN
        RAISE EXCEPTION 'That egg class does not belong to this company.';
    END IF;

    IF p_kind IN ('Breakage', 'Loss') THEN
        v_delta := -abs(p_quantity);
        v_type  := 'Egg Loss';
    ELSE
        v_delta := p_quantity;
        v_type  := 'Adjustment';
    END IF;

    -- Same lock as sorting: an adjustment and a sorting of the same eggs queue.
    PERFORM pg_advisory_xact_lock(hashtext('poultry-eggsort:' || p_farmid));
    SELECT COALESCE(SUM(t.quantity), 0) INTO v_onhand
    FROM   poultrystocktransactions t WHERE t.farmid = p_farmid AND t.poultryproductid = p_poultryproductid;
    SELECT COALESCE((SELECT z.name FROM poultryeggsizes z WHERE z.poultryproductid = p_poultryproductid), 'Unsorted / General')
    INTO   v_name;
    IF v_onhand + v_delta < 0 THEN
        RAISE EXCEPTION 'Only % % egg(s) are in stock, so % cannot be taken out.', trunc(v_onhand), v_name, -v_delta
            USING ERRCODE = 'P0003';
    END IF;

    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, unitcost, relatedid, note, createdby)
    VALUES (p_farmid, p_poultryproductid, v_type, v_delta, NULL, NULL,
            left(p_kind || ': ' || btrim(p_reason), 500), p_by)
    RETURNING poultrystocktransactionid INTO v_id;

    INSERT INTO poultryeggsortingaudit (farmid, entity, entityid, action, actor, details)
    VALUES (p_farmid, 'Adjustment', v_id, 'EggClassAdjusted', p_by,
            jsonb_build_object('class', v_name, 'kind', p_kind, 'quantity', v_delta,
                               'reason', btrim(p_reason), 'onHandBefore', v_onhand, 'onHandAfter', v_onhand + v_delta));
    RETURN v_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 4. Missing activity: earlier days' production still unsorted
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sppoultryactivity_unsortedeggs(
    p_farmid text, p_businessdate date DEFAULT NULL, p_windowdays integer DEFAULT 30)
RETURNS TABLE (productionrecordid integer, flockid integer, flockname text, batchname text, housename text,
               productiondate date, leftunsorted integer, daysoutstanding integer, severity text)
LANGUAGE plpgsql
STABLE
AS $function$
#variable_conflict use_column
DECLARE
    v_date   date := COALESCE(p_businessdate, public.fncompany_businessdate(p_farmid));
    v_on     boolean;
    v_policy text;
    v_onhand numeric;
    v_budget numeric;
    r        record;
BEGIN
    SELECT g.enableeggsorting, g.closingpolicy INTO v_on, v_policy
    FROM   public.sppoultryeggsortingsettings_get(p_farmid) g;
    IF NOT COALESCE(v_on, FALSE) OR v_policy = 'Off' THEN
        RETURN;
    END IF;

    SELECT COALESCE(SUM(c.onhand), 0) INTO v_onhand
    FROM   public.sppoultryeggclasses_get(p_farmid) c WHERE c.classkind = 'Unsorted';
    v_budget := GREATEST(v_onhand, 0);

    -- Newest first: what Unsorted still holds is most plausibly the newest
    -- production; older eggs went out unsorted first.
    FOR r IN
        SELECT d.* FROM (
            SELECT DISTINCT ON (x.productionrecordid)
                   x.productionrecordid AS rid, x.flockid AS fid, x.flockname AS fname, x.batchname AS bname,
                   x.housename AS hname, x.productiondate AS pdate, x.recordleft AS lft
            FROM   public.sppoultryeggsorting_picks(p_farmid, v_date - GREATEST(COALESCE(p_windowdays, 30), 1), v_date, NULL, NULL) x
            WHERE  x.recordleft > 0
            ORDER  BY x.productionrecordid
        ) d
        ORDER  BY d.pdate DESC, d.rid DESC
    LOOP
        EXIT WHEN v_budget <= 0;
        IF r.pdate < v_date THEN
            productionrecordid := r.rid;
            flockid            := r.fid;
            flockname          := r.fname;
            batchname          := r.bname;
            housename          := r.hname;
            productiondate     := r.pdate;
            leftunsorted       := LEAST(r.lft, trunc(v_budget))::int;
            daysoutstanding    := v_date - r.pdate;
            severity           := CASE WHEN v_date - r.pdate >= 3 THEN 'Critical' ELSE 'Warning' END;
            RETURN NEXT;
        END IF;
        -- Today's production uses up stock too, even though it is not reported.
        v_budget := v_budget - r.lft;
    END LOOP;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 6. Egg Stock Balance report: every egg class, not just Unsorted
-- -----------------------------------------------------------------------------
-- The live body (211) counts stock moves on the raw-egg product only. Since
-- 342, sorting moves eggs out of that product into sizes; counted on Unsorted
-- alone every sorting would read as eggs disappearing. Summed over ALL egg
-- classes, 'Sorting Out' + 'Sorting In' net to exactly the sorting loss, and
-- 'Egg Loss' / class adjustments land where they belong. Otherwise unchanged.
CREATE OR REPLACE FUNCTION public.sppoultryreport_eggstockbalance(p_farmid text, p_startdate date, p_enddate date)
RETURNS TABLE(openingproducedsaleable bigint, openingadjustments bigint, openingsales bigint, productionadded bigint,
              brokeninrange bigint, adjustmentsinrange bigint, salesinrange bigint, openingstockmoves bigint,
              stockmovesinrange bigint)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE((SELECT SUM(r.totalproduction::bigint
                             - (COALESCE(r.brokeneggs,0)+COALESCE(r.meatyeggs,0)+COALESCE(r.softeggs,0)+COALESCE(r.losteggs,0))::bigint)
                  FROM productionrecords r
                  WHERE r.farmid = p_farmid AND r.date < p_startdate), 0)::bigint            AS openingproducedsaleable,
        COALESCE((SELECT SUM(a.eggdelta) FROM egginventoryadjustment a
                  WHERE a.farmid = p_farmid AND a.adjustmentdate < p_startdate), 0)::bigint  AS openingadjustments,
        COALESCE((SELECT SUM(trunc(s.quantity)::bigint) FROM sale s
                  WHERE s.farmid = p_farmid AND s.product ILIKE '%egg%' AND s.saledate < p_startdate
                    AND NOT (COALESCE(s.saledescription,'') ILIKE 'Driver return #%'
                          OR COALESCE(s.saledescription,'') ILIKE 'Delivery #%')), 0)::bigint AS openingsales,
        COALESCE((SELECT SUM(r.totalproduction::bigint) FROM productionrecords r
                  WHERE r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate), 0)::bigint AS productionadded,
        COALESCE((SELECT SUM((COALESCE(r.brokeneggs,0)+COALESCE(r.meatyeggs,0)+COALESCE(r.softeggs,0)+COALESCE(r.losteggs,0))::bigint)
                  FROM productionrecords r
                  WHERE r.farmid = p_farmid AND r.date >= p_startdate AND r.date <= p_enddate), 0)::bigint AS brokeninrange,
        COALESCE((SELECT SUM(a.eggdelta) FROM egginventoryadjustment a
                  WHERE a.farmid = p_farmid AND a.adjustmentdate >= p_startdate AND a.adjustmentdate < (p_enddate + 1)), 0)::bigint AS adjustmentsinrange,
        COALESCE((SELECT SUM(trunc(s.quantity)::bigint) FROM sale s
                  WHERE s.farmid = p_farmid AND s.product ILIKE '%egg%'
                    AND s.saledate >= p_startdate AND s.saledate < (p_enddate + 1)
                    AND NOT (COALESCE(s.saledescription,'') ILIKE 'Driver return #%'
                          OR COALESCE(s.saledescription,'') ILIKE 'Delivery #%')), 0)::bigint AS salesinrange,
        COALESCE((SELECT SUM(trunc(t.quantity)::bigint)
                  FROM poultrystocktransactions t
                  WHERE t.farmid = p_farmid
                    AND public.fnpoultry_iseggclass(p_farmid, t.poultryproductid)
                    AND t.txntype NOT IN ('Production','Sale')
                    AND t.createddate < p_startdate), 0)::bigint AS openingstockmoves,
        COALESCE((SELECT SUM(trunc(t.quantity)::bigint)
                  FROM poultrystocktransactions t
                  WHERE t.farmid = p_farmid
                    AND public.fnpoultry_iseggclass(p_farmid, t.poultryproductid)
                    AND t.txntype NOT IN ('Production','Sale')
                    AND t.createddate >= p_startdate AND t.createddate < (p_enddate + 1)), 0)::bigint AS stockmovesinrange;
END
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification. Every fixture is rolled back by the sentinel at the end.
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    a   text := '44444444-3333-4333-8333-000000000344';
    d   date := current_date - 4;
    who text := '__344__';
    f1 integer; r1 integer; r2 integer; r3 integer;
    zl integer; lg integer; un integer;
    s1 integer; s2 integer; sale1 integer; adj integer;
    v_n integer;
BEGIN
    BEGIN
        INSERT INTO farms (id, farmid, name, email, type, timezoneid)
        VALUES (a, a, 'Selftest A', 'a@selftest.invalid', 'Poultry', 'UTC');
        INSERT INTO flock (userid, farmid, name, startdate, breed, quantity, active, hasarrived, batchid, createdat)
        VALUES (who, a, 'Flock 3', d - 140, 'Brown', 2000, TRUE, TRUE, -344, timestamp '2026-01-01') RETURNING flockid INTO f1;

        -- Settings: crate size and Unsorted price; audit records both states.
        PERFORM public.sppoultryeggsortingsettings_save(a, TRUE, 'Warning', 24, 16, who);
        IF public.fnpoultry_eggspercrate(a) <> 24 OR public.fnpoultry_eggspercrate('no-such-farm') <> 30 THEN
            RAISE EXCEPTION '344: eggs per crate should be 24 here and 30 by default.';
        END IF;
        BEGIN
            PERFORM public.sppoultryeggsortingsettings_save(a, TRUE, 'Warning', 0, NULL, who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '344: a crate of 0 eggs was accepted.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        IF NOT EXISTS (SELECT 1 FROM poultryeggsortingaudit WHERE farmid = a AND action = 'SettingsChanged' AND actor = who) THEN
            RAISE EXCEPTION '344: settings change not audited.';
        END IF;
        IF (SELECT count(*) FROM poultryeggsortingaudit WHERE farmid = a AND action = 'SizeAdded') <> 8 THEN
            RAISE EXCEPTION '344: the seeded sizes should be audited.';
        END IF;

        -- Prices.
        SELECT eggsizeid, poultryproductid INTO zl, lg FROM poultryeggsizes WHERE farmid = a AND name = 'Large';
        PERFORM public.sppoultryeggsize_setprice(a, zl, 20, who);
        IF (SELECT pricepercrate FROM public.sppoultryeggclasses_get(a) WHERE eggsizeid = zl) <> 20
           OR (SELECT pricepercrate FROM public.sppoultryeggclasses_get(a) WHERE classkind = 'Unsorted') <> 16 THEN
            RAISE EXCEPTION '344: class prices should read back 20 (Large) and 16 (Unsorted).';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM poultryeggsortingaudit WHERE farmid = a AND action = 'SizeChanged' AND actor = who
                       AND details ? 'pricePerCrate') THEN
            RAISE EXCEPTION '344: price change not audited with its actor.';
        END IF;
        PERFORM public.sppoultryeggsize_save(a, zl, 'Large A', NULL, TRUE, 'renamer');
        IF NOT EXISTS (SELECT 1 FROM poultryeggsortingaudit WHERE farmid = a AND action = 'SizeChanged' AND actor = 'renamer') THEN
            RAISE EXCEPTION '344: rename not audited with its actor.';
        END IF;

        -- Sorting lifecycle audited.
        r1 := public.spproductionrecord_insert(a, who, who, 20, 140, d, 2000, 0, 2000, 0, NULL, 500, 0, 0, 500, f1, 0);
        s1 := public.sppoultryeggsorting_save(a, NULL, 'ByPick', d, ARRAY[r1], 1,
              json_build_array(json_build_object('lineType', 'SizedOutput', 'eggSizeId', zl, 'quantity', 300))::text, NULL, NULL, who);
        PERFORM public.sppoultryeggsorting_post(a, s1, who);
        IF NOT EXISTS (SELECT 1 FROM poultryeggsortingaudit WHERE entity = 'Sorting' AND entityid = s1 AND action = 'Posted'
                       AND jsonb_array_length(details->'sources') = 1 AND jsonb_array_length(details->'lines') = 1) THEN
            RAISE EXCEPTION '344: posting should be audited with its lines and source picks.';
        END IF;
        PERFORM public.sppoultryeggsorting_reverse(a, s1, 'counted twice', who);
        IF NOT EXISTS (SELECT 1 FROM poultryeggsortingaudit WHERE entity = 'Sorting' AND entityid = s1 AND action = 'Reversed'
                       AND details->>'reason' = 'counted twice') THEN
            RAISE EXCEPTION '344: reversal should be audited with its reason.';
        END IF;
        s2 := public.sppoultryeggsorting_save(a, NULL, 'ByPick', d, ARRAY[r1], 1, '[]', NULL, NULL, who);
        PERFORM public.sppoultryeggsorting_discard(a, s2, 'discarder');
        IF NOT EXISTS (SELECT 1 FROM poultryeggsortingaudit WHERE entity = 'Sorting' AND entityid = s2 AND action = 'DraftDiscarded' AND actor = 'discarder') THEN
            RAISE EXCEPTION '344: discarding should be audited with who did it.';
        END IF;
        BEGIN
            DELETE FROM poultryeggsortingaudit WHERE farmid = a;
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '344: the audit trail was deleted.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        -- Sale class change audited.
        PERFORM public.sppoultryeggsorting_post(a, public.sppoultryeggsorting_save(a, NULL, 'ByPick', d, ARRAY[r1], 1,
              json_build_array(json_build_object('lineType', 'SizedOutput', 'eggSizeId', zl, 'quantity', 400))::text, NULL, NULL, who), who);
        sale1 := public.spsale_insert(who, a, d::timestamp, 'Fresh Eggs', 48, 20, 40, 'Cash', 'Buyer');
        PERFORM public.sppoultrysale_setegg(a, sale1, lg, NULL, 'seller');
        IF NOT EXISTS (SELECT 1 FROM poultryeggsortingaudit WHERE entity = 'Sale' AND entityid = sale1 AND actor = 'seller'
                       AND details->>'to' = 'Large A') THEN
            RAISE EXCEPTION '344: the sale''s class change should be audited.';
        END IF;

        -- Stock balance report: sorting moves eggs between classes, it does not lose them.
        IF (SELECT stockmovesinrange FROM public.sppoultryreport_eggstockbalance(a, d, current_date)) <> 0 THEN
            RAISE EXCEPTION '344: a loss-free sorting must not move the stock balance report.';
        END IF;

        -- Class adjustments: Large had 400 - 48 = 352.
        adj := public.sppoultryeggclass_adjust(a, lg, 'Breakage', 30, 'dropped tray', who);
        IF (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = lg) <> 322
           OR (SELECT txntype FROM poultrystocktransactions WHERE poultrystocktransactionid = adj) <> 'Egg Loss' THEN
            RAISE EXCEPTION '344: breakage should take 30 out of Large as an Egg Loss.';
        END IF;
        BEGIN
            PERFORM public.sppoultryeggclass_adjust(a, lg, 'Loss', 1000, 'too many', who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '344: a class was driven below zero.';
        EXCEPTION WHEN SQLSTATE 'P0003' THEN NULL;
        END;
        BEGIN
            PERFORM public.sppoultryeggclass_adjust(a, lg, 'Correction', 5, '  ', who);
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '344: an adjustment without a reason was accepted.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;
        PERFORM public.sppoultryeggclass_adjust(a, lg, 'Stocktake', 8, 'found in cold room', who);
        IF (SELECT SUM(quantity) FROM poultrystocktransactions WHERE farmid = a AND poultryproductid = lg) <> 330 THEN
            RAISE EXCEPTION '344: a stock-take of +8 should leave 330 Large.';
        END IF;

        -- Missing activity. r1 (D) has 100 left after 400 sorted; add D+1 (200) and today (300).
        r2 := public.spproductionrecord_insert(a, who, who, 20, 140, d + 1, 2000, 0, 2000, 0, NULL, 200, 0, 0, 200, f1, 0);
        r3 := public.spproductionrecord_insert(a, who, who, 20, 140, current_date, 2000, 0, 2000, 0, NULL, 300, 0, 0, 300, f1, 0);
        -- Unsorted: 500 + 200 + 300 - 400 sorted = 600 -> covers today's 300, D+1's 200, D's 100.
        SELECT count(*) INTO v_n FROM public.sppoultryactivity_unsortedeggs(a, current_date);
        IF v_n <> 2 OR EXISTS (SELECT 1 FROM public.sppoultryactivity_unsortedeggs(a, current_date) WHERE productionrecordid = r3) THEN
            RAISE EXCEPTION '344: two earlier days should be reported, never today.';
        END IF;
        IF (SELECT severity FROM public.sppoultryactivity_unsortedeggs(a, current_date) WHERE productionrecordid = r1) <> 'Critical' THEN
            RAISE EXCEPTION '344: four days unsorted should be Critical.';
        END IF;
        -- Sell 450 unsorted: 150 remain -> today's 300 absorbs it all; nothing earlier is waiting.
        sale1 := public.spsale_insert(who, a, d::timestamp, 'Fresh Eggs', 450, 16, 240, 'Cash', NULL);
        IF EXISTS (SELECT 1 FROM public.sppoultryactivity_unsortedeggs(a, current_date)) THEN
            RAISE EXCEPTION '344: eggs sold unsorted must not be reported as waiting to be sorted.';
        END IF;
        PERFORM public.sppoultryeggsortingsettings_save(a, TRUE, 'Off', 24, 16, who);
        PERFORM public.spsale_delete(a, who, sale1);
        IF EXISTS (SELECT 1 FROM public.sppoultryactivity_unsortedeggs(a, current_date)) THEN
            RAISE EXCEPTION '344: with the policy Off there is no task.';
        END IF;

        RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '__344_ok__';
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
        NULL;
    END;

    RAISE NOTICE '344_PoultryEggSortingCompletion: verified (eggs per crate + bounds, prices per class, audit of settings / sizes / post / reverse / discard / sale class with actors, append-only audit, class breakage + stock-take + no negative + reason required, unsorted-eggs activity: earlier days only, severity, capped by unsorted stock, off when policy Off).';
END $$;
