// Customer Balances / Supplier Balances API client.
//
// One client for all three company types. The three modules have different
// route prefixes but the same endpoint shapes and the same response DTOs
// (PoultryFarmAPI/Models/BalanceModels.cs), so the module only decides the
// prefix. Poultry ships first; the water and generic entries light up when
// their migrations land.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

export type BalanceModule = "poultry" | "water" | "generic"

/** Route prefix per module. Generic nests the farm id in the path. */
function prefix(module: BalanceModule, farmId: string): string {
  switch (module) {
    case "water":
      return "/Water"
    case "generic":
      return `/generic-company/${encodeURIComponent(farmId)}`
    default:
      return "/Poultry"
  }
}

function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

function currentUserId(): string {
  const { userId } = getUserContext()
  return userId
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

async function jsend<T>(path: string, method: "POST" | "PUT" | "DELETE", body?: any): Promise<T> {
  const init: RequestInit = { method, headers: getAuthHeaders() }
  if (body !== undefined) init.body = JSON.stringify(body)
  const res = await fetch(farmApiUrl(path), init)
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(explainHttpError(method, path, res.status, t))
  }
  if (res.status === 204) return undefined as unknown as T
  const text = await res.text()
  return text ? (JSON.parse(text) as T) : (undefined as unknown as T)
}

// ----------------------------------------------------------------------- types

export type BalanceSide = "customer" | "supplier"

export const BALANCE_STATUS_FILTERS = ["All", "Partial", "Unpaid", "Overdue"] as const
export type BalanceStatusFilter = (typeof BALANCE_STATUS_FILTERS)[number]

/** A customer who owes us, or a supplier we owe. */
export interface PartyBalanceRow {
  partyId: number
  partyName: string
  contactPhone?: string | null
  contactEmail?: string | null
  paymentTermsDays: number
  totalBalance: number
  openDocumentCount: number
  oldestDocumentDate?: string | null
  latestDocumentDate?: string | null
  lastPaymentDate?: string | null
  overdueAmount: number
  totalInvoiced: number
  totalPaid: number
}

/** The unpaid or part-paid sale/purchase behind a balance. */
export interface OpenDocumentRow {
  documentType: string
  documentId: number
  reference?: string | null
  documentDate: string
  label?: string | null
  description?: string | null
  totalAmount: number
  amountPaid: number
  balance: number
  dueDate?: string | null
  ageDays: number
  status: string
  isOverdue: boolean
  cashAccountId?: number | null
}

export interface BalanceSummary {
  totalBalance: number
  partyCount: number
  overdueBalance: number
  paymentsToday: number
  largestBalance: number
  largestBalanceParty?: string | null
}

export interface PaymentAllocationInput {
  saleId?: number
  documentType?: string
  documentId: number
  amount: number
}

export interface RecordPaymentRequest {
  farmId: string
  partyId: number | null
  amount: number
  paymentDate?: string | null
  paymentMethod?: string | null
  cashAccountId?: number | null
  reference?: string | null
  notes?: string | null
  sourceType?: string | null
  createdBy?: string | null
  allocations: PaymentAllocationInput[]
}

export interface PaymentHistoryRow {
  /** uuid on the customer side (a payment group), integer on the supplier side. */
  paymentId: string
  partyId?: number | null
  partyName?: string | null
  paymentDate: string
  totalAmount: number
  paymentMethod?: string | null
  reference?: string | null
  notes?: string | null
  sourceType?: string | null
  status: "Posted" | "Reversed" | string
  allocationCount: number
  cashAccountId?: number | null
  createdBy?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface PaymentAllocationRow {
  allocationId: number
  documentType: string
  documentId: number
  reference?: string | null
  documentDate?: string | null
  label?: string | null
  documentTotal: number
  amountApplied: number
  balanceBefore: number
  balanceAfter: number
  status: string
}

export interface StatementLine {
  entryDate?: string | null
  entryType: "OpeningBalance" | "Sale" | "Purchase" | "Payment" | string
  reference?: string | null
  description?: string | null
  /** Increases what is owed. */
  debit: number
  /** Reduces it. */
  credit: number
  runningBalance: number
  documentType?: string | null
  documentId?: number | null
}

export interface BalanceAuditRow {
  side: string
  documentType: string
  documentId: number
  amountPaid: number
  allocated: number
  difference: number
}

export interface BalanceFilters {
  from?: string | null
  to?: string | null
  partyId?: number | null
  status?: BalanceStatusFilter
  minBalance?: number | null
  search?: string | null
}

// --------------------------------------------------------------------- helpers

function qs(params: Record<string, string | number | null | undefined>): string {
  const search = new URLSearchParams()
  for (const [k, v] of Object.entries(params)) {
    if (v === null || v === undefined || v === "") continue
    search.set(k, String(v))
  }
  const s = search.toString()
  return s ? `?${s}` : ""
}

/** Customer routes say customerId; supplier routes say supplierId. */
function partyParam(side: BalanceSide): "customerId" | "supplierId" {
  return side === "customer" ? "customerId" : "supplierId"
}

function balancesPath(side: BalanceSide): string {
  return side === "customer" ? "customer-balances" : "supplier-balances"
}

function paymentsPath(side: BalanceSide): string {
  return side === "customer" ? "customer-payments" : "supplier-payments"
}

// ----------------------------------------------------------------------- reads

export async function listBalances(
  module: BalanceModule,
  side: BalanceSide,
  filters: BalanceFilters = {},
): Promise<PartyBalanceRow[]> {
  const farmId = activeFarmId()
  const q = qs({
    farmId,
    from: filters.from,
    to: filters.to,
    [partyParam(side)]: filters.partyId,
    status: filters.status,
    minBalance: filters.minBalance,
    search: filters.search,
  })
  return jget<PartyBalanceRow[]>(`${prefix(module, farmId)}/${balancesPath(side)}${q}`)
}

export async function getBalanceSummary(
  module: BalanceModule,
  side: BalanceSide,
): Promise<BalanceSummary> {
  const farmId = activeFarmId()
  return jget<BalanceSummary>(
    `${prefix(module, farmId)}/${balancesPath(side)}/summary${qs({ farmId })}`,
  )
}

/** The sales or purchases behind one party's balance. */
export async function listOpenDocuments(
  module: BalanceModule,
  side: BalanceSide,
  partyId: number,
  filters: Pick<BalanceFilters, "from" | "to" | "status"> = {},
): Promise<OpenDocumentRow[]> {
  const farmId = activeFarmId()
  const leaf = side === "customer" ? "open-sales" : "open-purchases"
  const q = qs({ farmId, from: filters.from, to: filters.to, status: filters.status })
  return jget<OpenDocumentRow[]>(
    `${prefix(module, farmId)}/${balancesPath(side)}/${partyId}/${leaf}${q}`,
  )
}

export async function listPayments(
  module: BalanceModule,
  side: BalanceSide,
  opts: { partyId?: number | null; documentType?: string | null; documentId?: number | null; from?: string | null; to?: string | null } = {},
): Promise<PaymentHistoryRow[]> {
  const farmId = activeFarmId()
  const q = qs({
    farmId,
    [partyParam(side)]: opts.partyId,
    ...(side === "customer"
      ? { saleId: opts.documentId }
      : { documentType: opts.documentType, documentId: opts.documentId }),
    from: opts.from,
    to: opts.to,
  })
  return jget<PaymentHistoryRow[]>(`${prefix(module, farmId)}/${paymentsPath(side)}${q}`)
}

export async function getPayment(
  module: BalanceModule,
  side: BalanceSide,
  paymentId: string,
): Promise<{ payment: PaymentHistoryRow; allocations: PaymentAllocationRow[] }> {
  const farmId = activeFarmId()
  return jget(
    `${prefix(module, farmId)}/${paymentsPath(side)}/${encodeURIComponent(paymentId)}${qs({ farmId })}`,
  )
}

export async function getStatement(
  module: BalanceModule,
  side: BalanceSide,
  partyId: number,
  range: { from?: string | null; to?: string | null } = {},
): Promise<StatementLine[]> {
  const farmId = activeFarmId()
  const leaf = side === "customer" ? "customers" : "suppliers"
  return jget<StatementLine[]>(
    `${prefix(module, farmId)}/${leaf}/${partyId}/statement${qs({ farmId, from: range.from, to: range.to })}`,
  )
}

export async function auditBalances(module: BalanceModule): Promise<BalanceAuditRow[]> {
  const farmId = activeFarmId()
  return jget<BalanceAuditRow[]>(`${prefix(module, farmId)}/balances/audit${qs({ farmId })}`)
}

// ---------------------------------------------------------------------- writes

/**
 * Post a payment and its allocations.
 *
 * One call, one transaction on the server: the payment, its allocations, every
 * document balance and the cash movement all land together or none of them do.
 */
export async function recordPayment(
  module: BalanceModule,
  side: BalanceSide,
  input: Omit<RecordPaymentRequest, "farmId" | "createdBy"> & { createdBy?: string },
): Promise<string> {
  const farmId = activeFarmId()
  const body: RecordPaymentRequest = {
    ...input,
    farmId,
    createdBy: input.createdBy ?? currentUserId(),
  }
  const res = await jsend<{ paymentId: string | number }>(
    `${prefix(module, farmId)}/${paymentsPath(side)}`,
    "POST",
    body,
  )
  return String(res?.paymentId ?? "")
}

export async function reversePayment(
  module: BalanceModule,
  side: BalanceSide,
  paymentId: string,
  reason: string,
): Promise<number> {
  const farmId = activeFarmId()
  const res = await jsend<{ reversedAllocations: number }>(
    `${prefix(module, farmId)}/${paymentsPath(side)}/${encodeURIComponent(paymentId)}/reverse`,
    "POST",
    { farmId, reason, reversedBy: currentUserId() },
  )
  return res?.reversedAllocations ?? 0
}
