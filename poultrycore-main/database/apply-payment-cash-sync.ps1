# =============================================================================
# Apply migration 353 (the customer-payment cash sync keeps the receipt row it
# already wrote, instead of deleting and re-inserting the whole group) to
# Postgres. Needs 351/352 applied first.
#
#   1. MEASURE   revenue, balances, sales, payments, cash accounts, cash rows,
#                stock and Cash Flow per poultry company.
#   2. DRY RUN   353 AND checks/sale-reversal.test.sql (plus the flock
#                closeout / reopen checks, which also reverse payments) inside
#                one transaction that is then ROLLED BACK.
#   3. APPLY     353 in its own transaction.
#   4. MEASURE   again and diff -- must be identical: 353 replaces one function
#                and runs nothing, so no row and no number may move.
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-payment-cash-sync.ps1            # measure + dry run
#   .\apply-payment-cash-sync.ps1 -Apply     # ... then apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'payment-cash-sync'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files  = @('353_PoultryPaymentCashSyncInPlace.postgres.sql')
$checks = @('sale-reversal.test.sql', 'poultry-flock-closeout.test.sql', 'poultry-flock-reopen-reverses-sales.test.sql')
$passMarkers = @('sale reversal: all checks passed', 'poultry-flock-closeout: all checks passed',
                 'poultry-flock-reopen-reverses-sales: all checks passed')
foreach ($f in $files)  { if (-not (Test-Path (Join-Path $MigrationsDir $f))) { throw "Missing migration: $f" } }
foreach ($c in $checks) { if (-not (Test-Path (Join-Path $ChecksDir $c)))     { throw "Missing check: $c" } }

# Redirection is handed to cmd.exe on purpose: PowerShell 5.1 wraps a native
# command's stderr in ErrorRecords, so a psql NOTICE would abort the run.
function Invoke-Psql {
    param([string] $File, [string] $LogPath, [string] $Extra = '')
    $line = '"{0}" -h {1} -p {2} -U {3} -d {4} -X -w -v ON_ERROR_STOP=1 {6} -f "{5}"' -f `
            $Psql, $DbHost, $Port, $User, $Database, $File, $Extra
    if ($LogPath) { $line += ' > "{0}" 2>&1' -f $LogPath }
    & cmd.exe /c $line
    return $LASTEXITCODE
}

$invariantSql = @'
\pset footer off
\pset pager off
\echo '-- revenue lines per company (all time)'
SELECT f.farmid, COUNT(*) AS n, SUM(v.totalamount) AS revenue
FROM   (SELECT DISTINCT farmid FROM public.sale) f
CROSS  JOIN LATERAL public.fnpoultrypl_revenuelines(f.farmid, '2000-01-01', '2100-01-01') v
GROUP  BY f.farmid ORDER BY f.farmid;
\echo '-- customer balances per company'
SELECT f.farmid, COUNT(*) AS customers, SUM(b.totalbalance) AS owed, SUM(b.totalsales) AS sales, SUM(b.totalpaid) AS paid
FROM   (SELECT DISTINCT farmid FROM public.sale) f
CROSS  JOIN LATERAL public.sppoultrycustomerbalances(f.farmid, NULL, NULL, NULL, 'All', NULL, NULL) b
GROUP  BY f.farmid ORDER BY f.farmid;
\echo '-- every sale'
SELECT saleid, farmid, status, quantity, totalamount, paid, amountpaid, poultrycashaccountid FROM public.sale ORDER BY saleid;
\echo '-- every payment and allocation'
SELECT poultrypaymentid, saleid, amount, status, paymentgroupid FROM public.poultrypayments ORDER BY poultrypaymentid;
SELECT allocationid, paymentid, saleid, amountapplied, status FROM public.customerpaymentallocation
WHERE  module = 'poultry' ORDER BY allocationid;
\echo '-- cash accounts, every cash row, stock'
SELECT poultrycashaccountid, currentbalance FROM public.poultrycashaccounts ORDER BY poultrycashaccountid;
SELECT poultrycashtransactionid, poultrycashaccountid, transactiondate, sourcetype, sourceid, amount, createdat, clearingstatus
FROM   public.poultrycashtransactions ORDER BY poultrycashtransactionid;
SELECT farmid, poultryproductid, SUM(quantity) FROM public.poultrystocktransactions
GROUP  BY farmid, poultryproductid ORDER BY farmid, poultryproductid;
\echo '-- cash flow per company'
SELECT f.farmid, s.moneyin, s.moneyout, s.netcashflow, s.cashathand
FROM   (SELECT DISTINCT farmid FROM public.sale) f
CROSS  JOIN LATERAL public.sppoultrycashflow_summary(f.farmid, NULL, NULL) s
ORDER  BY f.farmid;
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
[void](Invoke-Psql -File $invariantFile -LogPath $after)
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host "No change to revenue, balances, sales, payments, cash rows, stock or Cash Flow. ($((Get-Content $after).Count) lines compared)" -ForegroundColor Green
} else {
    $diff | Select-Object -First 40 | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- 353 runs nothing, it only replaces a function.' -ForegroundColor Red
}
