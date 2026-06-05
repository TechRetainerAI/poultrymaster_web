-- =============================================================================
-- Migration 033: Stored procedures for Customers / Sales / Customer Payments
--                / Cash Transactions
-- =============================================================================
-- Run AFTER 032_AddGenericCustomersSalesCash.sql.
--
-- This is the transactional core of the Generic Company module. The big
-- procs (Sale_Approve, CustomerPayment_Approve) keep stock + cash + customer
-- balances in lockstep using XACT_ABORT-protected transactions.
--
-- Idempotency: every Approve proc is safe to re-run on an already-approved
-- row — it returns the current row without doing anything. This protects
-- against client retries on transient network errors.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- GenericCustomer
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericCustomer_GetAll
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericCustomerId, FarmId, CustomerName, CustomerType, PhoneNumber, Email,
           Location, Address, CreditLimit, PaymentTermsDays, OpeningBalance,
           CurrentBalance, AssignedStaffId, IsActive, IsDeleted, Notes,
           CreatedAt, UpdatedAt
    FROM   dbo.GenericCustomers
    WHERE  FarmId = @FarmId AND IsDeleted = 0
    ORDER  BY IsActive DESC, CustomerName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCustomer_GetById
    @GenericCustomerId INT,
    @FarmId            NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericCustomerId, FarmId, CustomerName, CustomerType, PhoneNumber, Email,
           Location, Address, CreditLimit, PaymentTermsDays, OpeningBalance,
           CurrentBalance, AssignedStaffId, IsActive, IsDeleted, Notes,
           CreatedAt, UpdatedAt
    FROM   dbo.GenericCustomers
    WHERE  GenericCustomerId = @GenericCustomerId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCustomer_Insert
    @FarmId           NVARCHAR(450),
    @CustomerName     NVARCHAR(200),
    @CustomerType     NVARCHAR(40)   = 'Individual',
    @PhoneNumber      NVARCHAR(50)   = NULL,
    @Email            NVARCHAR(150)  = NULL,
    @Location         NVARCHAR(255)  = NULL,
    @Address          NVARCHAR(500)  = NULL,
    @CreditLimit      DECIMAL(14,2)  = 0,
    @PaymentTermsDays INT            = 0,
    @OpeningBalance   DECIMAL(14,2)  = 0,
    @AssignedStaffId  INT            = NULL,
    @IsActive         BIT            = 1,
    @Notes            NVARCHAR(1000) = NULL,
    @CreatedBy        NVARCHAR(450)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    INSERT INTO dbo.GenericCustomers (
        FarmId, CustomerName, CustomerType, PhoneNumber, Email, Location, Address,
        CreditLimit, PaymentTermsDays, OpeningBalance, CurrentBalance,
        AssignedStaffId, IsActive, Notes
    )
    VALUES (
        @FarmId, @CustomerName, @CustomerType, @PhoneNumber, @Email, @Location, @Address,
        @CreditLimit, @PaymentTermsDays, @OpeningBalance, @OpeningBalance,
        @AssignedStaffId, @IsActive, @Notes
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    -- Seed ledger row when OpeningBalance is non-zero, so the ledger always
    -- explains the CurrentBalance.
    IF (@OpeningBalance <> 0)
    BEGIN
        INSERT INTO dbo.GenericCustomerLedger (
            FarmId, GenericCustomerId, TransactionDate, TransactionType,
            DebitAmount, CreditAmount, BalanceAfterTransaction, Description, CreatedBy
        )
        VALUES (
            @FarmId, @NewId, SYSUTCDATETIME(), 'OpeningBalance',
            CASE WHEN @OpeningBalance > 0 THEN  @OpeningBalance ELSE 0 END,
            CASE WHEN @OpeningBalance < 0 THEN -@OpeningBalance ELSE 0 END,
            @OpeningBalance, 'Opening balance', @CreatedBy
        );
    END

    COMMIT TRANSACTION;

    SELECT @NewId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCustomer_Update
    @GenericCustomerId INT,
    @FarmId            NVARCHAR(450),
    @CustomerName      NVARCHAR(200),
    @CustomerType      NVARCHAR(40),
    @PhoneNumber       NVARCHAR(50)   = NULL,
    @Email             NVARCHAR(150)  = NULL,
    @Location          NVARCHAR(255)  = NULL,
    @Address           NVARCHAR(500)  = NULL,
    @CreditLimit       DECIMAL(14,2),
    @PaymentTermsDays  INT,
    @AssignedStaffId   INT            = NULL,
    @IsActive          BIT,
    @Notes             NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    -- OpeningBalance/CurrentBalance are NOT updateable here. Balance changes
    -- only via the ledger.
    UPDATE dbo.GenericCustomers
    SET    CustomerName     = @CustomerName,
           CustomerType     = @CustomerType,
           PhoneNumber      = @PhoneNumber,
           Email            = @Email,
           Location         = @Location,
           Address          = @Address,
           CreditLimit      = @CreditLimit,
           PaymentTermsDays = @PaymentTermsDays,
           AssignedStaffId  = @AssignedStaffId,
           IsActive         = @IsActive,
           Notes            = @Notes,
           UpdatedAt        = SYSUTCDATETIME()
    WHERE  GenericCustomerId = @GenericCustomerId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCustomer_Delete
    @GenericCustomerId INT,
    @FarmId            NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericCustomers
    SET    IsDeleted = 1, IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCustomerId = @GenericCustomerId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCustomer_GetOwingMoney
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericCustomerId, FarmId, CustomerName, CustomerType, PhoneNumber,
           CreditLimit, CurrentBalance,
           CASE WHEN CreditLimit > 0 AND CurrentBalance > CreditLimit THEN 1 ELSE 0 END AS IsOverLimit
    FROM   dbo.GenericCustomers
    WHERE  FarmId = @FarmId AND IsDeleted = 0 AND CurrentBalance > 0
    ORDER  BY CurrentBalance DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCustomerLedger_GetForCustomer
    @GenericCustomerId INT,
    @FarmId            NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericCustomerLedgerId, FarmId, GenericCustomerId, TransactionDate,
           TransactionType, SaleId, PaymentId, DebitAmount, CreditAmount,
           BalanceAfterTransaction, Description, CreatedBy, CreatedAt
    FROM   dbo.GenericCustomerLedger
    WHERE  GenericCustomerId = @GenericCustomerId AND FarmId = @FarmId
    ORDER  BY TransactionDate, GenericCustomerLedgerId;
END
GO

-- =============================================================================
-- GenericCashTransaction (read-only here; writes happen via Sale_Approve /
-- CustomerPayment_Approve / Adjustment).
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericCashTransaction_GetByAccount
    @GenericCashAccountId INT,
    @FarmId               NVARCHAR(450),
    @FromDate             DATETIME2 = NULL,
    @ToDate               DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.GenericCashTransactionId, t.FarmId, t.GenericCashAccountId,
           a.AccountName,
           t.TransactionDate, t.TransactionType, t.SourceType, t.SourceId,
           t.Amount, t.BalanceAfterTransaction, t.Description,
           t.CreatedBy, t.ApprovedBy, t.ApprovedAt, t.CreatedAt
    FROM   dbo.GenericCashTransactions t
    INNER  JOIN dbo.GenericCashAccounts a ON a.GenericCashAccountId = t.GenericCashAccountId
    WHERE  t.GenericCashAccountId = @GenericCashAccountId
       AND t.FarmId = @FarmId
       AND (@FromDate IS NULL OR t.TransactionDate >= @FromDate)
       AND (@ToDate   IS NULL OR t.TransactionDate <= @ToDate)
    ORDER  BY t.TransactionDate DESC, t.GenericCashTransactionId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCashTransaction_GetByFarm
    @FarmId   NVARCHAR(450),
    @FromDate DATETIME2 = NULL,
    @ToDate   DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.GenericCashTransactionId, t.FarmId, t.GenericCashAccountId,
           a.AccountName,
           t.TransactionDate, t.TransactionType, t.SourceType, t.SourceId,
           t.Amount, t.BalanceAfterTransaction, t.Description,
           t.CreatedBy, t.ApprovedBy, t.ApprovedAt, t.CreatedAt
    FROM   dbo.GenericCashTransactions t
    INNER  JOIN dbo.GenericCashAccounts a ON a.GenericCashAccountId = t.GenericCashAccountId
    WHERE  t.FarmId = @FarmId
       AND (@FromDate IS NULL OR t.TransactionDate >= @FromDate)
       AND (@ToDate   IS NULL OR t.TransactionDate <= @ToDate)
    ORDER  BY t.TransactionDate DESC, t.GenericCashTransactionId DESC;
END
GO

-- Manual cash adjustment (single account, signed amount, requires reason).
-- Useful for opening-counts, found money, write-offs, etc.
CREATE OR ALTER PROCEDURE dbo.spGenericCashTransaction_InsertAdjustment
    @FarmId               NVARCHAR(450),
    @GenericCashAccountId INT,
    @Amount               DECIMAL(14,2),     -- signed: + cash in, - cash out
    @Reason               NVARCHAR(500),
    @TransactionDate      DATETIME2 = NULL,
    @CreatedBy            NVARCHAR(450) = NULL,
    @ApprovedBy           NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF (@Reason IS NULL OR LTRIM(RTRIM(@Reason)) = '')
    BEGIN
        RAISERROR('Reason is required for a cash adjustment.', 16, 1);
        RETURN;
    END
    IF (@Amount = 0)
    BEGIN
        RAISERROR('Amount must be non-zero.', 16, 1);
        RETURN;
    END

    DECLARE @AllowNeg BIT, @Current DECIMAL(14,2);
    SELECT @AllowNeg = AllowNegativeBalance, @Current = CurrentBalance
    FROM   dbo.GenericCashAccounts
    WHERE  GenericCashAccountId = @GenericCashAccountId AND FarmId = @FarmId;

    IF @Current IS NULL
    BEGIN
        RAISERROR('Cash account not found.', 16, 1);
        RETURN;
    END

    DECLARE @NewBalance DECIMAL(14,2) = @Current + @Amount;
    IF (@NewBalance < 0 AND @AllowNeg = 0)
    BEGIN
        RAISERROR('Cash adjustment would push balance negative; account does not allow it.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    INSERT INTO dbo.GenericCashTransactions (
        FarmId, GenericCashAccountId, TransactionDate, TransactionType,
        SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
        CreatedBy, ApprovedBy, ApprovedAt
    )
    VALUES (
        @FarmId, @GenericCashAccountId, ISNULL(@TransactionDate, SYSUTCDATETIME()),
        'Adjustment', 'Adjustment', NULL, @Amount, @NewBalance, @Reason,
        @CreatedBy, @ApprovedBy, SYSUTCDATETIME()
    );

    UPDATE dbo.GenericCashAccounts
    SET    CurrentBalance = @NewBalance, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCashAccountId = @GenericCashAccountId AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT CAST(SCOPE_IDENTITY() AS BIGINT) AS GenericCashTransactionId, @NewBalance AS NewBalance;
END
GO

-- =============================================================================
-- GenericCustomerPayment
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericCustomerPayment_GetAll
    @FarmId  NVARCHAR(450),
    @Status  NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.GenericCustomerPaymentId, p.FarmId, p.GenericCustomerId,
           c.CustomerName, p.PaymentDate, p.Amount, p.PaymentMethod,
           p.GenericCashAccountId, p.ReceivedByStaffId, p.LinkedSaleId,
           p.Status, p.Notes, p.CreatedBy, p.ApprovedBy, p.ApprovedAt,
           p.CreatedAt, p.UpdatedAt
    FROM   dbo.GenericCustomerPayments p
    INNER  JOIN dbo.GenericCustomers c ON c.GenericCustomerId = p.GenericCustomerId
    WHERE  p.FarmId = @FarmId
       AND (@Status IS NULL OR p.Status = @Status)
    ORDER  BY p.PaymentDate DESC, p.GenericCustomerPaymentId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCustomerPayment_GetById
    @GenericCustomerPaymentId INT,
    @FarmId                   NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.GenericCustomerPaymentId, p.FarmId, p.GenericCustomerId,
           c.CustomerName, p.PaymentDate, p.Amount, p.PaymentMethod,
           p.GenericCashAccountId, p.ReceivedByStaffId, p.LinkedSaleId,
           p.Status, p.Notes, p.CreatedBy, p.ApprovedBy, p.ApprovedAt,
           p.CreatedAt, p.UpdatedAt
    FROM   dbo.GenericCustomerPayments p
    INNER  JOIN dbo.GenericCustomers c ON c.GenericCustomerId = p.GenericCustomerId
    WHERE  p.GenericCustomerPaymentId = @GenericCustomerPaymentId AND p.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCustomerPayment_Insert
    @FarmId                NVARCHAR(450),
    @GenericCustomerId     INT,
    @Amount                DECIMAL(14,2),
    @PaymentMethod         NVARCHAR(40),
    @GenericCashAccountId  INT            = NULL,
    @ReceivedByStaffId     INT            = NULL,
    @LinkedSaleId          INT            = NULL,
    @PaymentDate           DATETIME2      = NULL,
    @Notes                 NVARCHAR(1000) = NULL,
    @CreatedBy             NVARCHAR(450)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF (@Amount <= 0)
    BEGIN
        RAISERROR('Payment amount must be greater than zero.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.GenericCustomerPayments (
        FarmId, GenericCustomerId, PaymentDate, Amount, PaymentMethod,
        GenericCashAccountId, ReceivedByStaffId, LinkedSaleId, Status,
        Notes, CreatedBy
    )
    VALUES (
        @FarmId, @GenericCustomerId, ISNULL(@PaymentDate, SYSUTCDATETIME()),
        @Amount, @PaymentMethod, @GenericCashAccountId, @ReceivedByStaffId,
        @LinkedSaleId, 'Draft', @Notes, @CreatedBy
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

-- Atomic approval: ledger PaymentCredit + customer balance update + cash CashIn.
CREATE OR ALTER PROCEDURE dbo.spGenericCustomerPayment_Approve
    @GenericCustomerPaymentId INT,
    @FarmId                   NVARCHAR(450),
    @ApprovedBy               NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Idempotent
    IF EXISTS (SELECT 1 FROM dbo.GenericCustomerPayments
               WHERE  GenericCustomerPaymentId = @GenericCustomerPaymentId
                 AND  FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT GenericCustomerPaymentId, Status, ApprovedBy, ApprovedAt
        FROM   dbo.GenericCustomerPayments
        WHERE  GenericCustomerPaymentId = @GenericCustomerPaymentId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @CustomerId INT, @Amount DECIMAL(14,2), @CashAccountId INT,
            @Status NVARCHAR(20), @PaymentDate DATETIME2, @Notes NVARCHAR(1000);

    SELECT @CustomerId    = GenericCustomerId,
           @Amount        = Amount,
           @CashAccountId = GenericCashAccountId,
           @Status        = Status,
           @PaymentDate   = PaymentDate,
           @Notes         = Notes
    FROM   dbo.GenericCustomerPayments
    WHERE  GenericCustomerPaymentId = @GenericCustomerPaymentId AND FarmId = @FarmId;

    IF @CustomerId IS NULL
    BEGIN
        RAISERROR('Customer payment %d not found.', 16, 1, @GenericCustomerPaymentId);
        RETURN;
    END
    IF @Status NOT IN ('Draft')
    BEGIN
        RAISERROR('Customer payment cannot be approved from status %s.', 16, 1, @Status);
        RETURN;
    END

    DECLARE @CashAllowNeg BIT, @CashCurrent DECIMAL(14,2), @CashNewBalance DECIMAL(14,2);
    IF @CashAccountId IS NOT NULL
    BEGIN
        SELECT @CashAllowNeg = AllowNegativeBalance, @CashCurrent = CurrentBalance
        FROM   dbo.GenericCashAccounts
        WHERE  GenericCashAccountId = @CashAccountId AND FarmId = @FarmId;

        IF @CashCurrent IS NULL
        BEGIN
            RAISERROR('Cash account on the payment does not exist or belongs to another farm.', 16, 1);
            RETURN;
        END

        SET @CashNewBalance = @CashCurrent + @Amount;   -- CashIn always increases
    END

    DECLARE @CustomerBalance DECIMAL(14,2);
    SELECT @CustomerBalance = CurrentBalance
    FROM   dbo.GenericCustomers WHERE GenericCustomerId = @CustomerId AND FarmId = @FarmId;
    IF @CustomerBalance IS NULL
    BEGIN
        RAISERROR('Customer on the payment does not exist or belongs to another farm.', 16, 1);
        RETURN;
    END
    DECLARE @CustomerNewBalance DECIMAL(14,2) = @CustomerBalance - @Amount;

    BEGIN TRANSACTION;

    -- Mark approved
    UPDATE dbo.GenericCustomerPayments
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCustomerPaymentId = @GenericCustomerPaymentId AND FarmId = @FarmId;

    -- Ledger row (PaymentCredit)
    INSERT INTO dbo.GenericCustomerLedger (
        FarmId, GenericCustomerId, TransactionDate, TransactionType,
        PaymentId, DebitAmount, CreditAmount, BalanceAfterTransaction,
        Description, CreatedBy
    )
    VALUES (
        @FarmId, @CustomerId, @PaymentDate, 'PaymentCredit',
        @GenericCustomerPaymentId, 0, @Amount, @CustomerNewBalance,
        ISNULL(@Notes, 'Customer payment'), @ApprovedBy
    );

    -- Customer balance
    UPDATE dbo.GenericCustomers
    SET    CurrentBalance = @CustomerNewBalance, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCustomerId = @CustomerId AND FarmId = @FarmId;

    -- Cash side (only if a cash account was provided)
    IF @CashAccountId IS NOT NULL
    BEGIN
        INSERT INTO dbo.GenericCashTransactions (
            FarmId, GenericCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
            CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @CashAccountId, @PaymentDate, 'CashIn',
            'CustomerPayment', @GenericCustomerPaymentId, @Amount, @CashNewBalance,
            ISNULL(@Notes, 'Customer payment'),
            @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
        );

        UPDATE dbo.GenericCashAccounts
        SET    CurrentBalance = @CashNewBalance, UpdatedAt = SYSUTCDATETIME()
        WHERE  GenericCashAccountId = @CashAccountId AND FarmId = @FarmId;
    END

    COMMIT TRANSACTION;

    SELECT GenericCustomerPaymentId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.GenericCustomerPayments
    WHERE  GenericCustomerPaymentId = @GenericCustomerPaymentId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCustomerPayment_Cancel
    @GenericCustomerPaymentId INT,
    @FarmId                   NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericCustomerPayments
    SET    Status = 'Cancelled', UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCustomerPaymentId = @GenericCustomerPaymentId
       AND FarmId = @FarmId
       AND Status = 'Draft';

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Payment cannot be cancelled (not found or already finalized).', 16, 1);
        RETURN;
    END
END
GO

-- =============================================================================
-- GenericSale + GenericSaleItem
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericSale_GetAll
    @FarmId  NVARCHAR(450),
    @Status  NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT s.GenericSaleId, s.FarmId, s.SaleDate, s.GenericCustomerId,
           c.CustomerName, s.BranchId, s.SalesType, s.SalesChannel,
           s.SalespersonStaffId, s.SubtotalAmount, s.DiscountAmount,
           s.TaxAmount, s.TotalAmount, s.AmountPaid, s.Balance,
           s.PaymentStatus, s.PaymentMethod, s.GenericCashAccountId,
           s.ReceiptNumber, s.Status, s.Notes,
           s.CreatedBy, s.ApprovedBy, s.ApprovedAt,
           s.CancelledBy, s.CancelledAt, s.CancellationReason,
           s.CreatedAt, s.UpdatedAt
    FROM   dbo.GenericSales s
    LEFT   JOIN dbo.GenericCustomers c ON c.GenericCustomerId = s.GenericCustomerId
    WHERE  s.FarmId = @FarmId AND s.IsDeleted = 0
       AND (@Status IS NULL OR s.Status = @Status)
    ORDER  BY s.SaleDate DESC, s.GenericSaleId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericSale_GetById
    @GenericSaleId INT,
    @FarmId        NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    -- Result set 1: header
    SELECT s.GenericSaleId, s.FarmId, s.SaleDate, s.GenericCustomerId,
           c.CustomerName, s.BranchId, s.SalesType, s.SalesChannel,
           s.SalespersonStaffId, s.SubtotalAmount, s.DiscountAmount,
           s.TaxAmount, s.TotalAmount, s.AmountPaid, s.Balance,
           s.PaymentStatus, s.PaymentMethod, s.GenericCashAccountId,
           s.ReceiptNumber, s.Status, s.Notes,
           s.CreatedBy, s.ApprovedBy, s.ApprovedAt,
           s.CancelledBy, s.CancelledAt, s.CancellationReason,
           s.CreatedAt, s.UpdatedAt
    FROM   dbo.GenericSales s
    LEFT   JOIN dbo.GenericCustomers c ON c.GenericCustomerId = s.GenericCustomerId
    WHERE  s.GenericSaleId = @GenericSaleId AND s.FarmId = @FarmId;

    -- Result set 2: items
    SELECT GenericSaleItemId, GenericSaleId, FarmId, ItemType,
           GenericProductId, GenericServiceId, Description,
           Quantity, UnitPrice, DiscountAmount, LineTotal,
           CostAmount, Notes
    FROM   dbo.GenericSaleItems
    WHERE  GenericSaleId = @GenericSaleId AND FarmId = @FarmId
    ORDER  BY GenericSaleItemId;
END
GO

-- Insert a Draft sale with its items in one call. Totals are recomputed from
-- the items + header-level discount/tax inside the SP so the client cannot
-- fudge them.
CREATE OR ALTER PROCEDURE dbo.spGenericSale_Insert
    @FarmId               NVARCHAR(450),
    @SaleDate             DATETIME2      = NULL,
    @GenericCustomerId    INT            = NULL,
    @BranchId             INT            = NULL,
    @SalesType            NVARCHAR(30)   = 'WalkInSale',
    @SalesChannel         NVARCHAR(30)   = NULL,
    @SalespersonStaffId   INT            = NULL,
    @HeaderDiscountAmount DECIMAL(14,2)  = 0,
    @TaxAmount            DECIMAL(14,2)  = 0,
    @AmountPaid           DECIMAL(14,2)  = 0,
    @PaymentMethod        NVARCHAR(20)   = NULL,
    @GenericCashAccountId INT            = NULL,
    @ReceiptNumber        NVARCHAR(60)   = NULL,
    @Notes                NVARCHAR(1000) = NULL,
    @CreatedBy            NVARCHAR(450)  = NULL,
    @Items                dbo.GenericSaleItemTvp READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Validate items
    IF NOT EXISTS (SELECT 1 FROM @Items)
    BEGIN
        RAISERROR('Sale must have at least one item.', 16, 1);
        RETURN;
    END
    IF EXISTS (SELECT 1 FROM @Items WHERE Quantity <= 0)
    BEGIN
        RAISERROR('Item quantity must be greater than zero.', 16, 1);
        RETURN;
    END
    IF EXISTS (SELECT 1 FROM @Items WHERE UnitPrice < 0)
    BEGIN
        RAISERROR('Item unit price cannot be negative.', 16, 1);
        RETURN;
    END
    IF EXISTS (SELECT 1 FROM @Items WHERE ItemType NOT IN ('Product', 'Service'))
    BEGIN
        RAISERROR('Item type must be Product or Service.', 16, 1);
        RETURN;
    END
    IF EXISTS (
        SELECT 1 FROM @Items
        WHERE (ItemType = 'Product' AND GenericProductId IS NULL)
           OR (ItemType = 'Service' AND GenericServiceId IS NULL))
    BEGIN
        RAISERROR('Product items need GenericProductId; service items need GenericServiceId.', 16, 1);
        RETURN;
    END

    -- Compute totals from items + header
    DECLARE @Subtotal DECIMAL(14,2) = (
        SELECT ISNULL(SUM(Quantity * UnitPrice - DiscountAmount), 0) FROM @Items
    );
    DECLARE @Total   DECIMAL(14,2) = @Subtotal - ISNULL(@HeaderDiscountAmount, 0) + ISNULL(@TaxAmount, 0);
    DECLARE @Balance DECIMAL(14,2) = @Total - ISNULL(@AmountPaid, 0);
    DECLARE @PayStatus NVARCHAR(20) =
        CASE
            WHEN ISNULL(@AmountPaid, 0) = 0      THEN 'Unpaid'
            WHEN @AmountPaid >= @Total           THEN 'Paid'
            ELSE 'Partial'
        END;

    BEGIN TRANSACTION;

    INSERT INTO dbo.GenericSales (
        FarmId, SaleDate, GenericCustomerId, BranchId, SalesType, SalesChannel,
        SalespersonStaffId, SubtotalAmount, DiscountAmount, TaxAmount,
        TotalAmount, AmountPaid, Balance, PaymentStatus, PaymentMethod,
        GenericCashAccountId, ReceiptNumber, Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, ISNULL(@SaleDate, SYSUTCDATETIME()), @GenericCustomerId, @BranchId,
        @SalesType, @SalesChannel, @SalespersonStaffId,
        @Subtotal, ISNULL(@HeaderDiscountAmount, 0), ISNULL(@TaxAmount, 0),
        @Total, ISNULL(@AmountPaid, 0), @Balance, @PayStatus, @PaymentMethod,
        @GenericCashAccountId, @ReceiptNumber, 'Draft', @Notes, @CreatedBy
    );

    DECLARE @NewSaleId INT = CAST(SCOPE_IDENTITY() AS INT);

    INSERT INTO dbo.GenericSaleItems (
        GenericSaleId, FarmId, ItemType, GenericProductId, GenericServiceId,
        Description, Quantity, UnitPrice, DiscountAmount, CostAmount, Notes
    )
    SELECT @NewSaleId, @FarmId, ItemType, GenericProductId, GenericServiceId,
           Description, Quantity, UnitPrice, ISNULL(DiscountAmount, 0), CostAmount, Notes
    FROM   @Items;

    COMMIT TRANSACTION;

    SELECT @NewSaleId;
END
GO

-- THE BIG ONE: atomic approve.
-- Reduces inventory + writes StockMovement SaleOut per product line where
-- TrackInventory=1, writes CashTransaction CashIn for AmountPaid, writes
-- CustomerLedger SaleDebit + bumps Customer.CurrentBalance if Balance > 0
-- and CustomerId is set.
CREATE OR ALTER PROCEDURE dbo.spGenericSale_Approve
    @GenericSaleId INT,
    @FarmId        NVARCHAR(450),
    @ApprovedBy    NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Idempotent
    IF EXISTS (SELECT 1 FROM dbo.GenericSales
               WHERE  GenericSaleId = @GenericSaleId AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT GenericSaleId, Status, ApprovedBy, ApprovedAt
        FROM   dbo.GenericSales
        WHERE  GenericSaleId = @GenericSaleId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @Status NVARCHAR(20), @CustomerId INT, @CashAccountId INT,
            @AmountPaid DECIMAL(14,2), @Balance DECIMAL(14,2),
            @SaleDate DATETIME2, @ReceiptNumber NVARCHAR(60);

    SELECT @Status        = Status,
           @CustomerId    = GenericCustomerId,
           @CashAccountId = GenericCashAccountId,
           @AmountPaid    = AmountPaid,
           @Balance       = Balance,
           @SaleDate      = SaleDate,
           @ReceiptNumber = ReceiptNumber
    FROM   dbo.GenericSales
    WHERE  GenericSaleId = @GenericSaleId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL
    BEGIN
        RAISERROR('Sale %d not found.', 16, 1, @GenericSaleId);
        RETURN;
    END
    IF @Status <> 'Draft'
    BEGIN
        RAISERROR('Sale cannot be approved from status %s.', 16, 1, @Status);
        RETURN;
    END
    IF (@AmountPaid > 0 AND @CashAccountId IS NULL)
    BEGIN
        RAISERROR('AmountPaid is greater than zero but no GenericCashAccountId is set.', 16, 1);
        RETURN;
    END
    IF (@Balance > 0 AND @CustomerId IS NULL)
    BEGIN
        RAISERROR('Sale has an unpaid balance but no customer is attached (credit sales require a customer).', 16, 1);
        RETURN;
    END

    -- Pre-flight: stock check (only for products with TrackInventory=1).
    IF EXISTS (
        SELECT 1
        FROM   dbo.GenericSaleItems i
        INNER  JOIN dbo.GenericProducts p ON p.GenericProductId = i.GenericProductId AND p.FarmId = @FarmId
        WHERE  i.GenericSaleId = @GenericSaleId
           AND i.ItemType = 'Product'
           AND p.TrackInventory = 1
           AND p.CurrentStock - i.Quantity < 0
    )
    BEGIN
        RAISERROR('Insufficient stock for one or more products on this sale.', 16, 1);
        RETURN;
    END

    -- Cash pre-flight if account does not allow negative.
    DECLARE @CashNewBalance DECIMAL(14,2) = NULL;
    IF (@AmountPaid > 0)
    BEGIN
        DECLARE @CashAllowNeg BIT, @CashCurrent DECIMAL(14,2);
        SELECT @CashAllowNeg = AllowNegativeBalance, @CashCurrent = CurrentBalance
        FROM   dbo.GenericCashAccounts
        WHERE  GenericCashAccountId = @CashAccountId AND FarmId = @FarmId;

        IF @CashCurrent IS NULL
        BEGIN
            RAISERROR('Cash account on the sale does not exist or belongs to another farm.', 16, 1);
            RETURN;
        END
        SET @CashNewBalance = @CashCurrent + @AmountPaid;   -- CashIn always increases
    END

    BEGIN TRANSACTION;

    -- 1. Mark sale approved
    UPDATE dbo.GenericSales
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericSaleId = @GenericSaleId AND FarmId = @FarmId;

    -- 2. Inventory: write SaleOut movements + decrement Product.CurrentStock.
    --    Service items and products with TrackInventory=0 are skipped.
    INSERT INTO dbo.GenericStockMovements (
        FarmId, GenericProductId, MovementDate, MovementType, Quantity,
        UnitCost, UnitSellingPrice, TotalCostValue, ReferenceType, ReferenceId,
        Reason, CreatedBy, ApprovedBy, ApprovedAt
    )
    SELECT @FarmId, i.GenericProductId, @SaleDate, 'SaleOut', -i.Quantity,
           p.CostPrice, i.UnitPrice, p.CostPrice * i.Quantity, 'Sale', @GenericSaleId,
           CONCAT('Sale ', ISNULL(@ReceiptNumber, CAST(@GenericSaleId AS NVARCHAR(20)))),
           @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
    FROM   dbo.GenericSaleItems i
    INNER  JOIN dbo.GenericProducts p
        ON p.GenericProductId = i.GenericProductId AND p.FarmId = @FarmId
    WHERE  i.GenericSaleId = @GenericSaleId
       AND i.ItemType = 'Product'
       AND p.TrackInventory = 1;

    UPDATE p
    SET    p.CurrentStock = p.CurrentStock - i.Quantity,
           p.UpdatedAt    = SYSUTCDATETIME()
    FROM   dbo.GenericProducts p
    INNER  JOIN dbo.GenericSaleItems i
        ON i.GenericProductId = p.GenericProductId AND i.FarmId = p.FarmId
    WHERE  i.GenericSaleId = @GenericSaleId
       AND i.ItemType = 'Product'
       AND p.TrackInventory = 1
       AND p.FarmId = @FarmId;

    -- 3. Cash side: CashTransaction CashIn + bump cash account balance.
    IF (@AmountPaid > 0)
    BEGIN
        INSERT INTO dbo.GenericCashTransactions (
            FarmId, GenericCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
            CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @CashAccountId, @SaleDate, 'CashIn',
            'Sale', @GenericSaleId, @AmountPaid, @CashNewBalance,
            CONCAT('Sale ', ISNULL(@ReceiptNumber, CAST(@GenericSaleId AS NVARCHAR(20)))),
            @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
        );

        UPDATE dbo.GenericCashAccounts
        SET    CurrentBalance = @CashNewBalance, UpdatedAt = SYSUTCDATETIME()
        WHERE  GenericCashAccountId = @CashAccountId AND FarmId = @FarmId;
    END

    -- 4. Customer side: SaleDebit ledger + bump customer balance (if any unpaid balance).
    IF (@Balance > 0 AND @CustomerId IS NOT NULL)
    BEGIN
        DECLARE @CustomerNewBalance DECIMAL(14,2);
        SELECT @CustomerNewBalance = CurrentBalance + @Balance
        FROM   dbo.GenericCustomers
        WHERE  GenericCustomerId = @CustomerId AND FarmId = @FarmId;

        INSERT INTO dbo.GenericCustomerLedger (
            FarmId, GenericCustomerId, TransactionDate, TransactionType,
            SaleId, DebitAmount, CreditAmount, BalanceAfterTransaction,
            Description, CreatedBy
        )
        VALUES (
            @FarmId, @CustomerId, @SaleDate, 'SaleDebit',
            @GenericSaleId, @Balance, 0, @CustomerNewBalance,
            CONCAT('Credit on sale ', ISNULL(@ReceiptNumber, CAST(@GenericSaleId AS NVARCHAR(20)))),
            @ApprovedBy
        );

        UPDATE dbo.GenericCustomers
        SET    CurrentBalance = @CustomerNewBalance, UpdatedAt = SYSUTCDATETIME()
        WHERE  GenericCustomerId = @CustomerId AND FarmId = @FarmId;
    END

    COMMIT TRANSACTION;

    SELECT GenericSaleId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.GenericSales
    WHERE  GenericSaleId = @GenericSaleId AND FarmId = @FarmId;
END
GO

-- Cancel: only valid on Draft sales. Approved sales must be Refunded.
CREATE OR ALTER PROCEDURE dbo.spGenericSale_Cancel
    @GenericSaleId  INT,
    @FarmId         NVARCHAR(450),
    @CancelledBy    NVARCHAR(450) = NULL,
    @Reason         NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericSales
    SET    Status = 'Cancelled',
           CancelledBy = @CancelledBy,
           CancelledAt = SYSUTCDATETIME(),
           CancellationReason = @Reason,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericSaleId = @GenericSaleId AND FarmId = @FarmId AND Status = 'Draft';

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Sale cannot be cancelled (not found or not in Draft).', 16, 1);
        RETURN;
    END
END
GO

-- Refund: reverses an Approved sale across all three sides.
--   * Stock: insert ReturnIn movements (positive Qty) + bump Product.CurrentStock back up.
--   * Cash:  insert CashOut transaction for AmountPaid + decrement CashAccount.CurrentBalance.
--   * Customer: insert RefundDebit-credit reversal entry (CreditAmount = unpaid balance)
--               and reduce Customer.CurrentBalance.
-- Mark sale Status='Refunded', PaymentStatus='Refunded'.
CREATE OR ALTER PROCEDURE dbo.spGenericSale_Refund
    @GenericSaleId  INT,
    @FarmId         NVARCHAR(450),
    @RefundedBy     NVARCHAR(450) = NULL,
    @Reason         NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @CustomerId INT, @CashAccountId INT,
            @AmountPaid DECIMAL(14,2), @Balance DECIMAL(14,2),
            @SaleDate DATETIME2, @ReceiptNumber NVARCHAR(60);

    SELECT @Status        = Status,
           @CustomerId    = GenericCustomerId,
           @CashAccountId = GenericCashAccountId,
           @AmountPaid    = AmountPaid,
           @Balance       = Balance,
           @SaleDate      = SaleDate,
           @ReceiptNumber = ReceiptNumber
    FROM   dbo.GenericSales
    WHERE  GenericSaleId = @GenericSaleId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL
    BEGIN
        RAISERROR('Sale %d not found.', 16, 1, @GenericSaleId);
        RETURN;
    END
    IF @Status <> 'Approved'
    BEGIN
        RAISERROR('Only Approved sales can be refunded (status was %s).', 16, 1, @Status);
        RETURN;
    END

    -- Cash pre-flight if account does not allow negative.
    DECLARE @CashNewBalance DECIMAL(14,2) = NULL;
    IF (@AmountPaid > 0)
    BEGIN
        DECLARE @CashAllowNeg BIT, @CashCurrent DECIMAL(14,2);
        SELECT @CashAllowNeg = AllowNegativeBalance, @CashCurrent = CurrentBalance
        FROM   dbo.GenericCashAccounts
        WHERE  GenericCashAccountId = @CashAccountId AND FarmId = @FarmId;

        IF @CashCurrent IS NULL
        BEGIN
            RAISERROR('Cash account on the sale no longer exists.', 16, 1);
            RETURN;
        END
        SET @CashNewBalance = @CashCurrent - @AmountPaid;
        IF (@CashNewBalance < 0 AND @CashAllowNeg = 0)
        BEGIN
            RAISERROR('Refund would push cash account negative; account does not allow it.', 16, 1);
            RETURN;
        END
    END

    DECLARE @RefundDesc NVARCHAR(500) =
        CONCAT('Refund on sale ', ISNULL(@ReceiptNumber, CAST(@GenericSaleId AS NVARCHAR(20))),
               CASE WHEN @Reason IS NULL THEN '' ELSE ' - ' + @Reason END);

    BEGIN TRANSACTION;

    -- 1. Mark sale refunded
    UPDATE dbo.GenericSales
    SET    Status = 'Refunded', PaymentStatus = 'Refunded',
           UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericSaleId = @GenericSaleId AND FarmId = @FarmId;

    -- 2. Inventory back IN
    INSERT INTO dbo.GenericStockMovements (
        FarmId, GenericProductId, MovementDate, MovementType, Quantity,
        UnitCost, UnitSellingPrice, TotalCostValue, ReferenceType, ReferenceId,
        Reason, CreatedBy, ApprovedBy, ApprovedAt
    )
    SELECT @FarmId, i.GenericProductId, SYSUTCDATETIME(), 'ReturnIn', i.Quantity,
           p.CostPrice, i.UnitPrice, p.CostPrice * i.Quantity, 'Sale', @GenericSaleId,
           @RefundDesc, @RefundedBy, @RefundedBy, SYSUTCDATETIME()
    FROM   dbo.GenericSaleItems i
    INNER  JOIN dbo.GenericProducts p
        ON p.GenericProductId = i.GenericProductId AND p.FarmId = @FarmId
    WHERE  i.GenericSaleId = @GenericSaleId
       AND i.ItemType = 'Product'
       AND p.TrackInventory = 1;

    UPDATE p
    SET    p.CurrentStock = p.CurrentStock + i.Quantity,
           p.UpdatedAt    = SYSUTCDATETIME()
    FROM   dbo.GenericProducts p
    INNER  JOIN dbo.GenericSaleItems i
        ON i.GenericProductId = p.GenericProductId AND i.FarmId = p.FarmId
    WHERE  i.GenericSaleId = @GenericSaleId
       AND i.ItemType = 'Product'
       AND p.TrackInventory = 1
       AND p.FarmId = @FarmId;

    -- 3. Cash OUT for AmountPaid
    IF (@AmountPaid > 0)
    BEGIN
        INSERT INTO dbo.GenericCashTransactions (
            FarmId, GenericCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
            CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @CashAccountId, SYSUTCDATETIME(), 'CashOut',
            'Refund', @GenericSaleId, -@AmountPaid, @CashNewBalance,
            @RefundDesc, @RefundedBy, @RefundedBy, SYSUTCDATETIME()
        );

        UPDATE dbo.GenericCashAccounts
        SET    CurrentBalance = @CashNewBalance, UpdatedAt = SYSUTCDATETIME()
        WHERE  GenericCashAccountId = @CashAccountId AND FarmId = @FarmId;
    END

    -- 4. Customer reversal for the credit portion
    IF (@Balance > 0 AND @CustomerId IS NOT NULL)
    BEGIN
        DECLARE @CustomerNewBalance DECIMAL(14,2);
        SELECT @CustomerNewBalance = CurrentBalance - @Balance
        FROM   dbo.GenericCustomers
        WHERE  GenericCustomerId = @CustomerId AND FarmId = @FarmId;

        INSERT INTO dbo.GenericCustomerLedger (
            FarmId, GenericCustomerId, TransactionDate, TransactionType,
            SaleId, DebitAmount, CreditAmount, BalanceAfterTransaction,
            Description, CreatedBy
        )
        VALUES (
            @FarmId, @CustomerId, SYSUTCDATETIME(), 'RefundDebit',
            @GenericSaleId, 0, @Balance, @CustomerNewBalance,
            @RefundDesc, @RefundedBy
        );

        UPDATE dbo.GenericCustomers
        SET    CurrentBalance = @CustomerNewBalance, UpdatedAt = SYSUTCDATETIME()
        WHERE  GenericCustomerId = @CustomerId AND FarmId = @FarmId;
    END

    COMMIT TRANSACTION;

    SELECT GenericSaleId, Status, PaymentStatus
    FROM   dbo.GenericSales
    WHERE  GenericSaleId = @GenericSaleId AND FarmId = @FarmId;
END
GO

PRINT '033_AddGenericSalesStoredProcedures.sql complete.';
GO
