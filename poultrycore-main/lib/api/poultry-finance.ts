// Poultry Cash Accounts + Staff + Attendance + Payroll API client.
// Port of the Water finance/HR client (lib/api/water.ts), poultry-scoped:
// endpoints live under /Poultry/* on the Farm API. FarmId + userId come from
// getUserContext(). Grouped in one module the same way water.ts is.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"
import { ledgerFromParam, ledgerToParam } from "@/lib/cash/cash-flow"

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
  /** TRF-2026-0001. Stamped on insert; older rows were backfilled by 252. */
  transferNumber?: string | null
  fromPoultryCashAccountId: number
  fromAccountName?: string | null
  toPoultryCashAccountId: number
  toAccountName?: string | null
  transferDate: string
  amount: number
  status: "Draft" | "Approved" | "Cancelled" | "Reversed" | string
  /** The bank's or wallet's own reference for the movement. */
  referenceNumber?: string | null
  notes?: string | null
  createdBy?: string | null
  approvedBy?: string | null
  approvedAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
  /** The two ledger rows approval wrote. Null until approved. */
  outgoingCashTransactionId?: number | null
  incomingCashTransactionId?: number | null
  createdAt?: string | null
  updatedAt?: string | null
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

/**
 * The ledger read.
 *
 * fromDate/toDate accept a plain yyyy-mm-dd and are widened to cover the whole
 * day. That is not a convenience — it is a correctness fix. The controller binds
 * toDate as a DateTime (PoultryCashControllers.cs:82) and the function compares
 * `t.transactiondate <= p_todate` (223_PoultryCashReconciliation.postgres.sql:862),
 * so a bare date means midnight and silently excludes everything recorded that
 * day. Asking for "Today" returned nothing at all.
 *
 * Normalised here rather than at each call site so every caller benefits and
 * nobody has to remember. lib/api/water.ts carries the same fix for the water
 * ledger; the water cash-flow REPORT that still had the unfixed version was
 * retired when /water-cash-flow replaced it.
 */
export const listPoultryCashTransactions = (opts?: {
  cashAccountId?: number; fromDate?: string; toDate?: string; clearingStatus?: PoultryClearingStatus
}) => {
  const qs = new URLSearchParams({ farmId: activeFarmId() })
  if (opts?.cashAccountId != null) qs.set("cashAccountId", String(opts.cashAccountId))
  if (opts?.fromDate) qs.set("fromDate", ledgerFromParam(opts.fromDate))
  if (opts?.toDate) qs.set("toDate", ledgerToParam(opts.toDate))
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
  transferDate?: string | null; notes?: string | null; referenceNumber?: string | null
}) =>
  jsend<{ poultryCashTransferId: number }>(`/Poultry/cash-transfers`, "POST",
    { ...input, farmId: activeFarmId(), createdBy: currentUserId() || null })

export const approvePoultryCashTransfer = (id: number) =>
  jsend<void>(`/Poultry/cash-transfers/${id}/approve?farmId=${fid()}&approvedBy=${encodeURIComponent(currentUserId() || "")}`, "POST")

// =============================================================================
// Loans (migration 254)
//
// Three rules the server enforces, restated because they are what these shapes
// are for: repaying principal is not an expense; a repayment moves cash exactly
// once, for its total; a lender is never a supplier.
// =============================================================================

export interface PoultryLoan {
  poultryLoanId: number
  farmId: string
  loanNumber?: string | null
  /** Null on a Cash-Flow row: a 'Loan received' adjustment records no lender. */
  lenderName?: string | null
  lenderType: string
  accountNumber?: string | null
  loanDate: string
  /** What is OWED. May exceed amountReceived when the lender withheld a fee. */
  originalPrincipal: number
  /** What actually ARRIVED. This, not the principal, is the cash in. */
  amountReceived: number
  interestRate?: number | null
  interestType?: string | null
  termMonths?: number | null
  paymentFrequency?: string | null
  startDate: string
  endDate?: string | null
  nextPaymentDate?: string | null
  poultryCashAccountId?: number | null
  accountName?: string | null
  outstandingPrincipal: number
  totalPrincipalRepaid: number
  totalInterestPaid: number
  totalFeesPaid: number
  status: "Draft" | "Active" | "PaidOff" | "Overdue" | "Cancelled" | "Reversed" | string
  /** Derived on read — nothing stamps it, because no scheduler exists. */
  isOverdue: boolean
  paymentCount: number
  paidOffDate?: string | null
  notes?: string | null
  createdBy?: string | null
  createdAt?: string | null
  reversalReason?: string | null
  /**
   * Which record this row is (migration 290).
   *
   * `Loan` — a real loan record, repayable and cancellable here.
   * `CashAdjustment` — a "Loan received" typed on the Cash or Cash Flow page.
   * Read-only here: there is no loan behind it, so nothing on this page can
   * repay, reverse or cancel it. The Cash Flow page edits and deletes it.
   *
   * A legacy row carries `poultryLoanId` 0 and no lender, rate, term or next
   * payment date; its repaid/interest/fee totals and payment count are 0 and
   * its status is always 'Active'. It still counts towards outstanding debt.
   */
  source: "Loan" | "CashAdjustment" | string
  /**
   * The id WITHIN `source`. For a Cash-Flow row `poultryLoanId` is 0 — the two
   * id spaces overlap, so key rows on `source` + `sourceId`.
   */
  sourceId: number
}

export interface PoultryLoanPayment {
  poultryLoanPaymentId: number
  farmId: string
  poultryLoanId: number
  loanNumber?: string | null
  lenderName?: string | null
  paymentNumber?: string | null
  paymentDate: string
  totalAmount: number
  principalAmount: number
  interestAmount: number
  feeAmount: number
  otherAmount: number
  poultryCashAccountId: number
  accountName?: string | null
  paymentMethod?: string | null
  referenceNumber?: string | null
  notes?: string | null
  status: "Posted" | "Reversed" | string
  /** The expense rows for the cost of borrowing. Null when that part was zero. */
  interestExpenseId?: number | null
  feeExpenseId?: number | null
  createdBy?: string | null
  createdAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface PoultryLoanSummary {
  activeLoans: number
  totalBorrowed: number
  totalReceived: number
  outstandingPrincipal: number
  totalPrincipalRepaid: number
  totalInterestPaid: number
  totalFeesPaid: number
  overdueLoans: number
  nextPaymentDate?: string | null
}

export const listPoultryLoans = (status?: string | null) =>
  jget<PoultryLoan[]>(`/Poultry/loans?farmId=${fid()}${status && status !== "All" ? `&status=${encodeURIComponent(status)}` : ""}`)

export const getPoultryLoanSummary = () =>
  jget<PoultryLoanSummary>(`/Poultry/loans/summary?farmId=${fid()}`)

export const createPoultryLoan = (input: {
  lenderName: string
  originalPrincipal: number
  startDate: string
  amountReceived?: number
  poultryCashAccountId?: number | null
  lenderType?: string
  accountNumber?: string | null
  loanDate?: string | null
  interestRate?: number | null
  interestType?: string | null
  termMonths?: number | null
  paymentFrequency?: string | null
  endDate?: string | null
  nextPaymentDate?: string | null
  status?: string
  notes?: string | null
}) =>
  jsend<{ poultryLoanId: number }>(`/Poultry/loans`, "POST",
    { ...input, farmId: activeFarmId(), createdBy: currentUserId() || null })

/**
 * Turn a Cash Flow "Loan received" adjustment into a real, repayable loan
 * (migrations 292/293).
 *
 * No amount and no cash account here on purpose: the amount comes from the
 * adjustment, and the conversion writes NO cash row -- the adjustment stays the
 * cash event and the loan is the debt record beside it. Nothing about cash
 * moves; the borrowing simply becomes repayable.
 *
 * The server refuses a non-LoanReceived row, a negative amount (that is a
 * correction, not a borrowing) and a second conversion.
 */
export const createPoultryLoanFromAdjustment = (input: {
  adjustmentId: number
  lenderName: string
  lenderType?: string
  accountNumber?: string | null
  interestRate?: number | null
  interestType?: string | null
  termMonths?: number | null
  paymentFrequency?: string | null
  endDate?: string | null
  nextPaymentDate?: string | null
  notes?: string | null
}) =>
  jsend<{ poultryLoanId: number }>(`/Poultry/loans/from-adjustment`, "POST",
    { ...input, farmId: activeFarmId(), createdBy: currentUserId() || null })

export const updatePoultryLoan = (id: number, input: Record<string, unknown>) =>
  jsend<void>(
    `/Poultry/loans/${id}?farmId=${fid()}&updatedBy=${encodeURIComponent(currentUserId() || "")}`,
    "PUT", input)

export const cancelPoultryLoan = (id: number, reason: string) =>
  jsend<void>(
    `/Poultry/loans/${id}/cancel?farmId=${fid()}&cancelledBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST", { reason })

export const listPoultryLoanPayments = (loanId?: number | null) =>
  jget<PoultryLoanPayment[]>(`/Poultry/loan-payments?farmId=${fid()}${loanId ? `&loanId=${loanId}` : ""}`)

/**
 * One call, one cash movement. The split is sent as its parts and the server
 * adds them up — a total sent from the browser could disagree with them.
 */
export const recordPoultryLoanRepayment = (loanId: number, input: {
  poultryCashAccountId: number
  principalAmount: number
  interestAmount: number
  feeAmount: number
  otherAmount?: number
  paymentDate?: string | null
  paymentMethod?: string | null
  referenceNumber?: string | null
  notes?: string | null
  nextPaymentDate?: string | null
}) =>
  jsend<{ poultryLoanPaymentId: number }>(`/Poultry/loans/${loanId}/record-repayment`, "POST",
    { ...input, poultryLoanId: loanId, farmId: activeFarmId(), createdBy: currentUserId() || null })

export const reversePoultryLoanPayment = (paymentId: number, reason: string) =>
  jsend<void>(
    `/Poultry/loan-payments/${paymentId}/reverse?farmId=${fid()}&reversedBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST", { reason })

// =============================================================================
// Owner money (migration 253)
//
// What the owner put into the farm and what they took out. Neither is trading:
// a contribution is not revenue and a draw is not an expense, so nothing here
// touches sales, expenses or supplier/customer payments.
// =============================================================================

export type OwnerMoneyType = "Contribution" | "Draw"

export interface PoultryOwnerMoney {
  poultryOwnerMoneyId: number
  farmId: string
  /** OWN-2026-0001 for a contribution, OWD- for a draw. */
  transactionNumber?: string | null
  transactionDate: string
  transactionType: OwnerMoneyType | string
  /** Always POSITIVE — the direction lives in transactionType. */
  amount: number
  /**
   * Null for a row recorded on the Cash / Cash Flow page (migration 287):
   * cashadjustment has no cash-account column, which is why Cash Flow reports
   * those movements without one either.
   */
  poultryCashAccountId: number | null
  accountName?: string | null
  paymentMethod?: string | null
  ownerUserId?: string | null
  ownerName?: string | null
  referenceNumber?: string | null
  notes?: string | null
  status: "Posted" | "Reversed" | string
  poultryCashTransactionId?: number | null
  reversalCashTransactionId?: number | null
  createdBy?: string | null
  createdAt?: string | null
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
  /**
   * Which record this row is (migration 287).
   *
   * `OwnerMoney` — recorded on this page, reversible here.
   * `CashAdjustment` — an owner injection or withdrawal typed on the Cash or
   * Cash Flow page. Read-only here: it belongs to the Cash page, which edits
   * and deletes it.
   */
  source: "OwnerMoney" | "CashAdjustment" | string
  /**
   * The id WITHIN `source`. For a Cash-page row `poultryOwnerMoneyId` is 0 —
   * the two id spaces overlap, so key rows on `source` + `sourceId`.
   */
  sourceId: number
}

export interface PoultryOwnerMoneySummary {
  totalContributions: number
  totalDraws: number
  /** Contributions less draws, all time. Reversed records count for nothing. */
  netFunding: number
  periodContributions: number
  periodDraws: number
  contributionCount: number
  drawCount: number
  /** How many of the above came from the Cash / Cash Flow pages (migration 287). */
  legacyCount: number
  /** Contributions less draws, for those Cash-page rows only. */
  legacyNet: number
}

export const listPoultryOwnerMoney = (opts: {
  type?: string | null; from?: string | null; to?: string | null; status?: string | null
} = {}) => {
  const q = new URLSearchParams({ farmId: fid() })
  if (opts.type && opts.type !== "All") q.set("type", opts.type)
  if (opts.status && opts.status !== "All") q.set("status", opts.status)
  if (opts.from) q.set("from", opts.from)
  if (opts.to) q.set("to", opts.to)
  return jget<PoultryOwnerMoney[]>(`/Poultry/owner-money?${q.toString()}`)
}

export const getPoultryOwnerMoneySummary = (from?: string | null, to?: string | null) => {
  const q = new URLSearchParams({ farmId: fid() })
  if (from) q.set("from", from)
  if (to) q.set("to", to)
  return jget<PoultryOwnerMoneySummary>(`/Poultry/owner-money/summary?${q.toString()}`)
}

/** One endpoint for both directions — they differ by a single field. */
export const recordPoultryOwnerMoney = (input: {
  transactionType: OwnerMoneyType
  amount: number
  poultryCashAccountId: number
  transactionDate?: string | null
  paymentMethod?: string | null
  ownerName?: string | null
  referenceNumber?: string | null
  notes?: string | null
}) =>
  jsend<{ poultryOwnerMoneyId: number }>(`/Poultry/owner-money`, "POST",
    { ...input, farmId: activeFarmId(), createdBy: currentUserId() || null })

/** Append-only: one opposite cash row, the original kept, the reason audited. */
export const reversePoultryOwnerMoney = (id: number, reason: string) =>
  jsend<void>(
    `/Poultry/owner-money/${id}/reverse?farmId=${fid()}&reversedBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST", { reason })

/** Cancels a DRAFT only — a draft moved no money. Use reverse for an approved one. */
export const cancelPoultryCashTransfer = (id: number) =>
  jsend<void>(`/Poultry/cash-transfers/${id}/cancel?farmId=${fid()}`, "POST")

/**
 * Undoes an APPROVED transfer: two opposite ledger rows, both balances
 * restored, the original rows kept. The reason is required and lands in the
 * audit trail, which is why it travels in the body rather than the query string.
 */
export const reversePoultryCashTransfer = (id: number, reason: string) =>
  jsend<void>(
    `/Poultry/cash-transfers/${id}/reverse?farmId=${fid()}&reversedBy=${encodeURIComponent(currentUserId() || "")}`,
    "POST", { reason })

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

// =============================================================================
// Employee Loans & Advances (migrations 305/306)
//
// Money the company LENDS TO STAFF -- a receivable, and the mirror image of the
// Loans section above, which is money the company borrowed. The two never share
// a type: a lender is not a worker, and a liability is not an asset.
//
// Every financial rule lives in the SQL. This module sends parameters, and the
// one thing it will not let you do is post a payroll repayment: those are
// created by approving the payroll run, which is also the only thing that can
// reverse them (spec sections 39 and 60).
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

/** How a repayment reached the company. "Payroll" is never chosen by a user. */
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

export interface PoultryEmployeeLoan {
  poultryEmployeeLoanId: number
  farmId: string
  poultryStaffId: number
  staffName?: string | null
  staffRole?: string | null
  loanNumber?: string | null
  loanType: string
  principalAmount: number
  interestEnabled: boolean
  interestAmount: number
  interestRate?: number | null
  interestType?: string | null
  /** Principal + interest: what the worker owes in total. */
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
  poultryCashAccountId?: number | null
  cashAccountName?: string | null
  paymentMethod?: string | null
  referenceNumber?: string | null
  poultryCashTransactionId?: number | null
  disbursedBy?: string | null
  disbursedAt?: string | null
  createdBy?: string | null
  createdAt: string
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface PoultryEmployeeLoanPage {
  items: PoultryEmployeeLoan[]
  totalCount: number
}

export interface PoultryEmployeeLoanRepayment {
  poultryEmployeeLoanRepaymentId: number
  poultryEmployeeLoanId: number
  poultryStaffId: number
  staffName?: string | null
  repaymentNumber?: string | null
  repaymentDate: string
  amount: number
  principalAmount: number
  interestAmount: number
  sourceType: string
  poultryPayrollRunId?: number | null
  payrollPeriodStart?: string | null
  payrollPeriodEnd?: string | null
  poultryPayrollItemId?: number | null
  poultryPayrollDeductionId?: number | null
  /** Always null for a payroll repayment: no money moved. */
  poultryCashAccountId?: number | null
  cashAccountName?: string | null
  paymentMethod?: string | null
  referenceNumber?: string | null
  description?: string | null
  notes?: string | null
  balanceBefore: number
  balanceAfter: number
  status: string
  poultryCashTransactionId?: number | null
  reversalCashTransactionId?: number | null
  createdBy?: string | null
  createdAt: string
  reversedBy?: string | null
  reversedAt?: string | null
  reversalReason?: string | null
}

export interface PoultryEmployeeLoanSummary {
  outstandingTotal: number
  disbursedInPeriod: number
  repaidInPeriod: number
  activeLoans: number
  staffWithActiveLoans: number
  paidLoans: number
  draftLoans: number
}

export interface PoultryEmployeeLoanEligible {
  poultryEmployeeLoanId: number
  loanNumber?: string | null
  loanType: string
  outstandingBalance: number
  defaultPayrollDeduction?: number | null
  repaymentMethod?: string | null
  disbursementDate: string
}

export interface PoultryEmployeeLoanFilter {
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

/** Server-side filtered and paged: never pull a farm's whole history. */
export const listPoultryEmployeeLoans = (f: PoultryEmployeeLoanFilter = {}) => {
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
  return jget<PoultryEmployeeLoanPage>(`/Poultry/employee-loans?${q.toString()}`)
}

export const getPoultryEmployeeLoanSummary = (fromDate?: string, toDate?: string) => {
  const q = new URLSearchParams({ farmId: activeFarmId() })
  if (fromDate) q.set("fromDate", fromDate)
  if (toDate) q.set("toDate", toDate)
  return jget<PoultryEmployeeLoanSummary>(`/Poultry/employee-loans/summary?${q.toString()}`)
}

export const getPoultryEmployeeLoan = (id: number) =>
  jget<PoultryEmployeeLoan>(`/Poultry/employee-loans/${id}?farmId=${fid()}`)

export const listPoultryEmployeeLoanRepayments = (loanId: number) =>
  jget<PoultryEmployeeLoanRepayment[]>(
    `/Poultry/employee-loans/${loanId}/repayments?farmId=${fid()}`)

/**
 * Which advances a deduction may be applied to for this worker. The dropdown
 * shows what this returns; the server re-checks the same rules when the payroll
 * is approved, so a hand-made id gets refused rather than posted.
 */
export const listEligiblePoultryEmployeeLoans = (staffId: number) =>
  jget<PoultryEmployeeLoanEligible[]>(
    `/Poultry/employee-loans/eligible?farmId=${fid()}&staffId=${staffId}`)

export interface PoultryEmployeeLoanInput {
  poultryStaffId: number
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
  /** False records the agreement only: a Draft owes nothing and moves no cash. */
  disburseNow?: boolean
  poultryCashAccountId?: number | null
  paymentMethod?: string | null
  referenceNumber?: string | null
}

export const createPoultryEmployeeLoan = (input: PoultryEmployeeLoanInput) =>
  jsend<{ poultryEmployeeLoanId: number }>(`/Poultry/employee-loans`, "POST", {
    ...input,
    farmId: activeFarmId(),
    createdBy: currentUserId() || null,
  })

/** Terms only, once it is disbursed: the amount and the worker are history. */
export const updatePoultryEmployeeLoan = (
  id: number, input: Partial<PoultryEmployeeLoanInput>,
) =>
  jsend<void>(`/Poultry/employee-loans/${id}`, "PUT", {
    ...input,
    farmId: activeFarmId(),
    updatedBy: currentUserId() || null,
  })

export const disbursePoultryEmployeeLoan = (
  id: number,
  input: {
    poultryCashAccountId: number
    paymentMethod?: string | null
    referenceNumber?: string | null
  },
) =>
  jsend<void>(`/Poultry/employee-loans/${id}/disburse`, "POST", {
    ...input,
    farmId: activeFarmId(),
    disbursedBy: currentUserId() || null,
  })

export const cancelPoultryEmployeeLoan = (id: number, reason?: string | null) =>
  jsend<void>(`/Poultry/employee-loans/${id}/cancel`, "POST", {
    farmId: activeFarmId(), reason: reason ?? null, actionBy: currentUserId() || null,
  })

export const reversePoultryEmployeeLoan = (id: number, reason?: string | null) =>
  jsend<void>(`/Poultry/employee-loans/${id}/reverse`, "POST", {
    farmId: activeFarmId(), reason: reason ?? null, actionBy: currentUserId() || null,
  })

export interface PoultryEmployeeLoanRepaymentInput {
  poultryEmployeeLoanId: number
  amount: number
  sourceType?: string
  principalAmount?: number | null
  interestAmount?: number | null
  repaymentDate?: string | null
  poultryCashAccountId?: number | null
  paymentMethod?: string | null
  referenceNumber?: string | null
  description?: string | null
  notes?: string | null
}

/** A repayment the worker actually made. Payroll deductions never come here. */
export const recordPoultryEmployeeLoanRepayment = (input: PoultryEmployeeLoanRepaymentInput) =>
  jsend<{ poultryEmployeeLoanRepaymentId: number }>(
    `/Poultry/employee-loans/repayments`, "POST", {
      ...input,
      farmId: activeFarmId(),
      createdBy: currentUserId() || null,
    })

/**
 * Reverses a repayment the worker made directly. A payroll-created one is
 * refused by the server with a message naming the run to reopen -- that is
 * deliberate, not a gap.
 */
export const reversePoultryEmployeeLoanRepayment = (
  repaymentId: number, reason?: string | null,
) =>
  jsend<void>(`/Poultry/employee-loans/repayments/${repaymentId}/reverse`, "POST", {
    farmId: activeFarmId(), reason: reason ?? null, actionBy: currentUserId() || null,
  })

// -----------------------------------------------------------------------------
// Structured payroll deductions (306)
// -----------------------------------------------------------------------------
export const PAYROLL_DEDUCTION_TYPES = [
  "EmployeeLoanRepayment", "SalaryAdvanceRepayment", "OtherDeduction",
] as const

export const PAYROLL_DEDUCTION_TYPE_LABELS: Record<string, string> = {
  EmployeeLoanRepayment: "Employee loan repayment",
  SalaryAdvanceRepayment: "Salary advance repayment",
  OtherDeduction: "Other deduction",
}

export interface PoultryPayrollDeduction {
  /** Null on the legacy row: it is the unexplained remainder, not a record. */
  poultryPayrollItemDeductionId?: number | null
  poultryPayrollItemId: number
  poultryStaffId: number
  deductionType: string
  amount: number
  poultryEmployeeLoanId?: number | null
  loanNumber?: string | null
  loanType?: string | null
  loanOutstanding?: number | null
  poultryEmployeeLoanRepaymentId?: number | null
  description?: string | null
  reference?: string | null
  status: string
  isLegacy: boolean
  createdBy?: string | null
  createdAt?: string | null
}

export interface PoultryPayrollDeductionRunRow {
  poultryPayrollItemId: number
  poultryStaffId: number
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
export const listPoultryPayrollDeductions = (payrollItemId: number) =>
  jget<PoultryPayrollDeduction[]>(
    `/Poultry/payroll-deductions?farmId=${fid()}&payrollItemId=${payrollItemId}`)

export const listPoultryPayrollDeductionsForRun = (runId: number) =>
  jget<PoultryPayrollDeductionRunRow[]>(
    `/Poultry/payroll-deductions/run/${runId}?farmId=${fid()}`)

export interface PoultryPayrollDeductionInput {
  poultryPayrollItemId: number
  deductionType: string
  amount: number
  poultryEmployeeLoanId?: number | null
  description?: string | null
  reference?: string | null
  poultryPayrollItemDeductionId?: number | null
}

/** Unapproved runs only. Nothing here moves a balance -- approval does that. */
export const savePoultryPayrollDeduction = (input: PoultryPayrollDeductionInput) =>
  jsend<{ poultryPayrollItemDeductionId: number }>(
    `/Poultry/payroll-deductions`, "POST", {
      ...input,
      farmId: activeFarmId(),
      savedBy: currentUserId() || null,
    })

export const deletePoultryPayrollDeduction = (deductionId: number) =>
  jsend<void>(
    `/Poultry/payroll-deductions/${deductionId}?farmId=${fid()}` +
    `&deletedBy=${encodeURIComponent(currentUserId() || "")}`, "DELETE")
