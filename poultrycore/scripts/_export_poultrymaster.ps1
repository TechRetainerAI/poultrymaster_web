# Export PoultryMaster database (schema + data) to a single SQL migration file.
# Uses System.Data.SqlClient (no SMO, no pyodbc, no sqlpackage).
#
# Output: 003_PoultryMaster_full_snapshot_<timestamp>.sql in the same folder.

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$OutFile = Join-Path $ScriptDir ("003_PoultryMaster_full_snapshot_{0}.sql" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

$ConnStr = 'Server=34.39.109.13;Database=PoultryMaster;User Id=sqlserver;Password=Techretainer@77;Encrypt=False;TrustServerCertificate=True;Connect Timeout=30'
$conn = New-Object System.Data.SqlClient.SqlConnection $ConnStr
$conn.Open()
Write-Host "Connected to PoultryMaster on 34.39.109.13."

function Q($sql) {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.CommandTimeout = 0
    $rdr = $cmd.ExecuteReader()
    $rows = New-Object System.Collections.ArrayList
    while ($rdr.Read()) {
        $row = [ordered]@{}
        for ($i=0; $i -lt $rdr.FieldCount; $i++) {
            $row[$rdr.GetName($i)] = if ($rdr.IsDBNull($i)) { $null } else { $rdr.GetValue($i) }
        }
        [void]$rows.Add([pscustomobject]$row)
    }
    $rdr.Close()
    return ,$rows
}

function FormatValue($v) {
    if ($null -eq $v -or $v -is [System.DBNull]) { return 'NULL' }
    switch ($v.GetType().FullName) {
        'System.String'   { return "N'" + ($v -replace "'", "''") + "'" }
        'System.Boolean'  { return $(if ($v) { '1' } else { '0' }) }
        'System.Byte[]'   {
            if ($v.Length -eq 0) { return '0x' }
            $hex = [System.BitConverter]::ToString($v).Replace('-','')
            return '0x' + $hex
        }
        'System.DateTime' { return "'" + $v.ToString('yyyy-MM-ddTHH:mm:ss.fff') + "'" }
        'System.DateTimeOffset' { return "'" + $v.ToString('yyyy-MM-ddTHH:mm:ss.fffzzz') + "'" }
        'System.TimeSpan' { return "'" + $v.ToString() + "'" }
        'System.Guid'     { return "'" + $v.ToString() + "'" }
        default {
            if ($v -is [decimal] -or $v -is [double] -or $v -is [single]) {
                return $v.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            }
            return $v.ToString()
        }
    }
}

# ------------------------------------------------------------
# 1. Discover all user tables
# ------------------------------------------------------------
Write-Host "Reading schema metadata..."
$tables = Q @"
SELECT s.name AS schema_name, t.name AS table_name, t.object_id
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE t.is_ms_shipped = 0
ORDER BY s.name, t.name;

"@
Write-Host ("  Tables: {0}" -f $tables.Count)

# Columns per table
$columns = Q @"
SELECT s.name AS schema_name, t.name AS table_name, c.column_id, c.name AS column_name,
       TYPE_NAME(c.user_type_id) AS type_name,
       c.max_length, c.precision, c.scale, c.is_nullable, c.is_identity,
       ic.seed_value, ic.increment_value,
       OBJECT_DEFINITION(c.default_object_id) AS default_def,
       CASE WHEN cc.column_id IS NOT NULL THEN 1 ELSE 0 END AS is_computed,
       cc.definition AS computed_def, cc.is_persisted
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.columns c ON c.object_id = t.object_id
LEFT JOIN sys.identity_columns ic ON ic.object_id = c.object_id AND ic.column_id = c.column_id
LEFT JOIN sys.computed_columns cc ON cc.object_id = c.object_id AND cc.column_id = c.column_id
WHERE t.is_ms_shipped = 0
ORDER BY s.name, t.name, c.column_id;

"@
Write-Host ("  Columns: {0}" -f $columns.Count)

# Primary keys
$pks = Q @"
SELECT s.name AS schema_name, t.name AS table_name, kc.name AS pk_name, c.name AS column_name, ic.key_ordinal, ic.is_descending_key
FROM sys.key_constraints kc
JOIN sys.tables t  ON t.object_id = kc.parent_object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.index_columns ic ON ic.object_id = kc.parent_object_id AND ic.index_id = kc.unique_index_id
JOIN sys.columns c        ON c.object_id  = ic.object_id        AND c.column_id  = ic.column_id
WHERE kc.type = 'PK'
ORDER BY s.name, t.name, ic.key_ordinal;

"@

# Unique constraints
$uqs = Q @"
SELECT s.name AS schema_name, t.name AS table_name, kc.name AS uq_name, c.name AS column_name, ic.key_ordinal
FROM sys.key_constraints kc
JOIN sys.tables t  ON t.object_id = kc.parent_object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.index_columns ic ON ic.object_id = kc.parent_object_id AND ic.index_id = kc.unique_index_id
JOIN sys.columns c        ON c.object_id  = ic.object_id        AND c.column_id  = ic.column_id
WHERE kc.type = 'UQ'
ORDER BY s.name, t.name, kc.name, ic.key_ordinal;

"@

# Check constraints
$checks = Q @"
SELECT s.name AS schema_name, t.name AS table_name, cc.name, cc.definition
FROM sys.check_constraints cc
JOIN sys.tables t  ON t.object_id = cc.parent_object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
ORDER BY s.name, t.name, cc.name;

"@

# Foreign keys (column lists)
$fks = Q @"
SELECT fk.name AS fk_name,
       sp.name AS parent_schema, tp.name AS parent_table,
       sr.name AS ref_schema,    tr.name AS ref_table,
       cp.name AS parent_column, cr.name AS ref_column, fkc.constraint_column_id,
       fk.delete_referential_action_desc, fk.update_referential_action_desc
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.tables tp  ON tp.object_id = fkc.parent_object_id
JOIN sys.schemas sp ON sp.schema_id = tp.schema_id
JOIN sys.columns cp ON cp.object_id  = fkc.parent_object_id AND cp.column_id = fkc.parent_column_id
JOIN sys.tables tr  ON tr.object_id = fkc.referenced_object_id
JOIN sys.schemas sr ON sr.schema_id = tr.schema_id
JOIN sys.columns cr ON cr.object_id  = fkc.referenced_object_id AND cr.column_id = fkc.referenced_column_id
ORDER BY fk.name, fkc.constraint_column_id;

"@

# Default constraints
$defaults = Q @"
SELECT s.name AS schema_name, t.name AS table_name, c.name AS column_name,
       dc.name AS default_name, dc.definition
FROM sys.default_constraints dc
JOIN sys.tables t  ON t.object_id = dc.parent_object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
ORDER BY s.name, t.name, c.column_id;

"@

# Indexes (non-PK, non-UQ -- only standalone)
$indexes = Q @"
SELECT s.name AS schema_name, t.name AS table_name, i.name AS index_name,
       i.is_unique, i.type_desc, i.filter_definition
FROM sys.indexes i
JOIN sys.tables t  ON t.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE i.is_primary_key = 0 AND i.is_unique_constraint = 0 AND i.type > 0
  AND t.is_ms_shipped = 0
ORDER BY s.name, t.name, i.name;

"@
$indexCols = Q @"
SELECT s.name AS schema_name, t.name AS table_name, i.name AS index_name,
       c.name AS column_name, ic.key_ordinal, ic.is_descending_key, ic.is_included_column
FROM sys.indexes i
JOIN sys.tables t  ON t.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c        ON c.object_id  = ic.object_id AND c.column_id = ic.column_id
WHERE i.is_primary_key = 0 AND i.is_unique_constraint = 0 AND i.type > 0
  AND t.is_ms_shipped = 0
ORDER BY s.name, t.name, i.name, ic.is_included_column, ic.key_ordinal;

"@

# Views / Procedures / Triggers (with bodies)
$modules = Q @"
SELECT s.name AS schema_name, o.name AS obj_name, o.type_desc, m.definition
FROM sys.sql_modules m
JOIN sys.objects o ON o.object_id = m.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE o.is_ms_shipped = 0
  AND o.type_desc IN ('VIEW','SQL_STORED_PROCEDURE','SQL_TRIGGER')
ORDER BY o.type_desc, s.name, o.name;

"@
Write-Host ("  Modules (views/procs/triggers): {0}" -f $modules.Count)

# ------------------------------------------------------------
# 2. Build column type string
# ------------------------------------------------------------
function ColType($col) {
    $tn = $col.type_name
    switch -Regex ($tn) {
        '^n?varchar$|^n?char$|^varbinary$|^binary$' {
            $len = if ($col.max_length -eq -1) { 'MAX' }
                   elseif ($tn -like 'n*' -and $tn -notlike '*binary') { ($col.max_length / 2).ToString() }
                   else { $col.max_length.ToString() }
            return "$tn($len)"
        }
        '^decimal$|^numeric$' { return "$tn($($col.precision),$($col.scale))" }
        '^datetime2$|^time$|^datetimeoffset$' {
            if ($col.scale -ne $null -and $col.scale -ne 7) { return "$tn($($col.scale))" }
            return $tn
        }
        default { return $tn }
    }
}

# ------------------------------------------------------------
# 3. Open output file and start writing
# ------------------------------------------------------------
$sw = New-Object System.IO.StreamWriter $OutFile, $false, ([System.Text.UTF8Encoding]::new($true))
function W($line) { $sw.WriteLine($line) }
function WGO() { $sw.WriteLine('GO'); $sw.WriteLine() }

W "-- ============================================================================="
W "-- PoultryMaster full schema + data snapshot"
W ("-- Generated: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
W "-- Source: PoultryMaster on 34.39.109.13"
W "-- Use: idempotent migration script -- re-runnable from a clean DB or rebuild target."
W "-- ============================================================================="
W ""
W "SET ANSI_NULLS ON;"
W "SET QUOTED_IDENTIFIER ON;"
W "SET NOCOUNT ON;"
WGO

# ------------------------------------------------------------
# 4. Drop FKs first (so subsequent table drops work in any order)
# ------------------------------------------------------------
W "-- ===== Drop existing foreign keys (idempotency) ====="
$fkNames = $fks | Select-Object -ExpandProperty fk_name -Unique
foreach ($n in $fkNames) {
    W "IF OBJECT_ID(N'$n','F') IS NOT NULL"
    W "    ALTER TABLE [dbo].[$(($fks | Where-Object fk_name -eq $n | Select-Object -First 1).parent_table)] DROP CONSTRAINT [$n];"
}
WGO

# Drop views / procs / triggers (idempotency)
W "-- ===== Drop existing views / procedures / triggers ====="
foreach ($m in $modules) {
    $kind = switch ($m.type_desc) {
        'VIEW' { 'V' }
        'SQL_STORED_PROCEDURE' { 'P' }
        'SQL_TRIGGER' { 'TR' }
    }
    W "IF OBJECT_ID(N'[$($m.schema_name)].[$($m.obj_name)]','$kind') IS NOT NULL"
    $dropKw = switch ($m.type_desc) { 'VIEW' {'VIEW'} 'SQL_STORED_PROCEDURE' {'PROCEDURE'} 'SQL_TRIGGER' {'TRIGGER'} }
    W "    DROP $dropKw [$($m.schema_name)].[$($m.obj_name)];"
}
WGO

# Drop existing tables (idempotency)
W "-- ===== Drop existing tables ====="
foreach ($t in $tables) {
    W "IF OBJECT_ID(N'[$($t.schema_name)].[$($t.table_name)]','U') IS NOT NULL"
    W "    DROP TABLE [$($t.schema_name)].[$($t.table_name)];"
}
WGO

# ------------------------------------------------------------
# 5. Create tables (columns + PKs + UQs + CHECKs + DEFAULTs)
# ------------------------------------------------------------
W "-- ============================================================================="
W "-- SECTION 1: CREATE TABLES"
W "-- ============================================================================="
W ""

foreach ($t in $tables) {
    $tcols = $columns | Where-Object { $_.schema_name -eq $t.schema_name -and $_.table_name -eq $t.table_name }
    W "CREATE TABLE [$($t.schema_name)].[$($t.table_name)] ("
    $colLines = @()
    foreach ($c in $tcols) {
        if ($c.is_computed -eq 1) {
            $line = "    [$($c.column_name)] AS ($($c.computed_def))"
            if ($c.is_persisted) { $line += " PERSISTED" }
        } else {
            $line = "    [$($c.column_name)] $(ColType $c)"
            if ($c.is_identity -eq $true -or $c.is_identity -eq 1) {
                $line += " IDENTITY($($c.seed_value),$($c.increment_value))"
            }
            $line += if ($c.is_nullable) { ' NULL' } else { ' NOT NULL' }
            # Inline default
            $def = $defaults | Where-Object { $_.schema_name -eq $t.schema_name -and $_.table_name -eq $t.table_name -and $_.column_name -eq $c.column_name } | Select-Object -First 1
            if ($def) {
                $line += " CONSTRAINT [$($def.default_name)] DEFAULT $($def.definition)"
            }
        }
        $colLines += $line
    }
    # Inline PK
    $tpk = $pks | Where-Object { $_.schema_name -eq $t.schema_name -and $_.table_name -eq $t.table_name }
    if ($tpk) {
        $pkName = ($tpk | Select-Object -First 1).pk_name
        $pkCols = ($tpk | ForEach-Object { "[$($_.column_name)]" + $(if ($_.is_descending_key) {' DESC'} else {' ASC'}) }) -join ', '
        $colLines += "    CONSTRAINT [$pkName] PRIMARY KEY ($pkCols)"
    }
    # Inline UQ constraints
    $tuq = $uqs | Where-Object { $_.schema_name -eq $t.schema_name -and $_.table_name -eq $t.table_name } | Group-Object uq_name
    foreach ($g in $tuq) {
        $uqCols = ($g.Group | Sort-Object key_ordinal | ForEach-Object { "[$($_.column_name)]" }) -join ', '
        $colLines += "    CONSTRAINT [$($g.Name)] UNIQUE ($uqCols)"
    }
    W (($colLines) -join ",`r`n")
    W ");"
    WGO
}

# CHECK constraints
$checkGroups = $checks | Group-Object schema_name, table_name
if ($checkGroups) {
    W "-- ===== Check constraints ====="
    foreach ($g in $checkGroups) {
        foreach ($c in $g.Group) {
            W "ALTER TABLE [$($c.schema_name)].[$($c.table_name)]"
            W "    ADD CONSTRAINT [$($c.name)] CHECK $($c.definition);"
        }
    }
    WGO
}

# ------------------------------------------------------------
# 6. Insert data (with IDENTITY_INSERT toggling)
# ------------------------------------------------------------
W "-- ============================================================================="
W "-- SECTION 2: INSERT DATA"
W "-- ============================================================================="
W ""

$totalRows = 0
foreach ($t in $tables) {
    $tcols = $columns | Where-Object { $_.schema_name -eq $t.schema_name -and $_.table_name -eq $t.table_name -and $_.is_computed -ne 1 }
    if ($tcols.Count -eq 0) { continue }
    $hasIdentity = ($tcols | Where-Object { $_.is_identity -eq $true -or $_.is_identity -eq 1 }).Count -gt 0

    $colList = ($tcols | ForEach-Object { "[$($_.column_name)]" }) -join ', '

    # Row count first
    $rcCmd = $conn.CreateCommand()
    $rcCmd.CommandText = "SELECT COUNT(*) FROM [$($t.schema_name)].[$($t.table_name)]"
    $rcCmd.CommandTimeout = 0
    $rc = [int]$rcCmd.ExecuteScalar()
    if ($rc -eq 0) {
        W "-- (no rows in [$($t.schema_name)].[$($t.table_name)])"
        W ""
        continue
    }
    Write-Host ("  data: {0}.{1} ({2:N0} rows)" -f $t.schema_name, $t.table_name, $rc)
    $totalRows += $rc

    W "PRINT N'Inserting data into [$($t.schema_name)].[$($t.table_name)] ($rc rows)...';"
    if ($hasIdentity) { W "SET IDENTITY_INSERT [$($t.schema_name)].[$($t.table_name)] ON;" }

    $dCmd = $conn.CreateCommand()
    $dCmd.CommandText = "SELECT $colList FROM [$($t.schema_name)].[$($t.table_name)]"
    $dCmd.CommandTimeout = 0
    $rdr = $dCmd.ExecuteReader()
    $rowCount = 0
    $batchSize = 200
    $batchVals = New-Object System.Collections.ArrayList
    while ($rdr.Read()) {
        $vals = @()
        for ($i=0; $i -lt $rdr.FieldCount; $i++) {
            $v = if ($rdr.IsDBNull($i)) { $null } else { $rdr.GetValue($i) }
            $vals += FormatValue $v
        }
        [void]$batchVals.Add('(' + ($vals -join ', ') + ')')
        $rowCount++
        if ($batchVals.Count -ge $batchSize) {
            W "INSERT INTO [$($t.schema_name)].[$($t.table_name)] ($colList) VALUES"
            W (($batchVals -join ",`r`n") + ';')
            $batchVals.Clear()
        }
    }
    if ($batchVals.Count -gt 0) {
        W "INSERT INTO [$($t.schema_name)].[$($t.table_name)] ($colList) VALUES"
        W (($batchVals -join ",`r`n") + ';')
    }
    $rdr.Close()

    if ($hasIdentity) { W "SET IDENTITY_INSERT [$($t.schema_name)].[$($t.table_name)] OFF;" }
    WGO
}
Write-Host ("Total rows exported: {0:N0}" -f $totalRows)

# ------------------------------------------------------------
# 7. Foreign keys
# ------------------------------------------------------------
W "-- ============================================================================="
W "-- SECTION 3: FOREIGN KEYS"
W "-- ============================================================================="
W ""
$fkGroups = $fks | Group-Object fk_name
foreach ($g in $fkGroups) {
    $first = $g.Group | Select-Object -First 1
    $parentCols = ($g.Group | Sort-Object constraint_column_id | ForEach-Object { "[$($_.parent_column)]" }) -join ', '
    $refCols    = ($g.Group | Sort-Object constraint_column_id | ForEach-Object { "[$($_.ref_column)]" })    -join ', '
    $onDel = if ($first.delete_referential_action_desc -ne 'NO_ACTION') { " ON DELETE $($first.delete_referential_action_desc.Replace('_',' '))" } else { '' }
    $onUpd = if ($first.update_referential_action_desc -ne 'NO_ACTION') { " ON UPDATE $($first.update_referential_action_desc.Replace('_',' '))" } else { '' }
    W "ALTER TABLE [$($first.parent_schema)].[$($first.parent_table)] WITH NOCHECK"
    W "    ADD CONSTRAINT [$($g.Name)] FOREIGN KEY ($parentCols)"
    W "    REFERENCES [$($first.ref_schema)].[$($first.ref_table)] ($refCols)$onDel$onUpd;"
}
WGO

# ------------------------------------------------------------
# 8. Non-PK indexes
# ------------------------------------------------------------
W "-- ============================================================================="
W "-- SECTION 4: INDEXES"
W "-- ============================================================================="
W ""
foreach ($i in $indexes) {
    $key = ($indexCols | Where-Object { $_.schema_name -eq $i.schema_name -and $_.table_name -eq $i.table_name -and $_.index_name -eq $i.index_name -and $_.is_included_column -eq $false } |
            Sort-Object key_ordinal | ForEach-Object { "[$($_.column_name)]" + $(if ($_.is_descending_key) {' DESC'} else {''}) }) -join ', '
    $inc = ($indexCols | Where-Object { $_.schema_name -eq $i.schema_name -and $_.table_name -eq $i.table_name -and $_.index_name -eq $i.index_name -and $_.is_included_column -eq $true } |
            ForEach-Object { "[$($_.column_name)]" }) -join ', '
    $unique = if ($i.is_unique) { 'UNIQUE ' } else { '' }
    $type = if ($i.type_desc -eq 'CLUSTERED') { 'CLUSTERED' } else { 'NONCLUSTERED' }
    $line = "CREATE $unique$type INDEX [$($i.index_name)] ON [$($i.schema_name)].[$($i.table_name)] ($key)"
    if ($inc) { $line += " INCLUDE ($inc)" }
    if ($i.filter_definition) { $line += " WHERE $($i.filter_definition)" }
    W ($line + ';')
}
WGO

# ------------------------------------------------------------
# 9. Views, procedures, triggers
# ------------------------------------------------------------
W "-- ============================================================================="
W "-- SECTION 5: VIEWS / STORED PROCEDURES / TRIGGERS"
W "-- ============================================================================="
W ""
foreach ($m in $modules) {
    W "-- $($m.type_desc): [$($m.schema_name)].[$($m.obj_name)]"
    W $m.definition.Trim()
    WGO
}

W "PRINT N'PoultryMaster snapshot restored.';"
W "GO"

$sw.Close()
$conn.Close()

$size = (Get-Item $OutFile).Length
Write-Host ""
Write-Host ("=== DONE ===")
Write-Host ("Output: {0}" -f $OutFile)
Write-Host ("Size:   {0:N1} MB ({1:N0} bytes)" -f ($size/1MB), $size)
Write-Host ("Total rows: {0:N0}" -f $totalRows)
