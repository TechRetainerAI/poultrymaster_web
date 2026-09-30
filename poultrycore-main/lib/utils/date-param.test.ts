import { describe, expect, it } from "vitest"
import { parseDateParam } from "./date-param"

describe("parseDateParam", () => {
  it("reads a valid date", () => {
    expect(parseDateParam("?date=2026-09-29")).toBe("2026-09-29")
    expect(parseDateParam("?tab=x&date=2026-09-29")).toBe("2026-09-29")
  })

  it("ignores anything that is not a calendar date", () => {
    for (const s of ["", "?date=", "?date=29/09/2026", "?date=2026-13-01", "?date=today", null]) {
      expect(parseDateParam(s)).toBeNull()
    }
  })
})
