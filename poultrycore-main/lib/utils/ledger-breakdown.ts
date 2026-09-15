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
