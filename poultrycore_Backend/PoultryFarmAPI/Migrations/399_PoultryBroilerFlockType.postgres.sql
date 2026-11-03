-- =============================================================================
-- 399: Broilers, phase 1 -- every flock is a Layer flock or a Broiler flock.
--
-- The app was built around laying hens. A broiler farm could already buy
-- chicks, place them and sell them, but every screen asked it about eggs, and
-- nothing knew which flocks were meat birds. The company setting
-- poultrycompanyprofiles.businesstype (Layers | Broilers | Both, 212) was
-- saved and then read by nothing.
--
--   1. flock.flocktype  'Layer' | 'Broiler', NOT NULL.
--      Set PER FLOCK: a company may run both at once. The company setting is
--      only the default.
--   2. fnpoultry_defaultflocktype(farm, breed) -- the one default rule:
--        a broiler breed (Cobb, Ross, Arbor Acres, Hubbard, "broiler")  -> Broiler
--        else a company whose business type is Broilers                -> Broiler
--        else                                                            Layer
--      The breed list mirrors the "Broilers" group of lib/poultry/breeds.ts.
--   3. A BEFORE INSERT trigger fills the type when the writer did not send
--      one, so every existing way of creating a flock (Flocks page, Flock
--      Purchases allocation, Farm Setup) gets a sensible type without being
--      changed.
--   4. spflock_settype -- the only way to change it afterwards. Refused on a
--      closed flock: its reports were finalised as what it was.
--   5. spflock_getall / spflock_getbyid return flocktype (DROP + CREATE:
--      RETURNS TABLE is part of the signature). Bodies are the LIVE ones,
--      read from dev 2026-11-03, plus the one column.
--   6. fnpoultrysale_isbirdsale also matches "broiler". A sale of "Broilers"
--      or "Live broilers" took no birds off the flock -- the bird position,
--      closeout and flock lifetime all missed it. No existing sale carries
--      such a name (checked on dev 2026-11-03), so no figure moves.
--
-- Existing flocks: typed by the same default rule. On dev that makes every
-- flock a Layer except those whose breed names a broiler breed.
-- =============================================================================
\set ON_ERROR_STOP on
BEGIN;

-- 1-2. The column and the default rule ---------------------------------------
ALTER TABLE public.flock ADD COLUMN IF NOT EXISTS flocktype text;

CREATE OR REPLACE FUNCTION public.fnpoultry_isbroilerbreed(p_breed text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $function$
    SELECT lower(COALESCE(p_breed, '')) ~ '(broil|cobb|ross|arbor|hubbard)';
$function$;

CREATE OR REPLACE FUNCTION public.fnpoultry_defaultflocktype(p_farmid text, p_breed text DEFAULT NULL)
RETURNS text LANGUAGE sql STABLE AS $function$
    SELECT CASE
        WHEN public.fnpoultry_isbroilerbreed(p_breed) THEN 'Broiler'
        WHEN EXISTS (SELECT 1 FROM public.poultrycompanyprofiles p
                     WHERE p.farmid = p_farmid AND p.businesstype = 'Broilers') THEN 'Broiler'
        ELSE 'Layer'
    END;
$function$;

UPDATE public.flock
   SET flocktype = public.fnpoultry_defaultflocktype(farmid::text, breed::text)
 WHERE flocktype IS NULL;

ALTER TABLE public.flock ALTER COLUMN flocktype SET NOT NULL;
ALTER TABLE public.flock DROP CONSTRAINT IF EXISTS ck_flock_flocktype;
ALTER TABLE public.flock ADD CONSTRAINT ck_flock_flocktype CHECK (flocktype IN ('Layer', 'Broiler'));

-- 3. Default on insert ---------------------------------------------------------
CREATE OR REPLACE FUNCTION public.tr_flock_flocktype_fn()
RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    IF NEW.flocktype IS NULL OR btrim(NEW.flocktype) = '' THEN
        NEW.flocktype := public.fnpoultry_defaultflocktype(NEW.farmid::text, NEW.breed::text);
    END IF;
    RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS tr_flock_flocktype ON public.flock;
CREATE TRIGGER tr_flock_flocktype BEFORE INSERT ON public.flock
    FOR EACH ROW EXECUTE FUNCTION public.tr_flock_flocktype_fn();

-- 4. Changing it -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.spflock_settype(
    p_flockid   integer,
    p_farmid    text,
    p_flocktype text,
    p_userid    text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $function$
DECLARE
    v_flock record;
BEGIN
    IF p_flocktype IS NULL OR p_flocktype NOT IN ('Layer', 'Broiler') THEN
        RAISE EXCEPTION 'Flock type must be Layer or Broiler.' USING ERRCODE = 'P0001';
    END IF;

    SELECT f.flockid, f.name, f.flocktype, f.closeddate
      INTO v_flock
      FROM public.flock f
     WHERE f.flockid = p_flockid
       AND f.farmid = p_farmid
       AND NOT COALESCE(f.isdeleted, FALSE)
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Flock not found.' USING ERRCODE = 'P0001';
    END IF;

    IF v_flock.flocktype = p_flocktype THEN
        RETURN;
    END IF;

    IF v_flock.closeddate IS NOT NULL THEN
        RAISE EXCEPTION 'Flock "%" is closed. Reopen it before changing whether it is a layer or broiler flock.',
            v_flock.name USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.flock
       SET flocktype = p_flocktype,
           updatedat = now(),
           updatedby = COALESCE(p_userid, updatedby)
     WHERE flockid = p_flockid
       AND farmid = p_farmid;
END
$function$;

-- 5. Readers ------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.spflock_getall(text, text);
CREATE FUNCTION public.spflock_getall(p_farmid text, p_userid text DEFAULT NULL::text)
 RETURNS TABLE(flockid integer, userid text, farmid text, name text, breed text, startdate date, quantity integer, active boolean, houseid integer, batchid integer, inactivationreason text, otherreason text, notes text, hasarrived boolean, batchname text, createdat timestamp without time zone, closeddate date, closedat timestamp without time zone, closedby text, closereason text, closeoutid integer, flocktype text)
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
        f.closeoutid,
        f.flocktype                           -- 399
    FROM flock f
    LEFT JOIN mainflockbatch b
        ON f.batchid = b.batchid AND f.farmid = b.farmid
    WHERE f.farmid = p_farmid
    ORDER BY f.startdate DESC;
END
$function$;

DROP FUNCTION IF EXISTS public.spflock_getbyid(integer, text);
CREATE FUNCTION public.spflock_getbyid(p_flockid integer, p_farmid text)
 RETURNS TABLE(flockid integer, userid text, farmid text, name text, breed text, startdate date, quantity integer, active boolean, houseid integer, batchid integer, inactivationreason text, otherreason text, notes text, hasarrived boolean, batchname text, closeddate date, closedat timestamp without time zone, closedby text, closereason text, closeoutid integer, flocktype text)
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
        f.closeoutid,
        f.flocktype                           -- 399
    FROM flock f
    LEFT JOIN mainflockbatch b
        ON f.batchid = b.batchid AND f.farmid = b.farmid
    WHERE f.flockid = p_flockid
      AND f.farmid = p_farmid;
END
$function$;

-- 6. "Broilers" is a bird sale ----------------------------------------------------
-- 374's body plus '%broiler%'. Dead Birds stay excluded via the byproduct role.
CREATE OR REPLACE FUNCTION public.fnpoultrysale_isbirdsale(p_product text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $function$
    SELECT (lower(COALESCE(p_product, '')) = 'birds'
            OR lower(COALESCE(p_product, '')) LIKE '%bird%'
            OR lower(COALESCE(p_product, '')) LIKE '%chick%'
            OR lower(COALESCE(p_product, '')) LIKE '%cockerel%'
            OR (lower(COALESCE(p_product, '')) LIKE '%broiler%'    -- 399, but not
                AND lower(COALESCE(p_product, '')) !~ '(feed|mash|starter|grower|finisher|concentrate)'))  -- "Broiler feed"
       AND lower(COALESCE(p_product, '')) NOT LIKE '%egg%'
       AND public.fnpoultrysale_byproductrole(p_product) IS NULL;   -- 374: Dead Birds are not live birds
$function$;

COMMIT;
