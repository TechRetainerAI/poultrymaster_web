import { getAuthHeaders, loginApiUrl } from "./config"
import { tryRefreshAccessToken } from "./auth"

// 60-minute access tokens expire while the user is still on the page. Without
// a refresh-then-retry wrapper the next /Companies/* call surfaces a hard 401
// that only goes away after a manual logout/login. This helper does one
// refresh attempt before giving up — it leaves the original error in place
// when refresh fails so the caller's existing error path still fires.
async function loginApiFetch(path: string, init?: RequestInit): Promise<Response> {
  const url = loginApiUrl(path)
  const first = await fetch(url, { ...init, headers: { ...getAuthHeaders(), ...(init?.headers ?? {}) } })
  if (first.status !== 401) return first

  const refreshed = await tryRefreshAccessToken()
  if (!refreshed) return first

  // Rebuild headers so we send the fresh Bearer token, not the cached one.
  return fetch(url, { ...init, headers: { ...getAuthHeaders(), ...(init?.headers ?? {}) } })
}

export type CompanyType = "Poultry" | "Water" | "Generic" | string

export interface Company {
  farmId: string
  name: string
  type: CompanyType
  email?: string | null
  phoneNumber?: string | null
  ownerUserId?: string | null
  role: "Admin" | "Staff" | string
  createdAt: string
  updatedAt?: string | null
}

export interface CreateCompanyInput {
  name: string
  type: CompanyType
  email?: string
  phoneNumber?: string
}

export interface SwitchFarmResponse {
  accessToken: { token: string; expiryTokenDate: string }
  refreshToken: { token: string; expiryTokenDate: string }
  userId: string
  username: string
  isStaff: boolean
  farmId: string
  farmName: string
  isSubscriber: boolean
}

// Backend returns PascalCase via LoginResponse; defensive PascalCase ⇄ camelCase.
function lower<T = any>(obj: any): T {
  if (obj === null || obj === undefined || typeof obj !== "object") return obj as T
  if (Array.isArray(obj)) return obj.map(lower) as unknown as T
  const out: any = {}
  for (const k of Object.keys(obj)) {
    const lk = k.charAt(0).toLowerCase() + k.slice(1)
    out[lk] = lower(obj[k])
  }
  return out as T
}

export async function getMyCompanies(): Promise<Company[]> {
  const res = await loginApiFetch("/Companies/mine")
  if (!res.ok) {
    throw new Error(res.status === 401
      ? "Your session has expired. Please log in again."
      : `getMyCompanies failed: ${res.status}`)
  }
  return lower<Company[]>(await res.json())
}

export async function createCompany(input: CreateCompanyInput): Promise<Company> {
  const res = await loginApiFetch("/Companies", {
    method: "POST",
    body: JSON.stringify({
      Name: input.name,
      Type: input.type,
      Email: input.email ?? null,
      PhoneNumber: input.phoneNumber ?? null,
    }),
  })
  if (!res.ok) {
    const t = await res.text()
    throw new Error(res.status === 401
      ? "Your session has expired. Please log in again."
      : `createCompany failed: ${res.status} ${t}`)
  }
  return lower<Company>(await res.json())
}

export async function switchCompany(farmId: string): Promise<SwitchFarmResponse> {
  const res = await loginApiFetch("/Companies/switch", {
    method: "POST",
    body: JSON.stringify({ FarmId: farmId }),
  })
  if (!res.ok) {
    const t = await res.text()
    throw new Error(res.status === 401
      ? "Your session has expired. Please log in again."
      : `switchCompany failed: ${res.status} ${t}`)
  }
  return lower<SwitchFarmResponse>(await res.json())
}
