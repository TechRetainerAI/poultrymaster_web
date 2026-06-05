-- ============================================================
-- Post-migration verification.
-- Run against the PROD database after migrations 001–024.
-- Every row in the final SELECT should read OK.
-- ============================================================

SET NOCOUNT ON;

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 50000, N'You are on a system DB. Switch to the prod application DB first.', 1;
END

DECLARE @checks TABLE (
    StepNo  INT,
    Area    NVARCHAR(60),
    Check_  NVARCHAR(200),
    Status  NVARCHAR(20),
    Detail  NVARCHAR(400)
);

-- ------------------------------------------------------------
-- 022 — Flock.HasArrived (the bug fix)
-- ------------------------------------------------------------
INSERT @checks
SELECT 22, 'Flock', 'Column dbo.Flock.HasArrived exists',
       CASE WHEN COL_LENGTH('dbo.Flock','HasArrived') IS NOT NULL THEN 'OK' ELSE 'MISSING' END,
       'Required for the expenses flock dropdown';

INSERT @checks
SELECT 22, 'Flock', 'spFlock_GetAll returns HasArrived',
       CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.spFlock_GetAll')) LIKE '%HasArrived%'
            THEN 'OK' ELSE 'STALE' END,
       'Proc must SELECT HasArrived or API maps to false';

INSERT @checks
SELECT 22, 'Flock', 'spFlock_Insert accepts @HasArrived',
       CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.spFlock_Insert')) LIKE '%@HasArrived%'
            THEN 'OK' ELSE 'STALE' END,
       'Insert proc must accept the new parameter';

INSERT @checks
SELECT 22, 'Flock', 'spFlock_Update accepts @HasArrived',
       CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.spFlock_Update')) LIKE '%@HasArrived%'
            THEN 'OK' ELSE 'STALE' END,
       'Update proc must accept the new parameter';

-- ------------------------------------------------------------
-- 001/003 — ProductionRecord columns
-- ------------------------------------------------------------
INSERT @checks
SELECT 1, 'ProductionRecord', 'BrokenEggs column exists',
       CASE WHEN COL_LENGTH('dbo.ProductionRecord','BrokenEggs') IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

INSERT @checks
SELECT 1, 'ProductionRecord', 'EggCount column exists',
       CASE WHEN COL_LENGTH('dbo.ProductionRecord','EggCount') IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

INSERT @checks
SELECT 3, 'ProductionRecord', 'EggGrade column exists',
       CASE WHEN COL_LENGTH('dbo.ProductionRecord','EggGrade') IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

-- ------------------------------------------------------------
-- 005 — Sales.Paid
-- ------------------------------------------------------------
INSERT @checks
SELECT 5, 'Sales', 'Paid column exists',
       CASE WHEN COL_LENGTH('dbo.Sales','Paid') IS NOT NULL
              OR COL_LENGTH('dbo.Sale','Paid')  IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

-- ------------------------------------------------------------
-- 007/008 — AuditLogs
-- ------------------------------------------------------------
INSERT @checks
SELECT 8, 'AuditLogs', 'Table dbo.AuditLogs exists',
       CASE WHEN OBJECT_ID('dbo.AuditLogs','U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

INSERT @checks
SELECT 7, 'AuditLogs', 'FarmId column exists',
       CASE WHEN COL_LENGTH('dbo.AuditLogs','FarmId') IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

-- ------------------------------------------------------------
-- 011 — Inventory module
-- ------------------------------------------------------------
INSERT @checks
SELECT 11, 'Inventory', 'Table dbo.InventoryItem exists',
       CASE WHEN OBJECT_ID('dbo.InventoryItem','U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

-- ------------------------------------------------------------
-- 013 — Supplier link
-- ------------------------------------------------------------
INSERT @checks
SELECT 13, 'Supplier', 'Table dbo.Supplier exists',
       CASE WHEN OBJECT_ID('dbo.Supplier','U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

-- ------------------------------------------------------------
-- 015/016 — Attachment columns
-- ------------------------------------------------------------
INSERT @checks
SELECT 15, 'HealthRecord', 'AttachmentImage column exists',
       CASE WHEN COL_LENGTH('dbo.HealthRecord','AttachmentImage') IS NOT NULL
              OR COL_LENGTH('dbo.HealthRecord','AttachmentPath')  IS NOT NULL THEN 'OK' ELSE 'MISSING' END,
       'Either column name acceptable depending on migration variant';

INSERT @checks
SELECT 16, 'Expense', 'Receipt/attachment field present',
       CASE WHEN COL_LENGTH('dbo.Expense','AttachmentImage') IS NOT NULL
              OR COL_LENGTH('dbo.Expense','AttachmentPath')  IS NOT NULL
              OR COL_LENGTH('dbo.Expense','ReceiptPath')     IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

-- ------------------------------------------------------------
-- 021/023/024 — MainFlockBatch additions
-- ------------------------------------------------------------
INSERT @checks
SELECT 21, 'MainFlockBatch', 'Table exists',
       CASE WHEN OBJECT_ID('dbo.MainFlockBatch','U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

INSERT @checks
SELECT 23, 'MainFlockBatch', 'AmountPaid column exists',
       CASE WHEN COL_LENGTH('dbo.MainFlockBatch','AmountPaid') IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

INSERT @checks
SELECT 24, 'MainFlockBatch', 'Notes column exists',
       CASE WHEN COL_LENGTH('dbo.MainFlockBatch','Notes') IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

-- ------------------------------------------------------------
-- Negative checks — these should NOT exist on prod (water + multi-company)
-- ------------------------------------------------------------
INSERT @checks
SELECT 25, 'SkipSet', 'WaterProducts NOT on prod',
       CASE WHEN OBJECT_ID('dbo.WaterProducts','U') IS NULL THEN 'OK' ELSE 'UNEXPECTED' END,
       'Should stay dev-only per instruction';

INSERT @checks
SELECT 25, 'SkipSet', 'UserFarms NOT on prod',
       CASE WHEN OBJECT_ID('dbo.UserFarms','U') IS NULL THEN 'OK' ELSE 'UNEXPECTED' END,
       'Multi-company table — should stay dev-only';

-- ------------------------------------------------------------
-- Data sanity: at least one flock for the current farm should now be selectable
-- ------------------------------------------------------------
DECLARE @flockCount INT = (SELECT COUNT(*) FROM dbo.Flock WHERE COL_LENGTH('dbo.Flock','HasArrived') IS NOT NULL);
INSERT @checks
SELECT 99, 'Data', 'Flock rows reachable',
       CASE WHEN @flockCount > 0 THEN 'OK' ELSE 'EMPTY' END,
       CONCAT('Total flock rows: ', @flockCount, ' (0 means farms have no flocks yet, not a schema problem)');

-- ------------------------------------------------------------
-- Final report
-- ------------------------------------------------------------
SELECT
    StepNo,
    Area,
    Check_   AS [Check],
    Status,
    Detail
FROM @checks
ORDER BY
    CASE Status WHEN 'OK' THEN 1 ELSE 0 END,   -- failures first
    StepNo, Area;

PRINT N'';
PRINT N'>>> Any non-OK row above must be investigated before the app is considered fixed.';
