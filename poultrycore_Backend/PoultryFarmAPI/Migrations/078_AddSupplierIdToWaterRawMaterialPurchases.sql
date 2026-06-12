-- =============================================================================
-- Migration 078: SupplierId on WaterRawMaterialPurchases + propagate to the
--                auto-created linked WaterExpense (SourceType/SourceId/Supplier).
-- =============================================================================
-- "Three Prompts In one powerful please implement all.txt" §1, §4, §10 +
-- Prompt 2 (Populate Clickable Source Links). After this migration:
--
--   * Each raw material purchase row carries SupplierId (FK to WaterSuppliers)
--     in addition to the legacy SupplierName freetext column.
--   * The linked WaterExpense row auto-created by spWaterRawMaterialPurchase_Insert
--     now also carries SourceType = 'RawMaterialPurchase', SourceId = the new
--     purchase id, and the same SupplierId. This is what the Expenses-page
--     Source column reads to render a clickable "Raw Materials & Supplies
--     Purchase" link, and what the Supplier Report joins on.
--   * The Update SP also propagates a changed SupplierId from the purchase
--     row down to the linked expense, so editing the supplier on the purchase
--     keeps the expense in sync.
--   * Existing rows are backfilled: any WaterExpense referenced by a purchase
--     via LinkedWaterExpenseId gets SourceType/SourceId set so old records
--     render the clickable source too (Prompt 2 §10).
--
-- Idempotent. CREATE OR ALTER + COL_LENGTH-guarded ADD + an existence-checked
-- backfill UPDATE.
--
-- Compatibility: the freetext SupplierName column is preserved on the purchase
-- row (the legacy Insert/Update params still accept it and we still write it).
-- New code prefers SupplierId; old code keeps working.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Schema
-- -----------------------------------------------------------------------------
IF COL_LENGTH(N'dbo.WaterRawMaterialPurchases', N'SupplierId') IS NULL
    ALTER TABLE dbo.WaterRawMaterialPurchases ADD SupplierId INT NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE name = N'FK_WaterRawMaterialPurchases_Supplier'
      AND parent_object_id = OBJECT_ID(N'dbo.WaterRawMaterialPurchases')
)
    ALTER TABLE dbo.WaterRawMaterialPurchases
        ADD CONSTRAINT FK_WaterRawMaterialPurchases_Supplier
            FOREIGN KEY (SupplierId) REFERENCES dbo.WaterSuppliers(WaterSupplierId);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_WaterRawMaterialPurchases_Supplier'
      AND object_id = OBJECT_ID(N'dbo.WaterRawMaterialPurchases')
)
    CREATE INDEX IX_WaterRawMaterialPurchases_Supplier
        ON dbo.WaterRawMaterialPurchases (SupplierId)
        WHERE SupplierId IS NOT NULL;
GO

-- -----------------------------------------------------------------------------
-- 2. spWaterRawMaterialPurchase_Insert — accept @SupplierId, write Source* to
--    the auto-created linked expense, copy SupplierId there too.
--    Replaces the body from migration 068.
-- -----------------------------------------------------------------------------
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
    @CreatedBy             NVARCHAR(450) = NULL,
    @SupplierId            INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@Quantity <= 0) BEGIN RAISERROR('Quantity must be > 0.', 16, 1); RETURN; END
    IF (@UnitCost < 0)  BEGIN RAISERROR('UnitCost cannot be negative.', 16, 1); RETURN; END

    DECLARE @TotalCost DECIMAL(14,2) = CAST(@Quantity AS DECIMAL(14,2)) * @UnitCost;
    DECLARE @ItemName NVARCHAR(150);
    SELECT @ItemName = ItemName FROM dbo.WaterRawMaterialItems
    WHERE  WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;

    -- If a SupplierId was supplied but no freetext name, derive the name so
    -- legacy PaidTo / SupplierName columns stay populated.
    IF (@SupplierId IS NOT NULL AND (@SupplierName IS NULL OR @SupplierName = N''))
        SELECT @SupplierName = SupplierName FROM dbo.WaterSuppliers
        WHERE  WaterSupplierId = @SupplierId AND FarmId = @FarmId;

    EXEC dbo.spWaterExpenseCategory_EnsureRawMaterialPurchase @FarmId = @FarmId;
    DECLARE @CatId INT;
    SELECT @CatId = WaterExpenseCategoryId
    FROM   dbo.WaterExpenseCategories
    WHERE  FarmId = @FarmId AND Name = N'Raw Materials / Inventory Purchase';

    DECLARE @CashAccountId INT;
    SELECT TOP 1 @CashAccountId = WaterCashAccountId
    FROM   dbo.WaterCashAccounts
    WHERE  FarmId = @FarmId AND IsActive = 1
    ORDER  BY WaterCashAccountId;

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
        PaymentMethod, AmountPaid, ReceiptUrl, ReceivedByStaffId, Notes, CreatedBy,
        SupplierId
    )
    VALUES (
        @FarmId, @WaterRawMaterialItemId, @SupplierName,
        ISNULL(@PurchaseDate, SYSUTCDATETIME()), @Quantity, @UnitCost,
        @EffectivePaymentMethod, @AmountPaid, @ReceiptUrl, @ReceivedByStaffId, @Notes, @CreatedBy,
        @SupplierId
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    UPDATE dbo.WaterRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity + @Quantity, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterRawMaterialItemId = @WaterRawMaterialItemId AND FarmId = @FarmId;

    -- Auto-create the linked Approved expense with full Source* + SupplierId.
    DECLARE @ExpenseId INT = NULL;
    IF (@CatId IS NOT NULL AND @TotalCost > 0)
    BEGIN
        INSERT INTO dbo.WaterExpenses
            (FarmId, ExpenseDate, WaterExpenseCategoryId, Description, Amount, PaidTo,
             PaymentMethod, WaterCashAccountId, LinkedWaterProductionBatchId,
             Status, Notes, CreatedBy, ApprovedBy, ApprovedAt,
             SupplierId, SourceType, SourceId)
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
             @CreatedBy, @CreatedBy, SYSUTCDATETIME(),
             @SupplierId, N'RawMaterialPurchase', @NewId);

        SET @ExpenseId = CAST(SCOPE_IDENTITY() AS INT);

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

-- -----------------------------------------------------------------------------
-- 3. spWaterRawMaterialPurchase_Update — accept @SupplierId + propagate to the
--    linked expense if present. Replaces the body from migration 060.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialPurchase_Update
    @WaterRawMaterialPurchaseId INT,
    @FarmId        NVARCHAR(450),
    @SupplierName  NVARCHAR(200) = NULL,
    @PurchaseDate  DATETIME2     = NULL,
    @Quantity      DECIMAL(14,3),
    @UnitCost      DECIMAL(14,2),
    @PaymentMethod NVARCHAR(30)  = NULL,
    @AmountPaid    DECIMAL(14,2) = 0,
    @ReceiptUrl    NVARCHAR(500) = NULL,
    @Notes         NVARCHAR(500) = NULL,
    @SupplierId    INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@Quantity <= 0) BEGIN RAISERROR('Quantity must be > 0.', 16, 1); RETURN; END
    IF (@UnitCost < 0)  BEGIN RAISERROR('UnitCost cannot be negative.', 16, 1); RETURN; END

    DECLARE @OldQty DECIMAL(14,3), @ItemId INT, @LinkedExpenseId INT;
    SELECT @OldQty = Quantity, @ItemId = WaterRawMaterialItemId, @LinkedExpenseId = LinkedWaterExpenseId
    FROM   dbo.WaterRawMaterialPurchases
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    IF @OldQty IS NULL
    BEGIN RAISERROR('Purchase %d not found.', 16, 1, @WaterRawMaterialPurchaseId); RETURN; END

    DECLARE @Delta DECIMAL(14,3) = @Quantity - @OldQty;
    IF (@Delta < 0)
    BEGIN
        DECLARE @CurrentStock DECIMAL(14,3) = (
            SELECT CurrentQuantity FROM dbo.WaterRawMaterialItems
            WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId);
        IF (@CurrentStock + @Delta < 0)
        BEGIN
            DECLARE @Msg1 NVARCHAR(400) = CONCAT(
                N'Cannot reduce quantity: only ',
                CONVERT(NVARCHAR(40), @CurrentStock),
                N' units of this item remain in stock. Reverse usages first.');
            RAISERROR(@Msg1, 16, 1);
            RETURN;
        END
    END

    -- Resolve SupplierName from SupplierId if needed so the freetext column
    -- stays consistent (used by reports that haven't been migrated to the join).
    IF (@SupplierId IS NOT NULL AND (@SupplierName IS NULL OR @SupplierName = N''))
        SELECT @SupplierName = SupplierName FROM dbo.WaterSuppliers
        WHERE  WaterSupplierId = @SupplierId AND FarmId = @FarmId;

    BEGIN TRANSACTION;

    UPDATE dbo.WaterRawMaterialPurchases
    SET    SupplierName  = @SupplierName,
           SupplierId    = @SupplierId,
           PurchaseDate  = ISNULL(@PurchaseDate, PurchaseDate),
           Quantity      = @Quantity,
           UnitCost      = @UnitCost,
           PaymentMethod = @PaymentMethod,
           AmountPaid    = @AmountPaid,
           ReceiptUrl    = @ReceiptUrl,
           Notes         = @Notes,
           UpdatedAt     = SYSUTCDATETIME()
    WHERE  WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId AND FarmId = @FarmId;

    IF (@Delta <> 0)
    BEGIN
        UPDATE dbo.WaterRawMaterialItems
        SET    CurrentQuantity = CurrentQuantity + @Delta,
               UpdatedAt       = SYSUTCDATETIME()
        WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId;
    END

    -- Propagate Supplier + cost changes to the linked expense (still active).
    IF (@LinkedExpenseId IS NOT NULL)
    BEGIN
        UPDATE dbo.WaterExpenses
        SET    Amount    = CAST(@Quantity AS DECIMAL(14,2)) * @UnitCost,
               PaidTo    = @SupplierName,
               SupplierId= @SupplierId,
               UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterExpenseId = @LinkedExpenseId
          AND  FarmId         = @FarmId
          AND  IsDeleted      = 0
          AND  Status IN ('Draft','Submitted','Approved');
    END

    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- 4. Backfill: pre-existing linked expenses (created before this migration)
--    have NULL SourceType/SourceId. Populate them so the Expenses-page Source
--    column lights up for old rows too.
-- -----------------------------------------------------------------------------
UPDATE e
SET    e.SourceType = N'RawMaterialPurchase',
       e.SourceId   = p.WaterRawMaterialPurchaseId,
       e.SupplierId = COALESCE(e.SupplierId, p.SupplierId),
       e.UpdatedAt  = SYSUTCDATETIME()
FROM   dbo.WaterExpenses e
INNER  JOIN dbo.WaterRawMaterialPurchases p
        ON p.LinkedWaterExpenseId = e.WaterExpenseId
       AND p.FarmId = e.FarmId
WHERE  e.SourceType IS NULL
  AND  e.IsDeleted = 0;
GO

PRINT '078_AddSupplierIdToWaterRawMaterialPurchases.sql complete.';
GO
