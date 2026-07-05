/* ============================================================================
   120_ReloadSyncsLoadingHeader.sql

   Bug (prod, 2026-06-24): "I loaded the Motor King with 380 bags instead of 320.
   I came to reload but it still shows 380."

   Root cause: spWaterVehicleLoading_Reload (migration 068) replaces the loading
   ITEMS and re-applies LoadOut stock, but its header UPDATE only touches
   driver/vehicle/route/date/cash/notes — it never recomputes the header
   columns BagsLoaded / WaterProductId / ExpectedSellingPricePerBag. The
   deliveries card reads those header columns, so a corrected reload still shows
   the old quantity (and the persisted ExpectedCash stays wrong too).

   Fix: when @ItemsJson is supplied, after replacing the items re-sync the header
   from the new items — identical to spWaterVehicleLoading_Insert (migration 064):
     BagsLoaded                 = SUM(items.BagsLoaded)
     WaterProductId             = first item's product
     ExpectedSellingPricePerBag = first item's unit price
   ExpectedCash is a PERSISTED computed column (BagsLoaded * price) so it
   recomputes automatically. Also carry SachetsPerBag/Notes onto the re-inserted
   items (068 dropped them).

   Idempotent (CREATE OR ALTER). Body = migration 068 + header re-sync.
   ============================================================================ */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
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

    -- Update header (NULL coalesces to existing value).
    UPDATE dbo.WaterVehicleLoadings
    SET    WaterDriverId         = ISNULL(@WaterDriverId, WaterDriverId),
           WaterVehicleId        = ISNULL(@WaterVehicleId, WaterVehicleId),
           WaterRouteId          = ISNULL(@WaterRouteId, WaterRouteId),
           LoadDate              = ISNULL(@LoadDate, LoadDate),
           OpeningCashWithDriver = ISNULL(@OpeningCashWithDriver, OpeningCashWithDriver),
           Notes                 = ISNULL(@Notes, Notes),
           UpdatedAt             = SYSUTCDATETIME()
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;

    -- Replace items + re-apply LoadOut, and RE-SYNC the header from the new
    -- items (this is the fix — the deliveries card reads the header columns).
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

        -- Re-sync the singular header columns from the new items (mirrors
        -- spWaterVehicleLoading_Insert): total bags, first product, first price.
        DECLARE @HBags INT, @HProd INT, @HPrice DECIMAL(14,2), @HSachets INT;
        SELECT @HBags = ISNULL(SUM(BagsLoaded), 0)
        FROM   dbo.WaterVehicleLoadingItems
        WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId;

        SELECT TOP 1 @HProd = WaterProductId, @HPrice = UnitPrice, @HSachets = SachetsPerBag
        FROM   dbo.WaterVehicleLoadingItems
        WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId
        ORDER  BY WaterVehicleLoadingItemId;

        UPDATE dbo.WaterVehicleLoadings
        SET    BagsLoaded                 = @HBags,
               WaterProductId             = ISNULL(@HProd, WaterProductId),
               ExpectedSellingPricePerBag = ISNULL(@HPrice, ExpectedSellingPricePerBag),
               SachetsPerBag              = ISNULL(@HSachets, SachetsPerBag),
               UpdatedAt                  = SYSUTCDATETIME()
        WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;

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

PRINT '120_ReloadSyncsLoadingHeader.sql complete.';
GO
