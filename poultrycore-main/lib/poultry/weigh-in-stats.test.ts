import { describe, expect, it } from "vitest"
import { computeWeighInStats, formatWeight, parseWeights } from "./weigh-in-stats"

// Same cases as database/checks/flock-weigh-ins.test.sql (check 1).
describe("computeWeighInStats", () => {
  it("1a: an even spread", () => {
    expect(computeWeighInStats([1800, 1900, 2000, 2100, 2200])).toEqual({
      sampleSize: 5, avgWeightG: 2000, minWeightG: 1800, maxWeightG: 2200, uniformityPct: 100, cvPct: 7.91,
    })
  })
  it("1b: outliers pull uniformity down and CV up", () => {
    const s = computeWeighInStats([1000, 2000, 2000, 2000, 3000])!
    expect(s.uniformityPct).toBe(60)
    expect(s.cvPct).toBe(35.36)
  })
  it("1c: one bird has no spread", () => {
    const s = computeWeighInStats([1500])!
    expect(s.uniformityPct).toBe(100)
    expect(s.cvPct).toBeNull()
  })
  it("1d: exactly +/-10% counts as uniform", () => {
    expect(computeWeighInStats([2000, 1800, 2200])!.uniformityPct).toBe(100)
  })
  it("nothing weighed, nothing computed", () => {
    expect(computeWeighInStats([])).toBeNull()
  })
})

describe("parseWeights", () => {
  it("splits on spaces, commas, semicolons and lines", () => {
    expect(parseWeights("1850, 1920 1780;\n2010", "g").weightsG).toEqual([1850, 1920, 1780, 2010])
  })
  it("converts kilograms", () => {
    expect(parseWeights("1.85 2.1", "kg").weightsG).toEqual([1850, 2100])
  })
  it("keeps what it cannot read, so the form can point at it", () => {
    const p = parseWeights("1850 abc 0 -5 25000", "g")
    expect(p.weightsG).toEqual([1850])
    expect(p.invalid).toEqual(["abc", "0", "-5", "25000"])
  })
})

describe("formatWeight", () => {
  it("grams under a kilo, kilos above", () => {
    expect(formatWeight(450)).toBe("450 g")
    expect(formatWeight(1850)).toBe("1.85 kg")
    expect(formatWeight(null)).toBe("—")
  })
})
