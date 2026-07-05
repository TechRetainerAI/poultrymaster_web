-- =============================================================================
-- Migration 125: Poultry Company — Production Recipes (bill of materials) (slice 3)
-- =============================================================================
-- Mirrors WaterProductionRecipe(Item). A recipe ties a finished product to the
-- raw materials it consumes per output unit (with waste allowance). Additive.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.PoultryProductionRecipes', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryProductionRecipes (
        PoultryProductionRecipeId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId           NVARCHAR(450) NOT NULL,
        PoultryProductId INT           NOT NULL,
        RecipeName       NVARCHAR(150) NULL,
        IsActive         BIT           NOT NULL CONSTRAINT DF_PoultryRecipes_Active DEFAULT (1),
        Notes            NVARCHAR(500) NULL,
        CreatedBy        NVARCHAR(450) NULL,
        CreatedAt        DATETIME2     NOT NULL CONSTRAINT DF_PoultryRecipes_Created DEFAULT (SYSUTCDATETIME()),
        UpdatedBy        NVARCHAR(450) NULL,
        UpdatedAt        DATETIME2     NULL,
        CONSTRAINT FK_PoultryRecipes_Product FOREIGN KEY (PoultryProductId) REFERENCES dbo.PoultryProducts (PoultryProductId),
        CONSTRAINT UQ_PoultryRecipes_Product UNIQUE (FarmId, PoultryProductId)
    );
    CREATE INDEX IX_PoultryRecipes_FarmId ON dbo.PoultryProductionRecipes (FarmId);
END
GO

IF OBJECT_ID('dbo.PoultryProductionRecipeItems', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryProductionRecipeItems (
        PoultryProductionRecipeItemId INT IDENTITY(1,1) PRIMARY KEY,
        PoultryProductionRecipeId INT NOT NULL,
        PoultryRawMaterialItemId  INT NOT NULL,
        QuantityPerOutputUnit DECIMAL(18,6) NOT NULL CONSTRAINT DF_PoultryRecipeItems_Qty DEFAULT (0),
        WasteAllowancePercent DECIMAL(9,4)  NOT NULL CONSTRAINT DF_PoultryRecipeItems_Waste DEFAULT (0),
        IsOptional   BIT NOT NULL CONSTRAINT DF_PoultryRecipeItems_Opt DEFAULT (0),
        DisplayOrder INT NOT NULL CONSTRAINT DF_PoultryRecipeItems_Ord DEFAULT (0),
        Notes        NVARCHAR(300) NULL,
        CONSTRAINT FK_PoultryRecipeItems_Recipe FOREIGN KEY (PoultryProductionRecipeId) REFERENCES dbo.PoultryProductionRecipes (PoultryProductionRecipeId) ON DELETE CASCADE,
        CONSTRAINT FK_PoultryRecipeItems_Item   FOREIGN KEY (PoultryRawMaterialItemId)  REFERENCES dbo.PoultryRawMaterialItems (PoultryRawMaterialItemId)
    );
    CREATE INDEX IX_PoultryRecipeItems_Recipe ON dbo.PoultryProductionRecipeItems (PoultryProductionRecipeId);
END
GO

-- Returns recipe header (result 1) + items with the item name/unit and the
-- latest known per-unit cost (result 2) for production costing.
CREATE OR ALTER PROCEDURE dbo.spPoultryProductionRecipe_GetByProduct
    @FarmId NVARCHAR(450), @PoultryProductId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.PoultryProductionRecipes
    WHERE  FarmId = @FarmId AND PoultryProductId = @PoultryProductId;

    SELECT ri.*, i.ItemName, i.UnitOfMeasure, i.CurrentQuantity AS AvailableStock,
           CAST(ISNULL((
               SELECT TOP 1 CASE WHEN ISNULL(p.ProductionUnitsPerPurchaseUnit,0) > 0
                                 THEN p.TotalCost / NULLIF(p.Quantity * p.ProductionUnitsPerPurchaseUnit,0)
                                 ELSE p.UnitCost END
               FROM dbo.PoultryRawMaterialPurchases p
               WHERE p.PoultryRawMaterialItemId = ri.PoultryRawMaterialItemId AND p.FarmId = @FarmId
               ORDER BY p.PurchaseDate DESC, p.PoultryRawMaterialPurchaseId DESC
           ), 0) AS DECIMAL(18,4)) AS LatestUnitCost
    FROM   dbo.PoultryProductionRecipeItems ri
    INNER  JOIN dbo.PoultryProductionRecipes r ON r.PoultryProductionRecipeId = ri.PoultryProductionRecipeId
    INNER  JOIN dbo.PoultryRawMaterialItems  i ON i.PoultryRawMaterialItemId  = ri.PoultryRawMaterialItemId
    WHERE  r.FarmId = @FarmId AND r.PoultryProductId = @PoultryProductId
    ORDER  BY ri.DisplayOrder, ri.PoultryProductionRecipeItemId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProductionRecipe_Upsert
    @FarmId NVARCHAR(450), @PoultryProductId INT, @RecipeName NVARCHAR(150) = NULL,
    @Notes NVARCHAR(500) = NULL, @ItemsJson NVARCHAR(MAX) = NULL, @UpdatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    DECLARE @RecipeId INT;
    SELECT @RecipeId = PoultryProductionRecipeId FROM dbo.PoultryProductionRecipes
    WHERE  FarmId = @FarmId AND PoultryProductId = @PoultryProductId;

    IF @RecipeId IS NULL
    BEGIN
        INSERT INTO dbo.PoultryProductionRecipes (FarmId, PoultryProductId, RecipeName, Notes, CreatedBy, UpdatedBy, UpdatedAt)
        VALUES (@FarmId, @PoultryProductId, @RecipeName, @Notes, @UpdatedBy, @UpdatedBy, SYSUTCDATETIME());
        SET @RecipeId = CAST(SCOPE_IDENTITY() AS INT);
    END
    ELSE
    BEGIN
        UPDATE dbo.PoultryProductionRecipes
        SET    RecipeName = @RecipeName, Notes = @Notes, UpdatedBy = @UpdatedBy, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryProductionRecipeId = @RecipeId;
        DELETE FROM dbo.PoultryProductionRecipeItems WHERE PoultryProductionRecipeId = @RecipeId;
    END

    IF (@ItemsJson IS NOT NULL AND LEN(@ItemsJson) > 2)
    BEGIN
        INSERT INTO dbo.PoultryProductionRecipeItems
            (PoultryProductionRecipeId, PoultryRawMaterialItemId, QuantityPerOutputUnit, WasteAllowancePercent, IsOptional, DisplayOrder, Notes)
        SELECT @RecipeId, j.PoultryRawMaterialItemId, j.QuantityPerOutputUnit,
               ISNULL(j.WasteAllowancePercent,0), ISNULL(j.IsOptional,0), ISNULL(j.DisplayOrder,0), j.Notes
        FROM OPENJSON(@ItemsJson) WITH (
            PoultryRawMaterialItemId INT          '$.poultryRawMaterialItemId',
            QuantityPerOutputUnit    DECIMAL(18,6) '$.quantityPerOutputUnit',
            WasteAllowancePercent    DECIMAL(9,4)  '$.wasteAllowancePercent',
            IsOptional               BIT           '$.isOptional',
            DisplayOrder             INT           '$.displayOrder',
            Notes                    NVARCHAR(300) '$.notes'
        ) j;
    END

    COMMIT TRANSACTION;
    SELECT @RecipeId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProductionRecipe_Delete
    @FarmId NVARCHAR(450), @PoultryProductionRecipeId INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.PoultryProductionRecipes
    WHERE  PoultryProductionRecipeId = @PoultryProductionRecipeId AND FarmId = @FarmId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryProductionRecipe_GetByProduct TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProductionRecipe_Upsert       TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProductionRecipe_Delete       TO [Techretainer];
    PRINT '125: granted EXECUTE on spPoultryProductionRecipe_* to Techretainer.';
END
GO

PRINT '125_AddPoultryProductionRecipes.sql complete.';
GO
