-- Migration 217: Restaurant Management System — Floor Plan + POS / Orders
-- Applied: 2026-08-30
-- Phase R2: Floors, tables, orders, order items, order modifiers,
--           order payments, discounts, order status workflow

-- =============================================================================
-- 1. FLOORS / SECTIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantfloors (
    floorid              SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    name                 TEXT NOT NULL,          -- e.g. 'Ground Floor', 'Rooftop', 'Patio'
    floornumber          INT DEFAULT 0,
    description          TEXT,
    isactive             BOOLEAN DEFAULT TRUE,
    sortorder            INT DEFAULT 0,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantfloors_farm ON restaurantfloors(farmid);

-- =============================================================================
-- 2. TABLES
-- =============================================================================

CREATE TABLE IF NOT EXISTS restauranttables (
    tableid              SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    floorid              INT REFERENCES restaurantfloors(floorid) ON DELETE SET NULL,
    tablenumber          TEXT NOT NULL,          -- '1', 'A1', 'BAR-3'
    tablename            TEXT,                   -- optional display name
    capacity             INT DEFAULT 4,
    shape                TEXT DEFAULT 'Square',  -- Square, Round, Booth, Bar, Long
    status               TEXT DEFAULT 'Available', -- Available, Occupied, Reserved, NeedsCleaning, OutOfService
    positionx            INT DEFAULT 0,          -- grid position for floor plan
    positiony            INT DEFAULT 0,
    width                INT DEFAULT 1,          -- grid units
    height               INT DEFAULT 1,
    isactive             BOOLEAN DEFAULT TRUE,
    currentorderid       INT,                    -- FK set later after orders table exists
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restauranttables_farm ON restauranttables(farmid);
CREATE INDEX IF NOT EXISTS ix_restauranttables_farm_status ON restauranttables(farmid, status);
CREATE UNIQUE INDEX IF NOT EXISTS ix_restauranttables_farm_number ON restauranttables(farmid, tablenumber);

-- =============================================================================
-- 3. ORDERS
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantorders (
    orderid              SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    ordernumber          TEXT NOT NULL,           -- auto-generated: ORD-YYYYMMDD-NNN
    ordertype            TEXT NOT NULL DEFAULT 'DineIn', -- DineIn, Takeaway, Delivery, DriveThrough
    status               TEXT NOT NULL DEFAULT 'Placed', -- Placed, Confirmed, Preparing, Ready, Served, Completed, Cancelled, Refunded
    tableid              INT REFERENCES restauranttables(tableid) ON DELETE SET NULL,
    tablenumber          TEXT,
    customerid           INT,                    -- optional FK to GenericCustomers
    customername         TEXT,
    customerphone        TEXT,
    covers               INT DEFAULT 1,          -- number of guests
    subtotal             NUMERIC(12,2) DEFAULT 0,
    discountamount       NUMERIC(12,2) DEFAULT 0,
    taxamount            NUMERIC(12,2) DEFAULT 0,
    servicechargeamount  NUMERIC(12,2) DEFAULT 0,
    totalamount          NUMERIC(12,2) DEFAULT 0,
    paidamount           NUMERIC(12,2) DEFAULT 0,
    paymentstatus        TEXT DEFAULT 'Unpaid',   -- Unpaid, Partial, Paid, Refunded
    notes                TEXT,
    createdby            TEXT,
    servedby             TEXT,                    -- waiter/server
    cancelreason         TEXT,
    refundreason         TEXT,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP,
    completedat          TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantorders_farm ON restaurantorders(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantorders_farm_status ON restaurantorders(farmid, status);
CREATE INDEX IF NOT EXISTS ix_restaurantorders_farm_date ON restaurantorders(farmid, createdat DESC);
CREATE INDEX IF NOT EXISTS ix_restaurantorders_farm_table ON restaurantorders(farmid, tableid);

-- Add FK from tables to orders
ALTER TABLE restauranttables DROP CONSTRAINT IF EXISTS fk_restauranttables_currentorder;
ALTER TABLE restauranttables ADD CONSTRAINT fk_restauranttables_currentorder
    FOREIGN KEY (currentorderid) REFERENCES restaurantorders(orderid) ON DELETE SET NULL;

-- =============================================================================
-- 4. ORDER ITEMS
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantorderitems (
    orderitemid          SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    orderid              INT NOT NULL REFERENCES restaurantorders(orderid) ON DELETE CASCADE,
    menuitemid           INT REFERENCES restaurantmenuitems(menuitemid) ON DELETE SET NULL,
    comboid              INT REFERENCES restaurantcombos(comboid) ON DELETE SET NULL,
    itemname             TEXT NOT NULL,           -- snapshot at time of order
    quantity             INT DEFAULT 1,
    unitprice            NUMERIC(12,2) DEFAULT 0, -- snapshot price
    modifiertotal        NUMERIC(12,2) DEFAULT 0, -- sum of modifier price adjustments
    linetotal            NUMERIC(12,2) DEFAULT 0, -- (unitprice + modifiertotal) * quantity
    notes                TEXT,                    -- per-item special instructions
    status               TEXT DEFAULT 'Pending',  -- Pending, Preparing, Ready, Served, Cancelled
    seatnumber           INT,                     -- for bill splitting by seat
    kdsstation           TEXT,                     -- assigned kitchen station
    senttoktchenat       TIMESTAMP,
    prepstartedat        TIMESTAMP,
    readyat              TIMESTAMP,
    createdat            TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantorderitems_order ON restaurantorderitems(farmid, orderid);
CREATE INDEX IF NOT EXISTS ix_restaurantorderitems_status ON restaurantorderitems(farmid, status);

-- =============================================================================
-- 5. ORDER ITEM MODIFIERS (selected modifiers for each order item)
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantorderitemmodifiers (
    orderitemmodifierid  SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    orderitemid          INT NOT NULL REFERENCES restaurantorderitems(orderitemid) ON DELETE CASCADE,
    modifierid           INT REFERENCES restaurantmodifiers(modifierid) ON DELETE SET NULL,
    modifiername         TEXT NOT NULL,           -- snapshot
    priceadjustment      NUMERIC(12,2) DEFAULT 0, -- snapshot
    quantity             INT DEFAULT 1
);
CREATE INDEX IF NOT EXISTS ix_restaurantorderitemmods_item ON restaurantorderitemmodifiers(farmid, orderitemid);

-- =============================================================================
-- 6. ORDER PAYMENTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantorderpayments (
    orderpaymentid       SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    orderid              INT NOT NULL REFERENCES restaurantorders(orderid) ON DELETE CASCADE,
    paymentmethod        TEXT NOT NULL,           -- Cash, Card, MobileMoney, Voucher, GiftCard
    amount               NUMERIC(12,2) NOT NULL,
    tipamount            NUMERIC(12,2) DEFAULT 0,
    reference            TEXT,                    -- card ref, mobile money ref, voucher code
    status               TEXT DEFAULT 'Completed', -- Completed, Refunded, Voided
    processedby          TEXT,
    createdat            TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantorderpayments_order ON restaurantorderpayments(farmid, orderid);

-- =============================================================================
-- 7. DISCOUNTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantdiscounts (
    discountid           SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    name                 TEXT NOT NULL,
    discounttype         TEXT NOT NULL DEFAULT 'Percentage', -- Percentage, FixedAmount
    value                NUMERIC(12,2) NOT NULL,  -- % or fixed amount
    couponcode           TEXT,
    isautoapply          BOOLEAN DEFAULT FALSE,   -- auto-apply (e.g. happy hour)
    minorderamount       NUMERIC(12,2) DEFAULT 0,
    maxdiscountamount    NUMERIC(12,2),           -- cap for percentage discounts
    startdate            TIMESTAMP,
    enddate              TIMESTAMP,
    isactive             BOOLEAN DEFAULT TRUE,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantdiscounts_farm ON restaurantdiscounts(farmid);

-- Order-level discount application
CREATE TABLE IF NOT EXISTS restaurantorderdiscounts (
    orderdiscountid      SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    orderid              INT NOT NULL REFERENCES restaurantorders(orderid) ON DELETE CASCADE,
    discountid           INT REFERENCES restaurantdiscounts(discountid) ON DELETE SET NULL,
    discountname         TEXT NOT NULL,
    discounttype         TEXT NOT NULL,
    value                NUMERIC(12,2) NOT NULL,
    appliedamount        NUMERIC(12,2) NOT NULL,  -- actual discount amount
    createdat            TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantorderdiscounts_order ON restaurantorderdiscounts(farmid, orderid);

-- =============================================================================
-- STORED PROCEDURES: FLOORS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_floor_list(p_farmid TEXT)
RETURNS TABLE (
    floorid INT, farmid TEXT, name TEXT, floornumber INT, description TEXT,
    isactive BOOLEAN, sortorder INT, createdat TIMESTAMP, updatedat TIMESTAMP,
    tablecount BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT f.floorid, f.farmid, f.name, f.floornumber, f.description,
           f.isactive, f.sortorder, f.createdat, f.updatedat,
           (SELECT COUNT(*) FROM restauranttables t WHERE t.floorid = f.floorid AND t.farmid = f.farmid) AS tablecount
    FROM restaurantfloors f
    WHERE f.farmid = p_farmid
    ORDER BY f.sortorder, f.floornumber;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_floor_insert(
    p_farmid TEXT, p_name TEXT, p_floornumber INT, p_description TEXT,
    p_isactive BOOLEAN, p_sortorder INT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantfloors (farmid, name, floornumber, description, isactive, sortorder)
    VALUES (p_farmid, p_name, p_floornumber, p_description, p_isactive, p_sortorder)
    RETURNING floorid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_floor_update(
    p_id INT, p_farmid TEXT, p_name TEXT, p_floornumber INT,
    p_description TEXT, p_isactive BOOLEAN, p_sortorder INT
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantfloors SET name = p_name, floornumber = p_floornumber,
        description = p_description, isactive = p_isactive, sortorder = p_sortorder, updatedat = NOW()
    WHERE floorid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_floor_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantfloors WHERE floorid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: TABLES
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_table_list(p_farmid TEXT, p_floorid INT DEFAULT NULL, p_status TEXT DEFAULT NULL)
RETURNS TABLE (
    tableid INT, farmid TEXT, floorid INT, floorname TEXT, tablenumber TEXT,
    tablename TEXT, capacity INT, shape TEXT, status TEXT,
    positionx INT, positiony INT, width INT, height INT,
    isactive BOOLEAN, currentorderid INT, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT t.tableid, t.farmid, t.floorid, COALESCE(f.name, '') AS floorname,
           t.tablenumber, t.tablename, t.capacity, t.shape, t.status,
           t.positionx, t.positiony, t.width, t.height,
           t.isactive, t.currentorderid, t.createdat, t.updatedat
    FROM restauranttables t
    LEFT JOIN restaurantfloors f ON f.floorid = t.floorid AND f.farmid = t.farmid
    WHERE t.farmid = p_farmid
      AND (p_floorid IS NULL OR t.floorid = p_floorid)
      AND (p_status IS NULL OR t.status = p_status)
    ORDER BY t.tablenumber;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_table_get(p_id INT, p_farmid TEXT)
RETURNS TABLE (
    tableid INT, farmid TEXT, floorid INT, floorname TEXT, tablenumber TEXT,
    tablename TEXT, capacity INT, shape TEXT, status TEXT,
    positionx INT, positiony INT, width INT, height INT,
    isactive BOOLEAN, currentorderid INT, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT t.tableid, t.farmid, t.floorid, COALESCE(f.name, '') AS floorname,
           t.tablenumber, t.tablename, t.capacity, t.shape, t.status,
           t.positionx, t.positiony, t.width, t.height,
           t.isactive, t.currentorderid, t.createdat, t.updatedat
    FROM restauranttables t
    LEFT JOIN restaurantfloors f ON f.floorid = t.floorid AND f.farmid = t.farmid
    WHERE t.tableid = p_id AND t.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_table_insert(
    p_farmid TEXT, p_floorid INT, p_tablenumber TEXT, p_tablename TEXT,
    p_capacity INT, p_shape TEXT, p_positionx INT, p_positiony INT,
    p_width INT, p_height INT, p_isactive BOOLEAN
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restauranttables (farmid, floorid, tablenumber, tablename, capacity, shape,
        positionx, positiony, width, height, isactive)
    VALUES (p_farmid, p_floorid, p_tablenumber, p_tablename, p_capacity, p_shape,
        p_positionx, p_positiony, p_width, p_height, p_isactive)
    RETURNING tableid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_table_update(
    p_id INT, p_farmid TEXT, p_floorid INT, p_tablenumber TEXT, p_tablename TEXT,
    p_capacity INT, p_shape TEXT, p_positionx INT, p_positiony INT,
    p_width INT, p_height INT, p_isactive BOOLEAN
) RETURNS VOID AS $$
BEGIN
    UPDATE restauranttables SET floorid = p_floorid, tablenumber = p_tablenumber,
        tablename = p_tablename, capacity = p_capacity, shape = p_shape,
        positionx = p_positionx, positiony = p_positiony, width = p_width, height = p_height,
        isactive = p_isactive, updatedat = NOW()
    WHERE tableid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_table_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restauranttables WHERE tableid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_table_update_status(p_id INT, p_farmid TEXT, p_status TEXT, p_currentorderid INT DEFAULT NULL)
RETURNS VOID AS $$
BEGIN
    UPDATE restauranttables SET status = p_status, currentorderid = p_currentorderid, updatedat = NOW()
    WHERE tableid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_table_update_position(p_id INT, p_farmid TEXT, p_positionx INT, p_positiony INT)
RETURNS VOID AS $$
BEGIN
    UPDATE restauranttables SET positionx = p_positionx, positiony = p_positiony, updatedat = NOW()
    WHERE tableid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: ORDERS
-- =============================================================================

-- Generate next order number
CREATE OR REPLACE FUNCTION sprestaurant_order_next_number(p_farmid TEXT)
RETURNS TEXT AS $$
DECLARE v_seq INT; v_date TEXT;
BEGIN
    v_date := TO_CHAR(NOW(), 'YYYYMMDD');
    SELECT COALESCE(MAX(
        CASE WHEN ordernumber LIKE 'ORD-' || v_date || '-%'
             THEN CAST(SPLIT_PART(ordernumber, '-', 3) AS INT) ELSE 0 END
    ), 0) + 1 INTO v_seq
    FROM restaurantorders WHERE farmid = p_farmid;
    RETURN 'ORD-' || v_date || '-' || LPAD(v_seq::TEXT, 4, '0');
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_order_insert(
    p_farmid TEXT, p_ordertype TEXT, p_tableid INT, p_tablenumber TEXT,
    p_customerid INT, p_customername TEXT, p_customerphone TEXT,
    p_covers INT, p_notes TEXT, p_createdby TEXT, p_servedby TEXT
) RETURNS TABLE (
    orderid INT, ordernumber TEXT
) AS $$
DECLARE v_id INT; v_num TEXT;
BEGIN
    v_num := sprestaurant_order_next_number(p_farmid);
    INSERT INTO restaurantorders (farmid, ordernumber, ordertype, tableid, tablenumber,
        customerid, customername, customerphone, covers, notes, createdby, servedby)
    VALUES (p_farmid, v_num, p_ordertype, p_tableid, p_tablenumber,
        p_customerid, p_customername, p_customerphone, p_covers, p_notes, p_createdby, p_servedby)
    RETURNING restaurantorders.orderid INTO v_id;
    -- Mark table as occupied if dine-in
    IF p_tableid IS NOT NULL THEN
        UPDATE restauranttables SET status = 'Occupied', currentorderid = v_id, updatedat = NOW()
        WHERE restauranttables.tableid = p_tableid AND restauranttables.farmid = p_farmid;
    END IF;
    RETURN QUERY SELECT v_id, v_num;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_order_list(
    p_farmid TEXT, p_status TEXT DEFAULT NULL, p_ordertype TEXT DEFAULT NULL,
    p_fromdate TIMESTAMP DEFAULT NULL, p_todate TIMESTAMP DEFAULT NULL
)
RETURNS TABLE (
    orderid INT, farmid TEXT, ordernumber TEXT, ordertype TEXT, status TEXT,
    tableid INT, tablenumber TEXT, customerid INT, customername TEXT, customerphone TEXT,
    covers INT, subtotal NUMERIC, discountamount NUMERIC, taxamount NUMERIC,
    servicechargeamount NUMERIC, totalamount NUMERIC, paidamount NUMERIC,
    paymentstatus TEXT, notes TEXT, createdby TEXT, servedby TEXT,
    cancelreason TEXT, refundreason TEXT,
    createdat TIMESTAMP, updatedat TIMESTAMP, completedat TIMESTAMP,
    itemcount BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT o.orderid, o.farmid, o.ordernumber, o.ordertype, o.status,
           o.tableid, o.tablenumber, o.customerid, o.customername, o.customerphone,
           o.covers, o.subtotal, o.discountamount, o.taxamount,
           o.servicechargeamount, o.totalamount, o.paidamount,
           o.paymentstatus, o.notes, o.createdby, o.servedby,
           o.cancelreason, o.refundreason,
           o.createdat, o.updatedat, o.completedat,
           (SELECT COUNT(*) FROM restaurantorderitems i WHERE i.orderid = o.orderid) AS itemcount
    FROM restaurantorders o
    WHERE o.farmid = p_farmid
      AND (p_status IS NULL OR o.status = p_status)
      AND (p_ordertype IS NULL OR o.ordertype = p_ordertype)
      AND (p_fromdate IS NULL OR o.createdat >= p_fromdate)
      AND (p_todate IS NULL OR o.createdat <= p_todate)
    ORDER BY o.createdat DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_order_get(p_id INT, p_farmid TEXT)
RETURNS TABLE (
    orderid INT, farmid TEXT, ordernumber TEXT, ordertype TEXT, status TEXT,
    tableid INT, tablenumber TEXT, customerid INT, customername TEXT, customerphone TEXT,
    covers INT, subtotal NUMERIC, discountamount NUMERIC, taxamount NUMERIC,
    servicechargeamount NUMERIC, totalamount NUMERIC, paidamount NUMERIC,
    paymentstatus TEXT, notes TEXT, createdby TEXT, servedby TEXT,
    cancelreason TEXT, refundreason TEXT,
    createdat TIMESTAMP, updatedat TIMESTAMP, completedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT o.orderid, o.farmid, o.ordernumber, o.ordertype, o.status,
           o.tableid, o.tablenumber, o.customerid, o.customername, o.customerphone,
           o.covers, o.subtotal, o.discountamount, o.taxamount,
           o.servicechargeamount, o.totalamount, o.paidamount,
           o.paymentstatus, o.notes, o.createdby, o.servedby,
           o.cancelreason, o.refundreason,
           o.createdat, o.updatedat, o.completedat
    FROM restaurantorders o
    WHERE o.orderid = p_id AND o.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_order_update_status(
    p_id INT, p_farmid TEXT, p_status TEXT, p_reason TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantorders SET status = p_status, updatedat = NOW(),
        cancelreason = CASE WHEN p_status = 'Cancelled' THEN p_reason ELSE cancelreason END,
        refundreason = CASE WHEN p_status = 'Refunded' THEN p_reason ELSE refundreason END,
        completedat = CASE WHEN p_status IN ('Completed','Cancelled','Refunded') THEN NOW() ELSE completedat END
    WHERE orderid = p_id AND farmid = p_farmid;
    -- Free the table when order completes/cancels
    IF p_status IN ('Completed', 'Cancelled') THEN
        UPDATE restauranttables SET status = 'NeedsCleaning', currentorderid = NULL, updatedat = NOW()
        WHERE currentorderid = p_id AND farmid = p_farmid;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Recalculate order totals from items
CREATE OR REPLACE FUNCTION sprestaurant_order_recalc(p_orderid INT, p_farmid TEXT, p_taxrate NUMERIC DEFAULT 0, p_servicechargerate NUMERIC DEFAULT 0)
RETURNS VOID AS $$
DECLARE v_sub NUMERIC; v_disc NUMERIC; v_tax NUMERIC; v_sc NUMERIC;
BEGIN
    SELECT COALESCE(SUM(linetotal), 0) INTO v_sub FROM restaurantorderitems WHERE orderid = p_orderid AND farmid = p_farmid AND status != 'Cancelled';
    SELECT COALESCE(SUM(appliedamount), 0) INTO v_disc FROM restaurantorderdiscounts WHERE orderid = p_orderid AND farmid = p_farmid;
    v_tax := ROUND((v_sub - v_disc) * p_taxrate / 100, 2);
    v_sc := ROUND((v_sub - v_disc) * p_servicechargerate / 100, 2);
    UPDATE restaurantorders SET subtotal = v_sub, discountamount = v_disc, taxamount = v_tax,
        servicechargeamount = v_sc, totalamount = v_sub - v_disc + v_tax + v_sc, updatedat = NOW()
    WHERE orderid = p_orderid AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: ORDER ITEMS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_orderitem_insert(
    p_farmid TEXT, p_orderid INT, p_menuitemid INT, p_comboid INT,
    p_itemname TEXT, p_quantity INT, p_unitprice NUMERIC,
    p_notes TEXT, p_seatnumber INT, p_kdsstation TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantorderitems (farmid, orderid, menuitemid, comboid, itemname,
        quantity, unitprice, linetotal, notes, seatnumber, kdsstation)
    VALUES (p_farmid, p_orderid, p_menuitemid, p_comboid, p_itemname,
        p_quantity, p_unitprice, p_unitprice * p_quantity, p_notes, p_seatnumber, p_kdsstation)
    RETURNING orderitemid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_orderitem_list(p_orderid INT, p_farmid TEXT)
RETURNS TABLE (
    orderitemid INT, farmid TEXT, orderid INT, menuitemid INT, comboid INT,
    itemname TEXT, quantity INT, unitprice NUMERIC, modifiertotal NUMERIC,
    linetotal NUMERIC, notes TEXT, status TEXT, seatnumber INT, kdsstation TEXT,
    senttoktchenat TIMESTAMP, prepstartedat TIMESTAMP, readyat TIMESTAMP, createdat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT i.orderitemid, i.farmid, i.orderid, i.menuitemid, i.comboid,
           i.itemname, i.quantity, i.unitprice, i.modifiertotal,
           i.linetotal, i.notes, i.status, i.seatnumber, i.kdsstation,
           i.senttoktchenat, i.prepstartedat, i.readyat, i.createdat
    FROM restaurantorderitems i
    WHERE i.orderid = p_orderid AND i.farmid = p_farmid
    ORDER BY i.createdat;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_orderitem_update_status(p_id INT, p_farmid TEXT, p_status TEXT)
RETURNS VOID AS $$
BEGIN
    UPDATE restaurantorderitems SET status = p_status,
        senttoktchenat = CASE WHEN p_status = 'Preparing' AND senttoktchenat IS NULL THEN NOW() ELSE senttoktchenat END,
        prepstartedat = CASE WHEN p_status = 'Preparing' THEN NOW() ELSE prepstartedat END,
        readyat = CASE WHEN p_status = 'Ready' THEN NOW() ELSE readyat END
    WHERE orderitemid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_orderitem_cancel(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    UPDATE restaurantorderitems SET status = 'Cancelled' WHERE orderitemid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Recalc item line total after modifier changes
CREATE OR REPLACE FUNCTION sprestaurant_orderitem_recalc(p_orderitemid INT, p_farmid TEXT)
RETURNS VOID AS $$
DECLARE v_modtotal NUMERIC; v_qty INT; v_unit NUMERIC;
BEGIN
    SELECT COALESCE(SUM(priceadjustment * quantity), 0) INTO v_modtotal
    FROM restaurantorderitemmodifiers WHERE orderitemid = p_orderitemid AND farmid = p_farmid;
    SELECT quantity, unitprice INTO v_qty, v_unit FROM restaurantorderitems WHERE orderitemid = p_orderitemid AND farmid = p_farmid;
    UPDATE restaurantorderitems SET modifiertotal = v_modtotal, linetotal = (v_unit + v_modtotal) * v_qty
    WHERE orderitemid = p_orderitemid AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: ORDER ITEM MODIFIERS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_orderitemmod_insert(
    p_farmid TEXT, p_orderitemid INT, p_modifierid INT,
    p_modifiername TEXT, p_priceadjustment NUMERIC, p_quantity INT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantorderitemmodifiers (farmid, orderitemid, modifierid, modifiername, priceadjustment, quantity)
    VALUES (p_farmid, p_orderitemid, p_modifierid, p_modifiername, p_priceadjustment, p_quantity)
    RETURNING orderitemmodifierid INTO v_id;
    -- recalc item line total
    PERFORM sprestaurant_orderitem_recalc(p_orderitemid, p_farmid);
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_orderitemmod_list(p_orderitemid INT, p_farmid TEXT)
RETURNS TABLE (
    orderitemmodifierid INT, farmid TEXT, orderitemid INT, modifierid INT,
    modifiername TEXT, priceadjustment NUMERIC, quantity INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT m.orderitemmodifierid, m.farmid, m.orderitemid, m.modifierid,
           m.modifiername, m.priceadjustment, m.quantity
    FROM restaurantorderitemmodifiers m
    WHERE m.orderitemid = p_orderitemid AND m.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: ORDER PAYMENTS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_orderpayment_insert(
    p_farmid TEXT, p_orderid INT, p_paymentmethod TEXT, p_amount NUMERIC,
    p_tipamount NUMERIC, p_reference TEXT, p_processedby TEXT
) RETURNS INT AS $$
DECLARE v_id INT; v_paid NUMERIC;
BEGIN
    INSERT INTO restaurantorderpayments (farmid, orderid, paymentmethod, amount, tipamount, reference, processedby)
    VALUES (p_farmid, p_orderid, p_paymentmethod, p_amount, p_tipamount, p_reference, p_processedby)
    RETURNING orderpaymentid INTO v_id;
    -- Update paid amount and payment status
    SELECT COALESCE(SUM(amount), 0) INTO v_paid FROM restaurantorderpayments
    WHERE orderid = p_orderid AND farmid = p_farmid AND status = 'Completed';
    UPDATE restaurantorders SET paidamount = v_paid, updatedat = NOW(),
        paymentstatus = CASE
            WHEN v_paid >= totalamount THEN 'Paid'
            WHEN v_paid > 0 THEN 'Partial'
            ELSE 'Unpaid'
        END
    WHERE orderid = p_orderid AND farmid = p_farmid;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_orderpayment_list(p_orderid INT, p_farmid TEXT)
RETURNS TABLE (
    orderpaymentid INT, farmid TEXT, orderid INT, paymentmethod TEXT,
    amount NUMERIC, tipamount NUMERIC, reference TEXT, status TEXT,
    processedby TEXT, createdat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT p.orderpaymentid, p.farmid, p.orderid, p.paymentmethod,
           p.amount, p.tipamount, p.reference, p.status,
           p.processedby, p.createdat
    FROM restaurantorderpayments p
    WHERE p.orderid = p_orderid AND p.farmid = p_farmid
    ORDER BY p.createdat;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: DISCOUNTS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_discount_list(p_farmid TEXT)
RETURNS TABLE (
    discountid INT, farmid TEXT, name TEXT, discounttype TEXT, value NUMERIC,
    couponcode TEXT, isautoapply BOOLEAN, minorderamount NUMERIC,
    maxdiscountamount NUMERIC, startdate TIMESTAMP, enddate TIMESTAMP,
    isactive BOOLEAN, createdat TIMESTAMP, updatedat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT d.discountid, d.farmid, d.name, d.discounttype, d.value,
           d.couponcode, d.isautoapply, d.minorderamount,
           d.maxdiscountamount, d.startdate, d.enddate,
           d.isactive, d.createdat, d.updatedat
    FROM restaurantdiscounts d
    WHERE d.farmid = p_farmid
    ORDER BY d.name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_discount_insert(
    p_farmid TEXT, p_name TEXT, p_discounttype TEXT, p_value NUMERIC,
    p_couponcode TEXT, p_isautoapply BOOLEAN, p_minorderamount NUMERIC,
    p_maxdiscountamount NUMERIC, p_startdate TIMESTAMP, p_enddate TIMESTAMP,
    p_isactive BOOLEAN
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantdiscounts (farmid, name, discounttype, value, couponcode, isautoapply,
        minorderamount, maxdiscountamount, startdate, enddate, isactive)
    VALUES (p_farmid, p_name, p_discounttype, p_value, p_couponcode, p_isautoapply,
        p_minorderamount, p_maxdiscountamount, p_startdate, p_enddate, p_isactive)
    RETURNING discountid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_discount_update(
    p_id INT, p_farmid TEXT, p_name TEXT, p_discounttype TEXT, p_value NUMERIC,
    p_couponcode TEXT, p_isautoapply BOOLEAN, p_minorderamount NUMERIC,
    p_maxdiscountamount NUMERIC, p_startdate TIMESTAMP, p_enddate TIMESTAMP,
    p_isactive BOOLEAN
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantdiscounts SET name = p_name, discounttype = p_discounttype, value = p_value,
        couponcode = p_couponcode, isautoapply = p_isautoapply, minorderamount = p_minorderamount,
        maxdiscountamount = p_maxdiscountamount, startdate = p_startdate, enddate = p_enddate,
        isactive = p_isactive, updatedat = NOW()
    WHERE discountid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_discount_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantdiscounts WHERE discountid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Apply discount to order
CREATE OR REPLACE FUNCTION sprestaurant_orderdiscount_apply(
    p_farmid TEXT, p_orderid INT, p_discountid INT, p_discountname TEXT,
    p_discounttype TEXT, p_value NUMERIC, p_appliedamount NUMERIC
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantorderdiscounts (farmid, orderid, discountid, discountname, discounttype, value, appliedamount)
    VALUES (p_farmid, p_orderid, p_discountid, p_discountname, p_discounttype, p_value, p_appliedamount)
    RETURNING orderdiscountid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_orderdiscount_remove(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantorderdiscounts WHERE orderdiscountid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_orderdiscount_list(p_orderid INT, p_farmid TEXT)
RETURNS TABLE (
    orderdiscountid INT, farmid TEXT, orderid INT, discountid INT,
    discountname TEXT, discounttype TEXT, value NUMERIC, appliedamount NUMERIC,
    createdat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT d.orderdiscountid, d.farmid, d.orderid, d.discountid,
           d.discountname, d.discounttype, d.value, d.appliedamount, d.createdat
    FROM restaurantorderdiscounts d
    WHERE d.orderid = p_orderid AND d.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;
