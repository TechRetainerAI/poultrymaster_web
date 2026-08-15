"use client"

// Poultry Closing Report — one row per daily closing.
//
// Ported from the Water side (/water-reports/closing-report) and built on the
// same ReportShell, so the toolbar, PDF letterhead and email-a-report behaviour
// are identical across both company types. `backHref` has to be passed
// explicitly: the shell defaults to /water-reports.
//
// This is the sibling of /poultry-closing-report, which totals a whole PERIOD
// into categories. That one answers "how did the last month go"; this one
// answers "what happened on each day, and did the cash reconcile" — which is why
// it carries counted cash and the difference, the two columns the by-category
// view has nowhere to put.

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { DataPagination } from "@/components/ui/data-pagination"
import { usePagination } from "@/hooks/use-pagination"
import { listPoultryDailyClosings, type PoultryDailyClosing } from "@/lib/api/poultry-inventory"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"
import { cn } from "@/lib/utils"

export default function PoultryClosingReportDailyPage() {
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
      const all = await listPoultryDailyClosings({ fromDate, toDate })
      setRows(all ?? [])
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => {
    // Money is totalled over APPROVED closings only — a draft or rejected day is
    // not a figure anyone should be adding up.
    const approved = rows.filter((c) => c.status === "Approved")
    const income = approved.reduce((s, c) => s + (c.totalIncome ?? 0), 0)
    const expenses = approved.reduce((s, c) => s + (c.totalExpenses ?? 0), 0)
    const cash = approved.reduce((s, c) => s + (c.cashAtHand ?? 0), 0)
    const difference = approved.reduce((s, c) => s + (c.cashDifference ?? 0), 0)
    const short = approved.filter((c) => (c.cashDifference ?? 0) !== 0).length
    return { total: rows.length, approved: approved.length, income, expenses, cash, difference, short }
  }, [rows])

  const noteFor = (c: PoultryDailyClosing) =>
    c.rejectionReason ? `Rejected: ${c.rejectionReason}` : (c.managerNotes || "—")

  return (
    <ReportShell
      title="Closing Report"
      description="Every daily closing, with cash reconciliation and approval status."
      backHref="/poultry/reports"
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      // No onRefresh: the shell declares the prop but never uses it, and changing
      // either date already refetches. Water's copy passes it and it does nothing.
      pdf={{
        title: "Closing Report",
        filename: "poultry-closing-report",
        columns: [
          { header: "Date" },
          { header: "Produced", align: "right" },
          { header: "Sold", align: "right" },
          { header: "Income", align: "right" },
          { header: "Expenses", align: "right" },
          { header: "Cash at hand", align: "right" },
          { header: "Counted", align: "right" },
          { header: "Difference", align: "right" },
          { header: "Status" },
          { header: "Notes" },
        ],
        rows: rows.map((c) => [
          (c.closingDate ?? "").slice(0, 10),
          (c.quantityProduced ?? 0).toLocaleString(),
          (c.eggsSold ?? 0).toLocaleString(),
          fmtMoney(c.totalIncome ?? 0),
          fmtMoney(c.totalExpenses ?? 0),
          fmtMoney(c.cashAtHand ?? 0),
          fmtMoney(c.actualCashCounted ?? 0),
          fmtMoney(c.cashDifference ?? 0),
          c.status,
          noteFor(c),
        ]),
        summaryLines: [
          `Closings: ${totals.approved} / ${totals.total}`,
          `Income: ${fmtMoney(totals.income)}`,
          `Expenses: ${fmtMoney(totals.expenses)}`,
          `Cash at hand: ${fmtMoney(totals.cash)}`,
          `Cash difference: ${fmtMoney(totals.difference)}${totals.short > 0 ? ` (${totals.short} day(s) did not balance)` : ""}`,
        ],
      }}
      summary={<>
        <SumTile label="Closings" value={`${totals.approved} / ${totals.total}`} />
        <SumTile label="Income" value={fmtMoney(totals.income)} accent="green" />
        <SumTile label="Expenses" value={fmtMoney(totals.expenses)} accent="rose" />
        <SumTile label="Cash at hand" value={fmtMoney(totals.cash)} />
        {/* The reason to open this report rather than the by-category one: any
            non-zero difference is a day where the counted cash did not match. */}
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
              <TableHead className="text-right">Produced</TableHead>
              <TableHead className="text-right">Sold</TableHead>
              <TableHead className="text-right">Income</TableHead>
              <TableHead className="text-right">Expenses</TableHead>
              <TableHead className="text-right">Cash at hand</TableHead>
              <TableHead className="text-right">Counted</TableHead>
              <TableHead className="text-right">Difference</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Notes</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={10} className="text-slate-500 text-center p-4">No closings in this period.</TableCell></TableRow>
            ) : pg.pageItems.map((c) => {
              const diff = c.cashDifference ?? 0
              return (
                <TableRow key={c.poultryDailyClosingId}>
                  <TableCell className="whitespace-nowrap">{(c.closingDate ?? "").slice(0, 10)}</TableCell>
                  <TableCell className="text-right tabular-nums">{(c.quantityProduced ?? 0).toLocaleString()}</TableCell>
                  <TableCell className="text-right tabular-nums">{(c.eggsSold ?? 0).toLocaleString()}</TableCell>
                  <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(c.totalIncome ?? 0)}</TableCell>
                  <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(c.totalExpenses ?? 0)}</TableCell>
                  <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(c.cashAtHand ?? 0)}</TableCell>
                  <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(c.actualCashCounted ?? 0)}</TableCell>
                  <TableCell className={cn(
                    "text-right tabular-nums whitespace-nowrap",
                    diff !== 0 && "text-rose-700 font-medium"
                  )}>
                    {fmtMoney(diff)}
                  </TableCell>
                  <TableCell>
                    <span className={cn(
                      "text-xs px-2 py-0.5 rounded",
                      c.status === "Approved" ? "bg-green-100 text-green-700" :
                      c.status === "Submitted" ? "bg-blue-100 text-blue-700" :
                      c.status === "Rejected" ? "bg-red-100 text-red-700" :
                      "bg-slate-100 text-slate-700"
                    )}>
                      {c.status}
                    </span>
                  </TableCell>
                  <TableCell className="max-w-[200px] truncate text-xs text-slate-500">{noteFor(c)}</TableCell>
                </TableRow>
              )
            })}
          </TableBody>
        </Table>
      </div>
      <DataPagination {...pg.paginationProps} />
    </ReportShell>
  )
}
