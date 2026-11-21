import { describe, it, expect } from "vitest"
import { BREEDS, ageText, ageToDays, breedsFor, daysToAge, parseAgeText } from "./breeds"

describe("livestock breeds", () => {
  it("has breeds for every kind of animal seeded in migration 458", () => {
    for (const code of ["duck", "guinea_fowl", "turkey", "quail", "goose", "rabbit", "grasscutter", "goat", "sheep", "pig", "cattle"]) {
      expect(BREEDS[code]?.length, code).toBeGreaterThan(0)
    }
  })
  it("always offers local, cross and not sure, without duplicates", () => {
    for (const code of Object.keys(BREEDS)) {
      const list = breedsFor(code)
      expect(list).toContain("Local / indigenous")
      expect(new Set(list).size, code).toBe(list.length)
    }
    expect(breedsFor(null)).toEqual(["Local / indigenous", "Cross / mixed", "Not sure"])
  })
})

describe("livestock age", () => {
  it("converts to days", () => {
    expect(ageToDays(8, "weeks")).toBe(56)
    expect(ageToDays(2, "years")).toBe(730)
    expect(ageToDays(3, "months")).toBe(90)
    expect(ageToDays(1.5, "weeks")).toBe(11)
  })
  it("shows days in the largest even unit", () => {
    expect(daysToAge(56)).toEqual({ n: 8, unit: "weeks" })
    expect(daysToAge(365)).toEqual({ n: 1, unit: "years" })
    expect(daysToAge(60)).toEqual({ n: 2, unit: "months" })
    expect(daysToAge(10)).toEqual({ n: 10, unit: "days" })
    expect(daysToAge(0)).toEqual({ n: 0, unit: "days" })
  })
  it("writes and reads back age text", () => {
    expect(ageText(1, "years")).toBe("1 year")
    expect(ageText(8, "weeks")).toBe("8 weeks")
    expect(parseAgeText("8 weeks")).toEqual({ n: 8, unit: "weeks" })
    expect(parseAgeText("1 yr")).toEqual({ n: 1, unit: "years" })
    expect(parseAgeText("3 months")).toEqual({ n: 3, unit: "months" })
    expect(parseAgeText("Point of lay")).toBeNull()
  })
})
