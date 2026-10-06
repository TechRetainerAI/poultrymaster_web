import { describe, expect, it } from "vitest"
import { PRODUCTION_EGG_GRADE, eggGradeToApi, productionEggGrade } from "./egg-grade"

describe("production egg grade", () => {
  it("is Mixed for a new record or one saved without a grade", () => {
    expect(productionEggGrade(undefined)).toBe(PRODUCTION_EGG_GRADE)
    expect(productionEggGrade(null)).toBe("Mixed")
    expect(productionEggGrade("")).toBe("Mixed")
    expect(eggGradeToApi(productionEggGrade(null))).toBe("Mixed")
  })

  it("keeps the grade an older record was saved with", () => {
    expect(productionEggGrade("Large")).toBe("Large")
    expect(productionEggGrade("P3")).toBe("Large")   // legacy code
  })

  it("treats an unknown stored value as Mixed", () => {
    expect(productionEggGrade("Serum")).toBe("Mixed")
  })
})
