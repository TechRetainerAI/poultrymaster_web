"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { useIsMobile } from "@/hooks/use-mobile"
import {
  Hotel, TrendingUp, TrendingDown, DollarSign, BarChart3,
  ChevronRight, Search, X,
} from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useFmt } from "@/lib/currency"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { cn } from "@/lib/utils"
import {
  getHotelProfitLoss, getHotelPlExpenses, getHotelPlRevenue,
  type HotelProfitLossReport, type HotelProfitLossLine,
  type HotelPlExpenseRow, type HotelPlRevenueRow,
} from "@/lib/api/hotel-profit-loss"

function defaultMonth() {
  const now = new Date()
  const y = now.getFullYear()
  const m = String(now.getMonth() + 1).padStart(2, "0")
  const last = new Date(y, now.getMonth() + 1, 0).getDate()
  return { from: `${y}-${m}-01`, to: `${y}-${m}-${last}` }
}

const SECTION_COLORS: Record<string, string> = {
  Revenue: "text-emerald-700",
  OperatingExpense: "text-rose-700",
}

const SECTION_BG: Record<string, string> = {
  Revenue: "bg-emerald-50",
  OperatingExpense: "bg-rose-50",
}

export default function HotelProfitLossPage() {
  const isMobile = useIsMobile()
  const router = useRouter()
  const logout = useLogout()
  const gh = useFmt()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)

  const def = defaultMonth()
  const [dateFrom, setDateFrom] = useState(def.from)
  const [dateTo, setDateTo] = useState(def.to)
  const [report, setReport] = useState<HotelProfitLossReport | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")

  // Drilldown state
  const [drillLine, setDrillLine] = useState<HotelProfitLossLine | null>(null)
  const [drillRows, setDrillRows] = useState<any[]>([])
  const [drillLoading, setDrillLoading] = useState(false)
  const [drillSearch, setDrillSearch] = useState("")

  const canView = permissions.isAdmin || permissions.featureAccess.canViewCashLedger

  const load = useCallback(async () => {
    setError("")
    try {
      const data = await getHotelProfitLoss({ startDate: dateFrom, endDate: dateTo })
      setReport(data)
    } catch (e: any) {
      setError(e?.message ?? String(e))
      setReport(null)
    }
    setLoading(false)
  }, [dateFrom, dateTo])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    if (!activeFarmId) return
    setLoading(true)
    void load()
  }, [activeFarmType, activeFarmId, router, load])

  const openDrilldown = useCallback(async (line: HotelProfitLossLine) => {
    setDrillLine(line)
    setDrillSearch("")
    setDrillLoading(true)
    try {
      if (line.section === "Revenue") {
        const rows = await getHotelPlRevenue({
          startDate: dateFrom, endDate: dateTo, lineKey: line.lineKey,
        })
        setDrillRows(rows)
      } else {
        const rows = await getHotelPlExpenses({
          startDate: dateFrom, endDate: dateTo,
          lineKey: line.lineKey === "StaffWages" ? undefined : line.lineKey,
        })
        setDrillRows(rows)
      }
    } catch { setDrillRows([]) }
    setDrillLoading(false)
  }, [dateFrom, dateTo])

  const filteredDrill = useMemo(() => {
    if (!drillSearch) return drillRows
    const q = drillSearch.toLowerCase()
    return drillRows.filter((r: any) =>
      (r.description ?? "").toLowerCase().includes(q) ||
      (r.category ?? r.method ?? "").toLowerCase().includes(q) ||
      (r.vendor ?? "").toLowerCase().includes(q)
    )
  }, [drillRows, drillSearch])

  // Separate lines by section
  const revenueLines = useMemo(
    () => (report?.lines ?? []).filter((l) => l.section === "Revenue"),
    [report],
  )
  const expenseLines = useMemo(
    () => (report?.lines ?? []).filter((l) => l.section === "OperatingExpense"),
    [report],
  )

  if (!canView) {
    return (
      <div className="flex h-screen bg-slate-50">
        <DashboardSidebar onLogout={logout} />
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
          <DashboardHeader />
          <main className="flex-1 overflow-auto p-3 md:p-4">
            <Card><CardContent className="py-12 text-center text-slate-600">
              You do not have access to Profit & Loss.
            </CardContent></Card>
          </main>
        </div>
      </div>
    )
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-auto p-3 md:p-4">

          <div className="mb-3">
            <h1 className="text-xl font-semibold text-slate-900 flex items-center gap-2">
              <Hotel className="h-5 w-5 text-amber-600" />
              Profit & Loss
            </h1>
            <p className="mt-1 text-xs text-slate-500">Did the hotel make money this period?</p>
          </div>

          {/* Date range */}
          <div className="mb-3 flex flex-wrap items-center gap-2">
            <Input type="date" className="h-8 w-[9rem]" value={dateFrom}
                   onChange={(e) => setDateFrom(e.target.value)} />
            <span className="text-xs text-slate-400">to</span>
            <Input type="date" className="h-8 w-[9rem]" value={dateTo}
                   onChange={(e) => setDateTo(e.target.value)} />
            <Button size="sm" onClick={() => { setLoading(true); void load() }}>
              Update
            </Button>
          </div>

          {error && <Alert variant="destructive" className="mb-3"><AlertDescription>{error}</AlertDescription></Alert>}

          {loading ? (
            <Card><CardContent className="py-12 text-center text-slate-600">Loading…</CardContent></Card>
          ) : report ? (
            <div className="space-y-3">

              {/* KPI cards */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                <KpiCard label="Total Revenue" value={gh(report.totalRevenue)}
                         icon={<TrendingUp className="h-4 w-4" />} tone="text-emerald-700" />
                <KpiCard label="Total Expenses" value={gh(report.totalExpenses)}
                         icon={<TrendingDown className="h-4 w-4" />} tone="text-rose-700" />
                <KpiCard label="Net Profit" value={`${report.netProfit > 0 ? "+" : ""}${gh(report.netProfit)}`}
                         icon={<DollarSign className="h-4 w-4" />}
                         tone={report.netProfit >= 0 ? "text-emerald-700" : "text-rose-700"} />
                <KpiCard label="Net Margin"
                         value={report.netMarginPercent != null ? `${report.netMarginPercent}%` : "—"}
                         icon={<BarChart3 className="h-4 w-4" />}
                         tone={report.netProfit >= 0 ? "text-emerald-700" : "text-rose-700"} />
              </div>

              {/* Status banner */}
              <div className={cn(
                "rounded-lg border px-3 py-2 text-sm font-medium",
                report.status === "Profit" ? "border-emerald-200 bg-emerald-50 text-emerald-800" :
                report.status === "Loss" ? "border-rose-200 bg-rose-50 text-rose-800" :
                "border-slate-200 bg-slate-50 text-slate-800",
              )}>
                {report.status === "Profit" && `The hotel made a profit of ${gh(report.netProfit)} this period.`}
                {report.status === "Loss" && `The hotel made a loss of ${gh(Math.abs(report.netProfit))} this period.`}
                {report.status === "Break-even" && "The hotel broke even this period."}
              </div>

              {/* P&L Statement */}
              <Card>
                <CardHeader className="pb-2">
                  <CardTitle className="text-base">Income Statement</CardTitle>
                </CardHeader>
                <CardContent className="p-0 md:px-4 md:pb-4">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Line</TableHead>
                        <TableHead className="text-right w-[8rem]">Amount</TableHead>
                        <TableHead className="text-right w-[4rem]">#</TableHead>
                        <TableHead className="w-[2rem]" />
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {/* Revenue section */}
                      <TableRow className="bg-emerald-50/50">
                        <TableCell colSpan={4} className="font-semibold text-emerald-800 text-xs uppercase tracking-wide py-1.5">
                          Revenue
                        </TableCell>
                      </TableRow>
                      {revenueLines.map((l) => (
                        <PlRow key={l.lineKey} line={l} gh={gh} onClick={() => openDrilldown(l)} />
                      ))}
                      <SubtotalRow label="Total Revenue" value={report.totalRevenue} gh={gh} tone="text-emerald-700" />

                      {/* Expense section */}
                      <TableRow className="bg-rose-50/50">
                        <TableCell colSpan={4} className="font-semibold text-rose-800 text-xs uppercase tracking-wide py-1.5">
                          Operating Expenses
                        </TableCell>
                      </TableRow>
                      {expenseLines.map((l) => (
                        <PlRow key={l.lineKey} line={l} gh={gh} onClick={() => openDrilldown(l)} />
                      ))}
                      <SubtotalRow label="Total Expenses" value={report.totalExpenses} gh={gh} tone="text-rose-700" />

                      {/* Net profit */}
                      <TableRow className="border-t-2 border-slate-300 bg-slate-50">
                        <TableCell className="font-bold text-slate-900">Net Profit</TableCell>
                        <TableCell className={cn("text-right font-bold tabular-nums",
                          report.netProfit >= 0 ? "text-emerald-700" : "text-rose-700")}>
                          {report.netProfit > 0 ? "+" : ""}{gh(report.netProfit)}
                        </TableCell>
                        <TableCell />
                        <TableCell />
                      </TableRow>
                    </TableBody>
                  </Table>
                </CardContent>
              </Card>

              {/* Explanation */}
              <div className="rounded-lg border border-slate-200 bg-white p-3 text-xs text-slate-600">
                <p className="font-medium text-slate-900 mb-1">Profit is not cash</p>
                <p>
                  This report shows what the hotel earned and spent. It counts revenue when
                  guests pay their invoices and expenses when they are approved — not when cash
                  moves between accounts. For cash movements, see{" "}
                  <a href="/hotel-cash-flow" className="underline">Cash Flow</a>.
                </p>
              </div>
            </div>
          ) : null}
        </main>
      </div>

      {/* Drilldown dialog */}
      <Dialog open={!!drillLine} onOpenChange={(o) => { if (!o) setDrillLine(null) }}>
        <DialogContent className="max-w-3xl max-h-[80vh] overflow-hidden flex flex-col">
          <DialogHeader>
            <DialogTitle className="text-base">
              {drillLine?.lineLabel} — {gh(drillLine?.amount ?? 0)}
              <span className="ml-2 text-xs font-normal text-slate-500">
                ({drillLine?.entryCount} {drillLine?.entryCount === 1 ? "entry" : "entries"})
              </span>
            </DialogTitle>
          </DialogHeader>

          <div className="relative mb-2">
            <Search className="absolute left-2.5 top-2 h-4 w-4 text-slate-400" />
            <Input
              className="h-8 pl-8 pr-8 text-sm"
              placeholder="Search…"
              value={drillSearch}
              onChange={(e) => setDrillSearch(e.target.value)}
            />
            {drillSearch && (
              <button className="absolute right-2 top-2" onClick={() => setDrillSearch("")}>
                <X className="h-4 w-4 text-slate-400" />
              </button>
            )}
          </div>

          <div className="flex-1 overflow-auto">
            {drillLoading ? (
              <p className="py-8 text-center text-sm text-slate-500">Loading…</p>
            ) : filteredDrill.length === 0 ? (
              <p className="py-8 text-center text-sm text-slate-500">No entries found.</p>
            ) : drillLine?.section === "Revenue" ? (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Date</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead>Description</TableHead>
                    <TableHead>Method</TableHead>
                    <TableHead className="text-right">Amount</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredDrill.map((r: HotelPlRevenueRow, i: number) => (
                    <TableRow key={`${r.sourceType}-${r.sourceId}-${i}`}>
                      <TableCell className="whitespace-nowrap">{r.entryDate?.split("T")[0]}</TableCell>
                      <TableCell>{r.sourceType === "GuestPayment" ? "Guest payment" : "Restaurant order"}</TableCell>
                      <TableCell className="max-w-xs break-words">{r.description ?? "—"}</TableCell>
                      <TableCell>{r.method ?? "—"}</TableCell>
                      <TableCell className="text-right tabular-nums text-emerald-700">{gh(r.amount)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Date</TableHead>
                    <TableHead>Category</TableHead>
                    <TableHead>Description</TableHead>
                    <TableHead>Vendor</TableHead>
                    <TableHead className="text-right">Amount</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredDrill.map((r: HotelPlExpenseRow, i: number) => (
                    <TableRow key={`${r.hotelExpenseId}-${i}`}>
                      <TableCell className="whitespace-nowrap">{r.expenseDate?.split("T")[0]}</TableCell>
                      <TableCell>{r.category ?? "—"}</TableCell>
                      <TableCell className="max-w-xs break-words">{r.description ?? "—"}</TableCell>
                      <TableCell>{r.vendor ?? "—"}</TableCell>
                      <TableCell className="text-right tabular-nums text-rose-600">{gh(r.amount)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

function PlRow({ line, gh, onClick }: {
  line: HotelProfitLossLine; gh: (n: number) => string; onClick: () => void
}) {
  return (
    <TableRow className="cursor-pointer hover:bg-slate-50" onClick={onClick}>
      <TableCell className="pl-6">{line.lineLabel}</TableCell>
      <TableCell className={cn("text-right tabular-nums", SECTION_COLORS[line.section])}>
        {gh(Math.abs(line.amount))}
      </TableCell>
      <TableCell className="text-right text-xs text-slate-400">{line.entryCount}</TableCell>
      <TableCell>
        <ChevronRight className="h-3.5 w-3.5 text-slate-400" />
      </TableCell>
    </TableRow>
  )
}

function SubtotalRow({ label, value, gh, tone }: {
  label: string; value: number; gh: (n: number) => string; tone: string
}) {
  return (
    <TableRow className="border-t border-slate-200">
      <TableCell className="font-semibold text-slate-700">{label}</TableCell>
      <TableCell className={cn("text-right font-semibold tabular-nums", tone)}>
        {gh(value)}
      </TableCell>
      <TableCell />
      <TableCell />
    </TableRow>
  )
}

function KpiCard({ label, value, icon, tone }: {
  label: string; value: string; icon: React.ReactNode; tone?: string
}) {
  return (
    <Card>
      <CardContent className="p-3">
        <div className="flex items-center gap-1 text-[11px] uppercase tracking-wide text-slate-500">
          {icon}
          <span className="truncate">{label}</span>
        </div>
        <div className={cn("mt-1 text-lg font-semibold tabular-nums", tone ?? "text-slate-900")}>
          {value}
        </div>
      </CardContent>
    </Card>
  )
}
