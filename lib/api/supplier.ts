import { DEFAULT_FARM_API_HOST } from "@/lib/api/default-api-hosts"
import { buildApiUrl, getAuthHeaders } from "./config"

function normalizeApiBase(raw?: string, fallback = DEFAULT_FARM_API_HOST) {
  const val = raw || fallback
  return val.startsWith("http://") || val.startsWith("https://") ? val : `https://${val}`
}

const DIRECT_API_BASE_URL = normalizeApiBase(process.env.NEXT_PUBLIC_API_BASE_URL)
const IS_BROWSER = typeof window !== "undefined"

export interface Supplier {
  supplierId: number
  farmId: string
  userId: string
  name: string
  contactEmail: string
  contactPhone: string
  address: string
  city: string
  createdDate: string
}

export interface SupplierInput {
  farmId: string
  userId: string
  name: string
  contactEmail?: string
  contactPhone: string
  address: string
  city: string
}

export interface ApiResponse<T = unknown> {
  success: boolean
  data?: T
  message?: string
}

function mapSupplier(raw: Record<string, unknown>): Supplier {
  return {
    supplierId: Number(raw.supplierId ?? raw.SupplierId ?? 0),
    farmId: String(raw.farmId ?? raw.FarmId ?? ""),
    userId: String(raw.userId ?? raw.UserId ?? ""),
    name: String(raw.name ?? raw.Name ?? ""),
    contactEmail: String(raw.contactEmail ?? raw.ContactEmail ?? ""),
    contactPhone: String(raw.contactPhone ?? raw.ContactPhone ?? ""),
    address: String(raw.address ?? raw.Address ?? ""),
    city: String(raw.city ?? raw.City ?? ""),
    createdDate: String(raw.createdDate ?? raw.CreatedDate ?? ""),
  }
}

export async function getSupplier(id: number, userId: string, farmId: string): Promise<ApiResponse<Supplier>> {
  try {
    const endpoint = `/Supplier/${id}?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    const url = IS_BROWSER ? buildApiUrl(endpoint) : `${DIRECT_API_BASE_URL}/api${endpoint}`
    const response = await fetch(url, { headers: getAuthHeaders() })
    if (!response.ok) {
      const text = await response.text()
      return { success: false, message: text || `Failed to fetch supplier (${response.status})` }
    }
    const data = (await response.json()) as Record<string, unknown>
    return { success: true, data: mapSupplier(data) }
  } catch (e) {
    return { success: false, message: (e as Error)?.message || "Network error" }
  }
}

export async function getSuppliers(userId: string, farmId: string): Promise<ApiResponse<Supplier[]>> {
  try {
    const endpoint = `/Supplier?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    const url = IS_BROWSER ? buildApiUrl(endpoint) : `${DIRECT_API_BASE_URL}/api${endpoint}`
    const response = await fetch(url, { headers: getAuthHeaders() })
    if (!response.ok) {
      const text = await response.text()
      return { success: false, message: text || `Failed to fetch suppliers (${response.status})` }
    }
    const data = await response.json()
    const arr = Array.isArray(data) ? data : []
    return { success: true, data: arr.map((x) => mapSupplier(x as Record<string, unknown>)) }
  } catch (e) {
    return { success: false, message: (e as Error)?.message || "Network error" }
  }
}

export async function createSupplier(input: SupplierInput): Promise<ApiResponse<void>> {
  try {
    const url = IS_BROWSER ? buildApiUrl("/Supplier") : `${DIRECT_API_BASE_URL}/api/Supplier`
    const response = await fetch(url, {
      method: "POST",
      headers: getAuthHeaders(),
      body: JSON.stringify({
        ...input,
        supplierId: 0,
        contactEmail: input.contactEmail?.trim() || null,
        createdDate: new Date().toISOString(),
      }),
    })
    if (!response.ok) {
      return { success: false, message: (await response.text()) || "Failed to create supplier" }
    }
    return { success: true }
  } catch (e) {
    return { success: false, message: (e as Error)?.message || "Network error" }
  }
}

export async function updateSupplier(id: number, input: SupplierInput): Promise<ApiResponse<void>> {
  try {
    const url = IS_BROWSER ? buildApiUrl(`/Supplier/${id}`) : `${DIRECT_API_BASE_URL}/api/Supplier/${id}`
    const response = await fetch(url, {
      method: "PUT",
      headers: getAuthHeaders(),
      body: JSON.stringify({
        ...input,
        supplierId: id,
        contactEmail: input.contactEmail?.trim() || null,
      }),
    })
    if (!response.ok) {
      return { success: false, message: (await response.text()) || "Failed to update supplier" }
    }
    return { success: true }
  } catch (e) {
    return { success: false, message: (e as Error)?.message || "Network error" }
  }
}

export async function deleteSupplier(id: number, userId: string, farmId: string): Promise<ApiResponse<void>> {
  try {
    const endpoint = `/Supplier/${id}?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    const url = IS_BROWSER ? buildApiUrl(endpoint) : `${DIRECT_API_BASE_URL}/api${endpoint}`
    const response = await fetch(url, { method: "DELETE", headers: getAuthHeaders() })
    if (!response.ok) {
      return { success: false, message: (await response.text()) || "Failed to delete supplier" }
    }
    return { success: true }
  } catch (e) {
    return { success: false, message: (e as Error)?.message || "Network error" }
  }
}
