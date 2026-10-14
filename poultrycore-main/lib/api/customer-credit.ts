// Customer credit and refunds (migration 351, poultry).
//
// Credit is money the business RECEIVED and still holds for a customer, with
// no active sale to apply it to -- typically a payment kept when its sale was
// reversed. It is derived on the server (payment - active allocations -
// refunds); nothing here computes it.
//
//   apply   an ALLOCATION only: no new payment, no Money In, no cash movement
//   refund  real Money Out from the account the business chooses; no stock moves

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"

export interface CustomerCreditSummaryRow {
  customerId: number
  customerName: string
  availableCredit: number
  paymentCount: number
  /** What the customer still owes on active sales -- shown beside the credit, never netted. */
  outstanding: number
}

export interface CustomerCreditRow {
  poultryPaymentId: number
  paymentGroupId: string | null
  paymentNumber: string | null
  paymentDate: string | null
  amount: number
  unapplied: number
  sourceType: string | null
  saleId: number
  saleStatus: string | null
  poultryCashAccountId: number | null
}

export interface CustomerRefundRow {
  refundId: number
  refundNumber: string
  customerId: number
  customerName: string | null
  amount: number
  refundDate: string
  poultryCashAccountId: number
  accountName: string | null
  paymentMethod: string | null
  reason: string
  status: string
  createdBy: string | null
  createdAt: string
  paymentNumbers: string | null
}

function farm(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

async function call<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders(), ...init })
  const text = await res.text().catch(() => "")
  let data: any = null
  try { data = text ? JSON.parse(text) : null } catch { data = text }
  if (!res.ok) throw new Error((data && data.message) || (typeof data === "string" && data) || `Request failed (${res.status})`)
  return data as T
}

export function listCustomerCredit(): Promise<CustomerCreditSummaryRow[]> {
  return call(`Poultry/customer-payments/credit?farmId=${encodeURIComponent(farm())}`)
}

export function getCustomerCredit(customerId: number): Promise<CustomerCreditRow[]> {
  return call(`Poultry/customer-payments/credit/${customerId}?farmId=${encodeURIComponent(farm())}`)
}

/** Total credit a customer holds (0 when none). */
export async function customerCreditTotal(customerId: number): Promise<number> {
  const rows = await getCustomerCredit(customerId)
  return Math.round(rows.reduce((t, r) => t + (Number(r.unapplied) || 0), 0) * 100) / 100
}

export function applyCustomerCredit(customerId: number, saleId: number, amount: number): Promise<{ applied: number }> {
  const farmId = farm()
  return call(`Poultry/customer-payments/apply-credit?farmId=${encodeURIComponent(farmId)}`, {
    method: "POST",
    body: JSON.stringify({ farmId, customerId, saleId, amount }),
  })
}

export interface CustomerRefundInput {
  customerId: number
  amount: number
  poultryCashAccountId: number
  paymentMethod?: string | null
  refundDate?: string | null
  reason: string
}

export function recordCustomerRefund(input: CustomerRefundInput): Promise<{ refundId: number }> {
  const farmId = farm()
  return call(`Poultry/customer-payments/refunds?farmId=${encodeURIComponent(farmId)}`, {
    method: "POST",
    body: JSON.stringify({ ...input, farmId }),
  })
}

export function listCustomerRefunds(customerId?: number): Promise<CustomerRefundRow[]> {
  const q = new URLSearchParams({ farmId: farm() })
  if (customerId) q.set("customerId", String(customerId))
  return call(`Poultry/customer-payments/refunds?${q.toString()}`)
}

// ------------------------------------------------------------- 363 manual credit
// Credit created by hand, owner / admin only. Each kind says where the money
// came from -- there is no "set the balance":
//   OpeningCredit  held before the farm used the system. No cash, no P&L.
//   Deposit        paid in advance, no sale yet. Real cash in to an account.
//   CreditNote     goodwill credit. No cash; a cost on Profit & Loss.

export type ManualCreditKind = "OpeningCredit" | "Deposit" | "CreditNote"

export const MANUAL_CREDIT_KIND_LABEL: Record<ManualCreditKind, string> = {
  OpeningCredit: "Opening balance",
  Deposit: "Deposit",
  CreditNote: "Credit note",
}

export interface ManualCreditInput {
  customerId: number
  kind: ManualCreditKind
  amount: number
  creditDate?: string | null
  /** Deposit only. */
  poultryCashAccountId?: number | null
  paymentMethod?: string | null
  reference?: string | null
  reason: string
}

export interface ManualCreditRow {
  paymentGroupId: string
  poultryPaymentId: number
  paymentNumber: string | null
  kind: ManualCreditKind
  creditDate: string | null
  customerId: number
  customerName: string | null
  amount: number
  /** Applied to sales. */
  used: number
  refunded: number
  /** Still held for the customer. */
  remaining: number
  status: string
  poultryCashAccountId: number | null
  cashAccountName: string | null
  paymentMethod: string | null
  reference: string | null
  reason: string | null
  createdBy: string | null
  createdAt: string | null
  reversedAt: string | null
  reversalReason: string | null
}

export function listManualCredits(): Promise<ManualCreditRow[]> {
  return call(`Poultry/customer-payments/credit/manual?farmId=${encodeURIComponent(farm())}`)
}

export function createManualCredit(input: ManualCreditInput): Promise<{ paymentGroupId: string; paymentNumber: string | null }> {
  const farmId = farm()
  return call(`Poultry/customer-payments/credit/manual?farmId=${encodeURIComponent(farmId)}`, {
    method: "POST",
    body: JSON.stringify({ ...input, farmId }),
  })
}

export function reverseManualCredit(paymentGroupId: string, reason: string): Promise<{ reversed: number }> {
  const farmId = farm()
  return call(`Poultry/customer-payments/credit/manual/${encodeURIComponent(paymentGroupId)}/reverse?farmId=${encodeURIComponent(farmId)}`, {
    method: "POST",
    body: JSON.stringify({ farmId, reason }),
  })
}
