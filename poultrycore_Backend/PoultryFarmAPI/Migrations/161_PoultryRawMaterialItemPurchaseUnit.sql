-- =============================================================================
-- Migration 161: raw-material item gets a separate PURCHASE unit (James)
-- =============================================================================
-- An item now carries two units: UnitOfMeasure = the PRODUCTION-LEVEL unit (how
-- it's stocked/consumed) and PurchaseUnitOfMeasure = how it's BOUGHT. The New
-- Purchase dialog loads both when the item is picked. Additive column; existing
-- items get PurchaseUnitOfMeasure = UnitOfMeasure (1:1) so nothing changes until
-- edited. Display-only units — the stock/costing math uses the purchase's
-- ProductionUnitsPerPurchaseUnit, so this doesn't touch batch costing.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.PoultryRawMaterialItems','PurchaseUnitOfMeasure') IS NULL
    ALTER TABLE dbo.PoultryRawMaterialItems ADD PurchaseUnitOfMeasure NVARCHAR(30) NULL;
GO

-- Backfill existing items so their purchase unit defaults to their current unit.
UPDATE dbo.PoultryRawMaterialItems
SET    PurchaseUnitOfMeasure = UnitOfMeasure
WHERE  PurchaseUnitOfMeasure IS NULL AND UnitOfMeasure IS NOT NULL;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialItem_Insert
    @FarmId           NVARCHAR(450),
    @ItemName         NVARCHAR(150),
    @Category         NVARCHAR(40),
    @UnitOfMeasure    NVARCHAR(30)  = NULL,
    @MinimumStockAlert DECIMAL(14,3) = 0,
    @Notes            NVARCHAR(500) = NULL,
    @UsageMethod      NVARCHAR(10)  = 'FIFO',
    @PurchaseUnitOfMeasure NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@UsageMethod IS NULL OR @UsageMethod NOT IN ('FIFO','LIFO','HIFO')) SET @UsageMethod = 'FIFO';
    INSERT INTO dbo.PoultryRawMaterialItems (FarmId, ItemName, Category, UnitOfMeasure, MinimumStockAlert, Notes, UsageMethod, PurchaseUnitOfMeasure)
    VALUES (@FarmId, @ItemName, @Category, @UnitOfMeasure, ISNULL(@MinimumStockAlert, 0), @Notes, @UsageMethod, ISNULL(@PurchaseUnitOfMeasure, @UnitOfMeasure));
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialItem_Update
    @PoultryRawMaterialItemId INT,
    @FarmId           NVARCHAR(450),
    @ItemName         NVARCHAR(150),
    @Category         NVARCHAR(40),
    @UnitOfMeasure    NVARCHAR(30)  = NULL,
    @MinimumStockAlert DECIMAL(14,3) = 0,
    @IsActive         BIT           = 1,
    @Notes            NVARCHAR(500) = NULL,
    @UsageMethod      NVARCHAR(10)  = 'FIFO',
    @PurchaseUnitOfMeasure NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@UsageMethod IS NULL OR @UsageMethod NOT IN ('FIFO','LIFO','HIFO')) SET @UsageMethod = 'FIFO';
    UPDATE dbo.PoultryRawMaterialItems
    SET    ItemName = @ItemName, Category = @Category, UnitOfMeasure = @UnitOfMeasure,
           MinimumStockAlert = ISNULL(@MinimumStockAlert, 0), IsActive = ISNULL(@IsActive, 1),
           Notes = @Notes, UsageMethod = @UsageMethod,
           PurchaseUnitOfMeasure = ISNULL(@PurchaseUnitOfMeasure, @UnitOfMeasure),
           UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialItemId = @PoultryRawMaterialItemId AND FarmId = @FarmId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryRawMaterialItem_Insert TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialItem_Update TO [Techretainer];
END
GO

PRINT '161_PoultryRawMaterialItemPurchaseUnit.sql complete.';
GO
