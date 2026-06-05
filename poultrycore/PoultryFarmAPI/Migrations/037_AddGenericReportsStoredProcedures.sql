-- =============================================================================
-- Migration 037: Daily Closings + Reports + Dashboard stored procedures
-- =============================================================================
-- Run AFTER 036_AddGenericDailyClosings.sql.
--
-- Daily Closing SPs:
--   * spGenericDailyClosing_Submit  — auto-aggregates everything from the
--                                      immutable tables for the date. The
--                                      manager only enters ActualCashCounted
--                                      and notes.
--   * spGenericDailyClosing_Approve — locks the snapshot.
--   * spGenericDailyClosing_Reject  — sends back for re-submission.
--   * spGenericDailyClosing_Get*    — reads.
--
-- Report SPs (all parameterised by FarmId + date range):
--   * spGenericReport_Dashboard      — one-shot bundle for the dashboard
--                                      (today / week / alerts).
--   * spGenericReport_PeriodPnL      — period totals + P&L numbers.
--   * spGenericReport_SalesByProduct
--   * spGenericReport_SalesByCustomer
--   * spGenericReport_ExpensesByCategory
--   * spGenericReport_InventoryValue
--   * spGenericReport_CashSummary
--
-- All reports query the source-of-truth tables (Sales, Purchases, Expenses,
-- CashTransactions, StockMovements, Customer/Supplier Ledger) and respect
-- Status='Approved' wherever applicable. Drafts / Cancelled / Refunded rows
-- are excluded from totals.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- GenericDailyClosing
-- =============================================================================

-- Get a closing by id.
CREATE OR ALTER PROCEDURE dbo.spGenericDailyClosing_GetById
    @GenericDailyClosingId INT,
    @FarmId                NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT *
    FROM   dbo.GenericDailyClosings
    WHERE  GenericDailyClosingId = @GenericDailyClosingId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericDailyClosing_GetAll
    @FarmId    NVARCHAR(450),
    @FromDate  DATE = NULL,
    @ToDate    DATE = NULL,
    @Status    NVARCHAR(20) = NULL,
    @BranchId  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT *
    FROM   dbo.GenericDailyClosings
    WHERE  FarmId = @FarmId
       AND (@FromDate IS NULL OR ClosingDate >= @FromDate)
       AND (@ToDate   IS NULL OR ClosingDate <= @ToDate)
       AND (@Status   IS NULL OR Status = @Status)
       AND (@BranchId IS NULL OR BranchId = @BranchId)
    ORDER  BY ClosingDate DESC, GenericDailyClosingId DESC;
END
GO

-- Creates the Draft row and immediately auto-aggregates everything.
-- The manager only needs to call this once with ActualCashCounted +
-- notes, then call Submit + Approve.
--
-- @OpeningCash: if NULL, defaults to yesterday's closing's ActualCashCounted
-- where one exists, otherwise the sum of all cash account opening balances.
CREATE OR ALTER PROCEDURE dbo.spGenericDailyClosing_Insert
    @FarmId             NVARCHAR(450),
    @ClosingDate        DATE,
    @BranchId           INT            = NULL,
    @OpeningCash        DECIMAL(14,2)  = NULL,
    @ActualCashCounted  DECIMAL(14,2)  = 0,
    @ManagerNotes       NVARCHAR(2000) = NULL,
    @DifferenceReason   NVARCHAR(500)  = NULL,
    @CreatedBy          NVARCHAR(450)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Guard against duplicates per the unique index.
    IF EXISTS (
        SELECT 1 FROM dbo.GenericDailyClosings
        WHERE  FarmId = @FarmId AND ClosingDate = @ClosingDate
           AND (@BranchId IS NULL OR BranchId = @BranchId)
           AND (BranchId  IS NULL OR @BranchId IS NOT NULL)   -- only matches same NULL-ness
    )
    BEGIN
        RAISERROR('A closing already exists for this farm/branch/date.', 16, 1);
        RETURN;
    END

    -- Default OpeningCash from previous closing if available, else from
    -- cash-account opening balances.
    IF @OpeningCash IS NULL
    BEGIN
        SELECT TOP 1 @OpeningCash = ActualCashCounted
        FROM   dbo.GenericDailyClosings
        WHERE  FarmId = @FarmId AND ClosingDate < @ClosingDate
           AND ((@BranchId IS NULL AND BranchId IS NULL)
                OR BranchId = @BranchId)
           AND Status = 'Approved'
        ORDER  BY ClosingDate DESC;

        IF @OpeningCash IS NULL
        BEGIN
            SELECT @OpeningCash = ISNULL(SUM(OpeningBalance), 0)
            FROM   dbo.GenericCashAccounts WHERE FarmId = @FarmId;
        END
    END

    INSERT INTO dbo.GenericDailyClosings (
        FarmId, BranchId, ClosingDate, OpeningCash,
        ActualCashCounted, ManagerNotes, DifferenceReason,
        Status, CreatedBy
    )
    VALUES (
        @FarmId, @BranchId, @ClosingDate, @OpeningCash,
        @ActualCashCounted, @ManagerNotes, @DifferenceReason,
        'Draft', @CreatedBy
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);
    SELECT @NewId;
END
GO

-- Submit: auto-aggregates the numbers from the immutable tables. Moves
-- Draft → Submitted. Idempotent: re-running on Submitted state is allowed
-- and re-aggregates (so the manager can edit ActualCashCounted then re-Submit).
CREATE OR ALTER PROCEDURE dbo.spGenericDailyClosing_Submit
    @GenericDailyClosingId INT,
    @FarmId                NVARCHAR(450),
    @ActualCashCounted     DECIMAL(14,2)  = NULL,
    @ManagerNotes          NVARCHAR(2000) = NULL,
    @DifferenceReason      NVARCHAR(500)  = NULL,
    @SubmittedBy           NVARCHAR(450)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @ClosingDate DATE, @BranchId INT,
            @OpeningCash DECIMAL(14,2);
    SELECT @Status      = Status,
           @ClosingDate = ClosingDate,
           @BranchId    = BranchId,
           @OpeningCash = OpeningCash
    FROM   dbo.GenericDailyClosings
    WHERE  GenericDailyClosingId = @GenericDailyClosingId AND FarmId = @FarmId;

    IF @Status IS NULL
    BEGIN
        RAISERROR('Daily closing %d not found.', 16, 1, @GenericDailyClosingId);
        RETURN;
    END
    IF @Status NOT IN ('Draft', 'Submitted')
    BEGIN
        RAISERROR('Daily closing cannot be (re-)submitted from status %s.', 16, 1, @Status);
        RETURN;
    END

    DECLARE @DayStart DATETIME2 = CAST(@ClosingDate AS DATETIME2);
    DECLARE @DayEnd   DATETIME2 = DATEADD(DAY, 1, @DayStart);

    -- 1. Total sales (Approved sale TotalAmounts for the date)
    DECLARE @TotalSales DECIMAL(14,2) = ISNULL((
        SELECT SUM(TotalAmount)
        FROM   dbo.GenericSales
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND IsDeleted = 0
           AND SaleDate >= @DayStart AND SaleDate < @DayEnd
           AND (@BranchId IS NULL OR BranchId = @BranchId)
    ), 0);

    -- 2. Credit portion of today's sales (Balance > 0)
    DECLARE @CreditSales DECIMAL(14,2) = ISNULL((
        SELECT SUM(Balance)
        FROM   dbo.GenericSales
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND IsDeleted = 0
           AND SaleDate >= @DayStart AND SaleDate < @DayEnd
           AND (@BranchId IS NULL OR BranchId = @BranchId)
    ), 0);

    -- 3. Customer payments received
    DECLARE @TotalCustomerPayments DECIMAL(14,2) = ISNULL((
        SELECT SUM(Amount)
        FROM   dbo.GenericCustomerPayments
        WHERE  FarmId = @FarmId AND Status = 'Approved'
           AND PaymentDate >= @DayStart AND PaymentDate < @DayEnd
    ), 0);

    -- 4. Approved expenses for the day
    DECLARE @TotalExpenses DECIMAL(14,2) = ISNULL((
        SELECT SUM(Amount)
        FROM   dbo.GenericExpenses
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND IsDeleted = 0
           AND ExpenseDate >= @DayStart AND ExpenseDate < @DayEnd
           AND (@BranchId IS NULL OR BranchId = @BranchId)
    ), 0);

    -- 5. Cash actually paid out on purchases today
    DECLARE @TotalPurchasesPaid DECIMAL(14,2) = ISNULL((
        SELECT SUM(AmountPaid)
        FROM   dbo.GenericPurchases
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND IsDeleted = 0
           AND PurchaseDate >= @DayStart AND PurchaseDate < @DayEnd
           AND (@BranchId IS NULL OR BranchId = @BranchId)
    ), 0);

    -- 6. Supplier payments
    DECLARE @TotalSupplierPayments DECIMAL(14,2) = ISNULL((
        SELECT SUM(Amount)
        FROM   dbo.GenericSupplierPayments
        WHERE  FarmId = @FarmId AND Status = 'Approved'
           AND PaymentDate >= @DayStart AND PaymentDate < @DayEnd
    ), 0);

    -- 7. Total cash in / out (from the immutable cash ledger - the truth)
    DECLARE @TotalCashIn DECIMAL(14,2) = ISNULL((
        SELECT SUM(Amount)
        FROM   dbo.GenericCashTransactions
        WHERE  FarmId = @FarmId
           AND TransactionDate >= @DayStart AND TransactionDate < @DayEnd
           AND Amount > 0
    ), 0);

    DECLARE @TotalCashOut DECIMAL(14,2) = ISNULL((
        SELECT SUM(-Amount)
        FROM   dbo.GenericCashTransactions
        WHERE  FarmId = @FarmId
           AND TransactionDate >= @DayStart AND TransactionDate < @DayEnd
           AND Amount < 0
    ), 0);

    -- 8. Current customer/supplier debt snapshots
    DECLARE @CustomerDebtTotal DECIMAL(14,2) = ISNULL((
        SELECT SUM(CurrentBalance)
        FROM   dbo.GenericCustomers
        WHERE  FarmId = @FarmId AND IsDeleted = 0 AND CurrentBalance > 0
    ), 0);

    DECLARE @SupplierDebtTotal DECIMAL(14,2) = ISNULL((
        SELECT SUM(CurrentBalance)
        FROM   dbo.GenericSuppliers
        WHERE  FarmId = @FarmId AND IsDeleted = 0 AND CurrentBalance > 0
    ), 0);

    -- 9. Approved inventory adjustments for the day
    DECLARE @InventoryAdjustmentsCount INT = ISNULL((
        SELECT COUNT(*)
        FROM   dbo.GenericStockAdjustments
        WHERE  FarmId = @FarmId AND Status = 'Approved'
           AND AdjustmentDate >= @DayStart AND AdjustmentDate < @DayEnd
    ), 0);

    -- 10. Expected cash + difference
    DECLARE @ExpectedCash DECIMAL(14,2) = @OpeningCash + @TotalCashIn - @TotalCashOut;
    DECLARE @ActualCash   DECIMAL(14,2) = ISNULL(@ActualCashCounted, 0);
    DECLARE @CashDiff     DECIMAL(14,2) = @ActualCash - @ExpectedCash;

    BEGIN TRANSACTION;

    UPDATE dbo.GenericDailyClosings
    SET    TotalSales                = @TotalSales,
           TotalCustomerPayments     = @TotalCustomerPayments,
           TotalCashIn               = @TotalCashIn,
           TotalExpenses             = @TotalExpenses,
           TotalPurchasesPaid        = @TotalPurchasesPaid,
           TotalSupplierPayments     = @TotalSupplierPayments,
           TotalPayrollPaid          = 0,                       -- payroll phase deferred
           TotalCashOut              = @TotalCashOut,
           ExpectedCash              = @ExpectedCash,
           ActualCashCounted         = COALESCE(@ActualCashCounted, ActualCashCounted),
           CashDifference            = @CashDiff,
           CreditSales               = @CreditSales,
           CustomerDebtTotal         = @CustomerDebtTotal,
           SupplierDebtTotal         = @SupplierDebtTotal,
           InventoryAdjustmentsCount = @InventoryAdjustmentsCount,
           ManagerNotes              = COALESCE(@ManagerNotes, ManagerNotes),
           DifferenceReason          = COALESCE(@DifferenceReason, DifferenceReason),
           Status                    = 'Submitted',
           SubmittedBy               = @SubmittedBy,
           SubmittedAt               = SYSUTCDATETIME(),
           UpdatedAt                 = SYSUTCDATETIME()
    WHERE  GenericDailyClosingId = @GenericDailyClosingId AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT * FROM dbo.GenericDailyClosings
    WHERE  GenericDailyClosingId = @GenericDailyClosingId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericDailyClosing_Approve
    @GenericDailyClosingId INT,
    @FarmId                NVARCHAR(450),
    @ApprovedBy            NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Idempotent
    IF EXISTS (SELECT 1 FROM dbo.GenericDailyClosings
               WHERE  GenericDailyClosingId = @GenericDailyClosingId
                 AND  FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT GenericDailyClosingId, Status, ApprovedBy, ApprovedAt
        FROM   dbo.GenericDailyClosings
        WHERE  GenericDailyClosingId = @GenericDailyClosingId AND FarmId = @FarmId;
        RETURN;
    END

    UPDATE dbo.GenericDailyClosings
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericDailyClosingId = @GenericDailyClosingId
       AND FarmId = @FarmId
       AND Status = 'Submitted';

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Daily closing cannot be approved (not found or not Submitted).', 16, 1);
        RETURN;
    END

    SELECT GenericDailyClosingId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.GenericDailyClosings
    WHERE  GenericDailyClosingId = @GenericDailyClosingId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericDailyClosing_Reject
    @GenericDailyClosingId INT,
    @FarmId                NVARCHAR(450),
    @RejectionReason       NVARCHAR(500),
    @ApprovedBy            NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericDailyClosings
    SET    Status = 'Rejected', RejectionReason = @RejectionReason,
           ApprovedBy = @ApprovedBy, ApprovedAt = SYSUTCDATETIME(),
           UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericDailyClosingId = @GenericDailyClosingId AND FarmId = @FarmId
       AND Status = 'Submitted';

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Daily closing cannot be rejected (not found or not Submitted).', 16, 1);
        RETURN;
    END
END
GO

-- =============================================================================
-- Reports
-- =============================================================================

-- One-shot dashboard bundle. Returns four result sets:
--   1. Today snapshot (one row)
--   2. Week snapshot (one row)
--   3. Cash account balances list
--   4. Alerts (low-stock count, draft sales count, owing-customers count,
--      owed-supplier count, pending closings count) - one row
-- The C# service stitches them into a single response object.
CREATE OR ALTER PROCEDURE dbo.spGenericReport_Dashboard
    @FarmId  NVARCHAR(450),
    @AsOf    DATETIME2 = NULL    -- "now" by default; clients can request historical snapshots
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME2 = ISNULL(@AsOf, SYSUTCDATETIME());
    DECLARE @TodayStart DATETIME2 = CAST(CAST(@Now AS DATE) AS DATETIME2);
    DECLARE @TodayEnd   DATETIME2 = DATEADD(DAY, 1, @TodayStart);
    DECLARE @WeekStart  DATETIME2 = DATEADD(DAY, -6, @TodayStart);
    DECLARE @YesterdayStart DATETIME2 = DATEADD(DAY, -1, @TodayStart);

    -- =====================================================================
    -- Result set 1: today snapshot
    -- =====================================================================
    DECLARE @TodaySales DECIMAL(14,2) = ISNULL((
        SELECT SUM(TotalAmount) FROM dbo.GenericSales
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND IsDeleted = 0
           AND SaleDate >= @TodayStart AND SaleDate < @TodayEnd), 0);

    DECLARE @TodayExpenses DECIMAL(14,2) = ISNULL((
        SELECT SUM(Amount) FROM dbo.GenericExpenses
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND IsDeleted = 0
           AND ExpenseDate >= @TodayStart AND ExpenseDate < @TodayEnd), 0);

    DECLARE @TodayPurchasesPaid DECIMAL(14,2) = ISNULL((
        SELECT SUM(AmountPaid) FROM dbo.GenericPurchases
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND IsDeleted = 0
           AND PurchaseDate >= @TodayStart AND PurchaseDate < @TodayEnd), 0);

    DECLARE @YesterdaySales DECIMAL(14,2) = ISNULL((
        SELECT SUM(TotalAmount) FROM dbo.GenericSales
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND IsDeleted = 0
           AND SaleDate >= @YesterdayStart AND SaleDate < @TodayStart), 0);

    DECLARE @CashAtHand DECIMAL(14,2) = ISNULL((
        SELECT SUM(CurrentBalance) FROM dbo.GenericCashAccounts
        WHERE  FarmId = @FarmId AND IsActive = 1), 0);

    DECLARE @InventoryValue DECIMAL(14,2) = ISNULL((
        SELECT SUM(CurrentStock * CostPrice) FROM dbo.GenericProducts
        WHERE  FarmId = @FarmId AND IsDeleted = 0 AND TrackInventory = 1), 0);

    DECLARE @CustomerDebt DECIMAL(14,2) = ISNULL((
        SELECT SUM(CurrentBalance) FROM dbo.GenericCustomers
        WHERE  FarmId = @FarmId AND IsDeleted = 0 AND CurrentBalance > 0), 0);

    DECLARE @SupplierDebt DECIMAL(14,2) = ISNULL((
        SELECT SUM(CurrentBalance) FROM dbo.GenericSuppliers
        WHERE  FarmId = @FarmId AND IsDeleted = 0 AND CurrentBalance > 0), 0);

    SELECT
        @TodaySales         AS TodaySales,
        @TodayExpenses      AS TodayExpenses,
        @TodayPurchasesPaid AS TodayPurchasesPaid,
        (@TodaySales - @TodayExpenses) AS TodayGrossProfit,   -- simplification; net profit needs COGS
        @YesterdaySales     AS YesterdaySales,
        @CashAtHand         AS CashAtHand,
        @InventoryValue     AS InventoryValue,
        @CustomerDebt       AS CustomerDebt,
        @SupplierDebt       AS SupplierDebt;

    -- =====================================================================
    -- Result set 2: this-week snapshot (last 7 days inclusive)
    -- =====================================================================
    DECLARE @WeekSales DECIMAL(14,2) = ISNULL((
        SELECT SUM(TotalAmount) FROM dbo.GenericSales
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND IsDeleted = 0
           AND SaleDate >= @WeekStart AND SaleDate < @TodayEnd), 0);

    DECLARE @WeekExpenses DECIMAL(14,2) = ISNULL((
        SELECT SUM(Amount) FROM dbo.GenericExpenses
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND IsDeleted = 0
           AND ExpenseDate >= @WeekStart AND ExpenseDate < @TodayEnd), 0);

    DECLARE @WeekPurchasesPaid DECIMAL(14,2) = ISNULL((
        SELECT SUM(AmountPaid) FROM dbo.GenericPurchases
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND IsDeleted = 0
           AND PurchaseDate >= @WeekStart AND PurchaseDate < @TodayEnd), 0);

    DECLARE @TopSellingDesc NVARCHAR(200) = NULL;
    DECLARE @TopSellingQty  DECIMAL(14,3) = 0;
    SELECT TOP 1
           @TopSellingDesc = COALESCE(p.ProductName, s.ServiceName, i.Description),
           @TopSellingQty  = SUM(i.Quantity)
    FROM   dbo.GenericSaleItems i
    INNER  JOIN dbo.GenericSales sa ON sa.GenericSaleId = i.GenericSaleId
    LEFT   JOIN dbo.GenericProducts p ON p.GenericProductId = i.GenericProductId
    LEFT   JOIN dbo.GenericServices s ON s.GenericServiceId = i.GenericServiceId
    WHERE  sa.FarmId = @FarmId AND sa.Status = 'Approved' AND sa.IsDeleted = 0
       AND sa.SaleDate >= @WeekStart AND sa.SaleDate < @TodayEnd
    GROUP  BY i.GenericProductId, i.GenericServiceId, p.ProductName, s.ServiceName, i.Description
    ORDER  BY SUM(i.Quantity) DESC;

    DECLARE @TopExpenseCategory NVARCHAR(100) = NULL;
    DECLARE @TopExpenseAmount   DECIMAL(14,2) = 0;
    SELECT TOP 1
           @TopExpenseCategory = c.Name,
           @TopExpenseAmount   = SUM(e.Amount)
    FROM   dbo.GenericExpenses e
    INNER  JOIN dbo.GenericExpenseCategories c ON c.GenericExpenseCategoryId = e.GenericExpenseCategoryId
    WHERE  e.FarmId = @FarmId AND e.Status = 'Approved' AND e.IsDeleted = 0
       AND e.ExpenseDate >= @WeekStart AND e.ExpenseDate < @TodayEnd
    GROUP  BY c.Name
    ORDER  BY SUM(e.Amount) DESC;

    SELECT
        @WeekSales          AS WeekSales,
        @WeekExpenses       AS WeekExpenses,
        @WeekPurchasesPaid  AS WeekPurchasesPaid,
        (@WeekSales - @WeekExpenses) AS WeekGrossProfit,
        @TopSellingDesc     AS TopSellingItem,
        @TopSellingQty      AS TopSellingQuantity,
        @TopExpenseCategory AS TopExpenseCategory,
        @TopExpenseAmount   AS TopExpenseAmount;

    -- =====================================================================
    -- Result set 3: cash accounts (live balances)
    -- =====================================================================
    SELECT GenericCashAccountId, AccountName, AccountType, CurrentBalance, IsActive
    FROM   dbo.GenericCashAccounts
    WHERE  FarmId = @FarmId
    ORDER  BY IsActive DESC, AccountName;

    -- =====================================================================
    -- Result set 4: alerts
    -- =====================================================================
    DECLARE @LowStockCount INT = (
        SELECT COUNT(*) FROM dbo.GenericProducts
        WHERE  FarmId = @FarmId AND IsActive = 1 AND IsDeleted = 0
           AND TrackInventory = 1 AND CurrentStock <= MinimumStockAlert
    );
    DECLARE @DraftSalesCount INT = (
        SELECT COUNT(*) FROM dbo.GenericSales
        WHERE  FarmId = @FarmId AND Status = 'Draft' AND IsDeleted = 0
    );
    DECLARE @DraftExpensesCount INT = (
        SELECT COUNT(*) FROM dbo.GenericExpenses
        WHERE  FarmId = @FarmId AND Status IN ('Draft', 'Submitted') AND IsDeleted = 0
    );
    DECLARE @CustomersOwingCount INT = (
        SELECT COUNT(*) FROM dbo.GenericCustomers
        WHERE  FarmId = @FarmId AND IsDeleted = 0 AND CurrentBalance > 0
    );
    DECLARE @SuppliersOwedCount INT = (
        SELECT COUNT(*) FROM dbo.GenericSuppliers
        WHERE  FarmId = @FarmId AND IsDeleted = 0 AND CurrentBalance > 0
    );
    DECLARE @PendingClosingsCount INT = (
        SELECT COUNT(*) FROM dbo.GenericDailyClosings
        WHERE  FarmId = @FarmId AND Status IN ('Draft', 'Submitted')
    );

    SELECT
        @LowStockCount        AS LowStockCount,
        @DraftSalesCount      AS DraftSalesCount,
        @DraftExpensesCount   AS DraftExpensesCount,
        @CustomersOwingCount  AS CustomersOwingCount,
        @SuppliersOwedCount   AS SuppliersOwedCount,
        @PendingClosingsCount AS PendingClosingsCount;
END
GO

-- Period P&L: simple summary numbers for a date range. Net profit here is
-- (TotalSales - TotalExpenses) which is gross-of-COGS profit. A true COGS-
-- aware P&L would need to sum SaleItem.CostAmount; deferred to a later
-- enhancement.
CREATE OR ALTER PROCEDURE dbo.spGenericReport_PeriodPnL
    @FarmId    NVARCHAR(450),
    @FromDate  DATE,
    @ToDate    DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Start DATETIME2 = CAST(@FromDate AS DATETIME2);
    DECLARE @End   DATETIME2 = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME2));

    DECLARE @TotalSales DECIMAL(14,2) = ISNULL((
        SELECT SUM(TotalAmount) FROM dbo.GenericSales
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND IsDeleted = 0
           AND SaleDate >= @Start AND SaleDate < @End), 0);

    DECLARE @TotalExpenses DECIMAL(14,2) = ISNULL((
        SELECT SUM(Amount) FROM dbo.GenericExpenses
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND IsDeleted = 0
           AND ExpenseDate >= @Start AND ExpenseDate < @End), 0);

    DECLARE @TotalPurchasesPaid DECIMAL(14,2) = ISNULL((
        SELECT SUM(AmountPaid) FROM dbo.GenericPurchases
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND IsDeleted = 0
           AND PurchaseDate >= @Start AND PurchaseDate < @End), 0);

    DECLARE @COGS DECIMAL(14,2) = ISNULL((
        SELECT SUM(ISNULL(i.CostAmount, 0) * i.Quantity)
        FROM   dbo.GenericSaleItems i
        INNER  JOIN dbo.GenericSales s ON s.GenericSaleId = i.GenericSaleId
        WHERE  s.FarmId = @FarmId AND s.Status = 'Approved' AND s.IsDeleted = 0
           AND s.SaleDate >= @Start AND s.SaleDate < @End
    ), 0);

    DECLARE @SalesCount INT = (
        SELECT COUNT(*) FROM dbo.GenericSales
        WHERE  FarmId = @FarmId AND Status = 'Approved' AND IsDeleted = 0
           AND SaleDate >= @Start AND SaleDate < @End
    );

    SELECT
        @FromDate           AS PeriodStart,
        @ToDate             AS PeriodEnd,
        @TotalSales         AS TotalIncome,
        @TotalExpenses      AS TotalExpenses,
        @COGS               AS CostOfGoodsSold,
        (@TotalSales - @COGS) AS GrossProfit,
        (@TotalSales - @TotalExpenses) AS NetProfit,
        CASE WHEN @TotalSales > 0 THEN ((@TotalSales - @TotalExpenses) / @TotalSales) * 100 ELSE 0 END AS ProfitMarginPct,
        @TotalPurchasesPaid AS TotalPurchasesPaid,
        @SalesCount         AS SalesCount;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericReport_SalesByProduct
    @FarmId    NVARCHAR(450),
    @FromDate  DATE,
    @ToDate    DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Start DATETIME2 = CAST(@FromDate AS DATETIME2);
    DECLARE @End   DATETIME2 = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME2));

    SELECT i.GenericProductId,
           ISNULL(p.ProductName, '(deleted product)') AS ProductName,
           p.SKU,
           SUM(i.Quantity)   AS TotalQuantity,
           SUM(i.LineTotal)  AS TotalRevenue,
           SUM(ISNULL(i.CostAmount, 0) * i.Quantity) AS TotalCost,
           COUNT(DISTINCT s.GenericSaleId) AS SalesCount
    FROM   dbo.GenericSaleItems i
    INNER  JOIN dbo.GenericSales s ON s.GenericSaleId = i.GenericSaleId
    LEFT   JOIN dbo.GenericProducts p ON p.GenericProductId = i.GenericProductId
    WHERE  s.FarmId = @FarmId AND s.Status = 'Approved' AND s.IsDeleted = 0
       AND s.SaleDate >= @Start AND s.SaleDate < @End
       AND i.ItemType = 'Product'
    GROUP  BY i.GenericProductId, p.ProductName, p.SKU
    ORDER  BY SUM(i.LineTotal) DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericReport_SalesByCustomer
    @FarmId    NVARCHAR(450),
    @FromDate  DATE,
    @ToDate    DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Start DATETIME2 = CAST(@FromDate AS DATETIME2);
    DECLARE @End   DATETIME2 = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME2));

    SELECT s.GenericCustomerId,
           ISNULL(c.CustomerName, '(walk-in / no customer)') AS CustomerName,
           c.PhoneNumber,
           COUNT(*)                AS SalesCount,
           SUM(s.TotalAmount)      AS TotalRevenue,
           SUM(s.AmountPaid)       AS TotalPaid,
           SUM(s.Balance)          AS TotalOutstanding
    FROM   dbo.GenericSales s
    LEFT   JOIN dbo.GenericCustomers c ON c.GenericCustomerId = s.GenericCustomerId
    WHERE  s.FarmId = @FarmId AND s.Status = 'Approved' AND s.IsDeleted = 0
       AND s.SaleDate >= @Start AND s.SaleDate < @End
    GROUP  BY s.GenericCustomerId, c.CustomerName, c.PhoneNumber
    ORDER  BY SUM(s.TotalAmount) DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericReport_ExpensesByCategory
    @FarmId    NVARCHAR(450),
    @FromDate  DATE,
    @ToDate    DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Start DATETIME2 = CAST(@FromDate AS DATETIME2);
    DECLARE @End   DATETIME2 = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME2));

    SELECT c.GenericExpenseCategoryId, c.Name AS CategoryName,
           COUNT(*)         AS ExpenseCount,
           SUM(e.Amount)    AS TotalAmount
    FROM   dbo.GenericExpenses e
    INNER  JOIN dbo.GenericExpenseCategories c ON c.GenericExpenseCategoryId = e.GenericExpenseCategoryId
    WHERE  e.FarmId = @FarmId AND e.Status = 'Approved' AND e.IsDeleted = 0
       AND e.ExpenseDate >= @Start AND e.ExpenseDate < @End
    GROUP  BY c.GenericExpenseCategoryId, c.Name
    ORDER  BY SUM(e.Amount) DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericReport_InventoryValue
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    -- Per-category breakdown
    SELECT ISNULL(c.Name, '(uncategorised)') AS CategoryName,
           c.GenericProductCategoryId,
           COUNT(*) AS ProductCount,
           SUM(p.CurrentStock) AS TotalUnits,
           SUM(p.CurrentStock * p.CostPrice) AS TotalCostValue,
           SUM(p.CurrentStock * p.SellingPrice) AS TotalRetailValue
    FROM   dbo.GenericProducts p
    LEFT   JOIN dbo.GenericProductCategories c ON c.GenericProductCategoryId = p.GenericProductCategoryId
    WHERE  p.FarmId = @FarmId AND p.IsDeleted = 0 AND p.TrackInventory = 1
    GROUP  BY c.GenericProductCategoryId, c.Name
    ORDER  BY SUM(p.CurrentStock * p.CostPrice) DESC;

    -- Farm total (second result set)
    SELECT ISNULL(SUM(CurrentStock * CostPrice), 0)    AS TotalCostValue,
           ISNULL(SUM(CurrentStock * SellingPrice), 0) AS TotalRetailValue,
           COUNT(*)                                    AS ProductCount
    FROM   dbo.GenericProducts
    WHERE  FarmId = @FarmId AND IsDeleted = 0 AND TrackInventory = 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericReport_CashSummary
    @FarmId    NVARCHAR(450),
    @FromDate  DATE,
    @ToDate    DATE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Start DATETIME2 = CAST(@FromDate AS DATETIME2);
    DECLARE @End   DATETIME2 = DATEADD(DAY, 1, CAST(@ToDate AS DATETIME2));

    -- Per-account balances + period activity
    SELECT a.GenericCashAccountId,
           a.AccountName,
           a.AccountType,
           a.CurrentBalance,
           ISNULL((
               SELECT SUM(t.Amount) FROM dbo.GenericCashTransactions t
               WHERE  t.GenericCashAccountId = a.GenericCashAccountId
                  AND t.FarmId = @FarmId
                  AND t.TransactionDate >= @Start AND t.TransactionDate < @End
                  AND t.Amount > 0
           ), 0) AS PeriodCashIn,
           ISNULL((
               SELECT SUM(-t.Amount) FROM dbo.GenericCashTransactions t
               WHERE  t.GenericCashAccountId = a.GenericCashAccountId
                  AND t.FarmId = @FarmId
                  AND t.TransactionDate >= @Start AND t.TransactionDate < @End
                  AND t.Amount < 0
           ), 0) AS PeriodCashOut,
           a.IsActive
    FROM   dbo.GenericCashAccounts a
    WHERE  a.FarmId = @FarmId
    ORDER  BY a.IsActive DESC, a.AccountName;

    -- Farm totals (second result set)
    SELECT ISNULL(SUM(CurrentBalance), 0) AS TotalCashAtHand
    FROM   dbo.GenericCashAccounts
    WHERE  FarmId = @FarmId AND IsActive = 1;
END
GO

PRINT '037_AddGenericReportsStoredProcedures.sql complete.';
GO
