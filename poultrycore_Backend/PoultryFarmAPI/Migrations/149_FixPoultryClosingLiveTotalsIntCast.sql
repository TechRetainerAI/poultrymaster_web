-- =============================================================================
-- Migration 149: fix InvalidCastException in the poultry closing live totals
-- =============================================================================
-- GET /Poultry/daily-closings failed 500 (Int32 -> Decimal): CratesSold /
-- CratesReturned (PoultryDriverReturns) and Mortality.Quantity are INT columns,
-- so their SUM() came back as INT and the reader's GetDecimal threw. Cast those
-- aggregates to DECIMAL. Function-only; identical to 148 otherwise.
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
    prod AS (
        SELECT EggsProduced = ISNULL(SUM(CASE WHEN Status='Approved' THEN QuantityProduced - ISNULL(DamagedQuantity,0) ELSE 0 END),0),
               ProdCost     = ISNULL(SUM(CASE WHEN Status='Approved' THEN TotalCost ELSE 0 END),0)
        FROM   dbo.PoultryProductionBatches
        WHERE  FarmId = @FarmId AND CAST(ProductionDate AS DATE) = @ClosingDate
    ),
    loss AS (
        SELECT EggsDamaged = ISNULL(SUM(QuantityLost),0)
        FROM   dbo.PoultryProductionLoss
        WHERE  FarmId = @FarmId AND CAST(LossDate AS DATE) = @ClosingDate
    ),
    stock AS (
        SELECT ClosingStock = ISNULL(SUM(Quantity),0)
        FROM   dbo.PoultryStockTransactions
        WHERE  FarmId = @FarmId AND CAST(CreatedDate AS DATE) <= @ClosingDate
    ),
    feed AS (
        SELECT FeedUsedQty = ISNULL(SUM(QuantityUsed),0)
        FROM   dbo.PoultryRawMaterialUsage
        WHERE  FarmId = @FarmId AND CAST(UsedDate AS DATE) = @ClosingDate
    ),
    mort AS (
        SELECT Mortality = ISNULL(SUM(CAST(Quantity AS DECIMAL(14,3))),0)   -- 149: Quantity is INT
        FROM   dbo.Mortality
        WHERE  FarmId = @FarmId AND CAST(DateOfDeath AS DATE) = @ClosingDate
    ),
    dr AS (   -- approved driver-return sales for the day
        SELECT EggsSold      = ISNULL(SUM(CAST(CratesSold AS DECIMAL(14,3))),0),      -- 149: INT
               EggsReturned  = ISNULL(SUM(CAST(CratesReturned AS DECIMAL(14,3))),0),  -- 149: INT
               TotalIncome   = ISNULL(SUM(CAST(CashCollected + MoMoCollected + BankCollected + CreditSalesAmount AS DECIMAL(18,2))),0),
               CreditSales   = ISNULL(SUM(CAST(CreditSalesAmount AS DECIMAL(18,2))),0),
               CashCollected = ISNULL(SUM(CAST(CashCollected AS DECIMAL(18,2))),0),
               MoMoCollected = ISNULL(SUM(CAST(MoMoCollected AS DECIMAL(18,2))),0),
               BankCollected = ISNULL(SUM(CAST(BankCollected AS DECIMAL(18,2))),0)
        FROM   dbo.PoultryDriverReturns
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND CAST(ReturnDate AS DATE) = @ClosingDate
    ),
    pay AS (  -- direct customer payments (collections not tied to a counted sale)
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
        EggsProduced = CAST(prod.EggsProduced AS DECIMAL(18,3)),
        ProdCost     = CAST(prod.ProdCost AS DECIMAL(18,2)),
        EggsDamaged  = CAST(loss.EggsDamaged AS DECIMAL(18,3)),
        ClosingStock = CAST(stock.ClosingStock AS DECIMAL(18,3)),
        FeedUsedQty  = CAST(feed.FeedUsedQty AS DECIMAL(18,3)),
        mort.Mortality,
        dr.EggsSold, dr.EggsReturned, dr.TotalIncome, dr.CreditSales,
        dr.CashCollected, dr.MoMoCollected, dr.BankCollected,
        pay.CustomerCollections, exp.TotalExpenses,
        CashBalance = CAST(bal.CashBalance AS DECIMAL(18,2)),
        MoMoBalance = CAST(bal.MoMoBalance AS DECIMAL(18,2)),
        BankBalance = CAST(bal.BankBalance AS DECIMAL(18,2)),
        CashAtHand  = CAST((dr.TotalIncome - dr.CreditSales) + pay.CustomerCollections - exp.TotalExpenses AS DECIMAL(18,2))
    FROM prod, loss, stock, feed, mort, dr, pay, exp, bal
);
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT SELECT ON dbo.fnPoultryDailyClosing_LiveTotals TO [Techretainer];
GO

PRINT '149_FixPoultryClosingLiveTotalsIntCast.sql complete.';
GO
