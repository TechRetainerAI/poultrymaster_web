-- =============================================================================
-- Migration 287: Custom (per-farm) Restaurant Menu Item Names   (PostgreSQL)
-- =============================================================================
-- Lets a restaurant pick "Other" on the Add Menu Item form, type a dish name,
-- and have that name come back as a normal pickable option next time.
--
-- WHY THE farmid COLUMN
-- restaurantmenuitemnames started life as a system-wide seed list. It is read by
-- BOTH the Restaurant module and Hotel Setup (Business/HotelSetupService.cs:164,
-- via sprestaurant_menuitemname_list). If custom names were simply appended to
-- the table, one restaurant's invented dish would surface in every other
-- restaurant's dropdown AND in Hotel's. So rows are scoped:
--     farmid IS NULL  -> the shared system seed list (exactly today's 45 rows)
--     farmid = '<id>' -> that one farm's custom additions
--
-- COMPATIBILITY WITH HOTEL — deliberate, do not "simplify" away:
-- sprestaurant_menuitemname_list() is left in place and now filters to
-- farmid IS NULL. Every pre-existing row gets NULL from the ALTER below, so the
-- proc returns byte-for-byte what it returned before and Hotel Setup is
-- unaffected. It still RETURNS SETOF restaurantmenuitemnames, which now carries
-- one extra column; HotelSetupService reads columns BY NAME, so the extra
-- column is ignored. Never rename or drop code/description/category/sortorder/
-- isactive on this table — that WOULD break Hotel Setup.
-- =============================================================================

-- 1. Farm scoping -------------------------------------------------------------
ALTER TABLE public.restaurantmenuitemnames
    ADD COLUMN IF NOT EXISTS farmid character varying(100) NULL;

-- 2. Uniqueness -------------------------------------------------------------
-- `code` was globally UNIQUE. Two different farms must be able to hold their own
-- rows without colliding, so uniqueness becomes (farmid, code). COALESCE keeps
-- the NULL system rows in one bucket, since NULL <> NULL in a plain unique index.
ALTER TABLE public.restaurantmenuitemnames
    DROP CONSTRAINT IF EXISTS restaurantmenuitemnames_code_key;

CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantmenuitemnames_farm_code
    ON public.restaurantmenuitemnames (COALESCE(farmid, ''), code);

-- Stops the same farm adding "Jollof Rice" twice with different capitalisation.
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantmenuitemnames_farm_desc
    ON public.restaurantmenuitemnames (COALESCE(farmid, ''), lower(description));

-- 3. System list — unchanged results, now explicitly system-only --------------
CREATE OR REPLACE FUNCTION public.sprestaurant_menuitemname_list()
 RETURNS SETOF restaurantmenuitemnames
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT * FROM restaurantmenuitemnames
    WHERE isactive = true AND farmid IS NULL
    ORDER BY sortorder, description;
END;
$function$;

-- 4. Restaurant list — system seeds PLUS this farm's own names ----------------
CREATE OR REPLACE FUNCTION public.sprestaurant_menuitemname_list_for_farm(p_farmid text)
 RETURNS SETOF restaurantmenuitemnames
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT * FROM restaurantmenuitemnames
    WHERE isactive = true
      AND (farmid IS NULL OR farmid = p_farmid)
    ORDER BY sortorder, description;
END;
$function$;

-- 5. Add one custom name for a farm ------------------------------------------
-- Idempotent: adding a name the farm already has (or one already in the system
-- seed list) returns the existing row instead of erroring, so a double-submit or
-- a user retyping "Jollof Rice" is harmless.
CREATE OR REPLACE FUNCTION public.sprestaurant_menuitemname_insert(
    p_farmid      text,
    p_description text,
    p_category    text DEFAULT NULL
)
 RETURNS SETOF restaurantmenuitemnames
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id   integer;
    v_desc text := btrim(p_description);
BEGIN
    IF v_desc IS NULL OR v_desc = '' THEN
        RAISE EXCEPTION 'Item name cannot be empty';
    END IF;

    -- Already available to this farm (its own, or a system seed)? Hand it back.
    SELECT restaurantmenuitemnameid INTO v_id
    FROM restaurantmenuitemnames
    WHERE lower(description) = lower(v_desc)
      AND (farmid IS NULL OR farmid = p_farmid)
    ORDER BY farmid NULLS FIRST
    LIMIT 1;

    IF v_id IS NULL THEN
        -- code is NOT NULL and capped at 10 chars. Take the id from the sequence
        -- FIRST so code can be derived in the same INSERT: a placeholder code plus
        -- a follow-up UPDATE would collide under concurrency, and would leave a
        -- stale blocking row if the transaction died between the two statements.
        v_id := nextval(pg_get_serial_sequence('public.restaurantmenuitemnames',
                                               'restaurantmenuitemnameid'));

        INSERT INTO restaurantmenuitemnames
               (restaurantmenuitemnameid, code, description, category, sortorder, isactive, farmid)
        VALUES (v_id, 'C' || v_id::text, v_desc,
                NULLIF(btrim(coalesce(p_category, '')), ''), 500, true, p_farmid);
    END IF;

    RETURN QUERY SELECT * FROM restaurantmenuitemnames WHERE restaurantmenuitemnameid = v_id;
END;
$function$;
