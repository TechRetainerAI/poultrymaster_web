/*
  Developer farm-registry portal — SQL Server setup
  ==================================================
  The registry is a *separate* static site (farm-registry-portal). It is NOT the farm app.
  It shows all registered farms and paid vs unpaid (via Login API /api/System/farms).

  LOGIN (important)
  -----------------
  There is no separate "developer login table" for authentication. The Login API uses
  ASP.NET Identity:
    - dbo.AspNetUsers     — usernames and password hashes (the real login rows)
    - dbo.AspNetRoles     — e.g. SystemAdmin, PlatformOwner
    - dbo.AspNetUserRoles — which user has which role

  Only users with SystemAdmin OR PlatformOwner get a JWT that can call /api/System/farms.
  Farm owners and staff stay on the main product; they do not use this portal.

  This script:
    1) Ensures platform roles exist
    2) Creates an optional bookkeeping table (does NOT grant API access by itself)
    3) Creates a view listing accounts that *can* sign into the developer portal (by role)
    4) Example: grant platform roles to your developer username (edit @DeveloperUserName)
*/

SET NOCOUNT ON;

/* --- 1) Roles required for the developer portal --- */
IF NOT EXISTS (SELECT 1 FROM dbo.AspNetRoles WHERE NormalizedName = N'SYSTEMADMIN')
    INSERT INTO dbo.AspNetRoles (Id, Name, NormalizedName, ConcurrencyStamp)
    VALUES (CAST(NEWID() AS NVARCHAR(450)), N'SystemAdmin', N'SYSTEMADMIN', CAST(NEWID() AS NVARCHAR(36)));

IF NOT EXISTS (SELECT 1 FROM dbo.AspNetRoles WHERE NormalizedName = N'PLATFORMOWNER')
    INSERT INTO dbo.AspNetRoles (Id, Name, NormalizedName, ConcurrencyStamp)
    VALUES (CAST(NEWID() AS NVARCHAR(450)), N'PlatformOwner', N'PLATFORMOWNER', CAST(NEWID() AS NVARCHAR(36)));

GO

/* --- 2) Optional: who you designate as the portal operator (documentation / reporting only) ---
      API access is still controlled only by AspNetUserRoles + JWT. */
IF OBJECT_ID(N'dbo.DeveloperPortalOperator', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DeveloperPortalOperator (
        UserId NVARCHAR(450) NOT NULL,
        Label NVARCHAR(200) NULL,
        RecordedUtc DATETIME2 NOT NULL CONSTRAINT DF_DeveloperPortalOperator_Recorded DEFAULT SYSUTCDATETIME(),
        CONSTRAINT PK_DeveloperPortalOperator PRIMARY KEY (UserId),
        CONSTRAINT FK_DeveloperPortalOperator_AspNetUsers FOREIGN KEY (UserId) REFERENCES dbo.AspNetUsers (Id)
    );
END;

GO

/* --- 3) View: Identity users who currently have developer-portal roles --- */
IF OBJECT_ID(N'dbo.vw_DeveloperPortalEligibleUsers', N'V') IS NOT NULL
    DROP VIEW dbo.vw_DeveloperPortalEligibleUsers;
GO

CREATE VIEW dbo.vw_DeveloperPortalEligibleUsers
AS
SELECT DISTINCT
    u.Id AS UserId,
    u.UserName,
    u.Email,
    r.Name AS RoleName
FROM dbo.AspNetUsers u
INNER JOIN dbo.AspNetUserRoles ur ON ur.UserId = u.Id
INNER JOIN dbo.AspNetRoles r ON r.Id = ur.RoleId
WHERE r.NormalizedName IN (N'SYSTEMADMIN', N'PLATFORMOWNER');
GO

/* --- 4) Grant both platform roles to one developer account (edit username) --- */
DECLARE @DeveloperUserName NVARCHAR(256) = N'systemadmin'; /* <-- your single developer login */

DECLARE @UserId NVARCHAR(450) =
(
    SELECT TOP (1) u.Id
    FROM dbo.AspNetUsers u
    WHERE u.NormalizedUserName = UPPER(LTRIM(RTRIM(@DeveloperUserName)))
       OR u.UserName = @DeveloperUserName
       OR u.NormalizedUserName = @DeveloperUserName
    ORDER BY CASE WHEN u.NormalizedUserName = UPPER(LTRIM(RTRIM(@DeveloperUserName))) THEN 0 ELSE 1 END
);

IF @UserId IS NULL
BEGIN
    PRINT N'No AspNetUsers row matched. USE the Login API database. Existing UserName values (first 30):';
    SELECT TOP (30) UserName, NormalizedUserName, Email FROM dbo.AspNetUsers ORDER BY UserName;
    PRINT N'Create the user first (Development seed, Register API, or Cloud Run DatabaseBootstrap__SeedIdentity), then re-run section 4.';
END
ELSE
BEGIN
    DECLARE @R1 NVARCHAR(450) = (SELECT Id FROM dbo.AspNetRoles WHERE NormalizedName = N'SYSTEMADMIN');
    DECLARE @R2 NVARCHAR(450) = (SELECT Id FROM dbo.AspNetRoles WHERE NormalizedName = N'PLATFORMOWNER');

    IF @R1 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.AspNetUserRoles WHERE UserId = @UserId AND RoleId = @R1)
        INSERT INTO dbo.AspNetUserRoles (UserId, RoleId) VALUES (@UserId, @R1);

    IF @R2 IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.AspNetUserRoles WHERE UserId = @UserId AND RoleId = @R2)
        INSERT INTO dbo.AspNetUserRoles (UserId, RoleId) VALUES (@UserId, @R2);

    IF NOT EXISTS (SELECT 1 FROM dbo.DeveloperPortalOperator WHERE UserId = @UserId)
        INSERT INTO dbo.DeveloperPortalOperator (UserId, Label) VALUES (@UserId, N'Default developer portal account');

    PRINT N'Platform roles attached. Developer must sign out and sign in again for a new JWT.';
END;

GO
