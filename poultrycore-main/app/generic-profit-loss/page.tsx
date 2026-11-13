"use client"

// Generic Profit & Loss — deep copy of poultry-profit-loss page structure.
// Uses the same page header, KPI tiles, period dropdown, statement card, and
// export buttons as the poultry side, adapted for the generic P&L API data.

import { useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Button } from "@/components/ui/button"
import { Loader2, TrendingUp, FileSpreadsheet, Printer, Mail } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useLogout } from "@/hooks/use-logout"
import { useToast } from "@/hooks/use-toast"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { getPeriodPnL, type GenericPeriodPnL } from "@/lib/api/generic"
import { PeriodSelect } from "@/components/ui/period-select"
import { defaultReportRange, rangeToPeriod, type PeriodKey } from "@/lib/date-ranges"
import { exportTableToPdf, emailTableAsPdf } from "@/lib/utils/pdf-export"

// KPI tile matching the poultry P&L — same structure: label, value, tone,
// optional hint/term line, with coloured border for profit/loss.
function Kpi({ label, value, hint, term, tone, strong }: {
  label: string; value: string
  hint?: React.ReactNode
  term?: string
  tone: "slate" | "emerald" | "red"; strong?: boolean
}) {
  const ring = tone === "emerald" ? "border-emerald-200" : tone === "red" ? "border-red-200" : "border-slate-200"
  const text = tone === "emerald" ? "text-emerald-700" : tone === "red" ? "text-red-700" : "text-slate-900"
  return (
    <Card className={cn(ring, strong && "ring-1 ring-slate-300")}>
      <CardContent className="p-3">
        <div className="text-[11px] uppercase tracking-wide text-slate-500">{label}</div>
        <div className={cn("text-lg font-semibold tabular-nums", text)}>{value}</div>
        {hint && <div className="text-[11px] leading-snug text-slate-500 space-y-0.5">{hint}</div>}
        {term && <div className="text-[10px] leading-snug text-slate-400 mt-0.5">{term}</div>}
      </CardContent>
    </Card>
  )
}

// Statement row — same as poultry statement structure
function Row({ label, value, bold, tone, indent }: { label: string; value: string; bold?: boolean; tone?: "good" | "bad" | "muted"; indent?: boolean }) {
  return (
    <div className={cn("flex items-center justify-between py-2.5 px-4", bold && "font-semibold", indent && "pl-8")}>
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
  const farmName = useAuthStore((s) => s.activeFarmName)
  const logout = useLogout()
  const { toast } = useToast()
  const gh = useFmt()

  const initial = useMemo(() => defaultReportRange(), [])
  const [range, setRange] = useState({ from: initial.from, to: initial.to })
  const [period, setPeriod] = useState<PeriodKey>(() => rangeToPeriod(initial.from, initial.to))

  const [loading, setLoading] = useState(true)
  const [pnl, setPnl] = useState<GenericPeriodPnL | null>(null)
  const [downloading, setDownloading] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      setPnl(await getPeriodPnL(range.from, range.to))
    } catch (e: any) {
      toast({ title: "Could not load P&L", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setLoading(false) }
  }, [range.from, range.to, toast])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") { router.replace("/dashboard"); return }
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeFarmType, load])

  // Total expenses for KPI
  const totalExpenses = pnl ? pnl.totalExpenses + pnl.costOfGoodsSold + pnl.totalPurchasesPaid : 0

  // Export
  const exportOpts = useCallback(() => {
    if (!pnl) return null
    const rows: (string | number)[][] = []
    rows.push(["", "Sales Revenue", pnl.totalIncome])
    rows.push(["", "Cost of Goods Sold (COGS)", pnl.costOfGoodsSold])
    rows.push(["Total", "Gross Profit", pnl.grossProfit])
    rows.push(["", "Operating Expenses", pnl.totalExpenses])
    rows.push(["", "Purchases Paid", pnl.totalPurchasesPaid])
    rows.push(["Result", "Net Profit / (Loss)", pnl.netProfit])
    rows.push(["", "Profit Margin", `${pnl.profitMarginPct.toFixed(1)}%`])
    return {
      title: "Profit & Loss",
      filename: "generic-profit-loss",
      farmName: farmName ?? undefined,
      fromDate: range.from,
      toDate: range.to,
      summaryLines: [
        `Total Revenue: ${gh(pnl.totalIncome)}`,
        `Gross Profit: ${gh(pnl.grossProfit)}`,
        `Net Profit: ${gh(pnl.netProfit)}`,
      ],
      columns: [{ header: "", dataKey: "kind" }, { header: "Line", dataKey: "label" }, { header: "Amount", dataKey: "amount" }],
      rows,
      orientation: "portrait" as const,
    }
  }, [pnl, farmName, range.from, range.to, gh])

  const onCsv = () => {
    const o = exportOpts(); if (!o) return
    const csv = [["Kind", "Line", "Amount"], ...o.rows].map((r) => r.map((c) => `"${String(c ?? "")}"`).join(",")).join("\n")
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8;" }))
    const a = document.createElement("a")
    a.href = url; a.download = "generic-profit-loss.csv"; a.click()
    URL.revokeObjectURL(url)
  }

  const onPdf = async () => {
    const o = exportOpts(); if (!o) return
    setDownloading(true)
    try { await exportTableToPdf(o as any) }
    catch (e: any) { toast({ title: "PDF failed", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setDownloading(false) }
  }

  const onEmail = async () => {
    const o = exportOpts(); if (!o) return
    setDownloading(true)
    try {
      const res = await emailTableAsPdf(o as any)
      toast({ title: res.success ? "Report sent" : "Could not send", description: res.message ?? res.recipient })
    } catch (e: any) { toast({ title: "Email failed", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setDownloading(false) }
  }

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4">

          {/* Page header — matching poultry P&L "page" chrome: icon, title, subtitle, export buttons */}
          <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div className="flex items-start gap-3 min-w-0">
              <div className="w-10 h-10 shrink-0 rounded-lg bg-emerald-100 flex items-center justify-center">
                <TrendingUp className="w-5 h-5 text-emerald-700" />
              </div>
              <div className="min-w-0">
                <h1 className="text-xl sm:text-2xl font-bold text-slate-900">Profit &amp; Loss</h1>
                <p className="text-sm text-slate-600">
                  Did the business make money from its operations this period?
                </p>
              </div>
            </div>
            <div className="shrink-0 print:hidden">
              <div className="flex items-center gap-2 flex-wrap">
                <Button size="sm" variant="outline" onClick={onCsv} disabled={!pnl} className="gap-1" title="Download CSV">
                  <FileSpreadsheet className="h-4 w-4" /> CSV
                </Button>
                <Button size="sm" variant="outline" onClick={onEmail} disabled={!pnl} className="gap-1" title="Email this report as a PDF">
                  <Mail className="h-4 w-4" /> Email
                </Button>
                <Button size="sm" onClick={onPdf} disabled={!pnl || downloading} className="gap-1" title="Download PDF">
                  {downloading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Printer className="h-4 w-4" />} PDF
                </Button>
              </div>
            </div>
          </div>

          {/* Period filter — matching poultry PoultryReportFilter: Period dropdown + From/To dates */}
          <div className="flex flex-wrap items-end gap-3">
            <PeriodSelect
              value={period}
              onChange={(p, r) => {
                setPeriod(p)
                if (r) setRange({ from: r.from, to: r.to })
              }}
            />
            <div>
              <Label className="text-xs text-slate-500">From</Label>
              <Input type="date" value={range.from} className="w-40" onChange={(e) => {
                setRange((r) => ({ ...r, from: e.target.value }))
                setPeriod("custom")
              }} />
            </div>
            <div>
              <Label className="text-xs text-slate-500">To</Label>
              <Input type="date" value={range.to} className="w-40" onChange={(e) => {
                setRange((r) => ({ ...r, to: e.target.value }))
                setPeriod("custom")
              }} />
            </div>
            <Button onClick={load} size="sm" className="h-10">Update</Button>
          </div>

          {loading && (
            <div className="flex items-center gap-2 text-sm text-slate-500 py-10 justify-center">
              <Loader2 className="w-4 h-4 animate-spin" /> Loading…
            </div>
          )}

          {pnl && !loading && (
            <>
              {/* KPI tiles — matching poultry: 5 across on xl, 3 on lg, 2 on mobile */}
              <div className="grid gap-3 grid-cols-2 lg:grid-cols-3 xl:grid-cols-5">
                <Kpi label="Total revenue" value={gh(pnl.totalIncome)} tone="slate"
                     term="Everything sold this period"
                     hint={`${pnl.salesCount} sale(s)`} />
                <Kpi label="Total expenses"
                     value={gh(totalExpenses)}
                     term="Everything taken off revenue"
                     hint={<>
                       <span className="text-rose-700">COGS {gh(pnl.costOfGoodsSold)}</span>
                       {" + "}
                       <span className="text-amber-700">Opex {gh(pnl.totalExpenses)}</span>
                       {" + "}
                       <span className="text-violet-700">Purchases {gh(pnl.totalPurchasesPaid)}</span>
                     </>}
                     tone="red" />
                <Kpi label="Gross profit"
                     value={gh(pnl.grossProfit)}
                     term={pnl.totalIncome > 0 ? `${((pnl.grossProfit / pnl.totalIncome) * 100).toFixed(1)}% of sales` : "No sales this period"}
                     hint={<>
                       <span className="text-emerald-700">Revenue</span>
                       <span className="text-slate-400"> − </span>
                       <span className="text-rose-700">COGS</span>
                     </>}
                     tone={pnl.grossProfit >= 0 ? "emerald" : "red"} />
                <Kpi label={pnl.netProfit < 0 ? "Net loss" : "Net profit"}
                     value={gh(pnl.netProfit)}
                     term={`${pnl.profitMarginPct.toFixed(1)}% margin`}
                     hint={<>
                       <span className="text-emerald-700">Revenue</span>
                       <span className="text-slate-400"> − </span>
                       <span className="text-amber-700">All costs</span>
                     </>}
                     tone={pnl.netProfit > 0 ? "emerald" : pnl.netProfit < 0 ? "red" : "slate"} strong />
                <Kpi label="Profit margin" value={`${pnl.profitMarginPct.toFixed(1)}%`} tone="slate"
                     term="Net profit ÷ revenue"
                     hint={pnl.profitMarginPct >= 0 ? "Healthy" : "Loss-making"} />
              </div>

              {/* P&L statement card — matching poultry section-card structure */}
              <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
                {/* Revenue */}
                <div className="flex flex-col overflow-hidden rounded-xl border bg-white shadow-sm border-emerald-200">
                  <div className="px-3 py-2 text-[11px] font-semibold uppercase tracking-wide bg-emerald-50 text-emerald-800">
                    Revenue
                  </div>
                  <div className="flex-1 px-3 py-3">
                    <div className="flex items-center justify-between text-sm">
                      <span className="text-slate-900">Sales Revenue</span>
                      <span className="tabular-nums text-slate-900">{gh(pnl.totalIncome)}</span>
                    </div>
                  </div>
                  <div className="mt-auto flex items-center gap-2 border-t border-emerald-200 px-3 py-2 bg-emerald-50/60">
                    <span className="text-sm font-semibold text-slate-900">Total Revenue</span>
                    <span className="ml-auto text-sm font-semibold tabular-nums text-slate-900">{gh(pnl.totalIncome)}</span>
                  </div>
                </div>

                {/* Cost of Goods Sold */}
                <div className="flex flex-col overflow-hidden rounded-xl border bg-white shadow-sm border-rose-200">
                  <div className="px-3 py-2 text-[11px] font-semibold uppercase tracking-wide bg-rose-50 text-rose-800">
                    Cost of Goods Sold
                  </div>
                  <div className="flex-1 px-3 py-3">
                    <div className="flex items-center justify-between text-sm">
                      <span className="text-slate-900">COGS</span>
                      <span className="tabular-nums text-slate-900">({gh(pnl.costOfGoodsSold)})</span>
                    </div>
                  </div>
                  <div className="mt-auto flex items-center gap-2 border-t border-rose-200 px-3 py-2 bg-rose-50/60">
                    <span className="text-sm font-semibold text-slate-900">Total COGS</span>
                    <span className="ml-auto text-sm font-semibold tabular-nums text-slate-900">({gh(pnl.costOfGoodsSold)})</span>
                  </div>
                </div>

                {/* Operating Expenses */}
                <div className="flex flex-col overflow-hidden rounded-xl border bg-white shadow-sm border-amber-200">
                  <div className="px-3 py-2 text-[11px] font-semibold uppercase tracking-wide bg-amber-50 text-amber-800">
                    Operating Expenses
                  </div>
                  <div className="flex-1 px-3 py-3 space-y-1">
                    <div className="flex items-center justify-between text-sm">
                      <span className="text-slate-900">Expenses</span>
                      <span className="tabular-nums text-slate-900">({gh(pnl.totalExpenses)})</span>
                    </div>
                    <div className="flex items-center justify-between text-sm">
                      <span className="text-slate-900">Purchases Paid</span>
                      <span className="tabular-nums text-slate-900">({gh(pnl.totalPurchasesPaid)})</span>
                    </div>
                  </div>
                  <div className="mt-auto flex items-center gap-2 border-t border-amber-200 px-3 py-2 bg-amber-50/60">
                    <span className="text-sm font-semibold text-slate-900">Total Operating</span>
                    <span className="ml-auto text-sm font-semibold tabular-nums text-slate-900">({gh(pnl.totalExpenses + pnl.totalPurchasesPaid)})</span>
                  </div>
                </div>

                {/* Net Profit */}
                <div className={cn("flex flex-col overflow-hidden rounded-xl border bg-white shadow-sm",
                  pnl.netProfit >= 0 ? "border-emerald-200" : "border-red-200")}>
                  <div className={cn("px-3 py-2 text-[11px] font-semibold uppercase tracking-wide",
                    pnl.netProfit >= 0 ? "bg-emerald-50 text-emerald-800" : "bg-red-50 text-red-800")}>
                    {pnl.netProfit < 0 ? "Net Loss" : "Net Profit"}
                  </div>
                  <div className="flex-1 px-3 py-3 space-y-1">
                    <div className="flex items-center justify-between text-sm">
                      <span className="text-slate-500">Revenue</span>
                      <span className="tabular-nums text-emerald-700">{gh(pnl.totalIncome)}</span>
                    </div>
                    <div className="flex items-center justify-between text-sm">
                      <span className="text-slate-500">Less: All costs</span>
                      <span className="tabular-nums text-red-600">({gh(totalExpenses)})</span>
                    </div>
                  </div>
                  <div className={cn("mt-auto flex items-center gap-2 border-t px-3 py-2",
                    pnl.netProfit >= 0 ? "border-emerald-200 bg-emerald-50/60" : "border-red-200 bg-red-50/60")}>
                    <span className="text-sm font-semibold text-slate-900">{pnl.netProfit < 0 ? "Net Loss" : "Net Profit"}</span>
                    <span className={cn("ml-auto text-sm font-semibold tabular-nums",
                      pnl.netProfit >= 0 ? "text-emerald-700" : "text-red-600")}>{gh(pnl.netProfit)}</span>
                  </div>
                </div>
              </div>

              {/* Full statement card — same as poultry's detailed breakdown */}
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

              {/* Disclaimer / method note, matching poultry */}
              <div className="text-[11px] text-slate-500 space-y-1">
                <p>
                  This statement uses the accrual method: revenue is recognised when a sale is recorded
                  and expenses when they are approved, regardless of when cash actually moved.
                </p>
              </div>
            </>
          )}
        </main>
      </div>
    </div>
  )
}
