-- =============================================================================
-- Migration 038: Water Company — Production schema
-- =============================================================================
-- Phase W1: Boreholes, Machines, Production Batches with embedded water-quality
-- fields, plus separate detailed Quality Tests table. Builds on Migration 025
-- which already created WaterProducts / WaterCustomers / WaterStockTransactions
-- / WaterSales / WaterSaleItems / WaterPayments.
--
-- All tables scoped by FarmId. Additive + idempotent.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. WaterBoreholes — water source tracking
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterBoreholes', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterBoreholes (
        WaterBoreholeId         INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                  NVARCHAR(450) NOT NULL,
        BoreholeName            NVARCHAR(150) NOT NULL,
        Location                NVARCHAR(255) NULL,
        PumpType                NVARCHAR(60)  NULL,
        PumpCapacity            NVARCHAR(60)  NULL,           -- e.g. "5000 L/hr"
        TankCapacity            NVARCHAR(60)  NULL,           -- e.g. "10000 L"
        WaterTreatmentMethod    NVARCHAR(120) NULL,
        FiltrationSystem        NVARCHAR(120) NULL,
        UVSterilizationAvailable BIT          NOT NULL CONSTRAINT DF_WaterBoreholes_UV DEFAULT (0),
        MaintenanceFrequencyDays INT          NULL,
        LastMaintenanceDate     DATE          NULL,
        NextMaintenanceDate     DATE          NULL,
        WaterQualityTestDueDate DATE          NULL,
        Status                  NVARCHAR(30)  NOT NULL CONSTRAINT DF_WaterBoreholes_Status DEFAULT ('Active'),
        Notes                   NVARCHAR(1000) NULL,
        CreatedAt               DATETIME2     NOT NULL CONSTRAINT DF_WaterBoreholes_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt               DATETIME2     NULL
    );
    CREATE INDEX IX_WaterBoreholes_FarmId ON dbo.WaterBoreholes (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 2. WaterMachines — sachet/bottling/dispenser machines
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterMachines', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterMachines (
        WaterMachineId           INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450) NOT NULL,
        MachineName              NVARCHAR(150) NOT NULL,
        MachineNumber            NVARCHAR(60)  NULL,
        MachineType              NVARCHAR(40)  NULL,           -- 'SachetMachine' | 'BottleMachine' | 'DispenserFiller' | 'Other'
        Manufacturer             NVARCHAR(120) NULL,
        PurchaseDate             DATE          NULL,
        CapacityPerHour          INT           NULL,            -- bags or bottles per hour
        AssignedOperatorStaffId  INT           NULL,
        MaintenanceFrequencyDays INT           NULL,
        LastMaintenanceDate      DATE          NULL,
        NextMaintenanceDate      DATE          NULL,
        Status                   NVARCHAR(30)  NOT NULL CONSTRAINT DF_WaterMachines_Status DEFAULT ('Active'),
        Notes                    NVARCHAR(1000) NULL,
        CreatedAt                DATETIME2     NOT NULL CONSTRAINT DF_WaterMachines_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                DATETIME2     NULL
    );
    CREATE INDEX IX_WaterMachines_FarmId ON dbo.WaterMachines (FarmId);
END
GO

-- -----------------------------------------------------------------------------
-- 3. WaterProductionBatches — the production heart
-- -----------------------------------------------------------------------------
-- Embedded quality status (Pending/Passed/Failed); detailed test logged
-- separately in WaterQualityTests if you want full lab readings.
--
-- Approval → writes a row to WaterStockTransactions with TxnType='Restock'
-- and Quantity = +(BagsProduced - DamagedBags). See spWaterProductionBatch_Approve.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterProductionBatches', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterProductionBatches (
        WaterProductionBatchId       INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                       NVARCHAR(450) NOT NULL,
        BatchNumber                  NVARCHAR(60)  NOT NULL,
        ProductionDate               DATE          NOT NULL,
        Shift                        NVARCHAR(20)  NOT NULL CONSTRAINT DF_WaterProductionBatches_Shift DEFAULT ('FullDay'),
        WaterMachineId               INT           NULL,
        WaterBoreholeId              INT           NULL,
        OperatorStaffId              INT           NULL,
        StartTime                    DATETIME2     NULL,
        EndTime                      DATETIME2     NULL,
        WaterProductId               INT           NOT NULL,
        BagsProduced                 INT           NOT NULL CONSTRAINT DF_WaterProductionBatches_Bags DEFAULT (0),
        SachetsPerBag                INT           NOT NULL CONSTRAINT DF_WaterProductionBatches_SPB DEFAULT (30),
        LooseSachetsProduced         INT           NOT NULL CONSTRAINT DF_WaterProductionBatches_Loose DEFAULT (0),
        RejectedSachets              INT           NOT NULL CONSTRAINT DF_WaterProductionBatches_Rejected DEFAULT (0),
        DamagedBags                  INT           NOT NULL CONSTRAINT DF_WaterProductionBatches_Damaged DEFAULT (0),
        PackagingRollsUsed           INT           NOT NULL CONSTRAINT DF_WaterProductionBatches_Rolls DEFAULT (0),
        EstimatedWaterUsedLitres     INT           NULL,
        ElectricityCost              DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterProductionBatches_Elec DEFAULT (0),
        FuelCost                     DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterProductionBatches_Fuel DEFAULT (0),
        LaborCost                    DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterProductionBatches_Labor DEFAULT (0),
        OtherProductionCost          DECIMAL(14,2) NOT NULL CONSTRAINT DF_WaterProductionBatches_Other DEFAULT (0),
        TotalProductionCost          AS (ElectricityCost + FuelCost + LaborCost + OtherProductionCost) PERSISTED,
        -- Inline quality summary (optional detailed test in WaterQualityTests).
        QualityStatus                NVARCHAR(20)  NOT NULL CONSTRAINT DF_WaterProductionBatches_QualityStatus DEFAULT ('Pending'),
        QualityPHLevel               DECIMAL(5,2)  NULL,
        QualityChlorinePpm           DECIMAL(8,4)  NULL,
        QualityTurbidity             DECIMAL(8,4)  NULL,
        QualityTDS                   INT           NULL,
        QualityNotes                 NVARCHAR(500) NULL,
        Notes                        NVARCHAR(1000) NULL,
        Status                       NVARCHAR(20)  NOT NULL CONSTRAINT DF_WaterProductionBatches_Status DEFAULT ('Draft'),
        CreatedBy                    NVARCHAR(450) NULL,
        ApprovedBy                   NVARCHAR(450) NULL,
        ApprovedAt                   DATETIME2     NULL,
        CreatedAt                    DATETIME2     NOT NULL CONSTRAINT DF_WaterProductionBatches_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                    DATETIME2     NULL,
        IsDeleted                    BIT           NOT NULL CONSTRAINT DF_WaterProductionBatches_IsDeleted DEFAULT (0),
        CONSTRAINT UQ_WaterProductionBatches_Farm_Batch UNIQUE (FarmId, BatchNumber),
        CONSTRAINT FK_WaterProductionBatches_Product   FOREIGN KEY (WaterProductId)  REFERENCES dbo.WaterProducts (WaterProductId),
        CONSTRAINT FK_WaterProductionBatches_Machine   FOREIGN KEY (WaterMachineId)  REFERENCES dbo.WaterMachines (WaterMachineId),
        CONSTRAINT FK_WaterProductionBatches_Borehole  FOREIGN KEY (WaterBoreholeId) REFERENCES dbo.WaterBoreholes (WaterBoreholeId)
    );

    CREATE INDEX IX_WaterProductionBatches_FarmId  ON dbo.WaterProductionBatches (FarmId);
    CREATE INDEX IX_WaterProductionBatches_Date    ON dbo.WaterProductionBatches (ProductionDate);
    CREATE INDEX IX_WaterProductionBatches_Status  ON dbo.WaterProductionBatches (Status);
    CREATE INDEX IX_WaterProductionBatches_Machine ON dbo.WaterProductionBatches (WaterMachineId);
END
GO

-- -----------------------------------------------------------------------------
-- 4. WaterQualityTests — separate detailed lab/field tests (per borehole or batch)
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterQualityTests', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterQualityTests (
        WaterQualityTestId       INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450) NOT NULL,
        WaterBoreholeId          INT           NULL,
        WaterProductionBatchId   INT           NULL,
        TestDate                 DATETIME2     NOT NULL CONSTRAINT DF_WaterQualityTests_Date DEFAULT (SYSUTCDATETIME()),
        TestType                 NVARCHAR(40)  NULL,           -- 'Internal' | 'FDA' | 'GhanaStandards' | 'Lab' | etc.
        PHLevel                  DECIMAL(5,2)  NULL,
        TDS                      INT           NULL,
        Turbidity                DECIMAL(8,4)  NULL,
        ChlorineLevel            DECIMAL(8,4)  NULL,
        Result                   NVARCHAR(20)  NOT NULL CONSTRAINT DF_WaterQualityTests_Result DEFAULT ('Pending'),
        TestedBy                 NVARCHAR(120) NULL,
        LabName                  NVARCHAR(150) NULL,
        AttachmentUrl            NVARCHAR(500) NULL,
        NextTestDate             DATE          NULL,
        Notes                    NVARCHAR(1000) NULL,
        CreatedBy                NVARCHAR(450) NULL,
        CreatedAt                DATETIME2     NOT NULL CONSTRAINT DF_WaterQualityTests_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                DATETIME2     NULL,
        CONSTRAINT FK_WaterQualityTests_Borehole FOREIGN KEY (WaterBoreholeId)        REFERENCES dbo.WaterBoreholes (WaterBoreholeId),
        CONSTRAINT FK_WaterQualityTests_Batch    FOREIGN KEY (WaterProductionBatchId) REFERENCES dbo.WaterProductionBatches (WaterProductionBatchId)
    );

    CREATE INDEX IX_WaterQualityTests_FarmId   ON dbo.WaterQualityTests (FarmId);
    CREATE INDEX IX_WaterQualityTests_Date     ON dbo.WaterQualityTests (TestDate);
    CREATE INDEX IX_WaterQualityTests_Borehole ON dbo.WaterQualityTests (WaterBoreholeId);
    CREATE INDEX IX_WaterQualityTests_Batch    ON dbo.WaterQualityTests (WaterProductionBatchId);
END
GO

-- -----------------------------------------------------------------------------
-- 5. WaterDailyPumpingLogs — borehole-level daily output
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.WaterDailyPumpingLogs', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterDailyPumpingLogs (
        WaterDailyPumpingLogId   INT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450) NOT NULL,
        WaterBoreholeId          INT           NOT NULL,
        LogDate                  DATE          NOT NULL,
        OpeningTankLevel         INT           NULL,
        ClosingTankLevel         INT           NULL,
        EstimatedLitresPumped    INT           NULL,
        PumpStartTime            DATETIME2     NULL,
        PumpEndTime              DATETIME2     NULL,
        ElectricityUsed          DECIMAL(14,2) NULL,
        FuelUsed                 DECIMAL(14,2) NULL,
        OperatorStaffId          INT           NULL,
        Notes                    NVARCHAR(500) NULL,
        CreatedAt                DATETIME2     NOT NULL CONSTRAINT DF_WaterDailyPumpingLogs_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedAt                DATETIME2     NULL,
        CONSTRAINT FK_WaterDailyPumpingLogs_Borehole FOREIGN KEY (WaterBoreholeId) REFERENCES dbo.WaterBoreholes (WaterBoreholeId)
    );

    CREATE INDEX IX_WaterDailyPumpingLogs_FarmId   ON dbo.WaterDailyPumpingLogs (FarmId);
    CREATE INDEX IX_WaterDailyPumpingLogs_Borehole ON dbo.WaterDailyPumpingLogs (WaterBoreholeId);
    CREATE INDEX IX_WaterDailyPumpingLogs_Date     ON dbo.WaterDailyPumpingLogs (LogDate);
END
GO

PRINT '038_AddWaterProductionSchema.sql complete.';
GO
