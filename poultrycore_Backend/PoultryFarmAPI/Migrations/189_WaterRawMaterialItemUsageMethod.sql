-- =============================================================================
-- Migration 189: carry UsageMethod through the water raw-material item SPs
-- =============================================================================
-- Migration 187 added WaterRawMaterialItems.UsageMethod and 188 made the draw
-- engine obey it, but the item Insert/Update SPs don't know about the column, so
-- the picker on the item form would have had nowhere to save to. Both now accept
-- it, defaulting to FIFO and ignoring anything outside the three policies (the
-- CHECK constraint would otherwise reject the whole save).
--
-- spWaterRawMaterialItem_GetAll returns i.* already, so the column reaches the
-- API without a change there.
--
-- Body as migration 165 plus the new parameter. Idempotent (CREATE OR ALTER).
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_Insert
    @FarmId NVARCHAR(450), @ItemName NVARCHAR(150), @Category NVARCHAR(40),
    @UnitOfMeasure NVARCHAR(30) = NULL,
    @MinimumStockAlert DECIMAL(14,3) = 0,
    @CurrentQuantity DECIMAL(14,3) = 0,
    @IsActive BIT = 1, @Notes NVARCHAR(500) = NULL,
    @PurchaseUnitOfMeasure NVARCHAR(30) = NULL,
    @UsageMethod NVARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- An unknown policy falls back to FIFO rather than failing the save.
    IF (@UsageMethod IS NULL OR @UsageMethod NOT IN ('FIFO','LIFO','HIFO')) SET @UsageMethod = 'FIFO';

    INSERT INTO dbo.WaterRawMaterialItems (FarmId, ItemName, Category, UnitOfMeasure,
        MinimumStockAlert, CurrentQuantity, IsActive, Notes, PurchaseUnitOfMeasure, UsageMethod)
    VALUES (@FarmId, @ItemName, @Category, @UnitOfMeasure,
        @MinimumStockAlert, @CurrentQuantity, @IsActive, @Notes, ISNULL(@PurchaseUnitOfMeasure, @UnitOfMeasure), @UsageMethod);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_Update
    @WaterRawMaterialItemId INT, @FarmId NVARCHAR(450),
    @ItemName NVARCHAR(150), @Category NVARCHAR(40),
    @UnitOfMeasure NVARCHAR(30) = NULL,
    @MinimumStockAlert DECIMAL(14,3),
    @IsActive BIT, @Notes NVARCHAR(500) = NULL,
    @PurchaseUnitOfMeasure NVARCHAR(30) = NULL,
    @UsageMethod NVARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- CurrentQuantity is NOT updateable here — only via Purchases / Usage.
    -- A NULL/unknown policy leaves whatever the item already had, so a caller
    -- that doesn't send the field can't silently reset it to FIFO.
    UPDATE dbo.WaterRawMaterialItems
    SET ItemName = @ItemName, Category = @Category, UnitOfMeasure = @UnitOfMeasure,
        MinimumStockAlert = @MinimumStockAlert, IsActive = @IsActive,
        Notes = @Notes, PurchaseUnitOfMeasure = ISNULL(@PurchaseUnitOfMeasure, @UnitOfMeasure),
        UsageMethod = CASE WHEN @UsageMethod IN ('FIFO','LIFO','HIFO') THEN @UsageMethod ELSE UsageMethod END,
        UpdatedAt = SYSUTCDATETIME()
    WHERE WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_Insert TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_Update TO PoultryAppRole;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_Insert TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_Update TO [Techretainer];
    PRINT '189: granted EXECUTE on spWaterRawMaterialItem_Insert/Update to Techretainer.';
END
GO

PRINT '189_WaterRawMaterialItemUsageMethod.sql complete.';
GO
