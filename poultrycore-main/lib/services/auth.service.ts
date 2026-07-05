import { apiClient } from '@/lib/api/client'
import { getAuthenticationApiUrl, persistFeaturePermissionsFromUserData, tryRefreshAccessToken } from '@/lib/api/auth'
import { getAuthHeaders } from '@/lib/api/config'

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
    twoFactorEnabled?: boolean
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
    // The verify response may be nested (data.response.user), flat camelCase,
    // or flat PascalCase (ASP.NET). Read all variants so userId/farmId always land.
    const rawUser = data?.response?.user || data?.user || {}
    const pick = (...keys: string[]) => { for (const k of keys) { const v = (rawUser as any)?.[k] ?? (data as any)?.[k]; if (v !== undefined && v !== null && v !== '') return v } return undefined }
    const user = {
      id: pick('id', 'Id', 'userId', 'UserId'),
      username: pick('username', 'Username', 'userName', 'UserName') || credentials.userName,
      email: pick('email', 'Email') || '',
      farmId: pick('farmId', 'FarmId') || pick('id', 'Id', 'userId', 'UserId'),
      farmName: pick('farmName', 'FarmName') || '',
      isStaff: !!pick('isStaff', 'IsStaff'),
      isSubscriber: !!pick('isSubscriber', 'IsSubscriber'),
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
   * Get current user information.
   *
   * Goes through the same-origin Login API proxy (not the Farm API axios
   * instance — the Authentication routes only exist on the Login API). One
   * automatic 401 → refresh → retry attempt so the 60-minute token expiry
   * doesn't wipe the profile page until the user logs out and back in.
   */
  static async getCurrentUser(): Promise<AuthResponse['user']> {
    const url = getAuthenticationApiUrl('get-current-user')
    const doFetch = () => fetch(url, { headers: getAuthHeaders() })

    let res = await doFetch()
    if (res.status === 401 && (await tryRefreshAccessToken())) {
      res = await doFetch()
    }
    if (!res.ok) {
      const err: any = new Error(`getCurrentUser failed: ${res.status}`)
      err.status = res.status
      throw err
    }
    // Backend returns the EF/Identity ApplicationUser (PascalCase). The profile
    // page already accepts a few case variants (phone vs phoneNumber, etc.)
    // but normalize the common ones so it always finds what it needs.
    const raw = await res.json()
    return {
      id: raw.id ?? raw.Id ?? '',
      username: raw.userName ?? raw.UserName ?? raw.username ?? '',
      email: raw.email ?? raw.Email ?? '',
      farmId: raw.farmId ?? raw.FarmId ?? '',
      farmName: raw.farmName ?? raw.FarmName ?? '',
      isStaff: raw.isStaff ?? raw.IsStaff ?? false,
      isSubscriber: raw.isSubscriber ?? raw.IsSubscriber ?? false,
      firstName: raw.firstName ?? raw.FirstName ?? '',
      lastName: raw.lastName ?? raw.LastName ?? '',
      phoneNumber: raw.phoneNumber ?? raw.PhoneNumber ?? '',
      phone: raw.phoneNumber ?? raw.PhoneNumber ?? '',
      twoFactorEnabled: raw.twoFactorEnabled ?? raw.TwoFactorEnabled ?? false,
    } as AuthResponse['user']
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
