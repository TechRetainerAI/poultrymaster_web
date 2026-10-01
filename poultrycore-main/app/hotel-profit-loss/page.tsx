"use client"

/**
 * Hotel Profit & Loss — standalone page.
 *
 * Laid out like Poultry's (components/poultry-reports/poultry-profit-loss-view,
 * chrome="page"), through the Restaurant's copy (app/restaurant-profit-loss):
 * the icon header with CSV / Email / PDF, Period + From / To + Clear, the five
 * KPI tiles that print their own arithmetic, then the statement as coloured
 * section cards. Violet where Poultry is emerald for the page's own chrome.
 *
 * Data is unchanged: one call, getHotelProfitLoss (sphotelreport_plsummary +
 * sphotelreport_pllines, as of 334). Its sections map onto Poultry's bands:
 *   Revenue                                  -> Revenue
 *   OperatingExpense, supply lines           -> Direct costs (supplies bought / used)
 *   OperatingExpense, everything else        -> Operating expenses
 *   OtherCost                                -> Depreciation & financing
 * Tap a line to see the entries behind it (the existing drilldowns).
 */

import { Fragment, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { TrendingUp, ChevronRight, Search, X } from "lucide-react"
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
import {
  getHotelProfitLoss, getHotelPlExpenses, getHotelPlRevenue,
  type HotelProfitLossReport, type HotelProfitLossLine,
  type HotelPlExpenseRow, type HotelPlRevenueRow,
} from "@/lib/api/hotel-profit-loss"

/** The supply lines (migration 334): the cost of what guests used. */
const DIRECT_COST_KEYS = new Set(["SuppliesPurchased", "SuppliesUsed"])

export default function HotelProfitLossPage() {
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
  const [report, setReport] = useState<HotelProfitLossReport | null>(null)
  const [loading, setLoading] = useState(true)
  const [downloading, setDownloading] = useState(false)
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
      setReport(await getHotelProfitLoss({ startDate: filter.fromDate, endDate: filter.toDate }))
    } catch (e: any) {
      setError(e?.message ?? String(e)); setReport(null)
    }
    setLoading(false)
  }, [filter.fromDate, filter.toDate])

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Hotel") { router.replace("/dashboard"); return }
    if (!activeFarmId || !filter.fromDate || !filter.toDate) return
    setLoading(true); void load()
  }, [activeFarmType, activeFarmId, router, load, filter.fromDate, filter.toDate])

  const openDrilldown = useCallback(async (line: HotelProfitLossLine) => {
    setDrillLine(line); setDrillSearch(""); setDrillLoading(true)
    try {
      if (line.section === "Revenue") {
        setDrillRows(await getHotelPlRevenue({ startDate: filter.fromDate, endDate: filter.toDate, lineKey: line.lineKey }))
      } else {
        setDrillRows(await getHotelPlExpenses({
          startDate: filter.fromDate, endDate: filter.toDate,
          lineKey: line.lineKey === "StaffWages" ? undefined : line.lineKey,
        }))
      }
    } catch { setDrillRows([]) }
    setDrillLoading(false)
  }, [filter.fromDate, filter.toDate])

  const filteredDrill = useMemo(() => {
    if (!drillSearch) return drillRows
    const q = drillSearch.toLowerCase()
    return drillRows.filter((r: any) =>
      (r.description ?? "").toLowerCase().includes(q) ||
      (r.category ?? r.method ?? "").toLowerCase().includes(q) ||
      (r.vendor ?? "").toLowerCase().includes(q))
  }, [drillRows, drillSearch])

  // The four bands; cost lines come back as positive amounts.
  const bands = useMemo(() => {
    const lines = (report?.lines ?? []).filter((l) => l.amount !== 0)
    return {
      revenue: lines.filter((l) => l.section === "Revenue"),
      direct: lines.filter((l) => l.section === "OperatingExpense" && DIRECT_COST_KEYS.has(l.lineKey)),
      operating: lines.filter((l) => l.section === "OperatingExpense" && !DIRECT_COST_KEYS.has(l.lineKey)),
      other: lines.filter((l) => l.section === "OtherCost"),
    }
  }, [report])
  const t = useMemo(() => {
    const sum = (ls: HotelProfitLossLine[]) => ls.reduce((a, l) => a + l.amount, 0)
    const revenue = report?.totalRevenue ?? sum(bands.revenue)
    const direct = sum(bands.direct)
    const operating = (report?.totalExpenses ?? direct + sum(bands.operating)) - direct
    const other = report?.totalOtherCosts ?? sum(bands.other)
    const gross = revenue - direct
    const operatingProfit = gross - operating
    const net = report?.netProfit ?? operatingProfit - other
    return { revenue, direct, operating, other, total: direct + operating + other, gross, operatingProfit, net }
  }, [report, bands])
  const pct = (n: number) => (t.revenue > 0 ? `${Math.round((n / t.revenue) * 1000) / 10}% of revenue` : undefined)

  // ----------------------------------------------------------------- export --
  const exportOpts = useCallback(() => {
    if (!report) return null
    const rows: (string | number)[][] = []
    const push = (label: string, amount: number | null, kind = "") => rows.push([kind, label, amount == null ? "" : amount])
    push("REVENUE", null, "Section"); bands.revenue.forEach((l) => push(l.lineLabel, l.amount)); push("Total Revenue", t.revenue, "Total")
    push("DIRECT COSTS (SUPPLIES)", null, "Section"); bands.direct.forEach((l) => push(l.lineLabel, l.amount)); push("Total Direct Costs", t.direct, "Total")
    push("GROSS PROFIT", t.gross, "Result")
    push("OPERATING EXPENSES", null, "Section"); bands.operating.forEach((l) => push(l.lineLabel, l.amount)); push("Total Operating Expenses", t.operating, "Total")
    push("OPERATING PROFIT", t.operatingProfit, "Result")
    push("DEPRECIATION & FINANCING", null, "Section"); bands.other.forEach((l) => push(l.lineLabel, l.amount)); push("Total Depreciation & Financing", t.other, "Total")
    push("NET PROFIT", t.net, "Result")
    return {
      title: "Profit & Loss",
      filename: "hotel-profit-loss",
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
  }, [report, bands, t, farmName, filter.fromDate, filter.toDate, gh])

  const onCsv = () => {
    const o = exportOpts(); if (!o) return
    const csv = [["Kind", "Line", "Amount"], ...o.rows].map((r) => r.map((c) => `"${String(c ?? "")}"`).join(",")).join("\n")
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8;" }))
    const a = document.createElement("a"); a.href = url; a.download = "hotel-profit-loss.csv"; a.click()
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
        <div className="w-10 h-10 shrink-0 rounded-lg bg-violet-100 flex items-center justify-center">
          <TrendingUp className="w-5 h-5 text-violet-600" />
        </div>
        <div className="min-w-0">
          <h1 className="text-xl sm:text-2xl font-bold text-slate-900">Profit &amp; Loss</h1>
          <p className="text-sm text-slate-600">Did the hotel make money from its operations this period?</p>
        </div>
      </div>
      <div className="shrink-0 print:hidden">
        <PoultryReportExportButtons onCsv={onCsv} onPdf={onPdf} onEmail={onEmail} busy={downloading} disabled={!report} />
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
    : report ? (
      <div className="space-y-4">
        <div className="grid grid-cols-2 lg:grid-cols-5 gap-3">
          <Kpi label="Total revenue" value={gh(t.revenue)} tone="slate"
               term="Everything earned this period"
               tip="Room revenue (guest payments received), walk-in restaurant sales and interest on staff loans. Refundable guest deposits are money held for the guest, not revenue."
               hint="Rooms, restaurant and other income" />
          <Kpi label="Total expenses" value={gh(t.total)} tone="red"
               term="Everything taken off revenue"
               tip="Every cost in this period: supplies guests used, the cost of running the hotel (wages, utilities, laundry, repairs) and depreciation plus the interest and fees on borrowing. Revenue minus this is Net profit. Owner drawings, loan principal and capital purchases are not costs."
               hint={<Formula op="+" gh={gh} terms={[
                 { label: "Direct costs", value: t.direct, tone: "direct" },
                 { label: "Operating expenses", value: t.operating, tone: "operating" },
                 { label: "Depreciation & financing", value: t.other, tone: "other" },
               ]} />} />
          <Kpi label="Gross profit" value={gh(t.gross)} tone={t.gross >= 0 ? "emerald" : "red"}
               term={pct(t.gross) ?? "No revenue this period"}
               tip="Revenue minus the supplies that went into serving guests (amenities, linen, cleaning and kitchen stock)."
               hint={<Formula op="−" gh={gh} terms={[
                 { label: "Revenue", value: t.revenue, tone: "revenue" },
                 { label: "Direct costs", value: t.direct, tone: "direct" },
               ]} />} />
          <Kpi label="Operating profit" value={gh(t.operatingProfit)} tone={t.operatingProfit >= 0 ? "emerald" : "red"}
               term="Before depreciation and financing"
               tip="What the business made: gross profit minus the cost of running the hotel. It stops short of wear on assets and the cost of borrowing."
               hint={<Formula op="−" gh={gh} terms={[
                 { label: "Gross profit", value: t.gross, tone: "subtotal" },
                 { label: "Operating expenses", value: t.operating, tone: "operating" },
               ]} />} />
          <Kpi label={t.net < 0 ? "Net loss" : "Net profit"} value={gh(t.net)} strong
               tone={t.net > 0 ? "emerald" : t.net < 0 ? "red" : "slate"}
               term={pct(t.net)}
               tip="What is actually left: operating profit minus depreciation and the interest and fees on borrowing. Owner money, loan principal and capital purchases are not in this figure."
               hint={<Formula op="−" gh={gh} terms={[
                 { label: "Operating profit", value: t.operatingProfit, tone: "subtotal" },
                 { label: "Depreciation & financing", value: t.other, tone: "other" },
               ]} />} />
        </div>

        <div className={cn("rounded-lg border px-3 py-2 text-sm font-medium",
          t.net > 0 ? "border-emerald-200 bg-emerald-50 text-emerald-800" :
          t.net < 0 ? "border-rose-200 bg-rose-50 text-rose-800" : "border-slate-200 bg-slate-50 text-slate-800")}>
          {t.net > 0 && `The hotel made a profit of ${gh(t.net)} this period.`}
          {t.net < 0 && `The hotel made a loss of ${gh(Math.abs(t.net))} this period.`}
          {t.net === 0 && "The hotel broke even this period."}
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-3">
          <SectionCard title="Revenue" tone="emerald" lines={bands.revenue} totalLabel="Total revenue"
                       totalAmount={t.revenue} gh={gh} onOpen={openDrilldown} />
          <SectionCard title="Direct costs" tone="rose" lines={bands.direct} totalLabel="Total direct costs"
                       totalAmount={t.direct} gh={gh} negative onOpen={openDrilldown} />
          <SectionCard title="Operating expenses" tone="amber" lines={bands.operating} totalLabel="Total operating expenses"
                       totalAmount={t.operating} gh={gh} negative onOpen={openDrilldown} />
          <SectionCard title="Depreciation & financing" tone="violet" lines={bands.other} totalLabel="Total depreciation & financing"
                       totalAmount={t.other} gh={gh} negative onOpen={openDrilldown} />
        </div>

        <Card><CardContent className="p-3 grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs">
          {[
            ["Room revenue", gh(report.roomRevenue)],
            ["Restaurant / F&B", gh(report.restaurantRevenue)],
            ["Net margin", report.netMarginPercent != null ? `${report.netMarginPercent}%` : "—"],
            ["Deposits held (not revenue)", gh(report.depositsNet)],
          ].map(([k, v]) => (
            <div key={k}><div className="text-slate-500">{k}</div><div className="font-semibold tabular-nums text-slate-900">{v}</div></div>
          ))}
        </CardContent></Card>

        <div className="rounded-lg border border-slate-200 bg-white p-3 text-xs text-slate-600">
          <p className="font-medium text-slate-900 mb-1">Profit is not cash</p>
          <p>Room revenue is counted when guests pay; restaurant sales when they are paid at the till. Expenses count when
            they are approved, whether or not the supplier has been paid yet. Supplies expensed when consumed reach profit as
            they are used (Internal Use). Owner money and loan principal never touch profit; loan interest and fees do. A
            capital investment is not charged in the month it is bought — its cost reaches profit over time as depreciation,
            which moves no cash. For the cash actually received and spent, see{" "}
            <a href="/hotel-cash-flow" className="underline">Cash Flow</a>; for why the two differ, see{" "}
            <a href="/hotel-financial-activity" className="underline">Financial Activity</a>.</p>
        </div>
      </div>
    ) : null}

    {/* Drilldown dialog: the entries behind one line. */}
    <Dialog open={!!drillLine} onOpenChange={(o) => { if (!o) setDrillLine(null) }}>
      <DialogContent className="sm:max-w-3xl max-h-[80vh] overflow-hidden flex flex-col">
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
          <Input className="h-8 pl-8 pr-8 text-sm" placeholder="Search…" value={drillSearch} onChange={(e) => setDrillSearch(e.target.value)} />
          {drillSearch && (
            <button className="absolute right-2 top-2" onClick={() => setDrillSearch("")}><X className="h-4 w-4 text-slate-400" /></button>
          )}
        </div>
        <div className="flex-1 overflow-auto">
          {drillLoading ? (
            <p className="py-8 text-center text-sm text-slate-500">Loading…</p>
          ) : filteredDrill.length === 0 ? (
            <p className="py-8 text-center text-sm text-slate-500">No entries found.</p>
          ) : drillLine?.section === "Revenue" ? (
            <Table>
              <TableHeader><TableRow>
                <TableHead>Date</TableHead><TableHead>Type</TableHead><TableHead>Description</TableHead>
                <TableHead>Method</TableHead><TableHead className="text-right">Amount</TableHead>
              </TableRow></TableHeader>
              <TableBody>
                {filteredDrill.map((r: HotelPlRevenueRow, i: number) => (
                  <TableRow key={`${r.sourceType}-${r.sourceId}-${i}`}>
                    <TableCell className="whitespace-nowrap">{r.entryDate?.split("T")[0]}</TableCell>
                    <TableCell>{r.sourceType === "GuestPayment" ? "Guest payment" : r.sourceType === "RestaurantOrder" ? "Restaurant order" : "Staff loan interest"}</TableCell>
                    <TableCell className="max-w-xs break-words">{r.description ?? "—"}</TableCell>
                    <TableCell>{r.method ?? "—"}</TableCell>
                    <TableCell className="text-right tabular-nums text-emerald-700">{gh(r.amount)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          ) : (
            <Table>
              <TableHeader><TableRow>
                <TableHead>Date</TableHead><TableHead>Category</TableHead><TableHead>Description</TableHead>
                <TableHead>Vendor</TableHead><TableHead className="text-right">Amount</TableHead>
              </TableRow></TableHeader>
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
  </>)
}

// ----------------------------------------------------------------- pieces ---
// Poultry's Kpi / Formula / SectionCard (poultry-profit-loss-view.tsx), as the
// Restaurant page copies them (Poultry keeps them private to that file).

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

/** One band of the statement. Hotel cost lines are positive; a cost band prints them in parentheses. */
function SectionCard({ title, lines, totalLabel, totalAmount, gh, negative, tone, onOpen }: {
  title: string; lines: HotelProfitLossLine[]; totalLabel: string; totalAmount: number
  gh: (n: number) => string; negative?: boolean; tone: keyof typeof SECTION_TONES
  onOpen: (line: HotelProfitLossLine) => void
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
            <li key={l.lineKey}>
              <button type="button" onClick={() => onOpen(l)} className="flex w-full items-center gap-1.5 px-3 py-2 text-left hover:bg-slate-50">
                <span className="text-sm text-slate-900">{l.lineLabel}</span>
                <span className="text-[10px] text-slate-400">{l.entryCount}</span>
                <span className="ml-auto shrink-0 text-sm tabular-nums text-slate-900">{money(l.amount)}</span>
                <ChevronRight className="h-3.5 w-3.5 shrink-0 text-slate-400" />
              </button>
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
