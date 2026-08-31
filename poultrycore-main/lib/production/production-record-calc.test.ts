import { describe, expect, it } from "vitest"
import {
  EGGS_PER_CRATE, birdsLeft, cratesEquivalent, effectiveFeedKg, flockAge,
  netSellableEggs, pickTotal, resolveAge, totalCostOfProduction, totalLosses,
} from "./production-record-calc"

describe("pickTotal", () => {
  it("is crates × 30 + loose", () => {
    expect(pickTotal(12, 5)).toBe(365)
    expect(pickTotal(10, 8)).toBe(308)
    expect(pickTotal(8, 1)).toBe(241)
  })

  it("handles an empty pick", () => {
    expect(pickTotal(0, 0)).toBe(0)
  })

  it("refuses to let bad input produce a negative or fractional count", () => {
    expect(pickTotal(-3, 5)).toBe(5)
    expect(pickTotal(2, -1)).toBe(60)
    expect(pickTotal(1.7, 2.9)).toBe(32)
    expect(pickTotal(NaN, NaN)).toBe(0)
  })
})

describe("cratesEquivalent", () => {
  it("splits eggs into whole crates plus the remainder", () => {
    expect(cratesEquivalent(682)).toEqual({ crates: 22, pieces: 22 })
    expect(cratesEquivalent(60)).toEqual({ crates: 2, pieces: 0 })
    expect(cratesEquivalent(15)).toEqual({ crates: 0, pieces: 15 })
  })

  it("round-trips against pickTotal", () => {
    const { crates, pieces } = cratesEquivalent(914)
    expect(pickTotal(crates, pieces)).toBe(914)
  })

  it("uses the same crate size the form does", () => {
    expect(EGGS_PER_CRATE).toBe(30)
  })
})

describe("egg losses", () => {
  it("sums the four non-sellable categories (migration 198's rule)", () => {
    expect(totalLosses({ broken: 4, meaty: 2, soft: 1, lost: 3 })).toBe(10)
  })

  it("treats missing categories as zero, not NaN", () => {
    expect(totalLosses({ broken: 4 })).toBe(4)
    expect(totalLosses({})).toBe(0)
  })

  it("nets losses off the picked total", () => {
    expect(netSellableEggs(682, 10)).toBe(672)
  })

  it("never reports negative sellable eggs", () => {
    expect(netSellableEggs(5, 40)).toBe(0)
  })
})

describe("birdsLeft", () => {
  it("is always birds minus deaths", () => {
    expect(birdsLeft(1050, 90)).toBe(960)
    expect(birdsLeft(0, 0)).toBe(0)
  })

  it("returns the negative so validation can catch it", () => {
    // Clamping here would hide the exact error the form blocks the save on.
    expect(birdsLeft(10, 25)).toBe(-15)
  })
})

describe("flockAge", () => {
  it("counts whole days, weeks and years from the start date", () => {
    expect(flockAge("2026-01-01", "2026-01-08")).toEqual({ ageDays: 7, ageWeeks: 1, ageYears: 0 })
    expect(flockAge("2025-01-01", "2026-01-01")).toEqual({ ageDays: 365, ageWeeks: 52, ageYears: 1 })
  })

  it("is unaffected by a timestamp on either date", () => {
    // The off-by-one this guards against: local-date parsing across a timezone
    // boundary made a flock a day older or younger than it was.
    expect(flockAge("2026-01-01T23:00:00Z", "2026-01-08T01:00:00Z").ageDays).toBe(7)
  })

  it("never goes negative for a date before the flock started", () => {
    expect(flockAge("2026-06-01", "2026-01-01")).toEqual({ ageDays: 0, ageWeeks: 0, ageYears: 0 })
  })

  it("degrades to zero rather than throwing on missing or junk dates", () => {
    expect(flockAge(null, "2026-01-01").ageDays).toBe(0)
    expect(flockAge("2026-01-01", undefined).ageDays).toBe(0)
    expect(flockAge("not-a-date", "2026-01-01").ageDays).toBe(0)
  })
})

describe("resolveAge", () => {
  it("uses the calculated age when manual entry is off", () => {
    expect(resolveAge(false, { weeks: "9" }, { ageWeeks: 3, ageDays: 21 }))
      .toEqual({ ageInWeeks: 3, ageInDays: 21 })
  })

  it("prefers the box the user actually filled", () => {
    expect(resolveAge(true, { days: "40" }, { ageWeeks: 0, ageDays: 0 }))
      .toEqual({ ageInDays: 40, ageInWeeks: 5 })
    expect(resolveAge(true, { weeks: "6" }, { ageWeeks: 0, ageDays: 0 }))
      .toEqual({ ageInDays: 42, ageInWeeks: 6 })
    expect(resolveAge(true, { years: "2" }, { ageWeeks: 0, ageDays: 0 }))
      .toEqual({ ageInDays: 730, ageInWeeks: 104 })
  })

  it("falls back to zero when manual entry is on but empty", () => {
    expect(resolveAge(true, {}, { ageWeeks: 5, ageDays: 35 }))
      .toEqual({ ageInDays: 0, ageInWeeks: 0 })
  })
})

describe("effectiveFeedKg", () => {
  it("uses the feed lines when there are any", () => {
    // The regression this locks down: the old list-page modal ignored the lines
    // and saved the manual box, so feed entered as lines was stored as 0.
    expect(effectiveFeedKg(125.5, "")).toBe(125.5)
    expect(effectiveFeedKg(125.5, "80")).toBe(125.5)
  })

  it("falls back to the manual box when there are no lines", () => {
    expect(effectiveFeedKg(0, "80")).toBe(80)
    expect(effectiveFeedKg(0, 42.25)).toBe(42.25)
  })

  it("is 0 rather than NaN when neither is given", () => {
    expect(effectiveFeedKg(0, "")).toBe(0)
    expect(effectiveFeedKg(0, "abc")).toBe(0)
  })
})

describe("totalCostOfProduction", () => {
  it("adds feed and medication, rounded to the pesewa", () => {
    expect(totalCostOfProduction(250.004, 99.996)).toBe(350)
    expect(totalCostOfProduction(0, 0)).toBe(0)
  })

  it("tolerates a missing side", () => {
    expect(totalCostOfProduction(120.5, 0)).toBe(120.5)
  })
})
