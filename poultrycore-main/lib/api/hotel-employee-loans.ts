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
// CONSTANTS
// =============================================================================

export const HOTEL_LOAN_TYPES = [
  { value: "SalaryAdvance", label: "Salary advance" },
  { value: "EmployeeLoan", label: "Staff loan" },
  { value: "OtherAdvance", label: "Other advance" },
] as const

/** How the staff member will pay it back. PayrollDeduction and Mixed are what payroll suggests deductions for. */
export const HOTEL_LOAN_REPAYMENT_METHODS = [
  { value: "PayrollDeduction", label: "Deduct from payroll" },
  { value: "Mixed", label: "Payroll and cash" },
  { value: "Cash", label: "Cash" },
  { value: "MoMo", label: "Mobile money" },
  { value: "Bank", label: "Bank" },
  { value: "Other", label: "Other" },
] as const

/** Sources for a repayment recorded by hand. Payroll repayments only come from approving a payroll run. */
export const HOTEL_LOAN_REPAYMENT_SOURCES = [
  { value: "Cash", label: "Cash" },
  { value: "MoMo", label: "Mobile money" },
  { value: "Bank", label: "Bank" },
  { value: "Other", label: "Other" },
] as const

export function hotelLoanTypeLabel(v: string): string {
  return HOTEL_LOAN_TYPES.find((t) => t.value === v)?.label ?? v
}
export function hotelLoanMethodLabel(v: string): string {
  return HOTEL_LOAN_REPAYMENT_METHODS.find((t) => t.value === v)?.label ?? v
}
export function hotelLoanSourceLabel(v: string): string {
  if (v === "Payroll") return "Payroll deduction"
  return HOTEL_LOAN_REPAYMENT_SOURCES.find((t) => t.value === v)?.label ?? v
}

// =============================================================================
// TYPES
// =============================================================================

export interface HotelEmployeeLoan {
  hotelEmployeeLoanId: number
  farmId: string
  hotelStaffId: number
  staffName?: string | null
  staffIsActive: boolean
  loanNumber?: string | null
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
  cashAccountName?: string | null
  reference?: string | null
  notes?: string | null
  createdBy?: string | null
  createdAt: string
  updatedAt?: string | null
  reversedBy?: string | null
  reversedReason?: string | null
  reversedAt?: string | null
  repaymentCount: number
  lastRepaymentDate?: string | null
  /** Amount draft payroll runs are already set to deduct from this loan. */
  draftPayrollClaims: number
}

export interface HotelEmployeeLoanRepayment {
  hotelEmployeeLoanRepaymentId: number
  farmId: string
  hotelEmployeeLoanId: number
  loanNumber?: string | null
  hotelStaffId: number
  staffName?: string | null
  amount: number
  principalAmount: number
  interestAmount: number
  sourceType: string
  paymentMethod?: string | null
  hotelCashAccountId?: number | null
  cashAccountName?: string | null
  cashTransactionId?: number | null
  hotelPayrollRunId?: number | null
  payrollPeriod?: string | null
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
  staffWithLoans: number
  draftCount: number
  paidCount: number
  interestEarned: number
  repaidViaPayroll: number
  draftPayrollClaims: number
}

/** One open loan of a staff member, as the payroll screen needs it. */
export interface HotelEmployeeLoanEligible {
  hotelEmployeeLoanId: number
  loanNumber?: string | null
  loanType: string
  repaymentMethod: string
  outstandingBalance: number
  defaultPayrollDeduction: number
  /** Already set aside on other draft payroll lines. */
  claimedElsewhere: number
  /** The most this payroll line may deduct. */
  available: number
  suggestedDeduction: number
  /** What this payroll line deducts today (0 if none). */
  currentDeduction: number
}

export interface HotelEmployeeLoanStaffRow {
  hotelStaffId: number
  staffName: string
  department?: string | null
  staffIsActive: boolean
  activeLoans: number
  outstanding: number
  disbursedInPeriod: number
  repaidCashInPeriod: number
  repaidPayrollInPeriod: number
  interestInPeriod: number
  lastRepaymentDate?: string | null
  totalEver: number
}

export interface HotelEmployeeLoanInput {
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

export interface HotelEmployeeLoanUpdateInput {
  loanType: string
  principalAmount: number
  interestAmount: number
  repaymentMethod: string
  defaultPayrollDeduction: number
  expectedEndDate?: string | null
  reference?: string | null
  notes?: string | null
}

export interface HotelEmployeeLoanRepaymentInput {
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

/** A staff member's open loans with the suggested payroll deduction. excludeItemId: the payroll line being edited. */
export async function listEligibleHotelEmployeeLoans(staffId: number, excludeItemId?: number | null): Promise<HotelEmployeeLoanEligible[]> {
  const x = excludeItemId ? `&excludeItemId=${excludeItemId}` : ""
  return jget(`/api/Hotel/employee-loans/eligible?staffId=${staffId}${x}`)
}

/** Per staff member: owed now, and advanced / repaid between the dates (inclusive). */
export async function getHotelEmployeeLoanStaffReport(fromDate?: string, toDate?: string): Promise<HotelEmployeeLoanStaffRow[]> {
  let q = ""
  if (fromDate) q += `&fromDate=${encodeURIComponent(fromDate)}`
  if (toDate) q += `&toDate=${encodeURIComponent(toDate)}`
  return jget(`/api/Hotel/employee-loans/staff-report${q ? "?" + q.slice(1) : ""}`)
}

export async function createHotelEmployeeLoan(input: HotelEmployeeLoanInput): Promise<{ hotelEmployeeLoanId: number }> {
  return jsend("/api/Hotel/employee-loans", "POST", { ...input, farmId: activeFarmId() })
}

export async function updateHotelEmployeeLoan(id: number, input: HotelEmployeeLoanUpdateInput): Promise<void> {
  await jsend(`/api/Hotel/employee-loans/${id}`, "PUT", { ...input, farmId: activeFarmId() })
}

export async function disburseHotelEmployeeLoan(id: number, cashAccountId: number, disbursementDate?: string | null, reference?: string | null): Promise<void> {
  await jsend(`/api/Hotel/employee-loans/${id}/disburse`, "POST", {
    farmId: activeFarmId(), hotelCashAccountId: cashAccountId, disbursementDate, reference,
  })
}

export async function cancelHotelEmployeeLoan(id: number, reason?: string): Promise<void> {
  await jsend(`/api/Hotel/employee-loans/${id}/cancel`, "POST", { farmId: activeFarmId(), reason })
}

export async function reverseHotelEmployeeLoan(id: number, reason: string): Promise<void> {
  await jsend(`/api/Hotel/employee-loans/${id}/reverse`, "POST", { farmId: activeFarmId(), reason })
}

export async function listHotelEmployeeLoanRepayments(loanId: number): Promise<HotelEmployeeLoanRepayment[]> {
  return jget(`/api/Hotel/employee-loans/${loanId}/repayments`)
}

/** Every repayment of the hotel, reversed ones included, oldest first. */
export async function listAllHotelEmployeeLoanRepayments(): Promise<HotelEmployeeLoanRepayment[]> {
  return jget(`/api/Hotel/employee-loan-repayments`)
}

export async function recordHotelEmployeeLoanRepayment(input: HotelEmployeeLoanRepaymentInput): Promise<{ hotelEmployeeLoanRepaymentId: number }> {
  return jsend("/api/Hotel/employee-loan-repayments", "POST", { ...input, farmId: activeFarmId() })
}

export async function reverseHotelEmployeeLoanRepayment(id: number, reason: string): Promise<void> {
  await jsend(`/api/Hotel/employee-loan-repayments/${id}/reverse`, "POST", { farmId: activeFarmId(), reason })
}
