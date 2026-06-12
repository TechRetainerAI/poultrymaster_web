/* =============================================================================
   058_FixWaterDailyClosingLiveAggregation.sql

   Problem (reported by James, 2026-05-25):
     "The numbers are not flowing to the closing page... they all say zeros
      when there's data entered for the day."

   Two root causes, both in 044_AddWaterRawMaterialsDailyClosingStoredProcedures.sql:

   1. spWaterDailyClosing_Insert creates the row with all aggregation fields at 0.
      spWaterDailyClosing_GetAll / _GetById return that empty snapshot verbatim.
      Aggregation only runs inside _Submit, so a Draft closing always shows
      zeros until the manager hits Submit. That is what James was seeing.

   2. Even Submit only counts production batches with Status = 'Approved' and
      driver returns with Status = 'Approved'. If James recorded a batch but
      hasn't approved it yet, his bags don't show up on the closing.

   Fix:
     - Extract the aggregation into one inline TVF, dbo.fnWaterDailyClosing_LiveTotals,
       so the same numbers are produced from GetAll, GetById, and Submit.
     - GetAll / GetById join the TVF for rows still in Draft, returning live
       numbers. Submitted / Approved rows keep their frozen snapshot.
     - Widen the production-batch and driver-return filters to include
       both Draft and Approved (excludes Cancelled / IsDeleted).
   ============================================================================= */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- Inline TVF: live aggregation for a (FarmId, ClosingDate) pair.
-- Returning a single row keeps the join simple.
-- -----------------------------------------------------------------------------
CREATE OR ALTER FUNCTION dbo.fnWaterDailyClosing_LiveTotals (
    @FarmId      NVARCHAR(450),
    @ClosingDate DATE
)
RETURNS TABLE
AS
RETURN
(
    WITH
    /* production: include Draft and Approved (Cancelled / IsDeleted excluded) */
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
    sale_items AS (
        SELECT BagsSold = ISNULL(SUM(CAST(si.Quantity AS DECIMAL(14,3))), 0)
        FROM   dbo.WaterSales s
        INNER  JOIN dbo.WaterSaleItems si ON si.WaterSaleId = s.WaterSaleId
        WHERE  s.FarmId = @FarmId
           AND s.Status NOT IN ('Cancelled')
           AND s.SaleDate >= CAST(@ClosingDate AS DATETIME2)
           AND s.SaleDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    sale_money AS (
        SELECT
            TotalIncome = ISNULL(SUM(TotalAmount), 0),
            CreditSales = ISNULL(SUM(TotalAmount - AmountPaid), 0)
        FROM   dbo.WaterSales
        WHERE  FarmId = @FarmId AND Status NOT IN ('Cancelled')
           AND SaleDate >= CAST(@ClosingDate AS DATETIME2)
           AND SaleDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    payments AS (
        SELECT CustomerCollections = ISNULL(SUM(Amount), 0)
        FROM   dbo.WaterPayments
        WHERE  FarmId = @FarmId
           AND PaymentDate >= CAST(@ClosingDate AS DATETIME2)
           AND PaymentDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    /* driver returns: include Draft and Approved too (was Approved-only) */
    returns AS (
        SELECT
            BagsReturned = ISNULL(SUM(CAST(BagsReturned AS DECIMAL(14,3))), 0),
            BagsDamaged  = ISNULL(SUM(CAST(BagsDamaged  AS DECIMAL(14,3))), 0)
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
    /* ClosingStockBags is not tied to a date; current stock on hand */
    closing_stock AS (
        SELECT ClosingStockBags = ISNULL(SUM(CAST(Quantity AS DECIMAL(14,3))), 0)
        FROM   dbo.WaterStockTransactions
        WHERE  FarmId = @FarmId
    )
    SELECT
        prod.BagsProduced,
        prod.TotalProductionCost,
        sale_items.BagsSold,
        sale_money.TotalIncome,
        sale_money.CreditSales,
        payments.CustomerCollections,
        returns.BagsReturned,
        returns.BagsDamaged,
        shortages.DriverShortagesTotal,
        raw_spend.RawMaterialSpendToday,
        closing_stock.ClosingStockBags,
        /* Total expenses = raw materials bought today + production costs incurred today */
        TotalExpenses = raw_spend.RawMaterialSpendToday + prod.TotalProductionCost,
        /* Best-effort cash at hand: same formula Submit uses */
        CashAtHand    = sale_money.TotalIncome - sale_money.CreditSales
                        + payments.CustomerCollections - raw_spend.RawMaterialSpendToday
    FROM   prod
    CROSS  JOIN sale_items
    CROSS  JOIN sale_money
    CROSS  JOIN payments
    CROSS  JOIN returns
    CROSS  JOIN shortages
    CROSS  JOIN raw_spend
    CROSS  JOIN closing_stock
);
GO

-- -----------------------------------------------------------------------------
-- GetAll: for Draft rows return live aggregation; for non-Draft return snapshot.
-- We enumerate columns explicitly so the C# data reader keeps the same shape.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterDailyClosing_GetAll
    @FarmId NVARCHAR(450),
    @Status NVARCHAR(20) = NULL,
    @FromDate DATE = NULL,
    @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        c.WaterDailyClosingId,
        c.FarmId,
        c.ClosingDate,
        c.OpeningStockBags,
        BagsProduced         = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.BagsProduced, 0)         ELSE c.BagsProduced         END,
        BagsSold             = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.BagsSold, 0)             ELSE c.BagsSold             END,
        BagsReturned         = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.BagsReturned, 0)         ELSE c.BagsReturned         END,
        BagsDamaged          = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.BagsDamaged, 0)          ELSE c.BagsDamaged          END,
        ClosingStockBags     = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.ClosingStockBags, 0)     ELSE c.ClosingStockBags     END,
        TotalIncome          = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.TotalIncome, 0)          ELSE c.TotalIncome          END,
        TotalExpenses        = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.TotalExpenses, 0)        ELSE c.TotalExpenses        END,
        TotalProductionCost  = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.TotalProductionCost, 0)  ELSE c.TotalProductionCost  END,
        CashAtHand           = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.CashAtHand, 0)           ELSE c.CashAtHand           END,
        c.ActualCashCounted,
        CashDifference       = CASE WHEN c.Status = 'Draft' THEN ISNULL(c.ActualCashCounted, 0) - ISNULL(lt.CashAtHand, 0) ELSE c.CashDifference END,
        CreditSales          = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.CreditSales, 0)          ELSE c.CreditSales          END,
        CustomerCollections  = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.CustomerCollections, 0)  ELSE c.CustomerCollections  END,
        DriverShortagesTotal = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.DriverShortagesTotal, 0) ELSE c.DriverShortagesTotal END,
        c.ManagerNotes,
        c.DifferenceReason,
        c.Status,
        c.CreatedBy,
        c.SubmittedBy,
        c.SubmittedAt,
        c.ApprovedBy,
        c.ApprovedAt,
        c.RejectionReason,
        c.CreatedAt,
        c.UpdatedAt
    FROM   dbo.WaterDailyClosings c
    OUTER  APPLY dbo.fnWaterDailyClosing_LiveTotals(c.FarmId, c.ClosingDate) lt
    WHERE  c.FarmId = @FarmId
       AND (@Status   IS NULL OR c.Status = @Status)
       AND (@FromDate IS NULL OR c.ClosingDate >= @FromDate)
       AND (@ToDate   IS NULL OR c.ClosingDate <= @ToDate)
    ORDER  BY c.ClosingDate DESC, c.WaterDailyClosingId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDailyClosing_GetById
    @WaterDailyClosingId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        c.WaterDailyClosingId,
        c.FarmId,
        c.ClosingDate,
        c.OpeningStockBags,
        BagsProduced         = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.BagsProduced, 0)         ELSE c.BagsProduced         END,
        BagsSold             = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.BagsSold, 0)             ELSE c.BagsSold             END,
        BagsReturned         = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.BagsReturned, 0)         ELSE c.BagsReturned         END,
        BagsDamaged          = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.BagsDamaged, 0)          ELSE c.BagsDamaged          END,
        ClosingStockBags     = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.ClosingStockBags, 0)     ELSE c.ClosingStockBags     END,
        TotalIncome          = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.TotalIncome, 0)          ELSE c.TotalIncome          END,
        TotalExpenses        = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.TotalExpenses, 0)        ELSE c.TotalExpenses        END,
        TotalProductionCost  = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.TotalProductionCost, 0)  ELSE c.TotalProductionCost  END,
        CashAtHand           = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.CashAtHand, 0)           ELSE c.CashAtHand           END,
        c.ActualCashCounted,
        CashDifference       = CASE WHEN c.Status = 'Draft' THEN ISNULL(c.ActualCashCounted, 0) - ISNULL(lt.CashAtHand, 0) ELSE c.CashDifference END,
        CreditSales          = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.CreditSales, 0)          ELSE c.CreditSales          END,
        CustomerCollections  = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.CustomerCollections, 0)  ELSE c.CustomerCollections  END,
        DriverShortagesTotal = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.DriverShortagesTotal, 0) ELSE c.DriverShortagesTotal END,
        c.ManagerNotes,
        c.DifferenceReason,
        c.Status,
        c.CreatedBy,
        c.SubmittedBy,
        c.SubmittedAt,
        c.ApprovedBy,
        c.ApprovedAt,
        c.RejectionReason,
        c.CreatedAt,
        c.UpdatedAt
    FROM   dbo.WaterDailyClosings c
    OUTER  APPLY dbo.fnWaterDailyClosing_LiveTotals(c.FarmId, c.ClosingDate) lt
    WHERE  c.WaterDailyClosingId = @WaterDailyClosingId
       AND c.FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- Submit: identical aggregation to the TVF, just freezing the snapshot.
-- Rewritten to read from the TVF so the rules stay in one place.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterDailyClosing_Submit
    @WaterDailyClosingId INT,
    @FarmId NVARCHAR(450),
    @ActualCashCounted DECIMAL(14,2) = NULL,
    @ManagerNotes NVARCHAR(2000) = NULL,
    @DifferenceReason NVARCHAR(500) = NULL,
    @SubmittedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ClosingDate DATE, @Status NVARCHAR(20);
    SELECT @ClosingDate = ClosingDate, @Status = Status
    FROM   dbo.WaterDailyClosings
    WHERE  WaterDailyClosingId = @WaterDailyClosingId AND FarmId = @FarmId;

    IF @ClosingDate IS NULL
    BEGIN RAISERROR('Closing %d not found.', 16, 1, @WaterDailyClosingId); RETURN; END
    IF @Status NOT IN ('Draft', 'Submitted')
    BEGIN RAISERROR('Closing cannot be (re)submitted from status %s.', 16, 1, @Status); RETURN; END

    DECLARE @ActCash DECIMAL(14,2) = ISNULL(@ActualCashCounted, 0);

    BEGIN TRANSACTION;

    UPDATE c
    SET    BagsProduced         = ISNULL(lt.BagsProduced, 0),
           BagsSold             = ISNULL(lt.BagsSold, 0),
           BagsReturned         = ISNULL(lt.BagsReturned, 0),
           BagsDamaged          = ISNULL(lt.BagsDamaged, 0),
           ClosingStockBags     = ISNULL(lt.ClosingStockBags, 0),
           TotalIncome          = ISNULL(lt.TotalIncome, 0),
           TotalExpenses        = ISNULL(lt.TotalExpenses, 0),
           TotalProductionCost  = ISNULL(lt.TotalProductionCost, 0),
           CashAtHand           = ISNULL(lt.CashAtHand, 0),
           ActualCashCounted    = COALESCE(@ActualCashCounted, c.ActualCashCounted),
           CashDifference       = @ActCash - ISNULL(lt.CashAtHand, 0),
           CreditSales          = ISNULL(lt.CreditSales, 0),
           CustomerCollections  = ISNULL(lt.CustomerCollections, 0),
           DriverShortagesTotal = ISNULL(lt.DriverShortagesTotal, 0),
           ManagerNotes         = COALESCE(@ManagerNotes, c.ManagerNotes),
           DifferenceReason     = COALESCE(@DifferenceReason, c.DifferenceReason),
           Status               = 'Submitted',
           SubmittedBy          = @SubmittedBy,
           SubmittedAt          = SYSUTCDATETIME(),
           UpdatedAt            = SYSUTCDATETIME()
    FROM   dbo.WaterDailyClosings c
    OUTER  APPLY dbo.fnWaterDailyClosing_LiveTotals(c.FarmId, c.ClosingDate) lt
    WHERE  c.WaterDailyClosingId = @WaterDailyClosingId
       AND c.FarmId = @FarmId;

    COMMIT TRANSACTION;

    /* Return the freshly-frozen snapshot via the same shape GetById uses. */
    EXEC dbo.spWaterDailyClosing_GetById @WaterDailyClosingId = @WaterDailyClosingId, @FarmId = @FarmId;
END
GO

PRINT '058_FixWaterDailyClosingLiveAggregation.sql complete.';
GO
