import { describe, expect, it } from "vitest"
import {
  IDENTITY_AND_AUDIT_FIELDS, buildRepeatPrefill, isIdentityField, latestEntry, repeatSubmitBlocker, stillUnconfirmed,
  type CopyPolicy, type RepeatContext,
} from "./repeat-previous"
import {
  expensePolicy, feedUsagePolicy, healthTypeFromNotes, internalUsePolicy, isRepeatableExpense, treatmentPolicy,
} from "./policies"

const TODAY = "2026-10-02"
const ctx = (valid: Record<string, (number | string)[]> = {}): RepeatContext => ({
  businessDate: TODAY,
  valid: Object.fromEntries(Object.entries(valid).map(([k, v]) => [k, new Set(v)])),
})

// Every key in a prefill must be either a field the policy allows or the date.
const assertNoIdentity = (values: object) => {
  for (const k of Object.keys(values)) expect(isIdentityField(k), `identity field leaked: ${k}`).toBe(false)
}

// ------------------------------------------------------------------ framework
describe("framework", () => {
  type Src = { id: number; name: string; qty: number; createdAt: string; status: string; when: string }
  type Form = { name: string; qty: number; when: string; createdAt: string; status: string; id: number }
  const p: CopyPolicy<Src, Form> = {
    formType: "t", noun: "thing", dateField: "when",
    fields: {
      name: { mode: "copy", from: (s) => s.name },
      qty: { mode: "review", from: (s) => s.qty },
      when: { mode: "copy", from: (s) => s.when },            // a policy trying to copy the date
      createdAt: { mode: "copy", from: (s) => s.createdAt },  // ... and an audit field
      status: { mode: "copy", from: (s) => s.status },        // ... and status
      id: { mode: "copy", from: (s) => s.id },                // ... and the id
    },
    describe: (s) => s.name, sourceId: (s) => s.id, sourceDate: (s) => s.when,
  }
  const src: Src = { id: 9, name: "A", qty: 5, createdAt: "2026-09-01T10:00", status: "Posted", when: "2026-10-01" }

  it("copies allowed fields and marks review fields", () => {
    const r = buildRepeatPrefill(p, src, ctx())
    expect(r.values).toMatchObject({ name: "A", qty: 5 })
    expect(r.review).toEqual(["qty"])
  })
  it("never copies identity/audit fields even when a policy asks", () => {
    const r = buildRepeatPrefill(p, src, ctx())
    expect(r.values).not.toHaveProperty("id")
    expect(r.values).not.toHaveProperty("createdAt")
    expect(r.values).not.toHaveProperty("status")
    assertNoIdentity(r.values)
  })
  it("never copies the date: it becomes the business date", () => {
    expect(buildRepeatPrefill(p, src, ctx()).values.when).toBe(TODAY)
  })
  it("keeps the source only for the banner", () => {
    expect(buildRepeatPrefill(p, src, ctx()).source).toMatchObject({ id: 9, date: "2026-10-01", noun: "thing" })
  })
  it("covers the identity list the prompt names", () => {
    for (const f of ["id", "receiptNumber", "paymentNumber", "referenceNo", "createdAt", "createdBy", "postedAt", "approvedBy", "status", "reversedAt", "reversalId"]) {
      expect(IDENTITY_AND_AUDIT_FIELDS.map((x) => x.toLowerCase())).toContain(f.toLowerCase())
    }
  })
  it("latestEntry picks the newest by date, then id", () => {
    const rows = [{ d: "2026-09-30", i: 5 }, { d: "2026-10-01", i: 2 }, { d: "2026-10-01", i: 3 }]
    expect(latestEntry(rows, (r) => r.d, (r) => r.i)).toEqual({ d: "2026-10-01", i: 3 })
    expect(latestEntry([], (r: any) => r.d, (r: any) => r.i)).toBeNull()
  })
  it("a review field stays unconfirmed until the person changes it", () => {
    const r = buildRepeatPrefill(p, src, ctx())
    expect(stillUnconfirmed(r, { qty: 5 }, "qty")).toBe(true)
    expect(stillUnconfirmed(r, { qty: 6 }, "qty")).toBe(false)
    expect(stillUnconfirmed(r, { name: "A" }, "name")).toBe(false)   // copy fields never need confirming
  })
})

// ----------------------------------------------------------------- Feed Usage
describe("feed usage policy", () => {
  const prev = { farmId: "f1", userId: "u", feedUsageId: 41, flockId: 7, usageDate: "2026-09-30T00:00:00", feedType: "Layer Feed", quantityKg: 120 }

  it("copies flock and feed, marks quantity for confirmation, dates today", () => {
    const r = buildRepeatPrefill(feedUsagePolicy, prev, ctx({ flock: [7] }))
    expect(r.values).toEqual({ flockId: "7", feedType: "Layer Feed", quantityKg: "120", usageDate: TODAY })
    expect(r.review).toEqual(["quantityKg"])
    assertNoIdentity(r.values)
  })
  it("drops a flock that has since closed or gone", () => {
    const r = buildRepeatPrefill(feedUsagePolicy, prev, ctx({ flock: [8] }))
    expect(r.values.flockId).toBeUndefined()
    expect(r.dropped[0]).toMatchObject({ field: "flockId" })
  })
  it("company isolation: a flock id from another company is not valid here", () => {
    expect(buildRepeatPrefill(feedUsagePolicy, { ...prev, flockId: 999 }, ctx({ flock: [7, 8] })).values.flockId).toBeUndefined()
  })
})

// ------------------------------------------------------------------ Treatment
describe("treatment policy", () => {
  const prev = { id: 3, flockId: 7, houseId: null, itemId: null, recordDate: "2026-09-25", vaccination: "Newcastle", medication: "Oxytet", waterConsumption: 2.5, notes: "[Type:Medication] coughing in pen 2" }

  it("medicine, treatment and dose are REVIEW — never silently repeated", () => {
    const r = buildRepeatPrefill(treatmentPolicy, prev, ctx({ flock: [7] }))
    expect(r.review.sort()).toEqual(["medication", "vaccination", "waterConsumption"])
    expect(r.values).toMatchObject({ recordType: "Medication", flockId: 7, recordDate: TODAY })
  })
  it("notes (observations) are never copied", () => {
    const r = buildRepeatPrefill(treatmentPolicy, prev, ctx({ flock: [7] }))
    expect(r.values).not.toHaveProperty("notes")
    expect(r.neverCopied.map((n) => n.field)).toContain("notes")
  })
  it("a mortality record type is never pre-set", () => {
    expect(buildRepeatPrefill(treatmentPolicy, { ...prev, notes: "[Type:Mortality] 3 dead" }, ctx({ flock: [7] })).values.recordType).toBeUndefined()
  })
  it("reads the stored record type", () => {
    expect(healthTypeFromNotes("[Type:Vaccination] x")).toBe("Vaccination")
    expect(healthTypeFromNotes("plain")).toBeNull()
  })
})

// --------------------------------------------------------------- Internal Use
describe("internal use policy", () => {
  const prev: any = {
    poultryInternalUsageId: 12, usageDate: "2026-09-29", referenceNo: "IU-0012", category: "StaffWelfare", reason: "Monthly ration",
    recipientName: "Staff", staffCount: 6, status: "Posted", totalCostValue: 300, notes: "given at gate", postedBy: "x", postedAt: "y",
    createdBy: "z", createdAt: "w",
    items: [{ poultryProductId: 4, productName: "Table eggs", entryQuantity: 6, entryUnit: "Crate", quantityPerStaff: 1, entryUnitCost: 50, unitCost: 1.67 }],
  }
  it("copies the purpose and product, marks quantities, never the cost, the reference or the status", () => {
    const r = buildRepeatPrefill(internalUsePolicy, prev, ctx({ product: [4] }))
    expect(r.values).toMatchObject({ category: "StaffWelfare", recipientName: "Staff", reason: "Monthly ration", poultryProductId: 4,
                                     entryUnit: "Crate", useStaffHelper: true, staffCount: 6, quantityPerStaff: 1, usageDate: TODAY })
    expect(r.review.sort()).toEqual(["quantityPerStaff", "staffCount"])
    expect(r.values).not.toHaveProperty("entryQuantity")   // the helper computes it
    expect(r.values).not.toHaveProperty("unitCost")
    expect(r.values).not.toHaveProperty("notes")
    expect(r.values).not.toHaveProperty("referenceNo")
    expect(r.values).not.toHaveProperty("status")
    assertNoIdentity(r.values)
  })
  it("without the staff helper, the total quantity is copied as REVIEW", () => {
    const r = buildRepeatPrefill(internalUsePolicy, { ...prev, staffCount: 0 }, ctx({ product: [4] }))
    expect(r.values).toMatchObject({ entryQuantity: 6, useStaffHelper: false })
    expect(r.review).toEqual(["entryQuantity"])
  })
  it("drops a product that has been made inactive", () => {
    const r = buildRepeatPrefill(internalUsePolicy, prev, ctx({ product: [5] }))
    expect(r.values.poultryProductId).toBeUndefined()
    expect(r.dropped.map((d) => d.field)).toEqual(["poultryProductId"])
  })
})

// ------------------------------------------------------------------- Expenses
describe("expense policy", () => {
  const prev: any = {
    expenseId: 88, expenseDate: "2026-09-01", category: "Utilities", description: "Internet", amount: 450, paymentMethod: "Mobile Money",
    flockId: 0, poultryCashAccountId: 3, supplierId: 5, amountPaid: 450, paymentStatus: "Paid", dueDate: null, createdDate: "x", sourceType: null,
  }
  const valid = ctx({ supplier: [5], cashAccount: [3], flock: [7] })

  it("default: copies only what describes the expense — never amount, cash account, paid status", () => {
    const r = buildRepeatPrefill(expensePolicy({ includeAmount: false }), prev, valid)
    expect(r.values).toEqual({ category: "Utilities", description: "Internet", paymentMethod: "Mobile Money", supplierId: "5", flockId: "ALL", expenseDate: TODAY })
    expect(r.review).toEqual([])
    expect(r.neverCopied.map((n) => n.field).sort()).toEqual(["amount", "amountPaid", "dueDate", "expenseDate", "paymentStatus", "poultryCashAccountId"])
  })
  it("explicit 'include amount': amount, cash account and paid status come as REVIEW", () => {
    const r = buildRepeatPrefill(expensePolicy({ includeAmount: true }), prev, valid)
    expect(r.values).toMatchObject({ amount: "450", poultryCashAccountId: "3", paymentStatus: "Paid" })
    expect(r.review.sort()).toEqual(["amount", "paymentStatus", "poultryCashAccountId"])
    expect(r.values).not.toHaveProperty("amountPaid")
    expect(r.values).not.toHaveProperty("dueDate")
  })
  it("drops a cash account that has been deactivated", () => {
    const r = buildRepeatPrefill(expensePolicy({ includeAmount: true }), prev, ctx({ supplier: [5], cashAccount: [9] }))
    expect(r.values.poultryCashAccountId).toBeUndefined()
    expect(r.dropped.map((d) => d.field)).toEqual(["poultryCashAccountId"])
  })
  it("keeps a flock-specific expense on its flock only while the flock is valid", () => {
    expect(buildRepeatPrefill(expensePolicy({ includeAmount: false }), { ...prev, flockId: 7 }, valid).values.flockId).toBe("7")
    expect(buildRepeatPrefill(expensePolicy({ includeAmount: false }), { ...prev, flockId: 8 }, valid).values.flockId).toBeUndefined()
  })
  it("workflow-generated expenses are not offered for repeat", () => {
    expect(isRepeatableExpense({ sourceType: "PoultryFeedConsumption" })).toBe(false)
    expect(isRepeatableExpense({ sourceType: null })).toBe(true)
  })
})

describe("submit guard", () => {
  const prev = { farmId: "f1", userId: "u", feedUsageId: 41, flockId: 7, usageDate: "2026-09-30", feedType: "Layer Feed", quantityKg: 120 }
  const r = buildRepeatPrefill(feedUsagePolicy, prev, ctx({ flock: [7] }))
  const labels = { quantityKg: "Quantity (kg)" }
  it("blocks saving while a copied quantity is unconfirmed", () => {
    expect(repeatSubmitBlocker(r, r.values, false, labels)).toMatch(/Quantity \(kg\)/)
  })
  it("editing the value confirms it", () => {
    expect(repeatSubmitBlocker(r, { ...r.values, quantityKg: "115" }, false, labels)).toBeNull()
  })
  it("ticking 'I've checked these' confirms an unchanged value", () => {
    expect(repeatSubmitBlocker(r, r.values, true, labels)).toBeNull()
  })
  it("a normal (non-repeated) form is never blocked", () => {
    expect(repeatSubmitBlocker(null, {}, false, labels)).toBeNull()
  })
})

describe("rules that changed since the previous entry", () => {
  it("a feed type no longer offered is dropped, not resubmitted", () => {
    const prev = { farmId: "f1", userId: "u", feedUsageId: 41, flockId: 7, usageDate: "2026-09-30", feedType: "Organic Feed", quantityKg: 10 }
    const r = buildRepeatPrefill(feedUsagePolicy, prev, ctx({ flock: [7], feedType: ["Layer Feed", "Grower Feed"] }))
    expect(r.values.feedType).toBeUndefined()
    expect(r.dropped.map((d) => d.field)).toEqual(["feedType"])
  })
  it("an expense category since removed is dropped", () => {
    const prev: any = { expenseId: 1, expenseDate: "2026-09-01", category: "Old Category", description: "x", amount: 1, paymentMethod: "Cash", flockId: 0, sourceType: null }
    const r = buildRepeatPrefill(expensePolicy({ includeAmount: false }), prev, ctx({ category: ["Utilities", "Feed"] }))
    expect(r.values.category).toBeUndefined()
  })
  it("building a prefill is pure: it never touches the source entry (nothing is re-posted)", () => {
    const prev = Object.freeze({ farmId: "f1", userId: "u", feedUsageId: 41, flockId: 7, usageDate: "2026-09-30", feedType: "Layer Feed", quantityKg: 10 })
    expect(() => buildRepeatPrefill(feedUsagePolicy, prev, ctx({ flock: [7] }))).not.toThrow()
    expect(prev.usageDate).toBe("2026-09-30")
  })
})
