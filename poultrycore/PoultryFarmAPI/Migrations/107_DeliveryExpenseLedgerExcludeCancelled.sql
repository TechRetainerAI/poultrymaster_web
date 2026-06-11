-- =============================================================================
-- 107_DeliveryExpenseLedgerExcludeCancelled.sql  (Feedback, James 2026-06-11:
--   "fix the old data" — follow-up to 106.)
--
-- When a driver return is reversed, a NEW return is created for the same loading
-- and the operator re-enters its delivery expenses there. The OLD return is
-- marked Cancelled, but its delivery-expense rows are left behind. Those stale
-- rows are correctly EXCLUDED from the daily closing and P&L (which only count
-- Draft/Approved returns), but spWaterDeliveryExpense_ListAll had no status
-- filter, so the Expenses ledger still listed them — over-stating the ledger and
-- pointing a Source link at a delivery where the expense can't be found (its copy
-- lives on the active return instead).
--
-- Fix: the ledger SP now excludes expenses whose return is Cancelled, so it shows
-- only live delivery expenses and matches the financial totals. (Expenses with no
-- linked return at all are still shown.) Idempotent; no schema change.
--
-- NOTE: this is a display/consistency fix — the stale rows remain in the table
-- but are no longer surfaced or counted. They can be hard-deleted separately if
-- desired; this migration intentionally does NOT delete data.
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
      -- Skip expenses stranded on a reversed/cancelled return (their live copy is
      -- on the active return); keep expenses with no linked return at all.
      AND  (dr.WaterDriverReturnId IS NULL OR dr.Status <> 'Cancelled')
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

PRINT '107_DeliveryExpenseLedgerExcludeCancelled.sql complete.';
GO
