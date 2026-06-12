-- =============================================================================
-- 112_AddGenericCashDefaultsAllocationAudit
-- =============================================================================
-- Cash Account integration - Slice 5. All ADDITIVE.
--
--   A. Company default cash-account mappings (preselect accounts per workflow).
--   B. Dedicated cash audit log (trigger-driven; covers every writer).
--   C. Payment-allocation primitive: store + post multiple method/account splits
--      for one source. Reusable from a new endpoint. NOTE: wiring allocations
--      into the existing sale/expense/purchase APPROVE procs (so a single sale
--      can split across accounts) is a follow-up that needs UI + dev-DB testing;
--      this migration delivers the storage + posting primitive without changing
--      those live procs.
-- =============================================================================

SET XACT_ABORT ON;
GO

-- =============================================================================
-- A. Default cash-account mappings (key -> account, per farm)
-- =============================================================================
-- Keys (suggested): CashSales, MoMoSales, BankSales, DriverReturnCash,
-- DriverReturnMoMo, DriverReturnBank, DriverFloat, ProductionExpense,
-- DeliveryExpense, FuelExpense, Payroll, PurchasePayment, PettyCash.
IF OBJECT_ID('dbo.GenericCashAccountDefaults', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericCashAccountDefaults (
        FarmId               NVARCHAR(450) NOT NULL,
        DefaultKey           NVARCHAR(40)  NOT NULL,
        GenericCashAccountId INT           NOT NULL,
        UpdatedAt            DATETIME2     NOT NULL CONSTRAINT DF_GenericCashDefaults_UpdatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT PK_GenericCashAccountDefaults PRIMARY KEY (FarmId, DefaultKey),
        CONSTRAINT FK_GenericCashAccountDefaults_Account
            FOREIGN KEY (GenericCashAccountId) REFERENCES dbo.GenericCashAccounts (GenericCashAccountId)
    );
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCashAccountDefault_Upsert
    @FarmId               NVARCHAR(450),
    @DefaultKey           NVARCHAR(40),
    @GenericCashAccountId INT
AS
BEGIN
    SET NOCOUNT ON;
    -- Validate the account belongs to the farm.
    IF NOT EXISTS (SELECT 1 FROM dbo.GenericCashAccounts
                   WHERE GenericCashAccountId = @GenericCashAccountId AND FarmId = @FarmId)
    BEGIN
        RAISERROR('Cash account does not belong to this farm.', 16, 1);
        RETURN;
    END

    MERGE dbo.GenericCashAccountDefaults AS tgt
    USING (SELECT @FarmId AS FarmId, @DefaultKey AS DefaultKey) AS src
        ON tgt.FarmId = src.FarmId AND tgt.DefaultKey = src.DefaultKey
    WHEN MATCHED THEN
        UPDATE SET GenericCashAccountId = @GenericCashAccountId, UpdatedAt = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (FarmId, DefaultKey, GenericCashAccountId)
        VALUES (@FarmId, @DefaultKey, @GenericCashAccountId);
END
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCashAccountDefault_GetAll
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT d.FarmId, d.DefaultKey, d.GenericCashAccountId, a.AccountName, a.AccountType, d.UpdatedAt
    FROM   dbo.GenericCashAccountDefaults d
    INNER  JOIN dbo.GenericCashAccounts a ON a.GenericCashAccountId = d.GenericCashAccountId
    WHERE  d.FarmId = @FarmId
    ORDER  BY d.DefaultKey;
END
GO

-- =============================================================================
-- B. Dedicated cash audit log (trigger-driven)
-- =============================================================================
IF OBJECT_ID('dbo.GenericCashAuditLog', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericCashAuditLog (
        GenericCashAuditLogId    BIGINT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450) NOT NULL,
        GenericCashAccountId     INT           NULL,
        GenericCashTransactionId BIGINT        NULL,
        Action                   NVARCHAR(30)  NOT NULL,   -- Posted | Reversed | StatusChanged
        OldStatus                NVARCHAR(20)  NULL,
        NewStatus                NVARCHAR(20)  NULL,
        Amount                   DECIMAL(14,2) NULL,
        PerformedBy              NVARCHAR(450) NULL,
        PerformedAt              DATETIME2     NOT NULL CONSTRAINT DF_GenericCashAudit_At DEFAULT (SYSUTCDATETIME())
    );
    CREATE INDEX IX_GenericCashAuditLog_FarmId ON dbo.GenericCashAuditLog (FarmId);
    CREATE INDEX IX_GenericCashAuditLog_Txn    ON dbo.GenericCashAuditLog (GenericCashTransactionId);
END
GO

CREATE OR ALTER TRIGGER dbo.trgGenericCashTransactions_AuditInsert
ON dbo.GenericCashTransactions
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.GenericCashAuditLog
        (FarmId, GenericCashAccountId, GenericCashTransactionId, Action, NewStatus, Amount, PerformedBy)
    SELECT i.FarmId, i.GenericCashAccountId, i.GenericCashTransactionId, 'Posted', i.Status, i.Amount,
           ISNULL(i.ApprovedBy, i.CreatedBy)
    FROM   inserted i;
END
GO

CREATE OR ALTER TRIGGER dbo.trgGenericCashTransactions_AuditStatus
ON dbo.GenericCashTransactions
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(Status) RETURN;

    INSERT INTO dbo.GenericCashAuditLog
        (FarmId, GenericCashAccountId, GenericCashTransactionId, Action, OldStatus, NewStatus, Amount, PerformedBy)
    SELECT i.FarmId, i.GenericCashAccountId, i.GenericCashTransactionId,
           CASE WHEN i.Status = 'Reversed' THEN 'Reversed' ELSE 'StatusChanged' END,
           d.Status, i.Status, i.Amount,
           ISNULL(i.ReversedBy, i.ApprovedBy)
    FROM   inserted i
    INNER  JOIN deleted d ON d.GenericCashTransactionId = i.GenericCashTransactionId
    WHERE  i.Status <> d.Status;
END
GO

-- =============================================================================
-- C. Payment-allocation primitive
-- =============================================================================
IF OBJECT_ID('dbo.GenericCashPaymentAllocations', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.GenericCashPaymentAllocations (
        GenericCashPaymentAllocationId BIGINT IDENTITY(1,1) PRIMARY KEY,
        FarmId                   NVARCHAR(450) NOT NULL,
        SourceType               NVARCHAR(40)  NOT NULL,   -- Sale | Purchase | Expense | CustomerPayment | ...
        SourceId                 INT           NOT NULL,
        Direction                NVARCHAR(10)  NOT NULL,   -- CashIn | CashOut
        PaymentMethod            NVARCHAR(20)  NOT NULL,   -- Cash | MoMo | Bank | ...
        GenericCashAccountId     INT           NOT NULL,
        Amount                   DECIMAL(14,2) NOT NULL,
        Reference                NVARCHAR(200) NULL,
        Notes                    NVARCHAR(500) NULL,
        GenericCashTransactionId BIGINT        NULL,       -- the posted cash txn for this split
        CreatedAt                DATETIME2     NOT NULL CONSTRAINT DF_GenericCashAlloc_CreatedAt DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT FK_GenericCashAlloc_Account
            FOREIGN KEY (GenericCashAccountId) REFERENCES dbo.GenericCashAccounts (GenericCashAccountId)
    );
    CREATE INDEX IX_GenericCashAlloc_Source ON dbo.GenericCashPaymentAllocations (FarmId, SourceType, SourceId);
END
GO

-- Posts a set of allocations (JSON array of {PaymentMethod, Amount, GenericCashAccountId,
-- Reference, Notes}) for one source, creating one CashTransaction per split and
-- updating each account balance. Idempotent per (FarmId, SourceType, SourceId, Direction):
-- if allocations already exist for the source they are returned unchanged.
CREATE OR ALTER PROCEDURE dbo.spGenericCashAllocations_Post
    @FarmId          NVARCHAR(450),
    @SourceType      NVARCHAR(40),
    @SourceId        INT,
    @Direction       NVARCHAR(10),          -- CashIn | CashOut
    @AllocationsJson NVARCHAR(MAX),
    @TransactionDate DATETIME2     = NULL,
    @CreatedBy       NVARCHAR(450) = NULL,
    @ApprovedBy      NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Direction NOT IN ('CashIn', 'CashOut')
    BEGIN
        RAISERROR('Direction must be CashIn or CashOut.', 16, 1);
        RETURN;
    END

    -- Idempotent: already allocated for this source+direction.
    IF EXISTS (SELECT 1 FROM dbo.GenericCashPaymentAllocations
               WHERE FarmId = @FarmId AND SourceType = @SourceType
                 AND SourceId = @SourceId AND Direction = @Direction)
    BEGIN
        SELECT * FROM dbo.GenericCashPaymentAllocations
        WHERE FarmId = @FarmId AND SourceType = @SourceType
          AND SourceId = @SourceId AND Direction = @Direction;
        RETURN;
    END

    DECLARE @When DATETIME2 = ISNULL(@TransactionDate, SYSUTCDATETIME());

    DECLARE @Allocs TABLE (
        PaymentMethod NVARCHAR(20),
        Amount        DECIMAL(14,2),
        AccountId     INT,
        Reference     NVARCHAR(200),
        Notes         NVARCHAR(500)
    );
    INSERT INTO @Allocs (PaymentMethod, Amount, AccountId, Reference, Notes)
    SELECT JSON_VALUE(v.value, '$.PaymentMethod'),
           TRY_CONVERT(DECIMAL(14,2), JSON_VALUE(v.value, '$.Amount')),
           TRY_CONVERT(INT, JSON_VALUE(v.value, '$.GenericCashAccountId')),
           JSON_VALUE(v.value, '$.Reference'),
           JSON_VALUE(v.value, '$.Notes')
    FROM   OPENJSON(@AllocationsJson) v;

    IF NOT EXISTS (SELECT 1 FROM @Allocs)
    BEGIN
        RAISERROR('No allocations supplied.', 16, 1);
        RETURN;
    END
    IF EXISTS (SELECT 1 FROM @Allocs WHERE Amount IS NULL OR Amount <= 0 OR AccountId IS NULL)
    BEGIN
        RAISERROR('Every allocation needs a positive Amount and a GenericCashAccountId.', 16, 1);
        RETURN;
    END
    -- All accounts must belong to the farm and be active.
    IF EXISTS (SELECT 1 FROM @Allocs al
               WHERE NOT EXISTS (SELECT 1 FROM dbo.GenericCashAccounts a
                                 WHERE a.GenericCashAccountId = al.AccountId
                                   AND a.FarmId = @FarmId AND a.IsActive = 1))
    BEGIN
        RAISERROR('One or more allocation accounts are invalid, inactive, or from another farm.', 16, 1);
        RETURN;
    END

    DECLARE @Sign DECIMAL(14,2) = CASE WHEN @Direction = 'CashIn' THEN 1 ELSE -1 END;

    BEGIN TRANSACTION;

    DECLARE @AccountId INT, @Amount DECIMAL(14,2), @Method NVARCHAR(20),
            @Ref NVARCHAR(200), @Nt NVARCHAR(500);
    DECLARE alloc CURSOR LOCAL FAST_FORWARD FOR
        SELECT AccountId, Amount, PaymentMethod, Reference, Notes FROM @Allocs;
    OPEN alloc;
    FETCH NEXT FROM alloc INTO @AccountId, @Amount, @Method, @Ref, @Nt;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @Signed DECIMAL(14,2) = @Sign * @Amount;
        DECLARE @Cur DECIMAL(14,2);
        SELECT @Cur = CurrentBalance FROM dbo.GenericCashAccounts
        WHERE GenericCashAccountId = @AccountId AND FarmId = @FarmId;
        DECLARE @NewBal DECIMAL(14,2) = @Cur + @Signed;

        INSERT INTO dbo.GenericCashTransactions (
            FarmId, GenericCashAccountId, TransactionDate, TransactionType,
            SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
            Status, CreatedBy, ApprovedBy, ApprovedAt, Notes
        )
        VALUES (
            @FarmId, @AccountId, @When, @Direction,
            @SourceType, @SourceId, @Signed, @NewBal,
            CONCAT(@SourceType, ' ', @SourceId, ' (', @Method, ')'),
            'Approved', @CreatedBy, @ApprovedBy, SYSUTCDATETIME(), @Ref
        );
        DECLARE @TxnId BIGINT = CAST(SCOPE_IDENTITY() AS BIGINT);

        -- The negative-balance trigger (migration 110) enforces policy here.
        UPDATE dbo.GenericCashAccounts
        SET    CurrentBalance = @NewBal, UpdatedAt = SYSUTCDATETIME()
        WHERE  GenericCashAccountId = @AccountId AND FarmId = @FarmId;

        INSERT INTO dbo.GenericCashPaymentAllocations (
            FarmId, SourceType, SourceId, Direction, PaymentMethod,
            GenericCashAccountId, Amount, Reference, Notes, GenericCashTransactionId
        )
        VALUES (
            @FarmId, @SourceType, @SourceId, @Direction, @Method,
            @AccountId, @Amount, @Ref, @Nt, @TxnId
        );

        FETCH NEXT FROM alloc INTO @AccountId, @Amount, @Method, @Ref, @Nt;
    END
    CLOSE alloc;
    DEALLOCATE alloc;

    COMMIT TRANSACTION;

    SELECT * FROM dbo.GenericCashPaymentAllocations
    WHERE FarmId = @FarmId AND SourceType = @SourceType
      AND SourceId = @SourceId AND Direction = @Direction;
END
GO
