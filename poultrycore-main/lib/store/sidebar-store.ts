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
      // Default OPEN on laptop (users can still collapse it; the choice persists).
      isCollapsed: false,
      isMobileOpen: false,
      toggle: () => set((state) => ({ isCollapsed: !state.isCollapsed })),
      toggleMobile: () => set((state) => ({ isMobileOpen: !state.isMobileOpen })),
      setCollapsed: (collapsed: boolean) => set({ isCollapsed: collapsed }),
      setMobileOpen: (open: boolean) => set({ isMobileOpen: open }),
    }),
    {
      // Bumped from 'sidebar-storage' so the new "expanded by default for all
      // company types" default applies to existing users (their old persisted
      // value came from a per-farm-type force-collapse that has been removed).
      name: 'sidebar-storage-v2',
      // Rehydrate after mount (see store-hydration.tsx) — `isCollapsed` drives
      // conditional header content, so a synchronous rehydrate would diverge
      // from the SSR default and cause a hydration mismatch.
      skipHydration: true,
      partialize: (state) => ({ isCollapsed: state.isCollapsed }), // Only persist collapsed state, not mobile
    }
  )
)

