# PROD Migration-Gap Audit — REFRESH

**Target DB:** `PoultryMaster` (PROD) on `34.39.109.13` — SQL Server
**Date:** 2026-08-17
**Supersedes:** `_PROD_MIGRATION_GAP_AUDIT.md` (2026-07-18)
**Changes applied to prod by this audit:** **NONE.** Read-only — catalog dumps, `OBJECT_ID`/`COL_LENGTH` probes and `sys.sql_modules` body inspection only.

**Method:** same as the July audit (no migration-tracking table exists, so applied/not-applied is inferred by object existence), with one addition: for SP-only migrations the **proc body** was inspected via `sys.sql_modules`, because a proc that already exists tells you nothing about whether a later migration rewrote it. That addition is what caught `198`.

## Mandatory self-check — PASSED
| Object | Migration | Expected | Result |
|---|---|---|---|
| `dbo.PoultryDailyClosings` | 128 | PRESENT | **PRESENT** (`OBJECT_ID` 1741965282) ✅ |
| `dbo.IamRoles` | 199 | MISSING | **MISSING** (`NULL`) ✅ |

---

## Headline: the July gap is closed, a new one opened

**All 8 structural migrations the July audit flagged as MISSING are now present on prod** — verified directly, not inferred:

| July finding | Probe | Result |
|---|---|---|
| `150` `MainFlockBatch.OrderPlacementDate` / `.EstimatedArrivalDate` | `COL_LENGTH` | 3 / 3 ✅ |
| `152` `ProductionRecords.Production4thPick` | `COL_LENGTH` | 4 ✅ |
| `153_FarmProductionSettings` table | `OBJECT_ID` | 2103014573 ✅ |
| `156` `ProductionBatchRecords` / `ProductionBatchAllocations` / `.ProductionBatchId` | `OBJECT_ID`/`COL_LENGTH` | 83531381 / 435532635 / 4 ✅ |
| `161` `PoultryRawMaterialItems.PurchaseUnitOfMeasure` | `COL_LENGTH` | 60 ✅ |
| `164` `ProductionBatchRecords.PostingVersion` | `COL_LENGTH` | 4 ✅ |
| `165` `WaterRawMaterialItems.PurchaseUnitOfMeasure` | `COL_LENGTH` | 60 ✅ |

Phase 1 of the July plan was executed at some point between 2026-07-18 and today. The `162` PARTIAL case is resolved with it.

`166_FixReloadDoubleReversalStockInflation` is also confirmed live on prod — `spWaterVehicleLoading_Reload`'s body carries the reload-reversal fix.

---

## Current state

| Category | Count |
|---|---:|
| Total migration files | **244** (was 199) |
| Structural, applied | 106 |
| **Structural, MISSING** | **2** (`199`, `203`) |
| PARTIAL | 0 |
| SP-only | 126 |
| DATA / OTHER | 10 |

---

## GAP 1 — `198_UnifySaleableEggDefinition` is NOT applied *(customer-visible today)*

Object existence hides this one: all four procs exist on prod, but with **pre-198 bodies**.

| Proc | Body length | Carries `MeatyEggs`/`LostEggs`? |
|---|---:|---|
| `spEggProduction_GetAll` | 787 | **no** |
| `spEggProduction_GetByFlock` | 787 | **no** |
| `spEggProduction_GetById` | 917 | **no** |
| `spPoultryEggStock_SyncForProduction` | 1609 | **no** |
| `spPoultryReport_EggStockBalance` | 1905 | yes *(from 124 — the definition 198 standardises on)* |

So the four-way disagreement `198` was written to fix is **live for customers right now**: the Egg Tracker, poultry egg stock and the Egg Stock Balance report still compute saleable eggs differently, and which one a record gets depends on the entry path that created it.

Note `198` also contains a **guarded one-time realign `UPDATE`** (only touches records where meaty/soft/lost were genuinely recorded and the saleable figure actually moved). It is a data mutation, not just proc bodies — treat it as such.

## GAP 2 — the entire IAM suite (`199`–`203`) is absent from prod

Zero of it is on prod. Confirmed by direct probe:

| File | Missing on prod |
|---|---|
| `199_IamFoundation` | 5 tables (`IamRoles`, `IamPermissions`, `IamRolePermissions`, `IamUserRoles`, `IamUserPermissions`) + 2 procs |
| `200_IamPhase1Reads` | 3 procs (`spIam_GetRoles`, `spIam_GetRolePermissions`, `spIam_GetUserRoles`) |
| `201_IamPhase2Writes` | 10 procs/functions (`spIam_Role_Save`, `spIam_RolePermissions_Set`, `fnIam_OrgOwner`, …) |
| `202_IamPhase3Enforcement` | no objects of its own — enforcement over the above, so inert/meaningless without them |
| `203_IamPhase4Governance` | 5 tables (`IamSessions`, `IamUserSecurity`, `IamAccessAudit`, `IamAccessReviews`, `IamPolicies`) + 14 procs + audit **triggers** |

> `200` and `202` reference `AspNetUsers.IsAdmin` and `AspNetUsers.FeaturePermissions`, which already exist on prod — that is why a pure column check would mislabel them "applied". They are not.

## GAP 3 — `166b` Great Favour correction still pending *(unchanged)*

Confirmed **not applied**: `0` rows on prod with `CreatedBy = 'system:166b'`.
Great Favour (`288bc52b-…`) product 3 (sachet water) ledger stock currently reads **4,264**.

`166` stopped the ongoing inflation, but the historical inflation is still in the ledger. The file still has `@TruePhysicalCount = -1` and self-aborts until someone sets the owner's counted figure. **Still blocked on that physical count — not on us.**

---

## The thing that decides everything else

Prod is SQL Server. **Dev is now PostgreSQL** (`VisibilityCoreDB`), and the backend on the `dev` branch is **Npgsql-only** — it cannot connect to a SQL Server prod at all.

`198`–`203` are written in **T-SQL** (verified: zero PostgreSQL syntax in any of the six). There is no PostgreSQL equivalent of them anywhere in the repo. So:

- Applying `198`–`203` to prod's SQL Server is possible and self-consistent — but the code that *uses* IAM cannot be deployed against it, so `199`–`203` would sit inert until prod also moves to PostgreSQL.
- Whenever prod does move, those six files are an unconverted migration job on top of the ~701 SPs already known to need conversion.

`198` is the exception and the one worth acting on independently: it is a **data-correctness fix to procs prod already runs**, it needs no application change, and it is wrong for customers today.

---

## Recommended order (nothing run yet — awaiting go-ahead)

1. **`198`** — apply to prod. Highest value, lowest risk, fixes live inconsistent egg figures. Review the realign `UPDATE`'s scope first; run in its own transaction.
2. **`166b`** — chase the owner's physical count, then run with `@TruePhysicalCount` set. Single farm, single product.
3. **`199`–`203`** — hold. Decide first whether prod stays on SQL Server or moves to PostgreSQL; applying inert IAM schema to a live customer DB buys nothing until that is settled.
4. `046` / `088` backfills — unchanged from July: review individually, almost certainly already applied, do not blind re-run.

## Appendix — reproducing this audit
```
sqlcmd -S 34.39.109.13 -U sqlserver -P '<pw>' -d PoultryMaster -C -h -1 -W -Q "<probe>"
```
Catalog dumps used: `sys.tables` (203 rows: 190 `dbo`, 13 `poultry2_techretainerDB`), `sys.columns` (2,835), `sys.objects` P/V/FN/IF/TF/TR (840).
Note `sys.objects` name concatenation needs `COLLATE DATABASE_DEFAULT` — prod mixes `Latin1_General_CI_AS_KS_WS` and `SQL_Latin1_General_CP1_CI_AS`.
