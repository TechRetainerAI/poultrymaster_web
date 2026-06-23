/* ============================================================================
   118_BusinessOfficeOnUser.sql

   Prompt 2: persist the owner's "Business Office" on their account so the HQ
   name (and basic settings) survive across devices instead of living only in
   the browser. The owner's user IS the organization in the current model, so
   these columns hang off AspNetUsers — no new Organization table required yet.

   Additive, idempotent. The Login API reads/writes these via EF (ApplicationUser
   gets matching properties); existing rows simply have NULLs.
   ============================================================================ */

IF COL_LENGTH('dbo.AspNetUsers', 'BusinessOfficeName') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD BusinessOfficeName NVARCHAR(200) NULL;
GO
IF COL_LENGTH('dbo.AspNetUsers', 'BusinessOfficeCurrency') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD BusinessOfficeCurrency NVARCHAR(10) NULL;
GO
IF COL_LENGTH('dbo.AspNetUsers', 'BusinessOfficeCountry') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD BusinessOfficeCountry NVARCHAR(100) NULL;
GO

PRINT '118_BusinessOfficeOnUser.sql complete.';
GO
