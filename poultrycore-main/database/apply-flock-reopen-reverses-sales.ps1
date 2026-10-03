# =============================================================================
# Apply migration 339 (reopening a flock reverses its closeout sales) to Postgres.
#
# Same four phases as apply-flock-closeout.ps1, which it is copied from:
# measure, dry run (migration + BOTH closeout check files, rolled back), apply,
# measure and diff.
#
# 339 only rebuilds spflock_reopen and the history reader and adds three
# snapshot columns. It moves no money until someone reopens a flock, so phase 4
# must show no change to flocks, the bird ledger, cash-account balances or
# payment statuses.
#
#   $env:PGPASSWORD = '<password>'
#   .pply-flock-reopen-reverses-sales.ps1          # measure + dry run
#   .pply-flock-reopen-reverses-sales.ps1 -Apply   # ... then apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'flock-reopen-reverses-sales'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files  = @('339_FlockReopenReversesSales.postgres.sql')
$checks = @('poultry-flock-closeout.test.sql', 'poultry-flock-reopen-reverses-sales.test.sql')
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
\echo '-- cash account balances'
SELECT poultrycashaccountid, farmid, currentbalance FROM public.poultrycashaccounts ORDER BY poultrycashaccountid;
\echo '-- payment statuses'
SELECT COALESCE(status, 'Posted') AS status, COUNT(*), SUM(amount) FROM public.poultrypayments GROUP BY 1 ORDER BY 1;
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
$passed = Get-Content $dryLog | Where-Object { $_ -match ': all checks passed' }
if (@($passed).Count -ne $checks.Count) {
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
Write-Host '=== DIFF (expected: identical -- 339 reopens nothing) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host "No change to any flock, bird-ledger total or missing-records total. ($((Get-Content $after).Count) lines compared)" -ForegroundColor Green
} else {
    $diff | Select-Object -First 40 | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- 339 must not move a number until a flock is reopened.' -ForegroundColor Red
}
