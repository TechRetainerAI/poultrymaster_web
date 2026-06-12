/*
  SQL Server: create ASP.NET Core Identity tables used by User.Management.API (Login API).

  Target shape = EF migrations (FixedVersion + FixedVersionofRefreshToken) + extended columns
  from Scripts/AspNetUsers_align_ApplicationUser.sql.

  When to use
  - Brand-new database where you want tables without running "dotnet ef database update".
  - If tables already exist, do NOT run this script (you will get "already exists" errors).
    Use EF migrations instead, or only run AspNetUsers_align_ApplicationUser.sql to add missing columns.

  Passwords: store only ASP.NET Identity PasswordHash (never plain text). Generate hash with:
    dotnet run --project Tools/IdentityHashGen -- "YourPassword"
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

/* ------------------------------------------------------------------ AspNetRoles */
IF OBJECT_ID(N'dbo.AspNetRoles', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AspNetRoles
    (
        Id               NVARCHAR(450) NOT NULL,
        Name             NVARCHAR(256) NULL,
        NormalizedName   NVARCHAR(256) NULL,
        ConcurrencyStamp NVARCHAR(MAX) NULL,
        CONSTRAINT PK_AspNetRoles PRIMARY KEY CLUSTERED (Id)
    );

    CREATE UNIQUE NONCLUSTERED INDEX RoleNameIndex
        ON dbo.AspNetRoles (NormalizedName)
        WHERE ([NormalizedName] IS NOT NULL);
END;
GO

/* ------------------------------------------------------------------ AspNetUsers */
IF OBJECT_ID(N'dbo.AspNetUsers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AspNetUsers
    (
        Id                     NVARCHAR(450) NOT NULL,
        UserName               NVARCHAR(256) NULL,
        NormalizedUserName     NVARCHAR(256) NULL,
        Email                  NVARCHAR(256) NULL,
        NormalizedEmail        NVARCHAR(256) NULL,
        EmailConfirmed         BIT NOT NULL CONSTRAINT DF_AspNetUsers_EmailConfirmed DEFAULT (0),
        PasswordHash           NVARCHAR(MAX) NULL,
        SecurityStamp          NVARCHAR(MAX) NULL,
        ConcurrencyStamp       NVARCHAR(MAX) NULL,
        PhoneNumber            NVARCHAR(MAX) NULL,
        PhoneNumberConfirmed   BIT NOT NULL CONSTRAINT DF_AspNetUsers_PhoneNumberConfirmed DEFAULT (0),
        TwoFactorEnabled       BIT NOT NULL CONSTRAINT DF_AspNetUsers_TwoFactorEnabled DEFAULT (0),
        LockoutEnd             DATETIMEOFFSET(7) NULL,
        LockoutEnabled         BIT NOT NULL CONSTRAINT DF_AspNetUsers_LockoutEnabled DEFAULT (1),
        AccessFailedCount      INT NOT NULL CONSTRAINT DF_AspNetUsers_AccessFailedCount DEFAULT (0),
        RefreshToken           NVARCHAR(MAX) NULL,
        RefreshTokenExpiry     DATETIME2(7) NULL,
        FarmId                 NVARCHAR(450) NOT NULL CONSTRAINT DF_AspNetUsers_FarmId DEFAULT (N''),
        FarmName               NVARCHAR(256) NULL,
        IsStaff                BIT NOT NULL CONSTRAINT DF_AspNetUsers_IsStaff DEFAULT (0),
        IsAdmin                BIT NOT NULL CONSTRAINT DF_AspNetUsers_IsAdmin DEFAULT (0),
        AdminTitle             NVARCHAR(100) NULL,
        Permissions            NVARCHAR(MAX) NULL,
        FeaturePermissions     NVARCHAR(MAX) NULL,
        IsSubscriber           BIT NOT NULL CONSTRAINT DF_AspNetUsers_IsSubscriber DEFAULT (0),
        FirstName              NVARCHAR(255) NOT NULL CONSTRAINT DF_AspNetUsers_FirstName DEFAULT (N''),
        LastName               NVARCHAR(255) NOT NULL CONSTRAINT DF_AspNetUsers_LastName DEFAULT (N''),
        CustomerId             NVARCHAR(255) NULL,
        CONSTRAINT PK_AspNetUsers PRIMARY KEY CLUSTERED (Id)
    );

    CREATE NONCLUSTERED INDEX EmailIndex
        ON dbo.AspNetUsers (NormalizedEmail);

    CREATE UNIQUE NONCLUSTERED INDEX UserNameIndex
        ON dbo.AspNetUsers (NormalizedUserName)
        WHERE ([NormalizedUserName] IS NOT NULL);
END;
GO

/* ------------------------------------------------------------------ AspNetRoleClaims */
IF OBJECT_ID(N'dbo.AspNetRoleClaims', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AspNetRoleClaims
    (
        Id         INT IDENTITY(1, 1) NOT NULL,
        RoleId     NVARCHAR(450) NOT NULL,
        ClaimType  NVARCHAR(MAX) NULL,
        ClaimValue NVARCHAR(MAX) NULL,
        CONSTRAINT PK_AspNetRoleClaims PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_AspNetRoleClaims_AspNetRoles_RoleId FOREIGN KEY (RoleId)
            REFERENCES dbo.AspNetRoles (Id) ON DELETE CASCADE
    );

    CREATE NONCLUSTERED INDEX IX_AspNetRoleClaims_RoleId ON dbo.AspNetRoleClaims (RoleId);
END;
GO

/* ------------------------------------------------------------------ AspNetUserClaims */
IF OBJECT_ID(N'dbo.AspNetUserClaims', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AspNetUserClaims
    (
        Id         INT IDENTITY(1, 1) NOT NULL,
        UserId     NVARCHAR(450) NOT NULL,
        ClaimType  NVARCHAR(MAX) NULL,
        ClaimValue NVARCHAR(MAX) NULL,
        CONSTRAINT PK_AspNetUserClaims PRIMARY KEY CLUSTERED (Id),
        CONSTRAINT FK_AspNetUserClaims_AspNetUsers_UserId FOREIGN KEY (UserId)
            REFERENCES dbo.AspNetUsers (Id) ON DELETE CASCADE
    );

    CREATE NONCLUSTERED INDEX IX_AspNetUserClaims_UserId ON dbo.AspNetUserClaims (UserId);
END;
GO

/* ------------------------------------------------------------------ AspNetUserLogins */
IF OBJECT_ID(N'dbo.AspNetUserLogins', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AspNetUserLogins
    (
        LoginProvider       NVARCHAR(450) NOT NULL,
        ProviderKey         NVARCHAR(450) NOT NULL,
        ProviderDisplayName NVARCHAR(MAX) NULL,
        UserId              NVARCHAR(450) NOT NULL,
        CONSTRAINT PK_AspNetUserLogins PRIMARY KEY CLUSTERED (LoginProvider, ProviderKey),
        CONSTRAINT FK_AspNetUserLogins_AspNetUsers_UserId FOREIGN KEY (UserId)
            REFERENCES dbo.AspNetUsers (Id) ON DELETE CASCADE
    );

    CREATE NONCLUSTERED INDEX IX_AspNetUserLogins_UserId ON dbo.AspNetUserLogins (UserId);
END;
GO

/* ------------------------------------------------------------------ AspNetUserRoles */
IF OBJECT_ID(N'dbo.AspNetUserRoles', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AspNetUserRoles
    (
        UserId NVARCHAR(450) NOT NULL,
        RoleId NVARCHAR(450) NOT NULL,
        CONSTRAINT PK_AspNetUserRoles PRIMARY KEY CLUSTERED (UserId, RoleId),
        CONSTRAINT FK_AspNetUserRoles_AspNetUsers_UserId FOREIGN KEY (UserId)
            REFERENCES dbo.AspNetUsers (Id) ON DELETE CASCADE,
        CONSTRAINT FK_AspNetUserRoles_AspNetRoles_RoleId FOREIGN KEY (RoleId)
            REFERENCES dbo.AspNetRoles (Id) ON DELETE CASCADE
    );

    CREATE NONCLUSTERED INDEX IX_AspNetUserRoles_RoleId ON dbo.AspNetUserRoles (RoleId);
END;
GO

/* ------------------------------------------------------------------ AspNetUserTokens */
IF OBJECT_ID(N'dbo.AspNetUserTokens', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AspNetUserTokens
    (
        UserId        NVARCHAR(450) NOT NULL,
        LoginProvider NVARCHAR(450) NOT NULL,
        Name          NVARCHAR(450) NOT NULL,
        Value         NVARCHAR(MAX) NULL,
        CONSTRAINT PK_AspNetUserTokens PRIMARY KEY CLUSTERED (UserId, LoginProvider, Name),
        CONSTRAINT FK_AspNetUserTokens_AspNetUsers_UserId FOREIGN KEY (UserId)
            REFERENCES dbo.AspNetUsers (Id) ON DELETE CASCADE
    );
END;
GO

/* ------------------------------------------------------------------ Seed roles (same IDs as EF migration FixedVersionofRefreshToken) */
IF NOT EXISTS (SELECT 1 FROM dbo.AspNetRoles WHERE Id = N'06fffaac-375e-4f66-9a02-b09f8e1c4b22')
    INSERT INTO dbo.AspNetRoles (Id, Name, NormalizedName, ConcurrencyStamp)
    VALUES (N'06fffaac-375e-4f66-9a02-b09f8e1c4b22', N'Admin', N'ADMIN', N'1');

IF NOT EXISTS (SELECT 1 FROM dbo.AspNetRoles WHERE Id = N'd0c7a5b6-0f03-47e9-91fa-15afad51eca0')
    INSERT INTO dbo.AspNetRoles (Id, Name, NormalizedName, ConcurrencyStamp)
    VALUES (N'd0c7a5b6-0f03-47e9-91fa-15afad51eca0', N'User', N'USER', N'2');

IF NOT EXISTS (SELECT 1 FROM dbo.AspNetRoles WHERE Id = N'e30c42ce-8a24-4a13-a10b-f07d3b205e16')
    INSERT INTO dbo.AspNetRoles (Id, Name, NormalizedName, ConcurrencyStamp)
    VALUES (N'e30c42ce-8a24-4a13-a10b-f07d3b205e16', N'HR', N'HR', N'3');

/* Optional: platform-level roles (API seed may also create these) */
IF NOT EXISTS (SELECT 1 FROM dbo.AspNetRoles WHERE NormalizedName = N'SYSTEMADMIN')
    INSERT INTO dbo.AspNetRoles (Id, Name, NormalizedName, ConcurrencyStamp)
    VALUES (CAST(NEWID() AS NVARCHAR(450)), N'SystemAdmin', N'SYSTEMADMIN', CAST(NEWID() AS NVARCHAR(36)));

IF NOT EXISTS (SELECT 1 FROM dbo.AspNetRoles WHERE NormalizedName = N'PLATFORMOWNER')
    INSERT INTO dbo.AspNetRoles (Id, Name, NormalizedName, ConcurrencyStamp)
    VALUES (CAST(NEWID() AS NVARCHAR(450)), N'PlatformOwner', N'PLATFORMOWNER', CAST(NEWID() AS NVARCHAR(36)));

GO

PRINT 'Identity tables are ready. Insert users with a valid PasswordHash, or use the Login API / DatabaseBootstrap.';
