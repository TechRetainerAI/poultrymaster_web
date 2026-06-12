-- =============================================================================
-- 106_DeliveryExpenseLoadingIdForSourceLink.sql  (Feedback, James 2026-06-11:
--   "an expense's Source link opens a different driver return — the expense
--    isn't in the one linked." Expense date said 06/10 but the link opened a
--    06/09 return.)
--
-- Root cause: the /water-driver-returns/[id] page resolves :id as a
-- WaterVehicleLoadingId (the delivery), but the Expenses ledger linked by
-- WaterDriverReturnId — so the page opened whatever *loading* shared that
-- number (an unrelated delivery on a different date). The frontend now links by
-- WaterVehicleLoadingId.
--
-- For that link to always resolve, the ledger row must carry the loading id of
-- the RETURN that holds the expense. wde.WaterVehicleLoadingId is populated on
-- newer rows but can be NULL on older ones. This recreation of
-- spWaterDeliveryExpense_ListAll returns COALESCE(wde.WaterVehicleLoadingId,
-- dr.WaterVehicleLoadingId) so the loading id is always present. No other
-- columns change. Idempotent.
-- =============================================================================

SET NOCOUNT ON;
GO

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
        -- Always expose the loading id of the return that holds this expense, so
        -- the Source link (which targets a WaterVehicleLoadingId) resolves.
        WaterVehicleLoadingId = COALESCE(wde.WaterVehicleLoadingId, dr.WaterVehicleLoadingId),
        wde.ExpenseCategory,
        wde.Amount,
        wde.Description,
        wde.IsApproved,
        wde.Notes,
        wde.CreatedBy,
        wde.CreatedAt,
        wde.UpdatedAt,
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

IF DATABASE_PRINCIPAL_ID('PoultryAppRole') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spWaterDeliveryExpense_ListAll TO PoultryAppRole;
END
GO

PRINT '106_DeliveryExpenseLoadingIdForSourceLink.sql complete.';
GO
