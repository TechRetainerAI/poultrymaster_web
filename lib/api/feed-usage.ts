function normalizeApiBase(raw?: string, fallback = 'farmapi.techretainer.com') {
  const val = raw || fallback
  return val.startsWith('http://') || val.startsWith('https://') ? val : `https://${val}`
}

const API_BASE_URL = normalizeApiBase(process.env.NEXT_PUBLIC_API_BASE_URL)

export interface FeedUsage {
  farmId: string
  userId: string
  feedUsageId: number
  flockId: number
  usageDate: string
  feedType: string
  quantityKg: number
}

export interface FeedUsageInput {
  farmId: string
  userId: string
  flockId: number
  usageDate: string
  feedType: string
  quantityKg: number
}

// Mock data for development
const mockFeedUsages: FeedUsage[] = [
  {
    farmId: "farm-1",
    userId: "user-1",
    feedUsageId: 1,
    flockId: 1,
    usageDate: new Date().toISOString(),
    feedType: "Starter Feed",
    quantityKg: 15.5,
  },
  {
    farmId: "farm-1",
    userId: "user-1",
    feedUsageId: 2,
    flockId: 2,
    usageDate: new Date(Date.now() - 86400000).toISOString(), // Yesterday
    feedType: "Layer Feed",
    quantityKg: 22.0,
  },
  {
    farmId: "farm-1",
    userId: "user-1",
    feedUsageId: 3,
    flockId: 1,
    usageDate: new Date(Date.now() - 172800000).toISOString(), // 2 days ago
    feedType: "Grower Feed",
    quantityKg: 18.5,
  },
]

let nextFeedUsageId = 4

export async function getFeedUsages(userId: string, farmId: string) {
  try {
    // API expects farmId (lowercase) in query parameters
    const url = `${API_BASE_URL}/api/FeedUsage?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    console.log("[v0] Fetching feed usages:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json",
      },
    })

    console.log("[v0] Feed usages response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Feed usages fetch error:", errorText)
      // Mock data fallback
      console.warn("[v0] Using mock data for feed usages due to API error.")
      return {
        success: true,
        message: "Using mock data",
        data: [
          { farmId, userId, feedUsageId: 1, flockId: 101, usageDate: new Date().toISOString(), feedType: "Starter", quantityKg: 25 },
          { farmId, userId, feedUsageId: 2, flockId: 102, usageDate: new Date(Date.now() - 86400000).toISOString(), feedType: "Grower", quantityKg: 30 },
          { farmId, userId, feedUsageId: 3, flockId: 101, usageDate: new Date(Date.now() - 2 * 86400000).toISOString(), feedType: "Layer", quantityKg: 28 },
        ],
      }
    }

    const contentType = response.headers.get("content-type")
    if (!contentType || !contentType.includes("application/json")) {
      console.error("[v0] Non-JSON response received")
      console.warn("[v0] Using mock data for feed usages due to non-JSON response.")
      return {
        success: true,
        message: "Using mock data",
        data: [
          { farmId, userId, feedUsageId: 1, flockId: 101, usageDate: new Date().toISOString(), feedType: "Starter", quantityKg: 25 },
          { farmId, userId, feedUsageId: 2, flockId: 102, usageDate: new Date(Date.now() - 86400000).toISOString(), feedType: "Grower", quantityKg: 30 },
          { farmId, userId, feedUsageId: 3, flockId: 101, usageDate: new Date(Date.now() - 2 * 86400000).toISOString(), feedType: "Layer", quantityKg: 28 },
        ],
      }
    }

    const data = await response.json()
    console.log("[v0] Feed usages data received:", data)

    if (!Array.isArray(data)) {
      console.error("[v0] Expected array but got:", typeof data)
      console.warn("[v0] Using mock data for feed usages due to unexpected data format.")
      return {
        success: true,
        message: "Using mock data",
        data: [
          { farmId, userId, feedUsageId: 1, flockId: 101, usageDate: new Date().toISOString(), feedType: "Starter", quantityKg: 25 },
          { farmId, userId, feedUsageId: 2, flockId: 102, usageDate: new Date(Date.now() - 86400000).toISOString(), feedType: "Grower", quantityKg: 30 },
          { farmId, userId, feedUsageId: 3, flockId: 101, usageDate: new Date(Date.now() - 2 * 86400000).toISOString(), feedType: "Layer", quantityKg: 28 },
        ],
      }
    }

    return {
      success: true,
      message: "Feed usages fetched successfully",
      data: data as FeedUsage[],
    }
  } catch (error) {
    console.error("[v0] Feed usages fetch error:", error)
    console.warn("[v0] API not available, using mock data for feed usages.")
    
    // Return mock data with farmId and userId
    return {
      success: true,
      message: "Feed usages loaded (API unavailable - using sample data)",
      data: mockFeedUsages.map(usage => ({ ...usage, farmId, userId })),
    }
  }
}

export async function getFeedUsage(id: number, userId: string, farmId: string) {
  try {
    // API expects farmId (lowercase) in query parameters
    const url = `${API_BASE_URL}/api/FeedUsage/${id}?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    console.log("[v0] Fetching feed usage:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json",
      },
    })

    console.log("[v0] Feed usage response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Feed usage fetch error:", errorText)
      // Mock data fallback
      console.warn("[v0] Using mock data for feed usage due to API error.")
      const mockUsage = mockFeedUsages.find(u => u.feedUsageId === id)
      if (mockUsage) {
        return {
          success: true,
          message: "Using mock data",
          data: { ...mockUsage, farmId, userId },
        }
      }
      return {
        success: false,
        message: "Feed usage not found",
        data: null,
      }
    }

    const contentType = response.headers.get("content-type")
    if (!contentType || !contentType.includes("application/json")) {
      console.error("[v0] Non-JSON response received")
      console.warn("[v0] Using mock data for feed usage due to non-JSON response.")
      const mockUsage = mockFeedUsages.find(u => u.feedUsageId === id)
      if (mockUsage) {
        return {
          success: true,
          message: "Using mock data",
          data: { ...mockUsage, farmId, userId },
        }
      }
      return {
        success: false,
        message: "Feed usage not found",
        data: null,
      }
    }

    const data = await response.json()
    console.log("[v0] Feed usage data received:", data)

    return {
      success: true,
      message: "Feed usage fetched successfully",
      data: data as FeedUsage,
    }
  } catch (error) {
    console.error("[v0] Feed usage fetch error:", error)
    console.warn("[v0] Using mock data for feed usage due to error.")
    const mockUsage = mockFeedUsages.find(u => u.feedUsageId === id)
    if (mockUsage) {
      return {
        success: true,
        message: "Using mock data",
        data: { ...mockUsage, farmId, userId },
      }
    }
    return {
      success: false,
      message: "Feed usage not found",
      data: null,
    }
  }
}

export async function createFeedUsage(usage: FeedUsageInput) {
  try {
    console.log("[v0] Usage input:", usage)

    // Try to get userId and farmId from localStorage as fallback
    let farmId = usage.farmId
    let userId = usage.userId
    
    console.log("[v0] ===== INITIAL CHECK =====")
    console.log("[v0] Initial farmId:", farmId, "| Type:", typeof farmId, "| Length:", farmId?.length)
    console.log("[v0] Initial userId:", userId, "| Type:", typeof userId, "| Length:", userId?.length)
    console.log("[v0] ============================")
    
    if (!farmId && typeof window !== "undefined") {
      farmId = localStorage.getItem("farmId") || ""
      console.log("[v0] Got farmId from localStorage:", farmId)
    }
    
    if (!userId && typeof window !== "undefined") {
      userId = localStorage.getItem("userId") || ""
      console.log("[v0] Got userId from localStorage:", userId)
    }
    
    console.log("[v0] ===== AFTER LOCALSTORAGE =====")
    console.log("[v0] Final farmId:", farmId, "| Is empty?:", farmId === "")
    console.log("[v0] Final userId:", userId, "| Is empty?:", userId === "")
    console.log("[v0] ====================================")
    
    // Debug: Check all localStorage values
    if (typeof window !== "undefined") {
      console.log("[v0] All localStorage values:")
      console.log("[v0] - farmId:", localStorage.getItem("farmId"))
      console.log("[v0] - userId:", localStorage.getItem("userId"))
      console.log("[v0] - username:", localStorage.getItem("username"))
      console.log("[v0] - farmName:", localStorage.getItem("farmName"))
      
      // SECURITY: Removed test value injection
      // Never set test values in production - this is a security risk
      // If farmId/userId is missing, fail gracefully
    }

    // Validate required fields
    if (!farmId) {
      console.error("[v0] FarmId is required but not provided. Usage:", usage)
      return {
        success: false,
        message: "Farm ID is required. Please log in again.",
      }
    }

    if (!userId) {
      console.error("[v0] userId is required but not provided. Usage:", usage)
      return {
        success: false,
        message: "User ID is required. Please log in again.",
      }
    }

    // Validate that farmId and userId are not empty strings
    if (!farmId || farmId.trim() === "") {
      console.error("[v0] FarmId is empty string after all checks")
      return {
        success: false,
        message: "Farm ID is empty. Please log in again.",
      }
    }

    if (!userId || userId.trim() === "") {
      console.error("[v0] UserId is empty string after all checks")
      return {
        success: false,
        message: "User ID is empty. Please log in again.",
      }
    }

    // The API error shows "FarmId" (capital F) is required in the body
    // Use PascalCase for all fields to match .NET conventions
    const requestBody = {
      FarmId: farmId,              // PascalCase - API requires this
      UserId: userId,              // PascalCase
      FeedUsageId: 0,              // Always 0 for new records
      FlockId: usage.flockId,
      UsageDate: usage.usageDate,
      FeedType: usage.feedType,
      QuantityKg: usage.quantityKg,
    }

    const url = `${API_BASE_URL}/api/FeedUsage`
    console.log("[v0] Creating feed usage:", url)
    console.log("[v0] Final farmId value being sent:", farmId)
    console.log("[v0] Final userId value being sent:", userId)
    console.log("[v0] Feed usage request body:", JSON.stringify(requestBody, null, 2))

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(requestBody),
    })

    console.log("[v0] ===== REQUEST SENT =====")
    console.log("[v0] URL:", url)
    console.log("[v0] Body JSON:", JSON.stringify(requestBody))
    console.log("[v0] FarmId value:", requestBody.FarmId)
    console.log("[v0] UserId value:", requestBody.UserId)
    console.log("[v0] ========================")
    
    // Show alert to user so they can see what's being sent
    if (!requestBody.FarmId || requestBody.FarmId === "") {
      alert("DEBUG: FarmId is empty! Value: '" + requestBody.FarmId + "'\nPlease check if you are logged in.")
      console.error("[v0] CRITICAL: FarmId is empty in request body!")
    }
    
    console.log("[v0] Feed usage create response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Feed usage create error:", errorText)
      
      // Parse error for better message
      try {
        const errorData = JSON.parse(errorText)
        const errorMessages = errorData.errors 
          ? Object.values(errorData.errors).flat().join(', ')
          : errorData.title || 'Failed to create feed usage'
        
        return {
          success: false,
          message: `API Error: ${errorMessages}`,
        }
      } catch (e) {
        return {
          success: false,
          message: `API Error: ${errorText}`,
        }
      }
    }

    const contentType = response.headers.get("content-type")
    if (!contentType || !contentType.includes("application/json")) {
      console.error("[v0] Non-JSON response received")
      return {
        success: false,
        message: "API returned non-JSON response",
      }
    }

    const data = await response.json()
    console.log("[v0] Created feed usage data:", data)

    return {
      success: true,
      message: "Feed usage created successfully",
      data: data as FeedUsage,
    }
  } catch (error) {
    console.error("[v0] Feed usage create exception:", error)
    return {
      success: false,
      message: `Network error: ${error instanceof Error ? error.message : 'Unknown error'}`,
    }
  }
}

export async function updateFeedUsage(id: number, usage: Partial<FeedUsageInput>) {
  try {
    const url = `${API_BASE_URL}/api/FeedUsage/${id}`
    console.log("[v0] Updating feed usage:", url)

    // Use PascalCase to match the API expectations (same as POST)
    const requestBody: any = {}
    if (usage.userId) requestBody.UserId = usage.userId
    requestBody.FeedUsageId = id  // Use the id parameter
    if (usage.flockId !== undefined) requestBody.FlockId = usage.flockId
    if (usage.usageDate) requestBody.UsageDate = usage.usageDate
    if (usage.feedType) requestBody.FeedType = usage.feedType
    if (usage.quantityKg !== undefined) requestBody.QuantityKg = usage.quantityKg

    console.log("[v0] Feed usage update request body:", requestBody)

    const response = await fetch(url, {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(requestBody),
    })

    console.log("[v0] Feed usage update response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Feed usage update error:", errorText)
      return {
        success: false,
        message: "Failed to update feed usage",
        data: null,
      }
    }

    const contentType = response.headers.get("content-type")
    if (!contentType || !contentType.includes("application/json")) {
      console.error("[v0] Non-JSON response received")
      return {
        success: false,
        message: "Invalid response format",
        data: null,
      }
    }

    const data = await response.json()
    console.log("[v0] Updated feed usage data:", data)

    return {
      success: true,
      message: "Feed usage updated successfully",
      data: data as FeedUsage,
    }
  } catch (error) {
    console.error("[v0] Feed usage update error:", error)
    return {
      success: false,
      message: "Failed to update feed usage",
      data: null,
    }
  }
}

export async function deleteFeedUsage(id: number, userId: string, farmId: string) {
  try {
    // SECURITY: Validate required parameters before proceeding
    if (!userId || !farmId) {
      console.error("[v0] Security: Missing userId or farmId for feed usage deletion");
      return {
        success: false,
        message: "Authorization required. Please log in again.",
      };
    }
    
    if (!id || !Number.isFinite(id) || id <= 0) {
      console.error("[v0] Security: Invalid feed usage ID");
      return {
        success: false,
        message: "Invalid feed usage ID",
      };
    }
    
    // API expects farmId (lowercase) in query parameters
    const url = `${API_BASE_URL}/api/FeedUsage/${id}?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    console.log("[v0] Deleting feed usage:", url)

    const response = await fetch(url, {
      method: "DELETE",
      headers: {
        Accept: "application/json",
        ...getAuthHeaders(),
      },
    })

    console.log("[v0] Feed usage delete response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Feed usage delete error:", errorText)
      return {
        success: false,
        message: "Failed to delete feed usage",
      }
    }

    return {
      success: true,
      message: "Feed usage deleted successfully",
    }
  } catch (error) {
    console.error("[v0] Feed usage delete error:", error)
    return {
      success: false,
      message: "Failed to delete feed usage",
    }
  }
}