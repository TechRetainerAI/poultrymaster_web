import { describe, expect, it } from "vitest"
import { mergeNewestFirst } from "./merge-by-date"

describe("mergeNewestFirst", () => {
  const d = (s: string) => ({ d: s })
  it("slots extra rows in by date and keeps the list's own order", () => {
    const rows = [d("2026-11-20"), d("2026-11-15"), d("2026-11-01")]
    const out = mergeNewestFirst(rows, [d("2026-11-12"), d("2026-11-30")], (x) => x.d)
    expect(out.map((x) => x.d)).toEqual(["2026-11-30", "2026-11-20", "2026-11-15", "2026-11-12", "2026-11-01"])
  })
  it("puts undated extras last and returns the list as is when there are none", () => {
    const rows = [d("2026-11-20")]
    expect(mergeNewestFirst(rows, [], (x) => x.d)).toBe(rows)
    expect(mergeNewestFirst(rows, [d("")], (x) => x.d).map((x) => x.d)).toEqual(["2026-11-20", ""])
  })
})
