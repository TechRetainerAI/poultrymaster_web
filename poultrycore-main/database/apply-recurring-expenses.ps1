# =============================================================================
# Apply migration 348 (Recurring Expense Engine, all company types) to Postgres.
#
#   1. MEASURE   every expense table and every cash account, all five modules.
#   2. DRY RUN   the migration AND checks/recurring-expense-engine.test.sql inside
#                one transaction that is then ROLLED BACK.
#   3. APPLY     the migration in its own transaction.
#   4. MEASURE   again and diff.
#
# 348 adds three empty tables and functions, and posts nothing: a draft becomes
# an expense only when a person posts it, through the module's own service.
# So phase 4 must print "No change" for every expense table and cash balance.
#
# Usage (password from the environment, never on the command line):
#   $env:PGPASSWORD = '<password>'
#   .pply-recurring-expenses.ps1            # measure + dry run
#   .pply-recurring-expenses.ps1 -Apply     # ... then apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'recurring-expenses'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files  = @('348_RecurringExpenseEngine.postgres.sql')
$checks = @('recurring-expense-engine.test.sql')
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

# --- the measurement, before and after ----------------------------------------
# Totals per expense module plus every cash balance: 348 must move none of them.
$measureSql = @'
\pset footer off
\pset pager off
\echo '-- expense tables'
SELECT 'poultry' AS m, COUNT(*), SUM(amount), SUM(COALESCE(amountpaid, amount)) FROM public.expense
UNION ALL SELECT 'water', COUNT(*), SUM(amount), SUM(COALESCE(amountpaid, amount)) FROM public.waterexpenses
UNION ALL SELECT 'generic', COUNT(*), SUM(amount), SUM(COALESCE(amountpaid, amount)) FROM public.genericexpenses
UNION ALL SELECT 'hotel', COUNT(*), SUM(amount), NULL FROM public.hotelexpenses
UNION ALL SELECT 'restaurant', COUNT(*), SUM(amount), NULL FROM public.restaurantexpenses;
\echo '-- cash accounts'
SELECT 'poultry', poultrycashaccountid, currentbalance FROM public.poultrycashaccounts
UNION ALL SELECT 'water', watercashaccountid, currentbalance FROM public.watercashaccounts
UNION ALL SELECT 'generic', genericcashaccountid, currentbalance FROM public.genericcashaccounts
UNION ALL SELECT 'hotel', hotelcashaccountid, currentbalance FROM public.hotelcashaccounts
UNION ALL SELECT 'restaurant', cashaccountid, currentbalance FROM public.restaurantcashaccounts
ORDER BY 1, 2;
'@
$measureFile = Join-Path $OutDir 'measure.sql'
Set-Content -Path $measureFile -Value $measureSql -Encoding utf8

Write-Host "Host:       $DbHost/$Database"
Write-Host "Migration:  $($files -join ', ')"
Write-Host "Checks:     $($checks -join ', ')"
Write-Host ''

# --- phase 1: measure before -------------------------------------------------
Write-Host '=== 1. BEFORE ===' -ForegroundColor Cyan
$before = Join-Path $OutDir 'before.txt'
if ((Invoke-Psql -File $measureFile -LogPath $before) -ne 0) {
    Get-Content $before | Write-Host
    throw 'Could not read the baseline. Nothing has been changed.'
}
Write-Host "  $((Get-Content $before).Count) line(s) captured" -ForegroundColor Gray

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
$passed = Get-Content $dryLog | Where-Object { $_ -match 'recurring-expense-engine: all checks passed' }
if (-not $passed) {
    throw 'The recurring-expense checks did not report success. Do not apply.'
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
$after = Join-Path $OutDir 'after.txt'
[void](Invoke-Psql -File $measureFile -LogPath $after)

Write-Host ''
Write-Host '=== DIFF (expected: identical -- 348 posts nothing) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host "No change to any expense table or cash balance. ($((Get-Content $after).Count) lines compared)" -ForegroundColor Green
} else {
    $diff | Select-Object -First 40 | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- 348 must not change existing data.' -ForegroundColor Red
}
