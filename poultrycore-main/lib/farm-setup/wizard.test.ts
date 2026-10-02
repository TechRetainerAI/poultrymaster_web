import { describe, expect, it } from "vitest"
import {
  MAX_BATCHES, MAX_FLOCKS,
  batchRowFromExisting, breakdown, defaultFlockName, deriveStartDate, duplicateKey,
  emptyBatch, emptyFlock, emptyHouse, errorsBySection, flocksNeedingReconciliation, generateBatches,
  historicalReduction, houseCapacityNote, houseLoad, houseRowFromExisting, houseRowViews,
  parseCount, penOptions, renameForHouse, resolveStartDate, seedReconciliation,
  summarize, summarizeHouseRows,
  balanceBreakdown, batchAllocationViews, batchDraft, batchEditRows, distributePensEvenly,
  fillPensToCapacity, fromBatchDraft, isHistoricalBatch,
  summarizeBatchEditRows, visibleBatchEditRows,
  summarizeBatchRows, toRequest,
  validateSetup, visibleBatchRows, visibleHouseRows,
  type BatchRow, type FlockRow, type HouseRow, type SetupContext, type SetupDraft,
} from "./wizard"

const BUSINESS_DATE = "2026-07-11"

const context = (over: Partial<SetupContext> = {}): SetupContext => ({
  existingBatches: [],
  existingHouses: [],
  existingFlocks: [],
  existingFlockNames: [],
  allocatedByBatchId: {},
  businessDate: BUSINESS_DATE,
  ...over,
})

// Sized to the default flock below (1,000 placed), because a historical batch
// must have every bird in a pen. A test that needs a different size says so.
const batch = (over: Partial<BatchRow> = {}): BatchRow => ({
  ...emptyBatch(),
  batchName: "B1", batchCode: "B001", breed: "Brown",
  numberOfBirds: "1000", startDate: "2025-07-05",
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
    const batches = generateBatches(opts({ count: 1 }))
    const h = { ...emptyHouse(), houseName: "Pen 1", capacity: "", location: "" }
    const draft: SetupDraft = {
      mode: "existing", batches, houses: [h],
      flocks: [{
        ...emptyFlock(batches[0].key, h.key),
        // All 5,000 of the generated batch, because it is historical.
        name: "B1 - Pen 1", originallyPlaced: "5000", currentLiveBirds: "4950",
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
    const d = draft({ batches: [batch({ numberOfBirds: "1050" })] })
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
    const d = draft({ batches: [batch({ numberOfBirds: "1050" })] })
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

  it("accepts a partial allocation of a NEW purchase — the rest is not placed yet", () => {
    // 6,000 chicks bought today, 4,000 in a pen so far. The other 2,000 are real
    // and genuinely unplaced, so this must be allowed.
    const b = batch({ numberOfBirds: "6000", isHistorical: false })
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "4000", currentLiveBirds: "3900" })],
    }
    expect(validateSetup(d, context()).errors).toEqual([])
  })

  it("REFUSES a partial allocation of a batch the farm already had", () => {
    // The same numbers, but these birds are standing in pens right now. If only
    // 4,000 of 6,000 have a pen, the farm cannot say where the other 2,000 are —
    // and they would sit in the bird ledger forever as stock no flock holds.
    const b = batch({ numberOfBirds: "6000", isHistorical: true })
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "4000", currentLiveBirds: "3900" })],
    }
    const { errors } = validateSetup(d, context())
    expect(errors).toHaveLength(1)
    expect(errors[0].section).toBe("batches")
    expect(errors[0].message).toContain("2,000 are unaccounted for")
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
    // Capacity plans the next placement; it does not get a vote on birds that
    // are already standing in the pen.
    const b = batch()
    const h = house({ capacity: "800" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "1000", currentLiveBirds: "919" })],
    }
    const { errors, warnings } = validateSetup(d, context())
    expect(errors).toEqual([])
    const capacity = warnings.filter((w) => w.field === "capacity")
    expect(capacity).toHaveLength(1)
    // Worded as what it costs going forward, not as a complaint about the past.
    expect(capacity[0].message).toContain("where your next batch can go")
  })

  it("does not warn about a house with no capacity recorded", () => {
    const b = batch()
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key)],
    }
    expect(validateSetup(d, context()).warnings.filter((w) => w.field === "capacity")).toEqual([])
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
    expect(warnings.find((w) => w.field === "capacity")?.message).toContain("already holds 800")
  })

  // ---- The pen's load, as the flock row shows it ------------------------
  it("reports a pen's load so the flock row can show it as the pen is picked", () => {
    const existing = { houseId: 3, houseName: "Pen 1", capacity: 2000, occupied: 500, availableCapacity: 1500, activeFlocks: 1 }
    const h = houseRowFromExisting(existing)
    const b = batch()
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "1000", currentLiveBirds: "900" })],
    }
    const load = houseLoad(h.key, d, context({ existingHouses: [existing] }))!
    expect(load.capacity).toBe(2000)
    expect(load.occupied).toBe(500)
    expect(load.activeFlocks).toBe(1)
    // Standing is what is STANDING -- current live birds, never originally placed.
    expect(load.standing).toBe(900)
    expect(load.total).toBe(1400)
    expect(load.overBy).toBe(0)
    expect(houseCapacityNote(load)).toBeNull()
  })

  it("sums every flock row that names the same pen", () => {
    const b = batch()
    const h = house({ capacity: "1000" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [
        flock(b.key, h.key, { name: "A", currentLiveBirds: "600" }),
        flock(b.key, h.key, { name: "B", currentLiveBirds: "600" }),
      ],
    }
    const load = houseLoad(h.key, d, context())!
    expect(load.standing).toBe(1200)
    expect(load.overBy).toBe(200)
    expect(houseCapacityNote(load)).toContain("where your next batch can go")
  })

  it("treats a pen with no capacity recorded as unconstrained", () => {
    const b = batch()
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { currentLiveBirds: "99999" })],
    }
    const load = houseLoad(h.key, d, context())!
    expect(load.capacity).toBeNull()
    expect(load.overBy).toBe(0)
    expect(houseCapacityNote(load)).toBeNull()
  })

  it("has no load for a pen the draft does not have", () => {
    expect(houseLoad("no-such-pen", draft(), context())).toBeNull()
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

// ---- Returning-user house filtering ----------------------------------------
//
// A farm coming back to allocate a new batch has twenty pens and eighteen of
// them are full. It came for the two it can use.
describe("house step filtering", () => {
  const occupiedPen = (id: number, capacity: number, occupied: number) => ({
    houseId: id, houseName: `Pen ${id}`, capacity,
    occupied, availableCapacity: Math.max(0, capacity - occupied),
    activeFlocks: occupied > 0 ? 1 : 0,
  })

  it("shows EMPTY pens only — a pen with room is still not empty", () => {
    const full = occupiedPen(1, 2000, 2000)
    const roomy = occupiedPen(2, 2000, 500)
    const empty = occupiedPen(3, 2000, 0)
    const d: SetupDraft = {
      mode: "existing", batches: [], flocks: [],
      houses: [full, roomy, empty].map(houseRowFromExisting),
    }
    const ctx = context({ existingHouses: [full, roomy, empty] })
    const views = houseRowViews(d, ctx)

    // Pen 2 has room for 1,500 more and is still hidden: it holds birds.
    expect(views.map((v) => v.hasRoom)).toEqual([false, true, true])
    expect(views.map((v) => v.isEmptyOnFarm)).toEqual([false, false, true])
    expect(visibleHouseRows(views, false).map((v) => v.row.houseName)).toEqual(["Pen 3"])
    expect(visibleHouseRows(views, true)).toHaveLength(3)
  })

  it("always shows a pen being created in this session, full or not", () => {
    const full = occupiedPen(1, 2000, 2000)
    const brandNew = { ...emptyHouse("1000", ""), houseName: "Pen 9" }
    const d: SetupDraft = {
      mode: "existing", batches: [], flocks: [],
      houses: [houseRowFromExisting(full), brandNew],
    }
    const visible = visibleHouseRows(houseRowViews(d, context({ existingHouses: [full] })), false)
    expect(visible.map((v) => v.row.houseName)).toEqual(["Pen 9"])
  })

  it("hides a pen holding birds even when it has no capacity recorded", () => {
    // Unconstrained is not the same as empty.
    const noCap = { houseId: 1, houseName: "Pen 1", capacity: null, occupied: 9999, availableCapacity: null, activeFlocks: 1 }
    const d: SetupDraft = {
      mode: "existing", batches: [], flocks: [], houses: [houseRowFromExisting(noCap)],
    }
    const views = houseRowViews(d, context({ existingHouses: [noCap] }))
    expect(views[0].hasRoom).toBe(true)
    expect(views[0].isEmptyOnFarm).toBe(false)
    expect(visibleHouseRows(views, false)).toHaveLength(0)
  })

  it("KEEPS an empty pen listed after this setup allocates to it", () => {
    // "Empty" on this step means empty of the FARM's birds. If it counted the
    // draft's own allocations, stepping back here would look like the pen had
    // vanished.
    const pen = occupiedPen(1, 1000, 0)
    const b = batch()
    const h = houseRowFromExisting(pen)
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "1000", currentLiveBirds: "1000" })],
    }
    const views = houseRowViews(d, context({ existingHouses: [pen] }))
    expect(views[0].isEmpty).toBe(false)        // the picker's question
    expect(views[0].isEmptyOnFarm).toBe(true)   // the Houses step's question
    expect(visibleHouseRows(views, false)).toHaveLength(1)
  })

  it("reports what is hidden so the step can say so", () => {
    const full = occupiedPen(1, 2000, 2000)
    const roomy = occupiedPen(2, 2000, 500)
    const brandNew = { ...emptyHouse("1000", ""), houseName: "Pen 9" }
    const d: SetupDraft = {
      mode: "existing", batches: [], flocks: [],
      houses: [...[full, roomy].map(houseRowFromExisting), brandNew],
    }
    // Both existing pens hold birds, so both are hidden.
    const summary = summarizeHouseRows(houseRowViews(d, context({ existingHouses: [full, roomy] })))
    expect(summary).toEqual({ total: 3, existing: 2, occupied: 2, hidden: 2 })
  })

  it("says nothing is hidden when every pen is empty", () => {
    const empty = occupiedPen(2, 2000, 0)
    const d: SetupDraft = {
      mode: "existing", batches: [], flocks: [], houses: [houseRowFromExisting(empty)],
    }
    expect(summarizeHouseRows(houseRowViews(d, context({ existingHouses: [empty] }))).hidden).toBe(0)
  })
})

// ---- Historical vs new purchase --------------------------------------------
//
// The two genuinely mix: a farm onboarded last year comes back having just
// bought a batch. What differs is whether the birds are a FACT or a PLAN.
describe("historical vs new purchase", () => {
  it("reads a new batch row's own flag", () => {
    expect(isHistoricalBatch(batch({ isHistorical: true }), context())).toBe(true)
    expect(isHistoricalBatch(batch({ isHistorical: false }), context())).toBe(false)
  })

  it("reads a REUSED batch from what is stored, not from what the row claims", () => {
    // The row carries only an id. The nature of a purchase it is not creating is
    // not its to restate — the server decides the same way.
    const existing = {
      batchId: 7, batchCode: "B001", batchName: "B1", breed: "Brown",
      numberOfBirds: 1000, isHistorical: true,
    }
    const row = { ...batchRowFromExisting(existing), isHistorical: false }
    expect(isHistoricalBatch(row, context({ existingBatches: [existing] }))).toBe(true)
  })

  it("treats a batch from an older server as a current purchase", () => {
    const existing = { batchId: 7, batchCode: "B001", batchName: "B1", breed: "Brown", numberOfBirds: 1000 }
    expect(isHistoricalBatch(batchRowFromExisting(existing), context({ existingBatches: [existing] }))).toBe(false)
  })

  it("carries the flag and the full purchase details to the server", () => {
    const b = batch({
      isHistorical: false, totalCost: "10000", amountPaid: "7000",
      supplierType: "foreign", dollarConversionRate: "12.5",
      orderPlacementDate: "2026-01-02", estimatedArrivalDate: "2026-01-09",
    })
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key)],
    }
    const sent = toRequest(d, context(), "u1", "f1").Batches[0]
    expect(sent.IsHistorical).toBe(false)
    expect(sent.TotalCost).toBe(10000)
    expect(sent.AmountPaid).toBe(7000)
    expect(sent.SupplierType).toBe("foreign")
    expect(sent.DollarConversionRate).toBe(12.5)
    expect(sent.OrderPlacementDate).toBe("2026-01-02")
    expect(sent.EstimatedArrivalDate).toBe("2026-01-09")
  })

  it("BLOCKS overfilling a pen with newly bought birds", () => {
    // A plan that does not fit is refused, the same answer the Batch Allocation
    // tool gives — it is the same decision.
    const b = batch({ numberOfBirds: "2400", isHistorical: false })
    const h = house({ capacity: "2000" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "2400", currentLiveBirds: "2400" })],
    }
    const { errors, warnings } = validateSetup(d, context())
    expect(warnings.filter((w) => w.field === "capacity")).toEqual([])
    expect(errors).toHaveLength(1)
    expect(errors[0].section).toBe("houses")
    expect(errors[0].message).toContain("only 2,000 will fit")
  })

  it("only WARNS when the same pen holds birds the farm already had", () => {
    // These birds are standing there. Capacity is a forward-planning figure and
    // does not get to refuse a fact.
    const b = batch({ numberOfBirds: "2400", isHistorical: true })
    const h = house({ capacity: "2000" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "2400", currentLiveBirds: "2400" })],
    }
    const { errors, warnings } = validateSetup(d, context())
    expect(errors).toEqual([])
    const capacity = warnings.filter((w) => w.field === "capacity")
    expect(capacity).toHaveLength(1)
    expect(capacity[0].message).toContain("where your next batch can go")
  })

  it("blocks when new birds are added to a pen already full of historical ones", () => {
    const hist = batch({ batchCode: "B001", numberOfBirds: "2000", isHistorical: true })
    const fresh = batch({ batchCode: "B002", numberOfBirds: "500", isHistorical: false })
    const h = house({ capacity: "2000" })
    const d: SetupDraft = {
      mode: "existing", batches: [hist, fresh], houses: [h],
      flocks: [
        flock(hist.key, h.key, { name: "A", originallyPlaced: "2000", currentLiveBirds: "2000" }),
        flock(fresh.key, h.key, { name: "B", originallyPlaced: "500", currentLiveBirds: "500" }),
      ],
    }
    const errors = validateSetup(d, context()).errors.filter((e) => e.section === "houses")
    expect(errors).toHaveLength(1)
    expect(errors[0].message).toContain("only 0 will fit")
  })
})

// ---- Batch-at-a-time allocation ---------------------------------------------
describe("batchAllocationViews", () => {
  const pen = (n: number) => house({ houseName: `Pen ${n}`, capacity: "" })

  it("the spec's exact-allocation case: 5,000 batch, 1,000 already out, 4,000 placed", () => {
    // Original 5,000 − previously 1,000 = 4,000 available.
    // Pen A 1,500 + Pen B 1,250 + Pen C 1,250 = 4,000. Nothing left.
    const existing = { batchId: 7, batchCode: "B1", batchName: "B1", breed: "Brown", numberOfBirds: 5000 }
    const b = batchRowFromExisting(existing)
    const pens = [pen(1), pen(2), pen(3)]
    const placed = [1500, 1250, 1250]
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: pens,
      flocks: pens.map((h, i) => flock(b.key, h.key, {
        name: `B1 - Pen ${i + 1}`,
        originallyPlaced: String(placed[i]), currentLiveBirds: String(placed[i]),
      })),
    }
    const ctx = context({ existingBatches: [existing], allocatedByBatchId: { 7: 1000 } })
    const v = batchAllocationViews(d, ctx)[0]

    expect(v.batchBirds).toBe(5000)
    expect(v.previouslyAllocated).toBe(1000)
    expect(v.available).toBe(4000)
    expect(v.thisAllocation).toBe(4000)
    expect(v.remaining).toBe(0)
    expect(v.status).toBe("complete")
    expect(validateSetup(d, ctx).errors).toEqual([])
  })

  it("the spec's over-allocation case: 5,000 placed into 4,000 available is BLOCKED", () => {
    const existing = { batchId: 7, batchCode: "B1", batchName: "B1", breed: "Brown", numberOfBirds: 5000 }
    const b = batchRowFromExisting(existing)
    const pens = [pen(1), pen(2), pen(3)]
    const placed = [2000, 2000, 1000]
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: pens,
      flocks: pens.map((h, i) => flock(b.key, h.key, {
        name: `B1 - Pen ${i + 1}`,
        originallyPlaced: String(placed[i]), currentLiveBirds: String(placed[i]),
      })),
    }
    const ctx = context({ existingBatches: [existing], allocatedByBatchId: { 7: 1000 } })
    const v = batchAllocationViews(d, ctx)[0]

    expect(v.thisAllocation).toBe(5000)
    expect(v.available).toBe(4000)
    expect(v.status).toBe("over")
    expect(validateSetup(d, ctx).errors.some((e) => e.section === "batches")).toBe(true)
  })

  it("the spec's partial case: 8,000 of a 12,000 NEW purchase leaves 4,000 for later", () => {
    const b = batch({ numberOfBirds: "12000", isHistorical: false })
    const h = pen(1)
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "8000", currentLiveBirds: "8000" })],
    }
    const v = batchAllocationViews(d, context())[0]
    expect(v.thisAllocation).toBe(8000)
    expect(v.remaining).toBe(4000)
    expect(v.status).toBe("partial")
    expect(validateSetup(d, context()).errors).toEqual([])
  })

  it("measures allocation as PLACED, so a historical batch reads fully allocated", () => {
    // 1,000 placed, 919 standing. Counting live birds would call this 81 short.
    const b = batch({ numberOfBirds: "1000", isHistorical: true })
    const h = pen(1)
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "1000", currentLiveBirds: "919" })],
    }
    const v = batchAllocationViews(d, context())[0]
    expect(v.thisAllocation).toBe(1000)
    expect(v.status).toBe("complete")
  })

  it("marks a batch with nothing placed as unallocated", () => {
    const b = batch({ numberOfBirds: "5000" })
    const d: SetupDraft = { mode: "existing", batches: [b], houses: [], flocks: [] }
    expect(batchAllocationViews(d, context())[0].status).toBe("unallocated")
  })
})

describe("visibleBatchRows", () => {
  const finished = { batchId: 1, batchCode: "OLD", batchName: "Old", breed: "Brown", numberOfBirds: 5000 }
  const partial = { batchId: 2, batchCode: "PART", batchName: "Part", breed: "Brown", numberOfBirds: 10000 }

  const build = () => {
    const oldRow = batchRowFromExisting(finished)
    const partRow = batchRowFromExisting(partial)
    const fresh = batch({ batchCode: "NEW", numberOfBirds: "12000" })
    const d: SetupDraft = {
      mode: "existing", batches: [oldRow, partRow, fresh], houses: [], flocks: [],
    }
    const ctx = context({
      existingBatches: [finished, partial],
      allocatedByBatchId: { 1: 5000, 2: 8000 },
    })
    return { d, ctx }
  }

  it("hides a batch the farm already finished, and keeps the rest", () => {
    const { d, ctx } = build()
    const views = batchAllocationViews(d, ctx)
    const visible = visibleBatchRows(views, false)
    expect(visible.map((v) => v.batch.batchCode)).toEqual(["NEW", "PART"])
  })

  it("shows everything when asked", () => {
    const { d, ctx } = build()
    expect(visibleBatchRows(batchAllocationViews(d, ctx), true)).toHaveLength(3)
  })

  it("puts an over-allocated batch first, because it is the one that blocks", () => {
    const b = batch({ batchCode: "OVER", numberOfBirds: "100" })
    const other = batch({ batchCode: "TODO", numberOfBirds: "500" })
    const h = house({ houseName: "Pen 1", capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [other, b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "900", currentLiveBirds: "900" })],
    }
    const visible = visibleBatchRows(batchAllocationViews(d, context()), false)
    expect(visible[0].batch.batchCode).toBe("OVER")
  })

  it("reports how many finished batches are out of sight", () => {
    const { d, ctx } = build()
    const summary = summarizeBatchRows(batchAllocationViews(d, ctx))
    expect(summary).toEqual({ total: 3, hidden: 1, withBirdsLeft: 2 })
  })
})

// ---- Optional data: informational, never blocking ---------------------------
describe("optional batch data", () => {
  it("mentions a missing supplier and cost without blocking", () => {
    const b = batch()
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h], flocks: [flock(b.key, h.key)],
    }
    const { errors, warnings } = validateSetup(d, context())
    expect(errors).toEqual([])
    expect(warnings.some((w) => w.message.includes("no supplier recorded"))).toBe(true)
    expect(warnings.some((w) => w.message.includes("no purchase cost recorded"))).toBe(true)
    expect(warnings.every((w) => w.message.includes("complete this later") || w.field === "capacity")).toBe(true)
  })

  it("says nothing once the details are filled in", () => {
    const b = batch({ supplierId: 3, costPerChick: "2" })
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h], flocks: [flock(b.key, h.key)],
    }
    expect(validateSetup(d, context()).warnings).toEqual([])
  })

  it("says nothing about a batch the farm already has", () => {
    // It is not being created, so there is nothing to complete here.
    const existing = { batchId: 7, batchCode: "B001", batchName: "B1", breed: "Brown", numberOfBirds: 1000 }
    const b = batchRowFromExisting(existing)
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h], flocks: [flock(b.key, h.key)],
    }
    const ctx = context({ existingBatches: [existing] })
    expect(validateSetup(d, ctx).warnings).toEqual([])
  })
})

// ---- The returning farm, end to end -----------------------------------------
//
// The spec's scenario: 20 houses (18 full, 2 empty), 15 existing flocks, 3
// finished batches and one new 5,000-bird batch. The farm came back to place
// that one batch, and nothing else should be in its way.
describe("a farm returning six months later", () => {
  const build = () => {
    const existingHouses = Array.from({ length: 20 }, (_, i) => ({
      houseId: i + 1,
      houseName: `Pen ${i + 1}`,
      capacity: 2000,
      // The first 18 are full; the last 2 are empty.
      occupied: i < 18 ? 2000 : 0,
      availableCapacity: i < 18 ? 0 : 2000,
      activeFlocks: i < 18 ? 1 : 0,
    }))

    const finishedBatches = [1, 2, 3].map((n) => ({
      batchId: n, batchCode: `OLD${n}`, batchName: `Old ${n}`,
      breed: "Brown", numberOfBirds: 5000, isHistorical: true,
    }))

    const existingFlocks = Array.from({ length: 15 }, (_, i) => ({
      flockId: i + 1, name: `Old flock ${i + 1}`,
      batchId: (i % 3) + 1, houseId: i + 1, houseName: `Pen ${i + 1}`,
      quantity: 2000, active: true,
    }))

    const ctx = context({
      existingHouses,
      existingBatches: finishedBatches,
      existingFlocks,
      existingFlockNames: existingFlocks.map((f) => f.name),
      allocatedByBatchId: { 1: 5000, 2: 5000, 3: 5000 },
    })

    // What the wizard loads: every existing house and batch as reusable rows,
    // plus the one new batch the farm came to place.
    const freshBatch = batch({ batchCode: "NEW", numberOfBirds: "5000", isHistorical: false })
    const draft: SetupDraft = {
      mode: "existing",
      houses: existingHouses.map(houseRowFromExisting),
      batches: [...finishedBatches.map(batchRowFromExisting), freshBatch],
      flocks: [],
    }
    return { draft, ctx, freshBatch }
  }

  it("offers the 2 pens with room, not all 20", () => {
    const { draft, ctx } = build()
    const visible = visibleHouseRows(houseRowViews(draft, ctx), false)
    expect(visible).toHaveLength(2)
    expect(visible.map((v) => v.row.houseName)).toEqual(["Pen 19", "Pen 20"])
  })

  it("shows all 20 with their occupancy when asked", () => {
    const { draft, ctx } = build()
    const all = visibleHouseRows(houseRowViews(draft, ctx), true)
    expect(all).toHaveLength(20)
    expect(all.find((v) => v.row.houseName === "Pen 1")?.load?.occupied).toBe(2000)
    expect(all.find((v) => v.row.houseName === "Pen 1")?.hasRoom).toBe(false)
  })

  it("offers only the batch with birds left, and puts it first", () => {
    const { draft, ctx } = build()
    const visible = visibleBatchRows(batchAllocationViews(draft, ctx), false)
    expect(visible.map((v) => v.batch.batchCode)).toEqual(["NEW"])
    expect(visible[0].available).toBe(5000)
  })

  it("keeps the three finished batches available behind the toggle", () => {
    const { draft, ctx } = build()
    expect(visibleBatchRows(batchAllocationViews(draft, ctx), true)).toHaveLength(4)
    expect(summarizeBatchRows(batchAllocationViews(draft, ctx)).hidden).toBe(3)
  })

  it("does NOT load any of the 15 existing flocks into the editable draft", () => {
    // They are context, reachable read-only; they are never editable rows.
    const { draft, ctx } = build()
    expect(draft.flocks).toEqual([])
    expect(ctx.existingFlocks).toHaveLength(15)
  })

  it("places the new batch into the two empty pens and validates", () => {
    const { draft, ctx, freshBatch } = build()
    const empty = draft.houses.filter((h) => ["Pen 19", "Pen 20"].includes(h.houseName))
    draft.flocks = empty.map((h, i) => flock(freshBatch.key, h.key, {
      name: `NEW - ${h.houseName}`,
      originallyPlaced: "2000", currentLiveBirds: "2000",
    }))

    const v = batchAllocationViews(draft, ctx).find((x) => x.batch.batchCode === "NEW")!
    expect(v.thisAllocation).toBe(4000)
    expect(v.remaining).toBe(1000)
    expect(v.status).toBe("partial")
    // A NEW purchase may be partially placed — the other 1,000 are real and
    // simply not in a pen yet.
    expect(validateSetup(draft, ctx).errors).toEqual([])
  })
})

// ---- The shared purchase form's seam ----------------------------------------
//
// batchDraft/fromBatchDraft are what let Initial Farm Setup render the same
// fields as Flock Purchases. A field added to the shared form and forgotten here
// would simply stop saving, silently — so this walks every field.
describe("batchDraft <-> BatchRow", () => {
  it("carries every shared field out to the form", () => {
    const row = batch({
      batchName: "B1", batchCode: "B001", breed: "Brown",
      numberOfBirds: "5000", startDate: "2026-03-01",
      costPerChick: "2", totalCost: "10000", amountPaid: "7000",
      supplierType: "foreign", supplierId: 9, dollarConversionRate: "12.5",
      orderPlacementDate: "2026-02-01", estimatedArrivalDate: "2026-02-28",
      notes: "shipped late",
    })
    expect(batchDraft(row)).toEqual({
      batchName: "B1", batchCode: "B001", breed: "Brown",
      numberOfBirds: "5000", startDate: "2026-03-01",
      costPerChick: "2", totalCost: "10000", amountPaid: "7000",
      supplierType: "foreign", supplierId: "9", dollarConversionRate: "12.5",
      orderPlacementDate: "2026-02-01", estimatedArrivalDate: "2026-02-28",
      notes: "shipped late",
    })
  })

  it("brings every shared field back again", () => {
    // Every key the form can emit, in one patch — this is the test that fails
    // when a new field is added to the shared form and not mapped back.
    const draft = batchDraft(batch())
    const patch = Object.fromEntries(
      Object.keys(draft).map((k) => [k, k === "supplierId" ? "4" : `${k}-value`]),
    )
    const back = fromBatchDraft(patch as never)
    expect(Object.keys(back).sort()).toEqual(Object.keys(draft).sort())
    expect(back.supplierId).toBe(4)
    expect(back.batchName).toBe("batchName-value")
  })

  it("treats an empty supplier as NO supplier, not as absent", () => {
    // "" is a real choice — it means the farm cleared the picker.
    expect(fromBatchDraft({ supplierId: "" }).supplierId).toBeNull()
  })

  it("leaves untouched fields alone", () => {
    expect(fromBatchDraft({ batchName: "only this" })).toEqual({ batchName: "only this" })
  })

  it("renders a row with no supplier as an empty picker", () => {
    expect(batchDraft(batch({ supplierId: null })).supplierId).toBe("")
  })
})

// ---- Breed is optional ------------------------------------------------------
describe("breed", () => {
  it("does NOT block a batch with no breed", () => {
    // A farm buying from a local hatchery often does not know what it was sold,
    // and nothing downstream depends on the field.
    const b = batch({ breed: "" })
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h], flocks: [flock(b.key, h.key)],
    }
    expect(validateSetup(d, context()).errors).toEqual([])
  })

  it("mentions it as worth completing, without blocking", () => {
    const b = batch({ breed: "", supplierId: 3, costPerChick: "2" })
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h], flocks: [flock(b.key, h.key)],
    }
    const { errors, warnings } = validateSetup(d, context())
    expect(errors).toEqual([])
    expect(warnings.map((w) => w.field)).toEqual(["breed"])
    expect(warnings[0].message).toContain("no breed recorded")
  })

  it("reaches the server as an empty string, never null", () => {
    // flock.breed and mainflockbatch.breed are both NOT NULL, so a blank breed
    // has to travel as "" — a null would be rejected by the database.
    const b = batch({ breed: "" })
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h], flocks: [flock(b.key, h.key)],
    }
    expect(toRequest(d, context(), "u1", "f1").Batches[0].Breed).toBe("")
  })
})

// ---- The mortality default --------------------------------------------------
//
// Most of the gap between placement and today is mortality on a real farm, so
// the reconciliation opens with that figure filled in. It is a PRE-FILL the farm
// confirms, not a silent assumption: the number is on screen and editable.
describe("seedReconciliation", () => {
  const build = (over: Partial<FlockRow> = {}) => {
    const b = batch({ numberOfBirds: "1000" })
    const h = house({ capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "1000", currentLiveBirds: "919", ...over })],
    }
    return d
  }

  it("fills the whole difference in as mortality", () => {
    const f = seedReconciliation(build()).flocks[0]
    expect(f.historyKnown).toBe(true)
    expect(f.historicalMortality).toBe("81")
    expect(breakdown(f).mortality).toBe(81)
    expect(breakdown(f).other).toBe(0)
  })

  it("leaves a flock that lost nothing alone", () => {
    const f = seedReconciliation(build({ currentLiveBirds: "1000" })).flocks[0]
    expect(f.historyKnown).toBe(false)
    expect(f.historicalMortality).toBe("")
  })

  it("does NOT overrule a farm that said it does not know", () => {
    // The whole point of the unknown bucket is that it survives.
    const f = seedReconciliation(build({ reconciliationTouched: true, historyKnown: false })).flocks[0]
    expect(f.historyKnown).toBe(false)
    expect(f.historicalMortality).toBe("")
    expect(breakdown(f).other).toBe(81)
  })

  it("does NOT overwrite a breakdown the farm typed", () => {
    const d = build({
      reconciliationTouched: true, historyKnown: true,
      historicalMortality: "60", historicalSold: "10", historicalCulled: "5",
    })
    const f = seedReconciliation(d).flocks[0]
    expect(f.historicalMortality).toBe("60")
    expect(f.historicalSold).toBe("10")
    expect(breakdown(f).other).toBe(6)
  })

  it("re-seeds to the new difference when the counts change and nothing was edited", () => {
    // Running it again is safe, and keeps the default honest after an edit to
    // the bird counts on an earlier step.
    const once = seedReconciliation(build())
    const changed: SetupDraft = {
      ...once,
      flocks: once.flocks.map((f) => ({ ...f, currentLiveBirds: "900" })),
    }
    expect(seedReconciliation(changed).flocks[0].historicalMortality).toBe("100")
  })

  it("produces a draft that validates and sends the mortality", () => {
    const d = seedReconciliation(build())
    expect(validateSetup(d, context()).errors).toEqual([])
    const sent = toRequest(d, context(), "u1", "f1").Flocks[0]
    expect(sent.HistoryKnown).toBe(true)
    expect(sent.HistoricalMortality).toBe(81)
    expect(sent.OtherAdjustment).toBe(0)
  })
})

// ---- The workspace must not move while you type -----------------------------
//
// Regression: the strip is ordered by status, and typing into Originally Placed
// flips a batch from "unallocated" to "partial", sliding it down the list. With
// the active batch derived as "whichever is first", that reorder dragged the
// workspace onto the NEXT batch after a single keystroke.
describe("the active batch while typing", () => {
  const twoBatches = (firstPlaced: string) => {
    const b1 = batch({ batchCode: "B1", numberOfBirds: "5000" })
    const b2 = batch({ batchCode: "B2", numberOfBirds: "6000" })
    const h = house({ houseName: "Pen 1", capacity: "" })
    return {
      mode: "existing", batches: [b1, b2], houses: [h],
      flocks: [flock(b1.key, h.key, { originallyPlaced: firstPlaced, currentLiveBirds: firstPlaced })],
    } as SetupDraft
  }

  it("REORDERS the strip once the first batch has birds in it", () => {
    // The behaviour that caused the bug, pinned so it is understood rather than
    // rediscovered: B2 genuinely does sort above a part-filled B1.
    const before = visibleBatchRows(batchAllocationViews(twoBatches(""), context()), false)
    expect(before.map((v) => v.batch.batchCode)).toEqual(["B1", "B2"])

    const after = visibleBatchRows(batchAllocationViews(twoBatches("5"), context()), false)
    expect(after.map((v) => v.batch.batchCode)).toEqual(["B2", "B1"])
  })

  it("keeps a chosen batch listed even after it sorts away", () => {
    // Which is why the page commits its choice instead of reading position 0.
    const d = twoBatches("5")
    const views = batchAllocationViews(d, context())
    const chosen = views.find((v) => v.batch.batchCode === "B1")!.batch.key
    const visible = visibleBatchRows(views, false, chosen)
    expect(visible.some((v) => v.batch.key === chosen)).toBe(true)
  })

  it("keeps a reused batch listed once this allocation completes it", () => {
    // Otherwise the filter drops it and the workspace vanishes mid-keystroke.
    const existing = { batchId: 4, batchCode: "OLD", batchName: "Old", breed: "Brown", numberOfBirds: 1000 }
    const row = batchRowFromExisting(existing)
    const h = house({ houseName: "Pen 1", capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [row], houses: [h],
      flocks: [flock(row.key, h.key, { originallyPlaced: "1000", currentLiveBirds: "1000" })],
    }
    const views = batchAllocationViews(d, context({ existingBatches: [existing] }))
    expect(views[0].status).toBe("complete")
    expect(visibleBatchRows(views, false)).toHaveLength(0)
    expect(visibleBatchRows(views, false, row.key).map((v) => v.batch.batchCode)).toEqual(["OLD"])
  })
})

// ---- The allocation picker offers EMPTY pens --------------------------------
describe("penOptions", () => {
  const existingPen = (id: number, occupied: number) => ({
    houseId: id, houseName: `Pen ${id}`, capacity: 2000,
    occupied, availableCapacity: Math.max(0, 2000 - occupied),
    activeFlocks: occupied > 0 ? 1 : 0,
  })

  const build = () => {
    const full = existingPen(1, 2000)
    const partly = existingPen(2, 500)
    const empty = existingPen(3, 0)
    const d: SetupDraft = {
      mode: "existing", batches: [], flocks: [],
      houses: [full, partly, empty].map(houseRowFromExisting),
    }
    return { d, ctx: context({ existingHouses: [full, partly, empty] }) }
  }

  it("withholds only the FULL pens", () => {
    // Pen 1 is full; Pen 2 holds 500 of 2,000 and is still a real choice.
    const { d, ctx } = build()
    const visible = penOptions(houseRowViews(d, ctx))
    expect(visible.map((v) => v.row.houseName)).toEqual(["Pen 2", "Pen 3"])
  })

  it("offers a part-full pen, because several flocks may share one", () => {
    const { d, ctx } = build()
    const partly = houseRowViews(d, ctx).find((v) => v.row.houseName === "Pen 2")!
    expect(partly.hasRoom).toBe(true)
    expect(partly.isEmpty).toBe(false)
    expect(penOptions(houseRowViews(d, ctx)).some((v) => v.row.houseName === "Pen 2")).toBe(true)
  })

  it("keeps a row's OWN pen listed after that row fills it", () => {
    // Otherwise choosing a pen removes it from the picker that is showing it,
    // and the field blanks itself.
    const empty = existingPen(3, 0)
    const b = batch({ numberOfBirds: "2000" })
    const h = houseRowFromExisting(empty)
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "2000", currentLiveBirds: "2000" })],
    }
    const views = houseRowViews(d, context({ existingHouses: [empty] }))
    expect(views[0].hasRoom).toBe(false)
    expect(penOptions(views)).toHaveLength(0)
    expect(penOptions(views, h.key).map((v) => v.row.houseName)).toEqual(["Pen 3"])
  })

  it("always offers a pen with no capacity recorded", () => {
    const noCap = { houseId: 9, houseName: "Pen 9", capacity: null, occupied: 4000, availableCapacity: null, activeFlocks: 2 }
    const d: SetupDraft = {
      mode: "existing", batches: [], flocks: [], houses: [houseRowFromExisting(noCap)],
    }
    expect(penOptions(houseRowViews(d, context({ existingHouses: [noCap] })))).toHaveLength(1)
  })

  it("offers a pen this setup is about to create", () => {
    const d: SetupDraft = {
      mode: "existing", batches: [], flocks: [],
      houses: [{ ...emptyHouse("2000", ""), houseName: "Pen 9" }],
    }
    expect(penOptions(houseRowViews(d, context()))).toHaveLength(1)
  })
})

// ---- A generated flock name follows its pen ---------------------------------
//
// Regression: the name was filled in on the FIRST pen choice and then frozen, so
// moving a flock from Pen 3 to Pen 5 left it called "B1 - Pen 3" — a label that
// reads like a fact and is wrong.
describe("renameForHouse", () => {
  it("names a flock that has no name yet", () => {
    expect(renameForHouse("", "B1", "", "Pen 3")).toBe("B1 - Pen 3")
  })

  it("FOLLOWS the pen when the name is still the generated one", () => {
    expect(renameForHouse("B1 - Pen 3", "B1", "Pen 3", "Pen 5")).toBe("B1 - Pen 5")
  })

  it("leaves a name the farm wrote alone", () => {
    expect(renameForHouse("Grandma's layers", "B1", "Pen 3", "Pen 5")).toBe("Grandma's layers")
  })

  it("still recognises its own name through case and spacing", () => {
    expect(renameForHouse("b1 -  PEN 3", "B1", "Pen 3", "Pen 5")).toBe("B1 - Pen 5")
  })

  it("copes with a batch that has no code yet", () => {
    expect(renameForHouse("Pen 3", "", "Pen 3", "Pen 5")).toBe("Pen 5")
  })

  it("copes with a pen that has no name yet", () => {
    expect(renameForHouse("B1 - Pen 3", "B1", "Pen 3", "")).toBe("B1")
  })

  it("does not clear a typed name when the pen is cleared", () => {
    expect(renameForHouse("Grandma's layers", "B1", "Pen 3", "")).toBe("Grandma's layers")
  })
})

// ---- The Batches step shows only what is being created ----------------------
describe("visibleBatchEditRows", () => {
  const existing = { batchId: 7, batchCode: "OLD", batchName: "Old", breed: "Brown", numberOfBirds: 1000 }

  const build = () => {
    const d: SetupDraft = {
      mode: "existing", houses: [], flocks: [],
      batches: [batchRowFromExisting(existing), batch({ batchCode: "NEW" })],
    }
    return d
  }

  it("hides batches the farm already has", () => {
    const visible = visibleBatchEditRows(batchEditRows(build()), false)
    expect(visible.map((v) => v.row.batchCode)).toEqual(["NEW"])
  })

  it("shows them when asked", () => {
    expect(visibleBatchEditRows(batchEditRows(build()), true)).toHaveLength(2)
  })

  it("keeps the draft index, so editing the right row still works", () => {
    // The step renders a filtered list but patches by position in the draft.
    const visible = visibleBatchEditRows(batchEditRows(build()), false)
    expect(visible[0].index).toBe(1)
  })

  it("reports how many are out of sight", () => {
    expect(summarizeBatchEditRows(batchEditRows(build()))).toEqual({ total: 2, existing: 1 })
  })

  it("leaves a hidden batch in the draft, so allocation can still use it", () => {
    // A farm coming back to place the rest of an old batch depends on this.
    const d = build()
    expect(visibleBatchEditRows(batchEditRows(d), false)).toHaveLength(1)
    expect(d.batches).toHaveLength(2)

    const ctx = context({ existingBatches: [existing], allocatedByBatchId: { 7: 400 } })
    const allocatable = visibleBatchRows(batchAllocationViews(d, ctx), false)
    expect(allocatable.map((v) => v.batch.batchCode).sort()).toEqual(["NEW", "OLD"])
  })

  it("says nothing when the farm has no batches of its own", () => {
    const d: SetupDraft = { mode: "existing", houses: [], flocks: [], batches: [batch()] }
    expect(summarizeBatchEditRows(batchEditRows(d)).existing).toBe(0)
  })
})

// ---- Auto-filling the pens a farm has ticked --------------------------------
describe("distributePensEvenly", () => {
  const threePens = () => {
    const b = batch({ numberOfBirds: "5000" })
    const pens = [1, 2, 3].map((n) => house({ houseName: `Pen ${n}`, capacity: "2000" }))
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: pens,
      flocks: pens.map((h, i) => flock(b.key, h.key, {
        name: `B - Pen ${i + 1}`, originallyPlaced: "", currentLiveBirds: "",
      })),
    }
    return { d, b }
  }

  it("splits evenly and hands the remainder to the first rows", () => {
    const { d, b } = threePens()
    const out = distributePensEvenly(d, b.key, 5000)
    expect(out.flocks.map((f) => f.originallyPlaced)).toEqual(["1667", "1667", "1666"])
  })

  it("sets standing birds equal to placed — a flock that has lost nothing", () => {
    const { d, b } = threePens()
    const out = distributePensEvenly(d, b.key, 3000)
    expect(out.flocks.every((f) => f.originallyPlaced === f.currentLiveBirds)).toBe(true)
  })

  it("leaves another batch's rows alone", () => {
    const { d, b } = threePens()
    const other = batch({ batchCode: "OTHER" })
    d.batches.push(other)
    d.flocks.push(flock(other.key, d.houses[0].key, { name: "keep", originallyPlaced: "77" }))
    const out = distributePensEvenly(d, b.key, 3000)
    expect(out.flocks.find((f) => f.name === "keep")!.originallyPlaced).toBe("77")
  })

  it("does nothing when no pens are ticked", () => {
    const b = batch()
    const d: SetupDraft = { mode: "existing", batches: [b], houses: [], flocks: [] }
    expect(distributePensEvenly(d, b.key, 5000)).toBe(d)
  })
})

describe("fillPensToCapacity", () => {
  it("fills each pen to its room, in order, until the birds run out", () => {
    const b = batch({ numberOfBirds: "5000" })
    const pens = [house({ houseName: "Pen 1", capacity: "2000" }),
                  house({ houseName: "Pen 2", capacity: "2000" }),
                  house({ houseName: "Pen 3", capacity: "2000" })]
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: pens,
      flocks: pens.map((h, i) => flock(b.key, h.key, {
        name: `B - Pen ${i + 1}`, originallyPlaced: "", currentLiveBirds: "",
      })),
    }
    const out = fillPensToCapacity(d, context(), b.key, 5000)
    // 2,000 + 2,000 + the last 1,000.
    expect(out.flocks.map((f) => f.originallyPlaced)).toEqual(["2000", "2000", "1000"])
  })

  it("counts what the farm already has in a pen", () => {
    const pen = { houseId: 1, houseName: "Pen 1", capacity: 2000, occupied: 1500, availableCapacity: 500, activeFlocks: 1 }
    const b = batch({ numberOfBirds: "5000" })
    const h = houseRowFromExisting(pen)
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "", currentLiveBirds: "" })],
    }
    const out = fillPensToCapacity(d, context({ existingHouses: [pen] }), b.key, 5000)
    expect(out.flocks[0].originallyPlaced).toBe("500")
  })

  it("gives an unconstrained pen whatever is left", () => {
    const b = batch({ numberOfBirds: "5000" })
    const h = house({ houseName: "Pen 1", capacity: "" })
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: [h],
      flocks: [flock(b.key, h.key, { originallyPlaced: "", currentLiveBirds: "" })],
    }
    expect(fillPensToCapacity(d, context(), b.key, 5000).flocks[0].originallyPlaced).toBe("5000")
  })

  it("is repeatable — running it twice gives the same answer", () => {
    const b = batch({ numberOfBirds: "5000" })
    const pens = [house({ houseName: "Pen 1", capacity: "2000" }), house({ houseName: "Pen 2", capacity: "2000" })]
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: pens,
      flocks: pens.map((h, i) => flock(b.key, h.key, { name: `P${i}`, originallyPlaced: "", currentLiveBirds: "" })),
    }
    const once = fillPensToCapacity(d, context(), b.key, 5000)
    const twice = fillPensToCapacity(once, context(), b.key, 5000)
    expect(twice.flocks.map((f) => f.originallyPlaced)).toEqual(once.flocks.map((f) => f.originallyPlaced))
  })

  it("leaves nothing for a pen once the birds are gone", () => {
    const b = batch({ numberOfBirds: "1000" })
    const pens = [house({ houseName: "Pen 1", capacity: "2000" }), house({ houseName: "Pen 2", capacity: "2000" })]
    const d: SetupDraft = {
      mode: "existing", batches: [b], houses: pens,
      flocks: pens.map((h, i) => flock(b.key, h.key, { name: `P${i}`, originallyPlaced: "", currentLiveBirds: "" })),
    }
    const out = fillPensToCapacity(d, context(), b.key, 1000)
    expect(out.flocks.map((f) => f.originallyPlaced)).toEqual(["1000", ""])
  })
})

// ---- The breakdown balances itself ------------------------------------------
//
// Mortality opens holding the whole gap, so typing into Sold on top of it used
// to claim more birds than went missing and earn an error for doing the
// obviously right thing.
describe("balanceBreakdown", () => {
  // 1,000 placed, 919 standing: 81 to account for, all of it mortality.
  const seeded = (over: Partial<FlockRow> = {}) => flock("b", "h", {
    originallyPlaced: "1000", currentLiveBirds: "919",
    historyKnown: true, historicalMortality: "81", ...over,
  })

  it("takes birds OUT of mortality when another bucket claims them", () => {
    const patch = balanceBreakdown(seeded(), { historicalSold: "10" })
    expect(patch.historicalSold).toBe("10")
    expect(patch.historicalMortality).toBe("71")
  })

  it("gives them BACK when that bucket is lowered again", () => {
    const after = { ...seeded(), historicalSold: "10", historicalMortality: "71" }
    expect(balanceBreakdown(after, { historicalSold: "4" }).historicalMortality).toBe("77")
  })

  it("gives them all back when the bucket is cleared", () => {
    const after = { ...seeded(), historicalSold: "10", historicalMortality: "71" }
    expect(balanceBreakdown(after, { historicalSold: "" }).historicalMortality).toBe("81")
  })

  it("balances against ALL the other buckets, not just the one edited", () => {
    const after = { ...seeded(), historicalSold: "10", historicalCulled: "5", historicalMortality: "66" }
    expect(balanceBreakdown(after, { historicalTransferred: "6" }).historicalMortality).toBe("60")
  })

  it("leaves the others alone when mortality itself is typed", () => {
    // Stating what died is a statement; the rest becomes the unknown remainder.
    const patch = balanceBreakdown(seeded({ historicalSold: "10" }), { historicalMortality: "50" })
    expect(patch.historicalMortality).toBe("50")
    expect(patch.historicalSold).toBeUndefined()
    expect(breakdown({ ...seeded({ historicalSold: "10" }), historicalMortality: "50" }).other).toBe(21)
  })

  it("bottoms out at zero rather than going negative", () => {
    const patch = balanceBreakdown(seeded(), { historicalSold: "500" })
    expect(patch.historicalMortality).toBe("0")
  })

  it("still reports an over-statement once the others alone exceed the gap", () => {
    const f = { ...seeded(), ...balanceBreakdown(seeded(), { historicalSold: "500" }) } as FlockRow
    const b = breakdown(f)
    expect(b.overStated).toBe(true)
    expect(b.stated).toBe(500)
  })

  it("marks the flock as worked on, so the mortality default stops re-seeding", () => {
    expect(balanceBreakdown(seeded(), { historicalSold: "10" }).reconciliationTouched).toBe(true)
  })

  it("keeps the whole gap accounted for", () => {
    const f = { ...seeded(), ...balanceBreakdown(seeded(), { historicalSold: "10" }) } as FlockRow
    const b = breakdown(f)
    expect(b.mortality + b.sold + b.culled + b.transferred + b.other).toBe(81)
    expect(b.other).toBe(0)
  })
})
