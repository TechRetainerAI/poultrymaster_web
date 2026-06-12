-- =============================================================================
-- CashIntegration_SmokeTest.sql
-- =============================================================================
-- Manual smoke test for the Cash Account integration (migrations 108-113).
-- Run against a DEV database AFTER applying migrations 108-113.
--
-- It exercises: opening-balance seed, money-in/out, negative-balance policy,
-- reversal, multi-allocation, reconciliation, and the ledger-vs-balance report,
-- asserting that SUM(approved Amount) always equals the stored CurrentBalance.
--
-- Safe to re-run: it uses a dedicated test farm and cleans up at the end.
-- It rolls everything back at the end so nothing is persisted.
-- =============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Farm NVARCHAR(450) = N'__cash_smoke_test__';
DECLARE @Acc INT, @Acc2 INT, @Txn BIGINT, @Bal DECIMAL(14,2), @Ledger DECIMAL(14,2);

BEGIN TRAN;

-- 1. Account create seeds an OpeningBalance transaction.
EXEC dbo.spGenericCashAccount_Insert
     @FarmId=@Farm, @AccountName=N'Smoke Cash Box', @AccountType=N'MainCashBox',
     @OpeningBalance=100, @NegativeBalancePolicy=N'DoNotAllow';
SELECT @Acc = GenericCashAccountId FROM dbo.GenericCashAccounts WHERE FarmId=@Farm AND AccountName=N'Smoke Cash Box';
IF NOT EXISTS (SELECT 1 FROM dbo.GenericCashTransactions WHERE GenericCashAccountId=@Acc AND SourceType='OpeningBalance')
    THROW 50001, 'FAIL: opening-balance transaction not seeded', 1;

-- 2. Money-in (owner contribution) raises balance to 250.
EXEC dbo.spGenericCashMovement_Post
     @FarmId=@Farm, @GenericCashAccountId=@Acc, @Direction=N'CashIn',
     @MovementType=N'OwnerContribution', @Amount=150, @Description=N'Owner top-up';
SELECT @Bal = CurrentBalance FROM dbo.GenericCashAccounts WHERE GenericCashAccountId=@Acc;
IF @Bal <> 250 THROW 50002, 'FAIL: balance after owner contribution should be 250', 1;

-- 3. Money-out beyond balance on a DoNotAllow account must be blocked.
BEGIN TRY
    EXEC dbo.spGenericCashMovement_Post
         @FarmId=@Farm, @GenericCashAccountId=@Acc, @Direction=N'CashOut',
         @MovementType=N'OwnerWithdrawal', @Amount=999;
    THROW 50003, 'FAIL: overdraw on DoNotAllow account was not blocked', 1;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50003 THROW;   -- our own failure marker
    -- expected block; swallow
END CATCH

-- 4. Reverse the owner contribution -> balance back to 100.
SELECT TOP 1 @Txn = GenericCashTransactionId FROM dbo.GenericCashTransactions
WHERE GenericCashAccountId=@Acc AND SourceType='OwnerContribution' ORDER BY GenericCashTransactionId DESC;
EXEC dbo.spGenericCashTransaction_Reverse @GenericCashTransactionId=@Txn, @FarmId=@Farm, @Reason=N'smoke reverse';
SELECT @Bal = CurrentBalance FROM dbo.GenericCashAccounts WHERE GenericCashAccountId=@Acc;
IF @Bal <> 100 THROW 50004, 'FAIL: balance after reversal should be 100', 1;

-- 5. Reconcile to an actual count of 120 -> posts +20 adjustment.
EXEC dbo.spGenericCashReconciliation_Create
     @FarmId=@Farm, @GenericCashAccountId=@Acc, @ActualBalance=120, @Reason=N'count';
SELECT @Bal = CurrentBalance FROM dbo.GenericCashAccounts WHERE GenericCashAccountId=@Acc;
IF @Bal <> 120 THROW 50005, 'FAIL: balance after reconciliation should be 120', 1;

-- 6. Ledger SUM(approved) must equal stored CurrentBalance.
SELECT @Ledger = SUM(Amount) FROM dbo.GenericCashTransactions
WHERE GenericCashAccountId=@Acc AND FarmId=@Farm AND Status='Approved';
IF @Ledger <> @Bal THROW 50006, 'FAIL: ledger sum does not equal current balance', 1;

-- 7. Multi-allocation across two accounts.
EXEC dbo.spGenericCashAccount_Insert @FarmId=@Farm, @AccountName=N'Smoke MoMo', @AccountType=N'MoMoWallet';
SELECT @Acc2 = GenericCashAccountId FROM dbo.GenericCashAccounts WHERE FarmId=@Farm AND AccountName=N'Smoke MoMo';
DECLARE @Json NVARCHAR(MAX) =
  N'[{"PaymentMethod":"Cash","Amount":60,"GenericCashAccountId":' + CAST(@Acc AS NVARCHAR(10)) + N'},' +
  N' {"PaymentMethod":"MoMo","Amount":40,"GenericCashAccountId":' + CAST(@Acc2 AS NVARCHAR(10)) + N'}]';
EXEC dbo.spGenericCashAllocations_Post
     @FarmId=@Farm, @SourceType=N'Sale', @SourceId=999001, @Direction=N'CashIn', @AllocationsJson=@Json;
IF (SELECT COUNT(*) FROM dbo.GenericCashPaymentAllocations WHERE FarmId=@Farm AND SourceId=999001) <> 2
    THROW 50007, 'FAIL: expected 2 allocation rows', 1;

PRINT '== ALL CASH SMOKE ASSERTIONS PASSED ==';

-- Always roll back: this is a non-destructive smoke test.
ROLLBACK TRAN;
