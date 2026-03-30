import { getAuthHeaders } from './config'

function normalizeApiBase(raw?: string, fallback = 'farmapi.techretainer.com') {
  const val = raw || fallback
  return val.startsWith('http://') || val.startsWith('https://') ? val : `https://${val}`
}

const API_BASE_URL = normalizeApiBase(process.env.NEXT_PUBLIC_API_BASE_URL)

export interface ProductionRecord {
  id: number
  farmId: string
  userId: string
  createdBy: string
  updatedBy: string
  ageInWeeks: number
  ageInDays: number
  date: string
  noOfBirds: number
  mortality: number
  noOfBirdsLeft: number
  feedKg: number
  medication: string
  production9AM: number
  production12PM: number
  production4PM: number
  brokenEggs: number
  totalProduction: number
  createdAt: string
  updatedAt: string
  flockId?: number | null
  flockName?: string
}

export interface ProductionRecordInput {
  farmId: string
  userId: string
  createdBy: string
  updatedBy: string
  ageInWeeks: number
  ageInDays: number
  date: string
  noOfBirds: number
  mortality: number
  noOfBirdsLeft: number
  feedKg: number
  medication: string
  production9AM: number
  production12PM: number
  production4PM: number
  brokenEggs: number
  totalProduction: number
  flockId?: number | null
}

// Mock data for development
const mockProductionRecords: ProductionRecord[] = [
  {
    id: 1,
    farmId: "farm-1",
    userId: "user-1",
    createdBy: "user-1",
    updatedBy: "user-1",
    ageInWeeks: 20,
    ageInDays: 140,
    date: new Date().toISOString(),
    noOfBirds: 100,
    mortality: 2,
    noOfBirdsLeft: 98,
    feedKg: 25.5,
    medication: "None",
    production9AM: 45,
    production12PM: 52,
    production4PM: 48,
    brokenEggs: 0,
    totalProduction: 145,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    flockId: null,
  },
  {
    id: 2,
    farmId: "farm-1",
    userId: "user-1",
    createdBy: "user-1",
    updatedBy: "user-1",
    ageInWeeks: 21,
    ageInDays: 147,
    date: new Date(Date.now() - 86400000).toISOString(), // Yesterday
    noOfBirds: 98,
    mortality: 1,
    noOfBirdsLeft: 97,
    feedKg: 24.0,
    medication: "Vitamin supplement",
    production9AM: 42,
    production12PM: 49,
    production4PM: 46,
    brokenEggs: 0,
    totalProduction: 137,
    createdAt: new Date(Date.now() - 86400000).toISOString(),
    updatedAt: new Date(Date.now() - 86400000).toISOString(),
    flockId: null,
  },
]

let nextRecordId = 3

export async function getProductionRecords(userId: string, farmId: string) {
  try {
    // Use proxy to avoid CORS issues
    const url = `/api/proxy/ProductionRecord?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    console.log("[v0] Fetching production records:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
    })

    console.log("[v0] Production records response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Production records fetch error:", errorText)
      
      // Return error instead of mock data
      return {
        success: false,
        message: `Failed to fetch production records: ${response.status} - ${errorText || 'Server error'}`,
        data: [],
      }
    }

    const contentType = response.headers.get("content-type")
    if (!contentType || !contentType.includes("application/json")) {
      console.error("[v0] Non-JSON response received")
      
      return {
        success: false,
        message: "Invalid response from server (non-JSON)",
        data: [],
      }
    }

    const data = await response.json()
    console.log("[v0] Production records data received:", data)

    return {
      success: true,
      message: "Production records fetched successfully",
      data: data as ProductionRecord[],
    }
  } catch (error) {
    console.error("[v0] Production records fetch error:", error)
    
    // Return error instead of mock data
    const errorMessage = error instanceof Error ? error.message : 'Network error'
    return {
      success: false,
      message: `Failed to connect to server: ${errorMessage}. Please check if the API is running and CORS is configured.`,
      data: [],
    }
  }
}

export async function getProductionRecord(id: number, userId: string, farmId: string) {
  try {
    // Use proxy to avoid CORS issues
    const url = `/api/proxy/ProductionRecord/${id}?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    console.log("[v0] Fetching production record:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Production record fetch error:", errorText)
      
      return {
        success: false,
        message: `Failed to fetch production record: ${response.status} - ${errorText || 'Server error'}`,
        data: null,
      }
    }

    const data = await response.json()
    return {
      success: true,
      message: "Production record fetched successfully",
      data: data as ProductionRecord,
    }
  } catch (error) {
    console.error("[v0] Production record fetch error:", error)
    
    const errorMessage = error instanceof Error ? error.message : 'Network error'
    return {
      success: false,
      message: `Failed to connect to server: ${errorMessage}`,
      data: null,
    }
  }
}

export async function createProductionRecord(record: ProductionRecordInput) {
  try {
    // Use proxy to avoid CORS issues
    const url = `/api/proxy/ProductionRecord`
    console.log("[v0] Creating production record:", url)

    // Only send fields expected by the SP (omit id/createdAt/updatedAt)
    const payload: any = {
      farmId: record.farmId,
      userId: record.userId,
      createdBy: record.createdBy,
      updatedBy: record.updatedBy,
      ageInWeeks: record.ageInWeeks,
      ageInDays: record.ageInDays,
      date: record.date,
      noOfBirds: record.noOfBirds,
      mortality: record.mortality,
      noOfBirdsLeft: record.noOfBirdsLeft,
      feedKg: record.feedKg,
      medication: record.medication,
      production9AM: record.production9AM,
      production12PM: record.production12PM,
      production4PM: record.production4PM,
      brokenEggs: record.brokenEggs ?? 0,
      totalProduction: record.totalProduction,
    }
    if (record.flockId !== undefined) payload.FlockId = record.flockId

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(payload),
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Production record create error:", errorText)
      // SECURITY: Removed mock data modification - no client-side data creation
      // All data operations must go through backend for proper validation and security
      return {
        success: false,
        message: errorText || "Failed to create production record. Backend validation required.",
      }
    }

    // Accept 204/No Content as success
    if (response.status === 204) {
      return { success: true, message: "Production record created successfully" }
    }

    // Some APIs return created entity; tolerate non-JSON
    const ct = response.headers.get("content-type") || ""
    if (!ct.includes("application/json")) {
      return { success: true, message: "Production record created successfully" }
    }

    await response.json().catch(() => null)
    return {
      success: true,
      message: "Production record created successfully",
    }
  } catch (error) {
    console.error("[v0] Production record create error:", error)
    // SECURITY: Removed mock data modification - no client-side data creation
    return {
      success: false,
      message: "Network error. Please try again.",
    }
  }
}

export async function updateProductionRecord(id: number, record: ProductionRecordInput) {
  try {
    // Use proxy to avoid CORS issues
    const url = `/api/proxy/ProductionRecord/${id}`
    console.log("[v0] Updating production record:", url)

    const payload: any = {
      id,
      farmId: record.farmId,
      userId: record.userId,
      createdBy: record.createdBy,
      updatedBy: record.updatedBy,
      ageInWeeks: record.ageInWeeks,
      ageInDays: record.ageInDays,
      date: record.date,
      noOfBirds: record.noOfBirds,
      mortality: record.mortality,
      noOfBirdsLeft: record.noOfBirdsLeft,
      feedKg: record.feedKg,
      medication: record.medication,
      production9AM: record.production9AM,
      production12PM: record.production12PM,
      production4PM: record.production4PM,
      brokenEggs: record.brokenEggs ?? 0,
      totalProduction: record.totalProduction,
    }
    if (record.flockId !== undefined) payload.FlockId = record.flockId

    const response = await fetch(url, {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(payload),
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Production record update error:", errorText)
      return {
        success: false,
        message: "Failed to update production record",
      }
    }

    if (response.status === 204) {
      return { success: true, message: "Production record updated successfully" }
    }

    const ct = response.headers.get("content-type") || ""
    if (!ct.includes("application/json")) {
      return { success: true, message: "Production record updated successfully" }
    }

    await response.json().catch(() => null)
    return {
      success: true,
      message: "Production record updated successfully",
    }
  } catch (error) {
    console.error("[v0] Production record update error:", error)
    return {
      success: false,
      message: "Failed to update production record",
    }
  }
}

export async function deleteProductionRecord(id: number, userId: string, farmId: string) {
  try {
    // SECURITY: Validate required parameters before proceeding
    if (!userId || !farmId) {
      console.error("[v0] Security: Missing userId or farmId for production record deletion")
      return {
        success: false,
        message: "Authorization required. Please log in again.",
      }
    }
    
    if (!id || !Number.isFinite(id) || id <= 0) {
      console.error("[v0] Security: Invalid production record ID")
      return {
        success: false,
        message: "Invalid production record ID",
      }
    }
    
    // Use proxy to avoid CORS issues
    const url = `/api/proxy/ProductionRecord/${id}?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    console.log("[v0] Deleting production record:", url)

    const response = await fetch(url, {
      method: "DELETE",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        ...getAuthHeaders(),
      },
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Production record delete error:", errorText)
      return {
        success: false,
        message: "Failed to delete production record",
      }
    }

    return {
      success: true,
      message: "Production record deleted successfully",
    }
  } catch (error) {
    console.error("[v0] Production record delete error:", error)
    return {
      success: false,
      message: "Failed to delete production record",
    }
  }
}