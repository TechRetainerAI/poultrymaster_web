-- Migration 222: Restaurant Management System — Inventory & Recipes
-- Applied: 2026-08-30
-- Phase R7: Ingredients, recipes, stock tracking, waste, food cost

-- =============================================================================
-- 1. INGREDIENTS (raw materials / inventory items)
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantingredients (
    ingredientid         SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    name                 TEXT NOT NULL,
    category             TEXT,                     -- Proteins, Dairy, Produce, Dry Goods, Spices, Beverages, etc.
    unit                 TEXT NOT NULL DEFAULT 'kg', -- kg, g, L, mL, pcs, dozen, bag, box
    costperunit          NUMERIC(12,4) DEFAULT 0,
    currentstock         NUMERIC(12,4) DEFAULT 0,
    parlevel             NUMERIC(12,4) DEFAULT 0,  -- minimum stock before reorder
    reorderpoint         NUMERIC(12,4) DEFAULT 0,
    supplierid           INT,
    suppliername         TEXT,
    expirydays           INT,                      -- shelf life in days
    storagearea          TEXT,                      -- Walk-in, Freezer, Dry Store, Bar
    isactive             BOOLEAN DEFAULT TRUE,
    notes                TEXT,
    createdat            TIMESTAMP DEFAULT NOW(),
    updatedat            TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantingredients_farm ON restaurantingredients(farmid);

-- =============================================================================
-- 2. RECIPES (ingredient list per menu item)
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantrecipes (
    recipeid             SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    menuitemid           INT NOT NULL REFERENCES restaurantmenuitems(menuitemid) ON DELETE CASCADE,
    ingredientid         INT NOT NULL REFERENCES restaurantingredients(ingredientid) ON DELETE CASCADE,
    quantity             NUMERIC(12,4) NOT NULL,   -- amount of ingredient per 1 menu item
    unit                 TEXT NOT NULL,
    wastepercent         NUMERIC(5,2) DEFAULT 0,   -- prep waste % (e.g. 10% for peeling)
    notes                TEXT,
    UNIQUE(farmid, menuitemid, ingredientid)
);
CREATE INDEX IF NOT EXISTS ix_restaurantrecipes_item ON restaurantrecipes(farmid, menuitemid);

-- =============================================================================
-- 3. STOCK MOVEMENTS
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantstockmovements (
    stockmovementid      SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    ingredientid         INT NOT NULL REFERENCES restaurantingredients(ingredientid) ON DELETE CASCADE,
    movementtype         TEXT NOT NULL,             -- PurchaseIn, OrderDeduction, WasteOut, AdjustmentIn, AdjustmentOut, TransferIn, TransferOut
    quantity             NUMERIC(12,4) NOT NULL,    -- positive for in, negative for out
    unitcost             NUMERIC(12,4),
    reference            TEXT,                      -- order number, PO number, etc.
    reason               TEXT,
    createdby            TEXT,
    createdat            TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantstockmovements_farm ON restaurantstockmovements(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantstockmovements_ingredient ON restaurantstockmovements(farmid, ingredientid);

-- =============================================================================
-- 4. WASTE LOG
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantwastelog (
    wastelogid           SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    ingredientid         INT REFERENCES restaurantingredients(ingredientid) ON DELETE SET NULL,
    menuitemid           INT REFERENCES restaurantmenuitems(menuitemid) ON DELETE SET NULL,
    ingredientname       TEXT NOT NULL,
    quantity             NUMERIC(12,4) NOT NULL,
    unit                 TEXT NOT NULL,
    costamount           NUMERIC(12,2) DEFAULT 0,
    reason               TEXT NOT NULL,            -- Spoilage, PrepWaste, Returned, Expired, Spillage, Overproduction, Other
    notes                TEXT,
    loggedby             TEXT,
    createdat            TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_restaurantwastelog_farm ON restaurantwastelog(farmid);
CREATE INDEX IF NOT EXISTS ix_restaurantwastelog_farm_date ON restaurantwastelog(farmid, createdat DESC);

-- =============================================================================
-- 5. STOCK TAKES
-- =============================================================================

CREATE TABLE IF NOT EXISTS restaurantstocktakes (
    stocktakeid          SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    takedate             DATE NOT NULL DEFAULT CURRENT_DATE,
    status               TEXT DEFAULT 'Draft',      -- Draft, Completed
    notes                TEXT,
    completedby          TEXT,
    createdat            TIMESTAMP DEFAULT NOW(),
    completedat          TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_restaurantstocktakes_farm ON restaurantstocktakes(farmid);

CREATE TABLE IF NOT EXISTS restaurantstocktakeitems (
    stocktakeitemid      SERIAL PRIMARY KEY,
    farmid               TEXT NOT NULL,
    stocktakeid          INT NOT NULL REFERENCES restaurantstocktakes(stocktakeid) ON DELETE CASCADE,
    ingredientid         INT NOT NULL REFERENCES restaurantingredients(ingredientid) ON DELETE CASCADE,
    systemqty            NUMERIC(12,4) DEFAULT 0,
    actualqty            NUMERIC(12,4) DEFAULT 0,
    variance             NUMERIC(12,4) DEFAULT 0,
    unit                 TEXT,
    notes                TEXT
);
CREATE INDEX IF NOT EXISTS ix_restaurantstocktakeitems_take ON restaurantstocktakeitems(farmid, stocktakeid);

-- =============================================================================
-- STORED PROCEDURES: INGREDIENTS
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_ingredient_list(p_farmid TEXT, p_category TEXT DEFAULT NULL)
RETURNS TABLE (
    ingredientid INT, farmid TEXT, name TEXT, category TEXT, unit TEXT,
    costperunit NUMERIC, currentstock NUMERIC, parlevel NUMERIC,
    reorderpoint NUMERIC, supplierid INT, suppliername TEXT, expirydays INT,
    storagearea TEXT, isactive BOOLEAN, notes TEXT,
    createdat TIMESTAMP, updatedat TIMESTAMP, islow BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT i.ingredientid, i.farmid, i.name, i.category, i.unit,
           i.costperunit, i.currentstock, i.parlevel, i.reorderpoint,
           i.supplierid, i.suppliername, i.expirydays, i.storagearea,
           i.isactive, i.notes, i.createdat, i.updatedat,
           (i.currentstock <= i.reorderpoint AND i.reorderpoint > 0) AS islow
    FROM restaurantingredients i
    WHERE i.farmid = p_farmid
      AND (p_category IS NULL OR i.category = p_category)
    ORDER BY i.category, i.name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_ingredient_insert(
    p_farmid TEXT, p_name TEXT, p_category TEXT, p_unit TEXT,
    p_costperunit NUMERIC, p_currentstock NUMERIC, p_parlevel NUMERIC,
    p_reorderpoint NUMERIC, p_suppliername TEXT, p_expirydays INT,
    p_storagearea TEXT, p_notes TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantingredients (farmid, name, category, unit, costperunit,
        currentstock, parlevel, reorderpoint, suppliername, expirydays, storagearea, notes)
    VALUES (p_farmid, p_name, p_category, p_unit, p_costperunit,
        p_currentstock, p_parlevel, p_reorderpoint, p_suppliername, p_expirydays, p_storagearea, p_notes)
    RETURNING ingredientid INTO v_id;
    -- Record opening stock movement
    IF p_currentstock > 0 THEN
        INSERT INTO restaurantstockmovements (farmid, ingredientid, movementtype, quantity, unitcost, reference)
        VALUES (p_farmid, v_id, 'OpeningStock', p_currentstock, p_costperunit, 'Initial stock');
    END IF;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_ingredient_update(
    p_id INT, p_farmid TEXT, p_name TEXT, p_category TEXT, p_unit TEXT,
    p_costperunit NUMERIC, p_parlevel NUMERIC, p_reorderpoint NUMERIC,
    p_suppliername TEXT, p_expirydays INT, p_storagearea TEXT, p_isactive BOOLEAN, p_notes TEXT
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantingredients SET name = p_name, category = p_category, unit = p_unit,
        costperunit = p_costperunit, parlevel = p_parlevel, reorderpoint = p_reorderpoint,
        suppliername = p_suppliername, expirydays = p_expirydays, storagearea = p_storagearea,
        isactive = p_isactive, notes = p_notes, updatedat = NOW()
    WHERE ingredientid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_ingredient_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantingredients WHERE ingredientid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Adjust stock manually
CREATE OR REPLACE FUNCTION sprestaurant_ingredient_adjust_stock(
    p_id INT, p_farmid TEXT, p_quantity NUMERIC, p_movementtype TEXT, p_reason TEXT, p_createdby TEXT
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantingredients SET currentstock = currentstock + p_quantity, updatedat = NOW()
    WHERE ingredientid = p_id AND farmid = p_farmid;
    INSERT INTO restaurantstockmovements (farmid, ingredientid, movementtype, quantity, reason, createdby)
    VALUES (p_farmid, p_id, p_movementtype, p_quantity, p_reason, p_createdby);
END;
$$ LANGUAGE plpgsql;

-- Low stock report
CREATE OR REPLACE FUNCTION sprestaurant_ingredient_lowstock(p_farmid TEXT)
RETURNS TABLE (
    ingredientid INT, name TEXT, category TEXT, unit TEXT,
    currentstock NUMERIC, reorderpoint NUMERIC, parlevel NUMERIC,
    costperunit NUMERIC, suppliername TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT i.ingredientid, i.name, i.category, i.unit,
           i.currentstock, i.reorderpoint, i.parlevel,
           i.costperunit, i.suppliername
    FROM restaurantingredients i
    WHERE i.farmid = p_farmid AND i.isactive = TRUE
      AND i.reorderpoint > 0 AND i.currentstock <= i.reorderpoint
    ORDER BY (i.currentstock / NULLIF(i.reorderpoint, 0));
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: RECIPES
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_recipe_list(p_menuitemid INT, p_farmid TEXT)
RETURNS TABLE (
    recipeid INT, farmid TEXT, menuitemid INT, ingredientid INT,
    ingredientname TEXT, quantity NUMERIC, unit TEXT, wastepercent NUMERIC,
    notes TEXT, costperunit NUMERIC, linecost NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT r.recipeid, r.farmid, r.menuitemid, r.ingredientid,
           i.name AS ingredientname, r.quantity, r.unit, r.wastepercent, r.notes,
           i.costperunit,
           ROUND(r.quantity * (1 + r.wastepercent / 100) * i.costperunit, 4) AS linecost
    FROM restaurantrecipes r
    JOIN restaurantingredients i ON i.ingredientid = r.ingredientid AND i.farmid = r.farmid
    WHERE r.menuitemid = p_menuitemid AND r.farmid = p_farmid
    ORDER BY i.name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_recipe_upsert(
    p_farmid TEXT, p_menuitemid INT, p_ingredientid INT, p_quantity NUMERIC,
    p_unit TEXT, p_wastepercent NUMERIC, p_notes TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantrecipes (farmid, menuitemid, ingredientid, quantity, unit, wastepercent, notes)
    VALUES (p_farmid, p_menuitemid, p_ingredientid, p_quantity, p_unit, p_wastepercent, p_notes)
    ON CONFLICT (farmid, menuitemid, ingredientid) DO UPDATE SET
        quantity = p_quantity, unit = p_unit, wastepercent = p_wastepercent, notes = p_notes
    RETURNING recipeid INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_recipe_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    DELETE FROM restaurantrecipes WHERE recipeid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Food cost for a menu item (sum of recipe ingredient costs)
CREATE OR REPLACE FUNCTION sprestaurant_recipe_foodcost(p_menuitemid INT, p_farmid TEXT)
RETURNS TABLE (totalcost NUMERIC, sellingprice NUMERIC, foodcostpercent NUMERIC) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(SUM(ROUND(r.quantity * (1 + r.wastepercent / 100) * i.costperunit, 4)), 0) AS totalcost,
        mi.price AS sellingprice,
        CASE WHEN mi.price > 0 THEN
            ROUND(COALESCE(SUM(ROUND(r.quantity * (1 + r.wastepercent / 100) * i.costperunit, 4)), 0) / mi.price * 100, 2)
        ELSE 0 END AS foodcostpercent
    FROM restaurantmenuitems mi
    LEFT JOIN restaurantrecipes r ON r.menuitemid = mi.menuitemid AND r.farmid = mi.farmid
    LEFT JOIN restaurantingredients i ON i.ingredientid = r.ingredientid AND i.farmid = r.farmid
    WHERE mi.menuitemid = p_menuitemid AND mi.farmid = p_farmid
    GROUP BY mi.price;
END;
$$ LANGUAGE plpgsql;

-- Deduct stock for an order (called when order is confirmed/completed)
CREATE OR REPLACE FUNCTION sprestaurant_recipe_deduct_order(p_orderid INT, p_farmid TEXT)
RETURNS INT AS $$
DECLARE v_count INT := 0; v_item RECORD;
BEGIN
    FOR v_item IN
        SELECT oi.menuitemid, oi.quantity AS orderqty, oi.orderitemid
        FROM restaurantorderitems oi
        WHERE oi.orderid = p_orderid AND oi.farmid = p_farmid
          AND oi.menuitemid IS NOT NULL AND oi.status != 'Cancelled'
    LOOP
        INSERT INTO restaurantstockmovements (farmid, ingredientid, movementtype, quantity, reference, createdby)
        SELECT p_farmid, r.ingredientid, 'OrderDeduction',
               -(r.quantity * (1 + r.wastepercent / 100) * v_item.orderqty),
               'Order #' || p_orderid, 'System'
        FROM restaurantrecipes r WHERE r.menuitemid = v_item.menuitemid AND r.farmid = p_farmid;

        UPDATE restaurantingredients SET
            currentstock = currentstock - (
                SELECT COALESCE(SUM(r.quantity * (1 + r.wastepercent / 100) * v_item.orderqty), 0)
                FROM restaurantrecipes r WHERE r.menuitemid = v_item.menuitemid AND r.farmid = p_farmid
            ), updatedat = NOW()
        WHERE farmid = p_farmid AND ingredientid IN (
            SELECT r.ingredientid FROM restaurantrecipes r WHERE r.menuitemid = v_item.menuitemid AND r.farmid = p_farmid
        );
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: WASTE LOG
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_wastelog_list(p_farmid TEXT, p_fromdate TIMESTAMP DEFAULT NULL, p_todate TIMESTAMP DEFAULT NULL)
RETURNS TABLE (
    wastelogid INT, farmid TEXT, ingredientid INT, menuitemid INT,
    ingredientname TEXT, quantity NUMERIC, unit TEXT, costamount NUMERIC,
    reason TEXT, notes TEXT, loggedby TEXT, createdat TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT w.wastelogid, w.farmid, w.ingredientid, w.menuitemid,
           w.ingredientname, w.quantity, w.unit, w.costamount,
           w.reason, w.notes, w.loggedby, w.createdat
    FROM restaurantwastelog w
    WHERE w.farmid = p_farmid
      AND (p_fromdate IS NULL OR w.createdat >= p_fromdate)
      AND (p_todate IS NULL OR w.createdat <= p_todate)
    ORDER BY w.createdat DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_wastelog_insert(
    p_farmid TEXT, p_ingredientid INT, p_menuitemid INT, p_ingredientname TEXT,
    p_quantity NUMERIC, p_unit TEXT, p_costamount NUMERIC, p_reason TEXT,
    p_notes TEXT, p_loggedby TEXT
) RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantwastelog (farmid, ingredientid, menuitemid, ingredientname,
        quantity, unit, costamount, reason, notes, loggedby)
    VALUES (p_farmid, p_ingredientid, p_menuitemid, p_ingredientname,
        p_quantity, p_unit, p_costamount, p_reason, p_notes, p_loggedby)
    RETURNING wastelogid INTO v_id;
    -- Deduct from stock
    IF p_ingredientid IS NOT NULL THEN
        UPDATE restaurantingredients SET currentstock = currentstock - p_quantity, updatedat = NOW()
        WHERE ingredientid = p_ingredientid AND farmid = p_farmid;
        INSERT INTO restaurantstockmovements (farmid, ingredientid, movementtype, quantity, reason, createdby)
        VALUES (p_farmid, p_ingredientid, 'WasteOut', -p_quantity, p_reason || ': ' || COALESCE(p_notes, ''), p_loggedby);
    END IF;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Waste summary by reason
CREATE OR REPLACE FUNCTION sprestaurant_wastelog_summary(p_farmid TEXT, p_fromdate TIMESTAMP DEFAULT NULL, p_todate TIMESTAMP DEFAULT NULL)
RETURNS TABLE (reason TEXT, total_quantity NUMERIC, total_cost NUMERIC, count BIGINT) AS $$
BEGIN
    RETURN QUERY
    SELECT w.reason, SUM(w.quantity) AS total_quantity, SUM(w.costamount) AS total_cost, COUNT(*) AS count
    FROM restaurantwastelog w
    WHERE w.farmid = p_farmid
      AND (p_fromdate IS NULL OR w.createdat >= p_fromdate)
      AND (p_todate IS NULL OR w.createdat <= p_todate)
    GROUP BY w.reason ORDER BY total_cost DESC;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- STORED PROCEDURES: STOCK TAKES
-- =============================================================================

CREATE OR REPLACE FUNCTION sprestaurant_stocktake_list(p_farmid TEXT)
RETURNS TABLE (
    stocktakeid INT, farmid TEXT, takedate DATE, status TEXT,
    notes TEXT, completedby TEXT, createdat TIMESTAMP, completedat TIMESTAMP,
    itemcount BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT s.stocktakeid, s.farmid, s.takedate, s.status, s.notes, s.completedby,
           s.createdat, s.completedat,
           (SELECT COUNT(*) FROM restaurantstocktakeitems si WHERE si.stocktakeid = s.stocktakeid) AS itemcount
    FROM restaurantstocktakes s WHERE s.farmid = p_farmid ORDER BY s.createdat DESC;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_stocktake_create(p_farmid TEXT, p_notes TEXT)
RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO restaurantstocktakes (farmid, notes) VALUES (p_farmid, p_notes) RETURNING stocktakeid INTO v_id;
    -- Pre-populate with all active ingredients
    INSERT INTO restaurantstocktakeitems (farmid, stocktakeid, ingredientid, systemqty, unit)
    SELECT p_farmid, v_id, i.ingredientid, i.currentstock, i.unit
    FROM restaurantingredients i WHERE i.farmid = p_farmid AND i.isactive = TRUE;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_stocktake_items(p_stocktakeid INT, p_farmid TEXT)
RETURNS TABLE (
    stocktakeitemid INT, ingredientid INT, ingredientname TEXT, category TEXT,
    systemqty NUMERIC, actualqty NUMERIC, variance NUMERIC, unit TEXT, notes TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT si.stocktakeitemid, si.ingredientid, i.name AS ingredientname, i.category,
           si.systemqty, si.actualqty, si.variance, si.unit, si.notes
    FROM restaurantstocktakeitems si
    JOIN restaurantingredients i ON i.ingredientid = si.ingredientid
    WHERE si.stocktakeid = p_stocktakeid AND si.farmid = p_farmid
    ORDER BY i.category, i.name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_stocktake_update_item(
    p_id INT, p_farmid TEXT, p_actualqty NUMERIC, p_notes TEXT
) RETURNS VOID AS $$
BEGIN
    UPDATE restaurantstocktakeitems SET actualqty = p_actualqty,
        variance = p_actualqty - systemqty, notes = p_notes
    WHERE stocktakeitemid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sprestaurant_stocktake_complete(p_id INT, p_farmid TEXT, p_completedby TEXT)
RETURNS VOID AS $$
DECLARE v_item RECORD;
BEGIN
    FOR v_item IN SELECT * FROM restaurantstocktakeitems WHERE stocktakeid = p_id AND farmid = p_farmid AND variance != 0
    LOOP
        UPDATE restaurantingredients SET currentstock = v_item.actualqty, updatedat = NOW()
        WHERE ingredientid = v_item.ingredientid AND farmid = p_farmid;
        INSERT INTO restaurantstockmovements (farmid, ingredientid, movementtype, quantity, reason, createdby)
        VALUES (p_farmid, v_item.ingredientid,
            CASE WHEN v_item.variance > 0 THEN 'AdjustmentIn' ELSE 'AdjustmentOut' END,
            v_item.variance, 'Stock take adjustment', p_completedby);
    END LOOP;
    UPDATE restaurantstocktakes SET status = 'Completed', completedby = p_completedby, completedat = NOW()
    WHERE stocktakeid = p_id AND farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- Inventory value report
CREATE OR REPLACE FUNCTION sprestaurant_inventory_value(p_farmid TEXT)
RETURNS TABLE (
    ingredientid INT, name TEXT, category TEXT, unit TEXT,
    currentstock NUMERIC, costperunit NUMERIC, totalvalue NUMERIC,
    islow BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT i.ingredientid, i.name, i.category, i.unit,
           i.currentstock, i.costperunit,
           ROUND(i.currentstock * i.costperunit, 2) AS totalvalue,
           (i.currentstock <= i.reorderpoint AND i.reorderpoint > 0) AS islow
    FROM restaurantingredients i
    WHERE i.farmid = p_farmid AND i.isactive = TRUE
    ORDER BY totalvalue DESC;
END;
$$ LANGUAGE plpgsql;
