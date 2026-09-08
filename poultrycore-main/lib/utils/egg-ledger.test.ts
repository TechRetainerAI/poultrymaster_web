import { describe, expect, it } from "vitest"
import { buildEggStockLedger, type EggLedgerRow, type EggStockMoveLedgerInput } from "./egg-ledger"
import { groupLedgerByType, EGG_MOVE_LABELS } from "./ledger-breakdown"

/**
 * The real shape this was written for: farm 3c4ac3cd's internal-use churn on
 * 24-26 Aug 2026. IU-2026-0002 (600) was posted and reversed twice and ends
 * Reversed; IU-2026-0003 (450) was posted three times and reversed twice and
 * ends Posted. Nine ledger rows, one live movement.
 */
const move = (
  id: number,
  createdDate: string,
  quantity: number,
  relatedId: number | null,
  txnType = "InternalUse",
): EggStockMoveLedgerInput => ({
  poultryStockTransactionId: id,
  createdDate,
  txnType,
  quantity,
  relatedId,
  note: quantity > 0 ? "Reversal of internal use" : "Internal use",
})

const INTERNAL_USE_CHURN: EggStockMoveLedgerInput[] = [
  move(254, "2026-08-24T11:59:25Z", -600, 2),
  move(255, "2026-08-24T12:24:13Z", -450, 3),
  move(256, "2026-08-24T13:05:30Z", 450, 3),
  move(258, "2026-08-24T23:33:55Z", -450, 3),
  move(259, "2026-08-24T23:34:58Z", 600, 2),
  move(260, "2026-08-26T01:20:32Z", 450, 3),
  move(261, "2026-08-26T01:32:37Z", -450, 3),
  move(262, "2026-08-26T01:44:48Z", -600, 2),
  move(263, "2026-08-26T01:45:36Z", 600, 2),
]

const ledgerOf = (moves: EggStockMoveLedgerInput[]) =>
  buildEggStockLedger([], [], [], [], moves)

const totals = (moves: EggStockMoveLedgerInput[]) => {
  const { rows } = ledgerOf(moves)
  return {
    rows: rows.length,
    in: rows.reduce((t, r) => t + r.in, 0),
    out: rows.reduce((t, r) => t + r.out, 0),
  }
}

describe("buildEggStockLedger — post/reverse netting", () => {
  it("keeps only the live posting out of a post/reverse/post/reverse/post run", () => {
    // IU-3: three postings, two reversals -> one 450 out. IU-2: two of each -> nothing.
    expect(totals(INTERNAL_USE_CHURN)).toEqual({ rows: 1, in: 0, out: 450 })
  })

  it("leaves the balance exactly where it was — every pair summed to zero", () => {
    expect(ledgerOf(INTERNAL_USE_CHURN).currentEggsAtHand).toBe(-450)
  })

  it("does not pair movements of different records, types or sizes", () => {
    const unrelated: EggStockMoveLedgerInput[] = [
      move(1, "2026-08-24T10:00:00Z", -450, 3),
      move(2, "2026-08-24T11:00:00Z", 450, 4),                    // different record
      move(3, "2026-08-24T12:00:00Z", -450, 3, "Driver Load Out"), // different type
      move(4, "2026-08-24T13:00:00Z", 300, 3),                     // different size
    ]
    expect(totals(unrelated)).toEqual({ rows: 4, in: 750, out: 900 })
  })

  it("never cancels hand-posted rows, which have no record to be reversed against", () => {
    // Two equal and opposite manual entries are two decisions, not a reversal.
    const manual: EggStockMoveLedgerInput[] = [
      move(1, "2026-08-24T10:00:00Z", -200, null, "Decrease"),
      move(2, "2026-08-24T11:00:00Z", 200, null, "Increase"),
    ]
    expect(totals(manual)).toEqual({ rows: 2, in: 200, out: 200 })
  })
})

describe("groupLedgerByType — the egg ledger", () => {
  const row = (type: string, inQty: number, outQty: number, seq: number): EggLedgerRow => ({
    sortKey: `${type}_${seq}`, date: "2026-09-01", type, description: type,
    in: inQty, out: outQty, balance: 0, seq,
  })

  const rows: EggLedgerRow[] = [
    row("Production", 600, 0, 0),
    row("Production", 300, 0, 1),
    row("Driver Return In", 100, 0, 2),
    row("Sale", 0, 500, 3),
    row("InternalUse", 0, 300, 4),
    row("Broken eggs", 0, 200, 5),
  ]

  it("buckets by movement type, biggest first, with a count per bucket", () => {
    expect(groupLedgerByType(rows, "in", EGG_MOVE_LABELS).map((b) => [b.label, b.amount, b.count])).toEqual([
      ["Production", 900, 2],
      ["Driver return", 100, 1],
    ])
  })

  it("splits in from out — a row is only ever on one side", () => {
    expect(groupLedgerByType(rows, "out", EGG_MOVE_LABELS).map((b) => [b.label, b.amount])).toEqual([
      ["Sale", 500],
      ["Internal use", 300],
      ["Broken eggs", 200],
    ])
  })

  it("adds up to the tile it decomposes", () => {
    const totalIn = rows.reduce((t, r) => t + r.in, 0)
    expect(groupLedgerByType(rows, "in", EGG_MOVE_LABELS).reduce((t, b) => t + b.amount, 0)).toBe(totalIn)
  })

  it("apportions percentages that sum to exactly 100", () => {
    // Thirds: naive rounding gives 33.3 x 3 = 99.9, which reads as a bug.
    const thirds = [row("Production", 100, 0, 0), row("Restock", 100, 0, 1), row("Adjustment", 100, 0, 2)]
    const pct = groupLedgerByType(thirds, "in", EGG_MOVE_LABELS).map((b) => b.percent)
    expect(pct).toEqual([33.4, 33.3, 33.3])
    // Summed in tenths: adding 33.3 + 33.4 + 33.3 as floats lands on
    // 99.99999999999999, which is float arithmetic, not a bad apportionment.
    expect(pct.reduce((t, n) => t + Math.round(n * 10), 0)).toBe(1000)
  })

  it("has nothing to show for a side with no movements", () => {
    expect(groupLedgerByType([row("Production", 600, 0, 0)], "out", EGG_MOVE_LABELS)).toEqual([])
  })
})
