# =============================================================================
# Apply migration 338 (end-of-flock closeout) to Postgres.
#
# Same four phases as the other apply scripts:
#
#   1. MEASURE   every flock row, the bird ledger per farm, and every flock's
#                bird position as today's readers compute it.
#   2. DRY RUN   the migration AND checks/poultry-flock-closeout.test.sql inside
#                one transaction that is then ROLLED BACK.
#   3. APPLY     the migration in its own transaction.
#   4. MEASURE   again and diff.
#
# WHAT THE MEASUREMENT IS FOR
# ---------------------------
# 338 closes no flock. It adds columns (all NULL), tables (empty), guards that
# only fire on a closed flock, and rebuilds two readers and the Missing Daily
# Records report. So phase 4 must print "No change" for the flocks, the bird
# ledger AND the missing-records totals. The last one matters: the report now
# includes closed flocks up to their closing date, and with none closed yet
# its numbers must be exactly what they were.
#
# The dry run carries the behavioural checks (~100 of them: all sold, transfer,
# unresolved balance, opening history, pen release, guards, sales and cash,
# lifetime metrics, reopen, audit, permissions). They RAISE on any failure, so
# a failing check stops the script before anything is committed.
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-flock-closeout.ps1                 # measure + dry run
#   .\apply-flock-closeout.ps1 -Apply          # ... then apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'flock-closeout'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files  = @('338_PoultryFlockCloseout.postgres.sql')
$checks = @('poultry-flock-closeout.test.sql')
foreach ($f in $files)  { if (-not (Test-Path (Join-Path $MigrationsDir $f))) { throw "Missing migration: $f" } }
foreach ($c in $checks) { if (-not (Test-Path (Join-Path $ChecksDir $c)))     { throw "Missing check: $c" } }

# Redirection is handed to cmd.exe rather than done in PowerShell on purpose.
# PowerShell 5.1 wraps a native command's stderr in ErrorRecords, so a single
# psql NOTICE -- of which the checks emit about a hundred -- trips
# $ErrorActionPreference and aborts a run that was going fine.
function Invoke-Psql {
    param([string] $File, [string] $LogPath)
    $line = '"{0}" -h {1} -p {2} -U {3} -d {4} -X -w -v ON_ERROR_STOP=1 -f "{5}"' -f `
            $Psql, $DbHost, $Port, $User, $Database, $File
    if ($LogPath) { $line += ' > "{0}" 2>&1' -f $LogPath }
    & cmd.exe /c $line
    return $LASTEXITCODE
}

# --- the measurement, before and after ----------------------------------------
# Ordered by key so a diff is a diff, not a re-sort. The flock columns are the
# ones that existed before 338, so the "before" query runs on either schema.
$measureSql = @'
\pset footer off
\pset pager off
\echo '-- flocks'
SELECT flockid, farmid, name, quantity, active, hasarrived, houseid, batchid,
       inactivationreason, otherreason, isdeleted, startdate
FROM   public.flock
ORDER  BY flockid;
\echo '-- bird ledger per farm and txntype'
SELECT t.farmid, t.txntype, COUNT(*) AS n, SUM(t.quantity) AS qty
FROM   public.poultrystocktransactions t
JOIN   public.poultryproducts p ON p.poultryproductid = t.poultryproductid
WHERE  p.isbirdproduct OR p.name = 'Birds'
GROUP  BY t.farmid, t.txntype
ORDER  BY t.farmid, t.txntype;
\echo '-- missing daily records, last 60 days, per farm'
SELECT f.farmid, r.*
FROM   (SELECT DISTINCT farmid FROM public.flock) f
CROSS  JOIN LATERAL public.sppoultryreport_missingdailyrecords_rs2(
           f.farmid, (now() AT TIME ZONE 'utc')::date - 60, (now() AT TIME ZONE 'utc')::date, NULL) r
ORDER  BY f.farmid;
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
Get-Content $dryLog | Where-Object { $_ -match 'FAIL|ERROR|all checks passed|338:' } | Write-Host
if ($dryCode -ne 0) {
    throw "DRY RUN FAILED (see $dryLog). Nothing has been changed."
}
$passed = Get-Content $dryLog | Where-Object { $_ -match 'poultry-flock-closeout: all checks passed' }
if (-not $passed) {
    throw 'The closeout checks did not report success. Do not apply.'
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
Write-Host '=== DIFF (expected: identical -- 338 closes nothing) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host "No change to any flock, bird-ledger total or missing-records total. ($((Get-Content $after).Count) lines compared)" -ForegroundColor Green
} else {
    $diff | Select-Object -First 40 | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- 338 must not move a number until a flock is closed.' -ForegroundColor Red
}
