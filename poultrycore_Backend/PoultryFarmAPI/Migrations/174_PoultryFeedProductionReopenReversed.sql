-- =============================================================================
-- Migration 174: Feed Production — allow EDIT / DELETE / REPOST of a Reversed batch
-- =============================================================================
-- A reversed batch has already had ALL of its side-effects unwound by
-- spPoultryFeedProductionBatch_Reverse (ingredient lots restored, produced feed
-- removed, cash reversed, usage/purchase/cash rows deleted). It therefore carries
-- no live inventory or cash impact and can safely be treated like a draft again.
--
-- This migration relaxes the lifecycle guards so a Reversed batch can be:
--   * EDITED   — reopens it to Draft (clears the reversed/posted audit stamp).
--   * DELETED  — removed outright (lines + costs cascade; nothing else to unwind).
--   * REPOSTED — re-run the posting engine (clears the reversed stamp, -> Posted).
--
-- Posted batches are still protected: they must be reversed before edit/delete.
-- CREATE OR ALTER only — no schema change. Idempotent. Safe to re-run.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- SAVE — now edits Draft OR Reversed. Editing a Reversed batch reopens it to a
-- clean Draft (the reversal/posted audit fields are cleared). Only Posted is blocked.
-- Body identical to migration 169 except the status guard + the reopen reset.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryFeedProductionBatch_Save
    @FarmId              NVARCHAR(450),
    @PoultryFeedProductionBatchId INT = NULL,
    @BatchNumber         NVARCHAR(60)  = NULL,
    @ProductionDate      DATETIME2     = NULL,
    @FinishedFeedItemId  INT,
    @FormulaId           INT           = NULL,
    @QuantityProduced    DECIMAL(14,3),
    @OutputUnit          NVARCHAR(30)  = NULL,
    @Notes               NVARCHAR(500) = NULL,
    @UserId              NVARCHAR(450) = NULL,
    @LinesJson           NVARCHAR(MAX) = NULL,
    @CostsJson           NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    DECLARE @Id INT = @PoultryFeedProductionBatchId;
    IF (@ProductionDate IS NULL) SET @ProductionDate = SYSUTCDATETIME();

    IF (@Id IS NOT NULL AND @Id <> 0)
    BEGIN
        DECLARE @CurStatus NVARCHAR(20);
        SELECT @CurStatus = Status FROM dbo.PoultryFeedProductionBatches
        WHERE PoultryFeedProductionBatchId = @Id AND FarmId = @FarmId;

        IF (@CurStatus IS NULL) BEGIN ROLLBACK TRANSACTION; THROW 51000, 'Feed production batch not found.', 1; END
        IF (@CurStatus = 'Posted') BEGIN ROLLBACK TRANSACTION; THROW 51001, 'Posted batches cannot be edited. Reverse the batch first.', 1; END
    END

    IF (@Id IS NULL OR @Id = 0)
    BEGIN
        -- Auto batch number: FP-<year>-<4-digit sequence> when not supplied.
        IF (@BatchNumber IS NULL OR LTRIM(RTRIM(@BatchNumber)) = '')
        BEGIN
            DECLARE @Yr NVARCHAR(4) = CAST(YEAR(@ProductionDate) AS NVARCHAR(4));
            DECLARE @Seq INT = ISNULL((
                SELECT MAX(TRY_CAST(RIGHT(BatchNumber, 4) AS INT))
                FROM   dbo.PoultryFeedProductionBatches
                WHERE  FarmId = @FarmId AND BatchNumber LIKE 'FP-' + @Yr + '-%'
            ), 0) + 1;
            SET @BatchNumber = 'FP-' + @Yr + '-' + RIGHT('0000' + CAST(@Seq AS NVARCHAR(10)), 4);
        END

        INSERT INTO dbo.PoultryFeedProductionBatches
            (FarmId, BatchNumber, ProductionDate, FinishedFeedItemId, FormulaId, QuantityProduced, OutputUnit, Notes, Status, CreatedBy)
        VALUES (@FarmId, @BatchNumber, @ProductionDate, @FinishedFeedItemId, @FormulaId, @QuantityProduced, @OutputUnit, @Notes, 'Draft', @UserId);
        SET @Id = CAST(SCOPE_IDENTITY() AS INT);
    END
    ELSE
    BEGIN
        -- Draft or Reversed. Editing a Reversed batch reopens it to a clean Draft:
        -- clear the posted/reversed audit stamp so it re-enters the normal flow.
        UPDATE dbo.PoultryFeedProductionBatches
        SET    BatchNumber = ISNULL(NULLIF(LTRIM(RTRIM(@BatchNumber)), ''), BatchNumber),
               ProductionDate = @ProductionDate, FinishedFeedItemId = @FinishedFeedItemId,
               FormulaId = @FormulaId, QuantityProduced = @QuantityProduced, OutputUnit = @OutputUnit,
               Notes = @Notes,
               Status = 'Draft',
               PostedBy = NULL, PostedAt = NULL,
               ReversedBy = NULL, ReversedAt = NULL, ReversalReason = NULL,
               UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryFeedProductionBatchId = @Id AND FarmId = @FarmId;

        DELETE FROM dbo.PoultryFeedProductionBatchLines       WHERE PoultryFeedProductionBatchId = @Id;
        DELETE FROM dbo.PoultryFeedProductionAdditionalCosts  WHERE PoultryFeedProductionBatchId = @Id;
    END

    -- Ingredient lines. Line cost is derived from the source split + unit costs
    -- (client TotalCost is never trusted). Inventory/purchased quantities are
    -- normalised from the source type so downstream posting is unambiguous.
    IF (@LinesJson IS NOT NULL AND LEN(@LinesJson) > 2)
    BEGIN
        INSERT INTO dbo.PoultryFeedProductionBatchLines
            (PoultryFeedProductionBatchId, IngredientItemId, SourceType, QuantityUsed, UnitOfMeasure,
             InventoryQuantityUsed, PurchasedQuantityUsed, InventoryUnitCost, PurchasedUnitCost, UnitCost, TotalCost,
             SupplierId, SupplierName, PurchaseReference, PaymentStatus, AmountPaid, PaidFromCashAccountId, PaymentMethod, SortOrder, Notes)
        SELECT @Id, j.IngredientItemId,
               CASE WHEN j.SourceType IN ('FromInventory','BoughtDuringProduction','MixedSource') THEN j.SourceType ELSE 'FromInventory' END,
               j.QuantityUsed, j.UnitOfMeasure,
               q.InvQty, q.PurQty, ISNULL(j.InventoryUnitCost,0), ISNULL(j.PurchasedUnitCost,0),
               CAST(d.LineTotal / NULLIF(j.QuantityUsed,0) AS DECIMAL(18,4)) AS UnitCost,
               CAST(d.LineTotal AS DECIMAL(14,2)) AS TotalCost,
               j.SupplierId, j.SupplierName, j.PurchaseReference, j.PaymentStatus, j.AmountPaid, j.PaidFromCashAccountId, j.PaymentMethod,
               ISNULL(j.SortOrder,0), j.Notes
        FROM OPENJSON(@LinesJson) WITH (
            IngredientItemId      INT           '$.ingredientItemId',
            SourceType            NVARCHAR(30)  '$.sourceType',
            QuantityUsed          DECIMAL(14,3) '$.quantityUsed',
            UnitOfMeasure         NVARCHAR(30)  '$.unitOfMeasure',
            InventoryQuantityUsed DECIMAL(14,3) '$.inventoryQuantityUsed',
            PurchasedQuantityUsed DECIMAL(14,3) '$.purchasedQuantityUsed',
            InventoryUnitCost     DECIMAL(18,4) '$.inventoryUnitCost',
            PurchasedUnitCost     DECIMAL(18,4) '$.purchasedUnitCost',
            SupplierId            INT           '$.supplierId',
            SupplierName          NVARCHAR(200) '$.supplierName',
            PurchaseReference     NVARCHAR(100) '$.purchaseReference',
            PaymentStatus         NVARCHAR(20)  '$.paymentStatus',
            AmountPaid            DECIMAL(14,2) '$.amountPaid',
            PaidFromCashAccountId INT           '$.paidFromCashAccountId',
            PaymentMethod         NVARCHAR(30)  '$.paymentMethod',
            SortOrder             INT           '$.sortOrder',
            Notes                 NVARCHAR(300) '$.notes'
        ) j
        CROSS APPLY (
            SELECT InvQty = CASE j.SourceType
                                WHEN 'BoughtDuringProduction' THEN 0
                                WHEN 'MixedSource' THEN ISNULL(j.InventoryQuantityUsed,0)
                                ELSE j.QuantityUsed END,
                   PurQty = CASE j.SourceType
                                WHEN 'BoughtDuringProduction' THEN j.QuantityUsed
                                WHEN 'MixedSource' THEN ISNULL(j.PurchasedQuantityUsed,0)
                                ELSE 0 END
        ) q
        CROSS APPLY (
            SELECT LineTotal = q.InvQty * ISNULL(j.InventoryUnitCost,0) + q.PurQty * ISNULL(j.PurchasedUnitCost,0)
        ) d
        WHERE j.IngredientItemId IS NOT NULL AND ISNULL(j.QuantityUsed,0) > 0;
    END

    -- Additional costs.
    IF (@CostsJson IS NOT NULL AND LEN(@CostsJson) > 2)
    BEGIN
        INSERT INTO dbo.PoultryFeedProductionAdditionalCosts
            (PoultryFeedProductionBatchId, CostType, Amount, PaymentStatus, AmountPaid, PaidFromCashAccountId, PaymentMethod, SupplierId, PayeeName, SortOrder, Notes)
        SELECT @Id, ISNULL(j.CostType,'Other'), ISNULL(j.Amount,0), j.PaymentStatus, j.AmountPaid, j.PaidFromCashAccountId, j.PaymentMethod, j.SupplierId, j.PayeeName, ISNULL(j.SortOrder,0), j.Notes
        FROM OPENJSON(@CostsJson) WITH (
            CostType              NVARCHAR(40)  '$.costType',
            Amount                DECIMAL(14,2) '$.amount',
            PaymentStatus         NVARCHAR(20)  '$.paymentStatus',
            AmountPaid            DECIMAL(14,2) '$.amountPaid',
            PaidFromCashAccountId INT           '$.paidFromCashAccountId',
            PaymentMethod         NVARCHAR(30)  '$.paymentMethod',
            SupplierId            INT           '$.supplierId',
            PayeeName             NVARCHAR(200) '$.payeeName',
            SortOrder             INT           '$.sortOrder',
            Notes                 NVARCHAR(300) '$.notes'
        ) j
        WHERE ISNULL(j.Amount,0) <> 0 OR j.CostType IS NOT NULL;
    END

    -- Recompute the cost roll-up from the persisted rows.
    DECLARE @IngCost DECIMAL(14,2) = ISNULL((SELECT SUM(TotalCost) FROM dbo.PoultryFeedProductionBatchLines WHERE PoultryFeedProductionBatchId = @Id), 0);
    DECLARE @AddCost DECIMAL(14,2) = ISNULL((SELECT SUM(Amount)    FROM dbo.PoultryFeedProductionAdditionalCosts WHERE PoultryFeedProductionBatchId = @Id), 0);
    DECLARE @TotCost DECIMAL(14,2) = @IngCost + @AddCost;

    UPDATE dbo.PoultryFeedProductionBatches
    SET    TotalIngredientCost = @IngCost,
           TotalAdditionalCost = @AddCost,
           TotalProductionCost = @TotCost,
           CostPerOutputUnit   = CAST(@TotCost / NULLIF(@QuantityProduced,0) AS DECIMAL(18,4))
    WHERE  PoultryFeedProductionBatchId = @Id AND FarmId = @FarmId;

    COMMIT TRANSACTION;
    SELECT @Id AS PoultryFeedProductionBatchId, @BatchNumber AS BatchNumber;
END
GO

-- -----------------------------------------------------------------------------
-- DELETE — now removes Draft OR Reversed (lines + costs cascade). A Reversed
-- batch's inventory/cash effects were already unwound, so nothing else to undo.
-- Only Posted is blocked.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryFeedProductionBatch_Delete
    @FarmId NVARCHAR(450), @PoultryFeedProductionBatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Status NVARCHAR(20);
    SELECT @Status = Status FROM dbo.PoultryFeedProductionBatches
    WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;

    IF (@Status IS NULL) RETURN;
    IF (@Status = 'Posted') THROW 51002, 'Posted batches cannot be deleted. Reverse the batch first.', 1;

    DELETE FROM dbo.PoultryFeedProductionBatches
    WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- POST — now accepts Draft OR Reversed (repost). Reposting re-runs the full
-- posting engine and clears the reversal audit stamp. Body identical to
-- migration 171 except the Reversed guard is removed + the reversal reset.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryFeedProductionBatch_Post
    @FarmId NVARCHAR(450),
    @PoultryFeedProductionBatchId INT,
    @PostedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @FinishedFeedItemId INT, @QtyProduced DECIMAL(14,3),
            @BatchNumber NVARCHAR(60), @ProductionDate DATETIME2, @OutputUnit NVARCHAR(30);
    SELECT @Status = Status, @FinishedFeedItemId = FinishedFeedItemId, @QtyProduced = QuantityProduced,
           @BatchNumber = BatchNumber, @ProductionDate = ProductionDate, @OutputUnit = OutputUnit
    FROM   dbo.PoultryFeedProductionBatches
    WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;

    IF @Status IS NULL      THROW 51100, 'Feed production batch not found.', 1;
    IF @Status = 'Posted'   THROW 51101, 'Batch is already posted.', 1;
    -- A Reversed batch may be reposted: all prior effects were already unwound.
    IF ISNULL(@QtyProduced,0) <= 0 THROW 51103, 'Quantity produced must be greater than zero.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.PoultryFeedProductionBatchLines WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId)
        THROW 51104, 'Add at least one ingredient line before posting.', 1;

    -- A recorded payment must name the cash account it came from.
    IF EXISTS (SELECT 1 FROM dbo.PoultryFeedProductionBatchLines
               WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND ISNULL(AmountPaid,0) > 0 AND PaidFromCashAccountId IS NULL)
        THROW 51105, 'Select a cash account for paid ingredient purchases.', 1;
    IF EXISTS (SELECT 1 FROM dbo.PoultryFeedProductionAdditionalCosts
               WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND ISNULL(AmountPaid,0) > 0 AND PaidFromCashAccountId IS NULL)
        THROW 51106, 'Select a cash account for paid production costs.', 1;

    BEGIN TRANSACTION;

    -- Declared once (T-SQL variables are batch-scoped); reset per iteration.
    DECLARE @LineId INT, @ItemId INT, @Qty DECIMAL(14,3),
            @InvQty DECIMAL(14,3), @PurQty DECIMAL(14,3), @PurUnit DECIMAL(18,4),
            @Unit NVARCHAR(30), @SupplierId INT, @SupplierName NVARCHAR(200), @PaymentMethod NVARCHAR(30),
            @InvCost DECIMAL(14,4), @InvPortion DECIMAL(14,2), @PurPortion DECIMAL(14,2), @UsageId INT;

    DECLARE line_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT PoultryFeedProductionBatchLineId, IngredientItemId, QuantityUsed,
               ISNULL(InventoryQuantityUsed,0), ISNULL(PurchasedQuantityUsed,0), ISNULL(PurchasedUnitCost,0),
               UnitOfMeasure, SupplierId, SupplierName, PaymentMethod
        FROM   dbo.PoultryFeedProductionBatchLines
        WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId
        ORDER  BY SortOrder, PoultryFeedProductionBatchLineId;
    OPEN line_cur;
    FETCH NEXT FROM line_cur INTO @LineId, @ItemId, @Qty, @InvQty, @PurQty, @PurUnit, @Unit, @SupplierId, @SupplierName, @PaymentMethod;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @InvCost = 0; SET @InvPortion = 0; SET @PurPortion = 0; SET @UsageId = NULL;

        -- Inventory portion: consume from real stock lots (authoritative cost).
        IF @InvQty > 0
        BEGIN
            INSERT INTO dbo.PoultryRawMaterialUsage (FarmId, PoultryRawMaterialItemId, PoultryFeedProductionBatchId, QuantityUsed, Notes, CreatedBy)
            VALUES (@FarmId, @ItemId, @PoultryFeedProductionBatchId, @InvQty, CONCAT(N'Feed production ', @BatchNumber), @PostedBy);
            SET @UsageId = CAST(SCOPE_IDENTITY() AS INT);

            EXEC dbo.spPoultryRawMaterialItem_ConsumeBatches @FarmId, @ItemId, @UsageId, @InvQty, @InvCost OUTPUT;

            UPDATE dbo.PoultryRawMaterialItems
            SET    CurrentQuantity = CurrentQuantity - @InvQty, UpdatedAt = SYSUTCDATETIME()
            WHERE  PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId;

            UPDATE dbo.PoultryRawMaterialUsage SET UnitCost = @InvCost WHERE PoultryRawMaterialUsageId = @UsageId;
            SET @InvPortion = CAST(ISNULL(@InvCost,0) * @InvQty AS DECIMAL(14,2));
        END

        -- Purchased portion: a bought-and-consumed lot (net-zero stock) for audit.
        IF @PurQty > 0
        BEGIN
            INSERT INTO dbo.PoultryRawMaterialPurchases
                (FarmId, PoultryRawMaterialItemId, SupplierName, SupplierId, PurchaseDate, Quantity, UnitCost, TotalCost,
                 ProductionUnit, ProductionUnitsPerPurchaseUnit, RemainingQuantity, PaymentMethod, AmountPaid,
                 SourceFeedProductionBatchId, Notes, CreatedBy)
            VALUES (@FarmId, @ItemId, @SupplierName, @SupplierId, @ProductionDate, @PurQty, @PurUnit, CAST(@PurQty * @PurUnit AS DECIMAL(14,2)),
                 @Unit, 1, 0, @PaymentMethod, CAST(@PurQty * @PurUnit AS DECIMAL(14,2)),
                 @PoultryFeedProductionBatchId, CONCAT(N'Bought for feed production ', @BatchNumber), @PostedBy);
            SET @PurPortion = CAST(@PurQty * @PurUnit AS DECIMAL(14,2));
        END

        UPDATE dbo.PoultryFeedProductionBatchLines
        SET    InventoryUnitCost = @InvCost,
               TotalCost = @InvPortion + @PurPortion,
               UnitCost  = CAST((@InvPortion + @PurPortion) / NULLIF(@Qty,0) AS DECIMAL(18,4))
        WHERE  PoultryFeedProductionBatchLineId = @LineId;

        FETCH NEXT FROM line_cur INTO @LineId, @ItemId, @Qty, @InvQty, @PurQty, @PurUnit, @Unit, @SupplierId, @SupplierName, @PaymentMethod;
    END
    CLOSE line_cur; DEALLOCATE line_cur;

    -- Roll up the finalised costs.
    DECLARE @IngCost DECIMAL(14,2) = ISNULL((SELECT SUM(TotalCost) FROM dbo.PoultryFeedProductionBatchLines WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId), 0);
    DECLARE @AddCost DECIMAL(14,2) = ISNULL((SELECT SUM(Amount)    FROM dbo.PoultryFeedProductionAdditionalCosts WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId), 0);
    DECLARE @TotCost DECIMAL(14,2) = @IngCost + @AddCost;
    DECLARE @CPU DECIMAL(18,4) = CAST(@TotCost / NULLIF(@QtyProduced,0) AS DECIMAL(18,4));

    -- Produced finished-feed stock lot (consumable by flocks at cost/unit).
    INSERT INTO dbo.PoultryRawMaterialPurchases
        (FarmId, PoultryRawMaterialItemId, SupplierName, PurchaseDate, Quantity, UnitCost, TotalCost,
         ProductionUnit, ProductionUnitsPerPurchaseUnit, RemainingQuantity, PaymentMethod, AmountPaid,
         SourceFeedProductionBatchId, Notes, CreatedBy)
    VALUES (@FarmId, @FinishedFeedItemId, N'Feed Production', @ProductionDate, @QtyProduced, @CPU, @TotCost,
         @OutputUnit, 1, @QtyProduced, N'Production', @TotCost,
         @PoultryFeedProductionBatchId, CONCAT(N'Produced feed ', @BatchNumber), @PostedBy);

    UPDATE dbo.PoultryRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity + @QtyProduced, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialItemId = @FinishedFeedItemId AND FarmId = @FarmId;

    -- Cash out — one posting per account (paid ingredient purchases + paid costs).
    ;WITH Pay AS (
        SELECT PaidFromCashAccountId AS AcctId, SUM(ISNULL(AmountPaid,0)) AS Paid
        FROM   dbo.PoultryFeedProductionBatchLines
        WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND PaidFromCashAccountId IS NOT NULL AND ISNULL(AmountPaid,0) > 0
        GROUP  BY PaidFromCashAccountId
        UNION ALL
        SELECT PaidFromCashAccountId, SUM(ISNULL(AmountPaid,0))
        FROM   dbo.PoultryFeedProductionAdditionalCosts
        WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND PaidFromCashAccountId IS NOT NULL AND ISNULL(AmountPaid,0) > 0
        GROUP  BY PaidFromCashAccountId
    )
    SELECT AcctId, SUM(Paid) AS Paid INTO #Pay FROM Pay GROUP BY AcctId HAVING SUM(Paid) > 0;

    DECLARE @AcctId INT, @Paid DECIMAL(14,2), @NewBal DECIMAL(14,2);
    DECLARE pay_cur CURSOR LOCAL FAST_FORWARD FOR SELECT AcctId, Paid FROM #Pay;
    OPEN pay_cur; FETCH NEXT FROM pay_cur INTO @AcctId, @Paid;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        UPDATE dbo.PoultryCashAccounts SET CurrentBalance = CurrentBalance - @Paid, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryCashAccountId = @AcctId AND FarmId = @FarmId;
        SET @NewBal = (SELECT CurrentBalance FROM dbo.PoultryCashAccounts WHERE PoultryCashAccountId = @AcctId AND FarmId = @FarmId);
        INSERT INTO dbo.PoultryCashTransactions
            (FarmId, PoultryCashAccountId, TransactionDate, TransactionType, SourceType, SourceId, Amount, BalanceAfterTransaction, Description, CreatedBy)
        VALUES (@FarmId, @AcctId, @ProductionDate, 'CashOut', 'FeedProduction', @PoultryFeedProductionBatchId, -@Paid, @NewBal, CONCAT(N'Feed production ', @BatchNumber), @PostedBy);
        FETCH NEXT FROM pay_cur INTO @AcctId, @Paid;
    END
    CLOSE pay_cur; DEALLOCATE pay_cur;
    DROP TABLE #Pay;

    -- -> Posted. Clear any reversal stamp left from a prior reverse (repost case).
    UPDATE dbo.PoultryFeedProductionBatches
    SET    TotalIngredientCost = @IngCost, TotalAdditionalCost = @AddCost, TotalProductionCost = @TotCost,
           CostPerOutputUnit = @CPU, Status = 'Posted', PostedBy = @PostedBy, PostedAt = SYSUTCDATETIME(),
           ReversedBy = NULL, ReversedAt = NULL, ReversalReason = NULL, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryFeedProductionBatch_Save   TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryFeedProductionBatch_Delete TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryFeedProductionBatch_Post   TO [Techretainer];
    PRINT '174: granted EXECUTE on spPoultryFeedProductionBatch_Save/Delete/Post to Techretainer.';
END
GO

PRINT '174_PoultryFeedProductionReopenReversed.sql complete.';
GO
