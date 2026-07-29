-- =============================================================================
-- Migration 176: Feed Production — decouple Feed Formula from a finished feed item
-- =============================================================================
-- A Feed Formula is a *reusable ingredient pattern*. It should NOT be bound to a
-- single finished-feed item: any formula can be applied to any finished feed the
-- user chooses when producing a batch (the Feed Production Batch decides the
-- output item, not the formula).
--
-- This makes PoultryFeedFormulas.FinishedFeedItemId NULLABLE and stops requiring
-- it on upsert. Existing formulas keep whatever item they were bound to (it is now
-- purely informational / legacy). GetAll / GetById already LEFT JOIN the item, so
-- a NULL simply shows no finished-feed name.
--
-- Additive + idempotent (column guard + CREATE OR ALTER). Safe to re-run.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- 1. Make FinishedFeedItemId nullable (the FK stays; FKs allow NULLs).
IF COLUMNPROPERTY(OBJECT_ID('dbo.PoultryFeedFormulas'), 'FinishedFeedItemId', 'AllowsNull') = 0
BEGIN
    ALTER TABLE dbo.PoultryFeedFormulas ALTER COLUMN FinishedFeedItemId INT NULL;
    PRINT '176: PoultryFeedFormulas.FinishedFeedItemId is now nullable.';
END
GO

-- 2. Upsert no longer requires a finished-feed item. @FinishedFeedItemId defaults
--    to NULL; a 0 is coerced to NULL. Everything else is unchanged from 168.
CREATE OR ALTER PROCEDURE dbo.spPoultryFeedFormula_Upsert
    @FarmId              NVARCHAR(450),
    @PoultryFeedFormulaId INT           = NULL,
    @FormulaName         NVARCHAR(150),
    @FinishedFeedItemId  INT            = NULL,   -- optional now (NULL / 0 = unbound)
    @DefaultOutputUnit   NVARCHAR(30)   = NULL,
    @Notes               NVARCHAR(500)  = NULL,
    @IsActive            BIT            = 1,
    @UserId              NVARCHAR(450)  = NULL,
    @LinesJson           NVARCHAR(MAX)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @FeedItem INT = NULLIF(@FinishedFeedItemId, 0);

    BEGIN TRANSACTION;

    DECLARE @Id INT = @PoultryFeedFormulaId;

    IF (@Id IS NULL OR @Id = 0)
    BEGIN
        INSERT INTO dbo.PoultryFeedFormulas (FarmId, FormulaName, FinishedFeedItemId, DefaultOutputUnit, Notes, IsActive, CreatedBy, UpdatedBy, UpdatedAt)
        VALUES (@FarmId, @FormulaName, @FeedItem, @DefaultOutputUnit, @Notes, ISNULL(@IsActive,1), @UserId, @UserId, SYSUTCDATETIME());
        SET @Id = CAST(SCOPE_IDENTITY() AS INT);
    END
    ELSE
    BEGIN
        UPDATE dbo.PoultryFeedFormulas
        SET    FormulaName = @FormulaName, FinishedFeedItemId = @FeedItem,
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

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryFeedFormula_Upsert TO [Techretainer];
    PRINT '176: granted EXECUTE on spPoultryFeedFormula_Upsert to Techretainer.';
END
GO

PRINT '176_PoultryFeedFormulaDecouple.sql complete.';
GO
