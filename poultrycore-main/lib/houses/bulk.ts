// Bulk house/pen creation: the pure part.
//
// A farm with 50 pens should not have to open the Add House form 50 times. This
// module holds everything about that batch that can be decided without a server:
// generating the rows, checking them, and turning them into the request body.
//
// The same rules exist on the server in PoultryFarmAPI/Business/HouseBulkValidator.cs
// and that copy is the one that decides -- this one exists so the grid can flag a
// bad row before anyone clicks Create. The messages are worded identically, so a
// row rejected by the server reads the same as one caught here. Change one, change
// the other.
//
// Deliberately UI-free so the Houses page, the Farm Setup Wizard and the
// Batch-to-Flock allocation screen can each present it however they like.

/** Limits mirrored from HouseBulkValidator.cs -- see the reasoning there. */
export const MAX_ROWS = 200
export const MAX_NAME_LENGTH = 100
export const MAX_LOCATION_LENGTH = 200
export const MAX_CAPACITY = 2_000_000_000

/** One row of the editable preview grid. Everything is a string: this is form state. */
export interface BulkHouseRow {
  /** Stable React key. Not sent to the server. */
  id: string
  name: string
  capacity: string
  location: string
}

export interface GenerateOptions {
  count: number
  prefix: string
  startNumber: number
  capacity: string
  location: string
}

export type BulkHouseField = "houseName" | "capacity" | "location" | "houses"

export interface BulkHouseRowError {
  /** Index into the row list, or -1 for a problem with the batch as a whole. */
  index: number
  field: BulkHouseField
  message: string
}

let rowSeq = 0
const nextRowId = () => `bulk-house-${++rowSeq}`

export function emptyRow(capacity = "", location = ""): BulkHouseRow {
  return { id: nextRowId(), name: "", capacity, location }
}

/** What actually gets stored: the trimmed string, exactly as the grid shows it. */
export const normalizeName = (raw: string | null | undefined): string => (raw ?? "").trim()

export const normalizeLocation = (raw: string | null | undefined): string | null => {
  const trimmed = (raw ?? "").trim()
  return trimmed.length === 0 ? null : trimmed
}

/**
 * The key two names are compared on: case-insensitive, internal runs of
 * whitespace collapsed. "pen  1" and "Pen 1" are the same pen to a farmer, so the
 * tool treats them as a duplicate rather than quietly creating both.
 */
export const duplicateKey = (raw: string | null | undefined): string =>
  normalizeName(raw).replace(/\s+/g, " ").toLowerCase()

/**
 * Build `count` rows named `<prefix> <n>`, counting up from `startNumber`.
 *
 * Only a convenience: every value it produces stays editable in the grid, and
 * nothing is saved until the user submits.
 */
export function generateRows(options: GenerateOptions): BulkHouseRow[] {
  const count = Math.max(0, Math.min(Math.floor(options.count || 0), MAX_ROWS))
  const prefix = (options.prefix ?? "").trim()
  const start = Number.isFinite(options.startNumber) ? Math.floor(options.startNumber) : 1
  const capacity = (options.capacity ?? "").trim()
  const location = (options.location ?? "").trim()

  const rows: BulkHouseRow[] = []
  for (let i = 0; i < count; i++) {
    const n = start + i
    rows.push({
      id: nextRowId(),
      // A blank prefix gives plain numbers rather than a leading space.
      name: prefix ? `${prefix} ${n}` : String(n),
      capacity,
      location,
    })
  }
  return rows
}

/** "Apply capacity to all" / "Apply location to all". Returns new rows. */
export function applyToAll(rows: BulkHouseRow[], patch: Partial<Pick<BulkHouseRow, "capacity" | "location">>): BulkHouseRow[] {
  return rows.map((r) => ({ ...r, ...patch }))
}

/**
 * Capacity as the server will see it: null when blank, otherwise the number.
 * Returns undefined when the text is not a usable whole number -- validateRows
 * reports that as a row error.
 */
export function parseCapacity(raw: string | null | undefined): number | null | undefined {
  const trimmed = (raw ?? "").trim()
  if (trimmed.length === 0) return null
  if (!/^-?\d+$/.test(trimmed)) return undefined
  const n = Number(trimmed)
  return Number.isSafeInteger(n) ? n : undefined
}

/**
 * Every problem with the batch, one entry per (row, field). An empty list means
 * the batch can be submitted.
 *
 * `existingNames` are the houses already on this farm. Duplicates -- within the
 * batch or against an existing house -- are errors, not silent renames: the user
 * corrects the row and resubmits.
 */
export function validateRows(rows: BulkHouseRow[], existingNames: (string | null | undefined)[] = []): BulkHouseRowError[] {
  const errors: BulkHouseRowError[] = []

  if (rows.length === 0) {
    return [{ index: -1, field: "houses", message: "Add at least one house before creating." }]
  }
  if (rows.length > MAX_ROWS) {
    return [{
      index: -1,
      field: "houses",
      message: `A single batch can create at most ${MAX_ROWS} houses. Split this into smaller batches.`,
    }]
  }

  const existing = new Set(existingNames.map(duplicateKey).filter((k) => k.length > 0))

  // Count first, then report: both "Pen 1" rows get flagged, not just the second
  // one, so the user can see the pair and decide which to fix.
  const counts = new Map<string, number>()
  for (const row of rows) {
    const key = duplicateKey(row.name)
    if (!key) continue
    counts.set(key, (counts.get(key) ?? 0) + 1)
  }

  rows.forEach((row, index) => {
    const name = normalizeName(row.name)
    if (name.length === 0) {
      errors.push({ index, field: "houseName", message: "House name is required." })
    } else if (name.length > MAX_NAME_LENGTH) {
      errors.push({ index, field: "houseName", message: `House name cannot be longer than ${MAX_NAME_LENGTH} characters.` })
    } else {
      const key = duplicateKey(name)
      if ((counts.get(key) ?? 0) > 1) {
        errors.push({ index, field: "houseName", message: `"${name}" appears more than once in this batch.` })
      } else if (existing.has(key)) {
        errors.push({ index, field: "houseName", message: `A house named "${name}" already exists on this farm.` })
      }
    }

    const capacity = parseCapacity(row.capacity)
    if (capacity === undefined) {
      errors.push({ index, field: "capacity", message: "Capacity must be a whole number." })
    } else if (capacity !== null && capacity < 0) {
      errors.push({ index, field: "capacity", message: "Capacity cannot be negative." })
    } else if (capacity !== null && capacity > MAX_CAPACITY) {
      errors.push({ index, field: "capacity", message: "Capacity is too large." })
    }

    if ((row.location ?? "").trim().length > MAX_LOCATION_LENGTH) {
      errors.push({ index, field: "location", message: `Location cannot be longer than ${MAX_LOCATION_LENGTH} characters.` })
    }
  })

  return errors
}

/** Errors keyed by row index then field, so a cell can render its own message. */
export function errorsByRow(errors: BulkHouseRowError[]): Record<number, Partial<Record<BulkHouseField, string>>> {
  const map: Record<number, Partial<Record<BulkHouseField, string>>> = {}
  for (const e of errors) {
    if (e.index < 0) continue
    map[e.index] = { ...(map[e.index] ?? {}), [e.field]: e.message }
  }
  return map
}

export interface BulkHouseSummary {
  count: number
  /** Birds across every row that has a capacity. */
  totalCapacity: number
  /** Rows with no capacity set -- so the total is not read as the whole picture. */
  withoutCapacity: number
}

export function summarize(rows: BulkHouseRow[]): BulkHouseSummary {
  let totalCapacity = 0
  let withoutCapacity = 0
  for (const row of rows) {
    const capacity = parseCapacity(row.capacity)
    if (capacity === null || capacity === undefined) withoutCapacity++
    else totalCapacity += capacity
  }
  return { count: rows.length, totalCapacity, withoutCapacity }
}

/** One row as the API takes it. The company is on the envelope, never on a row. */
export interface BulkHousePayloadItem {
  houseName: string
  capacity: number | null
  location: string | null
}

/**
 * Rows as they will be sent. Call only once validateRows comes back empty --
 * a row with unparseable capacity is sent as null here rather than guessed at.
 */
export function toPayloadItems(rows: BulkHouseRow[]): BulkHousePayloadItem[] {
  return rows.map((row) => {
    const capacity = parseCapacity(row.capacity)
    return {
      houseName: normalizeName(row.name),
      capacity: capacity === undefined ? null : capacity,
      location: normalizeLocation(row.location),
    }
  })
}
