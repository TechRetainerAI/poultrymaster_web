import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "./config"

// =============================================================================
// Hotel Owner Money, Loans (Financing), Cash Transfers, Reconciliation and the
// Cash Account extras (migration 331, HotelMoneyController).
//
// The endpoints return camelCase keys; the cash-account list (older endpoint)
// returns raw column names, so it is normalised here to one shape.
// =============================================================================

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

async function jsend<T>(endpoint: string, method: string, body?: Record<string, unknown>): Promise<T> {
  const farmId = activeFarmId()
  const url = method === "DELETE"
    ? farmApiUrl(`${endpoint}${endpoint.includes("?") ? "&" : "?"}farmId=${encodeURIComponent(farmId)}`)
    : farmApiUrl(endpoint)
  const res = await fetch(url, {
    method,
    headers: getAuthHeaders(),
    body: method === "DELETE" ? undefined : JSON.stringify({ farmId, ...(body ?? {}) }),
  })
  if (!res.ok) throw new Error(await readApiError(res))
  const text = await res.text()
  return text ? JSON.parse(text) : ({} as T)
}

const num = (v: unknown): number => (v == null || v === "" ? 0 : Number(v))
const numN = (v: unknown): number | null => (v == null || v === "" ? null : Number(v))

// =============================================================================
// CONSTANTS
// =============================================================================

/** Hotel account types. Cash, Bank and MobileMoney are the values older hotel accounts already carry. */
export const HOTEL_CASH_ACCOUNT_TYPES = [
  { value: "FrontDeskCash", label: "Front Desk Cash" },
  { value: "CashBox", label: "Cash Box" },
  { value: "PettyCash", label: "Petty Cash" },
  { value: "Cash", label: "Cash" },
  { value: "Bank", label: "Bank Account" },
  { value: "MobileMoney", label: "Mobile Money" },
  { value: "Other", label: "Other" },
] as const

export function hotelAccountTypeLabel(v?: string | null): string {
  return HOTEL_CASH_ACCOUNT_TYPES.find((t) => t.value === v)?.label ?? (v || "—")
}

/**
 * What the shared reconciliation vocabulary should call this account: count a
 * cash box, check a bank statement, read a MoMo balance.
 */
export function hotelVocabularyType(v?: string | null): string {
  switch (v) {
    case "FrontDeskCash": case "CashBox": case "PettyCash": case "Cash": return "cash"
    case "Bank": return "bank"
    case "MobileMoney": return "momo"
    default: return "other"
  }
}

/** What an account is linked to (auto-routing of guest payments, POS, expenses, payroll). */
export const HOTEL_CASH_PURPOSES = [
  { value: "FrontDesk", label: "Front Desk — guest payments in" },
  { value: "POS", label: "POS / Restaurant — orders in" },
  { value: "Expenses", label: "Expenses — money out" },
  { value: "Payroll", label: "Payroll — salaries out" },
] as const

/** Poultry's POULTRY_CASH_REASONS word for word, without the driver entries (no delivery drivers in a hotel). */
export const HOTEL_CASH_REASONS = [
  { value: "Cash shortage", label: "Cash shortage" },
  { value: "Cash overage", label: "Cash overage" },
  { value: "Bank charge", label: "Bank charge" },
  { value: "MoMo charge", label: "MoMo charge" },
  { value: "Unrecorded expense", label: "Unrecorded expense" },
  { value: "Unrecorded income", label: "Unrecorded income" },
  { value: "Wrong cash account used", label: "Wrong cash account used" },
  { value: "Owner draw not recorded", label: "Owner draw not recorded" },
  { value: "Owner contribution not recorded", label: "Owner contribution not recorded" },
  { value: "Rounding difference", label: "Rounding difference" },
  { value: "Opening balance correction", label: "Opening balance correction" },
  { value: "Other", label: "Other" },
] as const

/** Poultry's POULTRY_CASH_TRANSFER_REASONS, driver floats swapped for the front-desk float. */
export const HOTEL_CASH_TRANSFER_REASONS = [
  { value: "Bank deposit", label: "Bank deposit" },
  { value: "Bank withdrawal", label: "Bank withdrawal" },
  { value: "MoMo cash-out", label: "MoMo cash-out" },
  { value: "MoMo top-up", label: "MoMo top-up" },
  { value: "Front desk float issued", label: "Front desk float issued" },
  { value: "Front desk float returned", label: "Front desk float returned" },
  { value: "Petty cash top-up", label: "Petty cash top-up" },
  { value: "Funding payroll", label: "Funding payroll" },
  { value: "Funding supplier payment", label: "Funding supplier payment" },
  { value: "Consolidating balances", label: "Consolidating balances" },
  { value: "Safe keeping", label: "Safe keeping" },
  { value: "Other", label: "Other" },
] as const

/** Poultry's POULTRY_CASH_REVERSAL_REASONS, word for word. */
export const HOTEL_CASH_REVERSAL_REASONS = [
  { value: "Counted the wrong account", label: "Counted the wrong account" },
  { value: "Miscounted", label: "Miscounted" },
  { value: "Wrong amount entered", label: "Wrong amount entered" },
  { value: "Wrong date", label: "Wrong date" },
  { value: "Duplicate count", label: "Duplicate count" },
  { value: "Posted by mistake", label: "Posted by mistake" },
  { value: "Cash located afterwards", label: "Cash located afterwards" },
  { value: "Test or training entry", label: "Test or training entry" },
  { value: "Other", label: "Other" },
] as const

// =============================================================================
// CASH ACCOUNTS
// =============================================================================

export interface HotelMoneyAccount {
  hotelCashAccountId: number
  accountName: string
  accountType: string
  openingBalance: number
  currentBalance: number
  allowNegativeBalance: boolean
  isActive: boolean
  purpose: string | null
  notes: string | null
}

export async function listHotelMoneyAccounts(): Promise<HotelMoneyAccount[]> {
  const rows = await jget<any[]>("/Hotel/finance/cash-accounts")
  return (rows ?? []).map((r) => ({
    hotelCashAccountId: r.hotelCashAccountId ?? r.hotelcashaccountid,
    accountName: r.accountName ?? r.accountname ?? "",
    accountType: r.accountType ?? r.accounttype ?? "",
    openingBalance: num(r.openingBalance ?? r.openingbalance),
    currentBalance: num(r.currentBalance ?? r.currentbalance),
    allowNegativeBalance: !!(r.allowNegativeBalance ?? r.allownegativebalance),
    isActive: (r.isActive ?? r.isactive) !== false,
    purpose: r.purpose ?? null,
    notes: r.notes ?? null,
  }))
}

export interface HotelCashAccountStatus {
  hotelCashAccountId: number
  accountName: string
  accountType: string | null
  isActive: boolean
  currentBalance: number
  ledgerBalance: number
  cacheDrift: number
  lastReconciledAt: string | null
  lastReconciledBalance: number | null
  daysSinceReconciled: number | null
  unclearedCount: number
  unclearedAmount: number
}

export async function getHotelCashAccountStatus(): Promise<HotelCashAccountStatus[]> {
  const rows = await jget<any[]>("/Hotel/finance/cash-accounts/status")
  return (rows ?? []).map((r) => ({
    ...r,
    currentBalance: num(r.currentBalance),
    ledgerBalance: num(r.ledgerBalance),
    cacheDrift: num(r.cacheDrift),
    lastReconciledBalance: numN(r.lastReconciledBalance),
    unclearedAmount: num(r.unclearedAmount),
    unclearedCount: num(r.unclearedCount),
  }))
}

export const createHotelMoneyAccount = (input: {
  accountName: string; accountType: string; openingBalance: number
  allowNegativeBalance: boolean; notes?: string | null; purpose?: string | null
}) => jsend<any>("/Hotel/finance/cash-accounts", "POST", input)

export const updateHotelMoneyAccount = (id: number, input: {
  accountName: string; accountType: string; allowNegativeBalance: boolean; isActive: boolean
  notes?: string | null; purpose?: string | null
}) => jsend<void>(`/Hotel/finance/cash-accounts/${id}`, "PUT", input)

export const deleteHotelMoneyAccount = (id: number) =>
  jsend<void>(`/Hotel/finance/cash-accounts/${id}`, "DELETE")

export const recalculateHotelCashBalances = () =>
  jsend<{ changed: number }>("/Hotel/finance/cash-accounts/recalculate", "POST", {})

/** amount is SIGNED: positive adds cash, negative removes it. */
export const adjustHotelCashAccount = (id: number, input: { amount: number; reason: string }) =>
  jsend<{ hotelCashAdjustmentId: number }>(`/Hotel/finance/cash-accounts/${id}/adjust`, "POST", input)

export const reverseHotelCashAdjustment = (id: number, reason: string) =>
  jsend<void>(`/Hotel/finance/cash-adjustments/${id}/reverse`, "POST", { reason })

// =============================================================================
// OWNER MONEY
// =============================================================================

export type HotelOwnerMoneyType = "Contribution" | "Draw"

export interface HotelOwnerMoney {
  hotelOwnerMoneyId: number
  transactionNumber: string | null
  transactionDate: string
  transactionType: HotelOwnerMoneyType
  amount: number
  hotelCashAccountId: number
  accountName: string | null
  paymentMethod: string | null
  ownerName: string | null
  referenceNumber: string | null
  notes: string | null
  status: "Posted" | "Reversed"
  createdBy: string | null
  createdAt: string
  reversedAt: string | null
  reversalReason: string | null
}

export interface HotelOwnerMoneySummary {
  totalContributions: number
  totalDraws: number
  netFunding: number
  periodContributions: number
  periodDraws: number
  contributionCount: number
  drawCount: number
}

export async function listHotelOwnerMoney(): Promise<HotelOwnerMoney[]> {
  const rows = await jget<any[]>("/Hotel/owner-money")
  return (rows ?? []).map((r) => ({ ...r, amount: num(r.amount) }))
}

export async function getHotelOwnerMoneySummary(): Promise<HotelOwnerMoneySummary> {
  const r = await jget<any>("/Hotel/owner-money/summary")
  return {
    totalContributions: num(r?.totalContributions), totalDraws: num(r?.totalDraws), netFunding: num(r?.netFunding),
    periodContributions: num(r?.periodContributions), periodDraws: num(r?.periodDraws),
    contributionCount: num(r?.contributionCount), drawCount: num(r?.drawCount),
  }
}

export const recordHotelOwnerMoney = (input: {
  transactionType: HotelOwnerMoneyType; amount: number; hotelCashAccountId: number
  transactionDate: string | null; paymentMethod: string | null; ownerName: string | null
  referenceNumber: string | null; notes: string | null
}) => jsend<{ hotelOwnerMoneyId: number }>("/Hotel/owner-money", "POST", input)

export const reverseHotelOwnerMoney = (id: number, reason: string) =>
  jsend<void>(`/Hotel/owner-money/${id}/reverse`, "POST", { reason })

// =============================================================================
// LOANS (FINANCING)
// =============================================================================

export interface HotelLoan {
  hotelLoanId: number
  loanNumber: string | null
  lenderName: string
  lenderType: string
  accountNumber: string | null
  loanDate: string
  originalPrincipal: number
  amountReceived: number
  interestRate: number | null
  interestType: string | null
  termMonths: number | null
  paymentFrequency: string | null
  startDate: string
  endDate: string | null
  nextPaymentDate: string | null
  hotelCashAccountId: number | null
  accountName: string | null
  outstandingPrincipal: number
  totalPrincipalRepaid: number
  totalInterestPaid: number
  totalFeesPaid: number
  status: string
  isOverdue: boolean
  paymentCount: number
  notes: string | null
  createdAt: string
}

export interface HotelLoanPayment {
  hotelLoanPaymentId: number
  hotelLoanId: number
  loanNumber: string | null
  lenderName: string | null
  paymentNumber: string | null
  paymentDate: string
  totalAmount: number
  principalAmount: number
  interestAmount: number
  feeAmount: number
  otherAmount: number
  hotelCashAccountId: number
  accountName: string | null
  status: "Posted" | "Reversed"
  createdAt: string
  reversalReason: string | null
}

export interface HotelLoanSummary {
  activeLoans: number
  totalBorrowed: number
  totalReceived: number
  outstandingPrincipal: number
  totalPrincipalRepaid: number
  totalInterestPaid: number
  totalFeesPaid: number
  overdueLoans: number
  nextPaymentDate: string | null
}

const LOAN_NUMS = ["originalPrincipal", "amountReceived", "outstandingPrincipal", "totalPrincipalRepaid",
  "totalInterestPaid", "totalFeesPaid"] as const
const PAYMENT_NUMS = ["totalAmount", "principalAmount", "interestAmount", "feeAmount", "otherAmount"] as const

export async function listHotelLoans(): Promise<HotelLoan[]> {
  const rows = await jget<any[]>("/Hotel/loans")
  return (rows ?? []).map((r) => {
    const o: any = { ...r, interestRate: numN(r.interestRate) }
    for (const k of LOAN_NUMS) o[k] = num(r[k])
    return o as HotelLoan
  })
}

export async function listHotelLoanPayments(): Promise<HotelLoanPayment[]> {
  const rows = await jget<any[]>("/Hotel/loan-payments")
  return (rows ?? []).map((r) => {
    const o: any = { ...r }
    for (const k of PAYMENT_NUMS) o[k] = num(r[k])
    return o as HotelLoanPayment
  })
}

export async function getHotelLoanSummary(): Promise<HotelLoanSummary> {
  const r = await jget<any>("/Hotel/loans/summary")
  return {
    activeLoans: num(r?.activeLoans), totalBorrowed: num(r?.totalBorrowed), totalReceived: num(r?.totalReceived),
    outstandingPrincipal: num(r?.outstandingPrincipal), totalPrincipalRepaid: num(r?.totalPrincipalRepaid),
    totalInterestPaid: num(r?.totalInterestPaid), totalFeesPaid: num(r?.totalFeesPaid),
    overdueLoans: num(r?.overdueLoans), nextPaymentDate: r?.nextPaymentDate ?? null,
  }
}

export const createHotelLoan = (input: {
  lenderName: string; lenderType: string; accountNumber: string | null
  originalPrincipal: number; amountReceived: number; hotelCashAccountId: number | null
  startDate: string; interestRate: number | null; interestType: string | null
  termMonths: number | null; paymentFrequency: string | null; nextPaymentDate: string | null; notes: string | null
}) => jsend<{ hotelLoanId: number }>("/Hotel/loans", "POST", input)

export const recordHotelLoanRepayment = (loanId: number, input: {
  hotelCashAccountId: number; principalAmount: number; interestAmount: number; feeAmount: number
  otherAmount: number; paymentDate: string | null; paymentMethod: string | null
  referenceNumber: string | null; notes: string | null; nextPaymentDate: string | null
}) => jsend<{ hotelLoanPaymentId: number }>(`/Hotel/loans/${loanId}/repayments`, "POST", input)

export const reverseHotelLoanPayment = (id: number, reason: string) =>
  jsend<void>(`/Hotel/loan-payments/${id}/reverse`, "POST", { reason })

// =============================================================================
// CASH TRANSFERS
// =============================================================================

export interface HotelCashTransfer {
  hotelCashTransferId: number
  transferNumber: string | null
  fromHotelCashAccountId: number
  fromAccountName: string | null
  toHotelCashAccountId: number
  toAccountName: string | null
  transferDate: string
  amount: number
  status: "Approved" | "Reversed"
  referenceNumber: string | null
  notes: string | null
  createdBy: string | null
  createdAt: string
  reversalReason: string | null
}

export async function listHotelCashTransfers(): Promise<HotelCashTransfer[]> {
  const rows = await jget<any[]>("/Hotel/cash-transfers")
  return (rows ?? []).map((r) => ({ ...r, amount: num(r.amount) }))
}

/** One request, one transaction: the transfer is recorded and both legs posted together. */
export const recordHotelCashTransfer = (input: {
  fromHotelCashAccountId: number; toHotelCashAccountId: number; amount: number
  transferDate: string | null; referenceNumber: string | null; notes: string | null
}) => jsend<{ hotelCashTransferId: number }>("/Hotel/cash-transfers", "POST", input)

export const reverseHotelCashTransfer = (id: number, reason: string) =>
  jsend<void>(`/Hotel/cash-transfers/${id}/reverse`, "POST", { reason })

// =============================================================================
// RECONCILIATION
// =============================================================================

export interface HotelCashCount {
  hotelCashReconciliationId: number
  hotelCashAccountId: number
  accountName: string | null
  referenceNo: string | null
  reconciliationDate: string
  systemBalance: number
  actualBalance: number | null
  difference: number
  reason: string | null
  notes: string | null
  status: "Draft" | "Posted" | "Reversed"
  adjustmentTransactionId: number | null
  createdAt: string
  reversalReason: string | null
}

export async function listHotelCashCounts(accountId: number): Promise<HotelCashCount[]> {
  const rows = await jget<any[]>(`/Hotel/cash-reconciliations?accountId=${accountId}`)
  return (rows ?? []).map((r) => ({
    ...r, systemBalance: num(r.systemBalance), actualBalance: numN(r.actualBalance), difference: num(r.difference),
  }))
}

type CountFields = { reconciliationDate: string; actualBalance: number; reason: string | null; notes: string | null }

export const createHotelCashCount = (accountId: number, f: CountFields) =>
  jsend<{ hotelCashReconciliationId: number }>("/Hotel/cash-reconciliations", "POST", { hotelCashAccountId: accountId, ...f })

export const updateHotelCashCount = (id: number, accountId: number, f: CountFields) =>
  jsend<void>(`/Hotel/cash-reconciliations/${id}`, "PUT", { hotelCashAccountId: accountId, ...f })

export const deleteHotelCashCount = (id: number) => jsend<void>(`/Hotel/cash-reconciliations/${id}`, "DELETE")

export const postHotelCashCount = (id: number) =>
  jsend<{ adjustmentTransactionId: number | null }>(`/Hotel/cash-reconciliations/${id}/post`, "POST", {})

export const reverseHotelCashCount = (id: number, reason: string) =>
  jsend<void>(`/Hotel/cash-reconciliations/${id}/reverse`, "POST", { reason })
