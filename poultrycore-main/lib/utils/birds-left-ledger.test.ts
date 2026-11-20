import { describe, expect, it } from "vitest"
import { buildBirdsLeftLedger, summarizeBirdsLeftByFlock, type FlockPositionLookup } from "./birds-left-ledger"
import type { Flock } from "@/lib/api/flock"
import type { FlockPositionRow } from "@/lib/api/flock-positions"

const flock = (flockId: number, quantity: number) =>
  ({ flockId, name: `F${flockId}`, quantity, startDate: "2026-01-01T00:00:00" }) as unknown as Flock

const pos = (over: Partial<FlockPositionRow>): FlockPositionRow => ({
  flockId: 1, batchId: 1, isClosed: false, isDeleted: false, hasOpeningPosition: true, historyKnown: true,
  originallyPlaced: 0, openingMortality: 0, openingSold: 0, openingCulled: 0, openingTransferred: 0,
  openingOther: 0, openingLiveBirds: 0, recordedMortality: 0, productionRecordCount: 0, lastCountedBirds: 0,
  lastCountDate: null, correction: 0, birdsSold: 0, birdsCulled: 0, birdsTransferred: 0, currentLiveBirds: 0,
  startedBirds: 0, ...over,
})

describe("Birds tracker with the opening position (419)", () => {
  it("goes IN with the birds originally placed and OUT with the history (B1 - Pen 2)", () => {
    // flock.quantity is the opening LIVE count (941); 967 were placed, 26 died before setup.
    const positions: FlockPositionLookup = new Map([[1, pos({ originallyPlaced: 967, openingLiveBirds: 941, openingMortality: 26 })]])
    const [s] = summarizeBirdsLeftByFlock([flock(1, 941)], [], [], positions)
    expect(s.placedIn).toBe(967)
    expect(s.totalMortalityOut).toBe(26)
    expect(s.birdsLeftCalculated).toBe(941)
  })

  it("puts culled / transferred / other history in its own column", () => {
    const positions: FlockPositionLookup = new Map([[1, pos({ originallyPlaced: 1000, openingLiveBirds: 940,
      openingMortality: 20, openingSold: 10, openingCulled: 15, openingTransferred: 5, openingOther: 10 })]])
    const [s] = summarizeBirdsLeftByFlock([flock(1, 940)], [], [], positions)
    expect(s).toMatchObject({ placedIn: 1000, totalMortalityOut: 20, totalBirdSalesOut: 10, totalOtherOut: 30, birdsLeftCalculated: 940 })
  })

  it("starts from the opening live count when the history is not known, with no history rows", () => {
    const positions: FlockPositionLookup = new Map([[1, pos({ historyKnown: false, originallyPlaced: 1000, openingLiveBirds: 900, openingOther: 100 })]])
    const ledger = buildBirdsLeftLedger([flock(1, 900)], [], [], positions)
    expect(ledger).toHaveLength(1)
    expect(ledger[0]).toMatchObject({ type: "IN", quantity: 900 })
  })

  it("is unchanged without positions (API before 419)", () => {
    const [s] = summarizeBirdsLeftByFlock([flock(1, 941)], [], [])
    expect(s.placedIn).toBe(941)
    expect(s.totalOtherOut).toBe(0)
  })
})

describe("Birds tracker with bird count corrections (440)", () => {
  const rec = (flockId: number, left: number, mortality = 0) =>
    ({ id: 10 + flockId, flockId, date: "2026-11-10T00:00:00", mortality, noOfBirdsLeft: left, noOfBirds: left + mortality }) as any

  it("adds a count up as IN and a count down as OUT, and matches the latest record", () => {
    // 1,000 placed; Batch Bird Count: +199 (applied to the latest record -> 1,199 left).
    const positions: FlockPositionLookup = new Map([[1, pos({ originallyPlaced: 1000, openingLiveBirds: 1000 })]])
    const up = [{ birdAdjustmentId: 7, adjustmentDate: "2026-11-16", flockId: 1, quantity: 199, productionRecordId: 11, note: "MSM-00008" }]
    const ledger = buildBirdsLeftLedger([flock(1, 1000)], [rec(1, 1199)], [], positions, up)
    expect(ledger.find((r) => r.category === "Count correction")).toMatchObject({ type: "IN", quantity: 199, description: "MSM-00008" })
    const [s] = summarizeBirdsLeftByFlock([flock(1, 1000)], [rec(1, 1199)], [], positions, up)
    expect(s).toMatchObject({ totalCorrection: 199, birdsLeftCalculated: 1199, birdsLeftFromLatestLog: 1199 })

    const down = [{ birdAdjustmentId: 8, adjustmentDate: "2026-11-16", flockId: 1, quantity: -50, productionRecordId: 11 }]
    const [d] = summarizeBirdsLeftByFlock([flock(1, 1000)], [rec(1, 950)], [], positions, down)
    expect(d).toMatchObject({ totalCorrection: -50, birdsLeftCalculated: 950 })
  })

  it("a correction and its reversal cancel out", () => {
    const positions: FlockPositionLookup = new Map([[1, pos({ originallyPlaced: 1000, openingLiveBirds: 1000 })]])
    const both = [
      { birdAdjustmentId: 1, adjustmentDate: "2026-11-16", flockId: 1, quantity: -50, productionRecordId: 11 },
      { birdAdjustmentId: 2, adjustmentDate: "2026-11-16", flockId: 1, quantity: 50, productionRecordId: 11 },
    ]
    const [s] = summarizeBirdsLeftByFlock([flock(1, 1000)], [rec(1, 1000)], [], positions, both)
    expect(s).toMatchObject({ totalCorrection: 0, birdsLeftCalculated: 1000 })
  })

  it("a flock with no production record: counted once (position keeps it out of originally placed)", () => {
    // flock.quantity 1,010 = 1,000 placed + 10 counted; the position says 1,000 placed.
    const positions: FlockPositionLookup = new Map([[1, pos({ originallyPlaced: 1000, openingLiveBirds: 1000 })]])
    const c = [{ birdAdjustmentId: 3, adjustmentDate: "2026-11-16", flockId: 1, quantity: 10, productionRecordId: null }]
    const [s] = summarizeBirdsLeftByFlock([flock(1, 1010)], [], [], positions, c)
    expect(s).toMatchObject({ placedIn: 1000, totalCorrection: 10, birdsLeftCalculated: 1010 })
    // Without positions flock.quantity already holds it: not added again.
    const [n] = summarizeBirdsLeftByFlock([flock(1, 1010)], [], [], undefined, c)
    expect(n).toMatchObject({ placedIn: 1010, totalCorrection: 0, birdsLeftCalculated: 1010 })
  })
})
