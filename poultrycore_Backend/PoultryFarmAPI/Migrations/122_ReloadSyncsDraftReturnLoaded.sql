/* ============================================================================
   122_ReloadSyncsDraftReturnLoaded.sql

   Bug (prod, 2026-06-24, follow-up to 120): after correcting a load 380 -> 320,
   the loading header/products now show 320 (fixed by 120), BUT the delivery's
   "Return reconciliation" still shows Loaded 380.

   Root cause: WaterDriverReturnItems.BagsLoaded is a SECOND snapshot, taken when
   the driver return was recorded against the old (380) load. Reloading the
   loading doesn't touch an already-created return.

   Fix:
   1. spWaterVehicleLoading_Reload (re-create = migration 120 body + this) also
      re-syncs BagsLoaded/UnitPrice on any DRAFT driver return for the loading,
      matched by product, to the new loading items. Draft only — approved/
      reconciled returns have already posted stock/cash and must not change.
   2. One-time data correction: bring every existing DRAFT return item's
      BagsLoaded into line with its loading's current items (fixes the records
      already stuck, e.g. James's run).

   Idempotent (CREATE OR ALTER + a safe, Draft-only UPDATE).
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

    -- Reverse existing LoadOut stock txns from this loading.
    INSERT INTO dbo.WaterStockTransactions
        (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
    SELECT FarmId, WaterProductId, 'Adjust', -Quantity, UnitCost, NULL,
           CONCAT('Reload — reverse for loading #', @WaterVehicleLoadingId),
           @UpdatedBy
    FROM   dbo.WaterStockTransactions
    WHERE  FarmId = @FarmId
      AND  TxnType = 'LoadOut'
      AND  Note LIKE CONCAT('Vehicle loading #', @WaterVehicleLoadingId, '%');

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

        -- NEW (122): keep any open (Draft) driver return's loaded snapshot in
        -- step with the corrected load, so the reconciliation shows the right
        -- "Loaded". Draft only — posted returns must not be retroactively changed.
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

/* ---- One-time correction: align existing DRAFT return loaded snapshots ---- */
UPDATE dri
SET    dri.BagsLoaded = ni.BagsLoaded,
       dri.UnitPrice  = ni.UnitPrice,
       dri.UpdatedAt  = SYSUTCDATETIME()
FROM   dbo.WaterDriverReturnItems dri
JOIN   dbo.WaterDriverReturns dr ON dr.WaterDriverReturnId = dri.WaterDriverReturnId AND dr.Status = 'Draft'
JOIN   dbo.WaterVehicleLoadingItems ni
       ON ni.WaterVehicleLoadingId = dr.WaterVehicleLoadingId AND ni.WaterProductId = dri.WaterProductId
WHERE  dri.BagsLoaded <> ni.BagsLoaded;
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
    GRANT EXECUTE ON dbo.spWaterVehicleLoading_Reload TO [Techretainer];
GO

PRINT '122_ReloadSyncsDraftReturnLoaded.sql complete.';
GO
