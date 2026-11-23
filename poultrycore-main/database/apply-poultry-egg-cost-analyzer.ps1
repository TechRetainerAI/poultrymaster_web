# =============================================================================
# Apply migration 481 (Egg Cost & Profit Analyzer). New tables for the
# analyzer's own settings / assumptions / historical costs / snapshots / audit,
# and NEW functions only -- no existing function is replaced, no business row
# is written. The measurements include every company's P&L lines, Cost Per Egg
# and Feed Cost Per Egg outputs, which must be identical before and after.
#
#   .pply-water-production-reopen-stock.ps1           # measure + dry run
#   .pply-water-production-reopen-stock.ps1 -Apply    # ... then apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'poultry-egg-cost-analyzer'),
    # Apply only these (e.g. -Only 422_FlockReportsSkipDeletedAndPending.postgres.sql when 420/421 are already in).
    [string[]] $Only,
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files  = @('481_PoultryEggCostAnalyzer.postgres.sql')
if ($Only) { $files = @($files | Where-Object { $Only -contains $_ }); if (-not $files) { throw 'Nothing matches -Only.' } }
$checks = @('poultry-481-egg-cost-analyzer.test.sql')
$passMarkers = @('poultry 481: all checks passed')
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
\echo '-- business row counts'
SELECT 'expense', count(*), sum(amount) FROM public.expense UNION ALL
SELECT 'cash', count(*), sum(amount) FROM public.poultrycashtransactions UNION ALL
SELECT 'payments', count(*), sum(amount) FROM public.poultrypayments UNION ALL
SELECT 'stock', count(*), sum(quantity) FROM public.poultrystocktransactions UNION ALL
SELECT 'records', count(*), sum(totalproduction) FROM public.productionrecords UNION ALL
SELECT 'sales', count(*), sum(totalamount) FROM public.sale;
\echo '-- P&L lines per company, all time'
SELECT f.farmid, md5(string_agg(l::text, '|' ORDER BY l::text))
FROM (SELECT DISTINCT farmid FROM public.productionrecords) f
CROSS JOIN LATERAL public.sppoultryreport_pllines(f.farmid, DATE '2000-01-01', current_date) l GROUP BY 1 ORDER BY 1;
\echo '-- Cost Per Egg and Feed Cost Per Egg per company, last year'
SELECT f.farmid, md5(string_agg(c::text, '|' ORDER BY c::text))
FROM (SELECT DISTINCT farmid FROM public.productionrecords) f
CROSS JOIN LATERAL public.sppoultryreport_costperegg(f.farmid, current_date - 365, current_date, NULL, true, NULL) c GROUP BY 1 ORDER BY 1;
SELECT f.farmid, md5(string_agg(c::text, '|' ORDER BY c::text))
FROM (SELECT DISTINCT farmid FROM public.productionrecords) f
CROSS JOIN LATERAL public.sppoultryreport_feedcostperegg(f.farmid, current_date - 365, current_date, NULL, true, NULL) c GROUP BY 1 ORDER BY 1;
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
    Write-Host 'Stopping here. Re-run with -Apply to commit. Then deploy the API, then the web.' -ForegroundColor Yellow
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
