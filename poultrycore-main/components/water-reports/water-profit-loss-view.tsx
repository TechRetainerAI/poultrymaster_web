"use client"

/**
 * The water Profit & Loss statement, rendered at TWO routes.
 *
 *   chrome="report"  /water-reports/profit-loss -- one of the Reports. Keeps the
 *                    catalogue chrome and its back button.
 *   chrome="page"    /water-profit-loss -- a Money page beside Cash Flow. Not a
 *                    report, so no back button and no report card.
 *
 * One component, because the FIGURES must never differ between the two. Only the
 * frame changes. Mirrors the poultry split in poultry-profit-loss-view.tsx.
 *
 * WHAT CHANGED IN 316, AND WHAT DELIBERATELY DID NOT
 * --------------------------------------------------
 * The page used to show four totals and four flat panels. It now shows the
 * statement those totals are made of, with an entry count on every line and a
 * drilldown behind every figure.
 *
 * NET PROFIT IS UNCHANGED. spwaterreport_periodpnl is still the authority for
 * revenue, direct cost, losses and profit; 316 itemises its arithmetic rather
 * than replacing it. The poultry P&L is built the other way round -- on the
 * classification model (272) -- and porting that here would have RESTATED what
 * the company reports as profit, which is a business decision and not this
 * screen's to make.
 *
 * Every figure is clickable, and each drilldown reads the same server function
 * the figure was built from, so the two can never disagree.
 */

import { useCallback, useEffect, useMemo, useState } from "react"
import {
  Loader2, TrendingUp, Info, AlertTriangle, Search, X, Banknote, Wallet, Building2,
} from "lucide-react"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { StatementPanel, type StatementLine } from "@/components/reports/statement-sections"
// The same panel the poultry P&L uses for money that moved without being revenue
// or expense — dashed, captioned "Excluded from profit", and carrying links to
// the module each figure came from.
import { PlInfoSection } from "@/components/reports/pl-info-section"
import { Card, CardContent } from "@/components/ui/card"
import Link from "next/link"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { useFmt } from "@/lib/currency"
import { cn } from "@/lib/utils"
import { defaultReportRange } from "@/lib/date-ranges"
import { fmtDateTime } from "@/lib/utils/company-datetime"
// Water's OWN copy, not poultry's. Water counts raw materials as paid and
// delivery income as collected, so it sits closer to cash than the poultry P&L
// does -- and the examples of where the two still part company differ with it.
import {
  PROFIT_VS_CASH_TITLE, PROFIT_VS_CASH_BODY,
  CASH_NOT_PROFIT_EXAMPLES, PROFIT_NOT_CASH_EXAMPLES,
} from "@/lib/water/financial-classification"
import {
  getWaterProfitLoss, getWaterPlDetail, waterDrilldownKindFor, waterPlSectionLabel,
  type WaterProfitLossReport, type WaterPlLine, type WaterPlDetailRow, type WaterPlSection,
} from "@/lib/api/water-profit-loss"

/** The colour each band wears, and the order the statement reads in. */
const BANDS: { section: WaterPlSection; tone: "emerald" | "rose" | "amber" | "violet"; negative: boolean }[] = [
  { section: "Revenue", tone: "emerald", negative: false },
  { section: "DirectCost", tone: "rose", negative: true },
  { section: "OperatingExpense", tone: "amber", negative: true },
  { section: "OtherCost", tone: "violet", negative: true },
  { section: "Loss", tone: "violet", negative: true },
]

/**
 * What the two text columns of a drilldown hold, per kind. Written out rather
 * than guessed at per row: "Reference" means a sale number in one and a batch
 * number in another, and a column whose meaning shifts is worse than two.
 */
const DRILL_BLURB: Record<string, string> = {
  revenue: "Storefront sales and the driver returns behind delivery collections. The returns are COLLECTIONS, not sale rows — which is how the two are kept from double-counting.",
  directcost: "Raw material purchases at what was PAID for them, and approved production batches at their recorded cost.",
  expense: "Approved water expenses, and the delivery expenses recorded against driver returns.",
  loss: "Damaged or rejected stock, and cash a driver came up short.",
  financing: "Owner money and borrowing. None of it is revenue or expense — the cash moved and the profit did not.",
  capital: "What was capitalised into the asset register. Reaches profit later, through depreciation.",
  depreciation: "Depreciation posted against the asset register. It reduces profit and moves no money.",
}

export function WaterProfitLossView({ chrome = "report" }: { chrome?: "report" | "page" } = {}) {
  const gh = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [data, setData] = useState<WaterProfitLossReport | null>(null)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const [drill, setDrill] = useState<{ line: WaterPlLine; rows: WaterPlDetailRow[] } | null>(null)
  const [drillBusy, setDrillBusy] = useState(false)
  /** Free-text filter inside the drilldown. Cleared whenever a new one opens. */
  const [drillQuery, setDrillQuery] = useState("")

  const load = useCallback(async () => {
    setBusy(true); setError(null)
    try { setData(await getWaterProfitLoss({ startDate: fromDate, endDate: toDate })) }
    catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }, [fromDate, toDate])

  useEffect(() => { void load() }, [load])

  // -------------------------------------------------------------- drilldown --
  const openDrill = useCallback(async (line: WaterPlLine) => {
    const kind = waterDrilldownKindFor(line.section, line.lineKey)
    if (!kind) return
    setDrillQuery("")
    setDrill({ line, rows: [] })
    setDrillBusy(true)
    try {
      const rows = await getWaterPlDetail({
        kind, lineKey: line.lineKey, startDate: fromDate, endDate: toDate,
      })
      setDrill({ line, rows })
    } catch {
      setDrill(null)
    } finally {
      setDrillBusy(false)
    }
  }, [fromDate, toDate])

  const drillRows = useMemo(() => {
    const rows = drill?.rows ?? []
    const q = drillQuery.trim().toLowerCase()
    if (!q) return rows
    return rows.filter((r) =>
      [r.reference, r.party, r.detail].some((v) => (v ?? "").toLowerCase().includes(q)))
  }, [drill, drillQuery])

  // Shown and full totals side by side whenever a filter is on. A drilldown that
  // silently showed a subtotal would be worse than one that showed nothing.
  const drillShown = useMemo(() => drillRows.reduce((s, r) => s + r.amount, 0), [drillRows])
  const drillFull = useMemo(() => (drill?.rows ?? []).reduce((s, r) => s + r.amount, 0), [drill])
  const drillFiltered = drillQuery.trim() !== "" && drillRows.length !== (drill?.rows.length ?? 0)

  // -------------------------------------------------------------- statement --
  const lineFor = useCallback((l: WaterPlLine): StatementLine => ({
    id: l.section + ":" + l.lineKey,
    label: l.lineLabel,
    amount: l.amount,
    entryCount: l.entryCount > 0 ? l.entryCount : undefined,
    // Only where the server actually has rows to show. A chevron that opens an
    // empty dialog teaches people not to click the ones that work.
    onOpen: waterDrilldownKindFor(l.section, l.lineKey) ? () => void openDrill(l) : undefined,
  }), [openDrill])

  const bandLines = useCallback(
    (section: WaterPlSection) => (data?.lines ?? []).filter((l) => l.section === section),
    [data])

  const s = data?.summary
  const informational = (data?.lines ?? []).filter((l) => l.isInformational)

  // Split the Financing band in two. Owner money and borrowing are different
  // questions with different answers, and the panels link to different modules.
  const ownerLines = informational.filter(
    (l) => l.lineKey === "OwnerContributions" || l.lineKey === "OwnerDraws")
  const loanLines = informational.filter(
    (l) => l.lineKey === "LoansReceived" || l.lineKey === "LoanPrincipalRepaid")
  const capitalLines = informational.filter((l) => l.section === "CapitalInvestment")

  return (
    <ReportShell
      chrome={chrome}
      pageIcon={<TrendingUp className="w-5 h-5" />}
      title="Profit & Loss"
      description="Did the business make money from its operations this period?"
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      // The body is a sectioned statement, not a table, so the shell must not
      // try to card it up on a phone — the panels are already phone-shaped and
      // stack into one column of their own accord.
      mobileCards={false}
      pdf={s ? {
        title: "Profit & Loss",
        filename: "water-profit-loss",
        summaryCards: [
          { label: "Revenue", value: gh(s.totalRevenue), accent: "green" },
          { label: "Gross profit", value: gh(s.grossProfit), accent: s.grossProfit >= 0 ? "green" : "rose" },
          { label: "Operating profit", value: gh(s.operatingProfit), accent: s.operatingProfit >= 0 ? "green" : "rose" },
          { label: "Net profit", value: gh(s.netProfit), accent: s.netProfit >= 0 ? "green" : "rose" },
        ],
        columns: [{ header: "Line" }, { header: "Amount", align: "right" }],
        // The statement as printed, informational sections included but marked,
        // so a PDF reader sees the same separation the screen shows.
        rows: (data?.lines ?? []).map((l) => [
          (l.isInformational ? "(not in profit) " : "") + l.lineLabel,
          gh(l.amount),
        ]),
      } : undefined}
      summary={s ? (<>
        <SumTile label="Revenue" value={gh(s.totalRevenue)} accent="green" />
        <SumTile label="Gross profit" value={gh(s.grossProfit)}
                 accent={s.grossProfit >= 0 ? "green" : "rose"} />
        <SumTile label="Operating profit" value={gh(s.operatingProfit)}
                 accent={s.operatingProfit >= 0 ? "green" : "rose"} />
        <SumTile label="Net profit" value={gh(s.netProfit)}
                 accent={s.netProfit >= 0 ? "green" : "rose"} />
      </>) : undefined}
    >
      {!s ? (
        <p className="text-slate-500 text-sm">No P&amp;L data for this period.</p>
      ) : (<div className="space-y-4">

        {/* The sentence the four tiles above make, spelled out, so the gaps
            between them are attributable rather than mysterious. */}
        <p className="flex flex-wrap items-center gap-1 text-[11px] tabular-nums text-slate-500">
          <Info className="h-3.5 w-3.5 shrink-0" />
          <span>
            {gh(s.totalRevenue)} revenue − {gh(s.totalDirectCosts)} direct costs
            {" = "}<strong className="text-slate-700">{gh(s.grossProfit)}</strong> gross
            {" · − "}{gh(s.totalOperatingExpenses + s.totalOtherCosts)} expenses
            {" = "}<strong className="text-slate-700">{gh(s.operatingProfit)}</strong> operating
            {" · − "}{gh(s.totalLosses)} losses
            {" = "}<strong className="text-slate-900">{gh(s.netProfit)}</strong> net
            {s.netMarginPercent !== 0 && ` (${s.netMarginPercent}% margin)`}
          </span>
        </p>

        {/* The flaw 316 surfaces rather than hides. Zero on a company that has
            never bought a capital asset, which is most of them. */}
        {s.capitalInExpenses > 0 && (
          <p className="flex items-start gap-1.5 rounded-md border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900">
            <AlertTriangle className="mt-0.5 h-3.5 w-3.5 shrink-0" />
            <span>
              {gh(s.capitalInExpenses)} of capital asset purchases is being charged to this
              period&apos;s profit. A major purchase is money the company still owns and normally
              reaches profit gradually, through depreciation. The water P&amp;L counts it as an
              expense; the poultry one does not.
            </span>
          </p>
        )}

        {/* ---- the statement ------------------------------------------- */}
        <div className="grid items-start gap-3 lg:grid-cols-3">
          {BANDS.map((b) => {
            const lines = bandLines(b.section)
            if (lines.length === 0) return null
            const total = lines.reduce((sum, l) => sum + l.amount, 0)
            return (
              <StatementPanel
                key={b.section}
                title={waterPlSectionLabel(b.section)}
                totalLabel={"Total " + waterPlSectionLabel(b.section).toLowerCase()}
                total={total}
                gh={gh}
                negative={b.negative}
                tone={b.tone}
                lines={lines.map(lineFor)}
              />
            )
          })}
        </div>

        {/* ---- outside profit ------------------------------------------
            Three panels, not two, and the same three the poultry P&L shows:
            owner money and borrowing answer different questions and a single
            "Financing" card had to describe both at once.

            Each carries LINKS to the module its figures came from, because the
            question after "we took a 50,000 loan" is always "show me the loans".
            The hrefs are water's own. */}
        {informational.length > 0 && (
          <div className="space-y-2">
            <p className="flex items-start gap-1.5 text-[11px] text-slate-500">
              <Info className="mt-0.5 h-3.5 w-3.5 shrink-0" />
              <span>
                Below the line on purpose. Owner money, borrowing and capital purchases move
                cash without being revenue or expense, so none of them is inside the profit
                above — a loan received is not income, and a borehole bought is not a cost.
              </span>
            </p>
            <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
              <PlInfoSection
                icon={<Banknote className="w-4 h-4" />}
                title="Owner Contributions & Draws"
                subtitle="Excluded from profit"
                note="Money the owner put in or took out. It changes the cash in the bank and what the company owes its owner — never what it earned."
                lines={ownerLines}
                onOpen={openDrill}
                gh={gh}
                footer={
                  <div className="text-xs text-slate-600">
                    Net owner funding <strong>{gh(s.netOwnerFunding)}</strong>
                  </div>
                }
                links={[
                  { href: "/water-owner-money", label: "View Owner Money" },
                  { href: "/water-cash-flow", label: "View Cash Flow" },
                ]}
              />
              <PlInfoSection
                icon={<Wallet className="w-4 h-4" />}
                title="Loans (Financing)"
                subtitle="Excluded from profit"
                note="Borrowing received and principal repaid. Neither is income or cost — only the interest and fees on a loan reach profit, and those sit in Other Costs above."
                lines={loanLines}
                onOpen={openDrill}
                gh={gh}
                footer={
                  <div className="text-xs text-slate-600">
                    Net borrowing <strong>{gh(s.netBorrowing)}</strong>
                  </div>
                }
                links={[
                  { href: "/water-loans", label: "View Loans" },
                  { href: "/water-cash-flow", label: "View Cash Flow" },
                ]}
              />
              <PlInfoSection
                icon={<Building2 className="w-4 h-4" />}
                title="Capital Investments"
                subtitle="Excluded from immediate operating expenses"
                note="Major purchases the company still owns. Their cost reaches profit gradually, through depreciation, rather than all at once in the month they were bought."
                lines={capitalLines}
                onOpen={openDrill}
                gh={gh}
                footer={
                  <div className="text-xs text-slate-600">
                    Total invested <strong>{gh(s.totalCapitalInvestments)}</strong>
                  </div>
                }
                links={[{ href: "/water-assets", label: "View Capital Investments/Assets" }]}
              />
            </div>
          </div>
        )}

        {/* ---- why the two numbers differ ---------------------------------
            The question every owner asks once a P&L and a Cash Flow are both on
            the menu. It carries the link to the other one, because "show me"
            is the next sentence. */}
        <Card className="border-sky-200 bg-sky-50"><CardContent className="p-4 space-y-3">
          <div className="flex items-start gap-2">
            <Info className="mt-0.5 h-4 w-4 shrink-0 text-sky-700" />
            <div>
              <div className="text-sm font-semibold text-sky-900">{PROFIT_VS_CASH_TITLE}</div>
              <p className="mt-1 text-xs text-sky-900">{PROFIT_VS_CASH_BODY}</p>
            </div>
          </div>
          <div className="grid gap-3 text-xs text-sky-900 sm:grid-cols-2">
            <div>
              <div className="font-medium">Cash out that is not this period&apos;s cost</div>
              <ul className="mt-1 list-disc space-y-0.5 pl-4">
                {CASH_NOT_PROFIT_EXAMPLES.map((x) => <li key={x}>{x}</li>)}
              </ul>
            </div>
            <div>
              <div className="font-medium">Costs that did not move cash this period</div>
              <ul className="mt-1 list-disc space-y-0.5 pl-4">
                {PROFIT_NOT_CASH_EXAMPLES.map((x) => <li key={x}>{x}</li>)}
              </ul>
            </div>
          </div>
          <div className="flex flex-wrap gap-3">
            <Link href="/water-cash-flow" className="text-xs text-sky-800 underline">View Cash Flow</Link>
            <Link href="/water-expenses" className="text-xs text-sky-800 underline">View Expenses</Link>
          </div>
        </CardContent></Card>

        <p className="text-[11px] text-slate-500">
          Revenue counts storefront sales plus what drivers collected on delivery runs. Raw
          materials are counted as PAID rather than as invoiced. {s.entryCount.toLocaleString()} source
          record(s) are behind this statement — open any figure to see them.
        </p>
      </div>)}

      {/* ---- drilldown ------------------------------------------------- */}
      <Dialog open={!!drill} onOpenChange={(o) => { if (!o) setDrill(null) }}>
        <DialogContent className="w-[95vw] sm:max-w-3xl">
          <DialogHeader>
            <DialogTitle>{drill?.line.lineLabel}</DialogTitle>
            <DialogDescription>
              {drill ? DRILL_BLURB[waterDrilldownKindFor(drill.line.section, drill.line.lineKey) ?? ""] ?? "" : ""}
            </DialogDescription>
          </DialogHeader>

          {drillBusy ? (
            <div className="flex items-center justify-center gap-2 py-10 text-sm text-slate-500">
              <Loader2 className="h-4 w-4 animate-spin" /> Loading…
            </div>
          ) : (drill?.rows.length ?? 0) === 0 ? (
            <p className="py-6 text-sm text-slate-500">
              Nothing behind this figure for the selected period.
            </p>
          ) : (<>
            <div className="relative">
              <Search className="pointer-events-none absolute left-2 top-2.5 h-4 w-4 text-slate-400" />
              <Input
                className="pl-8"
                placeholder="Filter by reference, party or detail"
                value={drillQuery}
                onChange={(e) => setDrillQuery(e.target.value)}
              />
              {drillQuery && (
                <Button variant="ghost" size="sm" className="absolute right-1 top-1 h-7 px-2"
                        onClick={() => setDrillQuery("")}>
                  <X className="h-3.5 w-3.5" />
                </Button>
              )}
            </div>

            {/* Desktop: four columns. Phone: the same rows stacked, because a
                four-column table on a 390px screen is a horizontal scrollbar
                wearing a table's clothes. */}
            <div className="hidden max-h-[50vh] overflow-y-auto sm:block">
              <Table>
                <TableHeader><TableRow>
                  <TableHead>Date</TableHead>
                  <TableHead>Reference</TableHead>
                  <TableHead>Party</TableHead>
                  <TableHead>Detail</TableHead>
                  <TableHead className="text-right">Amount</TableHead>
                </TableRow></TableHeader>
                <TableBody>
                  {drillRows.map((r, i) => (
                    <TableRow key={i}>
                      <TableCell className="whitespace-nowrap text-sm">
                        {r.entryDate ? fmtDateTime(r.entryDate) : "—"}
                      </TableCell>
                      <TableCell className="text-sm font-mono">{r.reference ?? "—"}</TableCell>
                      <TableCell className="text-sm">{r.party ?? "—"}</TableCell>
                      <TableCell className="text-sm">{r.detail ?? "—"}</TableCell>
                      <TableCell className="text-right tabular-nums text-sm">{gh(r.amount)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>

            <ul className="max-h-[50vh] space-y-2 overflow-y-auto sm:hidden">
              {drillRows.map((r, i) => (
                <li key={i} className="rounded-md border border-slate-200 bg-white p-3">
                  <div className="flex items-start justify-between gap-3">
                    <span className="text-sm text-slate-900">
                      {r.entryDate ? fmtDateTime(r.entryDate) : "—"}
                    </span>
                    <span className="shrink-0 text-sm font-semibold tabular-nums">{gh(r.amount)}</span>
                  </div>
                  <p className="text-[11px] text-slate-500">
                    <span className="font-mono">{r.reference ?? "—"}</span>
                    {r.party ? ` · ${r.party}` : ""}
                  </p>
                  {r.detail && <p className="mt-0.5 text-[11px] text-slate-600">{r.detail}</p>}
                </li>
              ))}
            </ul>

            <div className="flex items-baseline justify-between border-t border-slate-200 pt-2">
              <span className="text-sm text-slate-600">
                {drillRows.length.toLocaleString()} record(s)
              </span>
              <span className="text-right">
                <span className={cn("font-semibold tabular-nums",
                                    drill && drill.line.amount < 0 && "text-red-600")}>
                  {gh(drillShown)}
                </span>
                {drillFiltered && (
                  <span className="block text-[11px] font-normal text-slate-500">
                    filtered · {gh(drillFull)} in full
                  </span>
                )}
              </span>
            </div>
          </>)}
        </DialogContent>
      </Dialog>
    </ReportShell>
  )
}
