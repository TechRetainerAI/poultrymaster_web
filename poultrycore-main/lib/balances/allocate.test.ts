import { describe, expect, it } from "vitest"
import {
  agingBucket, autoAllocateOldestFirst, balanceAfter, docKey,
  totalAllocated, totalOpenBalance, validateAllocations,
  type AllocatableDocument,
} from "./allocate"

// The worked example from the spec, on both sides.
const SALES: AllocatableDocument[] = [
  { documentType: "Sale", documentId: 1, documentDate: "2026-01-10", balance: 200 },  // S001
  { documentType: "Sale", documentId: 14, documentDate: "2026-02-02", balance: 800 }, // S014
  { documentType: "Sale", documentId: 20, documentDate: "2026-03-15", balance: 250 }, // S020
]

const PURCHASES: AllocatableDocument[] = [
  { documentType: "RawMaterialPurchase", documentId: 1, documentDate: "2026-01-05", balance: 600 },
  { documentType: "RawMaterialPurchase", documentId: 8, documentDate: "2026-02-11", balance: 1500 },
  { documentType: "FlockBatch", documentId: 12, documentDate: "2026-03-01", balance: 300 },
]

describe("autoAllocateOldestFirst", () => {
  it("fills the oldest sale first, then spills into the next", () => {
    // 700 across S001/S014/S020 -> 200 / 500 / nothing.
    const result = autoAllocateOldestFirst(700, SALES)
    expect(result["Sale:1"]).toBe(200)
    expect(result["Sale:14"]).toBe(500)
    expect(result["Sale:20"]).toBeUndefined()
    expect(totalAllocated(result)).toBe(700)
  })

  it("does the same across mixed payable document types", () => {
    // 1000 across P001/P008/P012 -> 600 / 400 / nothing.
    const result = autoAllocateOldestFirst(1000, PURCHASES)
    expect(result["RawMaterialPurchase:1"]).toBe(600)
    expect(result["RawMaterialPurchase:8"]).toBe(400)
    expect(result["FlockBatch:12"]).toBeUndefined()
  })

  it("orders by date, not by the order the rows arrived in", () => {
    const shuffled = [SALES[2], SALES[0], SALES[1]]
    expect(autoAllocateOldestFirst(700, shuffled)).toEqual(autoAllocateOldestFirst(700, SALES))
  })

  it("never allocates more than a document's balance", () => {
    const result = autoAllocateOldestFirst(5000, SALES)
    expect(result["Sale:1"]).toBe(200)
    expect(result["Sale:14"]).toBe(800)
    expect(result["Sale:20"]).toBe(250)
    // 5000 offered, only 1250 owed — the surplus stays unallocated rather than
    // overpaying, because overpayment is not supported.
    expect(totalAllocated(result)).toBe(1250)
  })

  it("allocates nothing for a zero or negative amount", () => {
    expect(autoAllocateOldestFirst(0, SALES)).toEqual({})
    expect(autoAllocateOldestFirst(-50, SALES)).toEqual({})
  })

  it("skips documents that have nothing owing", () => {
    const withSettled = [...SALES, { documentType: "Sale", documentId: 2, documentDate: "2026-01-01", balance: 0 }]
    expect(autoAllocateOldestFirst(100, withSettled)["Sale:2"]).toBeUndefined()
  })

  it("splits amounts with pesewas without floating-point drift", () => {
    const docs: AllocatableDocument[] = [
      { documentType: "Sale", documentId: 1, documentDate: "2026-01-01", balance: 0.1 },
      { documentType: "Sale", documentId: 2, documentDate: "2026-01-02", balance: 0.2 },
    ]
    // 0.1 + 0.2 === 0.30000000000000004 in float, which would fail the
    // must-equal-the-payment check against a payment of 0.30.
    expect(totalAllocated(autoAllocateOldestFirst(0.3, docs))).toBe(0.3)
  })
})

describe("validateAllocations", () => {
  const alloc = { "Sale:1": 200, "Sale:14": 500 }

  it("accepts an allocation that exactly matches the payment", () => {
    const v = validateAllocations(700, SALES, alloc)
    expect(v.ok).toBe(true)
    expect(v.unallocated).toBe(0)
    expect(v.problems).toHaveLength(0)
  })

  it("rejects an under-allocated payment and says how much is left", () => {
    const v = validateAllocations(700, SALES, { "Sale:1": 200 })
    expect(v.ok).toBe(false)
    expect(v.unallocated).toBe(500)
    expect(v.problems.some((p) => p.message.includes("500.00"))).toBe(true)
  })

  it("rejects an over-allocated payment", () => {
    const v = validateAllocations(600, SALES, alloc)
    expect(v.ok).toBe(false)
    expect(v.unallocated).toBe(-100)
  })

  it("rejects applying more than a single line's balance, and flags that line", () => {
    const v = validateAllocations(5000, SALES, { "Sale:14": 5000 })
    expect(v.ok).toBe(false)
    expect(v.overAllocated["Sale:14"]).toBe(4200)
  })

  it("rejects a negative line", () => {
    const v = validateAllocations(100, SALES, { "Sale:1": -100 })
    expect(v.ok).toBe(false)
    expect(v.problems.some((p) => p.key === "Sale:1")).toBe(true)
  })

  it("rejects a zero payment", () => {
    expect(validateAllocations(0, SALES, {}).ok).toBe(false)
  })

  it("rejects a payment applied to nothing", () => {
    const v = validateAllocations(700, SALES, {})
    expect(v.ok).toBe(false)
    expect(v.problems.some((p) => p.message.includes("at least one line"))).toBe(true)
  })

  it("rejects a line for a document that is no longer open", () => {
    const v = validateAllocations(100, SALES, { "Sale:999": 100 })
    expect(v.ok).toBe(false)
    expect(v.problems.some((p) => p.message.includes("no longer open"))).toBe(true)
  })

  it("requires a cash account when the caller says one is needed", () => {
    const withAccount = validateAllocations(700, SALES, alloc, { cashAccountRequired: true, cashAccountId: 3 })
    const without = validateAllocations(700, SALES, alloc, { cashAccountRequired: true, cashAccountId: null })
    expect(withAccount.ok).toBe(true)
    expect(without.ok).toBe(false)
  })

  it("ignores zero lines rather than treating them as allocations", () => {
    const v = validateAllocations(700, SALES, { ...alloc, "Sale:20": 0 })
    expect(v.ok).toBe(true)
  })
})

describe("balanceAfter", () => {
  it("subtracts what is being applied", () => {
    expect(balanceAfter(SALES[1], { "Sale:14": 500 })).toBe(300)
  })

  it("leaves an untouched document at its full balance", () => {
    expect(balanceAfter(SALES[2], { "Sale:14": 500 })).toBe(250)
  })
})

describe("docKey", () => {
  it("separates the same id under different document types", () => {
    expect(docKey({ documentType: "RawMaterialPurchase", documentId: 12 }))
      .not.toBe(docKey({ documentType: "FlockBatch", documentId: 12 }))
  })
})

describe("totalOpenBalance", () => {
  it("sums balances exactly", () => {
    expect(totalOpenBalance(SALES)).toBe(1250)
    expect(totalOpenBalance(PURCHASES)).toBe(2400)
  })
})

describe("agingBucket", () => {
  it("buckets by age in days", () => {
    expect(agingBucket(0)).toBe("Current")
    expect(agingBucket(1)).toBe("1-30")
    expect(agingBucket(30)).toBe("1-30")
    expect(agingBucket(31)).toBe("31-60")
    expect(agingBucket(90)).toBe("61-90")
    expect(agingBucket(91)).toBe("90+")
  })
})
