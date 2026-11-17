-- =============================================================================
-- Migration 441: Unified Item Architecture for Generic Business Type
-- Phase 1 of 5 — Shared item identity with multi-purpose capabilities.
--
-- Adds:
--   * CanSell, CanUseInProduction, CanUseInternally capability flags
--   * Description (richer item description, separate from Notes)
--   * PurchaseUnit, SalesUnit (separate from base stock UnitOfMeasure)
--   * UpdatedBy audit column
--
-- Backfills:
--   * Existing ItemType='Product' → CanSell = true
--   * Existing ItemType='SupplyItem' → CanUseInternally = true, CanSell = false
--   * Items with sale records → CanSell = true
--   * Items with production records → CanUseInProduction = true
--   * Items with internal usage records → CanUseInternally = true
--
-- Idempotent: safe to run multiple times.
-- =============================================================================

DO $$ BEGIN

-- =========================================================================
-- 1. Add capability flag columns
-- =========================================================================

IF NOT EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_name = 'genericproducts' AND column_name = 'cansell'
) THEN
  ALTER TABLE genericproducts ADD COLUMN cansell BOOLEAN NOT NULL DEFAULT TRUE;
  COMMENT ON COLUMN genericproducts.cansell IS
    '441. Whether this item can be sold to customers.';
END IF;

IF NOT EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_name = 'genericproducts' AND column_name = 'canuseinproduction'
) THEN
  ALTER TABLE genericproducts ADD COLUMN canuseinproduction BOOLEAN NOT NULL DEFAULT FALSE;
  COMMENT ON COLUMN genericproducts.canuseinproduction IS
    '441. Whether this item can be consumed or produced in production workflows.';
END IF;

IF NOT EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_name = 'genericproducts' AND column_name = 'canuseinternally'
) THEN
  ALTER TABLE genericproducts ADD COLUMN canuseinternally BOOLEAN NOT NULL DEFAULT FALSE;
  COMMENT ON COLUMN genericproducts.canuseinternally IS
    '441. Whether this item can be used for internal consumption (staff welfare, etc.).';
END IF;

-- =========================================================================
-- 2. Add description, unit, and audit columns
-- =========================================================================

IF NOT EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_name = 'genericproducts' AND column_name = 'description'
) THEN
  ALTER TABLE genericproducts ADD COLUMN description TEXT;
  COMMENT ON COLUMN genericproducts.description IS
    '441. Rich item description, separate from operational Notes.';
END IF;

IF NOT EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_name = 'genericproducts' AND column_name = 'purchaseunit'
) THEN
  ALTER TABLE genericproducts ADD COLUMN purchaseunit TEXT;
  COMMENT ON COLUMN genericproducts.purchaseunit IS
    '441. Unit used when purchasing (e.g. "bag"). Base stock unit remains UnitOfMeasure.';
END IF;

IF NOT EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_name = 'genericproducts' AND column_name = 'salesunit'
) THEN
  ALTER TABLE genericproducts ADD COLUMN salesunit TEXT;
  COMMENT ON COLUMN genericproducts.salesunit IS
    '441. Unit used when selling (e.g. "piece"). Base stock unit remains UnitOfMeasure.';
END IF;

IF NOT EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_name = 'genericproducts' AND column_name = 'updatedby'
) THEN
  ALTER TABLE genericproducts ADD COLUMN updatedby TEXT;
  COMMENT ON COLUMN genericproducts.updatedby IS
    '441. User who last updated this item.';
END IF;

-- =========================================================================
-- 3. Backfill capability flags from existing ItemType and usage history
-- =========================================================================

-- SupplyItem type: mark CanUseInternally, remove CanSell default
UPDATE genericproducts
SET cansell = FALSE, canuseinternally = TRUE
WHERE COALESCE("ItemType", 'Product') = 'SupplyItem'
  AND cansell = TRUE AND canuseinternally = FALSE;

-- Items that have been sold (SaleOut movements exist) → CanSell = true
UPDATE genericproducts p
SET cansell = TRUE
WHERE cansell = FALSE
  AND EXISTS (
    SELECT 1 FROM genericstockmovements m
    WHERE m.genericproductid = p.genericproductid
      AND m.farmid = p.farmid
      AND m.movementtype = 'SaleOut'
  );

-- Items that have production records → CanUseInProduction = true
UPDATE genericproducts p
SET canuseinproduction = TRUE
WHERE canuseinproduction = FALSE
  AND EXISTS (
    SELECT 1 FROM genericproductionrecords pr
    WHERE pr."GenericProductId" = p.genericproductid
      AND pr."FarmId" = p.farmid
      AND pr."Status" = 'Posted'
  );

-- Items that have internal usage records → CanUseInternally = true
UPDATE genericproducts p
SET canuseinternally = TRUE
WHERE canuseinternally = FALSE
  AND EXISTS (
    SELECT 1 FROM genericinternalusageitems iu
    INNER JOIN genericinternalusage h ON h.genericinternalusageid = iu.genericinternalusageid
    WHERE iu.genericproductid = p.genericproductid
      AND h.farmid = p.farmid
      AND h.status = 'Posted'
  );

END $$;

-- =========================================================================
-- 4. Replace stored procedures to include new columns
-- =========================================================================

-- GetAll: returns all non-deleted products for a farm, with capability flags
CREATE OR REPLACE FUNCTION spgenericproduct_getall(p_farmid TEXT)
RETURNS TABLE(
    "GenericProductId"         INT,
    "FarmId"                   TEXT,
    "GenericProductCategoryId" INT,
    "CategoryName"             TEXT,
    "ProductName"              TEXT,
    "SKU"                      TEXT,
    "Barcode"                  TEXT,
    "Description"              TEXT,
    "UnitOfMeasure"            TEXT,
    "PurchaseUnit"             TEXT,
    "SalesUnit"                TEXT,
    "CostPrice"                NUMERIC,
    "SellingPrice"             NUMERIC,
    "WholesalePrice"           NUMERIC,
    "RetailPrice"              NUMERIC,
    "OpeningStock"             NUMERIC,
    "CurrentStock"             NUMERIC,
    "MinimumStockAlert"        NUMERIC,
    "TrackInventory"           BOOLEAN,
    "SupplierId"               INT,
    "ItemType"                 TEXT,
    "CanSell"                  BOOLEAN,
    "CanUseInProduction"       BOOLEAN,
    "CanUseInternally"         BOOLEAN,
    "IsActive"                 BOOLEAN,
    "IsDeleted"                BOOLEAN,
    "Notes"                    TEXT,
    "ExpiryDate"               DATE,
    "TrackExpiry"              BOOLEAN,
    "CreatedBy"                TEXT,
    "CreatedAt"                TIMESTAMP,
    "UpdatedAt"                TIMESTAMP,
    "UpdatedBy"                TEXT
) LANGUAGE sql STABLE AS $$
    SELECT
        p.genericproductid,
        p.farmid,
        p.genericproductcategoryid,
        c.name,
        p.productname,
        p.sku,
        p.barcode,
        p.description,
        p.unitofmeasure,
        p.purchaseunit,
        p.salesunit,
        p.costprice,
        p.sellingprice,
        p.wholesaleprice,
        p.retailprice,
        p.openingstock,
        p.currentstock,
        p.minimumstockalert,
        p.trackinventory,
        p.supplierid,
        COALESCE(p."ItemType", 'Product'),
        p.cansell,
        p.canuseinproduction,
        p.canuseinternally,
        p.isactive,
        p.isdeleted,
        p.notes,
        p.expirydate,
        p.trackexpiry,
        p.createdby,
        p.createdat,
        p.updatedat,
        p.updatedby
    FROM genericproducts p
    LEFT JOIN genericproductcategories c
      ON c.genericproductcategoryid = p.genericproductcategoryid
    WHERE p.farmid = p_farmid AND p.isdeleted = FALSE
    ORDER BY p.isactive DESC, p.productname;
$$;

-- GetById: returns one product by ID and farm
CREATE OR REPLACE FUNCTION spgenericproduct_getbyid(
    p_genericproductid INT,
    p_farmid TEXT
)
RETURNS TABLE(
    "GenericProductId"         INT,
    "FarmId"                   TEXT,
    "GenericProductCategoryId" INT,
    "CategoryName"             TEXT,
    "ProductName"              TEXT,
    "SKU"                      TEXT,
    "Barcode"                  TEXT,
    "Description"              TEXT,
    "UnitOfMeasure"            TEXT,
    "PurchaseUnit"             TEXT,
    "SalesUnit"                TEXT,
    "CostPrice"                NUMERIC,
    "SellingPrice"             NUMERIC,
    "WholesalePrice"           NUMERIC,
    "RetailPrice"              NUMERIC,
    "OpeningStock"             NUMERIC,
    "CurrentStock"             NUMERIC,
    "MinimumStockAlert"        NUMERIC,
    "TrackInventory"           BOOLEAN,
    "SupplierId"               INT,
    "ItemType"                 TEXT,
    "CanSell"                  BOOLEAN,
    "CanUseInProduction"       BOOLEAN,
    "CanUseInternally"         BOOLEAN,
    "IsActive"                 BOOLEAN,
    "IsDeleted"                BOOLEAN,
    "Notes"                    TEXT,
    "ExpiryDate"               DATE,
    "TrackExpiry"              BOOLEAN,
    "CreatedBy"                TEXT,
    "CreatedAt"                TIMESTAMP,
    "UpdatedAt"                TIMESTAMP,
    "UpdatedBy"                TEXT
) LANGUAGE sql STABLE AS $$
    SELECT
        p.genericproductid,
        p.farmid,
        p.genericproductcategoryid,
        c.name,
        p.productname,
        p.sku,
        p.barcode,
        p.description,
        p.unitofmeasure,
        p.purchaseunit,
        p.salesunit,
        p.costprice,
        p.sellingprice,
        p.wholesaleprice,
        p.retailprice,
        p.openingstock,
        p.currentstock,
        p.minimumstockalert,
        p.trackinventory,
        p.supplierid,
        COALESCE(p."ItemType", 'Product'),
        p.cansell,
        p.canuseinproduction,
        p.canuseinternally,
        p.isactive,
        p.isdeleted,
        p.notes,
        p.expirydate,
        p.trackexpiry,
        p.createdby,
        p.createdat,
        p.updatedat,
        p.updatedby
    FROM genericproducts p
    LEFT JOIN genericproductcategories c
      ON c.genericproductcategoryid = p.genericproductcategoryid
    WHERE p.genericproductid = p_genericproductid AND p.farmid = p_farmid;
$$;

-- Insert: creates item + opening stock movement. Returns new ID.
CREATE OR REPLACE FUNCTION spgenericproduct_insert(
    p_farmid                   TEXT,
    p_genericproductcategoryid INT     DEFAULT NULL,
    p_productname              TEXT    DEFAULT '',
    p_sku                      TEXT    DEFAULT NULL,
    p_barcode                  TEXT    DEFAULT NULL,
    p_description              TEXT    DEFAULT NULL,
    p_unitofmeasure            TEXT    DEFAULT NULL,
    p_purchaseunit             TEXT    DEFAULT NULL,
    p_salesunit                TEXT    DEFAULT NULL,
    p_costprice                NUMERIC DEFAULT 0,
    p_sellingprice             NUMERIC DEFAULT 0,
    p_wholesaleprice           NUMERIC DEFAULT NULL,
    p_retailprice              NUMERIC DEFAULT NULL,
    p_openingstock             NUMERIC DEFAULT 0,
    p_minimumstockalert        NUMERIC DEFAULT 0,
    p_trackinventory           BOOLEAN DEFAULT TRUE,
    p_supplierid               INT     DEFAULT NULL,
    p_itemtype                 TEXT    DEFAULT 'Product',
    p_cansell                  BOOLEAN DEFAULT TRUE,
    p_canuseinproduction       BOOLEAN DEFAULT FALSE,
    p_canuseinternally         BOOLEAN DEFAULT FALSE,
    p_isactive                 BOOLEAN DEFAULT TRUE,
    p_notes                    TEXT    DEFAULT NULL,
    p_expirydate               DATE    DEFAULT NULL,
    p_trackexpiry              BOOLEAN DEFAULT FALSE,
    p_createdby                TEXT    DEFAULT NULL
)
RETURNS INT LANGUAGE plpgsql AS $fn$
DECLARE
    v_id INT;
    v_initial_stock NUMERIC;
BEGIN
    v_initial_stock := CASE WHEN p_trackinventory THEN p_openingstock ELSE 0 END;

    INSERT INTO genericproducts (
        farmid, genericproductcategoryid, productname, sku, barcode,
        description, unitofmeasure, purchaseunit, salesunit,
        costprice, sellingprice, wholesaleprice, retailprice,
        openingstock, currentstock, minimumstockalert, trackinventory,
        supplierid, "ItemType", cansell, canuseinproduction, canuseinternally,
        isactive, notes, expirydate, trackexpiry, createdby, createdat
    ) VALUES (
        p_farmid, p_genericproductcategoryid, p_productname, p_sku, p_barcode,
        p_description, p_unitofmeasure, p_purchaseunit, p_salesunit,
        p_costprice, p_sellingprice, p_wholesaleprice, p_retailprice,
        p_openingstock, v_initial_stock, p_minimumstockalert, p_trackinventory,
        p_supplierid, COALESCE(p_itemtype, 'Product'), p_cansell, p_canuseinproduction, p_canuseinternally,
        p_isactive, p_notes, p_expirydate, p_trackexpiry, p_createdby, NOW()
    )
    RETURNING genericproductid INTO v_id;

    -- Seed opening stock movement (skip for non-tracked or zero opening)
    IF p_trackinventory AND p_openingstock <> 0 THEN
        INSERT INTO genericstockmovements (
            farmid, genericproductid, movementdate, movementtype, quantity,
            unitcost, totalcostvalue, referencetype, reason, createdby, createdat
        ) VALUES (
            p_farmid, v_id, NOW(), 'OpeningStock', p_openingstock,
            p_costprice, p_costprice * p_openingstock, 'Opening', 'Opening stock seed',
            p_createdby, NOW()
        );
    END IF;

    RETURN v_id;
END;
$fn$;

-- Update: modifies item definition (never touches CurrentStock or OpeningStock)
CREATE OR REPLACE FUNCTION spgenericproduct_update(
    p_genericproductid         INT,
    p_farmid                   TEXT,
    p_genericproductcategoryid INT     DEFAULT NULL,
    p_productname              TEXT    DEFAULT '',
    p_sku                      TEXT    DEFAULT NULL,
    p_barcode                  TEXT    DEFAULT NULL,
    p_description              TEXT    DEFAULT NULL,
    p_unitofmeasure            TEXT    DEFAULT NULL,
    p_purchaseunit             TEXT    DEFAULT NULL,
    p_salesunit                TEXT    DEFAULT NULL,
    p_costprice                NUMERIC DEFAULT 0,
    p_sellingprice             NUMERIC DEFAULT 0,
    p_wholesaleprice           NUMERIC DEFAULT NULL,
    p_retailprice              NUMERIC DEFAULT NULL,
    p_minimumstockalert        NUMERIC DEFAULT 0,
    p_trackinventory           BOOLEAN DEFAULT TRUE,
    p_supplierid               INT     DEFAULT NULL,
    p_itemtype                 TEXT    DEFAULT NULL,
    p_cansell                  BOOLEAN DEFAULT TRUE,
    p_canuseinproduction       BOOLEAN DEFAULT FALSE,
    p_canuseinternally         BOOLEAN DEFAULT FALSE,
    p_isactive                 BOOLEAN DEFAULT TRUE,
    p_notes                    TEXT    DEFAULT NULL,
    p_expirydate               DATE    DEFAULT NULL,
    p_trackexpiry              BOOLEAN DEFAULT FALSE,
    p_updatedby                TEXT    DEFAULT NULL
)
RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    UPDATE genericproducts
    SET genericproductcategoryid = p_genericproductcategoryid,
        productname              = p_productname,
        sku                      = p_sku,
        barcode                  = p_barcode,
        description              = p_description,
        unitofmeasure            = p_unitofmeasure,
        purchaseunit             = p_purchaseunit,
        salesunit                = p_salesunit,
        costprice                = p_costprice,
        sellingprice             = p_sellingprice,
        wholesaleprice           = p_wholesaleprice,
        retailprice              = p_retailprice,
        minimumstockalert        = p_minimumstockalert,
        trackinventory           = p_trackinventory,
        supplierid               = p_supplierid,
        "ItemType"               = COALESCE(p_itemtype, "ItemType"),
        cansell                  = p_cansell,
        canuseinproduction       = p_canuseinproduction,
        canuseinternally         = p_canuseinternally,
        isactive                 = p_isactive,
        notes                    = p_notes,
        expirydate               = p_expirydate,
        trackexpiry              = p_trackexpiry,
        updatedby                = p_updatedby,
        updatedat                = NOW()
    WHERE genericproductid = p_genericproductid AND farmid = p_farmid;
END;
$fn$;

-- Delete (soft): unchanged logic, just redefined for completeness
CREATE OR REPLACE FUNCTION spgenericproduct_delete(
    p_genericproductid INT,
    p_farmid TEXT
)
RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    UPDATE genericproducts
    SET isdeleted = TRUE, isactive = FALSE, updatedat = NOW()
    WHERE genericproductid = p_genericproductid AND farmid = p_farmid;
END;
$fn$;

-- GetLowStock: products below minimum alert threshold
CREATE OR REPLACE FUNCTION spgenericproduct_getlowstock(p_farmid TEXT)
RETURNS TABLE(
    "GenericProductId"  INT,
    "FarmId"            TEXT,
    "ProductName"       TEXT,
    "SKU"               TEXT,
    "UnitOfMeasure"     TEXT,
    "CurrentStock"      NUMERIC,
    "MinimumStockAlert" NUMERIC,
    "Shortfall"         NUMERIC
) LANGUAGE sql STABLE AS $$
    SELECT
        p.genericproductid,
        p.farmid,
        p.productname,
        p.sku,
        p.unitofmeasure,
        p.currentstock,
        p.minimumstockalert,
        (p.minimumstockalert - p.currentstock)
    FROM genericproducts p
    WHERE p.farmid = p_farmid
      AND p.isactive = TRUE
      AND p.isdeleted = FALSE
      AND p.trackinventory = TRUE
      AND p.currentstock <= p.minimumstockalert
    ORDER BY (p.minimumstockalert - p.currentstock) DESC, p.productname;
$$;

-- ReconcileStock: rebuilds CurrentStock from SUM(StockMovements)
CREATE OR REPLACE FUNCTION spgenericproduct_reconcilestock(p_farmid TEXT)
RETURNS VOID LANGUAGE plpgsql AS $fn$
BEGIN
    UPDATE genericproducts p
    SET currentstock = COALESCE(m.total_qty, 0),
        updatedat    = NOW()
    FROM (
        SELECT genericproductid, SUM(quantity) AS total_qty
        FROM genericstockmovements
        WHERE farmid = p_farmid
        GROUP BY genericproductid
    ) m
    WHERE p.genericproductid = m.genericproductid
      AND p.farmid = p_farmid
      AND p.trackinventory = TRUE;

    -- Zero out items with no movements
    UPDATE genericproducts p
    SET currentstock = 0, updatedat = NOW()
    WHERE p.farmid = p_farmid
      AND p.trackinventory = TRUE
      AND NOT EXISTS (
          SELECT 1 FROM genericstockmovements m
          WHERE m.genericproductid = p.genericproductid AND m.farmid = p_farmid
      )
      AND p.currentstock <> 0;
END;
$fn$;
