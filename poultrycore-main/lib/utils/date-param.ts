// ?date=yyyy-MM-dd on a list page: open it filtered to that one day. Used by
// Daily Closing's "Review" links so they land on the day being closed, not on
// the page's default (current) view.
//
// Read from the query string on mount rather than via useSearchParams, which
// would force a Suspense boundary onto every list page that adopts it.

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/

/** The validated "yyyy-MM-dd" in `name`, or null. Pass window.location.search. */
export function parseDateParam(search: string | null | undefined, name = "date"): string | null {
  if (!search) return null
  const v = new URLSearchParams(search).get(name)?.trim() ?? ""
  if (!DATE_RE.test(v)) return null
  const [, m, d] = v.split("-").map(Number)
  if (m < 1 || m > 12 || d < 1 || d > 31) return null
  return v
}
