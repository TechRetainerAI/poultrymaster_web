-- =============================================================================
-- 092_AddProductPackagingPricingFields.sql
--
-- Feedback #8/#9/#10: redesign the water product "Details" section into
-- "Packaging & Pricing". Adds the genuinely-new columns and threads them through
-- the product CRUD SPs. Existing concepts are REUSED, not duplicated:
--   Inventory Unit          -> Unit            (existing)
--   Size Per Unit (number)  -> SizeMl          (existing)
--   Units Per Package       -> SachetsPerBag   (existing; label is dynamic in UI)
--   Selling Price Per Bag   -> BagPrice        (existing)
--   Selling Price Per Unit  -> SachetPrice     (existing)
-- New columns:
--   SizeUnit         NVARCHAR(20)  -- ml / L / cl / g / kg / Other
--   PackagingUnit    NVARCHAR(30)  -- Bag / Pack / Crate / ...
--   DefaultSalesUnit NVARCHAR(30)  -- the inventory or packaging unit sold by default
--   ProductCategory  NVARCHAR(60)  -- Sachet Water / Bottled Water / ...
--
-- Idempotent: column adds guarded by COL_LENGTH; SPs use CREATE OR ALTER
-- (which preserves existing EXECUTE grants). New params default NULL so older
-- callers keep working.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.WaterProducts','SizeUnit')         IS NULL ALTER TABLE dbo.WaterProducts ADD SizeUnit         NVARCHAR(20)  NULL;
GO
IF COL_LENGTH('dbo.WaterProducts','PackagingUnit')    IS NULL ALTER TABLE dbo.WaterProducts ADD PackagingUnit    NVARCHAR(30)  NULL;
GO
IF COL_LENGTH('dbo.WaterProducts','DefaultSalesUnit') IS NULL ALTER TABLE dbo.WaterProducts ADD DefaultSalesUnit NVARCHAR(30)  NULL;
GO
IF COL_LENGTH('dbo.WaterProducts','ProductCategory')  IS NULL ALTER TABLE dbo.WaterProducts ADD ProductCategory  NVARCHAR(60)  NULL;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProduct_Insert
    @FarmId           NVARCHAR(450),
    @Name             NVARCHAR(150),
    @Sku              NVARCHAR(60)  = NULL,
    @SizeMl           INT           = NULL,
    @Unit             NVARCHAR(30)  = NULL,
    @UnitPrice        DECIMAL(12,2) = 0,
    @IsActive         BIT           = 1,
    @ProductType      NVARCHAR(30)  = 'FinishedGood',
    @Notes            NVARCHAR(500) = NULL,
    @BaseUnit         NVARCHAR(20)  = NULL,
    @SachetsPerBag    INT           = NULL,
    @BagPrice         DECIMAL(12,2) = NULL,
    @SachetPrice      DECIMAL(12,2) = NULL,
    @IsSachetProduct  BIT           = 0,
    @SizeUnit         NVARCHAR(20)  = NULL,
    @PackagingUnit    NVARCHAR(30)  = NULL,
    @DefaultSalesUnit NVARCHAR(30)  = NULL,
    @ProductCategory  NVARCHAR(60)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterProducts
        (FarmId, Name, Sku, SizeMl, Unit, UnitPrice, IsActive, ProductType, Notes,
         BaseUnit, SachetsPerBag, BagPrice, SachetPrice, IsSachetProduct,
         SizeUnit, PackagingUnit, DefaultSalesUnit, ProductCategory)
    VALUES
        (@FarmId, @Name, @Sku, @SizeMl, @Unit, @UnitPrice, @IsActive,
         ISNULL(@ProductType, N'FinishedGood'), @Notes,
         @BaseUnit, @SachetsPerBag, @BagPrice, @SachetPrice, @IsSachetProduct,
         @SizeUnit, @PackagingUnit, @DefaultSalesUnit, @ProductCategory);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProduct_Update
    @WaterProductId   INT,
    @FarmId           NVARCHAR(450),
    @Name             NVARCHAR(150),
    @Sku              NVARCHAR(60)  = NULL,
    @SizeMl           INT           = NULL,
    @Unit             NVARCHAR(30)  = NULL,
    @UnitPrice        DECIMAL(12,2) = 0,
    @IsActive         BIT           = 1,
    @ProductType      NVARCHAR(30)  = 'FinishedGood',
    @Notes            NVARCHAR(500) = NULL,
    @BaseUnit         NVARCHAR(20)  = NULL,
    @SachetsPerBag    INT           = NULL,
    @BagPrice         DECIMAL(12,2) = NULL,
    @SachetPrice      DECIMAL(12,2) = NULL,
    @IsSachetProduct  BIT           = NULL,
    @SizeUnit         NVARCHAR(20)  = NULL,
    @PackagingUnit    NVARCHAR(30)  = NULL,
    @DefaultSalesUnit NVARCHAR(30)  = NULL,
    @ProductCategory  NVARCHAR(60)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterProducts
    SET    Name             = @Name,
           Sku              = @Sku,
           SizeMl           = @SizeMl,
           Unit             = @Unit,
           UnitPrice        = @UnitPrice,
           IsActive         = @IsActive,
           ProductType      = ISNULL(@ProductType, ProductType),
           Notes            = @Notes,
           BaseUnit         = @BaseUnit,
           SachetsPerBag    = @SachetsPerBag,
           BagPrice         = @BagPrice,
           SachetPrice      = @SachetPrice,
           IsSachetProduct  = ISNULL(@IsSachetProduct, IsSachetProduct),
           SizeUnit         = @SizeUnit,
           PackagingUnit    = @PackagingUnit,
           DefaultSalesUnit = @DefaultSalesUnit,
           ProductCategory  = @ProductCategory,
           UpdatedDate      = SYSUTCDATETIME()
    WHERE  WaterProductId = @WaterProductId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProduct_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.WaterProductId, p.FarmId, p.Name, p.Sku, p.SizeMl, p.Unit,
           p.UnitPrice, p.IsActive, p.Notes, p.CreatedDate, p.UpdatedDate,
           ISNULL(p.ProductType, N'FinishedGood') AS ProductType,
           p.BaseUnit, p.SachetsPerBag, p.BagPrice, p.SachetPrice, p.IsSachetProduct,
           p.SizeUnit, p.PackagingUnit, p.DefaultSalesUnit, p.ProductCategory,
           ISNULL(s.OnHand, 0) AS StockOnHand
    FROM   dbo.WaterProducts p
    OUTER APPLY (
        SELECT SUM(CAST(st.Quantity AS DECIMAL(18,4))) AS OnHand
        FROM   dbo.WaterStockTransactions st
        WHERE  st.WaterProductId = p.WaterProductId
    ) s
    WHERE  p.FarmId = @FarmId
    ORDER BY p.Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProduct_GetById
    @WaterProductId INT,
    @FarmId         NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.WaterProductId, p.FarmId, p.Name, p.Sku, p.SizeMl, p.Unit,
           p.UnitPrice, p.IsActive, p.Notes, p.CreatedDate, p.UpdatedDate,
           ISNULL(p.ProductType, N'FinishedGood') AS ProductType,
           p.BaseUnit, p.SachetsPerBag, p.BagPrice, p.SachetPrice, p.IsSachetProduct,
           p.SizeUnit, p.PackagingUnit, p.DefaultSalesUnit, p.ProductCategory,
           ISNULL(s.OnHand, 0) AS StockOnHand
    FROM   dbo.WaterProducts p
    OUTER APPLY (
        SELECT SUM(CAST(st.Quantity AS DECIMAL(18,4))) AS OnHand
        FROM   dbo.WaterStockTransactions st
        WHERE  st.WaterProductId = p.WaterProductId
    ) s
    WHERE  p.WaterProductId = @WaterProductId AND p.FarmId = @FarmId;
END
GO
