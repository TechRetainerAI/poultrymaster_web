# =============================================================================
# Apply migrations 345 (Receive Purchase) and 346 (Cash Flow for deferred stock
# purchases) to Postgres.
#
# Same four phases as the other apply scripts:
#
#   1. MEASURE   payables, deferred-cost rows, purchase history, closing-report
#                purchases and Cash Flow per poultry company.
#   2. DRY RUN   both migrations AND checks/poultry-receive-purchase.test.sql
#                inside one transaction that is then ROLLED BACK.
#   3. APPLY     each migration in its own transaction.
#   4. MEASURE   again and diff.
#
# WHAT THE MEASUREMENT IS FOR
# ---------------------------
# 345 receives nothing. It adds a nullable column, two empty tables, a trigger
# that only fires on a receipt's lot, new functions, and teaches four readers
# about reversedat -- which no row has yet. So every INVARIANT figure (payables,
# deferred rows, purchase history, period purchases) must print "No change".
#
# 346 DOES move a number, on purpose: Cash Flow starts counting money paid for
# stock that is expensed when used, which it never saw before. Phase 1 works
# out, from the raw tables, exactly how much that is per company; phase 4
# checks that Money Out rose by precisely that and nothing else.
#
# The dry run carries ~110 behavioural checks (paid / credit / part payment,
# both cost-recognition methods, FIFO/LIFO/HIFO, additional costs, reversal and
# its blockers, duplicates, validation, company isolation, permissions). They
# RAISE on any failure, so a failing check stops the script before anything is
# committed.
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-receive-purchase.ps1                 # measure + dry run
#   .\apply-receive-purchase.ps1 -Apply          # ... then apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'receive-purchase'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files  = @('345_PoultryReceivePurchase.postgres.sql', '346_PoultryCashFlowDeferredPurchases.postgres.sql')
$checks = @('poultry-receive-purchase.test.sql')
foreach ($f in $files)  { if (-not (Test-Path (Join-Path $MigrationsDir $f))) { throw "Missing migration: $f" } }
foreach ($c in $checks) { if (-not (Test-Path (Join-Path $ChecksDir $c)))     { throw "Missing check: $c" } }

# Redirection is handed to cmd.exe rather than done in PowerShell on purpose.
# PowerShell 5.1 wraps a native command's stderr in ErrorRecords, so a single
# psql NOTICE -- of which the checks emit about a hundred -- trips
# $ErrorActionPreference and aborts a run that was going fine.
function Invoke-Psql {
    param([string] $File, [string] $LogPath, [string] $Extra = '')
    $line = '"{0}" -h {1} -p {2} -U {3} -d {4} -X -w -v ON_ERROR_STOP=1 {6} -f "{5}"' -f `
            $Psql, $DbHost, $Port, $User, $Database, $File, $Extra
    if ($LogPath) { $line += ' > "{0}" 2>&1' -f $LogPath }
    & cmd.exe /c $line
    return $LASTEXITCODE
}

# --- the measurements ---------------------------------------------------------
# Invariant: must be byte-identical before and after. Written so the "before"
# query runs on the pre-345 schema (no reversedat, no receipt tables).
$invariantSql = @'
\pset footer off
\pset pager off
\echo '-- payables per poultry company and document type'
SELECT f.farmid, d.documenttype, COUNT(*) AS n, SUM(d.totalcost) AS total,
       SUM(d.amountpaid) AS paid, SUM(d.balance) AS balance
FROM   (SELECT DISTINCT farmid FROM public.poultryrawmaterialpurchases) f
CROSS  JOIN LATERAL public.fnpoultrypayables(f.farmid) d
GROUP  BY f.farmid, d.documenttype
ORDER  BY f.farmid, d.documenttype;
\echo '-- deferred-cost rows per company'
SELECT f.farmid, COUNT(*) AS n, SUM(r.deferredremainingcost) AS remaining,
       SUM(r.recognizedcost) AS recognized, string_agg(DISTINCT r.status, ',' ORDER BY r.status) AS statuses
FROM   (SELECT DISTINCT farmid FROM public.poultryrawmaterialpurchases) f
CROSS  JOIN LATERAL public.fnpoultrydeferredpurchase_rows(f.farmid) r
GROUP  BY f.farmid
ORDER  BY f.farmid;
\echo '-- purchase history per company'
SELECT f.farmid, COUNT(*) AS n, SUM(g.totalcost) AS total, SUM(g.balance) AS balance,
       string_agg(DISTINCT g.costrecognitionstatus, ',' ORDER BY g.costrecognitionstatus) AS statuses
FROM   (SELECT DISTINCT farmid FROM public.poultryrawmaterialpurchases) f
CROSS  JOIN LATERAL public.sppoultryrawmaterialpurchase_getall(f.farmid, NULL, NULL) g
GROUP  BY f.farmid
ORDER  BY f.farmid;
\echo '-- closing report raw-material purchases, last 365 days'
SELECT f.farmid, c.totalrawmaterialpurchases
FROM   (SELECT DISTINCT farmid FROM public.poultryrawmaterialpurchases) f
CROSS  JOIN LATERAL public.sppoultryclosingreport_get(
           f.farmid, (now() AT TIME ZONE 'utc')::date - 365, (now() AT TIME ZONE 'utc')::date) c
ORDER  BY f.farmid;
\echo '-- every lot'
SELECT poultryrawmaterialpurchaseid, farmid, quantity, remainingquantity, totalcost, amountpaid,
       deferredtotalcost, deferredremainingcost, costrecognitionmethod
FROM   public.poultryrawmaterialpurchases
ORDER  BY poultryrawmaterialpurchaseid;
'@

# Cash Flow: farm|moneyout, unaligned, so phase 4 can do arithmetic on it.
$cashflowSql = @'
SELECT f.farmid || '|' || s.moneyout::text
FROM   (SELECT DISTINCT farmid FROM public.poultryrawmaterialpurchases) f
CROSS  JOIN LATERAL public.sppoultrycashflow_summary(f.farmid, NULL, NULL) s
ORDER  BY f.farmid;
'@

# What 346 SHOULD add to Money Out, from the raw tables: paid-at-entry on
# deferred lots not made by feed production, plus posted supplier-payment
# allocations to deferred lots.
$expectedSql = @'
SELECT f.farmid || '|' || (
         COALESCE((SELECT SUM(GREATEST(pu.amountpaid - COALESCE((
                     SELECT SUM(sa.amountapplied) FROM public.supplierpaymentallocation sa
                     WHERE sa.farmid = pu.farmid AND sa.module = 'poultry' AND sa.status = 'Posted'
                       AND sa.documenttype = 'RawMaterialPurchase'
                       AND sa.documentid = pu.poultryrawmaterialpurchaseid), 0), 0))
                   FROM public.poultryrawmaterialpurchases pu
                   WHERE pu.farmid = f.farmid AND pu.costrecognitionmethod = 'EXPENSE_WHEN_CONSUMED'
                     AND pu.sourcefeedproductionbatchid IS NULL), 0)
       + COALESCE((SELECT SUM(sa.amountapplied)
                   FROM public.supplierpaymentallocation sa
                   JOIN public.poultrysupplierpayments sp ON sp.poultrysupplierpaymentid = sa.paymentid AND sp.status = 'Posted'
                   JOIN public.poultryrawmaterialpurchases pu ON pu.poultryrawmaterialpurchaseid = sa.documentid
                   WHERE sa.farmid = f.farmid AND sa.module = 'poultry' AND sa.status = 'Posted'
                     AND sa.documenttype = 'RawMaterialPurchase'
                     AND pu.costrecognitionmethod = 'EXPENSE_WHEN_CONSUMED'), 0)
       )::numeric(14,2)::text
FROM   (SELECT DISTINCT farmid FROM public.poultryrawmaterialpurchases) f
ORDER  BY f.farmid;
'@

$invariantFile = Join-Path $OutDir 'invariant.sql'
$cashflowFile  = Join-Path $OutDir 'cashflow.sql'
$expectedFile  = Join-Path $OutDir 'expected.sql'
Set-Content -Path $invariantFile -Value $invariantSql -Encoding utf8
Set-Content -Path $cashflowFile  -Value $cashflowSql  -Encoding utf8
Set-Content -Path $expectedFile  -Value $expectedSql  -Encoding utf8

function Read-FarmFigures([string] $Path) {
    $map = @{}
    Get-Content $Path | Where-Object { $_ -match '^[^|]+\|-?[0-9.]+$' } | ForEach-Object {
        $p = $_ -split '\|'
        $map[$p[0]] = [decimal]$p[1]
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
$exp = Read-FarmFigures $expected
$nonZero = @($exp.GetEnumerator() | Where-Object { $_.Value -ne 0 })
Write-Host "  346 should add to Money Out for $($nonZero.Count) company(ies):" -ForegroundColor Gray
$nonZero | ForEach-Object { Write-Host ("    {0}  +{1}" -f $_.Key, $_.Value) -ForegroundColor Gray }

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
Get-Content $dryLog | Where-Object { $_ -match 'FAIL|ERROR|all checks passed|345:|346:' } | Write-Host
if ($dryCode -ne 0) {
    throw "DRY RUN FAILED (see $dryLog). Nothing has been changed."
}
$passed = Get-Content $dryLog | Where-Object { $_ -match 'poultry-receive-purchase: all checks passed' }
if (-not $passed) {
    throw 'The receive-purchase checks did not report success. Do not apply.'
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
    Get-Content $log | Where-Object { $_ -match 'NOTICE' } | Write-Host -ForegroundColor Gray
}

# --- phase 4: measure after and diff ----------------------------------------
Write-Host ''
Write-Host '=== 4. AFTER ===' -ForegroundColor Cyan
$after   = Join-Path $OutDir 'after.txt'
$cfAfter = Join-Path $OutDir 'cashflow-after.txt'
[void](Invoke-Psql -File $invariantFile -LogPath $after)
[void](Invoke-Psql -File $cashflowFile -LogPath $cfAfter -Extra '-At')

Write-Host ''
Write-Host '=== INVARIANTS (expected: identical -- 345 receives nothing) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host "No change to payables, deferred cost, purchase history, period purchases or any lot. ($((Get-Content $after).Count) lines compared)" -ForegroundColor Green
} else {
    $diff | Select-Object -First 40 | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- 345 must not move a number until something is received.' -ForegroundColor Red
}

Write-Host ''
Write-Host '=== CASH FLOW (expected: Money Out rises by exactly the deferred-stock payments) ===' -ForegroundColor Cyan
$b = Read-FarmFigures $cfBefore
$a = Read-FarmFigures $cfAfter
$bad = 0
foreach ($farm in ($a.Keys | Sort-Object)) {
    $delta = $a[$farm] - $(if ($b.ContainsKey($farm)) { $b[$farm] } else { 0 })
    $want  = $(if ($exp.ContainsKey($farm)) { $exp[$farm] } else { 0 })
    if ($delta -ne $want) {
        $bad++
        Write-Host ("  MISMATCH {0}: Money Out moved {1}, expected {2}" -f $farm, $delta, $want) -ForegroundColor Red
    } elseif ($delta -ne 0) {
        Write-Host ("  {0}: +{1} (as expected)" -f $farm, $delta) -ForegroundColor Green
    }
}
if ($bad -eq 0) { Write-Host 'Cash Flow moved by exactly the expected amounts and nowhere else.' -ForegroundColor Green }
