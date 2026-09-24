"use client"

/**
 * Restaurant Profit & Loss — standalone page.
 * KPIs from sprestaurant_report_pnl_summary; the statement from
 * sprestaurant_report_pnl_lines (migration 323), whose lines add up to the same
 * totals by construction: the summary is computed from those lines.
 * The same data also appears in /restaurant-reports → P&L.
 */

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Input } from "@/components/ui/input"
import {
  UtensilsCrossed, TrendingUp, TrendingDown, DollarSign, BarChart3,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useFmt } from "@/lib/currency"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { cn } from "@/lib/utils"
import { getPnlSummary, type PnlSummary } from "@/lib/api/restaurant"
import { getPnlLines, type PnlLine } from "@/lib/api/restaurant-finance"

function defaultMonth() {
  const now = new Date()
  const y = now.getFullYear()
  const m = String(now.getMonth() + 1).padStart(2, "0")
  const last = new Date(y, now.getMonth() + 1, 0).getDate()
  return { from: `${y}-${m}-01`, to: `${y}-${m}-${last}` }
}

export default function RestaurantProfitLossPage() {
  const router = useRouter()
  const logout = useLogout()
  const gh = useFmt()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)

  const def = defaultMonth()
  const [dateFrom, setDateFrom] = useState(def.from)
  const [dateTo, setDateTo] = useState(def.to)
  const [summary, setSummary] = useState<PnlSummary | null>(null)
  const [lines, setLines] = useState<PnlLine[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")

  const canView = permissions.isAdmin || permissions.featureAccess.canViewCashLedger

  const load = useCallback(async () => {
    setError("")
    try {
      const [s, l] = await Promise.all([
        getPnlSummary(dateFrom, dateTo),
        getPnlLines(dateFrom, dateTo),
      ])
      setSummary(s)
      setLines(l)
    } catch (e: any) {
      setError(e?.message ?? String(e))
      setSummary(null); setLines([])
    }
    setLoading(false)
  }, [dateFrom, dateTo])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    if (!activeFarmId) return
    setLoading(true); void load()
  }, [activeFarmType, activeFarmId, router, load])

  if (!canView) return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4">
          <Card><CardContent className="py-12 text-center text-slate-600">You do not have access to Profit & Loss.</CardContent></Card>
        </main>
      </div>
    </div>
  )

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4">
          <div className="mb-3">
            <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
              <UtensilsCrossed className="h-5 w-5 text-rose-600" /> Profit & Loss
            </h1>
            <p className="mt-1 text-xs text-slate-500">Did the restaurant make money this period?</p>
          </div>

          <div className="mb-3 flex flex-wrap items-center gap-2">
            <Input type="date" className="h-8 w-[9rem]" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
            <span className="text-xs text-slate-400">to</span>
            <Input type="date" className="h-8 w-[9rem]" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
            <Button size="sm" onClick={() => { setLoading(true); void load() }}>Update</Button>
          </div>

          {error && <Alert variant="destructive" className="mb-3"><AlertDescription>{error}</AlertDescription></Alert>}

          {loading ? <Card><CardContent className="py-12 text-center text-slate-600">Loading…</CardContent></Card>
          : summary ? (
            <div className="space-y-3">
              {/* KPI cards */}
              <div className="grid grid-cols-2 md:grid-cols-5 gap-2">
                <KpiCard label="Revenue" value={gh(summary.revenue)} icon={<TrendingUp className="h-4 w-4" />} tone="text-emerald-700" />
                <KpiCard label="Cost of Goods" value={gh(summary.cogs)} icon={<TrendingDown className="h-4 w-4" />} tone="text-rose-700" />
                <KpiCard label="Gross Profit" value={gh(summary.grossProfit)} icon={<DollarSign className="h-4 w-4" />}
                         tone={summary.grossProfit >= 0 ? "text-emerald-700" : "text-rose-700"} />
                <KpiCard label="Expenses" value={gh(summary.expensesTotal)} icon={<TrendingDown className="h-4 w-4" />} tone="text-rose-700" />
                <KpiCard label="Net Profit" value={`${summary.netProfit > 0 ? "+" : ""}${gh(summary.netProfit)}`}
                         icon={<BarChart3 className="h-4 w-4" />} tone={summary.netProfit >= 0 ? "text-emerald-700" : "text-rose-700"} />
              </div>

              {/* Status */}
              <div className={cn("rounded-lg border px-3 py-2 text-sm font-medium",
                summary.netProfit > 0 ? "border-emerald-200 bg-emerald-50 text-emerald-800" :
                summary.netProfit < 0 ? "border-rose-200 bg-rose-50 text-rose-800" :
                "border-slate-200 bg-slate-50 text-slate-800",
              )}>
                {summary.netProfit > 0 && `The restaurant made a profit of ${gh(summary.netProfit)} this period.`}
                {summary.netProfit < 0 && `The restaurant made a loss of ${gh(Math.abs(summary.netProfit))} this period.`}
                {summary.netProfit === 0 && "The restaurant broke even this period."}
              </div>

              {/* P&L Statement */}
              <Card>
                <CardHeader className="pb-2"><CardTitle className="text-base">Income Statement</CardTitle></CardHeader>
                <CardContent className="p-0 md:px-4 md:pb-4">
                  <Table><TableBody>
                    <SectionHead label="Revenue" tone="bg-emerald-50/50 text-emerald-800" />
                    {lineRows(lines, "Revenue", gh, true)}
                    <TotalRow label="Net revenue" value={gh(summary.revenue)} />

                    <SectionHead label="Cost of Goods Sold" tone="bg-amber-50/50 text-amber-800" />
                    {lineRows(lines, "CostOfSales", gh, true)}
                    <TableRow className="border-t border-slate-200">
                      <TableCell className="font-semibold">Gross Profit</TableCell>
                      <TableCell className={cn("text-right font-semibold tabular-nums", summary.grossProfit >= 0 ? "text-emerald-700" : "text-rose-700")}>
                        {gh(summary.grossProfit)}
                        <span className="ml-1 text-xs font-normal text-slate-500">({summary.grossMarginPct}%)</span>
                      </TableCell>
                    </TableRow>

                    <SectionHead label="Operating Expenses" tone="bg-rose-50/50 text-rose-800" />
                    {lines.some((l) => l.section === "Expenses")
                      ? lineRows(lines, "Expenses", gh, true)
                      : <TableRow><TableCell colSpan={2} className="pl-6 text-sm text-slate-400 italic">No expenses recorded</TableCell></TableRow>}

                    {lines.some((l) => l.section === "Other" && l.amount !== 0) && (
                      <>
                        <SectionHead label="Other costs" tone="bg-slate-50 text-slate-700" />
                        {lineRows(lines, "Other", gh, false)}
                      </>
                    )}
                    <TotalRow label="Total expenses" value={gh(-summary.expensesTotal)} />

                    <TableRow className="border-t-2 border-slate-300 bg-slate-50">
                      <TableCell className="font-bold text-slate-900">Net Profit</TableCell>
                      <TableCell className={cn("text-right font-bold tabular-nums", summary.netProfit >= 0 ? "text-emerald-700" : "text-rose-700")}>
                        {summary.netProfit > 0 ? "+" : ""}{gh(summary.netProfit)}
                        <span className="ml-1 text-xs font-normal text-slate-500">({summary.netMarginPct}%)</span>
                      </TableCell>
                    </TableRow>
                  </TableBody></Table>
                </CardContent>
              </Card>

              {/* Ratios */}
              <Card>
                <CardHeader className="pb-2"><CardTitle className="text-base">Key Ratios</CardTitle></CardHeader>
                <CardContent>
                  {[
                    { label: "Food Cost %", value: `${summary.foodCostPct}%`, tone: summary.foodCostPct > 35 ? "text-rose-700" : summary.foodCostPct > 30 ? "text-amber-600" : "text-emerald-700" },
                    { label: "Gross Margin", value: `${summary.grossMarginPct}%`, tone: summary.grossMarginPct >= 60 ? "text-emerald-700" : "text-amber-600" },
                    { label: "Net Margin", value: `${summary.netMarginPct}%`, tone: summary.netMarginPct >= 10 ? "text-emerald-700" : summary.netMarginPct >= 0 ? "text-amber-600" : "text-rose-700" },
                    { label: "Completed Orders", value: String(summary.orderCount), tone: "text-slate-700" },
                    { label: "Tips Collected", value: gh(summary.tipsTotal), tone: "text-slate-700" },
                  ].map(({ label, value, tone }) => (
                    <div key={label} className="flex justify-between items-center py-2 border-b last:border-0">
                      <span className="text-sm text-slate-600">{label}</span>
                      <span className={cn("text-sm font-medium tabular-nums", tone)}>{value}</span>
                    </div>
                  ))}
                </CardContent>
              </Card>

              <div className="rounded-lg border border-slate-200 bg-white p-3 text-xs text-slate-600">
                <p className="font-medium text-slate-900 mb-1">Profit is not cash</p>
                <p>Revenue counts what completed orders sold, after discounts and partial refunds,
                  plus service charge and delivery fees. Tax is left out — it is owed to the tax office.
                  Gift-card sales are not revenue until the card pays for an order. Owner money and loan
                  principal never touch profit; loan interest and fees do. For the cash actually received
                  and spent, see <a href="/restaurant-cash-flow" className="underline">Cash Flow</a>.</p>
              </div>
            </div>
          ) : null}
        </main>
      </div>
    </div>
  )
}

function SectionHead({ label, tone }: { label: string; tone: string }) {
  return (
    <TableRow className={tone.split(" ")[0]}>
      <TableCell colSpan={2} className={cn("font-semibold text-xs uppercase tracking-wide py-1.5", tone.split(" ").slice(1).join(" "))}>{label}</TableCell>
    </TableRow>
  )
}

function TotalRow({ label, value }: { label: string; value: string }) {
  return (
    <TableRow className="border-t border-slate-200">
      <TableCell className="font-semibold text-slate-700">{label}</TableCell>
      <TableCell className="text-right font-semibold tabular-nums">{value}</TableCell>
    </TableRow>
  )
}

/** Lines are signed from profit's point of view: income +, cost −. Zero lines are hidden except when `keepZero`. */
function lineRows(lines: PnlLine[], section: PnlLine["section"], gh: (n: number) => string, keepZero: boolean) {
  return lines
    .filter((l) => l.section === section && (keepZero ? l.amount !== 0 || l.sortOrder % 10 === 0 : l.amount !== 0))
    .map((l) => (
      <TableRow key={l.lineKey}>
        <TableCell className="pl-6">{l.label}</TableCell>
        <TableCell className={cn("text-right tabular-nums", l.amount < 0 ? "text-rose-600" : "text-emerald-700")}>{gh(l.amount)}</TableCell>
      </TableRow>
    ))
}

function KpiCard({ label, value, icon, tone }: { label: string; value: string; icon: React.ReactNode; tone?: string }) {
  return (
    <Card><CardContent className="p-3">
      <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500">{icon}<span className="truncate">{label}</span></div>
      <div className={cn("mt-1 text-lg font-semibold tabular-nums", tone ?? "text-slate-900")}>{value}</div>
    </CardContent></Card>
  )
}
