-- =============================================================================
-- Migration 082: Payroll Details (with YTD) + Default System Customers
-- =============================================================================
-- Implements two specs from Migrations/ompal/:
--
-- 1. "Payroll Details Page, Delivery Return Approval, Delivery Sales Posting
--    Modes…" §1 — backend support for the full Payroll Run Details page.
--    Adds spWaterPayrollRun_GetDetailsWithYtd which returns 4 result sets:
--       Set 1: Run header (incl. all audit + status timestamps)
--       Set 2: Run items (employee breakdown)
--       Set 3: YTD totals + per-staff YTD breakdown for the run's year
--       Set 4: Linked WaterExpense row (if any)
--    The "year" is the calendar year of the run's PeriodStart, computed off
--    Approved/Paid runs only so unapproved drafts don't pollute reports.
--
-- 2. "Payroll Details Page…" §2 + the standalone "Add Button to Create Default
--    System Customers" prompt — schema + SPs for system-managed default
--    customers that back Summary-Only delivery sales and walk-in sales.
--    Adds three columns to dbo.WaterCustomers:
--       CustomerType         NVARCHAR(40)   NULL  -- 'SystemDefault' for these
--       DefaultCustomerType  NVARCHAR(40)   NULL  -- 'GeneralSales' | 'GeneralDelivery' | 'GeneralCredit'
--       IsDefaultCustomer    BIT            NOT NULL DEFAULT 0
--       IsSystemGenerated    BIT            NOT NULL DEFAULT 0
--       IsActive             BIT            NOT NULL DEFAULT 1
--    Filtered unique index on (FarmId, DefaultCustomerType) WHERE
--    DefaultCustomerType IS NOT NULL — guarantees no duplicates.
--
-- SPs
--   spWaterCustomer_CreateDefaults  — ensures the three default customers
--                                     exist for the given farm. Returns rows
--                                     for each (created or pre-existing) plus
--                                     a 'wasCreated' flag.
--   spWaterCustomer_GetDefault      — quick lookup by DefaultCustomerType.
--                                     Used by the delivery-return SP when
--                                     SalesPostingMode='Summary'.
--
-- Auto-seed
--   spWaterCompany_Setup now calls spWaterCustomer_CreateDefaults at the end
--   so every new Water company gets the three default customers automatically
--   (re-runs are safe — the index handles dedupe).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Schema additions on dbo.WaterCustomers
-- -----------------------------------------------------------------------------
IF COL_LENGTH(N'dbo.WaterCustomers', N'CustomerType') IS NULL
    ALTER TABLE dbo.WaterCustomers ADD CustomerType NVARCHAR(40) NULL;
GO
IF COL_LENGTH(N'dbo.WaterCustomers', N'DefaultCustomerType') IS NULL
    ALTER TABLE dbo.WaterCustomers ADD DefaultCustomerType NVARCHAR(40) NULL;
GO
IF COL_LENGTH(N'dbo.WaterCustomers', N'IsDefaultCustomer') IS NULL
    ALTER TABLE dbo.WaterCustomers ADD IsDefaultCustomer BIT NOT NULL CONSTRAINT DF_WaterCustomers_IsDefault DEFAULT (0);
GO
IF COL_LENGTH(N'dbo.WaterCustomers', N'IsSystemGenerated') IS NULL
    ALTER TABLE dbo.WaterCustomers ADD IsSystemGenerated BIT NOT NULL CONSTRAINT DF_WaterCustomers_IsSystem DEFAULT (0);
GO
IF COL_LENGTH(N'dbo.WaterCustomers', N'IsActive') IS NULL
    ALTER TABLE dbo.WaterCustomers ADD IsActive BIT NOT NULL CONSTRAINT DF_WaterCustomers_IsActive DEFAULT (1);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UX_WaterCustomers_FarmDefaultType'
      AND object_id = OBJECT_ID(N'dbo.WaterCustomers')
)
BEGIN
    CREATE UNIQUE INDEX UX_WaterCustomers_FarmDefaultType
        ON dbo.WaterCustomers (FarmId, DefaultCustomerType)
        WHERE DefaultCustomerType IS NOT NULL;
END
GO

-- -----------------------------------------------------------------------------
-- 2. spWaterPayrollRun_GetDetailsWithYtd
--    Powers the /water-payroll/[id]/details page. Four result sets so the
--    frontend can issue one round-trip for the whole view.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterPayrollRun_GetDetailsWithYtd
    @WaterPayrollRunId INT,
    @FarmId            NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PeriodStart DATE;
    SELECT @PeriodStart = PeriodStart
    FROM   dbo.WaterPayrollRuns
    WHERE  WaterPayrollRunId = @WaterPayrollRunId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @PeriodStart IS NULL
    BEGIN
        -- Empty result sets so the C# reader doesn't have to special-case.
        SELECT TOP 0 1 AS WaterPayrollRunId;
        SELECT TOP 0 1 AS WaterPayrollItemId;
        SELECT TOP 0 1 AS YtdTotalsRow;
        SELECT TOP 0 1 AS LinkedExpenseRow;
        RETURN;
    END

    DECLARE @Year INT = YEAR(@PeriodStart);
    DECLARE @YearStart DATE = DATEFROMPARTS(@Year, 1, 1);
    DECLARE @YearEnd   DATE = DATEFROMPARTS(@Year, 12, 31);

    -- Set 1: run header + cash account name + all audit cols (matches the
    -- existing _GetById shape so the model reader is reused).
    SELECT pr.WaterPayrollRunId, pr.FarmId,
           pr.PeriodStart, pr.PeriodEnd, pr.PayDate,
           pr.TotalGrossPay, pr.TotalDeductions, pr.TotalNetPay,
           pr.Status, pr.WaterCashAccountId, ca.AccountName AS CashAccountName,
           pr.Notes,
           pr.CreatedBy, pr.ApprovedBy, pr.ApprovedAt,
           pr.PaidBy, pr.PaidAt,
           pr.ReopenedBy, pr.ReopenedAt, pr.ReopenReason,
           pr.ReapprovedBy, pr.ReapprovedAt,
           pr.CreatedAt, pr.UpdatedAt
    FROM   dbo.WaterPayrollRuns pr
    LEFT JOIN dbo.WaterCashAccounts ca ON ca.WaterCashAccountId = pr.WaterCashAccountId
    WHERE  pr.WaterPayrollRunId = @WaterPayrollRunId AND pr.FarmId = @FarmId;

    -- Set 2: items
    SELECT pi.WaterPayrollItemId, pi.WaterPayrollRunId, pi.WaterStaffId,
           CONCAT(s.FirstName, N' ', s.LastName) AS StaffName,
           s.Role AS StaffRole,
           pi.BasicPay, pi.DailyWage, pi.Commission, pi.Bonus, pi.Deductions,
           pi.NetPay, pi.PaymentMethod, pi.Notes, pi.CreatedAt
    FROM   dbo.WaterPayrollItems pi
    LEFT JOIN dbo.WaterStaff s ON s.WaterStaffId = pi.WaterStaffId
    WHERE  pi.WaterPayrollRunId = @WaterPayrollRunId
    ORDER BY pi.WaterPayrollItemId;

    -- Set 3a: YTD totals row (single row).
    --   Source: Approved or Paid runs only — drafts & cancelled excluded.
    SELECT  @Year                          AS Year,
            ISNULL(SUM(pr.TotalGrossPay),   0) AS YtdGrossPaid,
            ISNULL(SUM(pr.TotalDeductions), 0) AS YtdDeductions,
            ISNULL(SUM(pr.TotalNetPay),     0) AS YtdNetPaid,
            COUNT(DISTINCT pr.WaterPayrollRunId) AS TotalPayrollRuns,
            COUNT(DISTINCT pi.WaterStaffId)      AS TotalStaffPaid
    FROM   dbo.WaterPayrollRuns pr
    LEFT JOIN dbo.WaterPayrollItems pi ON pi.WaterPayrollRunId = pr.WaterPayrollRunId
    WHERE  pr.FarmId = @FarmId
      AND  pr.IsDeleted = 0
      AND  pr.Status IN (N'Approved', N'Paid')
      AND  pr.PeriodStart >= @YearStart
      AND  pr.PeriodStart <= @YearEnd;

    -- Set 3b: per-staff YTD breakdown.
    SELECT  pi.WaterStaffId,
            CONCAT(s.FirstName, N' ', s.LastName) AS StaffName,
            s.Role  AS StaffRole,
            SUM(pi.BasicPay)   AS YtdBasic,
            SUM(pi.DailyWage)  AS YtdDaily,
            SUM(pi.Commission) AS YtdCommission,
            SUM(pi.Bonus)      AS YtdBonus,
            SUM(pi.Deductions) AS YtdDeductions,
            SUM(pi.BasicPay + pi.DailyWage + pi.Commission + pi.Bonus) AS YtdGross,
            SUM(pi.NetPay)     AS YtdNet
    FROM   dbo.WaterPayrollItems pi
    INNER JOIN dbo.WaterPayrollRuns pr ON pr.WaterPayrollRunId = pi.WaterPayrollRunId
    LEFT  JOIN dbo.WaterStaff       s  ON s.WaterStaffId       = pi.WaterStaffId
    WHERE  pr.FarmId = @FarmId
      AND  pr.IsDeleted = 0
      AND  pr.Status IN (N'Approved', N'Paid')
      AND  pr.PeriodStart >= @YearStart
      AND  pr.PeriodStart <= @YearEnd
    GROUP BY pi.WaterStaffId, s.FirstName, s.LastName, s.Role
    ORDER BY YtdNet DESC;

    -- Set 4: linked expense (zero rows if not yet approved or already cancelled).
    SELECT TOP (1)
           e.WaterExpenseId, e.FarmId, e.ExpenseDate,
           e.WaterExpenseCategoryId, c.Name AS CategoryName,
           e.Description, e.Amount, e.PaymentMethod,
           e.WaterCashAccountId, ca.AccountName AS CashAccountName,
           e.Status, e.Notes,
           e.CreatedBy, e.ApprovedBy, e.ApprovedAt,
           e.SourceType, e.SourceId,
           e.CreatedAt, e.UpdatedAt
    FROM   dbo.WaterExpenses e
    LEFT JOIN dbo.WaterExpenseCategories c  ON c.WaterExpenseCategoryId = e.WaterExpenseCategoryId
    LEFT JOIN dbo.WaterCashAccounts      ca ON ca.WaterCashAccountId    = e.WaterCashAccountId
    WHERE  e.FarmId = @FarmId
      AND  e.SourceType = N'Payroll'
      AND  e.SourceId = @WaterPayrollRunId
      AND  e.IsDeleted = 0;
END
GO

-- -----------------------------------------------------------------------------
-- 3. spWaterCustomer_CreateDefaults — idempotent, one row per default type
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterCustomer_CreateDefaults
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Defaults TABLE (
        DefaultType NVARCHAR(40) NOT NULL PRIMARY KEY,
        DisplayName NVARCHAR(150) NOT NULL,
        Notes       NVARCHAR(500) NULL
    );
    INSERT INTO @Defaults (DefaultType, DisplayName, Notes) VALUES
        (N'GeneralSales',    N'General Sales Customer',    N'Walk-in / cash sales without per-customer tracking.'),
        (N'GeneralDelivery', N'General Delivery Customer', N'Used for delivery-return Summary Only posting.'),
        (N'GeneralCredit',   N'General Credit Customer',   N'Catches credit balances when no customer is selected.');

    BEGIN TRANSACTION;

    DECLARE @Created TABLE (
        WaterCustomerId     INT,
        DefaultCustomerType NVARCHAR(40),
        Name                NVARCHAR(150),
        WasCreated          BIT
    );

    INSERT INTO dbo.WaterCustomers
        (FarmId, Name, CustomerType, DefaultCustomerType,
         IsDefaultCustomer, IsSystemGenerated, IsActive, Notes)
    OUTPUT INSERTED.WaterCustomerId, INSERTED.DefaultCustomerType, INSERTED.Name, 1
    INTO   @Created (WaterCustomerId, DefaultCustomerType, Name, WasCreated)
    SELECT @FarmId, d.DisplayName, N'SystemDefault', d.DefaultType,
           1, 1, 1, d.Notes
    FROM   @Defaults d
    WHERE  NOT EXISTS (
        SELECT 1 FROM dbo.WaterCustomers c
        WHERE  c.FarmId = @FarmId
          AND  c.DefaultCustomerType = d.DefaultType
    );

    -- Also surface the pre-existing rows so the C# caller can report which are
    -- new vs. already-there.
    INSERT INTO @Created (WaterCustomerId, DefaultCustomerType, Name, WasCreated)
    SELECT c.WaterCustomerId, c.DefaultCustomerType, c.Name, 0
    FROM   dbo.WaterCustomers c
    INNER JOIN @Defaults d ON d.DefaultType = c.DefaultCustomerType
    WHERE  c.FarmId = @FarmId
      AND  NOT EXISTS (SELECT 1 FROM @Created x WHERE x.WaterCustomerId = c.WaterCustomerId);

    COMMIT TRANSACTION;

    SELECT WaterCustomerId, DefaultCustomerType, Name, WasCreated
    FROM   @Created
    ORDER BY DefaultCustomerType;
END
GO

-- -----------------------------------------------------------------------------
-- 4. spWaterCustomer_GetDefault — single-row lookup for the delivery SP
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterCustomer_GetDefault
    @FarmId              NVARCHAR(450),
    @DefaultCustomerType NVARCHAR(40)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (1) WaterCustomerId, FarmId, Name,
           CustomerType, DefaultCustomerType,
           IsDefaultCustomer, IsSystemGenerated, IsActive
    FROM   dbo.WaterCustomers
    WHERE  FarmId = @FarmId
      AND  DefaultCustomerType = @DefaultCustomerType;
END
GO

-- -----------------------------------------------------------------------------
-- 5. Auto-seed defaults when a Water company is set up.
--    Re-wraps the existing spWaterCompany_Setup body and appends the
--    spWaterCustomer_CreateDefaults call.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterCompany_Setup
    @FarmId                  NVARCHAR(450),
    @BrandName               NVARCHAR(150)  = NULL,
    @BusinessType            NVARCHAR(30)   = 'Sachet',
    @ProductionSiteAddress   NVARCHAR(500)  = NULL,
    @MainLocation            NVARCHAR(255)  = NULL,
    @WaterSourceType         NVARCHAR(30)   = 'Borehole',
    @DefaultCurrency         NVARCHAR(10)   = 'GHC',
    @DefaultBagSachetCount   INT            = 30,
    @OwnerName               NVARCHAR(150)  = NULL,
    @PhoneNumber             NVARCHAR(50)   = NULL,
    @Notes                   NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Farms WHERE FarmId = @FarmId)
    BEGIN
        RAISERROR('Farm %s does not exist.', 16, 1, @FarmId);
        RETURN;
    END
    DECLARE @FarmType NVARCHAR(50);
    SELECT @FarmType = Type FROM dbo.Farms WHERE FarmId = @FarmId;
    IF (@FarmType IS NULL OR @FarmType <> 'Water')
    BEGIN
        RAISERROR('Farm %s is not a Water company (Type=%s).', 16, 1, @FarmId, @FarmType);
        RETURN;
    END

    IF @BusinessType    NOT IN ('Sachet', 'Bottled', 'Both')
    BEGIN RAISERROR('BusinessType must be Sachet, Bottled, or Both.', 16, 1); RETURN; END
    IF @WaterSourceType NOT IN ('Borehole', 'GhanaWater', 'Tanker', 'Mixed')
    BEGIN RAISERROR('WaterSourceType must be Borehole, GhanaWater, Tanker, or Mixed.', 16, 1); RETURN; END
    IF @DefaultBagSachetCount < 1
    BEGIN RAISERROR('DefaultBagSachetCount must be at least 1.', 16, 1); RETURN; END

    BEGIN TRANSACTION;

    IF EXISTS (SELECT 1 FROM dbo.WaterCompanyProfiles WHERE FarmId = @FarmId)
    BEGIN
        UPDATE dbo.WaterCompanyProfiles
        SET    BrandName             = @BrandName,
               BusinessType          = @BusinessType,
               ProductionSiteAddress = @ProductionSiteAddress,
               MainLocation          = @MainLocation,
               WaterSourceType       = @WaterSourceType,
               DefaultCurrency       = ISNULL(@DefaultCurrency, 'GHC'),
               DefaultBagSachetCount = ISNULL(@DefaultBagSachetCount, 30),
               OwnerName             = @OwnerName,
               PhoneNumber           = @PhoneNumber,
               Notes                 = @Notes,
               UpdatedAt             = SYSUTCDATETIME()
        WHERE  FarmId = @FarmId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.WaterCompanyProfiles (
            FarmId, BrandName, BusinessType, ProductionSiteAddress, MainLocation,
            WaterSourceType, DefaultCurrency, DefaultBagSachetCount,
            OwnerName, PhoneNumber, Notes
        )
        VALUES (
            @FarmId, @BrandName, @BusinessType, @ProductionSiteAddress, @MainLocation,
            @WaterSourceType, ISNULL(@DefaultCurrency, 'GHC'), ISNULL(@DefaultBagSachetCount, 30),
            @OwnerName, @PhoneNumber, @Notes
        );
    END

    EXEC dbo.spWaterFinance_SeedDefaults @FarmId = @FarmId;

    -- Migration 082 — auto-seed default customers (idempotent).
    EXEC dbo.spWaterCustomer_CreateDefaults @FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT WaterCompanyProfileId, FarmId, BrandName, BusinessType,
           ProductionSiteAddress, MainLocation, WaterSourceType,
           DefaultCurrency, DefaultBagSachetCount, OwnerName, PhoneNumber, Notes,
           CreatedAt, UpdatedAt
    FROM   dbo.WaterCompanyProfiles
    WHERE  FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- 6. Update spWaterCustomer_GetAll to surface the new system-customer fields
--    AND the OutstandingBalance the C# reader already expects.
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterCustomer_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    ;WITH OB AS (
        SELECT s.WaterCustomerId,
               SUM(s.TotalAmount - s.AmountPaid) AS Outstanding
        FROM   dbo.WaterSales s
        WHERE  s.FarmId = @FarmId
          AND  s.Status NOT IN (N'Cancelled')
          AND  s.WaterCustomerId IS NOT NULL
        GROUP BY s.WaterCustomerId
    )
    SELECT c.WaterCustomerId, c.FarmId, c.Name,
           c.ContactPhone, c.ContactEmail, c.Address, c.City, c.Notes,
           c.CreatedDate, c.UpdatedDate,
           c.CustomerType, c.DefaultCustomerType,
           c.IsDefaultCustomer, c.IsSystemGenerated, c.IsActive,
           ISNULL(ob.Outstanding, 0) AS OutstandingBalance
    FROM   dbo.WaterCustomers c
    LEFT JOIN OB ob ON ob.WaterCustomerId = c.WaterCustomerId
    WHERE  c.FarmId = @FarmId
    ORDER BY c.IsSystemGenerated DESC, c.Name;  -- system rows pinned to top
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterCustomer_GetById
    @WaterCustomerId INT,
    @FarmId          NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.WaterCustomerId, c.FarmId, c.Name,
           c.ContactPhone, c.ContactEmail, c.Address, c.City, c.Notes,
           c.CreatedDate, c.UpdatedDate,
           c.CustomerType, c.DefaultCustomerType,
           c.IsDefaultCustomer, c.IsSystemGenerated, c.IsActive
    FROM   dbo.WaterCustomers c
    WHERE  c.WaterCustomerId = @WaterCustomerId AND c.FarmId = @FarmId;
END
GO

-- Refuse Delete on system-default customers — they back active sales/posting
-- workflows and accidentally removing them would silently break delivery
-- reconciliation. The frontend should gate the button too, but the SP is the
-- backstop.
CREATE OR ALTER PROCEDURE dbo.spWaterCustomer_Delete
    @WaterCustomerId INT,
    @FarmId          NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (
        SELECT 1 FROM dbo.WaterCustomers
        WHERE  WaterCustomerId = @WaterCustomerId AND FarmId = @FarmId
          AND  (IsSystemGenerated = 1 OR IsDefaultCustomer = 1)
    )
    BEGIN
        RAISERROR('System default customers cannot be deleted.', 16, 1);
        RETURN;
    END

    DELETE FROM dbo.WaterCustomers
    WHERE  WaterCustomerId = @WaterCustomerId AND FarmId = @FarmId;
END
GO

-- -----------------------------------------------------------------------------
-- 7. Grants
-- -----------------------------------------------------------------------------
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterPayrollRun_GetDetailsWithYtd TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterCustomer_CreateDefaults      TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterCustomer_GetDefault          TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterCompany_Setup                TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterCustomer_GetAll              TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterCustomer_GetById             TO [Techretainer];
    GRANT EXECUTE ON dbo.spWaterCustomer_Delete              TO [Techretainer];
END
GO
IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterPayrollRun_GetDetailsWithYtd TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterCustomer_CreateDefaults      TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterCustomer_GetDefault          TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterCompany_Setup                TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterCustomer_GetAll              TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterCustomer_GetById             TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterCustomer_Delete              TO PoultryAppRole;
END
GO

PRINT '082_AddPayrollDetailsAndDefaultCustomers.sql complete.';
GO
