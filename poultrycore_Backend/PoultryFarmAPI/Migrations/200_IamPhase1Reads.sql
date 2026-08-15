-- =============================================================================
-- 200_IamPhase1Reads.sql
--
-- Identity & Access Management, phase 1: the read endpoints behind the Business
-- Setup → Access tab, plus the bootstrap that makes the tab reachable at all.
--
-- The bootstrap
-- -------------
-- Migration 199 created the roles but assigned none of them, so nobody held
-- office.access.view and the API would have refused to show anyone else's
-- permissions - including to the person who owns the account. This assigns:
--
--   AspNetUsers.IsStaff = 0                -> Owner              (org-wide)
--   AspNetUsers.IsStaff = 1 AND IsAdmin = 1 -> Organization Admin (org-wide)
--
-- which is exactly what hooks/use-permissions.ts already treats as an admin
-- today (`isAdmin = isAdminFlag || hasAdminRole || isSubscriber || !isStaff`).
-- Nobody gains or loses anything they did not already have; the existing rule
-- is simply now written down somewhere the server can read it.
--
-- Idempotent: CREATE OR ALTER throughout, and the bootstrap only inserts
-- assignments that are missing.
-- =============================================================================

SET NOCOUNT ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Bootstrap assignments.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.AspNetUsers','U') IS NOT NULL AND OBJECT_ID('dbo.IamUserRoles','U') IS NOT NULL
BEGIN
    DECLARE @ownerRoleId INT = (SELECT RoleId FROM dbo.IamRoles WHERE RoleKey = N'sys-owner');
    DECLARE @orgAdminRoleId INT = (SELECT RoleId FROM dbo.IamRoles WHERE RoleKey = N'sys-org-admin');

    -- Account owners -> Owner, org-wide (FarmId NULL).
    IF @ownerRoleId IS NOT NULL
    BEGIN
        INSERT INTO dbo.IamUserRoles (UserId, RoleId, FarmId, AssignedBy)
        SELECT u.Id, @ownerRoleId, NULL, N'migration-200'
        FROM dbo.AspNetUsers u
        WHERE ISNULL(u.IsStaff, 0) = 0
          AND NOT EXISTS (
              SELECT 1 FROM dbo.IamUserRoles ur
              WHERE ur.UserId = u.Id AND ur.RoleId = @ownerRoleId AND ur.FarmId IS NULL);

        PRINT CONCAT(N'200: ', @@ROWCOUNT, N' account owner(s) assigned the Owner role.');
    END

    -- Staff explicitly flagged admin on their account -> Organization Admin.
    -- IsAdmin is an EF-managed column on AspNetUsers, so it is referenced through
    -- dynamic SQL: a database that predates it must not fail to parse this batch.
    IF @orgAdminRoleId IS NOT NULL AND COL_LENGTH('dbo.AspNetUsers', 'IsAdmin') IS NOT NULL
    BEGIN
        DECLARE @sql NVARCHAR(MAX) = N'
            INSERT INTO dbo.IamUserRoles (UserId, RoleId, FarmId, AssignedBy)
            SELECT u.Id, @RoleId, NULL, N''migration-200''
            FROM dbo.AspNetUsers u
            WHERE ISNULL(u.IsStaff, 0) = 1
              AND ISNULL(u.IsAdmin, 0) = 1
              AND NOT EXISTS (
                  SELECT 1 FROM dbo.IamUserRoles ur
                  WHERE ur.UserId = u.Id AND ur.RoleId = @RoleId AND ur.FarmId IS NULL);
            SELECT @Rows = @@ROWCOUNT;';

        DECLARE @rows INT = 0;
        EXEC sp_executesql @sql,
             N'@RoleId INT, @Rows INT OUTPUT',
             @RoleId = @orgAdminRoleId, @Rows = @rows OUTPUT;

        PRINT CONCAT(N'200: ', @rows, N' staff admin(s) assigned the Organization Admin role.');
    END
END
GO

-- -----------------------------------------------------------------------------
-- 2. Role list.
--
--    Built-in roles (OwnerUserId NULL) are visible to every organization; custom
--    roles only to the organization that owns them.
--
--    PermissionCount is returned; an assigned-people count deliberately is NOT.
--    Built-in roles are shared across organizations, so a global assignment count
--    would report other customers' numbers. Counting people needs the caller's
--    organization membership, which lives in the Login API - that arrives in
--    phase 2 alongside the assignment UI.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spIam_GetRoles
    @OwnerUserId NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        r.RoleId,
        r.RoleKey,
        r.Name,
        r.Description,
        r.CompanyType,
        r.IsSystem,
        r.IsSuperuser,
        r.IsActive,
        PermissionCount = CASE
            WHEN r.IsSuperuser = 1 THEN (SELECT COUNT(*) FROM dbo.IamPermissions)
            ELSE (SELECT COUNT(*) FROM dbo.IamRolePermissions rp WHERE rp.RoleId = r.RoleId)
        END
    FROM dbo.IamRoles r
    WHERE r.IsActive = 1
      AND (r.OwnerUserId IS NULL OR (@OwnerUserId IS NOT NULL AND r.OwnerUserId = @OwnerUserId))
    ORDER BY r.IsSystem DESC, r.RoleId;
END
GO

-- -----------------------------------------------------------------------------
-- 3. The keys one role grants.
--
--    A superuser role holds the whole catalog rather than rows in
--    IamRolePermissions, so it is expanded here - otherwise the matrix would
--    render the Owner as having no permissions at all.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spIam_GetRolePermissions
    @RoleId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM dbo.IamRoles WHERE RoleId = @RoleId AND IsSuperuser = 1)
    BEGIN
        SELECT PermissionKey FROM dbo.IamPermissions ORDER BY PermissionKey;
        RETURN;
    END

    SELECT rp.PermissionKey
    FROM dbo.IamRolePermissions rp
    WHERE rp.RoleId = @RoleId
    ORDER BY rp.PermissionKey;
END
GO

-- -----------------------------------------------------------------------------
-- 4. The roles one person holds, in one company.
--
--    Org-wide assignments (FarmId NULL) always apply; company assignments only
--    for the company being asked about. Expired assignments are excluded, which
--    is why this cannot simply be read off IamUserRoles by the client.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spIam_GetUserRoles
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @now DATETIME2 = SYSUTCDATETIME();

    SELECT
        ur.Id,
        r.RoleId,
        r.RoleKey,
        r.Name,
        r.Description,
        r.IsSystem,
        r.IsSuperuser,
        ur.FarmId,
        IsOrgWide = CAST(CASE WHEN ur.FarmId IS NULL THEN 1 ELSE 0 END AS BIT),
        ur.AssignedBy,
        ur.AssignedAt,
        ur.ExpiresAt
    FROM dbo.IamUserRoles ur
    JOIN dbo.IamRoles r ON r.RoleId = ur.RoleId
    WHERE ur.UserId = @UserId
      AND r.IsActive = 1
      AND (ur.ExpiresAt IS NULL OR ur.ExpiresAt > @now)
      AND (ur.FarmId IS NULL OR (@FarmId IS NOT NULL AND ur.FarmId = @FarmId))
    ORDER BY r.IsSystem DESC, r.Name;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spIam_GetRoles           TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_GetRolePermissions TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_GetUserRoles       TO [Techretainer];
    PRINT N'200: granted EXECUTE to Techretainer.';
END
GO

PRINT N'200_IamPhase1Reads.sql complete.';
GO
