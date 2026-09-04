# =============================================================================
# Apply migrations 238-241 (expenses as payable documents) to Postgres.
#
# Runs in four phases, and phase 2 is the one that matters:
#
#   1. MEASURE   cash-flow and expense totals per farm, BEFORE anything changes.
#   2. DRY RUN   all four migrations inside a single transaction that is then
#                ROLLED BACK. This validates syntax AND behaviour without
#                committing a row -- the technique database/checks/README.md
#                describes, and how 222-224 were verified before they were ever
#                applied. If this phase fails, nothing has been touched.
#   3. APPLY     the four files in order, each in its own transaction.
#   4. MEASURE   the same totals again and diff them.
#
# 238/239 claim to be a no-op against existing data. Phase 4 is where that claim
# is either true or is not: for poultry every number must be identical. Water is
# the deliberate exception -- 240 turns existing Credit bills into open payables,
# so water supplier balances are EXPECTED to rise. See 240 section 9.
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-expense-payables.ps1                    # measure + dry run only
#   .\apply-expense-payables.ps1 -Apply             # ... then actually apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'expense-payables'),
    # Without this the script measures and dry-runs, then stops. Applying is
    # opt-in on purpose: the dry run is the thing you want to read first.
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files = @('238_PoultryExpensePayables.postgres.sql',
           '239_PoultryCashFlowExpensePaid.postgres.sql',
           '240_WaterExpensePayables.postgres.sql',
           '241_WaterCashFlowExpensePaid.postgres.sql')

foreach ($f in $files) {
    if (-not (Test-Path (Join-Path $MigrationsDir $f))) { throw "Missing migration: $f" }
}

# Redirection is handed to cmd.exe rather than done in PowerShell on purpose.
# PowerShell 5.1 wraps a native command's stderr in ErrorRecords, so a single
# psql NOTICE — of which a successful migration emits several — trips
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
# Deliberately reads the reporting functions rather than the tables: those are
# what the owner actually looks at, and they are what must not move.
$measureSql = @'
\pset footer off
SELECT 'poultry-cashflow' AS metric, f.farmid,
       ROUND(s.moneyin, 2) AS money_in, ROUND(s.moneyout, 2) AS money_out
FROM   (SELECT DISTINCT farmid FROM poultrycashaccounts) f
CROSS  JOIN LATERAL sppoultrycashflow_summary(f.farmid, NULL, NULL) s
ORDER  BY f.farmid;

SELECT 'poultry-expense-total' AS metric, lower(e.farmid::text) AS farmid,
       ROUND(SUM(e.amount), 2) AS total
FROM   expense e GROUP BY 2 ORDER BY 2;

SELECT 'poultry-supplier-balance' AS metric, f.farmid,
       ROUND(COALESCE(SUM(b.totalbalance), 0), 2) AS balance
FROM   (SELECT DISTINCT farmid FROM supplier) f
CROSS  JOIN LATERAL sppoultrysupplierbalances(f.farmid) b
GROUP  BY f.farmid ORDER BY f.farmid;

SELECT 'water-cashflow' AS metric, f.farmid,
       ROUND(s.moneyin, 2) AS money_in, ROUND(s.moneyout, 2) AS money_out
FROM   (SELECT DISTINCT farmid FROM watercashaccounts) f
CROSS  JOIN LATERAL spwatercashflow_summary(f.farmid, NULL, NULL) s
ORDER  BY f.farmid;

SELECT 'water-supplier-balance' AS metric, f.farmid,
       ROUND(COALESCE(SUM(b.totalbalance), 0), 2) AS balance
FROM   (SELECT DISTINCT farmid FROM watersuppliers) f
CROSS  JOIN LATERAL spwatersupplierbalances(f.farmid) b
GROUP  BY f.farmid ORDER BY f.farmid;
'@

$measureFile = Join-Path $OutDir 'measure.sql'
Set-Content -Path $measureFile -Value $measureSql -Encoding utf8

Write-Host "Host:     $DbHost/$Database"
Write-Host "Migrations: $($files -join ', ')"
Write-Host ""

# --- phase 1: measure before -------------------------------------------------
Write-Host '=== 1. BEFORE ===' -ForegroundColor Cyan
$before = Join-Path $OutDir 'before.txt'
if ((Invoke-Psql -File $measureFile -LogPath $before) -ne 0) {
    Get-Content $before | Write-Host
    throw 'Could not read the baseline. Nothing has been changed.'
}
Get-Content $before | Write-Host

# --- phase 2: dry run, rolled back ------------------------------------------
# The files carry their own BEGIN;/COMMIT; and \set ON_ERROR_STOP. Strip both so
# all four run inside ONE transaction this script controls and then discards.
Write-Host ''
Write-Host '=== 2. DRY RUN (rolled back) ===' -ForegroundColor Cyan
$dryFile = Join-Path $OutDir 'dryrun.sql'
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('BEGIN;')
foreach ($f in $files) {
    [void]$sb.AppendLine("\echo '--- $f ---'")
    Get-Content (Join-Path $MigrationsDir $f) | ForEach-Object {
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
Write-Host 'Dry run clean — syntax and behaviour validated, transaction discarded.' -ForegroundColor Green

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
        throw "$f failed (see $log). Migrations before it are committed; this one rolled back."
    }
    Write-Host '  ok' -ForegroundColor Green
}

# --- phase 4: measure after and diff ----------------------------------------
Write-Host ''
Write-Host '=== 4. AFTER ===' -ForegroundColor Cyan
$after = Join-Path $OutDir 'after.txt'
[void](Invoke-Psql -File $measureFile -LogPath $after)
Get-Content $after | Write-Host

Write-Host ''
Write-Host '=== DIFF (expected: poultry rows identical; water supplier balance may rise) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host 'No change to any measured total.' -ForegroundColor Green
} else {
    $diff | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Check every line above is a water supplier balance. A poultry line here is a bug.' -ForegroundColor Yellow
}
