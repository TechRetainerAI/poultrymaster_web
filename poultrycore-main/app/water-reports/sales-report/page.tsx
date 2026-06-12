"use client"

/** Sales Report (Prompt 2 §16.3). */

import { useEffect, useMemo, useState } from "react"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { ReportShell, SumTile } from "@/components/reports/report-shell"
import { listWaterSales } from "@/lib/api/water"
import { useFmt } from "@/lib/currency"

function isoDate(d: Date) { return d.toISOString().split("T")[0] }
function defaultFrom() { const d = new Date(); d.setDate(d.getDate() - 30); return isoDate(d) }
function defaultTo() { return isoDate(new Date()) }

export default function SalesReportPage() {
  const fmtMoney = useFmt()
  const [fromDate, setFromDate] = useState(defaultFrom())
  const [toDate, setToDate] = useState(defaultTo())
  const [rows, setRows] = useState<any[]>([])
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setBusy(true); setError(null)
    try {
      const all = await listWaterSales()
      // listWaterSales returns the full list; filter client-side.
      const inRange = (all ?? []).filter((s: any) => {
        const d = (s.saleDate ?? "").slice(0, 10)
        return d >= fromDate && d <= toDate
      })
      setRows(inRange)
    } catch (e: any) {
      setError(e?.message ?? String(e))
    } finally { setBusy(false) }
  }

  useEffect(() => { void load() /* eslint-disable-next-line react-hooks/exhaustive-deps */ }, [fromDate, toDate])

  const totals = useMemo(() => {
    const total = rows.reduce((s, r) => s + (r.totalAmount ?? 0), 0)
    const paid = rows.reduce((s, r) => s + (r.amountPaid ?? 0), 0)
    return { total, paid, balance: total - paid }
  }, [rows])

  return (
    <ReportShell
      title="Sales Report"
      description="All sales in the selected period. Totals respect the company's currency settings."
      busy={busy} error={error} onClearError={() => setError(null)}
      fromDate={fromDate} toDate={toDate}
      onFromDateChange={setFromDate} onToDateChange={setToDate}
      onRefresh={load}
      summary={<>
        <SumTile label="Sales count"      value={rows.length.toLocaleString()} />
        <SumTile label="Total amount"     value={fmtMoney(totals.total)} />
        <SumTile label="Amount paid"      value={fmtMoney(totals.paid)}    accent="green" />
        <SumTile label="Outstanding"      value={fmtMoney(totals.balance)} accent="rose" />
      </>}
    >
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Date</TableHead>
              <TableHead>Sale #</TableHead>
              <TableHead>Customer</TableHead>
              <TableHead>Source</TableHead>
              <TableHead className="text-right">Total</TableHead>
              <TableHead className="text-right">Paid</TableHead>
              <TableHead className="text-right">Balance</TableHead>
              <TableHead>Status</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow><TableCell colSpan={8} className="text-slate-500 text-center p-4">No sales in this period.</TableCell></TableRow>
            ) : rows.map((r: any) => (
              <TableRow key={r.waterSaleId}>
                <TableCell className="whitespace-nowrap">{(r.saleDate ?? "").slice(0, 10)}</TableCell>
                <TableCell>{r.waterSaleId}</TableCell>
                <TableCell>{r.customerName ?? r.waterCustomerId ?? "—"}</TableCell>
                <TableCell>{r.sourceType ?? "Manual"}</TableCell>
                <TableCell className="text-right tabular-nums">{fmtMoney(r.totalAmount ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums">{fmtMoney(r.amountPaid ?? 0)}</TableCell>
                <TableCell className="text-right tabular-nums">{fmtMoney((r.totalAmount ?? 0) - (r.amountPaid ?? 0))}</TableCell>
                <TableCell>{r.status ?? "—"}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </ReportShell>
  )
}
