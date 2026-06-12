export type FarmSummary = {
  farmId: string
  farmName?: string | null
  totalUsers: number
  staffCount: number
  hasPaidSubscription?: boolean
}

function normalizeBase(raw: string): string {
  const v = raw.trim()
  if (v.startsWith("http://") || v.startsWith("https://")) return v.replace(/\/+$/, "")
  return `https://${v.replace(/\/+$/, "")}`
}

export function loginApiBase(): string {
  const v = import.meta.env.VITE_LOGIN_API_URL as string | undefined
  if (!v) throw new Error("Set VITE_LOGIN_API_URL to your Login API origin (e.g. https://your-login-api.run.app)")
  return normalizeBase(v)
}

/** Farm API (PoultryMaster DB audit). Optional — omit if you only need the farm directory. */
export function farmApiBase(): string | null {
  const v = import.meta.env.VITE_FARM_API_URL as string | undefined
  if (!v?.trim()) return null
  return normalizeBase(v)
}

export type FarmAuditLogRow = {
  id: string
  userId: string
  userName: string
  farmId?: string
  action: string
  resource: string
  resourceId?: string | null
  details?: string | null
  ipAddress?: string | null
  userAgent?: string | null
  timestamp: string
  status: string
}

/** Recent dbo.AuditLogs across all farms (requires same JWT as directory: SystemAdmin or PlatformOwner). */
export async function fetchPlatformAuditLogs(token: string, take = 400): Promise<FarmAuditLogRow[]> {
  const base = farmApiBase()
  if (!base) throw new Error("VITE_FARM_API_URL is not set")
  const res = await fetch(`${base}/api/AuditLogs/platform?take=${take}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
  })
  if (res.status === 401 || res.status === 403) {
    throw new Error(
      "Farm API denied this token. Use SystemAdmin or PlatformOwner (same account as the directory). Ensure JWT:ValidIssuer / signing key match between Login and Farm API."
    )
  }
  if (!res.ok) {
    const t = await res.text()
    throw new Error(t || `Farm audit request failed (${res.status})`)
  }
  const data = (await res.json()) as FarmAuditLogRow[]
  return Array.isArray(data) ? data : []
}

function pick<T>(o: Record<string, unknown>, ...keys: string[]): T | undefined {
  for (const k of keys) {
    if (k in o && o[k] !== undefined && o[k] !== null) return o[k] as T
  }
  return undefined
}

export async function login(username: string, password: string): Promise<{ token: string; raw: unknown }> {
  const base = loginApiBase()
  const res = await fetch(`${base}/api/Authentication/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ username, password, rememberMe: true }),
  })
  const raw = await res.json().catch(() => ({}))
  const top = raw as Record<string, unknown>
  if (!res.ok) {
    const msg =
      pick<string>(top, "message", "Message") ||
      (typeof top.title === "string" ? top.title : null) ||
      `Login failed (${res.status})`
    throw new Error(msg)
  }
  const requires2FA = pick<boolean>(top, "requiresTwoFactor", "RequiresTwoFactor") === true
  if (requires2FA) {
    throw new Error(
      "This account uses two-factor authentication. Complete OTP in the main farm app, or use a developer portal account without 2FA."
    )
  }
  const isSuccess = pick<boolean>(top, "isSuccess", "IsSuccess") === true
  if (!isSuccess) {
    throw new Error(pick<string>(top, "message", "Message") || "Login failed")
  }
  const inner = (pick<Record<string, unknown>>(top, "response", "Response") ?? top) as Record<string, unknown>
  const access = pick<Record<string, unknown>>(inner, "accessToken", "AccessToken")
  const token = access ? pick<string>(access, "token", "Token") : undefined
  if (!token) throw new Error("Login response did not include an access token.")
  return { token, raw }
}

const ROLE_CLAIM_LONG = "http://schemas.microsoft.com/ws/2008/06/identity/claims/role"

function addRoleValues(set: Set<string>, v: unknown) {
  if (v == null) return
  if (Array.isArray(v)) {
    for (const x of v) set.add(String(x).trim())
    return
  }
  if (typeof v === "string" && v.trim()) set.add(v.trim())
}

/** All role claims from JWT (ASP.NET may emit one string, an array, or duplicate JSON keys). */
export function rolesFromJwt(token: string): string[] {
  try {
    const seg = token.split(".")[1]?.replace(/-/g, "+").replace(/_/g, "/")
    if (!seg) return []
    const raw = atob(seg)
    const set = new Set<string>()
    try {
      const payload = JSON.parse(raw) as Record<string, unknown>
      addRoleValues(set, payload[ROLE_CLAIM_LONG])
      addRoleValues(set, payload.role)
      addRoleValues(set, payload.Role)
      addRoleValues(set, payload.roles)
    } catch {
      /* invalid JSON — fall through to regex */
    }
    // Duplicate "role" keys in payload break JSON.parse; scrape long claim from raw segment.
    const escaped = ROLE_CLAIM_LONG.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    const re = new RegExp(`"${escaped}"\\s*:\\s*"([^"]*)"`, "g")
    let m: RegExpExecArray | null
    while ((m = re.exec(raw)) !== null) {
      if (m[1]) set.add(m[1].trim())
    }
    return [...set]
  } catch {
    return []
  }
}

export async function fetchFarms(token: string): Promise<FarmSummary[]> {
  const base = loginApiBase()
  const res = await fetch(`${base}/api/System/farms`, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
  })
  if (res.status === 401 || res.status === 403) {
    throw new Error("Not authorized. Sign in with the developer account (SystemAdmin or PlatformOwner role on Login API).")
  }
  if (!res.ok) {
    const t = await res.text()
    throw new Error(t || `Request failed (${res.status})`)
  }
  const data = (await res.json()) as FarmSummary[]
  return Array.isArray(data) ? data : []
}
