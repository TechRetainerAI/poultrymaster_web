-- =============================================================================
-- Migration 169: Feed Production — Batches, ingredient lines, additional costs
-- =============================================================================
-- The Feed Production batch: turns feed ingredients into finished feed with a
-- full cost breakdown. A dedicated module (NOT the generic PoultryProductionBatches).
--
--   dbo.PoultryFeedProductionBatches        — header (finished feed, quantity, costs, status)
--   dbo.PoultryFeedProductionBatchLines     — ingredient breakdown (source: inventory / bought / mixed)
--   dbo.PoultryFeedProductionAdditionalCosts — grinding, labor, transport, etc.
--
-- Lifecycle: Draft -> Posted -> Reversed. This slice covers DRAFT CRUD + cost
-- roll-up only. The transactional POST engine (inventory draws, produced stock
-- lot, cash/payable posting) and REVERSE land in later slices. Draft cost
-- figures are ESTIMATES (ingredient inventory cost is finalised from FIFO draws
-- at post time); the roll-up is always recomputed from the line/cost rows.
--
-- Additive + idempotent (object guards + CREATE OR ALTER). Safe to re-run.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. PoultryFeedProductionBatches — the batch header
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryFeedProductionBatches', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryFeedProductionBatches (
        PoultryFeedProductionBatchId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId               NVARCHAR(450) NOT NULL,
        BatchNumber          NVARCHAR(60)  NOT NULL,
        ProductionDate       DATETIME2     NOT NULL CONSTRAINT DF_PFPBatch_Date DEFAULT (SYSUTCDATETIME()),
        FinishedFeedItemId   INT           NOT NULL,   -- -> PoultryRawMaterialItems (Category 'FinishedFeed')
        FormulaId            INT           NULL,        -- -> PoultryFeedFormulas (optional)
        QuantityProduced     DECIMAL(14,3) NOT NULL CONSTRAINT DF_PFPBatch_Qty DEFAULT (0),
        OutputUnit           NVARCHAR(30)  NULL,
        TotalIngredientCost  DECIMAL(14,2) NOT NULL CONSTRAINT DF_PFPBatch_IngCost DEFAULT (0),
        TotalAdditionalCost  DECIMAL(14,2) NOT NULL CONSTRAINT DF_PFPBatch_AddCost DEFAULT (0),
        TotalProductionCost  DECIMAL(14,2) NOT NULL CONSTRAINT DF_PFPBatch_TotCost DEFAULT (0),
        CostPerOutputUnit    DECIMAL(18,4) NOT NULL CONSTRAINT DF_PFPBatch_CPU DEFAULT (0),
        Status               NVARCHAR(20)  NOT NULL CONSTRAINT DF_PFPBatch_Status DEFAULT ('Draft'),  -- Draft | Posted | Reversed
        Notes                NVARCHAR(500) NULL,
        CreatedBy            NVARCHAR(450) NULL,
        CreatedAt            DATETIME2     NOT NULL CONSTRAINT DF_PFPBatch_Created DEFAULT (SYSUTCDATETIME()),
        UpdatedAt            DATETIME2     NULL,
        PostedBy             NVARCHAR(450) NULL,
        PostedAt             DATETIME2     NULL,
        ReversedBy           NVARCHAR(450) NULL,
        ReversedAt           DATETIME2     NULL,
        ReversalReason       NVARCHAR(500) NULL,
        CONSTRAINT FK_PFPBatch_Item    FOREIGN KEY (FinishedFeedItemId) REFERENCES dbo.PoultryRawMaterialItems (PoultryRawMaterialItemId),
        CONSTRAINT FK_PFPBatch_Formula FOREIGN KEY (FormulaId)          REFERENCES dbo.PoultryFeedFormulas (PoultryFeedFormulaId),
        CONSTRAINT CK_PFPBatch_Status  CHECK (Status IN ('Draft','Posted','Reversed')),
        CONSTRAINT UQ_PFPBatch_Farm_Number UNIQUE (FarmId, BatchNumber)
    );
    CREATE INDEX IX_PFPBatch_FarmId ON dbo.PoultryFeedProductionBatches (FarmId);
    CREATE INDEX IX_PFPBatch_Status ON dbo.PoultryFeedProductionBatches (Status);
    CREATE INDEX IX_PFPBatch_Date   ON dbo.PoultryFeedProductionBatches (ProductionDate);
END
GO

-- -----------------------------------------------------------------------------
-- 2. PoultryFeedProductionBatchLines — ingredient breakdown
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryFeedProductionBatchLines', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryFeedProductionBatchLines (
        PoultryFeedProductionBatchLineId INT IDENTITY(1,1) PRIMARY KEY,
        PoultryFeedProductionBatchId INT           NOT NULL,
        IngredientItemId             INT           NOT NULL,   -- -> PoultryRawMaterialItems (Category 'FeedIngredient')
        SourceType                   NVARCHAR(30)  NOT NULL CONSTRAINT DF_PFPLine_Source DEFAULT ('FromInventory'), -- FromInventory | BoughtDuringProduction | MixedSource
        QuantityUsed                 DECIMAL(14,3) NOT NULL,
        UnitOfMeasure                NVARCHAR(30)  NULL,
        InventoryQuantityUsed        DECIMAL(14,3) NULL,
        PurchasedQuantityUsed        DECIMAL(14,3) NULL,
        InventoryUnitCost            DECIMAL(18,4) NULL,
        PurchasedUnitCost            DECIMAL(18,4) NULL,
        UnitCost                     DECIMAL(18,4) NOT NULL CONSTRAINT DF_PFPLine_Unit DEFAULT (0),  -- weighted
        TotalCost                    DECIMAL(14,2) NOT NULL CONSTRAINT DF_PFPLine_Total DEFAULT (0),
        SupplierId                   INT           NULL,
        SupplierName                 NVARCHAR(200) NULL,
        PurchaseReference            NVARCHAR(100) NULL,
        PaymentStatus                NVARCHAR(20)  NULL,        -- Paid | Unpaid | Partial (bought/mixed only)
        AmountPaid                   DECIMAL(14,2) NULL,
        PaidFromCashAccountId        INT           NULL,
        PaymentMethod                NVARCHAR(30)  NULL,
        SortOrder                    INT           NOT NULL CONSTRAINT DF_PFPLine_Sort DEFAULT (0),
        Notes                        NVARCHAR(300) NULL,
        CONSTRAINT FK_PFPLine_Batch FOREIGN KEY (PoultryFeedProductionBatchId) REFERENCES dbo.PoultryFeedProductionBatches (PoultryFeedProductionBatchId) ON DELETE CASCADE,
        CONSTRAINT FK_PFPLine_Item  FOREIGN KEY (IngredientItemId) REFERENCES dbo.PoultryRawMaterialItems (PoultryRawMaterialItemId),
        CONSTRAINT CK_PFPLine_Source CHECK (SourceType IN ('FromInventory','BoughtDuringProduction','MixedSource'))
    );
    CREATE INDEX IX_PFPLine_Batch ON dbo.PoultryFeedProductionBatchLines (PoultryFeedProductionBatchId);
END
GO

-- -----------------------------------------------------------------------------
-- 3. PoultryFeedProductionAdditionalCosts — grinding, labor, transport, etc.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.PoultryFeedProductionAdditionalCosts', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryFeedProductionAdditionalCosts (
        PoultryFeedProductionAdditionalCostId INT IDENTITY(1,1) PRIMARY KEY,
        PoultryFeedProductionBatchId INT           NOT NULL,
        CostType                     NVARCHAR(40)  NOT NULL,    -- Labor | Grinding | Transport | Electricity | Fuel | Packaging | MachineMaintenance | Other
        Amount                       DECIMAL(14,2) NOT NULL CONSTRAINT DF_PFPCost_Amount DEFAULT (0),
        PaymentStatus                NVARCHAR(20)  NULL,        -- Paid | Unpaid | Partial
        AmountPaid                   DECIMAL(14,2) NULL,
        PaidFromCashAccountId        INT           NULL,
        PaymentMethod                NVARCHAR(30)  NULL,
        SupplierId                   INT           NULL,
        PayeeName                    NVARCHAR(200) NULL,
        SortOrder                    INT           NOT NULL CONSTRAINT DF_PFPCost_Sort DEFAULT (0),
        Notes                        NVARCHAR(300) NULL,
        CONSTRAINT FK_PFPCost_Batch FOREIGN KEY (PoultryFeedProductionBatchId) REFERENCES dbo.PoultryFeedProductionBatches (PoultryFeedProductionBatchId) ON DELETE CASCADE
    );
    CREATE INDEX IX_PFPCost_Batch ON dbo.PoultryFeedProductionAdditionalCosts (PoultryFeedProductionBatchId);
END
GO

-- =============================================================================
-- Stored procedures — DRAFT CRUD + cost roll-up
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spPoultryFeedProductionBatch_GetAll
    @FarmId   NVARCHAR(450),
    @FromDate DATETIME2 = NULL,
    @ToDate   DATETIME2 = NULL,
    @Status   NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT b.*,
           i.ItemName      AS FinishedFeedItemName,
           i.UnitOfMeasure AS FinishedFeedUnit,
           f.FormulaName   AS FormulaName
    FROM   dbo.PoultryFeedProductionBatches b
    LEFT   JOIN dbo.PoultryRawMaterialItems i ON i.PoultryRawMaterialItemId = b.FinishedFeedItemId
    LEFT   JOIN dbo.PoultryFeedFormulas     f ON f.PoultryFeedFormulaId     = b.FormulaId
    WHERE  b.FarmId = @FarmId
      AND  (@FromDate IS NULL OR b.ProductionDate >= @FromDate)
      AND  (@ToDate   IS NULL OR b.ProductionDate < DATEADD(DAY, 1, @ToDate))
      AND  (@Status   IS NULL OR b.Status = @Status)
    ORDER  BY b.ProductionDate DESC, b.PoultryFeedProductionBatchId DESC;
END
GO

-- Header (result 1) + ingredient lines (result 2) + additional costs (result 3).
CREATE OR ALTER PROCEDURE dbo.spPoultryFeedProductionBatch_GetById
    @FarmId NVARCHAR(450), @PoultryFeedProductionBatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT b.*,
           i.ItemName AS FinishedFeedItemName, i.UnitOfMeasure AS FinishedFeedUnit,
           f.FormulaName AS FormulaName
    FROM   dbo.PoultryFeedProductionBatches b
    LEFT   JOIN dbo.PoultryRawMaterialItems i ON i.PoultryRawMaterialItemId = b.FinishedFeedItemId
    LEFT   JOIN dbo.PoultryFeedFormulas     f ON f.PoultryFeedFormulaId     = b.FormulaId
    WHERE  b.FarmId = @FarmId AND b.PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId;

    SELECT l.*, i.ItemName AS IngredientName, i.CurrentQuantity AS AvailableStock
    FROM   dbo.PoultryFeedProductionBatchLines l
    INNER  JOIN dbo.PoultryFeedProductionBatches b ON b.PoultryFeedProductionBatchId = l.PoultryFeedProductionBatchId
    LEFT   JOIN dbo.PoultryRawMaterialItems i ON i.PoultryRawMaterialItemId = l.IngredientItemId
    WHERE  b.FarmId = @FarmId AND l.PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId
    ORDER  BY l.SortOrder, l.PoultryFeedProductionBatchLineId;

    SELECT c.*
    FROM   dbo.PoultryFeedProductionAdditionalCosts c
    INNER  JOIN dbo.PoultryFeedProductionBatches b ON b.PoultryFeedProductionBatchId = c.PoultryFeedProductionBatchId
    WHERE  b.FarmId = @FarmId AND c.PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId
    ORDER  BY c.SortOrder, c.PoultryFeedProductionAdditionalCostId;
END
GO

-- Insert (when @Id is NULL/0) or update a DRAFT batch and replace its lines and
-- additional costs. Refuses to touch a Posted/Reversed batch. Auto-generates a
-- batch number (FP-YYYY-000N) on insert when none is supplied. Recomputes the
-- cost roll-up from the provided line/cost rows and returns the batch id.
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
        IF (@CurStatus <> 'Draft') BEGIN ROLLBACK TRANSACTION; THROW 51001, 'Only draft batches can be edited. Reverse the batch to make changes.', 1; END
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
        UPDATE dbo.PoultryFeedProductionBatches
        SET    BatchNumber = ISNULL(NULLIF(LTRIM(RTRIM(@BatchNumber)), ''), BatchNumber),
               ProductionDate = @ProductionDate, FinishedFeedItemId = @FinishedFeedItemId,
               FormulaId = @FormulaId, QuantityProduced = @QuantityProduced, OutputUnit = @OutputUnit,
               Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
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

-- Delete a DRAFT batch (lines + costs cascade). Posted/Reversed batches must be
-- reversed, not deleted.
CREATE OR ALTER PROCEDURE dbo.spPoultryFeedProductionBatch_Delete
    @FarmId NVARCHAR(450), @PoultryFeedProductionBatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Status NVARCHAR(20);
    SELECT @Status = Status FROM dbo.PoultryFeedProductionBatches
    WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;

    IF (@Status IS NULL) RETURN;
    IF (@Status <> 'Draft') THROW 51002, 'Only draft batches can be deleted. Reverse a posted batch instead.', 1;

    DELETE FROM dbo.PoultryFeedProductionBatches
    WHERE PoultryFeedProductionBatchId = @PoultryFeedProductionBatchId AND FarmId = @FarmId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryFeedProductionBatch_GetAll  TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryFeedProductionBatch_GetById TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryFeedProductionBatch_Save    TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryFeedProductionBatch_Delete  TO [Techretainer];
    PRINT '169: granted EXECUTE on spPoultryFeedProductionBatch_* to Techretainer.';
END
GO

PRINT '169_PoultryFeedProductionBatches.sql complete.';
GO
