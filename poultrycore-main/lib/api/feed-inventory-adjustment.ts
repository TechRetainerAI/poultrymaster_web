import { buildApiUrl, getAuthHeaders } from "./config"

export interface FeedInventoryAdjustment {
  adjustmentId: number
  userId: string
  farmId: string
  adjustmentDate: string
  adjustmentType: string
  feedDeltaKg: number
  description?: string | null
  createdDate?: string
}

export interface FeedInventoryAdjustmentInput {
  userId: string
  farmId: string
  adjustmentDate: string
  adjustmentType: "OpeningBalance" | "Stocktake" | "Correction"
  feedDeltaKg: number
  description?: string | null
}

export interface ApiResponse<T = unknown> {
  success: boolean
  data?: T
  message?: string
}

function mapRow(raw: Record<string, unknown>): FeedInventoryAdjustment {
  const kg = raw.feedDeltaKg ?? raw.FeedDeltaKg
  return {
    adjustmentId: Number(raw.adjustmentId ?? raw.AdjustmentId ?? 0),
    userId: String(raw.userId ?? raw.UserId ?? ""),
    farmId: String(raw.farmId ?? raw.FarmId ?? ""),
    adjustmentDate: String(raw.adjustmentDate ?? raw.AdjustmentDate ?? ""),
    adjustmentType: String(raw.adjustmentType ?? raw.AdjustmentType ?? ""),
    feedDeltaKg: typeof kg === "number" ? kg : parseFloat(String(kg ?? 0)) || 0,
    description: (raw.description ?? raw.Description) as string | null | undefined,
    createdDate: raw.createdDate != null ? String(raw.createdDate) : raw.CreatedDate != null ? String(raw.CreatedDate) : undefined,
  }
}

export async function getFeedInventoryAdjustments(farmId: string): Promise<ApiResponse<FeedInventoryAdjustment[]>> {
  try {
    const q = `?farmId=${encodeURIComponent(farmId)}`
    const url = buildApiUrl(`/FeedInventoryAdjustment${q}`)
    const res = await fetch(url, { headers: getAuthHeaders() })
    if (!res.ok) {
      const text = await res.text()
      return { success: false, message: text || `Failed to load feed adjustments (${res.status})` }
    }
    const data = await res.json()
    const arr = Array.isArray(data) ? data : []
    return { success: true, data: arr.map((x) => mapRow(x as Record<string, unknown>)) }
  } catch (e) {
    return { success: false, message: (e as Error)?.message || "Network error" }
  }
}

export async function createFeedInventoryAdjustment(
  input: FeedInventoryAdjustmentInput
): Promise<ApiResponse<FeedInventoryAdjustment>> {
  try {
    const url = buildApiUrl("/FeedInventoryAdjustment")
    const res = await fetch(url, {
      method: "POST",
      headers: getAuthHeaders(),
      body: JSON.stringify({
        UserId: input.userId,
        FarmId: input.farmId,
        AdjustmentDate: input.adjustmentDate,
        AdjustmentType: input.adjustmentType,
        FeedDeltaKg: input.feedDeltaKg,
        Description: input.description ?? null,
      }),
    })
    if (!res.ok) {
      const text = await res.text()
      return { success: false, message: text || "Failed to create feed adjustment" }
    }
    const raw = await res.json().catch(() => ({}))
    return { success: true, data: mapRow(raw as Record<string, unknown>) }
  } catch (e) {
    return { success: false, message: (e as Error)?.message || "Network error" }
  }
}

export async function updateFeedInventoryAdjustment(
  id: number,
  farmId: string,
  patch: Omit<FeedInventoryAdjustmentInput, "userId" | "farmId"> & { userId: string }
): Promise<ApiResponse<void>> {
  try {
    const url = buildApiUrl(`/FeedInventoryAdjustment/${id}`)
    const res = await fetch(url, {
      method: "PUT",
      headers: getAuthHeaders(),
      body: JSON.stringify({
        AdjustmentId: id,
        UserId: patch.userId,
        FarmId: farmId,
        AdjustmentDate: patch.adjustmentDate,
        AdjustmentType: patch.adjustmentType,
        FeedDeltaKg: patch.feedDeltaKg,
        Description: patch.description ?? null,
      }),
    })
    if (!res.ok) {
      const text = await res.text()
      return { success: false, message: text || "Failed to update feed adjustment" }
    }
    return { success: true }
  } catch (e) {
    return { success: false, message: (e as Error)?.message || "Network error" }
  }
}

export async function deleteFeedInventoryAdjustment(id: number, farmId: string): Promise<ApiResponse<void>> {
  try {
    const url = buildApiUrl(`/FeedInventoryAdjustment/${id}?farmId=${encodeURIComponent(farmId)}`)
    const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() })
    if (!res.ok) {
      const text = await res.text()
      return { success: false, message: text || "Failed to delete feed adjustment" }
    }
    return { success: true }
  } catch (e) {
    return { success: false, message: (e as Error)?.message || "Network error" }
  }
}
