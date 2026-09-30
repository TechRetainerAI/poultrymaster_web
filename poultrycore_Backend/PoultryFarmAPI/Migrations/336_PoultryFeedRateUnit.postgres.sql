-- =============================================================================
-- 336_PoultryFeedRateUnit.postgres.sql
--
-- Purpose
-- -------
-- Let a farm express its feed rate in the unit it thinks in (g per bird, kg per
-- 100 birds, lb per bird...), not only grams per bird per day.
--
-- The rate is STILL stored as grams per bird per day (gramsperbirdperday, 335)
-- -- the one figure the suggestion is computed from -- so nothing downstream
-- changes. What is added is the unit the farm CHOSE, kept only so the rate
-- reads back the way it was typed:
--   poultryfeedrates.rateunit         -- the unit a saved rate was entered in
--   poultryfeeddistributions.rateunit -- the unit a distribution's rate used
--
-- Units (key -> grams per bird per day for 1 of the unit):
--   g_bird   1           kg_bird  1000
--   kg_100   10          kg_1000  1
--   lb_bird  453.59237   lb_100   4.5359237
-- The conversion happens in the UI, which sends grams; this migration only
-- records and validates the key.
--
-- Depends on 335. Idempotent. Safe to run more than once.
-- EFFECT ON TODAY'S NUMBERS: none. Existing saved rates read back as g_bird.
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.fnpoultryfeedrate_unitok(p_unit text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT p_unit IN ('g_bird', 'kg_bird', 'kg_100', 'kg_1000', 'lb_bird', 'lb_100');
$function$;

ALTER TABLE public.poultryfeedrates
    ADD COLUMN IF NOT EXISTS rateunit text NOT NULL DEFAULT 'g_bird';
ALTER TABLE public.poultryfeeddistributions
    ADD COLUMN IF NOT EXISTS rateunit text;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_poultryfeedrates_unit') THEN
        ALTER TABLE public.poultryfeedrates
            ADD CONSTRAINT ck_poultryfeedrates_unit CHECK (public.fnpoultryfeedrate_unitok(rateunit));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_poultryfeeddist_unit') THEN
        ALTER TABLE public.poultryfeeddistributions
            ADD CONSTRAINT ck_poultryfeeddist_unit CHECK (rateunit IS NULL OR public.fnpoultryfeedrate_unitok(rateunit));
    END IF;
END $$;

-- Save a rate: grams as before, plus the unit it was entered in.
DROP FUNCTION IF EXISTS public.sppoultryfeedrate_set(text, integer, numeric, text);
DROP FUNCTION IF EXISTS public.sppoultryfeedrate_set(text, integer, numeric, text, text);
CREATE FUNCTION public.sppoultryfeedrate_set(
    p_farmid text, p_itemid integer, p_grams numeric, p_updatedby text, p_rateunit text DEFAULT 'g_bird')
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM poultryrawmaterialitems i
                   WHERE i.poultryrawmaterialitemid = p_itemid AND i.farmid = p_farmid) THEN
        RAISE EXCEPTION 'Feed product not found for this company.';
    END IF;
    IF p_grams IS NULL THEN
        DELETE FROM poultryfeedrates r WHERE r.farmid = p_farmid AND r.poultryrawmaterialitemid = p_itemid;
        RETURN;
    END IF;
    IF p_grams <= 0 THEN
        RAISE EXCEPTION 'A feed rate must be more than 0.';
    END IF;
    IF NOT public.fnpoultryfeedrate_unitok(COALESCE(p_rateunit, 'g_bird')) THEN
        RAISE EXCEPTION 'Unknown feed rate unit "%".', p_rateunit;
    END IF;
    INSERT INTO poultryfeedrates AS t (farmid, poultryrawmaterialitemid, gramsperbirdperday, rateunit, updatedby, updatedatutc)
    VALUES (p_farmid, p_itemid, p_grams, COALESCE(p_rateunit, 'g_bird'), p_updatedby, now())
    ON CONFLICT (farmid, poultryrawmaterialitemid) DO UPDATE
    SET gramsperbirdperday = EXCLUDED.gramsperbirdperday, rateunit = EXCLUDED.rateunit,
        updatedby = EXCLUDED.updatedby, updatedatutc = now();
END;
$function$;

-- Availability now also says which unit the saved rate was entered in.
DROP FUNCTION IF EXISTS public.sppoultryfeeddistribution_availability(text, integer);
CREATE FUNCTION public.sppoultryfeeddistribution_availability(p_farmid text, p_itemid integer)
RETURNS TABLE(
    poultryrawmaterialitemid integer, itemname text, category text, unitofmeasure text,
    usagemethod text, availablekg numeric, currentquantity numeric, lotcount integer,
    costrecognitionmethod text, gramsperbirdperday numeric, rateunit text)
LANGUAGE sql
STABLE
AS $function$
    SELECT i.poultryrawmaterialitemid, i.itemname::text, i.category::text, i.unitofmeasure::text,
           COALESCE(i.usagemethod, 'FIFO')::text,
           COALESCE((SELECT sum(p.remainingquantity * COALESCE(NULLIF(p.productionunitsperpurchaseunit, 0), 1))
                     FROM poultryrawmaterialpurchases p
                     WHERE p.farmid = p_farmid AND p.poultryrawmaterialitemid = i.poultryrawmaterialitemid
                       AND p.remainingquantity > 0), 0)::numeric(14,3),
           i.currentquantity,
           (SELECT count(*)::int FROM poultryrawmaterialpurchases p
            WHERE p.farmid = p_farmid AND p.poultryrawmaterialitemid = i.poultryrawmaterialitemid
              AND p.remainingquantity > 0),
           (SELECT e.method FROM public.fnpoultrycostrecognition_effective(
                p_farmid, i.poultryrawmaterialitemid, i.category, public.fncompany_businessdate(p_farmid)) e),
           r.gramsperbirdperday,
           r.rateunit
    FROM   poultryrawmaterialitems i
    LEFT   JOIN poultryfeedrates r ON r.farmid = p_farmid AND r.poultryrawmaterialitemid = i.poultryrawmaterialitemid
    WHERE  i.farmid = p_farmid AND i.poultryrawmaterialitemid = p_itemid;
$function$;

-- Record which unit a posted distribution's rate was entered in (called in the
-- same transaction right after sppoultryfeeddistribution_post).
CREATE OR REPLACE FUNCTION public.sppoultryfeeddistribution_setrateunit(p_id integer, p_farmid text, p_rateunit text)
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_rateunit IS NOT NULL AND NOT public.fnpoultryfeedrate_unitok(p_rateunit) THEN
        RAISE EXCEPTION 'Unknown feed rate unit "%".', p_rateunit;
    END IF;
    UPDATE poultryfeeddistributions d SET rateunit = p_rateunit
    WHERE d.poultryfeeddistributionid = p_id AND d.farmid = p_farmid;
END;
$function$;

COMMIT;

-- -----------------------------------------------------------------------------
-- Verification (rolled back).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    a  text := '__336_selftest__';
    it integer;
    r  record;
BEGIN
    BEGIN
        INSERT INTO poultryrawmaterialitems (farmid, itemname, category, unitofmeasure, currentquantity, isactive)
        VALUES (a, 'Layer Mash', 'FinishedFeed', 'kg', 0, TRUE) RETURNING poultryrawmaterialitemid INTO it;

        -- 1.1 kg per 100 birds = 11 g per bird: stored as grams, unit kept.
        PERFORM public.sppoultryfeedrate_set(a, it, 11, '__336__', 'kg_100');
        SELECT * INTO r FROM public.sppoultryfeeddistribution_availability(a, it);
        IF r.gramsperbirdperday <> 11 OR r.rateunit <> 'kg_100' THEN
            RAISE EXCEPTION '336: rate should read back 11 g in kg_100, got % %.', r.gramsperbirdperday, r.rateunit;
        END IF;

        -- The old 4-argument call still works and means grams.
        PERFORM public.sppoultryfeedrate_set(a, it, 112.5, '__336__');
        SELECT * INTO r FROM public.sppoultryfeeddistribution_availability(a, it);
        IF r.rateunit <> 'g_bird' THEN
            RAISE EXCEPTION '336: a rate saved without a unit should be g_bird.';
        END IF;

        BEGIN
            PERFORM public.sppoultryfeedrate_set(a, it, 5, '__336__', 'bushels');
            RAISE EXCEPTION USING ERRCODE = 'P0098', MESSAGE = '336: accepted an unknown unit.';
        EXCEPTION WHEN raise_exception THEN NULL;
        END;

        RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = '__336_ok__';
    EXCEPTION WHEN SQLSTATE 'P0099' THEN
        NULL;
    END;
    RAISE NOTICE '336_PoultryFeedRateUnit: verified (unit saved and read back, grams default, unknown unit refused).';
END $$;
