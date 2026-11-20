-- 440: Add ItemType column to genericproducts
-- Distinguishes Products (things you sell) from Supply Items (things you use internally).
-- Default is 'Product' so existing products remain sellable.

DO $$ BEGIN

IF NOT EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_name = 'genericproducts' AND column_name = 'ItemType'
) THEN
  ALTER TABLE genericproducts ADD COLUMN "ItemType" TEXT NOT NULL DEFAULT 'Product';
  COMMENT ON COLUMN genericproducts."ItemType" IS 'Product = things you sell, SupplyItem = things you use internally (packaging, fuel, tools, etc.)';
END IF;

END $$;
