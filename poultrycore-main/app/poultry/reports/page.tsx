"use client"

// =============================================================================
// Poultry Reports — index page (catalogue).
//
// Mirrors the water side (/water-reports): a data-driven catalogue that lists
// EVERY poultry report. Both the top-nav Reports mega-menu "View all reports →"
// and the Back button on each individual report land here, so this is the single
// browsable home for all reports.
//
// Layout: one card per group in a plain CSS grid. It was a masonry column flow,
// which balances by HEIGHT — with eleven groups (three of them a single row)
// the columns broke wherever they liked and nothing lined up. The catalogue is
// now four groups of 7/6/9/7 (see POULTRY_REPORT_MENU_GROUPS), which a
// three-column grid lays out as 3 + 1.
//
// Driven by POULTRY_REPORT_MENU_GROUPS (the 21 data-driven reports + Batch
// Production Summary + Feed Production + the four dashboards + Closing +
// Changes), each item carrying a ready `href`.
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
                  {TOTAL_REPORTS} reports in {POULTRY_REPORT_MENU_GROUPS.length} sections — each with its
                  own filters, summary cards and PDF export.
                </p>
              </div>
            </div>

            {/* One card per group. items-start so the short groups on the second
                row keep their own height instead of stretching to the tallest. */}
            <div className="grid grid-cols-1 items-start gap-4 sm:grid-cols-2 lg:grid-cols-3">
              {POULTRY_REPORT_MENU_GROUPS.map((g) => (
                <section
                  key={g.key}
                  className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm"
                >
                  <div className="flex items-start gap-2.5 border-b border-slate-100 px-3 py-2.5">
                    {/* An accent bar rather than a dot: it carries the group's
                        colour without competing with the row icons. */}
                    <span className={`mt-0.5 h-7 w-1 shrink-0 rounded-full ${g.color}`} />
                    <div className="min-w-0 flex-1">
                      <h2 className="truncate text-sm font-semibold text-slate-900">{g.label}</h2>
                      <p className="truncate text-[11px] text-slate-500">{g.blurb}</p>
                    </div>
                    <span className="shrink-0 rounded-full bg-slate-100 px-2 py-0.5 text-[11px] font-medium text-slate-600">
                      {g.items.length}
                    </span>
                  </div>

                  <div className="p-1.5">
                    {g.items.map((r) => (
                      <Link
                        key={r.id}
                        href={r.href}
                        className="group flex items-center gap-2.5 rounded-lg px-2 py-2 transition-colors hover:bg-slate-50"
                      >
                        <div className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-md ${g.tint}`}>
                          <r.icon className="h-4 w-4" />
                        </div>
                        <div className="min-w-0 flex-1">
                          <h3 className="truncate text-sm font-medium text-slate-900">{r.title}</h3>
                          <p className="truncate text-[11px] text-slate-500">{r.description}</p>
                        </div>
                        <ChevronRight className="h-4 w-4 shrink-0 text-slate-300 transition-colors group-hover:text-slate-400" />
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
