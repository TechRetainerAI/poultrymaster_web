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

type DrillKind = ReturnType<typeof drilldownKindFor>

/**
 * What the two text columns of a drilldown actually hold, per kind.
 *
 * They used to be headed "Detail" and "Source" whatever the line was, which
 * told the reader nothing: behind Egg Sales they are a product and a customer,
 * behind Feed Cost an item and where the cost came from, behind Depreciation an
 * asset and its category. A column heading that names the wrong thing is worse
 * than one that names nothing, and both are worse than the truth.
 */
const DRILL_COLUMNS: Record<DrillKind, { mid: string; right: string; blurb: string }> = {
  revenue: { mid: "Product", right: "Customer", blurb: "Every sale behind this figure." },
  inventory: { mid: "Item", right: "Source", blurb: "Every stock movement behind this figure, and when its cost was recognised." },
  depreciation: { mid: "Asset", right: "Category", blurb: "Each asset's depreciation for the period." },
  financing: { mid: "Detail", right: "Party", blurb: "Every entry behind this figure. None of it is profit." },
  capital: { mid: "Asset", right: "Detail", blurb: "What was bought. It is an asset, not an expense." },
  expenses: { mid: "Description", right: "Supplier", blurb: "Every expense behind this figure." },
}

/**
 * "2026-09-02" reads as a database row; "2 Sep 2026" reads as a date. Anything
 * that is not a date the server built (a "2026-09" depreciation period, a dash)
 * is passed through untouched rather than guessed at.
 */
function drillDate(v: string) {
  const m = /^(\d{4})-(\d{2})(?:-(\d{2}))?$/.exec(v ?? "")
  if (!m) return v || "—"
  const [, y, mo, d] = m
  const month = new Date(Number(y), Number(mo) - 1, 1).toLocaleString(undefined, { month: "short" })
  return d ? `${Number(d)} ${month} ${y}` : `${month} ${y}`
}

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

  const [drill, setDrill] = useState<{ line: PoultryProfitLossLine; rows: DrillRow[]; kind: DrillKind } | null>(null)
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
    const kind = drilldownKindFor(line.section, line.lineKey)
    setDrill({ line, rows: [], kind }); setDrillBusy(true)
    const range = { startDate: filter.fromDate, endDate: filter.toDate }
    try {
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
      setDrill({ line, rows, kind })
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
                {/* Each tile is NAMED for what it is, and says what was taken
                    off to get there -- "Gross profit" told an owner nothing
                    about why it sat 189,000 below Revenue. The four read down
                    as one sentence: what we sold, then what is left after each
                    kind of cost.

                    "MINUS", never "less". A statement says "Sales less feed"
                    and an accountant reads it as a subtraction, but the first
                    owner to read these tiles asked what it meant -- it parses
                    as "fewer sales of feed". These tiles exist to avoid exactly
                    that kind of word. "Then minus" on the last two, so the
                    chain from one tile to the next is explicit.

                    The hint carries the AMOUNT subtracted, not just the names
                    of the costs. Without it the reader can see that 176,863
                    became 184,523 but not what the 7,660 was or where to find
                    it, and the next question is always "how did we get this?".
                    The figure is the same total the matching section card
                    below prints, so the tiles are checkable on their own and
                    the card is where you go to see what is in it.

                    The accounting term stays on the tile as the `term` line
                    rather than being dropped. It is what an accountant, a bank
                    or the exported PDF will ask for, and it is what the water
                    reports still call the same figures. */}
                <Kpi label="What we sold" term="Total revenue"
                     value={gh(data.totalRevenue)} tone="slate"
                     hint="Eggs, birds, manure and feed sold in this period" />
                <Kpi label="Left after feed &amp; bird costs"
                     term={data.grossMarginPercent != null
                       ? `Gross profit · ${data.grossMarginPercent}% of sales`
                       : "Gross profit · no sales this period"}
                     value={gh(data.grossProfit)}
                     hint={<Working
                       from={gh(data.totalRevenue)} fromLabel="we sold"
                       minus={gh(data.totalDirectCosts)} minusLabel="feed, medication, birds, direct labour" />}
                     tone={data.grossProfit >= 0 ? "emerald" : "red"} />
                <Kpi label="Left after running costs" term="Operating profit"
                     value={gh(data.operatingProfit)}
                     hint={<Working
                       from={gh(data.grossProfit)} fromLabel="left after feed & bird costs"
                       minus={gh(data.totalOperatingExpenses)} minusLabel="running costs — payroll, utilities, transport, repairs, admin" />}
                     tone={data.operatingProfit >= 0 ? "emerald" : "red"} />
                <Kpi label="What is left in the end" term={`Net profit · ${data.status}`}
                     value={gh(data.netProfit)}
                     hint={<Working
                       from={gh(data.operatingProfit)} fromLabel="left after running costs"
                       minus={gh(data.totalOtherCosts)} minusLabel="wear on assets, loan interest, fees" />}
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

              {/* ---- the statement, as section cards ----------------------
                  Three column STACKS, not a plain grid of four: Revenue and
                  Depreciation & Financing share the first column, so the short
                  one sits directly under the short one instead of waiting for
                  the tallest card in its row. A grid aligns rows; that is
                  exactly what leaves a hole under Revenue.

                  Below md there is one column and the stacks go `contents`, so
                  the cards become items of the outer grid directly and `order`
                  can put them back in statement order -- Revenue, Direct,
                  Operating, Depreciation -- for a phone, where reading is
                  top-to-bottom and the side-by-side grouping means nothing.

                  The running subtotals -- Gross, Operating and Net Profit -- are
                  NOT repeated inside the cards. They are the tiles at the top of
                  the page, and a figure printed twice invites a reader to add it
                  twice. */}
              <div className="grid gap-4 md:grid-cols-2 md:items-start xl:grid-cols-3">
                <div className="contents md:block md:space-y-4">
                  <SectionCard
                    className="order-1 md:order-none"
                    tone="emerald" title="Revenue" lines={bySection("Revenue")}
                    totalLabel="Total Revenue" totalAmount={data.totalRevenue}
                    onOpen={openDrill} gh={gh}
                  />
                  <SectionCard
                    className="order-4 md:order-none"
                    tone="violet" negative title="Depreciation & Financing Costs" lines={bySection("OtherCost")}
                    totalLabel="Total Depreciation & Financing" totalAmount={data.totalOtherCosts}
                    onOpen={openDrill} gh={gh}
                  />
                </div>
                <div className="contents md:block md:space-y-4">
                  <SectionCard
                    className="order-2 md:order-none"
                    tone="rose" negative title="Direct Production Costs" lines={bySection("DirectCost")}
                    totalLabel="Total Direct Production Costs" totalAmount={data.totalDirectCosts}
                    onOpen={openDrill} gh={gh}
                  />
                </div>
                <div className="contents md:block md:space-y-4">
                  <SectionCard
                    className="order-3 md:order-none"
                    tone="amber" negative title="Operating Expenses" lines={bySection("OperatingExpense")}
                    totalLabel="Total Operating Expenses" totalAmount={data.totalOperatingExpenses}
                    onOpen={openDrill} gh={gh}
                  />
                </div>
              </div>

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
                  links={[{ href: "/poultry-assets", label: "View Capital Investments/Assets" }]}
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

          {/* ---- drilldown ------------------------------------------------
              w-[95vw] paired with sm:max-w-3xl, NOT a bare max-w-3xl: an
              unprefixed width replaces the dialog's own
              max-w-[calc(100%-2rem)] -- costing the phone its side gutter --
              while losing to the base sm:max-w-2xl above 640px, so the old
              class made the dialog edge-to-edge on a phone AND narrower than
              asked for on a desktop. See components/ui/dialog.tsx.

              The four-column table is desktop only. On a phone the same rows
              are stacked records: date and amount on the top line where they
              are compared, detail and source underneath. A four-column table
              on a 390px screen is a horizontal scrollbar wearing a table's
              clothes. */}
          <Dialog open={!!drill} onOpenChange={(o) => { if (!o) setDrill(null) }}>
            <DialogContent className="w-[95vw] sm:max-w-3xl">
              <DialogHeader className="space-y-1">
                <DialogTitle className="flex flex-wrap items-baseline gap-x-2 gap-y-1 pr-6 text-left">
                  <span className="min-w-0 break-words">{drill?.line.lineLabel}</span>
                  <span className="text-sm font-normal tabular-nums text-slate-500">
                    {gh(drill?.line.amount ?? 0)}
                  </span>
                </DialogTitle>
                {/* Say what the list IS and over what period, rather than
                    leaving the reader to infer both from the rows. */}
                <p className="text-left text-xs text-slate-500">
                  {drill ? DRILL_COLUMNS[drill.kind].blurb : ""}
                  {" "}
                  {drillDate(filter.fromDate)} – {drillDate(filter.toDate)}
                </p>
              </DialogHeader>

              {drillBusy ? (
                <div className="flex justify-center py-10"><Loader2 className="h-5 w-5 animate-spin text-slate-400" /></div>
              ) : (drill?.rows ?? []).length === 0 ? (
                <p className="py-8 text-center text-sm text-slate-500">
                  Nothing behind this figure in the selected period.
                </p>
              ) : (
                <>
                  <div className="-mx-2 max-h-[55vh] overflow-y-auto px-2 sm:mx-0 sm:max-h-[60vh] sm:px-0">
                    {/* Phone: one record per block, each field labelled -- a
                        column heading a reader has scrolled past is no heading
                        at all. */}
                    <ul className="divide-y divide-slate-100 sm:hidden">
                      {drill!.rows.map((r, i) => (
                        <li key={i} className="py-3">
                          <div className="flex items-baseline justify-between gap-3">
                            <span className="text-xs font-medium uppercase tracking-wide text-slate-500">
                              {drillDate(r.left)}
                            </span>
                            <span className="shrink-0 text-sm font-semibold tabular-nums text-slate-900">
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

                    {/* Desktop: the columns line up, so keep them -- but headed
                        with what they actually hold for THIS line, and stuck to
                        the top so they survive a long list.

                        table-fixed with declared widths, so a long description
                        or supplier name wraps inside its column instead of
                        pushing Amount off the right edge and leaving the reader
                        to scroll sideways for the one number they came for. */}
                    <Table className="hidden table-fixed sm:table">
                      <TableHeader className="sticky top-0 z-10 bg-white">
                        <TableRow>
                          <TableHead className="w-[116px]">Date</TableHead>
                          <TableHead>{drill ? DRILL_COLUMNS[drill.kind].mid : "Detail"}</TableHead>
                          <TableHead className="w-[26%]">{drill ? DRILL_COLUMNS[drill.kind].right : "Source"}</TableHead>
                          <TableHead className="w-[124px] text-right">Amount</TableHead>
                        </TableRow>
                      </TableHeader>
                      {/* [&>td]:align-top, not align-top on the row: TableCell
                          carries align-middle, which wins over the row and
                          leaves the date floating mid-way down a wrapped row. */}
                      <TableBody>
                        {drill!.rows.map((r, i) => (
                          <TableRow key={i} className="[&>td]:align-top">
                            <TableCell className="whitespace-nowrap text-sm text-slate-500">{drillDate(r.left)}</TableCell>
                            {/* whitespace-normal: TableCell ships whitespace-nowrap,
                                which is what was driving a long description straight
                                through the next column. */}
                            <TableCell className="text-sm break-words whitespace-normal">
                              {r.mid}
                              {r.note && <div className="text-[11px] text-slate-500">{r.note}</div>}
                            </TableCell>
                            <TableCell className="text-sm text-slate-500 break-words whitespace-normal">{r.right}</TableCell>
                            <TableCell className="text-right text-sm font-medium tabular-nums">{gh(r.amount)}</TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </div>

                  {/* The total is asserted on screen, not just in the tests: a
                      drilldown that does not add up to the line above it is the
                      first thing a sceptical owner checks. It sits OUTSIDE the
                      scroll box, so it is still there after scrolling -- which
                      is the only moment anyone wants it. */}
                  <div className="flex items-center justify-between gap-4 border-t pt-3 text-sm">
                    <span className="text-slate-500">
                      {drill!.rows.length} {drill!.rows.length === 1 ? "record" : "records"}
                    </span>
                    <span className="font-semibold tabular-nums">
                      {gh(drill!.rows.reduce((s, r) => s + r.amount, 0))}
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

/**
 * The two lines of a tile's arithmetic: where the figure started, and what came
 * off it. The value printed above the tile is the answer, so the result is not
 * repeated here -- it is the number the reader is already looking at.
 *
 * `from` names the PREVIOUS tile in the owner's words, not the accounting term,
 * so the four tiles chain visibly: "we sold" -> "left after feed & bird costs"
 * -> "left after running costs".
 */
function Working({ from, fromLabel, minus, minusLabel }: {
  from: string; fromLabel: string; minus: string; minusLabel: string
}) {
  return (
    <>
      <div>
        <span className="text-slate-400">from</span>{" "}
        <span className="font-medium tabular-nums text-slate-600">{from}</span> {fromLabel}
      </div>
      <div>
        <span className="text-slate-400">minus</span>{" "}
        <span className="font-medium tabular-nums text-slate-600">{minus}</span> {minusLabel}
      </div>
    </>
  )
}

function Kpi({ label, value, hint, term, tone, strong }: {
  label: string; value: string
  /**
   * ReactNode, not string: the three derived tiles print TWO lines here --
   * what the figure started from, and what was taken off it -- because one
   * line naming only the subtraction ("minus 7,660") sits under a value of
   * -184,523 and reconciles with nothing. The reader was being asked to
   * remember the previous tile.
   */
  hint?: React.ReactNode
  /**
   * The accounting name for this figure, kept under the plain-English one.
   * Both are needed and neither replaces the other: the owner reads the label,
   * everyone the farm hands the report to reads this. It also carries the
   * ratio or status that used to be the hint, since a margin and a "Loss" are
   * accountant's shorthand rather than the plain explanation the hint now gives.
   */
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


const SECTION_TONES = {
  emerald: { head: "bg-emerald-50 text-emerald-800", total: "bg-emerald-50/60", border: "border-emerald-200" },
  rose: { head: "bg-rose-50 text-rose-800", total: "bg-rose-50/60", border: "border-rose-200" },
  amber: { head: "bg-amber-50 text-amber-800", total: "bg-amber-50/60", border: "border-amber-200" },
  violet: { head: "bg-violet-50 text-violet-800", total: "bg-violet-50/60", border: "border-violet-200" },
} as const

/**
 * One band of the statement: its heading, its lines and its total, in a card of
 * its own.
 *
 * Costs print in parentheses rather than with a minus sign -- accounting
 * notation, and the one that survives being read quickly. Every line is a
 * button, not a row with a click handler, so it is reachable by keyboard and
 * announces itself; the drilldown behind it reads the same server function the
 * figure was built from.
 */
function SectionCard({
  title, lines, totalLabel, totalAmount, onOpen, gh, negative, tone, className,
}: {
  title: string
  lines: PoultryProfitLossLine[]
  totalLabel: string
  totalAmount: number
  onOpen: (l: PoultryProfitLossLine) => void
  gh: (n: number) => string
  negative?: boolean
  tone: keyof typeof SECTION_TONES
  className?: string
}) {
  const t = SECTION_TONES[tone]
  const money = (n: number) => (negative ? `(${gh(n)})` : gh(n))

  return (
    <div className={cn("overflow-hidden rounded-xl border bg-white shadow-sm", t.border, className)}>
      <div className={cn("px-4 py-2 text-[11px] font-semibold uppercase tracking-wide", t.head)}>
        {title}
      </div>

      {lines.length === 0 ? (
        <p className="px-4 py-4 text-sm text-slate-400">None this period</p>
      ) : (
        <ul className="divide-y divide-slate-100">
          {lines.map((l) => (
            <li key={l.section + l.lineKey}>
              <button
                type="button"
                onClick={() => onOpen(l)}
                className="flex w-full items-center gap-2 px-4 py-2 text-left transition-colors hover:bg-slate-50"
              >
                {/* No truncation: a statement line that reads "Medication &
                    Vete..." on a phone has hidden the very thing the reader
                    came for. It wraps instead and the row grows. */}
                <span className="inline-flex min-w-0 items-center gap-1 text-sm text-slate-900">
                  <span>{l.lineLabel}</span>
                  <ChevronRight className="h-3.5 w-3.5 shrink-0 text-slate-400" />
                </span>
                {l.entryCount > 0 && (
                  <span className="shrink-0 rounded-full bg-slate-100 px-2 py-0.5 text-[11px] text-slate-500">
                    {l.entryCount} {l.entryCount === 1 ? "entry" : "entries"}
                  </span>
                )}
                <span className="ml-auto shrink-0 text-sm tabular-nums text-slate-900">{money(l.amount)}</span>
              </button>
            </li>
          ))}
        </ul>
      )}

      <div className={cn("flex items-center gap-2 border-t px-4 py-2", t.border, t.total)}>
        <span className="text-sm font-semibold text-slate-900">{totalLabel}</span>
        <span className="ml-auto text-sm font-semibold tabular-nums text-slate-900">{money(totalAmount)}</span>
      </div>
    </div>
  )
}

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
