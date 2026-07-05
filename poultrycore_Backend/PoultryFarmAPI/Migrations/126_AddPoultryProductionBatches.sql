-- =============================================================================
-- Migration 126: Poultry Company — Production Batches (slice 4)
-- =============================================================================
-- Mirrors WaterProductionBatch. A batch turns raw materials into a finished
-- product. Draft batches record planned material usage; on Approve we:
--   * decrement raw-material stock by the actual quantity used,
--   * add finished-product stock (a Production stock transaction),
--   * roll up materials cost -> total cost -> cost per unit,
--   * auto-create a production-loss row for any damaged output.
-- Additive. Adds a UnitCost column to PoultryRawMaterialUsage for costing.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('dbo.PoultryRawMaterialUsage', 'UnitCost') IS NULL
    ALTER TABLE dbo.PoultryRawMaterialUsage ADD UnitCost DECIMAL(14,4) NULL;
GO

IF OBJECT_ID('dbo.PoultryProductionBatches', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryProductionBatches (
        PoultryProductionBatchId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId           NVARCHAR(450) NOT NULL,
        BatchNumber      NVARCHAR(60)  NOT NULL,
        ProductionDate   DATETIME2     NOT NULL CONSTRAINT DF_PoultryBatch_Date DEFAULT (SYSUTCDATETIME()),
        PoultryProductId INT           NOT NULL,
        QuantityProduced DECIMAL(14,3) NOT NULL CONSTRAINT DF_PoultryBatch_Qty DEFAULT (0),
        Unit             NVARCHAR(30)  NULL,
        DamagedQuantity  DECIMAL(14,3) NOT NULL CONSTRAINT DF_PoultryBatch_Damaged DEFAULT (0),
        LaborCost        DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryBatch_Labor DEFAULT (0),
        OtherCost        DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryBatch_Other DEFAULT (0),
        MaterialsCost    DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryBatch_Mat DEFAULT (0),
        TotalCost        DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryBatch_Total DEFAULT (0),
        CostPerUnit      DECIMAL(14,4) NOT NULL CONSTRAINT DF_PoultryBatch_CPU DEFAULT (0),
        Status           NVARCHAR(20)  NOT NULL CONSTRAINT DF_PoultryBatch_Status DEFAULT ('Draft'),  -- Draft | Approved | Cancelled
        Notes            NVARCHAR(500) NULL,
        CreatedBy        NVARCHAR(450) NULL,
        ApprovedBy       NVARCHAR(450) NULL,
        ApprovedAt       DATETIME2     NULL,
        CreatedAt        DATETIME2     NOT NULL CONSTRAINT DF_PoultryBatch_Created DEFAULT (SYSUTCDATETIME()),
        UpdatedAt        DATETIME2     NULL,
        CONSTRAINT FK_PoultryBatch_Product FOREIGN KEY (PoultryProductId) REFERENCES dbo.PoultryProducts (PoultryProductId)
    );
    CREATE INDEX IX_PoultryBatch_FarmId ON dbo.PoultryProductionBatches (FarmId);
    CREATE INDEX IX_PoultryBatch_Status ON dbo.PoultryProductionBatches (Status);
END
GO

IF OBJECT_ID('dbo.PoultryProductionLoss', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryProductionLoss (
        PoultryProductionLossId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId           NVARCHAR(450) NOT NULL,
        SourceType       NVARCHAR(40)  NOT NULL CONSTRAINT DF_PoultryProdLoss_Src DEFAULT ('ProductionBatch'),
        SourceId         INT           NULL,
        LossDate         DATETIME2     NOT NULL CONSTRAINT DF_PoultryProdLoss_Date DEFAULT (SYSUTCDATETIME()),
        PoultryProductId INT           NULL,
        QuantityLost     DECIMAL(14,3) NOT NULL CONSTRAINT DF_PoultryProdLoss_Qty DEFAULT (0),
        EstimatedValue   DECIMAL(14,2) NULL,
        Reason           NVARCHAR(500) NULL,
        CreatedAt        DATETIME2     NOT NULL CONSTRAINT DF_PoultryProdLoss_Created DEFAULT (SYSUTCDATETIME())
    );
    CREATE INDEX IX_PoultryProdLoss_FarmId ON dbo.PoultryProductionLoss (FarmId);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProductionBatch_GetAll
    @FarmId NVARCHAR(450), @Status NVARCHAR(20) = NULL, @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT b.*, p.Name AS ProductName
    FROM   dbo.PoultryProductionBatches b
    INNER  JOIN dbo.PoultryProducts p ON p.PoultryProductId = b.PoultryProductId
    WHERE  b.FarmId = @FarmId
       AND (@Status IS NULL OR b.Status = @Status)
       AND (@FromDate IS NULL OR CAST(b.ProductionDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(b.ProductionDate AS DATE) <= @ToDate)
    ORDER  BY b.ProductionDate DESC, b.PoultryProductionBatchId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProductionBatch_GetMaterials
    @FarmId NVARCHAR(450), @PoultryProductionBatchId INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT u.*, i.ItemName, i.UnitOfMeasure
    FROM   dbo.PoultryRawMaterialUsage u
    INNER  JOIN dbo.PoultryRawMaterialItems i ON i.PoultryRawMaterialItemId = u.PoultryRawMaterialItemId
    WHERE  u.FarmId = @FarmId AND u.PoultryProductionBatchId = @PoultryProductionBatchId
    ORDER  BY u.PoultryRawMaterialUsageId;
END
GO

-- Materials JSON: [{ poultryRawMaterialItemId, quantityUsed, expectedQuantityUsed, unitCost }]
CREATE OR ALTER PROCEDURE dbo.spPoultryProductionBatch_Insert
    @FarmId NVARCHAR(450), @BatchNumber NVARCHAR(60), @ProductionDate DATETIME2 = NULL,
    @PoultryProductId INT, @QuantityProduced DECIMAL(14,3), @Unit NVARCHAR(30) = NULL,
    @DamagedQuantity DECIMAL(14,3) = 0, @LaborCost DECIMAL(14,2) = 0, @OtherCost DECIMAL(14,2) = 0,
    @Notes NVARCHAR(500) = NULL, @CreatedBy NVARCHAR(450) = NULL, @MaterialsUsedJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    INSERT INTO dbo.PoultryProductionBatches
        (FarmId, BatchNumber, ProductionDate, PoultryProductId, QuantityProduced, Unit, DamagedQuantity, LaborCost, OtherCost, Notes, CreatedBy)
    VALUES
        (@FarmId, @BatchNumber, ISNULL(@ProductionDate, SYSUTCDATETIME()), @PoultryProductId, @QuantityProduced, @Unit,
         ISNULL(@DamagedQuantity,0), ISNULL(@LaborCost,0), ISNULL(@OtherCost,0), @Notes, @CreatedBy);

    DECLARE @BatchId INT = CAST(SCOPE_IDENTITY() AS INT);

    IF (@MaterialsUsedJson IS NOT NULL AND LEN(@MaterialsUsedJson) > 2)
        INSERT INTO dbo.PoultryRawMaterialUsage
            (FarmId, PoultryRawMaterialItemId, PoultryProductionBatchId, QuantityUsed, ExpectedQuantityUsed, UnitCost, CreatedBy)
        SELECT @FarmId, j.PoultryRawMaterialItemId, @BatchId, j.QuantityUsed, j.ExpectedQuantityUsed, j.UnitCost, @CreatedBy
        FROM OPENJSON(@MaterialsUsedJson) WITH (
            PoultryRawMaterialItemId INT          '$.poultryRawMaterialItemId',
            QuantityUsed             DECIMAL(14,3) '$.quantityUsed',
            ExpectedQuantityUsed     DECIMAL(14,3) '$.expectedQuantityUsed',
            UnitCost                 DECIMAL(14,4) '$.unitCost'
        ) j;

    COMMIT TRANSACTION;
    SELECT @BatchId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProductionBatch_Update
    @PoultryProductionBatchId INT, @FarmId NVARCHAR(450), @BatchNumber NVARCHAR(60),
    @ProductionDate DATETIME2 = NULL, @PoultryProductId INT, @QuantityProduced DECIMAL(14,3),
    @Unit NVARCHAR(30) = NULL, @DamagedQuantity DECIMAL(14,3) = 0, @LaborCost DECIMAL(14,2) = 0,
    @OtherCost DECIMAL(14,2) = 0, @Notes NVARCHAR(500) = NULL, @MaterialsUsedJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.PoultryProductionBatches WHERE PoultryProductionBatchId = @PoultryProductionBatchId AND FarmId = @FarmId AND Status = 'Draft')
    BEGIN RAISERROR('Only Draft batches can be edited.', 16, 1); RETURN; END

    BEGIN TRANSACTION;
    UPDATE dbo.PoultryProductionBatches
    SET    BatchNumber = @BatchNumber, ProductionDate = ISNULL(@ProductionDate, ProductionDate),
           PoultryProductId = @PoultryProductId, QuantityProduced = @QuantityProduced, Unit = @Unit,
           DamagedQuantity = ISNULL(@DamagedQuantity,0), LaborCost = ISNULL(@LaborCost,0),
           OtherCost = ISNULL(@OtherCost,0), Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryProductionBatchId = @PoultryProductionBatchId AND FarmId = @FarmId;

    DELETE FROM dbo.PoultryRawMaterialUsage WHERE PoultryProductionBatchId = @PoultryProductionBatchId AND FarmId = @FarmId;

    IF (@MaterialsUsedJson IS NOT NULL AND LEN(@MaterialsUsedJson) > 2)
        INSERT INTO dbo.PoultryRawMaterialUsage
            (FarmId, PoultryRawMaterialItemId, PoultryProductionBatchId, QuantityUsed, ExpectedQuantityUsed, UnitCost)
        SELECT @FarmId, j.PoultryRawMaterialItemId, @PoultryProductionBatchId, j.QuantityUsed, j.ExpectedQuantityUsed, j.UnitCost
        FROM OPENJSON(@MaterialsUsedJson) WITH (
            PoultryRawMaterialItemId INT          '$.poultryRawMaterialItemId',
            QuantityUsed             DECIMAL(14,3) '$.quantityUsed',
            ExpectedQuantityUsed     DECIMAL(14,3) '$.expectedQuantityUsed',
            UnitCost                 DECIMAL(14,4) '$.unitCost'
        ) j;

    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProductionBatch_Approve
    @PoultryProductionBatchId INT, @FarmId NVARCHAR(450), @ApprovedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ProductId INT, @Qty DECIMAL(14,3), @Damaged DECIMAL(14,3), @Labor DECIMAL(14,2), @Other DECIMAL(14,2), @Status NVARCHAR(20);
    SELECT @ProductId = PoultryProductId, @Qty = QuantityProduced, @Damaged = DamagedQuantity,
           @Labor = LaborCost, @Other = OtherCost, @Status = Status
    FROM   dbo.PoultryProductionBatches WHERE PoultryProductionBatchId = @PoultryProductionBatchId AND FarmId = @FarmId;

    IF @ProductId IS NULL BEGIN RAISERROR('Batch not found.', 16, 1); RETURN; END
    IF @Status <> 'Draft' BEGIN RAISERROR('Only Draft batches can be approved.', 16, 1); RETURN; END

    BEGIN TRANSACTION;

    -- 1. Consume raw materials.
    UPDATE i SET i.CurrentQuantity = i.CurrentQuantity - u.QuantityUsed, i.UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.PoultryRawMaterialItems i
    INNER  JOIN dbo.PoultryRawMaterialUsage u ON u.PoultryRawMaterialItemId = i.PoultryRawMaterialItemId
    WHERE  u.PoultryProductionBatchId = @PoultryProductionBatchId AND u.FarmId = @FarmId AND i.FarmId = @FarmId;

    -- 2. Materials cost roll-up.
    DECLARE @MatCost DECIMAL(14,2) = ISNULL((
        SELECT SUM(QuantityUsed * ISNULL(UnitCost,0)) FROM dbo.PoultryRawMaterialUsage
        WHERE PoultryProductionBatchId = @PoultryProductionBatchId AND FarmId = @FarmId), 0);
    DECLARE @Total DECIMAL(14,2) = @MatCost + ISNULL(@Labor,0) + ISNULL(@Other,0);
    DECLARE @Good DECIMAL(14,3) = CASE WHEN @Qty - ISNULL(@Damaged,0) > 0 THEN @Qty - ISNULL(@Damaged,0) ELSE @Qty END;
    DECLARE @CPU DECIMAL(14,4) = CASE WHEN @Good > 0 THEN @Total / @Good ELSE 0 END;

    -- 3. Add finished-product stock (good output only).
    INSERT INTO dbo.PoultryStockTransactions (FarmId, PoultryProductId, TxnType, Quantity, UnitCost, RelatedId, Note, CreatedBy)
    VALUES (@FarmId, @ProductId, 'Production', @Good, @CPU, @PoultryProductionBatchId,
            CONCAT(N'Production batch #', @PoultryProductionBatchId), @ApprovedBy);

    -- 4. Auto loss for damaged output.
    IF (ISNULL(@Damaged,0) > 0)
        INSERT INTO dbo.PoultryProductionLoss (FarmId, SourceType, SourceId, PoultryProductId, QuantityLost, EstimatedValue, Reason)
        VALUES (@FarmId, 'ProductionBatch', @PoultryProductionBatchId, @ProductId, @Damaged,
                CAST(@Damaged * @CPU AS DECIMAL(14,2)), N'Damaged output recorded on batch approval');

    -- 5. Finalize batch.
    UPDATE dbo.PoultryProductionBatches
    SET    MaterialsCost = @MatCost, TotalCost = @Total, CostPerUnit = @CPU,
           Status = 'Approved', ApprovedBy = @ApprovedBy, ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryProductionBatchId = @PoultryProductionBatchId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProductionBatch_Cancel
    @PoultryProductionBatchId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.PoultryProductionBatches WHERE PoultryProductionBatchId = @PoultryProductionBatchId AND FarmId = @FarmId AND Status = 'Draft')
    BEGIN RAISERROR('Only Draft batches can be cancelled.', 16, 1); RETURN; END
    BEGIN TRANSACTION;
    DELETE FROM dbo.PoultryRawMaterialUsage WHERE PoultryProductionBatchId = @PoultryProductionBatchId AND FarmId = @FarmId;
    UPDATE dbo.PoultryProductionBatches SET Status = 'Cancelled', UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryProductionBatchId = @PoultryProductionBatchId AND FarmId = @FarmId;
    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryProductionLoss_GetAll
    @FarmId NVARCHAR(450), @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT l.*, p.Name AS ProductName
    FROM   dbo.PoultryProductionLoss l
    LEFT   JOIN dbo.PoultryProducts p ON p.PoultryProductId = l.PoultryProductId
    WHERE  l.FarmId = @FarmId
       AND (@FromDate IS NULL OR CAST(l.LossDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(l.LossDate AS DATE) <= @ToDate)
    ORDER  BY l.LossDate DESC, l.PoultryProductionLossId DESC;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryProductionBatch_GetAll       TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProductionBatch_GetMaterials TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProductionBatch_Insert       TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProductionBatch_Update       TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProductionBatch_Approve      TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProductionBatch_Cancel       TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryProductionLoss_GetAll        TO [Techretainer];
    PRINT '126: granted EXECUTE on spPoultryProductionBatch/Loss to Techretainer.';
END
GO

PRINT '126_AddPoultryProductionBatches.sql complete.';
GO
