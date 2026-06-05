-- =============================================================================
-- Migration 044: Water Company — Phase W3 SPs (Raw Materials, Daily Closing,
-- Loss Records, Reports)
-- =============================================================================
-- Run AFTER 043_AddWaterRawMaterialsDailyClosing.sql.
--
-- Highlights:
--   * spWaterRawMaterialPurchase_Insert — increments item.CurrentQuantity atomically.
--   * spWaterRawMaterialUsage_Insert    — decrements item.CurrentQuantity atomically.
--   * spWaterDailyClosing_Submit        — auto-aggregates production + sales +
--                                          expenses + shortages + collections.
--   * Report SPs: Period P&L, Route Profitability, Driver Reconciliation,
--     Raw Material Variance, Extended Dashboard.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- WaterRawMaterialItem CRUD
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_GetAll @FarmId NVARCHAR(450) AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.WaterRawMaterialItems WHERE FarmId = @FarmId
    ORDER BY IsActive DESC, Category, ItemName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_GetById @WaterRawMaterialItemId INT, @FarmId NVARCHAR(450) AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.WaterRawMaterialItems
    WHERE WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_Insert
    @FarmId NVARCHAR(450), @ItemName NVARCHAR(150), @Category NVARCHAR(40),
    @UnitOfMeasure NVARCHAR(30) = NULL,
    @MinimumStockAlert DECIMAL(14,3) = 0,
    @CurrentQuantity DECIMAL(14,3) = 0,
    @IsActive BIT = 1, @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterRawMaterialItems (FarmId, ItemName, Category, UnitOfMeasure,
        MinimumStockAlert, CurrentQuantity, IsActive, Notes)
    VALUES (@FarmId, @ItemName, @Category, @UnitOfMeasure,
        @MinimumStockAlert, @CurrentQuantity, @IsActive, @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_Update
    @WaterRawMaterialItemId INT, @FarmId NVARCHAR(450),
    @ItemName NVARCHAR(150), @Category NVARCHAR(40),
    @UnitOfMeasure NVARCHAR(30) = NULL,
    @MinimumStockAlert DECIMAL(14,3),
    @IsActive BIT, @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- CurrentQuantity is NOT updateable here — only via Purchases / Usage.
    UPDATE dbo.WaterRawMaterialItems
    SET ItemName = @ItemName, Category = @Category, UnitOfMeasure = @UnitOfMeasure,
        MinimumStockAlert = @MinimumStockAlert, IsActive = @IsActive,
        Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
    WHERE WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_Delete @WaterRawMaterialItemId INT, @FarmId NVARCHAR(450) AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterRawMaterialItems SET IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_GetLowStock @FarmId NVARCHAR(450) AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.WaterRawMaterialItems
    WHERE FarmId = @FarmId AND IsActive = 1
      AND MinimumStockAlert > 0 AND CurrentQuantity <= MinimumStockAlert
    ORDER BY (CurrentQuantity - MinimumStockAlert);
END
GO

-- =============================================================================
-- WaterRawMaterialPurchase — atomic insert + increment stock
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialPurchase_GetAll
    @FarmId NVARCHAR(450), @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.*, i.ItemName, i.Category, i.UnitOfMeasure
    FROM   dbo.WaterRawMaterialPurchases p
    INNER  JOIN dbo.WaterRawMaterialItems i ON i.WaterRawMaterialItemId = p.WaterRawMaterialItemId
    WHERE  p.FarmId = @FarmId
       AND (@FromDate IS NULL OR CAST(p.PurchaseDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(p.PurchaseDate AS DATE) <= @ToDate)
    ORDER  BY p.PurchaseDate DESC, p.WaterRawMaterialPurchaseId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialPurchase_Insert
    @FarmId NVARCHAR(450),
    @WaterRawMaterialItemId INT,
    @SupplierName NVARCHAR(200) = NULL,
    @PurchaseDate DATETIME2 = NULL,
    @Quantity DECIMAL(14,3),
    @UnitCost DECIMAL(14,2),
    @PaymentMethod NVARCHAR(30) = NULL,
    @AmountPaid DECIMAL(14,2) = 0,
    @ReceiptUrl NVARCHAR(500) = NULL,
    @ReceivedByStaffId INT = NULL,
    @Notes NVARCHAR(500) = NULL,
    @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@Quantity <= 0) BEGIN RAISERROR('Quantity must be > 0.', 16, 1); RETURN; END
    IF (@UnitCost < 0)  BEGIN RAISERROR('UnitCost cannot be negative.', 16, 1); RETURN; END

    BEGIN TRANSACTION;

    INSERT INTO dbo.WaterRawMaterialPurchases (
        FarmId, WaterRawMaterialItemId, SupplierName, PurchaseDate, Quantity, UnitCost,
        PaymentMethod, AmountPaid, ReceiptUrl, ReceivedByStaffId, Notes, CreatedBy
    )
    VALUES (
        @FarmId, @WaterRawMaterialItemId, @SupplierName,
        ISNULL(@PurchaseDate, SYSUTCDATETIME()), @Quantity, @UnitCost,
        @PaymentMethod, @AmountPaid, @ReceiptUrl, @ReceivedByStaffId, @Notes, @CreatedBy
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    UPDATE dbo.WaterRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity + @Quantity, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT @NewId;
END
GO

-- =============================================================================
-- WaterRawMaterialUsage — atomic insert + decrement stock
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialUsage_GetAll
    @FarmId NVARCHAR(450), @BatchId INT = NULL, @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.*, i.ItemName, i.Category, i.UnitOfMeasure, b.BatchNumber
    FROM   dbo.WaterRawMaterialUsage u
    INNER  JOIN dbo.WaterRawMaterialItems   i ON i.WaterRawMaterialItemId  = u.WaterRawMaterialItemId
    LEFT   JOIN dbo.WaterProductionBatches  b ON b.WaterProductionBatchId  = u.WaterProductionBatchId
    WHERE  u.FarmId = @FarmId
       AND (@BatchId IS NULL OR u.WaterProductionBatchId = @BatchId)
       AND (@FromDate IS NULL OR CAST(u.UsedDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(u.UsedDate AS DATE) <= @ToDate)
    ORDER  BY u.UsedDate DESC, u.WaterRawMaterialUsageId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialUsage_Insert
    @FarmId NVARCHAR(450),
    @WaterRawMaterialItemId INT,
    @WaterProductionBatchId INT = NULL,
    @UsedDate DATETIME2 = NULL,
    @QuantityUsed DECIMAL(14,3),
    @ExpectedQuantityUsed DECIMAL(14,3) = NULL,
    @VarianceReason NVARCHAR(500) = NULL,
    @UsedByStaffId INT = NULL,
    @Notes NVARCHAR(500) = NULL,
    @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@QuantityUsed <= 0) BEGIN RAISERROR('QuantityUsed must be > 0.', 16, 1); RETURN; END

    DECLARE @OnHand DECIMAL(14,3);
    SELECT @OnHand = CurrentQuantity FROM dbo.WaterRawMaterialItems
    WHERE WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;
    IF @OnHand IS NULL
    BEGIN RAISERROR('Raw material item not found.', 16, 1); RETURN; END
    IF @OnHand < @QuantityUsed
    BEGIN
        DECLARE @OnHandStr NVARCHAR(20) = CAST(@OnHand AS NVARCHAR(20));
        DECLARE @QtyStr    NVARCHAR(20) = CAST(@QuantityUsed AS NVARCHAR(20));
        DECLARE @msg NVARCHAR(200) = N'Insufficient stock: on hand ' + @OnHandStr + N', trying to use ' + @QtyStr + N'.';
        RAISERROR(@msg, 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    INSERT INTO dbo.WaterRawMaterialUsage (
        FarmId, WaterRawMaterialItemId, WaterProductionBatchId, UsedDate,
        QuantityUsed, ExpectedQuantityUsed, VarianceReason, UsedByStaffId,
        Notes, CreatedBy
    )
    VALUES (
        @FarmId, @WaterRawMaterialItemId, @WaterProductionBatchId,
        ISNULL(@UsedDate, SYSUTCDATETIME()),
        @QuantityUsed, @ExpectedQuantityUsed, @VarianceReason, @UsedByStaffId,
        @Notes, @CreatedBy
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    UPDATE dbo.WaterRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity - @QuantityUsed, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT @NewId;
END
GO

-- =============================================================================
-- WaterLossRecord
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterLossRecord_GetAll
    @FarmId NVARCHAR(450), @LossType NVARCHAR(40) = NULL,
    @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT l.*, p.Name AS ProductName
    FROM   dbo.WaterLossRecords l
    LEFT   JOIN dbo.WaterProducts p ON p.WaterProductId = l.WaterProductId
    WHERE  l.FarmId = @FarmId
       AND (@LossType IS NULL OR l.LossType = @LossType)
       AND (@FromDate IS NULL OR CAST(l.LossDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(l.LossDate AS DATE) <= @ToDate)
    ORDER  BY l.LossDate DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterLossRecord_Insert
    @FarmId NVARCHAR(450),
    @LossDate DATETIME2 = NULL,
    @LossType NVARCHAR(40),
    @WaterProductId INT = NULL,
    @QuantityBags DECIMAL(14,3) = NULL,
    @QuantitySachets DECIMAL(14,3) = NULL,
    @EstimatedValue DECIMAL(14,2) = NULL,
    @ResponsibleStaffId INT = NULL,
    @Reason NVARCHAR(500) = NULL,
    @Notes NVARCHAR(500) = NULL,
    @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterLossRecords (
        FarmId, LossDate, LossType, WaterProductId, QuantityBags, QuantitySachets,
        EstimatedValue, ResponsibleStaffId, Reason, Notes, CreatedBy
    )
    VALUES (
        @FarmId, ISNULL(@LossDate, SYSUTCDATETIME()), @LossType, @WaterProductId,
        @QuantityBags, @QuantitySachets, @EstimatedValue, @ResponsibleStaffId,
        @Reason, @Notes, @CreatedBy
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterLossRecord_Approve
    @WaterLossRecordId INT, @FarmId NVARCHAR(450), @ApprovedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterLossRecords
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterLossRecordId = @WaterLossRecordId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- WaterDailyClosing — auto-aggregating Submit (the genius)
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterDailyClosing_GetAll
    @FarmId NVARCHAR(450),
    @Status NVARCHAR(20) = NULL,
    @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.WaterDailyClosings
    WHERE  FarmId = @FarmId
       AND (@Status   IS NULL OR Status = @Status)
       AND (@FromDate IS NULL OR ClosingDate >= @FromDate)
       AND (@ToDate   IS NULL OR ClosingDate <= @ToDate)
    ORDER  BY ClosingDate DESC, WaterDailyClosingId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDailyClosing_GetById
    @WaterDailyClosingId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.WaterDailyClosings
    WHERE WaterDailyClosingId = @WaterDailyClosingId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDailyClosing_Insert
    @FarmId NVARCHAR(450),
    @ClosingDate DATE,
    @ActualCashCounted DECIMAL(14,2) = 0,
    @ManagerNotes NVARCHAR(2000) = NULL,
    @DifferenceReason NVARCHAR(500) = NULL,
    @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM dbo.WaterDailyClosings WHERE FarmId = @FarmId AND ClosingDate = @ClosingDate)
    BEGIN RAISERROR('A closing already exists for that date.', 16, 1); RETURN; END

    INSERT INTO dbo.WaterDailyClosings (
        FarmId, ClosingDate, ActualCashCounted, ManagerNotes, DifferenceReason,
        Status, CreatedBy
    )
    VALUES (
        @FarmId, @ClosingDate, @ActualCashCounted, @ManagerNotes, @DifferenceReason,
        'Draft', @CreatedBy
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

-- The auto-aggregator. Pulls everything from the immutable tables.
CREATE OR ALTER PROCEDURE dbo.spWaterDailyClosing_Submit
    @WaterDailyClosingId INT,
    @FarmId NVARCHAR(450),
    @ActualCashCounted DECIMAL(14,2) = NULL,
    @ManagerNotes NVARCHAR(2000) = NULL,
    @DifferenceReason NVARCHAR(500) = NULL,
    @SubmittedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ClosingDate DATE, @Status NVARCHAR(20);
    SELECT @ClosingDate = ClosingDate, @Status = Status
    FROM   dbo.WaterDailyClosings
    WHERE  WaterDailyClosingId = @WaterDailyClosingId AND FarmId = @FarmId;

    IF @ClosingDate IS NULL
    BEGIN RAISERROR('Closing %d not found.', 16, 1, @WaterDailyClosingId); RETURN; END
    IF @Status NOT IN ('Draft', 'Submitted')
    BEGIN RAISERROR('Closing cannot be (re)submitted from status %s.', 16, 1, @Status); RETURN; END

    DECLARE @DayStart DATETIME2 = CAST(@ClosingDate AS DATETIME2);
    DECLARE @DayEnd   DATETIME2 = DATEADD(DAY, 1, @DayStart);

    -- Production (approved batches)
    DECLARE @BagsProduced DECIMAL(14,3) = ISNULL((
        SELECT SUM(CAST(BagsProduced - DamagedBags AS DECIMAL(14,3)))
        FROM   dbo.WaterProductionBatches
        WHERE  FarmId = @FarmId AND IsDeleted = 0 AND Status = 'Approved'
           AND ProductionDate = @ClosingDate
    ), 0);
    DECLARE @TotalProductionCost DECIMAL(14,2) = ISNULL((
        SELECT SUM(TotalProductionCost)
        FROM   dbo.WaterProductionBatches
        WHERE  FarmId = @FarmId AND IsDeleted = 0 AND Status = 'Approved'
           AND ProductionDate = @ClosingDate
    ), 0);

    -- Sales (via existing WaterSales table)
    DECLARE @BagsSold DECIMAL(14,3) = ISNULL((
        SELECT SUM(CAST(si.Quantity AS DECIMAL(14,3)))
        FROM   dbo.WaterSales s
        INNER  JOIN dbo.WaterSaleItems si ON si.WaterSaleId = s.WaterSaleId
        WHERE  s.FarmId = @FarmId
           AND s.Status NOT IN ('Cancelled')
           AND s.SaleDate >= @DayStart AND s.SaleDate < @DayEnd
    ), 0);
    DECLARE @TotalIncome DECIMAL(14,2) = ISNULL((
        SELECT SUM(TotalAmount)
        FROM   dbo.WaterSales
        WHERE  FarmId = @FarmId AND Status NOT IN ('Cancelled')
           AND SaleDate >= @DayStart AND SaleDate < @DayEnd
    ), 0);
    DECLARE @CreditSales DECIMAL(14,2) = ISNULL((
        SELECT SUM(TotalAmount - AmountPaid)
        FROM   dbo.WaterSales
        WHERE  FarmId = @FarmId AND Status NOT IN ('Cancelled')
           AND SaleDate >= @DayStart AND SaleDate < @DayEnd
    ), 0);

    -- Customer payments (collections via WaterPayments)
    DECLARE @CustomerCollections DECIMAL(14,2) = ISNULL((
        SELECT SUM(Amount) FROM dbo.WaterPayments
        WHERE  FarmId = @FarmId AND PaymentDate >= @DayStart AND PaymentDate < @DayEnd
    ), 0);

    -- Bags returned + damaged (from WaterDriverReturns approved today)
    DECLARE @BagsReturned DECIMAL(14,3) = ISNULL((
        SELECT SUM(CAST(BagsReturned AS DECIMAL(14,3)))
        FROM   dbo.WaterDriverReturns
        WHERE  FarmId = @FarmId AND Status = 'Approved'
           AND ReturnDate >= @DayStart AND ReturnDate < @DayEnd
    ), 0);
    DECLARE @BagsDamaged DECIMAL(14,3) = ISNULL((
        SELECT SUM(CAST(BagsDamaged AS DECIMAL(14,3)))
        FROM   dbo.WaterDriverReturns
        WHERE  FarmId = @FarmId AND Status = 'Approved'
           AND ReturnDate >= @DayStart AND ReturnDate < @DayEnd
    ), 0);

    -- Driver shortages today
    DECLARE @DriverShortagesTotal DECIMAL(14,2) = ISNULL((
        SELECT SUM(ShortageAmount) FROM dbo.WaterDriverShortages
        WHERE  FarmId = @FarmId
           AND ShortageDate >= @DayStart AND ShortageDate < @DayEnd
    ), 0);

    -- Raw material costs / expenses approximation
    DECLARE @RawMaterialSpendToday DECIMAL(14,2) = ISNULL((
        SELECT SUM(TotalCost) FROM dbo.WaterRawMaterialPurchases
        WHERE  FarmId = @FarmId AND PurchaseDate >= @DayStart AND PurchaseDate < @DayEnd
    ), 0);

    -- Stock on hand right now (proxy for ClosingStock; not tied to date strictly)
    DECLARE @ClosingStockBags DECIMAL(14,3) = ISNULL((
        SELECT SUM(CAST(Quantity AS DECIMAL(14,3)))
        FROM   dbo.WaterStockTransactions
        WHERE  FarmId = @FarmId
    ), 0);

    -- Cash at hand: best-effort SUM of WaterPayments and sale payments minus raw material spend.
    -- Owner enters ActualCashCounted to override.
    DECLARE @CashAtHand DECIMAL(14,2) = @TotalIncome - @CreditSales + @CustomerCollections - @RawMaterialSpendToday;
    DECLARE @ActCash    DECIMAL(14,2) = ISNULL(@ActualCashCounted, 0);
    DECLARE @CashDiff   DECIMAL(14,2) = @ActCash - @CashAtHand;

    BEGIN TRANSACTION;

    UPDATE dbo.WaterDailyClosings
    SET    BagsProduced         = @BagsProduced,
           BagsSold             = @BagsSold,
           BagsReturned         = @BagsReturned,
           BagsDamaged          = @BagsDamaged,
           ClosingStockBags     = @ClosingStockBags,
           TotalIncome          = @TotalIncome,
           TotalExpenses        = @RawMaterialSpendToday + @TotalProductionCost,
           TotalProductionCost  = @TotalProductionCost,
           CashAtHand           = @CashAtHand,
           ActualCashCounted    = COALESCE(@ActualCashCounted, ActualCashCounted),
           CashDifference       = @CashDiff,
           CreditSales          = @CreditSales,
           CustomerCollections  = @CustomerCollections,
           DriverShortagesTotal = @DriverShortagesTotal,
           ManagerNotes         = COALESCE(@ManagerNotes, ManagerNotes),
           DifferenceReason     = COALESCE(@DifferenceReason, DifferenceReason),
           Status               = 'Submitted',
           SubmittedBy          = @SubmittedBy,
           SubmittedAt          = SYSUTCDATETIME(),
           UpdatedAt            = SYSUTCDATETIME()
    WHERE  WaterDailyClosingId = @WaterDailyClosingId AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT * FROM dbo.WaterDailyClosings
    WHERE  WaterDailyClosingId = @WaterDailyClosingId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDailyClosing_Approve
    @WaterDailyClosingId INT, @FarmId NVARCHAR(450),
    @ApprovedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- Idempotent
    IF EXISTS (SELECT 1 FROM dbo.WaterDailyClosings
               WHERE WaterDailyClosingId = @WaterDailyClosingId AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT WaterDailyClosingId, Status, ApprovedBy, ApprovedAt FROM dbo.WaterDailyClosings
        WHERE WaterDailyClosingId = @WaterDailyClosingId AND FarmId = @FarmId;
        RETURN;
    END

    UPDATE dbo.WaterDailyClosings
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterDailyClosingId = @WaterDailyClosingId AND FarmId = @FarmId
       AND Status = 'Submitted';
    IF @@ROWCOUNT = 0
    BEGIN RAISERROR('Closing must be Submitted before Approving.', 16, 1); RETURN; END
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDailyClosing_Reject
    @WaterDailyClosingId INT, @FarmId NVARCHAR(450),
    @RejectionReason NVARCHAR(500), @ApprovedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterDailyClosings
    SET    Status = 'Rejected', RejectionReason = @RejectionReason,
           ApprovedBy = @ApprovedBy, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterDailyClosingId = @WaterDailyClosingId AND FarmId = @FarmId
       AND Status = 'Submitted';
    IF @@ROWCOUNT = 0
    BEGIN RAISERROR('Closing must be Submitted before Rejecting.', 16, 1); RETURN; END
END
GO

-- =============================================================================
-- Reports
-- =============================================================================

-- Period P&L: income (water sales) - expenses (raw materials + production costs).
CREATE OR ALTER PROCEDURE dbo.spWaterReport_PeriodPnL
    @FarmId NVARCHAR(450), @FromDate DATE, @ToDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Start DATETIME2 = CAST(@FromDate AS DATETIME2);
    DECLARE @End   DATETIME2 = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME2));

    DECLARE @TotalIncome DECIMAL(14,2) = ISNULL((
        SELECT SUM(TotalAmount) FROM dbo.WaterSales
        WHERE FarmId = @FarmId AND Status NOT IN ('Cancelled')
          AND SaleDate >= @Start AND SaleDate < @End
    ), 0);
    DECLARE @RawMaterialCost DECIMAL(14,2) = ISNULL((
        SELECT SUM(TotalCost) FROM dbo.WaterRawMaterialPurchases
        WHERE FarmId = @FarmId AND PurchaseDate >= @Start AND PurchaseDate < @End
    ), 0);
    DECLARE @ProductionCost DECIMAL(14,2) = ISNULL((
        SELECT SUM(TotalProductionCost) FROM dbo.WaterProductionBatches
        WHERE FarmId = @FarmId AND IsDeleted = 0 AND Status = 'Approved'
          AND ProductionDate >= @FromDate AND ProductionDate <= @ToDate
    ), 0);
    DECLARE @TotalExpenses DECIMAL(14,2) = @RawMaterialCost + @ProductionCost;
    DECLARE @NetProfit DECIMAL(14,2) = @TotalIncome - @TotalExpenses;
    DECLARE @BagsProduced INT = ISNULL((
        SELECT SUM(BagsProduced - DamagedBags) FROM dbo.WaterProductionBatches
        WHERE FarmId = @FarmId AND IsDeleted = 0 AND Status = 'Approved'
          AND ProductionDate >= @FromDate AND ProductionDate <= @ToDate
    ), 0);
    DECLARE @BagsSold INT = ISNULL((
        SELECT SUM(si.Quantity)
        FROM   dbo.WaterSales s
        INNER  JOIN dbo.WaterSaleItems si ON si.WaterSaleId = s.WaterSaleId
        WHERE  s.FarmId = @FarmId AND s.Status NOT IN ('Cancelled')
           AND s.SaleDate >= @Start AND s.SaleDate < @End
    ), 0);
    DECLARE @ProfitMargin DECIMAL(8,2) = CASE WHEN @TotalIncome > 0 THEN (@NetProfit / @TotalIncome) * 100 ELSE 0 END;
    DECLARE @AvgProfitPerBag DECIMAL(14,2) = CASE WHEN @BagsSold > 0 THEN @NetProfit / @BagsSold ELSE 0 END;

    SELECT @FromDate AS PeriodStart, @ToDate AS PeriodEnd,
           @TotalIncome AS TotalIncome,
           @TotalExpenses AS TotalExpenses,
           @RawMaterialCost AS RawMaterialCost,
           @ProductionCost AS ProductionCost,
           @NetProfit AS NetProfit,
           @ProfitMargin AS ProfitMarginPct,
           @BagsProduced AS BagsProduced,
           @BagsSold AS BagsSold,
           @AvgProfitPerBag AS AvgProfitPerBag;
END
GO

-- Route profitability: per route, sales (from loadings/returns), fuel cost (no expense category yet,
-- so this returns sales + bags sold + shortages; fuel will be enriched in a later phase).
CREATE OR ALTER PROCEDURE dbo.spWaterReport_RouteProfitability
    @FarmId NVARCHAR(450), @FromDate DATE, @ToDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Start DATETIME2 = CAST(@FromDate AS DATETIME2);
    DECLARE @End   DATETIME2 = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME2));

    SELECT r.WaterRouteId, r.RouteName,
           ISNULL(SUM(l.BagsLoaded), 0)                            AS TotalBagsLoaded,
           ISNULL(SUM(dr.BagsSold), 0)                             AS TotalBagsSold,
           ISNULL(SUM(dr.BagsReturned), 0)                         AS TotalBagsReturned,
           ISNULL(SUM(dr.BagsDamaged + dr.MissingBags), 0)         AS TotalBagsLost,
           ISNULL(SUM(dr.CashCollected + dr.MoMoCollected + dr.BankCollected + dr.CreditSalesAmount), 0) AS TotalRevenue,
           ISNULL(SUM(dr.ShortageAmount), 0)                       AS TotalShortages,
           ISNULL(SUM(dr.OverageAmount), 0)                        AS TotalOverages,
           ISNULL(SUM(dr.CashCollected + dr.MoMoCollected + dr.BankCollected + dr.CreditSalesAmount), 0)
               - ISNULL(SUM(dr.ShortageAmount), 0)                  AS NetRouteIncome
    FROM   dbo.WaterRoutes r
    LEFT   JOIN dbo.WaterVehicleLoadings l
                  ON l.WaterRouteId = r.WaterRouteId
                 AND l.LoadDate >= @Start AND l.LoadDate < @End
                 AND l.Status IN ('Loaded', 'Reconciled')
    LEFT   JOIN dbo.WaterDriverReturns dr
                  ON dr.WaterVehicleLoadingId = l.WaterVehicleLoadingId
                 AND dr.Status = 'Approved'
    WHERE  r.FarmId = @FarmId
    GROUP  BY r.WaterRouteId, r.RouteName
    ORDER  BY NetRouteIncome DESC;
END
GO

-- Driver reconciliation report: per driver, total loaded vs total accounted-for vs shortages.
CREATE OR ALTER PROCEDURE dbo.spWaterReport_DriverReconciliation
    @FarmId NVARCHAR(450), @FromDate DATE, @ToDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Start DATETIME2 = CAST(@FromDate AS DATETIME2);
    DECLARE @End   DATETIME2 = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME2));

    SELECT d.WaterDriverId, d.DriverName, d.PhoneNumber,
           ISNULL(SUM(l.BagsLoaded), 0)                            AS TotalBagsLoaded,
           ISNULL(SUM(dr.BagsSold), 0)                             AS TotalBagsSold,
           ISNULL(SUM(dr.BagsReturned), 0)                         AS TotalBagsReturned,
           ISNULL(SUM(dr.BagsDamaged + dr.MissingBags), 0)         AS TotalBagsLost,
           ISNULL(SUM(l.ExpectedCash), 0)                          AS ExpectedRevenue,
           ISNULL(SUM(dr.TotalAccountedFor), 0)                    AS ActualAccountedFor,
           ISNULL(SUM(dr.ShortageAmount), 0)                       AS TotalShortages,
           COUNT(DISTINCT CASE WHEN dr.ShortageAmount > 0 THEN dr.WaterDriverReturnId END) AS ShortageOccurrences
    FROM   dbo.WaterDrivers d
    LEFT   JOIN dbo.WaterVehicleLoadings l
                  ON l.WaterDriverId = d.WaterDriverId
                 AND l.LoadDate >= @Start AND l.LoadDate < @End
                 AND l.Status IN ('Loaded', 'Reconciled')
    LEFT   JOIN dbo.WaterDriverReturns dr
                  ON dr.WaterVehicleLoadingId = l.WaterVehicleLoadingId
                 AND dr.Status = 'Approved'
    WHERE  d.FarmId = @FarmId
    GROUP  BY d.WaterDriverId, d.DriverName, d.PhoneNumber
    ORDER  BY TotalShortages DESC, TotalBagsLoaded DESC;
END
GO

-- Raw material usage variance report.
CREATE OR ALTER PROCEDURE dbo.spWaterReport_RawMaterialVariance
    @FarmId NVARCHAR(450), @FromDate DATE, @ToDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Start DATETIME2 = CAST(@FromDate AS DATETIME2);
    DECLARE @End   DATETIME2 = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME2));

    SELECT i.WaterRawMaterialItemId, i.ItemName, i.Category, i.UnitOfMeasure,
           ISNULL(SUM(u.ExpectedQuantityUsed), 0) AS TotalExpected,
           ISNULL(SUM(u.QuantityUsed), 0)         AS TotalActual,
           ISNULL(SUM(u.Variance), 0)             AS TotalVariance,
           COUNT(u.WaterRawMaterialUsageId)       AS UsageCount
    FROM   dbo.WaterRawMaterialItems i
    LEFT   JOIN dbo.WaterRawMaterialUsage u
                  ON u.WaterRawMaterialItemId = i.WaterRawMaterialItemId
                 AND u.UsedDate >= @Start AND u.UsedDate < @End
    WHERE  i.FarmId = @FarmId
    GROUP  BY i.WaterRawMaterialItemId, i.ItemName, i.Category, i.UnitOfMeasure
    HAVING COUNT(u.WaterRawMaterialUsageId) > 0
    ORDER  BY ABS(ISNULL(SUM(u.Variance), 0)) DESC;
END
GO

-- Extended dashboard summary (today's bags produced/sold, stock on hand,
-- low-stock raw materials, pending shortages).
CREATE OR ALTER PROCEDURE dbo.spWaterReport_DashboardExtended
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @TodayStart DATETIME2 = CAST(CAST(SYSUTCDATETIME() AS DATE) AS DATETIME2);
    DECLARE @TodayEnd   DATETIME2 = DATEADD(DAY, 1, @TodayStart);

    -- 1. Today snapshot
    SELECT
      ISNULL((SELECT SUM(BagsProduced - DamagedBags) FROM dbo.WaterProductionBatches
              WHERE FarmId = @FarmId AND IsDeleted = 0 AND Status = 'Approved'
                AND ProductionDate = CAST(SYSUTCDATETIME() AS DATE)), 0) AS TodayBagsProduced,
      ISNULL((SELECT SUM(si.Quantity)
              FROM   dbo.WaterSales s
              INNER  JOIN dbo.WaterSaleItems si ON si.WaterSaleId = s.WaterSaleId
              WHERE  s.FarmId = @FarmId AND s.Status NOT IN ('Cancelled')
                 AND s.SaleDate >= @TodayStart AND s.SaleDate < @TodayEnd), 0) AS TodayBagsSold,
      ISNULL((SELECT SUM(TotalAmount) FROM dbo.WaterSales
              WHERE FarmId = @FarmId AND Status NOT IN ('Cancelled')
                AND SaleDate >= @TodayStart AND SaleDate < @TodayEnd), 0) AS TodayRevenue,
      ISNULL((SELECT SUM(TotalProductionCost) FROM dbo.WaterProductionBatches
              WHERE FarmId = @FarmId AND IsDeleted = 0 AND Status = 'Approved'
                AND ProductionDate = CAST(SYSUTCDATETIME() AS DATE)), 0) AS TodayProductionCost,
      ISNULL((SELECT SUM(Quantity) FROM dbo.WaterStockTransactions WHERE FarmId = @FarmId), 0) AS BagsOnHand,
      ISNULL((SELECT SUM(TotalAmount - AmountPaid) FROM dbo.WaterSales
              WHERE FarmId = @FarmId AND Status NOT IN ('Cancelled')), 0) AS TotalCustomerDebt,
      ISNULL((SELECT SUM(ShortageAmount) FROM dbo.WaterDriverShortages
              WHERE FarmId = @FarmId AND Status = 'Pending'), 0) AS PendingDriverShortages;

    -- 2. Alerts
    SELECT
      (SELECT COUNT(*) FROM dbo.WaterRawMaterialItems
       WHERE FarmId = @FarmId AND IsActive = 1
         AND MinimumStockAlert > 0 AND CurrentQuantity <= MinimumStockAlert) AS LowRawMaterialCount,
      (SELECT COUNT(*) FROM dbo.WaterDriverShortages
       WHERE FarmId = @FarmId AND Status = 'Pending') AS PendingShortagesCount,
      (SELECT COUNT(*) FROM dbo.WaterProductionBatches
       WHERE FarmId = @FarmId AND IsDeleted = 0 AND Status = 'Draft') AS DraftBatchesCount,
      (SELECT COUNT(*) FROM dbo.WaterVehicleLoadings
       WHERE FarmId = @FarmId AND IsDeleted = 0 AND Status = 'Loaded') AS LoadingsAwaitingReturnCount,
      (SELECT COUNT(*) FROM dbo.WaterDriverReturns
       WHERE FarmId = @FarmId AND Status = 'Draft') AS DraftReturnsCount,
      (SELECT COUNT(*) FROM dbo.WaterMachines
       WHERE FarmId = @FarmId AND Status IN ('Down', 'UnderMaintenance')) AS MachinesDownCount,
      (SELECT COUNT(*) FROM dbo.WaterVehicles
       WHERE FarmId = @FarmId AND Status = 'UnderMaintenance') AS VehiclesDownCount;
END
GO

PRINT '044_AddWaterRawMaterialsDailyClosingStoredProcedures.sql complete.';
GO
