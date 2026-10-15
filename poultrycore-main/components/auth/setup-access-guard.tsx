"use client"

// SetupAccessGuard -- page-level enforcement for lib/nav/setup-admin-routes:
// Setup is for the account owner and employees granted admin. Mounted once in
// app/layout.tsx, like WaterAccessGuard, so a new Setup page can't forget it.
// The Farm API refuses the writes as well ([SetupAdminOnly]); this only keeps
// an ordinary employee from landing on a page whose saves would all fail.

import { useEffect } from "react"
import { usePathname, useRouter } from "next/navigation"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { isSetupAdminRoute } from "@/lib/nav/setup-admin-routes"
import { dashboardHomeForType } from "@/lib/api/companies"
import { useAuthStore } from "@/lib/store/auth-store"

export function SetupAccessGuard() {
  const pathname = usePathname()
  const router = useRouter()
  const { toast } = useToast()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  useEffect(() => {
    if (typeof window === "undefined") return
    // Wait for the flags: acting on the loading defaults would bounce admins.
    if (permissions.isLoading) return
    if (!localStorage.getItem("auth_token")) return
    if (permissions.isAdmin) return
    if (!isSetupAdminRoute(pathname)) return

    toast({ title: "Setup is for admins", description: "Ask the account owner or an admin to make this change." })
    // dashboardHomeForType predates the Restaurant type.
    router.replace(activeFarmType === "Restaurant" ? "/restaurant-dashboard" : dashboardHomeForType(activeFarmType))
  }, [pathname, router, toast, activeFarmType, permissions.isLoading, permissions.isAdmin])

  return null
}
