// Pure helpers for Distribute Feed (migration 335). No React, no fetch —
// covered by feed-distribution.test.ts.
//
// Suggestions are only ever suggestions: Actual is what posts, and it is
// always the farmer's to type. A suggestion comes from the farm's OWN rate
// (grams per bird per day, saved per feed or typed for this distribution) or,
// only when chosen, from the flock's recent average — never from a built-in
// "standard" figure, and never silently swapped one for the other.

export type SuggestionBasis = "Rate" | "RecentAverage"

export interface DistributionCandidate {
  flockId: number
  flockName: string
  batchName: string | null
  houseName: string | null
  recordCount: number
  productionRecordId: number | null
  birds: number | null
  manualFeedKg: number | null
  stockFeedKg: number
  thisItemKg: number
  recentAvgKg: number | null
  recentAvgDays: number | null
}

/** grams/bird/day × birds → kg, to the gram. 1,840 birds × 112.5 g = 207 kg. */
export function suggestedKgByRate(birds: number | null | undefined, gramsPerBirdPerDay: number | null | undefined): number | null {
  const b = Number(birds)
  const g = Number(gramsPerBirdPerDay)
  if (!Number.isFinite(b) || !Number.isFinite(g) || b <= 0 || g <= 0) return null
  return Math.round(b * g) / 1000
}

export type RowState = "ok" | "noRecord" | "duplicate"

/** Only a flock with exactly one production record for the date can receive feed. */
export function rowState(c: Pick<DistributionCandidate, "recordCount">): RowState {
  if (c.recordCount === 1) return "ok"
  return c.recordCount === 0 ? "noRecord" : "duplicate"
}

export function suggestionFor(
  c: DistributionCandidate,
  basis: SuggestionBasis,
  gramsPerBirdPerDay: number | null,
): number | null {
  if (basis === "RecentAverage") return c.recentAvgKg ?? null
  return suggestedKgByRate(c.birds, gramsPerBirdPerDay)
}

/** "207.5" → 207.5; "", "abc", negatives → null. Actual is typed text. */
export function parseKg(text: string | null | undefined): number | null {
  const t = (text ?? "").trim()
  if (t === "") return null
  const n = Number(t)
  if (!Number.isFinite(n) || n < 0) return null
  return Math.round(n * 1000) / 1000
}

export interface DistributionTotals {
  available: number
  suggested: number
  actual: number
  remaining: number
}

export function distributionTotals(
  available: number,
  rows: { suggested: number | null; actualText: string; state: RowState }[],
): DistributionTotals {
  const round = (n: number) => Math.round(n * 1000) / 1000
  const suggested = rows.reduce((a, r) => a + (r.state === "ok" ? r.suggested ?? 0 : 0), 0)
  const actual = rows.reduce((a, r) => a + (r.state === "ok" ? parseKg(r.actualText) ?? 0 : 0), 0)
  return { available: round(available), suggested: round(suggested), actual: round(actual), remaining: round(available - actual) }
}

/** Why Post is disabled, in one sentence; null when it can post. */
export function postBlocker(
  totals: DistributionTotals,
  rows: { actualText: string; state: RowState }[],
): string | null {
  if (rows.some((r) => r.actualText.trim() !== "" && parseKg(r.actualText) == null)) {
    return "Fix the feed amounts that are not valid numbers."
  }
  if (totals.actual <= 0) return "Enter feed for at least one flock."
  if (totals.remaining < 0) {
    return `Not enough feed: ${Math.abs(totals.remaining).toLocaleString()} kg more than is in stock. Stock cannot go negative.`
  }
  return null
}

/**
 * Posting adds stock lines, and a record's feed kg then IS its stock lines —
 * the form's rule. A record that only had a hand-typed kg has that figure
 * replaced. Said up front rather than discovered on the record.
 */
export function manualFeedWarning(c: Pick<DistributionCandidate, "manualFeedKg">, actualKg: number | null): string | null {
  if (!actualKg || !c.manualFeedKg || c.manualFeedKg <= 0) return null
  return `Has ${c.manualFeedKg.toLocaleString()} kg typed without stock; posting replaces it with ${actualKg.toLocaleString()} kg from stock.`
}

/**
 * Units a farm can state its feed rate in (migration 336). Whatever is picked,
 * the rate is converted to grams per bird per day — the one figure stored and
 * the one the suggestion is computed from — so switching unit never changes
 * how much feed is suggested, only how the rate reads.
 */
export const RATE_UNITS = [
  { key: "g_bird", label: "g per bird per day", gramsPerUnit: 1 },
  { key: "kg_bird", label: "kg per bird per day", gramsPerUnit: 1000 },
  { key: "kg_100", label: "kg per 100 birds per day", gramsPerUnit: 10 },
  { key: "kg_1000", label: "kg per 1,000 birds per day", gramsPerUnit: 1 },
  { key: "lb_bird", label: "lb per bird per day", gramsPerUnit: 453.59237 },
  { key: "lb_100", label: "lb per 100 birds per day", gramsPerUnit: 4.5359237 },
] as const

export type RateUnit = (typeof RATE_UNITS)[number]["key"]
export const DEFAULT_RATE_UNIT: RateUnit = "g_bird"

export function isRateUnit(u: string | null | undefined): u is RateUnit {
  return RATE_UNITS.some((x) => x.key === u)
}

function unitOf(u: string | null | undefined) {
  return RATE_UNITS.find((x) => x.key === u) ?? RATE_UNITS[0]
}

export function rateUnitLabel(u: string | null | undefined): string {
  return unitOf(u).label
}

/** A rate in `unit` -> grams per bird per day. 1.1 kg per 100 birds = 11 g. */
export function toGramsPerBird(value: number | null | undefined, unit: string | null | undefined): number | null {
  const v = Number(value)
  if (value == null || !Number.isFinite(v) || v <= 0) return null
  return Math.round(v * unitOf(unit).gramsPerUnit * 1e6) / 1e6
}

/** Grams per bird per day -> the same rate in `unit`, for showing a saved rate the way it was typed. */
export function fromGramsPerBird(grams: number | null | undefined, unit: string | null | undefined): number | null {
  const g = Number(grams)
  if (grams == null || !Number.isFinite(g) || g <= 0) return null
  return Math.round((g / unitOf(unit).gramsPerUnit) * 1e6) / 1e6
}
