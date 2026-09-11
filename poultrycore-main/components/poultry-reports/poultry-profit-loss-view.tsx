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
import { ArrowLeft, AlertTriangle, Info, Loader2, ChevronRight, Wallet, Building2, Banknote } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useFmt } from "@/lib/currency"
import { useToast } from "@/hooks/use-toast"
import { cn } from "@/lib/utils"
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
  OWNER_SECTION_NOTE, BORROWING_SECTION_NOTE, CAPITAL_SECTION_NOTE, PL_METHOD_NOTE, legacyNote,
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

  // 272 splits Financing into four line keys; these are the two owner ones.
  // Named here rather than inlined so the owner card and the borrowing card
  // cannot drift into overlapping or leaving a key out -- borrowingLines is
  // deliberately "everything else", so a fifth key added later still appears
  // on the page instead of silently vanishing from both cards.
  const ownerLines = useMemo(
    () => bySection("Financing").filter(
      (l) => l.lineKey === "OwnerContributions" || l.lineKey === "OwnerDraws"),
    [bySection])
  const borrowingLines = useMemo(
    () => bySection("Financing").filter(
      (l) => l.lineKey !== "OwnerContributions" && l.lineKey !== "OwnerDraws"),
    [bySection])

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
              <Card><CardContent className="p-3 flex flex-wrap items-center gap-x-6 gap-y-2 text-xs">
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
                <Link href="/poultry-financial-settings" className="ml-auto text-sky-700 underline">Settings</Link>
              </CardContent></Card>

              {/* ---- the statement ---------------------------------------
                  ONE full-width table with FOUR columns, not two.
                  A two-column statement across a desktop leaves the amount on
                  the far edge, a hand-span from its own label, with nothing in
                  between. Narrowing the table, or cutting it into cards, both
                  fix that gap by making the page smaller -- a worse trade.
                  Filling it with Entries and % of Revenue fixes it with
                  information instead: the three numeric columns sit together on
                  the right, the label column takes what is left, and there is
                  no empty middle because nothing is empty. */}
              <Card><CardContent className="p-0 overflow-x-auto">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Section / Line</TableHead>
                      <TableHead className="w-[110px] text-right">Entries</TableHead>
                      <TableHead className="w-[170px] text-right">Amount</TableHead>
                      <TableHead className="w-[130px] text-right">% of Revenue</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    <StatementSection
                      title="Revenue" lines={bySection("Revenue")}
                      totalLabel="Total Revenue" totalAmount={data.totalRevenue}
                      revenue={data.totalRevenue} onOpen={openDrill} gh={gh}
                    />
                    <StatementSection
                      title="Direct Production Costs" negative lines={bySection("DirectCost")}
                      totalLabel="Total Direct Production Costs" totalAmount={data.totalDirectCosts}
                      resultLabel="Gross Profit" resultAmount={data.grossProfit}
                      resultPct={data.grossMarginPercent}
                      revenue={data.totalRevenue} onOpen={openDrill} gh={gh}
                    />
                    <StatementSection
                      title="Operating Expenses" negative lines={bySection("OperatingExpense")}
                      totalLabel="Total Operating Expenses" totalAmount={data.totalOperatingExpenses}
                      resultLabel="Operating Profit" resultAmount={data.operatingProfit}
                      resultPct={data.operatingMarginPercent}
                      revenue={data.totalRevenue} onOpen={openDrill} gh={gh}
                    />
                    <StatementSection
                      title="Depreciation & Financing Costs" negative lines={bySection("OtherCost")}
                      totalLabel="Total Depreciation & Financing" totalAmount={data.totalOtherCosts}
                      resultLabel="Net Profit" resultAmount={data.netProfit}
                      resultPct={data.netMarginPercent} strong
                      revenue={data.totalRevenue} onOpen={openDrill} gh={gh}
                    />
                  </TableBody>
                </Table>
              </CardContent></Card>

              {/* ---- informational: cash moved, profit did not ------------
                  Side by side: three across on a wide screen, two on medium,
                  stacked only on a phone. items-start is deliberately NOT set,
                  so the cards share a row height and their notes line up
                  instead of stepping.

                  Owner money is its own card rather than sharing one with
                  borrowing: they are both "not profit", but for different
                  reasons, and one card had to describe both at once. */}
              <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                <InfoSection
                  icon={<Banknote className="w-4 h-4" />}
                  title="Owner Contributions & Draws"
                  subtitle="Excluded from profit"
                  note={OWNER_SECTION_NOTE}
                  lines={ownerLines}
                  onOpen={openDrill}
                  gh={gh}
                  footer={
                    <div className="text-xs text-slate-600">
                      Net owner funding <strong>{gh(data.netOwnerFunding)}</strong>
                    </div>
                  }
                  links={[
                    { href: "/poultry-owner-money", label: "View Owner Money" },
                    { href: "/cash-flow", label: "View Cash Flow" },
                  ]}
                />
                <InfoSection
                  icon={<Wallet className="w-4 h-4" />}
                  title="Loans (Financing)"
                  subtitle="Excluded from profit"
                  note={BORROWING_SECTION_NOTE}
                  lines={borrowingLines}
                  onOpen={openDrill}
                  gh={gh}
                  footer={
                    <div className="text-xs text-slate-600">
                      Net borrowing <strong>{gh(data.netBorrowing)}</strong>
                    </div>
                  }
                  links={[
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
                  links={[{ href: "/poultry-assets", label: "View Capital Investments" }]}
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
                  <Table>
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
                          <TableCell className="text-sm">
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


/**
 * One band of the statement: its heading, its lines, its total, and the
 * subtotal that band produces.
 *
 * Emits rows into the shared table rather than owning a card of its own, so
 * every section uses one set of column widths and the figures line up down the
 * whole statement. Columns that do not line up are not a statement.
 *
 * % OF REVENUE is measured on the ABSOLUTE amount against total revenue, so a
 * cost reads "38.8% of revenue" rather than "-38.8%". A period with no revenue
 * prints an em dash rather than 0.0% or NaN: "0% of nothing" is not a fact.
 */
function StatementSection({
  title, lines, totalLabel, totalAmount, resultLabel, resultAmount, resultPct,
  revenue, onOpen, gh, negative, strong,
}: {
  title: string
  lines: PoultryProfitLossLine[]
  totalLabel: string; totalAmount: number
  resultLabel?: string; resultAmount?: number; resultPct?: number | null
  revenue: number
  onOpen: (l: PoultryProfitLossLine) => void
  gh: (n: number) => string
  negative?: boolean; strong?: boolean
}) {
  const money = (n: number) => (negative ? `(${gh(n)})` : gh(n))
  const pct = (n: number) =>
    revenue > 0 ? `${((Math.abs(n) / revenue) * 100).toFixed(1)}%` : "—"
  const entryTotal = lines.reduce((a, l) => a + l.entryCount, 0)

  return (
    <>
      <TableRow className="bg-slate-50 hover:bg-slate-50">
        <TableCell colSpan={4} className="py-2 text-[11px] font-semibold uppercase tracking-wide text-slate-500">
          {title}
        </TableCell>
      </TableRow>

      {lines.length === 0 ? (
        <TableRow>
          <TableCell colSpan={4} className="py-2 pl-8 text-sm text-slate-400">None this period</TableCell>
        </TableRow>
      ) : lines.map((l) => (
        <TableRow key={l.section + l.lineKey} className="cursor-pointer" onClick={() => onOpen(l)}>
          <TableCell className="py-1.5 pl-8 text-sm">
            <span className="inline-flex items-center gap-1 hover:underline">
              {l.lineLabel}
              <ChevronRight className="h-3.5 w-3.5 text-slate-400" />
            </span>
          </TableCell>
          <TableCell className="py-1.5 text-right text-sm tabular-nums text-slate-500">
            {l.entryCount}
          </TableCell>
          <TableCell className="py-1.5 text-right text-sm tabular-nums">{money(l.amount)}</TableCell>
          <TableCell className="py-1.5 text-right text-sm tabular-nums text-slate-500">
            {pct(l.amount)}
          </TableCell>
        </TableRow>
      ))}

      <TableRow className="border-t">
        <TableCell className="py-1.5 pl-8 text-sm font-medium">{totalLabel}</TableCell>
        <TableCell className="py-1.5 text-right text-sm tabular-nums text-slate-500">
          {entryTotal > 0 ? entryTotal : ""}
        </TableCell>
        <TableCell className="py-1.5 text-right text-sm font-medium tabular-nums">
          {money(totalAmount)}
        </TableCell>
        <TableCell className="py-1.5 text-right text-sm font-medium tabular-nums text-slate-500">
          {pct(totalAmount)}
        </TableCell>
      </TableRow>

      {resultLabel != null && resultAmount != null && (
        <TableRow className={cn("border-t-2 border-slate-300", strong && "bg-slate-50 hover:bg-slate-50")}>
          <TableCell className={cn("py-2 text-sm font-semibold", strong && "text-base")}>
            {resultLabel}
          </TableCell>
          {/* No entry count on a result row: it is arithmetic on the rows
              above, not a set of documents of its own. */}
          <TableCell />
          <TableCell className={cn(
            "py-2 text-right font-semibold tabular-nums", strong && "text-base",
            resultAmount >= 0 ? "text-emerald-700" : "text-red-700",
          )}>
            {gh(resultAmount)}
          </TableCell>
          <TableCell className={cn("py-2 text-right font-semibold tabular-nums text-slate-500", strong && "text-base")}>
            {resultPct != null ? `${resultPct}%` : pct(resultAmount)}
          </TableCell>
        </TableRow>
      )}
    </>
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
        <div className="space-y-1">
          {lines.map((l) => (
            <button key={l.lineKey} type="button" onClick={() => onOpen(l)}
                    className="flex w-full items-center justify-between text-sm hover:underline">
              <span className="inline-flex items-center gap-1">
                {l.lineLabel}<ChevronRight className="w-3.5 h-3.5 text-slate-400" />
              </span>
              <span className="tabular-nums">{gh(l.amount)}</span>
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
