import { describe, expect, it } from "vitest"
import { occurrenceDate, paymentEffect, previewDates, validateTemplate } from "./recurring-expense"
import { moduleForFarmType } from "@/lib/api/recurring-expenses"

// These mirror the database checks in recurring-expense-engine.test.sql (A1-A5),
// so the form's preview and what is actually raised can never disagree.
describe("occurrenceDate — anchored on the start date", () => {
  it("keeps month ends from 31 Jan without drifting", () => {
    expect([0, 1, 2, 3, 4].map((n) => occurrenceDate("2027-01-31", "Monthly", n)))
      .toEqual(["2027-01-31", "2027-02-28", "2027-03-31", "2027-04-30", "2027-05-31"])
  })
  it("uses 29 Feb in a leap year", () => {
    expect(occurrenceDate("2028-01-31", "Monthly", 1)).toBe("2028-02-29")
  })
  it("annual from 29 Feb", () => {
    expect([0, 1, 4].map((n) => occurrenceDate("2028-02-29", "Annual", n))).toEqual(["2028-02-29", "2029-02-28", "2032-02-29"])
  })
  it("quarterly from 30 Nov", () => {
    expect([0, 1, 2].map((n) => occurrenceDate("2026-11-30", "Quarterly", n))).toEqual(["2026-11-30", "2027-02-28", "2027-05-30"])
  })
  it("weekly and biweekly cross month and year ends", () => {
    expect(occurrenceDate("2026-12-28", "Weekly", 1)).toBe("2027-01-04")
    expect(occurrenceDate("2026-10-01", "Biweekly", 1)).toBe("2026-10-15")
  })
  it("semi-annual", () => {
    expect(occurrenceDate("2026-08-31", "SemiAnnual", 1)).toBe("2027-02-28")
  })
})

describe("previewDates", () => {
  it("stops at the end date", () => {
    expect(previewDates("2026-01-15", "Monthly", 10, "2026-03-20")).toEqual(["2026-01-15", "2026-02-15", "2026-03-15"])
  })
})

describe("paymentEffect", () => {
  it("credit is a payable, never cash", () => {
    expect(paymentEffect("Credit", true, false)).toMatch(/supplier balance, no cash/)
  })
  it("says when cash moves for modules that approve", () => {
    expect(paymentEffect("Cash", true, true)).toMatch(/when the expense is approved/)
    expect(paymentEffect("Cash", true, false)).toMatch(/when you post it/)
  })
})

describe("validateTemplate", () => {
  const ok = { name: "Rent", amount: 3000, frequency: "Monthly", startDate: "2026-10-01", categoryOk: true, paymentMethod: "Cash" }
  it("accepts a sound template", () => expect(validateTemplate(ok)).toEqual([]))
  it("refuses what the database refuses", () => {
    expect(validateTemplate({ ...ok, amount: 0 })).toContain("The amount must be greater than 0.")
    expect(validateTemplate({ ...ok, endDate: "2026-09-01" })[0]).toMatch(/before the start date/)
    expect(validateTemplate({ ...ok, paymentMethod: "Credit" })).toContain("An expense bought on credit needs a supplier, so it can be owed to someone.")
    expect(validateTemplate({ ...ok, categoryOk: false })).toContain("Choose a category.")
  })
  it("lets a draft template choose its cash account later, but not an automatic one", () => {
    expect(validateTemplate({ ...ok, approvalMode: "Draft", cashAccountId: null })).toEqual([])
    expect(validateTemplate({ ...ok, approvalMode: "AutoPost", cashAccountId: null })).toContain("Automatic posting needs the cash account it is paid from.")
    expect(validateTemplate({ ...ok, approvalMode: "AutoPost", cashAccountId: 22 })).toEqual([])
    expect(validateTemplate({ ...ok, approvalMode: "AutoPost", paymentMethod: "Credit", supplierId: 5, cashAccountId: null })).toEqual([])
  })
})

describe("moduleForFarmType", () => {
  it("maps every company type, legacy blank = poultry", () => {
    expect(["Poultry", "Water", "Generic", "Hotel", "Restaurant", "", null].map((t) => moduleForFarmType(t as any)))
      .toEqual(["poultry", "water", "generic", "hotel", "restaurant", "poultry", "poultry"])
  })
})
