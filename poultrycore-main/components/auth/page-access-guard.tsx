"use client"

// =============================================================================
// PageAccessGuard — one guard for every page, every company type.
//
// Wraps the whole app in app/layout.tsx. When per-company page access is live
// (migrations 506/507) it decides each URL with the same rule the menus use
// (lib/iam/page-registry canOpenPath), and renders <AccessRestricted/> INSTEAD
// of the page — the page never mounts, so it never requests its data. Typing
// /poultry-profit-loss with Profit & Loss unticked shows the message, not the
// figures. The API refuses the data as well (IamEnforcementFilter); this is the
// friendly half.
//
// Before 506/507 are applied it renders children untouched and the older
// Water/Hotel/Setup guards keep doing what they always did.
// =============================================================================

import { useEffect, useRef, useState } from "react"
import { usePathname } from "next/navigation"
import { usePermissions, PERMISSIONS_STALE_EVENT } from "@/hooks/use-permissions"
import { useAuthStore } from "@/lib/store/auth-store"
import { resolvePathAccess } from "@/lib/iam/page-registry"
import { AccessRestricted } from "@/components/auth/access-restricted"
import { announceRefusal } from "@/lib/iam/announce-refusal"

const DASHBOARD_BY_TYPE: Record<string, string> = {
  Poultry: "/dashboard",
  Water: "/water-dashboard",
  Generic: "/generic-dashboard",
  Hotel: "/hotel-dashboard",
  Restaurant: "/restaurant-dashboard",
  Livestock: "/livestock-dashboard",
}

/**
 * Any fetch through the proxy that comes back 403 means the person's access
 * changed (or never included this). Tell every usePermissions to re-read so
 * menus catch up at once. Installed once per tab.
 */
function useForbiddenSignal() {
  const installed = useRef(false)
  useEffect(() => {
    if (installed.current || typeof window === "undefined") return
    installed.current = true
    const w = window as typeof window & { __pageAccessFetchPatched?: boolean }
    if (w.__pageAccessFetchPatched) return
    w.__pageAccessFetchPatched = true
    const original = window.fetch.bind(window)
    window.fetch = async (...args: Parameters<typeof fetch>) => {
      const res = await original(...args)
      if (res.status === 403) {
        const url = typeof args[0] === "string" ? args[0] : args[0] instanceof URL ? args[0].href : args[0].url
        if (url.includes("/api/proxy/") && !url.includes("/Iam/")) {
          window.dispatchEvent(new Event(PERMISSIONS_STALE_EVENT))
          const method = (args[1]?.method ?? (args[0] instanceof Request ? args[0].method : "GET")).toUpperCase()
          if (method !== "GET" && method !== "HEAD") res.clone().json().then(announceRefusal, () => {})
        }
      }
      return res
    }
  }, [])
}

export function PageAccessGuard({ children }: { children: React.ReactNode }) {
  useForbiddenSignal()
  const pathname = usePathname() ?? "/"
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  // localStorage is only readable after mount; deciding earlier would render
  // differently on the server and the client.
  const [mounted, setMounted] = useState(false)
  useEffect(() => setMounted(true), [])
  // The page last shown for this company. While access is merely being
  // re-checked (focus, every minute, after a 403) it stays on screen instead of
  // unmounting — unmounting throws away the page's state and makes it reload.
  const shownFor = useRef<string | null>(null)
  const here = `${activeFarmType ?? ""}|${pathname}`

  const access = resolvePathAccess(pathname, activeFarmType)
  if (access.kind === "public" || access.kind === "member") return <>{children}</>

  // Never flash protected content while the active company's grants (and
  // which era we are in) load. One small request per company switch.
  if (!mounted) return null
  const signedIn = !!localStorage.getItem("auth_token")
  if (signedIn && !permissions.accessLoaded) return shownFor.current === here ? <>{children}</> : null

  // Not the page-access era: leave everything as it was.
  if (!permissions.pageAccess) { shownFor.current = here; return <>{children}</> }

  if (permissions.canOpen(pathname)) { shownFor.current = here; return <>{children}</> }
  shownFor.current = null
  return <AccessRestricted homeHref={DASHBOARD_BY_TYPE[activeFarmType ?? ""] ?? "/dashboard"} />
}
