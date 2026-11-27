"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { useAuthStore } from "@/lib/store/auth-store"

/**
 * The Help Center is poultry-specific (flocks, eggs, birds, vaccinations).
 * Send Water/Generic users to their dashboard until type-specific help pages
 * exist. Waits for Zustand to hydrate before deciding.
 */
export function usePoultryHelpRedirect() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType === "Water")        router.replace("/water-dashboard")
    else if (activeFarmType === "Generic") router.replace("/generic-dashboard")
  }, [activeFarmType, router])
}
