import { describe, expect, it } from "vitest"
import { lineRemoves, previewBatchReconciliation, previewFlockHistory, saleValue } from "./bird-reconciliation"

describe("saleValue", () => {
  it("values 2,000 birds at 45 as 90,000, fully paid", () => {
    const v = saleValue({ kind: "Sale", quantity: 2000, pricePerBird: 45, amountReceived: 90000 })
    expect(v).toMatchObject({ total: 90000, received: 90000, owed: 0, treatment: "HistoricalPaid", problem: null })
  })
  it("keeps the unpaid part as a receivable only when asked", () => {
    const tracked = saleValue({ kind: "Sale", quantity: 2000, pricePerBird: 45, amountReceived: 60000, createReceivable: true, customerId: 7 })
    expect(tracked).toMatchObject({ owed: 30000, treatment: "HistoricalReceivable", problem: null })
    const untracked = saleValue({ kind: "Sale", quantity: 2000, pricePerBird: 45, amountReceived: 60000 })
    expect(untracked.treatment).toBe("HistoricalUnpaidNotTracked")
  })
  it("needs a customer for a receivable", () => {
    expect(saleValue({ kind: "Sale", quantity: 10, pricePerBird: 5, amountReceived: 0, createReceivable: true }).problem).toMatch(/customer/)
  })
  it("is exact with decimal prices", () => {
    expect(saleValue({ kind: "Sale", quantity: 3, pricePerBird: 0.1, amountReceived: 0.3 }).total).toBe(0.3)
    expect(saleValue({ kind: "Sale", quantity: 2000, pricePerBird: 45.1 }).total).toBe(90200)
  })
  it("never invents a price", () => {
    expect(saleValue({ kind: "Sale", quantity: 10 }).problem).toMatch(/price/)
    expect(saleValue({ kind: "Sale", quantity: 10, valueUnknown: true })).toMatchObject({ total: null, treatment: "QuantityOnly", problem: null })
  })
  it("rejects more received than the sale was worth", () => {
    expect(saleValue({ kind: "Sale", quantity: 10, pricePerBird: 5, amountReceived: 60 }).problem).toMatch(/between/)
  })
})

describe("lineRemoves", () => {
  it("a sale valued from a flock moves no bird from the batch pool", () => {
    expect(lineRemoves({ kind: "Sale", quantity: 100, flockId: 4 })).toBe(0)
  })
  it("a stock correction can add birds back", () => {
    expect(lineRemoves({ kind: "StockCorrection", quantity: 20, direction: "Increase" })).toBe(-20)
    expect(lineRemoves({ kind: "StockCorrection", quantity: 20 })).toBe(20)
  })
})

describe("previewBatchReconciliation", () => {
  it("16,000 bought, 6,500 placed, three sales at different prices", () => {
    const p = previewBatchReconciliation(9500, [
      { kind: "Sale", quantity: 2000, pricePerBird: 40, amountReceived: 80000 },
      { kind: "Sale", quantity: 3000, pricePerBird: 45, amountReceived: 135000 },
      { kind: "Sale", quantity: 2000, pricePerBird: 50, amountReceived: 100000 },
      { kind: "Mortality", quantity: 2000 },
      { kind: "TransferOut", quantity: 500 },
    ], 0)
    expect(p.saleBirds).toBe(7000)
    expect(p.saleValue).toBe(315000)
    expect(p.unexplained).toBe(0)
    expect(p.status).toBe("Reconciled")
  })
  it("live unplaced birds are a legitimate outcome, not a gap", () => {
    const p = previewBatchReconciliation(9500, [{ kind: "Sale", quantity: 7000, valueUnknown: true }, { kind: "Mortality", quantity: 1000 }], 1500)
    expect(p).toMatchObject({ poolAfter: 1500, unexplained: 0, status: "Reconciled" })
  })
  it("what is not explained stays unexplained", () => {
    const p = previewBatchReconciliation(9500, [{ kind: "Mortality", quantity: 1000 }], 0)
    expect(p).toMatchObject({ unexplained: 8500, status: "Unexplained" })
  })
  it("refuses taking out more than the pool", () => {
    const p = previewBatchReconciliation(100, [{ kind: "Mortality", quantity: 200 }], 0)
    expect(p.status).toBe("Invalid")
  })
  it("Other needs a note", () => {
    expect(previewBatchReconciliation(10, [{ kind: "Other", quantity: 5 }], 5).problems[0]).toMatch(/note/)
  })
})

describe("previewFlockHistory", () => {
  it("1,500 placed, 1,350 remaining, 150 explained", () => {
    const p = previewFlockHistory({ originallyPlaced: 1500, currentLiveBirds: 1350, historyKnown: true,
      historicalMortality: 100, historicalSold: 30, historicalCulled: 20, historicalTransferred: 0 })
    expect(p).toMatchObject({ difference: 150, stated: 150, other: 0, problem: null })
  })
  it("the unexplained part is other, never mortality", () => {
    const p = previewFlockHistory({ originallyPlaced: 1500, currentLiveBirds: 1350, historyKnown: true,
      historicalMortality: 100, historicalSold: "", historicalCulled: "", historicalTransferred: "" })
    expect(p.other).toBe(50)
  })
  it("unknown history puts everything in other", () => {
    const p = previewFlockHistory({ originallyPlaced: 1500, currentLiveBirds: 1350, historyKnown: false,
      historicalMortality: 100, historicalSold: 0, historicalCulled: 0, historicalTransferred: 0 })
    expect(p).toMatchObject({ stated: 0, other: 150 })
  })
  it("more birds now than placed needs a documented increase", () => {
    expect(previewFlockHistory({ originallyPlaced: 100, currentLiveBirds: 120, historyKnown: true,
      historicalMortality: 0, historicalSold: 0, historicalCulled: 0, historicalTransferred: 0 }).problem).toMatch(/more than were placed/)
  })
  it("over-explained is refused", () => {
    expect(previewFlockHistory({ originallyPlaced: 100, currentLiveBirds: 90, historyKnown: true,
      historicalMortality: 20, historicalSold: 0, historicalCulled: 0, historicalTransferred: 0 }).problem).toMatch(/add up/)
  })
})
