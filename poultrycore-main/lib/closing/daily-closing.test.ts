import { describe, expect, it } from "vitest"
import type { ClosingCheck, ClosingWorkspace } from "@/lib/api/poultry-daily-closing"
import {
  closeReadiness,
  closingActionHref,
  closingStatusLabel,
  diffClosingState,
  formatLongDate,
  productionSummaryLine,
} from "./daily-closing"

function check(status: ClosingCheck["status"], key = `k-${status}`): ClosingCheck {
  return { key, section: "production", status, title: key, description: null, action: null }
}

function ws(p: Partial<{
  eggs: number; revenue: number; moneyIn: number; moneyOut: number; missing: number; expected: number
}> = {}): ClosingWorkspace {
  return {
    farmId: "f", businessDate: "2026-09-20", companyToday: "2026-09-20", companyLocalTime: "", timeZoneId: "Africa/Accra",
    currencySymbol: "GHC", generatedAtUtc: "",
    production: {
      expectedFlocks: p.expected ?? 20, reportedFlocks: (p.expected ?? 20) - (p.missing ?? 0), missingFlocks: p.missing ?? 0,
      awaitingPosting: 0, duplicateFlocks: 0, records: 20, eggsProduced: p.eggs ?? 14842, eggsDamaged: 0, goodEggs: 0,
      mortality: 13, feedKg: 2940, medicationUsed: 0, productionCost: 0,
      unpostedBatches: [], impossibleBirdCounts: [], unusualMortality: [],
    },
    sales: { count: 3, revenue: p.revenue ?? 1000, cashSales: 600, creditSales: 400, paymentsReceived: 100, paymentsCount: 1, receivablesChange: 300 },
    cash: { moneyIn: p.moneyIn ?? 700, moneyOut: p.moneyOut ?? 200, netCashFlow: (p.moneyIn ?? 700) - (p.moneyOut ?? 200),
            openingCash: 0, closingCash: 0, reconciliations: 0, expectedCash: null, actualCash: null, difference: null },
    expenses: { count: 1, total: 200, cash: 200, credit: 0, nonCash: 0 },
    inventory: { lowFeed: [], lowStock: [], negativeStock: [] },
    outstanding: { unpostedBatches: 0, draftDriverReturns: 0, loadingsWithoutReturn: 0, previousDayClosed: true },
    policy: {
      missingProduction: "Blocking", unpostedProduction: "Blocking", impossibleBirdCounts: "Blocking",
      pendingDriverReturns: "Warning", negativeStock: "Warning", cashDifference: "Warning",
      cashDifferenceTolerance: 0, requireCashCount: false, lowFeedDays: 3, unusualMortalityPct: 1, isCustomised: false,
    },
    checklist: [],
    counts: { blocking: 0, warning: 0, complete: 0 },
  }
}

describe("closingStatusLabel", () => {
  it("calls an approved closing Closed", () => {
    expect(closingStatusLabel({ status: "Approved" })).toBe("Closed")
    expect(closingStatusLabel({ status: "Submitted" })).toBe("Awaiting approval")
    expect(closingStatusLabel({ status: "Draft" })).toBe("Open")
    expect(closingStatusLabel(null)).toBe("Not closed")
  })
})

describe("closeReadiness", () => {
  it("allows closing with warnings", () => {
    const r = closeReadiness({ checklist: [check("Warning"), check("Complete")] }, null)
    expect(r.canClose).toBe(true)
    expect(r.warnings).toHaveLength(1)
    expect(r.reason).toBeNull()
  })

  it("refuses while anything blocks", () => {
    const r = closeReadiness({ checklist: [check("Blocking", "a"), check("Blocking", "b"), check("Warning")] }, { status: "Draft" })
    expect(r.canClose).toBe(false)
    expect(r.blockers.map((b) => b.key)).toEqual(["a", "b"])
    expect(r.reason).toBe("2 blocking checks must be resolved first.")
  })

  it("refuses a day that is already closed", () => {
    const r = closeReadiness({ checklist: [check("Complete")] }, { status: "Approved" })
    expect(r.canClose).toBe(false)
    expect(r.reason).toBe("This day is already closed.")
  })
})

describe("closingActionHref", () => {
  it("maps each server action key to a page", () => {
    expect(closingActionHref("missing-production", "2026-09-20")).toBe("/poultry-farm-completeness?date=2026-09-20")
    expect(closingActionHref("unposted-batches", "2026-09-20")).toBe("/batch-production-records?date=2026-09-20")
    expect(closingActionHref("production-records", "2026-09-20")).toBe("/production-records?date=2026-09-20")
    expect(closingActionHref("driver-returns", "2026-09-20")).toBe("/poultry-driver-returns?date=2026-09-20")
    expect(closingActionHref("egg-sorting", "2026-09-20")).toBe("/poultry-egg-sorting")
    expect(closingActionHref("customer-balances", "2026-09-20")).toBe("/sales?date=2026-09-20")
    // Current by nature: no date to carry.
    expect(closingActionHref("cash-count", "2026-09-20")).toBe("/poultry-cash-reconciliation")
  })

  it("links the previous day across a month boundary", () => {
    expect(closingActionHref("previous-day", "2026-10-01")).toBe("/poultry-daily-closing?date=2026-09-30")
  })

  it("gives no link for an unknown or empty action", () => {
    expect(closingActionHref("something-new", "2026-09-20")).toBeNull()
    expect(closingActionHref(null, "2026-09-20")).toBeNull()
  })
})

describe("diffClosingState (State At Closing vs Current Corrected State)", () => {
  it("is empty when nothing changed", () => {
    expect(diffClosingState(ws(), ws())).toEqual([])
  })

  it("reports a late sale and its cash effect", () => {
    const changes = diffClosingState(ws({ revenue: 1000, moneyIn: 700 }), ws({ revenue: 1050, moneyIn: 750 }))
    expect(changes.map((c) => c.label)).toEqual(["Sales", "Money in", "Net cash flow"])
    expect(changes[0]).toMatchObject({ atClose: 1000, current: 1050, delta: 50, kind: "money" })
  })

  it("ignores floating-point noise below a cent", () => {
    expect(diffClosingState(ws({ revenue: 0.1 + 0.2 }), ws({ revenue: 0.3 }))).toEqual([])
  })

  it("is empty when there is no closing snapshot", () => {
    expect(diffClosingState(null, ws())).toEqual([])
  })
})

describe("summary text", () => {
  it("formats the closing heading date without the browser's timezone", () => {
    expect(formatLongDate("2026-09-20")).toBe("September 20, 2026")
    expect(formatLongDate("2026-01-01T00:00:00")).toBe("January 1, 2026")
  })

  it("summarises production completeness", () => {
    expect(productionSummaryLine(ws())).toBe("Complete")
    expect(productionSummaryLine(ws({ missing: 3 }))).toBe("3 of 20 flocks missing")
    expect(productionSummaryLine(ws({ expected: 0 }))).toBe("No flocks expected")
  })
})
