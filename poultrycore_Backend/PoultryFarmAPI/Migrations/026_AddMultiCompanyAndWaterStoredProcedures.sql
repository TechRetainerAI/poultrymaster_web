-- =============================================================================
-- Migration 004: Stored procedures for multi-company + water module
-- =============================================================================
-- Run AFTER 003_AddMultiCompanyAndWaterSchema.sql.
--
-- Style matches existing project conventions: spEntity_Action with @FarmId
-- and where useful @UserId parameters. All procs are CREATE OR ALTER so the
-- script is safe to re-run.
-- =============================================================================

SET NOCOUNT ON;
-- Procs that touch dbo.WaterSaleItems (computed column LineTotal PERSISTED)
-- must be created under QUOTED_IDENTIFIER ON. Setting at the session level
-- here so every CREATE OR ALTER PROCEDURE below inherits it.
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- Companies / Farms procs
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spCompany_Create
    @FarmId       NVARCHAR(450),
    @Name         NVARCHAR(255),
    @Type         NVARCHAR(50),
    @OwnerUserId  NVARCHAR(450),
    @Email        NVARCHAR(255) = NULL,
    @PhoneNumber  NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.Farms (FarmId, Name, Type, OwnerUserId, Email, PhoneNumber, CreatedAt)
    VALUES (@FarmId, @Name, @Type, @OwnerUserId, @Email, @PhoneNumber, SYSUTCDATETIME());

    -- Owner is automatically a member with Admin role.
    IF NOT EXISTS (SELECT 1 FROM dbo.UserFarms WHERE UserId = @OwnerUserId AND FarmId = @FarmId)
    BEGIN
        INSERT INTO dbo.UserFarms (UserId, FarmId, Role)
        VALUES (@OwnerUserId, @FarmId, 'Admin');
    END

    SELECT FarmId, Name, Type, OwnerUserId, Email, PhoneNumber, CreatedAt, UpdatedAt
    FROM   dbo.Farms WHERE FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spCompany_GetByUserId
    @UserId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT f.FarmId, f.Name, f.Type, f.OwnerUserId, f.Email, f.PhoneNumber,
           f.CreatedAt, f.UpdatedAt, uf.Role
    FROM   dbo.Farms f
    INNER JOIN dbo.UserFarms uf ON uf.FarmId = f.FarmId
    WHERE  uf.UserId = @UserId
    ORDER  BY f.Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.spCompany_GetById
    @FarmId  NVARCHAR(450),
    @UserId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1 f.FarmId, f.Name, f.Type, f.OwnerUserId, f.Email, f.PhoneNumber,
                 f.CreatedAt, f.UpdatedAt, uf.Role
    FROM   dbo.Farms f
    INNER JOIN dbo.UserFarms uf ON uf.FarmId = f.FarmId
    WHERE  f.FarmId = @FarmId AND uf.UserId = @UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spCompany_Update
    @FarmId       NVARCHAR(450),
    @Name         NVARCHAR(255),
    @Email        NVARCHAR(255) = NULL,
    @PhoneNumber  NVARCHAR(50)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.Farms
    SET    Name = @Name, Email = @Email, PhoneNumber = @PhoneNumber, UpdatedAt = SYSUTCDATETIME()
    WHERE  FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spUserFarm_IsMember
    @UserId  NVARCHAR(450),
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CAST(CASE WHEN EXISTS (
        SELECT 1 FROM dbo.UserFarms WHERE UserId = @UserId AND FarmId = @FarmId
    ) THEN 1 ELSE 0 END AS BIT) AS IsMember;
END
GO


-- =============================================================================
-- WaterProducts procs
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterProduct_Insert
    @FarmId     NVARCHAR(450),
    @Name       NVARCHAR(150),
    @Sku        NVARCHAR(60)  = NULL,
    @SizeMl     INT           = NULL,
    @Unit       NVARCHAR(30)  = NULL,
    @UnitPrice  DECIMAL(12,2),
    @IsActive   BIT           = 1,
    @Notes      NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterProducts (FarmId, Name, Sku, SizeMl, Unit, UnitPrice, IsActive, Notes)
    VALUES (@FarmId, @Name, @Sku, @SizeMl, @Unit, @UnitPrice, @IsActive, @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProduct_Update
    @WaterProductId INT,
    @FarmId         NVARCHAR(450),
    @Name           NVARCHAR(150),
    @Sku            NVARCHAR(60)  = NULL,
    @SizeMl         INT           = NULL,
    @Unit           NVARCHAR(30)  = NULL,
    @UnitPrice      DECIMAL(12,2),
    @IsActive       BIT,
    @Notes          NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterProducts
    SET Name = @Name, Sku = @Sku, SizeMl = @SizeMl, Unit = @Unit,
        UnitPrice = @UnitPrice, IsActive = @IsActive, Notes = @Notes,
        UpdatedDate = SYSUTCDATETIME()
    WHERE WaterProductId = @WaterProductId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProduct_GetById
    @WaterProductId INT,
    @FarmId         NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.WaterProductId, p.FarmId, p.Name, p.Sku, p.SizeMl, p.Unit,
           p.UnitPrice, p.IsActive, p.Notes, p.CreatedDate, p.UpdatedDate,
           ISNULL((SELECT SUM(Quantity) FROM dbo.WaterStockTransactions
                   WHERE  WaterProductId = p.WaterProductId), 0) AS StockOnHand
    FROM dbo.WaterProducts p
    WHERE p.WaterProductId = @WaterProductId AND p.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProduct_GetAll
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.WaterProductId, p.FarmId, p.Name, p.Sku, p.SizeMl, p.Unit,
           p.UnitPrice, p.IsActive, p.Notes, p.CreatedDate, p.UpdatedDate,
           ISNULL((SELECT SUM(Quantity) FROM dbo.WaterStockTransactions
                   WHERE  WaterProductId = p.WaterProductId), 0) AS StockOnHand
    FROM dbo.WaterProducts p
    WHERE p.FarmId = @FarmId
    ORDER BY p.IsActive DESC, p.Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProduct_Delete
    @WaterProductId INT,
    @FarmId         NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    -- Soft-delete if the product has any history; otherwise hard-delete.
    IF EXISTS (SELECT 1 FROM dbo.WaterStockTransactions WHERE WaterProductId = @WaterProductId)
        OR EXISTS (SELECT 1 FROM dbo.WaterSaleItems WHERE WaterProductId = @WaterProductId)
    BEGIN
        UPDATE dbo.WaterProducts
        SET IsActive = 0, UpdatedDate = SYSUTCDATETIME()
        WHERE WaterProductId = @WaterProductId AND FarmId = @FarmId;
    END
    ELSE
    BEGIN
        DELETE FROM dbo.WaterProducts WHERE WaterProductId = @WaterProductId AND FarmId = @FarmId;
    END
END
GO


-- =============================================================================
-- WaterCustomers procs
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterCustomer_Insert
    @FarmId        NVARCHAR(450),
    @Name          NVARCHAR(150),
    @ContactPhone  NVARCHAR(50)  = NULL,
    @ContactEmail  NVARCHAR(150) = NULL,
    @Address       NVARCHAR(300) = NULL,
    @City          NVARCHAR(100) = NULL,
    @Notes         NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterCustomers (FarmId, Name, ContactPhone, ContactEmail, Address, City, Notes)
    VALUES (@FarmId, @Name, @ContactPhone, @ContactEmail, @Address, @City, @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterCustomer_Update
    @WaterCustomerId INT,
    @FarmId          NVARCHAR(450),
    @Name            NVARCHAR(150),
    @ContactPhone    NVARCHAR(50)  = NULL,
    @ContactEmail    NVARCHAR(150) = NULL,
    @Address         NVARCHAR(300) = NULL,
    @City            NVARCHAR(100) = NULL,
    @Notes           NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterCustomers
    SET Name = @Name, ContactPhone = @ContactPhone, ContactEmail = @ContactEmail,
        Address = @Address, City = @City, Notes = @Notes, UpdatedDate = SYSUTCDATETIME()
    WHERE WaterCustomerId = @WaterCustomerId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterCustomer_GetById
    @WaterCustomerId INT,
    @FarmId          NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT WaterCustomerId, FarmId, Name, ContactPhone, ContactEmail, Address, City, Notes,
           CreatedDate, UpdatedDate
    FROM dbo.WaterCustomers
    WHERE WaterCustomerId = @WaterCustomerId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterCustomer_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT WaterCustomerId, FarmId, Name, ContactPhone, ContactEmail, Address, City, Notes,
           CreatedDate, UpdatedDate,
           ISNULL((SELECT SUM(TotalAmount - AmountPaid) FROM dbo.WaterSales
                   WHERE WaterCustomerId = wc.WaterCustomerId AND Status <> 'Cancelled'), 0) AS OutstandingBalance
    FROM dbo.WaterCustomers wc
    WHERE FarmId = @FarmId
    ORDER BY Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterCustomer_Delete
    @WaterCustomerId INT,
    @FarmId          NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.WaterCustomers
    WHERE WaterCustomerId = @WaterCustomerId AND FarmId = @FarmId
      AND NOT EXISTS (SELECT 1 FROM dbo.WaterSales WHERE WaterCustomerId = @WaterCustomerId);
END
GO


-- =============================================================================
-- WaterStock procs
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterStock_AddTransaction
    @FarmId          NVARCHAR(450),
    @WaterProductId  INT,
    @TxnType         NVARCHAR(30),     -- 'Restock' | 'Adjust' | 'Sale' | 'Return'
    @Quantity        INT,              -- signed
    @UnitCost        DECIMAL(12,2) = NULL,
    @RelatedSaleId   INT = NULL,
    @Note            NVARCHAR(300) = NULL,
    @CreatedBy       NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Sanity: the product must belong to this farm.
    IF NOT EXISTS (SELECT 1 FROM dbo.WaterProducts WHERE WaterProductId = @WaterProductId AND FarmId = @FarmId)
    BEGIN
        RAISERROR('Product does not belong to this farm.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.WaterStockTransactions
        (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
    VALUES (@FarmId, @WaterProductId, @TxnType, @Quantity, @UnitCost, @RelatedSaleId, @Note, @CreatedBy);

    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterStock_GetTransactions
    @FarmId          NVARCHAR(450),
    @WaterProductId  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT st.StockTxnId, st.FarmId, st.WaterProductId, p.Name AS ProductName,
           st.TxnType, st.Quantity, st.UnitCost, st.RelatedSaleId,
           st.Note, st.CreatedDate, st.CreatedBy
    FROM dbo.WaterStockTransactions st
    INNER JOIN dbo.WaterProducts p ON p.WaterProductId = st.WaterProductId
    WHERE st.FarmId = @FarmId
      AND (@WaterProductId IS NULL OR st.WaterProductId = @WaterProductId)
    ORDER BY st.CreatedDate DESC;
END
GO


-- =============================================================================
-- WaterSales procs (header + items + auto-stock-out)
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterSale_Create
    @FarmId           NVARCHAR(450),
    @WaterCustomerId  INT = NULL,
    @SaleDate         DATETIME2 = NULL,
    @Notes            NVARCHAR(500) = NULL,
    @CreatedBy        NVARCHAR(450) = NULL,
    @ItemsJson        NVARCHAR(MAX)   -- [{"WaterProductId":1,"Quantity":10,"UnitPrice":2.50}, ...]
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @SaleDate IS NULL SET @SaleDate = SYSUTCDATETIME();

    BEGIN TRAN;

    DECLARE @SaleId INT;
    INSERT INTO dbo.WaterSales
        (FarmId, WaterCustomerId, SaleDate, TotalAmount, AmountPaid, Status, Notes, CreatedBy)
    VALUES (@FarmId, @WaterCustomerId, @SaleDate, 0, 0, 'Pending', @Notes, @CreatedBy);
    SET @SaleId = SCOPE_IDENTITY();

    -- Parse items from JSON.
    DECLARE @Items TABLE (WaterProductId INT, Quantity INT, UnitPrice DECIMAL(12,2));
    INSERT INTO @Items (WaterProductId, Quantity, UnitPrice)
    SELECT WaterProductId, Quantity, UnitPrice
    FROM OPENJSON(@ItemsJson)
    WITH (
        WaterProductId INT '$.WaterProductId',
        Quantity       INT '$.Quantity',
        UnitPrice      DECIMAL(12,2) '$.UnitPrice'
    );

    -- Reject if any product doesn't belong to this farm.
    IF EXISTS (
        SELECT 1 FROM @Items i
        LEFT JOIN dbo.WaterProducts p
               ON p.WaterProductId = i.WaterProductId AND p.FarmId = @FarmId
        WHERE p.WaterProductId IS NULL
    )
    BEGIN
        ROLLBACK;
        RAISERROR('One or more products do not belong to this farm.', 16, 1);
        RETURN;
    END

    -- Insert line items.
    INSERT INTO dbo.WaterSaleItems (WaterSaleId, WaterProductId, Quantity, UnitPrice)
    SELECT @SaleId, WaterProductId, Quantity, UnitPrice FROM @Items;

    -- Write a stock-out txn per item (negative quantity).
    INSERT INTO dbo.WaterStockTransactions
        (FarmId, WaterProductId, TxnType, Quantity, RelatedSaleId, Note, CreatedBy)
    SELECT @FarmId, WaterProductId, 'Sale', -Quantity, @SaleId,
           CONCAT('Sale #', @SaleId), @CreatedBy
    FROM @Items;

    -- Update header total.
    UPDATE dbo.WaterSales
    SET TotalAmount = ISNULL((SELECT SUM(LineTotal) FROM dbo.WaterSaleItems WHERE WaterSaleId = @SaleId), 0)
    WHERE WaterSaleId = @SaleId;

    COMMIT;

    SELECT @SaleId AS WaterSaleId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterSale_GetById
    @WaterSaleId INT,
    @FarmId      NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.WaterSaleId, s.FarmId, s.WaterCustomerId, c.Name AS CustomerName,
           s.SaleDate, s.TotalAmount, s.AmountPaid,
           (s.TotalAmount - s.AmountPaid) AS Balance,
           s.Status, s.Notes, s.CreatedDate, s.CreatedBy, s.UpdatedDate
    FROM dbo.WaterSales s
    LEFT JOIN dbo.WaterCustomers c ON c.WaterCustomerId = s.WaterCustomerId
    WHERE s.WaterSaleId = @WaterSaleId AND s.FarmId = @FarmId;

    SELECT i.WaterSaleItemId, i.WaterSaleId, i.WaterProductId, p.Name AS ProductName,
           i.Quantity, i.UnitPrice, i.LineTotal
    FROM dbo.WaterSaleItems i
    INNER JOIN dbo.WaterProducts p ON p.WaterProductId = i.WaterProductId
    WHERE i.WaterSaleId = @WaterSaleId
    ORDER BY i.WaterSaleItemId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterSale_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.WaterSaleId, s.FarmId, s.WaterCustomerId, c.Name AS CustomerName,
           s.SaleDate, s.TotalAmount, s.AmountPaid,
           (s.TotalAmount - s.AmountPaid) AS Balance,
           s.Status, s.Notes, s.CreatedDate, s.CreatedBy, s.UpdatedDate
    FROM dbo.WaterSales s
    LEFT JOIN dbo.WaterCustomers c ON c.WaterCustomerId = s.WaterCustomerId
    WHERE s.FarmId = @FarmId
    ORDER BY s.SaleDate DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterSale_Cancel
    @WaterSaleId INT,
    @FarmId      NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;

    -- Reverse stock-out txns by inserting compensating returns.
    INSERT INTO dbo.WaterStockTransactions (FarmId, WaterProductId, TxnType, Quantity, RelatedSaleId, Note)
    SELECT @FarmId, WaterProductId, 'Return', -Quantity, @WaterSaleId,
           CONCAT('Cancellation of sale #', @WaterSaleId)
    FROM dbo.WaterStockTransactions
    WHERE RelatedSaleId = @WaterSaleId AND FarmId = @FarmId AND TxnType = 'Sale';

    UPDATE dbo.WaterSales
    SET Status = 'Cancelled', UpdatedDate = SYSUTCDATETIME()
    WHERE WaterSaleId = @WaterSaleId AND FarmId = @FarmId;

    COMMIT;
END
GO


-- =============================================================================
-- WaterPayments procs
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterPayment_Record
    @FarmId        NVARCHAR(450),
    @WaterSaleId   INT,
    @Amount        DECIMAL(12,2),
    @PaymentMethod NVARCHAR(40)  = NULL,
    @PaymentDate   DATETIME2     = NULL,
    @Reference     NVARCHAR(120) = NULL,
    @Note          NVARCHAR(300) = NULL,
    @CreatedBy     NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @PaymentDate IS NULL SET @PaymentDate = SYSUTCDATETIME();

    -- Sale must belong to farm.
    IF NOT EXISTS (SELECT 1 FROM dbo.WaterSales WHERE WaterSaleId = @WaterSaleId AND FarmId = @FarmId)
    BEGIN
        RAISERROR('Sale does not belong to this farm.', 16, 1);
        RETURN;
    END

    BEGIN TRAN;

    INSERT INTO dbo.WaterPayments
        (FarmId, WaterSaleId, Amount, PaymentMethod, PaymentDate, Reference, Note, CreatedBy)
    VALUES (@FarmId, @WaterSaleId, @Amount, @PaymentMethod, @PaymentDate, @Reference, @Note, @CreatedBy);

    DECLARE @PaymentId INT = SCOPE_IDENTITY();

    -- Recompute AmountPaid and Status on the sale.
    UPDATE s
    SET    AmountPaid = ISNULL((SELECT SUM(Amount) FROM dbo.WaterPayments
                                WHERE WaterSaleId = s.WaterSaleId), 0),
           Status     = CASE
                          WHEN s.Status = 'Cancelled' THEN 'Cancelled'
                          WHEN ISNULL((SELECT SUM(Amount) FROM dbo.WaterPayments
                                       WHERE WaterSaleId = s.WaterSaleId), 0) >= s.TotalAmount
                               THEN 'Paid'
                          WHEN ISNULL((SELECT SUM(Amount) FROM dbo.WaterPayments
                                       WHERE WaterSaleId = s.WaterSaleId), 0) > 0
                               THEN 'PartiallyPaid'
                          ELSE 'Pending'
                        END,
           UpdatedDate = SYSUTCDATETIME()
    FROM dbo.WaterSales s
    WHERE s.WaterSaleId = @WaterSaleId;

    COMMIT;

    SELECT @PaymentId AS WaterPaymentId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterPayment_GetBySale
    @WaterSaleId INT,
    @FarmId      NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT WaterPaymentId, FarmId, WaterSaleId, Amount, PaymentMethod,
           PaymentDate, Reference, Note, CreatedDate, CreatedBy
    FROM dbo.WaterPayments
    WHERE WaterSaleId = @WaterSaleId AND FarmId = @FarmId
    ORDER BY PaymentDate DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterPayment_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.WaterPaymentId, p.FarmId, p.WaterSaleId, p.Amount, p.PaymentMethod,
           p.PaymentDate, p.Reference, p.Note, p.CreatedDate, p.CreatedBy,
           c.Name AS CustomerName
    FROM dbo.WaterPayments p
    INNER JOIN dbo.WaterSales s ON s.WaterSaleId = p.WaterSaleId
    LEFT  JOIN dbo.WaterCustomers c ON c.WaterCustomerId = s.WaterCustomerId
    WHERE p.FarmId = @FarmId
    ORDER BY p.PaymentDate DESC;
END
GO


-- =============================================================================
-- Water dashboard summary (one round-trip for the dashboard page)
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterDashboard_Summary
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TodayStart DATETIME2 = CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATETIME2);
    DECLARE @MonthStart DATETIME2 = DATEFROMPARTS(YEAR(SYSUTCDATETIME()), MONTH(SYSUTCDATETIME()), 1);

    SELECT
        (SELECT COUNT(*) FROM dbo.WaterProducts WHERE FarmId = @FarmId AND IsActive = 1)       AS ActiveProducts,
        (SELECT COUNT(*) FROM dbo.WaterCustomers WHERE FarmId = @FarmId)                       AS TotalCustomers,
        ISNULL((SELECT SUM(Quantity) FROM dbo.WaterStockTransactions WHERE FarmId = @FarmId), 0) AS TotalStockOnHand,
        ISNULL((SELECT SUM(TotalAmount) FROM dbo.WaterSales
                WHERE FarmId = @FarmId AND Status <> 'Cancelled' AND SaleDate >= @TodayStart), 0) AS SalesToday,
        ISNULL((SELECT SUM(TotalAmount) FROM dbo.WaterSales
                WHERE FarmId = @FarmId AND Status <> 'Cancelled' AND SaleDate >= @MonthStart), 0) AS SalesThisMonth,
        ISNULL((SELECT SUM(TotalAmount - AmountPaid) FROM dbo.WaterSales
                WHERE FarmId = @FarmId AND Status NOT IN ('Cancelled','Paid')), 0)                AS OutstandingReceivables;
END
GO

PRINT '004_AddMultiCompanyAndWaterStoredProcedures.sql complete.';
GO
