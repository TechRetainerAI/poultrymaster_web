-- =============================================
-- Inventory troubleshooting (run in SSMS)
-- Select your APPLICATION database in SSMS (NOT master) — same as PoultryConn.
-- Set @FarmId to your farm GUID.
--
-- Uses dynamic SQL so this script does NOT fail compile when
-- dbo.InventoryItem is missing (run 011_CreateInventoryItemModule.sql first).
-- =============================================

IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb')
BEGIN
    THROW 50000,
        N'Select your application database in SSMS (not master), then run again.',
        1;
END
GO

DECLARE @FarmId NVARCHAR(450) = N'6b888997-c36a-4462-bdb8-c0fe291f1062';

-- 0) Tables matching %Inventory%
SELECT s.name AS SchemaName, t.name AS TableName
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE t.name LIKE N'%Inventory%'
ORDER BY s.name, t.name;

-- 1) Row counts / sample (only if table exists)
IF OBJECT_ID(N'dbo.InventoryItem', N'U') IS NULL
BEGIN
  PRINT N'FAIL: dbo.InventoryItem missing. Run: Migrations/011_CreateInventoryItemModule.sql';
END
ELSE
BEGIN
  PRINT N'OK: dbo.InventoryItem exists.';

  EXEC sp_executesql
    N'SELECT COUNT(*) AS RowCountForFarm FROM dbo.InventoryItem WHERE FarmId = @fid',
    N'@fid NVARCHAR(450)',
    @fid = @FarmId;

  EXEC sp_executesql
    N'SELECT TOP 30 ItemId, UserId, CAST(FarmId AS NVARCHAR(64)) AS FarmId, ItemName, Category, QuantityInStock, IsActive
      FROM dbo.InventoryItem ORDER BY ItemId DESC';
END

-- 2) Procedures
SELECT name, type_desc
FROM sys.objects
WHERE name IN (
    N'spInventoryItem_GetAll',
    N'spInventoryItem_GetById',
    N'spInventoryItem_Insert',
    N'spInventoryItem_Update',
    N'spInventoryItem_Delete'
)
AND schema_id = SCHEMA_ID(N'dbo');

-- 3) Test GetAll
IF OBJECT_ID(N'dbo.InventoryItem', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.spInventoryItem_GetAll', N'P') IS NOT NULL
BEGIN
  EXEC dbo.spInventoryItem_GetAll @UserId = NULL, @FarmId = @FarmId;
END
ELSE
BEGIN
  PRINT N'Skip EXEC spInventoryItem_GetAll: create table + procs first.';
END
