-- =============================================
-- Cash Module: CashAdjustment table + stored procedures
-- Database: poultry2_Prod (or your target database)
-- =============================================
-- Cash adjustments: Opening Balance, Owner injection, Loan received,
-- Withdrawal, Correction. Sales and Expenses are in their own tables.
-- Cash at Hand = Sum(adjustments in) + Sales - Expenses - Sum(adjustments out)
-- =============================================

USE [poultry2_Prod];
GO

IF OBJECT_ID('dbo.CashAdjustment', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CashAdjustment
    (
        AdjustmentId INT IDENTITY(1,1) PRIMARY KEY,
        UserId NVARCHAR(450) NOT NULL,
        FarmId NVARCHAR(450) NOT NULL,
        AdjustmentDate DATETIME2 NOT NULL,
        AdjustmentType NVARCHAR(50) NOT NULL,  -- OpeningBalance, OwnerInjection, LoanReceived, Withdrawal, Correction
        Amount DECIMAL(18,2) NOT NULL,          -- positive = inflow, negative = outflow
        Description NVARCHAR(500) NULL,
        CreatedDate DATETIME2 NOT NULL CONSTRAINT DF_CashAdjustment_CreatedDate DEFAULT SYSUTCDATETIME()
    );
    CREATE INDEX IX_CashAdjustment_FarmId ON dbo.CashAdjustment(FarmId);
    CREATE INDEX IX_CashAdjustment_AdjustmentDate ON dbo.CashAdjustment(AdjustmentDate);
END
GO

-- spCashAdjustment_GetAll
IF OBJECT_ID('dbo.spCashAdjustment_GetAll', 'P') IS NOT NULL
    DROP PROCEDURE dbo.spCashAdjustment_GetAll;
GO
CREATE PROCEDURE dbo.spCashAdjustment_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        AdjustmentId,
        UserId,
        FarmId,
        AdjustmentDate,
        AdjustmentType,
        Amount,
        Description,
        CreatedDate
    FROM dbo.CashAdjustment
    WHERE FarmId = @FarmId
    ORDER BY AdjustmentDate ASC, AdjustmentId ASC;
END
GO

-- spCashAdjustment_GetById
IF OBJECT_ID('dbo.spCashAdjustment_GetById', 'P') IS NOT NULL
    DROP PROCEDURE dbo.spCashAdjustment_GetById;
GO
CREATE PROCEDURE dbo.spCashAdjustment_GetById
    @AdjustmentId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        AdjustmentId,
        UserId,
        FarmId,
        AdjustmentDate,
        AdjustmentType,
        Amount,
        Description,
        CreatedDate
    FROM dbo.CashAdjustment
    WHERE AdjustmentId = @AdjustmentId AND FarmId = @FarmId;
END
GO

-- spCashAdjustment_Insert
IF OBJECT_ID('dbo.spCashAdjustment_Insert', 'P') IS NOT NULL
    DROP PROCEDURE dbo.spCashAdjustment_Insert;
GO
CREATE PROCEDURE dbo.spCashAdjustment_Insert
    @UserId NVARCHAR(450),
    @FarmId NVARCHAR(450),
    @AdjustmentDate DATETIME2,
    @AdjustmentType NVARCHAR(50),
    @Amount DECIMAL(18,2),
    @Description NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.CashAdjustment
    (UserId, FarmId, AdjustmentDate, AdjustmentType, Amount, Description)
    VALUES
    (@UserId, @FarmId, @AdjustmentDate, @AdjustmentType, @Amount, @Description);

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
END
GO

-- spCashAdjustment_Update
IF OBJECT_ID('dbo.spCashAdjustment_Update', 'P') IS NOT NULL
    DROP PROCEDURE dbo.spCashAdjustment_Update;
GO
CREATE PROCEDURE dbo.spCashAdjustment_Update
    @AdjustmentId INT,
    @FarmId NVARCHAR(450),
    @AdjustmentDate DATETIME2,
    @AdjustmentType NVARCHAR(50),
    @Amount DECIMAL(18,2),
    @Description NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.CashAdjustment
    SET
        AdjustmentDate = @AdjustmentDate,
        AdjustmentType = @AdjustmentType,
        Amount = @Amount,
        Description = @Description
    WHERE AdjustmentId = @AdjustmentId AND FarmId = @FarmId;
END
GO

-- spCashAdjustment_Delete
IF OBJECT_ID('dbo.spCashAdjustment_Delete', 'P') IS NOT NULL
    DROP PROCEDURE dbo.spCashAdjustment_Delete;
GO
CREATE PROCEDURE dbo.spCashAdjustment_Delete
    @AdjustmentId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.CashAdjustment
    WHERE AdjustmentId = @AdjustmentId AND FarmId = @FarmId;
END
GO

PRINT 'Cash module (CashAdjustment table + procedures) created successfully.';
