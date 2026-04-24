import { farmApiUrl, getAuthHeaders } from "@/lib/api/config"

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
  farmId?: string
  action?: string
  resource?: string
  status?: "Success" | "Failed"
  startDate?: string
  endDate?: string
  page?: number
  pageSize?: number
}

function buildQuery(filters: Record<string, string | number | undefined>): string {
  const sp = new URLSearchParams()
  for (const [k, v] of Object.entries(filters)) {
    if (v === undefined || v === null || v === "") continue
    sp.set(k, String(v))
  }
  const q = sp.toString()
  return q ? `?${q}` : ""
}

function normalizeListPayload(res: unknown): AuditLog[] {
  if (Array.isArray(res)) return res as AuditLog[]
  if (res && typeof res === "object") {
    const o = res as Record<string, unknown>
    if (Array.isArray(o.items)) return o.items as AuditLog[]
    if (Array.isArray(o.data)) return o.data as AuditLog[]
    if (Array.isArray(o.result)) return o.result as AuditLog[]
  }
  return []
}

function extractUpstreamErrorMessage(status: number, body: unknown): string {
  if (typeof body === "string" && body.trim()) return body.trim().slice(0, 500)
  if (body && typeof body === "object") {
    const o = body as Record<string, unknown>
    const sqlMsg = o.sqlMessage
    if (typeof sqlMsg === "string" && sqlMsg.trim()) {
      const head = typeof o.message === "string" && o.message.trim() ? `${o.message.trim()}: ` : ""
      return `${head}${sqlMsg.trim()}`.slice(0, 800)
    }
    const msg = o.message ?? o.title ?? o.detail
    if (typeof msg === "string" && msg.trim()) return msg.trim()
    if (Array.isArray(o.errors) && o.errors.length)
      return String(o.errors[0]).slice(0, 500)
  }
  return status === 500
    ? "Farm API error (500). Common fix: run SQL migration 007_AddAuditLogsFarmId.sql so dbo.AuditLogs has a FarmId column, then redeploy the Farm API."
    : `HTTP ${status}`
}

async function farmGetJson(pathAfterApiWithQuery: string, signal?: AbortSignal): Promise<unknown> {
  const url = farmApiUrl(pathAfterApiWithQuery)
  const headers = getAuthHeaders() as Record<string, string>
  const res = await fetch(url, { method: "GET", headers, signal })
  const ct = res.headers.get("content-type") || ""
  const body = ct.includes("application/json") ? await res.json() : await res.text()
  if (!res.ok) {
    const detail = extractUpstreamErrorMessage(res.status, body)
    throw new Error(`HTTP ${res.status}: ${detail}`)
  }
  return body
}

export class AuditLogsService {
  /**
   * Get all audit logs with optional filters.
   * Uses same-origin `/api/proxy` in the browser (avoids CORS to Cloud Run).
   */
  static async getAll(filters?: AuditLogFilters, signal?: AbortSignal): Promise<AuditLog[]> {
    let farmId = filters?.farmId
    if (!farmId && typeof window !== "undefined") {
      farmId = localStorage.getItem("farmId") || ""
    }

    if (!farmId) {
      console.warn("[AuditLogsService] farmId is required but not provided")
      return []
    }

    const params: Record<string, string | number | undefined> = {
      page: filters?.page ?? 1,
      pageSize: filters?.pageSize ?? 200,
      farmId,
      ...filters,
    }

    const query = buildQuery(params)
    const res = await farmGetJson(`AuditLogs${query}`, signal)
    return normalizeListPayload(res)
  }

  static async getById(id: string): Promise<AuditLog> {
    return (await farmGetJson(`AuditLogs/${encodeURIComponent(id)}`)) as AuditLog
  }

  static async getByUserId(userId: string): Promise<AuditLog[]> {
    return this.getAll({ userId })
  }

  static async getByAction(action: string): Promise<AuditLog[]> {
    return this.getAll({ action })
  }

  static async getByDateRange(startDate: string, endDate: string): Promise<AuditLog[]> {
    return this.getAll({ startDate, endDate })
  }

  static async export(filters?: AuditLogFilters): Promise<Blob> {
    let farmId = filters?.farmId
    if (!farmId && typeof window !== "undefined") {
      farmId = localStorage.getItem("farmId") || ""
    }
    const params: Record<string, string | number | undefined> = {
      page: filters?.page ?? 1,
      pageSize: filters?.pageSize ?? 5000,
      farmId,
      ...filters,
    }
    const query = buildQuery(params)
    const tryPaths = [`AuditLogs/export${query}`, `auditlogs/export${query}`]

    for (const path of tryPaths) {
      try {
        const url = farmApiUrl(path)
        const headers = { ...getAuthHeaders(), Accept: "application/octet-stream,*/*" } as HeadersInit
        const res = await fetch(url, { method: "GET", headers })
        if (res.ok) return await res.blob()
      } catch {
        /* try next */
      }
    }
    return new Blob()
  }
}
