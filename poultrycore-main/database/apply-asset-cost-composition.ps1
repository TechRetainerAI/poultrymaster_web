# =============================================================================
# Apply migrations 313-314 (capital asset cost composition and original-cost
# correction) to Postgres.
#
# Same four phases as apply-generic-subscriptions.ps1:
#
#   1. MEASURE   every asset's cost, depreciation and book value, plus the cash
#                and payable totals behind them, BEFORE anything changes.
#   2. DRY RUN   both migrations PLUS both behavioural check files inside a
#                single transaction that is then ROLLED BACK. This validates
#                syntax AND behaviour without committing a row.
#   3. APPLY     the two files in order, each in its own transaction.
#   4. MEASURE   the same totals again and diff them.
#
# EFFECT ON TODAY'S NUMBERS: none. Both migrations widen a CHECK constraint, add
# functions, and rebuild two read functions with extra columns. No existing row
# is written. Phase 4 must print "No change to any measured total." Anything
# else is a bug, with no exceptions.
#
# WHAT PHASE 1 MEASURES, AND WHY THOSE COLUMNS
# --------------------------------------------
# The whole change is about one number being split into two. So the measurement
# reads the TOTAL from the function that has always produced it
# (fn*capitalasset_originalcost) -- NOT from the new halves -- and pairs it with
# accumulated depreciation, book value, cash and payables. If the split were
# wrong, or a read were rebuilt with a column in the wrong place, the total would
# move and phase 4 would say so.
#
# The check files then assert the other direction inside the dry run: that the
# two new halves add back to exactly that total, for every asset on the database.
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-asset-cost-composition.ps1                 # measure + dry run only
#   .\apply-asset-cost-composition.ps1 -Apply          # ... then actually apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'asset-cost-composition'),
    # Without this the script measures and dry-runs, then stops. Applying is
    # opt-in on purpose: the dry run is the thing you want to read first.
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files = @('313_PoultryAssetCostComposition.postgres.sql',
           '314_WaterAssetCostComposition.postgres.sql')

foreach ($f in $files) {
    if (-not (Test-Path (Join-Path $MigrationsDir $f))) { throw "Missing migration: $f" }
}

$checkFiles = @(
    (Join-Path $ChecksDir 'poultry-asset-cost-composition.test.sql'),
    (Join-Path $ChecksDir 'water-asset-cost-composition.test.sql')
)
foreach ($c in $checkFiles) {
    if (-not (Test-Path $c)) { throw "Missing check file: $c" }
}

# Redirection is handed to cmd.exe rather than done in PowerShell on purpose.
# PowerShell 5.1 wraps a native command's stderr in ErrorRecords, so a single
# psql NOTICE -- of which these migrations emit several -- trips
# $ErrorActionPreference and aborts a run that was going fine.
function Invoke-Psql {
    param([string] $File, [string] $LogPath)
    $line = '"{0}" -h {1} -p {2} -U {3} -d {4} -X -w -v ON_ERROR_STOP=1 -f "{5}"' -f `
            $Psql, $DbHost, $Port, $User, $Database, $File
    if ($LogPath) { $line += ' > "{0}" 2>&1' -f $LogPath }
    & cmd.exe /c $line
    return $LASTEXITCODE
}

# --- the same measurement, before and after ---------------------------------
# Deliberately reads originalcost (the TOTAL, under 270/283's name) rather than
# the new halves: this is the number that must not move, and reading it through
# the function that has always produced it is the only way to prove it did not.
$measureSql = @'
\pset footer off
SELECT 'poultry' AS module, f.farmid, f.name,
       (SELECT COUNT(*) FROM poultrycapitalassets a WHERE a.farmid = f.farmid)                  AS assets,
       (SELECT COUNT(*) FROM poultrycapitalassetcosts c WHERE c.farmid = f.farmid)              AS cost_rows,
       (SELECT ROUND(COALESCE(SUM(fnpoultrycapitalasset_originalcost(a.poultrycapitalassetid)), 0), 2)
          FROM poultrycapitalassets a WHERE a.farmid = f.farmid)                                AS total_cost,
       (SELECT ROUND(COALESCE(SUM(fnpoultrycapitalasset_accumulated(a.poultrycapitalassetid)), 0), 2)
          FROM poultrycapitalassets a WHERE a.farmid = f.farmid)                                AS accumulated,
       (SELECT ROUND(COALESCE(SUM(s.currentbookvalue), 0), 2)
          FROM sppoultrycapitalasset_summary(f.farmid) s)                                       AS book_value,
       (SELECT COUNT(*) FROM poultryassetdepreciation d WHERE d.farmid = f.farmid)              AS dep_rows,
       (SELECT ROUND(COALESCE(SUM(c.currentbalance), 0), 2) FROM poultrycashaccounts c
         WHERE c.farmid = f.farmid)                                                             AS cash,
       (SELECT ROUND(COALESCE(SUM(p.balance), 0), 2) FROM fnpoultrypayables(f.farmid) p)        AS payables
FROM   farms f
WHERE  f.type = 'Poultry'
ORDER  BY f.farmid;

SELECT 'water' AS module, f.farmid, f.name,
       (SELECT COUNT(*) FROM watercapitalassets a WHERE a.farmid = f.farmid)                    AS assets,
       (SELECT COUNT(*) FROM watercapitalassetcosts c WHERE c.farmid = f.farmid)                AS cost_rows,
       (SELECT ROUND(COALESCE(SUM(fnwatercapitalasset_originalcost(a.watercapitalassetid)), 0), 2)
          FROM watercapitalassets a WHERE a.farmid = f.farmid)                                  AS total_cost,
       (SELECT ROUND(COALESCE(SUM(fnwatercapitalasset_accumulated(a.watercapitalassetid)), 0), 2)
          FROM watercapitalassets a WHERE a.farmid = f.farmid)                                  AS accumulated,
       (SELECT ROUND(COALESCE(SUM(s.currentbookvalue), 0), 2)
          FROM spwatercapitalasset_summary(f.farmid) s)                                         AS book_value,
       (SELECT COUNT(*) FROM waterassetdepreciation d WHERE d.farmid = f.farmid)                AS dep_rows,
       (SELECT ROUND(COALESCE(SUM(c.currentbalance), 0), 2) FROM watercashaccounts c
         WHERE c.farmid = f.farmid)                                                             AS cash,
       (SELECT ROUND(COALESCE(SUM(p.balance), 0), 2) FROM fnwaterpayables(f.farmid) p)          AS payables
FROM   farms f
WHERE  f.type = 'Water'
ORDER  BY f.farmid;
'@

$measureFile = Join-Path $OutDir 'measure.sql'
Set-Content -Path $measureFile -Value $measureSql -Encoding utf8

Write-Host "Host:       $DbHost/$Database"
Write-Host "Migrations: $($files -join ', ')"
Write-Host ""

# --- phase 1: measure before -------------------------------------------------
Write-Host '=== 1. BEFORE ===' -ForegroundColor Cyan
$before = Join-Path $OutDir 'before.txt'
if ((Invoke-Psql -File $measureFile -LogPath $before) -ne 0) {
    Get-Content $before | Write-Host
    throw 'Could not read the baseline. Nothing has been changed.'
}
Get-Content $before | Write-Host

# --- phase 2: dry run, rolled back ------------------------------------------
# The files carry their own BEGIN;/COMMIT; and \set ON_ERROR_STOP. Strip both so
# both migrations -- and the behavioural checks that follow them -- run inside
# ONE transaction this script controls and then discards.
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

# The checks report themselves as NOTICEs reading "expect X got Y". A guard that
# did NOT refuse prints "got ALLOWED", and that is never acceptable.
$suspect = Get-Content $dryLog | Where-Object { $_ -match 'got ALLOWED' }
if ($suspect) {
    $suspect | Write-Host -ForegroundColor Red
    throw 'A negative case was NOT blocked. Read the dry-run log before applying.'
}

# The identity is the one assertion that must read exactly 0. If the halves stop
# adding to the whole, every screen downstream is lying and applying would ship
# that lie.
$identity = Get-Content $dryLog | Where-Object { $_ -match 'add(?:s)? to the whole' }
$identityBad = $identity | Where-Object { $_ -notmatch 'got 0\s*$' }
if ($identityBad) {
    $identityBad | Write-Host -ForegroundColor Red
    throw 'acquisition + additional does NOT equal the total. Do not apply.'
}
$identity | Write-Host -ForegroundColor Green

Write-Host 'Dry run clean -- syntax and behaviour validated, transaction discarded.' -ForegroundColor Green
Write-Host 'Read the "expect X got Y" lines above: every one must agree.' -ForegroundColor Yellow

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
        throw "$f failed (see $log). Migrations before it are committed; this one rolled back."
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
Write-Host '=== DIFF (expected: identical -- these migrations add, they do not rewrite) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host 'No change to any measured total.' -ForegroundColor Green
} else {
    $diff | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- nothing in 313-314 should move an existing number.' -ForegroundColor Red
}
