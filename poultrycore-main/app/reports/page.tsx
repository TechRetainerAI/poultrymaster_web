"use client"

import { useState, useEffect, Suspense } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { BarChart3, Plus, Egg, TrendingUp, CalendarDays, Wallet } from "lucide-react"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { useIsMobile } from "@/hooks/use-mobile"
import { useLogout } from "@/hooks/use-logout"
import { cn } from "@/lib/utils"
import {
  usePoultryDashboardData,
  DashboardFilterBar,
  PoultryDashboardSection,
  type DashboardView,
} from "@/components/poultry-reports/poultry-dashboard-view"

const VALID_TABS: DashboardView[] = ["production", "financial", "daily", "insights"]

function ReportsPageInner() {
  const isMobile = useIsMobile()
  const router = useRouter()
  const searchParams = useSearchParams()
  const logout = useLogout()

  // The dashboard data + filters live in the shared hook (single source of
  // truth shared with the dedicated /poultry/reports/<view> pages).
  const data = usePoultryDashboardData()

  // Tab can be deep-linked via ?tab= (used by the Reports mega-menu / catalogue
  // "Farm Dashboards" links). Falls back to Production.
  const initialTab = (() => {
    const t = searchParams.get("tab")
    return t && VALID_TABS.includes(t as DashboardView) ? (t as DashboardView) : "production"
  })()
  const [tab, setTab] = useState<DashboardView>(initialTab)

  // Keep the tab in sync when the ?tab= param changes (e.g. picking another
  // dashboard from the mega-menu while already on /reports).
  useEffect(() => {
    const t = searchParams.get("tab")
    if (t && VALID_TABS.includes(t as DashboardView) && t !== tab) setTab(t as DashboardView)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchParams])

  const changeTab = (v: string) => {
    setTab(v as DashboardView)
    router.replace(`/reports?tab=${v}`, { scroll: false })
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            {/* Page Header — aligned with Health Records */}
            <div className={cn("flex gap-4", isMobile ? "flex-col" : "items-center justify-between")}>
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-blue-100 rounded-lg flex items-center justify-center">
                  <BarChart3 className="w-5 h-5 text-blue-600" />
                </div>
                <div className="min-w-0">
                  <h1 className={cn("font-bold text-slate-900", isMobile ? "text-xl" : "text-2xl")}>Reports</h1>
                  <p className="text-sm text-slate-600">Comprehensive farm analytics and insights</p>
                </div>
              </div>
              <Button className={cn("gap-2 bg-blue-600 hover:bg-blue-700 shrink-0", isMobile && "w-full sm:w-auto h-11 sm:h-10")}>
                <Plus className="w-4 h-4" />
                New Report
              </Button>
            </div>

            {/* Tabs + filters — same pattern as Health Records (web + mobile) */}
            <Tabs value={tab} onValueChange={changeTab} className="w-full">
              <TabsList
                className={cn(
                  "w-full",
                  isMobile && "grid h-auto grid-cols-2 gap-1 sm:grid-cols-4"
                )}
              >
                <TabsTrigger value="production" className={cn(isMobile && "min-w-0 px-2 py-2 text-xs")}>
                  <Egg className={cn("w-4 h-4 shrink-0", isMobile ? "mr-1" : "mr-2")} />
                  Production
                </TabsTrigger>
                <TabsTrigger value="financial" className={cn(isMobile && "min-w-0 px-2 py-2 text-xs")}>
                  <Wallet className={cn("w-4 h-4 shrink-0", isMobile ? "mr-1" : "mr-2")} />
                  Financial
                </TabsTrigger>
                <TabsTrigger value="daily" className={cn(isMobile && "min-w-0 px-2 py-2 text-xs")}>
                  <CalendarDays className={cn("w-4 h-4 shrink-0", isMobile ? "mr-1" : "mr-2")} />
                  {isMobile ? "Daily" : "Daily Report"}
                </TabsTrigger>
                <TabsTrigger value="insights" className={cn(isMobile && "min-w-0 px-2 py-2 text-xs")}>
                  <TrendingUp className={cn("w-4 h-4 shrink-0", isMobile ? "mr-1" : "mr-2")} />
                  {isMobile ? "More" : "More Reports"}
                </TabsTrigger>
              </TabsList>

              <DashboardFilterBar data={data} />
            </Tabs>

            <div className="space-y-4">
              <PoultryDashboardSection view={tab} data={data} />
            </div>
          </div>
        </main>
      </div>
    </div>
  )
}

// useSearchParams must sit under a Suspense boundary for the page shell.
export default function ReportsPage() {
  return (
    <Suspense fallback={null}>
      <ReportsPageInner />
    </Suspense>
  )
}
