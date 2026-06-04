-- =============================================================================
-- Migration 076: WaterSuppliers (the Suppliers / "Paid To" master list)
-- =============================================================================
-- James (2026-05-30) — see "Three Prompts In one powerful please implement
-- all.txt" §1, §2, §4, §9. The Water module needs a Suppliers concept that:
--
--   * Is a setup tab AND a full standalone page (same data — one table).
--   * Drops into a reusable dropdown on Expenses ("Paid To"),
--     RawMaterialPurchases, and any other purchase/expense form.
--   * Carries enough metadata (type, contact, address) for a future
--     "Supplier Report" without a second migration.
--
-- Schema notes
--   * Soft-delete via IsDeleted (mirrors the rest of Water — see WaterExpenses,
--     WaterRawMaterialPurchases). Hard delete is intentionally NOT supported
--     because supplier rows are referenced by historical purchases/expenses.
--   * Filtered UX on (FarmId, SupplierName) WHERE IsDeleted = 0 — same trick
--     migration 075 used for WaterExpenses, so an old supplier can be soft-
--     deleted and re-created under the same name without index collision.
--   * SupplierType is a free string (validated app-side from the §1 list:
--     Raw Material, Packaging, Fuel, Machine Parts, Vehicle Repair,
--     Utility, Service, Other). Free text avoids a coupled lookup table for
--     what is essentially a label.
--
-- SPs
--   spWaterSupplier_Insert     — returns new identity
--   spWaterSupplier_Update     — partial update; nulls keep prior values
--   spWaterSupplier_Delete     — soft delete (IsDeleted = 1, IsActive = 0)
--   spWaterSupplier_GetById    — single row
--   spWaterSupplier_ListByFarm — list, optional @IncludeInactive bit (default 0)
--                                used both by the standalone page and by the
--                                dropdown component.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- -----------------------------------------------------------------------------
-- 1. Table
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.WaterSuppliers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.WaterSuppliers (
        WaterSupplierId   INT IDENTITY(1,1) PRIMARY KEY,
        FarmId            NVARCHAR(450)  NOT NULL,
        SupplierName      NVARCHAR(200)  NOT NULL,
        ContactPerson     NVARCHAR(200)  NULL,
        Phone             NVARCHAR(50)   NULL,
        Email             NVARCHAR(200)  NULL,
        Address           NVARCHAR(500)  NULL,
        SupplierType      NVARCHAR(60)   NULL,
        Notes             NVARCHAR(1000) NULL,
        IsActive          BIT            NOT NULL CONSTRAINT DF_WaterSuppliers_IsActive  DEFAULT (1),
        IsDeleted         BIT            NOT NULL CONSTRAINT DF_WaterSuppliers_IsDeleted DEFAULT (0),
        CreatedBy         NVARCHAR(450)  NULL,
        CreatedAt         DATETIME2      NOT NULL CONSTRAINT DF_WaterSuppliers_CreatedAt DEFAULT (SYSUTCDATETIME()),
        UpdatedBy         NVARCHAR(450)  NULL,
        UpdatedAt         DATETIME2      NULL
    );

    CREATE INDEX IX_WaterSuppliers_FarmId   ON dbo.WaterSuppliers (FarmId);
    CREATE INDEX IX_WaterSuppliers_Active   ON dbo.WaterSuppliers (FarmId, IsActive, IsDeleted);

    -- Active name must be unique per farm; soft-deleted rows free up the name.
    CREATE UNIQUE INDEX UX_WaterSuppliers_FarmName_Active
        ON dbo.WaterSuppliers (FarmId, SupplierName)
        WHERE IsDeleted = 0;
END
GO

-- -----------------------------------------------------------------------------
-- 2. SPs
-- -----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spWaterSupplier_Insert
    @FarmId        NVARCHAR(450),
    @SupplierName  NVARCHAR(200),
    @ContactPerson NVARCHAR(200) = NULL,
    @Phone         NVARCHAR(50)  = NULL,
    @Email         NVARCHAR(200) = NULL,
    @Address       NVARCHAR(500) = NULL,
    @SupplierType  NVARCHAR(60)  = NULL,
    @Notes         NVARCHAR(1000)= NULL,
    @CreatedBy     NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@SupplierName IS NULL OR LTRIM(RTRIM(@SupplierName)) = N'')
    BEGIN RAISERROR('SupplierName is required.', 16, 1); RETURN; END

    INSERT INTO dbo.WaterSuppliers (
        FarmId, SupplierName, ContactPerson, Phone, Email, Address,
        SupplierType, Notes, CreatedBy
    )
    VALUES (
        @FarmId, LTRIM(RTRIM(@SupplierName)), @ContactPerson, @Phone, @Email, @Address,
        @SupplierType, @Notes, @CreatedBy
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterSupplier_Update
    @WaterSupplierId INT,
    @FarmId          NVARCHAR(450),
    @SupplierName    NVARCHAR(200),
    @ContactPerson   NVARCHAR(200) = NULL,
    @Phone           NVARCHAR(50)  = NULL,
    @Email           NVARCHAR(200) = NULL,
    @Address         NVARCHAR(500) = NULL,
    @SupplierType    NVARCHAR(60)  = NULL,
    @Notes           NVARCHAR(1000)= NULL,
    @IsActive        BIT           = NULL,
    @UpdatedBy       NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF (@SupplierName IS NULL OR LTRIM(RTRIM(@SupplierName)) = N'')
    BEGIN RAISERROR('SupplierName is required.', 16, 1); RETURN; END

    UPDATE dbo.WaterSuppliers
    SET SupplierName  = LTRIM(RTRIM(@SupplierName)),
        ContactPerson = @ContactPerson,
        Phone         = @Phone,
        Email         = @Email,
        Address       = @Address,
        SupplierType  = @SupplierType,
        Notes         = @Notes,
        IsActive      = ISNULL(@IsActive, IsActive),
        UpdatedBy     = @UpdatedBy,
        UpdatedAt     = SYSUTCDATETIME()
    WHERE WaterSupplierId = @WaterSupplierId
      AND FarmId          = @FarmId
      AND IsDeleted       = 0;

    IF @@ROWCOUNT = 0
        RAISERROR('Supplier not found or already deleted.', 16, 1);
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterSupplier_Delete
    @WaterSupplierId INT,
    @FarmId          NVARCHAR(450),
    @DeletedBy       NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.WaterSuppliers
    SET IsDeleted = 1, IsActive = 0, UpdatedBy = @DeletedBy, UpdatedAt = SYSUTCDATETIME()
    WHERE WaterSupplierId = @WaterSupplierId AND FarmId = @FarmId AND IsDeleted = 0;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterSupplier_GetById
    @WaterSupplierId INT,
    @FarmId          NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT WaterSupplierId, FarmId, SupplierName, ContactPerson, Phone, Email,
           Address, SupplierType, Notes, IsActive, IsDeleted,
           CreatedBy, CreatedAt, UpdatedBy, UpdatedAt
    FROM   dbo.WaterSuppliers
    WHERE  WaterSupplierId = @WaterSupplierId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spWaterSupplier_ListByFarm
    @FarmId            NVARCHAR(450),
    @IncludeInactive   BIT = 0,
    @IncludeDeleted    BIT = 0,
    @Search            NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT WaterSupplierId, FarmId, SupplierName, ContactPerson, Phone, Email,
           Address, SupplierType, Notes, IsActive, IsDeleted,
           CreatedBy, CreatedAt, UpdatedBy, UpdatedAt
    FROM   dbo.WaterSuppliers
    WHERE  FarmId = @FarmId
      AND  (@IncludeDeleted  = 1 OR IsDeleted = 0)
      AND  (@IncludeInactive = 1 OR IsActive  = 1)
      AND  (@Search IS NULL OR @Search = N''
            OR SupplierName  LIKE N'%' + @Search + N'%'
            OR ContactPerson LIKE N'%' + @Search + N'%'
            OR Phone         LIKE N'%' + @Search + N'%'
            OR Email         LIKE N'%' + @Search + N'%')
    ORDER BY SupplierName;
END
GO

-- -----------------------------------------------------------------------------
-- 3. Grants (idempotent — same pattern as migrations 069/072/075)
-- -----------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'PoultryAppRole' AND type = N'R')
BEGIN
    GRANT EXECUTE ON dbo.spWaterSupplier_Insert     TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterSupplier_Update     TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterSupplier_Delete     TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterSupplier_GetById    TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spWaterSupplier_ListByFarm TO PoultryAppRole;
END
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'Techretainer')
BEGIN
    GRANT EXECUTE ON dbo.spWaterSupplier_Insert     TO Techretainer;
    GRANT EXECUTE ON dbo.spWaterSupplier_Update     TO Techretainer;
    GRANT EXECUTE ON dbo.spWaterSupplier_Delete     TO Techretainer;
    GRANT EXECUTE ON dbo.spWaterSupplier_GetById    TO Techretainer;
    GRANT EXECUTE ON dbo.spWaterSupplier_ListByFarm TO Techretainer;
END
GO

PRINT '076_AddWaterSuppliers.sql complete.';
GO
