// Egg Cost & Profit Analyzer (migration 481) -- API client. The server only
// returns facts and stores the analyzer's own settings / assumptions /
// historical costs / snapshots; every figure is computed by lib/egg-cost/engine.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import type { CostSettings, EggCostFacts, FlockAssumptions } from "@/lib/egg-cost/engine"

export interface ApiResult<T> { success: boolean; data?: T; message?: string }

async function call<T>(path: string, init?: RequestInit): Promise<ApiResult<T>> {
  try {
    const { farmId } = getUserContext()
    if (!farmId) return { success: false, message: "No company selected." }
    const sep = path.includes("?") ? "&" : "?"
    const res = await fetch(farmApiUrl(`/poultry/egg-cost/${path}${sep}farmId=${encodeURIComponent(farmId)}`), {
      ...init,
      headers: { ...getAuthHeaders(), ...(init?.headers ?? {}) },
    })
    const text = await res.text()
    let body: any = null
    try { body = text ? JSON.parse(text) : null } catch { body = text }
    if (!res.ok) {
      const message = (body && typeof body === "object" && (body.message || body.title)) || (typeof body === "string" && body) ||
        (res.status === 403 ? "You do not have permission to do this." : `Request failed (${res.status}).`)
      return { success: false, message }
    }
    return { success: true, data: body as T }
  } catch (e) {
    return { success: false, message: e instanceof Error ? e.message : "Network error" }
  }
}

const json = (method: string, body: unknown): RequestInit => ({ method, body: JSON.stringify(body), headers: { "Content-Type": "application/json" } })

export const getEggCostFacts = (startDate: string, endDate: string) =>
  call<EggCostFacts>(`facts?startDate=${startDate}&endDate=${endDate}`)

export const saveEggCostSettings = (settings: Partial<CostSettings>) =>
  call<CostSettings>("settings", json("PUT", settings))

export const saveFlockAssumptions = (flockId: number, a: Partial<FlockAssumptions>) =>
  call<void>(`flocks/${flockId}/assumptions`, json("PUT", a))

export interface HistoricalCostInput {
  flockId?: number | null
  batchId?: number | null
  category: "BirdPurchase" | "Feed" | "Medication" | "Labour" | "Overhead" | "Other"
  amount: number
  periodFrom?: string | null
  periodTo?: string | null
  reason: string
  reference?: string | null
  isEstimate: boolean
}
export const addHistoricalCost = (input: HistoricalCostInput) =>
  call<{ historicalCostId: number }>("historical-costs", json("POST", input))
export const reverseHistoricalCost = (id: number, reason: string) =>
  call<void>(`historical-costs/${id}/reverse`, json("POST", { reason }))

export interface SnapshotSummary {
  snapshotId: number
  name: string
  mode: "Recorded" | "Scenario"
  params: SnapshotParams
  calcVersion: string
  settingsVersion: number | null
  sourceFingerprint: string | null
  createdBy: string | null
  createdAt: string
  headline: Record<string, unknown> | null
}
export interface SnapshotParams {
  startDate: string
  endDate: string
  period: string
  scope: { level: "farm" | "batch" | "flock"; batchId?: number | null; flockIds?: number[] }
  costView: "direct" | "full"
  scenario?: Record<string, unknown> | null
}
export interface Snapshot extends SnapshotSummary { result: Record<string, unknown> }

export const listSnapshots = () => call<SnapshotSummary[]>("snapshots")
export const getSnapshot = (id: number) => call<Snapshot>(`snapshots/${id}`)
export const saveSnapshot = (input: {
  name: string; mode: "Recorded" | "Scenario"; params: SnapshotParams; result: Record<string, unknown>
  calcVersion: string; settingsVersion: number | null; sourceFingerprint: string | null
}) => call<{ snapshotId: number }>("snapshots", json("POST", input))
export const deleteSnapshot = (id: number) => call<void>(`snapshots/${id}`, { method: "DELETE" })

export interface AuditEntry {
  auditId: number; kind: string; refId: number | null; action: string
  changedBy: string | null; changedAt: string; before: unknown; after: unknown
}
export const listEggCostAudit = () => call<AuditEntry[]>("audit")
