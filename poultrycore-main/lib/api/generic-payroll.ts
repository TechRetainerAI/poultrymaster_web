// Generic payroll (migration 451): the Poultry payroll client
// (lib/api/poultry-finance.ts, payroll + templates + deductions) on
// api/Generic/payroll-runs, payroll-templates and payroll-deductions. Same
// shapes, generic ids. Shared constants and helpers are Poultry's, re-exported.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"
import { getCashAccounts, getStaff, type GenericCashAccount, type GenericStaff } from "./generic"

// ----- shared helpers (mirror water.ts) --------------------------------------
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

export {
  PAYROLL_FREQUENCIES, type PayrollFrequency, nextPayrollPeriod,
  PAYROLL_DEDUCTION_TYPES, PAYROLL_DEDUCTION_TYPE_LABELS,
} from "./poultry-finance"
export { listEligibleGenericEmployeeLoans, type GenericEmployeeLoanEligible } from "./generic-employee-loans"
export { getGenericEmployeeCreditTotal, type GenericEmployeeCreditTotal } from "./generic-employee-credit"

// Staff and cash accounts come from the Generic company API.
export type { GenericCashAccount, GenericStaff }
export const listGenericCashAccounts = (): Promise<GenericCashAccount[]> => getCashAccounts()
export const listGenericStaff = (): Promise<GenericStaff[]> => getStaff()

// =============================================================================
// Payroll
// =============================================================================
export const GENERIC_PAYMENT_METHODS = ["Cash", "MoMo", "Bank"] as const

export interface GenericPayrollItem {
  genericPayrollItemId: number
  genericPayrollRunId: number
  genericStaffId: number
  staffName?: string | null
  staffRole?: string | null
  basicPay: number
  dailyWage: number
  commission: number
  bonus: number
  deductions: number
  netPay: number
  paymentMethod?: string | null
  notes?: string | null
  createdAt: string
}

export interface GenericPayrollRun {
  genericPayrollRunId: number
  farmId: string
  periodStart: string
  periodEnd: string
  payDate?: string | null
  totalGrossPay: number
  totalDeductions: number
  totalNetPay: number
  status: "Draft" | "Approved" | "Paid" | "Reopened" | "Cancelled" | string
  genericCashAccountId?: number | null
  cashAccountName?: string | null
  notes?: string | null
  createdBy?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
  paidBy?: string | null
  paidAt?: string | null
  reopenedBy?: string | null
  reopenedAt?: string | null
  reopenReason?: string | null
  reapprovedBy?: string | null
  reapprovedAt?: string | null
  createdAt: string
  updatedAt?: string | null
  items?: GenericPayrollItem[]
}

export interface GenericPayrollYtdTotals {
  year: number
  ytdGrossPaid: number
  ytdDeductions: number
  ytdNetPaid: number
  totalPayrollRuns: number
  totalStaffPaid: number
}

export interface GenericPayrollYtdStaffRow {
  genericStaffId: number
  staffName?: string | null
  staffRole?: string | null
  ytdBasic: number
  ytdDaily: number
  ytdCommission: number
  ytdBonus: number
  ytdDeductions: number
  ytdGross: number
  ytdNet: number
}

export interface GenericPayrollLinkedExpense {
  expenseId: number
  farmId: string
  expenseDate: string
  category?: string | null
  description?: string | null
  amount: number
  paymentMethod?: string | null
  sourceType?: string | null
  sourceId?: number | null
  createdDate: string
}

export interface GenericPayrollRunDetails {
  run: GenericPayrollRun | null
  ytdTotals: GenericPayrollYtdTotals | null
  ytdByStaff: GenericPayrollYtdStaffRow[]
  linkedExpense: GenericPayrollLinkedExpense | null
}

export const listGenericPayrollRuns = (status?: string) =>
  jget<GenericPayrollRun[]>(`/Generic/payroll-runs?farmId=${fid()}${status ? `&status=${encodeURIComponent(status)}` : ""}`)

export const getGenericPayrollRun = (id: number) =>
  jget<GenericPayrollRun>(`/Generic/payroll-runs/${id}?farmId=${fid()}`)

export const getGenericPayrollRunDetails = (id: number) =>
  jget<GenericPayrollRunDetails>(`/Generic/payroll-runs/${id}/details?farmId=${fid()}`)

export const createGenericPayrollRun = (input: {
  periodStart: string; periodEnd: string; payDate?: string | null
  genericCashAccountId?: number | null; notes?: string | null
}) =>
  jsend<{ genericPayrollRunId: number }>(
    `/Generic/payroll-runs?createdBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST", { ...input, farmId: activeFarmId() })

export const upsertGenericPayrollItem = (runId: number, input: {
  genericStaffId: number; basicPay: number; dailyWage: number; commission: number
  bonus: number; deductions: number; paymentMethod?: string | null; notes?: string | null
  /** 442. The typed "Other deductions" only; when sent, `deductions` is ignored. */
  otherDeductions?: number | null
  /** 442. Wages kept as employee credit. null/undefined = leave as is, 0 = remove. */
  employeeCredit?: number | null
}) =>
  jsend<GenericPayrollItem>(`/Generic/payroll-runs/${runId}/items?farmId=${fid()}`, "POST", input)

export const deleteGenericPayrollItem = (itemId: number) =>
  jsend<void>(`/Generic/payroll-runs/items/${itemId}?farmId=${fid()}`, "DELETE")

export const approveGenericPayrollRun = (id: number) =>
  jsend<void>(`/Generic/payroll-runs/${id}/approve?farmId=${fid()}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")

export const markGenericPayrollRunPaid = (id: number, payDate?: string) =>
  jsend<void>(`/Generic/payroll-runs/${id}/mark-paid?farmId=${fid()}&paidBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST", { payDate: payDate ?? null })

export const cancelGenericPayrollRun = (id: number, reason?: string) =>
  jsend<void>(`/Generic/payroll-runs/${id}/cancel?farmId=${fid()}&cancelledBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST", { reason: reason ?? null })

export const unapproveGenericPayrollRun = (id: number, reason: string) =>
  jsend<void>(`/Generic/payroll-runs/${id}/unapprove?farmId=${fid()}&reopenedBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST", { reason })

export const deleteGenericPayrollRun = (id: number) =>
  jsend<void>(`/Generic/payroll-runs/${id}?farmId=${fid()}&deletedBy=${encodeURIComponent(currentUserId() || "")}`, "DELETE")

// ----- Payroll templates -------------------------------------------------------
// The standard payroll, set up once. Each period's run is created from it as a
// Draft and can still be adjusted; editing a template changes future runs only.
export interface GenericPayrollTemplateLine {
  genericPayrollTemplateLineId?: number
  genericStaffId: number
  staffName?: string | null
  staffRole?: string | null
  staffIsActive?: boolean
  basicPay: number
  dailyWage: number
  commission: number
  bonus: number
  deductions: number
  netPay?: number
  paymentMethod?: string | null
  notes?: string | null
}

export interface GenericPayrollTemplate {
  genericPayrollTemplateId: number
  name: string
  frequency: string
  genericCashAccountId?: number | null
  cashAccountName?: string | null
  notes?: string | null
  isActive: boolean
  lineCount: number
  staffInactiveCount: number
  totalGross: number
  totalDeductions: number
  totalNet: number
  runCount: number
  lastPeriodStart?: string | null
  lastPeriodEnd?: string | null
  createdBy?: string | null
  createdAt: string
  updatedBy?: string | null
  updatedAt?: string | null
  lines: GenericPayrollTemplateLine[]
}

export const listGenericPayrollTemplates = (includeInactive = false) =>
  jget<GenericPayrollTemplate[]>(`/Generic/payroll-templates?farmId=${fid()}&includeInactive=${includeInactive}`)

export const getGenericPayrollTemplate = (id: number) =>
  jget<GenericPayrollTemplate>(`/Generic/payroll-templates/${id}?farmId=${fid()}`)

export const saveGenericPayrollTemplate = (id: number | null, input: {
  name: string; frequency: string; genericCashAccountId?: number | null; notes?: string | null
  lines: GenericPayrollTemplateLine[]
}) =>
  jsend<{ genericPayrollTemplateId: number }>(
    id ? `/Generic/payroll-templates/${id}` : `/Generic/payroll-templates`,
    id ? "PUT" : "POST",
    {
      ...input, farmId: activeFarmId(), savedBy: currentUserId() || null,
      lines: input.lines.map((l) => ({
        genericStaffId: l.genericStaffId, basicPay: Number(l.basicPay) || 0, dailyWage: Number(l.dailyWage) || 0,
        commission: Number(l.commission) || 0, bonus: Number(l.bonus) || 0, deductions: Number(l.deductions) || 0,
        paymentMethod: l.paymentMethod || null, notes: l.notes || null,
      })),
    })

export const setGenericPayrollTemplateActive = (id: number, isActive: boolean) =>
  jsend<void>(`/Generic/payroll-templates/${id}/active`, "POST",
    { farmId: activeFarmId(), isActive, by: currentUserId() || null })

export const createGenericPayrollRunFromTemplate = (id: number, input: {
  periodStart: string; periodEnd: string; payDate?: string | null
  genericCashAccountId?: number | null; notes?: string | null
}) =>
  jsend<{ genericPayrollRunId: number }>(`/Generic/payroll-templates/${id}/create-run`, "POST",
    { ...input, farmId: activeFarmId(), createdBy: currentUserId() || null })

// -----------------------------------------------------------------------------
// Structured payroll deductions
// -----------------------------------------------------------------------------
export interface GenericPayrollDeduction {
  /** Null on the legacy row: it is the unexplained remainder, not a record. */
  genericPayrollItemDeductionId?: number | null
  genericPayrollItemId: number
  genericStaffId: number
  deductionType: string
  amount: number
  genericEmployeeLoanId?: number | null
  loanNumber?: string | null
  loanType?: string | null
  loanOutstanding?: number | null
  genericEmployeeLoanRepaymentId?: number | null
  description?: string | null
  reference?: string | null
  status: string
  isLegacy: boolean
  createdBy?: string | null
  createdAt?: string | null
}

export interface GenericPayrollDeductionRunRow {
  genericPayrollItemId: number
  genericStaffId: number
  staffName?: string | null
  deductions: number
  legacyDeductions: number
  structuredTotal: number
  structuredCount: number
  loanRepaymentTotal: number
  activeLoanCount: number
  activeLoanOutstanding: number
  /** What the worker's advances suggest. A suggestion: nothing posts from it. */
  suggestedDeduction: number
}

/** The breakdown behind one payslip line. The rows always add up to its total. */
export const listGenericPayrollDeductions = (payrollItemId: number) =>
  jget<GenericPayrollDeduction[]>(
    `/Generic/payroll-deductions?farmId=${fid()}&payrollItemId=${payrollItemId}`)

export const listGenericPayrollDeductionsForRun = (runId: number) =>
  jget<GenericPayrollDeductionRunRow[]>(
    `/Generic/payroll-deductions/run/${runId}?farmId=${fid()}`)

export interface GenericPayrollDeductionInput {
  genericPayrollItemId: number
  deductionType: string
  amount: number
  genericEmployeeLoanId?: number | null
  description?: string | null
  reference?: string | null
  genericPayrollItemDeductionId?: number | null
}

/** Unapproved runs only. Nothing here moves a balance -- approval does that. */
export const saveGenericPayrollDeduction = (input: GenericPayrollDeductionInput) =>
  jsend<{ genericPayrollItemDeductionId: number }>(
    `/Generic/payroll-deductions`, "POST", {
      ...input,
      farmId: activeFarmId(),
      savedBy: currentUserId() || null,
    })

export const deleteGenericPayrollDeduction = (deductionId: number) =>
  jsend<void>(
    `/Generic/payroll-deductions/${deductionId}?farmId=${fid()}` +
    `&deletedBy=${encodeURIComponent(currentUserId() || "")}`, "DELETE")
