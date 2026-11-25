-- =============================================================================
-- Migration 492: Generic Units of Measure table + Product image column
-- Branch: emma
-- =============================================================================
-- 1) Creates GenericUnitsOfMeasure table with seed data for common units.
--    Units are per-farm so each company can add their own.
--    When a product is saved with a new unit, the frontend will auto-add it.
-- 2) Adds imageurl column to genericproducts for product photos (base64 or URL).
-- =============================================================================
-- NOTE: genericproducts uses all-lowercase columns (farmid, productname, etc.)
--       except "ItemType" which is quoted mixed-case.
-- =============================================================================

-- ---- 1. GenericUnitsOfMeasure table ----

CREATE TABLE IF NOT EXISTS "GenericUnitsOfMeasure" (
    "GenericUnitOfMeasureId" SERIAL PRIMARY KEY,
    "FarmId"                 TEXT NOT NULL,
    "UnitName"               VARCHAR(60) NOT NULL,
    "UnitAbbreviation"       VARCHAR(20),
    "IsActive"               BOOLEAN NOT NULL DEFAULT TRUE,
    "CreatedAt"              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_generic_uom_farm_name UNIQUE ("FarmId", "UnitName")
);

CREATE INDEX IF NOT EXISTS ix_generic_uom_farmid ON "GenericUnitsOfMeasure" ("FarmId");

-- ---- SP: List all units for a farm ----

CREATE OR REPLACE FUNCTION spgenericuom_getall(p_farmid TEXT)
RETURNS TABLE (
    genericunitofmeasureid INT,
    farmid TEXT,
    unitname VARCHAR(60),
    unitabbreviation VARCHAR(20),
    isactive BOOLEAN,
    createdat TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT u."GenericUnitOfMeasureId", u."FarmId", u."UnitName", u."UnitAbbreviation",
           u."IsActive", u."CreatedAt"
    FROM "GenericUnitsOfMeasure" u
    WHERE u."FarmId" = p_farmid AND u."IsActive" = TRUE
    ORDER BY u."UnitName";
END;
$$ LANGUAGE plpgsql;

-- ---- SP: Upsert a unit (insert if not exists, return id) ----

CREATE OR REPLACE FUNCTION spgenericuom_upsert(
    p_farmid TEXT,
    p_unitname TEXT,
    p_unitabbreviation TEXT DEFAULT NULL
)
RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    -- Try to find existing
    SELECT u."GenericUnitOfMeasureId" INTO v_id
    FROM "GenericUnitsOfMeasure" u
    WHERE u."FarmId" = p_farmid AND LOWER(TRIM(u."UnitName")) = LOWER(TRIM(p_unitname));

    IF v_id IS NOT NULL THEN
        -- Reactivate if it was deactivated
        UPDATE "GenericUnitsOfMeasure" SET "IsActive" = TRUE
        WHERE "GenericUnitOfMeasureId" = v_id AND "IsActive" = FALSE;
        RETURN v_id;
    END IF;

    -- Insert new
    INSERT INTO "GenericUnitsOfMeasure" ("FarmId", "UnitName", "UnitAbbreviation")
    VALUES (p_farmid, TRIM(p_unitname), NULLIF(TRIM(COALESCE(p_unitabbreviation, '')), ''))
    RETURNING "GenericUnitOfMeasureId" INTO v_id;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- SP: Delete (soft) a unit ----

CREATE OR REPLACE FUNCTION spgenericuom_delete(p_id INT, p_farmid TEXT)
RETURNS VOID AS $$
BEGIN
    UPDATE "GenericUnitsOfMeasure"
    SET "IsActive" = FALSE
    WHERE "GenericUnitOfMeasureId" = p_id AND "FarmId" = p_farmid;
END;
$$ LANGUAGE plpgsql;

-- ---- Seed common units for existing farms that have Generic products ----

DO $$
DECLARE
    v_farmid TEXT;
    v_units TEXT[] := ARRAY[
        'kg', 'g', 'lb', 'oz',
        'litre', 'ml', 'gallon',
        'piece', 'dozen', 'pair',
        'bag', 'box', 'carton', 'pack', 'bundle', 'crate',
        'bottle', 'tin', 'jar', 'sachet',
        'metre', 'cm', 'inch', 'foot', 'yard',
        'roll', 'sheet', 'set', 'unit'
    ];
    v_unit TEXT;
BEGIN
    FOR v_farmid IN
        SELECT DISTINCT p.farmid FROM genericproducts p WHERE p.isdeleted = FALSE
    LOOP
        FOREACH v_unit IN ARRAY v_units LOOP
            INSERT INTO "GenericUnitsOfMeasure" ("FarmId", "UnitName")
            VALUES (v_farmid, v_unit)
            ON CONFLICT ("FarmId", "UnitName") DO NOTHING;
        END LOOP;
    END LOOP;
END;
$$;

-- Also add any custom units already used on existing products
INSERT INTO "GenericUnitsOfMeasure" ("FarmId", "UnitName")
SELECT DISTINCT p.farmid, TRIM(p.unitofmeasure)
FROM genericproducts p
WHERE p.isdeleted = FALSE
  AND p.unitofmeasure IS NOT NULL
  AND TRIM(p.unitofmeasure) <> ''
ON CONFLICT ("FarmId", "UnitName") DO NOTHING;

-- ---- 2. Product image column ----

ALTER TABLE genericproducts ADD COLUMN IF NOT EXISTS imageurl TEXT;

-- ---- Update the insert SP to accept imageurl ----
-- (The 27-arg overload; older overloads are kept for backwards compat)

CREATE OR REPLACE FUNCTION spgenericproduct_insert(
    p_farmid TEXT,
    p_genericproductcategoryid INT DEFAULT NULL,
    p_productname TEXT DEFAULT '',
    p_sku TEXT DEFAULT NULL,
    p_barcode TEXT DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_unitofmeasure TEXT DEFAULT NULL,
    p_purchaseunit TEXT DEFAULT NULL,
    p_salesunit TEXT DEFAULT NULL,
    p_costprice NUMERIC DEFAULT 0,
    p_sellingprice NUMERIC DEFAULT 0,
    p_wholesaleprice NUMERIC DEFAULT NULL,
    p_retailprice NUMERIC DEFAULT NULL,
    p_openingstock NUMERIC DEFAULT 0,
    p_minimumstockalert NUMERIC DEFAULT 0,
    p_trackinventory BOOLEAN DEFAULT TRUE,
    p_supplierid INT DEFAULT NULL,
    p_itemtype TEXT DEFAULT 'Product',
    p_cansell BOOLEAN DEFAULT TRUE,
    p_canuseinproduction BOOLEAN DEFAULT FALSE,
    p_canuseinternally BOOLEAN DEFAULT FALSE,
    p_isactive BOOLEAN DEFAULT TRUE,
    p_notes TEXT DEFAULT NULL,
    p_expirydate DATE DEFAULT NULL,
    p_trackexpiry BOOLEAN DEFAULT FALSE,
    p_createdby TEXT DEFAULT NULL,
    p_imageurl TEXT DEFAULT NULL
)
RETURNS INT AS $$
DECLARE v_id INT;
BEGIN
    INSERT INTO genericproducts (
        farmid, genericproductcategoryid, productname, sku, barcode,
        description, unitofmeasure, purchaseunit, salesunit,
        costprice, sellingprice, wholesaleprice, retailprice,
        openingstock, currentstock, minimumstockalert,
        trackinventory, supplierid, "ItemType",
        cansell, canuseinproduction, canuseinternally,
        isactive, notes, expirydate, trackexpiry,
        createdby, imageurl, createdat
    ) VALUES (
        p_farmid, p_genericproductcategoryid, p_productname, p_sku, p_barcode,
        p_description, p_unitofmeasure, p_purchaseunit, p_salesunit,
        p_costprice, p_sellingprice, p_wholesaleprice, p_retailprice,
        p_openingstock,
        CASE WHEN p_trackinventory = TRUE THEN p_openingstock ELSE 0 END,
        p_minimumstockalert,
        p_trackinventory, p_supplierid, COALESCE(p_itemtype, 'Product'),
        COALESCE(p_cansell, TRUE), COALESCE(p_canuseinproduction, FALSE), COALESCE(p_canuseinternally, FALSE),
        COALESCE(p_isactive, TRUE), p_notes, p_expirydate, COALESCE(p_trackexpiry, FALSE),
        p_createdby, p_imageurl, NOW()
    )
    RETURNING genericproductid INTO v_id;

    -- Opening stock movement
    IF (p_trackinventory = TRUE AND p_openingstock <> 0) THEN
        INSERT INTO genericstockmovements (
            farmid, genericproductid, movementdate, movementtype, quantity,
            unitcost, totalcostvalue, referencetype, reason, createdby
        ) VALUES (
            p_farmid, v_id, (now() at time zone 'utc'), 'OpeningStock', p_openingstock,
            p_costprice, p_costprice * p_openingstock, 'Opening', 'Opening stock seed', p_createdby
        );
    END IF;

    -- Auto-add unit to the units table if it doesn't exist
    IF p_unitofmeasure IS NOT NULL AND TRIM(p_unitofmeasure) <> '' THEN
        PERFORM spgenericuom_upsert(p_farmid, p_unitofmeasure);
    END IF;

    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- ---- Update the update SP to accept imageurl ----

CREATE OR REPLACE FUNCTION spgenericproduct_update(
    p_genericproductid INT,
    p_farmid TEXT,
    p_genericproductcategoryid INT DEFAULT NULL,
    p_productname TEXT DEFAULT '',
    p_sku TEXT DEFAULT NULL,
    p_barcode TEXT DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_unitofmeasure TEXT DEFAULT NULL,
    p_purchaseunit TEXT DEFAULT NULL,
    p_salesunit TEXT DEFAULT NULL,
    p_costprice NUMERIC DEFAULT 0,
    p_sellingprice NUMERIC DEFAULT 0,
    p_wholesaleprice NUMERIC DEFAULT NULL,
    p_retailprice NUMERIC DEFAULT NULL,
    p_minimumstockalert NUMERIC DEFAULT 0,
    p_trackinventory BOOLEAN DEFAULT TRUE,
    p_supplierid INT DEFAULT NULL,
    p_itemtype TEXT DEFAULT 'Product',
    p_cansell BOOLEAN DEFAULT TRUE,
    p_canuseinproduction BOOLEAN DEFAULT FALSE,
    p_canuseinternally BOOLEAN DEFAULT FALSE,
    p_isactive BOOLEAN DEFAULT TRUE,
    p_notes TEXT DEFAULT NULL,
    p_expirydate DATE DEFAULT NULL,
    p_trackexpiry BOOLEAN DEFAULT FALSE,
    p_updatedby TEXT DEFAULT NULL,
    p_imageurl TEXT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    UPDATE genericproducts SET
        genericproductcategoryid = p_genericproductcategoryid,
        productname = p_productname,
        sku = p_sku,
        barcode = p_barcode,
        description = p_description,
        unitofmeasure = p_unitofmeasure,
        purchaseunit = p_purchaseunit,
        salesunit = p_salesunit,
        costprice = p_costprice,
        sellingprice = p_sellingprice,
        wholesaleprice = p_wholesaleprice,
        retailprice = p_retailprice,
        minimumstockalert = p_minimumstockalert,
        trackinventory = p_trackinventory,
        supplierid = p_supplierid,
        "ItemType" = COALESCE(p_itemtype, 'Product'),
        cansell = COALESCE(p_cansell, TRUE),
        canuseinproduction = COALESCE(p_canuseinproduction, FALSE),
        canuseinternally = COALESCE(p_canuseinternally, FALSE),
        isactive = COALESCE(p_isactive, TRUE),
        notes = p_notes,
        expirydate = p_expirydate,
        trackexpiry = COALESCE(p_trackexpiry, FALSE),
        updatedby = p_updatedby,
        imageurl = p_imageurl,
        updatedat = NOW()
    WHERE genericproductid = p_genericproductid AND farmid = p_farmid AND isdeleted = FALSE;

    -- Auto-add unit to the units table if it doesn't exist
    IF p_unitofmeasure IS NOT NULL AND TRIM(p_unitofmeasure) <> '' THEN
        PERFORM spgenericuom_upsert(p_farmid, p_unitofmeasure);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ---- Update getall to return imageurl ----
-- NOTE: Must cast varchar columns to text to match RETURNS TABLE definition.
-- Drop the old overload first (both varchar and text signatures).

DROP FUNCTION IF EXISTS spgenericproduct_getall(character varying);
DROP FUNCTION IF EXISTS spgenericproduct_getall(text);

CREATE FUNCTION spgenericproduct_getall(p_farmid TEXT)
RETURNS TABLE (
    "GenericProductId" INT,
    "FarmId" TEXT,
    "GenericProductCategoryId" INT,
    "CategoryName" TEXT,
    "ProductName" TEXT,
    "SKU" TEXT,
    "Barcode" TEXT,
    "Description" TEXT,
    "UnitOfMeasure" TEXT,
    "PurchaseUnit" TEXT,
    "SalesUnit" TEXT,
    "CostPrice" NUMERIC,
    "SellingPrice" NUMERIC,
    "WholesalePrice" NUMERIC,
    "RetailPrice" NUMERIC,
    "OpeningStock" NUMERIC,
    "CurrentStock" NUMERIC,
    "MinimumStockAlert" NUMERIC,
    "TrackInventory" BOOLEAN,
    "SupplierId" INT,
    "ItemType" TEXT,
    "CanSell" BOOLEAN,
    "CanUseInProduction" BOOLEAN,
    "CanUseInternally" BOOLEAN,
    "IsActive" BOOLEAN,
    "IsDeleted" BOOLEAN,
    "Notes" TEXT,
    "ExpiryDate" DATE,
    "TrackExpiry" BOOLEAN,
    "CreatedBy" TEXT,
    "CreatedAt" TIMESTAMP,
    "UpdatedAt" TIMESTAMP,
    "UpdatedBy" TEXT,
    "ImageUrl" TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.genericproductid,
        p.farmid::text,
        p.genericproductcategoryid,
        c.name::text,
        p.productname::text,
        p.sku::text,
        p.barcode::text,
        p.description,
        p.unitofmeasure::text,
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
        p.notes::text,
        p.expirydate,
        p.trackexpiry,
        p.createdby,
        p.createdat,
        p.updatedat,
        p.updatedby,
        p.imageurl
    FROM genericproducts p
    LEFT JOIN genericproductcategories c
      ON c.genericproductcategoryid = p.genericproductcategoryid
    WHERE p.farmid = p_farmid AND p.isdeleted = FALSE
    ORDER BY p.isactive DESC, p.productname;
END;
$$ LANGUAGE plpgsql;

-- ---- Update getbyid to return imageurl ----

DROP FUNCTION IF EXISTS spgenericproduct_getbyid(INT, TEXT);
DROP FUNCTION IF EXISTS spgenericproduct_getbyid(INT, character varying);

CREATE FUNCTION spgenericproduct_getbyid(p_genericproductid INT, p_farmid TEXT)
RETURNS TABLE (
    "GenericProductId" INT,
    "FarmId" TEXT,
    "GenericProductCategoryId" INT,
    "CategoryName" TEXT,
    "ProductName" TEXT,
    "SKU" TEXT,
    "Barcode" TEXT,
    "Description" TEXT,
    "UnitOfMeasure" TEXT,
    "PurchaseUnit" TEXT,
    "SalesUnit" TEXT,
    "CostPrice" NUMERIC,
    "SellingPrice" NUMERIC,
    "WholesalePrice" NUMERIC,
    "RetailPrice" NUMERIC,
    "OpeningStock" NUMERIC,
    "CurrentStock" NUMERIC,
    "MinimumStockAlert" NUMERIC,
    "TrackInventory" BOOLEAN,
    "SupplierId" INT,
    "ItemType" TEXT,
    "CanSell" BOOLEAN,
    "CanUseInProduction" BOOLEAN,
    "CanUseInternally" BOOLEAN,
    "IsActive" BOOLEAN,
    "IsDeleted" BOOLEAN,
    "Notes" TEXT,
    "ExpiryDate" DATE,
    "TrackExpiry" BOOLEAN,
    "CreatedBy" TEXT,
    "CreatedAt" TIMESTAMP,
    "UpdatedAt" TIMESTAMP,
    "UpdatedBy" TEXT,
    "ImageUrl" TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.genericproductid,
        p.farmid::text,
        p.genericproductcategoryid,
        c.name::text,
        p.productname::text,
        p.sku::text,
        p.barcode::text,
        p.description,
        p.unitofmeasure::text,
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
        p.notes::text,
        p.expirydate,
        p.trackexpiry,
        p.createdby,
        p.createdat,
        p.updatedat,
        p.updatedby,
        p.imageurl
    FROM genericproducts p
    LEFT JOIN genericproductcategories c
      ON c.genericproductcategoryid = p.genericproductcategoryid
    WHERE p.genericproductid = p_genericproductid AND p.farmid = p_farmid;
END;
$$ LANGUAGE plpgsql;
