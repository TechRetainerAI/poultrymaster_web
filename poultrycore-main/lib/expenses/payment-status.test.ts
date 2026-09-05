import { describe, it, expect } from "vitest"
import {
  derivePaymentStatus,
  expenseBalance,
  amountPaidForStatus,
  requiresCashAccount,
  validateExpensePayment,
  isPayableExpense,
  expenseSourceLabel,
} from "./payment-status"

describe("derivePaymentStatus", () => {
  it("matches the SQL generated column, case for case", () => {
    expect(derivePaymentStatus(100, 100)).toBe("Paid")
    expect(derivePaymentStatus(100, 40)).toBe("PartiallyPaid")
    expect(derivePaymentStatus(100, 0)).toBe("Unpaid")
  })

  it("treats NonCash as non-cash whatever the amounts say", () => {
    expect(derivePaymentStatus(100, 0, "NonCash")).toBe("NonCash")
    expect(derivePaymentStatus(100, 100, "NonCash")).toBe("NonCash")
  })

  it("counts overpayment as Paid rather than inventing a fifth state", () => {
    expect(derivePaymentStatus(100, 150)).toBe("Paid")
  })

  it("does not fall foul of float arithmetic", () => {
    // 0.1 + 0.2 !== 0.3 in binary floating point. Paying a 0.30 bill in two
    // instalments must still read as Paid.
    expect(derivePaymentStatus(0.3, 0.1 + 0.2)).toBe("Paid")
  })
})

describe("expenseBalance", () => {
  it("never goes negative", () => {
    expect(expenseBalance(100, 150)).toBe(0)
  })

  it("is exact in minor units", () => {
    expect(expenseBalance(0.3, 0.1)).toBe(0.2)
  })
})

describe("amountPaidForStatus", () => {
  it("returns null for Paid, which is what the API reads as paid in full", () => {
    // The distinction that matters: null means "fully paid", 0 would mean "owes
    // everything". Getting this backwards turns every paid expense into a debt.
    expect(amountPaidForStatus("Paid", 500, 123)).toBeNull()
  })

  it("returns 0 for Unpaid", () => {
    expect(amountPaidForStatus("Unpaid", 500, 123)).toBe(0)
  })

  it("returns what was entered for PartiallyPaid", () => {
    expect(amountPaidForStatus("PartiallyPaid", 500, 123.45)).toBe(123.45)
  })
})

describe("requiresCashAccount", () => {
  it("is required only where money actually moved", () => {
    expect(requiresCashAccount("Paid")).toBe(true)
    expect(requiresCashAccount("PartiallyPaid")).toBe(true)
    expect(requiresCashAccount("Unpaid")).toBe(false)
  })
})

describe("validateExpensePayment", () => {
  const paid = {
    total: 1000,
    status: "Paid" as const,
    amountPaid: 0,
    paymentMethod: "Cash",
    cashAccountId: 4,
    supplierId: 9,
  }

  it("accepts a fully paid expense and resolves it to the full amount", () => {
    const v = validateExpensePayment(paid)
    expect(v.ok).toBe(true)
    expect(v.status).toBe("Paid")
    expect(v.amountPaid).toBe(1000)
    expect(v.balance).toBe(0)
  })

  it("accepts a part payment and leaves the rest owing", () => {
    const v = validateExpensePayment({ ...paid, status: "PartiallyPaid", amountPaid: 300 })
    expect(v.ok).toBe(true)
    expect(v.status).toBe("PartiallyPaid")
    expect(v.amountPaid).toBe(300)
    expect(v.balance).toBe(700)
  })

  it("accepts an unpaid expense with no cash account and no method", () => {
    const v = validateExpensePayment({
      total: 1000,
      status: "Unpaid",
      amountPaid: 0,
      supplierId: 9,
      cashAccountId: null,
      paymentMethod: null,
    })
    expect(v.ok).toBe(true)
    expect(v.balance).toBe(1000)
  })

  it("requires a cash account and a method once money has moved", () => {
    const v = validateExpensePayment({ ...paid, cashAccountId: null, paymentMethod: "" })
    expect(v.ok).toBe(false)
    expect(v.errors.map((p) => p.field)).toContain("cashAccountId")
    expect(v.errors.map((p) => p.field)).toContain("paymentMethod")
  })

  it("rejects a zero total", () => {
    const v = validateExpensePayment({ ...paid, total: 0 })
    expect(v.ok).toBe(false)
    expect(v.errors.some((p) => p.field === "amount")).toBe(true)
  })

  it("rejects paying more than the bill", () => {
    const v = validateExpensePayment({ ...paid, status: "PartiallyPaid", amountPaid: 1500 })
    expect(v.ok).toBe(false)
    expect(v.errors.some((p) => p.field === "amountPaid")).toBe(true)
  })

  it("rejects a partial payment of nothing", () => {
    const v = validateExpensePayment({ ...paid, status: "PartiallyPaid", amountPaid: 0 })
    expect(v.ok).toBe(false)
  })

  it("steers a full partial payment towards Paid instead of allowing both", () => {
    const v = validateExpensePayment({ ...paid, status: "PartiallyPaid", amountPaid: 1000 })
    expect(v.ok).toBe(false)
    expect(v.errors[0].message).toMatch(/choose "Paid"/i)
  })

  it("warns, but does not block, an unpaid expense with no supplier", () => {
    const v = validateExpensePayment({
      total: 1000,
      status: "Unpaid",
      amountPaid: 0,
      supplierId: null,
    })
    expect(v.ok).toBe(true)
    const warning = v.problems.find((p) => p.field === "supplierId")
    expect(warning?.severity).toBe("warning")
    expect(warning?.message).toMatch(/Supplier Balances/)
  })

  it("does not warn about a supplier on a fully paid expense", () => {
    const v = validateExpensePayment({ ...paid, supplierId: null })
    expect(v.problems.some((p) => p.field === "supplierId")).toBe(false)
  })

  // The rule that protects the audit: an edit may not contradict money that has
  // already moved through a supplier payment. Migration 238 raises on both.
  it("refuses to cut the total below what payments already settled", () => {
    const v = validateExpensePayment({ ...paid, total: 200, allocatedByPayments: 500 })
    expect(v.ok).toBe(false)
    expect(v.errors.some((p) => p.field === "amount")).toBe(true)
  })

  it("refuses to cut amount paid below what payments already settled", () => {
    const v = validateExpensePayment({
      ...paid,
      status: "PartiallyPaid",
      amountPaid: 100,
      allocatedByPayments: 500,
    })
    expect(v.ok).toBe(false)
    expect(v.errors.some((p) => p.field === "amountPaid")).toBe(true)
  })

  it("allows an edit that keeps at least what was already applied", () => {
    const v = validateExpensePayment({
      ...paid,
      status: "PartiallyPaid",
      amountPaid: 600,
      allocatedByPayments: 500,
    })
    expect(v.ok).toBe(true)
  })
})

describe("isPayableExpense", () => {
  it("is payable when it owes money and names a supplier", () => {
    expect(isPayableExpense({ balance: 500, paymentStatus: "Unpaid", supplierId: 3 })).toBe(true)
  })

  it("is not payable once settled", () => {
    expect(isPayableExpense({ balance: 0, paymentStatus: "Paid", supplierId: 3 })).toBe(false)
  })

  it("is not payable without a supplier — there would be nobody to pay", () => {
    expect(isPayableExpense({ balance: 500, paymentStatus: "Unpaid", supplierId: null })).toBe(false)
  })

  it("is never payable when non-cash: internal use moves stock, not money", () => {
    expect(isPayableExpense({ balance: 500, paymentStatus: "NonCash", supplierId: 3 })).toBe(false)
  })
})

describe("expenseSourceLabel", () => {
  it("calls a row with no source what it is — typed in by hand", () => {
    expect(expenseSourceLabel(null)).toBe("Manual expense")
    expect(expenseSourceLabel("")).toBe("Manual expense")
  })

  it("names the workflows that post expenses", () => {
    expect(expenseSourceLabel("PoultryInternalUsage")).toBe("Internal use")
    expect(expenseSourceLabel("PoultryRawMaterialPurchase")).toBe("Raw material purchase")
  })

  it("passes an unknown source through rather than dropping it", () => {
    expect(expenseSourceLabel("SomeFutureWorkflow")).toBe("SomeFutureWorkflow")
  })
})
