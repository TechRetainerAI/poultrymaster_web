-- =============================================
-- 011_CreateInventoryItemModule.sql
-- Creates dbo.InventoryItem + spInventoryItem_* procedures
-- required by PoultryFarmAPI InventoryService / InventoryItemController.
--
-- BEFORE YOU RUN:
--   1) In SSMS, select your APPLICATION database in the toolbar (NOT "master").
--   2) Or uncomment and set the name from your connection string, then execute:
--
--      USE [ReplaceWithYourDatabaseName];
--      GO
--
-- If you see "permission denied in database 'master'", you are still on master.
-- Safe to re-run: skips table create if it already exists; procedures use CREATE OR ALTER.
-- =============================================

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 50000,
        N'Wrong database: SSMS is using a system database (e.g. master). Select your farm/app database from the dropdown, or run USE [YourDbName]; GO, then execute this script again.',
        1;
END
GO

SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.InventoryItem', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[InventoryItem] (
        [ItemId]            INT IDENTITY(1, 1) NOT NULL,
        [UserId]            NVARCHAR(450) NOT NULL,
        [FarmId]            NVARCHAR(450) NOT NULL,
        [ItemName]          NVARCHAR(255) NOT NULL,
        [Category]          NVARCHAR(100) NOT NULL CONSTRAINT [DF_InventoryItem_Category] DEFAULT (N''),
        [QuantityInStock]   DECIMAL(18, 2) NOT NULL CONSTRAINT [DF_InventoryItem_Qty] DEFAULT ((0)),
        [UnitOfMeasure]     NVARCHAR(50) NULL,
        [ReorderLevel]      DECIMAL(18, 2) NULL,
        [IsActive]          BIT NOT NULL CONSTRAINT [DF_InventoryItem_IsActive] DEFAULT ((1)),
        CONSTRAINT [PK_InventoryItem] PRIMARY KEY CLUSTERED ([ItemId] ASC)
    );

    CREATE NONCLUSTERED INDEX [IX_InventoryItem_FarmId]
        ON [dbo].[InventoryItem] ([FarmId] ASC);

    CREATE NONCLUSTERED INDEX [IX_InventoryItem_FarmId_ItemName]
        ON [dbo].[InventoryItem] ([FarmId] ASC, [ItemName] ASC);

    PRINT N'Created dbo.InventoryItem.';
END
ELSE
    PRINT N'dbo.InventoryItem already exists — skipped create.';
GO

CREATE OR ALTER PROCEDURE [dbo].[spInventoryItem_Insert]
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450),
    @ItemName NVARCHAR(255),
    @Category NVARCHAR(100),
    @QuantityInStock DECIMAL(18, 2),
    @UnitOfMeasure NVARCHAR(50) = NULL,
    @ReorderLevel DECIMAL(18, 2) = NULL,
    @IsActive BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [dbo].[InventoryItem] (
        [UserId],
        [FarmId],
        [ItemName],
        [Category],
        [QuantityInStock],
        [UnitOfMeasure],
        [ReorderLevel],
        [IsActive]
    )
    VALUES (
        @UserId,
        @FarmId,
        @ItemName,
        @Category,
        @QuantityInStock,
        @UnitOfMeasure,
        @ReorderLevel,
        @IsActive
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewItemId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spInventoryItem_GetAll]
    @UserId NVARCHAR(450) = NULL,
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
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450),
    @ItemName NVARCHAR(255),
    @Category NVARCHAR(100),
    @QuantityInStock DECIMAL(18, 2),
    @UnitOfMeasure NVARCHAR(50) = NULL,
    @ReorderLevel DECIMAL(18, 2) = NULL,
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
    @UserId NVARCHAR(450) = NULL,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM [dbo].[InventoryItem]
    WHERE [ItemId] = @ItemId AND [FarmId] = @FarmId;
END
GO

PRINT N'011_CreateInventoryItemModule: procedures spInventoryItem_* are ready.';
GO
