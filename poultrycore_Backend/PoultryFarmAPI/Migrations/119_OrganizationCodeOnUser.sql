/* ============================================================================
   119_OrganizationCodeOnUser.sql

   Prompt 3: Organization Code based login. Each owner's Business Office gets a
   unique, human-readable OrganizationCode (e.g. EVANSBIZ) chosen at signup.
   The owner's account IS the organization in the current model, so the code
   lives on AspNetUsers next to BusinessOfficeName (migration 118).

   Stored UPPERCASE; the default CI collation + a unique filtered index makes it
   case-insensitively unique across the platform. Additive + idempotent.
   ============================================================================ */

IF COL_LENGTH('dbo.AspNetUsers', 'OrganizationCode') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD OrganizationCode NVARCHAR(30) NULL;
GO
IF COL_LENGTH('dbo.AspNetUsers', 'IsOrgCodeActive') IS NULL
    ALTER TABLE dbo.AspNetUsers ADD IsOrgCodeActive BIT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_AspNetUsers_OrganizationCode'
                 AND object_id = OBJECT_ID('dbo.AspNetUsers'))
    CREATE UNIQUE INDEX UX_AspNetUsers_OrganizationCode
        ON dbo.AspNetUsers (OrganizationCode)
        WHERE OrganizationCode IS NOT NULL;
GO

PRINT '119_OrganizationCodeOnUser.sql complete.';
GO
