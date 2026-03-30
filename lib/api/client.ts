import axios, { AxiosInstance, AxiosError, InternalAxiosRequestConfig } from 'axios'

export class ApiError extends Error {
  constructor(
    public status: number,
    public statusText: string,
    public data?: any
  ) {
    super(`API Error: ${status} ${statusText}`)
    this.name = 'ApiError'
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
          } catch (refreshError) {
            this.processQueue(refreshError, null)
            // Redirect to login on refresh failure
            if (typeof window !== 'undefined') {
              window.location.href = '/login'
            }
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
function normalizeBaseUrl(raw?: string, fallback = 'https://farmapi.techretainer.com') {
  const val = raw || fallback
  if (val.startsWith('http://') || val.startsWith('https://')) return val
  return `https://${val}`
}

export const apiClient = new ApiClient(
  normalizeBaseUrl(process.env.NEXT_PUBLIC_API_BASE_URL, 'https://farmapi.techretainer.com')
)

// Initialize token from localStorage on client side
if (typeof window !== 'undefined') {
  const token = localStorage.getItem('auth_token')
  if (token) {
    apiClient.setToken(token)
  }
}
