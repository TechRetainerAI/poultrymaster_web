-- =============================================
-- Stored Procedure: spFlock_GetTotalQuantityForBatch
-- Description: Gets the total quantity of birds across all flocks for a specific batch
-- Database: poultry2_Prod
-- =============================================
-- This stored procedure calculates the sum of Quantity from all flocks
-- that belong to a specific BatchId, UserId, and FarmId.
-- Optionally excludes a specific FlockId (useful when updating a flock).
-- =============================================

USE [poultry2_Prod];
GO

-- Drop the procedure if it exists
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[spFlock_GetTotalQuantityForBatch]') AND type in (N'P', N'PC'))
    DROP PROCEDURE [dbo].[spFlock_GetTotalQuantityForBatch];
GO

CREATE PROCEDURE [dbo].[spFlock_GetTotalQuantityForBatch]
    @BatchId INT,
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450),
    @FlockIdToExclude INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Calculate the sum of Quantity for all flocks matching the criteria
    -- ISNULL ensures we return 0 if no flocks are found
    SELECT ISNULL(SUM([Quantity]), 0) AS TotalQuantity
    FROM [dbo].[Flock]
    WHERE [BatchId] = @BatchId
      AND [UserId] = @UserId
      AND [FarmId] = @FarmId
      AND (@FlockIdToExclude IS NULL OR [FlockId] != @FlockIdToExclude);
END
GO

PRINT 'Stored procedure spFlock_GetTotalQuantityForBatch created successfully';
GO

-- Grant execute permissions (adjust as needed for your security model)
-- GRANT EXECUTE ON [dbo].[spFlock_GetTotalQuantityForBatch] TO [YourAppUser];
-- GO

PRINT '';
PRINT '========================================';
PRINT 'Stored Procedure Created!';
PRINT '========================================';
PRINT '';
PRINT 'Parameters:';
PRINT '  @BatchId INT - The batch ID to calculate total quantity for';
PRINT '  @UserId NVARCHAR(450) - The user ID (for filtering)';
PRINT '  @FarmId NVARCHAR(450) - The farm ID (for filtering)';
PRINT '  @FlockIdToExclude INT (optional) - Flock ID to exclude from calculation';
PRINT '';
PRINT 'Returns:';
PRINT '  TotalQuantity INT - Sum of all Quantity values matching the criteria';
PRINT '';
PRINT 'Usage:';
PRINT '  EXEC [dbo].[spFlock_GetTotalQuantityForBatch]';
PRINT '      @BatchId = 1,';
PRINT '      @UserId = ''user-guid'',';
PRINT '      @FarmId = ''farm-guid'',';
PRINT '      @FlockIdToExclude = NULL;';
PRINT '';
GO

