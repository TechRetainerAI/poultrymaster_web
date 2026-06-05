"use client"

/** Closing Report (Prompt 2 §16.17). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listWaterDailyClosings } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function ClosingReportPage() {
  const fmtMoney = useFmt()
  const [fromDate, setFromDate] = useState(defaultFrom())
  const [toDate, setToDate] = useState(defaultTo())
  const [rows, setRows] = useState<any[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const all = await listWaterDailyClosings({ fromDate, toDate })
      setRows(all ?? [])
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => {
    const approved = rows.filter(c => c.status === "Approved")
    const income = approved.reduce((s, c) => s + (c.totalIncome ?? 0), 0)
    const expenses = approved.reduce((s, c) => s + (c.totalExpenses ?? 0), 0)
    const cash = approved.reduce((s, c) => s + (c.cashAtHand ?? 0), 0)
    return { total: rows.length, approved: approved.length, income, expenses, cash }
  }, [rows])

  return (
    <ReportShell
      title="Closing Report"
      description="Daily closings with submission + reopen history."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
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
              <TableHead className="text-right">Sold</TableHead>
              <TableHead className="text-right">Income</TableHead>
              <TableHead className="text-right">Expenses</TableHead>
              <TableHead className="text-right">Cash at hand</TableHead>
              <TableHead>Submitted by</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Notes</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={9} className="text-slate-500 text-center p-4">No closings in this period.</TableCell></TableRow>
            ) : rows.map((c: any) => (
              <TableRow key={c.waterDailyClosingId}>
                <TableCell className="whitespace-nowrap">{(c.closingDate ?? "").slice(0, 10)}</TableCell>
                <TableCell className="text-right tabular-nums">{(c.bagsProduced ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums">{(c.bagsSold ?? 0).toLocaleString()}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(c.totalIncome ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(c.totalExpenses ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(c.cashAtHand ?? 0)}</TableCell>
                <TableCell>{c.submittedBy ?? c.createdBy ?? "—"}</TableCell>
                <TableCell>
                  {c.status}
                  {c.supersededByClosingId ? <span className="ml-1 text-xs text-slate-500">→ #{c.supersededByClosingId}</span> : null}
                </TableCell>
                <TableCell className="max-w-[200px] truncate text-xs text-slate-500">
                  {c.reopenReason ? `Reopened: ${c.reopenReason}` : (c.managerNotes ?? "—")}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}
