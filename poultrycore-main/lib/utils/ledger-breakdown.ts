/**
 * "Breakdown" for a stock ledger — the in/out cards on /egg-tracker and
 * /feed-tracker, and the same shape the Cash Flow page gives money with
 * "Money In by Source" / "Money Out by Use".
 *
 * Structural on purpose: every tracker's ledger row carries a type and an in
 * and an out, and that is all a breakdown needs. Written once here rather than
 * per tracker, so the cards cannot end up counting or rounding differently on
 * one page than another.
 */

import { assignPercentages, type FlowBucket } from "@/lib/cash/cash-flow"

/** The only fields a breakdown touches. Any ledger row fits. */
export interface LedgerRowLike {
  type: string
  in: number
  out: number
}

/**
 * Bucket a ledger by what moved the stock, biggest first.
 *
 * Each card decomposes exactly the "Total in" / "Total out" tile above it: same
 * rows, same arithmetic, only grouped. Percentages go through the cash module's
 * largest-remainder apportionment so the column sums to 100 rather than 99.9.
 *
 * A row can appear on both sides over its lifetime but never twice on one side:
 * each row carries either an `in` or an `out`, never both.
 *
 * `labels` renames the types that do not read as English on their own
 * ("InternalUse", "Purchase IN"). Anything unlisted is shown as it stands,
 * rather than dropped — a posting module inventing a new type still appears.
 */
export function groupLedgerByType<T extends LedgerRowLike>(
  rows: T[],
  direction: "in" | "out",
  labels: Record<string, string> = {},
): FlowBucket[] {
  return groupLedgerBy(rows, direction, (row) => row.type, labels)
}

/**
 * The same breakdown, grouped by whatever the caller says.
 *
 * The Feed tracker asks for both: by movement type ("Purchase", "Adjustment")
 * to see HOW the feed moved, and by item ("Layer mash", "Maize") to see WHICH
 * feed moved. Same arithmetic, same apportionment, different key.
 *
 * `keyOf` returning an empty value falls back to "Other", so a row is never
 * dropped for want of a label.
 */
export function groupLedgerBy<T extends LedgerRowLike>(
  rows: T[],
  direction: "in" | "out",
  keyOf: (row: T) => string | null | undefined,
  labels: Record<string, string> = {},
): FlowBucket[] {
  const acc = new Map<string, { label: string; amount: number; count: number }>()
  let total = 0

  for (const row of rows) {
    const qty = direction === "in" ? row.in : row.out
    if (!(qty > 0)) continue
    const key = (keyOf(row) || "").trim() || "Other"
    const bucket = acc.get(key)
    if (bucket) {
      bucket.amount += qty
      bucket.count += 1
    } else {
      acc.set(key, { label: labels[key] ?? key, amount: qty, count: 1 })
    }
    total += qty
  }

  const buckets: FlowBucket[] = [...acc.entries()]
    .map(([key, b]) => ({ key, label: b.label, amount: b.amount, count: b.count, percent: 0 }))
    .sort((a, b) => b.amount - a.amount || a.label.localeCompare(b.label))

  return assignPercentages(buckets, total)
}

/**
 * A breakdown of what is LEFT per key, rather than of one direction's flow.
 *
 * `groupLedgerBy(rows, "in", ...)` and its "out" twin each decompose a flow;
 * this decomposes the closing position the tracker's hero card states: per key,
 * in MINUS out over the whole ledger. Same rows, same keys, different question
 * — "what do we still hold of each item", not "how much of it moved".
 *
 * Only keys with something still on hand come back:
 *   * a key whose ins and outs cancel has nothing left to list, and
 *   * a key gone NEGATIVE is a counting error (more fed out than ever came in),
 *     which the tracker already flags on its own balance. A negative slice of a
 *     "what is left" card has no honest bar to draw and no honest share of the
 *     total, and including it would break assignPercentages' contract that the
 *     column sums to exactly 100.
 * So the returned total is the sum of what IS there, which is the figure the
 * card should print.
 *
 * EPS, not `!== 0`: quantities are decimal kg accumulated in floating point, so
 * an item that has been fully drawn down lands on 1e-13 rather than on 0 and
 * would otherwise show as a phantom bucket rounding to "0.0".
 */
const EPS = 1e-6

export function groupLedgerByNet<T extends LedgerRowLike>(
  rows: T[],
  keyOf: (row: T) => string | null | undefined,
  labels: Record<string, string> = {},
): FlowBucket[] {
  const acc = new Map<string, { label: string; amount: number; count: number }>()

  for (const row of rows) {
    const delta = (row.in || 0) - (row.out || 0)
    if (delta === 0) continue
    const key = (keyOf(row) || "").trim() || "Other"
    const bucket = acc.get(key)
    if (bucket) {
      bucket.amount += delta
      bucket.count += 1
    } else {
      acc.set(key, { label: labels[key] ?? key, amount: delta, count: 1 })
    }
  }

  let total = 0
  const buckets: FlowBucket[] = [...acc.entries()]
    .filter(([, b]) => b.amount > EPS)
    .map(([key, b]) => {
      total += b.amount
      return { key, label: b.label, amount: b.amount, count: b.count, percent: 0 }
    })
    .sort((a, b) => b.amount - a.amount || a.label.localeCompare(b.label))

  return assignPercentages(buckets, total)
}

/** Egg ledger types that need renaming for a bucket label. */
export const EGG_MOVE_LABELS: Record<string, string> = {
  InternalUse: "Internal use",
  "Driver Load Out": "Driver load-out",
  "Driver Return In": "Driver return",
  "Delivery Load": "Delivery load-out",
  "Delivery Return": "Delivery return",
}

/**
 * Feed ledger types. "Purchase IN" and "Usage OUT" carry their direction in the
 * name, which reads twice over in a card already titled "Feed in by source".
 */
export const FEED_MOVE_LABELS: Record<string, string> = {
  "Purchase IN": "Purchase",
  "Usage OUT": "Used in production",
}
