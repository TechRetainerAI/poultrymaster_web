/**
 * A stable colour per company, for telling several companies apart at a glance
 * in a list (the Business Office sidebar) rather than for encoding any meaning.
 * Type already has its own signal — the icon — and two poultry farms need to
 * look different from each other, so the colour identifies the company itself.
 *
 * Colours are handed out by position in creation order, NOT by hashing the id.
 * Hashing spreads evenly over many companies but collides constantly over few:
 * with a palette of 8 and only 6 companies, two of them share a colour about
 * 92% of the time, which defeats the point. Going in creation order guarantees
 * the first 8 are all different, and keeps a company's colour fixed as new ones
 * are added (a new company takes the next colour; deleting one does shift the
 * companies created after it).
 *
 * Tailwind scans for whole class strings, so every class here is written out in
 * full — building them as `bg-${hue}-500` would leave them out of the stylesheet.
 */

export interface CompanyColor {
  /** Solid square behind the company's initial. */
  chip: string
  /** Faint wash across the row, plus the hover state that replaces the default. */
  row: string
}

/** Deliberately excludes orange — that's the Business Office's own accent and
 *  the "New company" row, so a company tinted orange would read as chrome. */
const PALETTE: CompanyColor[] = [
  { chip: "bg-emerald-500 text-emerald-950", row: "bg-emerald-500/10 hover:bg-emerald-500/20" },
  { chip: "bg-sky-500 text-sky-950",         row: "bg-sky-500/10 hover:bg-sky-500/20" },
  { chip: "bg-violet-500 text-violet-950",   row: "bg-violet-500/10 hover:bg-violet-500/20" },
  { chip: "bg-amber-500 text-amber-950",     row: "bg-amber-500/10 hover:bg-amber-500/20" },
  { chip: "bg-rose-500 text-rose-950",       row: "bg-rose-500/10 hover:bg-rose-500/20" },
  { chip: "bg-teal-500 text-teal-950",       row: "bg-teal-500/10 hover:bg-teal-500/20" },
  { chip: "bg-indigo-500 text-indigo-950",   row: "bg-indigo-500/10 hover:bg-indigo-500/20" },
  { chip: "bg-fuchsia-500 text-fuchsia-950", row: "bg-fuchsia-500/10 hover:bg-fuchsia-500/20" },
]

/** Used when a row is rendered before its list has been mapped. */
export const FALLBACK_COMPANY_COLOR: CompanyColor = PALETTE[0]

/** Minimum shape needed to order companies; accepts the full `Company` too. */
type Colourable = { farmId: string; createdAt?: string | null }

/**
 * farmId → colour for a whole list. Ordering is by creation date (not by the
 * order the API happened to return, and not by name) so the assignment survives
 * a rename or a re-sorted list. Past `PALETTE.length` companies the colours
 * repeat, which is unavoidable — but they repeat in a fixed order rather than
 * at random.
 */
export function companyColorMap(companies: Colourable[]): Map<string, CompanyColor> {
  const ordered = [...companies].sort((a, b) => {
    const ta = Date.parse(a.createdAt ?? "") || 0
    const tb = Date.parse(b.createdAt ?? "") || 0
    if (ta !== tb) return ta - tb
    return a.farmId.localeCompare(b.farmId)
  })
  const map = new Map<string, CompanyColor>()
  ordered.forEach((c, i) => map.set(c.farmId, PALETTE[i % PALETTE.length]))
  return map
}

/** First letter of the company name for the chip. Falls back to "?" so a blank
 *  name still renders a square rather than collapsing the row's layout. */
export function companyInitial(name: string | null | undefined): string {
  const ch = (name ?? "").trim().charAt(0)
  return ch ? ch.toUpperCase() : "?"
}
