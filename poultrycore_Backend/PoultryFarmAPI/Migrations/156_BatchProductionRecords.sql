-- =============================================================================
-- Migration 156: Batch-level production records + allocation workflow
-- =============================================================================
-- Adds a batch-level production layer on top of the existing flock-level
-- ProductionRecords. A batch record captures TOTAL production for a group of
-- flocks (a specific bird batch, all active flocks, or a custom flock set) and
-- is inert (status PendingAllocation) until an allocation distributes those
-- totals across the included flocks and is POSTED. Posting reuses the existing
-- spProductionRecord_Insert per allocated flock, so all bird / egg / raw-material
-- side-effects are inherited unchanged. Reversing deletes the generated flock
-- records (spProductionRecord_Delete) which reverses those same side-effects.
--
-- Design mirrors migration 148 (multi-feed): child tables + JSON params +
-- spPoultryRawMaterialItem_ConsumeBatches for costing. Idempotent throughout.
--
-- Statuses: Draft, PendingAllocation, Allocated, Posted, Reversed, Cancelled.
-- BatchSelectionType: SpecificBatch, AllBatches, CustomBatch.
-- SourceType (on ProductionRecords): ManualSingleFlock, BatchAllocation.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 0. Provenance columns on the flock-level ProductionRecords.
-- -----------------------------------------------------------------------------
IF COL_LENGTH('dbo.ProductionRecords', 'ProductionBatchId') IS NULL
    ALTER TABLE dbo.ProductionRecords ADD ProductionBatchId INT NULL;
GO
IF COL_LENGTH('dbo.ProductionRecords', 'ProductionBatchAllocationId') IS NULL
    ALTER TABLE dbo.ProductionRecords ADD ProductionBatchAllocationId INT NULL;
GO
IF COL_LENGTH('dbo.ProductionRecords', 'SourceType') IS NULL
    ALTER TABLE dbo.ProductionRecords ADD SourceType NVARCHAR(30) NOT NULL
        CONSTRAINT DF_ProductionRecords_SourceType DEFAULT (N'ManualSingleFlock');
GO

-- -----------------------------------------------------------------------------
-- 1. Header: one row per batch production entry.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.ProductionBatchRecords', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductionBatchRecords (
        Id                     INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                 NVARCHAR(450) NOT NULL,
        UserId                 NVARCHAR(450) NULL,
        BatchSelectionType     NVARCHAR(20)  NOT NULL,          -- SpecificBatch | AllBatches | CustomBatch
        SelectedBirdBatchId    INT           NULL,              -- FK MainFlockBatch.BatchId when SpecificBatch
        BatchName              NVARCHAR(150) NULL,              -- display / custom-batch name
        ProductionDate         DATE          NOT NULL,
        AgeInWeeks             INT           NULL,              -- only meaningful for SpecificBatch
        AgeInDays              INT           NULL,
        AgeDisplay             NVARCHAR(50)  NULL,              -- "N/A" / "Mixed" / "42w 3d"
        FirstPickCrates        INT           NULL,
        FirstPickLooseEggs     INT           NULL,
        FirstPickTotal         INT           NOT NULL CONSTRAINT DF_PBR_P1 DEFAULT (0),
        SecondPickCrates       INT           NULL,
        SecondPickLooseEggs    INT           NULL,
        SecondPickTotal        INT           NOT NULL CONSTRAINT DF_PBR_P2 DEFAULT (0),
        ThirdPickCrates        INT           NULL,
        ThirdPickLooseEggs     INT           NULL,
        ThirdPickTotal         INT           NOT NULL CONSTRAINT DF_PBR_P3 DEFAULT (0),
        FourthPickCrates       INT           NULL,
        FourthPickLooseEggs    INT           NULL,
        FourthPickTotal        INT           NOT NULL CONSTRAINT DF_PBR_P4 DEFAULT (0),
        BrokenEggs             INT           NULL,
        MeatyEggs              INT           NULL,
        SoftEggs               INT           NULL,
        LostEggs               INT           NULL,
        TotalEggs              INT           NOT NULL CONSTRAINT DF_PBR_Total DEFAULT (0),
        FeedKg                 DECIMAL(18,2) NULL,
        Deaths                 INT           NOT NULL CONSTRAINT DF_PBR_Deaths DEFAULT (0),
        BirdsLeft              INT           NULL,
        EggGrade               NVARCHAR(50)  NULL,
        FeedType               NVARCHAR(100) NULL,
        Medication             NVARCHAR(500) NULL,
        TotalFeedCost          DECIMAL(14,2) NULL,
        TotalMedicationCost    DECIMAL(14,2) NULL,
        TotalCostOfProduction  DECIMAL(14,2) NULL,
        Status                 NVARCHAR(30)  NOT NULL CONSTRAINT DF_PBR_Status DEFAULT (N'PendingAllocation'),
        Notes                  NVARCHAR(MAX) NULL,
        CreatedBy              NVARCHAR(450) NULL,
        CreatedDate            DATETIME2     NOT NULL CONSTRAINT DF_PBR_Created DEFAULT (SYSUTCDATETIME()),
        UpdatedBy              NVARCHAR(450) NULL,
        UpdatedDate            DATETIME2     NULL,
        PostedBy               NVARCHAR(450) NULL,
        PostedDate             DATETIME2     NULL
    );
    CREATE INDEX IX_PBR_Farm ON dbo.ProductionBatchRecords (FarmId, ProductionDate DESC);
END
GO

-- -----------------------------------------------------------------------------
-- 2. Frozen included-flock list (the flocks allocation will distribute across).
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.ProductionBatchIncludedFlocks', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductionBatchIncludedFlocks (
        Id                      INT IDENTITY(1,1) PRIMARY KEY,
        ProductionBatchRecordId INT           NOT NULL,
        FlockId                 INT           NOT NULL,
        FlockName               NVARCHAR(150) NULL,
        BirdBatchId             INT           NULL,
        CreatedBy               NVARCHAR(450) NULL,
        CreatedDate             DATETIME2     NOT NULL CONSTRAINT DF_PBIF_Created DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_PBIF_Batch FOREIGN KEY (ProductionBatchRecordId)
            REFERENCES dbo.ProductionBatchRecords (Id) ON DELETE CASCADE
    );
    CREATE INDEX IX_PBIF_Batch ON dbo.ProductionBatchIncludedFlocks (ProductionBatchRecordId);
END
GO

-- -----------------------------------------------------------------------------
-- 3. Batch-level feed usage lines (one per feed item entered on the batch).
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.ProductionBatchFeedUsage', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductionBatchFeedUsage (
        Id                       INT IDENTITY(1,1) PRIMARY KEY,
        ProductionBatchRecordId  INT           NOT NULL,
        InventoryItemId          INT           NOT NULL,
        ItemName                 NVARCHAR(150) NULL,
        QuantityUsed             DECIMAL(14,3) NOT NULL,
        UnitCost                 DECIMAL(14,4) NULL,
        TotalCost                DECIMAL(14,2) NULL,
        CostingMethod            NVARCHAR(20)  NULL,
        CreatedBy                NVARCHAR(450) NULL,
        CreatedDate              DATETIME2     NOT NULL CONSTRAINT DF_PBFU_Created DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_PBFU_Batch FOREIGN KEY (ProductionBatchRecordId)
            REFERENCES dbo.ProductionBatchRecords (Id) ON DELETE CASCADE
    );
    CREATE INDEX IX_PBFU_Batch ON dbo.ProductionBatchFeedUsage (ProductionBatchRecordId);
END
GO

-- -----------------------------------------------------------------------------
-- 4. Batch-level medication usage lines.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.ProductionBatchMedicationUsage', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductionBatchMedicationUsage (
        Id                       INT IDENTITY(1,1) PRIMARY KEY,
        ProductionBatchRecordId  INT           NOT NULL,
        InventoryItemId          INT           NOT NULL,
        ItemName                 NVARCHAR(150) NULL,
        QuantityUsed             DECIMAL(14,3) NOT NULL,
        UnitCost                 DECIMAL(14,4) NULL,
        TotalCost                DECIMAL(14,2) NULL,
        CostingMethod            NVARCHAR(20)  NULL,
        CreatedBy                NVARCHAR(450) NULL,
        CreatedDate              DATETIME2     NOT NULL CONSTRAINT DF_PBMU_Created DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_PBMU_Batch FOREIGN KEY (ProductionBatchRecordId)
            REFERENCES dbo.ProductionBatchRecords (Id) ON DELETE CASCADE
    );
    CREATE INDEX IX_PBMU_Batch ON dbo.ProductionBatchMedicationUsage (ProductionBatchRecordId);
END
GO

-- -----------------------------------------------------------------------------
-- 5. Per-flock allocation rows.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.ProductionBatchAllocations', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductionBatchAllocations (
        Id                       INT IDENTITY(1,1) PRIMARY KEY,
        ProductionBatchRecordId  INT           NOT NULL,
        FlockId                  INT           NOT NULL,
        FlockName                NVARCHAR(150) NULL,
        AllocationMethod         NVARCHAR(30)  NULL,     -- Manual | ByBirdCount | ByPreviousProduction | EqualSplit
        AgeInWeeks               INT           NULL,
        AgeInDays                INT           NULL,
        BirdsBefore              INT           NULL,
        Deaths                   INT           NOT NULL CONSTRAINT DF_PBA_Deaths DEFAULT (0),
        BirdsAfter               INT           NULL,
        FirstPickEggs            INT           NOT NULL CONSTRAINT DF_PBA_P1 DEFAULT (0),
        SecondPickEggs           INT           NOT NULL CONSTRAINT DF_PBA_P2 DEFAULT (0),
        ThirdPickEggs            INT           NOT NULL CONSTRAINT DF_PBA_P3 DEFAULT (0),
        FourthPickEggs           INT           NOT NULL CONSTRAINT DF_PBA_P4 DEFAULT (0),
        BrokenEggs               INT           NULL,
        MeatyEggs                INT           NULL,
        SoftEggs                 INT           NULL,
        LostEggs                 INT           NULL,
        TotalEggs                INT           NOT NULL CONSTRAINT DF_PBA_Total DEFAULT (0),
        EggPercentage            DECIMAL(9,2)  NULL,
        FeedKg                   DECIMAL(18,2) NULL,
        TotalFeedCost            DECIMAL(14,2) NULL,
        TotalMedicationCost      DECIMAL(14,2) NULL,
        TotalCostOfProduction    DECIMAL(14,2) NULL,
        Notes                    NVARCHAR(MAX) NULL,
        GeneratedProductionRecordId INT        NULL,     -- set on Post, cleared on Reverse
        CreatedBy                NVARCHAR(450) NULL,
        CreatedDate              DATETIME2     NOT NULL CONSTRAINT DF_PBA_Created DEFAULT (SYSUTCDATETIME()),
        UpdatedBy                NVARCHAR(450) NULL,
        UpdatedDate              DATETIME2     NULL,
        CONSTRAINT FK_PBA_Batch FOREIGN KEY (ProductionBatchRecordId)
            REFERENCES dbo.ProductionBatchRecords (Id) ON DELETE CASCADE
    );
    CREATE INDEX IX_PBA_Batch ON dbo.ProductionBatchAllocations (ProductionBatchRecordId);
END
GO

-- -----------------------------------------------------------------------------
-- 6. Per-flock allocation feed usage (flattened batch feed lines per flock).
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.ProductionBatchAllocationFeedUsage', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductionBatchAllocationFeedUsage (
        Id                          INT IDENTITY(1,1) PRIMARY KEY,
        ProductionBatchAllocationId INT           NOT NULL,
        ProductionBatchFeedUsageId  INT           NULL,
        InventoryItemId             INT           NOT NULL,
        ItemName                    NVARCHAR(150) NULL,
        QuantityAllocated           DECIMAL(14,3) NOT NULL,
        UnitCost                    DECIMAL(14,4) NULL,
        TotalCost                   DECIMAL(14,2) NULL,
        CreatedBy                   NVARCHAR(450) NULL,
        CreatedDate                 DATETIME2     NOT NULL CONSTRAINT DF_PBAFU_Created DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_PBAFU_Alloc FOREIGN KEY (ProductionBatchAllocationId)
            REFERENCES dbo.ProductionBatchAllocations (Id) ON DELETE CASCADE
    );
    CREATE INDEX IX_PBAFU_Alloc ON dbo.ProductionBatchAllocationFeedUsage (ProductionBatchAllocationId);
END
GO

-- -----------------------------------------------------------------------------
-- 7. Per-flock allocation medication usage.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.ProductionBatchAllocationMedicationUsage', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProductionBatchAllocationMedicationUsage (
        Id                             INT IDENTITY(1,1) PRIMARY KEY,
        ProductionBatchAllocationId    INT           NOT NULL,
        ProductionBatchMedicationUsageId INT         NULL,
        InventoryItemId                INT           NOT NULL,
        ItemName                       NVARCHAR(150) NULL,
        QuantityAllocated              DECIMAL(14,3) NOT NULL,
        UnitCost                       DECIMAL(14,4) NULL,
        TotalCost                      DECIMAL(14,2) NULL,
        CreatedBy                      NVARCHAR(450) NULL,
        CreatedDate                    DATETIME2     NOT NULL CONSTRAINT DF_PBAMU_Created DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_PBAMU_Alloc FOREIGN KEY (ProductionBatchAllocationId)
            REFERENCES dbo.ProductionBatchAllocations (Id) ON DELETE CASCADE
    );
    CREATE INDEX IX_PBAMU_Alloc ON dbo.ProductionBatchAllocationMedicationUsage (ProductionBatchAllocationId);
END
GO

-- =============================================================================
-- STORED PROCEDURES
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Insert a batch record + its included flocks + feed/med usage lines.
--   @IncludedFlocksJson : [{ flockId, flockName, birdBatchId }]
--   @FeedsJson          : [{ itemId, itemName, qty, unitCost, totalCost, method }]
--   @MedicationsJson    : [{ itemId, itemName, qty, unitCost, totalCost, method }]
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_Insert
    @FarmId NVARCHAR(450), @UserId NVARCHAR(450), @CreatedBy NVARCHAR(450),
    @BatchSelectionType NVARCHAR(20), @SelectedBirdBatchId INT = NULL, @BatchName NVARCHAR(150) = NULL,
    @ProductionDate DATE, @AgeInWeeks INT = NULL, @AgeInDays INT = NULL, @AgeDisplay NVARCHAR(50) = NULL,
    @FirstPickCrates INT = NULL, @FirstPickLooseEggs INT = NULL, @FirstPickTotal INT = 0,
    @SecondPickCrates INT = NULL, @SecondPickLooseEggs INT = NULL, @SecondPickTotal INT = 0,
    @ThirdPickCrates INT = NULL, @ThirdPickLooseEggs INT = NULL, @ThirdPickTotal INT = 0,
    @FourthPickCrates INT = NULL, @FourthPickLooseEggs INT = NULL, @FourthPickTotal INT = 0,
    @BrokenEggs INT = NULL, @MeatyEggs INT = NULL, @SoftEggs INT = NULL, @LostEggs INT = NULL, @TotalEggs INT = 0,
    @FeedKg DECIMAL(18,2) = NULL, @Deaths INT = 0, @BirdsLeft INT = NULL, @EggGrade NVARCHAR(50) = NULL,
    @FeedType NVARCHAR(100) = NULL, @Medication NVARCHAR(500) = NULL,
    @TotalFeedCost DECIMAL(14,2) = NULL, @TotalMedicationCost DECIMAL(14,2) = NULL, @TotalCostOfProduction DECIMAL(14,2) = NULL,
    @Status NVARCHAR(30) = N'PendingAllocation', @Notes NVARCHAR(MAX) = NULL,
    @IncludedFlocksJson NVARCHAR(MAX) = NULL, @FeedsJson NVARCHAR(MAX) = NULL, @MedicationsJson NVARCHAR(MAX) = NULL,
    @NewId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    BEGIN TRANSACTION;

    INSERT INTO dbo.ProductionBatchRecords (
        FarmId, UserId, BatchSelectionType, SelectedBirdBatchId, BatchName, ProductionDate,
        AgeInWeeks, AgeInDays, AgeDisplay,
        FirstPickCrates, FirstPickLooseEggs, FirstPickTotal,
        SecondPickCrates, SecondPickLooseEggs, SecondPickTotal,
        ThirdPickCrates, ThirdPickLooseEggs, ThirdPickTotal,
        FourthPickCrates, FourthPickLooseEggs, FourthPickTotal,
        BrokenEggs, MeatyEggs, SoftEggs, LostEggs, TotalEggs,
        FeedKg, Deaths, BirdsLeft, EggGrade, FeedType, Medication,
        TotalFeedCost, TotalMedicationCost, TotalCostOfProduction, Status, Notes, CreatedBy, CreatedDate)
    VALUES (
        @FarmId, @UserId, @BatchSelectionType, @SelectedBirdBatchId, @BatchName, @ProductionDate,
        @AgeInWeeks, @AgeInDays, @AgeDisplay,
        @FirstPickCrates, @FirstPickLooseEggs, ISNULL(@FirstPickTotal,0),
        @SecondPickCrates, @SecondPickLooseEggs, ISNULL(@SecondPickTotal,0),
        @ThirdPickCrates, @ThirdPickLooseEggs, ISNULL(@ThirdPickTotal,0),
        @FourthPickCrates, @FourthPickLooseEggs, ISNULL(@FourthPickTotal,0),
        @BrokenEggs, @MeatyEggs, @SoftEggs, @LostEggs, ISNULL(@TotalEggs,0),
        @FeedKg, ISNULL(@Deaths,0), @BirdsLeft, @EggGrade, @FeedType, @Medication,
        @TotalFeedCost, @TotalMedicationCost, @TotalCostOfProduction, ISNULL(@Status,N'PendingAllocation'),
        @Notes, @CreatedBy, SYSUTCDATETIME());
    SET @NewId = CAST(SCOPE_IDENTITY() AS INT);

    EXEC dbo.spProductionBatchRecord_ReplaceChildren
         @NewId, @CreatedBy, @IncludedFlocksJson, @FeedsJson, @MedicationsJson;

    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- Replace the included-flock + feed + medication child rows for a batch.
-- Shared by Insert and Update. Does NOT touch allocations.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_ReplaceChildren
    @BatchId INT, @CreatedBy NVARCHAR(450) = NULL,
    @IncludedFlocksJson NVARCHAR(MAX) = NULL, @FeedsJson NVARCHAR(MAX) = NULL, @MedicationsJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF (@IncludedFlocksJson IS NOT NULL)
    BEGIN
        DELETE FROM dbo.ProductionBatchIncludedFlocks WHERE ProductionBatchRecordId = @BatchId;
        IF (LEN(@IncludedFlocksJson) > 0)
            INSERT INTO dbo.ProductionBatchIncludedFlocks (ProductionBatchRecordId, FlockId, FlockName, BirdBatchId, CreatedBy)
            SELECT @BatchId, j.FlockId, j.FlockName, j.BirdBatchId, @CreatedBy
            FROM OPENJSON(@IncludedFlocksJson)
                 WITH (FlockId INT '$.flockId', FlockName NVARCHAR(150) '$.flockName', BirdBatchId INT '$.birdBatchId') j
            WHERE j.FlockId IS NOT NULL;
    END

    IF (@FeedsJson IS NOT NULL)
    BEGIN
        DELETE FROM dbo.ProductionBatchFeedUsage WHERE ProductionBatchRecordId = @BatchId;
        IF (LEN(@FeedsJson) > 0)
            INSERT INTO dbo.ProductionBatchFeedUsage (ProductionBatchRecordId, InventoryItemId, ItemName, QuantityUsed, UnitCost, TotalCost, CostingMethod, CreatedBy)
            SELECT @BatchId, j.ItemId, j.ItemName, j.Qty, j.UnitCost, j.TotalCost, j.Method, @CreatedBy
            FROM OPENJSON(@FeedsJson)
                 WITH (ItemId INT '$.itemId', ItemName NVARCHAR(150) '$.itemName', Qty DECIMAL(14,3) '$.qty',
                       UnitCost DECIMAL(14,4) '$.unitCost', TotalCost DECIMAL(14,2) '$.totalCost', Method NVARCHAR(20) '$.method') j
            WHERE j.ItemId IS NOT NULL AND ISNULL(j.Qty,0) > 0;
    END

    IF (@MedicationsJson IS NOT NULL)
    BEGIN
        DELETE FROM dbo.ProductionBatchMedicationUsage WHERE ProductionBatchRecordId = @BatchId;
        IF (LEN(@MedicationsJson) > 0)
            INSERT INTO dbo.ProductionBatchMedicationUsage (ProductionBatchRecordId, InventoryItemId, ItemName, QuantityUsed, UnitCost, TotalCost, CostingMethod, CreatedBy)
            SELECT @BatchId, j.ItemId, j.ItemName, j.Qty, j.UnitCost, j.TotalCost, j.Method, @CreatedBy
            FROM OPENJSON(@MedicationsJson)
                 WITH (ItemId INT '$.itemId', ItemName NVARCHAR(150) '$.itemName', Qty DECIMAL(14,3) '$.qty',
                       UnitCost DECIMAL(14,4) '$.unitCost', TotalCost DECIMAL(14,2) '$.totalCost', Method NVARCHAR(20) '$.method') j
            WHERE j.ItemId IS NOT NULL AND ISNULL(j.Qty,0) > 0;
    END
END
GO

-- -----------------------------------------------------------------------------
-- Update a batch record (only while not Posted/Reversed). Re-syncs children.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_Update
    @Id INT, @UpdatedBy NVARCHAR(450),
    @BatchSelectionType NVARCHAR(20), @SelectedBirdBatchId INT = NULL, @BatchName NVARCHAR(150) = NULL,
    @ProductionDate DATE, @AgeInWeeks INT = NULL, @AgeInDays INT = NULL, @AgeDisplay NVARCHAR(50) = NULL,
    @FirstPickCrates INT = NULL, @FirstPickLooseEggs INT = NULL, @FirstPickTotal INT = 0,
    @SecondPickCrates INT = NULL, @SecondPickLooseEggs INT = NULL, @SecondPickTotal INT = 0,
    @ThirdPickCrates INT = NULL, @ThirdPickLooseEggs INT = NULL, @ThirdPickTotal INT = 0,
    @FourthPickCrates INT = NULL, @FourthPickLooseEggs INT = NULL, @FourthPickTotal INT = 0,
    @BrokenEggs INT = NULL, @MeatyEggs INT = NULL, @SoftEggs INT = NULL, @LostEggs INT = NULL, @TotalEggs INT = 0,
    @FeedKg DECIMAL(18,2) = NULL, @Deaths INT = 0, @BirdsLeft INT = NULL, @EggGrade NVARCHAR(50) = NULL,
    @FeedType NVARCHAR(100) = NULL, @Medication NVARCHAR(500) = NULL,
    @TotalFeedCost DECIMAL(14,2) = NULL, @TotalMedicationCost DECIMAL(14,2) = NULL, @TotalCostOfProduction DECIMAL(14,2) = NULL,
    @Status NVARCHAR(30) = NULL, @Notes NVARCHAR(MAX) = NULL,
    @IncludedFlocksJson NVARCHAR(MAX) = NULL, @FeedsJson NVARCHAR(MAX) = NULL, @MedicationsJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CurStatus NVARCHAR(30);
    SELECT @CurStatus = Status FROM dbo.ProductionBatchRecords WHERE Id = @Id;
    IF (@CurStatus IS NULL) THROW 51610, 'Batch production record not found.', 1;
    IF (@CurStatus IN (N'Posted', N'Reversed', N'Cancelled'))
        THROW 51611, 'A posted, reversed or cancelled batch cannot be edited.', 1;

    BEGIN TRANSACTION;
    UPDATE dbo.ProductionBatchRecords
    SET BatchSelectionType=@BatchSelectionType, SelectedBirdBatchId=@SelectedBirdBatchId, BatchName=@BatchName,
        ProductionDate=@ProductionDate, AgeInWeeks=@AgeInWeeks, AgeInDays=@AgeInDays, AgeDisplay=@AgeDisplay,
        FirstPickCrates=@FirstPickCrates, FirstPickLooseEggs=@FirstPickLooseEggs, FirstPickTotal=ISNULL(@FirstPickTotal,0),
        SecondPickCrates=@SecondPickCrates, SecondPickLooseEggs=@SecondPickLooseEggs, SecondPickTotal=ISNULL(@SecondPickTotal,0),
        ThirdPickCrates=@ThirdPickCrates, ThirdPickLooseEggs=@ThirdPickLooseEggs, ThirdPickTotal=ISNULL(@ThirdPickTotal,0),
        FourthPickCrates=@FourthPickCrates, FourthPickLooseEggs=@FourthPickLooseEggs, FourthPickTotal=ISNULL(@FourthPickTotal,0),
        BrokenEggs=@BrokenEggs, MeatyEggs=@MeatyEggs, SoftEggs=@SoftEggs, LostEggs=@LostEggs, TotalEggs=ISNULL(@TotalEggs,0),
        FeedKg=@FeedKg, Deaths=ISNULL(@Deaths,0), BirdsLeft=@BirdsLeft, EggGrade=@EggGrade,
        FeedType=@FeedType, Medication=@Medication,
        TotalFeedCost=@TotalFeedCost, TotalMedicationCost=@TotalMedicationCost, TotalCostOfProduction=@TotalCostOfProduction,
        Status=ISNULL(@Status, Status), Notes=@Notes, UpdatedBy=@UpdatedBy, UpdatedDate=SYSUTCDATETIME()
    WHERE Id = @Id;

    EXEC dbo.spProductionBatchRecord_ReplaceChildren
         @Id, @UpdatedBy, @IncludedFlocksJson, @FeedsJson, @MedicationsJson;
    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- GetById — header + children + allocations as JSON array columns.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_GetById
    @Id INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.*,
        (SELECT f.FlockId AS flockId, f.FlockName AS flockName, f.BirdBatchId AS birdBatchId
         FROM dbo.ProductionBatchIncludedFlocks f WHERE f.ProductionBatchRecordId = r.Id
         ORDER BY f.Id FOR JSON PATH) AS IncludedFlocksJson,
        (SELECT u.Id AS id, u.InventoryItemId AS itemId, u.ItemName AS itemName, u.QuantityUsed AS qty,
                u.UnitCost AS unitCost, u.TotalCost AS totalCost, u.CostingMethod AS method
         FROM dbo.ProductionBatchFeedUsage u WHERE u.ProductionBatchRecordId = r.Id
         ORDER BY u.Id FOR JSON PATH) AS FeedsJson,
        (SELECT u.Id AS id, u.InventoryItemId AS itemId, u.ItemName AS itemName, u.QuantityUsed AS qty,
                u.UnitCost AS unitCost, u.TotalCost AS totalCost, u.CostingMethod AS method
         FROM dbo.ProductionBatchMedicationUsage u WHERE u.ProductionBatchRecordId = r.Id
         ORDER BY u.Id FOR JSON PATH) AS MedicationsJson,
        (SELECT a.Id AS id, a.FlockId AS flockId, a.FlockName AS flockName, a.AllocationMethod AS allocationMethod,
                a.AgeInWeeks AS ageInWeeks, a.AgeInDays AS ageInDays, a.BirdsBefore AS birdsBefore, a.Deaths AS deaths,
                a.BirdsAfter AS birdsAfter, a.FirstPickEggs AS firstPickEggs, a.SecondPickEggs AS secondPickEggs,
                a.ThirdPickEggs AS thirdPickEggs, a.FourthPickEggs AS fourthPickEggs, a.BrokenEggs AS brokenEggs,
                a.MeatyEggs AS meatyEggs, a.SoftEggs AS softEggs, a.LostEggs AS lostEggs, a.TotalEggs AS totalEggs,
                a.EggPercentage AS eggPercentage, a.FeedKg AS feedKg, a.TotalFeedCost AS totalFeedCost,
                a.TotalMedicationCost AS totalMedicationCost, a.TotalCostOfProduction AS totalCostOfProduction,
                a.Notes AS notes, a.GeneratedProductionRecordId AS generatedProductionRecordId,
                (SELECT fu.ProductionBatchFeedUsageId AS batchUsageId, fu.InventoryItemId AS itemId, fu.ItemName AS itemName,
                        fu.QuantityAllocated AS qty, fu.UnitCost AS unitCost, fu.TotalCost AS totalCost
                 FROM dbo.ProductionBatchAllocationFeedUsage fu WHERE fu.ProductionBatchAllocationId = a.Id
                 ORDER BY fu.Id FOR JSON PATH) AS feeds,
                (SELECT mu.ProductionBatchMedicationUsageId AS batchUsageId, mu.InventoryItemId AS itemId, mu.ItemName AS itemName,
                        mu.QuantityAllocated AS qty, mu.UnitCost AS unitCost, mu.TotalCost AS totalCost
                 FROM dbo.ProductionBatchAllocationMedicationUsage mu WHERE mu.ProductionBatchAllocationId = a.Id
                 ORDER BY mu.Id FOR JSON PATH) AS medications
         FROM dbo.ProductionBatchAllocations a WHERE a.ProductionBatchRecordId = r.Id
         ORDER BY a.Id FOR JSON PATH) AS AllocationsJson
    FROM dbo.ProductionBatchRecords r
    WHERE r.Id = @Id AND r.FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- GetAll — header + included flocks (for the list page batch-name secondary line).
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_GetAll
    @UserId NVARCHAR(450), @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT r.*,
        (SELECT f.FlockId AS flockId, f.FlockName AS flockName, f.BirdBatchId AS birdBatchId
         FROM dbo.ProductionBatchIncludedFlocks f WHERE f.ProductionBatchRecordId = r.Id
         ORDER BY f.Id FOR JSON PATH) AS IncludedFlocksJson,
        (SELECT u.InventoryItemId AS itemId, u.ItemName AS itemName, u.QuantityUsed AS qty
         FROM dbo.ProductionBatchFeedUsage u WHERE u.ProductionBatchRecordId = r.Id
         ORDER BY u.Id FOR JSON PATH) AS FeedsJson,
        (SELECT u.InventoryItemId AS itemId, u.ItemName AS itemName, u.QuantityUsed AS qty
         FROM dbo.ProductionBatchMedicationUsage u WHERE u.ProductionBatchRecordId = r.Id
         ORDER BY u.Id FOR JSON PATH) AS MedicationsJson
    FROM dbo.ProductionBatchRecords r
    WHERE r.FarmId = @FarmId
    ORDER BY r.ProductionDate DESC, r.CreatedDate DESC;
END
GO

-- -----------------------------------------------------------------------------
-- Delete — only when not Posted (a Posted batch must be Reversed first).
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_Delete
    @Id INT, @UserId NVARCHAR(450), @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CurStatus NVARCHAR(30);
    SELECT @CurStatus = Status FROM dbo.ProductionBatchRecords WHERE Id = @Id AND FarmId = @FarmId;
    IF (@CurStatus IS NULL) RETURN;
    IF (@CurStatus = N'Posted') THROW 51612, 'A posted batch must be reversed before it can be deleted.', 1;
    DELETE FROM dbo.ProductionBatchRecords WHERE Id = @Id AND FarmId = @FarmId;  -- cascades to children
END
GO

-- -----------------------------------------------------------------------------
-- SetStatus — lightweight transition (e.g. Draft->PendingAllocation, Cancel).
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_SetStatus
    @Id INT, @FarmId NVARCHAR(450), @Status NVARCHAR(30), @UpdatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @CurStatus NVARCHAR(30);
    SELECT @CurStatus = Status FROM dbo.ProductionBatchRecords WHERE Id = @Id AND FarmId = @FarmId;
    IF (@CurStatus IS NULL) THROW 51613, 'Batch production record not found.', 1;
    IF (@CurStatus = N'Posted') THROW 51614, 'A posted batch must be reversed, not re-statused.', 1;
    UPDATE dbo.ProductionBatchRecords
    SET Status = @Status, UpdatedBy = @UpdatedBy, UpdatedDate = SYSUTCDATETIME()
    WHERE Id = @Id AND FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- SaveAllocation — replace the allocation rows for a batch and mark Allocated.
--   @AllocationsJson : [{ flockId, flockName, allocationMethod, ageInWeeks, ageInDays,
--        birdsBefore, deaths, birdsAfter, firstPickEggs..fourthPickEggs, brokenEggs,
--        meatyEggs, softEggs, lostEggs, totalEggs, eggPercentage, feedKg, notes,
--        feeds:[{ batchFeedUsageId, itemId, itemName, qty, unitCost, totalCost }],
--        medications:[{ batchMedicationUsageId, itemId, itemName, qty, unitCost, totalCost }] }]
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_SaveAllocation
    @Id INT, @FarmId NVARCHAR(450), @UpdatedBy NVARCHAR(450),
    @AllocationsJson NVARCHAR(MAX), @Status NVARCHAR(30) = N'Allocated'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CurStatus NVARCHAR(30);
    SELECT @CurStatus = Status FROM dbo.ProductionBatchRecords WHERE Id = @Id AND FarmId = @FarmId;
    IF (@CurStatus IS NULL) THROW 51620, 'Batch production record not found.', 1;
    IF (@CurStatus IN (N'Posted', N'Reversed', N'Cancelled'))
        THROW 51621, 'Allocation cannot be edited for a posted, reversed or cancelled batch.', 1;

    BEGIN TRANSACTION;
    DELETE FROM dbo.ProductionBatchAllocations WHERE ProductionBatchRecordId = @Id;  -- cascades feed/med

    DECLARE @rows TABLE (Seq INT, Payload NVARCHAR(MAX));
    INSERT INTO @rows (Seq, Payload)
    SELECT [key] + 1, [value] FROM OPENJSON(@AllocationsJson);

    DECLARE @i INT = 1, @n INT = (SELECT ISNULL(MAX(Seq),0) FROM @rows), @p NVARCHAR(MAX), @allocId INT;
    WHILE @i <= @n
    BEGIN
        SELECT @p = Payload FROM @rows WHERE Seq = @i;

        INSERT INTO dbo.ProductionBatchAllocations (
            ProductionBatchRecordId, FlockId, FlockName, AllocationMethod, AgeInWeeks, AgeInDays,
            BirdsBefore, Deaths, BirdsAfter, FirstPickEggs, SecondPickEggs, ThirdPickEggs, FourthPickEggs,
            BrokenEggs, MeatyEggs, SoftEggs, LostEggs, TotalEggs, EggPercentage, FeedKg,
            TotalFeedCost, TotalMedicationCost, TotalCostOfProduction, Notes, CreatedBy, CreatedDate)
        SELECT @Id, j.FlockId, j.FlockName, j.AllocationMethod, j.AgeInWeeks, j.AgeInDays,
               j.BirdsBefore, ISNULL(j.Deaths,0), j.BirdsAfter, ISNULL(j.FirstPickEggs,0), ISNULL(j.SecondPickEggs,0),
               ISNULL(j.ThirdPickEggs,0), ISNULL(j.FourthPickEggs,0), j.BrokenEggs, j.MeatyEggs, j.SoftEggs, j.LostEggs,
               ISNULL(j.TotalEggs,0), j.EggPercentage, j.FeedKg, j.TotalFeedCost, j.TotalMedicationCost,
               j.TotalCostOfProduction, j.Notes, @UpdatedBy, SYSUTCDATETIME()
        FROM OPENJSON(@p) WITH (
            FlockId INT '$.flockId', FlockName NVARCHAR(150) '$.flockName', AllocationMethod NVARCHAR(30) '$.allocationMethod',
            AgeInWeeks INT '$.ageInWeeks', AgeInDays INT '$.ageInDays', BirdsBefore INT '$.birdsBefore', Deaths INT '$.deaths',
            BirdsAfter INT '$.birdsAfter', FirstPickEggs INT '$.firstPickEggs', SecondPickEggs INT '$.secondPickEggs',
            ThirdPickEggs INT '$.thirdPickEggs', FourthPickEggs INT '$.fourthPickEggs', BrokenEggs INT '$.brokenEggs',
            MeatyEggs INT '$.meatyEggs', SoftEggs INT '$.softEggs', LostEggs INT '$.lostEggs', TotalEggs INT '$.totalEggs',
            EggPercentage DECIMAL(9,2) '$.eggPercentage', FeedKg DECIMAL(18,2) '$.feedKg',
            TotalFeedCost DECIMAL(14,2) '$.totalFeedCost', TotalMedicationCost DECIMAL(14,2) '$.totalMedicationCost',
            TotalCostOfProduction DECIMAL(14,2) '$.totalCostOfProduction', Notes NVARCHAR(MAX) '$.notes') j;
        SET @allocId = CAST(SCOPE_IDENTITY() AS INT);

        INSERT INTO dbo.ProductionBatchAllocationFeedUsage (
            ProductionBatchAllocationId, ProductionBatchFeedUsageId, InventoryItemId, ItemName, QuantityAllocated, UnitCost, TotalCost, CreatedBy)
        SELECT @allocId, f.BatchUsageId, f.ItemId, f.ItemName, f.Qty, f.UnitCost, f.TotalCost, @UpdatedBy
        FROM OPENJSON(@p, '$.feeds') WITH (
            BatchUsageId INT '$.batchUsageId', ItemId INT '$.itemId', ItemName NVARCHAR(150) '$.itemName',
            Qty DECIMAL(14,3) '$.qty', UnitCost DECIMAL(14,4) '$.unitCost', TotalCost DECIMAL(14,2) '$.totalCost') f
        WHERE f.ItemId IS NOT NULL;

        INSERT INTO dbo.ProductionBatchAllocationMedicationUsage (
            ProductionBatchAllocationId, ProductionBatchMedicationUsageId, InventoryItemId, ItemName, QuantityAllocated, UnitCost, TotalCost, CreatedBy)
        SELECT @allocId, m.BatchUsageId, m.ItemId, m.ItemName, m.Qty, m.UnitCost, m.TotalCost, @UpdatedBy
        FROM OPENJSON(@p, '$.medications') WITH (
            BatchUsageId INT '$.batchUsageId', ItemId INT '$.itemId', ItemName NVARCHAR(150) '$.itemName',
            Qty DECIMAL(14,3) '$.qty', UnitCost DECIMAL(14,4) '$.unitCost', TotalCost DECIMAL(14,2) '$.totalCost') m
        WHERE m.ItemId IS NOT NULL;

        SET @i += 1;
    END

    UPDATE dbo.ProductionBatchRecords
    SET Status = ISNULL(@Status, N'Allocated'), UpdatedBy = @UpdatedBy, UpdatedDate = SYSUTCDATETIME()
    WHERE Id = @Id;
    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- Post — validate balance, then create a flock-level ProductionRecord per
-- allocation row (reusing spProductionRecord_Insert so all bird/egg/raw-material
-- side-effects are inherited), stamp provenance, and mark the batch Posted.
-- All inside one transaction; XACT_ABORT rolls back everything on any failure.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_Post
    @Id INT, @FarmId NVARCHAR(450), @PostedBy NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @UserId NVARCHAR(450), @Status NVARCHAR(30), @Date DATE;
    SELECT @UserId = UserId, @Status = Status, @Date = ProductionDate
    FROM dbo.ProductionBatchRecords WHERE Id = @Id AND FarmId = @FarmId;

    IF (@Status IS NULL) THROW 51630, 'Batch production record not found.', 1;
    IF (@Status = N'Posted') THROW 51631, 'This batch has already been posted.', 1;
    IF (@Status NOT IN (N'Allocated', N'PendingAllocation'))
        THROW 51632, 'Only an allocated batch can be posted.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.ProductionBatchAllocations WHERE ProductionBatchRecordId = @Id)
        THROW 51633, 'This batch has no allocation rows to post.', 1;

    -- ---- Reconciliation: allocated egg/death totals must equal batch totals. ----
    DECLARE @bP1 INT, @bP2 INT, @bP3 INT, @bP4 INT, @bBroken INT, @bMeaty INT, @bSoft INT, @bLost INT, @bDeaths INT;
    SELECT @bP1=FirstPickTotal, @bP2=SecondPickTotal, @bP3=ThirdPickTotal, @bP4=FourthPickTotal,
           @bBroken=ISNULL(BrokenEggs,0), @bMeaty=ISNULL(MeatyEggs,0), @bSoft=ISNULL(SoftEggs,0),
           @bLost=ISNULL(LostEggs,0), @bDeaths=ISNULL(Deaths,0)
    FROM dbo.ProductionBatchRecords WHERE Id = @Id;

    DECLARE @aP1 INT, @aP2 INT, @aP3 INT, @aP4 INT, @aBroken INT, @aMeaty INT, @aSoft INT, @aLost INT, @aDeaths INT;
    SELECT @aP1=ISNULL(SUM(FirstPickEggs),0), @aP2=ISNULL(SUM(SecondPickEggs),0), @aP3=ISNULL(SUM(ThirdPickEggs),0),
           @aP4=ISNULL(SUM(FourthPickEggs),0), @aBroken=ISNULL(SUM(ISNULL(BrokenEggs,0)),0),
           @aMeaty=ISNULL(SUM(ISNULL(MeatyEggs,0)),0), @aSoft=ISNULL(SUM(ISNULL(SoftEggs,0)),0),
           @aLost=ISNULL(SUM(ISNULL(LostEggs,0)),0), @aDeaths=ISNULL(SUM(ISNULL(Deaths,0)),0)
    FROM dbo.ProductionBatchAllocations WHERE ProductionBatchRecordId = @Id;

    IF (@aP1<>@bP1 OR @aP2<>@bP2 OR @aP3<>@bP3 OR @aP4<>@bP4 OR @aBroken<>@bBroken
        OR @aMeaty<>@bMeaty OR @aSoft<>@bSoft OR @aLost<>@bLost OR @aDeaths<>@bDeaths)
        THROW 51634, 'Allocation does not balance against the batch egg/death totals.', 1;

    -- ---- Reconciliation: allocated feed qty per item must equal batch feed qty. ----
    IF EXISTS (
        SELECT bu.InventoryItemId
        FROM dbo.ProductionBatchFeedUsage bu
        WHERE bu.ProductionBatchRecordId = @Id
        GROUP BY bu.InventoryItemId
        HAVING ABS(SUM(bu.QuantityUsed) - ISNULL((
            SELECT SUM(afu.QuantityAllocated)
            FROM dbo.ProductionBatchAllocationFeedUsage afu
            JOIN dbo.ProductionBatchAllocations a ON a.Id = afu.ProductionBatchAllocationId
            WHERE a.ProductionBatchRecordId = @Id AND afu.InventoryItemId = bu.InventoryItemId), 0)) > 0.001)
        THROW 51635, 'Allocated feed quantities do not balance against the batch feed totals.', 1;

    -- ---- Reconciliation: allocated medication qty per item must equal batch. ----
    IF EXISTS (
        SELECT bu.InventoryItemId
        FROM dbo.ProductionBatchMedicationUsage bu
        WHERE bu.ProductionBatchRecordId = @Id
        GROUP BY bu.InventoryItemId
        HAVING ABS(SUM(bu.QuantityUsed) - ISNULL((
            SELECT SUM(amu.QuantityAllocated)
            FROM dbo.ProductionBatchAllocationMedicationUsage amu
            JOIN dbo.ProductionBatchAllocations a ON a.Id = amu.ProductionBatchAllocationId
            WHERE a.ProductionBatchRecordId = @Id AND amu.InventoryItemId = bu.InventoryItemId), 0)) > 0.001)
        THROW 51636, 'Allocated medication quantities do not balance against the batch medication totals.', 1;

    BEGIN TRANSACTION;

    DECLARE alloc CURSOR LOCAL FAST_FORWARD FOR
        SELECT Id, FlockId, ISNULL(AgeInWeeks,0), ISNULL(AgeInDays,0), ISNULL(BirdsBefore,0), ISNULL(Deaths,0),
               ISNULL(BirdsAfter, ISNULL(BirdsBefore,0)-ISNULL(Deaths,0)), FirstPickEggs, SecondPickEggs, ThirdPickEggs,
               FourthPickEggs, ISNULL(BrokenEggs,0), MeatyEggs, SoftEggs, LostEggs, TotalEggs, ISNULL(FeedKg,0), Notes
        FROM dbo.ProductionBatchAllocations WHERE ProductionBatchRecordId = @Id ORDER BY Id;

    DECLARE @allocId INT, @flockId INT, @aw INT, @ad INT, @birdsBefore INT, @deaths INT, @birdsAfter INT,
            @p1 INT, @p2 INT, @p3 INT, @p4 INT, @broken INT, @meaty INT, @soft INT, @lost INT, @total INT,
            @feedKg DECIMAL(18,2), @notes NVARCHAR(MAX), @newRecId INT, @feedsJson NVARCHAR(MAX), @medsJson NVARCHAR(MAX),
            @eggGrade NVARCHAR(50), @batchMedication NVARCHAR(500);
    SELECT @eggGrade = EggGrade, @batchMedication = Medication FROM dbo.ProductionBatchRecords WHERE Id = @Id;

    OPEN alloc;
    FETCH NEXT FROM alloc INTO @allocId, @flockId, @aw, @ad, @birdsBefore, @deaths, @birdsAfter,
        @p1, @p2, @p3, @p4, @broken, @meaty, @soft, @lost, @total, @feedKg, @notes;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Build [{itemId,qty}] feed/medication JSON for this allocation from the flattened usage.
        SET @feedsJson = (SELECT afu.InventoryItemId AS itemId, afu.QuantityAllocated AS qty
                          FROM dbo.ProductionBatchAllocationFeedUsage afu
                          WHERE afu.ProductionBatchAllocationId = @allocId AND afu.QuantityAllocated > 0
                          FOR JSON PATH);
        SET @medsJson = (SELECT amu.InventoryItemId AS itemId, amu.QuantityAllocated AS qty
                         FROM dbo.ProductionBatchAllocationMedicationUsage amu
                         WHERE amu.ProductionBatchAllocationId = @allocId AND amu.QuantityAllocated > 0
                         FOR JSON PATH);

        SET @newRecId = NULL;
        EXEC dbo.spProductionRecord_Insert
             @FarmId = @FarmId, @CreatedBy = @PostedBy, @UserId = @UserId,
             @AgeInWeeks = @aw, @AgeInDays = @ad, @Date = @Date,
             @NoOfBirds = @birdsBefore, @Mortality = @deaths, @NoOfBirdsLeft = @birdsAfter,
             @FeedKg = @feedKg, @Medication = @batchMedication,
             @Production9AM = @p1, @Production12PM = @p2, @Production4PM = @p3, @TotalProduction = @total,
             @FlockId = @flockId, @BrokenEggs = @broken, @Notes = @notes, @EggCount = @total,
             @EggGrade = @eggGrade, @MeatyEggs = @meaty, @SoftEggs = @soft, @LostEggs = @lost,
             @FeedsJson = @feedsJson, @MedicationsJson = @medsJson,
             @NewId = @newRecId OUTPUT;

        -- 4th pick + provenance stamp on the generated flock record.
        IF (@newRecId IS NOT NULL)
        BEGIN
            IF OBJECT_ID('dbo.spProductionRecord_SetFourthPick','P') IS NOT NULL
                EXEC dbo.spProductionRecord_SetFourthPick @RecordId = @newRecId, @FarmId = @FarmId, @Production4thPick = @p4;

            UPDATE dbo.ProductionRecords
            SET ProductionBatchId = @Id, ProductionBatchAllocationId = @allocId, SourceType = N'BatchAllocation'
            WHERE Id = @newRecId;

            UPDATE dbo.ProductionBatchAllocations SET GeneratedProductionRecordId = @newRecId WHERE Id = @allocId;
        END

        FETCH NEXT FROM alloc INTO @allocId, @flockId, @aw, @ad, @birdsBefore, @deaths, @birdsAfter,
            @p1, @p2, @p3, @p4, @broken, @meaty, @soft, @lost, @total, @feedKg, @notes;
    END
    CLOSE alloc; DEALLOCATE alloc;

    UPDATE dbo.ProductionBatchRecords
    SET Status = N'Posted', PostedBy = @PostedBy, PostedDate = SYSUTCDATETIME(), UpdatedBy = @PostedBy, UpdatedDate = SYSUTCDATETIME()
    WHERE Id = @Id;

    COMMIT TRANSACTION;
END
GO

-- -----------------------------------------------------------------------------
-- Reverse — delete the generated flock records (reverses their bird/egg/raw-
-- material side-effects via spProductionRecord_Delete) and mark batch Reversed.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spProductionBatchRecord_Reverse
    @Id INT, @FarmId NVARCHAR(450), @ReversedBy NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @UserId NVARCHAR(450), @Status NVARCHAR(30);
    SELECT @UserId = UserId, @Status = Status FROM dbo.ProductionBatchRecords WHERE Id = @Id AND FarmId = @FarmId;
    IF (@Status IS NULL) THROW 51640, 'Batch production record not found.', 1;
    IF (@Status <> N'Posted') THROW 51641, 'Only a posted batch can be reversed.', 1;

    BEGIN TRANSACTION;

    DECLARE @recId INT, @allocId INT;
    DECLARE rev CURSOR LOCAL FAST_FORWARD FOR
        SELECT Id, GeneratedProductionRecordId FROM dbo.ProductionBatchAllocations
        WHERE ProductionBatchRecordId = @Id AND GeneratedProductionRecordId IS NOT NULL;
    OPEN rev;
    FETCH NEXT FROM rev INTO @allocId, @recId;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC dbo.spProductionRecord_Delete @RecordId = @recId, @UserId = @UserId, @FarmId = @FarmId;
        UPDATE dbo.ProductionBatchAllocations SET GeneratedProductionRecordId = NULL WHERE Id = @allocId;
        FETCH NEXT FROM rev INTO @allocId, @recId;
    END
    CLOSE rev; DEALLOCATE rev;

    UPDATE dbo.ProductionBatchRecords
    SET Status = N'Reversed', UpdatedBy = @ReversedBy, UpdatedDate = SYSUTCDATETIME()
    WHERE Id = @Id;

    COMMIT TRANSACTION;
END
GO

-- =============================================================================
-- Grants to the application login.
-- =============================================================================
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.ProductionBatchRecords TO [Techretainer];
    GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.ProductionBatchIncludedFlocks TO [Techretainer];
    GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.ProductionBatchFeedUsage TO [Techretainer];
    GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.ProductionBatchMedicationUsage TO [Techretainer];
    GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.ProductionBatchAllocations TO [Techretainer];
    GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.ProductionBatchAllocationFeedUsage TO [Techretainer];
    GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.ProductionBatchAllocationMedicationUsage TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionBatchRecord_Insert          TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionBatchRecord_Update          TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionBatchRecord_ReplaceChildren TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionBatchRecord_GetById         TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionBatchRecord_GetAll          TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionBatchRecord_Delete          TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionBatchRecord_SetStatus       TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionBatchRecord_SaveAllocation  TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionBatchRecord_Post            TO [Techretainer];
    GRANT EXECUTE ON dbo.spProductionBatchRecord_Reverse         TO [Techretainer];
    PRINT '156: granted rights on batch-production objects to Techretainer.';
END
GO

PRINT '156_BatchProductionRecords.sql complete.';
GO
