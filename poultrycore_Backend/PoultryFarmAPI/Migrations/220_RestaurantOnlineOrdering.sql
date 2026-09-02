-- Migration 220: Restaurant Management System — Online Ordering
-- Applied: 2026-08-30
-- Phase R5: Online ordering settings, QR codes, delivery addresses,
--           promo codes, customer accounts, order tracking

-- =============================================================================
-- 1. ONLINE ORDERING SETTINGS
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantonlineorderingsettings (
    onlineorderingsettingid SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL UNIQUE,
    isenabled            BOOLEAN DEFAULT FALSE,
    allowdineinqr        BOOLEAN DEFAULT TRUE,    -- QR table ordering
    allowtakeaway        BOOLEAN DEFAULT TRUE,
    allowdelivery        BOOLEAN DEFAULT TRUE,
    minorderamount       NUMERIC(12,2) DEFAULT 0,
    maxordersperslot     INT DEFAULT 0,           -- 0 = unlimited (kitchen throttle)
    slotdurationmins     INT DEFAULT 30,
    estimatedprepminsdine INT DEFAULT 15,
    estimatedprepminstake INT DEFAULT 20,
    estimatedprepminsdeliv INT DEFAULT 30,
    deliveryfeetype      TEXT DEFAULT 'Fixed',     -- Fixed, DistanceBased, Free
    deliveryfeeamount    NUMERIC(12,2) DEFAULT 0,
    freedeliveryabove    NUMERIC(12,2),            -- free delivery for orders above this
    maxdeliverydistancekm NUMERIC(5,1) DEFAULT 10,
    acceptingorders      BOOLEAN DEFAULT TRUE,     -- master toggle
    pausedreason         TEXT,                     -- "Kitchen at capacity", etc.
    welcomemessage       TEXT,
    termsandconditions   TEXT,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);

-- =============================================================================
-- 2. QR CODES (per-table QR for dine-in ordering)
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantqrcodes (
    qrcodeid             SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    tableid              INT REFERENCES restauranttables(tableid) ON DELETE CASCADE,
    tablenumber          TEXT NOT NULL,
    qrtoken              TEXT NOT NULL UNIQUE,     -- unique token embedded in QR URL
    isactive             BOOLEAN DEFAULT TRUE,
    scanccount           INT DEFAULT 0,
    lastscanndat         TIMESTAMP,
    createdat            TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantqrcodes_farm ON restaurantqrcodes(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantqrcodes_token ON restaurantqrcodes(qrtoken);

-- =============================================================================
-- 3. PROMO CODES
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantpromocodes (
    promocodeid          SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    code                 TEXT NOT NULL,
    description          TEXT,
    discounttype         TEXT NOT NULL DEFAULT 'Percentage', -- Percentage, FixedAmount, FreeDelivery
    discountvalue        NUMERIC(12,2) NOT NULL DEFAULT 0,
    minorderamount       NUMERIC(12,2) DEFAULT 0,
    maxdiscountamount    NUMERIC(12,2),
    maxuses              INT DEFAULT 0,            -- 0 = unlimited
    currentuses          INT DEFAULT 0,
    validfrom            TIMESTAMP,
    validuntil           TIMESTAMP,
    isactive             BOOLEAN DEFAULT TRUE,
    channelrestriction   TEXT,                     -- NULL=all, 'Online', 'QR', 'Delivery'
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantpromocodes_farm ON restaurantpromocodes(farmid);
CREATE UNIQUE INDEX IF NOT EXISTS ix_restaurantpromocodes_farm_code ON restaurantpromocodes(farmid, code);

-- =============================================================================
-- 4. DELIVERY ADDRESSES (saved per customer phone/email)
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantdeliveryaddresses (
    deliveryaddressid    SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    customerphone        TEXT,
    customeremail        TEXT,
    label                TEXT DEFAULT 'Home',      -- Home, Work, Other
    addressline1         TEXT NOT NULL,
    addressline2         TEXT,
    city                 TEXT,
    postalcode           TEXT,
    latitude             NUMERIC(10,7),
    longitude            NUMERIC(10,7),
    deliverynotes        TEXT,
    isdefault            BOOLEAN DEFAULT FALSE,
    createdat            TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantdeliveryaddresses_farm ON restaurantdeliveryaddresses(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantdeliveryaddresses_phone ON restaurantdeliveryaddresses(farmid, customerphone);

-- =============================================================================
-- 5. ORDER TRACKING (extend existing orders with tracking fields)
-- =============================================================================

ALTER TABLE restaurantorders ADD COLUMN IF NOT EXISTS onlinesource TEXT;          -- 'QR', 'Web', 'App'
ALTER TABLE restaurantorders ADD COLUMN IF NOT EXISTS deliveryaddressid INT;
ALTER TABLE restaurantorders ADD COLUMN IF NOT EXISTS deliveryaddress TEXT;
ALTER TABLE restaurantorders ADD COLUMN IF NOT EXISTS deliveryfee NUMERIC(12,2) DEFAULT 0;
ALTER TABLE restaurantorders ADD COLUMN IF NOT EXISTS promocodeid INT;
ALTER TABLE restaurantorders ADD COLUMN IF NOT EXISTS promocode TEXT;
ALTER TABLE restaurantorders ADD COLUMN IF NOT EXISTS promodiscount NUMERIC(12,2) DEFAULT 0;
ALTER TABLE restaurantorders ADD COLUMN IF NOT EXISTS estimatedreadytime TIMESTAMP;
ALTER TABLE restaurantorders ADD COLUMN IF NOT EXISTS trackingtoken TEXT;          -- unique token for customer to track order

CREATE INDEX IF NOT EXISTS ix_restaurantorders_tracking ON restaurantorders(trackingtoken) WHERE trackingtoken IS NOT NULL;

-- =============================================================================
-- STORED PROCEDURES: ONLINE ORDERING SETTINGS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_onlinesettings_get(p_farmid TEXT)
RETURNS TABLE (
    onlineorderingsettingid INT, farmid TEXT, isenabled BOOLEAN,
    allowdineinqr BOOLEAN, allowtakeaway BOOLEAN, allowdelivery BOOLEAN,
    minorderamount NUMERIC, maxordersperslot INT, slotdurationmins INT,
    estimatedprepminsdine INT, estimatedprepminstake INT, estimatedprepminsdeliv INT,
    deliveryfeetype TEXT, deliveryfeeamount NUMERIC, freedeliveryabove NUMERIC,
    maxdeliverydistancekm NUMERIC, acceptingorders BOOLEAN, pausedreason TEXT,
    welcomemessage TEXT, termsandconditions TEXT,
    createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY SELECT s.* FROM restaurantonlineorderingsettings s WHERE s.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_onlinesettings_upsert(
    p_farmid TEXT, p_isenabled BOOLEAN, p_allowdineinqr BOOLEAN,
    p_allowtakeaway BOOLEAN, p_allowdelivery BOOLEAN,
    p_minorderamount NUMERIC, p_maxordersperslot INT, p_slotdurationmins INT,
    p_estimatedprepminsdine INT, p_estimatedprepminstake INT, p_estimatedprepminsdeliv INT,
    p_deliveryfeetype TEXT, p_deliveryfeeamount NUMERIC, p_freedeliveryabove NUMERIC,
    p_maxdeliverydistancekm NUMERIC, p_acceptingorders BOOLEAN, p_pausedreason TEXT,
    p_welcomemessage TEXT, p_termsandconditions TEXT
) RETURNS VOID AS $$
BEGIN
    INSERT INTO restaurantonlineorderingsettings (farmid, isenabled, allowdineinqr,
        allowtakeaway, allowdelivery, minorderamount, maxordersperslot, slotdurationmins,
        estimatedprepminsdine, estimatedprepminstake, estimatedprepminsdeliv,
        deliveryfeetype, deliveryfeeamount, freedeliveryabove,
        maxdeliverydistancekm, acceptingorders, pausedreason,
        welcomemessage, termsandconditions)
    VALUES (p_farmid, p_isenabled, p_allowdineinqr,
        p_allowtakeaway, p_allowdelivery, p_minorderamount, p_maxordersperslot, p_slotdurationmins,
        p_estimatedprepminsdine, p_estimatedprepminstake, p_estimatedprepminsdeliv,
        p_deliveryfeetype, p_deliveryfeeamount, p_freedeliveryabove,
        p_maxdeliverydistancekm, p_acceptingorders, p_pausedreason,
        p_welcomemessage, p_termsandconditions)
    ON CONFLICT (farmid) DO UPDATE SET
        isenabled = p_isenabled, allowdineinqr = p_allowdineinqr,
        allowtakeaway = p_allowtakeaway, allowdelivery = p_allowdelivery,
        minorderamount = p_minorderamount, maxordersperslot = p_maxordersperslot,
        slotdurationmins = p_slotdurationmins,
        estimatedprepminsdine = p_estimatedprepminsdine,
        estimatedprepminstake = p_estimatedprepminstake,
        estimatedprepminsdeliv = p_estimatedprepminsdeliv,
        deliveryfeetype = p_deliveryfeetype, deliveryfeeamount = p_deliveryfeeamount,
        freedeliveryabove = p_freedeliveryabove,
        maxdeliverydistancekm = p_maxdeliverydistancekm,
        acceptingorders = p_acceptingorders, pausedreason = p_pausedreason,
        welcomemessage = p_welcomemessage, termsandconditions = p_termsandconditions,
        updatedat = NOW();
END;
$$ LANGUAGE plpgsql;

-- Toggle accepting orders
CREATE OR REPLACE FUNCTION sprestaurant_onlinesettings_toggle(p_farmid TEXT, p_accepting BOOLEAN, p_reason TEXT DEFAULT NULL)
RETURNS VOID AS $$
BEGIN
    UPDATE restaurantonlineorderingsettings SET acceptingorders = p_accepting, pausedreason = p_reason, updatedat = NOW()
    WHERE farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: QR CODES
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_qrcode_list(p_farmid TEXT)
RETURNS TABLE (
    qrcodeid INT, farmid TEXT, tableid INT, tablenumber TEXT,
    qrtoken TEXT, isactive BOOLEAN, scanccount INT,
    lastscanndat TIMESTAMP, createdat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT q.qrcodeid, q.farmid, q.tableid, q.tablenumber,
           q.qrtoken, q.isactive, q.scanccount, q.lastscanndat, q.createdat
    FROM restaurantqrcodes q WHERE q.farmid = p_farmid ORDER BY q.tablenumber;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_qrcode_generate(
    p_farmid TEXT, p_tableid INT, p_tablenumber TEXT
) RETURNS TABLE (qrcodeid INT, qrtoken TEXT) AS $$
DECLARE v_id INT; v_token TEXT;
BEGIN
    v_token := p_farmid || '-' || p_tablenumber || '-' || EXTRACT(EPOCH FROM NOW())::BIGINT || '-' || FLOOR(RANDOM() * 100000)::INT;
    INSERT INTO restaurantqrcodes (farmid, tableid, tablenumber, qrtoken)
    VALUES (p_farmid, p_tableid, p_tablenumber, v_token)
    RETURNING restaurantqrcodes.qrcodeid INTO v_id;
    RETURN QUERY SELECT v_id, v_token;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_qrcode_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantqrcodes WHERE qrcodeid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Record a scan
CREATE OR REPLACE FUNCTION sprestaurant_qrcode_scan(p_token TEXT)
RETURNS TABLE (farmid TEXT, tableid INT, tablenumber TEXT, isactive BOOLEAN) AS $$
BEGIN
    UPDATE restaurantqrcodes SET scanccount = scanccount + 1, lastscanndat = NOW()
    WHERE qrtoken = p_token;
    RETURN QUERY
    SELECT q.farmid, q.tableid, q.tablenumber, q.isactive
    FROM restaurantqrcodes q WHERE q.qrtoken = p_token;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: PROMO CODES
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_promocode_list(p_farmid TEXT)
RETURNS TABLE (
    promocodeid INT, farmid TEXT, code TEXT, description TEXT,
    discounttype TEXT, discountvalue NUMERIC, minorderamount NUMERIC,
    maxdiscountamount NUMERIC, maxuses INT, currentuses INT,
    validfrom TIMESTAMP, validuntil TIMESTAMP, isactive BOOLEAN,
    channelrestriction TEXT, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT p.promocodeid, p.farmid, p.code, p.description,
           p.discounttype, p.discountvalue, p.minorderamount,
           p.maxdiscountamount, p.maxuses, p.currentuses,
           p.validfrom, p.validuntil, p.isactive,
           p.channelrestriction, p.createdat, p.updatedat
    FROM restaurantpromocodes p WHERE p.farmid = p_farmid ORDER BY p.code;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_promocode_insert(
    p_farmid TEXT, p_code TEXT, p_description TEXT, p_discounttype TEXT,
    p_discountvalue NUMERIC, p_minorderamount NUMERIC, p_maxdiscountamount NUMERIC,
    p_maxuses INT, p_validfrom TIMESTAMP, p_validuntil TIMESTAMP,
    p_isactive BOOLEAN, p_channelrestriction TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantpromocodes (farmid, code, description, discounttype, discountvalue,
        minorderamount, maxdiscountamount, maxuses, validfrom, validuntil, isactive, channelrestriction)
    VALUES (p_farmid, UPPER(p_code), p_description, p_discounttype, p_discountvalue,
        p_minorderamount, p_maxdiscountamount, p_maxuses, p_validfrom, p_validuntil, p_isactive, p_channelrestriction)
    RETURNING promocodeid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_promocode_update(
    p_id INT, p_farmid TEXT, p_code TEXT, p_description TEXT, p_discounttype TEXT,
    p_discountvalue NUMERIC, p_minorderamount NUMERIC, p_maxdiscountamount NUMERIC,
    p_maxuses INT, p_validfrom TIMESTAMP, p_validuntil TIMESTAMP,
    p_isactive BOOLEAN, p_channelrestriction TEXT
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantpromocodes SET code = UPPER(p_code), description = p_description,
        discounttype = p_discounttype, discountvalue = p_discountvalue,
        minorderamount = p_minorderamount, maxdiscountamount = p_maxdiscountamount,
        maxuses = p_maxuses, validfrom = p_validfrom, validuntil = p_validuntil,
        isactive = p_isactive, channelrestriction = p_channelrestriction, updatedat = NOW()
    WHERE promocodeid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_promocode_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantpromocodes WHERE promocodeid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Validate promo code at checkout
CREATE OR REPLACE FUNCTION sprestaurant_promocode_validate(
    p_farmid TEXT, p_code TEXT, p_orderamount NUMERIC, p_channel TEXT DEFAULT NULL
)
RETURNS TABLE (
    valid BOOLEAN, promocodeid INT, discounttype TEXT, discountvalue NUMERIC,
    maxdiscountamount NUMERIC, calculatediscount NUMERIC, message TEXT
) AS $$
DECLARE v_promo RECORD; v_discount NUMERIC;
BEGIN
    SELECT * INTO v_promo FROM restaurantpromocodes pc
    WHERE pc.farmid = p_farmid AND pc.code = UPPER(p_code) AND pc.isactive = TRUE;

    IF v_promo IS NULL THEN
        RETURN QUERY SELECT FALSE, 0, ''::TEXT, 0::NUMERIC, 0::NUMERIC, 0::NUMERIC, 'Invalid promo code'::TEXT;
        RETURN;
    END IF;
    IF v_promo.validfrom IS NOT NULL AND NOW() < v_promo.validfrom THEN
        RETURN QUERY SELECT FALSE, 0, ''::TEXT, 0::NUMERIC, 0::NUMERIC, 0::NUMERIC, 'Promo code not yet active'::TEXT;
        RETURN;
    END IF;
    IF v_promo.validuntil IS NOT NULL AND NOW() > v_promo.validuntil THEN
        RETURN QUERY SELECT FALSE, 0, ''::TEXT, 0::NUMERIC, 0::NUMERIC, 0::NUMERIC, 'Promo code expired'::TEXT;
        RETURN;
    END IF;
    IF v_promo.maxuses > 0 AND v_promo.currentuses >= v_promo.maxuses THEN
        RETURN QUERY SELECT FALSE, 0, ''::TEXT, 0::NUMERIC, 0::NUMERIC, 0::NUMERIC, 'Promo code usage limit reached'::TEXT;
        RETURN;
    END IF;
    IF p_orderamount < v_promo.minorderamount THEN
        RETURN QUERY SELECT FALSE, 0, ''::TEXT, 0::NUMERIC, 0::NUMERIC, 0::NUMERIC,
            ('Minimum order amount is ' || v_promo.minorderamount)::TEXT;
        RETURN;
    END IF;
    IF v_promo.channelrestriction IS NOT NULL AND p_channel IS NOT NULL AND v_promo.channelrestriction != p_channel THEN
        RETURN QUERY SELECT FALSE, 0, ''::TEXT, 0::NUMERIC, 0::NUMERIC, 0::NUMERIC, 'Promo code not valid for this channel'::TEXT;
        RETURN;
    END IF;

    -- Calculate discount
    IF v_promo.discounttype = 'Percentage' THEN
        v_discount := ROUND(p_orderamount * v_promo.discountvalue / 100, 2);
        IF v_promo.maxdiscountamount IS NOT NULL AND v_discount > v_promo.maxdiscountamount THEN
            v_discount := v_promo.maxdiscountamount;
        END IF;
    ELSIF v_promo.discounttype = 'FreeDelivery' THEN
        v_discount := 0; -- handled by caller
    ELSE
        v_discount := v_promo.discountvalue;
    END IF;

    RETURN QUERY SELECT TRUE, v_promo.promocodeid, v_promo.discounttype, v_promo.discountvalue,
        v_promo.maxdiscountamount, v_discount, 'Promo code applied!'::TEXT;
END;
$$ LANGUAGE plpgsql;

-- Increment usage count
CREATE OR REPLACE FUNCTION sprestaurant_promocode_use(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    UPDATE restaurantpromocodes SET currentuses = currentuses + 1 WHERE promocodeid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: DELIVERY ADDRESSES
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_deliveryaddress_list(p_farmid TEXT, p_phone TEXT DEFAULT NULL, p_email TEXT DEFAULT NULL)
RETURNS TABLE (
    deliveryaddressid INT, farmid TEXT, customerphone TEXT, customeremail TEXT,
    label TEXT, addressline1 TEXT, addressline2 TEXT, city TEXT, postalcode TEXT,
    latitude NUMERIC, longitude NUMERIC, deliverynotes TEXT, isdefault BOOLEAN, createdat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT d.* FROM restaurantdeliveryaddresses d
    WHERE d.farmid = p_farmid
      AND (p_phone IS NULL OR d.customerphone = p_phone)
      AND (p_email IS NULL OR d.customeremail = p_email)
    ORDER BY d.isdefault DESC, d.createdat DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_deliveryaddress_insert(
    p_farmid TEXT, p_customerphone TEXT, p_customeremail TEXT, p_label TEXT,
    p_addressline1 TEXT, p_addressline2 TEXT, p_city TEXT, p_postalcode TEXT,
    p_latitude NUMERIC, p_longitude NUMERIC, p_deliverynotes TEXT, p_isdefault BOOLEAN
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantdeliveryaddresses (farmid, customerphone, customeremail, label,
        addressline1, addressline2, city, postalcode, latitude, longitude, deliverynotes, isdefault)
    VALUES (p_farmid, p_customerphone, p_customeremail, p_label,
        p_addressline1, p_addressline2, p_city, p_postalcode, p_latitude, p_longitude, p_deliverynotes, p_isdefault)
    RETURNING deliveryaddressid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_deliveryaddress_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantdeliveryaddresses WHERE deliveryaddressid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: PUBLIC MENU (no auth required)
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_public_menu(p_farmid TEXT)
RETURNS TABLE (
    menuitemid INT, name TEXT, description TEXT, price NUMERIC,
    imageurl TEXT, preptime INT, calories INT, allergens TEXT,
    spicylevel INT, isvegetarian BOOLEAN, isvegan BOOLEAN, isglutenfree BOOLEAN,
    ishalal BOOLEAN, iskosher BOOLEAN, categoryid INT, categoryname TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT i.menuitemid, i.name, i.description, i.price,
           i.imageurl, i.preptime, i.calories, i.allergens,
           i.spicylevel, i.isvegetarian, i.isvegan, i.isglutenfree,
           i.ishalal, i.iskosher,
           c.menucategoryid AS categoryid, COALESCE(c.name, 'Uncategorized') AS categoryname
    FROM restaurantmenuitems i
    LEFT JOIN restaurantmenucategories c ON c.menucategoryid = i.menucategoryid AND c.farmid = i.farmid
    WHERE i.farmid = p_farmid AND i.isactive = TRUE AND i.isavailable = TRUE
    ORDER BY COALESCE(c.sortorder, 999), c.name, i.sortorder, i.name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_public_categories(p_farmid TEXT)
RETURNS TABLE (menucategoryid INT, name TEXT, description TEXT, imageurl TEXT, sortorder INT) AS $$
BEGIN
    RETURN QUERY
    SELECT c.menucategoryid, c.name, c.description, c.imageurl, c.sortorder
    FROM restaurantmenucategories c
    WHERE c.farmid = p_farmid AND c.isactive = TRUE
    ORDER BY c.sortorder, c.name;
END;
$$ LANGUAGE plpgsql;

-- Create online order with tracking token
CREATE OR REPLACE FUNCTION sprestaurant_online_order_insert(
    p_farmid TEXT, p_ordertype TEXT, p_tableid INT, p_tablenumber TEXT,
    p_customername TEXT, p_customerphone TEXT, p_covers INT, p_notes TEXT,
    p_onlinesource TEXT, p_deliveryaddress TEXT, p_deliveryfee NUMERIC,
    p_promocodeid INT, p_promocode TEXT, p_promodiscount NUMERIC
) RETURNS TABLE (orderid INT, ordernumber TEXT, trackingtoken TEXT) AS $$
DECLARE v_id INT; v_num TEXT; v_token TEXT;
BEGIN
    v_num := sprestaurant_order_next_number(p_farmid);
    v_token := 'TRK-' || EXTRACT(EPOCH FROM NOW())::BIGINT || '-' || FLOOR(RANDOM() * 1000000)::INT;
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, tableid, tablenumber,
        customername, customerphone, covers, notes,
        onlinesource, deliveryaddress, deliveryfee, promocodeid, promocode, promodiscount,
        trackingtoken, createdby)
    VALUES (p_farmid, v_num, p_ordertype, p_tableid, p_tablenumber,
        p_customername, p_customerphone, p_covers, p_notes,
        p_onlinesource, p_deliveryaddress, p_deliveryfee, p_promocodeid, p_promocode, p_promodiscount,
        v_token, 'Online')
    RETURNING restaurantorders.orderid INTO v_id;
    IF p_tableid IS NOT NULL THEN
        UPDATE restauranttables SET status = 'Occupied', currentorderid = v_id, updatedat = NOW()
        WHERE restauranttables.tableid = p_tableid AND restauranttables.farmid = p_farmid;
    END IF;
    -- Increment promo usage
    IF p_promocodeid IS NOT NULL THEN
        PERFORM sprestaurant_promocode_use(p_promocodeid, p_farmid);
    END IF;
    RETURN QUERY SELECT v_id, v_num, v_token;
END;
$$ LANGUAGE plpgsql;

-- Track order by token (public, no auth)
CREATE OR REPLACE FUNCTION sprestaurant_order_track(p_token TEXT)
RETURNS TABLE (
    orderid INT, ordernumber TEXT, ordertype TEXT, status TEXT,
    tablenumber TEXT, totalamount NUMERIC, paymentstatus TEXT,
    estimatedreadytime TIMESTAMP, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT o.orderid, o.ordernumber, o.ordertype, o.status,
           o.tablenumber, o.totalamount, o.paymentstatus,
           o.estimatedreadytime, o.createdat, o.updatedat
    FROM restaurantorders o WHERE o.trackingtoken = p_token;
END;
$$ LANGUAGE plpgsql;

-- Order throttle check
CREATE OR REPLACE FUNCTION sprestaurant_online_order_throttle_check(p_farmid TEXT)
RETURNS TABLE (can_accept BOOLEAN, current_count INT, max_per_slot INT, message TEXT) AS $$
DECLARE v_max INT; v_slot INT; v_count INT;
BEGIN
    SELECT maxordersperslot, slotdurationmins INTO v_max, v_slot
    FROM restaurantonlineorderingsettings WHERE farmid = p_farmid;
    IF v_max IS NULL OR v_max = 0 THEN
        RETURN QUERY SELECT TRUE, 0, 0, 'No throttle configured'::TEXT;
        RETURN;
    END IF;
    SELECT COUNT(*)::INT INTO v_count FROM restaurantorders
    WHERE farmid = p_farmid AND createdat > NOW() - (v_slot || ' minutes')::INTERVAL
      AND status NOT IN ('Cancelled', 'Refunded');
    IF v_count >= v_max THEN
        RETURN QUERY SELECT FALSE, v_count, v_max, 'Kitchen at capacity. Please try again in a few minutes.'::TEXT;
    ELSE
        RETURN QUERY SELECT TRUE, v_count, v_max, 'OK'::TEXT;
    END IF;
END;
$$ LANGUAGE plpgsql;
