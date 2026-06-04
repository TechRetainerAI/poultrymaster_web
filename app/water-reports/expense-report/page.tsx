"use client"

/** Expense Report (Prompt 2 §16.15). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listWaterExpenses } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function ExpenseReportPage() {
  const fmtMoney = useFmt()
  const [fromDate, setFromDate] = useState(defaultFrom())
  const [toDate, setToDate] = useState(defaultTo())
  const [rows, setRows] = useState<any[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const all = await listWaterExpenses({ fromDate, toDate })
      setRows(all ?? [])
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => {
    const approved = rows.filter((e: any) => e.status === "Approved")
    const total = approved.reduce((s, e) => s + (e.amount ?? 0), 0)
    const byCat: Record<string, number> = {}
    for (const e of approved) byCat[e.categoryName ?? "Uncategorised"] = (byCat[e.categoryName ?? "Uncategorised"] ?? 0) + (e.amount ?? 0)
    return { count: rows.length, approvedCount: approved.length, total, byCat }
  }, [rows])

  return (
    <ReportShell
      title="Expense Report"
      description="Expenses grouped by category and source. Only Approved expenses count toward totals."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      filterSummary={{ "Status counted": "Approved only" }}
      summary={<>
        <SumTile label="Expense count" value={`${totals.approvedCount} / ${totals.count}`} />
        <SumTile label="Approved total" value={fmtMoney(totals.total)} accent="rose" />
        <SumTile label="Categories" value={String(Object.keys(totals.byCat).length)} />
      </>}
    >
      <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mb-2">By category</h2>
      <Table>
        <TableHeader><TableRow><TableHead>Category</TableHead><TableHead className="text-right">Total</TableHead></TableRow></TableHeader>
        <TableBody>
          {Object.entries(totals.byCat).length === 0 ? (
            <TableRow><TableCell colSpan={2} className="text-slate-500 text-center p-4">No approved expenses.</TableCell></TableRow>
          ) : Object.entries(totals.byCat).sort(([, a], [, b]) => b - a).map(([cat, amt]) => (
            <TableRow key={cat}><TableCell>{cat}</TableCell><TableCell className="text-right tabular-nums">{fmtMoney(amt)}</TableCell></TableRow>
          ))}
        </TableBody>
      </Table>

      <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mt-4 mb-2">Details</h2>
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Category</TableHead>
              <TableHead>Description</TableHead>
              <TableHead>Method</TableHead>
              <TableHead>Source</TableHead>
              <TableHead className="text-right">Amount</TableHead>
              <TableHead>Status</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={7} className="text-slate-500 text-center p-4">No expenses in this period.</TableCell></TableRow>
            ) : rows.map((e: any) => (
              <TableRow key={e.waterExpenseId}>
                <TableCell className="whitespace-nowrap">{(e.expenseDate ?? "").slice(0, 10)}</TableCell>
                <TableCell>{e.categoryName ?? "—"}</TableCell>
                <TableCell className="max-w-[260px] truncate">{e.description ?? "—"}</TableCell>
                <TableCell>{e.paymentMethod ?? "—"}</TableCell>
                <TableCell>{e.linkedWaterProductionBatchId ? "Production batch" : "Manual"}</TableCell>
                <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(e.amount ?? 0)}</TableCell>
                <TableCell>{e.status ?? "—"}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}
