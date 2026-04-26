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

/** Explains real flow (browser → Next proxy → Login API) for support / debugging */
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

export interface RegisterData {
  farmName: string
  username: string
  email: string
  password: string
  firstName: string
  lastName: string
  roles: string[]
  phoneNumber: string
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
  const canViewActivityLog = pick(src.canViewActivityLog, src.CanViewActivityLog, src.viewActivityLog, src.ViewActivityLog, src.activityLog, src.ActivityLog)
  const canViewSettings = pick(src.canViewSettings, src.CanViewSettings, src.viewSettings, src.ViewSettings, src.settings, src.Settings)

  const normalized: Record<string, boolean> = {}
  if (canEnterSales !== undefined) normalized.canEnterSales = canEnterSales
  if (canEnterExpenses !== undefined) normalized.canEnterExpenses = canEnterExpenses
  if (canViewCashLedger !== undefined) normalized.canViewCashLedger = canViewCashLedger
  if (canSeeEmployees !== undefined) normalized.canSeeEmployees = canSeeEmployees
  if (canViewReports !== undefined) normalized.canViewReports = canViewReports
  if (canViewFinancial !== undefined) normalized.canViewFinancial = canViewFinancial
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
      return {
        success: false,
        message: result.message || "Registration failed",
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
      
      // Handle specific fetch errors
      if (fetchError.name === "AbortError") {
        console.error("[Poultry Core] Request timeout (client limit, ms):", LOGIN_FETCH_TIMEOUT_MS, API_BASE_URL)
        return {
          success: false,
          message: `Login request timed out (waited ${LOGIN_FETCH_TIMEOUT_MS / 1000}s).\n\n${loginUpstreamDiagnostics()}`,
        }
      }
      
      // Network errors — in the browser this is usually same-origin /api/proxy failing or unreachable
      console.error("[Poultry Core] Fetch error:", fetchError)
      console.error("[Poultry Core] Error details:", {
        name: fetchError.name,
        message: fetchError.message,
        stack: fetchError.stack,
      })
      
      let errorMessage = `Could not complete login (network error).\n\n${loginUpstreamDiagnostics()}\n\n`
      
      if (fetchError.message.includes('Failed to fetch') || fetchError.message.includes('NetworkError')) {
        errorMessage +=
          "Technical: \"Failed to fetch\" here often means your browser never got a normal response from this site’s /api/proxy route, OR the hosting server cannot reach the Login API URL above."
      } else {
        errorMessage += fetchError.message || "Unknown network error."
      }
      
      return {
        success: false,
        message: errorMessage,
      }
    }

    // Single read — some hosts/CDNs send text/html with a JSON body; parse if it looks like JSON
    const contentType = response.headers.get("content-type") || ""
    const text = await response.text()
    const trimmed = text.trim()

    if (!trimmed) {
      console.error("[Poultry Core] Empty response:", response.status, contentType)
      return {
        success: false,
        message: `Empty response (HTTP ${response.status}). Check Render logs for [Proxy API] and Cloud Run Login logs.\n\n${loginUpstreamDiagnostics()}`,
      }
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
        console.error("[Poultry Core] JSON parse error:", parseError, trimmed.slice(0, 500))
        return {
          success: false,
          message: `Invalid JSON (HTTP ${response.status}).\n\n${loginUpstreamDiagnostics()}`,
        }
      }
    } else {
      console.error("[Poultry Core] Non-JSON response:", {
        status: response.status,
        contentType,
        body: trimmed.slice(0, 500),
      })
      return {
        success: false,
        message: `Login failed (HTTP ${response.status}).\n${trimmed.slice(0, 400)}${trimmed.length > 400 ? "…" : ""}\n\n${loginUpstreamDiagnostics()}`,
      }
    }

    // Proxy timeout / errors: { success, message, errorType, errorCode } — show full message (already includes checks)
    if (
      [500, 502, 503, 504].includes(response.status) &&
      typeof (result as any)?.message === "string"
    ) {
      const r = result as any
      const suffix =
        r.errorType && r.errorType !== "AbortError"
          ? `\n(${r.errorType}${r.errorCode ? `: ${r.errorCode}` : ""})`
          : r.errorCode
            ? `\n(${r.errorCode})`
            : ""
      const alreadyHasFlow = String(r.message).includes("Login flow:")
      return {
        success: false,
        message: alreadyHasFlow
          ? `${r.message}${suffix}`
          : `${r.message}${suffix}\n\n${loginUpstreamDiagnostics()}`,
      }
    }

    if (
      response.status >= 500 &&
      result &&
      typeof result === "object" &&
      Object.keys(result).length === 0
    ) {
      return {
        success: false,
        message: `Login API returned HTTP ${response.status} with an empty JSON body. Typical causes: crash before response, or gateway timeout. Check Cloud Run → Login service → Logs (DB, SMTP, JWT).\n\n${loginUpstreamDiagnostics()}`,
      }
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
    console.error("[Poultry Core] Login error:", error)
    console.error("[Poultry Core] Error type:", error?.constructor?.name)
    console.error("[Poultry Core] Error message:", error?.message)
    
    // Provide more specific error messages based on the error type
    let errorMessage = "Network error. Please try again."
    
    if (error instanceof TypeError) {
      if (error.message === "Failed to fetch" || error.message.includes("Failed to fetch")) {
        errorMessage = `Could not complete login (Failed to fetch).\n\n${loginUpstreamDiagnostics()}`
      } else if (error.message.includes("CORS")) {
        errorMessage = `CORS blocked the response. With the proxy, the browser usually talks only to this site; if you still see CORS, try a hard refresh or redeploy the frontend.\n\n${loginUpstreamDiagnostics()}`
      } else if (error.message.includes("NetworkError")) {
        errorMessage = "Network connection failed. Please check your internet connection."
      } else {
        errorMessage = `Network error: ${error.message || "Unknown error occurred"}\n\n${loginUpstreamDiagnostics()}`
      }
    } else if (error?.name === "AbortError") {
      errorMessage = `Login request timed out.\n\n${loginUpstreamDiagnostics()}`
    } else {
      errorMessage = error?.message || "An unexpected error occurred. Please try again."
    }
    
    return {
      success: false,
      message: errorMessage,
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
      
      try {
        const result = contentType?.includes("application/json") ? JSON.parse(responseText) : null
        if (result) {
          return {
            success: false,
            message: result.message || "Failed to send reset code",
            errors: result.errors,
          }
        }
      } catch {
        // Not JSON, return generic error
      }
      return {
        success: false,
        message: responseText || "Failed to send reset code. Please try again.",
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
