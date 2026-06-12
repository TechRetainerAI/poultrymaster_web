# Page CRUD audit — Water + Generic modules
**Date:** 2026-05-26 (the "closing page can't be deleted" session)

This is the back-and-forth pain-point audit James asked for. The closing page is
fixed (commit `b050f5c`). Here's everything else.

## Legend

| Mark | Meaning |
|---|---|
| ✅ | Working — has the UI button + API + backend |
| 🟡 | API + backend exist, **just missing the UI** — quick fix (frontend-only) |
| 🟠 | Frontend wired up, **backend SP/endpoint missing** — needs a migration + service + controller |
| 🔴 | Nothing on either side — full-stack work |
| ➖ | N/A — page is intentionally read-only (dashboard, report, transaction log) |

## Water pages

| Page | Add | Edit | Delete | Notes |
|---|---|---|---|---|
| `water-products` | ✅ | ✅ | ✅ | Reference — does it right |
| `water-customers` | ✅ | ✅ | ✅ | |
| `water-drivers` | ✅ | ✅ | ✅ | |
| `water-vehicles` | ✅ | ✅ | ✅ | |
| `water-routes` | ✅ | ✅ | ✅ | |
| `water-machines` | ✅ | ✅ | ✅ | |
| `water-boreholes` | ✅ | ✅ | ✅ | |
| `water-staff` | ✅ | ✅ | ✅ | |
| `water-payroll` | ✅ | ✅ | ✅ | |
| `water-production-batches` | ✅ | ✅ | ✅ | Approve/cancel/reopen workflow |
| `water-raw-materials` | ✅ | ✅ | ✅ | |
| `water-daily-closing` | ✅ | ✅ (new) | ✅ (new) | **Just fixed.** Draft/Rejected editable+deletable |
| `water-driver-returns` | ✅ | ❌ | 🟡 | `cancelWaterDriverReturn` exists; UI uses approve only. Add cancel/delete on Pending. |
| `water-expenses` | ✅ | ❌ | 🟡 | `deleteWaterExpense` exists in `lib/api/water.ts:388`. UI imports `Trash2` but never calls it. Add the button. |
| `water-sales` | ✅ | ❌ | 🟠 | No `deleteWaterSale` or `updateWaterSale`. Backend has SP for cancel but not delete. Sales SHOULD lock once paid; allow edit + delete only when status='Pending'. |
| `water-payments` | ✅ | ❌ | 🔴 | No `deleteWaterPayment`. Payments locked once recorded is the usual rule, but at minimum allow undo within 5 minutes. |
| `water-cash-accounts` | ✅ | 🟡 | 🟡 | `updateWaterCashAccount` and `deleteWaterCashAccount` exist (lines 404, 407). UI doesn't expose them. |
| `water-maintenance` | ✅ | ❌ | ✅ | Delete works. Edit (e.g. reschedule a future maintenance) is missing. |
| `water-loss-records` | ✅ | ❌ | 🔴 | No update/delete in API. Once you log a damaged carton you can't fix a typo. |
| `water-company-setup` | ✅ | ✅ | ➖ | Single-row profile — no delete needed |
| `water-dashboard` | ➖ | ➖ | ➖ | Read-only |
| `water-stock` | ➖ | ➖ | ➖ | Read-only transaction log |
| `water-reports` | ➖ | ➖ | ➖ | Read-only |
| `water-setup` | (links to others) | (links) | ✅ | Just landed; uses ConfirmDeleteDialog |

## Generic pages

The TypeScript API client (`lib/api/generic.ts`) only has delete/update wired
for **Products**. Every other Generic entity has list + create only on the
client side. The backend SPs may exist (Generic Company migrations 028–037
include lots of `*_Update` and `*_Delete` SPs), but the controller/service
layer doesn't expose them yet for most.

| Page | Add | Edit | Delete | Notes |
|---|---|---|---|---|
| `generic-products` | ✅ | ✅ | ✅ | Reference |
| `generic-customers` | ✅ | ✅ | ✅ | |
| `generic-suppliers` | ✅ | ✅ | ✅ | |
| `generic-staff` | ✅ | ✅ | ✅ | |
| `generic-customer-payments` | ✅ | ❌ | 🔴 | Payments locked is OK; at minimum undo-within-window |
| `generic-supplier-payments` | ✅ | ❌ | 🔴 | Same |
| `generic-sales` | ✅ | ❌ | 🔴 | No update/delete in TS API |
| `generic-purchases` | ✅ | ❌ | 🔴 | Same |
| `generic-expenses` | ✅ | ❌ | 🔴 | Same |
| `generic-cash` | ✅ | ❌ | 🔴 | Cash transactions / adjustments need at minimum reverse-with-reason |
| `generic-cash-transfers` | ✅ | ❌ | 🔴 | Approval workflow exists; cancel/delete UI missing |
| `generic-stock-adjustments` | ✅ | ❌ | 🔴 | An accidental adjustment with no undo is a real audit headache |
| `generic-daily-closings` | ✅ | ❌ | 🔴 | **Same pain pattern as the water closing page.** Apply migration 062's design here too. |
| `generic-payroll` | ✅ | ❌ | 🔴 | Cancel/delete missing |
| `generic-attendance` | ✅ | ❌ | 🔴 | Edit attendance row (correct a typo) missing |
| `generic-setup` | ✅ | ✅ | ➖ | Profile page |
| `generic-dashboard` | ➖ | ➖ | ➖ | Read-only |
| `generic-reports` | ➖ | ➖ | ➖ | Read-only |

## Suggested fix order (highest pain → lowest)

### Tier 1 — UI-only fixes (API exists, just expose it). 30 min each.

1. **`water-expenses`** — wire the existing `Trash2` import to call `deleteWaterExpense` on Pending rows.
2. **`water-cash-accounts`** — add Edit + Delete buttons; APIs exist (`updateWaterCashAccount` line 404, `deleteWaterCashAccount` line 407).
3. **`water-driver-returns`** — add a "Cancel" action on Pending rows that calls `cancelWaterDriverReturn`.

### Tier 2 — Full-stack: copy the daily-closing pattern (migration + SP + service + controller + frontend). ~1 hour each.

4. **`generic-daily-closings`** — same exact pattern as `spWaterDailyClosing_Delete`. Add `spGenericDailyClosing_Delete` + `_UpdateNotes` in a new migration 063, wire C# + TS + UI.
5. **`water-sales`** — add `spWaterSale_Update` and `spWaterSale_Delete` with a status guard (only Pending). Same for the C# + TS layers. Then UI.
6. **`water-loss-records`** — same pattern, but rules are stricter (loss records are audit-bound; consider soft-delete only, with a reason).

### Tier 3 — Generic module CRUD parity. Bulk work.

7. Expose `update*` and `delete*` for every Generic entity in `lib/api/generic.ts`. Backend SPs already exist for most (check migrations 029, 031, 033, 035); add the controller/service layer.
8. Then add per-page edit/delete UI buttons across the generic-* routes.

## Audit log: status

✅ Already covered. `AuditLogActionFilter` is wired as a global MVC filter (`Program.cs:223`) — every `POST`/`PUT`/`DELETE` request to every controller writes a row to `dbo.AuditLogs`. Verified 2026-05-26: 127 rows across 34 distinct resource types in the last 7 days on `PoultryMasterDev`, including `WaterDailyClosing`, `WaterProductionBatch`, `WaterDriverReturn`, `GenericDailyClosing`.

When you add new endpoints (e.g. the DELETEs above), they'll start auto-logging the same way — no extra work needed.

## What the user should do next

Pick a tier. I'd recommend Tier 1 (~90 minutes of work for all three pages, ships small) before tackling the bigger tier-2 patterns.
