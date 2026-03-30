import { getAuthHeaders } from "./config"

function buildAdminProxyUrl(endpoint: string): string {
  const clean = endpoint.startsWith("/") ? endpoint : `/${endpoint}`
  const proxyPath = clean.replace(/^\/api\//, "/")
  return `/api/proxy${proxyPath}`
}

function extractErrorMessage(body: unknown): string | null {
  if (!body || typeof body !== "object") return null
  const o = body as Record<string, unknown>
  const em = o.errorMessage ?? o.ErrorMessage
  if (em && typeof em === "object") {
    const inner = em as Record<string, unknown>
    const m = inner.message ?? inner.Message
    if (typeof m === "string") return m
  }
  if (typeof o.message === "string") return o.message
  if (typeof o.Message === "string") return o.Message
  // ASP.NET ProblemDetails / validation
  if (typeof o.title === "string" && o.title) return o.title
  const errs = o.errors ?? o.Errors
  if (errs && typeof errs === "object") {
    const first = Object.values(errs as Record<string, unknown>).find(
      (v) => Array.isArray(v) && v.length > 0 && typeof v[0] === "string"
    ) as string[] | undefined
    if (first?.[0]) return first[0]
  }
  return null
}

export interface StripeProductLike {
  id: string
  name?: string | null
  description?: string | null
  default_price?: string | { id?: string } | null
}

export interface StripeProductList {
  data?: StripeProductLike[]
}

export interface CreateCheckoutSessionResponse {
  sessionId: string
  publicKey: string
}

export interface ApiResult<T> {
  success: boolean
  data?: T
  message?: string
}

export function priceIdFromProduct(p: StripeProductLike): string | null {
  const dp = p.default_price
  if (!dp) return null
  if (typeof dp === "string") return dp
  if (typeof dp === "object" && dp?.id) return dp.id
  return null
}

export async function getStripeProducts(): Promise<ApiResult<StripeProductLike[]>> {
  try {
    const url = buildAdminProxyUrl("Payments/products")
    const res = await fetch(url, { method: "GET", headers: getAuthHeaders() })
    const text = await res.text()
    let body: unknown = null
    if (text?.trim()) {
      try {
        body = JSON.parse(text)
      } catch {
        body = { message: text }
      }
    }
    if (!res.ok) {
      return {
        success: false,
        message: extractErrorMessage(body) || text || `Request failed (${res.status})`,
      }
    }
    const list = body as StripeProductList
    const data = Array.isArray(list?.data) ? list.data : []
    return { success: true, data }
  } catch (e) {
    return {
      success: false,
      message: e instanceof Error ? e.message : "Failed to load products",
    }
  }
}

export interface SubscriptionTierRow {
  id: string
  maxBirds: number | null
  monthlyAmount: number
  label: string
}

export interface SubscriptionTiersResponse {
  trialDays: number
  currency: string
  note?: string
  tiers: SubscriptionTierRow[]
}

/** Matches Login API `POST api/Payments/create-checkout-session` body (camelCase JSON). */
export interface CreateCheckoutSessionBody {
  successUrl: string
  failureUrl: string
  priceId?: string
  totalBirds?: number
  /** When using priceId only; omit or true to apply configured farm trial. */
  includeTrialWithPriceId?: boolean
}

/**
 * Which subscription band applies for a headcount (same rules as Login API farm tiers).
 */
export function tierForBirdCount(
  birds: number,
  tiers: SubscriptionTierRow[]
): SubscriptionTierRow | null {
  const t1 = tiers.find((t) => t.id === "tier1")
  const t2 = tiers.find((t) => t.id === "tier2")
  const t3 = tiers.find((t) => t.id === "tier3")
  if (!t1 || !t2 || !t3) return null
  const max1 = typeof t1.maxBirds === "number" ? t1.maxBirds : 0
  if (birds <= max1) return t1
  const max2 = t2.maxBirds
  if (typeof max2 === "number" && birds <= max2) return t2
  return t3
}

export async function getSubscriptionTiers(): Promise<ApiResult<SubscriptionTiersResponse>> {
  try {
    const url = buildAdminProxyUrl("Payments/subscription-tiers")
    const res = await fetch(url, { method: "GET", headers: getAuthHeaders() })
    const text = await res.text()
    let body: unknown = null
    if (text?.trim()) {
      try {
        body = JSON.parse(text)
      } catch {
        body = { message: text }
      }
    }
    if (!res.ok) {
      return {
        success: false,
        message: extractErrorMessage(body) || text || `Request failed (${res.status})`,
      }
    }
    const raw = body as Record<string, unknown>
    const tiersRaw = raw.tiers ?? raw.Tiers
    const tiers = Array.isArray(tiersRaw)
      ? (tiersRaw as Record<string, unknown>[]).map((row) => ({
          id: String(row.id ?? row.Id ?? ""),
          maxBirds:
            row.maxBirds === null || row.MaxBirds === null
              ? null
              : Number(row.maxBirds ?? row.MaxBirds),
          monthlyAmount: Number(row.monthlyAmount ?? row.MonthlyAmount ?? 0),
          label: String(row.label ?? row.Label ?? ""),
        }))
      : []
    const data: SubscriptionTiersResponse = {
      trialDays: Number(raw.trialDays ?? raw.TrialDays ?? 0),
      currency: String(raw.currency ?? raw.Currency ?? "ghs"),
      note: typeof raw.note === "string" ? raw.note : typeof raw.Note === "string" ? raw.Note : undefined,
      tiers,
    }
    return { success: true, data }
  } catch (e) {
    return {
      success: false,
      message: e instanceof Error ? e.message : "Failed to load subscription tiers",
    }
  }
}

/** Farm plan: 7-day trial (server default) then monthly tier from total birds in active flocks. */
export async function createFarmTierCheckoutSession(
  totalBirds: number,
  successUrl: string,
  cancelUrl: string
): Promise<ApiResult<CreateCheckoutSessionResponse>> {
  try {
    const url = buildAdminProxyUrl("Payments/create-checkout-session")
    const body: CreateCheckoutSessionBody = {
      totalBirds: Math.max(0, Math.floor(totalBirds)),
      successUrl,
      failureUrl: cancelUrl,
    }
    const res = await fetch(url, {
      method: "POST",
      headers: getAuthHeaders(),
      body: JSON.stringify(body),
    })
    const text = await res.text()
    let body: unknown = null
    if (text?.trim()) {
      try {
        body = JSON.parse(text)
      } catch {
        body = { message: text }
      }
    }
    if (!res.ok) {
      return {
        success: false,
        message: extractErrorMessage(body) || text || `Request failed (${res.status})`,
      }
    }
    const o = body as Record<string, unknown>
    const sessionId = (o.sessionId ?? o.SessionId) as string | undefined
    const publicKey = (o.publicKey ?? o.PublicKey) as string | undefined
    if (!sessionId || !publicKey) {
      return { success: false, message: "Invalid checkout response from server" }
    }
    return { success: true, data: { sessionId, publicKey } }
  } catch (e) {
    return {
      success: false,
      message: e instanceof Error ? e.message : "Failed to start checkout",
    }
  }
}

export async function createCheckoutSession(
  priceId: string,
  successUrl: string,
  cancelUrl: string,
  options?: { includeTrialWithPriceId?: boolean }
): Promise<ApiResult<CreateCheckoutSessionResponse>> {
  try {
    const url = buildAdminProxyUrl("Payments/create-checkout-session")
    const includeTrial = options?.includeTrialWithPriceId !== false
    const body: CreateCheckoutSessionBody = {
      priceId: priceId.trim(),
      successUrl,
      failureUrl: cancelUrl,
      includeTrialWithPriceId: includeTrial,
    }
    const res = await fetch(url, {
      method: "POST",
      headers: getAuthHeaders(),
      body: JSON.stringify(body),
    })
    const text = await res.text()
    let body: unknown = null
    if (text?.trim()) {
      try {
        body = JSON.parse(text)
      } catch {
        body = { message: text }
      }
    }
    if (!res.ok) {
      return {
        success: false,
        message: extractErrorMessage(body) || text || `Request failed (${res.status})`,
      }
    }
    const o = body as Record<string, unknown>
    const sessionId = (o.sessionId ?? o.SessionId) as string | undefined
    const publicKey = (o.publicKey ?? o.PublicKey) as string | undefined
    if (!sessionId || !publicKey) {
      return { success: false, message: "Invalid checkout response from server" }
    }
    return { success: true, data: { sessionId, publicKey } }
  } catch (e) {
    return {
      success: false,
      message: e instanceof Error ? e.message : "Failed to start checkout",
    }
  }
}

export async function openCustomerPortal(returnUrl: string): Promise<ApiResult<string>> {
  try {
    const url = buildAdminProxyUrl("Payments/customer-portal")
    const res = await fetch(url, {
      method: "POST",
      headers: getAuthHeaders(),
      body: JSON.stringify({ returnUrl }),
    })
    const text = await res.text()
    let body: unknown = null
    if (text?.trim()) {
      try {
        body = JSON.parse(text)
      } catch {
        body = { message: text }
      }
    }
    if (!res.ok) {
      return {
        success: false,
        message: extractErrorMessage(body) || text || `Request failed (${res.status})`,
      }
    }
    const o = body as Record<string, unknown>
    const portalUrl = o.url as string | undefined
    if (!portalUrl || typeof portalUrl !== "string") {
      return { success: false, message: "Invalid billing portal response" }
    }
    return { success: true, data: portalUrl }
  } catch (e) {
    return {
      success: false,
      message: e instanceof Error ? e.message : "Failed to open billing portal",
    }
  }
}
