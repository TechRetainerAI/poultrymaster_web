-- =============================================================================
-- 020_FixInventoryTablePointers.sql
-- Production data lives in dbo.InventoryItem (singular). Migration 019 mistakenly
-- targeted dbo.InventoryItems (plural) — an orphan that held only stale test rows.
-- After 019 deployed, every API read/write went to plural, hiding the user's real
-- inventory and breaking supplier/cost/etc. on new items.
--
-- This migration:
--   1. ADDs the 019 columns to dbo.InventoryItem (singular) so new fields persist.
--   2. Replaces spInventoryItem_Insert/Update/GetById/GetAll so they read/write
--      from dbo.InventoryItem (singular). The SELECT column order matches the
--      positional reads in InventoryService.cs (positions 0..9 unchanged).
--   3. Leaves the columns added to plural alone (harmless orphan).
--
-- Idempotent. All ADDs are nullable. Safe to re-run.
-- =============================================================================

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 50000, N'Select your application database (not master). Aborting.', 1;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[InventoryItem]') AND type = N'U')
BEGIN
    RAISERROR(N'020: dbo.InventoryItem (singular) not found. Bad target.', 16, 1);
    RETURN;
END
GO

-- 1. Add the 019 columns to singular if missing.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[InventoryItem]') AND name = N'Cost')
BEGIN ALTER TABLE dbo.InventoryItem ADD Cost DECIMAL(18,2) NULL; PRINT '020: Added Cost'; END
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[InventoryItem]') AND name = N'SupplierName')
BEGIN ALTER TABLE dbo.InventoryItem ADD SupplierName NVARCHAR(200) NULL; PRINT '020: Added SupplierName'; END
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[InventoryItem]') AND name = N'PurchaseDate')
BEGIN ALTER TABLE dbo.InventoryItem ADD PurchaseDate DATETIME2 NULL; PRINT '020: Added PurchaseDate'; END
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[InventoryItem]') AND name = N'Notes')
BEGIN ALTER TABLE dbo.InventoryItem ADD Notes NVARCHAR(MAX) NULL; PRINT '020: Added Notes'; END
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[InventoryItem]') AND name = N'Location')
BEGIN ALTER TABLE dbo.InventoryItem ADD Location NVARCHAR(200) NULL; PRINT '020: Added Location'; END
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[InventoryItem]') AND name = N'ExpiryDate')
BEGIN ALTER TABLE dbo.InventoryItem ADD ExpiryDate DATETIME2 NULL; PRINT '020: Added ExpiryDate'; END
GO

-- 2. Replace the sp's. NOTE: positional reads in InventoryService.cs:
--    GetAll  positions: ItemId(0), UserId(1), FarmId(2), ItemName(3), Category(4),
--                       QuantityInStock(5), UnitOfMeasure(6), ReorderLevel(7), SupplierId(8), IsActive(9)
--    GetById positions: FarmId(0), ItemId(1), UserId(2), ItemName(3), Category(4),
--                       QuantityInStock(5), UnitOfMeasure(6), ReorderLevel(7), SupplierId(8), IsActive(9)
--    Extra columns (Cost/SupplierName/etc.) at positions 10+ are read by NAME via
--    HydrateInventoryExtras helper, so their order does not matter.

CREATE OR ALTER PROCEDURE [dbo].[spInventoryItem_Insert]
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450),
    @ItemName NVARCHAR(255),
    @Category NVARCHAR(100),
    @QuantityInStock DECIMAL(18,2),
    @UnitOfMeasure NVARCHAR(50) = NULL,
    @ReorderLevel DECIMAL(18,2) = NULL,
    @SupplierId INT = NULL,
    @IsActive BIT,
    @Cost DECIMAL(18,2) = NULL,
    @SupplierName NVARCHAR(200) = NULL,
    @PurchaseDate DATETIME2 = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @Location NVARCHAR(200) = NULL,
    @ExpiryDate DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.InventoryItem
    (
        UserId, FarmId, ItemName, Category, QuantityInStock, UnitOfMeasure,
        ReorderLevel, SupplierId, IsActive,
        Cost, SupplierName, PurchaseDate, Notes, Location, ExpiryDate,
        CreatedBy, DateCreated
    )
    VALUES
    (
        @UserId, @FarmId, @ItemName, @Category, @QuantityInStock, @UnitOfMeasure,
        @ReorderLevel, @SupplierId, @IsActive,
        @Cost, @SupplierName, @PurchaseDate, @Notes, @Location, @ExpiryDate,
        @UserId, SYSUTCDATETIME()
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spInventoryItem_Update]
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450),
    @ItemId INT,
    @ItemName NVARCHAR(255),
    @Category NVARCHAR(100),
    @QuantityInStock DECIMAL(18,2),
    @UnitOfMeasure NVARCHAR(50) = NULL,
    @ReorderLevel DECIMAL(18,2) = NULL,
    @SupplierId INT = NULL,
    @IsActive BIT,
    @Cost DECIMAL(18,2) = NULL,
    @SupplierName NVARCHAR(200) = NULL,
    @PurchaseDate DATETIME2 = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @Location NVARCHAR(200) = NULL,
    @ExpiryDate DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.InventoryItem
    SET
        ItemName = @ItemName,
        Category = @Category,
        QuantityInStock = @QuantityInStock,
        UnitOfMeasure = @UnitOfMeasure,
        ReorderLevel = @ReorderLevel,
        SupplierId = @SupplierId,
        IsActive = @IsActive,
        Cost = @Cost,
        SupplierName = @SupplierName,
        PurchaseDate = @PurchaseDate,
        Notes = @Notes,
        Location = @Location,
        ExpiryDate = @ExpiryDate,
        UpdatedBy = @UserId,
        DateUpdated = SYSUTCDATETIME()
    WHERE ItemId = @ItemId AND FarmId = @FarmId;
END
GO

-- GetAll: position order matters for InventoryService.cs.
CREATE OR ALTER PROCEDURE [dbo].[spInventoryItem_GetAll]
    @UserId NVARCHAR(450) = NULL,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        ItemId, UserId, FarmId, ItemName, Category, QuantityInStock,
        UnitOfMeasure, ReorderLevel, SupplierId, IsActive,
        Cost, SupplierName, PurchaseDate, Notes, Location, ExpiryDate
    FROM dbo.InventoryItem
    WHERE FarmId = @FarmId
    ORDER BY ItemId DESC;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spInventoryItem_GetById]
    @ItemId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        FarmId, ItemId, UserId, ItemName, Category, QuantityInStock,
        UnitOfMeasure, ReorderLevel, SupplierId, IsActive,
        Cost, SupplierName, PurchaseDate, Notes, Location, ExpiryDate
    FROM dbo.InventoryItem
    WHERE ItemId = @ItemId AND FarmId = @FarmId;
END
GO

PRINT '020_FixInventoryTablePointers: complete.';
GO
