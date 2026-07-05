"use client"

/** Poultry Reports — index page. A simple catalog of the driver reports. */

import Link from "next/link"
import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { BarChart3, Wallet, ClipboardCheck, Truck } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"

const REPORTS = [
  {
    slug: "driver-collection",
    title: "Driver Collection",
    description: "Per-driver crates loaded/sold, expected vs collected cash, shortages, plus per-product detail.",
    icon: Wallet,
    color: "bg-emerald-500",
  },
  {
    slug: "driver-accountability",
    title: "Driver Accountability",
    description: "Per-driver crates loaded/sold/returned, expected vs accounted revenue, and shortages.",
    icon: ClipboardCheck,
    color: "bg-sky-500",
  },
  {
    slug: "delivery-run-report",
    title: "Delivery Run Report",
    description: "Vehicle loadings and their reconciliation status over a period.",
    icon: Truck,
    color: "bg-indigo-500",
  },
]

export default function PoultryReportsIndexPage() {
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

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {REPORTS.map((r) => (
              <Card key={r.slug} className="hover:shadow-md transition-shadow">
                <CardContent className="p-4 flex flex-col h-full">
                  <div className="flex items-start gap-3">
                    <div className={`w-10 h-10 rounded-lg ${r.color} flex items-center justify-center shrink-0`}>
                      <r.icon className="w-5 h-5 text-white" />
                    </div>
                    <div className="min-w-0 flex-1">
                      <h3 className="font-medium text-slate-900 truncate">{r.title}</h3>
                      <p className="text-xs text-slate-500 mt-1 line-clamp-2">{r.description}</p>
                    </div>
                  </div>
                  <div className="mt-3 flex justify-end">
                    <Button asChild size="sm">
                      <Link href={`/poultry-reports/${r.slug}`}>View report</Link>
                    </Button>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </main>
      </div>
    </div>
  )
}
