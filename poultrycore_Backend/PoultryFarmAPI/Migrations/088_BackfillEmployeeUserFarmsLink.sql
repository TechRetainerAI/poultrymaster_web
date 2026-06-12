-- =============================================================================
-- 088_BackfillEmployeeUserFarmsLink.sql
--
-- Heals staff employees that were created WITHOUT a UserFarms membership row.
--
-- Root cause: AdminService.CreateEmployeeAsync stamped AspNetUsers.FarmId on the
-- new staff user but never inserted into dbo.UserFarms. /Companies/mine
-- (spCompany_GetByUserId, migration 054) joins UserFarms, so such an employee
-- resolved to NO company at login and was dumped on the Poultry default
-- dashboard — e.g. a Water-company employee landing on the poultry "farm".
--
-- The code fix (AdminService now calls ICompanyDAL.AddMemberAsync) prevents this
-- for NEW employees. Migration 086 already backfilled accounts that existed at
-- the time, but every employee created between 086 and the code fix is still
-- missing its link. This migration re-runs the same heal, but assigns the
-- correct Role: 'Staff' for staff users, 'Admin' otherwise.
--
-- Idempotent: NOT EXISTS guard means re-running inserts nothing. Safe to run
-- after 086. Only inserts links the data already implies (AspNetUsers.FarmId
-- names a real Farms row); touches no existing UserFarms rows and deletes
-- nothing.
-- =============================================================================

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

DECLARE @backfilled INT;

INSERT INTO dbo.UserFarms (UserId, FarmId, Role)
SELECT u.Id,
       u.FarmId,
       CASE WHEN u.IsStaff = 1 THEN 'Staff' ELSE 'Admin' END
FROM   dbo.AspNetUsers u
INNER  JOIN dbo.Farms f ON f.FarmId = u.FarmId
WHERE  u.FarmId IS NOT NULL
  AND  LTRIM(RTRIM(u.FarmId)) <> ''
  AND  NOT EXISTS (
       SELECT 1 FROM dbo.UserFarms uf
       WHERE  uf.UserId = u.Id AND uf.FarmId = u.FarmId
  );

SET @backfilled = @@ROWCOUNT;
PRINT CONCAT('088: backfilled ', @backfilled, ' missing UserFarms link(s) for existing employees.');
GO
