"use client"

// The frame every Projects & Contracts page shares: Generic only, the usual
// sidebar/header, a back arrow and a title. Also says plainly when the module
// is switched off (history still readable, nothing new can be assigned).

import { useEffect, type ReactNode } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { ArrowLeft, Info } from "lucide-react"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useProjectsEnabled } from "@/hooks/use-generic-projects"

export function ProjectPage({
  title, subtitle, icon, actions, children, back, wide = true, projectsBanner = true,
}: {
  title: ReactNode
  subtitle?: ReactNode
  icon?: ReactNode
  actions?: ReactNode
  children: ReactNode
  back?: string
  wide?: boolean
  /** Say when the Projects module is off. False on pages any Generic company uses. */
  projectsBanner?: boolean
}) {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { enabled, isLoading } = useProjectsEnabled()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") router.replace("/dashboard")
  }, [activeFarmType, router])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex min-w-0 flex-1 flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6">
          {/* Full width: these pages carry wide tables and two-column forms. */}
          <div className="w-full space-y-4">
            <div className="flex flex-wrap items-center gap-3">
              <button onClick={() => (back ? router.push(back) : router.back())}
                className="rounded-full p-1 transition hover:bg-slate-200" title="Go back">
                <ArrowLeft className="h-5 w-5 text-slate-600" />
              </button>
              <div className="min-w-0 flex-1">
                <h1 className="flex items-center gap-2 text-xl font-semibold text-slate-900">{icon}{title}</h1>
                {subtitle && <div className="mt-0.5 text-sm text-slate-500">{subtitle}</div>}
              </div>
              {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
            </div>
            {projectsBanner && !isLoading && !enabled && (
              <div className="flex gap-2 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
                <Info className="mt-0.5 h-4 w-4 shrink-0" />
                <span>
                  Projects &amp; Contracts is switched off for this company. Existing projects and their history are kept and can be read,
                  but new transactions can&apos;t be assigned to a project. <Link href="/generic-business-features" className="font-medium underline">Turn it on in Business Features</Link>.
                </span>
              </div>
            )}
            {children}
          </div>
        </main>
      </div>
    </div>
  )
}
