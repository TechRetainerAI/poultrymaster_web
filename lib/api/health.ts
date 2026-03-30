// Health Records REST client targeting PoultryFarmAPI

import { buildApiUrl, getAuthHeaders } from './config'

function normalizeApiBase(raw?: string, fallback = 'farmapi.techretainer.com') {
  const val = raw || fallback
  return val.startsWith('http://') || val.startsWith('https://') ? val : `https://${val}`
}

// For server-side use
const DIRECT_API_BASE_URL = normalizeApiBase(process.env.NEXT_PUBLIC_API_BASE_URL)

// Check if we should use proxy (browser) or direct URL (server)
const IS_BROWSER = typeof window !== 'undefined'

export interface HealthRecord {
  id?: number
  userId?: string
  farmId?: string
  flockId?: number | null
  houseId?: number | null
  itemId?: number | null
  recordDate: string
  vaccination?: string | null
  medication?: string | null
  waterConsumption?: number | null
  notes?: string | null
}

export interface HealthRecordInput {
  userId: string
  farmId: string
  flockId?: number | null
  houseId?: number | null
  itemId?: number | null
  recordDate: string
  vaccination?: string | null
  medication?: string | null
  waterConsumption?: number | null
  notes?: string | null
}

export interface ApiResponse<T = any> {
  success: boolean
  data?: T
  message?: string
  errors?: string[]
}

async function request<T>(path: string, init?: RequestInit): Promise<ApiResponse<T>> {
  try {
    // Remove /api/ prefix if present (buildApiUrl handles it)
    const cleanPath = path.startsWith('/api/') ? path.replace('/api', '') : path
    const url = IS_BROWSER ? buildApiUrl(cleanPath) : `${DIRECT_API_BASE_URL}${path}`
    
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

    const contentType = res.headers.get('content-type') || ''
    const body = contentType.includes('application/json') ? await res.json() : await res.text()

    if (!res.ok) {
      // Handle 404 gracefully - endpoint might not exist on backend
      if (res.status === 404) {
        console.log(`[v0] Health API endpoint not available (404): ${path}`)
      } else {
        console.warn(`[v0] Health API error (${res.status}):`, body && (body.message || body.Message) || res.statusText)
      }
      return { success: false, message: (body && (body.message || body.Message)) || res.statusText }
    }

    return { success: true, data: body }
  } catch (error: any) {
    console.error(`[v0] Health API network error:`, error)
    return { success: false, message: error?.message || 'Network error' }
  }
}

// GET /api/Health?userId=&farmId=&flockId=
export async function getHealthRecords(
  userId: string,
  farmId: string,
  flockId?: number | null,
  houseId?: number | null,
  itemId?: number | null
): Promise<ApiResponse<HealthRecord[]>> {
  const params = new URLSearchParams({ userId, farmId })
  if (flockId) params.append('flockId', flockId.toString())
  if (houseId) params.append('houseId', houseId.toString())
  if (itemId) params.append('itemId', itemId.toString())
  return request<HealthRecord[]>(`/Health?${params.toString()}`)
}

// GET /api/Health/{id}?userId=&farmId=
export async function getHealthRecord(
  id: number,
  userId: string,
  farmId: string
): Promise<ApiResponse<HealthRecord>> {
  return request<HealthRecord>(`/Health/${id}?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`)
}

// POST /api/Health
export async function createHealthRecord(input: HealthRecordInput): Promise<ApiResponse<HealthRecord>> {
  const payload = {
    UserId: input.userId,
    FarmId: input.farmId,
    FlockId: input.flockId ?? null,
    HouseId: input.houseId ?? null,
    ItemId: input.itemId ?? null,
    RecordDate: input.recordDate,
    Vaccination: input.vaccination ?? null,
    Medication: input.medication ?? null,
    WaterConsumption: input.waterConsumption ?? null,
    Notes: input.notes ?? null,
  }
  return request<HealthRecord>(`/Health`, {
    method: 'POST',
    body: JSON.stringify(payload),
  })
}

// PUT /api/Health/{id}
export async function updateHealthRecord(id: number, input: HealthRecordInput): Promise<ApiResponse<HealthRecord>> {
  const payload = {
    Id: id,
    UserId: input.userId,
    FarmId: input.farmId,
    FlockId: input.flockId ?? null,
    HouseId: input.houseId ?? null,
    ItemId: input.itemId ?? null,
    RecordDate: input.recordDate,
    Vaccination: input.vaccination ?? null,
    Medication: input.medication ?? null,
    WaterConsumption: input.waterConsumption ?? null,
    Notes: input.notes ?? null,
  }
  return request<HealthRecord>(`/Health/${id}`, {
    method: 'PUT',
    body: JSON.stringify(payload),
  })
}

// DELETE /api/Health/{id}?userId=&farmId=
export async function deleteHealthRecord(
  id: number,
  userId: string,
  farmId: string
): Promise<ApiResponse<void>> {
  // SECURITY: Validate required parameters before proceeding
  if (!userId || !farmId) {
    console.error("[v0] Security: Missing userId or farmId for health record deletion");
    return {
      success: false,
      message: "Authorization required. Please log in again.",
    } as any;
  }
  
  if (!id || !Number.isFinite(id) || id <= 0) {
    console.error("[v0] Security: Invalid health record ID");
    return {
      success: false,
      message: "Invalid health record ID",
    } as any;
  }
  
  return request<void>(`/Health/${id}?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`, {
    method: 'DELETE',
  })
}

