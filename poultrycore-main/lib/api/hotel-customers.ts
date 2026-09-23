import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "./config"

function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

async function jget<T>(endpoint: string): Promise<T> {
  const farmId = activeFarmId()
  const sep = endpoint.includes("?") ? "&" : "?"
  const url = farmApiUrl(`${endpoint}${sep}farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

async function jsend<T>(endpoint: string, method: string, body?: unknown): Promise<T> {
  const url = farmApiUrl(endpoint)
  const res = await fetch(url, {
    method,
    headers: getAuthHeaders(),
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) throw new Error(await readApiError(res))
  const text = await res.text()
  return text ? JSON.parse(text) : ({} as T)
}

// =============================================================================
// TYPES
// =============================================================================

export interface HotelCustomer {
  hotelCustomerId: number
  farmId: string
  customerName: string
  customerType: string
  phone?: string | null
  email?: string | null
  address?: string | null
  city?: string | null
  paymentTermDays: number
  creditLimit: number
  openingBalance: number
  currentBalance: number
  isActive: boolean
  notes?: string | null
  createdBy?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface HotelCustomerInput {
  farmId: string
  customerName: string
  customerType?: string
  phone?: string | null
  email?: string | null
  address?: string | null
  city?: string | null
  paymentTermDays?: number
  creditLimit?: number
  openingBalance?: number
  notes?: string | null
  isActive?: boolean
}

export interface HotelCustomerLedgerEntry {
  hotelCustomerLedgerId: number
  farmId: string
  hotelCustomerId: number
  transactionDate: string
  transactionType: string
  invoiceId?: number | null
  paymentId?: number | null
  debitAmount: number
  creditAmount: number
  balanceAfterTransaction: number
  description?: string | null
  createdBy?: string | null
  createdAt: string
}

export interface HotelCustomerPayment {
  hotelCustomerPaymentId: number
  farmId: string
  hotelCustomerId: number
  customerName?: string | null
  paymentDate: string
  amount: number
  paymentMethod: string
  hotelCashAccountId?: number | null
  reference?: string | null
  linkedInvoiceId?: number | null
  status: "Draft" | "Approved" | "Cancelled" | string
  notes?: string | null
  createdBy?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface HotelCustomerPaymentInput {
  farmId: string
  hotelCustomerId: number
  amount: number
  paymentMethod?: string
  hotelCashAccountId?: number | null
  reference?: string | null
  linkedInvoiceId?: number | null
  paymentDate?: string | null
  notes?: string | null
}

export interface HotelCustomerBalanceSummary {
  totalCustomers: number
  customersOwing: number
  totalBalance: number
  totalOverdueCount: number
}

export interface HotelCustomerOwedRow {
  hotelCustomerId: number
  farmId: string
  customerName: string
  customerType?: string | null
  phone?: string | null
  paymentTermDays: number
  currentBalance: number
}

// =============================================================================
// API FUNCTIONS
// =============================================================================

// ── Customers ──────────────────────────────────────────────────────────────

export async function listHotelCustomers(): Promise<HotelCustomer[]> {
  return jget("/api/Hotel/customers")
}

export async function getHotelCustomer(id: number): Promise<HotelCustomer | null> {
  return jget(`/api/Hotel/customers/${id}`)
}

export async function createHotelCustomer(input: HotelCustomerInput): Promise<{ hotelCustomerId: number }> {
  return jsend("/api/Hotel/customers", "POST", { ...input, farmId: activeFarmId() })
}

export async function updateHotelCustomer(id: number, input: HotelCustomerInput): Promise<void> {
  await jsend(`/api/Hotel/customers/${id}`, "PUT", { ...input, farmId: activeFarmId() })
}

export async function deleteHotelCustomer(id: number): Promise<void> {
  const farmId = activeFarmId()
  await jsend(`/api/Hotel/customers/${id}?farmId=${encodeURIComponent(farmId)}`, "DELETE")
}

export async function listHotelCustomersOwed(): Promise<HotelCustomerOwedRow[]> {
  return jget("/api/Hotel/customers/owed")
}

export async function getHotelCustomerBalanceSummary(): Promise<HotelCustomerBalanceSummary> {
  return jget("/api/Hotel/customers/balance-summary")
}

// ── Ledger ─────────────────────────────────────────────────────────────────

export async function getHotelCustomerLedger(customerId: number): Promise<HotelCustomerLedgerEntry[]> {
  return jget(`/api/Hotel/customers/${customerId}/ledger`)
}

export async function postHotelCustomerInvoice(customerId: number, invoiceId: number, amount: number, description?: string): Promise<void> {
  await jsend("/api/Hotel/customers/post-invoice", "POST", {
    farmId: activeFarmId(),
    hotelCustomerId: customerId,
    invoiceId,
    amount,
    description,
  })
}

export async function postHotelCustomerAdjustment(customerId: number, amount: number, description?: string): Promise<void> {
  await jsend("/api/Hotel/customers/post-adjustment", "POST", {
    farmId: activeFarmId(),
    hotelCustomerId: customerId,
    amount,
    description,
  })
}

// ── Payments ───────────────────────────────────────────────────────────────

export async function listHotelCustomerPayments(status?: string | null): Promise<HotelCustomerPayment[]> {
  const q = status ? `?status=${encodeURIComponent(status)}` : ""
  return jget(`/api/Hotel/customer-payments${q}`)
}

export async function getHotelCustomerPayment(id: number): Promise<HotelCustomerPayment | null> {
  return jget(`/api/Hotel/customer-payments/${id}`)
}

export async function createHotelCustomerPayment(input: HotelCustomerPaymentInput): Promise<{ hotelCustomerPaymentId: number }> {
  return jsend("/api/Hotel/customer-payments", "POST", { ...input, farmId: activeFarmId() })
}

export async function approveHotelCustomerPayment(id: number): Promise<void> {
  const farmId = activeFarmId()
  await jsend(`/api/Hotel/customer-payments/${id}/approve?farmId=${encodeURIComponent(farmId)}`, "POST")
}

export async function cancelHotelCustomerPayment(id: number): Promise<void> {
  const farmId = activeFarmId()
  await jsend(`/api/Hotel/customer-payments/${id}/cancel?farmId=${encodeURIComponent(farmId)}`, "POST")
}
