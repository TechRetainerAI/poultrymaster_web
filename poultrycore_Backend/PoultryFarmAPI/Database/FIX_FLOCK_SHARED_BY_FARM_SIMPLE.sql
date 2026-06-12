-- =============================================
-- Fix Flock to be shared by all users in the same farm
-- This ensures admin and staff see the same flocks
-- =============================================
-- INSTRUCTIONS:
-- 1. Make sure you're connected to the correct database
-- 2. Run this entire script
-- 3. After running, restart your PoultryFarmAPI service
-- =============================================

-- Drop existing procedure if it exists
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.spFlock_GetAll') AND type in (N'P', N'PC'))
BEGIN
    DROP PROCEDURE dbo.spFlock_GetAll;
    PRINT 'Dropped existing spFlock_GetAll';
END
GO

-- Create the new procedure that filters by FarmId only
CREATE PROCEDURE dbo.spFlock_GetAll
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

PRINT 'spFlock_GetAll created successfully!';
PRINT 'Now all users (admin and staff) in the same farm will see all flocks.';
GO

