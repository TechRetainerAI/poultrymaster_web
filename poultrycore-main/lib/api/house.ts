// Houses REST client targeting PoultryFarmAPI

import { buildApiUrl, getAuthHeaders } from './config'

import { DEFAULT_FARM_API_HOST } from '@/lib/api/default-api-hosts'

function normalizeApiBase(raw?: string, fallback = DEFAULT_FARM_API_HOST) {
  const val = raw || fallback
  return val.startsWith('http://') || val.startsWith('https://') ? val : `https://${val}`
}

// For server-side use
const DIRECT_API_BASE_URL = normalizeApiBase(process.env.NEXT_PUBLIC_API_BASE_URL)

// Check if we should use proxy (browser) or direct URL (server)
const IS_BROWSER = typeof window !== 'undefined'

export interface House {
  houseId: number
  farmId: string
  name: string
  capacity?: number | null
  createdDate?: string
  location?: string | null
}

export interface HouseInput {
  userId: string
  farmId: string
  name: string
  capacity?: number | null
  location?: string | null
}

/** One row of a bulk create. The company is stated once, on the envelope. */
export interface BulkHouseItem {
  houseName: string
  capacity?: number | null
  location?: string | null
}

export interface BulkHouseCreateInput {
  userId: string
  farmId: string
  houses: BulkHouseItem[]
  /** Which screen this batch came from; recorded in the audit trail. */
  source?: string
}

/** A validation failure pinned to the row that caused it. */
export interface BulkHouseRowError {
  index: number
  field: string
  message: string
}

export interface BulkHouseCreateResult {
  success: boolean
  createdCount: number
  houses: House[]
  errors: BulkHouseRowError[]
  message?: string
}

export interface ApiResponse<T = any> {
  success: boolean
  data?: T
  message?: string
  errors?: string[]
}

// Map backend HouseModel (PascalCase) to frontend House (camelCase)
function mapHouse(raw: any): House {
  return {
    houseId: Number(raw.houseId ?? raw.HouseId ?? 0),
    farmId: raw.farmId ?? raw.FarmId ?? "",
    name: raw.name ?? raw.Name ?? raw.HouseName ?? raw.houseName ?? "",
    capacity: raw.capacity ?? raw.Capacity ?? null,
    createdDate: raw.createdDate ?? raw.CreatedDate ?? undefined,
    location: raw.location ?? raw.Location ?? null,
  }
}

// Backend BulkHouseCreateResult (PascalCase) -> camelCase, tolerating a body
// that never arrived (network error, HTML error page).
function mapBulkResult(raw: any): BulkHouseCreateResult {
  const houses = raw?.houses ?? raw?.Houses ?? []
  const errors = raw?.errors ?? raw?.Errors ?? []
  return {
    success: Boolean(raw?.success ?? raw?.Success ?? false),
    createdCount: Number(raw?.createdCount ?? raw?.CreatedCount ?? 0),
    houses: Array.isArray(houses) ? houses.map(mapHouse) : [],
    errors: (Array.isArray(errors) ? errors : []).map((e: any) => ({
      index: Number(e?.index ?? e?.Index ?? -1),
      field: e?.field ?? e?.Field ?? "",
      message: e?.message ?? e?.Message ?? "",
    })),
    message: raw?.message ?? raw?.Message ?? undefined,
  }
}

async function request<T>(path: string, init?: RequestInit): Promise<ApiResponse<T>> {
  try {
    // Separate pathname and query string
    const [pathname, queryString] = path.split('?')
    const queryPart = queryString ? `?${queryString}` : ''
    
    // Remove /api/ prefix if present (buildApiUrl handles it)
    const cleanPathname = pathname.startsWith('/api/') ? pathname.replace('/api', '') : pathname
    const fullPath = cleanPathname + queryPart
    const url = IS_BROWSER ? buildApiUrl(fullPath) : `${DIRECT_API_BASE_URL}${pathname}${queryPart}`
    
    const method = init?.method || 'GET'
    const headers = getAuthHeaders()
    
    // Merge any additional headers from init
    if (init?.headers) {
      Object.assign(headers, init.headers)
    }

    const res = await fetch(url, {
      method,
      headers,
      ...init,
    })

    // Handle 204 No Content - no body to read
    if (res.status === 204) {
      return { success: true, data: undefined as any }
    }

    const contentType = res.headers.get('content-type') || ''
    const body = contentType.includes('application/json') ? await res.json() : await res.text()

    if (!res.ok) {
      // Handle 404 gracefully - endpoint might not exist on backend
      if (res.status === 404) {
        console.log(`[v0] House API endpoint not available (404): ${path}`)
      } else {
        console.warn(`[v0] House API error (${res.status}):`, body && (body.message || body.Message) || res.statusText)
      }
      // Hand the parsed body back too: a rejected bulk batch carries per-row
      // errors, and a bare statusText would lose them.
      return { success: false, message: (body && (body.message || body.Message)) || res.statusText, data: body }
    }

    return { success: true, data: body }
  } catch (error: any) {
    console.error(`[v0] House API network error:`, error)
    return { success: false, message: error?.message || 'Network error' }
  }
}

// GET /api/House?userId=&farmId=
export async function getHouses(userId: string, farmId: string): Promise<ApiResponse<House[]>> {
  const qs = new URLSearchParams({ userId, farmId }).toString()
  const res = await request<any[]>(`/api/House?${qs}`)
  if (!res.success || !Array.isArray(res.data)) {
    return { success: false, message: res.message || "Failed to fetch houses", data: [] }
  }

  const mapped = res.data.map(mapHouse)
  return {
    success: true,
    data: mapped,
    message: res.message,
  }
}

// GET /api/House/{id}?userId=&farmId=
export async function getHouse(id: number, userId: string, farmId: string): Promise<ApiResponse<House>> {
  const res = await request<any>(`/api/House/${id}?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`)
  if (!res.success || !res.data) {
    return { success: false, message: res.message || "Failed to fetch house" } as ApiResponse<House>
  }

  return {
    success: true,
    data: mapHouse(res.data),
    message: res.message,
  }
}

// POST /api/House { UserId, FarmId, HouseName, Capacity, Location }
export async function createHouse(input: HouseInput): Promise<ApiResponse<House>> {
  const payload = {
    UserId: input.userId,
    FarmId: input.farmId,
    HouseName: input.name,
    Capacity: input.capacity ?? null,
    Location: input.location ?? null,
  }
  const res = await request<any>(`/api/House`, {
    method: 'POST',
    body: JSON.stringify(payload),
  })

  if (!res.success || !res.data) {
    return { success: false, message: res.message || "Failed to create house" } as ApiResponse<House>
  }

  return {
    success: true,
    data: mapHouse(res.data),
    message: res.message,
  }
}

/**
 * POST /api/House/bulk -- create many houses for the active company at once.
 *
 * Same endpoint family, same permission and the same stored function as
 * createHouse; the server does the N inserts inside one transaction, so either
 * every house in the batch exists afterwards or none does.
 *
 * `source` names the screen the batch came from and ends up on the per-house
 * audit rows, which is what lets the Farm Setup Wizard and the Batch-to-Flock
 * allocation screen reuse this without becoming indistinguishable in the log.
 */
export async function createHousesBulk(input: BulkHouseCreateInput): Promise<ApiResponse<BulkHouseCreateResult>> {
  const payload = {
    UserId: input.userId,
    FarmId: input.farmId,
    Source: input.source ?? "Houses page",
    Houses: input.houses.map((h) => ({
      HouseName: h.houseName,
      Capacity: h.capacity ?? null,
      Location: h.location ?? null,
    })),
  }

  const res = await request<any>(`/api/House/bulk`, {
    method: 'POST',
    body: JSON.stringify(payload),
  })

  // A rejected batch still carries the per-row errors the grid needs, but
  // `request` only hands back a message on a non-2xx. Re-read the body here so a
  // 400 can point at row 3 rather than saying "Bad Request".
  if (!res.success) {
    return {
      success: false,
      message: res.message || "Failed to create houses",
      data: mapBulkResult(res.data),
    }
  }

  return { success: true, data: mapBulkResult(res.data), message: res.data?.message ?? res.message }
}

// PUT /api/House/{id}
export async function updateHouse(id: number, input: HouseInput): Promise<ApiResponse<House>> {
  const payload = {
    UserId: input.userId,
    FarmId: input.farmId,
    HouseId: id,
    HouseName: input.name,
    Capacity: input.capacity ?? null,
    Location: input.location ?? null,
  }
  const res = await request<any>(`/api/House/${id}`, {
    method: 'PUT',
    body: JSON.stringify(payload),
  })

  if (!res.success) {
    return { success: false, message: res.message || "Failed to update house" } as ApiResponse<House>
  }

  // For 204 No Content, fetch the updated house to return it
  if (res.data === undefined) {
    // Only try to fetch if we have valid userId and farmId
    if (input.userId && input.farmId) {
      try {
        const updatedRes = await getHouse(id, input.userId, input.farmId)
        if (updatedRes.success && updatedRes.data) {
          return {
            success: true,
            data: updatedRes.data,
            message: "House updated successfully",
          }
        }
      } catch (error) {
        // If fetch fails (e.g., 404), still return success since update succeeded
        console.warn(`[v0] Failed to fetch updated house ${id}, but update succeeded:`, error)
      }
    }
    // Return success with constructed house data since update succeeded
    return {
      success: true,
      data: { houseId: id, farmId: input.farmId, name: input.name, capacity: input.capacity, location: input.location } as House,
      message: "House updated successfully",
    }
  }

  return {
    success: true,
    data: mapHouse(res.data),
    message: res.message,
  }
}

// DELETE /api/House/{id}?userId=&farmId={}
export async function deleteHouse(id: number, userId: string, farmId: string): Promise<ApiResponse<void>> {
  // SECURITY: Validate required parameters before proceeding
  if (!userId || !farmId) {
    console.error("[v0] Security: Missing userId or farmId for house deletion");
    return {
      success: false,
      message: "Authorization required. Please log in again.",
    } as any;
  }
  
  if (!id || !Number.isFinite(id) || id <= 0) {
    console.error("[v0] Security: Invalid house ID");
    return {
      success: false,
      message: "Invalid house ID",
    } as any;
  }
  
  return request<void>(`/api/House/${id}?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`, { method: 'DELETE' })
}
