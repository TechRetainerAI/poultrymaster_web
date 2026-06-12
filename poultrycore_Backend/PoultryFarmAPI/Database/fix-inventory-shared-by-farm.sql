-- =============================================
-- Fix Inventory Visibility Across Farm Staff
-- Database: poultry2_Prod
-- =============================================
-- Problem:
--   Staff cannot see inventory items created by admin because
--   spInventoryItem_GetAll filters by both UserId and FarmId.
--   Also, production DB uses [dbo].[InventoryItem] (singular table name).
--
-- Fix:
--   Keep @UserId for backward compatibility, but filter by FarmId only.
-- =============================================

USE [poultry2_Prod];
GO

PRINT '========================================';
PRINT 'Fixing InventoryItem GetAll visibility';
PRINT '========================================';
GO

CREATE OR ALTER PROCEDURE [dbo].[spInventoryItem_GetAll]
    @UserId NVARCHAR(450) = NULL, -- accepted but not used for filtering
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        [ItemId],
        [UserId],
        [FarmId],
        [ItemName],
        [Category],
        [QuantityInStock],
        [UnitOfMeasure],
        [ReorderLevel],
        [IsActive]
    FROM [dbo].[InventoryItem]
    WHERE [FarmId] = @FarmId
    ORDER BY [ItemName];
END
GO

PRINT 'spInventoryItem_GetAll updated successfully.';
PRINT 'All users in the same farm can now see shared inventory.';
GO

-- =============================================
-- Fix GetById, Update, Delete for farm-shared access
-- Staff must be able to update/delete items created by admin.
-- =============================================

CREATE OR ALTER PROCEDURE [dbo].[spInventoryItem_GetById]
    @ItemId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        [FarmId],
        [ItemId],
        [UserId],
        [ItemName],
        [Category],
        [QuantityInStock],
        [UnitOfMeasure],
        [ReorderLevel],
        [IsActive]
    FROM [dbo].[InventoryItem]
    WHERE [ItemId] = @ItemId AND [FarmId] = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spInventoryItem_Update]
    @ItemId INT,
    @UserId NVARCHAR(450),  -- accepted but not used for WHERE (backward compat)
    @FarmId NVARCHAR(450),
    @ItemName NVARCHAR(255),
    @Category NVARCHAR(100),
    @QuantityInStock DECIMAL(18,2),
    @UnitOfMeasure NVARCHAR(50) = NULL,
    @ReorderLevel DECIMAL(18,2) = NULL,
    @IsActive BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE [dbo].[InventoryItem]
    SET
        [ItemName] = @ItemName,
        [Category] = @Category,
        [QuantityInStock] = @QuantityInStock,
        [UnitOfMeasure] = ISNULL(@UnitOfMeasure, [UnitOfMeasure]),
        [ReorderLevel] = @ReorderLevel,
        [IsActive] = @IsActive
    WHERE [ItemId] = @ItemId AND [FarmId] = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spInventoryItem_Delete]
    @ItemId INT,
    @UserId NVARCHAR(450) = NULL,  -- accepted but not used for filtering
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM [dbo].[InventoryItem]
    WHERE [ItemId] = @ItemId AND [FarmId] = @FarmId;
END
GO

PRINT 'spInventoryItem_GetById, spInventoryItem_Update, spInventoryItem_Delete updated.';
PRINT 'Staff can now update and delete inventory items within their farm.';
GO

-- Optional quick verification:
-- EXEC [dbo].[spInventoryItem_GetAll] @UserId = NULL, @FarmId = N'your-farm-id';

