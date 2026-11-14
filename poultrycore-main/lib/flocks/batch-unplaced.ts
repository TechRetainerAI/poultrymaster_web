import type { BatchBirdReconciliationRow } from "@/lib/api/bird-reconciliation"
import type { BirdsLeftLedgerRow } from "@/lib/utils/birds-left-ledger"

/**
 * A batch's birds that never went into a flock, and what happened to them --
 * the part of a batch the flock-by-flock figures cannot see. A batch of
 * 73,000 that sold 8,500 before placing 64,500 into pens: flocks alone show
 * 64,500 in and never the 8,500 sold.
 *
 *   in    = bought - placed into flocks   (from the batch reconciliation)
 *   out   = died + sold before placing, + other (culled, moved, not yet
 *           accounted for)
 *   left  = still alive and not in a flock
 */
export interface BatchUnplacedSummary {
  batchId: number
  label: string
  startDate: string
  placedIn: number
  deaths: number
  sales: number
  other: number
  left: number
}

export function batchUnplacedSummaries(
  rows: Iterable<BatchBirdReconciliationRow>,
  /** Batches whose birds are not on the farm yet (isBatchNotArrived): their waiting birds are left out. */
  notArrivedBatchIds: ReadonlySet<number> = new Set(),
): BatchUnplacedSummary[] {
  const out: BatchUnplacedSummary[] = []
  for (const r of rows) {
    const waiting = notArrivedBatchIds.has(r.batchId) ? Math.max(0, r.unallocatedLive ?? 0) : 0
    const placedIn = (r.originalBirds ?? 0) - (r.originallyAllocated ?? 0) - waiting
    const deaths = r.batchMortality ?? 0
    const sales = r.batchSold ?? 0
    const left = Math.max(0, r.unallocatedLive ?? 0) - waiting
    const other = placedIn - deaths - sales - left
    if (placedIn === 0 && deaths === 0 && sales === 0 && left === 0) continue
    out.push({
      batchId: r.batchId,
      label: r.batchCode || r.batchName || `Batch #${r.batchId}`,
      startDate: (r.startDate ?? "").split("T")[0],
      placedIn, deaths, sales, other, left,
    })
  }
  return out
}

/** The same figures as ledger rows: one IN, and an OUT per cause. flockId is -batchId. */
export function batchUnplacedLedger(summaries: BatchUnplacedSummary[]): BirdsLeftLedgerRow[] {
  const rows: BirdsLeftLedgerRow[] = []
  for (const s of summaries) {
    const base = { date: s.startDate, flockId: -s.batchId, flockName: `${s.label} · not placed in a flock` }
    if (s.placedIn > 0) rows.push({ ...base, id: `in-batch-${s.batchId}`, type: "IN", category: "Placement", quantity: s.placedIn,
      description: `Batch ${s.label}: birds bought but never placed in a flock` })
    if (s.deaths > 0) rows.push({ ...base, id: `out-batch-${s.batchId}-death`, type: "OUT", category: "Mortality", quantity: s.deaths,
      description: `Batch ${s.label}: died before being placed in a flock` })
    if (s.sales > 0) rows.push({ ...base, id: `out-batch-${s.batchId}-sale`, type: "OUT", category: "Bird sale", quantity: s.sales,
      description: `Batch ${s.label}: sold before being placed in a flock` })
    if (s.other > 0) rows.push({ ...base, id: `out-batch-${s.batchId}-other`, type: "OUT", category: "Cull / transfer / other", quantity: s.other,
      description: `Batch ${s.label}: culled, moved or not yet accounted for (Batch Bird Reconciliation)` })
  }
  return rows
}
