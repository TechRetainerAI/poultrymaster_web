import { describe, it, expect } from "vitest"
import {
  buildCashFlowAnalysis, pctChange, describeChange, runwayDays,
  type CashFlowAnalysisInput,
} from "./cash-flow-analysis"

// Plain formatter so assertions read as numbers, not currency.
const fmt = (n: number) => n.toFixed(2)

const base: CashFlowAnalysisInput = {
  moneyIn: 0, moneyOut: 0, netCashFlow: 0, cashAtHand: 0,
  offLedgerIn: 0, offLedgerOut: 0, transferVolume: 0,
  movementCount: 0, daysInPeriod: 30,
  previousMoneyIn: 0, previousMoneyOut: 0, previousNetCashFlow: 0,
  moneyInByCategory: [], moneyOutByCategory: [],
}
const make = (o: Partial<CashFlowAnalysisInput>): CashFlowAnalysisInput => ({ ...base, ...o })
const ids = (o: Partial<CashFlowAnalysisInput>) => buildCashFlowAnalysis(make(o), fmt).map((i) => i.id)
const byId = (o: Partial<CashFlowAnalysisInput>, id: string) =>
  buildCashFlowAnalysis(make(o), fmt).find((i) => i.id === id)

describe("pctChange", () => {
  it("computes a normal change", () => {
    expect(pctChange(110, 100)).toBeCloseTo(10)
    expect(pctChange(90, 100)).toBeCloseTo(-10)
  })

  it("returns null on a zero baseline rather than Infinity", () => {
    expect(pctChange(500, 0)).toBeNull()
  })

  it("uses the magnitude of the baseline, so a negative baseline still reads correctly", () => {
    // -100 -> -50 is an improvement of 50 points on a base of 100.
    expect(pctChange(-50, -100)).toBeCloseTo(50)
  })

  it("returns null for non-finite input", () => {
    expect(pctChange(NaN, 100)).toBeNull()
    expect(pctChange(100, NaN)).toBeNull()
  })
})

describe("describeChange", () => {
  it("puts direction in words", () => {
    expect(describeChange(12.44)).toBe("up 12.4%")
    expect(describeChange(-3)).toBe("down 3.0%")
  })

  it("calls a sub-0.1% move unchanged rather than up 0.0%", () => {
    expect(describeChange(0)).toBe("unchanged")
    expect(describeChange(0.04)).toBe("unchanged")
  })

  it("passes null through", () => {
    expect(describeChange(null)).toBeNull()
  })
})

describe("runwayDays", () => {
  it("divides cash by the daily burn", () => {
    // 3000 out over 30 days = 100/day; 1000 on hand = 10 days.
    expect(runwayDays(1000, -3000, 30)).toBe(10)
  })

  it("is null when cash is growing — a runway would be meaningless", () => {
    expect(runwayDays(1000, 500, 30)).toBeNull()
  })

  it("is null when there is no cash to run down", () => {
    expect(runwayDays(0, -500, 30)).toBeNull()
    expect(runwayDays(-200, -500, 30)).toBeNull()
  })

  it("floors rather than rounds up, so it never overstates", () => {
    expect(runwayDays(1090, -3000, 30)).toBe(10)
  })
})

describe("buildCashFlowAnalysis", () => {
  it("says so plainly when nothing moved, and returns nothing else", () => {
    const r = buildCashFlowAnalysis(base, fmt)
    expect(r).toHaveLength(1)
    expect(r[0].id).toBe("no-activity")
    expect(r[0].tone).toBe("neutral")
  })

  it("reports a positive period as good, with the retention share", () => {
    const i = byId({ moneyIn: 1000, moneyOut: 400, netCashFlow: 600 }, "net-positive")
    expect(i?.tone).toBe("good")
    expect(i?.detail).toContain("60.0 of every 100")
  })

  it("reports a negative period as watch without claiming the business stopped", () => {
    const i = byId({ moneyIn: 400, moneyOut: 1000, netCashFlow: -600 }, "net-negative")
    expect(i?.tone).toBe("watch")
    expect(i?.title).toContain("600.00")
  })

  // --- concentration ---------------------------------------------------------
  it("flags a dominant spending category only when there was a real choice", () => {
    const cats = [
      { label: "Feed", amount: 700, sharePercent: 70 },
      { label: "Labour", amount: 200, sharePercent: 20 },
      { label: "Vet", amount: 100, sharePercent: 10 },
    ]
    expect(byId({ moneyIn: 500, moneyOut: 1000, moneyOutByCategory: cats }, "top-outflow")?.tone)
      .toBe("watch")
  })

  it("does not call two categories concentrated — that is arithmetic, not insight", () => {
    const cats = [
      { label: "Feed", amount: 700, sharePercent: 70 },
      { label: "Labour", amount: 300, sharePercent: 30 },
    ]
    expect(byId({ moneyIn: 500, moneyOut: 1000, moneyOutByCategory: cats }, "top-outflow")?.tone)
      .toBe("neutral")
  })

  it("words a single income source as all of it", () => {
    const i = byId({
      moneyIn: 1000, moneyOut: 100,
      moneyInByCategory: [{ label: "Sales", amount: 1000, sharePercent: 100 }],
    }, "top-inflow")
    expect(i?.detail).toContain("All")
    expect(i?.tone).toBe("neutral")   // one source is not a warning on its own
  })

  it("flags dependence when one of several sources dominates", () => {
    const i = byId({
      moneyIn: 1000, moneyOut: 100,
      moneyInByCategory: [
        { label: "Sales", amount: 850, sharePercent: 85 },
        { label: "Owner injection", amount: 150, sharePercent: 15 },
      ],
    }, "top-inflow")
    expect(i?.tone).toBe("watch")
  })

  // --- comparison ------------------------------------------------------------
  it("compares against the previous period when it had activity", () => {
    const i = byId({
      moneyIn: 1100, moneyOut: 500, netCashFlow: 600,
      previousMoneyIn: 1000, previousMoneyOut: 600, previousNetCashFlow: 400,
    }, "vs-previous")
    expect(i?.tone).toBe("good")
    expect(i?.detail).toContain("up 10.0%")
  })

  it("invents no trend when the previous period was empty", () => {
    expect(ids({ moneyIn: 1000, moneyOut: 400, netCashFlow: 600 })).not.toContain("vs-previous")
  })

  it("marks a decline as watch even while still cash positive", () => {
    const i = byId({
      moneyIn: 800, moneyOut: 500, netCashFlow: 300,
      previousMoneyIn: 1000, previousMoneyOut: 400, previousNetCashFlow: 600,
    }, "vs-previous")
    expect(i?.tone).toBe("watch")
  })

  // --- runway ----------------------------------------------------------------
  it("gives a runway when burning cash, and calls a short one out", () => {
    const i = byId({
      moneyIn: 100, moneyOut: 3100, netCashFlow: -3000,
      cashAtHand: 1000, daysInPeriod: 30,
    }, "runway")
    expect(i?.tone).toBe("watch")          // 10 days
    expect(i?.title).toContain("10 days")
  })

  it("treats a long runway as neutral, not alarming", () => {
    const i = byId({
      moneyIn: 100, moneyOut: 400, netCashFlow: -300,
      cashAtHand: 100000, daysInPeriod: 30,
    }, "runway")
    expect(i?.tone).toBe("neutral")
  })

  it("reports accumulation instead of runway when cash is growing", () => {
    const got = ids({ moneyIn: 1000, moneyOut: 400, netCashFlow: 600, cashAtHand: 5000 })
    expect(got).toContain("accumulation")
    expect(got).not.toContain("runway")
  })

  // --- off-ledger, the boss's point -----------------------------------------
  it("keeps off-ledger money neutral in tone", () => {
    const i = byId({
      moneyIn: 1000, moneyOut: 400, netCashFlow: 600,
      offLedgerIn: 200, offLedgerOut: 100,
    }, "off-ledger")
    expect(i?.tone).toBe("neutral")
    expect(i?.detail).not.toMatch(/missing|wrong|error|problem|fix/i)
  })

  it("omits off-ledger entirely when there is none", () => {
    expect(ids({ moneyIn: 1000, moneyOut: 400, netCashFlow: 600 })).not.toContain("off-ledger")
  })

  it("explains transfers as not being income or spending", () => {
    const i = byId({ moneyIn: 1000, moneyOut: 400, netCashFlow: 600, transferVolume: 900 }, "transfers")
    expect(i?.tone).toBe("neutral")
    expect(i?.detail).toContain("not income or spending")
  })

  // --- ordering --------------------------------------------------------------
  it("leads with the net position, since that is the decision", () => {
    const got = ids({
      moneyIn: 1000, moneyOut: 400, netCashFlow: 600,
      offLedgerIn: 500, transferVolume: 100,
      moneyOutByCategory: [{ label: "Feed", amount: 400, sharePercent: 100 }],
    })
    expect(got[0]).toBe("net-positive")
  })

  it("never emits duplicate ids", () => {
    const got = ids({
      moneyIn: 1000, moneyOut: 900, netCashFlow: 100, cashAtHand: 5000,
      offLedgerIn: 100, offLedgerOut: 50, transferVolume: 200,
      previousMoneyIn: 800, previousMoneyOut: 700, previousNetCashFlow: 100,
      moneyInByCategory: [{ label: "Sales", amount: 1000, sharePercent: 100 }],
      moneyOutByCategory: [
        { label: "Feed", amount: 500, sharePercent: 55.6 },
        { label: "Labour", amount: 250, sharePercent: 27.8 },
        { label: "Vet", amount: 150, sharePercent: 16.6 },
      ],
    })
    expect(new Set(got).size).toBe(got.length)
  })

  it("survives a divide-by-zero shaped period without throwing", () => {
    expect(() => buildCashFlowAnalysis(make({
      moneyIn: 0, moneyOut: 500, netCashFlow: -500, daysInPeriod: 0, cashAtHand: 0,
    }), fmt)).not.toThrow()
  })
})
