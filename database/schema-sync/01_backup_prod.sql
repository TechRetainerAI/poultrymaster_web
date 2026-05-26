-- ============================================================
-- STEP 1: Take a full prod backup BEFORE any schema work.
-- This is your only rollback if step 3 goes wrong. Do not skip.
--
-- Replace <PROD_DB_NAME> below with the actual prod database
-- name (from step 0). The backup path must be writable by the
-- SQL Server service account on 34.39.109.13.
--
-- After the backup finishes, copy the .bak off the server
-- (gsutil / scp) so you have an off-box copy.
-- ============================================================

DECLARE @db        sysname        = N'<PROD_DB_NAME>';
DECLARE @timestamp NVARCHAR(20)   = FORMAT(SYSUTCDATETIME(), 'yyyyMMdd_HHmmss');
DECLARE @path      NVARCHAR(4000) = N'C:\SQLBackups\' + @db + N'_preSchemaSync_' + @timestamp + N'.bak';
DECLARE @sql       NVARCHAR(MAX);

SET @sql = N'
BACKUP DATABASE ' + QUOTENAME(@db) + N'
TO DISK = ''' + @path + N'''
WITH FORMAT, INIT, COMPRESSION, CHECKSUM,
     NAME = ''' + @db + N' - pre schema sync'',
     STATS = 10;';

PRINT N'Backing up to: ' + @path;
EXEC sys.sp_executesql @sql;

-- Confirm the backup is restorable without actually restoring.
RESTORE VERIFYONLY FROM DISK = @path WITH CHECKSUM;
PRINT N'Backup verified OK: ' + @path;
