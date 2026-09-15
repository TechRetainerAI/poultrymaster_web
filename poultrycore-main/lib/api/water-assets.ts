// Water Asset Register and depreciation (migrations 283, 284, 286).
//
// A capital asset rides the same money rail every bill rides: recording one
// writes an ordinary waterexpenses row, classified CapitalAsset, and that row is
// what moves the cash and opens the supplier payable. What makes it different is
// only that it is EXCLUDED from profit and depreciated instead.
//
// Three numbers are computed server-side and writing them has no effect:
// originalCost, accumulatedDepreciation and currentBookValue.
//
// A SEPARATE MODULE, NOT AN ADDITION TO water.ts
// ----------------------------------------------
// The rest of the water client lives in one 3,000-line water.ts. This follows
// the newer per-feature shape the poultry side moved to instead -- the asset
// register is a self-contained rail with its own types, and burying it in the
// middle of that file would make both harder to read. The helpers below are the
// same ones water.ts uses, deliberately duplicated rather than exported from it,
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

export interface WaterAssetCategory {
  waterAssetCategoryId: number
  farmId?: string | null
  categoryName: string
  /** A suggestion the form fills in, never a rule. */
  defaultUsefulLifeMonths?: number | null
  sortOrder: number
  isActive: boolean
  assetCount: number
}

export interface WaterCapitalAsset {
  waterCapitalAssetId: number
  farmId?: string | null
  /** Read-only per-company running number, AST-0001. */
  assetNumber?: string | null
  assetName: string
  waterAssetCategoryId?: number | null
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

  costs?: WaterCapitalAssetCost[]
  depreciation?: WaterAssetDepreciation[]
}

export interface WaterCapitalAssetCost {
  waterCapitalAssetCostId: number
  waterCapitalAssetId: number
  costDate: string
  description?: string | null
  costCategory?: string | null
  amount: number
  /** Acquisition | AdditionalCost. */
  sourceType?: string | null
  /** The waterexpenses row that moved the money or opened the payable. */
  waterExpenseId?: number | null
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

export interface WaterAssetDepreciation {
  waterAssetDepreciationId: number
  waterCapitalAssetId: number
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
  waterExpenseId?: number | null
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

export interface WaterCapitalAssetSummary {
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

export interface WaterAssetDepreciationDue {
  waterCapitalAssetId: number
  assetNumber?: string | null
  assetName?: string | null
  monthsDue: number
  amountDue: number
  monthlyDepreciation?: number | null
  nextPeriod?: string | null
}

export interface WaterDepreciationRunResult {
  assetsProcessed: number
  entriesCreated: number
  totalAmount: number
}

export interface WaterCapitalAssetInput {
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
   * A watersuppliers id. Unlike the poultry input there is no free-text supplier
   * beside it: the server reads the name off the supplier row.
   */
  supplierId?: number | null
  paymentMethod?: string | null
  /**
   * Null means paid in full, EXCEPT on a Credit purchase where it means nothing
   * has been paid -- the rule every other water bill follows.
   */
  amountPaid?: number | null
  dueDate?: string | null
  cashAccountId?: number | null
  expenseCategory?: string | null
  location?: string | null
  serialNumber?: string | null
  notes?: string | null
}

export interface WaterCapitalAssetUpdateInput {
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

export interface WaterCapitalAssetCostInput {
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
export const listWaterAssetCategories = () =>
  jget<WaterAssetCategory[]>(`/Water/assets/categories?farmId=${encodeURIComponent(activeFarmId())}`)

export const upsertWaterAssetCategory = (input: Partial<WaterAssetCategory>) =>
  jsend<number>(
    `/Water/assets/categories?farmId=${encodeURIComponent(activeFarmId())}&userId=${encodeURIComponent(activeUserId() ?? "")}`,
    "POST",
    input,
  )

// ----- Assets -----

export const listWaterAssets = (opts?: { status?: string; categoryId?: number }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status && opts.status !== "all") qs.append("status", opts.status)
  if (opts?.categoryId) qs.append("categoryId", String(opts.categoryId))
  return jget<WaterCapitalAsset[]>(`/Water/assets?${qs.toString()}`)
}

/**
 * The five cards. Book value ignores the dates -- it is what the company owns
 * today, not what it acquired between them; only addedInPeriod is period-scoped.
 */
export const getWaterAssetSummary = (opts?: { fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterCapitalAssetSummary>(`/Water/assets/summary?${qs.toString()}`)
}

export const getWaterAsset = (id: number) =>
  jget<WaterCapitalAsset>(`/Water/assets/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

export const createWaterAsset = (input: WaterCapitalAssetInput) =>
  jsend<number>(`/Water/assets?farmId=${encodeURIComponent(activeFarmId())}`, "POST", {
    ...input, farmId: activeFarmId(), createdBy: activeUserId(),
  })

export const updateWaterAsset = (id: number, input: WaterCapitalAssetUpdateInput) =>
  jsend<void>(`/Water/assets/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "PUT", {
    ...input, farmId: activeFarmId(), updatedBy: activeUserId(),
  })

/** The construction workflow: add drilling, then the pump, then wiring, to one asset. */
export const addWaterAssetCost = (id: number, input: WaterCapitalAssetCostInput) =>
  jsend<number>(`/Water/assets/${id}/costs?farmId=${encodeURIComponent(activeFarmId())}`, "POST", {
    ...input, farmId: activeFarmId(), createdBy: activeUserId(),
  })

/** Proceeds reach CASH and are deliberately not revenue. */
export const disposeWaterAsset = (
  id: number,
  input: { disposalDate?: string | null; proceeds?: number | null; cashAccountId?: number | null; notes?: string | null },
) =>
  jsend<void>(`/Water/assets/${id}/dispose?farmId=${encodeURIComponent(activeFarmId())}`, "POST", {
    ...input, farmId: activeFarmId(), createdBy: activeUserId(),
  })

/** Refused once depreciation is posted, a supplier has been paid, or it is disposed. */
export const reverseWaterAsset = (id: number, reason: string) =>
  jsend<void>(`/Water/assets/${id}/reverse?farmId=${encodeURIComponent(activeFarmId())}`, "POST", {
    farmId: activeFarmId(), reason, createdBy: activeUserId(),
  })

// ----- Depreciation -----

export const listWaterDepreciation = (opts?: { assetId?: number; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.assetId) qs.append("assetId", String(opts.assetId))
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<WaterAssetDepreciation[]>(`/Water/asset-depreciation?${qs.toString()}`)
}

/** What Generate would charge, before it charges it. */
export const listWaterDepreciationDue = (throughDate?: string) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (throughDate) qs.append("throughDate", throughDate)
  return jget<WaterAssetDepreciationDue[]>(`/Water/asset-depreciation/due?${qs.toString()}`)
}

/** Idempotent: a second run charges nothing. */
export const generateWaterDepreciation = (input?: { throughDate?: string | null; assetId?: number | null }) =>
  jsend<WaterDepreciationRunResult>(
    `/Water/asset-depreciation/generate?farmId=${encodeURIComponent(activeFarmId())}`,
    "POST",
    { ...input, farmId: activeFarmId(), createdBy: activeUserId() },
  )

/**
 * Appends the opposite entry and keeps the original. Does NOT reopen the month
 * to the generator -- use adjustWaterDepreciation to re-post a corrected amount,
 * so that reversing cannot be silently undone by the next Generate.
 */
export const reverseWaterDepreciation = (entryId: number, reason: string) =>
  jsend<void>(
    `/Water/asset-depreciation/${entryId}/reverse?farmId=${encodeURIComponent(activeFarmId())}`,
    "POST",
    { farmId: activeFarmId(), reason, createdBy: activeUserId() },
  )

export const adjustWaterDepreciation = (input: {
  assetId: number; periodStart: string; amount: number; reason: string
}) =>
  jsend<number>(
    `/Water/asset-depreciation/adjust?farmId=${encodeURIComponent(activeFarmId())}`,
    "POST",
    { ...input, farmId: activeFarmId(), createdBy: activeUserId() },
  )

// ----- Financial settings (274) -----
//
// Kept here rather than in a third module: the settings page and the register
// are the same workstream, and the cost-recognition read is what the register's
// "why is this excluded from profit" link points at.

export interface WaterFinancialSettings {
  farmId: string
  packagingCostRecognitionMethod: string
  treatmentCostRecognitionMethod: string
  /** Forward-dated activation. Null = in force now. The server refuses a past date. */
  effectiveFromDate?: string | null
  /** False when nobody has chosen yet. The page says so rather than showing a default as a decision. */
  isConfigured: boolean
  /**
   * Whether EXPENSE_WHEN_CONSUMED can be chosen at all. False until the water
   * phase-2 migrations are applied, and the server REFUSES the deferred method
   * while it is: stamping purchases as deferred while they are still expensed at
   * purchase would charge the same cost twice once consumption recognition
   * lands. The page reads this to explain the option rather than offer a save
   * that will fail.
   */
  deferralAvailable: boolean
  createdBy?: string | null
  createdAt?: string | null
  updatedBy?: string | null
  updatedAt?: string | null
  /** Only on the PUT response, so a change can be audited from one round trip. */
  previousPackagingMethod?: string | null
  previousTreatmentMethod?: string | null
}

export interface WaterItemCostRecognition {
  waterRawMaterialItemId: number
  itemName?: string | null
  category?: string | null
  isActive: boolean
  /** Null means "follow the company default for this category group". */
  costRecognitionOverride?: string | null
  effectiveCostRecognitionMethod: string
  /** ItemOverride | FarmDefault. */
  costRecognitionSource: string
  /** Packaging | Treatment | Unconfigured. */
  costRecognitionCategoryGroup: string
  farmDefaultMethod?: string | null
}

export const getWaterFinancialSettings = () =>
  jget<WaterFinancialSettings>(
    `/Water/financial-settings/cost-recognition?farmId=${encodeURIComponent(activeFarmId())}`)

export const updateWaterFinancialSettings = (input: {
  packagingCostRecognitionMethod: string
  treatmentCostRecognitionMethod: string
  effectiveFromDate?: string | null
}) =>
  jsend<WaterFinancialSettings>(
    `/Water/financial-settings/cost-recognition?farmId=${encodeURIComponent(activeFarmId())}`,
    "PUT",
    { ...input, farmId: activeFarmId(), updatedBy: activeUserId() },
  )

/**
 * Every item with its resolved treatment. A SEPARATE read from the raw-material
 * item list: migration 274 does not add the resolved columns to
 * spwaterrawmaterialitem_getall, so the two are joined by id on the page.
 */
export const listWaterItemCostRecognition = () =>
  jget<WaterItemCostRecognition[]>(
    `/Water/financial-settings/items?farmId=${encodeURIComponent(activeFarmId())}`)

/** Pass "USE_DEFAULT" or null to clear the override. */
export const setWaterItemCostRecognition = (itemId: number, override: string | null) =>
  jsend<WaterItemCostRecognition>(
    `/Water/financial-settings/items/${itemId}/cost-recognition?farmId=${encodeURIComponent(activeFarmId())}`,
    "PUT",
    { farmId: activeFarmId(), costRecognitionOverride: override, updatedBy: activeUserId() },
  )
