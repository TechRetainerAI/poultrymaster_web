-- =============================================================================
-- 097_FixClosingDoubleCountDeliverySales.sql  (Feedback #33)
--
-- BUG: on the daily closing, Bags Sold / Credit Sales / Total income were
-- DOUBLED (most visible when a driver ran two deliveries, but it doubled for
-- every approved delivery).
--
-- Root cause: dbo.fnWaterDailyClosing_LiveTotals (the TVF used by
-- spWaterDailyClosing_GetAll / _GetById / _Submit) computes
--     BagsSold    = sale_items.BagsSold  + driver_returns.DriverBagsSold
--     TotalIncome = sale_money.TotalIncome + driver_returns.DriverTotalIncome
--     CreditSales = sale_money.CreditSales + driver_returns.DriverCreditSales
-- The intent was "storefront sales + delivery sales". But approving a driver
-- return CREATES WaterSales/WaterPayments rows stamped SourceType='DeliveryRun'.
-- Those delivery-generated rows were summed in sale_items/sale_money/payments
-- AND again in driver_returns -> every delivery counted twice.
--
-- FIX: exclude SourceType='DeliveryRun' from the storefront CTEs (sale_items,
-- sale_money) and from customer-collections (payments). Delivery figures now
-- come solely from driver_returns; storefront/credit-collection figures come
-- from genuine non-delivery rows. Each is counted exactly once.
--
-- Idempotent (CREATE OR ALTER). Recreating the TVF immediately corrects the
-- live Draft view, the GetAll list, and the frozen snapshot written on Submit.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER FUNCTION dbo.fnWaterDailyClosing_LiveTotals (
    @FarmId      NVARCHAR(450),
    @ClosingDate DATE
)
RETURNS TABLE
AS
RETURN
(
    WITH
    prod AS (
        SELECT
            BagsProduced        = ISNULL(SUM(CAST(BagsProduced - ISNULL(DamagedBags, 0) AS DECIMAL(14,3))), 0),
            TotalProductionCost = ISNULL(SUM(TotalProductionCost), 0)
        FROM dbo.WaterProductionBatches
        WHERE FarmId = @FarmId
          AND IsDeleted = 0
          AND Status IN ('Draft', 'Approved')
          AND ProductionDate = @ClosingDate
    ),
    /* Storefront / direct sales ONLY (exclude delivery-run-generated sales,
       which are already counted via driver_returns below — feedback #33). */
    sale_items AS (
        SELECT BagsSold = ISNULL(SUM(CAST(si.Quantity AS DECIMAL(14,3))), 0)
        FROM   dbo.WaterSales s
        INNER  JOIN dbo.WaterSaleItems si ON si.WaterSaleId = s.WaterSaleId
        WHERE  s.FarmId = @FarmId
           AND s.Status NOT IN ('Cancelled')
           AND ISNULL(s.SourceType, N'') <> N'DeliveryRun'
           AND s.SaleDate >= CAST(@ClosingDate AS DATETIME2)
           AND s.SaleDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    sale_money AS (
        SELECT
            TotalIncome = ISNULL(SUM(TotalAmount), 0),
            CreditSales = ISNULL(SUM(TotalAmount - AmountPaid), 0)
        FROM   dbo.WaterSales
        WHERE  FarmId = @FarmId AND Status NOT IN ('Cancelled')
           AND ISNULL(SourceType, N'') <> N'DeliveryRun'
           AND SaleDate >= CAST(@ClosingDate AS DATETIME2)
           AND SaleDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    /* Customer credit collections ONLY — delivery payments are part of the
       driver-route income, not separate credit collections (#33). */
    payments AS (
        SELECT CustomerCollections = ISNULL(SUM(Amount), 0)
        FROM   dbo.WaterPayments
        WHERE  FarmId = @FarmId
           AND ISNULL(SourceType, N'') <> N'DeliveryRun'
           AND PaymentDate >= CAST(@ClosingDate AS DATETIME2)
           AND PaymentDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    /* Driver-route activity. Bags + money come from approved+draft returns
       so the closing can preview the totals before approval. */
    driver_returns AS (
        SELECT
            BagsReturned       = ISNULL(SUM(CAST(BagsReturned AS DECIMAL(14,3))), 0),
            BagsDamaged        = ISNULL(SUM(CAST(BagsDamaged  AS DECIMAL(14,3))), 0),
            DriverBagsSold     = ISNULL(SUM(CAST(BagsSold AS DECIMAL(14,3))), 0),
            DriverTotalIncome  = ISNULL(SUM(CashCollected + MoMoCollected + BankCollected + CreditSalesAmount), 0),
            DriverCreditSales  = ISNULL(SUM(CreditSalesAmount), 0)
        FROM   dbo.WaterDriverReturns
        WHERE  FarmId = @FarmId
           AND Status IN ('Draft', 'Approved')
           AND ReturnDate >= CAST(@ClosingDate AS DATETIME2)
           AND ReturnDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    shortages AS (
        SELECT DriverShortagesTotal = ISNULL(SUM(ShortageAmount), 0)
        FROM   dbo.WaterDriverShortages
        WHERE  FarmId = @FarmId
           AND ShortageDate >= CAST(@ClosingDate AS DATETIME2)
           AND ShortageDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    raw_spend AS (
        SELECT RawMaterialSpendToday = ISNULL(SUM(TotalCost), 0)
        FROM   dbo.WaterRawMaterialPurchases
        WHERE  FarmId = @FarmId
           AND PurchaseDate >= CAST(@ClosingDate AS DATETIME2)
           AND PurchaseDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    closing_stock AS (
        SELECT ClosingStockBags = ISNULL(SUM(CAST(Quantity AS DECIMAL(14,3))), 0)
        FROM   dbo.WaterStockTransactions
        WHERE  FarmId = @FarmId
    )
    SELECT
        prod.BagsProduced,
        prod.TotalProductionCost,
        BagsSold     = sale_items.BagsSold + driver_returns.DriverBagsSold,
        TotalIncome  = sale_money.TotalIncome + driver_returns.DriverTotalIncome,
        CreditSales  = sale_money.CreditSales + driver_returns.DriverCreditSales,
        payments.CustomerCollections,
        driver_returns.BagsReturned,
        driver_returns.BagsDamaged,
        shortages.DriverShortagesTotal,
        raw_spend.RawMaterialSpendToday,
        closing_stock.ClosingStockBags,
        TotalExpenses = raw_spend.RawMaterialSpendToday + prod.TotalProductionCost,
        CashAtHand    = (sale_money.TotalIncome + driver_returns.DriverTotalIncome)
                        - (sale_money.CreditSales + driver_returns.DriverCreditSales)
                        + payments.CustomerCollections
                        - raw_spend.RawMaterialSpendToday
    FROM   prod
    CROSS  JOIN sale_items
    CROSS  JOIN sale_money
    CROSS  JOIN payments
    CROSS  JOIN driver_returns
    CROSS  JOIN shortages
    CROSS  JOIN raw_spend
    CROSS  JOIN closing_stock
);
GO
