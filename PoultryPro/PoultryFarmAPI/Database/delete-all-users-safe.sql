-- =============================================
-- SAFE VERSION: Delete all users with related records
-- This version handles foreign key constraints properly
-- =============================================
-- Database: poultry2_Prod
-- =============================================

USE [poultry2_Prod];
GO

PRINT '========================================';
PRINT 'Deleting all users and related records';
PRINT '========================================';
PRINT '';

-- Show current count
DECLARE @UserCount INT;
SELECT @UserCount = COUNT(*) FROM [dbo].[AspNetUsers];
PRINT 'Current user count: ' + CAST(@UserCount AS VARCHAR(10));
PRINT '';

BEGIN TRANSACTION;

BEGIN TRY
    PRINT 'Step 1: Deleting from AspNetUserRoles...';
    DELETE FROM [dbo].[AspNetUserRoles];
    PRINT '  Deleted ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' role assignments';
    
    PRINT 'Step 2: Deleting from AspNetUserClaims...';
    DELETE FROM [dbo].[AspNetUserClaims];
    PRINT '  Deleted ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' user claims';
    
    PRINT 'Step 3: Deleting from AspNetUserLogins...';
    DELETE FROM [dbo].[AspNetUserLogins];
    PRINT '  Deleted ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' user logins';
    
    PRINT 'Step 4: Deleting from AspNetUserTokens...';
    DELETE FROM [dbo].[AspNetUserTokens];
    PRINT '  Deleted ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' user tokens';
    
    -- Delete from custom tables that might reference UserId
    -- Uncomment and modify based on your schema
    
    -- Example: If you have a UserProfile table
    -- PRINT 'Step 5: Deleting from UserProfile...';
    -- DELETE FROM [dbo].[UserProfile];
    -- PRINT '  Deleted ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' user profiles';
    
    PRINT '';
    PRINT 'Step 5: Deleting from AspNetUsers...';
    DELETE FROM [dbo].[AspNetUsers];
    PRINT '  Deleted ' + CAST(@@ROWCOUNT AS VARCHAR(10)) + ' users';
    
    COMMIT TRANSACTION;
    
    PRINT '';
    PRINT '========================================';
    PRINT 'SUCCESS: All users deleted!';
    PRINT '========================================';
    
    -- Verify
    SELECT COUNT(*) AS RemainingUserCount FROM [dbo].[AspNetUsers];
    
END TRY
BEGIN CATCH
    ROLLBACK TRANSACTION;
    
    PRINT '';
    PRINT '========================================';
    PRINT 'ERROR: Transaction rolled back!';
    PRINT '========================================';
    PRINT 'Error: ' + ERROR_MESSAGE();
    PRINT 'Line: ' + CAST(ERROR_LINE() AS VARCHAR(10));
    PRINT '';
    PRINT 'Check for other tables that reference AspNetUsers';
    
END CATCH;
GO

