import { describe, expect, it } from "vitest"
import {
  daysText,
  explainAverage,
  isActionable,
  purchaseUnitEquivalent,
  restockHref,
  sortBySeverity,
  stockoutText,
  supplyStatusStyle,
  type StockSupplyRow,
} from "./days-of-supply"

const row = (p: Partial<StockSupplyRow> = {}): StockSupplyRow => ({
  poultryRawMaterialItemId: 7, itemName: "Layer Mash", category: "FinishedFeed",
  unitOfMeasure: "kg", purchaseUnitOfMeasure: "Bag", unitsPerPurchaseUnit: 50,
  currentQuantity: 1800, minimumStockAlert: 2000, belowReorder: true,
  businessDate: "2026-09-30", windowFrom: "2026-09-23", windowTo: "2026-09-29",
  lookbackDays: 7, windowDays: 7, consumedQty: 4340, usageDays: 7,
  avgDailyUsage: 620, daysOfSupply: 2.9, estimatedStockout: "2026-10-02",
  status: "Critical", severityRank: 2, criticalDays: 3, warningDays: 7, expectedDailyUsage: null,
  ...p,
})

describe("daysText — never NaN or Infinity", () => {
  it("reads days remaining", () => {
    expect(daysText(row())).toBe("2.9 days remaining")
    expect(daysText(row({ daysOfSupply: 1, status: "Critical" }))).toBe("1 day remaining")
  })

  it("words the states that have no figure", () => {
    expect(daysText(row({ status: "NoRecentUsage", daysOfSupply: null }))).toBe("No recent usage")
    expect(daysText(row({ status: "InsufficientHistory", daysOfSupply: null }))).toBe("Not enough history yet")
    expect(daysText(row({ status: "Negative", daysOfSupply: null }))).toBe("Stock is below zero — correct the count")
    expect(daysText(row({ status: "OutOfStock", daysOfSupply: 0 }))).toBe("Out of stock")
  })

  it("survives a bad number without printing NaN / Infinity", () => {
    expect(daysText(row({ daysOfSupply: Number.POSITIVE_INFINITY }))).toBe("—")
    expect(daysText(row({ daysOfSupply: Number.NaN }))).toBe("—")
  })
})

describe("stockoutText", () => {
  it("is labelled an estimate, on the company's date", () => {
    expect(stockoutText(row())).toBe("Estimated stock-out: Oct 2")
  })

  it("has none without a figure, and never for negative stock", () => {
    expect(stockoutText(row({ estimatedStockout: null }))).toBeNull()
    expect(stockoutText(row({ status: "Negative", estimatedStockout: "2026-09-30" }))).toBeNull()
  })
})

describe("explainAverage", () => {
  it("says what was averaged and over when", () => {
    expect(explainAverage(row())).toBe("4,340 kg used over the last 7 days, Sep 23–Sep 29: about 620 kg a day.")
  })

  it("says so for a new product averaged over fewer days", () => {
    expect(explainAverage(row({ windowDays: 4, consumedQty: 400, avgDailyUsage: 100 })))
      .toContain("over 4 days (since it was first stocked)")
  })

  it("explains no usage and too little history", () => {
    expect(explainAverage(row({ consumedQty: 0, status: "NoRecentUsage" }))).toBe("Nothing used from Sep 23 to Sep 29.")
    expect(explainAverage(row({ status: "InsufficientHistory", windowDays: 1 }))).toContain("only 1 day")
  })
})

describe("units and actions", () => {
  it("shows the purchase-unit equivalent only when it differs", () => {
    expect(purchaseUnitEquivalent(1800, row())).toBe("≈ 36 Bag")
    expect(purchaseUnitEquivalent(1800, row({ unitsPerPurchaseUnit: 1 }))).toBeNull()
    expect(purchaseUnitEquivalent(1800, row({ purchaseUnitOfMeasure: "kg" }))).toBeNull()
  })

  it("links Restock to the purchase dialog with the item chosen", () => {
    expect(restockHref(7)).toBe("/poultry-supply-purchases?purchase=1&itemId=7")
  })

  it("knows which states ask for action", () => {
    expect(isActionable("Critical")).toBe(true)
    expect(isActionable("Negative")).toBe(true)
    expect(isActionable("Healthy")).toBe(false)
    expect(isActionable("NoRecentUsage")).toBe(false)
    expect(supplyStatusStyle("Warning").label).toBe("Warning")
  })

  it("sorts most urgent first, then fewest days", () => {
    const sorted = sortBySeverity([
      row({ itemName: "C", severityRank: 4, daysOfSupply: 20 }),
      row({ itemName: "B", severityRank: 2, daysOfSupply: 2.5 }),
      row({ itemName: "A", severityRank: 2, daysOfSupply: 1.2 }),
      row({ itemName: "D", severityRank: 6, daysOfSupply: null }),
    ])
    expect(sorted.map((r) => r.itemName)).toEqual(["A", "B", "C", "D"])
  })
})
