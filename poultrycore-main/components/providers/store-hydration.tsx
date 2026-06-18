"use client"

import { useEffect } from "react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useSidebarStore } from "@/lib/store/sidebar-store"
import { useFarmSettingsStore } from "@/lib/currency"

/**
 * Rehydrates the persisted Zustand stores once, after the first client render.
 *
 * The stores are created with `skipHydration: true`, so on the server and on
 * the initial client render they expose their default (logged-out / null /
 * collapsed) state — which is exactly what the server rendered. That keeps the
 * first client render byte-identical to the SSR HTML (no hydration mismatch,
 * stable Radix `useId` / `aria-controls`). This effect then pulls the real
 * persisted values from localStorage, and the resulting state update is a
 * normal post-hydration client re-render that React does not diff against the
 * server markup.
 *
 * Mounted once near the root of the tree (app/layout.tsx).
 */
export function StoreHydration() {
  useEffect(() => {
    void useAuthStore.persist.rehydrate()
    void useSidebarStore.persist.rehydrate()
    void useFarmSettingsStore.persist.rehydrate()
  }, [])

  return null
}
