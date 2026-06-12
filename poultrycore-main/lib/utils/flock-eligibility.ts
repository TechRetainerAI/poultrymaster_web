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
 * birds have physically arrived AND it's marked active in the DB.
 * Start date is informational — placement is decided by the user via HasArrived.
 */
export function flockCountsTowardBirdTotals(flock: Pick<Flock, "active" | "hasArrived">, _now?: Date): boolean {
  return Boolean(flock.active) && Boolean(flock.hasArrived)
}

export type FlockLifecycleStatus = "pending" | "active" | "inactive"

export function getFlockLifecycleStatus(
  flock: Pick<Flock, "active" | "hasArrived">,
  _now?: Date
): FlockLifecycleStatus {
  if (!flock.hasArrived) return "pending"
  return flock.active ? "active" : "inactive"
}

/**
 * Inactive flocks may be auto-activated when the reason indicates they were
 * only waiting for placement (not culled). Skip if birds haven't arrived yet.
 */
export function shouldAutoActivateFlock(flock: Flock, _now?: Date): boolean {
  if (!flock.hasArrived || flock.active) return false
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
  const hasArrived = Boolean(row.hasArrived ?? row.HasArrived)
  return flockCountsTowardBirdTotals({ active, hasArrived } as Flock, now)
}

export function flockRowLifecycleStatus(row: Record<string, unknown>, now?: Date): FlockLifecycleStatus {
  const active = Boolean(row.active ?? row.Active)
  const hasArrived = Boolean(row.hasArrived ?? row.HasArrived)
  return getFlockLifecycleStatus({ active, hasArrived } as Flock, now)
}
