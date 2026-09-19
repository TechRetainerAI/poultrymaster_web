import { describe, expect, it } from "vitest"
import { previewCorrection } from "./correction-preview"

// The preview is the only figure on the Capital Investments screens that the
// client works out for itself, so these tests are not about the arithmetic
// being hard -- it is not -- but about it agreeing with the server that will
// actually do the write. Each case names the server rule it mirrors.

const base = {
  acquisitionCost: 130000,
  additionalCost: 0,
  residualValue: 0,
  usefulLifeMonths: 120,
  accumulatedDepreciation: 0,
  newAcquisitionCost: 13000,
}

describe("previewCorrection", () => {
  it("is the brief's own example: 130,000 typed, 13,000 meant", () => {
    const p = previewCorrection(base)!
    expect(p.next).toBe(13000)
    expect(p.difference).toBe(-117000)
    expect(p.newTotal).toBe(13000)
    expect(p.newBookValue).toBe(13000)
    expect(p.newMonthly).toBeCloseTo(108.33, 2)
  })

  it("leaves additional costs alone -- a correction is not an Add cost", () => {
    const p = previewCorrection({ ...base, acquisitionCost: 100000, additionalCost: 30000, newAcquisitionCost: 90000 })!
    // 100,000 -> 90,000 moves the total by exactly the 10,000, not by anything
    // to do with the 30,000 that was added later.
    expect(p.difference).toBe(-10000)
    expect(p.newTotal).toBe(120000)
  })

  it("never moves depreciation already posted, only what is still to come", () => {
    const p = previewCorrection({
      ...base, acquisitionCost: 120000, newAcquisitionCost: 60000,
      accumulatedDepreciation: 3000, usefulLifeMonths: 120,
    })!
    expect(p.newTotal).toBe(60000)
    // (60,000 - 0) / 120 = 500: the monthly charge halves from here on.
    expect(p.newMonthly).toBe(500)
    // Book value = total - accumulated. The 3,000 already charged still stands.
    expect(p.newBookValue).toBe(57000)
    expect(p.newRemaining).toBe(57000)
  })

  it("floors book value at the residual value, exactly as the server does", () => {
    const p = previewCorrection({
      ...base, acquisitionCost: 100000, newAcquisitionCost: 20000,
      residualValue: 15000, accumulatedDepreciation: 40000,
    })!
    // 20,000 - 40,000 would be negative; the floor is the residual value.
    expect(p.newBookValue).toBe(15000)
    expect(p.newRemaining).toBe(0)
    expect(p.overDepreciated).toBe(true)
  })

  it("flags a residual value the correction would put the cost under", () => {
    const p = previewCorrection({ ...base, residualValue: 50000, newAcquisitionCost: 40000 })!
    // The server RAISEs on this, so the dialog must refuse to submit it.
    expect(p.residualTooHigh).toBe(true)
  })

  it("does not flag a residual value the corrected cost still covers", () => {
    const p = previewCorrection({ ...base, residualValue: 5000, newAcquisitionCost: 13000 })!
    expect(p.residualTooHigh).toBe(false)
    expect(p.newDepreciable).toBe(8000)
  })

  it("counts additional costs when testing the residual value", () => {
    // The residual is compared with the TOTAL, not the acquisition alone --
    // an asset can carry its residual on the strength of what was added to it.
    const p = previewCorrection({
      ...base, acquisitionCost: 100000, additionalCost: 60000,
      residualValue: 50000, newAcquisitionCost: 10000,
    })!
    expect(p.newTotal).toBe(70000)
    expect(p.residualTooHigh).toBe(false)
  })

  it("correcting upwards raises the total and charges more per month", () => {
    const p = previewCorrection({ ...base, acquisitionCost: 13000, newAcquisitionCost: 130000 })!
    expect(p.difference).toBe(117000)
    expect(p.newTotal).toBe(130000)
    expect(p.newMonthly).toBeCloseTo(1083.33, 2)
  })

  it("has no monthly charge for an asset with no useful life yet", () => {
    const p = previewCorrection({ ...base, usefulLifeMonths: null })!
    expect(p.newMonthly).toBeNull()
  })

  it("says nothing is left to depreciate when the residual eats the whole cost", () => {
    const p = previewCorrection({ ...base, residualValue: 13000, newAcquisitionCost: 13000 })!
    expect(p.newDepreciable).toBe(0)
    expect(p.nothingLeft).toBe(true)
    expect(p.residualTooHigh).toBe(false)
  })

  it.each([
    ["a blank box", Number.NaN],
    ["zero", 0],
    ["a negative amount", -5],
  ])("previews nothing for %s -- the server refuses it anyway", (_label, amount) => {
    expect(previewCorrection({ ...base, newAcquisitionCost: amount })).toBeNull()
  })

  it("previews nothing when the amount is already what is recorded", () => {
    expect(previewCorrection({ ...base, newAcquisitionCost: 130000 })).toBeNull()
    // And within the server's own half-a-pesewa tolerance.
    expect(previewCorrection({ ...base, newAcquisitionCost: 130000.004 })).toBeNull()
    expect(previewCorrection({ ...base, newAcquisitionCost: 130000.01 })).not.toBeNull()
  })

  it("rounds to the money the server will actually store", () => {
    const p = previewCorrection({ ...base, newAcquisitionCost: 13000.456 })!
    expect(p.next).toBe(13000.46)
  })
})
