# =============================================================================
# Apply migrations 242-244 (Generic business templates, subscriptions and
# billing, customer balances) to Postgres.
#
# Same four phases as apply-expense-payables.ps1, and phase 2 is again the one
# that matters:
#
#   1. MEASURE   every Generic company's sales, expenses, cash, customer
#                balances and P&L totals, BEFORE anything changes.
#   2. DRY RUN   all three migrations PLUS the behavioural check file inside a
#                single transaction that is then ROLLED BACK. This validates
#                syntax AND behaviour without committing a row.
#   3. APPLY     the three files in order, each in its own transaction.
#   4. MEASURE   the same totals again and diff them.
#
# EFFECT ON TODAY'S NUMBERS: none. All three migrations only add columns,
# tables and functions; nothing rewrites an existing row. Phase 4 must print
# "No change to any measured total." Anything else is a bug, with no
# exceptions -- unlike 238-241, there is no expected-to-move line here.
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-generic-subscriptions.ps1                 # measure + dry run only
#   .\apply-generic-subscriptions.ps1 -Apply          # ... then actually apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'generic-subscriptions'),
    # Without this the script measures and dry-runs, then stops. Applying is
    # opt-in on purpose: the dry run is the thing you want to read first.
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files = @('242_GenericBusinessTemplates.postgres.sql',
           '243_GenericSubscriptionsAndBilling.postgres.sql',
           '244_GenericCustomerBalances.postgres.sql')

foreach ($f in $files) {
    if (-not (Test-Path (Join-Path $MigrationsDir $f))) { throw "Missing migration: $f" }
}

$checkFile = Join-Path $ChecksDir 'generic-subscription-billing.test.sql'
if (-not (Test-Path $checkFile)) { throw "Missing check file: $checkFile" }

# Redirection is handed to cmd.exe rather than done in PowerShell on purpose.
# PowerShell 5.1 wraps a native command's stderr in ErrorRecords, so a single
# psql NOTICE -- of which a successful migration emits several -- trips
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
# Reads the reporting function as well as the tables: spgenericreport_periodpnl
# is what the owner actually looks at, and it is what must not move.
$measureSql = @'
\pset footer off
SELECT 'generic' AS metric, f.farmid, f.name,
       (SELECT COUNT(*) FROM genericsales s
         WHERE s.farmid = f.farmid AND NOT COALESCE(s.isdeleted, FALSE))                        AS sales,
       (SELECT ROUND(COALESCE(SUM(s.totalamount), 0), 2) FROM genericsales s
         WHERE s.farmid = f.farmid AND NOT COALESCE(s.isdeleted, FALSE))                        AS sales_amount,
       (SELECT ROUND(COALESCE(SUM(s.balance), 0), 2) FROM genericsales s
         WHERE s.farmid = f.farmid AND NOT COALESCE(s.isdeleted, FALSE))                        AS sales_balance,
       (SELECT COUNT(*) FROM genericexpenses e
         WHERE e.farmid = f.farmid AND NOT COALESCE(e.isdeleted, FALSE))                        AS expenses,
       (SELECT ROUND(COALESCE(SUM(e.amount), 0), 2) FROM genericexpenses e
         WHERE e.farmid = f.farmid AND NOT COALESCE(e.isdeleted, FALSE))                        AS expense_amount,
       (SELECT ROUND(COALESCE(SUM(c.currentbalance), 0), 2) FROM genericcashaccounts c
         WHERE c.farmid = f.farmid)                                                             AS cash,
       (SELECT ROUND(COALESCE(SUM(k.currentbalance), 0), 2) FROM genericcustomers k
         WHERE k.farmid = f.farmid)                                                             AS customer_balance,
       (SELECT COUNT(*) FROM genericservices v WHERE v.farmid = f.farmid)                       AS services,
       (SELECT COUNT(*) FROM genericservicecategories g WHERE g.farmid = f.farmid)              AS service_categories,
       (SELECT ROUND(COALESCE(SUM(p.totalincome), 0), 2)
          FROM spgenericreport_periodpnl(f.farmid, '2000-01-01', '2099-12-31') p)               AS pnl_income,
       (SELECT ROUND(COALESCE(SUM(p.netprofit), 0), 2)
          FROM spgenericreport_periodpnl(f.farmid, '2000-01-01', '2099-12-31') p)               AS pnl_net
FROM   farms f
WHERE  f.type = 'Generic'
ORDER  BY f.farmid;
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
# all three -- and the behavioural checks that follow them -- run inside ONE
# transaction this script controls and then discards.
Write-Host ''
Write-Host '=== 2. DRY RUN (rolled back) ===' -ForegroundColor Cyan
$dryFile = Join-Path $OutDir 'dryrun.sql'
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('BEGIN;')
foreach ($f in ($files + @($checkFile))) {
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

# The checks report themselves as NOTICEs reading "expect X got Y". Surface any
# that a human should look at rather than trusting the exit code alone.
$suspect = Get-Content $dryLog | Where-Object { $_ -match '<-- BUG, allowed' }
if ($suspect) {
    $suspect | Write-Host -ForegroundColor Red
    throw 'A negative case was NOT blocked. Read the dry-run log before applying.'
}
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
Write-Host '=== DIFF (expected: identical -- these migrations add, they do not rewrite) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host 'No change to any measured total.' -ForegroundColor Green
} else {
    $diff | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- nothing in 242-244 should move an existing number.' -ForegroundColor Red
}
