import { apiClient } from '@/lib/api/client'
import type { Expense, ExpenseInput } from '@/lib/api/types'

interface ExpenseFilters {
  farmId?: string
  userId?: string
  category?: string
  startDate?: string
  endDate?: string
}

export class ExpensesService {
  /**
   * Get all expenses with optional filters
   */
  static async getAll(filters?: ExpenseFilters): Promise<Expense[]> {
    return apiClient.get<Expense[]>('/api/Expenses', filters)
  }

  /**
   * Get a single expense by ID
   */
  static async getById(id: number): Promise<Expense> {
    return apiClient.get<Expense>(`/api/Expenses/${id}`)
  }

  /**
   * Create a new expense
   */
  static async create(data: ExpenseInput): Promise<Expense> {
    return apiClient.post<Expense>('/api/Expenses', data)
  }

  /**
   * Update an existing expense
   */
  static async update(id: number, data: Partial<ExpenseInput>): Promise<Expense> {
    return apiClient.put<Expense>(`/api/Expenses/${id}`, data)
  }

  /**
   * Delete an expense
   */
  static async delete(id: number): Promise<void> {
    return apiClient.delete<void>(`/api/Expenses/${id}`)
  }

  /**
   * Get expenses by date range
   */
  static async getByDateRange(startDate: string, endDate: string): Promise<Expense[]> {
    return apiClient.get<Expense[]>('/api/Expenses', {
      startDate,
      endDate,
    })
  }

  /**
   * Get expenses by category
   */
  static async getByCategory(category: string): Promise<Expense[]> {
    return apiClient.get<Expense[]>('/api/Expenses', { category })
  }
}
