// Generic Employee Loans & Advances API client.
// Same pattern as poultry-finance.ts but hits /Generic/employee-loans endpoints.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

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
const fid = () => encodeURIComponent(activeFarmId())

// =============================================================================
// Constants & labels
// =============================================================================

export const EMPLOYEE_LOAN_TYPES = ["EmployeeLoan", "SalaryAdvance", "OtherAdvance"] as const
export type EmployeeLoanType = (typeof EMPLOYEE_LOAN_TYPES)[number]

export const EMPLOYEE_LOAN_TYPE_LABELS: Record<string, string> = {
  EmployeeLoan: "Employee loan",
  SalaryAdvance: "Salary advance",
  OtherAdvance: "Other advance",
}

export const EMPLOYEE_LOAN_REPAYMENT_METHODS = [
  "PayrollDeduction", "Cash", "MoMo", "Bank", "Mixed", "Other",
] as const

export const EMPLOYEE_LOAN_REPAYMENT_METHOD_LABELS: Record<string, string> = {
  PayrollDeduction: "Payroll deduction",
  Cash: "Cash",
  MoMo: "MoMo",
  Bank: "Bank",
  Mixed: "Mixed",
  Other: "Other",
}

export const EMPLOYEE_LOAN_REPAYMENT_SOURCES = ["ManualCash", "MoMo", "Bank", "Other"] as const

export const EMPLOYEE_LOAN_SOURCE_LABELS: Record<string, string> = {
  Payroll: "Payroll",
  ManualCash: "Cash",
  MoMo: "MoMo",
  Bank: "Bank",
  Other: "Other",
}

export const EMPLOYEE_LOAN_STATUS_LABELS: Record<string, string> = {
  Draft: "Draft",
  Active: "Active",
  Paid: "Paid",
  Cancelled: "Cancelled",
  Reversed: "Reversed",
  WrittenOff: "Written off",
}

// =============================================================================
// Types
// =============================================================================

export interface GenericEmployeeLoan {
  genericEmployeeLoanId: number
  farmId: string
  genericStaffId: number
  staffName?: string | null
  staffRole?: string | null
  loanNumber?: string | null
  loanType: string
  principalAmount: number
  interestEnabled: boolean
  interestAmount: number
  interestRate?: number | null
  interestType?: string | null
  totalRepayable: number
  disbursementDate: string
  repaymentMethod: string
  defaultPayrollDeduction?: number | null
  expectedStartDate?: string | null
  expectedEndDate?: string | null
  purpose?: string | null
  description?: string | null
  notes?: string | null
  status: string
  paidAt?: string | null
  totalRepaid: number
  totalPrincipalRepaid: number
  totalInterestRepaid: number
  outstandingBalance: number
  repaymentCount: number
  genericCashAccountId?: number | null
  cashAccountName?: string | null
  paymentMethod?: string | null
  referenceNumber?: string | null
  genericCashTransactionId?: number | null
  disbursedBy?: string | null
  disbursedAt?: string | null
  createdBy?: string | null
  createdAt: string
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface GenericEmployeeLoanPage {
  items: GenericEmployeeLoan[]
  totalCount: number
}

export interface GenericEmployeeLoanRepayment {
  genericEmployeeLoanRepaymentId: number
  genericEmployeeLoanId: number
  genericStaffId: number
  staffName?: string | null
  repaymentNumber?: string | null
  repaymentDate: string
  amount: number
  principalAmount: number
  interestAmount: number
  sourceType: string
  genericPayrollRunId?: number | null
  payrollPeriodStart?: string | null
  payrollPeriodEnd?: string | null
  genericPayrollItemId?: number | null
  genericCashAccountId?: number | null
  cashAccountName?: string | null
  paymentMethod?: string | null
  referenceNumber?: string | null
  description?: string | null
  notes?: string | null
  balanceBefore: number
  balanceAfter: number
  status: string
  genericCashTransactionId?: number | null
  reversalCashTransactionId?: number | null
  createdBy?: string | null
  createdAt: string
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface GenericEmployeeLoanSummary {
  outstandingTotal: number
  disbursedInPeriod: number
  repaidInPeriod: number
  activeLoans: number
  staffWithActiveLoans: number
  paidLoans: number
  draftLoans: number
}

export interface GenericEmployeeLoanEligible {
  genericEmployeeLoanId: number
  loanNumber?: string | null
  loanType: string
  outstandingBalance: number
  defaultPayrollDeduction?: number | null
  repaymentMethod?: string | null
  disbursementDate: string
}

export interface GenericEmployeeLoanFilter {
  staffId?: number | null
  loanType?: string | null
  status?: string | null
  repaymentMethod?: string | null
  fromDate?: string | null
  toDate?: string | null
  search?: string | null
  limit?: number
  offset?: number
}

// =============================================================================
// Reads
// =============================================================================

export const listGenericEmployeeLoans = (f: GenericEmployeeLoanFilter = {}) => {
  const q = new URLSearchParams({ farmId: activeFarmId() })
  if (f.staffId) q.set("staffId", String(f.staffId))
  if (f.loanType) q.set("loanType", f.loanType)
  if (f.status) q.set("status", f.status)
  if (f.repaymentMethod) q.set("repaymentMethod", f.repaymentMethod)
  if (f.fromDate) q.set("fromDate", f.fromDate)
  if (f.toDate) q.set("toDate", f.toDate)
  if (f.search?.trim()) q.set("search", f.search.trim())
  q.set("limit", String(f.limit ?? 50))
  q.set("offset", String(f.offset ?? 0))
  return jget<GenericEmployeeLoanPage>(`/Generic/employee-loans?${q.toString()}`)
}

export const getGenericEmployeeLoanSummary = (fromDate?: string, toDate?: string) => {
  const q = new URLSearchParams({ farmId: activeFarmId() })
  if (fromDate) q.set("fromDate", fromDate)
  if (toDate) q.set("toDate", toDate)
  return jget<GenericEmployeeLoanSummary>(`/Generic/employee-loans/summary?${q.toString()}`)
}

export const getGenericEmployeeLoan = (id: number) =>
  jget<GenericEmployeeLoan>(`/Generic/employee-loans/${id}?farmId=${fid()}`)

export const listGenericEmployeeLoanRepayments = (loanId: number) =>
  jget<GenericEmployeeLoanRepayment[]>(
    `/Generic/employee-loans/${loanId}/repayments?farmId=${fid()}`)

export const listEligibleGenericEmployeeLoans = (staffId: number) =>
  jget<GenericEmployeeLoanEligible[]>(
    `/Generic/employee-loans/eligible?farmId=${fid()}&staffId=${staffId}`)

// =============================================================================
// Writes
// =============================================================================

export interface GenericEmployeeLoanInput {
  genericStaffId: number
  principalAmount: number
  disbursementDate: string
  loanType?: string
  interestEnabled?: boolean
  interestAmount?: number | null
  interestRate?: number | null
  interestType?: string | null
  repaymentMethod?: string
  defaultPayrollDeduction?: number | null
  expectedStartDate?: string | null
  expectedEndDate?: string | null
  purpose?: string | null
  description?: string | null
  notes?: string | null
  disburseNow?: boolean
  genericCashAccountId?: number | null
  paymentMethod?: string | null
  referenceNumber?: string | null
}

export const createGenericEmployeeLoan = (input: GenericEmployeeLoanInput) =>
  jsend<{ genericEmployeeLoanId: number }>(`/Generic/employee-loans`, "POST", {
    ...input,
    farmId: activeFarmId(),
    createdBy: currentUserId() || null,
  })

export const updateGenericEmployeeLoan = (
  id: number, input: Partial<GenericEmployeeLoanInput>,
) =>
  jsend<void>(`/Generic/employee-loans/${id}`, "PUT", {
    ...input,
    farmId: activeFarmId(),
    updatedBy: currentUserId() || null,
  })

export const disburseGenericEmployeeLoan = (
  id: number,
  input: {
    genericCashAccountId: number
    paymentMethod?: string | null
    referenceNumber?: string | null
  },
) =>
  jsend<void>(`/Generic/employee-loans/${id}/disburse`, "POST", {
    ...input,
    farmId: activeFarmId(),
    disbursedBy: currentUserId() || null,
  })

export const cancelGenericEmployeeLoan = (id: number, reason?: string | null) =>
  jsend<void>(`/Generic/employee-loans/${id}/cancel`, "POST", {
    farmId: activeFarmId(), reason: reason ?? null, actionBy: currentUserId() || null,
  })

export const reverseGenericEmployeeLoan = (id: number, reason?: string | null) =>
  jsend<void>(`/Generic/employee-loans/${id}/reverse`, "POST", {
    farmId: activeFarmId(), reason: reason ?? null, actionBy: currentUserId() || null,
  })

export interface GenericEmployeeLoanRepaymentInput {
  genericEmployeeLoanId: number
  amount: number
  sourceType?: string
  principalAmount?: number | null
  interestAmount?: number | null
  repaymentDate?: string | null
  genericCashAccountId?: number | null
  paymentMethod?: string | null
  referenceNumber?: string | null
  description?: string | null
  notes?: string | null
}

export const recordGenericEmployeeLoanRepayment = (input: GenericEmployeeLoanRepaymentInput) =>
  jsend<{ genericEmployeeLoanRepaymentId: number }>(
    `/Generic/employee-loans/repayments`, "POST", {
      ...input,
      farmId: activeFarmId(),
      createdBy: currentUserId() || null,
    })

export const reverseGenericEmployeeLoanRepayment = (
  repaymentId: number, reason?: string | null,
) =>
  jsend<void>(`/Generic/employee-loans/repayments/${repaymentId}/reverse`, "POST", {
    farmId: activeFarmId(), reason: reason ?? null, actionBy: currentUserId() || null,
  })
