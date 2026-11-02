import { describe, expect, it } from "vitest"
import {
  DEFAULT_EGG_PACKAGING, eggQuantityHint, eggsPerBox, formatEggQuantity, formatPackaged, normalizePackaged, packagedLineAmount,
  packagedQuantityError, packagingConfigError, packagingKey, postedLineConversion, postedLineQuantity, toBoxesCratesPieces, toCratesPieces, toEggPieces,
  type EggPackaging,
} from "./egg-packaging"

const boxes = (cratesPerBox: number, eggsPerCrate = 30): EggPackaging => ({
  ...DEFAULT_EGG_PACKAGING, eggsPerCrate, enableBoxes: true, cratesPerBox, display: "BoxesCratesPieces",
})
const crateOnly = DEFAULT_EGG_PACKAGING

describe("egg packaging conversion (spec tests 1-8)", () => {
  it("1: 14 crates per box of 30 = 420 eggs", () => {
    expect(eggsPerBox(boxes(14))).toBe(420)
  })
  it("2: 10 crates per box = 300 eggs", () => {
    expect(eggsPerBox(boxes(10))).toBe(300)
  })
  it("3: 2 boxes + 3 crates + 10 pieces = 940 eggs", () => {
    expect(toEggPieces({ boxes: 2, crates: 3, pieces: 10 }, boxes(14))).toBe(940)
  })
  it("4: 10,675 eggs = 25 boxes + 5 crates + 25 pieces", () => {
    expect(toBoxesCratesPieces(10675, boxes(14))).toEqual({ boxes: 25, crates: 5, pieces: 25 })
  })
  it("5: 840 eggs = exactly 2 boxes", () => {
    expect(toBoxesCratesPieces(840, boxes(14))).toEqual({ boxes: 2, crates: 0, pieces: 0 })
  })
  it("6: 95 eggs = 0 boxes + 3 crates + 5 pieces", () => {
    expect(toBoxesCratesPieces(95, boxes(14))).toEqual({ boxes: 0, crates: 3, pieces: 5 })
  })
  it("7: zero eggs is all zeros", () => {
    expect(toBoxesCratesPieces(0, boxes(14))).toEqual({ boxes: 0, crates: 0, pieces: 0 })
  })
  it("8: crates per box of 0 is refused, and never divides by zero", () => {
    expect(packagingConfigError({ enableBoxes: true, cratesPerBox: 0, display: "BoxesCratesPieces", saleEntryUnit: "Boxes" }))
      .toMatch(/1 to 200/)
    const zero = { ...boxes(14), cratesPerBox: 0 }
    expect(eggsPerBox(zero)).toBeNull()
    expect(toBoxesCratesPieces(1000, zero)).toEqual({ boxes: 0, crates: 33, pieces: 10 })
  })
})

describe("configuration rules", () => {
  it("boxes on needs a box size", () => {
    expect(packagingConfigError({ enableBoxes: true, cratesPerBox: null, display: "CratesPieces", saleEntryUnit: "Crates" }))
      .toMatch(/crates are in one box/)
  })
  it("decimal and negative box sizes are refused", () => {
    const base = { enableBoxes: true, display: "CratesPieces" as const, saleEntryUnit: "Crates" as const }
    expect(packagingConfigError({ ...base, cratesPerBox: 2.5 })).not.toBeNull()
    expect(packagingConfigError({ ...base, cratesPerBox: -3 })).not.toBeNull()
    expect(packagingConfigError({ ...base, cratesPerBox: 201 })).not.toBeNull()
    expect(packagingConfigError({ ...base, cratesPerBox: 14 })).toBeNull()
  })
  it("box display and box-first entry need boxes on", () => {
    expect(packagingConfigError({ enableBoxes: false, cratesPerBox: 14, display: "BoxesCratesPieces", saleEntryUnit: "Crates" })).not.toBeNull()
    expect(packagingConfigError({ enableBoxes: false, cratesPerBox: 14, display: "CratesPieces", saleEntryUnit: "Boxes" })).not.toBeNull()
  })
})

describe("entry", () => {
  it("normalises an over-full entry without changing the egg count", () => {
    const n = normalizePackaged({ boxes: 1, crates: 16, pieces: 35 }, boxes(14))
    expect(n).toEqual({ boxes: 2, crates: 3, pieces: 5 })
    expect(toEggPieces(n, boxes(14))).toBe(toEggPieces({ boxes: 1, crates: 16, pieces: 35 }, boxes(14)))
  })
  it("refuses negatives, decimals, and boxes on a crate-only farm", () => {
    expect(packagedQuantityError({ crates: -1 }, boxes(14))).toMatch(/negative/)
    expect(packagedQuantityError({ pieces: 2.5 }, boxes(14))).toMatch(/whole/)
    expect(packagedQuantityError({ boxes: 1 }, crateOnly)).toMatch(/not set up/)
    expect(packagedQuantityError({ boxes: 2, crates: 3, pieces: 10 }, boxes(14))).toBeNull()
  })
  it("a crate-only farm converts exactly as before", () => {
    expect(toEggPieces({ crates: 3, pieces: 10 }, crateOnly)).toBe(100)
    expect(toCratesPieces(10675, crateOnly)).toEqual({ crates: 355, pieces: 25 })
  })
  it("follows a non-30 crate size", () => {
    expect(eggsPerBox(boxes(10, 24))).toBe(240)
    expect(toBoxesCratesPieces(500, boxes(10, 24))).toEqual({ boxes: 2, crates: 0, pieces: 20 })
  })
  it("keeps the sign on a decrease", () => {
    expect(toBoxesCratesPieces(-485, boxes(14))).toEqual({ boxes: -1, crates: -2, pieces: -5 })
  })
})

describe("display", () => {
  it("writes each preference", () => {
    expect(formatEggQuantity(10675, boxes(14))).toBe("25 boxes + 5 crates + 25 pcs")
    expect(formatEggQuantity(10675, boxes(14), "CratesPieces")).toBe("355 crates + 25 pcs")
    expect(formatEggQuantity(10675, boxes(14), "Pieces")).toBe("10,675 eggs")
  })
  it("box display on a crate-only farm falls back to crates", () => {
    expect(formatEggQuantity(10675, crateOnly, "BoxesCratesPieces")).toBe("355 crates + 25 pcs")
  })
  it("small and empty quantities are written in eggs", () => {
    expect(formatEggQuantity(25, boxes(14))).toBe("25 eggs")
    expect(formatEggQuantity(0, boxes(14))).toBe("0 eggs")
    expect(formatEggQuantity(1, boxes(14))).toBe("1 egg")
    expect(formatEggQuantity(420, boxes(14))).toBe("1 box")
  })
  it("formats an entry as entered", () => {
    expect(formatPackaged({ boxes: 2, crates: 3, pieces: 10 })).toBe("2 boxes + 3 crates + 10 pcs")
    expect(formatPackaged({ crates: 1 })).toBe("1 crate")
    expect(formatPackaged({})).toBe("0 eggs")
  })
  it("hints the other way round", () => {
    expect(eggQuantityHint(10675, boxes(14))).toBe("10,675 eggs")
    expect(eggQuantityHint(10675, { ...boxes(14), display: "Pieces" })).toBe("25 boxes + 5 crates + 25 pcs")
    expect(eggQuantityHint(20, boxes(14))).toBeNull()
  })
  it("cache key carries company and version", () => {
    expect(packagingKey("A", boxes(14))).not.toBe(packagingKey("B", boxes(14)))
    expect(packagingKey("A", boxes(14))).not.toBe(packagingKey("A", { ...boxes(10), version: 2 }))
  })
})

describe("pricing (spec tests 12-13)", () => {
  it("12: 2 boxes at 2,000 = 4,000", () => {
    expect(packagedLineAmount({ boxes: 2 }, { pricePerCrate: 150, pricePerBox: 2000 }, boxes(14))).toBe(4000)
  })
  it("13: 2 boxes at 2,000 + 3 crates at 150 + 10 pcs at 5 = 4,500 (no double charge)", () => {
    expect(packagedLineAmount({ boxes: 2, crates: 3, pieces: 10 }, { pricePerCrate: 150, pricePerBox: 2000, pricePerPiece: 5 }, boxes(14))).toBe(4500)
  })
  it("no box price: a box is crates per box x the crate price", () => {
    expect(packagedLineAmount({ boxes: 1, crates: 2, pieces: 15 }, { pricePerCrate: 150, pricePerPiece: 5 }, boxes(14))).toBe(2475)
  })
  it("no box or piece price: the same as the old pro-rata rule", () => {
    for (const [eggs, price] of [[223, 137.5], [940, 150], [95, 33.33], [1, 150], [10675, 149.99]] as const) {
      const q = toBoxesCratesPieces(eggs, boxes(14))
      const old = Math.round(((eggs / 30) * price) * 100) / 100
      expect(Math.abs(packagedLineAmount(q, { pricePerCrate: price }, boxes(14)) - old)).toBeLessThanOrEqual(0.01)
    }
  })
  it("matches the database rounding on a repeating price", () => {
    // fnpoultry_eggpackagedamount(0, 7, 13, 30, NULL, NULL, 137.50, NULL) = round(223 / 30 * 137.50, 2) = 1022.08
    expect(packagedLineAmount({ crates: 7, pieces: 13 }, { pricePerCrate: 137.5 }, crateOnly)).toBe(1022.08)
  })
})

describe("posted sale lines", () => {
  it("shows a 394 line as entered, with its own conversion, even after the box size changed", () => {
    const line = { quantity: 840, boxes: 2, crates: 0, pieces: 0, eggsPerCrate: 30, cratesPerBox: 14 }
    const today = boxes(10)
    expect(postedLineQuantity(line, today)).toEqual({ text: "2 boxes", eggs: 840, asEntered: true })
    expect(postedLineConversion(line)).toBe("1 box = 14 crates × 30 = 420 eggs")
  })
  it("an older line is a derived equivalent, not boxes sold (spec 31)", () => {
    const r = postedLineQuantity({ quantity: 420 }, boxes(14))
    expect(r.asEntered).toBe(false)
    expect(r.text).toBe("1 box")
  })
  it("14 crates sold as crates stay 14 crates, not 1 box", () => {
    const r = postedLineQuantity({ quantity: 420, boxes: 0, crates: 14, pieces: 0, eggsPerCrate: 30, cratesPerBox: 14 }, boxes(14))
    expect(r).toEqual({ text: "14 crates", eggs: 420, asEntered: true })
  })
})
