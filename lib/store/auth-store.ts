import { create } from 'zustand'
import { persist } from 'zustand/middleware'

interface User {
  id: string
  username: string
  email: string
  farmId: string
  farmName: string
  isStaff: boolean
  isSubscriber: boolean
}

interface AuthState {
  token: string | null
  refreshToken: string | null
  user: User | null
  isAuthenticated: boolean
  setToken: (token: string) => void
  setRefreshToken: (refreshToken: string) => void
  setUser: (user: User) => void
  login: (token: string, refreshToken: string, user: User) => void
  logout: () => void
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      token: null,
      refreshToken: null,
      user: null,
      isAuthenticated: false,
      
      setToken: (token) => {
        set({ token, isAuthenticated: !!token })
        // Sync with localStorage
        if (typeof window !== 'undefined') {
          if (token) {
            localStorage.setItem('auth_token', token)
          } else {
            localStorage.removeItem('auth_token')
          }
        }
      },
      
      setRefreshToken: (refreshToken) => set({ refreshToken }),
      
      setUser: (user) => set({ user }),
      
      login: (token, refreshToken, user) => {
        set({
          token,
          refreshToken,
          user,
          isAuthenticated: true,
        })
        // Sync with localStorage
        if (typeof window !== 'undefined') {
          localStorage.setItem('auth_token', token)
        }
      },
      
      logout: () => {
        set({
          token: null,
          refreshToken: null,
          user: null,
          isAuthenticated: false,
        })
        // Clear localStorage
        if (typeof window !== 'undefined') {
          localStorage.removeItem('auth_token')
        }
      },
    }),
    {
      name: 'auth-storage',
      partialize: (state) => ({
        token: state.token,
        refreshToken: state.refreshToken,
        user: state.user,
        isAuthenticated: state.isAuthenticated,
      }),
    }
  )
)
