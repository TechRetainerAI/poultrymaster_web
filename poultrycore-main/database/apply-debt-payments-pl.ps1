# =============================================================================
# Apply migration 382 (debt payments on Profit & Loss, per-payment exclude).
#
# DEPLOY ORDER: this script FIRST, then the API, then the web app. New columns
# have defaults and the P&L functions keep their signatures, so the old API
# keeps working.
#
# Four phases, as the other apply scripts:
#   1. MEASURE   money per company (must not move) + P&L per company (all time).
#   2. DRY RUN   382 + checks/debt-payments-pl.test.sql (+ customer debt /
#                supplier credit checks) inside one transaction, ROLLED BACK.
#   3. APPLY     382 in its own transaction.
#   4. MEASURE   again: money identical; P&L changes only by debt payments.
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-debt-payments-pl.ps1           # measure + dry run
#   .\apply-debt-payments-pl.ps1 -Apply    # ... then apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'debt-payments-pl'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files  = @('382_PoultryDebtPaymentsPL.postgres.sql')
$checks = @('debt-payments-pl.test.sql', 'customer-debt.test.sql', 'supplier-credit.test.sql')
$passMarkers = @('debt payments pl: all checks passed', 'customer debt: all checks passed', 'supplier credit: all checks passed')
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
$invariantSql = @'
\pset footer off
\pset pager off
\echo '-- cash per company'
SELECT farmid, count(*), sum(currentbalance) FROM public.poultrycashaccounts GROUP BY farmid ORDER BY farmid;
\echo '-- cash transactions per company'
SELECT farmid, count(*), sum(amount) FROM public.poultrycashtransactions GROUP BY farmid ORDER BY farmid;
\echo '-- sales paid / owed per company'
SELECT farmid, count(*), sum(amountpaid), sum(public.fnpoultrysalebalance(paid, totalamount, amountpaid))
FROM public.sale WHERE status = 'Posted' GROUP BY farmid ORDER BY farmid;
\echo '-- customer credit per company'
SELECT pp.farmid, sum(public.fnpoultrypayment_unapplied(pp.farmid, pp.poultrypaymentid))
FROM public.poultrypayments pp GROUP BY pp.farmid ORDER BY pp.farmid;
'@

$invariantFile = Join-Path $OutDir 'invariant.sql'
Set-Content -Path $invariantFile -Value $invariantSql -Encoding utf8


# What 382 is meant to change: P&L, all time, per company.
$plSql = @'
\pset footer off
\pset pager off
SELECT f.farmid, s.totalrevenue, s.totaloperatingexpenses, s.netprofit
FROM  (SELECT DISTINCT farmid FROM public.poultrypayments) f
CROSS JOIN LATERAL public.sppoultryreport_plsummary(f.farmid, DATE '2000-01-01', CURRENT_DATE) s
ORDER BY f.farmid;
'@
$plFile = Join-Path $OutDir 'pl.sql'
Set-Content -Path $plFile -Value $plSql -Encoding utf8

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
$plBefore = Join-Path $OutDir 'pl-before.txt'
[void](Invoke-Psql -File $plFile -LogPath $plBefore)

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
    Write-Host "No money moved. ($((Get-Content $after).Count) lines compared)" -ForegroundColor Green
} else {
    $diff | Select-Object -First 40 | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- 382 moves no money.' -ForegroundColor Red
}

Write-Host ''
Write-Host '=== P&L (expected: changes only where debts were paid) ===' -ForegroundColor Cyan
$plAfter = Join-Path $OutDir 'pl-after.txt'
[void](Invoke-Psql -File $plFile -LogPath $plAfter)
$plDiff = Compare-Object (Get-Content $plBefore) (Get-Content $plAfter)
if (-not $plDiff) { Write-Host 'No company P&L changed (no debt payments yet).' -ForegroundColor Green }
else { $plDiff | Format-Table -AutoSize | Out-String | Write-Host }

Write-Host ''
