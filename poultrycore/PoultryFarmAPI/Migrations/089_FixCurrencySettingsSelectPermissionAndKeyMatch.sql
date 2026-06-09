-- =============================================================================
-- 089_FixCurrencySettingsSelectPermissionAndKeyMatch.sql
--
-- Fixes two bugs in the Water "Currency settings" save (PUT /api/Water/farm-settings/currency):
--
-- BUG 1 — SELECT permission denied on 'Farms' (the reported 500):
--   WaterFarmSettingsService.GetAsync ran a *direct inline* SELECT on dbo.Farms.
--   Farms is owned by the Login API; the Farm API runtime login (Techretainer /
--   PoultryAppRole) only has EXECUTE on dbo SPs and relies on ownership chaining
--   for table access. A raw inline SELECT is NOT covered by ownership chaining,
--   so prod (PoultryMaster), where the login has no direct SELECT on Farms,
--   returned "SELECT permission was denied on the object 'Farms'".
--   Fix: read through a stored procedure (spCompany_GetCurrency) so EXECUTE +
--   ownership chaining is sufficient — no direct table grant required.
--
-- BUG 2 — currency never actually saved (silent, both dev and prod):
--   spCompany_UpdateCurrency matched WHERE Id = @FarmId, but the frontend stores
--   the legacy Farms.FarmId column value in localStorage (Id and FarmId are
--   different GUIDs). So the UPDATE matched 0 rows and the setting never
--   persisted. Fix: match on (Id = @FarmId OR FarmId = @FarmId), same as the
--   service's original inline read did.
--
-- Idempotent: CREATE OR ALTER + guarded GRANTs. Safe to re-run.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- 1. Update: match by Id OR the legacy FarmId column, then return the row.
CREATE OR ALTER PROCEDURE dbo.spCompany_UpdateCurrency
    @FarmId             NVARCHAR(450),
    @CurrencyCode       NVARCHAR(10),
    @CurrencySymbol     NVARCHAR(10),
    @ShowCurrencySymbol BIT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.Farms
    SET    CurrencyCode       = ISNULL(NULLIF(@CurrencyCode,   N''), CurrencyCode),
           CurrencySymbol     = ISNULL(NULLIF(@CurrencySymbol, N''), CurrencySymbol),
           ShowCurrencySymbol = ISNULL(@ShowCurrencySymbol, ShowCurrencySymbol),
           UpdatedAt          = SYSUTCDATETIME()
    WHERE  Id = @FarmId OR FarmId = @FarmId;

    SELECT TOP 1 ISNULL(FarmId, Id)               AS Id,
                 Name,
                 ISNULL(CurrencyCode,   N'GHS')   AS CurrencyCode,
                 ISNULL(CurrencySymbol, N'GHC')   AS CurrencySymbol,
                 ISNULL(ShowCurrencySymbol, 1)    AS ShowCurrencySymbol
    FROM   dbo.Farms
    WHERE  Id = @FarmId OR FarmId = @FarmId;
END
GO

-- 2. New read SP so the service no longer needs a direct SELECT on Farms.
CREATE OR ALTER PROCEDURE dbo.spCompany_GetCurrency
    @FarmId NVARCHAR(450)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP 1 ISNULL(FarmId, Id)               AS Id,
                 Name,
                 ISNULL(CurrencyCode,   N'GHS')   AS CurrencyCode,
                 ISNULL(CurrencySymbol, N'GHC')   AS CurrencySymbol,
                 ISNULL(ShowCurrencySymbol, 1)    AS ShowCurrencySymbol
    FROM   dbo.Farms
    WHERE  Id = @FarmId OR FarmId = @FarmId;
END
GO

-- 3. Grant EXECUTE to the runtime principals (guarded — only if they exist).
IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spCompany_UpdateCurrency TO [Techretainer];
    GRANT EXECUTE ON dbo.spCompany_GetCurrency    TO [Techretainer];
    PRINT '089: granted EXECUTE on currency SPs to Techretainer.';
END
GO
IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
BEGIN
    GRANT EXECUTE ON dbo.spCompany_UpdateCurrency TO PoultryAppRole;
    GRANT EXECUTE ON dbo.spCompany_GetCurrency    TO PoultryAppRole;
    PRINT '089: granted EXECUTE on currency SPs to PoultryAppRole.';
END
GO
