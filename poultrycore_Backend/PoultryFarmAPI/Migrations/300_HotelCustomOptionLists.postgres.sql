-- =============================================================================
-- Migration 300: Per-farm custom option lists for Hotel dropdowns (PostgreSQL)
-- =============================================================================
-- Nine dropdowns in the Hotel module offer an "Other" choice. Six of them reveal
-- a text box today, but what gets typed is written onto that one record and then
-- forgotten -- the next booking, request or work order means typing it again.
-- Two offer no box at all and store the literal word "Other". One offers the
-- choice twice over (see the hotelsupplycategories note below).
--
--   hotel-communications         Log Guest Communication -> Subject       'CommSubject'
--   hotel-guest-requests         New Guest Request       -> Type          'RequestType'
--   hotel-lost-found             Log Lost Item           -> Category      'LostFoundCategory'
--   hotel-housekeeping-schedule  Add Schedule Entry      -> Task Type     'HKTaskType'
--   hotel-menu                   Add Menu Item           -> Category      'MenuCategory'
--   hotel-inventory              Add Supply Item         -> Category      'SupplyCategory'
--   hotel-inventory              Add Supply Item         -> Name          'SupplyItemName'
--   hotel-maintenance            New Maintenance Request -> Asset / Area  'MaintenanceAsset'
--   hotel-restaurant-tables      Add Table               -> Location      'TableLocation'
--
-- The requirement is the same in all nine: let them type the value once, then
-- offer it as a normal pickable option from then on.
--
-- WHY A NEW TABLE RATHER THAN THE EXISTING HOTEL LOOKUP TABLES
-- This is the important decision in this migration, so it is worth stating
-- plainly. Six of the nine dropdowns already read from a database table:
--
--   hotelcommsubjects       (migration 234)   hoteltablelocations   (237)
--   hotelrequesttypes       (235)             hotelmaintenanceassets(239)
--   hotelhktasktypes        (236)             hotelsupplycategories (240)
--                                             hotelsupplyitems      (240)
--
-- Every one of those tables is GLOBAL. Not one of them has a farmid column --
-- they are seed lists shared by every hotel on the platform, served by
-- sphotel_*_list() functions that take no farm parameter. Writing an operator's
-- typed value into them would publish "Sauna heater" or "Pool Chemicals" to
-- every other hotel's dropdown. That is a cross-tenant data leak, not a feature.
--
-- Retrofitting farmid onto those six tables was the alternative and was
-- rejected: each is exposed as RETURNS SETOF <table>, so adding a column changes
-- the result shape of six functions at once, and HotelSetupController plus the
-- Hotel Setup pages read them. The blast radius is the whole Hotel module for no
-- gain over a table of our own.
--
-- So: one farm-scoped key/value table, and the frontend merges the global seed
-- rows with this farm's additions at render time. Same shape as migration 291,
-- which solved the identical problem for Restaurant -- deliberately a SEPARATE
-- table rather than reusing restaurantcustomoptions, because module isolation is
-- the rule in this codebase and a hotel's list has no business living in a table
-- named for restaurants.
--
-- WHAT STAYS WHERE IT IS
-- The built-in options are NOT copied in here. The six seed tables keep serving
-- their rows, and hotel-lost-found and hotel-menu keep their hardcoded arrays.
-- This table holds only what an operator adds. An empty table therefore means
-- today's exact behaviour, and editing a built-in list stays a seed/code change.
--
-- listkey is deliberately free text, as in 291: a tenth list should cost a
-- string constant, not a migration. The controller allow-lists the known keys.
-- =============================================================================

-- 1. Table --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.hotelcustomoptions (
    customoptionid   SERIAL PRIMARY KEY,
    farmid           TEXT NOT NULL,
    listkey          TEXT NOT NULL,          -- which dropdown, see header
    value            TEXT NOT NULL,          -- what the operator typed
    sortorder        INT DEFAULT 500,        -- 500 keeps custom values after the seeds
    isactive         BOOLEAN DEFAULT TRUE,
    createdat        TIMESTAMP DEFAULT NOW(),
    createdby        TEXT
);

CREATE INDEX IF NOT EXISTS ix_hotelcustomoptions_farm_list
    ON public.hotelcustomoptions (farmid, listkey)
    WHERE isactive = true;

-- One farm cannot hold "Sauna Heater" and "sauna heater" as two options. lower()
-- makes the guard case-insensitive; the insert function leans on this index
-- rather than a SELECT-then-INSERT, so a double-submit cannot race past it.
CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelcustomoptions_farm_list_value
    ON public.hotelcustomoptions (farmid, listkey, lower(value));

-- 2. Read one list ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sphotel_customoption_list(
    p_farmid  text,
    p_listkey text
)
 RETURNS SETOF hotelcustomoptions
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT * FROM hotelcustomoptions
    WHERE farmid = p_farmid
      AND listkey = p_listkey
      AND isactive = true
    ORDER BY sortorder, value;
END;
$function$;

-- 3. Read every list for a farm in one round trip -----------------------------
-- hotel-inventory renders TWO of these dropdowns in one dialog (Category and
-- Name). Fetching per-list would add a request per dropdown to a page that
-- already loads its items, categories and seed items on mount, so a caller
-- needing more than one list uses this and groups client-side.
CREATE OR REPLACE FUNCTION public.sphotel_customoption_list_all(p_farmid text)
 RETURNS SETOF hotelcustomoptions
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT * FROM hotelcustomoptions
    WHERE farmid = p_farmid
      AND isactive = true
    ORDER BY listkey, sortorder, value;
END;
$function$;

-- 4. Add one option -----------------------------------------------------------
-- Idempotent by design: saving a value the farm already has returns the existing
-- row instead of raising. The operator can press Save twice, and the same value
-- can arrive from two open dialogs; neither must surface as an error.
CREATE OR REPLACE FUNCTION public.sphotel_customoption_insert(
    p_farmid    text,
    p_listkey   text,
    p_value     text,
    p_createdby text DEFAULT NULL
)
 RETURNS SETOF hotelcustomoptions
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
    FROM hotelcustomoptions
    WHERE farmid = p_farmid
      AND listkey = btrim(p_listkey)
      AND lower(value) = lower(v_value)
    LIMIT 1;

    IF v_id IS NULL THEN
        INSERT INTO hotelcustomoptions (farmid, listkey, value, sortorder, isactive, createdby)
        VALUES (p_farmid, btrim(p_listkey), v_value, 500, true, p_createdby)
        RETURNING customoptionid INTO v_id;
    ELSE
        UPDATE hotelcustomoptions
        SET isactive = true
        WHERE customoptionid = v_id AND isactive = false;
    END IF;

    RETURN QUERY SELECT * FROM hotelcustomoptions WHERE customoptionid = v_id;
END;
$function$;

-- 5. Remove one option --------------------------------------------------------
-- Soft delete. These values are referenced only by the free-text columns they
-- were typed into (hotelguestcommunications.subject, hotelguestrequests.requesttype,
-- hotellostfounditems.category, hotelhousekeepingschedule.tasktype,
-- hotelmenuitems.category, hotelsupplies.category/name,
-- hotelmaintenancerequests.assetdescription, hotelrestauranttables.location) --
-- all plain text with no foreign key -- so removing an option never orphans a
-- record, it only stops offering the value. Keeping the row lets step 4
-- reactivate it.
CREATE OR REPLACE FUNCTION public.sphotel_customoption_delete(
    p_farmid         text,
    p_customoptionid integer
)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_rows integer;
BEGIN
    UPDATE hotelcustomoptions
    SET isactive = false
    WHERE customoptionid = p_customoptionid
      AND farmid = p_farmid;       -- farm scoping enforced here, not just in C#
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows;
END;
$function$;
