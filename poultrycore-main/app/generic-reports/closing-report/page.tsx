"use client"

// Closing Report — one row per daily closing, matching the poultry design.
// Uses the shared ReportShell for consistent toolbar, PDF and email behaviour.

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Badge } from "@/components/ui/badge"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { getDailyClosings, type GenericDailyClosing } from "@/lib/api/generic"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"
import { cn } from "@/lib/utils"

export default function GenericClosingReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [rows, setRows] = useState<GenericDailyClosing[]>([])
  const pg = usePagination(rows)
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const all = await getDailyClosings()
      // Filter by date range
      const filtered = all.filter((c) => {
        const d = c.closingDate.slice(0, 10)
        return (!fromDate || d >= fromDate) && (!toDate || d <= toDate)
      })
      setRows(filtered)
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => {
    const approved = rows.filter((c) => c.status === "Approved")
    const income = approved.reduce((s, c) => s + (c.totalSales ?? 0), 0)
    const expenses = approved.reduce((s, c) => s + (c.totalExpenses ?? 0), 0)
    const cashIn = approved.reduce((s, c) => s + (c.totalCashIn ?? 0), 0)
    const cashOut = approved.reduce((s, c) => s + (c.totalCashOut ?? 0), 0)
    const difference = approved.reduce((s, c) => s + (c.cashDifference ?? 0), 0)
    const short = approved.filter((c) => (c.cashDifference ?? 0) !== 0).length
    return { total: rows.length, approved: approved.length, income, expenses, cashIn, cashOut, difference, short }
  }, [rows])

  const statusBadge = (s: string) => {
    const cls = s === "Approved" ? "bg-emerald-100 text-emerald-800" : s === "Submitted" ? "bg-blue-100 text-blue-800" : s === "Rejected" ? "bg-red-100 text-red-800" : "bg-slate-100 text-slate-700"
    return <Badge className={`${cls} hover:${cls}`}>{s}</Badge>
  }

  return (
    <ReportShell
      title="Closing Report"
      description="Every daily closing, with cash reconciliation and approval status."
      backHref="/generic-reports"
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      pdf={{
        title: "Closing Report",
        filename: "generic-closing-report",
        columns: [
          { header: "Date" },
          { header: "Sales", align: "right" },
          { header: "Expenses", align: "right" },
          { header: "Cash In", align: "right" },
          { header: "Cash Out", align: "right" },
          { header: "Expected", align: "right" },
          { header: "Counted", align: "right" },
          { header: "Difference", align: "right" },
          { header: "Status" },
        ],
        rows: rows.map((c) => [
          (c.closingDate ?? "").slice(0, 10),
          fmtMoney(c.totalSales ?? 0),
          fmtMoney(c.totalExpenses ?? 0),
          fmtMoney(c.totalCashIn ?? 0),
          fmtMoney(c.totalCashOut ?? 0),
          fmtMoney(c.expectedCash ?? 0),
          fmtMoney(c.actualCashCounted ?? 0),
          fmtMoney(c.cashDifference ?? 0),
          c.status,
        ]),
        summaryLines: [
          `Closings: ${totals.approved} / ${totals.total}`,
          `Income: ${fmtMoney(totals.income)}`,
          `Expenses: ${fmtMoney(totals.expenses)}`,
          `Cash difference: ${fmtMoney(totals.difference)}${totals.short > 0 ? ` (${totals.short} day(s) did not balance)` : ""}`,
        ],
      }}
      summary={<>
        <SumTile label="Closings" value={`${totals.approved} / ${totals.total}`} />
        <SumTile label="Income" value={fmtMoney(totals.income)} accent="green" />
        <SumTile label="Expenses" value={fmtMoney(totals.expenses)} accent="rose" />
        <SumTile label="Cash In" value={fmtMoney(totals.cashIn)} accent="green" />
        <SumTile
          label={totals.short > 0 ? `Cash difference (${totals.short} day${totals.short === 1 ? "" : "s"})` : "Cash difference"}
          value={fmtMoney(totals.difference)}
          accent={totals.difference !== 0 ? "rose" : undefined}
        />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead className="text-right">Sales</TableHead>
              <TableHead className="text-right">Expenses</TableHead>
              <TableHead className="text-right">Cash In</TableHead>
              <TableHead className="text-right">Cash Out</TableHead>
              <TableHead className="text-right">Expected</TableHead>
              <TableHead className="text-right">Counted</TableHead>
              <TableHead className="text-right">Difference</TableHead>
              <TableHead>Status</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={9} className="text-slate-500 text-center p-4">No closings in this period.</TableCell></TableRow>
            ) : pg.pageItems.map((c) => (
              <TableRow key={c.genericDailyClosingId}>
                <TableCell className="whitespace-nowrap font-medium">{c.closingDate.slice(0, 10)}</TableCell>
                <TableCell className="text-right tabular-nums text-emerald-700">{fmtMoney(c.totalSales)}</TableCell>
                <TableCell className="text-right tabular-nums text-red-600">{fmtMoney(c.totalExpenses)}</TableCell>
                <TableCell className="text-right tabular-nums">{fmtMoney(c.totalCashIn)}</TableCell>
                <TableCell className="text-right tabular-nums">{fmtMoney(c.totalCashOut)}</TableCell>
                <TableCell className="text-right tabular-nums">{fmtMoney(c.expectedCash)}</TableCell>
                <TableCell className="text-right tabular-nums">{fmtMoney(c.actualCashCounted)}</TableCell>
                <TableCell className={cn("text-right tabular-nums font-medium", c.cashDifference !== 0 ? "text-red-600" : "text-slate-500")}>
                  {fmtMoney(c.cashDifference)}
                </TableCell>
                <TableCell>{statusBadge(c.status)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        {rows.length > 0 && <DataPagination {...pg.paginationProps} />}
      </div>
    </ReportShell>
  )
}
