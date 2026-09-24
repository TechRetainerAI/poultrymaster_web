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
}

export interface SetupContext {
  existingBatches: ExistingBatch[]
  existingHouses: ExistingHouse[]
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
    historyKnown: false,
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

    if (!normalize(b.breed)) err("batches", i, "breed", "Breed is required.")
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
    else standingByHouseKey.set(f.houseKey, (standingByHouseKey.get(f.houseKey) ?? 0) + count(f.currentLiveBirds))
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
  standingByHouseKey.forEach((standing, key) => {
    const house = houseByKey.get(key)
    if (!house) return
    const index = draft.houses.indexOf(house)

    let capacity: number | null = count(house.capacity) || null
    let occupied = 0
    let label = normalize(house.houseName)
    if (house.existingHouseId != null) {
      const existing = context.existingHouses.find((h) => h.houseId === house.existingHouseId)
      if (!existing) return
      capacity = existing.capacity && existing.capacity > 0 ? existing.capacity : null
      occupied = existing.occupied
      label = existing.houseName
    }
    if (capacity == null || capacity <= 0) return

    if (standing + occupied > capacity) {
      const occupiedNote = occupied > 0 ? ` and already holds ${occupied.toLocaleString()}` : ""
      warn("houses", index, "capacity",
        `${label} is recorded as holding ${capacity.toLocaleString()} birds${occupiedNote}, but you are placing ${standing.toLocaleString()} in it. The birds are real — check the capacity.`)
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
      SupplierId: b.supplierId ?? null,
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
