// Initial Farm Setup: the pure part.
//
// An established poultry farm arriving with birds already in its pens has to be
// able to say what is standing there TODAY — without the application deciding
// that everything which happened to those birds beforehand happened on the day
// they signed up.
//
// THE ARITHMETIC THAT MATTERS
// ---------------------------
// A flock placed with 1,050 birds that has 960 left has a historical reduction
// of 90. Those 90 belong to the OPENING POSITION, never to a production record.
// The flock is created holding 960 — the figure current-bird maths reads when
// there are no production records — so the first real day of tracking starts at
// 960 and subtracts only what really died that day.
//
// And the rule the whole feature turns on: when the farm cannot break the 90
// down, the 90 is an unknown adjustment. It is NOT mortality. Known lifetime
// mortality is what was stated plus what has been recorded since, and never the
// raw difference.
//
// The same rules exist on the server in PoultryFarmAPI/Business/FarmSetupValidator.cs
// and that copy is the one that decides. This one exists so the grids can flag a
// bad row as it is typed. Messages are worded identically.

import type { BatchPurchaseDraft, BatchPurchasePatch } from "@/lib/poultry/batch-purchase"
// The even split is the Batch Allocation tool's; this module borrows it rather
// than keeping a second copy of the same arithmetic.
import { distributeEqually } from "@/lib/flocks/allocation"

/** Limits mirrored from FarmSetupValidator.cs. */
export const MAX_BATCHES = 50
export const MAX_HOUSES = 200
export const MAX_FLOCKS = 200
export const MAX_NAME_LENGTH = 100
export const MAX_BATCH_CODE_LENGTH = 25

/** How the farm is arriving. Only "existing" reaches the opening-position wizard. */
export type SetupMode = "existing" | "newBatch"

export interface BatchRow {
  /** Stable key rows refer to. Not an id: a batch may not exist yet. */
  key: string
  /** Set when reusing a batch the farm already has. */
  existingBatchId?: number | null
  batchName: string
  batchCode: string
  breed: string
  /** Form state, hence a string. */
  numberOfBirds: string
  startDate: string
  costPerChick: string
  supplierId?: number | null
  notes?: string

  /**
   * Whether this purchase happened BEFORE the application started tracking the
   * farm. Per batch, not per session: a farm onboarded last year comes back
   * having just bought a new batch, and that one is a real purchase with real
   * cash behind it while the rest are history.
   *
   * Drives three things -- whether an expense is posted, what date the bird-stock
   * movement takes, and whether the batch must be fully allocated.
   */
  isHistorical: boolean

  // The rest of what the normal Flock Purchases form captures, so a farm that
  // knows its purchase details does not have to leave setup and edit the batch
  // afterwards to record them. All optional.
  totalCost: string
  amountPaid: string
  supplierType: string
  dollarConversionRate: string
  orderPlacementDate: string
  estimatedArrivalDate: string
}

export interface HouseRow {
  key: string
  existingHouseId?: number | null
  houseName: string
  capacity: string
  location: string
}

export interface FlockRow {
  key: string
  batchKey: string
  houseKey: string
  name: string
  originallyPlaced: string
  currentLiveBirds: string
  /** "date" = a placement date is known; "age" = only the current age is. */
  ageMode: "date" | "age"
  startDate: string
  currentAgeInWeeks: string
  historyKnown: boolean
  historicalMortality: string
  historicalSold: string
  historicalCulled: string
  historicalTransferred: string
  notes?: string

  /**
   * Whether the farm has actually worked on this flock's reconciliation.
   *
   * Set by editing the panel, never by the pre-fill. It is what lets the
   * mortality default be re-applied when the bird counts change, while leaving
   * a farm that has said "I don't know" — or typed its own figures — alone.
   */
  reconciliationTouched: boolean

  /** Optional override; blank means the flock takes its batch's breed. */
  breed: string
  /**
   * Whether the birds are physically in the pen. True for anything an
   * established farm is onboarding. Meaningful for a NEW purchase, which can be
   * allocated before it arrives.
   */
  hasArrived: boolean
}

export interface SetupDraft {
  mode: SetupMode
  batches: BatchRow[]
  houses: HouseRow[]
  flocks: FlockRow[]
}

/** A house the farm already has, with what is standing in it. */
export interface ExistingHouse {
  houseId: number
  houseName: string
  capacity?: number | null
  occupied: number
  availableCapacity?: number | null
  activeFlocks: number
}

export interface ExistingBatch {
  batchId: number
  batchCode: string
  batchName: string
  breed: string
  numberOfBirds: number
  startDate?: string
  /** Migration 326. Absent on an older server, which means a current purchase. */
  isHistorical?: boolean
}

/** A flock the farm already has. Read-only context for the allocation step. */
export interface ExistingFlock {
  flockId: number
  name: string
  batchId?: number | null
  houseId?: number | null
  houseName?: string | null
  quantity: number
  active: boolean
}

export interface SetupContext {
  existingBatches: ExistingBatch[]
  existingHouses: ExistingHouse[]
  existingFlocks: ExistingFlock[]
  existingFlockNames: string[]
  /** Birds already allocated out of each existing batch. */
  allocatedByBatchId: Record<number, number>
  /** The company's business date, from the server. */
  businessDate: string
}

export type SetupSection = "batches" | "houses" | "flocks" | "setup"

export interface SetupRowError {
  section: SetupSection
  /** Index into that section, or -1 for the setup as a whole. */
  index: number
  field: string
  message: string
}

let seq = 0
// A per-page-load suffix. The counter restarts at zero on every load, so after a
// refresh restores a saved draft a newly added row would be handed a key an
// existing row already holds -- duplicate React keys, and rows that swap their
// contents when one is removed. The suffix makes a collision impossible without
// making the keys unreadable.
const KEY_RUN = Math.random().toString(36).slice(2, 6)
const nextKey = (prefix: string) => `${prefix}-${KEY_RUN}-${++seq}`

export const normalize = (raw: string | null | undefined): string => (raw ?? "").trim()

export const duplicateKey = (raw: string | null | undefined): string =>
  normalize(raw).replace(/\s+/g, " ").toLowerCase()

/** Whole number from form text; undefined when the text is not one. */
export function parseCount(raw: string | null | undefined): number | undefined {
  const trimmed = normalize(raw)
  if (trimmed.length === 0) return 0
  if (!/^-?\d+$/.test(trimmed)) return undefined
  const n = Number(trimmed)
  return Number.isSafeInteger(n) ? n : undefined
}

const count = (raw: string | null | undefined): number => {
  const n = parseCount(raw)
  return n === undefined || n < 0 ? 0 : n
}

export function emptyBatch(): BatchRow {
  return {
    key: nextKey("batch"), batchName: "", batchCode: "", breed: "",
    numberOfBirds: "", startDate: "", costPerChick: "",
    // The wizard exists for birds a farm already has, so a batch is historical
    // until someone says otherwise.
    isHistorical: true,
    totalCost: "", amountPaid: "", supplierType: "local",
    dollarConversionRate: "", orderPlacementDate: "", estimatedArrivalDate: "",
  }
}

export function emptyHouse(capacity = "", location = ""): HouseRow {
  return { key: nextKey("house"), houseName: "", capacity, location }
}

export function emptyFlock(batchKey = "", houseKey = ""): FlockRow {
  return {
    key: nextKey("flock"), batchKey, houseKey, name: "",
    originallyPlaced: "", currentLiveBirds: "",
    ageMode: "date", startDate: "", currentAgeInWeeks: "",
    breed: "", hasArrived: true,
    historyKnown: false, reconciliationTouched: false,
    historicalMortality: "", historicalSold: "", historicalCulled: "", historicalTransferred: "",
  }
}

export interface GenerateBatchOptions {
  count: number
  /** Name prefix: "Batch" -> "Batch 1". */
  prefix: string
  /** Code prefix: "B" -> "B1". No space, because codes are identifiers. */
  codePrefix: string
  startNumber: number
  breed: string
  numberOfBirds: string
  startDate: string
}

/**
 * Build `count` batch rows, numbered from `startNumber`.
 *
 * The counterpart of the Houses step's generator (lib/houses/bulk.ts), and
 * deliberately the same shape: a convenience that produces ordinary editable
 * rows, never a shortcut past validation. Batch CODES are identifiers and must
 * be unique, so they get their own prefix and no space -- "B1", not "Batch 1",
 * which would collide with the name and read badly in a code column.
 */
export function generateBatches(options: GenerateBatchOptions): BatchRow[] {
  const count = Math.max(0, Math.min(Math.floor(options.count || 0), MAX_BATCHES))
  const prefix = normalize(options.prefix)
  const codePrefix = normalize(options.codePrefix)
  const start = Number.isFinite(options.startNumber) ? Math.floor(options.startNumber) : 1

  const rows: BatchRow[] = []
  for (let i = 0; i < count; i++) {
    const n = start + i
    rows.push({
      key: nextKey("batch"),
      // A blank prefix gives plain numbers rather than a leading space, the
      // same rule the house generator follows.
      batchName: prefix ? `${prefix} ${n}` : String(n),
      batchCode: codePrefix ? `${codePrefix}${n}` : String(n),
      breed: normalize(options.breed),
      numberOfBirds: normalize(options.numberOfBirds),
      startDate: normalize(options.startDate),
      costPerChick: "",
      isHistorical: true,
    totalCost: "", amountPaid: "", supplierType: "local",
    dollarConversionRate: "", orderPlacementDate: "", estimatedArrivalDate: "",
    })
  }
  return rows
}

/** Existing records the farm already has, turned into reusable rows. */
export function batchRowFromExisting(batch: ExistingBatch): BatchRow {
  return {
    key: nextKey("batch"),
    existingBatchId: batch.batchId,
    batchName: batch.batchName,
    batchCode: batch.batchCode,
    breed: batch.breed,
    numberOfBirds: String(batch.numberOfBirds),
    startDate: batch.startDate ? String(batch.startDate).split("T")[0] : "",
    costPerChick: "",
    // A reused batch keeps whatever it was recorded as; the server reads the
    // stored flag and ignores anything the client claims for it.
    isHistorical: batch.isHistorical ?? false,
    totalCost: "", amountPaid: "", supplierType: "local",
    dollarConversionRate: "", orderPlacementDate: "", estimatedArrivalDate: "",
  }
}

export function houseRowFromExisting(house: ExistingHouse): HouseRow {
  return {
    key: nextKey("house"),
    existingHouseId: house.houseId,
    houseName: house.houseName,
    capacity: house.capacity != null ? String(house.capacity) : "",
    location: "",
  }
}

/** "B1 - Pen 1", following the batch-allocation convention. */
export function defaultFlockName(batchCode: string, houseName: string): string {
  const code = normalize(batchCode)
  const house = normalize(houseName)
  if (!code) return house
  if (!house) return code
  return `${code} - ${house}`
}

/**
 * What a flock should be called once its pen changes.
 *
 * A generated name has to follow the pen. "B1 - Pen 3" left sitting on a flock
 * that is now in Pen 5 is worse than no name at all, because it reads like a
 * fact. But a name the FARM wrote is theirs, and moving the flock is no reason
 * to throw it away.
 *
 * The two are told apart by asking what we would have generated for the pen it
 * is leaving: if the name still says exactly that, it is ours to update.
 * Comparison ignores case and spacing, so a name that only differs in those is
 * still recognised as generated.
 */
export function renameForHouse(
  currentName: string,
  batchCode: string,
  previousHouseName: string,
  nextHouseName: string,
): string {
  const generatedBefore = defaultFlockName(batchCode, previousHouseName)
  const isOurs = !normalize(currentName)
    || duplicateKey(currentName) === duplicateKey(generatedBefore)
  return isOurs ? defaultFlockName(batchCode, nextHouseName) : currentName
}

/**
 * Birds unaccounted for between placement and today. Never negative — more birds
 * standing than were placed is a row error, not something to clamp away.
 */
export function historicalReduction(flock: FlockRow): number {
  return Math.max(0, count(flock.originallyPlaced) - count(flock.currentLiveBirds))
}

export interface OpeningBreakdown {
  mortality: number
  sold: number
  culled: number
  transferred: number
  /** What the stated buckets do not cover. Unknown — never mortality. */
  other: number
  /** mortality + sold + culled + transferred, as stated. */
  stated: number
  difference: number
  /** True when the stated buckets claim more birds than actually went missing. */
  overStated: boolean
}

/**
 * The breakdown a flock's opening position will carry.
 *
 * With `historyKnown` false the ENTIRE difference is an unknown adjustment and
 * every other bucket is zero. This is the line between "90 birds are gone" and
 * "90 birds died", and the application must never cross it on the farm's behalf.
 */
export function breakdown(flock: FlockRow): OpeningBreakdown {
  const difference = historicalReduction(flock)
  if (!flock.historyKnown) {
    return { mortality: 0, sold: 0, culled: 0, transferred: 0, other: difference, stated: 0, difference, overStated: false }
  }

  const mortality = count(flock.historicalMortality)
  const sold = count(flock.historicalSold)
  const culled = count(flock.historicalCulled)
  const transferred = count(flock.historicalTransferred)
  const stated = mortality + sold + culled + transferred
  return {
    mortality, sold, culled, transferred,
    other: Math.max(0, difference - stated),
    stated,
    difference,
    overStated: stated > difference,
  }
}

/** Flocks that need the reconciliation step at all. */
export function flocksNeedingReconciliation(flocks: FlockRow[]): FlockRow[] {
  return flocks.filter((f) => historicalReduction(f) > 0)
}

/**
 * A start date derived from a stated age: whole weeks back from the opening
 * date. An approximation, and recorded as estimated so nothing downstream
 * presents it as an exact historical fact.
 */
export function deriveStartDate(businessDate: string, ageInWeeks: number): string {
  const base = new Date(`${businessDate}T00:00:00Z`)
  if (Number.isNaN(base.getTime())) return businessDate
  base.setUTCDate(base.getUTCDate() - 7 * Math.max(0, Math.floor(ageInWeeks)))
  return base.toISOString().slice(0, 10)
}

/** The start date a flock row will be saved with, derived when only age is known. */
export function resolveStartDate(flock: FlockRow, businessDate: string): { date: string; estimated: boolean } {
  if (flock.ageMode === "date" && normalize(flock.startDate)) {
    return { date: normalize(flock.startDate), estimated: false }
  }
  return { date: deriveStartDate(businessDate, count(flock.currentAgeInWeeks)), estimated: true }
}

export interface SetupTotals {
  batchCount: number
  houseCount: number
  flockCount: number
  /** Birds the batches were bought with. */
  batchBirds: number
  originallyPlaced: number
  openingLiveBirds: number
  historicalReduction: number
  historicalMortality: number
  historicalSold: number
  historicalCulled: number
  historicalTransferred: number
  otherAdjustment: number
  flocksWithUnknownHistory: number
}

export function summarize(draft: SetupDraft): SetupTotals {
  const totals: SetupTotals = {
    batchCount: draft.batches.length,
    houseCount: draft.houses.length,
    flockCount: draft.flocks.length,
    batchBirds: draft.batches.reduce((s, b) => s + count(b.numberOfBirds), 0),
    originallyPlaced: 0,
    openingLiveBirds: 0,
    historicalReduction: 0,
    historicalMortality: 0,
    historicalSold: 0,
    historicalCulled: 0,
    historicalTransferred: 0,
    otherAdjustment: 0,
    flocksWithUnknownHistory: 0,
  }

  for (const flock of draft.flocks) {
    const b = breakdown(flock)
    totals.originallyPlaced += count(flock.originallyPlaced)
    totals.openingLiveBirds += count(flock.currentLiveBirds)
    totals.historicalReduction += b.difference
    totals.historicalMortality += b.mortality
    totals.historicalSold += b.sold
    totals.historicalCulled += b.culled
    totals.historicalTransferred += b.transferred
    totals.otherAdjustment += b.other
    if (!flock.historyKnown && b.difference > 0) totals.flocksWithUnknownHistory++
  }

  return totals
}

/**
 * What a pen is carrying, as the setup sees it.
 *
 * CAPACITY IS A FORWARD-PLANNING FIGURE. It is what decides which pen the NEXT
 * batch can go into -- lib/flocks/allocation.ts fills pens to their remaining
 * capacity when dividing a batch. It is not a statement about what is already
 * standing in a pen, so nothing here lets it populate a bird count or block an
 * onboarding: an established farm's birds are a fact, and when the two disagree
 * it is the capacity that is stale.
 */
export interface HouseLoad {
  label: string
  /** Recorded capacity, or null when none is recorded -- the pen is then unconstrained. */
  capacity: number | null
  /** Birds held by flocks that already exist OUTSIDE this setup. */
  occupied: number
  /** Flocks already in the pen outside this setup. */
  activeFlocks: number
  /** Birds this setup puts in the pen, across every flock row naming it. */
  standing: number
  /** occupied + standing. */
  total: number
  /** How far `total` runs past the recorded capacity. 0 when it fits, or when none is recorded. */
  overBy: number
}

/** Null when the key names no house row, or an existing house the context has lost. */
export function houseLoad(houseKey: string, draft: SetupDraft, context: SetupContext): HouseLoad | null {
  const row = draft.houses.find((h) => h.key === houseKey)
  if (!row) return null

  let capacity: number | null = count(row.capacity) || null
  let occupied = 0
  let activeFlocks = 0
  let label = normalize(row.houseName)
  if (row.existingHouseId != null) {
    const existing = context.existingHouses.find((h) => h.houseId === row.existingHouseId)
    if (!existing) return null
    capacity = existing.capacity && existing.capacity > 0 ? existing.capacity : null
    occupied = existing.occupied
    activeFlocks = existing.activeFlocks
    label = existing.houseName
  }

  const standing = draft.flocks.reduce(
    (sum, f) => (f.houseKey === houseKey ? sum + count(f.currentLiveBirds) : sum), 0)
  const total = occupied + standing

  return {
    label, capacity, occupied, activeFlocks, standing, total,
    overBy: capacity == null ? 0 : Math.max(0, total - capacity),
  }
}

/**
 * The note for a pen holding more than its recorded capacity, or null when it
 * fits or no capacity is recorded.
 *
 * Worded as what it costs GOING FORWARD rather than as a complaint about the
 * past. The birds are real; the number that is wrong is the one the next
 * allocation will read. FarmSetupValidator.cs says the same thing in the same
 * words -- that copy is the one that decides.
 */
export function houseCapacityNote(load: HouseLoad): string | null {
  if (load.capacity == null || load.overBy === 0) return null
  const held = load.occupied > 0 ? ` and already holds ${load.occupied.toLocaleString()}` : ""
  return `${load.label} is recorded as taking ${load.capacity.toLocaleString()} birds${held}, ` +
    `but this setup puts ${load.standing.toLocaleString()} in it. ` +
    `Update the capacity — it is what decides where your next batch can go.`
}

/**
 * Where a batch stands on giving its birds out.
 *
 * "over" is listed first deliberately: it is the only one that blocks, so it is
 * the one a batch strip should surface first.
 */
export type BatchAllocationStatus = "over" | "unallocated" | "partial" | "complete"

export interface BatchAllocationView {
  batch: BatchRow
  /** Index into `draft.batches` — what patchBatch/removeBatch take. */
  index: number
  isExisting: boolean
  /** Birds the batch was bought with. */
  batchBirds: number
  /** Birds earlier sessions already placed out of it. */
  previouslyAllocated: number
  /** Birds THIS session is placing, measured as originally placed. */
  thisAllocation: number
  /** batchBirds − previouslyAllocated. Never negative. */
  available: number
  /** available − thisAllocation. Never negative; see `status` for the over case. */
  remaining: number
  status: BatchAllocationStatus
  /** True when this batch must give out every bird — see isHistoricalBatch. */
  mustBeFullyAllocated: boolean
}

const STATUS_RANK: Record<BatchAllocationStatus, number> = {
  over: 0, unallocated: 1, partial: 2, complete: 3,
}

/**
 * Every batch with the arithmetic the allocation step runs on.
 *
 * MEASURED ON THE PLACED BASIS throughout. A batch's birds are what went in, and
 * `originallyPlaced` is the matching figure on a flock — using current live
 * birds here would make a fully-allocated historical batch look short by its
 * historical reduction, which is the same mistake migration 325 fixed on the
 * server (spflock_getconsumedforbatch).
 */
export function batchAllocationViews(draft: SetupDraft, context: SetupContext): BatchAllocationView[] {
  return draft.batches.map((batch, index) => {
    const isExisting = batch.existingBatchId != null
    const existing = isExisting
      ? context.existingBatches.find((b) => b.batchId === batch.existingBatchId)
      : undefined

    const batchBirds = existing ? existing.numberOfBirds : count(batch.numberOfBirds)
    const previouslyAllocated = existing ? (context.allocatedByBatchId[existing.batchId] ?? 0) : 0
    const thisAllocation = draft.flocks.reduce(
      (sum, f) => (f.batchKey === batch.key ? sum + count(f.originallyPlaced) : sum), 0)

    const available = Math.max(0, batchBirds - previouslyAllocated)
    const placed = previouslyAllocated + thisAllocation

    // Describes the batch's TOTAL state, not just this session's contribution.
    // A batch the farm part-placed months ago is "partial" even when this session
    // has not touched it — it has birds left, which is the thing that matters —
    // while "unallocated" means nothing has ever come out of it. Ranking them
    // apart is what puts a brand-new batch above a part-finished one in the strip.
    let status: BatchAllocationStatus
    if (batchBirds > 0 && placed > batchBirds) status = "over"
    else if (batchBirds > 0 && placed === batchBirds) status = "complete"
    else if (placed === 0) status = "unallocated"
    else status = "partial"

    return {
      batch, index, isExisting, batchBirds, previouslyAllocated, thisAllocation,
      available, remaining: Math.max(0, available - thisAllocation), status,
      mustBeFullyAllocated: isHistoricalBatch(batch, context),
    }
  })
}

/**
 * The batches the allocation step offers, most in need of attention first.
 *
 * A farm returning to place one new batch should not have to scroll past three
 * batches it finished eighteen months ago. By default a FULLY ALLOCATED batch it
 * already had is hidden; anything with birds left, anything added in this
 * session, and anything over-allocated stays, because those are the ones there
 * is work to do on.
 *
 * Nothing is removed from the draft — a hidden batch is still submitted, still
 * reused by id, and `showAll` brings it straight back.
 *
 * `keepKey` is never filtered out, whatever its status. Without it, allocating
 * the last of a reused batch's birds completes it, the filter drops it, and the
 * workspace someone is working in disappears from under them mid-keystroke.
 */
export function visibleBatchRows(
  views: BatchAllocationView[],
  showAll: boolean,
  keepKey?: string,
): BatchAllocationView[] {
  const shown = showAll
    ? [...views]
    : views.filter((v) => v.batch.key === keepKey || !v.isExisting || v.status !== "complete")
  return shown.sort((a, b) => STATUS_RANK[a.status] - STATUS_RANK[b.status] || a.index - b.index)
}

export interface BatchStepSummary {
  total: number
  /** Fully allocated batches the farm already had — hidden unless "show all". */
  hidden: number
  /** Batches still holding birds that nothing has placed. */
  withBirdsLeft: number
}

export function summarizeBatchRows(views: BatchAllocationView[]): BatchStepSummary {
  return {
    total: views.length,
    hidden: views.filter((v) => v.isExisting && v.status === "complete").length,
    withBirdsLeft: views.filter((v) => v.remaining > 0).length,
  }
}

/**
 * A BatchRow as the shared purchase fieldset wants it, and back again.
 *
 * The wizard carries more than a purchase form does — a key, whether the batch
 * is being reused, whether it is historical — so the two types cannot simply be
 * the same one. These adapters are the seam, and they are deliberately dull:
 * every field that exists on both is carried straight across, so adding a field
 * to the shared form is a one-line change here rather than a redesign.
 */
export function batchDraft(row: BatchRow): BatchPurchaseDraft {
  return {
    batchName: row.batchName,
    batchCode: row.batchCode,
    breed: row.breed,
    numberOfBirds: row.numberOfBirds,
    startDate: row.startDate,
    costPerChick: row.costPerChick,
    totalCost: row.totalCost,
    amountPaid: row.amountPaid,
    supplierType: row.supplierType,
    supplierId: row.supplierId != null ? String(row.supplierId) : "",
    dollarConversionRate: row.dollarConversionRate,
    orderPlacementDate: row.orderPlacementDate,
    estimatedArrivalDate: row.estimatedArrivalDate,
    notes: row.notes ?? "",
  }
}

/** The shared form's patch, as a BatchRow patch. */
export function fromBatchDraft(patch: BatchPurchasePatch): Partial<BatchRow> {
  const out: Partial<BatchRow> = {}
  if (patch.batchName !== undefined) out.batchName = patch.batchName
  if (patch.batchCode !== undefined) out.batchCode = patch.batchCode
  if (patch.breed !== undefined) out.breed = patch.breed
  if (patch.numberOfBirds !== undefined) out.numberOfBirds = patch.numberOfBirds
  if (patch.startDate !== undefined) out.startDate = patch.startDate
  if (patch.costPerChick !== undefined) out.costPerChick = patch.costPerChick
  if (patch.totalCost !== undefined) out.totalCost = patch.totalCost
  if (patch.amountPaid !== undefined) out.amountPaid = patch.amountPaid
  if (patch.supplierType !== undefined) out.supplierType = patch.supplierType
  // "" is a real choice here — it means "no supplier" — so it maps to null
  // rather than being dropped as absent.
  if (patch.supplierId !== undefined) out.supplierId = patch.supplierId === "" ? null : Number(patch.supplierId)
  if (patch.dollarConversionRate !== undefined) out.dollarConversionRate = patch.dollarConversionRate
  if (patch.orderPlacementDate !== undefined) out.orderPlacementDate = patch.orderPlacementDate
  if (patch.estimatedArrivalDate !== undefined) out.estimatedArrivalDate = patch.estimatedArrivalDate
  if (patch.notes !== undefined) out.notes = patch.notes
  return out
}

/**
 * Set a flock row's two bird counts.
 *
 * Standing starts EQUAL to placed — a flock that has lost nothing. The farm
 * records losses by lowering the second number, which is the one thing only it
 * can know; guessing a reduction on its behalf would be inventing history.
 */
function withBirds(f: FlockRow, birds: number): FlockRow {
  const value = birds > 0 ? String(birds) : ""
  return { ...f, originallyPlaced: value, currentLiveBirds: value }
}

/** The flock rows belonging to one batch, in draft order. */
const rowsForBatch = (draft: SetupDraft, batchKey: string) =>
  draft.flocks.filter((f) => f.batchKey === batchKey)

/**
 * Spread a batch's available birds evenly across the pens chosen for it.
 *
 * Floor the split and hand the remainder to the first rows, which is exactly
 * what distributeEqually does in the Batch Allocation tool — the two propose
 * identical numbers because a farmer should not get different advice from two
 * screens doing the same arithmetic.
 *
 * A SUGGESTION. Every number stays editable.
 */
export function distributePensEvenly(
  draft: SetupDraft,
  batchKey: string,
  available: number,
): SetupDraft {
  const targets = rowsForBatch(draft, batchKey)
  if (targets.length === 0 || available <= 0) return draft

  // Delegated, not reimplemented. The Batch Allocation tool owns this split, and
  // a farmer must not get different advice from two screens doing the same sum.
  const { rows } = distributeEqually(
    available,
    targets.map((f, n) => ({ id: String(n), houseId: 0, name: f.name, quantity: "" })),
  )
  const share = new Map<string, number>()
  targets.forEach((f, n) => share.set(f.key, count(rows[n].quantity)))

  return {
    ...draft,
    flocks: draft.flocks.map((f) => (share.has(f.key) ? withBirds(f, share.get(f.key)!) : f)),
  }
}

/**
 * Fill each chosen pen to its remaining capacity, in order, until the birds run
 * out.
 *
 * Room is what the pen can still take once everything OUTSIDE this batch is
 * accounted for — the farm's own flocks, and anything another batch in this
 * setup has put there. A pen with no capacity recorded is unconstrained and
 * takes whatever is left, which is the same rule the rest of the module uses.
 *
 * The batch's own rows are cleared first, so running this twice gives the same
 * answer rather than compounding on what it did last time.
 */
export function fillPensToCapacity(
  draft: SetupDraft,
  context: SetupContext,
  batchKey: string,
  available: number,
): SetupDraft {
  const targets = rowsForBatch(draft, batchKey)
  if (targets.length === 0 || available <= 0) return draft

  const targetKeys = new Set(targets.map((f) => f.key))
  // What each pen already holds that this batch is not responsible for.
  const baseline = new Map<string, number>()
  for (const f of draft.flocks) {
    if (targetKeys.has(f.key) || !f.houseKey) continue
    baseline.set(f.houseKey, (baseline.get(f.houseKey) ?? 0) + count(f.currentLiveBirds))
  }

  let remaining = available
  const share = new Map<string, number>()

  for (const f of targets) {
    if (remaining <= 0) {
      share.set(f.key, 0)
      continue
    }
    const row = draft.houses.find((h) => h.key === f.houseKey)
    let capacity: number | null = row ? count(row.capacity) || null : null
    let occupied = 0
    if (row?.existingHouseId != null) {
      const existing = context.existingHouses.find((h) => h.houseId === row.existingHouseId)
      capacity = existing?.capacity && existing.capacity > 0 ? existing.capacity : null
      occupied = existing?.occupied ?? 0
    }
    const used = occupied + (baseline.get(f.houseKey) ?? 0)
    const room = capacity == null ? remaining : Math.max(0, capacity - used)
    const take = Math.min(remaining, room)
    share.set(f.key, take)
    remaining -= take
  }

  return {
    ...draft,
    flocks: draft.flocks.map((f) => (share.has(f.key) ? withBirds(f, share.get(f.key)!) : f)),
  }
}

/** The four buckets the farm can type into. `other` is derived, never typed. */
export type BreakdownField =
  | "historicalMortality" | "historicalSold" | "historicalCulled" | "historicalTransferred"

/**
 * Edit one bucket of the breakdown and keep the total honest.
 *
 * MORTALITY IS THE BALANCING BUCKET. The reconciliation opens with the whole
 * difference sitting in it, so typing 10 into Sold on top of that would claim
 * 91 of an 81-bird gap and earn an error for doing the obviously right thing.
 * Instead the 10 comes OUT of mortality: 71 died, 10 were sold, still 81.
 * Lowering Sold again gives those birds back to mortality.
 *
 * Editing MORTALITY itself leaves the others alone — the farm is stating what
 * died, and whatever that does not cover becomes the unknown remainder, which
 * is what `other` has always been for.
 *
 * Mortality never goes below zero. If the other three alone exceed the gap, it
 * bottoms out and validateSetup reports the over-statement, because at that
 * point the numbers really are wrong and only the farm can say how.
 */
export function balanceBreakdown(
  flock: FlockRow,
  change: Partial<Record<BreakdownField, string>>,
): Partial<FlockRow> {
  const next: Partial<FlockRow> = { ...change, reconciliationTouched: true }
  if ("historicalMortality" in change) return next

  const merged = { ...flock, ...change }
  const claimed = count(merged.historicalSold)
    + count(merged.historicalCulled)
    + count(merged.historicalTransferred)
  const left = Math.max(0, historicalReduction(merged) - claimed)
  next.historicalMortality = left > 0 ? String(left) : "0"
  return next
}

/**
 * Fill in the reconciliation the way it usually turns out: the missing birds
 * died.
 *
 * On most farms the overwhelming majority of the gap between placement and today
 * IS mortality — sales are recorded separately and culls are rare — so starting
 * every flock at "unknown" made the farm retype a figure the application could
 * have offered.
 *
 * It is a PRE-FILL, not an assumption: the number is on screen, in the mortality
 * box, and the farm either agrees with it or changes it. That is the difference
 * between a default and inventing data, and it is why this writes a visible
 * figure rather than quietly classifying unknowns as deaths.
 *
 * Only ever touches a flock the farm has not worked on — `reconciliationTouched`
 * is set by editing the panel, so "I don't know" and hand-typed breakdowns both
 * survive. Re-running it after the bird counts change re-seeds to the new
 * difference, which is why the flag is not set here.
 */
export function seedReconciliation(draft: SetupDraft): SetupDraft {
  return {
    ...draft,
    flocks: draft.flocks.map((f) => {
      if (f.reconciliationTouched) return f
      const difference = historicalReduction(f)
      if (difference <= 0) return f
      return {
        ...f,
        historyKnown: true,
        historicalMortality: String(difference),
        historicalSold: "", historicalCulled: "", historicalTransferred: "",
      }
    }),
  }
}

/**
 * Whether a batch row represents a purchase made before tracking began.
 *
 * A REUSED batch answers from what is stored against it, not from what the row
 * claims: it carries only an id, and the nature of a purchase it is not creating
 * is not its to restate. FarmSetupValidator.IsHistoricalBatch decides the same
 * way, and that copy is the one that counts.
 */
export function isHistoricalBatch(batch: BatchRow, context: SetupContext): boolean {
  if (batch.existingBatchId != null) {
    const existing = context.existingBatches.find((b) => b.batchId === batch.existingBatchId)
    return existing?.isHistorical ?? false
  }
  return batch.isHistorical
}

/** A house row with everything the Houses step needs to decide how to show it. */
export interface HouseRowView {
  row: HouseRow
  /** Index into `draft.houses` — what patchHouse/removeHouse take. */
  index: number
  /** True when this pen already exists on the farm and is only being reused. */
  isExisting: boolean
  load: HouseLoad | null
  /**
   * Whether a new flock could still go in. A pen with no capacity recorded is
   * unconstrained, so it always has room — the same rule the rest of the
   * application uses (FlockAllocationValidator.AvailableCapacity).
   */
  hasRoom: boolean
  /**
   * Nothing in it at all: no existing flock, and nothing this setup has put
   * there yet. Stricter than `hasRoom`, and the right default for the
   * allocation picker — a pen may legally hold several flocks, but offering a
   * pen that already has birds as the obvious choice invites double-counting.
   *
   * A pen this setup has just filled therefore stops being empty, which is what
   * keeps it from being offered to a second row.
   */
  isEmpty: boolean
  /**
   * Nothing in it ON THE FARM — ignoring whatever this setup has put there.
   *
   * The HOUSES step asks this one. "Empty" there has to mean empty of the farm's
   * own birds, or a pen would disappear from the list the moment the setup
   * allocated something to it, and stepping back would look like the pen had
   * been lost.
   */
  isEmptyOnFarm: boolean
}

export function houseRowViews(draft: SetupDraft, context: SetupContext): HouseRowView[] {
  return draft.houses.map((row, index) => {
    const load = houseLoad(row.key, draft, context)
    return {
      row,
      index,
      isExisting: row.existingHouseId != null,
      load,
      hasRoom: load?.capacity == null ? true : load.total < load.capacity,
      // A pen we cannot assess is not hidden: better to offer it than to make it
      // unreachable on the strength of a missing record.
      isEmpty: load ? load.total === 0 : true,
      isEmptyOnFarm: load ? load.occupied === 0 : true,
    }
  })
}

/**
 * The pens the Houses step actually shows.
 *
 * A farm coming back six months later has twenty pens and eighteen of them hold
 * birds. Listing all twenty as editable rows buries the two it came to work with
 * and makes it look as though its whole farm is being recreated. So by default
 * an EXISTING pen is shown only when it is EMPTY; pens being created in this
 * session are always shown, because they are the session's work.
 *
 * Empty, not merely "has room". A pen holding 500 of 2,000 has room and is
 * plainly not empty, and a farm looking for somewhere to put a batch should not
 * have to read past it.
 *
 * Nothing is removed from the draft — the hidden rows are still reused by id on
 * submission, and `showAll` brings them back instantly. What is filtered is the
 * view, never the data.
 */
export function visibleHouseRows(views: HouseRowView[], showAll: boolean): HouseRowView[] {
  if (showAll) return views
  return views.filter((v) => !v.isExisting || v.isEmptyOnFarm)
}

/**
 * The pens the allocation picker offers: everything that still has room.
 *
 * Only FULL pens are withheld, and they are withheld outright — there is no
 * "show all". A pen with no room left is not a choice, so offering it behind a
 * tick box only adds a decision to a step that should be quick.
 *
 * A pen holding 500 of 2,000 IS offered. Several flocks may legally share a pen,
 * and during allocation the farm is looking for anywhere the birds will fit, not
 * only for somewhere untouched. (The HOUSES step asks the stricter question —
 * see visibleHouseRows — because there the farm is describing its buildings
 * rather than filling them.)
 *
 * A pen with no capacity recorded is unconstrained, so it always has room.
 *
 * `selectedKey` is ALWAYS included, whatever its state. A row's own pen can be
 * filled to capacity by that very row, and dropping it from its own picker would
 * blank the field the farm just set.
 */
export function penOptions(views: HouseRowView[], selectedKey?: string): HouseRowView[] {
  return views.filter((v) => v.row.key === selectedKey || v.hasRoom)
}


/** A batch row as the BATCHES step needs to show it. */
export interface BatchEditRow {
  row: BatchRow
  /** Index into `draft.batches` — what patchBatch/removeBatch take. */
  index: number
  isExisting: boolean
}

export function batchEditRows(draft: SetupDraft): BatchEditRow[] {
  return draft.batches.map((row, index) => ({
    row, index, isExisting: row.existingBatchId != null,
  }))
}

/**
 * The batches the BATCHES step actually shows.
 *
 * Only the ones being created. A farm already has its batches recorded — the
 * rows for those are locked, contribute nothing to fill in, and turn a step
 * about describing new stock into a list of old stock to scroll past.
 *
 * They stay in the draft: the allocation step still needs them, because placing
 * the rest of a batch bought months ago is a normal thing to come back and do.
 * What is filtered is the view, never the data.
 *
 * Not the same question as visibleBatchRows, which filters the ALLOCATION strip
 * by how much of a batch is still unplaced. Here the only question is whether
 * the farm is creating it.
 */
export function visibleBatchEditRows(views: BatchEditRow[], showExisting: boolean): BatchEditRow[] {
  return showExisting ? views : views.filter((v) => !v.isExisting)
}

export interface BatchEditSummary {
  total: number
  /** Batches the farm already has — hidden unless asked for. */
  existing: number
}

export function summarizeBatchEditRows(views: BatchEditRow[]): BatchEditSummary {
  return { total: views.length, existing: views.filter((v) => v.isExisting).length }
}

export interface HouseStepSummary {
  total: number
  existing: number
  /** Existing pens that already hold birds — hidden unless "show all" is on. */
  occupied: number
  hidden: number
}

export function summarizeHouseRows(views: HouseRowView[]): HouseStepSummary {
  const existing = views.filter((v) => v.isExisting)
  const occupied = existing.filter((v) => !v.isEmptyOnFarm)
  return {
    total: views.length,
    existing: existing.length,
    occupied: occupied.length,
    hidden: occupied.length,
  }
}

/**
 * Everything wrong with the draft.
 *
 * Errors block. Warnings do not: a house capacity the birds already exceed is a
 * wrong capacity, not a wrong farm, and refusing the onboarding would be
 * refusing reality. Batch totals DO block — flocks placed with more birds than
 * the batch ever held cannot be true.
 */
export function validateSetup(draft: SetupDraft, context: SetupContext): { errors: SetupRowError[]; warnings: SetupRowError[] } {
  const errors: SetupRowError[] = []
  const warnings: SetupRowError[] = []

  const err = (section: SetupSection, index: number, field: string, message: string) =>
    errors.push({ section, index, field, message })
  const warn = (section: SetupSection, index: number, field: string, message: string) =>
    warnings.push({ section, index, field, message })

  if (draft.batches.length > MAX_BATCHES) err("setup", -1, "batches", `At most ${MAX_BATCHES} batches in one setup.`)
  if (draft.houses.length > MAX_HOUSES) err("setup", -1, "houses", `At most ${MAX_HOUSES} houses in one setup.`)
  if (draft.flocks.length > MAX_FLOCKS) err("setup", -1, "flocks", `At most ${MAX_FLOCKS} flocks in one setup.`)
  if (errors.length > 0) return { errors, warnings }

  // ---- Batches ---------------------------------------------------------
  const existingCodes = new Set(context.existingBatches.map((b) => duplicateKey(b.batchCode)))
  const seenCodes = new Set<string>()
  const batchByKey = new Map<string, BatchRow>()

  draft.batches.forEach((b, i) => {
    batchByKey.set(b.key, b)
    if (b.existingBatchId != null) return   // reused: its details are the farm's own

    if (!normalize(b.batchName)) err("batches", i, "batchName", "Batch name is required.")
    else if (normalize(b.batchName).length > MAX_NAME_LENGTH)
      err("batches", i, "batchName", `Batch name cannot be longer than ${MAX_NAME_LENGTH} characters.`)

    const code = normalize(b.batchCode)
    if (!code) err("batches", i, "batchCode", "Batch code is required.")
    else if (code.length > MAX_BATCH_CODE_LENGTH)
      err("batches", i, "batchCode", `Batch code cannot be longer than ${MAX_BATCH_CODE_LENGTH} characters.`)
    else if (existingCodes.has(duplicateKey(code)))
      err("batches", i, "batchCode", `A batch with code "${code}" already exists — reuse it instead of creating a second one.`)
    else if (seenCodes.has(duplicateKey(code)))
      err("batches", i, "batchCode", `"${code}" appears more than once in this setup.`)
    else seenCodes.add(duplicateKey(code))

    // Breed is OPTIONAL. A farm buying from a local hatchery often does not know
    // what it was sold, and refusing the whole batch over it would stop the
    // onboarding for a field nothing depends on. It is still worth having, so the
    // optional-data warnings below mention it.
    if (count(b.numberOfBirds) <= 0) err("batches", i, "numberOfBirds", "Enter how many birds the batch originally had — more than zero.")
    if (!normalize(b.startDate)) err("batches", i, "startDate", "Give the batch an arrival or placement date.")
  })

  // ---- Houses ----------------------------------------------------------
  const existingHouseNames = new Set(context.existingHouses.map((h) => duplicateKey(h.houseName)))
  const seenHouseNames = new Set<string>()
  const houseByKey = new Map<string, HouseRow>()

  draft.houses.forEach((h, i) => {
    houseByKey.set(h.key, h)
    if (h.existingHouseId != null) return

    const name = normalize(h.houseName)
    if (!name) err("houses", i, "houseName", "House name is required.")
    else if (name.length > MAX_NAME_LENGTH)
      err("houses", i, "houseName", `House name cannot be longer than ${MAX_NAME_LENGTH} characters.`)
    else if (existingHouseNames.has(duplicateKey(name)))
      err("houses", i, "houseName", `A house named "${name}" already exists — select it instead of creating a second one.`)
    else if (seenHouseNames.has(duplicateKey(name)))
      err("houses", i, "houseName", `"${name}" appears more than once in this setup.`)
    else seenHouseNames.add(duplicateKey(name))

    if (parseCount(h.capacity) === undefined) err("houses", i, "capacity", "Capacity must be a whole number.")
    else if (count(h.capacity) < 0) err("houses", i, "capacity", "Capacity cannot be negative.")
  })

  // ---- Flocks ----------------------------------------------------------
  const existingNames = new Set(context.existingFlockNames.map(duplicateKey).filter(Boolean))
  const nameCounts = new Map<string, number>()
  for (const f of draft.flocks) {
    const key = duplicateKey(f.name)
    if (!key) continue
    nameCounts.set(key, (nameCounts.get(key) ?? 0) + 1)
  }

  const placedByBatchKey = new Map<string, number>()
  const standingByHouseKey = new Map<string, number>()
  // Of the standing birds, the ones being placed from a NEW purchase.
  const newBirdsByHouseKey = new Map<string, number>()

  draft.flocks.forEach((f, i) => {
    const name = normalize(f.name)
    if (!name) err("flocks", i, "name", "Flock name is required.")
    else if (name.length > MAX_NAME_LENGTH)
      err("flocks", i, "name", `Flock name cannot be longer than ${MAX_NAME_LENGTH} characters.`)
    else if ((nameCounts.get(duplicateKey(name)) ?? 0) > 1)
      err("flocks", i, "name", `"${name}" appears more than once in this setup.`)
    else if (existingNames.has(duplicateKey(name)))
      err("flocks", i, "name", `A flock named "${name}" already exists on this farm.`)

    const placed = parseCount(f.originallyPlaced)
    const live = parseCount(f.currentLiveBirds)

    if (placed === undefined) err("flocks", i, "originallyPlaced", "Originally placed must be a whole number.")
    else if (placed <= 0) err("flocks", i, "originallyPlaced", "Enter how many birds were originally placed in this flock.")

    if (live === undefined) err("flocks", i, "currentLiveBirds", "Current live birds must be a whole number.")
    else if (live < 0) err("flocks", i, "currentLiveBirds", "Current live birds cannot be negative.")
    else if (placed !== undefined && placed > 0 && live > placed)
      err("flocks", i, "currentLiveBirds",
        `There cannot be more birds standing (${live.toLocaleString()}) than were placed (${placed.toLocaleString()}).`)

    if (f.ageMode === "date" && !normalize(f.startDate))
      err("flocks", i, "startDate", "Give either the placement date or the flock's current age in weeks.")
    if (f.ageMode === "age" && parseCount(f.currentAgeInWeeks) === undefined)
      err("flocks", i, "currentAgeInWeeks", "Current age must be a whole number of weeks.")

    if (f.historyKnown) {
      const b = breakdown(f)
      if (b.overStated)
        err("flocks", i, "breakdown",
          `The breakdown adds up to ${b.stated.toLocaleString()} but only ${b.difference.toLocaleString()} birds remain to account for.`)
    }

    if (!f.batchKey || !batchByKey.has(f.batchKey)) err("flocks", i, "batchKey", "Choose which batch this flock came from.")
    else placedByBatchKey.set(f.batchKey, (placedByBatchKey.get(f.batchKey) ?? 0) + count(f.originallyPlaced))

    if (!f.houseKey || !houseByKey.has(f.houseKey)) err("flocks", i, "houseKey", "Choose which house/pen this flock is in.")
    else {
      standingByHouseKey.set(f.houseKey, (standingByHouseKey.get(f.houseKey) ?? 0) + count(f.currentLiveBirds))

      // Birds from a NEW purchase are being placed by a decision made right now,
      // so capacity gets to refuse them. Birds from a batch the farm already had
      // are standing in the pen whatever the capacity says.
      const fb = f.batchKey ? batchByKey.get(f.batchKey) : undefined
      if (fb && !isHistoricalBatch(fb, context)) {
        newBirdsByHouseKey.set(f.houseKey, (newBirdsByHouseKey.get(f.houseKey) ?? 0) + count(f.currentLiveBirds))
      }
    }
  })

  // ---- Batch integrity: an ERROR ---------------------------------------
  placedByBatchKey.forEach((placed, key) => {
    const batch = batchByKey.get(key)
    if (!batch) return
    const index = draft.batches.indexOf(batch)

    let capacity = count(batch.numberOfBirds)
    let alreadyAllocated = 0
    let label = normalize(batch.batchCode)
    if (batch.existingBatchId != null) {
      const existing = context.existingBatches.find((b) => b.batchId === batch.existingBatchId)
      if (!existing) return
      capacity = existing.numberOfBirds
      alreadyAllocated = context.allocatedByBatchId[existing.batchId] ?? 0
      label = existing.batchCode
    }
    if (capacity <= 0) return

    if (placed + alreadyAllocated > capacity) {
      const allocatedNote = alreadyAllocated > 0 ? ` (${alreadyAllocated.toLocaleString()} already allocated)` : ""
      err("batches", index, "numberOfBirds",
        `Flocks from ${label} were placed with ${placed.toLocaleString()} birds${allocatedNote}, but the batch only had ${capacity.toLocaleString()}.`)
    } else if (isHistoricalBatch(batch, context) && placed + alreadyAllocated < capacity) {
      // A HISTORICAL batch must be fully accounted for. Its birds are not a plan
      // -- they are standing in pens right now, so every one of them has a pen.
      // Birds left over would mean the farm cannot say where they are, and they
      // would sit in the bird ledger forever as stock no flock holds.
      //
      // A NEW purchase is the opposite case and stays partial-legal: 12,000
      // chicks bought today may have only 8,000 placed so far.
      const missing = capacity - (placed + alreadyAllocated)
      err("batches", index, "numberOfBirds",
        `${label} is a batch you already had, so all ${capacity.toLocaleString()} of its birds must be in a pen — ` +
        `${missing.toLocaleString()} are unaccounted for. Put them in a pen, or lower the batch to ${(placed + alreadyAllocated).toLocaleString()}.`)
    }
  })

  // The flock list is what tells us how many birds the farm has, so an empty one
  // is fatal — but it is appended LAST rather than short-circuiting the function.
  // Returning early here meant the batch and house grids were never validated at
  // all while the user was filling them in (flocks are only built on leaving the
  // Houses step), and the resulting always-present error blocked every Continue.
  if (draft.flocks.length === 0) {
    err("setup", -1, "flocks", "Add at least one flock — that is what tells us how many birds you have.")
  }

  // ---- House capacity: a WARNING ---------------------------------------
  // The pen is the FIRST field on a flock row, so by the time the bird counts
  // are typed the capacity is already known -- which is where this is now shown,
  // against the pen, as it happens (see the House/Pen field in
  // app/poultry-farm-setup/page.tsx). It is repeated on Review from this same
  // computation so the two cannot word it differently.
  standingByHouseKey.forEach((_standing, key) => {
    const house = houseByKey.get(key)
    if (!house) return
    const load = houseLoad(key, draft, context)
    if (!load || load.capacity == null || load.overBy === 0) return

    const index = draft.houses.indexOf(house)
    const newBirds = newBirdsByHouseKey.get(key) ?? 0

    if (newBirds > 0) {
      // Birds from a new purchase are still a PLAN, and a plan that overfills a
      // pen is refused -- the same answer the Batch Allocation tool gives,
      // because it is the same decision.
      const occupiedNote = load.occupied > 0 ? ` and already holds ${load.occupied.toLocaleString()}` : ""
      const room = Math.max(0, load.capacity - load.occupied - (load.standing - newBirds))
      err("houses", index, "capacity",
        `${load.label} holds ${load.capacity.toLocaleString()} birds${occupiedNote}. ` +
        `You are placing ${newBirds.toLocaleString()} newly bought birds in it and only ${room.toLocaleString()} will fit.`)
    } else {
      // Every bird here is already standing in the pen. Capacity is a
      // forward-planning figure and does not get to refuse a fact.
      const note = houseCapacityNote(load)
      if (note) warn("houses", index, "capacity", note)
    }
  })

  // ---- Optional data: INFORMATIONAL only -------------------------------
  // Never blocks. The point is that a farm should not discover six months later
  // that it could have recorded who it bought from; the point is not to make it
  // do so now.
  draft.batches.forEach((b, i) => {
    if (b.existingBatchId != null) return
    if (b.supplierId == null) {
      warn("batches", i, "supplierId",
        `${normalize(b.batchCode) || `Batch ${i + 1}`} has no supplier recorded. You can complete this later.`)
    }
    if (count(b.costPerChick) === 0 && count(b.totalCost) === 0) {
      warn("batches", i, "costPerChick",
        `${normalize(b.batchCode) || `Batch ${i + 1}`} has no purchase cost recorded. You can complete this later.`)
    }
    if (!normalize(b.breed)) {
      warn("batches", i, "breed",
        `${normalize(b.batchCode) || `Batch ${i + 1}`} has no breed recorded. You can complete this later.`)
    }
  })

  return { errors, warnings }
}

/** Errors keyed by section then index then field, so a cell can render its own. */
export function errorsBySection(errors: SetupRowError[]): Record<string, Record<number, Record<string, string>>> {
  const map: Record<string, Record<number, Record<string, string>>> = {}
  for (const e of errors) {
    if (e.index < 0) continue
    map[e.section] ??= {}
    map[e.section][e.index] = { ...(map[e.section][e.index] ?? {}), [e.field]: e.message }
  }
  return map
}

/** The request body. Keys travel as-is; the server resolves them to real ids. */
export function toRequest(draft: SetupDraft, context: SetupContext, userId: string, farmId: string) {
  return {
    UserId: userId,
    FarmId: farmId,
    SetupMode: "ExistingFarm",
    Source: "Initial Farm Setup",
    Batches: draft.batches.map((b) => ({
      Key: b.key,
      ExistingBatchId: b.existingBatchId ?? null,
      BatchName: normalize(b.batchName),
      BatchCode: normalize(b.batchCode),
      Breed: normalize(b.breed),
      NumberOfBirds: count(b.numberOfBirds),
      StartDate: normalize(b.startDate) ? `${normalize(b.startDate)}T00:00:00` : null,
      CostPerChick: normalize(b.costPerChick) ? Number(b.costPerChick) : null,
      TotalCost: normalize(b.totalCost) ? Number(b.totalCost) : null,
      AmountPaid: normalize(b.amountPaid) ? Number(b.amountPaid) : null,
      SupplierId: b.supplierId ?? null,
      SupplierType: normalize(b.supplierType) || null,
      DollarConversionRate: normalize(b.dollarConversionRate) ? Number(b.dollarConversionRate) : null,
      OrderPlacementDate: normalize(b.orderPlacementDate) || null,
      EstimatedArrivalDate: normalize(b.estimatedArrivalDate) || null,
      IsHistorical: b.isHistorical,
      Notes: b.notes ?? null,
    })),
    Houses: draft.houses.map((h) => ({
      Key: h.key,
      ExistingHouseId: h.existingHouseId ?? null,
      HouseName: normalize(h.houseName),
      Capacity: normalize(h.capacity) ? count(h.capacity) : null,
      Location: normalize(h.location) || null,
    })),
    Flocks: draft.flocks.map((f) => {
      const b = breakdown(f)
      const resolved = resolveStartDate(f, context.businessDate)
      return {
        BatchKey: f.batchKey,
        HouseKey: f.houseKey,
        Name: normalize(f.name),
        Breed: normalize(f.breed) || null,
        HasArrived: f.hasArrived,
        OriginallyPlaced: count(f.originallyPlaced),
        CurrentLiveBirds: count(f.currentLiveBirds),
        // Only one of these is sent: an exact date, or the age the server derives
        // one from and flags as estimated.
        StartDate: resolved.estimated ? null : `${resolved.date}T00:00:00`,
        CurrentAgeInWeeks: resolved.estimated ? count(f.currentAgeInWeeks) : null,
        HistoryKnown: f.historyKnown,
        HistoricalMortality: b.mortality,
        HistoricalSold: b.sold,
        HistoricalCulled: b.culled,
        HistoricalTransferred: b.transferred,
        OtherAdjustment: b.other,
        Notes: f.notes ?? null,
      }
    }),
  }
}
