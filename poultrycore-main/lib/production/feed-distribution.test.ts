import { describe, expect, it } from "vitest"
import {
  distributionTotals,
  manualFeedWarning,
  parseKg,
  postBlocker,
  rowState,
  suggestedKgByRate,
  suggestionFor,
  fromGramsPerBird,
  isRateUnit,
  rateUnitLabel,
  toGramsPerBird,
  type DistributionCandidate,
} from "./feed-distribution"

const cand = (p: Partial<DistributionCandidate> = {}): DistributionCandidate => ({
  flockId: 1, flockName: "B2 - Pen 7", batchName: "B2", houseName: "Pen 7",
  recordCount: 1, productionRecordId: 10, birds: 1840,
  manualFeedKg: null, stockFeedKg: 0, thisItemKg: 0, recentAvgKg: 180.5, recentAvgDays: 5,
  ...p,
})

describe("suggestedKgByRate", () => {
  it("converts grams per bird per day to kg", () => {
    expect(suggestedKgByRate(1840, 112.5)).toBe(207)
    expect(suggestedKgByRate(1000, 110)).toBe(110)
    expect(suggestedKgByRate(3, 0.5)).toBe(0.002) // to the gram
  })

  it("gives nothing without a rate or birds — never a default", () => {
    expect(suggestedKgByRate(1840, null)).toBeNull()
    expect(suggestedKgByRate(1840, 0)).toBeNull()
    expect(suggestedKgByRate(null, 112.5)).toBeNull()
  })
})

describe("suggestionFor", () => {
  it("uses the rate or, only when chosen, the recent average", () => {
    expect(suggestionFor(cand(), "Rate", 112.5)).toBe(207)
    expect(suggestionFor(cand(), "RecentAverage", 112.5)).toBe(180.5)
  })

  it("does not substitute one basis for the other", () => {
    expect(suggestionFor(cand({ recentAvgKg: null }), "RecentAverage", 112.5)).toBeNull()
    expect(suggestionFor(cand(), "Rate", null)).toBeNull()
  })
})

describe("rowState", () => {
  it("needs exactly one production record", () => {
    expect(rowState({ recordCount: 1 })).toBe("ok")
    expect(rowState({ recordCount: 0 })).toBe("noRecord")
    expect(rowState({ recordCount: 2 })).toBe("duplicate")
  })
})

describe("parseKg", () => {
  it("reads typed kg, rejecting junk and negatives", () => {
    expect(parseKg(" 207.5 ")).toBe(207.5)
    expect(parseKg("")).toBeNull()
    expect(parseKg("abc")).toBeNull()
    expect(parseKg("-3")).toBeNull()
  })
})

describe("distributionTotals / postBlocker", () => {
  it("adds only flocks that can receive feed, with manual overrides", () => {
    const t = distributionTotals(500, [
      { suggested: 207, actualText: "210", state: "ok" },      // manual override of the suggestion
      { suggested: 100, actualText: "100", state: "ok" },
      { suggested: 50, actualText: "50", state: "noRecord" }, // locked: not counted
    ])
    expect(t).toEqual({ available: 500, suggested: 307, actual: 310, remaining: 190 })
    expect(postBlocker(t, [{ actualText: "210", state: "ok" }])).toBeNull()
  })

  it("refuses more than is in stock", () => {
    const t = distributionTotals(100, [{ suggested: null, actualText: "150", state: "ok" }])
    expect(t.remaining).toBe(-50)
    expect(postBlocker(t, [{ actualText: "150", state: "ok" }])).toContain("50 kg more than is in stock")
  })

  it("refuses nothing entered, and invalid amounts", () => {
    const empty = distributionTotals(100, [{ suggested: 10, actualText: "", state: "ok" }])
    expect(postBlocker(empty, [{ actualText: "", state: "ok" }])).toBe("Enter feed for at least one flock.")
    const bad = distributionTotals(100, [{ suggested: 10, actualText: "abc", state: "ok" }])
    expect(postBlocker(bad, [{ actualText: "abc", state: "ok" }])).toContain("not valid numbers")
  })
})

describe("manualFeedWarning", () => {
  it("says when a typed kg will be replaced by stock lines", () => {
    expect(manualFeedWarning({ manualFeedKg: 50 }, 40)).toContain("replaces it with 40 kg")
    expect(manualFeedWarning({ manualFeedKg: null }, 40)).toBeNull()
    expect(manualFeedWarning({ manualFeedKg: 50 }, null)).toBeNull()
  })
})

describe("feed rate units", () => {
  it("converts each unit to grams per bird per day", () => {
    expect(toGramsPerBird(112.5, "g_bird")).toBe(112.5)
    expect(toGramsPerBird(0.1125, "kg_bird")).toBe(112.5)
    expect(toGramsPerBird(11.25, "kg_100")).toBe(112.5)
    expect(toGramsPerBird(112.5, "kg_1000")).toBe(112.5)
    expect(toGramsPerBird(1, "lb_bird")).toBe(453.59237)
    expect(toGramsPerBird(10, "lb_100")).toBe(45.359237)
  })

  it("gives the same suggestion whichever unit the same rate is typed in", () => {
    const viaGrams = suggestedKgByRate(1840, toGramsPerBird(112.5, "g_bird"))
    const viaKg100 = suggestedKgByRate(1840, toGramsPerBird(11.25, "kg_100"))
    const viaKgBird = suggestedKgByRate(1840, toGramsPerBird(0.1125, "kg_bird"))
    expect(viaGrams).toBe(207)
    expect(viaKg100).toBe(207)
    expect(viaKgBird).toBe(207)
  })

  it("reads a saved rate back in the unit it was typed in", () => {
    expect(fromGramsPerBird(112.5, "kg_100")).toBe(11.25)
    expect(fromGramsPerBird(453.59237, "lb_bird")).toBe(1)
    expect(fromGramsPerBird(null, "g_bird")).toBeNull()
  })

  it("rejects nothing-rates and knows its units", () => {
    expect(toGramsPerBird(0, "g_bird")).toBeNull()
    expect(toGramsPerBird(null, "g_bird")).toBeNull()
    expect(isRateUnit("kg_100")).toBe(true)
    expect(isRateUnit("bushels")).toBe(false)
    expect(rateUnitLabel("lb_100")).toBe("lb per 100 birds per day")
    expect(rateUnitLabel("unknown")).toBe("g per bird per day")
  })
})
