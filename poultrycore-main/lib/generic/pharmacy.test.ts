import { describe, expect, it } from "vitest"
import { describeQty, expiryState, packProblems, sellBlockReason, sellUnits, sellableStock } from "./pharmacy"

const amox = {
  baseUnit: "tablet",
  sellingPrice: 1,
  packs: [
    { packName: "Box", unitsPerPack: 100, sellingPrice: 70 },
    { packName: "Strip", unitsPerPack: 10, sellingPrice: 8 },
  ],
}

describe("sellUnits", () => {
  it("lists the base unit first, then packs smallest first, each with its own price", () => {
    expect(sellUnits(amox)).toEqual([
      { unit: "tablet", factor: 1, price: 1 },
      { unit: "Strip", factor: 10, price: 8 },
      { unit: "Box", factor: 100, price: 70 },
    ])
  })
  it("skips a pack without a size and a pack named like the base unit", () => {
    const u = sellUnits({ baseUnit: "tablet", sellingPrice: 1, packs: [
      { packName: "Tablet", unitsPerPack: 1, sellingPrice: 1 },
      { packName: "Card", unitsPerPack: 0, sellingPrice: 5 },
    ] })
    expect(u.map((x) => x.unit)).toEqual(["tablet"])
  })
})

describe("sellBlockReason", () => {
  it("lets a pharmacy sell every class", () => {
    expect(sellBlockReason("Pharmacy", "A")).toBeNull()
    expect(sellBlockReason("Pharmacy", "B")).toBeNull()
    expect(sellBlockReason("Pharmacy", "C")).toBeNull()
  })
  it("lets a chemical shop sell Class C only", () => {
    expect(sellBlockReason("ChemicalShop", "C")).toBeNull()
    expect(sellBlockReason("ChemicalShop", "A")).toMatch(/Class A/)
    expect(sellBlockReason("ChemicalShop", "B")).toMatch(/Class B/)
  })
})

describe("sellableStock", () => {
  it("leaves out stock in expired batches", () => {
    expect(sellableStock({ currentStock: 300, expiredQty: 50 })).toBe(250)
    expect(sellableStock({ currentStock: 10, expiredQty: 50 })).toBe(0)
  })
})

describe("packProblems", () => {
  it("accepts a good list", () => {
    expect(packProblems("tablet", amox.packs)).toEqual([])
  })
  it("names each problem", () => {
    const p = packProblems("tablet", [
      { packName: "tablet", unitsPerPack: 1, sellingPrice: 1 },
      { packName: "Strip", unitsPerPack: 10, sellingPrice: 8 },
      { packName: "strip", unitsPerPack: 0, sellingPrice: -1 },
    ])
    expect(p.join(" | ")).toMatch(/base unit/)
    expect(p.join(" | ")).toMatch(/twice/)
    expect(p.join(" | ")).toMatch(/how many tablet/)
    expect(p.join(" | ")).toMatch(/below zero/)
  })
})

describe("expiryState", () => {
  const today = new Date(2026, 10, 27)
  it("classifies dates against the warning window", () => {
    expect(expiryState("2026-11-26", 90, today)).toBe("expired")
    expect(expiryState("2026-11-27", 90, today)).toBe("soon")
    expect(expiryState("2027-02-25", 90, today)).toBe("soon")
    expect(expiryState("2027-03-01", 90, today)).toBe("ok")
    expect(expiryState(null, 90, today)).toBe("none")
  })
})

describe("describeQty", () => {
  it("breaks base units into packs", () => {
    expect(describeQty(234, sellUnits(amox))).toBe("2 Box + 3 Strip + 4 tablet")
    expect(describeQty(7, sellUnits(amox))).toBe("7 tablet")
    expect(describeQty(0, sellUnits(amox))).toBe("0 tablet")
  })
})
