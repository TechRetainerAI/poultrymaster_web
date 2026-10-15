// Customer debt (migration 369, poultry).
//
// What a customer owes WITHOUT a sale: owed from before the farm used the
// system, a historical or external transaction, a migration, an adjustment.
// The user records the event; what is still owed is derived on the server
// (amount - payments applied). No sale, no revenue, no stock, no cash.
//
// It is paid like a sale -- Receive payment on Customer Balances lists it among
// the customer's open items. Reversing is refused while anything is paid on it.
// Recording and reversing are owner / admin only.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"

export type CustomerDebtEntryType =
  | "OpeningBalance" | "HistoricalDebt" | "Adjustment" | "Migration" | "ExternalTransaction" | "Other"

export const CUSTOMER_DEBT_ENTRY_LABEL: Record<CustomerDebtEntryType, string> = {
  OpeningBalance: "Opening balance",
  HistoricalDebt: "Historical sale / debt",
  Adjustment: "Adjustment",
  Migration: "Migration",
  ExternalTransaction: "External transaction",
  Other: "Other",
}

export interface CustomerDebtRow {
  debtId: number
  debtNumber: string
  customerId: number
  customerName: string | null
  amount: number
  paid: number
  /** Still owed. */
  balance: number
  debtDate: string | null
  entryType: CustomerDebtEntryType
  description: string
  reference: string | null
  notes: string | null
  status: "Posted" | "Reversed" | string
  createdBy: string | null
  createdAt: string | null
  reversedBy: string | null
  reversedAt: string | null
  reversalReason: string | null
}

export interface CustomerDebtInput {
  customerId: number
  amount: number
  debtDate: string
  entryType: CustomerDebtEntryType
  description: string
  reference?: string | null
  notes?: string | null
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

export function listCustomerDebts(customerId?: number): Promise<CustomerDebtRow[]> {
  const q = new URLSearchParams({ farmId: farm() })
  if (customerId) q.set("customerId", String(customerId))
  return call(`Poultry/customer-debts?${q.toString()}`)
}

export function createCustomerDebt(input: CustomerDebtInput): Promise<{ debtId: number; debtNumber: string }> {
  const farmId = farm()
  return call(`Poultry/customer-debts?farmId=${encodeURIComponent(farmId)}`, {
    method: "POST",
    body: JSON.stringify({ ...input, farmId }),
  })
}

export function reverseCustomerDebt(debtId: number, reason: string): Promise<{ debtId: number }> {
  const farmId = farm()
  return call(`Poultry/customer-debts/${debtId}/reverse?farmId=${encodeURIComponent(farmId)}`, {
    method: "POST",
    body: JSON.stringify({ farmId, reason }),
  })
}
