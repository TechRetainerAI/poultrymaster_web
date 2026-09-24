import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "./config"

// =============================================================================
// Restaurant finance — API module (migration 323)
//
// Cash accounts, till shifts, transfers, owner money, loans, cash counts and
// daily closing. Every write posts to ONE cash ledger inside a single database
// function, so a request either fully happens or fully doesn't. Refusals (a
// closed day, an overdrawn account, an over-payment) come back as 400 with a
// plain sentence, which these helpers throw as the Error message.
//
// The acting user is taken from the login token on the server, never sent from
// here.
// =============================================================================

function farmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

function url(path: string, query: Record<string, string | number | undefined | null> = {}): string {
  const q = new URLSearchParams({ farmId: farmId() })
  for (const [k, v] of Object.entries(query)) if (v !== undefined && v !== null && v !== "") q.set(k, String(v))
  return farmApiUrl(`/Restaurant/finance${path}?${q.toString()}`)
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

export const ACCOUNT_TYPES = ["Till", "CashBox", "PettyCash", "MobileMoney", "Bank", "Other"] as const
export type AccountType = (typeof ACCOUNT_TYPES)[number]

export const ACCOUNT_TYPE_LABELS: Record<string, string> = {
  Till: "Till (cash drawer)",
  CashBox: "Cash box / safe",
  PettyCash: "Petty cash",
  MobileMoney: "Mobile money",
  Bank: "Bank account",
  Other: "Other",
}

export const DEFAULT_FOR_LABELS: Record<string, string> = {
  Cash: "Cash payments",
  Bank: "Card, bank transfer & cheque",
  MobileMoney: "Mobile money",
}

/** Owner-facing names for ledger source types. */
export const LEDGER_SOURCE_LABELS: Record<string, string> = {
  OpeningBalance: "Opening balance",
  OrderPayment: "Order payment",
  OrderRefund: "Refund",
  Expense: "Expense",
  ExpenseReversal: "Expense deleted",
  GiftCardSale: "Gift card sale",
  GiftCardReload: "Gift card reload",
  TransferOut: "Transfer out",
  TransferIn: "Transfer in",
  TransferReversalOut: "Transfer reversed",
  TransferReversalIn: "Transfer reversed",
  ShiftFloatOut: "Float to till",
  ShiftFloatIn: "Opening float",
  ShiftDropOut: "Takings dropped",
  ShiftDropIn: "Takings from till",
  ShiftVariance: "Till over / short",
  CountVariance: "Count difference",
  CountVarianceReversal: "Count reversed",
  OwnerContribution: "Owner contribution",
  OwnerDraw: "Owner drawing",
  OwnerContributionReversal: "Contribution reversed",
  OwnerDrawReversal: "Drawing reversed",
  LoanReceived: "Loan received",
  LoanReceivedReversal: "Loan cancelled",
  LoanRepayment: "Loan repayment",
  LoanRepaymentReversal: "Repayment reversed",
}

export function ledgerSourceLabel(s: string | null | undefined): string {
  if (!s) return "—"
  return LEDGER_SOURCE_LABELS[s] ?? s.replace(/([a-z])([A-Z])/g, "$1 $2")
}

/** Today in the browser's calendar, as YYYY-MM-DD. */
export function todayIso(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
}

// ----- Accounts -------------------------------------------------------------

export interface CashAccount {
  cashAccountId: number; name: string; accountType: string; defaultFor?: string | null
  openingBalance: number; currentBalance: number; ledgerBalance: number
  allowNegative: boolean; isActive: boolean; notes?: string | null
  lastCountedAt?: string | null; lastCountedBalance?: number | null
  openShiftId?: number | null; openShiftNumber?: string | null
  openShiftOpenedBy?: string | null; openShiftOpenedAt?: string | null
  createdAt: string
}
export interface CashAccountInput {
  name: string; accountType: string; openingBalance?: number; allowNegative?: boolean
  defaultFor?: string | null; notes?: string | null
}
export interface CashAccountUpdate {
  name: string; accountType: string; allowNegative: boolean; isActive: boolean
  defaultFor?: string | null; notes?: string | null
}
export interface LedgerRow {
  cashTxnId: number; txnDate: string; txnType: string; sourceType: string; sourceId?: number | null
  amount: number; runningBalance: number; description?: string | null; shiftId?: number | null
  reversesId?: number | null; createdBy?: string | null; createdAt: string
}

/** Also creates the three default accounts (cash box, bank, mobile money) on first use. */
export const listCashAccounts = () => get<CashAccount[]>("/accounts")
export const createCashAccount = (input: CashAccountInput) =>
  send<{ cashAccountId: number }>("POST", "/accounts", { ...input, farmId: farmId() })
export const updateCashAccount = (id: number, input: CashAccountUpdate) => send<void>("PUT", `/accounts/${id}`, input)
export const getAccountLedger = (id: number, from?: string, to?: string) =>
  get<LedgerRow[]>(`/accounts/${id}/ledger`, { from, to })

// ----- Till shifts ----------------------------------------------------------

export interface CashShift {
  shiftId: number; shiftNumber?: string | null; cashAccountId: number; tillName: string; status: string
  openedAt: string; openedBy?: string | null; openingFloat: number; openingBalance: number
  closedAt?: string | null; closedBy?: string | null; expectedCash?: number | null
  countedCash?: number | null; variance?: number | null; dropAmount: number
  closingBalance?: number | null; currentBalance: number; cashSales: number
  notes?: string | null; closeNotes?: string | null
}
export interface ShiftCloseResult {
  expectedCash: number; countedCash: number; variance: number; dropAmount: number; closingBalance: number
}
export interface ZReportLine { section: string; label: string; txnCount: number; amount: number; sortOrder: number }

export const listShifts = (status?: "Open" | "Closed", from?: string, to?: string) =>
  get<CashShift[]>("/shifts", { status, from, to })
export const openShift = (input: { tillAccountId: number; openingFloat?: number; floatFromAccountId?: number | null; notes?: string | null }) =>
  send<{ shiftId: number }>("POST", "/shifts", input)
export const closeShift = (id: number, input: { countedCash: number; dropAmount?: number; dropToAccountId?: number | null; notes?: string | null }) =>
  send<ShiftCloseResult>("POST", `/shifts/${id}/close`, input)
export const getZReport = (id: number) => get<ZReportLine[]>(`/shifts/${id}/z-report`)

// ----- Transfers ------------------------------------------------------------

export interface CashTransfer {
  transferId: number; transferNumber?: string | null; fromAccountId: number; fromAccountName: string
  toAccountId: number; toAccountName: string; amount: number; transferDate: string
  reference?: string | null; notes?: string | null; status: string; createdBy?: string | null; createdAt: string
  reversedBy?: string | null; reversedAt?: string | null; reversalReason?: string | null
}
export const listTransfers = (from?: string, to?: string) => get<CashTransfer[]>("/transfers", { from, to })
export const createTransfer = (input: { fromAccountId: number; toAccountId: number; amount: number; transferDate?: string; reference?: string | null; notes?: string | null }) =>
  send<{ transferId: number }>("POST", "/transfers", input)
export const reverseTransfer = (id: number, reason: string) => send<void>("POST", `/transfers/${id}/reverse`, { reason })

// ----- Owner money ----------------------------------------------------------

export interface OwnerMoneyEntry {
  ownerMoneyId: number; entryNumber?: string | null; entryType: "Contribution" | "Draw"; cashAccountId: number
  accountName: string; amount: number; entryDate: string; ownerName?: string | null; notes?: string | null
  status: string; createdBy?: string | null; createdAt: string; reversedBy?: string | null
  reversedAt?: string | null; reversalReason?: string | null
}
export const listOwnerMoney = (from?: string, to?: string) => get<OwnerMoneyEntry[]>("/owner-money", { from, to })
export const recordOwnerMoney = (input: { entryType: "Contribution" | "Draw"; cashAccountId: number; amount: number; entryDate?: string; ownerName?: string | null; notes?: string | null }) =>
  send<{ ownerMoneyId: number }>("POST", "/owner-money", input)
export const reverseOwnerMoney = (id: number, reason: string) => send<void>("POST", `/owner-money/${id}/reverse`, { reason })

// ----- Loans ----------------------------------------------------------------

export interface RestaurantLoan {
  loanId: number; loanNumber?: string | null; lenderName: string; principal: number; amountReceived: number
  receivedAccountId?: number | null; receivedAccountName?: string | null; loanDate: string
  interestRate?: number | null; dueDate?: string | null; outstandingPrincipal: number; principalRepaid: number
  interestPaid: number; feesPaid: number; status: "Active" | "PaidOff" | "Cancelled"; isOverdue: boolean
  notes?: string | null; createdBy?: string | null; createdAt: string; cancelReason?: string | null
}
export interface LoanPayment {
  loanPaymentId: number; loanId: number; loanNumber?: string | null; lenderName?: string | null; paymentDate: string; cashAccountId: number; accountName: string
  principalAmount: number; interestAmount: number; feeAmount: number; totalAmount: number; status: string
  notes?: string | null; createdBy?: string | null; createdAt: string; reversalReason?: string | null
}
export const listLoans = () => get<RestaurantLoan[]>("/loans")
export const listLoanPayments = (loanId: number) => get<LoanPayment[]>(`/loans/${loanId}/payments`)
/** Every repayment on every loan, newest first. */
export const listAllLoanPayments = () => get<LoanPayment[]>("/loans/payments")
export const createLoan = (input: { lenderName: string; principal: number; amountReceived: number; receivedAccountId?: number | null; loanDate?: string; interestRate?: number | null; dueDate?: string | null; notes?: string | null }) =>
  send<{ loanId: number }>("POST", "/loans", input)
export const repayLoan = (loanId: number, input: { cashAccountId: number; principal: number; interest: number; fees: number; paymentDate?: string; notes?: string | null }) =>
  send<{ loanPaymentId: number }>("POST", `/loans/${loanId}/repay`, input)
export const reverseLoanPayment = (paymentId: number, reason: string) => send<void>("POST", `/loans/payments/${paymentId}/reverse`, { reason })
export const cancelLoan = (loanId: number, reason: string) => send<void>("POST", `/loans/${loanId}/cancel`, { reason })

// ----- Cash counts ----------------------------------------------------------

export interface CashCount {
  countId: number; cashAccountId: number; accountName: string; countDate: string; systemBalance: number
  countedBalance: number; difference: number; status: string; notes?: string | null; createdBy?: string | null
  createdAt: string; reversalReason?: string | null
}
export const listCounts = (accountId?: number) => get<CashCount[]>("/counts", { accountId })
export const postCount = (input: { cashAccountId: number; counted: number; notes?: string | null }) =>
  send<{ countId: number }>("POST", "/counts", input)
export const reverseCount = (id: number, reason: string) => send<void>("POST", `/counts/${id}/reverse`, { reason })

// ----- Daily closing --------------------------------------------------------

export interface DayPreview {
  closingDate: string; isClosed: boolean; lastClosedDate?: string | null; orderCount: number; netSales: number
  discounts: number; taxCollected: number; serviceCharge: number; deliveryFees: number; refunds: number; tips: number
  takingsCash: number; takingsCard: number; takingsMobile: number; takingsGiftCard: number; takingsOther: number
  expenses: number; moneyIn: number; moneyOut: number; cashVariance: number
  openShifts: number; openOrders: number; unpaidOrders: number
}
export interface DailyClosing {
  closingId: number; closingDate: string; status: "Closed" | "Reopened"; orderCount: number; netSales: number
  taxCollected: number; moneyIn: number; moneyOut: number; cashVariance: number; notes?: string | null
  closedBy?: string | null; closedAt: string; reopenedBy?: string | null; reopenedAt?: string | null; reopenReason?: string | null
}
export const previewDay = (date: string) => get<DayPreview>("/daily-closing/preview", { date })
export const listClosings = (limit = 60, from?: string, to?: string) => get<DailyClosing[]>("/daily-closing", { limit, from, to })
export const closeDay = (closingDate: string, notes?: string | null) =>
  send<{ closingId: number }>("POST", "/daily-closing", { closingDate, notes })
export const reopenDay = (closingDate: string, reason: string) =>
  send<void>("POST", "/daily-closing/reopen", { closingDate, reason })

// ----- Reports (migration 324) ------------------------------------------------

/** One account over a period: opening + moneyIn − moneyOut + transfersIn − transfersOut = closing. */
export interface LedgerPeriodRow {
  cashAccountId: number; name: string; accountType: string; isActive: boolean
  openingBalance: number; moneyIn: number; moneyOut: number; transfersIn: number; transfersOut: number
  closingBalance: number; currentBalance: number; ledgerBalance: number; txnCount: number
  lastCountedAt?: string | null; lastCountedBalance?: number | null
}
/** A ledger row across accounts. runningBalance is THAT account's balance after the row. */
export interface LedgerRowAll {
  cashTxnId: number; txnDate: string; cashAccountId: number; accountName: string; txnType: string
  sourceType: string; sourceId?: number | null; amount: number; runningBalance: number
  /** Transfer, till float or drop — money moving between the restaurant's own accounts. */
  isInternal: boolean
  description?: string | null; shiftId?: number | null; createdBy?: string | null; createdAt: string
}
export interface TakingsByAccountRow {
  accountName: string; accountType: string; paymentMethod: string; paymentCount: number
  takings: number; tips: number; refunds: number; netTotal: number
}
export interface CashBridgeLine {
  sortOrder: number; lineKey: string; label: string; amount: number
  kind: "start" | "adjust" | "result" | "check"; explanation?: string | null
}
export const getLedgerPeriod = (from: string, to: string) => get<LedgerPeriodRow[]>("/ledger/period", { from, to })
export const getLedgerRows = (from: string, to: string, accountId?: number) =>
  get<LedgerRowAll[]>("/ledger/rows", { from, to, accountId })
export const getTakingsByAccount = (from: string, to: string) =>
  get<TakingsByAccountRow[]>("/reports/takings-by-account", { from, to })
export const getProfitVsCash = (from: string, to: string) =>
  get<CashBridgeLine[]>("/reports/profit-vs-cash", { from, to })

// ----- P&L statement --------------------------------------------------------

export interface PnlLine { section: "Revenue" | "CostOfSales" | "Expenses" | "Other"; lineKey: string; label: string; amount: number; sortOrder: number }
export const getPnlLines = (from: string, to: string) => get<PnlLine[]>("/pnl-lines", { from, to })
