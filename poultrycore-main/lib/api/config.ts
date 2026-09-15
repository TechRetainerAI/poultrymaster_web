// API Configuration
// PoultryFarmAPI is the main .NET backend API
// Default: localhost:7190 (HTTPS) or localhost:5142 (HTTP) for local development
// Production: set NEXT_PUBLIC_* or rely on default-api-hosts (Cloud Run)
import { DEFAULT_LOGIN_API_HOST } from "@/lib/api/default-api-hosts"
function normalizeApiBase(raw?: string, fallback = 'localhost:7190') {
  const val = raw || fallback
  if (val.startsWith('http://') || val.startsWith('https://')) {
    return val
  }
  // Default to https for production URLs, http for localhost
  if (val.includes('localhost')) {
    return `http://${val}`
  }
  return `https://${val}`
}

// Direct API base URL (for server-side use)
const DIRECT_API_BASE_URL = normalizeApiBase(process.env.NEXT_PUBLIC_API_BASE_URL)

function normalizeLoginAdminBase(raw?: string, fallback = DEFAULT_LOGIN_API_HOST) {
  const val = raw || fallback
  if (val.startsWith('http://') || val.startsWith('https://')) {
    return val
  }
  return `https://${val}`
}

const LOGIN_ADMIN_DIRECT = normalizeLoginAdminBase(
  process.env.NEXT_PUBLIC_LOGIN_API_URL || process.env.NEXT_PUBLIC_ADMIN_API_URL
)

// Check if we should use proxy (browser) or direct URL (server)
const IS_BROWSER = typeof window !== 'undefined'

// Get the API base URL - use proxy in browser to avoid CORS, direct URL in server
function getApiBaseUrl(): string {
  // In the browser, use the Next.js proxy route to avoid CORS issues
  if (IS_BROWSER) {
    return '/api/proxy'
  }
  // On the server, use the direct API URL
  return DIRECT_API_BASE_URL
}

const API_BASE_URL = getApiBaseUrl()

// Helper function to construct API URLs correctly
// When using proxy: /api/proxy/MainFlockBatch (no /api/ prefix needed)
// When using direct: https://<farm-host>/api/MainFlockBatch
export function buildApiUrl(endpoint: string): string {
  const cleanEndpoint = endpoint.startsWith('/') ? endpoint : `/${endpoint}`
  
  if (IS_BROWSER) {
    // Using proxy - remove /api/ prefix from endpoint if present
    const proxyPath = cleanEndpoint.replace(/^\/api\//, '/')
    return `${API_BASE_URL}${proxyPath}`
  } else {
    // Using direct URL - ensure /api/ prefix is present
    const apiPath = cleanEndpoint.startsWith('/api/') ? cleanEndpoint : `/api${cleanEndpoint}`
    return `${API_BASE_URL}${apiPath}`
  }
}

// Backward-compatible helper used across existing API modules.
export function farmApiUrl(endpoint: string): string {
  return buildApiUrl(endpoint)
}

export function loginApiUrl(endpoint: string): string {
  const cleanEndpoint = endpoint.startsWith('/') ? endpoint : `/${endpoint}`
  if (IS_BROWSER) {
    const proxyPath = cleanEndpoint.replace(/^\/api\//, '/')
    return `/api/proxy${proxyPath}`
  }
  const apiPath = cleanEndpoint.startsWith('/api/') ? cleanEndpoint : `/api${cleanEndpoint}`
  return `${LOGIN_ADMIN_DIRECT}${apiPath}`
}

// Log the configuration on load (only in browser)
if (typeof window !== "undefined") {
  console.log("[v0] API Configuration:")
  console.log("[v0] - Base URL:", API_BASE_URL)
  console.log("[v0] - Environment variable:", process.env.NEXT_PUBLIC_API_BASE_URL)
}

export { API_BASE_URL }

export function getApiUrl(path: string): string {
  // If using proxy (browser), path should start with /api/... which we'll append directly
  // If using direct URL (server), we need to ensure the path starts with /api/...
  const cleanPath = path.startsWith('/') ? path : `/${path}`
  const url = `${API_BASE_URL}${cleanPath}`
  console.log("[v0] Constructed API URL:", url)
  return url
}

// Helper function to get user context for API calls
export function getUserContext(): { farmId: string; userId: string } {
  if (typeof window === "undefined") {
    return { farmId: "", userId: "" }
  }

  const farmId = localStorage.getItem("farmId") || ""
  const userId = localStorage.getItem("userId") || ""

  return { farmId, userId }
}

// Helper function to get auth headers
export function getAuthHeaders(): HeadersInit {
  const headers: HeadersInit = {
    "Content-Type": "application/json",
    Accept: "application/json",
  }

  if (typeof window !== "undefined") {
    const token = localStorage.getItem("auth_token")
    if (token) {
      headers.Authorization = `Bearer ${token}`
    }
  }

  return headers
}

// Helper function to validate required context
export function validateUserContext(): { isValid: boolean; farmId: string; userId: string } {
  const { farmId, userId } = getUserContext()
  
  if (!farmId || !userId) {
    console.error("[v0] Missing required user context - farmId:", farmId, "userId:", userId)
    return { isValid: false, farmId, userId }
  }
  
  return { isValid: true, farmId, userId }
}

// Helper function to fetch with timeout
export async function fetchWithTimeout(
  url: string,
  options: RequestInit = {},
  timeout: number = 5000
): Promise<Response> {
  const controller = new AbortController()
  const timeoutId = setTimeout(() => controller.abort(), timeout)

  try {
    const response = await fetch(url, {
      ...options,
      signal: controller.signal,
    })
    clearTimeout(timeoutId)
    return response
  } catch (error) {
    clearTimeout(timeoutId)
    if ((error as Error).name === 'AbortError') {
      console.warn(`[v0] Request timed out after ${timeout}ms:`, url)
    }
    throw error
  }
}

/**
 * Flatten an ASP.NET validation `errors` bag into one readable sentence.
 *
 * Shape is `{ "ImageUrl": ["The field ImageUrl must be ..."] }`, or `"$.price"`
 * for a JSON deserialisation failure. The field name is prepended only when the
 * message doesn't already contain it, so we don't produce "ImageUrl: The field
 * ImageUrl must be...".
 */
function flattenValidationErrors(errs: unknown): string {
  if (Array.isArray(errs)) return errs.map(String).join(" ")
  if (!errs || typeof errs !== "object") return ""
  return Object.entries(errs as Record<string, unknown>)
    .map(([field, messages]) => {
      const text = (Array.isArray(messages) ? messages.map(String).join(" ") : String(messages)).trim()
      const name = field.replace(/^\$\.?/, "").trim()
      return name && text && !text.includes(name) ? `${name}: ${text}` : text
    })
    .filter(Boolean)
    .join(" ")
}

// Extract the REAL backend error from a failed Response so callers surface it
// instead of a generic "request failed" red card. The APIs return { message }
// (BadRequest) or a validation errors bag; SqlException surfaces as { message }
// via GlobalExceptionMiddleware. Ignores HTML error pages.
export async function readApiError(res: Response, fallback = "Request failed"): Promise<string> {
  let text = ""
  try { text = await res.text() } catch { /* body already consumed / empty */ }
  if (text) {
    const t = text.trim()
    if (!t.startsWith("<")) {
      try {
        const d: any = JSON.parse(t)
        // Order matters. An [ApiController] model-validation failure is a
        // ValidationProblemDetails whose `title` is always the useless constant
        // "One or more validation errors occurred." — the field that actually
        // failed is only in `errors`. Reading `title` first threw that away and
        // left users staring at a message that named nothing, so `errors` wins
        // and `title` is the last resort.
        const msg = String(
          flattenValidationErrors(d?.errors) ||
          d?.message || d?.Message || d?.error || d?.title || ""
        ).trim()
        if (msg) return msg
      } catch { return t }        // non-JSON, non-HTML → the text itself is the message
    }
  }
  return res.status === 401 ? "Your session has expired. Please log in again." : `${fallback} (${res.status})`
}
