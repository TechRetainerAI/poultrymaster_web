"use client"

// =============================================================================
// Poultry Reports — index page (catalogue).
//
// Mirrors the water side (/water-reports): a data-driven catalogue that lists
// EVERY poultry report. Both the top-nav Reports mega-menu "View all reports →"
// and the Back button on each individual report land here, so this is the single
// browsable home for all reports.
//
// Layout: a masonry column flow (like the Reports mega-menu) so every group packs
// tightly under the next with no wasted rows — the whole catalogue fits on ~one
// screen with minimal scrolling. Driven by POULTRY_REPORT_MENU_GROUPS (the 20
// advanced reports + Batch Production Summary + Farm Dashboards + Closing +
// Activity), each item carrying a ready `href`.
// =============================================================================

import Link from "next/link"
import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { BarChart3, ChevronRight } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { POULTRY_REPORT_MENU_GROUPS } from "@/lib/reports/poultry-reports-config"

const TOTAL_REPORTS = POULTRY_REPORT_MENU_GROUPS.reduce((n, g) => n + g.items.length, 0)

export default function PoultryReportsIndexPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  // Gate: this catalogue only exists inside a Poultry company context.
  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="mx-auto w-full max-w-7xl">
            {/* Page header */}
            <div className="mb-5 flex items-start gap-3">
              <div className="rounded-xl bg-blue-100 p-2.5">
                <BarChart3 className="h-6 w-6 text-blue-700" />
              </div>
              <div>
                <h1 className="text-2xl font-semibold text-slate-900">Reports</h1>
                <p className="mt-0.5 text-sm text-slate-500">
                  {TOTAL_REPORTS} reports — each with its own filters, summary cards and PDF export.
                </p>
              </div>
            </div>

            {/* Masonry column flow — groups pack tightly with no wasted rows. */}
            <div className="columns-1 gap-4 sm:columns-2 lg:columns-3 xl:columns-4">
              {POULTRY_REPORT_MENU_GROUPS.map((g) => (
                <section key={g.key} className="mb-4 break-inside-avoid">
                  <div className="mb-2 flex items-center gap-2 px-1">
                    <span className={`inline-block h-2 w-2 rounded-full ${g.color}`} />
                    <h2 className="text-[11px] font-semibold uppercase tracking-wider text-slate-500">{g.label}</h2>
                    <span className="text-[11px] font-normal text-slate-400">{g.items.length}</span>
                  </div>

                  <div className="space-y-1.5">
                    {g.items.map((r) => (
                      <Link
                        key={r.id}
                        href={r.href}
                        className="group flex items-center gap-2.5 rounded-lg border border-slate-200 bg-white px-2.5 py-2 transition-colors hover:border-slate-300 hover:bg-slate-50"
                      >
                        <div className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-md ${g.color}`}>
                          <r.icon className="h-4 w-4 text-white" />
                        </div>
                        <div className="min-w-0 flex-1">
                          <h3 className="truncate text-sm font-medium text-slate-900">{r.title}</h3>
                          <p className="truncate text-[11px] text-slate-500">{r.description}</p>
                        </div>
                        <ChevronRight className="h-4 w-4 shrink-0 text-slate-300 opacity-0 transition-opacity group-hover:opacity-100" />
                      </Link>
                    ))}
                  </div>
                </section>
              ))}
            </div>
          </div>
        </main>
      </div>
    </div>
  )
}
