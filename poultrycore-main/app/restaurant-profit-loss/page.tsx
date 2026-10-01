"use client"

/**
 * Restaurant Profit & Loss — standalone page.
 *
 * Laid out like Poultry's (components/poultry-reports/poultry-profit-loss-view,
 * chrome="page"): the icon header with CSV / Email / PDF, Period + From / To +
 * Clear, the five KPI tiles that print their own arithmetic (Total revenue,
 * Total expenses = Direct costs + Operating expenses + Depreciation & financing,
 * Gross, Operating and Net profit), then the statement as coloured section
 * cards. Rose where Poultry is emerald for the page's own chrome.
 *
 * Data is unchanged: KPIs from sprestaurant_report_pnl_summary, the statement
 * from sprestaurant_report_pnl_lines (323, re-emitted by 329/330), whose lines
 * add up to the same totals by construction. Sections map onto Poultry's bands:
 *   Revenue      -> Revenue
 *   CostOfSales  -> Direct costs (the cost of what was sold)
 *   Expenses     -> Operating expenses
 *   Other        -> Depreciation & financing (and cash over/short, staff-loan interest)
 */

import { Fragment, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { TrendingUp } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useFmt } from "@/lib/currency"
import { useLogout } from "@/hooks/use-logout"
import { usePermissions } from "@/hooks/use-permissions"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
import { defaultReportRange } from "@/lib/date-ranges"
import {
  PoultryReportFilter, type PoultryReportFilterValue,
} from "@/components/poultry-reports/poultry-report-filter"
import { PoultryReportExportButtons } from "@/components/poultry-reports/poultry-report-ui"
import { exportTableToPdf, emailTableAsPdf } from "@/lib/utils/pdf-export"
import { getPnlSummary, type PnlSummary } from "@/lib/api/restaurant"
import { getPnlLines, type PnlLine } from "@/lib/api/restaurant-finance"

export default function RestaurantProfitLossPage() {
  const router = useRouter()
  const logout = useLogout()
  const gh = useFmt()
  const { toast } = useToast()
  const permissions = usePermissions()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const activeFarmId = useAuthStore((s) => s.activeFarmId)
  const farmName = useAuthStore((s) => s.activeFarmName)

  const initial = useMemo(() => defaultReportRange(), [])
  const [filter, setFilter] = useState<PoultryReportFilterValue>({ fromDate: initial.from, toDate: initial.to })
  const [summary, setSummary] = useState<PnlSummary | null>(null)
  const [lines, setLines] = useState<PnlLine[]>([])
  const [loading, setLoading] = useState(true)
  const [downloading, setDownloading] = useState(false)
  const [error, setError] = useState("")

  const canView = permissions.isAdmin || permissions.featureAccess.canViewCashLedger

  const load = useCallback(async () => {
    setError("")
    try {
      const [s, l] = await Promise.all([getPnlSummary(filter.fromDate, filter.toDate), getPnlLines(filter.fromDate, filter.toDate)])
      setSummary(s); setLines(l)
    } catch (e: any) {
      setError(e?.message ?? String(e)); setSummary(null); setLines([])
    }
    setLoading(false)
  }, [filter.fromDate, filter.toDate])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    if (!activeFarmId || !filter.fromDate || !filter.toDate) return
    setLoading(true); void load()
  }, [activeFarmType, activeFarmId, router, load, filter.fromDate, filter.toDate])

  // Section totals, costs as positive figures (the lines are profit-signed).
  const bySection = useCallback((s: PnlLine["section"]) => lines.filter((l) => l.section === s && l.amount !== 0), [lines])
  const t = useMemo(() => {
    const sum = (s: PnlLine["section"]) => lines.filter((l) => l.section === s).reduce((a, l) => a + l.amount, 0)
    const revenue = summary?.revenue ?? sum("Revenue")
    const direct = -sum("CostOfSales")
    const operating = -sum("Expenses")
    const other = -sum("Other")
    const gross = revenue - direct
    const operatingProfit = gross - operating
    const net = summary?.netProfit ?? operatingProfit - other
    return { revenue, direct, operating, other, total: direct + operating + other, gross, operatingProfit, net }
  }, [lines, summary])

  // ----------------------------------------------------------------- export --
  const exportOpts = useCallback(() => {
    if (!summary) return null
    const rows: (string | number)[][] = []
    const push = (label: string, amount: number | null, kind = "") => rows.push([kind, label, amount == null ? "" : amount])
    push("REVENUE", null, "Section"); bySection("Revenue").forEach((l) => push(l.label, l.amount)); push("Total Revenue", t.revenue, "Total")
    push("DIRECT COSTS (COST OF SALES)", null, "Section"); bySection("CostOfSales").forEach((l) => push(l.label, -l.amount)); push("Total Direct Costs", t.direct, "Total")
    push("GROSS PROFIT", t.gross, "Result")
    push("OPERATING EXPENSES", null, "Section"); bySection("Expenses").forEach((l) => push(l.label, -l.amount)); push("Total Operating Expenses", t.operating, "Total")
    push("OPERATING PROFIT", t.operatingProfit, "Result")
    push("DEPRECIATION & FINANCING", null, "Section"); bySection("Other").forEach((l) => push(l.label, -l.amount)); push("Total Depreciation & Financing", t.other, "Total")
    push("NET PROFIT", t.net, "Result")
    return {
      title: "Profit & Loss",
      filename: "restaurant-profit-loss",
      farmName: farmName ?? undefined,
      fromDate: filter.fromDate,
      toDate: filter.toDate,
      summaryLines: [
        `Total Revenue: ${gh(t.revenue)}`, `Gross Profit: ${gh(t.gross)}`,
        `Operating Profit: ${gh(t.operatingProfit)}`, `Net Profit: ${gh(t.net)}`,
      ],
      columns: [{ header: "", dataKey: "kind" }, { header: "Line", dataKey: "label" }, { header: "Amount", dataKey: "amount" }],
      rows,
      orientation: "portrait" as const,
    }
  }, [summary, bySection, t, farmName, filter.fromDate, filter.toDate, gh])

  const onCsv = () => {
    const o = exportOpts(); if (!o) return
    const csv = [["Kind", "Line", "Amount"], ...o.rows].map((r) => r.map((c) => `"${String(c ?? "")}"`).join(",")).join("\n")
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8;" }))
    const a = document.createElement("a"); a.href = url; a.download = "restaurant-profit-loss.csv"; a.click()
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

  const shell = (children: React.ReactNode) => (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4">{children}</main>
      </div>
    </div>
  )

  if (!canView) return shell(
    <Card><CardContent className="py-12 text-center text-slate-600">You do not have access to Profit & Loss.</CardContent></Card>,
  )

  return shell(<>
    {/* The Money-page header, as Poultry's. */}
    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
      <div className="flex items-start gap-3 min-w-0">
        <div className="w-10 h-10 shrink-0 rounded-lg bg-rose-100 flex items-center justify-center">
          <TrendingUp className="w-5 h-5 text-rose-600" />
        </div>
        <div className="min-w-0">
          <h1 className="text-xl sm:text-2xl font-bold text-slate-900">Profit &amp; Loss</h1>
          <p className="text-sm text-slate-600">Did the restaurant make money from its operations this period?</p>
        </div>
      </div>
      <div className="shrink-0 print:hidden">
        <PoultryReportExportButtons onCsv={onCsv} onPdf={onPdf} onEmail={onEmail} busy={downloading} disabled={!summary} />
      </div>
    </div>

    <PoultryReportFilter
      value={filter}
      onChange={setFilter}
      onReset={() => setFilter({ fromDate: initial.from, toDate: initial.to })}
      show={{}}
      flocks={[]}
      customers={[]}
    />

    {error && <Alert variant="destructive"><AlertDescription>{error}</AlertDescription></Alert>}

    {loading ? <Card><CardContent className="py-12 text-center text-slate-600">Loading…</CardContent></Card>
    : summary ? (
      <div className="space-y-4">
        <div className="grid grid-cols-2 lg:grid-cols-5 gap-3">
          <Kpi label="Total revenue" value={gh(t.revenue)} tone="slate"
               term="Everything sold this period"
               tip="What completed orders sold in this period, after discounts and partial refunds, plus service charge and delivery fees — whether or not a pay-later customer has paid yet. Tax is not revenue."
               hint="Food, drinks, service charge and delivery fees" />
          <Kpi label="Total expenses" value={gh(t.total)} tone="red"
               term="Everything taken off revenue"
               tip="Every cost in this period: the cost of what was sold (stock charged when purchased or used), the cost of running the restaurant (wages, rent, utilities, gas, repairs) and depreciation plus the interest and fees on borrowing. Revenue minus this is Net profit. Owner drawings, loan principal and capital purchases are not costs."
               hint={<Formula op="+" gh={gh} terms={[
                 { label: "Direct costs", value: t.direct, tone: "direct" },
                 { label: "Operating expenses", value: t.operating, tone: "operating" },
                 { label: "Depreciation & financing", value: t.other, tone: "other" },
               ]} />} />
          <Kpi label="Gross profit" value={gh(t.gross)} tone={t.gross >= 0 ? "emerald" : "red"}
               term={t.revenue > 0 ? `${summary.grossMarginPct}% of sales` : "No sales this period"}
               tip="What the kitchen and bar made: revenue minus the cost of the food, drinks and supplies that went into it."
               hint={<Formula op="−" gh={gh} terms={[
                 { label: "Revenue", value: t.revenue, tone: "revenue" },
                 { label: "Direct costs", value: t.direct, tone: "direct" },
               ]} />} />
          <Kpi label="Operating profit" value={gh(t.operatingProfit)} tone={t.operatingProfit >= 0 ? "emerald" : "red"}
               term="Before depreciation and financing"
               tip="What the business made: gross profit minus the cost of running the restaurant. It stops short of wear on equipment and the cost of borrowing."
               hint={<Formula op="−" gh={gh} terms={[
                 { label: "Gross profit", value: t.gross, tone: "subtotal" },
                 { label: "Operating expenses", value: t.operating, tone: "operating" },
               ]} />} />
          <Kpi label={t.net < 0 ? "Net loss" : "Net profit"} value={gh(t.net)} strong
               tone={t.net > 0 ? "emerald" : t.net < 0 ? "red" : "slate"}
               term={t.revenue > 0 ? `${summary.netMarginPct}% of sales` : undefined}
               tip="What is actually left: operating profit minus depreciation and the interest and fees on borrowing (and cash over / short). Owner money, loan principal and capital purchases are not in this figure."
               hint={<Formula op="−" gh={gh} terms={[
                 { label: "Operating profit", value: t.operatingProfit, tone: "subtotal" },
                 { label: "Depreciation & financing", value: t.other, tone: "other" },
               ]} />} />
        </div>

        <div className={cn("rounded-lg border px-3 py-2 text-sm font-medium",
          t.net > 0 ? "border-emerald-200 bg-emerald-50 text-emerald-800" :
          t.net < 0 ? "border-rose-200 bg-rose-50 text-rose-800" : "border-slate-200 bg-slate-50 text-slate-800")}>
          {t.net > 0 && `The restaurant made a profit of ${gh(t.net)} this period.`}
          {t.net < 0 && `The restaurant made a loss of ${gh(Math.abs(t.net))} this period.`}
          {t.net === 0 && "The restaurant broke even this period."}
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-3">
          <SectionCard title="Revenue" tone="emerald" lines={bySection("Revenue")} totalLabel="Total revenue"
                       totalAmount={t.revenue} gh={gh} />
          <SectionCard title="Direct costs" tone="rose" lines={bySection("CostOfSales")} totalLabel="Total direct costs"
                       totalAmount={t.direct} gh={gh} negative />
          <SectionCard title="Operating expenses" tone="amber" lines={bySection("Expenses")} totalLabel="Total operating expenses"
                       totalAmount={t.operating} gh={gh} negative />
          <SectionCard title="Depreciation & financing" tone="violet" lines={bySection("Other")} totalLabel="Total depreciation & financing"
                       totalAmount={t.other} gh={gh} negative />
        </div>

        <Card><CardContent className="p-3 grid grid-cols-2 sm:grid-cols-5 gap-3 text-xs">
          {[
            ["Food cost", `${summary.foodCostPct}%`],
            ["Gross margin", `${summary.grossMarginPct}%`],
            ["Net margin", `${summary.netMarginPct}%`],
            ["Completed orders", String(summary.orderCount)],
            ["Tips collected", gh(summary.tipsTotal)],
          ].map(([k, v]) => (
            <div key={k}><div className="text-slate-500">{k}</div><div className="font-semibold tabular-nums text-slate-900">{v}</div></div>
          ))}
        </CardContent></Card>

        <div className="rounded-lg border border-slate-200 bg-white p-3 text-xs text-slate-600">
          <p className="font-medium text-slate-900 mb-1">Profit is not cash</p>
          <p>Revenue counts what completed orders sold, after discounts and partial refunds, plus service charge
            and delivery fees. Tax is left out — it is owed to the tax office. Gift-card sales are not revenue until
            the card pays for an order. Owner money and loan principal never touch profit; loan interest and fees do.
            A capital investment is not charged in the month it is bought — its cost reaches profit over time as
            depreciation, which moves no cash. For the cash actually received and spent, see{" "}
            <a href="/restaurant-cash-flow" className="underline">Cash Flow</a>; for why the two differ, see{" "}
            <a href="/restaurant-financial-activity" className="underline">Financial Activity</a>.</p>
        </div>
      </div>
    ) : null}
  </>)
}

// ----------------------------------------------------------------- pieces ---
// Poultry's Kpi / Formula / SectionCard (poultry-profit-loss-view.tsx), copied
// rather than imported because Poultry keeps them private to that file.

const FORMULA_TONES = {
  revenue: "text-emerald-700", direct: "text-rose-700", operating: "text-amber-700",
  other: "text-violet-700", subtotal: "text-slate-700",
} as const

function Formula({ op, terms, gh }: {
  op: "+" | "−"
  terms: { label: string; value: number; tone: keyof typeof FORMULA_TONES }[]
  gh: (n: number, opts?: { showSymbol?: boolean }) => string
}) {
  const money = (n: number) => { const s = gh(n, { showSymbol: false }); return n < 0 ? `(${s})` : s }
  const row = (cell: (x: (typeof terms)[number]) => string, className?: string) => (
    <div className={className}>
      {terms.map((x, i) => (
        <Fragment key={x.label}>
          {i > 0 && <span className="text-slate-400">{` ${op} `}</span>}
          <span className={FORMULA_TONES[x.tone]}>{cell(x)}</span>
        </Fragment>
      ))}
    </div>
  )
  return <>{row((x) => x.label)}{row((x) => money(x.value), "font-medium tabular-nums")}</>
}

function Kpi({ label, value, hint, term, tip, tone, strong }: {
  label: string; value: string; tip?: string; hint?: React.ReactNode; term?: string
  tone: "slate" | "emerald" | "red"; strong?: boolean
}) {
  const ring = tone === "emerald" ? "border-emerald-200" : tone === "red" ? "border-red-200" : "border-slate-200"
  const text = tone === "emerald" ? "text-emerald-700" : tone === "red" ? "text-red-700" : "text-slate-900"
  return (
    <Card className={cn(ring, strong && "ring-1 ring-slate-300")} title={tip}>
      <CardContent className="p-3">
        <div className={cn("text-[11px] uppercase tracking-wide text-slate-500", tip && "cursor-help underline decoration-dotted underline-offset-2")}>{label}</div>
        <div className={cn("text-lg font-semibold tabular-nums", text)}>{value}</div>
        {hint && <div className="text-[11px] leading-snug text-slate-500 space-y-0.5">{hint}</div>}
        {term && <div className="text-[10px] leading-snug text-slate-400 mt-0.5">{term}</div>}
      </CardContent>
    </Card>
  )
}

const SECTION_TONES = {
  emerald: { head: "bg-emerald-50 text-emerald-800", total: "bg-emerald-50/60", border: "border-emerald-200" },
  rose: { head: "bg-rose-50 text-rose-800", total: "bg-rose-50/60", border: "border-rose-200" },
  amber: { head: "bg-amber-50 text-amber-800", total: "bg-amber-50/60", border: "border-amber-200" },
  violet: { head: "bg-violet-50 text-violet-800", total: "bg-violet-50/60", border: "border-violet-200" },
} as const

/** One band of the statement. Lines are profit-signed; a cost band prints them as costs in parentheses. */
function SectionCard({ title, lines, totalLabel, totalAmount, gh, negative, tone }: {
  title: string; lines: PnlLine[]; totalLabel: string; totalAmount: number
  gh: (n: number) => string; negative?: boolean; tone: keyof typeof SECTION_TONES
}) {
  const s = SECTION_TONES[tone]
  const money = (n: number) => (negative ? `(${gh(n)})` : gh(n))
  return (
    <div className={cn("flex flex-col overflow-hidden rounded-xl border bg-white shadow-sm", s.border)}>
      <div className={cn("px-3 py-2 text-[11px] font-semibold uppercase tracking-wide", s.head)}>{title}</div>
      {lines.length === 0 ? (
        <p className="flex-1 px-4 py-4 text-sm text-slate-400">None this period</p>
      ) : (
        <ul className="flex-1 divide-y divide-slate-100">
          {lines.map((l) => (
            <li key={l.lineKey} className="flex items-center gap-1.5 px-3 py-2">
              <span className="text-sm text-slate-900">{l.label}</span>
              <span className="ml-auto shrink-0 text-sm tabular-nums text-slate-900">{money(negative ? -l.amount : l.amount)}</span>
            </li>
          ))}
        </ul>
      )}
      <div className={cn("mt-auto flex shrink-0 items-center gap-2 border-t px-3 py-2", s.border, s.total)}>
        <span className="text-sm font-semibold text-slate-900">{totalLabel}</span>
        <span className="ml-auto text-sm font-semibold tabular-nums text-slate-900">{money(totalAmount)}</span>
      </div>
    </div>
  )
}
