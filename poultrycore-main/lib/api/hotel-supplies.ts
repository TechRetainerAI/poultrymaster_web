// =============================================================================
// Hotel supply purchases, Internal Use and Deferred inventory cost (migration 334).
//
// The same shapes as the Restaurant's (lib/api/restaurant-suppliers.ts,
// lib/api/restaurant-internal-use.ts), so the pages follow one model. A supply
// is a hotelinventoryitems row: toiletries and amenities, linen and towels,
// cleaning products, housekeeping and maintenance stock, kitchen stock, office
// supplies. Refusals come back as 400 with a plain sentence.
// =============================================================================

import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "./config"
import type { InternalUseStatus } from "./internal-use"

function farmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

function url(path: string, query: Record<string, string | number | null | undefined> = {}): string {
  const q = new URLSearchParams({ farmId: farmId() })
  for (const [k, v] of Object.entries(query)) if (v !== null && v !== undefined && v !== "") q.set(k, String(v))
  return farmApiUrl(`/Hotel${path}?${q}`)
}

async function call<T>(method: string, u: string, body?: unknown): Promise<T> {
  const res = await fetch(u, { method, headers: getAuthHeaders(), body: body ? JSON.stringify(body) : undefined })
  if (!res.ok) throw new Error(await readApiError(res))
  const text = await res.text()
  return text ? JSON.parse(text) : ({} as T)
}

// ----- Purchases & cost recognition ------------------------------------------

export type CostMode = "EXPENSE_WHEN_PURCHASED" | "EXPENSE_WHEN_CONSUMED"

export const COST_MODE_LABELS: Record<CostMode, string> = {
  EXPENSE_WHEN_PURCHASED: "Expense when purchased",
  EXPENSE_WHEN_CONSUMED: "Expense when consumed",
}

export interface HotelSupplyPurchase {
  purchaseId: number
  purchaseDate: string
  itemId: number
  itemName: string
  category?: string | null
  unit?: string | null
  supplierId?: number | null
  supplierName?: string | null
  quantity: number
  unitCost: number
  totalCost: number
  paymentMethod?: string | null
  amountPaid: number
  allocated: number
  balance: number
  paymentStatus: string
  dueDate?: string | null
  cashAccountId?: number | null
  cashAccountName?: string | null
  costMode: CostMode
  remainingQuantity: number
  deferredTotalCost: number
  deferredRemainingCost: number
  notes?: string | null
  status: "Posted" | "Reversed" | string
  createdBy?: string | null
  createdAt: string
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface HotelSupplyPurchaseInput {
  itemId: number
  quantity: number
  totalCost: number
  purchaseDate?: string | null
  supplierId?: number | null
  paymentMethod?: string | null
  amountPaid?: number | null
  cashAccountId?: number | null
  dueDate?: string | null
  notes?: string | null
}

export const listSupplyPurchases = (q: { from?: string; to?: string; supplierId?: number; itemId?: number; purchaseId?: number } = {}) =>
  call<HotelSupplyPurchase[]>("GET", url("/supplies/purchases", q))
export const createSupplyPurchase = (input: HotelSupplyPurchaseInput) =>
  call<{ purchaseId: number }>("POST", url("/supplies/purchases"), { ...input, farmId: farmId() })
export const reverseSupplyPurchase = (id: number, reason: string) =>
  call<void>("POST", url(`/supplies/purchases/${id}/reverse`), { farmId: farmId(), reason })

export interface HotelSupplyCostModeRow {
  category: string
  costMode: CostMode
  itemCount: number
  isConfigured: boolean
  updatedBy?: string | null
  updatedAt?: string | null
}

export const listSupplyCostModes = () => call<HotelSupplyCostModeRow[]>("GET", url("/supplies/cost-recognition"))
export const setSupplyCostMode = (category: string, costMode: CostMode) =>
  call<void>("PUT", url("/supplies/cost-recognition"), { farmId: farmId(), category, costMode })

// ----- Deferred inventory cost -------------------------------------------------

export type DeferredScope = "DEFERRED" | "RECOGNIZED" | "EXCEPTION" | "ALL"

export interface HotelDeferredSummary {
  remainingDeferredCost: number
  recognizedCost: number
  deferredBasis: number
  operationalCost: number
  purchaseCount: number
  deferredPurchases: number
  fullyRecognized: number
  notRecognized: number
  exceptions: number
  exceptionDrift: number
  recognitionPercent: number
  blockedPurchases: number
  blockedCost: number
}

export interface HotelDeferredPurchase {
  purchaseId: number
  purchaseDate: string
  itemId: number
  itemName: string
  category?: string | null
  unit?: string | null
  supplierId?: number | null
  supplierName?: string | null
  purchasedQuantity: number
  consumedQuantity: number
  remainingQuantity: number
  operationalCost: number
  deferredTotalCost: number
  recognizedCost: number
  deferredRemainingCost: number
  recognitionPercent: number
  allocatedRecognizedCost: number
  recognitionDrift: number
  costRecognitionMethod: CostMode
  recognitionMethodLabel: string
  status: string
  exceptionReason?: string | null
  recognitionEvents: number
  lastRecognitionDate?: string | null
  costingMethod: string
  queuePosition?: number | null
  quantityAheadInQueue: number
}

export interface HotelDeferredHistoryRow {
  drawId: number
  usedDate: string
  sourceType: string
  sourceLabel: string
  quantityDrawn: number
  unit?: string | null
  unitCostAtDraw: number
  operationalCost: number
  recognizedCost: number
  recognitionOutcome: string
  isReversed: boolean
}

export function getDeferredCosts(q: {
  scope?: DeferredScope; itemId?: number | null; category?: string | null
  fromDate?: string | null; toDate?: string | null; search?: string | null
}): Promise<{ summary: HotelDeferredSummary; purchases: HotelDeferredPurchase[] }> {
  return call("GET", url("/deferred-inventory-costs", {
    scope: q.scope, itemId: q.itemId, category: q.category, fromDate: q.fromDate, toDate: q.toDate, search: q.search,
  }))
}

export function getDeferredCostHistory(purchaseId: number): Promise<HotelDeferredHistoryRow[]> {
  return call("GET", url(`/deferred-inventory-costs/${purchaseId}/history`))
}

// ----- Internal Use -----------------------------------------------------------

/** Poultry's reason keys adapted to a hotel; the key is what is stored. */
export type HotelInternalUseCategory =
  | "RoomAmenities" | "Housekeeping" | "StaffWelfare" | "Complimentary" | "Donation" | "Damaged" | "Other"

export const HOTEL_INTERNAL_USE_CATEGORIES: HotelInternalUseCategory[] = [
  "RoomAmenities", "Housekeeping", "StaffWelfare", "Complimentary", "Donation", "Damaged", "Other",
]

export const HOTEL_INTERNAL_USE_CATEGORY_LABELS: Partial<Record<HotelInternalUseCategory, string>> = {
  RoomAmenities: "Rooms restocked (amenities)",
  Housekeeping: "Housekeeping consumption",
  StaffWelfare: "Staff use",
  Complimentary: "Complimentary / guest gift",
  Donation: "Donation",
  Damaged: "Damaged / written off",
  Other: "Other",
}

/** Where the staff-count helper is offered up front (Poultry: Staff allowance). */
export const HOTEL_STAFF_BASED_CATEGORIES: HotelInternalUseCategory[] = ["StaffWelfare"]

/** "Supply" is every hotel line; "MenuItem" exists only so the shared page shape compiles. */
export type HotelInternalUseItemType = "Supply" | "MenuItem"

export interface HotelInternalUseItem {
  internalUsageItemId?: number
  itemType: HotelInternalUseItemType
  itemId?: number | null
  /** The page's field name for the stock item (Restaurant shape); the same as itemId. */
  ingredientId?: number | null
  menuItemId?: number | null
  itemName?: string | null
  entryQuantity: number
  entryUnit?: string | null
  quantityPerStaff?: number | null
  entryUnitCost: number
  totalCost?: number
  itemNotes?: string | null
}

export interface HotelInternalUsage {
  internalUsageId: number
  farmId: string
  usageDate: string
  referenceNo?: string | null
  category: HotelInternalUseCategory
  reason?: string | null
  recipientName?: string | null
  staffCount?: number | null
  status: InternalUseStatus
  totalCostValue: number
  /** What the current posting charged to Profit & Loss (stock expensed when consumed only). */
  plCost: number
  notes?: string | null
  postedBy?: string | null
  postedAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
  createdBy?: string | null
  createdAt: string
  updatedAt?: string | null
  items: HotelInternalUseItem[]
}

export interface HotelInternalUseOption {
  itemType: HotelInternalUseItemType
  itemId: number
  name: string
  category?: string | null
  unit?: string | null
  onHand: number
  suggestedUnitCost: number
  costMode?: string | null
}

export interface HotelInternalUsageInput {
  usageDate: string
  category: HotelInternalUseCategory
  reason?: string | null
  recipientName?: string | null
  staffCount?: number | null
  notes?: string | null
  items: HotelInternalUseItem[]
}

// The page speaks in ingredientId (the shape it was built on); the API in itemId.
const withIngredientIds = (r: HotelInternalUsage): HotelInternalUsage => ({
  ...r, items: (r.items ?? []).map((i) => ({ ...i, ingredientId: i.itemId ?? i.ingredientId ?? null })),
})
const toApi = (input: HotelInternalUsageInput) => ({
  ...input, farmId: farmId(),
  items: input.items.map((i) => ({ ...i, itemId: i.itemId ?? i.ingredientId ?? null })),
})

export const listHotelInternalUsage = async () =>
  (await call<HotelInternalUsage[]>("GET", url("/internal-usage"))).map(withIngredientIds)
export const listHotelInternalUseItems = () => call<HotelInternalUseOption[]>("GET", url("/internal-usage/items"))
export const createHotelInternalUsage = async (input: HotelInternalUsageInput) =>
  withIngredientIds(await call<HotelInternalUsage>("POST", url("/internal-usage"), toApi(input)))
export const updateHotelInternalUsage = async (id: number, input: HotelInternalUsageInput) =>
  withIngredientIds(await call<HotelInternalUsage>("PUT", url(`/internal-usage/${id}`), toApi(input)))
export const deleteHotelInternalUsage = (id: number) => call<void>("DELETE", url(`/internal-usage/${id}`))
export const postHotelInternalUsage = (id: number) => call<HotelInternalUsage>("POST", url(`/internal-usage/${id}/post`))
export const reverseHotelInternalUsage = (id: number, reason: string) =>
  call<HotelInternalUsage>("POST", url(`/internal-usage/${id}/reverse`), { farmId: farmId(), reason })
