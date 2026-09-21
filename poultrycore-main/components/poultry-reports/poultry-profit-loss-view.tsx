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

import { Fragment, useCallback, useEffect, useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import Link from "next/link"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { ArrowLeft, AlertTriangle, Info, Loader2, ChevronRight, Wallet, Building2, Banknote, Search, X } from "lucide-react"
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
  OWNER_SECTION_RULE, BORROWING_SECTION_RULE, CAPITAL_SECTION_RULE,
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
/**
 * The colour a drilldown wears.
 *
 * Deliberately the SAME tones the section cards use, so the dialog that opens
 * is visibly the card it came from: green for money in, rose for the cost of
 * producing, amber for running the business, violet for depreciation and
 * financing, sky for money that bought an asset rather than being spent.
 *
 * That is the whole point -- four dialogs that look identical are four chances
 * to read an expense list and think you are reading revenue.
 */
const DRILL_TONES: Record<DrillKind, {
  band: string; border: string; amount: string; rail: string
  /** The rule BETWEEN records, on both the phone list and the table. */
  divide: string; row: string
  label: string
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
  /** Free-text filter inside the drilldown. Cleared whenever a new one opens. */
  const [drillQuery, setDrillQuery] = useState("")

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

  /**
   * Every cost in the period, in one figure.
   *
   * Derived here rather than read from the report, because the server does not
   * send it: the statement is built as three separate bands and their totals
   * are what reach the client. Summing the three is the same arithmetic the
   * statement itself does, so the tile cannot disagree with the cards below it.
   *
   * The assertion it has to satisfy, and the reason it is defined this way:
   *   totalRevenue - totalExpenses === netProfit
   */
  const totalExpenses =
    (data?.totalDirectCosts ?? 0)
    + (data?.totalOperatingExpenses ?? 0)
    + (data?.totalOtherCosts ?? 0)

  /**
   * The rows the drilldown is showing right now.
   *
   * Filtering changes what adds up, so the footer below reports BOTH the shown
   * total and the full one whenever a filter is on. A drilldown that silently
   * stopped matching the line it opened from is exactly the thing that makes an
   * owner distrust the report.
   */
  const drillRows = useMemo(() => {
    const rows = drill?.rows ?? []
    const q = drillQuery.trim().toLowerCase()
    if (!q) return rows
    return rows.filter((r) =>
      [r.left, r.mid, r.right, r.note].some((v) => (v ?? "").toLowerCase().includes(q)))
  }, [drill, drillQuery])

  const drillShownTotal = useMemo(
    () => drillRows.reduce((sum, r) => sum + r.amount, 0), [drillRows])
  const drillFullTotal = useMemo(
    () => (drill?.rows ?? []).reduce((sum, r) => sum + r.amount, 0), [drill])
  const drillFiltered = drillQuery.trim().length > 0

  // -------------------------------------------------------------- drilldown --
  const openDrill = useCallback(async (line: PoultryProfitLossLine) => {
    setDrillQuery("")
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
              {/* ---- the headline numbers -------------------------------- */}
              <div className="grid gap-3 grid-cols-2 lg:grid-cols-3 xl:grid-cols-5">
                {/* Each tile is NAMED for what it is, and says what was taken
                    off to get there -- "Gross profit" told an owner nothing
                    about why it sat 189,000 below Revenue. The four read down
                    as one sentence: what we sold, then what is left after each
                    kind of cost.

                    Each one shows its FORMULA rather than describing itself
                    in words. This was prose once -- "from 62,266.68 revenue /
                    minus 139,030.00 feed, medication, birds, direct labour" --
                    and it carried the same facts, but it had to be read as a
                    sentence before it could be checked as a sum. See Formula
                    below for the shape and why the terms carry no currency
                    symbol.

                    Every term is the same total the matching section card
                    below prints, so a tile is checkable on its own and the
                    card is where you go to see what is inside one. The terms
                    chain: each tile starts from the one before it, which is
                    what makes the row read as a statement rather than five
                    unrelated figures.

                    The long lists of what is IN each cost -- feed, medication,
                    birds, direct labour -- moved to the tooltip. The formula
                    needs the name of the term, not its contents, and the two
                    together were what made the old hint a paragraph.

                    The accounting term stays on the tile as the `term` line
                    rather than being dropped. It is what an accountant, a bank
                    or the exported PDF will ask for, and it is what the water
                    reports still call the same figures. */}
                <Kpi label="Total revenue" value={gh(data.totalRevenue)} tone="slate"
                     term="Everything sold this period"
                     tip="Eggs, birds, manure and feed sold in this period, whether or not the customer has paid yet. Money a customer still owes you is revenue; money they paid for a sale in an earlier period is not."
                     hint="Eggs, birds, manure and feed sold" />
                {/* TOTAL EXPENSES means EVERYTHING taken off -- the direct
                    cost of producing, the cost of running the place, and
                    depreciation and financing. Defined that way on purpose:
                    it is what an owner means by the phrase, it includes the
                    feed, and it makes the obvious equation true --
                    revenue MINUS this IS net profit. Defining it as operating
                    costs only would have left the feed out and quietly broken
                    that sum for anyone who tried it. */}
                <Kpi label="Total expenses"
                     value={gh(totalExpenses)}
                     term="Everything taken off revenue"
                     tip="Every cost in this period: the direct cost of what you produced (feed, medication, birds, direct labour), the cost of running the business (payroll, utilities, transport, repairs, admin) and depreciation plus the interest and fees on borrowing. Revenue minus this figure is Net profit. It does NOT include owner draws, loan principal or capital purchases — those are money moving, not costs."
                     hint={<Formula op="+" gh={gh} terms={[
                       { label: "Direct costs", value: data.totalDirectCosts, tone: "direct" },
                       { label: "Operating expenses", value: data.totalOperatingExpenses, tone: "operating" },
                       { label: "Depreciation & financing", value: data.totalOtherCosts, tone: "other" },
                     ]} />}
                     tone="red" />
                <Kpi label="Gross profit"
                     value={gh(data.grossProfit)}
                     term={data.grossMarginPercent != null
                       ? `${data.grossMarginPercent}% of sales`
                       : "No sales this period"}
                     tip="What the FARMING made, before any of the cost of running a business. Revenue minus the direct cost of producing what you sold: feed, medication, the birds themselves and direct labour. Negative here means the flock cost more to feed than its output sold for."
                     hint={<Formula op="−" gh={gh} terms={[
                       { label: "Revenue", value: data.totalRevenue, tone: "revenue" },
                       { label: "Direct costs", value: data.totalDirectCosts, tone: "direct" },
                     ]} />}
                     tone={data.grossProfit >= 0 ? "emerald" : "red"} />
                <Kpi label="Operating profit"
                     value={gh(data.operatingProfit)}
                     term="Before depreciation and financing"
                     tip="What the BUSINESS made. Gross profit minus the cost of running it: payroll, utilities, transport, repairs, admin and marketing. It stops short of wear on assets and the cost of borrowing, so it answers whether the operation itself pays for itself."
                     hint={<Formula op="−" gh={gh} terms={[
                       { label: "Gross profit", value: data.grossProfit, tone: "subtotal" },
                       { label: "Operating expenses", value: data.totalOperatingExpenses, tone: "operating" },
                     ]} />}
                     tone={data.operatingProfit >= 0 ? "emerald" : "red"} />
                {/* Named for what it IS on the day, not always "profit": a farm
                    reading "Net profit -184,533" has to do a double take. */}
                <Kpi label={data.netProfit < 0 ? "Net loss" : "Net profit"}
                     value={gh(data.netProfit)}
                     term={data.netMarginPercent != null
                       ? `${data.netMarginPercent}% of sales`
                       : data.status}
                     tip="What is actually left. Operating profit minus depreciation — the wear on buildings, machines and equipment — and the interest and fees on borrowing. Owner money, loan principal and capital purchases are NOT in this figure; they are money moving, not profit, and they are shown separately below."
                     hint={<Formula op="−" gh={gh} terms={[
                       { label: "Operating profit", value: data.operatingProfit, tone: "subtotal" },
                       { label: "Depreciation & financing", value: data.totalOtherCosts, tone: "other" },
                     ]} />}
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
                  FOUR EQUAL CARDS, 2x2. This used to be three column STACKS,
                  with Revenue and Depreciation sharing the first column so the
                  two short ones sat on top of each other rather than each
                  leaving a hole beside a tall neighbour. That packed better and
                  read worse: four cards at four different sizes look like four
                  different KINDS of thing, when they are four bands of one
                  statement.

                  ALL FOUR ON ONE ROW from xl, so the statement reads left to
                  right in the order it is calculated: what came in, then each
                  band of cost. Two-up at md and one column on a phone, where
                  four columns would be four slivers.

                  Three parts, all needed:
                    xl:grid-cols-4     equal widths, one row
                    auto-rows-fr       every row as tall as the tallest, which
                                       still matters at the 2-up step
                    h-full per card    the card fills its stretched cell; the
                                       cell stretching is not enough on its own
                  `items-start` had to go: it is the opposite instruction.

                  The card body is a flex column with the line list taking the
                  slack, so every TOTAL sits on the foot of its card and the four
                  line up. Without that the cards are the same height but their
                  totals are not, which is what made them look uneven.

                  One column on a phone, in statement order, so `order` and the
                  `contents` trick that positioned the old stacks are both gone.

                  The running subtotals -- Gross, Operating and Net Profit -- are
                  NOT repeated inside the cards. They are the tiles at the top of
                  the page, and a figure printed twice invites a reader to add it
                  twice. */}
              <div className="grid gap-3 auto-rows-fr md:grid-cols-2 xl:grid-cols-4">
                <SectionCard
                  className="h-full"
                  tone="emerald" title="Revenue" lines={bySection("Revenue")}
                  totalLabel="Total Revenue" totalAmount={data.totalRevenue}
                  onOpen={openDrill} gh={gh}
                />
                <SectionCard
                  className="h-full"
                  tone="rose" negative title="Direct Production Costs" lines={bySection("DirectCost")}
                  totalLabel="Total Direct Production Costs" totalAmount={data.totalDirectCosts}
                  onOpen={openDrill} gh={gh}
                />
                <SectionCard
                  className="h-full"
                  tone="amber" negative title="Operating Expenses" lines={bySection("OperatingExpense")}
                  totalLabel="Total Operating Expenses" totalAmount={data.totalOperatingExpenses}
                  onOpen={openDrill} gh={gh}
                />
                <SectionCard
                  className="h-full"
                  tone="violet" negative title="Depreciation & Financing Costs" lines={bySection("OtherCost")}
                  totalLabel="Total Depreciation & Financing" totalAmount={data.totalOtherCosts}
                  onOpen={openDrill} gh={gh}
                />
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
                  note={noteWithRule(OWNER_SECTION_NOTE, OWNER_SECTION_RULE)}
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
                  note={noteWithRule(BORROWING_SECTION_NOTE, BORROWING_SECTION_RULE)}
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
                  note={noteWithRule(CAPITAL_SECTION_NOTE, CAPITAL_SECTION_RULE)}
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
              {/* The band is the demarcation. It carries the section's own
                  colour, so the dialog reads as the card it opened from rather
                  than as one more white box of numbers. Bled to the dialog's
                  edges with -m-6, cancelling DialogContent's p-6. */}
              <DialogHeader
                className={cn(
                  "-m-6 mb-0 space-y-1 border-b p-6",
                  drill ? DRILL_TONES[drill.kind].band : "",
                  drill ? DRILL_TONES[drill.kind].border : "",
                )}
              >
                <DialogTitle className="flex flex-wrap items-baseline gap-x-2 gap-y-1 pr-6 text-left">
                  <span className="min-w-0 break-words">{drill?.line.lineLabel}</span>
                  {drill && (
                    <Badge variant="outline"
                           className={cn("border-current/30 bg-white/60 text-[10px] font-medium",
                                         DRILL_TONES[drill.kind].amount)}>
                      {DRILL_TONES[drill.kind].label}
                    </Badge>
                  )}
                  <span className={cn("ml-auto text-sm font-semibold tabular-nums",
                                      drill ? DRILL_TONES[drill.kind].amount : "text-slate-500")}>
                    {gh(drill?.line.amount ?? 0)}
                  </span>
                </DialogTitle>
                {/* Say what the list IS and over what period, rather than
                    leaving the reader to infer both from the rows. */}
                <p className="text-left text-xs opacity-80">
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
                  {/* Worth having once a line has more than a screenful behind
                      it -- "which of these 60 expenses was the vet" is the
                      question a drilldown exists to answer, and scrolling is a
                      poor way to ask it. Matches on every column, including the
                      note, because the reader does not know which one holds the
                      word they remember. */}
                  <div className="relative">
                    <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                    <Input
                      value={drillQuery}
                      onChange={(e) => setDrillQuery(e.target.value)}
                      placeholder={`Filter these ${drill!.rows.length} records…`}
                      className="h-9 pl-8 pr-8"
                    />
                    {drillFiltered && (
                      <button
                        type="button"
                        onClick={() => setDrillQuery("")}
                        className="absolute right-2 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600"
                        aria-label="Clear filter"
                      >
                        <X className="h-4 w-4" />
                      </button>
                    )}
                  </div>

                  {drillFiltered && drillRows.length === 0 && (
                    <p className="py-6 text-center text-sm text-slate-500">
                      Nothing here matches “{drillQuery}”.
                    </p>
                  )}

                  <div className="-mx-2 max-h-[55vh] overflow-y-auto px-2 sm:mx-0 sm:max-h-[60vh] sm:px-0">
                    {/* Phone: one record per block, each field labelled -- a
                        column heading a reader has scrolled past is no heading
                        at all. */}
                    {/* The rule between records carries the section's colour
                        too, so the list is demarcated all the way down rather
                        than only at the top where the band is. */}
                    <ul className={cn("divide-y sm:hidden", DRILL_TONES[drill!.kind].divide)}>
                      {drillRows.map((r, i) => (
                        // The rail repeats the section's colour down the list,
                        // so a screenshot of three records still says which
                        // kind of money they were.
                        <li key={i} className={cn("border-l-2 py-3 pl-2",
                                                  DRILL_TONES[drill!.kind].rail)}>
                          <div className="flex items-baseline justify-between gap-3">
                            <span className="text-xs font-medium uppercase tracking-wide text-slate-500">
                              {drillDate(r.left)}
                            </span>
                            <span className={cn("shrink-0 text-sm font-semibold tabular-nums",
                                                DRILL_TONES[drill!.kind].amount)}>
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
                        <TableRow className={cn(DRILL_TONES[drill!.kind].row)}>
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
                        {drillRows.map((r, i) => (
                          <TableRow key={i}
                                    className={cn("[&>td]:align-top", DRILL_TONES[drill!.kind].row)}>
                            <TableCell className="whitespace-nowrap text-sm text-slate-500">{drillDate(r.left)}</TableCell>
                            {/* whitespace-normal: TableCell ships whitespace-nowrap,
                                which is what was driving a long description straight
                                through the next column. */}
                            <TableCell className="text-sm break-words whitespace-normal">
                              {r.mid}
                              {r.note && <div className="text-[11px] text-slate-500">{r.note}</div>}
                            </TableCell>
                            <TableCell className="text-sm text-slate-500 break-words whitespace-normal">{r.right}</TableCell>
                            <TableCell className={cn("text-right text-sm font-medium tabular-nums",
                                                     DRILL_TONES[drill!.kind].amount)}>{gh(r.amount)}</TableCell>
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
                  <div className={cn("flex items-center justify-between gap-4 border-t pt-3 text-sm",
                                     drill ? DRILL_TONES[drill.kind].border : "")}>
                    <span className="text-slate-500">
                      {drillFiltered
                        ? `${drillRows.length} of ${drill!.rows.length} records`
                        : `${drill!.rows.length} ${drill!.rows.length === 1 ? "record" : "records"}`}
                    </span>
                    {/* When a filter is on, the shown total is NOT the line's
                        total, and saying so is the whole reason both are here.
                        A drilldown that quietly stopped adding up to the figure
                        it opened from is what makes an owner stop believing the
                        report. */}
                    <span className="text-right">
                      <span className={cn("font-semibold tabular-nums",
                                          drill ? DRILL_TONES[drill.kind].amount : "")}>
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

/**
 * What colour a term in a formula wears.
 *
 * NOT decoration, and not a per-tile accent: it is the SAME colour the section
 * card holding that figure wears further down the page -- rose for the direct
 * cost of producing, amber for the cost of running the place, violet for
 * depreciation and financing, emerald for money in. So "Direct costs
 * 139,030.00" in the Gross profit formula is visibly the rose card below, and
 * an owner who wants to know what is inside the number knows where to look
 * without being told.
 *
 * A term carried forward from the previous tile -- Gross profit, Operating
 * profit -- is slate, because it is not a band of the statement; it is the
 * answer the tile before it already gave. Colouring it by its sign was the
 * alternative and it misleads: a red Gross profit term sitting beside rose
 * Direct costs reads as another cost.
 *
 * 700 shades, both lines. These sit at 11px on white and a lighter tone would
 * be decoration the reader cannot actually read.
 */
const FORMULA_TONES = {
  revenue:   "text-emerald-700",
  direct:    "text-rose-700",
  operating: "text-amber-700",
  other:     "text-violet-700",
  subtotal:  "text-slate-700",
} as const

/**
 * A tile's arithmetic, written as the formula it is.
 *
 * It used to be prose -- "from GH₵ 62,266.68 revenue / minus GH₵ 139,030.00
 * feed, medication, birds, direct labour" -- which says the same thing but has
 * to be read as a sentence before it can be checked as a sum. Two lines that
 * line up term for term can be checked at a glance, and they are what an owner
 * means when they ask how a figure was arrived at:
 *
 *     Revenue − Direct costs
 *     62,266.68 − 139,030.00
 *
 * The names go ABOVE the numbers, because the names are the formula and the
 * numbers are this period's instance of it. The result is still not printed:
 * it is the value on the tile, which the reader is already looking at.
 *
 * NO CURRENCY SYMBOL on the terms. Three "GH₵" in one line is exactly the
 * clutter that stops it reading as an equation, and the tile's own value
 * carries the symbol two lines up.
 *
 * A NEGATIVE TERM IS PARENTHESISED, sign and all: "(−76,763.32) − 7,660.00".
 * Accounting would drop the sign and let the brackets carry it, but these tiles
 * exist for readers who do not read accounting, and "76,763.32 − 7,660.00"
 * against a tile showing −84,423.32 looks like an error in the report.
 */
function Formula({ op, terms, gh }: {
  op: "+" | "−"
  terms: { label: string; value: number; tone: keyof typeof FORMULA_TONES }[]
  gh: (n: number, opts?: { showSymbol?: boolean }) => string
}) {
  const money = (n: number) => {
    const t = gh(n, { showSymbol: false })
    return n < 0 ? `(${t})` : t
  }
  // One row of the formula. Built twice from the same terms -- names, then
  // numbers -- so the two lines cannot fall out of step with each other.
  const row = (cell: (t: (typeof terms)[number]) => string, className?: string) => (
    <div className={className}>
      {terms.map((t, i) => (
        <Fragment key={t.label}>
          {/* The operator stays grey. It is punctuation between the terms, not
              a term, and colouring it would break the run of one colour that
              ties a name to its number. */}
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
  label: string; value: string
  /**
   * The plain-English meaning, on hover.
   *
   * The LABEL is now the accounting term, because that is what a bank, an
   * accountant or an exported PDF asks for. What it means moves here rather
   * than being dropped -- but note the tile still prints its own arithmetic
   * underneath, because a tooltip does not exist on a phone and "how did we
   * get this" is a question that has to be answerable without a mouse.
   */
  tip?: string
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
    <div className={cn("flex flex-col overflow-hidden rounded-xl border bg-white shadow-sm", t.border, className)}>
      <div className={cn("px-3 py-2 text-[11px] font-semibold uppercase tracking-wide", t.head)}>
        {title}
      </div>

      {lines.length === 0 ? (
        <p className="flex-1 px-4 py-4 text-sm text-slate-400">None this period</p>
      ) : (
        <ul className="flex-1 divide-y divide-slate-100">
          {lines.map((l) => (
            <li key={l.section + l.lineKey}>
              <button
                type="button"
                onClick={() => onOpen(l)}
                className="flex w-full items-center gap-1.5 px-3 py-2 text-left transition-colors hover:bg-slate-50"
              >
                {/* No truncation: a statement line that reads "Medication &
                    Vete..." on a phone has hidden the very thing the reader
                    came for. It wraps instead and the row grows. */}
                <span className="inline-flex min-w-0 items-center gap-1 text-sm text-slate-900">
                  <span>{l.lineLabel}</span>
                  <ChevronRight className="h-3.5 w-3.5 shrink-0 text-slate-400" />
                </span>
                {/* Just the count once the cards are a quarter of the width:
                    "20 entries" and the amount cannot both fit, and the amount
                    is the one nobody came here to lose. The full wording stays
                    on hover and at the wider steps. */}
                {l.entryCount > 0 && (
                  <span className="shrink-0 rounded-full bg-slate-100 px-1.5 py-0.5 text-[11px] text-slate-500"
                        title={`${l.entryCount} ${l.entryCount === 1 ? "entry" : "entries"}`}>
                    <span className="xl:hidden">
                      {l.entryCount} {l.entryCount === 1 ? "entry" : "entries"}
                    </span>
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

/**
 * Highlight the one clause in an info-card note that states the rule.
 *
 * These three cards all say the same difficult thing — this money moved but it
 * is not profit — and in a grey paragraph the sentence that actually answers
 * "why is this not in my expenses?" reads like the rest of the prose. Coloured,
 * an owner can find it without reading the paragraph.
 *
 * Sky, matching the "Profit is not cash" explainer below, because it is the
 * same point made twice: this is an explanation, not a warning, so it must not
 * borrow the amber/rose the report uses for money it wants you to look at.
 *
 * The clause is passed in rather than matched by hand, and comes from the same
 * constant the note is built from, so the split cannot silently miss. If a note
 * is ever reworded without its rule, this falls back to plain text.
 */
function noteWithRule(note: string, rule: string): React.ReactNode {
  const at = note.indexOf(rule)
  if (at < 0) return note
  return (
    <>
      {note.slice(0, at)}
      <mark className="box-decoration-clone rounded bg-sky-100 px-1 py-0.5 font-medium text-sky-900">
        {rule}
      </mark>
      {note.slice(at + rule.length)}
    </>
  )
}

function InfoSection({ icon, title, subtitle, note, lines, onOpen, gh, footer, links }: {
  icon: React.ReactNode; title: string; subtitle: string; note: React.ReactNode
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
