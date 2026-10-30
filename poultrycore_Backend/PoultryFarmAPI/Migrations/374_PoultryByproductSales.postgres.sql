-- =============================================================================
-- 374_PoultryByproductSales.postgres.sql                    (requires 372, 373)
--
-- Purpose (Phase 3 of the poultry inventory traceability programme)
-- -------
-- Broken Eggs and Dead Birds can be SOLD through the existing sale path
-- (sale + saleline, SG numbers, payments, reversal) -- no second sales system.
--
-- THE PROBLEM IT FIXES
--   Sales are sorted by product NAME. "Broken Eggs" matched '%egg%', so it
--   would come off the normal egg stock; "Dead Birds" matched '%bird%', so it
--   would come off the LIVE birds (bird position, flock closeout, P&L). A
--   byproduct sale must do neither.
--
-- WHAT CHANGES
--   fnpoultrysale_byproductrole(product)   'BrokenEggs' / 'DeadBirds' / NULL
--   fnpoultrysale_isbirdsale               no longer true for Dead Birds, so
--                                          live birds, closeout and P&L by flock
--                                          stop counting them as live birds sold
--   sppoultrybyproduct_syncforsale         the sale's 'Sale' rows on the
--                                          byproduct product (per line), dated
--                                          and attributed like the sale; refuses
--                                          to sell more than is on hand, and
--                                          refuses a byproduct the company does
--                                          not offer for sale
--   spsale_insert / sppoultrysale_creategroup / sppoultrysale_setegg /
--   sppoultryeggstock_syncforsale          route byproducts to the above and
--                                          keep them away from egg classes,
--                                          Unsorted eggs and live birds
--   sppoultrybyproductsettings_get / _set  "offer in Add Sale" per company
--                                          (Broken Eggs on, Dead Birds off)
--
-- Reversal needs nothing new: sppoultrysale_reverse already restores exactly
-- the product its 'Sale' rows came off -- Broken Eggs back to Broken Eggs,
-- Dead Birds back to Dead Birds, never to eggs or live birds.
--
-- Revenue: a byproduct sale is ordinary sales revenue (Phase 4 splits it out in
-- the reports). Generation never created revenue and still does not.
--
-- Deploy order: this migration, then the API, then the web app.
-- =============================================================================
BEGIN;

CREATE FUNCTION pg_temp.m374_patch(p_fn text, p_marker text, p_old text, p_new text)
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
        RAISE EXCEPTION '374: expected exactly one %, found %', p_fn, v_n;
    END IF;
    v_def := replace(pg_get_functiondef(v_oid), chr(13), '');
    IF position(replace(p_marker, chr(13), '') IN v_def) > 0 THEN
        RAISE NOTICE '374: % already patched (%), skipped', p_fn, p_marker;
        RETURN;
    END IF;
    v_n := (length(v_def) - length(replace(v_def, v_old, ''))) / greatest(length(v_old), 1);
    IF v_n <> 1 THEN
        RAISE EXCEPTION '374: anchor for % (%) found % times, expected 1', p_fn, p_marker, v_n;
    END IF;
    EXECUTE replace(v_def, v_old, v_new);
    RAISE NOTICE '374: patched % (%)', p_fn, p_marker;
END
$f$;

-- ------------------------------------------------------- 1. the role test --
-- The sale product text names a byproduct. The names are fixed (372 protects
-- them); "(system)" is the name 372 gives one when the plain name was taken.
CREATE OR REPLACE FUNCTION public.fnpoultrysale_byproductrole(p_product text)
RETURNS text LANGUAGE sql IMMUTABLE AS $f$
    SELECT CASE lower(btrim(COALESCE(p_product, '')))
               WHEN 'broken eggs'          THEN 'BrokenEggs'
               WHEN 'broken eggs (system)' THEN 'BrokenEggs'
               WHEN 'dead birds'           THEN 'DeadBirds'
               WHEN 'dead birds (system)'  THEN 'DeadBirds'
           END;
$f$;

-- Dead Birds are not live birds. Every reader of live bird sales (bird
-- position, closeout, P&L by flock, daily closing) goes through this.
CREATE OR REPLACE FUNCTION public.fnpoultrysale_isbirdsale(p_product text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $function$
    SELECT (lower(COALESCE(p_product, '')) = 'birds'
            OR lower(COALESCE(p_product, '')) LIKE '%bird%'
            OR lower(COALESCE(p_product, '')) LIKE '%chick%'
            OR lower(COALESCE(p_product, '')) LIKE '%cockerel%')
       AND lower(COALESCE(p_product, '')) NOT LIKE '%egg%'
       AND public.fnpoultrysale_byproductrole(p_product) IS NULL;   -- 374: Dead Birds are not live birds
$function$;

-- ---------------------------------------------------------- 2. settings --
CREATE OR REPLACE FUNCTION public.sppoultrybyproductsettings_get(p_farmid text)
RETURNS TABLE(brokeneggsinsales boolean, deadbirdsinsales boolean, cutoverat timestamp)
LANGUAGE sql STABLE AS $f$
    SELECT COALESCE(s.brokeneggsinsales, TRUE), COALESCE(s.deadbirdsinsales, FALSE), s.cutoverat
    FROM   (SELECT 1) one
    LEFT   JOIN poultrybyproductsettings s ON s.farmid = p_farmid;
$f$;

CREATE OR REPLACE FUNCTION public.sppoultrybyproductsettings_set(
    p_farmid text, p_brokeneggsinsales boolean, p_deadbirdsinsales boolean, p_by text)
RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    -- A company without a row has no cutover (all its production counts), so a
    -- row created here starts at the beginning of time, not now.
    INSERT INTO poultrybyproductsettings (farmid, cutoverat, brokeneggsinsales, deadbirdsinsales, updatedby)
    VALUES (p_farmid, '1900-01-01'::timestamp, COALESCE(p_brokeneggsinsales, TRUE), COALESCE(p_deadbirdsinsales, FALSE), p_by)
    ON CONFLICT (farmid) DO UPDATE
    SET brokeneggsinsales = COALESCE(p_brokeneggsinsales, poultrybyproductsettings.brokeneggsinsales),
        deadbirdsinsales  = COALESCE(p_deadbirdsinsales, poultrybyproductsettings.deadbirdsinsales),
        updatedby         = p_by,
        updatedat         = (now() AT TIME ZONE 'utc');
END
$f$;

-- --------------------------------------------- 3. a byproduct sale's stock --
-- Posts the sale's 'Sale' rows on the byproduct (one per line). Sales are
-- immutable once posted, so a second call writes nothing.
CREATE OR REPLACE FUNCTION public.sppoultrybyproduct_syncforsale(p_farmid text, p_saleid integer, p_by text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $f$
DECLARE
    v_s       record;
    v_role    text;
    v_prod    integer;
    v_onhand  numeric;
    v_set     record;
BEGIN
    SELECT s.saleid, s.product, s.quantity, s.status, s.ismultiline, s.flockid, s.batchid, s.saledate
    INTO   v_s FROM sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid;
    IF NOT FOUND OR v_s.status = 'Reversed' THEN RETURN; END IF;
    v_role := fnpoultrysale_byproductrole(v_s.product);
    IF v_role IS NULL OR COALESCE(v_s.quantity, 0) <= 0 THEN RETURN; END IF;
    IF EXISTS (SELECT 1 FROM poultrystocktransactions t
               WHERE t.farmid = p_farmid AND t.txntype = 'Sale' AND t.relatedid = p_saleid) THEN
        RETURN;
    END IF;

    SELECT * INTO v_set FROM sppoultrybyproductsettings_get(p_farmid);
    IF v_role = 'DeadBirds' AND NOT v_set.deadbirdsinsales THEN
        RAISE EXCEPTION 'Dead Birds are not offered for sale in this company. An owner or admin can turn it on under Products.'
            USING ERRCODE = 'P0001';
    END IF;
    IF v_role = 'BrokenEggs' AND NOT v_set.brokeneggsinsales THEN
        RAISE EXCEPTION 'Broken Eggs are not offered for sale in this company. An owner or admin can turn it on under Products.'
            USING ERRCODE = 'P0001';
    END IF;

    v_prod := fnpoultry_byproduct(p_farmid, v_role);
    PERFORM 1 FROM poultryproducts p WHERE p.poultryproductid = v_prod FOR UPDATE;   -- one sale at a time
    v_onhand := fnpoultry_byproductonhand(p_farmid, v_role);
    IF v_onhand < v_s.quantity THEN
        RAISE EXCEPTION 'Only % % available to sell.', trim_scale(GREATEST(v_onhand, 0)), fnpoultry_byproductname(v_role)
            USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, relatedid, note, createdby,
                                          salelineid, batchid, flockid, effectivedate)
    SELECT p_farmid, v_prod, 'Sale', -(l.quantity::numeric(14,3)), p_saleid,
           fnpoultry_byproductname(v_role) || ' sale', p_by, l.salelineid, v_s.batchid, v_s.flockid, v_s.saledate::date
    FROM   saleline l
    WHERE  l.saleid = p_saleid AND l.farmid = p_farmid AND l.quantity > 0;
    IF NOT FOUND THEN   -- no line yet: the sale itself
        INSERT INTO poultrystocktransactions (farmid, poultryproductid, txntype, quantity, relatedid, note, createdby,
                                              batchid, flockid, effectivedate)
        VALUES (p_farmid, v_prod, 'Sale', -(v_s.quantity::numeric(14,3)), p_saleid,
                fnpoultry_byproductname(v_role) || ' sale', p_by, v_s.batchid, v_s.flockid, v_s.saledate::date);
    END IF;
END
$f$;

-- ------------------------------------------------------ 4. the sale paths --
SELECT pg_temp.m374_patch('spsale_insert', '374: byproducts come out of their own stock',
$o$    -- Bird sale: bird-like product, not eggs.
    IF (v_p = 'birds'$o$,
$n$    -- 374: byproducts come out of their own stock -- never eggs, never live birds.
    IF public.fnpoultrysale_byproductrole(p_product) IS NOT NULL THEN
        IF COALESCE(p_quantity, 0) > 0 THEN
            PERFORM public.sppoultrybyproduct_syncforsale(p_farmid, v_newid, p_userid);
        END IF;
    -- Bird sale: bird-like product, not eggs.
    ELSIF (v_p = 'birds'$n$);

SELECT pg_temp.m374_patch('sppoultrysale_creategroup', '374: a byproduct is not an egg sale',
$o$    v_isegg   := lower(v_product) LIKE '%egg%';$o$,
$n$    v_isegg   := lower(v_product) LIKE '%egg%' AND public.fnpoultrysale_byproductrole(v_product) IS NULL;   -- 374: a byproduct is not an egg sale$n$);

SELECT pg_temp.m374_patch('sppoultrysale_creategroup', '374: byproduct lines',
$o$        IF v_isegg THEN
            PERFORM public.sppoultryeggstock_syncforsale(p_farmid, v_id, v_qty, p_userid);$o$,
$n$        IF public.fnpoultrysale_byproductrole(v_product) IS NOT NULL THEN
            PERFORM public.sppoultrybyproduct_syncforsale(p_farmid, v_id, p_userid);   -- 374: byproduct lines
        ELSIF v_isegg THEN
            PERFORM public.sppoultryeggstock_syncforsale(p_farmid, v_id, v_qty, p_userid);$n$);

SELECT pg_temp.m374_patch('sppoultrysale_setegg', '374: no egg class for a byproduct',
$o$    IF lower(COALESCE(v_product, '')) NOT LIKE '%egg%' THEN
        v_class := NULL;$o$,
$n$    IF lower(COALESCE(v_product, '')) NOT LIKE '%egg%'
       OR public.fnpoultrysale_byproductrole(v_product) IS NOT NULL THEN   -- 374: no egg class for a byproduct
        v_class := NULL;$n$);

SELECT pg_temp.m374_patch('sppoultrysale_setegg', '374: byproduct stock is not egg stock',
$o$    IF lower(COALESCE(v_product, '')) LIKE '%egg%' THEN
        PERFORM public.sppoultryeggstock_syncforsale$o$,
$n$    IF lower(COALESCE(v_product, '')) LIKE '%egg%'
       AND public.fnpoultrysale_byproductrole(v_product) IS NULL THEN   -- 374: byproduct stock is not egg stock
        PERFORM public.sppoultryeggstock_syncforsale$n$);

SELECT pg_temp.m374_patch('sppoultryeggstock_syncforsale', '374: never for a byproduct sale',
$o$    IF FOUND AND v_s.status = 'Reversed' THEN
        RETURN;
    END IF;$o$,
$n$    IF FOUND AND v_s.status = 'Reversed' THEN
        RETURN;
    END IF;
    -- 374: never for a byproduct sale -- its 'Sale' rows are on Broken Eggs / Dead Birds.
    IF public.fnpoultrysale_byproductrole((SELECT s.product FROM sale s WHERE s.saleid = p_saleid AND s.farmid = p_farmid)) IS NOT NULL THEN
        RETURN;
    END IF;$n$);

COMMIT;
