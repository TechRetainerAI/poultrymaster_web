-- =============================================================================
-- 019_AddInventoryFieldsForUI.sql
-- Fix: inventory create/update was silently dropping most form fields because
--      dbo.InventoryItems only had a tiny set of columns. The frontend form
--      collects Cost, Supplier (text name), PurchaseDate, Notes, Location and
--      ExpiryDate — none of which had a home in the DB.
-- This migration adds those columns and updates the spInventoryItem_* procs.
-- All ADDs are nullable; existing rows and existing callers keep working.
-- Idempotent (safe to re-run).
-- =============================================================================

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 50000, N'Select your application database (not master). Aborting.', 1;
END
GO

IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[InventoryItems]') AND type = N'U')
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[InventoryItems]') AND name = N'SupplierId')
    BEGIN ALTER TABLE [dbo].[InventoryItems] ADD [SupplierId] INT NULL; PRINT '019: Added SupplierId'; END
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[InventoryItems]') AND name = N'Cost')
    BEGIN ALTER TABLE [dbo].[InventoryItems] ADD [Cost] DECIMAL(18,2) NULL; PRINT '019: Added Cost'; END
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[InventoryItems]') AND name = N'SupplierName')
    BEGIN ALTER TABLE [dbo].[InventoryItems] ADD [SupplierName] NVARCHAR(200) NULL; PRINT '019: Added SupplierName'; END
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[InventoryItems]') AND name = N'PurchaseDate')
    BEGIN ALTER TABLE [dbo].[InventoryItems] ADD [PurchaseDate] DATETIME2 NULL; PRINT '019: Added PurchaseDate'; END
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[InventoryItems]') AND name = N'Notes')
    BEGIN ALTER TABLE [dbo].[InventoryItems] ADD [Notes] NVARCHAR(MAX) NULL; PRINT '019: Added Notes'; END
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[InventoryItems]') AND name = N'Location')
    BEGIN ALTER TABLE [dbo].[InventoryItems] ADD [Location] NVARCHAR(200) NULL; PRINT '019: Added Location'; END
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[InventoryItems]') AND name = N'ExpiryDate')
    BEGIN ALTER TABLE [dbo].[InventoryItems] ADD [ExpiryDate] DATETIME2 NULL; PRINT '019: Added ExpiryDate'; END
END
ELSE
BEGIN
    RAISERROR(N'019: dbo.InventoryItems not found.', 16, 1);
END
GO

-- Replace the sp's. Keep parameter order: existing params first, new at the end (back-compat for any other callers).
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
    INSERT INTO dbo.InventoryItems
    (
        UserId, FarmId, ItemName, Category, QuantityInStock, UnitOfMeasure,
        ReorderLevel, SupplierId, IsActive,
        Cost, SupplierName, PurchaseDate, Notes, Location, ExpiryDate,
        CreatedDate
    )
    VALUES
    (
        @UserId, @FarmId, @ItemName, @Category, @QuantityInStock, @UnitOfMeasure,
        @ReorderLevel, @SupplierId, @IsActive,
        @Cost, @SupplierName, @PurchaseDate, @Notes, @Location, @ExpiryDate,
        SYSUTCDATETIME()
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
    UPDATE dbo.InventoryItems
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
        UpdatedDate = SYSUTCDATETIME()
    WHERE ItemId = @ItemId AND FarmId = @FarmId;
END
GO

-- IMPORTANT: keep the column ORDER in the SELECT identical to what InventoryService.GetAll/GetById
-- currently expects (positions 0..9). Append the new columns at the end (positions 10..15).
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
    FROM dbo.InventoryItems
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
    FROM dbo.InventoryItems
    WHERE ItemId = @ItemId AND FarmId = @FarmId;
END
GO

PRINT '019_AddInventoryFieldsForUI: complete.';
GO
