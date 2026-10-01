import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "./config"
import type { InternalUseCategory, InternalUseStatus } from "./internal-use"

// =============================================================================
// Restaurant Internal Use — API module (migration 330)
//
// Poultry's Internal Use (lib/api/internal-use.ts) for the standalone
// Restaurant: stock the restaurant uses itself, recorded at cost, never as a
// sale. A line is a stock item, or a menu item (its recipe comes out of stock).
// Posting draws stock through the FIFO lots; the cost reaches Profit & Loss only
// for stock expensed when consumed (stock expensed when purchased was charged
// when it was bought). Refusals come back as 400 with a plain sentence.
// =============================================================================

/** Poultry's reason keys, restaurant wording. The key is what is stored. */
export const RESTAURANT_INTERNAL_USE_CATEGORIES: InternalUseCategory[] = [
  "StaffWelfare", "OwnerUse", "Sample", "Donation", "QualityTest", "InternalConsumption", "Other",
]

export const RESTAURANT_INTERNAL_USE_CATEGORY_LABELS: Partial<Record<InternalUseCategory, string>> = {
  StaffWelfare: "Staff meal",
  OwnerUse: "Owner use",
  Sample: "Complimentary / sample",
  Donation: "Donation",
  QualityTest: "Quality testing",
  InternalConsumption: "Kitchen use",
  Other: "Other",
}

/** Where the staff-count helper is offered up front (Poultry: Staff allowance). */
export const RESTAURANT_STAFF_BASED_CATEGORIES: InternalUseCategory[] = ["StaffWelfare"]

export type RestaurantInternalUseItemType = "Ingredient" | "MenuItem"

export interface RestaurantInternalUseItem {
  internalUsageItemId?: number
  itemType: RestaurantInternalUseItemType
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

export interface RestaurantInternalUsage {
  internalUsageId: number
  farmId: string
  usageDate: string
  referenceNo?: string | null
  category: InternalUseCategory
  reason?: string | null
  recipientName?: string | null
  staffCount?: number | null
  status: InternalUseStatus
  totalCostValue: number
  /** What the current posting charged to Profit & Loss (deferred stock only). */
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
  items: RestaurantInternalUseItem[]
}

export interface RestaurantInternalUseOption {
  itemType: RestaurantInternalUseItemType
  itemId: number
  name: string
  category?: string | null
  unit?: string | null
  /** Stock on hand; for a menu item, whole portions its recipe can still make. */
  onHand: number
  suggestedUnitCost: number
  costMode?: string | null
}

export interface RestaurantInternalUsageInput {
  usageDate: string
  category: InternalUseCategory
  reason?: string | null
  recipientName?: string | null
  staffCount?: number | null
  notes?: string | null
  items: RestaurantInternalUseItem[]
}

function farmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

const base = (path = "", query: Record<string, string> = {}) =>
  farmApiUrl(`/Restaurant/internal-usage${path}?${new URLSearchParams({ farmId: farmId(), ...query }).toString()}`)

async function call<T>(method: string, url: string, body?: unknown): Promise<T> {
  const res = await fetch(url, { method, headers: getAuthHeaders(), body: body ? JSON.stringify(body) : undefined })
  if (!res.ok) throw new Error(await readApiError(res))
  const text = await res.text()
  return text ? JSON.parse(text) : ({} as T)
}

export const listRestaurantInternalUsage = () => call<RestaurantInternalUsage[]>("GET", base())
export const listRestaurantInternalUseItems = () => call<RestaurantInternalUseOption[]>("GET", base("/items"))
export const createRestaurantInternalUsage = (input: RestaurantInternalUsageInput) =>
  call<RestaurantInternalUsage>("POST", base(), { ...input, farmId: farmId() })
export const updateRestaurantInternalUsage = (id: number, input: RestaurantInternalUsageInput) =>
  call<RestaurantInternalUsage>("PUT", base(`/${id}`), { ...input, farmId: farmId() })
export const deleteRestaurantInternalUsage = (id: number) => call<void>("DELETE", base(`/${id}`))
export const postRestaurantInternalUsage = (id: number) => call<RestaurantInternalUsage>("POST", base(`/${id}/post`))
export const reverseRestaurantInternalUsage = (id: number, reason: string) =>
  call<RestaurantInternalUsage>("POST", base(`/${id}/reverse`), { farmId: farmId(), reason })
