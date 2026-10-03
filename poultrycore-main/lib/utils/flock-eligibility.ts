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

export type FlockLifecycleStatus = "pending" | "active" | "inactive" | "closed"

/**
 * Closed through Close Flock (migration 338). Distinct from merely inactive:
 * a closed flock's birds are reconciled to zero and its house released, and
 * only Reopen Flock brings it back.
 */
export function isFlockClosed(flock: Pick<Flock, "closedDate"> | null | undefined): boolean {
  return Boolean(flock?.closedDate)
}

export function getFlockLifecycleStatus(
  flock: Pick<Flock, "active" | "hasArrived"> & Partial<Pick<Flock, "closedDate">>,
  _now?: Date
): FlockLifecycleStatus {
  if (isFlockClosed(flock)) return "closed"
  if (!flock.hasArrived) return "pending"
  return flock.active ? "active" : "inactive"
}

/**
 * May this flock be offered in a data-entry picker (production, feed,
 * medication, bird sales)? Closed flocks never are -- the database refuses the
 * write anyway -- unless it is the flock the record being edited already
 * belongs to, which must stay visible so the form can show it.
 */
export function isFlockOpenForEntry(
  flock: Pick<Flock, "flockId"> & Partial<Pick<Flock, "closedDate">>,
  keepFlockId?: number | null,
): boolean {
  if (keepFlockId != null && flock.flockId === keepFlockId) return true
  return !isFlockClosed(flock)
}

/**
 * Inactive flocks may be auto-activated when the reason indicates they were
 * only waiting for placement (not culled). Skip if birds haven't arrived yet.
 */
export function shouldAutoActivateFlock(flock: Flock, _now?: Date): boolean {
  // A closed flock is finished, not waiting. Its reason is 'closed', which the
  // heuristics below would not match either -- this makes it explicit, and the
  // database refuses the update regardless.
  if (isFlockClosed(flock)) return false
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
  const closedDate = (row.closedDate ?? row.ClosedDate ?? null) as string | null
  return getFlockLifecycleStatus({ active, hasArrived, closedDate } as Flock, now)
}
