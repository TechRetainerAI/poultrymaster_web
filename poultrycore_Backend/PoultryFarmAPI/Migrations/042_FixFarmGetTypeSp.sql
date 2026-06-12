-- =============================================================================
-- Migration 042: spFarm_GetType helper SP for company-scope checks
-- =============================================================================
-- The Generic Company controllers need to look up Farms.Type to gate access.
-- The runtime app user (Techretainer on dev) is granted EXECUTE on stored
-- procedures but NOT direct SELECT on dbo.Farms. The original GenericCompanyService
-- used raw SQL ("SELECT Type FROM dbo.Farms WHERE FarmId=@FarmId") which fails
-- with SQL error 229 (permission denied).
--
-- Replace the raw SQL with a stored proc, then we're back on the same path
-- the rest of the app already uses.
--
-- Idempotent (CREATE OR ALTER).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spFarm_GetType
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP 1 Type FROM dbo.Farms WHERE FarmId = @FarmId;
END
GO

-- Grant EXECUTE to the runtime user.
-- Idempotent and tolerant of missing user (skipped on databases without it).
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spFarm_GetType TO [Techretainer];
    PRINT '042: granted EXECUTE on dbo.spFarm_GetType to Techretainer.';
END
GO

-- ALSO: belt-and-braces grant EXECUTE on all Generic Company SPs and Water
-- production SPs to the runtime user. Some environments don't grant
-- EXECUTE-on-schema, so newly-created procs are inaccessible until granted
-- explicitly. This loop handles all of them with one block.
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    DECLARE @procName SYSNAME;
    DECLARE proc_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.procedures
        WHERE name LIKE 'spGeneric%'
           OR name LIKE 'spBusinessCategory%'
           OR name LIKE 'spWaterBorehole%'
           OR name LIKE 'spWaterMachine%'
           OR name LIKE 'spWaterProductionBatch%'
           OR name LIKE 'spWaterQualityTest%'
           OR name LIKE 'spWaterDailyPumpingLog%'
           OR name LIKE 'spWaterDriver%'
           OR name LIKE 'spWaterVehicle%'
           OR name LIKE 'spWaterRoute%'
           OR name LIKE 'spFarm_%';
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
    PRINT '042: granted EXECUTE on all Generic Company + Water production/distribution SPs to Techretainer.';
END
GO

PRINT '042_FixFarmGetTypeSp.sql complete.';
GO
