import { describe, expect, it } from "vitest"
import {
  MAX_ROWS,
  availableCapacity, buildRows, canFillByCapacity, defaultFlockName, distributeEqually,
  errorsByRow, fillByCapacity, parseQuantity, summarize, toPayloadItems, totalRequested,
  validateRows,
  type AllocationRow, type HouseOccupancy,
} from "./allocation"

// The spec's worked example: batch B3, 12,000 birds, six pens.
const house = (id: number, name: string, capacity: number | null, occupied = 0): HouseOccupancy => ({
  houseId: id,
  houseName: name,
  capacity,
  occupied,
  availableCapacity: capacity && capacity > 0 ? Math.max(0, capacity - occupied) : null,
  activeFlocks: occupied > 0 ? 1 : 0,
})

const SIX_PENS: HouseOccupancy[] = [
  house(1, "Pen 1", 2500), house(2, "Pen 2", 2500), house(3, "Pen 3", 2500),
  house(4, "Pen 4", 2500), house(5, "Pen 5", 2500), house(6, "Pen 6", 2500),
]

const ctx = (over: Partial<Parameters<typeof validateRows>[1]> = {}) => ({
  availableBirds: 12000,
  houses: SIX_PENS,
  existingNames: [] as string[],
  ...over,
})

describe("defaultFlockName", () => {
  it("names a flock after the batch and the pen", () => {
    expect(defaultFlockName("B3", "Pen 1")).toBe("B3 - Pen 1")
  })

  it("does not leave a dangling separator when one side is missing", () => {
    expect(defaultFlockName("", "Pen 1")).toBe("Pen 1")
    expect(defaultFlockName("B3", "")).toBe("B3")
  })
})

describe("buildRows", () => {
  it("makes one row per selected house, pre-named, with no birds yet", () => {
    const rows = buildRows("B3", SIX_PENS)
    expect(rows).toHaveLength(6)
    expect(rows.map((r) => r.name)).toEqual([
      "B3 - Pen 1", "B3 - Pen 2", "B3 - Pen 3", "B3 - Pen 4", "B3 - Pen 5", "B3 - Pen 6",
    ])
    expect(rows.every((r) => r.quantity === "")).toBe(true)
    expect(new Set(rows.map((r) => r.id)).size).toBe(6)
  })
})

describe("distributeEqually", () => {
  it("splits 12,000 across six pens as 2,000 each", () => {
    const { rows, base, remainder } = distributeEqually(12000, buildRows("B3", SIX_PENS))
    expect(base).toBe(2000)
    expect(remainder).toBe(0)
    expect(rows.map((r) => r.quantity)).toEqual(["2000", "2000", "2000", "2000", "2000", "2000"])
  })

  it("gives the remainder to the first pens and loses nothing", () => {
    // The spec's awkward case: 10,003 birds across 5 pens.
    const pens = buildRows("B3", SIX_PENS.slice(0, 5))
    const { rows, base, remainder } = distributeEqually(10003, pens)
    expect(base).toBe(2000)
    expect(remainder).toBe(3)
    expect(rows.map((r) => r.quantity)).toEqual(["2001", "2001", "2001", "2000", "2000"])
    expect(totalRequested(rows)).toBe(10003)
  })

  it("is deterministic — the same input always splits the same way", () => {
    const pens = buildRows("B3", SIX_PENS.slice(0, 5))
    expect(distributeEqually(10003, pens).rows.map((r) => r.quantity))
      .toEqual(distributeEqually(10003, pens).rows.map((r) => r.quantity))
  })

  it("handles one pen taking the whole batch", () => {
    const { rows } = distributeEqually(12000, buildRows("B3", SIX_PENS.slice(0, 1)))
    expect(rows[0].quantity).toBe("12000")
  })

  it("handles more pens than birds without going negative", () => {
    const { rows, base, remainder } = distributeEqually(3, buildRows("B3", SIX_PENS))
    expect(base).toBe(0)
    expect(remainder).toBe(3)
    expect(rows.map((r) => r.quantity)).toEqual(["1", "1", "1", "0", "0", "0"])
  })

  it("clears the grid when there is nothing left to allocate", () => {
    const { rows } = distributeEqually(0, buildRows("B3", SIX_PENS))
    expect(rows.every((r) => r.quantity === "")).toBe(true)
  })
})

describe("fillByCapacity", () => {
  it("fills each pen to its remaining capacity until the birds run out", () => {
    const houses = [house(1, "Pen 1", 2000), house(2, "Pen 2", 2000), house(3, "Pen 3", 2000)]
    const rows = fillByCapacity(5000, buildRows("B3", houses), houses)
    expect(rows.map((r) => r.quantity)).toEqual(["2000", "2000", "1000"])
  })

  it("respects what a pen already holds", () => {
    // Pen 1 holds 1,500 of 2,000, so only 500 more will fit.
    const houses = [house(1, "Pen 1", 2000, 1500), house(2, "Pen 2", 2000)]
    const rows = fillByCapacity(3000, buildRows("B3", houses), houses)
    expect(rows.map((r) => r.quantity)).toEqual(["500", "2000"])
  })

  it("leaves later pens empty once the birds are gone", () => {
    const houses = [house(1, "Pen 1", 2000), house(2, "Pen 2", 2000)]
    const rows = fillByCapacity(1200, buildRows("B3", houses), houses)
    expect(rows.map((r) => r.quantity)).toEqual(["1200", ""])
  })

  it("proposes nothing for a pen with no capacity recorded", () => {
    const houses = [house(1, "Pen 1", null), house(2, "Pen 2", 2000)]
    const rows = fillByCapacity(3000, buildRows("B3", houses), houses)
    expect(rows.map((r) => r.quantity)).toEqual(["", "2000"])
  })
})

describe("canFillByCapacity", () => {
  it("is available when every selected pen has a capacity", () => {
    expect(canFillByCapacity(buildRows("B3", SIX_PENS), SIX_PENS)).toBe(true)
  })

  it("is unavailable when capacity information is incomplete", () => {
    const houses = [house(1, "Pen 1", null), house(2, "Pen 2", 2000)]
    expect(canFillByCapacity(buildRows("B3", houses), houses)).toBe(false)
  })

  it("is unavailable with no rows", () => {
    expect(canFillByCapacity([], SIX_PENS)).toBe(false)
  })
})

describe("availableCapacity", () => {
  it("subtracts what the pen already holds", () => {
    expect(availableCapacity({ capacity: 2000, occupied: 1500 })).toBe(500)
  })

  it("treats a pen with no capacity as unconstrained, not as full", () => {
    expect(availableCapacity({ capacity: null, occupied: 0 })).toBeNull()
    expect(availableCapacity({ capacity: 0, occupied: 0 })).toBeNull()
  })

  it("never goes negative on an over-full pen", () => {
    expect(availableCapacity({ capacity: 2000, occupied: 2500 })).toBe(0)
  })
})

describe("validateRows", () => {
  const filled = (quantities: number[], houses = SIX_PENS): AllocationRow[] =>
    buildRows("B3", houses.slice(0, quantities.length)).map((r, i) => ({ ...r, quantity: String(quantities[i]) }))

  it("accepts one flock", () => {
    expect(validateRows(filled([2000]), ctx())).toEqual([])
  })

  it("accepts six flocks that use the whole batch", () => {
    expect(validateRows(filled([2000, 2000, 2000, 2000, 2000, 2000]), ctx())).toEqual([])
  })

  it("accepts fifty flocks", () => {
    const houses = Array.from({ length: 50 }, (_, i) => house(i + 1, `Pen ${i + 1}`, 500))
    const rows = buildRows("B3", houses).map((r) => ({ ...r, quantity: "200" }))
    expect(validateRows(rows, ctx({ houses, availableBirds: 12000 }))).toEqual([])
  })

  it("accepts a partial allocation and does not demand the whole batch", () => {
    // 8,000 of 12,000. The rest stays available for later.
    expect(validateRows(filled([2000, 2000, 2000, 2000]), ctx())).toEqual([])
  })

  it("accepts a later allocation of what is left", () => {
    // 8,000 already placed, 4,000 available, two more pens of 2,000.
    expect(validateRows(filled([2000, 2000]), ctx({ availableBirds: 4000 }))).toEqual([])
  })

  it("refuses an allocation bigger than the batch has left", () => {
    const errors = validateRows(filled([2000, 2000, 2000]), ctx({ availableBirds: 4000 }))
    expect(errors).toHaveLength(1)
    expect(errors[0].index).toBe(-1)
    expect(errors[0].message).toContain("only has 4,000 left")
  })

  it("refuses to exceed a pen's capacity", () => {
    const houses = [house(1, "Pen 1", 2000)]
    const errors = validateRows(filled([2500], houses), ctx({ houses }))
    expect(errors).toHaveLength(1)
    expect(errors[0].field).toBe("quantity")
    expect(errors[0].message).toContain("2,000 will fit")
  })

  it("counts what an occupied pen already holds against its capacity", () => {
    // Pen 1: capacity 2,000, holds 1,500 — only 500 will fit.
    const houses = [house(1, "Pen 1", 2000, 1500)]
    const errors = validateRows(filled([1000], houses), ctx({ houses }))
    expect(errors[0].message).toContain("already holds 1,500")
    expect(errors[0].message).toContain("500 will fit")
  })

  it("allows a second flock into an occupied pen that still has room", () => {
    const houses = [house(1, "Pen 1", 2000, 1500)]
    expect(validateRows(filled([500], houses), ctx({ houses }))).toEqual([])
  })

  it("aggregates two rows into the same pen before checking capacity", () => {
    // Neither row exceeds 2,000 alone; together they do.
    const houses = [house(1, "Pen 1", 2000)]
    const rows = buildRows("B3", houses).concat(buildRows("B3", houses))
    rows[0] = { ...rows[0], quantity: "1500", name: "B3 - Pen 1 (a)" }
    rows[1] = { ...rows[1], quantity: "1500", name: "B3 - Pen 1 (b)" }
    const errors = validateRows(rows, ctx({ houses }))
    expect(errors.filter((e) => e.field === "quantity")).toHaveLength(2)
  })

  it("leaves a pen with no capacity recorded unconstrained", () => {
    const houses = [house(1, "Pen 1", null)]
    expect(validateRows(filled([9000], houses), ctx({ houses }))).toEqual([])
  })

  it("requires a quantity above zero", () => {
    const errors = validateRows(filled([2000, 0]), ctx())
    expect(errors).toEqual([
      { index: 1, field: "quantity", message: "Enter how many birds go into this house — more than zero." },
    ])
  })

  it("requires a flock name", () => {
    const rows = filled([2000]).map((r) => ({ ...r, name: "  " }))
    expect(validateRows(rows, ctx())[0]).toEqual({ index: 0, field: "name", message: "Flock name is required." })
  })

  it("flags BOTH rows of a duplicate name, not just the second", () => {
    const rows = filled([1000, 1000]).map((r) => ({ ...r, name: "B3 - Pen 1" }))
    const errors = validateRows(rows, ctx())
    expect(errors.map((e) => e.index)).toEqual([0, 1])
    expect(errors[0].message).toBe('"B3 - Pen 1" appears more than once in this allocation.')
  })

  it("flags a flock name that already exists on the farm", () => {
    const errors = validateRows(filled([2000]), ctx({ existingNames: ["b3 - pen 1"] }))
    expect(errors).toEqual([
      { index: 0, field: "name", message: 'A flock named "B3 - Pen 1" already exists on this farm.' },
    ])
  })

  it("rejects a house that is not on this farm", () => {
    // A house id the context never offered — a deleted pen, or another company's.
    const rows = filled([2000]).map((r) => ({ ...r, houseId: 9999 }))
    const errors = validateRows(rows, ctx())
    expect(errors).toEqual([
      { index: 0, field: "houseId", message: "That house/pen is not available on this farm." },
    ])
  })

  it("requires a house to be chosen", () => {
    const rows = filled([2000]).map((r) => ({ ...r, houseId: 0 }))
    expect(errors(rows).houseId).toBe("Choose a house/pen for this flock.")
  })

  it("refuses an empty allocation", () => {
    expect(validateRows([], ctx())).toEqual([
      { index: -1, field: "allocations", message: "Add at least one house before creating flocks." },
    ])
  })

  it("refuses an allocation over the row limit", () => {
    const houses = Array.from({ length: MAX_ROWS + 1 }, (_, i) => house(i + 1, `Pen ${i + 1}`, null))
    const rows = buildRows("B3", houses).map((r) => ({ ...r, quantity: "1" }))
    const result = validateRows(rows, ctx({ houses, availableBirds: 1_000_000 }))
    expect(result).toHaveLength(1)
    expect(result[0].index).toBe(-1)
  })

  const errors = (rows: AllocationRow[]) => errorsByRow(validateRows(rows, ctx()))[0] ?? {}
})

describe("summarize", () => {
  it("reports the whole picture while typing", () => {
    const rows = distributeEqually(12000, buildRows("B3", SIX_PENS)).rows
    expect(summarize(rows, 12000, 0)).toEqual({
      batchBirds: 12000,
      previouslyAllocated: 0,
      thisAllocation: 12000,
      remaining: 0,
      overAllocated: false,
      flockCount: 6,
    })
  })

  it("shows what stays unallocated after a partial allocation", () => {
    const rows = buildRows("B3", SIX_PENS.slice(0, 4)).map((r) => ({ ...r, quantity: "2000" }))
    const totals = summarize(rows, 12000, 0)
    expect(totals.thisAllocation).toBe(8000)
    expect(totals.remaining).toBe(4000)
  })

  it("counts birds allocated earlier against what is left", () => {
    const rows = buildRows("B3", SIX_PENS.slice(0, 2)).map((r) => ({ ...r, quantity: "2000" }))
    expect(summarize(rows, 12000, 8000)).toMatchObject({ thisAllocation: 4000, remaining: 0, overAllocated: false })
  })

  it("flags an over-allocation instead of quietly clamping it", () => {
    const rows = buildRows("B3", SIX_PENS.slice(0, 3)).map((r) => ({ ...r, quantity: "2000" }))
    expect(summarize(rows, 12000, 8000)).toMatchObject({ thisAllocation: 6000, remaining: 0, overAllocated: true })
  })
})

describe("parseQuantity", () => {
  it("reads an empty box as zero rather than as a guess", () => {
    expect(parseQuantity("")).toBe(0)
  })

  it("refuses anything that is not a whole number", () => {
    expect(parseQuantity("2.5")).toBeUndefined()
    expect(parseQuantity("many")).toBeUndefined()
  })
})

describe("toPayloadItems", () => {
  it("sends the house, the trimmed name and the number", () => {
    const rows = buildRows("B3", SIX_PENS.slice(0, 1)).map((r) => ({ ...r, name: "  B3 - Pen 1  ", quantity: "2000" }))
    expect(toPayloadItems(rows)).toEqual([{ houseId: 1, name: "B3 - Pen 1", quantity: 2000 }])
  })

  it("carries no company or batch on a row — those live on the envelope", () => {
    const rows = buildRows("B3", SIX_PENS.slice(0, 1)).map((r) => ({ ...r, quantity: "1" }))
    expect(Object.keys(toPayloadItems(rows)[0]).sort()).toEqual(["houseId", "name", "quantity"])
  })
})
