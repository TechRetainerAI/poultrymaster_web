-- =============================================================================
-- 096_GrantClosingReopenLinkSupersededExecute.sql
--
-- BUG ("she cannot do the closing"): the app connects as [Techretainer], but
-- spWaterDailyClosing_Reopen and spWaterDailyClosing_LinkSuperseded were never
-- granted EXECUTE to that login (the other 9 closing SPs were). So reopening /
-- recreating a daily closing failed with a permission error in the app, even
-- though the SPs ran fine under an admin login. Same class of bug as the
-- currency-settings grant gap (mig 089).
--
-- Grants EXECUTE on the two missing closing SPs. Idempotent.
-- =============================================================================

SET NOCOUNT ON;
GO

IF DATABASE_PRINCIPAL_ID(N'Techretainer') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.spWaterDailyClosing_Reopen', 'P') IS NOT NULL
        GRANT EXECUTE ON dbo.spWaterDailyClosing_Reopen TO [Techretainer];
    IF OBJECT_ID('dbo.spWaterDailyClosing_LinkSuperseded', 'P') IS NOT NULL
        GRANT EXECUTE ON dbo.spWaterDailyClosing_LinkSuperseded TO [Techretainer];
END
GO

IF DATABASE_PRINCIPAL_ID(N'PoultryAppRole') IS NOT NULL
BEGIN
    IF OBJECT_ID('dbo.spWaterDailyClosing_Reopen', 'P') IS NOT NULL
        GRANT EXECUTE ON dbo.spWaterDailyClosing_Reopen TO PoultryAppRole;
    IF OBJECT_ID('dbo.spWaterDailyClosing_LinkSuperseded', 'P') IS NOT NULL
        GRANT EXECUTE ON dbo.spWaterDailyClosing_LinkSuperseded TO PoultryAppRole;
END
GO
