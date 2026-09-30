// Days of supply — client for api/Poultry/stock-supply (migration 337).
// Everything is derived on the server on each read; nothing here creates an
// alert or a purchase.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"
import type { StockSupplyRow } from "@/lib/inventory/days-of-supply"

export interface StockSupplySettings {
  lookbackDays: number
  criticalDays: number
  warningDays: number
  minHistoryDays: number
  isCustomised?: boolean
}

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
    if (res.status === 400 && message) throw new Error(message)
    throw new Error(explainHttpError(method, path, res.status, raw))
  }
  if (res.status === 204) return undefined as T
  const text = await res.text()
  return (text ? JSON.parse(text) : undefined) as T
}

export const getStockSupply = async (lookbackDays?: number) => {
  const qs = new URLSearchParams({ farmId: farmId() })
  if (lookbackDays) qs.set("lookbackDays", String(lookbackDays))
  return call<StockSupplyRow[]>("GET", `/Poultry/stock-supply?${qs}`)
}

export const getStockSupplySettings = async () =>
  call<StockSupplySettings>("GET", `/Poultry/stock-supply/settings?farmId=${encodeURIComponent(farmId())}`)

export const saveStockSupplySettings = async (s: StockSupplySettings) =>
  call<void>("PUT", `/Poultry/stock-supply/settings`, { ...s, farmId: farmId() })
