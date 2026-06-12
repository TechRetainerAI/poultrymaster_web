"use client"

/**
 * Reports — index page (Prompt 2 §16-§17).
 *
 * Categorised report cards covering Financial, Sales/Customers,
 * Production/Inventory, and Delivery/Operations. The catalog is data-driven
 * so future reports can be added by editing one array.
 *
 * Each card links to a focused report page under /water-reports/<slug>.
 * Reports we haven't built yet land on a "Coming soon" stub so the catalog
 * stays accurate during rollout — and the user can still navigate without
 * dead links.
 */

import Link from "next/link"
import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { BarChart3 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { WATER_REPORT_GROUPS, waterReportHref } from "@/lib/reports/water-reports-config"

export default function WaterReportsIndexPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") router.replace("/dashboard")
  }, [activeFarmType, router])

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="mb-6 flex items-start gap-3">
            <div className="rounded-lg bg-sky-100 p-2"><BarChart3 className="h-6 w-6 text-sky-700" /></div>
            <div>
              <h1 className="text-2xl font-semibold text-slate-900">Reports</h1>
              <p className="text-sm text-slate-500">
                Choose a report below. Each report has its own filters, summary cards, and PDF export.
              </p>
            </div>
          </div>

          <div className="space-y-6">
            {WATER_REPORT_GROUPS.map((g) => (
              <section key={g.label}>
                <div className="flex items-center gap-2 mb-2">
                  <span className={`inline-block h-2 w-2 rounded-full ${g.color}`} />
                  <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600">{g.label}</h2>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                  {g.reports.map((r) => (
                    <Card key={r.slug} className="hover:shadow-md transition-shadow">
                      <CardContent className="p-4 flex flex-col h-full">
                        <div className="flex items-start gap-3">
                          <div className={`w-10 h-10 rounded-lg ${g.color} flex items-center justify-center shrink-0`}>
                            <r.icon className="w-5 h-5 text-white" />
                          </div>
                          <div className="min-w-0 flex-1">
                            <div className="flex items-center justify-between gap-2">
                              <h3 className="font-medium text-slate-900 truncate">{r.title}</h3>
                              {r.status === "stub" && (
                                <Badge variant="outline" className="text-[10px] uppercase">Soon</Badge>
                              )}
                            </div>
                            <p className="text-xs text-slate-500 mt-1 line-clamp-2">{r.description}</p>
                          </div>
                        </div>
                        <div className="mt-3 flex justify-end">
                          <Button asChild size="sm" variant={r.status === "ready" ? "default" : "outline"}>
                            <Link href={waterReportHref(r.slug)}>
                              {r.status === "ready" ? "View report" : "Preview"}
                            </Link>
                          </Button>
                        </div>
                      </CardContent>
                    </Card>
                  ))}
                </div>
              </section>
            ))}
          </div>
        </main>
      </div>
    </div>
  )
}
