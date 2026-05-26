import { getAuthHeaders, loginApiUrl } from "./config"

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
  const res = await fetch(loginApiUrl("/Companies/mine"), { headers: getAuthHeaders() })
  if (!res.ok) throw new Error(`getMyCompanies failed: ${res.status}`)
  return lower<Company[]>(await res.json())
}

export async function createCompany(input: CreateCompanyInput): Promise<Company> {
  const res = await fetch(loginApiUrl("/Companies"), {
    method: "POST",
    headers: getAuthHeaders(),
    body: JSON.stringify({
      Name: input.name,
      Type: input.type,
      Email: input.email ?? null,
      PhoneNumber: input.phoneNumber ?? null,
    }),
  })
  if (!res.ok) {
    const t = await res.text()
    throw new Error(`createCompany failed: ${res.status} ${t}`)
  }
  return lower<Company>(await res.json())
}

export async function switchCompany(farmId: string): Promise<SwitchFarmResponse> {
  const res = await fetch(loginApiUrl("/Companies/switch"), {
    method: "POST",
    headers: getAuthHeaders(),
    body: JSON.stringify({ FarmId: farmId }),
  })
  if (!res.ok) {
    const t = await res.text()
    throw new Error(`switchCompany failed: ${res.status} ${t}`)
  }
  return lower<SwitchFarmResponse>(await res.json())
}
