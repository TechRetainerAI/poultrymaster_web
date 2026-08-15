-- =============================================================================
-- 201_IamPhase2Writes.sql
--
-- Identity & Access Management, phase 2: custom roles, per-company assignment
-- and per-user overrides. This is the first migration in the IAM set that lets
-- anything be written.
--
-- Organization ownership
-- ----------------------
-- Phase 1 keyed custom roles off the caller's own id, which was wrong for staff.
-- fnIam_OrgOwner resolves it properly, reusing the model migration 117 settled
-- on: an owner (IsStaff = 0) is their own organization; a staff member belongs
-- to the owner of their primary farm. Farms.Id is the real PK and Farms.FarmId
-- is vestigial, so both are matched — 117 keys on one and 027 on the other.
--
-- What is still NOT enforced
-- --------------------------
-- Nothing here makes the Farm API check permissions before acting. Assigning a
-- role changes what the UI offers and what /Iam reports; it does not yet stop a
-- crafted request. That is phase 3, and IAM stays additive until then — see
-- lib/iam/resolve.ts.
--
-- Idempotent: CREATE OR ALTER throughout.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Organization owner for any user.
-- -----------------------------------------------------------------------------
CREATE OR ALTER FUNCTION dbo.fnIam_OrgOwner (@UserId NVARCHAR(450))
RETURNS NVARCHAR(450)
AS
BEGIN
    IF @UserId IS NULL RETURN NULL;

    DECLARE @isStaff BIT, @primaryFarm NVARCHAR(450);
    SELECT @isStaff = ISNULL(IsStaff, 0), @primaryFarm = FarmId
    FROM dbo.AspNetUsers WHERE Id = @UserId;

    -- Unknown user, or an owner: they are their own organization.
    IF @isStaff IS NULL OR @isStaff = 0 RETURN @UserId;

    DECLARE @owner NVARCHAR(450) = NULL;
    IF @primaryFarm IS NOT NULL AND @primaryFarm <> N''
    BEGIN
        SELECT TOP 1 @owner = f.OwnerUserId
        FROM dbo.Farms f
        WHERE (f.Id = @primaryFarm OR f.FarmId = @primaryFarm)
          AND f.OwnerUserId IS NOT NULL AND f.OwnerUserId <> N'';
    END

    -- Staff with no resolvable farm fall back to themselves rather than NULL, so
    -- they see the built-in roles instead of an empty screen.
    RETURN ISNULL(@owner, @UserId);
END
GO

-- -----------------------------------------------------------------------------
-- 2. Role list, now organization-aware and carrying a people count.
--
--    The count is restricted to the caller's own organization: built-in roles
--    are shared across every customer, so an unrestricted count would report
--    other organizations' numbers.
-- -----------------------------------------------------------------------------
--    The parameter keeps its phase-1 name so the API keeps working against a
--    database that has 200 but not yet 201. It always held the CALLER's id; what
--    changes here is that the caller is now resolved to their organization owner
--    instead of being treated as one.
CREATE OR ALTER PROCEDURE dbo.spIam_GetRoles
    @OwnerUserId NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @org NVARCHAR(450) = dbo.fnIam_OrgOwner(@OwnerUserId);
    DECLARE @now DATETIME2 = SYSUTCDATETIME();

    -- Everyone whose organization is this one. Used only to scope the count.
    --
    -- Written set-based rather than as fnIam_OrgOwner(u.Id) = @org: a scalar UDF
    -- in a predicate runs once per row of AspNetUsers, and this loads every time
    -- the Access tab is opened. Same rule as the function, expressed as a join —
    -- an owner is their own organization; a staff member belongs to the owner of
    -- their primary farm. DISTINCT because Farms matches on either Id or FarmId.
    DECLARE @members TABLE (UserId NVARCHAR(450) PRIMARY KEY);
    IF @org IS NOT NULL
    BEGIN
        INSERT INTO @members (UserId)
        SELECT DISTINCT u.Id
        FROM dbo.AspNetUsers u
        LEFT JOIN dbo.Farms f
               ON (f.Id = u.FarmId OR f.FarmId = u.FarmId)
        WHERE (ISNULL(u.IsStaff, 0) = 0 AND u.Id = @org)
           OR (ISNULL(u.IsStaff, 0) = 1 AND f.OwnerUserId = @org);
    END

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
        END,
        AssignedUserCount = (
            SELECT COUNT(DISTINCT ur.UserId)
            FROM dbo.IamUserRoles ur
            JOIN @members m ON m.UserId = ur.UserId
            WHERE ur.RoleId = r.RoleId
              AND (ur.ExpiresAt IS NULL OR ur.ExpiresAt > @now)
        )
    FROM dbo.IamRoles r
    WHERE r.IsActive = 1
      AND (r.OwnerUserId IS NULL OR (@org IS NOT NULL AND r.OwnerUserId = @org))
    ORDER BY r.IsSystem DESC, r.Name;
END
GO

-- -----------------------------------------------------------------------------
-- 3. Create or rename a custom role.
--
--    Built-in roles are never editable: they are shared across organizations, so
--    letting one customer rename "Accountant" would rename it for everybody.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spIam_Role_Save
    @RoleId       INT = NULL,          -- NULL creates
    @CallerUserId NVARCHAR(450),
    @Name         NVARCHAR(100),
    @Description  NVARCHAR(400) = NULL,
    @CompanyType  NVARCHAR(20)  = NULL,
    @CopyFromRoleId INT = NULL         -- clone this role's grants on create
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Name IS NULL OR LTRIM(RTRIM(@Name)) = N''
    BEGIN
        RAISERROR (N'A role name is required.', 16, 1);
        RETURN;
    END

    DECLARE @org NVARCHAR(450) = dbo.fnIam_OrgOwner(@CallerUserId);
    SET @Name = LTRIM(RTRIM(@Name));

    IF @RoleId IS NOT NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM dbo.IamRoles WHERE RoleId = @RoleId AND IsSystem = 1)
        BEGIN
            RAISERROR (N'Built-in roles cannot be edited. Duplicate it and change the copy instead.', 16, 1);
            RETURN;
        END
        IF NOT EXISTS (SELECT 1 FROM dbo.IamRoles WHERE RoleId = @RoleId AND OwnerUserId = @org)
        BEGIN
            RAISERROR (N'That role does not belong to your organization.', 16, 1);
            RETURN;
        END

        UPDATE dbo.IamRoles
        SET Name = @Name, Description = @Description, CompanyType = @CompanyType,
            UpdatedAt = SYSUTCDATETIME()
        WHERE RoleId = @RoleId;

        SELECT RoleId = @RoleId;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM dbo.IamRoles WHERE OwnerUserId = @org AND Name = @Name)
    BEGIN
        RAISERROR (N'A role with that name already exists.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    INSERT INTO dbo.IamRoles (RoleKey, OwnerUserId, Name, Description, CompanyType, IsSystem, IsSuperuser, IsActive, CreatedBy)
    VALUES (NULL, @org, @Name, @Description, @CompanyType, 0, 0, 1, @CallerUserId);

    DECLARE @newId INT = CAST(SCOPE_IDENTITY() AS INT);

    -- Cloning is how a custom role is meant to start: nine built-ins are a better
    -- starting point than 340 empty checkboxes. A superuser source expands to the
    -- whole catalog, since it holds no rows of its own.
    IF @CopyFromRoleId IS NOT NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM dbo.IamRoles WHERE RoleId = @CopyFromRoleId AND IsSuperuser = 1)
            INSERT INTO dbo.IamRolePermissions (RoleId, PermissionKey)
            SELECT @newId, PermissionKey FROM dbo.IamPermissions;
        ELSE
            INSERT INTO dbo.IamRolePermissions (RoleId, PermissionKey)
            SELECT @newId, rp.PermissionKey
            FROM dbo.IamRolePermissions rp
            WHERE rp.RoleId = @CopyFromRoleId;
    END

    COMMIT TRANSACTION;

    SELECT RoleId = @newId;
END
GO

-- -----------------------------------------------------------------------------
-- 4. Delete a custom role. Refuses while anyone still holds it — silently
--    stripping people of access is exactly the surprise IAM exists to prevent.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spIam_Role_Delete
    @RoleId INT,
    @CallerUserId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @org NVARCHAR(450) = dbo.fnIam_OrgOwner(@CallerUserId);

    IF EXISTS (SELECT 1 FROM dbo.IamRoles WHERE RoleId = @RoleId AND IsSystem = 1)
    BEGIN
        RAISERROR (N'Built-in roles cannot be deleted.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.IamRoles WHERE RoleId = @RoleId AND OwnerUserId = @org)
    BEGIN
        RAISERROR (N'That role does not belong to your organization.', 16, 1);
        RETURN;
    END

    DECLARE @held INT = (SELECT COUNT(*) FROM dbo.IamUserRoles WHERE RoleId = @RoleId);
    IF @held > 0
    BEGIN
        DECLARE @msg NVARCHAR(200) =
            CONCAT(N'This role is still assigned to ', @held, N' person(s). Remove it from them first.');
        RAISERROR (@msg, 16, 1);
        RETURN;
    END

    -- IamRolePermissions cascades on the FK.
    DELETE FROM dbo.IamRoles WHERE RoleId = @RoleId;
END
GO

-- -----------------------------------------------------------------------------
-- 5. Replace a custom role's grants wholesale.
--
--    The matrix edits the full set, so a diff-based API would just be the same
--    thing with more round trips. Unknown keys are dropped rather than erroring:
--    the FK would reject them anyway, and a stale client should not be able to
--    fail the whole save.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spIam_RolePermissions_Set
    @RoleId INT,
    @CallerUserId NVARCHAR(450),
    @PermissionKeys NVARCHAR(MAX) = NULL   -- comma separated; NULL or '' clears
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @org NVARCHAR(450) = dbo.fnIam_OrgOwner(@CallerUserId);

    IF EXISTS (SELECT 1 FROM dbo.IamRoles WHERE RoleId = @RoleId AND IsSystem = 1)
    BEGIN
        RAISERROR (N'Built-in role permissions cannot be changed. Duplicate the role and edit the copy.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.IamRoles WHERE RoleId = @RoleId AND OwnerUserId = @org)
    BEGIN
        RAISERROR (N'That role does not belong to your organization.', 16, 1);
        RETURN;
    END

    DECLARE @wanted TABLE (PermissionKey NVARCHAR(120) PRIMARY KEY);
    IF @PermissionKeys IS NOT NULL AND LTRIM(RTRIM(@PermissionKeys)) <> N''
    BEGIN
        INSERT INTO @wanted (PermissionKey)
        SELECT DISTINCT p.PermissionKey
        FROM STRING_SPLIT(@PermissionKeys, N',') s
        JOIN dbo.IamPermissions p ON p.PermissionKey = LTRIM(RTRIM(s.value));
    END

    BEGIN TRANSACTION;

    DELETE rp FROM dbo.IamRolePermissions rp
    WHERE rp.RoleId = @RoleId
      AND NOT EXISTS (SELECT 1 FROM @wanted w WHERE w.PermissionKey = rp.PermissionKey);

    INSERT INTO dbo.IamRolePermissions (RoleId, PermissionKey)
    SELECT @RoleId, w.PermissionKey
    FROM @wanted w
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.IamRolePermissions rp
        WHERE rp.RoleId = @RoleId AND rp.PermissionKey = w.PermissionKey);

    COMMIT TRANSACTION;

    SELECT GrantedCount = (SELECT COUNT(*) FROM dbo.IamRolePermissions WHERE RoleId = @RoleId);
END
GO

-- -----------------------------------------------------------------------------
-- 6. Assign a role to someone, in one company or across the organization.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spIam_UserRole_Assign
    @UserId     NVARCHAR(450),
    @RoleId     INT,
    @FarmId     NVARCHAR(450) = NULL,   -- NULL = every company in the organization
    @AssignedBy NVARCHAR(450) = NULL,
    @ExpiresAt  DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.IamRoles WHERE RoleId = @RoleId AND IsActive = 1)
    BEGIN
        RAISERROR (N'That role does not exist.', 16, 1);
        RETURN;
    END

    IF @ExpiresAt IS NOT NULL AND @ExpiresAt <= SYSUTCDATETIME()
    BEGIN
        RAISERROR (N'The expiry date must be in the future.', 16, 1);
        RETURN;
    END

    -- Re-assigning an existing pairing updates its expiry rather than failing on
    -- the unique index — "extend their cover for another week" is the common case.
    IF EXISTS (
        SELECT 1 FROM dbo.IamUserRoles
        WHERE UserId = @UserId AND RoleId = @RoleId
          AND ((FarmId IS NULL AND @FarmId IS NULL) OR FarmId = @FarmId))
    BEGIN
        UPDATE dbo.IamUserRoles
        SET ExpiresAt = @ExpiresAt, AssignedBy = @AssignedBy, AssignedAt = SYSUTCDATETIME()
        WHERE UserId = @UserId AND RoleId = @RoleId
          AND ((FarmId IS NULL AND @FarmId IS NULL) OR FarmId = @FarmId);
    END
    ELSE
    BEGIN
        INSERT INTO dbo.IamUserRoles (UserId, RoleId, FarmId, AssignedBy, ExpiresAt)
        VALUES (@UserId, @RoleId, @FarmId, @AssignedBy, @ExpiresAt);
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.spIam_UserRole_Revoke
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.IamUserRoles WHERE Id = @Id;
END
GO

-- -----------------------------------------------------------------------------
-- 7. Per-user overrides.
--
--    A reason is mandatory. An override is drift by design — the whole point of
--    recording why is so the next person to review access can tell a deliberate
--    exception from an accident.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spIam_UserPermission_Set
    @UserId        NVARCHAR(450),
    @FarmId        NVARCHAR(450) = NULL,
    @PermissionKey NVARCHAR(120),
    @Effect        NVARCHAR(10),          -- Allow | Deny
    @Reason        NVARCHAR(400),
    @GrantedBy     NVARCHAR(450) = NULL,
    @ExpiresAt     DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Effect NOT IN (N'Allow', N'Deny')
    BEGIN
        RAISERROR (N'Effect must be Allow or Deny.', 16, 1);
        RETURN;
    END

    IF @Reason IS NULL OR LTRIM(RTRIM(@Reason)) = N''
    BEGIN
        RAISERROR (N'A reason is required for a permission override.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.IamPermissions WHERE PermissionKey = @PermissionKey)
    BEGIN
        RAISERROR (N'Unknown permission.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1 FROM dbo.IamUserPermissions
        WHERE UserId = @UserId AND PermissionKey = @PermissionKey
          AND ((FarmId IS NULL AND @FarmId IS NULL) OR FarmId = @FarmId))
    BEGIN
        UPDATE dbo.IamUserPermissions
        SET Effect = @Effect, Reason = @Reason, GrantedBy = @GrantedBy,
            GrantedAt = SYSUTCDATETIME(), ExpiresAt = @ExpiresAt
        WHERE UserId = @UserId AND PermissionKey = @PermissionKey
          AND ((FarmId IS NULL AND @FarmId IS NULL) OR FarmId = @FarmId);
    END
    ELSE
    BEGIN
        INSERT INTO dbo.IamUserPermissions (UserId, FarmId, PermissionKey, Effect, Reason, GrantedBy, ExpiresAt)
        VALUES (@UserId, @FarmId, @PermissionKey, @Effect, @Reason, @GrantedBy, @ExpiresAt);
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.spIam_UserPermission_Clear
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE FROM dbo.IamUserPermissions WHERE Id = @Id;
END
GO

-- Overrides for one person, in one company. Expired rows are returned too, and
-- flagged: an override that quietly lapsed is something an admin needs to see,
-- not something to hide.
CREATE OR ALTER PROCEDURE dbo.spIam_GetUserOverrides
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @now DATETIME2 = SYSUTCDATETIME();

    SELECT
        up.Id,
        up.PermissionKey,
        up.Effect,
        up.Reason,
        up.GrantedBy,
        up.GrantedAt,
        up.ExpiresAt,
        up.FarmId,
        IsOrgWide = CAST(CASE WHEN up.FarmId IS NULL THEN 1 ELSE 0 END AS BIT),
        HasExpired = CAST(CASE WHEN up.ExpiresAt IS NOT NULL AND up.ExpiresAt <= @now THEN 1 ELSE 0 END AS BIT),
        p.ResourceLabel,
        p.[Action],
        p.Module,
        p.PermissionGroup
    FROM dbo.IamUserPermissions up
    JOIN dbo.IamPermissions p ON p.PermissionKey = up.PermissionKey
    WHERE up.UserId = @UserId
      AND (up.FarmId IS NULL OR (@FarmId IS NOT NULL AND up.FarmId = @FarmId))
    ORDER BY up.Effect, p.Module, p.SortOrder;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.fnIam_OrgOwner              TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_GetRoles              TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_Role_Save             TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_Role_Delete           TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_RolePermissions_Set   TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_UserRole_Assign       TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_UserRole_Revoke       TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_UserPermission_Set    TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_UserPermission_Clear  TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_GetUserOverrides      TO [Techretainer];
    PRINT N'201: granted EXECUTE to Techretainer.';
END
GO

PRINT N'201_IamPhase2Writes.sql complete.';
GO
