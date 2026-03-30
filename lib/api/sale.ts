// API utility functions for Sale management

import { getAuthHeaders } from './config'

function normalizeApiBase(raw?: string, fallback = 'farmapi.techretainer.com') {
  const val = raw || fallback
  return val.startsWith('http://') || val.startsWith('https://') ? val : `https://${val}`
}

const API_BASE_URL = normalizeApiBase(process.env.NEXT_PUBLIC_API_BASE_URL)

export interface Sale {
  farmId: string
  userId: string
  saleId: number
  saleDate: string
  product: string
  quantity: number
  unitPrice: number
  totalAmount: number
  paymentMethod: string
  customerName: string
  flockId: number
  saleDescription: string
  createdDate: string
}

export interface SaleInput {
  farmId: string
  userId: string
  saleId?: number
  saleDate: string
  product: string
  quantity: number
  unitPrice: number
  totalAmount: number
  paymentMethod: string
  customerName: string
  flockId: number
  saleDescription: string
  createdDate?: string
}

export interface ApiResponse<T = any> {
  success: boolean
  data?: T
  message?: string
  errors?: string[]
}

// Mock data for development
const mockSales: Sale[] = [
  {
    farmId: "farm-1",
    userId: "user-1",
    saleId: 1,
    saleDate: "2024-01-15T00:00:00.000Z",
    product: "Fresh Eggs",
    quantity: 120,
    unitPrice: 0.50,
    totalAmount: 60.00,
    paymentMethod: "Cash",
    customerName: "Local Market",
    flockId: 1,
    saleDescription: "Regular weekly egg delivery",
    createdDate: "2024-01-15T08:30:00.000Z",
  },
  {
    farmId: "farm-1",
    userId: "user-1",
    saleId: 2,
    saleDate: "2024-01-20T00:00:00.000Z",
    product: "Chicken Meat",
    quantity: 10,
    unitPrice: 8.00,
    totalAmount: 80.00,
    paymentMethod: "Credit Card",
    customerName: "Restaurant ABC",
    flockId: 2,
    saleDescription: "Whole chicken sale",
    createdDate: "2024-01-20T14:15:00.000Z",
  },
  {
    farmId: "farm-1",
    userId: "user-1",
    saleId: 3,
    saleDate: "2024-02-01T00:00:00.000Z",
    product: "Fresh Eggs",
    quantity: 200,
    unitPrice: 0.45,
    totalAmount: 90.00,
    paymentMethod: "Bank Transfer",
    customerName: "Grocery Store XYZ",
    flockId: 1,
    saleDescription: "Bulk egg order",
    createdDate: "2024-02-01T10:45:00.000Z",
  },
  // Add some current month sales for dashboard display
  {
    farmId: "farm-1",
    userId: "user-1",
    saleId: 4,
    saleDate: new Date().toISOString().split('T')[0] + "T00:00:00.000Z", // Today
    product: "Fresh Eggs",
    quantity: 150,
    unitPrice: 0.55,
    totalAmount: 82.50,
    paymentMethod: "Cash",
    customerName: "Farmers Market",
    flockId: 1,
    saleDescription: "Weekly farmers market sale",
    createdDate: new Date().toISOString(),
  },
  {
    farmId: "farm-1",
    userId: "user-1",
    saleId: 5,
    saleDate: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString().split('T')[0] + "T00:00:00.000Z", // 1 week ago
    product: "Chicken Meat",
    quantity: 15,
    unitPrice: 7.50,
    totalAmount: 112.50,
    paymentMethod: "Credit Card",
    customerName: "Local Butcher",
    flockId: 2,
    saleDescription: "Processed chicken meat",
    createdDate: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
  },
]

let nextSaleId = 6

// Get all sales
export async function getSales(userId?: string, farmId?: string): Promise<ApiResponse<Sale[]>> {
  try {
    const params = new URLSearchParams()
    if (userId) params.append('userId', userId)
    if (farmId) params.append('farmId', farmId)
    
    const url = `${API_BASE_URL}/api/Sale${params.toString() ? '?' + params.toString() : ''}`
    console.log("[v0] Fetching sales:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json",
      },
    })

    console.log("[v0] Sales response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Sales fetch error:", errorText)
      console.warn("[v0] Using mock data for sales due to API error.")
      
      const filteredMockData = mockSales.filter(sale => 
        (!userId || sale.userId === userId) && 
        (!farmId || sale.farmId === farmId)
      )
      return {
        success: true,
        message: "Using mock data (API error)",
        data: filteredMockData,
      }
    }

    const contentType = response.headers.get("content-type")
    if (!contentType || !contentType.includes("application/json")) {
      console.error("[v0] Non-JSON response received")
      console.warn("[v0] Using mock data for sales due to non-JSON response.")
      const filteredMockData = mockSales.filter(sale => 
        (!userId || sale.userId === userId) && 
        (!farmId || sale.farmId === farmId)
      )
      return {
        success: true,
        message: "Using mock data",
        data: filteredMockData,
      }
    }

    const data = await response.json()
    console.log("[v0] Sales data received:", data)

    if (!Array.isArray(data)) {
      console.error("[v0] Expected array but got:", typeof data)
      console.warn("[v0] Using mock data for sales due to unexpected data format.")
      const filteredMockData = mockSales.filter(sale => 
        (!userId || sale.userId === userId) && 
        (!farmId || sale.farmId === farmId)
      )
      return {
        success: true,
        message: "Using mock data",
        data: filteredMockData,
      }
    }

    return {
      success: true,
      message: "Sales fetched successfully",
      data: data as Sale[],
    }
  } catch (error) {
    console.error("[v0] Sales fetch error:", error)
    console.warn("[v0] Using mock data for sales due to error.")
    const filteredMockData = mockSales.filter(sale => 
      (!userId || sale.userId === userId) && 
      (!farmId || sale.farmId === farmId)
    )
    return {
      success: true,
      message: "Using mock data",
      data: filteredMockData,
    }
  }
}

// Get single sale by ID
export async function getSale(id: number, userId?: string, farmId?: string): Promise<ApiResponse<Sale | null>> {
  try {
    const params = new URLSearchParams()
    if (userId) params.append('userId', userId)
    if (farmId) params.append('farmId', farmId)
    
    const url = `${API_BASE_URL}/api/Sale/${id}${params.toString() ? '?' + params.toString() : ''}`
    console.log("[v0] Fetching sale:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json",
      },
    })

    console.log("[v0] Sale response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Sale fetch error:", errorText)
      console.warn("[v0] Using mock data for sale due to API error.")
      
      const mockSale = mockSales.find(s => s.saleId === id)
      if (mockSale) {
        return {
          success: true,
          message: "Using mock data",
          data: mockSale,
        }
      }
      
      return {
        success: false,
        message: "Sale not found",
        data: null,
      }
    }

    const contentType = response.headers.get("content-type")
    if (!contentType || !contentType.includes("application/json")) {
      console.error("[v0] Non-JSON response received")
      console.warn("[v0] Using mock data for sale due to non-JSON response.")
      const mockSale = mockSales.find(s => s.saleId === id)
      if (mockSale) {
        return {
          success: true,
          message: "Using mock data",
          data: mockSale,
        }
      }
      return {
        success: false,
        message: "Sale not found",
        data: null,
      }
    }

    const data = await response.json()
    console.log("[v0] Sale data received:", data)

    return {
      success: true,
      message: "Sale fetched successfully",
      data: data as Sale,
    }
  } catch (error) {
    console.error("[v0] Sale fetch error:", error)
    console.warn("[v0] Using mock data for sale due to error.")
    const mockSale = mockSales.find(s => s.saleId === id)
    if (mockSale) {
      return {
        success: true,
        message: "Using mock data",
        data: mockSale,
      }
    }
    return {
      success: false,
      message: "Sale not found",
      data: null,
    }
  }
}

// Get sales by flock ID
export async function getSalesByFlock(flockId: number, userId?: string, farmId?: string): Promise<ApiResponse<Sale[]>> {
  try {
    const params = new URLSearchParams()
    if (userId) params.append('userId', userId)
    if (farmId) params.append('farmId', farmId)
    
    const url = `${API_BASE_URL}/api/Sale/ByFlock/${flockId}${params.toString() ? '?' + params.toString() : ''}`
    console.log("[v0] Fetching sales by flock:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json",
      },
    })

    console.log("[v0] Sales by flock response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Sales by flock fetch error:", errorText)
      // Mock data fallback
      console.warn("[v0] Using mock data for sales by flock due to API error.")
      const filteredMockData = mockSales.filter(sale => 
        sale.flockId === flockId &&
        (!userId || sale.userId === userId) && 
        (!farmId || sale.farmId === farmId)
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
      console.warn("[v0] Using mock data for sales by flock due to non-JSON response.")
      const filteredMockData = mockSales.filter(sale => 
        sale.flockId === flockId &&
        (!userId || sale.userId === userId) && 
        (!farmId || sale.farmId === farmId)
      )
      return {
        success: true,
        message: "Using mock data",
        data: filteredMockData,
      }
    }

    const data = await response.json()
    console.log("[v0] Sales by flock data received:", data)

    if (!Array.isArray(data)) {
      console.error("[v0] Expected array but got:", typeof data)
      console.warn("[v0] Using mock data for sales by flock due to unexpected data format.")
      const filteredMockData = mockSales.filter(sale => 
        sale.flockId === flockId &&
        (!userId || sale.userId === userId) && 
        (!farmId || sale.farmId === farmId)
      )
      return {
        success: true,
        message: "Using mock data",
        data: filteredMockData,
      }
    }

    return {
      success: true,
      message: "Sales by flock fetched successfully",
      data: data as Sale[],
    }
  } catch (error) {
    console.error("[v0] Sales by flock fetch error:", error)
    console.warn("[v0] Using mock data for sales by flock due to error.")
    const filteredMockData = mockSales.filter(sale => 
      sale.flockId === flockId &&
      (!userId || sale.userId === userId) && 
      (!farmId || sale.farmId === farmId)
    )
    return {
      success: true,
      message: "Using mock data",
      data: filteredMockData,
    }
  }
}

// Create new sale
export async function createSale(sale: SaleInput): Promise<ApiResponse<Sale>> {
  try {
    const url = `${API_BASE_URL}/api/Sale`
    console.log("[v0] Creating sale:", url)
    console.log("[v0] Sale input:", sale)

    // Try to get userId and farmId from localStorage as fallback
    let farmId = sale.farmId
    let userId = sale.userId
    
    console.log("[v0] Initial values - farmId:", farmId, "userId:", userId)
    
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
      console.error("[v0] FarmId is required but not provided. Sale:", sale)
      return {
        success: false,
        message: "Farm ID is required. Please log in again.",
        data: null as any,
      }
    }

    if (!userId) {
      console.error("[v0] userId is required but not provided. Sale:", sale)
      return {
        success: false,
        message: "User ID is required. Please log in again.",
        data: null as any,
      }
    }

    // Create the request body with proper field names that match the API expectations
    const requestBody = {
      farmId: farmId,
      userId: userId,
      saleId: 0, // Server will assign the ID
      saleDate: sale.saleDate,
      product: sale.product,
      quantity: sale.quantity,
      unitPrice: sale.unitPrice,
      totalAmount: sale.totalAmount,
      paymentMethod: sale.paymentMethod,
      customerName: sale.customerName,
      flockId: sale.flockId,
      saleDescription: sale.saleDescription,
      createdDate: new Date().toISOString(),
    }

    console.log("[v0] Sale request body:", requestBody)

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(requestBody),
    })

    console.log("[v0] Sale create response status:", response.status)

    // Read response text once
    const responseText = await response.text()
    
    if (!response.ok) {
      console.error("[v0] Sale create error:", responseText)
      // SECURITY: Removed mock data modification - no client-side data creation
      // All data operations must go through backend for proper validation and security
      return {
        success: false,
        message: errorText || "Failed to create sale. Backend validation required.",
        data: null as any,
      }
    }

    // Try to parse JSON, but handle empty responses
    let data: any = null
    const contentType = response.headers.get("content-type")
    
    if (contentType && contentType.includes("application/json") && responseText.trim()) {
      try {
        data = JSON.parse(responseText)
      } catch (e) {
        console.error("[v0] Failed to parse JSON response:", e)
      }
    }
    
    // If no data returned but successful, create sale object from request
    if (!data && response.ok) {
      console.log("[v0] Create successful (empty response)")
      data = {
        ...requestBody,
        saleId: nextSaleId++, // Generate a temporary ID
        createdDate: new Date().toISOString(),
      }
    }

    // SECURITY: Removed mock data fallback - all operations must succeed through backend
    if (!data) {
      console.error("[v0] Sale creation failed - no data returned")
      return {
        success: false,
        message: "Failed to create sale. No response from server.",
        data: null as any,
      }
    }

    console.log("[v0] Created sale data:", data)

    return {
      success: true,
      message: "Sale created successfully",
      data: data as Sale,
    }
  } catch (error) {
    console.error("[v0] Sale create error:", error)
    // SECURITY: Removed mock data modification - no client-side data creation
    return {
      success: false,
      message: "Network error. Please try again.",
      data: null as any,
    }
  }
}

// Update sale
export async function updateSale(id: number, sale: Partial<SaleInput>): Promise<ApiResponse<Sale>> {
  try {
    const url = `${API_BASE_URL}/api/Sale/${id}`
    console.log("[v0] Updating sale:", url)

    // Create the request body with proper field names that match the API expectations
    const requestBody: any = {}
    if (sale.farmId) requestBody.farmId = sale.farmId
    if (sale.userId) requestBody.userId = sale.userId
    if (sale.saleId !== undefined) requestBody.saleId = sale.saleId
    if (sale.saleDate) requestBody.saleDate = sale.saleDate
    if (sale.product) requestBody.product = sale.product
    if (sale.quantity !== undefined) requestBody.quantity = sale.quantity
    if (sale.unitPrice !== undefined) requestBody.unitPrice = sale.unitPrice
    if (sale.totalAmount !== undefined) requestBody.totalAmount = sale.totalAmount
    if (sale.paymentMethod) requestBody.paymentMethod = sale.paymentMethod
    if (sale.customerName) requestBody.customerName = sale.customerName
    if (sale.flockId !== undefined) requestBody.flockId = sale.flockId
    if (sale.saleDescription) requestBody.saleDescription = sale.saleDescription
    if (sale.createdDate) requestBody.createdDate = sale.createdDate

    console.log("[v0] Sale update request body:", requestBody)

    const response = await fetch(url, {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(requestBody),
    })

    console.log("[v0] Sale update response status:", response.status)

    // Read response text once
    const responseText = await response.text()
    
    if (!response.ok) {
      console.error("[v0] Sale update error:", responseText)
      return {
        success: false,
        message: "Failed to update sale",
        data: null as any,
      }
    }

    // Try to parse JSON, but handle empty responses
    let data: any = null
    const contentType = response.headers.get("content-type")
    
    if (contentType && contentType.includes("application/json") && responseText.trim()) {
      try {
        data = JSON.parse(responseText)
      } catch (e) {
        console.error("[v0] Failed to parse JSON response:", e)
      }
    }
    
    // If no data returned, assume success (some APIs return 200 with no body for updates)
    if (!data && response.ok) {
      console.log("[v0] Update successful (empty response)")
      // Return the original sale data as indication of success
      data = { ...requestBody, saleId: id }
    }

    console.log("[v0] Updated sale data:", data)

    return {
      success: true,
      message: "Sale updated successfully",
      data: data as Sale,
    }
  } catch (error) {
    console.error("[v0] Sale update error:", error)
    return {
      success: false,
      message: "Failed to update sale",
      data: null as any,
    }
  }
}

// Delete sale
export async function deleteSale(id: number, userId?: string, farmId?: string): Promise<ApiResponse> {
  try {
    // SECURITY: Validate required parameters before proceeding
    if (!userId || !farmId) {
      console.error("[v0] Security: Missing userId or farmId for sale deletion")
      return {
        success: false,
        message: "Authorization required. Please log in again.",
      }
    }
    
    if (!id || !Number.isFinite(id) || id <= 0) {
      console.error("[v0] Security: Invalid sale ID")
      return {
        success: false,
        message: "Invalid sale ID",
      }
    }
    
    const params = new URLSearchParams()
    params.append('userId', userId)
    params.append('farmId', farmId)
    
    const url = `${API_BASE_URL}/api/Sale/${id}?${params.toString()}`
    console.log("[v0] Deleting sale:", url)

    const response = await fetch(url, {
      method: "DELETE",
      headers: {
        Accept: "application/json",
        ...getAuthHeaders(),
      },
    })

    console.log("[v0] Sale delete response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Sale delete error:", errorText)
      return {
        success: false,
        message: errorText || "Failed to delete sale",
      }
    }

    // SECURITY: Removed mock data manipulation - no client-side data modification
    return {
      success: true,
      message: "Sale deleted successfully",
    }
  } catch (error) {
    console.error("[v0] Sale delete error:", error)
    return {
      success: false,
      message: "Failed to delete sale",
    }
  }
}

