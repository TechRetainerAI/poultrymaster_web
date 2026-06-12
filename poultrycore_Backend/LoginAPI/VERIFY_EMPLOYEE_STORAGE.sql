-- ============================================
-- VERIFY EMPLOYEE STORAGE IN DATABASE
-- Run this script to check if employees are stored
-- ============================================

-- Database: poultry2_ (from appsettings.json)
-- Table: AspNetUsers (ASP.NET Identity table)

-- 1. Check if IsStaff column exists
SELECT 
    COLUMN_NAME, 
    DATA_TYPE, 
    IS_NULLABLE,
    COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'AspNetUsers' 
    AND (COLUMN_NAME LIKE '%Staff%' OR COLUMN_NAME LIKE '%Farm%' OR COLUMN_NAME LIKE '%IsStaff%')
ORDER BY COLUMN_NAME;

-- 2. Check ALL users in AspNetUsers table
SELECT 
    Id,
    UserName,
    Email,
    FirstName,
    LastName,
    PhoneNumber,
    FarmId,
    FarmName,
    IsStaff,
    EmailConfirmed,
    LockoutEnabled,
    AccessFailedCount,
    PasswordHash,  -- Should not be NULL if user was created
    SecurityStamp  -- Should not be NULL if user was created
FROM AspNetUsers
ORDER BY IsStaff DESC, UserName;

-- 3. Check ONLY employees (IsStaff = 1 or IsStaff = true)
SELECT 
    Id,
    UserName,
    Email,
    FirstName,
    LastName,
    PhoneNumber,
    FarmId,
    FarmName,
    IsStaff,
    EmailConfirmed
FROM AspNetUsers
WHERE IsStaff = 1  -- or IsStaff = true (depending on data type)
ORDER BY UserName;

-- 4. Check employees by FarmId (replace 'YOUR_FARM_ID' with actual FarmId)
-- First, get your admin's FarmId:
SELECT 
    Id,
    UserName,
    FarmId,
    FarmName,
    IsStaff
FROM AspNetUsers
WHERE IsStaff = 0  -- Admin accounts
ORDER BY UserName;

-- Then use that FarmId to find employees:
-- SELECT * FROM AspNetUsers WHERE IsStaff = 1 AND FarmId = 'YOUR_FARM_ID_HERE';

-- 5. Check recent employee creations (if you have a CreatedDate or similar column)
SELECT TOP 10
    Id,
    UserName,
    Email,
    FirstName,
    LastName,
    FarmId,
    IsStaff,
    EmailConfirmed
FROM AspNetUsers
WHERE IsStaff = 1
ORDER BY Id DESC;  -- Most recent first (assuming GUIDs are sequential)

-- 6. Count employees by FarmId
SELECT 
    FarmId,
    FarmName,
    COUNT(*) as EmployeeCount
FROM AspNetUsers
WHERE IsStaff = 1
GROUP BY FarmId, FarmName
ORDER BY EmployeeCount DESC;

-- 7. Check if any users have NULL FarmId (this would cause issues)
SELECT 
    Id,
    UserName,
    Email,
    FarmId,
    IsStaff
FROM AspNetUsers
WHERE FarmId IS NULL OR FarmId = '';

-- ============================================
-- TROUBLESHOOTING QUERIES
-- ============================================

-- If employees aren't showing, check:
-- 1. Is IsStaff column actually a BIT/BOOLEAN? Try both:
SELECT * FROM AspNetUsers WHERE IsStaff = 1;
SELECT * FROM AspNetUsers WHERE IsStaff = 'true';
SELECT * FROM AspNetUsers WHERE IsStaff = 'True';

-- 2. Check data types
SELECT 
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'AspNetUsers'
    AND COLUMN_NAME IN ('IsStaff', 'FarmId', 'FarmName');

-- 3. Check if table exists and has data
SELECT COUNT(*) as TotalUsers FROM AspNetUsers;
SELECT COUNT(*) as TotalStaff FROM AspNetUsers WHERE IsStaff = 1;
SELECT COUNT(*) as TotalAdmins FROM AspNetUsers WHERE IsStaff = 0 OR IsStaff IS NULL;

