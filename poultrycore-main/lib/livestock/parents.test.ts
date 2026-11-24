import { describe, expect, it } from "vitest"
import { fitsRole, parentProblem, parentRank } from "./parents"

describe("fitsRole", () => {
  it("lets females and unknown-sex animals be mothers, only males be fathers", () => {
    expect(fitsRole({ sex: "Female" }, "mother")).toBe(true)
    expect(fitsRole({ sex: "Unknown" }, "mother")).toBe(true)
    expect(fitsRole({ sex: "Male" }, "mother")).toBe(false)
    expect(fitsRole({ sex: "Male" }, "father")).toBe(true)
    expect(fitsRole({ sex: "Unknown" }, "father")).toBe(false)
    expect(fitsRole({ sex: "Female" }, "father")).toBe(false)
  })
})

describe("parentProblem", () => {
  const ewe = { sex: "Female" as const, birthDate: "2024-01-01" }
  it("is fine when either birth date is missing", () => {
    expect(parentProblem({ ...ewe, birthDate: null }, "mother", "2025-01-01", 150)).toBeNull()
    expect(parentProblem(ewe, "mother", null, 150)).toBeNull()
  })
  it("refuses a parent born on or after the young one", () => {
    expect(parentProblem(ewe, "mother", "2024-01-01", null)).toMatch(/same birth date/)
    expect(parentProblem(ewe, "mother", "2023-06-01", null)).toMatch(/born after/)
  })
  it("refuses a parent younger than one pregnancy at the birth", () => {
    expect(parentProblem(ewe, "mother", "2024-03-01", 150)).toMatch(/too young/)
    expect(parentProblem(ewe, "mother", "2024-06-01", 150)).toBeNull()
  })
  it("refuses the wrong sex", () => {
    expect(parentProblem({ sex: "Male", birthDate: null }, "mother", null, null)).toMatch(/male/)
    expect(parentProblem({ sex: "Unknown", birthDate: null }, "father", null, null)).toMatch(/male/)
  })
})

describe("parentRank", () => {
  it("puts the same group first, then other live animals, then gone ones", () => {
    expect(parentRank({ status: "Active", groupId: 5 }, 5)).toBe(0)
    expect(parentRank({ status: "Active", groupId: 6 }, 5)).toBe(1)
    expect(parentRank({ status: "Dead", groupId: 5 }, 5)).toBe(2)
  })
})
