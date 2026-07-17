-- =============================================================================
-- Migration 146: Raw-material FIFO/LIFO/HIFO usage method + batch-level costing
-- =============================================================================
-- Adds a per-item consumption policy (FIFO / LIFO / HIFO) to
-- PoultryRawMaterialItems, turns PoultryRawMaterialPurchases into real
-- lots/batches by tracking RemainingQuantity per purchase, and rewrites the
-- production-record feed/medication sync so consumption automatically draws
-- from the correct batch(es) per the item's policy and computes the resulting
-- weighted-average unit cost server-side (the client-sent unit cost is no
-- longer trusted for what gets persisted).
--
-- New table PoultryRawMaterialUsageBatch links each usage event to the
-- specific purchase batch(es) it drew from, so edits/deletes can reverse
-- precisely and Purchases can't be deleted out from under recorded usage.
--
-- If the quantity requested exceeds everything left in tracked batches, the
-- whole save is rejected (RAISERROR + XACT_ABORT rolls back the transaction)
-- rather than silently going negative.
--
-- Idempotent (object/column guards + CREATE OR ALTER). Grants EXECUTE to the
-- app login.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. PoultryRawMaterialItems.UsageMethod
-- -----------------------------------------------------------------------------
IF COL_LENGTH('dbo.PoultryRawMaterialItems','UsageMethod') IS NULL
BEGIN
    ALTER TABLE dbo.PoultryRawMaterialItems
        ADD UsageMethod NVARCHAR(10) NOT NULL CONSTRAINT DF_PoultryRawMaterialItems_UsageMethod DEFAULT ('FIFO');
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_PoultryRawMaterialItems_UsageMethod')
    ALTER TABLE dbo.PoultryRawMaterialItems
        ADD CONSTRAINT CK_PoultryRawMaterialItems_UsageMethod CHECK (UsageMethod IN ('FIFO','LIFO','HIFO'));
GO

-- -----------------------------------------------------------------------------
-- 2. PoultryRawMaterialPurchases.RemainingQuantity — turns purchases into lots.
--    First-run only: backfill full quantity, then run a one-time FIFO drawdown
--    per item equal to (total ever purchased - current on-hand) so batches
--    reconcile with the item's existing CurrentQuantity before this feature
--    existed. No Usage/UsageBatch history rows are created for this backfill
--    (there's no production record to link it to) — it only seeds
--    RemainingQuantity so future FIFO/LIFO/HIFO draws start from a consistent
--    baseline.
-- -----------------------------------------------------------------------------
-- Add the column in its own batch first: a later statement in the SAME batch
-- that reads/writes it would compile against the pre-ALTER schema and fail
-- with "Invalid column name" even though the ALTER runs immediately before it.
IF COL_LENGTH('dbo.PoultryRawMaterialPurchases','RemainingQuantity') IS NULL
    ALTER TABLE dbo.PoultryRawMaterialPurchases ADD RemainingQuantity DECIMAL(14,3) NULL;
GO

-- Backfill + reconcile — guarded on the column still being nullable, so this
-- runs exactly once (it ends by making the column NOT NULL).
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.PoultryRawMaterialPurchases') AND name = 'RemainingQuantity' AND is_nullable = 1
)
BEGIN
    UPDATE dbo.PoultryRawMaterialPurchases SET RemainingQuantity = Quantity;

    ALTER TABLE dbo.PoultryRawMaterialPurchases ALTER COLUMN RemainingQuantity DECIMAL(14,3) NOT NULL;
    ALTER TABLE dbo.PoultryRawMaterialPurchases
        ADD CONSTRAINT DF_PoultryRMPurchases_Remaining DEFAULT (0) FOR RemainingQuantity;

    DECLARE @ReconItemId INT, @TotalPurchased DECIMAL(18,3), @OnHand DECIMAL(18,3), @Shortfall DECIMAL(18,3);
    DECLARE recon_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT i.PoultryRawMaterialItemId, ISNULL(SUM(p.Quantity), 0), i.CurrentQuantity
        FROM   dbo.PoultryRawMaterialItems i
        LEFT   JOIN dbo.PoultryRawMaterialPurchases p ON p.PoultryRawMaterialItemId = i.PoultryRawMaterialItemId
        GROUP  BY i.PoultryRawMaterialItemId, i.CurrentQuantity;

    OPEN recon_cursor;
    FETCH NEXT FROM recon_cursor INTO @ReconItemId, @TotalPurchased, @OnHand;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @Shortfall = @TotalPurchased - @OnHand;
        IF (@Shortfall > 0)
        BEGIN
            DECLARE @Remaining DECIMAL(18,3) = @Shortfall;
            DECLARE @DrawId INT, @DrawRemaining DECIMAL(14,3), @Take DECIMAL(14,3);
            DECLARE draw_cursor CURSOR LOCAL FAST_FORWARD FOR
                SELECT PoultryRawMaterialPurchaseId, RemainingQuantity
                FROM   dbo.PoultryRawMaterialPurchases
                WHERE  PoultryRawMaterialItemId = @ReconItemId AND RemainingQuantity > 0
                ORDER  BY PurchaseDate ASC, PoultryRawMaterialPurchaseId ASC;
            OPEN draw_cursor;
            FETCH NEXT FROM draw_cursor INTO @DrawId, @DrawRemaining;
            WHILE @@FETCH_STATUS = 0 AND @Remaining > 0
            BEGIN
                SET @Take = CASE WHEN @DrawRemaining <= @Remaining THEN @DrawRemaining ELSE @Remaining END;
                UPDATE dbo.PoultryRawMaterialPurchases
                SET    RemainingQuantity = RemainingQuantity - @Take
                WHERE  PoultryRawMaterialPurchaseId = @DrawId;
                SET @Remaining -= @Take;
                FETCH NEXT FROM draw_cursor INTO @DrawId, @DrawRemaining;
            END
            CLOSE draw_cursor;
            DEALLOCATE draw_cursor;
        END
        FETCH NEXT FROM recon_cursor INTO @ReconItemId, @TotalPurchased, @OnHand;
    END
    CLOSE recon_cursor;
    DEALLOCATE recon_cursor;
END
GO

-- -----------------------------------------------------------------------------
-- 3. PoultryRawMaterialUsageBatch — which purchase batch(es) a usage event drew
--    from. Deleting a Usage row cascades to its batch-draw children.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryRawMaterialUsageBatch', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryRawMaterialUsageBatch (
        PoultryRawMaterialUsageBatchId INT IDENTITY(1,1) PRIMARY KEY,
        PoultryRawMaterialUsageId      INT           NOT NULL,
        PoultryRawMaterialPurchaseId   INT           NOT NULL,
        QuantityDrawn                  DECIMAL(14,3) NOT NULL,
        UnitCostAtDraw                 DECIMAL(14,2) NOT NULL,
        CreatedAt                      DATETIME2     NOT NULL CONSTRAINT DF_PoultryRMUsageBatch_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_PoultryRMUsageBatch_Usage FOREIGN KEY (PoultryRawMaterialUsageId)
            REFERENCES dbo.PoultryRawMaterialUsage (PoultryRawMaterialUsageId) ON DELETE CASCADE,
        CONSTRAINT FK_PoultryRMUsageBatch_Purchase FOREIGN KEY (PoultryRawMaterialPurchaseId)
            REFERENCES dbo.PoultryRawMaterialPurchases (PoultryRawMaterialPurchaseId)
    );
    CREATE INDEX IX_PoultryRMUsageBatch_Usage    ON dbo.PoultryRawMaterialUsageBatch (PoultryRawMaterialUsageId);
    CREATE INDEX IX_PoultryRMUsageBatch_Purchase ON dbo.PoultryRawMaterialUsageBatch (PoultryRawMaterialPurchaseId);
END
GO

-- =============================================================================
-- Stored procedures
-- =============================================================================

-- ---- Items: carry UsageMethod through Insert/Update -------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialItem_Insert
    @FarmId           NVARCHAR(450),
    @ItemName         NVARCHAR(150),
    @Category         NVARCHAR(40),
    @UnitOfMeasure    NVARCHAR(30)  = NULL,
    @MinimumStockAlert DECIMAL(14,3) = 0,
    @Notes            NVARCHAR(500) = NULL,
    @UsageMethod      NVARCHAR(10)  = 'FIFO'
AS
BEGIN
    SET NOCOUNT ON;
    IF (@UsageMethod IS NULL OR @UsageMethod NOT IN ('FIFO','LIFO','HIFO')) SET @UsageMethod = 'FIFO';
    INSERT INTO dbo.PoultryRawMaterialItems (FarmId, ItemName, Category, UnitOfMeasure, MinimumStockAlert, Notes, UsageMethod)
    VALUES (@FarmId, @ItemName, @Category, @UnitOfMeasure, ISNULL(@MinimumStockAlert, 0), @Notes, @UsageMethod);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialItem_Update
    @PoultryRawMaterialItemId INT,
    @FarmId           NVARCHAR(450),
    @ItemName         NVARCHAR(150),
    @Category         NVARCHAR(40),
    @UnitOfMeasure    NVARCHAR(30)  = NULL,
    @MinimumStockAlert DECIMAL(14,3) = 0,
    @IsActive         BIT           = 1,
    @Notes            NVARCHAR(500) = NULL,
    @UsageMethod      NVARCHAR(10)  = 'FIFO'
AS
BEGIN
    SET NOCOUNT ON;
    IF (@UsageMethod IS NULL OR @UsageMethod NOT IN ('FIFO','LIFO','HIFO')) SET @UsageMethod = 'FIFO';
    UPDATE dbo.PoultryRawMaterialItems
    SET    ItemName = @ItemName, Category = @Category, UnitOfMeasure = @UnitOfMeasure,
           MinimumStockAlert = ISNULL(@MinimumStockAlert, 0), IsActive = ISNULL(@IsActive, 1),
           Notes = @Notes, UsageMethod = @UsageMethod, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialItemId = @PoultryRawMaterialItemId AND FarmId = @FarmId;
END
GO

-- ---- Purchases: seed/maintain RemainingQuantity, guard edits/deletes --------
CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialPurchase_Insert
    @FarmId                  NVARCHAR(450),
    @PoultryRawMaterialItemId INT,
    @SupplierName            NVARCHAR(200) = NULL,
    @SupplierId              INT           = NULL,
    @PurchaseDate            DATETIME2     = NULL,
    @Quantity                DECIMAL(14,3),
    @UnitCost                DECIMAL(14,2),
    @TotalCost               DECIMAL(14,2) = NULL,  -- exact total; NULL => Qty*UnitCost
    @ProductionUnit                 NVARCHAR(30)  = NULL,
    @ProductionUnitsPerPurchaseUnit DECIMAL(14,4) = NULL,
    @PaymentMethod           NVARCHAR(30)  = NULL,
    @AmountPaid              DECIMAL(14,2) = 0,
    @ReceiptUrl              NVARCHAR(500) = NULL,
    @Notes                   NVARCHAR(500) = NULL,
    @CreatedBy               NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@Quantity <= 0) BEGIN RAISERROR('Quantity must be > 0.', 16, 1); RETURN; END
    IF (@UnitCost < 0)  BEGIN RAISERROR('UnitCost cannot be negative.', 16, 1); RETURN; END
    IF (@TotalCost IS NULL OR @TotalCost <= 0) SET @TotalCost = CAST(@Quantity AS DECIMAL(14,2)) * @UnitCost;
    IF (@AmountPaid IS NULL) SET @AmountPaid = 0;
    IF (@AmountPaid > @TotalCost) SET @AmountPaid = @TotalCost;

    BEGIN TRANSACTION;

    INSERT INTO dbo.PoultryRawMaterialPurchases (
        FarmId, PoultryRawMaterialItemId, SupplierName, SupplierId, PurchaseDate,
        Quantity, UnitCost, TotalCost, ProductionUnit, ProductionUnitsPerPurchaseUnit,
        PaymentMethod, AmountPaid, ReceiptUrl, Notes, CreatedBy, RemainingQuantity
    )
    VALUES (
        @FarmId, @PoultryRawMaterialItemId, @SupplierName, @SupplierId, ISNULL(@PurchaseDate, SYSUTCDATETIME()),
        @Quantity, @UnitCost, @TotalCost, @ProductionUnit, @ProductionUnitsPerPurchaseUnit,
        @PaymentMethod, @AmountPaid, @ReceiptUrl, @Notes, @CreatedBy, @Quantity
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    UPDATE dbo.PoultryRawMaterialItems
    SET    CurrentQuantity = CurrentQuantity + @Quantity, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialItemId = @PoultryRawMaterialItemId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
    SELECT @NewId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialPurchase_Update
    @PoultryRawMaterialPurchaseId INT,
    @FarmId         NVARCHAR(450),
    @SupplierName   NVARCHAR(200) = NULL,
    @SupplierId     INT           = NULL,
    @PurchaseDate   DATETIME2     = NULL,
    @Quantity       DECIMAL(14,3),
    @UnitCost       DECIMAL(14,2),
    @TotalCost      DECIMAL(14,2) = NULL,
    @ProductionUnit                 NVARCHAR(30)  = NULL,
    @ProductionUnitsPerPurchaseUnit DECIMAL(14,4) = NULL,
    @PaymentMethod  NVARCHAR(30)  = NULL,
    @AmountPaid     DECIMAL(14,2) = 0,
    @ReceiptUrl     NVARCHAR(500) = NULL,
    @Notes          NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@Quantity <= 0) BEGIN RAISERROR('Quantity must be > 0.', 16, 1); RETURN; END
    IF (@UnitCost < 0)  BEGIN RAISERROR('UnitCost cannot be negative.', 16, 1); RETURN; END
    IF (@TotalCost IS NULL OR @TotalCost <= 0) SET @TotalCost = CAST(@Quantity AS DECIMAL(14,2)) * @UnitCost;

    DECLARE @OldQty DECIMAL(14,3), @OldRemaining DECIMAL(14,3), @ItemId INT;
    SELECT @OldQty = Quantity, @OldRemaining = RemainingQuantity, @ItemId = PoultryRawMaterialItemId
    FROM   dbo.PoultryRawMaterialPurchases
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    IF @OldQty IS NULL BEGIN RAISERROR('Purchase %d not found.', 16, 1, @PoultryRawMaterialPurchaseId); RETURN; END

    DECLARE @AlreadyDrawn DECIMAL(14,3) = @OldQty - ISNULL(@OldRemaining, @OldQty);
    IF (@Quantity < @AlreadyDrawn)
    BEGIN
        DECLARE @Msg2 NVARCHAR(400) = CONCAT(N'Cannot reduce quantity below ', CONVERT(NVARCHAR(40), @AlreadyDrawn), N' — that much has already been used from this batch.');
        RAISERROR(@Msg2, 16, 1); RETURN;
    END

    DECLARE @Delta DECIMAL(14,3) = @Quantity - @OldQty;
    IF (@Delta < 0)
    BEGIN
        DECLARE @CurrentStock DECIMAL(14,3) = (SELECT CurrentQuantity FROM dbo.PoultryRawMaterialItems WHERE PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId);
        IF (@CurrentStock + @Delta < 0)
        BEGIN
            DECLARE @Msg NVARCHAR(400) = CONCAT(N'Cannot reduce quantity: only ', CONVERT(NVARCHAR(40), @CurrentStock), N' units remain in stock.');
            RAISERROR(@Msg, 16, 1); RETURN;
        END
    END

    BEGIN TRANSACTION;

    UPDATE dbo.PoultryRawMaterialPurchases
    SET    SupplierName = @SupplierName, SupplierId = @SupplierId,
           PurchaseDate = ISNULL(@PurchaseDate, PurchaseDate),
           Quantity = @Quantity, UnitCost = @UnitCost, TotalCost = @TotalCost,
           ProductionUnit = @ProductionUnit, ProductionUnitsPerPurchaseUnit = @ProductionUnitsPerPurchaseUnit,
           PaymentMethod = @PaymentMethod, AmountPaid = @AmountPaid,
           ReceiptUrl = @ReceiptUrl, Notes = @Notes, UpdatedAt = SYSUTCDATETIME(),
           RemainingQuantity = @Quantity - @AlreadyDrawn
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    IF (@Delta <> 0)
        UPDATE dbo.PoultryRawMaterialItems
        SET    CurrentQuantity = CurrentQuantity + @Delta, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialPurchase_Delete
    @PoultryRawMaterialPurchaseId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM dbo.PoultryRawMaterialUsageBatch WHERE PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId)
    BEGIN
        RAISERROR('Cannot delete: this purchase batch has already been drawn from by a production/medication record. Delete or edit those records first.', 16, 1);
        RETURN;
    END

    DECLARE @Qty DECIMAL(14,3), @ItemId INT;
    SELECT @Qty = Quantity, @ItemId = PoultryRawMaterialItemId
    FROM   dbo.PoultryRawMaterialPurchases
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    IF @Qty IS NULL BEGIN RAISERROR('Purchase %d not found.', 16, 1, @PoultryRawMaterialPurchaseId); RETURN; END

    BEGIN TRANSACTION;
    DELETE FROM dbo.PoultryRawMaterialPurchases
    WHERE  PoultryRawMaterialPurchaseId = @PoultryRawMaterialPurchaseId AND FarmId = @FarmId;

    UPDATE dbo.PoultryRawMaterialItems
    SET    CurrentQuantity = CASE WHEN CurrentQuantity - @Qty < 0 THEN 0 ELSE CurrentQuantity - @Qty END,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
END
GO

-- ---- Batch consumption helper: FIFO/LIFO/HIFO walk ---------------------------
-- Draws @NeededQty of @ItemId from its purchase batches in the order dictated
-- by the item's UsageMethod, records one PoultryRawMaterialUsageBatch row per
-- batch drawn from, decrements each batch's RemainingQuantity, and returns the
-- resulting quantity-weighted average unit cost. Blocks (RAISERROR) if the
-- tracked batches don't have enough left to cover @NeededQty.
CREATE OR ALTER PROCEDURE dbo.spPoultryRawMaterialItem_ConsumeBatches
    @FarmId NVARCHAR(450),
    @ItemId INT,
    @UsageId INT,
    @NeededQty DECIMAL(14,3),
    @ComputedUnitCost DECIMAL(14,4) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @ComputedUnitCost = NULL;
    IF (@NeededQty IS NULL OR @NeededQty <= 0) RETURN;

    DECLARE @UsageMethod NVARCHAR(10) = (
        SELECT UsageMethod FROM dbo.PoultryRawMaterialItems
        WHERE PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId
    );
    SET @UsageMethod = ISNULL(@UsageMethod, 'FIFO');

    DECLARE @Draws TABLE (PurchaseId INT, QtyDrawn DECIMAL(14,3), UnitCost DECIMAL(14,2));

    ;WITH Ordered AS (
        SELECT PoultryRawMaterialPurchaseId, RemainingQuantity, UnitCost,
               SUM(RemainingQuantity) OVER (
                   ORDER BY
                       CASE WHEN @UsageMethod = 'FIFO' THEN PurchaseDate END ASC,
                       CASE WHEN @UsageMethod = 'LIFO' THEN PurchaseDate END DESC,
                       CASE WHEN @UsageMethod = 'HIFO' THEN UnitCost END DESC,
                       PoultryRawMaterialPurchaseId ASC
                   ROWS UNBOUNDED PRECEDING
               ) AS RunningTotal
        FROM   dbo.PoultryRawMaterialPurchases WITH (UPDLOCK, ROWLOCK)
        WHERE  PoultryRawMaterialItemId = @ItemId AND FarmId = @FarmId AND RemainingQuantity > 0
    )
    INSERT INTO @Draws (PurchaseId, QtyDrawn, UnitCost)
    SELECT PoultryRawMaterialPurchaseId,
           CASE WHEN RunningTotal <= @NeededQty THEN RemainingQuantity
                ELSE @NeededQty - (RunningTotal - RemainingQuantity) END,
           UnitCost
    FROM   Ordered
    WHERE  RunningTotal - RemainingQuantity < @NeededQty;

    DECLARE @TotalDrawn DECIMAL(14,3) = (SELECT ISNULL(SUM(QtyDrawn), 0) FROM @Draws);
    IF (@TotalDrawn + 0.0005 < @NeededQty)
    BEGIN
        DECLARE @ItemName NVARCHAR(150) = (SELECT ItemName FROM dbo.PoultryRawMaterialItems WHERE PoultryRawMaterialItemId = @ItemId);
        DECLARE @Msg NVARCHAR(400) = CONCAT(
            N'Not enough tracked batch stock for "', ISNULL(@ItemName, N'item'), N'": need ',
            CONVERT(NVARCHAR(30), @NeededQty), N', only ', CONVERT(NVARCHAR(30), @TotalDrawn),
            N' available across purchase batches.');
        RAISERROR(@Msg, 16, 1);
        RETURN;
    END

    UPDATE p
    SET    p.RemainingQuantity = p.RemainingQuantity - d.QtyDrawn, p.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialPurchases p
    JOIN   @Draws d ON d.PurchaseId = p.PoultryRawMaterialPurchaseId;

    INSERT INTO dbo.PoultryRawMaterialUsageBatch (PoultryRawMaterialUsageId, PoultryRawMaterialPurchaseId, QuantityDrawn, UnitCostAtDraw)
    SELECT @UsageId, PurchaseId, QtyDrawn, UnitCost FROM @Draws WHERE QtyDrawn > 0;

    SELECT @ComputedUnitCost = SUM(QtyDrawn * UnitCost) / NULLIF(SUM(QtyDrawn), 0) FROM @Draws;
END
GO

-- ---- Production sync: batch-aware, returns computed costs -------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryProductionRawMaterialSync
    @FarmId NVARCHAR(450), @ProductionId INT,
    @FeedItemId INT = NULL, @FeedQty DECIMAL(14,3) = NULL,
    @MedItemId  INT = NULL, @MedQty  DECIMAL(14,3) = NULL,
    @CreatedBy NVARCHAR(450) = NULL,
    @ComputedFeedUnitCost DECIMAL(14,4) = NULL OUTPUT,
    @ComputedTotalFeedCost DECIMAL(14,2) = NULL OUTPUT,
    @ComputedMedicationUnitCost DECIMAL(14,4) = NULL OUTPUT,
    @ComputedTotalMedicationCost DECIMAL(14,2) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @ComputedFeedUnitCost = NULL; SET @ComputedTotalFeedCost = NULL;
    SET @ComputedMedicationUnitCost = NULL; SET @ComputedTotalMedicationCost = NULL;

    -- 1. Reverse every prior production-linked usage row: restore the exact
    --    batch(es) it drew from, restore the item aggregate, then delete the
    --    usage rows (cascades to remove their batch-draw children).
    UPDATE p
    SET    p.RemainingQuantity = p.RemainingQuantity + b.QuantityDrawn, p.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialPurchases p
    JOIN   dbo.PoultryRawMaterialUsageBatch b ON b.PoultryRawMaterialPurchaseId = p.PoultryRawMaterialPurchaseId
    JOIN   dbo.PoultryRawMaterialUsage u ON u.PoultryRawMaterialUsageId = b.PoultryRawMaterialUsageId
    WHERE  u.FarmId = @FarmId AND u.ProductionRecordId = @ProductionId;

    UPDATE it
    SET    it.CurrentQuantity = it.CurrentQuantity + u.QuantityUsed, it.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialItems it
    JOIN   dbo.PoultryRawMaterialUsage u
      ON   u.PoultryRawMaterialItemId = it.PoultryRawMaterialItemId
    WHERE  u.FarmId = @FarmId AND u.ProductionRecordId = @ProductionId;

    DELETE FROM dbo.PoultryRawMaterialUsage
    WHERE  FarmId = @FarmId AND ProductionRecordId = @ProductionId;

    -- 2. Apply feed consumption (batch-walk per the item's FIFO/LIFO/HIFO policy).
    IF (@FeedItemId IS NOT NULL AND ISNULL(@FeedQty,0) > 0)
    BEGIN
        DECLARE @FeedUsageId INT;
        INSERT INTO dbo.PoultryRawMaterialUsage (FarmId, PoultryRawMaterialItemId, ProductionRecordId, QuantityUsed, Notes, CreatedBy)
        VALUES (@FarmId, @FeedItemId, @ProductionId, @FeedQty, N'Feed used in production', @CreatedBy);
        SET @FeedUsageId = CAST(SCOPE_IDENTITY() AS INT);

        EXEC dbo.spPoultryRawMaterialItem_ConsumeBatches @FarmId, @FeedItemId, @FeedUsageId, @FeedQty, @ComputedFeedUnitCost OUTPUT;

        UPDATE dbo.PoultryRawMaterialItems
        SET    CurrentQuantity = CurrentQuantity - @FeedQty, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryRawMaterialItemId = @FeedItemId AND FarmId = @FarmId;

        SET @ComputedTotalFeedCost = CAST(ISNULL(@ComputedFeedUnitCost, 0) * @FeedQty AS DECIMAL(14,2));
    END

    -- 3. Apply medication consumption.
    IF (@MedItemId IS NOT NULL AND ISNULL(@MedQty,0) > 0)
    BEGIN
        DECLARE @MedUsageId INT;
        INSERT INTO dbo.PoultryRawMaterialUsage (FarmId, PoultryRawMaterialItemId, ProductionRecordId, QuantityUsed, Notes, CreatedBy)
        VALUES (@FarmId, @MedItemId, @ProductionId, @MedQty, N'Medication used in production', @CreatedBy);
        SET @MedUsageId = CAST(SCOPE_IDENTITY() AS INT);

        EXEC dbo.spPoultryRawMaterialItem_ConsumeBatches @FarmId, @MedItemId, @MedUsageId, @MedQty, @ComputedMedicationUnitCost OUTPUT;

        UPDATE dbo.PoultryRawMaterialItems
        SET    CurrentQuantity = CurrentQuantity - @MedQty, UpdatedAt = SYSUTCDATETIME()
        WHERE  PoultryRawMaterialItemId = @MedItemId AND FarmId = @FarmId;

        SET @ComputedTotalMedicationCost = CAST(ISNULL(@ComputedMedicationUnitCost, 0) * @MedQty AS DECIMAL(14,2));
    END
END
GO

-- ---------------------------------------------------------------------------
-- spProductionRecord_Insert — persist provisional costing, then overwrite with
-- the server-computed batch costs once the sync has run (needs @NewId first).
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_Insert]
    @FarmId NVARCHAR(100), @CreatedBy NVARCHAR(100), @UserId NVARCHAR(100), @AgeInWeeks INT, @AgeInDays INT,
    @Date DATE, @NoOfBirds INT, @Mortality INT, @NoOfBirdsLeft INT, @FeedKg DECIMAL(18,2), @Medication NVARCHAR(500) = NULL,
    @Production9AM INT, @Production12PM INT, @Production4PM INT, @TotalProduction INT, @FlockId INT = NULL,
    @BrokenEggs INT = NULL, @Notes NVARCHAR(MAX) = NULL, @EggCount INT = NULL, @EggGrade NVARCHAR(50) = NULL,
    @MeatyEggs INT = NULL, @SoftEggs INT = NULL, @LostEggs INT = NULL,
    @SpecificFeedUsedId INT = NULL, @SpecificFeedUsedName NVARCHAR(150) = NULL, @FeedUnitCost DECIMAL(14,4) = NULL,
    @TotalFeedConsumed DECIMAL(14,3) = NULL, @TotalFeedCost DECIMAL(14,2) = NULL,
    @SpecificMedicationUsedId INT = NULL, @SpecificMedicationUsedName NVARCHAR(150) = NULL, @MedicationUnitCost DECIMAL(14,4) = NULL,
    @TotalMedicationConsumed DECIMAL(14,3) = NULL, @TotalMedicationCost DECIMAL(14,2) = NULL,
    @TotalCostOfProduction DECIMAL(14,2) = NULL,
    @NewId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @EggCount = ISNULL(@EggCount, @TotalProduction);
    IF (@TotalCostOfProduction IS NULL)
        SET @TotalCostOfProduction = ISNULL(@TotalFeedCost,0) + ISNULL(@TotalMedicationCost,0);
    BEGIN TRANSACTION;
    INSERT INTO [dbo].[ProductionRecords] (FarmId, CreatedBy, UserId, AgeInWeeks, AgeInDays, [Date], NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication, Production9AM, Production12PM, Production4PM, TotalProduction, FlockId, BrokenEggs, Notes, EggCount, EggGrade, MeatyEggs, SoftEggs, LostEggs,
        SpecificFeedUsedId, SpecificFeedUsedName, FeedUnitCost, TotalFeedConsumed, TotalFeedCost,
        SpecificMedicationUsedId, SpecificMedicationUsedName, MedicationUnitCost, TotalMedicationConsumed, TotalMedicationCost,
        TotalCostOfProduction, CreatedAt)
    VALUES (@FarmId, @CreatedBy, @UserId, @AgeInWeeks, @AgeInDays, @Date, @NoOfBirds, @Mortality, @NoOfBirdsLeft, @FeedKg, @Medication, @Production9AM, @Production12PM, @Production4PM, @TotalProduction, @FlockId, @BrokenEggs, @Notes, @EggCount, @EggGrade, @MeatyEggs, @SoftEggs, @LostEggs,
        @SpecificFeedUsedId, @SpecificFeedUsedName, @FeedUnitCost, @TotalFeedConsumed, @TotalFeedCost,
        @SpecificMedicationUsedId, @SpecificMedicationUsedName, @MedicationUnitCost, @TotalMedicationConsumed, @TotalMedicationCost,
        @TotalCostOfProduction, GETUTCDATE());
    SET @NewId = SCOPE_IDENTITY();

    -- Bird mortality -> -birds
    DECLARE @mq DECIMAL(14,3) = -CAST(ISNULL(@Mortality,0) AS DECIMAL(14,3));
    IF (@mq <> 0)
        EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Mortality', @mq, @NewId, N'Production mortality', @UserId;

    -- Good eggs -> +egg finished-product stock + stock movement
    DECLARE @good INT = ISNULL(@TotalProduction,0) - ISNULL(@BrokenEggs,0) - ISNULL(@LostEggs,0);
    IF (@good < 0) SET @good = 0;
    EXEC dbo.spPoultryEggStock_SyncForProduction @FarmId, @NewId, @good, NULL, @UserId;

    -- Feed + medication -> -raw-material inventory, drawn per each item's FIFO/LIFO/HIFO policy.
    DECLARE @OutFeedUnitCost DECIMAL(14,4), @OutTotalFeedCost DECIMAL(14,2),
            @OutMedUnitCost DECIMAL(14,4), @OutTotalMedCost DECIMAL(14,2);
    EXEC dbo.spPoultryProductionRawMaterialSync
         @FarmId, @NewId, @SpecificFeedUsedId, @TotalFeedConsumed, @SpecificMedicationUsedId, @TotalMedicationConsumed, @UserId,
         @ComputedFeedUnitCost = @OutFeedUnitCost OUTPUT,
         @ComputedTotalFeedCost = @OutTotalFeedCost OUTPUT,
         @ComputedMedicationUnitCost = @OutMedUnitCost OUTPUT,
         @ComputedTotalMedicationCost = @OutTotalMedCost OUTPUT;

    UPDATE [dbo].[ProductionRecords]
    SET    FeedUnitCost = @OutFeedUnitCost,
           TotalFeedCost = @OutTotalFeedCost,
           MedicationUnitCost = @OutMedUnitCost,
           TotalMedicationCost = @OutTotalMedCost,
           TotalCostOfProduction = ISNULL(@OutTotalFeedCost,0) + ISNULL(@OutTotalMedCost,0)
    WHERE  Id = @NewId;

    COMMIT TRANSACTION;
END
GO

-- ---------------------------------------------------------------------------
-- spProductionRecord_Update — same pattern, re-synced idempotently.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_Update]
    @RecordId INT, @UpdatedBy NVARCHAR(100), @AgeInWeeks INT, @AgeInDays INT, @Date DATE, @NoOfBirds INT, @Mortality INT,
    @NoOfBirdsLeft INT, @FeedKg DECIMAL(18,2), @Medication NVARCHAR(500) = NULL, @Production9AM INT, @Production12PM INT,
    @Production4PM INT, @TotalProduction INT, @FlockId INT = NULL, @BrokenEggs INT = NULL, @Notes NVARCHAR(MAX) = NULL,
    @EggCount INT = NULL, @EggGrade NVARCHAR(50) = NULL, @MeatyEggs INT = NULL, @SoftEggs INT = NULL, @LostEggs INT = NULL,
    @SpecificFeedUsedId INT = NULL, @SpecificFeedUsedName NVARCHAR(150) = NULL, @FeedUnitCost DECIMAL(14,4) = NULL,
    @TotalFeedConsumed DECIMAL(14,3) = NULL, @TotalFeedCost DECIMAL(14,2) = NULL,
    @SpecificMedicationUsedId INT = NULL, @SpecificMedicationUsedName NVARCHAR(150) = NULL, @MedicationUnitCost DECIMAL(14,4) = NULL,
    @TotalMedicationConsumed DECIMAL(14,3) = NULL, @TotalMedicationCost DECIMAL(14,2) = NULL,
    @TotalCostOfProduction DECIMAL(14,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @EggCount = ISNULL(@EggCount, @TotalProduction);
    IF (@TotalCostOfProduction IS NULL)
        SET @TotalCostOfProduction = ISNULL(@TotalFeedCost,0) + ISNULL(@TotalMedicationCost,0);
    DECLARE @FarmId NVARCHAR(100);
    SELECT @FarmId = FarmId FROM dbo.ProductionRecords WHERE Id = @RecordId;
    BEGIN TRANSACTION;
    UPDATE [dbo].[ProductionRecords]
    SET UpdatedBy=@UpdatedBy, AgeInWeeks=@AgeInWeeks, AgeInDays=@AgeInDays, [Date]=@Date, NoOfBirds=@NoOfBirds, Mortality=@Mortality,
        NoOfBirdsLeft=@NoOfBirdsLeft, FeedKg=@FeedKg, Medication=@Medication, Production9AM=@Production9AM, Production12PM=@Production12PM,
        Production4PM=@Production4PM, TotalProduction=@TotalProduction, FlockId=@FlockId, BrokenEggs=@BrokenEggs, Notes=@Notes,
        EggCount=@EggCount, EggGrade=@EggGrade, MeatyEggs=@MeatyEggs, SoftEggs=@SoftEggs, LostEggs=@LostEggs,
        SpecificFeedUsedId=@SpecificFeedUsedId, SpecificFeedUsedName=@SpecificFeedUsedName, FeedUnitCost=@FeedUnitCost,
        TotalFeedConsumed=@TotalFeedConsumed, TotalFeedCost=@TotalFeedCost,
        SpecificMedicationUsedId=@SpecificMedicationUsedId, SpecificMedicationUsedName=@SpecificMedicationUsedName, MedicationUnitCost=@MedicationUnitCost,
        TotalMedicationConsumed=@TotalMedicationConsumed, TotalMedicationCost=@TotalMedicationCost,
        TotalCostOfProduction=@TotalCostOfProduction, UpdatedAt=GETUTCDATE()
    WHERE Id = @RecordId;

    IF (@FarmId IS NOT NULL)
    BEGIN
        DECLARE @mq2 DECIMAL(14,3) = -CAST(ISNULL(@Mortality,0) AS DECIMAL(14,3));
        EXEC dbo.spPoultryBirdStock_Sync @FarmId, N'Mortality', @mq2, @RecordId, N'Production mortality', @UpdatedBy;

        DECLARE @good2 INT = ISNULL(@TotalProduction,0) - ISNULL(@BrokenEggs,0) - ISNULL(@LostEggs,0);
        IF (@good2 < 0) SET @good2 = 0;
        EXEC dbo.spPoultryEggStock_SyncForProduction @FarmId, @RecordId, @good2, NULL, @UpdatedBy;

        DECLARE @OutFeedUnitCost2 DECIMAL(14,4), @OutTotalFeedCost2 DECIMAL(14,2),
                @OutMedUnitCost2 DECIMAL(14,4), @OutTotalMedCost2 DECIMAL(14,2);
        EXEC dbo.spPoultryProductionRawMaterialSync
             @FarmId, @RecordId, @SpecificFeedUsedId, @TotalFeedConsumed, @SpecificMedicationUsedId, @TotalMedicationConsumed, @UpdatedBy,
             @ComputedFeedUnitCost = @OutFeedUnitCost2 OUTPUT,
             @ComputedTotalFeedCost = @OutTotalFeedCost2 OUTPUT,
             @ComputedMedicationUnitCost = @OutMedUnitCost2 OUTPUT,
             @ComputedTotalMedicationCost = @OutTotalMedCost2 OUTPUT;

        UPDATE [dbo].[ProductionRecords]
        SET    FeedUnitCost = @OutFeedUnitCost2,
               TotalFeedCost = @OutTotalFeedCost2,
               MedicationUnitCost = @OutMedUnitCost2,
               TotalMedicationCost = @OutTotalMedCost2,
               TotalCostOfProduction = ISNULL(@OutTotalFeedCost2,0) + ISNULL(@OutTotalMedCost2,0)
        WHERE  Id = @RecordId;
    END
    COMMIT TRANSACTION;
END
GO

-- spProductionRecord_Delete is unchanged — it calls spPoultryProductionRawMaterialSync
-- with NULL feed/med (reverse-only); the new OUTPUT params default to NULL and are
-- safely ignored by that positional call.

-- =============================================================================
-- Grants to the application login (matches ConnectionStrings__PoultryConn user)
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryRawMaterialItem_Insert            TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialItem_Update            TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Insert        TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Update        TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialPurchase_Delete        TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryRawMaterialItem_ConsumeBatches    TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProductionRawMaterialSync         TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionRecord_Insert                  TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionRecord_Update                  TO [Techretainer];
    PRINT '146: granted EXECUTE on updated raw-material/production procs to Techretainer.';
END
GO

PRINT '146_RawMaterialUsageMethodBatchCosting.sql complete.';
GO
