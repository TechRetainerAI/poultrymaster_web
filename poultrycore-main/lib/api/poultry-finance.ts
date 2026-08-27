// Poultry Cash Accounts + Staff + Attendance + Payroll API client.
// Port of the Water finance/HR client (lib/api/water.ts), poultry-scoped:
// endpoints live under /Poultry/* on the Farm API. FarmId + userId come from
// getUserContext(). Grouped in one module the same way water.ts is.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

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

// =============================================================================
// Cash Accounts
// =============================================================================
export const POULTRY_CASH_ACCOUNT_TYPES = [
  "FarmCashBox", "OwnerCash", "MoMoWallet", "BankAccount", "PettyCash", "Other",
] as const

export interface PoultryCashAccount {
  poultryCashAccountId: number
  farmId: string
  accountName: string
  accountType: string
  openingBalance: number
  currentBalance: number
  allowNegativeBalance: boolean
  isActive: boolean
  notes?: string | null
}

export interface PoultryCashTransaction {
  poultryCashTransactionId: number
  farmId: string
  poultryCashAccountId: number
  accountName?: string | null
  transactionDate: string
  transactionType: string
  sourceType?: string | null
  sourceId?: number | null
  amount: number
  balanceAfterTransaction?: number | null
  description?: string | null
  createdBy?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
  createdAt: string
  // Migration 223. Returned only by the ledger read; null on any older path.
  clearingStatus?: PoultryClearingStatus | null
  clearedDate?: string | null
  clearedBy?: string | null
  poultryCashReconciliationId?: number | null
  clearingNotes?: string | null
  reconciliationReference?: string | null
}

export interface PoultryCashTransfer {
  poultryCashTransferId: number
  farmId: string
  fromPoultryCashAccountId: number
  fromAccountName?: string | null
  toPoultryCashAccountId: number
  toAccountName?: string | null
  transferDate: string
  amount: number
  status: "Draft" | "Approved" | "Cancelled" | string
  notes?: string | null
}

export interface PoultryCashAccountInput {
  accountName: string
  accountType: string
  openingBalance?: number
  allowNegativeBalance?: boolean
  isActive?: boolean
  notes?: string | null
}

export const listPoultryCashAccounts = () =>
  jget<PoultryCashAccount[]>(`/Poultry/cash-accounts?farmId=${fid()}`)

export const getPoultryCashAccount = (id: number) =>
  jget<PoultryCashAccount>(`/Poultry/cash-accounts/${id}?farmId=${fid()}`)

export const createPoultryCashAccount = (input: PoultryCashAccountInput) =>
  jsend<{ poultryCashAccountId: number }>(`/Poultry/cash-accounts`, "POST", { ...input, farmId: activeFarmId() })

export const updatePoultryCashAccount = (id: number, input: PoultryCashAccountInput) =>
  jsend<void>(`/Poultry/cash-accounts/${id}`, "PUT", { ...input, poultryCashAccountId: id, farmId: activeFarmId() })

export const deletePoultryCashAccount = (id: number) =>
  jsend<void>(`/Poultry/cash-accounts/${id}?farmId=${fid()}`, "DELETE")

export const reconcilePoultryCashBalances = () =>
  jsend<void>(`/Poultry/cash-accounts/reconcile-balances?farmId=${fid()}`, "POST")

export const adjustPoultryCashAccount = (id: number, input: { amount: number; reason: string }) =>
  jsend<void>(`/Poultry/cash-accounts/${id}/adjust?farmId=${fid()}`, "POST",
    { amount: input.amount, reason: input.reason, createdBy: currentUserId() || null })

export const listPoultryCashTransactions = (opts?: {
  cashAccountId?: number; fromDate?: string; toDate?: string; clearingStatus?: PoultryClearingStatus
}) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.cashAccountId != null) qs.set("cashAccountId", String(opts.cashAccountId))
  if (opts?.fromDate) qs.set("fromDate", opts.fromDate)
  if (opts?.toDate) qs.set("toDate", opts.toDate)
  if (opts?.clearingStatus) qs.set("clearingStatus", opts.clearingStatus)
  return jget<PoultryCashTransaction[]>(`/Poultry/cash-accounts/transactions?${qs.toString()}`)
}

// ----- Cash count / reconciliation (migration 223)
/**
 * A CASH COUNT: what was physically counted (or read off the bank/MoMo app)
 * against what the ledger says, with the difference posted as an adjustment.
 *
 * Not to be confused with `reconcilePoultryCashBalances()` further up, which
 * recomputes the cached balance from the ledger and moves no money. The API
 * keeps them on separate routes for the same reason.
 */
export type PoultryClearingStatus = "Uncleared" | "Cleared" | "Disputed"
export type PoultryCashCountStatus = "Draft" | "Posted" | "Reversed"

/** Why the count differed. Stored as text, so keep these strings stable. */
export const POULTRY_CASH_REASONS = [
  { value: "Cash shortage",                 label: "Cash shortage" },
  { value: "Cash overage",                  label: "Cash overage" },
  { value: "Bank charge",                   label: "Bank charge" },
  { value: "MoMo charge",                   label: "MoMo charge" },
  { value: "Unrecorded expense",            label: "Unrecorded expense" },
  { value: "Unrecorded income",             label: "Unrecorded income" },
  { value: "Wrong cash account used",       label: "Wrong cash account used" },
  { value: "Owner draw not recorded",       label: "Owner draw not recorded" },
  { value: "Owner contribution not recorded", label: "Owner contribution not recorded" },
  { value: "Driver shortage",               label: "Driver shortage" },
  { value: "Driver overage",                label: "Driver overage" },
  { value: "Rounding difference",           label: "Rounding difference" },
  { value: "Opening balance correction",    label: "Opening balance correction" },
  { value: "Other",                         label: "Other" },
] as const

/**
 * Why money moved between two of the company's own accounts.
 *
 * Deliberately NOT the same list as POULTRY_CASH_REASONS: a transfer is not a
 * correction, so shortage/overage/unrecorded-expense make no sense here, and
 * offering them would invite miscategorising a routine deposit as a loss.
 * Stored in the transfer's notes column, so keep the strings stable.
 */
export const POULTRY_CASH_TRANSFER_REASONS = [
  { value: "Bank deposit",            label: "Bank deposit" },
  { value: "Bank withdrawal",         label: "Bank withdrawal" },
  { value: "MoMo cash-out",           label: "MoMo cash-out" },
  { value: "MoMo top-up",             label: "MoMo top-up" },
  { value: "Driver float issued",     label: "Driver float issued" },
  { value: "Driver float returned",   label: "Driver float returned" },
  { value: "Petty cash top-up",       label: "Petty cash top-up" },
  { value: "Funding payroll",         label: "Funding payroll" },
  { value: "Funding supplier payment", label: "Funding supplier payment" },
  { value: "Consolidating balances",  label: "Consolidating balances" },
  { value: "Safe keeping",            label: "Safe keeping" },
  { value: "Other",                   label: "Other" },
] as const

/**
 * Why a POSTED count is being undone.
 *
 * A third list, deliberately. POULTRY_CASH_REASONS says why the cash
 * differed; this says why the count itself should never have been posted. They
 * are not interchangeable — "Bank charge" is a fine reason for a shortage and a
 * nonsensical reason for a reversal, and offering it here would put a
 * cash-explanation into the reversalreason column where an audit later reads it
 * as one. Stored as text, so keep these strings stable.
 */
export const POULTRY_CASH_REVERSAL_REASONS = [
  { value: "Counted the wrong account", label: "Counted the wrong account" },
  { value: "Miscounted",                label: "Miscounted" },
  { value: "Wrong amount entered",      label: "Wrong amount entered" },
  { value: "Wrong date",                label: "Wrong date" },
  { value: "Duplicate count",           label: "Duplicate count" },
  { value: "Posted by mistake",         label: "Posted by mistake" },
  { value: "Cash located afterwards",   label: "Cash located afterwards" },
  { value: "Test or training entry",    label: "Test or training entry" },
  { value: "Other",                     label: "Other" },
] as const


export interface PoultryCashCount {
  poultryCashReconciliationId: number
  farmId: string
  poultryCashAccountId: number
  accountName?: string | null
  accountType?: string | null
  referenceNo?: string | null
  reconciliationDate: string
  /** Ledger truth: opening balance + sum of transactions. */
  systemBalance: number
  /** What the cached balance claimed at post time — differs only when this
   *  count healed a drifted cache. */
  systemBalanceCached?: number | null
  /** Null while drafting; 0 is a legitimate count. */
  actualBalance?: number | null
  difference: number
  adjustmentTransactionId?: number | null
  reversalTransactionId?: number | null
  clearedCount: number
  clearedAmount: number
  reason?: string | null
  notes?: string | null
  status: PoultryCashCountStatus
  createdBy?: string | null
  createdAt: string
  updatedAt?: string | null
  postedBy?: string | null
  postedAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface PoultryCashAccountCountStatus {
  poultryCashAccountId: number
  accountName: string
  accountType?: string | null
  isActive: boolean
  currentBalance: number
  ledgerBalance: number
  cacheDrift: number
  lastReconciledAt?: string | null
  lastReconciledBalance?: number | null
  daysSinceReconciled?: number | null
  unclearedCount: number
  unclearedAmount: number
  openDraftId?: number | null
}

export const listPoultryCashCounts = (opts?: {
  cashAccountId?: number; status?: PoultryCashCountStatus; fromDate?: string; toDate?: string
}) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.cashAccountId) qs.append("cashAccountId", String(opts.cashAccountId))
  if (opts?.status) qs.append("status", opts.status)
  if (opts?.fromDate) qs.append("fromDate", opts.fromDate)
  if (opts?.toDate) qs.append("toDate", opts.toDate)
  return jget<PoultryCashCount[]>(`/Poultry/cash-reconciliations?${qs.toString()}`)
}

export const listPoultryCashCountsForAccount = (cashAccountId: number) =>
  jget<PoultryCashCount[]>(
    `/Poultry/cash-reconciliations/account/${cashAccountId}?farmId=${fid()}`)

export const getPoultryCashAccountCountStatus = () =>
  jget<PoultryCashAccountCountStatus[]>(
    `/Poultry/cash-reconciliations/account-status?farmId=${fid()}`)

export const createPoultryCashCount = (input: {
  poultryCashAccountId: number; reconciliationDate?: string
  actualBalance?: number | null; reason?: string | null; notes?: string | null
}) =>
  jsend<{ poultryCashReconciliationId: number }>(
    `/Poultry/cash-reconciliations?farmId=${fid()}`,
    "POST", { ...input, createdBy: currentUserId() || null })

export const updatePoultryCashCount = (id: number, input: {
  reconciliationDate?: string; actualBalance?: number | null
  reason?: string | null; notes?: string | null
}) =>
  jsend<void>(`/Poultry/cash-reconciliations/${id}?farmId=${fid()}`,
    "PUT", { ...input, createdBy: currentUserId() || null })

export const deletePoultryCashCount = (id: number) =>
  jsend<void>(
    `/Poultry/cash-reconciliations/${id}?farmId=${fid()}` +
    `&userId=${encodeURIComponent(currentUserId() || "")}`, "DELETE")

/** Returns the adjustment transaction id, or null when the count balanced. */
export const postPoultryCashCount = (id: number, clearedTransactionIds?: number[]) =>
  jsend<{ adjustmentTransactionId: number | null }>(
    `/Poultry/cash-reconciliations/${id}/post?farmId=${fid()}`,
    "POST", { clearedTransactionIds: clearedTransactionIds ?? [], postedBy: currentUserId() || null })

export const reversePoultryCashCount = (id: number, reason?: string) =>
  jsend<void>(
    `/Poultry/cash-reconciliations/${id}/reverse?farmId=${fid()}`,
    "POST", { reason, reversedBy: currentUserId() || null })

export const setPoultryCashClearing = (input: {
  poultryCashAccountId: number; transactionIds: number[]
  clearingStatus: PoultryClearingStatus; clearingNotes?: string
}) =>
  jsend<{ updated: number }>(
    `/Poultry/cash-reconciliations/clearing?farmId=${fid()}`,
    "POST", { ...input, userId: currentUserId() || null })

// ----- Cash transfers
export const listPoultryCashTransfers = (status?: string) =>
  jget<PoultryCashTransfer[]>(`/Poultry/cash-transfers?farmId=${fid()}${status ? `&status=${encodeURIComponent(status)}` : ""}`)

export const createPoultryCashTransfer = (input: {
  fromPoultryCashAccountId: number; toPoultryCashAccountId: number; amount: number
  transferDate?: string | null; notes?: string | null
}) =>
  jsend<{ poultryCashTransferId: number }>(`/Poultry/cash-transfers`, "POST",
    { ...input, farmId: activeFarmId(), createdBy: currentUserId() || null })

export const approvePoultryCashTransfer = (id: number) =>
  jsend<void>(`/Poultry/cash-transfers/${id}/approve?farmId=${fid()}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")

export const cancelPoultryCashTransfer = (id: number) =>
  jsend<void>(`/Poultry/cash-transfers/${id}/cancel?farmId=${fid()}`, "POST")

// =============================================================================
// Staff
// =============================================================================
export const POULTRY_STAFF_ROLES = [
  "FarmManager", "Supervisor", "FarmHand", "VaccinatorHealth", "FeedMillOperator",
  "EggCollector", "Salesperson", "Accountant", "Cleaner", "Security", "Driver", "Other",
] as const

export const POULTRY_STAFF_SALARY_TYPES = ["Daily", "Weekly", "Monthly", "Commission", "Mixed"] as const

export interface PoultryStaff {
  poultryStaffId: number
  farmId: string
  firstName: string
  lastName: string
  phoneNumber?: string | null
  email?: string | null
  role: string
  salaryType: string
  basePay: number
  commissionRate?: number | null
  isActive: boolean
  isDeleted: boolean
  notes?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface PoultryStaffInput {
  firstName: string
  lastName: string
  phoneNumber?: string | null
  email?: string | null
  role: string
  salaryType: string
  basePay: number
  commissionRate?: number | null
  isActive?: boolean
  notes?: string | null
}

export const listPoultryStaff = (role?: string) =>
  jget<PoultryStaff[]>(`/Poultry/staff?farmId=${fid()}${role ? `&role=${encodeURIComponent(role)}` : ""}`)

export const getPoultryStaff = (id: number) =>
  jget<PoultryStaff>(`/Poultry/staff/${id}?farmId=${fid()}`)

export const createPoultryStaff = (input: PoultryStaffInput) =>
  jsend<PoultryStaff>(`/Poultry/staff`, "POST", { ...input, farmId: activeFarmId() })

export const updatePoultryStaff = (id: number, input: PoultryStaffInput) =>
  jsend<void>(`/Poultry/staff/${id}`, "PUT", { ...input, poultryStaffId: id, farmId: activeFarmId() })

export const deletePoultryStaff = (id: number) =>
  jsend<void>(`/Poultry/staff/${id}?farmId=${fid()}`, "DELETE")

// =============================================================================
// Attendance
// =============================================================================
export const POULTRY_ATTENDANCE_STATUS = ["Present", "Absent", "Late", "HalfDay", "OffDay"] as const

export interface PoultryStaffAttendance {
  poultryStaffAttendanceId: number
  farmId: string
  poultryStaffId: number
  staffName?: string | null
  attendanceDate: string
  clockIn?: string | null
  clockOut?: string | null
  shift?: string | null
  status: string
  notes?: string | null
  createdBy?: string | null
  createdAt: string
}

export interface PoultryStaffAttendanceInput {
  poultryStaffId: number
  attendanceDate: string
  clockIn?: string | null
  clockOut?: string | null
  shift?: string | null
  status: string
  notes?: string | null
}

export const listPoultryStaffAttendance = (opts?: { staffId?: number; fromDate?: string; toDate?: string }) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.staffId != null) qs.set("staffId", String(opts.staffId))
  if (opts?.fromDate) qs.set("fromDate", opts.fromDate)
  if (opts?.toDate) qs.set("toDate", opts.toDate)
  return jget<PoultryStaffAttendance[]>(`/Poultry/staff-attendance?${qs.toString()}`)
}

export const upsertPoultryStaffAttendance = (input: PoultryStaffAttendanceInput) =>
  jsend<PoultryStaffAttendance>(
    `/Poultry/staff-attendance?farmId=${fid()}&createdBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST", input)

export const deletePoultryStaffAttendance = (id: number) =>
  jsend<void>(`/Poultry/staff-attendance/${id}?farmId=${fid()}`, "DELETE")

// =============================================================================
// Payroll
// =============================================================================
export const POULTRY_PAYMENT_METHODS = ["Cash", "MoMo", "Bank"] as const

export interface PoultryPayrollItem {
  poultryPayrollItemId: number
  poultryPayrollRunId: number
  poultryStaffId: number
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

export interface PoultryPayrollRun {
  poultryPayrollRunId: number
  farmId: string
  periodStart: string
  periodEnd: string
  payDate?: string | null
  totalGrossPay: number
  totalDeductions: number
  totalNetPay: number
  status: "Draft" | "Approved" | "Paid" | "Reopened" | "Cancelled" | string
  poultryCashAccountId?: number | null
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
  items?: PoultryPayrollItem[]
}

export interface PoultryPayrollYtdTotals {
  year: number
  ytdGrossPaid: number
  ytdDeductions: number
  ytdNetPaid: number
  totalPayrollRuns: number
  totalStaffPaid: number
}

export interface PoultryPayrollYtdStaffRow {
  poultryStaffId: number
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

export interface PoultryPayrollLinkedExpense {
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

export interface PoultryPayrollRunDetails {
  run: PoultryPayrollRun | null
  ytdTotals: PoultryPayrollYtdTotals | null
  ytdByStaff: PoultryPayrollYtdStaffRow[]
  linkedExpense: PoultryPayrollLinkedExpense | null
}

export const listPoultryPayrollRuns = (status?: string) =>
  jget<PoultryPayrollRun[]>(`/Poultry/payroll-runs?farmId=${fid()}${status ? `&status=${encodeURIComponent(status)}` : ""}`)

export const getPoultryPayrollRun = (id: number) =>
  jget<PoultryPayrollRun>(`/Poultry/payroll-runs/${id}?farmId=${fid()}`)

export const getPoultryPayrollRunDetails = (id: number) =>
  jget<PoultryPayrollRunDetails>(`/Poultry/payroll-runs/${id}/details?farmId=${fid()}`)

export const createPoultryPayrollRun = (input: {
  periodStart: string; periodEnd: string; payDate?: string | null
  poultryCashAccountId?: number | null; notes?: string | null
}) =>
  jsend<{ poultryPayrollRunId: number }>(
    `/Poultry/payroll-runs?createdBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST", { ...input, farmId: activeFarmId() })

export const upsertPoultryPayrollItem = (runId: number, input: {
  poultryStaffId: number; basicPay: number; dailyWage: number; commission: number
  bonus: number; deductions: number; paymentMethod?: string | null; notes?: string | null
}) =>
  jsend<PoultryPayrollItem>(`/Poultry/payroll-runs/${runId}/items?farmId=${fid()}`, "POST", input)

export const deletePoultryPayrollItem = (itemId: number) =>
  jsend<void>(`/Poultry/payroll-runs/items/${itemId}?farmId=${fid()}`, "DELETE")

export const approvePoultryPayrollRun = (id: number) =>
  jsend<void>(`/Poultry/payroll-runs/${id}/approve?farmId=${fid()}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")

export const markPoultryPayrollRunPaid = (id: number, payDate?: string) =>
  jsend<void>(`/Poultry/payroll-runs/${id}/mark-paid?farmId=${fid()}&paidBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST", { payDate: payDate ?? null })

export const cancelPoultryPayrollRun = (id: number, reason?: string) =>
  jsend<void>(`/Poultry/payroll-runs/${id}/cancel?farmId=${fid()}&cancelledBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST", { reason: reason ?? null })

export const unapprovePoultryPayrollRun = (id: number, reason: string) =>
  jsend<void>(`/Poultry/payroll-runs/${id}/unapprove?farmId=${fid()}&reopenedBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST", { reason })

export const deletePoultryPayrollRun = (id: number) =>
  jsend<void>(`/Poultry/payroll-runs/${id}?farmId=${fid()}&deletedBy=${encodeURIComponent(currentUserId() || "")}`, "DELETE")

// ----- Customer payments (partial payments against a sale) --------------------
// Port of the Water payment client (lib/api/water.ts).
export interface PoultryPayment {
  poultryPaymentId: number
  farmId: string
  saleId: number
  amount: number
  paymentMethod?: string | null
  paymentDate: string
  reference?: string | null
  note?: string | null
  createdDate: string
  createdBy?: string | null
  customerName?: string | null
}

export interface PoultryPaymentInput {
  saleId: number
  amount: number
  paymentMethod?: string | null
  paymentDate?: string | null
  reference?: string | null
  note?: string | null
}

export const listPoultryPayments = () =>
  jget<PoultryPayment[]>(`/Poultry/payments?farmId=${fid()}`)

export const listPoultryPaymentsBySale = (saleId: number) =>
  jget<PoultryPayment[]>(`/Poultry/payments/by-sale/${saleId}?farmId=${fid()}`)

export const recordPoultryPayment = (input: PoultryPaymentInput) =>
  jsend<{ poultryPaymentId: number }>(`/Poultry/payments`, "POST", {
    ...input,
    farmId: activeFarmId(),
    createdBy: currentUserId() || null,
  })
