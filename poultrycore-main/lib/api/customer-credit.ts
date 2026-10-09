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
