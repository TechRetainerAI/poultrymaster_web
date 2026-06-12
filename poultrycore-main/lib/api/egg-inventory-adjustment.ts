import { buildApiUrl, getAuthHeaders } from "./config"

export interface EggInventoryAdjustment {
  adjustmentId: number
  userId: string
  farmId: string
  adjustmentDate: string
  adjustmentType: string
  eggDelta: number
  description?: string | null
  createdDate?: string
}

export interface EggInventoryAdjustmentInput {
  userId: string
  farmId: string
  adjustmentDate: string
  adjustmentType: "OpeningBalance" | "Stocktake" | "Correction"
  eggDelta: number
  description?: string | null
}

export interface ApiResponse<T = unknown> {
  success: boolean
  data?: T
  message?: string
}

function mapRow(raw: Record<string, unknown>): EggInventoryAdjustment {
  return {
    adjustmentId: Number(raw.adjustmentId ?? raw.AdjustmentId ?? 0),
    userId: String(raw.userId ?? raw.UserId ?? ""),
    farmId: String(raw.farmId ?? raw.FarmId ?? ""),
    adjustmentDate: String(raw.adjustmentDate ?? raw.AdjustmentDate ?? ""),
    adjustmentType: String(raw.adjustmentType ?? raw.AdjustmentType ?? ""),
    eggDelta: Number(raw.eggDelta ?? raw.EggDelta ?? 0),
    description: (raw.description ?? raw.Description) as string | null | undefined,
    createdDate: raw.createdDate != null ? String(raw.createdDate) : raw.CreatedDate != null ? String(raw.CreatedDate) : undefined,
  }
}

export async function getEggInventoryAdjustments(farmId: string): Promise<ApiResponse<EggInventoryAdjustment[]>> {
  try {
    const q = `?farmId=${encodeURIComponent(farmId)}`
    const url = buildApiUrl(`/EggInventoryAdjustment${q}`)
    const res = await fetch(url, { headers: getAuthHeaders() })
    if (!res.ok) {
      const text = await res.text()
      return { success: false, message: text || `Failed to load adjustments (${res.status})` }
    }
    const data = await res.json()
    const arr = Array.isArray(data) ? data : []
    return { success: true, data: arr.map((x) => mapRow(x as Record<string, unknown>)) }
  } catch (e) {
    return { success: false, message: (e as Error)?.message || "Network error" }
  }
}

export async function createEggInventoryAdjustment(
  input: EggInventoryAdjustmentInput
): Promise<ApiResponse<EggInventoryAdjustment>> {
  try {
    const url = buildApiUrl("/EggInventoryAdjustment")
    const res = await fetch(url, {
      method: "POST",
      headers: getAuthHeaders(),
      body: JSON.stringify({
        UserId: input.userId,
        FarmId: input.farmId,
        AdjustmentDate: input.adjustmentDate,
        AdjustmentType: input.adjustmentType,
        EggDelta: input.eggDelta,
        Description: input.description ?? null,
      }),
    })
    if (!res.ok) {
      const text = await res.text()
      return { success: false, message: text || "Failed to create adjustment" }
    }
    const raw = await res.json().catch(() => ({}))
    return { success: true, data: mapRow(raw as Record<string, unknown>) }
  } catch (e) {
    return { success: false, message: (e as Error)?.message || "Network error" }
  }
}

export async function updateEggInventoryAdjustment(
  id: number,
  farmId: string,
  patch: Omit<EggInventoryAdjustmentInput, "userId" | "farmId"> & { userId: string }
): Promise<ApiResponse<void>> {
  try {
    const url = buildApiUrl(`/EggInventoryAdjustment/${id}`)
    const res = await fetch(url, {
      method: "PUT",
      headers: getAuthHeaders(),
      body: JSON.stringify({
        AdjustmentId: id,
        UserId: patch.userId,
        FarmId: farmId,
        AdjustmentDate: patch.adjustmentDate,
        AdjustmentType: patch.adjustmentType,
        EggDelta: patch.eggDelta,
        Description: patch.description ?? null,
      }),
    })
    if (!res.ok) {
      const text = await res.text()
      return { success: false, message: text || "Failed to update adjustment" }
    }
    return { success: true }
  } catch (e) {
    return { success: false, message: (e as Error)?.message || "Network error" }
  }
}

export async function deleteEggInventoryAdjustment(id: number, farmId: string): Promise<ApiResponse<void>> {
  try {
    const url = buildApiUrl(`/EggInventoryAdjustment/${id}?farmId=${encodeURIComponent(farmId)}`)
    const res = await fetch(url, { method: "DELETE", headers: getAuthHeaders() })
    if (!res.ok) {
      const text = await res.text()
      return { success: false, message: text || "Failed to delete adjustment" }
    }
    return { success: true }
  } catch (e) {
    return { success: false, message: (e as Error)?.message || "Network error" }
  }
}
