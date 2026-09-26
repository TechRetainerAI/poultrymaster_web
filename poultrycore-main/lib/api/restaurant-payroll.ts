import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "./config"

// =============================================================================
// Restaurant payroll and staff loans & advances — API module (migration 326)
//
// Every money step runs inside one database function and posts through the
// restaurant cash ledger (migration 323): paying out an advance, a cash
// repayment, approving a payroll run (loan deductions become repayments) and
// marking it paid (net pay leaves the till/cash box). Refusals — a closed day,
// an over-deduction, a future date — come back as 400 with a plain sentence,
// which these helpers throw as the Error message.
//
// The staff loans here are money LENT TO STAFF. Money the restaurant borrowed
// lives in restaurant-finance.ts (listLoans / repayLoan) and the Loans page.
// =============================================================================

function farmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

function url(path: string, query: Record<string, string | number | undefined | null> = {}): string {
  const q = new URLSearchParams({ farmId: farmId() })
  for (const [k, v] of Object.entries(query)) if (v !== undefined && v !== null && v !== "") q.set(k, String(v))
  return farmApiUrl(`/Restaurant${path}?${q.toString()}`)
}

async function get<T>(path: string, query?: Record<string, string | number | undefined | null>): Promise<T> {
  const res = await fetch(url(path, query), { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

async function send<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(url(path), { method, headers: getAuthHeaders(), body: body ? JSON.stringify(body) : undefined })
  if (!res.ok) throw new Error(await readApiError(res))
  const text = await res.text()
  return text ? JSON.parse(text) : ({} as T)
}

// ----- Vocabulary -----------------------------------------------------------

export const STAFF_LOAN_TYPES = [
  { value: "SalaryAdvance", label: "Salary advance" },
  { value: "EmployeeLoan", label: "Staff loan" },
  { value: "OtherAdvance", label: "Other advance" },
] as const

/** PayrollDeduction and Mixed are the methods payroll suggests a deduction for. */
export const STAFF_LOAN_METHODS = [
  { value: "PayrollDeduction", label: "Deduct from payroll" },
  { value: "Mixed", label: "Payroll and cash" },
  { value: "Cash", label: "Cash" },
  { value: "MoMo", label: "Mobile money" },
  { value: "Bank", label: "Bank" },
  { value: "Other", label: "Other" },
] as const

/** For a repayment handed back directly. Payroll repayments only come from approving a run. */
export const STAFF_LOAN_REPAY_SOURCES = [
  { value: "Cash", label: "Cash" },
  { value: "MoMo", label: "Mobile money" },
  { value: "Bank", label: "Bank" },
  { value: "Other", label: "Other" },
] as const

export const staffLoanTypeLabel = (v: string) => STAFF_LOAN_TYPES.find((t) => t.value === v)?.label ?? v
export const staffLoanMethodLabel = (v: string) => STAFF_LOAN_METHODS.find((t) => t.value === v)?.label ?? v
export const staffLoanSourceLabel = (v: string) =>
  v === "Payroll" ? "Payroll deduction" : STAFF_LOAN_REPAY_SOURCES.find((t) => t.value === v)?.label ?? v

// ----- Types ----------------------------------------------------------------

export interface StaffLoan {
  staffLoanId: number; restaurantStaffId: number; staffName?: string | null; staffIsActive: boolean
  loanNumber: string; loanType: string; status: string
  principalAmount: number; interestAmount: number; totalRepayable: number
  totalPrincipalRepaid: number; totalInterestRepaid: number; outstandingBalance: number
  repaymentMethod: string; defaultPayrollDeduction: number
  disbursementDate?: string | null; expectedEndDate?: string | null
  cashAccountId?: number | null; cashAccountName?: string | null
  reference?: string | null; notes?: string | null; createdBy?: string | null; createdAt: string
  closedBy?: string | null; closedReason?: string | null; closedAt?: string | null
  repaymentCount: number; lastRepaymentDate?: string | null
  /** Already set to be deducted on draft payroll runs. */
  draftPayrollClaims: number
}

export interface StaffLoanRepayment {
  repaymentId: number; staffLoanId: number; loanNumber?: string | null
  restaurantStaffId: number; staffName?: string | null
  amount: number; principalAmount: number; interestAmount: number; sourceType: string
  cashAccountId?: number | null; cashAccountName?: string | null
  payrollRunId?: number | null; payrollRunNumber?: string | null
  balanceBefore: number; balanceAfter: number; repaymentDate: string
  reference?: string | null; notes?: string | null; status: string
  createdBy?: string | null; createdAt: string
  reversedBy?: string | null; reversedReason?: string | null; reversedAt?: string | null
}

export interface StaffLoanSummary {
  totalOutstanding: number; totalDisbursed: number; totalRepaid: number; activeCount: number
  staffWithLoans: number; draftCount: number; paidCount: number; interestEarned: number
  repaidViaPayroll: number; draftPayrollClaims: number
}

export interface StaffLoanEligible {
  staffLoanId: number; loanNumber: string; loanType: string; repaymentMethod: string
  outstandingBalance: number; defaultPayrollDeduction: number
  /** Already set aside on other draft payroll lines. */
  claimedElsewhere: number
  /** The most this payroll line may deduct. */
  available: number
  suggestedDeduction: number
  /** What this payroll line deducts today (0 if none). */
  currentDeduction: number
}

export interface StaffLoanStaffRow {
  restaurantStaffId: number; staffName?: string | null; role?: string | null; staffIsActive: boolean
  activeLoans: number; outstanding: number; disbursedInPeriod: number
  repaidCashInPeriod: number; repaidPayrollInPeriod: number; interestInPeriod: number
  lastRepaymentDate?: string | null; totalEver: number
}

export interface StaffLoanInput {
  restaurantStaffId: number; loanType: string; principalAmount: number; interestAmount: number
  repaymentMethod: string; defaultPayrollDeduction: number; expectedEndDate?: string | null
  reference?: string | null; notes?: string | null
  disburseNow: boolean; cashAccountId?: number | null; disbursementDate?: string | null
}

export interface StaffLoanUpdate {
  loanType: string; principalAmount: number; interestAmount: number; repaymentMethod: string
  defaultPayrollDeduction: number; expectedEndDate?: string | null; reference?: string | null; notes?: string | null
}

export interface PayrollRun {
  payrollRunId: number; runNumber: string; periodStart: string; periodEnd: string; payDate: string
  status: "Draft" | "Approved" | "Paid" | "Cancelled" | string
  cashAccountId?: number | null; cashAccountName?: string | null
  totalGross: number; totalDeductions: number; totalLoanDeductions: number; totalNet: number; lineCount: number
  notes?: string | null; createdBy?: string | null; createdAt: string
  approvedBy?: string | null; approvedAt?: string | null; paidBy?: string | null; paidAt?: string | null
  cancelledBy?: string | null; cancelReason?: string | null; reopenedBy?: string | null; reopenReason?: string | null
}

export interface PayrollLine {
  payrollLineId: number; payrollRunId: number; restaurantStaffId: number
  staffName?: string | null; staffRole?: string | null; salaryType?: string | null
  basicPay: number; allowances: number; overtime: number; bonus: number
  otherDeductions: number; loanDeductions: number; grossPay: number; netPay: number
  paymentMethod: string; notes?: string | null
}

export interface PayrollDeduction {
  payrollDeductionId: number; payrollLineId: number; restaurantStaffId: number; staffLoanId: number
  loanNumber?: string | null; loanType: string; deductionType: string; amount: number
  status: "Draft" | "Posted" | "Reversed" | string; repaymentId?: number | null; outstandingBalance: number
}

export interface PayrollRunDetail { run: PayrollRun; lines: PayrollLine[]; deductions: PayrollDeduction[] }

export interface PayrollRunInput {
  periodStart: string; periodEnd: string; payDate?: string | null; cashAccountId?: number | null; notes?: string | null
}

export interface PayrollLineInput {
  restaurantStaffId: number; basicPay: number; allowances: number; overtime: number; bonus: number
  /** Tax, penalties and the like. Staff loan repayments go in loanDeductions. */
  otherDeductions: number; paymentMethod?: string; notes?: string | null
  /** Omit to keep the line's loan deductions; a list replaces them (empty removes all). */
  loanDeductions?: { loanId: number; amount: number }[]
}

export interface PayrollReportRow {
  restaurantStaffId: number; staffName?: string | null; staffRole?: string | null; runs: number
  basicPay: number; extras: number; grossPay: number; otherDeductions: number; loanDeductions: number; netPay: number
}

// ----- Staff loans ----------------------------------------------------------

export const listStaffLoans = (status?: string, staffId?: number) =>
  get<StaffLoan[]>("/staff-loans", { status, staffId })
export const getStaffLoanSummary = (from?: string, to?: string) =>
  get<StaffLoanSummary>("/staff-loans/summary", { from, to })
export const listStaffLoanRepayments = (loanId?: number) =>
  get<StaffLoanRepayment[]>("/staff-loans/repayments", { loanId })
export const listEligibleStaffLoans = (staffId: number, excludeLineId?: number | null) =>
  get<StaffLoanEligible[]>("/staff-loans/eligible", { staffId, excludeLineId })
export const getStaffLoanStaffReport = (from?: string, to?: string) =>
  get<StaffLoanStaffRow[]>("/staff-loans/staff-report", { from, to })

export const createStaffLoan = (input: StaffLoanInput) =>
  send<{ staffLoanId: number }>("POST", "/staff-loans", input)
export const updateStaffLoan = (id: number, input: StaffLoanUpdate) =>
  send<void>("PUT", `/staff-loans/${id}`, input)
export const disburseStaffLoan = (id: number, input: { cashAccountId?: number | null; disbursementDate?: string; reference?: string | null }) =>
  send<void>("POST", `/staff-loans/${id}/disburse`, input)
export const cancelStaffLoan = (id: number, reason: string) =>
  send<void>("POST", `/staff-loans/${id}/cancel`, { reason })
export const reverseStaffLoan = (id: number, reason: string) =>
  send<void>("POST", `/staff-loans/${id}/reverse`, { reason })
export const repayStaffLoan = (id: number, input: {
  amount: number; sourceType: string; cashAccountId?: number | null; repaymentDate?: string; reference?: string | null; notes?: string | null
}) => send<{ repaymentId: number }>("POST", `/staff-loans/${id}/repayments`, input)
export const reverseStaffLoanRepayment = (repaymentId: number, reason: string) =>
  send<void>("POST", `/staff-loans/repayments/${repaymentId}/reverse`, { reason })

// ----- Payroll --------------------------------------------------------------

export const listPayrollRuns = (status?: string) => get<PayrollRun[]>("/payroll/runs", { status })
export const getPayrollRun = (id: number) => get<PayrollRunDetail>(`/payroll/runs/${id}`)
export const createPayrollRun = (input: PayrollRunInput) =>
  send<{ payrollRunId: number }>("POST", "/payroll/runs", input)
export const updatePayrollRun = (id: number, input: PayrollRunInput) => send<void>("PUT", `/payroll/runs/${id}`, input)
export const deletePayrollRun = (id: number) => send<void>("DELETE", `/payroll/runs/${id}`)
export const savePayrollLine = (runId: number, input: PayrollLineInput) =>
  send<{ payrollLineId: number }>("POST", `/payroll/runs/${runId}/lines`, input)
export const deletePayrollLine = (lineId: number) => send<void>("DELETE", `/payroll/lines/${lineId}`)
export const addAllStaffToPayroll = (runId: number) =>
  send<{ added: number }>("POST", `/payroll/runs/${runId}/add-all-staff`)
export const approvePayrollRun = (id: number) =>
  send<{ loanRepaymentsPosted: number }>("POST", `/payroll/runs/${id}/approve`)
export const reopenPayrollRun = (id: number, reason: string) =>
  send<{ repaymentsReversed: number }>("POST", `/payroll/runs/${id}/reopen`, { reason })
export const cancelPayrollRun = (id: number, reason: string) =>
  send<{ repaymentsReversed: number }>("POST", `/payroll/runs/${id}/cancel`, { reason })
export const markPayrollRunPaid = (id: number, input: { payDate?: string; cashAccountId?: number | null }) =>
  send<void>("POST", `/payroll/runs/${id}/mark-paid`, input)
export const getPayrollReport = (from: string, to: string) =>
  get<PayrollReportRow[]>("/payroll/report", { from, to })
