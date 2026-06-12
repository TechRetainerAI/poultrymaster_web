-- =============================================================================
-- Migration 035: Stored procedures for Suppliers / Purchases / Expenses /
--                Cash Transfers
-- =============================================================================
-- Run AFTER 034_AddGenericSuppliersPurchasesExpenses.sql.
--
-- Approval pattern is the same as Phase 3: idempotent, XACT_ABORT-protected
-- transactions that keep inventory + cash + supplier balance in lockstep.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- =============================================================================
-- GenericSupplier
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericSupplier_GetAll
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericSupplierId, FarmId, SupplierName, SupplierType, PhoneNumber, Email,
           Location, Address, PaymentTermsDays, OpeningBalance, CurrentBalance,
           IsActive, IsDeleted, Notes, CreatedAt, UpdatedAt
    FROM   dbo.GenericSuppliers
    WHERE  FarmId = @FarmId AND IsDeleted = 0
    ORDER  BY IsActive DESC, SupplierName;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericSupplier_GetById
    @GenericSupplierId INT,
    @FarmId            NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericSupplierId, FarmId, SupplierName, SupplierType, PhoneNumber, Email,
           Location, Address, PaymentTermsDays, OpeningBalance, CurrentBalance,
           IsActive, IsDeleted, Notes, CreatedAt, UpdatedAt
    FROM   dbo.GenericSuppliers
    WHERE  GenericSupplierId = @GenericSupplierId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericSupplier_Insert
    @FarmId           NVARCHAR(450),
    @SupplierName     NVARCHAR(200),
    @SupplierType     NVARCHAR(40)   = 'ProductSupplier',
    @PhoneNumber      NVARCHAR(50)   = NULL,
    @Email            NVARCHAR(150)  = NULL,
    @Location         NVARCHAR(255)  = NULL,
    @Address          NVARCHAR(500)  = NULL,
    @PaymentTermsDays INT            = 0,
    @OpeningBalance   DECIMAL(14,2)  = 0,
    @IsActive         BIT            = 1,
    @Notes            NVARCHAR(1000) = NULL,
    @CreatedBy        NVARCHAR(450)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    INSERT INTO dbo.GenericSuppliers (
        FarmId, SupplierName, SupplierType, PhoneNumber, Email, Location, Address,
        PaymentTermsDays, OpeningBalance, CurrentBalance, IsActive, Notes
    )
    VALUES (
        @FarmId, @SupplierName, @SupplierType, @PhoneNumber, @Email, @Location, @Address,
        @PaymentTermsDays, @OpeningBalance, @OpeningBalance, @IsActive, @Notes
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    IF (@OpeningBalance <> 0)
    BEGIN
        INSERT INTO dbo.GenericSupplierLedger (
            FarmId, GenericSupplierId, TransactionDate, TransactionType,
            DebitAmount, CreditAmount, BalanceAfterTransaction, Description, CreatedBy
        )
        VALUES (
            @FarmId, @NewId, SYSUTCDATETIME(), 'OpeningBalance',
            CASE WHEN @OpeningBalance < 0 THEN -@OpeningBalance ELSE 0 END,
            CASE WHEN @OpeningBalance > 0 THEN  @OpeningBalance ELSE 0 END,
            @OpeningBalance, 'Opening balance', @CreatedBy
        );
    END

    COMMIT TRANSACTION;

    SELECT @NewId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericSupplier_Update
    @GenericSupplierId INT,
    @FarmId            NVARCHAR(450),
    @SupplierName      NVARCHAR(200),
    @SupplierType      NVARCHAR(40),
    @PhoneNumber       NVARCHAR(50)   = NULL,
    @Email             NVARCHAR(150)  = NULL,
    @Location          NVARCHAR(255)  = NULL,
    @Address           NVARCHAR(500)  = NULL,
    @PaymentTermsDays  INT,
    @IsActive          BIT,
    @Notes             NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericSuppliers
    SET    SupplierName     = @SupplierName,
           SupplierType     = @SupplierType,
           PhoneNumber      = @PhoneNumber,
           Email            = @Email,
           Location         = @Location,
           Address          = @Address,
           PaymentTermsDays = @PaymentTermsDays,
           IsActive         = @IsActive,
           Notes            = @Notes,
           UpdatedAt        = SYSUTCDATETIME()
    WHERE  GenericSupplierId = @GenericSupplierId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericSupplier_Delete
    @GenericSupplierId INT,
    @FarmId            NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericSuppliers
    SET    IsDeleted = 1, IsActive = 0, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericSupplierId = @GenericSupplierId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericSupplier_GetOwedToThem
    @FarmId  NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericSupplierId, FarmId, SupplierName, SupplierType, PhoneNumber,
           PaymentTermsDays, CurrentBalance
    FROM   dbo.GenericSuppliers
    WHERE  FarmId = @FarmId AND IsDeleted = 0 AND CurrentBalance > 0
    ORDER  BY CurrentBalance DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericSupplierLedger_GetForSupplier
    @GenericSupplierId INT,
    @FarmId            NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT GenericSupplierLedgerId, FarmId, GenericSupplierId, TransactionDate,
           TransactionType, PurchaseId, ExpenseId, PaymentId,
           DebitAmount, CreditAmount, BalanceAfterTransaction,
           Description, CreatedBy, CreatedAt
    FROM   dbo.GenericSupplierLedger
    WHERE  GenericSupplierId = @GenericSupplierId AND FarmId = @FarmId
    ORDER  BY TransactionDate, GenericSupplierLedgerId;
END
GO

-- =============================================================================
-- GenericSupplierPayment
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericSupplierPayment_GetAll
    @FarmId  NVARCHAR(450),
    @Status  NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.GenericSupplierPaymentId, p.FarmId, p.GenericSupplierId,
           s.SupplierName, p.PaymentDate, p.Amount, p.PaymentMethod,
           p.GenericCashAccountId, p.PaidByStaffId, p.LinkedPurchaseId, p.LinkedExpenseId,
           p.Status, p.Notes, p.CreatedBy, p.ApprovedBy, p.ApprovedAt,
           p.CreatedAt, p.UpdatedAt
    FROM   dbo.GenericSupplierPayments p
    INNER  JOIN dbo.GenericSuppliers s ON s.GenericSupplierId = p.GenericSupplierId
    WHERE  p.FarmId = @FarmId
       AND (@Status IS NULL OR p.Status = @Status)
    ORDER  BY p.PaymentDate DESC, p.GenericSupplierPaymentId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericSupplierPayment_GetById
    @GenericSupplierPaymentId INT,
    @FarmId                   NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.GenericSupplierPaymentId, p.FarmId, p.GenericSupplierId,
           s.SupplierName, p.PaymentDate, p.Amount, p.PaymentMethod,
           p.GenericCashAccountId, p.PaidByStaffId, p.LinkedPurchaseId, p.LinkedExpenseId,
           p.Status, p.Notes, p.CreatedBy, p.ApprovedBy, p.ApprovedAt,
           p.CreatedAt, p.UpdatedAt
    FROM   dbo.GenericSupplierPayments p
    INNER  JOIN dbo.GenericSuppliers s ON s.GenericSupplierId = p.GenericSupplierId
    WHERE  p.GenericSupplierPaymentId = @GenericSupplierPaymentId AND p.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericSupplierPayment_Insert
    @FarmId                NVARCHAR(450),
    @GenericSupplierId     INT,
    @Amount                DECIMAL(14,2),
    @PaymentMethod         NVARCHAR(40),
    @GenericCashAccountId  INT            = NULL,
    @PaidByStaffId         INT            = NULL,
    @LinkedPurchaseId      INT            = NULL,
    @LinkedExpenseId       INT            = NULL,
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

    INSERT INTO dbo.GenericSupplierPayments (
        FarmId, GenericSupplierId, PaymentDate, Amount, PaymentMethod,
        GenericCashAccountId, PaidByStaffId, LinkedPurchaseId, LinkedExpenseId,
        Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, @GenericSupplierId, ISNULL(@PaymentDate, SYSUTCDATETIME()),
        @Amount, @PaymentMethod, @GenericCashAccountId, @PaidByStaffId,
        @LinkedPurchaseId, @LinkedExpenseId, 'Draft', @Notes, @CreatedBy
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

-- Atomic: supplier ledger PaymentDebit + supplier balance down + cash CashOut.
CREATE OR ALTER PROCEDURE dbo.spGenericSupplierPayment_Approve
    @GenericSupplierPaymentId INT,
    @FarmId                   NVARCHAR(450),
    @ApprovedBy               NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Idempotent
    IF EXISTS (SELECT 1 FROM dbo.GenericSupplierPayments
               WHERE  GenericSupplierPaymentId = @GenericSupplierPaymentId
                 AND  FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT GenericSupplierPaymentId, Status, ApprovedBy, ApprovedAt
        FROM   dbo.GenericSupplierPayments
        WHERE  GenericSupplierPaymentId = @GenericSupplierPaymentId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @SupplierId INT, @Amount DECIMAL(14,2), @CashAccountId INT,
            @Status NVARCHAR(20), @PaymentDate DATETIME2, @Notes NVARCHAR(1000);

    SELECT @SupplierId    = GenericSupplierId,
           @Amount        = Amount,
           @CashAccountId = GenericCashAccountId,
           @Status        = Status,
           @PaymentDate   = PaymentDate,
           @Notes         = Notes
    FROM   dbo.GenericSupplierPayments
    WHERE  GenericSupplierPaymentId = @GenericSupplierPaymentId AND FarmId = @FarmId;

    IF @SupplierId IS NULL
    BEGIN
        RAISERROR('Supplier payment %d not found.', 16, 1, @GenericSupplierPaymentId);
        RETURN;
    END
    IF @Status NOT IN ('Draft')
    BEGIN
        RAISERROR('Supplier payment cannot be approved from status %s.', 16, 1, @Status);
        RETURN;
    END

    -- Cash pre-flight
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
        SET @CashNewBalance = @CashCurrent - @Amount;
        IF (@CashNewBalance < 0 AND @CashAllowNeg = 0)
        BEGIN
            RAISERROR('Supplier payment would push cash account negative; account does not allow it.', 16, 1);
            RETURN;
        END
    END

    DECLARE @SupplierBalance DECIMAL(14,2);
    SELECT @SupplierBalance = CurrentBalance
    FROM   dbo.GenericSuppliers WHERE GenericSupplierId = @SupplierId AND FarmId = @FarmId;
    IF @SupplierBalance IS NULL
    BEGIN
        RAISERROR('Supplier on the payment does not exist or belongs to another farm.', 16, 1);
        RETURN;
    END
    DECLARE @SupplierNewBalance DECIMAL(14,2) = @SupplierBalance - @Amount;

    BEGIN TRANSACTION;

    UPDATE dbo.GenericSupplierPayments
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericSupplierPaymentId = @GenericSupplierPaymentId AND FarmId = @FarmId;

    INSERT INTO dbo.GenericSupplierLedger (
        FarmId, GenericSupplierId, TransactionDate, TransactionType,
        PaymentId, DebitAmount, CreditAmount, BalanceAfterTransaction,
        Description, CreatedBy
    )
    VALUES (
        @FarmId, @SupplierId, @PaymentDate, 'PaymentDebit',
        @GenericSupplierPaymentId, @Amount, 0, @SupplierNewBalance,
        ISNULL(@Notes, 'Supplier payment'), @ApprovedBy
    );

    UPDATE dbo.GenericSuppliers
    SET    CurrentBalance = @SupplierNewBalance, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericSupplierId = @SupplierId AND FarmId = @FarmId;

    IF @CashAccountId IS NOT NULL
    BEGIN
        INSERT INTO dbo.GenericCashTransactions (
            FarmId, GenericCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
            CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @CashAccountId, @PaymentDate, 'CashOut',
            'SupplierPayment', @GenericSupplierPaymentId, -@Amount, @CashNewBalance,
            ISNULL(@Notes, 'Supplier payment'),
            @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
        );

        UPDATE dbo.GenericCashAccounts
        SET    CurrentBalance = @CashNewBalance, UpdatedAt = SYSUTCDATETIME()
        WHERE  GenericCashAccountId = @CashAccountId AND FarmId = @FarmId;
    END

    COMMIT TRANSACTION;

    SELECT GenericSupplierPaymentId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.GenericSupplierPayments
    WHERE  GenericSupplierPaymentId = @GenericSupplierPaymentId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericSupplierPayment_Cancel
    @GenericSupplierPaymentId INT,
    @FarmId                   NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericSupplierPayments
    SET    Status = 'Cancelled', UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericSupplierPaymentId = @GenericSupplierPaymentId
       AND FarmId = @FarmId AND Status = 'Draft';

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Payment cannot be cancelled (not found or already finalized).', 16, 1);
        RETURN;
    END
END
GO

-- =============================================================================
-- GenericPurchase + GenericPurchaseItem
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericPurchase_GetAll
    @FarmId  NVARCHAR(450),
    @Status  NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.GenericPurchaseId, p.FarmId, p.GenericSupplierId, s.SupplierName,
           p.PurchaseDate, p.BranchId,
           p.SubtotalAmount, p.DiscountAmount, p.TaxAmount, p.TotalAmount,
           p.AmountPaid, p.Balance, p.PaymentStatus, p.PaymentMethod,
           p.GenericCashAccountId, p.InvoiceNumber, p.ReceiptUrl, p.ReceivedByStaffId,
           p.Status, p.Notes, p.CreatedBy, p.ApprovedBy, p.ApprovedAt,
           p.CancelledBy, p.CancelledAt, p.CancellationReason,
           p.CreatedAt, p.UpdatedAt
    FROM   dbo.GenericPurchases p
    LEFT   JOIN dbo.GenericSuppliers s ON s.GenericSupplierId = p.GenericSupplierId
    WHERE  p.FarmId = @FarmId AND p.IsDeleted = 0
       AND (@Status IS NULL OR p.Status = @Status)
    ORDER  BY p.PurchaseDate DESC, p.GenericPurchaseId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericPurchase_GetById
    @GenericPurchaseId INT,
    @FarmId            NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT p.GenericPurchaseId, p.FarmId, p.GenericSupplierId, s.SupplierName,
           p.PurchaseDate, p.BranchId,
           p.SubtotalAmount, p.DiscountAmount, p.TaxAmount, p.TotalAmount,
           p.AmountPaid, p.Balance, p.PaymentStatus, p.PaymentMethod,
           p.GenericCashAccountId, p.InvoiceNumber, p.ReceiptUrl, p.ReceivedByStaffId,
           p.Status, p.Notes, p.CreatedBy, p.ApprovedBy, p.ApprovedAt,
           p.CancelledBy, p.CancelledAt, p.CancellationReason,
           p.CreatedAt, p.UpdatedAt
    FROM   dbo.GenericPurchases p
    LEFT   JOIN dbo.GenericSuppliers s ON s.GenericSupplierId = p.GenericSupplierId
    WHERE  p.GenericPurchaseId = @GenericPurchaseId AND p.FarmId = @FarmId;

    SELECT GenericPurchaseItemId, GenericPurchaseId, FarmId, GenericProductId,
           Description, Quantity, UnitCost, DiscountAmount, LineTotal, Notes
    FROM   dbo.GenericPurchaseItems
    WHERE  GenericPurchaseId = @GenericPurchaseId AND FarmId = @FarmId
    ORDER  BY GenericPurchaseItemId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericPurchase_Insert
    @FarmId                NVARCHAR(450),
    @PurchaseDate          DATETIME2      = NULL,
    @GenericSupplierId     INT            = NULL,
    @BranchId              INT            = NULL,
    @HeaderDiscountAmount  DECIMAL(14,2)  = 0,
    @TaxAmount             DECIMAL(14,2)  = 0,
    @AmountPaid            DECIMAL(14,2)  = 0,
    @PaymentMethod         NVARCHAR(20)   = NULL,
    @GenericCashAccountId  INT            = NULL,
    @InvoiceNumber         NVARCHAR(60)   = NULL,
    @ReceiptUrl            NVARCHAR(500)  = NULL,
    @ReceivedByStaffId     INT            = NULL,
    @Notes                 NVARCHAR(1000) = NULL,
    @CreatedBy             NVARCHAR(450)  = NULL,
    @Items                 dbo.GenericPurchaseItemTvp READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM @Items)
    BEGIN
        RAISERROR('Purchase must have at least one item.', 16, 1);
        RETURN;
    END
    IF EXISTS (SELECT 1 FROM @Items WHERE Quantity <= 0)
    BEGIN
        RAISERROR('Item quantity must be greater than zero.', 16, 1);
        RETURN;
    END
    IF EXISTS (SELECT 1 FROM @Items WHERE UnitCost < 0)
    BEGIN
        RAISERROR('Item unit cost cannot be negative.', 16, 1);
        RETURN;
    END

    DECLARE @Subtotal DECIMAL(14,2) = (
        SELECT ISNULL(SUM(Quantity * UnitCost - DiscountAmount), 0) FROM @Items
    );
    DECLARE @Total   DECIMAL(14,2) = @Subtotal - ISNULL(@HeaderDiscountAmount, 0) + ISNULL(@TaxAmount, 0);
    DECLARE @Balance DECIMAL(14,2) = @Total - ISNULL(@AmountPaid, 0);
    DECLARE @PayStatus NVARCHAR(20) =
        CASE
            WHEN ISNULL(@AmountPaid, 0) = 0  THEN 'Unpaid'
            WHEN @AmountPaid >= @Total       THEN 'Paid'
            ELSE 'Partial'
        END;

    IF (@Balance > 0 AND @GenericSupplierId IS NULL)
    BEGIN
        RAISERROR('Credit purchase requires a supplier.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    INSERT INTO dbo.GenericPurchases (
        FarmId, GenericSupplierId, PurchaseDate, BranchId,
        SubtotalAmount, DiscountAmount, TaxAmount,
        TotalAmount, AmountPaid, Balance, PaymentStatus, PaymentMethod,
        GenericCashAccountId, InvoiceNumber, ReceiptUrl, ReceivedByStaffId,
        Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, @GenericSupplierId, ISNULL(@PurchaseDate, SYSUTCDATETIME()), @BranchId,
        @Subtotal, ISNULL(@HeaderDiscountAmount, 0), ISNULL(@TaxAmount, 0),
        @Total, ISNULL(@AmountPaid, 0), @Balance, @PayStatus, @PaymentMethod,
        @GenericCashAccountId, @InvoiceNumber, @ReceiptUrl, @ReceivedByStaffId,
        'Draft', @Notes, @CreatedBy
    );

    DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

    INSERT INTO dbo.GenericPurchaseItems (
        GenericPurchaseId, FarmId, GenericProductId, Description,
        Quantity, UnitCost, DiscountAmount, Notes
    )
    SELECT @NewId, @FarmId, GenericProductId, Description,
           Quantity, UnitCost, ISNULL(DiscountAmount, 0), Notes
    FROM   @Items;

    COMMIT TRANSACTION;

    SELECT @NewId;
END
GO

-- THE BIG ONE for the purchase side.
CREATE OR ALTER PROCEDURE dbo.spGenericPurchase_Approve
    @GenericPurchaseId INT,
    @FarmId            NVARCHAR(450),
    @ApprovedBy        NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Idempotent
    IF EXISTS (SELECT 1 FROM dbo.GenericPurchases
               WHERE  GenericPurchaseId = @GenericPurchaseId AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT GenericPurchaseId, Status, ApprovedBy, ApprovedAt
        FROM   dbo.GenericPurchases
        WHERE  GenericPurchaseId = @GenericPurchaseId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @Status NVARCHAR(20), @SupplierId INT, @CashAccountId INT,
            @AmountPaid DECIMAL(14,2), @Balance DECIMAL(14,2),
            @PurchaseDate DATETIME2, @InvoiceNumber NVARCHAR(60);

    SELECT @Status        = Status,
           @SupplierId    = GenericSupplierId,
           @CashAccountId = GenericCashAccountId,
           @AmountPaid    = AmountPaid,
           @Balance       = Balance,
           @PurchaseDate  = PurchaseDate,
           @InvoiceNumber = InvoiceNumber
    FROM   dbo.GenericPurchases
    WHERE  GenericPurchaseId = @GenericPurchaseId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL
    BEGIN
        RAISERROR('Purchase %d not found.', 16, 1, @GenericPurchaseId);
        RETURN;
    END
    IF @Status <> 'Draft'
    BEGIN
        RAISERROR('Purchase cannot be approved from status %s.', 16, 1, @Status);
        RETURN;
    END
    IF (@AmountPaid > 0 AND @CashAccountId IS NULL)
    BEGIN
        RAISERROR('AmountPaid is greater than zero but no GenericCashAccountId is set.', 16, 1);
        RETURN;
    END
    IF (@Balance > 0 AND @SupplierId IS NULL)
    BEGIN
        RAISERROR('Purchase has an unpaid balance but no supplier is attached.', 16, 1);
        RETURN;
    END

    -- Cash pre-flight
    DECLARE @CashNewBalance DECIMAL(14,2) = NULL;
    IF (@AmountPaid > 0)
    BEGIN
        DECLARE @CashAllowNeg BIT, @CashCurrent DECIMAL(14,2);
        SELECT @CashAllowNeg = AllowNegativeBalance, @CashCurrent = CurrentBalance
        FROM   dbo.GenericCashAccounts
        WHERE  GenericCashAccountId = @CashAccountId AND FarmId = @FarmId;

        IF @CashCurrent IS NULL
        BEGIN
            RAISERROR('Cash account on the purchase does not exist or belongs to another farm.', 16, 1);
            RETURN;
        END
        SET @CashNewBalance = @CashCurrent - @AmountPaid;
        IF (@CashNewBalance < 0 AND @CashAllowNeg = 0)
        BEGIN
            RAISERROR('Purchase would push cash account negative; account does not allow it.', 16, 1);
            RETURN;
        END
    END

    BEGIN TRANSACTION;

    -- 1. Mark approved
    UPDATE dbo.GenericPurchases
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericPurchaseId = @GenericPurchaseId AND FarmId = @FarmId;

    -- 2. Inventory: PurchaseIn for products with TrackInventory=1
    INSERT INTO dbo.GenericStockMovements (
        FarmId, GenericProductId, MovementDate, MovementType, Quantity,
        UnitCost, TotalCostValue, ReferenceType, ReferenceId,
        Reason, CreatedBy, ApprovedBy, ApprovedAt
    )
    SELECT @FarmId, i.GenericProductId, @PurchaseDate, 'PurchaseIn', i.Quantity,
           i.UnitCost, i.UnitCost * i.Quantity, 'Purchase', @GenericPurchaseId,
           CONCAT('Purchase ', ISNULL(@InvoiceNumber, CAST(@GenericPurchaseId AS NVARCHAR(20)))),
           @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
    FROM   dbo.GenericPurchaseItems i
    INNER  JOIN dbo.GenericProducts p
        ON p.GenericProductId = i.GenericProductId AND p.FarmId = @FarmId
    WHERE  i.GenericPurchaseId = @GenericPurchaseId
       AND p.TrackInventory = 1;

    UPDATE p
    SET    p.CurrentStock = p.CurrentStock + i.Quantity,
           p.UpdatedAt    = SYSUTCDATETIME()
    FROM   dbo.GenericProducts p
    INNER  JOIN dbo.GenericPurchaseItems i
        ON i.GenericProductId = p.GenericProductId AND i.FarmId = p.FarmId
    WHERE  i.GenericPurchaseId = @GenericPurchaseId
       AND p.TrackInventory = 1
       AND p.FarmId = @FarmId;

    -- 3. Cash side: CashOut for AmountPaid
    IF (@AmountPaid > 0)
    BEGIN
        INSERT INTO dbo.GenericCashTransactions (
            FarmId, GenericCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
            CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @CashAccountId, @PurchaseDate, 'CashOut',
            'Purchase', @GenericPurchaseId, -@AmountPaid, @CashNewBalance,
            CONCAT('Purchase ', ISNULL(@InvoiceNumber, CAST(@GenericPurchaseId AS NVARCHAR(20)))),
            @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
        );

        UPDATE dbo.GenericCashAccounts
        SET    CurrentBalance = @CashNewBalance, UpdatedAt = SYSUTCDATETIME()
        WHERE  GenericCashAccountId = @CashAccountId AND FarmId = @FarmId;
    END

    -- 4. Supplier side: PurchaseCredit ledger + bump supplier balance
    IF (@Balance > 0 AND @SupplierId IS NOT NULL)
    BEGIN
        DECLARE @SupplierNewBalance DECIMAL(14,2);
        SELECT @SupplierNewBalance = CurrentBalance + @Balance
        FROM   dbo.GenericSuppliers
        WHERE  GenericSupplierId = @SupplierId AND FarmId = @FarmId;

        INSERT INTO dbo.GenericSupplierLedger (
            FarmId, GenericSupplierId, TransactionDate, TransactionType,
            PurchaseId, DebitAmount, CreditAmount, BalanceAfterTransaction,
            Description, CreatedBy
        )
        VALUES (
            @FarmId, @SupplierId, @PurchaseDate, 'PurchaseCredit',
            @GenericPurchaseId, 0, @Balance, @SupplierNewBalance,
            CONCAT('Credit on purchase ', ISNULL(@InvoiceNumber, CAST(@GenericPurchaseId AS NVARCHAR(20)))),
            @ApprovedBy
        );

        UPDATE dbo.GenericSuppliers
        SET    CurrentBalance = @SupplierNewBalance, UpdatedAt = SYSUTCDATETIME()
        WHERE  GenericSupplierId = @SupplierId AND FarmId = @FarmId;
    END

    COMMIT TRANSACTION;

    SELECT GenericPurchaseId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.GenericPurchases
    WHERE  GenericPurchaseId = @GenericPurchaseId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericPurchase_Cancel
    @GenericPurchaseId INT,
    @FarmId            NVARCHAR(450),
    @CancelledBy       NVARCHAR(450) = NULL,
    @Reason            NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericPurchases
    SET    Status = 'Cancelled',
           CancelledBy = @CancelledBy,
           CancelledAt = SYSUTCDATETIME(),
           CancellationReason = @Reason,
           UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericPurchaseId = @GenericPurchaseId AND FarmId = @FarmId AND Status = 'Draft';

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Purchase cannot be cancelled (not found or not in Draft).', 16, 1);
        RETURN;
    END
END
GO

-- =============================================================================
-- GenericExpense
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericExpense_GetAll
    @FarmId    NVARCHAR(450),
    @Status    NVARCHAR(20) = NULL,
    @FromDate  DATETIME2    = NULL,
    @ToDate    DATETIME2    = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT e.GenericExpenseId, e.FarmId, e.ExpenseDate,
           e.GenericExpenseCategoryId, c.Name AS CategoryName,
           e.GenericSupplierId, s.SupplierName,
           e.Description, e.Amount, e.PaidTo, e.PaymentMethod,
           e.GenericCashAccountId, e.ReceiptUrl, e.BranchId, e.StaffId,
           e.Status, e.Notes, e.CreatedBy, e.ApprovedBy, e.ApprovedAt,
           e.RejectionReason, e.CreatedAt, e.UpdatedAt
    FROM   dbo.GenericExpenses e
    INNER  JOIN dbo.GenericExpenseCategories c ON c.GenericExpenseCategoryId = e.GenericExpenseCategoryId
    LEFT   JOIN dbo.GenericSuppliers s ON s.GenericSupplierId = e.GenericSupplierId
    WHERE  e.FarmId = @FarmId AND e.IsDeleted = 0
       AND (@Status   IS NULL OR e.Status = @Status)
       AND (@FromDate IS NULL OR e.ExpenseDate >= @FromDate)
       AND (@ToDate   IS NULL OR e.ExpenseDate <= @ToDate)
    ORDER  BY e.ExpenseDate DESC, e.GenericExpenseId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericExpense_GetById
    @GenericExpenseId INT,
    @FarmId           NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT e.GenericExpenseId, e.FarmId, e.ExpenseDate,
           e.GenericExpenseCategoryId, c.Name AS CategoryName,
           e.GenericSupplierId, s.SupplierName,
           e.Description, e.Amount, e.PaidTo, e.PaymentMethod,
           e.GenericCashAccountId, e.ReceiptUrl, e.BranchId, e.StaffId,
           e.Status, e.Notes, e.CreatedBy, e.ApprovedBy, e.ApprovedAt,
           e.RejectionReason, e.CreatedAt, e.UpdatedAt
    FROM   dbo.GenericExpenses e
    INNER  JOIN dbo.GenericExpenseCategories c ON c.GenericExpenseCategoryId = e.GenericExpenseCategoryId
    LEFT   JOIN dbo.GenericSuppliers s ON s.GenericSupplierId = e.GenericSupplierId
    WHERE  e.GenericExpenseId = @GenericExpenseId AND e.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericExpense_Insert
    @FarmId                    NVARCHAR(450),
    @ExpenseDate               DATETIME2      = NULL,
    @GenericExpenseCategoryId  INT,
    @GenericSupplierId         INT            = NULL,
    @Description               NVARCHAR(500)  = NULL,
    @Amount                    DECIMAL(14,2),
    @PaidTo                    NVARCHAR(200)  = NULL,
    @PaymentMethod             NVARCHAR(20),
    @GenericCashAccountId      INT            = NULL,
    @ReceiptUrl                NVARCHAR(500)  = NULL,
    @BranchId                  INT            = NULL,
    @StaffId                   INT            = NULL,
    @Notes                     NVARCHAR(1000) = NULL,
    @CreatedBy                 NVARCHAR(450)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF (@Amount <= 0)
    BEGIN
        RAISERROR('Expense amount must be greater than zero.', 16, 1);
        RETURN;
    END
    IF (@PaymentMethod = 'Credit' AND @GenericSupplierId IS NULL)
    BEGIN
        RAISERROR('Credit expense requires a supplier.', 16, 1);
        RETURN;
    END
    IF (@PaymentMethod <> 'Credit' AND @GenericCashAccountId IS NULL)
    BEGIN
        RAISERROR('Non-credit expense requires a cash account.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.GenericExpenses (
        FarmId, ExpenseDate, GenericExpenseCategoryId, GenericSupplierId,
        Description, Amount, PaidTo, PaymentMethod, GenericCashAccountId,
        ReceiptUrl, BranchId, StaffId, Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, ISNULL(@ExpenseDate, SYSUTCDATETIME()), @GenericExpenseCategoryId, @GenericSupplierId,
        @Description, @Amount, @PaidTo, @PaymentMethod, @GenericCashAccountId,
        @ReceiptUrl, @BranchId, @StaffId, 'Draft', @Notes, @CreatedBy
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

-- Approve: branches on PaymentMethod.
--   * Credit  → SupplierLedger ExpenseCredit + supplier balance up.
--   * Other   → CashTransaction CashOut + cash account balance down.
CREATE OR ALTER PROCEDURE dbo.spGenericExpense_Approve
    @GenericExpenseId INT,
    @FarmId           NVARCHAR(450),
    @ApprovedBy       NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Idempotent
    IF EXISTS (SELECT 1 FROM dbo.GenericExpenses
               WHERE  GenericExpenseId = @GenericExpenseId AND FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT GenericExpenseId, Status, ApprovedBy, ApprovedAt
        FROM   dbo.GenericExpenses
        WHERE  GenericExpenseId = @GenericExpenseId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @Status NVARCHAR(20), @PaymentMethod NVARCHAR(20),
            @Amount DECIMAL(14,2), @CashAccountId INT, @SupplierId INT,
            @ExpenseDate DATETIME2, @Description NVARCHAR(500), @CategoryId INT;

    SELECT @Status        = Status,
           @PaymentMethod = PaymentMethod,
           @Amount        = Amount,
           @CashAccountId = GenericCashAccountId,
           @SupplierId    = GenericSupplierId,
           @ExpenseDate   = ExpenseDate,
           @Description   = Description,
           @CategoryId    = GenericExpenseCategoryId
    FROM   dbo.GenericExpenses
    WHERE  GenericExpenseId = @GenericExpenseId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL
    BEGIN
        RAISERROR('Expense %d not found.', 16, 1, @GenericExpenseId);
        RETURN;
    END
    IF @Status NOT IN ('Draft', 'Submitted')
    BEGIN
        RAISERROR('Expense cannot be approved from status %s.', 16, 1, @Status);
        RETURN;
    END

    DECLARE @CategoryName NVARCHAR(100);
    SELECT @CategoryName = Name FROM dbo.GenericExpenseCategories
    WHERE  GenericExpenseCategoryId = @CategoryId AND FarmId = @FarmId;

    DECLARE @Desc NVARCHAR(500) =
        ISNULL(@Description, CONCAT('Expense: ', ISNULL(@CategoryName, '?')));

    BEGIN TRANSACTION;

    UPDATE dbo.GenericExpenses
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericExpenseId = @GenericExpenseId AND FarmId = @FarmId;

    IF @PaymentMethod = 'Credit'
    BEGIN
        DECLARE @SupplierNewBalance DECIMAL(14,2);
        SELECT @SupplierNewBalance = CurrentBalance + @Amount
        FROM   dbo.GenericSuppliers
        WHERE  GenericSupplierId = @SupplierId AND FarmId = @FarmId;

        IF @SupplierNewBalance IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('Supplier on the expense does not exist or belongs to another farm.', 16, 1);
            RETURN;
        END

        INSERT INTO dbo.GenericSupplierLedger (
            FarmId, GenericSupplierId, TransactionDate, TransactionType,
            ExpenseId, DebitAmount, CreditAmount, BalanceAfterTransaction,
            Description, CreatedBy
        )
        VALUES (
            @FarmId, @SupplierId, @ExpenseDate, 'ExpenseCredit',
            @GenericExpenseId, 0, @Amount, @SupplierNewBalance,
            @Desc, @ApprovedBy
        );

        UPDATE dbo.GenericSuppliers
        SET    CurrentBalance = @SupplierNewBalance, UpdatedAt = SYSUTCDATETIME()
        WHERE  GenericSupplierId = @SupplierId AND FarmId = @FarmId;
    END
    ELSE
    BEGIN
        DECLARE @CashAllowNeg BIT, @CashCurrent DECIMAL(14,2), @CashNewBalance DECIMAL(14,2);
        SELECT @CashAllowNeg = AllowNegativeBalance, @CashCurrent = CurrentBalance
        FROM   dbo.GenericCashAccounts
        WHERE  GenericCashAccountId = @CashAccountId AND FarmId = @FarmId;

        IF @CashCurrent IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('Cash account on the expense does not exist or belongs to another farm.', 16, 1);
            RETURN;
        END
        SET @CashNewBalance = @CashCurrent - @Amount;
        IF (@CashNewBalance < 0 AND @CashAllowNeg = 0)
        BEGIN
            ROLLBACK TRANSACTION;
            RAISERROR('Expense would push cash account negative; account does not allow it.', 16, 1);
            RETURN;
        END

        INSERT INTO dbo.GenericCashTransactions (
            FarmId, GenericCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
            CreatedBy, ApprovedBy, ApprovedAt
        )
        VALUES (
            @FarmId, @CashAccountId, @ExpenseDate, 'CashOut',
            'Expense', @GenericExpenseId, -@Amount, @CashNewBalance, @Desc,
            @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
        );

        UPDATE dbo.GenericCashAccounts
        SET    CurrentBalance = @CashNewBalance, UpdatedAt = SYSUTCDATETIME()
        WHERE  GenericCashAccountId = @CashAccountId AND FarmId = @FarmId;
    END

    COMMIT TRANSACTION;

    SELECT GenericExpenseId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.GenericExpenses
    WHERE  GenericExpenseId = @GenericExpenseId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericExpense_Reject
    @GenericExpenseId INT,
    @FarmId           NVARCHAR(450),
    @RejectionReason  NVARCHAR(500),
    @ApprovedBy       NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericExpenses
    SET    Status = 'Rejected', RejectionReason = @RejectionReason,
           ApprovedBy = @ApprovedBy, ApprovedAt = SYSUTCDATETIME(),
           UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericExpenseId = @GenericExpenseId
       AND FarmId = @FarmId
       AND Status IN ('Draft', 'Submitted');

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Expense cannot be rejected (not found or already finalized).', 16, 1);
        RETURN;
    END
END
GO

-- =============================================================================
-- GenericCashTransfer
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.spGenericCashTransfer_GetAll
    @FarmId  NVARCHAR(450),
    @Status  NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.GenericCashTransferId, t.FarmId, t.FromGenericCashAccountId,
           af.AccountName AS FromAccountName,
           t.ToGenericCashAccountId, ato.AccountName AS ToAccountName,
           t.TransferDate, t.Amount, t.Status, t.Notes,
           t.CreatedBy, t.ApprovedBy, t.ApprovedAt, t.CreatedAt, t.UpdatedAt
    FROM   dbo.GenericCashTransfers t
    INNER  JOIN dbo.GenericCashAccounts af  ON af.GenericCashAccountId  = t.FromGenericCashAccountId
    INNER  JOIN dbo.GenericCashAccounts ato ON ato.GenericCashAccountId = t.ToGenericCashAccountId
    WHERE  t.FarmId = @FarmId
       AND (@Status IS NULL OR t.Status = @Status)
    ORDER  BY t.TransferDate DESC, t.GenericCashTransferId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCashTransfer_GetById
    @GenericCashTransferId INT,
    @FarmId                NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT t.GenericCashTransferId, t.FarmId, t.FromGenericCashAccountId,
           af.AccountName AS FromAccountName,
           t.ToGenericCashAccountId, ato.AccountName AS ToAccountName,
           t.TransferDate, t.Amount, t.Status, t.Notes,
           t.CreatedBy, t.ApprovedBy, t.ApprovedAt, t.CreatedAt, t.UpdatedAt
    FROM   dbo.GenericCashTransfers t
    INNER  JOIN dbo.GenericCashAccounts af  ON af.GenericCashAccountId  = t.FromGenericCashAccountId
    INNER  JOIN dbo.GenericCashAccounts ato ON ato.GenericCashAccountId = t.ToGenericCashAccountId
    WHERE  t.GenericCashTransferId = @GenericCashTransferId AND t.FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCashTransfer_Insert
    @FarmId                     NVARCHAR(450),
    @FromGenericCashAccountId   INT,
    @ToGenericCashAccountId     INT,
    @Amount                     DECIMAL(14,2),
    @TransferDate               DATETIME2     = NULL,
    @Notes                      NVARCHAR(500) = NULL,
    @CreatedBy                  NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF (@FromGenericCashAccountId = @ToGenericCashAccountId)
    BEGIN
        RAISERROR('Source and destination cash accounts must be different.', 16, 1);
        RETURN;
    END
    IF (@Amount <= 0)
    BEGIN
        RAISERROR('Transfer amount must be greater than zero.', 16, 1);
        RETURN;
    END

    INSERT INTO dbo.GenericCashTransfers (
        FarmId, FromGenericCashAccountId, ToGenericCashAccountId,
        TransferDate, Amount, Status, Notes, CreatedBy
    )
    VALUES (
        @FarmId, @FromGenericCashAccountId, @ToGenericCashAccountId,
        ISNULL(@TransferDate, SYSUTCDATETIME()), @Amount, 'Draft', @Notes, @CreatedBy
    );

    SELECT CAST(SCOPE_IDENTITY() AS INT);
END
GO

-- Approve: write TransferOut on source, TransferIn on dest, update both balances.
CREATE OR ALTER PROCEDURE dbo.spGenericCashTransfer_Approve
    @GenericCashTransferId INT,
    @FarmId                NVARCHAR(450),
    @ApprovedBy            NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Idempotent
    IF EXISTS (SELECT 1 FROM dbo.GenericCashTransfers
               WHERE  GenericCashTransferId = @GenericCashTransferId
                 AND  FarmId = @FarmId AND Status = 'Approved')
    BEGIN
        SELECT GenericCashTransferId, Status, ApprovedBy, ApprovedAt
        FROM   dbo.GenericCashTransfers
        WHERE  GenericCashTransferId = @GenericCashTransferId AND FarmId = @FarmId;
        RETURN;
    END

    DECLARE @FromId INT, @ToId INT, @Amount DECIMAL(14,2),
            @TransferDate DATETIME2, @Status NVARCHAR(20), @Notes NVARCHAR(500);
    SELECT @FromId       = FromGenericCashAccountId,
           @ToId         = ToGenericCashAccountId,
           @Amount       = Amount,
           @TransferDate = TransferDate,
           @Status       = Status,
           @Notes        = Notes
    FROM   dbo.GenericCashTransfers
    WHERE  GenericCashTransferId = @GenericCashTransferId AND FarmId = @FarmId;

    IF @FromId IS NULL
    BEGIN
        RAISERROR('Cash transfer %d not found.', 16, 1, @GenericCashTransferId);
        RETURN;
    END
    IF @Status <> 'Draft'
    BEGIN
        RAISERROR('Cash transfer cannot be approved from status %s.', 16, 1, @Status);
        RETURN;
    END

    DECLARE @FromAllowNeg BIT, @FromCurrent DECIMAL(14,2),
            @ToCurrent DECIMAL(14,2);

    SELECT @FromAllowNeg = AllowNegativeBalance, @FromCurrent = CurrentBalance
    FROM   dbo.GenericCashAccounts
    WHERE  GenericCashAccountId = @FromId AND FarmId = @FarmId;

    SELECT @ToCurrent = CurrentBalance
    FROM   dbo.GenericCashAccounts
    WHERE  GenericCashAccountId = @ToId AND FarmId = @FarmId;

    IF (@FromCurrent IS NULL OR @ToCurrent IS NULL)
    BEGIN
        RAISERROR('One of the cash accounts on the transfer does not exist or belongs to another farm.', 16, 1);
        RETURN;
    END

    DECLARE @FromNewBalance DECIMAL(14,2) = @FromCurrent - @Amount;
    DECLARE @ToNewBalance   DECIMAL(14,2) = @ToCurrent   + @Amount;

    IF (@FromNewBalance < 0 AND @FromAllowNeg = 0)
    BEGIN
        RAISERROR('Transfer would push source account negative; account does not allow it.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    UPDATE dbo.GenericCashTransfers
    SET    Status = 'Approved', ApprovedBy = @ApprovedBy,
           ApprovedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCashTransferId = @GenericCashTransferId AND FarmId = @FarmId;

    -- Source: TransferOut (signed negative)
    INSERT INTO dbo.GenericCashTransactions (
        FarmId, GenericCashAccountId, TransactionDate, TransactionType,
        SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
        CreatedBy, ApprovedBy, ApprovedAt
    )
    VALUES (
        @FarmId, @FromId, @TransferDate, 'TransferOut',
        'Transfer', @GenericCashTransferId, -@Amount, @FromNewBalance,
        ISNULL(@Notes, CONCAT('Transfer to account ', CAST(@ToId AS NVARCHAR(20)))),
        @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
    );

    -- Dest: TransferIn (signed positive)
    INSERT INTO dbo.GenericCashTransactions (
        FarmId, GenericCashAccountId, TransactionDate, TransactionType,
        SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
        CreatedBy, ApprovedBy, ApprovedAt
    )
    VALUES (
        @FarmId, @ToId, @TransferDate, 'TransferIn',
        'Transfer', @GenericCashTransferId, @Amount, @ToNewBalance,
        ISNULL(@Notes, CONCAT('Transfer from account ', CAST(@FromId AS NVARCHAR(20)))),
        @ApprovedBy, @ApprovedBy, SYSUTCDATETIME()
    );

    -- Update both balances
    UPDATE dbo.GenericCashAccounts
    SET    CurrentBalance = @FromNewBalance, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCashAccountId = @FromId AND FarmId = @FarmId;

    UPDATE dbo.GenericCashAccounts
    SET    CurrentBalance = @ToNewBalance, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCashAccountId = @ToId AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT GenericCashTransferId, Status, ApprovedBy, ApprovedAt
    FROM   dbo.GenericCashTransfers
    WHERE  GenericCashTransferId = @GenericCashTransferId AND FarmId = @FarmId;
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCashTransfer_Cancel
    @GenericCashTransferId INT,
    @FarmId                NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.GenericCashTransfers
    SET    Status = 'Cancelled', UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCashTransferId = @GenericCashTransferId
       AND FarmId = @FarmId AND Status = 'Draft';

    IF @@ROWCOUNT = 0
    BEGIN
        RAISERROR('Transfer cannot be cancelled (not found or already finalized).', 16, 1);
        RETURN;
    END
END
GO

PRINT '035_AddGenericPurchasesStoredProcedures.sql complete.';
GO
