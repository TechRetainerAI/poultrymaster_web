-- Farm API error: "SELECT permission was denied on the object 'Auditlogs' ..."
-- The database principal in ConnectionStrings__PoultryConn must have SELECT and INSERT
-- on the audit log table (read list + insert from AuditLogActionFilter).
--
-- Set @DbUser (line ~21) to the SAME value as the SQL login / user id in your connection string:
--   …User ID=myapiuser;Password=…;…   →  @DbUser = N'myapiuser'
--   …UID=myapiuser;…                 →  @DbUser = N'myapiuser'
-- It must be a user that already exists under PoultryMaster → Security → Users (see list below if still CHANGE_ME).
--
-- If someone used DENY on this table, REVOKE that first, then GRANT.
--
-- Safe to re-run after setting @DbUser.

SET NOCOUNT ON;

-- Must match User ID= / UID= in ConnectionStrings__PoultryConn (edit if your login differs).
DECLARE @DbUser SYSNAME = N'techretainer';

IF @DbUser = N'CHANGE_ME' OR NULLIF(LTRIM(RTRIM(@DbUser)), N'') IS NULL
BEGIN
    PRINT N'009: Edit this script — set @DbUser to the User ID (or UID) from ConnectionStrings__PoultryConn / Cloud Run secret, then run again.';
    PRINT N'009: Candidate database users in ''' + DB_NAME() + N''' (pick the one that matches your API login):';
    SELECT dp.name AS database_user, dp.type_desc
    FROM sys.database_principals AS dp
    WHERE dp.type IN (N'S', N'U')
      AND dp.name NOT IN (N'guest', N'INFORMATION_SCHEMA', N'sys', N'dbo')
    ORDER BY dp.name;
    RETURN;
END;

IF DATABASE_PRINCIPAL_ID(@DbUser) IS NULL
BEGIN
    RAISERROR('009: Database user %s does not exist in this database. Create the user or fix the name.', 16, 1, @DbUser);
    RETURN;
END;

DECLARE @objId INT =
    COALESCE(OBJECT_ID(N'dbo.AuditLogs', N'U'), OBJECT_ID(N'dbo.Auditlogs', N'U'));

IF @objId IS NULL
BEGIN
    RAISERROR('009: No dbo.AuditLogs / dbo.Auditlogs table found. Run 007_AddAuditLogsFarmId.sql first.', 16, 1);
    RETURN;
END;

DECLARE @quotedObj NVARCHAR(520) =
    QUOTENAME(OBJECT_SCHEMA_NAME(@objId)) + N'.' + QUOTENAME(OBJECT_NAME(@objId));

DECLARE @sql NVARCHAR(MAX) =
    N'GRANT SELECT, INSERT ON ' + @quotedObj + N' TO ' + QUOTENAME(@DbUser) + N';';

EXEC sp_executesql @sql;

PRINT N'009_GrantAuditLogsPermissions: granted SELECT, INSERT on ' + @quotedObj + N' to ' + QUOTENAME(@DbUser) + N'.';
GO
