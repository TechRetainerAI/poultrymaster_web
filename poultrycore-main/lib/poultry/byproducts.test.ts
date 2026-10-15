import { describe, expect, it } from "vitest"
import { byproductRole } from "./byproducts"
import { isEggSaleProduct } from "@/lib/utils/egg-ledger"
import { isBirdSaleProduct } from "@/lib/utils/birds-left-ledger"
import { extraLineIsEggs } from "@/components/sales/egg-class-fields"
import { isEggProduct, saleProductOptions } from "@/components/sales/sale-item-row"

describe("byproduct sales (374)", () => {
  it("finds the two byproducts by name, nothing else", () => {
    expect(byproductRole("Broken Eggs")).toBe("BrokenEggs")
    expect(byproductRole(" dead birds ")).toBe("DeadBirds")
    expect(byproductRole("Dead Birds (system)")).toBe("DeadBirds")
    expect(byproductRole("Fresh Eggs")).toBeNull()
    expect(byproductRole("Birds")).toBeNull()
  })

  it("a Broken Eggs sale is not an egg sale", () => {
    expect(isEggProduct("Broken Eggs")).toBe(false)
    expect(isEggSaleProduct("Broken Eggs")).toBe(false)
    expect(extraLineIsEggs({ key: "a", product: "Broken Eggs", eggProductId: null, crates: 0, loose: 0, unitPrice: 1 })).toBe(false)
    expect(isEggProduct("Fresh Eggs")).toBe(true)
    expect(isEggSaleProduct("Fresh Eggs")).toBe(true)
  })

  it("a Dead Birds sale does not take live birds", () => {
    expect(isBirdSaleProduct("Dead Birds")).toBe(false)
    expect(isBirdSaleProduct("Chicken")).toBe(true)
  })

  it("offers Broken Eggs by default and Dead Birds only when turned on", () => {
    expect(saleProductOptions(null)).toEqual(["Fresh Eggs", "Chicken", "Broken Eggs", "Manure", "Other"])
    expect(saleProductOptions({ brokenEggsInSales: false, deadBirdsInSales: true }))
      .toEqual(["Fresh Eggs", "Chicken", "Dead Birds", "Manure", "Other"])
  })
})
