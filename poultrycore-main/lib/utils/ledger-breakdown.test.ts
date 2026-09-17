import { describe, expect, it } from "vitest"
import { groupLedgerBy, groupLedgerByNet } from "./ledger-breakdown"

/**
 * groupLedgerByNet is the arithmetic behind the trackers' "<noun> left by item"
 * card. Unlike its one-directional siblings it nets a key's ins against its
 * outs, so the cases worth pinning are the ones where that netting decides
 * whether a bucket exists at all.
 */
const row = (type: string, item: string, inQty: number, outQty: number) =>
  ({ type, itemName: item, in: inQty, out: outQty })

const byItem = (r: { itemName: string }) => r.itemName || "Not item-specific"

describe("groupLedgerByNet", () => {
  it("nets each key's ins against its outs", () => {
    const buckets = groupLedgerByNet(
      [
        row("Purchase IN", "Layer mash", 1000, 0),
        row("Usage OUT", "Layer mash", 0, 400),
        row("Purchase IN", "Grower mash", 500, 0),
      ],
      byItem,
    )

    expect(buckets.map((b) => [b.label, b.amount])).toEqual([
      ["Layer mash", 600],
      ["Grower mash", 500],
    ])
  })

  it("counts every movement that touched the key, not just the ins", () => {
    const buckets = groupLedgerByNet(
      [
        row("Purchase IN", "Layer mash", 1000, 0),
        row("Usage OUT", "Layer mash", 0, 400),
        row("Usage OUT", "Layer mash", 0, 100),
      ],
      byItem,
    )

    expect(buckets).toHaveLength(1)
    expect(buckets[0].count).toBe(3)
  })

  it("drops a key that has been fully drawn down", () => {
    const buckets = groupLedgerByNet(
      [
        row("Purchase IN", "Layer mash", 250, 0),
        row("Usage OUT", "Layer mash", 0, 250),
        row("Purchase IN", "Maize", 80, 0),
      ],
      byItem,
    )

    expect(buckets.map((b) => b.label)).toEqual(["Maize"])
  })

  it("drops a key whose netting lands on float dust rather than exactly zero", () => {
    // 0.1 + 0.2 - 0.3 === 5.55e-17, not 0. Without the epsilon this would show
    // as a phantom item holding "0.0".
    const buckets = groupLedgerByNet(
      [
        row("Purchase IN", "Layer mash", 0.1, 0),
        row("Purchase IN", "Layer mash", 0.2, 0),
        row("Usage OUT", "Layer mash", 0, 0.3),
      ],
      byItem,
    )

    expect(buckets).toEqual([])
  })

  it("drops an overdrawn key rather than showing a negative slice", () => {
    const buckets = groupLedgerByNet(
      [
        row("Purchase IN", "Layer mash", 100, 0),
        row("Usage OUT", "Layer mash", 0, 160),
        row("Purchase IN", "Maize", 40, 0),
      ],
      byItem,
    )

    expect(buckets.map((b) => b.label)).toEqual(["Maize"])
  })

  it("apportions percentages over what is left, summing to exactly 100", () => {
    const buckets = groupLedgerByNet(
      [
        row("Purchase IN", "A", 100, 0),
        row("Purchase IN", "B", 100, 0),
        row("Purchase IN", "C", 100, 0),
        // D is overdrawn, so it is excluded from the base as well as the list.
        row("Usage OUT", "D", 0, 50),
      ],
      byItem,
    )

    expect(buckets).toHaveLength(3)
    // Rounded back to tenths the way lib/cash/cash-flow.test.ts does: the
    // apportionment is exact in tenths, but summing 33.3 + 33.3 + 33.4 as
    // floats lands on 99.99999999999999.
    const sum = buckets.reduce((total, b) => total + b.percent, 0)
    expect(Math.round(sum * 10) / 10).toBe(100)
  })

  it("falls back to the caller's label for rows with no item", () => {
    const buckets = groupLedgerByNet(
      [row("Adjustment IN", "", 25, 0)],
      (r) => r.itemName || "Not item-specific",
    )

    expect(buckets.map((b) => b.label)).toEqual(["Not item-specific"])
  })

  it("nets where the one-directional grouping only totals a side", () => {
    const rows = [
      row("Purchase IN", "Layer mash", 1000, 0),
      row("Usage OUT", "Layer mash", 0, 400),
    ]

    expect(groupLedgerBy(rows, "in", byItem)[0].amount).toBe(1000)
    expect(groupLedgerBy(rows, "out", byItem)[0].amount).toBe(400)
    expect(groupLedgerByNet(rows, byItem)[0].amount).toBe(600)
  })
})
