-- =============================================================================
-- Migration 152: closing — add Medication used, fix balances, traceable stock
-- =============================================================================
-- Follow-ups on the poultry daily closing (James):
--   * Add "Medication used" (ProductionRecords.TotalMedicationConsumed).
--   * Cash/MoMo/Bank balances showed 0 because account types like 'FarmCashBox'
--     didn't match the exact 'Cash'/'MoMo'/'Bank' strings — match flexibly now
--     (MoMo/Mobile -> MoMo, Bank -> Bank, everything else -> Cash).
--   * "Closing stock 18,559" was the raw stock-ledger sum across all products and
--     couldn't be traced. Make it the cumulative EGG stock as of the date:
--     (eggs produced - broken to date) - (eggs sold to date) — same basis as the
--     Production Log, so it reconciles.
-- Adds lt.MedUsedQty to GetById/GetAll so it reaches the API.
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
    pr AS (   -- production for the day (Production Log)
        SELECT EggsProduced = ISNULL(SUM(ISNULL(TotalProduction,0)),0),
               EggsDamaged  = ISNULL(SUM(ISNULL(BrokenEggs,0)),0),
               ProdCost     = ISNULL(SUM(ISNULL(TotalCostOfProduction,0)),0),
               MortalityQty = ISNULL(SUM(ISNULL(Mortality,0)),0),
               FeedUsedQty  = ISNULL(SUM(ISNULL(FeedKg,0)),0),
               MedUsedQty   = ISNULL(SUM(ISNULL(TotalMedicationConsumed,0)),0)
        FROM   dbo.ProductionRecords
        WHERE  FarmId = @FarmId AND CAST([Date] AS DATE) = @ClosingDate
    ),
    sale AS (  -- sales for the day (dbo.Sale)
        SELECT EggsSold    = ISNULL(SUM(ISNULL(Quantity,0)),0),
               TotalIncome = ISNULL(SUM(ISNULL(TotalAmount,0)),0),
               CreditSales = ISNULL(SUM(CASE WHEN ISNULL(Paid,0) = 0 THEN TotalAmount ELSE 0 END),0),
               CashColl    = ISNULL(SUM(CASE WHEN Paid = 1 THEN TotalAmount ELSE 0 END),0)
        FROM   dbo.Sale
        WHERE  FarmId = @FarmId AND CAST(SaleDate AS DATE) = @ClosingDate
    ),
    egg AS (   -- cumulative egg stock as of the date (traceable "closing stock")
        SELECT ProducedToDate = ISNULL((SELECT SUM(ISNULL(TotalProduction,0) - ISNULL(BrokenEggs,0))
                                        FROM dbo.ProductionRecords WHERE FarmId=@FarmId AND CAST([Date] AS DATE) <= @ClosingDate),0),
               SoldToDate     = ISNULL((SELECT SUM(ISNULL(Quantity,0))
                                        FROM dbo.Sale WHERE FarmId=@FarmId AND CAST(SaleDate AS DATE) <= @ClosingDate),0)
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
    bal AS (   -- flexible account-type matching (e.g. 'FarmCashBox' -> Cash)
        SELECT MoMoBalance = ISNULL(SUM(CASE WHEN AccountType LIKE '%MoMo%' OR AccountType LIKE '%Mobile%' THEN CurrentBalance ELSE 0 END),0),
               BankBalance = ISNULL(SUM(CASE WHEN AccountType LIKE '%Bank%' THEN CurrentBalance ELSE 0 END),0),
               CashBalance = ISNULL(SUM(CASE WHEN AccountType LIKE '%MoMo%' OR AccountType LIKE '%Mobile%' OR AccountType LIKE '%Bank%' THEN 0 ELSE CurrentBalance END),0)
        FROM   dbo.PoultryCashAccounts
        WHERE  FarmId = @FarmId AND IsActive = 1
    )
    SELECT
        EggsProduced = CAST(pr.EggsProduced AS DECIMAL(18,3)),
        ProdCost     = CAST(pr.ProdCost     AS DECIMAL(18,2)),
        EggsDamaged  = CAST(pr.EggsDamaged  AS DECIMAL(18,3)),
        ClosingStock = CAST(egg.ProducedToDate - egg.SoldToDate AS DECIMAL(18,3)),
        FeedUsedQty  = CAST(pr.FeedUsedQty  AS DECIMAL(18,3)),
        MedUsedQty   = CAST(pr.MedUsedQty   AS DECIMAL(18,3)),
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
    FROM pr, sale, egg, pay, exp, bal
);
GO

-- GetById / GetAll: surface lt.MedUsedQty alongside the rest.
CREATE OR ALTER PROCEDURE dbo.spPoultryDailyClosing_GetById
    @PoultryDailyClosingId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        c.PoultryDailyClosingId, c.FarmId, c.ClosingDate,
        QuantityProduced    = CASE WHEN c.Status='Draft' THEN lt.EggsProduced ELSE c.QuantityProduced END,
        QuantityDamaged     = CASE WHEN c.Status='Draft' THEN lt.EggsDamaged  ELSE c.QuantityDamaged  END,
        TotalProductionCost = CASE WHEN c.Status='Draft' THEN lt.ProdCost     ELSE c.TotalProductionCost END,
        ClosingStock        = CASE WHEN c.Status='Draft' THEN lt.ClosingStock ELSE c.ClosingStock END,
        CashAtHand          = lt.CashAtHand,
        c.ActualCashCounted,
        CashDifference      = ISNULL(c.ActualCashCounted,0) - lt.CashAtHand,
        c.ManagerNotes, c.Status, c.RejectionReason,
        c.CreatedBy, c.SubmittedBy, c.SubmittedAt, c.ApprovedBy, c.ApprovedAt, c.CreatedAt, c.UpdatedAt,
        lt.EggsSold, lt.EggsReturned, lt.Mortality, lt.FeedUsedQty, lt.MedUsedQty,
        lt.TotalIncome, lt.TotalExpenses, lt.CreditSales, lt.CustomerCollections,
        lt.CashCollected, lt.MoMoCollected, lt.BankCollected,
        lt.CashBalance, lt.MoMoBalance, lt.BankBalance
    FROM   dbo.PoultryDailyClosings c
    OUTER  APPLY dbo.fnPoultryDailyClosing_LiveTotals(c.FarmId, c.ClosingDate) lt
    WHERE  c.PoultryDailyClosingId = @PoultryDailyClosingId AND c.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDailyClosing_GetAll
    @FarmId NVARCHAR(450), @Status NVARCHAR(20) = NULL, @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        c.PoultryDailyClosingId, c.FarmId, c.ClosingDate,
        QuantityProduced    = CASE WHEN c.Status='Draft' THEN lt.EggsProduced ELSE c.QuantityProduced END,
        QuantityDamaged     = CASE WHEN c.Status='Draft' THEN lt.EggsDamaged  ELSE c.QuantityDamaged  END,
        TotalProductionCost = CASE WHEN c.Status='Draft' THEN lt.ProdCost     ELSE c.TotalProductionCost END,
        ClosingStock        = CASE WHEN c.Status='Draft' THEN lt.ClosingStock ELSE c.ClosingStock END,
        CashAtHand          = lt.CashAtHand,
        c.ActualCashCounted,
        CashDifference      = ISNULL(c.ActualCashCounted,0) - lt.CashAtHand,
        c.ManagerNotes, c.Status, c.RejectionReason,
        c.CreatedBy, c.SubmittedBy, c.SubmittedAt, c.ApprovedBy, c.ApprovedAt, c.CreatedAt, c.UpdatedAt,
        lt.EggsSold, lt.EggsReturned, lt.Mortality, lt.FeedUsedQty, lt.MedUsedQty,
        lt.TotalIncome, lt.TotalExpenses, lt.CreditSales, lt.CustomerCollections,
        lt.CashCollected, lt.MoMoCollected, lt.BankCollected,
        lt.CashBalance, lt.MoMoBalance, lt.BankBalance
    FROM   dbo.PoultryDailyClosings c
    OUTER  APPLY dbo.fnPoultryDailyClosing_LiveTotals(c.FarmId, c.ClosingDate) lt
    WHERE  c.FarmId = @FarmId
       AND (@Status   IS NULL OR c.Status = @Status)
       AND (@FromDate IS NULL OR c.ClosingDate >= @FromDate)
       AND (@ToDate   IS NULL OR c.ClosingDate <= @ToDate)
    ORDER  BY c.ClosingDate DESC, c.PoultryDailyClosingId DESC;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT SELECT  ON dbo.fnPoultryDailyClosing_LiveTotals TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDailyClosing_GetById    TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDailyClosing_GetAll     TO [Techretainer];
END
GO

PRINT '152_PoultryClosingMedicationBalancesStock.sql complete.';
GO
