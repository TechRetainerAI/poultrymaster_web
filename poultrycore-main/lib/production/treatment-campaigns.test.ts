import { describe, expect, it } from "vitest"
import {
  addDays,
  dayPostBlocker,
  dayRowState,
  dayTotals,
  daysInclusive,
  describeDose,
  parseQty,
  recordableDays,
  statusLabel,
  suggestQuantity,
  withdrawalUntil,
} from "./treatment-campaigns"

describe("suggestQuantity — arithmetic on the farm's own dose, never a stand-in", () => {
  it("multiplies per bird, per 1,000 birds, or takes a per-flock amount as is", () => {
    expect(suggestQuantity(0.002, "PerBird", 1000)).toBe(2)
    expect(suggestQuantity(1.5, "Per1000Birds", 2000)).toBe(3)
    expect(suggestQuantity(2, "PerFlock", null)).toBe(2)
  })

  it("suggests nothing without a dose, a basis or a bird count", () => {
    expect(suggestQuantity(null, "PerBird", 1000)).toBeNull()
    expect(suggestQuantity(1, null, 1000)).toBeNull()
    expect(suggestQuantity(1, "PerBird", null)).toBeNull()
    expect(suggestQuantity(1, "Per1000Birds", 0)).toBeNull()
    expect(suggestQuantity(0, "PerFlock", 10)).toBeNull()
  })
})

describe("describeDose", () => {
  it("reads the dose back as set", () => {
    expect(describeDose(0.5, "Per1000Birds", "L")).toBe("0.5 L per 1,000 birds per day")
    expect(describeDose(null, "PerBird", "L")).toBeNull()
  })
})

describe("parseQty", () => {
  it("accepts typed numbers and rejects junk", () => {
    expect(parseQty("2.25")).toBe(2.25)
    expect(parseQty("")).toBeNull()
    expect(parseQty("abc")).toBeNull()
    expect(parseQty("-1")).toBeNull()
  })
})

describe("dates", () => {
  it("counts a campaign's days inclusively", () => {
    expect(daysInclusive("2026-10-01", "2026-10-05")).toBe(5)
    expect(daysInclusive("2026-10-05", "2026-10-01")).toBe(0)
  })

  it("lists the days that can be recorded: start up to today, never the future", () => {
    expect(recordableDays("2026-10-01", "2026-10-05", "2026-10-03")).toEqual(["2026-10-01", "2026-10-02", "2026-10-03"])
    expect(recordableDays("2026-10-10", "2026-10-12", "2026-10-03")).toEqual([])
  })

  it("runs withdrawal from the last dose given, by the farm's own days", () => {
    expect(withdrawalUntil("2026-10-05", 7)).toBe("2026-10-12")
    expect(withdrawalUntil("2026-10-05", null)).toBeNull()
    expect(withdrawalUntil(null, 7)).toBeNull()
    expect(addDays("2026-12-30", 3)).toBe("2027-01-02")
  })

  it("labels status", () => {
    expect(statusLabel("InProgress")).toBe("In Progress")
    expect(statusLabel("Scheduled")).toBe("Scheduled")
  })
})

describe("the day grid", () => {
  it("only lets an open flock with exactly one record be dosed, once", () => {
    expect(dayRowState({ isClosed: false, recordCount: 1, postedQuantity: null })).toBe("ok")
    expect(dayRowState({ isClosed: false, recordCount: 0, postedQuantity: null })).toBe("noRecord")
    expect(dayRowState({ isClosed: false, recordCount: 2, postedQuantity: null })).toBe("duplicate")
    expect(dayRowState({ isClosed: true, recordCount: 1, postedQuantity: null })).toBe("closed")
    expect(dayRowState({ isClosed: false, recordCount: 1, postedQuantity: 2 })).toBe("posted")
  })

  it("totals only the flocks that can be dosed", () => {
    const t = dayTotals(10, [
      { state: "ok", actualText: "2" },
      { state: "ok", actualText: "3.5" },
      { state: "noRecord", actualText: "9" },
    ])
    expect(t).toEqual({ available: 10, actual: 5.5, remaining: 4.5 })
  })

  it("blocks posting for the right reason", () => {
    const open = { alreadyPosted: false, campaignOpen: true, inWindow: true }
    const rows = [{ state: "ok" as const, actualText: "2" }]
    expect(dayPostBlocker({ actual: 2, remaining: 1 }, rows, open)).toBeNull()
    expect(dayPostBlocker({ actual: 2, remaining: -1 }, rows, open)).toMatch(/more than the stock/)
    expect(dayPostBlocker({ actual: 0, remaining: 3 }, [], open)).toMatch(/at least one flock/)
    expect(dayPostBlocker({ actual: 2, remaining: 1 }, rows, { ...open, alreadyPosted: true })).toMatch(/already recorded/)
    expect(dayPostBlocker({ actual: 2, remaining: 1 }, rows, { ...open, campaignOpen: false })).toMatch(/closed/)
    expect(dayPostBlocker({ actual: 0, remaining: 3 }, [{ state: "ok", actualText: "x" }], open)).toMatch(/not a number/)
  })
})
