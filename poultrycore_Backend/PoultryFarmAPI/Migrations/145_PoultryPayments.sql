-- =============================================================================
-- Migration 145: Poultry customer payments (partial payments against a sale)
-- =============================================================================
-- Ports the Water payment feature (migrations 025/026) to Poultry so a credit
-- sale can be paid off over time. Adds:
--   * dbo.Sale.AmountPaid  — running total of payments recorded against a sale.
--   * dbo.PoultryPayments  — one row per payment received.
--   * spPoultryPayment_Record / _GetBySale / _GetAll.
-- The record proc recomputes Sale.AmountPaid + Paid, then re-runs the existing
-- spPoultrySaleCash_Sync (mig 137) so the sale's cash-in posts once it is fully
-- paid (partial payments track receivables but move cash only when complete —
-- consistent with the existing "cash on paid" model).
-- The Sale read procs now also return AmountPaid so the UI can show "owed".
-- Fully idempotent (COL_LENGTH guard + CREATE OR ALTER).
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---- Sale.AmountPaid ---------------------------------------------------------
IF COL_LENGTH('dbo.Sale', 'AmountPaid') IS NULL
BEGIN
    ALTER TABLE dbo.Sale ADD AmountPaid DECIMAL(14,2) NOT NULL CONSTRAINT DF_Sale_AmountPaid DEFAULT (0);
    PRINT '145: added dbo.Sale.AmountPaid';
END
GO
-- Backfill: a fully paid sale is considered paid in full.
UPDATE dbo.Sale SET AmountPaid = TotalAmount WHERE ISNULL(Paid, 1) = 1 AND ISNULL(AmountPaid, 0) = 0;
GO

-- ---- PoultryPayments table ---------------------------------------------------
IF OBJECT_ID('dbo.PoultryPayments', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PoultryPayments (
        PoultryPaymentId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PoultryPayments PRIMARY KEY,
        FarmId           NVARCHAR(450) NOT NULL,
        SaleId           INT           NOT NULL,
        Amount           DECIMAL(14,2) NOT NULL,
        PaymentMethod    NVARCHAR(40)  NULL,
        PaymentDate      DATETIME2     NOT NULL CONSTRAINT DF_PoultryPayments_PaymentDate DEFAULT (SYSUTCDATETIME()),
        Reference        NVARCHAR(120) NULL,
        Note             NVARCHAR(300) NULL,
        CreatedDate      DATETIME2     NOT NULL CONSTRAINT DF_PoultryPayments_CreatedDate DEFAULT (SYSUTCDATETIME()),
        CreatedBy        NVARCHAR(450) NULL
    );
    CREATE INDEX IX_PoultryPayments_Farm_Sale ON dbo.PoultryPayments (FarmId, SaleId);
    PRINT '145: created dbo.PoultryPayments';
END
GO

-- ---- Sale read procs now expose AmountPaid ----------------------------------
CREATE OR ALTER PROCEDURE [dbo].[spSale_GetById]
    @SaleId INT,
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        SaleId, UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount,
        PaymentMethod, CustomerName, FlockId, SaleDescription, ISNULL(Paid, 1) AS Paid,
        Size, PoultryCashAccountId, ISNULL(AmountPaid, 0) AS AmountPaid,
        CreatedDate
    FROM [dbo].[Sale]
    WHERE SaleId = @SaleId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSale_GetAll]
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        SaleId, UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount,
        PaymentMethod, CustomerName, FlockId, SaleDescription, ISNULL(Paid, 1) AS Paid,
        Size, PoultryCashAccountId, ISNULL(AmountPaid, 0) AS AmountPaid,
        CreatedDate
    FROM [dbo].[Sale]
    WHERE FarmId = @FarmId
    ORDER BY SaleDate DESC, CreatedDate DESC;
END
GO

CREATE OR ALTER PROCEDURE [dbo].[spSale_GetByFlock]
    @FlockId INT,
    @FarmId NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        SaleId, UserId, FarmId, SaleDate, Product, Quantity, UnitPrice, TotalAmount,
        PaymentMethod, CustomerName, FlockId, SaleDescription, ISNULL(Paid, 1) AS Paid,
        Size, PoultryCashAccountId, ISNULL(AmountPaid, 0) AS AmountPaid,
        CreatedDate
    FROM [dbo].[Sale]
    WHERE FarmId = @FarmId AND FlockId = @FlockId
    ORDER BY SaleDate DESC, CreatedDate DESC;
END
GO

-- ---- spPoultryPayment_Record -------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryPayment_Record
    @FarmId        NVARCHAR(450),
    @SaleId        INT,
    @Amount        DECIMAL(14,2),
    @PaymentMethod NVARCHAR(40)  = NULL,
    @PaymentDate   DATETIME2     = NULL,
    @Reference     NVARCHAR(120) = NULL,
    @Note          NVARCHAR(300) = NULL,
    @CreatedBy     NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @PaymentDate IS NULL SET @PaymentDate = SYSUTCDATETIME();

    IF NOT EXISTS (SELECT 1 FROM dbo.Sale WHERE SaleId = @SaleId AND FarmId = @FarmId)
    BEGIN
        RAISERROR('Sale does not belong to this company.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    INSERT INTO dbo.PoultryPayments
        (FarmId, SaleId, Amount, PaymentMethod, PaymentDate, Reference, Note, CreatedBy)
    VALUES (@FarmId, @SaleId, @Amount, @PaymentMethod, @PaymentDate, @Reference, @Note, @CreatedBy);

    DECLARE @PaymentId INT = SCOPE_IDENTITY();

    -- Recompute the sale's running total + paid flag.
    DECLARE @Total DECIMAL(14,2), @AcctId INT, @NewPaid BIT;
    SELECT @Total = TotalAmount, @AcctId = PoultryCashAccountId FROM dbo.Sale WHERE SaleId = @SaleId AND FarmId = @FarmId;

    DECLARE @Sum DECIMAL(14,2) = ISNULL((SELECT SUM(Amount) FROM dbo.PoultryPayments WHERE SaleId = @SaleId AND FarmId = @FarmId), 0);
    SET @NewPaid = CASE WHEN @Sum >= @Total THEN 1 ELSE 0 END;

    UPDATE dbo.Sale SET AmountPaid = @Sum, Paid = @NewPaid WHERE SaleId = @SaleId AND FarmId = @FarmId;

    -- Keep the sale's cash-in in sync (posts the full amount once fully paid,
    -- reverses it if the sale is not yet fully paid). No-op if no account set.
    EXEC dbo.spPoultrySaleCash_Sync @FarmId, @SaleId, @AcctId, @Total, @NewPaid, N'Sale payment', @CreatedBy;

    COMMIT TRANSACTION;

    SELECT @PaymentId AS PoultryPaymentId;
END
GO

-- ---- spPoultryPayment_GetBySale ----------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryPayment_GetBySale
    @SaleId INT,
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PoultryPaymentId, FarmId, SaleId, Amount, PaymentMethod,
           PaymentDate, Reference, Note, CreatedDate, CreatedBy
    FROM dbo.PoultryPayments
    WHERE SaleId = @SaleId AND FarmId = @FarmId
    ORDER BY PaymentDate DESC;
END
GO

-- ---- spPoultryPayment_GetAll -------------------------------------------------
CREATE OR ALTER PROCEDURE dbo.spPoultryPayment_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.PoultryPaymentId, p.FarmId, p.SaleId, p.Amount, p.PaymentMethod,
           p.PaymentDate, p.Reference, p.Note, p.CreatedDate, p.CreatedBy,
           s.CustomerName AS CustomerName
    FROM dbo.PoultryPayments p
    INNER JOIN dbo.Sale s ON s.SaleId = p.SaleId
    WHERE p.FarmId = @FarmId
    ORDER BY p.PaymentDate DESC;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spPoultryPayment_Record   TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryPayment_GetBySale TO [Techretainer];
    GRANT EXECUTE ON dbo.spPoultryPayment_GetAll   TO [Techretainer];
    GRANT EXECUTE ON dbo.spSale_GetAll     TO [Techretainer];
    GRANT EXECUTE ON dbo.spSale_GetById    TO [Techretainer];
    GRANT EXECUTE ON dbo.spSale_GetByFlock TO [Techretainer];
    GRANT SELECT, INSERT ON dbo.PoultryPayments TO [Techretainer];
END
GO

PRINT '145_PoultryPayments: complete.';
GO
