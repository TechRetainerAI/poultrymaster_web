-- =============================================================================
-- Migration 168: Feed Production — Feed Formulas (Phase 2)
-- =============================================================================
-- Reusable feed recipes for the Feed Production module. A formula ties a
-- FinishedFeed raw-material item to the ingredient items that make it up. Each
-- line is either a Percentage of the batch (auto-scales with quantity produced)
-- or a FixedQuantity. When a batch selects a formula and a quantity to produce,
-- the UI auto-calculates required ingredient quantities (Phase 5).
--
--   dbo.PoultryFeedFormulas      — header (name, finished-feed item, default unit)
--   dbo.PoultryFeedFormulaLines  — ingredient lines (Percentage | FixedQuantity)
--
-- Both FinishedFeedItemId and IngredientItemId reference dbo.PoultryRawMaterialItems
-- (finished feed = Category 'FinishedFeed'; ingredients = 'FeedIngredient').
-- Category is convention-enforced by the UI; not a DB CHECK.
--
-- Additive + idempotent (object guards + CREATE OR ALTER). Safe to re-run.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. PoultryFeedFormulas — the formula header
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryFeedFormulas', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryFeedFormulas (
        PoultryFeedFormulaId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId               NVARCHAR(450) NOT NULL,
        FormulaName          NVARCHAR(150) NOT NULL,
        FinishedFeedItemId   INT           NOT NULL,   -- -> PoultryRawMaterialItems (Category 'FinishedFeed')
        DefaultOutputUnit    NVARCHAR(30)  NULL,
        Notes                NVARCHAR(500) NULL,
        IsActive             BIT           NOT NULL CONSTRAINT DF_PoultryFeedFormulas_Active DEFAULT (1),
        CreatedBy            NVARCHAR(450) NULL,
        CreatedAt            DATETIME2     NOT NULL CONSTRAINT DF_PoultryFeedFormulas_Created DEFAULT (SYSUTCDATETIME()),
        UpdatedBy            NVARCHAR(450) NULL,
        UpdatedAt            DATETIME2     NULL,
        CONSTRAINT FK_PoultryFeedFormulas_Item FOREIGN KEY (FinishedFeedItemId) REFERENCES dbo.PoultryRawMaterialItems (PoultryRawMaterialItemId),
        CONSTRAINT UQ_PoultryFeedFormulas_Farm_Name UNIQUE (FarmId, FormulaName)
    );
    CREATE INDEX IX_PoultryFeedFormulas_FarmId ON dbo.PoultryFeedFormulas (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 2. PoultryFeedFormulaLines — ingredient lines
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryFeedFormulaLines', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryFeedFormulaLines (
        PoultryFeedFormulaLineId INT IDENTITY(1,1) PRIMARY KEY,
        PoultryFeedFormulaId     INT           NOT NULL,
        IngredientItemId         INT           NOT NULL,   -- -> PoultryRawMaterialItems (Category 'FeedIngredient')
        QuantityMode             NVARCHAR(20)  NOT NULL CONSTRAINT DF_PoultryFeedFormulaLines_Mode DEFAULT ('Percentage'),  -- 'Percentage' | 'FixedQuantity'
        Percentage               DECIMAL(9,4)  NULL,        -- used when QuantityMode = 'Percentage'
        FixedQuantity            DECIMAL(18,6) NULL,        -- used when QuantityMode = 'FixedQuantity'
        UnitOfMeasure            NVARCHAR(30)  NULL,
        SortOrder                INT           NOT NULL CONSTRAINT DF_PoultryFeedFormulaLines_Sort DEFAULT (0),
        Notes                    NVARCHAR(300) NULL,
        CONSTRAINT FK_PoultryFeedFormulaLines_Formula FOREIGN KEY (PoultryFeedFormulaId) REFERENCES dbo.PoultryFeedFormulas (PoultryFeedFormulaId) ON DELETE CASCADE,
        CONSTRAINT FK_PoultryFeedFormulaLines_Item    FOREIGN KEY (IngredientItemId)     REFERENCES dbo.PoultryRawMaterialItems (PoultryRawMaterialItemId),
        CONSTRAINT CK_PoultryFeedFormulaLines_Mode CHECK (QuantityMode IN ('Percentage','FixedQuantity'))
    );
    CREATE INDEX IX_PoultryFeedFormulaLines_Formula ON dbo.PoultryFeedFormulaLines (PoultryFeedFormulaId);
END
GO

-- =============================================================================
-- Stored procedures
-- =============================================================================

-- List all formulas with finished-feed name, line count and percentage total
-- (the last two power the list view + the "should total 100%" badge).
CREATE OR ALTER PROCEDURE dbo.spPoultryFeedFormula_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT f.*,
           i.ItemName      AS FinishedFeedItemName,
           i.UnitOfMeasure AS FinishedFeedUnit,
           (SELECT COUNT(*) FROM dbo.PoultryFeedFormulaLines l WHERE l.PoultryFeedFormulaId = f.PoultryFeedFormulaId) AS LineCount,
           CAST(ISNULL((SELECT SUM(l.Percentage) FROM dbo.PoultryFeedFormulaLines l
                        WHERE l.PoultryFeedFormulaId = f.PoultryFeedFormulaId AND l.QuantityMode = 'Percentage'), 0) AS DECIMAL(9,4)) AS PercentageTotal
    FROM   dbo.PoultryFeedFormulas f
    LEFT   JOIN dbo.PoultryRawMaterialItems i ON i.PoultryRawMaterialItemId = f.FinishedFeedItemId
    WHERE  f.FarmId = @FarmId
    ORDER  BY f.IsActive DESC, f.FormulaName;
END
GO

-- Header (result 1) + lines enriched with ingredient name/unit/stock and the
-- latest known per-unit purchase cost (result 2), used for cost previews.
CREATE OR ALTER PROCEDURE dbo.spPoultryFeedFormula_GetById
    @FarmId NVARCHAR(450), @PoultryFeedFormulaId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT f.*, i.ItemName AS FinishedFeedItemName, i.UnitOfMeasure AS FinishedFeedUnit
    FROM   dbo.PoultryFeedFormulas f
    LEFT   JOIN dbo.PoultryRawMaterialItems i ON i.PoultryRawMaterialItemId = f.FinishedFeedItemId
    WHERE  f.FarmId = @FarmId AND f.PoultryFeedFormulaId = @PoultryFeedFormulaId;

    SELECT l.*,
           i.ItemName        AS IngredientName,
           i.UnitOfMeasure   AS IngredientUnit,
           i.CurrentQuantity AS AvailableStock,
           CAST(ISNULL((
               SELECT TOP 1 CASE WHEN ISNULL(p.ProductionUnitsPerPurchaseUnit,0) > 0
                                 THEN p.TotalCost / NULLIF(p.Quantity * p.ProductionUnitsPerPurchaseUnit,0)
                                 ELSE p.UnitCost END
               FROM dbo.PoultryRawMaterialPurchases p
               WHERE p.PoultryRawMaterialItemId = l.IngredientItemId AND p.FarmId = @FarmId
               ORDER BY p.PurchaseDate DESC, p.PoultryRawMaterialPurchaseId DESC
           ), 0) AS DECIMAL(18,4)) AS LatestUnitCost
    FROM   dbo.PoultryFeedFormulaLines l
    INNER  JOIN dbo.PoultryFeedFormulas f ON f.PoultryFeedFormulaId = l.PoultryFeedFormulaId
    INNER  JOIN dbo.PoultryRawMaterialItems i ON i.PoultryRawMaterialItemId = l.IngredientItemId
    WHERE  f.FarmId = @FarmId AND l.PoultryFeedFormulaId = @PoultryFeedFormulaId
    ORDER  BY l.SortOrder, l.PoultryFeedFormulaLineId;
END
GO

-- Insert (when @PoultryFeedFormulaId is NULL/0) or update a formula + replace all
-- its lines from @LinesJson. Returns the formula id. Transactional.
CREATE OR ALTER PROCEDURE dbo.spPoultryFeedFormula_Upsert
    @FarmId              NVARCHAR(450),
    @PoultryFeedFormulaId INT           = NULL,
    @FormulaName         NVARCHAR(150),
    @FinishedFeedItemId  INT,
    @DefaultOutputUnit   NVARCHAR(30)   = NULL,
    @Notes               NVARCHAR(500)  = NULL,
    @IsActive            BIT            = 1,
    @UserId              NVARCHAR(450)  = NULL,
    @LinesJson           NVARCHAR(MAX)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    DECLARE @Id INT = @PoultryFeedFormulaId;

    IF (@Id IS NULL OR @Id = 0)
    BEGIN
        INSERT INTO dbo.PoultryFeedFormulas (FarmId, FormulaName, FinishedFeedItemId, DefaultOutputUnit, Notes, IsActive, CreatedBy, UpdatedBy, UpdatedAt)
        VALUES (@FarmId, @FormulaName, @FinishedFeedItemId, @DefaultOutputUnit, @Notes, ISNULL(@IsActive,1), @UserId, @UserId, SYSUTCDATETIME());
        SET @Id = CAST(SCOPE_IDENTITY() AS INT);
    END
    ELSE
    BEGIN
        UPDATE dbo.PoultryFeedFormulas
        SET    FormulaName = @FormulaName, FinishedFeedItemId = @FinishedFeedItemId,
               DefaultOutputUnit = @DefaultOutputUnit, Notes = @Notes, IsActive = ISNULL(@IsActive,1),
               UpdatedBy = @UserId, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryFeedFormulaId = @Id AND FarmId = @FarmId;

        DELETE FROM dbo.PoultryFeedFormulaLines WHERE PoultryFeedFormulaId = @Id;
    END

    IF (@LinesJson IS NOT NULL AND LEN(@LinesJson) > 2)
    BEGIN
        INSERT INTO dbo.PoultryFeedFormulaLines
            (PoultryFeedFormulaId, IngredientItemId, QuantityMode, Percentage, FixedQuantity, UnitOfMeasure, SortOrder, Notes)
        SELECT @Id, j.IngredientItemId,
               CASE WHEN j.QuantityMode IN ('Percentage','FixedQuantity') THEN j.QuantityMode ELSE 'Percentage' END,
               j.Percentage, j.FixedQuantity, j.UnitOfMeasure, ISNULL(j.SortOrder,0), j.Notes
        FROM OPENJSON(@LinesJson) WITH (
            IngredientItemId INT           '$.ingredientItemId',
            QuantityMode     NVARCHAR(20)  '$.quantityMode',
            Percentage       DECIMAL(9,4)  '$.percentage',
            FixedQuantity    DECIMAL(18,6) '$.fixedQuantity',
            UnitOfMeasure    NVARCHAR(30)  '$.unitOfMeasure',
            SortOrder        INT           '$.sortOrder',
            Notes            NVARCHAR(300) '$.notes'
        ) j
        WHERE j.IngredientItemId IS NOT NULL;
    END

    COMMIT TRANSACTION;
    SELECT @Id AS PoultryFeedFormulaId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryFeedFormula_Delete
    @FarmId NVARCHAR(450), @PoultryFeedFormulaId INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.PoultryFeedFormulas
    WHERE  PoultryFeedFormulaId = @PoultryFeedFormulaId AND FarmId = @FarmId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryFeedFormula_GetAll  TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryFeedFormula_GetById TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryFeedFormula_Upsert  TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryFeedFormula_Delete  TO [Techretainer];
    PRINT '168: granted EXECUTE on spPoultryFeedFormula_* to Techretainer.';
END
GO

PRINT '168_PoultryFeedFormulas.sql complete.';
GO
