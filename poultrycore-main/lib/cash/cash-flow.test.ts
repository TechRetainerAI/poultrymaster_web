import { describe, expect, it } from "vitest"
import {
  buildCashFlowInsights, cashAccountsForPeriod, cashByAccount, cashFlowTotals, cashIdentity,
  categoryLabel, calculatedCashAtHand, excludeTransfers, flowLabel, groupByFlow, sourceTypeLabel,
  isInternalTransfer, ledgerFromParam, ledgerToParam, summariseTransfers, withinRange,
  type AccountStatusEntry, type CashAccountSeed, type LedgerEntry, type TransferEntry,
} from "./cash-flow"

// Money is plain here so the assertions read as arithmetic, not formatting.
const money = (n: number) => n.toFixed(2)

let nextId = 1
function entry(partial: Partial<LedgerEntry> & { amount: number }): LedgerEntry {
  return {
    id: nextId++,
    accountId: 1,
    transactionDate: "2026-08-10T09:00:00",
    ...partial,
  }
}

// A MoMo -> Bank transfer: two rows, netting to zero.
const TRANSFER_OUT = entry({ amount: -5000, sourceType: "Transfer", transactionType: "TransferOut" })
const TRANSFER_IN = entry({ amount: 5000, sourceType: "Transfer", transactionType: "TransferIn" })

describe("ledger date parameters", () => {
  it("stretches a bare to-date to the end of the day", () => {
    // Without this, "Today" excludes everything recorded today.
    expect(ledgerToParam("2026-08-28")).toBe("2026-08-28T23:59:59.999")
    expect(ledgerFromParam("2026-08-01")).toBe("2026-08-01T00:00:00")
  })

  it("leaves an explicit timestamp alone", () => {
    expect(ledgerToParam("2026-08-28T12:00:00")).toBe("2026-08-28T12:00:00")
  })
})

describe("isInternalTransfer", () => {
  it("catches a transfer by sourceType or by transactionType alone", () => {
    expect(isInternalTransfer(TRANSFER_OUT)).toBe(true)
    expect(isInternalTransfer(entry({ amount: 10, sourceType: "Transfer" }))).toBe(true)
    expect(isInternalTransfer(entry({ amount: 10, transactionType: "TransferIn" }))).toBe(true)
    expect(isInternalTransfer(entry({ amount: 10, sourceType: "Sale" }))).toBe(false)
  })
})

describe("cashFlowTotals", () => {
  it("adds up money in and out, out as a positive magnitude", () => {
    const totals = cashFlowTotals([
      entry({ amount: 12000, sourceType: "Sale" }),
      entry({ amount: -9000, sourceType: "Expense" }),
      entry({ amount: 500, sourceType: "Adjustment", description: "Unrecorded income" }),
    ])
    expect(totals.moneyIn).toBe(12500)
    expect(totals.moneyOut).toBe(9000)
    expect(totals.net).toBe(3500)
    expect(totals.entryCount).toBe(3)
  })

  it("excludes both legs of an internal transfer from in, out and net", () => {
    // The whole point: a MoMo -> Bank move is not income and not spending.
    const withoutTransfer = cashFlowTotals([entry({ amount: 1000, sourceType: "Sale" })])
    const withTransfer = cashFlowTotals([
      entry({ amount: 1000, sourceType: "Sale" }),
      TRANSFER_OUT,
      TRANSFER_IN,
    ])
    expect(withTransfer.moneyIn).toBe(withoutTransfer.moneyIn)
    expect(withTransfer.moneyOut).toBe(withoutTransfer.moneyOut)
    expect(withTransfer.net).toBe(withoutTransfer.net)
  })

  it("reports transfer volume once, not once per leg", () => {
    const totals = cashFlowTotals([TRANSFER_OUT, TRANSFER_IN])
    expect(totals.transferVolume).toBe(5000)
    expect(totals.transferCount).toBe(1)
  })

  it("returns zeroes for an empty ledger", () => {
    const totals = cashFlowTotals([])
    expect(totals).toMatchObject({ moneyIn: 0, moneyOut: 0, net: 0, entryCount: 0 })
  })

  it("keeps cents exact rather than accumulating float error", () => {
    const totals = cashFlowTotals([
      entry({ amount: 0.1, sourceType: "Sale" }),
      entry({ amount: 0.2, sourceType: "Sale" }),
    ])
    expect(totals.moneyIn).toBe(0.3)
  })
})

describe("excludeTransfers", () => {
  it("drops transfer rows and keeps the rest", () => {
    const rows = [entry({ amount: 100, sourceType: "Sale" }), TRANSFER_OUT, TRANSFER_IN]
    expect(excludeTransfers(rows)).toHaveLength(1)
  })
})

describe("flowLabel", () => {
  it("gives sourceTypes owner-facing names", () => {
    expect(flowLabel("Sale", null).label).toBe("Sales")
    expect(flowLabel("RawMaterialPurchase", null).label).toBe("Raw materials")
    expect(flowLabel("PoultrySupplierPayment", null).label).toBe("Supplier payments")
  })

  it("sub-buckets an adjustment by its stored reason", () => {
    // This is what rescues Money In from being one grey slice: customer payments
    // collapse into 'Sale', so adjustments are where the detail lives.
    const owner = flowLabel("Adjustment", "Owner contribution not recorded")
    expect(owner.key).toBe("Adjustment:Owner contribution not recorded")
    expect(owner.label).toBe("Owner contribution")

    const charge = flowLabel("Adjustment", "Bank charge")
    expect(charge.key).toBe("Adjustment:Bank charge")
    expect(charge.label).toBe("Bank charge")
  })

  it("falls back to the plain adjustment label for free text that is not a known reason", () => {
    expect(flowLabel("Adjustment", "whatever someone typed").key).toBe("Adjustment")
  })

  it("title-cases an unknown sourceType rather than rendering blank", () => {
    // A sourceType added later must degrade to something readable, not vanish.
    expect(flowLabel("SomeNewThing", null).label).toBe("Some New Thing")
    expect(flowLabel(null, null).label).toBe("Unclassified")
  })
})

describe("groupByFlow", () => {
  const ROWS = [
    entry({ amount: 12000, sourceType: "Sale" }),
    entry({ amount: 4500, sourceType: "Sale" }),
    entry({ amount: 2000, sourceType: "Adjustment", description: "Owner contribution not recorded" }),
    entry({ amount: 500, sourceType: "Adjustment", description: "Unrecorded income" }),
    entry({ amount: -9000, sourceType: "Expense" }),
    entry({ amount: -3000, sourceType: "Payroll" }),
    TRANSFER_IN,
    TRANSFER_OUT,
  ]

  it("groups inflows by source, largest first, transfers excluded", () => {
    const buckets = groupByFlow(ROWS, "in")
    expect(buckets.map((b) => b.label)).toEqual([
      "Sales", "Owner contribution", "Other income",
    ])
    expect(buckets[0].amount).toBe(16500)
    expect(buckets[0].count).toBe(2)
    expect(buckets.some((b) => b.label === "Internal transfer")).toBe(false)
  })

  it("groups outflows by use", () => {
    const buckets = groupByFlow(ROWS, "out")
    expect(buckets.map((b) => [b.label, b.amount])).toEqual([
      ["Expenses paid", 9000],
      ["Staff wages", 3000],
    ])
  })

  it("makes percentages sum to exactly 100", () => {
    // Three-way splits are where naive rounding lands on 99.9 and looks broken.
    const thirds = groupByFlow([
      entry({ amount: 100, sourceType: "Sale" }),
      entry({ amount: 100, sourceType: "Payroll" }),
      entry({ amount: 100, sourceType: "FeedProduction" }),
    ], "in")
    const sum = thirds.reduce((s, b) => s + b.percent, 0)
    expect(Math.round(sum * 10) / 10).toBe(100)
  })

  it("returns nothing for a direction with no rows", () => {
    expect(groupByFlow([entry({ amount: 100, sourceType: "Sale" })], "out")).toEqual([])
  })
})

describe("cashByAccount", () => {
  const base: AccountStatusEntry = {
    accountId: 1, accountName: "Main Cash", accountType: "FarmCashBox",
    isActive: true, currentBalance: 1000, ledgerBalance: 1000, cacheDrift: 0,
    lastReconciledAt: "2026-08-20T00:00:00", daysSinceReconciled: 8, unclearedCount: 0,
  }

  it("sums ledgerBalance, not the currentBalance cache", () => {
    // currentBalance is the drifting cache; ledgerBalance is opening + SUM.
    const rows = cashByAccount([{ ...base, currentBalance: 9999, ledgerBalance: 1000 }])
    expect(calculatedCashAtHand(rows)).toBe(1000)
  })

  it("flags drift ahead of staleness", () => {
    const rows = cashByAccount([
      { ...base, cacheDrift: -250, daysSinceReconciled: 400 },
    ])
    expect(rows[0].needsAttention).toBe(true)
    expect(rows[0].attentionReason).toBe("Stored balance disagrees with its transactions")
  })

  it("flags an account that has never been reconciled", () => {
    const rows = cashByAccount([{ ...base, lastReconciledAt: null, daysSinceReconciled: null }])
    expect(rows[0].attentionReason).toBe("Never reconciled")
  })

  it("flags a stale reconciliation with the day count", () => {
    const rows = cashByAccount([{ ...base, daysSinceReconciled: 45 }])
    expect(rows[0].attentionReason).toBe("Not reconciled in 45 days")
  })

  it("leaves a recently reconciled account alone", () => {
    expect(cashByAccount([base])[0].needsAttention).toBe(false)
  })

  it("includes inactive accounts by default, since the money is still real", () => {
    const rows = cashByAccount([base, { ...base, accountId: 2, accountName: "Closed", isActive: false, ledgerBalance: 500 }])
    expect(calculatedCashAtHand(rows)).toBe(1500)
    expect(cashByAccount(rows, { includeInactive: false })).toHaveLength(1)
  })

  it("shares add to 100 percent of cash held", () => {
    const rows = cashByAccount([
      base,
      { ...base, accountId: 2, accountName: "MoMo", ledgerBalance: 3000 },
    ])
    expect(rows[0].accountName).toBe("MoMo")   // sorted by balance
    expect(rows[0].sharePercent).toBe(75)
    expect(rows[1].sharePercent).toBe(25)
  })
})

describe("cashAccountsForPeriod", () => {
  const seed = (over: Partial<CashAccountSeed> & { accountId: number }): CashAccountSeed => ({
    accountName: `Account ${over.accountId}`, accountType: "FarmCashBox",
    isActive: true, openingBalance: 0, ...over,
  })
  const statusFor = (accountId: number, over: Partial<AccountStatusEntry> = {}): AccountStatusEntry => ({
    accountId, accountName: `Account ${accountId}`, accountType: "FarmCashBox",
    isActive: true, currentBalance: 0, ledgerBalance: 0, cacheDrift: 0,
    lastReconciledAt: "2026-08-20T00:00:00", daysSinceReconciled: 8, unclearedCount: 0,
    ...over,
  })
  const row = (accountId: number, day: string, amount: number): LedgerEntry => ({
    id: nextId++, accountId, transactionDate: `${day}T09:00:00`, amount,
  })

  const RANGE = { fromDate: "2026-08-01", toDate: "2026-08-31" }

  it("closes the identity: opening + in - out = closing", () => {
    const rows = cashAccountsForPeriod({
      accounts: [seed({ accountId: 1, openingBalance: 500 })],
      status: [statusFor(1)],
      entries: [
        // Before the period: folds into opening, never into in/out.
        row(1, "2026-07-15", 1000),
        row(1, "2026-08-05", 300),
        row(1, "2026-08-20", -125.5),
      ],
      ...RANGE,
    })

    expect(rows).toHaveLength(1)
    const [a] = rows
    expect(a.openingBalance).toBe(1500)
    expect(a.periodIn).toBe(300)
    expect(a.periodOut).toBe(125.5)
    expect(a.closingBalance).toBe(1674.5)
    expect(a.openingBalance + a.periodIn - a.periodOut).toBe(a.closingBalance)
    expect(a.movementCount).toBe(2)
  })

  it("counts the whole of the last day of the range", () => {
    // The rows carry a full timestamp. Comparing them raw against the to-date
    // drops everything recorded after midnight on the final day.
    const rows = cashAccountsForPeriod({
      accounts: [seed({ accountId: 1 })],
      status: [statusFor(1)],
      entries: [row(1, "2026-08-31", 400)],
      ...RANGE,
    })
    expect(rows[0].periodIn).toBe(400)
  })

  it("ignores anything after the period", () => {
    const rows = cashAccountsForPeriod({
      accounts: [seed({ accountId: 1, openingBalance: 100 })],
      status: [statusFor(1)],
      entries: [row(1, "2026-09-02", 9999)],
      ...RANGE,
    })
    expect(rows[0].periodIn).toBe(0)
    expect(rows[0].closingBalance).toBe(100)
  })

  it("keeps an account that never moved", () => {
    // Money sitting still is still money, and a report about where the money is
    // that omits it does not add up.
    const rows = cashAccountsForPeriod({
      accounts: [seed({ accountId: 1, openingBalance: 800 }), seed({ accountId: 2 })],
      status: [statusFor(1), statusFor(2)],
      entries: [],
      ...RANGE,
    })
    expect(rows).toHaveLength(2)
    expect(rows[0].closingBalance).toBe(800)
    expect(rows[1].movementCount).toBe(0)
  })

  it("handles an account opened mid-period", () => {
    const rows = cashAccountsForPeriod({
      accounts: [seed({ accountId: 7, openingBalance: 0 })],
      status: [statusFor(7)],
      entries: [row(7, "2026-08-14", 250)],
      ...RANGE,
    })
    expect(rows[0].openingBalance).toBe(0)
    expect(rows[0].closingBalance).toBe(250)
  })

  it("counts both legs of an internal transfer, one in each account", () => {
    // Deliberately NOT netted out. A transfer is not company-wide cash flow, but
    // it did move money out of one account and into another, and suppressing it
    // would break the identity on both sides.
    const rows = cashAccountsForPeriod({
      accounts: [seed({ accountId: 1, openingBalance: 5000 }), seed({ accountId: 2 })],
      status: [statusFor(1), statusFor(2)],
      entries: [
        { ...row(1, "2026-08-10", -5000), sourceType: "Transfer", transactionType: "TransferOut" },
        { ...row(2, "2026-08-10", 5000), sourceType: "Transfer", transactionType: "TransferIn" },
      ],
      ...RANGE,
    })
    const byId = new Map(rows.map((r) => [r.accountId, r]))
    expect(byId.get(1)!.periodOut).toBe(5000)
    expect(byId.get(1)!.closingBalance).toBe(0)
    expect(byId.get(2)!.periodIn).toBe(5000)
    expect(byId.get(2)!.closingBalance).toBe(5000)
  })

  it("shares out the period's closing cash, not the all-time balance", () => {
    const rows = cashAccountsForPeriod({
      accounts: [seed({ accountId: 1, openingBalance: 750 }), seed({ accountId: 2, openingBalance: 250 })],
      // ledgerBalance is all-time and deliberately disagrees with the period.
      status: [statusFor(1, { ledgerBalance: 99_999 }), statusFor(2, { ledgerBalance: 1 })],
      entries: [],
      ...RANGE,
    })
    expect(rows.map((r) => r.sharePercent)).toEqual([75, 25])
    expect(rows.reduce((s, r) => s + r.sharePercent, 0)).toBe(100)
  })

  it("passes the as-of-now verdict through untouched", () => {
    // Drift and reconciliation age come from a function with no date parameter,
    // so they describe today whatever period was asked for.
    const rows = cashAccountsForPeriod({
      accounts: [seed({ accountId: 1 })],
      status: [statusFor(1, { cacheDrift: -40, daysSinceReconciled: 400 })],
      entries: [],
      ...RANGE,
    })
    expect(rows[0].cacheDrift).toBe(-40)
    expect(rows[0].attentionReason).toBe("Stored balance disagrees with its transactions")
  })

  it("keeps an account that has a status row but no account record", () => {
    const rows = cashAccountsForPeriod({
      accounts: [],
      status: [statusFor(3, { accountName: "Closed MoMo" })],
      entries: [row(3, "2026-08-04", 60)],
      ...RANGE,
    })
    expect(rows).toHaveLength(1)
    expect(rows[0].accountName).toBe("Closed MoMo")
    expect(rows[0].periodIn).toBe(60)
  })
})

describe("cashIdentity", () => {
  it("closes when opening + in - out equals cash at hand", () => {
    const totals = cashFlowTotals([
      entry({ amount: 12450, sourceType: "Sale" }),
      entry({ amount: -9310, sourceType: "Expense" }),
    ])
    const id = cashIdentity({ openingTotal: 1200, totals, reportedCash: 4340 })
    expect(id.impliedCash).toBe(4340)
    expect(id.discrepancy).toBe(0)
    expect(id.balances).toBe(true)
  })

  it("reports the gap when it does not close", () => {
    const totals = cashFlowTotals([entry({ amount: 100, sourceType: "Sale" })])
    const id = cashIdentity({ openingTotal: 0, totals, reportedCash: 250 })
    expect(id.discrepancy).toBe(-150)
    expect(id.balances).toBe(false)
  })
})

describe("summariseTransfers", () => {
  const T = (over: Partial<TransferEntry>): TransferEntry => ({
    id: 1, transferDate: "2026-08-10T00:00:00",
    amount: 5000, status: "Approved", ...over,
  })

  it("counts approved volume and pending drafts separately", () => {
    const s = summariseTransfers([
      T({ id: 1 }),
      T({ id: 2, status: "Draft" }),
      T({ id: 3, status: "Cancelled" }),
    ])
    expect(s.approvedCount).toBe(1)
    expect(s.approvedVolume).toBe(5000)
    expect(s.pendingCount).toBe(1)
    expect(s.rows).toHaveLength(3)
  })

  it("filters to the selected range", () => {
    const s = summariseTransfers(
      [T({ transferDate: "2026-07-01T00:00:00" }), T({ transferDate: "2026-08-15T00:00:00" })],
      { from: "2026-08-01", to: "2026-08-31" },
    )
    expect(s.rows).toHaveLength(1)
  })
})

describe("buildCashFlowInsights", () => {
  const BASE = {
    periodLabel: "This month", periodDays: 30,
    totals: cashFlowTotals([
      entry({ amount: 18000, sourceType: "Sale" }),
      entry({ amount: -21500, sourceType: "Expense" }),
    ]),
    cashAtHand: 4340, customersOwe: 2000, weOweSuppliers: 1000,
    topIn: null, topOut: null,
  }

  it("says plainly that the business spent more than it earned", () => {
    const [first] = buildCashFlowInsights(BASE, money)
    expect(first.id).toBe("net-negative")
    expect(first.tone).toBe("bad")
    expect(first.detail).toContain("18000.00")
    expect(first.detail).toContain("21500.00")
    expect(first.detail).toContain("3500.00")
  })

  it("says plainly when money was kept", () => {
    const totals = cashFlowTotals([
      entry({ amount: 4500, sourceType: "Sale" }),
      entry({ amount: -3200, sourceType: "Expense" }),
    ])
    const [first] = buildCashFlowInsights({ ...BASE, totals }, money)
    expect(first.id).toBe("net-positive")
    expect(first.detail).toContain("1300.00")
  })

  it("handles the exactly-zero case without claiming either direction", () => {
    const totals = cashFlowTotals([
      entry({ amount: 1000, sourceType: "Sale" }),
      entry({ amount: -1000, sourceType: "Expense" }),
    ])
    const [first] = buildCashFlowInsights({ ...BASE, totals }, money)
    expect(first.id).toBe("net-flat")
  })

  it("returns a single friendly line when nothing happened", () => {
    const insights = buildCashFlowInsights({ ...BASE, totals: cashFlowTotals([]) }, money)
    expect(insights).toHaveLength(1)
    expect(insights[0].id).toBe("no-movement")
  })

  it("works out how long the cash lasts when burning", () => {
    // 3500 over 30 days is ~116.67/day; 4340 in hand is 37 days.
    const runway = buildCashFlowInsights(BASE, money).find((i) => i.id === "runway")
    expect(runway?.headline).toBe("At this rate your cash lasts about 37 days.")
  })

  it("does not talk about runway when the business is cash positive", () => {
    const totals = cashFlowTotals([entry({ amount: 500, sourceType: "Sale" })])
    const ids = buildCashFlowInsights({ ...BASE, totals }, money).map((i) => i.id)
    expect(ids).not.toContain("runway")
  })

  it("warns when one source dominates income", () => {
    const topIn = { key: "Sale", label: "Sales", amount: 18000, count: 3, percent: 92 }
    const ids = buildCashFlowInsights({ ...BASE, topIn }, money).map((i) => i.id)
    expect(ids).toContain("in-concentration")
  })

  it("stays quiet about concentration when income is spread", () => {
    const topIn = { key: "Sale", label: "Sales", amount: 100, count: 1, percent: 35 }
    const ids = buildCashFlowInsights({ ...BASE, topIn }, money).map((i) => i.id)
    expect(ids).not.toContain("in-concentration")
  })

  it("raises the alarm when suppliers are owed more than the business holds", () => {
    const i = buildCashFlowInsights({ ...BASE, weOweSuppliers: 99999 }, money)
      .find((x) => x.id === "payable-risk")
    expect(i?.tone).toBe("bad")
  })

  it("leaves data-quality problems to the warnings, and says so only once", () => {
    // These two used to be emitted here AND rendered as alerts by the page.
    const ids = buildCashFlowInsights(BASE, money).map((i) => i.id)
    expect(ids).not.toContain("unlinked-expenses")
    expect(ids).not.toContain("stale-accounts")
  })

  it("never returns more than six", () => {
    const insights = buildCashFlowInsights({
      ...BASE,
      topIn: { key: "Sale", label: "Sales", amount: 18000, count: 3, percent: 92 },
      topOut: { key: "Expense", label: "Expenses paid", amount: 21500, count: 5, percent: 88 },
      weOweSuppliers: 99999, customersOwe: 99999,
    }, money)
    expect(insights.length).toBeLessThanOrEqual(6)
  })
})

describe("sourceTypeLabel", () => {
  it("uses the same words GET /Cash returns, so both pages name a movement alike", () => {
    // CashController.cs:74,93 and FormatAdjustmentType at :189.
    expect(sourceTypeLabel("Sale")).toBe("Sale")
    expect(sourceTypeLabel("Expense")).toBe("Expense")
    expect(sourceTypeLabel("OwnerInjection")).toBe("Owner injection")
    expect(sourceTypeLabel("LoanReceived")).toBe("Loan received")
    expect(sourceTypeLabel("OpeningBalance")).toBe("Opening Balance")
  })

  it("calls a customer receipt a Sale, because the Cash page does", () => {
    // The cash-flow SPs separate a receipt from the sale that created it
    // (235:117); GET /Cash does not (CashController.cs:74). A column whose job is
    // to match the Cash page matches it — Category still tells the two apart.
    expect(sourceTypeLabel("CustomerPayment")).toBe("Sale")
    expect(sourceTypeLabel("Sale")).toBe("Sale")
  })

  it("says something different from categoryLabel for the same row", () => {
    // Adjacent columns: this says what the row IS, categoryLabel what it was FOR.
    expect(sourceTypeLabel("Expense")).toBe("Expense")
    expect(categoryLabel("Expense")).toBe("Expenses paid")
  })

  it("title-cases an unknown type rather than dropping it", () => {
    expect(sourceTypeLabel("DriverReturn")).toBe("Driver Return")
    expect(sourceTypeLabel(null)).toBe("—")
    expect(sourceTypeLabel("  ")).toBe("—")
  })
})

describe("categoryLabel", () => {
  it("spells out adjustment enum values rather than dumping them raw", () => {
    // These reach the report straight from the legacy /Cash table.
    expect(categoryLabel("OwnerInjection")).toBe("Owner injection")
    expect(categoryLabel("LoanReceived")).toBe("Loan received")
    expect(categoryLabel("OpeningBalance")).toBe("Opening balance")
  })

  it("names the same money the same way as the Cash Flow page", () => {
    // 233 emits the literal "Sales"; the page's flowLabel emits "Sales
    // collected" from sourceType "Sale". Both must land on one label or the two
    // screens name the same bucket differently.
    expect(categoryLabel("Sales")).toBe(flowLabel("Sale", null).label)
    expect(categoryLabel("Transfer")).toBe("Internal transfer")
    expect(categoryLabel("Internal transfer")).toBe("Internal transfer")
  })

  it("says why an uncategorised bucket exists", () => {
    expect(categoryLabel("Uncategorised")).toBe("No category set")
  })

  it("leaves a farm's own expense categories exactly as they typed them", () => {
    // Not ours to rewrite — these are the user's bookkeeping words.
    expect(categoryLabel("Feed")).toBe("Feed")
    expect(categoryLabel("Veterinary")).toBe("Veterinary")
    expect(categoryLabel("Labor")).toBe("Labor")
    expect(categoryLabel("Brooding gas")).toBe("Brooding gas")
  })

  it("splits an unmapped CamelCase source rather than showing it glued", () => {
    expect(categoryLabel("SomeNewSourceType")).toBe("Some New Source Type")
  })

  it("never returns blank", () => {
    expect(categoryLabel("")).toBe("Unclassified")
    expect(categoryLabel(null)).toBe("Unclassified")
    expect(categoryLabel(undefined)).toBe("Unclassified")
    expect(categoryLabel("   ")).toBe("Unclassified")
  })
})

describe("adjustment labels", () => {
  it("names the adjustment source types properly", () => {
    expect(flowLabel("ReconciliationAdjustment", null).label).toBe("Cash account reconciliation")
    expect(flowLabel("Adjustment", "whatever someone typed").label).toBe("Cash account adjustment")
    expect(flowLabel("LegacyAdjustment", null).label).toBe("Cash adjustment")
  })

  it("still prefers a known reason over the generic name", () => {
    // The reason is more specific than "Cash account adjustment", so it wins.
    expect(flowLabel("Adjustment", "Owner contribution not recorded").label).toBe("Owner contribution")
  })

  it("keeps the account ledger and the cash flow page saying the same thing", () => {
    // The ledger renders sourceType through categoryLabel; the breakdown goes
    // through flowLabel. Both must land on one name for the same row.
    expect(categoryLabel("Adjustment")).toBe(flowLabel("Adjustment", null).label)
    expect(categoryLabel("ReconciliationAdjustment"))
      .toBe(flowLabel("ReconciliationAdjustment", null).label)
    expect(categoryLabel("LegacyAdjustment")).toBe(flowLabel("LegacyAdjustment", null).label)
  })
})

describe("withinRange", () => {
  it("includes both ends of the range", () => {
    expect(withinRange("2026-09-01T00:00:00", "2026-09-01", "2026-09-30")).toBe(true)
    expect(withinRange("2026-09-30T00:00:00", "2026-09-01", "2026-09-30")).toBe(true)
  })

  it("keeps a row recorded late on the last day", () => {
    // The bug this exists to avoid: comparing the full timestamp against a bare
    // end date drops everything after midnight on the final day.
    expect(withinRange("2026-09-30T23:59:59.999", "2026-09-01", "2026-09-30")).toBe(true)
  })

  it("excludes either side", () => {
    expect(withinRange("2026-08-31T23:00:00", "2026-09-01", "2026-09-30")).toBe(false)
    expect(withinRange("2026-10-01T00:00:00", "2026-09-01", "2026-09-30")).toBe(false)
  })

  it("excludes a missing date rather than treating it as the epoch", () => {
    expect(withinRange(null, "2026-09-01", "2026-09-30")).toBe(false)
    expect(withinRange(undefined, "2026-09-01", "2026-09-30")).toBe(false)
    expect(withinRange("", "2026-09-01", "2026-09-30")).toBe(false)
  })

  it("handles a bare date with no time part", () => {
    expect(withinRange("2026-09-15", "2026-09-01", "2026-09-30")).toBe(true)
  })
})
