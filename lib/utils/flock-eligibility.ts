import type { Flock } from "@/lib/api/flock"
import { toLocalDateKey } from "@/lib/utils/date-key"

/** True when the flock's start date (local calendar) is today or earlier. */
export function flockHasReachedStartDate(flock: Pick<Flock, "startDate">, now: Date = new Date()): boolean {
  const startKey = toLocalDateKey(flock.startDate)
  if (!startKey) return false
  const todayKey = toLocalDateKey(now.toISOString())
  return startKey <= todayKey
}

/**
 * Flock contributes to farm-wide bird totals (billing, summaries, selects):
 * marked active in the DB and start date has been reached.
 */
export function flockCountsTowardBirdTotals(flock: Pick<Flock, "active" | "startDate">, now?: Date): boolean {
  return Boolean(flock.active) && flockHasReachedStartDate(flock, now)
}

export type FlockLifecycleStatus = "pending" | "active" | "inactive"

export function getFlockLifecycleStatus(
  flock: Pick<Flock, "active" | "startDate">,
  now?: Date
): FlockLifecycleStatus {
  if (!flockHasReachedStartDate(flock, now)) return "pending"
  return flock.active ? "active" : "inactive"
}

/**
 * Inactive flocks whose start date has passed may be auto-activated when the reason
 * indicates they were only waiting for placement (not culled).
 */
export function shouldAutoActivateFlock(flock: Flock, now?: Date): boolean {
  if (!flockHasReachedStartDate(flock, now) || flock.active) return false
  const r = (flock.inactivationReason ?? "").trim().toLowerCase()
  if (!r) return true
  return (
    r.includes("not yet ready") ||
    r.includes("not ready") ||
    r.includes("before start") ||
    r.includes("pending") ||
    r.includes("awaiting") ||
    r.includes("pre-placement") ||
    r.includes("placement")
  )
}

/** Normalize API row (camelCase or PascalCase) for eligibility helpers. */
export function flockRowCountsTowardBirdTotals(row: Record<string, unknown>, now?: Date): boolean {
  const active = Boolean(row.active ?? row.Active)
  const startDate = String(row.startDate ?? row.StartDate ?? "")
  return flockCountsTowardBirdTotals({ active, startDate } as Flock, now)
}

export function flockRowLifecycleStatus(row: Record<string, unknown>, now?: Date): FlockLifecycleStatus {
  const active = Boolean(row.active ?? row.Active)
  const startDate = String(row.startDate ?? row.StartDate ?? "")
  return getFlockLifecycleStatus({ active, startDate } as Flock, now)
}
