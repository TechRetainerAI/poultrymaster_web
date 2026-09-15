import { describe, it, expect } from "vitest"
import {
  nextBillingDate,
  billingPeriod,
  dueDate,
  periodsDue,
  periodTotal,
  BILLING_FREQUENCIES,
} from "./billing-schedule"

describe("nextBillingDate", () => {
  // The rows below are the same rows migration 243's verification block asserts
  // against fngenericnextbillingdate. If one of these fails, the browser and
  // the server disagree about when someone gets billed.
  it("matches the SQL schedule, case for case", () => {
    expect(nextBillingDate("2026-01-31", "Weekly")).toBe("2026-02-07")
    expect(nextBillingDate("2026-01-31", "Monthly")).toBe("2026-02-28")
    expect(nextBillingDate("2026-01-31", "Quarterly")).toBe("2026-04-30")
    expect(nextBillingDate("2026-01-31", "Termly")).toBe("2026-05-31")
    expect(nextBillingDate("2026-01-31", "SemiAnnual")).toBe("2026-07-31")
    expect(nextBillingDate("2026-01-31", "Annual")).toBe("2027-01-31")
    expect(nextBillingDate("2026-01-31", "OneTime")).toBeNull()
  })

  it("clamps into a short month instead of skipping it", () => {
    // A monthly plan that started on the 31st still bills in February.
    expect(nextBillingDate("2026-01-31", "Monthly")).toBe("2026-02-28")
    // 2028 is a leap year.
    expect(nextBillingDate("2028-01-31", "Monthly")).toBe("2028-02-29")
    expect(nextBillingDate("2026-03-31", "Monthly")).toBe("2026-04-30")
  })

  it("does not drift once it has clamped", () => {
    // Clamping is per hop, from the date actually billed -- so a plan that
    // clamped to the 28th stays on the 28th. That is what the SQL does, and
    // pretending otherwise would bill a day the server never bills.
    const feb = nextBillingDate("2026-01-31", "Monthly")!
    expect(nextBillingDate(feb, "Monthly")).toBe("2026-03-28")
  })

  it("crosses a year end", () => {
    expect(nextBillingDate("2026-12-15", "Monthly")).toBe("2027-01-15")
    expect(nextBillingDate("2026-11-30", "Quarterly")).toBe("2027-02-28")
  })

  it("returns null for a frequency it does not know", () => {
    expect(nextBillingDate("2026-01-01", "Fortnightly")).toBeNull()
  })

  it("returns null for a date it cannot read", () => {
    expect(nextBillingDate("not a date", "Monthly")).toBeNull()
    expect(nextBillingDate("2026-1-1", "Monthly")).toBeNull()
  })

  it("advances for every frequency except OneTime", () => {
    for (const f of BILLING_FREQUENCIES) {
      const next = nextBillingDate("2026-06-15", f)
      if (f === "OneTime") expect(next).toBeNull()
      else expect(next! > "2026-06-15").toBe(true)
    }
  })
})

describe("billingPeriod", () => {
  it("ends the day before the next bill, so periods never overlap", () => {
    expect(billingPeriod("2026-06-04", "Monthly")).toEqual({
      start: "2026-06-04",
      end: "2026-07-03",
    })
    expect(billingPeriod("2026-06-04", "Weekly")).toEqual({
      start: "2026-06-04",
      end: "2026-06-10",
    })
  })

  it("gives a OneTime plan a single day", () => {
    expect(billingPeriod("2026-06-04", "OneTime")).toEqual({
      start: "2026-06-04",
      end: "2026-06-04",
    })
  })

  it("leaves no gap between consecutive periods", () => {
    const first = billingPeriod("2026-01-31", "Monthly")!
    const second = billingPeriod(nextBillingDate("2026-01-31", "Monthly")!, "Monthly")!
    // The next period starts the day after the previous one ended.
    expect(Date.parse(`${second.start}T00:00:00Z`) - Date.parse(`${first.end}T00:00:00Z`))
      .toBe(86_400_000)
  })
})

describe("dueDate", () => {
  it("adds the payment terms to the period start", () => {
    expect(dueDate("2026-06-04", 14)).toBe("2026-06-18")
    expect(dueDate("2026-06-04", 0)).toBe("2026-06-04")
  })

  it("crosses a month boundary", () => {
    expect(dueDate("2026-01-25", 14)).toBe("2026-02-08")
  })

  it("treats negative terms as due immediately rather than in the past", () => {
    expect(dueDate("2026-06-04", -5)).toBe("2026-06-04")
  })
})

describe("periodsDue", () => {
  it("catches up every period a subscription is behind, oldest first", () => {
    expect(periodsDue("2026-06-04", "Monthly", "2026-09-04")).toEqual([
      "2026-06-04",
      "2026-07-04",
      "2026-08-04",
      "2026-09-04",
    ])
  })

  it("is empty for a subscription that is not due yet", () => {
    expect(periodsDue("2026-10-01", "Monthly", "2026-09-04")).toEqual([])
  })

  it("bills the as-of date itself", () => {
    expect(periodsDue("2026-09-04", "Monthly", "2026-09-04")).toEqual(["2026-09-04"])
  })

  it("stops at the subscription's end date", () => {
    expect(periodsDue("2026-06-04", "Monthly", "2026-12-04", "2026-08-01")).toEqual([
      "2026-06-04",
      "2026-07-04",
    ])
  })

  it("bills a OneTime plan exactly once", () => {
    expect(periodsDue("2026-06-04", "OneTime", "2027-06-04")).toEqual(["2026-06-04"])
  })

  it("cannot spin forever on a frequency it does not know", () => {
    // Unknown frequency has no next date, so it stops after one -- and even a
    // pathological input is capped at the same 60 the SQL guard uses.
    expect(periodsDue("2020-01-01", "Fortnightly", "2030-01-01")).toEqual(["2020-01-01"])
    expect(periodsDue("2000-01-01", "Weekly", "2030-01-01").length).toBe(60)
  })

  it("is empty when there is nothing to bill from", () => {
    expect(periodsDue(null, "Monthly", "2026-09-04")).toEqual([])
    expect(periodsDue(undefined, "Monthly", "2026-09-04")).toEqual([])
  })
})

describe("periodTotal", () => {
  it("is amount minus discount plus tax, the same arithmetic as the SQL", () => {
    expect(periodTotal(500, 50, 25)).toBe(475)
    expect(periodTotal(500)).toBe(500)
  })

  it("does not go negative when the discount exceeds the amount", () => {
    expect(periodTotal(100, 150)).toBe(0)
  })

  it("does not leak float noise into a money figure", () => {
    expect(periodTotal(0.1 + 0.2)).toBe(0.3)
  })
})
