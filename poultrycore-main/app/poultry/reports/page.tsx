"use client"

// =============================================================================
// Advanced Poultry Reports — landing / catalogue page (/poultry/reports).
// Only shown inside a Poultry company context. Additive: does not replace the
// existing /reports poultry dashboard.
// =============================================================================

import { useEffect } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { BarChart3, ArrowLeft } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { POULTRY_REPORT_MENU_GROUPS } from "@/lib/reports/poultry-reports-config"

export default function PoultryReportsLandingPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Poultry") router.replace("/dashboard")
  }, [activeFarmType, router])

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="p-4 sm:p-6 pb-16 min-w-0">
          <Button asChild variant="outline" size="sm" className="mb-4">
            <Link href="/reports"><ArrowLeft className="h-4 w-4 mr-1" /> Reports</Link>
          </Button>
          <div className="flex items-start gap-3 mb-6">
            <div className="rounded-lg bg-amber-100 p-2">
              <BarChart3 className="h-6 w-6 text-amber-700" />
            </div>
            <div>
              <h1 className="text-2xl font-semibold text-slate-900">Advanced Poultry Reports</h1>
              <p className="text-sm text-slate-500">
                Production, birds &amp; mortality, feed, inventory, sales, expenses, profitability and health —
                each report has its own filters and CSV / PDF export.
              </p>
            </div>
          </div>

          <div className="space-y-6">
            {POULTRY_REPORT_MENU_GROUPS.map((group) => (
              <section key={group.key}>
                <div className="flex items-center gap-2 mb-2">
                  <span className={`inline-block h-2.5 w-2.5 rounded-full ${group.color}`} />
                  <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-700">{group.label}</h2>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                  {group.items.map((r) => (
                    <Card key={r.id} className="hover:shadow-md transition-shadow">
                      <CardContent className="p-4">
                        <div className="flex items-start gap-3">
                          <div className={`w-10 h-10 rounded-lg ${group.color} flex items-center justify-center shrink-0`}>
                            <r.icon className="w-5 h-5 text-white" />
                          </div>
                          <div className="flex-1 min-w-0">
                            <h3 className="font-medium text-slate-900">{r.title}</h3>
                            <p className="text-xs text-slate-500 mt-1">{r.description}</p>
                          </div>
                        </div>
                        <Button asChild size="sm" className="mt-3 w-full">
                          <Link href={r.href}>View report</Link>
                        </Button>
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
