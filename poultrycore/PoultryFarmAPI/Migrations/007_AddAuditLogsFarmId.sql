-- PoultryFarmAPI AuditLogService queries dbo.AuditLogs with column FarmId.
-- Older installs used database/create-audit-logs-table.sql without FarmId → GET /api/AuditLogs returns 500.
--
-- SSMS may display [dbo].[Auditlogs]; on most SQL Server collations that is the same object as dbo.AuditLogs.
-- On case-sensitive databases, a legacy table might exist only as dbo.Auditlogs — this script adds FarmId to
-- whichever name exists (and creates dbo.AuditLogs if neither exists).
--
-- Safe to run repeatedly.

IF OBJECT_ID(N'dbo.AuditLogs', N'U') IS NULL AND OBJECT_ID(N'dbo.Auditlogs', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AuditLogs (
        Id UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_AuditLogs_Id DEFAULT NEWID() CONSTRAINT PK_AuditLogs PRIMARY KEY,
        UserId NVARCHAR(450) NOT NULL,
        UserName NVARCHAR(256) NULL,
        FarmId NVARCHAR(128) NULL,
        Action NVARCHAR(100) NOT NULL,
        Resource NVARCHAR(100) NULL,
        ResourceId NVARCHAR(450) NULL,
        Details NVARCHAR(MAX) NULL,
        IpAddress NVARCHAR(45) NULL,
        UserAgent NVARCHAR(500) NULL,
        [Timestamp] DATETIME2(7) NOT NULL CONSTRAINT DF_AuditLogs_Timestamp DEFAULT SYSUTCDATETIME(),
        Status NVARCHAR(50) NOT NULL
    );
END
ELSE
BEGIN
    IF OBJECT_ID(N'dbo.AuditLogs', N'U') IS NOT NULL AND COL_LENGTH(N'dbo.AuditLogs', N'FarmId') IS NULL
        ALTER TABLE dbo.AuditLogs ADD FarmId NVARCHAR(128) NULL;

    IF OBJECT_ID(N'dbo.Auditlogs', N'U') IS NOT NULL AND COL_LENGTH(N'dbo.Auditlogs', N'FarmId') IS NULL
        ALTER TABLE dbo.Auditlogs ADD FarmId NVARCHAR(128) NULL;
END
GO

PRINT '007_AddAuditLogsFarmId: dbo.AuditLogs and/or dbo.Auditlogs checked; FarmId present where applicable.';
GO
