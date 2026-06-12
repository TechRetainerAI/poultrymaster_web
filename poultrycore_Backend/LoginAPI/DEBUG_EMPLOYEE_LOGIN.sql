-- SQL script to debug employee login issues
-- This helps verify that employees can be found by username/email during login

-- Use the correct database name if not already selected
-- USE [YourDatabaseName];
-- GO

-- 1. Check a specific employee by Username (case-sensitive)
--    Replace 'Profowusu1' with the actual username
SELECT
    Id,
    UserName,
    NormalizedUserName,
    Email,
    NormalizedEmail,
    FirstName,
    LastName,
    IsStaff,
    EmailConfirmed,
    FarmId,
    FarmName,
    PhoneNumber,
    TwoFactorEnabled,
    LockoutEnabled,
    AccessFailedCount
FROM
    AspNetUsers
WHERE
    UserName = 'Profowusu1';
GO

-- 2. Check a specific employee by Email (case-sensitive)
--    Replace 'jquayson827@gmail.com' with the actual email
SELECT
    Id,
    UserName,
    NormalizedUserName,
    Email,
    NormalizedEmail,
    FirstName,
    LastName,
    IsStaff,
    EmailConfirmed,
    FarmId,
    FarmName
FROM
    AspNetUsers
WHERE
    Email = 'jquayson827@gmail.com';
GO

-- 3. Check by NormalizedUserName (this is what FindByNameAsync uses)
--    Replace 'PROFOWUSU1' with the UPPERCASE version of the username
SELECT
    Id,
    UserName,
    NormalizedUserName,
    Email,
    NormalizedEmail,
    IsStaff,
    EmailConfirmed
FROM
    AspNetUsers
WHERE
    NormalizedUserName = 'PROFOWUSU1';
GO

-- 4. Check by NormalizedEmail (this is what FindByEmailAsync uses)
--    Replace 'JQUAYSON827@GMAIL.COM' with the UPPERCASE version of the email
SELECT
    Id,
    UserName,
    NormalizedUserName,
    Email,
    NormalizedEmail,
    IsStaff,
    EmailConfirmed
FROM
    AspNetUsers
WHERE
    NormalizedEmail = 'JQUAYSON827@GMAIL.COM';
GO

-- 5. List ALL employees with their normalized fields
--    This helps identify if NormalizedUserName or NormalizedEmail are NULL or incorrect
SELECT
    Id,
    UserName,
    NormalizedUserName,
    Email,
    NormalizedEmail,
    IsStaff,
    EmailConfirmed,
    FarmId,
    FarmName,
    CASE 
        WHEN NormalizedUserName IS NULL THEN 'MISSING NormalizedUserName'
        WHEN NormalizedEmail IS NULL THEN 'MISSING NormalizedEmail'
        ELSE 'OK'
    END AS Status
FROM
    AspNetUsers
WHERE
    IsStaff = 1
ORDER BY
    UserName;
GO

-- 6. Find employees with NULL or empty NormalizedUserName/NormalizedEmail
--    These employees will NOT be found by FindByNameAsync or FindByEmailAsync
SELECT
    Id,
    UserName,
    NormalizedUserName,
    Email,
    NormalizedEmail,
    IsStaff,
    EmailConfirmed,
    FarmId,
    FarmName
FROM
    AspNetUsers
WHERE
    IsStaff = 1
    AND (
        NormalizedUserName IS NULL 
        OR NormalizedUserName = ''
        OR NormalizedEmail IS NULL 
        OR NormalizedEmail = ''
    )
ORDER BY
    UserName;
GO

-- 7. Fix NULL NormalizedUserName for a specific employee
--    Replace 'Profowusu1' with the actual username
--    This will set NormalizedUserName to UPPERCASE of UserName
UPDATE AspNetUsers
SET NormalizedUserName = UPPER(UserName)
WHERE UserName = 'Profowusu1'
    AND (NormalizedUserName IS NULL OR NormalizedUserName = '');
GO

-- 8. Fix NULL NormalizedEmail for a specific employee
--    Replace 'jquayson827@gmail.com' with the actual email
--    This will set NormalizedEmail to UPPERCASE of Email
UPDATE AspNetUsers
SET NormalizedEmail = UPPER(Email)
WHERE Email = 'jquayson827@gmail.com'
    AND (NormalizedEmail IS NULL OR NormalizedEmail = '');
GO

-- 9. Fix ALL employees with NULL NormalizedUserName or NormalizedEmail
--    Uncomment to fix all employees at once:
/*
UPDATE AspNetUsers
SET 
    NormalizedUserName = UPPER(UserName),
    NormalizedEmail = UPPER(Email)
WHERE IsStaff = 1
    AND (
        NormalizedUserName IS NULL 
        OR NormalizedUserName = ''
        OR NormalizedEmail IS NULL 
        OR NormalizedEmail = ''
    );
GO
*/

-- 10. Verify the fix
SELECT
    Id,
    UserName,
    NormalizedUserName,
    Email,
    NormalizedEmail,
    IsStaff,
    EmailConfirmed
FROM
    AspNetUsers
WHERE
    UserName = 'Profowusu1';
GO

