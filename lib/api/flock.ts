// API utility functions for Flock management

import { buildApiUrl, getAuthHeaders } from './config'

function normalizeApiBase(raw?: string, fallback = 'farmapi.techretainer.com') {
  const val = raw || fallback
  return val.startsWith('http://') || val.startsWith('https://') ? val : `https://${val}`
}

// For server-side use
const DIRECT_API_BASE_URL = normalizeApiBase(process.env.NEXT_PUBLIC_API_BASE_URL)

// Check if we should use proxy (browser) or direct URL (server)
const IS_BROWSER = typeof window !== 'undefined'

export interface Flock {
  farmId: string
  userId: string
  flockId: number
  name: string
  startDate: string
  breed: string
  quantity: number
  active: boolean
  houseId?: number | null
  batchId?: number | null
  inactivationReason?: string
  otherReason?: string
  notes?: string
  batchName?: string
}

export interface FlockInput {
  farmId: string
  userId: string
  flockId?: number
  name: string
  startDate: string
  breed: string
  quantity: number
  active: boolean
  houseId?: number | null
  batchId: number
  inactivationReason?: string
  otherReason?: string
  notes?: string
}

export interface ApiResponse<T = any> {
  success: boolean
  data?: T
  message?: string
  errors?: string[]
}

// Mock data for development
const mockFlocks: Flock[] = [
  {
    farmId: "farm-1",
    userId: "user-1",
    flockId: 1,
    name: "Layer Flock A",
    startDate: "2024-01-15T00:00:00.000Z",
    breed: "Rhode Island Red",
    quantity: 250,
    active: true,
    houseId: null,
  },
  {
    farmId: "farm-1",
    userId: "user-1",
    flockId: 2,
    name: "Broiler Flock B",
    startDate: "2024-02-01T00:00:00.000Z",
    breed: "Cornish Cross",
    quantity: 500,
    active: true,
    houseId: null,
  },
  {
    farmId: "farm-1",
    userId: "user-1",
    flockId: 3,
    name: "Retired Layer Flock",
    startDate: "2023-06-01T00:00:00.000Z",
    breed: "Leghorn",
    quantity: 180,
    active: false,
    houseId: null,
  },
]

let nextFlockId = 4

// Get all flocks
export async function getFlocks(userId?: string, farmId?: string): Promise<ApiResponse<Flock[]>> {
  try {
    const params = new URLSearchParams()
    if (userId) params.append('userId', userId)
    if (farmId) params.append('farmId', farmId)
    
    const endpoint = `/Flock${params.toString() ? '?' + params.toString() : ''}`
    const url = IS_BROWSER ? buildApiUrl(endpoint) : `${DIRECT_API_BASE_URL}/api${endpoint}`
    console.log("[v0] Fetching flocks:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: getAuthHeaders(),
    })

    console.log("[v0] Flocks response status:", response.status)

    if (!response.ok) {
      // Handle 404 gracefully - endpoint might not exist on backend
      if (response.status === 404) {
        console.log("[v0] Flocks endpoint not available (404), using mock data")
      } else {
        const errorText = await response.text()
        console.warn("[v0] Flocks API error:", response.status, errorText)
      }
      // Mock data fallback
      console.warn("[v0] Using mock data for flocks due to API error.")
      const filteredMockData = mockFlocks.filter(flock => 
        (!userId || flock.userId === userId) && 
        (!farmId || flock.farmId === farmId)
      )
      return {
        success: true,
        message: "Using mock data",
        data: filteredMockData,
      }
    }

    const contentType = response.headers.get("content-type")
    if (!contentType || !contentType.includes("application/json")) {
      console.error("[v0] Non-JSON response received")
      console.warn("[v0] Using mock data for flocks due to non-JSON response.")
      const filteredMockData = mockFlocks.filter(flock => 
        (!userId || flock.userId === userId) && 
        (!farmId || flock.farmId === farmId)
      )
      return {
        success: true,
        message: "Using mock data",
        data: filteredMockData,
      }
    }

    const data = await response.json()
    console.log("[v0] Flocks data received:", data)
    console.log("[v0] Flocks data type:", typeof data, "Is array?", Array.isArray(data))
    if (Array.isArray(data)) {
      console.log("[v0] Flocks count:", data.length)
      if (data.length > 0) {
        console.log("[v0] First flock sample:", data[0])
        console.log("[v0] Request filters - userId:", userId, "farmId:", farmId)
        console.log("[v0] First flock userId:", data[0]?.userId || data[0]?.UserId, "farmId:", data[0]?.farmId || data[0]?.FarmId)
      }
    }

    if (!Array.isArray(data)) {
      console.error("[v0] Expected array but got:", typeof data, "Value:", data)
      console.warn("[v0] Using mock data for flocks due to unexpected data format.")
      const filteredMockData = mockFlocks.filter(flock => 
        (!userId || flock.userId === userId) && 
        (!farmId || flock.farmId === farmId)
      )
      return {
        success: true,
        message: "Using mock data",
        data: filteredMockData,
      }
    }

    // Map backend PascalCase to frontend camelCase if needed
    const mappedData = (data as any[]).map((flock: any) => {
      // Extract farmId - check both PascalCase and camelCase, and ensure we get a value
      const extractedFarmId = flock.FarmId ?? flock.farmId ?? flock.FarmID ?? flock.farmID ?? null
      const extractedUserId = flock.UserId ?? flock.userId ?? flock.UserID ?? flock.userID ?? null
      
      // Log if farmId is missing
      if (!extractedFarmId) {
        console.warn("[v0] WARNING: Flock missing farmId:", {
          flockId: flock.FlockId || flock.flockId,
          name: flock.Name || flock.name,
          rawFlock: flock
        })
      }
      
      return {
        flockId: flock.FlockId ?? flock.flockId,
        userId: extractedUserId,
        farmId: extractedFarmId || '', // Ensure farmId is never null/undefined
        name: flock.Name ?? flock.name ?? '',
        breed: flock.Breed ?? flock.breed ?? '',
        startDate: flock.StartDate ?? flock.startDate ?? '',
        quantity: flock.Quantity ?? flock.quantity ?? 0,
        active: flock.Active !== undefined ? flock.Active : (flock.active !== undefined ? flock.active : true),
        houseId: flock.HouseId ?? flock.houseId ?? null,
        batchId: flock.BatchId ?? flock.batchId ?? null,
        batchName: flock.BatchName ?? flock.batchName ?? null,
        inactivationReason: flock.InactivationReason ?? flock.inactivationReason ?? null,
        otherReason: flock.OtherReason ?? flock.otherReason ?? null,
        notes: flock.Notes ?? flock.notes ?? null,
      }
    })

    console.log("[v0] Mapped flocks count:", mappedData.length)
    if (mappedData.length > 0) {
      console.log("[v0] Sample mapped flock:", mappedData[0])
      
      // CRITICAL: Log all unique farmIds to see if they're all the same
      const allFarmIds = mappedData.map((f: any) => f.farmId)
      const uniqueFarmIds = [...new Set(allFarmIds)]
      console.log("[v0] 🔍 CRITICAL DEBUG - All farmIds in response:", allFarmIds)
      console.log("[v0] 🔍 CRITICAL DEBUG - Unique farmIds:", uniqueFarmIds)
      console.log("[v0] 🔍 CRITICAL DEBUG - Number of unique farmIds:", uniqueFarmIds.length)
      
      if (uniqueFarmIds.length > 1) {
        console.error("[v0] ⚠️⚠️⚠️ ERROR: Backend returned flocks from MULTIPLE farms!")
        console.error("[v0] Unique farmIds found:", uniqueFarmIds)
        // Count flocks per farmId
        const countsByFarmId: Record<string, number> = {}
        allFarmIds.forEach((fid: string) => {
          countsByFarmId[fid] = (countsByFarmId[fid] || 0) + 1
        })
        console.error("[v0] Flocks per farmId:", countsByFarmId)
      }
    }

    // Filter by farmId and userId on the frontend as a safeguard
    // This ensures we only return flocks for the current farm, even if the backend returns all
    let filteredData = mappedData
    const originalCount = mappedData.length
    
    if (!farmId || farmId.trim() === '') {
      console.error("[v0] ⚠️ ERROR: No farmId provided for filtering! Returning empty array for security.")
      console.error("[v0] This should not happen - please check that farmId is set in localStorage")
      return {
        success: true,
        message: "No farmId provided - cannot filter flocks",
        data: [],
      }
    }
    
    // Normalize farmId - trim whitespace and convert to string for comparison
    const requestedFarmId = String(farmId || '').trim().toLowerCase()
    
    console.log("[v0] ===== FILTERING BY FARMID =====")
    console.log("[v0] Requested farmId:", requestedFarmId, "Type:", typeof farmId, "Length:", requestedFarmId.length)
    console.log("[v0] Before filter count:", filteredData.length)
    
    // Show sample farmIds from data
    const uniqueFarmIds = [...new Set(mappedData.map((f: any) => {
      const fid = String(f.farmId || '').trim().toLowerCase()
      return fid || '(empty/null)'
    }))]
    console.log("[v0] Unique farmIds in data:", uniqueFarmIds)
    console.log("[v0] Number of unique farmIds:", uniqueFarmIds.length)
    
    // Filter by farmId
    filteredData = filteredData.filter((flock: any) => {
      const flockFarmId = String(flock.farmId || '').trim().toLowerCase()
      const matches = flockFarmId === requestedFarmId && flockFarmId !== '' && requestedFarmId !== ''
      
      if (!matches) {
        console.warn("[v0] ❌ Filtered out flock:", {
          name: flock.name || '(no name)',
          flockId: flock.flockId,
          flockFarmId: flockFarmId || '(empty)',
          requestedFarmId: requestedFarmId,
          match: matches,
          flockFarmIdLength: flockFarmId.length,
          requestedFarmIdLength: requestedFarmId.length
        })
      }
      
      return matches
    })
    
    console.log("[v0] After farmId filter count:", filteredData.length)
    console.log("[v0] Filtered out:", originalCount - filteredData.length, "flocks")
    console.log("[v0] ================================")
    
    if (filteredData.length < originalCount) {
      console.warn("[v0] ⚠️ WARNING: Backend returned", originalCount - filteredData.length, "flocks from other farms!")
      console.warn("[v0] Backend should filter by farmId on the server side")
    }
    
    if (filteredData.length === 0 && originalCount > 0) {
      console.error("[v0] ⚠️ ERROR: All flocks were filtered out!")
      console.error("[v0] This could mean:")
      console.error("[v0]   1. farmId in localStorage doesn't match farmId in database")
      console.error("[v0]   2. farmId format is different (e.g., GUID vs number)")
      console.error("[v0]   3. Backend is returning flocks with null/empty farmId")
    }
    
    // IMPORTANT: Do NOT filter by userId here.
    // All users (admin + staff) for the same farm should see the same flocks.
    // Backend already enforces security; frontend only filters by farmId.

    return {
      success: true,
      message: "Flocks fetched successfully",
      data: filteredData as Flock[],
    }
  } catch (error) {
    console.error("[v0] Flocks fetch error:", error)
    console.warn("[v0] Using mock data for flocks due to error.")
    const filteredMockData = mockFlocks.filter(flock => 
      (!userId || flock.userId === userId) && 
      (!farmId || flock.farmId === farmId)
    )
    return {
      success: true,
      message: "Using mock data",
      data: filteredMockData,
    }
  }
}

// Get single flock by ID
export async function getFlock(id: number, userId?: string, farmId?: string): Promise<ApiResponse<Flock | null>> {
  try {
    const params = new URLSearchParams()
    if (userId) params.append('userId', userId)
    if (farmId) params.append('farmId', farmId)
    
    const endpoint = `/Flock/${id}${params.toString() ? '?' + params.toString() : ''}`
    const url = IS_BROWSER ? buildApiUrl(endpoint) : `${DIRECT_API_BASE_URL}/api${endpoint}`
    console.log("[v0] Fetching flock:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: getAuthHeaders(),
    })

    console.log("[v0] Flock response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Flock fetch error:", errorText)
      // Mock data fallback
      console.warn("[v0] Using mock data for flock due to API error.")
      const mockFlock = mockFlocks.find(f => f.flockId === id)
      if (mockFlock) {
        return {
          success: true,
          message: "Using mock data",
          data: mockFlock,
        }
      }
      return {
        success: false,
        message: "Flock not found",
        data: null,
      }
    }

    const contentType = response.headers.get("content-type")
    if (!contentType || !contentType.includes("application/json")) {
      console.error("[v0] Non-JSON response received")
      console.warn("[v0] Using mock data for flock due to non-JSON response.")
      const mockFlock = mockFlocks.find(f => f.flockId === id)
      if (mockFlock) {
        return {
          success: true,
          message: "Using mock data",
          data: mockFlock,
        }
      }
      return {
        success: false,
        message: "Flock not found",
        data: null,
      }
    }

    const data = await response.json()
    console.log("[v0] Flock data received:", data)

    // Map backend PascalCase to frontend camelCase (same as getFlocks)
    const mapped: Flock = {
      flockId: data.FlockId ?? data.flockId ?? id,
      userId: data.UserId ?? data.userId ?? '',
      farmId: data.FarmId ?? data.farmId ?? '',
      name: data.Name ?? data.name ?? '',
      breed: data.Breed ?? data.breed ?? '',
      startDate: data.StartDate ?? data.startDate ?? '',
      quantity: data.Quantity ?? data.quantity ?? 0,
      active: data.Active !== undefined ? data.Active : (data.active !== undefined ? data.active : true),
      houseId: data.HouseId ?? data.houseId ?? null,
      batchId: data.BatchId ?? data.batchId ?? null,
      batchName: data.BatchName ?? data.batchName ?? null,
      inactivationReason: data.InactivationReason ?? data.inactivationReason ?? '',
      otherReason: data.OtherReason ?? data.otherReason ?? '',
      notes: data.Notes ?? data.notes ?? '',
    }

    console.log("[v0] Mapped flock:", mapped)

    return {
      success: true,
      message: "Flock fetched successfully",
      data: mapped,
    }
  } catch (error) {
    console.error("[v0] Flock fetch error:", error)
    console.warn("[v0] Using mock data for flock due to error.")
    const mockFlock = mockFlocks.find(f => f.flockId === id)
    if (mockFlock) {
      return {
        success: true,
        message: "Using mock data",
        data: mockFlock,
      }
    }
    return {
      success: false,
      message: "Flock not found",
      data: null,
    }
  }
}

// Create new flock
export async function createFlock(flock: FlockInput): Promise<ApiResponse<Flock>> {
  try {
    const endpoint = `/Flock`
    const url = IS_BROWSER ? buildApiUrl(endpoint) : `${DIRECT_API_BASE_URL}/api${endpoint}`
    console.log("[v0] Creating flock:", url)
    console.log("[v0] Flock input:", flock)

    // Try to get userId and farmId from localStorage as fallback
    let farmId = flock.farmId
    let userId = flock.userId
    
    if (!farmId && typeof window !== "undefined") {
      farmId = localStorage.getItem("farmId") || ""
      console.log("[v0] Got farmId from localStorage:", farmId)
    }
    
    if (!userId && typeof window !== "undefined") {
      userId = localStorage.getItem("userId") || ""
      console.log("[v0] Got userId from localStorage:", userId)
    }

    // Validate required fields
    if (!farmId) {
      console.error("[v0] FarmId is required but not provided. Flock:", flock)
      return {
        success: false,
        message: "Farm ID is required. Please log in again.",
        data: null as any,
      }
    }

    if (!userId) {
      console.error("[v0] userId is required but not provided. Flock:", flock)
      return {
        success: false,
        message: "User ID is required. Please log in again.",
        data: null as any,
      }
    }

    // Format StartDate - ensure it has a time component if backend expects datetime
    // Some backends expect full datetime strings (YYYY-MM-DDTHH:mm:ss) instead of just date
    let formattedStartDate = flock.startDate
    if (flock.startDate && !flock.startDate.includes('T')) {
      // If it's just a date (YYYY-MM-DD), add time component (default to midnight UTC)
      formattedStartDate = `${flock.startDate}T00:00:00`
    }
    
    // Create the request body with proper field names that match the API expectations
    // Build request body, only including fields that have values (don't send null/undefined)
    const requestBody: any = {
      FarmId: farmId, // API expects FarmId (capital F)
      UserId: userId,
      FlockId: 0, // Server will assign the ID
      Name: flock.name,
      StartDate: formattedStartDate,
      Breed: flock.breed,
      Quantity: flock.quantity,
      Active: flock.active,
      BatchId: flock.batchId,
    }
    
    // Only add optional fields if they have values
    if (flock.houseId != null && flock.houseId !== 0) {
      requestBody.HouseId = flock.houseId
    }
    
    if (flock.notes != null && flock.notes.trim() !== '') {
      requestBody.Notes = flock.notes
    }
    
    // Only include inactivation fields if the flock is inactive
    if (!flock.active) {
      if (flock.inactivationReason && flock.inactivationReason.trim() !== '') {
        requestBody.InactivationReason = flock.inactivationReason
      }
      if (flock.inactivationReason === 'other' && flock.otherReason && flock.otherReason.trim() !== '') {
        requestBody.OtherReason = flock.otherReason
      }
    }

    console.log("[v0] Flock request body:", JSON.stringify(requestBody, null, 2))
    console.log("[v0] Flock input fields:", {
      farmId,
      userId,
      name: flock.name,
      startDate: flock.startDate,
      breed: flock.breed,
      quantity: flock.quantity,
      active: flock.active,
      houseId: flock.houseId,
      batchId: flock.batchId,
      inactivationReason: flock.inactivationReason,
      otherReason: flock.otherReason,
      notes: flock.notes,
    })

    const response = await fetch(url, {
      method: "POST",
      headers: getAuthHeaders(),
      body: JSON.stringify(requestBody),
    })

    console.log("[v0] Flock create response status:", response.status)
    console.log("[v0] Flock create response headers:", Object.fromEntries(response.headers.entries()))

    if (!response.ok) {
      // Read response body once (can only be read once)
      let errorMessage = `Failed to create flock (${response.status} ${response.statusText})`
      
      try {
        // Read as text first (can only read once)
        const errorText = await response.text()
        console.error("[v0] Flock create error (raw response):", errorText)
        console.error("[v0] Response status:", response.status)
        console.error("[v0] Response headers:", Object.fromEntries(response.headers.entries()))
        
        // Try to parse as JSON if it looks like JSON
        if (errorText.trim()) {
          if (errorText.trim().startsWith('{') || errorText.trim().startsWith('[')) {
            try {
              const errorJson = JSON.parse(errorText)
              console.error("[v0] Flock create error (parsed JSON):", JSON.stringify(errorJson, null, 2))
              
              // Handle various error response formats
              if (errorJson.title) {
                errorMessage = errorJson.title
                if (errorJson.detail) errorMessage += `: ${errorJson.detail}`
                if (errorJson.errors && typeof errorJson.errors === 'object') {
                  const validationErrors = Object.entries(errorJson.errors)
                    .map(([field, messages]: [string, any]) => `${field}: ${Array.isArray(messages) ? messages.join(', ') : messages}`)
                    .join('; ')
                  if (validationErrors) errorMessage += ` | Validation: ${validationErrors}`
                }
              } else if (errorJson.message) {
                errorMessage = errorJson.message
              } else if (errorJson.error) {
                errorMessage = typeof errorJson.error === 'string' ? errorJson.error : JSON.stringify(errorJson.error)
              } else if (Array.isArray(errorJson)) {
                errorMessage = errorJson.map((err: any) => err.message || JSON.stringify(err)).join('; ')
              } else if (Object.keys(errorJson).length === 0) {
                errorMessage = `Backend validation error (${response.status}). Empty JSON response usually means: 1) Required fields missing, 2) Invalid BatchId, 3) Invalid FarmId/UserId, 4) Date format issue. Check console for request details.`
              } else {
                errorMessage = JSON.stringify(errorJson)
              }
            } catch (jsonError) {
              // Not valid JSON, use as text
              errorMessage = errorText || errorMessage
            }
          } else {
            // Plain text error
            errorMessage = errorText || errorMessage
          }
        } else {
          // Empty response body
          errorMessage = `Backend returned empty error response (${response.status} ${response.statusText}). This usually indicates a validation error. Please check: 1) All required fields are provided, 2) BatchId is valid and exists, 3) FarmId and UserId are correct, 4) Date format is correct (YYYY-MM-DD).`
        }
      } catch (readError) {
        console.error("[v0] Could not read error response:", readError)
        errorMessage = `Failed to read error response (${response.status} ${response.statusText})`
      }
      
      console.error("[v0] Final error message:", errorMessage)
      console.error("[v0] Request body that caused error:", JSON.stringify(requestBody, null, 2))
      
      // SECURITY: Removed mock data modification - no client-side data creation
      // All data operations must go through backend for proper validation and security
      return {
        success: false,
        message: errorMessage,
        data: null as any,
      }
    }

    const contentType = response.headers.get("content-type")
    if (!contentType || !contentType.includes("application/json")) {
      console.error("[v0] Non-JSON response received")
      // SECURITY: Removed mock data modification - no client-side data creation
      return {
        success: false,
        message: "Invalid response from server. Please try again.",
        data: null as any,
      }
    }

    const data = await response.json()
    console.log("[v0] Created flock data:", data)

    return {
      success: true,
      message: "Flock created successfully",
      data: data as Flock,
    }
  } catch (error) {
    console.error("[v0] Flock create error:", error)
    // SECURITY: Removed mock data modification - no client-side data creation
    return {
      success: false,
      message: "Network error. Please try again.",
      data: null as any,
    }
  }
}

// Update flock
export async function updateFlock(id: number, flock: Partial<FlockInput>): Promise<ApiResponse<Flock>> {
  try {
    const endpoint = `/Flock/${id}`
    const url = IS_BROWSER ? buildApiUrl(endpoint) : `${DIRECT_API_BASE_URL}/api${endpoint}`
    console.log("[v0] Updating flock:", url)

    // Create the request body with ALL fields for a PUT request
    // Backend expects the complete object including FlockId
    const requestBody: any = {
      FlockId: id, // Always include the ID for PUT requests
      FarmId: flock.farmId || '',
      UserId: flock.userId || '',
      Name: flock.name || '',
      StartDate: flock.startDate || '',
      Breed: flock.breed || '',
      Quantity: flock.quantity ?? 0,
      Active: flock.active ?? true,
      HouseId: flock.houseId ?? null,
      BatchId: flock.batchId ?? 0,
      InactivationReason: flock.inactivationReason || '',
      OtherReason: flock.otherReason || '',
      Notes: flock.notes ?? '',
    }

    console.log("[v0] Flock update request body:", requestBody)

    const response = await fetch(url, {
      method: "PUT",
      headers: getAuthHeaders(),
      body: JSON.stringify(requestBody),
    })

    console.log("[v0] Flock update response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Flock update error:", errorText)
      return {
        success: false,
        message: "Failed to update flock",
        data: null as any,
      }
    }

    // Many APIs return 204 No Content for successful updates
    if (response.status === 204) {
      return {
        success: true,
        message: "Flock updated successfully",
        data: undefined as any,
      }
    }

    const contentType = response.headers.get("content-type") || ""
    if (!contentType.includes("application/json")) {
      // Treat non-JSON 200-range responses as success
      return {
        success: true,
        message: "Flock updated successfully",
        data: undefined as any,
      }
    }

    const data = await response.json()
    console.log("[v0] Updated flock data:", data)

    return {
      success: true,
      message: "Flock updated successfully",
      data: data as Flock,
    }
  } catch (error) {
    console.error("[v0] Flock update error:", error)
    return {
      success: false,
      message: "Failed to update flock",
      data: null as any,
    }
  }
}

// Delete flock
export async function deleteFlock(id: number, userId?: string, farmId?: string): Promise<ApiResponse> {
  try {
    // SECURITY: Validate required parameters before proceeding
    if (!userId || !farmId) {
      console.error("[v0] Security: Missing userId or farmId for flock deletion")
      return {
        success: false,
        message: "Authorization required. Please log in again.",
      }
    }
    
    if (!id || !Number.isFinite(id) || id <= 0) {
      console.error("[v0] Security: Invalid flock ID")
      return {
        success: false,
        message: "Invalid flock ID",
      }
    }
    
    const params = new URLSearchParams()
    params.append('userId', userId)
    params.append('farmId', farmId)
    
    const endpoint = `/Flock/${id}?${params.toString()}`
    const url = IS_BROWSER ? buildApiUrl(endpoint) : `${DIRECT_API_BASE_URL}/api${endpoint}`
    console.log("[v0] Deleting flock:", url)

    console.log("[v0] Delete request - id:", id, "userId:", userId, "farmId:", farmId)

    const response = await fetch(url, {
      method: "DELETE",
      headers: getAuthHeaders(),
    })

    console.log("[v0] Flock delete response status:", response.status)

    // Handle 204 No Content (successful delete) - no body to parse
    if (response.status === 204) {
      return {
        success: true,
        message: "Flock deleted successfully",
      }
    }

    // Handle 200 OK with potential body
    if (response.status === 200) {
      // Try to read body if present, but don't fail if empty
      try {
        const text = await response.text()
        if (text) {
          try {
            const data = JSON.parse(text)
            return {
              success: true,
              message: data.message || "Flock deleted successfully",
            }
          } catch {
            // Not JSON, that's fine
          }
        }
      } catch {
        // No body, that's fine
      }
      return {
        success: true,
        message: "Flock deleted successfully",
      }
    }

    // Handle error responses
    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Flock delete error:", errorText)
      return {
        success: false,
        message: errorText || "Failed to delete flock",
      }
    }

    return {
      success: true,
      message: "Flock deleted successfully",
    }
  } catch (error) {
    console.error("[v0] Flock delete error:", error)
    return {
      success: false,
      message: "Failed to delete flock",
    }
  }
}
