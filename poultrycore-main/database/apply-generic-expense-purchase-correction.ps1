# =============================================================================
# Apply 520_Enock_GenericExpensePurchaseCorrection: Edit & repost for reversed
# Generic expenses and inventory purchases (the 485 sale model). Adds the
# correction link columns + list columns. No business data changes.
#
#   .\apply-generic-expense-purchase-correction.ps1 -Database VisibilityCoreDB          # measure + trial
#   .\apply-generic-expense-purchase-correction.ps1 -Database VisibilityCoreDB -Apply   # ... then apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'generic-expense-purchase-correction'),
    # Apply only these (e.g. -Only 422_FlockReportsSkipDeletedAndPending.postgres.sql when 420/421 are already in).
    [string[]] $Only,
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files  = @('520_Enock_GenericExpensePurchaseCorrection.postgres.sql')
if ($Only) { $files = @($files | Where-Object { $Only -contains $_ }); if (-not $files) { throw 'Nothing matches -Only.' } }
$checks = @('generic-520-expense-purchase-correction.test.sql', 'generic-500-purchase-reversal.test.sql', 'generic-504-expense-reversal.test.sql', 'generic-505-expense-list-reversed.test.sql', 'generic-catchup-smoke.test.sql')
$passMarkers = @('generic 520: all checks passed', 'generic 500: all checks passed', 'generic 504: all checks passed', 'generic 505: all checks passed', 'generic catch-up: all checks passed')
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
    Write-Host 'Stopping here. Re-run with -Apply to commit. The API that calls these is not deployed yet.' -ForegroundColor Yellow
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
