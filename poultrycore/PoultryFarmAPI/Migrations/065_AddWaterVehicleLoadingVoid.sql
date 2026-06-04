/* =============================================================================
   065_AddWaterVehicleLoadingVoid.sql

   James reported the X icon on a Loaded delivery row "doesn't work". Reason:
   spWaterVehicleLoading_Cancel (migration 041) only fires for Draft loadings.
   Since the frontend auto-approves on create (load-and-go flow), every
   loading is Loaded by the time the user sees the X, so Cancel silently
   no-ops at the backend and the UI shows nothing happened.

   This migration adds spWaterVehicleLoading_Void — a safer "undo" that:
     * Allows Draft *or* Loaded (anything not yet Reconciled / Cancelled).
     * For Loaded, writes one +bags Adjust stock txn per item to reverse the
       LoadOut. We use 'Adjust' (not 'LoadReturnIn') so the audit log makes
       the reversal obvious.
     * Refuses when a non-cancelled WaterDriverReturn already references the
       loading — by then sales/payments/stock derivatives may have been
       created and the void can't be clean.
     * Marks the loading Cancelled + IsDeleted = 1.
   ============================================================================= */

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE dbo.spWaterVehicleLoading_Void
    @WaterVehicleLoadingId INT,
    @FarmId                NVARCHAR(450),
    @VoidedBy              NVARCHAR(450) = NULL,
    @Reason                NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Status NVARCHAR(20), @VehicleId INT;
    SELECT @Status = Status, @VehicleId = WaterVehicleId
    FROM   dbo.WaterVehicleLoadings
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId AND IsDeleted = 0;

    IF @Status IS NULL
    BEGIN RAISERROR('Loading %d not found or already deleted.', 16, 1, @WaterVehicleLoadingId); RETURN; END

    IF @Status = 'Cancelled'
    BEGIN RAISERROR('Loading is already cancelled.', 16, 1); RETURN; END

    IF @Status = 'Reconciled'
    BEGIN
        RAISERROR('Cannot void a Reconciled loading — the driver has already returned. Cancel the driver return first.', 16, 1);
        RETURN;
    END

    -- Block if a non-cancelled return exists. Returns might have generated
    -- sales/payments/stock movements that can't be cleanly reversed by a
    -- simple +bags adjust.
    IF EXISTS (
        SELECT 1 FROM dbo.WaterDriverReturns
        WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId
          AND  FarmId = @FarmId
          AND  Status <> 'Cancelled'
    )
    BEGIN
        RAISERROR('Cannot void: a driver return is already recorded against this loading. Cancel the return first.', 16, 1);
        RETURN;
    END

    BEGIN TRANSACTION;

    -- For Loaded loadings, write a +bags Adjust per item to reverse LoadOut.
    -- For Draft loadings, no stock moved yet so nothing to reverse.
    IF @Status = 'Loaded'
    BEGIN
        INSERT INTO dbo.WaterStockTransactions
            (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
        SELECT @FarmId, li.WaterProductId, 'Adjust', li.BagsLoaded, NULL, NULL,
               CONCAT('Void loading #', @WaterVehicleLoadingId,
                      CASE WHEN @Reason IS NULL THEN N''
                           ELSE CONCAT(N' — ', @Reason) END),
               @VoidedBy
        FROM   dbo.WaterVehicleLoadingItems li
        WHERE  li.WaterVehicleLoadingId = @WaterVehicleLoadingId AND li.BagsLoaded > 0;

        -- Legacy loadings created before migration 064 have no items rows.
        -- Fall back to header values so they can still be voided.
        IF NOT EXISTS (SELECT 1 FROM dbo.WaterVehicleLoadingItems WHERE WaterVehicleLoadingId = @WaterVehicleLoadingId)
        BEGIN
            DECLARE @ProductId INT, @BagsLoaded INT;
            SELECT @ProductId = WaterProductId, @BagsLoaded = BagsLoaded
            FROM   dbo.WaterVehicleLoadings
            WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;

            IF (@BagsLoaded > 0)
            BEGIN
                INSERT INTO dbo.WaterStockTransactions
                    (FarmId, WaterProductId, TxnType, Quantity, UnitCost, RelatedSaleId, Note, CreatedBy)
                VALUES (@FarmId, @ProductId, 'Adjust', @BagsLoaded, NULL, NULL,
                        CONCAT('Void loading #', @WaterVehicleLoadingId,
                               CASE WHEN @Reason IS NULL THEN N''
                                    ELSE CONCAT(N' — ', @Reason) END),
                        @VoidedBy);
            END
        END
    END

    UPDATE dbo.WaterVehicleLoadings
    SET    Status = 'Cancelled', IsDeleted = 1, UpdatedAt = SYSUTCDATETIME(),
           Notes = ISNULL(Notes, N'') +
                   CASE WHEN @Reason IS NULL THEN N' [Voided]'
                        ELSE CONCAT(N' [Voided: ', @Reason, N']') END
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;

    COMMIT TRANSACTION;

    SELECT WaterVehicleLoadingId, Status, IsDeleted
    FROM   dbo.WaterVehicleLoadings
    WHERE  WaterVehicleLoadingId = @WaterVehicleLoadingId AND FarmId = @FarmId;
END
GO

IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'PoultryAppRole' AND type = 'R')
BEGIN
    GRANT EXECUTE ON dbo.spWaterVehicleLoading_Void TO PoultryAppRole;
END
GO

PRINT '065_AddWaterVehicleLoadingVoid.sql complete.';
GO
