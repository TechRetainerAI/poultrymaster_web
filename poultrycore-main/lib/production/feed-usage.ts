// Feed Usage from stock (migration 389) — pure helpers for the entry form.
//
// A batch entry is stored per flock: the form splits each feed's total across
// the batch's flocks, and the server only accepts lines that add up. Splitting
// is done in grams (whole thousandths of a kg) so the parts always sum to the
// total exactly; any leftover gram goes to the flocks with the largest
// remainder, then the most birds.

import type { FeedRecordStatus, FeedUsageCandidate } from "@/lib/api/feed-usage-entries"

export type SplitBasis = "Birds" | "Equal" | "Manual"

export interface SplitFlock {
  flockId: number
  birds: number | null
}

/** Split `totalKg` across flocks. Returns kg per flockId, summing exactly to the total (3 dp). */
export function splitFeed(totalKg: number, flocks: SplitFlock[], basis: Exclude<SplitBasis, "Manual">): Record<number, number> {
  const out: Record<number, number> = {}
  if (!(totalKg > 0) || flocks.length === 0) {
    for (const f of flocks) out[f.flockId] = 0
    return out
  }
  const grams = Math.round(totalKg * 1000)
  const weights = flocks.map((f) => (basis === "Equal" ? 1 : Math.max(f.birds ?? 0, 0)))
  const sumW = weights.reduce((a, b) => a + b, 0)
  // No birds known anywhere: fall back to an equal split rather than nothing.
  const w = sumW > 0 ? weights : flocks.map(() => 1)
  const total = w.reduce((a, b) => a + b, 0)

  const exact = w.map((x) => (grams * x) / total)
  const base = exact.map((x) => Math.floor(x))
  let left = grams - base.reduce((a, b) => a + b, 0)
  const order = exact
    .map((x, i) => ({ i, rem: x - base[i], birds: flocks[i].birds ?? 0 }))
    .sort((a, b) => b.rem - a.rem || b.birds - a.birds || a.i - b.i)
  for (let k = 0; left > 0; k = (k + 1) % order.length, left--) base[order[k].i]++

  flocks.forEach((f, i) => { out[f.flockId] = base[i] / 1000 })
  return out
}

/** Sum of kg, rounded to grams so float noise never fails a comparison. */
export function sumKg(values: number[]): number {
  return Math.round(values.reduce((a, b) => a + (Number.isFinite(b) ? b : 0), 0) * 1000) / 1000
}

/** What saving will do to a flock's production record, in plain words. */
export function recordStatusNote(status: FeedRecordStatus): string {
  switch (status) {
    case "Recorded":
      return "Added to this flock's production record for the day."
    case "FeedOnly":
      return "This flock already has feed recorded today, but no production yet. The feed is added to it."
    case "None":
      return "No production record yet. A feed-only record is made; production for this day still shows as missing until it is filled in."
    case "Duplicate":
      return "This flock has more than one production record for the day. Fix the duplicate before recording feed."
  }
}

export function canFeed(c: Pick<FeedUsageCandidate, "recordStatus">): boolean {
  return c.recordStatus !== "Duplicate"
}

export interface BatchOption {
  batchId: number
  batchName: string
  flocks: FeedUsageCandidate[]
}

/** Batches that have at least one flock expected on the date, in the order the server listed them. */
export function batchesFrom(candidates: FeedUsageCandidate[]): BatchOption[] {
  const map = new Map<number, BatchOption>()
  for (const c of candidates) {
    if (c.batchId == null) continue
    const b = map.get(c.batchId) ?? { batchId: c.batchId, batchName: c.batchName ?? `Batch ${c.batchId}`, flocks: [] }
    b.flocks.push(c)
    map.set(c.batchId, b)
  }
  return [...map.values()]
}

/** One feed's split across a batch: the reason saving is blocked, or null. */
export function splitBlocker(itemName: string, totalKg: number, parts: number[]): string | null {
  const s = sumKg(parts)
  const t = Math.round(totalKg * 1000) / 1000
  if (parts.some((p) => p < 0)) return `${itemName}: a flock's share cannot be negative.`
  if (Math.abs(s - t) > 0.0005) {
    return `${itemName}: the flocks' shares add up to ${s.toLocaleString()} kg, not ${t.toLocaleString()} kg. Split all of it before saving.`
  }
  return null
}
