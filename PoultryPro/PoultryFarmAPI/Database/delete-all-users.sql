-- =============================================
-- WARNING: DESTRUCTIVE OPERATION
-- This script will DELETE ALL USERS from AspNetUsers table
-- =============================================
-- Database: poultry2_Prod
-- Table: [dbo].[AspNetUsers]
-- =============================================
-- ⚠️  BACKUP YOUR DATABASE BEFORE RUNNING THIS SCRIPT ⚠️
-- =============================================

USE [poultry2_Prod];
GO

PRINT '========================================';
PRINT 'WARNING: This will delete ALL users!';
PRINT '========================================';
PRINT '';
PRINT 'Current user count:';
SELECT COUNT(*) AS UserCount FROM [dbo].[AspNetUsers];
PRINT '';
GO

-- =============================================
-- OPTION 1: DELETE (Recommended - handles foreign keys)
-- =============================================
-- This will delete all users and handle foreign key constraints
-- If foreign keys exist, you may need to delete related records first
-- =============================================

BEGIN TRANSACTION;

BEGIN TRY
    -- Check for foreign key constraints
    PRINT 'Checking for foreign key constraints...';
    
    -- List tables that reference AspNetUsers
    SELECT 
        fk.name AS ForeignKeyName,
        OBJECT_NAME(fk.parent_object_id) AS ReferencingTable,
        COL_NAME(fc.parent_object_id, fc.parent_column_id) AS ReferencingColumn
    FROM sys.foreign_keys AS fk
    INNER JOIN sys.foreign_key_columns AS fc 
        ON fk.object_id = fc.constraint_object_id
    WHERE OBJECT_NAME(fk.referenced_object_id) = 'AspNetUsers';
    
    PRINT '';
    PRINT 'Deleting all users from AspNetUsers...';
    
    -- Delete all users
    DELETE FROM [dbo].[AspNetUsers];
    
    PRINT 'Successfully deleted all users.';
    PRINT 'Rows affected: ' + CAST(@@ROWCOUNT AS VARCHAR(10));
    
    -- Commit the transaction
    COMMIT TRANSACTION;
    
    PRINT '';
    PRINT '========================================';
    PRINT 'All users deleted successfully!';
    PRINT '========================================';
    
END TRY
BEGIN CATCH
    -- Rollback on error
    ROLLBACK TRANSACTION;
    
    PRINT '';
    PRINT '========================================';
    PRINT 'ERROR: Transaction rolled back!';
    PRINT '========================================';
    PRINT 'Error Message: ' + ERROR_MESSAGE();
    PRINT 'Error Number: ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
    PRINT 'Error Line: ' + CAST(ERROR_LINE() AS VARCHAR(10));
    PRINT '';
    PRINT 'Possible causes:';
    PRINT '  1. Foreign key constraints exist';
    PRINT '  2. Related records in other tables need to be deleted first';
    PRINT '';
    PRINT 'If foreign keys exist, you may need to:';
    PRINT '  1. Delete related records first (see related tables above)';
    PRINT '  2. Or use OPTION 2 below (TRUNCATE - requires disabling constraints)';
    
END CATCH;
GO

-- =============================================
-- OPTION 2: TRUNCATE (Faster, but requires no foreign keys)
-- =============================================
-- Uncomment the section below if DELETE fails due to foreign keys
-- WARNING: TRUNCATE will fail if foreign keys reference this table
-- =============================================

/*
USE [poultry2_Prod];
GO

-- Disable foreign key constraints temporarily
ALTER TABLE [dbo].[AspNetUsers] NOCHECK CONSTRAINT ALL;
GO

-- Truncate the table (faster than DELETE)
TRUNCATE TABLE [dbo].[AspNetUsers];
GO

-- Re-enable foreign key constraints
ALTER TABLE [dbo].[AspNetUsers] CHECK CONSTRAINT ALL;
GO

PRINT 'Table truncated successfully!';
GO
*/

-- =============================================
-- OPTION 3: Delete related records first (if foreign keys exist)
-- =============================================
-- If you get foreign key errors, you may need to delete from related tables first
-- Common related tables might include:
--   - AspNetUserRoles
--   - AspNetUserClaims
--   - AspNetUserLogins
--   - AspNetUserTokens
--   - Other custom tables that reference UserId
-- =============================================

/*
USE [poultry2_Prod];
GO

BEGIN TRANSACTION;

BEGIN TRY
    -- Delete from related tables first (adjust based on your schema)
    DELETE FROM [dbo].[AspNetUserRoles];
    DELETE FROM [dbo].[AspNetUserClaims];
    DELETE FROM [dbo].[AspNetUserLogins];
    DELETE FROM [dbo].[AspNetUserTokens];
    
    -- Add other related tables here if they exist
    -- DELETE FROM [dbo].[YourRelatedTable];
    
    -- Now delete users
    DELETE FROM [dbo].[AspNetUsers];
    
    COMMIT TRANSACTION;
    PRINT 'All users and related records deleted successfully!';
    
END TRY
BEGIN CATCH
    ROLLBACK TRANSACTION;
    PRINT 'Error: ' + ERROR_MESSAGE();
END CATCH;
GO
*/

-- =============================================
-- VERIFICATION
-- =============================================
-- Run this to verify all users are deleted
-- =============================================

PRINT '';
PRINT '========================================';
PRINT 'Verification: Current user count';
PRINT '========================================';
SELECT COUNT(*) AS RemainingUserCount FROM [dbo].[AspNetUsers];
GO

