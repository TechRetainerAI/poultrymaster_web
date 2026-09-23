import { farmApiUrl, getAuthHeaders, getUserContext, readApiError } from "./config"

function activeFarmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

async function jget<T>(endpoint: string): Promise<T> {
  const farmId = activeFarmId()
  const sep = endpoint.includes("?") ? "&" : "?"
  const url = farmApiUrl(`${endpoint}${sep}farmId=${encodeURIComponent(farmId)}`)
  const res = await fetch(url, { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(await readApiError(res))
  return res.json()
}

async function jsend<T>(endpoint: string, method: string, body?: unknown): Promise<T> {
  const url = farmApiUrl(endpoint)
  const res = await fetch(url, { method, headers: getAuthHeaders(), body: body ? JSON.stringify(body) : undefined })
  if (!res.ok) throw new Error(await readApiError(res))
  const text = await res.text()
  return text ? JSON.parse(text) : ({} as T)
}

// Types
export interface HotelAssetCategory { hotelAssetCategoryId: number; farmId: string; categoryName: string; defaultUsefulLifeMonths: number; sortOrder: number; isActive: boolean }
export interface HotelCapitalAsset {
  hotelCapitalAssetId: number; farmId: string; assetName: string; assetNumber?: string | null
  hotelAssetCategoryId?: number | null; categoryName?: string | null; status: string
  acquisitionDate?: string | null; inServiceDate?: string | null; disposalDate?: string | null
  acquisitionCost: number; additionalCost: number; totalCapitalizedCost: number
  residualValue: number; usefulLifeMonths: number; depreciationMethod: string
  accumulatedDepreciation: number; currentBookValue: number
  supplier?: string | null; location?: string | null; serialNumber?: string | null; notes?: string | null
  createdBy?: string | null; createdAt: string; updatedAt?: string | null
  reversedBy?: string | null; reversedReason?: string | null; reversedAt?: string | null
}
export interface HotelCapitalAssetCost { hotelCapitalAssetCostId: number; amount: number; sourceType: string; description?: string | null; costDate?: string | null; status: string; createdAt: string }
export interface HotelAssetDepreciation { hotelAssetDepreciationId: number; hotelCapitalAssetId: number; assetName?: string | null; periodStart: string; amount: number; accumulatedAfter: number; bookValueAfter: number; sourceType: string; reason?: string | null; status: string; createdAt: string }
export interface HotelCapitalAssetSummary { totalAssets: number; activeAssets: number; draftAssets: number; totalAssetCost: number; accumulatedDepreciation: number; currentBookValue: number }
export interface HotelDepreciationRunResult { assetsProcessed: number; entriesCreated: number; totalAmount: number }
export interface HotelCapitalAssetInput { farmId: string; assetName: string; hotelAssetCategoryId?: number | null; acquisitionDate?: string | null; inServiceDate?: string | null; residualValue?: number; usefulLifeMonths?: number; amount?: number; supplier?: string | null; location?: string | null; serialNumber?: string | null; notes?: string | null }
export interface HotelCapitalAssetUpdateInput { farmId: string; assetName: string; hotelAssetCategoryId?: number | null; acquisitionDate?: string | null; inServiceDate?: string | null; residualValue?: number; usefulLifeMonths?: number; supplier?: string | null; location?: string | null; serialNumber?: string | null; notes?: string | null }

// Categories
export async function listHotelAssetCategories(): Promise<HotelAssetCategory[]> { return jget("/api/Hotel/assets/categories") }
export async function upsertHotelAssetCategory(input: Partial<HotelAssetCategory>): Promise<{ hotelAssetCategoryId: number }> { return jsend(`/api/Hotel/assets/categories?farmId=${encodeURIComponent(activeFarmId())}`, "POST", input) }

// Assets
export async function listHotelAssets(status?: string | null, categoryId?: number | null): Promise<HotelCapitalAsset[]> {
  let q = ""; if (status) q += `&status=${encodeURIComponent(status)}`; if (categoryId) q += `&categoryId=${categoryId}`
  return jget(`/api/Hotel/assets${q ? "?" + q.slice(1) : ""}`)
}
export async function getHotelAsset(id: number): Promise<HotelCapitalAsset | null> { return jget(`/api/Hotel/assets/${id}`) }
export async function getHotelAssetSummary(): Promise<HotelCapitalAssetSummary> { return jget("/api/Hotel/assets/summary") }
export async function createHotelAsset(input: HotelCapitalAssetInput): Promise<{ hotelCapitalAssetId: number }> { return jsend("/api/Hotel/assets", "POST", { ...input, farmId: activeFarmId() }) }
export async function updateHotelAsset(id: number, input: HotelCapitalAssetUpdateInput): Promise<void> { await jsend(`/api/Hotel/assets/${id}`, "PUT", { ...input, farmId: activeFarmId() }) }
export async function activateHotelAsset(id: number): Promise<void> { await jsend(`/api/Hotel/assets/${id}/activate?farmId=${encodeURIComponent(activeFarmId())}`, "POST") }
export async function addHotelAssetCost(assetId: number, amount: number, description?: string, costDate?: string): Promise<{ costId: number }> { return jsend(`/api/Hotel/assets/${assetId}/costs`, "POST", { farmId: activeFarmId(), amount, description, costDate }) }
export async function getHotelAssetCosts(assetId: number): Promise<HotelCapitalAssetCost[]> { return jget(`/api/Hotel/assets/${assetId}/costs`) }
export async function reverseHotelAssetCost(assetId: number, costId: number, reason?: string): Promise<void> { await jsend(`/api/Hotel/assets/${assetId}/costs/${costId}?farmId=${encodeURIComponent(activeFarmId())}${reason ? `&reason=${encodeURIComponent(reason)}` : ""}`, "DELETE") }
export async function disposeHotelAsset(id: number, disposalDate?: string, reason?: string): Promise<void> { await jsend(`/api/Hotel/assets/${id}/dispose`, "POST", { farmId: activeFarmId(), disposalDate, reason }) }
export async function reverseHotelAsset(id: number, reason?: string): Promise<void> { await jsend(`/api/Hotel/assets/${id}/reverse`, "POST", { farmId: activeFarmId(), reason }) }

// Depreciation
export async function listHotelDepreciation(assetId?: number | null): Promise<HotelAssetDepreciation[]> { const q = assetId ? `&assetId=${assetId}` : ""; return jget(`/api/Hotel/asset-depreciation${q ? "?" + q.slice(1) : ""}`) }
export async function generateHotelDepreciation(throughDate?: string, assetId?: number | null): Promise<HotelDepreciationRunResult> { return jsend("/api/Hotel/asset-depreciation/generate", "POST", { farmId: activeFarmId(), throughDate, assetId }) }
export async function reverseHotelDepreciation(entryId: number, reason?: string): Promise<void> { await jsend(`/api/Hotel/asset-depreciation/${entryId}/reverse`, "POST", { farmId: activeFarmId(), reason }) }
