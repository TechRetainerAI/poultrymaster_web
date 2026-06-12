-- =============================================================================
-- 105_PnLIncludeDriverReturnIncome.sql  (Feedback, James 2026-06-10:
--   "The profit and loss report is not working" — Income showed 0.00 even
--   though the day clearly had sales.)
--
-- Root cause: spWaterReport_PeriodPnL summed income ONLY from WaterSales. For a
-- delivery-driven water business the day's income is recorded on the driver
-- RETURN (Cash + MoMo + Bank + Credit), and the WaterSales rows the approve-
-- reconcile creates are SourceType='DeliveryRun' (and may be Cancelled). So the
-- P&L counted 0 income while the closing — which sources income from the driver
-- returns — correctly showed the full amount.
--
-- FIX: make the P&L's income + bags-sold use the SAME basis as the daily closing
-- (dbo.fnWaterDailyClosing_LiveTotals):
--   TotalIncome = storefront WaterSales (non-Cancelled, EXCLUDING DeliveryRun)
--               + driver-return income (Cash+MoMo+Bank+Credit on Draft/Approved
--                 returns).
--   BagsSold    = storefront sale items (excl. DeliveryRun) + driver-return BagsSold.
-- Excluding DeliveryRun from the WaterSales sum prevents double-counting the
-- driver-return income. Everything else (raw, production, operating, losses,
-- NetProfit) is unchanged from 103. Idempotent.
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

    -- Storefront sales only (exclude DeliveryRun — that income is on the return).
    DECLARE @StorefrontIncome DECIMAL(14,2) = ISNULL((
        SELECT SUM(TotalAmount) FROM dbo.WaterSales
        WHERE FarmId = @FarmId AND Status NOT IN ('Cancelled')
          AND ISNULL(SourceType, N'') <> N'DeliveryRun'
          AND SaleDate >= @Start AND SaleDate < @End), 0);

    -- Driver-return income for the day (cash + momo + bank + credit sold).
    DECLARE @DriverIncome DECIMAL(14,2) = ISNULL((
        SELECT SUM(CashCollected + MoMoCollected + BankCollected + CreditSalesAmount)
        FROM dbo.WaterDriverReturns
        WHERE FarmId = @FarmId AND Status IN ('Draft','Approved')
          AND ReturnDate >= @Start AND ReturnDate < @End), 0);

    DECLARE @TotalIncome DECIMAL(14,2) = @StorefrontIncome + @DriverIncome;

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

    -- Bags sold = storefront sale items (excl. DeliveryRun) + driver-return bags sold.
    DECLARE @StorefrontBagsSold DECIMAL(14,3) = ISNULL((
        SELECT SUM(si.Quantity) FROM dbo.WaterSales s
        INNER JOIN dbo.WaterSaleItems si ON si.WaterSaleId = s.WaterSaleId
        WHERE s.FarmId = @FarmId AND s.Status NOT IN ('Cancelled')
          AND ISNULL(s.SourceType, N'') <> N'DeliveryRun'
          AND s.SaleDate >= @Start AND s.SaleDate < @End), 0);
    DECLARE @DriverBagsSold DECIMAL(14,3) = ISNULL((
        SELECT SUM(BagsSold) FROM dbo.WaterDriverReturns
        WHERE FarmId = @FarmId AND Status IN ('Draft','Approved')
          AND ReturnDate >= @Start AND ReturnDate < @End), 0);
    DECLARE @BagsSold INT = CAST(@StorefrontBagsSold + @DriverBagsSold AS INT);

    DECLARE @ProfitMargin DECIMAL(8,2) = CASE WHEN @TotalIncome > 0 THEN (@NetProfit / @TotalIncome) * 100 ELSE 0 END;
    DECLARE @AvgProfitPerBag DECIMAL(14,2) = CASE WHEN @BagsSold > 0 THEN @NetProfit / @BagsSold ELSE 0 END;

    SELECT @FromDate AS PeriodStart, @ToDate AS PeriodEnd,
           @TotalIncome AS TotalIncome,
           @OperatingExpenses AS TotalExpenses,   -- operating only
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

PRINT '105_PnLIncludeDriverReturnIncome.sql complete.';
GO
