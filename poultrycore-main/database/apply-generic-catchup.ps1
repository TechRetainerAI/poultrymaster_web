# =============================================================================
# Generic catch-up: brings a database's Generic company functions up to dev by
# re-running the WHOLE Generic migration series 439 -> 476 in number order
# (each file is idempotent; running the series in order leaves every function
# at its latest version -- running one old file alone could regress a newer one).
#
# Written 2026-11-23 for VisibilityCorePROD, where 439G-446 / 450-453 / 456 are
# missing and 448/449/455/472-476 differ from dev (Generic P&L, Expenses,
# Products, Payroll, Capital Assets, Cash transfers failing).
#
# -Database is REQUIRED (no default) so this can never hit production by accident.
#
#   .pply-generic-catchup.ps1 -Database VisibilityCorePROD          # measure + trial (rolled back)
#   .pply-generic-catchup.ps1 -Database VisibilityCorePROD -Apply   # ... then apply
#
# The trial also runs the Generic P&L query (Business/GenericProfitLoss.cs) and
# the Expenses list for every Generic company inside the rolled-back transaction,
# so a page that would still fail is caught before anything is applied.
# =============================================================================

[CmdletBinding()]
param(
    [string] $DbHost   = '34.175.134.7',
    [int]    $Port     = 5432,
    [Parameter(Mandatory = $true)] [string] $Database,
    [string] $User     = 'poultryapp',
    [string] $Psql     = 'C:\Program Files\PostgreSQL\18\bin\psql.exe',
    [string] $MigrationsDir = (Join-Path $PSScriptRoot '..\..\poultrycore_Backend\PoultryFarmAPI\Migrations'),
    [string] $ChecksDir = (Join-Path $PSScriptRoot 'checks'),
    [string] $OutDir   = (Join-Path $env:TEMP 'generic-catchup'),
    # Apply only these (e.g. -Only 422_FlockReportsSkipDeletedAndPending.postgres.sql when 420/421 are already in).
    [string[]] $Only,
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files  = @(
    '439_GenericProductionRecords.postgres.sql',
    '440_GenericProductItemType.postgres.sql',
    '441_GenericUnifiedItemArchitecture.postgres.sql',
    '442_GenericFinancialIntegration.postgres.sql',
    '443_GenericPhase5Reports.postgres.sql',
    '445_FixLoanCashBalanceAfter.postgres.sql',
    '446_FixGenericProductionStockMovementStatus.postgres.sql',
    '447_DropDuplicateGenericLoanRepaymentRecord.postgres.sql',
    '448_GenericExpensesLikePoultry.postgres.sql',
    '449_GenericSupplierCredit.postgres.sql',
    '450_GenericEmployeeCredit.postgres.sql',
    '451_GenericPayrollLikePoultry.postgres.sql',
    '452_GenericDeferredInventoryCost.postgres.sql',
    '453_GenericCapitalAssets.postgres.sql',
    '454_GenericPayrollMarkPaidLikePoultry.postgres.sql',
    '455_GenericLoansLikePoultry.postgres.sql',
    '456_GenericCashTransfersReconciliationLikePoultry.postgres.sql',
    '457_GenericExpenseReverseLegacyRows.postgres.sql',
    '472_GenericPurchaseUnitsAndDraftEdit.postgres.sql',
    '473_GenericCustomerCreditLifecycle.postgres.sql',
    '474_GenericPurchaseReporting.postgres.sql',
    '475_GenericSaleAccrualRevenue.postgres.sql',
    '476_GenericSaleUnitsAndCredit.postgres.sql',
    # 482: MUST follow 475/476, whose sale approval writes customer 0 for walk-ins
    '482_Enock_GenericWalkInSalePayment.postgres.sql',
    # 483: sale reversal (needs 473-476 + 482)
    '483_Enock_GenericSaleReversal.postgres.sql'
)
if ($Only) { $files = @($files | Where-Object { $Only -contains $_ }); if (-not $files) { throw 'Nothing matches -Only.' } }
$checks = @('generic-catchup-smoke.test.sql', 'generic-482-walkin-sale-payment.test.sql', 'generic-483-sale-reversal.test.sql')
$passMarkers = @('generic catch-up: all checks passed', 'generic 482: all checks passed', 'generic 483: all checks passed')
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
\echo '-- generic money per company (must not move)'
SELECT 'sales', farmid, status, count(*), sum(totalamount) FROM public.genericsales GROUP BY 2, 3 UNION ALL
SELECT 'expenses', farmid, status, count(*), sum(amount) FROM public.genericexpenses GROUP BY 2, 3 UNION ALL
SELECT 'cash', farmid, transactiontype, count(*), sum(amount) FROM public.genericcashtransactions GROUP BY 2, 3 UNION ALL
SELECT 'purchases', farmid, status, count(*), sum(totalamount) FROM public.genericpurchases GROUP BY 2, 3 UNION ALL
SELECT 'payroll', farmid, status, count(*), sum(totalgrosspay) FROM public.genericpayrollruns GROUP BY 2, 3 UNION ALL
SELECT 'stock', farmid, movementtype, count(*), sum(quantity) FROM public.genericstockmovements GROUP BY 2, 3
ORDER BY 1, 2, 3;
\echo '-- cash account balances'
SELECT farmid, count(*), sum(currentbalance) FROM public.genericcashaccounts GROUP BY 1 ORDER BY 1;
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
Get-Content $dryLog | Where-Object { $_ -match 'FAIL|ERROR|all checks passed|diff  got' } | Write-Host
if ($dryCode -ne 0) {
    throw "DRY RUN FAILED (see $dryLog). Nothing has been changed."
}
foreach ($m in $passMarkers) {
    if (-not (Get-Content $dryLog | Where-Object { $_ -match [regex]::Escape($m) })) {
        throw "A check file did not report success ('$m'). Do not apply."
    }
}
# the 316 reconciliation prints "expect 0.00 diff  got X": every X must be 0.00
$badDiff = @(Get-Content $dryLog | Where-Object { $_ -match 'diff\s+got' -and $_ -notmatch 'got\s+0\.00\s*$' })
if ($badDiff.Count -gt 0) { $badDiff | Write-Host -ForegroundColor Red; throw 'The P&L no longer reconciles to periodpnl. Do not apply.' }
$okCount = (Get-Content $dryLog | Where-Object { $_ -match 'NOTICE:\s+ok ' }).Count
Write-Host "Dry run clean -- $okCount checks passed, transaction discarded." -ForegroundColor Green

if (-not $Apply) {
    Write-Host ''
    Write-Host 'Stopping here. Re-run with -Apply to commit. The API on production already expects these.' -ForegroundColor Yellow
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
Write-Host '=== INVARIANTS (all identical expected) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host "No money moved. ($((Get-Content $after).Count) lines compared)" -ForegroundColor Green
} else {
    $diff | Select-Object -First 40 | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Expected: nothing. Any change must be explained before going further.' -ForegroundColor Red
}

Write-Host ''
