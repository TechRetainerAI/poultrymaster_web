/* ============================================================================
   121_Announcements.sql

   Prompt 4 §7/§15/§16 — Business Office announcements / notifications.

   Org-level announcements (the owner's account IS the organization, so an
   announcement is scoped by OrgOwnerUserId; NULL = platform-wide for every org).
   Per-user read/dismiss/acknowledge state lives in AnnouncementReceipts.

   Idempotent.
   ============================================================================ */

SET NOCOUNT ON; SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;
GO

IF OBJECT_ID('dbo.Announcements','U') IS NULL
BEGIN
    CREATE TABLE dbo.Announcements (
        AnnouncementId  INT IDENTITY(1,1) PRIMARY KEY,
        OrgOwnerUserId  NVARCHAR(450) NULL,                       -- NULL = platform-wide
        Title           NVARCHAR(200) NOT NULL,
        Message         NVARCHAR(2000) NOT NULL,
        Type            NVARCHAR(30)  NOT NULL CONSTRAINT DF_Ann_Type DEFAULT 'Info',
        Priority        INT           NOT NULL CONSTRAINT DF_Ann_Prio DEFAULT 0,
        AudienceRole    NVARCHAR(30)  NULL,                       -- NULL/'All' | 'Admin' | 'Staff'
        TargetFarmId    NVARCHAR(450) NULL,                       -- NULL = all companies
        StartDate       DATETIME2     NULL,
        EndDate         DATETIME2     NULL,
        IsDismissible   BIT           NOT NULL CONSTRAINT DF_Ann_Dismiss DEFAULT 1,
        RequiresAck     BIT           NOT NULL CONSTRAINT DF_Ann_Ack DEFAULT 0,
        ActionLabel     NVARCHAR(80)  NULL,
        ActionUrl       NVARCHAR(400) NULL,
        CreatedBy       NVARCHAR(450) NULL,
        CreatedAt       DATETIME2     NOT NULL CONSTRAINT DF_Ann_Created DEFAULT SYSUTCDATETIME(),
        IsDeleted       BIT           NOT NULL CONSTRAINT DF_Ann_Del DEFAULT 0
    );
    CREATE INDEX IX_Announcements_Org ON dbo.Announcements (OrgOwnerUserId, IsDeleted);
END
GO

IF OBJECT_ID('dbo.AnnouncementReceipts','U') IS NULL
BEGIN
    CREATE TABLE dbo.AnnouncementReceipts (
        AnnouncementId INT           NOT NULL,
        UserId         NVARCHAR(450) NOT NULL,
        ReadAt         DATETIME2     NULL,
        DismissedAt    DATETIME2     NULL,
        AcknowledgedAt DATETIME2     NULL,
        CONSTRAINT PK_AnnouncementReceipts PRIMARY KEY (AnnouncementId, UserId)
    );
END
GO

/* ---- list active announcements for a user (with their state) ------------- */
CREATE OR ALTER PROCEDURE dbo.spAnnouncement_ListForUser
    @UserId         NVARCHAR(450),
    @OrgOwnerUserId  NVARCHAR(450) = NULL,
    @IsAdmin        BIT           = 0,
    @FarmId         NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2 = SYSUTCDATETIME();
    SELECT a.AnnouncementId, a.OrgOwnerUserId, a.Title, a.Message, a.Type, a.Priority,
           a.AudienceRole, a.TargetFarmId, a.StartDate, a.EndDate, a.IsDismissible,
           a.RequiresAck, a.ActionLabel, a.ActionUrl, a.CreatedBy, a.CreatedAt,
           r.ReadAt, r.DismissedAt, r.AcknowledgedAt
    FROM   dbo.Announcements a
    LEFT   JOIN dbo.AnnouncementReceipts r
           ON r.AnnouncementId = a.AnnouncementId AND r.UserId = @UserId
    WHERE  a.IsDeleted = 0
      AND  (a.StartDate IS NULL OR a.StartDate <= @now)
      AND  (a.EndDate   IS NULL OR a.EndDate   >= @now)
      AND  (a.OrgOwnerUserId IS NULL OR a.OrgOwnerUserId = @OrgOwnerUserId)
      AND  (a.AudienceRole IS NULL OR a.AudienceRole = 'All'
            OR (a.AudienceRole = 'Admin' AND @IsAdmin = 1)
            OR (a.AudienceRole = 'Staff' AND @IsAdmin = 0))
      AND  (a.TargetFarmId IS NULL OR @FarmId IS NULL OR a.TargetFarmId = @FarmId)
      -- hide dismissed ones unless they're high-stakes (always re-shown)
      AND  (r.DismissedAt IS NULL OR a.Type IN ('Critical','Security','Payment'))
    ORDER  BY a.Priority DESC, a.CreatedAt DESC;
END
GO

/* ---- list an org's announcements for management -------------------------- */
CREATE OR ALTER PROCEDURE dbo.spAnnouncement_ListManage
    @OrgOwnerUserId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT a.AnnouncementId, a.OrgOwnerUserId, a.Title, a.Message, a.Type, a.Priority,
           a.AudienceRole, a.TargetFarmId, a.StartDate, a.EndDate, a.IsDismissible,
           a.RequiresAck, a.ActionLabel, a.ActionUrl, a.CreatedBy, a.CreatedAt,
           CAST(NULL AS DATETIME2) AS ReadAt, CAST(NULL AS DATETIME2) AS DismissedAt, CAST(NULL AS DATETIME2) AS AcknowledgedAt
    FROM   dbo.Announcements a
    WHERE  a.IsDeleted = 0 AND a.OrgOwnerUserId = @OrgOwnerUserId
    ORDER  BY a.CreatedAt DESC;
END
GO

/* ---- create ------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.spAnnouncement_Create
    @OrgOwnerUserId NVARCHAR(450) = NULL,
    @Title          NVARCHAR(200),
    @Message        NVARCHAR(2000),
    @Type           NVARCHAR(30)  = 'Info',
    @Priority       INT           = 0,
    @AudienceRole   NVARCHAR(30)  = NULL,
    @TargetFarmId   NVARCHAR(450) = NULL,
    @StartDate      DATETIME2     = NULL,
    @EndDate        DATETIME2     = NULL,
    @IsDismissible  BIT           = 1,
    @RequiresAck    BIT           = 0,
    @ActionLabel    NVARCHAR(80)  = NULL,
    @ActionUrl      NVARCHAR(400) = NULL,
    @CreatedBy      NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@Title IS NULL OR LEN(LTRIM(RTRIM(@Title))) = 0) BEGIN RAISERROR('Title is required.',16,1); RETURN; END
    INSERT INTO dbo.Announcements
        (OrgOwnerUserId, Title, Message, Type, Priority, AudienceRole, TargetFarmId,
         StartDate, EndDate, IsDismissible, RequiresAck, ActionLabel, ActionUrl, CreatedBy)
    VALUES
        (@OrgOwnerUserId, @Title, @Message, @Type, @Priority, @AudienceRole, @TargetFarmId,
         @StartDate, @EndDate, @IsDismissible, @RequiresAck, @ActionLabel, @ActionUrl, @CreatedBy);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

/* ---- per-user receipt (Read | Dismiss | Ack) ---------------------------- */
CREATE OR ALTER PROCEDURE dbo.spAnnouncement_SetReceipt
    @AnnouncementId INT,
    @UserId         NVARCHAR(450),
    @Action         NVARCHAR(20)         -- 'Read' | 'Dismiss' | 'Ack'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2 = SYSUTCDATETIME();
    IF NOT EXISTS (SELECT 1 FROM dbo.AnnouncementReceipts WHERE AnnouncementId = @AnnouncementId AND UserId = @UserId)
        INSERT INTO dbo.AnnouncementReceipts (AnnouncementId, UserId) VALUES (@AnnouncementId, @UserId);

    UPDATE dbo.AnnouncementReceipts
    SET    ReadAt         = CASE WHEN @Action IN ('Read','Dismiss','Ack') THEN ISNULL(ReadAt, @now) ELSE ReadAt END,
           DismissedAt    = CASE WHEN @Action = 'Dismiss' THEN @now ELSE DismissedAt END,
           AcknowledgedAt = CASE WHEN @Action = 'Ack'     THEN @now ELSE AcknowledgedAt END
    WHERE  AnnouncementId = @AnnouncementId AND UserId = @UserId;
END
GO

/* ---- soft delete (org-scoped) ------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.spAnnouncement_Delete
    @AnnouncementId INT,
    @OrgOwnerUserId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.Announcements SET IsDeleted = 1
    WHERE  AnnouncementId = @AnnouncementId AND OrgOwnerUserId = @OrgOwnerUserId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spAnnouncement_ListForUser TO [Techretainer];
    GRANT EXECUTE ON dbo.spAnnouncement_ListManage  TO [Techretainer];
    GRANT EXECUTE ON dbo.spAnnouncement_Create      TO [Techretainer];
    GRANT EXECUTE ON dbo.spAnnouncement_SetReceipt  TO [Techretainer];
    GRANT EXECUTE ON dbo.spAnnouncement_Delete      TO [Techretainer];
END
GO

PRINT '121_Announcements.sql complete.';
GO
