-- =============================================================================
-- 192_AspNetUsersFarmIdNullable.sql
-- Company soft-delete (167) sets dbo.AspNetUsers.FarmId = NULL to move a member
-- off a deleted company onto a neutral active company (the Business Office).
-- But AspNetUsers.FarmId was created NOT NULL, so "Delete company" failed with:
--   "Cannot insert the value NULL into column 'FarmId' ... column does not allow
--    nulls. UPDATE fails."
--
-- FarmId is only the legacy "active/default company" pointer — real membership
-- lives in dbo.UserFarms — so it should be nullable. This makes it nullable.
-- Metadata-only change (no table rewrite). Idempotent.
-- =============================================================================
SET NOCOUNT ON;
GO

IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('dbo.AspNetUsers') AND name = 'FarmId' AND is_nullable = 0)
BEGIN
    ALTER TABLE dbo.AspNetUsers ALTER COLUMN FarmId NVARCHAR(450) NULL;
    PRINT '192: dbo.AspNetUsers.FarmId is now nullable.';
END
ELSE
    PRINT '192: dbo.AspNetUsers.FarmId already nullable (no change).';
GO

PRINT '192_AspNetUsersFarmIdNullable.sql complete.';
GO
