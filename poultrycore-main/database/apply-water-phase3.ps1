# =============================================================================
# Apply the Water Phase 3 financial architecture (migrations 282+) to Postgres.
#
#   -Stage 1   282  financial cost type: WHAT kind of cost a row is, and which
#                   Profit & Loss line it belongs on -- structure first, keyword
#                   last
#   -Stage 2   283  capital assets: categories, the asset register, acquisition
#                   and additional capitalised costs
#   -Stage 3   284  straight-line depreciation, posted as a non-cash expense
#   -Stage 4   285  the Profit & Loss rewrite  <-- NOT YET WRITTEN, see below
#   -Stage 5   286  permissions
#
# The four phases, as in apply-water-money.ps1:
#
#   1. MEASURE   every water company's expense total, expense row count,
#                raw-material stock and cash, BEFORE anything changes.
#   2. DRY RUN   the migration PLUS the behavioural check file inside a single
#                transaction that is then ROLLED BACK.
#   3. APPLY     the migration in its own transaction.
#   4. MEASURE   the same totals again and diff them.
#
# STAGE 4 IS NOT AVAILABLE YET, AND THE SCRIPT WILL SAY SO
# ========================================================
# 285 rewrites spwaterreport_periodpnl. Unlike the poultry side -- where 207 had
# restored the Postgres bodies into the repo before 272 rewrote them -- water's
# live Postgres SP bodies were ported outside version control. The repo holds
# only the pre-migration T-SQL (103_FixPeriodPnL.sql, 105_PnLIncludeDriver
# ReturnIncome.sql), and rewriting the report from those would silently drop
# whatever the live port actually does.
#
# So stage 4 is deliberately absent rather than guessed at. Running it throws
# "Missing migration", which is the correct outcome: the fix is to dump the live
# body, not to invent one.
#
# WHY THE MEASURE DOES NOT READ THE P&L REPORT
# ============================================
# apply-poultry-phase3.ps1 baselines sppoultryreport_profitloss's own total,
# because that is the number an owner looks at. The water equivalent's Postgres
# signature is not in this repo to call, for the reason above. So the baseline
# reads the BASE TABLES instead -- approved expense total, cash, purchases,
# stock. Those are the inputs the report is built from, so anything that moves
# the report without a company asking will move one of them too, and the diff
# still catches it. It is a weaker measure than poultry's and that is worth
# knowing rather than glossing over.
#
# EFFECT ON TODAY'S NUMBERS: none, at every stage listed here. Stages 1-3 and 5
# add classification, a register, a depreciation ledger and permissions; nothing
# existing moves. Every one must print "No change to any measured total."
#
# The one number that CAN move is at stage 4, when it lands: 285 rewrites the
# report, and the whole point is that the report changes.
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-water-phase3.ps1 -Stage 1
#   .\apply-water-phase3.ps1 -Stage 1 -Apply
#
# Requires the dev machine's public IP to be on the Cloud SQL authorized-networks
# list, or every psql call times out. See the cloudsql-ip-allowlist note.
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 5)]
    [int]    $Stage,
    [string] $DbHost   = '34.175.134.7',
    [int]    $Port     = 5432,
    [string] $Database = 'VisibilityCoreDB',
    [string] $User     = 'poultryapp',
    [string] $Psql     = 'C:\Program Files\PostgreSQL\18\bin\psql.exe',
    [string] $MigrationsDir = (Join-Path $PSScriptRoot '..\..\poultrycore_Backend\PoultryFarmAPI\Migrations'),
    [string] $ChecksDir = (Join-Path $PSScriptRoot 'checks'),
    [string] $OutDir   = (Join-Path $env:TEMP 'water-phase3'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }

$stages = @{
    1 = @{ Migration = '282_WaterFinancialCostType.postgres.sql'; Check = 'water-financial-cost-type.test.sql' }
    2 = @{ Migration = '283_WaterCapitalAssets.postgres.sql';     Check = 'water-capital-assets.test.sql' }
    3 = @{ Migration = '284_WaterAssetDepreciation.postgres.sql'; Check = 'water-asset-depreciation.test.sql' }
    4 = @{ Migration = '285_WaterProfitLossRedesign.postgres.sql'; Check = 'water-profit-loss-redesign.test.sql' }
    5 = @{ Migration = '286_WaterAssetPermissions.postgres.sql';  Check = 'water-asset-permissions.test.sql' }
}
$plan = $stages[$Stage]
$files = @($plan.Migration)
$OutDir = Join-Path $OutDir "stage$Stage"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

foreach ($f in $files) {
    if (-not (Test-Path (Join-Path $MigrationsDir $f))) {
        if ($Stage -eq 4) {
            throw "Stage 4 (285) has not been written yet -- it needs the live spwaterreport_periodpnl body, which is not in this repo. See the header."
        }
        throw "Missing migration: $f"
    }
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
# Base tables, not the report. See the header for why.
$measureSql = @'
\pset footer off
SELECT 'water' AS metric, f.farmid, f.name,
       (SELECT COUNT(*) FROM waterrawmaterialitems i WHERE i.farmid = f.farmid)               AS items,
       (SELECT ROUND(COALESCE(SUM(i.currentquantity), 0), 2) FROM waterrawmaterialitems i
         WHERE i.farmid = f.farmid)                                                            AS stock_qty,
       (SELECT COUNT(*) FROM waterrawmaterialpurchases pu WHERE pu.farmid = f.farmid)          AS purchases,
       (SELECT ROUND(COALESCE(SUM(pu.totalcost), 0), 2) FROM waterrawmaterialpurchases pu
         WHERE pu.farmid = f.farmid)                                                           AS purchase_cost,
       (SELECT ROUND(COALESCE(SUM(pu.amountpaid), 0), 2) FROM waterrawmaterialpurchases pu
         WHERE pu.farmid = f.farmid)                                                           AS purchase_paid,
       (SELECT COUNT(*) FROM waterexpenses e
         WHERE e.farmid = f.farmid AND COALESCE(e.isdeleted, FALSE) = FALSE)                   AS expense_rows,
       (SELECT ROUND(COALESCE(SUM(e.amount), 0), 2) FROM waterexpenses e
         WHERE e.farmid = f.farmid AND COALESCE(e.isdeleted, FALSE) = FALSE)                   AS expense_total,
       -- The P&L input: only Approved bills have been recognised at all (047).
       (SELECT ROUND(COALESCE(SUM(e.amount), 0), 2) FROM waterexpenses e
         WHERE e.farmid = f.farmid AND COALESCE(e.isdeleted, FALSE) = FALSE
           AND COALESCE(e.status, '') = 'Approved')                                            AS approved_expense,
       (SELECT ROUND(COALESCE(SUM(a.currentbalance), 0), 2) FROM watercashaccounts a
         WHERE a.farmid = f.farmid)                                                            AS cash,
       -- What the company is owed-out on. 283 widens fnwaterpayables, so this is
       -- the number that would show it if the widening admitted anything it
       -- should not have.
       (SELECT ROUND(COALESCE(SUM(p.balance), 0), 2) FROM fnwaterpayables(f.farmid) p)         AS payables
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
# the exit code: a resolver that returns the WRONG answer still returns cleanly.
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
    Get-Content $log | Write-Host
}

# --- phase 4: measure after and diff ----------------------------------------
Write-Host ''
Write-Host '=== 4. AFTER ===' -ForegroundColor Cyan
$after = Join-Path $OutDir 'after.txt'
[void](Invoke-Psql -File $measureFile -LogPath $after)
Get-Content $after | Write-Host

Write-Host ''
Write-Host '=== DIFF (expected: identical at every stage in this script) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host 'No change to any measured total.' -ForegroundColor Green
} else {
    $diff | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'A moved approved_expense or payables here is the serious one: it means a company''s numbers changed without anyone choosing it.' -ForegroundColor Red
}

Write-Host ''
Write-Host 'RESTART THE API when the backend stages land.' -ForegroundColor Yellow
