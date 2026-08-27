// Pure calculations behind a production record.
//
// Extracted from the form so the numbers can be tested on their own, and so
// "the modal and the full page calculate the same way" is enforced by them
// calling the same functions rather than by two copies happening to agree.
// There is exactly one caller today — components/production/production-record-form
// — which both display modes render.

export const EGGS_PER_CRATE = 30

/** Eggs in one pick. Total = crates × 30 + loose. */
export function pickTotal(crates: number, loose: number, eggsPerCrate = EGGS_PER_CRATE): number {
  const c = Number.isFinite(crates) ? Math.max(0, Math.trunc(crates)) : 0
  const l = Number.isFinite(loose) ? Math.max(0, Math.trunc(loose)) : 0
  return c * eggsPerCrate + l
}

/** Split a raw egg count into whole crates plus the remainder. */
export function cratesEquivalent(totalEggs: number, eggsPerCrate = EGGS_PER_CRATE): { crates: number; pieces: number } {
  const t = Number.isFinite(totalEggs) ? Math.max(0, Math.trunc(totalEggs)) : 0
  return { crates: Math.floor(t / eggsPerCrate), pieces: t % eggsPerCrate }
}

/**
 * Eggs that cannot be sold.
 *
 * Same definition as migration 198 and the Egg Stock Balance report: an egg
 * counts towards stock on hand only if it is not broken, meaty, soft-shelled or
 * lost. Keeping one definition is what stops the form and the report disagreeing.
 */
export function totalLosses(l: { broken?: number; meaty?: number; soft?: number; lost?: number }): number {
  return (l.broken || 0) + (l.meaty || 0) + (l.soft || 0) + (l.lost || 0)
}

/** Never negative: more losses than picked is a data-entry error, not a negative stock. */
export function netSellableEggs(totalPicked: number, losses: number): number {
  return Math.max((totalPicked || 0) - (losses || 0), 0)
}

/**
 * Birds left is ALWAYS birds − deaths.
 *
 * Deliberately not clamped: a negative result is what the form's validation
 * blocks on, so hiding it here would hide the error.
 */
export function birdsLeft(numBirds: number, deaths: number): number {
  return (numBirds || 0) - (deaths || 0)
}

/**
 * Flock age on a given date, from its start date.
 *
 * Both dates are normalised to UTC date-only. Using local dates here caused an
 * off-by-one whenever the two straddled a timezone boundary.
 */
export function flockAge(startDate: string | null | undefined, onDate: string | null | undefined): {
  ageWeeks: number; ageDays: number; ageYears: number
} {
  const zero = { ageWeeks: 0, ageDays: 0, ageYears: 0 }
  try {
    if (!startDate || !onDate) return zero
    const [sy, sm, sd] = startDate.split("T")[0].split("-").map(Number)
    const [cy, cm, cd] = onDate.split("T")[0].split("-").map(Number)
    if ([sy, sm, sd, cy, cm, cd].some((n) => !Number.isFinite(n))) return zero
    const ms = Math.max(0, Date.UTC(cy, cm - 1, cd) - Date.UTC(sy, sm - 1, sd))
    const days = Math.floor(ms / 86400000)
    return { ageWeeks: Math.floor(days / 7), ageDays: days, ageYears: Math.floor(days / 365) }
  } catch {
    return zero
  }
}

/**
 * The age actually saved.
 *
 * Manual entry accepts whichever box the user filled — days, else years, else
 * weeks — which is the existing behaviour and why the fallbacks chain rather
 * than defaulting to 0.
 */
export function resolveAge(
  manual: boolean,
  manualEntry: { weeks?: string; days?: string; years?: string },
  calculated: { ageWeeks: number; ageDays: number },
): { ageInWeeks: number; ageInDays: number } {
  if (!manual) return { ageInWeeks: calculated.ageWeeks, ageInDays: calculated.ageDays }
  const w = parseInt(manualEntry.weeks || "") || 0
  const d = parseInt(manualEntry.days || "") || 0
  const y = parseInt(manualEntry.years || "") || 0
  return {
    ageInDays: d || y * 365 || w * 7,
    ageInWeeks: w || Math.floor(d / 7) || y * 52,
  }
}

/**
 * Feed kilograms to save.
 *
 * The Feed Breakdown wins when it has lines: the same feed must not be counted
 * both as an inventory draw and as a manual quantity. With no lines the manual
 * box is used, which is how most farms still record feed.
 *
 * The list-page modal used to ignore the lines entirely and save the manual box
 * alone, so feed entered as lines was stored as 0.
 */
export function effectiveFeedKg(lineTotalConsumed: number, manualFeedKg: string | number): number {
  if ((lineTotalConsumed || 0) > 0) return lineTotalConsumed
  const manual = typeof manualFeedKg === "number" ? manualFeedKg : parseFloat(manualFeedKg || "")
  return Number.isFinite(manual) ? manual : 0
}

/** Total cost of production = feed + medication, as the record stores it. */
export function totalCostOfProduction(feedCost: number, medicationCost: number): number {
  return Number(((feedCost || 0) + (medicationCost || 0)).toFixed(2))
}
