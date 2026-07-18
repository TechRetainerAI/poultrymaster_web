-- =============================================================================
-- Migration 164: water raw-material item gets a separate PURCHASE unit
-- =============================================================================
-- Mirrors poultry migration 161 for the Water company. An item now carries two
-- units: UnitOfMeasure = the PRODUCTION-LEVEL unit (how it's stocked/consumed)
-- and PurchaseUnitOfMeasure = how it's BOUGHT. Additive column; existing items
-- get PurchaseUnitOfMeasure = UnitOfMeasure (1:1) so nothing changes until
-- edited. Item GetAll/GetById already SELECT * so they return it automatically.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.WaterRawMaterialItems','PurchaseUnitOfMeasure') IS NULL
    ALTER TABLE dbo.WaterRawMaterialItems ADD PurchaseUnitOfMeasure NVARCHAR(30) NULL;
GO

-- Backfill existing items so their purchase unit defaults to their current unit.
UPDATE dbo.WaterRawMaterialItems
SET    PurchaseUnitOfMeasure = UnitOfMeasure
WHERE  PurchaseUnitOfMeasure IS NULL AND UnitOfMeasure IS NOT NULL;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_Insert
    @FarmId NVARCHAR(450), @ItemName NVARCHAR(150), @Category NVARCHAR(40),
    @UnitOfMeasure NVARCHAR(30) = NULL,
    @MinimumStockAlert DECIMAL(14,3) = 0,
    @CurrentQuantity DECIMAL(14,3) = 0,
    @IsActive BIT = 1, @Notes NVARCHAR(500) = NULL,
    @PurchaseUnitOfMeasure NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterRawMaterialItems (FarmId, ItemName, Category, UnitOfMeasure,
        MinimumStockAlert, CurrentQuantity, IsActive, Notes, PurchaseUnitOfMeasure)
    VALUES (@FarmId, @ItemName, @Category, @UnitOfMeasure,
        @MinimumStockAlert, @CurrentQuantity, @IsActive, @Notes, ISNULL(@PurchaseUnitOfMeasure, @UnitOfMeasure));
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_Update
    @WaterRawMaterialItemId INT, @FarmId NVARCHAR(450),
    @ItemName NVARCHAR(150), @Category NVARCHAR(40),
    @UnitOfMeasure NVARCHAR(30) = NULL,
    @MinimumStockAlert DECIMAL(14,3),
    @IsActive BIT, @Notes NVARCHAR(500) = NULL,
    @PurchaseUnitOfMeasure NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- CurrentQuantity is NOT updateable here — only via Purchases / Usage.
    UPDATE dbo.WaterRawMaterialItems
    SET ItemName = @ItemName, Category = @Category, UnitOfMeasure = @UnitOfMeasure,
        MinimumStockAlert = @MinimumStockAlert, IsActive = @IsActive,
        Notes = @Notes, PurchaseUnitOfMeasure = ISNULL(@PurchaseUnitOfMeasure, @UnitOfMeasure),
        UpdatedAt = SYSUTCDATETIME()
    WHERE WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_Insert TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_Update TO [Techretainer];
END
GO

PRINT '164_WaterRawMaterialItemPurchaseUnit.sql complete.';
GO
