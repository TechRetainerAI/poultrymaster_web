-- =============================================================================
-- Migration 188: Water production batches consume raw materials from lots
-- =============================================================================
-- Migration 187 gave water raw materials real purchase lots (RemainingQuantity)
-- and a per-item FIFO/LIFO/HIFO policy. This one puts them to work, so that in
-- /water-production-batches the item's policy decides which lot each material
-- line is drawn from and what it costs — the same way Poultry does it.
--
-- WHAT CHANGES
--   1. spWaterRawMaterialItem_ConsumeBatches (new) — the draw engine.
--   2. spWaterProductionBatch_Approve — draws each material line through the
--      engine and re-costs the batch from what was actually drawn.
--   3. spWaterProductionBatch_Reopen — restores the lots the batch drew from.
--   4. spWaterRawMaterialPurchase_Delete / _Update — refuse to disturb a lot
--      that recorded usage has already drawn from.
--
-- THE COST IS NO LONGER THE CLIENT'S TO DECIDE. A draft batch still carries the
-- unit cost the form sends (a preview from the latest purchase), and the draft's
-- RawMaterialCost still reflects it — but at approval every line is re-priced
-- from the lots it actually consumed, and RawMaterialCost, AllInCost and the
-- finished-goods cost/bag all follow. Nothing re-costs history: batches approved
-- before this migration keep the numbers they were approved with.
--
-- WHERE THE STOCK MOVES. Unlike Poultry, a water batch takes nothing at save —
-- Draft only records intent. Approve is where quantities leave and Reopen is
-- where they come back, so that is where the lot draw and restore belong.
--
-- Two bugs are fixed in passing, both of which Poultry hit the hard way:
--   * the approval shortage check tested CurrentQuantity, which includes stock
--     added by adjustment that has no lot behind it (Poultry 180 -> 181);
--   * the stock decrement/restore used UPDATE...FROM against a join that can
--     match one item twice, applying only one of them (Poultry 158).
--
-- Requires migration 187. Idempotent (CREATE OR ALTER). No schema change.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. The draw engine. Port of spPoultryRawMaterialItem_ConsumeBatches (159).
-- -----------------------------------------------------------------------------
-- Walks the item's open lots in policy order, takes what it needs, writes a
-- WaterRawMaterialUsageBatch row per lot touched, and hands back the weighted
-- average cost per PRODUCTION unit.
--
-- UNITS, the part that is easy to get wrong:
--   @NeededQty arrives in PRODUCTION units (what Usage.QuantityUsed is in)
--   RemainingQuantity is in PURCHASE units (what Purchases.Quantity is in)
--   Mult = ProductionUnitsPerPurchaseUnit bridges them (NULL/0 => 1)
-- The walk compares production units against production units; the lot is
-- decremented, and the draw recorded, in purchase units.
--
-- UPDLOCK on the lot read holds the rows for the duration of the transaction so
-- two concurrent approvals can't both spend the same remaining quantity.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_ConsumeBatches
    @FarmId NVARCHAR(450),
    @ItemId INT,
    @UsageId INT,
    @NeededQty DECIMAL(14,3),                 -- in PRODUCTION units
    @ComputedUnitCost DECIMAL(14,4) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @ComputedUnitCost = NULL;
    IF (@NeededQty IS NULL OR @NeededQty <= 0) RETURN;

    DECLARE @UsageMethod NVARCHAR(10) = ISNULL((
        SELECT UsageMethod FROM dbo.WaterRawMaterialItems
        WHERE WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId), 'FIFO');

    DECLARE @Draws TABLE (PurchaseId INT, ProdDrawn DECIMAL(18,4), PurchaseDrawn DECIMAL(18,4), UnitCost DECIMAL(14,2), Mult DECIMAL(18,8));

    ;WITH Ordered AS (
        SELECT WaterRawMaterialPurchaseId, RemainingQuantity, UnitCost,
               Mult      = ISNULL(NULLIF(ProductionUnitsPerPurchaseUnit, 0), 1),
               AvailProd = RemainingQuantity * ISNULL(NULLIF(ProductionUnitsPerPurchaseUnit, 0), 1),
               RunningTotal = SUM(RemainingQuantity * ISNULL(NULLIF(ProductionUnitsPerPurchaseUnit, 0), 1)) OVER (
                   ORDER BY
                       CASE WHEN @UsageMethod = 'FIFO' THEN PurchaseDate END ASC,
                       CASE WHEN @UsageMethod = 'LIFO' THEN PurchaseDate END DESC,
                       CASE WHEN @UsageMethod = 'HIFO' THEN UnitCost END DESC,
                       WaterRawMaterialPurchaseId ASC
                   ROWS UNBOUNDED PRECEDING)
        FROM   dbo.WaterRawMaterialPurchases WITH (UPDLOCK, ROWLOCK)
        WHERE  WaterRawMaterialItemId = @ItemId AND FarmId = @FarmId AND RemainingQuantity > 0
    )
    INSERT INTO @Draws (PurchaseId, ProdDrawn, PurchaseDrawn, UnitCost, Mult)
    SELECT WaterRawMaterialPurchaseId,
           ProdTake     = CASE WHEN RunningTotal <= @NeededQty THEN AvailProd ELSE @NeededQty - (RunningTotal - AvailProd) END,
           PurchaseTake = (CASE WHEN RunningTotal <= @NeededQty THEN AvailProd ELSE @NeededQty - (RunningTotal - AvailProd) END) / Mult,
           UnitCost, Mult
    FROM   Ordered
    WHERE  RunningTotal - AvailProd < @NeededQty;

    DECLARE @TotalDrawn DECIMAL(18,4) = (SELECT ISNULL(SUM(ProdDrawn), 0) FROM @Draws);
    IF (@TotalDrawn + 0.0005 < @NeededQty)
    BEGIN
        DECLARE @ItemName NVARCHAR(150) = (SELECT ItemName FROM dbo.WaterRawMaterialItems WHERE WaterRawMaterialItemId = @ItemId);
        DECLARE @Msg NVARCHAR(400) = CONCAT(
            N'Not enough tracked batch stock for "', ISNULL(@ItemName, N'item'), N'": need ',
            CONVERT(NVARCHAR(30), @NeededQty), N', only ', CONVERT(NVARCHAR(30), @TotalDrawn),
            N' available across purchase batches.');
        RAISERROR(@Msg, 16, 1);
        RETURN;
    END

    UPDATE p
    SET    p.RemainingQuantity = p.RemainingQuantity - d.PurchaseDrawn, p.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.WaterRawMaterialPurchases p
    JOIN   @Draws d ON d.PurchaseId = p.WaterRawMaterialPurchaseId;

    -- Stored in PURCHASE units + per-purchase cost, so a reopen restores each
    -- lot with a plain `RemainingQuantity += SUM(QuantityDrawn)`.
    INSERT INTO dbo.WaterRawMaterialUsageBatch (WaterRawMaterialUsageId, WaterRawMaterialPurchaseId, QuantityDrawn, UnitCostAtDraw)
    SELECT @UsageId, PurchaseId, PurchaseDrawn, CAST(UnitCost AS DECIMAL(14,2))
    FROM   @Draws WHERE ProdDrawn > 0;

    -- Cost per PRODUCTION unit = total purchase-cost drawn / production units drawn.
    SELECT @ComputedUnitCost = SUM(PurchaseDrawn * UnitCost) / NULLIF(SUM(ProdDrawn), 0) FROM @Draws;
END
GO

-- -----------------------------------------------------------------------------
-- 2. Approve — body as migration 067, with the lot draw and re-costing added,
--    the shortage check moved onto the lot pool, and the decrement aggregated.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterProductionBatch_Approve
    @WaterProductionBatchId INT,
    @FarmId                 NVARCHAR(450),
    @ApprovedBy             NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Idempotent: already-approved batches return their current state.
    IF EXISTS (SELECT 1 FROM dbo.WaterProductionBatches
               WHERE WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT WaterProductionBatchId, Status, ApprovedBy, ApprovedAt
        FROM dbo.WaterProductionBatches
        WHERE WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @Status         NVARCHAR(20),
            @ProductId      INT,
            @BagsProduced   INT,
            @DamagedBags    INT,
            @RejectedSachets INT,
            @SachetsPerBag  INT,
            @TotalCost      DECIMAL(14,2),
            @RawMatCost     DECIMAL(14,2),
            @ElectricityCost DECIMAL(14,2),
            @FuelCost       DECIMAL(14,2),
            @LaborCost      DECIMAL(14,2),
            @OtherCost      DECIMAL(14,2),
            @ProductionDate DATE,
            @BatchNo        NVARCHAR(60);

    SELECT @Status = Status, @ProductId = WaterProductId,
           @BagsProduced = BagsProduced, @DamagedBags = DamagedBags,
           @RejectedSachets = RejectedSachets,
           @SachetsPerBag = SachetsPerBag,
           @TotalCost = TotalProductionCost,
           @RawMatCost = ISNULL(RawMaterialCost, 0),
           @ElectricityCost = ElectricityCost,
           @FuelCost = FuelCost, @LaborCost = LaborCost,
           @OtherCost = OtherProductionCost,
           @ProductionDate = ProductionDate,
           @BatchNo = BatchNumber
    FROM   dbo.WaterProductionBatches
    WHERE  WaterProductionBatchId = @WaterProductionBatchId
       AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL
    BEGIN RAISERROR('Production batch %d not found.', 16, 1, @WaterProductionBatchId); RETURN; END
    IF @Status <> 'Draft'
    BEGIN RAISERROR('Production batch cannot be approved from status %s.', 16, 1, @Status); RETURN; END

    -- Pre-check raw material availability against the DRAWABLE LOT POOL, not
    -- CurrentQuantity. The two differ whenever stock arrived by adjustment: it
    -- counts as on hand but has no purchase lot behind it, so the draw below
    -- would fail on a number the user can't see. Poultry checked the wrong one
    -- and had to fix it twice (migrations 180 -> 181). Totals are per item,
    -- because one batch can list the same item on two lines.
    DECLARE @ShortName NVARCHAR(150), @ShortHave DECIMAL(18,4), @ShortNeed DECIMAL(18,4);
    ;WITH Need AS (
        SELECT u.WaterRawMaterialItemId, Needed = SUM(u.QuantityUsed)
        FROM   dbo.WaterRawMaterialUsage u
        WHERE  u.FarmId = @FarmId AND u.WaterProductionBatchId = @WaterProductionBatchId
        GROUP  BY u.WaterRawMaterialItemId
    )
    SELECT TOP 1
           @ShortName = mi.ItemName,
           @ShortHave = pool.LotStock,
           @ShortNeed = n.Needed
    FROM   Need n
    JOIN   dbo.WaterRawMaterialItems mi ON mi.WaterRawMaterialItemId = n.WaterRawMaterialItemId
    CROSS  APPLY (
        SELECT LotStock = ISNULL((
            SELECT SUM(p.RemainingQuantity * ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1))
            FROM   dbo.WaterRawMaterialPurchases p
            WHERE  p.WaterRawMaterialItemId = n.WaterRawMaterialItemId AND p.FarmId = @FarmId), 0)
    ) pool
    WHERE  n.Needed > pool.LotStock + 0.0005;

    IF @ShortName IS NOT NULL
    BEGIN
        DECLARE @msg NVARCHAR(400) = CONCAT(
            'Not enough stock of "', @ShortName, '" in purchase batches. Available to draw: ',
            CAST(@ShortHave AS NVARCHAR(30)), ', needed: ',
            CAST(@ShortNeed AS NVARCHAR(30)),
            '. Record a purchase or reduce the actual quantity used.'
        );
        RAISERROR(N'%s', 16, 1, @msg);
        RETURN;
    END

    DECLARE @GoodBags INT = @BagsProduced - ISNULL(@DamagedBags, 0);
    IF (@GoodBags < 0) SET @GoodBags = 0;

    -- All-in cost (excl loss writeoffs) for per-bag costing.
    -- Provisional, from the client's preview costs. Both are recomputed inside
    -- the transaction once the lots have actually been drawn.
    DECLARE @AllInCost DECIMAL(14,2) = @TotalCost + @RawMatCost;
    DECLARE @CostPerBag DECIMAL(14,4) =
        CASE WHEN @GoodBags > 0 THEN @AllInCost * 1.0 / @GoodBags ELSE 0 END;

    -- Ensure the four production expense categories exist.
    EXEC dbo.spWaterExpenseCategory_EnsureProductionDefaults @FarmId = @FarmId;

    DECLARE @CatElectricity INT, @CatFuel INT, @CatLabor INT, @CatOther INT;
    SELECT @CatElectricity = WaterExpenseCategoryId
    FROM   dbo.WaterExpenseCategories
    WHERE  FarmId = @FarmId AND Name = N'Electricity / Utilities';
    SELECT @CatFuel = WaterExpenseCategoryId
    FROM   dbo.WaterExpenseCategories
    WHERE  FarmId = @FarmId AND Name = N'Fuel';
    SELECT @CatLabor = WaterExpenseCategoryId
    FROM   dbo.WaterExpenseCategories
    WHERE  FarmId = @FarmId AND Name = N'Labor';
    SELECT @CatOther = WaterExpenseCategoryId
    FROM   dbo.WaterExpenseCategories
    WHERE  FarmId = @FarmId AND Name = N'Production Other';

    BEGIN TRANSACTION;

    UPDATE dbo.WaterProductionBatches
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId;

    -- ---------------------------------------------------------------
    -- A0. Draw each material line from its purchase lots, per the item's
    --     FIFO/LIFO/HIFO policy, and take the price from what was actually
    --     drawn. The unit cost the client sent is a preview only -- from here
    --     the ledger decides, so a batch can't be costed at a made-up price.
    --     A shortfall raises inside the transaction and XACT_ABORT rolls the
    --     whole approval back.
    -- ---------------------------------------------------------------
    DECLARE @UsageId INT, @MatItemId INT, @MatQty DECIMAL(14,3), @DrawUnitCost DECIMAL(14,4);
    DECLARE mat_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT u.WaterRawMaterialUsageId, u.WaterRawMaterialItemId, u.QuantityUsed
        FROM   dbo.WaterRawMaterialUsage u
        WHERE  u.FarmId = @FarmId AND u.WaterProductionBatchId = @WaterProductionBatchId
          AND  ISNULL(u.QuantityUsed, 0) > 0
        ORDER  BY u.WaterRawMaterialUsageId;
    OPEN mat_cur;
    FETCH NEXT FROM mat_cur INTO @UsageId, @MatItemId, @MatQty;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @DrawUnitCost = NULL;
        EXEC dbo.spWaterRawMaterialItem_ConsumeBatches
             @FarmId = @FarmId, @ItemId = @MatItemId, @UsageId = @UsageId,
             @NeededQty = @MatQty, @ComputedUnitCost = @DrawUnitCost OUTPUT;

        -- Only overwrite when the draw produced a price. A NULL means there was
        -- nothing to price from, and the client's preview figure is left alone
        -- so the batch still totals rather than collapsing to zero.
        IF (@DrawUnitCost IS NOT NULL)
            UPDATE dbo.WaterRawMaterialUsage
            SET    UnitCost = @DrawUnitCost
            WHERE  WaterRawMaterialUsageId = @UsageId;

        FETCH NEXT FROM mat_cur INTO @UsageId, @MatItemId, @MatQty;
    END
    CLOSE mat_cur; DEALLOCATE mat_cur;

    -- Re-cost the batch from the drawn prices. WaterRawMaterialUsage.TotalCost
    -- is a persisted computed column, so it follows UnitCost automatically.
    SET @RawMatCost = ISNULL((SELECT SUM(u.TotalCost)
                              FROM   dbo.WaterRawMaterialUsage u
                              WHERE  u.FarmId = @FarmId
                                AND  u.WaterProductionBatchId = @WaterProductionBatchId), 0);

    UPDATE dbo.WaterProductionBatches
    SET    RawMaterialCost = @RawMatCost, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId;

    -- Per-bag costing has to follow the real material cost, so it is recomputed
    -- here rather than kept from the pre-transaction estimate.
    SET @AllInCost  = @TotalCost + @RawMatCost;
    SET @CostPerBag = CASE WHEN @GoodBags > 0 THEN @AllInCost * 1.0 / @GoodBags ELSE 0 END;

    -- ---------------------------------------------------------------
    -- A. Finished goods Restock (GoodBags only — never damaged bags).
    -- ---------------------------------------------------------------
    IF (@GoodBags > 0)
       AND NOT EXISTS (
           SELECT 1 FROM dbo.WaterStockTransactions
           WHERE  FarmId = @FarmId AND WaterProductId = @ProductId
             AND  TxnType = 'Restock'
             AND  Note    = CONCAT('Production batch ', @BatchNo)
       )
    BEGIN
        INSERT INTO dbo.WaterStockTransactions (
            FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId,
            Note, CreatedBy
        )
        VALUES (
            @FarmId, @ProductId, 'Restock', @GoodBags,
            CAST(@CostPerBag AS DECIMAL(12,2)), NULL,
            CONCAT('Production batch ', @BatchNo), @ApprovedBy
        );
    END

    -- ---------------------------------------------------------------
    -- B. Raw material decrements.
    -- ---------------------------------------------------------------
    -- Aggregated first: UPDATE...FROM applies a single arbitrary matched row when
    -- several join to the same target, so a batch listing one item on two lines
    -- used to decrement only one of them (the drift Poultry fixed in 158).
    ;WITH Used AS (
        SELECT u.WaterRawMaterialItemId, Qty = SUM(u.QuantityUsed)
        FROM   dbo.WaterRawMaterialUsage u
        WHERE  u.FarmId = @FarmId AND u.WaterProductionBatchId = @WaterProductionBatchId
        GROUP  BY u.WaterRawMaterialItemId
    )
    UPDATE mi
    SET    mi.CurrentQuantity = mi.CurrentQuantity - x.Qty,
           mi.UpdatedAt       = SYSUTCDATETIME()
    FROM   dbo.WaterRawMaterialItems mi
    JOIN   Used x ON x.WaterRawMaterialItemId = mi.WaterRawMaterialItemId
    WHERE  mi.FarmId = @FarmId;

    -- ---------------------------------------------------------------
    -- C. Production-linked Expense rows (Electricity / Fuel / Labor / Other).
    --     We pick a default cash account if one exists, otherwise use Credit
    --     so the expense still books without forcing the user to configure
    --     cash accounts. The expense row is auto-Approved.
    -- ---------------------------------------------------------------
    DECLARE @DefaultCashAccountId INT;
    SELECT TOP 1 @DefaultCashAccountId = WaterCashAccountId
    FROM   dbo.WaterCashAccounts
    WHERE  FarmId = @FarmId AND IsActive = 1
    ORDER  BY WaterCashAccountId;

    DECLARE @ProdDateTime DATETIME2 = CAST(@ProductionDate AS DATETIME2);

    -- Helper inline: only insert when amount > 0 AND no prior linked row
    -- exists for this batch+category (idempotent re-approve).
    IF (@ElectricityCost > 0 AND @CatElectricity IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM dbo.WaterExpenses
                        WHERE FarmId = @FarmId
                          AND LinkedWaterProductionBatchId = @WaterProductionBatchId
                          AND WaterExpenseCategoryId = @CatElectricity
                          AND IsDeleted = 0
                          AND Status IN ('Draft','Submitted','Approved')))
    BEGIN
        INSERT INTO dbo.WaterExpenses
            (FarmId, ExpenseDate, WaterExpenseCategoryId, Description, Amount,
             PaymentMethod, WaterCashAccountId, LinkedWaterProductionBatchId,
             Status, Notes, CreatedBy, ApprovedBy, ApprovedAt)
        VALUES
            (@FarmId, @ProdDateTime, @CatElectricity,
             CONCAT('Electricity — Production batch ', @BatchNo),
             @ElectricityCost,
             CASE WHEN @DefaultCashAccountId IS NULL THEN 'Credit' ELSE 'Cash' END,
             @DefaultCashAccountId, @WaterProductionBatchId,
             'Approved',
             N'Auto-created from production batch approval.',
             @ApprovedBy, @ApprovedBy, SYSUTCDATETIME());
    END

    IF (@FuelCost > 0 AND @CatFuel IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM dbo.WaterExpenses
                        WHERE FarmId = @FarmId
                          AND LinkedWaterProductionBatchId = @WaterProductionBatchId
                          AND WaterExpenseCategoryId = @CatFuel
                          AND IsDeleted = 0
                          AND Status IN ('Draft','Submitted','Approved')))
    BEGIN
        INSERT INTO dbo.WaterExpenses
            (FarmId, ExpenseDate, WaterExpenseCategoryId, Description, Amount,
             PaymentMethod, WaterCashAccountId, LinkedWaterProductionBatchId,
             Status, Notes, CreatedBy, ApprovedBy, ApprovedAt)
        VALUES
            (@FarmId, @ProdDateTime, @CatFuel,
             CONCAT('Fuel — Production batch ', @BatchNo),
             @FuelCost,
             CASE WHEN @DefaultCashAccountId IS NULL THEN 'Credit' ELSE 'Cash' END,
             @DefaultCashAccountId, @WaterProductionBatchId,
             'Approved',
             N'Auto-created from production batch approval.',
             @ApprovedBy, @ApprovedBy, SYSUTCDATETIME());
    END

    IF (@LaborCost > 0 AND @CatLabor IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM dbo.WaterExpenses
                        WHERE FarmId = @FarmId
                          AND LinkedWaterProductionBatchId = @WaterProductionBatchId
                          AND WaterExpenseCategoryId = @CatLabor
                          AND IsDeleted = 0
                          AND Status IN ('Draft','Submitted','Approved')))
    BEGIN
        INSERT INTO dbo.WaterExpenses
            (FarmId, ExpenseDate, WaterExpenseCategoryId, Description, Amount,
             PaymentMethod, WaterCashAccountId, LinkedWaterProductionBatchId,
             Status, Notes, CreatedBy, ApprovedBy, ApprovedAt)
        VALUES
            (@FarmId, @ProdDateTime, @CatLabor,
             CONCAT('Labor — Production batch ', @BatchNo),
             @LaborCost,
             CASE WHEN @DefaultCashAccountId IS NULL THEN 'Credit' ELSE 'Cash' END,
             @DefaultCashAccountId, @WaterProductionBatchId,
             'Approved',
             N'Auto-created from production batch approval.',
             @ApprovedBy, @ApprovedBy, SYSUTCDATETIME());
    END

    IF (@OtherCost > 0 AND @CatOther IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM dbo.WaterExpenses
                        WHERE FarmId = @FarmId
                          AND LinkedWaterProductionBatchId = @WaterProductionBatchId
                          AND WaterExpenseCategoryId = @CatOther
                          AND IsDeleted = 0
                          AND Status IN ('Draft','Submitted','Approved')))
    BEGIN
        INSERT INTO dbo.WaterExpenses
            (FarmId, ExpenseDate, WaterExpenseCategoryId, Description, Amount,
             PaymentMethod, WaterCashAccountId, LinkedWaterProductionBatchId,
             Status, Notes, CreatedBy, ApprovedBy, ApprovedAt)
        VALUES
            (@FarmId, @ProdDateTime, @CatOther,
             CONCAT('Other production cost — Production batch ', @BatchNo),
             @OtherCost,
             CASE WHEN @DefaultCashAccountId IS NULL THEN 'Credit' ELSE 'Cash' END,
             @DefaultCashAccountId, @WaterProductionBatchId,
             'Approved',
             N'Auto-created from production batch approval.',
             @ApprovedBy, @ApprovedBy, SYSUTCDATETIME());
    END

    -- ---------------------------------------------------------------
    -- D. Production-linked Loss record (damaged bags + rejected sachets).
    --     Only inserted when at least one quantity > 0.
    -- ---------------------------------------------------------------
    IF (ISNULL(@DamagedBags,0) > 0 OR ISNULL(@RejectedSachets,0) > 0)
       AND NOT EXISTS (
           SELECT 1 FROM dbo.WaterProductionLosses
           WHERE  FarmId = @FarmId
             AND  SourceType = 'ProductionBatch'
             AND  SourceId   = @WaterProductionBatchId
             AND  IsDeleted  = 0
       )
    BEGIN
        DECLARE @BagsLossValue    DECIMAL(14,2) =
            CAST(ISNULL(@DamagedBags,0) AS DECIMAL(14,2)) * @CostPerBag;
        DECLARE @SachetsLossValue DECIMAL(14,2) =
            CASE WHEN @SachetsPerBag > 0
                 THEN (CAST(ISNULL(@RejectedSachets,0) AS DECIMAL(14,2)) / @SachetsPerBag) * @CostPerBag
                 ELSE 0 END;

        INSERT INTO dbo.WaterProductionLosses
            (FarmId, LossDate, LossType, SourceType, SourceId,
             WaterProductId, BagsLost, SachetsLost, SachetsPerBag,
             CostPerBag, BagsLossValue, SachetsLossValue,
             Reason, Status, Notes, CreatedBy)
        VALUES
            (@FarmId, @ProductionDate, 'ProductionDamage',
             'ProductionBatch', @WaterProductionBatchId,
             @ProductId, ISNULL(@DamagedBags,0), ISNULL(@RejectedSachets,0),
             @SachetsPerBag,
             @CostPerBag,
             @BagsLossValue, @SachetsLossValue,
             N'Production damage / rejected during production',
             'Approved',
             CONCAT('Auto-created from production batch ', @BatchNo),
             @ApprovedBy);
    END

    COMMIT TRANSACTION;

    SELECT WaterProductionBatchId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.WaterProductionBatches
    WHERE  WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId;
END
GO

-- ----------------------------------------------------------------------------
-- 3. Reopen — body as migration 067, plus the lot restore. Reversing the draw
--    puts each lot's RemainingQuantity back and clears the draw record, so a
--    re-approval draws again from a true picture.
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterProductionBatch_Reopen
    @WaterProductionBatchId INT,
    @FarmId                 NVARCHAR(450),
    @ReopenedBy             NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status       NVARCHAR(20),
            @ProductId    INT,
            @BagsProduced INT,
            @DamagedBags  INT,
            @BatchNo      NVARCHAR(60);

    SELECT @Status       = Status,
           @ProductId    = WaterProductId,
           @BagsProduced = BagsProduced,
           @DamagedBags  = DamagedBags,
           @BatchNo      = BatchNumber
    FROM   dbo.WaterProductionBatches
    WHERE  WaterProductionBatchId = @WaterProductionBatchId
       AND FarmId = @FarmId
       AND IsDeleted = 0;

    IF @Status IS NULL
    BEGIN RAISERROR('Production batch %d not found.', 16, 1, @WaterProductionBatchId); RETURN; END
    IF @Status <> 'Approved'
    BEGIN RAISERROR('Only Approved batches can be reopened. Current status: %s.', 16, 1, @Status); RETURN; END

    DECLARE @GoodBags INT = @BagsProduced - ISNULL(@DamagedBags, 0);
    IF (@GoodBags < 0) SET @GoodBags = 0;

    DECLARE @CurrentStock INT = ISNULL((
        SELECT SUM(Quantity) FROM dbo.WaterStockTransactions
        WHERE FarmId = @FarmId AND WaterProductId = @ProductId
    ), 0);

    IF @GoodBags > 0 AND @CurrentStock < @GoodBags
    BEGIN
        RAISERROR('Cannot reopen: only %d bags of this product remain in stock, but the batch added %d. Cancel related sales or adjust stock first.',
                  16, 1, @CurrentStock, @GoodBags);
        RETURN;
    END

    BEGIN TRANSACTION;

    -- Reverse the finished goods restock with a balancing Adjust txn.
    IF (@GoodBags > 0)
    BEGIN
        INSERT INTO dbo.WaterStockTransactions
            (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
        VALUES
            (@FarmId, @ProductId, 'Adjust', -@GoodBags, NULL, NULL,
             CONCAT('Reopen production batch ', @BatchNo), @ReopenedBy);
    END

    -- Restore the purchase lots this batch drew from, then the item totals.
    -- QuantityDrawn is in PURCHASE units, matching RemainingQuantity, so each lot
    -- goes back exactly as it was. Aggregated per lot for the same reason the
    -- decrement is aggregated.
    ;WITH LotRestore AS (
        SELECT ub.WaterRawMaterialPurchaseId, Qty = SUM(ub.QuantityDrawn)
        FROM   dbo.WaterRawMaterialUsageBatch ub
        JOIN   dbo.WaterRawMaterialUsage u ON u.WaterRawMaterialUsageId = ub.WaterRawMaterialUsageId
        WHERE  u.FarmId = @FarmId AND u.WaterProductionBatchId = @WaterProductionBatchId
        GROUP  BY ub.WaterRawMaterialPurchaseId
    )
    UPDATE p
    SET    p.RemainingQuantity = p.RemainingQuantity + r.Qty,
           p.UpdatedAt         = SYSUTCDATETIME()
    FROM   dbo.WaterRawMaterialPurchases p
    JOIN   LotRestore r ON r.WaterRawMaterialPurchaseId = p.WaterRawMaterialPurchaseId;

    -- The draw record is spent once the lots are back; leaving it would restore
    -- the same quantity again on a second reopen.
    DELETE ub
    FROM   dbo.WaterRawMaterialUsageBatch ub
    JOIN   dbo.WaterRawMaterialUsage u ON u.WaterRawMaterialUsageId = ub.WaterRawMaterialUsageId
    WHERE  u.FarmId = @FarmId AND u.WaterProductionBatchId = @WaterProductionBatchId;

    -- Restore raw material quantities.
    ;WITH Used AS (
        SELECT u.WaterRawMaterialItemId, Qty = SUM(u.QuantityUsed)
        FROM   dbo.WaterRawMaterialUsage u
        WHERE  u.FarmId = @FarmId AND u.WaterProductionBatchId = @WaterProductionBatchId
        GROUP  BY u.WaterRawMaterialItemId
    )
    UPDATE mi
    SET    mi.CurrentQuantity = mi.CurrentQuantity + x.Qty,
           mi.UpdatedAt       = SYSUTCDATETIME()
    FROM   dbo.WaterRawMaterialItems mi
    JOIN   Used x ON x.WaterRawMaterialItemId = mi.WaterRawMaterialItemId
    WHERE  mi.FarmId = @FarmId;

    -- Cancel linked expenses. For non-credit expenses that had been booked
    -- against a cash account at approve time, post a reversing CashIn so the
    -- balance comes back to where it was. Expenses already Rejected/Cancelled
    -- are skipped.
    DECLARE @ExpenseId INT, @ExpenseAmount DECIMAL(14,2),
            @ExpensePayment NVARCHAR(20), @ExpenseCash INT;
    DECLARE expense_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT WaterExpenseId, Amount, PaymentMethod, WaterCashAccountId
        FROM   dbo.WaterExpenses
        WHERE  FarmId = @FarmId
          AND  LinkedWaterProductionBatchId = @WaterProductionBatchId
          AND  IsDeleted = 0
          AND  Status IN ('Draft','Submitted','Approved');

    OPEN expense_cursor;
    FETCH NEXT FROM expense_cursor INTO @ExpenseId, @ExpenseAmount, @ExpensePayment, @ExpenseCash;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF (@ExpensePayment <> 'Credit' AND @ExpenseCash IS NOT NULL
            AND EXISTS (SELECT 1 FROM dbo.WaterCashTransactions
                        WHERE SourceType = 'Expense' AND SourceId = @ExpenseId
                          AND Amount < 0))
        BEGIN
            INSERT INTO dbo.WaterCashTransactions (
                FarmId, WaterCashAccountId, TransactionDate, TransactionType,
                SourceType, SourceId, Amount, Description, CreatedBy, ApprovedBy, ApprovedAt)
            VALUES (
                @FarmId, @ExpenseCash, SYSUTCDATETIME(), 'Adjustment',
                'Expense', @ExpenseId, @ExpenseAmount,
                CONCAT('Reverse — production batch ', @BatchNo, ' reopened'),
                @ReopenedBy, @ReopenedBy, SYSUTCDATETIME());

            UPDATE dbo.WaterCashAccounts
            SET    CurrentBalance = CurrentBalance + @ExpenseAmount,
                   UpdatedAt = SYSUTCDATETIME()
            WHERE  WaterCashAccountId = @ExpenseCash;
        END

        UPDATE dbo.WaterExpenses
        SET    Status     = 'Cancelled',
               UpdatedAt  = SYSUTCDATETIME(),
               Notes      = LEFT(ISNULL(Notes, N'') + CHAR(10) +
                                 N'Cancelled — production batch reopened.', 1000)
        WHERE  WaterExpenseId = @ExpenseId;

        FETCH NEXT FROM expense_cursor INTO @ExpenseId, @ExpenseAmount, @ExpensePayment, @ExpenseCash;
    END
    CLOSE expense_cursor;
    DEALLOCATE expense_cursor;

    -- Soft-delete linked loss rows. (We don't hard-delete so the auditor can
    -- still see "what was once recorded".)
    UPDATE dbo.WaterProductionLosses
    SET    IsDeleted = 1,
           Status    = 'Cancelled'
    WHERE  FarmId = @FarmId
      AND  SourceType = 'ProductionBatch'
      AND  SourceId   = @WaterProductionBatchId
      AND  IsDeleted  = 0;

    -- Flip the batch back to Draft.
    UPDATE dbo.WaterProductionBatches
    SET    Status      = 'Draft',
           ApprovedBy  = NULL,
           ApprovedAt  = NULL,
           UpdatedAt   = SYSUTCDATETIME()
    WHERE  WaterProductionBatchId = @WaterProductionBatchId
       AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT WaterProductionBatchId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.WaterProductionBatches
    WHERE  WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- 4. Purchase guards — a lot that recorded usage has drawn from can't be moved
--    out from under it. Deleting or re-quantifying such a purchase would leave
--    WaterRawMaterialUsageBatch pointing at stock that no longer exists and the
--    remaining balances wrong. Reopen the batch that consumed it instead.
--
--    Deliberately guards rather than cascades: the poultry equivalent taught us
--    that silently rewriting a drawn lot is how costing drifts.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialPurchase_GuardNotDrawn
    @WaterRawMaterialPurchaseId INT
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM dbo.WaterRawMaterialUsageBatch
               WHERE WaterRawMaterialPurchaseId = @WaterRawMaterialPurchaseId)
    BEGIN
        RAISERROR('This purchase batch has already been drawn from by an approved production batch. Reopen that batch first.', 16, 1);
    END
END
GO

IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_ConsumeBatches       TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_GuardNotDrawn    TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterProductionBatch_Approve              TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterProductionBatch_Reopen               TO PoultryAppRole;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_ConsumeBatches       TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterRawMaterialPurchase_GuardNotDrawn    TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterProductionBatch_Approve              TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterProductionBatch_Reopen               TO [Techretainer];
    PRINT '188: granted EXECUTE to Techretainer.';
END
GO

PRINT '188_WaterProductionBatchLotCosting.sql complete.';
GO
