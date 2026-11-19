// Generic Asset Register and depreciation (migration 453, the Water register (283-314) renamed).
//
// On Generic the COST LINE is the document: the part paid now leaves a cash
// account, the unpaid part is owed to the supplier (a 'CapitalAsset' bill on
// Supplier Balances), and no expense row is written -- so it never reaches
// operating expenses. Depreciation is a non-cash expense. genericExpenseId on a
// cost row is therefore always null.
//
// These numbers are computed server-side and writing them has no effect:
// acquisitionCost, additionalCost, totalCapitalizedCost, accumulatedDepreciation
// and currentBookValue.
//
// `originalCost` IS THE TOTAL. Migration 283 named the sum of an asset's cost
// rows `originalcost`, and every screen printed it as "Original cost" -- so an
// asset bought for 100,000 and improved twice read as having been BOUGHT for
// 130,000. 314 split that sum into acquisitionCost + additionalCost and kept the
// old field as an alias of the total. Read totalCapitalizedCost instead; the old
// name is only here so nothing written against 283 breaks.
//
// A SEPARATE MODULE, NOT AN ADDITION TO generic.ts
// ----------------------------------------------
// The rest of the generic client lives in one 3,000-line generic.ts. This follows
// the newer per-feature shape the poultry side moved to instead -- the asset
// register is a self-contained rail with its own types, and burying it in the
// middle of that file would make both harder to read. The helpers below are the
// same ones generic.ts uses, deliberately duplicated rather than exported from it,
// so this module does not depend on the internals of a file it has no other
// reason to touch.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

// The status vocabulary is identical on both sides -- the database checks the
// same strings -- so it is imported rather than declared a second time.
export type { CapitalAssetStatus } from "./poultry-assets"
import type { CapitalAssetStatus } from "./poultry-assets"

// ----- Types -----

export interface GenericAssetCategory {
  genericAssetCategoryId: number
  farmId?: string | null
  categoryName: string
  /** A suggestion the form fills in, never a rule. */
  defaultUsefulLifeMonths?: number | null
  sortOrder: number
  isActive: boolean
  assetCount: number
}

export interface GenericCapitalAsset {
  genericCapitalAssetId: number
  farmId?: string | null
  /** Read-only per-company running number, AST-0001. */
  assetNumber?: string | null
  assetName: string
  genericAssetCategoryId?: number | null
  categoryName?: string | null
  description?: string | null
  acquisitionDate: string
  /** Depreciation runs from the month containing this date. Null = not yet earning. */
  inServiceDate?: string | null
  location?: string | null
  serialNumber?: string | null
  supplierId?: number | null
  supplierName?: string | null
  status: CapitalAssetStatus
  notes?: string | null

  /**
   * Read-only: the TOTAL capitalised cost, under 283's misleading name.
   * @deprecated Use `totalCapitalizedCost`.
   */
  originalCost: number
  /**
   * 314. Read-only: what the asset was originally acquired for, including any
   * correction to that figure. Zero for one BUILT cost by cost.
   */
  acquisitionCost: number
  /** 314. Read-only: everything capitalised into it since. */
  additionalCost: number
  /** 314. Read-only: acquisitionCost + additionalCost. Print THIS one. */
  totalCapitalizedCost: number
  residualValue: number
  /** Read-only: totalCapitalizedCost − residualValue. */
  depreciableAmount: number
  usefulLifeMonths?: number | null
  /** Read-only: depreciableAmount / usefulLifeMonths. */
  monthlyDepreciation?: number | null
  /** Read-only: the signed sum of the depreciation ledger. */
  accumulatedDepreciation: number
  /** Read-only: never falls below residualValue. */
  currentBookValue: number
  remainingDepreciable: number
  isFullyDepreciated: boolean

  costEntries: number
  depreciationEntries: number

  disposalDate?: string | null
  disposalProceeds?: number | null

  createdBy?: string | null
  createdAt?: string | null
  updatedAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null

  costs?: GenericCapitalAssetCost[]
  depreciation?: GenericAssetDepreciation[]
}

export interface GenericCapitalAssetCost {
  genericCapitalAssetCostId: number
  genericCapitalAssetId: number
  costDate: string
  description?: string | null
  costCategory?: string | null
  /** SIGNED: negative only on a correction that reduced what was recorded. */
  amount: number
  /**
   * Acquisition | AdditionalCost | OriginalCostCorrection (314).
   * Acquisition and OriginalCostCorrection together are the original
   * acquisition cost; everything else is an additional capitalised cost.
   */
  sourceType?: string | null
  /** The genericexpenses row that moved the money or opened the payable. */
  genericExpenseId?: number | null
  supplierId?: number | null
  supplierName?: string | null
  paymentStatus?: string | null
  amountPaid?: number | null
  balance?: number | null
  /** 314. Read-only, from the linked expense. */
  paymentMethod?: string | null
  /** 314. When the unpaid part falls due. */
  dueDate?: string | null
  /** 314. Which cash account the money left. */
  cashAccountName?: string | null
  /**
   * 314. What the linked expense is now for. A correction SHARES the
   * acquisition's expense, so this is the corrected figure, not the signed
   * amount of this row.
   */
  expenseAmount?: number | null
  /** 314. The expense category the document was filed under. */
  expenseCategory?: string | null
  status: string
  createdBy?: string | null
  createdAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface GenericAssetDepreciation {
  genericAssetDepreciationId: number
  genericCapitalAssetId: number
  assetNumber?: string | null
  assetName?: string | null
  categoryName?: string | null
  periodStart: string
  periodEnd: string
  depreciationDate?: string | null
  /** SIGNED: a reversal is a negative row beside the original, never an edit. */
  amount: number
  depreciationMethod?: string | null
  /** Scheduled | CatchUp | ManualAdjustment | Reversal. */
  sourceType?: string | null
  status?: string | null
  genericExpenseId?: number | null
  reversalOfId?: number | null
  originalCost?: number | null
  monthlyDepreciation?: number | null
  /** Running accumulated depreciation as at this row. */
  accumulatedAfter?: number | null
  bookValueAfter?: number | null
  createdBy?: string | null
  createdAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface GenericCapitalAssetSummary {
  totalAssets: number
  activeAssets: number
  draftAssets: number
  disposedAssets: number
  fullyDepreciated: number
  totalAssetCost: number
  accumulatedDepreciation: number
  /** A BALANCE, not a period total: what the company owns today. */
  currentBookValue: number
  addedInPeriod: number
  addedCount: number
}

export interface GenericAssetDepreciationDue {
  genericCapitalAssetId: number
  assetNumber?: string | null
  assetName?: string | null
  monthsDue: number
  amountDue: number
  monthlyDepreciation?: number | null
  nextPeriod?: string | null
}

export interface GenericDepreciationRunResult {
  assetsProcessed: number
  entriesCreated: number
  totalAmount: number
}

export interface GenericCapitalAssetInput {
  assetName: string
  assetCategoryId?: number | null
  description?: string | null
  acquisitionDate?: string | null
  inServiceDate?: string | null
  /** Optional: an asset that will be BUILT starts at nothing and grows. */
  amount?: number | null
  residualValue?: number | null
  usefulLifeMonths?: number | null
  /**
   * A genericsuppliers id. Unlike the poultry input there is no free-text supplier
   * beside it: the server reads the name off the supplier row.
   */
  supplierId?: number | null
  paymentMethod?: string | null
  /**
   * Null means paid in full, EXCEPT on a Credit purchase where it means nothing
   * has been paid -- the rule every other generic bill follows.
   */
  amountPaid?: number | null
  dueDate?: string | null
  cashAccountId?: number | null
  expenseCategory?: string | null
  location?: string | null
  serialNumber?: string | null
  notes?: string | null
}

export interface GenericCapitalAssetUpdateInput {
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

export interface GenericCapitalAssetCostInput {
  costDate?: string | null
  description?: string | null
  costCategory?: string | null
  amount: number
  supplierId?: number | null
  paymentMethod?: string | null
  amountPaid?: number | null
  dueDate?: string | null
  cashAccountId?: number | null
  expenseCategory?: string | null
}

// ----- Helpers -----

function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

function activeUserId(): string | undefined {
  const { userId } = getUserContext()
  return userId || undefined
}

async function jget<T>(path: string): Promise<T> {
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(explainHttpError("GET", path, res.status, t))
  }
  return (await res.json()) as T
}

async function jsend<T>(path: string, method: "POST" | "PUT" | "DELETE", body?: any): Promise<T> {
  const init: RequestInit = { method, headers: getAuthHeaders() }
  if (body !== undefined) init.body = JSON.stringify(body)
  const res = await fetch(farmApiUrl(path), init)
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(explainHttpError(method, path, res.status, t))
  }
  if (res.status === 204) return undefined as unknown as T
  const text = await res.text()
  return text ? (JSON.parse(text) as T) : (undefined as unknown as T)
}

// ----- Categories -----

/** Seeds the fifteen defaults on first read, so a company never has to set them up. */
export const listGenericAssetCategories = () =>
  jget<GenericAssetCategory[]>(`/Generic/assets/categories?farmId=${encodeURIComponent(activeFarmId())}`)

export const upsertGenericAssetCategory = (input: Partial<GenericAssetCategory>) =>
  jsend<number>(
    `/Generic/assets/categories?farmId=${encodeURIComponent(activeFarmId())}&userId=${encodeURIComponent(activeUserId() ?? "")}`,
    "POST",
    input,
  )

// ----- Assets -----

export const listGenericAssets = (opts?: { status?: string; categoryId?: number }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status && opts.status !== "all") qs.append("status", opts.status)
  if (opts?.categoryId) qs.append("categoryId", String(opts.categoryId))
  return jget<GenericCapitalAsset[]>(`/Generic/assets?${qs.toString()}`)
}

/**
 * The five cards. Book value ignores the dates -- it is what the company owns
 * today, not what it acquired between them; only addedInPeriod is period-scoped.
 */
export const getGenericAssetSummary = (opts?: { fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<GenericCapitalAssetSummary>(`/Generic/assets/summary?${qs.toString()}`)
}

export const getGenericAsset = (id: number) =>
  jget<GenericCapitalAsset>(`/Generic/assets/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

export const createGenericAsset = (input: GenericCapitalAssetInput) =>
  jsend<number>(`/Generic/assets?farmId=${encodeURIComponent(activeFarmId())}`, "POST", {
    ...input, farmId: activeFarmId(), createdBy: activeUserId(),
  })

export const updateGenericAsset = (id: number, input: GenericCapitalAssetUpdateInput) =>
  jsend<void>(`/Generic/assets/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "PUT", {
    ...input, farmId: activeFarmId(), updatedBy: activeUserId(),
  })

/** The construction workflow: add drilling, then the pump, then wiring, to one asset. */
export const addGenericAssetCost = (id: number, input: GenericCapitalAssetCostInput) =>
  jsend<number>(`/Generic/assets/${id}/costs?farmId=${encodeURIComponent(activeFarmId())}`, "POST", {
    ...input, farmId: activeFarmId(), createdBy: activeUserId(),
  })

/** Proceeds reach CASH and are deliberately not revenue. */
export const disposeGenericAsset = (
  id: number,
  input: { disposalDate?: string | null; proceeds?: number | null; cashAccountId?: number | null; notes?: string | null },
) =>
  jsend<void>(`/Generic/assets/${id}/dispose?farmId=${encodeURIComponent(activeFarmId())}`, "POST", {
    ...input, farmId: activeFarmId(), createdBy: activeUserId(),
  })

/** Refused once depreciation is posted, a supplier has been paid, or it is disposed. */
/**
 * 314. Correct the ORIGINAL acquisition cost -- the fix for a typed 130,000 that
 * should have been 13,000.
 *
 * This is NOT "Add cost", and it is not an editable field. It appends a dated,
 * authored, reasoned correction row and amends the acquisition's own expense, so
 * cash and the supplier balance follow without a second document being created.
 * Depreciation already posted is left exactly as posted; future months follow
 * the corrected cost on their own.
 *
 * Refused when: no reason is given, the asset is reversed or disposed, the
 * amount is already right, the residual value would exceed the corrected cost,
 * or supplier payments already settled more than the corrected cost.
 */
export const correctGenericAssetOriginalCost = (
  id: number,
  input: { newAmount: number; effectiveDate?: string | null; reason: string },
) =>
  jsend<number>(`/Generic/assets/${id}/original-cost?farmId=${encodeURIComponent(activeFarmId())}`, "PUT", {
    ...input, farmId: activeFarmId(), createdBy: activeUserId(),
  })

/**
 * 314. Reverse ONE additional capitalised cost.
 *
 * DELETE is the verb the API uses because it is the permission this needs;
 * nothing is deleted. The row is kept and marked Reversed, and its cash and
 * payable are unwound. Refused on the original acquisition (correct it instead),
 * on a correction, and once depreciation has been posted.
 */
export const reverseGenericAssetCost = (assetId: number, costId: number, reason: string) =>
  jsend<void>(
    `/Generic/assets/${assetId}/costs/${costId}?farmId=${encodeURIComponent(activeFarmId())}`,
    "DELETE",
    { farmId: activeFarmId(), reason, createdBy: activeUserId() },
  )

export const reverseGenericAsset = (id: number, reason: string) =>
  jsend<void>(`/Generic/assets/${id}/reverse?farmId=${encodeURIComponent(activeFarmId())}`, "POST", {
    farmId: activeFarmId(), reason, createdBy: activeUserId(),
  })

// ----- Depreciation -----

export const listGenericDepreciation = (opts?: { assetId?: number; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.assetId) qs.append("assetId", String(opts.assetId))
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<GenericAssetDepreciation[]>(`/Generic/asset-depreciation?${qs.toString()}`)
}

/** What Generate would charge, before it charges it. */
export const listGenericDepreciationDue = (throughDate?: string) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (throughDate) qs.append("throughDate", throughDate)
  return jget<GenericAssetDepreciationDue[]>(`/Generic/asset-depreciation/due?${qs.toString()}`)
}

/** Idempotent: a second run charges nothing. */
export const generateGenericDepreciation = (input?: { throughDate?: string | null; assetId?: number | null }) =>
  jsend<GenericDepreciationRunResult>(
    `/Generic/asset-depreciation/generate?farmId=${encodeURIComponent(activeFarmId())}`,
    "POST",
    { ...input, farmId: activeFarmId(), createdBy: activeUserId() },
  )

/**
 * Appends the opposite entry and keeps the original. Does NOT reopen the month
 * to the generator -- use adjustGenericDepreciation to re-post a corrected amount,
 * so that reversing cannot be silently undone by the next Generate.
 */
export const reverseGenericDepreciation = (entryId: number, reason: string) =>
  jsend<void>(
    `/Generic/asset-depreciation/${entryId}/reverse?farmId=${encodeURIComponent(activeFarmId())}`,
    "POST",
    { farmId: activeFarmId(), reason, createdBy: activeUserId() },
  )

export const adjustGenericDepreciation = (input: {
  assetId: number; periodStart: string; amount: number; reason: string
}) =>
  jsend<number>(
    `/Generic/asset-depreciation/adjust?farmId=${encodeURIComponent(activeFarmId())}`,
    "POST",
    { ...input, farmId: activeFarmId(), createdBy: activeUserId() },
  )
