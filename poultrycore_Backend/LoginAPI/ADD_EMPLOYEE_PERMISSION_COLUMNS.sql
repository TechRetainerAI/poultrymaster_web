-- Adds admin/permission fields required by LoginAPI employee management
-- Safe to run multiple times (checks column existence first)

IF COL_LENGTH('AspNetUsers', 'IsAdmin') IS NULL
BEGIN
    ALTER TABLE AspNetUsers
    ADD IsAdmin BIT NOT NULL CONSTRAINT DF_AspNetUsers_IsAdmin DEFAULT (0);
END
GO

IF COL_LENGTH('AspNetUsers', 'AdminTitle') IS NULL
BEGIN
    ALTER TABLE AspNetUsers
    ADD AdminTitle NVARCHAR(100) NULL;
END
GO

IF COL_LENGTH('AspNetUsers', 'Permissions') IS NULL
BEGIN
    ALTER TABLE AspNetUsers
    ADD Permissions NVARCHAR(MAX) NULL;
END
GO

IF COL_LENGTH('AspNetUsers', 'FeaturePermissions') IS NULL
BEGIN
    ALTER TABLE AspNetUsers
    ADD FeaturePermissions NVARCHAR(MAX) NULL;
END
GO

-- Optional verification query
SELECT
    TOP (20)
    Id,
    UserName,
    IsStaff,
    IsAdmin,
    AdminTitle,
    Permissions,
    FeaturePermissions
FROM AspNetUsers
ORDER BY UserName;
GO
