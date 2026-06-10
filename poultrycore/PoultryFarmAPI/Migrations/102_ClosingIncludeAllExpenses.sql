-- =============================================================================
-- 102_ClosingIncludeAllExpenses.sql  (Feedback: "the expense isn't showing on
-- the closing", incl. driver-return delivery expenses)
--
-- The daily closing's TotalExpenses only summed raw-material purchases +
-- production cost. General expenses (WaterExpenses: fuel, salaries, balance
-- payments, manual entries) and delivery expenses (WaterDeliveryExpenses: the
-- fuel / chop-money logged on a driver return) never showed.
--
-- This recreation of dbo.fnWaterDailyClosing_LiveTotals:
--   * raw_spend now uses AmountPaid (cash actually paid that day) instead of the
--     full TotalCost — so a later balance payment is its own expense without
--     double counting the purchase.
--   * adds gen_exp   = approved WaterExpenses for the day, EXCLUDING the auto
--     'RawMaterialPurchase' expense (already covered by raw_spend's AmountPaid).
--   * adds delivery_exp = approved WaterDeliveryExpenses on Draft/Approved returns
--     for the day.
--   * TotalExpenses = production cost + raw_spend + gen_exp + delivery_exp.
--   * CashAtHand subtracts the same expense pool.
-- Keeps the #33 DeliveryRun de-dup and #10 shortages-from-returns. Idempotent.
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
        WHERE FarmId = @FarmId AND IsDeleted = 0 AND Status IN ('Draft', 'Approved')
          AND ProductionDate = @ClosingDate
    ),
    sale_items AS (
        SELECT BagsSold = ISNULL(SUM(CAST(si.Quantity AS DECIMAL(14,3))), 0)
        FROM   dbo.WaterSales s
        INNER  JOIN dbo.WaterSaleItems si ON si.WaterSaleId = s.WaterSaleId
        WHERE  s.FarmId = @FarmId AND s.Status NOT IN ('Cancelled')
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
    payments AS (
        SELECT CustomerCollections = ISNULL(SUM(Amount), 0)
        FROM   dbo.WaterPayments
        WHERE  FarmId = @FarmId
           AND ISNULL(SourceType, N'') <> N'DeliveryRun'
           AND PaymentDate >= CAST(@ClosingDate AS DATETIME2)
           AND PaymentDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    driver_returns AS (
        SELECT
            BagsReturned       = ISNULL(SUM(CAST(BagsReturned AS DECIMAL(14,3))), 0),
            BagsDamaged        = ISNULL(SUM(CAST(BagsDamaged  AS DECIMAL(14,3))), 0),
            DriverBagsSold     = ISNULL(SUM(CAST(BagsSold AS DECIMAL(14,3))), 0),
            DriverTotalIncome  = ISNULL(SUM(CashCollected + MoMoCollected + BankCollected + CreditSalesAmount), 0),
            DriverCreditSales  = ISNULL(SUM(CreditSalesAmount), 0),
            DriverShortages    = ISNULL(SUM(ShortageAmount), 0)
        FROM   dbo.WaterDriverReturns
        WHERE  FarmId = @FarmId AND Status IN ('Draft', 'Approved')
           AND ReturnDate >= CAST(@ClosingDate AS DATETIME2)
           AND ReturnDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    -- Raw-material CASH paid that day (not full cost — balance payments are
    -- counted separately as their own expense via gen_exp).
    raw_spend AS (
        SELECT RawMaterialSpendToday = ISNULL(SUM(AmountPaid), 0)
        FROM   dbo.WaterRawMaterialPurchases
        WHERE  FarmId = @FarmId
           AND PurchaseDate >= CAST(@ClosingDate AS DATETIME2)
           AND PurchaseDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    -- General approved expenses (fuel, salaries, balance payments, manual…),
    -- excluding the auto raw-material-purchase expense (already in raw_spend).
    gen_exp AS (
        SELECT GeneralExpenses = ISNULL(SUM(Amount), 0)
        FROM   dbo.WaterExpenses
        WHERE  FarmId = @FarmId AND IsDeleted = 0 AND Status = 'Approved'
           AND ISNULL(SourceType, N'') <> N'RawMaterialPurchase'
           AND ExpenseDate >= CAST(@ClosingDate AS DATETIME2)
           AND ExpenseDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    -- Delivery expenses (fuel / chop money) on the day's Draft/Approved returns.
    delivery_exp AS (
        SELECT DeliveryExpenses = ISNULL(SUM(de.Amount), 0)
        FROM   dbo.WaterDeliveryExpenses de
        INNER  JOIN dbo.WaterDriverReturns dr ON dr.WaterDriverReturnId = de.WaterDriverReturnId
        WHERE  dr.FarmId = @FarmId AND dr.Status IN ('Draft', 'Approved') AND de.IsApproved = 1
           AND dr.ReturnDate >= CAST(@ClosingDate AS DATETIME2)
           AND dr.ReturnDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    closing_stock AS (
        SELECT ClosingStockBags = ISNULL(SUM(CAST(Quantity AS DECIMAL(14,3))), 0)
        FROM   dbo.WaterStockTransactions WHERE FarmId = @FarmId
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
        DriverShortagesTotal = driver_returns.DriverShortages,
        raw_spend.RawMaterialSpendToday,
        closing_stock.ClosingStockBags,
        TotalExpenses = prod.TotalProductionCost + raw_spend.RawMaterialSpendToday
                        + gen_exp.GeneralExpenses + delivery_exp.DeliveryExpenses,
        CashAtHand    = (sale_money.TotalIncome + driver_returns.DriverTotalIncome)
                        - (sale_money.CreditSales + driver_returns.DriverCreditSales)
                        + payments.CustomerCollections
                        - raw_spend.RawMaterialSpendToday
                        - gen_exp.GeneralExpenses
                        - delivery_exp.DeliveryExpenses
    FROM   prod
    CROSS  JOIN sale_items
    CROSS  JOIN sale_money
    CROSS  JOIN payments
    CROSS  JOIN driver_returns
    CROSS  JOIN raw_spend
    CROSS  JOIN gen_exp
    CROSS  JOIN delivery_exp
    CROSS  JOIN closing_stock
);
GO
