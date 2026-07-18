/* ============================================================================
   166b_DataCorrection_GreatFavour_Stock.sql   (PROD, one-time, ONE farm)

   Companion to 166_FixReloadDoubleReversalStockInflation.sql. Migration 166
   stops NEW phantom stock; this fixes the phantom already banked in the ledger
   for Great Favour (FarmId 288bc52b-fb9a-43c4-9316-219306e7a47c, product
   "Sachet water" #3).

   Why a manual physical count is required (not a computed number):
   the reload double-reversal corrupted the ledger so badly that the correct
   stock CANNOT be reliably reconstructed from it — two independent methods both
   returned impossible NEGATIVE stock (phantom-net ≈ -473; full reconstruction
   ≈ -1,975). Both agree the true on-hand is near zero, but neither is exact.
   So we set stock to the OWNER'S CONFIRMED PHYSICAL COUNT.

   HOW TO RUN:
     1. Get the owner's actual counted Sachet-water stock (bags) right now.
     2. Set @TruePhysicalCount below to that number.
     3. Run once. It posts a SINGLE reconciling Adjust (audit-noted) so the
        ledger sum equals the physical count. Re-running is safe (idempotent:
        a second run computes a 0 delta and posts nothing).

   Leaving @TruePhysicalCount = -1 (the sentinel) aborts without changing data.
   ============================================================================ */

SET NOCOUNT ON; SET XACT_ABORT ON;
GO

DECLARE @FarmId    NVARCHAR(450) = N'288bc52b-fb9a-43c4-9316-219306e7a47c';
DECLARE @ProductId INT           = 3;              -- Sachet water
DECLARE @TruePhysicalCount INT   = -1;             -- <<< SET to the owner's counted bags, then run

-- Current ledger stock for that product (what the closing shows today):
DECLARE @Current INT = ISNULL((
    SELECT SUM(CAST(Quantity AS INT)) FROM dbo.WaterStockTransactions
    WHERE FarmId = @FarmId AND WaterProductId = @ProductId), 0);

PRINT CONCAT('Current ledger stock for product ', @ProductId, ' = ', @Current);

IF @TruePhysicalCount < 0
BEGIN
    RAISERROR('ABORTED: set @TruePhysicalCount to the owner''s confirmed physical count (bags) first. No data changed.', 16, 1);
    RETURN;
END

DECLARE @Delta INT = @TruePhysicalCount - @Current;

IF @Delta = 0
BEGIN
    PRINT 'Ledger already equals the physical count — nothing to post.';
    RETURN;
END

INSERT INTO dbo.WaterStockTransactions
    (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
VALUES
    (@FarmId, @ProductId, 'Adjust', @Delta, 0, NULL,
     CONCAT('Stock reconciliation to physical count (', @TruePhysicalCount,
            ') — corrects reload double-reversal inflation; see migration 166.'),
     'system:166b');

PRINT CONCAT('Posted reconciling Adjust of ', @Delta, '. New ledger stock = ', @TruePhysicalCount, '.');
GO
