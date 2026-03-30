

-- Step 0: Create FeedUsage table if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[FeedUsage]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[FeedUsage] (
        [FeedUsageId] INT IDENTITY(1,1) PRIMARY KEY,
        [FlockId] INT NOT NULL,
        [UsageDate] DATE NOT NULL,
        [FeedType] NVARCHAR(100) NOT NULL DEFAULT 'General Feed',
        [QuantityKg] DECIMAL(18,2) NOT NULL DEFAULT 0,
        [UserId] NVARCHAR(100) NULL,
        [FarmId] NVARCHAR(100) NOT NULL,
        [SourceProductionRecordId] INT NULL
    );
    PRINT 'Created FeedUsage table';
    
    -- Create indexes
    CREATE INDEX IX_FeedUsage_FarmId ON [dbo].[FeedUsage] ([FarmId]);
    CREATE INDEX IX_FeedUsage_FlockId ON [dbo].[FeedUsage] ([FlockId]);
    CREATE INDEX IX_FeedUsage_UsageDate ON [dbo].[FeedUsage] ([UsageDate]);
    PRINT 'Created indexes on FeedUsage table';
END
ELSE
BEGIN
    PRINT 'FeedUsage table already exists';
    
    -- Step 1: Add a column to track if FeedUsage came from ProductionRecord
    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[FeedUsage]') AND name = 'SourceProductionRecordId')
    BEGIN
        ALTER TABLE [dbo].[FeedUsage] ADD [SourceProductionRecordId] INT NULL;
        PRINT 'Added SourceProductionRecordId column to FeedUsage table';
    END
    ELSE
    BEGIN
        PRINT 'SourceProductionRecordId column already exists';
    END
END
GO

-- Step 2: Create a trigger to sync FeedUsage when ProductionRecord is inserted
IF OBJECT_ID('trg_ProductionRecord_InsertFeedUsage', 'TR') IS NOT NULL
    DROP TRIGGER trg_ProductionRecord_InsertFeedUsage;
GO

CREATE TRIGGER [dbo].[trg_ProductionRecord_InsertFeedUsage]
ON [dbo].[ProductionRecords]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Insert FeedUsage record for each new ProductionRecord with FeedKg > 0
    INSERT INTO [dbo].[FeedUsage] (
        FlockId, UsageDate, FeedType, QuantityKg, UserId, FarmId, SourceProductionRecordId
    )
    SELECT 
        ISNULL(i.FlockId, 0),
        i.[Date],
        'General Feed',  -- Default feed type from production records
        i.FeedKg,
        i.UserId,
        i.FarmId,
        i.Id
    FROM inserted i
    WHERE i.FeedKg > 0 AND i.FlockId IS NOT NULL;
    
    -- Log the sync
    IF @@ROWCOUNT > 0
    BEGIN
        PRINT 'FeedUsage record(s) created from ProductionRecord insert';
    END
END
GO

PRINT 'Created trigger trg_ProductionRecord_InsertFeedUsage';
GO

-- Step 3: Create a trigger to sync FeedUsage when ProductionRecord is updated
IF OBJECT_ID('trg_ProductionRecord_UpdateFeedUsage', 'TR') IS NOT NULL
    DROP TRIGGER trg_ProductionRecord_UpdateFeedUsage;
GO

CREATE TRIGGER [dbo].[trg_ProductionRecord_UpdateFeedUsage]
ON [dbo].[ProductionRecords]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Update existing FeedUsage records that came from this ProductionRecord
    UPDATE fu
    SET 
        fu.UsageDate = i.[Date],
        fu.QuantityKg = i.FeedKg,
        fu.FlockId = ISNULL(i.FlockId, fu.FlockId)
    FROM [dbo].[FeedUsage] fu
    INNER JOIN inserted i ON fu.SourceProductionRecordId = i.Id
    WHERE i.FeedKg > 0;
    
    -- Delete FeedUsage if FeedKg is now 0
    DELETE fu
    FROM [dbo].[FeedUsage] fu
    INNER JOIN inserted i ON fu.SourceProductionRecordId = i.Id
    WHERE i.FeedKg = 0;
    
    -- Insert new FeedUsage if FeedKg changed from 0 to > 0
    INSERT INTO [dbo].[FeedUsage] (
        FlockId, UsageDate, FeedType, QuantityKg, UserId, FarmId, SourceProductionRecordId
    )
    SELECT 
        ISNULL(i.FlockId, 0),
        i.[Date],
        'General Feed',
        i.FeedKg,
        i.UserId,
        i.FarmId,
        i.Id
    FROM inserted i
    LEFT JOIN [dbo].[FeedUsage] fu ON fu.SourceProductionRecordId = i.Id
    WHERE i.FeedKg > 0 AND fu.FeedUsageId IS NULL AND i.FlockId IS NOT NULL;
END
GO

PRINT 'Created trigger trg_ProductionRecord_UpdateFeedUsage';
GO

-- Step 4: Create a trigger to delete FeedUsage when ProductionRecord is deleted
IF OBJECT_ID('trg_ProductionRecord_DeleteFeedUsage', 'TR') IS NOT NULL
    DROP TRIGGER trg_ProductionRecord_DeleteFeedUsage;
GO

CREATE TRIGGER [dbo].[trg_ProductionRecord_DeleteFeedUsage]
ON [dbo].[ProductionRecords]
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Delete associated FeedUsage records
    DELETE fu
    FROM [dbo].[FeedUsage] fu
    INNER JOIN deleted d ON fu.SourceProductionRecordId = d.Id;
END
GO

PRINT 'Created trigger trg_ProductionRecord_DeleteFeedUsage';
GO

-- Step 5: Migrate existing ProductionRecord feed data to FeedUsage
-- (Only records that don't already have a linked FeedUsage)
PRINT 'Migrating existing ProductionRecord feed data to FeedUsage...';

INSERT INTO [dbo].[FeedUsage] (
    FlockId, UsageDate, FeedType, QuantityKg, UserId, FarmId, SourceProductionRecordId
)
SELECT 
    ISNULL(pr.FlockId, 0),
    pr.[Date],
    'General Feed',
    pr.FeedKg,
    ISNULL(pr.UserId, pr.CreatedBy),
    pr.FarmId,
    pr.Id
FROM [dbo].[ProductionRecords] pr
WHERE pr.FeedKg > 0 
AND pr.FlockId IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM [dbo].[FeedUsage] fu 
    WHERE fu.SourceProductionRecordId = pr.Id
);

PRINT 'Migrated ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' existing ProductionRecord feed entries to FeedUsage.';
GO

-- Step 6: Update spFeedUsage_GetAll to include source info
IF OBJECT_ID('spFeedUsage_GetAll', 'P') IS NOT NULL
    DROP PROCEDURE spFeedUsage_GetAll;
GO

CREATE PROCEDURE [dbo].[spFeedUsage_GetAll]
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        FeedUsageId,
        FlockId,
        UsageDate,
        FeedType,
        QuantityKg,
        UserId,
        FarmId,
        CASE 
            WHEN SourceProductionRecordId IS NOT NULL THEN 'Production Record'
            ELSE 'Manual Entry'
        END AS Source,
        SourceProductionRecordId
    FROM [dbo].[FeedUsage]
    WHERE FarmId = @FarmId
    ORDER BY UsageDate DESC;
END
GO

PRINT 'Updated spFeedUsage_GetAll to include source information';
GO

-- Step 7: Update spFeedUsage_GetById
IF OBJECT_ID('spFeedUsage_GetById', 'P') IS NOT NULL
    DROP PROCEDURE spFeedUsage_GetById;
GO

CREATE PROCEDURE [dbo].[spFeedUsage_GetById]
    @FeedUsageId INT,
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        FeedUsageId,
        FlockId,
        UsageDate,
        FeedType,
        QuantityKg,
        UserId,
        FarmId,
        CASE 
            WHEN SourceProductionRecordId IS NOT NULL THEN 'Production Record'
            ELSE 'Manual Entry'
        END AS Source,
        SourceProductionRecordId
    FROM [dbo].[FeedUsage]
    WHERE FeedUsageId = @FeedUsageId AND FarmId = @FarmId;
END
GO

PRINT 'Updated spFeedUsage_GetById';
GO

-- Step 8: Create spFeedUsage_Insert if it doesn't exist
IF OBJECT_ID('spFeedUsage_Insert', 'P') IS NOT NULL
    DROP PROCEDURE spFeedUsage_Insert;
GO

CREATE PROCEDURE [dbo].[spFeedUsage_Insert]
    @UserId NVARCHAR(100),
    @FarmId NVARCHAR(100),
    @FlockId INT,
    @UsageDate DATE,
    @FeedType NVARCHAR(100),
    @QuantityKg DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO [dbo].[FeedUsage] (FlockId, UsageDate, FeedType, QuantityKg, UserId, FarmId)
    VALUES (@FlockId, @UsageDate, @FeedType, @QuantityKg, @UserId, @FarmId);
    
    SELECT SCOPE_IDENTITY();
END
GO

PRINT 'Created spFeedUsage_Insert';
GO

-- Step 9: Create spFeedUsage_Update if it doesn't exist
IF OBJECT_ID('spFeedUsage_Update', 'P') IS NOT NULL
    DROP PROCEDURE spFeedUsage_Update;
GO

CREATE PROCEDURE [dbo].[spFeedUsage_Update]
    @FeedUsageId INT,
    @UserId NVARCHAR(100),
    @FarmId NVARCHAR(100),
    @FlockId INT,
    @UsageDate DATE,
    @FeedType NVARCHAR(100),
    @QuantityKg DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;
    
    UPDATE [dbo].[FeedUsage]
    SET 
        FlockId = @FlockId,
        UsageDate = @UsageDate,
        FeedType = @FeedType,
        QuantityKg = @QuantityKg,
        UserId = @UserId
    WHERE FeedUsageId = @FeedUsageId AND FarmId = @FarmId;
END
GO

PRINT 'Created spFeedUsage_Update';
GO

-- Step 10: Create spFeedUsage_Delete if it doesn't exist
IF OBJECT_ID('spFeedUsage_Delete', 'P') IS NOT NULL
    DROP PROCEDURE spFeedUsage_Delete;
GO

CREATE PROCEDURE [dbo].[spFeedUsage_Delete]
    @FeedUsageId INT,
    @UserId NVARCHAR(100),
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    
    DELETE FROM [dbo].[FeedUsage]
    WHERE FeedUsageId = @FeedUsageId AND FarmId = @FarmId;
END
GO

PRINT 'Created spFeedUsage_Delete';
GO

PRINT '';
PRINT '=============================================================';
PRINT 'MIGRATION 002 COMPLETED SUCCESSFULLY!';
PRINT '=============================================================';
PRINT 'Feed Usage table is now automatically synced with Production Records.';
PRINT 'When you enter FeedKg in Production Records, it will automatically';
PRINT 'appear in the Feed Usage page as "General Feed".';
PRINT '=============================================================';
GO

