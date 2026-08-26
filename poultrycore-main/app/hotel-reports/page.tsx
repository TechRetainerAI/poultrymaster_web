"use client"

/**
 * Hotel Reports — index page.
 *
 * Categorised report catalogue covering Financial, Operations,
 * Restaurant & Bar, and Housekeeping & Inventory. The catalog is data-driven
 * so future reports can be added by editing hotel-reports-config.ts.
 *
 * Layout mirrors the water-reports side: a masonry column flow so every group
 * packs tightly under the next with no wasted rows. Each row links to a
 * focused report page under /hotel-reports/<slug>; reports we haven't built yet
 * land on a "Coming soon" stub so the catalog stays accurate during rollout.
 */

import Link from "next/link"
import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Badge } from "@/components/ui/badge"
import { BarChart3, ChevronRight } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { HOTEL_REPORT_GROUPS } from "@/lib/reports/hotel-reports-config"

const TOTAL_REPORTS = HOTEL_REPORT_GROUPS.reduce((n, g) => n + g.reports.length, 0)

export default function HotelReportsIndexPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Hotel") router.replace("/dashboard")
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
              <div className="rounded-xl bg-violet-100 p-2.5">
                <BarChart3 className="h-6 w-6 text-violet-700" />
              </div>
              <div>
                <h1 className="text-2xl font-semibold text-slate-900">Reports</h1>
                <p className="mt-0.5 text-sm text-slate-500">
                  {TOTAL_REPORTS} reports — each with its own filters, summary cards and PDF export.
                </p>
              </div>
            </div>

            {/* Masonry column flow — groups pack tightly with no wasted rows. */}
            <div className="columns-1 sm:columns-2 lg:columns-3 xl:columns-4 gap-4">
              {HOTEL_REPORT_GROUPS.map((g) => (
                <section key={g.key} className="mb-4 break-inside-avoid">
                  <div className="mb-2 flex items-center gap-2 px-1">
                    <span className={`inline-block h-2 w-2 rounded-full ${g.color}`} />
                    <h2 className="text-[11px] font-semibold uppercase tracking-wider text-slate-500">{g.label}</h2>
                    <span className="text-[11px] font-normal text-slate-400">{g.reports.length}</span>
                  </div>

                  <div className="space-y-1.5">
                    {g.reports.map((r) => (
                      <Link
                        key={r.slug}
                        href={`/hotel-reports/${r.slug}`}
                        className="flex items-center gap-2.5 rounded-lg border border-slate-200 bg-white px-2.5 py-2 hover:border-violet-300 hover:bg-violet-50/50 transition-colors group"
                      >
                        <div className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-md text-white ${g.color}`}>
                          <r.icon className="h-4 w-4" />
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="text-sm font-medium text-slate-900 truncate">{r.title}</div>
                          <div className="text-[11px] text-slate-500 truncate">{r.description}</div>
                        </div>
                        {r.status === "stub" && (
                          <Badge className="bg-amber-100 text-amber-700 text-[10px]">Soon</Badge>
                        )}
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
