import { describe, expect, it } from "vitest"
import { feedDraftsFrom, medDraftsFrom } from "./carry-lines"

describe("carry lines to the next day", () => {
  it("turns saved lines into editable drafts, dropping empty ones", () => {
    expect(feedDraftsFrom([
      { specificFeedUsedId: 12, totalFeedConsumed: 50 },
      { specificFeedUsedId: null, totalFeedConsumed: 10 },
      { specificFeedUsedId: 13, totalFeedConsumed: 0 },
    ])).toEqual([{ specificFeedUsedId: "12", totalFeedConsumed: "50" }])
    expect(medDraftsFrom([{ specificMedicationUsedId: 5, totalMedicationConsumed: 0.5 }]))
      .toEqual([{ specificMedicationUsedId: "5", totalMedicationConsumed: "0.5" }])
  })

  it("is empty when nothing was saved", () => {
    expect(feedDraftsFrom(null)).toEqual([])
    expect(medDraftsFrom(undefined)).toEqual([])
  })
})
