-- SQL script to fix employees with IsStaff = 0
-- This fixes employees that were created before the IsStaff persistence fix

-- Use the correct database name if not already selected
-- USE [YourDatabaseName];
-- GO

-- 1. Check which employees have IsStaff = 0 but should be employees
--    (They have FarmId set, which indicates they were created by an admin)
SELECT
    Id,
    UserName,
    Email,
    FirstName,
    LastName,
    IsStaff,
    EmailConfirmed,
    FarmId,
    FarmName
FROM
    AspNetUsers
WHERE
    IsStaff = 0
    AND FarmId IS NOT NULL
    AND FarmId != ''
ORDER BY
    UserName;
GO

-- 2. Fix the specific employee shown by the user (Profowusu1)
--    Replace the Id if needed
UPDATE AspNetUsers
SET IsStaff = 1
WHERE Id = 'c4e4887e-7fd6-4f1e-bab1-cb90d1500eab'
    AND UserName = 'Profowusu1';
GO

-- 3. Fix ALL employees with IsStaff = 0 that have a FarmId
--    (This assumes all users with FarmId are employees, not admins)
--    Uncomment the following if you want to fix all at once:
/*
UPDATE AspNetUsers
SET IsStaff = 1
WHERE IsStaff = 0
    AND FarmId IS NOT NULL
    AND FarmId != '';
GO
*/

-- 4. Verify the fix
SELECT
    Id,
    UserName,
    Email,
    FirstName,
    LastName,
    IsStaff,
    EmailConfirmed,
    FarmId,
    FarmName
FROM
    AspNetUsers
WHERE
    Id = 'c4e4887e-7fd6-4f1e-bab1-cb90d1500eab'
    AND UserName = 'Profowusu1';
GO

