import { describe, it, expect } from "vitest"
import { buildFeedStockLedger, isFeedItem, type FeedStockLedgerInput } from "./feed-ledger"
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

/** Maize is an ingredient, Layer Mash is finished feed, Vaccine is neither. */
const base: Omit<FeedStockLedgerInput, "kind"> = {
  items: [
    item({ poultryRawMaterialItemId: 1, itemName: "Maize", purchaseUnitOfMeasure: "Bag" }),
    item({ poultryRawMaterialItemId: 2, itemName: "Layer Mash", category: "FinishedFeed" }),
    item({ poultryRawMaterialItemId: 9, itemName: "Vaccine", category: "Medication" }),
  ],
  purchases: [
    // Bought as 10 bags of 50kg. Stock is held in kg, so this is 500, not 10.
    purchase({ poultryRawMaterialPurchaseId: 11, poultryRawMaterialItemId: 1, purchaseDate: "2026-02-01T00:00:00", quantity: 10, productionUnitsPerPurchaseUnit: 50, supplierName: "Agro Ltd" }),
    purchase({ poultryRawMaterialPurchaseId: 12, poultryRawMaterialItemId: 2, purchaseDate: "2026-02-02T00:00:00", quantity: 800 }),
    purchase({ poultryRawMaterialPurchaseId: 13, poultryRawMaterialItemId: 9, purchaseDate: "2026-02-02T00:00:00", quantity: 5 }),
  ],
  usages: [
    usage({ poultryRawMaterialUsageId: 21, poultryRawMaterialItemId: 1, usedDate: "2026-02-05T00:00:00", quantityUsed: 200, poultryFeedProductionBatchId: 4, feedProductionBatchNumber: "FB-4" }),
    usage({ poultryRawMaterialUsageId: 22, poultryRawMaterialItemId: 2, usedDate: "2026-02-06T00:00:00", quantityUsed: 300 }),
  ],
  adjustments: [
    adjustment({ poultryRawMaterialAdjustmentId: 31, poultryRawMaterialItemId: 1, adjustedDate: "2026-02-08T00:00:00", quantity: -50, movementType: "Correction" }),
  ],
}

describe("buildFeedStockLedger — purchase units", () => {
  it("counts a purchase in the unit the item is STOCKED in, not bought in", () => {
    const { rows, totalInKg } = buildFeedStockLedger({ ...base, kind: "Ingredient" })
    // 10 bags x 50 = 500 kg. Summing `quantity` raw gave 10, which is the bug
    // this test exists to keep fixed.
    expect(rows[0].in).toBe(500)
    expect(totalInKg).toBe(500)
  })

  it("says what it converted from, so the row is still recognisable", () => {
    const { rows } = buildFeedStockLedger({ ...base, kind: "Ingredient" })
    expect(rows[0].description).toContain("bought as 10 Bag × 50")
  })

  it("leaves a 1:1 item exactly as entered", () => {
    const { rows } = buildFeedStockLedger({ ...base, kind: "FinishedFeed" })
    expect(rows[0].in).toBe(800)
    expect(rows[0].description).not.toContain("bought as")
  })

  it("treats a zero conversion factor as 1 rather than erasing the purchase", () => {
    const zero = {
      ...base,
      kind: "Ingredient" as const,
      purchases: [purchase({ poultryRawMaterialPurchaseId: 1, poultryRawMaterialItemId: 1, quantity: 40, productionUnitsPerPurchaseUnit: 0 })],
      usages: [],
      adjustments: [],
    }
    expect(buildFeedStockLedger(zero).rows[0].in).toBe(40)
  })
})

describe("buildFeedStockLedger — one half of the store at a time", () => {
  it("keeps ingredients out of the finished-feed ledger", () => {
    const { rows, feedKgAtHand } = buildFeedStockLedger({ ...base, kind: "FinishedFeed" })
    expect(rows.map((r) => r.itemName)).toEqual(["Layer Mash", "Layer Mash"])
    expect(feedKgAtHand).toBe(500) // 800 in, 300 out
  })

  it("keeps finished feed out of the ingredient ledger", () => {
    const { rows, feedKgAtHand } = buildFeedStockLedger({ ...base, kind: "Ingredient" })
    expect(rows.map((r) => r.itemName)).toEqual(["Maize", "Maize", "Maize"])
    expect(feedKgAtHand).toBe(250) // 500 in, 200 out, 50 corrected away
  })

  it("excludes items that are not feed at all from both halves", () => {
    for (const kind of ["Ingredient", "FinishedFeed"] as const) {
      const { rows } = buildFeedStockLedger({ ...base, kind })
      expect(rows.some((r) => r.itemName === "Vaccine")).toBe(false)
    }
  })

  it("does not let a movement row's own category pull in the other half", () => {
    // The purchase row claims FinishedFeed, but the item list — the authority —
    // says item 1 is an ingredient. The ingredient ledger keeps it; the finished
    // feed ledger must not also claim it, or the same stock is counted twice.
    const crossed = {
      ...base,
      purchases: [purchase({ poultryRawMaterialPurchaseId: 1, poultryRawMaterialItemId: 1, quantity: 100, category: "FinishedFeed" })],
      usages: [],
      adjustments: [],
    }
    expect(buildFeedStockLedger({ ...crossed, kind: "FinishedFeed" }).rows).toHaveLength(0)
    expect(buildFeedStockLedger({ ...crossed, kind: "Ingredient" }).rows).toHaveLength(1)
  })

  it("adds the whole-farm manual corrections wherever they are passed", () => {
    const { feedKgAtHand } = buildFeedStockLedger({
      ...base,
      kind: "FinishedFeed",
      manualAdjustments: [{ adjustmentId: 1, adjustmentDate: "2026-02-09T00:00:00", feedDeltaKg: -100, adjustmentType: "Stocktake" }],
    })
    expect(feedKgAtHand).toBe(400)
  })
})

describe("isFeedItem", () => {
  it("accepts either half and nothing else", () => {
    expect(isFeedItem({ category: "FeedIngredient" })).toBe(true)
    expect(isFeedItem({ category: "FinishedFeed" })).toBe(true)
    expect(isFeedItem({ category: "Medication" })).toBe(false)
  })
})
