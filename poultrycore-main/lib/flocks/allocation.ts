// Dividing a batch of birds across houses: the pure part.
//
// A farmer who buys 12,000 chicks and runs six pens should not have to open the
// Add Flock form six times. This module holds everything about that division
// that can be decided without a server: naming the flocks, spreading the birds,
// checking the result, and turning it into the request body.
//
// The rules exist on the server too, in PoultryFarmAPI/Business/FlockAllocationValidator.cs,
// and that copy is the one that decides. This one exists so the grid can flag a
// bad row before anyone clicks Create, and so the live totals at the bottom of
// the tool are honest as you type. Messages are worded identically. Change one,
// change the other.
//
// Deliberately UI-free so the Flock Groups page, the Flock Purchases page and
// (later) the Farm Setup Wizard can each present it however they like.

/** Limits mirrored from FlockAllocationValidator.cs -- see the reasoning there. */
export const MAX_ROWS = 200
export const MAX_NAME_LENGTH = 100

/** A house as the allocation tool sees it, straight from the allocation-context endpoint. */
export interface HouseOccupancy {
  houseId: number
  houseName: string
  capacity?: number | null
  location?: string | null
  /** Birds in active flocks currently placed in this house. */
  occupied: number
  /** capacity − occupied, or null when the house has no capacity recorded. */
  availableCapacity?: number | null
  activeFlocks: number
}

/** One row of the allocation grid. `quantity` is a string: this is form state. */
export interface AllocationRow {
  /** Stable React key. Not sent to the server. */
  id: string
  houseId: number
  name: string
  quantity: string
}

export type AllocationField = "name" | "quantity" | "houseId" | "allocations"

export interface AllocationRowError {
  /** Index into the row list, or -1 for a problem with the allocation as a whole. */
  index: number
  field: AllocationField
  message: string
}

let rowSeq = 0
const nextRowId = () => `alloc-${++rowSeq}`

export const normalizeName = (raw: string | null | undefined): string => (raw ?? "").trim()

/**
 * The key two flock names are compared on: case-insensitive, internal runs of
 * whitespace collapsed.
 */
export const duplicateKey = (raw: string | null | undefined): string =>
  normalizeName(raw).replace(/\s+/g, " ").toLowerCase()

/**
 * Birds a house can still take. Null means "no capacity recorded", which the
 * existing capacity rule treats as unconstrained rather than as zero — see the
 * `cap > 0` guard in app/flocks/page.tsx.
 */
export function availableCapacity(house: Pick<HouseOccupancy, "capacity" | "occupied">): number | null {
  const cap = house.capacity ?? 0
  if (cap <= 0) return null
  return Math.max(0, cap - (house.occupied ?? 0))
}

/**
 * The default name for a flock: "<batch code> - <house name>", e.g. "B3 - Pen 1".
 *
 * Follows what the batch and the pen are already called rather than inventing a
 * scheme, so a farmer reading a flock list can see where the birds came from and
 * where they went. Always editable before creation.
 */
export function defaultFlockName(batchCode: string, houseName: string): string {
  const code = (batchCode ?? "").trim()
  const house = (houseName ?? "").trim()
  if (!code) return house
  if (!house) return code
  return `${code} - ${house}`
}

/** One grid row per selected house, named by convention and starting empty. */
export function buildRows(batchCode: string, houses: HouseOccupancy[]): AllocationRow[] {
  return houses.map((h) => ({
    id: nextRowId(),
    houseId: h.houseId,
    name: defaultFlockName(batchCode, h.houseName),
    quantity: "",
  }))
}

export interface DistributionResult {
  rows: AllocationRow[]
  /** Birds every row gets at minimum. */
  base: number
  /**
   * How many rows take one extra bird. 10,003 across 5 pens is 2,000 each with
   * 3 left over, so the first three pens take 2,001 — the remainder goes
   * somewhere visible rather than being dropped.
   */
  remainder: number
}

/**
 * Spread `available` birds evenly across the rows, giving the remainder to the
 * first rows in grid order.
 *
 * Deterministic on purpose: the same input always produces the same split, and
 * the tool can say exactly which pens take the extra bird. Nothing is lost —
 * base * rows + remainder === available.
 */
export function distributeEqually(available: number, rows: AllocationRow[]): DistributionResult {
  const count = rows.length
  if (count === 0 || available <= 0) {
    return { rows: rows.map((r) => ({ ...r, quantity: "" })), base: 0, remainder: 0 }
  }

  const base = Math.floor(available / count)
  const remainder = available - base * count

  return {
    rows: rows.map((r, i) => ({ ...r, quantity: String(base + (i < remainder ? 1 : 0)) })),
    base,
    remainder,
  }
}

/**
 * True when every row's house has a capacity recorded. "Fill by capacity" is
 * meaningless otherwise, so the tool disables it rather than guessing at a
 * number for the houses that have none.
 */
export function canFillByCapacity(rows: AllocationRow[], houses: HouseOccupancy[]): boolean {
  if (rows.length === 0) return false
  const byId = new Map(houses.map((h) => [h.houseId, h]))
  return rows.every((r) => {
    const house = byId.get(r.houseId)
    return house != null && availableCapacity(house) != null
  })
}

/**
 * Propose filling each house to its remaining capacity, in grid order, until the
 * birds run out. Proposes only — nothing is saved, and every number stays
 * editable.
 */
export function fillByCapacity(available: number, rows: AllocationRow[], houses: HouseOccupancy[]): AllocationRow[] {
  const byId = new Map(houses.map((h) => [h.houseId, h]))
  let remaining = Math.max(0, available)

  return rows.map((r) => {
    const house = byId.get(r.houseId)
    const room = house ? availableCapacity(house) : null
    if (room == null) return { ...r, quantity: "" }
    const take = Math.min(room, remaining)
    remaining -= take
    return { ...r, quantity: take > 0 ? String(take) : "" }
  })
}

/** Quantity as the server will see it, or undefined when the text is unusable. */
export function parseQuantity(raw: string | null | undefined): number | undefined {
  const trimmed = (raw ?? "").trim()
  if (trimmed.length === 0) return 0
  if (!/^-?\d+$/.test(trimmed)) return undefined
  const n = Number(trimmed)
  return Number.isSafeInteger(n) ? n : undefined
}

export interface AllocationContext {
  /** Batch birds not yet allocated: original − already allocated. */
  availableBirds: number
  houses: HouseOccupancy[]
  /** Flock names already on this farm. */
  existingNames: string[]
}

/**
 * Everything wrong with the allocation, one entry per (row, field). Empty means
 * it can be submitted.
 *
 * Capacity is checked on the AGGREGATE per house: two rows of 1,500 into one
 * 2,000-bird pen must fail even though neither exceeds the capacity alone.
 */
export function validateRows(rows: AllocationRow[], context: AllocationContext): AllocationRowError[] {
  const errors: AllocationRowError[] = []

  if (rows.length === 0) {
    return [{ index: -1, field: "allocations", message: "Add at least one house before creating flocks." }]
  }
  if (rows.length > MAX_ROWS) {
    return [{
      index: -1,
      field: "allocations",
      message: `A single allocation can create at most ${MAX_ROWS} flocks. Split this into smaller allocations.`,
    }]
  }

  const byId = new Map(context.houses.map((h) => [h.houseId, h]))
  const existing = new Set(context.existingNames.map(duplicateKey).filter((k) => k.length > 0))

  const nameCounts = new Map<string, number>()
  for (const row of rows) {
    const key = duplicateKey(row.name)
    if (!key) continue
    nameCounts.set(key, (nameCounts.get(key) ?? 0) + 1)
  }

  const requestedPerHouse = new Map<number, number>()
  for (const row of rows) {
    const q = parseQuantity(row.quantity)
    if (q === undefined || q <= 0 || row.houseId <= 0) continue
    requestedPerHouse.set(row.houseId, (requestedPerHouse.get(row.houseId) ?? 0) + q)
  }

  rows.forEach((row, index) => {
    const name = normalizeName(row.name)
    if (name.length === 0) {
      errors.push({ index, field: "name", message: "Flock name is required." })
    } else if (name.length > MAX_NAME_LENGTH) {
      errors.push({ index, field: "name", message: `Flock name cannot be longer than ${MAX_NAME_LENGTH} characters.` })
    } else {
      const key = duplicateKey(name)
      if ((nameCounts.get(key) ?? 0) > 1) {
        errors.push({ index, field: "name", message: `"${name}" appears more than once in this allocation.` })
      } else if (existing.has(key)) {
        errors.push({ index, field: "name", message: `A flock named "${name}" already exists on this farm.` })
      }
    }

    const quantity = parseQuantity(row.quantity)
    if (quantity === undefined) {
      errors.push({ index, field: "quantity", message: "Enter how many birds go into this house — a whole number." })
    } else if (quantity <= 0) {
      errors.push({ index, field: "quantity", message: "Enter how many birds go into this house — more than zero." })
    }

    const house = byId.get(row.houseId)
    if (row.houseId <= 0) {
      errors.push({ index, field: "houseId", message: "Choose a house/pen for this flock." })
    } else if (!house) {
      errors.push({ index, field: "houseId", message: "That house/pen is not available on this farm." })
    } else if (quantity !== undefined && quantity > 0) {
      const room = availableCapacity(house)
      const requested = requestedPerHouse.get(row.houseId) ?? 0
      if (room != null && requested > room) {
        const occupiedNote = house.occupied > 0 ? ` and already holds ${house.occupied.toLocaleString()}` : ""
        errors.push({
          index,
          field: "quantity",
          message: `${house.houseName} holds ${(house.capacity ?? 0).toLocaleString()} birds${occupiedNote}. This allocation puts ${requested.toLocaleString()} in it — ${room.toLocaleString()} will fit.`,
        })
      }
    }
  })

  const requested = totalRequested(rows)
  if (requested > context.availableBirds) {
    errors.push({
      index: -1,
      field: "allocations",
      message: `This allocation places ${requested.toLocaleString()} birds but the batch only has ${context.availableBirds.toLocaleString()} left to allocate.`,
    })
  }

  return errors
}

/** Errors keyed by row index then field, so a cell can render its own message. */
export function errorsByRow(errors: AllocationRowError[]): Record<number, Partial<Record<AllocationField, string>>> {
  const map: Record<number, Partial<Record<AllocationField, string>>> = {}
  for (const e of errors) {
    if (e.index < 0) continue
    map[e.index] = { ...(map[e.index] ?? {}), [e.field]: e.message }
  }
  return map
}

/** Birds this allocation places. Unusable text counts as zero, not as a guess. */
export function totalRequested(rows: AllocationRow[]): number {
  return rows.reduce((sum, r) => {
    const q = parseQuantity(r.quantity)
    return sum + (q === undefined || q < 0 ? 0 : q)
  }, 0)
}

/** Just enough of a flock to count it against its batch. */
export interface BatchFlockQuantity {
  batchId?: number | null
  quantity?: number | null
}

/** Just enough of an opening position to count it against its batch. */
export interface BatchOpeningReduction {
  batchId?: number | null
  historicalReduction?: number | null
}

/**
 * Birds each batch has given out, keyed by batch id.
 *
 * TWO TERMS, BECAUSE THEY ARE MEASURED DIFFERENTLY. A batch's `numberOfBirds` is
 * what was PLACED. Since migration 319 a flock created by Initial Farm Setup
 * carries its opening LIVE birds -- 919 of the 1,000 placed -- so summing
 * quantities alone leaves the batch looking like it still has 81 to give, and
 * offers to place birds that died months ago. The opening historical reduction is
 * added back so both sides of the comparison mean the same thing.
 *
 * The server computes this identically in spflock_getconsumedforbatch (migration
 * 325); this copy exists so a page can show the figure without a round trip. A
 * farm that never ran Initial Farm Setup has no opening positions, and the second
 * term is then simply zero.
 */
export function consumedByBatch(
  flocks: readonly BatchFlockQuantity[],
  openingPositions: readonly BatchOpeningReduction[] = [],
): Map<number, number> {
  const map = new Map<number, number>()
  const add = (batchId: number | null | undefined, n: number | null | undefined) => {
    if (batchId == null) return
    const value = Number(n)
    if (!Number.isFinite(value) || value <= 0) return
    map.set(batchId, (map.get(batchId) ?? 0) + value)
  }
  for (const f of flocks) add(f.batchId, f.quantity)
  for (const p of openingPositions) add(p.batchId, p.historicalReduction)
  return map
}

/** Birds a batch has left to give. Never negative. */
export function unallocatedForBatch(
  batchBirds: number | null | undefined,
  consumed: number | null | undefined,
): number {
  return Math.max(0, (Number(batchBirds) || 0) - (Number(consumed) || 0))
}

export interface AllocationTotals {
  /** Birds the batch was bought with. */
  batchBirds: number
  /** Birds already in flocks from earlier allocations. */
  previouslyAllocated: number
  /** Birds this allocation places. */
  thisAllocation: number
  /** Birds still unallocated once this is saved. Never negative. */
  remaining: number
  /** True when this allocation asks for more than the batch has left. */
  overAllocated: boolean
  flockCount: number
}

/**
 * The live totals at the bottom of the tool. Partial allocation is normal, not
 * an error: a farmer may place 8,000 of 12,000 today and the rest next week.
 */
export function summarize(rows: AllocationRow[], batchBirds: number, previouslyAllocated: number): AllocationTotals {
  const thisAllocation = totalRequested(rows)
  const available = Math.max(0, batchBirds - previouslyAllocated)
  return {
    batchBirds,
    previouslyAllocated,
    thisAllocation,
    remaining: Math.max(0, available - thisAllocation),
    overAllocated: thisAllocation > available,
    flockCount: rows.length,
  }
}

/** One row as the API takes it. The batch and company live on the envelope. */
export interface AllocationPayloadItem {
  houseId: number
  name: string
  quantity: number
}

/** Rows as they will be sent. Call once validateRows comes back empty. */
export function toPayloadItems(rows: AllocationRow[]): AllocationPayloadItem[] {
  return rows.map((row) => ({
    houseId: row.houseId,
    name: normalizeName(row.name),
    quantity: parseQuantity(row.quantity) ?? 0,
  }))
}
