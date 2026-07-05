export interface EggProduction {
  productionId: number
  farmId: string
  userId: string
  flockId: number
  flockName?: string
  productionDate: string
  eggCount: number
  production9AM: number
  production12PM: number
  production4PM: number
  totalProduction: number
  brokenEggs: number
  notes: string
  /** Sort / size grade (Small, Medium, Large, XLarge, Jumbo, …). */
  eggGrade?: string | null
}

export interface ApiResponse<T = unknown> {
  success: boolean
  data?: T
  message?: string
  errors?: string[]
}

export interface EggProductionInput {
  farmId: string
  userId: string
  flockId: number
  productionDate: string
  eggCount: number
  production9AM: number
  production12PM: number
  production4PM: number
  totalProduction: number
  brokenEggs: number
  notes: string
  eggGrade?: string | null
  // Doc 4: feed/medication usage costing (optional).
  specificFeedUsedId?: number | null
  specificFeedUsedName?: string | null
  feedUnitCost?: number | null
  totalFeedConsumed?: number | null
  totalFeedCost?: number | null
  specificMedicationUsedId?: number | null
  specificMedicationUsedName?: string | null
  medicationUnitCost?: number | null
  totalMedicationConsumed?: number | null
  totalMedicationCost?: number | null
}

function mapEggRow(raw: Record<string, unknown>): EggProduction {
  const g = raw.eggGrade ?? raw.EggGrade
  return {
    productionId: Number(raw.productionId ?? raw.ProductionId ?? 0),
    farmId: String(raw.farmId ?? raw.FarmId ?? ""),
    userId: String(raw.userId ?? raw.UserId ?? ""),
    flockId: Number(raw.flockId ?? raw.FlockId ?? 0),
    flockName: raw.flockName != null ? String(raw.flockName) : raw.FlockName != null ? String(raw.FlockName) : undefined,
    productionDate: String(raw.productionDate ?? raw.ProductionDate ?? ""),
    eggCount: Number(raw.eggCount ?? raw.EggCount ?? 0),
    production9AM: Number(raw.production9AM ?? raw.Production9AM ?? 0),
    production12PM: Number(raw.production12PM ?? raw.Production12PM ?? 0),
    production4PM: Number(raw.production4PM ?? raw.Production4PM ?? 0),
    totalProduction: Number(raw.totalProduction ?? raw.TotalProduction ?? 0),
    brokenEggs: Number(raw.brokenEggs ?? raw.BrokenEggs ?? 0),
    notes: String(raw.notes ?? raw.Notes ?? ""),
    eggGrade: g != null && String(g).trim() !== "" ? String(g).trim() : null,
  }
}

export async function getEggProductions(userId?: string, farmId?: string): Promise<ApiResponse<EggProduction[]>> {
  try {
    const params = new URLSearchParams()
    if (userId) params.append("userId", userId)
    if (farmId) params.append("farmId", farmId)

    const url = `/api/proxy/EggProduction?${params.toString()}`

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error(
        "[EggProduction] fetch error:",
        response.status,
        response.statusText,
        errorText || "(empty body)"
      )
      return {
        success: false,
        message: `Failed to fetch egg productions (${response.status})`,
        data: [],
      }
    }

    const data = await response.json()
    const rows = Array.isArray(data) ? data.map((r) => mapEggRow(r as Record<string, unknown>)) : []

    return {
      success: true,
      message: "Egg productions fetched successfully",
      data: rows,
    }
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error)
    console.error("[EggProduction] fetch error:", msg, error)
    return {
      success: false,
      message: msg || "Failed to fetch egg productions",
      data: [],
    }
  }
}

export async function deleteEggProduction(productionId: number, userId: string, farmId: string): Promise<ApiResponse> {
  try {
    const params = new URLSearchParams()
    params.append("userId", userId)
    params.append("farmId", farmId)

    const url = `/api/proxy/EggProduction/${productionId}?${params.toString()}`

    const response = await fetch(url, {
      method: "DELETE",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[EggProduction] delete error:", errorText)
      return {
        success: false,
        message: "Failed to delete egg production",
      }
    }

    return {
      success: true,
      message: "Egg production deleted successfully",
    }
  } catch (error) {
    console.error("[EggProduction] delete error:", error)
    return {
      success: false,
      message: "Failed to delete egg production",
    }
  }
}

export async function createEggProduction(eggProduction: EggProductionInput): Promise<ApiResponse<EggProduction>> {
  try {
    const url = `/api/proxy/EggProduction`

    const response = await fetch(url, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(eggProduction),
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[EggProduction] create error:", errorText)
      return {
        success: false,
        message: errorText || "Failed to create egg production",
      }
    }

    const data = await response.json()

    return {
      success: true,
      message: "Egg production created successfully",
      data: mapEggRow(data as Record<string, unknown>),
    }
  } catch (error) {
    console.error("[EggProduction] create error:", error)
    return {
      success: false,
      message: "Failed to create egg production",
    }
  }
}

export async function getEggProduction(id: number, userId: string, farmId: string): Promise<ApiResponse<EggProduction>> {
  try {
    const params = new URLSearchParams()
    params.append("userId", userId)
    params.append("farmId", farmId)

    const url = `/api/proxy/EggProduction/${id}?${params.toString()}`

    const response = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[EggProduction] get error:", errorText)
      return {
        success: false,
        message: "Failed to fetch egg production",
      }
    }

    const data = await response.json()

    return {
      success: true,
      message: "Egg production fetched successfully",
      data: mapEggRow(data as Record<string, unknown>),
    }
  } catch (error) {
    console.error("[EggProduction] get error:", error)
    return {
      success: false,
      message: "Failed to fetch egg production",
    }
  }
}

export async function updateEggProduction(id: number, eggProduction: Partial<EggProductionInput>): Promise<ApiResponse> {
  try {
    const url = `/api/proxy/EggProduction/${id}`

    const response = await fetch(url, {
      method: "PUT",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(eggProduction),
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[EggProduction] update error:", errorText)
      return {
        success: false,
        message: errorText || "Failed to update egg production",
      }
    }

    return {
      success: true,
      message: "Egg production updated successfully",
    }
  } catch (error) {
    console.error("[EggProduction] update error:", error)
    return {
      success: false,
      message: "Failed to update egg production. Network error.",
    }
  }
}
