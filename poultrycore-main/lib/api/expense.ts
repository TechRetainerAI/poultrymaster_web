// API utility functions for Expense management

import { farmApiUrl, getAuthHeaders } from "./config"
import { derivePaymentStatus } from "@/lib/expenses/payment-status"

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
  /** Optional cash account this expense is paid from. */
  poultryCashAccountId?: number | null
  createdDate: string
  notes?: string
  paidTo?: string
  /** Receipt bytes stored on row; use GET …/attachment or /api/expense-image */
  hasAttachmentImage?: boolean

  // --- payment state (migration 238) ---------------------------------------
  /** The supplier this is owed to. `paidTo` stays the display name; this is what
   * makes the row a payable, so an unpaid expense without it never reaches
   * Supplier Balances. */
  supplierId?: number | null
  supplierName?: string | null
  /** Always resolved by the API: a fully paid expense reports amountPaid ===
   * amount, never null. */
  amountPaid: number
  /** amount − amountPaid, never negative. */
  balance: number
  paymentStatus: ExpensePaymentStatus
  dueDate?: string | null
  /** Which workflow created the row. Null means entered by hand. */
  sourceType?: string | null
  sourceId?: number | null
}

/** Generated in SQL from the amounts, so it cannot disagree with them. */
export type ExpensePaymentStatus = "Paid" | "PartiallyPaid" | "Unpaid" | "NonCash"

export interface ExpenseInput {
  farmId: string
  userId: string
  expenseId?: number
  expenseDate: string
  category: string
  description: string
  amount: number
  paymentMethod: string
  /** null = farm-wide / all-flocks expense (not attributed to one flock). */
  flockId: number | null
  /** Optional cash account to pay this expense from (posts a cash-out). */
  poultryCashAccountId?: number | null
  createdDate?: string
  supplier?: string
  /** The supplier this expense is owed to. Required for an unpaid expense to
   * appear on Supplier Balances. */
  supplierId?: number | null
  /** Cash paid so far. Omit or send null to mean "paid in full" — that is the
   * shape every expense written before migration 238 has, and sending 0 instead
   * would silently turn a paid expense into a payable. */
  amountPaid?: number | null
  dueDate?: string | null
  /** Base64 payload only (no data URL prefix). API maps to byte[]. */
  attachmentImage?: string | null
  attachmentContentType?: string | null
  /** PUT only: when true, attachment columns are written (including clear when image omitted/null). */
  setAttachmentImage?: boolean
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

function normalizeExpense(x: any, fallbackUserId?: string): Expense {
  const rawHas = x?.hasAttachmentImage ?? x?.HasAttachmentImage
  const hasAttachmentImage =
    rawHas === true || rawHas === 1 || String(rawHas).toLowerCase() === "true"
  const amount = Number(x.amount ?? x.Amount ?? 0)
  // A backend that has not had migration 238 applied returns none of the payment
  // fields. Falling back to "paid in full" keeps such a farm rendering exactly as
  // it does today rather than showing every expense as an unpaid debt.
  const rawPaid = x.amountPaid ?? x.AmountPaid
  const amountPaid = rawPaid === undefined || rawPaid === null ? amount : Number(rawPaid)
  const rawBalance = x.balance ?? x.Balance
  const balance =
    rawBalance === undefined || rawBalance === null
      ? Math.max(amount - amountPaid, 0)
      : Number(rawBalance)
  const paymentMethod = x.paymentMethod ?? x.PaymentMethod ?? ""
  return {
    farmId: x.farmId ?? x.FarmId ?? "",
    userId: x.userId ?? x.UserId ?? fallbackUserId ?? "",
    expenseId: Number(x.expenseId ?? x.ExpenseId ?? x.id ?? x.Id ?? 0),
    expenseDate: x.expenseDate ?? x.ExpenseDate,
    category: x.category ?? x.Category ?? "",
    description: x.description ?? x.Description ?? "",
    amount,
    paymentMethod,
    flockId: Number(x.flockId ?? x.FlockId ?? 0),
    poultryCashAccountId: (x.poultryCashAccountId ?? x.PoultryCashAccountId) ?? null,
    createdDate: x.createdDate ?? x.CreatedDate,
    notes: x.notes ?? x.Notes,
    paidTo: x.paidTo ?? x.PaidTo ?? x.supplier ?? x.Supplier,
    hasAttachmentImage,
    supplierId: (x.supplierId ?? x.SupplierId) ?? null,
    supplierName: (x.supplierName ?? x.SupplierName) ?? null,
    amountPaid,
    balance,
    paymentStatus:
      (x.paymentStatus ?? x.PaymentStatus) ??
      (paymentMethod === "NonCash"
        ? "NonCash"
        : balance <= 0
          ? "Paid"
          : amountPaid > 0
            ? "PartiallyPaid"
            : "Unpaid"),
    dueDate: (x.dueDate ?? x.DueDate) ?? null,
    sourceType: (x.sourceType ?? x.SourceType) ?? null,
    sourceId: (x.sourceId ?? x.SourceId) ?? null,
  }
}

// Get all expenses
export async function getExpenses(userId?: string, farmId?: string): Promise<ApiResponse<Expense[]>> {
  try {
    const params = new URLSearchParams()
    if (userId) params.append('userId', userId)
    if (farmId) params.append('farmId', farmId)
    
    const url = farmApiUrl(`Expense${params.toString() ? "?" + params.toString() : ""}`)
    console.log("[v0] Fetching expenses:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: {
        ...getAuthHeaders(),
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
    const normalized: Expense[] = data.map((x: any) => normalizeExpense(x, userId))
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
    
    const url = farmApiUrl(`Expense/${id}${params.toString() ? "?" + params.toString() : ""}`)
    console.log("[v0] Fetching expense:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: {
        ...getAuthHeaders(),
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
    const data: Expense = normalizeExpense(raw, userId)
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
    
    const url = farmApiUrl(`Expense/ByFlock/${flockId}${params.toString() ? "?" + params.toString() : ""}`)
    console.log("[v0] Fetching expenses by flock:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: {
        ...getAuthHeaders(),
        Accept: "application/json, text/plain;q=0.9, */*;q=0.8",
      },
    })

    console.log("[v0] Expenses by flock response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      return { success: false, message: errorText || `Failed to fetch expenses by flock (${response.status})` }
    }

    const rawList = await parseJsonLenient<any[]>(response)
    if (!rawList) return { success: false, message: "Failed to parse server response" }
    console.log("[v0] Expenses by flock data received:", rawList)

    if (!Array.isArray(rawList)) {
      return { success: false, message: "Unexpected data format" }
    }

    return {
      success: true,
      message: "Expenses by flock fetched successfully",
      data: rawList.map((x) => normalizeExpense(x, userId)),
    }
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : "Failed to fetch expenses by flock" }
  }
}

// Create new expense
export async function createExpense(expense: ExpenseInput): Promise<ApiResponse<Expense>> {
  try {
    const url = farmApiUrl("Expense")
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
    const requestBody: Record<string, unknown> = {
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
      poultryCashAccountId: expense.poultryCashAccountId ?? null,
    }
    if (expense.supplier !== undefined) {
      requestBody.supplier = expense.supplier
    }
    if (expense.supplierId !== undefined) {
      requestBody.supplierId = expense.supplierId
    }
    // Sent only when the caller means it. `undefined` leaves the backend on its
    // "paid in full" default; an explicit null says the same thing deliberately.
    // Sending 0 by accident would turn a paid expense into an unpaid payable.
    if (expense.amountPaid !== undefined) {
      requestBody.amountPaid = expense.amountPaid
    }
    if (expense.dueDate !== undefined) {
      requestBody.dueDate = expense.dueDate
    }
    if (expense.attachmentImage && expense.attachmentContentType) {
      requestBody.attachmentImage = expense.attachmentImage
      requestBody.attachmentContentType = expense.attachmentContentType
    }

    console.log("[v0] Expense request body:", { ...requestBody, attachmentImage: requestBody.attachmentImage ? "[bytes]" : undefined })

    const response = await fetch(url, {
      method: "POST",
      headers: {
        ...getAuthHeaders(),
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

    const data = await parseJsonLenient<any>(response)
    if (!data) return { success: false, message: "Failed to parse server response", data: null as any }
    console.log("[v0] Created expense data:", data)

    return {
      success: true,
      message: "Expense created successfully",
      data: normalizeExpense(data, userId),
    }
  } catch (error) {
    return { success: false, message: error instanceof Error ? error.message : "Failed to create expense", data: null as any }
  }
}

// Update expense
export async function updateExpense(id: number, expense: Partial<ExpenseInput>): Promise<ApiResponse<Expense>> {
  try {
    const url = farmApiUrl(`Expense/${id}`)
    console.log("[v0] Updating expense:", url)

    const requestBody: Record<string, unknown> = {}
    if (expense.farmId) requestBody.farmId = expense.farmId
    if (expense.userId) requestBody.userId = expense.userId
    if (expense.expenseId !== undefined) requestBody.expenseId = expense.expenseId
    if (expense.expenseDate) requestBody.expenseDate = expense.expenseDate
    if (expense.category) requestBody.category = expense.category
    if (expense.description !== undefined) requestBody.description = expense.description
    if (expense.amount !== undefined) requestBody.amount = expense.amount
    if (expense.paymentMethod) requestBody.paymentMethod = expense.paymentMethod
    if (expense.flockId !== undefined) requestBody.flockId = expense.flockId
    if (expense.poultryCashAccountId !== undefined) requestBody.poultryCashAccountId = expense.poultryCashAccountId
    if (expense.createdDate) requestBody.createdDate = expense.createdDate
    if (expense.supplier !== undefined) requestBody.supplier = expense.supplier
    if (expense.supplierId !== undefined) requestBody.supplierId = expense.supplierId
    // See createExpense: undefined means "don't touch", null means "paid in full".
    if (expense.amountPaid !== undefined) requestBody.amountPaid = expense.amountPaid
    if (expense.dueDate !== undefined) requestBody.dueDate = expense.dueDate

    if (expense.setAttachmentImage === true) {
      requestBody.setAttachmentImage = true
      if (expense.attachmentImage && expense.attachmentContentType) {
        requestBody.attachmentImage = expense.attachmentImage
        requestBody.attachmentContentType = expense.attachmentContentType
      } else {
        requestBody.attachmentImage = null
        requestBody.attachmentContentType = null
      }
    }

    console.log("[v0] Expense update request body:", { ...requestBody, attachmentImage: requestBody.attachmentImage ? "[bytes]" : requestBody.attachmentImage })

    const response = await fetch(url, {
      method: "PUT",
      headers: {
        ...getAuthHeaders(),
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

    if (response.status === 204) {
      const synthetic: Expense = {
        expenseId: id,
        farmId: expense.farmId ?? "",
        userId: expense.userId ?? "",
        expenseDate: expense.expenseDate ?? "",
        category: expense.category ?? "",
        description: expense.description ?? "",
        amount: Number(expense.amount ?? 0),
        paymentMethod: expense.paymentMethod ?? "",
        flockId: Number(expense.flockId ?? 0),
        createdDate: expense.createdDate ?? "",
        // A 204 returns no body, so this echoes back what was sent. amountPaid
        // is undefined when the caller did not touch it, and undefined means
        // "paid in full" — the same reading normalizeExpense applies.
        supplierId: expense.supplierId ?? null,
        amountPaid: expense.amountPaid ?? Number(expense.amount ?? 0),
        balance: Math.max(
          Number(expense.amount ?? 0) - (expense.amountPaid ?? Number(expense.amount ?? 0)),
          0,
        ),
        paymentStatus: derivePaymentStatus(
          Number(expense.amount ?? 0),
          expense.amountPaid ?? Number(expense.amount ?? 0),
          expense.paymentMethod,
        ),
        dueDate: expense.dueDate ?? null,
      }
      if (expense.setAttachmentImage === true) {
        synthetic.hasAttachmentImage = Boolean(expense.attachmentImage && expense.attachmentContentType)
      }
      return {
        success: true,
        message: "Expense updated successfully",
        data: synthetic,
      }
    }

    const data = await parseJsonLenient<any>(response)
    if (!data) {
      return {
        success: true,
        message: "Expense updated successfully",
        data: {
          expenseId: id,
          farmId: expense.farmId ?? "",
          userId: expense.userId ?? "",
          expenseDate: expense.expenseDate ?? "",
          category: expense.category ?? "",
          description: expense.description ?? "",
          amount: expense.amount ?? 0,
          paymentMethod: expense.paymentMethod ?? "",
          flockId: expense.flockId ?? 0,
          createdDate: expense.createdDate ?? "",
        } as Expense,
      }
    }
    console.log("[v0] Updated expense data:", data)

    return {
      success: true,
      message: "Expense updated successfully",
      data: normalizeExpense(data, expense.userId),
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
    
    const url = farmApiUrl(`Expense/${id}?${params.toString()}`)
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
