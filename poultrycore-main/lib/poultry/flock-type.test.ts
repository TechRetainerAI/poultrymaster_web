import { describe, expect, it } from "vitest"
import { defaultFlockType, flockTypeOf, isBroilerBreed, showBroilerFeatures, showEggFeatures } from "./flock-type"

describe("isBroilerBreed", () => {
  it("knows the catalog's broiler breeds, any casing", () => {
    expect(isBroilerBreed("Cobb 500")).toBe(true)
    expect(isBroilerBreed("ross 308")).toBe(true)
    expect(isBroilerBreed("  Arbor   Acres ")).toBe(true)
  })
  it("matches the same fragments as the database", () => {
    expect(isBroilerBreed("Broiller")).toBe(true)
    expect(isBroilerBreed("Hubbard Classic")).toBe(true)
  })
  it("leaves layers and dual-purpose breeds alone", () => {
    expect(isBroilerBreed("Isa Brown")).toBe(false)
    expect(isBroilerBreed("Sasso")).toBe(false)
    expect(isBroilerBreed("")).toBe(false)
    expect(isBroilerBreed(null)).toBe(false)
  })
})

describe("defaultFlockType", () => {
  it("breed first, then company, then Layer", () => {
    expect(defaultFlockType("Cobb 500", "Layers")).toBe("Broiler")
    expect(defaultFlockType("Local", "Broilers")).toBe("Broiler")
    expect(defaultFlockType("Local", "Both")).toBe("Layer")
    expect(defaultFlockType("Isa Brown", undefined)).toBe("Layer")
  })
})

describe("flockTypeOf", () => {
  it("treats a missing type as Layer", () => {
    expect(flockTypeOf({})).toBe("Layer")
    expect(flockTypeOf(null)).toBe("Layer")
    expect(flockTypeOf({ flockType: "Broiler" })).toBe("Broiler")
  })
})

describe("showEggFeatures", () => {
  const layer = { flockType: "Layer" }
  const broiler = { flockType: "Broiler" }
  const closedLayer = { flockType: "Layer", closedDate: "2026-01-01" }

  it("shows eggs while any open flock lays", () => {
    expect(showEggFeatures([layer, broiler], "Broilers")).toBe(true)
  })
  it("hides eggs when only broilers are running", () => {
    expect(showEggFeatures([broiler, closedLayer], "Both")).toBe(false)
    expect(showEggFeatures([broiler], undefined)).toBe(false)
  })
  it("falls back to the company type when no flock is open", () => {
    expect(showEggFeatures([closedLayer], "Broilers")).toBe(false)
    expect(showEggFeatures([], "Layers")).toBe(true)
    expect(showEggFeatures([], "Both")).toBe(true)
  })
  it("shows eggs when nothing is known", () => {
    expect(showEggFeatures(null, null)).toBe(true)
    expect(showEggFeatures([], undefined)).toBe(true)
  })
  it("ignores deleted flocks", () => {
    expect(showEggFeatures([{ ...layer, isDeleted: true }, broiler])).toBe(false)
  })
})

describe("showBroilerFeatures", () => {
  it("offers broiler screens once a broiler flock exists, closed or not", () => {
    expect(showBroilerFeatures([{ flockType: "Broiler", closedDate: "2026-01-01" }], "Layers")).toBe(true)
  })
  it("offers them to a company set to Broilers or Both", () => {
    expect(showBroilerFeatures([{ flockType: "Layer" }], "Both")).toBe(true)
    expect(showBroilerFeatures([], "Broilers")).toBe(true)
  })
  it("hides them on a layer-only farm", () => {
    expect(showBroilerFeatures([{ flockType: "Layer" }], "Layers")).toBe(false)
    expect(showBroilerFeatures([], null)).toBe(false)
  })
  it("ignores deleted broiler flocks, and shows them when nothing is known", () => {
    expect(showBroilerFeatures([{ flockType: "Broiler", isDeleted: true }], "Layers")).toBe(false)
    expect(showBroilerFeatures(null, null)).toBe(true)
  })
})

import { isBroilerBatch, shouldSwitchToChicken } from "./flock-type"

describe("broiler sales", () => {
  const flocks = [
    { batchId: 1, flockType: "Broiler" }, { batchId: 1, flockType: "Broiler" },
    { batchId: 2, flockType: "Broiler" }, { batchId: 2, flockType: "Layer" },
  ]
  it("a batch is broiler when all its flocks are", () => {
    expect(isBroilerBatch(1, flocks)).toBe(true)
    expect(isBroilerBatch(2, flocks)).toBe(false)
    expect(isBroilerBatch(0, flocks)).toBe(false)
  })
  it("an undivided batch goes by its breed", () => {
    expect(isBroilerBatch(9, flocks, "Cobb 500")).toBe(true)
    expect(isBroilerBatch(9, flocks, "Isa Brown")).toBe(false)
  })
  it("switches only away from eggs or blank", () => {
    expect(shouldSwitchToChicken("Fresh Eggs")).toBe(true)
    expect(shouldSwitchToChicken("")).toBe(true)
    expect(shouldSwitchToChicken("Broken Eggs")).toBe(false)
    expect(shouldSwitchToChicken("Manure")).toBe(false)
    expect(shouldSwitchToChicken("Chicken")).toBe(false)
  })
})
