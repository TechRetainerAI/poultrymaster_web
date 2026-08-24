import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { forceReauth } from "./session-expiry"

// Poultry Company profile + setup — the counterpart of lib/api/water.ts's
// "W5: Company profile + setup" section, backed by migration 212's
// sppoultrycompany_* functions via /api/Poultry/company.
//
// Before this existed, the poultry farm profile lived entirely in browser
// localStorage (app/settings/page.tsx), so nothing persisted across devices
// and the keys were not namespaced per company.

// ---------------------------------------------------------------------------
// helpers — same shape as lib/api/poultry-distribution.ts
// ---------------------------------------------------------------------------
function activeFarmId(): string {
  const { farmId } = getUserContext()
  return farmId || ""
}

async function jget<T>(path: string): Promise<T> {
  const res = await fetch(farmApiUrl(path), { headers: getAuthHeaders() })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(`GET ${path} failed (${res.status}): ${t || res.statusText}`)
  }
  return (await res.json()) as T
}

async function jsend<T>(path: string, method: "POST" | "PUT" | "DELETE", body?: any): Promise<T> {
  const init: RequestInit = { method, headers: getAuthHeaders() }
  if (body !== undefined) init.body = JSON.stringify(body)
  const res = await fetch(farmApiUrl(path), init)
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const t = await res.text().catch(() => "")
    throw new Error(`${method} ${path} failed (${res.status}): ${t || res.statusText}`)
  }
  if (res.status === 204) return undefined as unknown as T
  const text = await res.text()
  return text ? (JSON.parse(text) as T) : (undefined as unknown as T)
}

// ---------------------------------------------------------------------------
// types
// ---------------------------------------------------------------------------

/** Layers (eggs) | Broilers (meat) | Both. Poultry's answer to WaterBusinessType. */
export const POULTRY_BUSINESS_TYPES = ["Layers", "Broilers", "Both"] as const
export type PoultryBusinessType = (typeof POULTRY_BUSINESS_TYPES)[number]

/** How the birds are housed. Poultry's answer to WaterSourceType. */
export const POULTRY_HOUSING_SYSTEMS = ["DeepLitter", "BatteryCage", "FreeRange", "Mixed"] as const
export type PoultryHousingSystem = (typeof POULTRY_HOUSING_SYSTEMS)[number]

/** Display labels for the housing values, which are stored without spaces. */
export const POULTRY_HOUSING_LABELS: Record<PoultryHousingSystem, string> = {
  DeepLitter: "Deep litter",
  BatteryCage: "Battery cage",
  FreeRange: "Free range",
  Mixed: "Mixed",
}

export interface PoultryCompanyProfile {
  poultryCompanyProfileId: number
  farmId: string
  brandName?: string | null
  businessType: string
  farmSiteAddress?: string | null
  mainLocation?: string | null
  housingSystem: string
  defaultCurrency: string
  defaultCrateEggCount: number
  totalCapacity?: number | null
  operatingHours?: string | null
  ownerName?: string | null
  phoneNumber?: string | null
  email?: string | null
  notes?: string | null
  createdAt: string
  updatedAt?: string | null
}

export interface PoultryCompanySetupInput {
  brandName?: string | null
  businessType?: string
  farmSiteAddress?: string | null
  mainLocation?: string | null
  housingSystem?: string
  defaultCurrency?: string
  defaultCrateEggCount?: number
  totalCapacity?: number | null
  operatingHours?: string | null
  ownerName?: string | null
  phoneNumber?: string | null
  email?: string | null
  notes?: string | null
}

// ---------------------------------------------------------------------------
// calls
// ---------------------------------------------------------------------------

/**
 * 404 from this endpoint means "no poultry profile set up yet" — the controller
 * returns NotFound() when the row is absent. Returned as null so the setup page
 * can render an empty form instead of an error.
 */
export const getPoultryCompanyProfile = async (): Promise<PoultryCompanyProfile | null> => {
  try {
    return await jget<PoultryCompanyProfile>(
      `/Poultry/company?farmId=${encodeURIComponent(activeFarmId())}`,
    )
  } catch (e) {
    if (e instanceof Error && /\(404\)/.test(e.message)) return null
    throw e
  }
}

export const setupPoultryCompany = (input: PoultryCompanySetupInput) =>
  jsend<PoultryCompanyProfile>(`/Poultry/company/setup`, "POST", { ...input, farmId: activeFarmId() })

export const updatePoultryCompanyProfile = (input: PoultryCompanySetupInput) =>
  jsend<PoultryCompanyProfile>(
    `/Poultry/company?farmId=${encodeURIComponent(activeFarmId())}`,
    "PUT",
    input,
  )
