-- =============================================================================
-- 109_AddGenericCashMovementPost
-- =============================================================================
-- Cash Account integration - Slice 2 (missing money-in / money-out workflows).
--
-- Adds ONE reusable proc, spGenericCashMovement_Post, for the typed cash
-- movements the Generic module did not previously have a home for:
--
--   Money IN  (CashIn) : OwnerContribution | LoanReceived | SupplierRefund | OtherIncome
--   Money OUT (CashOut): OwnerWithdrawal   | LoanRepayment | CustomerRefund | OtherCashOut
--
-- These reuse the same posting shape as sales/expenses: an Approved
-- GenericCashTransactions row (signed Amount), atomic CurrentBalance update,
-- negative-balance enforcement on cash-out. Income vs non-income classification
-- is by SourceType (reporting reads it; see slice 6), so OwnerContribution and
-- LoanReceived are NOT treated as revenue while OtherIncome may be.
--
-- Idempotency: when @SourceType/@SourceId identify an external source record,
-- a second post for the same (FarmId, SourceType, SourceId, TransactionType,
-- non-reversed) is rejected. Pure manual entries (no SourceId) are always allowed.
-- =============================================================================

SET XACT_ABORT ON;
GO

CREATE OR ALTER PROCEDURE dbo.spGenericCashMovement_Post
    @FarmId               NVARCHAR(450),
    @GenericCashAccountId INT,
    @Direction            NVARCHAR(10),      -- 'CashIn' | 'CashOut'
    @MovementType         NVARCHAR(40),      -- one of the typed values above
    @Amount               DECIMAL(14,2),     -- positive magnitude
    @Description          NVARCHAR(500) = NULL,
    @Reference            NVARCHAR(200) = NULL,
    @TransactionDate      DATETIME2     = NULL,
    @SourceId             INT           = NULL,   -- optional link to a source record
    @CreatedBy            NVARCHAR(450) = NULL,
    @ApprovedBy           NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Amount IS NULL OR @Amount <= 0
    BEGIN
        RAISERROR('Amount must be greater than zero.', 16, 1);
        RETURN;
    END
    IF @Direction NOT IN ('CashIn', 'CashOut')
    BEGIN
        RAISERROR('Direction must be CashIn or CashOut.', 16, 1);
        RETURN;
    END

    -- MovementType must match the direction.
    DECLARE @ValidIn  TABLE (v NVARCHAR(40));
    DECLARE @ValidOut TABLE (v NVARCHAR(40));
    INSERT INTO @ValidIn  VALUES ('OwnerContribution'), ('LoanReceived'), ('SupplierRefund'), ('OtherIncome');
    INSERT INTO @ValidOut VALUES ('OwnerWithdrawal'),  ('LoanRepayment'), ('CustomerRefund'), ('OtherCashOut');

    IF (@Direction = 'CashIn'  AND NOT EXISTS (SELECT 1 FROM @ValidIn  WHERE v = @MovementType))
    OR (@Direction = 'CashOut' AND NOT EXISTS (SELECT 1 FROM @ValidOut WHERE v = @MovementType))
    BEGIN
        RAISERROR('MovementType %s is not valid for direction %s.', 16, 1, @MovementType, @Direction);
        RETURN;
    END

    DECLARE @AllowNeg BIT, @Current DECIMAL(14,2), @IsActive BIT;
    SELECT @AllowNeg = AllowNegativeBalance, @Current = CurrentBalance, @IsActive = IsActive
    FROM   dbo.GenericCashAccounts
    WHERE  GenericCashAccountId = @GenericCashAccountId AND FarmId = @FarmId;

    IF @Current IS NULL
    BEGIN
        RAISERROR('Cash account not found.', 16, 1);
        RETURN;
    END
    IF @IsActive = 0
    BEGIN
        RAISERROR('Cash account is inactive.', 16, 1);
        RETURN;
    END

    -- Idempotency for source-linked movements.
    IF @SourceId IS NOT NULL AND EXISTS (
        SELECT 1 FROM dbo.GenericCashTransactions
        WHERE  FarmId = @FarmId AND SourceType = @MovementType AND SourceId = @SourceId
           AND TransactionType = @Direction AND Status <> 'Reversed')
    BEGIN
        RAISERROR('A %s movement has already been posted for this source.', 16, 1, @MovementType);
        RETURN;
    END

    DECLARE @Signed DECIMAL(14,2) = CASE WHEN @Direction = 'CashIn' THEN @Amount ELSE -@Amount END;
    DECLARE @NewBalance DECIMAL(14,2) = @Current + @Signed;

    IF (@Direction = 'CashOut' AND @NewBalance < 0 AND @AllowNeg = 0)
    BEGIN
        RAISERROR('This movement would push the account negative; account does not allow it. Add money, choose another account, or enable a negative-balance policy.', 16, 1);
        RETURN;
    END

    DECLARE @Desc NVARCHAR(500) =
        ISNULL(@Description, @MovementType)
        + CASE WHEN @Reference IS NOT NULL AND LTRIM(RTRIM(@Reference)) <> ''
               THEN ' (Ref: ' + @Reference + ')' ELSE '' END;

    BEGIN TRANSACTION;

    INSERT INTO dbo.GenericCashTransactions (
        FarmId, GenericCashAccountId, TransactionDate, TransactionType,
        SourceType, SourceId, Amount, BalanceAfterTransaction, Description,
        Status, CreatedBy, ApprovedBy, ApprovedAt, Notes
    )
    VALUES (
        @FarmId, @GenericCashAccountId, ISNULL(@TransactionDate, SYSUTCDATETIME()), @Direction,
        @MovementType, @SourceId, @Signed, @NewBalance, @Desc,
        'Approved', @CreatedBy, @ApprovedBy, SYSUTCDATETIME(), @Reference
    );

    DECLARE @NewId BIGINT = CAST(SCOPE_IDENTITY() AS BIGINT);

    UPDATE dbo.GenericCashAccounts
    SET    CurrentBalance = @NewBalance, UpdatedAt = SYSUTCDATETIME()
    WHERE  GenericCashAccountId = @GenericCashAccountId AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT @NewId AS GenericCashTransactionId, @NewBalance AS NewBalance;
END
GO
