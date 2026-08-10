-- =============================================================================
-- Migration 193: Water Daily Production (batch production, water side)
-- =============================================================================
-- A water factory runs several sachet machines in a day. The operator knows the
-- day's TOTALS -- bags produced, film used, electricity -- long before anyone
-- attributes output to a specific machine. Today /water-production-batches
-- forces one batch per machine, entered separately, with each machine's raw
-- material usage typed by hand and no cross-check that the day's film adds up.
--
-- This is the water mirror of the poultry Batch Production module (migrations
-- 156 + 164), where "flock" becomes "machine":
--
--   WaterDailyProductions            -- the day's combined totals (inert)
--     -> WaterDailyProductionMachines        (frozen machine scope)
--     -> WaterDailyProductionMaterials       (day-total raw material lines)
--     -> WaterDailyProductionAllocations     (one row per machine)
--          -> WaterDailyProductionAllocationMaterials
--
-- POST creates one real WaterProductionBatches row per allocation and runs the
-- EXISTING spWaterProductionBatch_Approve on each, so lot costing, finished
-- goods stock, auto-expenses and loss rows are all inherited -- exactly as
-- poultry's Post reuses spProductionRecord_Insert.
--
-- THREE FACTS THIS MIGRATION IS BUILT AROUND (verified, not assumed):
--
--  1. Every SP in this chain signals failure with RAISERROR + RETURN, not THROW
--     (188_WaterProductionBatchLotCosting.sql lines 106/180/182/219/535/537/549).
--     RAISERROR does NOT honour SET XACT_ABORT. Poultry's _Post has no TRY/CATCH
--     (164:122-275) and gets away with it only because its callee uses THROW.
--     Here a mid-loop shortage would otherwise let the cursor carry on and the
--     outer COMMIT commit a half-approved day. Hence TRY/CATCH + an explicit
--     assertion after every _Approve / _Reopen call.
--
--  2. UQ_WaterProductionBatches_Farm_Batch (038:123) is NOT filtered on
--     IsDeleted, so a cancelled child owns its BatchNumber forever. Reposting
--     therefore suffixes -v{PostingVersion}, and the collision probe deliberately
--     ignores IsDeleted.
--
--  3. spWaterRawMaterialItem_RecalculateStock sums ALL WaterRawMaterialUsage
--     rows with no reversal filter (177:145-147). _Reopen restores live stock but
--     leaves the usage rows, so "Recalculate stock" after a reopen subtracts the
--     same quantity twice. That is a PRE-EXISTING latent bug; reversal makes it
--     reachable and permanent. Fixed here the same way poultry fixed it in
--     migration 179: IsReversed on the usage row + a filter in the recalc.
--
-- Idempotent. Safe to re-run. Every post-hoc column add is its own COL_LENGTH
-- block OUTSIDE the CREATE TABLE guard -- the omission of that discipline is
-- what forced poultry's self-heal block at 164:43-112.
-- =============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- 1. Provenance on the existing WaterProductionBatches (mirrors 156:29-38)
-- =============================================================================
IF COL_LENGTH('dbo.WaterProductionBatches', 'WaterDailyProductionId') IS NULL
    ALTER TABLE dbo.WaterProductionBatches ADD WaterDailyProductionId INT NULL;
GO
IF COL_LENGTH('dbo.WaterProductionBatches', 'WaterDailyProductionAllocationId') IS NULL
    ALTER TABLE dbo.WaterProductionBatches ADD WaterDailyProductionAllocationId INT NULL;
GO
IF COL_LENGTH('dbo.WaterProductionBatches', 'SourceType') IS NULL
    ALTER TABLE dbo.WaterProductionBatches
        ADD SourceType NVARCHAR(30) NOT NULL
            CONSTRAINT DF_WaterProductionBatches_SourceType DEFAULT (N'ManualSingleBatch') WITH VALUES;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_WaterProductionBatches_DailyProduction'
               AND object_id = OBJECT_ID('dbo.WaterProductionBatches'))
    CREATE INDEX IX_WaterProductionBatches_DailyProduction
        ON dbo.WaterProductionBatches (FarmId, WaterDailyProductionId);
GO

-- =============================================================================
-- 2. Append-only reversal support on WaterRawMaterialUsage (fact 3, mirrors 179)
-- =============================================================================
IF COL_LENGTH('dbo.WaterRawMaterialUsage', 'IsReversed') IS NULL
    ALTER TABLE dbo.WaterRawMaterialUsage
        ADD IsReversed BIT NOT NULL
            CONSTRAINT DF_WaterRawMaterialUsage_IsReversed DEFAULT (0) WITH VALUES;
GO
IF COL_LENGTH('dbo.WaterRawMaterialUsage', 'ReversedAt') IS NULL
    ALTER TABLE dbo.WaterRawMaterialUsage ADD ReversedAt DATETIME2 NULL;
GO

-- =============================================================================
-- 3. WaterDailyProductions -- the day header
-- =============================================================================
IF OBJECT_ID('dbo.WaterDailyProductions', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterDailyProductions (
        WaterDailyProductionId   INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450) NOT NULL,
        UserId                   NVARCHAR(450) NULL,
        ProductionNumber         NVARCHAR(60)  NULL,
        ProductionDate           DATE          NOT NULL,
        Shift                    NVARCHAR(20)  NOT NULL CONSTRAINT DF_WDP_Shift DEFAULT ('FullDay'),
        -- AllMachines | CustomMachines | SingleMachine
        MachineSelectionType     NVARCHAR(20)  NOT NULL CONSTRAINT DF_WDP_MachineSel DEFAULT ('AllMachines'),
        WaterProductId           INT           NOT NULL,
        WaterBoreholeId          INT           NULL,
        OperatorStaffId          INT           NULL,
        StartTime                DATETIME2     NULL,
        EndTime                  DATETIME2     NULL,
        -- Day output totals
        BagsProduced             INT           NOT NULL CONSTRAINT DF_WDP_Bags DEFAULT (0),
        SachetsPerBag            INT           NOT NULL CONSTRAINT DF_WDP_SPB DEFAULT (30),
        LooseSachetsProduced     INT           NOT NULL CONSTRAINT DF_WDP_Loose DEFAULT (0),
        RejectedSachets          INT           NOT NULL CONSTRAINT DF_WDP_Rejected DEFAULT (0),
        DamagedBags              INT           NOT NULL CONSTRAINT DF_WDP_Damaged DEFAULT (0),
        PackagingRollsUsed       INT           NOT NULL CONSTRAINT DF_WDP_Rolls DEFAULT (0),
        EstimatedWaterUsedLitres INT           NULL,
        -- The four buckets that become WaterExpenses rows on each child's approve
        ElectricityCost          DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDP_Elec DEFAULT (0),
        FuelCost                 DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDP_Fuel DEFAULT (0),
        LaborCost                DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDP_Labor DEFAULT (0),
        OtherProductionCost      DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDP_Other DEFAULT (0),
        TotalProductionCost      AS (ElectricityCost + FuelCost + LaborCost + OtherProductionCost) PERSISTED,
        -- Preview before Post; the true post-draw total after Post.
        RawMaterialCost          DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDP_RawMatCost DEFAULT (0),
        -- Inline quality summary, same shape as WaterProductionBatches so it copies down
        QualityStatus            NVARCHAR(20)  NOT NULL CONSTRAINT DF_WDP_QualityStatus DEFAULT ('Pending'),
        QualityPHLevel           DECIMAL(5,2)  NULL,
        QualityChlorinePpm       DECIMAL(8,4)  NULL,
        QualityTurbidity         DECIMAL(8,4)  NULL,
        QualityTDS               INT           NULL,
        QualityNotes             NVARCHAR(500) NULL,
        -- Draft | PendingAllocation | Allocated | Posted | Reversed | Cancelled
        Status                   NVARCHAR(30)  NOT NULL CONSTRAINT DF_WDP_Status DEFAULT ('PendingAllocation'),
        PostingVersion           INT           NOT NULL CONSTRAINT DF_WDP_PostingVersion DEFAULT (0),
        Notes                    NVARCHAR(MAX) NULL,
        CreatedBy                NVARCHAR(450) NULL,
        CreatedAt                DATETIME2     NOT NULL CONSTRAINT DF_WDP_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedBy                NVARCHAR(450) NULL,
        UpdatedAt                DATETIME2     NULL,
        PostedBy                 NVARCHAR(450) NULL,
        PostedAt                 DATETIME2     NULL,
        ReversedBy               NVARCHAR(450) NULL,
        ReversedAt               DATETIME2     NULL,
        IsDeleted                BIT           NOT NULL CONSTRAINT DF_WDP_IsDeleted DEFAULT (0),
        CONSTRAINT FK_WDP_Product  FOREIGN KEY (WaterProductId)  REFERENCES dbo.WaterProducts (WaterProductId),
        CONSTRAINT FK_WDP_Borehole FOREIGN KEY (WaterBoreholeId) REFERENCES dbo.WaterBoreholes (WaterBoreholeId)
    );

    CREATE INDEX IX_WDP_Farm ON dbo.WaterDailyProductions (FarmId, ProductionDate DESC);
    CREATE UNIQUE INDEX UX_WDP_Number ON dbo.WaterDailyProductions (FarmId, ProductionNumber)
        WHERE ProductionNumber IS NOT NULL;
END
GO

-- =============================================================================
-- 4. WaterDailyProductionMachines -- frozen machine scope
-- =============================================================================
-- Analogue of ProductionBatchIncludedFlocks. Earns its place twice over:
-- 'AllMachines' resolves to "every Active machine" and that set moves when a
-- machine goes UnderMaintenance between create and allocate; and CapacityPerHour
-- is frozen here as the allocation weight so re-allocating reproduces the split.
-- Child tables carry no FarmId (precedent: WaterProductionRecipeItems 063:83).
-- =============================================================================
IF OBJECT_ID('dbo.WaterDailyProductionMachines', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterDailyProductionMachines (
        WaterDailyProductionMachineId INT IDENTITY(1,1) PRIMARY KEY,
        WaterDailyProductionId        INT NOT NULL,
        WaterMachineId                INT NOT NULL,
        MachineName                   NVARCHAR(150) NULL,
        MachineNumber                 NVARCHAR(60)  NULL,
        CapacityPerHour               INT NULL,
        OperatorStaffId               INT NULL,
        CreatedBy                     NVARCHAR(450) NULL,
        CreatedAt                     DATETIME2 NOT NULL CONSTRAINT DF_WDPM_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_WDPM_Header FOREIGN KEY (WaterDailyProductionId)
            REFERENCES dbo.WaterDailyProductions (WaterDailyProductionId) ON DELETE CASCADE
    );
    CREATE INDEX IX_WDPM_Header ON dbo.WaterDailyProductionMachines (WaterDailyProductionId);
END
GO

-- =============================================================================
-- 5. WaterDailyProductionMaterials -- day-total raw material lines
-- =============================================================================
-- ONE table, not poultry's feed + medication pair. Water has a single
-- WaterRawMaterialItems catalog, so two parallel tables would be ceremony.
-- =============================================================================
IF OBJECT_ID('dbo.WaterDailyProductionMaterials', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterDailyProductionMaterials (
        WaterDailyProductionMaterialId INT IDENTITY(1,1) PRIMARY KEY,
        WaterDailyProductionId         INT NOT NULL,
        WaterRawMaterialItemId         INT NOT NULL,
        ItemName                       NVARCHAR(150) NULL,
        UnitOfMeasure                  NVARCHAR(30)  NULL,
        QuantityUsed                   DECIMAL(14,3) NOT NULL CONSTRAINT DF_WDPMat_Qty DEFAULT (0),
        ExpectedQuantityUsed           DECIMAL(14,3) NULL,
        UnitCost                       DECIMAL(14,4) NULL,
        TotalCost                      AS (QuantityUsed * ISNULL(UnitCost, 0)) PERSISTED,
        VarianceReason                 NVARCHAR(500) NULL,
        Notes                          NVARCHAR(500) NULL,
        CreatedBy                      NVARCHAR(450) NULL,
        CreatedAt                      DATETIME2 NOT NULL CONSTRAINT DF_WDPMat_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_WDPMat_Header FOREIGN KEY (WaterDailyProductionId)
            REFERENCES dbo.WaterDailyProductions (WaterDailyProductionId) ON DELETE CASCADE
    );
    CREATE INDEX IX_WDPMat_Header ON dbo.WaterDailyProductionMaterials (WaterDailyProductionId);
END
GO

-- =============================================================================
-- 6. WaterDailyProductionAllocations -- one row per machine
-- =============================================================================
IF OBJECT_ID('dbo.WaterDailyProductionAllocations', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterDailyProductionAllocations (
        WaterDailyProductionAllocationId INT IDENTITY(1,1) PRIMARY KEY,
        WaterDailyProductionId           INT NOT NULL,
        WaterMachineId                   INT NOT NULL,
        MachineName                      NVARCHAR(150) NULL,
        -- Manual | ByMachineCapacity | ByPreviousProduction | EqualSplit
        AllocationMethod                 NVARCHAR(30)  NULL,
        Shift                            NVARCHAR(20)  NULL,
        OperatorStaffId                  INT           NULL,
        StartTime                        DATETIME2     NULL,
        EndTime                          DATETIME2     NULL,
        BagsProduced                     INT NOT NULL CONSTRAINT DF_WDPA_Bags DEFAULT (0),
        LooseSachetsProduced             INT NOT NULL CONSTRAINT DF_WDPA_Loose DEFAULT (0),
        RejectedSachets                  INT NOT NULL CONSTRAINT DF_WDPA_Rejected DEFAULT (0),
        DamagedBags                      INT NOT NULL CONSTRAINT DF_WDPA_Damaged DEFAULT (0),
        PackagingRollsUsed               INT NOT NULL CONSTRAINT DF_WDPA_Rolls DEFAULT (0),
        EstimatedWaterUsedLitres         INT NULL,
        ElectricityCost                  DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDPA_Elec DEFAULT (0),
        FuelCost                         DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDPA_Fuel DEFAULT (0),
        LaborCost                        DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDPA_Labor DEFAULT (0),
        OtherProductionCost              DECIMAL(14,2) NOT NULL CONSTRAINT DF_WDPA_Other DEFAULT (0),
        TotalProductionCost              AS (ElectricityCost + FuelCost + LaborCost + OtherProductionCost) PERSISTED,
        RawMaterialCost                  DECIMAL(14,2) NULL,
        Notes                            NVARCHAR(MAX) NULL,
        -- Set on Post, cleared on Reverse. No FK: the child is soft-cancelled,
        -- and allocation rows are replaced wholesale by _SaveAllocation.
        GeneratedWaterProductionBatchId  INT NULL,
        GeneratedBatchNumber             NVARCHAR(60) NULL,
        CreatedBy                        NVARCHAR(450) NULL,
        CreatedAt                        DATETIME2 NOT NULL CONSTRAINT DF_WDPA_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedBy                        NVARCHAR(450) NULL,
        UpdatedAt                        DATETIME2 NULL,
        CONSTRAINT FK_WDPA_Header FOREIGN KEY (WaterDailyProductionId)
            REFERENCES dbo.WaterDailyProductions (WaterDailyProductionId) ON DELETE CASCADE,
        CONSTRAINT UQ_WDPA_Machine UNIQUE (WaterDailyProductionId, WaterMachineId)
    );
    CREATE INDEX IX_WDPA_Header ON dbo.WaterDailyProductionAllocations (WaterDailyProductionId);
END
GO

-- =============================================================================
-- 7. WaterDailyProductionAllocationMaterials -- per-machine material split
-- =============================================================================
IF OBJECT_ID('dbo.WaterDailyProductionAllocationMaterials', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterDailyProductionAllocationMaterials (
        WaterDailyProductionAllocationMaterialId INT IDENTITY(1,1) PRIMARY KEY,
        WaterDailyProductionAllocationId INT NOT NULL,
        WaterDailyProductionMaterialId   INT NULL,
        WaterRawMaterialItemId           INT NOT NULL,
        ItemName                         NVARCHAR(150) NULL,
        QuantityAllocated                DECIMAL(14,3) NOT NULL CONSTRAINT DF_WDPAM_Qty DEFAULT (0),
        -- recipe qty per bag * this row's bags. NOT distributed by weight: the
        -- recipe is linear in bags and that is what the operator compares to.
        ExpectedQuantityAllocated        DECIMAL(14,3) NULL,
        UnitCost                         DECIMAL(14,4) NULL,
        TotalCost                        AS (QuantityAllocated * ISNULL(UnitCost, 0)) PERSISTED,
        CreatedBy                        NVARCHAR(450) NULL,
        CreatedAt                        DATETIME2 NOT NULL CONSTRAINT DF_WDPAM_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_WDPAM_Alloc FOREIGN KEY (WaterDailyProductionAllocationId)
            REFERENCES dbo.WaterDailyProductionAllocations (WaterDailyProductionAllocationId) ON DELETE CASCADE
    );
    CREATE INDEX IX_WDPAM_Alloc ON dbo.WaterDailyProductionAllocationMaterials (WaterDailyProductionAllocationId);
END
GO

-- =============================================================================
-- 8. WaterDailyProductionPostings -- append-only posting log
-- =============================================================================
-- Never deleted. Survives allocation replacement, so support can answer
-- "which batch numbers did version 1 create?" after a reverse + repost.
-- =============================================================================
IF OBJECT_ID('dbo.WaterDailyProductionPostings', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterDailyProductionPostings (
        WaterDailyProductionPostingId    INT IDENTITY(1,1) PRIMARY KEY,
        WaterDailyProductionId           INT NOT NULL,
        WaterDailyProductionAllocationId INT NULL,
        PostingVersion                   INT NOT NULL,
        WaterProductionBatchId           INT NOT NULL,
        BatchNumber                      NVARCHAR(60) NOT NULL,
        WaterMachineId                   INT NULL,
        PostedBy                         NVARCHAR(450) NULL,
        PostedAt                         DATETIME2 NOT NULL CONSTRAINT DF_WDPP_PostedAt DEFAULT (SYSUTCDATETIME()),
        ReversedBy                       NVARCHAR(450) NULL,
        ReversedAt                       DATETIME2 NULL,
        CONSTRAINT FK_WDPP_Header FOREIGN KEY (WaterDailyProductionId)
            REFERENCES dbo.WaterDailyProductions (WaterDailyProductionId) ON DELETE CASCADE
    );
    CREATE INDEX IX_WDPP_Header ON dbo.WaterDailyProductionPostings (WaterDailyProductionId, PostingVersion);
END
GO

-- =============================================================================
-- 9. Recalculate stock -- now excludes reversed usage (fact 3; supersedes 177)
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spWaterRawMaterialItem_RecalculateStock
    @FarmId                 NVARCHAR(450),
    @WaterRawMaterialItemId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Expected AS (
        SELECT i.WaterRawMaterialItemId,
               i.CurrentQuantity AS OldQuantity,
               CAST(
                   ISNULL((SELECT SUM(p.Quantity * ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1))
                           FROM   dbo.WaterRawMaterialPurchases p
                           WHERE  p.WaterRawMaterialItemId = i.WaterRawMaterialItemId AND p.FarmId = i.FarmId), 0)
                 - ISNULL((SELECT SUM(u.QuantityUsed)
                           FROM   dbo.WaterRawMaterialUsage u
                           WHERE  u.WaterRawMaterialItemId = i.WaterRawMaterialItemId AND u.FarmId = i.FarmId
                             AND  u.IsReversed = 0), 0)
                 + ISNULL((SELECT SUM(a.Quantity)
                           FROM   dbo.WaterRawMaterialAdjustments a
                           WHERE  a.WaterRawMaterialItemId = i.WaterRawMaterialItemId AND a.FarmId = i.FarmId), 0)
               AS DECIMAL(14,3)) AS RawExpected
        FROM   dbo.WaterRawMaterialItems i
        WHERE  i.FarmId = @FarmId
          AND  (@WaterRawMaterialItemId IS NULL OR i.WaterRawMaterialItemId = @WaterRawMaterialItemId)
    )
    SELECT WaterRawMaterialItemId,
           OldQuantity,
           CASE WHEN RawExpected < 0 THEN 0 ELSE RawExpected END AS NewQuantity
    INTO   #calc
    FROM   Expected;

    UPDATE i
    SET    CurrentQuantity = c.NewQuantity, UpdatedAt = SYSUTCDATETIME()
    FROM   dbo.WaterRawMaterialItems i
    INNER JOIN #calc c ON c.WaterRawMaterialItemId = i.WaterRawMaterialItemId
    WHERE  i.FarmId = @FarmId AND i.CurrentQuantity <> c.NewQuantity;

    SELECT c.WaterRawMaterialItemId,
           i.ItemName,
           i.Category,
           i.UnitOfMeasure,
           c.OldQuantity,
           c.NewQuantity,
           CAST(c.NewQuantity - c.OldQuantity AS DECIMAL(14,3)) AS Delta
    FROM   #calc c
    INNER JOIN dbo.WaterRawMaterialItems i ON i.WaterRawMaterialItemId = c.WaterRawMaterialItemId
    ORDER BY i.ItemName;

    DROP TABLE #calc;
END
GO

-- =============================================================================
-- 10. _ReplaceChildren -- machines + materials. Never touches allocations.
-- =============================================================================
-- NULL json = leave that child set alone; '' or '[]' = clear it.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spWaterDailyProduction_ReplaceChildren
    @WaterDailyProductionId INT,
    @MachinesJson           NVARCHAR(MAX) = NULL,
    @MaterialsJson          NVARCHAR(MAX) = NULL,
    @CreatedBy              NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @MachinesJson IS NOT NULL
    BEGIN
        DELETE FROM dbo.WaterDailyProductionMachines WHERE WaterDailyProductionId = @WaterDailyProductionId;

        IF LTRIM(RTRIM(@MachinesJson)) NOT IN (N'', N'[]')
            INSERT INTO dbo.WaterDailyProductionMachines
                (WaterDailyProductionId, WaterMachineId, MachineName, MachineNumber, CapacityPerHour, OperatorStaffId, CreatedBy)
            SELECT @WaterDailyProductionId, j.waterMachineId, j.machineName, j.machineNumber,
                   j.capacityPerHour, j.operatorStaffId, @CreatedBy
            FROM   OPENJSON(@MachinesJson) WITH (
                       waterMachineId  INT            '$.waterMachineId',
                       machineName     NVARCHAR(150)  '$.machineName',
                       machineNumber   NVARCHAR(60)   '$.machineNumber',
                       capacityPerHour INT            '$.capacityPerHour',
                       operatorStaffId INT            '$.operatorStaffId'
                   ) j
            WHERE  j.waterMachineId > 0;
    END

    IF @MaterialsJson IS NOT NULL
    BEGIN
        DELETE FROM dbo.WaterDailyProductionMaterials WHERE WaterDailyProductionId = @WaterDailyProductionId;

        IF LTRIM(RTRIM(@MaterialsJson)) NOT IN (N'', N'[]')
            INSERT INTO dbo.WaterDailyProductionMaterials
                (WaterDailyProductionId, WaterRawMaterialItemId, ItemName, UnitOfMeasure,
                 QuantityUsed, ExpectedQuantityUsed, UnitCost, VarianceReason, Notes, CreatedBy)
            SELECT @WaterDailyProductionId, j.waterRawMaterialItemId, j.itemName, j.unitOfMeasure,
                   ISNULL(j.quantityUsed, 0), j.expectedQuantityUsed, j.unitCost, j.varianceReason, j.notes, @CreatedBy
            FROM   OPENJSON(@MaterialsJson) WITH (
                       waterRawMaterialItemId INT            '$.waterRawMaterialItemId',
                       itemName               NVARCHAR(150)  '$.itemName',
                       unitOfMeasure          NVARCHAR(30)   '$.unitOfMeasure',
                       quantityUsed           DECIMAL(14,3)  '$.quantityUsed',
                       expectedQuantityUsed   DECIMAL(14,3)  '$.expectedQuantityUsed',
                       unitCost               DECIMAL(14,4)  '$.unitCost',
                       varianceReason         NVARCHAR(500)  '$.varianceReason',
                       notes                  NVARCHAR(500)  '$.notes'
                   ) j
            WHERE  j.waterRawMaterialItemId > 0 AND ISNULL(j.quantityUsed, 0) > 0;
    END
END
GO

-- =============================================================================
-- 11. _Insert
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spWaterDailyProduction_Insert
    @FarmId                   NVARCHAR(450),
    @UserId                   NVARCHAR(450) = NULL,
    @ProductionNumber         NVARCHAR(60)  = NULL,
    @ProductionDate           DATE,
    @Shift                    NVARCHAR(20)  = 'FullDay',
    @MachineSelectionType     NVARCHAR(20)  = 'AllMachines',
    @WaterProductId           INT,
    @WaterBoreholeId          INT = NULL,
    @OperatorStaffId          INT = NULL,
    @StartTime                DATETIME2 = NULL,
    @EndTime                  DATETIME2 = NULL,
    @BagsProduced             INT = 0,
    @SachetsPerBag            INT = 30,
    @LooseSachetsProduced     INT = 0,
    @RejectedSachets          INT = 0,
    @DamagedBags              INT = 0,
    @PackagingRollsUsed       INT = 0,
    @EstimatedWaterUsedLitres INT = NULL,
    @ElectricityCost          DECIMAL(14,2) = 0,
    @FuelCost                 DECIMAL(14,2) = 0,
    @LaborCost                DECIMAL(14,2) = 0,
    @OtherProductionCost      DECIMAL(14,2) = 0,
    @RawMaterialCost          DECIMAL(14,2) = 0,
    @QualityStatus            NVARCHAR(20)  = 'Pending',
    @QualityPHLevel           DECIMAL(5,2)  = NULL,
    @QualityChlorinePpm       DECIMAL(8,4)  = NULL,
    @QualityTurbidity         DECIMAL(8,4)  = NULL,
    @QualityTDS               INT           = NULL,
    @QualityNotes             NVARCHAR(500) = NULL,
    @Status                   NVARCHAR(30)  = 'PendingAllocation',
    @Notes                    NVARCHAR(MAX) = NULL,
    @CreatedBy                NVARCHAR(450) = NULL,
    @MachinesJson             NVARCHAR(MAX) = NULL,
    @MaterialsJson            NVARCHAR(MAX) = NULL,
    @NewId                    INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@DamagedBags > @BagsProduced) THROW 52605, 'Damaged bags cannot exceed bags produced.', 1;
    IF (@BagsProduced < 0) THROW 52606, 'Bags produced cannot be negative.', 1;

    BEGIN TRANSACTION;

    INSERT INTO dbo.WaterDailyProductions
        (FarmId, UserId, ProductionNumber, ProductionDate, Shift, MachineSelectionType,
         WaterProductId, WaterBoreholeId, OperatorStaffId, StartTime, EndTime,
         BagsProduced, SachetsPerBag, LooseSachetsProduced, RejectedSachets, DamagedBags,
         PackagingRollsUsed, EstimatedWaterUsedLitres,
         ElectricityCost, FuelCost, LaborCost, OtherProductionCost, RawMaterialCost,
         QualityStatus, QualityPHLevel, QualityChlorinePpm, QualityTurbidity, QualityTDS, QualityNotes,
         Status, Notes, CreatedBy)
    VALUES
        (@FarmId, @UserId, NULLIF(@ProductionNumber, N''), @ProductionDate, @Shift, @MachineSelectionType,
         @WaterProductId, @WaterBoreholeId, @OperatorStaffId, @StartTime, @EndTime,
         @BagsProduced, @SachetsPerBag, @LooseSachetsProduced, @RejectedSachets, @DamagedBags,
         @PackagingRollsUsed, @EstimatedWaterUsedLitres,
         @ElectricityCost, @FuelCost, @LaborCost, @OtherProductionCost, @RawMaterialCost,
         @QualityStatus, @QualityPHLevel, @QualityChlorinePpm, @QualityTurbidity, @QualityTDS, @QualityNotes,
         @Status, @Notes, @CreatedBy);

    SET @NewId = CAST(SCOPE_IDENTITY() AS INT);

    EXEC dbo.spWaterDailyProduction_ReplaceChildren
         @WaterDailyProductionId = @NewId,
         @MachinesJson  = @MachinesJson,
         @MaterialsJson = @MaterialsJson,
         @CreatedBy     = @CreatedBy;

    COMMIT TRANSACTION;
END
GO

-- =============================================================================
-- 12. _Update -- blocked once Posted or Cancelled. Reversed IS editable.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spWaterDailyProduction_Update
    @WaterDailyProductionId   INT,
    @FarmId                   NVARCHAR(450),
    @ProductionNumber         NVARCHAR(60)  = NULL,
    @ProductionDate           DATE,
    @Shift                    NVARCHAR(20)  = 'FullDay',
    @MachineSelectionType     NVARCHAR(20)  = 'AllMachines',
    @WaterProductId           INT,
    @WaterBoreholeId          INT = NULL,
    @OperatorStaffId          INT = NULL,
    @StartTime                DATETIME2 = NULL,
    @EndTime                  DATETIME2 = NULL,
    @BagsProduced             INT = 0,
    @SachetsPerBag            INT = 30,
    @LooseSachetsProduced     INT = 0,
    @RejectedSachets          INT = 0,
    @DamagedBags              INT = 0,
    @PackagingRollsUsed       INT = 0,
    @EstimatedWaterUsedLitres INT = NULL,
    @ElectricityCost          DECIMAL(14,2) = 0,
    @FuelCost                 DECIMAL(14,2) = 0,
    @LaborCost                DECIMAL(14,2) = 0,
    @OtherProductionCost      DECIMAL(14,2) = 0,
    @RawMaterialCost          DECIMAL(14,2) = 0,
    @QualityStatus            NVARCHAR(20)  = 'Pending',
    @QualityPHLevel           DECIMAL(5,2)  = NULL,
    @QualityChlorinePpm       DECIMAL(8,4)  = NULL,
    @QualityTurbidity         DECIMAL(8,4)  = NULL,
    @QualityTDS               INT           = NULL,
    @QualityNotes             NVARCHAR(500) = NULL,
    @Status                   NVARCHAR(30)  = NULL,
    @Notes                    NVARCHAR(MAX) = NULL,
    @UpdatedBy                NVARCHAR(450) = NULL,
    @MachinesJson             NVARCHAR(MAX) = NULL,
    @MaterialsJson            NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@DamagedBags > @BagsProduced) THROW 52605, 'Damaged bags cannot exceed bags produced.', 1;
    IF (@BagsProduced < 0) THROW 52606, 'Bags produced cannot be negative.', 1;

    BEGIN TRANSACTION;

    DECLARE @Current NVARCHAR(30);
    SELECT @Current = Status
    FROM   dbo.WaterDailyProductions WITH (UPDLOCK, HOLDLOCK)
    WHERE  WaterDailyProductionId = @WaterDailyProductionId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Current IS NULL THROW 52610, 'Daily production record not found.', 1;
    IF @Current IN (N'Posted', N'Cancelled')
        THROW 52611, 'A posted or cancelled daily production record cannot be edited. Reverse it first.', 1;

    UPDATE dbo.WaterDailyProductions
    SET    ProductionNumber = NULLIF(@ProductionNumber, N''),
           ProductionDate = @ProductionDate, Shift = @Shift,
           MachineSelectionType = @MachineSelectionType,
           WaterProductId = @WaterProductId, WaterBoreholeId = @WaterBoreholeId,
           OperatorStaffId = @OperatorStaffId, StartTime = @StartTime, EndTime = @EndTime,
           BagsProduced = @BagsProduced, SachetsPerBag = @SachetsPerBag,
           LooseSachetsProduced = @LooseSachetsProduced, RejectedSachets = @RejectedSachets,
           DamagedBags = @DamagedBags, PackagingRollsUsed = @PackagingRollsUsed,
           EstimatedWaterUsedLitres = @EstimatedWaterUsedLitres,
           ElectricityCost = @ElectricityCost, FuelCost = @FuelCost,
           LaborCost = @LaborCost, OtherProductionCost = @OtherProductionCost,
           RawMaterialCost = @RawMaterialCost,
           QualityStatus = @QualityStatus, QualityPHLevel = @QualityPHLevel,
           QualityChlorinePpm = @QualityChlorinePpm, QualityTurbidity = @QualityTurbidity,
           QualityTDS = @QualityTDS, QualityNotes = @QualityNotes,
           Status = ISNULL(@Status, Status),
           Notes = @Notes, UpdatedBy = @UpdatedBy, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterDailyProductionId = @WaterDailyProductionId AND FarmId = @FarmId;

    EXEC dbo.spWaterDailyProduction_ReplaceChildren
         @WaterDailyProductionId = @WaterDailyProductionId,
         @MachinesJson  = @MachinesJson,
         @MaterialsJson = @MaterialsJson,
         @CreatedBy     = @UpdatedBy;

    COMMIT TRANSACTION;
END
GO

-- =============================================================================
-- 13. _GetById -- header + FOR JSON PATH child sets
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spWaterDailyProduction_GetById
    @WaterDailyProductionId INT,
    @FarmId                 NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT h.*,
           ProductName  = p.Name,
           BoreholeName = b.BoreholeName,
           GoodBags     = (h.BagsProduced - h.DamagedBags),
           AllInCost    = (h.TotalProductionCost + h.RawMaterialCost),
           CostPerBag   = CASE WHEN (h.BagsProduced - h.DamagedBags) > 0
                               THEN CAST((h.TotalProductionCost + h.RawMaterialCost)
                                         / (h.BagsProduced - h.DamagedBags) AS DECIMAL(14,4))
                               ELSE 0 END,
           ProductionEfficiencyPercent =
               CASE WHEN (h.BagsProduced * h.SachetsPerBag) > 0
                    THEN CAST(((h.BagsProduced * h.SachetsPerBag) - h.RejectedSachets) * 100.0
                              / (h.BagsProduced * h.SachetsPerBag) AS DECIMAL(9,2))
                    ELSE 0 END,
           MachinesJson = (
               SELECT m.WaterDailyProductionMachineId, m.WaterMachineId, m.MachineName,
                      m.MachineNumber, m.CapacityPerHour, m.OperatorStaffId
               FROM   dbo.WaterDailyProductionMachines m
               WHERE  m.WaterDailyProductionId = h.WaterDailyProductionId
               ORDER  BY m.WaterDailyProductionMachineId
               FOR JSON PATH),
           MaterialsJson = (
               SELECT mt.WaterDailyProductionMaterialId, mt.WaterRawMaterialItemId, mt.ItemName,
                      mt.UnitOfMeasure, mt.QuantityUsed, mt.ExpectedQuantityUsed,
                      mt.UnitCost, mt.TotalCost, mt.VarianceReason, mt.Notes
               FROM   dbo.WaterDailyProductionMaterials mt
               WHERE  mt.WaterDailyProductionId = h.WaterDailyProductionId
               ORDER  BY mt.WaterDailyProductionMaterialId
               FOR JSON PATH),
           AllocationsJson = (
               SELECT a.WaterDailyProductionAllocationId, a.WaterMachineId, a.MachineName,
                      a.AllocationMethod, a.Shift, a.OperatorStaffId, a.StartTime, a.EndTime,
                      a.BagsProduced, a.LooseSachetsProduced, a.RejectedSachets, a.DamagedBags,
                      a.PackagingRollsUsed, a.EstimatedWaterUsedLitres,
                      a.ElectricityCost, a.FuelCost, a.LaborCost, a.OtherProductionCost,
                      a.TotalProductionCost, a.RawMaterialCost, a.Notes,
                      a.GeneratedWaterProductionBatchId, a.GeneratedBatchNumber,
                      materials = (
                          SELECT am.WaterDailyProductionAllocationMaterialId,
                                 am.WaterDailyProductionMaterialId, am.WaterRawMaterialItemId,
                                 am.ItemName, am.QuantityAllocated, am.ExpectedQuantityAllocated,
                                 am.UnitCost, am.TotalCost
                          FROM   dbo.WaterDailyProductionAllocationMaterials am
                          WHERE  am.WaterDailyProductionAllocationId = a.WaterDailyProductionAllocationId
                          ORDER  BY am.WaterDailyProductionAllocationMaterialId
                          FOR JSON PATH)
               FROM   dbo.WaterDailyProductionAllocations a
               WHERE  a.WaterDailyProductionId = h.WaterDailyProductionId
               ORDER  BY a.WaterDailyProductionAllocationId
               FOR JSON PATH),
           PostingsJson = (
               SELECT pg.WaterDailyProductionPostingId, pg.WaterDailyProductionAllocationId,
                      pg.PostingVersion, pg.WaterProductionBatchId, pg.BatchNumber,
                      pg.WaterMachineId, pg.PostedBy, pg.PostedAt, pg.ReversedBy, pg.ReversedAt
               FROM   dbo.WaterDailyProductionPostings pg
               WHERE  pg.WaterDailyProductionId = h.WaterDailyProductionId
               ORDER  BY pg.WaterDailyProductionPostingId
               FOR JSON PATH)
    FROM   dbo.WaterDailyProductions h
    LEFT   JOIN dbo.WaterProducts  p ON p.WaterProductId  = h.WaterProductId
    LEFT   JOIN dbo.WaterBoreholes b ON b.WaterBoreholeId = h.WaterBoreholeId
    WHERE  h.WaterDailyProductionId = @WaterDailyProductionId
      AND  h.FarmId = @FarmId AND h.IsDeleted = 0;
END
GO

-- =============================================================================
-- 14. _GetAll -- water convention: (@FarmId, @Status, @FromDate, @ToDate).
--     Deliberately NOT poultry's @UserId, which its SP takes and never uses.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spWaterDailyProduction_GetAll
    @FarmId   NVARCHAR(450),
    @Status   NVARCHAR(30) = NULL,
    @FromDate DATE = NULL,
    @ToDate   DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT h.*,
           ProductName  = p.Name,
           GoodBags     = (h.BagsProduced - h.DamagedBags),
           AllInCost    = (h.TotalProductionCost + h.RawMaterialCost),
           CostPerBag   = CASE WHEN (h.BagsProduced - h.DamagedBags) > 0
                               THEN CAST((h.TotalProductionCost + h.RawMaterialCost)
                                         / (h.BagsProduced - h.DamagedBags) AS DECIMAL(14,4))
                               ELSE 0 END,
           MachineCount    = (SELECT COUNT(*) FROM dbo.WaterDailyProductionMachines m
                              WHERE m.WaterDailyProductionId = h.WaterDailyProductionId),
           AllocationCount = (SELECT COUNT(*) FROM dbo.WaterDailyProductionAllocations a
                              WHERE a.WaterDailyProductionId = h.WaterDailyProductionId),
           MachinesJson = (
               SELECT m.WaterMachineId, m.MachineName, m.CapacityPerHour
               FROM   dbo.WaterDailyProductionMachines m
               WHERE  m.WaterDailyProductionId = h.WaterDailyProductionId
               ORDER  BY m.WaterDailyProductionMachineId
               FOR JSON PATH)
    FROM   dbo.WaterDailyProductions h
    LEFT   JOIN dbo.WaterProducts p ON p.WaterProductId = h.WaterProductId
    WHERE  h.FarmId = @FarmId AND h.IsDeleted = 0
      AND  (@Status   IS NULL OR h.Status = @Status)
      AND  (@FromDate IS NULL OR h.ProductionDate >= @FromDate)
      AND  (@ToDate   IS NULL OR h.ProductionDate <= @ToDate)
    ORDER  BY h.ProductionDate DESC, h.WaterDailyProductionId DESC;
END
GO

-- =============================================================================
-- 15. _Delete / _SetStatus
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spWaterDailyProduction_Delete
    @WaterDailyProductionId INT,
    @FarmId                 NVARCHAR(450),
    @UserId                 NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Status NVARCHAR(30) = (
        SELECT Status FROM dbo.WaterDailyProductions
        WHERE WaterDailyProductionId = @WaterDailyProductionId AND FarmId = @FarmId AND IsDeleted = 0);

    IF @Status IS NULL THROW 52610, 'Daily production record not found.', 1;
    IF @Status = N'Posted'
        THROW 52612, 'A posted daily production record cannot be deleted. Reverse it first.', 1;

    DELETE FROM dbo.WaterDailyProductions
    WHERE  WaterDailyProductionId = @WaterDailyProductionId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDailyProduction_SetStatus
    @WaterDailyProductionId INT,
    @FarmId                 NVARCHAR(450),
    @Status                 NVARCHAR(30),
    @UpdatedBy              NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Current NVARCHAR(30) = (
        SELECT Status FROM dbo.WaterDailyProductions
        WHERE WaterDailyProductionId = @WaterDailyProductionId AND FarmId = @FarmId AND IsDeleted = 0);

    IF @Current IS NULL THROW 52610, 'Daily production record not found.', 1;
    IF @Current = N'Posted'
        THROW 52614, 'A posted daily production record cannot change status. Reverse it first.', 1;

    UPDATE dbo.WaterDailyProductions
    SET    Status = @Status, UpdatedBy = @UpdatedBy, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterDailyProductionId = @WaterDailyProductionId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- 16. _SaveAllocation -- replace allocation rows + their material splits
-- =============================================================================
-- Row-by-row WHILE over OPENJSON so SCOPE_IDENTITY() can parent each row's
-- nested materials (same shape as poultry 164:452-499).
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spWaterDailyProduction_SaveAllocation
    @WaterDailyProductionId INT,
    @FarmId                 NVARCHAR(450),
    @AllocationsJson        NVARCHAR(MAX),
    @Status                 NVARCHAR(30) = 'Allocated',
    @UpdatedBy              NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @Current NVARCHAR(30);
    SELECT @Current = Status
    FROM   dbo.WaterDailyProductions WITH (UPDLOCK, HOLDLOCK)
    WHERE  WaterDailyProductionId = @WaterDailyProductionId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Current IS NULL THROW 52610, 'Daily production record not found.', 1;
    IF @Current IN (N'Posted', N'Cancelled')
        THROW 52621, 'Allocation cannot be changed on a posted or cancelled record.', 1;

    DELETE FROM dbo.WaterDailyProductionAllocations WHERE WaterDailyProductionId = @WaterDailyProductionId;

    DECLARE @Rows TABLE (Seq INT IDENTITY(1,1) PRIMARY KEY, Payload NVARCHAR(MAX));
    INSERT INTO @Rows (Payload)
    SELECT [value] FROM OPENJSON(ISNULL(@AllocationsJson, N'[]'));

    DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @Rows), @row NVARCHAR(MAX), @allocId INT;

    WHILE @i <= @n
    BEGIN
        SELECT @row = Payload FROM @Rows WHERE Seq = @i;

        INSERT INTO dbo.WaterDailyProductionAllocations
            (WaterDailyProductionId, WaterMachineId, MachineName, AllocationMethod, Shift,
             OperatorStaffId, StartTime, EndTime, BagsProduced, LooseSachetsProduced,
             RejectedSachets, DamagedBags, PackagingRollsUsed, EstimatedWaterUsedLitres,
             ElectricityCost, FuelCost, LaborCost, OtherProductionCost, RawMaterialCost,
             Notes, CreatedBy)
        SELECT @WaterDailyProductionId, j.waterMachineId, j.machineName, j.allocationMethod, j.shift,
               j.operatorStaffId, j.startTime, j.endTime,
               ISNULL(j.bagsProduced, 0), ISNULL(j.looseSachetsProduced, 0),
               ISNULL(j.rejectedSachets, 0), ISNULL(j.damagedBags, 0),
               ISNULL(j.packagingRollsUsed, 0), j.estimatedWaterUsedLitres,
               ISNULL(j.electricityCost, 0), ISNULL(j.fuelCost, 0),
               ISNULL(j.laborCost, 0), ISNULL(j.otherProductionCost, 0), j.rawMaterialCost,
               j.notes, @UpdatedBy
        FROM   OPENJSON(@row) WITH (
                   waterMachineId           INT           '$.waterMachineId',
                   machineName              NVARCHAR(150) '$.machineName',
                   allocationMethod         NVARCHAR(30)  '$.allocationMethod',
                   shift                    NVARCHAR(20)  '$.shift',
                   operatorStaffId          INT           '$.operatorStaffId',
                   startTime                DATETIME2     '$.startTime',
                   endTime                  DATETIME2     '$.endTime',
                   bagsProduced             INT           '$.bagsProduced',
                   looseSachetsProduced     INT           '$.looseSachetsProduced',
                   rejectedSachets          INT           '$.rejectedSachets',
                   damagedBags              INT           '$.damagedBags',
                   packagingRollsUsed       INT           '$.packagingRollsUsed',
                   estimatedWaterUsedLitres INT           '$.estimatedWaterUsedLitres',
                   electricityCost          DECIMAL(14,2) '$.electricityCost',
                   fuelCost                 DECIMAL(14,2) '$.fuelCost',
                   laborCost                DECIMAL(14,2) '$.laborCost',
                   otherProductionCost      DECIMAL(14,2) '$.otherProductionCost',
                   rawMaterialCost          DECIMAL(14,2) '$.rawMaterialCost',
                   notes                    NVARCHAR(MAX) '$.notes'
               ) j
        WHERE  j.waterMachineId > 0;

        SET @allocId = CAST(SCOPE_IDENTITY() AS INT);

        IF @allocId IS NOT NULL
            INSERT INTO dbo.WaterDailyProductionAllocationMaterials
                (WaterDailyProductionAllocationId, WaterDailyProductionMaterialId,
                 WaterRawMaterialItemId, ItemName, QuantityAllocated,
                 ExpectedQuantityAllocated, UnitCost, CreatedBy)
            SELECT @allocId, m.waterDailyProductionMaterialId, m.waterRawMaterialItemId, m.itemName,
                   ISNULL(m.quantityAllocated, 0), m.expectedQuantityAllocated, m.unitCost, @UpdatedBy
            FROM   OPENJSON(@row, '$.materials') WITH (
                       waterDailyProductionMaterialId INT           '$.waterDailyProductionMaterialId',
                       waterRawMaterialItemId         INT           '$.waterRawMaterialItemId',
                       itemName                       NVARCHAR(150) '$.itemName',
                       quantityAllocated              DECIMAL(14,3) '$.quantityAllocated',
                       expectedQuantityAllocated      DECIMAL(14,3) '$.expectedQuantityAllocated',
                       unitCost                       DECIMAL(14,4) '$.unitCost'
                   ) m
            WHERE  m.waterRawMaterialItemId > 0 AND ISNULL(m.quantityAllocated, 0) > 0;

        SET @i += 1;
    END

    UPDATE dbo.WaterDailyProductions
    SET    Status = ISNULL(@Status, N'Allocated'), UpdatedBy = @UpdatedBy, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterDailyProductionId = @WaterDailyProductionId AND FarmId = @FarmId;

    COMMIT TRANSACTION;
END
GO

PRINT '193: tables, children and CRUD procs created.';
GO

-- =============================================================================
-- 17. _Post -- create one WaterProductionBatch per allocation and approve it
-- =============================================================================
-- TRY/CATCH is MANDATORY here, not stylistic. Every callee in this chain
-- (spWaterProductionBatch_Approve, spWaterRawMaterialItem_ConsumeBatches)
-- signals failure with RAISERROR + RETURN, and RAISERROR does not honour
-- SET XACT_ABORT. Without the CATCH a mid-loop shortage would let the cursor
-- carry on and the outer COMMIT commit a half-approved day. The explicit
-- "did the child actually reach Approved?" assertion covers the same hole from
-- the other side. Poultry's _Post (164:122-275) has neither and is safe only
-- because spProductionRecord_Insert uses THROW.
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spWaterDailyProduction_Post
    @WaterDailyProductionId INT,
    @FarmId                 NVARCHAR(450),
    @PostedBy               NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Status NVARCHAR(30), @ProductionDate DATE, @Shift NVARCHAR(20),
                @ProductId INT, @BoreholeId INT, @OperatorStaffId INT,
                @SachetsPerBag INT, @PostingVersion INT, @ProductionNumber NVARCHAR(60),
                @QualityStatus NVARCHAR(20), @QualityPH DECIMAL(5,2), @QualityCl DECIMAL(8,4),
                @QualityTurb DECIMAL(8,4), @QualityTDS INT, @QualityNotes NVARCHAR(500),
                @hBags INT, @hLoose INT, @hRejected INT, @hDamaged INT, @hRolls INT, @hLitres INT,
                @hElec DECIMAL(14,2), @hFuel DECIMAL(14,2), @hLabor DECIMAL(14,2), @hOther DECIMAL(14,2);

        SELECT @Status = Status, @ProductionDate = ProductionDate, @Shift = Shift,
               @ProductId = WaterProductId, @BoreholeId = WaterBoreholeId,
               @OperatorStaffId = OperatorStaffId, @SachetsPerBag = SachetsPerBag,
               @PostingVersion = ISNULL(PostingVersion, 0), @ProductionNumber = ProductionNumber,
               @QualityStatus = QualityStatus, @QualityPH = QualityPHLevel, @QualityCl = QualityChlorinePpm,
               @QualityTurb = QualityTurbidity, @QualityTDS = QualityTDS, @QualityNotes = QualityNotes,
               @hBags = BagsProduced, @hLoose = LooseSachetsProduced, @hRejected = RejectedSachets,
               @hDamaged = DamagedBags, @hRolls = PackagingRollsUsed, @hLitres = EstimatedWaterUsedLitres,
               @hElec = ElectricityCost, @hFuel = FuelCost, @hLabor = LaborCost, @hOther = OtherProductionCost
        FROM   dbo.WaterDailyProductions WITH (UPDLOCK, HOLDLOCK)
        WHERE  WaterDailyProductionId = @WaterDailyProductionId AND FarmId = @FarmId AND IsDeleted = 0;

        IF @Status IS NULL THROW 52700, 'Daily production record not found.', 1;
        IF @Status = N'Posted' THROW 52701, 'This daily production record is already posted.', 1;
        IF @Status NOT IN (N'Allocated', N'PendingAllocation', N'Reversed')
            THROW 52702, 'Only an allocated, pending or reversed daily production record can be posted.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.WaterDailyProductionAllocations
                       WHERE WaterDailyProductionId = @WaterDailyProductionId)
            THROW 52703, 'Allocate the day across machines before posting.', 1;

        IF EXISTS (SELECT 1 FROM dbo.WaterDailyProductionAllocations a
                   WHERE a.WaterDailyProductionId = @WaterDailyProductionId
                     AND NOT EXISTS (SELECT 1 FROM dbo.WaterDailyProductionMachines m
                                     WHERE m.WaterDailyProductionId = @WaterDailyProductionId
                                       AND m.WaterMachineId = a.WaterMachineId))
            THROW 52704, 'An allocation row names a machine that is not in this day''s machine list.', 1;

        IF EXISTS (SELECT 1 FROM dbo.WaterDailyProductionAllocations
                   WHERE WaterDailyProductionId = @WaterDailyProductionId AND DamagedBags > BagsProduced)
            THROW 52705, 'A machine cannot have more damaged bags than bags produced.', 1;

        IF EXISTS (SELECT 1 FROM dbo.WaterDailyProductionAllocations
                   WHERE WaterDailyProductionId = @WaterDailyProductionId
                     AND (BagsProduced < 0 OR LooseSachetsProduced < 0 OR RejectedSachets < 0
                          OR DamagedBags < 0 OR PackagingRollsUsed < 0))
            THROW 52706, 'Allocation quantities cannot be negative.', 1;

        -- ---- Reconciliation: SUM(allocations) must equal the day header -----
        DECLARE @aBags INT, @aLoose INT, @aRejected INT, @aDamaged INT, @aRolls INT, @aLitres INT,
                @aElec DECIMAL(14,2), @aFuel DECIMAL(14,2), @aLabor DECIMAL(14,2), @aOther DECIMAL(14,2);

        SELECT @aBags = ISNULL(SUM(BagsProduced), 0), @aLoose = ISNULL(SUM(LooseSachetsProduced), 0),
               @aRejected = ISNULL(SUM(RejectedSachets), 0), @aDamaged = ISNULL(SUM(DamagedBags), 0),
               @aRolls = ISNULL(SUM(PackagingRollsUsed), 0), @aLitres = ISNULL(SUM(EstimatedWaterUsedLitres), 0),
               @aElec = ISNULL(SUM(ElectricityCost), 0), @aFuel = ISNULL(SUM(FuelCost), 0),
               @aLabor = ISNULL(SUM(LaborCost), 0), @aOther = ISNULL(SUM(OtherProductionCost), 0)
        FROM   dbo.WaterDailyProductionAllocations
        WHERE  WaterDailyProductionId = @WaterDailyProductionId;

        IF (@aBags <> @hBags OR @aLoose <> @hLoose OR @aRejected <> @hRejected
            OR @aDamaged <> @hDamaged OR @aRolls <> @hRolls)
            THROW 52710, 'The machine allocation does not add up to the day''s output totals.', 1;

        IF (@hLitres IS NOT NULL AND @aLitres <> @hLitres)
            THROW 52711, 'The allocated water usage does not add up to the day''s total.', 1;

        -- Hard gate, unlike poultry where money lines are informational: each
        -- bucket becomes a real WaterExpenses row per child (188:366-456), so an
        -- under-allocated bucket silently under-books the day's expenses.
        IF (ABS(@aElec - @hElec) > 0.01 OR ABS(@aFuel - @hFuel) > 0.01
            OR ABS(@aLabor - @hLabor) > 0.01 OR ABS(@aOther - @hOther) > 0.01)
            THROW 52712, 'The allocated production costs do not add up to the day''s cost totals.', 1;

        IF EXISTS (
            SELECT 1
            FROM   dbo.WaterDailyProductionMaterials m
            LEFT   JOIN (SELECT am.WaterRawMaterialItemId, Qty = SUM(am.QuantityAllocated)
                         FROM   dbo.WaterDailyProductionAllocationMaterials am
                         JOIN   dbo.WaterDailyProductionAllocations a
                                ON a.WaterDailyProductionAllocationId = am.WaterDailyProductionAllocationId
                         WHERE  a.WaterDailyProductionId = @WaterDailyProductionId
                         GROUP  BY am.WaterRawMaterialItemId) s
                   ON s.WaterRawMaterialItemId = m.WaterRawMaterialItemId
            WHERE  m.WaterDailyProductionId = @WaterDailyProductionId
              AND  ABS(ISNULL(s.Qty, 0) - m.QuantityUsed) > 0.001)
            THROW 52713, 'The allocated raw material quantities do not add up to the day''s totals.', 1;

        -- ...and the other way round: a material allocated to a machine that the
        -- day header never listed would otherwise slip past the check above and
        -- draw stock nobody accounted for.
        IF EXISTS (
            SELECT 1
            FROM   dbo.WaterDailyProductionAllocationMaterials am
            JOIN   dbo.WaterDailyProductionAllocations a
                   ON a.WaterDailyProductionAllocationId = am.WaterDailyProductionAllocationId
            WHERE  a.WaterDailyProductionId = @WaterDailyProductionId
              AND  am.QuantityAllocated > 0
              AND  NOT EXISTS (SELECT 1 FROM dbo.WaterDailyProductionMaterials m
                               WHERE m.WaterDailyProductionId = @WaterDailyProductionId
                                 AND m.WaterRawMaterialItemId = am.WaterRawMaterialItemId))
            THROW 52714, 'A machine was allocated a raw material that is not on the day''s material list.', 1;

        -- ---- Day-level lot pool pre-check -----------------------------------
        -- _Approve pre-checks per child, so without this the third machine fails
        -- with a message about one child batch. Same lot-pool shape as 188:191-221.
        DECLARE @ShortName NVARCHAR(150), @ShortHave DECIMAL(18,4), @ShortNeed DECIMAL(18,4);

        ;WITH Need AS (
            SELECT am.WaterRawMaterialItemId, Needed = SUM(am.QuantityAllocated)
            FROM   dbo.WaterDailyProductionAllocationMaterials am
            JOIN   dbo.WaterDailyProductionAllocations a
                   ON a.WaterDailyProductionAllocationId = am.WaterDailyProductionAllocationId
            WHERE  a.WaterDailyProductionId = @WaterDailyProductionId
            GROUP  BY am.WaterRawMaterialItemId
        )
        SELECT TOP 1 @ShortName = i.ItemName, @ShortHave = pool.LotStock, @ShortNeed = n.Needed
        FROM   Need n
        JOIN   dbo.WaterRawMaterialItems i
               ON i.WaterRawMaterialItemId = n.WaterRawMaterialItemId AND i.FarmId = @FarmId
        CROSS  APPLY (
            SELECT LotStock = ISNULL(SUM(p.RemainingQuantity
                                         * ISNULL(NULLIF(p.ProductionUnitsPerPurchaseUnit, 0), 1)), 0)
            FROM   dbo.WaterRawMaterialPurchases p
            WHERE  p.WaterRawMaterialItemId = n.WaterRawMaterialItemId
              AND  p.FarmId = @FarmId AND p.RemainingQuantity > 0) pool
        WHERE  n.Needed > pool.LotStock + 0.0005
        ORDER  BY i.ItemName;

        IF @ShortName IS NOT NULL
        BEGIN
            DECLARE @ShortMsg NVARCHAR(600) = CONCAT(
                N'Not enough stock for the whole day: ', @ShortName,
                N' needs ', CONVERT(NVARCHAR(30), CAST(@ShortNeed AS DECIMAL(14,3))),
                N' but only ', CONVERT(NVARCHAR(30), CAST(@ShortHave AS DECIMAL(14,3))),
                N' is available across purchase batches. Reduce the day''s usage, or record a purchase first.');
            THROW 52716, @ShortMsg, 1;
        END

        -- ---- Create + approve one child batch per allocation ----------------
        DECLARE @NextVersion INT = @PostingVersion + 1;
        DECLARE @BaseNo NVARCHAR(60) = ISNULL(NULLIF(@ProductionNumber, N''),
            CONCAT(N'DP-', CONVERT(CHAR(8), @ProductionDate, 112), N'-', @WaterDailyProductionId));
        DECLARE @VerSuffix NVARCHAR(10) = CASE WHEN @NextVersion > 1
                                               THEN CONCAT(N'-v', @NextVersion) ELSE N'' END;

        DECLARE @allocId INT, @machineId INT, @aShift NVARCHAR(20), @aOperator INT,
                @aStart DATETIME2, @aEnd DATETIME2,
                @rBags INT, @rLoose INT, @rRejected INT, @rDamaged INT, @rRolls INT, @rLitres INT,
                @rElec DECIMAL(14,2), @rFuel DECIMAL(14,2), @rLabor DECIMAL(14,2), @rOther DECIMAL(14,2),
                @rNotes NVARCHAR(MAX),
                @batchNo NVARCHAR(60), @newBatchId INT, @probe INT, @childStatus NVARCHAR(20),
                @childRawCost DECIMAL(14,2);

        DECLARE alloc_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT WaterDailyProductionAllocationId, WaterMachineId, Shift, OperatorStaffId,
                   StartTime, EndTime, BagsProduced, LooseSachetsProduced, RejectedSachets,
                   DamagedBags, PackagingRollsUsed, EstimatedWaterUsedLitres,
                   ElectricityCost, FuelCost, LaborCost, OtherProductionCost, Notes
            FROM   dbo.WaterDailyProductionAllocations
            WHERE  WaterDailyProductionId = @WaterDailyProductionId
            ORDER  BY WaterDailyProductionAllocationId;

        OPEN alloc_cur;
        FETCH NEXT FROM alloc_cur INTO @allocId, @machineId, @aShift, @aOperator, @aStart, @aEnd,
              @rBags, @rLoose, @rRejected, @rDamaged, @rRolls, @rLitres,
              @rElec, @rFuel, @rLabor, @rOther, @rNotes;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- 1. Batch number. The probe deliberately ignores IsDeleted: the
            --    unique index does not filter on it (038:123), so a cancelled
            --    child from an earlier posting cycle still owns its number.
            SET @batchNo = CONCAT(@BaseNo, N'/M', @machineId, @VerSuffix);
            SET @probe = 2;
            WHILE EXISTS (SELECT 1 FROM dbo.WaterProductionBatches
                          WHERE FarmId = @FarmId AND BatchNumber = @batchNo)
            BEGIN
                SET @batchNo = CONCAT(@BaseNo, N'/M', @machineId, @VerSuffix, N'-', @probe);
                SET @probe += 1;
            END

            -- 2. Insert the child directly. NOT via spWaterProductionBatch_Insert:
            --    that opens its own transaction, re-validates what we already
            --    validated, and ends with a bare SELECT (067:337) that would emit
            --    one stray result set per iteration.
            INSERT INTO dbo.WaterProductionBatches
                (FarmId, BatchNumber, ProductionDate, Shift, WaterMachineId, WaterBoreholeId,
                 OperatorStaffId, StartTime, EndTime, WaterProductId,
                 BagsProduced, SachetsPerBag, LooseSachetsProduced, RejectedSachets, DamagedBags,
                 PackagingRollsUsed, EstimatedWaterUsedLitres,
                 ElectricityCost, FuelCost, LaborCost, OtherProductionCost, RawMaterialCost,
                 QualityStatus, QualityPHLevel, QualityChlorinePpm, QualityTurbidity, QualityTDS, QualityNotes,
                 Notes, Status, CreatedBy,
                 WaterDailyProductionId, WaterDailyProductionAllocationId, SourceType)
            VALUES
                (@FarmId, @batchNo, @ProductionDate, ISNULL(@aShift, @Shift), @machineId, @BoreholeId,
                 ISNULL(@aOperator, @OperatorStaffId), @aStart, @aEnd, @ProductId,
                 @rBags, @SachetsPerBag, @rLoose, @rRejected, @rDamaged,
                 @rRolls, @rLitres,
                 @rElec, @rFuel, @rLabor, @rOther, 0,
                 @QualityStatus, @QualityPH, @QualityCl, @QualityTurb, @QualityTDS, @QualityNotes,
                 @rNotes, N'Draft', @PostedBy,
                 @WaterDailyProductionId, @allocId, N'DailyProductionAllocation');

            SET @newBatchId = CAST(SCOPE_IDENTITY() AS INT);

            -- 3. The machine's share of the day's raw materials.
            INSERT INTO dbo.WaterRawMaterialUsage
                (FarmId, WaterRawMaterialItemId, WaterProductionBatchId, UsedDate,
                 QuantityUsed, ExpectedQuantityUsed, UnitCost, UsedByStaffId)
            SELECT @FarmId, am.WaterRawMaterialItemId, @newBatchId, @ProductionDate,
                   am.QuantityAllocated, am.ExpectedQuantityAllocated, am.UnitCost,
                   ISNULL(@aOperator, @OperatorStaffId)
            FROM   dbo.WaterDailyProductionAllocationMaterials am
            WHERE  am.WaterDailyProductionAllocationId = @allocId
              AND  am.QuantityAllocated > 0;

            UPDATE dbo.WaterProductionBatches
            SET    RawMaterialCost = ISNULL((SELECT SUM(u.TotalCost) FROM dbo.WaterRawMaterialUsage u
                                             WHERE u.WaterProductionBatchId = @newBatchId), 0)
            WHERE  WaterProductionBatchId = @newBatchId;

            -- 4. Inherit the whole existing pipeline: lot draw + real costing,
            --    finished goods restock, auto-expenses, loss row.
            EXEC dbo.spWaterProductionBatch_Approve
                 @WaterProductionBatchId = @newBatchId,
                 @FarmId                 = @FarmId,
                 @ApprovedBy             = @PostedBy;

            -- 5. _Approve signals failure with RAISERROR + RETURN, which does not
            --    abort the batch. Assert the state it claims to have reached.
            SELECT @childStatus = Status, @childRawCost = ISNULL(RawMaterialCost, 0)
            FROM   dbo.WaterProductionBatches WHERE WaterProductionBatchId = @newBatchId;

            IF @childStatus <> N'Approved'
                THROW 52717, 'A machine batch could not be approved. Nothing has been posted.', 1;

            -- 6. Write back the true post-draw cost + the provenance pointers.
            UPDATE dbo.WaterDailyProductionAllocations
            SET    GeneratedWaterProductionBatchId = @newBatchId,
                   GeneratedBatchNumber = @batchNo,
                   RawMaterialCost = @childRawCost,
                   UpdatedBy = @PostedBy, UpdatedAt = SYSUTCDATETIME()
            WHERE  WaterDailyProductionAllocationId = @allocId;

            INSERT INTO dbo.WaterDailyProductionPostings
                (WaterDailyProductionId, WaterDailyProductionAllocationId, PostingVersion,
                 WaterProductionBatchId, BatchNumber, WaterMachineId, PostedBy)
            VALUES (@WaterDailyProductionId, @allocId, @NextVersion,
                    @newBatchId, @batchNo, @machineId, @PostedBy);

            FETCH NEXT FROM alloc_cur INTO @allocId, @machineId, @aShift, @aOperator, @aStart, @aEnd,
                  @rBags, @rLoose, @rRejected, @rDamaged, @rRolls, @rLitres,
                  @rElec, @rFuel, @rLabor, @rOther, @rNotes;
        END
        CLOSE alloc_cur; DEALLOCATE alloc_cur;

        UPDATE dbo.WaterDailyProductions
        SET    RawMaterialCost = ISNULL((SELECT SUM(ISNULL(a.RawMaterialCost, 0))
                                         FROM dbo.WaterDailyProductionAllocations a
                                         WHERE a.WaterDailyProductionId = @WaterDailyProductionId), 0),
               Status = N'Posted', PostingVersion = @NextVersion,
               PostedBy = @PostedBy, PostedAt = SYSUTCDATETIME(),
               ReversedBy = NULL, ReversedAt = NULL, UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterDailyProductionId = @WaterDailyProductionId AND FarmId = @FarmId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'alloc_cur') >= 0
        BEGIN
            CLOSE alloc_cur; DEALLOCATE alloc_cur;
        END
        IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- =============================================================================
-- 18. _Reverse -- reopen every child, then soft-cancel it
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spWaterDailyProduction_Reverse
    @WaterDailyProductionId INT,
    @FarmId                 NVARCHAR(450),
    @ReversedBy             NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Status NVARCHAR(30), @ProductId INT, @PostingVersion INT;

        SELECT @Status = Status, @ProductId = WaterProductId, @PostingVersion = ISNULL(PostingVersion, 0)
        FROM   dbo.WaterDailyProductions WITH (UPDLOCK, HOLDLOCK)
        WHERE  WaterDailyProductionId = @WaterDailyProductionId AND FarmId = @FarmId AND IsDeleted = 0;

        IF @Status IS NULL THROW 52720, 'Daily production record not found.', 1;
        IF @Status <> N'Posted' THROW 52721, 'Only a posted daily production record can be reversed.', 1;

        -- Day-level finished-stock pre-check. _Reopen refuses per child when
        -- stock is below that child's GoodBags (188:547-552), and reversal is
        -- sequential -- child 1 lowers stock before child 2 is checked. Ask the
        -- honest question once, with one readable message.
        DECLARE @NeedBags INT = ISNULL((
            SELECT SUM(b.BagsProduced - b.DamagedBags)
            FROM   dbo.WaterDailyProductionAllocations a
            JOIN   dbo.WaterProductionBatches b
                   ON b.WaterProductionBatchId = a.GeneratedWaterProductionBatchId
            WHERE  a.WaterDailyProductionId = @WaterDailyProductionId
              AND  a.GeneratedWaterProductionBatchId IS NOT NULL), 0);

        DECLARE @HaveBags INT = ISNULL((
            SELECT SUM(Quantity) FROM dbo.WaterStockTransactions
            WHERE FarmId = @FarmId AND WaterProductId = @ProductId), 0);

        IF (@NeedBags > 0 AND @HaveBags < @NeedBags)
        BEGIN
            DECLARE @StockMsg NVARCHAR(600) = CONCAT(
                N'This day added ', CONVERT(NVARCHAR(20), @NeedBags),
                N' bags to stock but only ', CONVERT(NVARCHAR(20), @HaveBags),
                N' remain. Cancel the related sales or adjust stock before reversing.');
            THROW 52722, @StockMsg, 1;
        END

        DECLARE @allocId INT, @childId INT, @childStatus NVARCHAR(20);

        -- LIFO: unwind draws in the opposite order to the draw.
        DECLARE rev_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT WaterDailyProductionAllocationId, GeneratedWaterProductionBatchId
            FROM   dbo.WaterDailyProductionAllocations
            WHERE  WaterDailyProductionId = @WaterDailyProductionId
              AND  GeneratedWaterProductionBatchId IS NOT NULL
            ORDER  BY WaterDailyProductionAllocationId DESC;

        OPEN rev_cur;
        FETCH NEXT FROM rev_cur INTO @allocId, @childId;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC dbo.spWaterProductionBatch_Reopen
                 @WaterProductionBatchId = @childId,
                 @FarmId                 = @FarmId,
                 @ReopenedBy             = @ReversedBy;

            SELECT @childStatus = Status FROM dbo.WaterProductionBatches
            WHERE  WaterProductionBatchId = @childId;

            IF @childStatus <> N'Draft'
                THROW 52723, 'A machine batch could not be reopened. Nothing has been reversed.', 1;

            -- Append-only: keep the usage rows, flag them. Deleting them would
            -- lose the audit trail; leaving them unflagged would make
            -- spWaterRawMaterialItem_RecalculateStock subtract the same
            -- quantity a second time (fact 3 in this file's header).
            UPDATE dbo.WaterRawMaterialUsage
            SET    IsReversed = 1, ReversedAt = SYSUTCDATETIME()
            WHERE  WaterProductionBatchId = @childId AND FarmId = @FarmId AND IsReversed = 0;

            -- Soft-cancel, never hard-delete. _Reopen reverses by COMPENSATION:
            -- an Adjust stock txn naming the batch, cancelled WaterExpenses linked
            -- by LinkedWaterProductionBatchId, a soft-deleted WaterProductionLosses
            -- row keyed on the batch id. Deleting the row would orphan all of it,
            -- and WaterQualityTests.WaterProductionBatchId is a real FK with no
            -- cascade (038:162).
            UPDATE dbo.WaterProductionBatches
            SET    Status = N'Cancelled', IsDeleted = 1, RawMaterialCost = 0,
                   Notes = LEFT(ISNULL(NULLIF(Notes, N'') + NCHAR(13) + NCHAR(10), N'')
                                + N'[Reversed with daily production]', 1000),
                   UpdatedAt = SYSUTCDATETIME()
            WHERE  WaterProductionBatchId = @childId AND FarmId = @FarmId;

            UPDATE dbo.WaterDailyProductionAllocations
            SET    GeneratedWaterProductionBatchId = NULL,   -- GeneratedBatchNumber kept
                   UpdatedBy = @ReversedBy, UpdatedAt = SYSUTCDATETIME()
            WHERE  WaterDailyProductionAllocationId = @allocId;

            UPDATE dbo.WaterDailyProductionPostings
            SET    ReversedBy = @ReversedBy, ReversedAt = SYSUTCDATETIME()
            WHERE  WaterDailyProductionId = @WaterDailyProductionId
              AND  WaterProductionBatchId = @childId AND ReversedAt IS NULL;

            FETCH NEXT FROM rev_cur INTO @allocId, @childId;
        END
        CLOSE rev_cur; DEALLOCATE rev_cur;

        -- Allocations are KEPT: a reversed day is editable, re-allocatable and
        -- repostable at a fresh PostingVersion.
        UPDATE dbo.WaterDailyProductions
        SET    Status = N'Reversed', ReversedBy = @ReversedBy, ReversedAt = SYSUTCDATETIME(),
               UpdatedAt = SYSUTCDATETIME()
        WHERE  WaterDailyProductionId = @WaterDailyProductionId AND FarmId = @FarmId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'rev_cur') >= 0
        BEGIN
            CLOSE rev_cur; DEALLOCATE rev_cur;
        END
        IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

-- =============================================================================
-- 19. _DeleteAllocation -- drop the split, keeping the day record
-- =============================================================================
CREATE OR ALTER PROCEDURE dbo.spWaterDailyProduction_DeleteAllocation
    @WaterDailyProductionId INT,
    @FarmId                 NVARCHAR(450),
    @UpdatedBy              NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(30) = (
        SELECT Status FROM dbo.WaterDailyProductions
        WHERE WaterDailyProductionId = @WaterDailyProductionId AND FarmId = @FarmId AND IsDeleted = 0);

    IF @Status IS NULL THROW 52650, 'Daily production record not found.', 1;
    IF @Status = N'Cancelled' THROW 52651, 'This daily production record is cancelled.', 1;

    -- Reverse first if it is live, so stock and cash are unwound before the
    -- split disappears.
    IF @Status = N'Posted'
        EXEC dbo.spWaterDailyProduction_Reverse
             @WaterDailyProductionId = @WaterDailyProductionId,
             @FarmId                 = @FarmId,
             @ReversedBy             = @UpdatedBy;

    DELETE FROM dbo.WaterDailyProductionAllocations
    WHERE  WaterDailyProductionId = @WaterDailyProductionId;

    UPDATE dbo.WaterDailyProductions
    SET    Status = N'PendingAllocation', UpdatedBy = @UpdatedBy, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterDailyProductionId = @WaterDailyProductionId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- 20. Grants
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterDailyProduction_ReplaceChildren  TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_Insert           TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_Update           TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_GetById          TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_GetAll           TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_Delete           TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_SetStatus        TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_SaveAllocation   TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_DeleteAllocation TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_Post             TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_Reverse          TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_RecalculateStock TO [Techretainer];
    PRINT '193: granted EXECUTE on water daily production procs to Techretainer.';
END
GO

IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterDailyProduction_ReplaceChildren  TO [PoultryAppRole];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_Insert           TO [PoultryAppRole];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_Update           TO [PoultryAppRole];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_GetById          TO [PoultryAppRole];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_GetAll           TO [PoultryAppRole];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_Delete           TO [PoultryAppRole];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_SetStatus        TO [PoultryAppRole];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_SaveAllocation   TO [PoultryAppRole];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_DeleteAllocation TO [PoultryAppRole];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_Post             TO [PoultryAppRole];
    GRANT EXECUTE ON dbo.spWaterDailyProduction_Reverse          TO [PoultryAppRole];
    GRANT EXECUTE ON dbo.spWaterRawMaterialItem_RecalculateStock TO [PoultryAppRole];
    PRINT '193: granted EXECUTE on water daily production procs to PoultryAppRole.';
END
GO

PRINT '193_WaterDailyProduction.sql complete.';
GO
