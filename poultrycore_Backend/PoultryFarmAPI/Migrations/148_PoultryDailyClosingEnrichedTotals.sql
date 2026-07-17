-- =============================================================================
-- Migration 148: enrich the Poultry Daily Closing (parity with Water)
-- =============================================================================
-- The poultry closing showed only 4 figures. Mirror the water closing: a
-- table-valued function computes the day's production + money figures live from
-- the poultry sources (production batches, loss, stock, feed usage, mortality,
-- driver-return sales, customer payments, expenses, cash accounts). GetById /
-- GetAll surface them. Add Reopen / Recreate / UpdateNotes actions to match
-- water. "Enriched now, refine later" — enriched figures are computed live for
-- all statuses (snapshot-on-approve can be tightened later).
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
        SELECT Mortality = ISNULL(SUM(Quantity),0)
        FROM   dbo.Mortality
        WHERE  FarmId = @FarmId AND CAST(DateOfDeath AS DATE) = @ClosingDate
    ),
    dr AS (   -- approved driver-return sales for the day
        SELECT EggsSold      = ISNULL(SUM(CratesSold),0),
               EggsReturned  = ISNULL(SUM(CratesReturned),0),
               TotalIncome   = ISNULL(SUM(CashCollected + MoMoCollected + BankCollected + CreditSalesAmount),0),
               CreditSales   = ISNULL(SUM(CreditSalesAmount),0),
               CashCollected = ISNULL(SUM(CashCollected),0),
               MoMoCollected = ISNULL(SUM(MoMoCollected),0),
               BankCollected = ISNULL(SUM(BankCollected),0)
        FROM   dbo.PoultryDriverReturns
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND CAST(ReturnDate AS DATE) = @ClosingDate
    ),
    pay AS (  -- direct customer payments (collections not tied to a counted sale)
        SELECT CustomerCollections = ISNULL(SUM(Amount),0)
        FROM   dbo.PoultryPayments
        WHERE  FarmId = @FarmId AND CAST(PaymentDate AS DATE) = @ClosingDate
    ),
    exp AS (
        SELECT TotalExpenses = ISNULL(SUM(Amount),0)
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
        prod.EggsProduced, prod.ProdCost,
        loss.EggsDamaged, stock.ClosingStock, feed.FeedUsedQty, mort.Mortality,
        dr.EggsSold, dr.EggsReturned, dr.TotalIncome, dr.CreditSales,
        dr.CashCollected, dr.MoMoCollected, dr.BankCollected,
        pay.CustomerCollections, exp.TotalExpenses,
        bal.CashBalance, bal.MoMoBalance, bal.BankBalance,
        -- Cash at hand = (income - credit) + walk-in collections - expenses (as water).
        CashAtHand = (dr.TotalIncome - dr.CreditSales) + pay.CustomerCollections - exp.TotalExpenses
    FROM prod, loss, stock, feed, mort, dr, pay, exp, bal
);
GO

-- GetById: core figures (live for Draft, stored otherwise) + enriched live totals.
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
        lt.EggsSold, lt.EggsReturned, lt.Mortality, lt.FeedUsedQty,
        lt.TotalIncome, lt.TotalExpenses, lt.CreditSales, lt.CustomerCollections,
        lt.CashCollected, lt.MoMoCollected, lt.BankCollected,
        lt.CashBalance, lt.MoMoBalance, lt.BankBalance
    FROM   dbo.PoultryDailyClosings c
    OUTER  APPLY dbo.fnPoultryDailyClosing_LiveTotals(c.FarmId, c.ClosingDate) lt
    WHERE  c.PoultryDailyClosingId = @PoultryDailyClosingId AND c.FarmId = @FarmId;
END
GO

-- GetAll: same enriched shape so the list can show richer figures too.
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
        lt.EggsSold, lt.EggsReturned, lt.Mortality, lt.FeedUsedQty,
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

-- Reopen: unlock a submitted/approved/rejected closing back to Draft.
CREATE OR ALTER PROCEDURE dbo.spPoultryDailyClosing_Reopen
    @PoultryDailyClosingId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryDailyClosings
    SET    Status='Draft', SubmittedBy=NULL, SubmittedAt=NULL, ApprovedBy=NULL, ApprovedAt=NULL,
           RejectionReason=NULL, UpdatedAt=SYSUTCDATETIME()
    WHERE  PoultryDailyClosingId=@PoultryDailyClosingId AND FarmId=@FarmId;
END
GO

-- Recreate: full reset to a fresh draft for the date (figures recompute live).
CREATE OR ALTER PROCEDURE dbo.spPoultryDailyClosing_Recreate
    @PoultryDailyClosingId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryDailyClosings
    SET    Status='Draft', ActualCashCounted=0, CashDifference=0, ManagerNotes=NULL,
           SubmittedBy=NULL, SubmittedAt=NULL, ApprovedBy=NULL, ApprovedAt=NULL,
           RejectionReason=NULL, UpdatedAt=SYSUTCDATETIME()
    WHERE  PoultryDailyClosingId=@PoultryDailyClosingId AND FarmId=@FarmId;
END
GO

-- UpdateNotes: save actual cash + manager notes without submitting.
CREATE OR ALTER PROCEDURE dbo.spPoultryDailyClosing_UpdateNotes
    @PoultryDailyClosingId INT, @FarmId NVARCHAR(450),
    @ActualCashCounted DECIMAL(14,2) = NULL, @ManagerNotes NVARCHAR(2000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryDailyClosings
    SET    ActualCashCounted = ISNULL(@ActualCashCounted, ActualCashCounted),
           ManagerNotes = @ManagerNotes, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryDailyClosingId=@PoultryDailyClosingId AND FarmId=@FarmId AND Status IN ('Draft','Rejected');
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT SELECT  ON dbo.fnPoultryDailyClosing_LiveTotals TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDailyClosing_GetById     TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDailyClosing_GetAll      TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDailyClosing_Reopen      TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDailyClosing_Recreate    TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDailyClosing_UpdateNotes TO [Techretainer];
END
GO

PRINT '148_PoultryDailyClosingEnrichedTotals.sql complete.';
GO
