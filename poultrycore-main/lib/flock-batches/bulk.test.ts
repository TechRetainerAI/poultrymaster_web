import { describe, it, expect } from "vitest"
import { generateRows, nextStartNumber, validateRows, summarize, toPayloadItems, makeCode, emptyRow } from "./bulk"

const gen = (o: Partial<Parameters<typeof generateRows>[0]> = {}) => generateRows({
  count: 3, namePrefix: "Batch", codePrefix: "B", startNumber: 6, breed: "Isa Brown",
  startDate: "2026-11-05", numberOfBirds: "1000", costPerChick: "10", amountPaid: "", ...o,
})

describe("bulk flock batches", () => {
  it("generates names and padded codes from the start number", () => {
    const rows = gen()
    expect(rows.map((r) => [r.batchName, r.batchCode])).toEqual([["Batch 6", "B006"], ["Batch 7", "B007"], ["Batch 8", "B008"]])
    expect(rows[0]).toMatchObject({ breed: "Isa Brown", startDate: "2026-11-05", numberOfBirds: "1000" })
  })

  it("continues the farm's code series", () => {
    expect(nextStartNumber("B", ["B001", "b005", "BT1", "Bnew", null])).toBe(6)
    expect(nextStartNumber("X", ["B001"])).toBe(1)
    expect(makeCode("B", 12)).toBe("B012")
  })

  it("accepts a clean batch", () => {
    expect(validateRows(gen(), ["B001"])).toEqual([])
  })

  it("rejects duplicate codes in the list and against the farm", () => {
    const rows = gen({ startNumber: 1 })
    rows[2].batchCode = " b001 "
    const errs = validateRows(rows, ["B002"])
    expect(errs.filter((e) => e.field === "batchCode").map((e) => e.index)).toEqual([1, 2])
    expect(errs.find((e) => e.index === 1)?.message).toBe('A batch with code "B002" already exists.')
    expect(errs.find((e) => e.index === 2)?.message).toBe('"b001" appears more than once in this list.')
  })

  it("requires name, birds > 0 and a start date", () => {
    const errs = validateRows([emptyRow({ batchCode: "Z1" })])
    expect(errs.map((e) => e.field).sort()).toEqual(["batchName", "numberOfBirds", "startDate"])
  })

  it("refuses paying more than the cost, and negatives", () => {
    const [a, b] = gen({ count: 2 })
    a.amountPaid = "10001"
    b.costPerChick = "-1"
    const errs = validateRows([a, b])
    expect(errs).toEqual([
      { index: 0, field: "amountPaid", message: "Amount paid cannot be more than the total cost." },
      { index: 1, field: "costPerChick", message: "Cost per chick cannot be negative." },
    ])
  })

  it("totals birds, cost and balance", () => {
    const rows = gen({ count: 2, amountPaid: "4000" })
    expect(summarize(rows)).toEqual({ count: 2, birds: 2000, totalCost: 20000, amountPaid: 8000, balance: 12000 })
  })

  it("copies the shared settings onto every row", () => {
    const items = toPayloadItems(gen({ count: 1 }), { supplierType: "foreign", supplierId: "4", poultryCashAccountId: "", status: "pending", notes: " run 1 " })
    expect(items[0]).toMatchObject({ batchCode: "B006", numberOfBirds: 1000, totalCost: 10000, supplierType: "foreign", supplierId: 4, poultryCashAccountId: null, status: "pending", notes: "run 1" })
  })
})
