"use client"

import { useEffect } from "react"
import { usePathname, useRouter } from "next/navigation"
import { usePermissions } from "@/hooks/use-permissions"
import { useAuthStore } from "@/lib/store/auth-store"
import { isGatedHotelRoute, isHotelNavItemVisible } from "@/lib/utils/hotel-nav-access"

export function HotelAccessGuard() {
  const pathname = usePathname()
  const router = useRouter()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  useEffect(() => {
    if (typeof window === "undefined") return
    if (!pathname) return
    if (permissions.isLoading) return
    if (activeFarmType !== "Hotel") return
    if (!localStorage.getItem("auth_token")) return

    const base = `/${(pathname.split("/")[1] ?? "")}`
    if (!isGatedHotelRoute(base)) return
    if (isHotelNavItemVisible(base, permissions.featureAccess, permissions.isAdmin)) return

    router.replace("/hotel-dashboard")
  }, [
    pathname,
    router,
    activeFarmType,
    permissions.isLoading,
    permissions.featureAccess,
    permissions.isAdmin,
  ])

  return null
}
