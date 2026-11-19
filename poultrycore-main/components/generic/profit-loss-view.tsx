"use client"

// =============================================================================
// Generic Profit & Loss -- a port of Poultry's statement
// (components/poultry-reports/poultry-profit-loss-view.tsx), on Generic's data.
//
//   Revenue
//   − Direct Production Costs   = Gross Profit
//   − Operating Expenses        = Operating Profit
//   − Depreciation & Financing  = Net Profit
//
//   OWNER / LOANS / CAPITAL      excluded from profit
//
// Generic's server sends ONE flat list of entries ({ section, line, date,
// reference, description, amount }) rather than Poultry's report + six
// drilldown endpoints. The statement and every drilldown are built here from
// that one list, so a line and the records behind it can never disagree.
//
// Section mapping (Business/GenericProfitLoss.cs):
//   revenue   -> Revenue                 (Sales, Subscription income)
//   direct    -> Direct Production Costs (Cost of goods sold, Stock losses)
//   operating -> Operating Expenses      (expense categories, Payroll)
//   other     -> Depreciation & Financing Costs (Depreciation, Loan interest, Loan fees)
//   owner     -> Owner Contributions & Draws   (excluded)
//   borrowing -> Loans (Financing)             (Loan proceeds, Principal repaid; excluded)
//   capital   -> Capital Investments           (Asset purchases; excluded)
//
// Left out on purpose (Poultry-only): flock filter, cost-recognition strip and
// its settings link, the legacy-classification note, egg/feed/bird wording.
// =============================================================================

import { Fragment, useCallback, useEffect, useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ArrowLeft, Info, Loader2, ChevronRight, TrendingUp, Wallet, Building2, Banknote, Search, X } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useFmt, useFarmSettingsStore } from "@/lib/currency"
import { useToast } from "@/hooks/use-toast"
import { useLogout } from "@/hooks/use-logout"
import { useGenericModules } from "@/hooks/use-generic-modules"
import { cn } from "@/lib/utils"
import { defaultReportRange } from "@/lib/date-ranges"
import { PoultryReportFilter, type PoultryReportFilterValue } from "@/components/poultry-reports/poultry-report-filter"
import { PoultryReportExportButtons } from "@/components/poultry-reports/poultry-report-ui"
import { PlInfoSection as InfoSection } from "@/components/reports/pl-info-section"
import { RichCard } from "@/components/reports/report-header"
import { exportTableToPdf, emailTableAsPdf } from "@/lib/utils/pdf-export"
import { downloadCsv } from "@/lib/utils/download-csv"
import { getProfitLossEntries, type GenericProfitLossEntry as Entry } from "@/lib/api/generic"
import {
  PROFIT_VS_CASH_TITLE, PROFIT_VS_CASH_BODY,
  CASH_NOT_PROFIT_EXAMPLES, PROFIT_NOT_CASH_EXAMPLES,
  OWNER_SECTION_NOTE, BORROWING_SECTION_NOTE, CAPITAL_SECTION_NOTE, PL_METHOD_NOTE,
  OWNER_SECTION_RULE, BORROWING_SECTION_RULE, CAPITAL_SECTION_RULE,
} from "@/lib/poultry/financial-classification"

type Section = Entry["section"]

/** One statement line: every entry of one section + line, summed. */
type Line = { section: Section; lineKey: string; lineLabel: string; amount: number; entryCount: number; entries: Entry[] }

type DrillKind = "revenue" | "inventory" | "depreciation" | "financing" | "capital" | "expenses"
type DrillRow = { left: string; mid?: string; right?: string; amount: number; note?: string }

/** The same kinds and colours Poultry's drilldown uses. */
function drillKindFor(line: Line): DrillKind {
  if (line.section === "revenue") return "revenue"
  if (line.section === "capital") return "capital"
  if (line.section === "owner" || line.section === "borrowing") return "financing"
  if (line.section === "direct") return "inventory"
  if (line.section === "other") return line.lineKey === "Depreciation" ? "depreciation" : "financing"
  return "expenses"
}

/** Generic's entries carry a description and a reference, so those are the two text columns. */
const DRILL_COLUMNS: Record<DrillKind, { mid: string; right: string; blurb: string }> = {
  revenue: { mid: "Customer", right: "Reference", blurb: "Every sale behind this figure." },
  inventory: { mid: "Detail", right: "Reference", blurb: "Every sale or stock write-off behind this figure, at its recorded cost." },
  depreciation: { mid: "Description", right: "Reference", blurb: "Each depreciation charge for the period." },
  financing: { mid: "Detail", right: "Reference", blurb: "Every entry behind this figure. None of it is profit." },
  capital: { mid: "Asset", right: "Reference", blurb: "What was bought. It is an asset, not an expense." },
  expenses: { mid: "Description", right: "Reference", blurb: "Every expense behind this figure." },
}

const DRILL_TONES: Record<DrillKind, {
  band: string; border: string; amount: string; rail: string; divide: string; row: string; label: string
}> = {
  revenue:      { band: "bg-emerald-50 text-emerald-900", border: "border-emerald-200",
                  amount: "text-emerald-700", rail: "border-l-emerald-400",
                  divide: "divide-emerald-200", row: "border-emerald-200", label: "Money in" },
  inventory:    { band: "bg-rose-50 text-rose-900", border: "border-rose-200",
                  amount: "text-rose-700", rail: "border-l-rose-400",
                  divide: "divide-rose-200", row: "border-rose-200", label: "Direct cost" },
  expenses:     { band: "bg-amber-50 text-amber-900", border: "border-amber-200",
                  amount: "text-amber-700", rail: "border-l-amber-400",
                  divide: "divide-amber-200", row: "border-amber-200", label: "Running cost" },
  depreciation: { band: "bg-violet-50 text-violet-900", border: "border-violet-200",
                  amount: "text-violet-700", rail: "border-l-violet-400",
                  divide: "divide-violet-200", row: "border-violet-200", label: "Depreciation" },
  financing:    { band: "bg-violet-50 text-violet-900", border: "border-violet-200",
                  amount: "text-violet-700", rail: "border-l-violet-400",
                  divide: "divide-violet-200", row: "border-violet-200", label: "Not profit" },
  capital:      { band: "bg-sky-50 text-sky-900", border: "border-sky-200",
                  amount: "text-sky-700", rail: "border-l-sky-400",
                  divide: "divide-sky-200", row: "border-sky-200", label: "Not an expense" },
}

/** Interest and fees are a financing COST, so "other" holds them beside depreciation (as on Poultry). */
const LINE_ORDER: Partial<Record<Section, string[]>> = {
  revenue: ["Sales", "Subscription income"],
  direct: ["Cost of goods sold", "Stock losses"],
  operating: ["Payroll"],
  other: ["Depreciation", "Loan interest", "Loan fees"],
  owner: ["Owner contributions", "Owner draws"],
  borrowing: ["Loan proceeds", "Principal repaid"],
  capital: ["Asset purchases"],
}

function drillDate(v: string) {
  const m = /^(\d{4})-(\d{2})(?:-(\d{2}))?/.exec(v ?? "")
  if (!m) return v || "—"
  const [, y, mo, d] = m
  const month = new Date(Number(y), Number(mo) - 1, 1).toLocaleString(undefined, { month: "short" })
  return d ? `${Number(d)} ${month} ${y}` : `${month} ${y}`
}

const round2 = (n: number) => Math.round(n * 100) / 100
const marginOf = (part: number, revenue: number) => revenue ? Math.round(part * 1000 / revenue) / 10 : null

/**
 * Two skins, one statement (as on Poultry):
 *   report  /generic-reports/period-pnl -- report chrome, back to the catalogue.
 *   page    /generic-profit-loss        -- Money-page header, no back link.
 * The `report` prop is kept so both routes keep working unchanged.
 */
export function GenericProfitLossView({ report = false }: { report?: boolean }) {
  const isReport = report
  const router = useRouter()
  const logout = useLogout()
  const farmId = useAuthStore((s) => s.activeFarmId)
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const farmName = useAuthStore((s) => s.activeFarmName)
  const settings = useFarmSettingsStore((s) => s.settings)
  const { labels, isSubscriptionBusiness } = useGenericModules()
  const gh = useFmt()
  const { toast } = useToast()

  useEffect(() => {
    if (activeFarmType && activeFarmType !== "Generic") router.replace("/dashboard")
  }, [activeFarmType, router])

  const initial = useMemo(() => defaultReportRange(), [])
  const [filter, setFilter] = useState<PoultryReportFilterValue>({ fromDate: initial.from, toDate: initial.to })

  const [entries, setEntries] = useState<Entry[] | null>(null)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [downloading, setDownloading] = useState(false)

  const currencyLabel = `${settings?.currencyCode ?? "GHS"} (${settings?.currencySymbol ?? "GHC"})`
  const [generatedAt, setGeneratedAt] = useState("")
  useEffect(() => { setGeneratedAt(new Date().toLocaleString()) }, [])

  const [drill, setDrill] = useState<{ line: Line; rows: DrillRow[]; kind: DrillKind } | null>(null)
  const [drillQuery, setDrillQuery] = useState("")

  const validRange = !!filter.fromDate && !!filter.toDate && filter.fromDate <= filter.toDate

  const load = useCallback(async () => {
    if (!farmId || activeFarmType !== "Generic") return
    if (!validRange) { setBusy(false); setEntries(null); setError("Choose a valid start and end date."); return }
    setBusy(true); setError(null)
    try {
      setEntries(await getProfitLossEntries(farmId, filter.fromDate, filter.toDate))
      setGeneratedAt(new Date().toLocaleString())
    } catch (e: any) {
      setError(e?.message ?? String(e))
    } finally { setBusy(false) }
  }, [farmId, activeFarmType, validRange, filter.fromDate, filter.toDate])

  useEffect(() => { void load() }, [load])

  // ---------------------------------------------------- statement figures --
  const lineLabel = useCallback((section: Section, line: string) =>
    section === "revenue" && line === "Subscription income" && labels?.subscription
      ? `${labels.subscription} income` : line, [labels])

  const linesBySection = useMemo(() => {
    const map = new Map<Section, Map<string, Line>>()
    for (const e of entries ?? []) {
      const sec = map.get(e.section) ?? new Map<string, Line>()
      const l = sec.get(e.line) ?? { section: e.section, lineKey: e.line, lineLabel: lineLabel(e.section, e.line), amount: 0, entryCount: 0, entries: [] }
      l.amount += Number(e.amount) || 0
      l.entryCount += 1
      l.entries.push(e)
      sec.set(e.line, l)
      map.set(e.section, sec)
    }
    return map
  }, [entries, lineLabel])

  const bySection = useCallback((s: Section): Line[] => {
    const order = LINE_ORDER[s] ?? []
    const rank = (k: string) => { const i = order.indexOf(k); return i < 0 ? order.length : i }
    return Array.from(linesBySection.get(s)?.values() ?? [])
      .map((l) => ({ ...l, amount: round2(l.amount) }))
      .sort((a, b) => rank(a.lineKey) - rank(b.lineKey) || a.lineLabel.localeCompare(b.lineLabel))
  }, [linesBySection])

  const totalOf = useCallback((s: Section) => round2(bySection(s).reduce((sum, l) => sum + l.amount, 0)), [bySection])

  const totalRevenue = totalOf("revenue")
  const totalDirectCosts = totalOf("direct")
  const totalOperatingExpenses = totalOf("operating")
  const totalOtherCosts = totalOf("other")
  const grossProfit = round2(totalRevenue - totalDirectCosts)
  const operatingProfit = round2(grossProfit - totalOperatingExpenses)
  const netProfit = round2(operatingProfit - totalOtherCosts)
  const totalExpenses = round2(totalDirectCosts + totalOperatingExpenses + totalOtherCosts)
  const grossMarginPercent = marginOf(grossProfit, totalRevenue)
  const netMarginPercent = marginOf(netProfit, totalRevenue)
  const status = netProfit > 0 ? "Profit" : netProfit < 0 ? "Loss" : "Break-even"
  const netOwnerFunding = totalOf("owner")
  const netBorrowing = totalOf("borrowing")
  const totalCapitalInvestments = totalOf("capital")
  const subscriptionIncome = bySection("revenue").find((l) => l.lineKey === "Subscription income")?.amount ?? 0

  // -------------------------------------------------------------- drilldown --
  const drillRows = useMemo(() => {
    const rows = drill?.rows ?? []
    const q = drillQuery.trim().toLowerCase()
    if (!q) return rows
    return rows.filter((r) => [r.left, r.mid, r.right, r.note].some((v) => (v ?? "").toLowerCase().includes(q)))
  }, [drill, drillQuery])
  const drillShownTotal = useMemo(() => drillRows.reduce((sum, r) => sum + r.amount, 0), [drillRows])
  const drillFullTotal = useMemo(() => (drill?.rows ?? []).reduce((sum, r) => sum + r.amount, 0), [drill])
  const drillFiltered = drillQuery.trim().length > 0

  const openDrill = useCallback((line: Line) => {
    setDrillQuery("")
    const rows: DrillRow[] = line.entries.map((e) => ({
      left: String(e.date ?? "").split("T")[0],
      mid: e.description || "—",
      right: e.reference || "—",
      amount: Number(e.amount) || 0,
    }))
    setDrill({ line, rows, kind: drillKindFor(line) })
  }, [])

  // ----------------------------------------------------------------- export --
  const exportOpts = useCallback(() => {
    if (!entries) return null
    const rows: (string | number)[][] = []
    const push = (label: string, amount: number | null, kind = "") => rows.push([kind, label, amount == null ? "" : amount])

    push("REVENUE", null, "Section")
    bySection("revenue").forEach((l) => push(l.lineLabel, l.amount))
    push("Total Revenue", totalRevenue, "Total")
    push("DIRECT PRODUCTION COSTS", null, "Section")
    bySection("direct").forEach((l) => push(l.lineLabel, l.amount))
    push("Total Direct Production Costs", totalDirectCosts, "Total")
    push("GROSS PROFIT", grossProfit, "Result")
    push("OPERATING EXPENSES", null, "Section")
    bySection("operating").forEach((l) => push(l.lineLabel, l.amount))
    push("Total Operating Expenses", totalOperatingExpenses, "Total")
    push("OPERATING PROFIT", operatingProfit, "Result")
    push("DEPRECIATION & FINANCING", null, "Section")
    bySection("other").forEach((l) => push(l.lineLabel, l.amount))
    push("Total Depreciation & Financing", totalOtherCosts, "Total")
    push("NET PROFIT", netProfit, "Result")
    push("FINANCING & OWNER ACTIVITY (excluded from profit)", null, "Excluded")
    bySection("owner").forEach((l) => push(l.lineLabel, l.amount, "Excluded"))
    bySection("borrowing").forEach((l) => push(l.lineLabel, l.amount, "Excluded"))
    push("CAPITAL INVESTMENTS (excluded from profit)", null, "Excluded")
    bySection("capital").forEach((l) => push(l.lineLabel, l.amount, "Excluded"))
    push("Total Capital Investments", totalCapitalInvestments, "Excluded")

    return {
      title: "Profit & Loss",
      filename: `generic-profit-loss-${filter.fromDate}-${filter.toDate}`,
      farmName: farmName ?? undefined,
      fromDate: filter.fromDate,
      toDate: filter.toDate,
      currencyLabel,
      summaryLines: [
        `Total Revenue: ${gh(totalRevenue)}`,
        `Gross Profit: ${gh(grossProfit)}`,
        `Operating Profit: ${gh(operatingProfit)}`,
        `Net Profit: ${gh(netProfit)}`,
      ],
      columns: [{ header: "" }, { header: "Line" }, { header: "Amount", align: "right" as const }],
      rows,
      orientation: "portrait" as const,
      notes: [PL_METHOD_NOTE],
    }
  }, [entries, bySection, farmName, filter.fromDate, filter.toDate, gh, currencyLabel,
      totalRevenue, totalDirectCosts, grossProfit, totalOperatingExpenses, operatingProfit,
      totalOtherCosts, netProfit, totalCapitalInvestments])

  const onCsv = () => {
    const o = exportOpts(); if (!o) return
    downloadCsv(o.filename, ["Kind", "Line", "Amount"], o.rows)
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
      if (!res.success) throw new Error(res.message ?? "Delivery failed.")
      toast({ title: "Report emailed", description: res.recipient })
    } catch (e: any) { toast({ title: "Email failed", description: e?.message ?? String(e), variant: "destructive" }) }
    finally { setDownloading(false) }
  }

  // ------------------------------------------------------------------ render --
  if (activeFarmType && activeFarmType !== "Generic") return null

  const data = entries

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar onLogout={logout} />
      <div className="flex-1 min-w-0 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4">
          {isReport ? (
            <div className="flex items-center justify-between gap-2 flex-wrap print:hidden">
              <Button asChild variant="outline" size="sm">
                <Link href="/generic-reports"><ArrowLeft className="h-4 w-4 mr-1" /> Reports</Link>
              </Button>
              <PoultryReportExportButtons onCsv={onCsv} onPdf={onPdf} onEmail={onEmail}
                                          busy={downloading} disabled={!data} />
            </div>
          ) : (
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
                <PoultryReportExportButtons onCsv={onCsv} onPdf={onPdf} onEmail={onEmail}
                                            busy={downloading} disabled={!data} />
              </div>
            </div>
          )}

          <div className={isReport
            ? "bg-white rounded-xl border border-slate-200 shadow-sm overflow-hidden print:border-0 print:shadow-none"
            : undefined}>
            {isReport && <div className="h-1.5 bg-gradient-to-r from-amber-500 to-amber-400 print:hidden" />}
            <div className={isReport ? "p-4 sm:p-6 print:p-0 space-y-4" : "space-y-4"}>
              {isReport && (
                <header className="border-b border-slate-200 pb-4">
                  <div className="text-xs font-semibold uppercase tracking-wider text-amber-700">
                    {farmName ?? "Company"}
                  </div>
                  <h1 className="text-2xl font-semibold text-slate-900 mt-0.5">Profit &amp; Loss</h1>
                  <p className="text-sm text-slate-500 mt-1">
                    Did the business make money from its operations this period?
                  </p>
                  <div className="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-1 text-sm text-slate-500">
                    <div><span className="font-medium text-slate-600">Period:</span> {filter.fromDate} → {filter.toDate}</div>
                    <div><span className="font-medium text-slate-600">Currency:</span> {currencyLabel}</div>
                    <div><span className="font-medium text-slate-600">Generated:</span> {generatedAt}</div>
                  </div>
                </header>
              )}

              <PoultryReportFilter
                value={filter}
                onChange={setFilter}
                onReset={() => setFilter({ ...filter, fromDate: initial.from, toDate: initial.to })}
                show={{}}
                flocks={[]}
                customers={[]}
              />

              {busy && (
                <div className="flex items-center gap-2 text-sm text-slate-500 py-10 justify-center">
                  <Loader2 className="w-4 h-4 animate-spin" /> Loading…
                </div>
              )}

              {error && (
                <Card className="border-red-200 bg-red-50"><CardContent className="p-4 text-sm text-red-800">
                  {error}
                </CardContent></Card>
              )}

              {data && !busy && !error && (
                <>
                  <div className="grid gap-3 grid-cols-2 lg:grid-cols-3 xl:grid-cols-5">
                    <Kpi label="Total revenue" value={gh(totalRevenue)} tone="slate"
                         term="Everything sold this period"
                         tip="Approved sales in this period, excluding sales tax, whether or not the customer has paid yet. Money a customer still owes you is revenue; money they paid for a sale in an earlier period is not."
                         hint="Approved sales, excluding sales tax" />
                    <Kpi label="Total expenses"
                         value={gh(totalExpenses)}
                         term="Everything taken off revenue"
                         tip="Every cost in this period: the direct cost of what you sold (cost of goods sold and stock written off), the cost of running the business (payroll and your expense categories) and depreciation plus the interest and fees on borrowing. Revenue minus this figure is Net profit. It does NOT include owner draws, loan principal or capital purchases — those are money moving, not costs."
                         hint={<Formula op="+" gh={gh} terms={[
                           { label: "Direct costs", value: totalDirectCosts, tone: "direct" },
                           { label: "Operating expenses", value: totalOperatingExpenses, tone: "operating" },
                           { label: "Depreciation & financing", value: totalOtherCosts, tone: "other" },
                         ]} />}
                         tone="red" />
                    <Kpi label="Gross profit"
                         value={gh(grossProfit)}
                         term={grossMarginPercent != null ? `${grossMarginPercent}% of sales` : "No sales this period"}
                         tip="What the TRADING made, before any of the cost of running a business. Revenue minus the direct cost of what you sold: the recorded cost of the goods and any stock written off. Negative here means the goods cost more than they sold for."
                         hint={<Formula op="−" gh={gh} terms={[
                           { label: "Revenue", value: totalRevenue, tone: "revenue" },
                           { label: "Direct costs", value: totalDirectCosts, tone: "direct" },
                         ]} />}
                         tone={grossProfit >= 0 ? "emerald" : "red"} />
                    <Kpi label="Operating profit"
                         value={gh(operatingProfit)}
                         term="Before depreciation and financing"
                         tip="What the BUSINESS made. Gross profit minus the cost of running it: payroll, rent, utilities, transport, repairs, admin and marketing. It stops short of wear on assets and the cost of borrowing, so it answers whether the operation itself pays for itself."
                         hint={<Formula op="−" gh={gh} terms={[
                           { label: "Gross profit", value: grossProfit, tone: "subtotal" },
                           { label: "Operating expenses", value: totalOperatingExpenses, tone: "operating" },
                         ]} />}
                         tone={operatingProfit >= 0 ? "emerald" : "red"} />
                    <Kpi label={netProfit < 0 ? "Net loss" : "Net profit"}
                         value={gh(netProfit)}
                         term={netMarginPercent != null ? `${netMarginPercent}% of sales` : status}
                         tip="What is actually left. Operating profit minus depreciation — the wear on buildings, machines and equipment — and the interest and fees on borrowing. Owner money, loan principal and capital purchases are NOT in this figure; they are money moving, not profit, and they are shown separately below."
                         hint={<Formula op="−" gh={gh} terms={[
                           { label: "Operating profit", value: operatingProfit, tone: "subtotal" },
                           { label: "Depreciation & financing", value: totalOtherCosts, tone: "other" },
                         ]} />}
                         tone={netProfit > 0 ? "emerald" : netProfit < 0 ? "red" : "slate"} strong />
                  </div>

                  <div className="grid gap-3 auto-rows-fr md:grid-cols-2 xl:grid-cols-4">
                    <SectionCard className="h-full" tone="emerald" title="Revenue" lines={bySection("revenue")}
                      totalLabel="Total Revenue" totalAmount={totalRevenue} onOpen={openDrill} gh={gh} />
                    <SectionCard className="h-full" tone="rose" negative title="Direct Production Costs" lines={bySection("direct")}
                      totalLabel="Total Direct Production Costs" totalAmount={totalDirectCosts} onOpen={openDrill} gh={gh} />
                    <SectionCard className="h-full" tone="amber" negative title="Operating Expenses" lines={bySection("operating")}
                      totalLabel="Total Operating Expenses" totalAmount={totalOperatingExpenses} onOpen={openDrill} gh={gh} />
                    <SectionCard className="h-full" tone="violet" negative title="Depreciation & Financing Costs" lines={bySection("other")}
                      totalLabel="Total Depreciation & Financing" totalAmount={totalOtherCosts} onOpen={openDrill} gh={gh} />
                  </div>

                  <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                    <InfoSection
                      icon={<Banknote className="w-4 h-4" />}
                      title="Owner Contributions & Draws"
                      subtitle="Excluded from profit"
                      note={noteWithRule(OWNER_SECTION_NOTE, OWNER_SECTION_RULE)}
                      lines={bySection("owner")}
                      onOpen={openDrill}
                      gh={gh}
                      footer={<div className="text-xs text-slate-600">Net owner funding <strong>{gh(netOwnerFunding)}</strong></div>}
                      links={[
                        { href: "/generic-owner-money", label: "View Owner Money" },
                        { href: "/generic-cash-flow", label: "View Cash Flow" },
                      ]}
                    />
                    <InfoSection
                      icon={<Wallet className="w-4 h-4" />}
                      title="Loans (Financing)"
                      subtitle="Excluded from profit"
                      note={noteWithRule(BORROWING_SECTION_NOTE, BORROWING_SECTION_RULE)}
                      lines={bySection("borrowing")}
                      onOpen={openDrill}
                      gh={gh}
                      footer={<div className="text-xs text-slate-600">Net borrowing <strong>{gh(netBorrowing)}</strong></div>}
                      links={[
                        { href: "/generic-loans", label: "View Loans" },
                        { href: "/generic-cash-flow", label: "View Cash Flow" },
                      ]}
                    />
                    <InfoSection
                      icon={<Building2 className="w-4 h-4" />}
                      title="Capital Investments"
                      subtitle="Excluded from immediate operating expenses"
                      note={noteWithRule(CAPITAL_SECTION_NOTE, CAPITAL_SECTION_RULE)}
                      lines={bySection("capital")}
                      onOpen={openDrill}
                      gh={gh}
                      footer={<div className="text-xs text-slate-600">Total capital investments <strong>{gh(totalCapitalInvestments)}</strong></div>}
                      links={[{ href: "/generic-assets", label: "View Capital Investments/Assets" }]}
                    />
                  </div>

                  {/* Generic-only: recurring income, for subscription businesses. */}
                  {isSubscriptionBusiness && (
                    <section aria-label="Income breakdown" className="grid gap-3 md:grid-cols-3">
                      <RichCard label={`${labels.subscription} income`} value={gh(subscriptionIncome)} />
                      <RichCard label="Other income" value={gh(totalRevenue - subscriptionIncome)} />
                      <RichCard label="Recurring share" value={totalRevenue ? (100 * subscriptionIncome / totalRevenue).toFixed(1) + "%" : "?"} />
                    </section>
                  )}

                  <Card className="border-sky-200 bg-sky-50"><CardContent className="p-4 space-y-3">
                    <div className="flex items-start gap-2">
                      <Info className="w-4 h-4 text-sky-700 mt-0.5 shrink-0" />
                      <div>
                        <div className="text-sm font-semibold text-sky-900">{PROFIT_VS_CASH_TITLE}</div>
                        <p className="text-xs text-sky-900 mt-1">{PROFIT_VS_CASH_BODY}</p>
                      </div>
                    </div>
                    <div className="grid gap-3 sm:grid-cols-2 text-xs text-sky-900">
                      <div>
                        <div className="font-medium">Cash out that is not this period&apos;s cost</div>
                        <ul className="mt-1 space-y-0.5 list-disc pl-4">
                          {CASH_NOT_PROFIT_EXAMPLES.map((x) => <li key={x}>{x}</li>)}
                        </ul>
                      </div>
                      <div>
                        <div className="font-medium">Costs that did not move cash this period</div>
                        <ul className="mt-1 space-y-0.5 list-disc pl-4">
                          {PROFIT_NOT_CASH_EXAMPLES.map((x) => <li key={x}>{x}</li>)}
                        </ul>
                      </div>
                    </div>
                    <Link href="/generic-cash-flow" className="text-xs text-sky-800 underline">View Cash Flow</Link>
                  </CardContent></Card>

                  <div className="text-[11px] text-slate-500 space-y-1">
                    <p>{PL_METHOD_NOTE}</p>
                  </div>
                </>
              )}
            </div>
          </div>

          <Dialog open={!!drill} onOpenChange={(o) => { if (!o) setDrill(null) }}>
            <DialogContent className="w-[95vw] sm:max-w-3xl">
              <DialogHeader className={cn("-m-6 mb-0 space-y-1 border-b p-6",
                drill ? DRILL_TONES[drill.kind].band : "", drill ? DRILL_TONES[drill.kind].border : "")}>
                <DialogTitle className="flex flex-wrap items-baseline gap-x-2 gap-y-1 pr-6 text-left">
                  <span className="min-w-0 break-words">{drill?.line.lineLabel}</span>
                  {drill && (
                    <Badge variant="outline"
                           className={cn("border-current/30 bg-white/60 text-[10px] font-medium", DRILL_TONES[drill.kind].amount)}>
                      {DRILL_TONES[drill.kind].label}
                    </Badge>
                  )}
                  <span className={cn("ml-auto text-sm font-semibold tabular-nums",
                                      drill ? DRILL_TONES[drill.kind].amount : "text-slate-500")}>
                    {gh(drill?.line.amount ?? 0)}
                  </span>
                </DialogTitle>
                <p className="text-left text-xs opacity-80">
                  {drill ? DRILL_COLUMNS[drill.kind].blurb : ""}
                  {" "}
                  {drillDate(filter.fromDate)} – {drillDate(filter.toDate)}
                </p>
              </DialogHeader>

              {(drill?.rows ?? []).length === 0 ? (
                <p className="py-8 text-center text-sm text-slate-500">
                  Nothing behind this figure in the selected period.
                </p>
              ) : (
                <>
                  <div className="relative">
                    <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                    <Input
                      value={drillQuery}
                      onChange={(e) => setDrillQuery(e.target.value)}
                      placeholder={`Filter these ${drill!.rows.length} records…`}
                      className="h-9 pl-8 pr-8"
                    />
                    {drillFiltered && (
                      <button type="button" onClick={() => setDrillQuery("")}
                              className="absolute right-2 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600"
                              aria-label="Clear filter">
                        <X className="h-4 w-4" />
                      </button>
                    )}
                  </div>

                  {drillFiltered && drillRows.length === 0 && (
                    <p className="py-6 text-center text-sm text-slate-500">Nothing here matches “{drillQuery}”.</p>
                  )}

                  <div className="-mx-2 max-h-[55vh] overflow-y-auto px-2 sm:mx-0 sm:max-h-[60vh] sm:px-0">
                    <ul className={cn("divide-y sm:hidden", DRILL_TONES[drill!.kind].divide)}>
                      {drillRows.map((r, i) => (
                        <li key={i} className={cn("border-l-2 py-3 pl-2", DRILL_TONES[drill!.kind].rail)}>
                          <div className="flex items-baseline justify-between gap-3">
                            <span className="text-xs font-medium uppercase tracking-wide text-slate-500">{drillDate(r.left)}</span>
                            <span className={cn("shrink-0 text-sm font-semibold tabular-nums", DRILL_TONES[drill!.kind].amount)}>
                              {gh(r.amount)}
                            </span>
                          </div>
                          {r.mid && <div className="mt-1 break-words text-sm text-slate-900">{r.mid}</div>}
                          {r.note && <div className="break-words text-[11px] text-slate-500">{r.note}</div>}
                          {r.right && r.right !== "—" && (
                            <div className="mt-1 break-words text-xs text-slate-500">
                              <span className="text-slate-400">{DRILL_COLUMNS[drill!.kind].right}: </span>
                              {r.right}
                            </div>
                          )}
                        </li>
                      ))}
                    </ul>

                    <Table className="hidden table-fixed sm:table">
                      <TableHeader className="sticky top-0 z-10 bg-white">
                        <TableRow className={cn(DRILL_TONES[drill!.kind].row)}>
                          <TableHead className="w-[116px]">Date</TableHead>
                          <TableHead>{DRILL_COLUMNS[drill!.kind].mid}</TableHead>
                          <TableHead className="w-[26%]">{DRILL_COLUMNS[drill!.kind].right}</TableHead>
                          <TableHead className="w-[124px] text-right">Amount</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {drillRows.map((r, i) => (
                          <TableRow key={i} className={cn("[&>td]:align-top", DRILL_TONES[drill!.kind].row)}>
                            <TableCell className="whitespace-nowrap text-sm text-slate-500">{drillDate(r.left)}</TableCell>
                            <TableCell className="text-sm break-words whitespace-normal">
                              {r.mid}
                              {r.note && <div className="text-[11px] text-slate-500">{r.note}</div>}
                            </TableCell>
                            <TableCell className="text-sm text-slate-500 break-words whitespace-normal">{r.right}</TableCell>
                            <TableCell className={cn("text-right text-sm font-medium tabular-nums", DRILL_TONES[drill!.kind].amount)}>
                              {gh(r.amount)}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>

                  <div className={cn("flex items-center justify-between gap-4 border-t pt-3 text-sm",
                                     drill ? DRILL_TONES[drill.kind].border : "")}>
                    <span className="text-slate-500">
                      {drillFiltered
                        ? `${drillRows.length} of ${drill!.rows.length} records`
                        : `${drill!.rows.length} ${drill!.rows.length === 1 ? "record" : "records"}`}
                    </span>
                    <span className="text-right">
                      <span className={cn("font-semibold tabular-nums", drill ? DRILL_TONES[drill.kind].amount : "")}>
                        {gh(drillShownTotal)}
                      </span>
                      {drillFiltered && (
                        <span className="block text-[11px] font-normal text-slate-500">
                          filtered · {gh(drillFullTotal)} in full
                        </span>
                      )}
                    </span>
                  </div>
                </>
              )}
            </DialogContent>
          </Dialog>
        </main>
      </div>
    </div>
  )
}

// ----------------------------------------------------------------- pieces ---
// Copied from the Poultry view (not exported there), so the two look the same.

const FORMULA_TONES = {
  revenue:   "text-emerald-700",
  direct:    "text-rose-700",
  operating: "text-amber-700",
  other:     "text-violet-700",
  subtotal:  "text-slate-700",
} as const

function Formula({ op, terms, gh }: {
  op: "+" | "−"
  terms: { label: string; value: number; tone: keyof typeof FORMULA_TONES }[]
  gh: (n: number, opts?: { showSymbol?: boolean }) => string
}) {
  const money = (n: number) => {
    const t = gh(n, { showSymbol: false })
    return n < 0 ? `(${t})` : t
  }
  const row = (cell: (t: (typeof terms)[number]) => string, className?: string) => (
    <div className={className}>
      {terms.map((t, i) => (
        <Fragment key={t.label}>
          {i > 0 && <span className="text-slate-400">{` ${op} `}</span>}
          <span className={FORMULA_TONES[t.tone]}>{cell(t)}</span>
        </Fragment>
      ))}
    </div>
  )
  return (
    <>
      {row((t) => t.label)}
      {row((t) => money(t.value), "font-medium tabular-nums")}
    </>
  )
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
        <div className={cn("text-[11px] uppercase tracking-wide text-slate-500",
                           tip && "cursor-help underline decoration-dotted underline-offset-2")}>
          {label}
        </div>
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

function SectionCard({ title, lines, totalLabel, totalAmount, onOpen, gh, negative, tone, className }: {
  title: string
  lines: Line[]
  totalLabel: string
  totalAmount: number
  onOpen: (l: Line) => void
  gh: (n: number) => string
  negative?: boolean
  tone: keyof typeof SECTION_TONES
  className?: string
}) {
  const t = SECTION_TONES[tone]
  const money = (n: number) => (negative ? `(${gh(n)})` : gh(n))
  return (
    <div className={cn("flex flex-col overflow-hidden rounded-xl border bg-white shadow-sm", t.border, className)}>
      <div className={cn("px-3 py-2 text-[11px] font-semibold uppercase tracking-wide", t.head)}>{title}</div>
      {lines.length === 0 ? (
        <p className="flex-1 px-4 py-4 text-sm text-slate-400">None this period</p>
      ) : (
        <ul className="flex-1 divide-y divide-slate-100">
          {lines.map((l) => (
            <li key={l.section + l.lineKey}>
              <button type="button" onClick={() => onOpen(l)}
                      className="flex w-full items-center gap-1.5 px-3 py-2 text-left transition-colors hover:bg-slate-50">
                <span className="inline-flex min-w-0 items-center gap-1 text-sm text-slate-900">
                  <span>{l.lineLabel}</span>
                  <ChevronRight className="h-3.5 w-3.5 shrink-0 text-slate-400" />
                </span>
                {l.entryCount > 0 && (
                  <span className="shrink-0 rounded-full bg-slate-100 px-1.5 py-0.5 text-[11px] text-slate-500"
                        title={`${l.entryCount} ${l.entryCount === 1 ? "entry" : "entries"}`}>
                    <span className="xl:hidden">{l.entryCount} {l.entryCount === 1 ? "entry" : "entries"}</span>
                    <span className="hidden xl:inline">{l.entryCount}</span>
                  </span>
                )}
                <span className="ml-auto shrink-0 text-sm tabular-nums text-slate-900">{money(l.amount)}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
      <div className={cn("mt-auto flex shrink-0 items-center gap-2 border-t px-3 py-2", t.border, t.total)}>
        <span className="text-sm font-semibold text-slate-900">{totalLabel}</span>
        <span className="ml-auto text-sm font-semibold tabular-nums text-slate-900">{money(totalAmount)}</span>
      </div>
    </div>
  )
}

function noteWithRule(note: string, rule: string): React.ReactNode {
  const at = note.indexOf(rule)
  if (at < 0) return note
  return (
    <>
      {note.slice(0, at)}
      <mark className="box-decoration-clone rounded bg-sky-100 px-1 py-0.5 font-medium text-sky-900">{rule}</mark>
      {note.slice(at + rule.length)}
    </>
  )
}
