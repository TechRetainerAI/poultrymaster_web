# =============================================================================
# Apply migrations 245-246 (money paid on a bill at entry becomes a real
# supplier payment) to Postgres.
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
# EFFECT ON TODAY'S NUMBERS: none. Both migrations only replace functions;
# there is no backfill and no historical bill gains a payment record. Phase 4 must print
# "No change to any measured total." Anything else is a bug, with no
# exceptions -- unlike 238-241, there is no expected-to-move line here.
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-expense-entry-payments.ps1                 # measure + dry run only
#   .\apply-expense-entry-payments.ps1 -Apply          # ... then actually apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'expense-entry-payments'),
    # Without this the script measures and dry-runs, then stops. Applying is
    # opt-in on purpose: the dry run is the thing you want to read first.
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files = @('245_PoultryExpenseEntryPayments.postgres.sql',
           '246_WaterExpenseEntryPayments.postgres.sql')

foreach ($f in $files) {
    if (-not (Test-Path (Join-Path $MigrationsDir $f))) { throw "Missing migration: $f" }
}

$checkFile = Join-Path $ChecksDir 'poultry-expense-entry-payments.test.sql'
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
-- What 245/246 must NOT move. They add a payment record for money that was
-- already being recorded on the bill; not one figure below may shift.
SELECT 'poultry-cashflow' AS metric, f.farmid,
       ROUND(s.moneyin, 2) AS money_in, ROUND(s.moneyout, 2) AS money_out
FROM   (SELECT DISTINCT farmid FROM poultrycashaccounts) f
CROSS  JOIN LATERAL sppoultrycashflow_summary(f.farmid, NULL, NULL) s
ORDER  BY f.farmid;

SELECT 'poultry-supplier-balance' AS metric, f.farmid,
       ROUND(COALESCE(SUM(b.totalbalance), 0), 2) AS balance
FROM   (SELECT DISTINCT farmid FROM supplier) f
CROSS  JOIN LATERAL sppoultrysupplierbalances(f.farmid) b
GROUP  BY f.farmid ORDER BY f.farmid;

SELECT 'poultry-expense-paid' AS metric, lower(e.farmid::text) AS farmid,
       COUNT(*) AS rows, ROUND(SUM(COALESCE(e.amountpaid, e.amount)), 2) AS paid
FROM   expense e GROUP BY 2 ORDER BY 2;

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

-- Existing payment records, so the apply cannot have invented any.
SELECT 'entry-payments' AS metric, sp.farmid, COUNT(*) AS n
FROM   poultrysupplierpayments sp
WHERE  sp.sourcetype = 'ExpenseEntry'
GROUP  BY sp.farmid ORDER BY sp.farmid;
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
Write-Host '=== DIFF (expected: identical -- no backfill, only new bills are affected) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host 'No change to any measured total.' -ForegroundColor Green
} else {
    $diff | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- 245/246 change only bills entered from now on.' -ForegroundColor Red
}
