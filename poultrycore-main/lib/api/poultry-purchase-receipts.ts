import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

// Receive Purchase (migration 345): /Poultry/purchase-receipts on the Farm API.
// One call receives a whole supplier invoice -- stock, payable and any payment
// made on the spot -- so there is nothing to sequence on this side.

export type PurchaseReceiptStatus = "Posted" | "Reversed"
export type PurchaseReceiptPaymentStatus = "Paid" | "Part paid" | "Unpaid" | "Reversed"

export interface PurchaseReceiptLine {
  poultryPurchaseReceiptLineId: number
  lineNo: number
  poultryRawMaterialItemId: number
  itemName?: string | null
  category?: string | null
  unitOfMeasure?: string | null
  quantity: number
  /** Invoice price per purchase unit. */
  unitCost: number
  lineSubtotal: number
  allocatedAdditionalCost: number
  lineTotal: number
  /** What the cost layer holds per purchase unit, additional costs included. */
  landedUnitCost: number
  productionUnit?: string | null
  productionUnitsPerPurchaseUnit?: number | null
  productionQuantity: number
  notes?: string | null
  poultryRawMaterialPurchaseId: number
  costRecognitionMethod?: string | null
  /** "Expensed as paid" | "Expensed when used". */
  recognitionLabel?: string | null
  remainingQuantity: number
  consumedQuantity: number
  amountPaid: number
  balance: number
  deferredRemainingCost: number
  reversalAdjustmentId?: number | null
}

export interface PurchaseReceipt {
  poultryPurchaseReceiptId: number
  receiptNumber: string
  supplierId: number
  supplierName?: string | null
  purchaseDate: string
  referenceNo?: string | null
  dueDate?: string | null
  notes?: string | null
  subtotal: number
  additionalCosts: number
  additionalCostsNote?: string | null
  totalCost: number
  amountPaidAtReceipt: number
  /** Live: later supplier payments count, reversed ones do not. */
  amountPaid: number
  balance: number
  paymentStatus: PurchaseReceiptPaymentStatus
  isOverdue: boolean
  paymentMethod?: string | null
  poultryCashAccountId?: number | null
  cashAccountName?: string | null
  poultrySupplierPaymentId?: number | null
  status: PurchaseReceiptStatus
  lineCount: number
  itemSummary?: string | null
  expensedAtPurchaseCost: number
  deferredCost: number
  createdBy?: string | null
  createdAt: string
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
  /** Why it cannot be reversed right now; null when it can. */
  reversalBlocker?: string | null
  lines?: PurchaseReceiptLine[] | null
}

export interface ReceivePurchaseLineInput {
  poultryRawMaterialItemId: number
  quantity: number
  unitCost: number
  productionUnit?: string | null
  productionUnitsPerPurchaseUnit?: number | null
  notes?: string | null
}

export interface ReceivePurchaseInput {
  supplierId?: number | null
  supplierName?: string | null
  purchaseDate: string
  referenceNo?: string | null
  dueDate?: string | null
  notes?: string | null
  additionalCosts: number
  additionalCostsNote?: string | null
  amountPaid: number
  paymentMethod?: string | null
  cashAccountId?: number | null
  /** One per form: a repeated Save returns the first receipt. */
  clientRequestId: string
  lines: ReceivePurchaseLineInput[]
}

function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

async function call<T>(path: string, method: "GET" | "POST", body?: unknown): Promise<T> {
  const init: RequestInit = { method, headers: getAuthHeaders() }
  if (body !== undefined) init.body = JSON.stringify(body)
  const res = await fetch(farmApiUrl(path), init)
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(explainHttpError(method, path, res.status, t))
  }
  const text = await res.text()
  return text ? (JSON.parse(text) as T) : (undefined as unknown as T)
}

export function listPurchaseReceipts(opts?: { fromDate?: string; toDate?: string; status?: string }) {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  if (opts?.status && opts.status !== "All") qs.append("status", opts.status)
  return call<PurchaseReceipt[]>(`/Poultry/purchase-receipts?${qs.toString()}`, "GET")
}

export function getPurchaseReceipt(id: number) {
  return call<PurchaseReceipt>(`/Poultry/purchase-receipts/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "GET")
}

export function receivePurchase(input: ReceivePurchaseInput) {
  const farmId = activeFarmId()
  const { userId } = getUserContext()
  return call<PurchaseReceipt>(`/Poultry/purchase-receipts?farmId=${encodeURIComponent(farmId)}`, "POST", {
    ...input, farmId, createdBy: userId || null,
  })
}

export function reversePurchaseReceipt(id: number, reason: string) {
  const farmId = activeFarmId()
  const { userId } = getUserContext()
  return call<{ linesReversed: number; receipt: PurchaseReceipt }>(
    `/Poultry/purchase-receipts/${id}/reverse?farmId=${encodeURIComponent(farmId)}`, "POST",
    { farmId, reason, reversedBy: userId || null })
}

/** A fresh idempotency key for a new form. */
export function newClientRequestId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") return crypto.randomUUID()
  // RFC 4122 v4 from Math.random -- only for very old browsers.
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0
    return (c === "x" ? r : (r & 0x3) | 0x8).toString(16)
  })
}
