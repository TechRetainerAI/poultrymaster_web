-- If the table was created as dbo.Auditlogs and the database uses a *case-sensitive* collation,
-- queries in AuditLogService against dbo.AuditLogs will fail ("Invalid object name") even after FarmId exists.
-- This renames the legacy object to dbo.AuditLogs so it matches the API and scripts.
--
-- Safe to run repeatedly: skips when dbo.AuditLogs already exists or dbo.Auditlogs is missing.
-- Typical CI (case-insensitive) databases: skip — dbo.Auditlogs and dbo.AuditLogs are already the same object.

IF OBJECT_ID(N'dbo.Auditlogs', N'U') IS NOT NULL AND OBJECT_ID(N'dbo.AuditLogs', N'U') IS NULL
BEGIN
    EXEC sp_rename N'dbo.Auditlogs', N'AuditLogs';
    PRINT '008_RenameLegacyAuditlogsToAuditLogs: renamed dbo.Auditlogs -> dbo.AuditLogs.';
END
ELSE
    PRINT '008_RenameLegacyAuditlogsToAuditLogs: skipped (AuditLogs already exists or Auditlogs not found).';
GO
