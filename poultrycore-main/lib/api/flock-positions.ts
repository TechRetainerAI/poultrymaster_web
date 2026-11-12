import { buildApiUrl, getAuthHeaders } from "./config"
import type { FlockBirdPosition } from "./flock-closeout"

/**
 * GET /api/Flock/positions (migration 419): every flock's bird position --
 * originally placed, the opening historical reduction from Initial Farm Setup,
 * what was recorded since, and live now -- in one call.
 *
 * List pages must read this instead of flock.quantity: for an onboarded flock
 * quantity is the OPENING LIVE count, so summing it drops every bird that died,
 * was sold, culled or transferred before tracking began.
 */
export interface FlockPositionRow extends FlockBirdPosition {
  batchId: number | null
  isClosed: boolean
  isDeleted: boolean
  /** Originally placed; the opening live count when the history is not known. */
  startedBirds: number
}

/** Null when the server predates 419 -- callers fall back to their old figures. */
export async function getFlockPositions(farmId: string): Promise<FlockPositionRow[] | null> {
  if (!farmId) return null
  try {
    const url = buildApiUrl(`/Flock/positions?farmId=${encodeURIComponent(farmId)}`)
    const response = await fetch(url, { method: "GET", headers: getAuthHeaders() })
    if (!response.ok) return null
    const data = await response.json()
    return Array.isArray(data) ? (data as FlockPositionRow[]) : null
  } catch {
    return null
  }
}
