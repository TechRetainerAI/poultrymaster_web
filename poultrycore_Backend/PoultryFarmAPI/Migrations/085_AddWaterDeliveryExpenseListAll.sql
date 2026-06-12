-- =============================================================================
-- Migration 085: Unified expense ledger — list all WaterDeliveryExpenses
-- =============================================================================
-- "James 2026-06-02": Step 4 delivery expenses on a driver-return form were
-- being persisted to dbo.WaterDeliveryExpenses only, so they never appeared
-- on the /water-expenses page (which reads dbo.WaterExpenses). Adding a
-- list-all SP so the frontend can UNION both tables client-side and show a
-- single Expenses ledger with a Source column ("Direct" / "Delivery #N").
--
-- This is non-destructive: no schema changes, just a new read SP. The
-- frontend keeps using spWaterExpense_List for direct entries and now also
-- calls spWaterDeliveryExpense_ListAll for delivery entries.
--
-- The SP joins WaterDriverReturns + WaterVehicleLoadings + WaterDrivers +
-- WaterVehicles so the frontend can render a clickable "Source" cell without
-- a second round-trip.
-- =============================================================================

SET NOCOUNT ON;

IF OBJECT_ID('dbo.spWaterDeliveryExpense_ListAll', 'P') IS NOT NULL
    DROP PROCEDURE dbo.spWaterDeliveryExpense_ListAll;
GO

CREATE PROCEDURE dbo.spWaterDeliveryExpense_ListAll
    @FarmId    NVARCHAR(450),
    @FromDate  DATETIME2 = NULL,
    @ToDate    DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        wde.WaterDeliveryExpenseId,
        wde.FarmId,
        wde.WaterDriverReturnId,
        wde.WaterVehicleLoadingId,
        wde.ExpenseCategory,
        wde.Amount,
        wde.Description,
        wde.IsApproved,
        wde.Notes,
        wde.CreatedBy,
        wde.CreatedAt,
        wde.UpdatedAt,
        -- Driver-return context for the unified Expenses list:
        dr.ReturnDate    AS ReturnDate,
        dr.Status        AS ReturnStatus,
        d.DriverName     AS DriverName,
        v.VehicleName    AS VehicleNumber
    FROM   dbo.WaterDeliveryExpenses wde
    LEFT JOIN dbo.WaterDriverReturns   dr ON dr.WaterDriverReturnId   = wde.WaterDriverReturnId
    LEFT JOIN dbo.WaterVehicleLoadings vl ON vl.WaterVehicleLoadingId = COALESCE(wde.WaterVehicleLoadingId, dr.WaterVehicleLoadingId)
    LEFT JOIN dbo.WaterDrivers         d  ON d.WaterDriverId          = vl.WaterDriverId
    LEFT JOIN dbo.WaterVehicles        v  ON v.WaterVehicleId         = vl.WaterVehicleId
    WHERE  wde.FarmId = @FarmId
      AND  (@FromDate IS NULL OR COALESCE(dr.ReturnDate, wde.CreatedAt) >= @FromDate)
      AND  (@ToDate   IS NULL OR COALESCE(dr.ReturnDate, wde.CreatedAt) <  DATEADD(DAY, 1, @ToDate))
    ORDER BY COALESCE(dr.ReturnDate, wde.CreatedAt) DESC, wde.WaterDeliveryExpenseId DESC;
END
GO

-- Grant on PoultryAppRole (the runtime login). Idempotent: only grant if the
-- role exists in this database (dev/prod parity differs here historically).
IF DATABASE_PRINCIPAL_ID('PoultryAppRole') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterDeliveryExpense_ListAll TO PoultryAppRole;
END
GO

PRINT 'Migration 085 applied: spWaterDeliveryExpense_ListAll created.';
