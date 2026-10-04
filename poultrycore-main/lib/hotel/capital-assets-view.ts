// Hotel Capital Investments/Assets, in the shape the Poultry-style asset page
// (app/restaurant-assets, itself Poultry's app/poultry-assets) works with.
//
// app/hotel-assets is that page with its data calls pointed here. Every
// function reads or writes the Hotel API (lib/api/hotel-assets, migration 322)
// and converts rows to the Restaurant types, so the page and the shared
// components/capital-assets/* panels don't need a Hotel branch.
//
// Differences from the Restaurant API, handled here:
//   * A Hotel asset starts as Draft ("Not in service") and needs an explicit
//     Activate. The Poultry/Restaurant page puts an asset in service by giving
//     it an in-service date -- so create/update call Activate when a Draft
//     asset has one.
//   * Hotel update replaces every field; the page sends only what changed, so
//     update merges onto the current asset first.
//   * Hotel has no "correct original cost", no "depreciation due" list and no
//     depreciation adjustment. The page hides those actions (HOTEL_ASSETS_CAN).
//   * The summary has no "added this period" or "amount owed"; they are
//     worked out from the asset list (this calendar month).

import {
  listHotelAssets, listHotelAssetCategories, getHotelAsset, getHotelAssetSummary,
  createHotelAsset, updateHotelAsset, activateHotelAsset, addHotelAssetCost, getHotelAssetCosts,
  reverseHotelAssetCost, disposeHotelAsset, reverseHotelAsset, listHotelDepreciation,
  generateHotelDepreciation, reverseHotelDepreciation,
  type HotelCapitalAsset, type HotelCapitalAssetCost, type HotelAssetDepreciation,
} from "@/lib/api/hotel-assets"
import { loadHotelCashAccounts } from "@/lib/hotel/balances"
import type {
  RestaurantCapitalAsset, RestaurantAssetCategory, RestaurantCapitalAssetSummary,
  RestaurantAssetDepreciationDue, RestaurantCapitalAssetCost, RestaurantAssetDepreciation,
  RestaurantCapitalAssetInput, RestaurantCapitalAssetUpdateInput, RestaurantCapitalAssetCostInput,
  RestaurantDepreciationRunResult, RestaurantAssetStatus,
} from "@/lib/api/restaurant-assets"
import type { CashAccount } from "@/lib/api/restaurant-finance"

export { ASSET_PAYMENT_METHODS } from "@/lib/api/restaurant-assets"
export type HotelAssetView = RestaurantCapitalAsset
export type HotelAssetCategoryView = RestaurantAssetCategory
export type HotelAssetSummaryView = RestaurantCapitalAssetSummary
export type HotelAssetDepreciationDueView = RestaurantAssetDepreciationDue
export type HotelCashAccountView = CashAccount

/** Actions the Hotel backend supports beyond the common set. */
export const HOTEL_ASSETS_CAN = { correctOriginalCost: false, depreciationDue: false } as const

const n = (v: unknown) => Number(v ?? 0) || 0
const day = (d?: string | null) => (d ?? "").slice(0, 10)

function toView(a: HotelCapitalAsset, costs = 0, deps = 0): HotelAssetView {
  const total = n(a.totalCapitalizedCost), residual = n(a.residualValue), life = n(a.usefulLifeMonths)
  const depreciable = Math.max(0, total - residual)
  return {
    capitalAssetId: a.hotelCapitalAssetId,
    assetNumber: a.assetNumber ?? `#${a.hotelCapitalAssetId}`,
    assetName: a.assetName,
    assetCategoryId: a.hotelAssetCategoryId ?? null,
    categoryName: a.categoryName ?? null,
    description: null,
    acquisitionDate: a.acquisitionDate ?? a.createdAt,
    inServiceDate: a.inServiceDate ?? null,
    location: a.location ?? null,
    serialNumber: a.serialNumber ?? null,
    supplierId: null,
    supplierName: a.supplier ?? null,
    status: a.status as RestaurantAssetStatus,
    notes: a.notes ?? null,
    acquisitionCost: n(a.acquisitionCost),
    additionalCost: n(a.additionalCost),
    totalCapitalizedCost: total,
    residualValue: residual,
    depreciableAmount: depreciable,
    usefulLifeMonths: life || null,
    monthlyDepreciation: life > 0 ? depreciable / life : null,
    accumulatedDepreciation: n(a.accumulatedDepreciation),
    currentBookValue: n(a.currentBookValue),
    remainingDepreciable: Math.max(0, n(a.currentBookValue) - residual),
    isFullyDepreciated: a.status === "FullyDepreciated",
    costEntries: costs,
    depreciationEntries: deps,
    amountOwed: 0,
    disposalDate: a.disposalDate ?? null,
    disposalProceeds: null,
    disposalNotes: null,
    createdBy: a.createdBy ?? null,
    createdAt: a.createdAt,
    updatedAt: a.updatedAt ?? null,
    reversedBy: a.reversedBy ?? null,
    reversedAt: a.reversedAt ?? null,
    reversalReason: a.reversedReason ?? null,
  }
}

function costView(assetId: number, c: HotelCapitalAssetCost): RestaurantCapitalAssetCost {
  return {
    assetCostId: c.hotelCapitalAssetCostId, capitalAssetId: assetId,
    costDate: c.costDate ?? c.createdAt, description: c.description ?? null, amount: n(c.amount),
    sourceType: c.sourceType, amountPaid: 0, balance: 0, status: c.status, createdAt: c.createdAt,
  }
}

function depView(d: HotelAssetDepreciation): RestaurantAssetDepreciation {
  const start = new Date(`${day(d.periodStart)}T00:00:00`)
  const end = new Date(start.getFullYear(), start.getMonth() + 1, 0)
  const endKey = `${end.getFullYear()}-${String(end.getMonth() + 1).padStart(2, "0")}-${String(end.getDate()).padStart(2, "0")}`
  return {
    assetDepreciationId: d.hotelAssetDepreciationId, capitalAssetId: d.hotelCapitalAssetId,
    assetName: d.assetName ?? null, periodStart: day(d.periodStart), periodEnd: endKey,
    amount: n(d.amount), sourceType: d.sourceType, status: d.status,
    accumulatedAfter: d.accumulatedAfter, bookValueAfter: d.bookValueAfter,
    createdAt: d.createdAt, reversalReason: d.reason ?? null,
  }
}

export async function listHotelAssetViews(): Promise<HotelAssetView[]> {
  return (await listHotelAssets()).map((a) => toView(a))
}

export async function listHotelAssetCategoryViews(): Promise<HotelAssetCategoryView[]> {
  const [cats, assets] = await Promise.all([listHotelAssetCategories(), listHotelAssets().catch(() => [])])
  return cats.map((c) => ({
    assetCategoryId: c.hotelAssetCategoryId, categoryName: c.categoryName,
    defaultUsefulLifeMonths: c.defaultUsefulLifeMonths, sortOrder: c.sortOrder, isActive: c.isActive,
    assetCount: assets.filter((a) => a.hotelAssetCategoryId === c.hotelAssetCategoryId && a.status !== "Reversed").length,
  }))
}

export async function getHotelAssetSummaryView(): Promise<HotelAssetSummaryView> {
  const [s, assets] = await Promise.all([getHotelAssetSummary(), listHotelAssets()])
  const month = new Date().toISOString().slice(0, 7)
  const added = assets.filter((a) => a.status !== "Reversed" && day(a.acquisitionDate ?? a.createdAt).startsWith(month))
  return {
    totalAssets: n(s.totalAssets), activeAssets: n(s.activeAssets), draftAssets: n(s.draftAssets),
    disposedAssets: assets.filter((a) => a.status === "Disposed").length,
    fullyDepreciated: assets.filter((a) => a.status === "FullyDepreciated").length,
    totalAssetCost: n(s.totalAssetCost), accumulatedDepreciation: n(s.accumulatedDepreciation),
    currentBookValue: n(s.currentBookValue),
    addedInPeriod: added.reduce((t, a) => t + n(a.totalCapitalizedCost), 0), addedCount: added.length,
    amountOwed: 0,
  }
}

/** One asset with its cost and depreciation history, for the details panel. */
export async function getHotelAssetView(id: number): Promise<HotelAssetView> {
  const [a, costs, deps] = await Promise.all([getHotelAsset(id), getHotelAssetCosts(id).catch(() => []), listHotelDepreciation(id).catch(() => [])])
  if (!a) throw new Error("Asset not found")
  const postedDeps = deps.filter((d) => d.status !== "Reversed")
  return {
    ...toView(a, costs.length, postedDeps.length),
    costs: costs.map((c) => costView(id, c)),
    depreciation: deps.map(depView),
  }
}

async function activateIfInService(id: number, inServiceDate?: string | null) {
  if (!inServiceDate) return
  const a = await getHotelAsset(id)
  if (a?.status === "Draft") await activateHotelAsset(id)
}

/** Hotel has no default cash account: money paid now must say where it came from. */
function requirePaidFrom(amountPaid: number | null | undefined, amount: number | null | undefined, cashAccountId: number | null | undefined) {
  const paidNow = amountPaid ?? amount ?? 0
  if (paidNow > 0 && !cashAccountId) throw new Error("Choose the cash account this was paid from (Paid from), or set Amount paid now to 0.")
}

export async function createHotelAssetView(input: RestaurantCapitalAssetInput): Promise<{ capitalAssetId: number }> {
  requirePaidFrom(input.amountPaid, input.amount, input.cashAccountId)
  const res = await createHotelAsset({
    farmId: "", // filled in by createHotelAsset from the active company
    assetName: input.assetName, hotelAssetCategoryId: input.assetCategoryId ?? null,
    acquisitionDate: input.acquisitionDate ?? null, inServiceDate: input.inServiceDate ?? null,
    residualValue: n(input.residualValue), usefulLifeMonths: input.usefulLifeMonths ?? undefined,
    amount: input.amount ?? undefined, supplier: input.supplier ?? null,
    location: input.location ?? null, serialNumber: input.serialNumber ?? null,
    notes: [input.description, input.notes].filter(Boolean).join("\n") || null,
    hotelCashAccountId: input.cashAccountId ?? null,
    amountPaid: input.amountPaid ?? null, dueDate: input.dueDate ?? null,
  })
  await activateIfInService(res.hotelCapitalAssetId, input.inServiceDate)
  return { capitalAssetId: res.hotelCapitalAssetId }
}

export async function updateHotelAssetView(id: number, input: RestaurantCapitalAssetUpdateInput): Promise<void> {
  const cur = await getHotelAsset(id)
  if (!cur) throw new Error("Asset not found")
  const pick = <T,>(v: T | undefined, fallback: T) => (v === undefined ? fallback : v)
  await updateHotelAsset(id, {
    farmId: "",
    assetName: pick(input.assetName ?? undefined, cur.assetName),
    hotelAssetCategoryId: pick(input.assetCategoryId, cur.hotelAssetCategoryId ?? null),
    acquisitionDate: cur.acquisitionDate ?? null,
    inServiceDate: pick(input.inServiceDate, cur.inServiceDate ?? null),
    residualValue: n(pick(input.residualValue, cur.residualValue)),
    usefulLifeMonths: n(pick(input.usefulLifeMonths, cur.usefulLifeMonths)),
    supplier: cur.supplier ?? null,
    location: pick(input.location, cur.location ?? null),
    serialNumber: pick(input.serialNumber, cur.serialNumber ?? null),
    notes: pick(input.notes, cur.notes ?? null),
  })
  await activateIfInService(id, pick(input.inServiceDate, cur.inServiceDate ?? null))
}

export async function addHotelAssetCostView(id: number, input: RestaurantCapitalAssetCostInput): Promise<{ assetCostId: number }> {
  requirePaidFrom(input.amountPaid, input.amount, input.cashAccountId)
  const r = await addHotelAssetCost(id, input.amount, input.description ?? undefined, input.costDate ?? undefined, {
    hotelCashAccountId: input.cashAccountId ?? null, amountPaid: input.amountPaid ?? null, dueDate: input.dueDate ?? null,
  })
  return { assetCostId: r.costId }
}

export const reverseHotelAssetCostView = (assetId: number, costId: number, reason: string) =>
  reverseHotelAssetCost(assetId, costId, reason)

export const disposeHotelAssetView = (
  id: number, input: { disposalDate?: string | null; proceeds?: number | null; cashAccountId?: number | null; notes?: string | null },
) => disposeHotelAsset(id, input.disposalDate ?? undefined, input.notes ?? undefined)

export const reverseHotelAssetView = (id: number, reason: string) => reverseHotelAsset(id, reason)

/** Hotel has no "what is due" query; the page hides that list (HOTEL_ASSETS_CAN.depreciationDue). */
export async function listHotelDepreciationDueView(): Promise<HotelAssetDepreciationDueView[]> { return [] }

export async function generateHotelDepreciationView(input?: { throughDate?: string | null; assetId?: number | null }): Promise<RestaurantDepreciationRunResult> {
  const r = await generateHotelDepreciation(input?.throughDate ?? undefined, input?.assetId ?? null)
  return { assetsProcessed: n(r.assetsProcessed), entriesCreated: n(r.entriesCreated), totalAmount: n(r.totalAmount) }
}

export const reverseHotelDepreciationView = (entryId: number, reason: string) => reverseHotelDepreciation(entryId, reason)

export async function correctHotelAssetOriginalCostView(
  _id: number, _input: { newAmount: number; effectiveDate?: string | null; reason: string },
): Promise<{ assetCostId: number }> {
  throw new Error("Correcting the original cost isn't available for Hotel assets yet.")
}

/** Hotel cash accounts in the Restaurant CashAccount shape the page's pickers use. */
export async function listHotelCashAccountViews(): Promise<HotelCashAccountView[]> {
  const list = await loadHotelCashAccounts()
  return list.map((a) => ({
    cashAccountId: a.id, name: a.name, accountType: "Cash", openingBalance: 0,
    currentBalance: n(a.currentBalance), ledgerBalance: n(a.currentBalance),
    allowNegative: !!a.allowNegativeBalance, isActive: true, createdAt: "",
  }))
}
