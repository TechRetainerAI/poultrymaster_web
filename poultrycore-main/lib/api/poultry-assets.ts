// Poultry Asset Register and depreciation (migrations 270-273).
//
// A capital asset rides the same money rail every bill rides: recording one
// writes an ordinary expense, classified CapitalAsset, and that row is what
// moves the cash and opens the supplier payable. What makes it different is
// only that it is EXCLUDED from profit and depreciated instead.
//
// Three numbers are computed server-side and writing them has no effect:
// originalCost, accumulatedDepreciation and currentBookValue.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

// ----- Types -----

export type CapitalAssetStatus =
  | "Draft"
  | "Active"
  | "FullyDepreciated"
  | "Disposed"
  | "Reversed"

export interface PoultryAssetCategory {
  poultryAssetCategoryId: number
  farmId?: string | null
  categoryName: string
  /** A suggestion the form fills in, never a rule. */
  defaultUsefulLifeMonths?: number | null
  sortOrder: number
  isActive: boolean
  assetCount: number
}

export interface PoultryCapitalAsset {
  poultryCapitalAssetId: number
  farmId?: string | null
  /** Read-only per-farm running number, AST-0001. */
  assetNumber?: string | null
  assetName: string
  poultryAssetCategoryId?: number | null
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

  /** Read-only: the sum of the asset's capitalised costs. */
  originalCost: number
  residualValue: number
  /** Read-only: originalCost − residualValue. */
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

  costs?: PoultryCapitalAssetCost[]
  depreciation?: PoultryAssetDepreciation[]
}

export interface PoultryCapitalAssetCost {
  poultryCapitalAssetCostId: number
  poultryCapitalAssetId: number
  costDate: string
  description?: string | null
  costCategory?: string | null
  amount: number
  /** Acquisition | AdditionalCost. */
  sourceType?: string | null
  /** The expense row that moved the money or opened the payable. */
  expenseId?: number | null
  supplierId?: number | null
  supplierName?: string | null
  paymentStatus?: string | null
  amountPaid?: number | null
  balance?: number | null
  status: string
  createdBy?: string | null
  createdAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface PoultryAssetDepreciation {
  poultryAssetDepreciationId: number
  poultryCapitalAssetId: number
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
  expenseId?: number | null
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

export interface PoultryCapitalAssetSummary {
  totalAssets: number
  activeAssets: number
  draftAssets: number
  disposedAssets: number
  fullyDepreciated: number
  totalAssetCost: number
  accumulatedDepreciation: number
  /** A BALANCE, not a period total: what the farm owns today. */
  currentBookValue: number
  addedInPeriod: number
  addedCount: number
}

export interface PoultryAssetDepreciationDue {
  poultryCapitalAssetId: number
  assetNumber?: string | null
  assetName?: string | null
  monthsDue: number
  amountDue: number
  monthlyDepreciation?: number | null
  nextPeriod?: string | null
}

export interface PoultryDepreciationRunResult {
  assetsProcessed: number
  entriesCreated: number
  totalAmount: number
}

export interface PoultryCapitalAssetInput {
  assetName: string
  assetCategoryId?: number | null
  description?: string | null
  acquisitionDate?: string | null
  inServiceDate?: string | null
  /** Optional: an asset that will be BUILT starts at nothing and grows. */
  amount?: number | null
  residualValue?: number | null
  usefulLifeMonths?: number | null
  supplier?: string | null
  supplierId?: number | null
  paymentMethod?: string | null
  amountPaid?: number | null
  dueDate?: string | null
  cashAccountId?: number | null
  expenseCategory?: string | null
  location?: string | null
  serialNumber?: string | null
  notes?: string | null
}

export interface PoultryCapitalAssetUpdateInput {
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

export interface PoultryCapitalAssetCostInput {
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

/** Seeds the thirteen defaults on first read, so a farm never has to set them up. */
export const listPoultryAssetCategories = () =>
  jget<PoultryAssetCategory[]>(`/Poultry/assets/categories?farmId=${encodeURIComponent(activeFarmId())}`)

export const upsertPoultryAssetCategory = (input: Partial<PoultryAssetCategory>) =>
  jsend<number>(
    `/Poultry/assets/categories?farmId=${encodeURIComponent(activeFarmId())}&userId=${encodeURIComponent(activeUserId() ?? "")}`,
    "POST",
    input,
  )

// ----- Assets -----

export const listPoultryAssets = (opts?: { status?: string; categoryId?: number }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status && opts.status !== "all") qs.append("status", opts.status)
  if (opts?.categoryId) qs.append("categoryId", String(opts.categoryId))
  return jget<PoultryCapitalAsset[]>(`/Poultry/assets?${qs.toString()}`)
}

/**
 * The five cards. Book value ignores the dates -- it is what the farm owns
 * today, not what it acquired between them; only addedInPeriod is period-scoped.
 */
export const getPoultryAssetSummary = (opts?: { fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<PoultryCapitalAssetSummary>(`/Poultry/assets/summary?${qs.toString()}`)
}

export const getPoultryAsset = (id: number) =>
  jget<PoultryCapitalAsset>(`/Poultry/assets/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

export const createPoultryAsset = (input: PoultryCapitalAssetInput) =>
  jsend<number>(`/Poultry/assets?farmId=${encodeURIComponent(activeFarmId())}`, "POST", {
    ...input, farmId: activeFarmId(), createdBy: activeUserId(),
  })

export const updatePoultryAsset = (id: number, input: PoultryCapitalAssetUpdateInput) =>
  jsend<void>(`/Poultry/assets/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "PUT", {
    ...input, farmId: activeFarmId(), updatedBy: activeUserId(),
  })

/** The construction workflow: add cement, then wood, then labour, to one asset. */
export const addPoultryAssetCost = (id: number, input: PoultryCapitalAssetCostInput) =>
  jsend<number>(`/Poultry/assets/${id}/costs?farmId=${encodeURIComponent(activeFarmId())}`, "POST", {
    ...input, farmId: activeFarmId(), createdBy: activeUserId(),
  })

/** Proceeds reach CASH and are deliberately not revenue. */
export const disposePoultryAsset = (
  id: number,
  input: { disposalDate?: string | null; proceeds?: number | null; cashAccountId?: number | null; notes?: string | null },
) =>
  jsend<void>(`/Poultry/assets/${id}/dispose?farmId=${encodeURIComponent(activeFarmId())}`, "POST", {
    ...input, farmId: activeFarmId(), createdBy: activeUserId(),
  })

/** Refused once depreciation is posted, a supplier has been paid, or it is disposed. */
export const reversePoultryAsset = (id: number, reason: string) =>
  jsend<void>(`/Poultry/assets/${id}/reverse?farmId=${encodeURIComponent(activeFarmId())}`, "POST", {
    farmId: activeFarmId(), reason, createdBy: activeUserId(),
  })

// ----- Depreciation -----

export const listPoultryDepreciation = (opts?: { assetId?: number; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.assetId) qs.append("assetId", String(opts.assetId))
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<PoultryAssetDepreciation[]>(`/Poultry/asset-depreciation?${qs.toString()}`)
}

/** What Generate would charge, before it charges it. */
export const listPoultryDepreciationDue = (throughDate?: string) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (throughDate) qs.append("throughDate", throughDate)
  return jget<PoultryAssetDepreciationDue[]>(`/Poultry/asset-depreciation/due?${qs.toString()}`)
}

/** Idempotent: a second run charges nothing. */
export const generatePoultryDepreciation = (input?: { throughDate?: string | null; assetId?: number | null }) =>
  jsend<PoultryDepreciationRunResult>(
    `/Poultry/asset-depreciation/generate?farmId=${encodeURIComponent(activeFarmId())}`,
    "POST",
    { ...input, farmId: activeFarmId(), createdBy: activeUserId() },
  )

/**
 * Appends the opposite entry and keeps the original. Does NOT reopen the month
 * to the generator -- use adjustPoultryDepreciation to re-post a corrected
 * amount, so that reversing cannot be silently undone by the next Generate.
 */
export const reversePoultryDepreciation = (entryId: number, reason: string) =>
  jsend<void>(
    `/Poultry/asset-depreciation/${entryId}/reverse?farmId=${encodeURIComponent(activeFarmId())}`,
    "POST",
    { farmId: activeFarmId(), reason, createdBy: activeUserId() },
  )

export const adjustPoultryDepreciation = (input: {
  assetId: number; periodStart: string; amount: number; reason: string
}) =>
  jsend<number>(
    `/Poultry/asset-depreciation/adjust?farmId=${encodeURIComponent(activeFarmId())}`,
    "POST",
    { ...input, farmId: activeFarmId(), createdBy: activeUserId() },
  )
