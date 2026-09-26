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
  const res = await fetch(url, { method, headers: getAuthHeaders(), body: body ? JSON.stringify(body) : undefined })
  if (!res.ok) throw new Error(await readApiError(res))
  const text = await res.text()
  return text ? JSON.parse(text) : ({} as T)
}

export interface HotelSupplier {
  hotelSupplierId: number; farmId: string; supplierName: string; supplierType: string
  phone?: string | null; email?: string | null; location?: string | null; address?: string | null
  paymentTermDays: number; openingBalance: number; currentBalance: number
  isActive: boolean; notes?: string | null; createdAt: string; updatedAt?: string | null
}

export interface HotelSupplierInput {
  farmId: string; supplierName: string; supplierType?: string
  phone?: string | null; email?: string | null; location?: string | null; address?: string | null
  paymentTermDays?: number; openingBalance?: number; notes?: string | null; isActive?: boolean
}

export interface HotelSupplierLedgerEntry {
  hotelSupplierLedgerId: number; transactionDate: string; transactionType: string
  expenseId?: number | null; paymentId?: number | null
  debitAmount: number; creditAmount: number; balanceAfterTransaction: number
  description?: string | null; createdAt: string
}

export interface HotelSupplierPayment {
  hotelSupplierPaymentId: number; farmId: string; hotelSupplierId: number
  supplierName?: string | null; paymentDate: string; amount: number; paymentMethod: string
  hotelCashAccountId?: number | null; reference?: string | null; linkedExpenseId?: number | null
  status: string; notes?: string | null; createdBy?: string | null
  approvedBy?: string | null; approvedAt?: string | null; createdAt: string
}

export interface HotelSupplierPaymentInput {
  farmId: string; hotelSupplierId: number; amount: number; paymentMethod?: string
  hotelCashAccountId?: number | null; reference?: string | null; linkedExpenseId?: number | null
  paymentDate?: string | null; notes?: string | null
}

export interface HotelSupplierBalanceSummary { totalSuppliers: number; suppliersOwed: number; totalBalance: number }

export async function listHotelSuppliers(): Promise<HotelSupplier[]> { return jget("/api/Hotel/suppliers") }
export async function getHotelSupplier(id: number): Promise<HotelSupplier | null> { return jget(`/api/Hotel/suppliers/${id}`) }
export async function createHotelSupplier(input: HotelSupplierInput): Promise<{ hotelSupplierId: number }> { return jsend("/api/Hotel/suppliers", "POST", { ...input, farmId: activeFarmId() }) }
export async function updateHotelSupplier(id: number, input: HotelSupplierInput): Promise<void> { await jsend(`/api/Hotel/suppliers/${id}`, "PUT", { ...input, farmId: activeFarmId() }) }
export async function deleteHotelSupplier(id: number): Promise<void> { await jsend(`/api/Hotel/suppliers/${id}?farmId=${encodeURIComponent(activeFarmId())}`, "DELETE") }
export async function getHotelSupplierBalanceSummary(): Promise<HotelSupplierBalanceSummary> { return jget("/api/Hotel/suppliers/balance-summary") }
export async function getHotelSupplierLedger(supplierId: number): Promise<HotelSupplierLedgerEntry[]> { return jget(`/api/Hotel/suppliers/${supplierId}/ledger`) }

export async function listHotelSupplierPayments(status?: string | null): Promise<HotelSupplierPayment[]> {
  const q = status ? `?status=${encodeURIComponent(status)}` : ""
  return jget(`/api/Hotel/supplier-payments${q}`)
}
export async function createHotelSupplierPayment(input: HotelSupplierPaymentInput): Promise<{ hotelSupplierPaymentId: number }> { return jsend("/api/Hotel/supplier-payments", "POST", { ...input, farmId: activeFarmId() }) }
export async function approveHotelSupplierPayment(id: number): Promise<void> { await jsend(`/api/Hotel/supplier-payments/${id}/approve?farmId=${encodeURIComponent(activeFarmId())}`, "POST") }
export async function cancelHotelSupplierPayment(id: number): Promise<void> { await jsend(`/api/Hotel/supplier-payments/${id}/cancel?farmId=${encodeURIComponent(activeFarmId())}`, "POST") }
