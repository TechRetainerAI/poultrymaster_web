import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { forceReauth } from "./session-expiry"

// Poultry inventory + raw materials API wrappers (mirror lib/api/water.ts).
// Additive: new module; existing poultry API wrappers untouched. Calls hit
// /Poultry/* on the Farm API via the same-origin proxy.

// ----- Types -----
// Which purchase batch gets drawn from first when an item is consumed.
export type RawMaterialUsageMethod = "FIFO" | "LIFO" | "HIFO"

export interface PoultryRawMaterialItem {
  poultryRawMaterialItemId: number
  farmId: string
  itemName: string
  category: string
  unitOfMeasure?: string | null
  /** How the item is BOUGHT (e.g. "bag"); production/stock uses unitOfMeasure. */
  purchaseUnitOfMeasure?: string | null
  minimumStockAlert: number
  currentQuantity: number
  isActive: boolean
  isLowStock?: boolean
  notes?: string | null
  usageMethod: RawMaterialUsageMethod
  createdAt: string
  updatedAt?: string | null
}

export interface PoultryRawMaterialItemInput {
  itemName: string
  category: string
  unitOfMeasure?: string | null
  purchaseUnitOfMeasure?: string | null
  minimumStockAlert?: number
  isActive?: boolean
  notes?: string | null
  usageMethod?: RawMaterialUsageMethod
}

export interface PoultryRawMaterialPurchase {
  poultryRawMaterialPurchaseId: number
  farmId: string
  poultryRawMaterialItemId: number
  itemName?: string | null
  category?: string | null
  unitOfMeasure?: string | null
  supplierName?: string | null
  supplierId?: number | null
  purchaseDate: string
  quantity: number
  unitCost: number
  totalCost: number
  /** How much of this batch hasn't been consumed yet (drives FIFO/LIFO/HIFO draws). */
  remainingQuantity: number
  productionUnit?: string | null
  productionUnitsPerPurchaseUnit?: number | null
  productionQuantity?: number | null
  productionUnitCost?: number | null
  paymentMethod?: string | null
  poultryCashAccountId?: number | null
  amountPaid: number
  balance: number
  receiptUrl?: string | null
  notes?: string | null
  createdBy?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface PoultryRawMaterialPurchaseInput {
  poultryRawMaterialItemId: number
  supplierName?: string | null
  supplierId?: number | null
  purchaseDate?: string
  quantity: number
  unitCost: number
  totalCost?: number
  productionUnit?: string | null
  productionUnitsPerPurchaseUnit?: number | null
  paymentMethod?: string | null
  poultryCashAccountId?: number | null
  amountPaid?: number
  receiptUrl?: string | null
  notes?: string | null
}

export interface PoultryRawMaterialUsage {
  poultryRawMaterialUsageId: number
  farmId: string
  poultryRawMaterialItemId: number
  itemName?: string | null
  unitOfMeasure?: string | null
  poultryProductionBatchId?: number | null
  usedDate: string
  quantityUsed: number
  expectedQuantityUsed?: number | null
  variance: number
  varianceReason?: string | null
  notes?: string | null
  createdAt: string
}

// ----- Helpers -----
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
    throw new Error(`GET ${path} failed (${res.status}): ${t || res.statusText}`)
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
    throw new Error(`${method} ${path} failed (${res.status}): ${t || res.statusText}`)
  }
  if (res.status === 204) return undefined as unknown as T
  const text = await res.text()
  return text ? (JSON.parse(text) as T) : (undefined as unknown as T)
}

// ----- Raw material items -----
export const listPoultryRawMaterialItems = () =>
  jget<PoultryRawMaterialItem[]>(`/Poultry/raw-material-items?farmId=${encodeURIComponent(activeFarmId())}`)

export const createPoultryRawMaterialItem = (input: PoultryRawMaterialItemInput) =>
  jsend<PoultryRawMaterialItem>(`/Poultry/raw-material-items`, "POST", { ...input, farmId: activeFarmId() })

export const updatePoultryRawMaterialItem = (id: number, input: PoultryRawMaterialItemInput) =>
  jsend<void>(`/Poultry/raw-material-items/${id}`, "PUT", { ...input, poultryRawMaterialItemId: id, farmId: activeFarmId() })

export const deletePoultryRawMaterialItem = (id: number) =>
  jsend<void>(`/Poultry/raw-material-items/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ----- Raw material purchases -----
export const listPoultryRawMaterialPurchases = (opts?: { fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<PoultryRawMaterialPurchase[]>(`/Poultry/raw-material-purchases?${qs.toString()}`)
}

export const createPoultryRawMaterialPurchase = (input: PoultryRawMaterialPurchaseInput) =>
  jsend<{ poultryRawMaterialPurchaseId: number }>(`/Poultry/raw-material-purchases`, "POST", { ...input, farmId: activeFarmId(), createdBy: activeUserId() })

export const updatePoultryRawMaterialPurchase = (id: number, input: PoultryRawMaterialPurchaseInput) =>
  jsend<void>(`/Poultry/raw-material-purchases/${id}`, "PUT", { ...input, poultryRawMaterialPurchaseId: id, farmId: activeFarmId() })

export const deletePoultryRawMaterialPurchase = (id: number) =>
  jsend<void>(`/Poultry/raw-material-purchases/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

export const payPoultryRawMaterialPurchaseBalance = (
  id: number,
  input: { amount: number; paymentMethod?: string; paymentDate?: string },
) =>
  jsend<{ balance: number }>(`/Poultry/raw-material-purchases/${id}/pay-balance`, "POST", {
    farmId: activeFarmId(),
    amount: input.amount,
    paymentMethod: input.paymentMethod ?? "Cash",
    paymentDate: input.paymentDate || null,
    createdBy: activeUserId(),
  })

// ----- Usage history -----
export const listPoultryRawMaterialUsageHistory = (opts?: { itemId?: number; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.itemId) qs.append("itemId", String(opts.itemId))
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<PoultryRawMaterialUsage[]>(`/Poultry/raw-material-usage/history?${qs.toString()}`)
}

// ----- Manual adjustments (increase/decrease a raw material / supply directly) -----
export interface PoultryRawMaterialAdjustment {
  poultryRawMaterialAdjustmentId: number
  farmId: string
  poultryRawMaterialItemId: number
  itemName?: string | null
  category?: string | null
  unitOfMeasure?: string | null
  adjustedDate: string
  quantity: number            // signed: + increase, - decrease
  unitCost?: number | null
  movementType?: string | null
  note?: string | null
  createdBy?: string | null
  createdAt: string
}

export const listPoultryRawMaterialAdjustments = (opts?: { fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<PoultryRawMaterialAdjustment[]>(`/Poultry/raw-material-adjustments?${qs.toString()}`)
}

// quantity is a SIGNED delta (positive increases stock, negative decreases it).
export const adjustPoultryRawMaterialItem = (
  itemId: number,
  input: { quantity: number; unitCost?: number | null; movementType?: string; note?: string | null },
) =>
  jsend<{ currentQuantity: number }>(`/Poultry/raw-material-items/${itemId}/adjust`, "POST", {
    ...input, farmId: activeFarmId(), createdBy: activeUserId(),
  })

// Recompute raw-material CurrentQuantity from purchases, usage and adjustments.
// Omit itemId to recalculate every raw material / supply for the active company.
export interface PoultryRawMaterialRecalcRow {
  poultryRawMaterialItemId: number
  itemName?: string | null
  category?: string | null
  unitOfMeasure?: string | null
  oldQuantity: number
  newQuantity: number
  delta: number
}

export const recalculatePoultryRawMaterialStock = (itemId?: number) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (itemId) qs.append("itemId", String(itemId))
  // Send an empty body so a Content-Length is always set — a bodyless POST can
  // 411 (Length Required) when relayed through the same-origin proxy's fetch.
  return jsend<PoultryRawMaterialRecalcRow[]>(`/Poultry/raw-material-items/recalculate-stock?${qs.toString()}`, "POST", {})
}

// ===================== Products + Stock (slice 2) =====================
export interface PoultryProduct {
  poultryProductId: number
  farmId: string
  name: string
  sku?: string | null
  unit?: string | null
  unitPrice: number
  productType: string
  isActive: boolean
  notes?: string | null
  isRawEggProduct: boolean
  requiresRecipeSetup: boolean
  isBirdProduct?: boolean
  size?: string | null
  stockOnHand: number
  createdDate: string
  updatedDate?: string | null
}
export interface PoultryProductInput {
  name: string; sku?: string | null; unit?: string | null; unitPrice?: number; productType?: string; isActive?: boolean; notes?: string | null
  isRawEggProduct?: boolean; requiresRecipeSetup?: boolean; size?: string | null
}
export const ensureDefaultPoultryEgg = () =>
  jsend<{ poultryProductId: number }>(`/Poultry/products/ensure-default-egg?farmId=${encodeURIComponent(activeFarmId())}`, "POST")
// Ensure both default products (Eggs + Birds) — doc 2.
export const ensurePoultryDefaults = () =>
  jsend<{ eggProductId: number; birdsProductId: number }>(`/Poultry/products/ensure-defaults?farmId=${encodeURIComponent(activeFarmId())}`, "POST")
export interface PoultryStockTransaction {
  poultryStockTransactionId: number; farmId: string; poultryProductId: number; productName?: string | null
  txnType: string; quantity: number; unitCost?: number | null; relatedId?: number | null; note?: string | null; createdDate: string
}

export const listPoultryProducts = () =>
  jget<PoultryProduct[]>(`/Poultry/products?farmId=${encodeURIComponent(activeFarmId())}`)
export const createPoultryProduct = (input: PoultryProductInput) =>
  jsend<PoultryProduct>(`/Poultry/products`, "POST", { ...input, farmId: activeFarmId() })
export const updatePoultryProduct = (id: number, input: PoultryProductInput) =>
  jsend<void>(`/Poultry/products/${id}`, "PUT", { ...input, poultryProductId: id, farmId: activeFarmId() })
export const deletePoultryProduct = (id: number) =>
  jsend<void>(`/Poultry/products/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

export const listPoultryStockTransactions = (productId?: number) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (productId) qs.append("productId", String(productId))
  return jget<PoultryStockTransaction[]>(`/Poultry/stock/transactions?${qs.toString()}`)
}
export const addPoultryStockTransaction = (input: { poultryProductId: number; txnType: string; quantity: number; unitCost?: number | null; note?: string | null }) =>
  jsend<{ poultryStockTransactionId: number }>(`/Poultry/stock/transactions`, "POST", { ...input, farmId: activeFarmId() })

// ===================== Recipes (slice 3) =====================
export interface PoultryRecipeItem {
  poultryProductionRecipeItemId?: number
  poultryRawMaterialItemId: number
  itemName?: string | null
  unitOfMeasure?: string | null
  availableStock?: number
  latestUnitCost?: number
  quantityPerOutputUnit: number
  wasteAllowancePercent: number
  isOptional: boolean
  displayOrder: number
  notes?: string | null
}
export interface PoultryRecipe {
  poultryProductionRecipeId: number
  farmId: string
  poultryProductId: number
  recipeName?: string | null
  isActive: boolean
  notes?: string | null
  items: PoultryRecipeItem[]
}
export const getPoultryRecipe = (productId: number) =>
  jget<PoultryRecipe | null>(`/Poultry/products/${productId}/recipe?farmId=${encodeURIComponent(activeFarmId())}`)
export const upsertPoultryRecipe = (productId: number, input: { recipeName?: string | null; notes?: string | null; items: PoultryRecipeItem[] }) =>
  jsend<{ poultryProductionRecipeId: number }>(`/Poultry/products/${productId}/recipe`, "PUT", { ...input, farmId: activeFarmId() })

// ===================== Production batches (slice 4) =====================
export interface PoultryMaterialUsageInput {
  poultryRawMaterialItemId: number; quantityUsed: number; expectedQuantityUsed?: number | null; unitCost?: number | null
}
export interface PoultryProductionBatch {
  poultryProductionBatchId: number; farmId: string; batchNumber: string; productionDate: string
  poultryProductId: number; productName?: string | null; quantityProduced: number; unit?: string | null
  damagedQuantity: number; laborCost: number; otherCost: number; materialsCost: number; totalCost: number; costPerUnit: number
  status: string; notes?: string | null; approvedBy?: string | null; approvedAt?: string | null; createdAt: string
}
export interface PoultryProductionBatchInput {
  batchNumber: string; productionDate?: string; poultryProductId: number; quantityProduced: number; unit?: string | null
  damagedQuantity?: number; laborCost?: number; otherCost?: number; notes?: string | null; materialsUsed: PoultryMaterialUsageInput[]
}
export const listPoultryProductionBatches = (opts?: { status?: string; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status) qs.append("status", opts.status)
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<PoultryProductionBatch[]>(`/Poultry/production-batches?${qs.toString()}`)
}
export const getPoultryBatchMaterials = (id: number) =>
  jget<PoultryMaterialUsageInput[]>(`/Poultry/production-batches/${id}/materials?farmId=${encodeURIComponent(activeFarmId())}`)
export const createPoultryProductionBatch = (input: PoultryProductionBatchInput) =>
  jsend<{ poultryProductionBatchId: number }>(`/Poultry/production-batches`, "POST", { ...input, farmId: activeFarmId() })
export const updatePoultryProductionBatch = (id: number, input: PoultryProductionBatchInput) =>
  jsend<void>(`/Poultry/production-batches/${id}`, "PUT", { ...input, poultryProductionBatchId: id, farmId: activeFarmId() })
export const approvePoultryProductionBatch = (id: number) =>
  jsend<void>(`/Poultry/production-batches/${id}/approve?farmId=${encodeURIComponent(activeFarmId())}`, "POST")
export const cancelPoultryProductionBatch = (id: number) =>
  jsend<void>(`/Poultry/production-batches/${id}/cancel?farmId=${encodeURIComponent(activeFarmId())}`, "POST")

// ===================== Losses (slice 5) =====================
export interface PoultryProductionLoss {
  poultryProductionLossId: number; farmId: string; sourceType: string; sourceId?: number | null; lossDate: string
  poultryProductId?: number | null; productName?: string | null; quantityLost: number; estimatedValue?: number | null; reason?: string | null
}
export interface PoultryLossRecord {
  poultryLossRecordId: number; farmId: string; lossDate: string; lossType: string
  poultryProductId?: number | null; productName?: string | null; quantity?: number | null; estimatedValue?: number | null
  reason?: string | null; status: string; approvedBy?: string | null; notes?: string | null
}
export interface PoultryLossRecordInput {
  lossDate?: string; lossType: string; poultryProductId?: number | null; quantity?: number | null; estimatedValue?: number | null; reason?: string | null; notes?: string | null
}
export const listPoultryProductionLosses = (opts?: { fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<PoultryProductionLoss[]>(`/Poultry/production-losses?${qs.toString()}`)
}
export const listPoultryLossRecords = (opts?: { lossType?: string; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.lossType) qs.append("lossType", opts.lossType)
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<PoultryLossRecord[]>(`/Poultry/loss-records?${qs.toString()}`)
}
export const createPoultryLossRecord = (input: PoultryLossRecordInput) =>
  jsend<{ poultryLossRecordId: number }>(`/Poultry/loss-records`, "POST", { ...input, farmId: activeFarmId() })
export const updatePoultryLossRecord = (id: number, input: PoultryLossRecordInput) =>
  jsend<void>(`/Poultry/loss-records/${id}`, "PUT", { ...input, poultryLossRecordId: id, farmId: activeFarmId() })
export const approvePoultryLossRecord = (id: number) =>
  jsend<void>(`/Poultry/loss-records/${id}/approve?farmId=${encodeURIComponent(activeFarmId())}`, "POST")
export const unapprovePoultryLossRecord = (id: number) =>
  jsend<void>(`/Poultry/loss-records/${id}/unapprove?farmId=${encodeURIComponent(activeFarmId())}`, "POST")
export const deletePoultryLossRecord = (id: number) =>
  jsend<void>(`/Poultry/loss-records/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")

// ===================== Daily closing (slice 6) =====================
export interface PoultryDailyClosing {
  poultryDailyClosingId: number; farmId: string; closingDate: string
  quantityProduced: number; quantityDamaged: number; totalProductionCost: number; closingStock: number
  cashAtHand: number; actualCashCounted: number; cashDifference: number; managerNotes?: string | null
  status: string; rejectionReason?: string | null; submittedAt?: string | null; approvedAt?: string | null
  // Enriched live figures (migration 148)
  eggsSold?: number; eggsReturned?: number; mortality?: number; feedUsedQty?: number; medUsedQty?: number
  totalIncome?: number; totalExpenses?: number; creditSales?: number; customerCollections?: number
  cashCollected?: number; moMoCollected?: number; bankCollected?: number
  cashBalance?: number; moMoBalance?: number; bankBalance?: number
}
export const listPoultryDailyClosings = (opts?: { status?: string; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status) qs.append("status", opts.status)
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<PoultryDailyClosing[]>(`/Poultry/daily-closings?${qs.toString()}`)
}
export const getPoultryDailyClosing = (id: number) =>
  jget<PoultryDailyClosing>(`/Poultry/daily-closings/${id}?farmId=${encodeURIComponent(activeFarmId())}`)
export const createPoultryDailyClosing = (input: { closingDate: string; managerNotes?: string | null }) =>
  jsend<{ poultryDailyClosingId: number }>(`/Poultry/daily-closings`, "POST", { ...input, farmId: activeFarmId() })
export const submitPoultryDailyClosing = (id: number, input: { actualCashCounted: number; managerNotes?: string | null }) =>
  jsend<void>(`/Poultry/daily-closings/${id}/submit`, "POST", { ...input, farmId: activeFarmId() })
export const approvePoultryDailyClosing = (id: number) =>
  jsend<void>(`/Poultry/daily-closings/${id}/approve?farmId=${encodeURIComponent(activeFarmId())}`, "POST")
export const rejectPoultryDailyClosing = (id: number, reason: string) =>
  jsend<void>(`/Poultry/daily-closings/${id}/reject?farmId=${encodeURIComponent(activeFarmId())}&reason=${encodeURIComponent(reason)}`, "POST")
export const deletePoultryDailyClosing = (id: number) =>
  jsend<void>(`/Poultry/daily-closings/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE")
export const reopenPoultryDailyClosing = (id: number) =>
  jsend<void>(`/Poultry/daily-closings/${id}/reopen?farmId=${encodeURIComponent(activeFarmId())}`, "POST")
export const recreatePoultryDailyClosing = (id: number) =>
  jsend<void>(`/Poultry/daily-closings/${id}/recreate?farmId=${encodeURIComponent(activeFarmId())}`, "POST")
export const savePoultryDailyClosingNotes = (id: number, input: { actualCashCounted?: number; managerNotes?: string | null }) =>
  jsend<void>(`/Poultry/daily-closings/${id}/notes`, "POST", { ...input, farmId: activeFarmId() })

// ===================== Closing report (doc 6) =====================
export const getPoultryClosingReport = (fromDate: string, toDate: string) =>
  jget<Record<string, any>>(`/Poultry/closing-report?farmId=${encodeURIComponent(activeFarmId())}&fromDate=${fromDate}&toDate=${toDate}`)

// ===================== Delivery (doc 9) =====================
export interface PoultryDelivery {
  poultryDeliveryId: number; farmId: string; deliveryDate: string
  driverName?: string | null; vehicleName?: string | null; route?: string | null
  poultryProductId: number; productName?: string | null
  quantityLoaded: number; unit?: string | null; unitPrice: number
  quantitySold: number; quantityReturned: number; quantityBroken: number; quantityShort: number
  cashCollected: number; creditSales: number; deliveryExpenses: number; totalSales: number; cashVariance: number
  status: string; notes?: string | null; reconciledAt?: string | null
}
export const listPoultryDeliveries = (opts?: { status?: string; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.status) qs.append("status", opts.status)
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<PoultryDelivery[]>(`/Poultry/deliveries?${qs.toString()}`)
}
export const loadPoultryDelivery = (input: { poultryProductId: number; quantityLoaded: number; unit?: string | null; unitPrice?: number; driverName?: string | null; vehicleName?: string | null; route?: string | null; deliveryDate?: string | null; notes?: string | null }) =>
  jsend<{ poultryDeliveryId: number }>(`/Poultry/deliveries/load`, "POST", { ...input, farmId: activeFarmId(), createdBy: activeUserId() })
export const reconcilePoultryDelivery = (id: number, input: { quantitySold: number; quantityReturned: number; quantityBroken?: number; quantityShort?: number; cashCollected?: number; creditSales?: number; deliveryExpenses?: number; paymentMethod?: string }) =>
  jsend<void>(`/Poultry/deliveries/${id}/reconcile`, "POST", { ...input, farmId: activeFarmId(), reconciledBy: activeUserId() })
export const reversePoultryDelivery = (id: number) =>
  jsend<void>(`/Poultry/deliveries/${id}/reverse?farmId=${encodeURIComponent(activeFarmId())}`, "POST")
export const cancelPoultryDelivery = (id: number) =>
  jsend<void>(`/Poultry/deliveries/${id}/cancel?farmId=${encodeURIComponent(activeFarmId())}`, "POST")
