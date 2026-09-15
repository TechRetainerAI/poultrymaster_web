import { describe, it, expect } from "vitest"
import {
  buildFeedItemMovements,
  buildFeedItemPositions,
  summariseFeedPositions,
  feedItemKind,
  productionQty,
  type FeedItemLedgerInput,
} from "./feed-item-ledger"
import type {
  PoultryRawMaterialItem,
  PoultryRawMaterialPurchase,
  PoultryRawMaterialUsage,
  PoultryRawMaterialAdjustment,
} from "@/lib/api/poultry-inventory"

const item = (o: Partial<PoultryRawMaterialItem> & { poultryRawMaterialItemId: number }) => ({
  farmId: "f", itemName: `Item ${o.poultryRawMaterialItemId}`, category: "FeedIngredient",
  unitOfMeasure: "Kilogram", minimumStockAlert: 0, currentQuantity: 0, isActive: true,
  usageMethod: "FIFO" as const, createdAt: "2026-01-01T00:00:00",
  ...o,
}) as PoultryRawMaterialItem

const purchase = (o: Partial<PoultryRawMaterialPurchase> & { poultryRawMaterialPurchaseId: number; poultryRawMaterialItemId: number }) => ({
  farmId: "f", purchaseDate: "2026-02-10T00:00:00", quantity: 0, unitCost: 0, totalCost: 0,
  remainingQuantity: 0, amountPaid: 0, balance: 0, createdAt: "2026-02-10T00:00:00",
  ...o,
}) as PoultryRawMaterialPurchase

const usage = (o: Partial<PoultryRawMaterialUsage> & { poultryRawMaterialUsageId: number; poultryRawMaterialItemId: number }) => ({
  farmId: "f", usedDate: "2026-02-15T00:00:00", quantityUsed: 0, variance: 0,
  createdAt: "2026-02-15T00:00:00",
  ...o,
}) as PoultryRawMaterialUsage

const adjustment = (o: Partial<PoultryRawMaterialAdjustment> & { poultryRawMaterialAdjustmentId: number; poultryRawMaterialItemId: number }) => ({
  farmId: "f", adjustedDate: "2026-02-20T00:00:00", quantity: 0, createdAt: "2026-02-20T00:00:00",
  ...o,
}) as PoultryRawMaterialAdjustment

const empty: FeedItemLedgerInput = { items: [], purchases: [], usages: [], adjustments: [] }

describe("feedItemKind", () => {
  it("splits the two feed categories and ignores everything else", () => {
    expect(feedItemKind("FeedIngredient")).toBe("Ingredient")
    expect(feedItemKind("FinishedFeed")).toBe("FinishedFeed")
    // Free-text by convention (migration 167), so spelling variants must land.
    expect(feedItemKind("Finished Feed")).toBe("FinishedFeed")
    expect(feedItemKind("feed ingredient")).toBe("Ingredient")
    for (const c of ["Medication", "Packaging", "Grain", "Equipment", "", null]) {
      expect(feedItemKind(c)).toBeNull()
    }
  })
})

describe("productionQty", () => {
  it("converts a purchase from its purchase unit into stock units", () => {
    expect(productionQty(purchase({ poultryRawMaterialPurchaseId: 1, poultryRawMaterialItemId: 1, quantity: 10, productionUnitsPerPurchaseUnit: 50 }))).toBe(500)
  })

  it("treats a missing or zero factor as 1, like migration 175's NULLIF", () => {
    expect(productionQty(purchase({ poultryRawMaterialPurchaseId: 1, poultryRawMaterialItemId: 1, quantity: 40 }))).toBe(40)
    expect(productionQty(purchase({ poultryRawMaterialPurchaseId: 2, poultryRawMaterialItemId: 1, quantity: 40, productionUnitsPerPurchaseUnit: 0 }))).toBe(40)
  })
})

describe("buildFeedItemMovements", () => {
  const input: FeedItemLedgerInput = {
    items: [
      item({ poultryRawMaterialItemId: 1, itemName: "Maize", currentQuantity: 700 }),
      item({ poultryRawMaterialItemId: 2, itemName: "Layer Mash", category: "FinishedFeed", currentQuantity: 0 }),
      item({ poultryRawMaterialItemId: 9, itemName: "Vaccine", category: "Medication", currentQuantity: 5 }),
    ],
    purchases: [
      purchase({ poultryRawMaterialPurchaseId: 11, poultryRawMaterialItemId: 1, purchaseDate: "2026-02-01T00:00:00", quantity: 10, productionUnitsPerPurchaseUnit: 100, supplierName: "Agro Ltd" }),
      purchase({ poultryRawMaterialPurchaseId: 12, poultryRawMaterialItemId: 9, purchaseDate: "2026-02-01T00:00:00", quantity: 5 }),
    ],
    usages: [
      usage({ poultryRawMaterialUsageId: 21, poultryRawMaterialItemId: 1, usedDate: "2026-02-05T00:00:00", quantityUsed: 300, poultryFeedProductionBatchId: 4, feedProductionBatchNumber: "FB-4", feedProductionFeedName: "Layer Mash" }),
    ],
    adjustments: [
      adjustment({ poultryRawMaterialAdjustmentId: 31, poultryRawMaterialItemId: 1, adjustedDate: "2026-02-08T00:00:00", quantity: -50, movementType: "Correction", note: "spillage" }),
    ],
  }

  it("keeps one running balance per item, in ledger order", () => {
    const maize = buildFeedItemMovements(input).get(1)!
    expect(maize.map((m) => [m.label, m.inQty, m.outQty, m.balance])).toEqual([
      ["Purchase", 1000, 0, 1000],
      ["Used in feed production", 0, 300, 700],
      ["Correction", 0, 50, 650],
    ])
  })

  it("excludes items outside the two feed categories", () => {
    const moves = buildFeedItemMovements(input)
    expect(moves.has(9)).toBe(false)
  })

  it("keeps a feed item that has never moved", () => {
    expect(buildFeedItemMovements(input).get(2)).toEqual([])
  })

  it("orders same-day movements stock-in, stock-out, correction", () => {
    const sameDay: FeedItemLedgerInput = {
      ...empty,
      items: [item({ poultryRawMaterialItemId: 1 })],
      adjustments: [adjustment({ poultryRawMaterialAdjustmentId: 1, poultryRawMaterialItemId: 1, adjustedDate: "2026-03-01T00:00:00", quantity: -5, movementType: "Correction" })],
      usages: [usage({ poultryRawMaterialUsageId: 1, poultryRawMaterialItemId: 1, usedDate: "2026-03-01T00:00:00", quantityUsed: 20 })],
      purchases: [purchase({ poultryRawMaterialPurchaseId: 1, poultryRawMaterialItemId: 1, purchaseDate: "2026-03-01T00:00:00", quantity: 100 })],
    }
    expect(buildFeedItemMovements(sameDay).get(1)!.map((m) => m.kind))
      .toEqual(["Purchase", "Usage", "Adjustment"])
  })

  it("labels produced feed and production purchases apart from an ordinary purchase", () => {
    const fromBatch: FeedItemLedgerInput = {
      ...empty,
      items: [item({ poultryRawMaterialItemId: 2, category: "FinishedFeed" })],
      purchases: [
        purchase({ poultryRawMaterialPurchaseId: 1, poultryRawMaterialItemId: 2, quantity: 500, sourceFeedProductionBatchId: 7, feedProductionBatchNumber: "FB-7", feedProductionRole: "Produced" }),
        purchase({ poultryRawMaterialPurchaseId: 2, poultryRawMaterialItemId: 2, purchaseDate: "2026-02-11T00:00:00", quantity: 20, sourceFeedProductionBatchId: 7, feedProductionBatchNumber: "FB-7", feedProductionRole: "Purchased" }),
        purchase({ poultryRawMaterialPurchaseId: 3, poultryRawMaterialItemId: 2, purchaseDate: "2026-02-12T00:00:00", quantity: 30 }),
      ],
    }
    expect(buildFeedItemMovements(fromBatch).get(2)!.map((m) => m.label))
      .toEqual(["Produced", "Bought for production", "Purchase"])
  })

  it("keeps reversed draws in the ledger and marks them", () => {
    const reversed: FeedItemLedgerInput = {
      ...empty,
      items: [item({ poultryRawMaterialItemId: 1 })],
      usages: [usage({ poultryRawMaterialUsageId: 1, poultryRawMaterialItemId: 1, quantityUsed: 40, isReversed: true, operationalCost: 240 })],
      adjustments: [adjustment({ poultryRawMaterialAdjustmentId: 1, poultryRawMaterialItemId: 1, adjustedDate: "2026-02-16T00:00:00", quantity: 40, movementType: "ProductionReversal" })],
    }
    const rows = buildFeedItemMovements(reversed).get(1)!
    expect(rows[0].reversed).toBe(true)
    expect(rows[1].label).toBe("Production reversed")
    // The pair nets to zero rather than either row being dropped.
    expect(rows[1].balance).toBe(0)
  })
})

describe("buildFeedItemPositions", () => {
  const input: FeedItemLedgerInput = {
    items: [item({ poultryRawMaterialItemId: 1, itemName: "Maize", currentQuantity: 650 })],
    purchases: [
      purchase({ poultryRawMaterialPurchaseId: 1, poultryRawMaterialItemId: 1, purchaseDate: "2026-01-10T00:00:00", quantity: 400 }),
      purchase({ poultryRawMaterialPurchaseId: 2, poultryRawMaterialItemId: 1, purchaseDate: "2026-02-10T00:00:00", quantity: 600 }),
    ],
    usages: [
      usage({ poultryRawMaterialUsageId: 1, poultryRawMaterialItemId: 1, usedDate: "2026-01-20T00:00:00", quantityUsed: 100 }),
      usage({ poultryRawMaterialUsageId: 2, poultryRawMaterialItemId: 1, usedDate: "2026-02-20T00:00:00", quantityUsed: 250 }),
    ],
    adjustments: [],
  }

  it("opens on everything before the window and closes on opening + in - out", () => {
    const [pos] = buildFeedItemPositions(input, "2026-02-01", "2026-02-28")
    expect(pos.opening).toBe(300)      // 400 in, 100 out, all in January
    expect(pos.inQty).toBe(600)
    expect(pos.outQty).toBe(250)
    expect(pos.closing).toBe(650)
    expect(pos.movementCount).toBe(2)
  })

  it("includes both boundary days", () => {
    const [pos] = buildFeedItemPositions(input, "2026-02-10", "2026-02-20")
    expect(pos.movementCount).toBe(2)
    expect(pos.opening).toBe(300)
  })

  it("reports drift when the stored stock figure disagrees with its own rows", () => {
    const drifted = { ...input, items: [item({ poultryRawMaterialItemId: 1, currentQuantity: 5030 })] }
    const [pos] = buildFeedItemPositions(drifted, "2026-02-01", "2026-02-28")
    expect(pos.derivedNow).toBe(650)
    expect(pos.onRecord).toBe(5030)
    expect(pos.drift).toBe(-4380)
  })

  it("reconciles to zero drift when the identity holds", () => {
    const [pos] = buildFeedItemPositions(input, "2026-02-01", "2026-02-28")
    expect(pos.drift).toBe(0)
  })

  it("treats an empty window as all time", () => {
    const [pos] = buildFeedItemPositions(input, "", "")
    expect(pos.opening).toBe(0)
    expect(pos.closing).toBe(650)
    expect(pos.movementCount).toBe(4)
  })
})

describe("summariseFeedPositions", () => {
  // Two kilogram items and one bag item — the shape of the one live farm that
  // holds both units in the same half of its feed store.
  const input: FeedItemLedgerInput = {
    items: [
      item({ poultryRawMaterialItemId: 1, itemName: "Maize", currentQuantity: 300 }),
      item({ poultryRawMaterialItemId: 2, itemName: "Soya", currentQuantity: 200 }),
      item({ poultryRawMaterialItemId: 3, itemName: "Bagged mash", unitOfMeasure: "Bag", currentQuantity: 12 }),
      item({ poultryRawMaterialItemId: 9, itemName: "Vaccine", category: "Medication", currentQuantity: 99 }),
    ],
    purchases: [
      purchase({ poultryRawMaterialPurchaseId: 1, poultryRawMaterialItemId: 1, purchaseDate: "2026-02-02T00:00:00", quantity: 500 }),
      purchase({ poultryRawMaterialPurchaseId: 2, poultryRawMaterialItemId: 2, purchaseDate: "2026-02-02T00:00:00", quantity: 200 }),
      purchase({ poultryRawMaterialPurchaseId: 3, poultryRawMaterialItemId: 3, purchaseDate: "2026-02-02T00:00:00", quantity: 12 }),
    ],
    usages: [
      usage({ poultryRawMaterialUsageId: 1, poultryRawMaterialItemId: 1, usedDate: "2026-02-09T00:00:00", quantityUsed: 200 }),
    ],
    adjustments: [],
  }

  it("groups the roll-up by stocking unit instead of summing across them", () => {
    const totals = summariseFeedPositions(buildFeedItemPositions(input, "2026-02-01", "2026-02-28"))
    expect(totals.map((t) => t.unit)).toEqual(["Kilogram", "Bag"])

    const [kg, bag] = totals
    expect(kg.items).toBe(2)
    expect(kg.inQty).toBe(700)
    expect(kg.outQty).toBe(200)
    expect(kg.closing).toBe(500)
    expect(kg.onRecord).toBe(500)
    expect(kg.movementCount).toBe(3)

    expect(bag.items).toBe(1)
    expect(bag.closing).toBe(12)
  })

  it("leaves out items that are not feed", () => {
    const totals = summariseFeedPositions(buildFeedItemPositions(input, "", ""))
    expect(totals.reduce((n, t) => n + t.items, 0)).toBe(3)
  })

  it("counts how many items disagree with their stored stock figure", () => {
    const drifted = {
      ...input,
      items: [...input.items.slice(0, 2), item({ poultryRawMaterialItemId: 3, unitOfMeasure: "Bag", currentQuantity: 99 })],
    }
    const totals = summariseFeedPositions(buildFeedItemPositions(drifted, "2026-02-01", "2026-02-28"))
    expect(totals.find((t) => t.unit === "Kilogram")!.driftItems).toBe(0)
    expect(totals.find((t) => t.unit === "Bag")!.driftItems).toBe(1)
  })

  it("gives a single line when every item shares one unit", () => {
    const oneUnit = { ...input, items: input.items.filter((i) => i.poultryRawMaterialItemId !== 3) }
    const totals = summariseFeedPositions(buildFeedItemPositions(oneUnit, "2026-02-01", "2026-02-28"))
    expect(totals).toHaveLength(1)
    expect(totals[0].unit).toBe("Kilogram")
  })

  it("returns nothing when there are no feed items", () => {
    expect(summariseFeedPositions([])).toEqual([])
  })
})
