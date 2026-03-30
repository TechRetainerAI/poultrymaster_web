import type { ProductionRecord } from "@/lib/api/production-record"

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

  // Guard against legacy/bad data where left can exceed birds.
  if (birds <= 0) return Math.max(0, left)
  return Math.max(0, Math.min(left, birds))
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
