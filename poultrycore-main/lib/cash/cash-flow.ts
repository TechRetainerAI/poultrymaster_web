/**
 * Company-wide cash-flow arithmetic.
 *
 * Pure by design — no React, no API imports, no currency formatting — so every
 * number and every sentence on the Cash Flow page can be unit-tested without a
 * store, a fetch or a render. Same shape as lib/balances/allocate.ts.
 *
 * Input types are structural rather than the API DTOs. That is deliberate: it
 * keeps this module from being coupled to whichever client happens to feed it,
 * and it lets tests build a five-field object instead of a full transaction.
 *
 * THE ONE RULE THAT MATTERS: `amount` is signed. Positive is money in, negative
 * is money out. There is no "type" string to branch on, and the ledger relies on
 * SUM(amount) meaning the balance. Anything here that treats direction as
 * anything other than the sign is wrong.
 */

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

export interface LedgerEntry {
  id: number
  accountId: number
  accountName?: string | null
  transactionDate: string
  transactionType?: string | null
  sourceType?: string | null
  /** SIGNED: positive in, negative out. */
  amount: number
  description?: string | null
}

export interface AccountStatusEntry {
  accountId: number
  accountName: string
  accountType?: string | null
  isActive: boolean
  currentBalance: number
  /** openingBalance + SUM(amount). The authoritative figure — see below. */
  ledgerBalance: number
  cacheDrift: number
  lastReconciledAt?: string | null
  daysSinceReconciled?: number | null
  unclearedCount: number
}

export interface TransferEntry {
  id: number
  fromAccountName?: string | null
  toAccountName?: string | null
  transferDate: string
  amount: number
  status: string
}

// ---------------------------------------------------------------------------
// Date parameters
// ---------------------------------------------------------------------------

/**
 * The ledger read compares `transactiondate <= p_todate` and the controller
 * binds a DateTime, so a bare "2026-08-28" means midnight — which excludes
 * everything recorded that day and makes "Today" return nothing at all.
 * See 223_PoultryCashReconciliation.postgres.sql:862.
 */
export function ledgerFromParam(from: string): string {
  return from.includes("T") ? from : `${from}T00:00:00`
}

export function ledgerToParam(to: string): string {
  return to.includes("T") ? to : `${to}T23:59:59.999`
}

// ---------------------------------------------------------------------------
// Internal transfers
// ---------------------------------------------------------------------------

/**
 * A transfer between two of the company's own accounts is two rows that net to
 * zero. Counting them would inflate both Money In and Money Out by the same
 * amount and tell the owner the business moved money it never earned or spent.
 *
 * Both markers are checked even though the approve SP always writes both
 * (129:296) — it costs nothing and it means a hand-written row with only one of
 * them still cannot leak into the totals.
 */
export function isInternalTransfer(e: LedgerEntry): boolean {
  if ((e.sourceType ?? "") === "Transfer") return true
  const t = e.transactionType ?? ""
  return t === "TransferIn" || t === "TransferOut"
}

export function excludeTransfers(entries: LedgerEntry[]): LedgerEntry[] {
  return entries.filter((e) => !isInternalTransfer(e))
}

// ---------------------------------------------------------------------------
// Totals
// ---------------------------------------------------------------------------

export interface CashFlowTotals {
  moneyIn: number
  /** A positive magnitude — the page says "Money Out: 9,310", not "-9,310". */
  moneyOut: number
  net: number
  transferVolume: number
  transferCount: number
  entryCount: number
}

export function cashFlowTotals(entries: LedgerEntry[]): CashFlowTotals {
  let moneyIn = 0
  let moneyOut = 0
  let transferVolume = 0
  let transferCount = 0
  let entryCount = 0

  for (const e of entries) {
    const amount = Number(e.amount) || 0
    if (isInternalTransfer(e)) {
      // Count one leg, not two, or the "volume moved" reads double.
      if (amount > 0) {
        transferVolume += amount
        transferCount += 1
      }
      continue
    }
    entryCount += 1
    if (amount > 0) moneyIn += amount
    else moneyOut += -amount
  }

  return {
    moneyIn: round2(moneyIn),
    moneyOut: round2(moneyOut),
    net: round2(moneyIn - moneyOut),
    transferVolume: round2(transferVolume),
    transferCount,
    entryCount,
  }
}

// ---------------------------------------------------------------------------
// Breakdowns
// ---------------------------------------------------------------------------

export type FlowDirection = "in" | "out"

export interface FlowBucket {
  key: string
  label: string
  /** Positive magnitude. */
  amount: number
  count: number
  /** 0–100, summing to exactly 100 across the returned buckets. */
  percent: number
}

/**
 * The owner-facing name for a raw sourceType.
 *
 * One map covers both rails. They overlap on most values and the ones they do
 * not overlap on cannot collide, so splitting it per module would buy nothing
 * and guarantee the two drift. An unknown key is title-cased rather than
 * dropped, so a rail-specific source type added later still reads sensibly.
 *
 * Kept as plain strings rather than imported from lib/api so this module has no
 * dependencies at all. The adjustment reasons must stay in step with
 * POULTRY_CASH_REASONS / WATER_CASH_REASONS — they are matched by exact value,
 * and a rename there without a rename here degrades the label to "Adjustment"
 * rather than breaking anything.
 */
const SOURCE_LABELS: Record<string, string> = {
  // Shared
  Sale: "Sales collected",
  Expense: "Expenses paid",
  Payroll: "Staff wages",
  RawMaterialPurchase: "Raw materials",
  Adjustment: "Adjustment",
  LegacyAdjustment: "Adjustment (recorded before cash accounts)",

  // Poultry only
  PoultrySupplierPayment: "Supplier payments",
  FeedProduction: "Feed made",
  FeedProductionReversal: "Feed production reversed",

  // Water only. Note Water DOES have a CustomerPayment source type where
  // Poultry collapses collections into 'Sale' — so Water's Money In breakdown
  // separates a sale from the cash that later settles it, and Poultry's cannot.
  CustomerPayment: "Customer payments",
  DriverReturn: "Driver returns",
  OwnerDeposit: "Owner contribution",
  Withdrawal: "Owner draw",
  DailyClosing: "Daily closing",
  Maintenance: "Maintenance",
  // Kept close to the raw sourceType on purpose. The account ledger page shows
  // sourceType unlabelled, so anything too friendly here would have the same row
  // reading two different ways on two screens — and this is the one source type
  // an operator is most likely to be cross-checking between them.
  ReconciliationAdjustment: "Reconciliation adjustment",
  Transfer: "Internal transfer",
}

/** Exact values from POULTRY_CASH_REASONS — sppoultrycashaccount_adjust (129:148)
 *  stores the reason verbatim in `description`, which is the only thing that
 *  makes an adjustment breakdown more useful than one grey slice. */
const ADJUSTMENT_REASONS = new Set([
  "Cash shortage",
  "Cash overage",
  "Bank charge",
  "MoMo charge",
  "Unrecorded expense",
  "Unrecorded income",
  "Wrong cash account used",
  "Owner draw not recorded",
  "Owner contribution not recorded",
  "Driver shortage",
  "Driver overage",
  "Rounding difference",
  "Opening balance correction",
  "Other",
])

/** Reasons read better on a cash-flow breakdown without their bookkeeping tail. */
const REASON_LABELS: Record<string, string> = {
  "Owner contribution not recorded": "Owner contribution",
  "Owner draw not recorded": "Owner draw",
  "Unrecorded income": "Other income",
  "Unrecorded expense": "Other spending",
}

export function flowLabel(
  sourceType: string | null | undefined,
  description: string | null | undefined,
): { key: string; label: string } {
  const source = (sourceType ?? "").trim()

  // Customer payments collapse into sourceType 'Sale' (223:439), so Money In
  // would otherwise be one bucket. Adjustments carry their reason as free text,
  // and that is what rescues the breakdown.
  if (source === "Adjustment") {
    const reason = (description ?? "").trim()
    if (ADJUSTMENT_REASONS.has(reason)) {
      return { key: `Adjustment:${reason}`, label: REASON_LABELS[reason] ?? reason }
    }
  }

  if (!source) return { key: "Unknown", label: "Unclassified" }
  // An unrecognised source type is labelled, never blank and never dropped — a
  // sourceType added later should degrade to a readable name, not disappear
  // from a total the owner is trying to reconcile.
  return { key: source, label: SOURCE_LABELS[source] ?? titleCase(source) }
}

export function groupByFlow(entries: LedgerEntry[], direction: FlowDirection): FlowBucket[] {
  const want = direction === "in" ? 1 : -1
  const acc = new Map<string, { label: string; amount: number; count: number }>()
  let total = 0

  for (const e of entries) {
    if (isInternalTransfer(e)) continue
    const amount = Number(e.amount) || 0
    if (amount === 0) continue
    if (Math.sign(amount) !== want) continue

    const magnitude = Math.abs(amount)
    const { key, label } = flowLabel(e.sourceType, e.description)
    const bucket = acc.get(key)
    if (bucket) {
      bucket.amount += magnitude
      bucket.count += 1
    } else {
      acc.set(key, { label, amount: magnitude, count: 1 })
    }
    total += magnitude
  }

  const rows = [...acc.entries()].map(([key, b]) => ({
    key,
    label: b.label,
    amount: round2(b.amount),
    count: b.count,
    percent: 0,
  }))

  rows.sort((a, b) => b.amount - a.amount || a.label.localeCompare(b.label))
  return assignPercentages(rows, total)
}

/**
 * Largest-remainder apportionment, so the percent column sums to exactly 100
 * instead of 99.9. Naive rounding is what makes a breakdown look broken to
 * anyone who adds the column up.
 */
function assignPercentages(rows: FlowBucket[], total: number): FlowBucket[] {
  if (rows.length === 0 || total <= 0) {
    return rows.map((r) => ({ ...r, percent: 0 }))
  }

  const exact = rows.map((r) => (r.amount / total) * 100)
  const floored = exact.map((n) => Math.floor(n * 10) / 10)
  const used = floored.reduce((s, n) => s + n, 0)
  // Work in tenths to avoid accumulating float error while distributing.
  let remaining = Math.round((100 - used) * 10)

  const order = exact
    .map((n, i) => ({ i, frac: n * 10 - Math.floor(n * 10) }))
    .sort((a, b) => b.frac - a.frac)

  const percents = [...floored]
  for (const { i } of order) {
    if (remaining <= 0) break
    percents[i] = Math.round((percents[i] + 0.1) * 10) / 10
    remaining -= 1
  }

  return rows.map((r, i) => ({ ...r, percent: percents[i] }))
}

// ---------------------------------------------------------------------------
// Cash by account
// ---------------------------------------------------------------------------

export interface AccountCashRow extends AccountStatusEntry {
  sharePercent: number
  needsAttention: boolean
  attentionReason: string | null
}

/** Reconciled longer ago than this and the page says so. */
export const STALE_RECONCILE_DAYS = 30

export function cashByAccount(
  status: AccountStatusEntry[],
  opts?: { includeInactive?: boolean },
): AccountCashRow[] {
  // Inactive accounts are included by default: money sitting in a closed account
  // is still the company's money, and hiding it makes cash at hand disagree with
  // the sum of the rows below it.
  const includeInactive = opts?.includeInactive ?? true
  const rows = status.filter((a) => includeInactive || a.isActive)
  const total = rows.reduce((s, a) => s + (Number(a.ledgerBalance) || 0), 0)

  return rows
    .map((a) => {
      const drifted = Math.abs(Number(a.cacheDrift) || 0) >= 0.01
      const never = a.lastReconciledAt == null
      const stale = (a.daysSinceReconciled ?? 0) > STALE_RECONCILE_DAYS

      let attentionReason: string | null = null
      // Drift first: it means the books disagree with themselves, which is a
      // different and more urgent problem than not having been reconciled.
      //
      // "Reconciled", not "counted": this list mixes cash boxes with bank and
      // MoMo accounts, and you do not count a bank account — you check it
      // against a statement. Per-account-type wording lives in
      // components/cash/cash-account-vocabulary.ts; here one neutral word has to
      // cover every row, and reconcile is the one that is true of all of them.
      if (drifted) attentionReason = "Stored balance disagrees with its transactions"
      else if (never) attentionReason = "Never reconciled"
      else if (stale) attentionReason = `Not reconciled in ${a.daysSinceReconciled} days`

      return {
        ...a,
        sharePercent: total > 0 ? round2(((Number(a.ledgerBalance) || 0) / total) * 100) : 0,
        needsAttention: attentionReason !== null,
        attentionReason,
      }
    })
    .sort((a, b) => b.ledgerBalance - a.ledgerBalance || a.accountName.localeCompare(b.accountName))
}

/**
 * Always sums ledgerBalance, never currentBalance. currentBalance is a cache
 * maintained by hand in every posting SP and it drifts; ledgerBalance is
 * openingbalance + SUM(amount) computed on read
 * (223_PoultryCashReconciliation.postgres.sql:882). The difference between them
 * is surfaced as cacheDrift rather than silently picked.
 */
export function calculatedCashAtHand(rows: AccountCashRow[]): number {
  return round2(rows.reduce((s, a) => s + (Number(a.ledgerBalance) || 0), 0))
}

// ---------------------------------------------------------------------------
// The reconciliation identity
// ---------------------------------------------------------------------------

export interface CashIdentity {
  openingTotal: number
  moneyIn: number
  moneyOut: number
  impliedCash: number
  reportedCash: number
  discrepancy: number
  balances: boolean
}

/**
 * Money in minus money out does NOT equal cash at hand, and that surprises
 * everyone who checks. The ledger holds no opening-balance row — opening sits on
 * the account (spPoultryCashAccount_Insert seeds currentBalance = openingBalance
 * and writes no transaction), so the identity only closes with the opening term.
 *
 * Printing the whole sum is what makes the six summary cards defensible instead
 * of mysterious, and it is self-checking: over an all-time range it must close.
 */
export function cashIdentity(args: {
  openingTotal: number
  totals: CashFlowTotals
  reportedCash: number
}): CashIdentity {
  const openingTotal = round2(args.openingTotal)
  const { moneyIn, moneyOut } = args.totals
  const impliedCash = round2(openingTotal + moneyIn - moneyOut)
  const reportedCash = round2(args.reportedCash)
  const discrepancy = round2(impliedCash - reportedCash)

  return {
    openingTotal,
    moneyIn,
    moneyOut,
    impliedCash,
    reportedCash,
    discrepancy,
    balances: Math.abs(discrepancy) < 0.01,
  }
}

// ---------------------------------------------------------------------------
// Transfers panel
// ---------------------------------------------------------------------------

export interface TransferSummary {
  rows: TransferEntry[]
  approvedCount: number
  approvedVolume: number
  pendingCount: number
}

export function summariseTransfers(
  transfers: TransferEntry[],
  range?: { from?: string; to?: string },
): TransferSummary {
  const rows = transfers.filter((t) => {
    const day = (t.transferDate ?? "").split("T")[0]
    if (!day) return true
    if (range?.from && day < range.from) return false
    if (range?.to && day > range.to) return false
    return true
  })

  let approvedCount = 0
  let approvedVolume = 0
  let pendingCount = 0
  for (const t of rows) {
    if (t.status === "Approved") {
      approvedCount += 1
      approvedVolume += Math.abs(Number(t.amount) || 0)
    } else if (t.status === "Draft") {
      pendingCount += 1
    }
  }

  return {
    rows: [...rows].sort((a, b) => (b.transferDate ?? "").localeCompare(a.transferDate ?? "")),
    approvedCount,
    approvedVolume: round2(approvedVolume),
    pendingCount,
  }
}

// ---------------------------------------------------------------------------
// Insights
// ---------------------------------------------------------------------------

export interface CashFlowInsightInput {
  periodLabel: string
  periodDays: number
  totals: CashFlowTotals
  cashAtHand: number
  customersOwe: number
  weOweSuppliers: number
  topIn: FlowBucket | null
  topOut: FlowBucket | null
  accountsNeedingAttention: number
  unlinkedExpenseCount?: number
}

export interface CashFlowInsight {
  id: string
  tone: "good" | "warn" | "bad" | "neutral"
  headline: string
  detail: string
}

/**
 * Plain-language answers to the questions the page exists to answer.
 *
 * `fmt` is injected rather than imported so the sentences can be asserted
 * exactly in tests without pulling in the currency store — pass n => n.toFixed(2)
 * in a test and useFmt() on the page. It is also what keeps the dialog a dumb
 * renderer with no arithmetic of its own.
 *
 * Ordered most-important-first and capped, because six good sentences are read
 * and twelve are skimmed.
 */
export function buildCashFlowInsights(
  input: CashFlowInsightInput,
  fmt: (n: number) => string,
): CashFlowInsight[] {
  const { totals, periodLabel } = input
  const out: CashFlowInsight[] = []

  if (totals.moneyIn === 0 && totals.moneyOut === 0) {
    return [{
      id: "no-movement",
      tone: "neutral",
      headline: "No money moved in this period.",
      detail: `Nothing was received or paid out ${periodLabel.toLowerCase()}. If that looks wrong, check that sales and expenses are being recorded against a cash account.`,
    }]
  }

  if (totals.net > 0) {
    out.push({
      id: "net-positive",
      tone: "good",
      headline: "You kept money this period.",
      detail: `${periodLabel} the business took in ${fmt(totals.moneyIn)} and paid out ${fmt(totals.moneyOut)}, keeping ${fmt(totals.net)}.`,
    })
  } else if (totals.net < 0) {
    out.push({
      id: "net-negative",
      tone: "bad",
      headline: "You spent more than you took in.",
      detail: `${periodLabel} the business took in ${fmt(totals.moneyIn)} and paid out ${fmt(totals.moneyOut)} — ${fmt(Math.abs(totals.net))} more than it earned.`,
    })
  } else {
    out.push({
      id: "net-flat",
      tone: "neutral",
      headline: "Money in and money out were equal.",
      detail: `${periodLabel} the business took in and paid out ${fmt(totals.moneyIn)}.`,
    })
  }

  // Runway only means something while money is actually going out.
  if (totals.net < 0 && totals.moneyOut > 0 && input.periodDays > 0 && input.cashAtHand > 0) {
    const burnPerDay = Math.abs(totals.net) / input.periodDays
    if (burnPerDay > 0) {
      const days = Math.floor(input.cashAtHand / burnPerDay)
      out.push({
        id: "runway",
        tone: days < 30 ? "bad" : "warn",
        headline: `At this rate your cash lasts about ${days} ${days === 1 ? "day" : "days"}.`,
        detail: `You are spending about ${fmt(round2(burnPerDay))} a day more than you take in, and you hold ${fmt(input.cashAtHand)}.`,
      })
    }
  }

  if (input.topIn && input.topIn.percent >= 60) {
    out.push({
      id: "in-concentration",
      tone: "warn",
      headline: "Most of your money comes from one place.",
      detail: `${input.topIn.label} is ${input.topIn.percent}% of everything received. If it stops, most of your income stops with it.`,
    })
  }

  if (input.topOut && input.topOut.percent >= 40) {
    out.push({
      id: "out-concentration",
      tone: "neutral",
      headline: `${input.topOut.label} is your biggest cost.`,
      detail: `${fmt(input.topOut.amount)} went to ${input.topOut.label.toLowerCase()} — ${input.topOut.percent}% of everything paid out.`,
    })
  }

  if (input.weOweSuppliers > input.cashAtHand) {
    out.push({
      id: "payable-risk",
      tone: "bad",
      headline: "You owe suppliers more than you have.",
      detail: `Suppliers are owed ${fmt(input.weOweSuppliers)} and you hold ${fmt(input.cashAtHand)} across all cash accounts.`,
    })
  }

  if (input.customersOwe > input.cashAtHand) {
    out.push({
      id: "receivable-heavy",
      tone: "warn",
      headline: "Customers hold more cash than you do.",
      detail: `Customers owe ${fmt(input.customersOwe)}, more than the ${fmt(input.cashAtHand)} you hold. Collecting is the fastest cash you can raise.`,
    })
  }

  if ((input.unlinkedExpenseCount ?? 0) > 0) {
    const n = input.unlinkedExpenseCount as number
    out.push({
      id: "unlinked-expenses",
      tone: "warn",
      headline: "Some spending is missing from this page.",
      detail: `${n} ${n === 1 ? "expense was" : "expenses were"} recorded without a cash account, so they are not in Money Out. Your real net is lower than shown.`,
    })
  }

  if (input.accountsNeedingAttention > 0) {
    const n = input.accountsNeedingAttention
    out.push({
      id: "stale-accounts",
      tone: "warn",
      headline: `${n} cash ${n === 1 ? "account needs" : "accounts need"} reconciling.`,
      detail: "Cash at hand is calculated from what was recorded. Reconciling confirms it matches the money actually there.",
    })
  }

  return out.slice(0, 6)
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Money, to the cent. Keeps float drift out of totals that get compared. */
function round2(n: number): number {
  return Math.round((Number(n) || 0) * 100) / 100
}

function titleCase(s: string): string {
  return s
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/^./, (c) => c.toUpperCase())
}
