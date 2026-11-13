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
