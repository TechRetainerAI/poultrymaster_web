# =============================================================================
# Apply the Water money-control layer (migrations 257-260) to Postgres.
#
# One script for the four stages rather than four near-identical ones, because
# the phases and the measurement are the same every time and only the file pair
# changes:
#
#   -Stage 1   257  cash transfer reversal        water-cash-transfer-reversal
#   -Stage 2   258  owner money                   water-owner-money
#   -Stage 3   259  loans and repayments          water-loans
#   -Stage 4   260  permissions                   water-money-permissions
#
# The four phases, unchanged from apply-poultry-cash-transfer-reversal.ps1:
#
#   1. MEASURE   every Water company's cash accounts, balances, ledger rows,
#                transfers and cash-flow totals, BEFORE anything changes.
#   2. DRY RUN   the migration PLUS the behavioural check file inside a single
#                transaction that is then ROLLED BACK. This validates syntax
#                AND behaviour without committing a row.
#   3. APPLY     the migration in its own transaction.
#   4. MEASURE   the same totals again and diff them.
#
# EFFECT ON TODAY'S NUMBERS: none, at every stage. 257 adds columns and
# functions; 258 and 259 add tables and cash-flow arms that return nothing until
# a record exists; 260 only grants. Phase 4 must print "No change to any
# measured total." at every stage -- anything else is a bug, not a surprise.
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-water-money.ps1 -Stage 1            # measure + dry run only
#   .\apply-water-money.ps1 -Stage 1 -Apply     # ... then actually apply
#
# Requires the dev machine's public IP to be on the Cloud SQL authorized-networks
# list, or every psql call times out. See the cloudsql-ip-allowlist note.
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 4)]
    [int]    $Stage,
    [string] $DbHost   = '34.175.134.7',
    [int]    $Port     = 5432,
    [string] $Database = 'VisibilityCoreDB',
    [string] $User     = 'poultryapp',
    [string] $Psql     = 'C:\Program Files\PostgreSQL\18\bin\psql.exe',
    [string] $MigrationsDir = (Join-Path $PSScriptRoot '..\..\poultrycore_Backend\PoultryFarmAPI\Migrations'),
    [string] $ChecksDir = (Join-Path $PSScriptRoot 'checks'),
    [string] $OutDir   = (Join-Path $env:TEMP 'water-money'),
    # Without this the script measures and dry-runs, then stops. Applying is
    # opt-in on purpose: the dry run is the thing you want to read first.
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }

$stages = @{
    1 = @{ Migration = '257_WaterCashTransferReversal.postgres.sql'; Check = 'water-cash-transfer-reversal.test.sql' }
    2 = @{ Migration = '258_WaterOwnerMoney.postgres.sql';           Check = 'water-owner-money.test.sql' }
    3 = @{ Migration = '259_WaterLoans.postgres.sql';                Check = 'water-loans.test.sql' }
    4 = @{ Migration = '260_WaterMoneyPermissions.postgres.sql';     Check = 'water-money-permissions.test.sql' }
}
$plan = $stages[$Stage]
$files = @($plan.Migration)
$OutDir = Join-Path $OutDir "stage$Stage"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

foreach ($f in $files) {
    if (-not (Test-Path (Join-Path $MigrationsDir $f))) { throw "Missing migration: $f" }
}

$checkFile = Join-Path $ChecksDir $plan.Check
if (-not (Test-Path $checkFile)) { throw "Missing check file: $checkFile" }

# Redirection is handed to cmd.exe rather than done in PowerShell on purpose.
# PowerShell 5.1 wraps a native command's stderr in ErrorRecords, so a single
# psql NOTICE -- of which these dry runs emit dozens -- trips
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
# Reads the cash-flow function as well as the tables: spwatercashflow_summary is
# what the owner actually looks at, and it is what must not move.
#
# The farm filter is `type = 'Water'` AND `has water cash accounts`. Both halves
# matter -- watercashtransfers also holds rows for a Generic company built on
# the water rail, and including it would make the baseline noisy without
# telling anyone anything.
$measureSql = @'
\pset footer off
SELECT 'water' AS metric, f.farmid, f.name,
       (SELECT COUNT(*) FROM watercashaccounts a WHERE a.farmid = f.farmid)                     AS accounts,
       (SELECT ROUND(COALESCE(SUM(a.currentbalance), 0), 2) FROM watercashaccounts a
         WHERE a.farmid = f.farmid)                                                             AS cash,
       (SELECT COUNT(*) FROM watercashtransactions t WHERE t.farmid = f.farmid)                 AS ledger_rows,
       (SELECT ROUND(COALESCE(SUM(t.amount), 0), 2) FROM watercashtransactions t
         WHERE t.farmid = f.farmid)                                                             AS ledger_net,
       (SELECT COUNT(*) FROM watercashtransfers x WHERE x.farmid = f.farmid)                    AS transfers,
       (SELECT COUNT(*) FROM watercashtransfers x
         WHERE x.farmid = f.farmid AND x.status = 'Approved')                                   AS approved_transfers,
       (SELECT ROUND(COALESCE(s.moneyin, 0), 2)
          FROM spwatercashflow_summary(f.farmid, NULL, NULL) s)                                 AS money_in,
       (SELECT ROUND(COALESCE(s.moneyout, 0), 2)
          FROM spwatercashflow_summary(f.farmid, NULL, NULL) s)                                 AS money_out,
       (SELECT ROUND(COALESCE(s.netcashflow, 0), 2)
          FROM spwatercashflow_summary(f.farmid, NULL, NULL) s)                                 AS net_flow,
       (SELECT ROUND(COALESCE(SUM(e.amount), 0), 2) FROM waterexpenses e
         WHERE e.farmid = f.farmid AND e.status = 'Approved'
           AND COALESCE(e.isdeleted, FALSE) = FALSE)                                            AS approved_expense
FROM   farms f
WHERE  f.type = 'Water'
  AND  EXISTS (SELECT 1 FROM watercashaccounts a WHERE a.farmid = f.farmid)
ORDER  BY f.farmid;
'@

$measureFile = Join-Path $OutDir 'measure.sql'
Set-Content -Path $measureFile -Value $measureSql -Encoding utf8

Write-Host "Host:       $DbHost/$Database"
Write-Host "Stage:      $Stage  ($($plan.Migration))"
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
# the migration AND the behavioural checks run inside ONE transaction this
# script controls and then discards.
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

# Every check line reads "expect X got Y". Compare the two rather than trusting
# the exit code: a report that returns the WRONG number still returns cleanly.
# 0 and 0.00 are the same number written two ways, so they are normalised.
$mismatch = Get-Content $dryLog | Where-Object {
    if ($_ -match 'expect\s+(\S+)\s+got\s+(\S+)\s*$') {
        $a = $matches[1]; $b = $matches[2]
        if ($a -as [decimal] -ne $null -and $b -as [decimal] -ne $null) {
            [decimal]$a -ne [decimal]$b
        } else { $a -ne $b }
    } else { $false }
}
if ($mismatch) {
    $mismatch | Write-Host -ForegroundColor Red
    throw 'A check did not get what it expected. Read the dry-run log before applying.'
}

# The negative cases report themselves rather than failing the script, so an
# unblocked one would otherwise pass silently.
$allowed = Get-Content $dryLog | Where-Object { $_ -match '<-- BUG, allowed' }
if ($allowed) {
    $allowed | Write-Host -ForegroundColor Red
    throw 'A negative case was NOT blocked. Read the dry-run log before applying.'
}
Write-Host 'Dry run clean -- every "expect X got Y" agrees, transaction discarded.' -ForegroundColor Green

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
        throw "$f failed (see $log). It rolled back; nothing is half-applied."
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
Write-Host '=== DIFF (expected: identical -- balances and cash flow must not move) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host 'No change to any measured total.' -ForegroundColor Green
} else {
    $diff | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- these migrations add structure, they move no money.' -ForegroundColor Red
}

Write-Host ''
Write-Host 'RESTART THE API. New actions and new columns; a running' -ForegroundColor Yellow
Write-Host 'PoultryFarmAPI.exe serves neither.' -ForegroundColor Yellow
