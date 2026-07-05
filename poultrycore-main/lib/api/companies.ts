import { getAuthHeaders, loginApiUrl, buildApiUrl, readApiError } from "./config"
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
  if (!res.ok) throw new Error(await readApiError(res, "Couldn't load your companies"))
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
  if (!res.ok) throw new Error(await readApiError(res, "Couldn't create the company"))
  return lower<Company>(await res.json())
}

// Doc 3 §8: edit a company (name/email/phone). Type is immutable after creation.
export interface UpdateCompanyInput {
  name: string
  email?: string | null
  phoneNumber?: string | null
}
export async function updateCompany(farmId: string, input: UpdateCompanyInput): Promise<Company> {
  const res = await loginApiFetch(`/Companies/${encodeURIComponent(farmId)}`, {
    method: "PUT",
    body: JSON.stringify({
      Name: input.name,
      Email: input.email ?? null,
      PhoneNumber: input.phoneNumber ?? null,
    }),
  })
  if (!res.ok) throw new Error(await readApiError(res, "Couldn't update the company"))
  return lower<Company>(await res.json())
}

// Email a "company created" confirmation. Call after createCompany. The backend
// returns 200 with { success, message } even on send failure.
export async function sendCompanyWelcomeEmail(input: { email: string; companyName?: string; companyType?: string }): Promise<{ success: boolean; message?: string }> {
  try {
    // Email lives on the Farm API EmailController (the proxy routes /Email/* there),
    // so call it directly via the Farm proxy path — not loginApiFetch.
    const res = await fetch(buildApiUrl("/Email/send-welcome"), {
      method: "POST",
      headers: getAuthHeaders(),
      body: JSON.stringify({
        Email: input.email,
        CompanyName: input.companyName ?? null,
        CompanyType: input.companyType ?? null,
      }),
    })
    const text = await res.text()
    let data: any = {}
    try { data = text ? JSON.parse(text) : {} } catch { /* non-JSON */ }
    if (!res.ok) return { success: false, message: data.message || `HTTP ${res.status}` }
    return { success: data.success !== false, message: data.message }
  } catch (e) {
    return { success: false, message: e instanceof Error ? e.message : "Network error" }
  }
}

// Pick the company that matches the user's signed-in farmId. Falls back to the
// first company so newly-promoted users (FarmId in JWT may briefly diverge from
// UserFarms membership) still land somewhere usable instead of getting stuck on
// the Poultry default. Used by the login + 2FA pages right after authentication
// to populate auth-store.activeFarmType before routing — without this, the
// sidebar/dashboard renders the Poultry nav for a Water/Generic signup until
// the user manually opens the company switcher.
export async function resolveActiveCompanyForUser(farmId: string | null): Promise<Company | null> {
  try {
    const list = await getMyCompanies()
    if (!list.length) return null
    const match = farmId ? list.find((c) => c.farmId === farmId) : undefined
    return match ?? list[0]
  } catch {
    return null
  }
}

// Map a CompanyType to the right "home" route. Mirrors the routing the
// company-switcher does on switch (see components/dashboard/company-switcher.tsx).
export function dashboardHomeForType(type: CompanyType | null | undefined): string {
  if (type === "Water") return "/water-dashboard"
  if (type === "Generic") return "/generic-dashboard"
  return "/dashboard"
}

export async function switchCompany(farmId: string): Promise<SwitchFarmResponse> {
  const res = await loginApiFetch("/Companies/switch", {
    method: "POST",
    body: JSON.stringify({ FarmId: farmId }),
  })
  if (!res.ok) throw new Error(await readApiError(res, "Couldn't switch company"))
  return lower<SwitchFarmResponse>(await res.json())
}
