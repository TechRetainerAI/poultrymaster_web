import type { BatchBirdReconciliationRow } from "@/lib/api/bird-reconciliation"
import type { FlockPositionRow } from "@/lib/api/flock-positions"
import { flockLifetime } from "@/lib/flocks/bird-position"

/**
 * The farm's birds from start to now, the way the flock and batch reports
 * count them:
 *
 *   bought = died + sold + other + left
 *
 * Built from the batch reconciliation (migrations 413/420), which follows
 * every batch bird whether it went into a flock or not -- so birds sold or
 * lost straight from a batch, before it was divided into flocks, are counted.
 * Summing flocks alone misses those (a batch of 16,000 that sold 8,500 before
 * placing shows only 7,500), which is what made the Flocks and Batches cards
 * disagree with the reports.
 *
 * Flocks that belong to no batch are added from their own bird position.
 */
export interface FarmBirdTotals {
  /** Every bird the farm received: batch sizes, plus flocks with no batch. */
  bought: number
  /** Before placing, before tracking began (Initial Farm Setup), and recorded since. */
  died: number
  /** Before placing, before tracking began, and posted sales since. */
  sold: number
  /**
   * Everything else (signed): culled, transferred, birds in flocks that were
   * deleted, count corrections, and birds never accounted for.
   */
  other: number
  /** Alive now: in flocks, plus batch birds not yet in a flock. */
  left: number
  /** Of `left`, the batch birds not yet in any flock. */
  notInFlock: number
}

/** One batch's figures, same rule. Null-safe for an API that predates 420. */
export function batchBirdTotals(r: BatchBirdReconciliationRow): FarmBirdTotals {
  const bought = r.originalBirds ?? 0
  const died = (r.batchMortality ?? 0) + (r.flockHistMortality ?? 0) + (r.flockRecordedMortality ?? 0)
  const sold = (r.batchSold ?? 0) + (r.flockSold ?? 0)
  const left = r.totalLiveBirds ?? 0
  return {
    bought, died, sold, left,
    notInFlock: Math.max(0, r.unallocatedLive ?? 0),
    // Whatever the named causes do not explain, so the four always add up.
    other: bought - died - sold - left,
  }
}

/**
 * A batch whose birds are not on the farm yet: still Pending, or starting on a
 * later day. Its birds that are not in a flock are left out of every total --
 * they are bought, not alive on the farm.
 */
export function isBatchNotArrived(
  batch: { status?: string | null; startDate?: string | null },
  today: Date = new Date(),
): boolean {
  if ((batch.status ?? "").toLowerCase() === "pending") return true
  const day = (batch.startDate ?? "").slice(0, 10)
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return false
  const pad = (n: number) => String(n).padStart(2, "0")
  const todayKey = `${today.getFullYear()}-${pad(today.getMonth() + 1)}-${pad(today.getDate())}`
  return day > todayKey
}

/**
 * The batch's figures with its not-yet-arrived birds taken out: only the
 * birds not in any flock, since a flock is a record of birds that did arrive.
 */
function withoutNotArrived(b: FarmBirdTotals): FarmBirdTotals {
  const waiting = b.notInFlock
  return { ...b, bought: b.bought - waiting, left: b.left - waiting, notInFlock: 0 }
}

/** Null when there is nothing to total from (the reconciliation did not load). */
export function farmBirdTotals(
  reconRows: Iterable<BatchBirdReconciliationRow>,
  positions: Iterable<FlockPositionRow>,
  /** Batches whose birds have not arrived yet -- see isBatchNotArrived. */
  notArrivedBatchIds: ReadonlySet<number> = new Set(),
): FarmBirdTotals | null {
  const t: FarmBirdTotals = { bought: 0, died: 0, sold: 0, other: 0, left: 0, notInFlock: 0 }
  let any = false
  const batchIds = new Set<number>()
  for (const r of reconRows) {
    const raw = batchBirdTotals(r)
    const b = notArrivedBatchIds.has(r.batchId) ? withoutNotArrived(raw) : raw
    t.bought += b.bought; t.died += b.died; t.sold += b.sold
    t.other += b.other; t.left += b.left; t.notInFlock += b.notInFlock
    batchIds.add(r.batchId)
    any = true
  }
  // Flocks the batch figures do not cover: no batch, or a batch that no
  // longer exists (deleted while the flock was kept).
  for (const p of positions) {
    if (p.isDeleted || (p.batchId != null && batchIds.has(p.batchId))) continue
    const l = flockLifetime(p)
    t.bought += l.started; t.died += l.deaths; t.sold += l.sold; t.left += l.live
    t.other += l.started - l.deaths - l.sold - l.live
    any = true
  }
  return any ? t : null
}
