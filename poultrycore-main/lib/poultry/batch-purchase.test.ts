import { describe, expect, it } from "vitest"
import {
  SUPPLIER_TYPES, batchBalance, deriveTotalCost, emptyBatchPurchase,
  patchForCostChange, paymentStatus,
} from "./batch-purchase"

describe("deriveTotalCost", () => {
  it("multiplies the cost per chick by the birds", () => {
    expect(deriveTotalCost("2.5", "1000")).toBe("2500")
  })

  it("rounds to the penny rather than trailing float noise", () => {
    expect(deriveTotalCost("0.1", "3")).toBe("0.3")
  })

  it("stays EMPTY when there is nothing to say", () => {
    // A farm that has not told us what it paid must not be shown a confident 0.
    expect(deriveTotalCost("", "1000")).toBe("")
    expect(deriveTotalCost("2.5", "")).toBe("")
    expect(deriveTotalCost("junk", "1000")).toBe("")
  })
})

describe("patchForCostChange", () => {
  const draft = { costPerChick: "2", numberOfBirds: "1000", totalCost: "2000" }

  it("recomputes the total when the cost changes", () => {
    expect(patchForCostChange(draft, { costPerChick: "3" }))
      .toEqual({ costPerChick: "3", totalCost: "3000" })
  })

  it("recomputes the total when the bird count changes", () => {
    expect(patchForCostChange(draft, { numberOfBirds: "500" }))
      .toEqual({ numberOfBirds: "500", totalCost: "1000" })
  })

  it("does NOT wipe a hand-typed total when the cost is cleared", () => {
    // The invoice is the invoice. Clearing one input must not destroy the other.
    expect(patchForCostChange(draft, { costPerChick: "" }))
      .toEqual({ costPerChick: "" })
  })
})

describe("batchBalance", () => {
  it("is what is still owed", () => {
    expect(batchBalance("10000", "7000")).toBe(3000)
  })

  it("is never negative — overpaying is not a negative debt", () => {
    expect(batchBalance("100", "500")).toBe(0)
  })

  it("treats blank and junk as zero", () => {
    expect(batchBalance("", "")).toBe(0)
    expect(batchBalance("abc", "5")).toBe(0)
  })
})

describe("paymentStatus", () => {
  it("says nothing was costed when there is no cost", () => {
    expect(paymentStatus("", "").label).toBe("No cost set")
    expect(paymentStatus(0, 100).label).toBe("No cost set")
  })

  it("distinguishes unpaid, part paid and settled", () => {
    expect(paymentStatus(1000, 0).label).toBe("Unpaid")
    expect(paymentStatus(1000, 400).label).toBe("Part payment")
    expect(paymentStatus(1000, 1000).label).toBe("Paid in full")
    expect(paymentStatus(1000, 1200).label).toBe("Paid in full")
  })

  it("carries its own colours, so both screens badge it the same", () => {
    expect(paymentStatus(1000, 400).className).toContain("amber")
    expect(paymentStatus(1000, 0).className).toContain("red")
  })
})

describe("the shared contract", () => {
  it("offers exactly local and foreign", () => {
    expect(SUPPLIER_TYPES.map((t) => t.value)).toEqual(["local", "foreign"])
  })

  it("starts a batch as local with everything else blank", () => {
    const empty = emptyBatchPurchase()
    expect(empty.supplierType).toBe("local")
    expect(Object.entries(empty).filter(([k]) => k !== "supplierType").every(([, v]) => v === "")).toBe(true)
  })
})
