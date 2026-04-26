/*
  Create Identity user "developerlogin" for the developer farm-registry portal only.

  Run against the Login API database (same as ConnStr). Requires dbo.AspNetUsers + dbo.Farms
  (or stored procedure dbo.sp_CreateFarm).

  Default password after this script (CHANGE immediately on production):
    DevDeveloperLogin!23

  To use a different password: from repo folder poultrycore/LoginAPI run:
    dotnet run --project Tools/IdentityHashGen -- "YourNewPassword"
  Replace @PasswordHash below with the printed line, then run this script again on a DB where
  you have deleted the old developerlogin row first (or only change hash via UPDATE).
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @UserName NVARCHAR(256) = N'developerlogin';
DECLARE @Email NVARCHAR(256) = N'developerlogin@localhost';

/* Hash for plain text: DevDeveloperLogin!23 (Identity v3 / PasswordHasher<ApplicationUser>) */
DECLARE @PasswordHash NVARCHAR(MAX) = N'AQAAAAIAAYagAAAAEFcnt6uaAPIvyzf4FXczd7hLCnygZvA/lIWgZU7+GZeEcD0i7mf3k6i7Dc958ar4+w==';

IF OBJECT_ID(N'dbo.AspNetUsers', N'U') IS NULL
BEGIN
    RAISERROR(N'dbo.AspNetUsers missing — wrong database.', 16, 1);
    RETURN;
END;

/* --- Ensure platform roles --- */
IF NOT EXISTS (SELECT 1 FROM dbo.AspNetRoles WHERE NormalizedName = N'SYSTEMADMIN')
    INSERT INTO dbo.AspNetRoles (Id, Name, NormalizedName, ConcurrencyStamp)
    VALUES (CAST(NEWID() AS NVARCHAR(450)), N'SystemAdmin', N'SYSTEMADMIN', CAST(NEWID() AS NVARCHAR(36)));

IF NOT EXISTS (SELECT 1 FROM dbo.AspNetRoles WHERE NormalizedName = N'PLATFORMOWNER')
    INSERT INTO dbo.AspNetRoles (Id, Name, NormalizedName, ConcurrencyStamp)
    VALUES (CAST(NEWID() AS NVARCHAR(450)), N'PlatformOwner', N'PLATFORMOWNER', CAST(NEWID() AS NVARCHAR(36)));

DECLARE @UserId NVARCHAR(450) =
(
    SELECT TOP (1) Id
    FROM dbo.AspNetUsers
    WHERE NormalizedUserName = UPPER(LTRIM(RTRIM(@UserName)))
       OR UserName = @UserName
);

IF @UserId IS NOT NULL
BEGIN
    PRINT N'User already exists: ' + @UserName + N'. Ensuring SystemAdmin + PlatformOwner roles only.';
    DECLARE @R1a NVARCHAR(450) = (SELECT Id FROM dbo.AspNetRoles WHERE NormalizedName = N'SYSTEMADMIN');
    DECLARE @R2a NVARCHAR(450) = (SELECT Id FROM dbo.AspNetRoles WHERE NormalizedName = N'PLATFORMOWNER');
    IF @R1a IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.AspNetUserRoles WHERE UserId = @UserId AND RoleId = @R1a)
        INSERT INTO dbo.AspNetUserRoles (UserId, RoleId) VALUES (@UserId, @R1a);
    IF @R2a IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.AspNetUserRoles WHERE UserId = @UserId AND RoleId = @R2a)
        INSERT INTO dbo.AspNetUserRoles (UserId, RoleId) VALUES (@UserId, @R2a);
    PRINT N'Done. Sign in with existing password; re-login if roles were added.';
    RETURN;
END;

DECLARE @FarmId NVARCHAR(450) = LOWER(CAST(NEWID() AS NVARCHAR(36)));

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'dbo.sp_CreateFarm', N'P') IS NOT NULL
    BEGIN
        EXEC dbo.sp_CreateFarm
            @FarmId = @FarmId,
            @Name = N'Platform (developer portal)',
            @Type = N'System',
            @Email = @Email,
            @PhoneNumber = NULL;
    END
    ELSE IF OBJECT_ID(N'dbo.Farms', N'U') IS NOT NULL
    BEGIN
        INSERT INTO dbo.Farms (FarmId, Name, Email, Type, PhoneNumber, CreatedAt)
        VALUES (@FarmId, N'Platform (developer portal)', @Email, N'System', NULL, SYSUTCDATETIME());
    END
    ELSE
    BEGIN
        RAISERROR(N'Neither dbo.sp_CreateFarm nor dbo.Farms exists — cannot attach FarmId.', 16, 1);
        RETURN;
    END;

    SET @UserId = LOWER(CAST(NEWID() AS NVARCHAR(36)));
    DECLARE @SecStamp NVARCHAR(MAX) = CAST(NEWID() AS NVARCHAR(36));
    DECLARE @ConcStamp NVARCHAR(MAX) = CAST(NEWID() AS NVARCHAR(36));

    INSERT INTO dbo.AspNetUsers
    (
        Id,
        UserName,
        NormalizedUserName,
        Email,
        NormalizedEmail,
        EmailConfirmed,
        PasswordHash,
        SecurityStamp,
        ConcurrencyStamp,
        PhoneNumber,
        PhoneNumberConfirmed,
        TwoFactorEnabled,
        LockoutEnd,
        LockoutEnabled,
        AccessFailedCount,
        RefreshToken,
        RefreshTokenExpiry,
        FarmId,
        FarmName,
        IsStaff,
        IsAdmin,
        AdminTitle,
        Permissions,
        FeaturePermissions,
        IsSubscriber,
        FirstName,
        LastName,
        CustomerId
    )
    VALUES
    (
        @UserId,
        @UserName,
        UPPER(@UserName),
        @Email,
        UPPER(@Email),
        1,
        @PasswordHash,
        @SecStamp,
        @ConcStamp,
        NULL,
        0,
        0,
        NULL,
        1,
        0,
        NULL,
        NULL,
        @FarmId,
        N'Platform (developer portal)',
        0,
        1,
        NULL,
        NULL,
        NULL,
        0,
        N'Developer',
        N'Portal',
        NULL
    );

    DECLARE @R1 NVARCHAR(450) = (SELECT Id FROM dbo.AspNetRoles WHERE NormalizedName = N'SYSTEMADMIN');
    DECLARE @R2 NVARCHAR(450) = (SELECT Id FROM dbo.AspNetRoles WHERE NormalizedName = N'PLATFORMOWNER');
    INSERT INTO dbo.AspNetUserRoles (UserId, RoleId) VALUES (@UserId, @R1);
    INSERT INTO dbo.AspNetUserRoles (UserId, RoleId) VALUES (@UserId, @R2);

    COMMIT TRANSACTION;
    PRINT N'Created user ''' + @UserName + N''' with farm ' + @FarmId + N'.';
    PRINT N'Default password: DevDeveloperLogin!23 — change it after first login.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

GO
