-- =============================================
-- Fix HouseId support in Flock stored procedures
-- Database: poultry2_Prod
-- =============================================
-- This script ensures HouseId is properly saved and retrieved
-- for Flock records through all CRUD stored procedures.
-- =============================================

USE [poultry2_Prod];
GO

PRINT '========================================';
PRINT 'Fixing HouseId in Flock Stored Procedures';
PRINT '========================================';
GO

-- =============================================
-- Step 1: Update spFlock_Insert to accept @HouseId
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[spFlock_Insert]') AND type in (N'P', N'PC'))
    DROP PROCEDURE [dbo].[spFlock_Insert];
GO

CREATE PROCEDURE [dbo].[spFlock_Insert]
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450),
    @Name NVARCHAR(255),
    @Breed NVARCHAR(100),
    @StartDate DATETIME2,
    @Quantity INT,
    @BatchId INT,
    @HouseId INT = NULL,
    @InactivationReason NVARCHAR(255) = NULL,
    @OtherReason NVARCHAR(500) = NULL,
    @Notes NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Validate Quantity > 0
    IF @Quantity <= 0
    BEGIN
        RAISERROR('Quantity must be greater than zero', 16, 1);
        RETURN;
    END
    
    -- Validate BatchId is provided
    IF @BatchId IS NULL OR @BatchId = 0
    BEGIN
        RAISERROR('BatchId is required', 16, 1);
        RETURN;
    END
    
    -- Insert the flock with HouseId support
    INSERT INTO [dbo].[Flock] 
        ([UserId], [FarmId], [Name], [Breed], [StartDate], [Quantity], [Active], [HouseId], [BatchId], [InactivationReason], [OtherReason], [Notes])
    VALUES 
        (@UserId, @FarmId, @Name, @Breed, @StartDate, @Quantity, 1, @HouseId, @BatchId, @InactivationReason, @OtherReason, @Notes);
    
    -- Return the newly created FlockId
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS FlockId;
END
GO

PRINT 'spFlock_Insert updated - now accepts @HouseId parameter';
GO

-- =============================================
-- Step 2: Update spFlock_Update to accept @HouseId
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[spFlock_Update]') AND type in (N'P', N'PC'))
    DROP PROCEDURE [dbo].[spFlock_Update];
GO

CREATE PROCEDURE [dbo].[spFlock_Update]
    @FlockId INT,
    @Name NVARCHAR(255),
    @Breed NVARCHAR(100),
    @StartDate DATETIME2,
    @Quantity INT,
    @Active BIT,
    @HouseId INT = NULL,
    @InactivationReason NVARCHAR(255) = NULL,
    @OtherReason NVARCHAR(500) = NULL,
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450),
    @BatchId INT = NULL,
    @Notes NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    UPDATE [dbo].[Flock]
    SET 
        [Name] = @Name,
        [Breed] = @Breed,
        [StartDate] = @StartDate,
        [Quantity] = @Quantity,
        [Active] = @Active,
        [HouseId] = @HouseId,
        [InactivationReason] = @InactivationReason,
        [OtherReason] = @OtherReason,
        [BatchId] = @BatchId,
        [Notes] = @Notes
    WHERE [FlockId] = @FlockId 
      AND [FarmId] = @FarmId;
END
GO

PRINT 'spFlock_Update updated - now accepts @HouseId parameter';
GO

-- =============================================
-- Step 3: Ensure spFlock_GetById returns HouseId
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[spFlock_GetById]') AND type in (N'P', N'PC'))
    DROP PROCEDURE [dbo].[spFlock_GetById];
GO

CREATE PROCEDURE [dbo].[spFlock_GetById]
    @FlockId INT,
    @FarmId NVARCHAR(450)
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
        b.[BatchName]
    FROM [dbo].[Flock] f
    LEFT JOIN [dbo].[MainFlockBatch] b ON f.[BatchId] = b.[BatchId] AND f.[FarmId] = b.[FarmId]
    WHERE f.[FlockId] = @FlockId 
      AND f.[FarmId] = @FarmId;
END
GO

PRINT 'spFlock_GetById updated - now returns HouseId';
GO

-- =============================================
-- Step 4: Ensure spFlock_GetAll returns HouseId (should already be fine)
-- =============================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[spFlock_GetAll]') AND type in (N'P', N'PC'))
    DROP PROCEDURE [dbo].[spFlock_GetAll];
GO

CREATE PROCEDURE [dbo].[spFlock_GetAll]
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
        b.[BatchName]
    FROM [dbo].[Flock] f
    LEFT JOIN [dbo].[MainFlockBatch] b ON f.[BatchId] = b.[BatchId] AND f.[FarmId] = b.[FarmId]
    WHERE f.[FarmId] = @FarmId
    ORDER BY f.[StartDate] DESC;
END
GO

PRINT 'spFlock_GetAll verified - returns HouseId';
GO

PRINT '';
PRINT '========================================';
PRINT 'HouseId Fix Complete!';
PRINT '========================================';
PRINT '';
PRINT 'What was fixed:';
PRINT '  1. spFlock_Insert now accepts @HouseId parameter';
PRINT '  2. spFlock_Update now accepts @HouseId parameter';
PRINT '  3. spFlock_GetById now returns HouseId column';
PRINT '  4. spFlock_GetAll verified to return HouseId column';
PRINT '';
PRINT 'The C# BirdFlockService.cs has also been updated to:';
PRINT '  - Pass @HouseId when creating and updating flocks';
PRINT '  - Read HouseId from the database reader in GetById and GetAll';
PRINT '';
GO

