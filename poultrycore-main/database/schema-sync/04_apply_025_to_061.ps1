# =============================================================================
# STEP 4: Apply migrations 025 -> 061 to prod in order.
#
# Run AFTER:
#   * 01_backup_prod.sql (you have an off-box .bak)
#   * 03_verify_prod_state.sql (you've eyeballed the 5 numbers)
#
# Run AS:
#   * A login with db_owner OR db_ddladmin on the prod DB. NOT the
#     application login (sqlserver) -- it lacks DDL rights.
#
# What this script does:
#   * Runs each migration with `sqlcmd -b` so SQL errors halt the script.
#   * Pauses for human confirmation before the three risky migrations:
#       046 (BackfillOrphanFarmIds)
#       053 (FixSpCreateFarmAndCleanupBrokenRows)
#       054 (FixCompanySpsAndFinishFarmIdRebind)
#   * Each pause prints the relevant pre-check query so you can run it
#     in SSMS, see the rowcount, and decide before typing 'yes'.
#
# Does NOT:
#   * Take a backup (use 01_backup_prod.sql first).
#   * Modify Cloud Run services.
#   * Anything destructive without your typed confirmation.
#
# Usage:
#   .\04_apply_025_to_061.ps1 -Server 34.39.109.13 -Database <PROD_DB> `
#                             -User <db_owner_login> -Password <pwd>
#
# Or wire it to an integrated-auth account by passing -IntegratedAuth:
#   .\04_apply_025_to_061.ps1 -Server 34.39.109.13 -Database <PROD_DB> -IntegratedAuth
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]  [string] $Server,
    [Parameter(Mandatory = $true)]  [string] $Database,
    [Parameter(Mandatory = $false)] [string] $User,
    [Parameter(Mandatory = $false)] [string] $Password,
    [Parameter(Mandatory = $false)] [switch] $IntegratedAuth,
    [Parameter(Mandatory = $false)] [string] $MigrationsDir = (Join-Path $PSScriptRoot '..\..\poultrycore\PoultryFarmAPI\Migrations')
)

$ErrorActionPreference = 'Stop'

# ---------- helpers ----------
function Invoke-Sqlcmd-File {
    param([string] $File)

    if (-not (Test-Path $File)) { throw "Migration file not found: $File" }

    Write-Host ""
    Write-Host "----------------------------------------------------------------"
    Write-Host "Applying: $(Split-Path -Leaf $File)"
    Write-Host "----------------------------------------------------------------"

    $argList = @(
        '-S', $Server,
        '-d', $Database,
        '-b',                     # exit non-zero on any T-SQL error
        '-I',                     # SET QUOTED_IDENTIFIER ON
        '-i', $File
    )
    if ($IntegratedAuth) {
        $argList += '-E'
    } else {
        if (-not $User -or -not $Password) {
            throw "Either -IntegratedAuth or both -User and -Password are required."
        }
        $argList += @('-U', $User, '-P', $Password)
    }

    & sqlcmd @argList
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd exited with code $LASTEXITCODE on $(Split-Path -Leaf $File). Stopping."
    }
}

function Confirm-Or-Halt {
    param([string] $Prompt)
    Write-Host ""
    Write-Host $Prompt -ForegroundColor Yellow
    $response = Read-Host "Type exactly 'yes' to proceed (anything else halts)"
    if ($response -ne 'yes') {
        Write-Host "Halted by user. No further migrations applied." -ForegroundColor Red
        exit 1
    }
}

# ---------- preflight ----------
Write-Host "Server:   $Server"
Write-Host "Database: $Database"
Write-Host "Auth:     $(if ($IntegratedAuth) {'Integrated'} else {"SQL login $User"})"
Write-Host "Source:   $MigrationsDir"
Write-Host ""

if (-not (Test-Path $MigrationsDir)) {
    throw "Migrations directory not found: $MigrationsDir"
}

Confirm-Or-Halt "About to apply migrations 025 -> 061 to '$Database' on '$Server'. Have you (a) taken a verified off-box backup and (b) confirmed you are connected to PROD (not dev)?"

# ---------- 025 -> 045 (additive; 046 needs a manual gate) ----------
$range1 = @(
    '025_AddMultiCompanyAndWaterSchema.sql',
    '026_AddMultiCompanyAndWaterStoredProcedures.sql',
    '027_FixCompanyProcsForDevSchema.sql',
    '028_AddGenericCompanyFoundation.sql',
    '029_AddGenericCompanyStoredProcedures.sql',
    '030_AddGenericProductsServicesInventory.sql',
    '031_AddGenericInventoryStoredProcedures.sql',
    '032_AddGenericCustomersSalesCash.sql',
    '033_AddGenericSalesStoredProcedures.sql',
    '034_AddGenericSuppliersPurchasesExpenses.sql',
    '035_AddGenericPurchasesStoredProcedures.sql',
    '036_AddGenericDailyClosings.sql',
    '037_AddGenericReportsStoredProcedures.sql',
    '038_AddWaterProductionSchema.sql',
    '039_AddWaterProductionStoredProcedures.sql',
    '040_AddWaterDistributionSchema.sql',
    '041_AddWaterDistributionStoredProcedures.sql',
    '042_FixFarmGetTypeSp.sql',
    '043_AddWaterRawMaterialsDailyClosing.sql',
    '044_AddWaterRawMaterialsDailyClosingStoredProcedures.sql',
    '045_GrantExecuteOnWaterPhase3Sps.sql'
)
foreach ($f in $range1) { Invoke-Sqlcmd-File (Join-Path $MigrationsDir $f) }

# ---------- 046 risky: BackfillOrphanFarmIds ----------
Write-Host ""
Write-Host "Before 046, run this in SSMS and read the row count:" -ForegroundColor Yellow
@"
    SELECT COUNT(*) AS orphan_aspnet_users
    FROM   dbo.AspNetUsers u
    WHERE  u.FarmId IS NOT NULL
       AND LTRIM(RTRIM(u.FarmId)) <> ''
       AND NOT EXISTS (SELECT 1 FROM dbo.Farms f WHERE f.FarmId = u.FarmId);

    SELECT COUNT(*) AS orphan_user_farms
    FROM   dbo.UserFarms uf
    WHERE  NOT EXISTS (SELECT 1 FROM dbo.Farms f WHERE f.FarmId = uf.FarmId);
"@ | Write-Host
Confirm-Or-Halt "046 will INSERT one placeholder Farms row per orphan above (Type='Poultry', synthetic email). Proceed?"
Invoke-Sqlcmd-File (Join-Path $MigrationsDir '046_BackfillOrphanFarmIds.sql')

# ---------- 047 -> 052 (additive) ----------
$range2 = @(
    '047_AddWaterFinanceTables.sql',
    '048_AddWaterFinanceStoredProcedures.sql',
    '049_AddWaterCompanyProfile.sql',
    '050_AddWaterStaffAttendancePayroll.sql',
    '051_AddWaterStaffPayrollStoredProcedures.sql',
    '052_AddWaterMaintenanceLogs.sql'
)
foreach ($f in $range2) { Invoke-Sqlcmd-File (Join-Path $MigrationsDir $f) }

# ---------- 053 risky: FixSpCreateFarm + cleanup ----------
Write-Host ""
Write-Host "Before 053, run this in SSMS and read the row count:" -ForegroundColor Yellow
@"
    SELECT COUNT(*) AS misplaced_rows
    FROM   dbo.Farms
    WHERE  FarmId = '0'
       AND Id LIKE '________-____-____-____-____________';
"@ | Write-Host
Confirm-Or-Halt "053 will (a) UPDATE Farms rows where Id has a GUID and FarmId='0' to swap the columns, and (b) DELETE the migration-046 backfill duplicates that match the same FarmId by AspNetUsers.UserName. If the row count above is 0, 053 is effectively just CREATE OR ALTER sp_CreateFarm. Proceed?"
Invoke-Sqlcmd-File (Join-Path $MigrationsDir '053_FixSpCreateFarmAndCleanupBrokenRows.sql')

# ---------- 054 risky: spCompany_* + duplicate-FarmId cleanup ----------
Write-Host ""
Write-Host "Before 054, run this in SSMS and READ THE OUTPUT — these are the rows 054 will delete:" -ForegroundColor Yellow
@"
    WITH RankedFarms AS (
        SELECT f.Id, f.FarmId, f.Name, f.Type, f.CreatedAt,
               ROW_NUMBER() OVER (
                 PARTITION BY f.FarmId
                 ORDER BY CASE WHEN f.Type IN ('Generic','Water') THEN 0 ELSE 1 END,
                          CASE WHEN f.Name IN (SELECT u.UserName FROM dbo.AspNetUsers u WHERE u.FarmId = f.FarmId) THEN 1 ELSE 0 END,
                          f.CreatedAt) AS rnk
        FROM   dbo.Farms f
        WHERE  EXISTS (
           SELECT 1 FROM dbo.Farms f2 WHERE f2.FarmId = f.FarmId GROUP BY f2.FarmId HAVING COUNT(*) > 1
        )
    )
    SELECT * FROM RankedFarms ORDER BY FarmId, rnk;
    -- Rows where rnk > 1 will be DELETED by 054. If any of those rows
    -- look like real farms you want to keep, ABORT.
"@ | Write-Host
Confirm-Or-Halt "054 will DELETE every row above where rnk > 1, then CREATE OR ALTER the spCompany_* family to join on Farms.FarmId. Proceed?"
Invoke-Sqlcmd-File (Join-Path $MigrationsDir '054_FixCompanySpsAndFinishFarmIdRebind.sql')

# ---------- 055 -> 061 (additive / SP-only) ----------
$range3 = @(
    '055_AddGenericStaffPayroll.sql',
    '056_AddGenericStaffPayrollStoredProcedures.sql',
    '057_AddWaterDashboardIntelligenceSps.sql',
    '058_FixWaterDailyClosingLiveAggregation.sql',
    '059_AddWaterProductionBatchReopen.sql',
    '060_AddWaterRawMaterialPurchaseUpdateDelete.sql',
    '061_FixDriverReturnCashFlow.sql'
)
foreach ($f in $range3) { Invoke-Sqlcmd-File (Join-Path $MigrationsDir $f) }

Write-Host ""
Write-Host "All migrations applied without error." -ForegroundColor Green
Write-Host "Run database/schema-sync/99_post_migration_verify.sql next." -ForegroundColor Green
