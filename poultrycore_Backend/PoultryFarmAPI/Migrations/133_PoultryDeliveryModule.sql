-- =============================================================================
-- Migration 133: Poultry egg Delivery module (doc section 9)
-- =============================================================================
-- One PoultryDeliveries record: Load -> (record return) -> Reconcile.
--   Load     : reduce egg stock (PoultryStockTransaction 'Delivery Load' -qty)
--   Reconcile: returned +stock ('Delivery Return'); broken+short -> production
--              loss; sold -> Sale; delivery expenses -> Expense; cash -> CashAdjustment.
--              Sold eggs are NOT deducted again (already out at load).
--   Reverse  : undo sale/expense/cash/return-stock/loss; back to Loaded.
-- Drivers/vehicles/routes are free text in this v1. Additive + idempotent.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.PoultryDeliveries', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryDeliveries (
        PoultryDeliveryId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId           NVARCHAR(450) NOT NULL,
        DeliveryDate     DATETIME2     NOT NULL CONSTRAINT DF_PoultryDeliveries_Date DEFAULT (SYSUTCDATETIME()),
        DriverName       NVARCHAR(150) NULL,
        VehicleName      NVARCHAR(150) NULL,
        Route            NVARCHAR(150) NULL,
        PoultryProductId INT           NOT NULL,
        QuantityLoaded   DECIMAL(14,3) NOT NULL CONSTRAINT DF_PoultryDeliveries_Loaded DEFAULT (0),
        Unit             NVARCHAR(30)  NULL,
        UnitPrice        DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryDeliveries_Price DEFAULT (0),
        QuantitySold     DECIMAL(14,3) NOT NULL CONSTRAINT DF_PoultryDeliveries_Sold DEFAULT (0),
        QuantityReturned DECIMAL(14,3) NOT NULL CONSTRAINT DF_PoultryDeliveries_Ret DEFAULT (0),
        QuantityBroken   DECIMAL(14,3) NOT NULL CONSTRAINT DF_PoultryDeliveries_Brk DEFAULT (0),
        QuantityShort    DECIMAL(14,3) NOT NULL CONSTRAINT DF_PoultryDeliveries_Sh DEFAULT (0),
        CashCollected    DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryDeliveries_Cash DEFAULT (0),
        CreditSales      DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryDeliveries_Cred DEFAULT (0),
        DeliveryExpenses DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryDeliveries_Exp DEFAULT (0),
        Status           NVARCHAR(20)  NOT NULL CONSTRAINT DF_PoultryDeliveries_Status DEFAULT ('Loaded'), -- Loaded | Reconciled | Cancelled
        LinkedSaleId     INT NULL, LinkedExpenseId INT NULL, LinkedCashAdjId INT NULL,
        Notes            NVARCHAR(500) NULL,
        CreatedBy        NVARCHAR(450) NULL,
        CreatedAt        DATETIME2     NOT NULL CONSTRAINT DF_PoultryDeliveries_Created DEFAULT (SYSUTCDATETIME()),
        UpdatedAt        DATETIME2     NULL,
        ReconciledBy     NVARCHAR(450) NULL,
        ReconciledAt     DATETIME2     NULL,
        CONSTRAINT FK_PoultryDeliveries_Product FOREIGN KEY (PoultryProductId) REFERENCES dbo.PoultryProducts (PoultryProductId)
    );
    CREATE INDEX IX_PoultryDeliveries_FarmId ON dbo.PoultryDeliveries (FarmId);
    CREATE INDEX IX_PoultryDeliveries_Status ON dbo.PoultryDeliveries (Status);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDelivery_GetAll
    @FarmId NVARCHAR(450), @Status NVARCHAR(20) = NULL, @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.*, p.Name AS ProductName,
           CAST(d.QuantitySold * d.UnitPrice AS DECIMAL(14,2)) AS TotalSales,
           CAST(d.CashCollected + d.CreditSales - (d.QuantitySold * d.UnitPrice) AS DECIMAL(14,2)) AS CashVariance
    FROM   dbo.PoultryDeliveries d
    INNER  JOIN dbo.PoultryProducts p ON p.PoultryProductId = d.PoultryProductId
    WHERE  d.FarmId = @FarmId
       AND (@Status IS NULL OR d.Status = @Status)
       AND (@FromDate IS NULL OR CAST(d.DeliveryDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(d.DeliveryDate AS DATE) <= @ToDate)
    ORDER  BY d.DeliveryDate DESC, d.PoultryDeliveryId DESC;
END
GO

-- Load eggs onto a vehicle: reduce egg stock immediately.
CREATE OR ALTER PROCEDURE dbo.spPoultryDelivery_Load
    @FarmId NVARCHAR(450), @DeliveryDate DATETIME2 = NULL, @DriverName NVARCHAR(150) = NULL,
    @VehicleName NVARCHAR(150) = NULL, @Route NVARCHAR(150) = NULL, @PoultryProductId INT,
    @QuantityLoaded DECIMAL(14,3), @Unit NVARCHAR(30) = NULL, @UnitPrice DECIMAL(14,2) = 0,
    @Notes NVARCHAR(500) = NULL, @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF (@QuantityLoaded <= 0) BEGIN RAISERROR('Quantity loaded must be > 0.', 16, 1); RETURN; END

    BEGIN TRANSACTION;
    INSERT INTO dbo.PoultryDeliveries (FarmId, DeliveryDate, DriverName, VehicleName, Route, PoultryProductId, QuantityLoaded, Unit, UnitPrice, Notes, CreatedBy)
    VALUES (@FarmId, ISNULL(@DeliveryDate, SYSUTCDATETIME()), @DriverName, @VehicleName, @Route, @PoultryProductId, @QuantityLoaded, @Unit, @UnitPrice, @Notes, @CreatedBy);
    DECLARE @Id INT = CAST(SCOPE_IDENTITY() AS INT);

    INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, UnitCost, RelatedId, Note, CreatedBy)
    VALUES (@FarmId, @PoultryProductId, 'Delivery Load', -@QuantityLoaded, @UnitPrice, @Id, N'Eggs loaded for delivery', @CreatedBy);
    COMMIT TRANSACTION;
    SELECT @Id;
END
GO

-- Reconcile a delivery: record return figures + post all side effects.
CREATE OR ALTER PROCEDURE dbo.spPoultryDelivery_Reconcile
    @PoultryDeliveryId INT, @FarmId NVARCHAR(450),
    @QuantitySold DECIMAL(14,3), @QuantityReturned DECIMAL(14,3), @QuantityBroken DECIMAL(14,3) = 0, @QuantityShort DECIMAL(14,3) = 0,
    @CashCollected DECIMAL(14,2) = 0, @CreditSales DECIMAL(14,2) = 0, @DeliveryExpenses DECIMAL(14,2) = 0,
    @PaymentMethod NVARCHAR(30) = 'Cash', @ReconciledBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Loaded DECIMAL(14,3), @ProductId INT, @UnitPrice DECIMAL(14,2), @Status NVARCHAR(20), @Date DATETIME2;
    SELECT @Loaded = QuantityLoaded, @ProductId = PoultryProductId, @UnitPrice = UnitPrice, @Status = Status, @Date = DeliveryDate
    FROM dbo.PoultryDeliveries WHERE PoultryDeliveryId = @PoultryDeliveryId AND FarmId = @FarmId;

    IF @Loaded IS NULL BEGIN RAISERROR('Delivery not found.', 16, 1); RETURN; END
    IF @Status <> 'Loaded' BEGIN RAISERROR('Only a Loaded delivery can be reconciled.', 16, 1); RETURN; END

    DECLARE @Accounted DECIMAL(14,3) = ISNULL(@QuantitySold,0) + ISNULL(@QuantityReturned,0) + ISNULL(@QuantityBroken,0) + ISNULL(@QuantityShort,0);
    IF (ABS(@Accounted - @Loaded) > 0.001) BEGIN RAISERROR('Sold + returned + broken + short must equal quantity loaded.', 16, 1); RETURN; END

    DECLARE @gid UNIQUEIDENTIFIER = TRY_CAST(@FarmId AS UNIQUEIDENTIFIER);
    DECLARE @user NVARCHAR(450) = ISNULL(@ReconciledBy, N'system');
    DECLARE @SaleId INT = NULL, @ExpenseId INT = NULL, @CashId INT = NULL;

    BEGIN TRANSACTION;

    -- returned eggs back into stock
    IF (ISNULL(@QuantityReturned,0) > 0)
        INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, UnitCost, RelatedId, Note, CreatedBy)
        VALUES (@FarmId, @ProductId, 'Delivery Return', @QuantityReturned, @UnitPrice, @PoultryDeliveryId, N'Eggs returned from delivery', @user);

    -- broken + short recorded as loss (eggs already out of stock at load)
    IF (ISNULL(@QuantityBroken,0) + ISNULL(@QuantityShort,0) > 0)
        INSERT INTO dbo.PoultryProductionLoss (FarmId, SourceType, SourceId, LossDate, PoultryProductId, QuantityLost, EstimatedValue, Reason)
        VALUES (@FarmId, 'PoultryDelivery', @PoultryDeliveryId, ISNULL(@Date, SYSUTCDATETIME()), @ProductId,
                ISNULL(@QuantityBroken,0) + ISNULL(@QuantityShort,0), CAST((ISNULL(@QuantityBroken,0)+ISNULL(@QuantityShort,0)) * @UnitPrice AS DECIMAL(14,2)),
                N'Delivery broken/short eggs');

    -- sold eggs -> Sale (FarmId is nvarchar on Sale; no cast)
    IF (ISNULL(@QuantitySold,0) > 0)
    BEGIN
        INSERT INTO dbo.Sale (UserId, SaleDate, Product, Quantity, UnitPrice, TotalAmount, PaymentMethod, CustomerName, SaleDescription, FarmId, CreatedBy, Paid)
        VALUES (@user, CAST(ISNULL(@Date, SYSUTCDATETIME()) AS DATE), N'Eggs', @QuantitySold, @UnitPrice, CAST(@QuantitySold * @UnitPrice AS DECIMAL(18,2)),
                ISNULL(@PaymentMethod, N'Cash'), N'Delivery Sale', CONCAT(N'Delivery #', @PoultryDeliveryId), @FarmId, @user,
                CASE WHEN ISNULL(@CreditSales,0) > 0 THEN 0 ELSE 1 END);
        SET @SaleId = CAST(SCOPE_IDENTITY() AS INT);
    END

    -- delivery expenses -> Expense (FarmId is uniqueidentifier)
    IF (ISNULL(@DeliveryExpenses,0) > 0 AND @gid IS NOT NULL)
    BEGIN
        INSERT INTO dbo.Expense (ExpenseDate, Category, Description, Amount, PaymentMethod, Supplier, FlockId, CreatedDate, UserId, FarmId, SourceType, SourceId)
        VALUES (ISNULL(@Date, SYSUTCDATETIME()), N'Delivery Expense', CONCAT(N'Delivery #', @PoultryDeliveryId, N' expenses'), @DeliveryExpenses,
                N'Cash', NULL, NULL, SYSUTCDATETIME(), @user, @gid, N'PoultryDelivery', @PoultryDeliveryId);
        SET @ExpenseId = CAST(SCOPE_IDENTITY() AS INT);
    END

    -- cash collected -> CashAdjustment (In)
    IF (ISNULL(@CashCollected,0) > 0)
    BEGIN
        INSERT INTO dbo.CashAdjustment (UserId, FarmId, AdjustmentDate, AdjustmentType, Amount, Description, CreatedDate)
        VALUES (@user, @FarmId, ISNULL(@Date, SYSUTCDATETIME()), N'In', @CashCollected, CONCAT(N'Delivery #', @PoultryDeliveryId, N' cash collected'), SYSUTCDATETIME());
        SET @CashId = CAST(SCOPE_IDENTITY() AS INT);
    END

    UPDATE dbo.PoultryDeliveries
    SET QuantitySold = @QuantitySold, QuantityReturned = @QuantityReturned, QuantityBroken = ISNULL(@QuantityBroken,0), QuantityShort = ISNULL(@QuantityShort,0),
        CashCollected = ISNULL(@CashCollected,0), CreditSales = ISNULL(@CreditSales,0), DeliveryExpenses = ISNULL(@DeliveryExpenses,0),
        Status = 'Reconciled', LinkedSaleId = @SaleId, LinkedExpenseId = @ExpenseId, LinkedCashAdjId = @CashId,
        ReconciledBy = @ReconciledBy, ReconciledAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryDeliveryId = @PoultryDeliveryId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

-- Reverse a reconciled delivery: undo all postings, back to Loaded.
CREATE OR ALTER PROCEDURE dbo.spPoultryDelivery_Reverse
    @PoultryDeliveryId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @SaleId INT, @ExpenseId INT, @CashId INT, @Status NVARCHAR(20);
    SELECT @SaleId = LinkedSaleId, @ExpenseId = LinkedExpenseId, @CashId = LinkedCashAdjId, @Status = Status
    FROM dbo.PoultryDeliveries WHERE PoultryDeliveryId = @PoultryDeliveryId AND FarmId = @FarmId;
    IF @Status IS NULL BEGIN RAISERROR('Delivery not found.', 16, 1); RETURN; END
    IF @Status <> 'Reconciled' BEGIN RAISERROR('Only a Reconciled delivery can be reversed.', 16, 1); RETURN; END

    DECLARE @gid UNIQUEIDENTIFIER = TRY_CAST(@FarmId AS UNIQUEIDENTIFIER);
    BEGIN TRANSACTION;
    DELETE FROM dbo.PoultryStockTransactions WHERE FarmId = @FarmId AND TxnType = 'Delivery Return' AND RelatedId = @PoultryDeliveryId;
    DELETE FROM dbo.PoultryProductionLoss WHERE FarmId = @FarmId AND SourceType = 'PoultryDelivery' AND SourceId = @PoultryDeliveryId;
    IF @SaleId IS NOT NULL DELETE FROM dbo.Sale WHERE SaleId = @SaleId AND FarmId = @FarmId;
    IF @ExpenseId IS NOT NULL AND @gid IS NOT NULL DELETE FROM dbo.Expense WHERE ExpenseId = @ExpenseId AND FarmId = @gid;
    IF @CashId IS NOT NULL DELETE FROM dbo.CashAdjustment WHERE AdjustmentId = @CashId AND FarmId = @FarmId;

    UPDATE dbo.PoultryDeliveries
    SET Status = 'Loaded', QuantitySold = 0, QuantityReturned = 0, QuantityBroken = 0, QuantityShort = 0,
        CashCollected = 0, CreditSales = 0, DeliveryExpenses = 0, LinkedSaleId = NULL, LinkedExpenseId = NULL, LinkedCashAdjId = NULL,
        ReconciledBy = NULL, ReconciledAt = NULL, UpdatedAt = SYSUTCDATETIME()
    WHERE PoultryDeliveryId = @PoultryDeliveryId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
END
GO

-- Cancel a not-yet-reconciled load: put the eggs back.
CREATE OR ALTER PROCEDURE dbo.spPoultryDelivery_Cancel
    @PoultryDeliveryId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Status NVARCHAR(20);
    SELECT @Status = Status FROM dbo.PoultryDeliveries WHERE PoultryDeliveryId = @PoultryDeliveryId AND FarmId = @FarmId;
    IF @Status IS NULL BEGIN RAISERROR('Delivery not found.', 16, 1); RETURN; END
    IF @Status <> 'Loaded' BEGIN RAISERROR('Only a Loaded delivery can be cancelled.', 16, 1); RETURN; END
    BEGIN TRANSACTION;
    DELETE FROM dbo.PoultryStockTransactions WHERE FarmId = @FarmId AND TxnType = 'Delivery Load' AND RelatedId = @PoultryDeliveryId;
    UPDATE dbo.PoultryDeliveries SET Status = 'Cancelled', UpdatedAt = SYSUTCDATETIME() WHERE PoultryDeliveryId = @PoultryDeliveryId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryDelivery_GetAll    TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDelivery_Load      TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDelivery_Reconcile TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDelivery_Reverse   TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDelivery_Cancel    TO [Techretainer];
    PRINT '133: granted EXECUTE to Techretainer.';
END
GO

PRINT '133_PoultryDeliveryModule.sql complete.';
GO
