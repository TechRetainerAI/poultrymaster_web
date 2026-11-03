import { describe, expect, it } from "vitest"
import {
  avgKgPerBird, birdLineAmount, birdPricingFromLine, birdPricingPayload, birdPricingProblem,
  isLiveBirdProduct, perBirdPrice,
} from "./bird-pricing"

const perKg = (kg: number | null, ppk: number | null) => ({ basis: "PerKg" as const, liveWeightKg: kg, pricePerKg: ppk })
const perBird = (kg: number | null = null) => ({ basis: "PerBird" as const, liveWeightKg: kg, pricePerKg: null })

describe("isLiveBirdProduct (mirrors fnpoultrysale_isbirdsale)", () => {
  it("knows live birds", () => {
    for (const p of ["Birds", "Chicken", "Live broilers", "Broilers", "Cockerels"]) expect(isLiveBirdProduct(p), p).toBe(true)
  })
  it("is not fooled by feed, eggs or byproducts", () => {
    for (const p of ["Broiler feed", "Broiler starter mash", "Fresh Eggs", "Dead Birds", "Manure", ""]) expect(isLiveBirdProduct(p), p).toBe(false)
  })
})

// Same figures as database/checks/bird-sales-per-kg.test.sql.
describe("amounts", () => {
  it("per kg: kg x price; per-bird price = amount / birds", () => {
    const amt = birdLineAmount(100, 1, perKg(250, 30))
    expect(amt).toBe(7500)
    expect(perBirdPrice(amt, 100)).toBe(75)
  })
  it("per bird: birds x unit price, weight only recorded", () => {
    expect(birdLineAmount(20, 80, perBird(48.5))).toBe(1600)
  })
  it("rounds the way the database does", () => {
    expect(perBirdPrice(1110, 14)).toBe(79.29)
  })
  it("average weight", () => {
    expect(avgKgPerBird(100, 250)).toBe(2.5)
    expect(avgKgPerBird(0, 250)).toBeNull()
    expect(avgKgPerBird(10, null)).toBeNull()
  })
})

describe("birdPricingProblem", () => {
  it("accepts a complete per-kg line and a plain per-bird line", () => {
    expect(birdPricingProblem(100, perKg(250, 30))).toBeNull()
    expect(birdPricingProblem(100, perBird())).toBeNull()
  })
  it("refuses what the database refuses", () => {
    expect(birdPricingProblem(10, perKg(null, 30))).toMatch(/live weight/)
    expect(birdPricingProblem(10, perKg(25, null))).toMatch(/price per kg/)
    expect(birdPricingProblem(10.5, perKg(25, 30))).toMatch(/whole number/)
    expect(birdPricingProblem(2, perKg(50, 30))).toMatch(/over 20 kg/)
  })
})

describe("payload", () => {
  it("sends nothing for a plain per-bird line", () => {
    expect(birdPricingPayload(perBird())).toEqual({})
  })
  it("sends the weight on a per-bird line, and the price per kg only per kg", () => {
    expect(birdPricingPayload(perBird(48.5))).toEqual({ pricingBasis: "PerBird", liveWeightKg: 48.5, pricePerKg: null })
    expect(birdPricingPayload(perKg(250, 30), true)).toEqual({ pricingBasis: "PerKg", liveWeightKg: 250, pricePerKg: 30, amountOverridden: true })
  })
  it("round-trips a saved line", () => {
    expect(birdPricingFromLine({ pricingBasis: "PerKg", liveWeightKg: 250, pricePerKg: 30 })).toEqual(perKg(250, 30))
    expect(birdPricingFromLine({})).toEqual(perBird())
  })
})

describe("one bird-sale rule (403)", () => {
  it("the Birds tracker uses the database's rule", async () => {
    const { isBirdSaleProduct } = await import("@/lib/utils/birds-left-ledger")
    for (const p of ["Birds", "Chicken", "Live broilers", "Broiler feed", "Layer mash", "Poultry manure", "Dead Birds", "Fresh Eggs"]) {
      expect(isBirdSaleProduct(p), p).toBe(isLiveBirdProduct(p))
    }
    expect(isBirdSaleProduct("Poultry manure")).toBe(false)
    expect(isBirdSaleProduct("Layer mash")).toBe(false)
  })
})
