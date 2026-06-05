/* =============================================================================
   068_DeliveryReversalClosingReopenCurrencyLossPurchase.sql

   Prompt 2 — Delivery Workflow, Setup Pages, Reversal Logic, Currency Settings,
   Filters, and Reports Completion.  This migration covers everything the
   prompt asks for that needs DB-level changes:

   1. WaterDriverReturn — reverse reconciliation (undo sales/items/payments,
      reverse the LoadReturnIn stock txn, flip the loading back to "Returned"
      and the return back to "Draft" so the user can fix and re-approve).
   2. WaterVehicleLoading — Reload/EditLoad: reverse old LoadOut stock txns
      and apply the new ones in one atomic transaction.
   3. WaterLossRecord — Update + Unapprove SPs (so Pending can be edited and
      Approved can be unapproved with audit). LossType + SourceType columns.
   4. WaterDailyClosing — Reopen + Resubmit with SupersededByClosingId,
      IsActive, ReopenedBy/At/Reason columns; only one active closing per
      day per farm (filtered unique index).
   5. WaterRawMaterialPurchase — Insert now also creates a linked
      Approved WaterExpenses row. Delete cancels it.
   6. Farms — currency settings columns + spCompany_UpdateCurrency.

   Idempotent: COL_LENGTH / OBJECT_ID guards everywhere.
   ============================================================================= */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- 1. Farms — currency settings
-- =============================================================================
IF COL_LENGTH('dbo.Farms', 'CurrencyCode') IS NULL
BEGIN
    PRINT 'Adding Farms.CurrencyCode';
    ALTER TABLE dbo.Farms
        ADD CurrencyCode NVARCHAR(10) NOT NULL
            CONSTRAINT DF_Farms_CurrencyCode DEFAULT (N'GHS') WITH VALUES;
END
GO
IF COL_LENGTH('dbo.Farms', 'CurrencySymbol') IS NULL
BEGIN
    PRINT 'Adding Farms.CurrencySymbol';
    ALTER TABLE dbo.Farms
        ADD CurrencySymbol NVARCHAR(10) NOT NULL
            CONSTRAINT DF_Farms_CurrencySymbol DEFAULT (N'GHC') WITH VALUES;
END
GO
IF COL_LENGTH('dbo.Farms', 'ShowCurrencySymbol') IS NULL
BEGIN
    PRINT 'Adding Farms.ShowCurrencySymbol';
    ALTER TABLE dbo.Farms
        ADD ShowCurrencySymbol BIT NOT NULL
            CONSTRAINT DF_Farms_ShowCurrencySymbol DEFAULT (1) WITH VALUES;
END
GO

CREATE OR ALTER PROCEDURE dbo.spCompany_UpdateCurrency
    @FarmId             NVARCHAR(450),
    @CurrencyCode       NVARCHAR(10),
    @CurrencySymbol     NVARCHAR(10),
    @ShowCurrencySymbol BIT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.Farms
    SET    CurrencyCode       = ISNULL(NULLIF(@CurrencyCode,   N''), CurrencyCode),
           CurrencySymbol     = ISNULL(NULLIF(@CurrencySymbol, N''), CurrencySymbol),
           ShowCurrencySymbol = ISNULL(@ShowCurrencySymbol, ShowCurrencySymbol),
           UpdatedAt          = SYSUTCDATETIME()
    WHERE  Id = @FarmId;

    SELECT Id, Name, CurrencyCode, CurrencySymbol, ShowCurrencySymbol
    FROM   dbo.Farms
    WHERE  Id = @FarmId;
END
GO

-- =============================================================================
-- 2. WaterLossRecords — SourceType / SourceId + Update + Unapprove SPs
-- =============================================================================
IF COL_LENGTH('dbo.WaterLossRecords', 'SourceType') IS NULL
BEGIN
    ALTER TABLE dbo.WaterLossRecords
        ADD SourceType NVARCHAR(40) NULL;
END
GO
IF COL_LENGTH('dbo.WaterLossRecords', 'SourceId') IS NULL
BEGIN
    ALTER TABLE dbo.WaterLossRecords
        ADD SourceId INT NULL;
END
GO
IF COL_LENGTH('dbo.WaterLossRecords', 'UnapprovedBy') IS NULL
BEGIN
    ALTER TABLE dbo.WaterLossRecords
        ADD UnapprovedBy NVARCHAR(450) NULL,
            UnapprovedAt DATETIME2     NULL,
            UnapproveReason NVARCHAR(500) NULL;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterLossRecord_Update
    @WaterLossRecordId   INT,
    @FarmId              NVARCHAR(450),
    @LossDate            DATETIME2,
    @LossType            NVARCHAR(40),
    @WaterProductId      INT           = NULL,
    @QuantityBags        DECIMAL(14,3) = 0,
    @QuantitySachets     DECIMAL(14,3) = 0,
    @EstimatedValue      DECIMAL(14,2) = 0,
    @ResponsibleStaffId  INT           = NULL,
    @Reason              NVARCHAR(500) = NULL,
    @Notes               NVARCHAR(1000)= NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Pending only — Approved must be Unapprove-d first.
    IF NOT EXISTS (SELECT 1 FROM dbo.WaterLossRecords
                   WHERE WaterLossRecordId = @WaterLossRecordId
                     AND FarmId = @FarmId
                     AND Status IN ('Pending','Draft','Reopened'))
    BEGIN
        RAISERROR('Loss record cannot be edited from its current status. Unapprove it first.', 16, 1);
        RETURN;
    END

    UPDATE dbo.WaterLossRecords
    SET    LossDate           = @LossDate,
           LossType           = @LossType,
           WaterProductId     = @WaterProductId,
           QuantityBags       = @QuantityBags,
           QuantitySachets    = @QuantitySachets,
           EstimatedValue     = @EstimatedValue,
           ResponsibleStaffId = @ResponsibleStaffId,
           Reason             = @Reason,
           Notes              = @Notes,
           UpdatedAt          = SYSUTCDATETIME()
    WHERE  WaterLossRecordId = @WaterLossRecordId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterLossRecord_Unapprove
    @WaterLossRecordId  INT,
    @FarmId             NVARCHAR(450),
    @UnapprovedBy       NVARCHAR(450) = NULL,
    @Reason             NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Only Approved → Reopened.
    UPDATE dbo.WaterLossRecords
    SET    Status         = 'Reopened',
           UnapprovedBy   = @UnapprovedBy,
           UnapprovedAt   = SYSUTCDATETIME(),
           UnapproveReason = @Reason,
           UpdatedAt      = SYSUTCDATETIME()
    WHERE  WaterLossRecordId = @WaterLossRecordId
      AND  FarmId = @FarmId
      AND  Status = 'Approved';

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Loss record is not Approved (or not found).', 16, 1);
        RETURN;
    END

    SELECT WaterLossRecordId, Status, UnapprovedBy, UnapprovedAt
    FROM   dbo.WaterLossRecords
    WHERE  WaterLossRecordId = @WaterLossRecordId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- 3. WaterDailyClosings — Reopen / Resubmit support
-- =============================================================================
IF COL_LENGTH('dbo.WaterDailyClosings', 'IsActive') IS NULL
BEGIN
    ALTER TABLE dbo.WaterDailyClosings
        ADD IsActive BIT NOT NULL
            CONSTRAINT DF_WaterDailyClosings_IsActive DEFAULT (1) WITH VALUES;
END
GO
IF COL_LENGTH('dbo.WaterDailyClosings', 'SupersededByClosingId') IS NULL
BEGIN
    ALTER TABLE dbo.WaterDailyClosings
        ADD SupersededByClosingId INT          NULL,
            ReopenedBy            NVARCHAR(450) NULL,
            ReopenedAt            DATETIME2     NULL,
            ReopenReason          NVARCHAR(500) NULL;
END
GO

-- Only one ACTIVE closing per farm+date. Filtered index because existing
-- inactive (superseded) rows must remain in history.
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_WaterDailyClosings_ActivePerFarmDate'
                 AND object_id = OBJECT_ID('dbo.WaterDailyClosings'))
BEGIN
    CREATE UNIQUE INDEX UX_WaterDailyClosings_ActivePerFarmDate
        ON dbo.WaterDailyClosings (FarmId, ClosingDate)
        WHERE IsActive = 1;
END
GO

-- Reopen: mark the active closing inactive (Reopened) and let the user submit
-- a fresh one for the same date. Old rows are kept for audit.
CREATE OR ALTER PROCEDURE dbo.spWaterDailyClosing_Reopen
    @WaterDailyClosingId INT,
    @FarmId              NVARCHAR(450),
    @ReopenedBy          NVARCHAR(450) = NULL,
    @Reason              NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterDailyClosings
    SET    Status       = 'Reopened',
           IsActive     = 0,
           ReopenedBy   = @ReopenedBy,
           ReopenedAt   = SYSUTCDATETIME(),
           ReopenReason = @Reason,
           UpdatedAt    = SYSUTCDATETIME()
    WHERE  WaterDailyClosingId = @WaterDailyClosingId AND FarmId = @FarmId
       AND IsActive = 1;

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Closing not found or already reopened.', 16, 1);
        RETURN;
    END
END
GO

-- Resubmit: convenience SP that takes a NEW WaterDailyClosingId (already
-- inserted via the existing Insert) and links the previous active closing as
-- its predecessor via SupersededByClosingId. Use after spWaterDailyClosing_Insert.
CREATE OR ALTER PROCEDURE dbo.spWaterDailyClosing_LinkSuperseded
    @WaterDailyClosingId INT,
    @FarmId              NVARCHAR(450),
    @SupersededByClosingId INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterDailyClosings
    SET    SupersededByClosingId = @SupersededByClosingId,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterDailyClosingId = @WaterDailyClosingId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- 4. WaterRawMaterialPurchases — LinkedWaterExpenseId + auto-expense on Insert
-- =============================================================================
IF COL_LENGTH('dbo.WaterRawMaterialPurchases', 'LinkedWaterExpenseId') IS NULL
BEGIN
    ALTER TABLE dbo.WaterRawMaterialPurchases
        ADD LinkedWaterExpenseId INT NULL;
END
GO

-- Helper SP to ensure the 'Raw Materials / Inventory Purchase' category exists.
CREATE OR ALTER PROCEDURE dbo.spWaterExpenseCategory_EnsureRawMaterialPurchase
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.WaterExpenseCategories
                   WHERE FarmId = @FarmId AND Name = N'Raw Materials / Inventory Purchase')
        INSERT INTO dbo.WaterExpenseCategories (FarmId, Name, Description, IsActive)
        VALUES (@FarmId, N'Raw Materials / Inventory Purchase',
                N'Auto-created for raw material purchases.', 1);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialPurchase_Insert
    @FarmId                NVARCHAR(450),
    @WaterRawMaterialItemId INT,
    @SupplierName          NVARCHAR(200) = NULL,
    @PurchaseDate          DATETIME2     = NULL,
    @Quantity              DECIMAL(14,3),
    @UnitCost              DECIMAL(14,2),
    @PaymentMethod         NVARCHAR(30)  = NULL,
    @AmountPaid            DECIMAL(14,2) = 0,
    @ReceiptUrl            NVARCHAR(500) = NULL,
    @ReceivedByStaffId     INT           = NULL,
    @Notes                 NVARCHAR(500) = NULL,
    @CreatedBy             NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@Quantity <= 0) BEGIN RAISERROR('Quantity must be > 0.', 16, 1); RETURN; END
    IF (@UnitCost < 0)  BEGIN RAISERROR('UnitCost cannot be negative.', 16, 1); RETURN; END

    DECLARE @TotalCost DECIMAL(14,2) = CAST(@Quantity AS DECIMAL(14,2)) * @UnitCost;
    DECLARE @ItemName NVARCHAR(150);
    SELECT @ItemName = ItemName FROM dbo.WaterRawMaterialItems
    WHERE WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;

    EXEC dbo.spWaterExpenseCategory_EnsureRawMaterialPurchase @FarmId = @FarmId;
    DECLARE @CatId INT;
    SELECT @CatId = WaterExpenseCategoryId
    FROM   dbo.WaterExpenseCategories
    WHERE  FarmId = @FarmId AND Name = N'Raw Materials / Inventory Purchase';

    -- Default cash account (any active one) so the expense can book against it.
    DECLARE @CashAccountId INT;
    SELECT TOP 1 @CashAccountId = WaterCashAccountId
    FROM   dbo.WaterCashAccounts
    WHERE  FarmId = @FarmId AND IsActive = 1
    ORDER  BY WaterCashAccountId;

    -- Treat empty / unknown PaymentMethod as Cash (or Credit when no cash account).
    DECLARE @EffectivePaymentMethod NVARCHAR(30) =
        CASE
            WHEN @PaymentMethod IN ('Cash','MoMo','Bank','Card','Credit','Mixed')
                THEN @PaymentMethod
            WHEN @CashAccountId IS NULL THEN 'Credit'
            ELSE 'Cash'
        END;

    BEGIN TRANSACTION;

    INSERT INTO dbo.WaterRawMaterialPurchases (
        FarmId, WaterRawMaterialItemId, SupplierName, PurchaseDate, Quantity, UnitCost,
        PaymentMethod, AmountPaid, ReceiptUrl, ReceivedByStaffId, Notes, CreatedBy
    )
    VALUES (
        @FarmId, @WaterRawMaterialItemId, @SupplierName,
        ISNULL(@PurchaseDate, SYSUTCDATETIME()), @Quantity, @UnitCost,
        @EffectivePaymentMethod, @AmountPaid, @ReceiptUrl, @ReceivedByStaffId, @Notes, @CreatedBy
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    UPDATE dbo.WaterRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity + @Quantity, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;

    -- Auto-create the linked Approved expense (idempotent against re-insert is
    -- not relevant here because this is a fresh row). The cash side-effect on
    -- a Cash payment is handled inline: we book a CashOut row and update the
    -- cash account balance. For Credit purchases we skip the cash side.
    DECLARE @ExpenseId INT = NULL;
    IF (@CatId IS NOT NULL AND @TotalCost > 0)
    BEGIN
        INSERT INTO dbo.WaterExpenses
            (FarmId, ExpenseDate, WaterExpenseCategoryId, Description, Amount, PaidTo,
             PaymentMethod, WaterCashAccountId, LinkedWaterProductionBatchId,
             Status, Notes, CreatedBy, ApprovedBy, ApprovedAt)
        VALUES
            (@FarmId, ISNULL(@PurchaseDate, SYSUTCDATETIME()), @CatId,
             CONCAT(N'Raw material purchase: ', ISNULL(@ItemName, N'item #' + CAST(@WaterRawMaterialItemId AS NVARCHAR(20))),
                    N' (', CAST(@Quantity AS NVARCHAR(30)), N' units)'),
             @TotalCost, @SupplierName,
             @EffectivePaymentMethod,
             CASE WHEN @EffectivePaymentMethod = 'Credit' THEN NULL ELSE @CashAccountId END,
             NULL,
             'Approved',
             N'Auto-created from raw material purchase.',
             @CreatedBy, @CreatedBy, SYSUTCDATETIME());

        SET @ExpenseId = CAST(SCOPE_IDENTITY() AS INT);

        -- Mirror the cash impact when not Credit.
        IF (@EffectivePaymentMethod <> 'Credit' AND @CashAccountId IS NOT NULL)
        BEGIN
            INSERT INTO dbo.WaterCashTransactions (
                FarmId, WaterCashAccountId, TransactionDate, TransactionType,
                SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
            )
            VALUES (
                @FarmId, @CashAccountId, ISNULL(@PurchaseDate, SYSUTCDATETIME()), 'CashOut',
                'Expense', @ExpenseId, -@TotalCost,
                CONCAT(N'Raw material purchase #', @NewId),
                @CreatedBy, @CreatedBy, SYSUTCDATETIME()
            );

            UPDATE dbo.WaterCashAccounts
            SET    CurrentBalance = CurrentBalance - @TotalCost,
                   UpdatedAt = SYSUTCDATETIME()
            WHERE  WaterCashAccountId = @CashAccountId;
        END

        UPDATE dbo.WaterRawMaterialPurchases
        SET    LinkedWaterExpenseId = @ExpenseId
        WHERE  WaterRawMaterialPurchaseId = @NewId;
    END

    COMMIT TRANSACTION;

    SELECT @NewId;
END
GO

-- Helper to cancel the linked expense when the purchase row is deleted later.
CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialPurchase_CancelLinkedExpense
    @WaterRawMaterialPurchaseId INT,
    @FarmId                     NVARCHAR(450),
    @CancelledBy                NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ExpenseId INT, @Amount DECIMAL(14,2),
            @Payment NVARCHAR(30), @CashAccountId INT;
    SELECT @ExpenseId = e.WaterExpenseId, @Amount = e.Amount,
           @Payment = e.PaymentMethod, @CashAccountId = e.WaterCashAccountId
    FROM   dbo.WaterRawMaterialPurchases p
    INNER  JOIN dbo.WaterExpenses e ON e.WaterExpenseId = p.LinkedWaterExpenseId
    WHERE  p.WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId
      AND  p.FarmId = @FarmId
      AND  e.IsDeleted = 0
      AND  e.Status IN ('Draft','Submitted','Approved');

    IF @ExpenseId IS NULL RETURN;

    BEGIN TRANSACTION;

    IF (@Payment <> 'Credit' AND @CashAccountId IS NOT NULL)
    BEGIN
        INSERT INTO dbo.WaterCashTransactions (
            FarmId, WaterCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @CashAccountId, SYSUTCDATETIME(), 'Adjustment',
            'Expense', @ExpenseId, @Amount,
            N'Reverse — raw material purchase cancelled.',
            @CancelledBy, @CancelledBy, SYSUTCDATETIME()
        );

        UPDATE dbo.WaterCashAccounts
        SET    CurrentBalance = CurrentBalance + @Amount,
               UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterCashAccountId = @CashAccountId;
    END

    UPDATE dbo.WaterExpenses
    SET    Status    = 'Cancelled',
           UpdatedAt = SYSUTCDATETIME(),
           Notes     = LEFT(ISNULL(Notes, N'') + CHAR(10) +
                            N'Cancelled — raw material purchase cancelled.', 1000)
    WHERE  WaterExpenseId = @ExpenseId;

    COMMIT TRANSACTION;
END
GO

-- =============================================================================
-- 5. WaterDriverReturn — Reverse Reconciliation
-- =============================================================================
-- Undoes everything spWaterDriverReturn_Approve did:
--   * Cancel the per-customer WaterSales (status='Cancelled', IsDeleted=1)
--   * Cancel their WaterPayments
--   * Reverse the LoadReturnIn stock txns (insert Adjust with -qty)
--   * Re-set WaterVehicleLoading.Status to 'Returned' so the user can edit
--     the return.
--   * Flip the return back to Draft so the user can edit + re-approve.
--
-- Idempotent: if the return is already Draft/Cancelled, the SP returns
-- without changing anything.

CREATE OR ALTER PROCEDURE dbo.spWaterDriverReturn_Reverse
    @WaterDriverReturnId INT,
    @FarmId              NVARCHAR(450),
    @ReversedBy          NVARCHAR(450) = NULL,
    @Reason              NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @LoadingId INT;
    SELECT @Status = Status, @LoadingId = WaterVehicleLoadingId
    FROM   dbo.WaterDriverReturns
    WHERE  WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;

    IF @Status IS NULL
    BEGIN RAISERROR('Driver return %d not found.', 16, 1, @WaterDriverReturnId); RETURN; END
    IF @Status <> 'Approved'
    BEGIN RAISERROR('Only Approved driver returns can be reversed. Current status: %s.', 16, 1, @Status); RETURN; END

    BEGIN TRANSACTION;

    -- 1. Cancel sales created from this run (SourceType='DeliveryRun', SourceId=ReturnId).
    DECLARE @SaleId INT, @SaleTotalPaid DECIMAL(14,2);
    DECLARE sale_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT WaterSaleId, AmountPaid
        FROM   dbo.WaterSales
        WHERE  FarmId = @FarmId
          AND  SourceType = 'DeliveryRun'
          AND  SourceId   = @WaterDriverReturnId
          AND  ISNULL(Status, N'') NOT IN ('Cancelled','Reversed');

    OPEN sale_cur;
    FETCH NEXT FROM sale_cur INTO @SaleId, @SaleTotalPaid;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- WaterPayments has no Status column — annotate via Note instead and
        -- leave the row in place so cash totals stay traceable. The sale
        -- being cancelled is what the UI watches.
        UPDATE dbo.WaterPayments
        SET    Note = LEFT(ISNULL(Note, N'') + N' [Reversed — delivery reconciliation reversed]', 500)
        WHERE  FarmId = @FarmId
          AND  WaterSaleId = @SaleId;

        -- Cancel the sale itself.
        UPDATE dbo.WaterSales
        SET    Status      = 'Cancelled',
               UpdatedDate = SYSUTCDATETIME(),
               Notes       = LEFT(ISNULL(Notes, N'') + CHAR(10) + N'Reversed — delivery reconciliation reversed.', 500)
        WHERE  WaterSaleId = @SaleId AND FarmId = @FarmId;

        FETCH NEXT FROM sale_cur INTO @SaleId, @SaleTotalPaid;
    END
    CLOSE sale_cur;
    DEALLOCATE sale_cur;

    -- 2. Reverse the LoadReturnIn stock txns this reconciliation created.
    DECLARE @ReverseNote NVARCHAR(120) =
        CONCAT('Reverse reconciliation — driver return #', @WaterDriverReturnId);

    INSERT INTO dbo.WaterStockTransactions
        (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
    SELECT FarmId, WaterProductId, 'Adjust', -Quantity, NULL, NULL,
           @ReverseNote, @ReversedBy
    FROM   dbo.WaterStockTransactions
    WHERE  FarmId = @FarmId
      AND  TxnType = 'LoadReturnIn'
      AND  Note LIKE CONCAT('Driver return #', @WaterDriverReturnId, '%');

    -- 3. Flip loading back to "Returned" so the user can edit the return.
    UPDATE dbo.WaterVehicleLoadings
    SET    Status = 'Returned', UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterVehicleLoadingId = @LoadingId AND FarmId = @FarmId;

    -- 4. Flip the return back to Draft + record the reversal.
    UPDATE dbo.WaterDriverReturns
    SET    Status         = 'Draft',
           ApprovedBy     = NULL,
           ApprovedAt     = NULL,
           UpdatedAt      = SYSUTCDATETIME(),
           Notes          = LEFT(ISNULL(Notes, N'') + CHAR(10) +
                                 N'Reversed by ' + ISNULL(@ReversedBy, N'') +
                                 N'. Reason: ' + ISNULL(@Reason, N'(none)'), 1000)
    WHERE  WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT WaterDriverReturnId, Status FROM dbo.WaterDriverReturns
    WHERE  WaterDriverReturnId = @WaterDriverReturnId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- 6. WaterVehicleLoading — Reload / Edit Load
-- =============================================================================
-- Reverses old LoadOut stock txns then re-applies new ones. Header columns
-- are updated atomically. Refuses when the loading is past "Returned".
CREATE OR ALTER PROCEDURE dbo.spWaterVehicleLoading_Reload
    @WaterVehicleLoadingId INT,
    @FarmId                NVARCHAR(450),
    @WaterDriverId         INT           = NULL,
    @WaterVehicleId        INT           = NULL,
    @WaterRouteId          INT           = NULL,
    @LoadDate              DATETIME2     = NULL,
    @OpeningCashWithDriver DECIMAL(14,2) = 0,
    @Notes                 NVARCHAR(1000)= NULL,
    @ItemsJson             NVARCHAR(MAX) = NULL,
    @UpdatedBy             NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(30);
    SELECT @Status = Status FROM dbo.WaterVehicleLoadings
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;

    IF @Status IS NULL
    BEGIN RAISERROR('Loading %d not found.', 16, 1, @WaterVehicleLoadingId); RETURN; END
    IF @Status NOT IN ('Draft', 'Loaded')
    BEGIN RAISERROR('Loading cannot be edited from status %s. Reverse reconciliation first.', 16, 1, @Status); RETURN; END

    BEGIN TRANSACTION;

    -- Reverse existing LoadOut stock txns from this loading.
    INSERT INTO dbo.WaterStockTransactions
        (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
    SELECT FarmId, WaterProductId, 'Adjust', -Quantity, UnitCost, NULL,
           CONCAT('Reload — reverse for loading #', @WaterVehicleLoadingId),
           @UpdatedBy
    FROM   dbo.WaterStockTransactions
    WHERE  FarmId = @FarmId
      AND  TxnType = 'LoadOut'
      AND  Note LIKE CONCAT('Vehicle loading #', @WaterVehicleLoadingId, '%');

    -- Update header. NULL coalesces to existing value.
    UPDATE dbo.WaterVehicleLoadings
    SET    WaterDriverId         = ISNULL(@WaterDriverId, WaterDriverId),
           WaterVehicleId        = ISNULL(@WaterVehicleId, WaterVehicleId),
           WaterRouteId          = ISNULL(@WaterRouteId, WaterRouteId),
           LoadDate              = ISNULL(@LoadDate, LoadDate),
           OpeningCashWithDriver = ISNULL(@OpeningCashWithDriver, OpeningCashWithDriver),
           Notes                 = ISNULL(@Notes, Notes),
           UpdatedAt             = SYSUTCDATETIME()
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;

    -- Replace items + re-apply LoadOut for the new lines (only when supplied).
    IF @ItemsJson IS NOT NULL AND LEN(@ItemsJson) > 2
    BEGIN
        DELETE FROM dbo.WaterVehicleLoadingItems
        WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId;

        INSERT INTO dbo.WaterVehicleLoadingItems
            (WaterVehicleLoadingId, WaterProductId, BagsLoaded, UnitPrice)
        SELECT @WaterVehicleLoadingId, j.WaterProductId, j.BagsLoaded, j.UnitPrice
        FROM OPENJSON(@ItemsJson)
        WITH (
            WaterProductId INT             '$.waterProductId',
            BagsLoaded     INT             '$.bagsLoaded',
            UnitPrice      DECIMAL(14,2)   '$.unitPrice'
        ) j
        WHERE j.WaterProductId IS NOT NULL;

        INSERT INTO dbo.WaterStockTransactions
            (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
        SELECT @FarmId, i.WaterProductId, 'LoadOut', -i.BagsLoaded, i.UnitPrice, NULL,
               CONCAT('Vehicle loading #', @WaterVehicleLoadingId, ' (reload)'),
               @UpdatedBy
        FROM   dbo.WaterVehicleLoadingItems i
        WHERE  i.WaterVehicleLoadingId = @WaterVehicleLoadingId;
    END

    COMMIT TRANSACTION;

    SELECT WaterVehicleLoadingId, Status FROM dbo.WaterVehicleLoadings
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- 7. Grants
-- =============================================================================
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'PoultryAppRole' AND type = 'R')
BEGIN
    GRANT EXECUTE ON dbo.spCompany_UpdateCurrency                          TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterLossRecord_Update                          TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterLossRecord_Unapprove                       TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterDailyClosing_Reopen                        TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterDailyClosing_LinkSuperseded                TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterExpenseCategory_EnsureRawMaterialPurchase  TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_Insert                 TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_CancelLinkedExpense    TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterDriverReturn_Reverse                       TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterVehicleLoading_Reload                      TO PoultryAppRole;
END
GO

PRINT '068_DeliveryReversalClosingReopenCurrencyLossPurchase.sql complete.';
GO
