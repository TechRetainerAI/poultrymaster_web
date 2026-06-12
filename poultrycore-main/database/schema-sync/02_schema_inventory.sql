-- ============================================================
-- STEP 2: Schema inventory — RUN THIS TWICE.
--   First time:  connect to the DEV database and run it
--   Second time: connect to the PROD database and run it
-- Save each result set to a CSV (or just copy/paste) labelled
-- DEV_<resultname>.csv and PROD_<resultname>.csv, then send
-- them back to Claude.
--
-- Read-only. Touches nothing. Safe to run on prod.
-- ============================================================

PRINT N'>>> Inventory for database: ' + DB_NAME();
PRINT N'>>> Run timestamp (UTC):    ' + CONVERT(NVARCHAR(30), SYSUTCDATETIME(), 126);

-- ------------------------------------------------------------
-- 2.1 — Tables
-- ------------------------------------------------------------
SELECT
    s.name                AS [Schema],
    t.name                AS TableName,
    p.rows                AS RowCount_est
FROM sys.tables t
JOIN sys.schemas s   ON s.schema_id = t.schema_id
JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
WHERE t.is_ms_shipped = 0
ORDER BY s.name, t.name;

-- ------------------------------------------------------------
-- 2.2 — Columns (this is the most important one for finding
--       missing columns like HasArrived on the Flock table)
-- ------------------------------------------------------------
SELECT
    s.name                                       AS [Schema],
    t.name                                       AS TableName,
    c.name                                       AS ColumnName,
    c.column_id                                  AS Ordinal,
    ty.name                                      AS DataType,
    c.max_length                                 AS MaxLength,
    c.precision                                  AS [Precision],
    c.scale                                      AS Scale,
    c.is_nullable                                AS IsNullable,
    c.is_identity                                AS IsIdentity,
    OBJECT_DEFINITION(c.default_object_id)       AS DefaultDefinition,
    cc.definition                                AS ComputedDefinition
FROM sys.columns c
JOIN sys.tables  t  ON t.object_id = c.object_id
JOIN sys.schemas s  ON s.schema_id = t.schema_id
JOIN sys.types   ty ON ty.user_type_id = c.user_type_id
LEFT JOIN sys.computed_columns cc ON cc.object_id = c.object_id AND cc.column_id = c.column_id
WHERE t.is_ms_shipped = 0
ORDER BY s.name, t.name, c.column_id;

-- ------------------------------------------------------------
-- 2.3 — Primary keys + unique constraints
-- ------------------------------------------------------------
SELECT
    s.name                       AS [Schema],
    t.name                       AS TableName,
    kc.name                      AS ConstraintName,
    kc.type_desc                 AS ConstraintType,
    STUFF((
        SELECT ',' + c.name
        FROM sys.index_columns ic
        JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = kc.parent_object_id AND ic.index_id = kc.unique_index_id
        ORDER BY ic.key_ordinal
        FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, '') AS ColumnList
FROM sys.key_constraints kc
JOIN sys.tables  t ON t.object_id = kc.parent_object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0
ORDER BY s.name, t.name, kc.type_desc, kc.name;

-- ------------------------------------------------------------
-- 2.4 — Foreign keys
-- ------------------------------------------------------------
SELECT
    s.name                       AS [Schema],
    t.name                       AS TableName,
    fk.name                      AS FKName,
    rs.name                      AS RefSchema,
    rt.name                      AS RefTable,
    STUFF((
        SELECT ',' + c.name
        FROM sys.foreign_key_columns fkc
        JOIN sys.columns c ON c.object_id = fkc.parent_object_id AND c.column_id = fkc.parent_column_id
        WHERE fkc.constraint_object_id = fk.object_id
        ORDER BY fkc.constraint_column_id
        FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, '') AS ColumnList,
    fk.delete_referential_action_desc AS OnDelete,
    fk.update_referential_action_desc AS OnUpdate
FROM sys.foreign_keys fk
JOIN sys.tables  t  ON t.object_id = fk.parent_object_id
JOIN sys.schemas s  ON s.schema_id = t.schema_id
JOIN sys.tables  rt ON rt.object_id = fk.referenced_object_id
JOIN sys.schemas rs ON rs.schema_id = rt.schema_id
ORDER BY s.name, t.name, fk.name;

-- ------------------------------------------------------------
-- 2.5 — Indexes (non-PK)
-- ------------------------------------------------------------
SELECT
    s.name                       AS [Schema],
    t.name                       AS TableName,
    i.name                       AS IndexName,
    i.type_desc                  AS IndexType,
    i.is_unique                  AS IsUnique,
    i.has_filter                 AS HasFilter,
    i.filter_definition          AS FilterDef,
    STUFF((
        SELECT ',' + c.name
        FROM sys.index_columns ic
        JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
        ORDER BY ic.key_ordinal
        FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, '') AS KeyColumns,
    STUFF((
        SELECT ',' + c.name
        FROM sys.index_columns ic
        JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1
        ORDER BY ic.index_column_id
        FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, '') AS IncludedColumns
FROM sys.indexes i
JOIN sys.tables  t ON t.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0
  AND i.is_primary_key = 0
  AND i.is_unique_constraint = 0
  AND i.type > 0
ORDER BY s.name, t.name, i.name;

-- ------------------------------------------------------------
-- 2.6 — Programmability (procs, functions, views, triggers)
-- ------------------------------------------------------------
SELECT
    s.name              AS [Schema],
    o.name              AS ObjectName,
    o.type_desc         AS ObjectType,
    o.create_date       AS Created,
    o.modify_date       AS LastModified
FROM sys.objects o
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE o.is_ms_shipped = 0
  AND o.type IN ('P','FN','IF','TF','V','TR')
ORDER BY o.type_desc, s.name, o.name;

-- ------------------------------------------------------------
-- 2.7 — Specifically: does Flock have HasArrived? (sanity check
--       tied directly to the "no flocks available" bug)
-- ------------------------------------------------------------
SELECT
    DB_NAME()                              AS DatabaseName,
    t.name                                 AS TableName,
    SUM(CASE WHEN c.name = 'HasArrived' THEN 1 ELSE 0 END) AS HasArrived_present,
    SUM(CASE WHEN c.name = 'Active'     THEN 1 ELSE 0 END) AS Active_present,
    SUM(CASE WHEN c.name = 'BatchId'    THEN 1 ELSE 0 END) AS BatchId_present,
    SUM(CASE WHEN c.name = 'HouseId'    THEN 1 ELSE 0 END) AS HouseId_present
FROM sys.tables t
LEFT JOIN sys.columns c ON c.object_id = t.object_id
WHERE t.name IN ('Flock','Flocks')
GROUP BY t.name;
