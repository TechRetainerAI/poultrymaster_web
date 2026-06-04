-- ============================================================
-- STEP 3: Verify prod's current state BEFORE applying any
-- migration. Read-only. Run as any login that has SELECT on
-- dbo.Farms / dbo.AspNetUsers / sys catalog views.
--
-- Connect SSMS to the prod database (not master). Paste this
-- entire block. Run. Paste the five numbered results back.
-- ============================================================

PRINT N'=== Verifying prod state at ' + CONVERT(NVARCHAR(50), SYSUTCDATETIME(), 121) + N' ===';
PRINT N'Server:   ' + @@SERVERNAME;
PRINT N'Database: ' + DB_NAME();
PRINT N'';

-- ------------------------------------------------------------
-- Q1. Does dbo.UserFarms exist? (created by migration 025)
-- NULL → 025 has not run → multi-company is broken on prod.
-- ------------------------------------------------------------
PRINT N'--- Q1: UserFarms exists? ---';
SELECT OBJECT_ID(N'dbo.UserFarms') AS UserFarms_ObjectId;

-- ------------------------------------------------------------
-- Q2. Does dbo.Farms.Type exist? (added by migration 025)
-- NULL → 025 has not run.
-- ------------------------------------------------------------
PRINT N'--- Q2: Farms.Type column length? ---';
SELECT  COL_LENGTH(N'dbo.Farms', N'Type')        AS Farms_Type_Length,
        COL_LENGTH(N'dbo.Farms', N'OwnerUserId') AS Farms_OwnerUserId_Length,
        COL_LENGTH(N'dbo.Farms', N'UpdatedAt')   AS Farms_UpdatedAt_Length,
        COL_LENGTH(N'dbo.Farms', N'Id')          AS Farms_Id_Length,
        COL_LENGTH(N'dbo.Farms', N'FarmId')      AS Farms_FarmId_Length;

-- ------------------------------------------------------------
-- Q3. How many "misplaced GUID" Farms rows exist?
-- (the symptom migration 053 fixes: Id has a GUID, FarmId='0')
-- > 0 → users were created via the buggy sp_CreateFarm.
-- ------------------------------------------------------------
PRINT N'--- Q3: misplaced Farms rows (FarmId=0, GUID-shaped Id) ---';
-- Guarded so this still runs cleanly if either column is missing.
IF COL_LENGTH(N'dbo.Farms', N'Id') IS NOT NULL
   AND COL_LENGTH(N'dbo.Farms', N'FarmId') IS NOT NULL
BEGIN
    SELECT COUNT(*) AS misplaced_rows
    FROM   dbo.Farms
    WHERE  FarmId = '0'
       AND Id LIKE '________-____-____-____-____________';
END
ELSE
BEGIN
    SELECT CAST(NULL AS INT) AS misplaced_rows,
           N'Skipped: Farms.Id and/or Farms.FarmId column missing' AS Note;
END

-- ------------------------------------------------------------
-- Q4. How many AspNetUsers point at a non-existent Farms.FarmId?
-- > 0 → those users see no data at all.
-- ------------------------------------------------------------
PRINT N'--- Q4: orphan AspNetUsers (FarmId not in dbo.Farms) ---';
IF OBJECT_ID(N'dbo.AspNetUsers', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.Farms', N'FarmId') IS NOT NULL
BEGIN
    SELECT COUNT(*) AS orphan_users
    FROM   dbo.AspNetUsers u
    WHERE  u.FarmId IS NOT NULL
       AND LTRIM(RTRIM(u.FarmId)) <> ''
       AND NOT EXISTS (SELECT 1 FROM dbo.Farms f WHERE f.FarmId = u.FarmId);
END
ELSE
BEGIN
    SELECT CAST(NULL AS INT) AS orphan_users,
           N'Skipped: AspNetUsers table or Farms.FarmId column missing' AS Note;
END

-- ------------------------------------------------------------
-- Q5. What does spCompany_GetByUserId currently join on?
-- Search the SP body for the join clause. After migration 054
-- it joins on f.FarmId. Before, it joins on f.Id.
-- ------------------------------------------------------------
PRINT N'--- Q5: spCompany_GetByUserId join clause ---';
IF OBJECT_ID(N'dbo.spCompany_GetByUserId', N'P') IS NOT NULL
BEGIN
    DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(N'dbo.spCompany_GetByUserId'));
    SELECT
        CASE
            WHEN @def LIKE N'%uf.FarmId = f.FarmId%' THEN N'NEW (post-054, correct)'
            WHEN @def LIKE N'%uf.FarmId = f.Id%'     THEN N'OLD (pre-054, broken)'
            ELSE N'UNKNOWN — paste OBJECT_DEFINITION below and read it manually'
        END AS spCompany_GetByUserId_State,
        LEN(@def) AS sp_body_length_chars;
END
ELSE
BEGIN
    SELECT N'spCompany_GetByUserId does not exist' AS spCompany_GetByUserId_State,
           CAST(NULL AS INT) AS sp_body_length_chars;
END

PRINT N'=== Done. Paste the five result sets back. ===';
