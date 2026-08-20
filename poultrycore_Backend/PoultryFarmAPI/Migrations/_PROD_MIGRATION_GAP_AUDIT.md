# PROD Migration-Gap Audit

**Target DB:** `PoultryMaster` (PROD) on `34.39.109.13`
**Reference DB:** `PoultryMasterDev` (DEV — has everything)
**Date:** 2026-07-18
**Method:** No migration-tracking table exists. Applied/not-applied was **inferred by object existence** — the full prod catalog (`sys.tables`, `sys.columns`, `sys.objects`) was dumped and every migration's structural signature (created tables + added columns) was checked against it. All 8 "MISSING" findings were then **re-verified directly** against prod with `OBJECT_ID` / `COL_LENGTH`.

## Mandatory self-check — PASSED
| Object | Migration | Expected | Method result |
|---|---|---|---|
| `dbo.ProductionBatchRecords` (table) | 156 | MISSING | **MISSING** ✅ |
| `dbo.PoultryDailyClosings` (table) | 128 | PRESENT | **PRESENT** ✅ |

The method correctly reports both known cases, so the bulk results below are trusted.

---

## Summary counts
| Category | Count |
|---|---:|
| Total migration files | **199** |
| APPLIED (structural objects all present) | 83 |
| **MISSING (structural — must apply)** | **8** |
| PARTIAL (some objects present, some absent — dangerous) | 1 |
| SP-ONLY (only procs/views/functions — idempotent, safe re-apply) | 99 |
| DATA / OTHER (backfills, grants, renames, index drops — no structural DDL) | 8 |

> **Note on numbering:** the dev branch has a **forked/duplicated numbering** from ~106 onward — two parallel series (Water/Generic vs Poultry) were merged, so numbers 106, 107, 108, 109, 110, 111, 112, 113, 120–166 each appear on **two different files**. Always identify files by **full filename**, never by number alone. Prod has been applied **out of lockstep** — e.g. `153_RawMaterialUsageMethodBatchCosting`, `154`, `155` tables are present while `150`, `152`, `153_FarmProductionSettings`, `156` are absent — so per-object checking (done here) is the only reliable method.

---

## MISSING structural migrations — THE MUST-APPLY LIST (ordered)

All 8 were re-verified directly against prod. **All 8 contain `IF NOT EXISTS` / `COL_LENGTH` guards, so they are idempotent and safe to (re-)apply.**

| # | File | Adds | Confirmed absent in prod |
|---|---|---|---|
| 1 | `150_FlockBatchOrderAndArrivalDates.sql` | cols `MainFlockBatch.OrderPlacementDate`, `MainFlockBatch.EstimatedArrivalDate` | both `COL_LENGTH = NULL` ✅ |
| 2 | `152_ProductionRecordFourthPick.sql` | col `ProductionRecords.Production4thPick` | `COL_LENGTH = NULL` ✅ |
| 3 | `153_FarmProductionSettings.sql` | **table** `dbo.FarmProductionSettings` | `OBJECT_ID = NULL` ✅ |
| 4 | `156_BatchProductionRecords.sql` | **7 tables**: `ProductionBatchRecords`, `ProductionBatchIncludedFlocks`, `ProductionBatchFeedUsage`, `ProductionBatchMedicationUsage`, `ProductionBatchAllocations`, `ProductionBatchAllocationFeedUsage`, `ProductionBatchAllocationMedicationUsage`; **+ 3 cols** on `ProductionRecords`: `ProductionBatchId`, `ProductionBatchAllocationId`, `SourceType` | all absent ✅ |
| 5 | `161_PoultryRawMaterialItemPurchaseUnit.sql` | col `PoultryRawMaterialItems.PurchaseUnitOfMeasure` (+ one-time backfill `UPDATE`, self-guarded) | `COL_LENGTH = NULL` ✅ |
| 6 | `163_ReconcileProductionRecordFourthPick.sql` | col `ProductionRecords.Production4thPick` (same col as 152; guarded reconcile) | `COL_LENGTH = NULL` ✅ |
| 7 | `164_BatchAllocationIntegrity.sql` | cols `ProductionBatchRecords.PostingVersion`, `.FeedType`, `.Medication` (**depends on 156**) | table+cols absent ✅ |
| 8 | `165_WaterRawMaterialItemPurchaseUnit.sql` | col `WaterRawMaterialItems.PurchaseUnitOfMeasure` (+ one-time backfill `UPDATE`, self-guarded) | `COL_LENGTH = NULL` ✅ |

---

## PARTIAL migration — CALL-OUT (dangerous by nature, but safe here)

| File | Present in prod | Missing in prod |
|---|---|---|
| `162_ReconcileFlockBatchSPs.sql` | col `MainFlockBatch.DollarConversionRate` (added earlier by applied `160_FlockBatchDollarConversionRate`) | cols `MainFlockBatch.OrderPlacementDate`, `MainFlockBatch.EstimatedArrivalDate` (same two that `150` adds) |

`162` is a **reconcile** migration: it re-adds those three columns behind `IF NOT EXISTS`/`COL_LENGTH` guards and then rebuilds flock-batch SPs. It is **idempotent and safe**. It is the only file where prod has a proper subset of the objects. Applying `150` (or `162`) fills the gap; running both in order is harmless.

---

## SP-ONLY migrations (99) — idempotent, safe to re-apply in order

Every one of these defines **only** `CREATE OR ALTER PROCEDURE/VIEW/FUNCTION` (no tables, no columns), so re-running them cannot damage data — they just refresh proc bodies to the dev version. They are the bulk of the file set. Because prod's proc bodies may be older than dev, **re-running the SP-only files that touch the newly-added objects is recommended** after the structural migrations (see plan). Full list (by filename): 004, 006, 010, 026, 027, 029, 031, 033, 035, 037, 039, 041, 042, 044, 048, 051, 053, 054, 056, 057, 058, 059, 060, 061, 062, 065, 066, 069, 071, 072, 073, 079, 081, 085, 086, 087, 089, 090, 091, 094, 095, 097, 099, 100, 101, 102, 103, 105, `106_DeliveryExpenseLoadingIdForSourceLink`, `106_RawMaterialPurchaseSelectableCashAccount`, `107_ClosingApprovedOnlyDedupAndProdCost`, `107_DeliveryExpenseLedgerExcludeCancelled`, `108_ClosingCashIsIncomeMinusExpenses`, `109_AddGenericCashMovementPost`, `109_ClosingCashAddCollectionsNotIncome`, `110_DriverReturnPostCashToAccounts`, `111_WaterSaleDeleteAndSource`, `112_WaterCashAccountAdjust`, `113_AddGenericCashAccountDetailsAndLedgerReport`, `113_WaterCashAccountDeleteOrDeactivate`, 114, 115, 117, `120_AddPoultryAdvancedReports_Part1`, `120_ReloadSyncsLoadingHeader`, `121_AddPoultryAdvancedReports_Part2`, `122_AddPoultryProfitLossCompany`, `122_ReloadSyncsDraftReturnLoaded`, `123_ProfitLossByFlockRevenueSplit`, `124_EggStockBalanceSubtractSales`, `127_AddPoultryStaffAttendanceStoredProcedures`, 129 (`AddPoultryCashStoredProcedures`), `131_AddPoultryPayrollStoredProcedures`, `132_PoultryClosingReport`, `135_PoultryClosingReportBirds`, `136_ProductionRecordEggStockSync`, `138_ProductionRecordGetIncludesCosting`, `139_AddPoultryDriverDistributionStoredProcedures`, `139_EggSaleReducesStock`, 140, 141, 142, 143, 144, 146, 147, 148, 149, `150_PoultryFinishedStockReconcileBirdsEggs`, `151_FlockBatchPayBalance`, `151_PoultryClosingTotalsFromProductionLog`, `152_PoultryClosingMedicationBalancesStock`, `154_DailyEggReportFourthPick`, `155_EggProductionFourthPick`, `156_BatchConsumeInProductionUnits`, 157, 158, 159, `166_FixReloadDoubleReversalStockInflation`.

*(SP-only migrations were NOT individually diffed against prod's proc bodies. They are structurally safe regardless; the recommendation is to re-run the ones tied to the missing objects.)*

---

## One-time DATA migrations — FLAG FOR MANUAL REVIEW

These 8 files contain no structural DDL. **3 are genuine one-time data mutations** whose "applied" state cannot be inferred from schema — review before running, and do NOT blind re-run:

| File | Risky statements | Notes |
|---|---|---|
| `046_BackfillOrphanFarmIds.sql` | `INSERT INTO dbo.Farms (...)` (bulk), plus UPDATEs | Backfills `Farms` rows for orphan FarmIds referenced by AspNetUsers/UserFarms. Self-selects orphans, but re-running could re-insert. Almost certainly already applied on prod (its target objects are old). **Review, likely skip.** |
| `088_BackfillEmployeeUserFarmsLink.sql` | `INSERT INTO dbo.UserFarms (...)` | Heals staff employees missing a UserFarms row. Companion to code fix. **Review; re-run is low-risk (it re-selects unlinked employees) but confirm not already applied.** |
| `166b_DataCorrection_GreatFavour_Stock.sql` | `INSERT INTO dbo.WaterStockTransactions` | **Single-farm, one-time** correction (Great Favour, FarmId `288bc52b-…`) setting stock to owner's physical count. Companion to `166`. **Must be reviewed/applied manually per that farm — do NOT run generically.** |

The other 5 DATA/OTHER files are structurally harmless / idempotent and need no special handling:
- `008_RenameLegacyAuditlogsToAuditLogs.sql` — sp_rename guarded by existence.
- `009_GrantAuditLogsPermissions.sql`, `045_GrantExecuteOnWaterPhase3Sps.sql`, `096_GrantClosingReopenLinkSupersededExecute.sql` — GRANT statements (idempotent).
- `074_DropLegacyWaterDailyClosingFarmDateIndex.sql` — DROP INDEX guarded by existence.

> Also note: several **APPLIED** structural migrations embed guarded one-time backfills (`002`, `025`, `028`, `084`, `110_AddGenericCashNegativeBalancePolicy`, `145_PoultryPayments`, `153_RawMaterialUsageMethodBatchCosting`). Because their structural objects are already present in prod, **these were already applied — do not re-run them.**

---

## Recommended ordered apply plan

Apply against `PoultryMaster`, each file in its own transaction, in this order. All structural files are guarded (idempotent), so this is safe even if a given object partially exists.

**Phase 1 — structural (required, in this order):**
1. `150_FlockBatchOrderAndArrivalDates.sql`
2. `152_ProductionRecordFourthPick.sql`
3. `153_FarmProductionSettings.sql`  ⟵ the `FarmProductionSettings` one, **not** `153_RawMaterialUsageMethodBatchCosting` (already applied)
4. `156_BatchProductionRecords.sql`  (creates the 7 batch tables + 3 ProductionRecords cols)
5. `161_PoultryRawMaterialItemPurchaseUnit.sql`
6. `163_ReconcileProductionRecordFourthPick.sql`
7. `164_BatchAllocationIntegrity.sql`  (must come **after** 156)
8. `165_WaterRawMaterialItemPurchaseUnit.sql`
9. `162_ReconcileFlockBatchSPs.sql`  (fills the PARTIAL gap + rebuilds flock SPs; safe/guarded)

**Phase 2 — refresh dependent stored procs (recommended; all idempotent `CREATE OR ALTER`):**
Re-run the SP-only files that read the newly-added objects so prod's proc bodies match dev. At minimum the batch/fourth-pick/settings/raw-material family:
`156_BatchConsumeInProductionUnits`, `157_RawMaterialStockProductionUnitsWithBatches`, `158_ProductionSyncReversalAggregateFix`, `159_BatchConsumeUsageInPurchaseUnits`, `154_DailyEggReportFourthPick`, `155_EggProductionFourthPick`, `148_PoultryDailyClosingEnrichedTotals`, `149_FixPoultryClosingLiveTotalsIntCast`, `152_PoultryClosingMedicationBalancesStock`, `166_FixReloadDoubleReversalStockInflation`.
*(Safest exhaustive alternative: re-run every SP-only file in filename order — they cannot harm data.)*

**Phase 3 — manual data review (do NOT auto-run):**
Review `046`, `088`, `166b` individually against prod state as described above. `166b` is farm-specific and needs the owner's physical count confirmation.

---

## Appendix — how to run one file safely
```
sqlcmd -S 34.39.109.13 -d PoultryMaster -U sqlserver -P 'Techretainer@77' -C \
  -i "C:\...\Migrations\156_BatchProductionRecords.sql"
```
(Windows path required — sqlcmd cannot read Git-Bash `/tmp` or `/c/...` paths.)
