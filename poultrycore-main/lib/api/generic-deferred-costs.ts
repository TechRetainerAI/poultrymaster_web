// Generic Deferred inventory cost (migration 452, Report 40 Part 6): the
// Poultry/Water client on api/Generic/deferred-inventory-costs. A "lot" is a
// stock movement that added stock (purchase, opening stock, production, ...);
// lotId is its id, genericPurchaseId is set when it came from a purchase.
import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

export type GenericDeferredCostScope = "DEFERRED" | "RECOGNIZED" | "EXCEPTION" | "ALL"

export interface GenericDeferredPurchase {
  lotId: number
  genericPurchaseId?: number | null
  purchaseDate: string
  genericProductId: number
  itemName?: string | null
  category?: string | null
  unitOfMeasure?: string | null
  productionUnit?: string | null
  supplierId?: number | null
  supplierName?: string | null
  /** Purchase | Opening stock | Produced | Stock adjustment | Transfer in */
  lotSource?: string | null
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
  costRecognitionMethod?: string | null
  recognitionMethodLabel?: string | null
  status?: string | null
  exceptionReason?: string | null
  recognitionEvents: number
  lastRecognitionDate?: string | null
  costingMethod?: string | null
  queuePosition?: number | null
  quantityAheadInQueue?: number | null
}

export interface GenericDeferredRecognition {
  genericStockMovementId: number
  usedDate: string
  sourceType?: string | null
  sourceLabel?: string | null
  referenceId?: number | null
  itemName?: string | null
  productionUnit?: string | null
  quantityDrawn: number
  unitCostAtDraw: number
  operationalCost: number
  recognizedCost: number
  recognitionOutcome?: string | null
  isReversed: boolean
}

export interface GenericDeferredCostSummary {
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

export interface GenericDeferredCostResponse {
  summary: GenericDeferredCostSummary
  purchases: GenericDeferredPurchase[]
}

export interface GenericDeferredCostFilters {
  scope?: GenericDeferredCostScope
  itemId?: number
  supplierId?: number
  category?: string
  fromDate?: string
  toDate?: string
  search?: string
}

function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
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

// ----- Calls -----

export const getGenericDeferredCosts = (f?: GenericDeferredCostFilters) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  qs.append("scope", f?.scope ?? "DEFERRED")
  if (f?.itemId != null) qs.append("itemId", String(f.itemId))
  if (f?.supplierId != null) qs.append("supplierId", String(f.supplierId))
  if (f?.category) qs.append("category", f.category)
  if (f?.fromDate) qs.append("fromDate", f.fromDate)
  if (f?.toDate) qs.append("toDate", f.toDate)
  if (f?.search) qs.append("search", f.search)
  return jget<GenericDeferredCostResponse>(`/Generic/deferred-inventory-costs?${qs.toString()}`)
}

export const getGenericDeferredCostHistory = (lotId: number) =>
  jget<GenericDeferredRecognition[]>(
    `/Generic/deferred-inventory-costs/${lotId}/history?farmId=${encodeURIComponent(activeFarmId())}`)
