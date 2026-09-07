# =============================================================================
# Apply migration 251 (the Generic module toggles and company settings) to
# Postgres.
#
# Same four phases as apply-generic-subscriptions.ps1:
#
#   1. MEASURE   every Generic company's sales, expenses, cash, customer
#                balances and P&L totals, BEFORE anything changes.
#   2. DRY RUN   the migration PLUS the behavioural check file inside a single
#                transaction that is then ROLLED BACK. This validates syntax
#                AND behaviour without committing a row.
#   3. APPLY     the migration in its own transaction.
#   4. MEASURE   the same totals again and diff them.
#
# EFFECT ON TODAY'S NUMBERS: none. Two boolean columns defaulting TRUE on a
# settings table, one new settings table, and functions. Phase 4 must print
# "No change to any measured total."
#
# The one BEHAVIOUR this migration can change is auto-posting invoices, and it
# ships FALSE: every existing company keeps the draft-then-approve flow 243 gave
# it until someone turns the setting on. The dry run proves both halves.
#
# It also fixes a live bug on the way past: saving module settings mapped a
# void-returning upsert as if it returned the row, so the endpoint 500'd AFTER
# writing. That is a C# fix, not a SQL one -- restart the API for it.
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-generic-subscription-reporting.ps1            # measure + dry run only
#   .\apply-generic-subscription-reporting.ps1 -Apply     # ... then actually apply
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
    [string] $OutDir   = (Join-Path $env:TEMP 'generic-business-settings'),
    # Without this the script measures and dry-runs, then stops. Applying is
    # opt-in on purpose: the dry run is the thing you want to read first.
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$files = @('251_GenericBusinessSettings.postgres.sql')

foreach ($f in $files) {
    if (-not (Test-Path (Join-Path $MigrationsDir $f))) { throw "Missing migration: $f" }
}

$checkFile = Join-Path $ChecksDir 'generic-business-settings.test.sql'
if (-not (Test-Path $checkFile)) { throw "Missing check file: $checkFile" }

# Redirection is handed to cmd.exe rather than done in PowerShell on purpose.
# PowerShell 5.1 wraps a native command's stderr in ErrorRecords, so a single
# psql NOTICE -- of which this dry run emits about fifty -- trips
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
# Reads the reporting functions as well as the tables: spgenericreport_periodpnl
# is what the owner actually looks at, and it is what must not move.
$measureSql = @'
\pset footer off
SELECT 'generic' AS metric, f.farmid, f.name,
       (SELECT COUNT(*) FROM genericsales s
         WHERE s.farmid = f.farmid AND NOT COALESCE(s.isdeleted, FALSE))                        AS sales,
       (SELECT ROUND(COALESCE(SUM(s.totalamount), 0), 2) FROM genericsales s
         WHERE s.farmid = f.farmid AND NOT COALESCE(s.isdeleted, FALSE))                        AS sales_amount,
       (SELECT ROUND(COALESCE(SUM(s.balance), 0), 2) FROM genericsales s
         WHERE s.farmid = f.farmid AND NOT COALESCE(s.isdeleted, FALSE))                        AS sales_balance,
       (SELECT COUNT(*) FROM genericexpenses e
         WHERE e.farmid = f.farmid AND NOT COALESCE(e.isdeleted, FALSE))                        AS expenses,
       (SELECT ROUND(COALESCE(SUM(e.amount), 0), 2) FROM genericexpenses e
         WHERE e.farmid = f.farmid AND NOT COALESCE(e.isdeleted, FALSE))                        AS expense_amount,
       (SELECT ROUND(COALESCE(SUM(c.currentbalance), 0), 2) FROM genericcashaccounts c
         WHERE c.farmid = f.farmid)                                                             AS cash,
       (SELECT ROUND(COALESCE(SUM(k.currentbalance), 0), 2) FROM genericcustomers k
         WHERE k.farmid = f.farmid)                                                             AS customer_balance,
       (SELECT COUNT(*) FROM genericsubscriptions v WHERE v.farmid = f.farmid)                  AS subscriptions,
       (SELECT COUNT(*) FROM genericstaffpayments p WHERE p.farmid = f.farmid)                  AS staff_payments,
       (SELECT COUNT(*) FROM genericsales s
         WHERE s.farmid = f.farmid AND s.status = 'Draft'
           AND s.genericsubscriptionid IS NOT NULL)                                             AS draft_invoices,
       (SELECT ROUND(COALESCE(SUM(p.totalincome), 0), 2)
          FROM spgenericreport_periodpnl(f.farmid, '2000-01-01', '2099-12-31') p)               AS pnl_income,
       (SELECT ROUND(COALESCE(SUM(p.netprofit), 0), 2)
          FROM spgenericreport_periodpnl(f.farmid, '2000-01-01', '2099-12-31') p)               AS pnl_net
FROM   farms f
WHERE  f.type = 'Generic'
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
# the migration AND the behavioural checks run inside ONE transaction this
# script controls and then discards.
Write-Host ''
Write-Host '=== 2. DRY RUN (rolled back) ===' -ForegroundColor Cyan
$dryFile = Join-Path $OutDir 'dryrun.sql'
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('BEGIN;')
foreach ($f in ($files + @($checkFile))) {
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

# Every check line reads "expect X got Y". Compare the two rather than trusting
# the exit code: a report that returns the WRONG number still returns cleanly.
# 0 and 0.00 are the same number written two ways, so they are normalised.
$mismatch = Get-Content $dryLog | Where-Object {
    if ($_ -match 'expect\s+(\S+)\s+got\s+(\S+)\s*$') {
        $a = $matches[1]; $b = $matches[2]
        if ($a -as [decimal] -ne $null -and $b -as [decimal] -ne $null) {
            [decimal]$a -ne [decimal]$b
        } else { $a -ne $b }
    } else { $false }
}
if ($mismatch) {
    $mismatch | Write-Host -ForegroundColor Red
    throw 'A check did not get what it expected. Read the dry-run log before applying.'
}

# The negative cases report themselves rather than failing the script, so an
# unblocked one would otherwise pass silently.
$allowed = Get-Content $dryLog | Where-Object { $_ -match '<-- BUG, allowed' }
if ($allowed) {
    $allowed | Write-Host -ForegroundColor Red
    throw 'A negative case was NOT blocked. Read the dry-run log before applying.'
}
Write-Host 'Dry run clean -- every "expect X got Y" agrees, transaction discarded.' -ForegroundColor Green

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
        throw "$f failed (see $log). It rolled back; nothing is half-applied."
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
Write-Host '=== DIFF (expected: identical -- nothing here changes a document) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host 'No change to any measured total.' -ForegroundColor Green
} else {
    $diff | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'Any line here is a bug -- 251 only adds settings.' -ForegroundColor Red
}

Write-Host ''
Write-Host 'RESTART THE API. The two new module toggles and the settings endpoints' -ForegroundColor Yellow
Write-Host 'need the new assembly -- and until it is running, saving module settings' -ForegroundColor Yellow
Write-Host 'still hits the old mapping bug this chunk fixed.' -ForegroundColor Yellow
