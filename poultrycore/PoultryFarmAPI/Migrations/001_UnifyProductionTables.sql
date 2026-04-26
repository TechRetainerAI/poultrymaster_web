

-- Step 0: Create ProductionRecord table if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionRecords]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[ProductionRecords] (
        [Id] INT IDENTITY(1,1) PRIMARY KEY,
        [FarmId] NVARCHAR(100) NOT NULL,
        [UserId] NVARCHAR(100) NULL,
        [CreatedBy] NVARCHAR(100) NOT NULL,
        [UpdatedBy] NVARCHAR(100) NULL,
        [AgeInWeeks] INT NOT NULL DEFAULT 0,
        [AgeInDays] INT NOT NULL DEFAULT 0,
        [Date] DATE NOT NULL,
        [NoOfBirds] INT NOT NULL DEFAULT 0,
        [Mortality] INT NOT NULL DEFAULT 0,
        [NoOfBirdsLeft] INT NOT NULL DEFAULT 0,
        [FeedKg] DECIMAL(18,2) NOT NULL DEFAULT 0,
        [Medication] NVARCHAR(500) NULL,
        [Production9AM] INT NOT NULL DEFAULT 0,
        [Production12PM] INT NOT NULL DEFAULT 0,
        [Production4PM] INT NOT NULL DEFAULT 0,
        [TotalProduction] INT NOT NULL DEFAULT 0,
        [FlockId] INT NULL,
        [BrokenEggs] INT NULL,
        [Notes] NVARCHAR(MAX) NULL,
        [EggCount] INT NULL DEFAULT 0,
        [CreatedAt] DATETIME NOT NULL DEFAULT GETUTCDATE(),
        [UpdatedAt] DATETIME NULL
    );
    PRINT 'Created ProductionRecord table';
    
    -- Create index on FarmId for faster queries
    CREATE INDEX IX_ProductionRecords_FarmId ON [dbo].[ProductionRecords] ([FarmId]);
    CREATE INDEX IX_ProductionRecords_Date ON [dbo].[ProductionRecords] ([Date]);
    CREATE INDEX IX_ProductionRecords_FlockId ON [dbo].[ProductionRecords] ([FlockId]) WHERE [FlockId] IS NOT NULL;
    PRINT 'Created indexes on ProductionRecord table';
END
ELSE
BEGIN
    PRINT 'ProductionRecord table already exists';
END
GO

-- Step 1: Add BrokenEggs and Notes columns to ProductionRecord if they don't exist
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionRecords]') AND type in (N'U'))
BEGIN
    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[ProductionRecords]') AND name = 'BrokenEggs')
    BEGIN
        ALTER TABLE [dbo].[ProductionRecords] ADD [BrokenEggs] INT NULL;
        PRINT 'Added BrokenEggs column to ProductionRecord table';
    END
    ELSE
    BEGIN
        PRINT 'BrokenEggs column already exists';
    END
END
GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionRecords]') AND type in (N'U'))
BEGIN
    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[ProductionRecords]') AND name = 'Notes')
    BEGIN
        ALTER TABLE [dbo].[ProductionRecords] ADD [Notes] NVARCHAR(MAX) NULL;
        PRINT 'Added Notes column to ProductionRecord table';
    END
    ELSE
    BEGIN
        PRINT 'Notes column already exists';
    END
END
GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionRecords]') AND type in (N'U'))
BEGIN
    IF NOT EXISTS (SELECT * FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[ProductionRecords]') AND name = 'EggCount')
    BEGIN
        ALTER TABLE [dbo].[ProductionRecords] ADD [EggCount] INT NULL DEFAULT 0;
        PRINT 'Added EggCount column to ProductionRecord table';
    END
    ELSE
    BEGIN
        PRINT 'EggCount column already exists';
    END
END
GO

-- Step 2: Update spProductionRecord_Insert to include new columns
IF OBJECT_ID('spProductionRecord_Insert', 'P') IS NOT NULL
    DROP PROCEDURE spProductionRecord_Insert;
GO

CREATE PROCEDURE [dbo].[spProductionRecord_Insert]
    @FarmId NVARCHAR(100),
    @CreatedBy NVARCHAR(100),
    @UserId NVARCHAR(100),
    @AgeInWeeks INT,
    @AgeInDays INT,
    @Date DATE,
    @NoOfBirds INT,
    @Mortality INT,
    @NoOfBirdsLeft INT,
    @FeedKg DECIMAL(18,2),
    @Medication NVARCHAR(500) = NULL,
    @Production9AM INT,
    @Production12PM INT,
    @Production4PM INT,
    @TotalProduction INT,
    @FlockId INT = NULL,
    @BrokenEggs INT = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @EggCount INT = NULL,
    @NewId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Calculate EggCount if not provided (use TotalProduction)
    SET @EggCount = ISNULL(@EggCount, @TotalProduction);
    
    INSERT INTO [dbo].[ProductionRecords] (
        FarmId, CreatedBy, UserId, AgeInWeeks, AgeInDays, [Date],
        NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication,
        Production9AM, Production12PM, Production4PM, TotalProduction,
        FlockId, BrokenEggs, Notes, EggCount, CreatedAt
    )
    VALUES (
        @FarmId, @CreatedBy, @UserId, @AgeInWeeks, @AgeInDays, @Date,
        @NoOfBirds, @Mortality, @NoOfBirdsLeft, @FeedKg, @Medication,
        @Production9AM, @Production12PM, @Production4PM, @TotalProduction,
        @FlockId, @BrokenEggs, @Notes, @EggCount, GETUTCDATE()
    );
    
    SET @NewId = SCOPE_IDENTITY();
END
GO

PRINT 'Created/Updated spProductionRecord_Insert';
GO

-- Step 3: Update spProductionRecord_Update to include new columns
IF OBJECT_ID('spProductionRecord_Update', 'P') IS NOT NULL
    DROP PROCEDURE spProductionRecord_Update;
GO

CREATE PROCEDURE [dbo].[spProductionRecord_Update]
    @RecordId INT,
    @UpdatedBy NVARCHAR(100),
    @AgeInWeeks INT,
    @AgeInDays INT,
    @Date DATE,
    @NoOfBirds INT,
    @Mortality INT,
    @NoOfBirdsLeft INT,
    @FeedKg DECIMAL(18,2),
    @Medication NVARCHAR(500) = NULL,
    @Production9AM INT,
    @Production12PM INT,
    @Production4PM INT,
    @TotalProduction INT,
    @FlockId INT = NULL,
    @BrokenEggs INT = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @EggCount INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Calculate EggCount if not provided
    SET @EggCount = ISNULL(@EggCount, @TotalProduction);
    
    UPDATE [dbo].[ProductionRecords]
    SET 
        UpdatedBy = @UpdatedBy,
        AgeInWeeks = @AgeInWeeks,
        AgeInDays = @AgeInDays,
        [Date] = @Date,
        NoOfBirds = @NoOfBirds,
        Mortality = @Mortality,
        NoOfBirdsLeft = @NoOfBirdsLeft,
        FeedKg = @FeedKg,
        Medication = @Medication,
        Production9AM = @Production9AM,
        Production12PM = @Production12PM,
        Production4PM = @Production4PM,
        TotalProduction = @TotalProduction,
        FlockId = @FlockId,
        BrokenEggs = @BrokenEggs,
        Notes = @Notes,
        EggCount = @EggCount,
        UpdatedAt = GETUTCDATE()
    WHERE Id = @RecordId;
END
GO

PRINT 'Created/Updated spProductionRecord_Update';
GO

-- Step 4: Update spProductionRecord_GetById to include new columns
IF OBJECT_ID('spProductionRecord_GetById', 'P') IS NOT NULL
    DROP PROCEDURE spProductionRecord_GetById;
GO

CREATE PROCEDURE [dbo].[spProductionRecord_GetById]
    @RecordId INT,
    @UserId NVARCHAR(100),
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        Id, FarmId, UserId, CreatedBy, UpdatedBy,
        AgeInWeeks, AgeInDays, [Date],
        NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication,
        Production9AM, Production12PM, Production4PM, TotalProduction,
        FlockId, BrokenEggs, Notes, ISNULL(EggCount, TotalProduction) AS EggCount,
        CreatedAt, UpdatedAt
    FROM [dbo].[ProductionRecords]
    WHERE Id = @RecordId AND FarmId = @FarmId;
END
GO

PRINT 'Created/Updated spProductionRecord_GetById';
GO

-- Step 5: Update spProductionRecord_GetAll to include new columns
IF OBJECT_ID('spProductionRecord_GetAll', 'P') IS NOT NULL
    DROP PROCEDURE spProductionRecord_GetAll;
GO

CREATE PROCEDURE [dbo].[spProductionRecord_GetAll]
    @UserId NVARCHAR(100),
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        Id, FarmId, UserId, CreatedBy, UpdatedBy,
        AgeInWeeks, AgeInDays, [Date],
        NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication,
        Production9AM, Production12PM, Production4PM, TotalProduction,
        FlockId, BrokenEggs, Notes, ISNULL(EggCount, TotalProduction) AS EggCount,
        CreatedAt, UpdatedAt
    FROM [dbo].[ProductionRecords]
    WHERE FarmId = @FarmId
    ORDER BY [Date] DESC, CreatedAt DESC;
END
GO

PRINT 'Created/Updated spProductionRecord_GetAll';
GO

-- Step 6: Update spProductionRecord_Delete (if needed)
IF OBJECT_ID('spProductionRecord_Delete', 'P') IS NOT NULL
    DROP PROCEDURE spProductionRecord_Delete;
GO

CREATE PROCEDURE [dbo].[spProductionRecord_Delete]
    @RecordId INT,
    @UserId NVARCHAR(100),
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    
    DELETE FROM [dbo].[ProductionRecords]
    WHERE Id = @RecordId AND FarmId = @FarmId;
END
GO

PRINT 'Created/Updated spProductionRecord_Delete';
GO

-- =============================================================
-- Step 7: Update EggProduction stored procedures to use ProductionRecord table
-- This allows the EggProduction page to read/write from the same table
-- =============================================================

IF OBJECT_ID('spEggProduction_Insert', 'P') IS NOT NULL
    DROP PROCEDURE spEggProduction_Insert;
GO

CREATE PROCEDURE [dbo].[spEggProduction_Insert]
    @FlockId INT,
    @ProductionDate DATE,
    @EggCount INT,
    @Production9AM INT = 0,
    @Production12PM INT = 0,
    @Production4PM INT = 0,
    @BrokenEggs INT = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @UserId NVARCHAR(100) = NULL,
    @FarmId NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TotalProduction INT = @Production9AM + @Production12PM + @Production4PM;
    
    -- If no time-based breakdown provided, put all eggs in Production9AM
    IF @TotalProduction = 0 AND @EggCount > 0
    BEGIN
        SET @Production9AM = @EggCount;
        SET @TotalProduction = @EggCount;
    END
    
    -- Insert into ProductionRecord table (the unified table)
    INSERT INTO [dbo].[ProductionRecords] (
        FarmId, CreatedBy, UserId, 
        AgeInWeeks, AgeInDays, [Date],
        NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication,
        Production9AM, Production12PM, Production4PM, TotalProduction,
        FlockId, BrokenEggs, Notes, EggCount, CreatedAt
    )
    VALUES (
        @FarmId, @UserId, @UserId,
        0, 0, @ProductionDate,  -- Default age values
        0, 0, 0, 0, NULL,       -- Default bird/feed values
        @Production9AM, @Production12PM, @Production4PM, @TotalProduction,
        @FlockId, @BrokenEggs, @Notes, @EggCount, GETUTCDATE()
    );
    
    SELECT SCOPE_IDENTITY();
END
GO

PRINT 'Created/Updated spEggProduction_Insert (now uses ProductionRecord table)';
GO

IF OBJECT_ID('spEggProduction_Update', 'P') IS NOT NULL
    DROP PROCEDURE spEggProduction_Update;
GO

CREATE PROCEDURE [dbo].[spEggProduction_Update]
    @ProductionId INT,
    @FlockId INT,
    @ProductionDate DATE,
    @EggCount INT,
    @Production9AM INT = 0,
    @Production12PM INT = 0,
    @Production4PM INT = 0,
    @BrokenEggs INT = NULL,
    @Notes NVARCHAR(MAX) = NULL,
    @UserId NVARCHAR(100) = NULL,
    @FarmId NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @TotalProduction INT = @Production9AM + @Production12PM + @Production4PM;
    
    -- If no time-based breakdown, put all eggs in Production9AM
    IF @TotalProduction = 0 AND @EggCount > 0
    BEGIN
        SET @Production9AM = @EggCount;
        SET @TotalProduction = @EggCount;
    END
    
    UPDATE [dbo].[ProductionRecords]
    SET 
        FlockId = @FlockId,
        [Date] = @ProductionDate,
        EggCount = @EggCount,
        Production9AM = @Production9AM,
        Production12PM = @Production12PM,
        Production4PM = @Production4PM,
        TotalProduction = @TotalProduction,
        BrokenEggs = @BrokenEggs,
        Notes = @Notes,
        UpdatedBy = @UserId,
        UpdatedAt = GETUTCDATE()
    WHERE Id = @ProductionId AND FarmId = @FarmId;
END
GO

PRINT 'Created/Updated spEggProduction_Update (now uses ProductionRecord table)';
GO

IF OBJECT_ID('spEggProduction_GetById', 'P') IS NOT NULL
    DROP PROCEDURE spEggProduction_GetById;
GO

CREATE PROCEDURE [dbo].[spEggProduction_GetById]
    @ProductionId INT,
    @UserId NVARCHAR(100),
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        Id AS ProductionId,
        ISNULL(FlockId, 0) AS FlockId,
        [Date] AS ProductionDate,
        ISNULL(EggCount, TotalProduction) AS EggCount,
        Production9AM,
        Production12PM,
        Production4PM,
        BrokenEggs,
        Notes,
        ISNULL(UserId, CreatedBy) AS UserId,
        FarmId
    FROM [dbo].[ProductionRecords]
    WHERE Id = @ProductionId AND FarmId = @FarmId;
END
GO

PRINT 'Created/Updated spEggProduction_GetById (now uses ProductionRecord table)';
GO

IF OBJECT_ID('spEggProduction_GetAll', 'P') IS NOT NULL
    DROP PROCEDURE spEggProduction_GetAll;
GO

CREATE PROCEDURE [dbo].[spEggProduction_GetAll]
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        Id AS ProductionId,
        ISNULL(FlockId, 0) AS FlockId,
        [Date] AS ProductionDate,
        ISNULL(EggCount, TotalProduction) AS EggCount,
        Production9AM,
        Production12PM,
        Production4PM,
        BrokenEggs,
        Notes,
        ISNULL(UserId, CreatedBy) AS UserId,
        FarmId
    FROM [dbo].[ProductionRecords]
    WHERE FarmId = @FarmId
    ORDER BY [Date] DESC, CreatedAt DESC;
END
GO

PRINT 'Created/Updated spEggProduction_GetAll (now uses ProductionRecord table)';
GO

IF OBJECT_ID('spEggProduction_GetByFlock', 'P') IS NOT NULL
    DROP PROCEDURE spEggProduction_GetByFlock;
GO

CREATE PROCEDURE [dbo].[spEggProduction_GetByFlock]
    @FlockId INT,
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        Id AS ProductionId,
        ISNULL(FlockId, 0) AS FlockId,
        [Date] AS ProductionDate,
        ISNULL(EggCount, TotalProduction) AS EggCount,
        Production9AM,
        Production12PM,
        Production4PM,
        BrokenEggs,
        Notes,
        ISNULL(UserId, CreatedBy) AS UserId,
        FarmId
    FROM [dbo].[ProductionRecords]
    WHERE FlockId = @FlockId AND FarmId = @FarmId
    ORDER BY [Date] DESC;
END
GO

PRINT 'Created/Updated spEggProduction_GetByFlock (now uses ProductionRecord table)';
GO

IF OBJECT_ID('spEggProduction_Delete', 'P') IS NOT NULL
    DROP PROCEDURE spEggProduction_Delete;
GO

CREATE PROCEDURE [dbo].[spEggProduction_Delete]
    @ProductionId INT,
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    
    DELETE FROM [dbo].[ProductionRecords]
    WHERE Id = @ProductionId AND FarmId = @FarmId;
END
GO

PRINT 'Created/Updated spEggProduction_Delete (now uses ProductionRecord table)';
GO

-- =============================================================
-- Step 8: Migrate existing EggProduction data to ProductionRecord
-- (Only if EggProduction table exists and has data)
-- =============================================================
IF OBJECT_ID('dbo.EggProduction', 'U') IS NOT NULL
BEGIN
    PRINT 'Migrating existing EggProduction data to ProductionRecord table...';
    
    -- Check if there's data to migrate
    DECLARE @EggProductionCount INT;
    SELECT @EggProductionCount = COUNT(*) FROM [dbo].[EggProduction];
    
    IF @EggProductionCount > 0
    BEGIN
        -- Insert EggProduction records that don't already exist in ProductionRecord
        INSERT INTO [dbo].[ProductionRecords] (
            FarmId, CreatedBy, UserId, 
            AgeInWeeks, AgeInDays, [Date],
            NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication,
            Production9AM, Production12PM, Production4PM, TotalProduction,
            FlockId, BrokenEggs, Notes, EggCount, CreatedAt
        )
        SELECT 
            ep.FarmId, 
            ISNULL(ep.UserId, 'system'), 
            ISNULL(ep.UserId, 'system'),
            0, 0, ep.ProductionDate,
            0, 0, 0, 0, NULL,
            ISNULL(ep.Production9AM, 0), 
            ISNULL(ep.Production12PM, 0), 
            ISNULL(ep.Production4PM, 0),
            ISNULL(ep.Production9AM, 0) + ISNULL(ep.Production12PM, 0) + ISNULL(ep.Production4PM, 0),
            ep.FlockId, 
            ep.BrokenEggs, 
            ep.Notes, 
            ep.EggCount,
            GETUTCDATE()
        FROM [dbo].[EggProduction] ep
        WHERE NOT EXISTS (
            SELECT 1 FROM [dbo].[ProductionRecords] pr 
            WHERE pr.FarmId = ep.FarmId 
            AND pr.[Date] = ep.ProductionDate 
            AND pr.FlockId = ep.FlockId
            AND pr.TotalProduction = (ISNULL(ep.Production9AM, 0) + ISNULL(ep.Production12PM, 0) + ISNULL(ep.Production4PM, 0))
        );
        
        PRINT 'Migration completed. Migrated ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' records.';
    END
    ELSE
    BEGIN
        PRINT 'No data to migrate from EggProduction table.';
    END
END
ELSE
BEGIN
    PRINT 'EggProduction table does not exist. No migration needed.';
END
GO

PRINT '';
PRINT '=============================================================';
PRINT 'MIGRATION 001 COMPLETED SUCCESSFULLY!';
PRINT '=============================================================';
PRINT 'Both Production Records page and Egg Production page now';
PRINT 'use the same ProductionRecord table as the data source.';
PRINT '=============================================================';
GO

