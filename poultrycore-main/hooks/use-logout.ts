"use client"

import { useCallback } from "react"
import { useRouter } from "next/navigation"

const KEYS_TO_CLEAR = [
  "auth_token", "refresh_token", "username", "userName", "userId",
  "farmId", "farmName", "farmType", "isStaff", "isSubscriber",
  "roles", "auth-storage",
]

export function useLogout() {
  const router = useRouter()
  return useCallback(() => {
    if (typeof window !== "undefined") {
      for (const k of KEYS_TO_CLEAR) localStorage.removeItem(k)
    }
    router.push("/login")
  }, [router])
}
