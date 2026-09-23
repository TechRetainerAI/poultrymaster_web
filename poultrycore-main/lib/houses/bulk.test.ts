import { describe, expect, it } from "vitest"
import {
  MAX_NAME_LENGTH, MAX_ROWS,
  applyToAll, duplicateKey, emptyRow, errorsByRow, generateRows,
  parseCapacity, summarize, toPayloadItems, validateRows,
  type BulkHouseRow,
} from "./bulk"

// The worked example from the spec: 10 pens, prefix "Pen", starting at 1,
// 2,000 birds each, all in "Layer House A".
const TEN_PENS = () => generateRows({
  count: 10, prefix: "Pen", startNumber: 1, capacity: "2000", location: "Layer House A",
})

const row = (name: string, capacity = "", location = ""): BulkHouseRow => ({
  ...emptyRow(), name, capacity, location,
})

describe("generateRows", () => {
  it("generates the named series with the shared capacity and location", () => {
    const rows = TEN_PENS()
    expect(rows).toHaveLength(10)
    expect(rows[0].name).toBe("Pen 1")
    expect(rows[9].name).toBe("Pen 10")
    expect(rows.every((r) => r.capacity === "2000")).toBe(true)
    expect(rows.every((r) => r.location === "Layer House A")).toBe(true)
  })

  it("creates a single house when count is 1", () => {
    const rows = generateRows({ count: 1, prefix: "Pen", startNumber: 1, capacity: "", location: "" })
    expect(rows.map((r) => r.name)).toEqual(["Pen 1"])
  })

  it("honours a custom prefix", () => {
    const rows = generateRows({ count: 3, prefix: "Brooder House", startNumber: 1, capacity: "", location: "" })
    expect(rows.map((r) => r.name)).toEqual(["Brooder House 1", "Brooder House 2", "Brooder House 3"])
  })

  it("honours a custom starting number", () => {
    const rows = generateRows({ count: 3, prefix: "Pen", startNumber: 11, capacity: "", location: "" })
    expect(rows.map((r) => r.name)).toEqual(["Pen 11", "Pen 12", "Pen 13"])
  })

  it("numbers plainly when no prefix is given, with no leading space", () => {
    const rows = generateRows({ count: 2, prefix: "   ", startNumber: 4, capacity: "", location: "" })
    expect(rows.map((r) => r.name)).toEqual(["4", "5"])
  })

  it("never generates more than one batch's worth", () => {
    expect(generateRows({ count: 5000, prefix: "P", startNumber: 1, capacity: "", location: "" })).toHaveLength(MAX_ROWS)
  })

  it("gives every row its own key so removing one does not disturb the rest", () => {
    const ids = TEN_PENS().map((r) => r.id)
    expect(new Set(ids).size).toBe(10)
  })
})

describe("applyToAll", () => {
  it("applies one capacity across every row without touching names", () => {
    const rows = applyToAll(TEN_PENS(), { capacity: "3500" })
    expect(rows.every((r) => r.capacity === "3500")).toBe(true)
    expect(rows[0].name).toBe("Pen 1")
  })

  it("applies one location across every row", () => {
    const rows = applyToAll(TEN_PENS(), { location: "Broiler Shed B" })
    expect(rows.every((r) => r.location === "Broiler Shed B")).toBe(true)
  })
})

describe("validateRows", () => {
  it("passes a clean batch of ten", () => {
    expect(validateRows(TEN_PENS(), [])).toEqual([])
  })

  it("passes a batch of one", () => {
    expect(validateRows([row("Pen 1", "2000", "Layer House A")], [])).toEqual([])
  })

  it("accepts rows edited individually after generation", () => {
    const rows = TEN_PENS()
    rows[3] = { ...rows[3], name: "Quarantine Pen", capacity: "500", location: "Isolation Block" }
    expect(validateRows(rows, [])).toEqual([])
  })

  it("requires a name", () => {
    const errors = validateRows([row("Pen 1"), row("   ")], [])
    expect(errors).toEqual([{ index: 1, field: "houseName", message: "House name is required." }])
  })

  it("rejects a name longer than the column allows", () => {
    const errors = validateRows([row("x".repeat(MAX_NAME_LENGTH + 1))], [])
    expect(errors[0].field).toBe("houseName")
    expect(errors[0].message).toContain(String(MAX_NAME_LENGTH))
  })

  it("flags BOTH rows of a duplicate inside the batch, not just the second", () => {
    const errors = validateRows([row("Pen 1"), row("Pen 2"), row("Pen 1")], [])
    expect(errors.map((e) => e.index)).toEqual([0, 2])
    expect(errors[0].message).toBe('"Pen 1" appears more than once in this batch.')
  })

  it("treats case and spacing differences as the same name", () => {
    const errors = validateRows([row("Pen 1"), row("pen  1")], [])
    expect(errors).toHaveLength(2)
  })

  it("flags a name that already exists on the farm", () => {
    // Existing: Pen 1, Pen 2. Creating: Pen 1, Pen 3, Pen 4 -- only Pen 1 is flagged.
    const errors = validateRows([row("Pen 1"), row("Pen 3"), row("Pen 4")], ["Pen 1", "Pen 2"])
    expect(errors).toEqual([
      { index: 0, field: "houseName", message: 'A house named "Pen 1" already exists on this farm.' },
    ])
  })

  it("matches an existing house case-insensitively", () => {
    expect(validateRows([row("PEN 1")], ["Pen 1"])).toHaveLength(1)
  })

  it("rejects a negative capacity", () => {
    const errors = validateRows([row("Pen 1", "-5")], [])
    expect(errors).toEqual([{ index: 0, field: "capacity", message: "Capacity cannot be negative." }])
  })

  it("rejects a capacity that is not a whole number", () => {
    expect(validateRows([row("Pen 1", "12.5")], [])[0].message).toBe("Capacity must be a whole number.")
    expect(validateRows([row("Pen 1", "lots")], [])[0].message).toBe("Capacity must be a whole number.")
  })

  it("allows a blank capacity, because the single Add House form does", () => {
    expect(validateRows([row("Pen 1", "")], [])).toEqual([])
  })

  it("allows zero capacity", () => {
    expect(validateRows([row("Pen 1", "0")], [])).toEqual([])
  })

  it("refuses an empty batch", () => {
    expect(validateRows([], [])).toEqual([
      { index: -1, field: "houses", message: "Add at least one house before creating." },
    ])
  })

  it("refuses a batch over the row limit", () => {
    const rows = Array.from({ length: MAX_ROWS + 1 }, (_, i) => row(`Pen ${i + 1}`))
    const errors = validateRows(rows, [])
    expect(errors).toHaveLength(1)
    expect(errors[0].index).toBe(-1)
  })

  it("reports several problems at once, one per row and field", () => {
    const errors = validateRows([row("", "-1"), row("Pen 2")], [])
    expect(errors).toHaveLength(2)
    expect(errors.map((e) => e.field).sort()).toEqual(["capacity", "houseName"])
  })
})

describe("errorsByRow", () => {
  it("keys messages by row and field so a cell can render its own", () => {
    const map = errorsByRow(validateRows([row("", "-1")], []))
    expect(map[0].houseName).toBe("House name is required.")
    expect(map[0].capacity).toBe("Capacity cannot be negative.")
  })

  it("drops batch-level errors, which have no row to attach to", () => {
    expect(errorsByRow(validateRows([], []))).toEqual({})
  })
})

describe("summarize", () => {
  it("counts the houses and adds up the birds", () => {
    // 10 pens x 2,000 birds = 20,000.
    expect(summarize(TEN_PENS())).toEqual({ count: 10, totalCapacity: 20000, withoutCapacity: 0 })
  })

  it("says how many rows have no capacity so the total is not mistaken for the whole", () => {
    expect(summarize([row("Pen 1", "2000"), row("Pen 2", "")]))
      .toEqual({ count: 2, totalCapacity: 2000, withoutCapacity: 1 })
  })
})

describe("parseCapacity", () => {
  it("reads a blank box as no capacity, not as zero", () => {
    expect(parseCapacity("")).toBeNull()
    expect(parseCapacity("   ")).toBeNull()
  })

  it("reads a whole number", () => {
    expect(parseCapacity(" 2000 ")).toBe(2000)
  })

  it("refuses anything that is not a whole number", () => {
    expect(parseCapacity("2.5")).toBeUndefined()
    expect(parseCapacity("2e3")).toBeUndefined()
  })
})

describe("toPayloadItems", () => {
  it("sends the trimmed name and a null -- not an empty string -- location", () => {
    expect(toPayloadItems([row("  Pen 1  ", "2000", "   ")])).toEqual([
      { houseName: "Pen 1", capacity: 2000, location: null },
    ])
  })

  it("carries each row's own edits rather than the generated defaults", () => {
    const rows = TEN_PENS()
    rows[0] = { ...rows[0], capacity: "1500", location: "Layer House B" }
    const items = toPayloadItems(rows)
    expect(items[0]).toEqual({ houseName: "Pen 1", capacity: 1500, location: "Layer House B" })
    expect(items[1]).toEqual({ houseName: "Pen 2", capacity: 2000, location: "Layer House A" })
  })

  it("carries no company or user on a row -- those live on the envelope", () => {
    expect(Object.keys(toPayloadItems([row("Pen 1")])[0]).sort()).toEqual(["capacity", "houseName", "location"])
  })
})

describe("duplicateKey", () => {
  it("ignores case, surrounding space and repeated inner space", () => {
    expect(duplicateKey("  Pen   1 ")).toBe(duplicateKey("pen 1"))
  })
})
