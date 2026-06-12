-- =============================================================================
-- 103_FixPeriodPnL.sql  (Feedback: "profit and loss page numbers are not matching")
--
-- The Profit & Loss report numbers were wrong:
--   * The SP returned TotalExpenses = RawMaterialCost + ProductionCost, but the
--     P&L page subtracts production + raw-material cost in "gross profit" AND
--     then subtracts TotalExpenses again — and it read fields that didn't exist
--     (totalProductionCost / totalRawMaterialCost / totalLosses), so gross profit
--     showed the full income and operating expenses/losses were ignored.
--   * General expenses (WaterExpenses), delivery expenses, and losses were never
--     included.
--
-- FIX: return clean, separate components consistent with the daily closing:
--   TotalIncome, RawMaterialCost (cash paid), ProductionCost, TotalExpenses
--   (operating only: general WaterExpenses excl. the auto raw-material expense +
--   delivery expenses), TotalLosses (production losses + driver shortages), and
--   NetProfit = Income − RawMaterial − Production − Operating − Losses.
-- Idempotent.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

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
          AND SaleDate >= @Start AND SaleDate < @End), 0);

    -- Cash paid for raw materials (matches the closing's AmountPaid basis).
    DECLARE @RawMaterialCost DECIMAL(14,2) = ISNULL((
        SELECT SUM(AmountPaid) FROM dbo.WaterRawMaterialPurchases
        WHERE FarmId = @FarmId AND PurchaseDate >= @Start AND PurchaseDate < @End), 0);

    DECLARE @ProductionCost DECIMAL(14,2) = ISNULL((
        SELECT SUM(TotalProductionCost) FROM dbo.WaterProductionBatches
        WHERE FarmId = @FarmId AND IsDeleted = 0 AND Status = 'Approved'
          AND ProductionDate >= @FromDate AND ProductionDate <= @ToDate), 0);

    -- Operating expenses: general approved WaterExpenses (excl. the auto
    -- raw-material-purchase expense, already in RawMaterialCost) + delivery expenses.
    DECLARE @GeneralExpenses DECIMAL(14,2) = ISNULL((
        SELECT SUM(Amount) FROM dbo.WaterExpenses
        WHERE FarmId = @FarmId AND IsDeleted = 0 AND Status = 'Approved'
          AND ISNULL(SourceType, N'') <> N'RawMaterialPurchase'
          AND ExpenseDate >= @Start AND ExpenseDate < @End), 0);
    DECLARE @DeliveryExpenses DECIMAL(14,2) = ISNULL((
        SELECT SUM(de.Amount) FROM dbo.WaterDeliveryExpenses de
        INNER JOIN dbo.WaterDriverReturns dr ON dr.WaterDriverReturnId = de.WaterDriverReturnId
        WHERE dr.FarmId = @FarmId AND dr.Status IN ('Draft','Approved') AND de.IsApproved = 1
          AND dr.ReturnDate >= @Start AND dr.ReturnDate < @End), 0);
    DECLARE @OperatingExpenses DECIMAL(14,2) = @GeneralExpenses + @DeliveryExpenses;

    -- Losses: production losses (damaged/rejected) + driver cash shortages.
    DECLARE @ProductionLosses DECIMAL(14,2) = ISNULL((
        SELECT SUM(TotalValue) FROM dbo.WaterProductionLosses
        WHERE FarmId = @FarmId AND LossDate >= @Start AND LossDate < @End), 0);
    DECLARE @ShortageLosses DECIMAL(14,2) = ISNULL((
        SELECT SUM(ShortageAmount) FROM dbo.WaterDriverReturns
        WHERE FarmId = @FarmId AND Status IN ('Draft','Approved')
          AND ReturnDate >= @Start AND ReturnDate < @End), 0);
    DECLARE @TotalLosses DECIMAL(14,2) = @ProductionLosses + @ShortageLosses;

    DECLARE @NetProfit DECIMAL(14,2) =
        @TotalIncome - @RawMaterialCost - @ProductionCost - @OperatingExpenses - @TotalLosses;

    DECLARE @BagsProduced INT = ISNULL((
        SELECT SUM(BagsProduced - DamagedBags) FROM dbo.WaterProductionBatches
        WHERE FarmId = @FarmId AND IsDeleted = 0 AND Status = 'Approved'
          AND ProductionDate >= @FromDate AND ProductionDate <= @ToDate), 0);
    DECLARE @BagsSold INT = ISNULL((
        SELECT SUM(si.Quantity) FROM dbo.WaterSales s
        INNER JOIN dbo.WaterSaleItems si ON si.WaterSaleId = s.WaterSaleId
        WHERE s.FarmId = @FarmId AND s.Status NOT IN ('Cancelled')
          AND s.SaleDate >= @Start AND s.SaleDate < @End), 0);
    DECLARE @ProfitMargin DECIMAL(8,2) = CASE WHEN @TotalIncome > 0 THEN (@NetProfit / @TotalIncome) * 100 ELSE 0 END;
    DECLARE @AvgProfitPerBag DECIMAL(14,2) = CASE WHEN @BagsSold > 0 THEN @NetProfit / @BagsSold ELSE 0 END;

    SELECT @FromDate AS PeriodStart, @ToDate AS PeriodEnd,
           @TotalIncome AS TotalIncome,
           @OperatingExpenses AS TotalExpenses,   -- operating only now
           @RawMaterialCost AS RawMaterialCost,
           @ProductionCost AS ProductionCost,
           @TotalLosses AS TotalLosses,
           @NetProfit AS NetProfit,
           @ProfitMargin AS ProfitMarginPct,
           @BagsProduced AS BagsProduced,
           @BagsSold AS BagsSold,
           @AvgProfitPerBag AS AvgProfitPerBag;
END
GO
