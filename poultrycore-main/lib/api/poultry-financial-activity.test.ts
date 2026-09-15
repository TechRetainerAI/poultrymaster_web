import { describe, it, expect } from "vitest"
import { formatActivityMoment, positionLabel, activitySourceLink, type FinancialActivityRow } from "./poultry-financial-activity"

const row = (o: Partial<FinancialActivityRow>): FinancialActivityRow => ({
  eventKey: "Sale:1", businessDate: "2026-09-12", occurredAt: "2026-09-12T10:30:00",
  activityType: "Operating", type: "Sale", category: "Sales",
  moneyIn: 0, moneyOut: 0, revenue: 0, expense: 0, profitImpact: 0, runningCash: 0,
  isCashActivity: false, isNonCashActivity: false, isInternalTransfer: false,
  positionChanges: [], ...o,
})

describe("formatActivityMoment", () => {
  it("reads the stored wall clock as written, not through the browser's timezone", () => {
    // 10:30 recorded on the farm must read 10:30 to everyone. Going through
    // `new Date("2026-09-12T10:30:00")` would apply the reader's own offset and
    // move an evening entry to the previous day west of the farm.
    expect(formatActivityMoment("2026-09-12T10:30:00")).toBe("09/12/2026 10:30 AM")
    expect(formatActivityMoment("2026-09-12T22:05:00")).toBe("09/12/2026 10:05 PM")
    expect(formatActivityMoment("2026-09-12T12:00:00")).toBe("09/12/2026 12:00 PM")
  })

  it("drops a midnight time, which means the day was back-dated and no clock time is known", () => {
    expect(formatActivityMoment("2026-09-12T00:00:00")).toBe("09/12/2026")
  })

  it("survives empty and unexpected input rather than printing Invalid Date", () => {
    expect(formatActivityMoment("")).toBe("—")
    expect(formatActivityMoment("not a date")).toBe("not a date")
  })
})

describe("positionLabel", () => {
  it("names the positions an owner reads", () => {
    expect(positionLabel("CustomerReceivable")).toBe("Customer Receivable")
    expect(positionLabel("LoanLiability")).toBe("Loan Liability")
  })
  it("passes an unknown position through instead of blanking it", () => {
    expect(positionLabel("SomethingNew")).toBe("SomethingNew")
  })
})

describe("activitySourceLink", () => {
  it("points each event at the module that owns it", () => {
    expect(activitySourceLink(row({ sourceType: "Sale" }))?.href).toBe("/sales")
    expect(activitySourceLink(row({ sourceType: "LoanPayment" }))?.href).toBe("/poultry-loans")
    expect(activitySourceLink(row({ sourceType: "PoultryFeedConsumption" }))?.href).toBe("/feed-inventory-tracker")
    // Routes verified against app/ — a link that 404s is worse than no link.
    expect(activitySourceLink(row({ sourceType: "CustomerPayment" }))?.href).toBe("/poultry-payments")
    expect(activitySourceLink(row({ sourceType: "SupplierPayment" }))?.href).toBe("/supplier-payments")
  })

  it("returns nothing where there is no page to open, rather than a link that 404s", () => {
    expect(activitySourceLink(row({ sourceType: "Adjustment" }))).toBeNull()
    expect(activitySourceLink(row({ sourceType: null }))).toBeNull()
  })
})
