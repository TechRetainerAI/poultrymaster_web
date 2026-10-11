# =============================================================================
# Apply migrations 351 (posted sales are immutable: Sale Reversal, Customer
# Credit, Refunds) and 352 (readers learn about Reversed sales) to Postgres.
#
# DEPLOY ORDER: the API first, then this script. The previous API saved a sale
# in several transactions, and 351's guard would refuse its egg-class step.
#
# Same four phases as the other apply scripts:
#
#   1. MEASURE   revenue, receivables, customer balances, egg stock, closing
#                report, cash accounts and Cash Flow per poultry company.
#   2. DRY RUN   both migrations AND checks/sale-reversal.test.sql (plus the
#                flock closeout / reopen checks 351 changes) inside one
#                transaction that is then ROLLED BACK.
#   3. APPLY     each migration in its own transaction.
#   4. MEASURE   again and diff.
#
# WHAT THE MEASUREMENT IS FOR
# ---------------------------
# 351/352 reverse nothing. Every sale is created Posted, so every reader that
# now filters on status = 'Posted' must read exactly what it read before: the
# INVARIANT block must print "No change".
#
# One number moves, on purpose: Cash Flow now shows a payment that was reversed
# BEFORE 351 as the receipt it was AND the reversal that undid it (it used to
# vanish). Money In and Money Out each rise by the total of those payments and
# net cash does not move. Phase 1 works that total out from the raw table;
# phase 4 checks Cash Flow moved by exactly that and its net by nothing.
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-sale-reversal.ps1                 # measure + dry run
#   .\apply-sale-reversal.ps1 -Apply          # ... then apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'sale-reversal'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files  = @('351_PoultrySaleReversal.postgres.sql', '352_PoultrySaleReversalReaders.postgres.sql')
$checks = @('sale-reversal.test.sql', 'poultry-flock-closeout.test.sql', 'poultry-flock-reopen-reverses-sales.test.sql')
$passMarkers = @('sale reversal: all checks passed', 'poultry-flock-closeout: all checks passed',
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
# Invariant: must be byte-identical before and after. Written to run on the
# pre-351 schema too (no status column referenced).
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
\echo '-- every sale'
SELECT saleid, farmid, quantity, totalamount, paid, amountpaid, poultrycashaccountid, poultryproductid
FROM   public.sale ORDER BY saleid;
\echo '-- every payment and allocation'
SELECT poultrypaymentid, saleid, amount, status, paymentgroupid FROM public.poultrypayments ORDER BY poultrypaymentid;
SELECT allocationid, paymentid, saleid, amountapplied, status FROM public.customerpaymentallocation
WHERE  module = 'poultry' ORDER BY allocationid;
\echo '-- cash accounts and stock'
SELECT poultrycashaccountid, currentbalance FROM public.poultrycashaccounts ORDER BY poultrycashaccountid;
SELECT farmid, poultryproductid, SUM(quantity) FROM public.poultrystocktransactions
GROUP  BY farmid, poultryproductid ORDER BY farmid, poultryproductid;
\echo '-- cash flow net per company'
SELECT f.farmid, s.netcashflow, s.cashathand
FROM   (SELECT DISTINCT farmid FROM public.sale) f
CROSS  JOIN LATERAL public.sppoultrycashflow_summary(f.farmid, NULL, NULL) s
ORDER  BY f.farmid;
'@

# Cash Flow Money In and Money Out: farm|in|out, unaligned, for arithmetic.
$cashflowSql = @'
SELECT f.farmid || '|' || s.moneyin::text || '|' || s.moneyout::text
FROM   (SELECT DISTINCT farmid FROM public.sale) f
CROSS  JOIN LATERAL public.sppoultrycashflow_summary(f.farmid, NULL, NULL) s
ORDER  BY f.farmid;
'@

# What 352 SHOULD add to both Money In and Money Out: payments reversed before
# 351, which Cash Flow used to drop and now shows in and back out.
$expectedSql = @'
SELECT f.farmid || '|' || COALESCE((SELECT SUM(p.amount) FROM public.poultrypayments p
                                    WHERE lower(p.farmid::text) = lower(f.farmid) AND p.status = 'Reversed'
                                      AND p.reversedat IS NOT NULL AND p.amount <> 0), 0)::numeric(14,2)::text
FROM   (SELECT DISTINCT farmid FROM public.sale) f
ORDER  BY f.farmid;
'@

$invariantFile = Join-Path $OutDir 'invariant.sql'
$cashflowFile  = Join-Path $OutDir 'cashflow.sql'
$expectedFile  = Join-Path $OutDir 'expected.sql'
Set-Content -Path $invariantFile -Value $invariantSql -Encoding utf8
Set-Content -Path $cashflowFile  -Value $cashflowSql  -Encoding utf8
Set-Content -Path $expectedFile  -Value $expectedSql  -Encoding utf8

function Read-Figures([string] $Path) {
    $map = @{}
    Get-Content $Path | Where-Object { $_ -match '^[^|]+(\|-?[0-9.]+)+$' } | ForEach-Object {
        $p = $_ -split '\|'
        $map[$p[0]] = @($p[1..($p.Count - 1)] | ForEach-Object { [decimal]$_ })
    }
    return $map
}

Write-Host "Host:       $DbHost/$Database"
Write-Host "Migrations: $($files -join ', ')"
Write-Host "Checks:     $($checks -join ', ')"
Write-Host ''

# --- phase 1: measure before -------------------------------------------------
Write-Host '=== 1. BEFORE ===' -ForegroundColor Cyan
$before   = Join-Path $OutDir 'before.txt'
$cfBefore = Join-Path $OutDir 'cashflow-before.txt'
$expected = Join-Path $OutDir 'expected-delta.txt'
if ((Invoke-Psql -File $invariantFile -LogPath $before) -ne 0) {
    Get-Content $before | Write-Host
    throw 'Could not read the baseline. Nothing has been changed.'
}
if ((Invoke-Psql -File $cashflowFile -LogPath $cfBefore -Extra '-At') -ne 0) { Get-Content $cfBefore | Write-Host; throw 'Could not read Cash Flow.' }
if ((Invoke-Psql -File $expectedFile -LogPath $expected -Extra '-At') -ne 0) { Get-Content $expected | Write-Host; throw 'Could not compute the expected Cash Flow change.' }
Write-Host "  $((Get-Content $before).Count) invariant line(s) captured" -ForegroundColor Gray
$exp = Read-Figures $expected
$nonZero = @($exp.GetEnumerator() | Where-Object { $_.Value[0] -ne 0 })
Write-Host "  Cash Flow will show earlier payment reversals for $($nonZero.Count) company(ies):" -ForegroundColor Gray
$nonZero | ForEach-Object { Write-Host ("    {0}  in +{1} / out +{1}" -f $_.Key, $_.Value[0]) -ForegroundColor Gray }

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
    Write-Host 'Stopping here. Re-run with -Apply to commit (API deployed first).' -ForegroundColor Yellow
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
$cfAfter = Join-Path $OutDir 'cashflow-after.txt'
[void](Invoke-Psql -File $invariantFile -LogPath $after)
[void](Invoke-Psql -File $cashflowFile -LogPath $cfAfter -Extra '-At')

Write-Host ''
Write-Host '=== INVARIANTS (expected: identical -- nothing has been reversed yet) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host "No change to revenue, balances, egg stock, closing totals, sales, payments, cash or stock. ($((Get-Content $after).Count) lines compared)" -ForegroundColor Green
} else {
    $diff | Select-Object -First 40 | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- 351/352 must not move a number until a sale is reversed.' -ForegroundColor Red
}

Write-Host ''
Write-Host '=== CASH FLOW (expected: In and Out each rise by the earlier reversals; net unchanged) ===' -ForegroundColor Cyan
$b = Read-Figures $cfBefore
$a = Read-Figures $cfAfter
$bad = 0
foreach ($farm in ($a.Keys | Sort-Object)) {
    $bi = $(if ($b.ContainsKey($farm)) { $b[$farm] } else { @(0, 0) })
    $want = $(if ($exp.ContainsKey($farm)) { $exp[$farm][0] } else { 0 })
    $dIn  = $a[$farm][0] - $bi[0]
    $dOut = $a[$farm][1] - $bi[1]
    if ($dIn -ne $want -or $dOut -ne $want) {
        $bad++
        Write-Host ("  MISMATCH {0}: in {1}, out {2}, expected {3} each" -f $farm, $dIn, $dOut, $want) -ForegroundColor Red
    } elseif ($want -ne 0) {
        Write-Host ("  {0}: in +{1}, out +{1} (as expected)" -f $farm, $want) -ForegroundColor Green
    }
}
if ($bad -eq 0) { Write-Host 'Cash Flow moved by exactly the expected amounts and nowhere else.' -ForegroundColor Green }
