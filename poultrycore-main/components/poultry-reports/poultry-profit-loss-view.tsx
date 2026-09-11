"use client"

// =============================================================================
// The redesigned Poultry Profit & Loss (migration 272).
//
// It has its own view rather than riding the shared report engine because it is
// not a table: it is a STATEMENT, with subtotals that carry meaning and two
// sections deliberately printed outside the arithmetic.
//
//   Revenue
//   − Direct Production Costs   = Gross Profit      is the farming profitable?
//   − Operating Expenses        = Operating Profit  is the business profitable?
//   − Depreciation & Financing  = Net Profit        what is actually left
//
//   FINANCING & OWNER ACTIVITY   excluded from profit
//   CAPITAL INVESTMENTS          excluded from immediate operating expenses
//
// The two informational sections are visually separated and labelled, because a
// reader who adds them into the total gets a number that means nothing. Every
// figure is clickable, and each drilldown reads the same server function the
// figure was built from, so the two can never disagree.
// =============================================================================

import { useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ArrowLeft, AlertTriangle, Info, Loader2, ChevronRight, Wallet, Building2 } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useFmt } from "@/lib/currency"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
import {
  SECTION_TONES, StatementPanel, stated, type SectionTone,
} from "@/components/reports/statement-sections"
import { defaultReportRange } from "@/lib/date-ranges"
import {
  PoultryReportFilter, type PoultryReportFilterValue,
} from "@/components/poultry-reports/poultry-report-filter"
import { PoultryReportExportButtons } from "@/components/poultry-reports/poultry-report-ui"
import { exportTableToPdf, emailTableAsPdf } from "@/lib/utils/pdf-export"
import {
  getPoultryProfitLoss, getPoultryPlExpenses, getPoultryPlRevenue, getPoultryPlInventory,
  getPoultryPlDepreciation, getPoultryPlFinancing, getPoultryPlCapital, drilldownKindFor,
  type PoultryProfitLossReport, type PoultryProfitLossLine, type PlSection,
} from "@/lib/api/poultry-profit-loss"
import {
  PROFIT_VS_CASH_TITLE, PROFIT_VS_CASH_BODY,
  CASH_NOT_PROFIT_EXAMPLES, PROFIT_NOT_CASH_EXAMPLES,
  FINANCING_SECTION_NOTE, CAPITAL_SECTION_NOTE, PL_METHOD_NOTE, legacyNote,
  recognitionSummaryLine, ITEM_OVERRIDE_TOOLTIP,
} from "@/lib/poultry/financial-classification"

type DrillRow = { left: string; mid?: string; right?: string; amount: number; note?: string }

export function PoultryProfitLossView() {
  const router = useRouter()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const farmName = useAuthStore((s) => s.activeFarmName)
  const gh = useFmt()
  const { toast } = useToast()

  const initial = useMemo(() => defaultReportRange(), [])
  const [filter, setFilter] = useState<PoultryReportFilterValue>({
    fromDate: initial.from, toDate: initial.to,
    flockId: null, customerName: null, supplierName: null, category: null,
    includeClosedFlocks: false,
  })

  const [data, setData] = useState<PoultryProfitLossReport | null>(null)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [downloading, setDownloading] = useState(false)

  const [drill, setDrill] = useState<{ line: PoultryProfitLossLine; rows: DrillRow[] } | null>(null)
  const [drillBusy, setDrillBusy] = useState(false)

  const load = useCallback(async () => {
    setBusy(true); setError(null)
    try {
      setData(await getPoultryProfitLoss({ startDate: filter.fromDate, endDate: filter.toDate }))
    } catch (e: any) {
      setError(e?.message ?? String(e))
    } finally { setBusy(false) }
  }, [filter.fromDate, filter.toDate])

  useEffect(() => { void load() }, [load])

  const lines = data?.lines ?? []
  const bySection = useCallback(
    (s: PlSection) => lines.filter((l) => l.section === s).sort((a, b) => a.sortOrder - b.sortOrder),
    [lines],
  )

  // -------------------------------------------------------------- drilldown --
  const openDrill = useCallback(async (line: PoultryProfitLossLine) => {
    setDrill({ line, rows: [] }); setDrillBusy(true)
    const range = { startDate: filter.fromDate, endDate: filter.toDate }
    try {
      const kind = drilldownKindFor(line.section, line.lineKey)
      let rows: DrillRow[] = []
      if (kind === "revenue") {
        rows = (await getPoultryPlRevenue({ ...range, lineKey: line.lineKey })).map((r) => ({
          left: (r.saleDate || "").split("T")[0],
          mid: r.product ?? "—",
          right: r.customerName ?? "—",
          amount: r.totalAmount,
        }))
      } else if (kind === "inventory") {
        // The recognition column is the point of this view: a period spanning a
        // settings change holds both a purchase recognised at purchase and a
        // consumption recognised at consumption, and they are different stock.
        rows = (await getPoultryPlInventory({ ...range, lineKey: line.lineKey })).map((r) => ({
          left: (r.expenseDate || "").split("T")[0],
          mid: r.itemName ?? r.description ?? "—",
          right: r.sourceLabel ?? "—",
          amount: r.amount,
          note: [r.recognition, r.quantity != null ? `${r.quantity} ${r.unitOfMeasure ?? ""}`.trim() : null,
                 r.costLayers ? `${r.costLayers} cost layer${r.costLayers === 1 ? "" : "s"}` : null]
                .filter(Boolean).join(" · "),
        }))
      } else if (kind === "depreciation") {
        rows = (await getPoultryPlDepreciation(range)).map((r) => ({
          left: (r.periodStart || "").split("T")[0]?.slice(0, 7) ?? "—",
          mid: r.assetName ?? "—",
          right: r.categoryName ?? "—",
          amount: r.amount,
          note: [r.originalCost != null ? `Cost ${gh(r.originalCost)}` : null,
                 r.bookValueAfter != null ? `Book value ${gh(r.bookValueAfter)}` : null,
                 r.sourceType && r.sourceType !== "Scheduled" ? r.sourceType : null]
                .filter(Boolean).join(" · "),
        }))
      } else if (kind === "financing") {
        rows = (await getPoultryPlFinancing({ ...range, lineKey: line.lineKey })).map((r) => ({
          left: (r.entryDate || "").split("T")[0],
          mid: r.description ?? "—",
          right: r.party ?? "—",
          amount: r.amount,
          note: r.reference ?? undefined,
        }))
      } else if (kind === "capital") {
        rows = (await getPoultryPlCapital(range))
          .filter((r) => (r.categoryName ?? "Other Assets") === line.lineKey)
          .map((r) => ({
            left: (r.costDate || "").split("T")[0],
            mid: r.assetName ?? "—",
            right: r.description ?? r.costCategory ?? "—",
            amount: r.amount,
            note: `Book value now ${gh(r.currentBookValue)}`,
          }))
      } else {
        rows = (await getPoultryPlExpenses({ ...range, lineKey: line.lineKey })).map((r) => ({
          left: (r.expenseDate || "").split("T")[0],
          mid: r.description ?? r.category ?? "—",
          right: r.supplierName ?? r.sourceLabel ?? "—",
          amount: r.amount,
          note: r.isLegacy ? "Placed by category (legacy record)" : undefined,
        }))
      }
      setDrill({ line, rows })
    } catch (e: any) {
      toast({ title: "Could not open the details", description: e?.message ?? String(e), variant: "destructive" })
      setDrill(null)
    } finally { setDrillBusy(false) }
  }, [filter.fromDate, filter.toDate, gh, toast])

  // ----------------------------------------------------------------- export --
  const exportOpts = useCallback(() => {
    if (!data) return null
    const rows: (string | number)[][] = []
    const push = (label: string, amount: number | null, kind = "") =>
      rows.push([kind, label, amount == null ? "" : amount])

    push("REVENUE", null, "Section")
    bySection("Revenue").forEach((l) => push(l.lineLabel, l.amount))
    push("Total Revenue", data.totalRevenue, "Total")
    push("DIRECT PRODUCTION COSTS", null, "Section")
    bySection("DirectCost").forEach((l) => push(l.lineLabel, l.amount))
    push("Total Direct Production Costs", data.totalDirectCosts, "Total")
    push("GROSS PROFIT", data.grossProfit, "Result")
    push("OPERATING EXPENSES", null, "Section")
    bySection("OperatingExpense").forEach((l) => push(l.lineLabel, l.amount))
    push("Total Operating Expenses", data.totalOperatingExpenses, "Total")
    push("OPERATING PROFIT", data.operatingProfit, "Result")
    push("DEPRECIATION & FINANCING", null, "Section")
    bySection("OtherCost").forEach((l) => push(l.lineLabel, l.amount))
    push("Total Depreciation & Financing", data.totalOtherCosts, "Total")
    push("NET PROFIT", data.netProfit, "Result")
    // Informational, and labelled so nothing in a spreadsheet can be added into
    // Net Profit by accident.
    push("FINANCING & OWNER ACTIVITY (excluded from profit)", null, "Excluded")
    bySection("Financing").forEach((l) => push(l.lineLabel, l.amount, "Excluded"))
    push("CAPITAL INVESTMENTS (excluded from profit)", null, "Excluded")
    bySection("CapitalInvestment").forEach((l) => push(l.lineLabel, l.amount, "Excluded"))
    push("Total Capital Investments", data.totalCapitalInvestments, "Excluded")

    return {
      title: "Profit & Loss",
      filename: "poultry-profit-loss",
      farmName: farmName ?? undefined,
      fromDate: filter.fromDate,
      toDate: filter.toDate,
      subtitle: `Cost recognition — Feed: ${recognitionSummaryLine(data.feedRecognitionMethod, data.hasItemOverrides)}; `
        + `Medication: ${recognitionSummaryLine(data.medicationRecognitionMethod, data.hasItemOverrides)}; `
        + `Capital assets: depreciation`,
      summaryLines: [
        `Total Revenue: ${gh(data.totalRevenue)}`,
        `Gross Profit: ${gh(data.grossProfit)}`,
        `Operating Profit: ${gh(data.operatingProfit)}`,
        `Net Profit: ${gh(data.netProfit)}`,
      ],
      columns: [{ header: "", dataKey: "kind" }, { header: "Line", dataKey: "label" }, { header: "Amount", dataKey: "amount" }],
      rows,
      orientation: "portrait" as const,
      notes: [PL_METHOD_NOTE],
    }
  }, [data, bySection, farmName, filter.fromDate, filter.toDate, gh])

  const onCsv = () => {
    const o = exportOpts(); if (!o) return
    const csv = [["Kind", "Line", "Amount"], ...o.rows].map((r) => r.map((c) => `"${String(c ?? "")}"`).join(",")).join("\n")
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8;" }))
    const a = document.createElement("a")
    a.href = url; a.download = "poultry-profit-loss.csv"; a.click()
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

  // ------------------------------------------------------------------ render --
  if (activeFarmType && activeFarmType !== "Poultry") {
    return (
      <div className="p-6 text-sm text-slate-600">
        This report is for poultry companies. <Link href="/dashboard" className="underline">Back to dashboard</Link>
      </div>
    )
  }

  const legacy = data ? legacyNote(data.legacyExpenses, data.classifiedExpenses) : null

  // The shared panel takes plain lines; each one carries the drilldown it opens.
  const panelLines = (section: PlSection) => bySection(section).map((l) => ({
    id: l.section + l.lineKey,
    label: l.lineLabel,
    amount: l.amount,
    entryCount: l.entryCount,
    onOpen: () => openDrill(l),
  }))

  return (
    <div className="flex h-screen bg-slate-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-4">
          <div className="flex flex-wrap items-center gap-3">
            <Button variant="ghost" size="sm" onClick={() => router.push("/poultry/reports")}>
              <ArrowLeft className="w-4 h-4 mr-1" /> Reports
            </Button>
            <div>
              <h1 className="text-lg font-semibold text-slate-900">Profit &amp; Loss</h1>
              <p className="text-xs text-slate-500">Did the business make money from its operations this period?</p>
            </div>
            <div className="ml-auto">
              <PoultryReportExportButtons onCsv={onCsv} onPdf={onPdf} onEmail={onEmail}
                                          busy={downloading} disabled={!data} />
            </div>
          </div>

          {/* Dates only. The other filters the shared engine offers -- flock,
              customer, supplier -- do not apply: a P&L is a company statement,
              and a flock-scoped one is a different report that already exists. */}
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

          {data && !busy && (
            <>
              {/* ---- the four numbers ------------------------------------ */}
              <div className="grid gap-3 grid-cols-2 lg:grid-cols-4">
                <Kpi label="Total Revenue" value={gh(data.totalRevenue)} tone="slate" />
                <Kpi label="Gross Profit" value={gh(data.grossProfit)}
                     hint={data.grossMarginPercent != null ? `${data.grossMarginPercent}% margin` : "No revenue this period"}
                     tone={data.grossProfit >= 0 ? "emerald" : "red"} />
                <Kpi label="Operating Profit" value={gh(data.operatingProfit)}
                     hint="After running costs, before depreciation and financing"
                     tone={data.operatingProfit >= 0 ? "emerald" : "red"} />
                <Kpi label="Net Profit" value={gh(data.netProfit)} hint={data.status}
                     tone={data.netProfit > 0 ? "emerald" : data.netProfit < 0 ? "red" : "slate"} strong />
              </div>

              {/* ---- how the costs were recognised ----------------------- */}
              {/* One pair per line on a phone: the method names are long
                  sentences, and wrapping them mid-phrase across a flex row
                  made the strip unreadable. */}
              <Card><CardContent className="p-3 grid gap-y-1.5 text-xs sm:flex sm:flex-wrap sm:items-center sm:gap-x-6 sm:gap-y-2">
                <span className="font-semibold uppercase tracking-wide text-slate-500">Cost recognition</span>
                <span><span className="text-slate-500">Feed:</span>{" "}
                  <span className="font-medium">{recognitionSummaryLine(data.feedRecognitionMethod, data.hasItemOverrides)}</span></span>
                <span><span className="text-slate-500">Medication:</span>{" "}
                  <span className="font-medium">{recognitionSummaryLine(data.medicationRecognitionMethod, data.hasItemOverrides)}</span></span>
                <span><span className="text-slate-500">Capital assets:</span>{" "}
                  <span className="font-medium">Depreciation</span></span>
                {data.hasItemOverrides && (
                  <Badge variant="outline" className="text-[10px] font-normal border-emerald-300 text-emerald-700"
                         title={ITEM_OVERRIDE_TOOLTIP}>
                    Some item overrides active
                  </Badge>
                )}
                <Link href="/poultry-financial-settings" className="text-sky-700 underline sm:ml-auto">Settings</Link>
              </CardContent></Card>

              {/* ---- the statement, side by side on a desktop ------------- */}
              {/* Four columns, one per section, so the whole statement is on a
                  single line of the page: where money came IN, and the three
                  places it goes OUT. Side by side the columns cannot show the
                  running results between them — Gross, Operating, Net are read
                  off the KPI tiles at the top of the page instead. Below lg:
                  the stacked statement further down, which is the readable
                  shape on a narrow screen and still carries them inline. */}
              <div className="hidden items-start gap-3 lg:grid lg:grid-cols-3">
                {/* Revenue and Depreciation & Financing are a line or two each,
                    so they share a column: stacked, they stand as tall as the
                    four-line Direct Production Costs beside them and the three
                    columns square off instead of leaving two stubs and a wall. */}
                <div className="flex flex-col gap-3">
                  <StatementPanel title="Revenue" totalLabel="Total Revenue" total={data.totalRevenue}
                                  lines={panelLines("Revenue")} gh={gh} tone="emerald" />
                  <StatementPanel title="Depreciation & Financing Costs" totalLabel="Total Depreciation & Financing"
                                  total={data.totalOtherCosts} lines={panelLines("OtherCost")}
                                  gh={gh} negative tone="violet" />
                </div>
                <StatementPanel title="Direct Production Costs" totalLabel="Total Direct Production Costs"
                                total={data.totalDirectCosts} lines={panelLines("DirectCost")}
                                gh={gh} negative tone="rose" />
                <StatementPanel title="Operating Expenses" totalLabel="Total Operating Expenses"
                                total={data.totalOperatingExpenses} lines={panelLines("OperatingExpense")}
                                gh={gh} negative tone="amber" />
              </div>

              <Card className="lg:hidden"><CardContent className="p-0">
                <Table>
                  <TableBody>
                    {/* One colour per section, carried by the heading, a spine
                        down the left of its lines, and its own subtotal — so the
                        eye can tell at a glance where money came IN (emerald)
                        from the three places it goes OUT, and the running
                        results (Gross / Operating / Net) read as the milestones
                        between them rather than as more rows. */}
                    <SectionRows title="Revenue" lines={bySection("Revenue")} onOpen={openDrill} gh={gh} tone="emerald" />
                    <TotalRow label="Total Revenue" amount={data.totalRevenue} gh={gh} tone="emerald" />

                    <SectionRows title="Direct Production Costs" lines={bySection("DirectCost")} onOpen={openDrill} gh={gh} negative tone="rose" />
                    <TotalRow label="Total Direct Production Costs" amount={data.totalDirectCosts} gh={gh} negative tone="rose" />
                    <ResultRow label="Gross Profit" amount={data.grossProfit} pct={data.grossMarginPercent} gh={gh} />

                    <SectionRows title="Operating Expenses" lines={bySection("OperatingExpense")} onOpen={openDrill} gh={gh} negative tone="amber" />
                    <TotalRow label="Total Operating Expenses" amount={data.totalOperatingExpenses} gh={gh} negative tone="amber" />
                    <ResultRow label="Operating Profit" amount={data.operatingProfit} pct={data.operatingMarginPercent} gh={gh} />

                    <SectionRows title="Depreciation & Financing Costs" lines={bySection("OtherCost")} onOpen={openDrill} gh={gh} negative tone="violet" />
                    <TotalRow label="Total Depreciation & Financing" amount={data.totalOtherCosts} gh={gh} negative tone="violet" />
                    <ResultRow label="Net Profit" amount={data.netProfit} pct={data.netMarginPercent} gh={gh} strong />
                  </TableBody>
                </Table>
              </CardContent></Card>

              {/* ---- informational: cash moved, profit did not ------------ */}
              <div className="grid gap-4 lg:grid-cols-2">
                <InfoSection
                  icon={<Wallet className="w-4 h-4" />}
                  title="Financing & Owner Activity"
                  subtitle="Excluded from profit"
                  note={FINANCING_SECTION_NOTE}
                  lines={bySection("Financing")}
                  onOpen={openDrill}
                  gh={gh}
                  footer={
                    <div className="flex flex-wrap gap-3 text-xs">
                      <span className="text-slate-600">Net owner funding <strong>{gh(data.netOwnerFunding)}</strong></span>
                      <span className="text-slate-600">Net borrowing <strong>{gh(data.netBorrowing)}</strong></span>
                    </div>
                  }
                  links={[
                    { href: "/poultry-owner-money", label: "View Owner Money" },
                    { href: "/poultry-loans", label: "View Loans" },
                    { href: "/cash-flow", label: "View Cash Flow" },
                  ]}
                />
                <InfoSection
                  icon={<Building2 className="w-4 h-4" />}
                  title="Capital Investments"
                  subtitle="Excluded from immediate operating expenses"
                  note={CAPITAL_SECTION_NOTE}
                  lines={bySection("CapitalInvestment")}
                  onOpen={openDrill}
                  gh={gh}
                  footer={
                    <div className="text-xs text-slate-600">
                      Total capital investments <strong>{gh(data.totalCapitalInvestments)}</strong>
                    </div>
                  }
                  links={[{ href: "/poultry-assets", label: "View Assets" }]}
                />
              </div>

              {/* ---- why the two numbers differ --------------------------- */}
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
                <Link href="/cash-flow" className="text-xs text-sky-800 underline">View Cash Flow</Link>
              </CardContent></Card>

              {/* ---- how the report classified itself --------------------- */}
              <div className="text-[11px] text-slate-500 space-y-1">
                <p>{PL_METHOD_NOTE}</p>
                {legacy && (
                  <p className="flex items-start gap-1.5 text-amber-700">
                    <AlertTriangle className="w-3.5 h-3.5 mt-0.5 shrink-0" />{legacy}
                  </p>
                )}
              </div>
            </>
          )}

          {/* ---- drilldown ------------------------------------------------ */}
          <Dialog open={!!drill} onOpenChange={(o) => { if (!o) setDrill(null) }}>
            <DialogContent className="max-w-3xl">
              <DialogHeader>
                <DialogTitle>
                  {drill?.line.lineLabel}
                  <span className="ml-2 font-normal text-sm text-slate-500">{gh(drill?.line.amount ?? 0)}</span>
                </DialogTitle>
              </DialogHeader>
              {drillBusy ? (
                <div className="py-10 flex justify-center"><Loader2 className="w-5 h-5 animate-spin text-slate-400" /></div>
              ) : (
                <div className="max-h-[60vh] overflow-y-auto">
                  {/* Phone: four columns cannot fit, so each entry is stacked —
                      what it was and how much on the first line, the date and
                      the source beneath. Same rows, same order, same total. */}
                  <div className="space-y-2 sm:hidden">
                    {(drill?.rows ?? []).length === 0 ? (
                      <p className="py-6 text-center text-sm text-slate-500">
                        Nothing behind this figure in the selected period.
                      </p>
                    ) : drill!.rows.map((r, i) => (
                      <div key={i} className="rounded-lg border border-slate-200 p-3">
                        <div className="flex items-start justify-between gap-3">
                          <span className="min-w-0 break-words text-sm font-medium text-slate-900">
                            {r.mid || r.left}
                          </span>
                          <span className="shrink-0 tabular-nums text-sm font-semibold">{gh(r.amount)}</span>
                        </div>
                        {r.note && <div className="mt-0.5 text-[11px] text-slate-500">{r.note}</div>}
                        <div className="mt-1 flex flex-wrap gap-x-3 text-[11px] text-slate-500">
                          <span>{r.left}</span>
                          {r.right && <span>{r.right}</span>}
                        </div>
                      </div>
                    ))}
                  </div>

                  <Table className="hidden sm:table">
                    <TableHeader><TableRow>
                      <TableHead>Date</TableHead><TableHead>Detail</TableHead>
                      <TableHead>Source</TableHead><TableHead className="text-right">Amount</TableHead>
                    </TableRow></TableHeader>
                    <TableBody>
                      {(drill?.rows ?? []).length === 0 ? (
                        <TableRow><TableCell colSpan={4} className="text-center text-slate-500 py-6">
                          Nothing behind this figure in the selected period.
                        </TableCell></TableRow>
                      ) : drill!.rows.map((r, i) => (
                        <TableRow key={i}>
                          <TableCell className="whitespace-nowrap text-sm">{r.left}</TableCell>
                          <TableCell className="text-sm whitespace-normal">
                            {r.mid}
                            {r.note && <div className="text-[11px] text-slate-500">{r.note}</div>}
                          </TableCell>
                          <TableCell className="text-sm text-slate-500">{r.right}</TableCell>
                          <TableCell className="text-right tabular-nums text-sm">{gh(r.amount)}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                  {/* The total is asserted on screen, not just in the tests: a
                      drilldown that does not add up to the line above it is the
                      first thing a sceptical owner checks. */}
                  {(drill?.rows ?? []).length > 0 && (
                    <div className="flex justify-end gap-4 border-t px-4 py-2 text-sm">
                      <span className="text-slate-500">{drill!.rows.length} record(s)</span>
                      <span className="font-semibold tabular-nums">
                        {gh(drill!.rows.reduce((s, r) => s + r.amount, 0))}
                      </span>
                    </div>
                  )}
                </div>
              )}
            </DialogContent>
          </Dialog>
        </main>
      </div>
    </div>
  )
}

// ----------------------------------------------------------------- pieces ---

function Kpi({ label, value, hint, tone, strong }: {
  label: string; value: string; hint?: string
  tone: "slate" | "emerald" | "red"; strong?: boolean
}) {
  const ring = tone === "emerald" ? "border-emerald-200" : tone === "red" ? "border-red-200" : "border-slate-200"
  const text = tone === "emerald" ? "text-emerald-700" : tone === "red" ? "text-red-700" : "text-slate-900"
  return (
    <Card className={cn(ring, strong && "ring-1 ring-slate-300")}>
      <CardContent className="p-3">
        <div className="text-[11px] uppercase tracking-wide text-slate-500">{label}</div>
        <div className={cn("text-lg font-semibold tabular-nums", text)}>{value}</div>
        {hint && <div className="text-[11px] text-slate-500">{hint}</div>}
      </CardContent>
    </Card>
  )
}

function SectionRows({ title, lines, onOpen, gh, negative, tone }: {
  title: string; lines: PoultryProfitLossLine[]
  onOpen: (l: PoultryProfitLossLine) => void
  gh: (n: number) => string; negative?: boolean; tone: SectionTone
}) {
  const t = SECTION_TONES[tone]
  return (
    <>
      {/* hover is pinned to the same tint: a heading is not clickable, and a
          row that lights up under the cursor reads as though it were. */}
      <TableRow className={cn(t.head, "hover:bg-inherit")}>
        <TableCell colSpan={2} className="px-3 py-2 text-[11px] font-semibold uppercase tracking-wide whitespace-normal sm:px-4">
          {title}
        </TableCell>
      </TableRow>
      {lines.length === 0 ? (
        <TableRow><TableCell colSpan={2} className={cn("border-l-4 py-2 pl-5 text-sm text-slate-400 whitespace-normal sm:pl-8", t.rail)}>None this period</TableCell></TableRow>
      ) : lines.map((l) => (
        <TableRow key={l.section + l.lineKey} className="cursor-pointer" onClick={() => onOpen(l)}>
          <TableCell className={cn("border-l-4 py-3 pl-5 pr-2 text-sm whitespace-normal sm:py-1.5 sm:pl-8", t.rail)}>
            <span className="inline-flex items-center gap-1 hover:underline">
              {l.lineLabel}
              <ChevronRight className="w-3.5 h-3.5 text-slate-400" />
            </span>
            <span className="ml-2 inline-block rounded-full bg-slate-100 px-1.5 py-px align-middle text-[10px] font-medium text-slate-500">
              {l.entryCount} {l.entryCount === 1 ? "entry" : "entries"}
            </span>
          </TableCell>
          <TableCell className="py-3 pr-3 text-right tabular-nums text-sm whitespace-nowrap sm:py-1.5 sm:pr-4">
            {stated(l.amount, gh, negative)}
          </TableCell>
        </TableRow>
      ))}
    </>
  )
}

function TotalRow({ label, amount, gh, negative, tone }: {
  label: string; amount: number; gh: (n: number) => string; negative?: boolean
  tone: SectionTone
}) {
  const t = SECTION_TONES[tone]
  return (
    <TableRow className={cn("border-t", t.total, "hover:bg-inherit")}>
      <TableCell className={cn("border-l-4 px-3 py-2 text-sm font-medium whitespace-normal sm:px-4 sm:py-1.5", t.rail)}>{label}</TableCell>
      <TableCell className="px-3 py-2 text-right tabular-nums text-sm font-medium whitespace-nowrap sm:px-4 sm:py-1.5">
        {stated(amount, gh, negative)}
      </TableCell>
    </TableRow>
  )
}

function ResultRow({ label, amount, pct, gh, strong }: {
  label: string; amount: number; pct?: number | null; gh: (n: number) => string; strong?: boolean
}) {
  return (
    <TableRow className={cn(
      "border-t-2 border-slate-300 hover:bg-inherit",
      // A result is an answer, so it is banded rather than tinted at the edge:
      // green when the farm is ahead at that line, red when it is behind, and
      // Net Profit — the one figure most readers came for — banded strongest.
      amount >= 0
        ? (strong ? "bg-emerald-100" : "bg-emerald-50")
        : (strong ? "bg-rose-100" : "bg-rose-50"),
    )}>
      {/* The spine stops at a result — that is the point of it — but the 4px
          it occupied is kept transparent so every label still starts on the
          same vertical line. */}
      <TableCell className={cn("border-l-4 border-transparent px-3 py-2.5 text-sm font-semibold whitespace-normal sm:px-4 sm:py-2", strong && "text-base")}>
        {label}
        {/* Its own chip, and under the label on a phone: run straight on after
            the label it read as one word — "Gross Profit-1830.3%" — and beside
            it on a phone it pushed the amount off a 360px screen. */}
        {pct != null && (
          <span className="mt-1 block w-fit rounded bg-white/70 px-1.5 py-px text-xs font-normal text-slate-500 ring-1 ring-slate-200 sm:mt-0 sm:ml-2 sm:inline-block">
            {pct}% of revenue
          </span>
        )}
      </TableCell>
      <TableCell className={cn(
        "px-3 py-2.5 text-right tabular-nums font-semibold whitespace-nowrap sm:px-4 sm:py-2", strong && "text-base",
        amount >= 0 ? "text-emerald-700" : "text-red-700",
      )}>
        {gh(amount)}
      </TableCell>
    </TableRow>
  )
}

/**
 * The two sections that are NOT profit. Deliberately in their own cards with
 * their own heading and explanation: a reader who adds these into Net Profit
 * gets a number that means nothing, and the layout is the first defence.
 */
function InfoSection({ icon, title, subtitle, note, lines, onOpen, gh, footer, links }: {
  icon: React.ReactNode; title: string; subtitle: string; note: string
  lines: PoultryProfitLossLine[]
  onOpen: (l: PoultryProfitLossLine) => void
  gh: (n: number) => string
  footer?: React.ReactNode
  links: { href: string; label: string }[]
}) {
  return (
    <Card className="border-dashed"><CardContent className="p-4 space-y-3">
      <div className="flex items-start gap-2">
        <span className="text-slate-500 mt-0.5">{icon}</span>
        <div>
          <div className="text-sm font-semibold text-slate-900">{title}</div>
          <div className="text-[11px] uppercase tracking-wide text-amber-700">{subtitle}</div>
        </div>
      </div>
      <p className="text-xs text-slate-600">{note}</p>
      {lines.length === 0 ? (
        <p className="text-sm text-slate-400">None this period.</p>
      ) : (
        // Each line is a drilldown trigger, so it needs a finger-sized row on
        // a phone; on a desktop it goes back to a tight statement line.
        <div className="space-y-1">
          {lines.map((l) => (
            <button key={l.lineKey} type="button" onClick={() => onOpen(l)}
                    className="flex w-full items-center justify-between gap-3 py-2 text-left text-sm hover:underline sm:py-0.5">
              <span className="inline-flex min-w-0 items-center gap-1">
                <span className="break-words">{l.lineLabel}</span>
                <ChevronRight className="w-3.5 h-3.5 shrink-0 text-slate-400" />
              </span>
              <span className="shrink-0 tabular-nums">{gh(l.amount)}</span>
            </button>
          ))}
        </div>
      )}
      {footer}
      <div className="flex flex-wrap gap-3 pt-1">
        {links.map((l) => (
          <Link key={l.href} href={l.href} className="text-xs text-sky-700 underline">{l.label}</Link>
        ))}
      </div>
    </CardContent></Card>
  )
}
