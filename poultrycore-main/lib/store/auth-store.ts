import { create } from 'zustand'
import { persist } from 'zustand/middleware'
import type { Company, CompanyType } from '@/lib/api/companies'

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

  // Multi-company
  companies: Company[]
  activeFarmId: string | null
  activeFarmName: string | null
  activeFarmType: CompanyType | null

  setToken: (token: string) => void
  setRefreshToken: (refreshToken: string) => void
  setUser: (user: User) => void
  login: (token: string, refreshToken: string, user: User) => void
  logout: () => void

  setCompanies: (companies: Company[]) => void
  setActiveCompany: (farmId: string, name: string, type: CompanyType, token?: string) => void
  // Doc 3 §9: drop the active company so the Business Office is company-neutral
  // (no default company selected). Also clears the mirrored localStorage keys.
  clearActiveCompany: () => void
}

/**
 * Fired whenever the active company changes (including being cleared).
 *
 * IAM permissions are granted per company, so anything holding a resolved
 * permission set has to drop it and re-read on this event — see
 * hooks/use-permissions.ts. A plain window event rather than a store
 * subscription because the consumers are outside React's tree in places.
 */
export const COMPANY_CHANGED_EVENT = 'iam:company-changed'

function syncCompanyToLocalStorage(farmId: string | null, name: string | null, type: CompanyType | null) {
  if (typeof window === 'undefined') return
  if (farmId) localStorage.setItem('farmId', farmId)
  else localStorage.removeItem('farmId')
  if (name) localStorage.setItem('farmName', name)
  else localStorage.removeItem('farmName')
  if (type) localStorage.setItem('farmType', type)
  else localStorage.removeItem('farmType')
  window.dispatchEvent(new Event(COMPANY_CHANGED_EVENT))
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      token: null,
      refreshToken: null,
      user: null,
      isAuthenticated: false,
      companies: [],
      activeFarmId: null,
      activeFarmName: null,
      activeFarmType: null,

      setToken: (token) => {
        set({ token, isAuthenticated: !!token })
        if (typeof window !== 'undefined') {
          if (token) localStorage.setItem('auth_token', token)
          else localStorage.removeItem('auth_token')
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
          activeFarmId: user.farmId,
          activeFarmName: user.farmName,
        })
        if (typeof window !== 'undefined') {
          localStorage.setItem('auth_token', token)
        }
        syncCompanyToLocalStorage(user.farmId, user.farmName, get().activeFarmType)
      },

      logout: () => {
        set({
          token: null,
          refreshToken: null,
          user: null,
          isAuthenticated: false,
          companies: [],
          activeFarmId: null,
          activeFarmName: null,
          activeFarmType: null,
        })
        if (typeof window !== 'undefined') {
          localStorage.removeItem('auth_token')
          localStorage.removeItem('farmId')
          localStorage.removeItem('farmName')
          localStorage.removeItem('farmType')
        }
      },

      setCompanies: (companies) => {
        // If the current active company is now stale (was deleted), drop it.
        const current = get().activeFarmId
        const stillExists = current && companies.some((c) => c.farmId === current)
        if (!stillExists && companies.length > 0) {
          const first = companies[0]
          set({
            companies,
            activeFarmId: first.farmId,
            activeFarmName: first.name,
            activeFarmType: first.type,
          })
          syncCompanyToLocalStorage(first.farmId, first.name, first.type)
        } else {
          // Reconcile active type from the matched company (it can change if updated server-side).
          const match = companies.find((c) => c.farmId === current)
          set({
            companies,
            activeFarmType: match?.type ?? get().activeFarmType,
          })
          if (match) syncCompanyToLocalStorage(match.farmId, match.name, match.type)
        }
      },

      setActiveCompany: (farmId, name, type, token) => {
        set((s) => ({
          activeFarmId: farmId,
          activeFarmName: name,
          activeFarmType: type,
          token: token ?? s.token,
          user: s.user ? { ...s.user, farmId, farmName: name } : s.user,
        }))
        if (typeof window !== 'undefined' && token) {
          localStorage.setItem('auth_token', token)
        }
        syncCompanyToLocalStorage(farmId, name, type)
      },

      clearActiveCompany: () => {
        set({ activeFarmId: null, activeFarmName: null, activeFarmType: null })
        syncCompanyToLocalStorage(null, null, null)
      },
    }),
    {
      name: 'auth-storage',
      // Defer rehydration until after the first client render so SSR HTML and
      // the initial client render agree (both see the null/default state).
      // Without this, persist rehydrates synchronously and `activeFarmType`
      // jumps to e.g. "Water" on the very first client render, diverging from
      // the server's null → Poultry render and shifting React's useId counter,
      // which produces Radix `aria-controls` hydration mismatches. A one-time
      // rehydrate() runs on mount via components/providers/store-hydration.tsx.
      skipHydration: true,
      partialize: (state) => ({
        token: state.token,
        refreshToken: state.refreshToken,
        user: state.user,
        isAuthenticated: state.isAuthenticated,
        companies: state.companies,
        activeFarmId: state.activeFarmId,
        activeFarmName: state.activeFarmName,
        activeFarmType: state.activeFarmType,
      }),
    }
  )
)
