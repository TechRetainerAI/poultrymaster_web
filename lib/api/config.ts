// API Configuration
// PoultryFarmAPI is the main .NET backend API
// Default: localhost:7190 (HTTPS) or localhost:5142 (HTTP) for local development
// Production: farmapi.techretainer.com or your production URL
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
// When using direct: https://farmapi.techretainer.com/api/MainFlockBatch
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
