-- =============================================================================
-- Migration 153: Farm production settings (egg pick times + enable 4th pick)
-- =============================================================================
-- Farms pick eggs at different times of day. Production records are labelled
-- generically (1st/2nd/3rd/4th Pick); this table lets each farm configure the
-- time each pick represents (display/reporting only) and whether the 4th pick is
-- enabled for entry. Times are stored as 24h "HH:mm" strings; the UI formats them.
--
-- EnableFourthPick defaults to 0 (off) so existing farms are unchanged; the
-- backend always stores the 4th pick regardless. Idempotent.
-- =============================================================================
IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 50000, N'Select your application database (not master). Aborting.', 1;
END
GO

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[FarmProductionSettings]') AND type = N'U')
BEGIN
    CREATE TABLE [dbo].[FarmProductionSettings] (
        [Id]               INT IDENTITY(1,1) NOT NULL CONSTRAINT [PK_FarmProductionSettings] PRIMARY KEY,
        [FarmId]           NVARCHAR(450) NOT NULL,
        [FirstPickTime]    NVARCHAR(10) NULL,
        [SecondPickTime]   NVARCHAR(10) NULL,
        [ThirdPickTime]    NVARCHAR(10) NULL,
        [FourthPickTime]   NVARCHAR(10) NULL,
        [EnableFourthPick] BIT NOT NULL CONSTRAINT [DF_FarmProductionSettings_EnableFourthPick] DEFAULT (0),
        [CreatedBy]        NVARCHAR(450) NULL,
        [CreatedDate]      DATETIME2 NOT NULL CONSTRAINT [DF_FarmProductionSettings_CreatedDate] DEFAULT (SYSUTCDATETIME()),
        [UpdatedBy]        NVARCHAR(450) NULL,
        [UpdatedDate]      DATETIME2 NULL,
        CONSTRAINT [UQ_FarmProductionSettings_FarmId] UNIQUE ([FarmId])
    );
    PRINT N'153: Created dbo.FarmProductionSettings';
END
GO

-- ---------------------------------------------------------------------------
-- Get — returns the stored row, or a sensible default row when none exists so
-- the caller always receives usable pick times.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spFarmProductionSettings_Get]
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM [dbo].[FarmProductionSettings] WHERE [FarmId] = @FarmId)
        SELECT [Id], [FarmId], [FirstPickTime], [SecondPickTime], [ThirdPickTime], [FourthPickTime],
               [EnableFourthPick], [CreatedBy], [CreatedDate], [UpdatedBy], [UpdatedDate]
        FROM   [dbo].[FarmProductionSettings]
        WHERE  [FarmId] = @FarmId;
    ELSE
        SELECT CAST(0 AS INT) AS [Id], @FarmId AS [FarmId],
               N'09:00' AS [FirstPickTime], N'12:00' AS [SecondPickTime], N'16:00' AS [ThirdPickTime], N'18:00' AS [FourthPickTime],
               CAST(0 AS BIT) AS [EnableFourthPick],
               CAST(NULL AS NVARCHAR(450)) AS [CreatedBy], CAST(NULL AS DATETIME2) AS [CreatedDate],
               CAST(NULL AS NVARCHAR(450)) AS [UpdatedBy], CAST(NULL AS DATETIME2) AS [UpdatedDate];
END
GO

-- ---------------------------------------------------------------------------
-- Upsert — one row per farm.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spFarmProductionSettings_Upsert]
    @FarmId           NVARCHAR(450),
    @FirstPickTime    NVARCHAR(10) = NULL,
    @SecondPickTime   NVARCHAR(10) = NULL,
    @ThirdPickTime    NVARCHAR(10) = NULL,
    @FourthPickTime   NVARCHAR(10) = NULL,
    @EnableFourthPick BIT = 0,
    @UpdatedBy        NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM [dbo].[FarmProductionSettings] WHERE [FarmId] = @FarmId)
        UPDATE [dbo].[FarmProductionSettings]
        SET    [FirstPickTime] = @FirstPickTime, [SecondPickTime] = @SecondPickTime,
               [ThirdPickTime] = @ThirdPickTime, [FourthPickTime] = @FourthPickTime,
               [EnableFourthPick] = @EnableFourthPick, [UpdatedBy] = @UpdatedBy, [UpdatedDate] = SYSUTCDATETIME()
        WHERE  [FarmId] = @FarmId;
    ELSE
        INSERT INTO [dbo].[FarmProductionSettings]
            ([FarmId], [FirstPickTime], [SecondPickTime], [ThirdPickTime], [FourthPickTime], [EnableFourthPick], [CreatedBy], [CreatedDate])
        VALUES (@FarmId, @FirstPickTime, @SecondPickTime, @ThirdPickTime, @FourthPickTime, @EnableFourthPick, @UpdatedBy, SYSUTCDATETIME());

    EXEC [dbo].[spFarmProductionSettings_Get] @FarmId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spFarmProductionSettings_Get    TO [Techretainer];
    GRANT EXECUTE ON dbo.spFarmProductionSettings_Upsert TO [Techretainer];
    GRANT SELECT, INSERT, UPDATE ON dbo.FarmProductionSettings TO [Techretainer];
    PRINT N'153: granted rights on FarmProductionSettings to Techretainer.';
END
GO

PRINT N'153_FarmProductionSettings.sql complete.';
GO
