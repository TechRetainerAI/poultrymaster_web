/** Local calendar date key YYYY-MM-DD (avoids UTC off-by-one in date filters). */
export function toLocalDateKey(dateStr: string | undefined | null): string {
  if (!dateStr) return ""
  const d = new Date(dateStr)
  if (Number.isNaN(d.getTime())) return ""
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, "0")
  const day = String(d.getDate()).padStart(2, "0")
  return `${y}-${m}-${day}`
}

/**
 * Turn a yyyy-mm-dd picker value into the timestamp to store.
 *
 * A date picker gives a bare day, which binds to midnight. That is right for a
 * back-dated entry — nobody knows what time last Tuesday's payment happened —
 * but wrong for something recorded just now: it buries a brand-new row beneath
 * everything else already recorded today, because every other module (customer
 * receipts, supplier payments) stamps a real clock time.
 *
 * So: today gets the actual time, any other day gets midnight.
 *
 * Both sides are compared as UTC date keys because the callers build their
 * initial picker value the same way, so this compares like with like.
 *
 * Returns null for an empty input, which callers pass through to mean "let the
 * server decide".
 */
export function entryTimestamp(dateKey: string | null | undefined, now: Date = new Date()): string | null {
  if (!dateKey) return null
  return dateKey === now.toISOString().slice(0, 10)
    ? now.toISOString()
    : `${dateKey}T00:00:00.000Z`
}
