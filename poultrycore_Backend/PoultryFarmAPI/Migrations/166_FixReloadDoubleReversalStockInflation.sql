/* ============================================================================
   166_FixReloadDoubleReversalStockInflation.sql

   Bug (prod, 2026-07-17, Great Favour water co.): "This stock value is
   incorrect." The daily closing showed Closing stock = 6371 with produced 0 /
   sold 277, and the number never tracked daily flows.

   Root cause: spWaterVehicleLoading_Reload (migrations 068 -> 120 -> 122)
   reverses a loading's LoadOut by posting a +Adjust for EVERY LoadOut row whose
   note matches the loading — and excludes nothing already reversed. So each
   repeated reload re-reverses LoadOuts a PRIOR reload already cancelled, dumping
   extra +Adjust into stock. For Great Favour that accumulated to ~+6,844 phantom
   bags (44 reverse-Adjusts vs 23 reload-LoadOuts), i.e. almost the entire 6371.
   Secondary defect: the prefix match `Note LIKE 'Vehicle loading #<id>%'` also
   leaks into #<id>0, #<id>1 … loadings (no digit boundary).

   Fix: reverse the loading's OUTSTANDING NET LoadOut effect exactly once. Sum,
   per product, this loading's own LoadOut rows AND its prior reload-reversal
   Adjusts, then post a SINGLE balancing Adjust so the loading's net stock effect
   returns to zero before the new LoadOut is re-applied. Idempotent across any
   number of reloads (a second reload sums to 0 and posts nothing). LoadReturnIn
   (real driver returns) is deliberately excluded — those are genuine stock. The
   [^0-9] boundary stops #12 from matching #120.

   NOTE: this stops NEW inflation. Historical phantom stock already in the ledger
   is corrected separately (see 166b_DataCorrection_GreatFavour_Stock.sql), which
   must be run with the owner's confirmed physical count.

   Everything else in this SP is carried over verbatim from migration 122.
   Idempotent (CREATE OR ALTER).
   ============================================================================ */

SET NOCOUNT ON; SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterVehicleLoading_Reload
    @WaterVehicleLoadingId INT,
    @FarmId                NVARCHAR(450),
    @WaterDriverId         INT           = NULL,
    @WaterVehicleId        INT           = NULL,
    @WaterRouteId          INT           = NULL,
    @LoadDate              DATETIME2     = NULL,
    @OpeningCashWithDriver DECIMAL(14,2) = 0,
    @Notes                 NVARCHAR(1000)= NULL,
    @ItemsJson             NVARCHAR(MAX) = NULL,
    @UpdatedBy             NVARCHAR(450) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(30);
    SELECT @Status = Status FROM dbo.WaterVehicleLoadings
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;

    IF @Status IS NULL
    BEGIN RAISERROR('Loading %d not found.', 16, 1, @WaterVehicleLoadingId); RETURN; END
    IF @Status NOT IN ('Draft', 'Loaded')
    BEGIN RAISERROR('Loading cannot be edited from status %s. Reverse reconciliation first.', 16, 1, @Status); RETURN; END

    BEGIN TRANSACTION;

    -- Reverse this loading's OUTSTANDING net LoadOut effect, exactly once.
    -- (See file header for the double-reversal bug this replaces.) Sum, per
    -- product, the loading's own LoadOut rows plus its prior reload-reversal
    -- Adjusts, then post one balancing Adjust so the net returns to zero.
    INSERT INTO dbo.WaterStockTransactions
        (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
    SELECT @FarmId, x.WaterProductId, 'Adjust', -x.NetQty, 0, NULL,
           CONCAT('Reload — reverse for loading #', @WaterVehicleLoadingId),
           @UpdatedBy
    FROM (
        SELECT WaterProductId, SUM(CAST(Quantity AS INT)) AS NetQty
        FROM   dbo.WaterStockTransactions
        WHERE  FarmId = @FarmId
          AND (
                (TxnType = 'LoadOut'
                 AND (Note LIKE CONCAT('Vehicle loading #', @WaterVehicleLoadingId, '[^0-9]%')
                      OR Note = CONCAT('Vehicle loading #', @WaterVehicleLoadingId)))
             OR (TxnType = 'Adjust'
                 AND Note = CONCAT('Reload — reverse for loading #', @WaterVehicleLoadingId))
              )
        GROUP BY WaterProductId
    ) x
    WHERE x.NetQty <> 0;

    -- Header (NULL coalesces to existing).
    UPDATE dbo.WaterVehicleLoadings
    SET    WaterDriverId         = ISNULL(@WaterDriverId, WaterDriverId),
           WaterVehicleId        = ISNULL(@WaterVehicleId, WaterVehicleId),
           WaterRouteId          = ISNULL(@WaterRouteId, WaterRouteId),
           LoadDate              = ISNULL(@LoadDate, LoadDate),
           OpeningCashWithDriver = ISNULL(@OpeningCashWithDriver, OpeningCashWithDriver),
           Notes                 = ISNULL(@Notes, Notes),
           UpdatedAt             = SYSUTCDATETIME()
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;

    IF @ItemsJson IS NOT NULL AND LEN(@ItemsJson) > 2
    BEGIN
        DELETE FROM dbo.WaterVehicleLoadingItems
        WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId;

        INSERT INTO dbo.WaterVehicleLoadingItems
            (WaterVehicleLoadingId, WaterProductId, BagsLoaded, SachetsPerBag, UnitPrice, Notes)
        SELECT @WaterVehicleLoadingId, j.WaterProductId, ISNULL(j.BagsLoaded, 0),
               ISNULL(j.SachetsPerBag, 30), j.UnitPrice, j.Notes
        FROM OPENJSON(@ItemsJson)
        WITH (
            WaterProductId INT             '$.waterProductId',
            BagsLoaded     INT             '$.bagsLoaded',
            SachetsPerBag  INT             '$.sachetsPerBag',
            UnitPrice      DECIMAL(14,2)   '$.unitPrice',
            Notes          NVARCHAR(500)   '$.notes'
        ) j
        WHERE j.WaterProductId IS NOT NULL;

        -- Re-sync the singular header columns from the new items (migration 120).
        DECLARE @HBags INT, @HProd INT, @HPrice DECIMAL(14,2), @HSachets INT;
        SELECT @HBags = ISNULL(SUM(BagsLoaded), 0)
        FROM   dbo.WaterVehicleLoadingItems WHERE WaterVehicleLoadingId = @WaterVehicleLoadingId;
        SELECT TOP 1 @HProd = WaterProductId, @HPrice = UnitPrice, @HSachets = SachetsPerBag
        FROM   dbo.WaterVehicleLoadingItems WHERE WaterVehicleLoadingId = @WaterVehicleLoadingId
        ORDER  BY WaterVehicleLoadingItemId;

        UPDATE dbo.WaterVehicleLoadings
        SET    BagsLoaded                 = @HBags,
               WaterProductId             = ISNULL(@HProd, WaterProductId),
               ExpectedSellingPricePerBag = ISNULL(@HPrice, ExpectedSellingPricePerBag),
               SachetsPerBag              = ISNULL(@HSachets, SachetsPerBag),
               UpdatedAt                  = SYSUTCDATETIME()
        WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;

        -- (122) keep any open (Draft) driver return's loaded snapshot in step
        -- with the corrected load. Draft only — posted returns must not change.
        UPDATE dri
        SET    dri.BagsLoaded = ni.BagsLoaded,
               dri.UnitPrice  = ni.UnitPrice,
               dri.UpdatedAt  = SYSUTCDATETIME()
        FROM   dbo.WaterDriverReturnItems dri
        JOIN   dbo.WaterDriverReturns dr ON dr.WaterDriverReturnId = dri.WaterDriverReturnId
        JOIN   dbo.WaterVehicleLoadingItems ni
               ON ni.WaterVehicleLoadingId = @WaterVehicleLoadingId AND ni.WaterProductId = dri.WaterProductId
        WHERE  dr.WaterVehicleLoadingId = @WaterVehicleLoadingId
          AND  dr.FarmId = @FarmId
          AND  dr.Status = 'Draft';

        -- Re-apply LoadOut for the new lines.
        INSERT INTO dbo.WaterStockTransactions
            (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
        SELECT @FarmId, i.WaterProductId, 'LoadOut', -i.BagsLoaded, i.UnitPrice, NULL,
               CONCAT('Vehicle loading #', @WaterVehicleLoadingId, ' (reload)'),
               @UpdatedBy
        FROM   dbo.WaterVehicleLoadingItems i
        WHERE  i.WaterVehicleLoadingId = @WaterVehicleLoadingId;
    END

    COMMIT TRANSACTION;

    SELECT WaterVehicleLoadingId, Status FROM dbo.WaterVehicleLoadings
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;
END
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterVehicleLoading_Reload TO [Techretainer];
GO

PRINT '166_FixReloadDoubleReversalStockInflation.sql complete.';
GO
