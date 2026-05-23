-- =============================================================================
-- 022_AddFlockHasArrived.sql
-- Adds an explicit HasArrived flag to dbo.Flock so the UI can decide
-- Pending vs Active manually instead of inferring it from the start date.
--
-- Behavior after this migration:
--   HasArrived = 0  =>  status displays as Pending
--   HasArrived = 1  =>  status follows the existing Active boolean
--
-- Existing rows are backfilled to HasArrived = 1 (treated as already arrived)
-- so the dashboards / score-card numbers do not flip overnight.
--
-- Idempotent (safe to re-run).
-- =============================================================================

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 50000, N'Select your application database (not master). Aborting.', 1;
END
GO

SET NOCOUNT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Flock]') AND type = N'U')
BEGIN
    RAISERROR(N'022: dbo.Flock not found. Run earlier migrations first.', 16, 1);
END
GO

-- ---------------------------------------------------------------------------
-- 1. Add column. Default = 1 so existing rows backfill as already arrived
--    and any older sp shape that omits @HasArrived keeps inserting arrived rows.
--    New rows from the updated sp will pass the explicit value from the form.
-- ---------------------------------------------------------------------------
IF COL_LENGTH(N'dbo.Flock', N'HasArrived') IS NULL
BEGIN
    ALTER TABLE [dbo].[Flock]
        ADD [HasArrived] BIT NOT NULL CONSTRAINT [DF_Flock_HasArrived] DEFAULT (1);
    PRINT N'022: Added Flock.HasArrived (defaulted existing rows to 1).';
END
GO

-- ---------------------------------------------------------------------------
-- 2. Update sp's. Append @HasArrived at the end with a default so any other
--    caller without the new param keeps working.
-- ---------------------------------------------------------------------------

CREATE OR ALTER PROCEDURE [dbo].[spFlock_Insert]
    @UserId             NVARCHAR(450),
    @FarmId             NVARCHAR(450),
    @Name               NVARCHAR(255),
    @Breed              NVARCHAR(100),
    @StartDate          DATETIME2,
    @Quantity           INT,
    @BatchId            INT,
    @HouseId            INT             = NULL,
    @InactivationReason NVARCHAR(255)   = NULL,
    @OtherReason        NVARCHAR(500)   = NULL,
    @Notes              NVARCHAR(MAX)   = NULL,
    @HasArrived         BIT             = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @Quantity <= 0
    BEGIN
        RAISERROR('Quantity must be greater than zero', 16, 1);
        RETURN;
    END

    IF @BatchId IS NULL OR @BatchId = 0
    BEGIN
        RAISERROR('BatchId is required', 16, 1);
        RETURN;
    END

    INSERT INTO [dbo].[Flock]
    (
        [UserId], [FarmId], [Name], [Breed], [StartDate], [Quantity],
        [Active], [HouseId], [BatchId],
        [InactivationReason], [OtherReason], [Notes],
        [HasArrived]
    )
    VALUES
    (
        @UserId, @FarmId, @Name, @Breed, @StartDate, @Quantity,
        1, @HouseId, @BatchId,
        @InactivationReason, @OtherReason, @Notes,
        ISNULL(@HasArrived, 0)
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS FlockId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spFlock_Update]
    @FlockId            INT,
    @Name               NVARCHAR(255),
    @Breed              NVARCHAR(100),
    @StartDate          DATETIME2,
    @Quantity           INT,
    @Active             BIT,
    @HouseId            INT             = NULL,
    @InactivationReason NVARCHAR(255)   = NULL,
    @OtherReason        NVARCHAR(500)   = NULL,
    @UserId             NVARCHAR(450),
    @FarmId             NVARCHAR(450),
    @BatchId            INT             = NULL,
    @Notes              NVARCHAR(MAX)   = NULL,
    @HasArrived         BIT             = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE [dbo].[Flock]
    SET
        [Name]               = @Name,
        [Breed]              = @Breed,
        [StartDate]          = @StartDate,
        [Quantity]           = @Quantity,
        [Active]             = @Active,
        [HouseId]            = @HouseId,
        [InactivationReason] = @InactivationReason,
        [OtherReason]        = @OtherReason,
        [BatchId]            = @BatchId,
        [Notes]              = @Notes,
        [HasArrived]         = ISNULL(@HasArrived, [HasArrived])
    WHERE [FlockId] = @FlockId
      AND [FarmId]  = @FarmId;
END
GO

-- GetById / GetAll: rebuild so the new HasArrived column ships at a known
-- position alongside the existing select shape (keeps ISNULL Active default).
CREATE OR ALTER PROCEDURE [dbo].[spFlock_GetById]
    @FlockId INT,
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        f.[FlockId],
        f.[UserId],
        f.[FarmId],
        f.[Name],
        f.[Breed],
        f.[StartDate],
        f.[Quantity],
        ISNULL(f.[Active], 1) AS [Active],
        f.[HouseId],
        f.[BatchId],
        f.[InactivationReason],
        f.[OtherReason],
        f.[Notes],
        ISNULL(f.[HasArrived], 0) AS [HasArrived],
        b.[BatchName]
    FROM [dbo].[Flock] f
    LEFT JOIN [dbo].[MainFlockBatch] b
        ON f.[BatchId] = b.[BatchId] AND f.[FarmId] = b.[FarmId]
    WHERE f.[FlockId] = @FlockId
      AND f.[FarmId]  = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spFlock_GetAll]
    @FarmId NVARCHAR(450),
    @UserId NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        f.[FlockId],
        f.[UserId],
        f.[FarmId],
        f.[Name],
        f.[Breed],
        f.[StartDate],
        f.[Quantity],
        ISNULL(f.[Active], 1) AS [Active],
        f.[HouseId],
        f.[BatchId],
        f.[InactivationReason],
        f.[OtherReason],
        f.[Notes],
        ISNULL(f.[HasArrived], 0) AS [HasArrived],
        b.[BatchName]
    FROM [dbo].[Flock] f
    LEFT JOIN [dbo].[MainFlockBatch] b
        ON f.[BatchId] = b.[BatchId] AND f.[FarmId] = b.[FarmId]
    WHERE f.[FarmId] = @FarmId
    ORDER BY f.[StartDate] DESC;
END
GO

PRINT N'022_AddFlockHasArrived: complete.';
GO
