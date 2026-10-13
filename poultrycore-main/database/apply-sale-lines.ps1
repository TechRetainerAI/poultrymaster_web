# =============================================================================
# Apply migration 358 (ONE sale header, many sale lines) to Postgres.
#
# DEPLOY ORDER: this script FIRST, then the API, then the web app.
#   - The old API keeps working on 358: it calls sppoultrysale_creategroup
#     without the new optional request key, and ignores the new columns.
#   - The new API passes p_requestkey, which only exists after 358.
#
# Same four phases as the other apply scripts:
#
#   1. MEASURE   revenue, customer balances, egg stock, closing report, cash
#                accounts, stock, Cash Flow totals, receivables per company.
#   2. DRY RUN   358 AND checks/sale-lines.test.sql, sale-reversal.test.sql
#                and the flock closeout / reopen checks inside one transaction
#                that is then ROLLED BACK.
#   3. APPLY     358 in its own transaction. It also measures before/after
#                internally and RAISES (rolling itself back) if any money or
#                stock moved.
#   4. MEASURE   again and diff.
#
# WHAT SHOULD MOVE: nothing but structure. The 5 existing SG groups become one
# sale each, so row COUNTS drop, which is why this compares totals per company
# rather than every row. Cash Flow Money In / Out totals stay the same; only
# the number of rows a payment shows as changes.
#
# Usage (password from the environment, never on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-sale-lines.ps1            # measure + dry run
#   .\apply-sale-lines.ps1 -Apply     # ... then apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'sale-lines'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files  = @('358_PoultrySaleLines.postgres.sql')
$checks = @('sale-lines.test.sql', 'sale-reversal.test.sql', 'poultry-flock-closeout.test.sql', 'poultry-flock-reopen-reverses-sales.test.sql')
$passMarkers = @('sale lines: all checks passed', 'sale reversal: all checks passed', 'poultry-flock-closeout: all checks passed',
                 'poultry-flock-reopen-reverses-sales: all checks passed')
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
# Must be identical before and after: totals only, per company.
$invariantSql = @'
\pset footer off
\pset pager off
\echo '-- revenue per company (all time)'
SELECT f.farmid, SUM(v.totalamount) AS revenue
FROM   (SELECT DISTINCT farmid FROM public.sale) f
CROSS  JOIN LATERAL public.fnpoultrypl_revenuelines(f.farmid, '2000-01-01', '2100-01-01') v
GROUP  BY f.farmid ORDER BY f.farmid;
\echo '-- customer balances per company'
SELECT f.farmid, SUM(b.totalbalance) AS owed, SUM(b.totalsales) AS sales, SUM(b.totalpaid) AS paid
FROM   (SELECT DISTINCT farmid FROM public.sale) f
CROSS  JOIN LATERAL public.sppoultrycustomerbalances(f.farmid, NULL, NULL, NULL, 'All', NULL, NULL) b
GROUP  BY f.farmid ORDER BY f.farmid;
\echo '-- egg stock report (all time)'
SELECT f.farmid, r.*
FROM   (SELECT DISTINCT farmid FROM public.sale) f
CROSS  JOIN LATERAL public.sppoultryreport_eggstockbalance(f.farmid, '2000-01-01', '2100-01-01') r
ORDER  BY f.farmid;
\echo '-- closing report, last 365 days'
SELECT f.farmid, c.*
FROM   (SELECT DISTINCT farmid FROM public.sale) f
CROSS  JOIN LATERAL public.sppoultryclosingreport_get(
           f.farmid, (now() AT TIME ZONE 'utc')::date - 365, (now() AT TIME ZONE 'utc')::date) c
ORDER  BY f.farmid;
\echo '-- sales, payments, allocations per company'
SELECT farmid, status, SUM(totalamount), SUM(fnpoultrysalebalance(paid, totalamount, amountpaid))
FROM   public.sale GROUP BY farmid, status ORDER BY farmid, status;
SELECT farmid, status, SUM(amount) FROM public.poultrypayments GROUP BY farmid, status ORDER BY farmid, status;
SELECT farmid, status, SUM(amountapplied) FROM public.customerpaymentallocation
WHERE  module = 'poultry' GROUP BY farmid, status ORDER BY farmid, status;
\echo '-- cash accounts and stock'
SELECT poultrycashaccountid, currentbalance FROM public.poultrycashaccounts ORDER BY poultrycashaccountid;
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
    Write-Host "No change to revenue, balances, egg stock, closing totals, sales, payments, cash, stock or Cash Flow. ($((Get-Content $after).Count) lines compared)" -ForegroundColor Green
} else {
    $diff | Select-Object -First 40 | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- 358 must not move a number.' -ForegroundColor Red
}

Write-Host ''
