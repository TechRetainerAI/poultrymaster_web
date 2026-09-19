# =============================================================================
# Apply migration 315 (an entry time on every Financial Activity row) to
# Postgres.
#
# Same four phases as the other apply scripts, but phase 1 measures something
# unusual, and deliberately:
#
#   1. MEASURE   EVERY EXISTING COLUMN OF EVERY ACTIVITY ROW, for every poultry
#                company -- not a set of totals.
#   2. DRY RUN   the migration plus its behavioural checks inside a single
#                transaction that is then ROLLED BACK.
#   3. APPLY     the migration in its own transaction.
#   4. MEASURE   the same rows again and diff them.
#
# WHY ROW-BY-ROW RATHER THAN TOTALS
# ---------------------------------
# This migration rebuilds the function that Financial Activity, its summary and
# Running Cash are all computed from. `occurredat` is inside the window that
# computes Running Cash and inside the array_agg that decides which leg an event
# takes its description and date from. A mistake there would not change a TOTAL
# -- the same money would still be there -- it would REORDER rows and hand a
# different running balance to every line after the first one.
#
# Totals cannot see that. The full row set can. So the measurement dumps
# eventkey, both dates, type, category, description, all four money columns,
# profit impact and running cash for every row, and phase 4 must print "No
# change to any measured row."
#
# `createdat` is excluded from the measurement on purpose: it does not exist
# before the migration, so asking for it in phase 1 would simply fail.
#
# EFFECT ON TODAY'S NUMBERS: none. One added column.
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-financial-activity-entry-time.ps1                 # measure + dry run
#   .\apply-financial-activity-entry-time.ps1 -Apply          # ... then apply
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
    [string] $ChecksDir = (Join-Path $PSScriptRoot 'checks'),
    [string] $OutDir   = (Join-Path $env:TEMP 'fa-entry-time'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files = @('315_PoultryFinancialActivityEntryTime.postgres.sql')
foreach ($f in $files) {
    if (-not (Test-Path (Join-Path $MigrationsDir $f))) { throw "Missing migration: $f" }
}

$checkFiles = @((Join-Path $ChecksDir 'poultry-financial-activity-entry-time.test.sql'))
foreach ($c in $checkFiles) {
    if (-not (Test-Path $c)) { throw "Missing check file: $c" }
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

# --- the same measurement, before and after ---------------------------------
# Every pre-existing column of every row, ordered deterministically so a diff is
# a diff and not a re-sort.
$measureSql = @'
\pset footer off
\pset pager off
SELECT f.farmid,
       g.eventkey, g.businessdate, g.occurredat, g.activitytype, g.type,
       g.category, g.description, g.sourcetype, g.sourceid, g.sourcenumber,
       g.moneyin, g.moneyout, g.revenue, g.expense, g.profitimpact,
       g.runningcash, g.iscash, g.isnoncash, g.istransfer,
       g.cashaccountid, g.cashaccountname, g.partyname, g.plline, g.status
FROM   farms f
CROSS  JOIN LATERAL public.sppoultryfinancialactivity_get(f.farmid, '2000-01-01', '2099-12-31') g
WHERE  f.type = 'Poultry'
ORDER  BY f.farmid, g.businessdate, g.occurredat, g.eventkey;
'@

$measureFile = Join-Path $OutDir 'measure.sql'
Set-Content -Path $measureFile -Value $measureSql -Encoding utf8

Write-Host "Host:       $DbHost/$Database"
Write-Host "Migration:  $($files -join ', ')"
Write-Host ""

# --- phase 1: measure before -------------------------------------------------
Write-Host '=== 1. BEFORE ===' -ForegroundColor Cyan
$before = Join-Path $OutDir 'before.txt'
if ((Invoke-Psql -File $measureFile -LogPath $before) -ne 0) {
    Get-Content $before | Write-Host
    throw 'Could not read the baseline. Nothing has been changed.'
}
$beforeRows = (Get-Content $before).Count
Write-Host "  $beforeRows line(s) of activity captured" -ForegroundColor Gray

# --- phase 2: dry run, rolled back ------------------------------------------
Write-Host ''
Write-Host '=== 2. DRY RUN (rolled back) ===' -ForegroundColor Cyan
$dryFile = Join-Path $OutDir 'dryrun.sql'
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('BEGIN;')
foreach ($f in ($files + $checkFiles)) {
    $path = if (Test-Path $f) { $f } else { Join-Path $MigrationsDir $f }
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

# The checks report as NOTICEs reading "expect X got Y". These three must be
# zero or the migration has broken something it was not allowed to touch.
$mustBeZero = Get-Content $dryLog |
    Where-Object { $_ -match 'expect (0|0\.00) (difference )?got' } |
    Where-Object { $_ -notmatch 'got (0|0\.00)\s*$' }
if ($mustBeZero) {
    $mustBeZero | Write-Host -ForegroundColor Red
    throw 'A zero-difference assertion did not hold. Do not apply.'
}
# And the leg that lives on another branch must have survived the rebuild.
# Anchored on the D1 label, not on the words: the migration's own verification
# block prints a line about the same leg in a different shape, and matching both
# made this guard fire on a clean run.
$leg = Get-Content $dryLog | Where-Object { $_ -match 'D1\. the payroll repayment leg' }
if (-not $leg) {
    throw 'The payroll-leg assertion did not run at all. Do not apply.'
}
if ($leg -notmatch 'got 1\s*$') {
    $leg | Write-Host -ForegroundColor Red
    throw 'The employee-loan payroll leg was lost in the rebuild. Do not apply.'
}
$leg | Write-Host -ForegroundColor Green

Write-Host 'Dry run clean -- syntax and behaviour validated, transaction discarded.' -ForegroundColor Green
Write-Host 'Read the "expect X got Y" lines above: every one must agree.' -ForegroundColor Yellow

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
}

# --- phase 4: measure after and diff ----------------------------------------
Write-Host ''
Write-Host '=== 4. AFTER ===' -ForegroundColor Cyan
$after = Join-Path $OutDir 'after.txt'
[void](Invoke-Psql -File $measureFile -LogPath $after)
$afterRows = (Get-Content $after).Count
Write-Host "  $afterRows line(s) of activity captured" -ForegroundColor Gray

Write-Host ''
Write-Host '=== DIFF (expected: identical -- one added column, nothing rewritten) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host "No change to any measured row. ($afterRows lines compared)" -ForegroundColor Green
} else {
    $diff | Select-Object -First 40 | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- 315 adds a column and rewrites nothing.' -ForegroundColor Red
}
