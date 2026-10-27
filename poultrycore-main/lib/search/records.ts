/**
 * The record half of the header search: named things (a customer, a supplier,
 * a flock, a product) as opposed to pages.
 *
 * A record source is only ever offered when the page it lands on is in the
 * user's gated page index (see use-global-search). A record is a way INTO a
 * page, so it must not be a way around that page's permission.
 */

import { scoreFields } from "./fuzzy"

export type RecordKind = "customer" | "supplier" | "flock" | "house" | "product" | "driver"

export interface SearchRecord {
  kind: RecordKind
  /** Unique within its kind. */
  id: string
  title: string
  /** Phone, city, breed -- whatever helps tell two "Kofi"s apart. */
  subtitle?: string
  /** Extra text that should match (email, SKU) but is not shown. */
  extra?: string[]
  /** Phone numbers, matched on their digits alone. */
  phones?: (string | null | undefined)[]
  href: string
  /**
   * When set, the landing page is a LIST, and this is put in front of it
   * through the globalSearchQuery hand-off so it opens already filtered.
   */
  prefill?: string
  inactive?: boolean
}

export const RECORD_KIND_LABEL: Record<RecordKind, string> = {
  customer: "Customer",
  supplier: "Supplier",
  flock: "Flock",
  house: "House",
  product: "Product",
  driver: "Driver",
}

export interface RankedRecord extends SearchRecord {
  score: number
}

export function rankRecords(text: string, records: SearchRecord[], limit = 6): RankedRecord[] {
  if (!text.trim()) return []
  // A query that is a phone number fragment is matched on digits, and a local
  // leading 0 is allowed to meet a stored country code: "0244" finds +233 244.
  const qDigits = /^[\d\s+()-]+$/.test(text.trim()) ? phoneDigits(text) : ""
  const ranked: RankedRecord[] = []
  for (const r of records) {
    if (qDigits.length >= 4) {
      const local = qDigits.replace(/^0/, "")
      const hit = (r.phones ?? []).some((p) => {
        const d = phoneDigits(p)
        return d.includes(qDigits) || (local.length >= 4 && d.includes(local))
      })
      if (hit) ranked.push({ ...r, score: 75 - (r.inactive ? 8 : 0) })
      continue
    }
    let score = scoreFields(text, [
      { text: r.title, weight: 1 },
      { text: r.subtitle ?? "", weight: 0.6 },
      ...(r.extra ?? []).map((e) => ({ text: e, weight: 0.6 })),
    ])
    // Records are noisier than pages (hundreds of names), so they need a real
    // hit -- a loose subsequence across someone's name is not one.
    if (score < 45) continue
    if (r.inactive) score -= 8
    ranked.push({ ...r, score })
  }
  return ranked.sort((a, b) => b.score - a.score).slice(0, limit)
}

/** Digits only, so "024 412" finds "+233 24 412 ...". */
export function phoneDigits(s?: string | null): string {
  return (s ?? "").replace(/\D+/g, "")
}
