// Inventory purchase reversal (migration 478 for Water) -- the sale reversal
// model applied to purchases. One shape for every module so the one
// ReversePurchaseDialog serves them; the server decides everything that matters
// and re-checks it on confirm, these only carry it.

import { farmApiUrl, getAuthHeaders } from "./config"
import type { ApiResponse } from "./sale"

export type PurchaseModule = "water" | "poultry"

/** What happens to one money line: the supplier gave it back, or it stays with them as credit. */
export type PurchaseMoneyAction = "Refund" | "KeepAsCredit"

export interface PurchaseMoneyLine {
  /** "entry" (paid when the purchase was entered) or "sp:{paymentId}" */
  key: string
  source: "PaidAtEntry" | "SupplierPayment"
  paymentId: number | null
  paymentNumbers: string
  allocated: number
  paymentDate: string | null
  paymentMethod: string | null
  cashAccountId: number | null
  cashAccountName: string | null
  allowed: PurchaseMoneyAction[]
  default: PurchaseMoneyAction
  /** Why "keep as credit" is not offered (no supplier on the purchase). */
  keepUnavailableReason: string | null
  /** Why a refund is not offered (Poultry: the payment also paid other items). */
  refundUnavailableReason?: string | null
  /** The money never went through a cash account, so a refund puts nothing back into one. */
  noCashNote: string | null
}

export interface PurchaseReversalPreview {
  found: boolean
  purchaseId: number
  purchaseDate: string
  itemName: string
  unit: string | null
  quantity: number
  /** Production units taken back out of stock. */
  stockToRemove: number
  supplierId: number | null
  supplierName: string
  total: number
  paid: number
  /** Supplier credit spent on the purchase -- always goes back to the supplier. */
  creditApplied: number
  outstanding: number
  deferred: boolean
  payments: PurchaseMoneyLine[]
  supplierCreditNow: number
  blockers: { code: string; message: string }[]
  fingerprint: string
}

export interface PurchaseReversalRecord {
  purchaseReversalId: number
  reversalNumber: string
  purchaseId: number
  reasonCode: string | null
  reason: string
  occurredAt: string
  reversedBy: string | null
  paymentHandling: string
  total: number
  paid: number
  creditCreated: number
  creditReleased: number
  refunded: number
  stockRemoved: number
}

export interface ReversePurchaseInput {
  farmId: string
  userId?: string
  reasonCode: string
  reason: string
  paymentHandling: Record<string, PurchaseMoneyAction>
  expectedFingerprint: string
  idempotencyKey: string
}

async function readJson(response: Response): Promise<any> {
  const text = await response.text()
  try { return text ? JSON.parse(text) : null } catch { return text }
}

const base = (module: PurchaseModule, id: number) =>
  `${module === "water" ? "Water" : "Poultry"}/raw-material-purchases/${id}`

export async function getPurchaseReversalPreview(
  module: PurchaseModule, id: number, farmId: string,
): Promise<ApiResponse<PurchaseReversalPreview>> {
  try {
    const response = await fetch(farmApiUrl(`${base(module, id)}/reversal-preview?farmId=${encodeURIComponent(farmId)}`), {
      headers: getAuthHeaders(),
    })
    const data = await readJson(response)
    if (!response.ok) return { success: false, message: data?.message || "Could not work out what reversing this purchase would do." }
    return { success: true, data }
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : "Network error" }
  }
}

export async function getPurchaseReversal(
  module: PurchaseModule, id: number, farmId: string,
): Promise<ApiResponse<PurchaseReversalRecord>> {
  try {
    const response = await fetch(farmApiUrl(`${base(module, id)}/reversal?farmId=${encodeURIComponent(farmId)}`), {
      headers: getAuthHeaders(),
    })
    const data = await readJson(response)
    if (!response.ok) return { success: false, message: data?.message || "Reversal not found" }
    return { success: true, data }
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : "Network error" }
  }
}

/** stale: the purchase changed after the preview was shown -- reload it and confirm again. */
export async function reversePurchase(
  module: PurchaseModule, id: number, input: ReversePurchaseInput,
): Promise<ApiResponse<{ purchaseReversalId: number; reversal: PurchaseReversalRecord | null }> & { stale?: boolean }> {
  try {
    const response = await fetch(farmApiUrl(`${base(module, id)}/reverse?farmId=${encodeURIComponent(input.farmId)}`), {
      method: "POST",
      headers: getAuthHeaders(),
      body: JSON.stringify(input),
    })
    const data = await readJson(response)
    if (!response.ok) {
      return { success: false, stale: !!data?.stale, message: data?.message || (typeof data === "string" ? data : "The purchase was not reversed.") }
    }
    return { success: true, data }
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : "Network error" }
  }
}
