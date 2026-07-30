-- =============================================================================
-- Migration 184: Feed Production — persist the recipe amount behind an
--                ingredient line's quantity
-- =============================================================================
-- A batch can be mixed without a saved formula: the quantities the farmer types
-- are read as a base recipe and scaled to fill the batch, exactly the way an
-- all-fixed formula's lines are (50/30/20 typed against a 500 kg batch uses
-- 250/150/100; quantities that already add up to the batch are used as they are).
--
-- Until now only the resolved QuantityUsed was stored, so reopening a draft lost
-- the recipe it came from and the row came back as a flat number that no longer
-- followed the batch size. These columns keep it, using the same vocabulary as
-- dbo.PoultryFeedFormulaLines so the same reading applies across the module:
--
--   QuantityMode  'Quantity'      — QuantityUsed is the literal figure (default,
--                                   and what every existing row is)
--                 'FixedQuantity' — FixedQuantity is the recipe amount the farmer
--                                   typed, scaled to fill the batch
--   FixedQuantity used when QuantityMode = 'FixedQuantity'
--
-- These are a record of the farmer's intent, not an input to any calculation the
-- server does: QuantityUsed stays authoritative for costing, posting and stock
-- draws, so nothing downstream changes and existing rows keep behaving exactly
-- as before. Formula-driven lines leave QuantityMode at 'Quantity' — their share
-- lives on the formula, and the batch's FormulaId links back to it.
--
-- Additive + idempotent. Safe to re-run.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Columns on PoultryFeedProductionBatchLines
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryFeedProductionBatchLines', 'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.columns
                   WHERE object_id = OBJECT_ID('dbo.PoultryFeedProductionBatchLines') AND name = 'QuantityMode')
    BEGIN
        -- NOT NULL with a default: every existing row becomes 'Quantity', which
        -- is what it already was in effect.
        ALTER TABLE dbo.PoultryFeedProductionBatchLines
            ADD QuantityMode NVARCHAR(20) NOT NULL
                CONSTRAINT DF_PFPLine_QtyMode DEFAULT ('Quantity') WITH VALUES;
        PRINT '184: added PoultryFeedProductionBatchLines.QuantityMode.';
    END

    IF NOT EXISTS (SELECT 1 FROM sys.columns
                   WHERE object_id = OBJECT_ID('dbo.PoultryFeedProductionBatchLines') AND name = 'FixedQuantity')
    BEGIN
        ALTER TABLE dbo.PoultryFeedProductionBatchLines ADD FixedQuantity DECIMAL(18,6) NULL;
        PRINT '184: added PoultryFeedProductionBatchLines.FixedQuantity.';
    END
END
GO

IF OBJECT_ID('dbo.PoultryFeedProductionBatchLines', 'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_PFPLine_QtyMode')
BEGIN
    ALTER TABLE dbo.PoultryFeedProductionBatchLines
        ADD CONSTRAINT CK_PFPLine_QtyMode CHECK (QuantityMode IN ('Quantity','FixedQuantity'));
    PRINT '184: added CK_PFPLine_QtyMode.';
END
GO

-- -----------------------------------------------------------------------------
-- 2. SAVE — carry the share through from the client payload.
-- -----------------------------------------------------------------------------
-- Body identical to migration 174 (edits a Draft OR reopens a Reversed batch)
-- except that the ingredient-line INSERT now also persists QuantityMode and
-- FixedQuantity. A mode that isn't recognised, or a recipe amount that isn't
-- there, falls back to 'Quantity' — so an older client that doesn't send the
-- fields behaves exactly as before, and a row can never claim a mode it has no
-- figure for.
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
    -- QuantityUsed remains the authoritative figure; the recipe columns only
    -- record how the farmer arrived at it.
    IF (@LinesJson IS NOT NULL AND LEN(@LinesJson) > 2)
    BEGIN
        INSERT INTO dbo.PoultryFeedProductionBatchLines
            (PoultryFeedProductionBatchId, IngredientItemId, SourceType, QuantityUsed, UnitOfMeasure,
             QuantityMode, FixedQuantity,
             InventoryQuantityUsed, PurchasedQuantityUsed, InventoryUnitCost, PurchasedUnitCost, UnitCost, TotalCost,
             SupplierId, SupplierName, PurchaseReference, PaymentStatus, AmountPaid, PaidFromCashAccountId, PaymentMethod, SortOrder, Notes)
        SELECT @Id, j.IngredientItemId,
               CASE WHEN j.SourceType IN ('FromInventory','BoughtDuringProduction','MixedSource') THEN j.SourceType ELSE 'FromInventory' END,
               j.QuantityUsed, j.UnitOfMeasure,
               m.Mode,
               CASE WHEN m.Mode = 'FixedQuantity' THEN j.FixedQuantity END,
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
            QuantityMode          NVARCHAR(20)  '$.quantityMode',
            FixedQuantity         DECIMAL(18,6) '$.fixedQuantity',
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
            SELECT Mode = CASE
                            WHEN j.QuantityMode = 'FixedQuantity' AND ISNULL(j.FixedQuantity,0) > 0 THEN 'FixedQuantity'
                            ELSE 'Quantity' END
        ) m
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

-- spPoultryFeedProductionBatch_GetById already returns l.* for the line result
-- set, so the three new columns reach the API without a change there.

-- -----------------------------------------------------------------------------
-- 3. Grants — CREATE OR ALTER keeps existing permissions, but re-grant defensively
--    for environments where the proc was dropped and recreated.
-- -----------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'Techretainer')
BEGIN
    GRANT EXECUTE ON dbo.spPoultryFeedProductionBatch_Save TO [Techretainer];
    PRINT '184: granted EXECUTE on spPoultryFeedProductionBatch_Save to Techretainer.';
END
GO

PRINT '184_PoultryFeedProductionLineShares.sql complete.';
GO
