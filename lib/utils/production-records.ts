import type { ProductionRecord } from "@/lib/api/production-record"
import type { Flock } from "@/lib/api/flock"

function toNumber(value: unknown): number {
  const n = Number(value)
  return Number.isFinite(n) ? n : 0
}

function toTimestamp(value: unknown): number {
  if (!value) return 0
  const t = new Date(String(value)).getTime()
  return Number.isFinite(t) ? t : 0
}

function getRecordFlockId(record: ProductionRecord | Record<string, unknown>): number | null {
  const raw = (record as any).flockId ?? (record as any).FlockId
  if (raw === null || raw === undefined || raw === "") return null
  const flockId = Number(raw)
  return Number.isFinite(flockId) ? flockId : null
}

export function getLatestRecordForFlock(
  records: Array<ProductionRecord | Record<string, unknown>>,
  flockId: number,
): (ProductionRecord | Record<string, unknown>) | null {
  const byFlock = records.filter((r) => getRecordFlockId(r) === flockId)
  if (byFlock.length === 0) return null

  const sorted = byFlock.sort((a, b) => {
    const dateDiff = toTimestamp((b as any).date ?? (b as any).Date) - toTimestamp((a as any).date ?? (a as any).Date)
    if (dateDiff !== 0) return dateDiff

    const updatedDiff =
      toTimestamp((b as any).updatedAt ?? (b as any).UpdatedAt) -
      toTimestamp((a as any).updatedAt ?? (a as any).UpdatedAt)
    if (updatedDiff !== 0) return updatedDiff

    return toNumber((b as any).id ?? (b as any).Id) - toNumber((a as any).id ?? (a as any).Id)
  })

  return sorted[0] ?? null
}

export function getBirdsLeftFromRecord(record: ProductionRecord | Record<string, unknown> | null): number {
  if (!record) return 0
  const birds = toNumber((record as any).noOfBirds ?? (record as any).NoOfBirds)
  const left = toNumber((record as any).noOfBirdsLeft ?? (record as any).NoOfBirdsLeft)
  const mort = toNumber((record as any).mortality ?? (record as any).Mortality)

  if (birds <= 0) return Math.max(0, left)

  // Same-day sanity: some rows store noOfBirdsLeft === noOfBirds while mortality > 0.
  const sameDayLeft = Math.max(0, birds - mort)
  if (mort > 0 && left >= birds) return Math.min(sameDayLeft, birds)

  // Guard against legacy/bad data where left can exceed birds.
  return Math.max(0, Math.min(left, birds))
}

/** Birds left from the most recent production row for this flock (uses stored `noOfBirdsLeft`). */
export function getBirdsLeftForFlockFromRecords(
  records: Array<ProductionRecord | Record<string, unknown>>,
  flockId: number,
): number {
  return getBirdsLeftFromRecord(getLatestRecordForFlock(records, flockId))
}

export function sumLatestBirdsLeftByFlock(
  records: Array<ProductionRecord | Record<string, unknown>>,
): number {
  const flockIds = new Set<number>()
  records.forEach((r) => {
    const fid = getRecordFlockId(r)
    if (fid !== null) flockIds.add(fid)
  })

  let total = 0
  flockIds.forEach((fid) => {
    const latest = getLatestRecordForFlock(records, fid)
    total += getBirdsLeftFromRecord(latest)
  })

  return total
}

/**
 * Birds left used for billing and farm-wide totals: for each **active** flock, use
 * `noOfBirdsLeft` from the latest production row, or placed `quantity` when there is no
 * production yet (same rule as the Flocks table `getCurrentBirds`).
 */
export function sumActiveFlocksBirdsLeft(
  flocks: Flock[],
  records: Array<ProductionRecord | Record<string, unknown>>,
): number {
  return flocks
    .filter((f) => f.active)
    .reduce((sum, flock) => {
      const latest = getLatestRecordForFlock(records, flock.flockId)
      if (!latest) return sum + Math.max(0, Number(flock.quantity) || 0)
      return sum + getBirdsLeftFromRecord(latest)
    }, 0)
}

export function sumLatestBirdsByFlock(
  records: Array<ProductionRecord | Record<string, unknown>>,
): number {
  const flockIds = new Set<number>()
  records.forEach((r) => {
    const fid = getRecordFlockId(r)
    if (fid !== null) flockIds.add(fid)
  })

  let total = 0
  flockIds.forEach((fid) => {
    const latest = getLatestRecordForFlock(records, fid)
    total += toNumber((latest as any)?.noOfBirds ?? (latest as any)?.NoOfBirds)
  })

  return total
}
