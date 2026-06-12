import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useAuthStore } from '@/lib/store/auth-store'
import { apiClient } from '@/lib/api/client'

export function useAuth() {
  const router = useRouter()
  const { token, refreshToken, user, isAuthenticated, login, logout, setToken } = useAuthStore()

  // Sync token with API client
  useEffect(() => {
    apiClient.setToken(token)
  }, [token])

  // Initialize token from localStorage on mount
  useEffect(() => {
    if (typeof window !== 'undefined') {
      const storedToken = localStorage.getItem('auth_token')
      if (storedToken && !token) {
        setToken(storedToken)
      }
    }
  }, [token, setToken])

  /**
   * Check if user is authenticated
   */
  const checkAuth = () => {
    return isAuthenticated && token !== null
  }

  /**
   * Require authentication - redirect to login if not authenticated
   */
  const requireAuth = () => {
    if (!checkAuth()) {
      router.push('/login')
    }
  }

  /**
   * Handle logout
   */
  const handleLogout = () => {
    logout()
    apiClient.setToken(null)
    // Clear localStorage
    if (typeof window !== 'undefined') {
      localStorage.removeItem('auth_token')
      localStorage.removeItem('auth-storage')
    }
    router.push('/login')
  }

  return {
    token,
    refreshToken,
    user,
    isAuthenticated: checkAuth(),
    login,
    logout: handleLogout,
    setToken,
    requireAuth,
  }
}
