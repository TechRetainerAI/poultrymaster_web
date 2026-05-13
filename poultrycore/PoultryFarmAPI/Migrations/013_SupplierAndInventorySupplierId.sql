-- 013_SupplierAndInventorySupplierId.sql — suppliers (like customers) + optional SupplierId on inventory
IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 50000, N'Select your application database before running this script.', 1;
END
GO

SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.Supplier', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[Supplier] (
        [SupplierId]   INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
        [UserId]       NVARCHAR(450) NOT NULL,
        [FarmId]       NVARCHAR(450) NOT NULL,
        [Name]         NVARCHAR(200) NOT NULL,
        [ContactEmail] NVARCHAR(256) NULL,
        [ContactPhone] NVARCHAR(50) NULL,
        [Address]      NVARCHAR(500) NULL,
        [City]         NVARCHAR(100) NULL,
        [CreatedDate]  DATETIME2 NOT NULL CONSTRAINT [DF_Supplier_Created] DEFAULT (SYSUTCDATETIME())
    );
    CREATE NONCLUSTERED INDEX [IX_Supplier_FarmId] ON [dbo].[Supplier]([FarmId]);
    PRINT N'Created dbo.Supplier.';
END
GO

IF COL_LENGTH(N'dbo.InventoryItem', N'SupplierId') IS NULL
BEGIN
    ALTER TABLE [dbo].[InventoryItem] ADD [SupplierId] INT NULL;
    PRINT N'Added InventoryItem.SupplierId.';
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSupplier_Insert]
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450),
    @Name NVARCHAR(200),
    @ContactEmail NVARCHAR(256) = NULL,
    @ContactPhone NVARCHAR(50) = NULL,
    @Address NVARCHAR(500) = NULL,
    @City NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [dbo].[Supplier] ([UserId], [FarmId], [Name], [ContactEmail], [ContactPhone], [Address], [City])
    VALUES (@UserId, @FarmId, @Name, @ContactEmail, @ContactPhone, @Address, @City);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSupplier_Update]
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450),
    @SupplierId INT,
    @Name NVARCHAR(200),
    @ContactEmail NVARCHAR(256) = NULL,
    @ContactPhone NVARCHAR(50) = NULL,
    @Address NVARCHAR(500) = NULL,
    @City NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE [dbo].[Supplier]
    SET [Name] = @Name,
        [ContactEmail] = @ContactEmail,
        [ContactPhone] = @ContactPhone,
        [Address] = @Address,
        [City] = @City
    WHERE [SupplierId] = @SupplierId AND [FarmId] = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSupplier_GetById]
    @SupplierId INT,
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT [SupplierId], [FarmId], [UserId], [Name], [ContactEmail], [ContactPhone], [Address], [City], [CreatedDate]
    FROM [dbo].[Supplier]
    WHERE [SupplierId] = @SupplierId AND [FarmId] = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSupplier_GetAll]
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT [SupplierId], [FarmId], [UserId], [Name], [ContactEmail], [ContactPhone], [Address], [City], [CreatedDate]
    FROM [dbo].[Supplier]
    WHERE [FarmId] = @FarmId
    ORDER BY [Name];
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSupplier_Delete]
    @SupplierId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM [dbo].[Supplier] WHERE [SupplierId] = @SupplierId AND [FarmId] = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spInventoryItem_Insert]
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450),
    @ItemName NVARCHAR(255),
    @Category NVARCHAR(100),
    @QuantityInStock DECIMAL(18, 2),
    @UnitOfMeasure NVARCHAR(50) = NULL,
    @ReorderLevel DECIMAL(18, 2) = NULL,
    @SupplierId INT = NULL,
    @IsActive BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [dbo].[InventoryItem] (
        [UserId], [FarmId], [ItemName], [Category], [QuantityInStock], [UnitOfMeasure], [ReorderLevel], [SupplierId], [IsActive]
    )
    VALUES (@UserId, @FarmId, @ItemName, @Category, @QuantityInStock, @UnitOfMeasure, @ReorderLevel, @SupplierId, @IsActive);
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
        [ItemId], [UserId], [FarmId], [ItemName], [Category], [QuantityInStock], [UnitOfMeasure], [ReorderLevel], [SupplierId], [IsActive]
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
        [FarmId], [ItemId], [UserId], [ItemName], [Category], [QuantityInStock], [UnitOfMeasure], [ReorderLevel], [SupplierId], [IsActive]
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
    @SupplierId INT = NULL,
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
        [SupplierId] = @SupplierId,
        [IsActive] = @IsActive
    WHERE [ItemId] = @ItemId AND [FarmId] = @FarmId;
END
GO

PRINT N'013_SupplierAndInventorySupplierId: complete.';
GO
