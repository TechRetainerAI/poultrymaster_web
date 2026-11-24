// Egg Cost & Profit Analyzer -- the calculation engine (migration 481).
//
// Pure functions over the facts sppoultryeggcost_facts returns. Nothing here
// talks to the server or writes anything: the same code produces the
// recorded analysis, every trend bucket, and the baseline a What-If scenario
// starts from, so all three always agree.
//
// Cost basis (see the 481 header for the full rule list):
//   * Feed and medication = what was CONSUMED, valued by the cost layers on
//     each production record. Stock purchase / consumption expenses are the
//     same feed again and are excluded (shown in the reconciliation).
//   * Labour, utilities, overhead, depreciation, packaging = expense rows as
//     the P&L classifies them. A row tagged to a flock is that flock's; an
//     untagged row is SHARED and allocated by the company's chosen basis.
//   * Pre-laying cost (bird cost + rearing feed/medication + historical
//     entries) is spread over the flock's EXPECTED lifetime saleable eggs.
//     No expectation stated = not applied, and the result says so.

export const CALC_VERSION = "481.1"

// ------------------------------------------------------------------ facts
export type CostComponent =
  | "Labour" | "Utilities" | "Overhead" | "Veterinary" | "DirectFeedExpense" | "Packaging" | "Depreciation"
  | "ExcludedStockFeed" | "ExcludedStockMedication" | "ExcludedBirdPurchase" | "ExcludedCapital"
  | "ExcludedFinancing" | "ExcludedInternalUse"

export interface FactFlock {
  flockId: number
  name: string
  batchId: number | null
  batchCode: string | null
  batchName: string | null
  flockType: string
  startDate: string | null
  closedDate: string | null
  firstEggDate: string | null
  originallyPlaced: number | null
  birdsAtStart: number | null
  birdsAtEnd: number | null
  birdCost: number | null
  birdCostBasis: string | null
  batchIsHistorical: boolean
  lifetimeSaleableEggs: number
  saleableEggsBeforePeriod: number
  preLayFeedCost: number
  preLayMedicationCost: number
  preLayRecords: number
  preLayFeedWithoutCost: number
  historicalCost: number
  historicalCostHasEstimate: boolean
  assumptions: FlockAssumptions | null
}

export interface FlockAssumptions {
  expectedLifetimeSaleableEggs: number | null
  expectedLayingWeeks: number | null
  expectedLayRatePct: number | null
  expectedMortalityPct: number | null
  expectedResidualValue: number | null
  useResidualValue: boolean
  notes: string | null
  updatedBy?: string | null
  updatedAt?: string | null
}

export interface FactRecord {
  id: number
  date: string
  flockId: number
  gross: number
  broken: number
  meaty: number
  soft: number
  lost: number
  saleable: number
  birds: number | null
  feedKg: number
  feedCost: number
  medicationCost: number
  sourceType: string | null
}

export interface FactRecordLine {
  recordId: number
  kind: "Feed" | "Medication"
  item: string | null
  quantity: number | null
  unitCost: number | null
  totalCost: number | null
}

export interface FactCost {
  expenseId: number
  date: string
  flockId: number | null
  component: CostComponent
  plLine: string
  plSection: string
  sourceType: string | null
  sourceId: number | null
  category: string | null
  description: string | null
  amount: number
  assetName: string | null
}

export interface FactSale {
  saleId: number
  date: string
  flockId: number | null
  product: string
  size: string | null
  eggs: number
  amount: number
}

export interface CostSettings {
  labourAllocation: "BirdDays" | "SaleableEggs"
  overheadAllocation: "BirdDays" | "SaleableEggs"
  labourInDirect: boolean
  includePreLaying: boolean
  includeDepreciation: boolean
  depreciationEggSharePct: number
  overheadEggSharePct: number
  directFeedExpenses: "Exclude" | "Include"
  packagingTreatment: "PackagedOnly" | "Exclude"
  byproductTreatment: "None" | "DeductBrokenEggSales"
  version: number
  updatedBy?: string | null
  updatedAt?: string | null
  isDefault?: boolean
}

export interface EggCostFacts {
  farmId: string
  startDate: string
  endDate: string
  packaging: { eggsPerCrate: number; enableBoxes: boolean; cratesPerBox: number | null }
  settings: CostSettings
  flocks: FactFlock[]
  records: FactRecord[]
  recordLines: FactRecordLine[]
  costs: FactCost[]
  sales: FactSale[]
  brokenEggSales: { eggs: number; amount: number } | null
  historicalCosts: HistoricalCost[]
  assetsInService: number
  fingerprint: string
  generatedAt: string
}

export interface HistoricalCost {
  historicalCostId: number
  flockId: number | null
  batchId: number | null
  category: string
  amount: number
  periodFrom: string | null
  periodTo: string | null
  reason: string
  reference: string | null
  isEstimate: boolean
  enteredBy: string | null
  enteredAt: string
}

export const DEFAULT_SETTINGS: CostSettings = {
  labourAllocation: "BirdDays",
  overheadAllocation: "BirdDays",
  labourInDirect: true,
  includePreLaying: true,
  includeDepreciation: true,
  depreciationEggSharePct: 100,
  overheadEggSharePct: 100,
  directFeedExpenses: "Exclude",
  packagingTreatment: "PackagedOnly",
  byproductTreatment: "None",
  version: 0,
  isDefault: true,
}

// ------------------------------------------------------------------ scope
export type ScopeLevel = "farm" | "batch" | "flock"
export interface Scope { level: ScopeLevel; batchId?: number | null; flockIds?: number[] }

// ------------------------------------------------------------------ small helpers
const DAY = 86_400_000
const toDay = (s: string) => Date.parse(`${s.slice(0, 10)}T00:00:00Z`)
const isoDay = (t: number) => new Date(t).toISOString().slice(0, 10)
/** Inclusive day count of [a, b]; 0 when b < a. */
export const daysBetween = (a: string, b: string) => Math.max(0, Math.round((toDay(b) - toDay(a)) / DAY) + 1)
const maxDay = (a: string, b: string) => (a > b ? a : b)
const minDay = (a: string, b: string) => (a < b ? a : b)
const sum = (xs: number[]) => xs.reduce((s, x) => s + x, 0)
export const round2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100
/** a / b, or null when b is not a positive number -- never a misleading 0. */
export const safeDiv = (a: number, b: number): number | null => (b > 0 && Number.isFinite(a) ? a / b : null)

// ------------------------------------------------------------------ per-flock result
export interface FlockCostRow {
  flockId: number
  name: string
  batchId: number | null
  batchCode: string | null
  flockType: string
  /** In its laying life during the period (first egg on or before the period end). */
  isLaying: boolean
  inScope: boolean
  gross: number
  broken: number
  otherLoss: number
  saleable: number
  /** Bird-days in the period while laying, and before laying (rearing). */
  layingBirdDays: number
  rearingBirdDays: number
  avgBirds: number | null
  activeLayingDays: number
  recordDays: number
  feedKg: number
  feed: number
  medication: number
  veterinary: number
  labourDirect: number
  labourAllocated: number
  otherDirect: number
  overheadAllocated: number
  depreciationAllocated: number
  packagingAllocated: number
  directFeedExpense: number
  preLay: PreLayResult
  feedWithoutCostRecords: number
  direct: number
  full: number
  packaged: number
}

export interface PreLayResult {
  pool: number
  birdCost: number
  rearingFeed: number
  rearingMedication: number
  historical: number
  residualDeducted: number
  expectedLifetimeEggs: number | null
  expectedBasis: string | null
  ratePerEgg: number | null
  allocated: number
  status: "Applied" | "NoAssumption" | "NoCost" | "Excluded" | "NotLaying"
  hasEstimate: boolean
}

/** Expected lifetime saleable eggs: stated, or worked out from the stated assumptions. */
export function expectedLifetimeEggs(f: Pick<FactFlock, "originallyPlaced" | "assumptions">): { eggs: number | null; basis: string | null } {
  const a = f.assumptions
  if (!a) return { eggs: null, basis: null }
  if (a.expectedLifetimeSaleableEggs && a.expectedLifetimeSaleableEggs > 0) {
    return { eggs: a.expectedLifetimeSaleableEggs, basis: "Stated expected lifetime saleable eggs" }
  }
  const placed = f.originallyPlaced ?? 0
  if (placed > 0 && a.expectedLayingWeeks && a.expectedLayRatePct != null && a.expectedLayRatePct > 0) {
    const mort = (a.expectedMortalityPct ?? 0) / 100
    // average birds over the laying life ~ placed less half the expected losses
    const avgBirds = placed * (1 - mort / 2)
    const eggs = Math.round(avgBirds * a.expectedLayingWeeks * 7 * (a.expectedLayRatePct / 100))
    return {
      eggs: eggs > 0 ? eggs : null,
      basis: `${placed.toLocaleString()} birds placed × (1 − ${a.expectedMortalityPct ?? 0}% mortality ÷ 2) × ${a.expectedLayingWeeks} weeks × 7 days × ${a.expectedLayRatePct}% lay rate`,
    }
  }
  return { eggs: null, basis: null }
}

/** Pre-laying pool and per-egg rate of one flock (lifetime, not period). */
export function preLayRate(f: FactFlock, settings: CostSettings): Omit<PreLayResult, "allocated" | "status"> & { status: PreLayResult["status"] } {
  const birdCost = f.birdCost ?? 0
  const rearingFeed = f.preLayFeedCost ?? 0
  const rearingMedication = f.preLayMedicationCost ?? 0
  const historical = f.historicalCost ?? 0
  const residual = f.assumptions?.useResidualValue ? Math.max(f.assumptions.expectedResidualValue ?? 0, 0) : 0
  const pool = Math.max(birdCost + rearingFeed + rearingMedication + historical - residual, 0)
  const exp = expectedLifetimeEggs(f)
  const base = {
    pool, birdCost, rearingFeed, rearingMedication, historical, residualDeducted: residual,
    expectedLifetimeEggs: exp.eggs, expectedBasis: exp.basis,
    hasEstimate: !!f.historicalCostHasEstimate || exp.basis !== null,
  }
  if (!settings.includePreLaying) return { ...base, ratePerEgg: null, status: "Excluded" }
  if (pool <= 0) return { ...base, ratePerEgg: null, status: "NoCost" }
  if (!exp.eggs) return { ...base, ratePerEgg: null, status: "NoAssumption" }
  return { ...base, ratePerEgg: pool / exp.eggs, status: "Applied" }
}

// ------------------------------------------------------------------ the analysis
export interface ComponentLine {
  key: string
  label: string
  amount: number
  /** Recorded on a source row / allocated from a shared cost / an estimate. */
  classification: "Direct" | "Allocated" | "Estimated"
  inDirect: boolean
  inFull: boolean
  inPackaged: boolean
  note?: string
}

export interface Warning {
  code: string
  severity: "missing" | "estimate" | "info"
  message: string
}

export type Completeness = "Complete" | "Partial" | "Estimated" | "Insufficient"

export interface PriceAnalysis {
  eggsSold: number
  revenue: number
  pricePerEgg: number | null
  pricePerCrate: number | null
  bySize: { size: string; eggs: number; revenue: number; pricePerCrate: number | null }[]
  untaggedSalesEggs: number
  basis: string
}

export interface EggCostAnalysis {
  calcVersion: string
  startDate: string
  endDate: string
  scope: Scope
  eggsPerCrate: number
  settings: CostSettings
  flocks: FlockCostRow[]
  /** Totals over the flocks in scope. */
  gross: number
  broken: number
  otherLoss: number
  saleable: number
  saleableCrates: number
  components: ComponentLine[]
  directTotal: number
  fullTotal: number
  packagedTotal: number
  feedTotal: number
  directPerEgg: number | null
  directPerCrate: number | null
  fullPerEgg: number | null
  fullPerCrate: number | null
  feedPerCrate: number | null
  packagedPerCrate: number | null
  /** Full cost less broken-egg sales, only when that policy is configured. */
  byproductAdjustedPerCrate: number | null
  price: PriceAnalysis
  marginPerCrate: number | null
  marginPct: number | null
  breakEvenPerCrate: number | null
  /** Shared cost that fell outside egg production, by reason. */
  notEggCost: { label: string; amount: number }[]
  /** Expense rows left out of the analysis, and why (the reconciliation). */
  excluded: { component: string; label: string; amount: number; count: number }[]
  unallocatedShared: number
  completeness: Completeness
  warnings: Warning[]
  fullLabel: string
  directLabel: string
}

const EXCLUDED_LABELS: Record<string, string> = {
  ExcludedStockFeed: "Feed purchases and feed consumption expenses (feed is costed from usage instead)",
  ExcludedStockMedication: "Medication purchases and consumption expenses (costed from usage instead)",
  ExcludedBirdPurchase: "Bird purchases (enter through pre-laying cost instead)",
  ExcludedCapital: "Capital asset acquisitions (only depreciation counts)",
  ExcludedFinancing: "Loan interest and financing costs",
  ExcludedInternalUse: "Internal use (eggs or birds given away at selling price)",
  DirectFeedExpense: "Feed entered directly as an expense (setting: excluded, to avoid counting feed twice)",
  Packaging: "Packaging and production supplies (setting: excluded)",
  Depreciation: "Depreciation (setting: excluded)",
}

function birdsForFlock(f: FactFlock, recs: FactRecord[]): number | null {
  const withBirds = recs.filter((r) => r.birds != null && r.birds > 0)
  if (withBirds.length) return sum(withBirds.map((r) => r.birds!)) / withBirds.length
  const ends = [f.birdsAtStart, f.birdsAtEnd].filter((x): x is number => x != null && x > 0)
  if (ends.length) return sum(ends) / ends.length
  return f.originallyPlaced && f.originallyPlaced > 0 ? f.originallyPlaced : null
}

/** Shares of `amount` over `weights` that sum exactly to the (rounded) amount. */
export function allocate(amount: number, weights: { key: number; weight: number }[]): Map<number, number> {
  const out = new Map<number, number>()
  const total = sum(weights.map((w) => Math.max(w.weight, 0)))
  if (total <= 0 || amount === 0) return out
  let given = 0
  const positive = weights.filter((w) => w.weight > 0)
  positive.forEach((w, i) => {
    const share = i === positive.length - 1 ? round2(amount - given) : round2((amount * w.weight) / total)
    given = round2(given + share)
    out.set(w.key, (out.get(w.key) ?? 0) + share)
  })
  return out
}

export function analyze(facts: EggCostFacts, scope: Scope, window?: { startDate: string; endDate: string }): EggCostAnalysis {
  const settings = { ...DEFAULT_SETTINGS, ...(facts.settings ?? {}) }
  const start = window?.startDate ?? facts.startDate
  const end = window?.endDate ?? facts.endDate
  const epc = facts.packaging?.eggsPerCrate > 0 ? facts.packaging.eggsPerCrate : 30
  const inWindow = (d: string) => d.slice(0, 10) >= start && d.slice(0, 10) <= end

  const records = facts.records.filter((r) => inWindow(r.date))
  const costs = facts.costs.filter((c) => inWindow(c.date))
  const sales = facts.sales.filter((s) => inWindow(s.date))

  const inScope = (f: FactFlock) =>
    scope.level === "farm" ? true
      : scope.level === "batch" ? f.batchId != null && f.batchId === scope.batchId
        : (scope.flockIds ?? []).includes(f.flockId)

  const recsByFlock = new Map<number, FactRecord[]>()
  for (const r of records) {
    const list = recsByFlock.get(r.flockId) ?? []
    list.push(r)
    recsByFlock.set(r.flockId, list)
  }

  // ---- per-flock production, feed, medication, bird-days
  const rows = new Map<number, FlockCostRow>()
  for (const f of facts.flocks) {
    const recs = recsByFlock.get(f.flockId) ?? []
    const isBroiler = (f.flockType ?? "").toLowerCase() === "broiler"
    const firstEgg = f.firstEggDate ? f.firstEggDate.slice(0, 10) : null
    const isLaying = !isBroiler && firstEgg != null && firstEgg <= end
    const layingRecs = isLaying ? recs.filter((r) => r.date.slice(0, 10) >= firstEgg!) : []

    const life0 = maxDay(start, (f.startDate ?? start).slice(0, 10))
    const life1 = minDay(end, (f.closedDate ?? end).slice(0, 10))
    const activeDays = life1 >= life0 ? daysBetween(life0, life1) : 0
    const layStart = isLaying ? maxDay(life0, firstEgg!) : null
    const activeLayingDays = isLaying && layStart && life1 >= layStart ? daysBetween(layStart, life1) : 0
    const birds = birdsForFlock(f, recs)
    const layingBirdDays = birds ? birds * activeLayingDays : 0
    const rearingBirdDays = birds ? birds * Math.max(activeDays - activeLayingDays, 0) : 0

    const pl = preLayRate(f, settings)
    const saleable = sum(layingRecs.map((r) => r.saleable))
    rows.set(f.flockId, {
      flockId: f.flockId, name: f.name, batchId: f.batchId, batchCode: f.batchCode, flockType: f.flockType,
      isLaying, inScope: inScope(f),
      gross: sum(layingRecs.map((r) => r.gross)),
      broken: sum(layingRecs.map((r) => r.broken)),
      otherLoss: sum(layingRecs.map((r) => r.meaty + r.soft + r.lost)),
      saleable,
      layingBirdDays, rearingBirdDays, avgBirds: birds,
      activeLayingDays,
      recordDays: new Set(layingRecs.map((r) => r.date.slice(0, 10))).size,
      feedKg: sum(layingRecs.map((r) => r.feedKg)),
      feed: round2(sum(layingRecs.map((r) => r.feedCost))),
      medication: round2(sum(layingRecs.map((r) => r.medicationCost))),
      veterinary: 0, labourDirect: 0, labourAllocated: 0, otherDirect: 0,
      overheadAllocated: 0, depreciationAllocated: 0, packagingAllocated: 0, directFeedExpense: 0,
      preLay: {
        ...pl,
        allocated: pl.status === "Applied" && isLaying ? round2(pl.ratePerEgg! * saleable) : 0,
        status: !isLaying && pl.status === "Applied" ? "NotLaying" : pl.status,
      },
      feedWithoutCostRecords: layingRecs.filter((r) => r.feedKg > 0 && !(r.feedCost > 0)).length,
      direct: 0, full: 0, packaged: 0,
    })
  }

  // ---- expense rows: tagged -> that flock; untagged -> shared
  const notEgg = new Map<string, number>()
  const addNotEgg = (label: string, amt: number) => { if (amt) notEgg.set(label, round2((notEgg.get(label) ?? 0) + amt)) }
  const excluded = new Map<string, { amount: number; count: number }>()
  const exclude = (key: string, amt: number) => {
    const e = excluded.get(key) ?? { amount: 0, count: 0 }
    e.amount = round2(e.amount + amt); e.count += 1
    excluded.set(key, e)
  }
  const shared: Record<"Labour" | "Overhead" | "Depreciation" | "Packaging" | "Feed" | "Veterinary", number> = {
    Labour: 0, Overhead: 0, Depreciation: 0, Packaging: 0, Feed: 0, Veterinary: 0,
  }

  for (const c of costs) {
    let comp: string = c.component
    if (comp === "Utilities") comp = "Overhead"
    if (comp.startsWith("Excluded")) { exclude(comp, c.amount); continue }
    if (comp === "DirectFeedExpense" && settings.directFeedExpenses === "Exclude") { exclude(comp, c.amount); continue }
    if (comp === "Packaging" && settings.packagingTreatment === "Exclude") { exclude(comp, c.amount); continue }
    if (comp === "Depreciation" && !settings.includeDepreciation) { exclude(comp, c.amount); continue }
    if (comp === "DirectFeedExpense") comp = "Feed"

    const row = c.flockId != null ? rows.get(c.flockId) : undefined
    if (row) {
      const day = c.date.slice(0, 10)
      const fl = facts.flocks.find((f) => f.flockId === row.flockId)
      const beforeLay = !row.isLaying || (fl?.firstEggDate != null && day < fl.firstEggDate.slice(0, 10))
      if (beforeLay) { addNotEgg("Tagged to flocks that were not laying (rearing or broilers)", c.amount); continue }
      if (comp === "Labour") row.labourDirect = round2(row.labourDirect + c.amount)
      else if (comp === "Veterinary") row.veterinary = round2(row.veterinary + c.amount)
      else if (comp === "Feed") row.directFeedExpense = round2(row.directFeedExpense + c.amount)
      else if (comp === "Depreciation") row.depreciationAllocated = round2(row.depreciationAllocated + c.amount)
      else if (comp === "Packaging") row.packagingAllocated = round2(row.packagingAllocated + c.amount)
      else row.otherDirect = round2(row.otherDirect + c.amount)
      continue
    }
    shared[comp as keyof typeof shared] = round2(shared[comp as keyof typeof shared] + c.amount)
  }

  // ---- allocate the shared pools
  const all = [...rows.values()]
  const laying = all.filter((r) => r.isLaying)
  let unallocatedShared = 0

  const allocateShared = (
    amount: number, basis: "BirdDays" | "SaleableEggs", eggSharePct: number,
    apply: (r: FlockCostRow, share: number) => void, label: string,
  ) => {
    if (!amount) return
    const eggPart = round2((amount * Math.min(Math.max(eggSharePct, 0), 100)) / 100)
    addNotEgg(`${label}: share set to other activities (${100 - eggSharePct}%)`, round2(amount - eggPart))
    if (!eggPart) return
    if (basis === "SaleableEggs") {
      const shares = allocate(eggPart, laying.map((r) => ({ key: r.flockId, weight: r.saleable })))
      if (shares.size === 0) { unallocatedShared = round2(unallocatedShared + eggPart); return }
      for (const r of laying) { const s = shares.get(r.flockId); if (s) apply(r, s) }
      return
    }
    // BirdDays: every flock's birds share the cost; the part on rearing days or
    // broilers is not egg cost this period.
    const NONLAY = -1
    const weights = [
      ...all.map((r) => ({ key: r.flockId, weight: r.isLaying ? r.layingBirdDays : 0 })),
      { key: NONLAY, weight: sum(all.map((r) => r.rearingBirdDays)) },
    ]
    const shares = allocate(eggPart, weights)
    if (shares.size === 0) { unallocatedShared = round2(unallocatedShared + eggPart); return }
    for (const r of laying) { const s = shares.get(r.flockId); if (s) apply(r, s) }
    addNotEgg(`${label}: share of birds not laying (rearing days or broilers)`, shares.get(NONLAY) ?? 0)
  }

  allocateShared(shared.Labour, settings.labourAllocation, 100, (r, s) => { r.labourAllocated = round2(r.labourAllocated + s) }, "Labour")
  allocateShared(shared.Overhead, settings.overheadAllocation, settings.overheadEggSharePct, (r, s) => { r.overheadAllocated = round2(r.overheadAllocated + s) }, "Utilities and overhead")
  allocateShared(shared.Depreciation, settings.overheadAllocation, settings.depreciationEggSharePct, (r, s) => { r.depreciationAllocated = round2(r.depreciationAllocated + s) }, "Depreciation")
  allocateShared(shared.Veterinary, settings.overheadAllocation, 100, (r, s) => { r.veterinary = round2(r.veterinary + s) }, "Veterinary")
  // packaging and directly-expensed feed follow the eggs
  allocateShared(shared.Packaging, "SaleableEggs", 100, (r, s) => { r.packagingAllocated = round2(r.packagingAllocated + s) }, "Packaging")
  allocateShared(shared.Feed, "SaleableEggs", 100, (r, s) => { r.directFeedExpense = round2(r.directFeedExpense + s) }, "Feed expenses")

  // ---- per-flock totals
  for (const r of all) {
    const labour = r.labourDirect + r.labourAllocated
    r.direct = round2(r.feed + r.directFeedExpense + r.medication + r.veterinary + r.otherDirect + (settings.labourInDirect ? labour : 0))
    r.full = round2(r.direct + (settings.labourInDirect ? 0 : labour) + r.overheadAllocated + r.depreciationAllocated + r.preLay.allocated)
    r.packaged = round2(r.full + r.packagingAllocated)
  }

  // ---- scope totals
  const sc = laying.filter((r) => r.inScope)
  const tot = (k: keyof FlockCostRow) => round2(sum(sc.map((r) => Number(r[k]) || 0)))
  const gross = sum(sc.map((r) => r.gross))
  const broken = sum(sc.map((r) => r.broken))
  const otherLoss = sum(sc.map((r) => r.otherLoss))
  const saleable = sum(sc.map((r) => r.saleable))
  const preLay = round2(sum(sc.map((r) => r.preLay.allocated)))
  const preLayEstimate = sc.some((r) => r.preLay.allocated > 0 && r.preLay.hasEstimate)

  const comps: ComponentLine[] = [
    { key: "Feed", label: "Feed (consumed)", amount: tot("feed"), classification: "Direct", inDirect: true, inFull: true, inPackaged: true },
    ...(tot("directFeedExpense") ? [{ key: "DirectFeedExpense", label: "Feed (expensed directly)", amount: tot("directFeedExpense"), classification: "Direct" as const, inDirect: true, inFull: true, inPackaged: true }] : []),
    { key: "Medication", label: "Medication & supplements (consumed)", amount: tot("medication"), classification: "Direct", inDirect: true, inFull: true, inPackaged: true },
    { key: "Veterinary", label: "Veterinary & health services", amount: tot("veterinary"), classification: "Direct", inDirect: true, inFull: true, inPackaged: true },
    { key: "LabourDirect", label: "Labour (flock-assigned)", amount: tot("labourDirect"), classification: "Direct", inDirect: settings.labourInDirect, inFull: true, inPackaged: true },
    { key: "LabourAllocated", label: "Labour (shared, allocated)", amount: tot("labourAllocated"), classification: "Allocated", inDirect: settings.labourInDirect, inFull: true, inPackaged: true,
      note: settings.labourAllocation === "BirdDays" ? "Allocated by bird-days" : "Allocated by saleable eggs" },
    { key: "OtherDirect", label: "Other flock-assigned expenses", amount: tot("otherDirect"), classification: "Direct", inDirect: true, inFull: true, inPackaged: true },
    { key: "Overhead", label: "Utilities & overhead (shared, allocated)", amount: tot("overheadAllocated"), classification: "Allocated", inDirect: false, inFull: true, inPackaged: true,
      note: settings.overheadAllocation === "BirdDays" ? "Allocated by bird-days" : "Allocated by saleable eggs" },
    { key: "Depreciation", label: "Depreciation", amount: tot("depreciationAllocated"), classification: "Allocated", inDirect: false, inFull: settings.includeDepreciation, inPackaged: settings.includeDepreciation },
    { key: "PreLaying", label: "Pre-laying cost allocation", amount: preLay, classification: preLayEstimate ? "Estimated" : "Allocated", inDirect: false, inFull: settings.includePreLaying, inPackaged: settings.includePreLaying,
      note: "Bird cost + rearing feed/medication + historical entries ÷ expected lifetime saleable eggs" },
    { key: "Packaging", label: "Packaging & supplies", amount: tot("packagingAllocated"), classification: "Allocated", inDirect: false, inFull: false, inPackaged: settings.packagingTreatment === "PackagedOnly",
      note: "Purchases of packaging/supplies in the period -- VisibilityCore does not record packaging use" },
  ]

  const directTotal = round2(sum(comps.filter((c) => c.inDirect).map((c) => c.amount)))
  const fullTotal = round2(sum(comps.filter((c) => c.inFull).map((c) => c.amount)))
  const packagedTotal = round2(sum(comps.filter((c) => c.inPackaged).map((c) => c.amount)))
  const feedTotal = round2(tot("feed") + tot("directFeedExpense"))
  const perEgg = (x: number) => safeDiv(x, saleable)
  const perCrate = (x: number) => { const p = perEgg(x); return p == null ? null : p * epc }

  // ---- selling price (actual, weighted)
  const scopeIds = new Set(sc.map((r) => r.flockId))
  const scopeSales = scope.level === "farm" ? sales : sales.filter((s) => s.flockId != null && scopeIds.has(s.flockId))
  const eggsSold = sum(scopeSales.map((s) => Number(s.eggs) || 0))
  const revenue = round2(sum(scopeSales.map((s) => Number(s.amount) || 0)))
  const sizes = new Map<string, { eggs: number; revenue: number }>()
  for (const s of scopeSales) {
    const k = s.size || "Ungraded"
    const v = sizes.get(k) ?? { eggs: 0, revenue: 0 }
    v.eggs += Number(s.eggs) || 0; v.revenue += Number(s.amount) || 0
    sizes.set(k, v)
  }
  const pricePerEgg = safeDiv(revenue, eggsSold)
  const price: PriceAnalysis = {
    eggsSold, revenue, pricePerEgg,
    pricePerCrate: pricePerEgg == null ? null : pricePerEgg * epc,
    bySize: [...sizes.entries()].map(([size, v]) => {
      const p = safeDiv(v.revenue, v.eggs)
      return { size, eggs: v.eggs, revenue: round2(v.revenue), pricePerCrate: p == null ? null : p * epc }
    }).sort((a, b) => b.eggs - a.eggs),
    untaggedSalesEggs: scope.level === "farm" ? 0 : sum(sales.filter((s) => s.flockId == null).map((s) => Number(s.eggs) || 0)),
    basis: scope.level === "farm" ? "Weighted average of all egg sales in the period"
      : "Weighted average of egg sales recorded against these flocks",
  }

  const fullPerCrate = perCrate(fullTotal)
  const m = price.pricePerCrate != null && fullPerCrate != null ? margin(fullPerCrate, price.pricePerCrate) : null

  // byproduct-adjusted view (explicit policy only; farm scope, or by broken share)
  let byproductAdjustedPerCrate: number | null = null
  if (settings.byproductTreatment === "DeductBrokenEggSales" && facts.brokenEggSales && fullPerCrate != null) {
    const farmBroken = sum(laying.map((r) => r.broken))
    const share = scope.level === "farm" ? 1 : (safeDiv(broken, farmBroken) ?? 0)
    byproductAdjustedPerCrate = perCrate(Math.max(fullTotal - facts.brokenEggSales.amount * share, 0))
  }

  // ---- completeness
  const warnings: Warning[] = []
  const missingDays = sum(sc.map((r) => Math.max(r.activeLayingDays - r.recordDays, 0)))
  const expectedDays = sum(sc.map((r) => r.activeLayingDays))
  if (saleable <= 0) {
    warnings.push({ code: "NoProduction", severity: "missing", message: sc.length
      ? "No saleable eggs were recorded for this selection, so no cost per egg or crate can be worked out."
      : "No laying flocks in this selection for the period." })
  }
  if (missingDays > 0) {
    warnings.push({ code: "MissingRecords", severity: "missing",
      message: `Production records are missing for ${missingDays.toLocaleString()} of ${expectedDays.toLocaleString()} flock-days in this period.` })
  }
  const feedNoCost = sum(sc.map((r) => r.feedWithoutCostRecords))
  if (feedNoCost > 0) {
    warnings.push({ code: "FeedWithoutCost", severity: "missing",
      message: `${feedNoCost.toLocaleString()} production record(s) have feed quantities but no feed cost (feed not issued from tracked stock). Feed cost is understated.` })
  }
  if (saleable > 0 && feedTotal <= 0) warnings.push({ code: "NoFeedCost", severity: "missing", message: "No feed cost was recorded for this period." })
  if (saleable > 0 && tot("labourDirect") + tot("labourAllocated") <= 0) {
    warnings.push({ code: "NoLabour", severity: "missing", message: "Labour costs were not recorded or allocated for this period." })
  }
  if (saleable > 0 && tot("overheadAllocated") + tot("otherDirect") <= 0) {
    warnings.push({ code: "NoOverhead", severity: "missing", message: "No utilities or other overhead expenses were recorded for this period." })
  }
  if (settings.includeDepreciation) {
    if (facts.assetsInService > 0 && shared.Depreciation <= 0 && !costs.some((c) => c.component === "Depreciation")) {
      warnings.push({ code: "NoDepreciation", severity: "missing", message: "Capital assets are in service but no depreciation was posted for this period." })
    } else if (facts.assetsInService === 0) {
      warnings.push({ code: "NoAssets", severity: "info", message: "Depreciation data is not configured (no capital assets recorded)." })
    }
  }
  if (settings.includePreLaying) {
    const noAssumption = sc.filter((r) => r.preLay.status === "NoAssumption")
    const noCost = sc.filter((r) => r.preLay.status === "NoCost")
    if (noAssumption.length) warnings.push({ code: "PreLayAssumption", severity: "missing",
      message: `Pre-laying cost assumptions are unavailable for ${noAssumption.length} flock(s): ${noAssumption.slice(0, 4).map((r) => r.name).join(", ")}${noAssumption.length > 4 ? "…" : ""}. Their pre-laying cost is not included.` })
    if (noCost.length) warnings.push({ code: "PreLayNoCost", severity: "info",
      message: `No pre-laying cost is known for ${noCost.length} flock(s) (no bird cost on the batch, no rearing records, no historical entry).` })
    if (preLayEstimate) warnings.push({ code: "PreLayEstimate", severity: "estimate",
      message: "Pre-laying allocation uses estimated historical costs or an estimated lifetime production." })
  }
  if (unallocatedShared > 0) warnings.push({ code: "Unallocated", severity: "missing",
    message: `Shared costs of ${unallocatedShared.toLocaleString()} could not be allocated (no bird-days or eggs to allocate them by).` })
  if (eggsSold <= 0) warnings.push({ code: "NoSales", severity: "info", message: scope.level === "farm"
    ? "No egg sales in this period -- there is no actual selling price to compare with."
    : "No egg sales were recorded against these flocks -- compare with the farm's price or enter a price in What-If." })
  const exFeed = excluded.get("DirectFeedExpense")
  if (exFeed) warnings.push({ code: "DirectFeedExcluded", severity: "info",
    message: `${exFeed.count} feed expense(s) entered directly (${exFeed.amount.toLocaleString()}) were left out to avoid counting feed twice. Change this in Cost Settings if that feed never went through stock.` })
  if (tot("veterinary") > 0) warnings.push({ code: "VeterinaryExpenses", severity: "info",
    message: `${tot("veterinary").toLocaleString()} of medication / veterinary cost comes from expenses entered directly (not from stock usage). Check none of it is medicine also issued from stock.` })
  if (scope.level !== "farm" && price.untaggedSalesEggs > 0) warnings.push({ code: "UntaggedSales", severity: "info",
    message: `${price.untaggedSalesEggs.toLocaleString()} eggs were sold without a flock, so they are not in this selection's selling price.` })

  const missing = warnings.some((w) => w.severity === "missing")
  const estimated = warnings.some((w) => w.severity === "estimate")
  const completeness: Completeness = saleable <= 0 ? "Insufficient" : missing ? "Partial" : estimated ? "Estimated" : "Complete"

  return {
    calcVersion: CALC_VERSION, startDate: start, endDate: end, scope, eggsPerCrate: epc, settings,
    flocks: all,
    gross, broken, otherLoss, saleable, saleableCrates: saleable / epc,
    components: comps,
    directTotal, fullTotal, packagedTotal, feedTotal,
    directPerEgg: perEgg(directTotal), directPerCrate: perCrate(directTotal),
    fullPerEgg: perEgg(fullTotal), fullPerCrate,
    feedPerCrate: perCrate(feedTotal),
    packagedPerCrate: settings.packagingTreatment === "PackagedOnly" ? perCrate(packagedTotal) : null,
    byproductAdjustedPerCrate,
    price,
    marginPerCrate: m?.margin ?? null,
    marginPct: m?.marginPct ?? null,
    breakEvenPerCrate: fullPerCrate,
    notEggCost: [...notEgg.entries()].filter(([, v]) => v).map(([label, amount]) => ({ label, amount })),
    excluded: [...excluded.entries()].map(([component, v]) => ({ component, label: EXCLUDED_LABELS[component] ?? component, ...v })),
    unallocatedShared,
    completeness, warnings,
    fullLabel: completeness === "Complete" ? "Full Cost Per Crate" : "Estimated Full Cost Per Crate",
    directLabel: completeness === "Complete" ? "Direct Cost Per Crate" : "Recorded Direct Cost Per Crate",
  }
}

// ------------------------------------------------------------------ price & margin maths
/** Margin on the SELLING price (gross margin), the farmer's "I keep 24% of what I charge". */
export function margin(costPerCrate: number, pricePerCrate: number) {
  const m = pricePerCrate - costPerCrate
  return { margin: m, marginPct: pricePerCrate > 0 ? m / pricePerCrate : null, markupPct: costPerCrate > 0 ? m / costPerCrate : null }
}

/** Selling price for a target margin (on price) and, separately, for a target markup (on cost). */
export function targetPrice(costPerCrate: number, targetPct: number) {
  const p = targetPct / 100
  return {
    byMargin: p < 1 ? costPerCrate / (1 - p) : null,
    byMarkup: costPerCrate * (1 + p),
  }
}

/** Saleable crates needed for planned costs to come to a target cost per crate. */
export function targetProduction(plannedTotalCost: number, targetCostPerCrate: number, eggsPerCrate: number) {
  const crates = safeDiv(plannedTotalCost, targetCostPerCrate)
  return { crates, eggs: crates == null ? null : crates * eggsPerCrate }
}

/** Most that can be spent on feed and still hit a cost per crate. */
export function maxFeedCost(expectedSaleableEggs: number, otherCosts: number, desiredCostPerCrate: number, eggsPerCrate: number) {
  const crates = expectedSaleableEggs / eggsPerCrate
  const allowance = desiredCostPerCrate * crates - otherCosts
  return { crates, totalAllowed: desiredCostPerCrate * crates, feedAllowance: allowance, feasible: allowance > 0 }
}

/** The same costs over the eggs left after breakage at two breakage rates. */
export function breakageEffect(totalCost: number, grossEggs: number, fromPct: number, toPct: number, eggsPerCrate: number) {
  const at = (pct: number) => {
    const saleable = grossEggs * (1 - pct / 100)
    const perEgg = safeDiv(totalCost, saleable)
    return { saleable, perCrate: perEgg == null ? null : perEgg * eggsPerCrate }
  }
  const a = at(fromPct), b = at(toPct)
  return { from: a, to: b, extraSaleableEggs: b.saleable - a.saleable,
    savingPerCrate: a.perCrate != null && b.perCrate != null ? a.perCrate - b.perCrate : null }
}

/** The spec's own example: cost per crate from a total and saleable eggs. */
export function costPerCrate(totalCost: number, saleableEggs: number, eggsPerCrate: number): number | null {
  const e = safeDiv(totalCost, saleableEggs)
  return e == null ? null : e * eggsPerCrate
}

// ------------------------------------------------------------------ What-If
export interface ScenarioInputs {
  feedPricePct: number
  feedQuantityPct: number
  medicationPct: number
  labourPct: number
  overheadPct: number
  depreciationPct: number
  preLayPoolPct: number
  expectedLifetimeEggsPct: number
  /** Change in egg output (gross), %. */
  eggOutputPct: number
  /** Productive birds, %. Moves feed quantity and egg output together. */
  birdsPct: number
  /** Broken/lost share of gross eggs, %; null keeps the recorded rate. */
  lossRatePct: number | null
  /** Selling price per crate; null keeps the actual average. */
  sellingPricePerCrate: number | null
  /** Packaging per crate added on top, when the scenario wants one. */
  packagingPct: number
}

export const NEUTRAL_SCENARIO: ScenarioInputs = {
  feedPricePct: 0, feedQuantityPct: 0, medicationPct: 0, labourPct: 0, overheadPct: 0, depreciationPct: 0,
  preLayPoolPct: 0, expectedLifetimeEggsPct: 0, eggOutputPct: 0, birdsPct: 0, lossRatePct: null,
  sellingPricePerCrate: null, packagingPct: 0,
}

export interface ScenarioResult {
  valid: boolean
  errors: string[]
  gross: number
  saleable: number
  saleableCrates: number
  components: { key: string; label: string; baseline: number; scenario: number }[]
  directTotal: number
  fullTotal: number
  directPerCrate: number | null
  fullPerCrate: number | null
  pricePerCrate: number | null
  marginPerCrate: number | null
  marginPct: number | null
  breakEvenPerCrate: number | null
  fullPerCrateChange: number | null
  marginPerCrateChange: number | null
  /** Estimated production margin over the period's saleable crates. */
  periodMargin: number | null
  periodMarginChangePct: number | null
}

export function validateScenario(s: ScenarioInputs): string[] {
  const errors: string[] = []
  const pctKeys: (keyof ScenarioInputs)[] = ["feedPricePct", "feedQuantityPct", "medicationPct", "labourPct", "overheadPct",
    "depreciationPct", "preLayPoolPct", "expectedLifetimeEggsPct", "eggOutputPct", "birdsPct", "packagingPct"]
  for (const k of pctKeys) {
    const v = s[k] as number
    if (!Number.isFinite(v)) errors.push(`${k} must be a number.`)
    else if (v < -100) errors.push(`${k} cannot be below -100% (a quantity cannot go negative).`)
  }
  if (s.expectedLifetimeEggsPct <= -100) errors.push("Expected lifetime eggs cannot fall to zero.")
  if (s.lossRatePct != null && (s.lossRatePct < 0 || s.lossRatePct >= 100)) errors.push("Broken/lost eggs must be between 0% and 100%.")
  if (s.sellingPricePerCrate != null && s.sellingPricePerCrate < 0) errors.push("Selling price cannot be negative.")
  return errors
}

export function runScenario(base: EggCostAnalysis, s: ScenarioInputs): ScenarioResult {
  const errors = validateScenario(s)
  const f = (pct: number) => 1 + pct / 100
  const val = (key: string) => base.components.find((c) => c.key === key)?.amount ?? 0
  const birds = f(s.birdsPct)

  const gross = Math.max(base.gross * f(s.eggOutputPct) * birds, 0)
  const baseLossRate = base.gross > 0 ? (base.gross - base.saleable) / base.gross : 0
  const lossRate = s.lossRatePct != null ? s.lossRatePct / 100 : baseLossRate
  const saleable = base.gross > 0 ? gross * (1 - lossRate) : base.saleable * f(s.eggOutputPct) * birds

  // pre-laying: rate scales with the pool and inversely with expected eggs; the
  // amount follows this scenario's saleable eggs
  const baseRate = safeDiv(val("PreLaying"), base.saleable) ?? 0
  const preLay = baseRate * f(s.preLayPoolPct) / f(s.expectedLifetimeEggsPct) * saleable

  const scen: Record<string, number> = {
    Feed: val("Feed") * f(s.feedPricePct) * f(s.feedQuantityPct) * birds,
    DirectFeedExpense: val("DirectFeedExpense") * f(s.feedPricePct) * f(s.feedQuantityPct) * birds,
    Medication: val("Medication") * f(s.medicationPct),
    Veterinary: val("Veterinary") * f(s.medicationPct),
    LabourDirect: val("LabourDirect") * f(s.labourPct),
    LabourAllocated: val("LabourAllocated") * f(s.labourPct),
    OtherDirect: val("OtherDirect") * f(s.overheadPct),
    Overhead: val("Overhead") * f(s.overheadPct),
    Depreciation: val("Depreciation") * f(s.depreciationPct),
    PreLaying: preLay,
    Packaging: val("Packaging") * f(s.packagingPct) * (base.saleable > 0 ? saleable / base.saleable : 1),
  }
  const comps = base.components.map((c) => ({ key: c.key, label: c.label, baseline: c.amount, scenario: round2(scen[c.key] ?? c.amount) }))
  const directTotal = round2(sum(base.components.filter((c) => c.inDirect).map((c) => scen[c.key] ?? c.amount)))
  const fullTotal = round2(sum(base.components.filter((c) => c.inFull).map((c) => scen[c.key] ?? c.amount)))
  const epc = base.eggsPerCrate
  const directPerCrate = costPerCrate(directTotal, saleable, epc)
  const fullPerCrate = costPerCrate(fullTotal, saleable, epc)
  const price = s.sellingPricePerCrate ?? base.price.pricePerCrate
  const m = price != null && fullPerCrate != null ? margin(fullPerCrate, price) : null
  const crates = saleable / epc
  const periodMargin = m ? m.margin * crates : null
  const basePeriodMargin = base.marginPerCrate != null ? base.marginPerCrate * base.saleableCrates : null
  return {
    valid: errors.length === 0, errors,
    gross, saleable, saleableCrates: crates, components: comps,
    directTotal, fullTotal, directPerCrate, fullPerCrate,
    pricePerCrate: price, marginPerCrate: m?.margin ?? null, marginPct: m?.marginPct ?? null,
    breakEvenPerCrate: fullPerCrate,
    fullPerCrateChange: fullPerCrate != null && base.fullPerCrate != null ? fullPerCrate - base.fullPerCrate : null,
    marginPerCrateChange: m && base.marginPerCrate != null ? m.margin - base.marginPerCrate : null,
    periodMargin,
    periodMarginChangePct: periodMargin != null && basePeriodMargin != null && basePeriodMargin !== 0
      ? (periodMargin - basePeriodMargin) / Math.abs(basePeriodMargin) : null,
  }
}

// ------------------------------------------------------------------ trends
export type TrendGrain = "week" | "month"
export interface TrendPoint {
  label: string
  startDate: string
  endDate: string
  saleable: number
  brokenRate: number | null
  directPerCrate: number | null
  fullPerCrate: number | null
  feedPerCrate: number | null
  pricePerCrate: number | null
  marginPerCrate: number | null
  completeness: Completeness
}

export function buckets(start: string, end: string, grain: TrendGrain): { label: string; startDate: string; endDate: string }[] {
  const out: { label: string; startDate: string; endDate: string }[] = []
  let t = toDay(start)
  const last = toDay(end)
  if (grain === "week") {
    // weeks start Monday
    const dow = (new Date(t).getUTCDay() + 6) % 7
    t -= dow * DAY
    while (t <= last) {
      const s = isoDay(t), e = isoDay(t + 6 * DAY)
      out.push({ label: `Wk of ${s.slice(5)}`, startDate: maxDay(s, start), endDate: minDay(e, end) })
      t += 7 * DAY
    }
  } else {
    let d = new Date(t)
    d = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1))
    while (d.getTime() <= last) {
      const s = isoDay(d.getTime())
      const next = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 1))
      const e = isoDay(next.getTime() - DAY)
      out.push({ label: d.toLocaleString("en", { month: "short", year: "2-digit", timeZone: "UTC" }), startDate: maxDay(s, start), endDate: minDay(e, end) })
      d = next
    }
  }
  return out
}

export function trend(facts: EggCostFacts, scope: Scope, grain: TrendGrain): TrendPoint[] {
  return buckets(facts.startDate, facts.endDate, grain).map((b) => {
    const a = analyze(facts, scope, b)
    return {
      ...b,
      saleable: a.saleable,
      brokenRate: safeDiv(a.broken, a.gross),
      directPerCrate: a.directPerCrate, fullPerCrate: a.fullPerCrate, feedPerCrate: a.feedPerCrate,
      pricePerCrate: a.price.pricePerCrate, marginPerCrate: a.marginPerCrate,
      completeness: a.completeness,
    }
  })
}

// ------------------------------------------------------------------ drilldown
export interface SourceRow {
  date: string
  flock: string
  reference: string
  description: string
  quantity: string
  unitCost: number | null
  amount: number
  classification: "Direct" | "Allocated" | "Estimated"
  formula?: string
}

/** The source rows behind one component line, for the scope on screen. */
export function sources(facts: EggCostFacts, a: EggCostAnalysis, key: string): SourceRow[] {
  const inWindow = (d: string) => d.slice(0, 10) >= a.startDate && d.slice(0, 10) <= a.endDate
  const scopeRows = a.flocks.filter((r) => r.inScope && r.isLaying)
  const ids = new Set(scopeRows.map((r) => r.flockId))
  const flockName = (id: number | null) => (id == null ? "—" : facts.flocks.find((f) => f.flockId === id)?.name ?? `#${id}`)
  const firstEgg = new Map(facts.flocks.map((f) => [f.flockId, f.firstEggDate?.slice(0, 10) ?? null]))
  const laidOn = (r: FactRecord) => { const fe = firstEgg.get(r.flockId); return fe != null && r.date.slice(0, 10) >= fe }

  if (key === "Feed" || key === "Medication") {
    const kind = key === "Feed" ? "Feed" : "Medication"
    const recs = facts.records.filter((r) => ids.has(r.flockId) && inWindow(r.date) && laidOn(r))
    const out: SourceRow[] = []
    for (const r of recs) {
      const lines = facts.recordLines.filter((l) => l.recordId === r.id && l.kind === kind)
      if (lines.length) {
        for (const l of lines) out.push({
          date: r.date, flock: flockName(r.flockId), reference: `Production record #${r.id}`,
          description: l.item ?? kind, quantity: l.quantity != null ? String(l.quantity) : "",
          unitCost: l.unitCost, amount: Number(l.totalCost) || 0, classification: "Direct",
        })
      } else {
        const amt = kind === "Feed" ? r.feedCost : r.medicationCost
        if (amt > 0 || (kind === "Feed" && r.feedKg > 0)) out.push({
          date: r.date, flock: flockName(r.flockId), reference: `Production record #${r.id}`,
          description: kind === "Feed" && amt === 0 ? "Feed recorded WITHOUT a cost" : `${kind} (record total)`,
          quantity: kind === "Feed" ? `${r.feedKg} kg` : "", unitCost: null, amount: amt, classification: "Direct",
        })
      }
    }
    return out
  }

  if (key === "PreLaying") {
    return scopeRows.filter((r) => r.preLay.pool > 0 || r.preLay.status !== "NoCost").map((r) => ({
      date: "", flock: r.name, reference: r.preLay.status,
      description: [
        r.preLay.birdCost ? `Birds ${round2(r.preLay.birdCost).toLocaleString()}` : "",
        r.preLay.rearingFeed ? `Rearing feed ${round2(r.preLay.rearingFeed).toLocaleString()}` : "",
        r.preLay.rearingMedication ? `Rearing medication ${round2(r.preLay.rearingMedication).toLocaleString()}` : "",
        r.preLay.historical ? `Historical ${round2(r.preLay.historical).toLocaleString()}` : "",
        r.preLay.residualDeducted ? `less residual ${round2(r.preLay.residualDeducted).toLocaleString()}` : "",
      ].filter(Boolean).join(" + ") || "No pre-laying cost",
      quantity: `${r.saleable.toLocaleString()} eggs`,
      unitCost: r.preLay.ratePerEgg,
      amount: r.preLay.allocated,
      classification: r.preLay.hasEstimate ? "Estimated" : "Allocated",
      formula: r.preLay.ratePerEgg != null
        ? `Pool ${round2(r.preLay.pool).toLocaleString()} ÷ ${r.preLay.expectedLifetimeEggs?.toLocaleString()} expected eggs (${r.preLay.expectedBasis}) = ${r.preLay.ratePerEgg.toFixed(4)} per egg × ${r.saleable.toLocaleString()} saleable eggs`
        : r.preLay.status === "NoAssumption" ? "Not applied: no expected lifetime production stated for this flock" : undefined,
    }))
  }

  const comp = ({
    LabourDirect: ["Labour"], LabourAllocated: ["Labour"], Overhead: ["Utilities", "Overhead"], OtherDirect: ["Utilities", "Overhead"],
    Depreciation: ["Depreciation"], Packaging: ["Packaging"], Veterinary: ["Veterinary"], DirectFeedExpense: ["DirectFeedExpense"],
  } as Record<string, string[]>)[key] ?? []
  const wantTagged = key === "LabourDirect" || key === "OtherDirect"
  const wantShared = key === "LabourAllocated" || key === "Overhead"
  const allocKey: keyof FlockCostRow = key === "LabourAllocated" ? "labourAllocated"
    : key === "Overhead" ? "overheadAllocated" : key === "Depreciation" ? "depreciationAllocated"
      : key === "Packaging" ? "packagingAllocated" : key === "Veterinary" ? "veterinary" : "directFeedExpense"
  const isShared = (c: FactCost) => c.flockId == null || !a.flocks.some((r) => r.flockId === c.flockId)
  const window = facts.costs.filter((c) => inWindow(c.date) && comp.includes(c.component))
  // A tagged row counts for its flock only on or after its first egg (as in analyze()).
  const taggedHere = (c: FactCost) => {
    if (c.flockId == null || !ids.has(c.flockId)) return false
    const fe = firstEgg.get(c.flockId)
    return fe != null && c.date.slice(0, 10) >= fe
  }
  // This selection's part of the shared pool = what analyze() allocated to its
  // flocks, less the tagged rows that were added to the same field.
  const sharedTotal = window.filter(isShared).reduce((s, x) => s + x.amount, 0)
  const scopeField = scopeRows.reduce((s, r) => s + (Number(r[allocKey]) || 0), 0)
  const taggedInField = key === "LabourAllocated" || key === "Overhead" ? 0
    : window.filter(taggedHere).reduce((s, x) => s + x.amount, 0)
  const ratio = sharedTotal > 0 ? Math.max(scopeField - taggedInField, 0) / sharedTotal : 0
  const basis = key === "Packaging" || key === "DirectFeedExpense" ? "by saleable eggs"
    : (key === "LabourAllocated" ? a.settings.labourAllocation : a.settings.overheadAllocation) === "BirdDays" ? "by bird-days" : "by saleable eggs"

  const picked = window.filter((c) => (wantTagged ? taggedHere(c) : wantShared ? isShared(c) : isShared(c) || taggedHere(c)))
  // Each shared row's share, distributed so the rows add up to the component to the cent.
  const sharedRows = picked.filter((c) => !taggedHere(c))
  const shares = allocate(round2(Math.max(scopeField - taggedInField, 0)), sharedRows.map((c) => ({ key: c.expenseId, weight: c.amount })))
  return picked
    .map((c) => {
      const tagged = taggedHere(c)
      let amount = c.amount
      let formula: string | undefined
      if (!tagged) {
        amount = shares.get(c.expenseId) ?? 0
        formula = `${c.amount.toLocaleString()} shared × ${(ratio * 100).toFixed(1)}% to this selection (${basis})`
      }
      return {
        date: c.date, flock: tagged ? flockName(c.flockId) : "Shared",
        reference: `Expense #${c.expenseId}${c.sourceType ? ` · ${c.sourceType}` : ""}`,
        description: [c.assetName, c.category, c.description].filter(Boolean).join(" — "),
        quantity: "", unitCost: null, amount, classification: tagged ? "Direct" as const : "Allocated" as const, formula,
      }
    })
}
