-- ============================================================
-- Post-migration verification.
-- Run against the PROD database after migrations 001–086.
-- Every row in the final SELECT should read OK.
--
-- 2026-06-04 — strategy reversed: Water + Generic + Multi-company
-- are now expected on prod. The old "SkipSet" negative checks were
-- removed and positive checks for those modules were added.
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
       CASE WHEN COL_LENGTH('dbo.ProductionRecord','EggGrade')  IS NOT NULL
              OR COL_LENGTH('dbo.ProductionRecords','EggGrade') IS NOT NULL THEN 'OK' ELSE 'MISSING' END,
       'Either singular or plural table — migration 001 unifies them';

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
-- 025 — Multi-company (Water + Generic enabled on prod as of 2026-06-04)
-- ------------------------------------------------------------
INSERT @checks
SELECT 25, 'MultiCompany', 'Table dbo.UserFarms exists',
       CASE WHEN OBJECT_ID('dbo.UserFarms','U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END,
       'Joins AspNetUsers to Farms by role';

INSERT @checks
SELECT 25, 'MultiCompany', 'Farms.Type column exists',
       CASE WHEN COL_LENGTH('dbo.Farms','Type') IS NOT NULL THEN 'OK' ELSE 'MISSING' END,
       'Drives Poultry/Water/Generic sidebar switching';

INSERT @checks
SELECT 54, 'MultiCompany', 'spCompany_GetByUserId joins on FarmId (post-054)',
       CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.spCompany_GetByUserId')) LIKE '%uf.FarmId = f.FarmId%'
            THEN 'OK' ELSE 'STALE' END,
       'Must join on Farms.FarmId, not Farms.Id';

-- ------------------------------------------------------------
-- 038-048 — Water module anchors
-- ------------------------------------------------------------
INSERT @checks
SELECT 38, 'Water', 'Table dbo.WaterProducts exists',
       CASE WHEN OBJECT_ID('dbo.WaterProducts','U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

INSERT @checks
SELECT 76, 'Water', 'Table dbo.WaterSuppliers exists',
       CASE WHEN OBJECT_ID('dbo.WaterSuppliers','U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

-- ------------------------------------------------------------
-- 028-037 — Generic Company anchors
-- ------------------------------------------------------------
INSERT @checks
SELECT 28, 'Generic', 'Table dbo.GenericCompanyProfiles exists',
       CASE WHEN OBJECT_ID('dbo.GenericCompanyProfiles','U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

INSERT @checks
SELECT 55, 'Generic', 'Table dbo.GenericStaff exists',
       CASE WHEN OBJECT_ID('dbo.GenericStaff','U') IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

-- ------------------------------------------------------------
-- 084 — Sachet inventory + SellingUnit on sale items
-- ------------------------------------------------------------
INSERT @checks
SELECT 84, 'Water', 'spWaterSale_CreateV2 exists (sachet-aware)',
       CASE WHEN OBJECT_ID('dbo.spWaterSale_CreateV2','P') IS NOT NULL THEN 'OK' ELSE 'MISSING' END, '';

-- ------------------------------------------------------------
-- 086 — sp_CreateFarm now creates UserFarms link
-- ------------------------------------------------------------
INSERT @checks
SELECT 86, 'Auth', 'sp_CreateFarm writes UserFarms link',
       CASE WHEN OBJECT_DEFINITION(OBJECT_ID('dbo.sp_CreateFarm')) LIKE '%UserFarms%'
            THEN 'OK' ELSE 'STALE' END,
       'Without this, signup creates a Farms row that the companies UI cannot see';

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
