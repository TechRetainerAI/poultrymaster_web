-- 012_EggInventoryAdjustment.sql — manual egg stock corrections (egg tracker / ledger)
-- Run against your application database (not master). Safe to re-run.

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 50000, N'Select your application database before running this script.', 1;
END
GO

SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.EggInventoryAdjustment', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[EggInventoryAdjustment] (
        [AdjustmentId]   INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
        [UserId]         NVARCHAR(450) NOT NULL,
        [FarmId]         NVARCHAR(450) NOT NULL,
        [AdjustmentDate] DATETIME2 NOT NULL,
        [AdjustmentType] NVARCHAR(50) NOT NULL,
        [EggDelta]       INT NOT NULL,
        [Description]    NVARCHAR(500) NULL,
        [CreatedDate]    DATETIME2 NOT NULL CONSTRAINT [DF_EggInvAdj_Created] DEFAULT (SYSUTCDATETIME())
    );
    CREATE NONCLUSTERED INDEX [IX_EggInvAdj_FarmId] ON [dbo].[EggInventoryAdjustment]([FarmId]);
    CREATE NONCLUSTERED INDEX [IX_EggInvAdj_FarmDate] ON [dbo].[EggInventoryAdjustment]([FarmId], [AdjustmentDate]);
    PRINT N'Created dbo.EggInventoryAdjustment.';
END
ELSE
    PRINT N'dbo.EggInventoryAdjustment already exists.';
GO

CREATE OR ALTER PROCEDURE [dbo].[spEggInventoryAdjustment_GetAll]
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        [AdjustmentId], [UserId], [FarmId], [AdjustmentDate], [AdjustmentType],
        [EggDelta], [Description], [CreatedDate]
    FROM [dbo].[EggInventoryAdjustment]
    WHERE [FarmId] = @FarmId
    ORDER BY [AdjustmentDate] ASC, [AdjustmentId] ASC;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spEggInventoryAdjustment_GetById]
    @AdjustmentId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        [AdjustmentId], [UserId], [FarmId], [AdjustmentDate], [AdjustmentType],
        [EggDelta], [Description], [CreatedDate]
    FROM [dbo].[EggInventoryAdjustment]
    WHERE [AdjustmentId] = @AdjustmentId AND [FarmId] = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spEggInventoryAdjustment_Insert]
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450),
    @AdjustmentDate DATETIME2,
    @AdjustmentType NVARCHAR(50),
    @EggDelta INT,
    @Description NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [dbo].[EggInventoryAdjustment] (
        [UserId], [FarmId], [AdjustmentDate], [AdjustmentType], [EggDelta], [Description]
    )
    VALUES (@UserId, @FarmId, @AdjustmentDate, @AdjustmentType, @EggDelta, @Description);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spEggInventoryAdjustment_Update]
    @AdjustmentId INT,
    @FarmId NVARCHAR(450),
    @AdjustmentDate DATETIME2,
    @AdjustmentType NVARCHAR(50),
    @EggDelta INT,
    @Description NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE [dbo].[EggInventoryAdjustment]
    SET
        [AdjustmentDate] = @AdjustmentDate,
        [AdjustmentType] = @AdjustmentType,
        [EggDelta] = @EggDelta,
        [Description] = @Description
    WHERE [AdjustmentId] = @AdjustmentId AND [FarmId] = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spEggInventoryAdjustment_Delete]
    @AdjustmentId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM [dbo].[EggInventoryAdjustment]
    WHERE [AdjustmentId] = @AdjustmentId AND [FarmId] = @FarmId;
END
GO

PRINT N'012_EggInventoryAdjustment: complete.';
GO
