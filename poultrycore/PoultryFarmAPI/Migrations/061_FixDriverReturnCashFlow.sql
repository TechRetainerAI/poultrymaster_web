/* =============================================================================
   061_FixDriverReturnCashFlow.sql

   James reported a driver returned ₵1,500 in cash and it didn't show up
   anywhere — not on Payments, not on the closing, nowhere. Diagnosis:
   spWaterDriverReturn_Approve (in 041) marks the return approved, books the
   shortage, and returns bags to stock, but it never writes the actual
   CashCollected / MoMoCollected / BankCollected to any cash account. So the
   money is captured on the return row but invisible to every aggregator that
   reads cash from WaterCashTransactions (Cash & Accounts page, closing,
   dashboards).

   Note: WaterCashTransactions.SourceType already documents 'DriverReturn'
   as a valid value (047_AddWaterFinanceTables.sql:128) — the schema author
   intended this; it's a missing implementation, not a design change.

   Fix:
     1. spWaterDriverReturn_Approve: also write up to three WaterCashTransactions
        rows (Cash / MoMo / Bank) into the first active account of each type,
        and update the account balances. Skip zero amounts. Fail loudly if a
        non-zero method has no matching cash account so James knows to set
        one up.
     2. spWaterDriverReturn_Cancel: if the return was already Approved when
        cancelled, reverse those cash transactions.
     3. fnWaterDailyClosing_LiveTotals (from 058): add driver-return BagsSold,
        TotalAccountedFor, and CreditSalesAmount into the closing aggregation
        so the closing reports actually reflect what the drivers brought in.
   ============================================================================= */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. spWaterDriverReturn_Approve — replace with cash-booking version
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_Approve
    @WaterDriverReturnId INT,
    @FarmId NVARCHAR(450),
    @ApprovedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Idempotent: already approved → return current state without re-booking.
    IF EXISTS (SELECT 1 FROM dbo.WaterDriverReturns
               WHERE WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT WaterDriverReturnId, Status, ApprovedBy, ApprovedAt
        FROM dbo.WaterDriverReturns
        WHERE WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @Status NVARCHAR(20), @LoadingId INT,
            @BagsSold INT, @BagsReturned INT, @BagsDamaged INT,
            @CashCollected DECIMAL(14,2), @MoMoCollected DECIMAL(14,2),
            @BankCollected DECIMAL(14,2), @CreditSalesAmount DECIMAL(14,2),
            @ReturnDate DATETIME2;

    SELECT @Status = Status, @LoadingId = WaterVehicleLoadingId,
           @BagsSold = BagsSold, @BagsReturned = BagsReturned, @BagsDamaged = BagsDamaged,
           @CashCollected = CashCollected, @MoMoCollected = MoMoCollected,
           @BankCollected = BankCollected, @CreditSalesAmount = CreditSalesAmount,
           @ReturnDate = ReturnDate
    FROM   dbo.WaterDriverReturns
    WHERE  WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;

    IF @Status IS NULL
    BEGIN RAISERROR('Driver return %d not found.', 16, 1, @WaterDriverReturnId); RETURN; END
    IF @Status <> 'Draft'
    BEGIN RAISERROR('Driver return cannot be approved from status %s.', 16, 1, @Status); RETURN; END

    -- Loading details (product + expected price + driver id for shortage row)
    DECLARE @ProductId INT, @ExpectedPricePerBag DECIMAL(14,2), @DriverId INT;
    SELECT @ProductId = WaterProductId, @ExpectedPricePerBag = ExpectedSellingPricePerBag,
           @DriverId = WaterDriverId
    FROM   dbo.WaterVehicleLoadings WHERE WaterVehicleLoadingId = @LoadingId AND FarmId = @FarmId;

    DECLARE @ExpectedCash    DECIMAL(14,2) = CAST(@BagsSold AS DECIMAL(14,2)) * @ExpectedPricePerBag;
    DECLARE @TotalAccounted  DECIMAL(14,2) = @CashCollected + @MoMoCollected + @BankCollected + @CreditSalesAmount;
    DECLARE @Shortage DECIMAL(14,2) = CASE WHEN @ExpectedCash > @TotalAccounted THEN @ExpectedCash - @TotalAccounted ELSE 0 END;
    DECLARE @Overage  DECIMAL(14,2) = CASE WHEN @TotalAccounted > @ExpectedCash THEN @TotalAccounted - @ExpectedCash ELSE 0 END;

    /* Pre-flight: resolve default accounts (first active of each type) for
       any non-zero method. Bail before any writes if a method has money to
       book but no matching account — better to refuse than silently lose
       the audit trail. */
    DECLARE @CashAcctId INT = NULL, @MoMoAcctId INT = NULL, @BankAcctId INT = NULL;

    IF (@CashCollected > 0)
    BEGIN
        SELECT TOP 1 @CashAcctId = WaterCashAccountId FROM dbo.WaterCashAccounts
        WHERE FarmId = @FarmId AND IsActive = 1 AND AccountType = 'Cash'
        ORDER BY WaterCashAccountId;
        IF @CashAcctId IS NULL
        BEGIN
            RAISERROR('No active Cash account on file. Add one on the Cash & Accounts page before approving driver returns with cash.', 16, 1);
            RETURN;
        END
    END

    IF (@MoMoCollected > 0)
    BEGIN
        SELECT TOP 1 @MoMoAcctId = WaterCashAccountId FROM dbo.WaterCashAccounts
        WHERE FarmId = @FarmId AND IsActive = 1 AND AccountType = 'MoMo'
        ORDER BY WaterCashAccountId;
        IF @MoMoAcctId IS NULL
        BEGIN
            RAISERROR('No active MoMo account on file. Add one on the Cash & Accounts page before approving driver returns with MoMo.', 16, 1);
            RETURN;
        END
    END

    IF (@BankCollected > 0)
    BEGIN
        SELECT TOP 1 @BankAcctId = WaterCashAccountId FROM dbo.WaterCashAccounts
        WHERE FarmId = @FarmId AND IsActive = 1 AND AccountType = 'Bank'
        ORDER BY WaterCashAccountId;
        IF @BankAcctId IS NULL
        BEGIN
            RAISERROR('No active Bank account on file. Add one on the Cash & Accounts page before approving driver returns with bank deposits.', 16, 1);
            RETURN;
        END
    END

    BEGIN TRANSACTION;

    /* 1. Mark return approved + record shortage/overage on the return row. */
    UPDATE dbo.WaterDriverReturns
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME(),
           ShortageAmount = @Shortage, OverageAmount = @Overage
    WHERE  WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;

    /* 2. Mark loading reconciled. */
    UPDATE dbo.WaterVehicleLoadings
    SET    Status = 'Reconciled', UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterVehicleLoadingId = @LoadingId AND FarmId = @FarmId;

    /* 3. Stock back: write LoadReturnIn for the returned bags (positive). */
    IF (@BagsReturned > 0)
    BEGIN
        INSERT INTO dbo.WaterStockTransactions (
            FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy
        )
        VALUES (
            @FarmId, @ProductId, 'LoadReturnIn', @BagsReturned, NULL, NULL,
            CONCAT('Driver return #', @WaterDriverReturnId, ' for loading #', @LoadingId),
            @ApprovedBy
        );
    END

    /* 4. NEW: book each non-zero collection method as a CashIn on the
          default account of that type. SourceType='DriverReturn' so the
          rows trace back to this return. */
    IF (@CashCollected > 0)
    BEGIN
        INSERT INTO dbo.WaterCashTransactions (
            FarmId, WaterCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @CashAcctId, @ReturnDate, 'CashIn',
            'DriverReturn', @WaterDriverReturnId, @CashCollected,
            CONCAT('Driver return #', @WaterDriverReturnId, ' cash'),
            @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
        );
        UPDATE dbo.WaterCashAccounts SET CurrentBalance = CurrentBalance + @CashCollected, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterCashAccountId = @CashAcctId;
    END

    IF (@MoMoCollected > 0)
    BEGIN
        INSERT INTO dbo.WaterCashTransactions (
            FarmId, WaterCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @MoMoAcctId, @ReturnDate, 'CashIn',
            'DriverReturn', @WaterDriverReturnId, @MoMoCollected,
            CONCAT('Driver return #', @WaterDriverReturnId, ' MoMo'),
            @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
        );
        UPDATE dbo.WaterCashAccounts SET CurrentBalance = CurrentBalance + @MoMoCollected, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterCashAccountId = @MoMoAcctId;
    END

    IF (@BankCollected > 0)
    BEGIN
        INSERT INTO dbo.WaterCashTransactions (
            FarmId, WaterCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @BankAcctId, @ReturnDate, 'CashIn',
            'DriverReturn', @WaterDriverReturnId, @BankCollected,
            CONCAT('Driver return #', @WaterDriverReturnId, ' bank'),
            @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
        );
        UPDATE dbo.WaterCashAccounts SET CurrentBalance = CurrentBalance + @BankCollected, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterCashAccountId = @BankAcctId;
    END

    /* 5. If any shortage, insert into WaterDriverShortages for follow-up. */
    IF (@Shortage > 0)
    BEGIN
        INSERT INTO dbo.WaterDriverShortages (
            FarmId, WaterDriverId, WaterVehicleLoadingId, WaterDriverReturnId,
            ShortageDate, ExpectedAmount, ActualAmount, ShortageAmount,
            Reason, Status, Notes
        )
        VALUES (
            @FarmId, @DriverId, @LoadingId, @WaterDriverReturnId,
            SYSUTCDATETIME(), @ExpectedCash, @TotalAccounted, @Shortage,
            NULL, 'Pending', NULL
        );
    END

    COMMIT TRANSACTION;

    SELECT WaterDriverReturnId, Status, ApprovedBy, ApprovedAt,
           ShortageAmount, OverageAmount
    FROM dbo.WaterDriverReturns
    WHERE WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- 2. spWaterDriverReturn_Cancel — reverse the cash bookings if the return
--    was already Approved when cancelled. Idempotent on non-Approved returns.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_Cancel
    @WaterDriverReturnId INT, @FarmId NVARCHAR(450),
    @CancelledBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20);
    SELECT @Status = Status FROM dbo.WaterDriverReturns
    WHERE  WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;

    IF @Status IS NULL
    BEGIN RAISERROR('Driver return %d not found.', 16, 1, @WaterDriverReturnId); RETURN; END
    IF @Status = 'Cancelled' RETURN;

    BEGIN TRANSACTION;

    /* If the return was Approved, reverse the cash account impact. We do this
       by inserting compensating CashOut rows AND adjusting CurrentBalance —
       same shape as spWaterExpense_Cancel uses. We sum existing CashIn rows
       per account so partial manual adjustments are preserved. */
    IF @Status = 'Approved'
    BEGIN
        DECLARE @ReversalRows TABLE (
            WaterCashAccountId INT,
            TotalAmount        DECIMAL(14,2)
        );
        INSERT INTO @ReversalRows (WaterCashAccountId, TotalAmount)
        SELECT WaterCashAccountId, SUM(Amount)
        FROM   dbo.WaterCashTransactions
        WHERE  FarmId = @FarmId
           AND SourceType = 'DriverReturn'
           AND SourceId   = @WaterDriverReturnId
           AND TransactionType = 'CashIn'
        GROUP  BY WaterCashAccountId;

        INSERT INTO dbo.WaterCashTransactions (
            FarmId, WaterCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
        )
        SELECT @FarmId, r.WaterCashAccountId, SYSUTCDATETIME(), 'CashOut',
               'DriverReturn', @WaterDriverReturnId, -r.TotalAmount,
               CONCAT('Reverse driver return #', @WaterDriverReturnId),
               @CancelledBy, @CancelledBy, SYSUTCDATETIME()
        FROM   @ReversalRows r;

        UPDATE a
        SET    a.CurrentBalance = a.CurrentBalance - r.TotalAmount,
               a.UpdatedAt = SYSUTCDATETIME()
        FROM   dbo.WaterCashAccounts a
        INNER  JOIN @ReversalRows r ON r.WaterCashAccountId = a.WaterCashAccountId;

        /* Reverse the stock bring-back too — the bags returned to stock when
           approved are no longer real. */
        DECLARE @LoadingId INT, @BagsReturned INT, @ProductId INT;
        SELECT @LoadingId = dr.WaterVehicleLoadingId, @BagsReturned = dr.BagsReturned
        FROM   dbo.WaterDriverReturns dr WHERE dr.WaterDriverReturnId = @WaterDriverReturnId;
        SELECT @ProductId = WaterProductId
        FROM   dbo.WaterVehicleLoadings WHERE WaterVehicleLoadingId = @LoadingId;

        IF (@BagsReturned > 0)
        BEGIN
            INSERT INTO dbo.WaterStockTransactions (
                FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy
            )
            VALUES (
                @FarmId, @ProductId, 'Adjust', -@BagsReturned, NULL, NULL,
                CONCAT('Cancel driver return #', @WaterDriverReturnId, ' — undo stock bring-back'),
                @CancelledBy
            );
        END
    END

    UPDATE dbo.WaterDriverReturns
    SET    Status = 'Cancelled', UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- 3. fnWaterDailyClosing_LiveTotals — add driver-return aggregation
-- -----------------------------------------------------------------------------
-- Add driver-return BagsSold, TotalAccountedFor, CreditSalesAmount to the
-- closing aggregation. Existing 058 version only summed sales rows from
-- WaterSales + WaterSaleItems, missing all driver-route activity.
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
    /* Storefront / direct sales (WaterSales table) */
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
    /* Customer credit payments (WaterPayments table) */
    payments AS (
        SELECT CustomerCollections = ISNULL(SUM(Amount), 0)
        FROM   dbo.WaterPayments
        WHERE  FarmId = @FarmId
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
        /* Combined bags sold = storefront sales + driver-route sales */
        BagsSold     = sale_items.BagsSold + driver_returns.DriverBagsSold,
        /* Combined income = storefront sales + driver-route accounted-for */
        TotalIncome  = sale_money.TotalIncome + driver_returns.DriverTotalIncome,
        /* Combined credit sales = storefront credit + driver-route credit */
        CreditSales  = sale_money.CreditSales + driver_returns.DriverCreditSales,
        payments.CustomerCollections,
        driver_returns.BagsReturned,
        driver_returns.BagsDamaged,
        shortages.DriverShortagesTotal,
        raw_spend.RawMaterialSpendToday,
        closing_stock.ClosingStockBags,
        TotalExpenses = raw_spend.RawMaterialSpendToday + prod.TotalProductionCost,
        /* Cash at hand: income that wasn't credit, plus customer payments
           on old credit, minus raw materials spend. Same shape as 058. */
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

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'PoultryAppRole' AND type = 'R')
BEGIN
    GRANT EXECUTE ON dbo.spWaterDriverReturn_Approve TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterDriverReturn_Cancel  TO PoultryAppRole;
END
GO

PRINT '061_FixDriverReturnCashFlow.sql complete.';
GO
