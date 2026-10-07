import { describe, expect, it } from "vitest"
import type { EggSortingPick } from "@/lib/api/egg-sorting"
import {
  cratesText,
  groupProductionDays,
  parseEggs,
  pickStatus,
  sortingBalance,
  sortingBlocker,
  statusOf,
  toApiLines,
} from "./egg-sorting"

const pick = (over: Partial<EggSortingPick>): EggSortingPick => ({
  productionRecordId: 1, flockId: 3, flockName: "Flock 3", batchName: null, houseName: null,
  productionDate: "2026-10-05T00:00:00", pickNumber: 1, pickGross: 500, pickSorted: 0, pickLeft: 500,
  available: 500, recordGross: 1710, recordCollectionLoss: 0, recordSaleable: 1710, recordSorted: 0,
  recordLeft: 1710, byPickSorted: 0, ...over,
})

describe("egg sorting helpers", () => {
  it("groups pick rows into one production day per record, picks in order", () => {
    const days = groupProductionDays([
      pick({ pickNumber: 2, pickGross: 600 }),
      pick({ pickNumber: 1 }),
      pick({ productionRecordId: 2, productionDate: "2026-10-06", recordSorted: 50, recordLeft: 0, pickSorted: 50, available: 0 }),
    ])
    expect(days).toHaveLength(2)
    expect(days[0].productionDate).toBe("2026-10-06")              // newest first
    expect(days[1].picks.map((p) => p.pickNumber)).toEqual([1, 2])
    expect(days[0].status).toBe("Complete")
    expect(days[1].status).toBe("NotStarted")
  })

  it("derives pick status from sorted and remaining", () => {
    expect(statusOf(0, 500)).toBe("NotStarted")
    expect(statusOf(300, 200)).toBe("Partial")
    expect(statusOf(500, 0)).toBe("Complete")
    // The day's saleable cap can leave a pick with nothing available.
    expect(pickStatus(pick({ pickSorted: 590, pickLeft: 20, available: 0 }))).toBe("Complete")
  })

  it("balances: input = sized + loss, remaining = available - input (spec 12/85)", () => {
    const b = sortingBalance(1710, [
      { lineType: "SizedOutput", text: "840" },
      { lineType: "SizedOutput", text: "600" },
      { lineType: "SizedOutput", text: "210" },
      { lineType: "SizedOutput", text: "40" },
      { lineType: "Reject", text: "20" },
    ])
    expect(b).toMatchObject({ sized: 1690, loss: 20, input: 1710, remainingAfter: 0 })
    expect(sortingBlocker(b)).toBeNull()
  })

  it("allows partial sorting and refuses more than is left", () => {
    expect(sortingBlocker(sortingBalance(500, [{ lineType: "SizedOutput", text: "300" }]))).toBeNull()
    expect(sortingBlocker(sortingBalance(500, [{ lineType: "SizedOutput", text: "490" }, { lineType: "Breakage", text: "20" }])))
      .toMatch(/10 more than are left/)
    expect(sortingBlocker(sortingBalance(500, []))).toMatch(/how the eggs graded/)
    expect(sortingBlocker(sortingBalance(500, [{ lineType: "SizedOutput", text: "1.5" }]))).toMatch(/whole numbers/)
  })

  it("sends only filled lines, sizes with their id, losses without one", () => {
    expect(toApiLines([
      { lineType: "SizedOutput", eggSizeId: 4, text: "260" },
      { lineType: "SizedOutput", eggSizeId: 5, text: "" },
      { lineType: "Reject", eggSizeId: 9, text: "10" },
    ])).toEqual([
      { lineType: "SizedOutput", eggSizeId: 4, quantity: 260, notes: null },
      { lineType: "Reject", eggSizeId: null, quantity: 10, notes: null },
    ])
  })

  it("parses whole positive eggs only", () => {
    expect(parseEggs("12")).toBe(12)
    expect(parseEggs("0")).toBeNull()
    expect(parseEggs("-3")).toBeNull()
    expect(parseEggs("")).toBeNull()
  })

  it("shows one base quantity as crates + loose (spec 32)", () => {
    expect(cratesText(28870)).toBe("962 cr + 10")
    expect(cratesText(60)).toBe("2 cr")
    expect(cratesText(7)).toBe("7 eggs")
  })
})
