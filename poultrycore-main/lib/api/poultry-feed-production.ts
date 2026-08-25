import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

// Feed Production module API wrappers. Calls hit /Poultry/* on the Farm API via
// the same-origin proxy. Additive; a dedicated module that reuses the poultry
// raw-material inventory. Backend controllers auto-serialize camelCase.

// ---------------------------------------------------------------- Helpers
function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}
function activeUserId(): string | null {
  const { userId } = getUserContext()
  return userId || null
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

// ---------------------------------------------------------------- Formulas
export type FeedFormulaQuantityMode = "Percentage" | "FixedQuantity"

export interface FeedFormulaLine {
  poultryFeedFormulaLineId: number
  poultryFeedFormulaId: number
  ingredientItemId: number
  ingredientName?: string | null
  ingredientUnit?: string | null
  availableStock: number
  latestUnitCost: number
  quantityMode: FeedFormulaQuantityMode
  percentage?: number | null
  fixedQuantity?: number | null
  unitOfMeasure?: string | null
  sortOrder: number
  notes?: string | null
}

export interface FeedFormula {
  poultryFeedFormulaId: number
  farmId: string
  formulaName: string
  finishedFeedItemId?: number | null   // optional: a formula is reusable across any finished feed
  finishedFeedItemName?: string | null
  finishedFeedUnit?: string | null
  defaultOutputUnit?: string | null
  notes?: string | null
  isActive: boolean
  createdBy?: string | null
  createdAt?: string | null
  updatedAt?: string | null
  // List-view aggregates (present on list rows)
  lineCount?: number
  percentageTotal?: number
  // Detail (present on getFeedFormula)
  lines?: FeedFormulaLine[]
}

export interface FeedFormulaLineInput {
  ingredientItemId: number
  quantityMode: FeedFormulaQuantityMode
  percentage?: number | null
  fixedQuantity?: number | null
  unitOfMeasure?: string | null
  sortOrder: number
  notes?: string | null
}

export interface FeedFormulaUpsertInput {
  poultryFeedFormulaId?: number | null
  formulaName: string
  finishedFeedItemId?: number | null   // optional: leave null to keep the formula reusable
  defaultOutputUnit?: string | null
  notes?: string | null
  isActive?: boolean
  lines: FeedFormulaLineInput[]
}

export const listFeedFormulas = () =>
  jget<FeedFormula[]>(`/Poultry/feed-formulas?farmId=${encodeURIComponent(activeFarmId())}`)

export const getFeedFormula = (id: number) =>
  jget<FeedFormula>(`/Poultry/feed-formulas/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

export const upsertFeedFormula = (input: FeedFormulaUpsertInput) =>
  jsend<{ poultryFeedFormulaId: number }>(`/Poultry/feed-formulas`, "POST", {
    ...input,
    farmId: activeFarmId(),
    userId: activeUserId(),
  })

export const deleteFeedFormula = (id: number) =>
  jsend<void>(`/Poultry/feed-formulas/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ---------------------------------------------------------------- Batches
export type FeedProductionSourceType = "FromInventory" | "BoughtDuringProduction" | "MixedSource"
export type FeedProductionStatus = "Draft" | "Posted" | "Reversed"
export type PaymentStatus = "Paid" | "Unpaid" | "Partial"

// How a batch line's quantity was arrived at. "Quantity" is the literal figure;
// "FixedQuantity" means fixedQuantity holds the recipe amount the farmer typed,
// scaled to fill the batch the way an all-fixed formula is — see
// lib/feed-formula-scale.ts. Persisted by migration 184 so reopening a draft
// keeps following the batch size.
export type FeedProductionLineQuantityMode = "Quantity" | "FixedQuantity"

export interface FeedProductionBatchLine {
  poultryFeedProductionBatchLineId: number
  poultryFeedProductionBatchId: number
  ingredientItemId: number
  ingredientName?: string | null
  availableStock: number
  sourceType: FeedProductionSourceType
  quantityUsed: number
  unitOfMeasure?: string | null
  quantityMode?: FeedProductionLineQuantityMode | null
  fixedQuantity?: number | null
  inventoryQuantityUsed?: number | null
  purchasedQuantityUsed?: number | null
  inventoryUnitCost?: number | null
  purchasedUnitCost?: number | null
  unitCost: number
  totalCost: number
  supplierId?: number | null
  supplierName?: string | null
  purchaseReference?: string | null
  paymentStatus?: PaymentStatus | null
  amountPaid?: number | null
  paidFromCashAccountId?: number | null
  paymentMethod?: string | null
  sortOrder: number
  notes?: string | null
}

export interface FeedProductionAdditionalCost {
  poultryFeedProductionAdditionalCostId: number
  poultryFeedProductionBatchId: number
  costType: string
  amount: number
  paymentStatus?: PaymentStatus | null
  amountPaid?: number | null
  paidFromCashAccountId?: number | null
  paymentMethod?: string | null
  supplierId?: number | null
  payeeName?: string | null
  sortOrder: number
  notes?: string | null
}

export interface FeedProductionBatch {
  poultryFeedProductionBatchId: number
  farmId: string
  batchNumber?: string | null
  productionDate?: string | null
  finishedFeedItemId: number
  finishedFeedItemName?: string | null
  finishedFeedUnit?: string | null
  formulaId?: number | null
  formulaName?: string | null
  quantityProduced: number
  outputUnit?: string | null
  totalIngredientCost: number
  totalAdditionalCost: number
  totalProductionCost: number
  costPerOutputUnit: number
  status: FeedProductionStatus
  notes?: string | null
  createdBy?: string | null
  createdAt?: string | null
  updatedAt?: string | null
  postedBy?: string | null
  postedAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
  lines?: FeedProductionBatchLine[]
  additionalCosts?: FeedProductionAdditionalCost[]
}

export interface FeedProductionBatchLineInput {
  ingredientItemId: number
  sourceType: FeedProductionSourceType
  quantityUsed: number
  unitOfMeasure?: string | null
  // The server falls back to "Quantity" when the recipe amount is missing or zero.
  quantityMode?: FeedProductionLineQuantityMode | null
  fixedQuantity?: number | null
  inventoryQuantityUsed?: number | null
  purchasedQuantityUsed?: number | null
  inventoryUnitCost?: number | null
  purchasedUnitCost?: number | null
  supplierId?: number | null
  supplierName?: string | null
  purchaseReference?: string | null
  paymentStatus?: PaymentStatus | null
  amountPaid?: number | null
  paidFromCashAccountId?: number | null
  paymentMethod?: string | null
  sortOrder: number
  notes?: string | null
}

export interface FeedProductionAdditionalCostInput {
  costType: string
  amount: number
  paymentStatus?: PaymentStatus | null
  amountPaid?: number | null
  paidFromCashAccountId?: number | null
  paymentMethod?: string | null
  supplierId?: number | null
  payeeName?: string | null
  sortOrder: number
  notes?: string | null
}

export interface FeedProductionBatchSaveInput {
  poultryFeedProductionBatchId?: number | null
  batchNumber?: string | null
  productionDate?: string | null
  finishedFeedItemId: number
  formulaId?: number | null
  quantityProduced: number
  outputUnit?: string | null
  notes?: string | null
  lines: FeedProductionBatchLineInput[]
  additionalCosts: FeedProductionAdditionalCostInput[]
}

export interface FeedBatchItem {
  poultryRawMaterialItemId: number
  itemName: string
  category: string
  unitOfMeasure?: string | null
  currentQuantity: number
  isActive: boolean
  latestUnitCost: number
  // Stock that posting can actually draw, across purchase lots. Lower than
  // currentQuantity when stock was added by adjustment (which creates no lot).
  availableFromLots: number
}

export const listFeedProductionItems = () =>
  jget<FeedBatchItem[]>(`/Poultry/feed-production/items?farmId=${encodeURIComponent(activeFarmId())}`)

export const listFeedProductionBatches = (opts?: { fromDate?: string; toDate?: string; status?: FeedProductionStatus }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  if (opts?.status) qs.append("status", opts.status)
  return jget<FeedProductionBatch[]>(`/Poultry/feed-production?${qs.toString()}`)
}

export const getFeedProductionBatch = (id: number) =>
  jget<FeedProductionBatch>(`/Poultry/feed-production/${id}?farmId=${encodeURIComponent(activeFarmId())}`)

export const saveFeedProductionBatch = (input: FeedProductionBatchSaveInput) =>
  jsend<FeedProductionBatch>(`/Poultry/feed-production`, "POST", {
    ...input,
    farmId: activeFarmId(),
    userId: activeUserId(),
  })

export const deleteFeedProductionBatch = (id: number) =>
  jsend<void>(`/Poultry/feed-production/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

export interface FeedIngredientUsageRow {
  ingredientItemId: number
  ingredientName?: string | null
  unitOfMeasure?: string | null
  totalQuantityUsed: number
  totalCost: number
  fromInventoryQuantity: number
  purchasedQuantity: number
  batchCount: number
}

export interface FeedTraceabilityRow {
  poultryFeedProductionBatchId: number
  batchNumber?: string | null
  finishedFeedItemId: number
  finishedFeedName?: string | null
  poultryRawMaterialUsageId: number
  productionRecordId?: number | null
  quantityUsed: number
  quantityDrawn: number
  unitCostAtDraw: number
  usedDate?: string | null
}

export const getFeedIngredientUsageReport = (opts?: { fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<FeedIngredientUsageRow[]>(`/Poultry/feed-production/reports/ingredient-usage?${qs.toString()}`)
}

export const getFeedProductionTraceability = (id: number) =>
  jget<FeedTraceabilityRow[]>(`/Poultry/feed-production/${id}/traceability?farmId=${encodeURIComponent(activeFarmId())}`)

export const postFeedProductionBatch = (id: number) =>
  jsend<FeedProductionBatch>(`/Poultry/feed-production/${id}/post`, "POST", { farmId: activeFarmId(), userId: activeUserId() })

export const reverseFeedProductionBatch = (id: number, reversalReason?: string) =>
  jsend<FeedProductionBatch>(`/Poultry/feed-production/${id}/reverse`, "POST", { farmId: activeFarmId(), userId: activeUserId(), reversalReason: reversalReason ?? null })
