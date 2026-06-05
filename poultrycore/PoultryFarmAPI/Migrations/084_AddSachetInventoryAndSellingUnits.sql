-- =============================================================================
-- Migration 084: Sachet-based inventory + Selling Unit on sale items
-- =============================================================================
-- "Payroll Details Page, Delivery Return Approval, Delivery Sales Posting
--  Modes, Sales Unit Enhancements, and Sachet-Based Inventory Improvements"
--  §7 – §17.
--
-- Goal
--   * Allow a Water product to define an internal base unit (default = the
--     product's own Unit) and a SachetsPerBag conversion. For sachet-water
--     products, BaseUnit='Sachet' so 1 bag = SachetsPerBag sachets of stock.
--   * Allow sales to be recorded in EITHER bag OR sachet using the new
--     SellingUnit column on WaterSaleItems. Stock is deducted in BaseQuantity
--     (sachets) so reports/inventory always reconcile cleanly.
--   * Add per-unit prices on WaterProducts so the Sales modal can auto-fill
--     the right price based on selected Selling Unit.
--
-- Schema additions on dbo.WaterProducts
--   BaseUnit         NVARCHAR(20)   NULL    -- 'Sachet' for sachet water; falls back to Unit
--   SachetsPerBag    INT            NULL    -- conversion ratio (default from company profile)
--   BagPrice         DECIMAL(12,2)  NULL    -- selling price per bag
--   SachetPrice      DECIMAL(12,2)  NULL    -- selling price per sachet
--   IsSachetProduct  BIT            NOT NULL DEFAULT 0
--                                            -- when 1: inventory page shows both Bags + Sachets
--                                            -- and sales deduct in sachets via BaseQuantity
--
-- Schema additions on dbo.WaterSaleItems
--   SellingUnit   NVARCHAR(20)   NULL    -- 'Bag' | 'Sachet' (NULL = pre-migration legacy)
--   BaseUnit      NVARCHAR(20)   NULL    -- snapshot of product's base unit at sale time
--   BaseQuantity  DECIMAL(18,4)  NULL    -- snapshot of equivalent stock units (sachets)
--
-- Schema additions on dbo.WaterStockTransactions
--   BaseQuantity  DECIMAL(18,4)  NULL    -- signed equivalent in BaseUnit (sachets for sachet products)
--
-- New SP
--   spWaterSale_CreateV2 — accepts SellingUnit per line, computes BaseQuantity
--                          using the product's SachetsPerBag, writes the stock
--                          txn in BaseQuantity, and validates sachet stock.
--   spWaterInventory_GetStockSummary — single SELECT used by the inventory
--                          page that returns StockBags + StockSachets for
--                          every finished product based on BaseQuantity.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. WaterProducts additions
-- -----------------------------------------------------------------------------
IF COL_LENGTH(N'dbo.WaterProducts', N'BaseUnit') IS NULL
    ALTER TABLE dbo.WaterProducts ADD BaseUnit NVARCHAR(20) NULL;
GO
IF COL_LENGTH(N'dbo.WaterProducts', N'SachetsPerBag') IS NULL
    ALTER TABLE dbo.WaterProducts ADD SachetsPerBag INT NULL;
GO
IF COL_LENGTH(N'dbo.WaterProducts', N'BagPrice') IS NULL
    ALTER TABLE dbo.WaterProducts ADD BagPrice DECIMAL(12,2) NULL;
GO
IF COL_LENGTH(N'dbo.WaterProducts', N'SachetPrice') IS NULL
    ALTER TABLE dbo.WaterProducts ADD SachetPrice DECIMAL(12,2) NULL;
GO
IF COL_LENGTH(N'dbo.WaterProducts', N'IsSachetProduct') IS NULL
    ALTER TABLE dbo.WaterProducts ADD IsSachetProduct BIT NOT NULL CONSTRAINT DF_WaterProducts_IsSachet DEFAULT (0);
GO

-- Backfill: any product whose Unit ∈ ('sachet','sachets','bag','bags') and
-- doesn't yet have IsSachetProduct/SachetsPerBag → mark as sachet product
-- using the company-profile default count.
UPDATE p
SET    p.IsSachetProduct = 1,
       p.BaseUnit        = N'Sachet',
       p.SachetsPerBag   = ISNULL(p.SachetsPerBag, ISNULL(cp.DefaultBagSachetCount, 30)),
       p.BagPrice        = ISNULL(p.BagPrice,    p.UnitPrice),
       p.SachetPrice     = ISNULL(p.SachetPrice, CASE WHEN ISNULL(p.SachetsPerBag, ISNULL(cp.DefaultBagSachetCount, 30)) > 0
                                                      THEN p.UnitPrice / ISNULL(p.SachetsPerBag, ISNULL(cp.DefaultBagSachetCount, 30))
                                                      ELSE NULL END)
FROM   dbo.WaterProducts p
LEFT JOIN dbo.WaterCompanyProfiles cp ON cp.FarmId = p.FarmId
WHERE  p.IsSachetProduct = 0
  AND  LOWER(ISNULL(p.Unit, N'')) IN (N'sachet', N'sachets', N'bag', N'bags');
GO

-- -----------------------------------------------------------------------------
-- 2. WaterSaleItems additions
-- -----------------------------------------------------------------------------
IF COL_LENGTH(N'dbo.WaterSaleItems', N'SellingUnit') IS NULL
    ALTER TABLE dbo.WaterSaleItems ADD SellingUnit NVARCHAR(20) NULL;
GO
IF COL_LENGTH(N'dbo.WaterSaleItems', N'BaseUnit') IS NULL
    ALTER TABLE dbo.WaterSaleItems ADD BaseUnit NVARCHAR(20) NULL;
GO
IF COL_LENGTH(N'dbo.WaterSaleItems', N'BaseQuantity') IS NULL
    ALTER TABLE dbo.WaterSaleItems ADD BaseQuantity DECIMAL(18,4) NULL;
GO

-- -----------------------------------------------------------------------------
-- 3. WaterStockTransactions additions
-- -----------------------------------------------------------------------------
IF COL_LENGTH(N'dbo.WaterStockTransactions', N'BaseQuantity') IS NULL
    ALTER TABLE dbo.WaterStockTransactions ADD BaseQuantity DECIMAL(18,4) NULL;
GO
-- Backfill BaseQuantity for existing rows using product conversions.
UPDATE st
SET    BaseQuantity =
       CASE
           WHEN p.IsSachetProduct = 1 AND ISNULL(p.SachetsPerBag, 0) > 0
               THEN CAST(st.Quantity AS DECIMAL(18,4)) * p.SachetsPerBag
           ELSE CAST(st.Quantity AS DECIMAL(18,4))
       END
FROM   dbo.WaterStockTransactions st
INNER JOIN dbo.WaterProducts p ON p.WaterProductId = st.WaterProductId
WHERE  st.BaseQuantity IS NULL;
GO

-- -----------------------------------------------------------------------------
-- 4. spWaterSale_CreateV2 — selling-unit-aware sale + sachet stock validation
-- -----------------------------------------------------------------------------
-- Backwards-compat: the existing spWaterSale_Create still works; the new SP
-- is invoked when the C# layer sends a payload that includes per-line
-- SellingUnit. The frontend will always send SellingUnit going forward.
CREATE OR ALTER PROCEDURE dbo.spWaterSale_CreateV2
    @FarmId           NVARCHAR(450),
    @WaterCustomerId  INT = NULL,
    @SaleDate         DATETIME2 = NULL,
    @Notes            NVARCHAR(500) = NULL,
    @CreatedBy        NVARCHAR(450) = NULL,
    -- [{"WaterProductId":1,"Quantity":10,"UnitPrice":2.50,"SellingUnit":"Bag"}, ...]
    @ItemsJson        NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @SaleDate IS NULL SET @SaleDate = SYSUTCDATETIME();

    -- Parse and enrich items.
    DECLARE @Items TABLE (
        WaterProductId INT,
        Quantity       INT,
        UnitPrice      DECIMAL(12,2),
        SellingUnit    NVARCHAR(20),
        BaseUnit       NVARCHAR(20),
        BaseQuantity   DECIMAL(18,4)
    );

    ;WITH src AS (
        SELECT j.WaterProductId, j.Quantity, j.UnitPrice, j.SellingUnit
        FROM OPENJSON(@ItemsJson)
        WITH (
            WaterProductId INT             '$.WaterProductId',
            Quantity       INT             '$.Quantity',
            UnitPrice      DECIMAL(12,2)   '$.UnitPrice',
            SellingUnit    NVARCHAR(20)    '$.SellingUnit'
        ) j
    )
    INSERT INTO @Items (WaterProductId, Quantity, UnitPrice, SellingUnit, BaseUnit, BaseQuantity)
    SELECT src.WaterProductId, src.Quantity, src.UnitPrice,
           ISNULL(src.SellingUnit, ISNULL(p.Unit, N'Unit')) AS SellingUnit,
           ISNULL(p.BaseUnit, ISNULL(p.Unit, N'Unit'))     AS BaseUnit,
           CASE
               WHEN p.IsSachetProduct = 1 AND LOWER(ISNULL(src.SellingUnit, p.Unit)) = N'bag'
                   THEN CAST(src.Quantity AS DECIMAL(18,4)) * ISNULL(p.SachetsPerBag, 1)
               ELSE CAST(src.Quantity AS DECIMAL(18,4))
           END AS BaseQuantity
    FROM   src
    LEFT JOIN dbo.WaterProducts p
           ON p.WaterProductId = src.WaterProductId AND p.FarmId = @FarmId;

    -- Reject if any product doesn't belong to this farm.
    IF EXISTS (
        SELECT 1 FROM @Items i
        LEFT JOIN dbo.WaterProducts p
               ON p.WaterProductId = i.WaterProductId AND p.FarmId = @FarmId
        WHERE p.WaterProductId IS NULL
    )
    BEGIN
        RAISERROR('One or more products do not belong to this farm.', 16, 1);
        RETURN;
    END

    -- Validate sachet stock per product (sum of equivalent sachets <= on-hand sachets).
    DECLARE @InsufficientName NVARCHAR(150);
    SELECT TOP (1) @InsufficientName = p.Name
    FROM   @Items i
    INNER JOIN dbo.WaterProducts p ON p.WaterProductId = i.WaterProductId
    OUTER APPLY (
        SELECT ISNULL(SUM(st.BaseQuantity), 0) AS OnHandBase
        FROM   dbo.WaterStockTransactions st
        WHERE  st.WaterProductId = p.WaterProductId
    ) oh
    WHERE p.IsSachetProduct = 1
      AND i.BaseQuantity > oh.OnHandBase;

    IF @InsufficientName IS NOT NULL
    BEGIN
        RAISERROR('Insufficient sachet stock for %s.', 16, 1, @InsufficientName);
        RETURN;
    END

    BEGIN TRAN;

    DECLARE @SaleId INT;
    INSERT INTO dbo.WaterSales
        (FarmId, WaterCustomerId, SaleDate, TotalAmount, AmountPaid, Status, Notes, CreatedBy)
    VALUES (@FarmId, @WaterCustomerId, @SaleDate, 0, 0, N'Pending', @Notes, @CreatedBy);
    SET @SaleId = SCOPE_IDENTITY();

    INSERT INTO dbo.WaterSaleItems
        (WaterSaleId, WaterProductId, Quantity, UnitPrice, SellingUnit, BaseUnit, BaseQuantity)
    SELECT @SaleId, WaterProductId, Quantity, UnitPrice, SellingUnit, BaseUnit, BaseQuantity
    FROM   @Items;

    -- Stock-out txn per line, signed in BaseQuantity (so the on-hand SUM stays
    -- in sachets for sachet products).
    INSERT INTO dbo.WaterStockTransactions
        (FarmId, WaterProductId, TxnType, Quantity, BaseQuantity, RelatedSaleId, Note, CreatedBy)
    SELECT @FarmId, WaterProductId, N'Sale',
           -Quantity,
           -BaseQuantity,
           @SaleId, CONCAT(N'Sale #', @SaleId), @CreatedBy
    FROM   @Items;

    UPDATE dbo.WaterSales
    SET    TotalAmount = ISNULL((SELECT SUM(LineTotal) FROM dbo.WaterSaleItems WHERE WaterSaleId = @SaleId), 0)
    WHERE  WaterSaleId = @SaleId;

    COMMIT;

    SELECT @SaleId AS WaterSaleId;
END
GO

-- -----------------------------------------------------------------------------
-- 5. spWaterInventory_GetStockSummary — bag + sachet breakdown for inventory UI
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterInventory_GetStockSummary
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.WaterProductId, p.FarmId, p.Name, p.Sku, p.SizeMl, p.Unit,
           p.UnitPrice, p.BagPrice, p.SachetPrice, p.SachetsPerBag,
           p.BaseUnit, p.IsSachetProduct, p.IsActive, p.ProductType,
           ISNULL(s.OnHandRaw,  0) AS StockOnHand,
           ISNULL(s.OnHandBase, 0) AS StockBaseQuantity,
           CASE
               WHEN p.IsSachetProduct = 1 AND ISNULL(p.SachetsPerBag, 0) > 0
                   THEN ISNULL(s.OnHandBase, 0) / NULLIF(p.SachetsPerBag, 0)
               ELSE ISNULL(s.OnHandRaw, 0)
           END AS StockBags,
           CASE
               WHEN p.IsSachetProduct = 1 THEN ISNULL(s.OnHandBase, 0)
               ELSE NULL
           END AS StockSachets
    FROM   dbo.WaterProducts p
    OUTER APPLY (
        SELECT SUM(CAST(st.Quantity AS DECIMAL(18,4))) AS OnHandRaw,
               SUM(ISNULL(st.BaseQuantity, st.Quantity)) AS OnHandBase
        FROM   dbo.WaterStockTransactions st
        WHERE  st.WaterProductId = p.WaterProductId
    ) s
    WHERE  p.FarmId = @FarmId
    ORDER BY p.Name;
END
GO

-- -----------------------------------------------------------------------------
-- 6. Update spWaterProduct_* to surface new fields (additive only, no breakage)
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterProduct_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.WaterProductId, p.FarmId, p.Name, p.Sku, p.SizeMl, p.Unit,
           p.UnitPrice, p.IsActive, p.Notes, p.CreatedDate, p.UpdatedDate,
           ISNULL(p.ProductType, N'FinishedGood') AS ProductType,
           p.BaseUnit, p.SachetsPerBag, p.BagPrice, p.SachetPrice, p.IsSachetProduct,
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

-- Update the upsert SPs to write the new bag/sachet fields. Existing callers
-- continue to work because all the new params have defaults.
CREATE OR ALTER PROCEDURE dbo.spWaterProduct_Insert
    @FarmId          NVARCHAR(450),
    @Name            NVARCHAR(150),
    @Sku             NVARCHAR(60)  = NULL,
    @SizeMl          INT           = NULL,
    @Unit            NVARCHAR(30)  = NULL,
    @UnitPrice       DECIMAL(12,2) = 0,
    @IsActive        BIT           = 1,
    @ProductType     NVARCHAR(30)  = 'FinishedGood',
    @Notes           NVARCHAR(500) = NULL,
    @BaseUnit        NVARCHAR(20)  = NULL,
    @SachetsPerBag   INT           = NULL,
    @BagPrice        DECIMAL(12,2) = NULL,
    @SachetPrice     DECIMAL(12,2) = NULL,
    @IsSachetProduct BIT           = 0
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterProducts
        (FarmId, Name, Sku, SizeMl, Unit, UnitPrice, IsActive, ProductType, Notes,
         BaseUnit, SachetsPerBag, BagPrice, SachetPrice, IsSachetProduct)
    VALUES
        (@FarmId, @Name, @Sku, @SizeMl, @Unit, @UnitPrice, @IsActive,
         ISNULL(@ProductType, N'FinishedGood'), @Notes,
         @BaseUnit, @SachetsPerBag, @BagPrice, @SachetPrice, @IsSachetProduct);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProduct_Update
    @WaterProductId  INT,
    @FarmId          NVARCHAR(450),
    @Name            NVARCHAR(150),
    @Sku             NVARCHAR(60)  = NULL,
    @SizeMl          INT           = NULL,
    @Unit            NVARCHAR(30)  = NULL,
    @UnitPrice       DECIMAL(12,2) = 0,
    @IsActive        BIT           = 1,
    @ProductType     NVARCHAR(30)  = 'FinishedGood',
    @Notes           NVARCHAR(500) = NULL,
    @BaseUnit        NVARCHAR(20)  = NULL,
    @SachetsPerBag   INT           = NULL,
    @BagPrice        DECIMAL(12,2) = NULL,
    @SachetPrice     DECIMAL(12,2) = NULL,
    @IsSachetProduct BIT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterProducts
    SET    Name            = @Name,
           Sku             = @Sku,
           SizeMl          = @SizeMl,
           Unit            = @Unit,
           UnitPrice       = @UnitPrice,
           IsActive        = @IsActive,
           ProductType     = ISNULL(@ProductType, ProductType),
           Notes           = @Notes,
           BaseUnit        = @BaseUnit,
           SachetsPerBag   = @SachetsPerBag,
           BagPrice        = @BagPrice,
           SachetPrice     = @SachetPrice,
           IsSachetProduct = ISNULL(@IsSachetProduct, IsSachetProduct),
           UpdatedDate     = SYSUTCDATETIME()
    WHERE  WaterProductId = @WaterProductId AND FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- 7. Patch spWaterSale_GetById to surface the new selling-unit fields.
--    Items result set gets SellingUnit / BaseUnit / BaseQuantity appended.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterSale_GetById
    @WaterSaleId INT,
    @FarmId      NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.WaterSaleId, s.FarmId, s.WaterCustomerId, c.Name AS CustomerName,
           s.SaleDate, s.TotalAmount, s.AmountPaid,
           (s.TotalAmount - s.AmountPaid) AS Balance,
           s.Status, s.Notes, s.CreatedDate, s.CreatedBy, s.UpdatedDate
    FROM dbo.WaterSales s
    LEFT JOIN dbo.WaterCustomers c ON c.WaterCustomerId = s.WaterCustomerId
    WHERE s.WaterSaleId = @WaterSaleId AND s.FarmId = @FarmId;

    SELECT i.WaterSaleItemId, i.WaterSaleId, i.WaterProductId, p.Name AS ProductName,
           i.Quantity, i.UnitPrice, i.LineTotal,
           i.SellingUnit, i.BaseUnit, i.BaseQuantity
    FROM dbo.WaterSaleItems i
    INNER JOIN dbo.WaterProducts p ON p.WaterProductId = i.WaterProductId
    WHERE i.WaterSaleId = @WaterSaleId
    ORDER BY i.WaterSaleItemId;
END
GO

-- -----------------------------------------------------------------------------
-- 8. Grants
-- -----------------------------------------------------------------------------
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterSale_CreateV2              TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterInventory_GetStockSummary  TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterProduct_GetAll             TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterProduct_GetById            TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterProduct_Insert             TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterProduct_Update             TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterSale_GetById               TO [Techretainer];
END
GO
IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterSale_CreateV2              TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterInventory_GetStockSummary  TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterProduct_GetAll             TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterProduct_GetById            TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterProduct_Insert             TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterProduct_Update             TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterSale_GetById               TO PoultryAppRole;
END
GO

PRINT '084_AddSachetInventoryAndSellingUnits.sql complete.';
GO
