-- =============================================================================
-- 018_WeeklyReportExtensions.sql
-- Schema additions for the Weekly Poultry Production Report (Phase 3B).
--
-- Adds:
--   #8  dbo.Sale.Size                — egg size sold (Inside / Tee / Serum / etc.)
--   #9  dbo.ProductionRecords.MeatyEggs / SoftEggs / LostEggs — egg loss types
--                                       (BrokenEggs already exists.)
--   #15 dbo.FarmObservations         — free-text weekly notes per farm + week.
--
-- All ADDs are NULL-able with safe defaults — existing rows and existing app
-- code continue to work unchanged. Idempotent: safe to re-run.
-- =============================================================================

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 50000, N'Select your application database (not master). Aborting.', 1;
END
GO

-------------------------------------------------------------------------------
-- (#8) Sale.Size
-------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Sale]') AND type = N'U')
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[Sale]') AND name = N'Size')
    BEGIN
        ALTER TABLE [dbo].[Sale] ADD [Size] NVARCHAR(50) NULL;
        PRINT '018: Added Size column to dbo.Sale';
    END
    ELSE
        PRINT '018: dbo.Sale.Size already exists';
END
ELSE
BEGIN
    RAISERROR(N'018: dbo.Sale not found. Run earlier migrations first.', 16, 1);
END
GO

-- spSale_Insert — add @Size
CREATE OR ALTER PROCEDURE [dbo].[spSale_Insert]
    @UserId NVARCHAR(100),
    @FarmId NVARCHAR(100),
    @SaleDate DATETIME2,
    @Product NVARCHAR(200),
    @Quantity DECIMAL(18,2),
    @UnitPrice DECIMAL(18,2),
    @TotalAmount DECIMAL(18,2),
    @PaymentMethod NVARCHAR(100) = NULL,
    @CustomerName NVARCHAR(200) = NULL,
    @FlockId INT = NULL,
    @SaleDescription NVARCHAR(MAX) = NULL,
    @Paid BIT = 1,
    @Size NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [dbo].[Sale]
    (
        UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount,
        PaymentMethod, CustomerName, FlockId, SaleDescription, Paid, Size, CreatedDate
    )
    VALUES
    (
        @UserId, @FarmId, @SaleDate, @Product, @Quantity, @UnitPrice, @TotalAmount,
        @PaymentMethod, @CustomerName, @FlockId, @SaleDescription, ISNULL(@Paid, 1), @Size, SYSUTCDATETIME()
    );
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSale_Update]
    @UserId NVARCHAR(100),
    @FarmId NVARCHAR(100),
    @SaleId INT,
    @SaleDate DATETIME2,
    @Product NVARCHAR(200),
    @Quantity DECIMAL(18,2),
    @UnitPrice DECIMAL(18,2),
    @TotalAmount DECIMAL(18,2),
    @PaymentMethod NVARCHAR(100) = NULL,
    @CustomerName NVARCHAR(200) = NULL,
    @FlockId INT = NULL,
    @SaleDescription NVARCHAR(MAX) = NULL,
    @Paid BIT = 1,
    @Size NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE [dbo].[Sale]
    SET
        SaleDate = @SaleDate,
        Product = @Product,
        Quantity = @Quantity,
        UnitPrice = @UnitPrice,
        TotalAmount = @TotalAmount,
        PaymentMethod = @PaymentMethod,
        CustomerName = @CustomerName,
        FlockId = @FlockId,
        SaleDescription = @SaleDescription,
        Paid = ISNULL(@Paid, 1),
        Size = @Size
    WHERE SaleId = @SaleId
      AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSale_GetById]
    @SaleId INT,
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        SaleId, UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount,
        PaymentMethod, CustomerName, FlockId, SaleDescription, ISNULL(Paid, 1) AS Paid,
        Size,
        CreatedDate
    FROM [dbo].[Sale]
    WHERE SaleId = @SaleId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSale_GetAll]
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        SaleId, UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount,
        PaymentMethod, CustomerName, FlockId, SaleDescription, ISNULL(Paid, 1) AS Paid,
        Size,
        CreatedDate
    FROM [dbo].[Sale]
    WHERE FarmId = @FarmId
    ORDER BY SaleDate DESC, CreatedDate DESC;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSale_GetByFlock]
    @FlockId INT,
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        SaleId, UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount,
        PaymentMethod, CustomerName, FlockId, SaleDescription, ISNULL(Paid, 1) AS Paid,
        Size,
        CreatedDate
    FROM [dbo].[Sale]
    WHERE FarmId = @FarmId AND FlockId = @FlockId
    ORDER BY SaleDate DESC, CreatedDate DESC;
END
GO

-------------------------------------------------------------------------------
-- (#9) ProductionRecords.MeatyEggs / SoftEggs / LostEggs
-------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ProductionRecords]') AND type = N'U')
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[ProductionRecords]') AND name = N'MeatyEggs')
    BEGIN
        ALTER TABLE [dbo].[ProductionRecords] ADD [MeatyEggs] INT NULL;
        PRINT '018: Added MeatyEggs to ProductionRecords';
    END
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[ProductionRecords]') AND name = N'SoftEggs')
    BEGIN
        ALTER TABLE [dbo].[ProductionRecords] ADD [SoftEggs] INT NULL;
        PRINT '018: Added SoftEggs to ProductionRecords';
    END
    IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[dbo].[ProductionRecords]') AND name = N'LostEggs')
    BEGIN
        ALTER TABLE [dbo].[ProductionRecords] ADD [LostEggs] INT NULL;
        PRINT '018: Added LostEggs to ProductionRecords';
    END
END
ELSE
BEGIN
    RAISERROR(N'018: dbo.ProductionRecords not found. Run earlier migrations first.', 16, 1);
END
GO

-- spProductionRecord_Insert — append MeatyEggs/SoftEggs/LostEggs
CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_Insert]
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
    @EggGrade NVARCHAR(50) = NULL,
    @MeatyEggs INT = NULL,
    @SoftEggs INT = NULL,
    @LostEggs INT = NULL,
    @NewId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @EggCount = ISNULL(@EggCount, @TotalProduction);

    INSERT INTO [dbo].[ProductionRecords] (
        FarmId, CreatedBy, UserId, AgeInWeeks, AgeInDays, [Date],
        NoOfBirds, Mortality, NoOfBirdsLeft, FeedKg, Medication,
        Production9AM, Production12PM, Production4PM, TotalProduction,
        FlockId, BrokenEggs, Notes, EggCount, EggGrade,
        MeatyEggs, SoftEggs, LostEggs,
        CreatedAt
    )
    VALUES (
        @FarmId, @CreatedBy, @UserId, @AgeInWeeks, @AgeInDays, @Date,
        @NoOfBirds, @Mortality, @NoOfBirdsLeft, @FeedKg, @Medication,
        @Production9AM, @Production12PM, @Production4PM, @TotalProduction,
        @FlockId, @BrokenEggs, @Notes, @EggCount, @EggGrade,
        @MeatyEggs, @SoftEggs, @LostEggs,
        GETUTCDATE()
    );

    SET @NewId = SCOPE_IDENTITY();
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_Update]
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
    @EggCount INT = NULL,
    @EggGrade NVARCHAR(50) = NULL,
    @MeatyEggs INT = NULL,
    @SoftEggs INT = NULL,
    @LostEggs INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
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
        EggGrade = @EggGrade,
        MeatyEggs = @MeatyEggs,
        SoftEggs = @SoftEggs,
        LostEggs = @LostEggs,
        UpdatedAt = GETUTCDATE()
    WHERE Id = @RecordId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_GetById]
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
        EggGrade,
        MeatyEggs, SoftEggs, LostEggs,
        CreatedAt, UpdatedAt
    FROM [dbo].[ProductionRecords]
    WHERE Id = @RecordId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spProductionRecord_GetAll]
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
        EggGrade,
        MeatyEggs, SoftEggs, LostEggs,
        CreatedAt, UpdatedAt
    FROM [dbo].[ProductionRecords]
    WHERE FarmId = @FarmId
    ORDER BY [Date] DESC, CreatedAt DESC;
END
GO

-------------------------------------------------------------------------------
-- (#15) dbo.FarmObservations (new table + procs)
-------------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[FarmObservations]') AND type = N'U')
BEGIN
    CREATE TABLE [dbo].[FarmObservations] (
        [Id]             INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [FarmId]         NVARCHAR(450) NOT NULL,
        [UserId]         NVARCHAR(450) NULL,
        [WeekStartDate]  DATE NOT NULL,
        [Notes]          NVARCHAR(MAX) NULL,
        [CreatedAt]      DATETIME2 NOT NULL CONSTRAINT [DF_FarmObservations_CreatedAt] DEFAULT(SYSUTCDATETIME()),
        [UpdatedAt]      DATETIME2 NULL,
        CONSTRAINT [UX_FarmObservations_FarmWeek] UNIQUE ([FarmId], [WeekStartDate])
    );
    PRINT '018: Created dbo.FarmObservations';
END
ELSE
    PRINT '018: dbo.FarmObservations already exists';
GO

CREATE OR ALTER PROCEDURE [dbo].[spFarmObservation_Upsert]
    @FarmId NVARCHAR(450),
    @UserId NVARCHAR(450) = NULL,
    @WeekStartDate DATE,
    @Notes NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM dbo.FarmObservations WHERE FarmId = @FarmId AND WeekStartDate = @WeekStartDate)
    BEGIN
        UPDATE dbo.FarmObservations
        SET Notes = @Notes,
            UserId = COALESCE(@UserId, UserId),
            UpdatedAt = SYSUTCDATETIME()
        WHERE FarmId = @FarmId AND WeekStartDate = @WeekStartDate;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.FarmObservations (FarmId, UserId, WeekStartDate, Notes)
        VALUES (@FarmId, @UserId, @WeekStartDate, @Notes);
    END

    SELECT Id, FarmId, UserId, WeekStartDate, Notes, CreatedAt, UpdatedAt
    FROM dbo.FarmObservations
    WHERE FarmId = @FarmId AND WeekStartDate = @WeekStartDate;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spFarmObservation_GetByWeek]
    @FarmId NVARCHAR(450),
    @WeekStartDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, FarmId, UserId, WeekStartDate, Notes, CreatedAt, UpdatedAt
    FROM dbo.FarmObservations
    WHERE FarmId = @FarmId AND WeekStartDate = @WeekStartDate;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spFarmObservation_GetAll]
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT Id, FarmId, UserId, WeekStartDate, Notes, CreatedAt, UpdatedAt
    FROM dbo.FarmObservations
    WHERE FarmId = @FarmId
    ORDER BY WeekStartDate DESC;
END
GO

PRINT '018_WeeklyReportExtensions: complete.';
GO
