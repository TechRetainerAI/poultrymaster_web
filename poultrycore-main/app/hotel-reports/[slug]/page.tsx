"use client"

/**
 * Catch-all for /hotel-reports/<slug> when we haven't shipped that specific
 * report yet. The catalog on /hotel-reports labels these cards with a "Soon"
 * badge; landing here keeps the route shape valid and tells the user exactly
 * what to expect.
 *
 * As individual reports are implemented, they should live in their own
 * subdirectory (e.g. /hotel-reports/revenue-summary/page.tsx) which Next.js
 * will resolve before this catch-all.
 */

import Link from "next/link"
import { useParams } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ArrowLeft, BarChart3 } from "lucide-react"
import { useLogout } from "@/hooks/use-logout"
import { HOTEL_REPORT_GROUPS } from "@/lib/reports/hotel-reports-config"
import type { HotelReport, HotelReportGroup } from "@/lib/reports/hotel-reports-config"

/** Look up a report by slug across all groups. */
function findReport(slug: string): { report: HotelReport; group: HotelReportGroup } | null {
  for (const g of HOTEL_REPORT_GROUPS) {
    const r = g.reports.find((r) => r.slug === slug)
    if (r) return { report: r, group: g }
  }
  return null
}

export default function HotelReportCatchAllPage() {
  const params = useParams<{ slug: string }>()
  const slug = params?.slug ?? ""
  const match = findReport(slug)
  const logout = useLogout()

  // Not a known report slug
  if (!match) {
    return (
      <div className="flex min-h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0">
          <DashboardHeader />
          <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 min-w-0">
            <div className="mb-4">
              <Button asChild variant="outline" size="sm">
                <Link href="/hotel-reports"><ArrowLeft className="h-4 w-4 mr-1" /> Reports</Link>
              </Button>
            </div>

            <Card>
              <CardContent className="p-6 space-y-3">
                <div className="flex items-center gap-3">
                  <div className="rounded-lg bg-violet-100 p-2">
                    <BarChart3 className="h-6 w-6 text-violet-700" />
                  </div>
                  <h1 className="text-xl font-semibold text-slate-900">Report not found</h1>
                </div>
                <p className="text-sm text-slate-600 max-w-prose">
                  No report matches the slug <span className="font-mono">{slug}</span>. Please check the
                  URL or return to the <Link href="/hotel-reports" className="text-violet-600 hover:underline">reports catalog</Link>.
                </p>
              </CardContent>
            </Card>
          </main>
        </div>
      </div>
    )
  }

  const { report, group } = match

  // Ready reports should have their own page.tsx — if we end up here, treat as not found
  if (report.status === "ready") {
    return (
      <div className="flex min-h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0">
          <DashboardHeader />
          <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 min-w-0">
            <div className="mb-4">
              <Button asChild variant="outline" size="sm">
                <Link href="/hotel-reports"><ArrowLeft className="h-4 w-4 mr-1" /> Reports</Link>
              </Button>
            </div>

            <Card>
              <CardContent className="p-6 space-y-3">
                <div className="flex items-center gap-3">
                  <div className="rounded-lg bg-violet-100 p-2">
                    <BarChart3 className="h-6 w-6 text-violet-700" />
                  </div>
                  <h1 className="text-xl font-semibold text-slate-900">Report not found</h1>
                </div>
                <p className="text-sm text-slate-600 max-w-prose">
                  The <span className="font-medium">{report.title}</span> report page has not been created yet.
                  Return to the <Link href="/hotel-reports" className="text-violet-600 hover:underline">reports catalog</Link>.
                </p>
              </CardContent>
            </Card>
          </main>
        </div>
      </div>
    )
  }

  // Stub — show "Coming Soon" card
  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 min-w-0">
          <div className="mb-4">
            <Button asChild variant="outline" size="sm">
              <Link href="/hotel-reports"><ArrowLeft className="h-4 w-4 mr-1" /> Reports</Link>
            </Button>
          </div>

          <Card>
            <CardContent className="p-6 space-y-3">
              <div className="flex items-center gap-3">
                <div className={`rounded-lg p-2 ${group.color}`}>
                  <report.icon className="h-6 w-6 text-white" />
                </div>
                <div>
                  <h1 className="text-xl font-semibold text-slate-900">{report.title}</h1>
                  <Badge variant="outline" className="text-[10px] uppercase mt-1">Coming soon</Badge>
                </div>
              </div>
              <p className="text-sm text-slate-600 max-w-prose">
                {report.description}. This report is in the catalog but hasn't been built out yet. The Reports
                index lists it as <span className="font-medium">"Soon"</span>. Once we ship it, the page at
                <span className="font-mono"> /hotel-reports/{slug}</span> will replace this stub automatically.
              </p>
              <p className="text-sm text-slate-600 max-w-prose">
                In the meantime, check out other reports from the{" "}
                <Link href="/hotel-reports" className="text-violet-600 hover:underline">reports catalog</Link>.
              </p>
            </CardContent>
          </Card>
        </main>
      </div>
    </div>
  )
}
