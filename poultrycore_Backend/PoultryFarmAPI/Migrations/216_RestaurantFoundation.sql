-- Migration 216: Restaurant Management System — Foundation + Menu Management
-- Applied: 2026-08-30
-- Phase R1: Restaurant profile, menu categories, menu items, modifier groups,
--           modifiers, combos, menu schedules, item tags

-- =============================================================================
-- 1. RESTAURANT PROFILES
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantprofiles (
    restaurantprofileid  SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    restaurantname       TEXT NOT NULL,
    address              TEXT,
    city                 TEXT,
    country              TEXT,
    phone                TEXT,
    email                TEXT,
    cuisinetype          TEXT,           -- e.g. 'Italian', 'Chinese', 'Multi-Cuisine'
    servicetypes         TEXT,           -- comma-separated: 'DineIn,Takeaway,Delivery,DriveThrough'
    openingtime          TEXT DEFAULT '08:00',
    closingtime          TEXT DEFAULT '22:00',
    defaultcurrency      TEXT DEFAULT 'GHS',
    taxrate              NUMERIC(5,2) DEFAULT 0,
    servicechargerate    NUMERIC(5,2) DEFAULT 0,
    timezone             TEXT,
    logourl              TEXT,
    description          TEXT,
    seatingcapacity      INT DEFAULT 0,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantprofiles_farm ON restaurantprofiles(farmid);

-- =============================================================================
-- 2. MENU CATEGORIES
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantmenucategories (
    menucategoryid       SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    parentcategoryid     INT REFERENCES restaurantmenucategories(menucategoryid) ON DELETE SET NULL,
    name                 TEXT NOT NULL,
    description          TEXT,
    imageurl             TEXT,
    sortorder            INT DEFAULT 0,
    isactive             BOOLEAN DEFAULT TRUE,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantmenucategories_farm ON restaurantmenucategories(farmid);

-- =============================================================================
-- 3. MENU ITEMS
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantmenuitems (
    menuitemid           SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    menucategoryid       INT REFERENCES restaurantmenucategories(menucategoryid) ON DELETE SET NULL,
    name                 TEXT NOT NULL,
    description          TEXT,
    price                NUMERIC(12,2) NOT NULL DEFAULT 0,
    costprice            NUMERIC(12,2) DEFAULT 0,
    imageurl             TEXT,
    preptime             INT DEFAULT 0,           -- minutes
    calories             INT,
    allergens            TEXT,                     -- comma-separated
    spicylevel           INT DEFAULT 0,            -- 0-5
    isvegetarian         BOOLEAN DEFAULT FALSE,
    isvegan              BOOLEAN DEFAULT FALSE,
    isglutenfree         BOOLEAN DEFAULT FALSE,
    ishalal              BOOLEAN DEFAULT FALSE,
    iskosher             BOOLEAN DEFAULT FALSE,
    isavailable          BOOLEAN DEFAULT TRUE,     -- 86'd toggle
    isactive             BOOLEAN DEFAULT TRUE,
    sortorder            INT DEFAULT 0,
    sku                  TEXT,
    barcode              TEXT,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantmenuitems_farm ON restaurantmenuitems(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantmenuitems_category ON restaurantmenuitems(farmid, menucategoryid);

-- =============================================================================
-- 4. MODIFIER GROUPS (e.g. "Choose Size", "Extra Toppings")
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantmodifiergroups (
    modifiergroupid      SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    name                 TEXT NOT NULL,
    description          TEXT,
    isrequired           BOOLEAN DEFAULT FALSE,    -- must customer pick one?
    minselections        INT DEFAULT 0,
    maxselections        INT DEFAULT 1,
    sortorder            INT DEFAULT 0,
    isactive             BOOLEAN DEFAULT TRUE,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantmodifiergroups_farm ON restaurantmodifiergroups(farmid);

-- =============================================================================
-- 5. MODIFIERS (individual options within a group)
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantmodifiers (
    modifierid           SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    modifiergroupid      INT NOT NULL REFERENCES restaurantmodifiergroups(modifiergroupid) ON DELETE CASCADE,
    name                 TEXT NOT NULL,
    priceadjustment      NUMERIC(12,2) DEFAULT 0,  -- extra charge
    isdefault            BOOLEAN DEFAULT FALSE,
    isavailable          BOOLEAN DEFAULT TRUE,
    sortorder            INT DEFAULT 0,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantmodifiers_group ON restaurantmodifiers(farmid, modifiergroupid);

-- =============================================================================
-- 6. MENU ITEM <-> MODIFIER GROUP JUNCTION
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantmenuitemmodifiergroups (
    menuitemmodifiergroupid SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    menuitemid           INT NOT NULL REFERENCES restaurantmenuitems(menuitemid) ON DELETE CASCADE,
    modifiergroupid      INT NOT NULL REFERENCES restaurantmodifiergroups(modifiergroupid) ON DELETE CASCADE,
    sortorder            INT DEFAULT 0,
    UNIQUE(farmid, menuitemid, modifiergroupid)
);
CREATE INDEX IF NOT EXISTS ix_restaurantmenuitemmodgroups_item ON restaurantmenuitemmodifiergroups(farmid, menuitemid);

-- =============================================================================
-- 7. COMBOS / MEAL DEALS
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantcombos (
    comboid              SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    name                 TEXT NOT NULL,
    description          TEXT,
    price                NUMERIC(12,2) NOT NULL DEFAULT 0,
    imageurl             TEXT,
    isactive             BOOLEAN DEFAULT TRUE,
    sortorder            INT DEFAULT 0,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantcombos_farm ON restaurantcombos(farmid);

CREATE TABLE IF NOT EXISTS restaurantcomboitems (
    comboitemid          SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    comboid              INT NOT NULL REFERENCES restaurantcombos(comboid) ON DELETE CASCADE,
    menuitemid           INT REFERENCES restaurantmenuitems(menuitemid) ON DELETE SET NULL,
    menucategoryid       INT REFERENCES restaurantmenucategories(menucategoryid) ON DELETE SET NULL,
    quantity             INT DEFAULT 1,
    sortorder            INT DEFAULT 0
);
CREATE INDEX IF NOT EXISTS ix_restaurantcomboitems_combo ON restaurantcomboitems(farmid, comboid);

-- =============================================================================
-- 8. MENU SCHEDULES (time-based menus)
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantmenuschedules (
    menuscheduleid       SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    name                 TEXT NOT NULL,          -- e.g. 'Breakfast', 'Lunch', 'Dinner', 'Happy Hour'
    starttime            TEXT NOT NULL,          -- '06:00'
    endtime              TEXT NOT NULL,          -- '11:00'
    daysofweek           TEXT,                   -- comma-separated: 'Mon,Tue,Wed,Thu,Fri,Sat,Sun'
    isactive             BOOLEAN DEFAULT TRUE,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantmenuschedules_farm ON restaurantmenuschedules(farmid);

-- Junction: which items belong to which schedule
CREATE TABLE IF NOT EXISTS restaurantmenuscheduleitems (
    menuscheduleitemid   SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    menuscheduleid       INT NOT NULL REFERENCES restaurantmenuschedules(menuscheduleid) ON DELETE CASCADE,
    menuitemid           INT NOT NULL REFERENCES restaurantmenuitems(menuitemid) ON DELETE CASCADE,
    overrideprice        NUMERIC(12,2),         -- optional price override for this schedule
    UNIQUE(farmid, menuscheduleid, menuitemid)
);
CREATE INDEX IF NOT EXISTS ix_restaurantmenuscheditems_sched ON restaurantmenuscheduleitems(farmid, menuscheduleid);

-- =============================================================================
-- 9. ITEM TAGS (flexible tagging)
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantitemtags (
    itemtagid            SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    menuitemid           INT NOT NULL REFERENCES restaurantmenuitems(menuitemid) ON DELETE CASCADE,
    tag                  TEXT NOT NULL,          -- e.g. 'Popular', 'New', 'Chef Special', 'Spicy'
    UNIQUE(farmid, menuitemid, tag)
);
CREATE INDEX IF NOT EXISTS ix_restaurantitemtags_item ON restaurantitemtags(farmid, menuitemid);

-- =============================================================================
-- STORED PROCEDURES: RESTAURANT PROFILE
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_profile_get(p_farmid TEXT)
RETURNS TABLE (
    restaurantprofileid INT, farmid TEXT, restaurantname TEXT, address TEXT,
    city TEXT, country TEXT, phone TEXT, email TEXT, cuisinetype TEXT,
    servicetypes TEXT, openingtime TEXT, closingtime TEXT, defaultcurrency TEXT,
    taxrate NUMERIC, servicechargerate NUMERIC, timezone TEXT, logourl TEXT,
    description TEXT, seatingcapacity INT, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT r.restaurantprofileid, r.farmid, r.restaurantname, r.address,
           r.city, r.country, r.phone, r.email, r.cuisinetype,
           r.servicetypes, r.openingtime, r.closingtime, r.defaultcurrency,
           r.taxrate, r.servicechargerate, r.timezone, r.logourl,
           r.description, r.seatingcapacity, r.createdat, r.updatedat
    FROM restaurantprofiles r
    WHERE r.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_profile_upsert(
    p_farmid TEXT, p_restaurantname TEXT, p_address TEXT, p_city TEXT,
    p_country TEXT, p_phone TEXT, p_email TEXT, p_cuisinetype TEXT,
    p_servicetypes TEXT, p_openingtime TEXT, p_closingtime TEXT,
    p_defaultcurrency TEXT, p_taxrate NUMERIC, p_servicechargerate NUMERIC,
    p_timezone TEXT, p_logourl TEXT, p_description TEXT, p_seatingcapacity INT
)
RETURNS TABLE (
    restaurantprofileid INT, farmid TEXT, restaurantname TEXT, address TEXT,
    city TEXT, country TEXT, phone TEXT, email TEXT, cuisinetype TEXT,
    servicetypes TEXT, openingtime TEXT, closingtime TEXT, defaultcurrency TEXT,
    taxrate NUMERIC, servicechargerate NUMERIC, timezone TEXT, logourl TEXT,
    description TEXT, seatingcapacity INT, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
DECLARE v_id INT;
BEGIN
    SELECT r.restaurantprofileid INTO v_id FROM restaurantprofiles r WHERE r.farmid = p_farmid;
    IF v_id IS NOT NULL THEN
        UPDATE restaurantprofiles SET
            restaurantname = p_restaurantname, address = p_address, city = p_city,
            country = p_country, phone = p_phone, email = p_email,
            cuisinetype = p_cuisinetype, servicetypes = p_servicetypes,
            openingtime = p_openingtime, closingtime = p_closingtime,
            defaultcurrency = p_defaultcurrency, taxrate = p_taxrate,
            servicechargerate = p_servicechargerate, timezone = p_timezone,
            logourl = p_logourl, description = p_description,
            seatingcapacity = p_seatingcapacity, updatedat = NOW()
        WHERE restaurantprofiles.restaurantprofileid = v_id;
    ELSE
        INSERT INTO restaurantprofiles (farmid, restaurantname, address, city, country, phone, email,
            cuisinetype, servicetypes, openingtime, closingtime, defaultcurrency, taxrate,
            servicechargerate, timezone, logourl, description, seatingcapacity)
        VALUES (p_farmid, p_restaurantname, p_address, p_city, p_country, p_phone, p_email,
            p_cuisinetype, p_servicetypes, p_openingtime, p_closingtime, p_defaultcurrency,
            p_taxrate, p_servicechargerate, p_timezone, p_logourl, p_description, p_seatingcapacity)
        RETURNING restaurantprofiles.restaurantprofileid INTO v_id;
    END IF;
    RETURN QUERY SELECT r.restaurantprofileid, r.farmid, r.restaurantname, r.address,
        r.city, r.country, r.phone, r.email, r.cuisinetype, r.servicetypes,
        r.openingtime, r.closingtime, r.defaultcurrency, r.taxrate, r.servicechargerate,
        r.timezone, r.logourl, r.description, r.seatingcapacity, r.createdat, r.updatedat
    FROM restaurantprofiles r WHERE r.restaurantprofileid = v_id;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: MENU CATEGORIES
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_menucategory_list(p_farmid TEXT)
RETURNS TABLE (
    menucategoryid INT, farmid TEXT, parentcategoryid INT, name TEXT,
    description TEXT, imageurl TEXT, sortorder INT, isactive BOOLEAN,
    createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT c.menucategoryid, c.farmid, c.parentcategoryid, c.name,
           c.description, c.imageurl, c.sortorder, c.isactive,
           c.createdat, c.updatedat
    FROM restaurantmenucategories c
    WHERE c.farmid = p_farmid
    ORDER BY c.sortorder, c.name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_menucategory_get(p_id INT, p_farmid TEXT)
RETURNS TABLE (
    menucategoryid INT, farmid TEXT, parentcategoryid INT, name TEXT,
    description TEXT, imageurl TEXT, sortorder INT, isactive BOOLEAN,
    createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT c.menucategoryid, c.farmid, c.parentcategoryid, c.name,
           c.description, c.imageurl, c.sortorder, c.isactive,
           c.createdat, c.updatedat
    FROM restaurantmenucategories c
    WHERE c.menucategoryid = p_id AND c.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_menucategory_insert(
    p_farmid TEXT, p_parentcategoryid INT, p_name TEXT, p_description TEXT,
    p_imageurl TEXT, p_sortorder INT, p_isactive BOOLEAN
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantmenucategories (farmid, parentcategoryid, name, description, imageurl, sortorder, isactive)
    VALUES (p_farmid, p_parentcategoryid, p_name, p_description, p_imageurl, p_sortorder, p_isactive)
    RETURNING menucategoryid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_menucategory_update(
    p_id INT, p_farmid TEXT, p_parentcategoryid INT, p_name TEXT,
    p_description TEXT, p_imageurl TEXT, p_sortorder INT, p_isactive BOOLEAN
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantmenucategories SET
        parentcategoryid = p_parentcategoryid, name = p_name, description = p_description,
        imageurl = p_imageurl, sortorder = p_sortorder, isactive = p_isactive, updatedat = NOW()
    WHERE menucategoryid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_menucategory_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantmenucategories WHERE menucategoryid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: MENU ITEMS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_menuitem_list(p_farmid TEXT, p_categoryid INT DEFAULT NULL)
RETURNS TABLE (
    menuitemid INT, farmid TEXT, menucategoryid INT, categoryname TEXT,
    name TEXT, description TEXT, price NUMERIC, costprice NUMERIC,
    imageurl TEXT, preptime INT, calories INT, allergens TEXT,
    spicylevel INT, isvegetarian BOOLEAN, isvegan BOOLEAN, isglutenfree BOOLEAN,
    ishalal BOOLEAN, iskosher BOOLEAN, isavailable BOOLEAN, isactive BOOLEAN,
    sortorder INT, sku TEXT, barcode TEXT, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT i.menuitemid, i.farmid, i.menucategoryid,
           COALESCE(c.name, '') AS categoryname,
           i.name, i.description, i.price, i.costprice,
           i.imageurl, i.preptime, i.calories, i.allergens,
           i.spicylevel, i.isvegetarian, i.isvegan, i.isglutenfree,
           i.ishalal, i.iskosher, i.isavailable, i.isactive,
           i.sortorder, i.sku, i.barcode, i.createdat, i.updatedat
    FROM restaurantmenuitems i
    LEFT JOIN restaurantmenucategories c ON c.menucategoryid = i.menucategoryid AND c.farmid = i.farmid
    WHERE i.farmid = p_farmid
      AND (p_categoryid IS NULL OR i.menucategoryid = p_categoryid)
    ORDER BY i.sortorder, i.name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_menuitem_get(p_id INT, p_farmid TEXT)
RETURNS TABLE (
    menuitemid INT, farmid TEXT, menucategoryid INT, categoryname TEXT,
    name TEXT, description TEXT, price NUMERIC, costprice NUMERIC,
    imageurl TEXT, preptime INT, calories INT, allergens TEXT,
    spicylevel INT, isvegetarian BOOLEAN, isvegan BOOLEAN, isglutenfree BOOLEAN,
    ishalal BOOLEAN, iskosher BOOLEAN, isavailable BOOLEAN, isactive BOOLEAN,
    sortorder INT, sku TEXT, barcode TEXT, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT i.menuitemid, i.farmid, i.menucategoryid,
           COALESCE(c.name, '') AS categoryname,
           i.name, i.description, i.price, i.costprice,
           i.imageurl, i.preptime, i.calories, i.allergens,
           i.spicylevel, i.isvegetarian, i.isvegan, i.isglutenfree,
           i.ishalal, i.iskosher, i.isavailable, i.isactive,
           i.sortorder, i.sku, i.barcode, i.createdat, i.updatedat
    FROM restaurantmenuitems i
    LEFT JOIN restaurantmenucategories c ON c.menucategoryid = i.menucategoryid AND c.farmid = i.farmid
    WHERE i.menuitemid = p_id AND i.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_menuitem_insert(
    p_farmid TEXT, p_menucategoryid INT, p_name TEXT, p_description TEXT,
    p_price NUMERIC, p_costprice NUMERIC, p_imageurl TEXT, p_preptime INT,
    p_calories INT, p_allergens TEXT, p_spicylevel INT,
    p_isvegetarian BOOLEAN, p_isvegan BOOLEAN, p_isglutenfree BOOLEAN,
    p_ishalal BOOLEAN, p_iskosher BOOLEAN, p_isavailable BOOLEAN,
    p_isactive BOOLEAN, p_sortorder INT, p_sku TEXT, p_barcode TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantmenuitems (farmid, menucategoryid, name, description, price, costprice,
        imageurl, preptime, calories, allergens, spicylevel, isvegetarian, isvegan, isglutenfree,
        ishalal, iskosher, isavailable, isactive, sortorder, sku, barcode)
    VALUES (p_farmid, p_menucategoryid, p_name, p_description, p_price, p_costprice,
        p_imageurl, p_preptime, p_calories, p_allergens, p_spicylevel, p_isvegetarian,
        p_isvegan, p_isglutenfree, p_ishalal, p_iskosher, p_isavailable, p_isactive,
        p_sortorder, p_sku, p_barcode)
    RETURNING menuitemid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_menuitem_update(
    p_id INT, p_farmid TEXT, p_menucategoryid INT, p_name TEXT, p_description TEXT,
    p_price NUMERIC, p_costprice NUMERIC, p_imageurl TEXT, p_preptime INT,
    p_calories INT, p_allergens TEXT, p_spicylevel INT,
    p_isvegetarian BOOLEAN, p_isvegan BOOLEAN, p_isglutenfree BOOLEAN,
    p_ishalal BOOLEAN, p_iskosher BOOLEAN, p_isavailable BOOLEAN,
    p_isactive BOOLEAN, p_sortorder INT, p_sku TEXT, p_barcode TEXT
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantmenuitems SET
        menucategoryid = p_menucategoryid, name = p_name, description = p_description,
        price = p_price, costprice = p_costprice, imageurl = p_imageurl, preptime = p_preptime,
        calories = p_calories, allergens = p_allergens, spicylevel = p_spicylevel,
        isvegetarian = p_isvegetarian, isvegan = p_isvegan, isglutenfree = p_isglutenfree,
        ishalal = p_ishalal, iskosher = p_iskosher, isavailable = p_isavailable,
        isactive = p_isactive, sortorder = p_sortorder, sku = p_sku, barcode = p_barcode,
        updatedat = NOW()
    WHERE menuitemid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_menuitem_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantmenuitems WHERE menuitemid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Toggle availability (86'd)
CREATE OR REPLACE FUNCTION sprestaurant_menuitem_toggle_available(p_id INT, p_farmid TEXT, p_isavailable BOOLEAN)
RETURNS VOID AS $$
BEGIN
    UPDATE restaurantmenuitems SET isavailable = p_isavailable, updatedat = NOW()
    WHERE menuitemid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: MODIFIER GROUPS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_modifiergroup_list(p_farmid TEXT)
RETURNS TABLE (
    modifiergroupid INT, farmid TEXT, name TEXT, description TEXT,
    isrequired BOOLEAN, minselections INT, maxselections INT,
    sortorder INT, isactive BOOLEAN, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT g.modifiergroupid, g.farmid, g.name, g.description,
           g.isrequired, g.minselections, g.maxselections,
           g.sortorder, g.isactive, g.createdat, g.updatedat
    FROM restaurantmodifiergroups g
    WHERE g.farmid = p_farmid
    ORDER BY g.sortorder, g.name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_modifiergroup_insert(
    p_farmid TEXT, p_name TEXT, p_description TEXT, p_isrequired BOOLEAN,
    p_minselections INT, p_maxselections INT, p_sortorder INT, p_isactive BOOLEAN
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantmodifiergroups (farmid, name, description, isrequired, minselections, maxselections, sortorder, isactive)
    VALUES (p_farmid, p_name, p_description, p_isrequired, p_minselections, p_maxselections, p_sortorder, p_isactive)
    RETURNING modifiergroupid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_modifiergroup_update(
    p_id INT, p_farmid TEXT, p_name TEXT, p_description TEXT, p_isrequired BOOLEAN,
    p_minselections INT, p_maxselections INT, p_sortorder INT, p_isactive BOOLEAN
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantmodifiergroups SET
        name = p_name, description = p_description, isrequired = p_isrequired,
        minselections = p_minselections, maxselections = p_maxselections,
        sortorder = p_sortorder, isactive = p_isactive, updatedat = NOW()
    WHERE modifiergroupid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_modifiergroup_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantmodifiergroups WHERE modifiergroupid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: MODIFIERS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_modifier_list(p_farmid TEXT, p_groupid INT DEFAULT NULL)
RETURNS TABLE (
    modifierid INT, farmid TEXT, modifiergroupid INT, groupname TEXT,
    name TEXT, priceadjustment NUMERIC, isdefault BOOLEAN,
    isavailable BOOLEAN, sortorder INT, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT m.modifierid, m.farmid, m.modifiergroupid,
           COALESCE(g.name, '') AS groupname,
           m.name, m.priceadjustment, m.isdefault,
           m.isavailable, m.sortorder, m.createdat, m.updatedat
    FROM restaurantmodifiers m
    LEFT JOIN restaurantmodifiergroups g ON g.modifiergroupid = m.modifiergroupid AND g.farmid = m.farmid
    WHERE m.farmid = p_farmid
      AND (p_groupid IS NULL OR m.modifiergroupid = p_groupid)
    ORDER BY m.sortorder, m.name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_modifier_insert(
    p_farmid TEXT, p_modifiergroupid INT, p_name TEXT, p_priceadjustment NUMERIC,
    p_isdefault BOOLEAN, p_isavailable BOOLEAN, p_sortorder INT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantmodifiers (farmid, modifiergroupid, name, priceadjustment, isdefault, isavailable, sortorder)
    VALUES (p_farmid, p_modifiergroupid, p_name, p_priceadjustment, p_isdefault, p_isavailable, p_sortorder)
    RETURNING modifierid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_modifier_update(
    p_id INT, p_farmid TEXT, p_modifiergroupid INT, p_name TEXT,
    p_priceadjustment NUMERIC, p_isdefault BOOLEAN, p_isavailable BOOLEAN, p_sortorder INT
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantmodifiers SET
        modifiergroupid = p_modifiergroupid, name = p_name, priceadjustment = p_priceadjustment,
        isdefault = p_isdefault, isavailable = p_isavailable, sortorder = p_sortorder, updatedat = NOW()
    WHERE modifierid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_modifier_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantmodifiers WHERE modifierid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: MENU ITEM <-> MODIFIER GROUP ASSIGNMENT
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_menuitem_modifiergroups_list(p_menuitemid INT, p_farmid TEXT)
RETURNS TABLE (
    menuitemmodifiergroupid INT, farmid TEXT, menuitemid INT,
    modifiergroupid INT, groupname TEXT, isrequired BOOLEAN,
    minselections INT, maxselections INT, sortorder INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT j.menuitemmodifiergroupid, j.farmid, j.menuitemid,
           j.modifiergroupid, g.name AS groupname, g.isrequired,
           g.minselections, g.maxselections, j.sortorder
    FROM restaurantmenuitemmodifiergroups j
    JOIN restaurantmodifiergroups g ON g.modifiergroupid = j.modifiergroupid AND g.farmid = j.farmid
    WHERE j.menuitemid = p_menuitemid AND j.farmid = p_farmid
    ORDER BY j.sortorder;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_menuitem_modifiergroup_assign(
    p_farmid TEXT, p_menuitemid INT, p_modifiergroupid INT, p_sortorder INT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantmenuitemmodifiergroups (farmid, menuitemid, modifiergroupid, sortorder)
    VALUES (p_farmid, p_menuitemid, p_modifiergroupid, p_sortorder)
    ON CONFLICT (farmid, menuitemid, modifiergroupid) DO UPDATE SET sortorder = p_sortorder
    RETURNING menuitemmodifiergroupid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_menuitem_modifiergroup_unassign(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantmenuitemmodifiergroups WHERE menuitemmodifiergroupid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: COMBOS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_combo_list(p_farmid TEXT)
RETURNS TABLE (
    comboid INT, farmid TEXT, name TEXT, description TEXT,
    price NUMERIC, imageurl TEXT, isactive BOOLEAN, sortorder INT,
    createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT cb.comboid, cb.farmid, cb.name, cb.description,
           cb.price, cb.imageurl, cb.isactive, cb.sortorder,
           cb.createdat, cb.updatedat
    FROM restaurantcombos cb
    WHERE cb.farmid = p_farmid
    ORDER BY cb.sortorder, cb.name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_combo_insert(
    p_farmid TEXT, p_name TEXT, p_description TEXT, p_price NUMERIC,
    p_imageurl TEXT, p_isactive BOOLEAN, p_sortorder INT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantcombos (farmid, name, description, price, imageurl, isactive, sortorder)
    VALUES (p_farmid, p_name, p_description, p_price, p_imageurl, p_isactive, p_sortorder)
    RETURNING comboid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_combo_update(
    p_id INT, p_farmid TEXT, p_name TEXT, p_description TEXT,
    p_price NUMERIC, p_imageurl TEXT, p_isactive BOOLEAN, p_sortorder INT
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantcombos SET
        name = p_name, description = p_description, price = p_price,
        imageurl = p_imageurl, isactive = p_isactive, sortorder = p_sortorder, updatedat = NOW()
    WHERE comboid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_combo_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantcombos WHERE comboid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Combo items CRUD
CREATE OR REPLACE FUNCTION sprestaurant_comboitem_list(p_comboid INT, p_farmid TEXT)
RETURNS TABLE (
    comboitemid INT, farmid TEXT, comboid INT, menuitemid INT,
    menuitemname TEXT, menucategoryid INT, categoryname TEXT,
    quantity INT, sortorder INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT ci.comboitemid, ci.farmid, ci.comboid, ci.menuitemid,
           COALESCE(mi.name, '') AS menuitemname,
           ci.menucategoryid, COALESCE(mc.name, '') AS categoryname,
           ci.quantity, ci.sortorder
    FROM restaurantcomboitems ci
    LEFT JOIN restaurantmenuitems mi ON mi.menuitemid = ci.menuitemid AND mi.farmid = ci.farmid
    LEFT JOIN restaurantmenucategories mc ON mc.menucategoryid = ci.menucategoryid AND mc.farmid = ci.farmid
    WHERE ci.comboid = p_comboid AND ci.farmid = p_farmid
    ORDER BY ci.sortorder;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_comboitem_insert(
    p_farmid TEXT, p_comboid INT, p_menuitemid INT, p_menucategoryid INT,
    p_quantity INT, p_sortorder INT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantcomboitems (farmid, comboid, menuitemid, menucategoryid, quantity, sortorder)
    VALUES (p_farmid, p_comboid, p_menuitemid, p_menucategoryid, p_quantity, p_sortorder)
    RETURNING comboitemid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_comboitem_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantcomboitems WHERE comboitemid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: MENU SCHEDULES
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_menuschedule_list(p_farmid TEXT)
RETURNS TABLE (
    menuscheduleid INT, farmid TEXT, name TEXT, starttime TEXT,
    endtime TEXT, daysofweek TEXT, isactive BOOLEAN,
    createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT s.menuscheduleid, s.farmid, s.name, s.starttime,
           s.endtime, s.daysofweek, s.isactive, s.createdat, s.updatedat
    FROM restaurantmenuschedules s
    WHERE s.farmid = p_farmid
    ORDER BY s.starttime;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_menuschedule_insert(
    p_farmid TEXT, p_name TEXT, p_starttime TEXT, p_endtime TEXT,
    p_daysofweek TEXT, p_isactive BOOLEAN
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantmenuschedules (farmid, name, starttime, endtime, daysofweek, isactive)
    VALUES (p_farmid, p_name, p_starttime, p_endtime, p_daysofweek, p_isactive)
    RETURNING menuscheduleid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_menuschedule_update(
    p_id INT, p_farmid TEXT, p_name TEXT, p_starttime TEXT,
    p_endtime TEXT, p_daysofweek TEXT, p_isactive BOOLEAN
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantmenuschedules SET
        name = p_name, starttime = p_starttime, endtime = p_endtime,
        daysofweek = p_daysofweek, isactive = p_isactive, updatedat = NOW()
    WHERE menuscheduleid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_menuschedule_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantmenuschedules WHERE menuscheduleid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Schedule item assignment
CREATE OR REPLACE FUNCTION sprestaurant_menuscheduleitem_assign(
    p_farmid TEXT, p_menuscheduleid INT, p_menuitemid INT, p_overrideprice NUMERIC
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantmenuscheduleitems (farmid, menuscheduleid, menuitemid, overrideprice)
    VALUES (p_farmid, p_menuscheduleid, p_menuitemid, p_overrideprice)
    ON CONFLICT (farmid, menuscheduleid, menuitemid) DO UPDATE SET overrideprice = p_overrideprice
    RETURNING menuscheduleitemid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_menuscheduleitem_unassign(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantmenuscheduleitems WHERE menuscheduleitemid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_menuscheduleitem_list(p_scheduleid INT, p_farmid TEXT)
RETURNS TABLE (
    menuscheduleitemid INT, farmid TEXT, menuscheduleid INT,
    menuitemid INT, menuitemname TEXT, overrideprice NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT si.menuscheduleitemid, si.farmid, si.menuscheduleid,
           si.menuitemid, COALESCE(mi.name, '') AS menuitemname, si.overrideprice
    FROM restaurantmenuscheduleitems si
    LEFT JOIN restaurantmenuitems mi ON mi.menuitemid = si.menuitemid AND mi.farmid = si.farmid
    WHERE si.menuscheduleid = p_scheduleid AND si.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: ITEM TAGS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_itemtag_list(p_menuitemid INT, p_farmid TEXT)
RETURNS TABLE (itemtagid INT, farmid TEXT, menuitemid INT, tag TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT t.itemtagid, t.farmid, t.menuitemid, t.tag
    FROM restaurantitemtags t
    WHERE t.menuitemid = p_menuitemid AND t.farmid = p_farmid
    ORDER BY t.tag;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_itemtag_add(p_farmid TEXT, p_menuitemid INT, p_tag TEXT)
RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantitemtags (farmid, menuitemid, tag)
    VALUES (p_farmid, p_menuitemid, p_tag)
    ON CONFLICT (farmid, menuitemid, tag) DO NOTHING
    RETURNING itemtagid INTO v_id;
    RETURN COALESCE(v_id, 0);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_itemtag_remove(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantitemtags WHERE itemtagid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;
