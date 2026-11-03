import { describe, expect, it } from "vitest"
import { broilerTotals, fmtFcr, fmtKgEach, fmtKgTotal } from "./broiler-kpis"

// The worked example from database/checks/broiler-kpis.test.sql, plus a second flock.
const big = { birdsStarted: 1000, deaths: 50, kgProduced: 2300, feedKg: 4200, totalCost: 5000, profit: 15000, kgIsEstimated: true }
const small = { birdsStarted: 100, deaths: 10, kgProduced: 200, feedKg: 400, totalCost: 600, profit: 300, kgIsEstimated: false }
const unknown = { birdsStarted: 200, deaths: 0, kgProduced: null, feedKg: 0, totalCost: 1000, profit: -1000, kgIsEstimated: false }

describe("broilerTotals", () => {
  it("one flock gives back its own figures", () => {
    const t = broilerTotals([big])
    expect(t.fcr).toBe(1.826)
    expect(t.liveabilityPct).toBe(95)
    expect(t.costPerKg).toBe(2.17)
  })

  it("adds quantities, not ratios: FCR = total feed / total kg", () => {
    const t = broilerTotals([big, small])
    expect(t.kgProduced).toBe(2500)
    expect(t.fcr).toBe(1.84)            // 4600 / 2500, not the mean of 1.826 and 2.0
    expect(t.liveabilityPct).toBe(94.55) // 1040 / 1100
    expect(t.costPerKg).toBe(2.24)      // 5600 / 2500
    expect(t.kgIsEstimated).toBe(true)
  })

  it("leaves a flock with unknown kg out of FCR and cost per kg, but not out of birds or profit", () => {
    const t = broilerTotals([big, unknown])
    expect(t.flocks).toBe(2)
    expect(t.flocksWithKg).toBe(1)
    expect(t.fcr).toBe(1.826)
    expect(t.costPerKg).toBe(2.17)
    expect(t.birdsStarted).toBe(1200)
    expect(t.profit).toBe(14000)
  })

  it("nothing known, nothing claimed", () => {
    const t = broilerTotals([unknown])
    expect(t.fcr).toBeNull()
    expect(t.costPerKg).toBeNull()
    expect(broilerTotals([]).liveabilityPct).toBeNull()
  })
})

describe("formatting", () => {
  it("formats", () => {
    expect(fmtFcr(1.8261)).toBe("1.826")
    expect(fmtKgEach(2.4210526)).toBe("2.42 kg")
    expect(fmtKgTotal(2300.4)).toBe("2,300 kg")
    expect(fmtFcr(null)).toBe("—")
  })
})
