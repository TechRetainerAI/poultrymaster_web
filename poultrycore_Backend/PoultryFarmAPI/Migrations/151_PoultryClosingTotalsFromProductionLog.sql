-- =============================================================================
-- Migration 151: daily-closing figures come from the Production Log / Sale
-- =============================================================================
-- The closing showed 0 for Eggs produced, Sold, Income, Production cost,
-- Mortality and Feed — only Expenses was right. Same root cause as the stock
-- reconcile (150): fnPoultryDailyClosing_LiveTotals sourced production from
-- PoultryProductionBatches and sales from PoultryDriverReturns, but this farm
-- records production in dbo.ProductionRecords and sales in dbo.Sale (the log the
-- Production Log / Closing Report use). Re-source those figures accordingly.
-- Expenses, cash-account balances and closing stock are unchanged.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER FUNCTION dbo.fnPoultryDailyClosing_LiveTotals (
    @FarmId NVARCHAR(450), @ClosingDate DATE
)
RETURNS TABLE
AS
RETURN
(
    WITH
    pr AS (   -- production for the day, from the log the farm actually uses
        SELECT EggsProduced = ISNULL(SUM(ISNULL(TotalProduction,0)),0),
               EggsDamaged  = ISNULL(SUM(ISNULL(BrokenEggs,0)),0),
               ProdCost     = ISNULL(SUM(ISNULL(TotalCostOfProduction,0)),0),
               MortalityQty = ISNULL(SUM(ISNULL(Mortality,0)),0),
               FeedUsedQty  = ISNULL(SUM(ISNULL(FeedKg,0)),0)
        FROM   dbo.ProductionRecords
        WHERE  FarmId = @FarmId AND CAST([Date] AS DATE) = @ClosingDate
    ),
    sale AS (  -- sales for the day, from dbo.Sale
        SELECT EggsSold    = ISNULL(SUM(ISNULL(Quantity,0)),0),
               TotalIncome = ISNULL(SUM(ISNULL(TotalAmount,0)),0),
               CreditSales = ISNULL(SUM(CASE WHEN ISNULL(Paid,0) = 0 THEN TotalAmount ELSE 0 END),0),
               CashColl    = ISNULL(SUM(CASE WHEN Paid = 1 THEN TotalAmount ELSE 0 END),0)
        FROM   dbo.Sale
        WHERE  FarmId = @FarmId AND CAST(SaleDate AS DATE) = @ClosingDate
    ),
    stock AS (
        SELECT ClosingStock = ISNULL(SUM(Quantity),0)
        FROM   dbo.PoultryStockTransactions
        WHERE  FarmId = @FarmId AND CAST(CreatedDate AS DATE) <= @ClosingDate
    ),
    pay AS (
        SELECT CustomerCollections = ISNULL(SUM(CAST(Amount AS DECIMAL(18,2))),0)
        FROM   dbo.PoultryPayments
        WHERE  FarmId = @FarmId AND CAST(PaymentDate AS DATE) = @ClosingDate
    ),
    exp AS (
        SELECT TotalExpenses = ISNULL(SUM(CAST(Amount AS DECIMAL(18,2))),0)
        FROM   dbo.Expense
        WHERE  FarmId = TRY_CAST(@FarmId AS UNIQUEIDENTIFIER) AND CAST(ExpenseDate AS DATE) = @ClosingDate
    ),
    bal AS (
        SELECT CashBalance = ISNULL(SUM(CASE WHEN AccountType IN ('Cash')                       THEN CurrentBalance ELSE 0 END),0),
               MoMoBalance = ISNULL(SUM(CASE WHEN AccountType IN ('MoMo','Mobile Money','Momo') THEN CurrentBalance ELSE 0 END),0),
               BankBalance = ISNULL(SUM(CASE WHEN AccountType IN ('Bank','Bank Transfer')       THEN CurrentBalance ELSE 0 END),0)
        FROM   dbo.PoultryCashAccounts
        WHERE  FarmId = @FarmId AND IsActive = 1
    )
    SELECT
        EggsProduced = CAST(pr.EggsProduced AS DECIMAL(18,3)),
        ProdCost     = CAST(pr.ProdCost     AS DECIMAL(18,2)),
        EggsDamaged  = CAST(pr.EggsDamaged  AS DECIMAL(18,3)),
        ClosingStock = CAST(stock.ClosingStock AS DECIMAL(18,3)),
        FeedUsedQty  = CAST(pr.FeedUsedQty  AS DECIMAL(18,3)),
        Mortality    = CAST(pr.MortalityQty AS DECIMAL(18,3)),
        EggsSold     = CAST(sale.EggsSold   AS DECIMAL(18,3)),
        EggsReturned = CAST(0 AS DECIMAL(18,3)),
        TotalIncome  = CAST(sale.TotalIncome AS DECIMAL(18,2)),
        CreditSales  = CAST(sale.CreditSales AS DECIMAL(18,2)),
        CashCollected = CAST(sale.CashColl  AS DECIMAL(18,2)),
        MoMoCollected = CAST(0 AS DECIMAL(18,2)),
        BankCollected = CAST(0 AS DECIMAL(18,2)),
        CustomerCollections = pay.CustomerCollections,
        TotalExpenses = exp.TotalExpenses,
        CashBalance = CAST(bal.CashBalance AS DECIMAL(18,2)),
        MoMoBalance = CAST(bal.MoMoBalance AS DECIMAL(18,2)),
        BankBalance = CAST(bal.BankBalance AS DECIMAL(18,2)),
        CashAtHand  = CAST((sale.TotalIncome - sale.CreditSales) + pay.CustomerCollections - exp.TotalExpenses AS DECIMAL(18,2))
    FROM pr, sale, stock, pay, exp, bal
);
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT SELECT ON dbo.fnPoultryDailyClosing_LiveTotals TO [Techretainer];
GO

PRINT '151_PoultryClosingTotalsFromProductionLog.sql complete.';
GO
