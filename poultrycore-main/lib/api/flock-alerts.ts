// Flock anomaly alerts — client for api/Poultry/flock-alerts (migration 338).
// Listing re-runs the server's idempotent scan (yesterday + today) first, so
// what comes back is current; the scan can never create duplicates.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"
import type {
  FlockAlert,
  FlockAlertEvent,
  FlockAnomalySignalSetting,
  FlockSignalEvaluation,
} from "@/lib/production/flock-anomalies"

function farmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

async function call<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(farmApiUrl(path), {
    method,
    headers: getAuthHeaders(),
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const raw = await res.text().catch(() => "")
    let message: string | undefined
    try { message = JSON.parse(raw)?.message } catch { /* not JSON */ }
    if ((res.status === 400 || res.status === 404) && message) throw new Error(message)
    throw new Error(explainHttpError(method, path, res.status, raw))
  }
  if (res.status === 204) return undefined as T
  const text = await res.text()
  return (text ? JSON.parse(text) : undefined) as T
}

export type AlertStatusFilter = "active" | "all" | "Open" | "Acknowledged" | "Resolved" | "Cleared"

export const getFlockAlerts = async (opts: {
  status?: AlertStatusFilter; from?: string; to?: string; flockId?: number; refresh?: boolean
} = {}) => {
  const qs = new URLSearchParams({ farmId: farmId(), status: opts.status ?? "active" })
  if (opts.from) qs.set("from", opts.from)
  if (opts.to) qs.set("to", opts.to)
  if (opts.flockId) qs.set("flockId", String(opts.flockId))
  if (opts.refresh === false) qs.set("refresh", "false")
  return call<FlockAlert[]>("GET", `/Poultry/flock-alerts?${qs}`)
}

export const getFlockAlert = async (alertId: number) =>
  call<{ alert: FlockAlert; events: FlockAlertEvent[] }>(
    "GET", `/Poultry/flock-alerts/${alertId}?farmId=${encodeURIComponent(farmId())}`)

export const getFlockEvaluation = async (date?: string) => {
  const qs = new URLSearchParams({ farmId: farmId() })
  if (date) qs.set("date", date)
  return call<FlockSignalEvaluation[]>("GET", `/Poultry/flock-alerts/evaluation?${qs}`)
}

export const rescanFlockAlerts = async (from: string, to: string) =>
  call<unknown[]>("POST", `/Poultry/flock-alerts/scan`, { farmId: farmId(), from, to })

export const acknowledgeFlockAlert = async (alertId: number, note?: string) =>
  call<void>("POST", `/Poultry/flock-alerts/${alertId}/acknowledge`, { farmId: farmId(), note: note || null })

export const addFlockAlertNote = async (alertId: number, note: string) =>
  call<void>("POST", `/Poultry/flock-alerts/${alertId}/notes`, { farmId: farmId(), note })

export const resolveFlockAlert = async (alertId: number, note: string) =>
  call<void>("POST", `/Poultry/flock-alerts/${alertId}/resolve`, { farmId: farmId(), note })

export const getFlockAnomalySettings = async () =>
  call<FlockAnomalySignalSetting[]>("GET", `/Poultry/flock-alerts/settings?farmId=${encodeURIComponent(farmId())}`)

export const saveFlockAnomalySetting = async (s: FlockAnomalySignalSetting) =>
  call<void>("PUT", `/Poultry/flock-alerts/settings`, { ...s, farmId: farmId() })

export const resetFlockAnomalySetting = async (signalKey: string) =>
  call<void>("PUT", `/Poultry/flock-alerts/settings/reset`, { farmId: farmId(), signalKey })
