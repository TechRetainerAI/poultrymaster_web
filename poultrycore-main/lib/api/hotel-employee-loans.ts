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

export interface HotelEmployeeLoan {
  hotelEmployeeLoanId: number
  farmId: string
  hotelStaffId: number
  staffName?: string | null
  loanType: string
  status: string
  principalAmount: number
  interestAmount: number
  totalRepayable: number
  totalPrincipalRepaid: number
  totalInterestRepaid: number
  outstandingBalance: number
  repaymentMethod: string
  defaultPayrollDeduction: number
  disbursementDate?: string | null
  expectedEndDate?: string | null
  hotelCashAccountId?: number | null
  reference?: string | null
  notes?: string | null
  createdBy?: string | null
  createdAt: string
  updatedAt?: string | null
  reversedBy?: string | null
  reversedReason?: string | null
  reversedAt?: string | null
}

export interface HotelEmployeeLoanRepayment {
  hotelEmployeeLoanRepaymentId: number
  farmId: string
  hotelEmployeeLoanId: number
  amount: number
  principalAmount: number
  interestAmount: number
  sourceType: string
  paymentMethod?: string | null
  hotelCashAccountId?: number | null
  balanceBefore: number
  balanceAfter: number
  repaymentDate: string
  reference?: string | null
  notes?: string | null
  status: string
  createdBy?: string | null
  createdAt: string
  reversedBy?: string | null
  reversedReason?: string | null
  reversedAt?: string | null
}

export interface HotelEmployeeLoanSummary {
  totalOutstanding: number
  totalDisbursed: number
  totalRepaid: number
  activeCount: number
}

export interface HotelEmployeeLoanInput {
  farmId: string
  hotelStaffId: number
  staffName?: string | null
  loanType?: string
  principalAmount: number
  interestAmount?: number
  repaymentMethod?: string
  defaultPayrollDeduction?: number
  expectedEndDate?: string | null
  reference?: string | null
  notes?: string | null
  disburseNow?: boolean
  hotelCashAccountId?: number | null
  disbursementDate?: string | null
}

export interface HotelEmployeeLoanRepaymentInput {
  farmId: string
  hotelEmployeeLoanId: number
  amount: number
  sourceType?: string
  hotelCashAccountId?: number | null
  repaymentDate?: string | null
  reference?: string | null
  notes?: string | null
}

// =============================================================================
// API FUNCTIONS
// =============================================================================

export async function listHotelEmployeeLoans(status?: string | null, staffId?: number | null): Promise<HotelEmployeeLoan[]> {
  let q = ""
  if (status) q += `&status=${encodeURIComponent(status)}`
  if (staffId) q += `&staffId=${staffId}`
  return jget(`/api/Hotel/employee-loans${q ? "?" + q.slice(1) : ""}`)
}

export async function getHotelEmployeeLoan(id: number): Promise<HotelEmployeeLoan | null> {
  return jget(`/api/Hotel/employee-loans/${id}`)
}

export async function getHotelEmployeeLoanSummary(fromDate?: string, toDate?: string): Promise<HotelEmployeeLoanSummary> {
  let q = ""
  if (fromDate) q += `&fromDate=${encodeURIComponent(fromDate)}`
  if (toDate) q += `&toDate=${encodeURIComponent(toDate)}`
  return jget(`/api/Hotel/employee-loans/summary${q ? "?" + q.slice(1) : ""}`)
}

export async function createHotelEmployeeLoan(input: HotelEmployeeLoanInput): Promise<{ hotelEmployeeLoanId: number }> {
  return jsend("/api/Hotel/employee-loans", "POST", { ...input, farmId: activeFarmId() })
}

export async function disburseHotelEmployeeLoan(id: number, cashAccountId?: number | null, disbursementDate?: string | null, reference?: string | null): Promise<void> {
  await jsend(`/api/Hotel/employee-loans/${id}/disburse`, "POST", {
    farmId: activeFarmId(), hotelCashAccountId: cashAccountId, disbursementDate, reference,
  })
}

export async function cancelHotelEmployeeLoan(id: number, reason?: string): Promise<void> {
  await jsend(`/api/Hotel/employee-loans/${id}/cancel`, "POST", { farmId: activeFarmId(), reason })
}

export async function reverseHotelEmployeeLoan(id: number, reason?: string): Promise<void> {
  await jsend(`/api/Hotel/employee-loans/${id}/reverse`, "POST", { farmId: activeFarmId(), reason })
}

export async function listHotelEmployeeLoanRepayments(loanId: number): Promise<HotelEmployeeLoanRepayment[]> {
  return jget(`/api/Hotel/employee-loans/${loanId}/repayments`)
}

export async function recordHotelEmployeeLoanRepayment(input: HotelEmployeeLoanRepaymentInput): Promise<{ hotelEmployeeLoanRepaymentId: number }> {
  return jsend("/api/Hotel/employee-loan-repayments", "POST", { ...input, farmId: activeFarmId() })
}

export async function reverseHotelEmployeeLoanRepayment(id: number, reason?: string): Promise<void> {
  await jsend(`/api/Hotel/employee-loan-repayments/${id}/reverse`, "POST", { farmId: activeFarmId(), reason })
}
