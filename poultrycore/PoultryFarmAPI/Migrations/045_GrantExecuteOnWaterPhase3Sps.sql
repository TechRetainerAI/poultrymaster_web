-- =============================================================================
-- Migration 045: Grant EXECUTE on Water Phase W3 SPs to Techretainer
-- =============================================================================
-- Same belt-and-braces grant we added in migration 042 — now covering the
-- newly-created W3 SPs (Raw Materials, Daily Closing, Loss Records, Reports).
--
-- Idempotent and tolerant of missing user.
-- =============================================================================

SET NOCOUNT ON;

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    DECLARE @procName SYSNAME;
    DECLARE proc_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.procedures
        WHERE name LIKE 'spWaterRawMaterial%'
           OR name LIKE 'spWaterLossRecord%'
           OR name LIKE 'spWaterDailyClosing%'
           OR name LIKE 'spWaterReport_%';
    OPEN proc_cursor;
    FETCH NEXT FROM proc_cursor INTO @procName;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @grantSql NVARCHAR(MAX) =
            N'GRANT EXECUTE ON [dbo].' + QUOTENAME(@procName) + N' TO [Techretainer];';
        EXEC sp_executesql @grantSql;
        FETCH NEXT FROM proc_cursor INTO @procName;
    END;
    CLOSE proc_cursor;
    DEALLOCATE proc_cursor;
    PRINT '045: granted EXECUTE on Water W3 SPs to Techretainer.';
END
GO

PRINT '045_GrantExecuteOnWaterPhase3Sps.sql complete.';
GO
