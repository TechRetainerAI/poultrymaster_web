-- Migration 218: Restaurant Management System — Kitchen Display System (KDS)
-- Applied: 2026-08-30
-- Phase R3: KDS stations, station-item mappings, KDS queue queries

-- =============================================================================
-- 1. KDS STATIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantkdsstations (
    kdsstationid         SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    name                 TEXT NOT NULL,          -- e.g. 'Grill', 'Fryer', 'Bar', 'Cold', 'Dessert', 'Expo'
    displaycolor         TEXT DEFAULT '#3B82F6', -- hex color for UI
    sortorder            INT DEFAULT 0,
    isexpo               BOOLEAN DEFAULT FALSE,  -- expo station sees ALL items
    isactive             BOOLEAN DEFAULT TRUE,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantkdsstations_farm ON restaurantkdsstations(farmid);

-- =============================================================================
-- 2. STATION <-> MENU ITEM MAPPINGS
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantkdsstationitems (
    kdsstationitemid     SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    kdsstationid         INT NOT NULL REFERENCES restaurantkdsstations(kdsstationid) ON DELETE CASCADE,
    menuitemid           INT NOT NULL REFERENCES restaurantmenuitems(menuitemid) ON DELETE CASCADE,
    UNIQUE(farmid, kdsstationid, menuitemid)
);
CREATE INDEX IF NOT EXISTS ix_restaurantkdsstationitems_station ON restaurantkdsstationitems(farmid, kdsstationid);

-- =============================================================================
-- STORED PROCEDURES: KDS STATIONS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_kdsstation_list(p_farmid TEXT)
RETURNS TABLE (
    kdsstationid INT, farmid TEXT, name TEXT, displaycolor TEXT,
    sortorder INT, isexpo BOOLEAN, isactive BOOLEAN,
    createdat TIMESTAMP, updatedat TIMESTAMP, itemcount BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT s.kdsstationid, s.farmid, s.name, s.displaycolor,
           s.sortorder, s.isexpo, s.isactive, s.createdat, s.updatedat,
           (SELECT COUNT(*) FROM restaurantkdsstationitems si WHERE si.kdsstationid = s.kdsstationid AND si.farmid = s.farmid) AS itemcount
    FROM restaurantkdsstations s
    WHERE s.farmid = p_farmid
    ORDER BY s.sortorder, s.name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_kdsstation_insert(
    p_farmid TEXT, p_name TEXT, p_displaycolor TEXT, p_sortorder INT,
    p_isexpo BOOLEAN, p_isactive BOOLEAN
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantkdsstations (farmid, name, displaycolor, sortorder, isexpo, isactive)
    VALUES (p_farmid, p_name, p_displaycolor, p_sortorder, p_isexpo, p_isactive)
    RETURNING kdsstationid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_kdsstation_update(
    p_id INT, p_farmid TEXT, p_name TEXT, p_displaycolor TEXT,
    p_sortorder INT, p_isexpo BOOLEAN, p_isactive BOOLEAN
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantkdsstations SET name = p_name, displaycolor = p_displaycolor,
        sortorder = p_sortorder, isexpo = p_isexpo, isactive = p_isactive, updatedat = NOW()
    WHERE kdsstationid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_kdsstation_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantkdsstations WHERE kdsstationid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: STATION-ITEM MAPPINGS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_kdsstationitem_list(p_kdsstationid INT, p_farmid TEXT)
RETURNS TABLE (
    kdsstationitemid INT, farmid TEXT, kdsstationid INT,
    menuitemid INT, menuitemname TEXT, categoryname TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT si.kdsstationitemid, si.farmid, si.kdsstationid,
           si.menuitemid, mi.name AS menuitemname,
           COALESCE(mc.name, '') AS categoryname
    FROM restaurantkdsstationitems si
    JOIN restaurantmenuitems mi ON mi.menuitemid = si.menuitemid AND mi.farmid = si.farmid
    LEFT JOIN restaurantmenucategories mc ON mc.menucategoryid = mi.menucategoryid AND mc.farmid = mi.farmid
    WHERE si.kdsstationid = p_kdsstationid AND si.farmid = p_farmid
    ORDER BY mi.name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_kdsstationitem_assign(
    p_farmid TEXT, p_kdsstationid INT, p_menuitemid INT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantkdsstationitems (farmid, kdsstationid, menuitemid)
    VALUES (p_farmid, p_kdsstationid, p_menuitemid)
    ON CONFLICT (farmid, kdsstationid, menuitemid) DO NOTHING
    RETURNING kdsstationitemid INTO v_id;
    -- Also update the menu item's default kdsstation name
    UPDATE restaurantmenuitems SET updatedat = NOW()
    WHERE menuitemid = p_menuitemid AND farmid = p_farmid;
    RETURN COALESCE(v_id, 0);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_kdsstationitem_unassign(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantkdsstationitems WHERE kdsstationitemid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Bulk assign: set station for a menu item (removes from other stations, adds to this one)
CREATE OR REPLACE FUNCTION sprestaurant_kdsstationitem_set_station(
    p_farmid TEXT, p_menuitemid INT, p_kdsstationid INT
) RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantkdsstationitems WHERE farmid = p_farmid AND menuitemid = p_menuitemid;
    IF p_kdsstationid IS NOT NULL AND p_kdsstationid > 0 THEN
        INSERT INTO restaurantkdsstationitems (farmid, kdsstationid, menuitemid)
        VALUES (p_farmid, p_kdsstationid, p_menuitemid)
        ON CONFLICT DO NOTHING;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: KDS QUEUE (the main display query)
-- =============================================================================

-- Get active order items for a station (or all for expo)
CREATE OR REPLACE FUNCTION sprestaurant_kds_queue(
    p_farmid TEXT, p_kdsstationid INT DEFAULT NULL, p_isexpo BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    orderitemid INT, orderid INT, ordernumber TEXT, ordertype TEXT,
    tablenumber TEXT, itemname TEXT, quantity INT, notes TEXT,
    status TEXT, seatnumber INT, kdsstation TEXT,
    senttoktchenat TIMESTAMP, prepstartedat TIMESTAMP, readyat TIMESTAMP,
    createdat TIMESTAMP, modifiers TEXT,
    elapsedminutes DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT oi.orderitemid, oi.orderid, o.ordernumber, o.ordertype,
           o.tablenumber, oi.itemname, oi.quantity, oi.notes,
           oi.status, oi.seatnumber, oi.kdsstation,
           oi.senttoktchenat, oi.prepstartedat, oi.readyat,
           oi.createdat,
           -- Aggregate modifiers as comma-separated string
           (SELECT STRING_AGG(m.modifiername || CASE WHEN m.quantity > 1 THEN ' x' || m.quantity ELSE '' END, ', ')
            FROM restaurantorderitemmodifiers m WHERE m.orderitemid = oi.orderitemid) AS modifiers,
           -- Elapsed minutes since order item created
           EXTRACT(EPOCH FROM (NOW() - oi.createdat)) / 60.0 AS elapsedminutes
    FROM restaurantorderitems oi
    JOIN restaurantorders o ON o.orderid = oi.orderid AND o.farmid = oi.farmid
    WHERE oi.farmid = p_farmid
      AND oi.status IN ('Pending', 'Preparing', 'Ready')
      AND o.status NOT IN ('Cancelled', 'Refunded', 'Completed')
      AND (
          p_isexpo = TRUE  -- Expo sees everything
          OR p_kdsstationid IS NULL  -- No filter = show all
          OR EXISTS (
              SELECT 1 FROM restaurantkdsstationitems si
              WHERE si.menuitemid = oi.menuitemid AND si.kdsstationid = p_kdsstationid AND si.farmid = oi.farmid
          )
          -- Also include items explicitly assigned to this station name
          OR oi.kdsstation = (SELECT s.name FROM restaurantkdsstations s WHERE s.kdsstationid = p_kdsstationid AND s.farmid = p_farmid)
      )
    ORDER BY
        CASE oi.status WHEN 'Pending' THEN 1 WHEN 'Preparing' THEN 2 WHEN 'Ready' THEN 3 END,
        oi.createdat;
END;
$$ LANGUAGE plpgsql;

-- Bump item (mark as Ready from Preparing, or Served from Ready)
CREATE OR REPLACE FUNCTION sprestaurant_kds_bump(p_orderitemid INT, p_farmid TEXT)
RETURNS TEXT AS $$
DECLARE v_status TEXT; v_new TEXT;
BEGIN
    SELECT status INTO v_status FROM restaurantorderitems WHERE orderitemid = p_orderitemid AND farmid = p_farmid;
    v_new := CASE v_status
        WHEN 'Pending' THEN 'Preparing'
        WHEN 'Preparing' THEN 'Ready'
        WHEN 'Ready' THEN 'Served'
        ELSE v_status
    END;
    UPDATE restaurantorderitems SET status = v_new,
        senttoktchenat = CASE WHEN v_new = 'Preparing' AND senttoktchenat IS NULL THEN NOW() ELSE senttoktchenat END,
        prepstartedat = CASE WHEN v_new = 'Preparing' THEN NOW() ELSE prepstartedat END,
        readyat = CASE WHEN v_new = 'Ready' THEN NOW() ELSE readyat END
    WHERE orderitemid = p_orderitemid AND farmid = p_farmid;
    RETURN v_new;
END;
$$ LANGUAGE plpgsql;

-- Recall a bumped item (move Ready back to Preparing)
CREATE OR REPLACE FUNCTION sprestaurant_kds_recall(p_orderitemid INT, p_farmid TEXT)
RETURNS TEXT AS $$
DECLARE v_status TEXT; v_new TEXT;
BEGIN
    SELECT status INTO v_status FROM restaurantorderitems WHERE orderitemid = p_orderitemid AND farmid = p_farmid;
    v_new := CASE v_status
        WHEN 'Ready' THEN 'Preparing'
        WHEN 'Served' THEN 'Ready'
        ELSE v_status
    END;
    UPDATE restaurantorderitems SET status = v_new,
        readyat = CASE WHEN v_new = 'Preparing' THEN NULL ELSE readyat END
    WHERE orderitemid = p_orderitemid AND farmid = p_farmid;
    RETURN v_new;
END;
$$ LANGUAGE plpgsql;

-- Bump all items of an order at once (for expo "order complete")
CREATE OR REPLACE FUNCTION sprestaurant_kds_bump_order(p_orderid INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    -- Move all Pending -> Preparing
    UPDATE restaurantorderitems SET status = 'Preparing', prepstartedat = NOW(),
        senttoktchenat = COALESCE(senttoktchenat, NOW())
    WHERE orderid = p_orderid AND farmid = p_farmid AND status = 'Pending';
    -- Move all Preparing -> Ready
    UPDATE restaurantorderitems SET status = 'Ready', readyat = NOW()
    WHERE orderid = p_orderid AND farmid = p_farmid AND status = 'Preparing';
END;
$$ LANGUAGE plpgsql;

-- KDS summary stats
CREATE OR REPLACE FUNCTION sprestaurant_kds_stats(p_farmid TEXT)
RETURNS TABLE (
    pending_count BIGINT, preparing_count BIGINT, ready_count BIGINT,
    avg_prep_minutes DOUBLE PRECISION, longest_wait_minutes DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*) FILTER (WHERE oi.status = 'Pending') AS pending_count,
        COUNT(*) FILTER (WHERE oi.status = 'Preparing') AS preparing_count,
        COUNT(*) FILTER (WHERE oi.status = 'Ready') AS ready_count,
        AVG(EXTRACT(EPOCH FROM (oi.readyat - oi.prepstartedat)) / 60.0) FILTER (WHERE oi.readyat IS NOT NULL AND oi.prepstartedat IS NOT NULL) AS avg_prep_minutes,
        MAX(EXTRACT(EPOCH FROM (NOW() - oi.createdat)) / 60.0) FILTER (WHERE oi.status IN ('Pending', 'Preparing')) AS longest_wait_minutes
    FROM restaurantorderitems oi
    JOIN restaurantorders o ON o.orderid = oi.orderid AND o.farmid = oi.farmid
    WHERE oi.farmid = p_farmid
      AND oi.status IN ('Pending', 'Preparing', 'Ready')
      AND o.status NOT IN ('Cancelled', 'Refunded', 'Completed');
END;
$$ LANGUAGE plpgsql;
