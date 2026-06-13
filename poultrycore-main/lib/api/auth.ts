// API utility functions for authentication

import { DEFAULT_LOGIN_API_HOST } from "@/lib/api/default-api-hosts"

// Use Admin API URL for authentication endpoints
// For local development with ngrok, you may need to:
// 1. Run the backend locally and set NEXT_PUBLIC_ADMIN_API_URL to http://localhost:PORT
// 2. Or update the production backend CORS to allow your ngrok domain
// Example: NEXT_PUBLIC_ADMIN_API_URL=http://localhost:7010
function normalizeAdminBase(raw?: string, fallback = DEFAULT_LOGIN_API_HOST) {
  const val = raw || fallback
  return val.startsWith('http://') || val.startsWith('https://') ? val : `https://${val}`
}

const API_BASE_URL = normalizeAdminBase(
  process.env.NEXT_PUBLIC_LOGIN_API_URL || process.env.NEXT_PUBLIC_ADMIN_API_URL
)

/**
 * Browser: same-origin `/api/proxy/...` → Next.js forwards to Admin API (no CORS).
 * Server: direct Admin URL (SSR / no browser CORS).
 */
export function getAuthenticationApiUrl(pathSegment: string): string {
  const seg = pathSegment.replace(/^\/+/, "").replace(/\/+$/, "")
  if (typeof window !== "undefined") {
    return `/api/proxy/Authentication/${seg}`
  }
  return `${API_BASE_URL}/api/Authentication/${seg}`
}

/**
 * Diagnostic flow text (browser → Next proxy → Login API). Useful for support
 * but James reported (2026-05-30) that end users were seeing the whole thing
 * in the login error toast. We now route this to console.error only — the
 * UI shows a short friendly message via friendlyLoginError() below.
 */
function loginUpstreamDiagnostics(): string {
  const upstream = API_BASE_URL
  if (typeof window === "undefined") {
    return `Upstream Login API URL: ${upstream}`
  }
  const o = window.location.origin
  return (
    `Login flow: browser → ${o}/api/proxy/Authentication/login → server forwards to:\n${upstream}\n\n` +
    `Checks:\n` +
    `• Redeploy the frontend after code/env changes (Next must serve /api/proxy).\n` +
    `• On Render/hosting: set NEXT_PUBLIC_ADMIN_API_URL to your Login Cloud Run URL (full https://….run.app).\n` +
    `• GCP → Cloud Run → Login service → Logs: fix startup if the container crashes (DB connection string, etc.).\n` +
    `• From your PC: curl -sI "${upstream}/" — expect HTTP 200 or 404 from the app, not timeout.`
  )
}

/**
 * Maps an internal error reason to a short, user-friendly toast message.
 * The verbose technical diagnostic (loginUpstreamDiagnostics) is logged to
 * the browser console instead — support can grab it from DevTools when
 * needed without showing it to end users.
 */
type LoginErrorReason =
  | "timeout"
  | "network"
  | "empty-body"
  | "invalid-json"
  | "non-json"
  | "server-500"
  | "upstream-5xx"
function friendlyLoginError(reason: LoginErrorReason): string {
  switch (reason) {
    case "timeout":
      return "The server is taking too long to respond. Please try again in a moment."
    case "network":
      return "Couldn't reach the login service. Please check your internet connection and try again."
    case "empty-body":
    case "invalid-json":
    case "non-json":
    case "server-500":
    case "upstream-5xx":
      return "The login service is having trouble right now. Please try again in a minute. If it keeps happening, contact support."
  }
}
function logLoginDiagnostic(label: string, extra?: unknown) {
  // Single place to dump the verbose flow + any extra context for support.
  // eslint-disable-next-line no-console
  console.error(`[Login diagnostic] ${label}\n${loginUpstreamDiagnostics()}`, extra ?? "")
}

export interface RegisterData {
  farmName: string
  username: string
  email: string
  password: string
  firstName: string
  lastName: string
  roles: string[]
  phoneNumber: string
  companyType: "Poultry" | "Water"
}

export interface LoginData {
  username: string
  password: string
  rememberMe: boolean
}

export interface ForgotPasswordData {
  email: string
}

export interface ResetPasswordData {
  email: string
  password: string
  confirmPassword: string
  token: string
}

export interface ConfirmEmailData {
  email: string
  token: string
}

export interface ApiResponse<T = any> {
  success: boolean
  data?: T
  message?: string
  errors?: string[]
}

function toBoolean(value: unknown): boolean | undefined {
  if (typeof value === "boolean") return value
  if (typeof value === "number") {
    if (value === 1) return true
    if (value === 0) return false
  }
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase()
    if (normalized === "true" || normalized === "1") return true
    if (normalized === "false" || normalized === "0") return false
  }
  return undefined
}

function unwrapPermissionsJson(source: unknown): unknown {
  if (typeof source === "string" && source.trim()) {
    try {
      return JSON.parse(source)
    } catch {
      return null
    }
  }
  return source
}

function extractFromFeatureRecord(src: Record<string, unknown>): Record<string, boolean> {
  const pick = (a: unknown, b: unknown, c: unknown, d: unknown, e: unknown, f: unknown) =>
    toBoolean(a) ?? toBoolean(b) ?? toBoolean(c) ?? toBoolean(d) ?? toBoolean(e) ?? toBoolean(f)

  const canEnterSales = pick(src.canEnterSales, src.CanEnterSales, src.canViewSales, src.CanViewSales, src.viewSales, src.ViewSales)
  const canEnterExpenses = pick(src.canEnterExpenses, src.CanEnterExpenses, src.canViewExpenses, src.CanViewExpenses, src.viewExpenses, src.ViewExpenses)
  const canViewCashLedger = pick(src.canViewCashLedger, src.CanViewCashLedger, src.canViewCash, src.CanViewCash, src.viewCash, src.ViewCash)
  const canSeeEmployees = pick(src.canSeeEmployees, src.CanSeeEmployees, src.seeEmployees, src.SeeEmployees, src.viewEmployees, src.ViewEmployees)
  const canViewReports = pick(src.canViewReports, src.CanViewReports, src.viewReports, src.ViewReports, src.reports, src.Reports)
  const canViewFinancial = pick(src.canViewFinancial, src.CanViewFinancial, src.viewFinancial, src.ViewFinancial, src.financial, src.Financial)
  const canViewCustomers = pick(
    src.canViewCustomers,
    src.CanViewCustomers,
    src.viewCustomers,
    src.ViewCustomers,
    src.customers,
    src.Customers
  )
  const canViewActivityLog = pick(src.canViewActivityLog, src.CanViewActivityLog, src.viewActivityLog, src.ViewActivityLog, src.activityLog, src.ActivityLog)
  const canViewSettings = pick(src.canViewSettings, src.CanViewSettings, src.viewSettings, src.ViewSettings, src.settings, src.Settings)

  const normalized: Record<string, boolean> = {}
  if (canEnterSales !== undefined) normalized.canEnterSales = canEnterSales
  if (canEnterExpenses !== undefined) normalized.canEnterExpenses = canEnterExpenses
  if (canViewCashLedger !== undefined) normalized.canViewCashLedger = canViewCashLedger
  if (canSeeEmployees !== undefined) normalized.canSeeEmployees = canSeeEmployees
  if (canViewReports !== undefined) normalized.canViewReports = canViewReports
  if (canViewFinancial !== undefined) normalized.canViewFinancial = canViewFinancial
  if (canViewCustomers !== undefined) normalized.canViewCustomers = canViewCustomers
  if (canViewActivityLog !== undefined) normalized.canViewActivityLog = canViewActivityLog
  if (canViewSettings !== undefined) normalized.canViewSettings = canViewSettings
  return normalized
}

/**
 * Merge feature flags from any shape the Login API returns (string JSON, nested permissions, featureAccess).
 * Later sources override earlier so FeaturePermissions is authoritative when listed last.
 */
function extractFeaturePermissions(userData: any): Record<string, boolean> | null {
  const merged: Record<string, boolean> = {}

  const tryMerge = (raw: unknown) => {
    const unwrapped = unwrapPermissionsJson(raw) ?? raw
    if (!unwrapped || typeof unwrapped !== "object" || Array.isArray(unwrapped)) return
    const partial = extractFromFeatureRecord(unwrapped as Record<string, unknown>)
    Object.assign(merged, partial)
  }

  tryMerge(userData?.permissions ?? userData?.Permissions)
  tryMerge(userData?.permissions?.featurePermissions ?? userData?.Permissions?.FeaturePermissions)
  tryMerge(userData?.featureAccess ?? userData?.FeatureAccess)
  tryMerge(userData?.featurePermissions ?? userData?.FeaturePermissions)

  return Object.keys(merged).length > 0 ? merged : null
}

/** Persist feature flags after login / 2FA. Staff with no explicit JSON get {} (deny-by-default in UI). */
export function persistFeaturePermissionsFromUserData(userData: any, isStaff: boolean): void {
  if (typeof window === "undefined") return
  const featurePermissions = extractFeaturePermissions(userData)
  if (featurePermissions && Object.keys(featurePermissions).length > 0) {
    localStorage.setItem("featurePermissions", JSON.stringify(featurePermissions))
  } else if (isStaff) {
    localStorage.setItem("featurePermissions", JSON.stringify({}))
  } else {
    localStorage.removeItem("featurePermissions")
  }
}

/**
 * Reload feature permissions from the Login API (same source as login response) and update localStorage.
 * Call after load so staff see admin changes without re-login. Uses same-origin proxy.
 */
export async function refreshFeaturePermissionsFromServer(): Promise<void> {
  if (typeof window === "undefined") return
  const username = localStorage.getItem("username")
  if (!username?.trim()) return

  try {
    const token = localStorage.getItem("auth_token")
    const res = await fetch(
      `/api/proxy/UserProfile/findByUserName?normalizedUserName=${encodeURIComponent(username.trim().toUpperCase())}`,
      {
        headers: {
          accept: "application/json",
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
      }
    )
    if (!res.ok) return
    const text = await res.text()
    if (!text?.trim()) return
    let data: any
    try {
      data = JSON.parse(text)
    } catch {
      console.warn("[permissions] refreshFeaturePermissionsFromServer: non-JSON response")
      return
    }
    const isStaff = data?.isStaff === true || data?.IsStaff === true
    persistFeaturePermissionsFromUserData(data, isStaff)
  } catch (e) {
    console.warn("[permissions] refreshFeaturePermissionsFromServer failed:", e)
  }
}

// Register new user
export async function register(data: RegisterData): Promise<ApiResponse> {
  try {
    const response = await fetch(getAuthenticationApiUrl("register"), {
      method: "POST",
      headers: {
        accept: "*/*",
        "Content-Type": "application/json",
      },
      body: JSON.stringify(data),
    })

    const result = await response.json()

    if (!response.ok) {
      // ASP.NET [ApiController] auto-validation returns ProblemDetails:
      // { title: "One or more validation errors occurred.", errors: { field: [..] } }
      // — pick `title` so the user sees a real message instead of "Registration failed".
      return {
        success: false,
        message: result.message || result.title || "Registration failed",
        errors: result.errors,
      }
    }

    return {
      success: true,
      data: result,
      message: "Registration successful",
    }
  } catch (error) {
    return {
      success: false,
      message: "Network error. Please try again.",
    }
  }
}

/**
 * Try to swap the stored refresh token for a fresh access token.
 *
 * Why this exists: getMyCompanies and other plain-fetch helpers don't go through
 * the axios refresh interceptor, so when the 60-minute access token expires they
 * surface a hard "401" until the user manually logs out and back in. This helper
 * lets fetch-based helpers attempt one refresh on 401 before giving up.
 *
 * Single-flight: if a refresh is already in progress, callers await the same
 * promise so we never POST refresh-token twice in parallel.
 */
let refreshInFlight: Promise<boolean> | null = null
export function tryRefreshAccessToken(): Promise<boolean> {
  if (typeof window === "undefined") return Promise.resolve(false)
  if (refreshInFlight) return refreshInFlight

  refreshInFlight = (async () => {
    try {
      const accessToken = localStorage.getItem("auth_token") || ""
      const refreshToken = localStorage.getItem("refresh_token") || ""
      if (!accessToken || !refreshToken) return false

      // Backend expects the full LoginResponse shape (TokenType objects, not raw
      // strings). ExpiryTokenDate is checked with `AND token mismatch`, so as
      // long as the refresh token matches user.RefreshToken the date is ignored.
      const res = await fetch(getAuthenticationApiUrl("Refresh-Token"), {
        method: "POST",
        headers: { "Content-Type": "application/json", accept: "*/*" },
        body: JSON.stringify({
          accessToken: { token: accessToken, expiryTokenDate: new Date(0).toISOString() },
          refreshToken: { token: refreshToken, expiryTokenDate: new Date(0).toISOString() },
        }),
      })
      if (!res.ok) return false

      const json = await res.json().catch(() => null)
      // Wrapper shape: { isSuccess, response: { accessToken: { token, ... }, refreshToken: { token, ... } } }
      const r = json?.response ?? json
      const newAccess = r?.accessToken?.token ?? r?.AccessToken?.Token
      const newRefresh = r?.refreshToken?.token ?? r?.RefreshToken?.Token
      if (!newAccess) return false

      localStorage.setItem("auth_token", newAccess)
      if (newRefresh) localStorage.setItem("refresh_token", newRefresh)

      // Sync the axios singleton so Farm API requests pick up the new token too.
      try {
        const { apiClient } = await import("@/lib/api/client")
        apiClient.setToken(newAccess)
      } catch { /* not critical */ }

      return true
    } catch {
      return false
    } finally {
      refreshInFlight = null
    }
  })()

  return refreshInFlight
}

/** Browser → /api/proxy → Cloud Run: must exceed proxy’s Login/Admin upstream timeout (75s) so the client sees a JSON error instead of a generic abort. */
const LOGIN_FETCH_TIMEOUT_MS = 90_000

// Login user
export async function login(data: LoginData): Promise<ApiResponse> {
  try {
    console.log("[Poultry Core] Login request:", {
      username: data.username,
      adminApiUrl: API_BASE_URL,
      fetchUrl: getAuthenticationApiUrl("login"),
    })

    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), LOGIN_FETCH_TIMEOUT_MS)

    let response: Response
    try {
      response = await fetch(getAuthenticationApiUrl("login"), {
        method: "POST",
        headers: {
          accept: "*/*",
          "Content-Type": "application/json",
        },
        body: JSON.stringify(data),
        signal: controller.signal,
      })
      clearTimeout(timeoutId)
    } catch (fetchError: any) {
      clearTimeout(timeoutId)
      
      if (fetchError.name === "AbortError") {
        logLoginDiagnostic(`Client timeout after ${LOGIN_FETCH_TIMEOUT_MS}ms`, API_BASE_URL)
        return { success: false, message: friendlyLoginError("timeout") }
      }

      // Network errors — in the browser this is usually same-origin /api/proxy
      // failing or the upstream Cloud Run service being unreachable. Log the
      // full context for support; users just see the short message.
      logLoginDiagnostic("Fetch error (network)", {
        name: fetchError?.name,
        message: fetchError?.message,
        stack: fetchError?.stack,
      })
      return { success: false, message: friendlyLoginError("network") }
    }

    // Single read — some hosts/CDNs send text/html with a JSON body; parse if it looks like JSON
    const contentType = response.headers.get("content-type") || ""
    const text = await response.text()
    const trimmed = text.trim()

    if (!trimmed) {
      logLoginDiagnostic(`Empty response body, HTTP ${response.status}`, { contentType })
      return { success: false, message: friendlyLoginError("empty-body") }
    }

    const looksJson =
      trimmed.startsWith("{") ||
      trimmed.startsWith("[") ||
      contentType.includes("application/json") ||
      contentType.includes("text/json")

    let result: any
    if (looksJson) {
      try {
        result = JSON.parse(text)
      } catch (parseError) {
        logLoginDiagnostic(`Invalid JSON, HTTP ${response.status}`, { parseError, bodyPreview: trimmed.slice(0, 500) })
        return { success: false, message: friendlyLoginError("invalid-json") }
      }
    } else {
      logLoginDiagnostic(`Non-JSON response, HTTP ${response.status}`, { contentType, bodyPreview: trimmed.slice(0, 500) })
      return { success: false, message: friendlyLoginError("non-json") }
    }

    // Proxy/gateway 5xx with a JSON body — log the raw message + error codes
    // for support, but the user sees the friendly message.
    if (
      [500, 502, 503, 504].includes(response.status) &&
      typeof (result as any)?.message === "string"
    ) {
      const r = result as any
      logLoginDiagnostic(`Upstream ${response.status} with message`, {
        message: r.message,
        errorType: r.errorType,
        errorCode: r.errorCode,
      })
      return { success: false, message: friendlyLoginError("upstream-5xx") }
    }

    if (
      response.status >= 500 &&
      result &&
      typeof result === "object" &&
      Object.keys(result).length === 0
    ) {
      logLoginDiagnostic(`HTTP ${response.status} with empty JSON body`)
      return { success: false, message: friendlyLoginError("server-500") }
    }

    console.log("[Poultry Core] Full login response:", JSON.stringify(result, null, 2))
    console.log("[Poultry Core] Requires 2FA:", result.RequiresTwoFactor || result.requiresTwoFactor)
    console.log("[Poultry Core] Is Success:", result.isSuccess)
    console.log("[Poultry Core] Response keys:", Object.keys(result))

    // Check for specific error messages
    if (!response.ok || !result.isSuccess) {
      let errorMessage = result.message || result.Message || "Login failed"
      
      // Provide helpful error messages for common issues
      if (errorMessage.includes("doesnot exist") || errorMessage.includes("does not exist") || errorMessage.includes("User doesnot exist")) {
        errorMessage = "Username or email not found. Please check your credentials or contact your administrator to verify your account exists."
      } else if (errorMessage.includes("Invalid password") || errorMessage.includes("invalid password")) {
        errorMessage = "Invalid password. Please check your password and try again."
      } else if (errorMessage.includes("locked out")) {
        errorMessage = "Account is locked. Please try again later or contact your administrator."
      } else if (errorMessage.includes("verify your email") || errorMessage.includes("email confirmation")) {
        errorMessage = "Please verify your email address before logging in. Check your email for a verification link."
      }
      
      return {
        success: false,
        message: errorMessage,
        errors: result.errors,
      }
    }

    // Check if 2FA is required (check before processing success response)
    const requires2FA = result.RequiresTwoFactor || result.requiresTwoFactor
    console.log("[Poultry Core] Checking 2FA requirement:", { requires2FA, result })
    
    if (requires2FA === true) {
      console.log("[Poultry Core] 2FA required, redirecting to 2FA page")
      return {
        success: true,
        data: {
          requiresTwoFactor: true,
          userId: result.userId || result.UserId,
          userName: result.username || result.userName || result.userName,
          message: result.message || result.Message || "OTP sent to your email"
        },
        message: result.message || result.Message || "OTP sent to your email",
      }
    }
    
    console.log("[Poultry Core] No 2FA required, processing normal login")

    // Handle the response structure from your API
    // The response can be in result.response (nested) or directly in result (flat)
    const userData = result.response || result
    
    if (result.isSuccess && userData) {

      // Store access token
      if (userData.accessToken?.token) {
        localStorage.setItem("auth_token", userData.accessToken.token)
        console.log("[Poultry Core] Stored auth token")
        
        // Also sync with apiClient if it exists
        if (typeof window !== 'undefined') {
          try {
            const { apiClient } = await import('@/lib/api/client')
            apiClient.setToken(userData.accessToken.token)
            console.log("[Poultry Core] Synced token with apiClient")
          } catch (err) {
            console.log("[Poultry Core] Could not sync with apiClient:", err)
          }
        }
      }

      // Store refresh token
      if (userData.refreshToken?.token) {
        localStorage.setItem("refresh_token", userData.refreshToken.token)
        console.log("[Poultry Core] Stored refresh token")
      }

      // Store user ID - handle both case variations
      const userId = userData.userId || userData.UserId
      if (userId) {
        localStorage.setItem("userId", userId)
        console.log("[Poultry Core] Stored userId:", userId)
      }

      // Store username - handle both case variations
      const username = userData.username || userData.Username || userData.userName || userData.UserName
      if (username) {
        localStorage.setItem("username", username)
        console.log("[Poultry Core] Stored username:", username)
      }

      // Store farm ID - handle both case variations
      const farmId = userData.farmId || userData.FarmId
      if (farmId) {
        localStorage.setItem("farmId", farmId)
        console.log("[v0] Stored farmId:", farmId)
      } else if (userId) {
        // Fallback: If farmId is not returned, use userId as farmId
        localStorage.setItem("farmId", userId)
        console.log("[v0] FarmId not in response, using userId as farmId:", userId)
      }

      // Store farm name - handle both case variations
      const farmName = userData.farmName || userData.FarmName
      if (farmName) {
        localStorage.setItem("farmName", farmName)
        console.log("[v0] Stored farmName:", farmName)
      } else {
        // Fallback farm name
        localStorage.setItem("farmName", "My Farm")
        console.log("[v0] FarmName not in response, using default: My Farm")
      }

      // Handle case sensitivity for IsStaff/isStaff
      const isStaff = userData.isStaff || userData.IsStaff || false
      const isSubscriber = userData.isSubscriber || userData.IsSubscriber || false
      
      // Store user roles - check if user is staff first
      if (userData.roles && Array.isArray(userData.roles)) {
        localStorage.setItem("roles", JSON.stringify(userData.roles))
        console.log("[v0] Stored roles:", userData.roles)
      } else {
        // Default role based on staff status
        if (isStaff) {
          localStorage.setItem("roles", JSON.stringify(["Staff", "User"]))
          console.log("[v0] No roles in response, defaulting to Staff for employee")
        } else {
          localStorage.setItem("roles", JSON.stringify(["Admin", "FarmAdmin"]))
          console.log("[v0] No roles in response, defaulting to Admin for non-staff user")
        }
      }

      // Store user flags - handle both case variations
      localStorage.setItem("isStaff", String(isStaff))
      localStorage.setItem("isSubscriber", String(isSubscriber))
      // #D: an employee can be flagged IsAdmin on their account (e.g. Christy).
      // The backend already returns it; persist it so usePermissions can grant
      // admin-only actions (Delete, etc.) to staff-admins. Staff WITHOUT this
      // flag stay non-admin.
      const isAdminFlag = userData.isAdmin === true || userData.IsAdmin === true
      localStorage.setItem("isAdmin", String(isAdminFlag))

      persistFeaturePermissionsFromUserData(userData, isStaff)
      
      console.log("[v0] Login complete - stored all user data")
      console.log("[v0] Employee status - isStaff:", isStaff, "isSubscriber:", isSubscriber)
    }

    return {
      success: result.isSuccess || true,
      data: result,
      message: result.message || "Login successful",
    }
  } catch (error: any) {
    // Same user-friendly + console-diagnostic split as the inner handlers.
    logLoginDiagnostic("Unhandled login error", {
      name: error?.constructor?.name,
      message: error?.message,
      stack: error?.stack,
    })

    if (error instanceof TypeError) {
      // TypeError covers "Failed to fetch", "NetworkError", CORS rejections.
      return { success: false, message: friendlyLoginError("network") }
    }
    if (error?.name === "AbortError") {
      return { success: false, message: friendlyLoginError("timeout") }
    }
    return {
      success: false,
      message: error?.message || "Something went wrong. Please try again.",
    }
  }
}

// Forgot password - send OTP
export async function forgotPassword(data: ForgotPasswordData): Promise<ApiResponse> {
  try {
    console.log("[Auth API] Forgot password request:", { email: data.email, apiUrl: API_BASE_URL })

    const response = await fetch(getAuthenticationApiUrl("ForgotPassword"), {
      method: "POST",
      headers: {
        accept: "*/*",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ email: data.email }),
    })

    console.log("[Auth API] Forgot password response status:", response.status)

    // Check if response is JSON
    const contentType = response.headers.get("content-type")
    const responseText = await response.text()
    
    // Backend returns 200 OK even if user doesn't exist (security)
    if (!response.ok) {
      console.error("[Auth API] Forgot password error:", responseText)

      let parsed: { message?: string; errors?: string[] } | null = null
      const looksJson =
        contentType?.includes("application/json") ||
        responseText.trimStart().startsWith("{")
      if (looksJson && responseText.trim()) {
        try {
          parsed = JSON.parse(responseText)
        } catch {
          parsed = null
        }
      }
      if (parsed?.message) {
        return {
          success: false,
          message: parsed.message,
          errors: parsed.errors,
        }
      }
      return {
        success: false,
        message:
          responseText.trim() ||
          (response.status === 503
            ? "Email service is temporarily unavailable. Please try again later."
            : "Failed to send reset code. Please try again."),
      }
    }

    // Success response
    return {
      success: true,
      message: "If this email exists, a reset code has been sent to your inbox.",
    }
  } catch (error) {
    console.error("[Auth API] Forgot password exception:", error)
    return {
      success: false,
      message: "Network error. Please check if the API is running on " + API_BASE_URL,
    }
  }
}

// Reset password
export async function resetPassword(data: ResetPasswordData): Promise<ApiResponse> {
  try {
    console.log("[Auth API] Reset password request:", { 
      email: data.email, 
      hasToken: !!data.token,
      apiUrl: API_BASE_URL 
    })

    const response = await fetch(getAuthenticationApiUrl("ResetPassword"), {
      method: "POST",
      headers: {
        accept: "*/*",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email: data.email,
        token: data.token,
        password: data.password,
        confirmPassword: data.confirmPassword,
      }),
    })

    console.log("[Auth API] Reset password response status:", response.status)

    const contentType = response.headers.get("content-type")
    const responseText = await response.text()

    if (!response.ok) {
      console.error("[Auth API] Reset password error:", responseText)
      
      try {
        const result = contentType?.includes("application/json") ? JSON.parse(responseText) : null
        if (!result) {
          return {
            success: false,
            message: responseText || "Password reset failed. Please try again.",
          }
        }
        
        // Extract validation errors if present
        let errorMessage = "Password reset failed"
        if (result.errors) {
          const errorMessages = Object.values(result.errors).flat()
          errorMessage = errorMessages.join(', ')
        } else if (result.message) {
          errorMessage = result.message
        }
        
        return {
          success: false,
          message: errorMessage,
          errors: result.errors,
        }
      } catch {
        return {
          success: false,
          message: "Invalid reset code or password. Please try again.",
        }
      }
    }

    // Success
    return {
      success: true,
      message: "Password reset successful! You can now login with your new password.",
    }
  } catch (error) {
    console.error("[Auth API] Reset password exception:", error)
    return {
      success: false,
      message: "Network error. Please check if the API is running on " + API_BASE_URL,
    }
  }
}

// Confirm email
export async function confirmEmail(data: ConfirmEmailData): Promise<ApiResponse> {
  try {
    console.log("[Auth API] Confirm email request:", { email: data.email, hasToken: !!data.token })

    const url = `${getAuthenticationApiUrl("ConfirmEmail")}?email=${encodeURIComponent(data.email)}&token=${encodeURIComponent(data.token)}`
    
    const response = await fetch(url, {
      method: "GET",
      headers: {
        accept: "*/*",
      },
    })

    console.log("[Auth API] Confirm email response status:", response.status)

    const contentType = response.headers.get("content-type")
    const responseText = await response.text()

    if (!response.ok) {
      console.error("[Auth API] Confirm email error:", responseText)
      
      try {
        const result = contentType?.includes("application/json") ? JSON.parse(responseText) : null
        if (result) {
          return {
            success: false,
            message: result.message || "Email confirmation failed",
            errors: result.errors,
          }
        }
      } catch {
        // Not JSON
      }
      return {
        success: false,
        message: responseText || "Email confirmation failed. The link may be invalid or expired.",
      }
    }

    let result
    try {
      result = contentType?.includes("application/json") ? JSON.parse(responseText) : null
      if (!result) {
        return {
          success: false,
          message: "Invalid response from server. Please try again.",
        }
      }
    } catch (parseError) {
      console.error("[Auth API] JSON parse error:", parseError)
      return {
        success: false,
        message: "Invalid response from server. Please try again.",
      }
    }
    return {
      success: true,
      data: result,
      message: result.message || "Email confirmed successfully! You can now login.",
    }
  } catch (error) {
    console.error("[Auth API] Confirm email exception:", error)
    return {
      success: false,
      message: "Network error. Please check if the API is running on " + API_BASE_URL,
    }
  }
}
