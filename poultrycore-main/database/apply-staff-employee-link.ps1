# =============================================================================
# Apply migration 362 (Staff <-> Employee link) to Postgres.
#
# DEPLOY ORDER: this script FIRST, then the API, then the web app. Purely
# additive: a nullable userid on four staff tables, two readers and one setter.
# The old API never reads the new column.
#
# Four phases, as the other apply scripts:
#   1. MEASURE   every staff table: rows, live rows, hotel rows already linked.
#   2. DRY RUN   362 + checks/staff-employee-link.test.sql inside one
#                transaction that is ROLLED BACK.
#   3. APPLY     362 in its own transaction.
#   4. MEASURE   again: nothing may move -- no row is linked until a user does it.
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-staff-employee-link.ps1           # measure + dry run
#   .\apply-staff-employee-link.ps1 -Apply    # ... then apply
# =============================================================================

[CmdletBinding()]
param(
    [string] $DbHost   = '34.175.134.7',
    [int]    $Port     = 5432,
    [string] $Database = 'VisibilityCoreDB',
    [string] $User     = 'poultryapp',
    [string] $Psql     = 'C:\Program Files\PostgreSQL\18\bin\psql.exe',
    [string] $MigrationsDir = (Join-Path $PSScriptRoot '..\..\poultrycore_Backend\PoultryFarmAPI\Migrations'),
    [string] $ChecksDir = (Join-Path $PSScriptRoot 'checks'),
    [string] $OutDir   = (Join-Path $env:TEMP 'staff-employee-link'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files  = @('362_StaffEmployeeLink.postgres.sql')
$checks = @('staff-employee-link.test.sql')
$passMarkers = @('staff employee link: all checks passed')
foreach ($f in $files)  { if (-not (Test-Path (Join-Path $MigrationsDir $f))) { throw "Missing migration: $f" } }
foreach ($c in $checks) { if (-not (Test-Path (Join-Path $ChecksDir $c)))     { throw "Missing check: $c" } }

# Redirection is handed to cmd.exe rather than done in PowerShell on purpose.
# PowerShell 5.1 wraps a native command's stderr in ErrorRecords, so a single
# psql NOTICE trips $ErrorActionPreference and aborts a run that was going fine.
function Invoke-Psql {
    param([string] $File, [string] $LogPath, [string] $Extra = '')
    $line = '"{0}" -h {1} -p {2} -U {3} -d {4} -X -w -v ON_ERROR_STOP=1 {6} -f "{5}"' -f `
            $Psql, $DbHost, $Port, $User, $Database, $File, $Extra
    if ($LogPath) { $line += ' > "{0}" 2>&1' -f $LogPath }
    & cmd.exe /c $line
    return $LASTEXITCODE
}

# --- the measurements ---------------------------------------------------------
$invariantSql = @'
\pset footer off
\pset pager off
\echo '-- staff rows per table'
SELECT 'poultry', count(*), count(*) FILTER (WHERE NOT isdeleted) FROM public.poultrystaff
UNION ALL SELECT 'water', count(*), count(*) FILTER (WHERE NOT isdeleted) FROM public.waterstaff
UNION ALL SELECT 'generic', count(*), count(*) FILTER (WHERE NOT isdeleted) FROM public.genericstaff
UNION ALL SELECT 'restaurant', count(*), count(*) FROM public.restaurantstaff
UNION ALL SELECT 'hotel', count(*), count(userid) FROM public.hotelstaff;
\echo '-- staff logins'
SELECT count(*) FROM public.aspnetusers WHERE isstaff;
'@

$invariantFile = Join-Path $OutDir 'invariant.sql'
Set-Content -Path $invariantFile -Value $invariantSql -Encoding utf8

Write-Host "Host:       $DbHost/$Database"
Write-Host "Migrations: $($files -join ', ')"
Write-Host "Checks:     $($checks -join ', ')"
Write-Host ''

# --- phase 1: measure before -------------------------------------------------
Write-Host '=== 1. BEFORE ===' -ForegroundColor Cyan
$before = Join-Path $OutDir 'before.txt'
if ((Invoke-Psql -File $invariantFile -LogPath $before) -ne 0) {
    Get-Content $before | Write-Host
    throw 'Could not read the baseline. Nothing has been changed.'
}
Write-Host "  $((Get-Content $before).Count) invariant line(s) captured" -ForegroundColor Gray

# --- phase 2: dry run, rolled back ------------------------------------------
Write-Host ''
Write-Host '=== 2. DRY RUN + CHECKS (rolled back) ===' -ForegroundColor Cyan
$dryFile = Join-Path $OutDir 'dryrun.sql'
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('BEGIN;')
$parts = @($files | ForEach-Object { Join-Path $MigrationsDir $_ }) + @($checks | ForEach-Object { Join-Path $ChecksDir $_ })
foreach ($path in $parts) {
    [void]$sb.AppendLine("\echo '--- $(Split-Path $path -Leaf) ---'")
    Get-Content $path | ForEach-Object {
        if ($_ -notmatch '^\s*(BEGIN|COMMIT|ROLLBACK)\s*;\s*$' -and $_ -notmatch '^\s*\\set\s+ON_ERROR_STOP') {
            [void]$sb.AppendLine($_)
        }
    }
}
[void]$sb.AppendLine('ROLLBACK;')
Set-Content -Path $dryFile -Value $sb.ToString() -Encoding utf8

$dryLog = Join-Path $OutDir 'dryrun.log'
$dryCode = Invoke-Psql -File $dryFile -LogPath $dryLog
Get-Content $dryLog | Where-Object { $_ -match 'FAIL|ERROR|all checks passed' } | Write-Host
if ($dryCode -ne 0) {
    throw "DRY RUN FAILED (see $dryLog). Nothing has been changed."
}
foreach ($m in $passMarkers) {
    if (-not (Get-Content $dryLog | Where-Object { $_ -match [regex]::Escape($m) })) {
        throw "A check file did not report success ('$m'). Do not apply."
    }
}
$okCount = (Get-Content $dryLog | Where-Object { $_ -match 'NOTICE:\s+ok ' }).Count
Write-Host "Dry run clean -- $okCount checks passed, transaction discarded." -ForegroundColor Green

if (-not $Apply) {
    Write-Host ''
    Write-Host 'Stopping here. Re-run with -Apply to commit (then deploy the API).' -ForegroundColor Yellow
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
}

# --- phase 4: measure after and diff ----------------------------------------
Write-Host ''
Write-Host '=== 4. AFTER ===' -ForegroundColor Cyan
$after   = Join-Path $OutDir 'after.txt'
[void](Invoke-Psql -File $invariantFile -LogPath $after)

Write-Host ''
Write-Host '=== INVARIANTS (expected: identical -- only structure changed) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host "No staff row or login moved. ($((Get-Content $after).Count) lines compared)" -ForegroundColor Green
} else {
    $diff | Select-Object -First 40 | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- 362 links nothing until a user does.' -ForegroundColor Red
}

Write-Host ''
