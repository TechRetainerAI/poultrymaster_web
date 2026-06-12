-- =============================================================================
-- 104_ClosingMoMoAndBankBalance.sql  (Feedback, James 2026-06-10:
--   "The Driver shortages are not showing on the closing. The area is there for
--    it to show but it does not show. These are the three main things not
--    flowing to the closing" — Closing stock, Bank balance, Driver shortages.)
--
-- Driver shortages and Closing stock WERE computed (columns DriverShortagesTotal
-- and ClosingStockBags) but the web page read the wrong field names — fixed in
-- the frontend. Bank balance / MoMo balance, however, were NEVER computed or
-- returned by the closing at all, so those tiles were always 0.
--
-- This migration:
--   * Adds MoMoBalance + BankBalance snapshot columns to WaterDailyClosings.
--   * Recreates dbo.fnWaterDailyClosing_LiveTotals (carrying forward every rule
--     from 102 — DeliveryRun de-dup, shortages-from-returns, all-expenses) and
--     adds two informational outputs:
--         MoMoBalance = driver-return MoMoCollected + customer payments paid by
--                       'Mobile Money' for the day.
--         BankBalance = driver-return BankCollected + customer payments paid by
--                       'Bank' for the day.
--     (Storefront WaterSales has no channel split, so it is treated as cash and
--      not attributed to MoMo/Bank. These tiles are informational and do NOT
--      change CashAtHand / TotalExpenses.)
--   * Recreates GetAll / GetById / Submit to surface (Draft = live) and freeze
--     (Submit = snapshot) the two new columns.
-- Idempotent.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.WaterDailyClosings', 'MoMoBalance') IS NULL
    ALTER TABLE dbo.WaterDailyClosings
        ADD MoMoBalance DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDC_MoMoBalance DEFAULT(0);
GO
IF COL_LENGTH('dbo.WaterDailyClosings', 'BankBalance') IS NULL
    ALTER TABLE dbo.WaterDailyClosings
        ADD BankBalance DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDC_BankBalance DEFAULT(0);
GO

-- -----------------------------------------------------------------------------
-- Live aggregation TVF (carries forward 102; adds MoMoBalance + BankBalance).
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
        SELECT
            CustomerCollections = ISNULL(SUM(Amount), 0),
            MoMoPayments = ISNULL(SUM(CASE WHEN PaymentMethod IN (N'Mobile Money', N'MoMo', N'Momo') THEN Amount ELSE 0 END), 0),
            BankPayments = ISNULL(SUM(CASE WHEN PaymentMethod IN (N'Bank', N'Bank Transfer', N'Transfer') THEN Amount ELSE 0 END), 0)
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
            DriverMoMo         = ISNULL(SUM(MoMoCollected), 0),
            DriverBank         = ISNULL(SUM(BankCollected), 0),
            DriverShortages    = ISNULL(SUM(ShortageAmount), 0)
        FROM   dbo.WaterDriverReturns
        WHERE  FarmId = @FarmId AND Status IN ('Draft', 'Approved')
           AND ReturnDate >= CAST(@ClosingDate AS DATETIME2)
           AND ReturnDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    raw_spend AS (
        SELECT RawMaterialSpendToday = ISNULL(SUM(AmountPaid), 0)
        FROM   dbo.WaterRawMaterialPurchases
        WHERE  FarmId = @FarmId
           AND PurchaseDate >= CAST(@ClosingDate AS DATETIME2)
           AND PurchaseDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
    gen_exp AS (
        SELECT GeneralExpenses = ISNULL(SUM(Amount), 0)
        FROM   dbo.WaterExpenses
        WHERE  FarmId = @FarmId AND IsDeleted = 0 AND Status = 'Approved'
           AND ISNULL(SourceType, N'') <> N'RawMaterialPurchase'
           AND ExpenseDate >= CAST(@ClosingDate AS DATETIME2)
           AND ExpenseDate <  DATEADD(DAY, 1, CAST(@ClosingDate AS DATETIME2))
    ),
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
        MoMoBalance  = driver_returns.DriverMoMo + payments.MoMoPayments,
        BankBalance  = driver_returns.DriverBank + payments.BankPayments,
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

-- -----------------------------------------------------------------------------
-- GetAll
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
        MoMoBalance          = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.MoMoBalance, 0)          ELSE c.MoMoBalance          END,
        BankBalance          = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.BankBalance, 0)          ELSE c.BankBalance          END,
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

-- -----------------------------------------------------------------------------
-- GetById
-- -----------------------------------------------------------------------------
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
        MoMoBalance          = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.MoMoBalance, 0)          ELSE c.MoMoBalance          END,
        BankBalance          = CASE WHEN c.Status = 'Draft' THEN ISNULL(lt.BankBalance, 0)          ELSE c.BankBalance          END,
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
-- Submit: freeze snapshot (now incl. MoMoBalance + BankBalance).
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
           MoMoBalance          = ISNULL(lt.MoMoBalance, 0),
           BankBalance          = ISNULL(lt.BankBalance, 0),
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

    EXEC dbo.spWaterDailyClosing_GetById @WaterDailyClosingId = @WaterDailyClosingId, @FarmId = @FarmId;
END
GO

PRINT '104_ClosingMoMoAndBankBalance.sql complete.';
GO
