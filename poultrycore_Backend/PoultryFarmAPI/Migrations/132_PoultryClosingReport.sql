-- =============================================================================
-- Migration 132: Poultry Closing Report aggregation (doc section 6)
-- =============================================================================
-- One SP returns a single-row period summary aggregating the poultry tables:
-- Sale, Expense, ProductionRecords, PoultryStockTransactions, raw materials,
-- losses, CashAdjustment. FarmId is a GUID string; Expense.FarmId is a GUID
-- (cast), the rest compare as strings. Delivery fields are 0 until the delivery
-- module (doc 9) lands. Read-only + idempotent.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryClosingReport_Get
    @FarmId NVARCHAR(450), @FromDate DATE, @ToDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Gid UNIQUEIDENTIFIER = TRY_CAST(@FarmId AS UNIQUEIDENTIFIER);

    -- Egg finished product for this farm (for closing stock).
    DECLARE @egg INT;
    SELECT TOP 1 @egg = PoultryProductId FROM dbo.PoultryProducts
    WHERE FarmId = @FarmId AND (IsRawEggProduct = 1 OR Name IN (N'Eggs', N'Chicken Eggs'))
    ORDER BY IsRawEggProduct DESC, PoultryProductId;

    -- Sales
    DECLARE @TotalSales DECIMAL(18,2) = ISNULL((SELECT SUM(TotalAmount) FROM dbo.Sale WHERE FarmId = @FarmId AND SaleDate BETWEEN @FromDate AND @ToDate), 0);
    DECLARE @EggsSold DECIMAL(18,3) = ISNULL((SELECT SUM(Quantity) FROM dbo.Sale WHERE FarmId = @FarmId AND SaleDate BETWEEN @FromDate AND @ToDate), 0);
    DECLARE @CashSales DECIMAL(18,2) = ISNULL((SELECT SUM(TotalAmount) FROM dbo.Sale WHERE FarmId = @FarmId AND SaleDate BETWEEN @FromDate AND @ToDate AND Paid = 1), 0);
    DECLARE @CreditSales DECIMAL(18,2) = ISNULL((SELECT SUM(TotalAmount) FROM dbo.Sale WHERE FarmId = @FarmId AND SaleDate BETWEEN @FromDate AND @ToDate AND ISNULL(Paid,0) = 0), 0);

    -- Expenses (Expense.FarmId is uniqueidentifier)
    DECLARE @TotalExpenses DECIMAL(18,2) = 0, @RawMatExpense DECIMAL(18,2) = 0;
    IF (@Gid IS NOT NULL)
    BEGIN
        SET @TotalExpenses = ISNULL((SELECT SUM(Amount) FROM dbo.Expense WHERE FarmId = @Gid AND CAST(ExpenseDate AS DATE) BETWEEN @FromDate AND @ToDate), 0);
        SET @RawMatExpense = ISNULL((SELECT SUM(Amount) FROM dbo.Expense WHERE FarmId = @Gid AND CAST(ExpenseDate AS DATE) BETWEEN @FromDate AND @ToDate AND Category = N'Raw Materials / Inventory Purchase'), 0);
    END

    -- Raw material purchases (by our own table, authoritative)
    DECLARE @RawPurchases DECIMAL(18,2) = ISNULL((SELECT SUM(TotalCost) FROM dbo.PoultryRawMaterialPurchases WHERE FarmId = @FarmId AND CAST(PurchaseDate AS DATE) BETWEEN @FromDate AND @ToDate), 0);
    DECLARE @RawConsumed DECIMAL(18,3) = ISNULL((SELECT SUM(QuantityUsed) FROM dbo.PoultryRawMaterialUsage WHERE FarmId = @FarmId AND CAST(UsedDate AS DATE) BETWEEN @FromDate AND @ToDate), 0);

    -- Production
    DECLARE @EggsProduced INT = 0, @BrokenEggs INT = 0, @ProdRecords INT = 0,
            @FeedCost DECIMAL(18,2) = 0, @MedCost DECIMAL(18,2) = 0, @ProdCost DECIMAL(18,2) = 0,
            @FeedConsumed DECIMAL(18,3) = 0, @MedConsumed DECIMAL(18,3) = 0, @ProdDays INT = 0;
    SELECT @EggsProduced = ISNULL(SUM(TotalProduction),0), @BrokenEggs = ISNULL(SUM(BrokenEggs),0), @ProdRecords = COUNT(*),
           @FeedCost = ISNULL(SUM(TotalFeedCost),0), @MedCost = ISNULL(SUM(TotalMedicationCost),0), @ProdCost = ISNULL(SUM(TotalCostOfProduction),0),
           @FeedConsumed = ISNULL(SUM(TotalFeedConsumed),0), @MedConsumed = ISNULL(SUM(TotalMedicationConsumed),0),
           @ProdDays = COUNT(DISTINCT [Date])
    FROM dbo.ProductionRecords WHERE FarmId = @FarmId AND [Date] BETWEEN @FromDate AND @ToDate;

    -- Losses
    DECLARE @ProdLossQty DECIMAL(18,3) = ISNULL((SELECT SUM(QuantityLost) FROM dbo.PoultryProductionLoss WHERE FarmId = @FarmId AND CAST(LossDate AS DATE) BETWEEN @FromDate AND @ToDate), 0);
    DECLARE @LossRecordVal DECIMAL(18,2) = ISNULL((SELECT SUM(EstimatedValue) FROM dbo.PoultryLossRecords WHERE FarmId = @FarmId AND CAST(LossDate AS DATE) BETWEEN @FromDate AND @ToDate AND Status = 'Approved'), 0);

    -- Inventory closing (egg finished stock as of ToDate)
    DECLARE @ClosingEggStock DECIMAL(18,3) = 0, @OpeningEggStock DECIMAL(18,3) = 0;
    IF (@egg IS NOT NULL)
    BEGIN
        SET @ClosingEggStock = ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryStockTransactions WHERE FarmId = @FarmId AND PoultryProductId = @egg AND CAST(CreatedDate AS DATE) <= @ToDate), 0);
        SET @OpeningEggStock = ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryStockTransactions WHERE FarmId = @FarmId AND PoultryProductId = @egg AND CAST(CreatedDate AS DATE) < @FromDate), 0);
    END

    -- Cash (approximation from CashAdjustment net + cash sales - expenses)
    DECLARE @CashAdjNet DECIMAL(18,2) = ISNULL((SELECT SUM(CASE WHEN AdjustmentType IN ('In','Deposit','Add','Increase','Credit') THEN Amount
                                                                WHEN AdjustmentType IN ('Out','Withdraw','Deduct','Decrease','Debit') THEN -Amount
                                                                ELSE Amount END)
                                               FROM dbo.CashAdjustment WHERE FarmId = @FarmId AND CAST(AdjustmentDate AS DATE) BETWEEN @FromDate AND @ToDate), 0);

    SELECT
        @FromDate AS FromDate, @ToDate AS ToDate,
        -- Financial
        @TotalSales AS TotalSales, @TotalExpenses AS TotalExpenses, @RawPurchases AS TotalRawMaterialPurchases,
        @FeedCost AS TotalFeedCost, @MedCost AS TotalMedicationCost, @ProdCost AS TotalCostOfProduction,
        CAST(@TotalSales - @TotalExpenses AS DECIMAL(18,2)) AS NetProfitLoss,
        @CreditSales AS TotalOwedByCustomers,
        -- Production
        @EggsProduced AS TotalEggsProduced, CAST(@EggsProduced - @BrokenEggs AS INT) AS TotalGoodEggs, @BrokenEggs AS TotalBrokenEggs,
        @ProdRecords AS TotalProductionRecords, CAST(CASE WHEN @ProdDays > 0 THEN @EggsProduced * 1.0 / @ProdDays ELSE 0 END AS DECIMAL(18,2)) AS AvgEggsPerDay,
        @FeedConsumed AS TotalFeedConsumed, @MedConsumed AS TotalMedicationConsumed,
        CAST(CASE WHEN @EggsProduced > 0 THEN @ProdCost / @EggsProduced ELSE 0 END AS DECIMAL(18,4)) AS AvgProductionCostPerEgg,
        -- Inventory
        @OpeningEggStock AS OpeningEggStock, @ClosingEggStock AS ClosingEggStock, @EggsSold AS EggsSold,
        @RawPurchases AS RawMaterialsPurchased, @RawConsumed AS RawMaterialsConsumed,
        -- Losses
        @ProdLossQty AS ProductionLossQty, @LossRecordVal AS ApprovedLossValue, @BrokenEggs AS BrokenEggsTotal,
        -- Cash (approx)
        @CashSales AS CashSalesCollected, @CashAdjNet AS CashAdjustmentsNet,
        CAST(@CashSales + @CashAdjNet AS DECIMAL(18,2)) AS EstimatedCashInflows,
        -- Delivery (populated when delivery module lands)
        CAST(0 AS DECIMAL(18,3)) AS EggsLoadedForDelivery, CAST(0 AS DECIMAL(18,3)) AS EggsReturned,
        CAST(0 AS DECIMAL(18,2)) AS DriverCollections, CAST(0 AS DECIMAL(18,2)) AS DeliveryExpenses;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryClosingReport_Get TO [Techretainer];
    PRINT '132: granted EXECUTE to Techretainer.';
END
GO

PRINT '132_PoultryClosingReport.sql complete.';
GO
