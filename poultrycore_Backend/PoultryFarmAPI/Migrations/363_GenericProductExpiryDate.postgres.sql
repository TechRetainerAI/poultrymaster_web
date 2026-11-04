-- Migration 363: Add optional expiry date to Generic products.
--
-- Useful for grocery, pharmacy, bakery and produce sellers that need to track
-- perishable items. Nullable DATE — null means no expiry tracking for that item.
--
-- Idempotent: safe to run multiple times.

DO $$
BEGIN
    -- Add expiryDate column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'genericproducts' AND column_name = 'expirydate'
    ) THEN
        ALTER TABLE genericproducts ADD COLUMN expirydate DATE NULL;
        COMMENT ON COLUMN genericproducts.expirydate IS
            '363. Optional expiry/best-before date. NULL = no expiry. Read by inventory page for expiry warnings.';
    END IF;

    -- Add trackExpiry boolean column (default false so existing products are unaffected)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'genericproducts' AND column_name = 'trackexpiry'
    ) THEN
        ALTER TABLE genericproducts ADD COLUMN trackexpiry BOOLEAN NOT NULL DEFAULT FALSE;
        COMMENT ON COLUMN genericproducts.trackexpiry IS
            '363. Whether this product tracks expiry dates. FALSE for existing products.';
    END IF;
END $$;

-- Update the product get SP to include the new columns
CREATE OR REPLACE FUNCTION spgenericproduct_getall(p_farmid VARCHAR(450))
RETURNS TABLE(
    genericproductid INT,
    genericproductcategoryid INT,
    categoryname TEXT,
    productname TEXT,
    sku TEXT,
    barcode TEXT,
    unitofmeasure TEXT,
    costprice NUMERIC,
    sellingprice NUMERIC,
    wholesaleprice NUMERIC,
    retailprice NUMERIC,
    openingstock NUMERIC,
    currentstock NUMERIC,
    minimumstockalert NUMERIC,
    trackinventory BOOLEAN,
    supplierid INT,
    isactive BOOLEAN,
    notes TEXT,
    expirydate DATE,
    trackexpiry BOOLEAN
)
LANGUAGE sql STABLE AS $$
    SELECT
        p.genericproductid,
        p.genericproductcategoryid,
        c.name AS categoryname,
        p.productname,
        p.sku,
        p.barcode,
        p.unitofmeasure,
        p.costprice,
        p.sellingprice,
        p.wholesaleprice,
        p.retailprice,
        p.openingstock,
        p.currentstock,
        p.minimumstockalert,
        p.trackinventory,
        p.supplierid,
        p.isactive,
        p.notes,
        p.expirydate,
        p.trackexpiry
    FROM genericproducts p
    LEFT JOIN genericproductcategories c ON c.genericproductcategoryid = p.genericproductcategoryid
    WHERE p.farmid = p_farmid AND p.isdeleted = FALSE
    ORDER BY p.productname;
$$;
