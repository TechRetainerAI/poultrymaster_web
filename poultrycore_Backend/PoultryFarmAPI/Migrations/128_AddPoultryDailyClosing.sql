-- =============================================================================
-- Migration 128: Poultry Company — Daily Closing (slice 6)
-- =============================================================================
-- Mirrors WaterDailyClosing: an end-of-day snapshot that aggregates production,
-- damage/loss and finished-stock for the date. Draft rows compute live; Submit
-- persists the computed totals. Workflow: Draft -> Submitted -> Approved/Rejected.
-- Additive. Self-contained (no cash ledger posting in this slice).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.PoultryDailyClosings', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryDailyClosings (
        PoultryDailyClosingId INT IDENTITY(1,1) PRIMARY KEY,
        FarmId           NVARCHAR(450) NOT NULL,
        ClosingDate      DATE          NOT NULL,
        QuantityProduced DECIMAL(14,3) NOT NULL CONSTRAINT DF_PoultryClose_Prod DEFAULT (0),
        QuantityDamaged  DECIMAL(14,3) NOT NULL CONSTRAINT DF_PoultryClose_Dmg DEFAULT (0),
        TotalProductionCost DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryClose_ProdCost DEFAULT (0),
        ClosingStock     DECIMAL(14,3) NOT NULL CONSTRAINT DF_PoultryClose_Stock DEFAULT (0),
        CashAtHand       DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryClose_Cash DEFAULT (0),
        ActualCashCounted DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryClose_ActCash DEFAULT (0),
        CashDifference   DECIMAL(14,2) NOT NULL CONSTRAINT DF_PoultryClose_Diff DEFAULT (0),
        ManagerNotes     NVARCHAR(2000) NULL,
        Status           NVARCHAR(20)  NOT NULL CONSTRAINT DF_PoultryClose_Status DEFAULT ('Draft'),
        RejectionReason  NVARCHAR(500) NULL,
        CreatedBy        NVARCHAR(450) NULL,
        SubmittedBy      NVARCHAR(450) NULL,
        SubmittedAt      DATETIME2     NULL,
        ApprovedBy       NVARCHAR(450) NULL,
        ApprovedAt       DATETIME2     NULL,
        CreatedAt        DATETIME2     NOT NULL CONSTRAINT DF_PoultryClose_Created DEFAULT (SYSUTCDATETIME()),
        UpdatedAt        DATETIME2     NULL,
        CONSTRAINT UQ_PoultryClose_FarmDate UNIQUE (FarmId, ClosingDate)
    );
    CREATE INDEX IX_PoultryClose_FarmId ON dbo.PoultryDailyClosings (FarmId);
    CREATE INDEX IX_PoultryClose_Status ON dbo.PoultryDailyClosings (Status);
END
GO

-- Helper: aggregate the production/loss/stock figures for a farm + date.
CREATE OR ALTER PROCEDURE dbo.spPoultryDailyClosing_ComputeForDate
    @FarmId NVARCHAR(450), @ClosingDate DATE,
    @QuantityProduced DECIMAL(14,3) OUTPUT, @QuantityDamaged DECIMAL(14,3) OUTPUT,
    @TotalProductionCost DECIMAL(14,2) OUTPUT, @ClosingStock DECIMAL(14,3) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @QuantityProduced = ISNULL(SUM(CASE WHEN Status='Approved' THEN QuantityProduced - DamagedQuantity ELSE 0 END),0),
           @TotalProductionCost = ISNULL(SUM(CASE WHEN Status='Approved' THEN TotalCost ELSE 0 END),0)
    FROM   dbo.PoultryProductionBatches
    WHERE  FarmId = @FarmId AND CAST(ProductionDate AS DATE) = @ClosingDate;

    SELECT @QuantityDamaged = ISNULL(SUM(QuantityLost),0)
    FROM   dbo.PoultryProductionLoss
    WHERE  FarmId = @FarmId AND CAST(LossDate AS DATE) = @ClosingDate;

    SELECT @ClosingStock = ISNULL(SUM(Quantity),0)
    FROM   dbo.PoultryStockTransactions
    WHERE  FarmId = @FarmId AND CAST(CreatedDate AS DATE) <= @ClosingDate;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDailyClosing_GetAll
    @FarmId NVARCHAR(450), @Status NVARCHAR(20) = NULL, @FromDate DATE = NULL, @ToDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.PoultryDailyClosings
    WHERE  FarmId = @FarmId
       AND (@Status IS NULL OR Status = @Status)
       AND (@FromDate IS NULL OR ClosingDate >= @FromDate)
       AND (@ToDate   IS NULL OR ClosingDate <= @ToDate)
    ORDER  BY ClosingDate DESC, PoultryDailyClosingId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDailyClosing_GetById
    @PoultryDailyClosingId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Status NVARCHAR(20), @Date DATE;
    SELECT @Status = Status, @Date = ClosingDate FROM dbo.PoultryDailyClosings
    WHERE  PoultryDailyClosingId = @PoultryDailyClosingId AND FarmId = @FarmId;
    IF @Status IS NULL RETURN;

    IF @Status = 'Draft'
    BEGIN
        DECLARE @P DECIMAL(14,3), @D DECIMAL(14,3), @C DECIMAL(14,2), @S DECIMAL(14,3);
        EXEC dbo.spPoultryDailyClosing_ComputeForDate @FarmId, @Date, @P OUTPUT, @D OUTPUT, @C OUTPUT, @S OUTPUT;
        SELECT PoultryDailyClosingId, FarmId, ClosingDate,
               @P AS QuantityProduced, @D AS QuantityDamaged, @C AS TotalProductionCost, @S AS ClosingStock,
               CashAtHand, ActualCashCounted, CashDifference, ManagerNotes, Status, RejectionReason,
               CreatedBy, SubmittedBy, SubmittedAt, ApprovedBy, ApprovedAt, CreatedAt, UpdatedAt
        FROM   dbo.PoultryDailyClosings
        WHERE  PoultryDailyClosingId = @PoultryDailyClosingId AND FarmId = @FarmId;
    END
    ELSE
        SELECT * FROM dbo.PoultryDailyClosings
        WHERE  PoultryDailyClosingId = @PoultryDailyClosingId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDailyClosing_Insert
    @FarmId NVARCHAR(450), @ClosingDate DATE, @ManagerNotes NVARCHAR(2000) = NULL, @CreatedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM dbo.PoultryDailyClosings WHERE FarmId = @FarmId AND ClosingDate = @ClosingDate)
    BEGIN RAISERROR('A closing already exists for this date.', 16, 1); RETURN; END
    INSERT INTO dbo.PoultryDailyClosings (FarmId, ClosingDate, ManagerNotes, CreatedBy)
    VALUES (@FarmId, @ClosingDate, @ManagerNotes, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDailyClosing_Submit
    @PoultryDailyClosingId INT, @FarmId NVARCHAR(450), @ActualCashCounted DECIMAL(14,2) = 0,
    @ManagerNotes NVARCHAR(2000) = NULL, @SubmittedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    DECLARE @Date DATE;
    SELECT @Date = ClosingDate FROM dbo.PoultryDailyClosings
    WHERE  PoultryDailyClosingId = @PoultryDailyClosingId AND FarmId = @FarmId AND Status = 'Draft';
    IF @Date IS NULL BEGIN RAISERROR('Only Draft closings can be submitted.', 16, 1); RETURN; END

    DECLARE @P DECIMAL(14,3), @D DECIMAL(14,3), @C DECIMAL(14,2), @S DECIMAL(14,3);
    EXEC dbo.spPoultryDailyClosing_ComputeForDate @FarmId, @Date, @P OUTPUT, @D OUTPUT, @C OUTPUT, @S OUTPUT;

    UPDATE dbo.PoultryDailyClosings
    SET    QuantityProduced = @P, QuantityDamaged = @D, TotalProductionCost = @C, ClosingStock = @S,
           ActualCashCounted = ISNULL(@ActualCashCounted,0),
           CashDifference = ISNULL(@ActualCashCounted,0) - CashAtHand,
           ManagerNotes = ISNULL(@ManagerNotes, ManagerNotes),
           Status = 'Submitted', SubmittedBy = @SubmittedBy, SubmittedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryDailyClosingId = @PoultryDailyClosingId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDailyClosing_Approve
    @PoultryDailyClosingId INT, @FarmId NVARCHAR(450), @ApprovedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryDailyClosings
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy, ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryDailyClosingId = @PoultryDailyClosingId AND FarmId = @FarmId AND Status = 'Submitted';
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDailyClosing_Reject
    @PoultryDailyClosingId INT, @FarmId NVARCHAR(450), @RejectionReason NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.PoultryDailyClosings
    SET    Status = 'Rejected', RejectionReason = @RejectionReason, UpdatedAt = SYSUTCDATETIME()
    WHERE  PoultryDailyClosingId = @PoultryDailyClosingId AND FarmId = @FarmId AND Status = 'Submitted';
END
GO

CREATE OR ALTER PROCEDURE dbo.spPoultryDailyClosing_Delete
    @PoultryDailyClosingId INT, @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.PoultryDailyClosings
    WHERE  PoultryDailyClosingId = @PoultryDailyClosingId AND FarmId = @FarmId AND Status IN ('Draft','Rejected');
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryDailyClosing_ComputeForDate TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDailyClosing_GetAll  TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDailyClosing_GetById TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDailyClosing_Insert  TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDailyClosing_Submit  TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDailyClosing_Approve TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDailyClosing_Reject  TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryDailyClosing_Delete  TO [Techretainer];
    PRINT '128: granted EXECUTE on spPoultryDailyClosing_* to Techretainer.';
END
GO

PRINT '128_AddPoultryDailyClosing.sql complete.';
GO
