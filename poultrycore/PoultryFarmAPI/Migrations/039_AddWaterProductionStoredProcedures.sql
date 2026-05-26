-- =============================================================================
-- Migration 039: Water Company — Production stored procedures
-- =============================================================================
-- Phase W1 SPs. Run AFTER 038_AddWaterProductionSchema.sql.
--
-- Centrepiece: spWaterProductionBatch_Approve — atomic. On approval:
--   * Mark batch Approved + ApprovedBy/At.
--   * INSERT into WaterStockTransactions: TxnType='Restock',
--     Quantity = +(BagsProduced - DamagedBags), UnitCost = TotalProductionCost
--     / max(BagsProduced - DamagedBags, 1).
--   * Idempotent if already Approved.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- WaterBorehole
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterBorehole_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.WaterBoreholes WHERE FarmId = @FarmId
    ORDER BY (CASE WHEN Status = 'Active' THEN 0 ELSE 1 END), BoreholeName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterBorehole_GetById
    @WaterBoreholeId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.WaterBoreholes
    WHERE WaterBoreholeId = @WaterBoreholeId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterBorehole_Insert
    @FarmId                  NVARCHAR(450),
    @BoreholeName            NVARCHAR(150),
    @Location                NVARCHAR(255) = NULL,
    @PumpType                NVARCHAR(60)  = NULL,
    @PumpCapacity            NVARCHAR(60)  = NULL,
    @TankCapacity            NVARCHAR(60)  = NULL,
    @WaterTreatmentMethod    NVARCHAR(120) = NULL,
    @FiltrationSystem        NVARCHAR(120) = NULL,
    @UVSterilizationAvailable BIT          = 0,
    @MaintenanceFrequencyDays INT          = NULL,
    @LastMaintenanceDate     DATE          = NULL,
    @NextMaintenanceDate     DATE          = NULL,
    @WaterQualityTestDueDate DATE          = NULL,
    @Status                  NVARCHAR(30)  = 'Active',
    @Notes                   NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterBoreholes (
        FarmId, BoreholeName, Location, PumpType, PumpCapacity, TankCapacity,
        WaterTreatmentMethod, FiltrationSystem, UVSterilizationAvailable,
        MaintenanceFrequencyDays, LastMaintenanceDate, NextMaintenanceDate,
        WaterQualityTestDueDate, Status, Notes
    )
    VALUES (
        @FarmId, @BoreholeName, @Location, @PumpType, @PumpCapacity, @TankCapacity,
        @WaterTreatmentMethod, @FiltrationSystem, @UVSterilizationAvailable,
        @MaintenanceFrequencyDays, @LastMaintenanceDate, @NextMaintenanceDate,
        @WaterQualityTestDueDate, @Status, @Notes
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterBorehole_Update
    @WaterBoreholeId         INT,
    @FarmId                  NVARCHAR(450),
    @BoreholeName            NVARCHAR(150),
    @Location                NVARCHAR(255) = NULL,
    @PumpType                NVARCHAR(60)  = NULL,
    @PumpCapacity            NVARCHAR(60)  = NULL,
    @TankCapacity            NVARCHAR(60)  = NULL,
    @WaterTreatmentMethod    NVARCHAR(120) = NULL,
    @FiltrationSystem        NVARCHAR(120) = NULL,
    @UVSterilizationAvailable BIT,
    @MaintenanceFrequencyDays INT          = NULL,
    @LastMaintenanceDate     DATE          = NULL,
    @NextMaintenanceDate     DATE          = NULL,
    @WaterQualityTestDueDate DATE          = NULL,
    @Status                  NVARCHAR(30),
    @Notes                   NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterBoreholes
    SET BoreholeName = @BoreholeName, Location = @Location, PumpType = @PumpType,
        PumpCapacity = @PumpCapacity, TankCapacity = @TankCapacity,
        WaterTreatmentMethod = @WaterTreatmentMethod, FiltrationSystem = @FiltrationSystem,
        UVSterilizationAvailable = @UVSterilizationAvailable,
        MaintenanceFrequencyDays = @MaintenanceFrequencyDays,
        LastMaintenanceDate = @LastMaintenanceDate, NextMaintenanceDate = @NextMaintenanceDate,
        WaterQualityTestDueDate = @WaterQualityTestDueDate,
        Status = @Status, Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
    WHERE WaterBoreholeId = @WaterBoreholeId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterBorehole_Delete
    @WaterBoreholeId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterBoreholes SET Status = 'Inactive', UpdatedAt = SYSUTCDATETIME()
    WHERE WaterBoreholeId = @WaterBoreholeId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- WaterMachine
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterMachine_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.WaterMachines WHERE FarmId = @FarmId
    ORDER BY (CASE WHEN Status = 'Active' THEN 0 ELSE 1 END), MachineName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterMachine_GetById
    @WaterMachineId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.WaterMachines
    WHERE WaterMachineId = @WaterMachineId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterMachine_Insert
    @FarmId                   NVARCHAR(450),
    @MachineName              NVARCHAR(150),
    @MachineNumber            NVARCHAR(60)  = NULL,
    @MachineType              NVARCHAR(40)  = NULL,
    @Manufacturer             NVARCHAR(120) = NULL,
    @PurchaseDate             DATE          = NULL,
    @CapacityPerHour          INT           = NULL,
    @AssignedOperatorStaffId  INT           = NULL,
    @MaintenanceFrequencyDays INT           = NULL,
    @LastMaintenanceDate      DATE          = NULL,
    @NextMaintenanceDate      DATE          = NULL,
    @Status                   NVARCHAR(30)  = 'Active',
    @Notes                    NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterMachines (
        FarmId, MachineName, MachineNumber, MachineType, Manufacturer, PurchaseDate,
        CapacityPerHour, AssignedOperatorStaffId, MaintenanceFrequencyDays,
        LastMaintenanceDate, NextMaintenanceDate, Status, Notes
    )
    VALUES (
        @FarmId, @MachineName, @MachineNumber, @MachineType, @Manufacturer, @PurchaseDate,
        @CapacityPerHour, @AssignedOperatorStaffId, @MaintenanceFrequencyDays,
        @LastMaintenanceDate, @NextMaintenanceDate, @Status, @Notes
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterMachine_Update
    @WaterMachineId           INT,
    @FarmId                   NVARCHAR(450),
    @MachineName              NVARCHAR(150),
    @MachineNumber            NVARCHAR(60)  = NULL,
    @MachineType              NVARCHAR(40)  = NULL,
    @Manufacturer             NVARCHAR(120) = NULL,
    @PurchaseDate             DATE          = NULL,
    @CapacityPerHour          INT           = NULL,
    @AssignedOperatorStaffId  INT           = NULL,
    @MaintenanceFrequencyDays INT           = NULL,
    @LastMaintenanceDate      DATE          = NULL,
    @NextMaintenanceDate      DATE          = NULL,
    @Status                   NVARCHAR(30),
    @Notes                    NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterMachines
    SET MachineName = @MachineName, MachineNumber = @MachineNumber, MachineType = @MachineType,
        Manufacturer = @Manufacturer, PurchaseDate = @PurchaseDate,
        CapacityPerHour = @CapacityPerHour, AssignedOperatorStaffId = @AssignedOperatorStaffId,
        MaintenanceFrequencyDays = @MaintenanceFrequencyDays,
        LastMaintenanceDate = @LastMaintenanceDate, NextMaintenanceDate = @NextMaintenanceDate,
        Status = @Status, Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
    WHERE WaterMachineId = @WaterMachineId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterMachine_Delete
    @WaterMachineId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterMachines SET Status = 'Inactive', UpdatedAt = SYSUTCDATETIME()
    WHERE WaterMachineId = @WaterMachineId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- WaterProductionBatch
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterProductionBatch_GetAll
    @FarmId   NVARCHAR(450),
    @Status   NVARCHAR(20) = NULL,
    @FromDate DATE         = NULL,
    @ToDate   DATE         = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT b.*, p.Name AS ProductName, m.MachineName, bh.BoreholeName
    FROM   dbo.WaterProductionBatches b
    INNER  JOIN dbo.WaterProducts p   ON p.WaterProductId = b.WaterProductId
    LEFT   JOIN dbo.WaterMachines m   ON m.WaterMachineId = b.WaterMachineId
    LEFT   JOIN dbo.WaterBoreholes bh ON bh.WaterBoreholeId = b.WaterBoreholeId
    WHERE  b.FarmId = @FarmId AND b.IsDeleted = 0
       AND (@Status   IS NULL OR b.Status = @Status)
       AND (@FromDate IS NULL OR b.ProductionDate >= @FromDate)
       AND (@ToDate   IS NULL OR b.ProductionDate <= @ToDate)
    ORDER  BY b.ProductionDate DESC, b.WaterProductionBatchId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProductionBatch_GetById
    @WaterProductionBatchId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT b.*, p.Name AS ProductName, m.MachineName, bh.BoreholeName
    FROM   dbo.WaterProductionBatches b
    INNER  JOIN dbo.WaterProducts p   ON p.WaterProductId = b.WaterProductId
    LEFT   JOIN dbo.WaterMachines m   ON m.WaterMachineId = b.WaterMachineId
    LEFT   JOIN dbo.WaterBoreholes bh ON bh.WaterBoreholeId = b.WaterBoreholeId
    WHERE  b.WaterProductionBatchId = @WaterProductionBatchId AND b.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProductionBatch_Insert
    @FarmId                   NVARCHAR(450),
    @BatchNumber              NVARCHAR(60),
    @ProductionDate           DATE,
    @Shift                    NVARCHAR(20)  = 'FullDay',
    @WaterMachineId           INT           = NULL,
    @WaterBoreholeId          INT           = NULL,
    @OperatorStaffId          INT           = NULL,
    @StartTime                DATETIME2     = NULL,
    @EndTime                  DATETIME2     = NULL,
    @WaterProductId           INT,
    @BagsProduced             INT           = 0,
    @SachetsPerBag            INT           = 30,
    @LooseSachetsProduced     INT           = 0,
    @RejectedSachets          INT           = 0,
    @DamagedBags              INT           = 0,
    @PackagingRollsUsed       INT           = 0,
    @EstimatedWaterUsedLitres INT           = NULL,
    @ElectricityCost          DECIMAL(14,2) = 0,
    @FuelCost                 DECIMAL(14,2) = 0,
    @LaborCost                DECIMAL(14,2) = 0,
    @OtherProductionCost      DECIMAL(14,2) = 0,
    @QualityStatus            NVARCHAR(20)  = 'Pending',
    @QualityPHLevel           DECIMAL(5,2)  = NULL,
    @QualityChlorinePpm       DECIMAL(8,4)  = NULL,
    @QualityTurbidity         DECIMAL(8,4)  = NULL,
    @QualityTDS               INT           = NULL,
    @QualityNotes             NVARCHAR(500) = NULL,
    @Notes                    NVARCHAR(1000) = NULL,
    @CreatedBy                NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF (@BagsProduced < 0)
    BEGIN RAISERROR('BagsProduced cannot be negative.', 16, 1); RETURN; END
    IF (@SachetsPerBag <= 0) SET @SachetsPerBag = 30;
    IF (@DamagedBags < 0 OR @DamagedBags > @BagsProduced)
    BEGIN RAISERROR('DamagedBags must be between 0 and BagsProduced.', 16, 1); RETURN; END

    INSERT INTO dbo.WaterProductionBatches (
        FarmId, BatchNumber, ProductionDate, Shift, WaterMachineId, WaterBoreholeId,
        OperatorStaffId, StartTime, EndTime, WaterProductId, BagsProduced, SachetsPerBag,
        LooseSachetsProduced, RejectedSachets, DamagedBags, PackagingRollsUsed,
        EstimatedWaterUsedLitres, ElectricityCost, FuelCost, LaborCost, OtherProductionCost,
        QualityStatus, QualityPHLevel, QualityChlorinePpm, QualityTurbidity, QualityTDS,
        QualityNotes, Notes, Status, CreatedBy
    )
    VALUES (
        @FarmId, @BatchNumber, @ProductionDate, @Shift, @WaterMachineId, @WaterBoreholeId,
        @OperatorStaffId, @StartTime, @EndTime, @WaterProductId, @BagsProduced, @SachetsPerBag,
        @LooseSachetsProduced, @RejectedSachets, @DamagedBags, @PackagingRollsUsed,
        @EstimatedWaterUsedLitres, @ElectricityCost, @FuelCost, @LaborCost, @OtherProductionCost,
        @QualityStatus, @QualityPHLevel, @QualityChlorinePpm, @QualityTurbidity, @QualityTDS,
        @QualityNotes, @Notes, 'Draft', @CreatedBy
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProductionBatch_Update
    @WaterProductionBatchId   INT,
    @FarmId                   NVARCHAR(450),
    @BatchNumber              NVARCHAR(60),
    @ProductionDate           DATE,
    @Shift                    NVARCHAR(20),
    @WaterMachineId           INT           = NULL,
    @WaterBoreholeId          INT           = NULL,
    @OperatorStaffId          INT           = NULL,
    @StartTime                DATETIME2     = NULL,
    @EndTime                  DATETIME2     = NULL,
    @WaterProductId           INT,
    @BagsProduced             INT,
    @SachetsPerBag            INT,
    @LooseSachetsProduced     INT,
    @RejectedSachets          INT,
    @DamagedBags              INT,
    @PackagingRollsUsed       INT,
    @EstimatedWaterUsedLitres INT           = NULL,
    @ElectricityCost          DECIMAL(14,2),
    @FuelCost                 DECIMAL(14,2),
    @LaborCost                DECIMAL(14,2),
    @OtherProductionCost      DECIMAL(14,2),
    @QualityStatus            NVARCHAR(20),
    @QualityPHLevel           DECIMAL(5,2)  = NULL,
    @QualityChlorinePpm       DECIMAL(8,4)  = NULL,
    @QualityTurbidity         DECIMAL(8,4)  = NULL,
    @QualityTDS               INT           = NULL,
    @QualityNotes             NVARCHAR(500) = NULL,
    @Notes                    NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- Block edits once Approved (audit safety). Caller should cancel + recreate.
    IF EXISTS (SELECT 1 FROM dbo.WaterProductionBatches
               WHERE WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        RAISERROR('Cannot edit an Approved production batch. Cancel and recreate.', 16, 1);
        RETURN;
    END

    UPDATE dbo.WaterProductionBatches
    SET BatchNumber = @BatchNumber, ProductionDate = @ProductionDate, Shift = @Shift,
        WaterMachineId = @WaterMachineId, WaterBoreholeId = @WaterBoreholeId,
        OperatorStaffId = @OperatorStaffId, StartTime = @StartTime, EndTime = @EndTime,
        WaterProductId = @WaterProductId, BagsProduced = @BagsProduced,
        SachetsPerBag = @SachetsPerBag, LooseSachetsProduced = @LooseSachetsProduced,
        RejectedSachets = @RejectedSachets, DamagedBags = @DamagedBags,
        PackagingRollsUsed = @PackagingRollsUsed,
        EstimatedWaterUsedLitres = @EstimatedWaterUsedLitres,
        ElectricityCost = @ElectricityCost, FuelCost = @FuelCost,
        LaborCost = @LaborCost, OtherProductionCost = @OtherProductionCost,
        QualityStatus = @QualityStatus, QualityPHLevel = @QualityPHLevel,
        QualityChlorinePpm = @QualityChlorinePpm, QualityTurbidity = @QualityTurbidity,
        QualityTDS = @QualityTDS, QualityNotes = @QualityNotes, Notes = @Notes,
        UpdatedAt = SYSUTCDATETIME()
    WHERE WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId;
END
GO

-- THE BIG SP: atomic approve writes a Restock stock movement for the good bags.
CREATE OR ALTER PROCEDURE dbo.spWaterProductionBatch_Approve
    @WaterProductionBatchId INT,
    @FarmId                 NVARCHAR(450),
    @ApprovedBy             NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Idempotent
    IF EXISTS (SELECT 1 FROM dbo.WaterProductionBatches
               WHERE WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT WaterProductionBatchId, Status, ApprovedBy, ApprovedAt
        FROM dbo.WaterProductionBatches
        WHERE WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @Status     NVARCHAR(20),
            @ProductId  INT,
            @BagsProduced INT,
            @DamagedBags  INT,
            @TotalCost  DECIMAL(14,2),
            @BatchNo    NVARCHAR(60);

    SELECT @Status = Status, @ProductId = WaterProductId,
           @BagsProduced = BagsProduced, @DamagedBags = DamagedBags,
           @TotalCost = TotalProductionCost, @BatchNo = BatchNumber
    FROM   dbo.WaterProductionBatches
    WHERE  WaterProductionBatchId = @WaterProductionBatchId
       AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL
    BEGIN RAISERROR('Production batch %d not found.', 16, 1, @WaterProductionBatchId); RETURN; END
    IF @Status <> 'Draft'
    BEGIN RAISERROR('Production batch cannot be approved from status %s.', 16, 1, @Status); RETURN; END

    DECLARE @GoodBags INT = @BagsProduced - ISNULL(@DamagedBags, 0);
    IF (@GoodBags < 0) SET @GoodBags = 0;

    -- Cost-per-bag fallback to 1 to avoid div/0; only used to set UnitCost on the
    -- stock txn for inventory valuation.
    DECLARE @CostPerBag DECIMAL(14,2) = CASE WHEN @GoodBags > 0 THEN @TotalCost / @GoodBags ELSE 0 END;

    BEGIN TRANSACTION;

    UPDATE dbo.WaterProductionBatches
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId;

    IF (@GoodBags > 0)
    BEGIN
        INSERT INTO dbo.WaterStockTransactions (
            FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId,
            Note, CreatedBy
        )
        VALUES (
            @FarmId, @ProductId, 'Restock', @GoodBags, @CostPerBag, NULL,
            CONCAT('Production batch ', @BatchNo), @ApprovedBy
        );
    END

    COMMIT TRANSACTION;

    SELECT WaterProductionBatchId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.WaterProductionBatches
    WHERE  WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterProductionBatch_Cancel
    @WaterProductionBatchId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterProductionBatches
    SET    IsDeleted = 1, UpdatedAt = SYSUTCDATETIME()
    WHERE  WaterProductionBatchId = @WaterProductionBatchId AND FarmId = @FarmId AND Status = 'Draft';
    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Only Draft production batches can be cancelled.', 16, 1);
        RETURN;
    END
END
GO

-- =============================================================================
-- WaterQualityTest
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterQualityTest_GetAll
    @FarmId  NVARCHAR(450),
    @BoreholeId INT = NULL,
    @BatchId    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.*, bh.BoreholeName, b.BatchNumber
    FROM   dbo.WaterQualityTests t
    LEFT   JOIN dbo.WaterBoreholes bh ON bh.WaterBoreholeId = t.WaterBoreholeId
    LEFT   JOIN dbo.WaterProductionBatches b ON b.WaterProductionBatchId = t.WaterProductionBatchId
    WHERE  t.FarmId = @FarmId
       AND (@BoreholeId IS NULL OR t.WaterBoreholeId = @BoreholeId)
       AND (@BatchId    IS NULL OR t.WaterProductionBatchId = @BatchId)
    ORDER  BY t.TestDate DESC, t.WaterQualityTestId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterQualityTest_Insert
    @FarmId                NVARCHAR(450),
    @WaterBoreholeId       INT           = NULL,
    @WaterProductionBatchId INT          = NULL,
    @TestDate              DATETIME2     = NULL,
    @TestType              NVARCHAR(40)  = NULL,
    @PHLevel               DECIMAL(5,2)  = NULL,
    @TDS                   INT           = NULL,
    @Turbidity             DECIMAL(8,4)  = NULL,
    @ChlorineLevel         DECIMAL(8,4)  = NULL,
    @Result                NVARCHAR(20)  = 'Pending',
    @TestedBy              NVARCHAR(120) = NULL,
    @LabName               NVARCHAR(150) = NULL,
    @AttachmentUrl         NVARCHAR(500) = NULL,
    @NextTestDate          DATE          = NULL,
    @Notes                 NVARCHAR(1000) = NULL,
    @CreatedBy             NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterQualityTests (
        FarmId, WaterBoreholeId, WaterProductionBatchId, TestDate, TestType,
        PHLevel, TDS, Turbidity, ChlorineLevel, Result, TestedBy, LabName,
        AttachmentUrl, NextTestDate, Notes, CreatedBy
    )
    VALUES (
        @FarmId, @WaterBoreholeId, @WaterProductionBatchId,
        ISNULL(@TestDate, SYSUTCDATETIME()), @TestType,
        @PHLevel, @TDS, @Turbidity, @ChlorineLevel, @Result, @TestedBy, @LabName,
        @AttachmentUrl, @NextTestDate, @Notes, @CreatedBy
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

-- =============================================================================
-- WaterDailyPumpingLog (light CRUD)
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spWaterDailyPumpingLog_GetAll
    @FarmId   NVARCHAR(450),
    @FromDate DATE = NULL,
    @ToDate   DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT l.*, bh.BoreholeName
    FROM   dbo.WaterDailyPumpingLogs l
    INNER  JOIN dbo.WaterBoreholes bh ON bh.WaterBoreholeId = l.WaterBoreholeId
    WHERE  l.FarmId = @FarmId
       AND (@FromDate IS NULL OR l.LogDate >= @FromDate)
       AND (@ToDate   IS NULL OR l.LogDate <= @ToDate)
    ORDER  BY l.LogDate DESC, l.WaterDailyPumpingLogId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterDailyPumpingLog_Insert
    @FarmId                NVARCHAR(450),
    @WaterBoreholeId       INT,
    @LogDate               DATE,
    @OpeningTankLevel      INT          = NULL,
    @ClosingTankLevel      INT          = NULL,
    @EstimatedLitresPumped INT          = NULL,
    @PumpStartTime         DATETIME2    = NULL,
    @PumpEndTime           DATETIME2    = NULL,
    @ElectricityUsed       DECIMAL(14,2) = NULL,
    @FuelUsed              DECIMAL(14,2) = NULL,
    @OperatorStaffId       INT          = NULL,
    @Notes                 NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.WaterDailyPumpingLogs (
        FarmId, WaterBoreholeId, LogDate, OpeningTankLevel, ClosingTankLevel,
        EstimatedLitresPumped, PumpStartTime, PumpEndTime, ElectricityUsed,
        FuelUsed, OperatorStaffId, Notes
    )
    VALUES (
        @FarmId, @WaterBoreholeId, @LogDate, @OpeningTankLevel, @ClosingTankLevel,
        @EstimatedLitresPumped, @PumpStartTime, @PumpEndTime, @ElectricityUsed,
        @FuelUsed, @OperatorStaffId, @Notes
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

PRINT '039_AddWaterProductionStoredProcedures.sql complete.';
GO
