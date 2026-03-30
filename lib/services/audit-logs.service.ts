import { apiClient } from '@/lib/api/client'

export interface AuditLog {
  id: string
  userId: string
  userName: string
  action: string
  resource: string
  resourceId: string
  details: string
  ipAddress: string
  userAgent: string
  timestamp: string
  status: "Success" | "Failed"
}

interface AuditLogFilters {
  userId?: string
  farmId?: string // Optional in filters, but will be auto-filled from localStorage if not provided
  action?: string
  resource?: string
  status?: "Success" | "Failed"
  startDate?: string
  endDate?: string
  page?: number
  pageSize?: number
}

export class AuditLogsService {
  /**
   * Get all audit logs with optional filters
   */
  static async getAll(filters?: AuditLogFilters): Promise<AuditLog[]> {
    // Get farmId from filters or from localStorage (required by backend)
    let farmId = filters?.farmId
    if (!farmId && typeof window !== "undefined") {
      farmId = localStorage.getItem("farmId") || ""
    }
    
    // If still no farmId, return empty array with warning
    if (!farmId) {
      console.warn("[AuditLogsService] farmId is required but not provided")
      return []
    }
    
    const params = { 
      page: 1, 
      pageSize: 200, 
      farmId, // Always include farmId as it's required by backend
      ...filters 
    }
    
    // Try the correct endpoint first (api/AuditLogs)
    const tryPaths = [
      '/api/AuditLogs', // This is the correct endpoint based on the controller
      '/api/AuditLog',
      '/api/auditlogs',
    ]
    
    for (const path of tryPaths) {
      try {
        const res: any = await apiClient.get<any>(path, params)
        // Accept multiple shapes: array | {items}| {data} | {result}
        if (Array.isArray(res)) return res as AuditLog[]
        if (Array.isArray(res?.items)) return res.items as AuditLog[]
        if (Array.isArray(res?.data)) return res.data as AuditLog[]
        if (Array.isArray(res?.result)) return res.result as AuditLog[]
      } catch (e: any) {
        // Log the error for the first path attempt to help with debugging
        if (path === '/api/AuditLogs') {
          console.error(`[AuditLogsService] Error fetching from ${path}:`, e?.message || e)
        }
        // try next path
      }
    }
    return []
  }

  /**
   * Get a single audit log by ID
   */
  static async getById(id: string): Promise<AuditLog> {
    try {
      return await apiClient.get<AuditLog>(`/api/AuditLogs/${id}`)
    } catch {
      return await apiClient.get<AuditLog>(`/api/AuditLog/${id}`)
    }
  }

  /**
   * Get audit logs by user ID
   */
  static async getByUserId(userId: string): Promise<AuditLog[]> {
    return this.getAll({ userId })
  }

  /**
   * Get audit logs by action type
   */
  static async getByAction(action: string): Promise<AuditLog[]> {
    return this.getAll({ action })
  }

  /**
   * Get audit logs by date range
   */
  static async getByDateRange(startDate: string, endDate: string): Promise<AuditLog[]> {
    return this.getAll({ startDate, endDate })
  }

  /**
   * Export audit logs (returns file download)
   */
  static async export(filters?: AuditLogFilters): Promise<Blob> {
    const tryPaths = [
      '/api/AuditLogs/export',
      '/api/auditlogs/export',
      '/api/PoultryFarmAPI/AuditLogs/export',
      '/PoultryFarmAPI/AuditLogs/export',
    ]
    for (const path of tryPaths) {
      try {
        return await apiClient.get(path, { ...filters, responseType: 'blob' as any })
      } catch {}
    }
    // Fallback empty blob
    return new Blob()
  }
}
