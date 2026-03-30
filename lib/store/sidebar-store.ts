import { create } from 'zustand'
import { persist } from 'zustand/middleware'

interface SidebarState {
  isCollapsed: boolean
  isMobileOpen: boolean
  toggle: () => void
  toggleMobile: () => void
  setCollapsed: (collapsed: boolean) => void
  setMobileOpen: (open: boolean) => void
}

export const useSidebarStore = create<SidebarState>()(
  persist(
    (set) => ({
      isCollapsed: true,
      isMobileOpen: false,
      toggle: () => set((state) => ({ isCollapsed: !state.isCollapsed })),
      toggleMobile: () => set((state) => ({ isMobileOpen: !state.isMobileOpen })),
      setCollapsed: (collapsed: boolean) => set({ isCollapsed: collapsed }),
      setMobileOpen: (open: boolean) => set({ isMobileOpen: open }),
    }),
    {
      name: 'sidebar-storage',
      partialize: (state) => ({ isCollapsed: state.isCollapsed }), // Only persist collapsed state, not mobile
    }
  )
)

