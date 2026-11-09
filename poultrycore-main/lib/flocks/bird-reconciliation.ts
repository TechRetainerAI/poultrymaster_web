// Pure maths for Batch Bird Reconciliation and existing-flock history
// (migration 413). The server recomputes and enforces every figure; these only
// let a form show the same numbers before it is saved. Money is worked in whole
// pesewas (integers) so 2,000 x 45.10 is exact.

export type ReconciliationKind = "Sale" | "Mortality" | "Cull" | "TransferOut" | "StockCorrection" | "Other"

/** One line as the API takes it (camelCase = the database's json keys). */
export interface ReconciliationLine {
  kind: ReconciliationKind
  quantity: number
  date?: string | null
  note?: string | null
  /** StockCorrection only. */
  direction?: "Decrease" | "Increase"
  // ---- Sale only
  /** Set = sold from this flock after placing: values the flock's opening "sold", moves no bird. */
  flockId?: number | null
  pricePerBird?: number | null
  valueUnknown?: boolean
  customerId?: number | null
  amountReceived?: number | null
  createReceivable?: boolean
  linkDebtId?: number | null
  reference?: string | null
  classification?: "PreCutover"
}

export const KIND_LABELS: Record<ReconciliationKind, string> = {
  Sale: "Previously sold",
  Mortality: "Historical mortality",
  Cull: "Culled / removed",
  TransferOut: "Transferred outside the batch",
  StockCorrection: "Historical stock correction",
  Other: "Other documented reason",
}

const int = (v: unknown): number => {
  const n = Number(v)
  return Number.isFinite(n) ? Math.trunc(n) : 0
}
const toPesewas = (v: unknown): number => {
  const n = Number(v)
  return Number.isFinite(n) ? Math.round(n * 100) : 0
}

/** Birds this line takes out of the batch's never-placed pool (negative = adds back). */
export function lineRemoves(line: ReconciliationLine): number {
  if (line.kind === "Sale" && line.flockId) return 0 // valued from a flock, no bird moves
  const q = Math.max(0, int(line.quantity))
  return line.kind === "StockCorrection" && line.direction === "Increase" ? -q : q
}

export interface SaleValue {
  /** null when the value is unknown */
  total: number | null
  received: number
  owed: number
  treatment: "QuantityOnly" | "HistoricalPaid" | "HistoricalReceivable" | "HistoricalUnpaidNotTracked"
  problem: string | null
}

/** Mirrors sppoultrybatchreconcile_post's rules for a sale line. */
export function saleValue(line: ReconciliationLine): SaleValue {
  if (line.valueUnknown) return { total: null, received: 0, owed: 0, treatment: "QuantityOnly", problem: null }
  const q = Math.max(0, int(line.quantity))
  const price = line.pricePerBird
  if (price === null || price === undefined || String(price) === "" || Number(price) < 0) {
    return { total: null, received: 0, owed: 0, treatment: "QuantityOnly",
             problem: "Enter the selling price per bird, or tick “value unknown”." }
  }
  const totalP = q * toPesewas(price)
  const receivedP = line.amountReceived === null || line.amountReceived === undefined || String(line.amountReceived) === ""
    ? totalP : toPesewas(line.amountReceived)
  if (receivedP < 0 || receivedP > totalP) {
    return { total: totalP / 100, received: receivedP / 100, owed: 0, treatment: "HistoricalPaid",
             problem: "Amount received must be between 0 and the sale value." }
  }
  const owedP = totalP - receivedP
  const treatment = owedP === 0 ? "HistoricalPaid"
    : (line.createReceivable || line.linkDebtId) ? "HistoricalReceivable" : "HistoricalUnpaidNotTracked"
  const problem = treatment === "HistoricalReceivable" && !line.customerId
    ? "Choose the customer who still owes the balance." : null
  return { total: totalP / 100, received: receivedP / 100, owed: owedP / 100, treatment, problem }
}

export interface BatchReconciliationPreview {
  /** Birds not in any flock right now (server figure). */
  poolBefore: number
  removed: number
  poolAfter: number
  stillAlive: number
  /** poolAfter - stillAlive. Positive = still to explain; negative = over-explained. */
  unexplained: number
  byKind: Record<ReconciliationKind, number>
  saleBirds: number
  saleValue: number
  received: number
  owed: number
  receivablesToCreate: number
  problems: string[]
  /** "Reconciled" only when nothing is left unexplained and nothing is wrong. */
  status: "Reconciled" | "Unexplained" | "Invalid"
}

export function previewBatchReconciliation(poolBefore: number, lines: ReconciliationLine[], stillAlive: number): BatchReconciliationPreview {
  const byKind: Record<ReconciliationKind, number> = { Sale: 0, Mortality: 0, Cull: 0, TransferOut: 0, StockCorrection: 0, Other: 0 }
  const problems: string[] = []
  let removed = 0, saleBirds = 0, valueP = 0, receivedP = 0, owedP = 0, receivables = 0
  lines.forEach((l, i) => {
    const q = int(l.quantity)
    if (q < 0) problems.push(`Line ${i + 1}: birds cannot be negative.`)
    if (q === 0) return
    const r = lineRemoves(l)
    removed += r
    byKind[l.kind] += r
    if (l.kind === "Other" && !(l.note ?? "").trim()) problems.push(`Line ${i + 1}: “Other” needs a note saying what happened.`)
    if (l.kind === "Sale") {
      saleBirds += Math.max(0, q)
      const v = saleValue(l)
      if (v.problem) problems.push(`Line ${i + 1}: ${v.problem}`)
      valueP += Math.round((v.total ?? 0) * 100)
      receivedP += Math.round(v.received * 100)
      owedP += Math.round(v.owed * 100)
      if (v.treatment === "HistoricalReceivable" && !l.linkDebtId) receivables += 1
    }
  })
  const alive = Math.max(0, int(stillAlive))
  const poolAfter = poolBefore - removed
  if (poolAfter < 0) problems.push(`These lines take out ${removed.toLocaleString()} birds but only ${poolBefore.toLocaleString()} are not in a flock.`)
  if (alive > Math.max(poolAfter, 0)) problems.push(`Only ${Math.max(poolAfter, 0).toLocaleString()} birds are left out of a flock, so ${alive.toLocaleString()} cannot still be alive there.`)
  const unexplained = poolAfter - alive
  return {
    poolBefore, removed, poolAfter, stillAlive: alive, unexplained, byKind,
    saleBirds, saleValue: valueP / 100, received: receivedP / 100, owed: owedP / 100,
    receivablesToCreate: receivables, problems,
    status: problems.length > 0 ? "Invalid" : unexplained === 0 ? "Reconciled" : "Unexplained",
  }
}

// ---- Existing flock --------------------------------------------------------

export interface FlockHistoryDraft {
  originallyPlaced: string | number
  currentLiveBirds: string | number
  historyKnown: boolean
  historicalMortality: string | number
  historicalSold: string | number
  historicalCulled: string | number
  historicalTransferred: string | number
}

export interface FlockHistoryPreview {
  placed: number
  live: number
  difference: number
  stated: number
  /** Recorded as "other / unknown" -- never as mortality. */
  other: number
  problem: string | null
}

/** Same rule as ExistingFlockHistory.Breakdown / FarmSetupValidator.Breakdown. */
export function previewFlockHistory(d: FlockHistoryDraft): FlockHistoryPreview {
  const placed = int(d.originallyPlaced)
  const live = int(d.currentLiveBirds)
  const difference = Math.max(0, placed - live)
  const parts = [d.historicalMortality, d.historicalSold, d.historicalCulled, d.historicalTransferred].map(int)
  const stated = d.historyKnown ? parts.reduce((a, b) => a + b, 0) : 0
  let problem: string | null = null
  if (placed <= 0) problem = "Enter how many birds were originally placed."
  else if (live < 0) problem = "Birds remaining cannot be negative."
  else if (live > placed) problem = "Birds remaining are more than were placed. Record the extra birds as a transfer in or a correction instead."
  else if (parts.some((p) => p < 0)) problem = "Historical figures cannot be negative."
  else if (stated > difference) problem = `The reasons add up to ${stated.toLocaleString()} but only ${difference.toLocaleString()} birds are gone.`
  return { placed, live, difference, stated, other: Math.max(0, difference - stated), problem }
}

/** A fresh idempotency key for one submission (a retry reuses it). */
export function newRequestKey(prefix: string): string {
  const rnd = typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(36).slice(2)}`
  return `${prefix}:${rnd}`
}
