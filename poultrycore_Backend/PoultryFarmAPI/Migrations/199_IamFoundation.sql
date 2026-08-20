-- =============================================================================
-- 199_IamFoundation.sql
--
-- Identity & Access Management, phase 0: the data model and the read path.
-- Nothing in the application changes behaviour when this runs.
--
-- Why there is no back-compat data migration
-- ------------------------------------------
-- IAM is additive through phases 1-2: effective access is the UNION of the
-- legacy AspNetUsers.FeaturePermissions blob and whatever IAM grants. Nobody
-- can lose access on deploy, so there is nothing to backfill. The migration
-- that turns legacy flags into role assignments belongs to phase 3, when IAM
-- becomes authoritative and the union rule retires.
--
-- Source of truth
-- ---------------
-- dbo.IamPermissions is the catalog - keys, labels and grouping all live here
-- and the frontend reads it over the API rather than keeping its own copy.
-- A role can only be granted a key that exists in the catalog (FK), so a typo
-- is rejected at write time rather than silently never matching.
--
-- Scope
-- -----
-- Role definitions are organization-level; ASSIGNMENTS are per company
-- (IamUserRoles.FarmId). FarmId NULL on an assignment means org-wide.
--
-- Idempotent: every object is guarded or CREATE OR ALTER; the seeds are
-- NOT EXISTS-guarded and converge on re-run.
-- =============================================================================

SET NOCOUNT ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Tables
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.IamPermissions','U') IS NULL
BEGIN
    CREATE TABLE dbo.IamPermissions (
        PermissionKey    NVARCHAR(120) NOT NULL PRIMARY KEY,   -- module.resource.action
        Module           NVARCHAR(30)  NOT NULL,               -- poultry|water|generic|office
        Resource         NVARCHAR(60)  NOT NULL,
        [Action]         NVARCHAR(20)  NOT NULL,               -- view|create|edit|delete|approve|export
        PermissionGroup  NVARCHAR(60)  NOT NULL,               -- UI grouping, e.g. 'Finance'
        ResourceLabel    NVARCHAR(120) NOT NULL,
        Description      NVARCHAR(400) NULL,
        CompanyType      NVARCHAR(20)  NULL,                   -- NULL = company-neutral (office)
        IsDangerous      BIT           NOT NULL DEFAULT 0,
        SortOrder        INT           NOT NULL DEFAULT 0
    );
    CREATE INDEX IX_IamPermissions_Module ON dbo.IamPermissions (Module, PermissionGroup, Resource);
    PRINT N'199: created dbo.IamPermissions.';
END
GO

IF OBJECT_ID('dbo.IamRoles','U') IS NULL
BEGIN
    CREATE TABLE dbo.IamRoles (
        RoleId       INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        RoleKey      NVARCHAR(60)  NULL,        -- stable id for built-ins ('sys-accountant'); NULL for custom
        OwnerUserId  NVARCHAR(450) NULL,        -- NULL = built-in, visible to every organization
        Name         NVARCHAR(100) NOT NULL,
        Description  NVARCHAR(400) NULL,
        CompanyType  NVARCHAR(20)  NULL,        -- role only offered for this company type; NULL = any
        IsSystem     BIT NOT NULL DEFAULT 0,    -- built-in: not editable, not deletable
        IsSuperuser  BIT NOT NULL DEFAULT 0,    -- grants everything, including keys added later
        IsActive     BIT NOT NULL DEFAULT 1,
        CreatedBy    NVARCHAR(450) NULL,
        CreatedAt    DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        UpdatedAt    DATETIME2 NULL
    );
    CREATE UNIQUE INDEX UX_IamRoles_SystemKey ON dbo.IamRoles (RoleKey) WHERE RoleKey IS NOT NULL;
    CREATE UNIQUE INDEX UX_IamRoles_OwnerName ON dbo.IamRoles (OwnerUserId, Name) WHERE OwnerUserId IS NOT NULL;
    PRINT N'199: created dbo.IamRoles.';
END
GO

IF OBJECT_ID('dbo.IamRolePermissions','U') IS NULL
BEGIN
    CREATE TABLE dbo.IamRolePermissions (
        RoleId        INT           NOT NULL,
        PermissionKey NVARCHAR(120) NOT NULL,
        CONSTRAINT PK_IamRolePermissions PRIMARY KEY (RoleId, PermissionKey),
        CONSTRAINT FK_IamRolePermissions_Role
            FOREIGN KEY (RoleId) REFERENCES dbo.IamRoles (RoleId) ON DELETE CASCADE,
        CONSTRAINT FK_IamRolePermissions_Permission
            FOREIGN KEY (PermissionKey) REFERENCES dbo.IamPermissions (PermissionKey)
    );
    PRINT N'199: created dbo.IamRolePermissions.';
END
GO

-- Assignments. FarmId NULL = org-wide. The unique index treats NULLs as equal,
-- which is what we want: one org-wide assignment per (user, role).
IF OBJECT_ID('dbo.IamUserRoles','U') IS NULL
BEGIN
    CREATE TABLE dbo.IamUserRoles (
        Id         INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        -- 256 rather than the 450 used elsewhere: these two columns sit in a
        -- composite index, and NVARCHAR(450) is 900 bytes apiece, which puts the
        -- key over SQL Server's 1700-byte limit. Ids here are GUID strings (36
        -- chars), so 256 is generous.
        UserId     NVARCHAR(256) NOT NULL,
        RoleId     INT           NOT NULL,
        FarmId     NVARCHAR(256) NULL,
        AssignedBy NVARCHAR(450) NULL,
        AssignedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        ExpiresAt  DATETIME2 NULL,
        CONSTRAINT FK_IamUserRoles_Role
            FOREIGN KEY (RoleId) REFERENCES dbo.IamRoles (RoleId)
    );
    CREATE UNIQUE INDEX UX_IamUserRoles ON dbo.IamUserRoles (UserId, RoleId, FarmId);
    CREATE INDEX IX_IamUserRoles_Lookup ON dbo.IamUserRoles (UserId, FarmId) INCLUDE (RoleId, ExpiresAt);
    PRINT N'199: created dbo.IamUserRoles.';
END
GO

-- Per-user overrides layered on top of roles. Reason is required by the API,
-- so an override always carries an explanation of why it exists.
IF OBJECT_ID('dbo.IamUserPermissions','U') IS NULL
BEGIN
    CREATE TABLE dbo.IamUserPermissions (
        Id            INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        -- 256 for the same reason as IamUserRoles: both columns are part of the
        -- unique index alongside PermissionKey.
        UserId        NVARCHAR(256) NOT NULL,
        FarmId        NVARCHAR(256) NULL,
        PermissionKey NVARCHAR(120) NOT NULL,
        Effect        NVARCHAR(10)  NOT NULL,   -- Allow | Deny
        Reason        NVARCHAR(400) NULL,
        GrantedBy     NVARCHAR(450) NULL,
        GrantedAt     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        ExpiresAt     DATETIME2 NULL,
        CONSTRAINT CK_IamUserPermissions_Effect CHECK (Effect IN (N'Allow', N'Deny')),
        CONSTRAINT FK_IamUserPermissions_Permission
            FOREIGN KEY (PermissionKey) REFERENCES dbo.IamPermissions (PermissionKey)
    );
    CREATE UNIQUE INDEX UX_IamUserPermissions ON dbo.IamUserPermissions (UserId, FarmId, PermissionKey);
    PRINT N'199: created dbo.IamUserPermissions.';
END
GO

-- -----------------------------------------------------------------------------
-- 1b. Fix up installs created before the columns were narrowed.
--
--     The first cut declared UserId/FarmId as NVARCHAR(450) on these two tables.
--     At 900 bytes each that puts the composite index keys at 1804 and 2040
--     bytes, over SQL Server's 1700-byte limit — it creates the index anyway but
--     warns that inserts can fail on long values. Narrowing to 256 removes the
--     warning for good. Non-destructive: indexes are dropped, the columns are
--     widened down, and the indexes are rebuilt identically.
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.IamUserRoles','U') IS NOT NULL
   AND (SELECT c.max_length FROM sys.columns c
        WHERE c.object_id = OBJECT_ID('dbo.IamUserRoles') AND c.name = 'UserId') > 512
BEGIN
    DROP INDEX IF EXISTS UX_IamUserRoles ON dbo.IamUserRoles;
    DROP INDEX IF EXISTS IX_IamUserRoles_Lookup ON dbo.IamUserRoles;

    ALTER TABLE dbo.IamUserRoles ALTER COLUMN UserId NVARCHAR(256) NOT NULL;
    ALTER TABLE dbo.IamUserRoles ALTER COLUMN FarmId NVARCHAR(256) NULL;

    CREATE UNIQUE INDEX UX_IamUserRoles ON dbo.IamUserRoles (UserId, RoleId, FarmId);
    CREATE INDEX IX_IamUserRoles_Lookup ON dbo.IamUserRoles (UserId, FarmId) INCLUDE (RoleId, ExpiresAt);

    PRINT N'199: narrowed IamUserRoles key columns to fit the index size limit.';
END
GO

IF OBJECT_ID('dbo.IamUserPermissions','U') IS NOT NULL
   AND (SELECT c.max_length FROM sys.columns c
        WHERE c.object_id = OBJECT_ID('dbo.IamUserPermissions') AND c.name = 'UserId') > 512
BEGIN
    DROP INDEX IF EXISTS UX_IamUserPermissions ON dbo.IamUserPermissions;

    ALTER TABLE dbo.IamUserPermissions ALTER COLUMN UserId NVARCHAR(256) NOT NULL;
    ALTER TABLE dbo.IamUserPermissions ALTER COLUMN FarmId NVARCHAR(256) NULL;

    CREATE UNIQUE INDEX UX_IamUserPermissions ON dbo.IamUserPermissions (UserId, FarmId, PermissionKey);

    PRINT N'199: narrowed IamUserPermissions key columns to fit the index size limit.';
END
GO

-- -----------------------------------------------------------------------------
-- 2. Catalog seed.
--
--    One row per resource, with its applicable actions as a CSV that is expanded
--    into individual keys below. Actions are deliberately not uniform: a report
--    cannot be "approved", a cost figure is view-only.
-- -----------------------------------------------------------------------------
DECLARE @cat TABLE (
    Module NVARCHAR(30), Resource NVARCHAR(60), Grp NVARCHAR(60),
    ResourceLabel NVARCHAR(120), Descr NVARCHAR(400),
    Actions NVARCHAR(200), CompanyType NVARCHAR(20), SortOrder INT
);

-- --- Poultry -----------------------------------------------------------------
INSERT INTO @cat VALUES
 ('poultry','flocks','Flock & Birds','Flocks','Bird flocks and their lifecycle.','view,create,edit,delete','Poultry',10),
 ('poultry','houses','Flock & Birds','Houses','Poultry houses and pens.','view,create,edit,delete','Poultry',11),
 ('poultry','flock-batches','Flock & Birds','Flock Batches','Purchased batches of birds, their cost and arrival.','view,create,edit,delete','Poultry',12),
 ('poultry','loss-records','Flock & Birds','Bird Loss Records','Mortality, culls and other bird losses.','view,create,edit,delete','Poultry',13),
 ('poultry','egg-production','Production','Egg Production','Daily egg collection by pick.','view,create,edit,delete,export','Poultry',20),
 ('poultry','egg-sorting','Production','Egg Sorting','Grading collected eggs into sizes.','view,create,edit,delete','Poultry',21),
 ('poultry','egg-stock','Production','Egg Stock','Eggs on hand and the egg stock ledger.','view,edit,export','Poultry',22),
 ('poultry','production-records','Production','Production Records','Combined daily production entry.','view,create,edit,delete,export','Poultry',23),
 ('poultry','feed-usage','Feed','Feed Usage','Feed issued to flocks.','view,create,edit,delete','Poultry',30),
 ('poultry','feed-formulas','Feed','Feed Formulas','Recipes used to produce feed.','view,create,edit,delete','Poultry',31),
 ('poultry','feed-production','Feed','Feed Production','Feed batches. Approve covers posting and reversing a batch.','view,create,edit,delete,approve','Poultry',32),
 ('poultry','feed-production-cost','Feed','Feed Production Costs','See unit costs and totals on feed batches and cost reports.','view','Poultry',33),
 ('poultry','raw-materials','Feed','Raw Materials','Feed ingredients and their stock.','view,create,edit,delete','Poultry',34),
 ('poultry','health','Health','Health Records','Vaccinations, treatments and health checks.','view,create,edit,delete','Poultry',40),
 ('poultry','medication','Health','Medication','Medication stock and administration.','view,create,edit,delete','Poultry',41),
 ('poultry','inventory','Inventory','Inventory','General inventory items.','view,create,edit,delete','Poultry',50),
 ('poultry','stock','Inventory','Stock','Stock balances and adjustments.','view,edit,export','Poultry',51),
 ('poultry','products','Inventory','Products','Sellable products and their pricing.','view,create,edit,delete','Poultry',52),
 ('poultry','sales','Sales & Customers','Sales','Sales orders and invoices.','view,create,edit,delete,export','Poultry',60),
 ('poultry','customers','Sales & Customers','Customers','Customer records and balances.','view,create,edit,delete,export','Poultry',61),
 ('poultry','payments','Sales & Customers','Customer Payments','Payments received. Approve covers confirming a payment.','view,create,edit,delete,approve','Poultry',62),
 ('poultry','suppliers','Purchasing','Suppliers','Supplier records and balances.','view,create,edit,delete','Poultry',70),
 ('poultry','expenses','Finance','Expenses','Expense entry. Approve covers authorising an expense.','view,create,edit,delete,approve,export','Poultry',80),
 ('poultry','cash','Finance','Cash & Accounts','Cash accounts and the cash ledger.','view,create,edit,delete,export','Poultry',81),
 ('poultry','daily-closing','Finance','Daily Closing','End-of-day closing. Approve locks the day.','view,create,edit,approve','Poultry',82),
 ('poultry','staff','People','Staff','Staff records for this company.','view,create,edit,delete','Poultry',90),
 ('poultry','payroll','People','Payroll','Payroll runs. Approve authorises payment.','view,create,edit,delete,approve,export','Poultry',91),
 ('poultry','drivers','Logistics','Drivers','Driver records.','view,create,edit,delete','Poultry',100),
 ('poultry','vehicles','Logistics','Vehicles','Vehicle records.','view,create,edit,delete','Poultry',101),
 ('poultry','routes','Logistics','Routes','Delivery routes.','view,create,edit,delete','Poultry',102),
 ('poultry','deliveries','Logistics','Deliveries','Delivery notes and dispatch.','view,create,edit,delete','Poultry',103),
 ('poultry','driver-returns','Logistics','Driver Returns','Cash and stock returned by drivers. Approve accepts a return.','view,create,edit,delete,approve','Poultry',104),
 ('poultry','reports','Reports','Reports','All reports for this company.','view,export','Poultry',110);

-- --- Water -------------------------------------------------------------------
INSERT INTO @cat VALUES
 ('water','daily-production','Production','Daily Production','Daily water production entry.','view,create,edit,delete,export','Water',20),
 ('water','production-batches','Production','Production Batches','Bagging and bottling batches. Approve covers posting a batch.','view,create,edit,delete,approve','Water',21),
 ('water','production-losses','Production','Production Losses','Losses recorded during production.','view,create,edit,delete','Water',22),
 ('water','boreholes','Assets','Boreholes','Borehole records and yields.','view,create,edit,delete','Water',30),
 ('water','machines','Assets','Machines','Production machines.','view,create,edit,delete','Water',31),
 ('water','maintenance','Assets','Maintenance','Maintenance jobs. Approve signs off completion.','view,create,edit,delete,approve','Water',32),
 ('water','raw-materials','Inventory','Raw Materials','Sachets, bottles, caps and other inputs.','view,create,edit,delete','Water',50),
 ('water','inventory','Inventory','Inventory','General inventory items.','view,create,edit,delete','Water',51),
 ('water','stock','Inventory','Stock','Stock balances and adjustments.','view,edit,export','Water',52),
 ('water','products','Inventory','Products','Sellable products and their pricing.','view,create,edit,delete','Water',53),
 ('water','sales','Sales & Customers','Sales','Sales orders and invoices.','view,create,edit,delete,export','Water',60),
 ('water','customers','Sales & Customers','Customers','Customer records and balances.','view,create,edit,delete,export','Water',61),
 ('water','payments','Sales & Customers','Customer Payments','Payments received. Approve covers confirming a payment.','view,create,edit,delete,approve','Water',62),
 ('water','suppliers','Purchasing','Suppliers','Supplier records and balances.','view,create,edit,delete','Water',70),
 ('water','expenses','Finance','Expenses','Expense entry. Approve covers authorising an expense.','view,create,edit,delete,approve,export','Water',80),
 ('water','cash','Finance','Cash & Accounts','Cash accounts and the cash ledger.','view,create,edit,delete,export','Water',81),
 ('water','daily-closing','Finance','Daily Closing','End-of-day closing. Approve locks the day.','view,create,edit,approve','Water',82),
 ('water','staff','People','Staff','Staff records for this company.','view,create,edit,delete','Water',90),
 ('water','payroll','People','Payroll','Payroll runs. Approve authorises payment.','view,create,edit,delete,approve,export','Water',91),
 ('water','drivers','Logistics','Drivers','Driver records.','view,create,edit,delete','Water',100),
 ('water','vehicles','Logistics','Vehicles','Vehicle records.','view,create,edit,delete','Water',101),
 ('water','routes','Logistics','Routes','Delivery routes.','view,create,edit,delete','Water',102),
 ('water','driver-returns','Logistics','Driver Returns','Cash and stock returned by drivers. Approve accepts a return.','view,create,edit,delete,approve','Water',103),
 ('water','reports','Reports','Reports','All reports for this company.','view,export','Water',110);

-- --- Generic company ---------------------------------------------------------
INSERT INTO @cat VALUES
 ('generic','products','Inventory','Products','Sellable products and their pricing.','view,create,edit,delete','Generic',50),
 ('generic','inventory','Inventory','Inventory','Inventory items and balances.','view,create,edit,delete','Generic',51),
 ('generic','stock-adjustments','Inventory','Stock Adjustments','Manual stock corrections. Approve authorises the adjustment.','view,create,edit,delete,approve','Generic',52),
 ('generic','sales','Sales & Customers','Sales','Sales orders and invoices.','view,create,edit,delete,export','Generic',60),
 ('generic','customers','Sales & Customers','Customers','Customer records and balances.','view,create,edit,delete,export','Generic',61),
 ('generic','payments','Sales & Customers','Customer Payments','Payments received. Approve covers confirming a payment.','view,create,edit,delete,approve','Generic',62),
 ('generic','purchases','Purchasing','Purchases','Purchase orders and goods received. Approve authorises the purchase.','view,create,edit,delete,approve','Generic',70),
 ('generic','suppliers','Purchasing','Suppliers','Supplier records and balances.','view,create,edit,delete','Generic',71),
 ('generic','supplier-payments','Purchasing','Supplier Payments','Payments made to suppliers. Approve releases the payment.','view,create,edit,delete,approve','Generic',72),
 ('generic','expenses','Finance','Expenses','Expense entry. Approve covers authorising an expense.','view,create,edit,delete,approve,export','Generic',80),
 ('generic','cash','Finance','Cash & Accounts','Cash accounts and the cash ledger.','view,create,edit,delete,export','Generic',81),
 ('generic','cash-transfers','Finance','Cash Transfers','Move money between cash accounts. Approve releases the transfer.','view,create,edit,delete,approve','Generic',82),
 ('generic','daily-closing','Finance','Daily Closing','End-of-day closing. Approve locks the day.','view,create,edit,approve','Generic',83),
 ('generic','staff','People','Staff','Staff records for this company.','view,create,edit,delete','Generic',90),
 ('generic','attendance','People','Attendance','Staff attendance records.','view,create,edit,delete','Generic',91),
 ('generic','payroll','People','Payroll','Payroll runs. Approve authorises payment.','view,create,edit,delete,approve,export','Generic',92),
 ('generic','reports','Reports','Reports','All reports for this company.','view,export','Generic',110);

-- --- Business Office (company-neutral) ---------------------------------------
INSERT INTO @cat VALUES
 ('office','organization','Organization','Organization Profile','Business office name, currency and country.','view,edit',NULL,10),
 ('office','companies','Organization','Companies','Create and configure the companies in the organization.','view,create,edit,delete',NULL,11),
 ('office','billing','Organization','Billing & Subscription','Plan, invoices and payment method.','view,edit',NULL,12),
 ('office','settings','Organization','Settings','Application and company settings.','view,edit',NULL,13),
 ('office','employees','People','Employees','Org-wide employee records and their company access.','view,create,edit,delete',NULL,20),
 ('office','access','Access','Access Management','Roles, assignments and permission overrides.','view,create,edit,delete',NULL,30),
 ('office','audit-log','Access','Activity Log','System activity and the audit trail.','view,export',NULL,31);

-- Expand the CSV into one row per action. Delete and approve are inherently
-- destructive; cost visibility and access management are marked dangerous too
-- so the matrix can colour them even though the action is only 'view'.
--
-- MERGE rather than INSERT-if-missing so that correcting a label or description
-- above and re-applying the migration actually updates it, the same way the
-- built-in role grants below rebuild.
--
-- Deliberately no WHEN NOT MATCHED BY SOURCE clause, so this never deletes.
-- FK_IamRolePermissions_Permission has no cascade, so removing a key that any
-- role still grants would be REFUSED by the foreign key and fail the migration
-- midway. Retiring a permission means revoking its grants first, which deserves
-- its own migration rather than happening as a side effect of editing this list.
MERGE dbo.IamPermissions AS t
USING (
    SELECT
        PermissionKey = CONCAT(c.Module, N'.', c.Resource, N'.', LTRIM(RTRIM(s.value))),
        c.Module,
        c.Resource,
        [Action] = LTRIM(RTRIM(s.value)),
        PermissionGroup = c.Grp,
        c.ResourceLabel,
        Description = c.Descr,
        c.CompanyType,
        IsDangerous = CASE
            WHEN LTRIM(RTRIM(s.value)) IN (N'delete', N'approve') THEN 1
            WHEN c.Resource IN (N'feed-production-cost', N'access', N'billing') THEN 1
            ELSE 0
        END,
        c.SortOrder
    FROM @cat c
    CROSS APPLY STRING_SPLIT(c.Actions, ',') s
) AS s
ON t.PermissionKey = s.PermissionKey
WHEN MATCHED THEN UPDATE SET
    t.Module = s.Module, t.Resource = s.Resource, t.[Action] = s.[Action],
    t.PermissionGroup = s.PermissionGroup, t.ResourceLabel = s.ResourceLabel,
    t.Description = s.Description, t.CompanyType = s.CompanyType,
    t.IsDangerous = s.IsDangerous, t.SortOrder = s.SortOrder
WHEN NOT MATCHED THEN
    INSERT (PermissionKey, Module, Resource, [Action], PermissionGroup, ResourceLabel, Description, CompanyType, IsDangerous, SortOrder)
    VALUES (s.PermissionKey, s.Module, s.Resource, s.[Action], s.PermissionGroup, s.ResourceLabel, s.Description, s.CompanyType, s.IsDangerous, s.SortOrder);

-- PRINT takes a scalar expression, not a subquery: putting the SELECT inline
-- makes the WHOLE BATCH fail to compile, which silently skips the seed above it.
DECLARE @catalogCount INT = (SELECT COUNT(*) FROM dbo.IamPermissions);
PRINT CONCAT(N'199: catalog holds ', @catalogCount, N' permission key(s).');
GO

-- -----------------------------------------------------------------------------
-- 3. Built-in roles.
--
--    OwnerUserId NULL means the role belongs to no organization in particular -
--    every org sees the same nine, and none of them can be edited or deleted.
--    Grants are expressed as set queries over the catalog rather than literal
--    key lists, so a role picks up new keys of the same shape automatically
--    when a module is added.
-- -----------------------------------------------------------------------------
MERGE dbo.IamRoles AS t
USING (VALUES
    (N'sys-owner',         N'Owner',                N'Full control, including access management. Cannot be locked out.', 1),
    (N'sys-org-admin',     N'Organization Admin',   N'Everything across every company, including users and access.', 0),
    (N'sys-company-admin', N'Company Admin',        N'Everything inside the companies they are assigned to.', 0),
    (N'sys-manager',       N'Manager',              N'Day-to-day running of a company, including approvals. Cannot delete records.', 0),
    (N'sys-accountant',    N'Accountant',           N'Finance, sales, purchasing and reports. Cannot delete records.', 0),
    (N'sys-storekeeper',   N'Storekeeper',          N'Stock, inventory, feed and production. No financial figures.', 0),
    (N'sys-data-entry',    N'Data Entry',           N'Record daily operations. No finance, no deletions, no approvals.', 0),
    (N'sys-sales-clerk',   N'Sales Clerk',          N'Take sales and record customer payments.', 0),
    (N'sys-auditor',       N'Auditor',              N'Read-only across everything. Can view and export, change nothing.', 0)
) AS s (RoleKey, Name, Description, IsSuperuser)
ON t.RoleKey = s.RoleKey
WHEN MATCHED THEN UPDATE SET
    t.Name = s.Name, t.Description = s.Description,
    t.IsSuperuser = s.IsSuperuser, t.IsSystem = 1, t.UpdatedAt = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (RoleKey, OwnerUserId, Name, Description, CompanyType, IsSystem, IsSuperuser, IsActive)
    VALUES (s.RoleKey, NULL, s.Name, s.Description, NULL, 1, s.IsSuperuser, 1);
GO

-- Rebuild built-in grants from scratch each run, so editing the rules below and
-- re-applying the migration is enough to correct them.
DELETE rp
FROM dbo.IamRolePermissions rp
JOIN dbo.IamRoles r ON r.RoleId = rp.RoleId
WHERE r.IsSystem = 1;
GO

DECLARE
    @owner INT = (SELECT RoleId FROM dbo.IamRoles WHERE RoleKey = N'sys-owner'),
    @orgAdmin INT = (SELECT RoleId FROM dbo.IamRoles WHERE RoleKey = N'sys-org-admin'),
    @coAdmin INT = (SELECT RoleId FROM dbo.IamRoles WHERE RoleKey = N'sys-company-admin'),
    @manager INT = (SELECT RoleId FROM dbo.IamRoles WHERE RoleKey = N'sys-manager'),
    @acct INT = (SELECT RoleId FROM dbo.IamRoles WHERE RoleKey = N'sys-accountant'),
    @store INT = (SELECT RoleId FROM dbo.IamRoles WHERE RoleKey = N'sys-storekeeper'),
    @entry INT = (SELECT RoleId FROM dbo.IamRoles WHERE RoleKey = N'sys-data-entry'),
    @sales INT = (SELECT RoleId FROM dbo.IamRoles WHERE RoleKey = N'sys-sales-clerk'),
    @audit INT = (SELECT RoleId FROM dbo.IamRoles WHERE RoleKey = N'sys-auditor');

-- Owner and Organization Admin: everything. Owner is additionally a superuser,
-- so keys added by a later migration are covered without re-seeding.
INSERT INTO dbo.IamRolePermissions (RoleId, PermissionKey)
SELECT @owner, PermissionKey FROM dbo.IamPermissions;

INSERT INTO dbo.IamRolePermissions (RoleId, PermissionKey)
SELECT @orgAdmin, PermissionKey FROM dbo.IamPermissions;

-- Company Admin: everything inside a company, plus the read-only slice of the
-- Business Office they need to do the job. No billing, no access management.
INSERT INTO dbo.IamRolePermissions (RoleId, PermissionKey)
SELECT @coAdmin, PermissionKey FROM dbo.IamPermissions WHERE Module <> N'office'
UNION
SELECT @coAdmin, PermissionKey FROM dbo.IamPermissions
WHERE PermissionKey IN (N'office.employees.view', N'office.settings.view', N'office.audit-log.view');

-- Manager: runs the company day to day and can approve, but cannot delete.
INSERT INTO dbo.IamRolePermissions (RoleId, PermissionKey)
SELECT @manager, PermissionKey FROM dbo.IamPermissions
WHERE Module <> N'office' AND [Action] <> N'delete'
UNION
SELECT @manager, PermissionKey FROM dbo.IamPermissions
WHERE PermissionKey IN (N'office.employees.view', N'office.audit-log.view');

-- Accountant: the money-facing groups, plus cost visibility. No deletions.
INSERT INTO dbo.IamRolePermissions (RoleId, PermissionKey)
SELECT @acct, PermissionKey FROM dbo.IamPermissions
WHERE Module <> N'office'
  AND PermissionGroup IN (N'Finance', N'Sales & Customers', N'Purchasing', N'Reports')
  AND [Action] <> N'delete'
UNION
SELECT @acct, PermissionKey FROM dbo.IamPermissions
WHERE Resource = N'feed-production-cost'
UNION
SELECT @acct, PermissionKey FROM dbo.IamPermissions
WHERE PermissionKey = N'office.audit-log.view';

-- Storekeeper: physical goods only. Explicitly excludes cost figures.
INSERT INTO dbo.IamRolePermissions (RoleId, PermissionKey)
SELECT @store, PermissionKey FROM dbo.IamPermissions
WHERE Module <> N'office'
  AND PermissionGroup IN (N'Inventory', N'Feed', N'Production')
  AND Resource <> N'feed-production-cost'
  AND [Action] IN (N'view', N'create', N'edit')
UNION
SELECT @store, PermissionKey FROM dbo.IamPermissions
WHERE Resource = N'reports' AND [Action] = N'view';

-- Data Entry: records what happened. Nothing financial, nothing destructive.
INSERT INTO dbo.IamRolePermissions (RoleId, PermissionKey)
SELECT @entry, PermissionKey FROM dbo.IamPermissions
WHERE Module <> N'office'
  AND PermissionGroup IN (N'Production', N'Flock & Birds', N'Feed', N'Health', N'Logistics', N'Inventory', N'Assets')
  AND Resource <> N'feed-production-cost'
  AND [Action] IN (N'view', N'create', N'edit');

-- Sales Clerk: the counter. Sees products so they can quote a price.
INSERT INTO dbo.IamRolePermissions (RoleId, PermissionKey)
SELECT @sales, PermissionKey FROM dbo.IamPermissions
WHERE Module <> N'office'
  AND PermissionGroup = N'Sales & Customers'
  AND [Action] IN (N'view', N'create', N'edit')
UNION
SELECT @sales, PermissionKey FROM dbo.IamPermissions
WHERE Resource IN (N'products', N'reports') AND [Action] = N'view';

-- Auditor: sees everything, changes nothing. Billing is excluded - reviewing
-- the farm's records does not require the card on file.
INSERT INTO dbo.IamRolePermissions (RoleId, PermissionKey)
SELECT @audit, PermissionKey FROM dbo.IamPermissions
WHERE [Action] IN (N'view', N'export') AND Resource <> N'billing';

-- Scalar variable, not an inline subquery — see the note on the catalog PRINT.
DECLARE @grantCount INT = (
    SELECT COUNT(*) FROM dbo.IamRolePermissions rp
    JOIN dbo.IamRoles r ON r.RoleId = rp.RoleId WHERE r.IsSystem = 1);
PRINT CONCAT(N'199: seeded ', @grantCount, N' built-in role grant(s).');
GO

-- -----------------------------------------------------------------------------
-- 4. The read path.
--
--    Resolution order, and the only place it is written down:
--      1. an unexpired user-level Deny wins outright
--      2. an unexpired user-level Allow grants
--      3. the union of unexpired role grants for this company or org-wide
--      4. otherwise denied
--
--    A superuser role short-circuits to the whole catalog. Source is returned
--    so the UI can answer "which role gave them this?" without a second query.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spIam_GetEffectivePermissions
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @now DATETIME2 = SYSUTCDATETIME();

    -- Assignments in scope: org-wide, or for the company being asked about.
    DECLARE @roles TABLE (RoleId INT PRIMARY KEY, RoleName NVARCHAR(100), IsSuperuser BIT);
    INSERT INTO @roles (RoleId, RoleName, IsSuperuser)
    SELECT DISTINCT r.RoleId, r.Name, r.IsSuperuser
    FROM dbo.IamUserRoles ur
    JOIN dbo.IamRoles r ON r.RoleId = ur.RoleId
    WHERE ur.UserId = @UserId
      AND r.IsActive = 1
      AND (ur.ExpiresAt IS NULL OR ur.ExpiresAt > @now)
      AND (ur.FarmId IS NULL OR (@FarmId IS NOT NULL AND ur.FarmId = @FarmId));

    DECLARE @denies TABLE (PermissionKey NVARCHAR(120) PRIMARY KEY);
    INSERT INTO @denies (PermissionKey)
    SELECT DISTINCT up.PermissionKey
    FROM dbo.IamUserPermissions up
    WHERE up.UserId = @UserId
      AND up.Effect = N'Deny'
      AND (up.ExpiresAt IS NULL OR up.ExpiresAt > @now)
      AND (up.FarmId IS NULL OR (@FarmId IS NOT NULL AND up.FarmId = @FarmId));

    IF EXISTS (SELECT 1 FROM @roles WHERE IsSuperuser = 1)
    BEGIN
        SELECT p.PermissionKey, N'superuser' AS Source
        FROM dbo.IamPermissions p
        WHERE NOT EXISTS (SELECT 1 FROM @denies d WHERE d.PermissionKey = p.PermissionKey);
        RETURN;
    END

    SELECT PermissionKey, MIN(Source) AS Source
    FROM (
        SELECT rp.PermissionKey, CONCAT(N'role:', r.RoleName) AS Source
        FROM dbo.IamRolePermissions rp
        JOIN @roles r ON r.RoleId = rp.RoleId

        UNION ALL

        SELECT up.PermissionKey, N'override' AS Source
        FROM dbo.IamUserPermissions up
        WHERE up.UserId = @UserId
          AND up.Effect = N'Allow'
          AND (up.ExpiresAt IS NULL OR up.ExpiresAt > @now)
          AND (up.FarmId IS NULL OR (@FarmId IS NOT NULL AND up.FarmId = @FarmId))
    ) x
    WHERE NOT EXISTS (SELECT 1 FROM @denies d WHERE d.PermissionKey = x.PermissionKey)
    GROUP BY PermissionKey;
END
GO

-- The catalog, for the permission matrix UI. Returned whole; it is small and
-- static, and the client filters by company type.
CREATE OR ALTER PROCEDURE dbo.spIam_GetCatalog
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PermissionKey, Module, Resource, [Action], PermissionGroup,
           ResourceLabel, Description, CompanyType, IsDangerous, SortOrder
    FROM dbo.IamPermissions
    ORDER BY Module, SortOrder, Resource, [Action];
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spIam_GetEffectivePermissions TO [Techretainer];
    GRANT EXECUTE ON dbo.spIam_GetCatalog              TO [Techretainer];
    GRANT SELECT  ON dbo.IamPermissions                TO [Techretainer];
    PRINT N'199: granted EXECUTE to Techretainer.';
END
GO

PRINT N'199_IamFoundation.sql complete.';
GO
