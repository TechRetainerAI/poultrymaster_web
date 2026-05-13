-- 014_FeedInventoryAdjustment.sql — manual feed stock corrections (feed tracker / ledger, kg)
-- Run against your application database (not master). Safe to re-run.

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 50000, N'Select your application database before running this script.', 1;
END
GO

SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.FeedInventoryAdjustment', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[FeedInventoryAdjustment] (
        [AdjustmentId]   INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
        [UserId]         NVARCHAR(450) NOT NULL,
        [FarmId]         NVARCHAR(450) NOT NULL,
        [AdjustmentDate] DATETIME2 NOT NULL,
        [AdjustmentType] NVARCHAR(50) NOT NULL,
        [FeedDeltaKg]    DECIMAL(18, 4) NOT NULL,
        [Description]    NVARCHAR(500) NULL,
        [CreatedDate]    DATETIME2 NOT NULL CONSTRAINT [DF_FeedInvAdj_Created] DEFAULT (SYSUTCDATETIME())
    );
    CREATE NONCLUSTERED INDEX [IX_FeedInvAdj_FarmId] ON [dbo].[FeedInventoryAdjustment]([FarmId]);
    CREATE NONCLUSTERED INDEX [IX_FeedInvAdj_FarmDate] ON [dbo].[FeedInventoryAdjustment]([FarmId], [AdjustmentDate]);
    PRINT N'Created dbo.FeedInventoryAdjustment.';
END
ELSE
    PRINT N'dbo.FeedInventoryAdjustment already exists.';
GO

CREATE OR ALTER PROCEDURE [dbo].[spFeedInventoryAdjustment_GetAll]
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        [AdjustmentId], [UserId], [FarmId], [AdjustmentDate], [AdjustmentType],
        [FeedDeltaKg], [Description], [CreatedDate]
    FROM [dbo].[FeedInventoryAdjustment]
    WHERE [FarmId] = @FarmId
    ORDER BY [AdjustmentDate] ASC, [AdjustmentId] ASC;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spFeedInventoryAdjustment_GetById]
    @AdjustmentId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        [AdjustmentId], [UserId], [FarmId], [AdjustmentDate], [AdjustmentType],
        [FeedDeltaKg], [Description], [CreatedDate]
    FROM [dbo].[FeedInventoryAdjustment]
    WHERE [AdjustmentId] = @AdjustmentId AND [FarmId] = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spFeedInventoryAdjustment_Insert]
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450),
    @AdjustmentDate DATETIME2,
    @AdjustmentType NVARCHAR(50),
    @FeedDeltaKg DECIMAL(18, 4),
    @Description NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [dbo].[FeedInventoryAdjustment] (
        [UserId], [FarmId], [AdjustmentDate], [AdjustmentType], [FeedDeltaKg], [Description]
    )
    VALUES (@UserId, @FarmId, @AdjustmentDate, @AdjustmentType, @FeedDeltaKg, @Description);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spFeedInventoryAdjustment_Update]
    @AdjustmentId INT,
    @FarmId NVARCHAR(450),
    @AdjustmentDate DATETIME2,
    @AdjustmentType NVARCHAR(50),
    @FeedDeltaKg DECIMAL(18, 4),
    @Description NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE [dbo].[FeedInventoryAdjustment]
    SET
        [AdjustmentDate] = @AdjustmentDate,
        [AdjustmentType] = @AdjustmentType,
        [FeedDeltaKg] = @FeedDeltaKg,
        [Description] = @Description
    WHERE [AdjustmentId] = @AdjustmentId AND [FarmId] = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spFeedInventoryAdjustment_Delete]
    @AdjustmentId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM [dbo].[FeedInventoryAdjustment]
    WHERE [AdjustmentId] = @AdjustmentId AND [FarmId] = @FarmId;
END
GO

PRINT N'014_FeedInventoryAdjustment: complete.';
GO
