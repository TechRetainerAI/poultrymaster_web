-- =============================================================================
-- Migration 129: Poultry Products — egg/recipe flags, size + default egg product
-- =============================================================================
-- Doc sections 3, 7, 8, 14. Additive columns + a default-egg ensure/backfill SP.
--   * PoultryProducts: IsRawEggProduct, RequiresRecipeSetup, Size (all nullable-safe)
--   * spPoultryProduct_EnsureDefaultEgg: idempotently create the "Eggs" finished
--     product for a farm (raw egg product, no recipe). Used on load + backfill.
-- Idempotent (guarded ALTER + CREATE OR ALTER).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.PoultryProducts', 'IsRawEggProduct') IS NULL
    ALTER TABLE dbo.PoultryProducts ADD IsRawEggProduct BIT NOT NULL CONSTRAINT DF_PoultryProducts_Egg DEFAULT (0);
GO
IF COL_LENGTH('dbo.PoultryProducts', 'RequiresRecipeSetup') IS NULL
    ALTER TABLE dbo.PoultryProducts ADD RequiresRecipeSetup BIT NOT NULL CONSTRAINT DF_PoultryProducts_Recipe DEFAULT (1);
GO
IF COL_LENGTH('dbo.PoultryProducts', 'Size') IS NULL
    ALTER TABLE dbo.PoultryProducts ADD Size NVARCHAR(60) NULL;
GO

-- GetAll returns the new fields (SELECT p.* already does once columns exist; the
-- StockOnHand subquery is unchanged). Redefined for clarity + to be explicit.
CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.*,
           CAST(ISNULL((SELECT SUM(t.Quantity) FROM dbo.PoultryStockTransactions t
                        WHERE t.PoultryProductId = p.PoultryProductId AND t.FarmId = p.FarmId), 0) AS DECIMAL(18,3)) AS StockOnHand
    FROM   dbo.PoultryProducts p
    WHERE  p.FarmId = @FarmId
    ORDER  BY p.IsActive DESC, p.Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_Insert
    @FarmId NVARCHAR(450), @Name NVARCHAR(150), @Sku NVARCHAR(60) = NULL,
    @Unit NVARCHAR(30) = NULL, @UnitPrice DECIMAL(14,2) = 0,
    @ProductType NVARCHAR(30) = 'FinishedGood', @Notes NVARCHAR(500) = NULL,
    @IsRawEggProduct BIT = 0, @RequiresRecipeSetup BIT = 1, @Size NVARCHAR(60) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.PoultryProducts (FarmId, Name, Sku, Unit, UnitPrice, ProductType, Notes, IsRawEggProduct, RequiresRecipeSetup, Size)
    VALUES (@FarmId, @Name, @Sku, @Unit, ISNULL(@UnitPrice,0), ISNULL(@ProductType,'FinishedGood'), @Notes,
            ISNULL(@IsRawEggProduct,0), ISNULL(@RequiresRecipeSetup,1), @Size);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_Update
    @PoultryProductId INT, @FarmId NVARCHAR(450), @Name NVARCHAR(150), @Sku NVARCHAR(60) = NULL,
    @Unit NVARCHAR(30) = NULL, @UnitPrice DECIMAL(14,2) = 0, @ProductType NVARCHAR(30) = 'FinishedGood',
    @IsActive BIT = 1, @Notes NVARCHAR(500) = NULL,
    @IsRawEggProduct BIT = 0, @RequiresRecipeSetup BIT = 1, @Size NVARCHAR(60) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryProducts
    SET    Name = @Name, Sku = @Sku, Unit = @Unit, UnitPrice = ISNULL(@UnitPrice,0),
           ProductType = ISNULL(@ProductType,'FinishedGood'), IsActive = ISNULL(@IsActive,1),
           Notes = @Notes, IsRawEggProduct = ISNULL(@IsRawEggProduct,0),
           RequiresRecipeSetup = ISNULL(@RequiresRecipeSetup,1), Size = @Size, UpdatedDate = SYSUTCDATETIME()
    WHERE  PoultryProductId = @PoultryProductId AND FarmId = @FarmId;
END
GO

-- Idempotently ensure a default egg finished-product exists for the farm.
-- Returns the egg product id (existing or newly created).
CREATE OR ALTER PROCEDURE dbo.spPoultryProduct_EnsureDefaultEgg
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Id INT;
    SELECT TOP 1 @Id = PoultryProductId FROM dbo.PoultryProducts
    WHERE  FarmId = @FarmId AND (IsRawEggProduct = 1 OR Name IN (N'Eggs', N'Chicken Eggs'))
    ORDER  BY IsRawEggProduct DESC, PoultryProductId;

    IF @Id IS NULL
    BEGIN
        INSERT INTO dbo.PoultryProducts (FarmId, Name, Unit, UnitPrice, ProductType, IsRawEggProduct, RequiresRecipeSetup)
        VALUES (@FarmId, N'Eggs', N'Crate', 0, 'FinishedGood', 1, 0);
        SET @Id = CAST(SCOPE_IDENTITY() AS INT);
    END
    SELECT @Id AS PoultryProductId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryProduct_GetAll          TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProduct_Insert          TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProduct_Update          TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProduct_EnsureDefaultEgg TO [Techretainer];
    PRINT '129: granted EXECUTE to Techretainer.';
END
GO

PRINT '129_PoultryProductsEggAndFields.sql complete.';
GO
