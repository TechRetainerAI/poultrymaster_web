// Pure helpers for the Egg Sorting Workspace: grouping the pick rows the API
// returns into production days, the live balance of a sorting being entered,
// and egg <-> crate display. No I/O here, so it is easy to reason about.

import type { EggSortingLine, EggSortingPick, SortingLineType } from "@/lib/api/egg-sorting"
import { EGGS_PER_CRATE } from "@/lib/production/production-record-calc"

export type PickStatus = "NotStarted" | "Partial" | "Complete"

export interface ProductionDay {
  productionRecordId: number
  flockId: number
  flockName: string
  batchName: string | null
  houseName: string | null
  productionDate: string
  gross: number
  collectionLoss: number
  saleable: number
  sorted: number
  left: number
  status: PickStatus
  picks: EggSortingPick[]
  /** Eggs of this day already sold or used straight from Unsorted. 0 unless capToSortable set it. */
  soldUnsorted?: number
}

export const LOSS_TYPES: { key: Exclude<SortingLineType, "SizedOutput">; label: string }[] = [
  { key: "Reject", label: "Reject" },
  { key: "Breakage", label: "Breakage" },
  { key: "OtherLoss", label: "Other loss" },
]

export function lineTypeLabel(t: SortingLineType | string, sizeName?: string | null): string {
  if (t === "SizedOutput") return sizeName ?? "Size"
  return LOSS_TYPES.find((l) => l.key === t)?.label ?? t
}

export function statusOf(sorted: number, left: number): PickStatus {
  if (left <= 0 && sorted > 0) return "Complete"
  if (sorted > 0) return "Partial"
  return left <= 0 ? "Complete" : "NotStarted"
}

export const STATUS_LABEL: Record<PickStatus, string> = {
  NotStarted: "Not started",
  Partial: "Partial",
  Complete: "Complete",
}

/** Pick rows -> one entry per production record, newest first. */
export function groupProductionDays(rows: EggSortingPick[]): ProductionDay[] {
  const byRecord = new Map<number, ProductionDay>()
  for (const r of rows) {
    let d = byRecord.get(r.productionRecordId)
    if (!d) {
      d = {
        productionRecordId: r.productionRecordId,
        flockId: r.flockId,
        flockName: r.flockName ?? `Flock ${r.flockId}`,
        batchName: r.batchName,
        houseName: r.houseName,
        productionDate: r.productionDate.slice(0, 10),
        gross: r.recordGross,
        collectionLoss: r.recordCollectionLoss,
        saleable: r.recordSaleable,
        sorted: r.recordSorted,
        left: r.recordLeft,
        status: statusOf(r.recordSorted, r.recordLeft),
        picks: [],
      }
      byRecord.set(r.productionRecordId, d)
    }
    d.picks.push(r)
  }
  for (const d of byRecord.values()) d.picks.sort((a, b) => a.pickNumber - b.pickNumber)
  return [...byRecord.values()].sort((a, b) =>
    a.productionDate === b.productionDate ? a.flockName.localeCompare(b.flockName) : b.productionDate.localeCompare(a.productionDate))
}

/**
 * What each open production record can REALLY still be sorted into, once the
 * eggs sold or used straight from Unsorted are taken off.
 *
 * Production left (saleable - sorted) only says what was never sorted; an
 * unsorted sale also takes eggs off the shelf, and posting refuses to sort
 * more than Unsorted holds. The ledger does not say which day a sold egg came
 * from, so the shortfall is taken from the OLDEST days first (date, then
 * record) -- the eggs that go first, and the same order Sort All uses.
 *
 * `openDays` must hold every record with eggs left up to the business date
 * (from the summary's oldest-left date), or the shortfall lands on the wrong
 * days. Returns recordId -> sortable eggs, for open records only.
 */
export function sortableByRecord(openDays: ProductionDay[], unsortedOnHand: number): Map<number, number> {
  const open = openDays.filter((d) => d.left > 0)
    .sort((a, b) => a.productionDate.localeCompare(b.productionDate) || a.productionRecordId - b.productionRecordId)
  const totalLeft = open.reduce((s, d) => s + d.left, 0)
  let gone = Math.max(0, totalLeft - Math.max(0, Math.trunc(unsortedOnHand)))
  const out = new Map<number, number>()
  for (const d of open) {
    const take = Math.min(gone, d.left)
    gone -= take
    out.set(d.productionRecordId, d.left - take)
  }
  return out
}

/**
 * The day as it can actually be sorted: `left` and each pick's `available`
 * cut down to `sortable` (earliest pick first), the cut kept in soldUnsorted.
 * Undefined (a record that is not open) or enough eggs: the day unchanged.
 */
export function capToSortable(day: ProductionDay, sortable: number | undefined): ProductionDay {
  if (sortable == null || sortable >= day.left) return day
  let sold = day.left - Math.max(0, sortable)
  const picks = day.picks.map((p) => {
    const take = Math.min(sold, Math.max(0, p.available))
    sold -= take
    return take ? { ...p, available: p.available - take } : p
  })
  const left = Math.max(0, sortable)
  return { ...day, picks, left, soldUnsorted: day.left - left, status: statusOf(day.sorted, left) }
}

/** What a pick can still give, shown on its row. */
export function pickRemaining(p: EggSortingPick): number {
  return Math.max(0, p.available)
}

export function pickStatus(p: EggSortingPick): PickStatus {
  return statusOf(p.pickSorted, pickRemaining(p))
}

/** Whole, positive eggs, or null. */
export function parseEggs(text: string): number | null {
  const t = text.trim()
  if (t === "") return null
  const n = Number(t)
  return Number.isInteger(n) && n > 0 ? n : null
}

export interface SortingBalance {
  available: number
  sized: number
  loss: number
  /** sized + loss: what this sorting takes out of Unsorted. */
  input: number
  /** available - input: still unsorted after posting (negative = too many). */
  remainingAfter: number
  invalidLines: number
}

export function sortingBalance(available: number, lines: { lineType: SortingLineType; text: string }[]): SortingBalance {
  let sized = 0, loss = 0, invalid = 0
  for (const l of lines) {
    if (l.text.trim() === "") continue
    const n = parseEggs(l.text)
    if (n == null) { invalid++; continue }
    if (l.lineType === "SizedOutput") sized += n
    else loss += n
  }
  const input = sized + loss
  return { available, sized, loss, input, remainingAfter: available - input, invalidLines: invalid }
}

/** The reason Post is disabled, or null when it can post. */
export function sortingBlocker(b: SortingBalance): string | null {
  if (b.invalidLines > 0) return "Quantities must be whole numbers of eggs."
  if (b.input <= 0) return "Enter how the eggs graded."
  if (b.remainingAfter < 0) return `That is ${fmtCount(-b.remainingAfter)} more than are left to sort.`
  return null
}

export function toApiLines(lines: { lineType: SortingLineType; eggSizeId: number | null; text: string; notes?: string }[]): EggSortingLine[] {
  return lines
    .map((l) => ({ ...l, qty: parseEggs(l.text) }))
    .filter((l) => l.qty != null)
    .map((l) => ({ lineType: l.lineType, eggSizeId: l.lineType === "SizedOutput" ? l.eggSizeId : null, quantity: l.qty as number, notes: l.notes?.trim() || null }))
}

export const fmtCount = (n: number) => Math.round(n).toLocaleString()

/** "28,870 eggs" -> "962 crates + 10" (one base unit; crates are display only). */
export function cratesText(eggs: number, perCrate = EGGS_PER_CRATE): string {
  const n = Math.max(0, Math.round(eggs))
  const crates = Math.floor(n / perCrate)
  const loose = n % perCrate
  if (crates === 0) return `${loose} egg${loose === 1 ? "" : "s"}`
  return loose ? `${crates.toLocaleString()} cr + ${loose}` : `${crates.toLocaleString()} cr`
}

export function pct(part: number, whole: number): string {
  if (!whole) return "—"
  return `${((part / whole) * 100).toFixed(1)}%`
}

/** "1st Pick (9:00 AM)" style label for a pick number, from the farm's labels. */
export function pickLabel(n: number, labels: { first: string; second: string; third: string; fourth: string; fifth: string; sixth: string }): string {
  return [labels.first, labels.second, labels.third, labels.fourth, labels.fifth, labels.sixth][n - 1] ?? `Pick ${n}`
}

export const TXN_LABEL: Record<string, string> = {
  Production: "Production",
  Sale: "Sale",
  "Sorting Out": "Sorted (out of Unsorted)",
  "Sorting In": "Sorted (into size)",
  "Sorting Reversal": "Sorting reversed",
  InternalUse: "Internal use",
  Adjustment: "Adjustment",
  "Egg Loss": "Breakage / loss",
  Increase: "Adjustment (+)",
  Decrease: "Adjustment (−)",
  "Opening Adjustment": "Opening balance",
  "Driver Load Out": "Driver load-out",
  "Driver Return In": "Driver return",
  Restock: "Restock",
}
