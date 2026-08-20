"use client"

// =============================================================================
// WaterAccessGuard — page-level enforcement for the water Staff Page Access
// flags.
//
// Hiding a nav row is not access control; without this, a staff member who
// can't see Payroll in the menu still reaches it by typing /water-payroll.
//
// Mounted once in app/layout.tsx (beside SubscriptionGuard) rather than added
// page by page. There is no shared layout under the ~29 app/water-* route
// folders, so the alternative was a hook call in every one of them — easy to
// forget on the next page someone adds, and the point of a guard is that it
// can't be forgotten.
//
// Deliberately narrow: it only acts on a `/water-*` path that
// lib/utils/water-nav-access has an explicit rule for, only inside a Water
// company, and only once permissions have finished loading.
// =============================================================================

import { useEffect } from "react"
import { usePathname, useRouter } from "next/navigation"
import { usePermissions } from "@/hooks/use-permissions"
import { useAuthStore } from "@/lib/store/auth-store"
import { isGatedWaterRoute, isWaterNavItemVisible } from "@/lib/utils/water-nav-access"

export function WaterAccessGuard() {
  const pathname = usePathname()
  const router = useRouter()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  useEffect(() => {
    if (typeof window === "undefined") return
    if (!pathname) return
    // Wait for the flags: acting while they're still the loading defaults would
    // bounce people off pages they're allowed to see.
    if (permissions.isLoading) return
    if (activeFarmType !== "Water") return
    if (!localStorage.getItem("auth_token")) return

    // Detail routes (/water-drivers/12) are governed by their list route.
    const base = `/${(pathname.split("/")[1] ?? "")}`
    if (!isGatedWaterRoute(base)) return
    if (isWaterNavItemVisible(base, permissions.featureAccess, permissions.isAdmin)) return

    router.replace("/water-dashboard")
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
