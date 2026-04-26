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
