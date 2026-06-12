// Weekly farm observations / notes. Backed by FarmObservationController + spFarmObservation_* (migration 018).

import { farmApiUrl, getAuthHeaders } from "./config"

export interface FarmObservation {
  id: number
  farmId: string
  userId?: string | null
  /** ISO date (YYYY-MM-DD) — Monday of the week these notes apply to. */
  weekStartDate: string
  notes?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface ApiResponse<T = unknown> {
  success: boolean
  message?: string
  data?: T | null
}

/** Get the notes row for the given farm + week. Returns null if no row exists yet. */
export async function getObservationByWeek(
  farmId: string,
  weekStartDate: string,
): Promise<ApiResponse<FarmObservation | null>> {
  try {
    const params = new URLSearchParams({ farmId, weekStartDate })
    const url = farmApiUrl(`FarmObservation/by-week?${params.toString()}`)
    const response = await fetch(url, {
      method: "GET",
      headers: { ...(await getAuthHeaders()), Accept: "application/json" },
    })

    if (!response.ok) {
      const text = await response.text()
      return { success: false, message: text || "Failed to load observation", data: null }
    }
    const text = await response.text()
    const data = text.trim() ? (JSON.parse(text) as FarmObservation | null) : null
    return { success: true, data }
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Network error"
    return { success: false, message: msg, data: null }
  }
}

/** Upsert (insert or update) the notes for a given farm + week. */
export async function upsertObservation(input: {
  farmId: string
  userId?: string | null
  weekStartDate: string
  notes?: string | null
}): Promise<ApiResponse<FarmObservation>> {
  try {
    const url = farmApiUrl("FarmObservation")
    const response = await fetch(url, {
      method: "POST",
      headers: {
        ...(await getAuthHeaders()),
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        farmId: input.farmId,
        userId: input.userId ?? null,
        weekStartDate: input.weekStartDate,
        notes: input.notes ?? null,
      }),
    })

    if (!response.ok) {
      const text = await response.text()
      return { success: false, message: text || "Failed to save observation", data: null }
    }
    const data = (await response.json()) as FarmObservation
    return { success: true, data }
  } catch (err) {
    const msg = err instanceof Error ? err.message : "Network error"
    return { success: false, message: msg, data: null }
  }
}
