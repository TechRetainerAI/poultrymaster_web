import { describe, expect, it } from "vitest"
import {
  BREED_CATALOG, FARM_BREEDS_GROUP, breedKey, breedOptions,
  groupedBreedOptions, isKnownBreed,
} from "./breeds"

describe("breedKey", () => {
  it("makes one breed of the spellings that differ only in case and spacing", () => {
    expect(breedKey("Isa Brown")).toBe(breedKey("ISA   brown"))
    expect(breedKey("  Cobb 500 ")).toBe("cobb 500")
  })

  it("is empty for nothing", () => {
    expect(breedKey("")).toBe("")
    expect(breedKey(null)).toBe("")
    expect(breedKey(undefined)).toBe("")
  })
})

describe("breedOptions", () => {
  it("puts what the farm already uses first", () => {
    const options = breedOptions(["Kuroiler", "Cobb 500"])
    expect(options.slice(0, 2).map((o) => o.value)).toEqual(["Cobb 500", "Kuroiler"])
    expect(options.slice(0, 2).every((o) => o.group === FARM_BREEDS_GROUP)).toBe(true)
  })

  it("KEEPS a stored breed the list has never heard of", () => {
    // The rule that stops opening an old record from clearing its breed.
    const options = breedOptions([], "Some Local Cross")
    expect(options[0]).toEqual({
      value: "Some Local Cross", label: "Some Local Cross", group: FARM_BREEDS_GROUP,
    })
  })

  it("does not list the same breed twice, whatever its spelling", () => {
    const options = breedOptions(["isa brown", "ISA BROWN"], "Isa Brown")
    expect(options.filter((o) => breedKey(o.value) === "isa brown")).toHaveLength(1)
  })

  it("keeps the farm's spelling rather than the catalog's", () => {
    // What the farm typed is what its existing records say.
    const options = breedOptions(["ISA BROWN"])
    expect(options.find((o) => breedKey(o.value) === "isa brown")?.value).toBe("ISA BROWN")
  })

  it("offers the catalog to a farm with no history at all", () => {
    const options = breedOptions()
    expect(options.length).toBe(BREED_CATALOG.reduce((n, g) => n + g.breeds.length, 0))
    expect(options.some((o) => o.value === "Cobb 500")).toBe(true)
  })

  it("ignores blanks", () => {
    expect(breedOptions(["", "   "], "").every((o) => o.value.trim().length > 0)).toBe(true)
  })
})

describe("groupedBreedOptions", () => {
  it("leads with the farm's own breeds, then the catalog in order", () => {
    const groups = groupedBreedOptions(["Kuroiler"])
    expect(groups[0].group).toBe(FARM_BREEDS_GROUP)
    expect(groups.slice(1).map((g) => g.group)).toEqual(BREED_CATALOG.map((c) => c.group))
  })

  it("omits the farm group entirely when there is nothing in it", () => {
    expect(groupedBreedOptions().map((g) => g.group)).toEqual(BREED_CATALOG.map((c) => c.group))
  })

  it("does not repeat a farm breed under its catalog group", () => {
    const groups = groupedBreedOptions(["Cobb 500"])
    const broilers = groups.find((g) => g.group === "Broilers")!
    expect(broilers.options.some((o) => o.value === "Cobb 500")).toBe(false)
  })
})

describe("isKnownBreed", () => {
  it("recognises a catalog breed however it is spelled", () => {
    expect(isKnownBreed("cobb 500")).toBe(true)
  })

  it("recognises one the farm has used", () => {
    expect(isKnownBreed("Noiler X", ["Noiler X"])).toBe(true)
  })

  it("says no to something new, which is what the Other option is for", () => {
    expect(isKnownBreed("Brand New Cross")).toBe(false)
    expect(isKnownBreed("")).toBe(false)
  })
})

describe("white layers", () => {
  const WHITES = [
    "ISA White", "Dekalb White", "Bovans White", "Shaver White", "Babcock White",
    "Hy-Line W-36", "Hy-Line W-80", "Lohmann LSL-Lite", "White Leghorn",
    "H&N Nick Chick", "Novogen White (Novowhite)", "White Layer — Unknown Strain",
  ]

  it("A: offers every white strain to a company with no history", () => {
    const values = breedOptions().map((o) => o.value)
    for (const w of WHITES) expect(values).toContain(w)
    expect(groupedBreedOptions().find((g) => g.group === "White layers")!.options).toHaveLength(WHITES.length)
  })

  it("keeps ISA White distinct from Isa Brown, and the unknown strain distinct from all", () => {
    expect(breedKey("ISA White")).not.toBe(breedKey("Isa Brown"))
    const keys = BREED_CATALOG.flatMap((g) => g.breeds).map(breedKey)
    expect(new Set(keys).size).toBe(keys.length)
  })

  it("restores a saved ISA White when the flock is reopened, without a duplicate", () => {
    const options = breedOptions(["ISA White"], "ISA White")
    expect(options[0]).toEqual({ value: "ISA White", label: "ISA White", group: FARM_BREEDS_GROUP })
    expect(options.filter((o) => breedKey(o.value) === "isa white")).toHaveLength(1)
  })

  it("still lists the browns exactly as before", () => {
    const layers = BREED_CATALOG.find((g) => g.group === "Layers")!.breeds
    expect(layers).toEqual(["Isa Brown", "Lohmann Brown", "Bovan Brown", "Hy-Line Brown", "Shaver Brown", "Dekalb Brown", "Nera Black"])
  })
})
