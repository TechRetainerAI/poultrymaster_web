"use client"

import { useEffect, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { ArrowLeft, DollarSign, Loader2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { getPeriodPnL, type GenericPeriodPnL } from "@/lib/api/generic"
import { PeriodSelect } from "@/components/ui/period-select"
import { rangeToPeriod } from "@/lib/date-ranges"

function fmt(n: number) {
  return new Intl.NumberFormat(undefined, { style: "currency", currency: "GHS", maximumFractionDigits: 2 }).format(n)
}

function defaultMonthRange() {
  const now = new Date()
  const start = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10)
  const end = now.toISOString().slice(0, 10)
  return { fromDate: start, toDate: end }
}

export default function PeriodPnLPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()

  const [range, setRange] = useState(defaultMonthRange())
  const [data, setData] = useState<GenericPeriodPnL | null>(null)
  const [loading, setLoading] = useState(false)

  const load = async () => {
    setLoading(true)
    try { setData(await getPeriodPnL(range.fromDate, range.toDate)) }
    catch (e: any) { toast({ title: "Could not load report", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setLoading(false) }
  }

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, router])

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6">
          <Link href="/generic-reports" className="inline-flex items-center text-sm text-slate-500 hover:text-slate-700 mb-2">
            <ArrowLeft className="h-3 w-3 mr-1" /> Back to reports
          </Link>
          <h1 className="text-2xl font-semibold text-slate-900 flex items-center gap-2 mb-4">
            <DollarSign className="h-6 w-6 text-emerald-600" /> Period P&amp;L
          </h1>

          <Card className="mb-4">
            <CardContent className="flex flex-wrap items-end gap-3 pt-6">
              <PeriodSelect value={rangeToPeriod(range.fromDate, range.toDate)} onChange={(_p, rg) => { if (rg) setRange({ fromDate: rg.from, toDate: rg.to }) }} />
              <div>
                <Label>From</Label>
                <Input type="date" value={range.fromDate} onChange={(e) => setRange((r) => ({ ...r, fromDate: e.target.value }))} />
              </div>
              <div>
                <Label>To</Label>
                <Input type="date" value={range.toDate} onChange={(e) => setRange((r) => ({ ...r, toDate: e.target.value }))} />
              </div>
              <Button onClick={load} disabled={loading}>{loading && <Loader2 className="h-4 w-4 animate-spin mr-2" />}Run</Button>
            </CardContent>
          </Card>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500"><Loader2 className="h-4 w-4 animate-spin" /> Loading…</div>
          ) : !data ? null : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
              <Stat title="Total income"        value={fmt(data.totalIncome)}        />
              <Stat title="Total expenses"      value={fmt(data.totalExpenses)}      />
              <Stat title="Cost of goods sold"  value={fmt(data.costOfGoodsSold)}    />
              <Stat title="Gross profit"        value={fmt(data.grossProfit)}        accent="emerald" />
              <Stat title="Net profit"          value={fmt(data.netProfit)}          accent="emerald" />
              <Stat title="Profit margin"       value={`${data.profitMarginPct.toFixed(1)}%`} />
              <Stat title="Purchases paid"      value={fmt(data.totalPurchasesPaid)} />
              <Stat title="Sales count"         value={data.salesCount.toString()}   />
            </div>
          )}
        </main>
      </div>
    </div>
  )
}

function Stat({ title, value, accent = "slate" }: { title: string; value: string; accent?: "slate" | "emerald" }) {
  return (
    <Card>
      <CardHeader className="pb-1"><CardTitle className="text-xs uppercase tracking-wide text-slate-500">{title}</CardTitle></CardHeader>
      <CardContent>
        <div className={`text-2xl font-semibold ${accent === "emerald" ? "text-emerald-700" : "text-slate-900"}`}>{value}</div>
      </CardContent>
    </Card>
  )
}
