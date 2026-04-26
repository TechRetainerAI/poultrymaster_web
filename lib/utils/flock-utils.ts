import { getFlocks, type Flock } from "@/lib/api/flock"
import { getUserContext } from "@/lib/utils/user-context"

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

export function getFlocksForSelect(): { value: string; label: string }[] {
  if (!flocksCache) {
    return []
  }
  
  return flocksCache
    .filter(flock => flock.active) // Only show active flocks
    .map(flock => ({
      value: flock.flockId.toString(),
      label: `${flock.name} (${flock.breed}) - ${flock.quantity} birds`
    }))
}
