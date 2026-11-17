import { describe, expect, it } from "vitest"
import type { BatchBirdReconciliationRow } from "@/lib/api/bird-reconciliation"
import { batchUnplacedLedger, batchUnplacedSummaries } from "./batch-unplaced"

const row = (o: Partial<BatchBirdReconciliationRow>): BatchBirdReconciliationRow => ({
  batchId: 1, batchCode: "B1", batchName: "Batch 1", startDate: "2026-05-19T00:00:00", isHistorical: true,
  originalBirds: 0, originallyAllocated: 0, flockCount: 0, batchSold: 0, batchMortality: 0, batchCulled: 0,
  batchTransferred: 0, batchOtherRemovals: 0, batchAdditions: 0, unallocatedPool: 0, unallocatedLive: 0,
  unexplained: 0, flockLiveBirds: 0, totalLiveBirds: 0, flockHistoricalReductions: 0, historicalSaleBirds: 0,
  historicalSaleValue: 0, historicalReceived: 0, historicalOwed: 0, status: "FullyAccountedFor" as never,
  lastReconciledAt: null, lastReconciliationNo: null, ...o,
})

describe("batchUnplacedSummaries", () => {
  it("a batch that sold birds before placing the rest (Evans Jones shape)", () => {
    const [s] = batchUnplacedSummaries([row({ originalBirds: 73000, originallyAllocated: 64500, batchSold: 8500 })])
    expect(s).toMatchObject({ placedIn: 8500, sales: 8500, deaths: 0, other: 0, left: 0 })
    const ledger = batchUnplacedLedger([s])
    expect(ledger.filter((r) => r.type === "IN").reduce((a, r) => a + r.quantity, 0)).toBe(8500)
    expect(ledger.filter((r) => r.type === "OUT").reduce((a, r) => a + r.quantity, 0)).toBe(8500)
  })

  it("skips a batch fully placed into flocks", () => {
    expect(batchUnplacedSummaries([row({ originalBirds: 1000, originallyAllocated: 1000 })])).toEqual([])
  })

  it("birds still waiting in the batch are left; a batch not arrived yet drops them", () => {
    const r = row({ originalBirds: 1000, originallyAllocated: 0, unallocatedLive: 1000 })
    expect(batchUnplacedSummaries([r])[0]).toMatchObject({ placedIn: 1000, left: 1000, other: 0 })
    expect(batchUnplacedSummaries([r], new Set([1]))).toEqual([])
  })
})
