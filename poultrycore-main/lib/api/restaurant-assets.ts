import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "./config"

// =============================================================================
// Restaurant Capital Investments/Assets — API module (migration 328)
//
// The Poultry Asset Register (270-273, 313) for the standalone restaurant. A
// capital purchase moves the amount PAID NOW out of a cash account through the
// restaurant ledger (323) and is NOT charged to profit; anything unpaid is owed
// to the supplier named on the cost. Depreciation is a non-cash cost charged a
// month at a time and shown on the P&L under Depreciation & Financing.
//
// These numbers are computed server-side and writing them has no effect:
// acquisitionCost, additionalCost, totalCapitalizedCost, accumulatedDepreciation,
// currentBookValue and amountOwed. Refusals (a closed day, an overdrawn account,
// posted depreciation) come back as 400 with a plain sentence, thrown here as
// the Error message. The acting user comes from the login token on the server.
// =============================================================================

function farmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

function url(path: string, query: Record<string, string | number | undefined | null> = {}): string {
  const q = new URLSearchParams({ farmId: farmId() })
  for (const [k, v] of Object.entries(query)) if (v !== undefined && v !== null && v !== "") q.set(k, String(v))
  return farmApiUrl(`/Restaurant${path}?${q.toString()}`)
}

async function get<T>(path: string, query?: Record<string, string | number | undefined | null>): Promise<T> {
  const res = await fetch(url(path, query), { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

async function send<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(url(path), { method, headers: getAuthHeaders(), body: body ? JSON.stringify(body) : undefined })
  if (!res.ok) throw new Error(await readApiError(res))
  const text = await res.text()
  return text ? JSON.parse(text) : ({} as T)
}

// ----- Types -----------------------------------------------------------------

export type RestaurantAssetStatus = "Draft" | "Active" | "FullyDepreciated" | "Disposed" | "Reversed"

export interface RestaurantAssetCategory {
  assetCategoryId: number
  categoryName: string
  /** A suggestion the form fills in, never a rule. */
  defaultUsefulLifeMonths?: number | null
  sortOrder: number
  isActive: boolean
  assetCount: number
}

export interface RestaurantCapitalAssetCost {
  assetCostId: number
  capitalAssetId: number
  costDate: string
  description?: string | null
  costCategory?: string | null
  /** SIGNED: negative only on a correction that reduced what was recorded. */
  amount: number
  /** Acquisition | AdditionalCost | OriginalCostCorrection. */
  sourceType?: string | null
  correctionOfId?: number | null
  supplierId?: number | null
  supplierName?: string | null
  paymentMethod?: string | null
  /** Cash that left when this row was posted (≤ 0 on a correction: money handed back). */
  amountPaid: number
  /** Still owed on the purchase document this row belongs to. */
  balance: number
  paymentStatus?: string | null
  dueDate?: string | null
  cashAccountId?: number | null
  cashAccountName?: string | null
  /** What the purchase document is now for (an acquisition carries its corrections). */
  documentAmount?: number | null
  status: string
  createdBy?: string | null
  createdAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface RestaurantAssetDepreciation {
  assetDepreciationId: number
  capitalAssetId: number
  assetNumber?: string | null
  assetName?: string | null
  categoryName?: string | null
  periodStart: string
  periodEnd: string
  depreciationDate?: string | null
  /** SIGNED: a reversal is a negative row beside the original, never an edit. */
  amount: number
  depreciationMethod?: string | null
  /** Scheduled | ManualAdjustment | Reversal. */
  sourceType?: string | null
  status?: string | null
  reversalOfId?: number | null
  originalCost?: number | null
  monthlyDepreciation?: number | null
  accumulatedAfter?: number | null
  bookValueAfter?: number | null
  createdBy?: string | null
  createdAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface RestaurantCapitalAsset {
  capitalAssetId: number
  /** Read-only per-restaurant running number, AST-0001. */
  assetNumber: string
  assetName: string
  assetCategoryId?: number | null
  categoryName?: string | null
  description?: string | null
  acquisitionDate: string
  /** Depreciation runs from the month containing this date. Null = not yet in service. */
  inServiceDate?: string | null
  location?: string | null
  serialNumber?: string | null
  supplierId?: number | null
  supplierName?: string | null
  status: RestaurantAssetStatus
  notes?: string | null
  acquisitionCost: number
  additionalCost: number
  /** acquisitionCost + additionalCost. Print THIS one. */
  totalCapitalizedCost: number
  residualValue: number
  depreciableAmount: number
  usefulLifeMonths?: number | null
  monthlyDepreciation?: number | null
  accumulatedDepreciation: number
  /** Never falls below residualValue. */
  currentBookValue: number
  remainingDepreciable: number
  isFullyDepreciated: boolean
  costEntries: number
  depreciationEntries: number
  /** Still owed to suppliers on this asset's purchases. */
  amountOwed: number
  disposalDate?: string | null
  disposalProceeds?: number | null
  disposalNotes?: string | null
  createdBy?: string | null
  createdAt?: string | null
  updatedAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
  costs?: RestaurantCapitalAssetCost[]
  depreciation?: RestaurantAssetDepreciation[]
}

export interface RestaurantCapitalAssetSummary {
  totalAssets: number
  activeAssets: number
  draftAssets: number
  disposedAssets: number
  fullyDepreciated: number
  totalAssetCost: number
  accumulatedDepreciation: number
  /** A BALANCE, not a period total: what the restaurant owns today. */
  currentBookValue: number
  addedInPeriod: number
  addedCount: number
  amountOwed: number
}

export interface RestaurantAssetDepreciationDue {
  capitalAssetId: number
  assetNumber?: string | null
  assetName?: string | null
  monthsDue: number
  amountDue: number
  monthlyDepreciation?: number | null
  nextPeriod?: string | null
}

export interface RestaurantDepreciationRunResult {
  assetsProcessed: number
  entriesCreated: number
  totalAmount: number
}

export interface RestaurantCapitalAssetInput {
  assetName: string
  assetCategoryId?: number | null
  description?: string | null
  acquisitionDate?: string | null
  inServiceDate?: string | null
  /** Optional: something built cost by cost starts at nothing and grows. */
  amount?: number | null
  residualValue?: number | null
  usefulLifeMonths?: number | null
  supplier?: string | null
  supplierId?: number | null
  paymentMethod?: string | null
  /** Blank = paid in full (nothing, on Credit). */
  amountPaid?: number | null
  dueDate?: string | null
  cashAccountId?: number | null
  location?: string | null
  serialNumber?: string | null
  notes?: string | null
}

export interface RestaurantCapitalAssetUpdateInput {
  assetName?: string | null
  assetCategoryId?: number | null
  description?: string | null
  location?: string | null
  serialNumber?: string | null
  notes?: string | null
  inServiceDate?: string | null
  usefulLifeMonths?: number | null
  residualValue?: number | null
  /** The three financial fields are locked once depreciation has been posted. */
  setFinancials?: boolean
}

export interface RestaurantCapitalAssetCostInput {
  costDate?: string | null
  description?: string | null
  costCategory?: string | null
  amount: number
  supplier?: string | null
  supplierId?: number | null
  paymentMethod?: string | null
  amountPaid?: number | null
  dueDate?: string | null
  cashAccountId?: number | null
}

/** How a capital purchase was paid. Credit = nothing paid now, all owed. */
export const ASSET_PAYMENT_METHODS = ["Cash", "MoMo", "Bank", "Credit"] as const

// ----- Categories --------------------------------------------------------------

/** Seeds the restaurant defaults on first read. */
export const listRestaurantAssetCategories = () => get<RestaurantAssetCategory[]>("/assets/categories")

// ----- Assets --------------------------------------------------------------------

export const listRestaurantAssets = (opts?: { status?: string; categoryId?: number }) =>
  get<RestaurantCapitalAsset[]>("/assets", {
    status: opts?.status && opts.status !== "all" ? opts.status : undefined,
    categoryId: opts?.categoryId,
  })

/** The five cards. Book value ignores the dates; only addedInPeriod is period-scoped. */
export const getRestaurantAssetSummary = (opts?: { fromDate?: string; toDate?: string }) =>
  get<RestaurantCapitalAssetSummary>("/assets/summary", { fromDate: opts?.fromDate, toDate: opts?.toDate })

export const getRestaurantAsset = (id: number) => get<RestaurantCapitalAsset>(`/assets/${id}`)

export const createRestaurantAsset = (input: RestaurantCapitalAssetInput) =>
  send<{ capitalAssetId: number }>("POST", "/assets", input)

export const updateRestaurantAsset = (id: number, input: RestaurantCapitalAssetUpdateInput) =>
  send<void>("PUT", `/assets/${id}`, input)

/** The construction / refit workflow: add installation, then the extraction hood, to one asset. */
export const addRestaurantAssetCost = (id: number, input: RestaurantCapitalAssetCostInput) =>
  send<{ assetCostId: number }>("POST", `/assets/${id}/costs`, input)

/**
 * Correct the ORIGINAL acquisition cost -- not Add cost, not an editable field.
 * Appends a dated, reasoned correction row; if the corrected cost is below what
 * was paid, the difference goes back to the account it left.
 */
export const correctRestaurantAssetOriginalCost = (
  id: number,
  input: { newAmount: number; effectiveDate?: string | null; reason: string },
) => send<{ assetCostId: number }>("PUT", `/assets/${id}/original-cost`, input)

/** Reverse ONE added cost. Nothing is deleted: the row is kept and marked Reversed. */
export const reverseRestaurantAssetCost = (assetId: number, costId: number, reason: string) =>
  send<void>("DELETE", `/assets/${assetId}/costs/${costId}`, { reason })

/** Proceeds reach CASH and are deliberately not revenue. */
export const disposeRestaurantAsset = (
  id: number,
  input: { disposalDate?: string | null; proceeds?: number | null; cashAccountId?: number | null; notes?: string | null },
) => send<void>("POST", `/assets/${id}/dispose`, input)

/** Refused once depreciation is posted or the asset is disposed. */
export const reverseRestaurantAsset = (id: number, reason: string) =>
  send<void>("POST", `/assets/${id}/reverse`, { reason })

// ----- Depreciation --------------------------------------------------------------

export const listRestaurantDepreciation = (opts?: { assetId?: number; fromDate?: string; toDate?: string }) =>
  get<RestaurantAssetDepreciation[]>("/asset-depreciation", {
    assetId: opts?.assetId, fromDate: opts?.fromDate, toDate: opts?.toDate,
  })

/** What Generate would charge, before it charges it. */
export const listRestaurantDepreciationDue = (throughDate?: string) =>
  get<RestaurantAssetDepreciationDue[]>("/asset-depreciation/due", { throughDate })

/** Idempotent: a second run charges nothing. Never moves cash. */
export const generateRestaurantDepreciation = (input?: { throughDate?: string | null; assetId?: number | null }) =>
  send<RestaurantDepreciationRunResult>("POST", "/asset-depreciation/generate", input ?? {})

/** Appends the opposite entry and keeps the original; the month is NOT reopened. */
export const reverseRestaurantDepreciation = (entryId: number, reason: string) =>
  send<void>("POST", `/asset-depreciation/${entryId}/reverse`, { reason })

export const adjustRestaurantDepreciation = (input: { assetId: number; periodStart: string; amount: number; reason: string }) =>
  send<{ assetDepreciationId: number }>("POST", "/asset-depreciation/adjust", input)
