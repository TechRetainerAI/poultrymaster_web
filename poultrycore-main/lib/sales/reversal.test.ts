import { describe, expect, it } from "vitest"
import type { ReversalPaymentItem } from "@/lib/api/sale"
import {
  defaultHandling, effectiveAction, matchesStatusFilter, paymentSourceLabel, restoreLabel, reversalOutcome,
} from "./reversal"

const item = (over: Partial<ReversalPaymentItem>): ReversalPaymentItem => ({
  key: "g1", paymentGroupId: "g1", paymentNumbers: "PAY-0011", source: "SaleEntry", saleGenerated: true,
  allocated: 7500, paymentTotal: 7500, paymentDate: null, paymentMethod: "Cash", cashAccountId: 1,
  cashAccountName: "Main Cash", customerId: 5, recordedAtReversal: false,
  allowed: ["KeepAsCredit", "ReversePayment"], default: "KeepAsCredit", reverseUnavailableReason: null,
  ...over,
})

describe("reversal outcome", () => {
  it("keeps a sale-generated payment as credit by default: cash unchanged", () => {
    const p = { payments: [item({})] }
    expect(reversalOutcome(p, defaultHandling(p))).toEqual({ creditCreated: 7500, cashOut: 0, cashOutByAccount: [] })
  })

  it("reverses it when chosen: Money Out on the original account", () => {
    const p = { payments: [item({})] }
    expect(reversalOutcome(p, { g1: "ReversePayment" })).toEqual({
      creditCreated: 0, cashOut: 7500, cashOutByAccount: [{ account: "Main Cash", amount: 7500 }],
    })
  })

  it("never reverses a bulk customer payment, even if asked", () => {
    const bulk = item({ key: "g2", source: "CustomerBalances", saleGenerated: false, allowed: ["KeepAsCredit"] })
    expect(effectiveAction(bulk, { g2: "ReversePayment" })).toBe("KeepAsCredit")
    expect(reversalOutcome({ payments: [bulk] }, { g2: "ReversePayment" }).cashOut).toBe(0)
  })

  it("handles each payment on its own (mixed)", () => {
    const p = {
      payments: [
        item({ key: "a", allocated: 2000 }),
        item({ key: "b", allocated: 1000, source: "CustomerBalances", saleGenerated: false, allowed: ["KeepAsCredit"] }),
        item({ key: "c", allocated: 500.5, source: "CustomerBalances", saleGenerated: false, allowed: ["KeepAsCredit"] }),
      ],
    }
    expect(reversalOutcome(p, { a: "ReversePayment" })).toMatchObject({ creditCreated: 1500.5, cashOut: 2000 })
  })

  it("a walk-in's money (no customer) defaults to being reversed", () => {
    const walkIn = item({ key: "AT-SALE", recordedAtReversal: true, customerId: null, allowed: ["ReversePayment"], default: "ReversePayment" })
    expect(effectiveAction(walkIn, {})).toBe("ReversePayment")
    expect(effectiveAction(walkIn, { "AT-SALE": "KeepAsCredit" })).toBe("ReversePayment")
    expect(paymentSourceLabel(walkIn)).toBe("Received at the sale")
  })

  it("an unpaid sale moves no money", () => {
    expect(reversalOutcome({ payments: [] }, {})).toEqual({ creditCreated: 0, cashOut: 0, cashOutByAccount: [] })
  })
})

describe("labels", () => {
  it("says what stock comes back, by class", () => {
    expect(restoreLabel({ restoreQuantity: 300, restoreUnit: "eggs", restoreProductName: "Large" })).toBe("300 eggs (Large)")
    expect(restoreLabel({ restoreQuantity: 10, restoreUnit: "birds", restoreProductName: "Birds" })).toBe("10 birds")
    expect(restoreLabel({ restoreQuantity: 0, restoreUnit: "eggs", restoreProductName: "Large" })).toBeNull()
  })

  it("names where a payment came from", () => {
    expect(paymentSourceLabel(item({}))).toBe("Paid with this sale")
    expect(paymentSourceLabel(item({ source: "CustomerBalances", saleGenerated: false }))).toBe("Customer payment")
  })
})

describe("status filter", () => {
  it("hides reversed sales from Active and every payment filter", () => {
    expect(matchesStatusFilter({ status: "Reversed" }, "Paid", "Active")).toBe(false)
    expect(matchesStatusFilter({ status: "Reversed" }, "Paid", "Paid")).toBe(false)
    expect(matchesStatusFilter({ status: "Reversed" }, "Paid", "Reversed")).toBe(true)
    expect(matchesStatusFilter({ status: "Reversed" }, "Paid", "All")).toBe(true)
  })

  it("filters active sales by payment status", () => {
    expect(matchesStatusFilter({ status: "Posted" }, "Partial", "Partial")).toBe(true)
    expect(matchesStatusFilter({}, "Pending", "Paid")).toBe(false)
    expect(matchesStatusFilter({}, "Pending", "Active")).toBe(true)
  })
})
