import axios, { AxiosInstance, AxiosError, InternalAxiosRequestConfig } from 'axios'
import { DEFAULT_FARM_API_ORIGIN } from '@/lib/api/default-api-hosts'

export class ApiError extends Error {
  constructor(
    public status: number,
    public statusText: string,
    public data?: any
  ) {
    // Surface the REAL backend error (GlobalExceptionMiddleware / controllers
    // return { message } or a validation errors bag) instead of a generic
    // "API Error 400" red card. Falls back to the status when there's nothing
    // useful in the body.
    super(ApiError.buildMessage(status, statusText, data))
    this.name = 'ApiError'
  }

  private static buildMessage(status: number, statusText: string, data: any): string {
    let msg = ""
    if (typeof data === "string") {
      // Ignore HTML error pages — they're noise, not a message.
      msg = data.trim().startsWith("<") ? "" : data.trim()
    } else if (data && typeof data === "object") {
      const errs = (data as any).errors
      msg = String(
        (data as any).message ?? (data as any).Message ?? (data as any).title ??
        (data as any).error ??
        (Array.isArray(errs) ? errs.join(", ")
          : errs && typeof errs === "object" ? Object.values(errs).flat().join(", ")
          : "")
      ).trim()
    }
    return msg || `Request failed (${status}${statusText ? " " + statusText : ""})`
  }
}

class ApiClient {
  private client: AxiosInstance
  private token: string | null = null
  private refreshToken: string | null = null
  private isRefreshing = false
  private failedQueue: Array<{
    resolve: (token: string) => void
    reject: (error: any) => void
  }> = []

  constructor(baseURL: string) {
    this.client = axios.create({
      baseURL,
      timeout: 30000,
      headers: {
        'Content-Type': 'application/json',
      },
    })

    // Request interceptor
    this.client.interceptors.request.use(
      (config: InternalAxiosRequestConfig) => {
        if (this.token && config.headers) {
          config.headers.Authorization = `Bearer ${this.token}`
        }
        // Attach a friendly username header for audit logging if available
        if (typeof window !== 'undefined' && config.headers) {
          const username = localStorage.getItem('username') || localStorage.getItem('userName')
          if (username) {
            ;(config.headers as any)['username'] = username
            ;(config.headers as any)['X-Username'] = username
          }
        }
        return config
      },
      (error) => Promise.reject(error)
    )

    // Response interceptor with token refresh logic
    this.client.interceptors.response.use(
      (response) => response,
      async (error: AxiosError) => {
        const originalRequest = error.config as any

        // If 401 and not already retrying
        if (error.response?.status === 401 && !originalRequest._retry) {
          if (this.isRefreshing) {
            // If already refreshing, queue the request
            return new Promise((resolve, reject) => {
              this.failedQueue.push({ resolve, reject })
            })
              .then((token) => {
                originalRequest.headers.Authorization = `Bearer ${token}`
                return this.client(originalRequest)
              })
              .catch((err) => {
                return Promise.reject(err)
              })
          }

          originalRequest._retry = true
          this.isRefreshing = true

          try {
            // Try to refresh the token
            if (this.refreshToken) {
              const response = await axios.post(`${baseURL}/api/Authentication/refresh-token`, {
                refreshToken: this.refreshToken,
              })

              const { token, refreshToken } = response.data
              this.setTokens(token, refreshToken)

              // Process the queue
              this.processQueue(null, token)

              // Retry the original request
              originalRequest.headers.Authorization = `Bearer ${token}`
              return this.client(originalRequest)
            }
            // No refresh token available — the session is over. Fall through to
            // the catch so we log out completely (N7).
            throw new Error('No refresh token')
          } catch (refreshError) {
            this.processQueue(refreshError, null)
            // N7: when the session truly expires, log the user out COMPLETELY —
            // clear every auth artefact so the app can't re-hydrate a stale login.
            this.clearAllAuthAndRedirect()
            return Promise.reject(refreshError)
          } finally {
            this.isRefreshing = false
          }
        }

        if (error.response) {
          // For 404 errors, provide a more helpful message
          if (error.response.status === 404) {
            throw new ApiError(
              error.response.status,
              error.response.statusText || 'Not Found',
              error.response.data || 'The requested endpoint was not found'
            )
          }
          throw new ApiError(
            error.response.status,
            error.response.statusText,
            error.response.data
          )
        }
        throw error
      }
    )
  }

  private processQueue(error: any, token: string | null) {
    this.failedQueue.forEach((prom) => {
      if (error) {
        prom.reject(error)
      } else {
        prom.resolve(token!)
      }
    })

    this.failedQueue = []
  }

  setTokens(token: string | null, refreshToken?: string | null) {
    this.token = token
    if (refreshToken !== undefined) {
      this.refreshToken = refreshToken
    }
  }

  // N7: wipe every auth artefact (in-memory + persisted) and send the user to
  // the login screen, so an expired session can't silently re-hydrate.
  private clearAllAuthAndRedirect() {
    this.token = null
    this.refreshToken = null
    if (typeof window !== 'undefined') {
      try {
        localStorage.removeItem('auth_token')
        localStorage.removeItem('auth-storage')
        localStorage.removeItem('farmId')
        localStorage.removeItem('farmName')
        localStorage.removeItem('farmType')
      } catch {}
      if (window.location.pathname !== '/login') window.location.href = '/login'
    }
  }

  setToken(token: string | null) {
    this.token = token
  }

  getToken(): string | null {
    return this.token
  }

  getRefreshToken(): string | null {
    return this.refreshToken
  }

  async get<T>(url: string, params?: any): Promise<T> {
    const response = await this.client.get<T>(url, { params })
    return response.data
  }

  async post<T>(url: string, data?: any): Promise<T> {
    const response = await this.client.post<T>(url, data)
    return response.data
  }

  async put<T>(url: string, data?: any): Promise<T> {
    const response = await this.client.put<T>(url, data)
    return response.data
  }

  async patch<T>(url: string, data?: any): Promise<T> {
    const response = await this.client.patch<T>(url, data)
    return response.data
  }

  async delete<T>(url: string): Promise<T> {
    const response = await this.client.delete<T>(url)
    return response.data
  }
}

// Singleton instance
function normalizeBaseUrl(raw?: string, fallback = DEFAULT_FARM_API_ORIGIN) {
  const val = raw || fallback
  if (val.startsWith('http://') || val.startsWith('https://')) return val
  return `https://${val}`
}

export const apiClient = new ApiClient(
  normalizeBaseUrl(process.env.NEXT_PUBLIC_API_BASE_URL, DEFAULT_FARM_API_ORIGIN)
)

// Initialize token from localStorage on client side
if (typeof window !== 'undefined') {
  const token = localStorage.getItem('auth_token')
  if (token) {
    apiClient.setToken(token)
  }
}
