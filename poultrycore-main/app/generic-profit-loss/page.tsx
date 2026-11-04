"use client"

// Generic Profit & Loss — period P&L statement using the existing getPeriodPnL API.

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Loader2, TrendingUp, TrendingDown, DollarSign, ShoppingCart } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { getPeriodPnL, type GenericPeriodPnL } from "@/lib/api/generic"

function defaultRange() {
  const now = new Date()
  const y = now.getFullYear(), m = now.getMonth()
  return {
    from: new Date(y, m, 1).toISOString().slice(0, 10),
    to: now.toISOString().slice(0, 10),
  }
}

function Row({ label, value, bold, tone, indent }: { label: string; value: string; bold?: boolean; tone?: "good" | "bad" | "muted"; indent?: boolean }) {
  return (
    <div className={cn("flex items-center justify-between py-2 px-4", bold && "font-semibold", indent && "pl-8")}>
      <span className={cn("text-sm", tone === "muted" ? "text-slate-500" : "text-slate-900")}>{label}</span>
      <span className={cn("text-sm tabular-nums",
        tone === "good" ? "text-emerald-700" : tone === "bad" ? "text-red-600" : tone === "muted" ? "text-slate-500" : "text-slate-900",
        bold && "text-base"
      )}>{value}</span>
    </div>
  )
}

function Divider() { return <div className="border-t border-slate-200" /> }

export default function GenericProfitLossPage() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const logout = useLogout()
  const { toast } = useToast()
  const gh = useFmt()

  const [loading, setLoading] = useState(true)
  const [pnl, setPnl] = useState<GenericPeriodPnL | null>(null)
  const [range, setRange] = useState(defaultRange)

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType])

  async function load() {
    setLoading(true)
    try {
      const data = await getPeriodPnL(range.from, range.to)
      setPnl(data)
    } catch (e: any) {
      toast({ title: "Could not load P&L", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-4 md:p-6 space-y-4">
          <div>
            <h1 className="text-2xl font-bold text-slate-900">Profit &amp; Loss</h1>
            <p className="text-sm text-slate-500">Income, expenses, and profit for a period.</p>
          </div>

          <div className="flex flex-wrap items-end gap-3">
            <div>
              <Label className="text-xs text-slate-500">From</Label>
              <Input type="date" value={range.from} onChange={(e) => setRange((r) => ({ ...r, from: e.target.value }))} className="w-40" />
            </div>
            <div>
              <Label className="text-xs text-slate-500">To</Label>
              <Input type="date" value={range.to} onChange={(e) => setRange((r) => ({ ...r, to: e.target.value }))} className="w-40" />
            </div>
            <button type="button" onClick={load} className="rounded-md bg-emerald-600 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-700">
              Update
            </button>
          </div>

          {loading ? (
            <div className="flex items-center gap-2 text-slate-500 py-8"><Loader2 className="h-4 w-4 animate-spin" /> Loading...</div>
          ) : pnl && (
            <>
              {/* KPI cards */}
              <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
                <div className={cn("rounded-xl border bg-white p-3 shadow-sm sm:p-4", "border-slate-200")}>
                  <div className="flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-slate-500"><ShoppingCart className="w-4 h-4 text-blue-600" /> Revenue</div>
                  <div className="mt-1 text-xl font-bold tabular-nums sm:text-2xl text-slate-900">{gh(pnl.totalIncome)}</div>
                  <div className="text-xs text-slate-500">{pnl.salesCount} sale(s)</div>
                </div>
                <div className={cn("rounded-xl border bg-white p-3 shadow-sm sm:p-4", "border-slate-200")}>
                  <div className="flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-slate-500"><TrendingDown className="w-4 h-4 text-red-600" /> Expenses</div>
                  <div className="mt-1 text-xl font-bold tabular-nums sm:text-2xl text-red-600">{gh(pnl.totalExpenses)}</div>
                </div>
                <div className={cn("rounded-xl border bg-white p-3 shadow-sm sm:p-4", "border-slate-200")}>
                  <div className="flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-slate-500"><TrendingUp className="w-4 h-4 text-emerald-600" /> Gross Profit</div>
                  <div className={cn("mt-1 text-xl font-bold tabular-nums sm:text-2xl", pnl.grossProfit >= 0 ? "text-emerald-700" : "text-red-600")}>{gh(pnl.grossProfit)}</div>
                </div>
                <div className={cn("rounded-xl border bg-white p-3 shadow-sm sm:p-4", pnl.netProfit >= 0 ? "border-emerald-200" : "border-red-200")}>
                  <div className="flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-slate-500"><DollarSign className="w-4 h-4" /> Net Profit</div>
                  <div className={cn("mt-1 text-xl font-bold tabular-nums sm:text-2xl", pnl.netProfit >= 0 ? "text-emerald-700" : "text-red-600")}>{gh(pnl.netProfit)}</div>
                  <div className="text-xs text-slate-500">Margin: {pnl.profitMarginPct.toFixed(1)}%</div>
                </div>
              </div>

              {/* P&L statement */}
              <Card>
                <CardContent className="p-0">
                  <div className="py-3 px-4 bg-slate-50 border-b">
                    <h2 className="text-sm font-semibold text-slate-700">Profit &amp; Loss Statement</h2>
                    <p className="text-xs text-slate-500">{range.from} to {range.to}</p>
                  </div>
                  <Row label="Sales Revenue" value={gh(pnl.totalIncome)} tone="good" bold />
                  <Divider />
                  <Row label="Cost of Goods Sold (COGS)" value={`(${gh(pnl.costOfGoodsSold)})`} tone="bad" indent />
                  <Divider />
                  <Row label="Gross Profit" value={gh(pnl.grossProfit)} bold tone={pnl.grossProfit >= 0 ? "good" : "bad"} />
                  <Divider />
                  <Row label="Operating Expenses" value={`(${gh(pnl.totalExpenses)})`} tone="bad" indent />
                  <Row label="Purchases Paid" value={`(${gh(pnl.totalPurchasesPaid)})`} tone="muted" indent />
                  <Divider />
                  <div className="bg-slate-50">
                    <Row label="Net Profit / (Loss)" value={gh(pnl.netProfit)} bold tone={pnl.netProfit >= 0 ? "good" : "bad"} />
                    <Row label="Profit Margin" value={`${pnl.profitMarginPct.toFixed(1)}%`} tone="muted" indent />
                  </div>
                </CardContent>
              </Card>
            </>
          )}
        </main>
      </div>
    </div>
  )
}
