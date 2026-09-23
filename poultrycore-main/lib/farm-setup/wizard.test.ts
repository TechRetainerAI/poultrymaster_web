import { describe, expect, it } from "vitest"
import {
  MAX_BATCHES, MAX_FLOCKS,
  batchRowFromExisting, breakdown, defaultFlockName, deriveStartDate, duplicateKey,
  emptyBatch, emptyFlock, emptyHouse, errorsBySection, flocksNeedingReconciliation, generateBatches,
  historicalReduction, houseRowFromExisting, parseCount, resolveStartDate, summarize,
  toRequest, validateSetup,
  type BatchRow, type FlockRow, type HouseRow, type SetupContext, type SetupDraft,
} from "./wizard"

const BUSINESS_DATE = "2026-07-11"

const context = (over: Partial<SetupContext> = {}): SetupContext => ({
  existingBatches: [],
  existingHouses: [],
  existingFlockNames: [],
  allocatedByBatchId: {},
  businessDate: BUSINESS_DATE,
  ...over,
})

const batch = (over: Partial<BatchRow> = {}): BatchRow => ({
  ...emptyBatch(),
  batchName: "B1", batchCode: "B001", breed: "Brown",
  numberOfBirds: "6000", startDate: "2025-07-05",
  ...over,
})

const house = (over: Partial<HouseRow> = {}): HouseRow => ({
  ...emptyHouse(), houseName: "Pen 1", capacity: "5000", location: "Layer House A", ...over,
})

const flock = (batchKey: string, houseKey: string, over: Partial<FlockRow> = {}): FlockRow => ({
  ...emptyFlock(batchKey, houseKey),
  name: "B1 - Pen 1", originallyPlaced: "1000", currentLiveBirds: "919",
  ageMode: "date", startDate: "2025-07-05",
  ...over,
})

/**
 * The regression scenario from the spec: two batches totalling 8,200 birds
 * originally placed across eight flocks, 7,518 standing today, 682 gone before
 * the farm ever opened the application.
 */
function regressionDraft(): SetupDraft {
  const b1 = batch({ batchName: "B1", batchCode: "B001", numberOfBirds: "4000" })
  const b2 = batch({ batchName: "B2", batchCode: "B002", numberOfBirds: "4200", breed: "White" })
  const houses = Array.from({ length: 8 }, (_, i) =>
    house({ houseName: `Pen ${i + 1}`, capacity: "2000" }))

  // 4 flocks per batch. Placed 1,025 each = 8,200. Standing 939/940 = 7,518.
  const placed = [1000, 1000, 1000, 1000, 1050, 1050, 1050, 1050]
  const live = [919, 919, 919, 919, 961, 960, 961, 960]
  const flocks = houses.map((h, i) =>
    flock(i < 4 ? b1.key : b2.key, h.key, {
      name: `${i < 4 ? "B1" : "B2"} - Pen ${i + 1}`,
      originallyPlaced: String(placed[i]),
      currentLiveBirds: String(live[i]),
    }))

  return { mode: "existing", batches: [b1, b2], houses, flocks }
}

describe("the regression scenario", () => {
  it("adds up to 8,200 placed, 7,518 standing and 682 unaccounted for", () => {
    const totals = summarize(regressionDraft())
    expect(totals.flockCount).toBe(8)
    expect(totals.originallyPlaced).toBe(8200)
    expect(totals.openingLiveBirds).toBe(7518)
    expect(totals.historicalReduction).toBe(682)
  })

  it("records the whole 682 as UNKNOWN, not as mortality, when the farm cannot say", () => {
    const totals = summarize(regressionDraft())
    expect(totals.historicalMortality).toBe(0)
    expect(totals.otherAdjustment).toBe(682)
    expect(totals.flocksWithUnknownHistory).toBe(8)
  })

  it("records the 682 as mortality only when the farm says so", () => {
    const draft = regressionDraft()
    draft.flocks = draft.flocks.map((f) => ({
      ...f, historyKnown: true, historicalMortality: String(historicalReduction(f)),
    }))
    const totals = summarize(draft)
    expect(totals.historicalMortality).toBe(682)
    expect(totals.otherAdjustment).toBe(0)
  })

  it("sends every flock with its CURRENT birds, not what was placed", () => {
    // This is the line that stops a fake first production record being needed:
    // the flock is created holding what is standing in the pen.
    const draft = regressionDraft()
    const request = toRequest(draft, context(), "u1", "f1")
    expect(request.Flocks.map((f) => f.CurrentLiveBirds).reduce((a, b) => a + b, 0)).toBe(7518)
    expect(request.Flocks.map((f) => f.OriginallyPlaced).reduce((a, b) => a + b, 0)).toBe(8200)
  })

  it("passes validation", () => {
    expect(validateSetup(regressionDraft(), context()).errors).toEqual([])
  })
})

describe("generateBatches", () => {
  const opts = (over: Partial<Parameters<typeof generateBatches>[0]> = {}) => ({
    count: 3, prefix: "Batch", codePrefix: "B", startNumber: 1,
    breed: "Layers", numberOfBirds: "5000", startDate: "2026-01-09",
    ...over,
  })

  it("numbers the names and the codes from the starting number", () => {
    const rows = generateBatches(opts())
    expect(rows.map((r) => r.batchName)).toEqual(["Batch 1", "Batch 2", "Batch 3"])
    expect(rows.map((r) => r.batchCode)).toEqual(["B1", "B2", "B3"])
  })

  it("honours a custom starting number", () => {
    const rows = generateBatches(opts({ count: 2, startNumber: 7 }))
    expect(rows.map((r) => r.batchName)).toEqual(["Batch 7", "Batch 8"])
    expect(rows.map((r) => r.batchCode)).toEqual(["B7", "B8"])
  })

  it("copies breed, birds and date onto every row", () => {
    const rows = generateBatches(opts())
    expect(rows.every((r) => r.breed === "Layers")).toBe(true)
    expect(rows.every((r) => r.numberOfBirds === "5000")).toBe(true)
    expect(rows.every((r) => r.startDate === "2026-01-09")).toBe(true)
  })

  it("gives codes NO space, so they read as identifiers", () => {
    // "Batch 1" is a name; "B1" is a code. A space in a code column is a bug.
    expect(generateBatches(opts({ count: 1 }))[0].batchCode).toBe("B1")
  })

  it("numbers plainly when a prefix is blank, with no leading space", () => {
    const rows = generateBatches(opts({ count: 2, prefix: "   ", codePrefix: "" }))
    expect(rows.map((r) => r.batchName)).toEqual(["1", "2"])
    expect(rows.map((r) => r.batchCode)).toEqual(["1", "2"])
  })

  it("never generates more than one setup's worth", () => {
    expect(generateBatches(opts({ count: 5000 }))).toHaveLength(MAX_BATCHES)
  })

  it("gives every row its own key", () => {
    expect(new Set(generateBatches(opts({ count: 5 })).map((r) => r.key)).size).toBe(5)
  })

  it("produces rows that pass validation as they stand", () => {
    // The generator is a convenience, not a way round the rules -- what it
    // makes must be submittable without further editing.
    const batches = generateBatches(opts({ count: 2 }))
    const h = { ...emptyHouse(), houseName: "Pen 1", capacity: "", location: "" }
    const draft: SetupDraft = {
      mode: "existing", batches, houses: [h],
      flocks: [{
        ...emptyFlock(batches[0].key, h.key),
        name: "B1 - Pen 1", originallyPlaced: "1000", currentLiveBirds: "950",
        ageMode: "date", startDate: "2026-01-09",
      }],
    }
    expect(validateSetup(draft, context()).errors).toEqual([])
  })

  it("produces unique codes, so its own rows never collide", () => {
    const batches = generateBatches(opts({ count: 4 }))
    const draft: SetupDraft = {
      mode: "existing", batches, houses: [], flocks: [],
    }
    const codeErrors = validateSetup(draft, context()).errors.filter((e) => e.field === "batchCode")
    expect(codeErrors).toEqual([])
  })
})

describe("historicalReduction", () => {
  it("is the difference between placed and standing", () => {
    expect(historicalReduction(flock("b", "h", { originallyPlaced: "1050", currentLiveBirds: "960" }))).toBe(90)
  })

  it("is zero for a flock that has lost nothing", () => {
    expect(historicalReduction(flock("b", "h", { originallyPlaced: "1000", currentLiveBirds: "1000" }))).toBe(0)
  })

  it("never goes negative", () => {
    expect(historicalReduction(flock("b", "h", { originallyPlaced: "900", currentLiveBirds: "1000" }))).toBe(0)
  })
})

describe("breakdown", () => {
  const f = (over: Partial<FlockRow>) =>
    flock("b", "h", { originallyPlaced: "1050", currentLiveBirds: "960", ...over })

  it("splits a known history into its buckets", () => {
    // The spec's example: 70 died, 10 sold, 5 culled, 0 transferred, 5 unknown.
    const b = breakdown(f({
      historyKnown: true, historicalMortality: "70", historicalSold: "10",
      historicalCulled: "5", historicalTransferred: "0",
    }))
    expect(b).toMatchObject({ mortality: 70, sold: 10, culled: 5, transferred: 0, other: 5, difference: 90 })
  })

  it("puts an unexplained remainder in `other`, never in mortality", () => {
    const b = breakdown(f({ historyKnown: true, historicalMortality: "60" }))
    expect(b.mortality).toBe(60)
    expect(b.other).toBe(30)
  })

  it("puts the WHOLE difference in `other` when the history is unknown", () => {
    // The rule the feature turns on: 90 birds gone is not 90 birds dead.
    const b = breakdown(f({ historyKnown: false, historicalMortality: "90" }))
    expect(b.mortality).toBe(0)
    expect(b.other).toBe(90)
  })

  it("flags a breakdown that claims more birds than went missing", () => {
    expect(breakdown(f({ historyKnown: true, historicalMortality: "200" })).overStated).toBe(true)
  })

  it("is all zeroes for a flock that lost nothing", () => {
    const b = breakdown(f({ originallyPlaced: "1000", currentLiveBirds: "1000" }))
    expect(b).toMatchObject({ mortality: 0, other: 0, difference: 0 })
  })
})

describe("flocksNeedingReconciliation", () => {
  it("skips flocks whose numbers already agree", () => {
    const needs = flocksNeedingReconciliation([
      flock("b", "h1", { originallyPlaced: "1000", currentLiveBirds: "1000" }),
      flock("b", "h2", { originallyPlaced: "1050", currentLiveBirds: "960" }),
    ])
    expect(needs).toHaveLength(1)
    expect(needs[0].currentLiveBirds).toBe("960")
  })
})

describe("age and start date", () => {
  it("derives a start date from a stated age, in whole weeks", () => {
    // 70 weeks before 2026-07-11.
    expect(deriveStartDate("2026-07-11", 70)).toBe("2025-03-08")
  })

  it("marks a derived date as estimated and a supplied one as not", () => {
    expect(resolveStartDate(flock("b", "h", { ageMode: "date", startDate: "2025-07-05" }), BUSINESS_DATE))
      .toEqual({ date: "2025-07-05", estimated: false })
    expect(resolveStartDate(flock("b", "h", { ageMode: "age", currentAgeInWeeks: "70" }), BUSINESS_DATE).estimated)
      .toBe(true)
  })

  it("sends the age rather than a made-up date when only the age is known", () => {
    const b = batch()
    const h = house()
    const draft: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { ageMode: "age", currentAgeInWeeks: "70", startDate: "" })],
    }
    const request = toRequest(draft, context(), "u1", "f1")
    expect(request.Flocks[0].StartDate).toBeNull()
    expect(request.Flocks[0].CurrentAgeInWeeks).toBe(70)
  })
})

describe("validateSetup", () => {
  const draft = (over: Partial<SetupDraft> = {}): SetupDraft => {
    const b = batch()
    const h = house()
    return { mode: "existing", batches: [b], houses: [h], flocks: [flock(b.key, h.key)], ...over }
  }

  it("accepts a farm with no historical reduction at all", () => {
    const d = draft()
    d.flocks = [flock(d.batches[0].key, d.houses[0].key, { originallyPlaced: "1000", currentLiveBirds: "1000" })]
    expect(validateSetup(d, context()).errors).toEqual([])
  })

  it("accepts known mortality, sold and culled together", () => {
    const d = draft()
    d.flocks = [flock(d.batches[0].key, d.houses[0].key, {
      originallyPlaced: "1050", currentLiveBirds: "960", historyKnown: true,
      historicalMortality: "70", historicalSold: "10", historicalCulled: "5",
    })]
    expect(validateSetup(d, context()).errors).toEqual([])
  })

  it("accepts multiple batches, houses and several flocks per batch", () => {
    expect(validateSetup(regressionDraft(), context()).errors).toEqual([])
  })

  it("refuses an empty setup", () => {
    const d = draft({ flocks: [] })
    expect(validateSetup(d, context()).errors[0].message).toContain("at least one flock")
  })

  it("refuses a setup over the flock limit", () => {
    const d = draft()
    d.flocks = Array.from({ length: MAX_FLOCKS + 1 }, (_, i) =>
      flock(d.batches[0].key, d.houses[0].key, { name: `F${i}` }))
    expect(validateSetup(d, context()).errors[0].index).toBe(-1)
  })

  it("refuses more birds standing than were placed", () => {
    const d = draft()
    d.flocks = [flock(d.batches[0].key, d.houses[0].key, { originallyPlaced: "900", currentLiveBirds: "1000" })]
    const errs = validateSetup(d, context()).errors
    expect(errs.some((e) => e.field === "currentLiveBirds")).toBe(true)
  })

  it("refuses a breakdown that claims more than went missing", () => {
    const d = draft()
    d.flocks = [flock(d.batches[0].key, d.houses[0].key, {
      originallyPlaced: "1050", currentLiveBirds: "960", historyKnown: true, historicalMortality: "200",
    })]
    expect(validateSetup(d, context()).errors.some((e) => e.field === "breakdown")).toBe(true)
  })

  it("does NOT check the breakdown when the history is unknown", () => {
    // Leftover numbers in a collapsed panel must not block the setup.
    const d = draft()
    d.flocks = [flock(d.batches[0].key, d.houses[0].key, {
      originallyPlaced: "1050", currentLiveBirds: "960", historyKnown: false, historicalMortality: "9999",
    })]
    expect(validateSetup(d, context()).errors).toEqual([])
  })

  // ---- Batch integrity: blocks ----------------------------------------
  it("refuses flocks placed with more birds than the batch ever held", () => {
    // The spec's case: B1 holds 6,000, flocks claim 7,000 placed.
    const b = batch({ numberOfBirds: "6000" })
    const h1 = house({ houseName: "Pen 1", capacity: "" })
    const h2 = house({ houseName: "Pen 2", capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h1, h2],
      flocks: [
        flock(b.key, h1.key, { name: "B1 - Pen 1", originallyPlaced: "4000", currentLiveBirds: "4000" }),
        flock(b.key, h2.key, { name: "B1 - Pen 2", originallyPlaced: "3000", currentLiveBirds: "3000" }),
      ],
    }
    const errs = validateSetup(d, context()).errors
    expect(errs).toHaveLength(1)
    expect(errs[0].message).toContain("7,000")
    expect(errs[0].message).toContain("6,000")
  })

  it("accepts an exact batch allocation", () => {
    const b = batch({ numberOfBirds: "6000" })
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "6000", currentLiveBirds: "5800" })],
    }
    expect(validateSetup(d, context()).errors).toEqual([])
  })

  it("accepts a partial batch allocation", () => {
    const b = batch({ numberOfBirds: "6000" })
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "4000", currentLiveBirds: "3900" })],
    }
    expect(validateSetup(d, context()).errors).toEqual([])
  })

  it("counts what a reused batch has already given out", () => {
    const existing = { batchId: 7, batchCode: "B001", batchName: "B1", breed: "Brown", numberOfBirds: 6000 }
    const b = batchRowFromExisting(existing)
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "3000", currentLiveBirds: "3000" })],
    }
    const ctx = context({ existingBatches: [existing], allocatedByBatchId: { 7: 4000 } })
    // 4,000 already out plus 3,000 more is 7,000 against a 6,000-bird batch.
    expect(validateSetup(d, ctx).errors.some((e) => e.message.includes("already allocated"))).toBe(true)
  })

  // ---- House capacity: warns only --------------------------------------
  it("WARNS rather than blocks when the birds exceed a house's recorded capacity", () => {
    // Historical reality beats a number somebody typed into a setup form.
    const b = batch()
    const h = house({ capacity: "800" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "1000", currentLiveBirds: "919" })],
    }
    const { errors, warnings } = validateSetup(d, context())
    expect(errors).toEqual([])
    expect(warnings).toHaveLength(1)
    expect(warnings[0].message).toContain("check the capacity")
  })

  it("does not warn about a house with no capacity recorded", () => {
    const b = batch()
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key)],
    }
    expect(validateSetup(d, context()).warnings).toEqual([])
  })

  it("counts what a reused house already holds", () => {
    const existing = { houseId: 3, houseName: "Pen 1", capacity: 1000, occupied: 800, availableCapacity: 200, activeFlocks: 1 }
    const h = houseRowFromExisting(existing)
    const b = batch()
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "500", currentLiveBirds: "500" })],
    }
    const { warnings } = validateSetup(d, context({ existingHouses: [existing] }))
    expect(warnings[0].message).toContain("already holds 800")
  })

  // ---- Duplicates and reuse -------------------------------------------
  it("flags a batch code that already exists rather than creating a second one", () => {
    const existing = { batchId: 1, batchCode: "B001", batchName: "B1", breed: "Brown", numberOfBirds: 6000 }
    const d = draft()
    const errs = validateSetup(d, context({ existingBatches: [existing] })).errors
    expect(errs.some((e) => e.message.includes("reuse it"))).toBe(true)
  })

  it("does NOT flag a batch that is explicitly being reused", () => {
    const existing = { batchId: 1, batchCode: "B001", batchName: "B1", breed: "Brown", numberOfBirds: 6000 }
    const b = batchRowFromExisting(existing)
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "1000", currentLiveBirds: "919" })],
    }
    expect(validateSetup(d, context({ existingBatches: [existing] })).errors).toEqual([])
  })

  it("flags a house name that already exists", () => {
    const existing = { houseId: 3, houseName: "Pen 1", capacity: 5000, occupied: 0, availableCapacity: 5000, activeFlocks: 0 }
    const d = draft()
    const errs = validateSetup(d, context({ existingHouses: [existing] })).errors
    expect(errs.some((e) => e.message.includes("select it instead"))).toBe(true)
  })

  it("flags a flock name that already exists on the farm", () => {
    const d = draft()
    const errs = validateSetup(d, context({ existingFlockNames: ["b1 - pen 1"] })).errors
    expect(errs.some((e) => e.field === "name" && e.message.includes("already exists"))).toBe(true)
  })

  it("flags two flocks in this setup sharing a name", () => {
    const d = draft()
    d.flocks = [
      flock(d.batches[0].key, d.houses[0].key, { name: "B1 - Pen 1" }),
      flock(d.batches[0].key, d.houses[0].key, { name: "B1 - Pen 1" }),
    ]
    const errs = validateSetup(d, context()).errors.filter((e) => e.field === "name")
    expect(errs.map((e) => e.index)).toEqual([0, 1])
  })
})

describe("errorsBySection", () => {
  it("keys messages by section, row and field", () => {
    const b = batch({ batchName: "" })
    const h = house()
    const d: SetupDraft = { mode: "existing", batches: [b], houses: [h], flocks: [flock(b.key, h.key)] }
    const map = errorsBySection(validateSetup(d, context()).errors)
    expect(map.batches[0].batchName).toBe("Batch name is required.")
  })
})

describe("toRequest", () => {
  it("carries the keys so the server can resolve them to real ids", () => {
    const d = regressionDraft()
    const request = toRequest(d, context(), "u1", "f1")
    expect(request.Flocks[0].BatchKey).toBe(d.batches[0].key)
    expect(request.Flocks[0].HouseKey).toBe(d.houses[0].key)
  })

  it("marks reused records by id and new ones by null", () => {
    const existing = { batchId: 9, batchCode: "B009", batchName: "B9", breed: "Brown", numberOfBirds: 500 }
    const b = batchRowFromExisting(existing)
    const h = house()
    const d: SetupDraft = { mode: "existing", batches: [b], houses: [h], flocks: [flock(b.key, h.key)] }
    const request = toRequest(d, context(), "u1", "f1")
    expect(request.Batches[0].ExistingBatchId).toBe(9)
    expect(request.Houses[0].ExistingHouseId).toBeNull()
  })

  it("never sends a breakdown for a flock whose history is unknown", () => {
    const b = batch()
    const h = house()
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, {
        originallyPlaced: "1050", currentLiveBirds: "960",
        historyKnown: false, historicalMortality: "70", historicalSold: "20",
      })],
    }
    const sent = toRequest(d, context(), "u1", "f1").Flocks[0]
    expect(sent.HistoricalMortality).toBe(0)
    expect(sent.HistoricalSold).toBe(0)
    expect(sent.OtherAdjustment).toBe(90)
  })
})

describe("defaultFlockName", () => {
  it("follows the batch-allocation convention", () => {
    expect(defaultFlockName("B1", "Pen 1")).toBe("B1 - Pen 1")
  })
})

describe("parseCount", () => {
  it("reads a blank box as zero and refuses anything that is not a whole number", () => {
    expect(parseCount("")).toBe(0)
    expect(parseCount("12.5")).toBeUndefined()
  })
})

describe("duplicateKey", () => {
  it("ignores case and repeated spacing", () => {
    expect(duplicateKey("  B1 -  Pen 1 ")).toBe(duplicateKey("b1 - pen 1"))
  })
})
