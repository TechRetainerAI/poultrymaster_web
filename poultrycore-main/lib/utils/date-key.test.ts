import { describe, it, expect } from "vitest"
import { entryTimestamp, toLocalDateKey } from "./date-key"

describe("entryTimestamp", () => {
  // Fixed "now" so the test says what it means rather than depending on the
  // clock it happens to run on.
  const NOW = new Date("2026-09-04T10:56:01.864Z")

  it("stamps the real clock time when the entry is dated today", () => {
    // The whole point: something recorded just now must sort above everything
    // already recorded today, not beneath it at midnight.
    expect(entryTimestamp("2026-09-04", NOW)).toBe("2026-09-04T10:56:01.864Z")
  })

  it("uses midnight for a back-dated entry", () => {
    // Nobody knows what time last Tuesday's payment happened, and inventing a
    // time would put it in a misleading position within that day.
    expect(entryTimestamp("2026-09-01", NOW)).toBe("2026-09-01T00:00:00.000Z")
  })

  it("uses midnight for a future-dated entry", () => {
    expect(entryTimestamp("2026-12-25", NOW)).toBe("2026-12-25T00:00:00.000Z")
  })

  it("passes an empty value through as null so the server decides", () => {
    expect(entryTimestamp("", NOW)).toBeNull()
    expect(entryTimestamp(null, NOW)).toBeNull()
    expect(entryTimestamp(undefined, NOW)).toBeNull()
  })

  it("compares UTC date keys on both sides", () => {
    // Late-evening UTC: the key is still that day, so it is still "today".
    const late = new Date("2026-09-04T23:59:59.000Z")
    expect(entryTimestamp("2026-09-04", late)).toBe("2026-09-04T23:59:59.000Z")
  })
})

describe("toLocalDateKey", () => {
  it("returns an empty string for junk rather than throwing", () => {
    expect(toLocalDateKey("")).toBe("")
    expect(toLocalDateKey(null)).toBe("")
    expect(toLocalDateKey("not a date")).toBe("")
  })
})
