import type { ProductionRecord } from '@/lib/api/production-record'
import type { Flock } from '@/lib/api/flock'
import type { ProductionBatchRecord } from '@/lib/api/production-batch'
import { getLatestRecordForFlock, getBirdsLeftFromRecord } from '@/lib/utils/production-records'

export type AllocMethod = 'Manual' | 'ByBirdCount' | 'ByPreviousProduction' | 'EqualSplit'

/** One editable allocation row (grid state). */
export interface AllocRow {
  flockId: number
  flockName: string
  ageInWeeks: number | null
  ageInDays: number | null
  birdsBefore: number
  deaths: number
  p1: number
  p2: number
  p3: number
  p4: number
  broken: number
  meaty: number
  soft: number
  lost: number
  /** itemId -> quantity consumed for each batch feed line. */
  feedQty: Record<number, number>
  /** itemId -> quantity consumed for each batch medication line. */
  medQty: Record<number, number>
  notes: string
}

/**
 * Distribute an integer total across N buckets by weight, using the
 * largest-remainder method so the parts sum EXACTLY to the total.
 */
export function distributeInteger(total: number, weights: number[]): number[] {
  const n = weights.length
  if (n === 0) return []
  const t = Math.round(total || 0)
  const sumW = weights.reduce((a, b) => a + (b > 0 ? b : 0), 0)
  if (t <= 0 || sumW <= 0) return new Array(n).fill(0)
  const raw = weights.map((w) => (t * (w > 0 ? w : 0)) / sumW)
  const floors = raw.map((x) => Math.floor(x))
  let remainder = t - floors.reduce((a, b) => a + b, 0)
  const order = raw
    .map((x, i) => ({ i, frac: x - Math.floor(x) }))
    .sort((a, b) => b.frac - a.frac)
  const result = floors.slice()
  for (let k = 0; k < order.length && remainder > 0; k++) {
    result[order[k].i] += 1
    remainder -= 1
  }
  return result
}

/** Distribute a decimal total by weight, keeping `dp` decimals and summing exactly. */
export function distributeDecimal(total: number, weights: number[], dp = 3): number[] {
  const n = weights.length
  if (n === 0) return []
  const factor = Math.pow(10, dp)
  const scaled = distributeInteger(Math.round((total || 0) * factor), weights)
  return scaled.map((x) => x / factor)
}

/** Age (weeks + residual days) from a flock start date, as of `asOf`. */
export function ageFromStartDate(startDate?: string | null, asOf: Date = new Date()): { weeks: number; days: number } | null {
  if (!startDate) return null
  const start = new Date(startDate)
  if (!Number.isFinite(start.getTime())) return null
  const diffDays = Math.max(0, Math.floor((asOf.getTime() - start.getTime()) / 86400000))
  return { weeks: Math.floor(diffDays / 7), days: diffDays }
}

/** Birds currently on a flock: latest production birds-left, else placed quantity. */
export function birdsForFlock(flock: Flock, records: Array<ProductionRecord | Record<string, unknown>>): number {
  const latest = getLatestRecordForFlock(records, flock.flockId)
  if (latest) return getBirdsLeftFromRecord(latest)
  return Math.max(0, Number(flock.quantity) || 0)
}

/** Average total eggs over the last `n` production records for a flock (recency weight). */
export function recentProductionAvg(
  records: Array<ProductionRecord | Record<string, unknown>>,
  flockId: number,
  n = 7,
): number {
  const rows = records
    .filter((r) => Number((r as any).flockId ?? (r as any).FlockId) === flockId)
    .sort((a, b) => new Date(String((b as any).date)).getTime() - new Date(String((a as any).date)).getTime())
    .slice(0, n)
  if (rows.length === 0) return 0
  const sum = rows.reduce((acc, r) => acc + (Number((r as any).totalProduction ?? (r as any).TotalProduction) || 0), 0)
  return sum / rows.length
}

/** Build blank allocation rows for each included flock, seeded with birds + age. */
export function buildBlankRows(
  batch: ProductionBatchRecord,
  flocksById: Map<number, Flock>,
  records: Array<ProductionRecord | Record<string, unknown>>,
): AllocRow[] {
  const feedIds = (batch.feeds || []).map((f) => f.itemId)
  const medIds = (batch.medications || []).map((m) => m.itemId)
  return (batch.includedFlocks || []).map((incl) => {
    const flock = flocksById.get(incl.flockId)
    const age = flock ? ageFromStartDate(flock.startDate) : null
    return {
      flockId: incl.flockId,
      flockName: incl.flockName || flock?.name || `Flock ${incl.flockId}`,
      ageInWeeks: batch.batchSelectionType === 'SpecificBatch' && age ? age.weeks : age?.weeks ?? null,
      ageInDays: age?.days ?? null,
      birdsBefore: flock ? birdsForFlock(flock, records) : 0,
      deaths: 0,
      p1: 0,
      p2: 0,
      p3: 0,
      p4: 0,
      broken: 0,
      meaty: 0,
      soft: 0,
      lost: 0,
      feedQty: Object.fromEntries(feedIds.map((id) => [id, 0])),
      medQty: Object.fromEntries(medIds.map((id) => [id, 0])),
      notes: '',
    }
  })
}

/** Weights for a given method, one per row (index-aligned with `rows`). */
export function weightsForMethod(
  method: AllocMethod,
  rows: AllocRow[],
  records: Array<ProductionRecord | Record<string, unknown>>,
): number[] {
  if (method === 'EqualSplit') return rows.map(() => 1)
  if (method === 'ByBirdCount') return rows.map((r) => r.birdsBefore)
  if (method === 'ByPreviousProduction') {
    const w = rows.map((r) => recentProductionAvg(records, r.flockId))
    // Fall back to bird count when there's no production history at all.
    if (w.reduce((a, b) => a + b, 0) <= 0) return rows.map((r) => r.birdsBefore)
    return w
  }
  return rows.map(() => 0) // Manual
}

/** Apply an allocation method: distribute every batch total across the rows. */
export function applyMethod(
  method: AllocMethod,
  rows: AllocRow[],
  batch: ProductionBatchRecord,
  records: Array<ProductionRecord | Record<string, unknown>>,
): AllocRow[] {
  if (method === 'Manual') {
    // Blank editable grid — keep birds/age, zero the values.
    return rows.map((r) => ({
      ...r,
      deaths: 0, p1: 0, p2: 0, p3: 0, p4: 0, broken: 0, meaty: 0, soft: 0, lost: 0,
      feedQty: Object.fromEntries(Object.keys(r.feedQty).map((k) => [k, 0])),
      medQty: Object.fromEntries(Object.keys(r.medQty).map((k) => [k, 0])),
    }))
  }
  const w = weightsForMethod(method, rows, records)
  const p1 = distributeInteger(batch.firstPickTotal, w)
  const p2 = distributeInteger(batch.secondPickTotal, w)
  const p3 = distributeInteger(batch.thirdPickTotal, w)
  const p4 = distributeInteger(batch.fourthPickTotal, w)
  const broken = distributeInteger(batch.brokenEggs || 0, w)
  const meaty = distributeInteger(batch.meatyEggs || 0, w)
  const soft = distributeInteger(batch.softEggs || 0, w)
  const lost = distributeInteger(batch.lostEggs || 0, w)
  const deaths = distributeInteger(batch.deaths || 0, w)
  const feedDist: Record<number, number[]> = {}
  ;(batch.feeds || []).forEach((f) => (feedDist[f.itemId] = distributeDecimal(f.qty, w)))
  const medDist: Record<number, number[]> = {}
  ;(batch.medications || []).forEach((m) => (medDist[m.itemId] = distributeDecimal(m.qty, w)))

  return rows.map((r, i) => ({
    ...r,
    deaths: deaths[i], p1: p1[i], p2: p2[i], p3: p3[i], p4: p4[i],
    broken: broken[i], meaty: meaty[i], soft: soft[i], lost: lost[i],
    feedQty: Object.fromEntries((batch.feeds || []).map((f) => [f.itemId, feedDist[f.itemId][i]])),
    medQty: Object.fromEntries((batch.medications || []).map((m) => [m.itemId, medDist[m.itemId][i]])),
  }))
}

// ---- Derived per-row values ----
export const rowTotalEggs = (r: AllocRow) => r.p1 + r.p2 + r.p3 + r.p4
export const rowBirdsAfter = (r: AllocRow) => Math.max(0, r.birdsBefore - r.deaths)
export const rowEggPct = (r: AllocRow) => (r.birdsBefore > 0 ? (rowTotalEggs(r) / r.birdsBefore) * 100 : 0)
export const rowFeedCost = (r: AllocRow, batch: ProductionBatchRecord) =>
  (batch.feeds || []).reduce((s, f) => s + (r.feedQty[f.itemId] || 0) * (f.unitCost || 0), 0)
export const rowMedCost = (r: AllocRow, batch: ProductionBatchRecord) =>
  (batch.medications || []).reduce((s, m) => s + (r.medQty[m.itemId] || 0) * (m.unitCost || 0), 0)

export interface ReconLine {
  key: string
  label: string
  batchTotal: number
  allocated: number
  diff: number
  balanced: boolean
  money?: boolean
  decimals?: number
}

const INT_TOL = 0
const QTY_TOL = 0.001
const MONEY_TOL = 0.01

/** Build the reconciliation footer lines + an overall `balanced` flag. */
export function buildReconciliation(rows: AllocRow[], batch: ProductionBatchRecord): { lines: ReconLine[]; balanced: boolean } {
  const sum = (fn: (r: AllocRow) => number) => rows.reduce((s, r) => s + fn(r), 0)
  const lines: ReconLine[] = []

  const intLine = (key: string, label: string, batchTotal: number, allocated: number) => {
    const diff = allocated - batchTotal
    lines.push({ key, label, batchTotal, allocated, diff, balanced: Math.abs(diff) <= INT_TOL })
  }
  const qtyLine = (key: string, label: string, batchTotal: number, allocated: number) => {
    const diff = allocated - batchTotal
    lines.push({ key, label, batchTotal, allocated, diff, balanced: Math.abs(diff) <= QTY_TOL, decimals: 3 })
  }
  const moneyLine = (key: string, label: string, batchTotal: number, allocated: number) => {
    const diff = allocated - batchTotal
    lines.push({ key, label, batchTotal, allocated, diff, balanced: Math.abs(diff) <= MONEY_TOL, money: true })
  }

  intLine('p1', '1st Pick', batch.firstPickTotal, sum((r) => r.p1))
  intLine('p2', '2nd Pick', batch.secondPickTotal, sum((r) => r.p2))
  intLine('p3', '3rd Pick', batch.thirdPickTotal, sum((r) => r.p3))
  intLine('p4', '4th Pick', batch.fourthPickTotal, sum((r) => r.p4))
  intLine('broken', 'Broken', batch.brokenEggs || 0, sum((r) => r.broken))
  intLine('meaty', 'Meaty', batch.meatyEggs || 0, sum((r) => r.meaty))
  intLine('soft', 'Soft', batch.softEggs || 0, sum((r) => r.soft))
  intLine('lost', 'Lost', batch.lostEggs || 0, sum((r) => r.lost))
  intLine('total', 'Total Eggs', batch.totalEggs, sum(rowTotalEggs))
  intLine('deaths', 'Deaths', batch.deaths || 0, sum((r) => r.deaths))
  ;(batch.feeds || []).forEach((f) =>
    qtyLine(`feed-${f.itemId}`, `${f.itemName || 'Feed'} (feed)`, f.qty, sum((r) => r.feedQty[f.itemId] || 0)),
  )
  ;(batch.medications || []).forEach((m) =>
    qtyLine(`med-${m.itemId}`, `${m.itemName || 'Medication'} (med)`, m.qty, sum((r) => r.medQty[m.itemId] || 0)),
  )
  moneyLine('feedCost', 'Total Feed Cost', batch.totalFeedCost || 0, sum((r) => rowFeedCost(r, batch)))
  moneyLine('medCost', 'Total Medication Cost', batch.totalMedicationCost || 0, sum((r) => rowMedCost(r, batch)))
  moneyLine(
    'prodCost',
    'Total Cost of Production',
    batch.totalCostOfProduction || 0,
    sum((r) => rowFeedCost(r, batch) + rowMedCost(r, batch)),
  )

  // The hard gate matches what the server's Post proc actually enforces: egg/death
  // totals exact, and each feed/medication QUANTITY balanced within unit tolerance.
  // Money lines are shown for information but don't block posting — final costs are
  // recomputed server-side (FIFO/LIFO/HIFO) when the flock records are created.
  const balanced = lines.filter((l) => !l.money).every((l) => l.balanced)
  return { lines, balanced }
}
