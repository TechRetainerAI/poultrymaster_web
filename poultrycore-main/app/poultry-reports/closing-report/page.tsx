"use client"

/**
 * Poultry Closing Report — the per-day closing LIST.
 *
 * Mirrors app/water-reports/closing-report/page.tsx: one row per daily closing
 * over a date range, with the submit / reopen history.
 *
 * Not to be confused with /poultry-closing-report, which is the same word for a
 * different thing: that page is a single period rolled up BY CATEGORY
 * (financial / production / inventory sections). This one lists the closings
 * themselves.
 */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { listPoultryDailyClosings, type PoultryDailyClosing } from "@/lib/api/poultry-inventory"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

export default function PoultryClosingReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [rows, setRows] = useState<PoultryDailyClosing[]>([])
  const pg = usePagination(rows)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      setRows((await listPoultryDailyClosings({ fromDate, toDate })) ?? [])
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  // Money totals count APPROVED closings only — a draft or rejected closing has
  // not been agreed, so rolling it into the period total would overstate income.
  const totals = useMemo(() => {
    const approved = rows.filter((c) => c.status === "Approved")
    return {
      total: rows.length,
      approved: approved.length,
      income: approved.reduce((s, c) => s + (c.totalIncome ?? 0), 0),
      expenses: approved.reduce((s, c) => s + (c.totalExpenses ?? 0), 0),
      cash: approved.reduce((s, c) => s + (c.cashAtHand ?? 0), 0),
    }
  }, [rows])

  const cashDiffLabel = (c: PoultryDailyClosing) => {
    const d = c.cashDifference ?? 0
    if (!d) return "—"
    return `${d > 0 ? "+" : ""}${fmtMoney(d)}`
  }

  return (
    <ReportShell
      backHref="/poultry-reports"
      title="Closing Report"
      description="Daily closings with cash counted, variance and submission history."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      pdf={{
        title: "Closing Report",
        filename: "poultry-closing-report",
        orientation: "landscape",
        columns: [
          { header: "Date" },
          { header: "Produced", align: "right" },
          { header: "Damaged", align: "right" },
          { header: "Eggs sold", align: "right" },
          { header: "Income", align: "right" },
          { header: "Expenses", align: "right" },
          { header: "Cash at hand", align: "right" },
          { header: "Counted", align: "right" },
          { header: "Variance", align: "right" },
          { header: "Status" },
          { header: "Notes" },
        ],
        rows: rows.map((c) => [
          (c.closingDate ?? "").slice(0, 10),
          (c.quantityProduced ?? 0).toLocaleString(),
          (c.quantityDamaged ?? 0).toLocaleString(),
          (c.eggsSold ?? 0).toLocaleString(),
          fmtMoney(c.totalIncome ?? 0),
          fmtMoney(c.totalExpenses ?? 0),
          fmtMoney(c.cashAtHand ?? 0),
          fmtMoney(c.actualCashCounted ?? 0),
          cashDiffLabel(c),
          c.status,
          c.rejectionReason ? `Rejected: ${c.rejectionReason}` : (c.managerNotes ?? "—"),
        ]),
        summaryLines: [
          `Closings: ${totals.approved} / ${totals.total} approved`,
          `Income: ${fmtMoney(totals.income)}`,
          `Expenses: ${fmtMoney(totals.expenses)}`,
          `Cash at hand: ${fmtMoney(totals.cash)}`,
        ],
      }}
      summary={<>
        <SumTile label="Closings" value={`${totals.approved} / ${totals.total}`} />
        <SumTile label="Income" value={fmtMoney(totals.income)} accent="green" />
        <SumTile label="Expenses" value={fmtMoney(totals.expenses)} accent="rose" />
        <SumTile label="Cash at hand" value={fmtMoney(totals.cash)} />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead className="text-right">Produced</TableHead>
              <TableHead className="text-right">Damaged</TableHead>
              <TableHead className="text-right">Eggs sold</TableHead>
              <TableHead className="text-right">Income</TableHead>
              <TableHead className="text-right">Expenses</TableHead>
              <TableHead className="text-right">Cash at hand</TableHead>
              <TableHead className="text-right">Counted</TableHead>
              <TableHead className="text-right">Variance</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Notes</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={11} className="text-slate-500 text-center p-4">No closings in this period.</TableCell></TableRow>
            ) : pg.pageItems.map((c) => (
              <TableRow key={c.poultryDailyClosingId}>
                <TableCell className="whitespace-nowrap">{(c.closingDate ?? "").slice(0, 10)}</TableCell>
                <TableCell className="text-right tabular-nums">{(c.quantityProduced ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(c.quantityDamaged ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(c.eggsSold ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(c.totalIncome ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(c.totalExpenses ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(c.cashAtHand ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(c.actualCashCounted ?? 0)}</TableCell>
                <TableCell className={`text-right tabular-nums whitespace-nowrap ${(c.cashDifference ?? 0) < 0 ? "text-rose-700" : (c.cashDifference ?? 0) > 0 ? "text-emerald-700" : ""}`}>
                  {cashDiffLabel(c)}
                </TableCell>
                <TableCell className="whitespace-nowrap">{c.status}</TableCell>
                <TableCell className="max-w-[200px] truncate text-xs text-slate-500">
                  {c.rejectionReason ? `Rejected: ${c.rejectionReason}` : (c.managerNotes ?? "—")}
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
