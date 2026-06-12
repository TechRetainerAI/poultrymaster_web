-- =============================================
-- Fix Flock API for Frontend Integration
-- Database: poultry2_Prod
-- =============================================
-- This script ensures flocks display based on FarmId only
-- All users in the same farm will see all flocks for that farm
-- =============================================

USE [poultry2_Prod];
GO

PRINT '========================================';
PRINT 'Fixing Flock API for Frontend';
PRINT '========================================';
GO

-- Step 1: Add Active column if it doesn't exist
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Flock') AND name = 'Active')
BEGIN
    PRINT 'Adding Active column to Flock table...';
    ALTER TABLE [dbo].[Flock] ADD [Active] BIT NOT NULL DEFAULT 1;
    PRINT 'Active column added successfully';
END
ELSE
BEGIN
    PRINT 'Active column already exists';
END
GO

-- Step 2: Update spFlock_GetAll to filter by FarmId only
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[spFlock_GetAll]') AND type in (N'P', N'PC'))
    DROP PROCEDURE [dbo].[spFlock_GetAll];
GO

CREATE PROCEDURE [dbo].[spFlock_GetAll]
    @FarmId NVARCHAR(450),
    @UserId NVARCHAR(450) = NULL  -- Accepted but not used in filtering (for backward compatibility)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Filter by FarmId only - all users in the same farm see all flocks
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

PRINT 'spFlock_GetAll updated successfully - now filters by FarmId only';
GO

-- Step 3: Ensure spFlock_Insert is correct
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
    
    -- Insert the flock (Active defaults to 1, HouseId is NULL)
    INSERT INTO [dbo].[Flock] 
        ([UserId], [FarmId], [Name], [Breed], [StartDate], [Quantity], [Active], [HouseId], [BatchId], [InactivationReason], [OtherReason], [Notes])
    VALUES 
        (@UserId, @FarmId, @Name, @Breed, @StartDate, @Quantity, 1, NULL, @BatchId, @InactivationReason, @OtherReason, @Notes);
    
    -- Return the newly created FlockId
    SELECT CAST(SCOPE_IDENTITY() AS INT) AS FlockId;
END
GO

PRINT 'spFlock_Insert updated successfully';
GO

PRINT '';
PRINT '========================================';
PRINT 'Flock API Fix Complete!';
PRINT '========================================';
PRINT '';
PRINT 'What was fixed:';
PRINT '  1. Active column added (if missing)';
PRINT '  2. spFlock_GetAll now filters by FarmId only';
PRINT '     - All users in the same farm will see all flocks for that farm';
PRINT '     - The @UserId parameter is accepted but not used for filtering';
PRINT '  3. spFlock_Insert updated to handle create properly';
PRINT '';
PRINT 'The backend C# service (BirdFlockService.cs) already passes only @FarmId,';
PRINT 'so this stored procedure change will work correctly with the frontend.';
PRINT '';
GO

