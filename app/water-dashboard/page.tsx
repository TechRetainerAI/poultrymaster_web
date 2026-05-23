"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Droplets, Package, Users, ShoppingCart, Wallet, AlertCircle, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { getWaterDashboardSummary, type WaterDashboardSummary } from "@/lib/api/water"

function fmtMoney(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

export default function WaterDashboardPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmName = useAuthStore((s) => s.activeFarmName)
  const logout = useLogout()
  const [summary, setSummary] = useState<WaterDashboardSummary | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Water") {
      router.replace("/dashboard")
      return
    }
    let cancelled = false
    ;(async () => {
      try {
        const s = await getWaterDashboardSummary()
        if (!cancelled) setSummary(s)
      } catch (e: any) {
        if (!cancelled) setError(e?.message ?? String(e))
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => { cancelled = true }
  }, [activeFarmType, router])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <div className="mb-6">
            <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2">
              <Droplets className="h-6 w-6 text-sky-600" />
              {activeFarmName ?? "Water company"} dashboard
            </h1>
            <p className="text-sm text-slate-500">Stock, sales and receivables for your water business.</p>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : error ? (
            <Card className="border-red-200 bg-red-50">
              <CardContent className="flex items-center gap-2 p-4 text-red-700">
                <AlertCircle className="h-4 w-4" /> {error}
              </CardContent>
            </Card>
          ) : summary ? (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              <StatCard icon={Package}  title="Active products"  value={summary.activeProducts} accent="sky" />
              <StatCard icon={Users}    title="Customers"         value={summary.totalCustomers} accent="emerald" />
              <StatCard icon={Droplets} title="Stock on hand"     value={summary.totalStockOnHand} suffix="units" accent="cyan" />
              <StatCard icon={ShoppingCart} title="Sales today"   value={fmtMoney(summary.salesToday)} accent="orange" />
              <StatCard icon={ShoppingCart} title="Sales this month" value={fmtMoney(summary.salesThisMonth)} accent="amber" />
              <StatCard icon={Wallet}   title="Outstanding"       value={fmtMoney(summary.outstandingReceivables)} accent="rose" />
            </div>
          ) : null}
        </main>
      </div>
    </div>
  )
}

function StatCard({
  icon: Icon, title, value, suffix, accent,
}: {
  icon: any
  title: string
  value: string | number
  suffix?: string
  accent: "sky" | "emerald" | "cyan" | "orange" | "amber" | "rose"
}) {
  const accentMap: Record<string, string> = {
    sky:     "text-sky-600 bg-sky-50",
    emerald: "text-emerald-600 bg-emerald-50",
    cyan:    "text-cyan-600 bg-cyan-50",
    orange:  "text-orange-600 bg-orange-50",
    amber:   "text-amber-600 bg-amber-50",
    rose:    "text-rose-600 bg-rose-50",
  }
  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between pb-1">
        <CardTitle className="text-xs uppercase tracking-wide text-slate-500">{title}</CardTitle>
        <div className={`rounded-md p-2 ${accentMap[accent]}`}>
          <Icon className="h-4 w-4" />
        </div>
      </CardHeader>
      <CardContent>
        <div className="text-2xl font-semibold text-slate-900">{value}{suffix ? <span className="text-sm text-slate-500 ml-1">{suffix}</span> : null}</div>
      </CardContent>
    </Card>
  )
}
