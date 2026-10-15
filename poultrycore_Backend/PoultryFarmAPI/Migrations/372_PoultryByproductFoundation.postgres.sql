-- =============================================================================
-- 372_PoultryByproductFoundation.postgres.sql
--
-- Purpose (Phase 1 of the poultry inventory traceability programme)
-- -------
-- Two protected, system-managed products for every poultry company:
--   Broken Eggs  (role BrokenEggs)  unit Egg
--   Dead Birds   (role DeadBirds)   unit Bird
-- held in the existing stock ledger (poultrystocktransactions) -- no second
-- egg or bird ledger. They are found by ROLE, never by name: the name-based
-- egg / bird tests elsewhere must not see them as eggs or live birds.
--
-- WHERE THEY COME FROM
--   Production record   brokeneggs -> Broken Eggs   'Broken Egg Prod'   (+)
--                       mortality  -> Dead Birds    'Mortality In'      (+)
--     Saleable eggs are ALREADY net of broken eggs (198 / 204), and live
--     birds already fall by the mortality, so nothing is counted twice.
--   Disposed immediately (per record, optional): the same amount goes out at
--     once -- 'Mortality Disposal' / 'Broken Egg Disposal' (-) -- so the
--     ledger still shows what was generated AND what was disposed.
--   Egg sorting         'Breakage' lines -> Broken Eggs 'Sorting Breakage' (+)
--
-- Every row is a delta to reach a target for (product, txntype, source id):
-- re-posting writes nothing, a correction posts the difference, a reversal
-- posts the opposite. Rows are dated to the production / sorting date.
--
-- CUTOVER: stock starts from this deployment. A production record created
-- before it never generates byproduct stock, even when edited later (opening
-- stock on hand is entered once as a manual movement).
--
-- SAFETY: an edit or reversal that would take Broken Eggs or Dead Birds below
-- zero (they were since sold, used or disposed) is refused, and nothing of it
-- is saved.
--
-- Deploy order: this migration, then the API, then the web app.
-- =============================================================================
BEGIN;

-- --------------------------------------------------------------- 1. schema --
ALTER TABLE public.poultryproducts ADD COLUMN IF NOT EXISTS systemrole text;
CREATE UNIQUE INDEX IF NOT EXISTS ux_poultryproducts_systemrole
    ON public.poultryproducts (farmid, systemrole) WHERE systemrole IS NOT NULL;

ALTER TABLE public.productionrecords ADD COLUMN IF NOT EXISTS mortalitydisposition text NOT NULL DEFAULT 'Keep';
ALTER TABLE public.productionrecords ADD COLUMN IF NOT EXISTS brokeneggdisposition text NOT NULL DEFAULT 'Keep';
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_productionrecords_byproductdisposition') THEN
        ALTER TABLE public.productionrecords ADD CONSTRAINT ck_productionrecords_byproductdisposition
            CHECK (mortalitydisposition IN ('Keep', 'Disposed') AND brokeneggdisposition IN ('Keep', 'Disposed'));
    END IF;
END $$;

-- Per company: when byproduct stock started, and whether each byproduct is
-- offered in Add Sale (Dead Birds off until a farm turns it on).
CREATE TABLE IF NOT EXISTS public.poultrybyproductsettings (
    farmid               text      PRIMARY KEY,
    cutoverat            timestamp NOT NULL,
    brokeneggsinsales    boolean   NOT NULL DEFAULT TRUE,
    deadbirdsinsales     boolean   NOT NULL DEFAULT FALSE,
    updatedby            text,
    updatedat            timestamp NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);
-- Every company that already has production starts from now; a new company
-- has no row and so no cutover.
INSERT INTO public.poultrybyproductsettings (farmid, cutoverat)
SELECT DISTINCT pr.farmid, (now() AT TIME ZONE 'utc')
FROM   public.productionrecords pr
ON CONFLICT (farmid) DO NOTHING;

-- ------------------------------------------------------ 2. system products --
CREATE OR REPLACE FUNCTION public.fnpoultry_byproductname(p_role text)
RETURNS text LANGUAGE sql IMMUTABLE AS $f$
    SELECT CASE p_role WHEN 'BrokenEggs' THEN 'Broken Eggs' WHEN 'DeadBirds' THEN 'Dead Birds' END;
$f$;

-- The company's product for a role, created (or adopted) when missing.
CREATE OR REPLACE FUNCTION public.fnpoultry_byproduct(p_farmid text, p_role text)
RETURNS integer LANGUAGE plpgsql AS $f$
DECLARE
    v_id   integer;
    v_name text := fnpoultry_byproductname(p_role);
BEGIN
    IF v_name IS NULL THEN
        RAISE EXCEPTION 'Unknown byproduct role %.', p_role;
    END IF;
    SELECT p.poultryproductid INTO v_id FROM poultryproducts p
    WHERE  p.farmid = p_farmid AND p.systemrole = p_role;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    -- A product of that name made by hand is adopted, unless it is an egg
    -- class or the birds product (then the system one gets its own name).
    SELECT p.poultryproductid INTO v_id FROM poultryproducts p
    WHERE  p.farmid = p_farmid AND lower(p.name) = lower(v_name)
      AND  NOT COALESCE(p.israweggproduct, FALSE) AND NOT COALESCE(p.isbirdproduct, FALSE)
      AND  p.systemrole IS NULL
      AND  NOT EXISTS (SELECT 1 FROM poultryeggsizes z WHERE z.poultryproductid = p.poultryproductid);
    IF v_id IS NOT NULL THEN
        UPDATE poultryproducts p SET systemrole = p_role, isactive = TRUE, producttype = 'FinishedGood',
               unit = CASE WHEN p_role = 'BrokenEggs' THEN 'Egg' ELSE 'Bird' END,
               updateddate = (now() AT TIME ZONE 'utc')
        WHERE  p.poultryproductid = v_id;
        RETURN v_id;
    END IF;

    IF EXISTS (SELECT 1 FROM poultryproducts p WHERE p.farmid = p_farmid AND lower(p.name) = lower(v_name)) THEN
        v_name := v_name || ' (system)';
    END IF;
    INSERT INTO poultryproducts (farmid, name, unit, unitprice, producttype, isactive, israweggproduct,
                                 requiresrecipesetup, isbirdproduct, systemrole)
    VALUES (p_farmid, v_name, CASE WHEN p_role = 'BrokenEggs' THEN 'Egg' ELSE 'Bird' END, 0, 'FinishedGood', TRUE,
            FALSE, FALSE, FALSE, p_role)
    RETURNING poultryproductid INTO v_id;
    RETURN v_id;
END
$f$;

CREATE OR REPLACE FUNCTION public.sppoultryproduct_ensurebyproducts(p_farmid text)
RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    PERFORM fnpoultry_byproduct(p_farmid, 'BrokenEggs');
    PERFORM fnpoultry_byproduct(p_farmid, 'DeadBirds');
END
$f$;

-- Seed every poultry company now (idempotent).
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT DISTINCT x.farmid FROM (
                 SELECT pr.farmid FROM productionrecords pr
                 UNION SELECT p.farmid FROM poultryproducts p) x LOOP
        PERFORM public.sppoultryproduct_ensurebyproducts(r.farmid);
    END LOOP;
END $$;

-- ------------------------------------------------------- 3. the byproduct sync --
-- Post the delta that brings (product, txntype, source id) to p_target.
-- Returns the delta posted. No stock check here: callers check the result.
CREATE OR REPLACE FUNCTION public.sppoultrybyproduct_post(p_farmid text, p_role text, p_txntype text, p_relatedid integer,
    p_target numeric, p_date date, p_note text, p_by text DEFAULT NULL)
RETURNS numeric LANGUAGE plpgsql AS $f$
DECLARE
    v_prod  integer := fnpoultry_byproduct(p_farmid, p_role);
    v_net   numeric;
    v_delta numeric;
BEGIN
    SELECT COALESCE(SUM(t.quantity), 0) INTO v_net FROM poultrystocktransactions t
    WHERE  t.farmid = p_farmid AND t.poultryproductid = v_prod AND t.txntype = p_txntype AND t.relatedid = p_relatedid;
    v_delta := COALESCE(p_target, 0) - v_net;
    IF v_delta = 0 THEN RETURN 0; END IF;
    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, relatedid, note, createdby, createddate)
    VALUES (p_farmid, v_prod, p_txntype, v_delta, p_relatedid,
            left(CASE WHEN COALESCE(p_target, 0) = 0 THEN 'Reversal: ' || COALESCE(p_note, p_txntype) ELSE p_note END, 500),
            p_by, COALESCE(p_date, (now() AT TIME ZONE 'utc')::date)::timestamp);
    RETURN v_delta;
END
$f$;

CREATE OR REPLACE FUNCTION public.fnpoultry_byproductonhand(p_farmid text, p_role text)
RETURNS numeric LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(SUM(t.quantity), 0)
    FROM   poultrystocktransactions t
    JOIN   poultryproducts p ON p.poultryproductid = t.poultryproductid
    WHERE  t.farmid = p_farmid AND p.farmid = p_farmid AND p.systemrole = p_role;
$f$;

-- Refuse a change that pushed a byproduct below zero (it was since sold,
-- used or disposed). Stock already negative before is not this change's doing.
CREATE OR REPLACE FUNCTION public.fnpoultry_byproductguard(p_farmid text, p_role text, p_before numeric, p_what text)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
    v_after numeric := fnpoultry_byproductonhand(p_farmid, p_role);
BEGIN
    IF v_after < 0 AND v_after < p_before THEN
        RAISE EXCEPTION 'This % would leave % at % -- some of them have since been sold, used or disposed. Reverse those first.',
            p_what, fnpoultry_byproductname(p_role), trunc(v_after) USING ERRCODE = 'P0001';
    END IF;
END
$f$;

-- A production record's byproducts: generated, and disposed at once if chosen.
-- p_remove = the record is being reversed.
CREATE OR REPLACE FUNCTION public.sppoultrybyproduct_syncforproduction(p_farmid text, p_recordid integer,
    p_remove boolean DEFAULT FALSE, p_by text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
    v_pr       record;
    v_cutover  timestamp;
    v_broken   numeric := 0;
    v_dead     numeric := 0;
    v_bb       numeric;
    v_db       numeric;
    v_label    text;
BEGIN
    SELECT pr.* INTO v_pr FROM productionrecords pr WHERE pr.id = p_recordid AND pr.farmid = p_farmid;
    IF NOT FOUND THEN RETURN; END IF;

    -- Before the cutover: no byproduct stock, unless some was already posted.
    SELECT s.cutoverat INTO v_cutover FROM poultrybyproductsettings s WHERE s.farmid = p_farmid;
    IF v_cutover IS NOT NULL AND v_pr.createdat < v_cutover
       AND NOT EXISTS (SELECT 1 FROM poultrystocktransactions t JOIN poultryproducts p ON p.poultryproductid = t.poultryproductid
                       WHERE t.farmid = p_farmid AND t.relatedid = p_recordid AND p.systemrole IS NOT NULL
                         AND t.txntype IN ('Broken Egg Prod', 'Mortality In', 'Mortality Disposal', 'Broken Egg Disposal')) THEN
        RETURN;
    END IF;

    IF NOT p_remove THEN
        v_broken := GREATEST(COALESCE(v_pr.brokeneggs, 0), 0);
        v_dead   := GREATEST(COALESCE(v_pr.mortality, 0), 0);
    END IF;
    v_label := 'Production ' || to_char(v_pr.date, 'YYYY-MM-DD');
    v_bb := fnpoultry_byproductonhand(p_farmid, 'BrokenEggs');
    v_db := fnpoultry_byproductonhand(p_farmid, 'DeadBirds');

    -- Disposal first when it shrinks (a reversal puts it back before the
    -- generation comes off), generation first when it grows.
    PERFORM sppoultrybyproduct_post(p_farmid, 'BrokenEggs', 'Broken Egg Disposal', p_recordid,
        CASE WHEN v_pr.brokeneggdisposition = 'Disposed' THEN -v_broken ELSE 0 END, v_pr.date, 'Disposed at once - ' || v_label, p_by);
    PERFORM sppoultrybyproduct_post(p_farmid, 'BrokenEggs', 'Broken Egg Prod', p_recordid, v_broken, v_pr.date, 'Broken eggs - ' || v_label, p_by);
    PERFORM sppoultrybyproduct_post(p_farmid, 'DeadBirds', 'Mortality Disposal', p_recordid,
        CASE WHEN v_pr.mortalitydisposition = 'Disposed' THEN -v_dead ELSE 0 END, v_pr.date, 'Disposed at once - ' || v_label, p_by);
    PERFORM sppoultrybyproduct_post(p_farmid, 'DeadBirds', 'Mortality In', p_recordid, v_dead, v_pr.date, 'Mortality - ' || v_label, p_by);

    PERFORM fnpoultry_byproductguard(p_farmid, 'BrokenEggs', v_bb, CASE WHEN p_remove THEN 'reversal' ELSE 'change' END);
    PERFORM fnpoultry_byproductguard(p_farmid, 'DeadBirds',  v_db, CASE WHEN p_remove THEN 'reversal' ELSE 'change' END);
END
$f$;

-- Set a record's dispositions (Keep / Disposed) and re-post.
CREATE OR REPLACE FUNCTION public.sppoultryproduction_setdisposition(p_farmid text, p_recordid integer,
    p_mortalitydisposition text, p_brokeneggdisposition text, p_by text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    UPDATE productionrecords pr
    SET    mortalitydisposition = COALESCE(NULLIF(p_mortalitydisposition, ''), pr.mortalitydisposition),
           brokeneggdisposition = COALESCE(NULLIF(p_brokeneggdisposition, ''), pr.brokeneggdisposition)
    WHERE  pr.id = p_recordid AND pr.farmid = p_farmid;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Production record not found for this company.' USING ERRCODE = 'P0001';
    END IF;
    PERFORM sppoultrybyproduct_syncforproduction(p_farmid, p_recordid, FALSE, p_by);
END
$f$;

-- What each production record chose (for the production form and lists).
CREATE OR REPLACE FUNCTION public.sppoultryproduction_dispositions(p_farmid text)
RETURNS TABLE(id integer, mortalitydisposition text, brokeneggdisposition text)
LANGUAGE sql STABLE AS $f$
    SELECT pr.id, pr.mortalitydisposition, pr.brokeneggdisposition
    FROM   productionrecords pr
    WHERE  pr.farmid = p_farmid
      AND  (pr.mortalitydisposition <> 'Keep' OR pr.brokeneggdisposition <> 'Keep');
$f$;

-- ------------------------------------------------------- 4. live patches --
CREATE FUNCTION pg_temp.m372_patch(p_fn text, p_marker text, p_old text, p_new text)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
    v_oid oid;
    v_n   integer;
    v_def text;
    v_old text := replace(p_old, chr(13), '');
    v_new text := replace(p_new, chr(13), '');
BEGIN
    SELECT count(*), min(p.oid) INTO v_n, v_oid
    FROM   pg_proc p WHERE p.proname = p_fn AND p.pronamespace = 'public'::regnamespace;
    IF v_n <> 1 THEN
        RAISE EXCEPTION '372: expected exactly one %, found %', p_fn, v_n;
    END IF;
    v_def := replace(pg_get_functiondef(v_oid), chr(13), '');
    IF position(replace(p_marker, chr(13), '') IN v_def) > 0 THEN
        RAISE NOTICE '372: % already patched (%), skipped', p_fn, p_marker;
        RETURN;
    END IF;
    v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / greatest(length(v_old), 1);
    IF v_n <> 1 THEN
        RAISE EXCEPTION '372: anchor for % (%) found % times, expected 1', p_fn, p_marker, v_n;
    END IF;
    EXECUTE replace(v_def, v_old, v_new);
    RAISE NOTICE '372: patched % (%)', p_fn, p_marker;
END
$f$;

-- 4a. Production: insert, update, reversal.
SELECT pg_temp.m372_patch('spproductionrecord_insert', '372: broken eggs and dead birds',
$o$    PERFORM sppoultryeggstock_syncforproduction(p_farmid, v_newid, v_good, NULL::numeric, p_userid);$o$,
$n$    PERFORM sppoultryeggstock_syncforproduction(p_farmid, v_newid, v_good, NULL::numeric, p_userid);
    -- 372: broken eggs and dead birds into their own stock.
    PERFORM sppoultrybyproduct_syncforproduction(p_farmid, v_newid, FALSE, p_userid);$n$);

SELECT pg_temp.m372_patch('spproductionrecord_update', '372: broken eggs and dead birds',
$o$        PERFORM sppoultryeggstock_syncforproduction(v_farmid, p_recordid, v_good2, NULL::numeric, p_updatedby);$o$,
$n$        PERFORM sppoultryeggstock_syncforproduction(v_farmid, p_recordid, v_good2, NULL::numeric, p_updatedby);
        -- 372: broken eggs and dead birds follow the corrected record.
        PERFORM sppoultrybyproduct_syncforproduction(v_farmid, p_recordid, FALSE, p_updatedby);$n$);

SELECT pg_temp.m372_patch('spproductionrecord_delete', '372: byproducts come off too',
$o$    PERFORM sppoultryeggstock_syncforproduction(p_farmid, p_recordid, 0, NULL::numeric, p_userid);$o$,
$n$    PERFORM sppoultryeggstock_syncforproduction(p_farmid, p_recordid, 0, NULL::numeric, p_userid);
    -- 372: byproducts come off too (refused if they were since sold or disposed).
    PERFORM sppoultrybyproduct_syncforproduction(p_farmid, p_recordid, TRUE, p_userid);$n$);

-- 4b. Egg sorting breakage -> Broken Eggs.
SELECT pg_temp.m372_patch('sppoultryeggsorting_post', '372: breakage becomes broken eggs',
$o$    UPDATE poultryeggsortingsessions x
    SET    status = 'Posted', inputquantity = v_input, outputquantity = v_out, lossquantity = v_loss,$o$,
$n$    -- 372: breakage becomes broken eggs (Reject / Other loss stay a loss).
    PERFORM sppoultrybyproduct_post(p_farmid, 'BrokenEggs', 'Sorting Breakage', p_sessionid,
        (SELECT COALESCE(SUM(l.quantity), 0) FROM poultryeggsortinglines l
         WHERE l.sessionid = p_sessionid AND l.linetype = 'Breakage'),
        fncompany_businessdate(p_farmid), 'Breakage in ' || v_note, p_by);

    UPDATE poultryeggsortingsessions x
    SET    status = 'Posted', inputquantity = v_input, outputquantity = v_out, lossquantity = v_loss,$n$);

SELECT pg_temp.m372_patch('sppoultryeggsorting_reverse', '372: its broken eggs come off',
$o$    UPDATE poultryeggsortingsessions x
    SET    status = 'Reversed', reversedby = p_by, reversedatutc = now(),$o$,
$n$    -- 372: its broken eggs come off (refused if they were since sold or disposed).
    DECLARE v_bb numeric := fnpoultry_byproductonhand(p_farmid, 'BrokenEggs');
    BEGIN
        PERFORM sppoultrybyproduct_post(p_farmid, 'BrokenEggs', 'Sorting Breakage', p_sessionid, 0,
            fncompany_businessdate(p_farmid), 'Breakage in egg sorting ' || s.sessionno, p_by);
        PERFORM fnpoultry_byproductguard(p_farmid, 'BrokenEggs', v_bb, 'reversal');
    END;

    UPDATE poultryeggsortingsessions x
    SET    status = 'Reversed', reversedby = p_by, reversedatutc = now(),$n$);

-- 4c. The system products cannot be renamed, switched off, turned into eggs, or deleted.
SELECT pg_temp.m372_patch('sppoultryproduct_update', '372: a system product keeps its role',
$o$BEGIN
    UPDATE poultryproducts p$o$,
$n$BEGIN
    -- 372: a system product keeps its role, name, unit and active state.
    IF EXISTS (SELECT 1 FROM poultryproducts p
               WHERE p.poultryproductid = p_poultryproductid AND p.farmid = p_farmid AND p.systemrole IS NOT NULL
                 AND (p.name IS DISTINCT FROM p_name OR NOT COALESCE(p_isactive, TRUE)
                      OR COALESCE(p_israweggproduct, FALSE) OR p.unit IS DISTINCT FROM p_unit)) THEN
        RAISE EXCEPTION 'This is a system product (Broken Eggs / Dead Birds): its name, unit and type cannot change and it cannot be switched off. You can change its price.' USING ERRCODE = 'P0001';
    END IF;
    UPDATE poultryproducts p$n$);

SELECT pg_temp.m372_patch('sppoultryproduct_delete', '372: a system product cannot be deleted',
$o$BEGIN
    IF EXISTS (SELECT 1 FROM poultrystocktransactions t$o$,
$n$BEGIN
    -- 372: a system product cannot be deleted.
    IF EXISTS (SELECT 1 FROM poultryproducts p
               WHERE p.poultryproductid = p_poultryproductid AND p.farmid = p_farmid AND p.systemrole IS NOT NULL) THEN
        RAISE EXCEPTION 'Broken Eggs and Dead Birds are system products and cannot be deleted.' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM poultrystocktransactions t$n$);

-- 4d. A new company's defaults include the two byproducts.
SELECT pg_temp.m372_patch('sppoultryproduct_ensuredefaultbirds', '372: and the byproducts',
$o$    RETURN v_id;
END;$o$,
$n$    PERFORM sppoultryproduct_ensurebyproducts(p_farmid);   -- 372: and the byproducts
    RETURN v_id;
END;$n$);

COMMIT;
