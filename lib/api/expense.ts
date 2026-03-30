// API utility functions for Expense management

import { getAuthHeaders } from './config'

function normalizeApiBase(raw?: string, fallback = 'farmapi.techretainer.com') {
  const val = raw || fallback
  return val.startsWith('http://') || val.startsWith('https://') ? val : `https://${val}`
}

const API_BASE_URL = normalizeApiBase(process.env.NEXT_PUBLIC_API_BASE_URL)

export interface Expense {
  farmId: string
  userId: string
  expenseId: number
  expenseDate: string
  category: string
  description: string
  amount: number
  paymentMethod: string
  flockId: number
  createdDate: string
  notes?: string
  paidTo?: string
}

export interface ExpenseInput {
  farmId: string
  userId: string
  expenseId?: number
  expenseDate: string
  category: string
  description: string
  amount: number
  paymentMethod: string
  flockId: number
  createdDate?: string
}

export interface ApiResponse<T = any> {
  success: boolean
  data?: T
  message?: string
  errors?: string[]
}

async function parseJsonLenient<T>(response: Response): Promise<T | null> {
  // Try JSON first
  try {
    return await response.clone().json()
  } catch {}
  // Fallback to text then JSON.parse
  try {
    const txt = await response.text()
    if (!txt) return null
    return JSON.parse(txt) as T
  } catch {}
  return null
}

// Mock data removed: all operations now rely strictly on the backend API

// Get all expenses
export async function getExpenses(userId?: string, farmId?: string): Promise<ApiResponse<Expense[]>> {
  try {
    const params = new URLSearchParams()
    if (userId) params.append('userId', userId)
    if (farmId) params.append('farmId', farmId)
    
    const url = `${API_BASE_URL}/api/Expense${params.toString() ? '?' + params.toString() : ''}`
    console.log("[v0] Fetching expenses:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: {
        // Accept both JSON and text/plain (Swagger shows text/plain)
        Accept: "application/json, text/plain;q=0.9, */*;q=0.8",
      },
    })

    console.log("[v0] Expenses response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      return { success: false, message: errorText || `Failed to fetch expenses (${response.status})` }
    }

    const data = await parseJsonLenient<any[]>(response)
    if (!data) return { success: false, message: "Failed to parse server response" }
    // Normalize payload to expected shape
    const normalized: Expense[] = data.map((x: any) => ({
      farmId: x.farmId ?? x.FarmId ?? "",
      userId: x.userId ?? x.UserId ?? "",
      expenseId: Number(x.expenseId ?? x.ExpenseId ?? x.id ?? x.Id ?? 0),
      expenseDate: x.expenseDate ?? x.ExpenseDate,
      category: x.category ?? x.Category ?? "",
      description: x.description ?? x.Description ?? "",
      amount: Number(x.amount ?? x.Amount ?? 0),
      paymentMethod: x.paymentMethod ?? x.PaymentMethod ?? "",
      flockId: Number(x.flockId ?? x.FlockId ?? 0),
      createdDate: x.createdDate ?? x.CreatedDate,
      notes: x.notes ?? x.Notes,
      paidTo: x.paidTo ?? x.PaidTo ?? x.supplier ?? x.Supplier,
    }))
    console.log("[v0] Expenses data received:", data)
    console.log("[v0] Number of expenses:", Array.isArray(data) ? data.length : 'not an array')

    if (!Array.isArray(data)) {
      return { success: false, message: "Unexpected data format from server" }
    }

    console.log("[v0] Filtering expenses for userId:", userId, "farmId:", farmId)
    console.log("[v0] Raw expense data sample:", data.slice(0, 2))

    return {
      success: true,
      message: "Expenses fetched successfully",
      data: normalized,
    }
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : "Failed to fetch expenses" }
  }
}

// Get single expense by ID
export async function getExpense(id: number, userId?: string, farmId?: string): Promise<ApiResponse<Expense | null>> {
  try {
    const params = new URLSearchParams()
    if (userId) params.append('userId', userId)
    if (farmId) params.append('farmId', farmId)
    
    const url = `${API_BASE_URL}/api/Expense/${id}${params.toString() ? '?' + params.toString() : ''}`
    console.log("[v0] Fetching expense:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json, text/plain;q=0.9, */*;q=0.8",
      },
    })

    console.log("[v0] Expense response status:", response.status)

    if (!response.ok) {
      if (response.status === 404) {
        // Gracefully handle not found: return null without noisy logs
        return {
          success: false,
          message: "Expense not found",
          data: null,
        }
      }

      const errorText = await response.text()

      // Check if it's the backend casting error for specific expense ID
      return {
        success: false,
        message: errorText || `Failed to fetch expense (${response.status})`,
        data: null,
      }
    }

    const raw = await parseJsonLenient<any>(response)
    if (!raw) return { success: false, message: "Failed to parse server response", data: null }
    const data: Expense = {
      farmId: raw.farmId ?? raw.FarmId ?? "",
      userId: raw.userId ?? raw.UserId ?? "",
      expenseId: Number(raw.expenseId ?? raw.ExpenseId ?? raw.id ?? raw.Id ?? 0),
      expenseDate: raw.expenseDate ?? raw.ExpenseDate,
      category: raw.category ?? raw.Category ?? "",
      description: raw.description ?? raw.Description ?? "",
      amount: Number(raw.amount ?? raw.Amount ?? 0),
      paymentMethod: raw.paymentMethod ?? raw.PaymentMethod ?? "",
      flockId: Number(raw.flockId ?? raw.FlockId ?? 0),
      createdDate: raw.createdDate ?? raw.CreatedDate,
      notes: raw.notes ?? raw.Notes,
      paidTo: raw.paidTo ?? raw.PaidTo ?? raw.supplier ?? raw.Supplier,
    }
    console.log("[v0] Expense data received:", data)

    return {
      success: true,
      message: "Expense fetched successfully",
      data,
    }
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : "Failed to fetch expense", data: null }
  }
}

// Get expenses by flock ID
export async function getExpensesByFlock(flockId: number, userId?: string, farmId?: string): Promise<ApiResponse<Expense[]>> {
  try {
    const params = new URLSearchParams()
    if (userId) params.append('userId', userId)
    if (farmId) params.append('farmId', farmId)
    
    const url = `${API_BASE_URL}/api/Expense/ByFlock/${flockId}${params.toString() ? '?' + params.toString() : ''}`
    console.log("[v0] Fetching expenses by flock:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json, text/plain;q=0.9, */*;q=0.8",
      },
    })

    console.log("[v0] Expenses by flock response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      return { success: false, message: errorText || `Failed to fetch expenses by flock (${response.status})` }
    }

    const data = await parseJsonLenient<Expense[]>(response)
    if (!data) return { success: false, message: "Failed to parse server response" }
    console.log("[v0] Expenses by flock data received:", data)

    if (!Array.isArray(data)) {
      return { success: false, message: "Unexpected data format" }
    }

    return {
      success: true,
      message: "Expenses by flock fetched successfully",
      data: data as Expense[],
    }
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : "Failed to fetch expenses by flock" }
  }
}

// Create new expense
export async function createExpense(expense: ExpenseInput): Promise<ApiResponse<Expense>> {
  try {
    const url = `${API_BASE_URL}/api/Expense`
    console.log("[v0] Creating expense:", url)
    console.log("[v0] Expense input:", expense)

    // Require provided context
    const farmId = expense.farmId
    const userId = expense.userId

    // Validate required fields
    if (!farmId) {
      console.error("[v0] FarmId is required but not provided. Expense:", expense)
      return {
        success: false,
        message: "Farm ID is required. Please log in again.",
        data: null as any,
      }
    }

    if (!userId) {
      console.error("[v0] userId is required but not provided. Expense:", expense)
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
      // Don't include expenseId - server will assign the ID
      // Don't include createdDate - server will set this
      expenseDate: expense.expenseDate,
      category: expense.category,
      description: expense.description,
      amount: expense.amount,
      paymentMethod: expense.paymentMethod,
      flockId: expense.flockId,
    }

    console.log("[v0] Expense request body:", requestBody)

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json, text/plain;q=0.9, */*;q=0.8",
      },
      body: JSON.stringify(requestBody),
    })

    console.log("[v0] Expense create response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Expense create error:", errorText)
      
      // Check if it's a backend data casting error but the record might have been created
      return { success: false, message: errorText || `Failed to create expense (${response.status})`, data: null as any }
    }

    const data = await parseJsonLenient<Expense>(response)
    if (!data) return { success: false, message: "Failed to parse server response", data: null as any }
    console.log("[v0] Created expense data:", data)

    return {
      success: true,
      message: "Expense created successfully",
      data: data as Expense,
    }
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : "Failed to create expense", data: null as any }
  }
}

// Update expense
export async function updateExpense(id: number, expense: Partial<ExpenseInput>): Promise<ApiResponse<Expense>> {
  try {
    const url = `${API_BASE_URL}/api/Expense/${id}`
    console.log("[v0] Updating expense:", url)

    // Create the request body with proper field names that match the API expectations
    const requestBody: any = {}
    if (expense.farmId) requestBody.farmId = expense.farmId
    if (expense.userId) requestBody.userId = expense.userId
    if (expense.expenseId !== undefined) requestBody.expenseId = expense.expenseId
    if (expense.expenseDate) requestBody.expenseDate = expense.expenseDate
    if (expense.category) requestBody.category = expense.category
    if (expense.description) requestBody.description = expense.description
    if (expense.amount !== undefined) requestBody.amount = expense.amount
    if (expense.paymentMethod) requestBody.paymentMethod = expense.paymentMethod
    if (expense.flockId !== undefined) requestBody.flockId = expense.flockId
    if (expense.createdDate) requestBody.createdDate = expense.createdDate

    console.log("[v0] Expense update request body:", requestBody)

    const response = await fetch(url, {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json, text/plain;q=0.9, */*;q=0.8",
      },
      body: JSON.stringify(requestBody),
    })

    console.log("[v0] Expense update response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      
      // Check if it's the backend casting error but the expense might have been updated
      return { success: false, message: errorText || `Failed to update expense (${response.status})`, data: null as any }
    }

    const data = await parseJsonLenient<Expense>(response)
    if (!data) return { success: false, message: "Failed to parse server response", data: null as any }
    console.log("[v0] Updated expense data:", data)

    return {
      success: true,
      message: "Expense updated successfully",
      data: data as Expense,
    }
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : "Failed to update expense", data: null as any }
  }
}

// Delete expense
export async function deleteExpense(id: number, userId?: string, farmId?: string): Promise<ApiResponse> {
  try {
    // SECURITY: Validate required parameters before proceeding
    if (!userId || !farmId) {
      console.error("[v0] Security: Missing userId or farmId for expense deletion")
      return {
        success: false,
        message: "Authorization required. Please log in again.",
      }
    }
    
    if (!Number.isFinite(id) || id <= 0) {
      return { success: false, message: "Invalid expense id" }
    }
    
    const params = new URLSearchParams()
    params.append('userId', userId)
    params.append('farmId', farmId)
    
    const url = `${API_BASE_URL}/api/Expense/${id}?${params.toString()}`
    console.log("[v0] Deleting expense:", url)

    const response = await fetch(url, {
      method: "DELETE",
      headers: {
        Accept: "application/json",
        ...getAuthHeaders(),
      },
    })

    console.log("[v0] Expense delete response status:", response.status)

    if (!response.ok) {
      // Treat 404 as already-deleted for idempotent UX
      if (response.status === 404) {
        return {
          success: true,
          message: "Expense already deleted",
        }
      }

      const errorText = await response.text()

      // Check if it's the backend casting error but the expense might have been deleted
      if (errorText.includes("InvalidCastException") || errorText.includes("expense record ID")) {
        console.warn("[v0] Backend casting error detected during delete, treating as deleted")
        return { success: true, message: "Expense deleted" }
      }
      
      console.error("[v0] Expense delete error:", errorText)
      return {
        success: false,
        message: "Failed to delete expense",
      }
    }

    return {
      success: true,
      message: "Expense deleted successfully",
    }
  } catch (error) {
    console.error("[v0] Expense delete error:", error)
    return {
      success: false,
      message: "Failed to delete expense",
    }
  }
}
