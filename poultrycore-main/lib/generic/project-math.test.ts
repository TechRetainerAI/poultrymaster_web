import { describe, expect, it } from "vitest"
import {
  buildAssignment, checkSplit, filterToParam, paramToFilter, projectIdFromQuery, reconciles, toSplits,
} from "./project-math"

describe("project filter value", () => {
  it("round-trips all, general and ids", () => {
    expect(filterToParam(paramToFilter(""))).toBe("all")
    expect(filterToParam(paramToFilter("ALL"))).toBe("all")
    expect(filterToParam(paramToFilter("general"))).toBe("general")
    expect(filterToParam(paramToFilter("12, 15,12"))).toBe("12,15")
  })
  it("treats junk as the whole company, never as a narrower filter", () => {
    expect(paramToFilter("abc")).toEqual({ kind: "all" })
    expect(paramToFilter("-3,0")).toEqual({ kind: "all" })
  })
})

describe("checkSplit", () => {
  it("accepts 60 + 40 of 100 chairs and leaves nothing General", () => {
    const c = checkSplit([{ projectId: 1, value: 60 }, { projectId: 2, value: 40 }], "quantity", 100)
    expect(c.ok).toBe(true)
    expect(c.unallocated).toBe(0)
  })
  it("accepts a partial split; the rest stays General", () => {
    const c = checkSplit([{ projectId: 1, value: 6000 }], "amount", 10000)
    expect(c.ok).toBe(true)
    expect(c.unallocated).toBe(4000)
  })
  it("refuses more than the whole (double counting)", () => {
    const c = checkSplit([{ projectId: 1, value: 70 }, { projectId: 2, value: 40 }], "percent", 0)
    expect(c.ok).toBe(false)
  })
  it("refuses the same project twice and zero parts", () => {
    expect(checkSplit([{ projectId: 1, value: 1 }, { projectId: 1, value: 1 }], "quantity", 5).ok).toBe(false)
    expect(checkSplit([{ projectId: 1, value: 0 }], "quantity", 5).ok).toBe(false)
  })
  it("ignores rows with no project chosen", () => {
    expect(checkSplit([{ projectId: null, value: 999 }], "amount", 10).ok).toBe(true)
  })
})

describe("toSplits / buildAssignment", () => {
  it("sends percent as a share", () => {
    expect(toSplits([{ projectId: 3, value: 25 }], "percent")).toEqual([{ projectId: 3, share: 0.25 }])
  })
  it("sends nothing when no project was touched", () => {
    expect(buildAssignment(undefined)).toBeUndefined()
  })
  it("sends General explicitly when chosen", () => {
    expect(buildAssignment(null)).toEqual({ projectId: null })
  })
  it("uses per-line splits, filling unsplit lines from the header", () => {
    expect(buildAssignment(7, [null, [{ projectId: 8, quantity: 2 }]])).toEqual({
      lines: [[{ projectId: 7, share: 1 }], [{ projectId: 8, quantity: 2 }]],
    })
  })
})

describe("helpers", () => {
  it("reads ?projectId=", () => {
    expect(projectIdFromQuery("?projectId=14&x=1")).toBe(14)
    expect(projectIdFromQuery("?projectId=abc")).toBeNull()
  })
  it("reconciles to the cent", () => {
    expect(reconciles([{ company: 100, projects: 60.004, general: 39.996 }])).toBe(true)
    expect(reconciles([{ company: 100, projects: 60, general: 39 }])).toBe(false)
  })
})
