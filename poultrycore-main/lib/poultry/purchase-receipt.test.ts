import { describe, expect, it } from "vitest"
import {
  allocateAdditionalCents, allocatePaymentCents, lineSubtotalCents, paymentStatusFor,
  previewReceipt, toCents, validateReceipt, type ReceiptLineDraft,
} from "./purchase-receipt"
import { EXPENSE_WHEN_CONSUMED, EXPENSE_WHEN_PURCHASED } from "./cost-recognition"

const ewp = (quantity: number, unitCost: number, extra: Partial<ReceiptLineDraft> = {}): ReceiptLineDraft =>
  ({ itemId: 1, quantity, unitCost, method: EXPENSE_WHEN_PURCHASED, ...extra })
const ewc = (quantity: number, unitCost: number, extra: Partial<ReceiptLineDraft> = {}): ReceiptLineDraft =>
  ({ itemId: 2, quantity, unitCost, method: EXPENSE_WHEN_CONSUMED, ...extra })

describe("toCents", () => {
  it("rounds half away from zero, like Postgres round(numeric, 2)", () => {
    expect(toCents(1.005)).toBe(101)
    expect(toCents(0.1 + 0.2)).toBe(30)
    expect(toCents(-1.005)).toBe(-101)
  })
  it("treats junk as nothing", () => {
    expect(toCents(Number.NaN)).toBe(0)
  })
})

describe("lineSubtotalCents", () => {
  it("is quantity x unit cost to the pesewa", () => {
    expect(lineSubtotalCents(3, 33.33)).toBe(9999)
    expect(lineSubtotalCents(1.255, 10)).toBe(1255)
  })
})

describe("allocateAdditionalCents", () => {
  it("spreads by value (the DB test F1: 100 over 1000 and 3000 -> 25 / 75)", () => {
    expect(allocateAdditionalCents([{ subtotalCents: 100000, quantity: 10 }, { subtotalCents: 300000, quantity: 30 }], 10000))
      .toEqual([2500, 7500])
  })
  it("gives the rounding pennies to the LAST line (F5: 0.10 over three -> 3/3/4)", () => {
    const three = [1, 2, 3].map(() => ({ subtotalCents: 100, quantity: 1 }))
    expect(allocateAdditionalCents(three, 10)).toEqual([3, 3, 4])
  })
  it("always sums to exactly the additional cost", () => {
    const lines = [{ subtotalCents: 333, quantity: 1 }, { subtotalCents: 333, quantity: 1 }, { subtotalCents: 334, quantity: 1 }]
    for (const add of [1, 7, 99, 1001, 123457]) {
      expect(allocateAdditionalCents(lines, add).reduce((a, b) => a + b, 0)).toBe(add)
    }
  })
  it("falls back to quantity when every line is free (F6: 40 over 1 and 3 -> 10 / 30)", () => {
    expect(allocateAdditionalCents([{ subtotalCents: 0, quantity: 1 }, { subtotalCents: 0, quantity: 3 }], 4000))
      .toEqual([1000, 3000])
  })
  it("allocates nothing when there is nothing to allocate", () => {
    expect(allocateAdditionalCents([{ subtotalCents: 100, quantity: 1 }], 0)).toEqual([0])
    expect(allocateAdditionalCents([], 500)).toEqual([])
  })
})

describe("allocatePaymentCents", () => {
  it("fills line 1 before line 2 (DB test E1: 500 over 300 + 700 -> 300 / 200)", () => {
    expect(allocatePaymentCents([30000, 70000], 50000)).toEqual([30000, 20000])
  })
  it("never exceeds a line, and skips free lines", () => {
    expect(allocatePaymentCents([0, 1000, 500], 1200)).toEqual([0, 1000, 200])
  })
})

describe("paymentStatusFor", () => {
  it("names the three states", () => {
    expect(paymentStatusFor(1000, 0)).toBe("Unpaid")
    expect(paymentStatusFor(1000, 400)).toBe("Part paid")
    expect(paymentStatusFor(1000, 1000)).toBe("Paid")
  })
})

describe("previewReceipt — the posting matrix", () => {
  it("PAID, expensed as paid: stock +, cash -, expense = paid, nothing payable", () => {
    const p = previewReceipt([ewp(10, 100)], 0, 1000)
    expect(p).toMatchObject({
      total: 1000, paid: 1000, balance: 0, status: "Paid",
      inventoryIncrease: 1000, cashOut: 1000, payableIncrease: 0, expenseNow: 1000,
      deferredToConsumption: 0, expenseWhenBalancePaid: 0,
    })
  })

  it("PAID, expensed when used: cash moves, NO expense now", () => {
    const p = previewReceipt([ewc(200, 10)], 0, 2000)
    expect(p).toMatchObject({ cashOut: 2000, payableIncrease: 0, expenseNow: 0, deferredToConsumption: 2000 })
  })

  it("CREDIT: payable = total, no cash, no expense", () => {
    const p = previewReceipt([ewp(5, 100)], 0, 0)
    expect(p).toMatchObject({ status: "Unpaid", cashOut: 0, payableIncrease: 500, expenseNow: 0, expenseWhenBalancePaid: 500 })
  })

  it("PART PAYMENT — GHS 10,000 / 4,000 / 6,000", () => {
    const p = previewReceipt([ewp(100, 100)], 0, 4000)
    expect(p).toMatchObject({
      total: 10000, paid: 4000, balance: 6000, status: "Part paid",
      cashOut: 4000, payableIncrease: 6000, expenseNow: 4000, expenseWhenBalancePaid: 6000,
    })
  })

  it("MIXED invoice part paid: only the expensed-as-paid line's paid part reaches the P&L", () => {
    const p = previewReceipt([ewp(3, 100), ewc(70, 10)], 0, 500)
    expect(p.lines.map((l) => l.paidNow)).toEqual([300, 200])
    expect(p).toMatchObject({ expenseNow: 300, deferredToConsumption: 700, cashOut: 500, payableIncrease: 500 })
  })

  it("never counts a cedi twice: cash = expense-now + paid-on-deferred, inventory = total", () => {
    const p = previewReceipt([ewp(3, 100), ewc(70, 10), ewp(2, 55.55)], 12.34, 777.77)
    const paidOnDeferred = p.lines.filter((l) => l.deferred).reduce((s, l) => s + l.paidNow, 0)
    expect(toCents(p.cashOut)).toBe(toCents(p.expenseNow + paidOnDeferred))
    expect(toCents(p.inventoryIncrease)).toBe(toCents(p.lines.reduce((s, l) => s + l.total, 0)))
    expect(toCents(p.payableIncrease + p.cashOut)).toBe(toCents(p.total))
  })

  it("lands additional costs on the lines and prices the lot at the landed cost (F2/F3)", () => {
    const p = previewReceipt([ewp(10, 100), ewp(30, 100)], 100, 0)
    expect(p.lines.map((l) => l.total)).toEqual([1025, 3075])
    expect(p.lines.map((l) => l.landedUnitCost)).toEqual([102.5, 102.5])
    expect(p.total).toBe(4100)
  })

  it("keeps the invoice unit cost exactly when nothing is added", () => {
    expect(previewReceipt([ewp(3, 33.333)], 0, 0).lines[0].landedUnitCost).toBe(33.333)
  })

  it("converts purchase units to production units (2 bags x 25 kg = 50)", () => {
    expect(previewReceipt([ewp(2, 50, { unitsPerPurchaseUnit: 25 })], 0, 0).lines[0].productionQuantity).toBe(50)
  })

  it("caps an overpayment at the total rather than inventing a credit", () => {
    expect(previewReceipt([ewp(1, 10)], 0, 11).paid).toBe(10)
  })
})

describe("validateReceipt", () => {
  const base = {
    supplierChosen: true, purchaseDate: "2026-09-28", today: "2026-10-01",
    lines: [ewp(1, 10)], additionalCosts: 0, amountPaid: 0, cashAccountId: null,
  }

  it("accepts a sound credit receipt", () => {
    expect(validateReceipt(base)).toEqual([])
  })
  it("refuses the same things the database refuses, in the same words", () => {
    expect(validateReceipt({ ...base, supplierChosen: false })).toContain("Choose the supplier you bought from.")
    expect(validateReceipt({ ...base, purchaseDate: "2026-10-02" })[0]).toMatch(/in the future/)
    expect(validateReceipt({ ...base, lines: [] })).toContain("Add at least one item to the receipt.")
    expect(validateReceipt({ ...base, lines: [ewp(0, 10)] })).toContain("Line 1: quantity must be greater than 0.")
    expect(validateReceipt({ ...base, lines: [ewp(1.2345, 10)] })).toContain("Line 1: quantity can have at most 3 decimal places.")
    expect(validateReceipt({ ...base, lines: [{ ...ewp(1, 10), itemId: null }] })).toContain("Line 1: choose an item.")
    expect(validateReceipt({ ...base, amountPaid: 11, cashAccountId: 1 })[0]).toMatch(/more than the purchase total/)
    expect(validateReceipt({ ...base, amountPaid: 5 })).toContain("Choose the cash account the payment came from.")
    expect(validateReceipt({ ...base, dueDate: "2026-09-01" })[0]).toMatch(/due date/)
  })
  it("ignores the due date once the receipt is paid in full", () => {
    expect(validateReceipt({ ...base, amountPaid: 10, cashAccountId: 1, dueDate: "2026-09-01" })).toEqual([])
  })
})
