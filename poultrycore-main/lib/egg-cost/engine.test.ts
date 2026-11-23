// Egg Cost & Profit Analyzer engine -- the spec's required scenarios that
// the calculation itself answers. (Database-side guarantees -- isolation,
// non-regression, sorting -- are covered by
// database/checks/poultry-481-egg-cost-analyzer.test.sql.)
import { describe, expect, it } from "vitest"
import {
  allocate, analyze, breakageEffect, costPerCrate, DEFAULT_SETTINGS, margin, maxFeedCost, NEUTRAL_SCENARIO,
  runScenario, sources, targetPrice, targetProduction, trend, validateScenario,
  type EggCostFacts, type FactCost, type FactFlock, type FactRecord,
} from "./engine"

const START = "2026-10-01"
const END = "2026-10-07"

function flock(id: number, over: Partial<FactFlock> = {}): FactFlock {
  return {
    flockId: id, name: `Flock ${id}`, batchId: 1, batchCode: "B1", batchName: "Batch 1", flockType: "Layer",
    startDate: "2026-01-01", closedDate: null, firstEggDate: "2026-06-01",
    originallyPlaced: 1000, birdsAtStart: 1000, birdsAtEnd: 1000,
    birdCost: null, birdCostBasis: null, batchIsHistorical: false,
    lifetimeSaleableEggs: 0, saleableEggsBeforePeriod: 0,
    preLayFeedCost: 0, preLayMedicationCost: 0, preLayRecords: 0, preLayFeedWithoutCost: 0,
    historicalCost: 0, historicalCostHasEstimate: false, assumptions: null,
    ...over,
  }
}

let recId = 1
/** Seven daily records summing to the given week totals. */
function week(flockId: number, t: { gross: number; broken?: number; feed?: number; med?: number; birds?: number }): FactRecord[] {
  const out: FactRecord[] = []
  for (let d = 0; d < 7; d++) {
    const share = (n: number) => (d < 6 ? Math.floor(n / 7) : n - Math.floor(n / 7) * 6)
    const gross = share(t.gross), broken = share(t.broken ?? 0)
    out.push({
      id: recId++, date: `2026-10-0${d + 1}`, flockId, gross, broken, meaty: 0, soft: 0, lost: 0,
      saleable: gross - broken, birds: t.birds ?? 1000, feedKg: 10,
      feedCost: d < 6 ? Math.floor((t.feed ?? 0) / 7 * 100) / 100 : 0, medicationCost: 0, sourceType: "ManualSingleFlock",
    })
  }
  // put exact remainders on the last day
  const last = out[6]
  last.feedCost = Math.round(((t.feed ?? 0) - out.slice(0, 6).reduce((s, r) => s + r.feedCost, 0)) * 100) / 100
  last.medicationCost = t.med ?? 0
  return out
}

let expId = 1
const cost = (component: FactCost["component"], amount: number, flockId: number | null = null, date = "2026-10-03"): FactCost => ({
  expenseId: expId++, date, flockId, component, plLine: component, plSection: "OperatingExpense",
  sourceType: null, sourceId: null, category: component, description: null, amount, assetName: null,
})

function facts(over: Partial<EggCostFacts>): EggCostFacts {
  return {
    farmId: "f", startDate: START, endDate: END,
    packaging: { eggsPerCrate: 30, enableBoxes: false, cratesPerBox: null },
    settings: { ...DEFAULT_SETTINGS },
    flocks: [], records: [], recordLines: [], costs: [], sales: [],
    brokenEggSales: null, historicalCosts: [], assetsInService: 1,
    fingerprint: "x", generatedAt: "now",
    ...over,
  }
}

const FARM = { level: "farm" as const }

describe("Test 1 -- the original calculation", () => {
  it("8,100 over 28,000 saleable eggs is 8.68 a crate", () => {
    expect(costPerCrate(8100, 28000, 30)!).toBeCloseTo(8.678571, 5)
    expect(costPerCrate(8100, 28000, 30)!.toFixed(2)).toBe("8.68")
  })
  it("the analyzer reproduces it from records and expenses", () => {
    const a = analyze(facts({
      flocks: [flock(1)],
      records: week(1, { gross: 28000, feed: 5000, med: 1000 }),
      costs: [cost("Overhead", 500, 1), cost("Labour", 1600, 1)],
    }), FARM)
    expect(a.saleable).toBe(28000)
    expect(a.directTotal).toBe(8100)
    expect(a.directPerCrate!.toFixed(2)).toBe("8.68")
  })
})

describe("Test 2 -- broken eggs", () => {
  it("the same 8,100 over 27,000 saleable eggs is 9.00", () => {
    const a = analyze(facts({
      flocks: [flock(1)],
      records: week(1, { gross: 28000, broken: 1000, feed: 5000, med: 1000 }),
      costs: [cost("Overhead", 500, 1), cost("Labour", 1600, 1)],
    }), FARM)
    expect(a.gross).toBe(28000)
    expect(a.broken).toBe(1000)
    expect(a.saleable).toBe(27000)
    expect(a.directPerCrate!.toFixed(2)).toBe("9.00")
  })
})

describe("Test 3 -- pre-laying costs", () => {
  it("100,000 over 500,000 expected eggs is 0.20 an egg, 6.00 a crate", () => {
    const f = flock(1, {
      birdCost: 100000,
      assumptions: { expectedLifetimeSaleableEggs: 500000, expectedLayingWeeks: null, expectedLayRatePct: null,
        expectedMortalityPct: null, expectedResidualValue: null, useResidualValue: false, notes: null },
    })
    const a = analyze(facts({ flocks: [f], records: week(1, { gross: 28000, feed: 5000 }), costs: [cost("Labour", 1, 1)] }), FARM)
    const row = a.flocks[0]
    expect(row.preLay.ratePerEgg).toBeCloseTo(0.2, 10)
    expect(row.preLay.allocated).toBe(5600)
    const pre = a.components.find((c) => c.key === "PreLaying")!
    expect((pre.amount / a.saleable) * 30).toBeCloseTo(6.0, 10)
    // and it is in Full, not in Direct
    expect(a.fullTotal - a.directTotal).toBeCloseTo(5600, 2)
  })
  it("without an expected lifetime production it is not applied, and says so", () => {
    const a = analyze(facts({ flocks: [flock(1, { birdCost: 100000 })], records: week(1, { gross: 28000, feed: 5000 }) }), FARM)
    expect(a.flocks[0].preLay.status).toBe("NoAssumption")
    expect(a.flocks[0].preLay.allocated).toBe(0)
    expect(a.warnings.some((w) => w.code === "PreLayAssumption")).toBe(true)
  })
})

describe("Test 4 / 5 -- feed is the feed consumed, counted once", () => {
  it("50,000 purchased, 8,000 consumed: 8,000 enters the analysis", () => {
    const purchase = { ...cost("ExcludedStockFeed", 50000), sourceType: "PoultryRawMaterialPurchase" }
    const a = analyze(facts({ flocks: [flock(1)], records: week(1, { gross: 28000, feed: 8000 }), costs: [purchase] }), FARM)
    expect(a.feedTotal).toBe(8000)
    expect(a.excluded.find((e) => e.component === "ExcludedStockFeed")!.amount).toBe(50000)
  })
  it("ingredients bought for feed production and the consumption expense are not added to the feed eaten", () => {
    const ingredients = { ...cost("ExcludedStockFeed", 20000), sourceType: "PoultryRawMaterialPurchase" }
    const consumption = { ...cost("ExcludedStockFeed", 8000), sourceType: "PoultryFeedConsumption" }
    const a = analyze(facts({ flocks: [flock(1)], records: week(1, { gross: 28000, feed: 8000 }), costs: [ingredients, consumption] }), FARM)
    expect(a.feedTotal).toBe(8000)
    expect(a.fullTotal).toBe(8000)
  })
})

describe("Test 6 / 7 -- shared labour and overhead", () => {
  it("3,000 split 60/40 is 1,800 and 1,200", () => {
    const s = allocate(3000, [{ key: 1, weight: 60 }, { key: 2, weight: 40 }])
    expect(s.get(1)).toBe(1800)
    expect(s.get(2)).toBe(1200)
  })
  it("the analyzer allocates shared labour by saleable eggs 60/40", () => {
    const a = analyze(facts({
      settings: { ...DEFAULT_SETTINGS, labourAllocation: "SaleableEggs" },
      flocks: [flock(1), flock(2)],
      records: [...week(1, { gross: 6000, feed: 1 }), ...week(2, { gross: 4000, feed: 1 })],
      costs: [cost("Labour", 3000)],
    }), FARM)
    expect(a.flocks.find((r) => r.flockId === 1)!.labourAllocated).toBe(1800)
    expect(a.flocks.find((r) => r.flockId === 2)!.labourAllocated).toBe(1200)
  })
  it("2,000 of electricity allocated over three flocks reconciles to 2,000 exactly", () => {
    const a = analyze(facts({
      flocks: [flock(1), flock(2, { originallyPlaced: 333 }), flock(3, { originallyPlaced: 777 })],
      records: [...week(1, { gross: 7000, birds: 1000 }), ...week(2, { gross: 2000, birds: 333 }), ...week(3, { gross: 5000, birds: 777 })],
      costs: [cost("Utilities", 2000)],
    }), FARM)
    const total = a.flocks.reduce((s, r) => s + r.overheadAllocated, 0)
    expect(Math.round(total * 100) / 100).toBe(2000)
  })
})

describe("Test 8 -- direct versus full", () => {
  it("direct 8,100 + allocated overhead 1,900 = full 10,000, no duplicate", () => {
    const a = analyze(facts({
      flocks: [flock(1)],
      records: week(1, { gross: 28000, feed: 5000, med: 1000 }),
      costs: [cost("Overhead", 500, 1), cost("Labour", 1600, 1), cost("Utilities", 1900)],
    }), FARM)
    expect(a.directTotal).toBe(8100)
    expect(a.fullTotal).toBe(10000)
  })
})

describe("Test 9 / 10 -- missing costs and zero production", () => {
  it("production and feed but no labour: incomplete, labelled as such", () => {
    const a = analyze(facts({ flocks: [flock(1)], records: week(1, { gross: 28000, feed: 5000 }), costs: [cost("Utilities", 100)] }), FARM)
    expect(a.warnings.some((w) => w.code === "NoLabour")).toBe(true)
    expect(a.completeness).toBe("Partial")
    expect(a.fullLabel).toMatch(/Estimated/)
  })
  it("costs but no saleable eggs: no division by zero, no zero cost", () => {
    const a = analyze(facts({ flocks: [flock(1)], records: week(1, { gross: 0, feed: 5000 }), costs: [cost("Labour", 100, 1)] }), FARM)
    expect(a.saleable).toBe(0)
    expect(a.directPerCrate).toBeNull()
    expect(a.fullPerCrate).toBeNull()
    expect(a.completeness).toBe("Insufficient")
  })
})

describe("Test 11 -- farm, batch and flock", () => {
  it("flock totals add up to the farm total; batch is its flocks", () => {
    const f = facts({
      flocks: [flock(1), flock(2), flock(3, { batchId: 2, batchCode: "B2" })],
      records: [...week(1, { gross: 7000, feed: 700 }), ...week(2, { gross: 5000, feed: 600 }), ...week(3, { gross: 9000, feed: 800 })],
      costs: [cost("Labour", 3000), cost("Utilities", 1000), cost("Labour", 500, 3)],
    })
    const farm = analyze(f, FARM)
    const b1 = analyze(f, { level: "batch", batchId: 1 })
    const b2 = analyze(f, { level: "batch", batchId: 2 })
    expect(Math.round((b1.fullTotal + b2.fullTotal) * 100) / 100).toBe(farm.fullTotal)
    const one = analyze(f, { level: "flock", flockIds: [3] })
    expect(one.fullTotal).toBe(b2.fullTotal)
    expect(farm.unallocatedShared).toBe(0)
  })
  it("a rearing flock takes its share of shared cost, which is not egg cost", () => {
    const f = facts({
      flocks: [flock(1), flock(2, { firstEggDate: null })],
      records: [...week(1, { gross: 7000, feed: 700 }), ...week(2, { gross: 0, feed: 300 })],
      costs: [cost("Utilities", 1000)],
    })
    const a = analyze(f, FARM)
    expect(a.flocks.find((r) => r.flockId === 1)!.overheadAllocated).toBe(500)
    expect(a.notEggCost.reduce((s, x) => s + x.amount, 0)).toBe(500)
    expect(a.feedTotal).toBe(700) // the rearing flock's feed is pre-laying, not egg cost
  })
})

describe("Test 12 / 13 -- sorting and broken-egg sales", () => {
  it("sales by size never change production", () => {
    const base = facts({ flocks: [flock(1)], records: week(1, { gross: 28000, feed: 5000 }) })
    const sold = { ...base, sales: [{ saleId: 1, date: "2026-10-02", flockId: 1, product: "Eggs", size: "Large", eggs: 900, amount: 450 },
      { saleId: 2, date: "2026-10-02", flockId: 1, product: "Eggs", size: "Small", eggs: 600, amount: 240 }] }
    expect(analyze(sold, FARM).gross).toBe(analyze(base, FARM).gross)
    expect(analyze(sold, FARM).saleable).toBe(28000)
  })
  it("broken-egg sales never reduce cost unless the policy says so -- and then only in its own view", () => {
    const f = facts({ flocks: [flock(1)], records: week(1, { gross: 28000, broken: 1000, feed: 5000 }), brokenEggSales: { eggs: 500, amount: 300 } })
    const a = analyze(f, FARM)
    expect(a.byproductAdjustedPerCrate).toBeNull()
    const b = analyze({ ...f, settings: { ...f.settings, byproductTreatment: "DeductBrokenEggSales" } }, FARM)
    expect(b.fullPerCrate).toBe(a.fullPerCrate)
    expect(b.byproductAdjustedPerCrate!).toBeCloseTo(((5000 - 300) / 27000) * 30, 8)
  })
})

describe("Test 14 -- packaging", () => {
  it("packaged and unpackaged cost per crate stay distinct", () => {
    const a = analyze(facts({ flocks: [flock(1)], records: week(1, { gross: 30000, feed: 6000 }), costs: [cost("Packaging", 1000)] }), FARM)
    expect(a.fullPerCrate).toBeCloseTo(6, 10)
    expect(a.packagedPerCrate).toBeCloseTo(7, 10)
  })
})

describe("Test 15 / 18 -- selling price and target margin", () => {
  it("cost 38, price 50: margin 12, 24%", () => {
    const m = margin(38, 50)
    expect(m.margin).toBe(12)
    expect(m.marginPct).toBeCloseTo(0.24, 10)
  })
  it("target 24% margin on price is 50.00; 24% markup on cost is 47.12", () => {
    const t = targetPrice(38, 24)
    expect(t.byMargin!).toBeCloseTo(50, 10)
    expect(t.byMarkup.toFixed(2)).toBe("47.12")
  })
  it("reverse calculators", () => {
    expect(targetProduction(8100, 9, 30).crates).toBe(900)
    const mf = maxFeedCost(27000, 3100, 9, 30)
    expect(mf.feedAllowance).toBe(5000)
    const be = breakageEffect(8100, 28000, 5, 2, 30)
    expect(be.to.perCrate!).toBeLessThan(be.from.perCrate!)
    expect(be.extraSaleableEggs).toBeCloseTo(840, 6)
  })
})

describe("Test 16 / 17 -- What-If never touches the baseline", () => {
  const f = facts({ flocks: [flock(1)], records: week(1, { gross: 28000, feed: 5000, med: 1000 }), costs: [cost("Labour", 1600, 1), cost("Overhead", 500, 1)] })
  it("feed +15% raises the cost per crate by exactly feed × 15%", () => {
    const base = analyze(f, FARM)
    const before = JSON.stringify(base)
    const s = runScenario(base, { ...NEUTRAL_SCENARIO, feedPricePct: 15 })
    expect(s.fullPerCrate! - base.fullPerCrate!).toBeCloseTo((5000 * 0.15 / 28000) * 30, 8)
    expect(JSON.stringify(base)).toBe(before)
  })
  it("egg output -10% with costs constant: unit cost ÷ 0.9", () => {
    const base = analyze(f, FARM)
    const s = runScenario(base, { ...NEUTRAL_SCENARIO, eggOutputPct: -10 })
    expect(s.fullPerCrate!).toBeCloseTo(base.fullPerCrate! / 0.9, 8)
  })
  it("refuses impossible inputs", () => {
    expect(validateScenario({ ...NEUTRAL_SCENARIO, feedPricePct: -150 }).length).toBeGreaterThan(0)
    expect(validateScenario({ ...NEUTRAL_SCENARIO, lossRatePct: 120 }).length).toBeGreaterThan(0)
    expect(validateScenario({ ...NEUTRAL_SCENARIO, sellingPricePerCrate: -1 }).length).toBeGreaterThan(0)
  })
})

describe("drilldown and trends", () => {
  const f = facts({
    flocks: [flock(1), flock(2)],
    records: [...week(1, { gross: 6000, feed: 600 }), ...week(2, { gross: 4000, feed: 400 })],
    costs: [cost("Labour", 1000), cost("Utilities", 500), cost("Labour", 200, 2)],
  })
  it("the source rows of every component add up to the component", () => {
    for (const scope of [FARM, { level: "flock" as const, flockIds: [2] }]) {
      const a = analyze(f, scope)
      for (const c of a.components) {
        const rows = sources(f, a, c.key)
        const total = Math.round(rows.reduce((s, r) => s + r.amount, 0) * 100) / 100
        expect({ key: c.key, total }).toEqual({ key: c.key, total: c.amount })
      }
    }
  })
  it("weekly trend buckets cover the period", () => {
    const t = trend(f, FARM, "week")
    expect(t.reduce((s, p) => s + p.saleable, 0)).toBe(10000)
  })
})
