-- =============================================================================
-- Migration 143: reconcile the poultry closing report with the Production Log
-- =============================================================================
-- Problem (James): the Closing Report showed empty / wrong numbers because it
-- sourced feed, deaths and birds from the poultry-inventory tables
-- (PoultryStockTransactions / new costing fields) which are empty unless a farm
-- has set up the optional inventory module. The Production Log — the source of
-- truth the client uses — sums the plain ProductionRecords / Flock columns.
--
-- This redefines spPoultryClosingReport_Get to compute those figures the SAME
-- way the Production Log does, so the report always reconciles:
--   * TotalFeedKg      = SUM(ProductionRecords.FeedKg)             (legacy feed)
--   * MortalityCount   = SUM(ProductionRecords.Mortality)         (deaths)
--   * PlacedBirds      = SUM(Flock.Quantity) for active+arrived flocks
--   * BirdsLeft        = SUM(latest NoOfBirdsLeft per active+arrived flock)
--   * AvgEggsPerRecord = TotalEggsProduced / TotalProductionRecords
-- All previously-returned columns are preserved (additive), so the C# generic
-- dictionary mapping and the existing UI keep working; new columns are surfaced
-- by adding rows to the report page.
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

    DECLARE @egg INT;
    SELECT TOP 1 @egg = PoultryProductId FROM dbo.PoultryProducts
    WHERE FarmId = @FarmId AND (IsRawEggProduct = 1 OR Name IN (N'Eggs', N'Chicken Eggs'))
    ORDER BY IsRawEggProduct DESC, PoultryProductId;

    DECLARE @bird INT;
    SELECT TOP 1 @bird = PoultryProductId FROM dbo.PoultryProducts
    WHERE FarmId = @FarmId AND (IsBirdProduct = 1 OR Name = N'Birds')
    ORDER BY IsBirdProduct DESC, PoultryProductId;

    -- ---- Money ---------------------------------------------------------------
    DECLARE @TotalSales DECIMAL(18,2) = ISNULL((SELECT SUM(TotalAmount) FROM dbo.Sale WHERE FarmId = @FarmId AND SaleDate BETWEEN @FromDate AND @ToDate), 0);
    DECLARE @EggsSold DECIMAL(18,3) = ISNULL((SELECT SUM(Quantity) FROM dbo.Sale WHERE FarmId = @FarmId AND SaleDate BETWEEN @FromDate AND @ToDate), 0);
    DECLARE @CashSales DECIMAL(18,2) = ISNULL((SELECT SUM(TotalAmount) FROM dbo.Sale WHERE FarmId = @FarmId AND SaleDate BETWEEN @FromDate AND @ToDate AND Paid = 1), 0);
    DECLARE @CreditSales DECIMAL(18,2) = ISNULL((SELECT SUM(TotalAmount) FROM dbo.Sale WHERE FarmId = @FarmId AND SaleDate BETWEEN @FromDate AND @ToDate AND ISNULL(Paid,0) = 0), 0);

    DECLARE @TotalExpenses DECIMAL(18,2) = 0, @RawMatExpense DECIMAL(18,2) = 0;
    IF (@Gid IS NOT NULL)
    BEGIN
        SET @TotalExpenses = ISNULL((SELECT SUM(Amount) FROM dbo.Expense WHERE FarmId = @Gid AND CAST(ExpenseDate AS DATE) BETWEEN @FromDate AND @ToDate), 0);
        SET @RawMatExpense = ISNULL((SELECT SUM(Amount) FROM dbo.Expense WHERE FarmId = @Gid AND CAST(ExpenseDate AS DATE) BETWEEN @FromDate AND @ToDate AND Category = N'Raw Materials / Inventory Purchase'), 0);
    END

    DECLARE @RawPurchases DECIMAL(18,2) = ISNULL((SELECT SUM(TotalCost) FROM dbo.PoultryRawMaterialPurchases WHERE FarmId = @FarmId AND CAST(PurchaseDate AS DATE) BETWEEN @FromDate AND @ToDate), 0);
    DECLARE @RawConsumed DECIMAL(18,3) = ISNULL((SELECT SUM(QuantityUsed) FROM dbo.PoultryRawMaterialUsage WHERE FarmId = @FarmId AND CAST(UsedDate AS DATE) BETWEEN @FromDate AND @ToDate), 0);

    -- ---- Production (from ProductionRecords — same as the Production Log) -----
    DECLARE @EggsProduced INT = 0, @BrokenEggs INT = 0, @ProdRecords INT = 0,
            @FeedCost DECIMAL(18,2) = 0, @MedCost DECIMAL(18,2) = 0, @ProdCost DECIMAL(18,2) = 0,
            @FeedConsumed DECIMAL(18,3) = 0, @MedConsumed DECIMAL(18,3) = 0, @ProdDays INT = 0,
            @FeedKg DECIMAL(18,3) = 0, @MortalityProd DECIMAL(18,3) = 0;
    SELECT @EggsProduced = ISNULL(SUM(TotalProduction),0), @BrokenEggs = ISNULL(SUM(BrokenEggs),0), @ProdRecords = COUNT(*),
           @FeedCost = ISNULL(SUM(TotalFeedCost),0), @MedCost = ISNULL(SUM(TotalMedicationCost),0), @ProdCost = ISNULL(SUM(TotalCostOfProduction),0),
           @FeedConsumed = ISNULL(SUM(TotalFeedConsumed),0), @MedConsumed = ISNULL(SUM(TotalMedicationConsumed),0), @ProdDays = COUNT(DISTINCT [Date]),
           @FeedKg = ISNULL(SUM(FeedKg),0), @MortalityProd = ISNULL(SUM(Mortality),0)
    FROM dbo.ProductionRecords WHERE FarmId = @FarmId AND [Date] BETWEEN @FromDate AND @ToDate;

    DECLARE @ProdLossQty DECIMAL(18,3) = ISNULL((SELECT SUM(QuantityLost) FROM dbo.PoultryProductionLoss WHERE FarmId = @FarmId AND CAST(LossDate AS DATE) BETWEEN @FromDate AND @ToDate), 0);
    DECLARE @LossRecordVal DECIMAL(18,2) = ISNULL((SELECT SUM(EstimatedValue) FROM dbo.PoultryLossRecords WHERE FarmId = @FarmId AND CAST(LossDate AS DATE) BETWEEN @FromDate AND @ToDate AND Status = 'Approved'), 0);

    -- ---- Egg stock (inventory module; 0 when not configured) ------------------
    DECLARE @ClosingEggStock DECIMAL(18,3) = 0, @OpeningEggStock DECIMAL(18,3) = 0;
    IF (@egg IS NOT NULL)
    BEGIN
        SET @ClosingEggStock = ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryStockTransactions WHERE FarmId = @FarmId AND PoultryProductId = @egg AND CAST(CreatedDate AS DATE) <= @ToDate), 0);
        SET @OpeningEggStock = ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryStockTransactions WHERE FarmId = @FarmId AND PoultryProductId = @egg AND CAST(CreatedDate AS DATE) < @FromDate), 0);
    END

    -- ---- Birds (from Flock + ProductionRecords — same as the Production Log) --
    -- Placed birds = quantity of every active + arrived flock (matches the
    -- farm-wide "Overall Total Birds" headline). Birds left = the latest
    -- NoOfBirdsLeft logged for each such flock (or its placed quantity when it
    -- has no production yet), clamped to [0, placed].
    DECLARE @PlacedBirds DECIMAL(18,3) = ISNULL((
        SELECT SUM(Quantity) FROM dbo.Flock
        WHERE FarmId = @FarmId AND Active = 1 AND HasArrived = 1 AND ISNULL(IsDeleted,0) = 0), 0);

    DECLARE @BirdsLeft DECIMAL(18,3) = ISNULL((
        SELECT SUM(
            CASE
                WHEN lr.NoOfBirdsLeft IS NULL THEN f.Quantity
                WHEN lr.NoOfBirdsLeft < 0 THEN 0
                WHEN lr.NoOfBirdsLeft > f.Quantity THEN f.Quantity
                ELSE lr.NoOfBirdsLeft
            END)
        FROM dbo.Flock f
        OUTER APPLY (
            SELECT TOP 1 pr.NoOfBirdsLeft
            FROM dbo.ProductionRecords pr
            WHERE pr.FarmId = @FarmId AND pr.FlockId = f.FlockId AND pr.[Date] <= @ToDate
            ORDER BY pr.[Date] DESC
        ) lr
        WHERE f.FarmId = @FarmId AND f.Active = 1 AND f.HasArrived = 1 AND ISNULL(f.IsDeleted,0) = 0), 0);

    DECLARE @BirdsLost DECIMAL(18,3) = CASE WHEN @PlacedBirds - @BirdsLeft > 0 THEN @PlacedBirds - @BirdsLeft ELSE 0 END;

    -- Inventory-based bird movements (0 when the module is not configured).
    DECLARE @OpeningBirds DECIMAL(18,3) = 0, @ClosingBirds DECIMAL(18,3) = 0, @BirdsPurchased DECIMAL(18,3) = 0, @BirdsSold DECIMAL(18,3) = 0;
    IF (@bird IS NOT NULL)
    BEGIN
        SET @OpeningBirds = ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryStockTransactions WHERE FarmId=@FarmId AND PoultryProductId=@bird AND CAST(CreatedDate AS DATE) < @FromDate),0);
        SET @ClosingBirds = ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryStockTransactions WHERE FarmId=@FarmId AND PoultryProductId=@bird AND CAST(CreatedDate AS DATE) <= @ToDate),0);
        SET @BirdsPurchased = ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryStockTransactions WHERE FarmId=@FarmId AND PoultryProductId=@bird AND TxnType='Bird Batch Purchase' AND CAST(CreatedDate AS DATE) BETWEEN @FromDate AND @ToDate),0);
        SET @BirdsSold = -ISNULL((SELECT SUM(Quantity) FROM dbo.PoultryStockTransactions WHERE FarmId=@FarmId AND PoultryProductId=@bird AND TxnType='Bird Sale' AND CAST(CreatedDate AS DATE) BETWEEN @FromDate AND @ToDate),0);
    END

    DECLARE @CashAdjNet DECIMAL(18,2) = ISNULL((SELECT SUM(CASE WHEN AdjustmentType IN ('In','Deposit','Add','Increase','Credit') THEN Amount
                                                                WHEN AdjustmentType IN ('Out','Withdraw','Deduct','Decrease','Debit') THEN -Amount
                                                                ELSE Amount END)
                                               FROM dbo.CashAdjustment WHERE FarmId = @FarmId AND CAST(AdjustmentDate AS DATE) BETWEEN @FromDate AND @ToDate), 0);

    SELECT
        @FromDate AS FromDate, @ToDate AS ToDate,
        @TotalSales AS TotalSales, @TotalExpenses AS TotalExpenses, @RawPurchases AS TotalRawMaterialPurchases,
        @FeedCost AS TotalFeedCost, @MedCost AS TotalMedicationCost, @ProdCost AS TotalCostOfProduction,
        CAST(@TotalSales - @TotalExpenses AS DECIMAL(18,2)) AS NetProfitLoss, @CreditSales AS TotalOwedByCustomers,
        @EggsProduced AS TotalEggsProduced, CAST(@EggsProduced - @BrokenEggs AS INT) AS TotalGoodEggs, @BrokenEggs AS TotalBrokenEggs,
        @ProdRecords AS TotalProductionRecords,
        CAST(CASE WHEN @ProdDays > 0 THEN @EggsProduced * 1.0 / @ProdDays ELSE 0 END AS DECIMAL(18,2)) AS AvgEggsPerDay,
        CAST(CASE WHEN @ProdRecords > 0 THEN @EggsProduced * 1.0 / @ProdRecords ELSE 0 END AS DECIMAL(18,2)) AS AvgEggsPerRecord,
        @FeedKg AS TotalFeedKg,
        @FeedConsumed AS TotalFeedConsumed, @MedConsumed AS TotalMedicationConsumed,
        CAST(CASE WHEN @EggsProduced > 0 THEN @ProdCost / @EggsProduced ELSE 0 END AS DECIMAL(18,4)) AS AvgProductionCostPerEgg,
        @OpeningEggStock AS OpeningEggStock, @ClosingEggStock AS ClosingEggStock, @EggsSold AS EggsSold,
        @RawPurchases AS RawMaterialsPurchased, @RawConsumed AS RawMaterialsConsumed,
        @ProdLossQty AS ProductionLossQty, @LossRecordVal AS ApprovedLossValue, @BrokenEggs AS BrokenEggsTotal,
        @CashSales AS CashSalesCollected, @CashAdjNet AS CashAdjustmentsNet, CAST(@CashSales + @CashAdjNet AS DECIMAL(18,2)) AS EstimatedCashInflows,
        -- Birds (Production-Log reconciled)
        @PlacedBirds AS PlacedBirds, @BirdsLeft AS BirdsLeft, @BirdsLost AS BirdsLost,
        @OpeningBirds AS OpeningBirds, @BirdsPurchased AS BirdsPurchased, @BirdsSold AS BirdsSold,
        CAST(@MortalityProd AS INT) AS MortalityCount, @ClosingBirds AS ClosingBirds,
        CAST(CASE WHEN @PlacedBirds > 0 THEN @MortalityProd / @PlacedBirds * 100 ELSE 0 END AS DECIMAL(9,2)) AS MortalityRatePct,
        -- Delivery (populated by delivery module reconciliation)
        CAST(0 AS DECIMAL(18,3)) AS EggsLoadedForDelivery, CAST(0 AS DECIMAL(18,3)) AS EggsReturned,
        CAST(0 AS DECIMAL(18,2)) AS DriverCollections, CAST(0 AS DECIMAL(18,2)) AS DeliveryExpenses;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spPoultryClosingReport_Get TO [Techretainer];
GO

PRINT '143_PoultryClosingReportReconcile.sql complete.';
GO
