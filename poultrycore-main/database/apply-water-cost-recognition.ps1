# =============================================================================
# Apply the Water cost-recognition work (migrations 274+) to Postgres.
#
#   -Stage 1   274  the foundation: settings, item override, purchase snapshot,
#                   and the one resolver everything else will call
#   -Stage 2   275  purchase-time behaviour: a deferred purchase stops writing a
#                   P&L expense, at BOTH the purchase and the supplier payment
#   -Stage 3   276  permissions
#   -Stage 4   277  cost layers: the deferred balance on a lot and the pro-rata
#                   draw when stock is consumed
#   -Stage 5   278  the deferred cost is opened at purchase and carried through
#                   a production batch into the finished product
#   -Stage 6   279  consumption recognition: packaging and treatment reach the
#                   P&L when they are used, once, and come back on reversal
#   -Stage 7   280  the two inventory values and the cost-layer audit
#   -Stage 8   281  the read surface those numbers are shown through
#
# WHICH STAGES EXIST TODAY
# ========================
# Stages 1 and 3 (274, 276) are written. The rest are NOT, and the script throws
# "Missing migration" rather than pretending otherwise.
#
# The reason is the same one apply-water-phase3.ps1 gives for its stage 4, and
# it is worth stating once here in full because it shapes this whole workstream:
#
#   Poultry's equivalent chain (261-268) could rewrite
#   sppoultryrawmaterialpurchase_insert, _paybalance, _consumebatches and the
#   usage reads because migration 207 had restored those Postgres bodies INTO
#   THE REPO first. Every later migration copied from a definition it could
#   read.
#
#   Water's live Postgres bodies were ported outside version control. The repo
#   holds spWaterRawMaterialPurchase_* only as pre-migration T-SQL (044, 090,
#   091, 116, 146, 147, 190). Rewriting them from that would silently drop
#   whatever the live port actually does -- the FIFO/LIFO/HIFO lot ordering and
#   the purchase-unit conversion are exactly the kind of thing that fails
#   quietly and is discovered a month later in a stock count.
#
#   Stages 2 and 4-8 all rewrite one of those bodies. They are blocked on a dump
#   of the live definitions, not on design.
#
# 274 and 276 are unblocked because they are purely ADDITIVE: new tables, new
# columns, new resolvers, new permission keys. 274 reaches the item override
# through two small new functions instead of rewriting
# spwaterrawmaterialitem_update -- the same shape 240 chose for
# spwaterexpense_setpayment, and for the same reason.
#
# THE INTERLOCK IS WHAT MAKES STAGE 1 SAFE TO SHIP ALONE
# ======================================================
# Poultry never had this problem: 261 and 262 went out together, so the moment a
# farm could CHOOSE deferral, the migration that suppresses the purchase expense
# was already there. Applying 274 on its own opens a gap that would be quiet and
# expensive:
#
#   a company sets Packaging to EXPENSE_WHEN_CONSUMED -> 274 stamps each new
#   purchase deferred -> but 275 is not applied, so the purchase STILL writes
#   its P&L expense -> months later 279 lands, reads those snapshots, and
#   recognises the same cost AGAIN as the stock is consumed.
#
# So 274 ships fnwatercostrecognition_deferralready() returning FALSE, and both
# writers refuse EXPENSE_WHEN_CONSUMED while it does. Stage 6 (279) is the
# migration that replaces it with TRUE, and nothing else may.
#
# If you are writing 279: replacing that function is not optional housekeeping.
# Leaving it FALSE means the feature stays switched off for every company; making
# it TRUE before the purchase side is right means double-counting. The check file
# for stage 1 asserts the guard blocks, then lifts it inside its own rolled-back
# transaction to test the resolver.
#
# The four phases, as in apply-water-money.ps1:
#
#   1. MEASURE   every water company's expense total, expense row count,
#                raw-material stock and cash, BEFORE anything changes.
#   2. DRY RUN   the migration PLUS the behavioural check file inside a single
#                transaction that is then ROLLED BACK.
#   3. APPLY     the migration in its own transaction.
#   4. MEASURE   the same totals again and diff them.
#
# EFFECT ON TODAY'S NUMBERS: none, at every stage -- as long as no company has
# changed its settings. Phase 4 must print "No change to any measured total."
#
# Usage (password is read from the environment, never passed on the command line):
#
#   $env:PGPASSWORD = '<password>'
#   .\apply-water-cost-recognition.ps1 -Stage 1
#   .\apply-water-cost-recognition.ps1 -Stage 1 -Apply
#
# Requires the dev machine's public IP to be on the Cloud SQL authorized-networks
# list, or every psql call times out. See the cloudsql-ip-allowlist note.
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 8)]
    [int]    $Stage,
    [string] $DbHost   = '34.175.134.7',
    [int]    $Port     = 5432,
    [string] $Database = 'VisibilityCoreDB',
    [string] $User     = 'poultryapp',
    [string] $Psql     = 'C:\Program Files\PostgreSQL\18\bin\psql.exe',
    [string] $MigrationsDir = (Join-Path $PSScriptRoot '..\..\poultrycore_Backend\PoultryFarmAPI\Migrations'),
    [string] $ChecksDir = (Join-Path $PSScriptRoot 'checks'),
    [string] $OutDir   = (Join-Path $env:TEMP 'water-cost-recognition'),
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'

if (-not $env:PGPASSWORD) { throw 'Set $env:PGPASSWORD first.' }
if (-not (Test-Path $Psql)) { throw "psql not found at $Psql" }
if (-not (Test-Path $MigrationsDir)) { throw "Migrations dir not found: $MigrationsDir" }

$stages = @{
    1 = @{ Migration = '274_WaterCostRecognitionFoundation.postgres.sql';    Check = 'water-cost-recognition-foundation.test.sql' }
    2 = @{ Migration = '275_WaterDeferredPurchaseExpense.postgres.sql';      Check = 'water-deferred-purchase-expense.test.sql' }
    3 = @{ Migration = '276_WaterFinancialSettingsPermissions.postgres.sql'; Check = 'water-financial-settings-permissions.test.sql' }
    # ---- Phase 2 ------------------------------------------------------------
    4 = @{ Migration = '277_WaterDeferredCostLayers.postgres.sql';           Check = 'water-deferred-cost-layers.test.sql' }
    5 = @{ Migration = '278_WaterDeferredCostTransfer.postgres.sql';         Check = 'water-deferred-cost-transfer.test.sql' }
    6 = @{ Migration = '279_WaterConsumptionRecognition.postgres.sql';       Check = 'water-consumption-recognition.test.sql' }
    7 = @{ Migration = '280_WaterCostLayerGuards.postgres.sql';              Check = 'water-cost-layer-guards.test.sql' }
    8 = @{ Migration = '281_WaterCostRecognitionReads.postgres.sql';         Check = 'water-cost-recognition-reads.test.sql' }
}
$plan = $stages[$Stage]
$files = @($plan.Migration)
$OutDir = Join-Path $OutDir "stage$Stage"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

foreach ($f in $files) {
    if (-not (Test-Path (Join-Path $MigrationsDir $f))) {
        if ($Stage -in 2, 4, 5, 6, 7, 8) {
            throw "Stage $Stage ($f) has not been written yet -- it rewrites a live water SP whose Postgres body is not in this repo. See the header."
        }
        throw "Missing migration: $f"
    }
}

$checkFile = Join-Path $ChecksDir $plan.Check
if (-not (Test-Path $checkFile)) { throw "Missing check file: $checkFile" }

# Redirection is handed to cmd.exe rather than done in PowerShell on purpose.
# PowerShell 5.1 wraps a native command's stderr in ErrorRecords, so a single
# psql NOTICE -- of which these dry runs emit dozens -- trips
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
# Base tables rather than the P&L report: spwaterreport_periodpnl's Postgres
# signature is not in this repo to call. See apply-water-phase3.ps1's header.
$measureSql = @'
\pset footer off
SELECT 'water' AS metric, f.farmid, f.name,
       (SELECT COUNT(*) FROM waterrawmaterialitems i WHERE i.farmid = f.farmid)               AS items,
       (SELECT ROUND(COALESCE(SUM(i.currentquantity), 0), 2) FROM waterrawmaterialitems i
         WHERE i.farmid = f.farmid)                                                            AS stock_qty,
       (SELECT COUNT(*) FROM waterrawmaterialpurchases pu WHERE pu.farmid = f.farmid)          AS purchases,
       (SELECT ROUND(COALESCE(SUM(pu.totalcost), 0), 2) FROM waterrawmaterialpurchases pu
         WHERE pu.farmid = f.farmid)                                                           AS purchase_cost,
       (SELECT ROUND(COALESCE(SUM(pu.amountpaid), 0), 2) FROM waterrawmaterialpurchases pu
         WHERE pu.farmid = f.farmid)                                                           AS purchase_paid,
       (SELECT COUNT(*) FROM waterexpenses e
         WHERE e.farmid = f.farmid AND COALESCE(e.isdeleted, FALSE) = FALSE)                   AS expense_rows,
       (SELECT ROUND(COALESCE(SUM(e.amount), 0), 2) FROM waterexpenses e
         WHERE e.farmid = f.farmid AND COALESCE(e.isdeleted, FALSE) = FALSE)                   AS expense_total,
       (SELECT ROUND(COALESCE(SUM(e.amount), 0), 2) FROM waterexpenses e
         WHERE e.farmid = f.farmid AND COALESCE(e.isdeleted, FALSE) = FALSE
           AND COALESCE(e.status, '') = 'Approved')                                            AS approved_expense,
       (SELECT ROUND(COALESCE(SUM(a.currentbalance), 0), 2) FROM watercashaccounts a
         WHERE a.farmid = f.farmid)                                                            AS cash,
       (SELECT ROUND(COALESCE(SUM(p.balance), 0), 2) FROM fnwaterpayables(f.farmid) p)         AS payables
FROM   farms f
WHERE  f.type = 'Water'
  AND  EXISTS (SELECT 1 FROM waterrawmaterialitems i WHERE i.farmid = f.farmid)
ORDER  BY f.farmid;
'@

$measureFile = Join-Path $OutDir 'measure.sql'
Set-Content -Path $measureFile -Value $measureSql -Encoding utf8

Write-Host "Host:       $DbHost/$Database"
Write-Host "Stage:      $Stage  ($($plan.Migration))"
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
# the exit code: a resolver that returns the WRONG method still returns cleanly.
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
    Get-Content $log | Write-Host
}

# --- phase 4: measure after and diff ----------------------------------------
Write-Host ''
Write-Host '=== 4. AFTER ===' -ForegroundColor Cyan
$after = Join-Path $OutDir 'after.txt'
[void](Invoke-Psql -File $measureFile -LogPath $after)
Get-Content $after | Write-Host

Write-Host ''
Write-Host '=== DIFF (expected: identical -- no company has asked for a different method) ===' -ForegroundColor Cyan
$diff = Compare-Object (Get-Content $before) (Get-Content $after)
if (-not $diff) {
    Write-Host 'No change to any measured total.' -ForegroundColor Green
} else {
    $diff | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host 'A moved approved_expense here is the serious one: it means a company''s P&L changed without anyone choosing it.' -ForegroundColor Red
}

Write-Host ''
Write-Host 'RESTART THE API when the backend stages land.' -ForegroundColor Yellow
