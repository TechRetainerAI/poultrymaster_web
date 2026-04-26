/*
  Align dbo.AspNetUsers with User.Management.Data.Models.ApplicationUser.
  Run this on the SAME database as ConnectionStrings__ConnStr (Login / User Management API).

  Fixes: Invalid column name 'AdminTitle', 'FeaturePermissions', 'IsAdmin', 'Permissions'
  and prevents similar errors for other extended Identity columns.

  Safe to re-run: each column is added only if missing (SQL Server).
*/

IF COL_LENGTH('dbo.AspNetUsers', 'FarmId') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD FarmId NVARCHAR(450) NOT NULL CONSTRAINT DF_AspNetUsers_FarmId DEFAULT (N'');

IF COL_LENGTH('dbo.AspNetUsers', 'FarmName') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD FarmName NVARCHAR(256) NULL;

IF COL_LENGTH('dbo.AspNetUsers', 'IsStaff') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD IsStaff BIT NOT NULL CONSTRAINT DF_AspNetUsers_IsStaff DEFAULT (0);

IF COL_LENGTH('dbo.AspNetUsers', 'IsAdmin') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD IsAdmin BIT NOT NULL CONSTRAINT DF_AspNetUsers_IsAdmin DEFAULT (0);

IF COL_LENGTH('dbo.AspNetUsers', 'AdminTitle') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD AdminTitle NVARCHAR(100) NULL;

IF COL_LENGTH('dbo.AspNetUsers', 'Permissions') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD Permissions NVARCHAR(MAX) NULL;

IF COL_LENGTH('dbo.AspNetUsers', 'FeaturePermissions') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD FeaturePermissions NVARCHAR(MAX) NULL;

IF COL_LENGTH('dbo.AspNetUsers', 'IsSubscriber') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD IsSubscriber BIT NOT NULL CONSTRAINT DF_AspNetUsers_IsSubscriber DEFAULT (0);

IF COL_LENGTH('dbo.AspNetUsers', 'FirstName') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD FirstName NVARCHAR(255) NOT NULL CONSTRAINT DF_AspNetUsers_FirstName DEFAULT (N'');

IF COL_LENGTH('dbo.AspNetUsers', 'LastName') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD LastName NVARCHAR(255) NOT NULL CONSTRAINT DF_AspNetUsers_LastName DEFAULT (N'');

IF COL_LENGTH('dbo.AspNetUsers', 'CustomerId') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD CustomerId NVARCHAR(255) NULL;
