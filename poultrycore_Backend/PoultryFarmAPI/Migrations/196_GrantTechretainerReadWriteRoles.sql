-- =============================================================================
-- 196_GrantTechretainerReadWriteRoles.sql
-- Prod bug: PUT /Poultry/raw-material-purchases/{id} failed on PROD (PoultryMaster)
-- with "SELECT permission was denied on the object 'PoultryRawMaterialPurchases'".
--
-- Root cause: the runtime app user `Techretainer` on PROD had EXECUTE on the SPs
-- but was a member of NO database role, so it could not read/write tables directly.
-- Several service methods use raw ADO.NET SQL instead of stored procedures, e.g.:
--   * PoultryInventoryServices.GuardNotFeedProductionLotAsync →
--       SELECT SourceFeedProductionBatchId FROM dbo.PoultryRawMaterialPurchases
--     (called by the Update / Delete / PayBalance paths)
--   * the in-app chat → raw INSERT/UPDATE into dbo.ChatThreads / ChatParticipants /
--     ChatMessages
-- Ownership chaining does NOT cover these (they don't run inside an SP), so the
-- caller needs direct table permission.
--
-- DEV's `Techretainer` is in db_datareader + db_datawriter (which is exactly why
-- this worked on dev but not prod). This migration aligns PROD with DEV.
--
-- Idempotent. Must be run by a db_owner (the `sqlserver` admin login), NOT by the
-- app user itself.
-- =============================================================================
SET NOCOUNT ON;
GO

IF DATABASE_PRINCIPAL_ID('Techretainer') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.database_role_members
                   WHERE role_principal_id   = DATABASE_PRINCIPAL_ID('db_datareader')
                     AND member_principal_id = DATABASE_PRINCIPAL_ID('Techretainer'))
    BEGIN
        ALTER ROLE db_datareader ADD MEMBER [Techretainer];
        PRINT '196: added Techretainer to db_datareader.';
    END
    ELSE PRINT '196: Techretainer already in db_datareader (no change).';

    IF NOT EXISTS (SELECT 1 FROM sys.database_role_members
                   WHERE role_principal_id   = DATABASE_PRINCIPAL_ID('db_datawriter')
                     AND member_principal_id = DATABASE_PRINCIPAL_ID('Techretainer'))
    BEGIN
        ALTER ROLE db_datawriter ADD MEMBER [Techretainer];
        PRINT '196: added Techretainer to db_datawriter.';
    END
    ELSE PRINT '196: Techretainer already in db_datawriter (no change).';
END
ELSE
    PRINT '196: Techretainer principal not found (skipped).';
GO

PRINT '196_GrantTechretainerReadWriteRoles.sql complete.';
GO
