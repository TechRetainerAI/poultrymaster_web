import { describe, expect, it } from "vitest"
import type { BatchBirdReconciliationRow } from "@/lib/api/bird-reconciliation"
import { batchBirdTotals, farmBirdTotals, isBatchNotArrived } from "./farm-bird-totals"

/** A batch row with only what the totals read; the rest zero. */
function batch(p: Partial<BatchBirdReconciliationRow>): BatchBirdReconciliationRow {
  return {
    batchId: 1, batchCode: "B", batchName: "B", startDate: "2026-01-01", isHistorical: false,
    originalBirds: 0, originallyAllocated: 0, flockCount: 1, batchSold: 0, flockSold: 0,
    batchMortality: 0, batchCulled: 0, batchTransferred: 0, batchOtherRemovals: 0, batchAdditions: 0,
    unallocatedPool: 0, unallocatedLive: 0, unexplained: 0, flockLiveBirds: 0, totalLiveBirds: 0,
    flockHistoricalReductions: 0, historicalSaleBirds: 0, historicalSaleValue: 0, historicalReceived: 0,
    historicalOwed: 0, status: "FullyAccountedFor" as BatchBirdReconciliationRow["status"],
    lastReconciledAt: null, lastReconciliationNo: null,
    ...p,
  }
}

// Evans Jones Farms, from the Batches page: 73,000 bought, 8,500 sold (all
// from Batch 1 before it went into flocks), 8,500 died before tracking began.
const evans = [
  batch({ batchId: 1, originalBirds: 16000, batchSold: 8500, flockHistMortality: 1000, totalLiveBirds: 6500 }),
  batch({ batchId: 5, originalBirds: 10000, totalLiveBirds: 10000 }),
  batch({ batchId: 4, originalBirds: 17000, flockHistMortality: 1000, totalLiveBirds: 16000 }),
  batch({ batchId: 3, originalBirds: 10000, flockHistMortality: 2500, totalLiveBirds: 7500 }),
  batch({ batchId: 2, originalBirds: 20000, flockHistMortality: 4000, totalLiveBirds: 16000 }),
]

describe("farmBirdTotals", () => {
  it("counts birds sold from a batch before placing, and historical deaths", () => {
    expect(farmBirdTotals(evans, [])).toEqual({
      bought: 73000, died: 8500, sold: 8500, other: 0, left: 56000, notInFlock: 0,
    })
  })

  it("gives a batch its birds left as bought − sold − died", () => {
    const t = batchBirdTotals(evans[0])
    expect(t.left).toBe(6500)
    expect(t.bought - t.sold - t.died - t.other).toBe(t.left)
  })

  it("puts what the named causes do not explain into other, so the sum still holds", () => {
    const t = batchBirdTotals(batch({ originalBirds: 1000, flockRecordedMortality: 4, totalLiveBirds: 496 }))
    expect(t.other).toBe(500)
    expect(t.bought - t.sold - t.died - t.other).toBe(t.left)
  })

  it("adds a flock whose batch no longer exists", () => {
    const flockD = {
      flockId: 3066, batchId: 57, isDeleted: false, isClosed: false, historyKnown: true,
      originallyPlaced: 2000, openingLiveBirds: 2000, openingMortality: 0, openingSold: 0,
      openingCulled: 0, openingTransferred: 0, openingOther: 0, recordedMortality: 1001,
      birdsSold: 0, birdsCulled: 0, birdsTransferred: 0, currentLiveBirds: 999,
    } as unknown as Parameters<typeof farmBirdTotals>[1] extends Iterable<infer T> ? T : never
    const t = farmBirdTotals(evans, [flockD])!
    expect(t.bought).toBe(75000)
    expect(t.left).toBe(56999)
    expect(t.died).toBe(9501)
  })

  it("leaves out the unplaced birds of a batch that has not arrived", () => {
    const rows = [...evans, batch({ batchId: 9, originalBirds: 1000, unallocatedLive: 1000, totalLiveBirds: 1000 })]
    expect(farmBirdTotals(rows, [])!.left).toBe(57000)
    const t = farmBirdTotals(rows, [], new Set([9]))!
    expect(t).toEqual({ bought: 73000, died: 8500, sold: 8500, other: 0, left: 56000, notInFlock: 0 })
  })

  it("knows a batch has not arrived from Pending or a later start date", () => {
    const today = new Date(2026, 10, 13)
    expect(isBatchNotArrived({ status: "Pending", startDate: "2026-11-01" }, today)).toBe(true)
    expect(isBatchNotArrived({ status: "active", startDate: "2026-11-14T00:00:00" }, today)).toBe(true)
    expect(isBatchNotArrived({ status: "active", startDate: "2026-11-13T00:00:00" }, today)).toBe(false)
    expect(isBatchNotArrived({ status: "active", startDate: "2026-11-01" }, today)).toBe(false)
  })

  it("is null when nothing loaded", () => {
    expect(farmBirdTotals([], [])).toBeNull()
  })
})
