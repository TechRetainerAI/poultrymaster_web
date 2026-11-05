// "Add Multiple Batches": the pure part.
//
// A big farm buying several lots of birds at once should not have to open the
// Add Flock Batch form once per lot. This module generates the rows, checks
// them and builds the request body -- no UI, no server.
//
// The same rules live in PoultryFarmAPI/Business/FlockBatchBulkValidator.cs and
// that copy decides; this one lets the grid flag a row before Create. Messages
// are worded identically. Change one, change the other.

export const MAX_ROWS = 100
export const MAX_NAME_LENGTH = 100
export const MAX_CODE_LENGTH = 25

/** One grid row. Strings, because this is form state. */
export interface BulkBatchRow {
  id: string
  batchName: string
  batchCode: string
  breed: string
  startDate: string
  numberOfBirds: string
  costPerChick: string
  amountPaid: string
}

/** Applied to every row on submit: one purchase run, one supplier and account. */
export interface BulkBatchShared {
  supplierType: string
  supplierId: string
  poultryCashAccountId: string
  status: string
  notes: string
}

export type BulkBatchField =
  | "batchName" | "batchCode" | "breed" | "startDate" | "numberOfBirds" | "costPerChick" | "amountPaid" | "batches"

export interface BulkBatchRowError {
  index: number
  field: BulkBatchField
  message: string
}

let seq = 0
const nextId = () => `bulk-batch-${++seq}`

export const normalize = (raw: string | null | undefined): string => (raw ?? "").trim()

/** Per-farm comparison key: case-insensitive, whitespace collapsed (same as migration 329's index). */
export const duplicateKey = (raw: string | null | undefined): string =>
  normalize(raw).replace(/\s+/g, " ").toLowerCase()

export interface GenerateOptions {
  count: number
  namePrefix: string
  codePrefix: string
  startNumber: number
  breed: string
  startDate: string
  numberOfBirds: string
  costPerChick: string
  amountPaid: string
}

/** Codes are the prefix plus a 3-digit number: "B" + 6 = "B006". */
export const makeCode = (prefix: string, n: number): string => `${normalize(prefix)}${String(n).padStart(3, "0")}`

export function emptyRow(defaults: Partial<BulkBatchRow> = {}): BulkBatchRow {
  return {
    id: nextId(), batchName: "", batchCode: "", breed: "", startDate: "",
    numberOfBirds: "", costPerChick: "", amountPaid: "", ...defaults,
  }
}

export function generateRows(o: GenerateOptions): BulkBatchRow[] {
  const count = Math.max(0, Math.min(Math.floor(o.count || 0), MAX_ROWS))
  const start = Number.isFinite(o.startNumber) ? Math.floor(o.startNumber) : 1
  const namePrefix = normalize(o.namePrefix)
  const rows: BulkBatchRow[] = []
  for (let i = 0; i < count; i++) {
    const n = start + i
    rows.push(emptyRow({
      batchName: namePrefix ? `${namePrefix} ${n}` : String(n),
      batchCode: makeCode(o.codePrefix, n),
      breed: normalize(o.breed),
      startDate: o.startDate,
      numberOfBirds: normalize(o.numberOfBirds),
      costPerChick: normalize(o.costPerChick),
      amountPaid: normalize(o.amountPaid),
    }))
  }
  return rows
}

/**
 * The number after the highest existing code of the form <prefix><digits>, so
 * a new run carries on the farm's series ("B005" exists -> start at 6).
 */
export function nextStartNumber(codePrefix: string, existingCodes: (string | null | undefined)[]): number {
  const key = duplicateKey(codePrefix)
  let highest = 0
  for (const c of existingCodes) {
    const k = duplicateKey(c)
    if (!k.startsWith(key)) continue
    const m = /^(\d+)$/.exec(k.slice(key.length))
    if (m && Number.isSafeInteger(Number(m[1]))) highest = Math.max(highest, Number(m[1]))
  }
  return highest + 1
}

export function applyToAll(rows: BulkBatchRow[], patch: Partial<Omit<BulkBatchRow, "id">>): BulkBatchRow[] {
  return rows.map((r) => ({ ...r, ...patch }))
}

const num = (raw: string): number | undefined => {
  const t = normalize(raw)
  if (t === "") return 0
  const n = Number(t)
  return Number.isFinite(n) ? n : undefined
}

/** Total cost as the single form computes it: cost per chick x birds. */
export function rowTotal(r: BulkBatchRow): number {
  const birds = Math.max(0, Math.floor(num(r.numberOfBirds) ?? 0))
  return +((num(r.costPerChick) ?? 0) * birds).toFixed(2)
}

export function validateRows(rows: BulkBatchRow[], existingCodes: (string | null | undefined)[] = []): BulkBatchRowError[] {
  const errors: BulkBatchRowError[] = []
  const err = (index: number, field: BulkBatchField, message: string) => errors.push({ index, field, message })

  if (rows.length === 0) { err(-1, "batches", "Add at least one batch."); return errors }
  if (rows.length > MAX_ROWS) { err(-1, "batches", `A single request can create at most ${MAX_ROWS} batches.`); return errors }

  const existing = new Set(existingCodes.map(duplicateKey))
  const seen = new Set<string>()

  rows.forEach((r, i) => {
    const name = normalize(r.batchName)
    if (!name) err(i, "batchName", "Batch name is required.")
    else if (name.length > MAX_NAME_LENGTH) err(i, "batchName", `Batch name cannot be longer than ${MAX_NAME_LENGTH} characters.`)

    const code = normalize(r.batchCode)
    if (!code) err(i, "batchCode", "Batch code is required.")
    else if (code.length > MAX_CODE_LENGTH) err(i, "batchCode", `Batch code cannot be longer than ${MAX_CODE_LENGTH} characters.`)
    else {
      const key = duplicateKey(code)
      if (existing.has(key)) err(i, "batchCode", `A batch with code "${code}" already exists.`)
      else if (seen.has(key)) err(i, "batchCode", `"${code}" appears more than once in this list.`)
      else seen.add(key)
    }

    const birds = num(r.numberOfBirds)
    if (birds === undefined || !Number.isInteger(birds) || birds <= 0) err(i, "numberOfBirds", "Number of birds must be greater than 0.")
    if (!/^\d{4}-\d{2}-\d{2}$/.test(normalize(r.startDate))) err(i, "startDate", "Start date is required.")

    const cost = num(r.costPerChick)
    if (cost === undefined || cost < 0) err(i, "costPerChick", "Cost per chick cannot be negative.")
    const paid = num(r.amountPaid)
    if (paid === undefined || paid < 0) err(i, "amountPaid", "Amount paid cannot be negative.")
    else if (paid > 0 && paid > rowTotal(r)) err(i, "amountPaid", "Amount paid cannot be more than the total cost.")
  })
  return errors
}

export function errorsByRow(errors: BulkBatchRowError[]): Record<number, Partial<Record<BulkBatchField, string>>> {
  const out: Record<number, Partial<Record<BulkBatchField, string>>> = {}
  for (const e of errors) {
    if (e.index < 0) continue
    out[e.index] = { ...(out[e.index] ?? {}), [e.field]: out[e.index]?.[e.field] ?? e.message }
  }
  return out
}

export function summarize(rows: BulkBatchRow[]) {
  let birds = 0, cost = 0, paid = 0
  for (const r of rows) {
    birds += Math.max(0, Math.floor(num(r.numberOfBirds) ?? 0))
    cost += rowTotal(r)
    paid += Math.max(0, num(r.amountPaid) ?? 0)
  }
  return { count: rows.length, birds, totalCost: +cost.toFixed(2), amountPaid: +paid.toFixed(2), balance: +(cost - paid).toFixed(2) }
}

/** The request rows: every shared setting copied onto every row. */
export function toPayloadItems(rows: BulkBatchRow[], shared: BulkBatchShared) {
  return rows.map((r) => ({
    batchName: normalize(r.batchName),
    batchCode: normalize(r.batchCode),
    breed: normalize(r.breed),
    startDate: normalize(r.startDate),
    numberOfBirds: Math.floor(num(r.numberOfBirds) ?? 0),
    costPerChick: num(r.costPerChick) ?? 0,
    totalCost: rowTotal(r),
    amountPaid: num(r.amountPaid) ?? 0,
    supplierType: shared.supplierType || "local",
    supplierId: shared.supplierId ? Number(shared.supplierId) : null,
    poultryCashAccountId: shared.poultryCashAccountId ? Number(shared.poultryCashAccountId) : null,
    status: shared.status || "active",
    notes: normalize(shared.notes) || null,
  }))
}
