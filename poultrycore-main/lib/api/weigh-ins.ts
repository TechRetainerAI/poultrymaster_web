// Flock weigh-ins (migration 400). Weights are in grams throughout.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

export interface FlockWeighIn {
  weighInId: number
  flockId: number
  flockName: string
  flockType: string
  breed: string | null
  flockClosed: boolean
  weighDate: string
  ageInDays: number
  sampleSize: number
  avgWeightG: number
  minWeightG: number | null
  maxWeightG: number | null
  uniformityPct: number | null
  cvPct: number | null
  /** The birds as weighed; null when only the summary was recorded. */
  weightsG: number[] | null
  notes: string | null
  createdBy: string | null
  createdAt: string
  prevAvgWeightG: number | null
  daysSincePrev: number | null
  dailyGainG: number | null
}

/** Send weightsG OR sampleSize + avgWeightG. With weights, the server derives the rest. */
export interface FlockWeighInInput {
  flockId: number
  weighDate: string
  sampleSize?: number | null
  avgWeightG?: number | null
  weightsG?: number[] | null
  uniformityPct?: number | null
  cvPct?: number | null
  minWeightG?: number | null
  maxWeightG?: number | null
  notes?: string | null
}

const farmId = () => getUserContext().farmId || ""

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
    if ((res.status === 400 || res.status === 403 || res.status === 404 || res.status === 409) && message) throw new Error(message)
    throw new Error(explainHttpError(method, path, res.status, raw))
  }
  if (res.status === 204) return undefined as T
  const text = await res.text()
  return (text ? JSON.parse(text) : undefined) as T
}

const base = "/Poultry/weigh-ins"

export const listWeighIns = (flockId?: number | null) =>
  call<FlockWeighIn[]>("GET", `${base}?farmId=${encodeURIComponent(farmId())}${flockId ? `&flockId=${flockId}` : ""}`)

export const createWeighIn = (input: FlockWeighInInput) =>
  call<{ weighInId: number }>("POST", base, { ...input, farmId: farmId() })

export const updateWeighIn = (id: number, input: FlockWeighInInput) =>
  call<void>("PUT", `${base}/${id}`, { ...input, farmId: farmId() })

export const deleteWeighIn = (id: number, reason: string) =>
  call<void>("DELETE", `${base}/${id}?farmId=${encodeURIComponent(farmId())}&reason=${encodeURIComponent(reason)}`)
