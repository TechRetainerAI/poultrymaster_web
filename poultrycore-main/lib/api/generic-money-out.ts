// Generic Company money-out API client (migration 249).
//
// Recurring expenses, staff and contractor payments, and owner contributions
// and draws. Same fetch + buildApiUrl + getAuthHeaders pattern as the other
// lib/api/* modules; its own file so lib/api/generic.ts does not grow a fourth
// module.

import { buildApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"

// =============================================================================
// Types
// =============================================================================

export type RecurringFrequency =
  | "Weekly"
  | "Monthly"
  | "Quarterly"
  | "SemiAnnual"
  | "Annual"

export const RECURRING_FREQUENCIES: RecurringFrequency[] = [
  "Weekly",
  "Monthly",
  "Quarterly",
  "SemiAnnual",
  "Annual",
]

export const FREQUENCY_LABELS: Record<RecurringFrequency, string> = {
  Weekly: "Every week",
  Monthly: "Every month",
  Quarterly: "Every 3 months",
  SemiAnnual: "Every 6 months",
  Annual: "Every year",
}

export interface GenericRecurringExpense {
  genericRecurringExpenseId: number
  farmId: string
  expenseName: string
  genericExpenseCategoryId: number
  categoryName?: string | null
  genericSupplierId?: number | null
  supplierName?: string | null
  amount: number
  frequency: string
  startDate: string
  endDate?: string | null
  nextDueDate?: string | null
  lastGeneratedDate?: string | null
  paymentMethod?: string | null
  defaultCashAccountId?: number | null
  /** Mark the generated expense paid and move the cash, or raise it as a bill. */
  autoPayOnGenerate: boolean
  reminderEnabled: boolean
  /** Active | Paused | Cancelled | Expired. */
  status: string
  notes?: string | null
  /** Due on or before today, and still Active. */
  isDue: boolean
  generatedCount: number
  createdBy?: string | null
  createdAt?: string | null
}

export interface CreateRecurringExpenseInput {
  expenseName: string
  genericExpenseCategoryId: number
  amount: number
  frequency: RecurringFrequency | string
  startDate: string
  genericSupplierId?: number | null
  endDate?: string | null
  paymentMethod?: string | null
  defaultCashAccountId?: number | null
  autoPayOnGenerate?: boolean
  reminderEnabled?: boolean
  notes?: string | null
}

/** One line of "what generating now would raise". */
export interface RecurringExpensePreviewRow {
  genericRecurringExpenseId: number
  expenseName: string
  categoryName?: string | null
  supplierName?: string | null
  amount: number
  frequency: string
  periodStart: string
  periodEnd: string
  /** True when this period already exists, so generate will skip it. */
  alreadyGenerated: boolean
}

export interface GenericStaffPayment {
  genericStaffPaymentId: number
  genericStaffId: number
  staffName?: string | null
  staffRole?: string | null
  workerType?: string | null
  paymentDate: string
  periodStart?: string | null
  periodEnd?: string | null
  amount: number
  paymentMethod?: string | null
  genericCashAccountId?: number | null
  cashAccountName?: string | null
  /** The expense this payment booked, which is how it reaches the P&L. */
  genericExpenseId?: number | null
  categoryName?: string | null
  description?: string | null
  referenceNo?: string | null
  /** Posted | Reversed. */
  status: string
  createdBy?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface RecordStaffPaymentInput {
  genericStaffId: number
  amount: number
  paymentDate?: string | null
  paymentMethod?: string | null
  cashAccountId?: number | null
  genericExpenseCategoryId?: number | null
  periodStart?: string | null
  periodEnd?: string | null
  description?: string | null
  reference?: string | null
}

export type OwnerEntryType = "Contribution" | "Draw"

export interface GenericOwnerEntry {
  genericOwnerEntryId: number
  entryDate: string
  entryType: string
  amount: number
  genericCashAccountId?: number | null
  cashAccountName?: string | null
  paymentMethod?: string | null
  ownerName?: string | null
  referenceNo?: string | null
  notes?: string | null
  status: string
  createdBy?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface RecordOwnerEntryInput {
  entryType: OwnerEntryType
  amount: number
  /** Required — owner money always moves cash. */
  cashAccountId: number
  entryDate?: string | null
  paymentMethod?: string | null
  ownerName?: string | null
  reference?: string | null
  notes?: string | null
}

// =============================================================================
// Plumbing
// =============================================================================

function farmBase(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("Missing farmId in user context.")
  return `/generic-company/${encodeURIComponent(farmId)}`
}

function currentFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("Missing farmId in user context.")
  return farmId
}

async function getJson<T>(endpoint: string): Promise<T> {
  const r = await fetch(buildApiUrl(endpoint), { method: "GET", headers: getAuthHeaders() })
  if (!r.ok) {
    const text = await r.text().catch(() => "")
    throw new Error(explainHttpError("GET", endpoint, r.status, text))
  }
  return (await r.json()) as T
}

async function postJson<T>(endpoint: string, body: unknown): Promise<T | null> {
  const r = await fetch(buildApiUrl(endpoint), {
    method: "POST",
    headers: getAuthHeaders(),
    // farmId travels in the body: model validation runs before the action body,
    // and the audit filter's farmId cascade reads the body, not the route.
    body: JSON.stringify({ ...(body as object), farmId: currentFarmId() }),
  })
  if (r.status === 204) return null
  if (!r.ok) {
    const text = await r.text().catch(() => "")
    throw new Error(explainHttpError("POST", endpoint, r.status, text))
  }
  const txt = await r.text()
  return txt ? (JSON.parse(txt) as T) : null
}

function qs(params: Record<string, string | number | null | undefined>): string {
  const p = new URLSearchParams()
  for (const [k, v] of Object.entries(params)) {
    if (v !== null && v !== undefined && v !== "") p.set(k, String(v))
  }
  const s = p.toString()
  return s ? `?${s}` : ""
}

// =============================================================================
// Recurring expenses
// =============================================================================

export async function getRecurringExpenses(status?: string | null): Promise<GenericRecurringExpense[]> {
  return getJson<GenericRecurringExpense[]>(`${farmBase()}/recurring-expenses${qs({ status })}`)
}

export async function createRecurringExpense(
  input: CreateRecurringExpenseInput,
): Promise<number | null> {
  const res = await postJson<{ genericRecurringExpenseId: number }>(
    `${farmBase()}/recurring-expenses`,
    input,
  )
  return res?.genericRecurringExpenseId ?? null
}

/** Pause, resume, cancel or expire. Cancelling needs a reason. */
export async function setRecurringExpenseStatus(
  id: number,
  input: { status: string; reason?: string | null; by?: string | null },
): Promise<void> {
  await postJson(`${farmBase()}/recurring-expenses/${id}/status`, input)
}

/** What generating now would raise. Writes nothing. */
export async function previewRecurring(asOf?: string | null): Promise<RecurringExpensePreviewRow[]> {
  return getJson<RecurringExpensePreviewRow[]>(
    `${farmBase()}/recurring-expenses/preview${qs({ asOf })}`,
  )
}

/**
 * Raises one expense per unbilled period, catching up anything behind, and
 * returns how many. Running it twice raises nothing twice.
 */
export async function generateRecurring(asOf?: string | null): Promise<number> {
  const res = await postJson<{ generated: number }>(
    `${farmBase()}/recurring-expenses/generate`,
    { asOf: asOf ?? null },
  )
  return res?.generated ?? 0
}

// =============================================================================
// Staff and contractor payments
// =============================================================================

export async function getStaffPayments(opts: {
  staffId?: number | null
  from?: string | null
  to?: string | null
} = {}): Promise<GenericStaffPayment[]> {
  return getJson<GenericStaffPayment[]>(
    `${farmBase()}/staff-payments${qs({ staffId: opts.staffId, from: opts.from, to: opts.to })}`,
  )
}

/**
 * Pays one person now, without a payroll run. Posts an expense so the cost
 * reaches the P&L, and one cash-out so it reaches cash flow.
 */
export async function recordStaffPayment(input: RecordStaffPaymentInput): Promise<number | null> {
  const res = await postJson<{ paymentId: number }>(`${farmBase()}/staff-payments`, input)
  return res?.paymentId ?? null
}

export async function reverseStaffPayment(
  paymentId: number,
  reason: string,
  reversedBy?: string | null,
): Promise<void> {
  await postJson(`${farmBase()}/staff-payments/${paymentId}/reverse`, { reason, reversedBy })
}

// =============================================================================
// Owner contributions and draws
// =============================================================================

export async function getOwnerEntries(opts: {
  entryType?: string | null
  from?: string | null
  to?: string | null
} = {}): Promise<GenericOwnerEntry[]> {
  return getJson<GenericOwnerEntry[]>(
    `${farmBase()}/owner-entries${qs({ entryType: opts.entryType, from: opts.from, to: opts.to })}`,
  )
}

/**
 * Owner money moves cash and nothing else — it is neither revenue nor an
 * operating expense, so profit is unaffected by how the owner funds things.
 */
export async function recordOwnerEntry(input: RecordOwnerEntryInput): Promise<number | null> {
  const res = await postJson<{ entryId: number }>(`${farmBase()}/owner-entries`, input)
  return res?.entryId ?? null
}

export async function reverseOwnerEntry(
  entryId: number,
  reason: string,
  reversedBy?: string | null,
): Promise<void> {
  await postJson(`${farmBase()}/owner-entries/${entryId}/reverse`, { reason, reversedBy })
}
