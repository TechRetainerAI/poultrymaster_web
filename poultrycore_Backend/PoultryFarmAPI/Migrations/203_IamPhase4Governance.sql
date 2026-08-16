-- =============================================================================
-- 203_IamPhase4Governance.sql
--
-- Identity & Access Management, phase 4: sessions, security policy, the change
-- history, and access review.
--
-- Four things, and why each earns its place
-- -----------------------------------------
-- 1. IamSessions + IamUserSecurity. Today the only way to deal with a lost
--    laptop is to change someone's password and hope. This records where a
--    person is signed in and gives an admin a "sign out everywhere" that the API
--    can actually honour: revoking stamps TokensValidFrom, and any JWT issued
--    before that instant stops being accepted.
--
-- 2. IamAccessAudit, written by TRIGGERS rather than by the stored procedures.
--    A trigger cannot be bypassed by a future proc, a manual UPDATE or a fix-up
--    script, which is exactly the property an access log needs. Attribution
--    comes from the rows' own AssignedBy / GrantedBy / CreatedBy columns, which
--    the phase-2 procs already set.
--
-- 3. IamPolicies. Password and session rules per organization. NOTE: this
--    migration STORES them; enforcing password rules happens in the Login API at
--    registration and password-change time, which is a separate change. The
--    Access tab says so rather than implying a rule is live when it is not.
--
-- 4. IamAccessReviews. A per-person attestation - "yes, this person still needs
--    this access, confirmed by me, on this date". Deliberately not a campaign
--    system: the useful part is the record and the staleness, not the workflow.
--
-- Idempotent: guarded CREATE TABLE, CREATE OR ALTER for procs and triggers.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.IamSessions','U') IS NULL
BEGIN
    CREATE TABLE dbo.IamSessions (
        SessionId   NVARCHAR(100) NOT NULL PRIMARY KEY,   -- opaque id minted at sign-in
        UserId      NVARCHAR(450) NOT NULL,
        FarmId      NVARCHAR(450) NULL,
        IpAddress   NVARCHAR(64)  NULL,
        UserAgent   NVARCHAR(400) NULL,
        Device      NVARCHAR(120) NULL,                   -- friendly summary of UserAgent
        CreatedAt   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        LastSeenAt  DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        RevokedAt   DATETIME2 NULL,
        RevokedBy   NVARCHAR(450) NULL
    );
    CREATE INDEX IX_IamSessions_User ON dbo.IamSessions (UserId, LastSeenAt DESC);
    PRINT N'203: created dbo.IamSessions.';
END
GO

-- One row per user. TokensValidFrom is the "sign out everywhere" watermark.
IF OBJECT_ID('dbo.IamUserSecurity','U') IS NULL
BEGIN
    CREATE TABLE dbo.IamUserSecurity (
        UserId                NVARCHAR(450) NOT NULL PRIMARY KEY,
        TokensValidFrom       DATETIME2 NULL,
        LastPasswordChangeAt  DATETIME2 NULL,
        MfaRequired           BIT NOT NULL DEFAULT 0,
        UpdatedAt             DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        UpdatedBy             NVARCHAR(450) NULL
    );
    PRINT N'203: created dbo.IamUserSecurity.';
END
GO

IF OBJECT_ID('dbo.IamAccessAudit','U') IS NULL
BEGIN
    CREATE TABLE dbo.IamAccessAudit (
        Id          BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        OccurredAt  DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        Entity      NVARCHAR(40)  NOT NULL,   -- Role | RolePermission | UserRole | UserPermission
        Operation   NVARCHAR(10)  NOT NULL,   -- Insert | Update | Delete
        SubjectId   NVARCHAR(450) NULL,       -- the person whose access changed
        ActorId     NVARCHAR(450) NULL,       -- who did it, per the row's own attribution
        FarmId      NVARCHAR(450) NULL,
        Detail      NVARCHAR(400) NULL
    );
    CREATE INDEX IX_IamAccessAudit_When ON dbo.IamAccessAudit (OccurredAt DESC);
    CREATE INDEX IX_IamAccessAudit_Subject ON dbo.IamAccessAudit (SubjectId, OccurredAt DESC);
    PRINT N'203: created dbo.IamAccessAudit.';
END
GO

-- Policy is per organization (the owner user id), matching how roles are scoped.
IF OBJECT_ID('dbo.IamPolicies','U') IS NULL
BEGIN
    CREATE TABLE dbo.IamPolicies (
        OwnerUserId            NVARCHAR(450) NOT NULL PRIMARY KEY,
        PasswordMinLength      INT NOT NULL DEFAULT 8,
        PasswordRequireUpper   BIT NOT NULL DEFAULT 1,
        PasswordRequireDigit   BIT NOT NULL DEFAULT 1,
        PasswordRequireSymbol  BIT NOT NULL DEFAULT 0,
        PasswordExpiryDays     INT NOT NULL DEFAULT 0,     -- 0 = never
        SessionIdleMinutes     INT NOT NULL DEFAULT 0,     -- 0 = no idle timeout
        SessionMaxHours        INT NOT NULL DEFAULT 0,     -- 0 = no cap
        RequireMfaForAdmins    BIT NOT NULL DEFAULT 0,
        DormantAfterDays       INT NOT NULL DEFAULT 90,
        AccessReviewDays       INT NOT NULL DEFAULT 180,   -- how long a review stays fresh
        UpdatedAt              DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        UpdatedBy              NVARCHAR(450) NULL
    );
    PRINT N'203: created dbo.IamPolicies.';
END
GO

IF OBJECT_ID('dbo.IamAccessReviews','U') IS NULL
BEGIN
    CREATE TABLE dbo.IamAccessReviews (
        Id         INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        UserId     NVARCHAR(450) NOT NULL,
        FarmId     NVARCHAR(450) NULL,
        Decision   NVARCHAR(20)  NOT NULL,   -- Confirmed | Flagged
        Note       NVARCHAR(400) NULL,
        ReviewedBy NVARCHAR(450) NULL,
        ReviewedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT CK_IamAccessReviews_Decision CHECK (Decision IN (N'Confirmed', N'Flagged'))
    );
    CREATE INDEX IX_IamAccessReviews_User ON dbo.IamAccessReviews (UserId, ReviewedAt DESC);
    PRINT N'203: created dbo.IamAccessReviews.';
END
GO

-- -----------------------------------------------------------------------------
-- 2. Change history, by trigger.
--
--    Triggers rather than proc-side logging: a proc added next year, a manual
--    UPDATE during a support call, or a fix-up script all get recorded too. An
--    access log that only sees the paths we remembered to instrument is not
--    worth having.
-- -----------------------------------------------------------------------------
CREATE OR ALTER TRIGGER dbo.trIamUserRoles_Audit
ON dbo.IamUserRoles
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.IamAccessAudit (Entity, Operation, SubjectId, ActorId, FarmId, Detail)
    SELECT N'UserRole',
           CASE WHEN EXISTS (SELECT 1 FROM deleted d2 WHERE d2.Id = i.Id) THEN N'Update' ELSE N'Insert' END,
           i.UserId, i.AssignedBy, i.FarmId,
           CONCAT(N'Role ', ISNULL(r.Name, CONCAT(N'#', i.RoleId)),
                  CASE WHEN i.FarmId IS NULL THEN N' (all companies)' ELSE N'' END,
                  CASE WHEN i.ExpiresAt IS NULL THEN N'' ELSE CONCAT(N' until ', CONVERT(NVARCHAR(20), i.ExpiresAt, 120)) END)
    FROM inserted i
    LEFT JOIN dbo.IamRoles r ON r.RoleId = i.RoleId;

    INSERT INTO dbo.IamAccessAudit (Entity, Operation, SubjectId, ActorId, FarmId, Detail)
    SELECT N'UserRole', N'Delete', d.UserId, d.AssignedBy, d.FarmId,
           CONCAT(N'Role ', ISNULL(r.Name, CONCAT(N'#', d.RoleId)), N' removed')
    FROM deleted d
    LEFT JOIN dbo.IamRoles r ON r.RoleId = d.RoleId
    WHERE NOT EXISTS (SELECT 1 FROM inserted i2 WHERE i2.Id = d.Id);
END
GO

CREATE OR ALTER TRIGGER dbo.trIamUserPermissions_Audit
ON dbo.IamUserPermissions
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.IamAccessAudit (Entity, Operation, SubjectId, ActorId, FarmId, Detail)
    SELECT N'UserPermission',
           CASE WHEN EXISTS (SELECT 1 FROM deleted d2 WHERE d2.Id = i.Id) THEN N'Update' ELSE N'Insert' END,
           i.UserId, i.GrantedBy, i.FarmId,
           CONCAT(i.Effect, N' ', i.PermissionKey, N' - ', ISNULL(i.Reason, N'no reason given'))
    FROM inserted i;

    INSERT INTO dbo.IamAccessAudit (Entity, Operation, SubjectId, ActorId, FarmId, Detail)
    SELECT N'UserPermission', N'Delete', d.UserId, d.GrantedBy, d.FarmId,
           CONCAT(N'Exception removed: ', d.Effect, N' ', d.PermissionKey)
    FROM deleted d
    WHERE NOT EXISTS (SELECT 1 FROM inserted i2 WHERE i2.Id = d.Id);
END
GO

CREATE OR ALTER TRIGGER dbo.trIamRoles_Audit
ON dbo.IamRoles
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.IamAccessAudit (Entity, Operation, SubjectId, ActorId, Detail)
    SELECT N'Role',
           CASE WHEN EXISTS (SELECT 1 FROM deleted d2 WHERE d2.RoleId = i.RoleId) THEN N'Update' ELSE N'Insert' END,
           i.OwnerUserId, ISNULL(i.CreatedBy, i.OwnerUserId),
           CONCAT(N'Role "', i.Name, N'"')
    FROM inserted i
    WHERE i.IsSystem = 0;   -- built-ins only change when a migration runs

    INSERT INTO dbo.IamAccessAudit (Entity, Operation, SubjectId, ActorId, Detail)
    SELECT N'Role', N'Delete', d.OwnerUserId, d.CreatedBy, CONCAT(N'Role "', d.Name, N'" deleted')
    FROM deleted d
    WHERE NOT EXISTS (SELECT 1 FROM inserted i2 WHERE i2.RoleId = d.RoleId)
      AND d.IsSystem = 0;
END
GO

-- Role grants change wholesale: spIam_RolePermissions_Set deletes and reinserts
-- the whole set, so a row-per-key trigger would write hundreds of entries for one
-- save and bury everything else. One summary row per statement instead, which is
-- what a reader actually wants: "this role's permissions changed, by this much".
CREATE OR ALTER TRIGGER dbo.trIamRolePermissions_Audit
ON dbo.IamRolePermissions
AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @added INT = (SELECT COUNT(*) FROM inserted);
    DECLARE @removed INT = (SELECT COUNT(*) FROM deleted);
    IF (@added + @removed) = 0 RETURN;

    DECLARE @roleId INT = COALESCE(
        (SELECT TOP 1 RoleId FROM inserted),
        (SELECT TOP 1 RoleId FROM deleted));

    -- Built-in roles only change when a migration runs; that is not news.
    IF EXISTS (SELECT 1 FROM dbo.IamRoles WHERE RoleId = @roleId AND IsSystem = 1) RETURN;

    INSERT INTO dbo.IamAccessAudit (Entity, Operation, SubjectId, ActorId, Detail)
    SELECT N'RolePermission',
           CASE WHEN @removed = 0 THEN N'Insert' WHEN @added = 0 THEN N'Delete' ELSE N'Update' END,
           r.OwnerUserId, r.CreatedBy,
           CONCAT(N'Permissions on "', r.Name, N'": ', @added, N' granted, ', @removed, N' removed')
    FROM dbo.IamRoles r
    WHERE r.RoleId = @roleId;
END
GO

-- -----------------------------------------------------------------------------
-- 3. Sessions
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spIam_Session_Touch
    @SessionId NVARCHAR(100),
    @UserId    NVARCHAR(450),
    @FarmId    NVARCHAR(450) = NULL,
    @IpAddress NVARCHAR(64)  = NULL,
    @UserAgent NVARCHAR(400) = NULL,
    @Device    NVARCHAR(120) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.IamSessions
    SET LastSeenAt = SYSUTCDATETIME(),
        FarmId     = ISNULL(@FarmId, FarmId),
        IpAddress  = ISNULL(@IpAddress, IpAddress)
    WHERE SessionId = @SessionId;

    IF @@ROWCOUNT = 0
        INSERT INTO dbo.IamSessions (SessionId, UserId, FarmId, IpAddress, UserAgent, Device)
        VALUES (@SessionId, @UserId, @FarmId, @IpAddress, @UserAgent, @Device);
END
GO

CREATE OR ALTER PROCEDURE dbo.spIam_Sessions_Get
    @UserId NVARCHAR(450),
    @IncludeRevoked BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT SessionId, UserId, FarmId, IpAddress, UserAgent, Device,
           CreatedAt, LastSeenAt, RevokedAt, RevokedBy,
           IsActive = CAST(CASE WHEN RevokedAt IS NULL THEN 1 ELSE 0 END AS BIT)
    FROM dbo.IamSessions
    WHERE UserId = @UserId
      AND (@IncludeRevoked = 1 OR RevokedAt IS NULL)
    ORDER BY LastSeenAt DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spIam_Session_Revoke
    @SessionId NVARCHAR(100),
    @RevokedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.IamSessions
    SET RevokedAt = SYSUTCDATETIME(), RevokedBy = @RevokedBy
    WHERE SessionId = @SessionId AND RevokedAt IS NULL;
END
GO

-- "Sign out everywhere". Stamping TokensValidFrom is what makes this real: the
-- API rejects any token issued before that instant, so it works on JWTs already
-- in the wild rather than only on sessions we happen to have a row for.
CREATE OR ALTER PROCEDURE dbo.spIam_RevokeAllSessions
    @UserId    NVARCHAR(450),
    @RevokedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    UPDATE dbo.IamSessions
    SET RevokedAt = SYSUTCDATETIME(), RevokedBy = @RevokedBy
    WHERE UserId = @UserId AND RevokedAt IS NULL;

    IF EXISTS (SELECT 1 FROM dbo.IamUserSecurity WHERE UserId = @UserId)
        UPDATE dbo.IamUserSecurity
        SET TokensValidFrom = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME(), UpdatedBy = @RevokedBy
        WHERE UserId = @UserId;
    ELSE
        INSERT INTO dbo.IamUserSecurity (UserId, TokensValidFrom, UpdatedBy)
        VALUES (@UserId, SYSUTCDATETIME(), @RevokedBy);

    COMMIT TRANSACTION;
END
GO

CREATE OR ALTER PROCEDURE dbo.spIam_GetTokensValidFrom
    @UserId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TokensValidFrom FROM dbo.IamUserSecurity WHERE UserId = @UserId;
END
GO

-- -----------------------------------------------------------------------------
-- 4. Policy
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spIam_Policy_Get
    @CallerUserId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @org NVARCHAR(450) = dbo.fnIam_OrgOwner(@CallerUserId);

    -- Return defaults rather than nothing, so the UI has something to show
    -- before an admin has ever opened the policy screen.
    IF NOT EXISTS (SELECT 1 FROM dbo.IamPolicies WHERE OwnerUserId = @org)
        INSERT INTO dbo.IamPolicies (OwnerUserId) VALUES (@org);

    SELECT OwnerUserId, PasswordMinLength, PasswordRequireUpper, PasswordRequireDigit,
           PasswordRequireSymbol, PasswordExpiryDays, SessionIdleMinutes, SessionMaxHours,
           RequireMfaForAdmins, DormantAfterDays, AccessReviewDays, UpdatedAt, UpdatedBy
    FROM dbo.IamPolicies
    WHERE OwnerUserId = @org;
END
GO

CREATE OR ALTER PROCEDURE dbo.spIam_Policy_Set
    @CallerUserId          NVARCHAR(450),
    @PasswordMinLength     INT,
    @PasswordRequireUpper  BIT,
    @PasswordRequireDigit  BIT,
    @PasswordRequireSymbol BIT,
    @PasswordExpiryDays    INT,
    @SessionIdleMinutes    INT,
    @SessionMaxHours       INT,
    @RequireMfaForAdmins   BIT,
    @DormantAfterDays      INT,
    @AccessReviewDays      INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @PasswordMinLength < 6 OR @PasswordMinLength > 128
    BEGIN
        RAISERROR (N'Minimum password length must be between 6 and 128.', 16, 1);
        RETURN;
    END

    DECLARE @org NVARCHAR(450) = dbo.fnIam_OrgOwner(@CallerUserId);

    IF NOT EXISTS (SELECT 1 FROM dbo.IamPolicies WHERE OwnerUserId = @org)
        INSERT INTO dbo.IamPolicies (OwnerUserId) VALUES (@org);

    UPDATE dbo.IamPolicies
    SET PasswordMinLength = @PasswordMinLength,
        PasswordRequireUpper = @PasswordRequireUpper,
        PasswordRequireDigit = @PasswordRequireDigit,
        PasswordRequireSymbol = @PasswordRequireSymbol,
        PasswordExpiryDays = @PasswordExpiryDays,
        SessionIdleMinutes = @SessionIdleMinutes,
        SessionMaxHours = @SessionMaxHours,
        RequireMfaForAdmins = @RequireMfaForAdmins,
        DormantAfterDays = @DormantAfterDays,
        AccessReviewDays = @AccessReviewDays,
        UpdatedAt = SYSUTCDATETIME(),
        UpdatedBy = @CallerUserId
    WHERE OwnerUserId = @org;
END
GO

-- -----------------------------------------------------------------------------
-- 5. Change history and access review
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spIam_GetAccessAudit
    @CallerUserId NVARCHAR(450),
    @SubjectId    NVARCHAR(450) = NULL,
    @Days         INT = 90,
    @MaxRows      INT = 500
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @org NVARCHAR(450) = dbo.fnIam_OrgOwner(@CallerUserId);
    DECLARE @since DATETIME2 = DATEADD(DAY, -ABS(ISNULL(@Days, 90)), SYSUTCDATETIME());

    -- Same organization-membership rule as spIam_GetRoles, expressed set-based.
    DECLARE @members TABLE (UserId NVARCHAR(450) PRIMARY KEY);
    INSERT INTO @members (UserId)
    SELECT DISTINCT u.Id
    FROM dbo.AspNetUsers u
    LEFT JOIN dbo.Farms f ON (f.Id = u.FarmId OR f.FarmId = u.FarmId)
    WHERE (ISNULL(u.IsStaff, 0) = 0 AND u.Id = @org)
       OR (ISNULL(u.IsStaff, 0) = 1 AND f.OwnerUserId = @org);

    SELECT TOP (@MaxRows)
        a.Id, a.OccurredAt, a.Entity, a.Operation, a.SubjectId, a.ActorId, a.FarmId, a.Detail,
        SubjectName = LTRIM(RTRIM(CONCAT(su.FirstName, N' ', su.LastName))),
        ActorName   = LTRIM(RTRIM(CONCAT(au.FirstName, N' ', au.LastName)))
    FROM dbo.IamAccessAudit a
    LEFT JOIN dbo.AspNetUsers su ON su.Id = a.SubjectId
    LEFT JOIN dbo.AspNetUsers au ON au.Id = a.ActorId
    WHERE a.OccurredAt >= @since
      AND (@SubjectId IS NOT NULL OR EXISTS (SELECT 1 FROM @members m WHERE m.UserId = a.SubjectId))
      AND (@SubjectId IS NULL OR a.SubjectId = @SubjectId)
    ORDER BY a.OccurredAt DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spIam_AccessReview_Record
    @UserId     NVARCHAR(450),
    @FarmId     NVARCHAR(450) = NULL,
    @Decision   NVARCHAR(20),
    @Note       NVARCHAR(400) = NULL,
    @ReviewedBy NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Decision NOT IN (N'Confirmed', N'Flagged')
    BEGIN
        RAISERROR (N'Decision must be Confirmed or Flagged.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.IamAccessReviews (UserId, FarmId, Decision, Note, ReviewedBy)
    VALUES (@UserId, @FarmId, @Decision, @Note, @ReviewedBy);
END
GO

-- The access review screen: everyone in the organization, when their access was
-- last confirmed, when they were last seen, and whether either has gone stale.
CREATE OR ALTER PROCEDURE dbo.spIam_GetAccessReview
    @CallerUserId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @org NVARCHAR(450) = dbo.fnIam_OrgOwner(@CallerUserId);
    DECLARE @now DATETIME2 = SYSUTCDATETIME();

    DECLARE @dormantDays INT = 90, @reviewDays INT = 180;
    SELECT @dormantDays = DormantAfterDays, @reviewDays = AccessReviewDays
    FROM dbo.IamPolicies WHERE OwnerUserId = @org;

    ;WITH members AS (
        SELECT DISTINCT u.Id, u.FirstName, u.LastName, u.Email, u.UserName, ISNULL(u.IsStaff, 0) AS IsStaff
        FROM dbo.AspNetUsers u
        LEFT JOIN dbo.Farms f ON (f.Id = u.FarmId OR f.FarmId = u.FarmId)
        WHERE (ISNULL(u.IsStaff, 0) = 0 AND u.Id = @org)
           OR (ISNULL(u.IsStaff, 0) = 1 AND f.OwnerUserId = @org)
    )
    SELECT
        m.Id AS UserId,
        m.FirstName, m.LastName, m.Email, m.UserName, m.IsStaff,
        RoleCount = (SELECT COUNT(*) FROM dbo.IamUserRoles ur
                     WHERE ur.UserId = m.Id AND (ur.ExpiresAt IS NULL OR ur.ExpiresAt > @now)),
        OverrideCount = (SELECT COUNT(*) FROM dbo.IamUserPermissions up
                         WHERE up.UserId = m.Id AND (up.ExpiresAt IS NULL OR up.ExpiresAt > @now)),
        LastSeenAt = (SELECT MAX(s.LastSeenAt) FROM dbo.IamSessions s WHERE s.UserId = m.Id),
        LastReviewedAt = (SELECT MAX(r.ReviewedAt) FROM dbo.IamAccessReviews r WHERE r.UserId = m.Id),
        LastDecision = (SELECT TOP 1 r.Decision FROM dbo.IamAccessReviews r
                        WHERE r.UserId = m.Id ORDER BY r.ReviewedAt DESC),
        -- Never seen counts as dormant only if we have session history at all;
        -- otherwise every user looks dormant on the day this ships.
        IsDormant = CAST(CASE
            WHEN @dormantDays <= 0 THEN 0
            WHEN NOT EXISTS (SELECT 1 FROM dbo.IamSessions) THEN 0
            WHEN (SELECT MAX(s.LastSeenAt) FROM dbo.IamSessions s WHERE s.UserId = m.Id) IS NULL THEN 1
            WHEN (SELECT MAX(s.LastSeenAt) FROM dbo.IamSessions s WHERE s.UserId = m.Id)
                 < DATEADD(DAY, -@dormantDays, @now) THEN 1
            ELSE 0 END AS BIT),
        ReviewIsStale = CAST(CASE
            WHEN @reviewDays <= 0 THEN 0
            WHEN (SELECT MAX(r.ReviewedAt) FROM dbo.IamAccessReviews r WHERE r.UserId = m.Id) IS NULL THEN 1
            WHEN (SELECT MAX(r.ReviewedAt) FROM dbo.IamAccessReviews r WHERE r.UserId = m.Id)
                 < DATEADD(DAY, -@reviewDays, @now) THEN 1
            ELSE 0 END AS BIT)
    FROM members m
    ORDER BY m.IsStaff DESC, m.FirstName, m.LastName;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spIam_Session_Touch        TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_Sessions_Get         TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_Session_Revoke       TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_RevokeAllSessions    TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_GetTokensValidFrom   TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_Policy_Get           TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_Policy_Set           TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_GetAccessAudit       TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_AccessReview_Record  TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_GetAccessReview      TO [Techretainer];
    PRINT N'203: granted EXECUTE to Techretainer.';
END
GO

PRINT N'203_IamPhase4Governance.sql complete.';
PRINT N'203: NOTE - password rules are STORED here but enforced by the Login API';
PRINT N'203:        at registration and password-change time, which is a separate change.';
GO
