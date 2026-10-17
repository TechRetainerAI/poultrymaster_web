// Supplier credit, advances, refunds and debt (migration 370, poultry).
//
// Supplier credit is money the business paid (or a supplier owes it) that is
// not on any open purchase: an advance, the part of a payment not applied, or
// a credit added by hand (credit note, opening credit). It is derived on the
// server: a payment's amount - what is applied - what the supplier refunded.
//
//   apply   an ALLOCATION of the credit to a purchase / batch / bill / debt:
//           no new payment, no cash (the cash left with the advance)
//   refund  the supplier sends money back: real Money In to the account chosen
//
// Supplier debt is what the business already owes a supplier without a
// purchase here; it is paid like a purchase on Supplier Balances.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"

export interface SupplierCreditSummaryRow {
  supplierId: number
  supplierName: string
  availableCredit: number
  creditCount: number
  /** Still owed to the supplier -- shown beside the credit, never netted. */
  owed: number
}

export interface SupplierCreditEvent {
  poultrySupplierPaymentId: number
  creditNumber: string
  creditDate: string | null
  supplierId: number
  supplierName: string | null
  /** Supplier advance | Overpayment | Credit note | Opening credit | Manual credit */
  source: string
  sourceType: string | null
  reference: string | null
  notes: string | null
  originalAmount: number
  applied: number
  refunded: number
  available: number
  /** Available | Partly used | Used | Refunded */
  status: string
  /** An advance or a credit added by hand: reversed from Supplier Credits. */
  isManual: boolean
  poultryCashAccountId: number | null
  accountName: string | null
}

export interface SupplierCreditApplication {
  allocationId: number
  poultrySupplierPaymentId: number
  creditNumber: string
  supplierId: number
  supplierName: string | null
  documentType: string
  documentId: number
  reference: string | null
  label: string | null
  amount: number
  appliedDate: string | null
  status: string
  createdBy: string | null
  reversedAt: string | null
  reversalReason: string | null
}

export interface SupplierRefundRow {
  refundId: number
  refundNumber: string
  supplierId: number
  supplierName: string | null
  amount: number
  refundDate: string | null
  poultryCashAccountId: number
  accountName: string | null
  paymentMethod: string | null
  reason: string
  status: string
  createdBy: string | null
  createdAt: string | null
  creditNumbers: string | null
  reversedAt: string | null
  reversedBy: string | null
  reversalReason: string | null
  reversalDate: string | null
}

export type SupplierCreditKind = "SupplierCreditNote" | "SupplierOpeningCredit" | "SupplierManualCredit"

export const SUPPLIER_CREDIT_KIND_LABEL: Record<SupplierCreditKind, string> = {
  SupplierCreditNote: "Credit note",
  SupplierOpeningCredit: "Opening credit",
  SupplierManualCredit: "Manual credit",
}

export type SupplierDebtEntryType =
  | "OpeningBalance" | "HistoricalDebt" | "Adjustment" | "Migration" | "ExternalTransaction" | "Other"

export const SUPPLIER_DEBT_ENTRY_LABEL: Record<SupplierDebtEntryType, string> = {
  OpeningBalance: "Opening balance",
  HistoricalDebt: "Historical purchase / debt",
  Adjustment: "Adjustment",
  Migration: "Migration",
  ExternalTransaction: "External transaction",
  Other: "Other",
}

export interface SupplierDebtRow {
  debtId: number
  debtNumber: string
  supplierId: number
  supplierName: string | null
  amount: number
  paid: number
  balance: number
  debtDate: string | null
  entryType: SupplierDebtEntryType
  description: string
  reference: string | null
  notes: string | null
  status: string
  createdBy: string | null
  createdAt: string | null
  reversedBy: string | null
  reversedAt: string | null
  reversalReason: string | null
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

const q = (extra?: Record<string, string | number | null | undefined>) => {
  const p = new URLSearchParams({ farmId: farm() })
  for (const [k, v] of Object.entries(extra ?? {})) if (v != null && v !== "") p.set(k, String(v))
  return p.toString()
}

const post = <T,>(path: string, body: object) => {
  const farmId = farm()
  return call<T>(`${path}?farmId=${encodeURIComponent(farmId)}`, { method: "POST", body: JSON.stringify({ ...body, farmId }) })
}

export const listSupplierCredit = () => call<SupplierCreditSummaryRow[]>(`Poultry/supplier-credits?${q()}`)
export const listSupplierCreditEvents = (supplierId?: number) =>
  call<SupplierCreditEvent[]>(`Poultry/supplier-credits/events?${q({ supplierId })}`)
export const listSupplierCreditApplications = (supplierId?: number) =>
  call<SupplierCreditApplication[]>(`Poultry/supplier-credits/applications?${q({ supplierId })}`)
export const listSupplierRefunds = (supplierId?: number) =>
  call<SupplierRefundRow[]>(`Poultry/supplier-credits/refunds?${q({ supplierId })}`)

/** Total credit a supplier holds for the business (0 when none). */
export async function supplierCreditTotal(supplierId: number): Promise<number> {
  const rows = await listSupplierCreditEvents(supplierId)
  return Math.round(rows.reduce((t, r) => t + (Number(r.available) || 0), 0) * 100) / 100
}

export const createSupplierCredit = (input: {
  supplierId: number; kind: SupplierCreditKind; amount: number; creditDate?: string | null; reference?: string | null; reason: string
}) => post<{ paymentId: number }>("Poultry/supplier-credits/manual", input)

export const reverseSupplierCredit = (paymentId: number, reason: string) =>
  post<{ reversed: number }>(`Poultry/supplier-credits/${paymentId}/reverse`, { reason })

export const applySupplierCredit = (input: {
  poultrySupplierPaymentId: number; documentType: string; documentId: number; amount: number
}) => post<{ allocationId: number }>("Poultry/supplier-credits/apply", input)

export const unapplySupplierCredit = (allocationId: number, reason: string) =>
  post<{ allocationId: number }>(`Poultry/supplier-credits/applications/${allocationId}/reverse`, { reason })

export const recordSupplierRefund = (input: {
  poultrySupplierPaymentId: number; amount: number; poultryCashAccountId: number
  paymentMethod?: string | null; refundDate?: string | null; reason: string
}) => post<{ refundId: number }>("Poultry/supplier-credits/refunds", input)

export const reverseSupplierRefund = (refundId: number, reason: string) =>
  post<{ refundId: number }>(`Poultry/supplier-credits/refunds/${refundId}/reverse`, { reason })

export const listSupplierDebts = (supplierId?: number) => call<SupplierDebtRow[]>(`Poultry/supplier-debts?${q({ supplierId })}`)

export const createSupplierDebt = (input: {
  supplierId: number; amount: number; debtDate: string; entryType: SupplierDebtEntryType
  description: string; reference?: string | null; notes?: string | null
}) => post<{ debtId: number; debtNumber: string }>("Poultry/supplier-debts", input)

export const reverseSupplierDebt = (debtId: number, reason: string) =>
  post<{ debtId: number }>(`Poultry/supplier-debts/${debtId}/reverse`, { reason })
