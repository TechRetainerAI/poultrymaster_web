# =============================================================================
# Apply migration 329 (batch codes unique per company, not globally) to Postgres.
#
# Same four phases as the other apply scripts:
#
#   1. MEASURE   every batch row, and the shape of every unique index on the
#                table.
#   2. DRY RUN   the migration inside a transaction that is then ROLLED BACK.
#   3. APPLY     the migration in its own transaction.
#   4. MEASURE   again and diff.
#
# WHAT THE MEASUREMENT IS FOR
# ---------------------------
# This migration must not touch a single row -- it only widens what the table
# will accept. So phase 4 compares every batch row and must print "No change to
# any batch row." Any difference at all is a bug.
#
# The index inventory is measured separately and is EXPECTED to differ: exactly
# one global unique index on batchcode disappears and one per-farm index
# appears. The script prints that change rather than diffing it silently, so it
# is read rather than assumed.
#
# WHY THE DRY RUN MATTERS HERE
# ----------------------------
# Phase 1 of the migration refuses to proceed if any farm already holds two
# codes that collide under the new normalisation ("B1" and "b1" in one company).
# Globally distinct codes do not rule that out. The dry run is what surfaces it
# before anything is committed.
#
# EFFECT ON TODAY'S NUMBERS: none. No row changes.
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-batch-code-per-farm.ps1                 # measure + dry run
#   .\apply-batch-code-per-farm.ps1 -Apply          # ... then apply
#
# Requires the dev machine's public IP to be on the Cloud SQL authorized-networks
# list, or every psql call times out. See the cloudsql-ip-allowlist note.
# =============================================================================

[CmdletBinding()]
param(
    [string] $DbHost   = '34.175.134.7',
    [int]    $Port     = 5432,
    [string] $Database = 'VisibilityCoreDB',
    [string] $User     = 'poultryapp',
    [string] $Psql     = 'C:\Program Files\PostgreSQL\18\bin\psql.exe',
    [string] $MigrationsDir = (Join-Path $PSScriptRoot '..\..\poultrycore_Backend\PoultryFarmAPI\Migrations'),
    [string] $OutDir   = (Join-Path $env:TEMP 'batch-code-per-farm'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files = @('329_BatchCodeUniquePerFarm.postgres.sql')
foreach ($f in $files) {
    if (-not (Test-Path (Join-Path $MigrationsDir $f))) { throw "Missing migration: $f" }
}

# Redirection is handed to cmd.exe rather than done in PowerShell on purpose.
# PowerShell 5.1 wraps a native command's stderr in ErrorRecords, so a single
# psql NOTICE -- of which this migration emits several -- trips
# $ErrorActionPreference and aborts a run that was going fine.
function Invoke-Psql {
    param([string] $File, [string] $LogPath)
    $line = '"{0}" -h {1} -p {2} -U {3} -d {4} -X -w -v ON_ERROR_STOP=1 -f "{5}"' -f `
            $Psql, $DbHost, $Port, $User, $Database, $File
    if ($LogPath) { $line += ' > "{0}" 2>&1' -f $LogPath }
    & cmd.exe /c $line
    return $LASTEXITCODE
}

# --- the row measurement, before and after -----------------------------------
# No row may change. Ordered by primary key so a diff is a diff, not a re-sort.
$measureSql = @'
\pset footer off
\pset pager off
SELECT batchid, farmid, batchcode, batchname, breed, numberofbirds,
       startdate, status, costperchick, totalcost, amountpaid,
       suppliertype, supplierid, ishistorical
FROM   public.mainflockbatch
ORDER  BY batchid;
'@
$measureFile = Join-Path $OutDir 'measure.sql'
Set-Content -Path $measureFile -Value $measureSql -Encoding utf8

# --- the index inventory, which is EXPECTED to change ------------------------
$indexSql = @'
\pset footer off
\pset pager off
SELECT i.relname AS index_name, pg_get_indexdef(idx.indexrelid) AS definition
FROM   pg_index idx
JOIN   pg_class i ON i.oid = idx.indexrelid
JOIN   pg_class t ON t.oid = idx.indrelid
JOIN   pg_namespace n ON n.oid = t.relnamespace
WHERE  n.nspname = 'public' AND t.relname = 'mainflockbatch' AND idx.indisunique
ORDER  BY i.relname;
'@
$indexFile = Join-Path $OutDir 'indexes.sql'
Set-Content -Path $indexFile -Value $indexSql -Encoding utf8

Write-Host "Host:       $DbHost/$Database"
Write-Host "Migration:  $($files -join ', ')"
Write-Host ''

# --- phase 1: measure before -------------------------------------------------
Write-Host '=== 1. BEFORE ===' -ForegroundColor Cyan
$before = Join-Path $OutDir 'before.txt'
if ((Invoke-Psql -File $measureFile -LogPath $before) -ne 0) {
    Get-Content $before | Write-Host
    throw 'Could not read the baseline. Nothing has been changed.'
}
Write-Host "  $((Get-Content $before).Count) line(s) of batch rows captured" -ForegroundColor Gray

$idxBefore = Join-Path $OutDir 'indexes-before.txt'
[void](Invoke-Psql -File $indexFile -LogPath $idxBefore)
Write-Host '  unique indexes now:' -ForegroundColor Gray
Get-Content $idxBefore | Write-Host

# --- phase 2: dry run, rolled back ------------------------------------------
Write-Host ''
Write-Host '=== 2. DRY RUN (rolled back) ===' -ForegroundColor Cyan
$dryFile = Join-Path $OutDir 'dryrun.sql'
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('BEGIN;')
foreach ($f in $files) {
    $path = Join-Path $MigrationsDir $f
    [void]$sb.AppendLine("\echo '--- $(Split-Path $path -Leaf) ---'")
    Get-Content $path | ForEach-Object {
        if ($_ -notmatch '^\s*(BEGIN|COMMIT)\s*;\s*$' -and $_ -notmatch '^\s*\\set\s+ON_ERROR_STOP') {
            [void]$sb.AppendLine($_)
        }
    }
}
[void]$sb.AppendLine('ROLLBACK;')
Set-Content -Path $dryFile -Value $sb.ToString() -Encoding utf8

$dryLog = Join-Path $OutDir 'dryrun.log'
$dryCode = Invoke-Psql -File $dryFile -LogPath $dryLog
Get-Content $dryLog | Write-Host
if ($dryCode -ne 0) {
    throw "DRY RUN FAILED (see $dryLog). Nothing has been changed."
}

# The migration's own verification block must have run to completion. Its final
# NOTICE is the only thing that proves both halves held: two companies sharing a
# code was accepted, and one company repeating it was refused.
$verified = Get-Content $dryLog |
    Where-Object { $_ -match 'batch codes are now unique per company, verified' }
if (-not $verified) {
    throw 'The migration verification block did not report success. Do not apply.'
}
$verified | Write-Host -ForegroundColor Green

Write-Host 'Dry run clean -- syntax and behaviour validated, transaction discarded.' -ForegroundColor Green

if (-not $Apply) {
    Write-Host ''
    Write-Host 'Stopping here. Re-run with -Apply to commit.' -ForegroundColor Yellow
    return
}

# --- phase 3: apply ----------------------------------------------------------
Write-Host ''
Write-Host '=== 3. APPLY ===' -ForegroundColor Cyan
foreach ($f in $files) {
    Write-Host "  $f" -NoNewline
    $log = Join-Path $OutDir "$f.log"
    $code = Invoke-Psql -File (Join-Path $MigrationsDir $f) -LogPath $log
    if ($code -ne 0) {
        Write-Host '  FAILED' -ForegroundColor Red
        Get-Content $log | Write-Host
        throw "$f failed (see $log)."
    }
    Write-Host '  ok' -ForegroundColor Green
    Get-Content $log | Where-Object { $_ -match 'NOTICE' } | Write-Host -ForegroundColor Gray
}

# --- phase 4: measure after and diff ----------------------------------------
Write-Host ''
Write-Host '=== 4. AFTER ===' -ForegroundColor Cyan
$after = Join-Path $OutDir 'after.txt'
[void](Invoke-Psql -File $measureFile -LogPath $after)

Write-Host ''
Write-Host '=== ROW DIFF (expected: identical -- no row is touched) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host "No change to any batch row. ($((Get-Content $after).Count) lines compared)" -ForegroundColor Green
} else {
    $diff | Select-Object -First 40 | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- 329 changes indexes only.' -ForegroundColor Red
}

Write-Host ''
Write-Host '=== INDEX CHANGE (expected: global one out, per-farm one in) ===' -ForegroundColor Cyan
$idxAfter = Join-Path $OutDir 'indexes-after.txt'
[void](Invoke-Psql -File $indexFile -LogPath $idxAfter)
Get-Content $idxAfter | Write-Host
