// Internal Use — stock the company intentionally consumes rather than sells
// (staff welfare, owner use, office refreshment, samples, donations, testing).
//
// Same fetch + farmApiUrl + getAuthHeaders pattern as the other lib/api/*
// modules. The Farm API already serialises camelCase, so no lower() here.
//
// Water ships first (migration 212). Poultry and Generic will add their function
// families to this file with the same shapes.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { forceReauth } from "./session-expiry"

// ----- Types -----

export type InternalUseStatus = "Draft" | "Posted" | "Reversed"

export type InternalUseCategory =
  | "StaffWelfare"
  | "OwnerUse"
  | "OfficeUse"
  | "FarmUse"
  | "Sample"
  | "Donation"
  | "QualityTest"
  | "InternalConsumption"
  | "Other"

/**
 * Display labels — the API stores the key, the UI shows these. The wording is
 * per company type: "Staff water allowance" on a water company reads wrong on a
 * poultry farm, and "Office use" is not a thing most farms say.
 */
export const INTERNAL_USE_CATEGORY_LABELS: Record<InternalUseCategory, string> = {
  StaffWelfare: "Staff water allowance",
  OwnerUse: "Owner use",
  OfficeUse: "Office use",
  FarmUse: "Farm use",
  Sample: "Sample / promotion",
  Donation: "Donation",
  QualityTest: "Quality testing",
  InternalConsumption: "Internal consumption",
  Other: "Other",
}

export const POULTRY_INTERNAL_USE_CATEGORY_LABELS: Record<InternalUseCategory, string> = {
  ...INTERNAL_USE_CATEGORY_LABELS,
  StaffWelfare: "Staff allowance",
  FarmUse: "Farm use",
}

/** Which reasons each company type offers, in the order they should appear. */
export const WATER_INTERNAL_USE_CATEGORIES: InternalUseCategory[] = [
  "StaffWelfare", "OwnerUse", "OfficeUse", "Sample",
  "Donation", "QualityTest", "InternalConsumption", "Other",
]

export const POULTRY_INTERNAL_USE_CATEGORIES: InternalUseCategory[] = [
  "StaffWelfare", "OwnerUse", "FarmUse", "Sample",
  "Donation", "QualityTest", "InternalConsumption", "Other",
]

/** Generic offers the same set as water — "Office use" fits an ordinary business. */
export const GENERIC_INTERNAL_USE_CATEGORIES: InternalUseCategory[] = WATER_INTERNAL_USE_CATEGORIES

/** Categories where the staff-count helper is worth offering up front. */
export const STAFF_BASED_CATEGORIES: InternalUseCategory[] = ["StaffWelfare", "OfficeUse"]

export interface WaterInternalUsageItem {
  waterInternalUsageItemId?: number
  waterProductId: number
  /** Read-side only; the API joins it in. */
  productName?: string | null
  /** What the user typed, in entryUnit. */
  entryQuantity: number
  entryUnit?: string | null
  /** Conversion snapshot, computed server-side from the product's sachetsPerBag. */
  unitsPerEntryUnit?: number
  /** entryQuantity × unitsPerEntryUnit, in base units (sachets). Server-computed. */
  stockQuantity?: number
  quantityPerStaff?: number | null
  /**
   * Cost in the unit being entered — per bag when entering bags, per sachet when
   * entering sachets. This is what the user types and what totalCost is computed
   * from (migration 213). 0 means "use the weighted average".
   */
  entryUnitCost: number
  /** Derived per base unit (sachet); server-computed, read-only. */
  unitCost?: number
  totalCost?: number
  itemNotes?: string | null
}

export interface WaterInternalUsage {
  waterInternalUsageId: number
  farmId: string
  usageDate: string
  referenceNo?: string | null
  category: InternalUseCategory
  reason?: string | null
  recipientName?: string | null
  responsibleStaffId?: number | null
  staffCount?: number | null
  status: InternalUseStatus
  totalCostValue: number
  notes?: string | null
  postedBy?: string | null
  postedAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
  createdBy?: string | null
  createdAt: string
  updatedAt?: string | null
  items: WaterInternalUsageItem[]
}

export interface WaterInternalUsageInput {
  waterInternalUsageId?: number
  usageDate: string
  category: InternalUseCategory
  reason?: string | null
  recipientName?: string | null
  responsibleStaffId?: number | null
  staffCount?: number | null
  notes?: string | null
  items: WaterInternalUsageItem[]
}

// ----- Helpers -----

function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}
function activeUserId(): string {
  return getUserContext().userId || ""
}

/**
 * The posting SPs raise real, user-facing messages ("Not enough Sachet Water:
 * 240 in stock, 900 needed."). GlobalExceptionMiddleware wraps them as JSON, so
 * pull the message out rather than showing the raw envelope in a toast.
 */
function explain(method: string, path: string, status: number, body: string): string {
  try {
    const j = JSON.parse(body)
    const msg = j?.message || j?.detail || j?.title || j?.error
    if (typeof msg === "string" && msg.trim()) return msg
    if (j?.errors && typeof j.errors === "object") {
      const flat = Object.values(j.errors as Record<string, unknown>).flat().map(String)
      if (flat.length) return flat.join(" ")
    }
  } catch {
    /* not JSON — fall through */
  }
  const t = (body || "").trim()
  return t || `${method} ${path} failed (${status}).`
}

async function jget<T>(path: string): Promise<T> {
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    throw new Error(explain("GET", path, res.status, await res.text().catch(() => "")))
  }
  return (await res.json()) as T
}

async function jsend<T>(path: string, method: "POST" | "PUT" | "DELETE", body?: any): Promise<T> {
  const init: RequestInit = { method, headers: getAuthHeaders() }
  if (body !== undefined) init.body = JSON.stringify(body)
  const res = await fetch(farmApiUrl(path), init)
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    throw new Error(explain(method, path, res.status, await res.text().catch(() => "")))
  }
  if (res.status === 204) return undefined as unknown as T
  const text = await res.text()
  return text ? (JSON.parse(text) as T) : (undefined as unknown as T)
}

// ----- Water -----

export const listWaterInternalUsage = (opts?: {
  status?: InternalUseStatus
  category?: InternalUseCategory
  fromDate?: string
  toDate?: string
}) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status) qs.set("status", opts.status)
  if (opts?.category) qs.set("category", opts.category)
  if (opts?.fromDate) qs.set("fromDate", opts.fromDate)
  if (opts?.toDate) qs.set("toDate", opts.toDate)
  return jget<WaterInternalUsage[]>(`/Water/internal-usage?${qs.toString()}`)
}

export const getWaterInternalUsage = (id: number) =>
  jget<WaterInternalUsage>(`/Water/internal-usage/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

/**
 * Weighted average cost PER BASE UNIT (sachet). 0 is a legitimate answer for a
 * product with no costed inflow. Callers entering in bags scale it by
 * sachetsPerBag before showing it.
 */
export const getWaterInternalUseSuggestedCost = (waterProductId: number) =>
  jget<{ waterProductId: number; unitCost: number }>(
    `/Water/internal-usage/suggested-cost?farmId=${encodeURIComponent(activeFarmId())}&waterProductId=${waterProductId}`,
  )

export const createWaterInternalUsage = (input: WaterInternalUsageInput) =>
  jsend<WaterInternalUsage>(`/Water/internal-usage`, "POST", {
    ...input,
    farmId: activeFarmId(),
    userId: activeUserId(),
    createdBy: activeUserId(),
  })

export const updateWaterInternalUsage = (id: number, input: WaterInternalUsageInput) =>
  jsend<void>(`/Water/internal-usage/${id}`, "PUT", {
    ...input,
    waterInternalUsageId: id,
    farmId: activeFarmId(),
    userId: activeUserId(),
  })

export const deleteWaterInternalUsage = (id: number) =>
  jsend<void>(
    `/Water/internal-usage/${id}?farmId=${encodeURIComponent(activeFarmId())}&userId=${encodeURIComponent(activeUserId())}`,
    "DELETE",
  )

export const postWaterInternalUsage = (id: number) =>
  jsend<WaterInternalUsage>(
    `/Water/internal-usage/${id}/post?farmId=${encodeURIComponent(activeFarmId())}&postedBy=${encodeURIComponent(activeUserId())}`,
    "POST",
  )

export const reverseWaterInternalUsage = (id: number, reason: string) =>
  jsend<WaterInternalUsage>(
    `/Water/internal-usage/${id}/reverse?farmId=${encodeURIComponent(activeFarmId())}&reversedBy=${encodeURIComponent(activeUserId())}`,
    "POST",
    { reason, userId: activeUserId() },
  )

// ----- Poultry -----
// Same shapes as the water family; the conversion is crates → eggs and the item
// carries eggsPerCrate (default 30, ignored for anything that is not a raw-egg
// product — fnpoultrycrateunits enforces that server-side).

export interface PoultryInternalUsageItem {
  poultryInternalUsageItemId?: number
  poultryProductId: number
  productName?: string | null
  entryQuantity: number
  entryUnit?: string | null
  unitsPerEntryUnit?: number
  stockQuantity?: number
  eggsPerCrate?: number | null
  quantityPerStaff?: number | null
  /** Cost per crate / per bird / per kg — whatever unit is being entered. */
  entryUnitCost: number
  /** Derived per stock unit; server-computed, read-only. */
  unitCost?: number
  totalCost?: number
  itemNotes?: string | null
}

export interface PoultryInternalUsage {
  poultryInternalUsageId: number
  farmId: string
  usageDate: string
  referenceNo?: string | null
  category: InternalUseCategory
  reason?: string | null
  recipientName?: string | null
  responsibleStaffId?: number | null
  staffCount?: number | null
  status: InternalUseStatus
  totalCostValue: number
  notes?: string | null
  postedBy?: string | null
  postedAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
  createdBy?: string | null
  createdAt: string
  updatedAt?: string | null
  items: PoultryInternalUsageItem[]
}

export interface PoultryInternalUsageInput {
  poultryInternalUsageId?: number
  usageDate: string
  category: InternalUseCategory
  reason?: string | null
  recipientName?: string | null
  responsibleStaffId?: number | null
  staffCount?: number | null
  notes?: string | null
  items: PoultryInternalUsageItem[]
}

export const listPoultryInternalUsage = (opts?: {
  status?: InternalUseStatus
  category?: InternalUseCategory
  fromDate?: string
  toDate?: string
}) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status) qs.set("status", opts.status)
  if (opts?.category) qs.set("category", opts.category)
  if (opts?.fromDate) qs.set("fromDate", opts.fromDate)
  if (opts?.toDate) qs.set("toDate", opts.toDate)
  return jget<PoultryInternalUsage[]>(`/Poultry/internal-usage?${qs.toString()}`)
}

export const getPoultryInternalUsage = (id: number) =>
  jget<PoultryInternalUsage>(`/Poultry/internal-usage/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

/** Weighted average PER STOCK UNIT (per egg, per bird, per kg). 0 is legitimate. */
export const getPoultryInternalUseSuggestedCost = (poultryProductId: number) =>
  jget<{ poultryProductId: number; unitCost: number }>(
    `/Poultry/internal-usage/suggested-cost?farmId=${encodeURIComponent(activeFarmId())}&poultryProductId=${poultryProductId}`,
  )

export const createPoultryInternalUsage = (input: PoultryInternalUsageInput) =>
  jsend<PoultryInternalUsage>(`/Poultry/internal-usage`, "POST", {
    ...input,
    farmId: activeFarmId(),
    userId: activeUserId(),
    createdBy: activeUserId(),
  })

export const updatePoultryInternalUsage = (id: number, input: PoultryInternalUsageInput) =>
  jsend<void>(`/Poultry/internal-usage/${id}`, "PUT", {
    ...input,
    poultryInternalUsageId: id,
    farmId: activeFarmId(),
    userId: activeUserId(),
  })

export const deletePoultryInternalUsage = (id: number) =>
  jsend<void>(
    `/Poultry/internal-usage/${id}?farmId=${encodeURIComponent(activeFarmId())}&userId=${encodeURIComponent(activeUserId())}`,
    "DELETE",
  )

export const postPoultryInternalUsage = (id: number) =>
  jsend<PoultryInternalUsage>(
    `/Poultry/internal-usage/${id}/post?farmId=${encodeURIComponent(activeFarmId())}&postedBy=${encodeURIComponent(activeUserId())}`,
    "POST",
  )

export const reversePoultryInternalUsage = (id: number, reason: string) =>
  jsend<PoultryInternalUsage>(
    `/Poultry/internal-usage/${id}/reverse?farmId=${encodeURIComponent(activeFarmId())}&reversedBy=${encodeURIComponent(activeUserId())}`,
    "POST",
    { reason, userId: activeUserId() },
  )

// ----- Generic -----
// Simplest of the three: genericproducts has one freetext unitOfMeasure with no
// conversion, so entryUnitCost is just the cost per unit and stockQuantity
// equals entryQuantity. Costing is exact — genericProducts.costPrice is real.

export interface GenericInternalUsageItem {
  genericInternalUsageItemId?: number
  genericProductId: number
  productName?: string | null
  entryQuantity: number
  entryUnit?: string | null
  unitsPerEntryUnit?: number
  stockQuantity?: number
  quantityPerStaff?: number | null
  entryUnitCost: number
  unitCost?: number
  totalCost?: number
  itemNotes?: string | null
}

export interface GenericInternalUsage {
  genericInternalUsageId: number
  farmId: string
  usageDate: string
  referenceNo?: string | null
  category: InternalUseCategory
  reason?: string | null
  recipientName?: string | null
  responsibleStaffId?: number | null
  staffCount?: number | null
  status: InternalUseStatus
  totalCostValue: number
  notes?: string | null
  postedBy?: string | null
  postedAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
  createdBy?: string | null
  createdAt: string
  updatedAt?: string | null
  items: GenericInternalUsageItem[]
}

export interface GenericInternalUsageInput {
  genericInternalUsageId?: number
  usageDate: string
  category: InternalUseCategory
  reason?: string | null
  recipientName?: string | null
  responsibleStaffId?: number | null
  staffCount?: number | null
  notes?: string | null
  items: GenericInternalUsageItem[]
}

export const listGenericInternalUsage = (opts?: {
  status?: InternalUseStatus
  category?: InternalUseCategory
  fromDate?: string
  toDate?: string
}) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status) qs.set("status", opts.status)
  if (opts?.category) qs.set("category", opts.category)
  if (opts?.fromDate) qs.set("fromDate", opts.fromDate)
  if (opts?.toDate) qs.set("toDate", opts.toDate)
  return jget<GenericInternalUsage[]>(`/generic-company/internal-usage?${qs.toString()}`)
}

export const getGenericInternalUsage = (id: number) =>
  jget<GenericInternalUsage>(`/generic-company/internal-usage/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

/** The product's own cost price — exact, not an average. */
export const getGenericInternalUseSuggestedCost = (genericProductId: number) =>
  jget<{ genericProductId: number; unitCost: number }>(
    `/generic-company/internal-usage/suggested-cost?farmId=${encodeURIComponent(activeFarmId())}&genericProductId=${genericProductId}`,
  )

export const createGenericInternalUsage = (input: GenericInternalUsageInput) =>
  jsend<GenericInternalUsage>(`/generic-company/internal-usage`, "POST", {
    ...input,
    farmId: activeFarmId(),
    userId: activeUserId(),
    createdBy: activeUserId(),
  })

export const updateGenericInternalUsage = (id: number, input: GenericInternalUsageInput) =>
  jsend<void>(`/generic-company/internal-usage/${id}`, "PUT", {
    ...input,
    genericInternalUsageId: id,
    farmId: activeFarmId(),
    userId: activeUserId(),
  })

export const deleteGenericInternalUsage = (id: number) =>
  jsend<void>(
    `/generic-company/internal-usage/${id}?farmId=${encodeURIComponent(activeFarmId())}&userId=${encodeURIComponent(activeUserId())}`,
    "DELETE",
  )

export const postGenericInternalUsage = (id: number) =>
  jsend<GenericInternalUsage>(
    `/generic-company/internal-usage/${id}/post?farmId=${encodeURIComponent(activeFarmId())}&postedBy=${encodeURIComponent(activeUserId())}`,
    "POST",
  )

export const reverseGenericInternalUsage = (id: number, reason: string) =>
  jsend<GenericInternalUsage>(
    `/generic-company/internal-usage/${id}/reverse?farmId=${encodeURIComponent(activeFarmId())}&reversedBy=${encodeURIComponent(activeUserId())}`,
    "POST",
    { reason, userId: activeUserId() },
  )
