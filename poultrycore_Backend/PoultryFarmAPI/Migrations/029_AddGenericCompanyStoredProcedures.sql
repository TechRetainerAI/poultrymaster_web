-- =============================================================================
-- Migration 029: Stored procedures for the Generic Company foundation
-- =============================================================================
-- Run AFTER 028_AddGenericCompanyFoundation.sql.
--
-- Style matches existing project conventions (see 026_AddMultiCompanyAnd
-- WaterStoredProcedures.sql): spEntity_Action, @FarmId-scoped, CREATE OR
-- ALTER so this script is safe to re-run.
--
-- Scope (Phase 1 - Foundation only):
--   * BusinessCategories: list active categories.
--   * GenericCompanyProfile: create with seed, get, update.
--   * GenericExpenseCategory: list, insert, update, soft-delete.
--   * GenericCashAccount:     list, insert, update, soft-delete.
--   * GenericCustomerType:    list (CRUD deferred to a later phase).
--   * GenericSupplierType:    list (CRUD deferred to a later phase).
--   * GenericPaymentMethod:   list (CRUD deferred to a later phase).
--
-- The "Setup" proc is intentionally idempotent: calling it twice on the same
-- FarmId will not duplicate seed rows. This matters because a client may
-- retry on transient errors and we never want a Farm to end up with two
-- "Main Cash Box" rows.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- BusinessCategories
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spBusinessCategory_GetAll
AS
BEGIN
    SET NOCOUNT ON;
    SELECT BusinessCategoryId, Name, Description, SortOrder, IsActive, CreatedAt, UpdatedAt
    FROM   dbo.BusinessCategories
    WHERE  IsActive = 1
    ORDER  BY SortOrder, Name;
END
GO

-- =============================================================================
-- GenericCompanyProfile + Setup
-- =============================================================================
-- spGenericCompany_Setup creates the profile row AND seeds the per-Farm default
-- expense categories, cash accounts, customer types, supplier types and
-- payment methods in one transaction.
--
-- This proc assumes the Farms row already exists (created via spCompany_Create
-- in the LoginAPI). It validates Type='Generic' before inserting anything so a
-- Poultry/Water farm cannot accidentally get a generic profile attached.
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericCompany_Setup
    @FarmId               NVARCHAR(450),
    @BusinessCategoryId   INT            = NULL,
    @BusinessDescription  NVARCHAR(500)  = NULL,
    @DefaultCurrency      NVARCHAR(10)   = 'GHC',
    @OpeningCashBalance   DECIMAL(14,2)  = 0,
    @BusinessStartDate    DATE           = NULL,
    @MainLocation         NVARCHAR(255)  = NULL,
    @OwnerName            NVARCHAR(150)  = NULL,
    @PhoneNumber          NVARCHAR(50)   = NULL,
    @Notes                NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- 1. Validate the farm exists and is Generic.
    IF NOT EXISTS (SELECT 1 FROM dbo.Farms WHERE FarmId = @FarmId)
    BEGIN
        RAISERROR('Farm %s does not exist.', 16, 1, @FarmId);
        RETURN;
    END

    DECLARE @FarmType NVARCHAR(50);
    SELECT @FarmType = Type FROM dbo.Farms WHERE FarmId = @FarmId;
    IF (@FarmType IS NULL OR @FarmType <> 'Generic')
    BEGIN
        RAISERROR('Farm %s is not a Generic company (Type=%s).', 16, 1, @FarmId, @FarmType);
        RETURN;
    END

    -- 2. Resolve the category snapshot up-front so the read at the end is cheap.
    DECLARE @CategoryName NVARCHAR(100) = NULL;
    IF (@BusinessCategoryId IS NOT NULL)
    BEGIN
        SELECT @CategoryName = Name FROM dbo.BusinessCategories WHERE BusinessCategoryId = @BusinessCategoryId;
        IF (@CategoryName IS NULL)
        BEGIN
            RAISERROR('BusinessCategoryId %d does not exist.', 16, 1, @BusinessCategoryId);
            RETURN;
        END
    END

    BEGIN TRANSACTION;

    -- 3. Insert profile (idempotent: skip if it already exists).
    IF NOT EXISTS (SELECT 1 FROM dbo.GenericCompanyProfiles WHERE FarmId = @FarmId)
    BEGIN
        INSERT INTO dbo.GenericCompanyProfiles (
            FarmId, BusinessCategoryId, BusinessCategoryNameSnapshot, BusinessDescription,
            DefaultCurrency, OpeningCashBalance, BusinessStartDate, MainLocation,
            OwnerName, PhoneNumber, Notes
        )
        VALUES (
            @FarmId, @BusinessCategoryId, @CategoryName, @BusinessDescription,
            ISNULL(@DefaultCurrency, 'GHC'), ISNULL(@OpeningCashBalance, 0), @BusinessStartDate, @MainLocation,
            @OwnerName, @PhoneNumber, @Notes
        );
    END

    -- 4. Seed default expense categories (skip ones that already exist).
    ;WITH seed (Name) AS (
        SELECT 'Rent'                       UNION ALL
        SELECT 'Utilities'                  UNION ALL
        SELECT 'Electricity'                UNION ALL
        SELECT 'Water'                      UNION ALL
        SELECT 'Internet'                   UNION ALL
        SELECT 'Fuel'                       UNION ALL
        SELECT 'Transport'                  UNION ALL
        SELECT 'Repairs and Maintenance'    UNION ALL
        SELECT 'Salaries and Wages'         UNION ALL
        SELECT 'Inventory Purchases'        UNION ALL
        SELECT 'Cleaning Supplies'          UNION ALL
        SELECT 'Marketing'                  UNION ALL
        SELECT 'Office Supplies'            UNION ALL
        SELECT 'Security'                   UNION ALL
        SELECT 'Bank Charges'               UNION ALL
        SELECT 'Mobile Money Charges'       UNION ALL
        SELECT 'Government Fees'            UNION ALL
        SELECT 'Loan Repayment'             UNION ALL
        SELECT 'Miscellaneous'
    )
    INSERT INTO dbo.GenericExpenseCategories (FarmId, Name)
    SELECT @FarmId, s.Name
    FROM   seed s
    WHERE  NOT EXISTS (
              SELECT 1 FROM dbo.GenericExpenseCategories e
              WHERE  e.FarmId = @FarmId AND e.Name = s.Name
           );

    -- 5. Seed default cash accounts. Opening balance only seeded into Main Cash
    --    Box, so the owner's stated OpeningCashBalance shows up immediately on
    --    the dashboard.
    IF NOT EXISTS (SELECT 1 FROM dbo.GenericCashAccounts WHERE FarmId = @FarmId AND AccountName = 'Main Cash Box')
    BEGIN
        INSERT INTO dbo.GenericCashAccounts (FarmId, AccountName, AccountType, OpeningBalance, CurrentBalance)
        VALUES (@FarmId, 'Main Cash Box', 'MainCashBox', ISNULL(@OpeningCashBalance, 0), ISNULL(@OpeningCashBalance, 0));
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.GenericCashAccounts WHERE FarmId = @FarmId AND AccountName = 'MoMo Wallet')
        INSERT INTO dbo.GenericCashAccounts (FarmId, AccountName, AccountType, OpeningBalance, CurrentBalance)
        VALUES (@FarmId, 'MoMo Wallet', 'MoMoWallet', 0, 0);

    IF NOT EXISTS (SELECT 1 FROM dbo.GenericCashAccounts WHERE FarmId = @FarmId AND AccountName = 'Bank Account')
        INSERT INTO dbo.GenericCashAccounts (FarmId, AccountName, AccountType, OpeningBalance, CurrentBalance)
        VALUES (@FarmId, 'Bank Account', 'BankAccount', 0, 0);

    IF NOT EXISTS (SELECT 1 FROM dbo.GenericCashAccounts WHERE FarmId = @FarmId AND AccountName = 'Petty Cash')
        INSERT INTO dbo.GenericCashAccounts (FarmId, AccountName, AccountType, OpeningBalance, CurrentBalance)
        VALUES (@FarmId, 'Petty Cash', 'PettyCash', 0, 0);

    -- 6. Seed default customer types.
    ;WITH ct (Name) AS (
        SELECT 'Individual' UNION ALL SELECT 'Business' UNION ALL SELECT 'Walk-in' UNION ALL
        SELECT 'Retail Customer' UNION ALL SELECT 'Wholesale Customer' UNION ALL SELECT 'Other'
    )
    INSERT INTO dbo.GenericCustomerTypes (FarmId, Name)
    SELECT @FarmId, ct.Name
    FROM   ct
    WHERE  NOT EXISTS (SELECT 1 FROM dbo.GenericCustomerTypes t WHERE t.FarmId = @FarmId AND t.Name = ct.Name);

    -- 7. Seed default supplier types.
    ;WITH st (Name) AS (
        SELECT 'Product Supplier' UNION ALL SELECT 'Service Provider' UNION ALL
        SELECT 'Contractor' UNION ALL SELECT 'Utility Provider' UNION ALL SELECT 'Other'
    )
    INSERT INTO dbo.GenericSupplierTypes (FarmId, Name)
    SELECT @FarmId, st.Name
    FROM   st
    WHERE  NOT EXISTS (SELECT 1 FROM dbo.GenericSupplierTypes t WHERE t.FarmId = @FarmId AND t.Name = st.Name);

    -- 8. Seed default payment methods.
    ;WITH pm (Name) AS (
        SELECT 'Cash' UNION ALL SELECT 'MoMo' UNION ALL SELECT 'Bank' UNION ALL
        SELECT 'Card' UNION ALL SELECT 'Credit' UNION ALL SELECT 'Mixed'
    )
    INSERT INTO dbo.GenericPaymentMethods (FarmId, Name)
    SELECT @FarmId, pm.Name
    FROM   pm
    WHERE  NOT EXISTS (SELECT 1 FROM dbo.GenericPaymentMethods p WHERE p.FarmId = @FarmId AND p.Name = pm.Name);

    COMMIT TRANSACTION;

    -- 9. Return the profile (joined with the category for display).
    SELECT p.GenericCompanyProfileId, p.FarmId, p.BusinessCategoryId,
           p.BusinessCategoryNameSnapshot, c.Name AS BusinessCategoryName,
           p.BusinessDescription, p.DefaultCurrency, p.OpeningCashBalance,
           p.BusinessStartDate, p.MainLocation, p.OwnerName, p.PhoneNumber,
           p.Notes, p.CreatedAt, p.UpdatedAt
    FROM   dbo.GenericCompanyProfiles p
    LEFT   JOIN dbo.BusinessCategories c ON c.BusinessCategoryId = p.BusinessCategoryId
    WHERE  p.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCompany_GetProfile
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.GenericCompanyProfileId, p.FarmId, p.BusinessCategoryId,
           p.BusinessCategoryNameSnapshot, c.Name AS BusinessCategoryName,
           p.BusinessDescription, p.DefaultCurrency, p.OpeningCashBalance,
           p.BusinessStartDate, p.MainLocation, p.OwnerName, p.PhoneNumber,
           p.Notes, p.CreatedAt, p.UpdatedAt
    FROM   dbo.GenericCompanyProfiles p
    LEFT   JOIN dbo.BusinessCategories c ON c.BusinessCategoryId = p.BusinessCategoryId
    WHERE  p.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCompany_UpdateProfile
    @FarmId               NVARCHAR(450),
    @BusinessCategoryId   INT            = NULL,
    @BusinessDescription  NVARCHAR(500)  = NULL,
    @DefaultCurrency      NVARCHAR(10)   = NULL,
    @OpeningCashBalance   DECIMAL(14,2)  = NULL,
    @BusinessStartDate    DATE           = NULL,
    @MainLocation         NVARCHAR(255)  = NULL,
    @OwnerName            NVARCHAR(150)  = NULL,
    @PhoneNumber          NVARCHAR(50)   = NULL,
    @Notes                NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CategoryName NVARCHAR(100) = NULL;
    IF (@BusinessCategoryId IS NOT NULL)
    BEGIN
        SELECT @CategoryName = Name FROM dbo.BusinessCategories WHERE BusinessCategoryId = @BusinessCategoryId;
        IF (@CategoryName IS NULL)
        BEGIN
            RAISERROR('BusinessCategoryId %d does not exist.', 16, 1, @BusinessCategoryId);
            RETURN;
        END
    END

    UPDATE dbo.GenericCompanyProfiles
    SET    BusinessCategoryId           = COALESCE(@BusinessCategoryId, BusinessCategoryId),
           BusinessCategoryNameSnapshot = COALESCE(@CategoryName, BusinessCategoryNameSnapshot),
           BusinessDescription          = COALESCE(@BusinessDescription, BusinessDescription),
           DefaultCurrency              = COALESCE(@DefaultCurrency, DefaultCurrency),
           OpeningCashBalance           = COALESCE(@OpeningCashBalance, OpeningCashBalance),
           BusinessStartDate            = COALESCE(@BusinessStartDate, BusinessStartDate),
           MainLocation                 = COALESCE(@MainLocation, MainLocation),
           OwnerName                    = COALESCE(@OwnerName, OwnerName),
           PhoneNumber                  = COALESCE(@PhoneNumber, PhoneNumber),
           Notes                        = COALESCE(@Notes, Notes),
           UpdatedAt                    = SYSUTCDATETIME()
    WHERE  FarmId = @FarmId;

    EXEC dbo.spGenericCompany_GetProfile @FarmId = @FarmId;
END
GO

-- =============================================================================
-- GenericExpenseCategory
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericExpenseCategory_GetAll
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericExpenseCategoryId, FarmId, Name, Description, IsActive,
           IsDeleted, CreatedAt, UpdatedAt
    FROM   dbo.GenericExpenseCategories
    WHERE  FarmId = @FarmId AND IsDeleted = 0
    ORDER  BY IsActive DESC, Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericExpenseCategory_Insert
    @FarmId       NVARCHAR(450),
    @Name         NVARCHAR(100),
    @Description  NVARCHAR(500) = NULL,
    @IsActive     BIT           = 1
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.GenericExpenseCategories (FarmId, Name, Description, IsActive)
    VALUES (@FarmId, @Name, @Description, @IsActive);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericExpenseCategory_Update
    @GenericExpenseCategoryId  INT,
    @FarmId                    NVARCHAR(450),
    @Name                      NVARCHAR(100),
    @Description               NVARCHAR(500) = NULL,
    @IsActive                  BIT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericExpenseCategories
    SET    Name = @Name, Description = @Description, IsActive = @IsActive,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericExpenseCategoryId = @GenericExpenseCategoryId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericExpenseCategory_Delete
    @GenericExpenseCategoryId  INT,
    @FarmId                    NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    -- Soft delete; later phases will reference this table from Expenses.
    UPDATE dbo.GenericExpenseCategories
    SET    IsDeleted = 1, IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericExpenseCategoryId = @GenericExpenseCategoryId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- GenericCashAccount
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericCashAccount_GetAll
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericCashAccountId, FarmId, AccountName, AccountType, OpeningBalance,
           CurrentBalance, AllowNegativeBalance, IsActive, Notes, CreatedAt, UpdatedAt
    FROM   dbo.GenericCashAccounts
    WHERE  FarmId = @FarmId
    ORDER  BY IsActive DESC, AccountName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCashAccount_Insert
    @FarmId                NVARCHAR(450),
    @AccountName           NVARCHAR(150),
    @AccountType           NVARCHAR(40),
    @OpeningBalance        DECIMAL(14,2) = 0,
    @AllowNegativeBalance  BIT           = 0,
    @Notes                 NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.GenericCashAccounts
        (FarmId, AccountName, AccountType, OpeningBalance, CurrentBalance, AllowNegativeBalance, Notes)
    VALUES
        (@FarmId, @AccountName, @AccountType, @OpeningBalance, @OpeningBalance, @AllowNegativeBalance, @Notes);
    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCashAccount_Update
    @GenericCashAccountId  INT,
    @FarmId                NVARCHAR(450),
    @AccountName           NVARCHAR(150),
    @AccountType           NVARCHAR(40),
    @AllowNegativeBalance  BIT,
    @IsActive              BIT,
    @Notes                 NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- Note: OpeningBalance and CurrentBalance are NOT updateable through this
    -- proc. Adjustments to CurrentBalance must go through the cash transactions
    -- module (later phase) so we always have an audit trail.
    UPDATE dbo.GenericCashAccounts
    SET    AccountName = @AccountName, AccountType = @AccountType,
           AllowNegativeBalance = @AllowNegativeBalance, IsActive = @IsActive,
           Notes = @Notes, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCashAccountId = @GenericCashAccountId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCashAccount_Delete
    @GenericCashAccountId  INT,
    @FarmId                NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    -- Soft delete (set IsActive=0). Hard delete is unsafe because later phases
    -- will reference this row from CashTransactions.
    UPDATE dbo.GenericCashAccounts
    SET    IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCashAccountId = @GenericCashAccountId AND FarmId = @FarmId;
END
GO

-- =============================================================================
-- GenericCustomerType / SupplierType / PaymentMethod - read-only for Phase 1
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericCustomerType_GetAll
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericCustomerTypeId, FarmId, Name, IsActive, CreatedAt, UpdatedAt
    FROM   dbo.GenericCustomerTypes
    WHERE  FarmId = @FarmId AND IsActive = 1
    ORDER  BY Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericSupplierType_GetAll
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericSupplierTypeId, FarmId, Name, IsActive, CreatedAt, UpdatedAt
    FROM   dbo.GenericSupplierTypes
    WHERE  FarmId = @FarmId AND IsActive = 1
    ORDER  BY Name;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericPaymentMethod_GetAll
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericPaymentMethodId, FarmId, Name, IsActive, CreatedAt, UpdatedAt
    FROM   dbo.GenericPaymentMethods
    WHERE  FarmId = @FarmId AND IsActive = 1
    ORDER  BY Name;
END
GO

PRINT '029_AddGenericCompanyStoredProcedures.sql complete.';
GO
