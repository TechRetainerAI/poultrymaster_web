# =============================================================================
# Apply migration 347 (Flock Lifecycle Assistant) to Postgres.
#
#   1. MEASURE   every flock and batch row, and every existing IAM grant.
#   2. DRY RUN   the migration AND checks/poultry-flock-lifecycle.test.sql inside
#                one transaction that is then ROLLED BACK.
#   3. APPLY     the migration in its own transaction.
#   4. MEASURE   again and diff.
#
# 347 adds five empty tables, functions and four IAM keys (with grants copied
# from the poultry.flocks keys). It touches no existing row, so phase 4 must
# print "No change" for flocks, batches and every grant that existed before.
#
# Usage (password from the environment, never on the command line):
#   $env:PGPASSWORD = '<password>'
#   .pply-flock-lifecycle.ps1            # measure + dry run
#   .pply-flock-lifecycle.ps1 -Apply     # ... then apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'flock-lifecycle'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files  = @('347_PoultryFlockLifecycle.postgres.sql')
$checks = @('poultry-flock-lifecycle.test.sql')
foreach ($f in $files)  { if (-not (Test-Path (Join-Path $MigrationsDir $f))) { throw "Missing migration: $f" } }
foreach ($c in $checks) { if (-not (Test-Path (Join-Path $ChecksDir $c)))     { throw "Missing check: $c" } }

# Redirection is handed to cmd.exe rather than done in PowerShell on purpose.
# PowerShell 5.1 wraps a native command's stderr in ErrorRecords, so a single
# psql NOTICE -- of which the checks emit about a hundred -- trips
# $ErrorActionPreference and aborts a run that was going fine.
function Invoke-Psql {
    param([string] $File, [string] $LogPath, [string] $Extra = '')
    $line = '"{0}" -h {1} -p {2} -U {3} -d {4} -X -w -v ON_ERROR_STOP=1 {6} -f "{5}"' -f `
            $Psql, $DbHost, $Port, $User, $Database, $File, $Extra
    if ($LogPath) { $line += ' > "{0}" 2>&1' -f $LogPath }
    & cmd.exe /c $line
    return $LASTEXITCODE
}

# --- the measurement, before and after ----------------------------------------
# Grants are filtered to keys that existed before 347, so the new lifecycle
# grants do not show up as a "change".
$measureSql = @'
\pset footer off
\pset pager off
\echo '-- flocks'
SELECT flockid, farmid, name, breed, startdate, quantity, active, batchid, houseid, hasarrived, closeddate, isdeleted
FROM   public.flock ORDER BY flockid;
\echo '-- batches'
SELECT batchid, farmid, batchcode, breed, startdate, numberofbirds FROM public.mainflockbatch ORDER BY batchid;
\echo '-- role grants (pre-347 keys)'
SELECT roleid, permissionkey FROM public.iamrolepermissions
WHERE  permissionkey NOT LIKE 'poultry.lifecycle.%' ORDER BY roleid, permissionkey;
'@
$measureFile = Join-Path $OutDir 'measure.sql'
Set-Content -Path $measureFile -Value $measureSql -Encoding utf8

Write-Host "Host:       $DbHost/$Database"
Write-Host "Migration:  $($files -join ', ')"
Write-Host "Checks:     $($checks -join ', ')"
Write-Host ''

# --- phase 1: measure before -------------------------------------------------
Write-Host '=== 1. BEFORE ===' -ForegroundColor Cyan
$before = Join-Path $OutDir 'before.txt'
if ((Invoke-Psql -File $measureFile -LogPath $before) -ne 0) {
    Get-Content $before | Write-Host
    throw 'Could not read the baseline. Nothing has been changed.'
}
Write-Host "  $((Get-Content $before).Count) line(s) captured" -ForegroundColor Gray

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
Get-Content $dryLog | Where-Object { $_ -match 'FAIL|ERROR|all checks passed|347:' } | Write-Host
if ($dryCode -ne 0) {
    throw "DRY RUN FAILED (see $dryLog). Nothing has been changed."
}
$passed = Get-Content $dryLog | Where-Object { $_ -match 'poultry-flock-lifecycle: all checks passed' }
if (-not $passed) {
    throw 'The lifecycle checks did not report success. Do not apply.'
}
$okCount = (Get-Content $dryLog | Where-Object { $_ -match 'NOTICE:\s+ok ' }).Count
Write-Host "Dry run clean -- $okCount checks passed, transaction discarded." -ForegroundColor Green

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
Write-Host '=== DIFF (expected: identical -- 347 touches no existing row) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host "No change to any flock, batch or existing grant. ($((Get-Content $after).Count) lines compared)" -ForegroundColor Green
} else {
    $diff | Select-Object -First 40 | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- 347 must not change existing data.' -ForegroundColor Red
}
