-- =============================================
-- Fix Flock to be shared by all users in the same farm
-- This ensures admin and staff see the same flocks
-- =============================================
-- INSTRUCTIONS:
-- 1. Replace 'poultry2_Prod' below with your actual database name
-- 2. Run this script on your PRODUCTION database
-- 3. After running, restart your PoultryFarmAPI service
-- =============================================

-- Replace 'poultry2_Prod' with your actual database name
USE [poultry2_Prod];
GO

PRINT '========================================';
PRINT 'Updating spFlock_GetAll to filter by FarmId only';
PRINT '========================================';
GO

-- Update spFlock_GetAll to filter by FarmId only (not UserId)
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[spFlock_GetAll]') AND type in (N'P', N'PC'))
BEGIN
    DROP PROCEDURE [dbo].[spFlock_GetAll];
    PRINT 'Dropped existing spFlock_GetAll';
END
GO

CREATE PROCEDURE [dbo].[spFlock_GetAll]
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Filter by FarmId only - all users (admin and staff) in the same farm see all flocks
    SELECT 
        f.FlockId,
        f.UserId,
        f.FarmId,
        f.Name,
        f.Breed,
        f.StartDate,
        f.Quantity,
        ISNULL(f.Active, 1) AS Active,
        f.HouseId,
        f.BatchId,
        f.InactivationReason,
        f.OtherReason,
        f.Notes,
        b.BatchName
    FROM dbo.Flock f
    LEFT JOIN dbo.MainFlockBatch b ON f.BatchId = b.BatchId AND f.FarmId = b.FarmId
    WHERE f.FarmId = @FarmId
    ORDER BY f.StartDate DESC;
END
GO

PRINT 'spFlock_GetAll updated successfully!';
PRINT 'Now all users (admin and staff) in the same farm will see all flocks.';
PRINT '';
PRINT '========================================';
PRINT 'NEXT STEPS:';
PRINT '1. Verify the stored procedure was created:';
PRINT '   SELECT * FROM sys.procedures WHERE name = ''spFlock_GetAll''';
PRINT '';
PRINT '2. Test the stored procedure:';
PRINT '   EXEC spFlock_GetAll @FarmId = ''your-farm-id-here''';
PRINT '';
PRINT '3. Restart your PoultryFarmAPI service/application';
PRINT '   so it picks up the new stored procedure.';
PRINT '';
PRINT '4. Test in the frontend - staff should now see admin''s flocks!';
PRINT '========================================';
GO

