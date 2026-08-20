-- =============================================================================
-- 202_IamPhase3Enforcement.sql
--
-- Identity & Access Management, phase 3: everything that must be TRUE in the
-- database before Iam:Enforced can be switched on.
--
-- Two jobs
-- --------
-- 1. Three catalog keys the route map needs (water deliveries, quality tests and
--    pumping logs). They were missing, and forcing those routes onto an
--    unrelated permission would have been worse than adding them.
--
-- 2. The back-compat backfill. Until now IAM has been ADDITIVE: effective access
--    is the union of the legacy AspNetUsers.FeaturePermissions blob and whatever
--    IAM grants, so nobody could lose anything. Enforcement ends that - the API
--    will check IAM and nothing else. Every staff member's legacy flags are
--    therefore written into IAM here, as org-wide per-user Allow overrides.
--
--    Why overrides rather than roles: the legacy flags were per-user and
--    org-wide, so per-user org-wide overrides reproduce them EXACTLY. Mapping
--    people onto built-in roles would have been tidier and would have quietly
--    changed what some of them could do.
--
--    Each row carries a reason, so the Access tab shows plainly where it came
--    from and an admin can replace them with real roles at their own pace.
--
-- IMPORTANT: the mapping below must stay in step with
-- poultrycore-main/lib/iam/keys.ts, which does the same job on the client while
-- enforcement is off. If you change one, change the other.
--
-- Idempotent: additive MERGE for the catalog; the backfill only inserts
-- overrides that are missing and never touches one an admin has edited.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Catalog additions.
-- -----------------------------------------------------------------------------
DECLARE @extra TABLE (
    Module NVARCHAR(30), Resource NVARCHAR(60), Grp NVARCHAR(60),
    ResourceLabel NVARCHAR(120), Descr NVARCHAR(400),
    Actions NVARCHAR(200), CompanyType NVARCHAR(20), SortOrder INT
);

INSERT INTO @extra VALUES
 ('water','deliveries','Logistics','Deliveries','Vehicle loading and dispatch.','view,create,edit,delete','Water',104),
 ('water','quality-tests','Production','Quality Tests','Water quality test results.','view,create,edit,delete','Water',23),
 ('water','pumping-logs','Production','Pumping Logs','Daily borehole pumping records.','view,create,edit,delete','Water',24);

MERGE dbo.IamPermissions AS t
USING (
    SELECT
        PermissionKey = CONCAT(c.Module, N'.', c.Resource, N'.', LTRIM(RTRIM(s.value))),
        c.Module, c.Resource, [Action] = LTRIM(RTRIM(s.value)),
        PermissionGroup = c.Grp, c.ResourceLabel, Description = c.Descr, c.CompanyType,
        IsDangerous = CASE WHEN LTRIM(RTRIM(s.value)) IN (N'delete', N'approve') THEN 1 ELSE 0 END,
        c.SortOrder
    FROM @extra c
    CROSS APPLY STRING_SPLIT(c.Actions, N',') s
) AS s
ON t.PermissionKey = s.PermissionKey
WHEN MATCHED THEN UPDATE SET
    t.PermissionGroup = s.PermissionGroup, t.ResourceLabel = s.ResourceLabel,
    t.Description = s.Description, t.IsDangerous = s.IsDangerous, t.SortOrder = s.SortOrder
WHEN NOT MATCHED THEN
    INSERT (PermissionKey, Module, Resource, [Action], PermissionGroup, ResourceLabel, Description, CompanyType, IsDangerous, SortOrder)
    VALUES (s.PermissionKey, s.Module, s.Resource, s.[Action], s.PermissionGroup, s.ResourceLabel, s.Description, s.CompanyType, s.IsDangerous, s.SortOrder);

-- Scalar variable: an inline subquery in PRINT fails to compile and takes the
-- whole batch — including the MERGE above — down with it.
DECLARE @catalogCount INT = (SELECT COUNT(*) FROM dbo.IamPermissions);
PRINT CONCAT(N'202: catalog now holds ', @catalogCount, N' permission key(s).');
GO

-- New keys must reach the roles that should already have had them, or a Manager
-- would suddenly be unable to see deliveries the moment enforcement went on.
-- Same rules as migration 199, applied only to the three new resources.
DECLARE @new TABLE (PermissionKey NVARCHAR(120) PRIMARY KEY, PermissionGroup NVARCHAR(60), [Action] NVARCHAR(20));
INSERT INTO @new (PermissionKey, PermissionGroup, [Action])
SELECT PermissionKey, PermissionGroup, [Action]
FROM dbo.IamPermissions
WHERE Resource IN (N'deliveries', N'quality-tests', N'pumping-logs') AND Module = N'water';

INSERT INTO dbo.IamRolePermissions (RoleId, PermissionKey)
SELECT r.RoleId, n.PermissionKey
FROM dbo.IamRoles r
CROSS JOIN @new n
WHERE r.IsSystem = 1
  AND r.IsSuperuser = 0
  AND (
        r.RoleKey IN (N'sys-org-admin', N'sys-company-admin')
     OR (r.RoleKey = N'sys-manager'     AND n.[Action] <> N'delete')
     OR (r.RoleKey = N'sys-storekeeper' AND n.PermissionGroup IN (N'Production', N'Inventory') AND n.[Action] IN (N'view', N'create', N'edit'))
     OR (r.RoleKey = N'sys-data-entry'  AND n.[Action] IN (N'view', N'create', N'edit'))
     OR (r.RoleKey = N'sys-auditor'     AND n.[Action] IN (N'view', N'export'))
  )
  AND NOT EXISTS (
      SELECT 1 FROM dbo.IamRolePermissions rp
      WHERE rp.RoleId = r.RoleId AND rp.PermissionKey = n.PermissionKey);

PRINT CONCAT(N'202: ', @@ROWCOUNT, N' built-in grant(s) added for the new keys.');
GO

-- -----------------------------------------------------------------------------
-- 2. Legacy flag backfill.
--
--    FeaturePermissions is JSON on AspNetUsers, written by the Login API. Keys
--    have appeared in several casings over time, so each flag is read through a
--    small set of aliases rather than one exact path.
-- -----------------------------------------------------------------------------
IF COL_LENGTH('dbo.AspNetUsers', 'FeaturePermissions') IS NULL
BEGIN
    PRINT N'202: AspNetUsers.FeaturePermissions not present - nothing to backfill.';
END
ELSE
BEGIN
    -- flag -> the catalog keys it stood for. Mirrors LEGACY_PERMISSION_MAP in
    -- lib/iam/keys.ts. Read generously: an over-broad mapping preserves what
    -- someone had, an under-broad one silently takes something away.
    DECLARE @map TABLE (Flag NVARCHAR(60), Resource NVARCHAR(60), Actions NVARCHAR(200), Modules NVARCHAR(60));

    INSERT INTO @map VALUES
     (N'canEnterSales',             N'sales',             N'view,create,edit,export', N'poultry,water,generic'),
     (N'canEnterExpenses',          N'expenses',          N'view,create,edit,export', N'poultry,water,generic'),
     (N'canViewCashLedger',         N'cash',              N'view,export',             N'poultry,water,generic'),
     (N'canViewCashLedger',         N'cash-transfers',    N'view',                    N'generic'),
     (N'canSeeEmployees',           N'staff',             N'view',                    N'poultry,water,generic'),
     (N'canSeeEmployees',           N'employees',         N'view',                    N'office'),
     (N'canViewReports',            N'reports',           N'view,export',             N'poultry,water,generic'),
     (N'canViewFinancial',          N'cash',              N'view,export',             N'poultry,water,generic'),
     (N'canViewFinancial',          N'payments',          N'view',                    N'poultry,water,generic'),
     (N'canViewFinancial',          N'daily-closing',     N'view',                    N'poultry,water,generic'),
     (N'canViewFinancial',          N'customers',         N'view',                    N'poultry,water,generic'),
     (N'canViewFinancial',          N'supplier-payments', N'view',                    N'generic'),
     (N'canViewFinancial',          N'cash-transfers',    N'view',                    N'generic'),
     (N'canViewCustomers',          N'customers',         N'view,export',             N'poultry,water,generic'),
     (N'canViewActivityLog',        N'audit-log',         N'view,export',             N'office'),
     (N'canViewSettings',           N'settings',          N'view',                    N'office'),
     (N'canViewFeedProduction',     N'feed-production',   N'view',                    N'poultry'),
     (N'canViewFeedProduction',     N'feed-formulas',     N'view',                    N'poultry'),
     (N'canManageFeedProduction',   N'feed-production',   N'create,edit,delete,approve', N'poultry'),
     (N'canManageFeedProduction',   N'feed-formulas',     N'create,edit,delete',      N'poultry'),
     (N'canViewFeedProductionCost', N'feed-production-cost', N'view',                 N'poultry');

    -- Expand flag rows into concrete keys.
    DECLARE @keys TABLE (Flag NVARCHAR(60), PermissionKey NVARCHAR(120));
    INSERT INTO @keys (Flag, PermissionKey)
    SELECT DISTINCT m.Flag, p.PermissionKey
    FROM @map m
    CROSS APPLY STRING_SPLIT(m.Modules, N',') mo
    CROSS APPLY STRING_SPLIT(m.Actions, N',') ac
    JOIN dbo.IamPermissions p
      ON p.PermissionKey = CONCAT(LTRIM(RTRIM(mo.value)), N'.', m.Resource, N'.', LTRIM(RTRIM(ac.value)));

    -- Only staff need this. Owners and staff-admins already hold Owner or
    -- Organization Admin from migration 200, which covers everything.
    DECLARE @inserted INT = 0;

    -- The DISTINCT is load-bearing, not tidiness. Several legacy flags map to the
    -- SAME key on purpose - canViewCashLedger and canViewFinancial both grant
    -- generic.cash.export, because the old umbrella flag covered the cash ledger
    -- too. A user holding both flags therefore produces that row twice, and the
    -- NOT EXISTS below cannot see duplicates arising within its own INSERT: it
    -- only checks what is already committed. Collapsing to one row per
    -- (user, key) first is what makes the statement safe.
    ;WITH wanted AS (
        SELECT DISTINCT u.Id AS UserId, k.PermissionKey
        FROM dbo.AspNetUsers u
        CROSS APPLY OPENJSON(u.FeaturePermissions) AS j
        JOIN @keys k ON k.Flag = j.[key] COLLATE DATABASE_DEFAULT
        WHERE ISNULL(u.IsStaff, 0) = 1
          AND ISJSON(u.FeaturePermissions) = 1
          -- OPENJSON reports true/false as the string 'true'/'false' for type 3.
          AND (j.value = N'true' OR j.value = N'1')
    )
    INSERT INTO dbo.IamUserPermissions (UserId, FarmId, PermissionKey, Effect, Reason, GrantedBy)
    SELECT w.UserId, NULL, w.PermissionKey, N'Allow',
           N'Migrated from the staff permissions set before access management existed.',
           N'migration-202'
    FROM wanted w
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.IamUserPermissions up
        WHERE up.UserId = w.UserId AND up.FarmId IS NULL AND up.PermissionKey = w.PermissionKey);

    SET @inserted = @@ROWCOUNT;
    PRINT CONCAT(N'202: ', @inserted, N' legacy permission(s) migrated into IAM for staff users.');

    -- Anyone who ends up with nothing would be locked out the moment enforcement
    -- goes on. Report them rather than guessing what they should have.
    DECLARE @orphans INT = (
        SELECT COUNT(*)
        FROM dbo.AspNetUsers u
        WHERE ISNULL(u.IsStaff, 0) = 1
          AND NOT EXISTS (SELECT 1 FROM dbo.IamUserRoles ur WHERE ur.UserId = u.Id)
          AND NOT EXISTS (SELECT 1 FROM dbo.IamUserPermissions up WHERE up.UserId = u.Id));

    IF @orphans > 0
        PRINT CONCAT(N'202: WARNING - ', @orphans,
            N' staff user(s) have no roles and no permissions. They will lose all access when Iam:Enforced is set to true. Assign them a role first.');
    ELSE
        PRINT N'202: every staff user has at least one role or permission.';
END
GO

PRINT N'202_IamPhase3Enforcement.sql complete.';
PRINT N'202: NOTE - this migration does NOT switch enforcement on. Run the API with';
PRINT N'202:        Iam:Enforced = false first, review the "IAM SHADOW" log lines,';
PRINT N'202:        then set it to true.';
GO
