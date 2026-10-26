import { describe, expect, it } from "vitest"
import { scaleFormulaLines } from "@/lib/feed-formula-scale"
import type { FeedFormulaLine } from "@/lib/api/poultry-feed-production"

// The default Layer formula (migration 385): fixed kg lines for 1,000 kg.
const fixed = (id: number, kg: number): FeedFormulaLine => ({
  poultryFeedFormulaLineId: id, poultryFeedFormulaId: 1, ingredientItemId: id,
  availableStock: 0, latestUnitCost: 0, quantityMode: "FixedQuantity",
  fixedQuantity: kg, unitOfMeasure: "kg", sortOrder: id,
})
const LAYER = [fixed(1, 50), fixed(2, 620), fixed(3, 190), fixed(4, 50), fixed(5, 90)]

describe("default 1-tonne formulas", () => {
  it("makes exactly the recipe at 1,000 kg", () => {
    expect([...scaleFormulaLines(LAYER, 1000).values()]).toEqual([50, 620, 190, 50, 90])
  })

  it("doubles every amount for 2 tonnes", () => {
    expect([...scaleFormulaLines(LAYER, 2000).values()]).toEqual([100, 1240, 380, 100, 180])
  })

  it("halves every amount for 500 kg and still totals the batch", () => {
    const half = [...scaleFormulaLines(LAYER, 500).values()]
    expect(half).toEqual([25, 310, 95, 25, 45])
    expect(half.reduce((s, n) => s + n, 0)).toBe(500)
  })
})
