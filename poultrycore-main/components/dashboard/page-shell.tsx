"use client"

// PageShell — renders a page either in the normal company chrome
// (DashboardSidebar + DashboardHeader) or, when opened from the Business Office
// with ?bo=1, inside the BusinessOfficeShell. This lets pages like /employees
// and /settings be the SAME page/data/features whether reached from a company
// or from the Business Office — they just keep the right surrounding chrome.

import { ReactNode, useEffect, useState } from "react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { BusinessOfficeShell } from "@/components/dashboard/business-office-shell"
import { useLogout } from "@/hooks/use-logout"

type BoActive = "home" | "companies" | "users" | "settings" | "help"

export function PageShell({ boActive, children }: { boActive: BoActive; children: ReactNode }) {
  // null until we've read the URL on the client — avoids a flash of the wrong
  // sidebar (and any SSR/hydration mismatch from reading window during render).
  const [bo, setBo] = useState<boolean | null>(null)
  const logout = useLogout()
  useEffect(() => {
    try { setBo(new URLSearchParams(window.location.search).get("bo") === "1") } catch { setBo(false) }
  }, [])

  if (bo === null) return <div className="min-h-screen bg-slate-50" />

  // Business Office: wrap in a scroll container since the BO shell is h-screen.
  if (bo) return (
    <BusinessOfficeShell active={boActive}>
      <div className="flex-1 min-h-0 overflow-auto">{children}</div>
    </BusinessOfficeShell>
  )

  // Company chrome — matches the pages' original min-h-screen (page-scroll) layout.
  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        {children}
      </div>
    </div>
  )
}
