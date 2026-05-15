-- Store serialized request/response payload on audit rows (inspect what changed).
-- Creates dbo.AuditLogs when no audit table exists; otherwise adds [Data] on the existing table
-- (works for dbo.AuditLogs, dbo.Auditlogs, and case-sensitive collations).
-- Safe to run repeatedly.

IF OBJECT_ID(N'dbo.AuditLogs', N'U') IS NULL AND OBJECT_ID(N'dbo.Auditlogs', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AuditLogs (
        Id UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_AuditLogs_Id_017 DEFAULT NEWID() CONSTRAINT PK_AuditLogs PRIMARY KEY,
        UserId NVARCHAR(450) NOT NULL,
        UserName NVARCHAR(256) NULL,
        FarmId NVARCHAR(128) NULL,
        Action NVARCHAR(100) NOT NULL,
        Resource NVARCHAR(100) NULL,
        ResourceId NVARCHAR(450) NULL,
        Details NVARCHAR(MAX) NULL,
        [Data] NVARCHAR(MAX) NULL,
        IpAddress NVARCHAR(45) NULL,
        UserAgent NVARCHAR(500) NULL,
        [Timestamp] DATETIME2(7) NOT NULL CONSTRAINT DF_AuditLogs_Timestamp_017 DEFAULT SYSUTCDATETIME(),
        Status NVARCHAR(50) NOT NULL
    );

    CREATE INDEX IX_AuditLogs_UserId ON dbo.AuditLogs (UserId);
    CREATE INDEX IX_AuditLogs_Timestamp ON dbo.AuditLogs ([Timestamp]);
    CREATE INDEX IX_AuditLogs_FarmId ON dbo.AuditLogs (FarmId);

    PRINT '017_AuditLogsData: created dbo.AuditLogs (with FarmId and Data).';
END
GO

DECLARE @TableName SYSNAME;
DECLARE @Qualified NVARCHAR(300);
DECLARE @Sql NVARCHAR(MAX);

SELECT TOP (1) @TableName = t.name
FROM sys.tables AS t
WHERE t.schema_id = SCHEMA_ID(N'dbo')
  AND t.name COLLATE Latin1_General_CI_AI = N'auditlogs';

IF @TableName IS NULL
BEGIN
    RAISERROR(
        '017_AuditLogsData: no audit log table in dbo. Create failed or wrong database. Check you are connected to the Farm API database.',
        16,
        1
    );
    RETURN;
END

SET @Qualified = QUOTENAME(N'dbo') + N'.' + QUOTENAME(@TableName);

IF COL_LENGTH(@Qualified, N'FarmId') IS NULL
BEGIN
    SET @Sql = N'ALTER TABLE ' + @Qualified + N' ADD FarmId NVARCHAR(128) NULL;';
    EXEC sp_executesql @Sql;
    PRINT '017_AuditLogsData: added FarmId to ' + @Qualified + N'.';
END

IF COL_LENGTH(@Qualified, N'Data') IS NULL
BEGIN
    SET @Sql = N'ALTER TABLE ' + @Qualified + N' ADD [Data] NVARCHAR(MAX) NULL;';
    EXEC sp_executesql @Sql;
    PRINT '017_AuditLogsData: added [Data] to ' + @Qualified + N'.';
END
ELSE
    PRINT '017_AuditLogsData: [Data] already present on ' + @Qualified + N'.';
GO
  When you do merge dev → production, don't forget to also apply 017_AuditLogsData.sql to PoultryMaster (production DB)
  — the deploy code expects the Data column. Want me to write a one-liner for that when the time comes?s