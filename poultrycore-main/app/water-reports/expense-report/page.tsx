"use client"

/** Expense Report (Prompt 2 §16.15). The "By category" rollup is the
 *  authoritative server-side report SP (spWaterReport_ExpenseByCategory) — this
 *  is what the emailed PDF contains. The detail list below is supplementary
 *  (full expense rows for the period, any status). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listWaterExpenses, getWaterExpenseByCategory, type WaterExpenseByCategoryRow } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"
import { defaultReportRange } from "@/lib/date-ranges"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function ExpenseReportPage() {
  const fmtMoney = useFmt()
  const DEFAULT_RANGE = defaultReportRange("last30")
  const [fromDate, setFromDate] = useState(DEFAULT_RANGE.from)
  const [toDate, setToDate] = useState(DEFAULT_RANGE.to)
  const [byCategory, setByCategory] = useState<WaterExpenseByCategoryRow[]>([])
  const [rows, setRows] = useState<any[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const [cats, all] = await Promise.all([
        getWaterExpenseByCategory(fromDate, toDate),
        listWaterExpenses({ fromDate, toDate }),
      ])
      setByCategory(cats ?? [])
      setRows(all ?? [])
    } catch (e: any) { setError(e?.message ?? String(e)) }
    finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => ({
    categoryTotal: byCategory.reduce((s, c) => s + (c.totalAmount ?? 0), 0),
    expenseCount: byCategory.reduce((s, c) => s + (c.expenseCount ?? 0), 0),
    categories: byCategory.length,
  }), [byCategory])

  return (
    <ReportShell
      title="Expense Report"
      description="Expenses grouped by category (authoritative report). The detail list below is supplementary."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      pdf={{
        // PDF uses the authoritative "By category" rollup (the detail list is supplementary).
        title: "Expense Report",
        filename: "water-expense-report",
        summaryLines: [
          `Categories: ${totals.categories}`,
          `Expense count: ${totals.expenseCount.toLocaleString()}`,
          `Total: ${fmtMoney(totals.categoryTotal)}`,
        ],
        columns: [
          { header: "Category" }, { header: "Count", align: "right" }, { header: "Total", align: "right" },
        ],
        rows: byCategory.slice().sort((a, b) => (b.totalAmount ?? 0) - (a.totalAmount ?? 0)).map((c) => [
          c.categoryName, (c.expenseCount ?? 0).toLocaleString(), fmtMoney(c.totalAmount ?? 0),
        ]),
      }}
      summary={<>
        <SumTile label="Categories" value={String(totals.categories)} />
        <SumTile label="Expense count" value={totals.expenseCount.toLocaleString()} />
        <SumTile label="Total" value={fmtMoney(totals.categoryTotal)} accent="rose" />
      </>}
    >
      <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mb-2">By category</h2>
      <Table>
        <TableHeader><TableRow><TableHead>Category</TableHead><TableHead className="text-right">Count</TableHead><TableHead className="text-right">Total</TableHead></TableRow></TableHeader>
        <TableBody>
          {byCategory.length === 0 ? (
            <TableRow><TableCell colSpan={3} className="text-slate-500 text-center p-4">No expenses in this period.</TableCell></TableRow>
          ) : byCategory.slice().sort((a, b) => (b.totalAmount ?? 0) - (a.totalAmount ?? 0)).map((c) => (
            <TableRow key={c.waterExpenseCategoryId}>
              <TableCell>{c.categoryName}</TableCell>
              <TableCell className="text-right tabular-nums">{(c.expenseCount ?? 0).toLocaleString()}</TableCell>
              <TableCell className="text-right tabular-nums whitespace-nowrap">{fmtMoney(c.totalAmount ?? 0)}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>

      <h2 className="text-sm font-semibold uppercase tracking-wider text-slate-600 mt-4 mb-2 print:hidden">Details</h2>
      <div className="overflow-x-auto print:hidden">
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
                <TableCell>{e.linkedWaterProductionBatchId ? "Production" : "Manual"}</TableCell>
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
