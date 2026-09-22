# =============================================================================
# Apply migration 316 (the water Profit & Loss analytical layer) to Postgres.
#
# Same four phases as the other apply scripts, and phase 1 measures the one
# thing this migration is forbidden to change:
#
#   1. MEASURE   spwaterreport_periodpnl for EVERY water company -- income, raw
#                materials, production cost, expenses, losses and NET PROFIT.
#   2. DRY RUN   the migration plus its behavioural checks inside a single
#                transaction that is then ROLLED BACK.
#   3. APPLY     the migration in its own transaction.
#   4. MEASURE   the same figures again and diff them.
#
# WHY THAT MEASUREMENT
# --------------------
# 316 adds a statement, a summary and seven drilldowns on top of
# spwaterreport_periodpnl. It does NOT rebuild the water P&L on the poultry
# classification model, because doing so would have restated what these
# companies report as profit -- on dev, a 123,063.58 figure assembled from five
# sources the classification model reads differently.
#
# So periodpnl is the authority and must come out of this untouched. Phase 4
# must print "No change to any reported figure." The dry run separately asserts
# the other direction: that the new statement's bands total periodpnl's
# components exactly, and that every drilldown sums to the line it opens.
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-water-pl-analysis.ps1                 # measure + dry run only
#   .\apply-water-pl-analysis.ps1 -Apply          # ... then actually apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'water-pl-analysis'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files = @('316_WaterProfitLossAnalysis.postgres.sql')
foreach ($f in $files) {
    if (-not (Test-Path (Join-Path $MigrationsDir $f))) { throw "Missing migration: $f" }
}

$checkFiles = @((Join-Path $ChecksDir 'water-profit-loss-analysis.test.sql'))
foreach ($c in $checkFiles) {
    if (-not (Test-Path $c)) { throw "Missing check file: $c" }
}

# Redirection is handed to cmd.exe rather than done in PowerShell on purpose.
# PowerShell 5.1 wraps a native command's stderr in ErrorRecords, so a single
# psql NOTICE trips $ErrorActionPreference and aborts a run that was going fine.
function Invoke-Psql {
    param([string] $File, [string] $LogPath)
    $line = '"{0}" -h {1} -p {2} -U {3} -d {4} -X -w -v ON_ERROR_STOP=1 -f "{5}"' -f `
            $Psql, $DbHost, $Port, $User, $Database, $File
    if ($LogPath) { $line += ' > "{0}" 2>&1' -f $LogPath }
    & cmd.exe /c $line
    return $LASTEXITCODE
}

# --- the same measurement, before and after ---------------------------------
# The authority itself, for every water company and over all time.
$measureSql = @'
\pset footer off
\pset pager off
SELECT f.farmid, f.name,
       p.totalincome, p.rawmaterialcost, p.productioncost,
       p.totalexpenses, p.totallosses, p.netprofit, p.profitmarginpct,
       p.bagsproduced, p.bagssold, p.avgprofitperbag
FROM   farms f
CROSS  JOIN LATERAL public.spwaterreport_periodpnl(f.farmid, '2000-01-01', '2099-12-31') p
WHERE  f.type = 'Water'
ORDER  BY f.farmid;
'@

$measureFile = Join-Path $OutDir 'measure.sql'
Set-Content -Path $measureFile -Value $measureSql -Encoding utf8

Write-Host "Host:       $DbHost/$Database"
Write-Host "Migration:  $($files -join ', ')"
Write-Host ""

# --- phase 1: measure before -------------------------------------------------
Write-Host '=== 1. BEFORE (spwaterreport_periodpnl -- the authority) ===' -ForegroundColor Cyan
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
foreach ($f in ($files + $checkFiles)) {
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

# Every reconciliation assertion prints "expect 0.00 diff got X". Any X that is
# not 0.00 means a band or a drilldown disagrees with the authority, and the
# whole point of this migration was that they cannot.
$bad = Get-Content $dryLog |
    Where-Object { $_ -match 'expect 0\.00 diff' } |
    Where-Object { $_ -notmatch 'got 0\.00\s*$' }
if ($bad) {
    $bad | Write-Host -ForegroundColor Red
    throw 'The statement does NOT reconcile to spwaterreport_periodpnl. Do not apply.'
}
$recon = Get-Content $dryLog | Where-Object { $_ -match 'expect 0\.00 diff' }
if (-not $recon) { throw 'The reconciliation assertions did not run at all. Do not apply.' }
Write-Host "$($recon.Count) reconciliation assertion(s), all exact." -ForegroundColor Green

Write-Host 'Dry run clean -- syntax and behaviour validated, transaction discarded.' -ForegroundColor Green

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
[void](Invoke-Psql -File $measureFile -LogPath $after)
Get-Content $after | Write-Host

Write-Host ''
Write-Host '=== DIFF (expected: identical -- 316 adds reads, it restates nothing) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host 'No change to any reported figure.' -ForegroundColor Green
} else {
    $diff | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- net profit was not 316''s to change.' -ForegroundColor Red
}
