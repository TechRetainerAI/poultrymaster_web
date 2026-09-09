# =============================================================================
# Apply the Poultry Phase 3 financial architecture (migrations 269+) to Postgres.
#
#   -Stage 1   269  financial cost type: WHAT kind of cost a row is, and which
#                   Profit & Loss line it belongs on -- structure first, keyword
#                   last
#   -Stage 2   270  capital assets: categories, the asset register, acquisition
#                   and additional capitalised costs
#   -Stage 3   271  straight-line depreciation, posted as a non-cash expense
#   -Stage 4   272  the Profit & Loss rewrite: Gross / Operating / Net Profit,
#                   financing & owner activity, capital investments, drilldowns
#   -Stage 5   273  permissions
#
# The four phases, as in apply-poultry-cost-recognition.ps1:
#
#   1. MEASURE   every poultry company's P&L expense total, expense row count,
#                raw-material stock and cash, BEFORE anything changes.
#   2. DRY RUN   the migration PLUS the behavioural check file inside a single
#                transaction that is then ROLLED BACK.
#   3. APPLY     the migration in its own transaction.
#   4. MEASURE   the same totals again and diff them.
#
# EFFECT ON TODAY'S NUMBERS
# =========================
# Stages 1-3 must print "No change to any measured total." They add
# classification, a register and a depreciation ledger; nothing existing moves.
#
# STAGE 4 IS DIFFERENT AND DELIBERATELY SO. It rewrites the P&L report, and the
# whole point is that the report changes: raw-material purchases stop falling
# into "Other" and land on Feed. pl_expense is the ONE measured total allowed to
# move, and only at stage 4. Read the diff rather than skipping it.
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-poultry-phase3.ps1 -Stage 1
#   .\apply-poultry-phase3.ps1 -Stage 1 -Apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'poultry-phase3'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }

$stages = @{
    1 = @{ Migration = '269_PoultryFinancialCostType.postgres.sql';   Check = 'poultry-financial-cost-type.test.sql' }
    2 = @{ Migration = '270_PoultryCapitalAssets.postgres.sql';       Check = 'poultry-capital-assets.test.sql' }
    3 = @{ Migration = '271_PoultryAssetDepreciation.postgres.sql';   Check = 'poultry-asset-depreciation.test.sql' }
    4 = @{ Migration = '272_PoultryProfitLossRedesign.postgres.sql';  Check = 'poultry-profit-loss-redesign.test.sql' }
    5 = @{ Migration = '273_PoultryAssetPermissions.postgres.sql';    Check = 'poultry-asset-permissions.test.sql' }
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
# pl_expense is read from the P&L report itself, not re-derived: it is the
# number an owner actually looks at, and the one this whole workstream is
# capable of moving.
$measureSql = @'
\pset footer off
SELECT 'poultry' AS metric, f.farmid, f.name,
       (SELECT COUNT(*) FROM poultryrawmaterialitems i WHERE i.farmid = f.farmid)                AS items,
       (SELECT ROUND(COALESCE(SUM(i.currentquantity), 0), 2) FROM poultryrawmaterialitems i
         WHERE i.farmid = f.farmid)                                                              AS stock_qty,
       (SELECT COUNT(*) FROM poultryrawmaterialpurchases pu WHERE pu.farmid = f.farmid)          AS purchases,
       (SELECT ROUND(COALESCE(SUM(pu.totalcost), 0), 2) FROM poultryrawmaterialpurchases pu
         WHERE pu.farmid = f.farmid)                                                             AS purchase_cost,
       (SELECT ROUND(COALESCE(SUM(pu.amountpaid), 0), 2) FROM poultryrawmaterialpurchases pu
         WHERE pu.farmid = f.farmid)                                                             AS purchase_paid,
       (SELECT COUNT(*) FROM expense e WHERE e.farmid::text = f.farmid)                          AS expense_rows,
       (SELECT ROUND(COALESCE(SUM(e.amount), 0), 2) FROM expense e WHERE e.farmid::text = f.farmid) AS expense_total,
       (SELECT ROUND(COALESCE(p.totalexpenses, 0), 2)
          FROM sppoultryreport_profitloss(f.farmid, '2000-01-01'::date, '2099-12-31'::date) p)   AS pl_expense,
       (SELECT ROUND(COALESCE(SUM(a.currentbalance), 0), 2) FROM poultrycashaccounts a
         WHERE a.farmid = f.farmid)                                                              AS cash,
       (SELECT ROUND(COALESCE(s.netcashflow, 0), 2)
          FROM sppoultrycashflow_summary(f.farmid, NULL, NULL) s)                                AS net_flow
FROM   farms f
WHERE  f.type = 'Poultry'
  AND  EXISTS (SELECT 1 FROM poultryrawmaterialitems i WHERE i.farmid = f.farmid)
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
# the exit code: a resolver that returns the WRONG method still returns cleanly.
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
Write-Host '=== DIFF (expected: identical -- no farm has asked for a different method) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host 'No change to any measured total.' -ForegroundColor Green
} else {
    $diff | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'A moved pl_expense here is the serious one: it means a farm''s P&L changed without anyone choosing it.' -ForegroundColor Red
}

Write-Host ''
Write-Host 'RESTART THE API when the backend stages land.' -ForegroundColor Yellow
