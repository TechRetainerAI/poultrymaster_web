import { apiClient } from '@/lib/api/client'
import { getAuthenticationApiUrl, persistFeaturePermissionsFromUserData } from '@/lib/api/auth'

interface LoginCredentials {
  username: string
  password: string
}

interface Login2FACredentials {
  userId: string
  userName: string
  otpCode: string
}

interface RegisterData {
  username: string
  email: string
  password: string
  phoneNumber?: string
  farmName?: string
}

interface AuthResponse {
  token: string
  refreshToken: string
  user: {
    id: string
    username: string
    email: string
    farmId: string
    farmName: string
    isStaff: boolean
    isSubscriber: boolean
    firstName?: string
    lastName?: string
    phone?: string
    phoneNumber?: string
    customerId?: string
    lastLoginTime?: string
  }
}

export class AuthService {
  /**
   * Login with username and password
   */
  static async login(credentials: LoginCredentials): Promise<AuthResponse> {
    return apiClient.post<AuthResponse>('/api/Authentication/login', credentials)
  }

  /**
   * Login with 2FA (after initial login)
   */
  static async login2FA(credentials: Login2FACredentials): Promise<AuthResponse> {
    // Same-origin proxy in browser avoids CORS to Cloud Run Login API
    const url = getAuthenticationApiUrl('login-2FA')
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', accept: '*/*' },
      // Backend model binder accepts PascalCase; send both to be safe
      body: JSON.stringify({
        userId: credentials.userId,
        userName: credentials.userName,
        otpCode: credentials.otpCode,
        UserId: credentials.userId,
        UserName: credentials.userName,
        OtpCode: credentials.otpCode,
      }),
    })

    if (!res.ok) {
      const text = await res.text()
      throw new Error(text || 'Invalid OTP code')
    }

    const data = (await res.json()) as any

    // Normalize and return AuthResponse while also syncing tokens to apiClient/localStorage
    const token = data?.response?.accessToken?.token || data?.accessToken?.token || data?.token
    const refreshToken = data?.response?.refreshToken?.token || data?.refreshToken?.token || data?.refreshToken
    const user = data?.response?.user || data?.user || {
      id: data?.userId,
      username: data?.username || credentials.userName,
      email: data?.email || '',
      farmId: data?.farmId || data?.userId,
      farmName: data?.farmName || '',
      isStaff: !!data?.isStaff,
      isSubscriber: !!data?.isSubscriber,
    }

    if (typeof window !== 'undefined' && token) {
      localStorage.setItem('auth_token', token)
      try { (await import('@/lib/api/client')).apiClient.setToken(token) } catch {}
      
      // Store employee information in localStorage (same as regular login)
      if (refreshToken) {
        localStorage.setItem('refresh_token', refreshToken)
      }
      
      // Handle case sensitivity for IsStaff/isStaff
      const isStaff = user.isStaff || data?.isStaff || data?.IsStaff || false
      const isSubscriber = user.isSubscriber || data?.isSubscriber || data?.IsSubscriber || false
      
      // Store user ID
      if (user.id) {
        localStorage.setItem('userId', user.id)
      }
      
      // Store username
      if (user.username) {
        localStorage.setItem('username', user.username)
      }
      
      // Store farm ID
      if (user.farmId) {
        localStorage.setItem('farmId', user.farmId)
      }
      
      // Store farm name
      if (user.farmName) {
        localStorage.setItem('farmName', user.farmName)
      } else {
        localStorage.setItem('farmName', 'My Farm')
      }
      
      // Store roles - default based on staff status
      if (isStaff) {
        localStorage.setItem('roles', JSON.stringify(['Staff', 'User']))
      } else {
        localStorage.setItem('roles', JSON.stringify(['Admin', 'FarmAdmin']))
      }
      
      // Store user flags
      localStorage.setItem('isStaff', String(isStaff))
      localStorage.setItem('isSubscriber', String(isSubscriber))

      const loginPayload = data?.response ?? data
      persistFeaturePermissionsFromUserData(loginPayload, isStaff)

      console.log('[2FA Login] Stored employee information - isStaff:', isStaff)
    }

    return { token, refreshToken, user } as AuthResponse
  }

  /**
   * Register a new user
   */
  static async register(data: RegisterData): Promise<AuthResponse> {
    return apiClient.post<AuthResponse>('/api/Authentication/register', data)
  }

  /**
   * Refresh authentication token
   */
  static async refreshToken(refreshToken: string): Promise<{ token: string; refreshToken: string }> {
    return apiClient.post<{ token: string; refreshToken: string }>('/api/Authentication/refresh-token', {
      refreshToken,
    })
  }

  /**
   * Get current user information
   */
  static async getCurrentUser(): Promise<AuthResponse['user']> {
    return apiClient.get<AuthResponse['user']>('/api/Authentication/get-current-user')
  }

  /**
   * Logout user
   */
  static async logout(): Promise<void> {
    return apiClient.post('/api/Authentication/logout', {})
  }

  /**
   * Request password reset
   */
  static async forgotPassword(email: string): Promise<void> {
    return apiClient.post('/api/Authentication/forgot-password', { email })
  }

  /**
   * Reset password
   */
  static async resetPassword(token: string, newPassword: string): Promise<void> {
    return apiClient.post('/api/Authentication/reset-password', {
      token,
      newPassword,
    })
  }

  /**
   * Verify user account with email token
   */
  static async verifyAccount(token: string): Promise<void> {
    return apiClient.post('/api/Authentication/verify-account', { token })
  }
}
