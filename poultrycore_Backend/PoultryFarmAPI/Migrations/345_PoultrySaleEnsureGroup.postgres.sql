-- =============================================================================
-- 345_PoultrySaleEnsureGroup.postgres.sql             (requires 341 and 343)
--
-- Purpose
-- -------
-- Lets a sale entered with ONE egg class have more egg sizes added to it
-- when it is edited.
--
-- A multi-size egg sale (343) is several sale rows sharing a sale number
-- (SG-00001). A sale saved with one class has no number, so a line added on
-- the edit dialog had nothing to join and became a separate sale.
-- sppoultrysale_ensuregroup gives such a sale its SG number (or returns the
-- one it already has); the app then saves the new lines with that number.
--
-- Numbering is the same as sppoultrysale_creategroup: the same advisory lock
-- and the same SG-nnnnn sequence per farm, so the two can never hand out the
-- same number.
--
-- Only the number is stamped. The sale's class, stock movement, cash and
-- payments are untouched.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.sppoultrysale_ensuregroup(
    p_farmid text, p_saleid integer, p_by text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
AS $function$
DECLARE
    v_group   text;
    v_product text;
BEGIN
    SELECT s.salegroupno, s.product
    INTO   v_group, v_product
    FROM   sale s
    WHERE  s.saleid = p_saleid AND s.farmid = p_farmid
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sale #% was not found for this company.', p_saleid;
    END IF;

    IF NULLIF(btrim(COALESCE(v_group, '')), '') IS NOT NULL THEN
        RETURN v_group;
    END IF;

    IF lower(COALESCE(v_product, '')) NOT LIKE '%egg%' THEN
        RAISE EXCEPTION 'Only an egg sale can have more egg sizes added to it.';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('poultry-salegroup-no:' || p_farmid));
    SELECT 'SG-' || lpad((COALESCE(max(NULLIF(regexp_replace(s.salegroupno, '\D', '', 'g'), '')::int), 0) + 1)::text, 5, '0')
    INTO   v_group
    FROM   sale s WHERE s.farmid = p_farmid AND s.salegroupno LIKE 'SG-%';

    PERFORM set_config('poultry.actor', COALESCE(p_by, ''), TRUE);
    UPDATE sale s SET salegroupno = v_group
    WHERE  s.saleid = p_saleid AND s.farmid = p_farmid;

    RETURN v_group;
END;
$function$;

COMMIT;
