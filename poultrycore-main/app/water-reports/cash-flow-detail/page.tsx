"use client"

/**
 * Water Cash Flow Detail — the Water twin of /poultry/reports/cash-flow-detail.
 *
 * Cash Movement says WHAT moved. This says what it was FOR, and how the period
 * compares with the one before it. The categories come from
 * spwatercashflow_detail (migration 236), which joins waterexpensecategories, so
 * "Expense" is not one grey slice the way the raw ledger would give it.
 *
 * Reads GET /api/Water/cash-flow twice — this period and the one immediately
 * before, same length — because "better or worse than last time" is the question
 * a set of totals on its own cannot answer.
 *
 * The sentences under Analysis come from lib/cash/cash-flow-analysis, the same
 * pure, unit-tested function the poultry report and both Cash Flow pages use.
 * They make claims about somebody's money, so they are tested rather than
 * trusted, and there is exactly one copy of them.
 */

import { useCallback, useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { DataPagination } from "@/components/ui/data-pagination"
import { CashAnalysisPanel, CashBreakdownPanel } from "@/components/reports/cash-report-sections"
import { usePagination } from "@/hooks/use-pagination"
import { getCashFlow, flowGroupLabel, type CashFlowRow, type CashFlowSummary } from "@/lib/api/cash-flow"
import { cashFlowBuckets, categoryLabel, withRunningBalance } from "@/lib/cash/cash-flow"
import { buildCashFlowAnalysis } from "@/lib/cash/cash-flow-analysis"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

const EMPTY_SUMMARY: CashFlowSummary = {
  moneyIn: 0, moneyOut: 0, netCashFlow: 0, openingCash: 0, closingCash: 0,
  operatingIn: 0, operatingOut: 0, financingIn: 0, financingOut: 0, movementCount: 0,
}

/** The document behind a row, so a figure can be traced back to what caused it. */
function reference(r: CashFlowRow): string {
  if (r.sourceId == null) return "—"
  switch (r.rowSource) {
    case "Receipt": return `Payment · sale #${r.sourceId}`
    case "SaleResidual": return `Sale #${r.sourceId}`
    case "Expense": return `Expense #${r.sourceId}`
    case "Adjustment": return `Adjustment #${r.sourceId}`
    default: return `#${r.sourceId}`
  }
}

export default function WaterCashFlowDetailReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT = defaultReportRange()
  const [fromDate, setFromDate] = useState(DEFAULT.from)
  const [toDate, setToDate] = useState(DEFAULT.to)
  const [rows, setRows] = useState<CashFlowRow[]>([])
  const [summary, setSummary] = useState<CashFlowSummary>(EMPTY_SUMMARY)
  const [prevSummary, setPrevSummary] = useState<CashFlowSummary>(EMPTY_SUMMARY)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // The window immediately before this one, same length, so "better than last
  // period" is like-for-like rather than a calendar-month assumption.
  const previousRange = useMemo(() => {
    const from = new Date(fromDate)
    const to = new Date(toDate)
    const days = Math.max(1, Math.round((to.getTime() - from.getTime()) / 86_400_000) + 1)
    const prevTo = new Date(from.getTime() - 86_400_000)
    const prevFrom = new Date(prevTo.getTime() - (days - 1) * 86_400_000)
    const iso = (d: Date) => d.toISOString().split("T")[0]
    return { from: iso(prevFrom), to: iso(prevTo), days }
  }, [fromDate, toDate])

  const load = useCallback(async () => {
    setBusy(true); setError(null)
    // allSettled: a missing comparison period is a degraded report, not a failed
    // one. The period's own figures are what the page exists to show.
    const [cur, prev] = await Promise.allSettled([
      getCashFlow("Water", { fromDate, toDate }),
      getCashFlow("Water", { fromDate: previousRange.from, toDate: previousRange.to }),
    ])

    if (cur.status === "fulfilled") {
      setRows(cur.value.rows)
      setSummary(cur.value.summary)
    } else {
      setError(cur.reason?.message ?? String(cur.reason))
      setRows([]); setSummary(EMPTY_SUMMARY)
    }
    setPrevSummary(prev.status === "fulfilled" ? prev.value.summary : EMPTY_SUMMARY)
    setBusy(false)
  }, [fromDate, toDate, previousRange.from, previousRange.to])

  useEffect(() => { void load() }, [load])

  const inBuckets = useMemo(() => cashFlowBuckets(rows, "in"), [rows])
  const outBuckets = useMemo(() => cashFlowBuckets(rows, "out"), [rows])

  const fromTrading = useMemo(
    () => Math.round((summary.operatingIn - summary.operatingOut) * 100) / 100,
    [summary],
  )

  const analysis = useMemo(
    () => buildCashFlowAnalysis({
      moneyIn: summary.moneyIn,
      moneyOut: summary.moneyOut,
      netCashFlow: summary.netCashFlow,
      operatingIn: summary.operatingIn,
      operatingOut: summary.operatingOut,
      financingIn: summary.financingIn,
      financingOut: summary.financingOut,
      cashAtHand: summary.closingCash,
      offLedgerIn: 0, offLedgerOut: 0, transferVolume: 0,
      movementCount: summary.movementCount,
      daysInPeriod: previousRange.days,
      previousMoneyIn: prevSummary.moneyIn,
      previousMoneyOut: prevSummary.moneyOut,
      previousNetCashFlow: prevSummary.netCashFlow,
      moneyInByCategory: inBuckets.map((b) => ({ label: b.label, amount: b.amount, sharePercent: b.percent })),
      moneyOutByCategory: outBuckets.map((b) => ({ label: b.label, amount: b.amount, sharePercent: b.percent })),
    }, fmtMoney),
    [summary, prevSummary, previousRange.days, inBuckets, outBuckets, fmtMoney],
  )

  // Newest first for reading; the running balance was accumulated oldest-first
  // and travels with its row, so reversing here does not disturb it.
  const visible = useMemo(
    () => withRunningBalance(rows, summary.openingCash).reverse(),
    [rows, summary.openingCash],
  )
  const pg = usePagination(visible)

  const pdfRows = useMemo(
    () => visible.map((r) => [
      (r.transactionDate ?? "").slice(0, 10),
      flowGroupLabel(r.flowGroup),
      categoryLabel(r.category),
      reference(r),
      r.description ?? "—",
      r.amount > 0 ? fmtMoney(r.amount) : "—",
      r.amount < 0 ? fmtMoney(-r.amount) : "—",
      fmtMoney(r.running),
    ]),
    [visible, fmtMoney],
  )

  return (
    <ReportShell
      title="Cash Flow Detail"
      description="Where cash came from, what it went on, and how the period compares with the one before it."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      pdf={{
        title: "Water Cash Flow Detail",
        filename: "water-cash-flow-detail",
        orientation: "landscape",
        summaryCards: [
          { label: "Opening cash", value: fmtMoney(summary.openingCash), note: "Start of period" },
          { label: "Money in", value: fmtMoney(summary.moneyIn), accent: "green" },
          { label: "Money out", value: fmtMoney(summary.moneyOut), accent: "rose" },
          { label: "Closing cash", value: fmtMoney(summary.closingCash), note: "Not your account balances" },
          { label: "From trading", value: fmtMoney(fromTrading), accent: fromTrading >= 0 ? "green" : "rose", note: "Operating only, excludes capital" },
        ],
        columns: [
          { header: "Date" }, { header: "Type" }, { header: "Category" }, { header: "Reference" },
          { header: "Description" },
          { header: "In", align: "right" }, { header: "Out", align: "right" },
          { header: "Running cash", align: "right" },
        ],
        rows: pdfRows,
      }}
      summary={<>
        <SumTile label="Opening cash" value={fmtMoney(summary.openingCash)} />
        <SumTile label="Money in" value={fmtMoney(summary.moneyIn)} accent="green" />
        <SumTile label="Money out" value={fmtMoney(summary.moneyOut)} accent="rose" />
        <SumTile label="Closing cash" value={fmtMoney(summary.closingCash)} accent="indigo" />
        <SumTile label="From trading" value={fmtMoney(fromTrading)} accent={fromTrading >= 0 ? "green" : "rose"} />
      </>}
    >
      <p className="mb-3 rounded-md border border-slate-200 bg-slate-50 p-2 text-xs leading-snug text-slate-600">
        These figures come from sales, payments, approved expenses and capital records, not from cash
        account balances. Closing cash is not expected to match what the accounts hold — comparing
        the two is what reconciliation is for. <b>From trading</b> excludes capital, so it is what the
        business itself earned rather than what owners and lenders put in.
      </p>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 print:grid-cols-2">
        <CashBreakdownPanel
          title="Money in by source"
          accent="green"
          total={fmtMoney(summary.moneyIn)}
          emptyText="No money came in during this period."
          items={inBuckets.map((b) => ({
            key: b.key, label: b.label, value: fmtMoney(b.amount), percent: b.percent,
          }))}
        />
        <CashBreakdownPanel
          title="Money out by category"
          accent="rose"
          total={fmtMoney(summary.moneyOut)}
          emptyText="Nothing was paid out during this period."
          items={outBuckets.map((b) => ({
            key: b.key, label: b.label, value: fmtMoney(b.amount), percent: b.percent,
          }))}
        />
      </div>

      <div className="mt-4">
        <CashAnalysisPanel title="Analysis" items={analysis} />
      </div>

      <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mt-6 mb-2">
        Every movement
      </h2>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Type</TableHead>
              <TableHead>Category</TableHead>
              <TableHead>Reference</TableHead>
              <TableHead>Description</TableHead>
              <TableHead className="text-right">In</TableHead>
              <TableHead className="text-right">Out</TableHead>
              <TableHead className="text-right">Running cash</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {visible.length === 0 ? (
              <TableRow>
                <TableCell colSpan={8} className="text-slate-500 text-center p-4">
                  No cash moved in this period.
                </TableCell>
              </TableRow>
            ) : pg.pageItems.map((r) => (
              <TableRow key={`${r.rowSource}-${r.id}`}>
                <TableCell className="whitespace-nowrap">{(r.transactionDate ?? "").slice(0, 10)}</TableCell>
                <TableCell className="whitespace-nowrap">{flowGroupLabel(r.flowGroup)}</TableCell>
                <TableCell>{categoryLabel(r.category)}</TableCell>
                <TableCell className="whitespace-nowrap">{reference(r)}</TableCell>
                <TableCell className="max-w-[260px] truncate" title={r.description ?? ""}>{r.description ?? "—"}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap text-emerald-700">
                  {r.amount > 0 ? fmtMoney(r.amount) : "—"}
                </TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap text-rose-700">
                  {r.amount < 0 ? fmtMoney(-r.amount) : "—"}
                </TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap font-medium">
                  {fmtMoney(r.running)}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <DataPagination {...pg.paginationProps} />
    </ReportShell>
  )
}
