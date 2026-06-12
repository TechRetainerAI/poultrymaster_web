# Prod Schema Sync Runbook — 2026-05-23

**Goal:** Bring prod's schema up to dev's, **excluding water + multi-company**, to fix the "no flocks available" bug on the expenses page.

**Server:** `34.39.109.13`
**Connect as:** a login with `db_owner` or `db_ddladmin` on the prod DB (the app login won't have permission to alter procs).

> Migrations are idempotent — each one checks before creating/altering. Already-applied ones become no-ops.

---

## Pre-flight (do not skip)

- [ ] You're connecting to **prod**, not dev. Run `SELECT @@SERVERNAME, DB_NAME();` and read it twice.
- [ ] No long-running write traffic right now (or you've put the app in a maintenance window).
- [ ] You know how to restore from the backup you're about to take.

---

## Step 1 — Identify the prod DB name

Run `00_discover_databases.sql` against `master` on `34.39.109.13`.
Note the prod database name. From the codebase the typical name is `PoultryMaster`; dev is `PoultryMasterDev`. Confirm before continuing.

> Substitute `<PROD_DB_NAME>` everywhere below with the real name.

---

## Step 2 — Full backup of prod

Open `01_backup_prod.sql`, replace `<PROD_DB_NAME>`, execute against `master`.

After it finishes:
- Confirm SSMS prints `Backup verified OK: <path>`
- Copy the `.bak` off the SQL server box (GCS, scp, anything) so a server-disk failure doesn't also lose the backup.

**Do not proceed without this.**

---

## Step 3 — Run migrations 001 → 024 in order

Location of files: `poultrycore\PoultryFarmAPI\Migrations\`

Connect SSMS to `<PROD_DB_NAME>` (not master). Open and execute each file **in numeric order**:

- [ ] `001_UnifyProductionTables.sql`
- [ ] `002_SyncFeedUsageWithProductionRecord.sql`
- [ ] `003_AddEggGradeToProductionRecords.sql`
- [ ] `004_FixProductionRecordGetAfterEggGrade.sql`
- [ ] `005_AddPaidToSales.sql`
- [ ] `006_FixHealthRecordSharedByFarm.sql`
- [ ] `007_AddAuditLogsFarmId.sql`
- [ ] `008_RenameLegacyAuditlogsToAuditLogs.sql`
- [ ] `009_GrantAuditLogsPermissions.sql`
- [ ] `010_EggGradeOnEggProductionProcedures.sql`
- [ ] `011_CreateInventoryItemModule.sql`
- [ ] `012_EggInventoryAdjustment.sql`
- [ ] `013_SupplierAndInventorySupplierId.sql`
- [ ] `014_FeedInventoryAdjustment.sql`
- [ ] `015_HealthRecordAttachmentImage.sql`
- [ ] `016_ExpenseAttachmentImage.sql`
- [ ] `017_AuditLogsData.sql`
- [ ] `018_WeeklyReportExtensions.sql`
- [ ] `019_AddInventoryFieldsForUI.sql`
- [ ] `020_FixInventoryTablePointers.sql`
- [ ] `021_MainFlockBatchPurchaseFields.sql`
- [ ] **`022_AddFlockHasArrived.sql`  ← this is the one that fixes your bug**
- [ ] `023_MainFlockBatchAmountPaid.sql`
- [ ] `024_MainFlockBatchNotes.sql`

If any script throws an error, **stop**, read the message, and ping me before continuing. Don't skip ahead.

---

## Step 4 — DO NOT RUN on prod

Per the decision to keep water/multi-company on dev only:

- [ ] ~~025_AddMultiCompanyAndWaterSchema.sql~~  ← SKIPPED
- [ ] ~~026_AddMultiCompanyAndWaterStoredProcedures.sql~~  ← SKIPPED
- [ ] ~~027_FixCompanyProcsForDevSchema.sql~~  ← SKIPPED

These create the `UserFarms`, `WaterProducts`, `WaterCustomers`, `WaterStockTransactions`, `WaterSales`, `WaterSaleItems`, `WaterPayments` tables plus Companies/UserFarm/Water procs and the `Farms.Type/OwnerUserId/UpdatedAt` columns. None of them are required for the poultry side to work.

---

## Step 5 — Verify

Run `99_post_migration_verify.sql` against `<PROD_DB_NAME>`. All checks should report **OK**.

---

## Step 6 — Redeploy the API

The Cloud Run API binary already expects the new sp shapes (it was built from the same repo as dev). If it's already deployed, no redeploy needed — the new sp's just start working. If you've held the API back at an older build, deploy the current build now.

---

## Step 7 — Smoke test in the browser

1. Hard refresh `https://poultrymaster.com/expenses/new`
2. The "Select Flock" dropdown should now list your active flocks
3. Create a test expense and confirm it saves
4. Delete the test expense if you don't want it in the books

If the dropdown is still empty after this, open DevTools → Console, look at the `[v0] Fetching flocks` log lines, and send me what you see.

---

## Rollback (only if something goes badly wrong)

The backup from Step 2 is your rollback. To restore:

```sql
USE master;
ALTER DATABASE [<PROD_DB_NAME>] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
RESTORE DATABASE [<PROD_DB_NAME>]
    FROM DISK = N'C:\SQLBackups\<PROD_DB_NAME>_preSchemaSync_<timestamp>.bak'
    WITH REPLACE, RECOVERY;
ALTER DATABASE [<PROD_DB_NAME>] SET MULTI_USER;
```

Note: restore = lose any rows written to prod *between* the backup and the restore. Take a fresh backup before restoring if customer data has been written in the interim.
