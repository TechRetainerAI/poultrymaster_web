import { buildApiUrl, getAuthHeaders } from './config'

export interface CashTransaction {
  date: string
  type: string
  description: string
  in: number
  out: number
  balance: number
  sortKey?: string
}

export interface CashSummary {
  currentCash: number
  lastUpdated: string
  transactions: CashTransaction[]
}

export interface CashAdjustmentInput {
  userId: string
  farmId: string
  adjustmentDate: string
  adjustmentType: 'OpeningBalance' | 'OwnerInjection' | 'LoanReceived' | 'Withdrawal' | 'Correction'
  amount: number
  description?: string | null
}

export interface ApiResponse<T = unknown> {
  success: boolean
  data?: T
  message?: string
}

export async function getCashSummary(userId: string, farmId: string): Promise<ApiResponse<CashSummary>> {
  try {
    const endpoint = `/Cash?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    const url = buildApiUrl(endpoint)

    const response = await fetch(url, {
      method: 'GET',
      headers: getAuthHeaders(),
    })

    if (!response.ok) {
      const text = await response.text()
      return {
        success: false,
        message: text || `Failed to fetch cash summary (${response.status})`,
      }
    }

    const data = await response.json()
    return {
      success: true,
      data: {
        currentCash: Number(data.currentCash ?? 0),
        lastUpdated: data.lastUpdated ?? new Date().toISOString(),
        transactions: Array.isArray(data.transactions) ? data.transactions : [],
      },
    }
  } catch (error: unknown) {
    console.error('[v0] Cash summary fetch error:', error)
    return {
      success: false,
      message: (error as Error)?.message || 'Network error while fetching cash summary',
    }
  }
}

export async function createCashAdjustment(input: CashAdjustmentInput): Promise<ApiResponse<{ adjustmentId: number }>> {
  try {
    const url = buildApiUrl('/Cash/Adjustment')
    const response = await fetch(url, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({
        UserId: input.userId,
        FarmId: input.farmId,
        AdjustmentDate: input.adjustmentDate,
        AdjustmentType: input.adjustmentType,
        Amount: input.amount,
        Description: input.description ?? null,
      }),
    })

    if (!response.ok) {
      const text = await response.text()
      return {
        success: false,
        message: text || `Failed to create adjustment (${response.status})`,
      }
    }

    const data = await response.json().catch(() => ({}))
    const adjId = data.adjustmentId ?? data.AdjustmentId ?? data.adjustmentid ?? 0
    return {
      success: true,
      data: { adjustmentId: Number(adjId) },
    }
  } catch (error: unknown) {
    console.error('[v0] Cash adjustment create error:', error)
    return {
      success: false,
      message: (error as Error)?.message || 'Network error while creating adjustment',
    }
  }
}

export async function updateCashAdjustment(
  id: number,
  input: Omit<CashAdjustmentInput, 'userId'>
): Promise<ApiResponse<void>> {
  try {
    const url = buildApiUrl(`/Cash/Adjustment/${id}`)
    const response = await fetch(url, {
      method: 'PUT',
      headers: getAuthHeaders(),
      body: JSON.stringify({
        FarmId: input.farmId,
        AdjustmentDate: input.adjustmentDate,
        AdjustmentType: input.adjustmentType,
        Amount: input.amount,
        Description: input.description ?? null,
      }),
    })

    if (!response.ok) {
      const text = await response.text()
      return {
        success: false,
        message: text || `Failed to update adjustment (${response.status})`,
      }
    }
    return { success: true }
  } catch (error: unknown) {
    console.error('[v0] Cash adjustment update error:', error)
    return {
      success: false,
      message: (error as Error)?.message || 'Network error while updating adjustment',
    }
  }
}

export async function deleteCashAdjustment(id: number, farmId: string): Promise<ApiResponse<void>> {
  try {
    const url = buildApiUrl(`/Cash/Adjustment/${id}?farmId=${encodeURIComponent(farmId)}`)
    const response = await fetch(url, {
      method: 'DELETE',
      headers: getAuthHeaders(),
    })

    if (!response.ok) {
      const text = await response.text()
      return {
        success: false,
        message: text || `Failed to delete adjustment (${response.status})`,
      }
    }
    return { success: true }
  } catch (error: unknown) {
    console.error('[v0] Cash adjustment delete error:', error)
    return {
      success: false,
      message: (error as Error)?.message || 'Network error while deleting adjustment',
    }
  }
}
