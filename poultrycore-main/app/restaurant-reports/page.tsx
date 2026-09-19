"use client"

/**
 * Restaurant Reports — the catalog.
 *
 * This replaces the previous 554-line single page whose seven tabs were the
 * whole of restaurant reporting. Each card here links to a real route under
 * /restaurant-reports/<slug>, so a report can be linked to, bookmarked and sent
 * to someone — none of which was possible when every menu entry resolved to the
 * same page's default tab.
 *
 * The grid is data-driven from restaurant-reports-config, so adding a report
 * never means editing this file.
 */

import Link from "next/link"
import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { BarChart3, ChevronRight, Eye, FileSpreadsheet } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import {
  RESTAURANT_REPORT_GROUPS, TOTAL_RESTAURANT_REPORTS,
} from "@/lib/reports/restaurant-reports-config"

export default function RestaurantReportsIndexPage() {
  const router = useRouter()
  const logout = useLogout()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const permissions = usePermissions()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Restaurant") router.replace("/dashboard")
  }, [activeFarmType, router])

  const allowed = permissions.isAdmin || permissions.featureAccess.canViewReports

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 min-w-0">
          <div className="mx-auto w-full max-w-7xl">
            <div className="mb-5 flex items-start gap-3">
              <div className="rounded-xl bg-rose-100 p-2.5 shrink-0">
                <BarChart3 className="h-6 w-6 text-rose-700" />
              </div>
              <div className="min-w-0">
                <h1 className="text-2xl font-semibold text-slate-900">Reports</h1>
                <p className="mt-0.5 text-sm text-slate-500">
                  {TOTAL_RESTAURANT_REPORTS} reports. Every one takes a date range, previews as a
                  PDF before you download it, and exports to CSV.
                </p>
              </div>
            </div>

            {!allowed ? (
              <Card className="max-w-lg">
                <CardContent className="p-6 space-y-2">
                  <h2 className="text-lg font-semibold text-slate-900">Reports are restricted</h2>
                  <p className="text-sm text-slate-600">
                    Your account does not have permission to view restaurant reports. An
                    administrator can grant this under Users &amp; Permissions.
                  </p>
                </CardContent>
              </Card>
            ) : (
              <>
                {/* Masonry column flow, matching the hotel and water catalogs:
                    groups pack tightly with no wasted rows between them. */}
                <div className="columns-1 md:columns-2 xl:columns-3 gap-4 [column-fill:_balance]">
                  {RESTAURANT_REPORT_GROUPS.map((g) => (
                    <div key={g.key} className="break-inside-avoid mb-4">
                      <Card className="overflow-hidden">
                        <div className={`px-4 py-2.5 ${g.color}`}>
                          <h2 className="text-sm font-semibold text-white uppercase tracking-wide">
                            {g.label}
                          </h2>
                        </div>
                        <CardContent className="p-0">
                          {g.reports.map((r) => {
                            const Icon = r.icon
                            return (
                              <Link
                                key={r.slug}
                                href={`/restaurant-reports/${r.slug}`}
                                className="flex items-start gap-3 px-4 py-3 border-b last:border-0 hover:bg-slate-50 transition-colors group"
                              >
                                <Icon className="h-4 w-4 mt-0.5 text-slate-400 group-hover:text-rose-600 shrink-0" />
                                <div className="min-w-0 flex-1">
                                  <div className="flex items-center gap-2 flex-wrap">
                                    <span className="text-sm font-medium text-slate-900">{r.title}</span>
                                    {r.isNew && (
                                      <Badge className="bg-rose-100 text-rose-700 hover:bg-rose-100 text-[10px] px-1.5 py-0">
                                        New
                                      </Badge>
                                    )}
                                  </div>
                                  <p className="text-xs text-slate-500 mt-0.5">{r.description}</p>
                                </div>
                                {/* Always visible, never hover-only: an opacity-0
                                    group-hover affordance is unreachable on a
                                    touch screen, which plan.md records as a
                                    recurring bug across the restaurant rows. */}
                                <ChevronRight className="h-4 w-4 text-slate-300 group-hover:text-rose-600 shrink-0 mt-0.5" />
                              </Link>
                            )
                          })}
                        </CardContent>
                      </Card>
                    </div>
                  ))}
                </div>

                <div className="mt-6 flex items-center gap-4 text-xs text-slate-500 flex-wrap">
                  <span className="flex items-center gap-1.5"><Eye className="h-3.5 w-3.5" /> View the PDF before downloading</span>
                  <span className="flex items-center gap-1.5"><FileSpreadsheet className="h-3.5 w-3.5" /> CSV export on every report</span>
                </div>
              </>
            )}
          </div>
        </main>
      </div>
    </div>
  )
}
