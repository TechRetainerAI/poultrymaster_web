// Water deferred inventory costs — the read side of water cost recognition.
//
// Which raw-material purchases still hold cost that has not reached Profit &
// Loss, which production runs moved it there, and how any one consumption's
// cost was worked out.
//
// READ-ONLY BY DESIGN. What has been recognised is DERIVED from the cost layers
// and their allocations -- there is no writer here, and adding one would create
// a second answer that immediately disagreed with the P&L. Recognition happens
// where consumption happens; this module only reports it.
//
// A SEPARATE MODULE, NOT AN ADDITION TO water.ts
// ----------------------------------------------
// Same call lib/api/water-assets.ts made, for the same reason: the rest of the
// water client lives in one 3,000-line water.ts, and burying a self-contained
// rail in the middle of it makes both harder to read. The helpers below are
// duplicated from water-assets.ts rather than exported from it, so this module
// does not depend on the internals of a file it has no other reason to touch.
//
// WHERE WATER DIFFERS FROM THE POULTRY TWIN (lib/api/poultry-inventory.ts)
// -----------------------------------------------------------------------
//  * EVERY water lot is BOUGHT. There is no feed-production equivalent, so
//    there is no "produced lot" concept here -- no batch-as-supplier, no
//    isLotProduced. A purchase always has a supplier or nothing.
//  * Consumption belongs to a PRODUCTION BATCH (sachets/bottles), not a flock.
//    Where poultry answers "which flock ate it", water answers "which batch
//    packed it".

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

// ----- Scope -----

/**
 * DEFERRED   cost still waiting to reach P&L. The default view.
 * RECOGNIZED lots that WERE deferred and are now fully expensed. Deliberately
 *            excludes expense-at-purchase lots: they were never deferred.
 * EXCEPTION  rows whose two independent counts disagree, or with cost stranded
 *            on a lot that has no stock left.
 * ALL        every purchase, however it was recognised.
 */
export type WaterDeferredCostScope = "DEFERRED" | "RECOGNIZED" | "EXCEPTION" | "ALL"

// ----- Types -----

export interface WaterDeferredPurchase {
  waterRawMaterialPurchaseId: number
  purchaseDate: string
  waterRawMaterialItemId: number
  itemName?: string | null
  category?: string | null
  /** How the item is BOUGHT (e.g. "Roll"). */
  unitOfMeasure?: string | null
  /** How it is CONSUMED (e.g. "Sachet"). Every quantity below is in this unit. */
  productionUnit?: string | null
  supplierId?: number | null
  supplierName?: string | null

  /** All three in PRODUCTION units — the unit a batch draws the stock in. */
  purchasedQuantity: number
  consumedQuantity: number
  remainingQuantity: number

  /** What the stock cost. NOT the deferred basis. */
  operationalCost: number
  /** What this lot deferred when it was created. 0 on expense-at-purchase. */
  deferredTotalCost: number
  /** How much of that has reached P&L. Already net of reversals. */
  recognizedCost: number
  /** How much is still waiting. */
  deferredRemainingCost: number
  recognitionPercent: number

  /** The same figure recounted from the individual allocations. */
  allocatedRecognizedCost: number
  /** Gap between the two counts. Non-zero means Exception. */
  recognitionDrift: number

  /** The method snapshot taken when the lot opened, NOT today's setting. */
  costRecognitionMethod?: string | null
  recognitionMethodLabel?: string | null
  /** Expensed at purchase | Not yet expensed | Partly expensed | Fully expensed | Exception */
  status?: string | null
  /** Plain-language reason, set only on Exception rows. */
  exceptionReason?: string | null

  recognitionEvents: number
  lastRecognitionDate?: string | null

  // ---- the consumption queue ----------------------------------------------
  /** FIFO | LIFO | HIFO — decides draw order, and therefore everything below. */
  costingMethod?: string | null
  /** Place in the queue for this item, 1 = drawn next. NULL when the lot has no
   *  stock left, so it is not queued at all. */
  queuePosition?: number | null
  /** Stock (production units) consumed before this lot is reached. 0 = next.
   *  This is why a deferred cost can sit still while stock is consumed. */
  quantityAheadInQueue?: number | null
}

/**
 * One consumption that drew on a purchase lot.
 *
 * The poultry twin carries flockId/flockName and a feed-production batch. Water
 * has neither: a draw belongs to a water production batch, or to one of the
 * other non-sale reductions (internal use, loss), which the server names in
 * sourceType/sourceLabel rather than in a column per source.
 */
export interface WaterDeferredRecognition {
  waterRawMaterialUsageId: number
  usedDate: string
  /** ProductionBatch | InternalUse | LossRecord | ... — server vocabulary. */
  sourceType?: string | null
  /** Ready-made label, built server-side so the UI never assembles one. */
  sourceLabel?: string | null
  waterProductionBatchId?: number | null
  batchNumber?: string | null
  productName?: string | null

  itemName?: string | null
  productionUnit?: string | null
  quantityDrawn: number
  unitCostAtDraw: number
  operationalCost: number
  /** THIS allocation's share. Zero on a lot expensed at purchase. */
  recognizedCost: number
  recognitionOutcome?: string | null

  isReversed: boolean
  reversedAt?: string | null
  waterExpenseId?: number | null
  /** The whole record's expense, NOT this row's share. See recognizedCost. */
  expenseAmount?: number | null
  expenseStatus?: string | null
}

/**
 * One cost layer a consumption drew from.
 *
 * Keyed on the PRODUCTION BATCH rather than the usage row, for the same reason
 * the poultry twin keys on the production record: editing a batch rewrites its
 * usage rows, so a usage id is not a stable handle to "this consumption".
 */
export interface WaterConsumptionCostLayer {
  waterRawMaterialUsageId: number
  waterRawMaterialItemId: number
  itemName?: string | null
  category?: string | null
  usedDate: string
  totalQuantityUsed: number
  productionUnit?: string | null

  waterRawMaterialPurchaseId: number
  purchaseDate: string
  supplierName?: string | null

  quantityDrawn: number
  unitCostAtDraw: number
  operationalCost: number
  recognizedCost: number
  /** The LOT's snapshot, not the item's current setting. */
  lotRecognitionMethod?: string | null
  recognitionLabel?: string | null
  isReversed: boolean
}

export interface WaterDeferredCostSummary {
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
  /** Lots that cannot be reached yet because older stock is in front. */
  blockedPurchases: number
  blockedCost: number
}

export interface WaterDeferredCostResponse {
  summary: WaterDeferredCostSummary
  purchases: WaterDeferredPurchase[]
}

export interface WaterDeferredCostFilters {
  scope?: WaterDeferredCostScope
  itemId?: number
  supplierId?: number
  category?: string
  fromDate?: string
  toDate?: string
  search?: string
}

// ----- Helpers -----

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

export const getWaterDeferredCosts = (f?: WaterDeferredCostFilters) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  qs.append("scope", f?.scope ?? "DEFERRED")
  if (f?.itemId != null) qs.append("itemId", String(f.itemId))
  if (f?.supplierId != null) qs.append("supplierId", String(f.supplierId))
  if (f?.category) qs.append("category", f.category)
  if (f?.fromDate) qs.append("fromDate", f.fromDate)
  if (f?.toDate) qs.append("toDate", f.toDate)
  if (f?.search) qs.append("search", f.search)
  return jget<WaterDeferredCostResponse>(`/Water/deferred-inventory-costs?${qs.toString()}`)
}

/** Every usage that drew on one purchase lot. Empty means nothing has drawn yet. */
export const getWaterDeferredCostHistory = (purchaseId: number) =>
  jget<WaterDeferredRecognition[]>(
    `/Water/deferred-inventory-costs/${purchaseId}/history?farmId=${encodeURIComponent(activeFarmId())}`)

/** How one production batch's raw-material cost was arrived at, lot by lot. */
export const getWaterConsumptionCostBreakdown = (productionBatchId: number) =>
  jget<WaterConsumptionCostLayer[]>(
    `/Water/deferred-inventory-costs/breakdown/${productionBatchId}?farmId=${encodeURIComponent(activeFarmId())}`)
