import { getFlocks, type Flock } from "@/lib/api/flock"
import { getUserContext } from "@/lib/utils/user-context"
import { flockCountsTowardBirdTotals, getFlockLifecycleStatus } from "@/lib/utils/flock-eligibility"

// Cache for flocks to avoid repeated API calls
let flocksCache: Flock[] | null = null
let cacheTimestamp: number = 0
const CACHE_DURATION = 5 * 60 * 1000 // 5 minutes

export async function getValidFlocks(): Promise<Flock[]> {
  const { farmId, userId } = getUserContext()
  
  if (!farmId || !userId) {
    console.warn("[v0] No farmId or userId found, returning empty flocks list")
    return []
  }

  // Check if cache is still valid
  const now = Date.now()
  if (flocksCache && (now - cacheTimestamp) < CACHE_DURATION) {
    console.log("[v0] Using cached flocks data")
    return flocksCache
  }

  try {
    console.log("[v0] Fetching fresh flocks data for forms")
    const result = await getFlocks(userId, farmId)
    
    if (result.success && result.data) {
      flocksCache = result.data
      cacheTimestamp = now
      console.log("[v0] Cached flocks data:", flocksCache.length, "flocks")
      return flocksCache
    }
    
    console.warn("[v0] Failed to fetch flocks, returning empty list")
    return []
  } catch (error) {
    console.error("[v0] Error fetching flocks:", error)
    return []
  }
}

export function clearFlocksCache() {
  flocksCache = null
  cacheTimestamp = 0
  console.log("[v0] Cleared flocks cache")
}

function flockSelectLabel(flock: Flock): string {
  const status = getFlockLifecycleStatus(flock)
  const statusNote =
    status === "pending" ? " · Pending arrival" : status === "inactive" ? " · Inactive" : ""
  return `${flock.name} (${flock.breed}) - ${flock.quantity} birds${statusNote}`
}

/** Flocks eligible for production / feed (arrived + active). */
export function getFlocksForSelect(): { value: string; label: string }[] {
  if (!flocksCache) return []

  return flocksCache
    .filter((flock) => flockCountsTowardBirdTotals(flock))
    .map((flock) => ({
      value: flock.flockId.toString(),
      label: flockSelectLabel(flock),
    }))
}

/** All flocks on the farm — for expenses (includes pending / inactive). */
export function getFlocksForExpenseSelect(): { value: string; label: string }[] {
  if (!flocksCache) return []

  return flocksCache.map((flock) => ({
    value: flock.flockId.toString(),
    label: flockSelectLabel(flock),
  }))
}

/** Flocks that have physically arrived — for production logging. */
export function getFlocksForProductionSelect(): { value: string; label: string }[] {
  if (!flocksCache) return []

  return flocksCache
    .filter((flock) => flock.hasArrived)
    .map((flock) => ({
      value: flock.flockId.toString(),
      label: flockSelectLabel(flock),
    }))
}

export function getFlockSelectEmptyHint(
  mode: "expense" | "production" | "eligible"
): string {
  const total = flocksCache?.length ?? 0
  if (total === 0) {
    return "No flocks in the database for this farm. Add a flock on the Flocks page first."
  }
  if (mode === "expense") {
    return "Flocks could not be loaded. Check your connection and try again."
  }
  const eligible =
    mode === "production"
      ? flocksCache!.filter((f) => f.hasArrived).length
      : flocksCache!.filter((f) => flockCountsTowardBirdTotals(f)).length
  if (eligible === 0) {
    return `You have ${total} flock(s), but none are ready for ${mode === "production" ? "production" : "this form"} yet. On the Flocks page, turn on “Flock Has Arrived” (and keep the flock Active).`
  }
  return "No flocks available"
}
