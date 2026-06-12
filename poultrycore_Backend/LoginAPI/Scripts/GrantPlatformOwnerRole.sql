/*
  Grant platform access: add Identity role "PlatformOwner" to an existing user (and create the role if missing).

  Prerequisites:
  - Run this against the SAME database as the Login API (ConnStr) — the one that has dbo.AspNetUsers.
  - The user must already exist (seed, Register API, or manual insert). This script does not create passwords.

  Replace @UserName with the exact or logical login name (e.g. systemadmin).

  After running, the user must sign out and sign in again so the JWT includes the new role.
*/

DECLARE @UserName NVARCHAR(256) = N'systemadmin'; /* <-- change to your login */

IF OBJECT_ID(N'dbo.AspNetUsers', N'U') IS NULL
BEGIN
    RAISERROR(N'Table dbo.AspNetUsers not found. You are probably on the wrong database — switch to the Login API database.', 16, 1);
    RETURN;
END;

IF NOT EXISTS (SELECT 1 FROM dbo.AspNetRoles WHERE NormalizedName = N'PLATFORMOWNER')
BEGIN
    INSERT INTO dbo.AspNetRoles (Id, Name, NormalizedName, ConcurrencyStamp)
    VALUES (CAST(NEWID() AS NVARCHAR(450)), N'PlatformOwner', N'PLATFORMOWNER', CAST(NEWID() AS NVARCHAR(36)));
END;

/* Identity stores NormalizedUserName (usually upper-case ASCII). Match flexibly. */
DECLARE @UserId NVARCHAR(450) =
(
    SELECT TOP (1) u.Id
    FROM dbo.AspNetUsers u
    WHERE u.NormalizedUserName = UPPER(LTRIM(RTRIM(@UserName)))
       OR u.UserName = @UserName
       OR u.NormalizedUserName = @UserName
    ORDER BY CASE WHEN u.NormalizedUserName = UPPER(LTRIM(RTRIM(@UserName))) THEN 0 ELSE 1 END
);

IF @UserId IS NULL
BEGIN
    PRINT N'No AspNetUsers row matched @UserName = ' + @UserName + N'. Existing UserName values (first 30):';
    SELECT TOP (30) UserName, NormalizedUserName, Email
    FROM dbo.AspNetUsers
    ORDER BY UserName;
    RAISERROR(
        N'No user found. Fix: (1) USE the Login database. (2) Set @UserName to one of the UserName values above. (3) Create the user first (Development seed, POST /api/Authentication/Register, or Cloud Run DatabaseBootstrap__SeedIdentity).',
        16,
        1);
    RETURN;
END;

DECLARE @RoleId NVARCHAR(450) = (SELECT Id FROM dbo.AspNetRoles WHERE NormalizedName = N'PLATFORMOWNER');

IF NOT EXISTS (SELECT 1 FROM dbo.AspNetUserRoles WHERE UserId = @UserId AND RoleId = @RoleId)
    INSERT INTO dbo.AspNetUserRoles (UserId, RoleId) VALUES (@UserId, @RoleId);

PRINT N'Done. User must re-login for a new token.';
