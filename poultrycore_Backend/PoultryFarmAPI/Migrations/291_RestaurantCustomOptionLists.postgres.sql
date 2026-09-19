-- =============================================================================
-- Migration 291: Per-farm custom option lists for Restaurant dropdowns (PostgreSQL)
-- =============================================================================
-- Four dropdowns in the Restaurant module offer an "Other" choice that, until
-- now, went nowhere: picking it stored the literal word "Other" and the operator
-- had no way to type what they actually meant.
--
--   restaurant-inventory   Add Ingredient -> Category      (listkey 'IngredientCategory')
--   restaurant-inventory   Log Waste      -> Reason        (listkey 'WasteReason')
--   restaurant-reservations New Reservation -> Occasion    (listkey 'ReservationOccasion')
--   restaurant-setup       Profile        -> Cuisine Type  (listkey 'CuisineType')
--
-- The requirement is the same in all four: let them type the value once, then
-- offer it as a normal pickable option from then on.
--
-- WHY ONE GENERIC TABLE RATHER THAN FOUR
-- Migration 287 solved this same problem for menu item names, but it had to add
-- farm scoping to an EXISTING shared seed table (restaurantmenuitemnames, which
-- Hotel Setup also reads). None of the four lists above exist in the database at
-- all — they are hardcoded string arrays in the page files. So there is no table
-- to retrofit and no Hotel coupling to preserve. A single key-value table serves
-- all four, and a fifth list later costs a string constant rather than a
-- migration. `listkey` is deliberately free text for that reason.
--
-- WHAT STAYS IN THE FRONTEND
-- The built-in options (Proteins, Dairy, Spoilage, Birthday, Italian, ...) are
-- NOT seeded here. They remain the hardcoded arrays the pages already ship, and
-- this table holds only what an operator adds. That keeps the two sources
-- independent: editing a built-in list is still a code change, this table never
-- needs backfilling, and an empty table means today's exact behaviour.
--
-- SCOPING
-- farmid is NOT NULL — every row belongs to exactly one restaurant. There is no
-- system-wide bucket, unlike 287. Nothing outside the Restaurant module reads
-- this table, so there is no Hotel compatibility requirement here.
-- =============================================================================

-- 1. Table --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.restaurantcustomoptions (
    customoptionid   SERIAL PRIMARY KEY,
    farmid           TEXT NOT NULL,
    listkey          TEXT NOT NULL,          -- which dropdown, see header
    value            TEXT NOT NULL,          -- what the operator typed
    sortorder        INT DEFAULT 500,        -- 500 keeps custom values after built-ins
    isactive         BOOLEAN DEFAULT TRUE,
    createdat        TIMESTAMP DEFAULT NOW(),
    createdby        TEXT
);

CREATE INDEX IF NOT EXISTS ix_restaurantcustomoptions_farm_list
    ON public.restaurantcustomoptions (farmid, listkey)
    WHERE isactive = true;

-- Same farm cannot hold "Goat Meat" and "goat meat" as two separate options.
-- lower() makes the guard case-insensitive; the proc below relies on this index
-- rather than a SELECT-then-INSERT, so a double-submit cannot race past it.
CREATE UNIQUE INDEX IF NOT EXISTS ux_restaurantcustomoptions_farm_list_value
    ON public.restaurantcustomoptions (farmid, listkey, lower(value));

-- 2. Read one list ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sprestaurant_customoption_list(
    p_farmid  text,
    p_listkey text
)
 RETURNS SETOF restaurantcustomoptions
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT * FROM restaurantcustomoptions
    WHERE farmid = p_farmid
      AND listkey = p_listkey
      AND isactive = true
    ORDER BY sortorder, value;
END;
$function$;

-- 3. Read every list for a farm in one round trip -----------------------------
-- The inventory page needs two lists (IngredientCategory, WasteReason) to render
-- one screen. Fetching per-list would mean one request per dropdown on a page
-- that is already doing seven calls on mount, so callers that need more than one
-- list use this and group client-side.
CREATE OR REPLACE FUNCTION public.sprestaurant_customoption_list_all(p_farmid text)
 RETURNS SETOF restaurantcustomoptions
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT * FROM restaurantcustomoptions
    WHERE farmid = p_farmid
      AND isactive = true
    ORDER BY listkey, sortorder, value;
END;
$function$;

-- 4. Add one option -----------------------------------------------------------
-- Idempotent by design: saving a value the farm already has returns the existing
-- row instead of raising. The UI saves on blur as well as on submit, so the same
-- value arrives twice routinely and that must not surface as an error.
CREATE OR REPLACE FUNCTION public.sprestaurant_customoption_insert(
    p_farmid    text,
    p_listkey   text,
    p_value     text,
    p_createdby text DEFAULT NULL
)
 RETURNS SETOF restaurantcustomoptions
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id    integer;
    v_value text := btrim(p_value);
BEGIN
    IF v_value IS NULL OR v_value = '' THEN
        RAISE EXCEPTION 'Value cannot be empty';
    END IF;
    IF p_listkey IS NULL OR btrim(p_listkey) = '' THEN
        RAISE EXCEPTION 'listkey is required';
    END IF;

    -- Reactivate rather than insert if this value was soft-deleted earlier,
    -- otherwise the unique index would reject re-adding something the operator
    -- removed by mistake.
    SELECT customoptionid INTO v_id
    FROM restaurantcustomoptions
    WHERE farmid = p_farmid
      AND listkey = btrim(p_listkey)
      AND lower(value) = lower(v_value)
    LIMIT 1;

    IF v_id IS NULL THEN
        INSERT INTO restaurantcustomoptions (farmid, listkey, value, sortorder, isactive, createdby)
        VALUES (p_farmid, btrim(p_listkey), v_value, 500, true, p_createdby)
        RETURNING customoptionid INTO v_id;
    ELSE
        UPDATE restaurantcustomoptions
        SET isactive = true
        WHERE customoptionid = v_id AND isactive = false;
    END IF;

    RETURN QUERY SELECT * FROM restaurantcustomoptions WHERE customoptionid = v_id;
END;
$function$;

-- 5. Remove one option -------------------------------------------------------
-- Soft delete. Rows are referenced only by the free-text columns they were typed
-- into (restaurantingredients.category, restaurantwastelog.reason,
-- restaurantreservations.occasion, restaurantprofile.cuisinetype) — all plain
-- TEXT with no foreign key — so removing an option never orphans existing
-- records, it only stops offering the value. Keeping the row lets step 4
-- reactivate it.
CREATE OR REPLACE FUNCTION public.sprestaurant_customoption_delete(
    p_farmid         text,
    p_customoptionid integer
)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_rows integer;
BEGIN
    UPDATE restaurantcustomoptions
    SET isactive = false
    WHERE customoptionid = p_customoptionid
      AND farmid = p_farmid;       -- farm scoping enforced here, not just in C#
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows;
END;
$function$;
