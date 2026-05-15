-- Store serialized request/response payload on audit rows (inspect what changed).
-- Safe to run repeatedly.

IF OBJECT_ID(N'dbo.AuditLogs', N'U') IS NOT NULL AND COL_LENGTH(N'dbo.AuditLogs', N'Data') IS NULL
    ALTER TABLE dbo.AuditLogs ADD [Data] NVARCHAR(MAX) NULL;

IF OBJECT_ID(N'dbo.Auditlogs', N'U') IS NOT NULL AND COL_LENGTH(N'dbo.Auditlogs', N'Data') IS NULL
    ALTER TABLE dbo.Auditlogs ADD [Data] NVARCHAR(MAX) NULL;

GO

PRINT '017_AuditLogsData: [Data] column added to audit log table(s) where missing.';
GO
