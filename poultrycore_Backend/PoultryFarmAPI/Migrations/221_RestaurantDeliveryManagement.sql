-- Migration 221: Restaurant Management System — Delivery Management
-- Applied: 2026-08-30
-- Phase R6: Drivers, delivery zones, dispatch/assignments, third-party platforms

-- =============================================================================
-- 1. DRIVERS
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantdrivers (
    driverid             SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    firstname            TEXT NOT NULL,
    lastname             TEXT NOT NULL,
    phone                TEXT NOT NULL,
    email                TEXT,
    vehicletype          TEXT DEFAULT 'Motorcycle', -- Motorcycle, Car, Bicycle, Van
    vehicleplate         TEXT,
    licensenumber        TEXT,
    status               TEXT DEFAULT 'OffDuty',    -- Available, OnDelivery, OffDuty, Suspended
    currentlatitude      NUMERIC(10,7),
    currentlongitude     NUMERIC(10,7),
    lastlocationupdate   TIMESTAMP,
    isactive             BOOLEAN DEFAULT TRUE,
    notes                TEXT,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantdrivers_farm ON restaurantdrivers(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantdrivers_farm_status ON restaurantdrivers(farmid, status);

-- =============================================================================
-- 2. DELIVERY ZONES
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantdeliveryzones (
    deliveryzoneid       SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    name                 TEXT NOT NULL,              -- e.g. 'Zone A - 0-3km', 'Zone B - 3-5km'
    mindistancekm        NUMERIC(5,1) DEFAULT 0,
    maxdistancekm        NUMERIC(5,1) DEFAULT 5,
    deliveryfee          NUMERIC(12,2) DEFAULT 0,
    estimatedmins        INT DEFAULT 30,
    isactive             BOOLEAN DEFAULT TRUE,
    sortorder            INT DEFAULT 0,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantdeliveryzones_farm ON restaurantdeliveryzones(farmid);

-- =============================================================================
-- 3. DELIVERY ASSIGNMENTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantdeliveryassignments (
    deliveryassignmentid SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    orderid              INT NOT NULL REFERENCES restaurantorders(orderid) ON DELETE CASCADE,
    ordernumber          TEXT,
    driverid             INT REFERENCES restaurantdrivers(driverid) ON DELETE SET NULL,
    drivername           TEXT,
    driverphone          TEXT,
    status               TEXT DEFAULT 'Pending',    -- Pending, Assigned, PickedUp, EnRoute, Delivered, Failed, Cancelled
    assignedat           TIMESTAMP,
    pickedupat           TIMESTAMP,
    deliveredat          TIMESTAMP,
    deliveryaddress      TEXT,
    deliverynotes        TEXT,
    deliveryzoneid       INT REFERENCES restaurantdeliveryzones(deliveryzoneid) ON DELETE SET NULL,
    deliveryfee          NUMERIC(12,2) DEFAULT 0,
    estimatedmins        INT,
    actualmins           INT,
    distancekm           NUMERIC(5,1),
    prooftype            TEXT,                       -- Signature, Photo, PIN
    proofdata            TEXT,                       -- signature data, photo URL, or PIN
    rating               INT,                        -- 1-5 customer rating
    failreason           TEXT,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantdeliveryassignments_farm ON restaurantdeliveryassignments(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantdeliveryassignments_farm_status ON restaurantdeliveryassignments(farmid, status);
CREATE INDEX IF NOT EXISTS ix_restaurantdeliveryassignments_driver ON restaurantdeliveryassignments(farmid, driverid);
CREATE INDEX IF NOT EXISTS ix_restaurantdeliveryassignments_order ON restaurantdeliveryassignments(farmid, orderid);

-- =============================================================================
-- 4. THIRD-PARTY PLATFORMS
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantthirdpartyplatforms (
    platformid           SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    name                 TEXT NOT NULL,              -- 'Uber Eats', 'DoorDash', 'Glovo', 'Bolt Food'
    apikey               TEXT,
    apisecret            TEXT,
    storeid              TEXT,                       -- restaurant's ID on the platform
    commissionrate       NUMERIC(5,2) DEFAULT 0,    -- platform commission %
    autoaccept           BOOLEAN DEFAULT FALSE,
    isenabled            BOOLEAN DEFAULT FALSE,
    isactive             BOOLEAN DEFAULT TRUE,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantthirdpartyplatforms_farm ON restaurantthirdpartyplatforms(farmid);

-- =============================================================================
-- 5. THIRD-PARTY ORDERS (synced from external platforms)
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantthirdpartyorders (
    thirdpartyorderid    SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    platformid           INT REFERENCES restaurantthirdpartyplatforms(platformid) ON DELETE SET NULL,
    platformname         TEXT NOT NULL,
    externalorderid      TEXT NOT NULL,              -- platform's order ID
    orderid              INT REFERENCES restaurantorders(orderid) ON DELETE SET NULL, -- linked local order
    status               TEXT DEFAULT 'Received',    -- Received, Accepted, Rejected, Preparing, Ready, PickedUp, Delivered, Cancelled
    customername         TEXT,
    customerphone        TEXT,
    deliveryaddress      TEXT,
    itemsjson            TEXT,                        -- JSON snapshot of items
    subtotal             NUMERIC(12,2) DEFAULT 0,
    deliveryfee          NUMERIC(12,2) DEFAULT 0,
    platformfee          NUMERIC(12,2) DEFAULT 0,
    totalamount          NUMERIC(12,2) DEFAULT 0,
    commissionamount     NUMERIC(12,2) DEFAULT 0,
    netamount            NUMERIC(12,2) DEFAULT 0,    -- total - commission
    notes                TEXT,
    receivedat           TIMESTAMP DEFAULT NOW(),
    acceptedat           TIMESTAMP,
    rejectedat           TIMESTAMP,
    rejectreason         TEXT,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantthirdpartyorders_farm ON restaurantthirdpartyorders(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantthirdpartyorders_farm_status ON restaurantthirdpartyorders(farmid, status);
CREATE INDEX IF NOT EXISTS ix_restaurantthirdpartyorders_external ON restaurantthirdpartyorders(farmid, externalorderid);

-- =============================================================================
-- STORED PROCEDURES: DRIVERS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_driver_list(p_farmid TEXT, p_status TEXT DEFAULT NULL)
RETURNS TABLE (
    driverid INT, farmid TEXT, firstname TEXT, lastname TEXT, phone TEXT, email TEXT,
    vehicletype TEXT, vehicleplate TEXT, licensenumber TEXT, status TEXT,
    currentlatitude NUMERIC, currentlongitude NUMERIC, lastlocationupdate TIMESTAMP,
    isactive BOOLEAN, notes TEXT, createdat TIMESTAMP, updatedat TIMESTAMP,
    activedeliveries BIGINT, totaldeliveries BIGINT, avgrating DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT d.driverid, d.farmid, d.firstname, d.lastname, d.phone, d.email,
           d.vehicletype, d.vehicleplate, d.licensenumber, d.status,
           d.currentlatitude, d.currentlongitude, d.lastlocationupdate,
           d.isactive, d.notes, d.createdat, d.updatedat,
           (SELECT COUNT(*) FROM restaurantdeliveryassignments a WHERE a.driverid = d.driverid AND a.status IN ('Assigned','PickedUp','EnRoute')) AS activedeliveries,
           (SELECT COUNT(*) FROM restaurantdeliveryassignments a WHERE a.driverid = d.driverid AND a.status = 'Delivered') AS totaldeliveries,
           (SELECT AVG(a.rating)::DOUBLE PRECISION FROM restaurantdeliveryassignments a WHERE a.driverid = d.driverid AND a.rating IS NOT NULL) AS avgrating
    FROM restaurantdrivers d
    WHERE d.farmid = p_farmid
      AND (p_status IS NULL OR d.status = p_status)
    ORDER BY d.firstname, d.lastname;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_driver_insert(
    p_farmid TEXT, p_firstname TEXT, p_lastname TEXT, p_phone TEXT, p_email TEXT,
    p_vehicletype TEXT, p_vehicleplate TEXT, p_licensenumber TEXT, p_notes TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantdrivers (farmid, firstname, lastname, phone, email,
        vehicletype, vehicleplate, licensenumber, notes)
    VALUES (p_farmid, p_firstname, p_lastname, p_phone, p_email,
        p_vehicletype, p_vehicleplate, p_licensenumber, p_notes)
    RETURNING driverid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_driver_update(
    p_id INT, p_farmid TEXT, p_firstname TEXT, p_lastname TEXT, p_phone TEXT, p_email TEXT,
    p_vehicletype TEXT, p_vehicleplate TEXT, p_licensenumber TEXT, p_isactive BOOLEAN, p_notes TEXT
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantdrivers SET firstname = p_firstname, lastname = p_lastname,
        phone = p_phone, email = p_email, vehicletype = p_vehicletype,
        vehicleplate = p_vehicleplate, licensenumber = p_licensenumber,
        isactive = p_isactive, notes = p_notes, updatedat = NOW()
    WHERE driverid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_driver_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantdrivers WHERE driverid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_driver_update_status(p_id INT, p_farmid TEXT, p_status TEXT)
RETURNS VOID AS $$
BEGIN
    UPDATE restaurantdrivers SET status = p_status, updatedat = NOW()
    WHERE driverid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_driver_update_location(p_id INT, p_farmid TEXT, p_lat NUMERIC, p_lng NUMERIC)
RETURNS VOID AS $$
BEGIN
    UPDATE restaurantdrivers SET currentlatitude = p_lat, currentlongitude = p_lng,
        lastlocationupdate = NOW() WHERE driverid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: DELIVERY ZONES
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_deliveryzone_list(p_farmid TEXT)
RETURNS TABLE (
    deliveryzoneid INT, farmid TEXT, name TEXT, mindistancekm NUMERIC,
    maxdistancekm NUMERIC, deliveryfee NUMERIC, estimatedmins INT,
    isactive BOOLEAN, sortorder INT, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT z.* FROM restaurantdeliveryzones z
    WHERE z.farmid = p_farmid ORDER BY z.sortorder, z.mindistancekm;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_deliveryzone_insert(
    p_farmid TEXT, p_name TEXT, p_mindistancekm NUMERIC, p_maxdistancekm NUMERIC,
    p_deliveryfee NUMERIC, p_estimatedmins INT, p_isactive BOOLEAN, p_sortorder INT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantdeliveryzones (farmid, name, mindistancekm, maxdistancekm,
        deliveryfee, estimatedmins, isactive, sortorder)
    VALUES (p_farmid, p_name, p_mindistancekm, p_maxdistancekm,
        p_deliveryfee, p_estimatedmins, p_isactive, p_sortorder)
    RETURNING deliveryzoneid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_deliveryzone_update(
    p_id INT, p_farmid TEXT, p_name TEXT, p_mindistancekm NUMERIC, p_maxdistancekm NUMERIC,
    p_deliveryfee NUMERIC, p_estimatedmins INT, p_isactive BOOLEAN, p_sortorder INT
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantdeliveryzones SET name = p_name, mindistancekm = p_mindistancekm,
        maxdistancekm = p_maxdistancekm, deliveryfee = p_deliveryfee,
        estimatedmins = p_estimatedmins, isactive = p_isactive, sortorder = p_sortorder, updatedat = NOW()
    WHERE deliveryzoneid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_deliveryzone_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantdeliveryzones WHERE deliveryzoneid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: DELIVERY ASSIGNMENTS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_deliveryassignment_list(
    p_farmid TEXT, p_status TEXT DEFAULT NULL, p_driverid INT DEFAULT NULL,
    p_fromdate TIMESTAMP DEFAULT NULL, p_todate TIMESTAMP DEFAULT NULL
)
RETURNS TABLE (
    deliveryassignmentid INT, farmid TEXT, orderid INT, ordernumber TEXT,
    driverid INT, drivername TEXT, driverphone TEXT, status TEXT,
    assignedat TIMESTAMP, pickedupat TIMESTAMP, deliveredat TIMESTAMP,
    deliveryaddress TEXT, deliverynotes TEXT, deliveryzoneid INT,
    deliveryfee NUMERIC, estimatedmins INT, actualmins INT, distancekm NUMERIC,
    prooftype TEXT, proofdata TEXT, rating INT, failreason TEXT,
    createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT a.* FROM restaurantdeliveryassignments a
    WHERE a.farmid = p_farmid
      AND (p_status IS NULL OR a.status = p_status)
      AND (p_driverid IS NULL OR a.driverid = p_driverid)
      AND (p_fromdate IS NULL OR a.createdat >= p_fromdate)
      AND (p_todate IS NULL OR a.createdat <= p_todate)
    ORDER BY a.createdat DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_deliveryassignment_create(
    p_farmid TEXT, p_orderid INT, p_ordernumber TEXT, p_driverid INT,
    p_deliveryaddress TEXT, p_deliverynotes TEXT, p_deliveryzoneid INT,
    p_deliveryfee NUMERIC, p_estimatedmins INT
) RETURNS INT AS $$
DECLARE v_id INT; v_dname TEXT; v_dphone TEXT;
BEGIN
    SELECT firstname || ' ' || lastname, phone INTO v_dname, v_dphone
    FROM restaurantdrivers WHERE driverid = p_driverid AND farmid = p_farmid;

    INSERT INTO restaurantdeliveryassignments (farmid, orderid, ordernumber, driverid,
        drivername, driverphone, status, assignedat, deliveryaddress, deliverynotes,
        deliveryzoneid, deliveryfee, estimatedmins)
    VALUES (p_farmid, p_orderid, p_ordernumber, p_driverid,
        v_dname, v_dphone, 'Assigned', NOW(), p_deliveryaddress, p_deliverynotes,
        p_deliveryzoneid, p_deliveryfee, p_estimatedmins)
    RETURNING deliveryassignmentid INTO v_id;

    -- Mark driver as OnDelivery
    UPDATE restaurantdrivers SET status = 'OnDelivery', updatedat = NOW()
    WHERE driverid = p_driverid AND farmid = p_farmid;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_deliveryassignment_update_status(
    p_id INT, p_farmid TEXT, p_status TEXT, p_failreason TEXT DEFAULT NULL
) RETURNS VOID AS $$
DECLARE v_driverid INT;
BEGIN
    SELECT driverid INTO v_driverid FROM restaurantdeliveryassignments
    WHERE deliveryassignmentid = p_id AND farmid = p_farmid;

    UPDATE restaurantdeliveryassignments SET status = p_status, updatedat = NOW(),
        pickedupat = CASE WHEN p_status = 'PickedUp' THEN NOW() ELSE pickedupat END,
        deliveredat = CASE WHEN p_status = 'Delivered' THEN NOW() ELSE deliveredat END,
        actualmins = CASE WHEN p_status = 'Delivered' THEN
            EXTRACT(EPOCH FROM (NOW() - assignedat))::INT / 60 ELSE actualmins END,
        failreason = CASE WHEN p_status = 'Failed' THEN p_failreason ELSE failreason END
    WHERE deliveryassignmentid = p_id AND farmid = p_farmid;

    -- Free driver on delivery complete/fail/cancel
    IF p_status IN ('Delivered', 'Failed', 'Cancelled') AND v_driverid IS NOT NULL THEN
        UPDATE restaurantdrivers SET status = 'Available', updatedat = NOW()
        WHERE driverid = v_driverid AND farmid = p_farmid;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_deliveryassignment_rate(p_id INT, p_farmid TEXT, p_rating INT)
RETURNS VOID AS $$
BEGIN
    UPDATE restaurantdeliveryassignments SET rating = p_rating, updatedat = NOW()
    WHERE deliveryassignmentid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_deliveryassignment_proof(p_id INT, p_farmid TEXT, p_prooftype TEXT, p_proofdata TEXT)
RETURNS VOID AS $$
BEGIN
    UPDATE restaurantdeliveryassignments SET prooftype = p_prooftype, proofdata = p_proofdata, updatedat = NOW()
    WHERE deliveryassignmentid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Driver performance stats
CREATE OR REPLACE FUNCTION sprestaurant_driver_stats(p_driverid INT, p_farmid TEXT, p_fromdate DATE DEFAULT NULL, p_todate DATE DEFAULT NULL)
RETURNS TABLE (
    total_deliveries BIGINT, completed_deliveries BIGINT, failed_deliveries BIGINT,
    avg_delivery_mins DOUBLE PRECISION, avg_rating DOUBLE PRECISION,
    total_delivery_fees NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*) AS total_deliveries,
        COUNT(*) FILTER (WHERE a.status = 'Delivered') AS completed_deliveries,
        COUNT(*) FILTER (WHERE a.status = 'Failed') AS failed_deliveries,
        AVG(a.actualmins)::DOUBLE PRECISION FILTER (WHERE a.actualmins IS NOT NULL) AS avg_delivery_mins,
        AVG(a.rating)::DOUBLE PRECISION FILTER (WHERE a.rating IS NOT NULL) AS avg_rating,
        COALESCE(SUM(a.deliveryfee) FILTER (WHERE a.status = 'Delivered'), 0) AS total_delivery_fees
    FROM restaurantdeliveryassignments a
    WHERE a.driverid = p_driverid AND a.farmid = p_farmid
      AND (p_fromdate IS NULL OR a.createdat::DATE >= p_fromdate)
      AND (p_todate IS NULL OR a.createdat::DATE <= p_todate);
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: THIRD-PARTY PLATFORMS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_thirdpartyplatform_list(p_farmid TEXT)
RETURNS TABLE (
    platformid INT, farmid TEXT, name TEXT, apikey TEXT, apisecret TEXT, storeid TEXT,
    commissionrate NUMERIC, autoaccept BOOLEAN, isenabled BOOLEAN, isactive BOOLEAN,
    createdat TIMESTAMP, updatedat TIMESTAMP, ordercount BIGINT, totalrevenue NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT p.platformid, p.farmid, p.name, p.apikey, p.apisecret, p.storeid,
           p.commissionrate, p.autoaccept, p.isenabled, p.isactive, p.createdat, p.updatedat,
           (SELECT COUNT(*) FROM restaurantthirdpartyorders o WHERE o.platformid = p.platformid) AS ordercount,
           (SELECT COALESCE(SUM(o.netamount), 0) FROM restaurantthirdpartyorders o WHERE o.platformid = p.platformid AND o.status = 'Delivered') AS totalrevenue
    FROM restaurantthirdpartyplatforms p
    WHERE p.farmid = p_farmid ORDER BY p.name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_thirdpartyplatform_insert(
    p_farmid TEXT, p_name TEXT, p_apikey TEXT, p_apisecret TEXT, p_storeid TEXT,
    p_commissionrate NUMERIC, p_autoaccept BOOLEAN, p_isenabled BOOLEAN
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantthirdpartyplatforms (farmid, name, apikey, apisecret, storeid,
        commissionrate, autoaccept, isenabled)
    VALUES (p_farmid, p_name, p_apikey, p_apisecret, p_storeid,
        p_commissionrate, p_autoaccept, p_isenabled)
    RETURNING platformid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_thirdpartyplatform_update(
    p_id INT, p_farmid TEXT, p_name TEXT, p_apikey TEXT, p_apisecret TEXT, p_storeid TEXT,
    p_commissionrate NUMERIC, p_autoaccept BOOLEAN, p_isenabled BOOLEAN
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantthirdpartyplatforms SET name = p_name, apikey = p_apikey,
        apisecret = p_apisecret, storeid = p_storeid, commissionrate = p_commissionrate,
        autoaccept = p_autoaccept, isenabled = p_isenabled, updatedat = NOW()
    WHERE platformid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_thirdpartyplatform_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantthirdpartyplatforms WHERE platformid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: THIRD-PARTY ORDERS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_thirdpartyorder_list(
    p_farmid TEXT, p_status TEXT DEFAULT NULL, p_platformid INT DEFAULT NULL
)
RETURNS TABLE (
    thirdpartyorderid INT, farmid TEXT, platformid INT, platformname TEXT,
    externalorderid TEXT, orderid INT, status TEXT,
    customername TEXT, customerphone TEXT, deliveryaddress TEXT,
    itemsjson TEXT, subtotal NUMERIC, deliveryfee NUMERIC, platformfee NUMERIC,
    totalamount NUMERIC, commissionamount NUMERIC, netamount NUMERIC,
    notes TEXT, receivedat TIMESTAMP, acceptedat TIMESTAMP, rejectedat TIMESTAMP,
    rejectreason TEXT, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT t.* FROM restaurantthirdpartyorders t
    WHERE t.farmid = p_farmid
      AND (p_status IS NULL OR t.status = p_status)
      AND (p_platformid IS NULL OR t.platformid = p_platformid)
    ORDER BY t.createdat DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_thirdpartyorder_insert(
    p_farmid TEXT, p_platformid INT, p_platformname TEXT, p_externalorderid TEXT,
    p_customername TEXT, p_customerphone TEXT, p_deliveryaddress TEXT,
    p_itemsjson TEXT, p_subtotal NUMERIC, p_deliveryfee NUMERIC, p_platformfee NUMERIC,
    p_totalamount NUMERIC, p_commissionrate NUMERIC, p_notes TEXT
) RETURNS INT AS $$
DECLARE v_id INT; v_commission NUMERIC; v_net NUMERIC;
BEGIN
    v_commission := ROUND(p_totalamount * p_commissionrate / 100, 2);
    v_net := p_totalamount - v_commission;
    INSERT INTO restaurantthirdpartyorders (farmid, platformid, platformname, externalorderid,
        customername, customerphone, deliveryaddress, itemsjson,
        subtotal, deliveryfee, platformfee, totalamount, commissionamount, netamount, notes)
    VALUES (p_farmid, p_platformid, p_platformname, p_externalorderid,
        p_customername, p_customerphone, p_deliveryaddress, p_itemsjson,
        p_subtotal, p_deliveryfee, p_platformfee, p_totalamount, v_commission, v_net, p_notes)
    RETURNING thirdpartyorderid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_thirdpartyorder_update_status(
    p_id INT, p_farmid TEXT, p_status TEXT, p_rejectreason TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantthirdpartyorders SET status = p_status, updatedat = NOW(),
        acceptedat = CASE WHEN p_status = 'Accepted' THEN NOW() ELSE acceptedat END,
        rejectedat = CASE WHEN p_status = 'Rejected' THEN NOW() ELSE rejectedat END,
        rejectreason = CASE WHEN p_status = 'Rejected' THEN p_rejectreason ELSE rejectreason END
    WHERE thirdpartyorderid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Delivery summary stats
CREATE OR REPLACE FUNCTION sprestaurant_delivery_stats(p_farmid TEXT, p_date DATE DEFAULT NULL)
RETURNS TABLE (
    total_assignments BIGINT, pending_count BIGINT, active_count BIGINT,
    delivered_count BIGINT, failed_count BIGINT,
    avg_delivery_mins DOUBLE PRECISION, total_fees NUMERIC,
    available_drivers BIGINT, ondelivery_drivers BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        (SELECT COUNT(*) FROM restaurantdeliveryassignments a WHERE a.farmid = p_farmid AND (p_date IS NULL OR a.createdat::DATE = p_date)) AS total_assignments,
        (SELECT COUNT(*) FROM restaurantdeliveryassignments a WHERE a.farmid = p_farmid AND a.status = 'Pending' AND (p_date IS NULL OR a.createdat::DATE = p_date)) AS pending_count,
        (SELECT COUNT(*) FROM restaurantdeliveryassignments a WHERE a.farmid = p_farmid AND a.status IN ('Assigned','PickedUp','EnRoute') AND (p_date IS NULL OR a.createdat::DATE = p_date)) AS active_count,
        (SELECT COUNT(*) FROM restaurantdeliveryassignments a WHERE a.farmid = p_farmid AND a.status = 'Delivered' AND (p_date IS NULL OR a.createdat::DATE = p_date)) AS delivered_count,
        (SELECT COUNT(*) FROM restaurantdeliveryassignments a WHERE a.farmid = p_farmid AND a.status = 'Failed' AND (p_date IS NULL OR a.createdat::DATE = p_date)) AS failed_count,
        (SELECT AVG(a.actualmins)::DOUBLE PRECISION FROM restaurantdeliveryassignments a WHERE a.farmid = p_farmid AND a.actualmins IS NOT NULL AND (p_date IS NULL OR a.createdat::DATE = p_date)) AS avg_delivery_mins,
        (SELECT COALESCE(SUM(a.deliveryfee), 0) FROM restaurantdeliveryassignments a WHERE a.farmid = p_farmid AND a.status = 'Delivered' AND (p_date IS NULL OR a.createdat::DATE = p_date)) AS total_fees,
        (SELECT COUNT(*) FROM restaurantdrivers d WHERE d.farmid = p_farmid AND d.status = 'Available' AND d.isactive = TRUE) AS available_drivers,
        (SELECT COUNT(*) FROM restaurantdrivers d WHERE d.farmid = p_farmid AND d.status = 'OnDelivery') AS ondelivery_drivers;
END;
$$ LANGUAGE plpgsql;
