-- Add Paid flag to Sale (singular) and refresh spSale_* procedures.
-- Your database uses dbo.Sale — not dbo.Sales. An earlier version of this
-- script targeted dbo.Sales, so Paid was never added and procs could read
-- the wrong object. This file is corrected to dbo.Sale only.
--
-- Purpose:
--   - Allow recording sales that are not yet paid.
--   - Keep Paid default true for existing behavior.
--   - Enable cash module to separate Paid cash-in from Owed.

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Sale]') AND type in (N'U'))
BEGIN
    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[Sale]') AND name = 'Paid')
    BEGIN
        ALTER TABLE [dbo].[Sale] ADD [Paid] BIT NOT NULL CONSTRAINT [DF_Sale_Paid] DEFAULT(1);
        PRINT 'Added Paid column to Sale';
    END
    ELSE
        PRINT 'Paid column already exists on Sale';
END
ELSE
BEGIN
    PRINT 'ERROR: dbo.Sale table not found. Create or rename your sales table before running this script.';
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSale_Insert]
    @UserId NVARCHAR(100),
    @FarmId NVARCHAR(100),
    @SaleDate DATETIME2,
    @Product NVARCHAR(200),
    @Quantity DECIMAL(18,2),
    @UnitPrice DECIMAL(18,2),
    @TotalAmount DECIMAL(18,2),
    @PaymentMethod NVARCHAR(100) = NULL,
    @CustomerName NVARCHAR(200) = NULL,
    @FlockId INT = NULL,
    @SaleDescription NVARCHAR(MAX) = NULL,
    @Paid BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [dbo].[Sale]
    (
        UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount,
        PaymentMethod, CustomerName, FlockId, SaleDescription, Paid, CreatedDate
    )
    VALUES
    (
        @UserId, @FarmId, @SaleDate, @Product, @Quantity, @UnitPrice, @TotalAmount,
        @PaymentMethod, @CustomerName, @FlockId, @SaleDescription, ISNULL(@Paid, 1), SYSUTCDATETIME()
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSale_Update]
    @UserId NVARCHAR(100),
    @FarmId NVARCHAR(100),
    @SaleId INT,
    @SaleDate DATETIME2,
    @Product NVARCHAR(200),
    @Quantity DECIMAL(18,2),
    @UnitPrice DECIMAL(18,2),
    @TotalAmount DECIMAL(18,2),
    @PaymentMethod NVARCHAR(100) = NULL,
    @CustomerName NVARCHAR(200) = NULL,
    @FlockId INT = NULL,
    @SaleDescription NVARCHAR(MAX) = NULL,
    @Paid BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE [dbo].[Sale]
    SET
        SaleDate = @SaleDate,
        Product = @Product,
        Quantity = @Quantity,
        UnitPrice = @UnitPrice,
        TotalAmount = @TotalAmount,
        PaymentMethod = @PaymentMethod,
        CustomerName = @CustomerName,
        FlockId = @FlockId,
        SaleDescription = @SaleDescription,
        Paid = ISNULL(@Paid, 1)
    WHERE SaleId = @SaleId
      AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSale_GetById]
    @SaleId INT,
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        SaleId, UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount,
        PaymentMethod, CustomerName, FlockId, SaleDescription, ISNULL(Paid, 1) AS Paid, CreatedDate
    FROM [dbo].[Sale]
    WHERE SaleId = @SaleId
      AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSale_GetAll]
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        SaleId, UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount,
        PaymentMethod, CustomerName, FlockId, SaleDescription, ISNULL(Paid, 1) AS Paid, CreatedDate
    FROM [dbo].[Sale]
    WHERE FarmId = @FarmId
    ORDER BY SaleDate DESC, CreatedDate DESC;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSale_GetByFlock]
    @FlockId INT,
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        SaleId, UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount,
        PaymentMethod, CustomerName, FlockId, SaleDescription, ISNULL(Paid, 1) AS Paid, CreatedDate
    FROM [dbo].[Sale]
    WHERE FarmId = @FarmId
      AND FlockId = @FlockId
    ORDER BY SaleDate DESC, CreatedDate DESC;
END
GO

PRINT '005_AddPaidToSales completed (dbo.Sale).';
GO
