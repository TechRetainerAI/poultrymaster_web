-- =============================================================================
-- Migration 127: Poultry Company — Manual Loss / Damage Records (slice 5)
-- =============================================================================
-- Mirrors WaterLossRecords (manual entries: damages, mortality losses, missing
-- stock, etc.). Workflow: Pending -> Approved (reversible via Unapprove).
-- Self-contained (no cash posting in this slice). Additive.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.PoultryLossRecords', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryLossRecords (
        PoultryLossRecordId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId           NVARCHAR(450) NOT NULL,
        LossDate         DATETIME2     NOT NULL CONSTRAINT DF_PoultryLoss_Date DEFAULT (SYSUTCDATETIME()),
        LossType         NVARCHAR(40)  NOT NULL CONSTRAINT DF_PoultryLoss_Type DEFAULT ('Other'),  -- Damage | Mortality | Theft | Spoilage | MissingStock | Other
        PoultryProductId INT           NULL,
        Quantity         DECIMAL(14,3) NULL,
        EstimatedValue   DECIMAL(14,2) NULL,
        ResponsibleStaffId INT         NULL,
        Reason           NVARCHAR(500) NULL,
        Status           NVARCHAR(20)  NOT NULL CONSTRAINT DF_PoultryLoss_Status DEFAULT ('Pending'),
        ApprovedBy       NVARCHAR(450) NULL,
        ApprovedAt       DATETIME2     NULL,
        Notes            NVARCHAR(500) NULL,
        CreatedBy        NVARCHAR(450) NULL,
        CreatedAt        DATETIME2     NOT NULL CONSTRAINT DF_PoultryLoss_Created DEFAULT (SYSUTCDATETIME()),
        UpdatedAt        DATETIME2     NULL
    );
    CREATE INDEX IX_PoultryLoss_FarmId ON dbo.PoultryLossRecords (FarmId);
    CREATE INDEX IX_PoultryLoss_Status ON dbo.PoultryLossRecords (Status);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryLossRecord_GetAll
    @FarmId NVARCHAR(450), @LossType NVARCHAR(40) = NULL, @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT l.*, p.Name AS ProductName
    FROM   dbo.PoultryLossRecords l
    LEFT   JOIN dbo.PoultryProducts p ON p.PoultryProductId = l.PoultryProductId
    WHERE  l.FarmId = @FarmId
       AND (@LossType IS NULL OR l.LossType = @LossType)
       AND (@FromDate IS NULL OR CAST(l.LossDate AS DATE) >= @FromDate)
       AND (@ToDate   IS NULL OR CAST(l.LossDate AS DATE) <= @ToDate)
    ORDER  BY l.LossDate DESC, l.PoultryLossRecordId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryLossRecord_Insert
    @FarmId NVARCHAR(450), @LossDate DATETIME2 = NULL, @LossType NVARCHAR(40),
    @PoultryProductId INT = NULL, @Quantity DECIMAL(14,3) = NULL, @EstimatedValue DECIMAL(14,2) = NULL,
    @ResponsibleStaffId INT = NULL, @Reason NVARCHAR(500) = NULL, @Notes NVARCHAR(500) = NULL, @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.PoultryLossRecords (FarmId, LossDate, LossType, PoultryProductId, Quantity, EstimatedValue, ResponsibleStaffId, Reason, Notes, CreatedBy)
    VALUES (@FarmId, ISNULL(@LossDate, SYSUTCDATETIME()), @LossType, @PoultryProductId, @Quantity, @EstimatedValue, @ResponsibleStaffId, @Reason, @Notes, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryLossRecord_Update
    @PoultryLossRecordId INT, @FarmId NVARCHAR(450), @LossDate DATETIME2 = NULL, @LossType NVARCHAR(40),
    @PoultryProductId INT = NULL, @Quantity DECIMAL(14,3) = NULL, @EstimatedValue DECIMAL(14,2) = NULL,
    @ResponsibleStaffId INT = NULL, @Reason NVARCHAR(500) = NULL, @Notes NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.PoultryLossRecords WHERE PoultryLossRecordId = @PoultryLossRecordId AND FarmId = @FarmId AND Status = 'Pending')
    BEGIN RAISERROR('Only Pending loss records can be edited.', 16, 1); RETURN; END
    UPDATE dbo.PoultryLossRecords
    SET    LossDate = ISNULL(@LossDate, LossDate), LossType = @LossType, PoultryProductId = @PoultryProductId,
           Quantity = @Quantity, EstimatedValue = @EstimatedValue, ResponsibleStaffId = @ResponsibleStaffId,
           Reason = @Reason, Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryLossRecordId = @PoultryLossRecordId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryLossRecord_Approve
    @PoultryLossRecordId INT, @FarmId NVARCHAR(450), @ApprovedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryLossRecords
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy, ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryLossRecordId = @PoultryLossRecordId AND FarmId = @FarmId AND Status = 'Pending';
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryLossRecord_Unapprove
    @PoultryLossRecordId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryLossRecords
    SET    Status = 'Pending', ApprovedBy = NULL, ApprovedAt = NULL, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryLossRecordId = @PoultryLossRecordId AND FarmId = @FarmId AND Status = 'Approved';
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryLossRecord_Delete
    @PoultryLossRecordId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.PoultryLossRecords WHERE PoultryLossRecordId = @PoultryLossRecordId AND FarmId = @FarmId AND Status = 'Pending';
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryLossRecord_GetAll    TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryLossRecord_Insert    TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryLossRecord_Update    TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryLossRecord_Approve   TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryLossRecord_Unapprove TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryLossRecord_Delete    TO [Techretainer];
    PRINT '127: granted EXECUTE on spPoultryLossRecord_* to Techretainer.';
END
GO

PRINT '127_AddPoultryLossRecords.sql complete.';
GO
